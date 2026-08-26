// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0059.mjs — watch every guard in migration 0059 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7). This applies the chain up
// to but NOT including 0059 exactly once, then runs MUTATED copies of 0059 inside begin/rollback
// and records the REAL red message each of its asserts produces. A mutation that applies cleanly
// is reported as GREEN!! and fails the run — that is a guard that would never have caught anything.
//
//   node scripts/db/breaktest-0059.mjs               # every mutation
//   node scripts/db/breaktest-0059.mjs --clean       # apply 0059 unmutated, print its receipt
//   node scripts/db/breaktest-0059.mjs --only=<sub>  # one mutation, by a substring of its name
//
// The pre-0059 chain is CACHED as a PGlite data directory keyed on the bytes of every file before
// 0059, so re-running this costs seconds rather than the ten minutes the chain takes. A changed
// earlier migration changes the key, so the cache can never be stale.
//
// It lives in scripts/, never in the migration: commit bfd37c7 of this repo is where a break-test
// harness was written INTO a migration and had to be taken out again.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { tmpdir } from 'node:os'
import path from 'node:path'

const LAST = '20260818000059_the_sea_decides_what_it_breeds.sql'
const sql = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')
const cleanOnly = process.argv.includes('--clean')
const only = (process.argv.find((a) => a.startsWith('--only=')) ?? '').slice('--only='.length)

const { PGlite } = await import('@electric-sql/pglite')

