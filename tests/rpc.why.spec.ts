// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHY THIS PRICE — world.price_why and the faith tastes (0185, docs/PRICE_FACTORS.md §3.1, §5, slice P1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-18: "is there a way for the prices move on many different factors? like relationship
// with other countries, religion, merchants". 0185 adds the faith half of a city's taste (per GOOD:
// coffee is dear in an Islamic city, sherry cheap) to the one stored demand, and one read that says why a
// price is what it is. This spec reads both back off a real PostgreSQL (the build's own world) and holds
// them to their promises:
//   * the read IS world.price (mid, ask, bid) and its terms multiply back to the mid;
//   * its taste is the row's stored demand, split into the region's half and the faith's half;
//   * an Islamic city's faith pays 1.35 for coffee and 0.60 for sherry; a city with no faith pays 1;
//   * the face's lines (whyLines) name the faith and rank the largest effect first;
//   * it refuses what it cannot answer; a signed-in player may read it, anon may not.
// It names the function its slice defines (world.price_why / price_why), so CI's rule S selects it
// whenever a migration re-defines it (docs/CI.md).

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { stakeLine, tariffLine, volumeLine, whyLines } from '../src/features/command/markets/whyLines'
import type { PriceWhy } from '../src/lib/rpc/types'

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
})

test.afterAll(async () => {
  await db?.close()
})

async function row(goodCode: string, faith: string | null): Promise<{ port_id: string; good_id: string }> {
  const r = await db.pg.query<{ port_id: string; good_id: string }>(
    `select pg.port_id, pg.good_id
       from public.port_goods pg join public.goods g on g.id = pg.good_id
      where g.code = $1 and world.port_faith(pg.port_id) is not distinct from $2
      order by pg.port_id limit 1`,
    [goodCode, faith],
  )
  expect(r.rows, `no ${goodCode} row in a ${faith ?? 'faithless'} city`).toHaveLength(1)
  return r.rows[0]
}

/** The signed-in company (Portuguese, founded at Lisbon if the built world has none for this caller). */
async function myCompany(): Promise<string> {
  const pid = await db.callAs<string | null>('select public.current_player_id() as result')
  if (pid) return pid
  return (await db.pg.query<{ id: string }>('select public.new_house($1, $2, $3, $4) as id', [db.authUid, 'Casa Spec 0191', 'PRT', 'LIS'])).rows[0].id
}

async function why(p: string, g: string): Promise<PriceWhy> {
  return db.callAs<PriceWhy>('select world.price_why($1::uuid, $2::uuid) as result', [p, g])
}

test('world.price_why is world.price, and its terms multiply back to the mid', async () => {
  for (const [code, faith] of [['coffee', 'islamic'], ['sherry', 'islamic'], ['wax', 'christian'], ['pepper', null]] as const) {
    const goodCode = code === 'pepper' ? 'black-pepper' : code
    const r = await row(goodCode, faith)
    const w = await why(r.port_id, r.good_id)
    const p = (await db.pg.query<{ mid: string; ask: string; bid: string }>(
      'select mid, ask, bid from world.price($1::uuid, $2::uuid)', [r.port_id, r.good_id])).rows[0]
    expect([w.mid, w.ask, w.bid].map(Number)).toEqual([p.mid, p.ask, p.bid].map(Number))
    const product = Number(w.base) * w.terms.reduce((acc, t) => acc * Number(t.mult), 1)
    expect(Math.abs(product - Number(w.mid))).toBeLessThanOrEqual(Math.max(0.0005 * Number(w.mid), 0.0002))
    const demand = (await db.pg.query<{ demand: string }>(
      'select demand from public.port_goods where port_id = $1 and good_id = $2', [r.port_id, r.good_id])).rows[0].demand
    const taste = w.terms.find((t) => t.key === 'taste')!
    expect(Number(taste.mult)).toBe(Number(demand))
    expect(w.faith?.code ?? null).toBe(faith)
  }
})

