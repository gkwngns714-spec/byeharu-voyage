// ═══════════════════════════════════════════════════════════════════════════════
// proof-0377.mjs — A MERCHANT SAILS THE SEAS HER HULL CAN HOLD (migration 0377): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/sea-merchants/proof-0377.mjs [--first=<sql file>] [--no-mutations] [--only=<text>] [--with=12,47]
//
// Restores the cached world at the head before 0377 (never from zero; nothing is written to the cache), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 70 on the world with no file: it must fail (the readers it calls do not exist yet);
//   DARK PARITY       - dark-scene.sql on the world before the file and after it, sea_conditions_bite_npc false: every SCENE line equal (the loops offered to every
//                       fourth merchant of the roster, and a REAL plan pass over 60 merchants at their lap start: every stop, course and line written, the counters);
//   POSITIVE CONTROL  - the real file, then proof 70: every marker it declares;
//   --with            - the real file followed by each named existing proof (12 and 47 share its re-cut bodies), one transaction each;
//   MUTATION CONTROLS - deliberate breakages (mutations-0377.mjs), each required to FAIL the file's own self-assert, or proof 70 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it. The dark scene takes about two minutes a side. sim.mjs is the lit simulation.

import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000377_a_merchant_sails_the_seas_her_hull_can_hold.sql'
const PROOF = 'scripts/db/proofs/70_a_merchant_sails_the_seas_her_hull_can_hold.sql'
const SCENE = 'scripts/ops/harness/sea-merchants/dark-scene.sql'
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
const scene = (await readFile(SCENE, 'utf8')).replaceAll('\r', '')
const first = arg('first') ? (await readFile(arg('first'), 'utf8')).replaceAll('\r', '') : ''
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied${first ? `, then ${arg('first')} (not committed)` : ''}`)
if (first) await db.exec(first)
if (arg('with')) {
  // what scripts/db/proof.mjs installs before the existing proofs run: the proposed courses (schema `proof`) and the held market
  await (await import('../../../db/proof-courses.mjs')).installProofCourses(db)
  await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
}

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from.slice(0, 120)}`)
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

const MUTATIONS = (await import('./mutations-0377.mjs')).mutations(swap)
const only = arg('only')

if (!only) {
  // RED FIRST
  const red = await attempt(proof)
  say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 160) : 'IT PASSED'}`)
  if (!red.err) failures.push('proof 70 passed with no file')

  // DARK PARITY
  const lines = (r) => r.notes.filter((n) => n.startsWith('SCENE: '))
  const a = await attempt(scene)
  const b = await attempt(file, scene)
  if (a.err) failures.push(`scene before: ${a.err}`)
  if (b.err) failures.push(`scene after: ${b.err}`)
  say(`DARK PARITY ${SCENE}: ${lines(a).length} scene lines before, ${lines(b).length} after`)
  if (lines(a).length === 0 || lines(a).length !== lines(b).length) failures.push('scene line counts differ')
  lines(a).forEach((n, j) => {
    const same = n === lines(b)[j]
    say(`  ${same ? 'equal ' : 'DIFFERS'} ${n.slice(0, 150)}`)
    if (!same) {
      failures.push(`dark differs at line ${j}`)
      say('  AFTER  ' + (lines(b)[j] ?? '').slice(0, 300))
    }
  })

  // POSITIVE CONTROL
  const t0 = Date.now()
  const whole = await attempt(file, proof)
  say(`whole: ${Date.now() - t0} ms`)
  if (whole.err) failures.push(`proof 70 failed: ${whole.err}`)
  for (const n of whole.notes.filter((x) => /^(PASS:)/.test(x) || /self-assert ok|timings/.test(x))) say('  ', n.slice(0, 400))
  if (whole.err) say('   ERROR', whole.err)
  const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
  const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
  if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)
}

// THE PROOFS THAT SHARE THE RE-CUT BODIES
if (arg('with')) {
  const all = await readdir('scripts/db/proofs')
  for (const n of arg('with').split(',')) {
    const f = all.find((x) => x.startsWith(`${n}_`))
    const sql = (await readFile(path.join('scripts/db/proofs', f), 'utf8')).replaceAll('\r', '')
    const t = Date.now()
    const r = await attempt(file, sql)
    say(`WITH ${f}: ${r.err ? 'RED ' + r.err.slice(0, 500) : `green, ${r.notes.filter((x) => x.startsWith('PASS:')).length} markers`}, ${Date.now() - t} ms`)
    if (r.err) failures.push(`proof ${n}: ${r.err.slice(0, 300)}`)
  }
}

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected, pre] of MUTATIONS) {
    if (only && !label.includes(only)) continue
    const r = await attempt(pre ?? '', mutate(file), proof)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 300)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
const ran = process.argv.includes('--no-mutations') ? 'mutations NOT run' : `${MUTATIONS.length} mutations red`
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, dark parity equal, the real file and proof 70 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
