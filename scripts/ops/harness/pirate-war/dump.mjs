// dump.mjs: the LIVE bodies on the cached head world (the chain before 0429), for cutting hunks. LOCAL ONLY.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/pirate-war/dump.mjs <out> <name>...
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const files = []
for (const name of await migrationFiles()) { if (name >= '20260818000429') continue; files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') }) }
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const [out, ...names] = process.argv.slice(2)
const r = await db.query(`select p.oid::regprocedure::text as fn, pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','cmd','world','voyage') and p.prokind = 'f' and p.proname = any($1) order by 1`, [names])
let s = ''
for (const x of r.rows) s += `\n===== ${x.fn} =====\n${x.def.replaceAll('\r', '')}\n`
await writeFile(out, s, 'utf8')
console.log(r.rows.map((x) => x.fn).join('\n'))
await db.close()
