// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BEST SALE READS THE SEA ONCE — world.best_sales after 0350 (the same answer, faster)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// 0348 gave every goods card its best sale (world.best_sales); on prod a call took ~2.6 s. 0350 takes out the
// work a call repeated for every good — world.mid_price once per harbour (now world.good_mids: every buyer's
// price in one pass) and her passage and stores to every harbour (now world.board_legs, asked once a call and
// handed to every world.board_sell) — and changes no figure. This spec reads the build's own world on a real
// PostgreSQL, as a company founded at Lisbon, and holds the read to the laws it must keep:
//   * THE CARD IS THE TRAY: a card's profit and units are world.good_board(good, fleet, here, units)'s row for
//     that city, to the coin — for every good with a sale, from her own city and from another city in hand;
//   * her cargo reads as cargo (basis on_board) and is world.good_board(good, fleet)'s row;
//   * world.good_mids is world.mid_price for every market row of the goods her city sells;
//   * world.board_sell answers the same whether the legs are handed over or asked there;
//   * the pieces are server-only (authenticated may run world.best_sales and none of them), and the body no
//     longer prices a harbour at a time.
// It names best_sales, good_board, board_sell, board_legs and good_mids so CI's rule S selects it when a
// migration re-defines any of them. Nothing here asserts a price or a time: prices move, and the time is
// measured where it can be compared (the migration's own probe; docs/dev-log/2026-11-11-dearest-buyers.md).

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'

interface Card {
  good: string
  basis: string
  port: string | null
  units: number | null
  profit: number | null
  days: number | null
  pays: boolean
}
interface Sales {
  port: string
  goods: Card[]
  cut: boolean
}
interface SellRow {
  port: string
  sailable: boolean
  units: number | null
  profit: number | null
}

let db: LocalDb
let fleet: string
let lisbon: string
let other: { id: string; code: string }

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  await db.callAs(`select cmd.found_house('Legs Spec', 'PRT') as result`)
  fleet = await db.callAs<string>(`select f.id as result from public.fleets f where f.player_id = public.current_player_id() limit 1`)
  lisbon = (await db.pg.query<{ id: string }>(`select id from public.ports where code = 'LIS'`)).rows[0].id
  // the nearest other harbour that sells goods: a city in hand that is not where she lies
  other = (
    await db.pg.query<{ id: string; code: string }>(
      `select p.id, p.code from public.ports p, public.ports hb
        where hb.id = $1 and p.kind = 'HARBOUR' and p.id <> hb.id
          and exists (select 1 from public.port_goods pg where pg.port_id = p.id and public.port_offers(p.id, pg.good_id))
        order by voyage.gc_distance_nm(hb.lat, hb.lon, p.lat, p.lon), p.code limit 1`,
      [lisbon],
    )
  ).rows[0]
})

test.afterAll(async () => {
  await db?.close()
})

const sales = (port: string) => db.callAs<Sales>('select world.best_sales($1::uuid, $2::uuid) as result', [fleet, port])

/** Every card with a sale against world.good_board's row for that city, read in ONE statement (one snapshot). */
async function cardsAgainstBoard(port: string) {
  return db.callAs<{ card: Card; row: SellRow | null }[]>(
    `with bs as materialized (select world.best_sales($1::uuid, $2::uuid) as b),
          cards as (select e from bs, jsonb_array_elements(bs.b->'goods') e where e->>'port' is not null)
     select coalesce(jsonb_agg(jsonb_build_object('card', e, 'row',
              (select s from jsonb_array_elements(x.gb->'sell') s where s->>'port' = e->>'port'))), '[]'::jsonb) as result
       from cards
      cross join lateral (select world.good_board((select g.id from public.goods g where g.code = e->>'good'), $1::uuid,
                                                  case when e->>'basis' <> 'on_board' then $2::uuid end,
                                                  case when e->>'basis' <> 'on_board' then (e->>'units')::numeric end) as gb) x`,
    [fleet, port],
  )
}

