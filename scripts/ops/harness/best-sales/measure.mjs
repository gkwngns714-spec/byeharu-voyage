// measure.mjs — world.best_sales on the LOCAL cached world (PGlite). LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/best-sales/measure.mjs [--upto=<migration file name>] [--apply=<migration file name>] <scene.sql> [...]
//
// Restores the cached world (never from zero), applies the chain up to and excluding --upto (default: 0350, so the
// world is the one 0350 is written against), then, in ONE transaction that is ROLLED BACK, runs --apply's migration
// file (if named) and each scene (each rolled back to a savepoint), printing its notices and its last rows.
// A PROD CHECK file (before-0350.sql, mids-after.sql ...) can be run here too, to see what it will answer.
// The cache is only read (MEASURE_SNAPSHOTS=1 also saves the prefixes it applies, on a private node_modules only).
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const say = (...a) => console.log(...a)
const UPTO = arg('upto') ?? '20260818000350'
const files = []
for (const name of await migrationFiles()) {
  if (name >= UPTO) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({
  variant: await preambleVariant(),
  files,
  cacheDir: process.env.PREFIX_DIR || PREFIX_CACHE_DIR,
  log: say,
  required: true,
  snapshots: process.env.MEASURE_SNAPSHOTS === '1',
})
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
const scenes = process.argv.slice(2).filter((a) => !a.startsWith('--'))
let failed = false
const onNotice = (n) => say('  ', n.message)
await db.exec('begin')
if (arg('apply')) {
  const t = Date.now()
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, arg('apply')), 'utf8')).replaceAll('\r', ''), { onNotice })
  say(`applied ${arg('apply')} in ${Date.now() - t} ms`)
}
for (const scene of scenes) {
  // a PROD CHECK run here loses its own transaction wrapper (this runner's transaction holds it) and the one table PGlite has not
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
