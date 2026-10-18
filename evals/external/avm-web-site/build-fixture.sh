#!/usr/bin/env bash
# Builds the fixture repository for the cases in this directory: Azure/terraform-azurerm-avm-res-web-site at a pinned commit, laid out the
# way this repository expects (the module under modules/web-site, its own tests/ and nested modules/ below it) and committed with a fixed
# identity and date, so the commit id is the same on every machine. The cases name that id as their base.
#
#   usage: build-fixture.sh <empty target directory>      prints the commit id
#   env:   AVM_SOURCE   a local clone to copy from instead of cloning from GitHub (it must contain the pinned commit)
set -euo pipefail
pin=56c704e9f44002a46a71226d3c19f3915e1865c0
expected=${EXPECTED_FIXTURE_COMMIT:-}
target=${1:?target directory}
[[ ! -e "$target" || -z "$(ls -A "$target" 2>/dev/null)" ]] || { echo "build-fixture: $target is not empty" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
src=${AVM_SOURCE:-https://github.com/Azure/terraform-azurerm-avm-res-web-site.git}
git clone -q "$src" "$tmp/src"
git -C "$tmp/src" checkout -q --detach "$pin"
mkdir -p "$target/modules/web-site"
git -C "$tmp/src" archive "$pin" | tar -x -C "$target/modules/web-site"
# the ignore rules of this repository that the pipeline relies on: its own working files must not look like changes to the path guard
printf '.agent/\n.codegraph/\n' >"$target/.gitignore"
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@localhost GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@localhost
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
git -C "$target" init -q -b main
git -C "$target" -c core.autocrlf=false -c core.safecrlf=false -c commit.gpgsign=false add -A
git -C "$target" -c core.autocrlf=false -c commit.gpgsign=false commit -q -m "terraform-azurerm-avm-res-web-site@$pin as modules/web-site"
id=$(git -C "$target" rev-parse HEAD)
[[ -z "$expected" || "$id" == "$expected" ]] || { echo "build-fixture: commit $id, expected $expected (git or tar output differs?)" >&2; exit 3; }
echo "$id"
