// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE RPC SURFACE — every function, against the real chain, checked against what the types claim
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A TypeScript interface over a jsonb payload is an ASSERTION, not a guarantee: the compiler has
// never seen the server. So every field src/lib/rpc/types.ts declares is read back here out of a
// payload a real PostgreSQL produced. If a migration renames a key, this file goes red — instead
// of a screen going blank in a player's hands.
//
// PURE UNIT SPEC. No browser: PGlite runs in this process, and the backend under test is exactly
// the one the app installs in local mode.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import {
  RPCS,
  backendKind,
  clearBackend,
  cmdCancel,
  cmdClear,
  cmdFoundHouse,
  cmdHaggle,
  cmdIssue,
  cmdPreview,
  cmdVerbSchema,
  createLocalBackend,
  expectOk,
  fromError,
  localSql,
  namedArgs,
  rpcLabel,
  setBackend,
  worldFleets,
  worldHaggleState,
  worldLedger,
  worldMarket,
  worldProvisionPresets,
  cmdProvisionPresetSave,
  cmdProvisionPresetDelete,
  cmdProvisionPresetApply,
  worldSnapshot,
} from '../src/lib/rpc'

let db: LocalDb

test.beforeAll(async () => {
  // One full build of the 243-good world (D21): ~2-3 min in Node PGlite. The default hook
  // timeout was sized for a smaller chain.
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

const isNum = (v: unknown) => typeof v === 'number' && Number.isFinite(v)
const isStr = (v: unknown) => typeof v === 'string' && v.length > 0

// ── the reads ──────────────────────────────────────────────────────────────────────────────────

test('world.snapshot() carries the whole static world, and not the world secret', async () => {
  const snap = expectOk(await worldSnapshot())
  // COUNTED, NOT REMEMBERED. The world is 214 real harbours now and it will grow again; a spec
  // that pins the number is asserting a seed, and goes red the day a port is added — which is not
  // a defect. What the reader owes us is "everything the world holds, and nothing invented".
  expect(snap.ports.length).toBeGreaterThan(100)
  expect(snap.legs.length).toBeGreaterThan(snap.ports.length)     // a world you can sail across
  expect(snap.goods.length).toBeGreaterThan(20)
  expect(snap.ship_classes).toHaveLength(3)
  expect(snap.verbs).toHaveLength(8)

  const lisboa = snap.ports.find((p) => p.code === 'LIS')
  expect(lisboa).toBeDefined()
  // Every field SnapshotPort declares, read back off a real row.
  expect(isStr(lisboa!.id)).toBe(true)
  // The port table carries the dataset's English names — the same strings the coordinate
  // validator checks against Wikidata. Local forms (Lisboa, Sevilla, Napoli) live in
  // data/ports.json as `localName` and are a presentation decision, not a data one.
  expect(lisboa!.name).toBe('Lisbon')
  expect(isStr(lisboa!.country)).toBe(true)
  expect(lisboa!.nation).toBe('PRT')
  expect(isNum(lisboa!.lat) && isNum(lisboa!.lon)).toBe(true)
  expect(isStr(lisboa!.sea) && isStr(lisboa!.region)).toBe(true)
  expect(lisboa!.culture).toBe('latin')
  expect(isNum(lisboa!.size_tier) && isNum(lisboa!.max_draft)).toBe(true)
  expect(typeof lisboa!.has_yard).toBe('boolean')
  expect(typeof lisboa!.has_academy).toBe('boolean')
  expect(typeof lisboa!.is_ice_closed).toBe('boolean')
  expect(isNum(lisboa!.yard_tier) && isNum(lisboa!.tax_rate) && isNum(lisboa!.crew_pool)).toBe(true)
  expect(isNum(lisboa!.dev_industry) && isNum(lisboa!.dev_commerce) && isNum(lisboa!.dev_military)).toBe(
    true,
  )

  const leg = snap.legs[0]
  expect(isStr(leg.id) && isStr(leg.from) && isStr(leg.to)).toBe(true)
  expect(isNum(leg.nm) && isNum(leg.hazard_mult)).toBe(true)
  // Canonically ordered, stored once, both ends resolvable to a port in the same payload.
  const codes = new Set(snap.ports.map((p) => p.code))
  for (const l of snap.legs) expect(codes.has(l.from) && codes.has(l.to)).toBe(true)

  const sal = snap.goods.find((g) => g.code === 'salt')!
  expect(isStr(sal.id) && isStr(sal.name)).toBe(true)
  expect(isNum(sal.base_value) && isNum(sal.bulk) && isNum(sal.perishable_pct_day)).toBe(true)
  expect(Array.isArray(sal.culture_mask)).toBe(true)
  const vinho = snap.goods.find((g) => g.code === 'wine')!
  expect(vinho.culture_mask).toContain('islamic')

  const barca = snap.ship_classes.find((c) => c.code === 'barca')!
  expect(barca.name).toBe('Barca')
  expect(barca.hold).toBe(60)
  expect(isNum(barca.speed_kn) && isNum(barca.crew_required) && isNum(barca.crew_max)).toBe(true)
  expect(isNum(barca.durability) && isNum(barca.draft) && isNum(barca.tier)).toBe(true)
  expect(isStr(barca.rig) && isStr(barca.family)).toBe(true)

  expect(snap.config.time_compression).toBe(480)
  expect(snap.config.order_queue_max).toBe(12)
  for (const key of [
    'fleet_max',
    'ship_max',
    'endurance_margin',
    'trade_step_tuns',
    'water_per_crew_day',
    'food_per_crew_day',
    'wage_per_crew_day',
  ] as const) {
    expect(isNum(snap.config[key]), `config.${key}`).toBe(true)
  }

  // §B.6: the hazard seed must not be in a payload every browser gets. Searched for BY VALUE, the
  // way migration 0009 asserts it — an allow-list of key names proves only that nobody named it.
  const secret = await db.pg.query<{ v: string }>("select public.wc_text('world_secret') as v")
  expect(secret.rows[0].v.length).toBeGreaterThanOrEqual(8)
  expect(JSON.stringify(snap)).not.toContain(secret.rows[0].v)
})

test('world.market() prices every good, with %NBR, stock band, availability and advice', async () => {
  const snap = expectOk(await worldSnapshot())
  const lis = snap.ports.find((p) => p.code === 'LIS')!
  const tun = snap.ports.find((p) => p.code === 'TUN')!

  const market = expectOk(await worldMarket(lis.id))
  expect(market.port).not.toBeNull()
  expect(market.port!.code).toBe('LIS')
  expect(isNum(market.port!.tax_rate) && isNum(market.port!.spread)).toBe(true)
  expect(isNum(market.port!.dev_commerce) && isStr(market.port!.culture)).toBe(true)
  expect(market.goods).toHaveLength(snap.goods.length)     // every good the world trades, priced

  // THE PRICES' OWN CLOCK (0029): two served instants a countdown subtracts — never a cadence
  // knob a client multiplies. `next_change_at` is strictly ahead of the payload's own `now`
  // (a boundary instant serves the NEXT boundary), and by no more than a whole slot, read from
  // the server's knob here only to bound the claim — the client never sees slot_seconds on this
  // payload, which is the point.
  const clockNow = Date.parse(market.clock.now)
  const nextChange = Date.parse(market.clock.next_change_at)
  expect(Number.isFinite(clockNow) && Number.isFinite(nextChange)).toBe(true)
  expect(nextChange).toBeGreaterThan(clockNow)
  const slotMs = Number(
    (await db.pg.query<{ v: number }>("select public.wc_num('drift_slot_seconds')::float8 as v"))
      .rows[0].v,
  ) * 1000
  expect(nextChange - clockNow).toBeLessThanOrEqual(slotMs)

  for (const g of market.goods) {
    expect(isStr(g.good_id) && isStr(g.code) && isStr(g.name) && isStr(g.category)).toBe(true)
    expect(g.buy).toBeGreaterThan(0)
    expect(g.sell).toBeGreaterThan(0)
    expect(g.buy).toBeGreaterThan(g.sell) // the spread, in the direction that costs the player
    expect(isNum(g.mid)).toBe(true)
    expect(g.pct_nbr === null || isNum(g.pct_nbr)).toBe(true)
    expect(isNum(g.stock) && isNum(g.stock_target)).toBe(true)
    expect(g.stock_band).toBeGreaterThanOrEqual(0)
    expect(g.stock_band).toBeLessThanOrEqual(6)
    expect(typeof g.available).toBe('boolean')
    expect(['buy', 'hold', 'sell']).toContain(g.advice)
  }

  // The culture mask is a fact about the port, and it shows through as a flag, not as a price.
  expect(market.goods.find((g) => g.code === 'wine')!.available).toBe(true)
  const tunis = expectOk(await worldMarket(tun.id))
  expect(tunis.goods.find((g) => g.code === 'wine')!.available).toBe(false)

  // A GRADIENT EXISTS, through the client seam. Which good and which pair is geography — 214 ports
  // and 14,980 derived prices decide it — so the spec asks the payload for one instead of naming
  // the pair a twelve-port design document once quoted.
  const buys = market.goods.filter((g) => g.advice === 'buy' && g.available)
  expect(buys.length).toBeGreaterThan(0)                       // somewhere here is worth loading
  for (const g of buys) expect(g.pct_nbr!).toBeLessThan(100)   // and the advice agrees with the number

  // The other end of the same gradient: the good this port marks as a BUY reads dearer somewhere
  // one leg away, which is the entire proposition of the game.
  const cheapest = buys.sort((a, b) => (a.pct_nbr ?? 100) - (b.pct_nbr ?? 100))[0]
  const neighbours = snap.legs
    .filter((l) => l.from === lis.code || l.to === lis.code)
    .map((l) => (l.from === lis.code ? l.to : l.from))
  let dearerSomewhere = false
  for (const code of neighbours) {
    const other = snap.ports.find((p) => p.code === code)!
    const there = expectOk(await worldMarket(other.id)).goods.find((g) => g.code === cheapest.code)!
    if (there.available && there.mid > cheapest.mid) { dearerSomewhere = true; break }
  }
  expect(dearerSomewhere).toBe(true)
})

test('world.fleets() reports the fleet, its ships, its stores and its empty queue', async () => {
  const fleets = expectOk(await worldFleets())
  expect(fleets).toHaveLength(1)
  const f = fleets[0]
  expect(isStr(f.id)).toBe(true)
  expect(f.name).toBe('Gaivota')
  expect(f.status).toBe('DOCKED')
  expect(f.port).toBe('LIS')
  expect(f.version).toBeGreaterThanOrEqual(1)
  expect(f.busy_until).toBeNull()
  expect(f.voyage).toBeNull()
  expect(f.speed_kn).toBeGreaterThan(0)
  expect(f.endurance_days).toBeGreaterThan(0)
  expect(Array.isArray(f.queue)).toBe(true)
  expect(f.queue).toHaveLength(0)

  expect(f.ships).toHaveLength(1)
  const s = f.ships[0]
  expect(isStr(s.id)).toBe(true)
  expect(s.name).toBe('Gaivota')
  expect(s.class).toBe('Barca')
  expect(s.is_flagship).toBe(true)
  expect(s.hold).toBe(60)
  expect(s.durability).toBe(s.max_durability)
  expect(s.crew).toBe(s.crew_required)
  expect(s.crew_max).toBeGreaterThanOrEqual(s.crew_required)
  expect(s.cargo).toEqual({}) // goods code -> tuns; empty on a new hull
  expect(s.cargo_tuns).toBe(0)
  expect(s.water_t).toBeGreaterThan(0)
  expect(s.food_t).toBeGreaterThan(0)

  // ── THE THREE KEYS 0017 ADDED, pinned so a rename turns THIS red instead of a screen blank ────
  // The client deleted its own "how much fits in this hull" arithmetic in favour of these (three
  // copies, one of which had silently forgotten the stores). That trade is only safe while the
  // server keeps serving them under these names, which is what this asserts.
  expect(s.hold_rated).toBe(60) // the shipwright's figure — never changes with an officer
  expect(typeof f.free_hold).toBe('number')
  expect(f.free_hold).toBeGreaterThan(0)

  // AND THE RELATIONSHIP, not merely the presence. Free hold is the stowed capacity minus what is
  // already aboard — cargo AND stores — so on a provisioned hull with an empty cargo bay it must be
  // strictly LESS than the hold. A free_hold that equalled `hold` would be the exact defect the
  // client copy had: stores forgotten.
  expect(f.free_hold).toBeLessThan(s.hold)
  expect(f.free_hold).toBeCloseTo(s.hold - s.cargo_tuns - s.water_t - s.food_t, 5)

  // No officer is posted on a new house, so the quartermaster's share is zero and the stowed hold
  // is the rated hold. This is the no-op 0017 promises, checked from the client's side of the wire.
  expect(f.officer_pct?.QUARTERMASTER ?? 0).toBe(0)
  expect(s.hold).toBe(s.hold_rated)
})

test('world.ledger() pages, reconciles, and carries the purse', async () => {
  const page = expectOk(await worldLedger())
  expect(page.ducats).toBe(8000)
  expect(page.ledger_sum).toBe(page.ducats)
  expect(page.events.length).toBeGreaterThanOrEqual(1)
  const founding = page.events.find((e) => e.kind === 'FOUNDED')!
  expect(founding).toBeDefined()
  expect(isStr(founding.id) && isStr(founding.at)).toBe(true)
  expect(founding.ducats_delta).toBe(8000)
  expect(founding.balance_after).toBe(8000)
  expect(founding.payload).toMatchObject({ port: 'LIS', company: 'Casa de Aveiro' })
  expect(isStr(page.next_cursor)).toBe(true)

  // The cursor is exclusive: paging past the oldest event returns nothing, and does not loop.
  const older = expectOk(await worldLedger(page.next_cursor, 10))
  expect(older.events).toHaveLength(0)

  const capped = expectOk(await worldLedger(null, 1))
  expect(capped.events).toHaveLength(1)
})

// ── the commands ───────────────────────────────────────────────────────────────────────────────

test('cmd.verb_schema() serves the eight V0 verbs, argument by argument', async () => {
  const verbs = expectOk(await cmdVerbSchema())
  expect(verbs.map((v) => v.verb)).toEqual([
    'SAIL',
    'BUY',
    'SELL',
    'PROVISION',
    'HIRE',
    'REPAIR',
    'CANCEL',
    'CLEAR',
  ])
  const sail = verbs[0]
  expect(sail.help.length).toBeGreaterThan(10)
  const dest = sail.args.find((a) => a.name === 'dest')!
  expect(dest.type).toBe('port')
  expect(dest.required).toBe(true)
  expect(dest.keyword).toBe('TO')
  expect(sail.args.find((a) => a.name === 'via')!.repeat).toBe(true)
  // The snapshot ships the same grammar, so a tap-builder and the keyboard cannot drift apart.
  const snap = expectOk(await worldSnapshot())
  expect(snap.verbs).toEqual(verbs)
})

test('cmd.preview() estimates without moving a ducat, and refuses in the same words a commit would', async () => {
  const fleet = expectOk(await worldFleets())[0]
  const before = expectOk(await worldLedger()).ducats

  const ok = expectOk(await cmdPreview(fleet.id, 'BUY salt 40'))
  expect(ok.ok).toBe(true)
  expect(ok.parsed.verb).toBe('BUY')
  expect(ok.parsed.fleet_id).toBe(fleet.id)
  expect(ok.estimate).toBeDefined()
  expect(ok.estimate!.qty).toBe(40)
  expect(ok.estimate!.good).toBe('salt')
  expect(Number(ok.estimate!.total)).toBeGreaterThan(0)
  expect(expectOk(await worldLedger()).ducats).toBe(before) // the dry run really was dry

  const refused = await cmdPreview(fleet.id, 'BUY salt 60')
  expect(refused.ok).toBe(false)
  if (refused.ok) throw new Error('unreachable')
  expect(refused.refusal.code).toBe('E_HOLD_FULL')
  expect(refused.refusal.source).toBe('server')
})

test('a refusal arrives as typed data: code, sentence, and DESIGN F.5 fixes', async () => {
  const fleet = expectOk(await worldFleets())[0]
  const result = await cmdIssue(fleet.id, 'BUY salt 60', fleet.version)

  // NOT a thrown string, NOT a null, NOT a silent no-op. The game refusing is the game working.
  expect(result.ok).toBe(false)
  if (result.ok) throw new Error('unreachable')
  const r = result.refusal
  expect(r.code).toBe('E_HOLD_FULL')
  expect(r.sentence).toContain('room for')
  expect(r.sentence.length).toBeGreaterThan(10)
  expect(r.fixes.length).toBeGreaterThanOrEqual(1)
  expect(r.fixes).toContain('SELL <good> ALL')
  expect(r.source).toBe('server')
  // The queue comes back with the refusal, so a screen can redraw without a second round trip.
  expect(r.queue?.some((o) => o.error_code === 'E_HOLD_FULL')).toBe(true)

  // …and the refused order is still in the queue as `failed`, exactly as the chain leaves it.
  const after = expectOk(await worldFleets())[0]
  expect(after.queue.some((o) => o.status === 'failed' && o.text === 'BUY salt 60')).toBe(true)

  expectOk(await cmdClear(fleet.id))
  await db.pg.query("delete from public.orders where status = 'failed'")
})

test('the other refusal shapes are the same shape', async () => {
  const fleet = expectOk(await worldFleets())[0]

  // A stale version — the F.3 rule that stops two devices double-issuing.
  const stale = await cmdIssue(fleet.id, 'BUY salt 10', fleet.version + 99)
  expect(stale.ok).toBe(false)
  if (stale.ok) throw new Error('unreachable')
  expect(stale.refusal.code).toBe('E_STALE')
  expect(stale.refusal.fixes.length).toBeGreaterThanOrEqual(1)

  // An unknown port, refused by the resolver rather than by a screen's own validation.
  const nowhere = await cmdIssue(fleet.id, 'SAIL TO zzz')
  expect(nowhere.ok).toBe(false)
  if (nowhere.ok) throw new Error('unreachable')
  expect(nowhere.refusal.code).toBe('E_NO_SUCH_PORT')

  // An ambiguous prefix, which must NAME the candidates rather than just say "ambiguous".
  const ambiguous = await cmdIssue(fleet.id, 'SAIL TO s')
  expect(ambiguous.ok).toBe(false)
  if (ambiguous.ok) throw new Error('unreachable')
  expect(ambiguous.refusal.code).toBe('E_AMBIGUOUS')
  // It must NAME what it could have meant. With 214 ports "s" matches dozens, so what is asserted
  // is the rule — several candidates, listed — rather than the two a twelve-port world had.
  expect(ambiguous.refusal.sentence).toContain('Safi')
  expect(ambiguous.refusal.sentence.split(',').length).toBeGreaterThan(1)

  // A fleet that is not the player's: the ownership check, phrased as a refusal like any other.
  const notMine = await cmdIssue('00000000-0000-4000-8000-0000000000ff', 'BUY salt 10')
  expect(notMine.ok).toBe(false)
  if (notMine.ok) throw new Error('unreachable')
  expect(notMine.refusal.code).toBe('E_NO_SUCH_FLEET')
})

// ── the bargain (migration 0022) ───────────────────────────────────────────────────────────────
//
// THESE TWO RUN BEFORE THE FLEET GOES TO SEA, and they say so rather than relying on it: a bargain
// is struck on the quay, so DOCKED is a precondition, and a precondition a proof does not own is
// the class of bug docs/NO_SPAGHETTI.md §4 exists to stop.
//
// THE OUTCOME IS FORCED, NOT WISHED FOR. `cmd.haggle` rolls `voyage.rng` against odds seeded from
// the world secret, so a proof that simply haggled and hoped would pass ~73% of the time and would
// be exactly the "probe picked its subject by lottery" defect 0010 and 0014 both shipped once. So
// the knobs are set to 0 for a certain refusal and to 1 for a certain win, inside the test, and put
// back afterwards. What is proven is then the RULE, at both ends, every run.

test('world.haggle_state() answers "how much negotiation can be done", in the server\'s own numbers', async () => {
  const fleet = expectOk(await worldFleets())[0]
  expect(fleet.status).toBe('DOCKED') // the precondition this test owns, stated
  const port = expectOk(await worldSnapshot()).ports.find((p) => p.code === fleet.port)!
  const market = expectOk(await worldMarket(port.id))
  // A DETERMINISTIC SUBJECT: the first tradeable good with stock, by code. Never `limit 1` on
  // whatever the heap hands back.
  const good = market.goods
    .filter((g) => g.available && g.stock > 0)
    .sort((a, b) => a.code.localeCompare(b.code))[0]
  expect(good).toBeDefined()

  const state = expectOk(await worldHaggleState(fleet.id, good.good_id))
  expect(state.docked).toBe(true)
  if (!state.docked) throw new Error('unreachable')

  // Every field src/lib/rpc/types.ts declares, read back out of a payload a real PostgreSQL made.
  expect(state.port).toBe(port.code)
  expect(state.good).toBe(good.code)
  expect(isNum(state.game_day)).toBe(true)
  expect(state.attempts_used).toBe(0)
  expect(state.attempts_left).toBe(state.attempts_max)
  expect(state.attempts_max).toBeGreaterThan(0)
  expect(state.wins).toBe(0)
  expect(state.concession).toBe(0)
  expect(state.concession_pct).toBe(0)
  expect(state.concession_max).toBeGreaterThan(0)
  expect(state.concession_max_pct).toBeCloseTo(state.concession_max * 100, 6)
  expect(state.step_pct).toBeGreaterThan(0)
  // THE ODDS SHOWN ARE THE ODDS ROLLED. `haggle_odds` is read by BOTH this and cmd.haggle, so a
  // panel drawn from this read cannot promise what the verb will not do — assert the range and
  // the pct/fraction agreement rather than a seeded value.
  expect(state.next_odds).toBeGreaterThan(0)
  expect(state.next_odds).toBeLessThanOrEqual(1)
  expect(state.next_odds_pct).toBeCloseTo(state.next_odds * 100, 1)
  // With no bargain struck and no purser posted, the executed spread IS the published one.
  expect(state.spread_published).toBeGreaterThan(0)
  expect(state.spread_effective).toBeCloseTo(state.spread_published, 6)
  expect(state.spread_floor).toBeLessThan(state.spread_published)
  expect(state.at_floor).toBe(false)
  expect(isStr(state.spent_on)).toBe(true)

  // A FLEET THAT IS NOT YOURS IS A REFUSAL, not a disclosure.
  const notMine = await worldHaggleState('00000000-0000-4000-8000-0000000000ff', good.good_id)
  expect(notMine.ok).toBe(false)
  if (notMine.ok) throw new Error('unreachable')
  expect(notMine.refusal.code).toBe('E_NOT_YOURS')
})

test('cmd.haggle() spends an attempt whether it wins or loses, and a win really moves the price', async () => {
  const fleet = expectOk(await worldFleets())[0]
  expect(fleet.status).toBe('DOCKED')
  const port = expectOk(await worldSnapshot()).ports.find((p) => p.code === fleet.port)!
  const market = expectOk(await worldMarket(port.id))
  const good = market.goods
    .filter((g) => g.available && g.stock > 0)
    .sort((a, b) => a.code.localeCompare(b.code))[0]

  // THE KNOBS THIS TEST OWNS WHILE IT RUNS. `haggle_odds` is
  // `(base + skill) × (1 − hardening × fails)`, clamped by `success_max` — so forcing an outcome
  // means setting THREE knobs, not one, and the hardening term is exactly the thing that made the
  // first draft of this test pass a forced win at 0.75 odds and fail on the roll.
  const knob = async (key: string, v: number) =>
    db.pg.query('update public.world_config set value = $1::jsonb where key = $2', [String(v), key])
  const before = expectOk(await worldHaggleState(fleet.id, good.good_id))
  if (!before.docked) throw new Error('unreachable')

  // WHAT TEN TUNS COST BEFORE ANY BARGAIN — the real quote, through the verb itself, rolled back.
  const quoted = (r: Awaited<ReturnType<typeof cmdPreview>>) => Number(expectOk(r).estimate!.total)
  const totalPlain = quoted(await cmdPreview(fleet.id, `BUY ${good.code} 10`))
  expect(totalPlain).toBeGreaterThan(0)

  try {
    // ── A CERTAIN REFUSAL. It still costs an attempt: 0022 writes the attempt and increments the
    //    count BEFORE it rolls, which is what makes save-scumming structurally impossible.
    await knob('haggle_base_success', 0)
    await knob('haggle_success_max', 0)
    const lost = expectOk(await cmdHaggle(fleet.id, good.good_id, 'buy'))
    expect(lost.ok).toBe(true)
    expect(lost.won).toBe(false)
    expect(lost.attempt).toBe(1)
    expect(lost.attempts_left).toBe(lost.attempts_max - 1)
    expect(lost.concession).toBe(0)
    expect(lost.good).toBe(good.code)
    expect(lost.side).toBe('buy')
    expect(isStr(lost.message)).toBe(true)
    expect(lost.spread_effective).toBeCloseTo(lost.spread_published, 6)
    // The count the panel prints is the server's, and it moved.
    const afterLoss = expectOk(await worldHaggleState(fleet.id, good.good_id))
    if (!afterLoss.docked) throw new Error('unreachable')
    expect(afterLoss.attempts_used).toBe(1)
    expect(afterLoss.wins).toBe(0)
    // …and it moved no money.
    expect(quoted(await cmdPreview(fleet.id, `BUY ${good.code} 10`))).toBe(totalPlain)

    // ── A REFUSAL HARDENS THE NEXT ATTEMPT, and that is asserted AT THE SHIPPED KNOBS.
    // The first draft compared the odds while `haggle_base_success` was still forced to 0, which
    // proved only that this test had turned a knob down. Put the base back and the hardening term
    // is the only thing left that can have moved the number: one refusal multiplies the odds by
    // (1 - haggle_hardening_per_fail), and the read must show it BEFORE a try is spent on it.
    await knob('haggle_base_success', 0.45)
    await knob('haggle_success_max', 0.85)
    const hardened = expectOk(await worldHaggleState(fleet.id, good.good_id))
    if (!hardened.docked) throw new Error('unreachable')
    expect(hardened.next_odds).toBeLessThan(before.next_odds)
    const perFail = await db.pg.query<{ v: number }>(
      "select public.wc_num('haggle_hardening_per_fail')::float8 as v",
    )
    expect(hardened.next_odds).toBeCloseTo(before.next_odds * (1 - perFail.rows[0].v), 4)

    // ── A CERTAIN WIN, and the price has to actually move. The hardening goes to 0 as well: with
    //    one refusal already taken, odds of 1 would still only be 0.75 and the roll could beat it.
    await knob('haggle_base_success', 1)
    await knob('haggle_success_max', 1)
    await knob('haggle_hardening_per_fail', 0)
    const won = expectOk(await cmdHaggle(fleet.id, good.good_id, 'buy'))
    expect(won.won).toBe(true)
    expect(won.attempt).toBe(2)
    expect(won.attempts_left).toBe(won.attempts_max - 2)
    expect(won.concession).toBeGreaterThan(0)
    expect(won.concession_pct).toBeCloseTo(won.concession * 100, 1)
    // THE COMPOSITION RULE, checked rather than trusted: with no purser posted the executed spread
    // is the published one less the concession, MULTIPLICATIVELY (0022 decision 5).
    expect(won.spread_effective).toBeCloseTo(won.spread_published * (1 - won.concession), 5)
    expect(won.spread_effective).toBeLessThan(won.spread_published)

    // AND THE MONEY. The same ten tuns, through the same verb, cost less than they did.
    const totalHaggled = quoted(await cmdPreview(fleet.id, `BUY ${good.code} 10`))
    expect(totalHaggled).toBeLessThan(totalPlain)

    // ── FINITE. The third attempt is allowed; the fourth is refused, in the server's words.
    expectOk(await cmdHaggle(fleet.id, good.good_id, 'buy'))
    const spent = await cmdHaggle(fleet.id, good.good_id, 'buy')
    expect(spent.ok).toBe(false)
    if (spent.ok) throw new Error('unreachable')
    expect(spent.refusal.code).toBe('E_HAGGLE_SPENT')
    expect(spent.refusal.source).toBe('server')
    expect(spent.refusal.fixes.length).toBeGreaterThanOrEqual(1)
  } finally {
    // The knobs go back whatever happened, so a failure here cannot poison the tests after it.
    // The values are 0022's own seeds; the day they are retuned this restore is what goes stale,
    // which is why it sits beside the migration's name rather than in a helper somewhere else.
    await knob('haggle_base_success', 0.45)
    await knob('haggle_success_max', 0.85)
    await knob('haggle_hardening_per_fail', 0.25)
    await db.pg.query('delete from public.haggle_daily')
  }
})

test('cmd.issue() / cmd.cancel_at() / cmd.clear() return the queue and the new version', async () => {
  const fleet = expectOk(await worldFleets())[0]

  const bought = expectOk(await cmdIssue(fleet.id, 'BUY salt 10', fleet.version))
  expect(bought.order.status).toBe('done')
  expect(bought.order.seq).toBeGreaterThanOrEqual(1)
  expect(bought.order.result).toMatchObject({ qty: 10, good: 'salt' })
  // The issue payload carries the order WITHOUT its text or verb; the queue beside it carries both.
  expect('verb' in bought.order).toBe(false)
  expect(bought.version).toBeGreaterThan(fleet.version)
  expect(bought.error_code).toBeNull()
  expect(Array.isArray(bought.queue)).toBe(true)

  // Queue two orders behind a SAILING fleet, then take them back apart.
  // Addressed by CODE: "Porto" is ambiguous with Portobelo in the real world, and a three-letter
  // code is exact by construction, so this tests the queue rather than the parser.
  const sailed = expectOk(await cmdIssue(fleet.id, 'SAIL Gaivota TO CAD'))
  expect(sailed.order.status).toBe('done')
  const queued = expectOk(await cmdIssue(fleet.id, 'SELL salt ALL'))
  expect(queued.order.status).toBe('pending')
  expectOk(await cmdIssue(fleet.id, 'BUY hides 10'))

  const cancelled = expectOk(await cmdCancel(fleet.id))
  expect(cancelled.cancelled).toBeGreaterThanOrEqual(1)
  expect(cancelled.queue.every((o) => o.status !== 'cancelled')).toBe(true)

  const cleared = expectOk(await cmdClear(fleet.id))
  expect(cleared.cancelled).toBeGreaterThanOrEqual(1)
  expect(cleared.queue).toHaveLength(0)
  // §F.3: CLEAR drops the pending orders and LEAVES THE ACTIVE VOYAGE RUNNING.
  expect(expectOk(await worldFleets())[0].status).toBe('SAILING')

  const clearedAll = expectOk(await cmdClear(fleet.id, true))
  expect(clearedAll.active_left_running).toBe(true)
  expect(clearedAll.note).toContain('RECALL')
})

test('a fleet at sea reports its voyage and its closed-form position', async () => {
  const snap = expectOk(await worldSnapshot())
  const fleet = expectOk(await worldFleets())[0]
  expect(fleet.status).toBe('SAILING')
  expect(fleet.port).toBeNull()
  const v = fleet.voyage!
  expect(v).not.toBeNull()
  expect(isStr(v.id) && isStr(v.eta)).toBe(true)
  expect(v.to).toBe('CAD')
  // The SAILED distance of the leg, not the straight line: 188 nm is the great circle and Cape
  // St Vincent is in the way. The number the voyage carries must be the number the leg holds.
  const legLisCad = snap.legs.find(
    (l) => (l.from === 'LIS' && l.to === 'CAD') || (l.from === 'CAD' && l.to === 'LIS'),
  )!
  expect(v.total_nm).toBe(legLisCad.nm)
  expect(v.total_nm).toBeGreaterThan(188)
  expect(v.nm_done).toBeGreaterThanOrEqual(0)
  expect(v.nm_done).toBeLessThanOrEqual(v.total_nm)
  const p = v.position!
  expect(p).not.toBeNull()
  expect(p.from_code).toBe('LIS')
  expect(p.to_code).toBe('CAD')
  expect(isNum(p.lat) && isNum(p.lon)).toBe(true)
  expect(p.leg_frac).toBeGreaterThanOrEqual(0)
  expect(p.leg_frac).toBeLessThanOrEqual(1)
  expect(p.leg_index).toBe(0)
})

// ── the dispatcher ─────────────────────────────────────────────────────────────────────────────

test('one catalogue builds both backends, and only one backend is ever in use', async () => {
  expect(backendKind()).toBe('local')

  // The SQL and the PostgREST call are derived from the same row — they cannot drift.
  expect(localSql('worldMarket')).toBe('select world.market($1::uuid) as result')
  expect(localSql('worldSnapshot')).toBe('select world.snapshot() as result')
  expect(localSql('cmdIssue')).toBe('select cmd.issue($1::uuid, $2::text, $3::int) as result')
  expect(namedArgs('cmdIssue', ['f', 'BUY salt 10'])).toEqual({
    p_fleet: 'f',
    p_text: 'BUY salt 10',
    p_expected_version: null,
  })
  expect(rpcLabel('worldLedger')).toBe('world.ledger(p_cursor, p_limit)')

  // The catalogue is the whole vocabulary. Server-only functions are deliberately not in it.
  // The COUNT is not the point — what a client may call is. The list is asserted by name so that
  // adding one is a deliberate edit here, and the server-only entry points below stay out.
  //
  // FOUNDING A HOUSE IS THE LINE WORTH BEING PRECISE ABOUT (0011). `public.new_house(uid, …)` takes
  // an arbitrary uid, so a client holding it could found a house on somebody else's account — it is
  // revoked from every client role, permanently, and stays out of this list. `cmd.found_house(name)`
  // takes NO uid and reads auth.uid() server-side, so the only house a caller can found is their
  // own. One of those belongs to a browser and the other never can; the difference is the argument.
  const names = Object.keys(RPCS)
  expect(names.sort()).toEqual(
    [
      'cmdCancel', 'cmdClear', 'cmdFoundHouse', 'cmdIssue', 'cmdPreview', 'cmdVerbSchema',
      'worldBuyCapacity', 'worldFleets', 'worldLedger', 'worldMarket', 'worldSnapshot',
      // Added deliberately 2026-08-22 with migration 0019: `world.trade_routes`, the read that
      // answers "where is this good worth more than it is here". It takes a port and OPTIONALLY a
      // fleet id — the fleet is checked against auth.uid() server-side (0019), so naming somebody
      // else's is E_NOT_YOURS rather than a disclosure.
      'worldTradeRoutes',
      // 0013-0016. Each of the three cmd.* entries takes NO player id — identity is the JWT's,
      // the same property that makes cmd.found_house safe for a browser to hold.
      'worldPriceHistory', 'worldPlayer', 'worldOfficers', 'worldSkills',
      'cmdHireOfficer', 'cmdPostOfficer', 'cmdStudySkill',
      // Pin moved deliberately 2026-08-23 with migration 0022, `a_bargain_is_struck_on_the_quay`:
      // `world.haggle_state` (the read) and `cmd.haggle` (the verb). They land together because
      // they are ONE feature, and because 0022 GRANTS EXECUTE to `authenticated` on exactly the
      // entry points this catalogue names — 0018's sweep reads it BY NAME, so a grant with no row
      // here is a door nobody opens. That is precisely what 0022 shipped as until this pin moved:
      // a complete server mechanic with no client at all.
      // Neither takes a player id; both read `current_player_id()` and refuse a fleet that is not
      // yours, which is the same property that makes `cmd.found_house` safe for a browser to hold.
      'worldHaggleState', 'cmdHaggle',
      // Pin moved deliberately 2026-08-23 with 0025 (the table of captains) and 0026 (the fair at
      // the quay). Both are READS and neither takes a player id.
      //
      // `world.standings(p_limit)` bounds how many LINES come back and cannot widen one: what a
      // board row may carry is settled on the server, and `public.standings` carries RLS with no
      // policy and no grant to any client role — a house's purse and the harbour her fleet lies in
      // are physically unreachable through it, which is 0025's own break-test.
      //
      // `world.buffs(p_port)` is the one on this list with a SIDE EFFECT, and it is deliberate:
      // reading it winds the fair calendar where pg_cron is absent (0009's catch-up idiom). It is
      // not the only winder any more — 0028 put the same call in `world.fleets()` so a fair happens
      // because the game is played rather than because one tab was opened — but it is still a
      // writer reached through a read, and that is worth knowing before anyone "optimises" it.
      'worldStandings', 'worldBuffs',
      // Pin moved deliberately 2026-08-23 with migration 0034 (a standing order keeps her
      // provisioned): the book of standing orders — one read and three verbs, landed WITH the
      // migration's grant rows because a grant with no catalogue row is a door nobody opens
      // (0022 shipped that way once, and its header says so). None takes a player id; apply with
      // a null preset CLEARS a fleet's order, so clearing is not a fifth entry point.
      'worldProvisionPresets', 'cmdProvisionPresetSave', 'cmdProvisionPresetDelete',
      'cmdProvisionPresetApply',
      // Pin moved deliberately 2026-08-23 with migration 0037 (she answers her helm at sea):
      // `cmd.divert` — change a SAILING fleet's destination NOW. Not a verb: it acts on the
      // queue and the voyage like cancel_at and clear, which is why it is an entry point and not
      // a row in the grammar. It takes no player id; the server reads current_player_id() and
      // refuses a fleet that is not yours. The onward passage it queues goes through cmd.issue
      // (the one parser) and is gated at the turn node by voyage.sail_refusal (the one refusal
      // authority), so this entry point carries no second grammar and no second legality path.
      'cmdDivert',
    ].sort(),
  )
  expect(JSON.stringify(RPCS)).not.toContain('new_house')
  expect(JSON.stringify(RPCS)).not.toContain('assume_identity')
  expect(JSON.stringify(RPCS)).not.toContain('settle')
  expect(JSON.stringify(RPCS)).not.toContain('tick_')
})

test('a fault crosses the boundary as a refusal, not as a stack trace', async () => {
  // Nothing installed: the surface answers, it does not explode.
  clearBackend()
  const nobody = await worldSnapshot()
  expect(nobody.ok).toBe(false)
  if (nobody.ok) throw new Error('unreachable')
  expect(nobody.refusal.code).toBe('E_NO_BACKEND')
  setBackend(createLocalBackend(db))

  // A raised E_CODE (the parser's shape) keeps its code and its sentence.
  const raised = fromError(new Error('E_AMBIGUOUS: "s" could be Safi, Sevilla'))
  expect(raised.code).toBe('E_AMBIGUOUS')
  expect(raised.sentence).toBe('"s" could be Safi, Sevilla')
  expect(raised.source).toBe('raised')

  // A permission failure is named as one — this is the SQLSTATE the lockdown produces.
  const denied = fromError(Object.assign(new Error('permission denied for table ports'), { code: '42501' }))
  expect(denied.code).toBe('E_FORBIDDEN')
  expect(denied.detail).toContain('42501')

  // A missing RPC upstream is what an unexposed schema looks like from PostgREST.
  expect(fromError(Object.assign(new Error('not found'), { code: 'PGRST202' })).code).toBe('E_NO_SUCH_RPC')

  // Anything else is a fault, and says so rather than pretending to be a game rule.
  const broken = await worldMarket('not-a-uuid')
  expect(broken.ok).toBe(false)
  if (broken.ok) throw new Error('unreachable')
  expect(broken.refusal.source).toBe('fault')
  expect(broken.refusal.detail).toContain('local · world.market(p_port)')
})

// ── signing the book (0011) ────────────────────────────────────────────────────────────────────
//
// This is the ONE path by which a signed-in player on a real project gets a house at all, and
// until 0011 it did not exist: `public.new_house()` takes a uid and is revoked from every client
// role, so cloud mode would have dropped a captain into an empty world with nothing to press.
//
// LOCAL MODE ALREADY FOUNDED ITS ONE CAPTAIN AT BOOT, which makes this fixture the exact case the
// client must survive on every sign-in: call it, and read the refusal rather than asking first.

test('cmd.found_house() refuses a second house on an account that already keeps one', async () => {
  const r = await cmdFoundHouse('Casa Duplicada')
  expect(r.ok, 'the local captain already has a house, so this must be a refusal').toBe(false)
  if (r.ok) return
  expect(r.refusal.code).toBe('E_ALREADY_FOUNDED')
  // DESIGN F.5: a refusal is a code, a SENTENCE and a fix — not a code the screen has to translate.
  expect(r.refusal.sentence.length).toBeGreaterThan(10)
  expect(r.refusal.source).toBe('server')
})

test('cmd.found_house() refuses an unknown nation, and names the ones that exist', async () => {
  const r = await cmdFoundHouse('Casa Sem Bandeira', 'ZZZ')
  expect(r.ok).toBe(false)
  if (r.ok) return
  // The already-founded check runs FIRST for the local captain, so this asserts the refusal
  // contract rather than the ordering: whichever bites, it arrives typed, with a sentence.
  expect(['E_NO_SUCH_NATION', 'E_ALREADY_FOUNDED']).toContain(r.refusal.code)
  expect(r.refusal.sentence.length).toBeGreaterThan(10)
})

test('the catalogue spells found_house the way the migration does', () => {
  expect(RPCS.cmdFoundHouse.schema).toBe('cmd')
  expect(RPCS.cmdFoundHouse.fn).toBe('found_house')
  // PostgREST calls by NAME: these two strings are the wire contract with 0011's signature.
  expect(RPCS.cmdFoundHouse.args.map((a) => a.name)).toEqual(['p_company_name', 'p_nation_code'])
  // And no uid crosses the wire — that is the whole security property of 0011.
  expect(rpcLabel('cmdFoundHouse')).not.toContain('uid')
})

// ── the book of standing orders (0034) ─────────────────────────────────────────────────────────
//
// The MECHANIC — the top-up on arrival, crew-at-fire-time, the trade-off, the cap, the written
// refusal — is proven on the server side twice over (0034's self-assert and proof 07). What this
// spec owes is the WIRE: every field the types declare read back off a real payload, and the
// refusal contract on the verbs the browser actually holds. The test writes one order and strikes
// it before it ends, so the local captain's book leaves as it arrived.

test('the book of standing orders round-trips: write, adjust, apply, clear, strike', async () => {
  const fleet = expectOk(await worldFleets())[0]

  const empty = expectOk(await worldProvisionPresets())
  expect(empty.max).toBeGreaterThan(0)
  expect(Array.isArray(empty.presets)).toBe(true)
  const before = empty.presets.length

  // WRITE. Every field PresetSaved declares, off a real answer.
  const saved = expectOk(await cmdProvisionPresetSave(null, 'Spec Order', 21))
  expect(isStr(saved.id)).toBe(true)
  expect(saved.name).toBe('Spec Order')
  expect(saved.days).toBe(21)

  // ADJUST — days only, then name only. A null argument means "keep", not "blank".
  expect(expectOk(await cmdProvisionPresetSave(saved.id, null, 30)).days).toBe(30)
  expect(expectOk(await cmdProvisionPresetSave(saved.id, 'Spec Order II', null)).name).toBe(
    'Spec Order II',
  )

  // APPLY, and the BOOK is where the edge is served — FleetsScreen joins on exactly this.
  const applied = expectOk(await cmdProvisionPresetApply(fleet.id, saved.id))
  expect(applied.fleet).toBe(fleet.name)
  expect(applied.preset).toBe('Spec Order II')
  expect(applied.days).toBe(30)
  const book = expectOk(await worldProvisionPresets())
  const row = book.presets.find((preset) => preset.id === saved.id)
  expect(row).toBeDefined()
  expect(row!.days).toBe(30)
  expect(row!.fleets.map((f) => f.id)).toContain(fleet.id)
  expect(isStr(row!.fleets[0].name)).toBe(true)

  // CLEAR is apply-with-null, one verb, and the edge disappears from the served book.
  expectOk(await cmdProvisionPresetApply(fleet.id, null))
  const cleared = expectOk(await worldProvisionPresets())
  expect(cleared.presets.find((preset) => preset.id === saved.id)!.fleets).toHaveLength(0)

  // REFUSALS ARE TYPED, with a sentence — the F.5 contract on the new verbs.
  const zero = await cmdProvisionPresetSave(saved.id, null, 0)
  expect(zero.ok).toBe(false)
  if (zero.ok) throw new Error('unreachable')
  expect(zero.refusal.code).toBe('E_PARSE')
  expect(zero.refusal.sentence.length).toBeGreaterThan(10)
  const ghost = await cmdProvisionPresetApply(fleet.id, '00000000-0000-4000-8000-0000000000aa')
  expect(ghost.ok).toBe(false)
  if (ghost.ok) throw new Error('unreachable')
  expect(ghost.refusal.code).toBe('E_NO_SUCH_PRESET')

  // STRIKE, and leave the book as it was found.
  const struck = expectOk(await cmdProvisionPresetDelete(saved.id))
  expect(struck.deleted).toBe('Spec Order II')
  expect(struck.detached_fleets).toBe(0)
  expect(expectOk(await worldProvisionPresets()).presets.length).toBe(before)
})
