// ═════════════════════════════════════════════════════════════════
// proof-0301.mjs — THE LAP HISTORY IS 100 (migration 0301): the populated-world proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/lap-keep/proof-0301.mjs
//
// What it does, all inside ONE transaction that is rolled back at the end (nothing persists, not even in the cached world):
//   1. restores the cached world at head 0300 (every migration but 0301), never from zero;
//   2. plants a populated world: 837 routes x 200 closed laps (+ 648 open laps) = prod's volume (167,587 rows), the `skipped` jsonb ~600 B, and ONE
//      real, valid probe route (a real house and fleet from public.new_house) with 205 closed laps and the open lap 206;
//   3. THE LAZY TRIM, with the REAL cmd.standing_route_close_lap (outside the migration, which never runs it):
//        control  - keep = 200 (as found): closing the probe's lap 206 trims the probe to 200 rows;
//        after the migration - keep = 100: the same close trims the probe to exactly 100 rows (laps 107..206) and the other 837 routes' lap rows
//        are byte-identical (one md5 over route, lap_no, net, before = after) - the close touches its own route only;
//   4. runs the REAL 0301 file on the populated world (timed), then again (re-runnable), then the GUARD against a knob at 150;
//   5. MUTATION CONTROLS: deliberate breakages of the file, each applied in a savepoint on the populated world and each required to FAIL its
//      self-assert for the intended reason; and a positive control that the unbroken file passes.
//
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000301_the_lap_history_is_100.sql'
const PROBE_AUTH = '00000000-0301-4000-8000-000000000001'
const PROBE_ROUTE = '00000000-0301-4000-8000-0000000000a1'
const PROBE_OPEN_LAP = '00000000-0301-4000-8000-0000000000b1'
const ROUTES = 837
const CLOSED_PER_ROUTE = 200
const OPEN_LAPS = 648

const t0 = Date.now()
const say = (...a) => console.log(...a)
const failures = []
const results = []

function expect(cond, what) {
  if (!cond) { failures.push(what); say(`  FAIL  ${what}`) } else say(`  ok    ${what}`)
  return cond
}

async function run(db, sql) {
  const notices = []
  const t = performance.now()
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
    return { ok: true, error: null, notices, ms: performance.now() - t }
  } catch (e) {
    return { ok: false, error: String(e?.message ?? e), notices, ms: performance.now() - t }
  }
}

const one = async (db, sql) => (await db.query(sql)).rows[0]

