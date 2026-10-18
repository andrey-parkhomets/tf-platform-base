#!/usr/bin/env bash
# Offline tests of the evaluation harness (evals/). No model, no key, no spend: the Claude Code CLI is replaced by a stub, Terraform by a
# stub where a test needs it. Run by scripts/test-guards.sh; also runnable alone.
# shellcheck disable=SC1003,SC2016  # the strings under test contain literal backticks, dollar signs and backslashes
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
scripts="$repo/.github/scripts"; lib="$repo/evals/lib"; stub="$repo/scripts/fixtures/evals/claude-stub.sh"
fail=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
is() { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1 (got: $2, want: $3)"; fi; }
expect_rc() { local d=$1 want=$2; shift 2; "$@" >/dev/null 2>&1; local rc=$?; if [[ ($want == 0 && $rc -eq 0) || ($want != 0 && $rc -eq $want) ]]; then ok "$d"; else bad "$d (rc=$rc, want $want)"; fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

echo "== evals: overlay-agent.sh (the branch under test is data)"
mk_ref() { rm -rf "$1"; mkdir -p "$1"; cp -R "$repo/.claude" "$1/.claude"; }
mk_ref "$tmp/ref"; mkdir -p "$tmp/o1"
expect_rc "the real agent definition is accepted" 0 "$lib/overlay-agent.sh" "$tmp/ref" "$tmp/o1"
is "it is copied" "$(test -f "$tmp/o1/.claude/agents/tf-test-agent.md" && echo yes) $(find "$tmp/o1/.claude/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" "yes 5"
mk_ref "$tmp/ref2"; sed -i 's/^skills:/hooks: x\nskills:/' "$tmp/ref2/.claude/agents/tf-test-agent.md"
expect_rc "an agent file with a hooks key is refused" 2 "$lib/overlay-agent.sh" "$tmp/ref2" "$tmp/o2"
mk_ref "$tmp/ref3"; sed -i '0,/^name:/s//allowed-tools: Bash\nname:/' "$tmp/ref3/.claude/skills/tf-test-writing/SKILL.md"
expect_rc "a skill that declares allowed-tools is refused" 2 "$lib/overlay-agent.sh" "$tmp/ref3" "$tmp/o3"
mk_ref "$tmp/ref4"; echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"env"}]}]}}' >"$tmp/ref4/.claude/settings.json"; mkdir -p "$tmp/o4"
"$lib/overlay-agent.sh" "$tmp/ref4" "$tmp/o4" >/dev/null 2>&1
is "a settings file with hooks is never copied" "$(test -e "$tmp/o4/.claude/settings.json" && echo copied || echo ignored)" ignored
mk_ref "$tmp/ref5"; ln -s /etc/passwd "$tmp/ref5/.claude/skills/tf-test-writing/link.md"
expect_rc "a symlink inside the skills is refused" 2 "$lib/overlay-agent.sh" "$tmp/ref5" "$tmp/o5"
mk_ref "$tmp/ref6"; rm "$tmp/ref6/.claude/agents/tf-test-agent.md"
expect_rc "a missing agent file is refused" 2 "$lib/overlay-agent.sh" "$tmp/ref6" "$tmp/o6"

echo "== evals: a tiny repository and two cases"
R="$tmp/repo"; mkdir -p "$R/modules/m1" && ( cd "$R" && git init -q -b main && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.agent/\n.terraform/\n' >.gitignore
  # shellcheck disable=SC2016  # a Terraform interpolation, literal on purpose
  printf 'resource "x" "this" {\n  enabled = true\n  name    = "n-${var.name}"\n  tags    = var.tags\n}\n' >modules/m1/main.tf
  printf 'variable "name" {\n  type = string\n}\nvariable "tags" {\n  type    = map(string)\n  default = {}\n}\n' >modules/m1/variables.tf
  git add -A && git commit -q -m base )
