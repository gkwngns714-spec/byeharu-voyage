// ═══════════════════════════════════════════════════════════════════════════════
// proof-0344.mjs — CROWN AND PIRATE HULLS HAVE A LEVEL (migration 0344): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/crown-level/proof-0344.mjs [--no-mutations] [--only=<text>]
//
// Restores the cached world at the head before 0344 (never from zero; nothing is written to the cache), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 51 on the world with no file: it must fail (the writer does not exist yet);
//   POSITIVE CONTROL  - the real file, then proof 51: every marker it declares;
//   MUTATION CONTROLS - deliberate breakages (mutations-0344.mjs), each required to FAIL the file's own self-assert, or proof 51 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000344_crown_hulls_have_a_level.sql'
const PROOF = 'scripts/db/proofs/51_crown_hulls_have_a_level.sql'
const failures = []
const say = (...a) => console.log(...a)
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const file = (await readFile(MIGRATIONS_DIR + path.sep + NAME, 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)

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

const MUTATIONS = (await import('./mutations-0344.mjs')).mutations(swap)
const only = arg('only')

if (!only) {
  const red = await attempt(proof)
  say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 160) : 'IT PASSED'}`)
  if (!red.err) failures.push('proof 51 passed with no file')

  const t = Date.now()
  const whole = await attempt(file, proof)
  say(`whole: ${Date.now() - t} ms`)
  if (whole.err) failures.push(`proof 51 failed: ${whole.err}`)
  for (const n of whole.notes.filter((x) => /^(PASS:)/.test(x) || /self-assert ok/.test(x))) say('  ', n.slice(0, 400))
  if (whole.err) say('   ERROR', whole.err)
  const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
  const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
  if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)
}

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    if (only && !label.includes(only)) continue
    const r = await attempt(mutate(file), proof)
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