test('a faith wants what it wants: coffee dear and sherry cheap in an Islamic city, nothing where no faith is held', async () => {
  const coffee = await row('coffee', 'islamic')
  const sherry = await row('sherry', 'islamic')
  const pepper = await row('black-pepper', null)
  const faithOf = async (r: { port_id: string; good_id: string }) =>
    Number((await why(r.port_id, r.good_id)).terms.find((t) => t.key === 'taste')!.faith)
  expect(await faithOf(coffee)).toBe(1.35)
  expect(await faithOf(sherry)).toBe(0.6)
  expect(await faithOf(pepper)).toBe(1)
  // the stored taste is the region's half × the faith's half, rounded once (world.demand_for)
  const d = (await db.pg.query<{ bad: number }>(`
    select count(*)::int as bad from public.port_goods pg
     where pg.demand is distinct from round(world.region_taste(pg.port_id, pg.good_id) * world.faith_taste(pg.port_id, pg.good_id), 3)`)).rows[0]
  expect(d.bad).toBe(0)
  // the face names the faith, largest effect first
  const w = await why(coffee.port_id, coffee.good_id)
  const lines = whyLines(w)
  expect(lines.find((l) => l.key === 'taste-faith')).toMatchObject({ label: 'Islamic demand', effect: '+35.0%' })
  for (let i = 1; i < lines.length; i++) {
    expect(Math.abs(Math.log(lines[i - 1].mult))).toBeGreaterThanOrEqual(Math.abs(Math.log(lines[i].mult)))
  }
})

test('0190: a busy quay is seen — what changed hands here today, and by how many companies', async () => {
  const r = await row('coffee', 'islamic')
  const before = await why(r.port_id, r.good_id)
  const players = (await db.pg.query<{ id: string }>('select id from public.players order by id limit 2')).rows
  expect(players.length, 'the built world has no company to trade').toBeGreaterThanOrEqual(1)
  const day = (await db.pg.query<{ d: number }>('select world.game_day() as d')).rows[0].d
  await db.pg.query(
    `insert into public.trade_daily (player_id, port_id, good_id, game_day, qty) values ($1, $2, $3, $4 - 1, 1000)
     on conflict (player_id, port_id, good_id, game_day) do update set qty = public.trade_daily.qty + excluded.qty`,
    [players[0].id, r.port_id, r.good_id, day])
  await db.pg.query(
    `insert into public.trade_daily (player_id, port_id, good_id, game_day, qty) values ($1, $2, $3, $4, 37)
     on conflict (player_id, port_id, good_id, game_day) do update set qty = public.trade_daily.qty + excluded.qty`,
    [players[0].id, r.port_id, r.good_id, day])
  const after = await why(r.port_id, r.good_id)
  expect(Number(after.volume!.units) - Number(before.volume!.units)).toBe(37)
  expect(after.volume!.houses).toBeGreaterThanOrEqual(1)
  expect(volumeLine(after)).toMatch(/^Today: [\d,]+ units by \d+ compan(y|ies)$/)
  expect(volumeLine({ ...after, volume: { game_day: day, units: 0, houses: 0 } })).toBe('No trades here today.')
})

test('0191: a city\'s best friends trade cheaper — rank 1 among its givers is spared 10 % of the spread', async () => {
  await db.pg.query(`update public.world_config set value = 'true'::jsonb where key = 'influence_enabled'`)
  const pid = await myCompany()
  const f = (await db.pg.query<{ id: string; nation_id: string }>(
    'select f.id, pl.nation_id from public.fleets f join public.players pl on pl.id = f.player_id where f.player_id = $1 order by f.id limit 1', [pid])).rows[0]
  const at = (await db.pg.query<{ port: string; good: string; far: string }>(`
    select (select id from public.ports where code = 'LIS') as port, (select id from public.goods order by code limit 1) as good,
           (select id from public.ports where code = 'LON') as far`)).rows[0]
  const spread = async (port: string) =>
    Number((await db.pg.query<{ s: string }>('select world.spread_effective($1, $2, $3) as s', [port, at.good, f.id])).rows[0].s)
  const floor = Number((await db.pg.query<{ s: string }>(
    `select world.spread($1) * public.wc_num('haggle_spread_floor_frac') as s`, [at.port])).rows[0].s)
  const before = await spread(at.port)
  const farBefore = await spread(at.far)
  await db.pg.query(`
    insert into public.port_influence (port_id, nation_id, player_id, points)
    values ($1, $2, $3, coalesce((select max(t.p) from (select sum(points) as p from public.port_influence where port_id = $1 group by player_id) t), 0) + 1000)
    on conflict (port_id, nation_id, player_id) do update set points = excluded.points`, [at.port, f.nation_id, pid])
  expect(await spread(at.port)).toBeCloseTo(Math.max(floor, before * 0.9), 9)
  expect(await spread(at.far)).toBe(farBefore)
  const w = await db.callAs<PriceWhy>('select world.price_why($1::uuid, $2::uuid) as result', [at.port, at.good])
  expect(w.stake).toEqual({ rank: 1, shave: 0.1 })
  expect(stakeLine(w)).toBe('#1 giver here: 10% off the spread')
})

