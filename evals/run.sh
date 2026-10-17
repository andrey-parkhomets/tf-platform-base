#!/usr/bin/env bash
# Runs the agent on the evaluation cases and stores what it produced (run-stage.sh). Needs the model key; does NOT score (score.sh does,
# in a job without the key). Budget-aware: a pre-flight estimate must fit the budget, and the loop stops when the REAL cost, read from
# each result, reaches it. Runs are ordered repeat by repeat, so a stop leaves complete earlier repeats rather than half of everything.
#
#   usage: evals/run.sh --out DIR [--stage analysis|writer|both] [--models "m1 m2"] [--repeats N] [--cases id,id|all]
#                       [--budget USD] [--force] [--dry-run]
#   env:   CASES_DIR (default: <AGENT_REF_DIR>/evals/cases), CLAUDE_BIN, AGENT_REF_DIR (see prepare-case.sh)
#   exit:  0 done (also when the budget stopped it; the skipped runs are recorded), 3 the estimate exceeds the budget, 2 bad arguments,
#          4 not a single run finished (nothing was spent for nothing: the messages are printed)
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=${EVAL_REPO:-$(cd "$here/.." && pwd)}
cases_dir=${CASES_DIR:-${AGENT_REF_DIR:-$repo}/evals/cases}

out=""; stage=both; models="claude-haiku-5-5"; repeats=1; want=all; budget=5; force=0; dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out=$2; shift 2 ;; --stage) stage=$2; shift 2 ;; --models) models=$2; shift 2 ;; --repeats) repeats=$2; shift 2 ;;
    --cases) want=$2; shift 2 ;; --budget) budget=$2; shift 2 ;; --force) force=1; shift ;; --dry-run) dry=1; shift ;;
    *) echo "run.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ -n "$out" || $dry -eq 1 ]] || { echo "run.sh: --out is required" >&2; exit 2; }
[[ "$stage" =~ ^(analysis|writer|both)$ && "$repeats" =~ ^[1-9][0-9]*$ && "$budget" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "run.sh: bad stage, repeats or budget" >&2; exit 2; }
for m in $models; do [[ "$m" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "run.sh: bad model $m" >&2; exit 2; }; done
[[ "$want" == all || "$want" =~ ^[a-z0-9,-]+$ ]] || { echo "run.sh: bad --cases" >&2; exit 2; }
# absolute: the stages change directory
[[ $dry -eq 1 ]] || { mkdir -p "$out" && out=$(cd "$out" && pwd); }

# the cases and the stages each one has
mapfile -t case_ids < <(for d in "$cases_dir"/*/; do [[ -f "$d/case.json" ]] && jq -r .id "$d/case.json"; done | sort)
selected=()
for id in "${case_ids[@]}"; do
  if [[ "$want" == all || ",$want," == *",$id,"* ]]; then selected+=("$id"); fi
done
[[ ${#selected[@]} -gt 0 ]] || { echo "run.sh: no case matches" >&2; exit 2; }
if [[ "$want" != all ]]; then
  IFS=, read -ra asked <<<"$want"
  for a in "${asked[@]}"; do [[ " ${selected[*]} " == *" $a "* ]] || { echo "run.sh: unknown case $a" >&2; exit 2; }; done
fi

has_stage() { jq -e --arg s "$2" '.stages[$s] != null' "$cases_dir/$1/case.json" >/dev/null 2>&1; }

# the plan, repeat by repeat
plan=()
for ((rep = 1; rep <= repeats; rep++)); do
  for id in "${selected[@]}"; do
    for m in $models; do
      for s in analysis writer; do
        [[ "$stage" == both || "$stage" == "$s" ]] && has_stage "$id" "$s" && plan+=("$rep|$id|$m|$s")
      done
    done
  done
done

est_of() { jq -r --arg m "$1" --arg s "$2" '(.[$m][$s] // ._default[$s])' "$here/costs.json"; }
estimate=0
for p in "${plan[@]}"; do IFS='|' read -r rep id m s <<<"$p"; estimate=$(awk -v a="$estimate" -v b="$(est_of "$m" "$s")" 'BEGIN{printf "%.4f", a+b}'); done
echo "plan: ${#plan[@]} run(s), estimated cost USD $estimate, budget USD $budget"
if awk -v e="$estimate" -v b="$budget" 'BEGIN{exit !(e > b)}' && [[ $force -eq 0 ]]; then
  echo "run.sh: the estimate exceeds the budget. Reduce --repeats, --models or --cases, raise --budget, or use --force." >&2
  exit 3
fi
if [[ $dry -eq 1 ]]; then
  printf '%s\n' "${plan[@]}" | awk -F'|' '{n[$3" "$4]++} END {for (k in n) print "  " k ": " n[k] " run(s)"}' | sort
  echo "dry run: nothing was run"; exit 0
fi

: >"$out/runs.jsonl"
spent=0; stopped=0
for p in "${plan[@]}"; do
  IFS='|' read -r rep id m s <<<"$p"
  if [[ $stopped -eq 1 ]]; then
    jq -nc --arg c "$id" --arg s "$s" --arg m "$m" --argjson r "$rep" '{case: $c, stage: $s, model: $m, repeat: $r, skipped: "budget"}' >>"$out/runs.jsonl"
    continue
  fi
  rd="$out/$m/$id/$s-$rep"
  echo "run  $m  $id  $s  #$rep"
  if "$here/lib/run-stage.sh" "$s" "$cases_dir/$id" "$m" "$rep" "$rd" && [[ -s "$rd/run.json" ]]; then
    cat "$rd/run.json" >>"$out/runs.jsonl"
    spent=$(awk -v a="$spent" -v b="$(jq -r .cost_usd "$rd/run.json")" 'BEGIN{printf "%.4f", a+b}')
  else
    jq -nc --arg c "$id" --arg s "$s" --arg m "$m" --argjson r "$rep" '{case: $c, stage: $s, model: $m, repeat: $r, skipped: "error"}' >>"$out/runs.jsonl"
  fi
  if awk -v a="$spent" -v b="$budget" 'BEGIN{exit !(a >= b)}'; then
    echo "run.sh: budget reached (USD $spent of $budget); the remaining runs are skipped"; stopped=1
  fi
done
echo "spent: USD $spent"
# a harness that spends nothing and reports success hides its own failure
started=$(jq -s '[.[] | select(.skipped == null)] | length' "$out/runs.jsonl"); unfinished=$(jq -s '[.[] | select(.skipped == null and .finished == false)] | length' "$out/runs.jsonl")
errors=$(jq -s '[.[] | select(.skipped == "error")] | length' "$out/runs.jsonl")
if [[ $unfinished -gt 0 || $errors -gt 0 ]]; then
  echo "run.sh: $unfinished run(s) did not finish and $errors could not start. First messages:" >&2
  jq -r 'select(.skipped == "error" or .finished == false) | "  \(.case) \(.stage) \(.model) #\(.repeat): \(.error // .skipped // "no message")"' "$out/runs.jsonl" | head -5 >&2
fi
if [[ $((started - unfinished)) -le 0 ]]; then echo "run.sh: no run finished" >&2; exit 4; fi
