// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0341.mjs — THE NAVY HUNTS (migration 0341, W19): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/the-navy-hunts/proof-0341.mjs [--first=a.sql,b.sql] [--no-mutations] [--no-old] [--only=<text>] [--with=31,34,37,40,41] [--cost] [--show]
//
// Restores the cached world at the head before 0341 (never from zero; nothing is written to the cache), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 48 on the world with no file: it must fail;
//   DARK PARITY       - the navy, navy-comes and own scenes (dark-scene.sql), on the world before the file and after it: every SCENE line must be equal;
//   POSITIVE CONTROL  - the real file followed by proof 48: every marker it declares;
//   OLD PROOFS        - the real file followed by proofs 31, 34, 37 and 40, whose bodies it re-cuts under (--with= names others);
//   MUTATION CONTROLS - deliberate breakages of the file (mutations-0341.mjs), each required to FAIL its self-assert, or proof 48 right after it, for the intended reason;
//   --first           - files applied before everything else, in that order (W17's contract stub while 0339 is not in the tree; nothing once it is);
//   --cost            - what the hunt pass costs, dark and lit, with the design's 75 hulls (cost-0341.mjs).
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000341_the_navy_hunts.sql'
const PROOF = 'scripts/db/proofs/48_the_navy_hunts.sql'
const OLD = ['scripts/db/proofs/31_battles.sql', 'scripts/db/proofs/34_a_player_attacks.sql', 'scripts/db/proofs/37_a_country_has_a_navy.sql', 'scripts/db/proofs/40_the_navy_comes.sql']
const SCENES = ['scripts/ops/harness/navy/dark-scene.sql', 'scripts/ops/harness/navy-comes/dark-scene.sql', 'scripts/ops/harness/the-navy-hunts/dark-scene.sql']
const failures = []
const say = (...a) => console.log(...a)
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const text = async (f) => (await readFile(f, 'utf8')).replaceAll('\r', '')
const file = await text(path.join(MIGRATIONS_DIR, NAME))
const proof = await text(PROOF)
const scenes = await Promise.all(SCENES.map(text))
const first = (arg('first') ?? '').split(',').filter(Boolean)
const before = (await Promise.all(first.map(text))).join('\n')
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied${first.length ? `; first: ${first.join(', ')}` : ''}`)
if (arg('with') || !process.argv.includes('--no-old')) {
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

const only = arg('only')
const MUTATIONS = (await import('./mutations-0341.mjs')).mutations(swap).filter(([label]) => !only || label.includes(only))

if (!only) {
  // RED FIRST
  const red = await attempt(before, proof)
  say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 160) : 'IT PASSED'}`)
  if (!red.err) failures.push('proof 48 passed with no file')

  // DARK PARITY
  const lines = (r) => r.notes.filter((n) => n.startsWith('SCENE: '))
  for (const [i, scene] of scenes.entries()) {
    const a = await attempt(before, scene)
    const b = await attempt(before, file, scene)
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
  const whole = await attempt(before, file, proof)
  say(`whole: ${Date.now() - t0} ms`)
  if (whole.err) failures.push(`proof 48 failed: ${whole.err}`)
  for (const n of whole.notes.filter((x) => /^(PASS:|NOTE:|COST:)/.test(x) || /self-assert ok/.test(x))) say('  ', n)
  if (whole.err) say('   ERROR', whole.err)
  const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
  const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
  if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

  // THE PROOFS OF THE BODIES IT RE-CUTS
  if (!process.argv.includes('--no-old')) {
    const list = arg('with') ? arg('with').split(',').map((n) => `scripts/db/proofs/${n}_`) : null
    const olds = list ? (await import('node:fs/promises')).readdir('scripts/db/proofs').then((fs) => fs.filter((f) => list.some((p) => `scripts/db/proofs/${f}`.startsWith(p))).map((f) => `scripts/db/proofs/${f}`)) : OLD
    for (const f of await olds) {
      const t1 = Date.now()
      const r = await attempt(before, file, await text(f))
      say(`OLD PROOF ${f}: ${r.err ? 'RED ' + r.err.slice(0, 300) : 'green'} (${Date.now() - t1} ms)`)
      if (r.err) failures.push(`${f}: ${r.err}`)
    }
  }
}

if (process.argv.includes('--cost')) {
  const { cost } = await import('./cost-0341.mjs')
  await cost(db, before, file, say)
}

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    const t1 = Date.now()
    const r = await attempt(before, mutate(file), proof)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 300)}`} (${Date.now() - t1} ms)`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
const ran = process.argv.includes('--no-mutations') ? 'mutations NOT run' : `${MUTATIONS.length} mutations red`
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, dark parity equal, the real file and proof 48 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
