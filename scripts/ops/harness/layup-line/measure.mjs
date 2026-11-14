// measure.mjs: THE WAITING-ASKS JOB FOR ONE REAL MINUTE, with N merchants staged laid up and due. LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/layup-line/measure.mjs [--n=200] [--budget=20000] [--fixture]
//
// Restores the cached world at the head before 0405 (never from zero; the cache is only read), applies 0405, lights the merchants, lays N of those in
// port at their first stop up by hand with their last ask an hour or more back, and CALLS public.tick_waiting_asks() as pg_cron calls it: with its
// commits, from the start of a clock minute to :57. There is no beat in this world, so public.arrivals_beats is filled with a row a second dated
// ahead: the open step then finds its gap as it does on prod once the second's beat has committed. Prints the minute's receipt, the line before
// and after, and what the budget holds at the measured cost. --fixture installs the proofs' market (prices that pay) first. The world is thrown away.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const N = Number(arg('n') ?? 200)
const NAME = '20260818000405'
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) mine = name
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
console.log(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
if (process.argv.includes('--fixture')) {
  await (await import('../../../db/proof-courses.mjs')).installProofCourses(db)
  await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
}
await db.exec((await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', ''))
await db.exec(`
update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
update public.world_config set value = to_jsonb(${Number(arg('budget') ?? 20000)}) where key = 'npc_ask_job_ms';
update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null, hold_until = null from public.npc_fleets nf where nf.route_id = sr.id;
create table public.ll_measure as
select ro.fleet_id, ro.route_id, row_number() over (order by ro.k) as i
  from public.npc_tend_roster() ro
  join public.fleets f on f.id = ro.fleet_id and f.status = 'DOCKED'
  join public.standing_routes sr on sr.id = ro.route_id and sr.fleet_id = ro.fleet_id
  join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
 where ro.k <= public.wc_int('npc_fleet_max')
 order by ro.k limit ${N};
update public.standing_routes sr set paused_reason = 'laid_up', updated_at = now() - make_interval(mins => 60 + (l.i % 60)::int) from public.ll_measure l where l.route_id = sr.id;
update public.npc_fleets nf set asked_at = null from public.ll_measure l where l.fleet_id = nf.fleet_id;
insert into public.arrivals_beats (slot, at, ms) select g, now() + interval '1 day', 1 from generate_series(0, 3599) g
on conflict (slot) do update set at = excluded.at;
`)
const line = async () => (await db.query(`select count(*)::int as line, count(*) filter (where q.due_at <= now())::int as due from public.npc_waiting_queue(now()) q`)).rows[0]
console.log('staged:', JSON.stringify(await line()))
const wait = 60000 - (Date.now() % 60000)
console.log(`waiting ${Math.round(wait / 1000)} s for the minute to start`)
await new Promise((r) => setTimeout(r, wait + 50))
const t = Date.now()
await db.exec('call public.tick_waiting_asks()')
const wall = Date.now() - t
const r = (await db.query(`select ms, receipt from public.waiting_ask_runs order by at desc limit 1`)).rows[0]
console.log(`one minute as the job runs it: ${wall} ms wall`)
console.log(JSON.stringify(r.receipt))
console.log('after:', JSON.stringify(await line()))
const rc = r.receipt
const per = (rc.plan_ms + rc.open_ms) / Math.max(1, rc.asked)
console.log(`cost an ask here: ${per.toFixed(0)} ms (plan ${(rc.plan_ms / Math.max(1, rc.asked)).toFixed(0)}, open ${(rc.open_ms / Math.max(1, rc.resumed)).toFixed(0)} a resume)`)
for (const ms of [per, 300, 460, 560]) console.log(`  at ${ms.toFixed(0)} ms an ask, ${rc.budget_ms} ms a minute holds ${Math.floor(rc.budget_ms / ms)} asks a minute = ${Math.floor(rc.budget_ms / ms) * 60} an hour: a line of ${Math.floor(rc.budget_ms / ms) * 10} asked every 10 minutes`)
await db.close()
process.exit(0)
