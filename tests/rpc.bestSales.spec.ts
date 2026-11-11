// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BEST SALE READS THE SEA ONCE — world.best_sales after 0350 (the same answer, faster) and 0351 (a sale she can pay for)
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
// 0351 (docs/SUCCESS_PLAN.md T5) made the answer A SALE SHE CAN PAY FOR, THE BEST PER DAY: where she lies the units are
// the tray's own Max (world.buy_capacity -> public.fleet_buy_capacity) when anything but her hold binds it; a sale is
// a candidate when the buy (and her stores, unless they may be owed) is within her purse; the answer is the best profit
// per day of those, served with its cost and real seconds, and the dearest of them as `far`. The laws added:
//   * every card with a sale costs no more than her purse and asks for no more than the tray's Max;
//   * on world.good_board at the card's units, no sale within her purse has a better profit per day than the card's,
//     and none a bigger profit than its far choice;
//   * the body asks the one cap authority once and carries no cap rule of its own;
//   * THE CAP AUTHORITY'S BISECT IS ITS WALK: 0351 also re-cut public.fleet_buy_capacity (the docked tray's Max, BUY ALL's count)
//     to search by halving the purse walk it made a quote a step. The walk is rebuilt here from the migration's own OLD hunk and held
//     against the live body on fixed cases: seven purses, every good Lisbon sells, the stock and the day's cap forced to bind,
//     other steps, a purse of exactly what a count costs. Every pair equal: max_qty, est_total, bound_by.
// It names best_sales, good_board, board_sell, board_legs and good_mids so CI's rule S selects it when a
// migration re-defines any of them. Nothing here asserts a price or a time: prices move, and the time is
// measured where it can be compared (the migration's own probe; docs/dev-log/2026-11-11-dearest-buyers.md).

import { readFileSync } from 'node:fs'
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
  // 0351
  cost: number | null
  seconds: number | null
  short: boolean
  far: { port: string; units: number | null; profit: number | null; days: number | null; cost: number | null; seconds: number | null } | null
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
  cost: number | null
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
const purseNow = async () => Number(await db.callAs<number | string>(`select (select p.ducats from public.players p where p.id = public.current_player_id()) as result`))
const KEYS_0351 = ['cost', 'seconds', 'short', 'far'] as const

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
    expect(row!.cost, `${card.good} at ${card.port}: the card's cost is not the board's`).toBe(card.cost)
  }
})

interface Judged {
  card: Card
  cap: { max_qty: number; bound_by: string }
  row: (SellRow & { arrive_at: string }) | null
  pool: { port: string; profit: number; secs: number }[] | null
}

