// HOW HONEST IS A REPEATING SEA JOB'S SERVED COIN AN HOUR? (local PGlite only, never prod; everything is rolled back)
//   node scripts/ops/harness/hq-figures/measure-repeat.mjs [--purse 5000000] [--runs 10] [--nation PRT] [--pick 0 | --id quicksilver:LIS:SET | --best] [--ledger]
// A fresh company asks world.actions for her fleet, takes the fixed run the server ranks first (or --pick n), sets it through
// cmd.set_fleet_job and lets the REAL job tick (public.tick_fleet_jobs) run it back to back: each voyage's stamps are moved into the
// past and world.fleets() settles the arrival (proof 184's way; a transaction has one instant, so nothing recovers between runs: the
// runs lie inside one game day, as ten runs of a few minutes do). Each run's coin is her ledger's; its time is the voyages' own
// seconds, the dock turns (world.trip_stop_seconds) and the two waits for the 2-minute job tick (60 s each on average).
// Printed: each run, then the measured coin an hour against the served `per_hour`.
// Use it on runs shorter than a game day: with one instant the day never turns, so a far run is not measured honestly here.
// --best: the Best run (one way, a new sale each run). --ledger: her ledger rows and the quay quotes beside each run.
import { world } from './q.mjs'

const arg = (k, d) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : d)
const PURSE = Number(arg('--purse', '5000000'))
const RUNS = Number(arg('--runs', '10'))
const NATION = arg('--nation', 'PRT')
const PICK = Number(arg('--pick', '0'))
const ID = arg('--id', null) // a part of the option's id, e.g. quicksilver:LIS:SET
const TICK_WAIT_S = 60 // the fleet-jobs job runs every 120 s: an idle fleet waits 60 s for it on average, at each end of a cycle