// ── the cached pre-0059 world, keyed on the bytes that built it ───────────────────────────────
const before = (await migrationFiles()).filter((f) => f < LAST)
const preamble = await readFile(PREAMBLE_PATH, 'utf8')
const key = createHash('sha256').update(preamble)
const sources = []
for (const f of before) {
  const raw = (await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n')
  key.update(f).update(raw)
  sources.push(raw)
}
const cacheDir = path.join(tmpdir(), 'byeharu-voyage-breaktest')
const cacheFile = path.join(cacheDir, `pre-0059-${key.digest('hex').slice(0, 16)}.tar.gz`)

let db
if (existsSync(cacheFile)) {
  db = await PGlite.create({ loadDataDir: new Blob([await readFile(cacheFile)]) })
  console.log(`chain restored from cache: ${cacheFile}\n`)
} else {
  db = await new PGlite()
  await db.exec(preamble)
  for (const raw of sources) await db.exec(raw)
  await mkdir(cacheDir, { recursive: true })
  await writeFile(cacheFile, Buffer.from(await (await db.dumpDataDir('gzip')).arrayBuffer()))
  console.log(`chain applied up to (not including) 0059, cached to ${cacheFile}\n`)
}

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
    console.log(`UNMUTATED 0059 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0059: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// Each entry is [name, ...[find, replace]] — a mutation may need more than one hunk to be a LEGAL
// wrong migration rather than a syntax error, and a mutation that merely fails to compile proves
// nothing about the guard it was aimed at.
const MUTATIONS = [
  // (a) statement 1 is a MOVE, not a retype. Give hazard_roll a body of its own that happens to
  //     read the mix — legal SQL, correct-looking, and not encounter_at's text.
  ['(a) hazard_roll is encounter_at’s body character for character',
    `select pg_temp.recut('voyage.encounter_at(uuid, int)'::regprocedure, true,
  'FUNCTION voyage.encounter_at(p_voyage uuid, p_day integer)',
  'FUNCTION voyage.hazard_roll(p_voyage uuid, p_day integer)');`,
    `select pg_temp.recut('voyage.encounter_at(uuid, int)'::regprocedure, true,
  'FUNCTION voyage.encounter_at(p_voyage uuid, p_day integer)',
  'FUNCTION voyage.hazard_roll(p_voyage uuid, p_day integer)',
  E'  v_leg   jsonb;', E'  v_leg   jsonb;  -- a harmless-looking edit');`],

  // (a) ... and the deleted copy really has to go.
  ['(a) voyage.encounter_at is DELETED, not left beside the draw',
    `select pg_temp.recut('voyage.encounter_at(uuid, int)'::regprocedure, true,`,
    `select pg_temp.recut('voyage.encounter_at(uuid, int)'::regprocedure, false,`],

  // (b) the flat weight must not survive beside the mix.
  ['(b) the retired columns are gone',
    `alter table public.voyage_event_kinds
  drop column roll_weight,
  drop column cedes_to,
  drop column cede_fraction;`,
    `alter table public.voyage_event_kinds
  drop column cedes_to,
  drop column cede_fraction;
alter table public.voyage_event_kinds drop constraint voyage_event_kinds_weight_iff_rolled;`],

  // (b) a kind left out of the draw is a hazard silently deleted from the game.
  ['(b) every kind in the mix is drawn',
    `update public.voyage_event_kinds set is_rolled = true where in_sea_mix;`,
    `update public.voyage_event_kinds set is_rolled = true where in_sea_mix and code <> 'DERELICT';`],

  // (c) the measured cost. Re-tune one coefficient so raid-days do not fall the way 0055 measured.
  ['(c) the Barbary raid-days really fall',
    `update public.voyage_event_kinds set is_rolled = true where in_sea_mix;`,
    `update public.voyage_event_kinds set is_rolled = true where in_sea_mix;
update public.voyage_event_kinds set mix_raiders = 99 where code = 'PIRATES';`],

  // (d) the slice is exactly the three declared hunks and nothing else in the settlement moved.
  //     Aimed at STORM's arm — a part of the deployed body this file has no business touching —
  //     because a mutation INSIDE the insertion is invisible to a byte comparison by design.
  ['(d) nothing else in voyage.settle moved',
    `  E'    if v_delay > 0 then perform voyage.recompute_eta(v.id); end if;',
  E'    if v_delay <> 0 then perform voyage.recompute_eta(v.id); end if;');`,
    `  E'    if v_delay > 0 then perform voyage.recompute_eta(v.id); end if;',
  E'    if v_delay <> 0 then perform voyage.recompute_eta(v.id); end if;',
  E'      v_delay   := 36;   -- DESIGN B.6: +1.5 voyage-days',
  E'      v_delay   := 30;   -- DESIGN B.6: +1.5 voyage-days');`],

  // (f) the frequency of event-days must not move. Halve the clamp inside the moved body — legal
  //     SQL, a plausible-looking tuning edit, and it changes only HOW OFTEN something happens.
  ['(f) the event-day frequency did not move',
    `  'FUNCTION voyage.encounter_at(p_voyage uuid, p_day integer)',
  'FUNCTION voyage.hazard_roll(p_voyage uuid, p_day integer)');`,
    `  'FUNCTION voyage.encounter_at(p_voyage uuid, p_day integer)',
  'FUNCTION voyage.hazard_roll(p_voyage uuid, p_day integer)',
  E'  v_p := least(public.wc_num(''hazard_p_max''),',
  E'  v_p := least(0.5 * public.wc_num(''hazard_p_max''),');`],

  // (g) FAIR_WIND must give back exactly the hours it names — and never more than the voyage lost.
  ['(g) FAIR_WIND gives back exactly what it reports',
    `      v_delay   := -v_gain;
      v_payload := v_payload || jsonb_build_object('hours_gained', v_gain, 'delay_hours', v_delay);`,
    `      v_delay   := -v_gain;
      v_payload := v_payload || jsonb_build_object('hours_gained', v_gain * 2, 'delay_hours', v_delay);`],

  // (g) ... and it must never drive the voyage's total delay below zero (0006:67's CHECK).
  ['(g) a fair wind cannot outrun the schedule it is repairing',
    `      v_gain    := least(round((0.25 + 0.70 * h.magnitude) * 24, 2),
                         voyage.delay_before_day(v.id, d));`,
    `      v_gain    := round((0.25 + 0.70 * h.magnitude) * 24, 2) + 4800;`],

  // (g) FOUL_WATER takes exactly what it reports.
  ['(g) FOUL_WATER takes exactly the tuns it reports',
    `        v_stores := v_stores + v_lost;`,
    `        v_stores := v_stores + v_lost * 0.5;`],

  // (g) SHOAL_WATER takes exactly the durability it reports, and no hours.
  ['(g) SHOAL_WATER takes exactly the durability it reports',
    `      v_payload := v_payload || jsonb_build_object('hull_lost', v_hull);

    elsif h.occurred and h.kind in ('DERELICT', 'CONSORT') then`,
    `      v_payload := v_payload || jsonb_build_object('hull_lost', v_hull * 0.5);

    elsif h.occurred and h.kind in ('DERELICT', 'CONSORT') then`],

  // (g) DERELICT and CONSORT touch no ship at all.
  ['(g) DERELICT and CONSORT touch no ship at all',
    `      v_kind := h.kind;

    elsif h.occurred then`,
    `      v_kind := h.kind;
      update public.ships set durability = greatest(0, durability - 1) where fleet_id = p_fleet;

    elsif h.occurred then`],

  // (g) a drawn kind with no arm must RAISE, never be written down as a quiet watch. The `elsif
  //     h.occurred then` line is KEPT (deleting it would break DERELICT's arm instead) and so is
  //     the E_KIND_ARM token, so the slice guard does not speak first and this one has to.
  ['(g) a drawn kind with no arm is refused, not recorded',
    `      raise exception 'E_KIND_ARM: % befell voyage % on day % and voyage.settle has no arm for it — a drawn kind with no arm would be written down as a quiet watch', h.kind, v.id, d
        using errcode = 'P0001';`,
    `      -- E_KIND_ARM, softened to a shrug: exactly the failure §7C forbids.
      v_kind := 'CLEAR';`],

  // (e) statement 4: the panel's mix must be voyage.sea_mix's own numbers.
  ['(e) the panel carries the mix, and it is sea_mix’s own numbers',
    `      'mix',    (select jsonb_object_agg(m.kind_code, m.share) from voyage.sea_mix(s.id) m),$wn$);`,
    `      'mix',    (select jsonb_object_agg(m.kind_code, round(m.share * 2, 6)) from voyage.sea_mix(s.id) m),$wn$);`],

  // (h) the posture. A client must not be able to reach the draw.
  ['(h) the draw stays out of every client’s reach',
    `revoke all on function voyage.hazard_roll(uuid, int) from public, anon, authenticated;`,
    `grant execute on function voyage.hazard_roll(uuid, int) to authenticated;`],
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
    console.log(`RED      ${name}\n         ${red.slice(0, 460)}`)
  }
}
console.log(bad === 0 ? '\nALL GUARDS BITE' : `\n${bad} GUARD(S) DID NOT BITE`)
process.exit(bad === 0 ? 0 : 1)
