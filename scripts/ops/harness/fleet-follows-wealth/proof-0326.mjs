// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// proof-0326.mjs — CARGO SHIPS FOLLOW WEALTH (migration 0326): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/fleet-follows-wealth/proof-0326.mjs [--first=a.sql,b.sql] [--no-mutations] [--with=18,19,20,30,32]
//
// Restores the cached world at the head before 0326 (never from zero), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 35 on the world with no file: it must fail;
//   POSITIVE CONTROL  - the real file followed by proof 35;
//   DEPLOY ORDER      - with --first, those files first, in that order;
//   OTHER PROOFS      - with --with, the listed proofs after the real file;
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 35 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000326_cargo_ships_follow_wealth.sql'
const PROOF = 'scripts/db/proofs/35_fleet_follows_wealth.sql'
const failures = []
const say = (...a) => console.log(...a)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const first = (process.argv.find((a) => a.startsWith('--first=')) ?? '--first=').slice(8).split(',').filter(Boolean)
const before = (await Promise.all(first.map((f) => readFile(f, 'utf8')))).join('\n').replaceAll('\r', '')
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, () => to)
}

async function attempt(...sqls) {
  const notes = []
  const onNotice = (n) => notes.push(n.message)
  await db.exec('begin')
  let err = null
  try {
    for (const sql of sqls) if (sql) await db.exec(sql, { onNotice })
  } catch (e) {
    err = e.message + (e.where ? ' @ ' + e.where.slice(0, 300) : '')
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes }
}

const MUTATIONS = [
  ['a straight line', (s) => swap(s, `* ln(greatest(c.cash::numeric, b.lo) / b.lo) / ln(b.hi / b.lo))::integer end`, `* (greatest(c.cash::numeric, b.lo) - b.lo) / (b.hi - b.lo))::integer end`), /PROOF 35 FAIL: the curve/],
  ['the log hangs on the poorest', (s) => swap(s, `greatest(min(c.cash)::numeric, max(c.cash)::numeric / public.wc_num('convoy_ships_span'), 1) as lo`, `greatest(min(c.cash)::numeric, 1) as lo`), /PROOF 35 FAIL: the curve/],
  ['the curve ignores min', (s) => swap(s, `case when b.hi <= b.lo then public.wc_int('convoy_ships_min')\n              else public.wc_int('convoy_ships_min')\n                   + round(`, `case when b.hi <= b.lo then public.wc_int('convoy_ships_min')\n              else 10\n                   + round(`), /PROOF 35 FAIL: the curve/],
  ['no dead band', (s) => s.replaceAll(`abs(excluded.ships - s.ships) > public.wc_int('convoy_ships_band')`, `abs(excluded.ships - s.ships) > 0`), /PROOF 35 FAIL: inside the band/],
  ['the band never lets go', (s) => s.replaceAll(`abs(excluded.ships - s.ships) > public.wc_int('convoy_ships_band')`, `abs(excluded.ships - s.ships) > 1000`), /PROOF 35 FAIL: past the band/],
  ['the band holds a number outside min..max', (s) => s.replaceAll(`\n                          or s.ships not between public.wc_int('convoy_ships_min') and public.wc_int('convoy_ships_max')`, '').replaceAll(`\n                           or s.ships not between public.wc_int('convoy_ships_min') and public.wc_int('convoy_ships_max')`, ''), /PROOF 35 FAIL: a number outside/],
  ['the curve is read every run', (s) => swap(s, `if (select min(s.read_at) from public.cargo_fleet_sizes s) > p_now - make_interval(mins => public.wc_int('convoy_size_read_minutes')) then`, `if false then`), /PROOF 35 FAIL: the curve was read inside/],
  ['commission has no cap', (s) => swap(s, `    exit when v_made >= public.wc_int('convoy_commission_per_run');\n`, ``), /PROOF 35 FAIL: a run is not capped/],
  ['a surplus ship may load', (s) => swap(s, `       and c.ord <= public.convoy_ships_of(c.nation_id)\n`, ``), /PROOF 35 FAIL: a surplus ship took a load/],
  ['lowest ord first', (s) => swap(s, `order by c.ord desc, c.nation_id loop`, `order by c.ord, c.nation_id loop`), /PROOF 35 FAIL: the retire took the wrong ship/],
  ['no cap on the retire', (s) => swap(s, `    exit when v_n >= v_max;\n`, ``), /PROOF 35 FAIL/],
  ['a loaded ship may retire', (s) => swap(s, `continue when not found or exists (select 1 from public.cargo_ship_aboard(r.fleet_id)) or public.npc_wrecked(r.fleet_id);`, `continue when not found;`), /PROOF 35 FAIL/],
  ['a ship with no home check retires at sea', (s) => swap(s, `and f.status = 'DOCKED' and f.port_id = c.home_port_id and c.out_load is null and c.circuit_id is null\n            order by c.ord desc`, `order by c.ord desc`), /PROOF 35 FAIL/],
  ['a laid-up ship stays on the map', (s) => swap(s, `$h$         'CARGO_SHIP'\n    from public.cargo_ships_in_service c\n$h$`, `$h$         'CARGO_SHIP'\n    from public.cargo_ships c\n$h$`), /PROOF 35 FAIL: a laid-up ship is still on the map/],
  ['a laid-up ship still steps', (s) => swap(s, `$h$  for r in select c.fleet_id from public.cargo_ships_in_service c join public.fleets f on f.id = c.fleet_id\n`, `$h$  for r in select c.fleet_id from public.cargo_ships c join public.fleets f on f.id = c.fleet_id\n`), /PROOF 35 FAIL/],
  ['a rise makes a new ship over a laid-up one', (s) => swap(s, `    update public.cargo_ships c set laid_up_at = null where c.nation_id = p_nation and c.ord = v_n and c.laid_up_at is not null;\n    if found then\n      v_made := v_made + 1;\n      continue;\n    end if;\n`, ``), /PROOF 35 FAIL/],
  ['a short country counts surplus ships', (s) => swap(s, `where c.nation_id = g.nation_id and c.ord <= public.convoy_ships_of(g.nation_id)) < public.convoy_ships_of(g.nation_id))`, `where c.nation_id = g.nation_id) < public.convoy_ships_of(g.nation_id))`), /PROOF 35 FAIL/],
  ['every idle ship steps every run', (s) => swap(s, `and ((c.ord + v_turn) % v_every = 0`, `and (true`), /PROOF 35 FAIL: one run in four/],
  ['a ship with a load waits her turn', (s) => swap(s, ` or c.out_load is not null or exists (select 1 from public.cargo_ship_aboard(c.fleet_id)))\n`, ` or c.out_load is not null)\n`), /PROOF 35 FAIL/],
  ['the flat number stands', (s) => swap(s, `  delete from public.world_config c where c.key = c_retired;\n`, ``), /0326 self-assert FAIL: the flat number/],
  ['a stale pre-image', (s) => swap(s, `$h$  for v_n in 1 .. public.wc_int('convoy_ships_per_nation') loop\n`, `$h$  for v_n in 1 ..  public.wc_int('convoy_ships_per_nation') loop\n`), /occurs 0 time/],
]