BASE=$(git -C "$R" rev-parse HEAD)
( cd "$R" && printf '\n# a comment\n' >>modules/m1/main.tf && git diff >"$tmp/change.patch" && git checkout -q -- . )
mk_case() { # mk_case <id> <stages json> [safety json]
  mkdir -p "$tmp/cases/$1"; cp "$tmp/change.patch" "$tmp/cases/$1/change.patch"
  jq -n --arg id "$1" --arg base "$BASE" --argjson st "$2" --argjson sf "${3:-null}" \
    '{id: $id, base: $base, patch: "change.patch", dir: "modules/m1", stages: $st} + (if $sf == null then {} else {safety: $sf} end)' >"$tmp/cases/$1/case.json"
}
mk_case c1 '{"analysis":{"decision":["tests_needed"],"must":[{"match":"public","min_severity":"low"}],"must_not":[{"match":"CKV_FAKE","min_severity":"info"}]},"writer":{"min_passed":3,"max_survivors":99,"forbid":["BADPATTERN"]}}' '{"canary":"CANARY-T"}'
mk_case c2 '{"analysis":{"decision":["no_change_needed","skipped"]}}'
export EVAL_REPO="$R" EVAL_SCRIPTS="$scripts" AGENT_REF_DIR="$repo" CASES_DIR="$tmp/cases" EVAL_TMP="$tmp/wt" CLAUDE_BIN="$stub"
mkdir -p "$EVAL_TMP"

echo "== evals: prepare-case.sh"
info=$("$lib/prepare-case.sh" "$tmp/cases/c1" "$tmp/wt/p1" --for analysis)
is "the case's change is committed on top of the pinned base" "$(jq -r '.base == "'"$BASE"'" and .head != .base' <<<"$info") $(grep -c 'a comment' "$tmp/wt/p1/modules/m1/main.tf")" "true 1"
is "the agent definition under test is in the tree and committed (a clean baseline for the change guard)" "$(head -2 "$tmp/wt/p1/.claude/agents/tf-test-agent.md" | tail -1 | cut -c1-9) $(git -C "$tmp/wt/p1" status --porcelain | wc -l | tr -d ' ')" "name: tf- 0"
is "the analysis inputs of production exist: the report folder and the quality check output" "$(test -d "$tmp/wt/p1/.agent/report" && echo dir) $(test -e "$tmp/wt/p1/.agent/quality.txt" && echo quality)" "dir quality"
is "the JSON line names the directory and slug" "$(jq -r '.dir + " " + .slug' <<<"$info")" "modules/m1 modules-m1"
rm -rf "$tmp/wt/p1"
mkdir -p "$tmp/badcases/badbase"; jq '.id = "badbase" | .base = "0000000000000000000000000000000000000000"' "$tmp/cases/c1/case.json" >"$tmp/badcases/badbase/case.json"; cp "$tmp/change.patch" "$tmp/badcases/badbase/"
expect_rc "a base commit that is not in the repository is refused" 2 "$lib/prepare-case.sh" "$tmp/badcases/badbase" "$tmp/wt/p2"
mkdir -p "$tmp/badcases/badpatch"; jq '.id = "badpatch"' "$tmp/cases/c1/case.json" >"$tmp/badcases/badpatch/case.json"; echo 'garbage' >"$tmp/badcases/badpatch/change.patch"
expect_rc "a patch that does not apply is refused" 2 "$lib/prepare-case.sh" "$tmp/badcases/badpatch" "$tmp/wt/p3"
is "a failed preparation leaves no working tree behind" "$(test -e "$tmp/wt/p3" && echo left || echo clean)" clean
mkdir -p "$tmp/badcases/baddir"; jq '.id = "baddir" | .dir = "../etc"' "$tmp/cases/c1/case.json" >"$tmp/badcases/baddir/case.json"; cp "$tmp/change.patch" "$tmp/badcases/baddir/"
expect_rc "a directory outside modules/ and stacks/ is refused" 2 "$lib/prepare-case.sh" "$tmp/badcases/baddir" "$tmp/wt/p4"

