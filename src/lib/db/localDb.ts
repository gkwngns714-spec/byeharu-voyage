// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LOCAL ENGINE — real PostgreSQL, in the tab, running the real chain
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// DEV_LOG D6: the same SQL runs in PGlite locally and in Supabase later. This file is the local
// half. It is not a mock, a fixture or a simulator — it is PostgreSQL 18 compiled to WebAssembly,
// with the real planner, real plpgsql, real constraints, real triggers and the real GRANTs, and
// the migrations it applies are the same files CI applies to a disposable Supabase.
//
// ── WHAT IT GUARANTEES ──────────────────────────────────────────────────────────────────────────
//   * PERSISTENCE. The database lives in IndexedDB, so closing the tab does not sink the fleet.
//   * NEVER A HALF-CHAIN. The applied chain's fingerprint is stored beside the data. If the build
//     carries a different chain, the stored database is DEMOLISHED and rebuilt from migration 0001
//     — applying six new migrations on top of a four-migration database is how you get a schema
//     that exists in no repository and can never be reproduced.
//   * ONE IDENTITY. Local mode has one captain. Their auth uid is stored in the database itself,
//     not in localStorage, so it cannot survive the data it identifies.
//   * HONEST FAILURE. Every phase reports through bootState; nothing is swallowed into a spinner.
//
// ── WHAT IT IS NOT ──────────────────────────────────────────────────────────────────────────────
//   PGlite runs single-user as a superuser, so RLS is BYPASSED here. The lockdown and the policies
//   are proven by `npm run db:proof` (which becomes `anon` deliberately) and by CI's disposable
//   Supabase — not by playing the game locally. Local play tests the RULES, not the WALLS.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { PGlite } from '@electric-sql/pglite'
import type { MigrationFile } from './chain'
import { describeChain, fingerprintChain, orderChain } from './chain'
import { applyChain } from './applyChain'
import { bootChannel, progressFor, type BootChannel } from './bootState'
import { rescuePlayerRows } from './rescue'

/** The IndexedDB database the local world lives in. */
export const LOCAL_DATA_DIR = 'idb://byeharu-voyage-v0'

/** §K.1's opening house. The chain's own `public.new_house()` seeds it; nothing here inserts rows. */
export const FOUNDING_COMPANY = 'Casa de Aveiro'
export const FOUNDING_NATION = 'PRT'

/**
 * The one local captain's auth uid. Local mode has no sign-in (authStore's `local` mode opens the
 * gate for a single captain), so the JWT subject every RLS policy and `current_player_id()` reads
 * is this constant. It is recorded in the database on first boot and read back afterwards, so the
 * identity and the data it owns can never be separated.
 */
export const LOCAL_AUTH_UID = '00000000-0000-4000-8000-000000000a17'

export interface OpenLocalDbOptions {
  /** How the SQL reaches this process. Browser: chainSource.ts. Node/tests: chainSource.node.mjs. */
  loadChain: () => Promise<MigrationFile[]>
  /** PGlite dataDir. Defaults to IndexedDB; a test passes `memory://` for a throwaway. */
  dataDir?: string
  /** Where boot progress is published. Defaults to the app-wide channel. */
  channel?: BootChannel
  /** Founding house name, so a test can open a second one. */
  companyName?: string
  authUid?: string
  log?: (...args: unknown[]) => void
  /** Set by the one-shot retry below. A caller never passes it. */
  retried?: boolean
}

export interface LocalDb {
  /** The live engine. Exposed for tests, tooling and the settle/tick loop — NOT for game rules. */
  readonly pg: PGlite
  /** The auth uid every call in this session assumes. */
  readonly authUid: string
  /** The fingerprint of the chain that built this database. */
  readonly fingerprint: string
  /** True when the stored database was demolished and rebuilt because the chain had changed. */
  readonly rebuilt: boolean
  /** Milliseconds from the first line of boot to `ready`. Measured, not estimated. */
  readonly bootMs: number
  /** Names of the migrations applied, in order. */
  readonly applied: readonly string[]
  /**
   * Run ONE server function as the local captain.
   *
   * The identity is set inside the same transaction as the call, because `cmd.assume_identity()`
   * uses `set_config(..., is_local => true)`: outside a transaction it would evaporate before the
   * next statement and every read would come back as "you have no fleets".
   */
  callAs<T>(sql: string, params?: unknown[]): Promise<T>
  close(): Promise<void>
}

/** The bookkeeping this adapter keeps beside the game data. NOT part of the chain, and says so. */
const APP_LOCAL_DDL = `
create schema if not exists app_local;
comment on schema app_local is
  'CLIENT-SIDE BOOKKEEPING, written by src/lib/db — never by a migration. It records which chain '
  'built this browser database and which local captain owns it. Nothing in supabase/migrations '
  'reads it, so a cloud deployment is identical without it.';
create table if not exists app_local.chain (
  singleton   boolean primary key default true check (singleton),
  fingerprint text not null,
  files       int not null,
  names       text[] not null,
  applied_at  timestamptz not null default now(),
  auth_uid    uuid
);
`

