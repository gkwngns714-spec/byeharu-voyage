// WHERE A LONG JOB'S TICK GOES (0499; local PGlite only, never prod; everything rolled back).
//   node scripts/ops/harness/fit-to-sail/profile-tick.mjs [--sea] [--wreck]
// The reported scene (prod, 24 Nov): one company, one fleet docked at Island of Mozambique, a land job whose party lives at Lisbon: the
// plan is seven SAILs, harbour by harbour. Prod's tick took 10,659 ms (its plan 3,055 ms). This times, on the chain's cached world with
// fleet_jobs_enabled, sea_courses_enabled, land_enabled and assign_home_enabled lit in this transaction:
//   the real tick (public.tick_fleet_jobs(false)) and its own receipt (plan_ms, open_ms);
//   the plan's parts, each asked alone: the course between two harbours (public.fleet_job_course), its miles
//     (voyage.segments_from_course), the leg judge (voyage.leg_refusal), the pathfinder (voyage.reach_passage), public.supply_reach;
//   the open's parts: cmd.parse, the reach gate (public.passage_gate) a SAIL, cmd.issue_lines whole.
//   --sea    sea_conditions_bite lit too (the gate then judges every zone of the course: public.sea_gate)
//   --cold   every cached plan is thrown away before each tick (DISCARD PLANS), as in the new session pg_cron opens for every run
//   --wreck  her flagship's hull at 0 (the reported fleet): what the tick does with a fleet that cannot sail
// NOT MEASURED HERE: production (PG 17, its plans, its disk, its other sessions). PGlite is one WASM Postgres 18 with everything in memory.
import { world } from '../hq-figures/q.mjs'

const SEA = process.argv.includes('--sea')
const WRECK = process.argv.includes('--wreck')
const COLD = process.argv.includes('--cold')
const db = await world()
const one = async (s, p = []) => (await db.query(s, p)).rows[0]
const timed = async (label, s, p = [], n = 1) => {
  const t = performance.now()
  let r
  for (let i = 0; i < n; i += 1) r = await one(s, p)
  const ms = (performance.now() - t) / n
  console.log(`${label.padEnd(58)} ${ms.toFixed(1).padStart(9)} ms${n > 1 ? `  (mean of ${n})` : ''}`)
  return r
}

await db.exec('begin')
await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled'${SEA ? `, 'sea_conditions_bite'` : ''})`)
const auth = '00000000-0499-4000-8000-0000000000f1'
const a = (await one(`select public.new_house($1, 'Casa do Reparo 499', 'PRT') as id`, [auth])).id
const f = (await one(`select f.id from public.fleets f where f.player_id = $1`, [a])).id
await db.query(`update public.players set ducats = 5000000 where id = $1`, [a])
await db.query(`select cmd.assume_identity($1)`, [auth])
await db.query(`select public.land_party($1)`, [a])
const isl = (await one(`select id from public.ports where code = 'ISL'`)).id
const lis = (await one(`select id from public.ports where code = 'LIS'`)).id
await db.query(`update public.fleets set port_id = $2, status = 'DOCKED', ready_at = null where id = $1`, [f, isl])
if (WRECK) await db.query(`update public.ships set durability = 0 where fleet_id = $1`, [f])
await db.query(`insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at) values ($1, $2, 'land', '{"to": "CAD"}'::jsonb, now(), now())`, [f, a])
console.log(`scene: land job, her fleet at ISL, the party at LIS${SEA ? '; sea conditions lit' : ''}${WRECK ? '; her flagship wrecked' : ''}`)

