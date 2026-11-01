#!/usr/bin/env bash
# Shared prelude for the diagnostics in this folder: the supabase CLI on PATH, and the cwd = a clone that holds the project link (supabase/.temp).
export PATH="$HOME/tools/supabase:$PATH"
if [ ! -d supabase/.temp ]; then
  for d in "$(git rev-parse --show-toplevel 2>/dev/null)" "$HOME/dev/byeharu-voyage" "$HOME/byeharu-voyage"; do
    [ -n "$d" ] && [ -d "$d/supabase/.temp" ] && { cd "$d" || exit 1; break; }
  done
fi
[ -d supabase/.temp ] || { echo "no supabase project link found (run 'supabase link' in a clone first)"; exit 1; }
# a path node.exe can read (Git Bash on Windows needs cygpath; elsewhere the path is already fine)
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
