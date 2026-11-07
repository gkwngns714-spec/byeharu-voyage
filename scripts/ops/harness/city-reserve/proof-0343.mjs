// ═══════════════════════════════════════════════════════════════════════════════
// proof-0343.mjs — THE DEFAULT CITY RESERVE (migration 0343): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/city-reserve/proof-0343.mjs [--no-mutations] [--only=<text>] [--with=16,17,...|all] [--cost]
//
// Restores the cached world at the head before 0343 (never from zero; nothing is written to the cache), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 50 on the world with no file: it must fail (the readers it calls do not exist yet);
//   DARK PARITY       - dark-scene.sql on the world before the file and after it: every SCENE line equal (the aid target, a donor's room and the hall's figure at every harbour, every realm's
//                       origins and load room, the real instant aid over the whole world with every flow digested, the real wind's one pass with every request and rest row digested);
//   POSITIVE CONTROL  - the real file, then proof 50: every marker it declares;
//   --with            - the real file followed by each named existing proof (or every older proof, `all`), one transaction each;
//   --cost            - the price of the two re-cut readers dark, before and after the file (ms a call);
//   MUTATION CONTROLS - deliberate breakages (mutations-0343.mjs), each required to FAIL the file's own self-assert, or proof 50 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000343_city_reserve.sql'
const PROOF = 'scripts/db/proofs/50_city_reserve.sql'
const SCENE = 'scripts/ops/harness/city-reserve/dark-scene.sql'
const COST = 'scripts/ops/harness/city-reserve/cost.sql'
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
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)
if (arg('with')) {
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

const MUTATIONS = (await import('./mutations-0343.mjs')).mutations(swap)
const only = arg('only')

if (!only) {
  // RED FIRST
  const red = await attempt(proof)
  say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 160) : 'IT PASSED'}`)
  if (!red.err) failures.push('proof 50 passed with no file')

  // DARK PARITY
  const lines = (r) => r.notes.filter((n) => n.startsWith('SCENE: '))
  const t0 = Date.now()
  const a = await attempt(scene)
  const t1 = Date.now()
  const b = await attempt(file, scene)
  if (a.err) failures.push(`scene before: ${a.err}`)
  if (b.err) failures.push(`scene after: ${b.err}`)
  say(`DARK PARITY ${SCENE}: ${lines(a).length} scene lines before (${t1 - t0} ms), ${lines(b).length} after (${Date.now() - t1} ms)`)
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
  const t2 = Date.now()
  const whole = await attempt(file, proof)
  say(`whole: ${Date.now() - t2} ms`)
  if (whole.err) failures.push(`proof 50 failed: ${whole.err}`)
  for (const n of whole.notes.filter((x) => /^(PASS:)/.test(x) || /self-assert ok/.test(x))) say('  ', n.slice(0, 400))
  if (whole.err) say('   ERROR', whole.err)
  const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
  const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
  if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)
}

// THE COST OF THE TWO READERS, DARK
if (process.argv.includes('--cost')) {
  const cost = (await readFile(COST, 'utf8')).replaceAll('\r', '')
  const before = await attempt(cost)
  const after = await attempt(file, cost)
  for (const [label, r] of [['before', before], ['after ', after]]) {
    if (r.err) failures.push(`cost ${label}: ${r.err}`)
    for (const n of r.notes.filter((x) => x.startsWith('COST: '))) say(`  ${label} ${n}`)
  }
}

// THE OLDER PROOFS, ON THE CHAIN WITH THE FILE
if (arg('with')) {
  const all = (await readdir('scripts/db/proofs')).filter((f) => /^\d\d_.*\.sql$/.test(f)).sort()
  const names = arg('with') === 'all' ? all.filter((f) => f < '50_') : arg('with').split(',').map((n) => all.find((x) => x.startsWith(`${n}_`)))
  for (const f of names) {
    const sql = (await readFile(path.join('scripts/db/proofs', f), 'utf8')).replaceAll('\r', '')
    const t = Date.now()
    const r = await attempt(file, sql)
    const want = [...sql.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
    const got = r.notes.filter((x) => x.startsWith('PASS:')).length
    say(`WITH ${f}: ${r.err ? 'RED ' + r.err.slice(0, 500) : `green, ${got} of ${want.length} markers`}, ${Date.now() - t} ms`)
    if (r.err) failures.push(`proof ${f}: ${r.err.slice(0, 300)}`)
    else if (got < want.length) failures.push(`proof ${f}: ${want.length - got} marker(s) missing`)
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
if (failures.length) {
  say('\nFAILURES')
  for (const f of failures) say('  ' + f)
  process.exit(1)
}
say('\nall green')