test('world.best_sales: every good the city sells, and each card is world.good_board\'s row to the coin', async () => {
  test.setTimeout(300_000)
  const s = await sales(lisbon)
  expect(s.port).toBe('LIS')
  expect(s.cut).toBe(false)
  const offered = (
    await db.pg.query<{ code: string }>(
      `select g.code from public.port_goods pg join public.goods g on g.id = pg.good_id
        where pg.port_id = $1 and public.port_offers($1, g.id) order by g.code`,
      [lisbon],
    )
  ).rows.map((r) => r.code)
  expect(s.goods.map((g) => g.good)).toEqual(offered)
  expect(s.goods.some((g) => g.port !== null), 'no good at Lisbon has a sale').toBe(true)
  for (const g of s.goods) {
    expect(g.port, 'a card names the city it is bought at').not.toBe('LIS')
    expect(g.pays).toBe(g.profit !== null && g.profit > 0)
  }
  const pairs = await cardsAgainstBoard(lisbon)
  expect(pairs.length).toBe(s.goods.filter((g) => g.port !== null).length)
  for (const { card, row } of pairs) {
    expect(row, `${card.good}: the board does not price ${card.port}`).not.toBeNull()
    expect(row!.sailable).toBe(true)
    expect(row!.profit, `${card.good} at ${card.port}: the card's profit is not the board's`).toBe(card.profit)
    expect(row!.units, `${card.good} at ${card.port}: the card's units are not the board's`).toBe(card.units)
  }
})

test('from another city in hand (bought there, sailed to first) the card is still the board\'s row', async () => {
  test.setTimeout(300_000)
  const s = await sales(other.id)
  expect(s.port).toBe(other.code)
  expect(s.goods.length).toBeGreaterThan(0)
  const pairs = await cardsAgainstBoard(other.id)
  expect(pairs.length).toBe(s.goods.filter((g) => g.port !== null).length)
  for (const { card, row } of pairs) {
    expect(card.port).not.toBe(other.code)
    expect(row, `${card.good}: the board does not price ${card.port}`).not.toBeNull()
    expect(row!.profit).toBe(card.profit)
    expect(row!.units).toBe(card.units)
  }
})

test('world.good_mids is world.mid_price for every market row of the goods her city sells', async () => {
  const r = await db.pg.query<{ rows: number; differ: number; market_rows: number }>(
    `select count(*)::int as rows,
            (count(*) filter (where m.mid is distinct from world.mid_price(m.port_id, s.good_id, m.stock)
                                 or m.stock is distinct from pg.stock or m.stock_target is distinct from pg.stock_target))::int as differ,
            (select count(*)::int from public.port_goods x
              where x.good_id in (select pg0.good_id from public.port_goods pg0 where pg0.port_id = $1 and public.port_offers($1, pg0.good_id))) as market_rows
       from (select pg0.good_id from public.port_goods pg0 where pg0.port_id = $1 and public.port_offers($1, pg0.good_id)) s
      cross join lateral world.good_mids(s.good_id) m
       join public.port_goods pg on pg.port_id = m.port_id and pg.good_id = s.good_id`,
    [lisbon],
  )
  expect(r.rows[0].rows).toBeGreaterThan(0)
  expect(r.rows[0].rows).toBe(r.rows[0].market_rows)
  expect(r.rows[0].differ).toBe(0)
})

test('world.board_sell answers the same with the legs handed over as when it asks world.board_legs itself', async () => {
  // the context world.best_sales builds for a good bought at Lisbon, once without `legs` and once with them
  const same = await db.callAs<{ goods: number; differ: number; rows: number; harbours: number }>(
    `with o as materialized (select world.board_origin($1::uuid) as o),
          g as (select gd.id, row_number() over (order by gd.code) as rn
                  from public.port_goods pg join public.goods gd on gd.id = pg.good_id
                 where pg.port_id = $2::uuid and public.port_offers($2::uuid, gd.id)),
          c as materialized (
            select g.id, o.o || jsonb_build_object('units', a.units, 'basis', a.basis, 'cost_each', a.cost_each,
                     'src', jsonb_build_object('code', 'LIS'), 'src_cut', false, 'src_name', 'Lisbon', 'fit', true, 'lean', true) as ctx
              from g cross join o cross join lateral world.board_amount($1::uuid, g.id, null) a where g.rn <= 3),
          l as materialized (select world.board_legs($1::uuid, (select ctx from c limit 1)) as legs),
          r as (select world.board_sell(c.id, $1::uuid, c.ctx) as asked,
                       world.board_sell(c.id, $1::uuid, c.ctx || jsonb_build_object('legs', l.legs)) as handed
                  from c cross join l)
     select jsonb_build_object('goods', count(*), 'differ', count(*) filter (where asked is distinct from handed),
                               'rows', coalesce(sum(jsonb_array_length(asked)), 0),
                               'harbours', (select jsonb_array_length(legs) from l)) as result
       from r`,
    [fleet, lisbon],
  )
  expect(same.goods).toBe(3)
  expect(same.rows).toBeGreaterThan(0)
  expect(same.differ).toBe(0)
  const harbours = (await db.pg.query<{ n: number }>(`select count(*)::int as n from public.ports where kind = 'HARBOUR'`)).rows[0].n
  expect(same.harbours, 'world.board_legs answers one row a harbour').toBe(harbours)
})

