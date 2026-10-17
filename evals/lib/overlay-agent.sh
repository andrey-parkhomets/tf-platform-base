#!/usr/bin/env bash
# Puts the agent definition under test into a case's working tree, treating the branch it comes from as DATA.
#
# The evaluation workflow runs from the default branch with the model key, and evaluates the agent of any branch. So it must never
# run code from that branch, and it must not load anything from it that could run code: no settings, no hooks, no MCP servers. Only
#   .claude/agents/tf-test-agent.md        frontmatter keys: name, description, tools, skills
#   .claude/skills/<name>/...              SKILL.md frontmatter keys: name, description, metadata
# are copied; everything else under .claude/ is ignored. Symlinks and files outside those two directories are never followed.
#
#   usage: overlay-agent.sh <ref checkout> <working tree>
#   exit:  0 copied, 2 refused (the reason is on stderr)
set -euo pipefail
src=${1:?directory with the branch under test}; dst=${2:?working tree}
agent_keys='^(name|description|tools|skills)$'
skill_keys='^(name|description|metadata)$'

die() { echo "overlay-agent: $*" >&2; exit 2; }

frontmatter_keys() { # prints the top-level keys of the YAML frontmatter of a markdown file
  awk '/^---[[:space:]]*$/ { c++; next } c == 1 && /^[A-Za-z_][A-Za-z0-9_-]*:/ { sub(/:.*/, ""); print } c == 2 { exit }' "$1"
}
check_file() { # check_file <file> <allowed key regex>
  local f=$1 re=$2 k first
  [[ -f "$f" && ! -L "$f" ]] || die "$f is not a regular file"
  first=$(head -1 "$f"); [[ "$first" =~ ^---[[:space:]]*$ ]] || die "$f has no frontmatter"
  while IFS= read -r k; do
    [[ "$k" =~ $re ]] || die "$f: frontmatter key '$k' is not allowed (it could change what the agent is allowed to do)"
  done < <(frontmatter_keys "$f")
}

agent="$src/.claude/agents/tf-test-agent.md"
check_file "$agent" "$agent_keys"
# the agent must not widen its own tool list beyond what production grants it
grep -qE '^tools:' "$agent" || die "$agent declares no tools"

[[ -d "$src/.claude/skills" && ! -L "$src/.claude/skills" ]] || die "no .claude/skills directory"
while IFS= read -r -d '' s; do
  [[ -L "$s" ]] && die "$s is a symlink"
  case "$s" in *"/SKILL.md") check_file "$s" "$skill_keys" ;; esac
done < <(find "$src/.claude/skills" -print0)

rm -rf "$dst/.claude"; mkdir -p "$dst/.claude/agents" "$dst/.claude/skills"
cp "$agent" "$dst/.claude/agents/tf-test-agent.md"
cp -R "$src/.claude/skills/." "$dst/.claude/skills/"
