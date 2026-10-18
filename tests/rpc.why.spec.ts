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
import { whyLines } from '../src/features/command/markets/whyLines'
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

test('it refuses what it cannot answer', async () => {
  const r = await row('coffee', 'islamic')
  await expect(why(r.port_id, '00000000-0000-0000-0000-000000000000')).rejects.toThrow(/E_NO_SUCH_GOOD/)
  await expect(db.callAs('select world.price_why(null::uuid, $1::uuid) as result', [r.good_id])).rejects.toThrow(/E_NO_SUCH_PORT/)
})

test('a signed-in player may read it, anon may not, and the leaves and tables are the server\'s own', async () => {
  const grants = await db.pg.query<{ fn: string; auth: boolean; anon: boolean }>(`
    select f.fn, has_function_privilege('authenticated', f.fn, 'execute') as auth, has_function_privilege('anon', f.fn, 'execute') as anon
      from unnest(array['world.price_why(uuid, uuid)', 'world.port_faith(uuid)', 'world.faith_taste(uuid, uuid)',
                        'world.region_taste(uuid, uuid)', 'world.demand_for(uuid, uuid)']) f(fn)`)
  expect(grants.rows).toEqual([
    { fn: 'world.price_why(uuid, uuid)', auth: true, anon: false },
    { fn: 'world.port_faith(uuid)', auth: false, anon: false },
    { fn: 'world.faith_taste(uuid, uuid)', auth: false, anon: false },
    { fn: 'world.region_taste(uuid, uuid)', auth: false, anon: false },
    { fn: 'world.demand_for(uuid, uuid)', auth: false, anon: false },
  ])
  const registered = await db.pg.query<{ n: number }>(
    `select count(*)::int as n from public.client_rpc_entry_points() where function_name = 'price_why' and arg_types = 'uuid, uuid'`,
  )
  expect(registered.rows[0].n).toBe(1)
})
