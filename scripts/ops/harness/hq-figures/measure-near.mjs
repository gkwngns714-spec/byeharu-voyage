// THE NEAR ROUND (0498), BY THE REAL JOB AND THE REAL TICK, over game days that turn (local PGlite only; all rolled back).
//   node scripts/ops/harness/hq-figures/measure-near.mjs [--purse 40000] [--homes PRT:LIS,NLD:AMS,PRT:VEN,PRT:GOA,JPN:NAG] [--days 3] [--within 1440]
// NEEDS 0498 IN THE CHAIN. A fresh Barca is given the near round through cmd.set_fleet_job('best', {within}) and public.tick_fleet_jobs
// runs it (jobs_wait_enabled and near_round_enabled lit inside this transaction). The day turns as in measure-rotation.mjs. When she
// waits at her base her time is moved to the day's turn and the tick asks her again.
// Printed a home: coin an hour (her purse, over the days), her selling runs a day, her sails home, her waits, the plan's time
// (the tick's own receipt: plan_ms), and whether any run lost coin.
// NOT IN THIS WORLD: other traders, the price drift inside a day, world events.
import { world } from './q.mjs'

const arg = (k, d) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : d)
const PURSE = Number(arg('--purse', '40000'))
const HOMES = arg('--homes', 'PRT:LIS,NLD:AMS,PRT:VEN,PRT:GOA,JPN:NAG').split(',').map((h) => h.split(':'))
const DAYS = Number(arg('--days', '3'))
const WITHIN = Number(arg('--within', '1440'))
const WAIT = 60

const db = await world()
const one = async (s, p = []) => (await db.query(s, p)).rows[0]
await db.exec('begin')
if (!(await one(`select to_regprocedure('public.near_round_on()') is not null as ok`)).ok) throw new Error('0498 is not in this chain: run from a worktree that has it')
await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'jobs_wait_enabled', 'near_round_enabled')`)
const day = Number((await one(`select public.wc_num('game_day_seconds') as s`)).s)
const turn = Number((await one(`select world.trip_stop_seconds() as s`)).s)
const END = DAYS * day
console.log(`game day ${day} s, ${DAYS} days; purse ${PURSE}; within ${WITHIN} nm; dock turn ${turn} s; a wait for the tick ${WAIT} s`)

async function turnDay() {
  await db.query(`update public.world_config set value = jsonb_set(value, '{game_day,count}', to_jsonb((value #>> '{game_day,count}')::bigint + 1)) where key = 'market_clock_anchor'`)
  await db.query(`update public.port_goods set glut_at = glut_at - make_interval(secs => $1) where glut <> 0`, [day])
  await db.query(`select public.tick_market_drift(now())`)
}
async function arrive(f) {
  let secs = 0
  for (let k = 0; k < 60; k += 1) {
    const v = await one(`select extract(epoch from eta - departed_at) as s from public.voyages where fleet_id = $1 and status = 'SAILING'`, [f])
    if (!v) break
    secs += Number(v.s)
    await db.query(`update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where fleet_id = $1 and status = 'SAILING'`, [f])
    await db.query(`select world.fleets()`)
  }
  return secs
}

const rows = []
let seq = 0
for (const [nation, port] of HOMES) {
  await db.exec('savepoint s')
  try {
    seq += 1
    const auth = `00000000-0498-4000-8000-${String(seq).padStart(12, '0')}`
    const a = (await one(`select public.new_house($1, $2, $3, $4) as id`, [auth, `Casa da Ronda ${seq}`, nation, port])).id
    const f = (await one(`select f.id from public.fleets f where f.player_id = $1`, [a])).id
    await db.query(`update public.players set ducats = $2 where id = $1`, [a, PURSE])
    await db.query(`select cmd.assume_identity($1)`, [auth])
    const set = (await one(`select cmd.set_fleet_job($1, 'best', $2::jsonb) as r`, [f, JSON.stringify({ within: WITHIN })])).r
    if (!set.ok) throw new Error(`the door refused: ${JSON.stringify(set)}`)
    let t = 0, d = 0, sales = 0, homes = 0, waits = 0, lost = 0, worst = 0, stopped = null
    const plans = []
    const kinds = new Set()
    const sync = async () => { while (Math.floor(t / day) > d) { d += 1; await turnDay() } }
    while (t < END && sales + homes < 1500) {
      await db.query(`update public.fleet_jobs set next_at = null where fleet_id = $1 and paused_reason is null`, [f])
      const before = Number((await one(`select ducats from public.players where id = $1`, [a])).ducats)
      await db.exec(`call public.tick_fleet_jobs(false)`)
      const rc = (await one(`select r.receipt from public.fleet_job_runs r order by r.at desc limit 1`))?.receipt
      const step = rc?.steps?.find((s) => s.fleet === f)
      if (step?.plan_ms !== undefined) plans.push(Number(step.plan_ms))
      if ((rc?.steps ?? []).filter((s) => s.fleet === f).length > 1) throw new Error('more than one plan for her in one tick')
      const out = await arrive(f)
      const j = await one(`select j.paused_reason, j.last from public.fleet_jobs j where j.fleet_id = $1`, [f])
      if (out === 0) {
        if (!j || j.paused_reason) { stopped = j?.paused_reason ?? 'gone'; break }
        waits += 1
        t = (d + 1) * day
        await sync()
        continue
      }
      t += out + turn + WAIT
      await sync()
      if (j?.last?.leg === 'home') homes += 1
      else {
        sales += 1
        kinds.add(`${j?.last?.good} ${j?.last?.from}-${j?.last?.to}`)
        const net = Number((await one(`select ducats from public.players where id = $1`, [a])).ducats) - before
        if (net < 0) { lost += 1; worst = Math.min(worst, net) }
      }
    }
    const coin = Number((await one(`select ducats from public.players where id = $1`, [a])).ducats) - PURSE
    const aboard = Number((await one(`select coalesce(sum((e.value)::numeric), 0) as q from public.ships s, jsonb_each_text(s.cargo) e where s.fleet_id = $1`, [f])).q)
    const secs = Math.max(t, END)
    plans.sort((x, y) => x - y)
    const r = { port, perHour: Math.round((coin * 3600) / secs), sales, perDay: (sales / DAYS).toFixed(1), kinds: kinds.size, homes, waits, lost, worst, aboard, stopped,
      planMean: Math.round(plans.reduce((s, v) => s + v, 0) / Math.max(plans.length, 1)), planMax: Math.round(plans.at(-1) ?? 0), plans: plans.length }
    rows.push(r)
    console.log(`${port}: ${r.perHour}/h; ${sales} selling runs of ${r.kinds} kinds (${r.perDay} a day), ${homes} sails home, ${waits} waits; runs that lost coin ${lost}${lost ? ` (worst ${worst})` : ''}; aboard ${aboard}; ${stopped ? `STOPPED ${stopped}; ` : ''}plan ${r.planMean} ms mean, ${r.planMax} ms max over ${r.plans} plans`)
  } catch (e) {
    console.log(`${port}: ERROR ${e.message}`)
  }
  await db.exec('rollback to savepoint s')
}
console.log(`\n| Home | Near round | selling runs a day | kinds | sails home | waits | runs that lost | plan, mean / max |`)
console.log('|---|---|---|---|---|---|---|---|')
for (const r of rows) console.log(`| ${r.port} | ${r.perHour}/h | ${r.perDay} | ${r.kinds} | ${r.homes} | ${r.waits} | ${r.lost}${r.lost ? ` (worst ${r.worst})` : ''} | ${r.planMean} / ${r.planMax} ms |`)
await db.exec('rollback')
await db.close()
process.exit(0)
