#!/usr/bin/env bash
# Builds the comment that every pull request with Terraform changes gets from the pull_request workflow. No model is
# involved: it shows the deterministic results for the changed directories and tells people how to ask the agent.
#   env: MATRIX (detect-modules.sh output), JOB_RESULTS ({"lint":"success",...}), RUN_URL
#   reads .agent/verify/<slug>.json
# Later this is the place for rules such as "require `agent coverage` for modules without tests".
set -euo pipefail

: "${MATRIX:?}"
marker='<!-- tf-test-agent -->'
icon() { case "$1" in pass|success|true) echo "✅";; none|skipped) echo "➖";; *) echo "❌";; esac; }

echo "$marker"
echo "## Terraform test agent"
echo
if [[ -n "${JOB_RESULTS:-}" ]]; then
  printf 'Pipeline: '
  jq -r 'to_entries | map("\(.key) \(if .value=="success" then "✅" elif .value=="skipped" then "➖" else "❌" end)") | join(" · ")' <<<"$JOB_RESULTS"
  echo
fi

count=$(jq 'length' <<<"$MATRIX")
if [[ "$count" -eq 0 ]]; then
  echo "No Terraform module or stack changed in a way that needs tests."
else
  echo "| directory | tests | fmt | validate | test | mutation check |"
  echo "|---|---|---|---|---|---|"
  missing=()
  for i in $(seq 0 $((count - 1))); do
    dir=$(jq -r ".[$i].dir" <<<"$MATRIX"); slug=$(jq -r ".[$i].slug" <<<"$MATRIX")
    has=$(jq -r ".[$i].has_tests" <<<"$MATRIX")
    v=".agent/verify/$slug.json"
    if [[ -f "$v" ]]; then
      r() { jq -r --arg k "$1" '.results[$k] // "none"' "$v"; }
      m=$(jq -r 'if (.mutation.total // 0) > 0 then "\(.mutation.total - .mutation.survived) of \(.mutation.total) caught" else "-" end' "$v")
      echo "| \`$dir\` | $([ "$has" = true ] && echo yes || echo "**none**") | $(icon "$(r fmt)") | $(icon "$(r validate)") | $(icon "$(r test)") $(jq -r '.summary // ""' "$v" | head -c 60) | $m |"
    else
      echo "| \`$dir\` | $([ "$has" = true ] && echo yes || echo "**none**") | ➖ | ➖ | ➖ | not run |"
    fi
    [[ "$has" = true ]] || missing+=("\`$dir\`")
  done
  echo
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Without tests: ${missing[*]}."
    echo
  fi
  cat <<'TXT'
The agent's automatic analysis (its own comment on this pull request) writes nothing to the branch. To have it write tests, ask for it in a comment on this pull request (people with write access; the whole comment must be just the command):

| comment | what happens |
|---|---|
| `agent coverage` | writes or updates tests for the directories changed here, checks them in a job without secrets, and commits the verified tests to this branch |
| `agent coverage modules/<name>` | the same for one directory, changed or not |
| `agent check comments` | reads the unresolved review threads on the agent's test files, changes the tests where it agrees, replies and resolves those threads |
| `agent remove <sha>` | reverts one commit made by the agent, as a new commit |
TXT
  echo
fi
[[ -n "${RUN_URL:-}" ]] && echo "[Workflow run]($RUN_URL)"
exit 0