test('0194: a glutted market remembers — the glut is its own term, and it is printed', async () => {
  const r = await row('coffee', 'islamic')
  await db.pg.query('update public.port_goods set glut = 0.15 where port_id = $1 and good_id = $2', [r.port_id, r.good_id])
  const w = await why(r.port_id, r.good_id)
  expect(Number(w.terms.find((t) => t.key === 'glut')!.mult)).toBe(0.85)
  const product = Number(w.base) * w.terms.reduce((acc, t) => acc * Number(t.mult), 1)
  expect(Math.abs(product - Number(w.mid))).toBeLessThanOrEqual(Math.max(0.0005 * Number(w.mid), 0.0002))
  expect(whyLines(w).find((l) => l.key === 'glut')).toMatchObject({ label: 'Sold a lot lately', effect: '−15.0%' })
  await db.pg.query('update public.port_goods set glut = 0 where port_id = $1 and good_id = $2', [r.port_id, r.good_id])
})

test("0196: a rival pays the tariff — the profit tax by how the company's power stands with the city's holder", async () => {
  await db.pg.query(`update public.world_config set value = 'true'::jsonb where key in ('influence_enabled', 'city_treasury_enabled')`)
  const pid = await myCompany()
  const nation = (await db.pg.query<{ code: string }>(
    'select n.code from public.players pl join public.nations n on n.id = pl.nation_id where pl.id = $1', [pid])).rows[0].code
  expect(nation, "the spec's company is Portuguese (data/relations.json is read for Portugal below)").toBe('PRT')
  const good = (await db.pg.query<{ id: string }>('select id from public.goods order by code limit 1')).rows[0].id
  const cap = Number((await db.pg.query<{ v: string }>(`select public.wc_num('tariff_rate_max') as v`)).rows[0].v)
  const cut = Number((await db.pg.query<{ v: string }>(`select public.wc_num('influence_citizen_tax_cut') as v`)).rows[0].v)
  // each a great power's HOME city (data/home-ports.json; a home never changes hands), so the holder is the data's
  const cases = [
    { port: 'LIS', holder: 'PRT', stance: 'home', want: (b: number) => b * (1 - cut) },
    { port: 'CAD', holder: 'ESP', stance: 'ally', want: (b: number) => b * 0.5 },
    { port: 'IST', holder: 'OTT', stance: 'rival', want: (b: number) => Math.min(b * 1.5, Math.max(b, cap)) },
    { port: 'AMS', holder: 'NLD', stance: 'war', want: (b: number) => Math.min(b * 2, Math.max(b, cap)) },
    { port: 'LAR', holder: 'FRA', stance: 'peace', want: (b: number) => b },
  ] as const
  for (const c of cases) {
    const port = (await db.pg.query<{ id: string; holder: string | null }>(
      `select p.id, (select n.code from public.nations n where n.id = public.port_nation(p.id)) as holder
         from public.ports p where p.code = $1`, [c.port])).rows[0]
    expect(port.holder, `${c.port}'s flag`).toBe(c.holder)
    const w = await why(port.id, good)
    expect(w.tariff, `${c.port}: price_why's tariff`).toBeTruthy()
    const base = Number(w.tariff!.base)
    expect(w.tariff!.stance).toBe(c.stance)
    expect(w.tariff!.holder?.code).toBe(c.holder)
    expect(Number(w.tariff!.rate)).toBeCloseTo(c.want(base), 9)
    // the charge is the same authority: profit_tax on 1,000 d. of profit at the company's rate
    const tax = Number((await db.pg.query<{ t: string }>('select public.profit_tax($1, 1000, $2) as t', [port.id, pid])).rows[0].t)
    expect(tax).toBe(Math.round(1000 * Number(w.tariff!.rate)))
    expect(Number(w.tariff!.rate)).toBeLessThanOrEqual(Math.max(base, cap) + 1e-12)
  }
  const ist = (await db.pg.query<{ id: string }>(`select id from public.ports where code = 'IST'`)).rows[0].id
  const line = tariffLine(await why(ist, good))!
  expect(line.label).toBe('Profit tax · Ottoman Empire, rival')
  expect(line.value).toMatch(/^\d+(\.\d)?% \(×1\.5\)$/)
  const lis = (await db.pg.query<{ id: string }>(`select id from public.ports where code = 'LIS'`)).rows[0].id
  expect(tariffLine(await why(lis, good))!.label).toBe('Profit tax · own country')
  // the race off: every company pays the city's rate, and the line names no stance
  await db.pg.query(`update public.world_config set value = 'false'::jsonb where key = 'influence_enabled'`)
  const off = await why(ist, good)
  expect(Number(off.tariff!.rate)).toBe(Number(off.tariff!.base))
  expect(tariffLine(off)!.label).toBe('Profit tax · Ottoman Empire')
  await db.pg.query(`update public.world_config set value = 'true'::jsonb where key = 'influence_enabled'`)
})

