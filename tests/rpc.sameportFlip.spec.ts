// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A ROUND TRIP NEVER PAYS — world.quote_priced's shelf rule and the house's rounding (0212)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE BUG THIS GUARDS AGAINST (found 2026-10-19 while building the live-price tick): buy 10 and sell them
// in the SAME port, with no time passing, and the sale was priced one stock step BETTER than the buy —
// each step of world.quote_priced's walk priced at the stock it STARTED from, so a buy from S paid mid(S)
// and the sale from S − 10 received mid(S − 10), the dearer mid. At a spread shaved to 0.4 % the flip paid.
// A second leak: `total := round(v_total)` on both sides paid a cheap good's x.50 bid a ducat up per one-tun lot.
//
// 0212's rule: stock is shelved in trade_step_tuns; a shelf has ONE mid (its top), whichever way it is
// walked; a buy's total is ceiled to the ducat and a sale's floored. This spec holds the ONE authority
// (world.quote_priced, which world.quote and both doors cmd.do_buy / cmd.do_sell compose) to the theorem:
//   * through the DOORS, a company that buys N and sells those N on the same quay, as one lot or as one-tun
//     lots, never holds more ducats than before;
//   * through the AUTHORITY, for any stock (fractional, below one shelf, on and off a boundary), any spread
//     (0, the shaved floor, the base, the widest) and any N (1 to 999): the sale mirrors the buy's shelves to
//     the digit (mid_total equal, the stock back where it was) and returns ≤ what was paid; lots too;
//   * the spread BITES: at a positive spread the round trip loses money, it does not merely break even;
//   * world.price's ask is a one-tun buy quote to the cent on a shelf boundary (what is shown is what the
//     first tun costs), and its bid is never below a one-tun sell quote (the sale fills the shelf above).
// It runs off a real PostgreSQL (the build's own world); every planted stock and knob is rolled back.
// It names world.quote_priced, world.quote, world.price, cmd.do_buy and cmd.do_sell so CI's rule S
// selects it whenever a migration re-defines one of them.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'

interface Quote {
  units: string
  total: string
  avg_price: string
  end_stock: string
  mid_total: string
}

let db: LocalDb
let fleet: string
let port: string
let good: string

const q = async <T,>(sql: string, params: unknown[] = []): Promise<T[]> => (await db.pg.query<T>(sql, params)).rows

const purse = () => db.callAs<number>('select ducats::int as result from public.players where id = public.current_player_id()')

const door = (verb: 'do_buy' | 'do_sell', qty: number) =>
  db.callAs<{ qty: number; total: number }>(`select cmd.${verb}($1::uuid, $2::jsonb) as result`, [fleet, JSON.stringify({ good, qty })])

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  await db.callAs(`select cmd.found_house('Casa Vaivém', 'PRT') as result`)
  const f = await db.callAs<{ id: string; port_id: string }>(
    'select to_jsonb(f) as result from public.fleets f where f.player_id = public.current_player_id() limit 1',
  )
  fleet = f.id
  port = f.port_id
  // the cheapest good this quay sells with a deep enough stock: cheap, so the ducat rounding is a large share
  const g = await q<{ id: string }>(
    `select g.id from public.goods g join public.port_goods pg on pg.good_id = g.id and pg.port_id = $1::uuid
      where public.port_offers(pg.port_id, g.id) and pg.stock >= 300 and g.bulk <= 1
      order by g.base_value, g.code limit 1`,
    [port],
  )
  good = g[0].id
})

test.afterAll(async () => {
  await db?.close()
})

test('through the doors: buy N, sell N on the same quay, and the purse never grows (one lot, and one-tun lots)', async () => {
  for (const n of [1, 7, 10, 15, 37]) {
    const before = await purse()
    const bought = await door('do_buy', n)
    expect(bought.qty).toBe(n)
    const sold = await door('do_sell', n)
    expect(sold.qty).toBe(n)
    const after = await purse()
    expect(after, `buy ${n} then sell ${n}: ${before} → ${after}`).toBeLessThanOrEqual(before)
  }
  // seven, sold one tun at a time: the shelf's one price and the floored ducat leave nothing to win
  const before = await purse()
  await door('do_buy', 7)
  for (let i = 0; i < 7; i++) await door('do_sell', 1)
  expect(await purse()).toBeLessThanOrEqual(before)
})

