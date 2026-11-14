// measure.mjs: THE BEAT'S EVENTS A REAL MINUTE, BEFORE AND AFTER 0413, in one local world. LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/day-hour/measure.mjs [--n=150] [--warm=3] [--mins=6]
//
// Restores the cached world at the head before 0413 (never from zero; the cache is only read), installs the proofs' market (prices that pay), lights the
// merchants and keeps --n of them. Then it plays the clock by hand, as pg_cron does: public.tick_arrivals(now()) every second and one pass of the lap-start
// job (public.tick_lap_starts(false)) every five seconds. --warm minutes to get the merchants to sea, --mins minutes counted at the old rate; then 0413 is
// applied (the ships at sea are re-timed by the file itself) and the same --mins are counted again. Printed per arm, a real minute: arrivals settled, voyage
// days settled, lap starts, the mean and the largest beat. PGlite is one connection and two to three times slower than prod: only the ratio of the two arms
// means anything. The world is thrown away.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const N = Number(arg('n') ?? 150), WARM = Number(arg('warm') ?? 3), MINS = Number(arg('mins') ?? 6)
const NAME = '20260818000413'
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) mine = name
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
const one = async (sql) => (await db.query(sql)).rows[0]
console.log(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
await (await import('../../../db/proof-courses.mjs')).installProofCourses(db, { log: () => {} })
await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
await db.exec(`
update public.world_config set value = to_jsonb(${N}) where key = 'npc_fleet_max';
update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
`)
const t0 = Date.now()
const sw = await one(`select public.npc_traders_switch(true) as j`)
console.log(`merchants lit in ${Date.now() - t0} ms:`, JSON.stringify(sw.j).slice(0, 300))
// every kept merchant in port with a loop is due now: the lap-start job plans her and puts her to sea
await db.exec(`update public.standing_routes sr set hold_until = now() from public.npc_tend_roster() ro
  where ro.route_id = sr.id and ro.k <= ${N} and sr.paused_reason is null and sr.lap_id is null and sr.hold_until is null`)
console.log('due at the start:', JSON.stringify(await one(`select count(*)::int as due from public.lap_starts_due()`)))
const T_START = new Date().toISOString()
const state = () => one(`select (select count(*)::int from public.voyages where status = 'SAILING') as sailing,
  (select count(*)::int from public.voyages where status = 'ARRIVED') as arrived,
  (select coalesce(sum(last_settled_day), 0)::int from public.voyages) as days,
  (select count(*)::int from public.standing_route_laps where started_at >= '${T_START}') as laps,
  (select count(*)::int from public.standing_routes where paused_reason = 'laid_up') as laid_up,
  public.wc_num('time_compression') as k`)
async function run(label, mins, count) {
  const end = Date.now() + mins * 60_000
  const s0 = await state()
  const beats = []
  let i = 0, lapMs = 0, fleets = 0, days = 0
  while (Date.now() < end) {
    const t = Date.now()
    const r = (await one(`select public.tick_arrivals(now()) as r`)).r
    beats.push(Date.now() - t)
    fleets += Number(r?.fleets ?? r?.arrived ?? 0); days += Number(r?.days ?? 0)
    if (i === 0 && count) console.log('  a beat says:', JSON.stringify(r).slice(0, 300))
    if (i % 5 === 0) { const t1 = Date.now(); await db.exec('call public.tick_lap_starts(false)'); lapMs += Date.now() - t1 }
    i++
    const wait = 1000 - (Date.now() - t)
    if (wait > 0) await new Promise((res) => setTimeout(res, wait))
  }
  const s1 = await state()
  const per = (a, b) => ((b - a) / mins).toFixed(1)
  beats.sort((a, b) => a - b)
  console.log(`${label}: rate ${s1.k}; ${mins} min, ${i} beats; a real minute: arrivals ${per(s0.arrived, s1.arrived)}, voyage days settled ${per(s0.days, s1.days)}, lap starts ${per(s0.laps, s1.laps)}; ` +
    `beat mean ${Math.round(beats.reduce((a, b) => a + b, 0) / beats.length)} ms, p95 ${beats[Math.floor(beats.length * 0.95)]} ms, max ${beats.at(-1)} ms; lap-start passes ${Math.round(lapMs / mins)} ms a minute; ` +
    `at sea ${s1.sailing}, laid up ${s1.laid_up}; the beat's own count: fleets ${(fleets / mins).toFixed(1)}, days ${(days / mins).toFixed(1)} a minute`)
  return { arrivals: (s1.arrived - s0.arrived) / mins, days: (s1.days - s0.days) / mins, laps: (s1.laps - s0.laps) / mins, beat: beats.reduce((a, b) => a + b, 0) / beats.length, lapMs: lapMs / mins }
}
await run('warm-up', WARM, false)
const a = await run('BEFORE', MINS, true)
await db.exec((await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', ''))
console.log(`applied ${mine}:`, JSON.stringify(await one(`select value from public.world_config where key = 'clock_anchor'`)))
const b = await run('AFTER', MINS, true)
const ratio = (x, y) => (y > 0 ? (x / y).toFixed(2) : 'n/a')
console.log(`AFTER / BEFORE: arrivals ${ratio(b.arrivals, a.arrivals)}, voyage days ${ratio(b.days, a.days)}, lap starts ${ratio(b.laps, a.laps)}, beat mean ms ${ratio(b.beat, a.beat)}, lap-start ms ${ratio(b.lapMs, a.lapMs)}`)
await db.close()
process.exit(0)
