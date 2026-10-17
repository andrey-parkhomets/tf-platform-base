#!/usr/bin/env bash
# Fails if the working tree contains any change outside the paths the agent may write.
# Allowed: (modules|stacks)/<name>/tests/<file>.tftest.hcl|.tfmock.hcl|.tftest.json
#          (regular files only, no symlinks, <= 200 KiB each)
# Also allowed: the .agent/ output directory (git-ignored, so it never shows here).
set -euo pipefail

allowed='^(modules|stacks)/[^/]+/tests/[A-Za-z0-9_.-]+\.(tftest\.hcl|tftest\.json|tfmock\.hcl)$'
max_bytes=204800
bad=0

while IFS= read -r -d '' entry; do
  path=${entry:3}
  # rename entries carry a second NUL-separated path, handled by the read below
  if [[ ! "$path" =~ $allowed ]]; then
    echo "::error::agent changed a path outside the allowed test locations: $path"
    bad=1
    continue
  fi
  if [[ -L "$path" ]]; then
    echo "::error::symlink not allowed: $path"; bad=1; continue
  fi
  if [[ -f "$path" ]] && (( $(wc -c <"$path") > max_bytes )); then
    echo "::error::test file too large: $path"; bad=1
  fi
done < <(git status --porcelain=v1 -z --untracked-files=all)

exit "$bad"
