#!/usr/bin/env bash
# pq.sh <file.sql> <out.json> — READ-ONLY prod query
node "$(dirname "$0")/../read-only.mjs" "$1" || exit 3   # the one judge of "read only": first statement, last statement, no write verb
npx --yes supabase@2.120.0 db query --linked --output-format json -f "$1" > "$2" 2>&1
echo "exit $? bytes $(wc -c < "$2")"
