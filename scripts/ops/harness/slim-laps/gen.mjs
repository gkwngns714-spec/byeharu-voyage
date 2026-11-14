// slim-laps (0416): writes before.sql, after.sql (read-only on prod) and rollback-<n>.sql (a draft, local only) from the migration's own hunks,
// so the three files can never disagree with it. Run from the repo root after any edit or renumber of the migration:
//   node scripts/ops/harness/slim-laps/gen.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'

const DIR = 'supabase/migrations'
const file = readdirSync(DIR).find((f) => f.endsWith('_a_merchant_keeps_her_ten_newest_laps.sql'))
const NUM = file.slice(10, 14)
const mig = readFileSync(`${DIR}/${file}`, 'utf8')
const fns = ['public.route_earnings(uuid)', 'world.fleet_trades(uuid)',
  'public.stats_merchants_window(timestamp with time zone,timestamp with time zone)', 'public.npc_share_budget(timestamp with time zone,uuid,bigint)',
  'public.npc_compact_houses(uuid[],timestamp with time zone)', 'public.tick_compact(boolean,boolean)']
const re = /\((\d), c_cut\[(\d)\],\n\$h\$([\s\S]*?)\$h\$,\n\$h\$([\s\S]*?)\$h\$\)/g
const hunks = []
let m
while ((m = re.exec(mig))) hunks.push({ ord: +m[1], fn: fns[+m[2] - 1], old: m[3], new: m[4] })
if (hunks.length !== 7) throw new Error(`expected 7 hunks, read ${hunks.length}`)
const E = (s) => "E'" + s.replace(/\\/g, '\\\\').replace(/'/g, "''").replace(/\n/g, '\\n') + "'"

const check = (name) => `-- ${NUM} PROD CHECK, ${name === 'before' ? 'BEFORE the deploy' : 'AFTER the deploy (the same read as before.sql, under its own name)'}, read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/slim-laps/${name}.sql
-- Written by gen.mjs from the migration's hunks. One row, one jsonb column \`r\`. It reads the catalog, world_config and one small ring table; no large table.
-- BEFORE, wanted: head = the migration before this file's number; applied false; hunks: every \`old\` 1 and every \`new\` 0 (prod's bodies are the
--   pre-images: 0409's, and whatever 0410 to 0415 left of these six functions, which is nothing); knobs: npc_route_lap_keep 24,
--   npc_route_lap_keep_hours 26, stats_city_good_keep_days 3, stats_city_good_hour_days 7 (a value the owner has since set is left alone: say so).
--   laps.heap_mb: THE FILL READS THE WHOLE LAP TABLE ONCE. Under about 80 MB (the RUNBOOK's rewrite has run) it takes seconds; at the 226 MB of
--   2026-11-14 with the disk throttled it can take a minute: run scripts/ops/harness/slim-db/RUNBOOK.md step 3b for standing_route_laps first.
-- AFTER, wanted: head = this file's number; applied true; hunks: every \`new\` 1; trigger true; knobs: npc_route_lap_keep 10,
--   npc_route_lap_keep_hours 0, route_hour_keep_hours 80, npc_invest_lap_hours 8, stats_city_good_keep_days 30, stats_city_good_hour_days 2;
--   book.rows above 0 at once (the fill) and about 900 x 80 = 72,000 after three days; laps.rows falling toward about 12 a merchant route
--   (11,000) over the compactor's next pass of every house (an hour or two).
-- READING after the deploy, at +30 min, +3 h, +24 h: open a merchant's fleet card: "today" and its laps read as before; the Stats tab's merchants
--   (profit a day, laps a day, losing) continuous across the deploy. Then scripts/ops/harness/slim-db/health.sql.
begin transaction read only;
with hk(ord, fn, old, new) as (values
${hunks.map((h) => `  (${h.ord}, '${h.fn}', ${E(h.old)}, ${E(h.new)})`).join(',\n')}
), body as (
  select hk.ord, hk.fn, hk.old, hk.new, replace(pg_get_functiondef(hk.fn::regprocedure), E'\\r', '') as def from hk
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', to_regclass('public.route_hour_laps') is not null,
  'hunks', (select jsonb_agg(jsonb_build_object('ord', b.ord, 'fn', b.fn,
                     'old', (length(b.def) - length(replace(b.def, b.old, ''))) / length(b.old),
                     'new', (length(b.def) - length(replace(b.def, b.new, ''))) / length(b.new)) order by b.ord) from body b),
  'trigger', exists (select 1 from pg_trigger t where t.tgrelid = 'public.standing_route_laps'::regclass and t.tgname = 'standing_route_laps_hour_book'),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('npc_route_lap_keep', 'npc_route_lap_keep_hours', 'route_hour_keep_hours', 'npc_invest_lap_hours', 'stats_city_good_keep_days',
                             'stats_city_good_hour_days', 'stats_city_good_fine_hours', 'standing_route_lap_keep', 'compact_trim_rows')),
  'laps', (select jsonb_build_object('rows', c.reltuples::bigint, 'heap_mb', pg_relation_size(c.oid) / 1048576, 'total_mb', pg_total_relation_size(c.oid) / 1048576)
             from pg_class c where c.oid = 'public.standing_route_laps'::regclass),
  'book', (select jsonb_build_object('rows', c.reltuples::bigint, 'total_mb', pg_total_relation_size(c.oid) / 1048576)
             from pg_class c where c.oid = to_regclass('public.route_hour_laps')),
  'compact', (select jsonb_agg(jsonb_build_object('at', c.at, 'ms', c.ms, 'houses', c.receipt->'houses', 'left', c.receipt->'left',
                                                  'failed', c.receipt->'failed', 'note', c.receipt->'note') order by c.at desc)
                from (select * from public.compact_runs order by at desc limit 3) c)
) as r;
`
writeFileSync('scripts/ops/harness/slim-laps/before.sql', check('before'))
writeFileSync('scripts/ops/harness/slim-laps/after.sql', check('after'))

const rollback = `-- ${NUM} FORWARD ROLLBACK, A DRAFT (written by gen.mjs from the migration's hunks). NOT a prod check and NOT a migration yet: to use it, strip the
-- guard line, give it the next number, add "-- news: none" and deploy it as any migration (owner only).
-- FIRST, WITH NO FILE (owner, one knob): npc_route_lap_keep 0 stops the trim: a merchant's route then keeps standing_route_lap_keep (100) laps like
-- a player's. Nothing else needs undoing for the figures to be right: the readers are exact wherever the lap rows are kept.
-- This draft takes the code away: the six bodies go back to their text before ${NUM} (the seven hunks reversed; each hunk's NEW text must occur
-- once, else it refuses: a later file re-cut those lines and the draft is stale), the trigger, the three new functions, the hour book and the two
-- new knobs go, and the four moved knobs go back to 0409's values (only where they still hold ${NUM}'s). MIND: the readers then read lap rows
-- again, and a merchant holds only her newest ten: her "today" and the Stats tab's merchants read short until 24 hours of laps have been kept
-- again (0409's rule keeps 26 hours from then on). Deleted lap rows do not come back.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h      record;
  v_def  text;
  v_n    int;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);
  create temp table back_${NUM} (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_${NUM} values
${hunks.map((h) => `  (${h.ord}, '${h.fn}',\n$h$${h.new}$h$,\n$h$${h.old}$h$)`).join(',\n')};
  for h in select * from back_${NUM} order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '${NUM} rollback refuses: hunk % of % occurs % time(s), not once: a later file re-cut it and this draft is stale', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  drop trigger standing_route_laps_hour_book on public.standing_route_laps;
  drop function public.route_hour_post();
  drop function public.route_day(uuid, timestamptz, timestamptz);
  drop function public.route_day_full(uuid, timestamptz);
  drop table public.route_hour_laps;
  delete from public.world_config where key in ('route_hour_keep_hours', 'npc_invest_lap_hours');
  update public.world_config set value = to_jsonb(24) where key = 'npc_route_lap_keep' and value = to_jsonb(10);
  update public.world_config set value = to_jsonb(26) where key = 'npc_route_lap_keep_hours' and value = to_jsonb(0);
  update public.world_config set value = to_jsonb(3) where key = 'stats_city_good_keep_days' and value = to_jsonb(30);
  update public.world_config set value = to_jsonb(7) where key = 'stats_city_good_hour_days' and value = to_jsonb(2);
  raise notice '${NUM} rollback ok: the six bodies are their text before ${NUM}; the hour book, its trigger and its readings are gone; the knobs are 0409''s.';
end $r$;
`
writeFileSync(`scripts/ops/harness/slim-laps/rollback-${NUM}.sql`, rollback)
console.log(`slim-laps: ${NUM}, ${hunks.length} hunks -> before.sql, after.sql, rollback-${NUM}.sql`)
