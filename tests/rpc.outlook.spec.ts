// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ESTIMATE — world.price_outlook (0170, docs/COMMAND_DESK.md §4, slice D1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-17: "i will be able to see the estimated price movement so that i can plan buying
// and selling for max profit". The estimate is ONE server read built from the terms the price is made
// of; the client draws it and computes nothing. This spec reads it back off a real PostgreSQL (the
// build's own world, tests/builtWorld.fixture.ts) and holds it to four promises:
//   * its "now" IS world.price — mid, ask and bid, to the cent;
//   * its band widens ahead (the drift's spread grows with the steps) and is honest about a flat row;
//   * the best time is served only when it beats the band (a low drift reverts upward; a flat row has none);
//   * it refuses what it cannot answer, and its window is the knobs'.
// It names the function its slice defines (world.price_outlook / price_outlook), so CI's rule S selects
// it whenever a migration re-defines it (docs/CI.md).
//
// The rows it bends (drift, stock) are bent with a direct UPDATE on this spec's own in-memory world —
// the market is random by design (0010), so a spec that needs a low drift or a flat row sets one.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'

interface OutlookPoint {
  at: string
  value: number
  lo: number
  hi: number
}
interface Outlook {
  port: string
  good: string
  side: 'mid' | 'ask' | 'bid'
  slot_seconds: number
  now: string
  horizon_slots: number
  band_z: number
  assumes: string
  held: string
  points: OutlookPoint[]
  best: { at: string; value: number; gain_pct: number } | null
  events: { code: string; name: string; from: string; to: string }[]
  clock: { now: string; next_change_at: string }
}

let db: LocalDb
let port: string
let good: string

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  // A row whose price sits well inside the world's band whatever the bends below do to it, so the
  // estimate can move: Lisbon, the first good (by code) whose terms keep it off both clamps (0173: the band
  // is the base's × the row's haul, the sea it crossed).
  const r = await db.pg.query<{ port_id: string; good_id: string }>(`
    select pg.port_id, pg.good_id
      from public.port_goods pg
      join public.ports p on p.id = pg.port_id
      join public.goods g on g.id = pg.good_id
     cross join lateral world.mid_terms(pg.port_id, pg.good_id) t
     where p.code = 'LIS'
       and world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, t.m_target / 2, 0.2, t.m_season, t.m_dev,
                                t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi) < t.m_band_hi * t.m_base * t.m_haul * 0.99
       and world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, t.m_target * 2, -0.2, t.m_season, t.m_dev,
                                t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi) > t.m_band_lo * t.m_base * t.m_haul * 1.01
     order by g.code limit 1`)
  expect(r.rows, 'no Lisbon row sits inside the band').toHaveLength(1)
  port = r.rows[0].port_id
  good = r.rows[0].good_id
})

test.afterAll(async () => {
  await db?.close()
})

async function outlook(side: string, slots: number | null = null, p = port, g = good): Promise<Outlook> {
  return db.callAs<Outlook>('select world.price_outlook($1::uuid, $2::uuid, $3::int, $4::text) as result', [p, g, slots, side])
}

async function bend(drift: number, stockOfTarget: number) {
  await db.pg.query(
    `update public.port_goods set drift = $3, stock = round(stock_target * $4, 2),
            drift_slot = public.drift_slot_of(now()), last_regen_day = world.game_day(now())
      where port_id = $1 and good_id = $2`,
    [port, good, drift, stockOfTarget],
  )
}

test('world.price_outlook: its now is world.price on every side, and the path is the window the knobs set', async () => {
  const price = await db.callAs<{ mid: number; ask: number; bid: number }>(
    'select to_jsonb(w) as result from world.price($1::uuid, $2::uuid) w',
    [port, good],
  )
  for (const side of ['mid', 'ask', 'bid'] as const) {
    const o = await outlook(side)
    expect(o.side).toBe(side)
    expect(o.horizon_slots).toBe(24)
    expect(o.points).toHaveLength(25)
    expect(o.slot_seconds).toBe(900)
    expect(o.band_z).toBeCloseTo(1.2816, 4)
    expect(o.assumes).toBe('If nobody else trades here')
    expect(o.held.length).toBeGreaterThan(10)
    expect(Array.isArray(o.events)).toBe(true)
    // now is the price the market serves, to the cent, and carries no band
    expect(o.points[0].value).toBe(Number(price[side]))
    expect(o.points[0].lo).toBe(o.points[0].value)
    expect(o.points[0].hi).toBe(o.points[0].value)
    expect(Date.parse(o.points[0].at)).toBe(Date.parse(o.now))
    // then one point a drift slot, on its boundaries, each later than the last
    expect(Date.parse(o.points[1].at)).toBe(Date.parse(o.clock.next_change_at))
    for (let i = 1; i < o.points.length; i++) {
      expect(Date.parse(o.points[i].at) - Date.parse(o.points[i - 1].at)).toBeGreaterThan(0)
      if (i > 1) expect(Date.parse(o.points[i].at) - Date.parse(o.points[i - 1].at)).toBe(900_000)
      expect(o.points[i].lo).toBeLessThanOrEqual(o.points[i].value)
      expect(o.points[i].hi).toBeGreaterThanOrEqual(o.points[i].value)
    }
  }
  // the window: capped at outlook_slots_max, at least one
  expect((await outlook('mid', 100_000)).horizon_slots).toBe(96)
  expect((await outlook('mid', 0)).points).toHaveLength(2)
})