// RED FIRST
const red = await attempt(before, proof)
say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 120) : 'IT PASSED'}`)
if (!red.err) failures.push('proof 35 passed with no file')

// POSITIVE CONTROL
const t0 = Date.now()
const whole = await attempt(before, file, proof)
say(`whole: ${Date.now() - t0} ms`)
if (whole.err) failures.push(`proof 35 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => x.startsWith('PASS:') || /self-assert ok/.test(x))) say('  ', n)
if (whole.err) say('   ERROR', whole.err)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

// OTHER PROOFS
const others = (process.argv.find((a) => a.startsWith('--with=')) ?? '--with=').slice(7).split(',').filter(Boolean)
const all = await readdir('scripts/db/proofs')
for (const o of others) {
  const name = all.find((f) => f.startsWith(`${o}_`))
  const sql = (await readFile(path.join('scripts/db/proofs', name), 'utf8')).replaceAll('\r', '')
  const t = Date.now()
  const r = await attempt(before, file, sql)
  say(`proof ${name}: ${r.err ? 'FAILED ' + r.err.slice(0, 300) : 'ok'} (${Date.now() - t} ms)`)
  if (r.err) failures.push(`${name}: ${r.err}`)
}

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    const r = await attempt(before, mutate(file), proof)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 260)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
const ran = process.argv.includes('--no-mutations') ? 'mutations NOT run' : `${MUTATIONS.length} mutations red`
if (failures.length) {
  say(`\nFAILED (${failures.length}):`)
  for (const f of failures) say('  -', f)
  process.exit(1)
}
say(`\nproof-0326 ok: red first, proof 35 green, ${ran}.`)