// ── 1. THE WORLD AT 0300 ──────────────────────────────────────────────────────────────────────
const names = await migrationFiles()
const files = []
for (const n of names) if (n !== NAME) files.push({ name: n, sql: await readFile(path.join(MIGRATIONS_DIR, n), 'utf8') })
const file0301 = await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')
const out = await applyWithPrefixCache({
  variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false,
})
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} migrations restored from the prefix cache, ${out.applied.filter((r) => !r.restored).length} applied here`)
expect(out.restored === files.length && out.applied.filter((r) => !r.restored).length === 0, 'the world is the cached 0300 prefix (nothing applied here)')

await db.exec('begin')

// ── 2. THE POPULATED WORLD ────────────────────────────────────────────────────────────────────
const tPlant = performance.now()
const made = await one(db, `select public.new_house('${PROBE_AUTH}'::uuid, 'Casa da Carreira', 'PRT') as pid`)
const PLAYER = made.pid
const house = await one(db, `select f.id as fleet from public.fleets f where f.player_id = '${PLAYER}'`)
await db.exec(`set local session_replication_role = replica`)
// the 837 planted routes (merchant-like: one planted owner, no fleet - only their lap rows matter here)
await db.exec(`
  insert into public.standing_routes (id, player_id, name, stop_cursor, lap_no, created_at, updated_at)
  select md5('plant-route-' || g)::uuid, '${PLAYER}'::uuid, 'Plant ' || lpad(g::text, 4, '0'), 0, ${CLOSED_PER_ROUTE + 1}, now(), now()
    from generate_series(1, ${ROUTES}) g`)
// closed laps 1..200 on each planted route, a 'skipped' of ~600 bytes, trades on the newest 7 only
await db.exec(`
  insert into public.standing_route_laps (id, route_id, lap_no, started_at, closed_at, stops_done, sold, bought, supplies, repairs, wages, net, skipped, stock_out, trades, taxes, insurance)
  select md5('plant-lap-' || r.g || '-' || l.n)::uuid, md5('plant-route-' || r.g)::uuid, l.n,
         now() - (${CLOSED_PER_ROUTE + 1} - l.n) * interval '2 hours' - interval '10 minutes', now() - (${CLOSED_PER_ROUTE + 1} - l.n) * interval '2 hours',
         4, 120000 + (l.n * 37) % 9000, 80000 + (l.n * 53) % 7000, 1200, 300, 900, 31000 + (l.n * 11) % 5000,
         jsonb_build_array(
           jsonb_build_object('port', 'LIS', 'verb', 'SELL', 'code', 'E_PRICE_LIMIT', 'line', 'SELL good_' || (l.n % 40), 'sentence', repeat('x', 130)),
           jsonb_build_object('port', 'FNC', 'verb', 'BUY', 'code', 'E_PRICE_LIMIT', 'line', 'BUY good_' || ((l.n + 7) % 40), 'sentence', repeat('y', 130)),
           jsonb_build_object('port', 'CAD', 'verb', 'SELL', 'code', 'E_PRICE_LIMIT', 'line', 'SELL good_' || ((l.n + 11) % 40), 'sentence', repeat('z', 130))),
         90000 + l.n,
         case when l.n > ${CLOSED_PER_ROUTE - 7} then '[["LIS",[["wine",20,2400]],[["spice",10,900]]]]'::jsonb end,
         700, 0
    from generate_series(1, ${ROUTES}) r(g) cross join generate_series(1, ${CLOSED_PER_ROUTE}) l(n)`)
// the open lap 201 on 648 of them
await db.exec(`
  insert into public.standing_route_laps (id, route_id, lap_no, started_at)
  select md5('plant-open-' || g)::uuid, md5('plant-route-' || g)::uuid, ${CLOSED_PER_ROUTE + 1}, now() - interval '5 minutes'
    from generate_series(1, ${OPEN_LAPS}) g`)
// THE PROBE: a real house and fleet, a route with 205 closed laps and the open lap 206
await db.exec(`
  insert into public.standing_routes (id, player_id, name, fleet_id, stop_cursor, lap_no, lap_id, created_at, updated_at)
  values ('${PROBE_ROUTE}', '${PLAYER}', 'Wine run', '${house.fleet}', 0, 206, '${PROBE_OPEN_LAP}', now(), now())`)
await db.exec(`
  insert into public.standing_route_laps (id, route_id, lap_no, started_at, closed_at, stops_done, sold, bought, supplies, repairs, wages, net, skipped, stock_out, taxes, insurance)
  select md5('probe-lap-' || l.n)::uuid, '${PROBE_ROUTE}', l.n, now() - (207 - l.n) * interval '20 minutes' - interval '10 minutes', now() - (207 - l.n) * interval '20 minutes',
         4, 120000, 80000, 1200, 300, 900, 31000, '[]'::jsonb, 90000, 700, 0
    from generate_series(1, 205) l(n)`)
await db.exec(`
  insert into public.standing_route_laps (id, route_id, lap_no, started_at, stops_done)
  values ('${PROBE_OPEN_LAP}', '${PROBE_ROUTE}', 206, now() - interval '5 minutes', 2)`)
await db.exec(`set local session_replication_role = origin`)
const plantMs = performance.now() - tPlant
const pop = await one(db, `select count(*)::int as laps, count(distinct route_id)::int as routes, count(*) filter (where closed_at is null)::int as open,
  pg_size_pretty(pg_relation_size('public.standing_route_laps')) as heap, pg_size_pretty(pg_indexes_size('public.standing_route_laps')) as idx,
  round(pg_relation_size('public.standing_route_laps')::numeric / count(*)) as heap_b_per_row,
  round(avg(pg_column_size(skipped))) as skipped_b from public.standing_route_laps`)
say(`planted in ${(plantMs / 1000).toFixed(1)} s: ${pop.laps} lap rows over ${pop.routes} routes (${pop.open} open), heap ${pop.heap} (${pop.heap_b_per_row} B a row), indexes ${pop.idx}, skipped ${pop.skipped_b} B`)
expect(pop.laps >= 167000 && pop.routes === ROUTES + 1, 'the world is populated at prod volume (>= 167,000 lap rows over 838 routes)')

const keepNow = async () => (await one(db, `select value::text as v from public.world_config where key = 'standing_route_lap_keep'`)).v
const probeCount = async () => (await one(db, `select count(*)::int as n from public.standing_route_laps where route_id = '${PROBE_ROUTE}'`)).n
const othersDigest = async () => (await one(db, `select md5(string_agg(x.route_id::text || ':' || x.lap_no || ':' || x.net, ',' order by x.route_id, x.lap_no)) as d, count(*)::int as n
  from public.standing_route_laps x where x.route_id <> '${PROBE_ROUTE}'`))
const closeProbe = async () => {
  const r = await run(db, `select cmd.standing_route_close_lap('${PROBE_ROUTE}'::uuid, now())`)
  return r
}
expect((await keepNow()) === '200', 'the knob reads 200 before the migration')

// ── 3a. THE CONTROL: keep = 200, the close trims the probe to 200 ─────────────────────────────
const others0 = await othersDigest()
await db.exec('savepoint control')
const c200 = await closeProbe()
expect(c200.ok, `[control, keep 200] the real cmd.standing_route_close_lap ran (${c200.error ?? 'ok'})`)
const n200 = await probeCount()
const others200 = await othersDigest()
expect(n200 === 200, `[control, keep 200] one close trims the probe route from 206 rows to ${n200} (laps 7..206)`)
expect(others200.d === others0.d && others200.n === others0.n, `[control, keep 200] the other ${others0.n} lap rows are byte-identical after the close (md5 ${others0.d.slice(0, 8)})`)
await db.exec('rollback to savepoint control')
expect((await probeCount()) === 206, 'the savepoint is back: the probe holds 206 rows again')

// ── 4. THE REAL FILE ON THE POPULATED WORLD ───────────────────────────────────────────────────
await db.exec('savepoint pristine')
const real = await run(db, file0301)
const receipt = real.notices.find((n) => n.startsWith('0301 self-assert ok')) ?? null
expect(real.ok && receipt, `the real 0301 file passes on the populated world (${real.ms.toFixed(0)} ms wall; ${real.error ?? 'no error'})`)
const printed = receipt?.match(/Printed, never asserted: (\d+) ms/)?.[1]
say(`  self-assert printed ${printed} ms; whole file ${real.ms.toFixed(0)} ms (guard + update + assert + resets) on ${pop.laps} lap rows`)
say(`  receipt: ${receipt?.slice(0, 220)} ...`)
results.push({ populatedFileMs: Math.round(real.ms), printedMs: Number(printed) })
expect((await keepNow()) === '100', 'the knob reads exactly 100 after the migration')
const row = await one(db, `select description, updated_at > now() - interval '1 minute' as fresh from public.world_config where key = 'standing_route_lap_keep'`)
expect(row.fresh && row.description.includes('100 would be good'), 'updated_at moved to now() and the description carries the owner order')
const nUntouched = (await one(db, `select count(*)::int as n from public.standing_route_laps`)).n
expect(nUntouched === pop.laps, `the migration deleted and inserted no lap row (${nUntouched} = ${pop.laps})`)

// ── 3b. AFTER THE MIGRATION: keep = 100, the close trims the probe to 100, touching no other route ─
await db.exec('savepoint after')
const c100 = await closeProbe()
expect(c100.ok, `[keep 100] the real cmd.standing_route_close_lap ran (${c100.error ?? 'ok'})`)
const n100 = await probeCount()
const others100 = await othersDigest()
expect(n100 === 100, `[keep 100] one close trims the probe route from 206 rows to ${n100} (laps 107..206)`)
const range = await one(db, `select min(lap_no)::int as lo, max(lap_no)::int as hi from public.standing_route_laps where route_id = '${PROBE_ROUTE}'`)
expect(range.lo === 107 && range.hi === 206, `[keep 100] the kept laps are ${range.lo}..${range.hi}`)
expect(others100.d === others0.d && others100.n === others0.n, `[keep 100] the other ${others0.n} lap rows are byte-identical after the close (md5 ${others0.d.slice(0, 8)}): no other route is touched`)
const totalAfter = (await one(db, `select count(*)::int as n from public.standing_route_laps`)).n
expect(totalAfter === pop.laps - 106, `[keep 100] the table lost exactly the probe's 106 rows (${pop.laps} -> ${totalAfter})`)
// a second route would trim at ITS OWN next close; show the lazy rule on the table: every other route still holds its 200-201 rows now
const still = await one(db, `select max(c)::int as mx, min(c)::int as mn from (select count(*) c from public.standing_route_laps where route_id <> '${PROBE_ROUTE}' group by route_id) x`)
expect(still.mx >= 200, `[keep 100] the other routes still hold ${still.mn}..${still.mx} rows each - they trim lazily, at their own next close`)
await db.exec('rollback to savepoint after')

