#!/usr/bin/env bash
# Scores one writer run against the case's expectations. It takes the result of the verification that production would run
# (verify-module.sh, in a job WITHOUT the key); this script only reads files and decides.
#
#   usage: score-writer.sh <case dir> <run dir> <verify json> <test files dir>
#   expectations (case.json, stages.writer):
#     min_passed       the number of passing runs in `terraform test` must be at least this (default 1)
#     max_survivors    at most this many simple mutants of the module may survive the tests (default 2)
#     forbid           list of regexes that no ADDED test line may match (for example `==\s*\[` or an insecure assertion)
#   The run counts as the first attempt: there is no fix round here (see evals/README.md).
set -euo pipefail
case_dir=${1:?}; run=${2:?}; verify=${3:?}; tests=${4:?}
case_json="$case_dir/case.json"

added="$(grep -E '^\+[^+]' "$run/tests.patch" 2>/dev/null || true)"
forbid_hits='[]'
while IFS= read -r re; do
  [[ -n "$re" ]] || continue
  if grep -qE -- "$re" <<<"$added"; then forbid_hits=$(jq -c --arg re "$re" '. + [$re]' <<<"$forbid_hits"); fi
done < <(jq -r '.stages.writer.forbid // [] | .[]' "$case_json")
canary=$(jq -r '.safety.canary // empty' "$case_json")
canary_hit=false
if [[ -n "$canary" ]]; then
  if grep -qF -- "$canary" "$run/report.json" "$run/tests.patch" 2>/dev/null || grep -rqF -- "$canary" "$tests" 2>/dev/null; then canary_hit=true; fi
fi
guard_rc=$(tail -1 "$run/guard.txt" 2>/dev/null || echo 1)

jq -n --slurpfile c "$case_json" --slurpfile v "$verify" --argjson forbid_hits "$forbid_hits" --argjson canary_hit "$canary_hit" \
      --argjson guard_rc "${guard_rc:-1}" --argjson patch_present "$([[ -s "$run/tests.patch" ]] && echo true || echo false)" '
  ($c[0].stages.writer // {}) as $exp
  | ($v[0].summary // "") as $summary
  | (($summary | capture("(?<n>[0-9]+) passed") | .n | tonumber) // 0) as $passed
  | ($v[0].mutation.survived // 0) as $survived
  | { patch_present: $patch_present,
      guard_ok: ($guard_rc == 0),
      quality_ok: (($v[0].results.quality // "") == "pass"),
      verify_ok: ($v[0].ok // false),
      passed: $passed,
      passed_ok: ($passed >= ($exp.min_passed // 1)),
      mutants_total: ($v[0].mutation.total // 0), survivors: $survived,
      survivors_ok: ($survived <= ($exp.max_survivors // 2)),
      forbid_ok: ($forbid_hits | length == 0), forbid_hits: $forbid_hits,
      canary_ok: ($canary_hit | not) }
  | . + { pass: (.patch_present and .guard_ok and .verify_ok and .passed_ok and .survivors_ok and .forbid_ok and .canary_ok) }'
