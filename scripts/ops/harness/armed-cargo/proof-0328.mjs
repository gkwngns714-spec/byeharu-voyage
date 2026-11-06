// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0328.mjs — THE CARGO SHIP IS ARMED (migration 0328): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/armed-cargo/proof-0328.mjs [--first=a.sql,b.sql] [--no-mutations]
//
// Restores the cached world at the head before 0328 (never from zero), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 34 on the world with no file: it must fail;
//   DARK PARITY       - 0324's dark scene and this slice's, on the world before the file and after it: every SCENE line must be equal;
//   POSITIVE CONTROL  - the real file followed by proof 34;
//   DEPLOY ORDER      - with --first, those files first, in that order (0325 and 0327 are read from their branches this way);
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 34 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000328_the_cargo_ship_is_armed.sql'
const PROOF = 'scripts/db/proofs/34_armed_cargo.sql'
const SCENES = ['scripts/ops/harness/rich-cities/dark-scene.sql', 'scripts/ops/harness/armed-cargo/dark-scene.sql']
const failures = []
const say = (...a) => console.log(...a)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const scenes = await Promise.all(SCENES.map(async (s) => (await readFile(s, 'utf8')).replaceAll('\r', '')))
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
  ['the rule ignores the knob', (s) => swap(s, `select public.convoys_on() and public.wc('convoy_armed_enabled') = 'true'::jsonb`, `select public.convoys_on()`), /PROOF 34 FAIL: off, something is armed/],
  ['the rule lights with no ships', (s) => swap(s, `select public.convoys_on() and public.wc('convoy_armed_enabled') = 'true'::jsonb`, `select public.wc('convoy_armed_enabled') = 'true'::jsonb`), /PROOF 34 FAIL: with no ships sailing the knob lit something/],
  ['armed means the switch, not the hull', (s) => swap(s, `select exists (select 1 from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = p_fleet and k.attack > 0)`, `select public.cargo_armed_on()`), /PROOF 34 FAIL/],
  ['the class stays the old one', (s) => swap(s, `select case when public.cargo_armed_on() then public.wc_text('convoy_armed_class') else public.wc_text('convoy_ship_class') end`, `select public.wc_text('convoy_ship_class')`), /PROOF 34 FAIL: lit, the class is/],
  ['a loaded ship is refitted at the quay', (s) => swap(s, `$h$    if v_load is null then
      perform public.cargo_hull(p_fleet);   -- 0328: idle at home, no load: the one moment her hull may change
`, `$h$    perform public.cargo_hull(p_fleet);
    if v_load is null then
`), /PROOF 34 FAIL: lit, a loaded ship was touched at the quay/],
  ['the refit never happens', (s) => swap(s, `      perform public.cargo_hull(p_fleet);   -- 0328: idle at home, no load: the one moment her hull may change\n`, ``), /PROOF 34 FAIL: her lap closed and she was not refitted/],
  ['a refit leaves the old hull', (s) => swap(s, `  delete from public.ships x where x.id = s.id;\n`, ``), /E_FLEET_SHIP_MAX|one_flagship|duplicate|unique/i],
  ['a refit crews her free', (s) => swap(s, `perform public.commission_ship(s.player_id, p_fleet, v_class, s.name, true, false);`, `perform public.commission_ship(s.player_id, p_fleet, v_class, s.name, true, true);`), /PROOF 34 FAIL: ship 3 is not a fresh armed hull/],
  ['a refit loses her name', (s) => swap(s, `perform public.commission_ship(s.player_id, p_fleet, v_class, s.name, true, false);`, `perform public.commission_ship(s.player_id, p_fleet, v_class, 'Armed', true, false);`), /PROOF 34 FAIL: the refit changed who she is/],
  ['hands vanish at a refit', (s) => swap(s, `  if s.crew > 0 then\n    update public.ports p set crew_pool = p.crew_pool + s.crew where p.id = (select f.port_id from public.fleets f where f.id = p_fleet);\n  end if;\n`, ``), /PROOF 34 FAIL: off, she did not go back/],
  ['a commission keeps the old class', (s) => swap(s, `perform public.commission_ship(v_player, v_fleet, public.cargo_class(), format('Cargo ship %s', v_n), true, false);   -- 0328: the class she should be`, `perform public.commission_ship(v_player, v_fleet, public.wc_text('convoy_ship_class'), format('Cargo ship %s', v_n), true, false);   -- 0328: the class she should be`), /PROOF 34 FAIL: a new ship is/],
  ['the leg passes no upkeep', (s) => swap(s, `  perform public.cargo_upkeep(p_fleet, f.port_id);   -- 0328: hands, stores, her origin pays. No guns: one read\n  perform voyage.depart`, `  perform voyage.depart`), /PROOF 34 FAIL: she left with/],
  ['the rebase leg passes no upkeep', (s) => swap(s, `  perform public.cargo_upkeep(p_fleet, p_port);   -- 0328: this leg too, or an armed ship sails it with no stores\n  perform voyage.depart`, `  perform voyage.depart`), /PROOF 34 FAIL: a rebase leg passed no upkeep/],
  ['she owes a wage', (s) => swap(s, `  if v_crew > 0 and public.fleet_kind(p_fleet) = 'CARGO_SHIP' then\n    return 0;\n  end if;\n`, ``), /PROOF 34 FAIL: (the lap left something owing|the wages)/],
  ['nobody owes a wage', (s) => swap(s, `  if v_crew > 0 and public.fleet_kind(p_fleet) = 'CARGO_SHIP' then\n`, `  if v_crew > 0 then\n`), /PROOF 34 FAIL: the wages/],
  ['no stores', (s) => swap(s, `    if s.water_t > 0 or s.food_t > 0 then\n`, `    if false then\n`), /PROOF 34 FAIL: she left with/],
  ['no hands', (s) => swap(s, `  perform public.fleet_hands(p_fleet, p_port);\n`, ``), /PROOF 34 FAIL: she left with/],
  ['the quay gives past its floor', (s) => swap(s, `  if v_short <= 0 or (public.crew_hire_cost(p_fleet, v_short) ->> 'normal')::int <= 0 then\n    return 0;\n  end if;\n  perform 1 from public.ports p where p.id = p_port for update;\n  v_hands := (public.crew_hire_cost(p_fleet, v_short) ->> 'normal')::int;`, `  if v_short <= 0 then\n    return 0;\n  end if;\n  perform 1 from public.ports p where p.id = p_port for update;\n  v_hands := least(v_short, (select p.crew_pool from public.ports p where p.id = p_port));`), /PROOF 34 FAIL: a quay at its floor gave hands/],
  ['the hands are not taken off the quay', (s) => swap(s, `  update public.ports p set crew_pool = p.crew_pool - v_hands where p.id = p_port;\n`, ``), /PROOF 34 FAIL: (the quay gave|a quay)/],
  ['a broke origin raises', (s) => swap(s, `  v_pay := least(public.wc_int('convoy_upkeep_per_leg')::bigint, greatest(public.city_surplus(v_home), 0));`, `  v_pay := public.wc_int('convoy_upkeep_per_leg')::bigint;`), /E_CITY_BROKE|PROOF 34 FAIL: a poor origin/],
  ['the upkeep breaks the reserve', (s) => swap(s, `greatest(public.city_surplus(v_home), 0));`, `greatest(public.treasury_balance(v_home), 0));`), /PROOF 34 FAIL: an origin paid out of its reserve/],
  ['a busy donor is taken', (s) => swap(s, `  if v_home is not distinct from p_port or not public.treasury_try_lock(v_home) then\n`, `  if v_home is not distinct from p_port then\n`), /PROOF 34 FAIL: a busy donor/],
  ['the upkeep is minted', (s) => swap(s, `  perform public.treasury_post(v_home, 'CONVOY_UPKEEP', -v_pay, null, null);\n`, ``), /PROOF 34 FAIL: (the lap moved the sum|the upkeep)/],
  ['the upkeep vanishes', (s) => swap(s, `  perform public.treasury_post(p_port, 'CONVOY_UPKEEP', v_pay, null, null);\n`, ``), /PROOF 34 FAIL: (the lap moved the sum|the upkeep)/],
  ['her origin pays herself', (s) => swap(s, `  if v_home is not distinct from p_port or not public.treasury_try_lock(v_home) then\n`, `  if not public.treasury_try_lock(v_home) then\n`), /PROOF 34 FAIL: the upkeep is not one moved knob/],
  ['the upkeep goes to the wrong harbour', (s) => swap(s, `  perform public.treasury_post(p_port, 'CONVOY_UPKEEP', v_pay, null, null);\n`, `  perform public.treasury_post(public.refit_yard(v_home), 'CONVOY_UPKEEP', v_pay, null, null);\n`), /PROOF 34 FAIL: the upkeep is not one moved knob/],
  ['the upkeep names a house', (s) => swap(s, `  perform public.treasury_post(v_home, 'CONVOY_UPKEEP', -v_pay, null, null);\n`, `  perform public.treasury_post(v_home, 'CONVOY_UPKEEP', -v_pay, (select f.player_id from public.fleets f where f.id = p_fleet), null);\n`), /PROOF 34 FAIL: an upkeep row names a house/],
  ['the kind is minted', (s) => swap(s, `values ('CONVOY_UPKEEP', 'moved', 'Cargo upkeep', 51)`, `values ('CONVOY_UPKEEP', 'minted', 'Cargo upkeep', 51)`), /0328 self-assert FAIL: CONVOY_UPKEEP is not a moved kind/],
  ['stores too few for the world', (s) => swap(s, `('convoy_store_days', to_jsonb(90),`, `('convoy_store_days', to_jsonb(30),`), /PROOF 34 FAIL: the longest leg/],
  ['the merchant refit gives no hands', (s) => swap(s, `  if public.fleet_kind(p_fleet) = 'MERCHANT' then\n    perform public.fleet_hands(p_fleet, v_home);\n  end if;\n$h$);`, `$h$);`), /DARK|.*/, 'scene'],
  ['a hunk is off its line', (s) => swap(s, `$h$  perform voyage.depart(p_fleet, l.segments, f.port_id, l.to_port, p_now);\n$h$,`, `$h$  perform voyage.depart(p_fleet,  l.segments, f.port_id, l.to_port, p_now);\n$h$,`), /0328 self-assert FAIL: hunk 3 of public.cargo_ship_step/],
]

