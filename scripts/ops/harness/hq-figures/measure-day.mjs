// DOES A REPEATING TRADE EARN AT ALL? Coin an hour over ONE game day, by the real job tick (local PGlite only; all rolled back).
//   node scripts/ops/harness/hq-figures/measure-day.mjs [--purses 40000,200000] [--homes PRT:LIS,NLD:AMS,VEN:VEN,GEN:GOA,JPN:NAG] [--top 3]
// For each home and purse a fresh company (one Barca) asks world.actions and, for each of the --top near fixed runs (a cycle under
// an hour, in the served order), sets it through cmd.set_fleet_job and lets public.tick_fleet_jobs run it back to back until the
// day's allowance stops her or a game day's time is spent (measure-repeat.mjs' way: one instant, so nothing recovers inside the day).
//   REPEAT          every whole run she makes, the losing ones too (what the job does today), over the game day
//   REPEAT, WAITS   the same runs up to the first whose own quote at that moment (world.actions, asked again each cycle) leaves no
//                   profit; she then waits for the day's turn. Over the game day.
//   BEST RUN        the Best job, until a game day of sailing is spent. ITS RUNS ARE FAR (hours each): with one instant the day never
//                   turns, so no allowance or stock returns between them; read it as a rough figure.
// Not played: the second day and after (the harness cannot turn the day).
import { world } from './q.mjs'

const arg = (k, d) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : d)
const PURSES = arg('--purses', '40000,200000').split(',').map(Number)
const HOMES = arg('--homes', 'PRT:LIS,NLD:AMS,VEN:VEN,GEN:GOA,JPN:NAG').split(',').map((h) => h.split(':'))
const TOP = Number(arg('--top', '3'))
const WAIT = 60
const NEAR_S = 3600

const db = await world()
const one = async (s, p = []) => (await db.query(s, p)).rows[0]
let seq = 0

async function company(nation, port, purse) {
  seq += 1
  const auth = `00000000-0496-4000-8000-${String(seq).padStart(12, '0')}`
  const a = (await one(`select public.new_house($1, $2, $3, $4) as id`, [auth, `Casa do Dia ${seq}`, nation, port])).id
  const f = await one(`select f.id from public.fleets f where f.player_id = $1`, [a])
  await db.query(`update public.players set ducats = $2 where id = $1`, [a, purse])
  await db.query(`select cmd.assume_identity($1)`, [auth])
  return { a, f: f.id, auth }
}
const purseOf = async (a) => Number((await one(`select ducats from public.players where id = $1`, [a])).ducats)
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
const cargo = async (f) => Number((await one(`select coalesce(sum((e.value)::numeric), 0) as q from public.ships s, jsonb_each_text(s.cargo) e where s.fleet_id = $1`, [f])).q)

await db.exec('begin')
await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled')`)
const day = Number((await one(`select public.wc_num('game_day_seconds') as s`)).s)
const turn = Number((await one(`select world.trip_stop_seconds() as s`)).s)
console.log(`game day ${day} s; dock turn ${turn} s; a wait for the tick ${WAIT} s`)
const table = []

