#!/usr/bin/env bash
# A stand-in for the Claude Code CLI, for tests. It records how it was called and behaves as scripted by environment variables, so the
# whole run/score pipeline can be tested without a model and without spending anything.
#   STUB_LOG       file that gets the arguments, the working directory and the agent file seen there
#   STUB_COST      total_cost_usd to report (default 0.01)
#   STUB_REPORT    a JSON file to write as the report (.agent/report/<slug>.json)
#   STUB_TESTS     a file to write as <dir>/tests/main.tftest.hcl
#   STUB_STRAY     a path to write outside tests/ (to exercise the path guard)
#   STUB_FAIL=1    exit non-zero without a result
set -uo pipefail
prompt=""; model=""; agent=""; allowed=""; turns=""
while [[ $# -gt 0 ]]; do
  case "$1" in -p) prompt=$2; shift 2 ;; --model) model=$2; shift 2 ;; --agent) agent=$2; shift 2 ;; --allowedTools) allowed=$2; shift 2 ;; --max-turns) turns=$2; shift 2 ;; *) shift ;; esac
done
{
  echo "model=$model agent=$agent turns=$turns"
  echo "allowed=$allowed"
  echo "cwd=$(pwd -P)"
  echo "agent_file_head=$(head -2 .claude/agents/tf-test-agent.md 2>/dev/null | tail -1)"
  echo "prompt<<"; echo "$prompt"; echo ">>"
} >>"${STUB_LOG:-/dev/null}"
[[ "${STUB_FAIL:-0}" == 1 ]] && exit 1
# shellcheck disable=SC2016  # the backticks are literal characters of the prompt
slug=$(sed -n 's/.*(slug `\([^`]*\)`).*/\1/p' <<<"$prompt" | head -1)
# shellcheck disable=SC2016
dir=$(sed -n 's/.*for the directory `\([^`]*\)`.*/\1/p' <<<"$prompt" | head -1)
mkdir -p .agent/report
[[ -n "${STUB_REPORT:-}" ]] && cp "$STUB_REPORT" ".agent/report/$slug.json"
# shellcheck disable=SC2016  # the backticks are literal characters of the prompt
# like the real agent, only the write modes may produce test files
if [[ -n "${STUB_TESTS:-}" && "$prompt" == *"mode \`analyze\`"* ]]; then :; elif [[ -n "${STUB_TESTS:-}" ]]; then mkdir -p "$dir/tests"; cp "$STUB_TESTS" "$dir/tests/main.tftest.hcl"; fi
if [[ -n "${STUB_STRAY:-}" ]]; then mkdir -p "$(dirname "$STUB_STRAY")"; echo x >"$STUB_STRAY"; fi
jq -nc --arg m "$model" --argjson cost "${STUB_COST:-0.01}" \
  '{type: "result", subtype: "success", is_error: false, num_turns: 7, duration_ms: 1234, total_cost_usd: $cost, permission_denials: [], modelUsage: {($m): {}}, result: "done"}'
