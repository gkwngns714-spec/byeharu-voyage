#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# supabase-snapshot.sh — the disposable stack's applied chain, kept between CI runs (2026-10-15)
# ═══════════════════════════════════════════════════════════════════════════════════════════════
#
# WHY: `supabase start` applies 0001 -> head from nothing on every run, and since 0105's merchant
# roster that is ~37 of disposable-chain's ~38 minutes (run 38693028351: first migration 06:35,
# last 07:12). On a PR every file but the new ones is byte-identical to a chain that main's own run
# ALREADY applied from zero, green, on the same CLI and the same config.
#
# WHAT: on a push to main (the from-zero net, unchanged) the stopped Postgres volume is tarred
# with a MANIFEST — one line per applied file, "<name> <sha256 of its bytes>", plus the CLI version
# and config.toml's sha. On a PR the newest kept snapshot is restored ONLY IF its manifest is an
# exact PREFIX of the PR's own chain (same names, same bytes, same order, same CLI, same config);
# `supabase start` then boots that volume ("Starting database from backup..." — the CLI skips its
# migrate step for an existing volume) and `supabase migration up` applies the files after the
# prefix through the CLI's own applier, every self-assert and CHECK with them. Anything else — an
# edited old migration, a new file that sorts before the prefix's last, a config or CLI change, no
# snapshot at all — is a full from-zero `supabase start`, exactly as before.
#
# USAGE
#   supabase-snapshot.sh manifest <out-file>        # this checkout's manifest
#   supabase-snapshot.sh key                        # a cache key for this checkout's chain
#   supabase-snapshot.sh usable <snapdir>           # prints "usable=true|false" and "prefix=N"
#   supabase-snapshot.sh save <snapdir>             # tar the (stopped) db volume + manifest
#   supabase-snapshot.sh restore <snapdir>          # untar into a fresh db volume
# ═══════════════════════════════════════════════════════════════════════════════════════════════
set -euo pipefail

VOLUME="supabase_db_$(sed -n 's/^project_id *= *"\(.*\)".*/\1/p' supabase/config.toml)"
CLI_VERSION="${SUPABASE_CLI_VERSION:?SUPABASE_CLI_VERSION must name the pinned CLI}"
# Bump to retire every kept snapshot at once (a change to how they are made).
FORMAT=v1

manifest() {
  echo "format $FORMAT"
  echo "cli $CLI_VERSION"
  echo "config $(sha256sum < supabase/config.toml | cut -d' ' -f1)"
  shopt -s nullglob
  for f in supabase/migrations/*.sql; do
    echo "file $(basename "$f") $(sha256sum < "$f" | cut -d' ' -f1)"
  done
}

case "${1:-}" in
  manifest)
    manifest > "$2"
    ;;
  key)
    echo "sbdb-$FORMAT-$CLI_VERSION-$(manifest | sha256sum | cut -c1-40)"
    ;;
  usable)
    snap="$2"
    if [ ! -f "$snap/manifest.txt" ] || [ ! -f "$snap/db.tar" ]; then
      echo "no snapshot restored" >&2
      echo "usable=false"; echo "prefix=0"; exit 0
    fi
    manifest > /tmp/head-manifest.txt
    n=$(wc -l < "$snap/manifest.txt")
    # The snapshot's manifest must be the head manifest's first n lines, byte for byte: format, CLI,
    # config, then every file in order with the same content hash.
    if head -n "$n" /tmp/head-manifest.txt | cmp -s - "$snap/manifest.txt"; then
      files=$(grep -c '^file ' "$snap/manifest.txt" || true)
      echo "snapshot covers $files file(s); $(( $(grep -c '^file ' /tmp/head-manifest.txt) - files )) new file(s) to apply on top" >&2
      echo "usable=true"; echo "prefix=$files"
    else
      echo "snapshot is NOT a prefix of this chain — first difference:" >&2
      diff <(head -n "$n" /tmp/head-manifest.txt) "$snap/manifest.txt" | head -5 >&2 || true
      echo "usable=false"; echo "prefix=0"
    fi
    ;;
  save)
    snap="$2"; mkdir -p "$snap"
    docker volume inspect "$VOLUME" > /dev/null
    docker run --rm -v "$VOLUME:/v:ro" -v "$snap:/out" alpine:3.20 tar -C /v -cf /out/db.tar .
    manifest > "$snap/manifest.txt"
    ls -la "$snap"
    ;;
  restore)
    snap="$2"
    if docker volume inspect "$VOLUME" > /dev/null 2>&1; then
      echo "::error::$VOLUME already exists; refusing to restore over it"; exit 1
    fi
    docker volume create "$VOLUME" > /dev/null
    docker run --rm -v "$VOLUME:/v" -v "$snap:/in:ro" alpine:3.20 tar -C /v -xpf /in/db.tar
    echo "restored $VOLUME from $(grep -c '^file ' "$snap/manifest.txt") applied file(s)"
    ;;
  *)
    echo "usage: $0 manifest|key|usable|save|restore ..." >&2; exit 2
    ;;
esac