const db = await world()
const one = async (s, p = []) => (await db.query(s, p)).rows[0]
const AUTH = '00000000-0496-4000-8000-0000000f1a01'
await db.exec('begin')
try {
  const a = (await one(`select public.new_house($1, 'Casa das Contas', $2) as id`, [AUTH, NATION])).id
  const f = await one(`select f.id, p.code as home from public.fleets f join public.ports p on p.id = f.port_id where f.player_id = $1`, [a])
  await db.query(`update public.players set ducats = $2 where id = $1`, [a, PURSE])
  await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled')`)
  await db.query(`select cmd.assume_identity($1)`, [AUTH])
  const turn = Number((await one(`select world.trip_stop_seconds() as s`)).s)
  const day = Number((await one(`select public.wc_num('game_day_seconds') as s`)).s)
  const acts = (await one(`select world.actions('fleet:' || $1) as j`, [f.id])).j
  const fixed = acts.options.filter((o) => o.id.startsWith('sea:fixed:') && o.end === 'sell')
  console.log(`company at ${f.home}, purse ${PURSE}; dock turn ${turn} s; game day ${day} s; world.actions ${acts.ms} ms, ${acts.options.length} options`)
  for (const o of fixed) console.log(`  option ${o.id}: units ${o.units}, net ${o.net}, interval ${o.interval_s} s, per_hour ${o.per_hour}` + (o.day ? `, day ${JSON.stringify(o.day)}` : ''))
  const BEST = process.argv.includes('--best') // the Best run: one way, a new sale each run, one wait for the tick a run
  const opt = BEST ? acts.options.find((o) => o.id === 'sea:best') : ID ? fixed.find((o) => o.id.includes(ID)) : fixed[PICK]
  if (!opt) throw new Error('no fixed run is offered')
  console.log(`taking ${opt.id}: served per_hour ${opt.per_hour} (net ${opt.net} a run of ${opt.interval_s} s)`)
  if (process.argv.includes('--ledger')) {
    for (let k = 1; k <= 4; k += 1) {
      const q = await one(`select (select total from world.quote((select id from public.ports where code = $1), (select id from public.goods where code = $3), $4::numeric, 'buy', null, $5)) as b, (select total from world.quote((select id from public.ports where code = $2), (select id from public.goods where code = $3), $4::numeric, 'sell', null, $5)) as s`, [opt.buy, opt.sell, opt.good, k * opt.units, f.id])
      console.log(`    quote of ${k} runs' units: buy ${q.b}, sell ${q.s}, margin ${q.s - q.b}`)
    }
  }
  const set = (await one(`select cmd.set_fleet_job($1, $2, $3::jsonb) as r`, [f.id, opt.job.kind, JSON.stringify(opt.job.params)])).r
  if (!set.ok) throw new Error(`the door refused: ${JSON.stringify(set)}`)

  const purse = async () => Number((await one(`select ducats from public.players where id = $1`, [a])).ducats)
  const arrive = async () => {
    let secs = 0
    for (let k = 0; k < 40; k += 1) {
      const v = await one(`select extract(epoch from eta - departed_at) as s from public.voyages where fleet_id = $1 and status = 'SAILING'`, [f.id])
      if (!v) break
      secs += Number(v.s)
      await db.query(`update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where fleet_id = $1 and status = 'SAILING'`, [f.id])
      await db.query(`select world.fleets()`)
    }
    return secs
  }
  const runs = []
  let tradedBefore = 0
  let stop = null
  for (let n = 1; n <= RUNS; n += 1) {
    const before = await purse()
    await db.exec(`call public.tick_fleet_jobs(false)`)
    let j = await one(`select to_jsonb(j) as j from public.fleet_jobs j where j.fleet_id = $1`, [f.id])
    const sailing = await one(`select 1 as x from public.voyages where fleet_id = $1 and status = 'SAILING'`, [f.id])
    if (!sailing) {
      stop = j?.j ? `run ${n} did not start: paused ${j.j.paused_reason ?? '-'}, last ${JSON.stringify(j.j.last)}` : `run ${n}: the job is gone`
      break
    }
    const out = await arrive()
    const after = await purse()
    if (BEST) {
      const net1 = after - before
      const last = (await one(`select j.last from public.fleet_jobs j where j.fleet_id = $1`, [f.id]))?.last
      runs.push({ n, net: net1, secs: out + turn + TICK_WAIT_S, out, back: 0 })
      if (process.argv.includes('--ledger')) {
        const ord = await db.query(`select o.raw_text, o.status, o.error_code, o.result->>'units' as units, o.result->>'total' as total from public.orders o where o.fleet_id = $1 and o.plan_id = (select j.last_plan from public.fleet_jobs j where j.fleet_id = $1) and o.verb in ('BUY', 'SELL') order by o.seq`, [f.id])
        const aboard = await one(`select coalesce(sum((e.value)::numeric), 0) as q from public.ships s, jsonb_each_text(s.cargo) e where s.fleet_id = $1`, [f.id])
        const cap = last?.to && last?.good ? await one(`select world.daily_cap_remaining($1, (select id from public.ports where code = $2), (select id from public.goods where code = $3)) as left, (select t.ducats from public.port_treasury t join public.ports p on p.id = t.port_id where p.code = $2) as city`, [a, last.to, last.good]) : null
        console.log('    orders: ' + ord.rows.map((r) => `${r.raw_text} ${r.status}${r.error_code ? ' ' + r.error_code : ''} units ${r.units} total ${r.total}`).join(' | ') + `; aboard after ${aboard.q}; allowance left there ${cap?.left}; city purse ${cap?.city}`)
      }
      console.log(`  run ${n}: net ${net1}, ${last?.good} ${last?.from} -> ${last?.to} (its card said ${last?.profit} in ${last?.seconds} s), sailed ${Math.round(out)} s`)
      continue
    }
    const stuck = Number((await one(`select public.fleet_cargo_qty($1, $2) as q`, [f.id, opt.good])).q)
    await db.exec(`call public.tick_fleet_jobs(false)`)
    const back = await arrive()
    j = await one(`select to_jsonb(j) as j from public.fleet_jobs j where j.fleet_id = $1`, [f.id])
    const traded = Number((await one(`select coalesce(sum(td.qty), 0) as q from public.trade_daily td join public.ports p on p.id = td.port_id where td.player_id = $1 and p.code = $2`, [a, opt.buy])).q)
    const units = traded - tradedBefore
    tradedBefore = traded
    const net = (await purse()) - before
    const secs = out + turn + TICK_WAIT_S + back + turn + TICK_WAIT_S
    if (stuck >= 1) {
      const why = await one(`select o.error_code, o.error_message, o.result from public.orders o where o.fleet_id = $1 and o.verb = 'SELL' order by o.issued_at desc, o.seq desc limit 1`, [f.id])
      stop = `run ${n} sold only a part: ${stuck} units stayed aboard (${why?.error_code ?? 'the sale took what the day allows'}); it is not counted`
      console.log(`  run ${n}: NOT WHOLE, ${stuck} of ${units} units unsold; purse ${before} -> ${after}`)
      break
    }
    runs.push({ n, net, secs, out, back })
    if (process.argv.includes('--ledger')) {
      const led = await db.query(`select l.kind, l.ducats_delta as d from public.ledger l where l.player_id = $1 and l.kind <> 'FOUNDING' order by l.id desc limit 8`, [a])
      console.log('    ledger, newest first: ' + led.rows.map((r) => `${r.kind} ${r.d}`).join(', '))
    }
    console.log(`  run ${n}: net ${net} (purse ${before} -> ${after} at the sale -> ${before + net} home), units ${units}, out ${Math.round(out)} s, back ${Math.round(back)} s, cycle ${Math.round(secs)} s; job ${j?.j?.paused_reason ?? 'going'}`)
    if (back === 0) {
      stop = `after run ${n} she did not sail back: paused ${j?.j?.paused_reason ?? '-'}, last ${JSON.stringify(j?.j?.last)}`
      break
    }
  }
  const coin = runs.reduce((s, r) => s + r.net, 0)
  const secs = runs.reduce((s, r) => s + r.secs, 0)
  const measured = secs > 0 ? Math.round((coin * 3600) / secs) : 0
  console.log(`runs played ${runs.length} of ${RUNS}${stop ? `; STOPPED: ${stop}` : ''}`)
  console.log(`first run ${runs[0]?.net}, last run ${runs.at(-1)?.net}; all ${coin} coin in ${Math.round(secs)} s`)
  console.log(`while she ran: ${measured} coin an hour (first run alone over its served interval: ${Math.round((opt.net * 3600) / opt.interval_s)})`)
  const overDay = Math.round((coin * 3600) / Math.max(day, secs))
  const m = stop ? overDay : measured
  console.log(`MEASURED ${m} coin an hour${stop ? ` over the game day (${day} s: the allowance returns at its turn)` : ''}; SERVED per_hour ${opt.per_hour}${opt.day ? ` (day: ${opt.day.runs} runs, ${opt.day.coin} coin, ${opt.day.seconds} s, ${opt.day.stop})` : ''}`)
  console.log(`served - measured = ${opt.per_hour - m} coin an hour (${m !== 0 ? (((opt.per_hour - m) / Math.abs(m)) * 100).toFixed(1) : 'n/a'} % of the measured figure)`)
} catch (e) {
  console.log('ERROR:', e.message)
} finally {
  await db.exec('rollback')
  await db.close()
}
process.exit(0)