for (const [nation, port] of HOMES)
  for (const purse of PURSES) {
    // which near runs the server offers her here
    await db.exec('savepoint s')
    let ids = []
    try {
      const c = await company(nation, port, purse)
      const acts = (await one(`select world.actions('fleet:' || $1) as j`, [c.f])).j
      ids = acts.options.filter((o) => o.id.startsWith('sea:fixed:') && o.end === 'sell' && o.interval_s < NEAR_S).slice(0, TOP).map((o) => ({ id: o.id, served: o.per_hour, net: o.net, units: o.units }))
    } catch (e) {
      console.log(`${port} ${purse}: ERROR ${e.message}`)
    }
    await db.exec('rollback to savepoint s')
    const rows = []
    for (const pick of ids) {
      await db.exec('savepoint s')
      try {
        const c = await company(nation, port, purse)
        let acts = (await one(`select world.actions('fleet:' || $1) as j`, [c.f])).j
        let opt = acts.options.find((o) => o.id === pick.id)
        if (!opt) throw new Error('the run is not offered the second time')
        await one(`select cmd.set_fleet_job($1, $2, $3::jsonb) as r`, [c.f, opt.job.kind, JSON.stringify(opt.job.params)])
        let coin = 0, secs = 0, n = 0, gainCoin = 0, gainN = 0, gaining = true, why = 'day'
        while (secs < day && n < 80) {
          if (n > 0) {
            // her quote of the next run, at this moment (what a job that waits would read)
            await db.query(`delete from public.fleet_jobs where fleet_id = $1`, [c.f]) // a read of options needs no job; set again below
            acts = (await one(`select world.actions('fleet:' || $1) as j`, [c.f])).j
            opt = acts.options.find((o) => o.id === pick.id)
            if (gaining && (!opt || opt.net <= 0)) gaining = false
            await one(`select cmd.set_fleet_job($1, 'fixed', $2::jsonb) as r`, [c.f, JSON.stringify({ good: pick.id.split(':')[2], buy: pick.id.split(':')[3], sell: pick.id.split(':')[4] })])
          }
          const before = await purseOf(c.a)
          await db.exec(`call public.tick_fleet_jobs(false)`)
          const out = await arrive(c.f)
          if (out === 0) { why = 'did not sail'; break }
          if ((await cargo(c.f)) >= 1) { why = 'allowance'; break }
          await db.exec(`call public.tick_fleet_jobs(false)`)
          const back = await arrive(c.f)
          const net = (await purseOf(c.a)) - before
          n += 1; coin += net; secs += out + back + 2 * turn + 2 * WAIT
          if (gaining) { gainN += 1; gainCoin += net }
          if (back === 0) { why = 'did not sail back'; break }
        }
        rows.push({ id: pick.id, units: pick.units, first: pick.net, served: pick.served, n, repeat: Math.round((coin * 3600) / Math.max(day, secs)), gainN, waits: Math.round((gainCoin * 3600) / Math.max(day, secs > day ? secs : day)), why })
      } catch (e) {
        rows.push({ id: pick.id, error: e.message })
      }
      await db.exec('rollback to savepoint s')
    }
    // the Best run
    let best = null
    await db.exec('savepoint s')
    try {
      const c = await company(nation, port, purse)
      await one(`select cmd.set_fleet_job($1, 'best', '{}'::jsonb) as r`, [c.f])
      let coin = 0, secs = 0, n = 0, part = 0, why = 'day'
      const start = await purseOf(c.a)
      while (secs < day && n < 40) {
        await db.exec(`call public.tick_fleet_jobs(false)`)
        const out = await arrive(c.f)
        if (out === 0) { why = (await one(`select coalesce(j.paused_reason, j.last->>'wait', 'idle') as w from public.fleet_jobs j where j.fleet_id = $1`, [c.f]))?.w ?? 'gone'; break }
        n += 1; secs += out + turn + WAIT
        if ((await cargo(c.f)) >= 1) part += 1
      }
      coin = (await purseOf(c.a)) - start
      best = { n, part, perHour: Math.round((coin * 3600) / Math.max(day, secs)), hours: (secs / 3600).toFixed(1), why, aboard: await cargo(c.f) }
    } catch (e) {
      best = { error: e.message }
    }
    await db.exec('rollback to savepoint s')
    const top = rows.filter((r) => !r.error).sort((x, y) => y.waits - x.waits)[0]
    table.push({ port, purse, rows, best, top })
    console.log(`\n${port}, purse ${purse}`)
    for (const r of rows) console.log(r.error ? `  ${r.id}: ERROR ${r.error}` : `  ${r.id}: ${r.units} units, first run ${r.first}; served ${r.served}/h; REPEAT ${r.n} runs ${r.repeat}/h (${r.why}); WAITS ${r.gainN} runs ${r.waits}/h`)
    console.log(`  BEST RUN: ${JSON.stringify(best)}`)
  }
console.log('\n| Home | Purse | Best near run | Repeat (as today) | Repeat that waits | Served now | Best run |')
console.log('|---|---|---|---|---|---|---|')
for (const t of table) console.log(`| ${t.port} | ${t.purse} | ${t.top ? t.top.id.split(':').slice(2, 5).join(' ') : 'none offered'} | ${t.top ? `${t.top.repeat}/h (${t.top.n} runs)` : '-'} | ${t.top ? `${t.top.waits}/h (${t.top.gainN} runs)` : '-'} | ${t.top ? `${t.top.served}/h` : '-'} | ${t.best?.error ? 'error' : `${t.best.perHour}/h (${t.best.n} runs, ${t.best.hours} h, ${t.best.part} part-sold)`} |`)
await db.exec('rollback')
await db.close()
process.exit(0)
