#!/usr/bin/env bash
# Usage: scripts/sync-fixtures.sh <upstream-commit>
set -euo pipefail
sha="$1"
dest="test/fixtures/openui-spec"
rm -rf "$dest" && mkdir -p "$dest"
gh api "repos/thesysdev/openui/git/trees/$sha?recursive=1" --jq '.tree[] | select(.type=="blob") | .path' |
  grep '^spec/fixtures/1.0/' | while read -r path; do
    out="$dest/${path#spec/fixtures/1.0/}"
    mkdir -p "$(dirname "$out")"
    curl -sfL "https://raw.githubusercontent.com/thesysdev/openui/$sha/$path" -o "$out"
  done
echo "thesysdev/openui spec/fixtures/1.0 at $sha" > "$dest/UPSTREAM"
