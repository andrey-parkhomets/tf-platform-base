#!/usr/bin/env bash
# Applies a verified patch to the checked-out branch and commits it. Runs in the job that holds the write
# token, which never runs Terraform and never runs the model.
#   commit-patch.sh <patch> <message-file>
# Identity comes from GIT_AUTHOR_* / GIT_COMMITTER_* in the environment. Prints the new commit SHA.
# The paths are checked again here, whatever the earlier jobs said.
set -euo pipefail

patch=${1:?patch}; msg=${2:?message file}
allowed='^(modules|stacks)/[^/]+/tests/[A-Za-z0-9_.-]+\.(tftest\.hcl|tftest\.json|tfmock\.hcl)$'

[[ -s "$patch" ]] || { echo "empty patch" >&2; exit 2; }
if ! git diff --quiet || ! git diff --cached --quiet; then echo "working tree is not clean" >&2; exit 2; fi

paths=$(git apply --numstat -z "$patch" | tr '\0' '\n' | cut -f3)
[[ -n "$paths" ]] || { echo "patch changes nothing" >&2; exit 2; }
bad=$(grep -Ev "$allowed" <<<"$paths" || true)
[[ -z "$bad" ]] || { echo "patch touches paths outside tests/: $bad" >&2; exit 1; }

git apply --check "$patch"
git apply "$patch"
while IFS= read -r p; do
  [[ -L "$p" ]] && { echo "symlink not allowed: $p" >&2; exit 1; }
  git add -A -- "$p"
done <<<"$paths"
git commit -q -F "$msg"
git rev-parse HEAD
