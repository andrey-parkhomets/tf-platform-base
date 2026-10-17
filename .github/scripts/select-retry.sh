#!/usr/bin/env bash
# Which directories get the one fix round? Those whose verification failed in a way that editing the TEST files can fix:
# the static quality check, `terraform validate`, or `terraform test`. A failed `init` (providers, network) or `fmt` on a
# non-test file is not something the agent can repair, so it is not retried. A directory without a result file (the verify job
# did not run) is not retried either: there is no log to learn from.
#   env: MATRIX  the round's directory list (detect-modules.sh format)
#        DL      directory with the downloaded verify artifacts, flat: <DL>/<slug>.json
#   stdout: the JSON array of directories to retry
set -euo pipefail
: "${MATRIX:?}" "${DL:?}"
failed='[]'
n=$(jq length <<<"$MATRIX")
for i in $(seq 0 $((n - 1))); do
  [[ $n -gt 0 ]] || break
  entry=$(jq -c ".[$i]" <<<"$MATRIX"); slug=$(jq -r .slug <<<"$entry")
  [[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
  f="$DL/$slug.json"
  [[ -f "$f" ]] || continue
  if jq -e '(.ok // false) | not' "$f" >/dev/null 2>&1 &&
     jq -e '.results | (.quality == "fail" or .validate == "fail" or .test == "fail")' "$f" >/dev/null 2>&1; then
    failed=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$failed")
  fi
done
printf '%s\n' "$failed"
