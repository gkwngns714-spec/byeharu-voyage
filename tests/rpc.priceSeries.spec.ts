// PURE UNIT SPEC — 0226, A PRICE IS KEPT FOR YEARS, BOTH WAYS (owner rows 189 and 205), against the real
// chain in PGlite through the backend the app installs in local mode. No browser.
//
// WHAT IT PINS, from the client's side of the wire (the migration's self-assert pins the server's):
//   · the snapshot job records BOTH sides of a sold pair, equal to world.price's to the cent, and the bid
//     alone of a pair the city does not sell — once it has been asked for;
//   · `worldPriceSeries` serves a pair the record does not keep as `recording: false` with no points, and
//     the local backend's store presses it into the record (`cmdWatchPrice`) so the next tick starts it;
//   · every span answers from its own tier with the step the client labels its axis by, and the payload's
//     shape is what src/lib/rpc/types.ts claims (ask null where the city does not sell the good);
//   · the registry carries the new read and the new press and not the dropped one.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { PRICE_SPANS, clearBackend, cmdWatchPrice, createLocalBackend, setBackend, worldPriceSeries } from '../src/lib/rpc'

let db: LocalDb
let port: string
let sold: string
let unsold: string

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Casa das Series', 'PRT') as result`)
  const subject = await db.callAs<{ port: string; sold: string; unsold: string }>(
    `select jsonb_build_object(
        'port', p.id,
        'sold', (select g.id from public.goods g join public.port_offered_goods(p.id) o on o.good_id = g.id order by g.code limit 1),
        'unsold', (select g.id from public.goods g join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id
                    where not public.port_offers(p.id, g.id) order by g.code limit 1)) as result
       from public.ports p
      where p.kind = 'HARBOUR' and exists (select 1 from public.port_offered_goods(p.id))
      order by p.code limit 1`,
  )
  port = subject.port
  sold = subject.sold
  unsold = subject.unsold
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('a sold pair is recorded on both sides, equal to the one price authority to the cent', async () => {
  // the local backend runs the snapshot job before the first series read, so the present slot is written
  const r = await worldPriceSeries(port, sold, '1d')
  expect(r.ok).toBe(true)
  if (!r.ok) return
  expect(r.value.tier).toBe('fine')
  expect(r.value.offered).toBe(true)
  expect(r.value.recording).toBe(true)
  expect(r.value.points.length).toBeGreaterThanOrEqual(1)
  const last = r.value.points[r.value.points.length - 1]
  const price = await db.callAs<{ ask: number; bid: number }>(
    `select jsonb_build_object('ask', p.ask, 'bid', p.bid) as result from world.price('${port}', '${sold}') p`,
  )
  expect(last.ask).toBe(price.ask)
  expect(last.bid).toBe(price.bid)
  expect(typeof last.stock).toBe('number')
  expect(r.value.step_seconds).toBe(await db.callAs<number>(`select public.wc_int('drift_slot_seconds') as result`))
})

test('a pair the city does not sell is not recorded until asked for; the ask keeps its bid alone from the next tick', async () => {
  const before = await worldPriceSeries(port, unsold, '1d')
  expect(before.ok).toBe(true)
  if (!before.ok) return
  expect(before.value.offered).toBe(false)
  expect(before.value.recording).toBe(false)
  expect(before.value.points).toEqual([])

  const press = await cmdWatchPrice(port, unsold)
  expect(press.ok).toBe(true)
  if (!press.ok) return
  expect(press.value.watched).toBe(true)
  expect(press.value.recording).toBe(true)
  // a second press is the same answer, and a sold pair is never watched
  const again = await cmdWatchPrice(port, unsold)
  expect(again.ok && again.value.watched).toBe(true)
  const soldPress = await cmdWatchPrice(port, sold)
  expect(soldPress.ok && !soldPress.value.watched && soldPress.value.recording).toBe(true)

  // the next slot's run records it — the job itself, at the next slot
  await db.callAs(`select public.tick_price_snapshot(now() + make_interval(secs => public.wc_num('drift_slot_seconds')::double precision))::text as result`)
  const after = await worldPriceSeries(port, unsold, '1d')
  expect(after.ok).toBe(true)
  if (!after.ok) return
  expect(after.value.recording).toBe(true)
  expect(after.value.points.length).toBeGreaterThanOrEqual(1)
  const last = after.value.points[after.value.points.length - 1]
  expect(last.ask).toBeNull()
  // (a bare numeric comes back as text from PGlite; jsonb carries the number)
  const bid = await db.callAs<number>(`select to_jsonb(p.bid) as result from world.price('${port}', '${unsold}') p`)
  expect(last.bid).toBe(bid)
})

