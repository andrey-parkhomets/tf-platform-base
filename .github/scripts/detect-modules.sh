#!/usr/bin/env bash
# Builds the matrix of changed Terraform directories (modules/<name>, stacks/<name>).
#
# Input, either:
#   CHANGED_DIRS   output of tj-actions/changed-files with dir_names=true, dir_names_max_depth=2
#                  (a JSON array, or whitespace-separated). This is the normal path.
#   BASE_SHA, HEAD_SHA   fallback without third-party actions: derives the same list from `git diff`.
# Output: a JSON array on stdout:
#   [{"dir":"modules/x","kind":"module","slug":"modules-x","has_tests":true}]
# Every directory is validated against a strict pattern before it is used anywhere, because the
# names come from the pull request. Paths are only ever handled as data.
set -euo pipefail

if [[ -n "${CHANGED_DIRS:-}" ]]; then
  CHANGED_DIRS=${CHANGED_DIRS//\\\"/\"}      # tolerate an escaped JSON string (escape_json=true)
  if jq -e 'type == "array"' <<<"$CHANGED_DIRS" >/dev/null 2>&1; then
    dirs=$(jq -r '.[]' <<<"$CHANGED_DIRS")
  else
    dirs=$(printf '%s\n' "$CHANGED_DIRS" | tr ' ' '\n')
  fi
else
  : "${BASE_SHA:?set CHANGED_DIRS, or BASE_SHA and HEAD_SHA}" "${HEAD_SHA:?}"
  dirs=$(git diff --name-only "$BASE_SHA...$HEAD_SHA" | awk -F/ '
    NF >= 3 && ($1 == "modules" || $1 == "stacks") {
      f = $NF
      if (f ~ /\.md$/ || f == ".terraform.lock.hcl") next   # same ignore list as the workflow
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
