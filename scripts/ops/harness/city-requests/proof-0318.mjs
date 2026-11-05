// ═════════════════════════════════════════════════════════════════
// proof-0318.mjs — A DRAW READS THE MARKET ONCE (migration 0318): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/city-requests/proof-0318.mjs
//
// Restores the cached world (never from zero), then:
//   RED FIRST        - on the world as it is, a draw makes hundreds of works_factor calls, and the job's only stop is its clock;
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason;
//   POSITIVE CONTROL - the real file, dark and on a world set as prod is (lit, closed);
//   THE COST         - the old and the new draw, timed on this world (PGlite: the ratio, not the milliseconds, is the figure);
//   THE JOB          - as cron runs it, with real commits, at its count.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { BROWSER_VARIANT, IMAGE_CACHE_DIR } from '../../../db/build-image.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000318_a_draw_reads_the_market_once.sql'
const failures = []
const say = (...a) => console.log(...a)

const names = await migrationFiles()
const files = []
for (const n of names) if (n !== NAME) files.push({ name: n, sql: await readFile(path.join(MIGRATIONS_DIR, n), 'utf8') })
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
// PROOF_WORLD=browser: the world image's own prefix cache, for a machine whose preamble cache is short. Either way it stops rather than replay from far back (never a local from-zero replay).
const browser = process.env.PROOF_WORLD === 'browser'
const out = await applyWithPrefixCache({
  variant: browser ? BROWSER_VARIANT : await preambleVariant(), files, cacheDir: browser ? path.join(IMAGE_CACHE_DIR, 'prefix') : PREFIX_CACHE_DIR, log: say, required: true, snapshots: false,
  onProgress: (step) => { if (step.total - step.index > 5) throw new Error(`the cache is short: it would apply ${step.total - step.index} files; stopping`) },
})
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored from the prefix cache, ${out.applied.filter((r) => !r.restored).length} applied here`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, () => to)
}

const BEFORE_ASSERT = `  -- ── 4. THE SELF-ASSERT: hunks, grants, nothing else moved ──\n`
const addBeforeAssert = (s, sql) => swap(s, BEFORE_ASSERT, `${sql}\n${BEFORE_ASSERT}`)

const MUTATIONS = [
  ['the draw forgets the offered goods', (s) => swap(s, `     where o.good_id is null\n       and not public.culture_refuses(p.culture, g.culture_mask)\n$h$,\n$h$           public.daily`, `     where true\n       and not public.culture_refuses(p.culture, g.culture_mask)\n$h$,\n$h$           public.daily`), /the draw moved/],
  ['the draw forgets the works', (s) => swap(s, `  v_base   numeric := public.daily_cap_base(null::uuid, p_port);   -- 0318: read once, not once a good\n`, `  v_base   numeric := public.wc_num('daily_cap_fraction');   -- 0318: read once, not once a good\n`), /the draw moved/],
  ['the draw forgets the cap', (s) => swap(s, `     cross join lateral (select greatest(0, v_base * pg.stock_target) as cap) c\n`, `     cross join lateral (select 1000000000::numeric as cap) c\n`), /the draw moved/],
  ['the cap forgets the skill', (s) => swap(s, `         * (1 + public.player_skill_bonus(p_player, 'TRADE_CAP'))\n         * public.works_factor`, `         * public.works_factor`), /self-assert FAIL/],
  ['the cap forgets the works', (s) => swap(s, `         * public.works_factor(p_port, 'market', 'market_cap_per_level')   -- 0123\n$body$`, `$body$`), /the cap moved|the draw moved/],
  ['the draw still asks good by good', (s) => swap(s, `     cross join lateral (select greatest(0, v_base * pg.stock_target) as cap) c\n`, `     cross join lateral (select world.daily_cap_remaining(null::uuid, p_port, g.id) as cap) c\n`), /asks the cap good by good/],
  ['the base is asked once a good', (s) => swap(s, `(select greatest(0, v_base * pg.stock_target) as cap) c\n`, `(select greatest(0, public.works_factor(p_port, 'market', 'market_cap_per_level') * v_base / public.works_factor(p_port, 'market', 'market_cap_per_level') * pg.stock_target) as cap) c\n`), /asks the cap good by good/],
  ['the job has no count', (s) => swap(s, `    exit when v_tried >= v_posts;   -- 0318: a draw is cheap now, so the clock no longer holds the pace\n`, `    -- 0318 x\n`), /did not stop at its count|still asks/],
  ['the job counts one past', (s) => swap(s, `    exit when v_tried >= v_posts;   -- 0318: a draw is cheap`, `    exit when v_tried > v_posts;   -- 0318: a draw is cheap`), /did not stop at its count|still asks/],
  ['the knob is not three', (s) => swap(s, `('contract_wind_posts', to_jsonb(3),`, `('contract_wind_posts', to_jsonb(4),`), /the knob is not this file's/],
  ['the helper is open to clients', (s) => swap(s, `  revoke all on function public.daily_cap_base(uuid, uuid) from public, anon, authenticated;\n`, `  grant execute on function public.daily_cap_base(uuid, uuid) to authenticated;\n`), /a client can reach/],
  ['a hunk against another body', (s) => swap(s, `$h$     cross join lateral (select world.daily_cap_remaining(null::uuid, p_port, g.id) as cap) c\n`, `$h$     cross join lateral (select world.daily_cap_remaining(null::uuid,  p_port, g.id) as cap) c\n`), /occurs 0 time/],
  ['a live function was touched', (s) => addBeforeAssert(s,
    `  execute replace(replace(pg_get_functiondef('public.crown_call_room(uuid)'::regprocedure), E'\\r', ''), 'select greatest(0,', 'select greatest(0 ,');`),
    /another function moved/],
  ['a cron job moved', (s) => addBeforeAssert(s,
    `  if to_regclass('cron.job') is not null then execute $q$select cron.schedule('byeharu-voyage:contract-wind', '*/2 * * * *', 'call public.tick_contract_wind()')$q$; else v_cron_before := 'x'; v_cron_after := null; raise exception '0318 self-assert FAIL: a cron job moved'; end if;`),
    /a cron job moved/],
]

async function attempt(sql) {
  const notices = []
  const t = performance.now()
  await db.exec('begin')
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
    return { ok: true, error: null, notices, ms: performance.now() - t }
  } catch (e) {
    return { ok: false, error: String(e?.message ?? e), notices, ms: performance.now() - t }
  } finally {
    await db.exec('rollback')
  }
}

// THE COUNT AND THE COST, of one draw at one harbour
async function drawCost(label) {
  await db.exec('begin')
  await db.exec(`set local track_functions = 'all'`)
  const port = (await db.query(`select id from public.ports where kind = 'HARBOUR' order by code limit 1`)).rows[0].id
  const calls = async () => Number((await db.query(`select coalesce(pg_stat_get_xact_function_calls('public.works_factor(uuid,text,text)'::regprocedure), 0) as c`)).rows[0].c)
  const c0 = await calls()
  const t = performance.now()
  for (let s = 1; s <= 3; s++) await db.query(`select * from public.contract_draw($1, 1000 + $2::int, 1)`, [port, s])
  const ms = (performance.now() - t) / 3
  const c1 = await calls()
  await db.exec('rollback')
  say(`${label}: ${(c1 - c0) / 3} works_factor calls a draw, ${ms.toFixed(1)} ms a draw`)
  return { calls: (c1 - c0) / 3, ms }
}

// RED FIRST
const red = await drawCost('RED FIRST, the world as it is')
if (red.calls < 100) failures.push(`the world as it is should ask hundreds of times: ${red.calls}`)
const body = (await db.query(`select pg_get_functiondef('public.tick_contract_wind(boolean,uuid)'::regprocedure) as d`)).rows[0].d
if (/v_posts/.test(body)) failures.push('the job already has a count')
say(`RED FIRST, the job: ${/v_posts/.test(body) ? 'has a count' : 'its only stops are the clock and an empty list'}`)

const green0 = await attempt(file)
if (!green0.ok) {
  say(`FAIL  the real file, before any mutation: ${green0.error}`)
  await db.close()
  process.exit(1)
}
say(`the real file is green first, ${Math.round(green0.ms)} ms`)

for (const [what, mutate, why] of MUTATIONS) {
  const r = await attempt(mutate(file))
  const good = !r.ok && why.test(r.error)
  if (!good) failures.push(what)
  say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 220)}`)
}

