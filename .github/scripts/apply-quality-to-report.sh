#!/usr/bin/env bash
# The analysis cannot run Terraform, but it can know that the existing tests already fail the static quality check
# (check-test-quality.sh). If they do, "no change needed" is wrong, whatever the model said: the decision becomes
# `tests_need_update` and the first error leads the rationale. A pure function of two files, so it is tested without GitHub.
#   usage: apply-quality-to-report.sh <report.json> <quality.txt>     (prints the report to stdout)
#   quality.txt: stdout of check-test-quality.sh (`::error ...::message` lines), empty when the check passed
set -euo pipefail
report=${1:?report.json}; quality=${2:?quality.txt}

errors=$(grep -E '^::error' "$quality" 2>/dev/null || true)
decision=$(jq -r '.decision // ""' "$report")
if [[ -z "$errors" ]] || [[ "$decision" != no_change_needed && "$decision" != skipped ]]; then
  cat "$report"; exit 0
fi
# `::error file=<f>::<message>` -> `<message>`; one line, short (the text contains names from the pull request).
first=$(head -1 <<<"$errors" | sed -e 's/^::error[^:]*::\(.*\)$/\1/' -e 's/^::error::\(.*\)$/\1/' | tr -d '\r' | head -c 300)
count=$(wc -l <<<"$errors" | tr -d ' ')
jq --arg first "$first" --arg count "$count" --arg old "$decision" '
  .decision = "tests_need_update"
  | .rationale = "The static test-quality check fails on the existing tests (" + $count + " error(s)): " + $first + ". "
      + "The change itself was judged \"" + $old + "\", but the tests must be fixed before they can be trusted. " + (.rationale // "")' "$report"
