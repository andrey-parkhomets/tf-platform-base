#!/usr/bin/env bash
# Which round's result counts for a directory? Round 2 only runs for directories whose round-1 verification failed, so a
# round-2 result, when it exists, supersedes round 1 (even if it failed too: then nothing is committed).
#   usage: pick-round.sh <dir with the downloaded artifacts> <slug>      prints 1 or 2
# Artifacts: <dl>/verify-r<round>-<slug>/<slug>.json
set -euo pipefail
dl=${1:?dir with downloaded artifacts}; slug=${2:?slug}
[[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo 1; exit 0; }
if [[ -f "$dl/verify-r2-$slug/$slug.json" ]]; then echo 2; else echo 1; fi