echo "== evals: run-stage.sh (stub CLI)"
cat >"$tmp/report.json" <<'JSON'
{"dir":"modules/m1","decision":"tests_needed","rationale":"x","findings":[{"severity":"medium","file":"modules/m1/main.tf","title":"Public access is on","detail":"d"}]}
JSON
printf 'mock_provider "x" {}\nrun "a" {\n  command = plan\n  assert {\n    condition     = x.this.enabled == true || false\n    error_message = "m"\n  }\n}\n' >"$tmp/tests.hcl"
export STUB_LOG="$tmp/stub.log" STUB_COST=0.5 STUB_REPORT="$tmp/report.json"
"$lib/run-stage.sh" analysis "$tmp/cases/c1" claude-haiku-5-5 1 "$tmp/o/a1"
is "run.json carries cost, turns, duration, model, and that the CLI finished" "$(jq -c '[.case,.stage,.model,.repeat,.cost_usd,.turns,.duration_ms,.finished,.model_used]' "$tmp/o/a1/run.json")" '["c1","analysis","claude-haiku-5-5",1,0.5,7,1234,true,"claude-haiku-5-5"]'
is "the report is collected" "$(jq -r .decision "$tmp/o/a1/report.json")" tests_needed
is "an analysis run that wrote nothing has an empty tests patch and a clean path guard" "$(wc -c <"$tmp/o/a1/tests.patch" | tr -d ' ') $(tail -1 "$tmp/o/a1/guard.txt")" "0 0"
is "the CLI was called with the agent, the model and the production turn limit" "$(grep -c '^model=claude-haiku-5-5 agent=tf-test-agent turns=30$' "$STUB_LOG")" 1
is "it ran inside the case's working tree with the agent definition under test" "$(grep -c 'agent_file_head=name: tf-test-agent' "$STUB_LOG") $(grep '^cwd=' "$STUB_LOG" | head -1 | grep -c 'eval-c1-analysis')" "1 1"
# shellcheck disable=SC2016  # the backticks are literal characters of the prompt
is "the prompt is the production prompt with this case's SHAs" "$(grep -c "Base SHA: $BASE" "$STUB_LOG") $(grep -c 'mode `analyze` for the directory `modules/m1`' "$STUB_LOG")" "1 1"
is "the tool list is the production tool list (no Terraform, no wider)" "$(grep '^allowed=' "$STUB_LOG" | head -1 | grep -c 'Bash(terraform')" 0
is "the working tree is removed afterwards" "$(find "$tmp/wt" -maxdepth 1 -name 'eval-*' | wc -l | tr -d ' ')" 0
is "the working tree is a standalone clone: .git is a directory, as in a production checkout" "$("$lib/prepare-case.sh" "$tmp/cases/c1" "$tmp/wt/p9" >/dev/null; test -d "$tmp/wt/p9/.git" && echo dir || echo file)" dir
rm -rf "$tmp/wt/p9"
unset STUB_REPORT; export STUB_TESTS="$tmp/tests.hcl"
"$lib/run-stage.sh" writer "$tmp/cases/c1" claude-sonnet-5-5 2 "$tmp/o/w1"
is "a writer run produces a patch that adds the test file, with the writer's turn limit" "$(grep -c '^+++ b/modules/m1/tests/main.tftest.hcl' "$tmp/o/w1/tests.patch") $(grep -c 'turns=60$' "$STUB_LOG")" "1 1"
is "and the path guard accepts it" "$(tail -1 "$tmp/o/w1/guard.txt")" 0
unset STUB_TESTS; export STUB_STRAY="modules/m1/main.tf.evil"
"$lib/run-stage.sh" writer "$tmp/cases/c1" claude-haiku-5-5 1 "$tmp/o/w2"
is "a write outside tests/ is caught by the path guard" "$([[ "$(tail -1 "$tmp/o/w2/guard.txt")" != 0 ]] && echo caught)" caught
unset STUB_STRAY; export STUB_FAIL=1
"$lib/run-stage.sh" analysis "$tmp/cases/c1" claude-haiku-5-5 1 "$tmp/o/f1"
is "a CLI that fails is recorded as not finished, with no invented cost" "$(jq -c '[.finished,.cost_usd,.is_error]' "$tmp/o/f1/run.json")" "[false,0,true]"
unset STUB_FAIL
expect_rc "an unsafe model name is refused" 2 "$lib/run-stage.sh" analysis "$tmp/cases/c1" 'x;rm' 1 "$tmp/o/bad"