// ── 4b. RE-RUNNABLE, AND THE GUARD ────────────────────────────────────────────────────────────
const again = await run(db, file0301)
expect(again.ok && again.notices.some((n) => n.includes('already reads 100')) && again.notices.some((n) => n.startsWith('0301 self-assert ok')),
  `the file is re-runnable with the knob at 100 (passes, says "already reads 100"; ${again.ms.toFixed(0)} ms)`)
await db.exec(`update public.world_config set value = to_jsonb(150) where key = 'standing_route_lap_keep'`)
const g150 = await run(db, file0301)
expect(!g150.ok && g150.error.includes('0301 refuses: standing_route_lap_keep reads 150'), `the guard refuses a knob at 150 (${g150.error?.split('\n')[0].slice(0, 110)})`)
await db.exec('rollback to savepoint pristine')
expect((await keepNow()) === '200', 'back to the pristine populated world: the knob reads 200 again')

// ── 5. MUTATION CONTROLS ──────────────────────────────────────────────────────────────────────
const AFTER_UPDATE = 'v_moved := true;'
const inject = (stmt) => {
  if (file0301.split(AFTER_UPDATE).length !== 2) throw new Error('the injection point is not exactly once in the file')
  return file0301.replace(AFTER_UPDATE, `${AFTER_UPDATE}\n    ${stmt}`)
}
const mutations = [
  ['M1  wrong value (101)', () => { const r = /\n(\s+)set value\s+= to_jsonb\(100\),\n(\s+)description/; if (!r.test(file0301)) throw new Error('M1 target'); return file0301.replace(r, (m, a, b) => `\n${a}set value = to_jsonb(101),\n${b}description`) }, 'does not read exactly 100'],
  ['M2a sibling knob moved (trades_keep 7 -> 8)', () => inject(`update public.world_config set value = to_jsonb(8), updated_at = now() where key = 'standing_route_lap_trades_keep';`), 'the sibling knob standing_route_lap_trades_keep moved'],
  ['M2b another knob moved (game_day_seconds)', () => inject(`update public.world_config set value = to_jsonb(61) where key = 'game_day_seconds';`), 'a world_config row other than standing_route_lap_keep moved'],
  ['M2c another knob\'s description touched', () => inject(`update public.world_config set description = description || ' ' where key = 'game_day_seconds';`), 'a world_config row other than standing_route_lap_keep moved'],
  ['M3  a function moved (public.wc search_path)', () => inject(`alter function public.wc(text) set search_path = public, pg_temp, pg_catalog;`), 'a function in public/cmd/world/voyage moved'],
  ['M4  an owner switch flipped (city_treasury_enabled)', () => inject(`update public.world_config set value = case when value = 'true'::jsonb then 'false'::jsonb else 'true'::jsonb end where key = 'city_treasury_enabled';`), 'a world_config row other than standing_route_lap_keep moved'],
  ['M5a the laps table read (a sequential scan, one row)', () => inject(`perform 1 from public.standing_route_laps limit 1;`), 'this file touched public.standing_route_laps'],
  ['M5b the laps table counted (an index-only scan)', () => inject(`perform count(*) from public.standing_route_laps;`), 'this file touched public.standing_route_laps'],
  ['M5c the laps table probed (an index scan that finds nothing)', () => inject(`perform 1 from public.standing_route_laps where route_id = '00000000-0000-0000-0000-000000000000'::uuid;`), 'this file touched public.standing_route_laps'],
  ['M5d the laps table written (a delete that finds nothing)', () => inject(`delete from public.standing_route_laps where route_id = '00000000-0000-0000-0000-000000000000'::uuid;`), 'this file touched public.standing_route_laps'],
  ['M6  a wall moved (anon may insert into world_config)', () => inject(`grant insert on public.world_config to anon;`), 'a wall moved'],
  ['M8  the closer stops reading the knob (a literal 200)', () => inject(`execute replace(pg_get_functiondef('cmd.standing_route_close_lap(uuid,timestamptz)'::regprocedure), 'public.wc_int(''standing_route_lap_keep'')', '200');`), 'the readers of the knob are'],
  ['M9  the closer trims every route, not its own (route_id dropped from the delete)', () => inject(`execute replace(pg_get_functiondef('cmd.standing_route_close_lap(uuid,timestamptz)'::regprocedure), 'where x.route_id = p_route and x.lap_no <= l.lap_no - public.wc_int(''standing_route_lap_keep'')', 'where x.lap_no <= l.lap_no - public.wc_int(''standing_route_lap_keep'')');`), 'the lap closer no longer trims one route at a time'],
  ['M7  a second reader of the knob appears', () => inject(`create function public.zz_second_reader() returns int language sql stable as $f$ select public.wc_int('standing_route_lap_keep') $f$;`), 'the readers of the knob are'],
]
for (const [label, make, want] of mutations) {
  await db.exec('savepoint m')
  const text = make()
  const r = await run(db, text)
  const caught = !r.ok && r.error.includes(want)
  expect(caught, `${label}: ${r.ok ? 'NOT CAUGHT (the file passed)' : 'fails with "' + r.error.split('\n')[0].replace(/^.*?: /, '').slice(0, 100) + '"'}${caught ? '' : '  (wanted: ' + want + ')'}`)
  results.push({ mutation: label, caught, error: r.error?.split('\n')[0].slice(0, 160) ?? null })
  await db.exec('rollback to savepoint m')
  await db.exec('release savepoint m')
}
// positive control: the unbroken file still passes after all that (the savepoints left the world pristine)
const clean = await run(db, file0301)
expect(clean.ok, 'positive control: the unbroken file passes on the pristine populated world')

await db.exec('rollback')
const after = await one(db, `select count(*)::int as n from public.standing_route_laps`)
expect(after.n === 0, `the whole proof rolled back (the cached world holds ${after.n} lap rows)`)
say(`\n${failures.length === 0 ? 'PROOF PASSED' : 'PROOF FAILED: ' + failures.length + ' check(s)'} in ${((Date.now() - t0) / 1000).toFixed(1)} s`)
say(JSON.stringify({ populated: pop, plantMs: Math.round(plantMs), results }))
process.exit(failures.length === 0 ? 0 : 1)