test('the pieces are server-only, and world.board_sell no longer prices a harbour at a time', async () => {
  const acl = await db.pg.query<{ fn: string; may: boolean; anon: boolean; volatile: string }>(
    `select f as fn, has_function_privilege('authenticated', f, 'execute') as may, has_function_privilege('anon', f, 'execute') as anon,
            (select p.provolatile::text from pg_proc p where p.oid = f::regprocedure) as volatile
       from unnest(array['world.best_sales(uuid,uuid)', 'world.board_sell(uuid,uuid,jsonb)', 'world.board_legs(uuid,jsonb)', 'world.good_mids(uuid)',
                         'world.board_origin(uuid)', 'world.board_passages(uuid,uuid,uuid,numeric)', 'world.board_amount(uuid,uuid,numeric)']) f`,
  )
  for (const r of acl.rows) {
    expect(r.may, `${r.fn}: authenticated`).toBe(r.fn.startsWith('world.best_sales('))
    expect(r.anon, `${r.fn}: anon`).toBe(false)
    expect(r.volatile, `${r.fn}: a read is STABLE`).toBe('s')
  }
  const src = await db.pg.query<{ sell: string; best: string }>(
    `select (select prosrc from pg_proc where oid = 'world.board_sell(uuid,uuid,jsonb)'::regprocedure) as sell,
            (select prosrc from pg_proc where oid = 'world.best_sales(uuid,uuid)'::regprocedure) as best`,
  )
  expect(src.rows[0].sell).not.toContain('mid_price(')
  expect(src.rows[0].sell).not.toContain('supply_needs(')
  expect(src.rows[0].sell).toContain('world.good_mids(p_good)')
  expect(src.rows[0].sell).toContain('world.board_legs(p_fleet, p_ctx)')
  expect(src.rows[0].best).toContain('world.board_legs(p_fleet, v_ctx)')
  // the soft budget 0348 set is still there: a slow call fails soft, never raises
  expect(src.rows[0].best).toContain(`interval '2.5 seconds'`)
})

test('her cargo reads as cargo, beside the goods bought here, and is the Sail & sell row', async () => {
  test.setTimeout(300_000)
  const good = (
    await db.pg.query<{ id: string; code: string }>(
      `select g.id, g.code from public.goods g join public.port_goods pg on pg.good_id = g.id and pg.port_id = $1
        where public.port_offers($1, g.id) and pg.stock >= 50 order by g.code limit 1`,
      [lisbon],
    )
  ).rows[0]
  await db.callAs(`select cmd.do_buy($1::uuid, jsonb_build_object('good', $2::text, 'qty', 10)) as result`, [fleet, good.id])
  const s = await sales(lisbon)
  const mine = s.goods.find((g) => g.good === good.code)!
  expect(mine.basis).toBe('on_board')
  // both kinds of legs are read in this one call: her cargo (from where she lies) and the goods bought here
  expect(s.goods.some((g) => g.basis !== 'on_board')).toBe(true)
  const pairs = await cardsAgainstBoard(lisbon)
  expect(pairs.length).toBe(s.goods.filter((g) => g.port !== null).length)
  for (const { card, row } of pairs) {
    expect(row, `${card.good}: the board does not price ${card.port}`).not.toBeNull()
    expect(row!.profit, `${card.good} (${card.basis}) at ${card.port}`).toBe(card.profit)
    if (card.basis !== 'on_board') expect(row!.units).toBe(card.units)
  }
})
