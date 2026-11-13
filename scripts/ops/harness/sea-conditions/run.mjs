// run.mjs: scenes on the LOCAL cached world (PGlite) for the sea conditions (0376 and after). LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/sea-conditions/run.mjs [--apply=0376,0377] [--commit] [--proofs=68] [--dump=<dir> --fns=<a;b>] [--set=key:value,...] <scene.sql> [...]
//
// Restores the cached world at the head before 0376 (never from zero; the cache is only read), then, in ONE transaction that is
// ROLLED BACK: applies the named migrations of this tree in name order, sets the named world_config keys, writes the live bodies
// named by --fns to --dump (LF), and runs each scene at a savepoint, printing its notices and its last rows. A PROD CHECK file
// runs here too (its read-only wrapper is taken off), to see what it will answer. --proofs runs the named proofs, each in its own
// rolled-back transaction, after the named migrations (committed in this throwaway world).
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const FIRST = '20260818000376'
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const say = (...a) => console.log(...a)
const files = []
const mine = []
for (const name of await migrationFiles()) {
  if (name >= FIRST) { mine.push(name); continue }
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
const onNotice = (n) => say('  ', n.message)
const wanted = (arg('apply') ?? '').split(',').filter(Boolean)
const toApply = mine.filter((n) => wanted.some((w) => n.slice(10, 14) === w))
let failed = false
const applyAll = async () => {
  for (const n of toApply) {
    const t = Date.now()
    try {
      await db.exec((await readFile(path.join(MIGRATIONS_DIR, n), 'utf8')).replaceAll('\r', ''), { onNotice })
      say(`applied ${n} in ${Date.now() - t} ms`)
    } catch (e) {
      say(`APPLY ERROR ${n} after ${Date.now() - t} ms: ${e.message}\n  where: ${e.where ?? ''}\n  detail: ${e.detail ?? ''} pos ${e.position ?? ''} iq ${(e.internalQuery ?? '').slice(0, 600)}`)
      await db.close()
      process.exit(1)
    }
  }
  for (const kv of (arg('set') ?? '').split(',').filter(Boolean)) {
    const [k, v] = kv.split(':')
    await db.query(`update public.world_config set value = $2::jsonb where key = $1`, [k, v])
    say(`set ${k} = ${v}`)
  }
}

if (arg('proofs')) {
  await (await import('../../../db/proof-courses.mjs')).installProofCourses(db)
  await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
  await applyAll()
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
await applyAll()
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
    say(`${scene}: ERROR ${e.message} ${e.where ?? ''}`)
  }
  await db.exec('rollback to savepoint scene')
}
await db.exec('rollback')
await db.close()
process.exit(failed ? 1 : 0)
