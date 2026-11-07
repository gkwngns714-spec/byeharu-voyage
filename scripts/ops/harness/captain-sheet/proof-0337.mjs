// ═══════════════════════════════════════════════════════════════════════════════
// proof-0337.mjs — A CAPTAIN HAS A SHEET (migration 0337): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/captain-sheet/proof-0337.mjs [--no-mutations] [--cost] [--only=<text>] [--with=29,33]
//
// Restores the cached world at the head before 0337 (never from zero; the cache is only READ: nothing is written or pruned), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 44 on the world with no file: it must fail;
//   POSITIVE CONTROL  - the real file followed by proof 44, every marker it declares must appear;
//   --with            - the real file followed by each named proof (proofs that share its readers: 29 uses captains, 33 is the Levels read whose registry hunk this file copies);
//   MUTATION CONTROLS - deliberate breakages of the file, or of a live rule the proof leans on, each required to FAIL its self-assert or proof 44 for the intended reason;
//   --cost            - what one sheet costs on the local world (PGlite; prod is 3 to 10 times slower: the dev-log prints the prod figure, measured read only).
// The harness reads the migration from supabase/migrations; it does not edit it. PREFIX_DIR=<dir> reads a private copy of the cache instead of the shared one.

import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000337_a_captain_has_a_sheet.sql'
const PROOF = 'scripts/db/proofs/44_a_captain_has_a_sheet.sql'
const failures = []
const say = (...a) => console.log(...a)
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({
  variant: await preambleVariant(),
  files,
  cacheDir: process.env.PREFIX_DIR || PREFIX_CACHE_DIR,
  log: say,
  required: true,
  snapshots: false,
})
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
  try {
    await db.exec('rollback')
  } catch {
    /* already aborted */
  }
  return { err, notes }
}

const MUTATIONS = (await import('./mutations-0337.mjs')).mutations(swap)
const only = arg('only')

if (!only) {
  // RED FIRST
  const red = await attempt(proof)
  say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 140) : 'IT PASSED'}`)
  if (!red.err) failures.push('proof 44 passed with no file')

  // POSITIVE CONTROL
  const t0 = Date.now()
  const whole = await attempt(file, proof)
  say(`whole: ${Date.now() - t0} ms`)
  if (whole.err) failures.push(`proof 44 failed: ${whole.err}`)
  for (const n of whole.notes.filter((x) => /^(PASS:|COST:)/.test(x) || /self-assert ok/.test(x))) say('  ', n)
  if (whole.err) say('   ERROR', whole.err)
  const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
  const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
  if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)
  say(`markers declared ${want.length}, seen ${want.length - missing.length}`)
}

// THE PROOFS THAT SHARE ITS CODE
if (arg('with')) {
  const all = await readdir('scripts/db/proofs')
  for (const n of arg('with').split(',')) {
    const f = all.find((x) => x.startsWith(`${n}_`))
    const sql = (await readFile(path.join('scripts/db/proofs', f), 'utf8')).replaceAll('\r', '')
    const t = Date.now()
    const r = await attempt(file, sql)
    say(`WITH ${f}: ${r.err ? 'RED ' + r.err.slice(0, 400) : `green, ${r.notes.filter((x) => x.startsWith('PASS:')).length} markers`}, ${Date.now() - t} ms`)
    if (r.err) failures.push(`proof ${n}: ${r.err.slice(0, 300)}`)
  }
}

if (process.argv.includes('--cost')) {
  const { cost } = await import('./cost-0337.mjs')
  await cost(db, file, say)
}

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    if (only && !label.includes(only)) continue
    const r = await attempt(mutate(file), proof)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 260)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
const ran = process.argv.includes('--no-mutations') ? 'mutations NOT run' : `${MUTATIONS.length} mutations red`
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, the real file and proof 44 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
