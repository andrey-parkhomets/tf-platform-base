#!/usr/bin/env bash
# Builds the working tree for one evaluation case (a standalone clone): the pinned base commit of this repository, the case's patch committed on top (that
# commit is the "head" of the pretend pull request), then the agent definition under test (overlay-agent.sh) as a local baseline commit,
# exactly as the production workflows do. Prints one JSON line describing it.
#
#   usage: prepare-case.sh <case dir> <working tree> [--for analysis|writer]
#   env:   EVAL_REPO       git repository with the full history (default: the repository this script is in)
#          AGENT_REF_DIR   checkout of the branch under test, used as DATA for .claude/ (default: EVAL_REPO)
#          EVAL_SCRIPTS    directory with the trusted scripts (default: <EVAL_REPO>/.github/scripts)
#   With --for analysis the inputs the production analysis job prepares are created too: .agent/quality.txt (the static test-quality
#   check) and, when the case ships Checkov fixtures, the scoped .agent/checkov.sarif.
set -euo pipefail

case_dir=${1:?case directory}; wt=${2:?working tree}; shift 2
for_stage=""
if [[ "${1:-}" == --for ]]; then for_stage=${2:?analysis or writer}; fi
here=$(cd "$(dirname "$0")" && pwd)
repo=${EVAL_REPO:-$(cd "$here/../.." && pwd)}
ref=${AGENT_REF_DIR:-$repo}
scripts=${EVAL_SCRIPTS:-$repo/.github/scripts}

die() { echo "prepare-case: $*" >&2; exit 2; }
jget() { jq -er "$1" "$case_dir/case.json" 2>/dev/null || die "case.json: missing $1"; }

id=$(jget .id); base=$(jget .base); patch=$(jget .patch); dir=$(jget .dir)
[[ "$id" =~ ^[a-z0-9][a-z0-9-]{0,60}$ ]]                                      || die "bad case id"
[[ "$base" =~ ^[0-9a-f]{40}$ ]]                                               || die "base must be a full commit SHA"
[[ "$patch" =~ ^[A-Za-z0-9._-]+\.patch$ && -f "$case_dir/$patch" ]]          || die "bad or missing patch"
[[ "$dir" =~ ^(modules|stacks)/[A-Za-z0-9][A-Za-z0-9._-]*$ && "$dir" != *..* ]] || die "bad directory"
git -C "$repo" cat-file -e "$base^{commit}" 2>/dev/null                       || die "base commit $base is not in the repository (fetch the full history)"

[[ ! -e "$wt" ]] || die "working tree $wt already exists"
created=0
# a tree that could not be completed is not left behind
# shellcheck disable=SC2154  # rc is assigned inside the trap
trap 'rc=$?; if [[ $created -eq 1 && $rc -ne 0 ]]; then rm -rf -- "$wt"; fi' EXIT
# A standalone clone, not a git worktree: in a worktree `.git` is a file, and the CLI (which records its placeholder files in
# .git/info/exclude) could not write there. Production has an ordinary checkout; this gives the agent the same layout. --shared borrows
# the objects of the source repository, so it is fast and small.
git clone -q --shared --no-checkout "$repo" "$wt"
created=1
git -C "$wt" checkout -q --detach "$base"
# the harness never signs: its commits are throw-away, and a global commit.gpgsign=true must not reach them
g() { git -C "$wt" -c user.name=eval -c user.email=eval@localhost -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
g apply --index "$(cd "$case_dir" && pwd)/$patch" || die "the patch does not apply to $base"
g commit -q -m "case $id"
head=$(g rev-parse HEAD)

"$here/overlay-agent.sh" "$ref" "$wt"
g add -A -- .claude
g diff --cached --quiet || g commit -q -m "baseline: agent definition under test"

mkdir -p "$wt/.agent/report"
if [[ "$for_stage" == analysis ]]; then
  (cd "$wt" && "$scripts/check-test-quality.sh" "$dir" >.agent/quality.txt 2>&1) || true
  sarif=$(jq -r '.checkov.head // empty' "$case_dir/case.json"); sbase=$(jq -r '.checkov.base // empty' "$case_dir/case.json")
  if [[ -n "$sarif" ]]; then
    [[ "$sarif" =~ ^[A-Za-z0-9._-]+\.sarif$ && -f "$case_dir/$sarif" ]] || die "bad Checkov fixture"
    basearg=-; if [[ -n "$sbase" ]]; then [[ "$sbase" =~ ^[A-Za-z0-9._-]+\.sarif$ && -f "$case_dir/$sbase" ]] || die "bad Checkov base fixture"; basearg="$case_dir/$sbase"; fi
    "$scripts/scope-sarif.sh" "$case_dir/$sarif" "$basearg" "$dir" >"$wt/.agent/checkov.sarif" || rm -f "$wt/.agent/checkov.sarif"
  fi
fi

jq -nc --arg wt "$wt" --arg base "$base" --arg head "$head" --arg dir "$dir" --arg slug "${dir//\//-}" --arg id "$id" \
  '{id: $id, workdir: $wt, base: $base, head: $head, dir: $dir, slug: $slug}'
