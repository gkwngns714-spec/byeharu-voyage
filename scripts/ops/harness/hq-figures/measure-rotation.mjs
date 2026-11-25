// A NEAR ROTATION AGAINST A REPEAT THAT WAITS, OVER GAME DAYS THAT TURN (local PGlite only; all rolled back).
//   node scripts/ops/harness/hq-figures/measure-rotation.mjs [--purses 40000,200000] [--homes PRT:LIS,NLD:AMS,PRT:VEN,PRT:GOA,JPN:NAG] [--days 2] [--leg 1800] [--top 2]
// THE DAY TURNS HERE. A harness clock counts the seconds her voyages, dock turns and waits for the job tick take. Each time it passes
// a game day the world's own day is turned: the market clock's anchor (world_config market_clock_anchor, public.clock_count's own
// record) is moved on one game day, every sale's mark is aged one game day (port_goods.glut_at), and the world's own daily job
// public.tick_market_drift(now()) runs: stock returns at each harbour's restock rate, the marks fade, the day's allowance is new.
// NOT TURNED: the hourly price drift inside a day, other traders (merchants, cities' wants), world events. Read the figures as a
// world where she trades alone.
//   REPEAT THAT WAITS  the fixed near run (the best of the --top the server ranks): before each run her own quote (world.actions) is
//                      asked; if it leaves no profit she waits for the day's turn. A sale the day's allowance cuts short is finished
//                      after the turn, before she sails home.
//   ROTATION           each cycle, where she lies, the best paying card of world.best_sales within --leg seconds of sailing, by profit
//                      a second, its units cut to what the SALE harbour's allowance takes; none pays: she waits for the day's turn.
//                      Its lines are public.sale_lines' (the Best job's own), sent through cmd.issue_lines. She does not sail home.
import { world } from './q.mjs'

const arg = (k, d) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : d)
const PURSES = arg('--purses', '40000,200000').split(',').map(Number)
const HOMES = arg('--homes', 'PRT:LIS,NLD:AMS,PRT:VEN,PRT:GOA,JPN:NAG').split(',').map((h) => h.split(':'))
const DAYS = Number(arg('--days', '2'))
const LEG = Number(arg('--leg', '1800'))
const TOP = Number(arg('--top', '2'))
const WAIT = 60

const db = await world()
const one = async (s, p = []) => (await db.query(s, p)).rows[0]
let seq = 0

async function company(nation, port, purse) {
  seq += 1
  const auth = `00000000-0496-4000-8000-${String(seq).padStart(12, '0')}`
  const a = (await one(`select public.new_house($1, $2, $3, $4) as id`, [auth, `Casa da Roda ${seq}`, nation, port])).id
  const f = (await one(`select f.id from public.fleets f where f.player_id = $1`, [a])).id
  await db.query(`update public.players set ducats = $2 where id = $1`, [a, purse])
  await db.query(`select cmd.assume_identity($1)`, [auth])
  return { a, f }
}
const purseOf = async (a) => Number((await one(`select ducats from public.players where id = $1`, [a])).ducats)
const cargo = async (f) => Number((await one(`select coalesce(sum((e.value)::numeric), 0) as q from public.ships s, jsonb_each_text(s.cargo) e where s.fleet_id = $1`, [f])).q)
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

await db.exec('begin')
await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled')`)
const day = Number((await one(`select public.wc_num('game_day_seconds') as s`)).s)
const turn = Number((await one(`select world.trip_stop_seconds() as s`)).s)
console.log(`game day ${day} s, ${DAYS} days; dock turn ${turn} s; a wait for the tick ${WAIT} s; a rotation's leg at most ${LEG} s`)

/** The world's own day, turned once: the anchor, the marks' age, the daily job. */
async function turnDay() {
  await db.query(`update public.world_config set value = jsonb_set(value, '{game_day,count}', to_jsonb((value #>> '{game_day,count}')::bigint + 1)) where key = 'market_clock_anchor'`)
  await db.query(`update public.port_goods set glut_at = glut_at - make_interval(secs => $1) where glut <> 0`, [day])
  await db.query(`select public.tick_market_drift(now())`)
}
/** A clock that turns the world's day as it passes each one. */
function clock() {
  const c = { t: 0, d: 0 }
  c.sync = async () => {
    while (Math.floor(c.t / day) > c.d) {
      c.d += 1
      await turnDay()
    }
  }
  c.toNextDay = async () => {
    c.t = (c.d + 1) * day
    await c.sync()
  }
  return c
}
const END = DAYS * day

async function repeatWaits(nation, port, purse, id) {
  const c = await company(nation, port, purse)
  const [, , good, buy, sell] = id.split(':')
  const k = clock()
  let runs = 0, waits = 0
  while (k.t < END && runs < 200) {
    await db.query(`delete from public.fleet_jobs where fleet_id = $1`, [c.f])
    const opt = (await one(`select world.actions('fleet:' || $1) as j`, [c.f])).j.options.find((o) => o.id === id)
    if (!opt || opt.net <= 0) {
      waits += 1
      await k.toNextDay()
      continue
    }
    await one(`select cmd.set_fleet_job($1, 'fixed', $2::jsonb) as r`, [c.f, JSON.stringify({ good, buy, sell })])
    await db.exec(`call public.tick_fleet_jobs(false)`)
    const out = await arrive(c.f)
    if (out === 0) break
    k.t += out + turn + WAIT
    await k.sync()
    if ((await cargo(c.f)) >= 1) await k.toNextDay() // the allowance cut the sale short: the rest is sold after the turn
    await db.exec(`call public.tick_fleet_jobs(false)`)
    const back = await arrive(c.f)
    k.t += back + turn + WAIT
    await k.sync()
    runs += 1
    if (back === 0) break
  }
  return { runs, waits, coin: (await purseOf(c.a)) - purse, aboard: await cargo(c.f), secs: Math.max(k.t, END) }
}

