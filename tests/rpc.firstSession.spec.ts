// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TEN-MINUTE FIRST SESSION — §K.1, played through the CLIENT SEAM
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `scripts/db/proofs/04_first_session.sql` already proves this session in SQL. This proves it
// again through src/lib/rpc — same beats, same typed strings, but every call goes through the
// dispatcher, the catalogue, the backend and the refusal contract that a screen will use.
//
// The two proofs answer different questions. The SQL one asks "does the game work?". This one asks
// "does the game work FROM THE CLIENT?" — and it would go red on a mis-cast parameter, a dropped
// argument, an identity that does not survive the call, or a refusal that arrives as a thrown
// string. None of those are visible from inside Postgres.
//
// ONE THING HAPPENS BEHIND THE SEAM, and it is marked where it happens: TIME. A voyage takes real
// minutes and a spec has seconds, so the departure is backdated with a direct UPDATE — the same
// device proof 04 and migration 0009's self-assert use. Everything else is the player's own words.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import {
  clearBackend,
  cmdClear,
  cmdIssue,
  createLocalBackend,
  expectOk,
  setBackend,
  worldFleets,
  worldLedger,
  worldMarket,
  worldSnapshot,
} from '../src/lib/rpc'

let db: LocalDb

test.beforeAll(async () => {
  db = await openLocalDb({ loadChain, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

/** The player closes the app and time passes. Nothing ticks; they simply come back and look. */
async function timePasses(minutes: number) {
  await db.pg.query(
    `update public.voyages
        set departed_at = departed_at - make_interval(mins => $1::int),
            eta         = eta         - make_interval(mins => $1::int)
      where status = 'SAILING'`,
    [minutes],
  )
}

test('§K.1: buy salt at Lisboa, sell it at Cádiz, bring hides home, and end richer', async () => {
  // ── 0:00 — the house, as the game opens ──────────────────────────────────────────────────────
  const snapshot = expectOk(await worldSnapshot())
  const lisboa = snapshot.ports.find((p) => p.code === 'LIS')!
  const cadiz = snapshot.ports.find((p) => p.code === 'CAD')!

  let fleet = expectOk(await worldFleets())[0]
  expect(fleet.name).toBe('Gaivota')
  expect(fleet.status).toBe('DOCKED')
  expect(fleet.port).toBe('LIS')
  expect(fleet.ships[0].class).toBe('Barca')

  const opening = expectOk(await worldLedger()).ducats!
  expect(opening).toBe(8000)

  // ── 0:20 — the MARKET tab. Salt is cheap here and dear there; that IS the game. ──────────────
  const here = expectOk(await worldMarket(lisboa.id))
  const there = expectOk(await worldMarket(cadiz.id))
  const salHere = here.goods.find((g) => g.code === 'sal')!
  const salThere = there.goods.find((g) => g.code === 'sal')!
  expect(salHere.advice).toBe('buy')
  expect(salHere.pct_nbr!).toBeLessThan(90)
  expect(salThere.pct_nbr!).toBeGreaterThan(110)
  expect(salThere.sell).toBeGreaterThan(salHere.buy)

  // ── 0:40 — the script's own order, and the honest refusal it earns ───────────────────────────
  // §K.1 says "BUY sal 60". A 60-tun hold carrying stores has no room for 60 tuns, and the game
  // says so, in a sentence, with a fix. The DESIGN's arithmetic is wrong; its beat is not.
  const tooMuch = await cmdIssue(fleet.id, 'BUY sal 60', fleet.version)
  expect(tooMuch.ok).toBe(false)
  if (tooMuch.ok) throw new Error('unreachable')
  expect(tooMuch.refusal.code).toBe('E_HOLD_FULL')
  expect(tooMuch.refusal.fixes.length).toBeGreaterThanOrEqual(1)
  // CLEAR drops PENDING orders; the refused one stays in the queue as `failed`, which is the log
  // of what the player tried. Its seq is remembered so the end-of-session check can require every
  // OTHER order to have succeeded, rather than quietly tolerating any failure at all.
  const refusedSeq = tooMuch.refusal.queue!.find((o) => o.error_code === 'E_HOLD_FULL')!.seq
  expectOk(await cmdClear(fleet.id))

  fleet = expectOk(await worldFleets())[0]
  const bought = expectOk(await cmdIssue(fleet.id, 'BUY sal 50', fleet.version))
  expect(bought.order.status).toBe('done')
  const spent = Number(bought.order.result!.total)
  expect(spent).toBeGreaterThan(0)

  fleet = expectOk(await worldFleets())[0]
  expect(fleet.ships[0].cargo.sal).toBe(50)
  expect(expectOk(await worldLedger()).ducats).toBe(opening - spent)

  // ── 1:20 — SAIL, typed exactly as the script types it ────────────────────────────────────────
  const sailed = expectOk(await cmdIssue(fleet.id, 'SAIL Gaivota TO Cadiz', fleet.version))
  expect(sailed.order.status).toBe('done')
  expect(Number(sailed.order.result!.total_nm)).toBe(188)

  // ── 1:35 — "you queue the rest while it sails" ───────────────────────────────────────────────
  expectOk(await cmdIssue(fleet.id, 'SELL sal ALL'))
  expectOk(await cmdIssue(fleet.id, 'BUY couro 40'))
  expectOk(await cmdIssue(fleet.id, 'SAIL Gaivota TO Lisboa'))

  fleet = expectOk(await worldFleets())[0]
  expect(fleet.status).toBe('SAILING')
  expect(fleet.voyage!.to).toBe('CAD')
  expect(fleet.queue.filter((o) => o.status === 'pending')).toHaveLength(3)

  // ── 6:20 → 11:00 — the app is closed. No tick runs. THE READ IS THE CATCH-UP. ────────────────
  for (let i = 0; i < 2; i += 1) {
    await timePasses(30)
    fleet = expectOk(await worldFleets())[0] // world.fleets() settles before it answers
  }

  expect(fleet.status).toBe('DOCKED')
  expect(fleet.port).toBe('LIS')
  expect(fleet.queue.filter((o) => o.status === 'pending')).toHaveLength(0)
  expect(fleet.queue.filter((o) => o.status === 'failed' && o.seq !== refusedSeq)).toHaveLength(0)
  expect(fleet.ships[0].cargo.sal ?? 0).toBe(0)
  expect(fleet.ships[0].cargo.couro).toBe(40)

  // The after-action report is PROSE (§E.6), and it reaches the client as prose.
  const log = expectOk(await worldLedger())
  const report = log.events.find((e) => e.kind === 'VOYAGE_REPORT')!
  expect(report).toBeDefined()
  const lines = report.payload.lines as string[]
  expect(Array.isArray(lines)).toBe(true)
  expect(lines[0]).toMatch(/^Day \d+\./)
  expect(lines[0].length).toBeGreaterThan(25)

  // ── the beat K.1 leaves implied: hides in the hold are not ducats in the purse ────────────────
  const sold = expectOk(await cmdIssue(fleet.id, 'SELL couro ALL', fleet.version))
  expect(sold.order.status).toBe('done')

  const closing = expectOk(await worldLedger())
  expect(closing.ducats!).toBeGreaterThan(opening)
  // The purse and the log agree to the ducat — the invariant the chain enforces with triggers,
  // read back through the same seam a screen reads it through.
  expect(closing.ledger_sum).toBe(closing.ducats)

  // The session's whole story is in the log, newest first, founding at the bottom.
  const kinds = new Set(closing.events.map((e) => e.kind))
  for (const kind of ['FOUNDED', 'BOUGHT', 'DEPARTED', 'VOYAGE_REPORT', 'SOLD']) {
    expect(kinds.has(kind), `the ledger should carry a ${kind} event`).toBe(true)
  }
  const full = expectOk(await worldLedger(null, 200))
  expect(full.events[full.events.length - 1].kind).toBe('FOUNDED')

  // AN HONEST GAP, asserted rather than assumed: WAGES are credited with no event behind them
  // (0007 calls public.credit() without emit_event), so they reconcile inside `ducats` but never
  // appear as a line in `events`. Summing the visible deltas therefore OVERSTATES the purse — and
  // a LEDGER screen that adds up the rows it renders will disagree with the balance it prints.
  const visible = full.events.reduce((sum, e) => sum + (e.ducats_delta ?? 0), 0)
  expect(visible).toBeGreaterThan(closing.ducats!)

  // And the fleet is simply home: nothing pending, nothing aboard, ready for the next order. A
  // screen mounting now — after a reload, against the persisted world — would read exactly this.
  const home = expectOk(await worldFleets())[0]
  expect(home.status).toBe('DOCKED')
  expect(home.port).toBe('LIS')
  expect(home.ships[0].cargo_tuns).toBe(0)
  expect(home.queue.filter((o) => o.status === 'pending')).toHaveLength(0)
})
