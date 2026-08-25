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
//   * NEVER SOMEONE ELSE'S WORLD. Since 2026-08-25 the world may arrive PRE-BUILT, as a data
//     directory generated during `npm run build` (scripts/db/build-image.mjs), because replaying
//     45 migrations in the player's tab cost 78.8 s (DEV_LOG D23). An image is a second copy of
//     the world, so it is admitted only on proof: it is asked for by a URL that contains this
//     build's own chain fingerprint, and once restored it must ANSWER with that same fingerprint
//     from app_local.chain, or `imageRefusal()` rejects it out loud and the chain is applied here
//     as before. The pre-built path is an OPTIMISATION on top of the apply path; it never replaces
//     it, and every failure of it lands back on it.
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
import { imageRefusal, readStoredChain, recordChain } from './appLocal'
import { bootChannel, progressFor, type BootChannel } from './bootState'
import { emptyStore, hasStoredWorld, type EmptyStoreResult } from './idbStore'
import { rescuePlayerRows } from './rescue'
import type { WorldImageFetch } from './worldImage'

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
  /**
   * How the PRE-BUILT world reaches this process, if this build ships one. Browser:
   * worldImage.ts's `fetchWorldImage`, wired in index.ts. A Node spec hands in the file the build
   * emitted. ABSENT BY DEFAULT — with no image the boot applies the chain, which is what it did
   * for the whole of this game's life and what still runs whenever the image is missing or refused.
   */
  loadImage?: (fingerprint: string) => Promise<WorldImageFetch>
  /**
   * Empty the store behind `dataDir`, so a pre-built world can be untarred into it. Defaults to
   * the IndexedDB implementation; a Node spec passes one that removes its scratch directory.
   * Its answer is never trusted — see idbStore.ts's header.
   */
  resetStore?: (dataDir: string) => Promise<EmptyStoreResult>
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
  /** True when this world was restored from the pre-built image instead of applied here. */
  readonly fromImage: boolean
  /** Milliseconds from the first line of boot to `ready`. Measured, not estimated. */
  readonly bootMs: number
  /** The migrations this world was built from, in order — applied in this tab, or, when
   *  `fromImage`, applied by the build that produced the image. Same chain either way: that is
   *  what the fingerprint check guarantees. */
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

