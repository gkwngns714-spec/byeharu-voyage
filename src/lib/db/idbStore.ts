// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BROWSER'S STORE — is there a world in it, and can it be emptied so a pre-built one fits?
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// PGlite untars a pre-built world into PGDATA **only into an empty data directory**: with a
// database already there it raises "Database already exists, cannot load from tarball"
// (@electric-sql/pglite@0.5.5, dist/index.js — the check is `FS.analyzePath(PGDATA/PG_VERSION)`).
// That is the whole reason this file exists, and it is the ONLY place in src/lib/db that knows
// anything about how PGlite lays its storage out.
//
// ── WHY THAT KNOWLEDGE IS QUARANTINED HERE, AND NEVER TRUSTED ───────────────────────────────────
// localDb.ts's `demolish()` is deliberately schema-level ("it does not depend on PGlite's internal
// storage naming — which is the sort of thing that changes in a patch release and silently strands
// a player on a schema nobody can reproduce"). That rule is right, and this file does not break it:
//
//   * `hasStoredWorld()` returns `null` for "cannot tell", never a guess.
//   * `emptyStore()` reports what it did; NOTHING acts on the report as if it were proof.
//   * Both callers verify by CONSEQUENCE instead: the load either succeeds, or PGlite raises and
//     the boot falls back to applying the chain exactly as it did before this optimisation existed.
//
// So the worst a PGlite storage rename can do here is turn the fast boot back into the slow boot,
// out loud. It cannot produce a half-built world, and it cannot silently strand anybody.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** `idb://byeharu-voyage-v0` → `byeharu-voyage-v0`; anything else → null (not an IndexedDB store). */
export function idbKey(dataDir: string): string | null {
  return dataDir.startsWith('idb://') ? dataDir.slice('idb://'.length) : null
}

/**
 * The IndexedDB database PGlite mounts this dataDir as. Emscripten's IDBFS names its database
 * after the mountpoint, and PGlite mounts at `/pglite/<dataDir>`.
 * A GUESS BY CONSTRUCTION — see the header. Only ever used to delete OUR OWN store.
 */
export function idbDatabaseName(key: string): string {
  return `/pglite/${key}`
}

function idbAvailable(): boolean {
  try {
    return typeof indexedDB !== 'undefined' && indexedDB !== null
  } catch {
    // A browser with storage disabled throws on access rather than returning undefined.
    return false
  }
}

/**
 * Has this origin ever stored a world for `dataDir`?
 *
 * `true` / `false` are hints, `null` is "cannot tell" — and every caller must treat all three as
 * a hint. Its only job is to let a first-ever boot skip an `initdb` it would immediately throw
 * away: a `false` that is wrong costs one raised error and the normal path.
 */
export async function hasStoredWorld(dataDir: string): Promise<boolean | null> {
  const key = idbKey(dataDir)
  if (key === null || !idbAvailable()) return null
  // Not universally implemented (Firefox before 126). Absent → "cannot tell", never "no".
  if (typeof indexedDB.databases !== 'function') return null
  try {
    const dbs = await indexedDB.databases()
    return dbs.some((d) => typeof d.name === 'string' && d.name.includes(key))
  } catch {
    return null
  }
}

export interface EmptyStoreResult {
  /** True only when a delete actually completed. A `false` here is not "it failed" — see `note`. */
  emptied: boolean
  /** The names it deleted, for the log. */
  deleted: string[]
  /** Why nothing was deleted, when nothing was. */
  note: string | null
}

/**
 * Throw away the IndexedDB store behind `dataDir`, so a pre-built world can be untarred into it.
 *
 * NEVER THROWS, and its answer is never load-bearing: the caller closes the engine first, calls
 * this, and then tries the load. If this did nothing useful, the load raises and the boot applies
 * the chain. The 5-second ceiling is for the `blocked` case — another tab holding the same store —
 * where waiting for ever would hang the boot behind a window the player may never close.
 */
export async function emptyStore(dataDir: string): Promise<EmptyStoreResult> {
  const key = idbKey(dataDir)
  if (key === null) {
    return { emptied: false, deleted: [], note: `${dataDir} is not an IndexedDB store` }
  }
  if (!idbAvailable()) {
    return { emptied: false, deleted: [], note: 'this browser allows no IndexedDB' }
  }

  const listed = await hasStoredWorld(dataDir)
  let names: string[]
  if (listed === null) {
    // Cannot enumerate: delete the one name PGlite would have used. If that is not the name, the
    // load below raises and the chain is applied — which is what happened before this existed.
    names = [idbDatabaseName(key)]
  } else {
    const dbs = await indexedDB.databases()
    names = dbs
      .map((d) => d.name)
      .filter((n): n is string => typeof n === 'string' && n.includes(key))
  }

  const deleted: string[] = []
  for (const name of names) {
    const ok = await deleteDatabase(name)
    if (ok) deleted.push(name)
  }
  return {
    emptied: deleted.length > 0,
    deleted,
    note: deleted.length > 0 ? null : `no IndexedDB store matching "${key}" could be deleted`,
  }
}

function deleteDatabase(name: string): Promise<boolean> {
  return new Promise((resolve) => {
    let settled = false
    const done = (ok: boolean) => {
      if (!settled) {
        settled = true
        resolve(ok)
      }
    }
    try {
      const req = indexedDB.deleteDatabase(name)
      req.onsuccess = () => done(true)
      req.onerror = () => done(false)
      // `blocked` means another connection is still open — usually a second tab. It may still
      // complete when that tab lets go, so this is a ceiling and not a verdict.
      req.onblocked = () => setTimeout(() => done(false), 5_000)
      setTimeout(() => done(false), 5_000)
    } catch {
      done(false)
    }
  })
}
