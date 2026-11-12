#!/usr/bin/env bash
# pq.sh <file.sql> — READ-ONLY prod query (the first statement of the file must be: begin transaction read only)
node "$(dirname "$0")/../read-only.mjs" "$1" || exit 3   # the one judge of "read only": first statement, last statement, no write verb
F=$(cygpath -w "$(realpath "$1")")
cd ~/dev/byeharu-voyage && npx --yes supabase@2.120.0 db query --linked --output-format json -f "$F" 2>&1
