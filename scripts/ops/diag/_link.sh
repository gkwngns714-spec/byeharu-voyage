#!/usr/bin/env bash
# Shared prelude for the diagnostics in this folder: the supabase CLI on PATH, and the cwd = a clone that holds the project link (supabase/.temp).
export PATH="$HOME/tools/supabase:$PATH"
if [ ! -f supabase/.temp/project-ref ]; then
  for d in "$(git rev-parse --show-toplevel 2>/dev/null)" "$HOME/dev/byeharu-voyage" "$HOME/byeharu-voyage"; do
    [ -n "$d" ] && [ -f "$d/supabase/.temp/project-ref" ] && { cd "$d" || exit 1; break; }
  done
fi
[ -f supabase/.temp/project-ref ] || { echo "no supabase project link found (run 'supabase link' in a clone first)"; exit 1; }
# Supabase CLI v3 refuses SQL in agent mode unless the statement is declared read-only; every query here is a pure SELECT, so say so when the CLI knows the flag (older CLIs do not).
SB_RO=""; supabase db query --help 2>&1 | grep -q -- "--read-only" && SB_RO="--read-only"
# a path node.exe can read (Git Bash on Windows needs cygpath; elsewhere the path is already fine)
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
