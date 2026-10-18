#!/usr/bin/env bash
# Runs the deterministic checks for one directory, outside the LLM:
#   the static test-quality check, fmt -check, init (lock file must already satisfy providers), validate, test, mutation check.
# Writes .agent/verify/<slug>.json and .agent/verify/<slug>.log. Exit code is 0 only if all pass.
# Needs no credentials. Must run in a job that has no secrets.
set -uo pipefail

dir=${1:?directory}
slug=${dir//\//-}
out=.agent/verify
mkdir -p "$out"
log="$out/$slug.log"
: >"$log"

run() { # run <name> <cmd...>; records pass/fail in $results
  local name=$1; shift
  { echo "### $name: $*"; } >>"$log"
  if (cd "$dir" && "$@") >>"$log" 2>&1; then
    results=$(jq -c --arg n "$name" '. + {($n): "pass"}' <<<"$results")
    return 0
  fi
  results=$(jq -c --arg n "$name" '. + {($n): "fail"}' <<<"$results")
  return 1
}

results='{}'
ok=0
# The static test-quality check first (no Terraform): a test that cannot fail, or that pins an insecure default, is rejected here
# and its message is in the log that the agent reads in the fix round.
{ echo "### quality: check-test-quality.sh $dir"; } >>"$log"
if "$(dirname "$0")/check-test-quality.sh" "$dir" >>"$log" 2>&1; then
  results=$(jq -c '. + {quality: "pass"}' <<<"$results")
else
  results=$(jq -c '. + {quality: "fail"}' <<<"$results"); ok=1
fi
run fmt terraform fmt -check -recursive -diff || ok=1
if run init terraform init -backend=false -input=false -lockfile=readonly -no-color; then
  run validate terraform validate -no-color || ok=1
  if compgen -G "$dir/tests/*.tftest.hcl" >/dev/null; then
    run test terraform test -no-color || ok=1
    # `terraform test` exits 0 when no run block executed ("Success! 0 passed, 0 failed."): that verifies nothing.
    if [[ $(jq -r .test <<<"$results") == pass ]] && ! tail -5 "$log" | grep -qE '^Success[!a-z ]* [1-9][0-9]* passed'; then
      echo "### test: no run block passed, so nothing was verified" >>"$log"
      results=$(jq -c '. + {test: "fail"}' <<<"$results"); ok=1
    fi
  else
    results=$(jq -c '. + {test: "none"}' <<<"$results")
  fi
else
  ok=1
fi

# Heuristic mutation check (informational): do the tests notice simple breakages of the module?
mutation='{}'
if [[ $ok -eq 0 ]] && compgen -G "$dir/tests/*.tftest.hcl" >/dev/null; then
  mout=$("$(dirname "$0")/mutation-check.sh" "$dir" 2>&1 || true)
  echo "### mutation check" >>"$log"; echo "$mout" >>"$log"
  total=$(sed -n 's/^mutants: \([0-9]*\), survived: \([0-9]*\)$/\1/p' <<<"$mout")
  survived=$(sed -n 's/^mutants: \([0-9]*\), survived: \([0-9]*\)$/\2/p' <<<"$mout")
  survivors=$(grep '^SURVIVED: ' <<<"$mout" | sed 's/^SURVIVED: //' | jq -R . | jq -sc .)
  mutation=$(jq -nc --argjson t "${total:-0}" --argjson s "${survived:-0}" --argjson l "${survivors:-[]}" '{total: $t, survived: $s, survivors: $l}')
fi

# "Success! 5 passed, 0 failed." comes from `terraform test`
summary=$(grep -E '^(Success|Fail)[!a-z ]*[0-9]+ passed, [0-9]+ failed' "$log" | tail -1 || true)
jq -n --arg dir "$dir" --argjson results "$results" --arg summary "$summary" --argjson mutation "$mutation" --argjson ok "$([ $ok -eq 0 ] && echo true || echo false)" \
  --argjson round "${ROUND:-1}" \
  '{dir: $dir, round: $round, ok: $ok, results: $results, summary: $summary, mutation: $mutation}' >"$out/$slug.json"

exit "$ok"
