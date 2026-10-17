#!/usr/bin/env bash
# Local sanity check for generated tests: apply simple mutations to a module copy and require
# that `terraform test` fails for each one. A surviving mutant means the tests miss that behaviour.
# Usage: mutation-check.sh <module dir>      (runs in a temporary copy, never edits the repo)
set -uo pipefail
dir=${1:?module dir}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cp -R "$dir/." "$work/"; rm -rf "$work/.terraform"
(cd "$work" && TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-}" terraform init -backend=false -input=false -lockfile=readonly >/dev/null 2>&1) || { echo "init failed"; exit 2; }

survived=0; total=0
mutate() { # mutate <description> <sed expression> <file>
  local desc=$1 expr=$2 file=$3
  cp "$work/$file" "$work/$file.orig"
  sed -E -i.bak "$expr" "$work/$file"
  if cmp -s "$work/$file" "$work/$file.orig"; then rm -f "$work/$file.bak" "$work/$file.orig"; return; fi  # nothing to mutate
  total=$((total + 1))
  if (cd "$work" && terraform test -no-color >/dev/null 2>&1); then
    echo "SURVIVED: $desc"; survived=$((survived + 1))
  else
    echo "killed:   $desc"
  fi
  mv "$work/$file.orig" "$work/$file"; rm -f "$work/$file.bak"
}

for f in $(cd "$work" && find . -maxdepth 1 -name '*.tf' ! -name 'variables.tf' ! -name 'versions.tf' ! -name 'outputs.tf' -exec basename {} \;); do
  mutate "flip true->false in $f"          '0,/= true/s//= false/'                          "$f"
  mutate "flip false->true in $f"          '0,/= false/s//= true/'                          "$f"
  mutate "change first string literal in $f" '0,/= "([A-Za-z0-9._-]+)"/s//= "mutated"/'     "$f"
  # shellcheck disable=SC2016  # the sed expression is literal on purpose
  mutate "change prefix in names in $f"    '0,/"([a-z]+)-\$\{/s//"x\1-${/'                    "$f"
  mutate "drop a tags assignment in $f"    '0,/tags += var\.tags/s//tags = {}/'              "$f"
done
echo "mutants: $total, survived: $survived"
exit $((survived > 0))