test('every span answers from its tier, oldest first, in the shape the types claim; a bad span is refused', async () => {
  // plant two finished hours of yesterday for the sold pair and fold them, exactly as the job would.
  // The base is a fixed hour of YESTERDAY'S UTC day (10:00), never "now minus 26 h": that slid across UTC
  // midnight between 00:00 and 02:00 UTC and split the eight rows over two days (day bucket 13, not 17).
  // The pair's FOLDED record starts empty, so the planted hours are its oldest and its day is theirs alone: the
  // world image carries the fine rows of the moment it was built, and the first read's job folded them into an
  // hour and a day. On the UTC day after an image was built those rows lie on "yesterday" too, earlier than
  // 10:00 — the 1w series then opened on the image's hour (bid 46.53, not 13) and the day was not the planted
  // one (CI run 40449328997, 04:31 UTC, image built 00:04 UTC the day before).
  await db.callAs(`with h as (delete from public.price_history_hour where port_id = '${port}' and good_id = '${sold}' returning 1),
                        d as (delete from public.price_history_day where port_id = '${port}' and good_id = '${sold}' returning 1)
                   select ((select count(*) from h) + (select count(*) from d))::int as result`)
  await db.callAs(`with ins as (
    insert into public.price_history (port_id, good_id, slot, at, mid, stock, ask, bid)
    select '${port}', '${sold}', public.drift_slot_of(h), h, 10, 0, 20 + i, 10 + i
      from generate_series(0, 7) i cross join lateral (select (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') - interval '14 hours' + make_interval(mins => 15 * i) as h) t
    on conflict do nothing returning 1)
    select count(*)::int as result from ins`)
  await db.callAs(`update public.price_rollup set hour_done = (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') - interval '14 hours', day_done = (((date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') - interval '14 hours') at time zone 'UTC')::date returning 1 as result`)
  await db.callAs(`select public.tick_price_snapshot(now() + make_interval(secs => 2 * public.wc_num('drift_slot_seconds')::double precision))::text as result`)

  const tiers: Record<string, string> = { '1d': 'fine', '1w': 'hour', '1m': 'hour', '1y': 'day', all: 'day' }
  for (const span of PRICE_SPANS) {
    const r = await worldPriceSeries(port, sold, span)
    expect(r.ok, span).toBe(true)
    if (!r.ok) continue
    expect(r.value.span).toBe(span)
    expect(r.value.tier).toBe(tiers[span])
    expect(r.value.points.length, span).toBeGreaterThanOrEqual(1)
    const ats = r.value.points.map((p) => Date.parse(p.at))
    expect(ats.every((t, i) => Number.isFinite(t) && (i === 0 || t > ats[i - 1]))).toBe(true)
    for (const p of r.value.points) {
      expect(typeof p.bid).toBe('number')
      expect(p.ask === null || typeof p.ask === 'number').toBe(true)
    }
    if (tiers[span] === 'hour') {
      expect(r.value.step_seconds).toBe(3600)
      const first = r.value.points[0]
      expect([first.bid_lo, first.bid, first.bid_hi]).toEqual([10, 13, 13])
      expect([first.ask_lo, first.ask, first.ask_hi]).toEqual([20, 23, 23])
    }
    if (tiers[span] === 'day') {
      expect(r.value.step_seconds).toBe(86_400)
      const first = r.value.points[0]
      expect([first.bid_lo, first.bid, first.bid_hi]).toEqual([10, 17, 17])
    }
  }
  const bad = await db.callAs<string>(`select coalesce((select world.price_series('${port}', '${sold}', '2w')::text), '') as result`).catch((e: Error) => e.message)
  expect(String(bad)).toContain('E_BAD_SPAN')
})

test('the registry carries price_series and watch_price for authenticated, and price_history is gone', async () => {
  const names = await db.callAs<string[]>(`select jsonb_agg(function_name) as result from public.client_rpc_entry_points()`)
  expect(names).toContain('price_series')
  expect(names).toContain('watch_price')
  expect(names).not.toContain('price_history')
  expect(
    await db.callAs<boolean>(`select has_function_privilege('anon', 'world.price_series(uuid, uuid, text)', 'execute') as result`),
  ).toBe(false)
})
