#!/usr/bin/env bash
# Builds the pull request comment (markdown) from the pipeline outputs.
#
# Reads (all optional except the matrix):
#   $MATRIX                          JSON from detect-modules.sh
#   .agent/report/<slug>.json        agent report per directory
#   .agent/verify/<slug>.json|.log   deterministic verification per directory
#   .agent/checkov.sarif             Checkov results (SARIF, produced by the checkov action)
#   $JOB_RESULTS                     JSON {"lint":"success",...} from the workflow
# Env: REPO, SERVER_URL (links), RUN_URL. Reads .agent/commits.json ([{dir, sha}]) for the commits the pipeline made.
# Writes the markdown to stdout. All agent-authored text is passed through `clean`:
# stripped of HTML and @mentions, and truncated, because it comes from an LLM that has read untrusted input.
set -euo pipefail

: "${MATRIX:?}"
marker="<!-- tf-test-agent-run ${RUN_ID:-} -->"
run_url=${RUN_URL:-}

clean() { # clean <max chars>
  head -c "${1:-1500}" | sed -e 's/</‹/g' -e 's/>/›/g' -e 's/@/@​/g' | tr -d '\r'
}
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
  echo "No Terraform module or stack changed in a way that needs tests. Nothing to do."
  [[ -n "$run_url" ]] && echo && echo "[Workflow run]($run_url)"
  exit 0
fi

for i in $(seq 0 $((count - 1))); do
  dir=$(jq -r ".[$i].dir" <<<"$MATRIX")
  slug=$(jq -r ".[$i].slug" <<<"$MATRIX")
  report=".agent/report/$slug.json"
  verify=".agent/verify/$slug.json"
  echo "### \`$dir\`"
  echo

  if [[ -f "$report" ]] && jq -e '.decision' "$report" >/dev/null 2>&1; then
    decision=$(jq -r '.decision // "unknown"' "$report" | clean 40)
    echo "**Decision:** \`$decision\` — $(jq -r '.rationale // ""' "$report" | clean 600)"
    echo
    if [[ $(jq '(.changed_behaviours // []) | length' "$report") -gt 0 ]]; then
      echo "Changed behaviour considered:"
      jq -r '(.changed_behaviours // [])[:10][] | "- " + .' "$report" | clean 1500
      echo
    fi
    echo "Skills used: $(jq -r '(.skills_used // []) | map("`" + . + "`") | join(", ")' "$report" | clean 400)"
    echo
  else
    agent_result=$(jq -r '.agent // "unknown"' <<<"${JOB_RESULTS:-{\}}")
    skipped=$(jq -r '.skipped // empty' "$report" 2>/dev/null || true)
    if [[ $skipped == agent_definition_not_on_base ]]; then
      echo "**Decision:** none. The agent was skipped: the agent definition (\`.claude/agents/tf-test-agent.md\`) is not on the base branch yet, and the action only loads agent definitions from the base branch."
    elif [[ $agent_result == failure ]]; then
      echo "**Decision:** none. The agent step failed for this run (see the workflow run for the reason, for example a turn limit). Tests it had already written are still verified below."
    else
      echo "**Decision:** no agent report was produced for this directory (the agent runs only for same-repository pull requests)."
    fi
    echo
  fi

  echo "**Verification** (separate job, no secrets, tests re-run from the patch):"
  echo
  r1=".agent/verify/$slug.round1.json"
  if [[ -f "$r1" ]]; then
    failed1=$(jq -r '[.results | to_entries[] | select(.value == "fail") | .key] | join(", ")' "$r1" | clean 120)
    if [[ "$(jq -r '.ok // false' "$verify" 2>/dev/null)" == true ]]; then
      echo "_Round 1 failed verification (${failed1:-unknown}); the agent read the log and fixed the tests in a second round, which is the result below._"
    else
      echo "_Round 1 failed verification (${failed1:-unknown}); the agent read the log in a second round, which failed as well (result below). Nothing is committed from a failed verification._"
    fi
    echo
  fi
  if [[ -f "$verify" ]]; then
    echo "| check | result |"; echo "|---|---|"
    jq -r '.results | to_entries[] | "\(.key)|\(.value)"' "$verify" | while IFS='|' read -r k v; do
      echo "| $k | $(icon "$v") $v |"
    done
    s=$(jq -r '.summary' "$verify")
    [[ -n "$s" ]] && echo && echo "\`$s\`"
    if [[ $(jq '(.mutation.total // 0)' "$verify") -gt 0 ]]; then
      echo
      echo "Mutation check (heuristic, simple breakages of the module code): $(jq -r '.mutation.total - .mutation.survived' "$verify") of $(jq -r '.mutation.total' "$verify") caught."
      if [[ $(jq '.mutation.survived' "$verify") -gt 0 ]]; then
        echo "Not caught by the tests:"
        jq -r '.mutation.survivors[:8][] | "- " + .' "$verify"
      fi
    fi
  else
    echo "_not run_"
  fi
  echo

  commit=$(jq -r --arg d "$dir" '[.[] | select(.dir == $d)][0].sha // empty' .agent/commits.json 2>/dev/null || true)
  if [[ -n "$commit" && "$commit" =~ ^[0-9a-f]{7,40}$ ]]; then
    echo "**Committed to this branch:** [\`${commit:0:7}\`](${SERVER_URL:-https://github.com}/${REPO:-}/commit/$commit) (verified tests only; the checks on the pull request run on it as on any other commit)."
    echo
    if [[ -f "$report" ]]; then
      jq -r '(.tests // [])[:10][] | "- `\(.file)`: " + ((.runs // []) | join(", "))' "$report" | clean 1500
      echo
    fi
    echo "Review it like any commit and comment on lines of the test file. \`agent check comments\` asks me to act on unresolved threads, \`agent remove ${commit:0:7}\` reverts it."
    echo
  elif [[ -f "$report" ]]; then
    echo "**Committed to this branch:** nothing."
    echo
  fi

  if [[ -f "$report" && $(jq '(.threads // []) | length' "$report" 2>/dev/null || echo 0) -gt 0 ]]; then
    echo "Review threads:"
    jq -r '(.threads // [])[:20][] | "- \(.outcome // "?"): \(.reply // "")"' "$report" | clean 2000
    echo
  fi

  if [[ -f "$report" ]]; then
    n=$(jq '(.findings // []) | length' "$report")
    if [[ "$n" -gt 0 ]]; then
      echo "**Findings for reviewers** (information only, no infrastructure code was changed):"
      echo
      jq -r '
        (.findings // [])[:20] | sort_by(. as $f | (["high","medium","low","info"] | index($f.severity)) // 9)[] |
        "- **\(.severity // "info")** (\(.source // "agent")) `\(.file // "")\(if (.line // 0) > 0 then ":" + (.line|tostring) else "" end)` — \(.title // ""): \(.detail // "")"' "$report" | clean 6000
      echo
    fi
    if [[ $(jq '(.not_covered // []) | length' "$report") -gt 0 ]]; then
      echo "<details><summary>What these tests do not show</summary>"
      echo
      jq -r '.not_covered[:8][] | "- " + .' "$report" | clean 1500
      echo
      echo "</details>"
      echo
    fi
  fi
done

if [[ -f .agent/checkov.sarif ]]; then
  fails=$(jq '[.runs[]?.results[]?] | length' .agent/checkov.sarif 2>/dev/null || echo "?")
  echo "Checkov (automated scanner, whole repository): $fails failed checks. Triage is in the findings above; raw SARIF is in the workflow run."
  echo
fi
[[ -n "$run_url" ]] && echo "[Workflow run]($run_url)"