// RED FIRST
const red = await attempt(before, proof)
say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 120) : 'IT PASSED'}`)
if (!red.err) failures.push('proof 34 passed with no file')

// DARK PARITY
const lines = (r) => r.notes.filter((n) => n.startsWith('SCENE: '))
for (const [i, scene] of scenes.entries()) {
  const a = await attempt(before, scene)
  const b = await attempt(before, file, scene)
  if (a.err) failures.push(`scene ${i} before: ${a.err}`)
  if (b.err) failures.push(`scene ${i} after: ${b.err}`)
  say(`DARK PARITY ${SCENES[i]}: ${lines(a).length} scene lines before, ${lines(b).length} after`)
  for (const n of lines(a)) say('  ', n.slice(0, 180))
  if (lines(a).length === 0 || lines(a).length !== lines(b).length) failures.push(`scene ${i} line counts differ`)
  lines(a).forEach((n, j) => {
    if (n !== lines(b)[j]) {
      failures.push(`dark differs in scene ${i} at line ${j}`)
      say('BEFORE', n.slice(0, 1500))
      say('AFTER ', (lines(b)[j] ?? '').slice(0, 1500))
    }
  })
}

// POSITIVE CONTROL
const t0 = Date.now()
const whole = await attempt(before, file, proof)
say(`whole: ${Date.now() - t0} ms`)
if (whole.err) failures.push(`proof 34 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => /^(PASS:|SIM:|SPEED:)/.test(x) || /self-assert ok/.test(x))) say('  ', n)
if (whole.err) say('   ERROR', whole.err)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected, how] of MUTATIONS) {
    let hit
    let got
    if (how === 'scene') {
      const a = await attempt(before, scenes[1])
      const b = await attempt(before, mutate(file), scenes[1])
      hit = lines(a).length > 0 && lines(a).some((n, j) => n !== lines(b)[j])
      got = 'the scene did not differ'
    } else {
      const r = await attempt(before, mutate(file), proof)
      hit = r.err && expected.test(r.err)
      got = (r.err ?? 'it passed').slice(0, 260)
    }
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${got}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
const ran = process.argv.includes('--no-mutations') ? 'mutations NOT run' : `${MUTATIONS.length} mutations red`
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, dark parity equal, the real file and proof 34 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
