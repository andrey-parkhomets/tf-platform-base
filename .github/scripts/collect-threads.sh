#!/usr/bin/env bash
# Collects the unresolved review threads on test files whose author may give the agent instructions
# (admin / maintain / write permission on this repository). Writes JSON to $OUT (default .agent/threads.json):
#   [{"id": "<thread node id>", "path": "...", "line": 12, "comments": [{"author": "x", "body": "..."}]}]
# The text is data for the agent, never instructions to the pipeline. Bodies are truncated, counts are capped.
#   collect-threads.sh <owner/repo> <pr number>        env: GH (gh binary, default `gh`), OUT
set -euo pipefail

repo=${1:?owner/repo}; pr=${2:?pr number}
gh=${GH:-gh}; out=${OUT:-.agent/threads.json}
[[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ && "$pr" =~ ^[0-9]+$ ]] || { echo "bad arguments" >&2; exit 2; }
owner=${repo%%/*}; name=${repo##*/}
mkdir -p "$(dirname "$out")"

# shellcheck disable=SC2016  # GraphQL variables, not shell
query='query($owner:String!,$name:String!,$pr:Int!){repository(owner:$owner,name:$name){pullRequest(number:$pr){
  reviewThreads(first:100){nodes{id isResolved isOutdated path line
    comments(first:20){nodes{author{login} body}}}}}}}'
raw=$("$gh" api graphql -f query="$query" -F owner="$owner" -F name="$name" -F pr="$pr")

allowed_path='^(modules|stacks)/[^/]+/tests/[A-Za-z0-9_.-]+\.(tftest\.hcl|tftest\.json|tfmock\.hcl)$'
candidates=$(jq -c --arg re "$allowed_path" '
  [.data.repository.pullRequest.reviewThreads.nodes[]
   | select(.isResolved == false and (.path | test($re)))]' <<<"$raw")

# Permission of every distinct commenter, from the API (author_association is not precise enough).
declare -A may
for login in $(jq -r '[.[].comments.nodes[].author.login // empty] | unique[]' <<<"$candidates"); do
  [[ "$login" =~ ^[A-Za-z0-9-]+(\[bot\])?$ ]] || continue
  perm=$("$gh" api "repos/$repo/collaborators/$login/permission" --jq .permission 2>/dev/null || echo none)
  case "$perm" in admin|maintain|write) may[$login]=1;; esac
done
allowed_json=$(printf '%s\n' "${!may[@]}" | jq -R . | jq -sc 'map(select(length > 0))')

jq -c --argjson ok "$allowed_json" '
  [.[]
   | { id, path, line: (.line // 0),
       comments: [ .comments.nodes[]
                   | select((.author.login // "") as $a | $ok | index($a))
                   | {author: .author.login, body: (.body | .[0:2000])} ] }
   | select(.comments | length > 0)][:20]' <<<"$candidates" >"$out"
echo "threads for the agent: $(jq length "$out")" >&2