const lit = await attempt(`
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  update public.world_config set value = to_jsonb(60) where key = 'game_day_seconds';
  ${file}`)
if (!lit.ok) failures.push(`the real file, lit: ${lit.error}`)
say(`${lit.ok ? 'GREEN' : 'FAIL'}  the real file on a lit, closed world, ${Math.round(lit.ms)} ms\n    ${lit.ok ? lit.notices.find((n) => n.includes('self-assert ok')) : lit.error}`)

try {
  await db.exec(file)
  const green = await drawCost('GREEN, the new draw')
  if (green.calls > 1) failures.push(`the new draw asks ${green.calls} times`)
  say(`the draw is ${(red.ms / green.ms).toFixed(1)} x cheaper here`)
  await db.exec(`update public.world_config set value = to_jsonb(30000) where key = 'contract_wind_ms'; update public.world_config set value = to_jsonb(0) where key = 'treasury_reserve_floor';`)
  await db.exec('call public.tick_contract_wind()')
  const r = (await db.query(`select (select receipt from public.contract_wind_runs order by at desc limit 1) as receipt, (select ms from public.contract_wind_runs order by at desc limit 1) as ms`)).rows[0]
  const good = r.receipt && r.receipt.tried === 3 && r.receipt.posted === 3 && r.receipt.failed === 0
  if (!good) failures.push(`the job with commits: ${JSON.stringify(r)}`)
  say(`${good ? 'GREEN' : 'FAIL'}  the job as cron runs it, a 30 s clock, real commits: ${JSON.stringify(r)}`)
} catch (e) {
  failures.push(`the job with commits: ${e?.message ?? e}`)
  say(`FAIL  the job with commits: ${e?.message ?? e}`)
}

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say(`\nall ${MUTATIONS.length} mutations red, the real file green`)
