// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ONE GOOD, EVERY CITY — world.good_board and world.watchlist (0171, docs/COMMAND_DESK.md §7.2–7.3, D2)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-17: "when i press coffee trade goods, it will show chart, where i can buy, the price if i
// sell to other cities. at which time". Two reads answer it; this spec reads them back off a real PostgreSQL
// (the build's own world) as a company founded at Lisbon, and holds them to what the desk will print:
//   * where it is sold (Buy at), with Lisbon "here" at 0 miles, and every harbour that buys it (Sell at);
//   * the quoted rows first, best net first, and each net the money's own parts added up;
//   * the watchlist names every good once, with its cheapest seller.
// It names good_board and watchlist so CI's rule S selects it when a migration re-defines them.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'

interface BuyRow {
  port: string
  here: boolean
  units: number
  cost: number
  price_each: number | null
  stock: number
  miles: number | null
  days: number | null
  arrive_at: string | null
  at_arrival: { value: number; lo: number; hi: number } | null
  best: { at: string; value: number; gain_pct: number } | null
}
interface SellRow {
  sailable?: boolean   // 0188
  port: string
  mid: number
  quoted: boolean
  miles: number | null
  units: number | null
  proceeds: number | null
  cost: number | null
  profit_tax: number | null
  port_fee: number | null
  wages: number | null
  net: number | null
  net_per_ton: number | null
  cap_left: number | null
}
interface Board {
  good: string
  fleet: { id: string; where: { kind: string; port: string | null }; speed_kn: number; wage_per_day: number }
  qty: { units: number; basis: string; tons: number; bought_at: string | null }
  buy: BuyRow[]
  sell: SellRow[]
  quoted: number
  quoted_near?: number
  assumes: string
}
interface Watch {
  window_slots: number
  goods: { code: string; sellers: number; best: { port: string; mid: number; recorded: boolean } | null; spark: number[]; on_board: number }[]
}

let db: LocalDb
let fleet: string
let good: string
let code: string

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  await db.callAs(`select cmd.found_house('Balcão Spec', 'PRT') as result`)
  fleet = await db.callAs<string>(`select f.id as result from public.fleets f where f.player_id = public.current_player_id() limit 1`)
  const r = await db.pg.query<{ id: string; code: string }>(`
    select g.id, g.code from public.goods g
      join public.port_goods pg on pg.good_id = g.id and pg.port_id = (select id from public.ports where code = 'LIS')
     where public.port_offers(pg.port_id, g.id) and pg.stock >= 50
     order by g.code limit 1`)
  good = r.rows[0].id
  code = r.rows[0].code
})

test.afterAll(async () => {
  await db?.close()
})

const board = () =>
  db.callAs<Board>('select world.good_board($1::uuid, $2::uuid) as result', [good, fleet])

test('world.good_board: where it is sold, and every harbour that buys it, best net first', async () => {
  const b = await board()
  expect(b.good).toBe(code)
  expect(b.fleet.where).toEqual({ kind: 'docked', port: 'LIS' })
  expect(b.assumes).toBe('If nobody else trades here')
  expect(['capacity', 'step']).toContain(b.qty.basis)
  // Buy at: Lisbon sells it, here, at no distance
  const lis = b.buy.find((r) => r.port === 'LIS')!
  expect(lis.here).toBe(true)
  expect(lis.miles).toBe(0)
  expect(lis.units).toBeGreaterThan(0)
  for (const r of b.buy) expect(r.at_arrival).not.toBeNull()
  // Sell at: every harbour that buys it; the quoted ones first, sorted by net
  const harbours = (
    await db.pg.query<{ n: number }>(
      `select count(*)::int as n from public.ports p join public.goods g on g.id = $1
        where p.kind = 'HARBOUR' and not public.culture_refuses(p.culture, g.culture_mask)`,
      [good],
    )
  ).rows[0].n
  expect(b.sell).toHaveLength(harbours)
  const quoted = b.sell.filter((r) => r.quoted)
  // the dearest good_board_quoted, and (0251) the nearest good_board_quoted_near she can sail to — once each
  expect(quoted.length).toBeGreaterThanOrEqual(Math.min(b.quoted, harbours))
  expect(quoted.length).toBeLessThanOrEqual(b.quoted + b.quoted_near!)
  expect(b.quoted_near).toBe(5)
  const sailable = b.sell.filter((r) => r.sailable && r.port !== 'LIS').sort((x, y) => x.miles! - y.miles!)
  const cut = sailable[Math.min(b.quoted_near!, sailable.length) - 1]?.miles ?? -1
  expect(sailable.filter((r) => r.miles! < cut).every((r) => r.quoted)).toBe(true)
  expect(b.sell.slice(0, quoted.length).every((r) => r.quoted)).toBe(true)
  // 0188: a city no chain of legs within her captain's reach gets to has no passage, so no miles, days or net —
  // it ranks after every city she can sail to; the rest are best net first
  const netted = quoted.filter((r) => r.net !== null)
  expect(quoted.slice(netted.length).every((r) => r.net === null && r.miles === null && r.sailable === false)).toBe(true)
  for (let i = 1; i < netted.length; i++) expect(netted[i].net!).toBeLessThanOrEqual(netted[i - 1].net!)
  // what it costs is the buy row it would be bought at: the cheapest that can fill any of it
  const src = b.buy.find((r) => r.port === b.qty.bought_at)!
  expect(src.units).toBeGreaterThan(0)
  for (const r of netted) {
    // the net is the money's own parts; the port fee is inside what she gets, never subtracted twice
    expect(r.net).toBe(r.proceeds! - r.cost! - r.profit_tax! - r.wages!)
    expect(r.port_fee!).toBeGreaterThanOrEqual(0)
    expect(r.cost).toBe(src.cost)
  }
  for (const r of b.sell.filter((x) => !x.quoted)) {
    expect(r.net).toBeNull()
    expect(r.mid).toBeGreaterThan(0)
  }
})

test('a good on board is priced from what it cost', async () => {
  await db.callAs(`select cmd.do_buy($1::uuid, jsonb_build_object('good', $2::text, 'qty', 10)) as result`, [fleet, good])
  const b = await board()
  expect(b.qty.basis).toBe('on_board')
  expect(b.qty.units).toBe(10)
  const basis = await db.callAs<number>('select public.fleet_cargo_basis($1::uuid, $2::text) as result', [fleet, code])
  for (const r of b.sell.filter((x) => x.quoted)) expect(r.cost).toBe(Math.round(basis * 10))
})

test('world.watchlist: every good once, its cheapest seller, and the cargo on board', async () => {
  const w = await db.callAs<Watch>('select world.watchlist($1::uuid) as result', [fleet])
  const n = (await db.pg.query<{ n: number }>('select count(*)::int as n from public.goods')).rows[0].n
  expect(w.goods).toHaveLength(n)
  expect(new Set(w.goods.map((g) => g.code)).size).toBe(n)
  const mine = w.goods.find((g) => g.code === code)!
  expect(mine.on_board).toBe(10)
  expect(mine.sellers).toBeGreaterThan(0)
  expect(mine.best).not.toBeNull()
  for (const g of w.goods) expect(g.spark.length).toBeLessThanOrEqual(12)
})

test('neither read answers for a fleet that is not yours', async () => {
  await expect(
    db.callAs('select world.good_board($1::uuid, gen_random_uuid()) as result', [good]),
  ).rejects.toThrow(/E_NOT_YOURS/)
  await expect(db.callAs('select world.watchlist(gen_random_uuid()) as result')).rejects.toThrow(/E_NOT_YOURS/)
})
