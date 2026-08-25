// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0055.mjs — watch every guard in migration 0055 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7). This applies the chain up
// to but NOT including 0055 exactly once, then runs MUTATED copies of 0055 inside begin/rollback
// and records the REAL red message each of its asserts produces. A mutation that applies cleanly
// is reported as GREEN!! and fails the run — that is a guard that would never have caught anything.
//
//   node scripts/db/breaktest-0055.mjs               # every mutation
//   node scripts/db/breaktest-0055.mjs --clean       # apply 0055 unmutated, print its receipt
//   node scripts/db/breaktest-0055.mjs --only=<sub>  # one mutation, by a substring of its name
//
// It lives in scripts/, never in the migration: commit bfd37c7 of this repo is where a break-test
// harness was written INTO a migration and had to be taken out again.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000055_what_these_waters_breed.sql'
const sql = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')
const cleanOnly = process.argv.includes('--clean')
/** `--only=<substring>` re-runs one mutation without paying for the other seventeen. */
const only = (process.argv.find((a) => a.startsWith('--only=')) ?? '').slice('--only='.length)

const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of await migrationFiles()) {
  if (f >= LAST) continue
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n'))
}
console.log('chain applied up to (not including) 0055\n')

// ── the unmutated run: it must be GREEN, and its receipt is the measurement this file reports ──
{
  const notices = []
  await db.exec('begin')
  let red = null
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
  } catch (e) {
    red = String(e.message)
  }
  await db.exec('rollback').catch(() => {})
  if (red) {
    console.log(`UNMUTATED 0055 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0055: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// Each entry is [name, ...[find, replace]] — a mutation may need more than one hunk to be a LEGAL
// wrong migration rather than a syntax error, and a mutation that merely fails to compile proves
// nothing about the guard it was aimed at.
const NL = '\n'
const MUTATIONS = [
  ['(a) the slice is exactly one insertion, and nothing else in the payload moved',
    `                 'waters', voyage.waters_ahead(v.id),${NL}                 'position',`,
    `                 'waters', voyage.waters_ahead(v.id),${NL}                 'nm_done', 0,${NL}                 'position',`],

  // 0035's closure trigger is deferrable exactly so a legitimate rebalance can span statements.
  // Deferring it around the seed is what makes this a LEGAL wrong migration rather than a syntax
  // error — the only kind that tests anything — and it must be made IMMEDIATE again before §3b,
  // because a pending constraint trigger blocks an ALTER TABLE on the same table.
  ['(b) the draw is unmoved — a new kind is DRAWN, with the mix legally rebalanced around it',
    "  ('FAIR_WIND', 11, false, null, null, null,",
    "  ('FAIR_WIND', 11, true, 0.1000, null, null,",
    `insert into public.voyage_event_kinds${NL}  (code, ordinal, is_rolled, roll_weight, cedes_to, cede_fraction,`,
    `set constraints voyage_event_kinds_weights_close deferred;${NL}insert into public.voyage_event_kinds${NL}  (code, ordinal, is_rolled, roll_weight, cedes_to, cede_fraction,`,
    '-- ── 3b. THE GUARDS',
    "update public.voyage_event_kinds set roll_weight = 0.2500 where code = 'CALM';" + NL +
      'set constraints voyage_event_kinds_weights_close immediate;' + NL +
      '-- ── 3b. THE GUARDS'],

  ['(b) the draw is unmoved — the rolled weights are re-cut',
    "  mix_base = 0.2600, mix_danger = 0.0000, mix_raiders =  0.0000 where code = 'CALM';",
    "  mix_base = 0.2600, mix_danger = 0.0000, mix_raiders =  0.0000 where code = 'CALM';" +
      NL + "update public.voyage_event_kinds set roll_weight = 0.3000 where code = 'CALM';" +
      NL + "update public.voyage_event_kinds set roll_weight = 0.3000 where code = 'PIRATES';"],

  ['(c) control: a rolled kind may not sit outside the mix',
    `  add constraint voyage_event_kinds_rolled_is_in_the_mix${NL}    check (not is_rolled or in_sea_mix);`,
    `  add constraint voyage_event_kinds_rolled_is_in_the_mix${NL}    check (true);`],

  ['(c) control: a mix response may not be negative',
    "    check ((mix_danger is null or mix_danger >= 0) and (mix_raiders is null or mix_raiders >= 0)),",
    "    check (true),"],

  ['(d) the mix is total — one sea is dropped out of it',
    "    from public.seas s where s.id = p_sea;",
    "    from public.seas s where s.id = p_sea and s.code <> 'BAL';"],

  ['(d) the shares ARE the bands — a share that does not add up while the band still closes',
    "           round(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p) / v_tot, 6),",
    "           round(k.mix_base * (1 + k.mix_danger * v_d + k.mix_raiders * v_d * v_p) / v_tot * 0.9, 6),"],

  ['(e) the sea really decides — the responses are flattened',
    "  mix_base = 0.0350, mix_danger = 0.0000, mix_raiders = 30.0000 where code = 'PIRATES';",
    "  mix_base = 0.0350, mix_danger = 0.0000, mix_raiders =  0.0000 where code = 'PIRATES';"],

  ['(e) corsairs stay out of the Arctic — the raider term becomes a plain danger term',
    "  mix_base = 0.0350, mix_danger = 0.0000, mix_raiders = 30.0000 where code = 'PIRATES';",
    "  mix_base = 0.0350, mix_danger = 9.0000, mix_raiders =  0.0000 where code = 'PIRATES';"],

  ['(e) the mix is a DIFFERENT draw — it is re-authored back into 0035’s flat bands',
    "  mix_base = 0.3000, mix_danger = 1.2000, mix_raiders =  0.0000 where code = 'STORM';",
    "  mix_base = 0.2200, mix_danger = 0.0000, mix_raiders =  0.0000 where code = 'STORM';",
    "  mix_base = 0.2600, mix_danger = 0.0000, mix_raiders =  0.0000 where code = 'CALM';",
    "  mix_base = 0.3500, mix_danger = 0.0000, mix_raiders =  0.0000 where code = 'CALM';",
    "  mix_base = 0.0350, mix_danger = 0.0000, mix_raiders = 30.0000 where code = 'PIRATES';",
    "  mix_base = 0.4300, mix_danger = 0.0000, mix_raiders =  0.0000 where code = 'PIRATES';"],

  ['(f) the content reads itself — a new kind names a payload key nothing writes',
    "   array['stores_lost'], array['?'],",
    "   array['nobody_writes_this'], array['?'],"],

  ['(g) it is dark — waters_ahead starts reading the encounter',
    "  v_done := voyage.progress_nm(p_voyage);",
    `  v_done := voyage.progress_nm(p_voyage);${NL}  perform 1 from voyage.encounter_at(p_voyage, 1);`],

  ['(h) the waters are the whole of what is left — a run is dropped',
    "    continue when v_to[i] <= v_done;",
    "    continue when v_to[i] <= v_done or i > 1;"],

  ['(h) the panel prints the tier the mix reads — the danger is invented instead',
    "      'danger', s.danger_level,",
    "      'danger', 3,"],

  ['(h) a water with no name is refused rather than drawn',
    "    if s.id is null then",
    "    if false then"],

  ['(i) it stays a DROP-IN — the probability drifts away from voyage.hazard_roll’s',
    `  v_p := least(public.wc_num('hazard_p_max'),${NL}               greatest(0, v_base * (v_leg->>'hazard_mult')::numeric));`,
    `  v_p := least(public.wc_num('hazard_p_max'),${NL}               greatest(0, v_base * 1.5 * (v_leg->>'hazard_mult')::numeric));`],

  ['(j) the encounter never reads the clock',
    "  r_occur := voyage.rng(p_voyage, p_day, 'occur');",
    `  if now() > (select v2.departed_at + interval '300 hours' from public.voyages v2 where v2.id = p_voyage) then${NL}    p_day := p_day + 1;${NL}    v_leg := voyage.leg_at_day(p_voyage, p_day);${NL}  end if;${NL}  r_occur := voyage.rng(p_voyage, p_day, 'occur');`],

  ['(j) the encounter draws the SAME rng streams as the hazard it will replace',
    "  r_kind  := voyage.rng(p_voyage, p_day, 'kind');",
    "  r_kind  := voyage.rng(p_voyage, p_day, 'kind2');"],

  ['(l) the posture is unmoved',
    "revoke all on function voyage.encounter_at(uuid, int) from public, anon, authenticated;",
    "grant execute on function voyage.encounter_at(uuid, int) to authenticated;"],
]

let bad = 0
for (const [name, ...hunks] of MUTATIONS) {
  if (only && !name.includes(only)) continue
  let mutated = sql
  let missing = false
  for (let i = 0; i < hunks.length; i += 2) {
    if (!mutated.includes(hunks[i])) {
      missing = true
      break
    }
    mutated = mutated.replace(hunks[i], hunks[i + 1])
  }
  if (missing) {
    console.log(`SKIPPED  ${name} — mutation anchor not found, FIX THE SCRIPT`)
    bad += 1
    continue
  }
  await db.exec('begin')
  let red = null
  try {
    await db.exec(mutated)
  } catch (e) {
    red = String(e.message).split('\n')[0]
  }
  await db.exec('rollback').catch(() => {})
  if (!red) {
    console.log(`GREEN!!  ${name} — the mutation applied cleanly. THE GUARD IS DECORATION.`)
    bad += 1
  } else {
    console.log(`RED      ${name}\n         ${red.slice(0, 420)}`)
  }
}
console.log(bad === 0 ? '\nALL GUARDS BITE' : `\n${bad} GUARD(S) DID NOT BITE`)
process.exit(bad === 0 ? 0 : 1)
