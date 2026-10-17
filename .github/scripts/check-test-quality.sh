#!/usr/bin/env bash
# Cheap static checks that a test file can actually fail.
#  - every run block has at least one assert block or expect_failures
#  - no run block uses `command = apply` (no cloud, no credentials)
#  - no assert is a constant `true`
#  - no assert pins an insecure DEFAULT (see `insecure` below): the test would bless it and make a later fix look like a
#    regression. Asserting that an explicitly set input is honoured is fine, so a run that sets the attribute itself is allowed.
#  - no symlinks under tests/
# Usage: check-test-quality.sh <dir>   (checks <dir>/tests/*.tftest.hcl)
set -euo pipefail
dir=${1:?module dir}
status=0

# A symlink in tests/ could make an edit land outside tests/; the guard also rejects it, this fails earlier and clearer.
if [[ -d "$dir/tests" ]] && [[ -n $(find "$dir/tests" -type l -print -quit) ]]; then
  echo "::error::symlink under $dir/tests is not allowed"
  status=1
fi

# attribute:regex of the insecure value. Extend when a module gains a security-relevant setting.
insecure='public_network_access_enabled:true public_network_enabled:true allow_nested_items_to_be_public:true shared_access_key_enabled:true
 https_only:false https_traffic_only_enabled:false purge_protection_enabled:false no_public_ip:false
 ftps_state:"AllAllowed" default_action:"Allow" min_tls_version:"(TLS)?1[._][01]" minimum_tls_version:"(TLS)?1[._][01]"'

for f in "$dir"/tests/*.tftest.hcl; do
  [[ -e "$f" ]] || continue
  awk -v file="$f" -v insecure="$insecure" '
    BEGIN { n = split(insecure, pairs, /[ \t\n]+/); k = 0
      for (i = 1; i <= n; i++) if (pairs[i] != "") { k++; c = index(pairs[i], ":"); attr[k] = substr(pairs[i], 1, c - 1); val[k] = substr(pairs[i], c + 1) } }
    function finish(   j) {
      if (inrun && !(asserts || expects)) { printf "::error file=%s::run \"%s\" has no assert and no expect_failures\n", file, name; bad = 1 }
      for (j = 1; inrun && j <= k; j++)
        if (hit[j] && !(attr[j] in assigned)) {
          printf "::error file=%s::run \"%s\" asserts %s == %s on its default. Do not pin an insecure default in a test; report it as a finding instead\n", file, name, attr[j], val[j]; bad = 1
        }
    }
    /^run[ \t]+"/ { finish(); inrun = 1; asserts = 0; expects = 0; name = $2; gsub(/"/, "", name); delete hit; delete assigned }
    inrun && /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=/ && !/^[ \t]*(condition|error_message|command|expect_failures)[ \t]*=/ { l = $0; sub(/^[ \t]*/, "", l); sub(/[ \t]*=.*/, "", l); assigned[l] = 1 }
    inrun && /^[ \t]*condition[ \t]*=/ { for (j = 1; j <= k; j++) if ($0 ~ ("[^A-Za-z0-9_]" attr[j] "[ \t]*==[ \t]*" val[j] "([^A-Za-z0-9_]|$)")) hit[j] = 1 }
    inrun && /^[ \t]*assert[ \t]*\{/ { asserts++ }
    inrun && /^[ \t]*expect_failures[ \t]*=/ { expects++ }
    /^[ \t]*command[ \t]*=[ \t]*apply/ { printf "::error file=%s::command = apply is not allowed (no cloud resources)\n", file; bad = 1 }
    /^[ \t]*condition[ \t]*=[ \t]*true[ \t]*$/ { printf "::error file=%s::constant assert condition (true)\n", file; bad = 1 }
    END { finish(); exit bad }
  ' "$f" || status=1
done
exit "$status"
