// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WORLD KEEPS ITS FIGURES — the Stats tab's six reads over public.tick_stats (0214)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Through the client wrappers, as a company founded at Lisbon: the job writes one rollup per slot and
// nothing on a second call in the same slot; the public reads serve what it wrote; and EVERY CITY IS OPEN
// (0223; the owner, 2026-10-25: "on cities, i want to see all the info without investment", reversing the
// 2026-10-20 gate 0214 built): with nothing invested anywhere a city's overview AND detail both arrive, the
// list row carries its figures, and no read carries a tier key. It names stats_city, stats_cities,
// stats_overview, stats_markets, stats_merchants, stats_me and tick_stats so CI's rule S selects it.
//
// AND THE LIVE READ (0224, owner row 200): world.stats_now serves the counters every writer keeps — base row plus
// the journal public.stats_live_deltas since the last count (public.stats_live_fold, inside tick_stats). Proven
// below: after the job it equals the rollup's holders with nothing since the count; a credit through public.credit
// moves the players' figure by its amount within the same second, with no job run; stats_live_add is the one helper.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import {
  clearBackend,
  createLocalBackend,
  setBackend,
  worldStatsCities,
  worldStatsCity,
  worldStatsMarkets,
  worldStatsMe,
  worldStatsMerchants,
  worldStatsNow,
  worldStatsOverview,
} from '../src/lib/rpc'

let db: LocalDb
let port: { id: string; code: string }

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Contas Spec', 'PRT') as result`)
  // a present price record, so the goods rows have a mid; then the job, once (the backend would run it
  // before the first stats read anyway — this makes the slot explicit)
  await db.callAs(`select public.tick_price_snapshot(now())::text as result`)
  await db.callAs(`select public.tick_stats(now())::text as result`)
  port = await db.callAs<{ id: string; code: string }>(
    `select jsonb_build_object('id', p.id, 'code', p.code) as result from public.ports p
      where p.kind = 'HARBOUR' and exists (select 1 from public.port_specialties s where s.port_id = p.id)
      order by p.code limit 1`,
  )
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('the job writes one rollup per slot and nothing on a second call in the same slot', async () => {
  const again = await db.callAs<{ wrote: number }>(`select public.tick_stats(now()) as result`)
  expect(again.wrote).toBe(0)
  const rows = await db.callAs<{ world: number; goods: number; cities: number; merchants: number }>(
    `select jsonb_build_object('world', (select count(*) from public.stats_world),
                               'goods', (select count(*) from public.stats_good),
                               'cities', (select count(*) from public.stats_city),
                               'merchants', (select count(*) from public.stats_merchants)) as result`,
  )
  const goods = Number(await db.callAs<number>(`select count(*)::int as result from public.goods`))
  const harbours = Number(await db.callAs<number>(`select count(*)::int as result from public.ports where kind = 'HARBOUR'`))
  expect(rows.world).toBe(1)
  expect(rows.merchants).toBe(1)
  expect(rows.goods).toBe(goods)
  expect(rows.cities).toBe(harbours)
})

test('the public reads serve what the job wrote: holders that add up, every good, the merchants, you', async () => {
  const o = await worldStatsOverview(24)
  expect(o.ok).toBe(true)
  if (!o.ok) return
  expect(o.value.at).not.toBeNull()
  expect(o.value.holders).not.toBeNull()
  const h = o.value.holders!
  expect(h.total).toBe(h.players + h.merchants + h.cities + h.set_aside)
  // your company's starting money is in the players' purses
  const purse = Number(await db.callAs<number>(`select ducats::bigint as result from public.players where id = public.current_player_id()`))
  expect(h.players).toBeGreaterThanOrEqual(purse)
  expect(o.value.series.length).toBeGreaterThanOrEqual(1)

  const m = await worldStatsMarkets()
  expect(m.ok).toBe(true)
  if (!m.ok) return
  const goods = Number(await db.callAs<number>(`select count(*)::int as result from public.goods`))
  expect(m.value.goods).toHaveLength(goods)
  const sold = m.value.goods.find((g) => g.markets > 0)
  expect(sold, 'no good is sold anywhere — the record is empty').toBeDefined()
  expect(sold!.mid).not.toBeNull()
  expect(Array.isArray(sold!.spark)).toBe(true)

  const mer = await worldStatsMerchants()
  expect(mer.ok).toBe(true)
  if (!mer.ok) return
  const houses = Number(await db.callAs<number>(`select count(*)::int as result from public.npc_houses`))
  expect(mer.value.houses).toBe(houses)

  const me = await worldStatsMe()
  expect(me.ok).toBe(true)
  if (!me.ok) return
  expect(me.value.leaderboard.you).not.toBeNull()
  expect(me.value.leaderboard.board.some((r) => r.is_you)).toBe(true)
  // rank and name only: no row carries a purse
  for (const r of me.value.leaderboard.board) expect(Object.keys(r).sort()).toEqual(['is_you', 'name', 'nation', 'rank'])
})

