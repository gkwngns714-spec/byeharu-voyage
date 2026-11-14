// dump.mjs: the LIVE bodies the waiting line runs through, from the cached world at the chain's head. LOCAL ONLY; not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/layup-line/dump.mjs <out.sql> [--before=20260818000405]
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const before = process.argv.find((a) => a.startsWith('--before='))?.slice(9) ?? '20260818000405'
const files = []
for (const name of await migrationFiles()) if (name < before) files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const r = await out.db.query(`select p.oid::regprocedure::text as fn, p.provolatile as vol, replace(pg_get_functiondef(p.oid), E'\r', '') as def
  from pg_proc p where p.pronamespace in ('public'::regnamespace, 'cmd'::regnamespace) and p.proname = any($1) order by 1`,
  [[...(process.argv.find((a) => a.startsWith('--fns='))?.slice(6).split(',') ?? []), 'npc_ask_waiting', 'npc_waiting_queue', 'tick_arrivals', 'tick_arrivals_each_second', 'tick_lap_starts', 'npc_tend_route', 'npc_tend_roster', 'tick_reconcile']])
await writeFile(process.argv[2], r.rows.map((x) => `===== ${x.fn} [${x.vol}] =====\n${x.def}\n`).join('\n'))
console.log(`head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored; ${r.rows.length} bodies`)
const j = await out.db.query(`select jobname, schedule, command from cron.job order by jobname`).catch((e) => ({ rows: [{ err: e.message }] }))
console.log(j.rows.length, 'cron rows'); for (const x of j.rows) console.log(' ', x.jobname ?? x.err, '|', x.schedule, '|', String(x.command).slice(0, 90))
await out.db.close(); process.exit(0)
