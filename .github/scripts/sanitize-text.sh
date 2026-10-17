#!/usr/bin/env bash
# Makes free text inert (see inert.jq). For text that is not part of a report: mutation survivors, review replies, error messages,
# the rationale in a commit message.
#   usage: ... | sanitize-text.sh [--join] [MAX]
#     default  line by line: each input line stays a line (a list), cut to MAX characters (default 300)
#     --join   the whole input becomes ONE line of at most MAX characters, so no input line can start a heading, a table or a fence
set -euo pipefail
join=0
if [[ "${1:-}" == --join ]]; then join=1; shift; fi
max=${1:-300}
[[ "$max" =~ ^[0-9]+$ ]] || max=300
if (( join )); then
  jq -Rrs -L "$(dirname "$0")" --argjson n "$max" 'include "inert"; inert($n) | sub("^ +"; "") | sub(" +$"; "")'
else
  jq -Rr -L "$(dirname "$0")" --argjson n "$max" 'include "inert"; inert($n)'
fi
