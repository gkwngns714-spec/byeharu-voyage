// sim.mjs <image> <minutes> <out.json> [migration...] — the prod-shaped merchant world (setup.mjs: prod's knobs,
// stocks, merchant and city purses, treasuries and loops, every merchant docked at her stop 0 at a lap start),
// the kickoff, then REAL time: the arrivals sweep every 15 s, the market drift every 10 min, the hourly
// reconcile at +20 and +45 min. Reports the laps that closed (≤ 0 share), lay-ups over time, the money,
// stranded merchants, Comptoir Chastellain's laps, and every sweep's and reconcile's wall-clock.
import { writeFileSync } from 'node:fs'
import { open, setup, log, shapeSql } from './setup.mjs'
const [image, mins, outf, ...migs] = process.argv.slice(2)
const db = await open(image, migs)
const q = await setup(db, false)
const money = async () => (await q(`select json_build_object(
  'merchants', (select sum(pl.ducats) + coalesce(sum((select sum(public.fleet_stock_at_cost(nf.fleet_id)) from public.npc_fleets nf where nf.player_id = pl.id)), 0) from public.players pl where pl.is_npc),
  'cities', (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)) j`))[0].j
const m0 = await money()
const t0iso = (await q(`select now()::text t`))[0].t
let k0 = Date.now()
const kick = await q(`select count(cmd.advance(nf.fleet_id, now())) n from public.npc_fleets nf`)
const kickMs = Date.now() - k0
log('kickoff', kick[0].n, 'in', kickMs, 'ms', JSON.stringify((await q(shapeSql))[0].j))
const T0 = Date.now(), end = T0 + Number(mins) * 60_000
const sweeps = [], recs = [], laid = [], recTend = []
const recAt = (process.env.RECAT ?? '20,45').split(',').map((m) => T0 + Number(m) * 60_000)
let nextDrift = T0 + 600_000, ri = 0
while (Date.now() < end) {
  const s0 = Date.now()
  await q(`select public.tick_arrivals(now())`)
  sweeps.push(Date.now() - s0)
  if (Date.now() >= nextDrift) { const d0 = Date.now(); await db.exec(`call public.tick_market_drift_each_port()`); log('drift', Date.now() - d0, 'ms'); nextDrift += 600_000 }
  if (ri < recAt.length && Date.now() >= recAt[ri]) {
    const notes = []; const r0 = Date.now(); await db.exec(`call public.tick_reconcile()`, { onNotice: (n) => notes.push(n.message) }); recs.push(Date.now() - r0)
    const rc = notes.find((n) => n.startsWith('tick_reconcile:')); let tend = null
    try { tend = JSON.parse(rc.slice('tick_reconcile: '.length)).merchant_upkeep?.tend ?? null; if (tend) delete tend.notes } catch {}
    recTend.push(tend); log('reconcile', recs.at(-1), 'ms', JSON.stringify(tend)); ri++
  }
  if (sweeps.length % 20 === 0) {
    const sh = (await q(shapeSql))[0].j; laid.push({ min: Math.round((Date.now() - T0) / 60000), laid_up: sh.paused?.laid_up ?? 0, sailing: sh.sailing })
    const w = sweeps.slice(-20); log('sweeps', sweeps.length, 'last20 avg', Math.round(w.reduce((a, b) => a + b, 0) / w.length), JSON.stringify(sh))
  }
  const wait = 15_000 - (Date.now() - s0)
  if (wait > 0) await new Promise((r) => setTimeout(r, wait))
}
const laps = (await q(`
  with l as (select lp.*, pl.company_name from public.standing_route_laps lp join public.npc_fleets nf on nf.route_id = lp.route_id
              join public.players pl on pl.id = nf.player_id
             where lp.closed_at is not null and lp.started_at >= $1::timestamptz)
  select json_build_object('n', count(*), 'le0', count(*) filter (where net <= 0), 'no_buy', count(*) filter (where bought = 0),
    'empty', count(*) filter (where bought = 0 and sold = 0), 'sum_net', sum(net), 'median_net', percentile_cont(0.5) within group (order by net),
    'chastellain', (select json_agg(json_build_array(l2.lap_no, l2.net, l2.bought, l2.sold)) from l l2 where l2.company_name = 'Comptoir Chastellain'),
    'by_nm', (select json_object_agg(b, json_build_array(n, le0)) from (select case when nm < 2000 then 0 when nm < 4000 then 2000 when nm < 8000 then 4000 else 8000 end b, count(*) n, count(*) filter (where net <= 0) le0
               from (select l3.net, (select sum(s.course_nm) from public.standing_route_stops s where s.route_id = l3.route_id) nm from l l3) z group by 1) y),
    'le0_sold0', (select count(*) from l l4 where l4.net <= 0 and l4.sold = 0),
    'le0_bought0_sold0', (select count(*) from l l4 where l4.net <= 0 and l4.sold = 0 and l4.bought = 0),
    'le0_traded', (select count(*) from l l4 where l4.net <= 0 and l4.sold > 0),
    'laps_by_lapstops', (select json_object_agg(k, json_build_array(n, le0)) from (select jsonb_array_length(coalesce(l6.trades, '[]'::jsonb)) k, count(*) n, count(*) filter (where l6.net <= 0) le0 from l l6 group by 1) z),
    'le0_sample', (select json_agg(json_build_array(l7.net, l7.bought, l7.sold, l7.supplies, l7.wages, l7.taxes, l7.trades, l7.skipped)) from (select * from l where net <= 0 and sold > 0 order by random() limit 8) l7),
    'last_half', (select json_build_array(count(*), count(*) filter (where l8.net <= 0)) from l l8 where l8.closed_at > now() - make_interval(mins => ${Math.round(Number(mins) / 2)})),
    'refusals', (select json_object_agg(k, c) from (select e->>'verb' || ' ' || (e->>'code') k, count(*) c from l l5, jsonb_array_elements(l5.skipped) e group by 1) z)) j from l`, [t0iso]))[0].j