// the parts, asked alone (reads; nothing is written)
await db.exec('savepoint parts')
const plan = (await timed('public.fleet_job_plan (the whole plan)', `select public.fleet_job_plan($1) as r`, [f])).r
await timed('public.fleet_job_plan, again (warm)', `select public.fleet_job_plan($1) as r`, [f], 3)
const lines = plan.lines ?? []
console.log(`  plan: ${lines.length ? lines.map((l) => l.text).join(' / ') : JSON.stringify(plan)}`)
const direct = (await timed('public.fleet_job_course ISL -> LIS (the direct course)', `select public.fleet_job_course($1, $2, $3) as c`, [f, isl, lis])).c
await timed('voyage.segments_from_course of it (its miles)', `select sum((s->>'nm')::numeric) as nm from jsonb_array_elements(voyage.segments_from_course($1::jsonb)) s`, [JSON.stringify(direct)])
await timed('voyage.leg_refusal of it (the leg judge)', `select voyage.leg_refusal($1, $2, 7052, $3::jsonb) as r`, [f, lis, JSON.stringify(direct)])
await timed('public.supply_reach', `select cap_nm from public.supply_reach($1)`, [f], 3)
await timed('voyage.reach_passage (the pathfinder, all harbours)', `select count(*) as n from voyage.reach_passage($1, $2, $3, (select sr.cap_nm from public.supply_reach($2) sr))`, [a, f, isl], 3)
await timed('public.fleet_job_legs ISL -> LIS (course, judge, chain)', `select public.fleet_job_legs($1, $2, $3) as r`, [f, isl, lis], 3)
let at = isl
let k = 0
for (const l of lines.filter((x) => x.text.startsWith('SAIL '))) {
  k += 1
  const to = (await one(`select id from public.ports where code = $1 and kind = 'HARBOUR'`, [l.text.slice(5)])).id
  await timed(`  leg ${k} ${l.text}: its course`, `select public.fleet_job_course($1, $2, $3) as c`, [f, at, to])
  await timed(`  leg ${k} ${l.text}: its judge (leg_shut)`, `select public.fleet_job_leg_shut($1, $2, $3::jsonb) as r`, [f, to, JSON.stringify(l.path)])
  await timed(`  leg ${k} ${l.text}: cmd.parse`, `select cmd.parse($1, $2, $3) as r`, [a, f, l.text])
  await timed(`  leg ${k} ${l.text}: the reach gate (passage_gate)`, `select public.passage_gate($1, $2, (select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course($4::jsonb)) s), $3, $4::jsonb) as r`, [a, f, to, JSON.stringify(l.path)])
  at = to
}
if (lines.length) {
  await db.exec('savepoint issue')
  const r = (await timed('cmd.issue_lines (parse, gates, queue, the first SAIL)', `select cmd.issue_lines($1, $2::jsonb, $3) as r`, [f, JSON.stringify(lines), plan.version])).r
  console.log(`  issue: ok ${r.ok}${r.ok ? '' : ` ${r.error_code} ${r.error_message}`}; orders ${(r.orders ?? []).map((o) => `${o.text}:${o.status}${o.error_code ? `:${o.error_code}` : ''}`).join(', ')}`)
  await db.exec('rollback to savepoint issue')
}
await db.exec('rollback to savepoint parts')

// the real tick, twice (the second finds her sailing, or stopped, or waiting)
for (const pass of [1, 2]) {
  if (COLD) await db.exec('discard plans')
  const t = performance.now()
  await db.exec(`call public.tick_fleet_jobs(false)`)
  const ms = performance.now() - t
  const rc = (await one(`select r.ms, r.receipt from public.fleet_job_runs r order by r.at desc limit 1`))
  const j = await one(`select j.runs, j.paused_reason, j.next_at > now() as waits, j.last from public.fleet_jobs j where j.fleet_id = $1`, [f])
  const st = await one(`select f.status, (select count(*) from public.orders o where o.fleet_id = f.id) as orders, (select count(*) from public.orders o where o.fleet_id = f.id and o.status = 'failed') as failed from public.fleets f where f.id = $1`, [f])
  console.log(`tick ${pass}: ${ms.toFixed(0)} ms by the clock; receipt ${JSON.stringify(rc?.receipt?.steps ?? [])} started ${rc?.receipt?.started} waited ${rc?.receipt?.waited} stopped ${rc?.receipt?.stopped}`)
  console.log(`  job: runs ${j.runs}, stopped on ${j.paused_reason}, waits ${j.waits}, last ${JSON.stringify(j.last)}; fleet ${st.status}, orders ${st.orders} (failed ${st.failed})`)
}
await db.exec('rollback')
await db.close()
process.exit(0)
