#!/usr/bin/env bash
# Runs ONE stage of the agent on ONE case with ONE model, the way production does (same rendered prompt and tool list, same agent
# definition), and stores what came out. It does not score anything: scoring needs Terraform and runs in a job without the key.
#
#   usage: run-stage.sh <analysis|writer> <case dir> <model> <repeat> <out dir>
#   env:   CLAUDE_BIN       the Claude Code CLI (default: claude)
#          MAX_TURNS        turn limit (default: 30 analysis, 60 writer: the production defaults)
#          AGENT_REF_DIR    the branch under test, as data (see prepare-case.sh)
#          EVAL_TMP         where working trees are made (default: $RUNNER_TEMP or /tmp)
#   out:   <out dir>/{run.json, result.json, report.json, tests.patch, guard.txt}
#          run.json: {case, stage, model, repeat, cost_usd, turns, duration_ms, is_error, denials, model_used, finished}
set -uo pipefail

stage=${1:?analysis or writer}; case_dir=${2:?}; model=${3:?}; rep=${4:?}; out=${5:?}
here=$(cd "$(dirname "$0")" && pwd)
repo=${EVAL_REPO:-$(cd "$here/../.." && pwd)}
scripts=${EVAL_SCRIPTS:-$repo/.github/scripts}
claude=${CLAUDE_BIN:-claude}

case "$stage" in
  analysis) mode=analyze;  tools='analyze'; turns=${MAX_TURNS:-30} ;;
  writer)   mode=coverage; tools='write'; turns=${MAX_TURNS:-60} ;;
  *) echo "run-stage: unknown stage $stage" >&2; exit 2 ;;
esac
[[ "$model" =~ ^[A-Za-z0-9._-]+$ && "$rep" =~ ^[0-9]+$ && "$turns" =~ ^[0-9]+$ ]] || { echo "run-stage: bad argument" >&2; exit 2; }

id=$(jq -er .id "$case_dir/case.json")
mkdir -p "$out"
wt="${EVAL_TMP:-${RUNNER_TEMP:-/tmp}}/eval-$id-$stage-${model//[^A-Za-z0-9]/_}-$rep-$$"
trap 'git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true' EXIT

info=$("$here/prepare-case.sh" "$case_dir" "$wt" --for "$stage") || { echo "run-stage: could not prepare $id" >&2; exit 2; }
dir=$(jq -r .dir <<<"$info"); slug=$(jq -r .slug <<<"$info"); base=$(jq -r .base <<<"$info"); head=$(jq -r .head <<<"$info")
ws=$(cd "$wt" && pwd -P)

export DIR=$dir SLUG=$slug BASE_SHA=$base HEAD_SHA=$head PR_NUMBER=0 WORKSPACE=$ws
export QUALITY_CHECK="$scripts/check-test-quality.sh"
export AGENT_CONFIG_DIR="${AGENT_REF_DIR:-$repo}/.github/agent"
prompt=$("$scripts/render-agent-config.sh" prompt "$mode") || exit 2
allowed=$("$scripts/render-agent-config.sh" tools "$tools") || exit 2
unset DIR SLUG BASE_SHA HEAD_SHA PR_NUMBER WORKSPACE QUALITY_CHECK AGENT_CONFIG_DIR

( cd "$wt" && CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=${CLAUDE_CODE_SUBPROCESS_ENV_SCRUB:-1} timeout "${STAGE_TIMEOUT:-1500}" \
    "$claude" -p "$prompt" --agent tf-test-agent --model "$model" --max-turns "$turns" \
    --allowedTools "$allowed" --disallowedTools "WebFetch,WebSearch" --output-format json --no-session-persistence \
    >"$out/result.raw" 2>"$out/stderr.log" )
rc=$?
finished=$([[ $rc -eq 0 ]] && echo true || echo false)

# the CLI prints one result object (or a list of messages ending in one)
jq -c 'if type == "array" then (map(select(.type == "result")) | last) else . end' "$out/result.raw" >"$out/result.json" 2>/dev/null || echo '{}' >"$out/result.json"
rm -f "$out/result.raw"

[[ -f "$wt/.agent/report/$slug.json" ]] && cp "$wt/.agent/report/$slug.json" "$out/report.json"
# What changed in the tree, as production's "Collect patch" and the path guard see it
( cd "$wt" && "$scripts/guard-paths.sh" >"$out/guard.txt" 2>&1; echo $? >>"$out/guard.txt" )
( cd "$wt" && git ls-files -z --others --exclude-standard -- ':(glob)modules/*/tests/*' ':(glob)stacks/*/tests/*' | xargs -0 -r git add -N -- \
    && git diff --binary -- ':(glob)modules/*/tests/*' ':(glob)stacks/*/tests/*' ) >"$out/tests.patch" 2>/dev/null

jq -nc --arg case "$id" --arg stage "$stage" --arg model "$model" --argjson rep "$rep" --argjson finished "$finished" \
  --slurpfile r "$out/result.json" \
  '{case: $case, stage: $stage, model: $model, repeat: $rep, finished: $finished,
    cost_usd: ($r[0].total_cost_usd // 0), turns: ($r[0].num_turns // 0), duration_ms: ($r[0].duration_ms // 0),
    is_error: ($r[0].is_error // true), denials: (($r[0].permission_denials // []) | length),
    model_used: (($r[0].modelUsage // {}) | keys | join(","))}' >"$out/run.json"
