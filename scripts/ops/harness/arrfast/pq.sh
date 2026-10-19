#!/usr/bin/env bash
# pq.sh <file.sql> <out.json> — READ-ONLY prod query
head -c 40 "$1" | grep -qi "begin transaction read only" || { echo "REFUSING: not read only"; exit 3; }
npx --yes supabase@2.120.0 db query --linked --output-format json -f "$1" > "$2" 2>&1
echo "exit $? bytes $(wc -c < "$2")"
