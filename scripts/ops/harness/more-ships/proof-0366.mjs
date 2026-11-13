// proof-0366.mjs - MORE SHIPS (migration 0366): the red-first proof. LOCAL ONLY (PGlite); not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/more-ships/proof-0366.mjs
//
// Restores the cached world at the head before 0366 (never from zero), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 67 on the world with no file: it must fail;
//   POSITIVE CONTROL  - the real file followed by proof 67, and the old-rows digest of before.sql the same before and after the file;
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000366_more_ships_to_trade_carry_and_fight.sql'
const failures = []
const say = (...a) => console.log(...a)
const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile('scripts/db/proofs/67_more_ships.sql', 'utf8')).replaceAll('\r', '')
const before = (await readFile('scripts/ops/harness/more-ships/before.sql', 'utf8')).replaceAll('\r', '')
  .replace('(select max(version) from supabase_migrations.schema_migrations)', 'null').replace('begin transaction read only;', '').replace(/commit;\s*$/, '')
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: process.env.BYEHARU_PREFIX_CACHE === 'required', snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, () => to)
}
async function attempt(...sqls) {
  const notes = []
  let rows = null
  await db.exec('begin')
  let err = null
  try {
    for (const sql of sqls) if (sql) rows = await db.exec(sql, { onNotice: (n) => notes.push(n.message) })
  } catch (e) {
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes, rows }
}
const digestOf = (r) => JSON.parse(r.rows.at(-1).rows[0].j)

// RED FIRST
const red = await attempt(proof)
say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 110) : 'IT PASSED'}`)
if (!red.err) failures.push('proof 67 passed with no file')

// POSITIVE CONTROL
const d0 = digestOf(await attempt(before))
const good = await attempt(file, proof)
say(`POSITIVE CONTROL, the file then proof 67: ${good.err ? 'RED: ' + good.err.slice(0, 300) : `green, ${good.notes.filter((n) => n.startsWith('PASS:')).length} PASS markers`}`)
if (good.err) failures.push(`the real file or proof 67 is red: ${good.err}`)
const d1 = digestOf(await attempt(file, before))
say(`OLD ROWS ${d0.old_rows} -> ${d1.old_rows}; FUNCTIONS ${d0.functions} -> ${d1.functions}; classes ${d0.classes} -> ${d1.classes}`)
if (d0.old_rows !== d1.old_rows || d0.functions !== d1.functions || d1.classes !== d0.classes + 54) failures.push('before.sql reads a different old-rows or functions digest after the file')

// MUTATION CONTROLS: each breakage is put just before the self-assert, or into a row; each must fail for its reason
const MARK = '  -- ── 3. THE SELF-ASSERT: the catalogue and stable reads. No game step, no row but the catalogue\'s. ──\n'
const MUTATIONS = [
  ['an older hull\'s hold moved', (s) => swap(s, MARK, `  update public.ship_classes set hold = hold + 1 where code = 'xebec';\n${MARK}`), /that existed has moved/],
  ['an older recipe\'s material moved', (s) => swap(s, MARK, `  update public.hull_recipe_goods set qty = qty + 1 where class_code = 'nau' and good_id = (select good_id from public.hull_recipe_goods where class_code = 'nau' order by good_id limit 1);\n${MARK}`), /that existed has moved/],
  ['an older requirement moved', (s) => swap(s, MARK, `  delete from public.skill_requirements where subject_kind = 'hull' and subject_code = 'galeon' and skill_code = 'SHIPS_OF_WAR';\n${MARK}`), /that existed has moved/],
  ['a merchant is given a new hull', (s) => swap(s, MARK, `  update public.npc_line_hulls set class_code = 'chalupa' where live_class = 'barca' and line_code = 'ENG';\n${MARK}`), /that existed has moved/],
  ['a knob is written', (s) => swap(s, MARK, `  update public.world_config set value = to_jsonb('greatgalley'::text) where key = 'fight_raider_class';\n${MARK}`), /world_config row moved|golden probe|raiders are built differently/],
  ['the raiders\' class moved', (s) => swap(s, MARK, `  update public.ship_classes set attack = attack + 10, guns = guns + 1 where code = 'xebec';\n${MARK}`), /that existed has moved/],
  ['a function is re-cut', (s) => swap(s, MARK, `  execute 'comment on function public.hull_labour(text) is ''bent'''; execute 'alter function public.hull_labour(text) volatile';\n${MARK}`), /a function moved/],
  ['a new hull has the wrong wave resistance', (s) => swap(s, "'mixed', 50, 28, 90, 7.30, 390, 5, 1, 40.00, 184000.00, 2, 98, 3, 50, 46, 38, 14.0, 25)", "'mixed', 50, 28, 90, 7.30, 390, 5, 1, 40.00, 184000.00, 2, 98, 3, 50, 46, 38, 14.0, 26)"), /not a whole class/],
  ['a new hull\'s guns are not a tenth of her attack', (s) => swap(s, "'mixed', 50, 28, 90, 7.30, 390, 5, 1,", "'mixed', 50, 28, 90, 7.30, 390, 6, 1,"), /not a whole class/],
  ['a requirement row is dropped', (s) => swap(s, "  ('hull', 'balinger', 'ENG_LIGHT', 1),\n", ''), /new rows are not/],
  ['a material names no good', (s) => swap(s, "  ('balinger', 'tar', 11),", "  ('balinger', 'no-such-good', 11),"), /new rows are not/],
  ['a new hull takes an older hull\'s name', (s) => swap(s, "('balinger', 'Balinger',", "('balinger', 'Fusta',"), /two classes answer to one name/],
  ['a new hull may be built at any yard', (s) => swap(s, "  ('balinger', 'ENG', 2, 'combat', 'T1', 28, false)", "  ('balinger', 'ENG', 2, 'combat', 'T1', 28, true)"), /not a whole class/],
  ['a new hull asks another line\'s skill', (s) => swap(s, "  ('hull', 'balinger', 'ENG_LIGHT', 1),", "  ('hull', 'balinger', 'FRA_LIGHT', 1),"), /outside the hull's own ladder/],
  ['the file is applied twice', (s) => `${s}\n${s}`, /applied once/],
]
for (const [what, mutate, why] of MUTATIONS) {
  let text
  try { text = mutate(file) } catch (e) { failures.push(`${what}: ${e.message}`); say(`MUTATION ${what}: NOT APPLIED (${e.message.slice(0, 80)})`); continue }
  const r = await attempt(text)
  const ok = r.err !== null && why.test(r.err)
  say(`MUTATION ${what}: ${ok ? 'red, as intended' : r.err ? `red for another reason: ${r.err.slice(0, 200)}` : 'IT PASSED'}`)
  if (!ok) failures.push(`${what}: ${r.err ?? 'passed'}`)
}

await db.close()
if (failures.length) {
  say(`\nFAILED (${failures.length}):\n  ${failures.join('\n  ')}`)
  process.exitCode = 1
} else {
  say(`\nOK: red first, the file and proof 67 green, the old-rows and functions digests unmoved, ${MUTATIONS.length} mutations red for their reasons.`)
}
