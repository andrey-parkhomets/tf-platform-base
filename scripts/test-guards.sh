#!/usr/bin/env bash
# Fast tests (no Docker, no network) for the deterministic safety scripts in .github/scripts/.
#   scripts/test-guards.sh
# These are the checks that must hold even if the agent misbehaves, so they get their own tests.
set -uo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
scripts="$repo/.github/scripts"
fail=0
ok()   { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }
is() { # is <description> <actual> <expected>
  if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1 (got: $2, want: $3)"; fi
}
expect_rc() { # expect_rc <description> <expected rc> <command...>
  local d=$1 want=$2; shift 2
  "$@" >/dev/null 2>&1; local rc=$?
  if [[ ($want == 0 && $rc -eq 0) || ($want != 0 && $rc -ne 0) ]]; then ok "$d"; else bad "$d (rc=$rc)"; fi
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

new_repo() { # new_repo <dir>: git repo with one module and a stack
  rm -rf "$1"; mkdir -p "$1/modules/m1/tests" "$1/stacks/s1"
  ( cd "$1" && git init -q -b main && git config user.email t@t && git config user.name t && git config commit.gpgsign false
    echo 'x' >modules/m1/main.tf; echo 'x' >stacks/s1/main.tf; touch modules/m1/tests/a.tftest.hcl
    printf '.agent/\n' >.gitignore
    git add -A && git commit -q -m base )
}

echo "== guard-paths.sh"
r="$tmp/g"; new_repo "$r"; cd "$r" || exit 1
expect_rc "clean tree passes" 0 "$scripts/guard-paths.sh"
echo 'new' >modules/m1/tests/b.tftest.hcl;                 expect_rc "new test file passes" 0 "$scripts/guard-paths.sh"
echo 'mock' >modules/m1/tests/c.tfmock.hcl;                expect_rc "mock file passes" 0 "$scripts/guard-paths.sh"
mkdir -p .agent/report; echo '{}' >.agent/report/x.json;   expect_rc "ignored .agent output passes" 0 "$scripts/guard-paths.sh"
echo 'y' >>modules/m1/main.tf;                             expect_rc "edit of a .tf file fails" 1 "$scripts/guard-paths.sh"
git checkout -q -- modules/m1/main.tf
echo 'y' >>.github_workflow_change;                        expect_rc "new file at the repo root fails" 1 "$scripts/guard-paths.sh"
rm .github_workflow_change
mkdir -p modules/m1/tests/sub; echo z >modules/m1/tests/sub/d.tftest.hcl; expect_rc "nested path under tests/ fails" 1 "$scripts/guard-paths.sh"
rm -r modules/m1/tests/sub
ln -s ../main.tf modules/m1/tests/link.tftest.hcl;         expect_rc "symlink in tests/ fails" 1 "$scripts/guard-paths.sh"
rm modules/m1/tests/link.tftest.hcl
head -c 300000 /dev/zero | tr '\0' 'a' >modules/m1/tests/big.tftest.hcl; expect_rc "oversized test file fails" 1 "$scripts/guard-paths.sh"
rm modules/m1/tests/big.tftest.hcl
echo 'x' >"modules/m1/tests/we ird.tftest.hcl";             expect_rc "unusual file name fails" 1 "$scripts/guard-paths.sh"
rm "modules/m1/tests/we ird.tftest.hcl"
printf 'p' >modules/m1/.terraform.lock.hcl;                 expect_rc "lock file change fails" 1 "$scripts/guard-paths.sh"

echo "== detect-modules.sh"
r="$tmp/d"; new_repo "$r"; cd "$r" || exit 1
out=$(CHANGED_DIRS='["modules/m1","stacks/s1"]' "$scripts/detect-modules.sh")
is "two directories" "$(jq length <<<"$out")" 2
is "has_tests detected" "$(jq -r '.[0].has_tests' <<<"$out")" true
is "kind stack" "$(jq -r '.[1].kind' <<<"$out")" stack
out=$(CHANGED_DIRS='[\"modules/m1\"]' "$scripts/detect-modules.sh")
is "escaped JSON accepted" "$(jq length <<<"$out")" 1
out=$(CHANGED_DIRS='modules/m1 modules/m1' "$scripts/detect-modules.sh")
is "duplicates collapsed" "$(jq length <<<"$out")" 1
# shellcheck disable=SC2016  # the $(id) is a literal test string
for evil in 'modules/..' 'modules/.hidden' 'modules/a..b' '../x' '/etc' 'modules/m1/../../x' 'modules/$(id)' 'modules/a;b' 'modules/gone'; do
  out=$(CHANGED_DIRS="$evil" "$scripts/detect-modules.sh" 2>/dev/null)
  is "rejected: $evil" "$out" "[]"
done
base=$(git rev-parse HEAD); echo y >>modules/m1/main.tf; echo y >modules/m1/README.md; git add -A; git commit -q -m c; head=$(git rev-parse HEAD)
out=$(BASE_SHA=$base HEAD_SHA=$head "$scripts/detect-modules.sh")
is "git fallback finds the module" "$(jq -r 'map(.dir)|join(",")' <<<"$out")" modules/m1

echo "== check-test-quality.sh"
r="$tmp/q"; new_repo "$r"; cd "$r" || exit 1
good='run "a" {\n  command = plan\n  assert {\n    condition     = 1 == 1\n    error_message = "x"\n  }\n}\n'
printf '%b' "$good" >modules/m1/tests/a.tftest.hcl;                         expect_rc "valid test passes" 0 "$scripts/check-test-quality.sh" modules/m1
printf 'run "a" {\n  command = apply\n  assert {\n    condition = 1 == 1\n    error_message = "x"\n  }\n}\n' >modules/m1/tests/a.tftest.hcl
expect_rc "command = apply fails" 1 "$scripts/check-test-quality.sh" modules/m1
printf 'run "a" {\n  command = plan\n}\n' >modules/m1/tests/a.tftest.hcl;  expect_rc "run without assert fails" 1 "$scripts/check-test-quality.sh" modules/m1
printf 'run "a" {\n  command = plan\n  assert {\n    condition = true\n    error_message = "x"\n  }\n}\n' >modules/m1/tests/a.tftest.hcl
expect_rc "constant true condition fails" 1 "$scripts/check-test-quality.sh" modules/m1
printf 'run "a" {\n  command = plan\n  variables {\n    x = 1\n  }\n  expect_failures = [var.x]\n}\n' >modules/m1/tests/a.tftest.hcl
expect_rc "expect_failures counts as a check" 0 "$scripts/check-test-quality.sh" modules/m1
ln -s ../main.tf modules/m1/tests/evil.tftest.hcl
printf 'run "a" {\n  command = plan\n  assert {\n    condition = 1 == 1\n    error_message = "x"\n  }\n}\n' >modules/m1/tests/a.tftest.hcl
expect_rc "symlink under tests/ fails" 1 "$scripts/check-test-quality.sh" modules/m1
rm modules/m1/tests/evil.tftest.hcl

echo
[[ $fail -eq 0 ]] && echo "all guard tests passed" || echo "SOME GUARD TESTS FAILED"
exit $fail
