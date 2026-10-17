#!/usr/bin/env bash
# Decides which directories the agent may write tests for automatically, right after the analysis. Pure function of its
# inputs, so it can be tested without GitHub. The analysis reports are model output: they only FILTER the directory list
# that detect-modules.sh produced; nothing from a report is ever used as a path.
#
#   env: MATRIX         detect-modules.sh output (the pull request's changed directories)
#        REPORT_DIR     directory with <slug>.json analysis reports
#        DEFAULT_ON     "0" = automatic writing is switched off for the repository (repository variable AGENT_AUTO_WRITE=0); then only a
#                       pull request with the label "auto-pr-agent" gets it. Anything else, or unset = on for every pull request
#        LABELS         JSON array of the pull request's label names. "no-auto-pr-agent" always wins (opt-out)
#        AGENT_COMMITS  number of commits the agent has already made on this pull request
#        MAX            cap on those commits
#        HEAD_REF       branch name (same pattern the comment commands require)
# Output (stdout): {"matrix":[...], "reason":"..."}  (reason is empty when something was selected or nothing needed tests)
set -euo pipefail

: "${MATRIX:?}" "${REPORT_DIR:?}"
out() { jq -cn --argjson m "$1" --arg r "$2" '{matrix: $m, reason: $r}'; }

# Automatic writing is the default and stays on until somebody switches it off on purpose: for one pull request with the label
# "no-auto-pr-agent" (always wins), or for the whole repository with AGENT_AUTO_WRITE=0 (a pull request can then opt back in with
# the label "auto-pr-agent"). The branch moves under the author when the agent commits, which is why both switches exist.
if jq -e 'index("no-auto-pr-agent")' <<<"${LABELS:-[]}" >/dev/null; then
  out '[]' "automatic writing is switched off for this pull request (label no-auto-pr-agent); remove the label to let the agent commit tests by itself"; exit 0
fi
if [[ "${DEFAULT_ON:-1}" == 0 ]] && ! jq -e 'index("auto-pr-agent")' <<<"${LABELS:-[]}" >/dev/null; then
  out '[]' "automatic writing is switched off for this repository (AGENT_AUTO_WRITE=0); add the label auto-pr-agent to this pull request to let the agent commit tests by itself"; exit 0
fi
if [[ ! "${HEAD_REF:-}" =~ ^[A-Za-z0-9._/-]+$ ]]; then out '[]' "the branch name has characters the agent does not accept"; exit 0; fi
commits=${AGENT_COMMITS:-0}; max=${MAX:-3}
if [[ ! "$commits" =~ ^[0-9]+$ || ! "$max" =~ ^[0-9]+$ ]]; then out '[]' "could not count the agent's commits"; exit 0; fi
if (( commits >= max )); then out '[]' "the agent already made $commits commits on this pull request (limit $max)"; exit 0; fi

selected='[]'
n=$(jq length <<<"$MATRIX")
for i in $(seq 0 $((n - 1))); do
  [[ $n -gt 0 ]] || break
  entry=$(jq -c ".[$i]" <<<"$MATRIX"); slug=$(jq -r .slug <<<"$entry"); dir=$(jq -r .dir <<<"$entry")
  r="$REPORT_DIR/$slug.json"
  [[ -f "$r" ]] || continue
  if jq -e --arg d "$dir" '.dir == $d and (.decision | IN("tests_needed","tests_need_update"))' "$r" >/dev/null 2>&1; then
    selected=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$selected")
  fi
done
# Only as many directories as the cap leaves room for, so a wide change cannot exceed it in one run.
room=$((max - commits))
out "$(jq -c --argjson k "$room" '.[:$k]' <<<"$selected")" ""
