// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WORLD KEEPS ITS FIGURES — the Stats tab's six reads over public.tick_stats (0214)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Through the client wrappers, as a company founded at Lisbon: the job writes one rollup per slot and
// nothing on a second call in the same slot; the public reads serve what it wrote; and THE GATE (the
// owner, 2026-10-20: "a statistic info of a city is added only when you invest certain amount") holds on
// the server: with nothing invested a city is locked and NO figure of it arrives; at stats_city_tier1 the
// overview and no detail; at stats_city_tier2 the detail. It names stats_city, stats_cities, stats_overview,
// stats_markets, stats_merchants, stats_me and tick_stats so CI's rule S selects it.

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

// ── THE GATE, in the owner's three steps ────────────────────────────────────────────────────────
test('with nothing invested a city is locked and no figure of it arrives', async () => {
  const c = await worldStatsCity(port.id)
  expect(c.ok).toBe(true)
  if (!c.ok) return
  expect(c.value.tier).toBe(0)
  expect(c.value.paid).toBe(0)
  expect(c.value.need).toBe(c.value.tier1)
  expect(c.value.overview).toBeUndefined()
  expect(c.value.detail).toBeUndefined()
  const list = await worldStatsCities()
  expect(list.ok).toBe(true)
  if (!list.ok) return
  const harbours = Number(await db.callAs<number>(`select count(*)::int as result from public.ports where kind = 'HARBOUR'`))
  expect(list.value.cities).toHaveLength(harbours)
  const row = list.value.cities.find((x) => x.code === port.code)!
  expect(row.tier).toBe(0)
  expect(row.purse).toBeUndefined()
  expect(row.income_1d).toBeUndefined()
  // nothing invested anywhere: not one city sends a figure
  expect(list.value.cities.every((x) => x.tier === 0 && x.purse === undefined)).toBe(true)
})

test('at the first threshold the overview arrives and the detail does not', async () => {
  await db.callAs(
    `insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day)
     values ($1::uuid, 'market', public.current_player_id(), 1, public.wc_num('stats_city_tier1')::bigint, 0, world.game_day())
     returning paid::text as result`,
    [port.id],
  )
  const c = await worldStatsCity(port.id)
  expect(c.ok).toBe(true)
  if (!c.ok) return
  expect(c.value.tier).toBe(1)
  expect(c.value.paid).toBe(c.value.tier1)
  expect(c.value.need).toBe(c.value.tier2 - c.value.tier1)
  expect(c.value.overview).toBeDefined()
  expect(c.value.detail).toBeUndefined()
  const purse = Number(await db.callAs<number>(`select public.treasury_balance($1::uuid)::bigint as result`, [port.id]))
  expect(c.value.overview!.purse).toBe(purse)
  expect(Array.isArray(c.value.overview!.works)).toBe(true)
  const list = await worldStatsCities()
  expect(list.ok).toBe(true)
  if (!list.ok) return
  const row = list.value.cities.find((x) => x.code === port.code)!
  expect(row.tier).toBe(1)
  expect(row.purse).toBe(purse)
  // only THAT city: every other harbour stays locked
  expect(list.value.cities.filter((x) => x.tier > 0)).toHaveLength(1)
})

test('at the second threshold the full detail arrives', async () => {
  await db.callAs(
    `update public.city_shares set paid = public.wc_num('stats_city_tier2')::bigint
      where port_id = $1::uuid and player_id = public.current_player_id() returning paid::text as result`,
    [port.id],
  )
  const c = await worldStatsCity(port.id)
  expect(c.ok).toBe(true)
  if (!c.ok) return
  expect(c.value.tier).toBe(2)
  expect(c.value.need).toBeNull()
  expect(c.value.overview).toBeDefined()
  expect(c.value.detail).toBeDefined()
  const offered = Number(await db.callAs<number>(`select count(*)::int as result from public.port_specialties where port_id = $1::uuid`, [port.id]))
  expect(c.value.detail!.goods.length).toBeGreaterThanOrEqual(offered)
  const g = c.value.detail!.goods.find((x) => x.mid !== null)!
  expect(g).toBeDefined()
  expect(g.stock).not.toBeNull()
  expect(g.stock_target).not.toBeNull()
})
