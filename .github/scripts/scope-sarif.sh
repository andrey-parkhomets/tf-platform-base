#!/usr/bin/env bash
# Scopes a Checkov SARIF to the directories a pull request changes, and says which findings are NEW in the pull request.
#
#   usage: scope-sarif.sh [--summary] <head.sarif> <base.sarif|-> <dir> [<dir>...]
#     head.sarif  the scan of the pull request's head commit (the whole repository: some checks are graph checks that need the stack
#                 around a module, so the scan itself is never narrowed; only its results are filtered)
#     base.sarif  the scan of the base commit, or "-" / a missing file when there is none
#     dir         changed directories (modules/<name> or stacks/<name>); a result is in scope when its file is below one of them
#   stdout: the SARIF with only the in-scope results, each carrying properties.scope = new | existing | unknown ("unknown" when there
#           is no baseline), and runs[0].properties.checkovScope = {total, in_scope, new, existing, baseline}.
#           With --summary: only that summary object.
#   exit: 0 ok, 2 bad arguments, 1 the head file is not a SARIF (nothing on stdout)
#
# New vs existing: the SARIF has no fingerprints and line numbers move, so a finding is identified by rule + file + the first line of
# the resource it is reported on (for example `resource "azurerm_key_vault" "this" {`). Same identity on the base = existing. Moving
# or renaming a resource makes its findings look new again; that is accepted.
set -euo pipefail

summary=0
if [[ "${1:-}" == --summary ]]; then summary=1; shift; fi
head=${1:?head.sarif}; base=${2:?base.sarif or -}; shift 2
[[ $# -ge 1 ]] || { echo "scope-sarif: at least one directory is required" >&2; exit 2; }
for d in "$@"; do
  [[ "$d" =~ ^(modules|stacks)/[A-Za-z0-9][A-Za-z0-9._-]*$ && "$d" != *..* ]] || { echo "scope-sarif: bad directory: $d" >&2; exit 2; }
done
dirs=$(printf '%s\n' "$@" | jq -R . | jq -sc .)

jq -e '.runs | type == "array"' "$head" >/dev/null 2>&1 || exit 1

has_base=false; base_arg=(--argjson base 'null')
if [[ "$base" != "-" && -f "$base" ]] && jq -e '.runs | type == "array"' "$base" >/dev/null 2>&1; then
  has_base=true; base_arg=(--slurpfile base "$base")
fi

jq --argjson dirs "$dirs" --argjson has_base "$has_base" --argjson summary "$summary" "${base_arg[@]}" '
  def norm:    ltrimstr("/");
  def uri:     (.locations[0].physicalLocation.artifactLocation.uri // "") | norm;
  def header:  ((.locations[0].physicalLocation.region.snippet.text // "") | split("\n")[0] | gsub("^\\s+|\\s+$"; ""));
  def key:     "\(.ruleId // "")|\(uri)|\(header)";
  def inscope: uri as $u | any($dirs[]; . as $d | $u | startswith($d + "/"));

  ( if $has_base then
      ( [ $base[0].runs[]?.results[]? | {key: key, value: true} ] | from_entries )
    else {} end ) as $basekeys
  | ( [ .runs[]?.results[]? ] ) as $all
  | ( $all | map(select(inscope)) ) as $in
  | ( $in | map(. + {properties: ((.properties // {}) +
        {scope: (if $has_base then (if $basekeys[key] then "existing" else "new" end) else "unknown" end)})}) ) as $scoped
  | { total: ($all | length),
      in_scope: ($scoped | length),
      new: ($scoped | map(select(.properties.scope == "new")) | length),
      existing: ($scoped | map(select(.properties.scope == "existing")) | length),
      baseline: $has_base } as $sum
  | if $summary == 1 then $sum
    else .runs |= map(.results = [ .results[]? | select(inscope) | . + {properties: ((.properties // {}) +
              {scope: (if $has_base then (if $basekeys[key] then "existing" else "new" end) else "unknown" end)})} ])
         | .runs[0].properties = ((.runs[0].properties // {}) + {checkovScope: $sum})
    end
' "$head"