// ── THE LIVE READ (0224) ────────────────────────────────────────────────────────────────────────
test('stats_now equals the rollup after the count, and moves with a credit before the next one', async () => {
  const o = await worldStatsOverview(24)
  expect(o.ok).toBe(true)
  if (!o.ok) return
  const n0 = await worldStatsNow()
  expect(n0.ok).toBe(true)
  if (!n0.ok) return
  // the job folded the journal on its way out (tick_stats → stats_live_fold): nothing is pending, no drift
  expect(n0.value.since_count.trades).toBe(0)
  expect(n0.value.total).toBe(n0.value.players + n0.value.merchants + n0.value.cities + n0.value.set_aside)
  expect(n0.value.players).toBe(o.value.holders!.players)
  expect(n0.value.merchants).toBe(o.value.holders!.merchants)
  expect(n0.value.cities).toBe(o.value.holders!.cities)
  expect(n0.value.set_aside).toBe(o.value.holders!.set_aside)
  for (const v of Object.values(n0.value.drift)) expect(v).toBe(0)
  // THE POSITIVE CONTROL, BY AMOUNT: one credit of 1,234 to this company, through the one money mover
  await db.callAs(`select public.credit(public.current_player_id(), 'PROBE_0224', 1234)::text as result`)
  const n1 = await worldStatsNow()
  expect(n1.ok).toBe(true)
  if (!n1.ok) return
  expect(n1.value.players - n0.value.players).toBe(1234)
  expect(n1.value.merchants).toBe(n0.value.merchants)
  expect(n1.value.counted_at).toBe(n0.value.counted_at)
  // and it is one journal row, written by the helper, not a second row of the base
  const pending = await db.callAs<number>(`select count(*)::int as result from public.stats_live_deltas`)
  expect(Number(pending)).toBe(1)
  expect(Number(await db.callAs<number>(`select count(*)::int as result from public.stats_live`))).toBe(1)
})

// ── EVERY CITY IS OPEN TO EVERYONE (0223, owner row 197) ───────────────────────────────────────
test('with nothing invested anywhere a city serves its overview and its detail, and every list row its figures', async () => {
  // the precondition is the company's own: not one share held anywhere
  expect(Number(await db.callAs<number>(`select count(*)::int as result from public.city_shares where player_id = public.current_player_id()`))).toBe(0)
  // the gate and its knobs are gone from the chain, not set to zero
  expect(await db.callAs<boolean>(`select to_regprocedure('public.stats_city_tier(uuid, uuid)') is null as result`)).toBe(true)
  expect(Number(await db.callAs<number>(`select count(*)::int as result from public.world_config where key like 'stats_city_tier%'`))).toBe(0)

  const c = await worldStatsCity(port.id)
  expect(c.ok).toBe(true)
  if (!c.ok) return
  expect(c.value.overview).toBeDefined()
  expect(c.value.detail).toBeDefined()
  for (const k of ['tier', 'paid', 'need', 'tier1', 'tier2']) expect(c.value).not.toHaveProperty(k)
  const purse = Number(await db.callAs<number>(`select public.treasury_balance($1::uuid)::bigint as result`, [port.id]))
  expect(c.value.overview!.purse).toBe(purse)
  expect(Array.isArray(c.value.overview!.works)).toBe(true)
  const offered = Number(await db.callAs<number>(`select count(*)::int as result from public.port_specialties where port_id = $1::uuid`, [port.id]))
  expect(c.value.detail!.goods.length).toBeGreaterThanOrEqual(offered)
  const g = c.value.detail!.goods.find((x) => x.mid !== null)!
  expect(g).toBeDefined()
  expect(g.stock).not.toBeNull()
  expect(g.stock_target).not.toBeNull()

  const list = await worldStatsCities()
  expect(list.ok).toBe(true)
  if (!list.ok) return
  const harbours = Number(await db.callAs<number>(`select count(*)::int as result from public.ports where kind = 'HARBOUR'`))
  expect(list.value.cities).toHaveLength(harbours)
  for (const k of ['tier1', 'tier2']) expect(list.value).not.toHaveProperty(k)
  const row = list.value.cities.find((x) => x.code === port.code)!
  expect(row.purse).toBe(purse)
  expect(row.income_1d).toBeDefined()
  expect(row.taxes_1d).toBeDefined()
  for (const k of ['tier', 'paid', 'need']) expect(row).not.toHaveProperty(k)
  // nothing invested anywhere, and not one city withholds its purse
  expect(list.value.cities.every((x) => x.purse !== undefined)).toBe(true)
})
