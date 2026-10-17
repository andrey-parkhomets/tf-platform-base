#!/usr/bin/env bash
# After the agent's tests are committed: reply to, and where addressed resolve, the review threads that the agent
# reports on. Only thread ids that were collected by collect-threads.sh are accepted; the reply text is cleaned.
#   resolve-threads.sh <report.json> <threads.json> <commit sha>        env: GH (default `gh`)
# Report format: "threads": [{"id": "...", "outcome": "addressed" | "declined", "reply": "..."}]
set -euo pipefail

report=${1:?report}; threads=${2:?threads}; sha=${3:?sha}
gh=${GH:-gh}
[[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "bad sha" >&2; exit 2; }
[[ -s "$report" && -s "$threads" ]] || exit 0

# shellcheck disable=SC2016  # GraphQL variables, not shell
reply_q='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{id}}}'
# shellcheck disable=SC2016
resolve_q='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{id}}}'

jq -c '(.threads // [])[:20][]' "$report" 2>/dev/null | while IFS= read -r item; do
  id=$(jq -r '.id // ""' <<<"$item"); outcome=$(jq -r '.outcome // ""' <<<"$item")
  jq -e --arg id "$id" 'any(.[]; .id == $id)' "$threads" >/dev/null || { echo "skip unknown thread id" >&2; continue; }
  text=$(jq -r '.reply // ""' <<<"$item" | head -c 800 | tr -d '\r' | sed -e 's/</‹/g' -e 's/>/›/g' -e 's/@/@\xe2\x80\x8b/g')
  case "$outcome" in
    addressed) body="Addressed in ${sha:0:7}. ${text}";;
    declined)  body="Not changed. ${text}";;
    *) continue;;
  esac
  "$gh" api graphql -f query="$reply_q" -F t="$id" -F b="$body" >/dev/null
  [[ "$outcome" == addressed ]] && "$gh" api graphql -f query="$resolve_q" -F t="$id" >/dev/null
  echo "$outcome: $id"
done
