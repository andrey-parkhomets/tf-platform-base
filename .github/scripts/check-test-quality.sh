#!/usr/bin/env bash
# Cheap static checks that a test file can actually fail.
#  - every run block has at least one assert block or expect_failures
#  - no run block uses `command = apply` (no cloud, no credentials)
#  - no assert is a constant `true`
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

for f in "$dir"/tests/*.tftest.hcl; do
  [[ -e "$f" ]] || continue
  awk -v file="$f" '
    function finish() {
      if (inrun && !(asserts || expects)) { printf "::error file=%s::run \"%s\" has no assert and no expect_failures\n", file, name; bad = 1 }
    }
    /^run[ \t]+"/ { finish(); inrun = 1; asserts = 0; expects = 0; name = $2; gsub(/"/, "", name) }
    inrun && /^[ \t]*assert[ \t]*\{/ { asserts++ }
    inrun && /^[ \t]*expect_failures[ \t]*=/ { expects++ }
    /^[ \t]*command[ \t]*=[ \t]*apply/ { printf "::error file=%s::command = apply is not allowed (no cloud resources)\n", file; bad = 1 }
    /^[ \t]*condition[ \t]*=[ \t]*true[ \t]*$/ { printf "::error file=%s::constant assert condition (true)\n", file; bad = 1 }
    END { finish(); exit bad }
  ' "$f" || status=1
done
exit "$status"
