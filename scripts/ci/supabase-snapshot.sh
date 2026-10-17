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
# and config.toml's sha — and saved under a key that is the sha of that manifest. On a PR a kept
# snapshot is restored ONLY IF its manifest is an exact PREFIX of the PR's own chain (same names,
# same bytes, same order, same CLI, same config); `supabase start` then boots that volume
# ("Starting database from backup..." — the CLI skips its migrate step for an existing volume) and
# `supabase migration up` applies the files after the prefix through the CLI's own applier, every
# self-assert and CHECK with them. Anything else — an edited old migration, a config or CLI change,
# no usable snapshot at all — is a full from-zero `supabase start`, exactly as before.
#
# WHICH SNAPSHOT (2026-10-17, `choose`): NOT "the newest". The key IS the manifest's hash, and a
# snapshot is usable exactly when its manifest is this chain's first lines — so the keys of every
# usable snapshot can be computed from the checkout alone (one per prefix length) and looked up in
# the repository's cache list. `choose` picks the LONGEST kept prefix this run may restore (a cache
# on the base branch or on this PR's own ref; GitHub lets a PR restore no other). Before it decides
# it WAITS, bounded, for main's own run on the PR's base commit when that run is still going and
# its snapshot — the base chain itself, the one that leaves only the PR's files to apply — is not
# kept yet. Why: PR #147 started two minutes before main's run saved the matching snapshot, the
# newest kept one was from a chain that 0137's out-of-order merge had made a non-prefix, and the
# PR applied 132 files from zero (47 minutes) while a usable snapshot sat one key over.
#
# USAGE
#   supabase-snapshot.sh manifest <out-file> [rev]  # this checkout's manifest (or the chain committed at <rev>)
#   supabase-snapshot.sh key [rev]                  # the cache key of this checkout's chain (or <rev>'s)
#   supabase-snapshot.sh choose <base-rev>          # PR: prints "key=<kept key or empty>" and "prefix=N"
#   supabase-snapshot.sh usable <snapdir>           # prints "usable=true|false" and "prefix=N"
#   supabase-snapshot.sh save <snapdir>             # tar the (stopped) db volume + manifest
#   supabase-snapshot.sh restore <snapdir>          # untar into a fresh db volume
#
# `choose` needs `gh` with a token that may read Actions (`permissions: actions: read`), and the
# GITHUB_REPOSITORY / GITHUB_REF / GITHUB_BASE_REF the runner sets. SNAPSHOT_WAIT_SECONDS bounds
# the wait (default 3000 = 50 min, about one from-zero apply: waiting longer than that can never
# beat applying from zero ourselves).
# ═══════════════════════════════════════════════════════════════════════════════════════════════
set -euo pipefail

VOLUME="supabase_db_$(sed -n 's/^project_id *= *"\(.*\)".*/\1/p' supabase/config.toml)"
CLI_VERSION="${SUPABASE_CLI_VERSION:?SUPABASE_CLI_VERSION must name the pinned CLI}"
# Bump to retire every kept snapshot at once (a change to how they are made).
FORMAT=v1
KEY_PREFIX="sbdb-$FORMAT-$CLI_VERSION-"

