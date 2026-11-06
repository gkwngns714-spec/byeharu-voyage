// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0331.mjs — A COUNTRY HAS A NAVY (migration 0331): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/navy/proof-0331.mjs [--no-mutations] [--cost] [--show]
//
// Restores the cached world at the head before 0331 (never from zero), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 37 on the world with no file: it must fail;
//   DARK PARITY       - the rich-cities, armed-cargo and navy scenes, on the world before the file and after it: every SCENE line must be equal, the map's reads byte for byte;
//   POSITIVE CONTROL  - the real file followed by proof 37;
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 37 right after it, for the intended reason;
//   --cost            - the job per call with 75 hulls on the probe world, what the dev-log's projection is scaled from.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000331_a_country_has_a_navy.sql'
const PROOF = 'scripts/db/proofs/37_a_country_has_a_navy.sql'
const SCENES = ['scripts/ops/harness/rich-cities/dark-scene.sql', 'scripts/ops/harness/armed-cargo/dark-scene.sql', 'scripts/ops/harness/navy/dark-scene.sql']
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

const MUTATIONS = (await import('./mutations-0331.mjs')).mutations(swap)

// RED FIRST
const red = await attempt(proof)
say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 120) : 'IT PASSED'}`)
if (!red.err) failures.push('proof 37 passed with no file')

// DARK PARITY
const lines = (r) => r.notes.filter((n) => n.startsWith('SCENE: '))
for (const [i, scene] of scenes.entries()) {
  const a = await attempt(scene)
  const b = await attempt(file, scene)
  if (a.err) failures.push(`scene ${i} before: ${a.err}`)
  if (b.err) failures.push(`scene ${i} after: ${b.err}`)
  say(`DARK PARITY ${SCENES[i]}: ${lines(a).length} scene lines before, ${lines(b).length} after`)
  if (process.argv.includes('--show')) for (const n of lines(a)) say('  ', n.slice(0, 200))
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
const whole = await attempt(file, proof)
say(`whole: ${Date.now() - t0} ms`)
if (whole.err) failures.push(`proof 37 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => /^(PASS:|SIM:|COST:)/.test(x) || /self-assert ok/.test(x))) say('  ', n)
if (whole.err) say('   ERROR', whole.err)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

if (process.argv.includes('--cost')) {
  const { cost } = await import('./cost-0331.mjs')
  await cost(db, file, say)
}

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected, how] of MUTATIONS) {
    let hit
    let got
    if (how === 'scene') {
      const a = await attempt(scenes[2])
      const b = await attempt(mutate(file), scenes[2])
      hit = lines(a).length > 0 && lines(a).some((n, j) => n !== lines(b)[j])
      got = 'the scene did not differ'
    } else {
      const r = await attempt(mutate(file), proof)
      hit = r.err && expected.test(r.err)
      got = (r.err ?? 'it passed').slice(0, 260)
    }
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${got}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
const ran = process.argv.includes('--no-mutations') ? 'mutations NOT run' : `${MUTATIONS.length} mutations red`
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, dark parity equal, the real file and proof 37 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
