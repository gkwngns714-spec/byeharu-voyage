// measure.mjs <image> <out.json> — prod-shaped world (setup.mjs, no kickoff); every merchant's present loop and her lap-start candidates priced as npc_plan prices them
import { writeFileSync, readFileSync } from 'node:fs'
import { open, setup, log } from './setup.mjs'
const [image, outf] = process.argv.slice(2)
const db = await open(image, [])
const q = await setup(db, false)
if (process.env.NEWCAND) { await q(`insert into public.world_config (key, value, description) values ('npc_route_trade_candidates', to_jsonb(${Number(process.env.NEWCAND)}), 'sim') on conflict (key) do update set value = excluded.value`); await db.exec(readFileSync('C:/Users/gkwng/dev/bv-harness/redesign-scratch/new_npc_loop_candidates.sql', 'utf8')); log('new candidates', process.env.NEWCAND) }
for (const kv of (process.env.KNOBS ?? '').split(',').filter(Boolean)) { const [k, v] = kv.split('='); await q(`update public.world_config set value = to_jsonb(${Number(v)}) where key = '${k}'`); log('knob', k, v) }
await db.exec(readFileSync('C:/Users/gkwng/dev/bv-harness/redesign-scratch/priceloop.sql', 'utf8'))
const routes = await q(`select nf.route_id, nf.fleet_id, f.name, pl.company_name house, pl.ducats,
   (select jsonb_agg(jsonb_build_object('port_id', s.port_id, 'code', p.code) order by s.ord) from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = nf.route_id) loop
  from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = nf.player_id order by nf.roster_ord`)
log('routes', routes.length)
const out = []
const t0 = Date.now()
for (const r of routes) {
  const cur = (await q(`select pg_temp.price_loop($1, $2, $3::jsonb) j`, [r.route_id, r.fleet_id, JSON.stringify(r.loop)]))[0].j
  const cands = await q(`select c.kind, c.stops, pg_temp.price_loop($1, $2, c.stops) j from public.npc_loop_candidates($1, $2, ($3::jsonb->0->>'port_id')::uuid,
      (select coalesce(sum(public.ship_cargo_tuns(s.id)),0) + public.fleet_free_hold($2) from public.ships s where s.fleet_id = $2),
      greatest(coalesce(voyage.fleet_speed($2), 0), 0.1)) c`, [r.route_id, r.fleet_id, JSON.stringify(r.loop)])
  out.push({ name: r.name, house: r.house, ducats: Number(r.ducats), loop: r.loop.map((x) => x.code), cur,
    cands: cands.map((c) => ({ kind: c.kind, loop: c.stops.map((x) => x.code), ...c.j, legs: undefined })) })
  if (out.length % 100 === 0) log(out.length, Date.now() - t0, 'ms')
}
writeFileSync(outf, JSON.stringify(out))
const pay = (x) => x.net > 0
const n = out.length
const s = { n, cur_pays: out.filter((o) => pay(o.cur)).length, cur_any: out.filter((o) => o.cur.any).length,
  cur_any_not_pay: out.filter((o) => o.cur.any && !pay(o.cur)).length,
  some_cand_pays: out.filter((o) => pay(o.cur) || o.cands.some(pay)).length,
  none_pays: out.filter((o) => !pay(o.cur) && !o.cands.some(pay)).length,
  cands_total: out.reduce((a, o) => a + o.cands.length, 0), cands_pay: out.reduce((a, o) => a + o.cands.filter(pay).length, 0),
  far_total: out.reduce((a, o) => a + o.cands.filter((c) => c.kind === 'far').length, 0), far_pay: out.reduce((a, o) => a + o.cands.filter((c) => c.kind === 'far' && pay(c)).length, 0),
  ms: Date.now() - t0 }
log(JSON.stringify(s))
process.exit(0)
