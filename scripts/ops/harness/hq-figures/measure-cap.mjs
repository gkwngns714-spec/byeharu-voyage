// WHAT BINDS A REPEATING TRADE? The day's allowance at three settings, over game days that turn (local PGlite only; all rolled back).
//   node scripts/ops/harness/hq-figures/measure-cap.mjs [--fractions 0.35,0.7,1.0] [--purse 40000] [--homes PRT:LIS,NLD:AMS,PRT:VEN,PRT:GOA,JPN:NAG] [--days 3] [--leg 1800]
// NEEDS 0497 IN THE CHAIN (run it from a worktree that has it): the jobs wait instead of losing (jobs_wait_enabled, lit here).
// world_config.daily_cap_fraction is set INSIDE THIS ROLLED-BACK TRANSACTION ONLY. No migration changes it; it is the owner's knob.
// The day turns as in measure-rotation.mjs: the market clock's anchor moves on a game day, every sale's mark is aged a day, and the
// world's own public.tick_market_drift runs (stock returns, marks fade, the allowance is new).
//   WAITING REPEAT   the REAL fixed job, set once (the better of the two near runs the server ranks first), run by the real tick. When
//                    it waits, why is read from public.fleet_run_quote and public.fleet_buy_capacity; her time is then moved to the
//                    day's turn and the tick asks her again.
//   ROTATION, HOME   each cycle the best paying card within --leg seconds, by profit a second, from the server's own cut cards
//                    (public.cards_fit); nothing pays where she lies: she sails HOME (if away), and waits for the day's turn there.
// WHAT STOPPED HER, counted each time she had to wait:
//   allowance  the day's allowance at the sale's harbour or the buying one is spent     stock  the buying quay is empty
//   purse      her coin buys none                                                       price  the quote leaves no profit (the quay's
//              walk and the mark of her own sales: the glut)
// NOT IN THIS WORLD: other traders (merchants, cities' wants), the price drift inside a day, world events. She trades alone.
import { world } from './q.mjs'

const arg = (k, d) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : d)
const FRACTIONS = arg('--fractions', '0.35,0.7,1.0').split(',').map(Number)
const PURSE = Number(arg('--purse', '40000'))
const HOMES = arg('--homes', 'PRT:LIS,NLD:AMS,PRT:VEN,PRT:GOA,JPN:NAG').split(',').map((h) => h.split(':'))
const DAYS = Number(arg('--days', '3'))
const LEG = Number(arg('--leg', '1800'))
const WAIT = 60

const db = await world()
const one = async (s, p = []) => (await db.query(s, p)).rows[0]
let seq = 0

async function company(nation, port) {
  seq += 1
  const auth = `00000000-0497-4000-8000-${String(seq).padStart(12, '0')}`
  const a = (await one(`select public.new_house($1, $2, $3, $4) as id`, [auth, `Casa da Medida ${seq}`, nation, port])).id
  const f = (await one(`select f.id, f.port_id from public.fleets f where f.player_id = $1`, [a]))
  await db.query(`update public.players set ducats = $2 where id = $1`, [a, PURSE])
  await db.query(`select cmd.assume_identity($1)`, [auth])
  return { a, f: f.id, home: f.port_id, homeCode: port }
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
if (!(await one(`select to_regprocedure('public.jobs_wait_on()') is not null as ok`)).ok) throw new Error('0497 is not in this chain: run from a worktree that has it')
await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'jobs_wait_enabled')`)
const day = Number((await one(`select public.wc_num('game_day_seconds') as s`)).s)
const turn = Number((await one(`select world.trip_stop_seconds() as s`)).s)
const END = DAYS * day
console.log(`game day ${day} s (${(day / 3600).toFixed(1)} h), ${DAYS} days; purse ${PURSE}; dock turn ${turn} s; a wait for the tick ${WAIT} s; a rotation's leg at most ${LEG} s`)

async function turnDay() {
  await db.query(`update public.world_config set value = jsonb_set(value, '{game_day,count}', to_jsonb((value #>> '{game_day,count}')::bigint + 1)) where key = 'market_clock_anchor'`)
  await db.query(`update public.port_goods set glut_at = glut_at - make_interval(secs => $1) where glut <> 0`, [day])
  await db.query(`select public.tick_market_drift(now())`)
}
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
const tally = (why, k) => { why[k] = (why[k] ?? 0) + 1 }
const said = (why) => Object.entries(why).sort((x, y) => y[1] - x[1]).map(([k, n]) => `${k} x${n}`).join(', ') || 'never waited'

