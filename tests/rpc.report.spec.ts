// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REPORT READS THE LEDGER — world.report (0278, docs/COMMAND_REDESIGN.md §4, R4; owner row 192)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The Report face's one read, through the client wrapper, as a company founded at Lisbon: a hire, a provision,
// a buy, a sail and a sell through the REAL verbs (the same path the migration's self-assert drives, re-read
// here at the wrapper level): the total is the purse's change; the section sums equal the total and the place
// sums equal the section sums; every kind sits under the design's section (Trade / Crew / Supplies / Other)
// with the ledger's own sum; the places read the port, the voyage and "Earlier"; day ⊂ week ⊂ all. The spec
// names report and books so CI's rule S selects it.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldReport } from '../src/lib/rpc'

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Report Spec', 'PRT') as result`)
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

const purse = () => db.callAs<number>(`select ducats::bigint as result from public.players where id = public.current_player_id()`)

const FLEET = `(select f.id from public.fleets f where f.player_id = public.current_player_id())`
/** One good Lisbon offers, with stock, the probe's culture accepts (0224's pick, ordered). */
const GOOD = `(select pg.good_id from public.port_goods pg
                join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
               where p.code = 'LIS' and pg.stock > 0 and not public.culture_refuses(p.culture, g.culture_mask)
                 and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)
               order by g.code limit 1)`