test('the band widens ahead, and the best time is served only when it beats the band', async () => {
  // a low drift at the target stock: the walk reverts toward zero, so the price is expected to RISE
  await bend(-0.15, 1)
  const low = await outlook('bid')
  expect(low.best, 'a drift of −0.15 reverts upward well beyond the band').not.toBeNull()
  expect(low.best!.gain_pct).toBeGreaterThan(0)
  expect(low.best!.value).toBeGreaterThan(low.points[0].value)
  expect(Date.parse(low.best!.at)).toBeGreaterThan(Date.parse(low.now))
  // the stock stays at its target, so the band's width in coins grows with the drift's spread alone
  // (to the cent the sides are rounded to)
  const width = low.points.map((p) => p.hi - p.lo)
  for (let i = 1; i < width.length; i++) expect(width[i]).toBeGreaterThanOrEqual(width[i - 1] - 0.02)
  expect(width[24]).toBeGreaterThan(width[1])

  // a short stock with no drift: the stock refills, so the ask is expected to FALL — a later time to buy
  await bend(0, 0.5)
  const short = await outlook('ask')
  expect(short.best).not.toBeNull()
  expect(short.best!.value).toBeLessThan(short.points[0].value)

  // a flat row (no drift, full stock): nothing moves but the band, so there is no better time
  await bend(0, 1)
  const flat = await outlook('mid')
  expect(flat.best).toBeNull()
  expect(new Set(flat.points.map((p) => p.value)).size).toBe(1)
  expect(flat.points[24].hi).toBeGreaterThan(flat.points[24].value)
})

test('it refuses what it cannot answer', async () => {
  await expect(outlook('sell')).rejects.toThrow(/side must be mid, ask or bid/)
  await expect(outlook('mid', null, port, '00000000-0000-0000-0000-000000000000')).rejects.toThrow(/E_NO_SUCH_GOOD/)
  await expect(
    db.callAs('select world.price_outlook(null::uuid, $1::uuid) as result', [good]),
  ).rejects.toThrow(/E_NO_SUCH_PORT/)
})

test('a signed-in player may read it, anon may not, and the leaves are the server\'s own', async () => {
  const grants = await db.pg.query<{ fn: string; auth: boolean; anon: boolean }>(`
    select f.fn, has_function_privilege('authenticated', f.fn, 'execute') as auth, has_function_privilege('anon', f.fn, 'execute') as anon
      from unnest(array['world.price_outlook(uuid, uuid, integer, text)', 'public.price_path(uuid, uuid, integer)',
                        'public.drift_moments(numeric, integer)', 'world.price_terms(uuid)',
                        'world.price_sides(numeric, numeric, numeric, numeric)',
                        'public.stock_after(numeric, numeric, numeric, numeric, numeric)']) f(fn)`)
  expect(grants.rows).toEqual([
    { fn: 'world.price_outlook(uuid, uuid, integer, text)', auth: true, anon: false },
    { fn: 'public.price_path(uuid, uuid, integer)', auth: false, anon: false },
    { fn: 'public.drift_moments(numeric, integer)', auth: false, anon: false },
    { fn: 'world.price_terms(uuid)', auth: false, anon: false },
    { fn: 'world.price_sides(numeric, numeric, numeric, numeric)', auth: false, anon: false },
    { fn: 'public.stock_after(numeric, numeric, numeric, numeric, numeric)', auth: false, anon: false },
  ])
  const registered = await db.pg.query<{ n: number }>(
    `select count(*)::int as n from public.client_rpc_entry_points() where function_name = 'price_outlook' and arg_types = 'uuid, uuid, int, text'`,
  )
  expect(registered.rows[0].n).toBe(1)
})
