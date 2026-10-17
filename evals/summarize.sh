#!/usr/bin/env bash
# Turns scores.jsonl into a Markdown report: pass rates per model and stage, per criterion, per case, what the runs cost, and (with a
# baseline) which rates dropped. A rate is passes over runs that were actually scored; skipped runs (budget, error) are listed, not hidden.
#   usage: evals/summarize.sh <scores.jsonl> [baseline.json]       prints Markdown;  --json prints the machine-readable summary
set -euo pipefail
json=0; if [[ "${1:-}" == --json ]]; then json=1; shift; fi
scores=${1:?scores.jsonl}; baseline=${2:-}
base_arg=(--argjson baseline 'null'); [[ -n "$baseline" && -f "$baseline" ]] && base_arg=(--slurpfile baseline "$baseline")

summary=$(jq -s "${base_arg[@]}" '
  def pct($n; $d): if $d == 0 then null else (($n * 1000 / $d) | round / 10) end;
  . as $all
  | [ $all[] | select(.pass != null) ] as $ran
  | [ $all[] | select(.pass == null) ] as $skipped
  | { runs: ($all | length), scored: ($ran | length), skipped: ($skipped | length),
      cost_usd: ($ran | map(.cost_usd // 0) | add // 0),
      groups: [ $ran | group_by([.model, .stage])[] |
        { model: .[0].model, stage: .[0].stage, n: length, passed: (map(select(.pass)) | length),
          rate: pct((map(select(.pass)) | length); length),
          mean_cost_usd: ((map(.cost_usd // 0) | add) / length), mean_turns: ((map(.turns // 0) | add) / length),
          criteria: ( [ .[].criteria | to_entries[] | select(.value | type == "boolean") ] | group_by(.key)
                      | map({key: .[0].key, value: pct((map(select(.value)) | length); length)}) | from_entries ) } ],
      cases: [ $ran | group_by([.case, .model, .stage])[] |
        { case: .[0].case, model: .[0].model, stage: .[0].stage, n: length, passed: (map(select(.pass)) | length) } ],
      skipped_runs: [ $skipped[] | {case, stage, model, repeat, reason: .skipped} ] }
  | . + { regressions: ( if $baseline == null then [] else
        [ .groups[] as $g | ($baseline[0].groups[]? | select(.model == $g.model and .stage == $g.stage)) as $b
          | select($g.rate != null and $b.rate != null and ($b.rate - $g.rate) > 20)
          | {model: $g.model, stage: $g.stage, was: $b.rate, now: $g.rate} ] end ) }' "$scores")

if [[ $json -eq 1 ]]; then echo "$summary"; exit 0; fi

jq -r '
  "## Evaluation summary\n",
  "\(.scored) run(s) scored, \(.skipped) skipped, measured cost USD \(.cost_usd * 1000 | round / 1000).\n",
  "| model | stage | passed | rate | mean cost | mean turns |", "|---|---|---|---|---|---|",
  (.groups[] | "| `\(.model)` | \(.stage) | \(.passed)/\(.n) | \(.rate // "n/a")% | USD \(.mean_cost_usd * 1000 | round / 1000) | \(.mean_turns | round) |"),
  "\n### Criteria (share of runs that satisfied each)\n",
  "| model | stage | criterion | rate |", "|---|---|---|---|",
  (.groups[] | . as $g | .criteria | to_entries[] | "| `\($g.model)` | \($g.stage) | \(.key) | \(.value // "n/a")% |"),
  "\n### Per case\n",
  "| case | model | stage | passed |", "|---|---|---|---|",
  (.cases[] | "| `\(.case)` | `\(.model)` | \(.stage) | \(.passed)/\(.n) |"),
  (if (.skipped_runs | length) > 0 then "\n### Not run\n", (.skipped_runs[] | "- `\(.case)` \(.stage) `\(.model)` #\(.repeat): \(.reason)") else empty end),
  (if (.regressions | length) > 0 then "\n### Regressions against the baseline\n", (.regressions[] | "- `\(.model)` \(.stage): \(.was)% -> \(.now)%") else empty end)
' <<<"$summary"
