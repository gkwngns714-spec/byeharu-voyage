// paired.mjs — world.best_sales BEFORE and AFTER a migration, ALTERNATED in one transaction on the LOCAL cached world (PGlite). LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/best-sales/paired.mjs --apply=<migration file name> [--upto=<migration file name>] [--n=20] [--purse=<coins>]
//
// --purse sets the probe company's purse first (a plain UPDATE of its own row, rolled back with everything else): a rich company is one whose hold binds every good.
//
// Two runs of cards.sql a minute apart differ by more than a small change does (this PC moves ~10 % between runs). Here the body before the migration is kept as a pg_temp copy,
// the migration is applied, and a new company where she lies asks the old and the new read in turn n times: the medians are of the same minute, the same cache, the same world.
// Everything is rolled back; the cache is only read. The copy calls the pieces as they are AFTER the migration (a migration that re-cuts a piece the old read calls is measured
// with the new piece on both sides: say so when you quote the figure).
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const APPLY = arg('apply')
if (!APPLY) throw new Error('--apply=<migration file name> is required')
const UPTO = arg('upto') ?? APPLY.slice(0, 14)
const N = Number(arg('n') ?? 20)
const PURSE = arg('purse') ? Number(arg('purse')) : null
const files = []
for (const name of await migrationFiles()) {
  if (name >= UPTO) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: process.env.PREFIX_DIR || PREFIX_CACHE_DIR, log: console.log, required: true, snapshots: false })
const db = out.db
const onNotice = (n) => console.log('  ', n.message)
await db.exec('begin')
await db.exec(
  `do $$ begin execute replace(pg_get_functiondef('world.best_sales(uuid,uuid)'::regprocedure), 'FUNCTION world.best_sales(', 'FUNCTION pg_temp.best_sales_before('); end $$;`,
)
await db.exec((await readFile(path.join(MIGRATIONS_DIR, APPLY), 'utf8')).replaceAll('\r', ''))
await db.exec(
  `do $s$
declare
  c_uid constant uuid := '00000000-0351-4000-8000-0000000000bb';
  v_pl uuid; v_fl uuid; v_home uuid; t timestamptz; i int; a numeric[] := '{}'; b numeric[] := '{}';
begin
  v_pl := public.new_house(c_uid, 'Probe paired', 'PRT');
  select id, port_id into v_fl, v_home from public.fleets where player_id = v_pl;
  perform cmd.assume_identity(c_uid);
  ${PURSE === null ? '' : `update public.players set ducats = ${PURSE} where id = v_pl;`}
  perform pg_temp.best_sales_before(v_fl, v_home), world.best_sales(v_fl, v_home);   -- warm both
  for i in 1 .. ${N} loop
    t := clock_timestamp(); perform pg_temp.best_sales_before(v_fl, v_home); a := a || (extract(epoch from clock_timestamp() - t) * 1000)::numeric;
    t := clock_timestamp(); perform world.best_sales(v_fl, v_home); b := b || (extract(epoch from clock_timestamp() - t) * 1000)::numeric;
  end loop;
  raise notice 'best_sales where she lies (%, purse %), % alternated pairs: BEFORE median % ms (min %, max %), AFTER median % ms (min %, max %)',
    (select code from public.ports where id = v_home), (select ducats from public.players where id = v_pl), ${N},
    (select round(percentile_cont(0.5) within group (order by x)::numeric) from unnest(a) x), (select round(min(x)) from unnest(a) x), (select round(max(x)) from unnest(a) x),
    (select round(percentile_cont(0.5) within group (order by x)::numeric) from unnest(b) x), (select round(min(x)) from unnest(b) x), (select round(max(x)) from unnest(b) x);
end $s$;`,
  { onNotice },
)
await db.exec('rollback')
await db.close()
