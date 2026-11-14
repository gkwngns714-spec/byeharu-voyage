// measure.mjs: THE WAITING-ASKS JOB FOR ONE REAL MINUTE UNDER THE BACK-OFF, with a line of N staged in its steady state. LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/ask-backoff/measure.mjs [--n=150] [--new=35] [--budget=600000] [--fixture]
//
// Restores the cached world at the head before 0407 (never from zero; the cache is only read), applies 0407, lights the merchants and stages THE LINE IN ITS
// STEADY STATE under the back-off: --new merchants newly laid up (refused once, last asked 0 to 10 minutes ago) and the rest of --n refused four times (last
// asked 0 to 50 minutes ago). It then CALLS public.tick_waiting_asks() as pg_cron calls it, with its commits, for one clock minute, and prints the receipt:
// how many came due and were asked in the minute, and the work spent. Under the old rule (everyone due every 10 minutes) n / 10 would be due a minute.
// public.arrivals_beats is filled with a row a second dated ahead so the open step finds its gap. --fixture installs the proofs market. The world is thrown away.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const N = Number(arg('n') ?? 150)
const NEW = Number(arg('new') ?? 35)   // newly laid up in the last ten minutes (prod: 2 to 5 resumed a minute, so about as many laid up)
const NAME = '20260818000407'
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
const line = async () => (await db.query(`select count(*)::int as line, count(*) filter (where q.due_at <= now())::int as due from public.npc_waiting_queue(now()) q`)).rows[0]
const wait = 60000 - (Date.now() % 60000)
console.log(`waiting ${Math.round(wait / 1000)} s for the minute to start`)
await new Promise((r) => setTimeout(r, wait + 50))
await db.exec(`
update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
update public.world_config set value = to_jsonb(${Number(arg('budget') ?? 600000)}) where key = 'npc_ask_job_ms';
update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null, hold_until = null from public.npc_fleets nf where nf.route_id = sr.id;
create table public.ll_measure as
select ro.fleet_id, ro.route_id, row_number() over (order by ro.k) as i
  from public.npc_tend_roster() ro
  join public.fleets f on f.id = ro.fleet_id and f.status = 'DOCKED'
  join public.standing_routes sr on sr.id = ro.route_id and sr.fleet_id = ro.fleet_id
  join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
 where ro.k <= public.wc_int('npc_fleet_max')
 order by ro.k limit ${N};
-- THE LINE IN ITS STEADY STATE: ${NEW} newly laid up (one refusal, their last ask spread evenly over the last 10 minutes) and the rest refused four times
-- or more (their last ask spread evenly over the last 50 minutes). In the minute run, those whose wait ends in it are due.
update public.standing_routes sr set paused_reason = 'laid_up',
       updated_at = now() - make_interval(secs => case when l.i <= ${NEW} then (600.0 * l.i / ${NEW}) else (3000.0 * (l.i - ${NEW}) / greatest(1, ${N} - ${NEW})) end)
  from public.ll_measure l where l.route_id = sr.id;
update public.npc_fleets nf set asked_at = null, refused = case when l.i <= ${NEW} then 1 else 4 end from public.ll_measure l where l.fleet_id = nf.fleet_id;
insert into public.arrivals_beats (slot, at, ms) select g, now() + interval '1 day', 1 from generate_series(0, 3599) g
on conflict (slot) do update set at = excluded.at;
`)
console.log('staged at the minute:', JSON.stringify(await line()))
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
const hard = (N - NEW) / 50, fresh = NEW / 10
console.log(`due in the 57 s by the rule: about ${((hard + fresh) * 57 / 60).toFixed(1)} (a minute: ${(hard + fresh).toFixed(1)}); under the old rule ${(N / 10).toFixed(1)} a minute`)
// prod (2026-11-14 02:10-02:35 UTC): a plan about 1,450 ms; an open read 1,700 ms with its wait for the quay in it (a lap start's open reads 180 ms)
for (const op of [200, 1700]) console.log(`  on prod, the long-refused refused again and the new ones resumed, at 1,450 ms a plan and ${op} ms an open: ${((hard * 1450 + fresh * (1450 + op)) / 1000).toFixed(1)} s of work a minute; under the old rule ${(((N - NEW) / 10 * 1450 + fresh * (1450 + op)) / 1000).toFixed(1)} s`)
await db.close()
process.exit(0)
