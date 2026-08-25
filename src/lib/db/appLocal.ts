// ═══════════════════════════════════════════════════════════════════════════════════════════════
// app_local — WHICH CHAIN BUILT THIS DATABASE, written inside the database itself
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// This is the bookkeeping localDb.ts has always kept beside the game data. It moved out of that
// file the day the world started being SHIPPED as a pre-built image (2026-08-25), because from
// then on two processes write it and one reads it:
//
//   * scripts/db/build-image.mjs stamps it into the image at BUILD time, from the chain in the
//     repository at that moment;
//   * localDb.ts stamps it after applying the chain in the browser;
//   * localDb.ts reads it on every boot and decides — reuse, or demolish and rebuild.
//
// THE WHOLE POINT IS THAT THERE IS ONE STAMP AND ONE READER. A pre-built image is a SECOND COPY
// OF THE WORLD, and this project has already lost a working day to exactly that class of defect:
// migration 0003 was edited after production had applied it, "production kept the ORIGINAL 70
// goods / 214 harbours while every fresh rebuild got 243", and — the sentence that matters —
// "Nothing red happened anywhere. Everything stayed green while the worlds diverged."
// (docs/DEV_LOG.md D23.)
//
// So the image carries, INSIDE it, the fingerprint of the chain it was built from, written by the
// same DDL and read by the same query as a browser-applied world. An image built from a different
// chain than the one the app shipped with is therefore not "an image that looks fine": it is a
// row that does not match `fingerprintChain(files)`, and `imageRefusal()` below turns that into a
// sentence the boot prints and the player is shown.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The slice of PGlite this module needs. Structural, so a build script or a test can hand in any. */
export interface AppLocalExecutor {
  exec(sql: string, options?: { onNotice?: (notice: { message?: string }) => void }): Promise<unknown>
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<{ rows: T[] }>
}

/** What built this database. `auth_uid` is null until a house is founded (an image has none). */
export interface StoredChain {
  fingerprint: string
  files: number
  applied_at: string
  auth_uid: string | null
}

/** The bookkeeping this adapter keeps beside the game data. NOT part of the chain, and says so. */
export const APP_LOCAL_DDL = `
create schema if not exists app_local;
comment on schema app_local is
  'CLIENT-SIDE BOOKKEEPING, written by src/lib/db and by scripts/db/build-image.mjs — never by a '
  'migration. It records which chain built this browser database and which local captain owns it. '
  'Nothing in supabase/migrations reads it, so a cloud deployment is identical without it.';
create table if not exists app_local.chain (
  singleton   boolean primary key default true check (singleton),
  fingerprint text not null,
  files       int not null,
  names       text[] not null,
  applied_at  timestamptz not null default now(),
  auth_uid    uuid
);
`

/**
 * Stamp the chain that built this database. Called after a browser apply AND at image build time
 * — one writer, so an image and a browser-built world are indistinguishable to the reader below.
 */
export async function recordChain(
  pg: AppLocalExecutor,
  args: { fingerprint: string; names: readonly string[]; authUid?: string | null },
): Promise<void> {
  await pg.exec(APP_LOCAL_DDL)
  await pg.query(
    `insert into app_local.chain (singleton, fingerprint, files, names, auth_uid)
     values (true, $1, $2, $3, $4)
     on conflict (singleton) do update
        set fingerprint = excluded.fingerprint, files = excluded.files,
            names = excluded.names, applied_at = now(), auth_uid = excluded.auth_uid`,
    [args.fingerprint, args.names.length, [...args.names], args.authUid ?? null],
  )
}

/** What built this database — or null if nothing has, or if it predates this bookkeeping. */
export async function readStoredChain(pg: AppLocalExecutor): Promise<StoredChain | null> {
  try {
    const r = await pg.query<StoredChain>(
      `select fingerprint, files, applied_at::text as applied_at, auth_uid::text as auth_uid
         from app_local.chain where singleton`,
    )
    return r.rows[0] ?? null
  } catch {
    // No app_local schema means no chain has ever been recorded here. Two cases land in the same
    // place, correctly: a brand-new database, and one built before this adapter existed. Both must
    // be built from 0001, and `demolish` makes the second case safe.
    return null
  }
}

/**
 * THE PAIRING CHECK, and the only thing that lets a shipped image be trusted.
 *
 * Returns null when the loaded image was built from exactly the chain this build carries, and a
 * SENTENCE otherwise. Never a boolean: a rejection that cannot say what it saw is a rejection
 * nobody can act on, and this is the one check standing between the player and a world that is
 * not the repository's.
 *
 * Pure, so the browser, the build script and the spec all run the identical comparison.
 */
export function imageRefusal(stored: StoredChain | null, fingerprint: string): string | null {
  if (!stored) {
    return (
      'the pre-built world carries no app_local.chain row at all, so there is nothing to say ' +
      'which chain built it. It is refused; the chain will be applied here instead.'
    )
  }
  if (stored.fingerprint !== fingerprint) {
    return (
      `the pre-built world was built from chain ${stored.fingerprint} over ${stored.files} ` +
      `migration(s), but this build carries chain ${fingerprint}. It is refused; the chain will ` +
      'be applied here instead. A world shipped from one chain and played against another is ' +
      'exactly the divergence that stayed green for a working day (DEV_LOG D23).'
    )
  }
  return null
}
