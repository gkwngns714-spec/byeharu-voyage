// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE RESCUE — take the player's own rows OUT of a world that is about to be demolished
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ── THE DEFECT THIS EXISTS TO CLOSE (2026-08-20, reported by the owner) ─────────────────────────
// The owner played the game, bought cargo, and watched the purse go down. A migration was edited
// later that day — 0005, for speed, with the economy proved bit-identical — and on their next load
// the purse was back at 8,000 ducats. The voyage, the cargo and the ledger were gone.
//
// Nothing had gone wrong with the game. localDb.ts does exactly what its own header promises:
// "if the build carries a different chain, the stored database is DEMOLISHED and rebuilt from
// migration 0001". Editing ANY migration changes the chain fingerprint, and `demolish()` is a
// `drop schema public cascade` — the world AND the house standing in it.
//
// That rule is right, and it stays: applying six new migrations onto a four-migration database
// produces a schema that exists in no repository. What was wrong is that the player's own rows
// went down with it SILENTLY and IRRECOVERABLY. Two separate faults, and this file fixes the
// second one:
//
//   1. It happened without a word.        → bootState carries `rescued`, and the app says so.
//   2. It could not be undone.            → every player row is dumped to localStorage FIRST.
//
// ── WHAT THIS DELIBERATELY DOES NOT DO ──────────────────────────────────────────────────────────
// IT DOES NOT REPLAY THE SAVE INTO THE NEW WORLD, and pretending it could would be worse than not
// having it. Every world row is keyed by a `gen_random_uuid()` primary key, so a rebuild gives
// every port, good and ship class a NEW id. `fleets.port_id`, `voyages.from_port_id`,
// `ships.class_id` and the cargo's `good_id` in a rescued row all point at uuids that no longer
// exist. A replay would have to translate each one back through its stable code (ports.code,
// goods.code, ship_classes.name) and would have to prove the destination table still has the same
// shape. That is a real piece of work with its own proofs — see DEV_LOG D11c — and this file is
// the half that had to exist first: THE DATA MUST SURVIVE BEFORE ANYTHING CAN RESTORE IT.
//
// So the contract here is narrow and honest: when a world is demolished, the player's rows are
// already on disk, in JSON, with their column names, and the app says where they went.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { PGlite } from '@electric-sql/pglite'

/**
 * The tables that hold what a PLAYER did, as opposed to what the world IS.
 *
 * The world (ports, legs, goods, port_goods, ship_classes, world_config…) is rebuilt from the
 * chain and is not worth a byte of storage — it is in the repository. These are the rows that
 * exist nowhere else. Ordered parent-first, so a future restore can walk the list forwards.
 */
export const PLAYER_TABLES = [
  'players',
  'fleets',
  'ships',
  'voyages',
  'voyage_events',
  'orders',
  'events',
  'ledger',
] as const

/** localStorage key for the most recent rescue. One slot: a rescue supersedes the last one. */
export const RESCUE_KEY = 'byeharu-voyage.rescued.v1'

/** Anything bigger than this is not going in localStorage, which is a ~5 MB budget for the whole
 *  origin. A rescue that evicts the app's other keys would be a second bug. */
const MAX_BYTES = 2_000_000

export interface Rescue {
  /** The fingerprint of the chain that built the world these rows came from. */
  fingerprint: string
  /** ISO timestamp of the rescue. */
  at: string
  /** table name → the rows it held, as plain objects keyed by column name. */
  tables: Record<string, unknown[]>
  /** Total rows across every table. */
  rows: number
  /** Set when a table existed but could not be read — the reason, for the log. */
  skipped: Record<string, string>
}

/** What the caller needs to report, without having to hold the payload. */
export interface RescueReceipt {
  rows: number
  tables: number
  stored: boolean
  /** Why it was not stored, when it was not. */
  note: string | null
}

type Storage = Pick<globalThis.Storage, 'getItem' | 'setItem' | 'removeItem'>

function defaultStorage(): Storage | null {
  try {
    return typeof localStorage === 'undefined' ? null : localStorage
  } catch {
    // Private-mode storage throws on access. A rescue that cannot be stored is reported, not fatal.
    return null
  }
}

/**
 * Read every player row out of `pg` and stash it. Call this BEFORE `demolish()`, while the old
 * schema is still standing.
 *
 * NEVER THROWS. It runs on the path to a rebuild the player did not ask for; a failure here must
 * degrade to "we could not save your voyage", never to a boot that dies. Every failure mode —
 * a missing table, an unreadable one, storage that is full or absent — comes back as a receipt.
 */
export async function rescuePlayerRows(
  pg: Pick<PGlite, 'query'>,
  fingerprint: string,
  storage: Storage | null = defaultStorage(),
  now: () => Date = () => new Date(),
): Promise<RescueReceipt> {
  const rescue: Rescue = { fingerprint, at: now().toISOString(), tables: {}, rows: 0, skipped: {} }

  for (const table of PLAYER_TABLES) {
    try {
      // `to_regclass` returns null rather than raising for a table that is not there — a world
      // built by a SHORTER chain genuinely will not have all of these.
      const exists = await pg.query<{ present: boolean }>(
        'select to_regclass($1) is not null as present',
        [`public.${table}`],
      )
      if (!exists.rows[0]?.present) continue
      const r = await pg.query<Record<string, unknown>>(`select * from public.${table}`)
      if (r.rows.length === 0) continue
      rescue.tables[table] = r.rows
      rescue.rows += r.rows.length
    } catch (err) {
      rescue.skipped[table] = err instanceof Error ? err.message : String(err)
    }
  }

  const tables = Object.keys(rescue.tables).length
  if (rescue.rows === 0) {
    return { rows: 0, tables: 0, stored: false, note: 'there was nothing of yours in it' }
  }
  if (!storage) {
    return { rows: rescue.rows, tables, stored: false, note: 'this browser allows no local storage' }
  }

  let json: string
  try {
    json = JSON.stringify(rescue)
  } catch (err) {
    return {
      rows: rescue.rows,
      tables,
      stored: false,
      note: `it could not be serialised (${err instanceof Error ? err.message : String(err)})`,
    }
  }
  if (json.length > MAX_BYTES) {
    return {
      rows: rescue.rows,
      tables,
      stored: false,
      note: `it is ${Math.round(json.length / 1024)} KB, over the ${MAX_BYTES / 1024} KB this browser slot allows`,
    }
  }
  try {
    storage.setItem(RESCUE_KEY, json)
  } catch (err) {
    return {
      rows: rescue.rows,
      tables,
      stored: false,
      note: `this browser refused to store it (${err instanceof Error ? err.message : String(err)})`,
    }
  }
  return { rows: rescue.rows, tables, stored: true, note: null }
}

/** Read back the stashed rescue, or null. Never throws on garbage — a corrupt byte is a null. */
export function readRescue(storage: Storage | null = defaultStorage()): Rescue | null {
  try {
    const raw = storage?.getItem(RESCUE_KEY)
    if (!raw) return null
    const parsed: unknown = JSON.parse(raw)
    if (!parsed || typeof parsed !== 'object') return null
    const r = parsed as Partial<Rescue>
    if (typeof r.fingerprint !== 'string' || typeof r.rows !== 'number' || !r.tables) return null
    return parsed as Rescue
  } catch {
    return null
  }
}

/** Throw the stash away. Only the player, through the UI, should ever ask for this. */
export function forgetRescue(storage: Storage | null = defaultStorage()): void {
  try {
    storage?.removeItem(RESCUE_KEY)
  } catch {
    /* nothing to do: a storage that will not delete is a storage that never stored */
  }
}
