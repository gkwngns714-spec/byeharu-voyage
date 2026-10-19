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
//
// ── 2026-08-25: AND THE MARKET IS PINNED, FOR THE SAME REASON PROOF 04'S IS ────────────────────
// This spec had proof 04's defect and had never been given proof 04's fixture
// (docs/OWNER_REQUESTS.md:100). `public.tick_market_drift` moves every price by `random()`
// deliberately, and the chain's own self-asserts call it while applying, so every rebuild of the
// world deals a different market — and this file needs ONE SPECIFIC THING to exist: a cargo out of
// Lisboa that a neighbour pays more for, a return cargo Lisboa pays more for, and a hold that the
// destination's daily cap will take. On an unlucky draw one of those is missing and the spec goes
// red on a correct chain, which is how a gate stops gating.
//
// So the market is pinned by `proof.pin_market` — the ONE authority for it
// (scripts/db/market-fixture.mjs), shared with proofs 04 and 05 — with this file's own draw. The
// drift is REPLACED, not removed: every row is redrawn from the distribution the real process
// settles into, keyed on the authored port and good codes, so this is a representative market and
// the same one on every run and every machine. Weather is pinned too, and for the same reason proof
// 04 pins it: a hazard that strands the fleet halts the queue, which is the halt rule WORKING and
// incompatible with a spec whose claim is "the queue completes". Neither is asserted here; both
// have their own coverage.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
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
  worldReach,
  worldSnapshot,
} from '../src/lib/rpc'
import type { MarketGood } from '../src/lib/rpc'
import { buyableHere } from '../src/domain/market'
import { courseBetweenPorts, seaNav } from './seaCourse.fixture'
import { installMarketFixture } from '../scripts/db/market-fixture.mjs'

let db: LocalDb

/** This spec's own draw. Nothing else in the repo uses this key, so nothing else can move it. */
const FIXTURE_KEY = '00000000-0f51-4000-8000-000000000051'
const FIXTURE_SECRET = 'first-session-fixture'

