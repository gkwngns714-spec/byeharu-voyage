// prof.mjs <image> <n> [migration...] — prod-shaped world; the first n merchants (roster order), each at her lap start, planned
// alone (public.npc_plan): the time of the candidates alone and of the whole plan, and what was written.
import { readFileSync } from 'node:fs'
import { open, setup, log } from './setup.mjs'
const [image, n, ...migs] = process.argv.slice(2)
const db = await open(image, migs)
const q = await setup(db, false)
for (const kv of (process.env.KNOBS ?? '').split(',').filter(Boolean)) { const [k, v] = kv.split('='); await q(`update public.world_config set value = to_jsonb(${Number(v)}) where key = '${k}'`); log('knob', k, v) }
if (process.env.CAND) { await db.exec(readFileSync(process.env.CAND, 'utf8')); log('candidates from', process.env.CAND) }
const rs = await q(`select nf.fleet_id, nf.route_id from public.npc_fleets nf order by nf.roster_ord limit ${Number(n)}`)
let tc = 0, tp = 0, nc = 0, laid = 0
for (const r of rs) {
  const c0 = Date.now()
  const c = await q(`select count(*)::int n from public.npc_loop_candidates($2, $1, (select s.port_id from public.standing_route_stops s where s.route_id = $2 and s.ord = 0),
     (select coalesce(sum(public.ship_cargo_tuns(s.id)),0) + public.fleet_free_hold($1) from public.ships s where s.fleet_id = $1), greatest(coalesce(voyage.fleet_speed($1), 0), 0.1))`, [r.fleet_id, r.route_id])
  tc += Date.now() - c0; nc += c[0].n
  const p0 = Date.now()
  const p = (await q(`select public.npc_plan(now(), $1) j`, [r.route_id]))[0].j
  tp += Date.now() - p0
  laid += Number(p.waiting ?? 0)
}
log(JSON.stringify({ n: rs.length, cand_ms_each: Math.round(tc / rs.length), cands_each: +(nc / rs.length).toFixed(1), plan_ms_each: Math.round(tp / rs.length), waiting: laid }))
process.exit(0)