test('a hire, a provision, a buy, a sail and a sell: sections and places add up, day ⊂ week ⊂ all', async () => {
  const before = await worldReport('all')
  expect(before.ok).toBe(true)
  const p0 = Number(await purse())

  // THE REAL VERBS, in a player's order (the migration's self-assert drives the same path)
  await db.callAs(`select cmd.do_hire(${FLEET}, jsonb_build_object('count',
    (select c.crew_max from public.ship_classes c join public.ships s on s.class_id = c.id
      where s.fleet_id = ${FLEET} order by s.id limit 1)))::text as result`)
  await db.callAs(`select cmd.do_provision(${FLEET}, '{"mode": "FULL"}')::text as result`)
  await db.callAs(`select cmd.do_buy(${FLEET}, jsonb_build_object('good', ${GOOD}, 'qty', 1))::text as result`)
  // SAIL to the nearest harbour that offers the good and takes its culture — the straight line is the
  // server's to verify, so a refused candidate is tried against the next (the migration's own rule).
  await db.callAs(`do $$
    declare
      v_f uuid := ${FLEET}; v_g uuid := ${GOOD}; r record; f_sailed boolean := false;
    begin
      for r in
        select p.id as pid
          from public.sea_reaches sr join public.ports p on sr.reaches ? p.code
         where sr.port_id = (select port_id from public.fleets where player_id = public.current_player_id())
           and p.kind = 'HARBOUR' and p.id <> (select port_id from public.fleets where player_id = public.current_player_id())
           and exists (select 1 from public.port_goods pg2 where pg2.port_id = p.id and pg2.good_id = v_g)
           and not public.culture_refuses(p.culture, (select g2.culture_mask from public.goods g2 where g2.id = v_g))
           and exists (select 1 from public.port_offered_goods(p.id) o where o.good_id = v_g)
         order by (sr.reaches->>p.code)::numeric asc limit 3
      loop
        begin
          perform cmd.do_sail(v_f, jsonb_build_object('dest', r.pid));
          f_sailed := true;
          exit;
        exception when others then
          null;
        end;
      end loop;
      if not f_sailed then
        raise exception 'no near harbour sails from Lisbon for the probe good';
      end if;
    end $$`)
  await db.callAs(`update public.voyages v set status = 'ARRIVED', eta = now() - interval '1 day'
                    where v.fleet_id = ${FLEET} and v.status = 'SAILING'`)
  // she docks where the voyage she is on sailed to — never a second guess of the destination
  await db.callAs(`update public.fleets f set status = 'DOCKED', port_id = v.dest_port_id
                     from public.voyages v
                    where v.fleet_id = f.id and v.status = 'ARRIVED' and f.id = ${FLEET}`)
  await db.callAs(`select cmd.do_sell(${FLEET}, jsonb_build_object('good', ${GOOD}, 'qty', 1))::text as result`)

  // an old row's shape, 8 game days back (no event, delta 0): proves day ⊂ week ⊂ all and reads "Earlier"
  await db.callAs(`insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at)
                   values (public.current_player_id(), 'PROBE_0278', 0,
                           (select ducats from public.players where id = public.current_player_id()),
                           null, now() - make_interval(secs => (8 * public.wc_num('game_day_seconds'))::double precision))`)

  const all = await worldReport('all')
  const week = await worldReport('week')
  const day = await worldReport('day')
  expect(all.ok).toBe(true)
  expect(week.ok).toBe(true)
  expect(day.ok).toBe(true)
  if (!all.ok || !week.ok || !day.ok) return

  const p1 = Number(await purse())
  const founding = Number(
    await db.callAs<number>(`select coalesce(sum(ducats_delta), 0)::bigint as result from public.ledger
                              where player_id = public.current_player_id() and kind = 'FOUNDING'`),
  )

  // the total is the purse's change since the founding (capital excluded, everything else in)
  expect(all.value.total).toBe(p1 - p0)
  expect(all.value.total).toBe(p1 - founding)

  // the section sums equal the total, the place sums equal the section sums
  const secs = all.value.sections.reduce((s, x) => s + x.ducats, 0)
  const places = all.value.places.reduce((s, x) => s + x.ducats, 0)
  expect(secs).toBe(all.value.total)
  expect(places).toBe(all.value.total)

  // every kind sits exactly once, under the design's section, with the ledger's own sum
  const kindsJson = await db.callAs<string>(`select jsonb_agg(jsonb_build_object('kind', k.kind, 'sum', k.s))::text as result
    from (select l.kind, sum(l.ducats_delta)::bigint as s
            from public.ledger l where l.player_id = public.current_player_id() and l.kind <> 'FOUNDING'
           group by l.kind order by l.kind) k`)
  const parsed: { kind: string; sum: number }[] = kindsJson ? JSON.parse(kindsJson) : []
  const lines = all.value.sections.flatMap((s) => s.lines.map((l) => ({ ...l, section: s.id })))
  expect(lines.length).toBe(parsed.length)
  for (const k of parsed) {
    const line = lines.find((l) => l.kind === k.kind)
    expect(line, `${k.kind} is missing from the sections`).toBeTruthy()
    expect(line!.ducats).toBe(Number(k.sum))
    const expected = ['SELL', 'BUY', 'TAX'].includes(k.kind)
      ? 'trade'
      : ['WAGES', 'HIRE'].includes(k.kind)
        ? 'crew'
        : k.kind === 'PROVISION'
          ? 'supplies'
          : 'other'
    expect(line!.section, `${k.kind} sits under the wrong section`).toBe(expected)
  }
  expect(lines.some((l) => l.kind === 'FOUNDING'), 'the founding capital reads as a line').toBe(false)

  // the places: the port she traded from, the voyage she sold on, and "Earlier" for the nameless rows
  const lis = all.value.places.find((p) => p.kind === 'port' && p.code === 'LIS')
  expect(lis).toBeTruthy()
  const voy = all.value.places.find((p) => p.kind === 'voyage')
  expect(voy).toBeTruthy()
  expect(voy && voy.kind === 'voyage' && voy.from === 'LIS').toBe(true)
  const earlier = all.value.places.find((p) => p.kind === 'earlier')
  expect(earlier).toBeTruthy()

  // day ⊂ week ⊂ all: one day, seven days, and the backdated row's day — and the totals agree
  expect(day.value.days.length).toBe(1)
  expect(week.value.days.length).toBe(7)
  expect(all.value.days.length).toBe(9)
  const today = day.value.days[0].game_day
  expect(week.value.days[0].game_day).toBe(today - 6)
  expect(week.value.days[6].game_day).toBe(today)
  expect(all.value.days[0].game_day).toBe(today - 8)
  expect(all.value.days[8].game_day).toBe(today)
  expect(day.value.total).toBe(week.value.total)
  expect(week.value.total).toBe(all.value.total)
})