test('the authority: any stock, any spread, any N — the sale mirrors the buy and returns no more than was paid', async () => {
  test.setTimeout(600_000)
  const stocks = [0.5, 1, 5, 9.99, 10, 11, 37.3, 600, 600.01, 1370, 6699.97, 50000]
  const spreads = [0, 0.004, 0.02, 0.06]
  const ns = [1, 2, 7, 10, 13, 30, 100, 999]
  let pairs = 0
  let bitten = 0
  await db.pg.transaction(async (tx) => {
    const t = async <T,>(sql: string, params: unknown[] = []) => (await tx.query<T>(sql, params)).rows
    const tq = async (n: number, side: 'buy' | 'sell'): Promise<Quote> =>
      (await t<Quote>('select * from world.quote_priced($1::uuid, $2::uuid, $3::numeric, $4, null, null, null, null, null, null)', [port, good, n, side]))[0]
    const plant = (stock: number) => tx.query('update public.port_goods set stock = $3 where port_id = $1::uuid and good_id = $2::uuid', [port, good, stock])
    for (const spread of spreads) {
      await tx.query(`update public.world_config set value = to_jsonb($1::numeric) where key in ('spread_base', 'spread_floor')`, [spread])
      for (const stock of stocks) {
        for (const n of ns) {
          await plant(stock)
          const b = await tq(n, 'buy')
          const units = Number(b.units)
          expect(units, `a buy of ${n} at stock ${stock}`).toBeGreaterThan(0)
          expect(units).toBeLessThanOrEqual(Math.min(n, stock))
          await plant(Number(b.end_stock))
          const s = await tq(units, 'sell')
          const tag = `spread ${spread}, stock ${stock}, N ${n}`
          expect(Number(s.units), tag).toBe(units)
          expect(Number(s.mid_total), `${tag}: the sale's shelves are the buy's`).toBe(Number(b.mid_total))
          expect(Number(s.end_stock), `${tag}: the stock returns`).toBeCloseTo(stock, 6)
          expect(Number(s.total), `${tag}: bought for ${b.total}, sold for ${s.total}`).toBeLessThanOrEqual(Number(b.total))
          if (spread > 0 && Number(b.mid_total) * spread >= 2) {
            // the spread is worth at least a ducat a side here, so the round trip must LOSE, not break even
            expect(Number(s.total), `${tag}: the spread bites`).toBeLessThan(Number(b.total))
            bitten++
          }
          // the same N sold one tun at a time, each lot from the stock the last one left
          if (Number.isInteger(units) && units <= 13) {
            await plant(Number(b.end_stock))
            let lots = 0
            for (let i = 0; i < units; i++) {
              const l = await tq(1, 'sell')
              lots += Number(l.total)
              await plant(Number(l.end_stock))
            }
            expect(lots, `${tag}: ${units} one-tun lots sold for ${lots}, bought for ${b.total}`).toBeLessThanOrEqual(Number(b.total))
          }
          pairs++
        }
      }
    }
    throw new Error('rollback')
  }).catch((e: unknown) => {
    if (!(e instanceof Error) || e.message !== 'rollback') throw e
  })
  expect(pairs).toBe(stocks.length * spreads.length * ns.length)
  expect(bitten).toBeGreaterThan(0)
})

test('world.price: the ask is a one-tun buy quote to the cent on a shelf boundary; the bid is never below a one-tun sell', async () => {
  await db.pg.transaction(async (tx) => {
    await tx.query('update public.port_goods set stock = 600 where port_id = $1::uuid and good_id = $2::uuid', [port, good])
    const p = (await tx.query<{ mid: string; ask: string; bid: string }>('select mid, ask, bid from world.price($1::uuid, $2::uuid)', [port, good])).rows[0]
    const b1 = (await tx.query<Quote>("select * from world.quote_priced($1::uuid, $2::uuid, 1, 'buy', null, null, null, null, null, null)", [port, good])).rows[0]
    const s1 = (await tx.query<Quote>("select * from world.quote_priced($1::uuid, $2::uuid, 1, 'sell', null, null, null, null, null, null)", [port, good])).rows[0]
    expect(Number(b1.avg_price)).toBe(Number(p.ask))
    expect(Number(s1.avg_price)).toBeLessThanOrEqual(Number(p.bid))
    expect(Number(s1.avg_price)).toBeLessThan(Number(p.ask))
    throw new Error('rollback')
  }).catch((e: unknown) => {
    if (!(e instanceof Error) || e.message !== 'rollback') throw e
  })
})
