// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FIRST SESSION — §K.1, played through the CLIENT SEAM
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
// WHY IT NAMES NO CARGO. §K.1's script reads "buy sal at Lisboa, sell it at Cádiz, 188 nm". All
// three were facts about a twelve-port world: the goods table is the real one now (so "sal" is
// three different commodities), the world is 214 real harbours (so which cargo pays is geography),
// and Lisboa to Cádiz is 248 nm sailed because Cape St Vincent is in the way. A spec that pins
// those is asserting a SEED. This one asks the market what a player would ask it, and plays the
// answer. The BEATS are asserted; the itinerary is discovered.
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

/** The player closes the app and time passes. Nothing ticks; they simply come back and look.
 *  Whatever voyage is running is pushed into the past, so the next read has it all to settle. */
async function timePasses() {
  await db.pg.query(
    `update public.voyages
        set departed_at = departed_at - (eta - now()) - interval '1 minute',
            eta         = now() - interval '1 minute'
      where status = 'SAILING'`,
  )
}

test('the first session: buy where it is cheap, sell where it is dear, come home richer', async () => {
  // ── 0:00 — the house, as the game opens ──────────────────────────────────────────────────────
  const snapshot = expectOk(await worldSnapshot())
  const lisboa = snapshot.ports.find((p) => p.code === 'LIS')!

  let fleet = expectOk(await worldFleets())[0]
  expect(fleet.name).toBe('Gaivota')
  expect(fleet.status).toBe('DOCKED')
  expect(fleet.port).toBe('LIS')
  expect(fleet.ships[0].class).toBe('Barca')

  const opening = expectOk(await worldLedger()).ducats!
  expect(opening).toBe(8000)

  // ── 0:20 — the MARKET tab, read the way a player reads it ────────────────────────────────────
  // What does this market mark BUY, and which port one leg away pays more for it?
  const here = expectOk(await worldMarket(lisboa.id))
  const buys = here.goods
    .filter((g) => g.available && g.advice === 'buy')
    .sort((a, b) => (a.pct_nbr ?? 100) - (b.pct_nbr ?? 100))
  expect(buys.length).toBeGreaterThan(0)

  const neighbours = snapshot.legs
    .filter((l) => l.from === 'LIS' || l.to === 'LIS')
    .map((l) => snapshot.ports.find((p) => p.code === (l.from === 'LIS' ? l.to : l.from))!)
  expect(neighbours.length).toBeGreaterThan(0)

  // A STARTER'S constraints are part of the choice, not a detail to work around afterwards: the
  // hold is 60 tuns and the purse is 8,000 ducats. Porcelain is the best gradient out of Lisbon
  // and 110 tuns of it costs 27,657 — the game says E_INSUFFICIENT_FUNDS, correctly, and a first
  // session that ignored the purse would be testing a player who does not exist.
  // FREE HOLD IS THE SERVER'S NUMBER, not a fold repeated here. This spec used to compute
  // `hold - cargo - water - food` by hand, which was a seventh copy of the rule migration 0017
  // folded onto `public.fleet_free_hold()` — and copies of that particular rule have already
  // drifted twice in this repo (one client copy forgot the stores entirely). Reading the served
  // field is also what makes this spec still true once an officer is posted: a quartermaster
  // changes the capacity, and a hand-fold here would silently ignore him.
  const spaceFor = (code: string) =>
    Math.floor(fleet.free_hold / snapshot.goods.find((g) => g.code === code)!.bulk)

  let cargo = buys[0]
  let destination = neighbours[0]
  let bestGain = 0
  for (const candidate of buys.slice(0, 12)) {
    // Enough purse to overfill the hold — so the refusal beat below is about SPACE, which is what
    // it means to test, rather than about money.
    if (candidate.buy * (spaceFor(candidate.code) + 20) >= opening) continue
    for (const port of neighbours) {
      const there = expectOk(await worldMarket(port.id)).goods.find((g) => g.code === candidate.code)!
      if (!there.available) continue
      const gain = (there.sell - candidate.buy) * spaceFor(candidate.code)
      if (gain > bestGain) {
        bestGain = gain
        cargo = candidate
        destination = port
      }
    }
  }
  expect(bestGain).toBeGreaterThan(0)        // somewhere out there is worth sailing to
  expect(cargo.pct_nbr!).toBeLessThan(100)   // and the %NBR column said so before we checked

  // Water the casks. §F.2 refuses a voyage the stores cannot cover, and a captain fills them at
  // the quay — that refusal is the game working, not an obstacle to route around.
  expectOk(await cmdIssue(fleet.id, 'PROVISION FULL'))
  fleet = expectOk(await worldFleets())[0]
  const stake = expectOk(await worldLedger()).ducats!

  // ── 0:40 — the order the tapped row composes, at a size that does NOT fit ────────────────────
  const bulk = snapshot.goods.find((g) => g.code === cargo.code)!.bulk
  const room = Math.floor(fleet.free_hold / bulk)
  expect(room).toBeGreaterThan(0)

  const tooMuch = await cmdIssue(fleet.id, `BUY ${cargo.code} ${room + 20}`, fleet.version)
  expect(tooMuch.ok).toBe(false)
  if (tooMuch.ok) throw new Error('unreachable')
  expect(tooMuch.refusal.code).toBe('E_HOLD_FULL')
  expect(tooMuch.refusal.sentence).toContain('room for')
  expect(tooMuch.refusal.fixes.length).toBeGreaterThanOrEqual(1)
  // CLEAR drops pending orders AND releases the halt a failed one puts the fleet under (§F.3).
  expectOk(await cmdClear(fleet.id))

  fleet = expectOk(await worldFleets())[0]
  const bought = expectOk(await cmdIssue(fleet.id, `BUY ${cargo.code} ${room}`, fleet.version))
  expect(bought.order.status).toBe('done')
  const spent = Number(bought.order.result!.total)
  expect(spent).toBeGreaterThan(0)

  fleet = expectOk(await worldFleets())[0]
  expect(fleet.ships[0].cargo[cargo.code]).toBe(room)
  expect(expectOk(await worldLedger()).ducats).toBe(stake - spent)

  // ── 1:20 — SAIL, typed the way a player types it ─────────────────────────────────────────────
  const sailed = expectOk(await cmdIssue(fleet.id, `SAIL Gaivota TO ${destination.code}`, fleet.version))
  expect(sailed.order.status).toBe('done')
  // The distance is the LEG's own sailed figure — the one that rounds capes — not a straight line.
  const leg = snapshot.legs.find(
    (l) =>
      (l.from === 'LIS' && l.to === destination.code) ||
      (l.from === destination.code && l.to === 'LIS'),
  )!
  expect(Number(sailed.order.result!.total_nm)).toBe(leg.nm)

  // ── 1:35 — "you queue the rest while it sails" ───────────────────────────────────────────────
  const homeward = expectOk(await worldMarket(destination.id))
    .goods.filter((g) => g.available && g.advice === 'buy')
    .sort((a, b) => (a.pct_nbr ?? 100) - (b.pct_nbr ?? 100))[0]
  expect(homeward).toBeDefined()

  expectOk(await cmdIssue(fleet.id, `SELL ${cargo.code} ALL`))
  expectOk(await cmdIssue(fleet.id, `BUY ${homeward.code} 10`))
  expectOk(await cmdIssue(fleet.id, 'SAIL Gaivota TO LIS'))

  fleet = expectOk(await worldFleets())[0]
  expect(fleet.status).toBe('SAILING')
  expect(fleet.voyage!.to).toBe(destination.code)
  expect(fleet.queue.filter((o) => o.status === 'pending')).toHaveLength(3)

  // ── 6:20 → 11:00 — the app is closed. No tick runs. THE READ IS THE CATCH-UP. ────────────────
  for (let i = 0; i < 24 && fleet.status === 'SAILING'; i += 1) {
    await timePasses()
    fleet = expectOk(await worldFleets())[0] // world.fleets() settles before it answers
  }

  expect(fleet.status).toBe('DOCKED')
  expect(fleet.port).toBe('LIS')
  expect(fleet.queue.filter((o) => o.status === 'pending')).toHaveLength(0)
  expect(fleet.queue.filter((o) => o.status === 'failed')).toHaveLength(0)
  expect(fleet.ships[0].cargo[cargo.code] ?? 0).toBe(0)
  expect(fleet.ships[0].cargo[homeward.code]).toBe(10)

  // The after-action report is PROSE (§E.6), and it reaches the client as prose.
  const log = expectOk(await worldLedger())
  const report = log.events.find((e) => e.kind === 'VOYAGE_REPORT')!
  expect(report).toBeDefined()
  const lines = report.payload.lines as string[]
  expect(Array.isArray(lines)).toBe(true)
  expect(lines[0]).toMatch(/^Day \d+\./)
  expect(lines[0].length).toBeGreaterThan(25)

  // ── the beat K.1 leaves implied: cargo in the hold is not ducats in the purse ─────────────────
  const sold = expectOk(await cmdIssue(fleet.id, `SELL ${homeward.code} ALL`, fleet.version))
  expect(sold.order.status).toBe('done')

  const closing = expectOk(await worldLedger())
  expect(closing.ducats!).toBeGreaterThan(stake)
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