export async function openLocalDb(options: OpenLocalDbOptions): Promise<LocalDb> {
  const channel = options.channel ?? bootChannel
  const dataDir = options.dataDir ?? LOCAL_DATA_DIR
  const authUid = options.authUid ?? LOCAL_AUTH_UID
  const log = options.log ?? ((...args: unknown[]) => console.info('[db]', ...args))
  const t0 = clock()

  const publish = (patch: Parameters<BootChannel['set']>[0]) => {
    channel.set({ ...patch, elapsedMs: Math.round(clock() - t0) })
  }

  publish({
    phase: 'booting',
    message: 'Starting PostgreSQL in this tab (a ~10 MB WebAssembly engine — this takes a moment).',
    progress: progressFor('booting', 0, 0),
    error: null,
  })

  let pg: PGlite
  let files: MigrationFile[]
  let fingerprint: string
  let rebuilt = false
  try {
    // Dynamic, so a cloud-configured build never downloads a Postgres it will not run.
    const [{ PGlite: PGliteCtor }, loaded] = await Promise.all([
      import('@electric-sql/pglite'),
      options.loadChain(),
    ])
    files = orderChain(loaded)
    fingerprint = fingerprintChain(files)
    pg = await PGliteCtor.create(dataDir)

    const stored = await readStoredChain(pg)
    if (stored && stored.fingerprint === fingerprint) {
      log(`reusing the stored world: ${describeChain(files)} (applied ${stored.applied_at})`)
      const applied = files.map((f) => f.name)
      const ready = await finishBoot({
        pg,
        channel,
        publish,
        authUid: stored.auth_uid ?? authUid,
        options,
        log,
        fingerprint,
        rebuilt: false,
        applied,
        t0,
      })
      return ready
    }

    if (stored) {
      rebuilt = true
      log(
        `THE CHAIN HAS CHANGED since this browser's world was built ` +
          `(stored ${stored.fingerprint} over ${stored.files} file(s); this build ${fingerprint} ` +
          `over ${files.length}). Rebuilding from migration 0001 — applying new migrations onto an ` +
          `old database would produce a schema that exists in no repository.`,
      )
      // THE PLAYER'S ROWS COME OUT FIRST. `demolish()` is a `drop schema public cascade`: it takes
      // the world AND the house standing in it, and until 2026-08-20 it took them silently and
      // irrecoverably — a purse that had bought cargo was back at 8,000 ducats with no word said
      // (DEV_LOG D11c). This cannot throw; a failed rescue is reported, never fatal.
      const rescued = await rescuePlayerRows(pg, stored.fingerprint)
      if (rescued.rows > 0) {
        log(
          rescued.stored
            ? `RESCUED ${rescued.rows} of your row(s) from ${rescued.tables} table(s) before ` +
                `demolishing — kept under localStorage "byeharu-voyage.rescued.v1".`
            : `COULD NOT RESCUE your ${rescued.rows} row(s): ${rescued.note}.`,
        )
      }
      publish({
        phase: 'booting',
        rebuilt: true,
        rescued: rescued.rows > 0 ? rescued : null,
        message: 'The world was built by an older version of the game. Rebuilding it from scratch.',
      })
      await demolish(pg)
    }

    publish({
      phase: 'applying',
      migrationCount: files.length,
      migrationIndex: 0,
      migration: files[0]?.name ?? null,
      fingerprint,
      rebuilt,
      message: 'Building the world: applying the migration chain.',
      progress: progressFor('applying', 0, files.length),
    })

    const result = await applyChain(pg, files, (step) => {
      publish({
        phase: 'applying',
        migration: step.name,
        migrationIndex: step.index,
        migrationCount: step.total,
        progress: progressFor('applying', step.index, step.total),
        message: `Applying ${step.index + 1} of ${step.total}: ${humanMigration(step.name)}`,
      })
    })
    log(
      `chain applied: ${result.applied.length} migration(s) in ${result.ms} ms, ` +
        `${result.receipts} self-assert receipt(s)`,
    )
    if (result.receipts < result.applied.length) {
      // Same non-vacuity floor as apply-chain.mjs: every migration in this chain proves itself out
      // loud, so a missing receipt means a self-assert stopped asserting.
      log(
        `WARNING: ${result.applied.length} migration(s) applied but only ${result.receipts} printed ` +
          `a self-assert receipt.`,
      )
    }

    await pg.exec(APP_LOCAL_DDL)
    await pg.query(
      `insert into app_local.chain (singleton, fingerprint, files, names, auth_uid)
       values (true, $1, $2, $3, $4)
       on conflict (singleton) do update
          set fingerprint = excluded.fingerprint, files = excluded.files,
              names = excluded.names, applied_at = now(), auth_uid = excluded.auth_uid`,
      [fingerprint, files.length, files.map((f) => f.name), authUid],
    )

    return await finishBoot({
      pg,
      channel,
      publish,
      authUid,
      options,
      log,
      fingerprint,
      rebuilt,
      applied: result.applied.map((a) => a.name),
      t0,
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)

    // A CHAIN THAT DIES HALFWAY LEAVES A HALF-BUILT DATABASE, and the fingerprint row is only
    // written on success — so the NEXT boot finds a world it cannot recognise, starts again at
    // 0001, and fails on `policy "nations_read" for table "nations" already exists` instead of on
    // whatever actually broke. The player is then stuck behind an error about a policy, for ever,
    // with no way back. Found in the browser (2026-08-19) after a genuinely failing migration.
    //
    // So: demolish the wreckage and try ONCE from an empty database. If it fails again it is the
    // migration and not the leftovers, and THAT is the message the player is given.
    if (pg! !== undefined && !options.retried) {
      log('BOOT FAILED — demolishing the half-built world and trying once from empty\n' + message)
      publish({
        phase: 'booting',
        rebuilt: true,
        message: 'The world was left half-built. Clearing it and starting again.',
      })
      try {
        await demolish(pg!)
      } catch {
        // Nothing left to salvage; the retry opens its own engine over the same store.
      }
      try {
        await pg!.close()
      } catch {
        // Already gone.
      }
      return await openLocalDb({ ...options, retried: true })
    }

    publish({
      phase: 'failed',
      error: message,
      progress: 1,
      message: 'The local world could not be built. The game cannot start.',
    })
    log('BOOT FAILED\n' + message)
    throw err
  }
}

/** Seed the founding house if this world has none, then hand back the handle. */
async function finishBoot(args: {
  pg: PGlite
  channel: BootChannel
  publish: (patch: Parameters<BootChannel['set']>[0]) => void
  authUid: string
  options: OpenLocalDbOptions
  log: (...a: unknown[]) => void
  fingerprint: string
  rebuilt: boolean
  applied: string[]
  t0: number
}): Promise<LocalDb> {
  const { pg, publish, authUid, options, log, fingerprint, rebuilt, applied, t0 } = args

  const existing = await pg.query<{ id: string }>('select id from public.players where auth_uid = $1', [
    authUid,
  ])
  if (existing.rows.length === 0) {
    publish({
      phase: 'seeding',
      progress: progressFor('seeding', 0, 0),
      message: 'Founding your house: one Barca at Lisboa, and the purse to start her.',
    })
    // THE CHAIN'S OWN FOUNDING FUNCTION. §K.1's opening — 8,000 ducats, one Barca named Gaivota
    // docked at Lisboa — is authored in migration 0004, with the purse invariant enforced by the
    // same triggers that guard every later ducat. A hand-written INSERT here would be a second
    // authority for what a new house is, and would bypass the ledger.
    await pg.query('select public.new_house($1, $2, $3) as player_id', [
      authUid,
      options.companyName ?? FOUNDING_COMPANY,
      FOUNDING_NATION,
    ])
    await pg.query('update app_local.chain set auth_uid = $1 where singleton', [authUid])
    log(`founded ${options.companyName ?? FOUNDING_COMPANY} (auth ${authUid})`)
  }

  const bootMs = Math.round(clock() - t0)
  publish({
    phase: 'ready',
    progress: 1,
    migration: null,
    fingerprint,
    rebuilt,
    message: 'The world is ready.',
    error: null,
  })
  log(`ready in ${bootMs} ms — chain ${fingerprint}`)

  return {
    pg,
    authUid,
    fingerprint,
    rebuilt,
    bootMs,
    applied,
    async callAs<T>(sql: string, params: unknown[] = []): Promise<T> {
      return pg.transaction(async (tx) => {
        await tx.query('select cmd.assume_identity($1)', [authUid])
        const r = await tx.query<{ result: T }>(sql, params)
        return (r.rows[0]?.result ?? null) as T
      })
    },
    close: () => pg.close(),
  }
}

interface StoredChain {
  fingerprint: string
  files: number
  applied_at: string
  auth_uid: string | null
}

/** What built this browser's database — or null if nothing has, or if it predates this bookkeeping. */
async function readStoredChain(pg: PGlite): Promise<StoredChain | null> {
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
 * Throw the world away. Schema-level, not file-level: it works identically on IndexedDB, on
 * `memory://` and on a node filesystem, and it does not depend on PGlite's internal storage
 * naming — which is the sort of thing that changes in a patch release and silently strands a
 * player on a schema nobody can reproduce.
 */
async function demolish(pg: PGlite): Promise<void> {
  await pg.exec(`
    drop schema if exists app_local cascade;
    drop schema if exists cmd cascade;
    drop schema if exists voyage cascade;
    drop schema if exists world cascade;
    drop schema if exists public cascade;
    create schema public;
  `)
}

/** `20260818000007_a_fleet_arrives_and_the_queue_runs_itself.sql` → `a fleet arrives and the queue runs itself`. */
export function humanMigration(name: string): string {
  return name.replace(/^\d+_/, '').replace(/\.sql$/, '').replace(/_/g, ' ')
}

function clock(): number {
  return typeof performance !== 'undefined' ? performance.now() : Date.now()
}
