#!/usr/bin/env bash
# Builds the pull request comment (markdown) from the pipeline outputs.
#
# Reads (all optional except the matrix):
#   $MATRIX                          JSON from detect-modules.sh
#   .agent/report/<slug>.json        agent report per directory
#   .agent/verify/<slug>.json|.log   deterministic verification per directory
#   .agent/checkov.sarif             Checkov results (SARIF, produced by the checkov action)
#   $JOB_RESULTS                     JSON {"lint":"success",...} from the workflow
# Writes the markdown to stdout. All agent-authored text is passed through `clean`:
# stripped of HTML and @mentions, and truncated, because it comes from an LLM that has read untrusted input.
set -euo pipefail

: "${MATRIX:?}"
marker='<!-- tf-test-agent -->'
run_url=${RUN_URL:-}

clean() { # clean <max chars>
  head -c "${1:-1500}" | sed -e 's/[<>]/ /g' -e 's/@/@​/g' | tr -d '\r'
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
    echo "**Decision:** no agent report was produced for this directory. Either the agent step failed, or it was skipped because the agent definition (\`.claude/agents/tf-test-agent.md\`) is not on the base branch yet; the action only loads agent definitions from the base branch."
    echo
  fi

  echo "**Verification** (separate job, no secrets, tests re-run from the patch):"
  echo
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

  patch=".agent/patch/$slug.patch"
  if [[ -s "$patch" ]]; then
    echo "<details><summary>Tests created or updated (verified patch, $(grep -c '^+++ ' "$patch") file(s))</summary>"
    echo
    if [[ -f "$report" ]]; then
      jq -r '(.tests // [])[:10][] | "- `\(.file)`: " + ((.runs // []) | join(", "))' "$report" | clean 1500
      echo
    fi
    echo "Nothing was pushed to this branch. To take the tests: \`gh run download ${RUN_ID:-<run id>} -n tf-tests-$slug\` and \`git apply tests.patch\`."
    echo
    echo "~~~~~~diff"
    grep -v '^~~~' "$patch" | head -c 20000 | tr -d '\r'
    echo
    echo "~~~~~~"
    echo "</details>"
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