test('it refuses what it cannot answer', async () => {
  const r = await row('coffee', 'islamic')
  await expect(why(r.port_id, '00000000-0000-0000-0000-000000000000')).rejects.toThrow(/E_NO_SUCH_GOOD/)
  await expect(db.callAs('select world.price_why(null::uuid, $1::uuid) as result', [r.good_id])).rejects.toThrow(/E_NO_SUCH_PORT/)
})

test('a signed-in player may read it, anon may not, and the leaves and tables are the server\'s own', async () => {
  const grants = await db.pg.query<{ fn: string; auth: boolean; anon: boolean }>(`
    select f.fn, has_function_privilege('authenticated', f.fn, 'execute') as auth, has_function_privilege('anon', f.fn, 'execute') as anon
      from unnest(array['world.price_why(uuid, uuid)', 'world.port_faith(uuid)', 'world.faith_taste(uuid, uuid)',
                        'world.region_taste(uuid, uuid)', 'world.demand_for(uuid, uuid)',
                        'public.power_stance(uuid, uuid)', 'public.stance_mult(text)']) f(fn)`)
  expect(grants.rows).toEqual([
    { fn: 'world.price_why(uuid, uuid)', auth: true, anon: false },
    { fn: 'world.port_faith(uuid)', auth: false, anon: false },
    { fn: 'world.faith_taste(uuid, uuid)', auth: false, anon: false },
    { fn: 'world.region_taste(uuid, uuid)', auth: false, anon: false },
    { fn: 'world.demand_for(uuid, uuid)', auth: false, anon: false },
    { fn: 'public.power_stance(uuid, uuid)', auth: false, anon: false },
    { fn: 'public.stance_mult(text)', auth: false, anon: false },
  ])
  const table = await db.pg.query<{ sel: boolean }>(
    `select has_table_privilege('authenticated', 'public.power_relations', 'select') or has_table_privilege('anon', 'public.power_relations', 'select') as sel`)
  expect(table.rows[0].sel).toBe(false)
  const registered = await db.pg.query<{ n: number }>(
    `select count(*)::int as n from public.client_rpc_entry_points() where function_name = 'price_why' and arg_types = 'uuid, uuid'`,
  )
  expect(registered.rows[0].n).toBe(1)
})
