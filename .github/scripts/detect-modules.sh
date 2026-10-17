#!/usr/bin/env bash
# Builds the matrix of Terraform directories (modules/<name>, stacks/<name>) to work on.
#
# Input, either:
#   BASE_SHA, HEAD_SHA   the directories changed between the two commits (`git diff`, no third-party action).
#   DIRS                 an explicit whitespace-separated list, used by `agent coverage <dir>`.
# Output: a JSON array on stdout:
#   [{"dir":"modules/x","kind":"module","slug":"modules-x","has_tests":true}]
# Every directory is validated against a strict pattern before it is used anywhere, because the
# names come from the pull request or from a comment. Paths are only ever handled as data.
set -euo pipefail

if [[ -n "${DIRS:-}" ]]; then
  dirs=$(printf '%s\n' "$DIRS" | tr -s '[:space:]' '\n')
else
  : "${BASE_SHA:?set DIRS, or BASE_SHA and HEAD_SHA}" "${HEAD_SHA:?}"
  # -z keeps unusual file names intact; ignore docs and lock files (they need no tests).
  dirs=$(git diff --name-only -z --diff-filter=ACMRD "$BASE_SHA...$HEAD_SHA" | tr '\0' '\n' | awk -F/ '
    NF >= 3 && ($1 == "modules" || $1 == "stacks") {
      f = $NF
      if (f ~ /\.md$/ || f == ".terraform.lock.hcl") next
      print $1 "/" $2
    }')
fi

out="[]"
while IFS= read -r dir; do
  [[ -z "$dir" ]] && continue
  if [[ ! "$dir" =~ ^(modules|stacks)/[A-Za-z0-9][A-Za-z0-9._-]*$ || "$dir" == *..* ]]; then
    echo "ignoring unexpected path: $dir" >&2; continue
  fi
  [[ -d "$dir" ]] || continue                  # directory deleted in the PR
  kind=${dir%%/*}; kind=${kind%s}              # modules -> module, stacks -> stack
  has_tests=false
  compgen -G "$dir/tests/*.tftest.hcl" >/dev/null && has_tests=true
  out=$(jq -c --arg dir "$dir" --arg kind "$kind" --argjson ht "$has_tests" \
    'if any(.[]; .dir == $dir) then . else . + [{dir: $dir, kind: $kind, slug: ($dir | gsub("/"; "-")), has_tests: $ht}] end' <<<"$out")
done <<<"$dirs"

printf '%s\n' "$out"
