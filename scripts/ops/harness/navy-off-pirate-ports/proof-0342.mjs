// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0342.mjs — THE NAVY KEEPS OFF PIRATE PORTS (migration 0342): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/navy-off-pirate-ports/proof-0342.mjs [--no-mutations] [--no-old] [--only=<text>] [--with=31,34,37,40,42,48] [--all-old] [--cost] [--show] [--dump=<file>]
//
// Restores the cached world at the head before 0342 (never from zero; nothing is written to the cache), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 49 on the world with no file: it must fail;
//   DARK PARITY       - the navy, navy-comes, the-navy-hunts and own scenes (dark-scene.sql), on the world before the file and after it: every SCENE line must be equal;
//   POSITIVE CONTROL  - the real file followed by proof 49: every marker it declares;
//   OLD PROOFS        - the real file followed by the proofs of the bodies it re-cuts (37, 40, 42, 48) and of the attack path that calls the navy (31, 34); --with= names others; --all-old runs every proof in scripts/db/proofs;
//   MUTATION CONTROLS - deliberate breakages of the file (mutations-0342.mjs), each required to FAIL its self-assert, or proof 49 right after it, for the intended reason;
//   --cost            - what the re-cut choosers cost, before and after the file (cost-0342.mjs);
//   --dump=<file>     - writes the LIVE bodies (pg_get_functiondef) of every function this file re-cuts, from the world before the file: the ground truth the hunks are sliced from.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile, readdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000342_navy_keeps_off_pirate_ports.sql'
const PROOF = 'scripts/db/proofs/49_navy_keeps_off_pirate_ports.sql'
const OLD = ['scripts/db/proofs/31_battles.sql', 'scripts/db/proofs/34_a_player_attacks.sql', 'scripts/db/proofs/37_a_country_has_a_navy.sql', 'scripts/db/proofs/40_the_navy_comes.sql',
  'scripts/db/proofs/42_a_realm_pays.sql', 'scripts/db/proofs/48_the_navy_hunts.sql']
const SCENES = ['scripts/ops/harness/navy/dark-scene.sql', 'scripts/ops/harness/navy-comes/dark-scene.sql', 'scripts/ops/harness/the-navy-hunts/dark-scene.sql', 'scripts/ops/harness/navy-off-pirate-ports/dark-scene.sql']
// the live bodies this file re-cuts, by identity (the ground truth of its hunks)
const RECUT = ['public.navy_patrol_build(bigint, timestamp with time zone)', 'public.harbour_nearest(double precision, double precision)', 'public.navy_reinforce(uuid, uuid, timestamp with time zone)',
  'public.navy_escort_step(uuid, uuid, boolean, timestamp with time zone)', 'public.navy_ship_step(uuid, timestamp with time zone)', 'public.navy_pay(timestamp with time zone, uuid)',
  'public.navy_add(timestamp with time zone, uuid)', 'public.navy_sail(uuid, uuid, jsonb, uuid, bigint, integer, timestamp with time zone)', 'public.navy_hunt_targets(uuid, timestamp with time zone)']
const failures = []
const say = (...a) => console.log(...a)
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const text = async (f) => (await readFile(f, 'utf8')).replaceAll('\r', '')
const t00 = Date.now()
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied, ${Date.now() - t00} ms`)

if (arg('dump')) {
  let s = ''
  for (const fn of RECUT) {
    const r = await db.query(`select replace(pg_get_functiondef(to_regprocedure($1)), E'\\r', '') as def, md5(replace(pg_get_functiondef(to_regprocedure($1)), E'\\r', '')) as md5`, [fn])
    s += `\n===== ${fn} md5 ${r.rows[0].md5} =====\n${r.rows[0].def}\n`
  }
  await writeFile(arg('dump'), s, 'utf8')
  say(`dumped ${RECUT.length} live bodies to ${arg('dump')}`)
  await db.close()
  process.exit(0)
}

const file = await text(path.join(MIGRATIONS_DIR, NAME))
const proof = await text(PROOF)
const scenes = await Promise.all(SCENES.map(text))
if (arg('with') || process.argv.includes('--all-old') || !process.argv.includes('--no-old')) {
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
const MUTATIONS = (await import('./mutations-0342.mjs')).mutations(swap).filter(([label]) => !only || label.includes(only))

if (!only) {
  // RED FIRST
  const red = await attempt(proof)
  say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 160) : 'IT PASSED'}`)
  if (!red.err) failures.push('proof 49 passed with no file')

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
  if (whole.err) failures.push(`proof 49 failed: ${whole.err}`)
  for (const n of whole.notes.filter((x) => /^(PASS:|NOTE:|COST:)/.test(x) || /self-assert ok/.test(x))) say('  ', n)
  if (whole.err) say('   ERROR', whole.err)
  const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
  const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
  if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

  // THE PROOFS OF THE BODIES IT RE-CUTS (or every older proof)
  if (!process.argv.includes('--no-old')) {
    let olds = OLD
    if (process.argv.includes('--all-old')) {
      olds = (await readdir('scripts/db/proofs')).filter((f) => f.endsWith('.sql') && f < '49_').sort().map((f) => `scripts/db/proofs/${f}`)
    } else if (arg('with')) {
      const list = arg('with').split(',').map((n) => `${n}_`)
      olds = (await readdir('scripts/db/proofs')).filter((f) => list.some((p) => f.startsWith(p))).sort().map((f) => `scripts/db/proofs/${f}`)
    }
    for (const f of olds) {
      const t1 = Date.now()
      const sql = await text(f)
      const r = await attempt(file, sql)
      const wantOld = [...sql.matchAll(/^\s*--\s*@pass\s+([A-Z][A-Z0-9_]*)\b/gm)].map((m) => m[1])
      const missingOld = wantOld.filter((m) => !r.notes.some((n) => n.includes(`PASS: ${m}`)))
      const bad = r.err ? 'RED ' + r.err.slice(0, 300) : missingOld.length ? `MARKERS MISSING ${missingOld.join(', ')}` : null
      say(`OLD PROOF ${f}: ${bad ?? `green (${wantOld.length} markers)`} (${Date.now() - t1} ms)`)
      if (bad) failures.push(`${f}: ${bad}`)
    }
  }
}

if (process.argv.includes('--cost')) {
  const { cost } = await import('./cost-0342.mjs')
  await cost(db, file, say)
}

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    const t1 = Date.now()
    const r = await attempt(mutate(file), proof)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 300)}`} (${Date.now() - t1} ms)`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
const ran = process.argv.includes('--no-mutations') ? 'mutations NOT run' : `${MUTATIONS.length} mutations red`
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, dark parity equal, the real file and proof 49 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