test.beforeAll(async () => {
  // One full build of the 243-good world (D21): ~2-3 min in Node PGlite. The default hook
  // timeout was sized for a smaller chain.
  test.setTimeout(360_000)
  // The build's own world (tests/builtWorld.fixture.ts says why), not a from-zero apply.
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))

  // THE PRECONDITIONS THIS FILE OWNS — see the header. pin_market raises on its own vacuity, so a
  // fixture that stopped applying reddens here rather than turning this spec back into a lottery.
  await installMarketFixture(db.pg)
  await db.pg.query(`select proof.pin_market($1::uuid, $2, 'fs1:', 'fs2:')`, [
    FIXTURE_KEY,
    FIXTURE_SECRET,
  ])
  await db.pg.query(`update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max'`)
  const { rows } = await db.pg.query<{ hazard: string; drifted: number; off_target: number }>(
    `select public.wc_num('hazard_p_max')::text as hazard,
            (select count(*)::int from public.port_goods where drift <> 0) as drifted,
            (select count(*)::int from public.port_goods where stock <> stock_target) as off_target`,
  )
  expect(Number(rows[0].hazard)).toBe(0)
  expect(rows[0].drifted).toBeGreaterThan(14_000)
  expect(rows[0].off_target).toBe(0)
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
  // 0061: `buyableHere` (culture AND roster), not `available` (culture only) — the same one
  // authority the market screen buys through. `world.market` already serves only what this quay
  // shows, so at Lisboa on turn one the two agree; asking the narrower question anyway is what
  // stops this line going quietly wrong the first time she reads a quay with cargo aboard.
  // 0071: this used to ask the server which rows were CHEAP HERE and rank them by the neighbour
  // index. Both are gone — that comparison is the answer the game exists to make the player find —
  // so the simulation reasons the way a player now has to: of what this quay actually deals in,
  // start with the cheapest thing on it. No server opinion, and the gain below still has to be
  // real for the test to pass, which is what was ever being measured.
  const buys = here.goods.filter((g) => buyableHere(g)).sort((a, b) => a.mid - b.mid)
  expect(buys.length).toBeGreaterThan(0)

  // 0039: the sailed distance table (world.reach) — the same one the endurance gate and the trade scan read;
  // the voyage below is checked against it. (Until 2026-10-19 this spec also searched the 24 nearest harbours
  // for its own cargo — 0061 moved that from eight to 24; 0208 replaced the search with world.trade_routes.)
  const reachHere = expectOk(await worldReach(lisboa.id)).reaches


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

  // WHAT SHE WILL ACTUALLY TRADE: the hold bounds it here, and the DESTINATION's daily cap
  // (G.7.1: daily_cap_fraction x stock_target, per player-port-good) bounds it there — a spec
  // that sells ALL of a full hold at a small market is asserting an ambient it does not own,
  // and on the 243-good catalogue it found one (Chank Shells, cap 23, hold 43: E_DAILY_CAP,
  // measured 2026-08-24). The fraction is deliberately NOT served (players meet the cap as a
  // refusal), so the bound composes the two chain rules a red would name: stock_target is
  // floored at 60 (0005's own greatest(60, …), re-asserted over every row by 0041) and the
  // fraction is 0.35 — their product floors every cap at 21. If either knob moves, this line
  // is the one to move with it.
  // Moved deliberately 2026-10-19 with 0208: 0207 made every market ten times deeper (market_depth 10, so
  // the floor is 600 × 0.35 = 210 a day) and 0208 made goods a fifth the price. At 20 units the round trip's
  // profit no longer covered the crew's wages (public.wages_from_profit takes a profit up to what is owed),
  // and she came home with exactly her stake. 200 is under the new floor of 210, as 20 was under 21.
  const CAP_SAFE = 200
  const tradeQty = (code: string) => Math.min(spaceFor(code), CAP_SAFE)

  // ── 0061: A FIRST SESSION NEEDS A PORT THAT TRADES BOTH WAYS ─────────────────────────────────
  // The market is held still by `installMarketFixture` above, so every quay read below is the same
  // quay twice — these reads are cached for speed, not to dodge a moving price.
  const quays = new Map<string, MarketGood[]>()
  const quayAt = async (port: { id: string; code: string }) => {
    const seen = quays.get(port.code)
    if (seen) return seen
    const goods = expectOk(await worldMarket(port.id)).goods
    quays.set(port.code, goods)
    return goods
  }

  /**
   * THE BEST THING TO CARRY HOME FROM A QUAY — asked the way the GAME asks it.
   *
   * `buyableHere` is the market section's one predicate (src/domain/market — it was the market
   * screen's until PORT needed it too, and §7 step 6 deleted the screen's re-export with the rest
   * of marketRows.ts): a good
   * is buyable when the culture allows it AND the city's roster names it, and `cmd.do_buy` refuses
   * everything else with `E_UNAVAILABLE`. This spec used to filter on `available` alone, which is
   * only the culture half — under 0061 that can pick a good the very next BUY would refuse, so the
   * old line was not merely too weak, it was wrong. One authority, both callers.
   */
  //
  // 0071: `except` is new and it is not a nicety. While this picked the good the SERVER called
  // cheap, the outbound and homeward cargoes could not collide — the two quays advised differently.
  // Choosing the cheapest thing on each quay can land on the SAME good at both ends, and then she
  // sells a hold of it and immediately buys it back, which is not a round trip and left the
  // assertion below reading 10 where it wanted 0.
  const homewardFrom = (goods: readonly MarketGood[], except?: string) =>
    goods
      .filter((g) => buyableHere(g) && g.code !== except)
      .sort((a, b) => a.mid - b.mid)[0]

  // 2026-10-19 (0208: goods a fifth the price, the distance premium halved, wages unchanged): THE OUTBOUND
  // CARGO IS THE GAME'S OWN BEST TRADE, world.trade_routes — the read proof 05 measures the first voyage by —
  // not this spec's own scan. The scan priced one unit's ask against one unit's bid at the cities whose ROSTER
  // trades the good, so it only ever saw the thin gradient between makers (haul 1). At ÷ 5 that gradient no
  // longer pays the crew: measured on this pinned market, the best it found was cork to Porto, quoted +4 on
  // 82 units and sold −3 after the price walk, and at 20 units the profit went whole to the wages (she came
  // home with exactly her stake). Priced with the walk at the real quantity, none of Lisboa's reachable
  // harbours paid. The claim is unchanged and no weaker: she must still come home richer — on the trade the
  // game shows her, whose every figure is world.quote's.
  type Route = { code: string; to: { code: string }; qty: number; profit: number }
  const routes = (await db.callAs<{ routes: Route[] }>(
    'select world.trade_routes($1::uuid, $2::uuid, null, null) as result', [lisboa.id, fleet.id])).routes
  expect(routes.length).toBeGreaterThan(0)
  let cargo = buys[0]
  let destination = lisboa
  let bestGain = 0
  let routeQty = 0
  for (const r of [...routes].sort((a, b) => b.profit - a.profit)) {
    const good = here.goods.find((g) => g.code === r.code && buyableHere(g))
    const port = snapshot.ports.find((p) => p.code === r.to.code && p.kind === 'HARBOUR')
    if (!good || !port || r.profit <= 0) continue
    // 0061: AND SHE MUST HAVE SOMETHING TO CARRY BACK (§K.1 is the ROUND TRIP)
    if (!homewardFrom(await quayAt(port), good.code)) continue
    // Enough purse to overfill the hold — so the refusal beat below is about SPACE, which is what
    // it means to test, rather than about money.
    if (good.buy * (spaceFor(good.code) + 20) >= opening) continue
    cargo = good
    destination = port
    bestGain = r.profit
    routeQty = r.qty
    break
  }
  console.log(`first session: ${cargo.code} to ${destination.code}, ${routeQty} units quoted at +${bestGain}`)
  expect(bestGain).toBeGreaterThan(0)        // somewhere out there is worth sailing to

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
  expect(tooMuch.refusal.fixes.length).toBeGreaterThanOrEqual(1)
  // AND THE PLAYER IS SHOWN THE ARITHMETIC AS A BAR, not asked to read it out of a paragraph
  // (migration 0050). The figures are the SERVER'S OWN numbers — `have` is the free hold this
  // spec computed from `fleet.free_hold` independently, which is what makes this an agreement
  // between two sides rather than a restatement of one. The old assertion pinned the sentence's
  // wording ("room for"), so shortening the prose would have reddened a correct chain.
  expect(tooMuch.refusal.figures).toEqual({ have: room, need: room + 20, unit: 't' })
  expect(tooMuch.refusal.sentence).not.toMatch(/\d/)
  // CLEAR drops pending orders AND releases the halt a failed one puts the fleet under (§F.3).
  expectOk(await cmdClear(fleet.id))

  fleet = expectOk(await worldFleets())[0]
  const qty = Math.min(tradeQty(cargo.code), routeQty)
  const bought = expectOk(await cmdIssue(fleet.id, `BUY ${cargo.code} ${qty}`, fleet.version))
  expect(bought.order.status).toBe('done')
  const spent = Number(bought.order.result!.total)
  expect(spent).toBeGreaterThan(0)

  fleet = expectOk(await worldFleets())[0]
  expect(fleet.ships[0].cargo[cargo.code]).toBe(qty)
  expect(expectOk(await worldLedger()).ducats).toBe(stake - spent)

  // ── 1:20 — SAIL, typed the way a player types it ─────────────────────────────────────────────
  // 0039: the player's client PROPOSES the course; the server verifies it and MEASURES the
  // miles itself. The spec plays the client's part with the app's own pathfinder.
  const sailed = expectOk(
    await cmdIssue(
      fleet.id,
      `SAIL Gaivota TO ${destination.code}`,
      fleet.version,
      courseBetweenPorts(await seaNav(), lisboa, destination),
    ),
  )
  expect(sailed.order.status).toBe('done')

  // 0045 runs the world twenty times faster: this passage is ~30 REAL SECONDS, and the reads
  // between orders (world.market wound the drift over every row until 0137; its own quay since) cost seconds each in a WASM
  // database — so without this the fleet ARRIVES underneath the spec's own typing and the
  // "queue the rest while it sails" beat executes at the quay instead of queueing (measured
  // 2026-08-24: the SELL ran at the destination and was refused by its daily cap). Time is held
  // still the same way timePasses() moves it — shifting departed_at and eta TOGETHER, which
  // keeps the closed-form schedule identical in shape while progress clamps at 0 — because the
  // beat under test is "orders land while she is at sea", never the player's typing speed.
  await db.pg.query(
    `update public.voyages
        set departed_at = departed_at + interval '1 hour', eta = eta + interval '1 hour'
      where status = 'SAILING'`,
  )
  // The distance is the SAILED figure that rounds capes, never a straight line — and it agrees
  // with the quay's own reach quote to half a per cent (one generator, two roundings).
  const quoted = reachHere[destination.code]
  const measured = Number(sailed.order.result!.total_nm)
  expect(measured).toBeGreaterThan(0)
  expect(Math.abs(measured - quoted)).toBeLessThan(Math.max(0.5, quoted * 0.005))

  // ── 1:35 — "you queue the rest while it sails" ───────────────────────────────────────────────
  // Read the quay FRESH — she has sailed since, and a spec that plans from a cached payload is
  // planning from a world that no longer exists. `homewardFrom` is the same predicate the
  // destination was chosen with, so this cannot be undefined unless the quay itself changed.
  const homeward = homewardFrom(expectOk(await worldMarket(destination.id)).goods, cargo.code)
  expect(homeward).toBeDefined()

  expectOk(await cmdIssue(fleet.id, `SELL ${cargo.code} ALL`))
  expectOk(await cmdIssue(fleet.id, `BUY ${homeward.code} 10`))
  expectOk(
    await cmdIssue(fleet.id, 'SAIL Gaivota TO LIS', null, courseBetweenPorts(await seaNav(), destination, lisboa)),
  )

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
