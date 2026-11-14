// q.mjs: run one SQL file (or --sql=) on the cached local world, print the rows. LOCAL ONLY; not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/day-hour/q.mjs <file.sql> [--before=20260818000413] [--also=<file.sql>] [--apply] [--raw]
// The world is the chain below --before (restored from the cache as far as it reaches, the rest applied). --also applies one more file on top of it
// (a migration of another branch that deploys first). --apply then applies the chain's files at or after --before (this slice's file). Thrown away.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const before = arg('before') ?? '20260818000413'
const files = []
const later = []
for (const name of await migrationFiles()) (name < before ? files : later).push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
console.error(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
try {
  const notice = { onNotice: (n) => { if (process.argv.includes('--notices')) console.error('  notice:', String(n.message).slice(0, 1500)) } }
  if (arg('also')) { await db.exec((await readFile(arg('also'), 'utf8')).replaceAll('\r', ''), notice); console.error('applied also', path.basename(arg('also')).slice(0, 14)) }
  if (process.argv.includes('--apply')) for (const f of later) { await db.exec(f.sql.replaceAll('\r', ''), notice); console.error('applied', f.name.slice(0, 14)) }
  const sql = arg('sql') ?? (await readFile(process.argv[2], 'utf8'))
  for (const res of await db.exec(sql.replaceAll('\r', ''), notice)) {
    if (!res.rows?.length) continue
    if (process.argv.includes('--raw')) for (const r of res.rows) console.log(Object.values(r).join('\n'))
    else for (const r of res.rows) console.log(JSON.stringify(r))
  }
} catch (e) { console.error('ERROR:', e.message, e.where ? '\n' + String(e.where).slice(0, 600) : ''); process.exit(1) }
await db.close(); process.exit(0)
