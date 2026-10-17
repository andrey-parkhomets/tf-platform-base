#!/usr/bin/env bash
# Turns an agent report (JSON written by the model) into one the comment renderers can print without further care: only the
# known keys survive, every string is inert (inert.jq), enumerations are checked, identifiers (paths, skill names, run names) are
# validated and dropped if they do not look right, and lists are bounded.
#   usage: clean-report.sh <report.json>      prints the cleaned JSON; prints {} if the file is not a JSON object
set -euo pipefail
f=${1:?report.json}
jq -L "$(dirname "$0")" '
include "inert";
def s($n): if type == "string" then inert($n) else empty end;
def strs($max; $n): [ (.[]? | s($n)) ] | .[:$max];
if type != "object" then {} else
{
  dir:        ((.dir | ident(120)) // ""),
  decision:   ((.decision // "") | oneof(["tests_needed","tests_need_update","no_change_needed","skipped","created","updated"]; "unknown")),
  rationale:  ((.rationale // "") | s(600)),
  changed_behaviours: ((.changed_behaviours // []) | strs(10; 300)),
  affected_callers:   [ (.affected_callers // [])[:10][] | ident(120) ],
  test_plan:          ((.test_plan // []) | strs(12; 400)),
  skills_used:        [ (.skills_used // [])[:10][] | skillname ],
  not_covered:        ((.not_covered // []) | strs(8; 300)),
  tests: [ (.tests // [])[:10][] | select(type == "object") |
           { file: ((.file | ident(200)) // ""), runs: [ (.runs // [])[:20][] | slugword(100) ] } ],
  threads: [ (.threads // [])[:20][] | select(type == "object") |
             { id: ((.id | slugword(120)) // ""), outcome: ((.outcome // "") | oneof(["addressed","declined"]; "declined")), reply: ((.reply // "") | s(800)) } ],
  findings: [ (.findings // [])[:20][] | select(type == "object") |
              { severity: ((.severity // "info") | oneof(["high","medium","low","info"]; "info")),
                source:   ((.source // "agent") | oneof(["agent","checkov"]; "agent")),
                file:     ((.file // "") | ident(200) // ""),
                line:     (if (.line | type) == "number" and .line >= 0 and .line < 1000000 then (.line | floor) else 0 end),
                title:    ((.title // "") | s(200)),
                detail:   ((.detail // "") | s(900)) } ]
}
end' "$f" 2>/dev/null || echo '{}'
