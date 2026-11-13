// run.mjs — scenes on the LOCAL cached world (PGlite) for gear wear (0158, the switch gear_wear_bite). LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/gear-wear/run.mjs [--apply=<migration number>] [--dump=<dir> --fns=a;b] [--proofs=68] [--fixtures] <scene.sql> [...]
//
// Restores the cached world at the chain's head (never from zero; the cache is only read; a migration named by --apply and every
// later file is left out of the restore), then, in ONE transaction that is ROLLED BACK: applies the --apply file when named, writes
// the live bodies named by --fns to --dump (LF), and runs each scene at a savepoint, printing its notices and its last rows.
// A PROD CHECK file can be run here too, to see what it will answer. --proofs runs the named proofs, each in its own rolled-back
// transaction (after the --apply file, when named), with the proof courses and the market fixture installed as proof.mjs does.
// --fixtures installs the same two fixtures for a scene (proof.sail, proof.pin_market).
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const say = (...a) => console.log(...a)
const NAME = arg('apply') ? `20260818${arg('apply').padStart(6, '0')}` : null
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (NAME && name.startsWith(NAME)) mine = name
  if (NAME && name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
if (NAME && !mine) { say(`no migration ${NAME}`); process.exit(2) }
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
const onNotice = (n) => say('  ', n.message)
const file = mine ? (await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', '') : null
let failed = false

if (arg('proofs')) {
  await (await import('../../../db/proof-courses.mjs')).installProofCourses(db)
  await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
  if (file) {
    const t = Date.now()
    await db.exec(file, { onNotice })
    say(`applied ${mine} in ${Date.now() - t} ms (committed in this throwaway world)`)
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

if (process.argv.includes('--fixtures')) {
  await (await import('../../../db/proof-courses.mjs')).installProofCourses(db, { log: () => {} })
  await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
}
await db.exec('begin')
if (file) {
  const t = Date.now()
  try {
    await db.exec(file, { onNotice })
    say(`applied ${mine} in ${Date.now() - t} ms`)
  } catch (e) {
    say(`APPLY ERROR after ${Date.now() - t} ms: ${e.message}\n  where: ${e.where ?? ''}\n  detail: ${e.detail ?? ''}`)
    await db.close()
    process.exit(1)
  }
}
if (arg('dump')) {
  await mkdir(arg('dump'), { recursive: true })
  for (const f of (arg('fns') ?? '').split(';').filter(Boolean)) {
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
    say(`${scene}: ERROR ${e.message}\n  where: ${(e.where ?? '').slice(0, 800)}`)
  }
  await db.exec('rollback to savepoint scene')
}
await db.exec('rollback')
await db.close()
process.exit(failed ? 1 : 0)