/** Why a fixed run cannot start now, in this harness's four words. */
async function whyFixed(c, good, sell, codes) {
  const q = (await one(`select public.fleet_run_quote($1, $2, (select port_id from public.fleets where id = $2), $3, $4, $5::text[]) as j`, [c.a, c.f, good, sell, codes])).j
  if (q?.why === 'allowance') return 'allowance'
  if (q?.why === 'buy') {
    const b = (await one(`select public.fleet_buy_capacity($1, (select id from public.goods where code = $2)) as j`, [c.f, good])).j?.bound_by
    return b === 'daily cap' ? 'allowance' : b === 'stock' ? 'stock' : b === 'purse' ? 'purse' : `buy (${b})`
  }
  return 'price'
}

async function waitingRepeat(nation, port, id) {
  const c = await company(nation, port)
  const [, , good, buy, sell] = id.split(':')
  const k = clock()
  const why = {}
  let runs = 0
  await one(`select cmd.set_fleet_job($1, 'fixed', $2::jsonb) as r`, [c.f, JSON.stringify({ good, buy, sell })])
  while (k.t < END && runs < 600) {
    await db.query(`update public.fleet_jobs set next_at = null where fleet_id = $1 and paused_reason is null`, [c.f]) // her time has come
    await db.exec(`call public.tick_fleet_jobs(false)`)
    const out = await arrive(c.f)
    if (out === 0) {
      const j = await one(`select j.paused_reason, j.last from public.fleet_jobs j where j.fleet_id = $1`, [c.f])
      if (!j || j.paused_reason) { tally(why, `STOPPED ${j?.paused_reason ?? 'gone'}`); break }
      tally(why, await whyFixed(c, good, sell, [sell, buy]))
      await k.toNextDay()
      continue
    }
    k.t += out + turn + WAIT
    await k.sync()
    await db.exec(`call public.tick_fleet_jobs(false)`)
    const back = await arrive(c.f)
    k.t += back + turn + WAIT
    await k.sync()
    runs += 1
    if (back === 0) { tally(why, 'did not sail back'); break }
  }
  return { id, runs, why, coin: (await purseOf(c.a)) - PURSE, aboard: await cargo(c.f), secs: Math.max(k.t, END) }
}

async function rotationHome(nation, port) {
  const c = await company(nation, port)
  const k = clock()
  const why = {}
  let runs = 0, homes = 0
  const kinds = new Set()
  while (k.t < END && runs < 900) {
    const f = await one(`select f.port_id, f.version, p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = $1`, [c.f])
    if (!f) break
    const bs = (await one(`select world.best_sales($1, $2) as j`, [c.f, f.port_id])).j
    const near = (g) => { const s = g.seconds ?? (g.days !== null && g.days !== undefined ? g.days * 86400 : null); return s !== null && s <= LEG ? s : null }
    const raw = (bs?.goods ?? []).filter((g) => g.port && g.profit > 0 && g.pays !== false && near(g) !== null)
    const fit = (await one(`select public.cards_fit($1, $2, $3, $4::jsonb, 40, false) as j`, [c.a, c.f, f.port_id, JSON.stringify(bs?.goods ?? [])])).j
    const cards = fit.filter((g) => near(g) !== null).map((g) => ({ g, rate: g.profit / (near(g) + WAIT + turn) })).sort((x, y) => y.rate - x.rate)
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
        ok = (await one(`select cmd.issue_lines($1, $2::jsonb, $3) as r`, [c.f, JSON.stringify(lines.lines), f.version])).r?.ok === true
      } catch {
        ok = false
      }
      if (!ok) { await db.exec('rollback to savepoint go'); continue }
      await db.exec('release savepoint go')
      sailed = await arrive(c.f)
      if (sailed > 0) { kinds.add(`${card.g.good} ${f.code}-${card.g.port}`); break }
    }
    if (sailed > 0) {
      runs += 1
      k.t += sailed + turn + WAIT
      await k.sync()
      continue
    }
    // nothing pays where she lies: say why, and go home if she is away
    tally(why, raw.length === 0 ? 'price' : cards.length === 0 ? 'allowance' : 'no course')
    if (f.port_id !== c.home) {
      const s = (await one(`select public.fleet_job_sails($1, $2, array[$3]) as j`, [c.f, f.port_id, c.homeCode])).j
      let went = 0
      if (s?.lines) {
        await db.exec('savepoint go')
        try {
          await one(`select cmd.issue_lines($1, $2::jsonb, $3) as r`, [c.f, JSON.stringify(s.lines), f.version])
          await db.exec('release savepoint go')
          went = await arrive(c.f)
        } catch {
          await db.exec('rollback to savepoint go')
        }
      }
      if (went > 0) {
        homes += 1
        k.t += went + turn + WAIT
        await k.sync()
        continue
      }
    }
    await k.toNextDay()
  }
  return { runs, homes, kinds: kinds.size, why, coin: (await purseOf(c.a)) - PURSE, aboard: await cargo(c.f), secs: Math.max(k.t, END) }
}