const routes = (await q(`
  with r as (select nf.route_id, coalesce((select sum(lp.net) from public.standing_route_laps lp where lp.route_id = nf.route_id and lp.closed_at is not null and lp.started_at >= $1::timestamptz), 0) s,
                    (select count(*) from public.standing_route_laps lp where lp.route_id = nf.route_id and lp.closed_at is not null and lp.started_at >= $1::timestamptz) n
               from public.npc_fleets nf)
  select json_build_object('with_laps', count(*) filter (where n > 0), 'sum_le0', count(*) filter (where n > 0 and s <= 0)) j from r`, [t0iso]))[0].j
const stranded = (await q(`select json_build_object(
  'error', (select count(*) from public.standing_routes sr join public.npc_fleets nf on nf.route_id = sr.id where sr.paused_reason = 'error'),
  'docked_idle', (select count(*) from public.fleets f join public.npc_fleets nf on nf.fleet_id = f.id join public.standing_routes sr on sr.id = nf.route_id
                   where f.status = 'DOCKED' and sr.lap_id is null and sr.paused_reason is null and sr.hold_until is null),
  'anchored', (select count(*) from public.fleets f join public.npc_fleets nf on nf.fleet_id = f.id where f.status not in ('DOCKED', 'SAILING')),
  'failed_orders', (select count(*) from public.orders o join public.npc_fleets nf on nf.fleet_id = o.fleet_id where o.status = 'failed'),
  'chastellain', (select json_agg(json_build_object('stops', (select string_agg(p.code, '-' order by s.ord) from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = sr.id), 'reason', sr.paused_reason, 'status', f.status))
                    from public.npc_fleets nf join public.players pl on pl.id = nf.player_id and pl.company_name = 'Comptoir Chastellain'
                    join public.standing_routes sr on sr.id = nf.route_id join public.fleets f on f.id = nf.fleet_id)) j`))[0].j
const m1 = await money()
const st = (xs) => { const s = xs.slice().sort((a, b) => a - b); return { n: xs.length, avg: Math.round(xs.reduce((a, b) => a + b, 0) / xs.length), p95: s[Math.floor(s.length * 0.95)], max: s.at(-1) } }
const out = { migs, mins: Number(mins), kick_ms: kickMs, sweeps: st(sweeps), sweeps_after_10: st(sweeps.slice(40)), reconcile_ms: recs, reconcile_tend: recTend, laps, routes, stranded,
  money: { merchants: Number(m1.merchants) - Number(m0.merchants), cities: Number(m1.cities) - Number(m0.cities) }, laid, end: (await q(shapeSql))[0].j }
writeFileSync(outf, JSON.stringify(out, null, 1))
log(JSON.stringify({ ...out, laid: undefined }))
process.exit(0)
