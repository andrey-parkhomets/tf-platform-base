#!/usr/bin/env bash
# Reproduces a CI evaluation from a terminal: starts the tf-ai-eval workflow, waits for it, downloads the scores and prints the
# summary. Needs the gh CLI, logged in with rights to run workflows. Spends real money (model key, environment tf-ai-agent).
#
#   evals/ci-run.sh --models claude-sonnet-5-5 --stage analysis --repeats 1 --budget 3
#   evals/ci-run.sh --dry-run ...        prints the workflow command and exits (nothing is started)
#
# flags (all optional): --ref (default main) --models (claude-haiku-5-5 | claude-sonnet-5-5 | both, default claude-haiku-5-5)
#   --stage (analysis | writer | both, default both) --repeats (1-3, default 1) --cases "id1,id2" --budget USD per model (default 5)
#   --cli-version --out DIR (default eval-results/<run id>) --dry-run
set -euo pipefail

ref=main models=claude-haiku-5-5 stage=both repeats=1 cases="" budget=5 cli="" out="" dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) ref=$2; shift 2 ;; --models) models=$2; shift 2 ;; --stage) stage=$2; shift 2 ;; --repeats) repeats=$2; shift 2 ;;
    --cases) cases=$2; shift 2 ;; --budget) budget=$2; shift 2 ;; --cli-version) cli=$2; shift 2 ;; --out) out=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done
[[ "$repeats" =~ ^[1-3]$ ]] || { echo "--repeats must be 1-3" >&2; exit 2; }
[[ "$budget" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "--budget must be a number (USD per model)" >&2; exit 2; }

args=(-f "ref=$ref" -f "models=$models" -f "stage=$stage" -f "repeats=$repeats" -f "budget_usd=$budget")
[[ -n "$cases" ]] && args+=(-f "cases=$cases")
[[ -n "$cli" ]] && args+=(-f "cli_version=$cli")
if [[ $dry == 1 ]]; then echo "gh workflow run tf-ai-eval.yml ${args[*]}"; exit 0; fi

before=$(gh run list --workflow tf-ai-eval.yml --event workflow_dispatch -L 1 --json databaseId -q '.[0].databaseId // 0')
gh workflow run tf-ai-eval.yml "${args[@]}"
id=$before
for _ in $(seq 1 30); do
  sleep 4
  id=$(gh run list --workflow tf-ai-eval.yml --event workflow_dispatch -L 1 --json databaseId -q '.[0].databaseId // 0')
  [[ "$id" != "$before" ]] && break
done
[[ "$id" != "$before" ]] || { echo "the run did not appear" >&2; exit 1; }
echo "run $id: $(gh run view "$id" --json url -q .url)"
gh run watch "$id" --exit-status >/dev/null || echo "the run did not succeed; partial results are still downloaded" >&2

out=${out:-eval-results/$id}
mkdir -p "$out"
gh run download "$id" -D "$out" || true
# summarize.sh prints the same report that the workflow writes to its step summary.
if [[ -f "$out/eval-scores/scores.jsonl" ]]; then
  base=""; [[ -f evals/baseline.json ]] && base=evals/baseline.json
  "$(dirname "$0")/summarize.sh" "$out/eval-scores/scores.jsonl" ${base:+"$base"}
else
  echo "no scores found under $out (see the run's logs)" >&2
  exit 1
fi