/** No image on offer. The default, and the shape every failure mode of a fetch comes back as. */
const NO_IMAGE: WorldImageFetch = {
  blob: null,
  url: '',
  bytes: 0,
  note: 'this build carries no pre-built world, so the chain is applied here',
}

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

  let pg: PGlite | undefined
  let files: MigrationFile[]
  let fingerprint: string
  let rebuilt = false
  let fromImage: boolean
  try {
    // Dynamic, so a cloud-configured build never downloads a Postgres it will not run.
    const [{ PGlite: PGliteCtor }, loaded] = await Promise.all([
      import('@electric-sql/pglite'),
      options.loadChain(),
    ])
    files = orderChain(loaded)
    fingerprint = fingerprintChain(files)
    const loadImage = options.loadImage ?? (() => Promise.resolve(NO_IMAGE))
    const resetStore = options.resetStore ?? emptyStore

    // ── 1. IS THIS BUILD'S WORLD ALREADY HERE? ────────────────────────────────────────────────
    // Asked first, because reusing it costs nothing and is what happens on every visit after the
    // first. The engine is opened to ask — EXCEPT when the store is known to have never held a
    // world, because opening it would run an `initdb` over the very directory a pre-built world
    // has to be untarred into (PGlite refuses to load one over an existing database), and that
    // initdb would then have to be thrown away again. `hasStoredWorld()` answers `false` only
    // when it is sure; every other answer takes the ordinary road.
    const stores = await hasStoredWorld(dataDir)
    if (stores !== false) {
      pg = await PGliteCtor.create(dataDir)
      const stored = await readStoredChain(pg)

      if (stored && stored.fingerprint === fingerprint) {
        log(`reusing the stored world: ${describeChain(files)} (applied ${stored.applied_at})`)
        return await finishBoot({
          pg,
          channel,
          publish,
          authUid: stored.auth_uid ?? authUid,
          options,
          log,
          fingerprint,
          rebuilt: false,
          fromImage: false,
          applied: files.map((f) => f.name),
          t0,
        })
      }

      if (stored) {
        rebuilt = true
        log(
          `THE CHAIN HAS CHANGED since this browser's world was built ` +
            `(stored ${stored.fingerprint} over ${stored.files} file(s); this build ${fingerprint} ` +
            `over ${files.length}). Rebuilding from migration 0001 — applying new migrations onto an ` +
            `old database would produce a schema that exists in no repository.`,
        )
        // THE PLAYER'S ROWS COME OUT FIRST. The rebuild below takes the world AND the house
        // standing in it, and until 2026-08-20 it took them silently and irrecoverably — a purse
        // that had bought cargo was back at 8,000 ducats with no word said (DEV_LOG D11c). This
        // cannot throw; a failed rescue is reported, never fatal.
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
      }

      // Nothing here is usable. Let the engine go, so the store can be emptied for a pre-built
      // world — and if that does not work out, step 3 re-opens it and `demolish()` still does the
      // job it always did.
      await pg.close()
      pg = undefined
    }

    // ── 2. THE PRE-BUILT WORLD ────────────────────────────────────────────────────────────────
    // An optimisation, admitted only on proof, and never load-bearing: every way this can fail —
    // no image emitted, a 404, an unreadable tarball, a fingerprint that does not match the chain
    // this build carries — returns undefined and lands on step 3, out loud.
    pg = await openFromImage({
      PGliteCtor,
      dataDir,
      fingerprint,
      loadImage,
      resetStore,
      // Nothing to empty on a store that is known never to have held a world.
      emptyFirst: stores !== false,
      log,
      publish,
    })
    fromImage = pg !== undefined

    // ── 3. THE CHAIN, APPLIED HERE. The path this game ran on for its whole life. ─────────────
    if (pg === undefined) {
      pg = await PGliteCtor.create(dataDir)
      // Re-read rather than assume: step 2 may have emptied the store, may have half-emptied it,
      // or may never have been reached at all.
      if (rebuilt || (await readStoredChain(pg)) !== null) await demolish(pg)

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

      await recordChain(pg, { fingerprint, names: files.map((f) => f.name), authUid })
    }

    return await finishBoot({
      pg,
      channel,
      publish,
      authUid,
      options,
      log,
      fingerprint,
      rebuilt,
      fromImage,
      applied: files.map((f) => f.name),
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
    if (pg !== undefined && !options.retried) {
      log('BOOT FAILED — demolishing the half-built world and trying once from empty\n' + message)
      publish({
        phase: 'booting',
        rebuilt: true,
        message: 'The world was left half-built. Clearing it and starting again.',
      })
      try {
        await demolish(pg)
      } catch {
        // Nothing left to salvage; the retry opens its own engine over the same store.
      }
      try {
        await pg.close()
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
  fromImage: boolean
  applied: string[]
  t0: number
}): Promise<LocalDb> {
  const { pg, publish, authUid, options, log, fingerprint, rebuilt, fromImage, applied, t0 } = args

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
    fromImage,
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

/**
 * OPEN THE PRE-BUILT WORLD, or hand back nothing and say why.
 *
 * Every step here can decline, and declining is not an error: the caller applies the chain, which
 * is what this game did for its whole life and still does whenever an image is absent, unreadable,
 * or built from another chain. NOTHING IN THIS FUNCTION THROWS, for that reason.
 *
 * The one thing it will not do is hand back a world it cannot vouch for. `imageRefusal()` compares
 * the fingerprint written INSIDE the restored database against the fingerprint of the chain this
 * build carries, and a mismatch is logged as an error, published to the boot channel so the app
 * can show it, and thrown away — store and all, so the next boot does not find it sitting there.
 */
async function openFromImage(args: {
  PGliteCtor: typeof PGlite
  dataDir: string
  fingerprint: string
  loadImage: (fingerprint: string) => Promise<WorldImageFetch>
  resetStore: (dataDir: string) => Promise<EmptyStoreResult>
  emptyFirst: boolean
  log: (...a: unknown[]) => void
  publish: (patch: Parameters<BootChannel['set']>[0]) => void
}): Promise<PGlite | undefined> {
  const { PGliteCtor, dataDir, fingerprint, loadImage, resetStore, emptyFirst, log, publish } = args

  let fetched: WorldImageFetch
  try {
    fetched = await loadImage(fingerprint)
  } catch (err) {
    log(`the pre-built world could not be asked for (${describeError(err)}) — applying the chain`)
    return undefined
  }
  if (!fetched.blob) {
    log(`applying the chain here: ${fetched.note ?? 'no pre-built world was offered'}`)
    return undefined
  }

  const size = `${(fetched.bytes / 1048576).toFixed(1)} MB`
  publish({
    phase: 'booting',
    progress: progressFor('booting', 0, 0),
    message: `Unpacking the world this version of the game was built with (${size}).`,
  })

  if (emptyFirst) {
    // PGlite will not untar a data directory over an existing database, so the store has to go
    // first. Its answer is a report, not a permission — the load below is what actually decides.
    const emptied = await resetStore(dataDir)
    log(
      emptied.emptied
        ? `emptied the stored world (${emptied.deleted.join(', ')}) to make room for the pre-built one`
        : `could not empty the stored world (${emptied.note}) — the pre-built world may not fit`,
    )
  }

  let pg: PGlite
  try {
    pg = await PGliteCtor.create({ dataDir, loadDataDir: fetched.blob })
  } catch (err) {
    log(
      `the pre-built world at ${fetched.url} could not be unpacked (${describeError(err)}) — ` +
        'applying the chain here instead',
    )
    return undefined
  }

  const stored = await readStoredChain(pg)
  const refusal = imageRefusal(stored, fingerprint)
  if (refusal) {
    log(`PRE-BUILT WORLD REFUSED: ${refusal}`)
    publish({ imageRefused: refusal })
    try {
      await pg.close()
    } catch {
      // Already gone; the reset below is what matters.
    }
    await resetStore(dataDir)
    return undefined
  }

  log(
    `restored the pre-built world (${size}, chain ${stored?.fingerprint}) — no migrations were ` +
      'applied in this tab',
  )
  return pg
}

function describeError(err: unknown): string {
  return err instanceof Error ? err.message : String(err)
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
