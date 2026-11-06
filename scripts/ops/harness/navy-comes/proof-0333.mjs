// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0333.mjs — THE NAVY COMES (migration 0333): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/navy-comes/proof-0333.mjs [--no-mutations] [--cost] [--show]
//
// Restores the cached world at the head before 0333 (never from zero), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 40 on the world with no file: it must fail;
//   DARK PARITY       - the rich-cities, armed-cargo, navy and own scenes, on the world before the file and after it: every SCENE line must be equal;
//   POSITIVE CONTROL  - the real file followed by proof 40;
//   OLD PROOFS        - the real file followed by proofs 31, 34 and 37, which it re-cuts bodies under;
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 40 right after it, for the intended reason;
//   --w14=<dir>       - 0334's file and proof 41 from a copy of branch `wanted`, on top of this file: its hunks must land, proofs 40 and 41 green with the row itself;
//   --cost            - what a press costs with 24 hulls on the probe world, what the dev-log's figures come from.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000333_the_navy_comes.sql'
const PROOF = 'scripts/db/proofs/40_the_navy_comes.sql'
const OLD = ['scripts/db/proofs/31_battles.sql', 'scripts/db/proofs/34_a_player_attacks.sql', 'scripts/db/proofs/37_a_country_has_a_navy.sql']
const SCENES = ['scripts/ops/harness/rich-cities/dark-scene.sql', 'scripts/ops/harness/armed-cargo/dark-scene.sql', 'scripts/ops/harness/navy/dark-scene.sql', 'scripts/ops/harness/navy-comes/dark-scene.sql']
const failures = []
const say = (...a) => console.log(...a)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const text = async (f) => (await readFile(f, 'utf8')).replaceAll('\r', '')
const file = await text(path.join(MIGRATIONS_DIR, NAME))
const proof = await text(PROOF)
const scenes = await Promise.all(SCENES.map(text))
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

const only = process.argv.find((a) => a.startsWith('--only='))?.slice(7)
const MUTATIONS = (await import('./mutations-0333.mjs')).mutations(swap).filter(([label]) => !only || label.includes(only))

// RED FIRST
const red = await attempt(proof)
say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 120) : 'IT PASSED'}`)
if (!red.err) failures.push('proof 40 passed with no file')

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
if (whole.err) failures.push(`proof 40 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => /^(PASS:|NOTE:)/.test(x) || /self-assert ok/.test(x))) say('  ', n)
if (whole.err) say('   ERROR', whole.err)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

// THE PROOFS OF THE BODIES IT RE-CUTS
if (!process.argv.includes('--no-old')) {
  for (const f of OLD) {
    const r = await attempt(file, await text(f))
    say(`OLD PROOF ${f}: ${r.err ? 'RED ' + r.err.slice(0, 300) : 'green'}`)
    if (r.err) failures.push(`${f}: ${r.err}`)
  }
}

const w14 = process.argv.find((a) => a.startsWith('--w14='))?.slice(6)
if (w14) {
  const w = await text(path.join(w14, '20260818000334_wanted.sql'))
  const r40 = await attempt(file, w, proof)
  say(`WITH 0334, proof 40: ${r40.err ? 'RED ' + r40.err.slice(0, 400) : 'green'}`)
  for (const n of r40.notes.filter((x) => /^PASS: NC_WANTED/.test(x))) say('  ', n)
  if (r40.err) failures.push(`proof 40 on 0334: ${r40.err}`)
  const r41 = await attempt(file, w, await text(path.join(w14, '41_wanted.sql')))
  say(`WITH 0334, proof 41: ${r41.err ? 'RED ' + r41.err.slice(0, 400) : 'green'}`)
  if (r41.err) failures.push(`proof 41 on 0334: ${r41.err}`)
}

if (process.argv.includes('--cost')) {
  const { cost } = await import('./cost-0333.mjs')
  await cost(db, file, say)
}

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    const r = await attempt(mutate(file), proof)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 260)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
const ran = process.argv.includes('--no-mutations') ? 'mutations NOT run' : `${MUTATIONS.length} mutations red`
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, dark parity equal, the real file and proof 40 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