# The manifest of the working tree, or — given a git revision — of the chain as committed there.
# Both print the same lines in the same order, so a snapshot's key can be predicted for a commit
# this run did not check out (the PR's base).
manifest() {
  local rev="${1:-}"
  echo "format $FORMAT"
  echo "cli $CLI_VERSION"
  if [ -z "$rev" ]; then
    echo "config $(sha256sum < supabase/config.toml | cut -d' ' -f1)"
    shopt -s nullglob
    for f in supabase/migrations/*.sql; do
      echo "file $(basename "$f") $(sha256sum < "$f" | cut -d' ' -f1)"
    done
  else
    echo "config $(git show "$rev:supabase/config.toml" | sha256sum | cut -d' ' -f1)"
    git ls-tree --name-only "$rev" -- supabase/migrations/ | grep '\.sql$' | LC_ALL=C sort | while read -r f; do
      echo "file $(basename "$f") $(git show "$rev:$f" | sha256sum | cut -d' ' -f1)"
    done
  fi
}

key_of() { echo "$KEY_PREFIX$(sha256sum | cut -c1-40)"; }

# Every kept snapshot key THIS run may restore: GitHub scopes a cache to the ref that saved it, and
# a pull request may read its own ref's and its base branch's. Anything else in the list is real
# but unreachable from here, so it is filtered out rather than chosen and then missed.
kept_keys() {
  gh api --paginate "repos/$GITHUB_REPOSITORY/actions/caches?key=$KEY_PREFIX&per_page=100" \
      --jq '.actions_caches[] | "\(.ref) \(.key)"' \
    | awk -v own="$GITHUB_REF" -v base="refs/heads/$GITHUB_BASE_REF" '$1 == own || $1 == base { print $2 }' \
    | sort -u
}

# "<run id> <status>" of main's migrations-apply-proof run for a commit, or "none".
main_run_for() {
  gh run list --repo "$GITHUB_REPOSITORY" --workflow migrations-apply-proof.yml --branch "$GITHUB_BASE_REF" \
      --limit 100 --json databaseId,headSha,status \
    | jq -r --arg s "$1" '[.[] | select(.headSha == $s)] | if length == 0 then "none" else "\(.[0].databaseId) \(.[0].status)" end'
}

case "${1:-}" in
  manifest)
    manifest "${3:-}" > "$2"
    ;;
  key)
    manifest "${2:-}" | key_of
    ;;
  choose)
    base="${2:?the PR base commit (first parent of the merge commit)}"
    manifest > /tmp/head-manifest.txt
    n=$(grep -c '^file ' /tmp/head-manifest.txt)
    # The key a snapshot of exactly this chain's first k files carries, for every k. A kept key
    # that is one of these IS a usable snapshot; nothing else can be (the `usable` check below in
    # the workflow still judges the restored bytes).
    declare -A len_of=()
    for ((k = n; k >= 1; k--)); do
      lines=$((3 + k))
      k_key=$(head -n "$lines" /tmp/head-manifest.txt | key_of)
      len_of[$k_key]=$k
    done
    ideal=$(manifest "$base" | key_of)
    ideal_k=${len_of[$ideal]:-0}
    if [ "$ideal_k" -eq 0 ]; then
      echo "the base chain ($base) is not a prefix of this chain (a file was added before its last one, or an old file changed): main's snapshot of it could never be used, so there is nothing to wait for" >&2
    fi
    deadline=$(( $(date +%s) + ${SNAPSHOT_WAIT_SECONDS:-3000} ))
    while :; do
      best_k=0; best_key=""
      while read -r key; do
        [ -n "$key" ] || continue
        k=${len_of[$key]:-0}
        if [ "$k" -gt "$best_k" ]; then best_k=$k; best_key=$key; fi
      done < <(kept_keys)
      if [ "$ideal_k" -gt 0 ] && [ "$best_k" -lt "$ideal_k" ]; then
        run=$(main_run_for "$base")
        status=${run#* }
        if [ "$run" != "none" ] && [ "$status" != "completed" ] && [ "$(date +%s)" -lt "$deadline" ]; then
          echo "$(date -u +%H:%M:%S) main's run ${run% *} for the base $base is $status and its snapshot ($ideal, $ideal_k files = everything but this PR's own) is not kept yet; the longest kept prefix is $best_k file(s). Waiting 60 s." >&2
          sleep 60
          continue
        fi
        echo "main's run for the base $base: ${run} — not waiting (any) longer" >&2
      fi
      break
    done
    if [ "$best_k" -gt 0 ]; then
      echo "chosen: $best_key — the longest kept prefix, $best_k of this chain's $n file(s); $((n - best_k)) to apply on top" >&2
    else
      echo "no kept snapshot is a prefix of this chain ($(kept_keys | wc -l) restorable key(s) checked against $n prefix key(s)): the full from-zero apply" >&2
    fi
    echo "key=$best_key"; echo "prefix=$best_k"
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
    echo "usage: $0 manifest|key|choose|usable|save|restore ..." >&2; exit 2
    ;;
esac
