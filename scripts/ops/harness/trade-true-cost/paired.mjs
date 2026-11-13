// paired.mjs — world.best_sales and world.good_board BEFORE and AFTER 0361, ALTERNATED in one transaction on the LOCAL cached world (PGlite). LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/trade-true-cost/paired.mjs [--n=15] [--closed]
//
// Two runs a minute apart differ by more than a small change does on this PC, so the bodies before the migration are kept as pg_temp copies (each old body
// asking the old pieces: the old world.board_sell asks the old world.board_legs, the old world.good_board and world.best_sales ask the old world.board_sell),
// the migration is applied, and a new company where she lies asks the old and the new read in turn n times: the medians are of the same minute, the same
// cache, the same world. --closed turns the economy closed with the city purses lit first (dock fees and port time in force), inside the same transaction.
// Everything is rolled back; the cache is only read.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const APPLY = '20260818000361_trade_says_what_a_trip_really_costs.sql'
const N = Number(arg('n') ?? 15)
const CLOSED = process.argv.includes('--closed')
const files = []
for (const name of await migrationFiles()) {
  if (name >= APPLY.slice(0, 14)) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: process.env.PREFIX_DIR || PREFIX_CACHE_DIR, log: console.log, required: true, snapshots: false })
const db = out.db
const onNotice = (n) => console.log('  ', n.message)
await db.exec('begin')
await db.exec(`do $$
begin
  execute replace(pg_get_functiondef('world.board_legs(uuid,jsonb)'::regprocedure), 'FUNCTION world.board_legs(', 'FUNCTION pg_temp.board_legs_before(');
  execute replace(replace(pg_get_functiondef('world.board_sell(uuid,uuid,jsonb)'::regprocedure), 'FUNCTION world.board_sell(', 'FUNCTION pg_temp.board_sell_before('),
                  'world.board_legs(', 'pg_temp.board_legs_before(');
  execute replace(replace(pg_get_functiondef('world.good_board(uuid,uuid,uuid,numeric)'::regprocedure), 'FUNCTION world.good_board(', 'FUNCTION pg_temp.good_board_before('),
                  'world.board_sell(', 'pg_temp.board_sell_before(');
  execute replace(replace(replace(pg_get_functiondef('world.best_sales(uuid,uuid)'::regprocedure), 'FUNCTION world.best_sales(', 'FUNCTION pg_temp.best_sales_before('),
                  'world.board_sell(', 'pg_temp.board_sell_before('), 'world.board_legs(', 'pg_temp.board_legs_before(');
end $$;`)
await db.exec((await readFile(path.join(MIGRATIONS_DIR, APPLY), 'utf8')).replaceAll('\r', ''))

/** One alternated pair of runs, reported as median (min .. max). */
const pair = (label, before, after, digits = 0) => `
  a := '{}'; b := '{}';
  for i in 1 .. ${N} loop
    t := clock_timestamp(); perform ${before}; a := a || (extract(epoch from clock_timestamp() - t) * 1000)::numeric;
    t := clock_timestamp(); perform ${after}; b := b || (extract(epoch from clock_timestamp() - t) * 1000)::numeric;
  end loop;
  raise notice '${label}: BEFORE % ms (% .. %), AFTER % ms (% .. %)',
    (select round(percentile_cont(0.5) within group (order by x)::numeric, ${digits}) from unnest(a) x), (select round(min(x), ${digits}) from unnest(a) x), (select round(max(x), ${digits}) from unnest(a) x),
    (select round(percentile_cont(0.5) within group (order by x)::numeric, ${digits}) from unnest(b) x), (select round(min(x), ${digits}) from unnest(b) x), (select round(max(x), ${digits}) from unnest(b) x);`

await db.exec(
  `do $s$
declare
  c_uid constant uuid := '00000000-0361-4000-8000-0000000000bb';
  v_pl uuid; v_fl uuid; v_home uuid; v_other uuid; v_good uuid; v_code text; t timestamptz; i int; v_ctx jsonb;
  a numeric[]; b numeric[];
begin
  v_pl := public.new_house(c_uid, 'Probe paired 0361', 'PRT');
  ${CLOSED ? `update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');` : ''}
  select id, port_id into v_fl, v_home from public.fleets where player_id = v_pl;
  perform cmd.assume_identity(c_uid);
  select p.id into v_other from public.ports p, public.ports hb
   where hb.id = v_home and p.kind = 'HARBOUR' and p.id <> v_home
     and exists (select 1 from public.port_goods pg where pg.port_id = p.id and public.port_offers(p.id, pg.good_id))
   order by voyage.gc_distance_nm(hb.lat, hb.lon, p.lat, p.lon), p.code limit 1;
  select g.id, g.code into v_good, v_code from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_home and public.port_offers(v_home, g.id) order by g.code limit 1;
  raise notice 'economy closed: %; ${N} pairs each, alternated; median (min .. max)', public.economy_closed();
  perform pg_temp.best_sales_before(v_fl, v_home), world.best_sales(v_fl, v_home);   -- warm both
  ${pair('world.best_sales where she lies', 'pg_temp.best_sales_before(v_fl, v_home)', 'world.best_sales(v_fl, v_home)')}
  ${pair('world.best_sales at another city', 'pg_temp.best_sales_before(v_fl, v_other)', 'world.best_sales(v_fl, v_other)')}
  ${pair('world.good_board, a good bought where she lies', 'pg_temp.good_board_before(v_good, v_fl, v_home, null)', 'world.good_board(v_good, v_fl, v_home, null)')}
  update public.ships s set cargo = jsonb_build_object(v_code, 5), cargo_basis = jsonb_build_object(v_code, 200)
   where s.id = (select x.id from public.ships x where x.fleet_id = v_fl order by x.id limit 1);
  ${pair('world.good_board, her cargo aboard', 'pg_temp.good_board_before(v_good, v_fl, null, null)', 'world.good_board(v_good, v_fl, null, null)')}
  v_ctx := world.board_origin(v_fl) || jsonb_build_object('basis', 'on_board');
  ${pair('world.board_legs (the piece that walks), once', 'pg_temp.board_legs_before(v_fl, v_ctx)', 'world.board_legs(v_fl, v_ctx)', 1)}
end $s$;`,
  { onNotice },
)
await db.exec('rollback')
await db.close()
