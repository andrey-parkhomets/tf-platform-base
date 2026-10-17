#!/usr/bin/env bash
# Parses a pull request comment into an agent command. The comment is untrusted input, so the grammar is
# strict: the whole comment must be exactly one command on one line (a quoted or pasted command inside a longer
# text does not trigger anything).
#
#   agent coverage                    tests for the directories changed in the pull request
#   agent coverage <modules|stacks>/<name>   tests for one directory, changed or not
#   agent check comments              handle the unresolved review threads on test files
#   agent remove <sha>                revert one commit made by the agent (7-40 hex characters)
#
# Input: $COMMENT_BODY. Output on stdout: `command=<name>` and `arg=<value>` lines.
# Exit 0 = command, 3 = not a command (silent), never anything else on purpose.
set -euo pipefail

body=${COMMENT_BODY-}
body=$(printf '%s' "$body" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
[[ -n "$body" && "$body" != *$'\n'* ]] || exit 3

dir_re='(modules|stacks)/[A-Za-z0-9][A-Za-z0-9._-]*'
if [[ "$body" =~ ^agent\ coverage$ ]]; then
  echo "command=coverage"; echo "arg="
elif [[ "$body" =~ ^agent\ coverage\ ($dir_re)$ && "$body" != *..* ]]; then
  echo "command=coverage"; echo "arg=${BASH_REMATCH[1]}"
elif [[ "$body" =~ ^agent\ check\ comments$ ]]; then
  echo "command=check_comments"; echo "arg="
elif [[ "$body" =~ ^agent\ remove\ ([0-9a-f]{7,40})$ ]]; then
  echo "command=remove"; echo "arg=${BASH_REMATCH[1]}"
else
  exit 3
fi
