// q.mjs: run one SQL file (or --sql=) on the cached local world at the chain's head, print the rows. LOCAL ONLY; not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/day-hour/q.mjs <file.sql> [--before=20260818000409] [--apply] [--raw]
// --apply also applies the migrations at or after --before (this slice's file) first. The world is thrown away.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const before = process.argv.find((a) => a.startsWith('--before='))?.slice(9) ?? '20260818000409'
const files = []
const later = []
for (const name of await migrationFiles()) (name < before ? files : later).push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
console.error(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
if (process.argv.includes('--apply')) for (const f of later) { await db.exec(f.sql.replaceAll('\r', '')); console.error('applied', f.name.slice(0, 14)) }
const sql = process.argv.find((a) => a.startsWith('--sql='))?.slice(6) ?? (await readFile(process.argv[2], 'utf8'))
for (const res of await db.exec(sql)) {
  if (!res.rows?.length) continue
  if (process.argv.includes('--raw')) for (const r of res.rows) console.log(Object.values(r).join('\n'))
  else for (const r of res.rows) console.log(JSON.stringify(r))
}
await db.close(); process.exit(0)
