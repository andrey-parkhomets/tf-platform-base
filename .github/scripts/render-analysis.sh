#!/usr/bin/env bash
# Builds the comment for the automatic, analysis-only agent run (agent-analysis.yml). The agent has decided what the change
# needs; nothing was written to the branch. Same rules as render-report.sh: all agent-authored text goes through `clean`.
#   env: MATRIX (detect output, possibly truncated), TOTAL (number of changed directories before the cap), RUN_URL
#   reads .agent/report/<slug>.json
set -euo pipefail

: "${MATRIX:?}"
marker='<!-- tf-test-agent-analysis -->'

clean() { # clean <max chars>
  head -c "${1:-1500}" | sed -e 's/[<>]/ /g' -e 's/@/@​/g' | tr -d '\r'
}

echo "$marker"
echo "## Terraform test agent: analysis"
echo
echo "Automatic, read-only. The agent looked at the change and decided what it needs. **Nothing was written to this branch.**"
echo

count=$(jq 'length' <<<"$MATRIX")
total=${TOTAL:-$count}
suggest=()
valid=0
for i in $(seq 0 $((count - 1))); do
  dir=$(jq -r ".[$i].dir" <<<"$MATRIX"); slug=$(jq -r ".[$i].slug" <<<"$MATRIX")
  report=".agent/report/$slug.json"
  echo "### \`$dir\`"
  echo
  if [[ -f "$report" ]] && jq -e '.decision' "$report" >/dev/null 2>&1; then
    decision=$(jq -r '.decision' "$report")
    case "$decision" in
      tests_needed|tests_need_update|no_change_needed|skipped) ;;
      *) decision=unknown ;;
    esac
    echo "**Decision:** \`$decision\`: $(jq -r '.rationale // ""' "$report" | clean 600)"
    echo
    if [[ $(jq '(.changed_behaviours // []) | length' "$report") -gt 0 ]]; then
      echo "Changed behaviour:"
      jq -r '(.changed_behaviours // [])[:10][] | "- " + .' "$report" | clean 1500
      echo
    fi
    if [[ $(jq '(.affected_callers // []) | length' "$report") -gt 0 ]]; then
      echo "Affected callers: $(jq -r '(.affected_callers // [])[:10] | map("`" + . + "`") | join(", ")' "$report" | clean 400)"
      echo
    fi
    if [[ $(jq '(.test_plan // []) | length' "$report") -gt 0 ]]; then
      echo "Tests it would write:"
      jq -r '(.test_plan // [])[:12][] | "- " + .' "$report" | clean 2000
      echo
    fi
    if [[ $(jq '(.findings // []) | length' "$report") -gt 0 ]]; then
      echo "**Findings for reviewers** (information only):"
      echo
      jq -r '
        (.findings // [])[:20] | sort_by(. as $f | (["high","medium","low","info"] | index($f.severity)) // 9)[] |
        "- **\(.severity // "info")** `\(.file // "")\(if (.line // 0) > 0 then ":" + (.line|tostring) else "" end)`: \(.title // ""). \(.detail // "")"' "$report" | clean 5000
      echo
    fi
    echo "Skills used: $(jq -r '(.skills_used // []) | map("`" + . + "`") | join(", ")' "$report" | clean 300)"
    echo
    [[ $decision == unknown ]] || valid=$((valid + 1))
    case "$decision" in tests_needed|tests_need_update) suggest+=("\`agent coverage $dir\`") ;; esac
  else
    echo "**Decision:** none. No valid report was produced for this directory (see the workflow run)."
    echo
  fi
done

if [[ "$total" -gt "$count" ]]; then
  echo "_$((total - count)) more changed directories were not analysed (limit: $count per run). Use \`agent coverage <dir>\` for those._"
  echo
fi
if [[ ${#suggest[@]} -gt 0 ]]; then
  echo "To have the tests written, verified without secrets and committed to this branch, comment (people with write access, one command per comment): ${suggest[*]}."
elif [[ $valid -eq 0 ]]; then
  echo "The analysis did not complete, so there is no recommendation. \`agent coverage [dir]\` still writes tests on request."
else
  echo "No test work is recommended. \`agent coverage [dir]\` still writes tests on request."
fi
echo
echo "_Analysis uses a model and can be wrong. It never edits infrastructure code; the decisions stay with people._"
[[ -n "${RUN_URL:-}" ]] && echo && echo "[Workflow run]($RUN_URL)"
exit 0
