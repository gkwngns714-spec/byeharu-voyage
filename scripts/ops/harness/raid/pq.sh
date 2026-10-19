#!/usr/bin/env bash
# pq.sh <file.sql> — READ-ONLY prod query (file must begin with: begin transaction read only)
head -c 40 "$1" | grep -qi "begin transaction read only" || { echo "REFUSING: not read only"; exit 3; }
F=$(cygpath -w "$(realpath "$1")")
cd ~/dev/byeharu-voyage && npx --yes supabase@2.120.0 db query --linked --output-format json -f "$F" 2>&1
