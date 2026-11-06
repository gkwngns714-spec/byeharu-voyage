// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0324.mjs — RICH CITIES SEND THE SHIPS (migration 0324): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/rich-cities/proof-0324.mjs [--first=a.sql,b.sql] [--no-mutations]
//
// Restores the cached world at the head before 0324 (never from zero), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 32 on the world with no file: it must fail;
//   DARK PARITY       - dark-scene.sql on the world before the file and after it: every SCENE line must be equal;
//   POSITIVE CONTROL  - the real file followed by proof 32;
//   DEPLOY ORDER      - with --first, those files first, in that order (0323 is read from its branch this way);
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 32 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000324_rich_cities_send_the_ships.sql'
const PROOF = 'scripts/db/proofs/32_rich_cities.sql'
const SCENE = 'scripts/ops/harness/rich-cities/dark-scene.sql'
const failures = []
const say = (...a) => console.log(...a)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const scene = (await readFile(SCENE, 'utf8')).replaceAll('\r', '')
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
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes }
}

const MUTATIONS = [
  ['the rule ignores the knob', (s) => swap(s, `select public.convoys_on() and public.wc('convoy_rich_enabled') = 'true'::jsonb`, `select public.convoys_on()`), /PROOF 32 FAIL: off, a ship is not based at her capital/],
  ['the rule lights with no ships', (s) => swap(s, `select public.convoys_on() and public.wc('convoy_rich_enabled') = 'true'::jsonb`, `select public.wc('convoy_rich_enabled') = 'true'::jsonb`), /PROOF 32 FAIL/],
  ['the call still runs lit', (s) => swap(s, `$h$  if public.rich_cities_on() then   -- 0324: above the call, so lit it never runs\n    return jsonb_build_object('aided', 0, 'aid', 0, 'called', 0, 'donors', 0) || public.cargo_ships_load(v_short);\n  end if;\n  v_call := public.crown_call(v_short);\n  if public.convoys_on() then\n$h$`, `$h$  v_call := public.crown_call(v_short);\n  if public.convoys_on() then\n$h$`), /PROOF 32 FAIL: (lit, gold moved instantly|the load went past the donor's room)/],
  ['the capital stays out of the roster lit', (s) => swap(s, `(x.cap <> x.port_id or public.rich_cities_on());`, `(x.cap <> x.port_id or false);`), /PROOF 32 FAIL: she did not load the whole need/],
  ['a gift still calls lit', (s) => swap(s, `if v_from is not null and not public.rich_cities_on() then`, `if v_from is not null and true then`), /PROOF 32 FAIL: lit, a gift the capital cannot pay called/],
  ['the load ignores the donor room', (s) => swap(s, `              then case when public.port_nation(p_port) = p_nation then public.crown_call_room(p_port) else 0 end`, `              then case when public.port_nation(p_port) = p_nation then public.city_surplus(p_port) else 0 end`), /PROOF 32 FAIL: the load went past the donor's room/],
  ['a foreign flag may load', (s) => swap(s, `              then case when public.port_nation(p_port) = p_nation then public.crown_call_room(p_port) else 0 end`, `              then public.crown_call_room(p_port)`), /PROOF 32 FAIL: origins/],
  ['a busy donor is taken', (s) => swap(s, `continue when v_fleet is null or not public.treasury_try_lock(v_home);`, `continue when v_fleet is null;`), /PROOF 32 FAIL: a busy donor paid/],
  ['the load is written at the capital', (s) => swap(s, `$h$    perform public.convoy_book('LOADED', v_fleet, v_player, v_home, v_a);\n$h$`, `$h$    perform public.convoy_book('LOADED', v_fleet, v_player, k.cap, v_a);\n$h$`), /E_CITY_BROKE: .* cannot pay/],
  ['the realm need forgets what is aboard', (s) => swap(s, `cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.nation_id = v_nat),\n`, `cross join lateral public.cargo_ship_aboard(c.fleet_id) a where false),\n`), /PROOF 32 FAIL: what is aboard was not counted/],
  ['a ship with funds aboard may move her home', (s) => swap(s, `  if c.fleet_id is null or v_port is null or exists (select 1 from public.cargo_ship_aboard(p_fleet)) then\n`, `  if c.fleet_id is null or v_port is null then\n`), /PROOF 32 FAIL: a ship with funds aboard is due a move/],
  ['the capital is no stop', (s) => swap(s, `$h$    if v_lit and v_left > 0 and public.port_nation(f.port_id) = c.nation_id then   -- 0324: every city of her realm, the capital too: her home alone is not a stop\n$h$`, `$h$    if v_lit and v_left > 0 and public.port_nation(f.port_id) = c.nation_id and f.port_id <> public.realm_capital(c.nation_id) then\n$h$`), /PROOF 32 FAIL: the stops were not served/],
  ['the old test stands: a rich city\'s ship pays nobody', (s) => swap(s, `$h$    if v_lit and v_left > 0 and public.port_nation(f.port_id) = c.nation_id then   -- 0324: every city of her realm, the capital too: her home alone is not a stop\n$h$`, `$h$    if v_lit and v_left > 0 and public.city_capital(f.port_id) = c.home_port_id then --\n$h$`), /PROOF 32 FAIL: the stops were not served/],
  ['a ship astray raises for ever', (s) => swap(s, `$h$    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
    v_cir := c.circuit_id;`, `$h$    v_cir := c.circuit_id;`), /E_CARGO_NO_LEG/],
  ['the circuit ignores her home', (s) => swap(s, `v_cir := public.cargo_circuit_of(c.nation_id, c.home_port_id);   -- 0324: the circuit from her home`, `v_cir := public.cargo_circuit_of(c.nation_id, public.realm_capital(c.nation_id));`), /PROOF 32 FAIL/],
  ['a home that left the top goes at once', (s) => swap(s, `  if c.based_at is not null and public.rich_cities_on() then\n`, `  if false then\n`), /PROOF 32 FAIL: she moved before the idle wait was out/],
  ['the idle wait reads no book', (s) => swap(s, `v_since := greatest(c.based_at, (select b.created_at from public.convoy_cargo b where b.fleet_id = p_fleet order by b.id desc limit 1));`, `v_since := now() - interval '10 years';`), /PROOF 32 FAIL: she moved before the idle wait was out/],
  ['a home in the top moves her', (s) => swap(s, `  if c.home_port_id = any (v_o) then\n    return null;\n  end if;\n`, ``), /PROOF 32 FAIL|never/],
  ['a move is a teleport', (s) => swap(s, `  perform voyage.depart(p_fleet, voyage.segments_from_course(v_leg -> 'course'), p_port, v_to, p_now);\n`, `  update public.fleets set port_id = v_to where id = p_fleet;\n`), /PROOF 32 FAIL: ship 1 did not sail there/],
  ['her home waits for the arrival', (s) => swap(s, `     set home_port_id = v_to, based_at = case when public.rich_cities_on() then p_now end\n`, `     set based_at = case when public.rich_cities_on() then p_now end\n`), /PROOF 32 FAIL: ship 1 is not based round robin/],
  ['off she stays based', (s) => swap(s, `based_at = case when public.rich_cities_on() then p_now end\n   where x.fleet_id = p_fleet;`, `based_at = p_now\n   where x.fleet_id = p_fleet;`), /PROOF 32 FAIL: off, an idle ship did not sail back/],
  ['all ships to one origin', (s) => swap(s, `  return v_o[(c.ord - 1) % cardinality(v_o) + 1];\nend`, `  return v_o[1];\nend`), /PROOF 32 FAIL: ship 2 is not based round robin/],
  ['a commission ignores the origin', (s) => swap(s, `$h$    v_home := v_o[(v_n - 1) % cardinality(v_o) + 1];   -- 0324: round robin. Off, the capital\n`, `$h$    v_home := v_cap;\n`), /PROOF 32 FAIL: a ship made lit is not at her origin/],
  ['a circuit does not start at her home', (s) => swap(s, `  v_plan jsonb := public.cargo_circuit_plan(p_nation, p_start);\n  v_start uuid`, `  v_plan jsonb := public.cargo_circuit_plan(p_nation);\n  v_start uuid`), /PROOF 32 FAIL: a circuit from a rich city/],
  ['the capital is left off a rich circuit', (s) => swap(s, `(p.id = p_to or (p_to is null and public.city_capital(p.id) = v_cap)) order by p.code);`, `(p.id = p_to or (p_to is null and public.city_capital(p.id) = v_cap and p.id <> v_cap)) order by p.code);`), /PROOF 32 FAIL: a circuit from a rich city/],
  ['origins take the capital always', (s) => swap(s, `              then coalesce((select array_agg(y.id order by y.room desc, y.code)`, `              then array[public.realm_capital(p_nation)] || coalesce((select array_agg(y.id order by y.room desc, y.code)`), /PROOF 32 FAIL: the origins are not/],
  ['origins ignore the count', (s) => swap(s, `                                      limit public.wc_int('convoy_rich_ports')) y),`, `                                      limit 3) y),`), /PROOF 32 FAIL: origins/],
  ['an origin may have no course', (s) => swap(s, `                                        and exists (select 1 from public.npc_courses c where c.from_port = h.id or c.to_port = h.id)\n`, ``), /PROOF 32 FAIL: origins/],
  ['no capital when no room', (s) => swap(s, `                            array[public.realm_capital(p_nation)])\n              else`, `                            array[]::uuid[])\n              else`), /PROOF 32 FAIL: origins/],
  ['the capital is told nothing', (s) => swap(s, `$h$               and c.nation_id = public.port_nation(p_port) and c.home_port_id <> p_port   -- 0324: her realm, as her step pays it; a capital that is not her home is a stop\n$h$`, `$h$               and c.home_port_id = public.city_capital(p_port) and c.home_port_id <> p_port --\n$h$`), /PROOF 32 FAIL: the capital was not told/],
  ['the last hunk is off its line', (s) => swap(s, `$h$  v_s := array[(v_ix ->> v_cap::text)::int]\n`, `$h$  v_s := array[(v_ix ->>  v_cap::text)::int]\n`), /0324 self-assert FAIL: hunk 6 of public.cargo_circuit_plan/],
]

// RED FIRST
const red = await attempt(before, proof)
say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 120) : 'IT PASSED'}`)
if (!red.err) failures.push('proof 32 passed with no file')

// DARK PARITY
const lines = (r) => r.notes.filter((n) => n.startsWith('SCENE: '))
const a = await attempt(before, scene)
const b = await attempt(before, file, scene)
if (a.err) failures.push(`scene before: ${a.err}`)
if (b.err) failures.push(`scene after: ${b.err}`)
say(`DARK PARITY: ${lines(a).length} scene lines before, ${lines(b).length} after`)
for (const n of lines(a)) say('  ', n.slice(0, 180))
if (lines(a).length === 0 || lines(a).length !== lines(b).length) failures.push('scene line counts differ')
lines(a).forEach((n, i) => {
  if (n !== lines(b)[i]) {
    failures.push(`dark differs at scene line ${i}`)
    say('BEFORE', n.slice(0, 1500))
    say('AFTER ', (lines(b)[i] ?? '').slice(0, 1500))
  }
})

// POSITIVE CONTROL
const t0 = Date.now()
const whole = await attempt(before, file, proof)
say(`whole: ${Date.now() - t0} ms`)
if (whole.err) failures.push(`proof 32 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => x.startsWith('PASS:') || /self-assert ok/.test(x))) say('  ', n)
if (whole.err) say('   ERROR', whole.err)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

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
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, dark parity equal, the real file and proof 32 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