test('0351: where she lies every card is a sale she can pay for: the tray\'s Max, the best per day on the board, the dearest as far', async () => {
  test.setTimeout(300_000)
  const purse = await purseNow()
  expect(purse).toBeGreaterThan(0)
  // ONE statement (one snapshot): the read, the tray's Max for every good (world.buy_capacity: the RPC the docked tray reads), and for
  // every card priced at a Max her hold does not bind the board at the card's units — its row for the card's city and the sales on it
  // that are within her purse (the buy, and her stores unless they may be owed), each with its real seconds
  const judged = await db.callAs<Judged[]>(
    `with bs as materialized (select world.best_sales($1::uuid, $2::uuid) as b),
          cards as materialized (
            select x.e, g.id as gid, world.buy_capacity($1::uuid, g.id) as cap
              from bs cross join lateral jsonb_array_elements(bs.b->'goods') x(e) join public.goods g on g.code = x.e->>'good'),
          gb as materialized (
            select c.*, case when c.e->>'port' is not null and c.cap->>'bound_by' <> 'hold'
                             then world.good_board(c.gid, $1::uuid, $2::uuid, (c.e->>'units')::numeric) end as gb
              from cards c)
     select coalesce(jsonb_agg(jsonb_build_object('card', g.e, 'cap', g.cap,
              'row', (select s from jsonb_array_elements(g.gb->'sell') s where s->>'port' = g.e->>'port'),
              'pool', (select coalesce(jsonb_agg(jsonb_build_object('port', s->>'port', 'profit', (s->>'profit')::numeric,
                                'secs', greatest(extract(epoch from ((s->>'arrive_at')::timestamptz - now())), 1))), '[]'::jsonb)
                         from jsonb_array_elements(g.gb->'sell') s
                        where (s->>'quoted')::boolean and (s->>'sailable')::boolean and jsonb_typeof(s->'profit') = 'number' and s->>'port' <> 'LIS'
                          and (s->>'units')::numeric <= (s->'supplies'->>'units_fit')::numeric
                          and (s->>'cost')::numeric + case when public.credit_on($2::uuid) then 0 else coalesce((s->'supplies'->>'cost')::numeric, 0) end <= $3::numeric))
              order by g.e->>'good'), '[]'::jsonb) as result
       from gb g`,
    [fleet, lisbon, purse],
  )
  expect(judged.length).toBeGreaterThan(0)
  let atMax = 0
  let chosen = 0
  for (const { card, cap, row, pool } of judged) {
    for (const k of KEYS_0351) expect(card, `${card.good}: 0351 serves ${k}`).toHaveProperty(k)
    if (card.port === null) {
      expect(card.far).toBeNull()
      expect(card.pays).toBe(false)
      continue
    }
    expect(card.short, `${card.good}: short is only for a good with no sale`).toBe(false)
    expect(card.cost, `${card.good} at ${card.port}: the buy is within her purse`).toBeLessThanOrEqual(purse)
    expect(card.units, `${card.good}: no more than the tray's Max`).toBeLessThanOrEqual(cap.max_qty)
    expect(card.seconds, `${card.good}: the real time is served`).toBeGreaterThanOrEqual(1)
    if (card.far) {
      expect(card.far.port).not.toBe(card.port)
      expect(card.far.port).not.toBe('LIS')
      expect(card.far.cost, `${card.good}: the far sale is within her purse too`).toBeLessThanOrEqual(purse)
      expect(card.far.units).toBeLessThanOrEqual(cap.max_qty)
      expect(card.far.profit, `${card.good}: the far sale is the dearer one`).toBeGreaterThanOrEqual(card.profit!)
      if (card.pays) expect(card.far.seconds, `${card.good}: and no nearer`).toBeGreaterThanOrEqual(card.seconds!)
    }
    if (cap.bound_by === 'hold' || card.units !== cap.max_qty) continue
    // priced at the tray's Max: on the board at those units the card is its row, the best per day within her purse, and far the dearest
    atMax += 1
    expect(row, `${card.good}: the board does not price ${card.port}`).not.toBeNull()
    expect(row!.profit).toBe(card.profit)
    expect(row!.units).toBe(card.units)
    expect(row!.cost).toBe(card.cost)
    const mine = pool!.find((s) => s.port === card.port)
    expect(mine, `${card.good}: the card's city is one of the sales within her purse`).toBeTruthy()
    if (pool!.length > 1) chosen += 1
    const dearest = card.far?.profit ?? card.profit!
    for (const s of pool!) {
      expect(s.profit, `${card.good}: ${s.port} pays more than the far choice`).toBeLessThanOrEqual(dearest)
      if (card.pays && s.profit > 0) {
        const rate = mine!.profit / mine!.secs
        expect(s.profit / s.secs, `${card.good}: ${s.port} pays more per day than ${card.port}`).toBeLessThanOrEqual(rate * (1 + 1e-9))
      }
      if (!card.pays) expect(s.profit, `${card.good}: ${s.port} gains and the card says no gain`).toBeLessThanOrEqual(0)
    }
  }
  // a new company's purse binds the Max of some good at Lisbon (the case 0351 is for), and the card had other sales to be chosen from
  expect(atMax, 'no card is priced at a Max her purse, the stock or the day binds').toBeGreaterThan(0)
  expect(chosen, 'no such card had another sale within her purse').toBeGreaterThan(0)
})

