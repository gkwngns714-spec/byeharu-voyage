// run.mjs — scenes on the LOCAL cached world (PGlite) for 0357 (a battle is fought round by round). LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/live-rounds/run.mjs [--apply] [--dump=<dir>] [--fns=<a;b>] [--proofs=60,56] [--after=<dir>] [--notes] <scene.sql> [...]
//
// Restores the cached world at the head before 0357 (never from zero; the cache is only read), then, in ONE transaction that is
// ROLLED BACK: applies 0357 when --apply is given, writes the live bodies of the functions 0357 cuts (and any named by --fns) to
// --dump (LF), and runs each scene at a savepoint, printing its notices and its last rows. A PROD CHECK file can be run here too,
// to see what it will answer. --proofs runs the named proofs (each in its own rolled-back transaction, after 0357 when --apply is
// given), with the proof courses and the market fixture installed as scripts/db/proof.mjs installs them.
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000357'
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const say = (...a) => console.log(...a)
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) mine = name
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: process.env.LR_SNAPSHOT === '1' })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
const onNotice = (n) => say('  ', n.message)
const apply = process.argv.includes('--apply')
const file = apply ? (await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', '') : null
let failed = false

// the bodies 0357 cuts, read from the migration's own hunks (gen-checks.mjs)
import { CUT } from './gen-checks.mjs'

if (arg('proofs')) {
  await (await import('../../../db/proof-courses.mjs')).installProofCourses(db)
  await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
  if (file) {
    const t = Date.now()
    await db.exec(file, { onNotice })
    say(`applied ${mine} in ${Date.now() - t} ms (committed in this throwaway world)`)
  }
  // --after=<dir>: the migrations of a tree that is ahead of this one (a batch branch), applied after 0357 in name order, so a proof can be run beneath them
  if (arg('after')) {
    for (const n of (await readdir(arg('after'))).filter((x) => x.endsWith('.sql')).sort()) {
      const t = Date.now()
      await db.exec((await readFile(path.join(arg('after'), n), 'utf8')).replaceAll('\r', ''), { onNotice: () => {} })
      say(`applied after it: ${n} in ${Date.now() - t} ms`)
    }
  }
  const all = await readdir('scripts/db/proofs')
  for (const n of arg('proofs').split(',')) {
    const f = all.find((x) => x.startsWith(`${n}_`))
    const sql = (await readFile(path.join('scripts/db/proofs', f), 'utf8')).replaceAll('\r', '')
    const want = [...sql.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
    const notes = []
    const t = Date.now()
    let err = null
    await db.exec('begin')
    try { await db.exec(sql, { onNotice: (x) => notes.push(x.message) }) } catch (e) { err = e.message }
    try { await db.exec('rollback') } catch { /* aborted */ }
    const missing = want.filter((m) => !notes.some((x) => x.includes(`PASS: ${m}`)))
    if (err || missing.length) failed = true
    say(`PROOF ${f}: ${err ? 'RED ' + err.slice(0, 1500) : missing.length ? 'MISSING ' + missing.join(', ') : `green, ${want.length} of ${want.length} markers`}, ${Date.now() - t} ms`)
    if (process.argv.includes('--notes')) for (const x of notes) say('   ', x.slice(0, 1200))
  }
  await db.close()
  process.exit(failed ? 1 : 0)
}

await db.exec('begin')
if (file) {
  const t = Date.now()
  try {
    await db.exec(file, { onNotice })
    say(`applied ${mine} in ${Date.now() - t} ms`)
  } catch (e) {
    say(`APPLY ERROR after ${Date.now() - t} ms: ${e.message}
  where: ${e.where ?? ""}
  detail: ${e.detail ?? ""} pos ${e.position ?? ""} iq ${(e.internalQuery ?? "").slice(0, 600)}`)
    await db.close()
    process.exit(1)
  }
}
if (arg('dump')) {
  await mkdir(arg('dump'), { recursive: true })
  const names = (arg('fns') ?? '').split(';').filter(Boolean)
  for (const f of [...CUT, ...names]) {
    const r = await db.query(`select replace(pg_get_functiondef(to_regprocedure($1)), E'\r', '') as d`, [f])
    if (!r.rows[0].d) { say(`no such function: ${f}`); continue }
    await writeFile(path.join(arg('dump'), f.replace(/\(.*/, '') + '.sql'), r.rows[0].d)
  }
  say(`dumped to ${arg('dump')}`)
}
for (const scene of process.argv.slice(2).filter((a) => !a.startsWith('--'))) {
  const sql = (await readFile(scene, 'utf8'))
    .replaceAll('\r', '')
    .replace(/^begin transaction read only;$/m, '')
    .replace(/^commit;$/m, '')
    .replace('(select max(version) from supabase_migrations.schema_migrations)', "'(not on PGlite)'::text")
  await db.exec('savepoint scene')
  const t0 = Date.now()
  try {
    const res = await db.exec(sql, { onNotice })
    const last = res.findLast((r) => r.rows?.length)
    for (const r of last?.rows ?? []) say('  ', JSON.stringify(r))
    say(`${scene}: ok, ${Date.now() - t0} ms`)
  } catch (e) {
    failed = true
    say(`${scene}: ERROR ${e.message}`)
  }
  await db.exec('rollback to savepoint scene')
}
await db.exec('rollback')
await db.close()
process.exit(failed ? 1 : 0)
