#!/usr/bin/env bash
# Renders the agent's prompt or tool list from the shared files in .github/agent/, so that production and the evaluation harness use
# the same text. Values are validated; substitution is plain string replacement (nothing is evaluated).
#   usage: render-agent-config.sh prompt <analyze|coverage|revise|fix>
#          render-agent-config.sh tools  <analyze|write>
#   env:   DIR SLUG BASE_SHA HEAD_SHA            (prompt)
#          PR_NUMBER QUALITY_CHECK               (prompt for the write modes)
#          WORKSPACE                             (tools: absolute path of the checkout)
#          QUALITY_CHECK                         (tools write: absolute path of check-test-quality.sh)
#   AGENT_CONFIG_DIR overrides the directory of the template files (default: .github/agent next to this script's repository)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cfg=${AGENT_CONFIG_DIR:-$here/../agent}
kind=${1:?prompt or tools}; what=${2:?mode}

die() { echo "render-agent-config: $*" >&2; exit 2; }
need() { [[ -n "${!1:-}" ]] || die "$1 is required"; }
valid() { # valid <name> <regex>
  [[ "${!1}" =~ $2 ]] || die "$1 has an unexpected value"
}
abs='^/[A-Za-z0-9._/-]+$'

declare -A V=()
fill() { # fill <template text>: replace every {{KEY}} that has a value, refuse any that is left
  local t=$1 k
  for k in "${!V[@]}"; do t=${t//"{{$k}}"/${V[$k]}}; done
  if [[ "$t" == *"{{"*"}}"* ]]; then die "unfilled placeholder in the template"; fi
  printf '%s\n' "$t"
}
readfile() { local f=$1; [[ -f "$f" ]] || die "missing template $f"; cat "$f"; }

case "$kind" in
  prompt)
    for k in DIR SLUG BASE_SHA HEAD_SHA; do need "$k"; done
    valid DIR '^(modules|stacks)/[A-Za-z0-9][A-Za-z0-9._-]*$'; [[ "$DIR" != *..* ]] || die "DIR has an unexpected value"
    valid SLUG '^[A-Za-z0-9][A-Za-z0-9._-]*$'
    valid BASE_SHA '^[0-9a-f]{7,40}$'; valid HEAD_SHA '^[0-9a-f]{7,40}$'
    V[DIR]=$DIR; V[SLUG]=$SLUG; V[BASE_SHA]=$BASE_SHA; V[HEAD_SHA]=$HEAD_SHA
    case "$what" in
      analyze) fill "$(readfile "$cfg/prompts/analyze.md")" ;;
      coverage|revise|fix)
        need PR_NUMBER; valid PR_NUMBER '^[0-9]+$'; need QUALITY_CHECK; valid QUALITY_CHECK "$abs"
        V[MODE]=$what; V[PR_NUMBER]=$PR_NUMBER; V[QUALITY_CHECK]=$QUALITY_CHECK
        V[MODE_LINE]=$(readfile "$cfg/prompts/write-$what.txt")
        fill "$(readfile "$cfg/prompts/write.md")" ;;
      *) die "unknown prompt mode: $what" ;;
    esac ;;
  tools)
    need WORKSPACE; valid WORKSPACE "$abs"; V[WORKSPACE]=$WORKSPACE
    case "$what" in
      analyze) fill "$(readfile "$cfg/tools/analyze.txt")" ;;
      write) need QUALITY_CHECK; valid QUALITY_CHECK "$abs"; V[QUALITY_CHECK]=$QUALITY_CHECK; fill "$(readfile "$cfg/tools/write.txt")" ;;
      *) die "unknown tools set: $what" ;;
    esac ;;
  *) die "usage: render-agent-config.sh prompt|tools <mode>" ;;
esac
