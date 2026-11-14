// probe.mjs: 0410 ON THE CACHED HEAD WORLD, each scene in a rolled-back transaction. LOCAL ONLY; not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/pacific-pirates/probe.mjs [scene.sql ...]
// It applies the file as the cached world is, then (still inside the transaction) runs each scene file given and prints its notices and last rows.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const NAME = '20260818000410'
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) mine = name
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const sql = (await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', '')
let bad = 0
await db.exec('begin')
const t = Date.now()
try {
  await db.exec(sql, { onNotice: (n) => console.log(`  ${n.message}`) })
  console.log(`applied in ${Date.now() - t} ms`)
  for (const f of process.argv.slice(2)) {
    const res = await db.exec((await readFile(f, 'utf8')).replaceAll('\r', ''), { onNotice: (n) => console.log(`  [${path.basename(f)}] ${n.message}`) })
    const last = res.at(-1)
    if (last?.rows?.length) for (const r of last.rows) console.log('  ' + JSON.stringify(r))
  }
} catch (e) { bad++; console.log(`ERROR ${e.message}`, e.where ?? "", e.position ?? "", e.internalQuery ? String(e.internalQuery).slice(0, 600) : "") }
await db.exec('rollback')
await db.close()
process.exit(bad ? 1 : 0)