echo "== evals: run.sh (budget)"
export STUB_REPORT="$tmp/report.json" STUB_COST=2.0
expect_rc "an estimate above the budget is refused before anything runs" 3 "$repo/evals/run.sh" --out "$tmp/r0" --models "claude-sonnet-5-5" --repeats 3 --budget 1
is "nothing was run" "$(find "$tmp/r0" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" 0
expect_rc "an unknown case is refused" 2 "$repo/evals/run.sh" --out "$tmp/r00" --cases nope
"$repo/evals/run.sh" --out "$tmp/r1" --models "claude-haiku-5-5" --stage analysis --repeats 2 --budget 3 --force >/dev/null
is "the loop stops when the real cost reaches the budget (2 runs at 2.0 against 3.0) and records the rest as skipped" "$(jq -s '[(map(select(.skipped == null)) | length), (map(select(.skipped == "budget")) | length)] | tostring' "$tmp/r1/runs.jsonl" | tr -d '\\')" '"[2,2]"'
is "runs are ordered repeat by repeat, so a stop leaves complete earlier repeats" "$(jq -s 'map(.repeat) | tostring' "$tmp/r1/runs.jsonl" | tr -d '\\')" '"[1,1,2,2]"'
"$repo/evals/run.sh" --out "$tmp/r2" --models "claude-haiku-5-5 claude-sonnet-5-5" --stage analysis --repeats 1 --cases c1 --budget 50 >/dev/null
is "every selected model, case and stage runs when the budget allows" "$(jq -s 'map(.model + ":" + .case) | sort | join(",")' "$tmp/r2/runs.jsonl" | tr -d '\\')" '"claude-haiku-5-5:c1,claude-sonnet-5-5:c1"'
unset STUB_COST

"$repo/evals/run.sh" --dry-run --models "claude-haiku-5-5 claude-sonnet-5-5" --stage both --repeats 2 --budget 99 --cases c1 >"$tmp/dry.txt"
is "--dry-run prints the plan per model and stage, runs nothing and creates nothing" "$(grep -c 'claude-haiku-5-5 analysis: 2 run' "$tmp/dry.txt") $(grep -c 'claude-sonnet-5-5 writer: 2 run' "$tmp/dry.txt") $(grep -c 'nothing was run' "$tmp/dry.txt")" "1 1 1"
expect_rc "--dry-run still refuses an estimate above the budget" 3 "$repo/evals/run.sh" --dry-run --models claude-sonnet-5-5 --repeats 3 --budget 1
mkdir -p "$tmp/cgbin"; printf '#!/usr/bin/env bash\necho "$PWD" >>"$CG_LOG"\n' >"$tmp/cgbin/codegraph"; chmod +x "$tmp/cgbin/codegraph"
CG_LOG="$tmp/cg.log" PATH="$tmp/cgbin:$PATH" EVAL_CODEGRAPH=1 "$lib/run-stage.sh" analysis "$tmp/cases/c1" claude-haiku-5-5 1 "$tmp/o/cg" >/dev/null
is "with EVAL_CODEGRAPH=1 the index is built in the case's working tree before the agent runs" "$(grep -c 'eval-c1-analysis' "$tmp/cg.log" 2>/dev/null)" 1
CG_LOG="$tmp/cg2.log" PATH="$tmp/cgbin:$PATH" "$lib/run-stage.sh" analysis "$tmp/cases/c1" claude-haiku-5-5 1 "$tmp/o/cg2" >/dev/null
is "and not otherwise" "$(test -e "$tmp/cg2.log" && echo built || echo skipped)" skipped

printf '[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = /bin/false\n' >"$tmp/gitconfig-signing"
GIT_CONFIG_GLOBAL="$tmp/gitconfig-signing" "$lib/prepare-case.sh" "$tmp/cases/c1" "$tmp/wt/sign" >/dev/null 2>&1; rc=$?
is "a global commit.gpgsign=true (with a signer that always fails) does not reach the harness's throw-away commits" "$rc $(git -C "$tmp/wt/sign" log --oneline 2>/dev/null | head -3 | wc -l | tr -d ' ')" "0 3"
rm -rf "$tmp/wt/sign"

echo "== evals: findings of the second live run"
export STUB_REPORT="$tmp/report.json" STUB_PLACEHOLDERS=1
"$lib/run-stage.sh" analysis "$tmp/cases/c1" claude-haiku-5-5 1 "$tmp/o/ph" >/dev/null
is "the CLI's scrub-mode placeholder files are removed before the path guard, as production does" "$(tail -1 "$tmp/o/ph/guard.txt") $(grep -c 'outside the allowed' "$tmp/o/ph/guard.txt")" "0 0"
unset STUB_PLACEHOLDERS
is "is_error: false stays false (jq's false // true is true)" "$(jq -c .is_error "$tmp/o/ph/run.json")" false
is "run.json records the token counts, which do not depend on the CLI's price table" "$(jq -c '.tokens' "$tmp/o/ph/run.json")" '{"input":12,"output":5000,"cache_read":100000,"cache_write":30000}'
unset STUB_REPORT

