// ═══════════════════════════════════════════════════════════════════════════════
// proof-0336.mjs — A REALM READS ITS OWN HARBOURS (migration 0336): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/origins-fence/proof-0336.mjs [--no-mutations] [--cost] [--show] [--only=<text>] [--with=18,19,20,32,35,36] [--snapshot]
//
// Restores the cached world at the head before 0336 (never from zero), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 43 on the world with no file: it must fail, and at its fence (the count of calls), because every answer of the unfenced read is already the right one;
//   DARK PARITY       - the rich-cities and armed-cargo scenes, on the world before the file and after it: every SCENE line equal;
//   POSITIVE CONTROL  - the real file followed by proof 43;
//   --with            - the real file followed by each named proof, one transaction each (the proofs that go through public.cargo_origins);
//   MUTATION CONTROLS - deliberate breakages, each required to FAIL the file's own self-assert, or proof 43 right after it, for the intended reason;
//   --cost            - the calls public.crown_call_room receives and the time of one lit read, 0324's body against the fenced one, on the local world.
//   --snapshot        - keep the world at the head before 0336 in the prefix cache, so the next run restores it.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000336_a_realm_reads_its_own_harbours.sql'
const PROOF = 'scripts/db/proofs/43_a_realm_reads_its_own.sql'
const SCENES = ['scripts/ops/harness/rich-cities/dark-scene.sql', 'scripts/ops/harness/armed-cargo/dark-scene.sql']
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
const scenes = await Promise.all(SCENES.map(async (s) => (await readFile(s, 'utf8')).replaceAll('\r', '')))
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: process.argv.includes('--snapshot') })
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

const MUTATIONS = (await import('./mutations-0336.mjs')).mutations(swap)
const only = arg('only')

if (!only) {
  // RED FIRST
  const red = await attempt(proof)
  say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 160) : 'IT PASSED'}`)
  if (!red.err) failures.push('proof 43 passed with no file')
  else if (!/PROOF 43 FAIL: public\.crown_call_room was asked of a harbour outside the realm/.test(red.err)) failures.push(`proof 43 was red with no file, but not at its fence: ${red.err.slice(0, 200)}`)
  for (const n of red.notes.filter((x) => /^PASS:/.test(x))) say('  ', n.slice(0, 200))

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
  if (whole.err) failures.push(`proof 43 failed: ${whole.err}`)
  for (const n of whole.notes.filter((x) => /^(PASS:|COST:)/.test(x) || /self-assert ok/.test(x))) say('  ', n)
  if (whole.err) say('   ERROR', whole.err)
  const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
  const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
  if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)
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
  const { cost } = await import('./cost-0336.mjs')
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
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first at the fence, dark parity equal, the real file and proof 43 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
