// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0332.mjs — A PLAYER BUILDS THE CROWN'S SHIPS (migration 0332): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/crown-ships/proof-0332.mjs [--no-mutations] [--show]
//
// Restores the cached world at the head before 0332 (never from zero), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 39 on the world with no file: it must fail;
//   PARITY            - parity-scene.sql before and after the file: both cut reads equal once the new key is off;
//   POSITIVE CONTROL  - the real file followed by proof 39;
//   MUTATION CONTROLS - deliberate breakages, each required to FAIL its self-assert, or proof 39 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000332_a_player_builds_the_crown_ships.sql'
const PROOF = 'scripts/db/proofs/39_a_player_builds_the_crown_ships.sql'
const SCENE = 'scripts/ops/harness/crown-ships/parity-scene.sql'
const failures = []
const say = (...a) => console.log(...a)

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

// RED FIRST
const red = await attempt(proof)
say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 120) : 'IT PASSED'}`)
if (!red.err) failures.push('proof 39 passed with no file')

// PARITY
const lines = (r) => r.notes.filter((n) => n.startsWith('SCENE: '))
const a = await attempt(scene)
const b = await attempt(file, scene)
if (a.err) failures.push(`scene before: ${a.err}`)
if (b.err) failures.push(`scene after: ${b.err}`)
say(`PARITY: ${lines(a).length} scene lines before, ${lines(b).length} after`)
if (process.argv.includes('--show')) for (const n of lines(a)) say('  ', n)
if (lines(a).length === 0 || lines(a).length !== lines(b).length) failures.push('scene line counts differ')
lines(a).forEach((n, j) => {
  if (n !== lines(b)[j]) failures.push(`scene differs: ${n} / ${lines(b)[j]}`)
})

// POSITIVE CONTROL
const good = await attempt(file, proof)
const passes = good.notes.filter((n) => n.startsWith('PASS: '))
say(`POSITIVE: ${good.err ? 'RED: ' + good.err : 'green'}, ${passes.length} PASS`)
for (const n of passes) say('  ', n.slice(0, 150))
for (const n of good.notes.filter((x) => x.includes('self-assert ok'))) say('  ', n.slice(0, 220))
if (good.err) failures.push(`the real file and proof: ${good.err}`)
const wanted = [...proof.matchAll(/^-- @pass (\S+)/gm)].map((m) => m[1])
for (const w of wanted) if (!passes.some((p) => p.startsWith(`PASS: ${w} `))) failures.push(`no PASS for ${w}`)

// MUTATIONS
if (!process.argv.includes('--no-mutations')) {
  const { mutations } = await import('./mutations-0332.mjs')
  for (const [label, mutate, want, after] of mutations(swap)) {
    const r = await attempt(mutate(file), after, proof)
    const ok = r.err && want.test(r.err)
    say(`MUTATION ${ok ? 'red ' : 'WRONG'} ${label}: ${r.err ? r.err.slice(0, 130) : 'IT PASSED'}`)
    if (!ok) failures.push(`mutation '${label}': ${r.err ?? 'passed'}`)
  }
}

if (failures.length) {
  console.error(`\nFAIL: ${failures.length}`)
  for (const f of failures) console.error(' -', f)
  process.exit(1)
}
say('\nALL GREEN')
process.exit(0)