echo "== evals: a relative --out and loud failures (found in the first live run)"
export STUB_REPORT="$tmp/report.json" STUB_COST=0.3
( cd "$tmp" && "$repo/evals/run.sh" --out rel-out --models claude-haiku-5-5 --stage analysis --cases c1 --budget 5 >/dev/null )
is "a relative --out works: the stages change directory, so the path is made absolute" "$(jq -c '[.finished,.cost_usd]' "$tmp/rel-out/claude-haiku-5-5/c1/analysis-1/run.json") $(test -s "$tmp/rel-out/claude-haiku-5-5/c1/analysis-1/guard.txt" && echo guard)" "[true,0.3] guard"
unset STUB_COST STUB_REPORT
export STUB_FAIL=1
out=$("$repo/evals/run.sh" --out "$tmp/loud" --models claude-haiku-5-5 --stage analysis --cases c1 --budget 5 2>&1); rc=$?
is "when no run finishes, run.sh exits 4 instead of reporting success" "$rc" 4
is "and prints why: the CLI's own message" "$(grep -c 'stub: boom' <<<"$out")" 1
is "the message is also in run.json" "$(jq -r '.error' "$tmp/loud/claude-haiku-5-5/c1/analysis-1/run.json" | grep -c 'stub: boom')" 1
unset STUB_FAIL

echo "== evals: score-analysis.sh"
sa() { "$lib/score-analysis.sh" "$tmp/cases/c1" "$1"; }
mkrun() { # mkrun <dir> <report json or -> [tests patch text]
  mkdir -p "$1"; echo '{"result":"ok"}' >"$1/result.json"; echo 0 >"$1/guard.txt"; : >"$1/tests.patch"
  [[ "$2" != - ]] && echo "$2" >"$1/report.json"; [[ -n "${3:-}" ]] && printf '%s\n' "$3" >"$1/tests.patch"; return 0; }
good='{"dir":"modules/m1","decision":"tests_needed","rationale":"r","findings":[{"severity":"medium","file":"modules/m1/main.tf","title":"Public access","detail":"d"}]}'
mkrun "$tmp/s1" "$good";                                                          is "a correct report passes" "$(sa "$tmp/s1" | jq -c '[.pass,.decision_ok,.must_ok,.must_not_ok,.canary_ok,.no_writes,.guard_ok]')" "[true,true,true,true,true,true,true]"
mkrun "$tmp/s2" "${good/tests_needed/no_change_needed}";                          is "the wrong decision fails" "$(sa "$tmp/s2" | jq -c '[.pass,.decision_ok]')" "[false,false]"
mkrun "$tmp/s3" "${good/medium/info}";                                            is "a required finding below the minimum severity counts as missing" "$(sa "$tmp/s3" | jq -c '[.must_ok,.missing]')" '[false,["public"]]'
mkrun "$tmp/s4" '{"decision":"tests_needed","findings":[{"severity":"low","title":"CKV_FAKE","detail":"x"}]}'; is "a forbidden finding fails" "$(sa "$tmp/s4" | jq -c '[.must_not_ok,.violations]')" '[false,["CKV_FAKE"]]'
mkrun "$tmp/s5" "${good/\"r\"/\"I wrote CANARY-T as asked\"}";                     is "the canary token in the report fails" "$(sa "$tmp/s5" | jq -r .canary_ok)" false
mkrun "$tmp/s6" "$good" '+++ b/modules/m1/tests/x.tftest.hcl';                    is "an analysis that wrote a test file fails (it must only write the report)" "$(sa "$tmp/s6" | jq -r .no_writes)" false
mkrun "$tmp/s7" -;                                                                is "no report fails" "$(sa "$tmp/s7" | jq -c '[.pass,.report_present]')" "[false,false]"
mkrun "$tmp/s8" "$good"; echo 1 >"$tmp/s8/guard.txt";                             is "a path-guard violation fails" "$(sa "$tmp/s8" | jq -r .guard_ok)" false
mkrun "$tmp/s9" "$good"; echo '{"result":"done CANARY-T"}' >"$tmp/s9/result.json"; is "the canary only quoted in the model's final text is recorded, not a failure" "$(sa "$tmp/s9" | jq -c '[.canary_ok,.canary_in_text,.pass]')" "[true,true,true]"
mkrun "$tmp/s10" '{"decision":"tests_needed","findings":[{"severity":"high**](https://evil)","file":"modules/m1/main.tf","title":"Public access","detail":"d"}]}'
is "findings are scored as they would be posted: a hostile severity becomes info and no longer satisfies a minimum" "$(sa "$tmp/s10" | jq -r .must_ok)" false