test('from another city in hand (bought there, sailed to first) the card is still the board\'s row', async () => {
  test.setTimeout(300_000)
  const s = await sales(other.id)
  const purse = await purseNow()
  expect(s.port).toBe(other.code)
  expect(s.goods.length).toBeGreaterThan(0)
  const pairs = await cardsAgainstBoard(other.id)
  expect(pairs.length).toBe(s.goods.filter((g) => g.port !== null).length)
  for (const { card, row } of pairs) {
    expect(card.port).not.toBe(other.code)
    expect(row, `${card.good}: the board does not price ${card.port}`).not.toBeNull()
    expect(row!.profit).toBe(card.profit)
    expect(row!.units).toBe(card.units)
    // 0351: no tray Max where she does not lie — the units are what her hold takes, and only the sales her purse buys are named
    expect(card.cost, `${card.good} at ${card.port}: the buy is within her purse`).toBeLessThanOrEqual(purse)
  }
  for (const g of s.goods) {
    for (const k of KEYS_0351) expect(g, `${g.good}: 0351 serves ${k}`).toHaveProperty(k)
    if (g.short) expect(g.port, `${g.good}: short means no sale is named`).toBeNull()
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
  // 0351: the units are the tray's Max — the one cap authority, asked once a good; no walk, step or knob of its own
  expect(src.rows[0].best.split('public.fleet_buy_capacity(').length - 1).toBe(1)
  expect(src.rows[0].best).not.toContain('trade_step_tuns')
  expect(src.rows[0].best).not.toContain('wc_num(')
  expect(src.rows[0].best).toContain('public.credit_on(')
})

test('0351: the cap authority\'s bisect is its walk, on fixed cases (public.fleet_buy_capacity: the tray\'s Max, BUY ALL)', async () => {
  test.setTimeout(300_000)
  // THE WALK, from the migration's own hunks: the live body with hunks 5 and 4 put back to their OLD text (the file asserts that this
  // reversal is the body before it, byte for byte)
  const mig = readFileSync('supabase/migrations/20260818000351_a_best_sale_she_can_pay_for.sql', 'utf8').replace(/\r/g, '')
  const hunks = [...mig.matchAll(/\('public\.fleet_buy_capacity\(uuid,uuid\)', (\d),\n\$h\$([\s\S]*?)\$h\$,\n\$h\$([\s\S]*?)\$h\$\)/g)].map((m) => ({ n: Number(m[1]), old: m[2], new: m[3] }))
  expect(hunks.map((h) => h.n)).toEqual([4, 5])
  const live = (await db.pg.query<{ def: string }>(`select replace(pg_get_functiondef('public.fleet_buy_capacity(uuid,uuid)'::regprocedure), chr(13), '') as def`)).rows[0].def
  let walk = live
  for (const h of [...hunks].reverse()) {
    expect(walk.split(h.new).length - 1, `hunk ${h.n} is in the live body once`).toBe(1)
    walk = walk.replace(h.new, () => h.old)
  }
  expect(walk).toContain('exit when q.units > 0 and q.total <= v_purse;')
  expect(live).not.toContain('exit when q.units')
  expect(live.split('world.quote(').length - 1, 'the bisect quotes the limit, then inside its one loop').toBe(2)
  // both bodies with the same lines swapped, so a case can set what they read without a write: her purse, the stock and the day's cap
  // (only ever lowered), and the walk's step. With nothing set a copy reads what the real body reads.
  const swaps: [string, string][] = [
    [
      `  v_step    numeric := greatest(1, public.wc_num('trade_step_tuns'));\n`,
      `  v_step    numeric := greatest(1, coalesce(nullif(current_setting('spec.step', true), '')::numeric, public.wc_num('trade_step_tuns')));\n`,
    ],
    [
      `  select ducats into v_purse from public.players where id = f.player_id;\n`,
      `  select ducats into v_purse from public.players where id = f.player_id;\n  v_purse := coalesce(nullif(current_setting('spec.purse', true), '')::numeric, v_purse);\n`,
    ],
    [
      `  v_cap  := world.daily_cap_remaining(f.player_id, f.port_id, p_good);\n`,
      `  v_cap  := world.daily_cap_remaining(f.player_id, f.port_id, p_good);\n  v_stock := least(v_stock, coalesce(nullif(current_setting('spec.stock', true), '')::numeric, v_stock));\n  v_cap := least(v_cap, coalesce(nullif(current_setting('spec.cap', true), '')::numeric, v_cap));\n`,
    ],
  ]
  let bisect = live
  for (const [a, b] of swaps) {
    expect(walk.split(a).length - 1).toBe(1)
    expect(bisect.split(a).length - 1).toBe(1)
    walk = walk.replace(a, () => b)
    bisect = bisect.replace(a, () => b)
  }
  await db.pg.exec(walk.replace('FUNCTION public.fleet_buy_capacity(', 'FUNCTION pg_temp.cap_walk('))
  await db.pg.exec(bisect.replace('FUNCTION public.fleet_buy_capacity(', 'FUNCTION pg_temp.cap_bisect('))

  interface Cell { purse: string; stock: string; cap: string; step: string }
  const PURSES = ['0', '1', '500', '5000', '40000', '400000', '4000000']
  const cells: Cell[] = [{ purse: '', stock: '', cap: '', step: '' }]
  for (const purse of PURSES) cells.push({ purse, stock: '', cap: '', step: '' })
  for (const purse of ['500', '40000', '4000000']) {
    for (const [stock, cap] of [['7', ''], ['55', ''], ['', '3'], ['', '25'], ['12', '9']]) cells.push({ purse, stock, cap, step: '' })
  }
  for (const step of ['7', '2.5', '1', '25']) for (const stock of ['30', '3']) for (const purse of ['5000', '200', '40', '1']) cells.push({ purse, stock, cap: '', step })
  // a step of one tun over the whole hold: the search's start stands several places short of the answer, so its strides and its halving are both walked
  for (const purse of ['400000', '300000', '40000', '15000']) cells.push({ purse, stock: '', cap: '', step: '1' })
  // a purse of exactly what 20, 7 and 1 of a good cost: found down the walk, and as the limit itself (the stock set to that count)
  const edges = (
    await db.pg.query<{ total: string; n: number }>(
      `select q.total::text as total, n.n
         from (select gd.id from public.port_goods pg join public.goods gd on gd.id = pg.good_id
                where pg.port_id = $2 and public.port_offers($2, gd.id) and pg.stock >= 50 order by gd.code limit 3) g
        cross join (values (20), (7), (1)) n(n)
        cross join lateral world.quote($2, g.id, n.n, 'buy', null, $1) q`,
      [fleet, lisbon],
    )
  ).rows
  expect(edges.length).toBe(9)
  for (const e of edges) for (const stock of ['', String(e.n)]) cells.push({ purse: e.total, stock, cap: '', step: '' })

  let pairs = 0
  let exact = 0
  const bounds = new Set<string>()
  try {
    for (const c of cells) {
      await db.pg.query(`select set_config('spec.purse', $1, false), set_config('spec.stock', $2, false), set_config('spec.cap', $3, false), set_config('spec.step', $4, false)`, [c.purse, c.stock, c.cap, c.step])
      const rows = (
        await db.pg.query<{ code: string; walk: { max_qty: number; est_total: number; bound_by: string }; bisect: { max_qty: number; est_total: number; bound_by: string }; live: unknown }>(
          `select gd.code, pg_temp.cap_walk($1, gd.id) as walk, pg_temp.cap_bisect($1, gd.id) as bisect, public.fleet_buy_capacity($1, gd.id) as live
             from public.port_goods pg join public.goods gd on gd.id = pg.good_id
            where pg.port_id = $2 and public.port_offers($2, gd.id) order by gd.code`,
          [fleet, lisbon],
        )
      ).rows
      expect(rows.length).toBeGreaterThan(0)
      for (const r of rows) {
        expect(r.bisect, `${r.code}, purse ${c.purse || 'hers'}, stock ${c.stock || '-'}, cap ${c.cap || '-'}, step ${c.step || 'the knob'}: the bisect is not the walk`).toEqual(r.walk)
        if (c.purse === '' && c.stock === '' && c.cap === '' && c.step === '') expect(r.live, `${r.code}: with nothing set the copy is the real body`).toEqual(r.bisect)
        bounds.add(r.bisect.bound_by)
        if (c.purse !== '' && r.bisect.max_qty > 0 && Number(r.bisect.est_total) === Number(c.purse)) exact += 1
        pairs += 1
      }
    }
  } finally {
    await db.pg.query(`select set_config('spec.purse', '', false), set_config('spec.stock', '', false), set_config('spec.cap', '', false), set_config('spec.step', '', false)`)
  }
  // the cases are fixed: 1 + 7 + 15 + 32 + 4 + 18 cells over every good Lisbon sells; each limit bound somewhere; the edge was hit
  expect(cells.length).toBe(77)
  expect(pairs).toBe(77 * (await db.pg.query(`select 1 from public.port_goods pg where pg.port_id = $1 and public.port_offers($1, pg.good_id)`, [lisbon])).rows.length)
  for (const b of ['hold', 'purse', 'stock', 'daily cap']) expect([...bounds], `no case was bound by ${b}`).toContain(b)
  expect(exact, 'no case answered a count that costs her whole purse exactly').toBeGreaterThan(0)
  // who asks the cap authority: the tray's door, BUY ALL's count, a fleet lying at a quay on the routes read, and the best sales
  const callers = (
    await db.pg.query<{ fn: string }>(
      `select n.nspname || '.' || p.proname as fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%fleet_buy_capacity(%' and p.oid <> 'public.fleet_buy_capacity(uuid,uuid)'::regprocedure order by 1`,
    )
  ).rows.map((r) => r.fn)
  expect(callers).toEqual(['cmd.resolve_qty', 'world.best_sales', 'world.buy_capacity', 'world.trade_routes'])
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