const perHour = (r) => Math.round((r.coin * 3600) / r.secs)
const rows = []
for (const frac of FRACTIONS) {
  await db.exec('savepoint frac')
  await db.query(`update public.world_config set value = to_jsonb($1::numeric) where key = 'daily_cap_fraction'`, [frac])
  for (const [nation, port] of HOMES) {
    let ids = []
    await db.exec('savepoint s')
    try {
      const c = await company(nation, port)
      ids = (await one(`select world.actions('fleet:' || $1) as j`, [c.f])).j.options.filter((o) => o.id.startsWith('sea:fixed:') && o.end === 'sell' && o.interval_s < 3600).slice(0, 2).map((o) => o.id)
    } catch (e) {
      console.log(`${frac} ${port}: ERROR ${e.message}`)
    }
    await db.exec('rollback to savepoint s')
    let rep = null
    for (const id of ids) {
      await db.exec('savepoint s')
      try {
        const r = await waitingRepeat(nation, port, id)
        console.log(`${frac} ${port} WAITING REPEAT ${id}: ${r.runs} runs, coin ${r.coin}, aboard ${r.aboard}: ${perHour(r)}/h; ${said(r.why)}`)
        if (!rep || perHour(r) > perHour(rep)) rep = r
      } catch (e) {
        console.log(`${frac} ${port} WAITING REPEAT ${id}: ERROR ${e.message}`)
      }
      await db.exec('rollback to savepoint s')
    }
    let rot = null
    await db.exec('savepoint s')
    try {
      rot = await rotationHome(nation, port)
      console.log(`${frac} ${port} ROTATION, HOME: ${rot.runs} runs of ${rot.kinds} kinds, ${rot.homes} sails home, coin ${rot.coin}, aboard ${rot.aboard}: ${perHour(rot)}/h; ${said(rot.why)}`)
    } catch (e) {
      console.log(`${frac} ${port} ROTATION: ERROR ${e.message}`)
    }
    await db.exec('rollback to savepoint s')
    rows.push({ frac, port, rep, rot })
  }
  await db.exec('rollback to savepoint frac')
}

// HOW FAST A QUAY COMES BACK: one row whose stock is emptied to half its mark and whose sale mark is put at 0.10, then the days turned
await db.exec('savepoint rec')
const row = await one(`select pg.port_id, pg.good_id, pg.stock_target as target, public.restock_rate(pg.port_id) as rate from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id where p.code = 'SET' and g.code = 'quicksilver'`)
await db.query(`update public.port_goods set stock = stock_target / 2, glut = 0.1, glut_at = now() where port_id = $1 and good_id = $2`, [row.port_id, row.good_id])
const rec = []
for (let d = 1; d <= 6; d += 1) {
  await turnDay()
  const r = await one(`select stock, stock_target, glut from public.port_goods where port_id = $1 and good_id = $2`, [row.port_id, row.good_id])
  rec.push(`day ${d} (${((d * day) / 3600).toFixed(0)} h): stock gap ${(100 * (1 - Number(r.stock) / Number(r.stock_target))).toFixed(1)} %, mark ${Number(r.glut).toFixed(4)}`)
}
await db.exec('rollback to savepoint rec')
console.log(`\nRECOVERY (quicksilver at Setubal, emptied to half its mark, its sale mark at 0.1000; restock rate ${row.rate} a game day; glut_half_life_hours ${(await one(`select public.wc_num('glut_half_life_hours') as h`)).h}):`)
for (const l of rec) console.log(`  ${l}`)

console.log(`\n| Allowance | Home | Waiting Repeat | paying runs a day | stopped by | Rotation, home | runs a day | stopped by |`)
console.log('|---|---|---|---|---|---|---|---|')
for (const t of rows)
  console.log(
    `| ${t.frac} | ${t.port} | ${t.rep ? `${perHour(t.rep)}/h (${t.rep.id.split(':').slice(2, 5).join(' ')})` : '-'} | ${t.rep ? (t.rep.runs / DAYS).toFixed(1) : '-'} | ${t.rep ? said(t.rep.why) : '-'} | ${t.rot ? `${perHour(t.rot)}/h (${t.rot.kinds} kinds, ${t.rot.homes} sails home)` : '-'} | ${t.rot ? (t.rot.runs / DAYS).toFixed(1) : '-'} | ${t.rot ? said(t.rot.why) : '-'} |`,
  )
await db.exec('rollback')
await db.close()
process.exit(0)