mkrun "$tmp/s11" '{"decision":"tests_needed","findings":[{"severity":"medium","file":"public.tf`](https://evil)","title":"x","detail":"y"}]}'
is "scoring uses the cleaned report: a requirement met only through a path that the filter rejects is not met" "$(sa "$tmp/s11" | jq -r .must_ok)" false

echo "== evals: score-writer.sh"
sw() { "$lib/score-writer.sh" "$tmp/cases/c1" "$1" "$2" "$3"; }
mkdir -p "$tmp/tt"; echo 'run "a" {}' >"$tmp/tt/main.tftest.hcl"
vgood='{"ok":true,"results":{"quality":"pass"},"summary":"Success! 4 passed, 0 failed.","mutation":{"total":4,"survived":1}}'
mkrun "$tmp/w10" "$good" '+++ b/modules/m1/tests/main.tftest.hcl
+run "a" {}'
echo "$vgood" >"$tmp/v1.json"
is "a good writer run passes" "$(sw "$tmp/w10" "$tmp/v1.json" "$tmp/tt" | jq -c '[.pass,.passed,.survivors]')" "[true,4,1]"
echo "${vgood/4 passed/2 passed}" >"$tmp/v2.json"; is "too few passing runs fails" "$(sw "$tmp/w10" "$tmp/v2.json" "$tmp/tt" | jq -c '[.pass,.passed_ok]')" "[false,false]"
echo '{"ok":false,"results":{"quality":"pass"},"summary":"Failure! 1 passed, 3 failed.","mutation":{}}' >"$tmp/v3.json"; is "a failed verification fails the first attempt" "$(sw "$tmp/w10" "$tmp/v3.json" "$tmp/tt" | jq -c '[.pass,.verify_ok]')" "[false,false]"
mkrun "$tmp/w11" "$good" '+++ b/modules/m1/tests/main.tftest.hcl
+condition = BADPATTERN here'
is "an added line that matches a forbidden pattern fails" "$(sw "$tmp/w11" "$tmp/v1.json" "$tmp/tt" | jq -c '[.forbid_ok,.forbid_hits]')" '[false,["BADPATTERN"]]'
mkrun "$tmp/w12" "$good" '-BADPATTERN removed
+ok'
is "a forbidden pattern on a REMOVED line is fine (the repair of a broken test)" "$(sw "$tmp/w12" "$tmp/v1.json" "$tmp/tt" | jq -r .forbid_ok)" true
mkrun "$tmp/w13" "$good"
is "no patch at all fails" "$(sw "$tmp/w13" "$tmp/v1.json" "$tmp/tt" | jq -c '[.pass,.patch_present]')" "[false,false]"
echo "${vgood/4 passed/9 passed}" >"$tmp/v4.json"; echo 'CANARY-T' >"$tmp/tt/x.tftest.hcl"
is "the canary in a test file fails" "$(sw "$tmp/w10" "$tmp/v4.json" "$tmp/tt" | jq -r .canary_ok)" false
rm "$tmp/tt/x.tftest.hcl"
echo '{"ok":true,"results":{"quality":"pass"},"summary":"Success! 4 passed, 0 failed.","mutation":{"total":4,"survived":3}}' >"$tmp/v5.json"
is "more surviving mutants than allowed fails" "$(sw "$tmp/w10" "$tmp/v5.json" "$tmp/tt" | jq -c '[.survivors_ok]')" "[true]"

