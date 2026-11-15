// probe.mjs: the NPC ladder ON THE CACHED HEAD WORLD (main's chain), in one rolled-back transaction. LOCAL ONLY; not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/npc-ladder/probe.mjs [--fix] [scene.sql ...]
// --fix applies 0451 first (inside the transaction); then each scene file runs and prints its notices and last rows. --json prints the last
// row's first column as JSON only (for a file).
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const NAME = process.env.BV_NAME ?? '20260818000451'
const quiet = process.argv.includes('--json')
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) { mine = name; continue }
  if (name > NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const run = async (f) => {
  const res = await db.exec((await readFile(f, 'utf8')).replaceAll('\r', ''), { onNotice: (n) => quiet || console.log(`  [${path.basename(f)}] ${n.message}`) })
  const last = res.at(-1)
  if (last?.rows?.length) for (const r of last.rows) console.log(quiet ? JSON.stringify(Object.values(r)[0]) : '  ' + JSON.stringify(r))
}
let bad = 0
await db.exec('begin')
try {
  if (process.argv.includes('--fix')) {
    const t = Date.now()
    await db.exec((await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', ''), { onNotice: (n) => quiet || console.log(`  ${n.message}`) })
    quiet || console.log(`applied ${mine} in ${Date.now() - t} ms`)
  }
  for (const f of process.argv.slice(2).filter((x) => !x.startsWith('--'))) await run(f)
} catch (e) { bad++; console.log(`ERROR ${e.message}`, e.where ?? '', e.position ?? '', e.internalQuery ? String(e.internalQuery).slice(0, 600) : '') }
await db.exec('rollback')
await db.close()
process.exit(bad ? 1 : 0)
