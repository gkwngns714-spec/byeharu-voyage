// ═══════════════════════════════════════════════════════════════════════════════
// proof-0339.mjs — PIRATE SHIPS SAIL (migration 0339): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/pirate-ships-sail/proof-0339.mjs [--no-mutations] [--only=<text>] [--with=18,20,23,30,31,34,36,37,38,40,41,45] [--cost]
//
// Restores the cached world at the head before 0339 (never from zero; nothing is written to the cache), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 46 on the world with no file: it must fail (the job it calls does not exist yet);
//   DARK PARITY       - dark-scene.sql on the world before the file and after it: every SCENE line equal (the map's rows, a departure's frozen path, 960 raid days settled through the real engine with the voyage id pinned,
//                       the kinds, origins, wages and fees, a pirate home's regen, the money figures, the attack door's refusal, the job with the switch off);
//   POSITIVE CONTROL  - the real file, then proof 46: every marker it declares;
//   --with            - the real file followed by each named existing proof (the proofs that run the raid, the kinds, the navy and the brethren), one transaction each;
//   --cost            - the price of the hot paths dark: voyage.depart and voyage.settle's PIRATES day, before and after the file, on the same probe (ms a call);
//   MUTATION CONTROLS - deliberate breakages (mutations-0339.mjs), each required to FAIL the file's own self-assert, or proof 46 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000339_pirate_ships_sail.sql'
const PROOF = 'scripts/db/proofs/46_pirate_ships_sail.sql'
const SCENE = 'scripts/ops/harness/pirate-ships-sail/dark-scene.sql'
const COST = 'scripts/ops/harness/pirate-ships-sail/cost.sql'
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

const MUTATIONS = (await import('./mutations-0339.mjs')).mutations(swap)
const only = arg('only')

if (!only) {
  // RED FIRST
  const red = await attempt(proof)
  say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 160) : 'IT PASSED'}`)
  if (!red.err) failures.push('proof 46 passed with no file')

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
  if (whole.err) failures.push(`proof 46 failed: ${whole.err}`)
  for (const n of whole.notes.filter((x) => /^(PASS:)/.test(x) || /self-assert ok|timings/.test(x))) say('  ', n.slice(0, 400))
  if (whole.err) say('   ERROR', whole.err)
  const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
  const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
  if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)
}

// THE COST OF THE HOT PATHS, DARK
if (process.argv.includes('--cost')) {
  const cost = (await readFile(COST, 'utf8')).replaceAll('\r', '')
  const before = await attempt(cost)
  const after = await attempt(file, cost)
  for (const [label, r] of [['before', before], ['after ', after]]) {
    if (r.err) failures.push(`cost ${label}: ${r.err}`)
    for (const n of r.notes.filter((x) => x.startsWith('COST: '))) say(`  ${label} ${n}`)
  }
}

// THE PROOFS THAT SHARE ITS CODE
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
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, dark parity equal, the real file and proof 46 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