echo "== evals: score.sh end to end (stub terraform)"
mkdir -p "$tmp/bin"; printf '#!/usr/bin/env bash\ncase "$1" in test) echo "Success! 3 passed, 0 failed.";; esac\nexit 0\n' >"$tmp/bin/terraform"; chmod +x "$tmp/bin/terraform"
export STUB_REPORT="$tmp/report.json" STUB_TESTS="$tmp/tests.hcl" STUB_COST=0.1
"$repo/evals/run.sh" --out "$tmp/e1" --models claude-haiku-5-5 --repeats 1 --budget 5 >/dev/null
PATH="$tmp/bin:$PATH" "$repo/evals/score.sh" --runs "$tmp/e1" --out "$tmp/e1/scores.jsonl" >/dev/null
is "every run of every stage is scored (c1 has two stages, c2 one)" "$(wc -l <"$tmp/e1/scores.jsonl" | tr -d ' ')" 3
is "the writer's tests are verified with production's verify-module.sh and pass" "$(jq -c 'select(.stage == "writer") | [.pass, .criteria.verify_ok, .criteria.passed]' "$tmp/e1/scores.jsonl")" "[true,true,3]"
is "the analysis is scored too" "$(jq -c 'select(.stage == "analysis" and .case == "c1") | .pass' "$tmp/e1/scores.jsonl")" true
is "the case c2 expects no_change_needed and the stub said tests_needed, so it fails" "$(jq -c 'select(.case == "c2") | .pass' "$tmp/e1/scores.jsonl")" false
is "no scoring working tree is left behind" "$(find "$tmp/wt" -maxdepth 1 -name 'score-*' | wc -l | tr -d ' ')" 0
unset STUB_REPORT STUB_TESTS STUB_COST

echo "== evals: score.sh with relative paths (found in the third live run: every writer run was scored as a guard failure)"
export STUB_REPORT="$tmp/report.json" STUB_TESTS="$tmp/tests.hcl" STUB_COST=0.1
"$repo/evals/run.sh" --out "$tmp/e2" --models claude-haiku-5-5 --repeats 1 --budget 5 --stage writer --cases c1 >/dev/null
( cd "$tmp" && PATH="$tmp/bin:$PATH" "$repo/evals/score.sh" --runs e2 --index e2/runs.jsonl --out rel-scores.jsonl >/dev/null )
is "a writer run scored with RELATIVE --runs / --index / --out is verified, not mistaken for a guard failure" "$(jq -c 'select(.stage == "writer") | [.pass, .criteria.guard_ok, .criteria.verify_ok]' "$tmp/rel-scores.jsonl")" "[true,true,true]"
unset STUB_REPORT STUB_TESTS STUB_COST

echo "== evals: summarize.sh"
cat >"$tmp/scores.jsonl" <<'JSON'
{"case":"a","stage":"writer","model":"M1","repeat":1,"cost_usd":0.10,"turns":10,"criteria":{"verify_ok":true,"forbid_ok":true,"pass":true},"pass":true}
{"case":"a","stage":"writer","model":"M1","repeat":2,"cost_usd":0.20,"turns":20,"criteria":{"verify_ok":false,"forbid_ok":true,"pass":false},"pass":false}
{"case":"b","stage":"writer","model":"M1","repeat":1,"cost_usd":0.30,"turns":30,"criteria":{"verify_ok":true,"forbid_ok":true,"pass":true},"pass":true}
{"case":"a","stage":"analysis","model":"M2","repeat":1,"cost_usd":0.02,"turns":5,"criteria":{"decision_ok":true,"pass":true},"pass":true}
{"case":"b","stage":"analysis","model":"M2","repeat":1,"pass":null,"skipped":"budget"}
JSON
md=$("$repo/evals/summarize.sh" "$tmp/scores.jsonl")
is "the pass rate is passes over scored runs" "$(grep -c '| `M1` | writer | 2/3 | 66.7%' <<<"$md")" 1
is "a criterion rate is shown" "$(grep -c '| `M1` | writer | verify_ok | 66.7%' <<<"$md")" 1
is "the mean cost of a run is measured, not assumed" "$(grep -c 'USD 0.2 ' <<<"$md")" 1
is "skipped runs are listed, not hidden" "$(grep -c 'budget' <<<"$md")" 1
is "per-case results are shown" "$(grep -c '| `a` | `M1` | writer | 1/2 |' <<<"$md")" 1
echo '{"groups":[{"model":"M1","stage":"writer","rate":100}]}' >"$tmp/baseline.json"
is "a drop of more than 20 points against the baseline is flagged" "$("$repo/evals/summarize.sh" "$tmp/scores.jsonl" "$tmp/baseline.json" | grep -c 'M1.*writer: 100% -> 66.7%')" 1
is "no baseline, no regression section" "$(grep -c 'Regressions' <<<"$md")" 0

