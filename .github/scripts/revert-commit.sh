#!/usr/bin/env bash
# Reverts one commit that the agent made, as a new commit (history is never rewritten).
#   revert-commit.sh <sha>        env: BASE_SHA (pull request base), BOT_EMAIL (author e-mail of the agent's commits)
# Refuses anything that is not a single-parent commit in BASE_SHA..HEAD, authored by the bot, touching only test files.
# Prints the new commit SHA.
set -euo pipefail

sha=${1:?sha}; : "${BASE_SHA:?}" "${BOT_EMAIL:?}"
allowed='^(modules|stacks)/[^/]+/tests/[A-Za-z0-9_.-]+\.(tftest\.hcl|tftest\.json|tfmock\.hcl)$'

[[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "not a commit id: $sha" >&2; exit 1; }
full=$(git rev-parse --verify --quiet "${sha}^{commit}") || { echo "unknown commit: $sha" >&2; exit 1; }
git rev-list "$BASE_SHA..HEAD" | grep -qx "$full" || { echo "$sha is not a commit of this pull request" >&2; exit 1; }
[[ $(git show -s --format=%ae "$full") == "$BOT_EMAIL" ]] || { echo "$sha was not made by the agent; revert it yourself" >&2; exit 1; }
[[ $(git show -s --format=%P "$full" | wc -w) -eq 1 ]] || { echo "$sha is a merge commit" >&2; exit 1; }
bad=$(git diff-tree --no-commit-id --name-only -r -z "$full" | tr '\0' '\n' | grep -Ev "$allowed" || true)
[[ -z "$bad" ]] || { echo "$sha touches files outside tests/: $bad" >&2; exit 1; }

if ! git revert --no-edit "$full" >/dev/null 2>&1; then
  git revert --abort >/dev/null 2>&1 || true
  echo "reverting $sha conflicts with later changes; revert it by hand" >&2
  exit 1
fi
git rev-parse HEAD
