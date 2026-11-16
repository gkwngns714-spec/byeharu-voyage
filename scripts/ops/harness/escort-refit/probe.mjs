// probe.mjs: the escort's re-rating ON THE CACHED HEAD WORLD (the browser image's prefix, main's whole chain), in one rolled-back transaction.
// LOCAL ONLY; not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/escort-refit/probe.mjs [--fix] [scene.sql ...]
// --fix applies 0452 first (inside the transaction); then each scene file runs and prints its notices and last rows.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, migrationFiles } from '../../../db/apply-chain.mjs'
import { BROWSER_VARIANT, IMAGE_CACHE_DIR } from '../../../db/build-image.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const NAME = process.env.BV_NAME ?? '20260818000452'
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) { mine = name; continue }
  if (name > NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const t0 = Date.now()
const { db } = await applyWithPrefixCache({ variant: BROWSER_VARIANT, files, cacheDir: path.join(IMAGE_CACHE_DIR, 'prefix'), log: (m) => console.log(m), required: true, snapshots: false })
console.log(`world ready in ${Date.now() - t0} ms`)
const run = async (f) => {
  const res = await db.exec((await readFile(f, 'utf8')).replaceAll('\r', ''), { onNotice: (n) => console.log(`  [${path.basename(f)}] ${n.message}`) })
  const last = res.at(-1)
  if (last?.rows?.length) for (const r of last.rows) console.log('  ' + JSON.stringify(r))
}
let bad = 0
await db.exec('begin')
try {
  if (process.argv.includes('--fix')) {
    if (!mine) throw new Error(`no migration ${NAME}`)
    const t = Date.now()
    await db.exec((await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', ''), { onNotice: (n) => console.log(`  ${n.message}`) })
    console.log(`applied ${mine} in ${Date.now() - t} ms`)
  }
  for (const f of process.argv.slice(2).filter((x) => !x.startsWith('--'))) await run(f)
} catch (e) { bad++; console.log(`ERROR ${e.message}`, e.where ?? '', e.position ?? '', e.internalQuery ? String(e.internalQuery).slice(0, 600) : '') }
await db.exec('rollback')
await db.close()
process.exit(bad ? 1 : 0)