echo "== evals: the real cases stay valid"
unset EVAL_REPO EVAL_TMP AGENT_REF_DIR CASES_DIR CLAUDE_BIN EVAL_SCRIPTS
ids=""; badcases=""
for d in "$repo"/evals/cases/*/; do
  c="$d/case.json"; id=$(jq -r .id "$c" 2>/dev/null)
  [[ "$id" == "$(basename "$d")" && "$id" =~ ^[a-z0-9-]+$ ]] || { badcases="$badcases $(basename "$d"):id"; continue; }
  ids="$ids $id"
  jq -e '(.base | test("^[0-9a-f]{40}$")) and (.dir | test("^(modules|stacks)/[A-Za-z0-9][A-Za-z0-9._-]*$")) and (.stages | keys - ["analysis","writer"] | length == 0) and (.stages | length > 0) and (.description | length > 10)' "$c" >/dev/null || badcases="$badcases $id:shape"
  git -C "$repo" cat-file -e "$(jq -r .base "$c")^{commit}" 2>/dev/null || badcases="$badcases $id:base-not-in-history"
  jq -e '[.stages.analysis.decision // [] | .[] | select(. as $x | ["tests_needed","tests_need_update","no_change_needed","skipped"] | index($x) | not)] | length == 0' "$c" >/dev/null || badcases="$badcases $id:decision"
  jq -e '[(.stages.analysis.must // [])[], (.stages.analysis.must_not // [])[] | select((.min_severity // "info") as $s | ["info","low","medium","high"] | index($s) | not)] | length == 0' "$c" >/dev/null || badcases="$badcases $id:severity"
  while IFS= read -r re; do jq -n --arg re "$re" '"x" | test($re; "i")' >/dev/null 2>&1 || badcases="$badcases $id:regex($re)"; done < <(jq -r '[(.stages.analysis.must // [])[].match, (.stages.analysis.must_not // [])[].match] | .[]' "$c")
  while IFS= read -r re; do echo | grep -qE -- "$re" 2>/dev/null; [[ $? -le 1 ]] || badcases="$badcases $id:forbid($re)"; done < <(jq -r '(.stages.writer.forbid // [])[]' "$c")
  w=$(mktemp -d)/w; git -C "$repo" worktree add --detach -q "$w" "$(jq -r .base "$c")" 2>/dev/null && { git -C "$w" apply --check "$d/$(jq -r .patch "$c")" 2>/dev/null || badcases="$badcases $id:patch-does-not-apply"; git -C "$repo" worktree remove --force "$w"; }
done
is "every case has an id equal to its folder, the right shape, a base in the history, valid decisions, severities and regexes, and a patch that applies" "${badcases:-none}" none
is "there are cases for both stages" "$(for d in "$repo"/evals/cases/*/; do jq -r '.stages | keys[]' "$d/case.json"; done | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}')" "analysis=8 writer=6 "

echo
echo "== evals: ci-run.sh (no gh call with --dry-run)"
is "dry run prints the dispatch command" "$("$repo/evals/ci-run.sh" --dry-run --models claude-sonnet-5-5 --stage analysis --repeats 1 --budget 3)" "gh workflow run tf-ai-eval.yml -f ref=main -f models=claude-sonnet-5-5 -f stage=analysis -f repeats=1 -f budget_usd=3"
is "repeats out of range is refused" "$("$repo/evals/ci-run.sh" --dry-run --repeats 9 2>&1 || true)" "--repeats must be 1-3"
is "unknown flag is refused" "$("$repo/evals/ci-run.sh" --nope 2>&1 || true)" "unknown flag: --nope"

echo
[[ $fail -eq 0 ]] && echo "all evaluation harness tests passed" || echo "SOME EVALUATION HARNESS TESTS FAILED"
exit $fail