async function rotation(nation, port, purse) {
  const c = await company(nation, port, purse)
  const k = clock()
  let runs = 0, waits = 0
  const seen = new Set()
  while (k.t < END && runs < 400) {
    const f = await one(`select f.port_id, f.version, p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = $1`, [c.f])
    if (!f) break
    const bs = (await one(`select world.best_sales($1, $2) as j`, [c.f, f.port_id])).j
    const cards = []
    for (const g of bs?.goods ?? []) {
      if (!g.port || !(g.profit > 0) || g.pays === false) continue
      const secs = g.seconds ?? (g.days !== null && g.days !== undefined ? g.days * 86400 : null)
      if (secs === null || secs > LEG) continue
      const left = Number((await one(`select coalesce(world.daily_cap_remaining($1, (select id from public.ports where code = $2), (select id from public.goods where code = $3)), 0) as q`, [c.a, g.port, g.good])).q)
      const units = Math.min(g.units, Math.floor(left))
      if (units < 1) continue
      cards.push({ g: { ...g, units }, rate: (g.profit * (units / g.units)) / (secs + WAIT + turn) })
    }
    cards.sort((x, y) => y.rate - x.rate)
    let sailed = 0
    for (const card of cards) {
      const lines = (await one(
        `select public.sale_lines(f.id, f.port_id, $2::jsonb,
                  (select coalesce(e->'stops', '[]'::jsonb) from jsonb_array_elements(coalesce(world.board_passages(f.player_id, f.id, f.port_id, (select sr.cap_nm from public.supply_reach(f.id) sr)), '[]'::jsonb)) e
                     join public.ports p on p.id = (e->>'port_id')::uuid where p.code = $3 limit 1)) as j
           from public.fleets f where f.id = $1`,
        [c.f, JSON.stringify(card.g), card.g.port],
      )).j
      if (!lines?.lines) continue
      await db.exec('savepoint go')
      let ok = false
      try {
        const r = (await one(`select cmd.issue_lines($1, $2::jsonb, $3) as r`, [c.f, JSON.stringify(lines.lines), f.version])).r
        ok = r?.ok === true
      } catch {
        ok = false
      }
      if (!ok) {
        await db.exec('rollback to savepoint go')
        continue
      }
      await db.exec('release savepoint go')
      sailed = await arrive(c.f)
      if (sailed > 0) {
        seen.add(`${card.g.good} ${f.code}-${card.g.port}`)
        break
      }
    }
    if (sailed === 0) {
      waits += 1
      await k.toNextDay()
      continue
    }
    runs += 1
    k.t += sailed + turn + WAIT
    await k.sync()
  }
  return { runs, waits, coin: (await purseOf(c.a)) - purse, aboard: await cargo(c.f), secs: Math.max(k.t, END), kinds: seen.size }
}

const perHour = (r) => Math.round((r.coin * 3600) / r.secs)
const table = []
for (const [nation, port] of HOMES)
  for (const purse of PURSES) {
    let ids = []
    await db.exec('savepoint s')
    try {
      const c = await company(nation, port, purse)
      ids = (await one(`select world.actions('fleet:' || $1) as j`, [c.f])).j.options.filter((o) => o.id.startsWith('sea:fixed:') && o.end === 'sell' && o.interval_s < 3600).slice(0, TOP).map((o) => o.id)
    } catch (e) {
      console.log(`${port} ${purse}: ERROR ${e.message}`)
    }
    await db.exec('rollback to savepoint s')
    let rep = null
    for (const id of ids) {
      await db.exec('savepoint s')
      try {
        const r = { id, ...(await repeatWaits(nation, port, purse, id)) }
        console.log(`${port} ${purse} REPEAT THAT WAITS ${id}: ${r.runs} runs, ${r.waits} waits, coin ${r.coin}, aboard ${r.aboard}: ${perHour(r)}/h`)
        if (!rep || perHour(r) > perHour(rep)) rep = r
      } catch (e) {
        console.log(`${port} ${purse} REPEAT ${id}: ERROR ${e.message}`)
      }
      await db.exec('rollback to savepoint s')
    }
    let rot = null
    await db.exec('savepoint s')
    try {
      rot = await rotation(nation, port, purse)
      console.log(`${port} ${purse} ROTATION: ${rot.runs} runs of ${rot.kinds} kinds, ${rot.waits} waits, coin ${rot.coin}, aboard ${rot.aboard}: ${perHour(rot)}/h`)
    } catch (e) {
      console.log(`${port} ${purse} ROTATION: ERROR ${e.message}`)
    }
    await db.exec('rollback to savepoint s')
    table.push({ port, purse, rep, rot })
  }
console.log(`\n| Home | Purse | Repeat that waits (${DAYS} days) | Rotation (${DAYS} days) | Rotation / Repeat |`)
console.log('|---|---|---|---|---|')
for (const t of table)
  console.log(
    `| ${t.port} | ${t.purse} | ${t.rep ? `${perHour(t.rep)}/h (${t.rep.id.split(':').slice(2, 5).join(' ')}, ${t.rep.runs} runs)` : '-'} | ${t.rot ? `${perHour(t.rot)}/h (${t.rot.runs} runs, ${t.rot.kinds} kinds${t.rot.aboard >= 1 ? `, ${t.rot.aboard} aboard` : ''})` : '-'} | ${t.rep && t.rot && perHour(t.rep) > 0 ? (perHour(t.rot) / perHour(t.rep)).toFixed(1) + 'x' : '-'} |`,
  )
await db.exec('rollback')
await db.close()
process.exit(0)
