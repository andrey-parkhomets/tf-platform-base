#!/usr/bin/env bash
# Scores the runs that run.sh stored. Needs Terraform (it runs production's verification on what the writer produced) and must run in a
# job WITHOUT the model key: the tests it runs were written by a model that read case data.
#
#   usage: evals/score.sh --runs DIR --out FILE.jsonl [--index FILE]     (the index defaults to DIR/runs.jsonl)
#   env:   CASES_DIR (default: <AGENT_REF_DIR>/evals/cases), EVAL_TMP, AGENT_REF_DIR
#   Every writer run is scored as the FIRST attempt: patch applied, tests formatted by `terraform fmt` (production's verify does the
#   same, so a formatting slip is not a failure), then verify-module.sh (static quality check, fmt, init, validate, test, mutation check).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=${EVAL_REPO:-$(cd "$here/.." && pwd)}
scripts=${EVAL_SCRIPTS:-$repo/.github/scripts}
cases_dir=${CASES_DIR:-${AGENT_REF_DIR:-$repo}/evals/cases}
runs=""; out=""; index=""
while [[ $# -gt 0 ]]; do case "$1" in --runs) runs=$2; shift 2 ;; --out) out=$2; shift 2 ;; --index) index=$2; shift 2 ;; *) echo "score.sh: unknown argument $1" >&2; exit 2 ;; esac; done
index=${index:-$runs/runs.jsonl}
[[ -d "$runs" && -n "$out" && -s "$index" ]] || { echo "score.sh: --runs must be a directory with an index (runs.jsonl or --index), and --out is required" >&2; exit 2; }
: >"$out"

allowed_paths='^(modules|stacks)/[^/]+/tests/[A-Za-z0-9_.-]+\.(tftest\.hcl|tftest\.json|tfmock\.hcl)$'

while IFS= read -r line; do
  id=$(jq -r .case <<<"$line"); stage=$(jq -r .stage <<<"$line"); model=$(jq -r .model <<<"$line"); rep=$(jq -r .repeat <<<"$line")
  [[ "$id" =~ ^[a-z0-9-]+$ && "$stage" =~ ^(analysis|writer)$ && "$model" =~ ^[A-Za-z0-9._-]+$ && "$rep" =~ ^[0-9]+$ ]] || continue
  if [[ "$(jq -r '.skipped // empty' <<<"$line")" != "" ]]; then
    jq -c '. + {pass: null}' <<<"$line" >>"$out"; continue
  fi
  cdir="$cases_dir/$id"; rd="$runs/$model/$id/$stage-$rep"
  if [[ "$stage" == analysis ]]; then
    crit=$("$here/lib/score-analysis.sh" "$cdir" "$rd") || crit='{"pass": false}'
  else
    wt="${EVAL_TMP:-${RUNNER_TEMP:-/tmp}}/score-$id-${model//[^A-Za-z0-9]/_}-$rep-$$"
    crit='{"pass": false, "patch_present": false}'
    if [[ -s "$rd/tests.patch" ]] && info=$("$here/lib/prepare-case.sh" "$cdir" "$wt" 2>/dev/null); then
      dir=$(jq -r .dir <<<"$info"); slug=$(jq -r .slug <<<"$info")
      # the paths are re-checked here, as production's verify and commit jobs do
      bad=$(git -C "$wt" apply --numstat "$rd/tests.patch" 2>/dev/null | cut -f3 | grep -Ev "$allowed_paths" || true)
      if [[ -z "$bad" ]] && git -C "$wt" apply "$rd/tests.patch" 2>/dev/null; then
        [[ -d "$wt/$dir/tests" ]] && (cd "$wt" && terraform fmt -recursive "$dir/tests" >/dev/null 2>&1)
        (cd "$wt" && ROUND=1 "$scripts/verify-module.sh" "$dir" >/dev/null 2>&1) || true
        if [[ -f "$wt/.agent/verify/$slug.json" ]]; then
          crit=$("$here/lib/score-writer.sh" "$cdir" "$rd" "$wt/.agent/verify/$slug.json" "$wt/$dir/tests") || crit='{"pass": false}'
        fi
      else
        crit='{"pass": false, "patch_present": true, "guard_ok": false}'
      fi
    elif [[ ! -s "$rd/tests.patch" ]]; then
      crit=$("$here/lib/score-writer.sh" "$cdir" "$rd" <(echo '{"ok": false, "results": {}, "summary": "", "mutation": {}}') /nonexistent 2>/dev/null) || crit='{"pass": false, "patch_present": false}'
    fi
    rm -rf -- "$wt"
  fi
  jq -c --argjson crit "$crit" '{case, stage, model, repeat, cost_usd, tokens, turns, duration_ms, denials, model_used, finished} + {criteria: $crit, pass: $crit.pass}' <<<"$line" >>"$out"
done <"$index"
echo "scored $(wc -l <"$out" | tr -d ' ') run(s) into $out"
