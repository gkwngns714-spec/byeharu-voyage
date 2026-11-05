// ═════════════════════════════════════════════════════════════════
// proof-0314.mjs — INSURANCE PAYS ITS WAY (migration 0314): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/insurance/proof-0314.mjs
//
// Restores the cached world at the head before 0314 (never from zero), then applies 0314 to it several times inside a transaction that is rolled back:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason;
//   POSITIVE CONTROL  - the real file, which must pass and print its receipt.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000314_insurance_pays_its_way.sql'
const failures = []
const say = (...a) => console.log(...a)

const names = await migrationFiles()
const files = []
for (const n of names) if (n !== NAME) files.push({ name: n, sql: await readFile(path.join(MIGRATIONS_DIR, n), 'utf8') })
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({
  variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false,
})
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored from the prefix cache, ${out.applied.filter((r) => !r.restored).length} applied here`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, to)
}

const TEST = `    if v_end <= 0 and v_bound < v.eta$h$;`

const MUTATIONS = [
  ['the guard stays d < v_cap (the bug itself)', (s) => swap(s, TEST, `    if v_end <= 0 and d < v_cap$h$;`),
    /a ship dry on the ETA did not arrive/],
  ['the test is on the stale eta of a day before: d + 1 < v_cap', (s) => swap(s, TEST, `    if v_end <= 0 and d + 1 < v_cap$h$;`),
    /a ship dry on the ETA did not arrive|a real dry day at sea is no longer a forced home/],
  ['never forced home at all', (s) => swap(s, TEST, `    if v_end <= 0 and false$h$;`),
    /a real dry day at sea is no longer a forced home/],
  ['forced home only with no delay', (s) => swap(s, TEST, `    if v_end <= 0 and v_bound < v.eta and v.delay_hours = 0$h$;`),
    /a real dry day at sea is no longer a forced home/],
  ['forced home on the ETA too: <= for <', (s) => swap(s, TEST, `    if v_end <= 0 and v_bound <= v.eta$h$;`),
    /a ship dry on the ETA did not arrive|a dry final day is no longer an arrival/],
  ['the test reads the eta as it stood before the delay', (s) => swap(s, TEST,
    `    if v_end <= 0 and v_bound < v.eta - make_interval(secs => (v.delay_hours * 3600 / public.wc_num('time_compression'))::double precision)$h$;`),
    /a real dry day at sea is no longer a forced home/],
  ['the scene does not run her dry, so it proves nothing', (s) => swap(s,
    `     set water_t = crew * public.wc_num('water_per_crew_day') * v_days, food_t = crew * public.wc_num('food_per_crew_day') * v_days`,
    `     set water_t = crew * public.wc_num('water_per_crew_day') * (v_days + 20), food_t = crew * public.wc_num('food_per_crew_day') * (v_days + 20)`),
    /the pre-image did not reproduce the bug|did not run dry/],
  ['the scene writes no delay, so no day is stacked', (s) => swap(s,
    `values (v_voy, 1, 'CALM', jsonb_build_object('delay_hours', v_calm), now());`,
    `values (v_voy, 1, 'CALM', jsonb_build_object('delay_hours', 0), now());`),
    /is not a stacked dry day|the probe's dry day is not a stacked day/],
  ['a hunk was cut against a body that is not the live one', (s) => swap(s,
    `$h$    -- A DRY FINAL DAY IS AN ARRIVAL, NOT A STRANDING: d < v_cap. voyage.day_ends_at clamps the\n`,
    `$h$    -- A DRY FINAL DAY  IS AN ARRIVAL, NOT A STRANDING: d < v_cap. voyage.day_ends_at clamps the\n`),
    /the hunk of voyage.settle occurs 0/],
  ['a hunk does not reverse: the new body gained a line no hunk knows', (s) => swap(s,
    `  v_def := replace(v_def0, v_old, v_new);\n  execute v_def;`,
    `  v_def := replace(v_def0, v_old, v_new);\n  execute replace(v_def, 'v_home    jsonb;', 'v_home    jsonb; -- drift');`),
    /does not reverse to its pre-image/],
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

const green0 = await attempt(file)
say(`\n${green0.ok ? 'GREEN' : 'FAIL'}  the real file first, ${Math.round(green0.ms)} ms\n    ${green0.ok ? green0.notices.filter((n) => /self-assert ok/.test(n)).join('\n    ') : green0.error}\n`)
if (!green0.ok) failures.push(`the real file: ${green0.error}`)

for (const [what, mutate, why] of MUTATIONS) {
  const r = await attempt(mutate(file))
  const good = !r.ok && why.test(r.error)
  if (!good) failures.push(what)
  say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 300)}`)
}

const green = await attempt(file)
if (!green.ok) failures.push(`the real file again: ${green.error}`)
say(`\n${green.ok ? 'GREEN' : 'FAIL'}  the real file after every mutation, ${Math.round(green.ms)} ms`)

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say(`\nall ${MUTATIONS.length} mutations red, the real file green`)
