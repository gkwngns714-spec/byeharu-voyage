// slim-db (0409): writes before.sql, after.sql (read-only on prod) and rollback-0409.sql (a draft, local only) from the migration's own hunks,
// so the three files can never disagree with it. Run from the repo root after any edit of the migration:
//   node scripts/ops/harness/slim-db/gen.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'

const DIR = 'supabase/migrations'
const file = readdirSync(DIR).find((f) => f.endsWith('_the_world_fits_the_harbour_it_has.sql'))
const NUM = file.slice(10, 14)
const mig = readFileSync(`${DIR}/${file}`, 'utf8')
const fns = ['public.tick_market_drift(timestamp with time zone,uuid)', 'public.tick_market_drift_each_port()',
  'public.npc_compact_houses(uuid[],timestamp with time zone)', 'public.tick_compact(boolean,boolean)']
const re = /\((\d), c_cut\[(\d)\],\n\$h\$([\s\S]*?)\$h\$,\n\$h\$([\s\S]*?)\$h\$\)/g
const hunks = []
let m
while ((m = re.exec(mig))) hunks.push({ ord: +m[1], fn: fns[+m[2] - 1], old: m[3], new: m[4] })
if (hunks.length !== 5) throw new Error(`expected 5 hunks, read ${hunks.length}`)
const E = (s) => "E'" + s.replace(/\\/g, '\\\\').replace(/'/g, "''").replace(/\n/g, '\\n') + "'"

const check = (name) => `-- ${NUM} PROD CHECK, ${name === 'before' ? 'BEFORE the deploy' : 'AFTER the deploy (the same read as before.sql, under its own name)'}, read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/slim-db/${name}.sql
-- Written by gen.mjs from the migration's hunks. One row, one jsonb column \`r\`. It reads the catalog, world_config, cron.job, the ports and the
-- newest rows of three small ring tables; no large table.
-- BEFORE, wanted: head 2026081800${String(+NUM - 1).padStart(4, '0')}; applied false; hunks: every \`old\` 1 and every \`new\` 0 (prod's bodies are the
--   pre-images); index_closed_at true; wants_trigger forbid_mutation; stats_schedule "6,21,36,51 * * * *"; knobs: npc_retention_hours 6,
--   stats_city_good_keep_days 0, stats_city_good_fine_hours 48 (if the owner has set another value ${NUM} leaves it: say so in the after read).
-- AFTER, wanted: head 2026081800${NUM}; applied true; hunks: every \`new\` 1 and every \`old\` 0, but hunk 5, whose new text ends with its old line
--   (its \`old\` reads 1); index_closed_at false; wants_trigger city_wants_guard; stats_schedule "6,36 * * * *"; knobs:
--   drift_spread_runs 10, npc_retention_hours 3, stats_city_good_keep_days 3, stats_city_good_fine_hours 26, city_wants_keep_periods 10,
--   npc_route_lap_keep 24, npc_route_lap_keep_hours 26, compact_trim_rows 2000, compact_budget_ms 8000, compact_hold_ms 200, compact_batch_max 25;
--   drift_due about a tenth of the ports.
-- WHAT IT MEASURES (both sides; write the before read down):
--   beat      the arrivals beat, the last 10 minutes of its ring: beats, mean ms, p95 ms, errors.
--   compact   the compactor's 5 newest receipts: ms, houses cut, due, left, the oldest row waiting against the cut, ms a house.
--   stats     the Stats count's 2 newest runs: ms and each phase's ms.
-- READING after the deploy, at +30 min, +3 h, +24 h: beat mean falls (about 12 s on 2026-11-14) as the drift's writes stop crowding the disk;
--   compact.left RISES first (the books are cut to 3 hours: every house is due at once) and then falls to a handful as ms_house falls;
--   stats.ms falls from 23 to 26 s. Then scripts/ops/harness/slim-db/health.sql for the sizes and the windows.
begin transaction read only;
with hk(ord, fn, old, new) as (values
${hunks.map((h) => `  (${h.ord}, '${h.fn}', ${E(h.old)}, ${E(h.new)})`).join(',\n')}
), body as (
  select hk.ord, hk.fn, hk.old, hk.new, replace(pg_get_functiondef(hk.fn::regprocedure), E'\\r', '') as def from hk
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', to_regprocedure('public.drift_ports_due(timestamp with time zone)') is not null,
  'hunks', (select jsonb_agg(jsonb_build_object('ord', b.ord, 'fn', b.fn,
                     'old', (length(b.def) - length(replace(b.def, b.old, ''))) / length(b.old),
                     'new', (length(b.def) - length(replace(b.def, b.new, ''))) / length(b.new)) order by b.ord) from body b),
  'index_closed_at', to_regclass('public.standing_route_laps_closed_at') is not null,
  'wants_trigger', (select p.proname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
                     where t.tgrelid = 'public.city_wants'::regclass and t.tgname = 'city_wants_append_only'),
  'stats_schedule', (select j.schedule from cron.job j where j.jobname = 'byeharu-voyage:stats'),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('drift_spread_runs', 'npc_retention_hours', 'stats_city_good_keep_days', 'stats_city_good_fine_hours', 'city_wants_keep_periods',
                             'npc_route_lap_keep', 'npc_route_lap_keep_hours', 'compact_trim_rows', 'compact_budget_ms', 'compact_hold_ms', 'compact_batch_max',
                             'drift_slot_seconds', 'game_day_seconds', 'drift_sigma', 'drift_theta', 'standing_route_lap_keep')),
  'ports', (select count(*) from public.ports),
  'drift_due', (select count(*) from (select row_number() over (order by po.id) as k from public.ports po) x
                 where coalesce((select (c.value #>> '{}')::int from public.world_config c where c.key = 'drift_spread_runs'), 1) <= 1
                    or x.k % (select (c.value #>> '{}')::int from public.world_config c where c.key = 'drift_spread_runs')
                       = floor(extract(epoch from now()) / 60)::bigint % (select (c.value #>> '{}')::int from public.world_config c where c.key = 'drift_spread_runs')),
  'beat', (select jsonb_build_object('beats', count(*), 'mean_ms', round(avg(b.ms)), 'p95_ms', round((percentile_cont(0.95) within group (order by b.ms))::numeric),
                                     'errors', count(*) filter (where b.error is not null))
             from public.arrivals_beats b where b.at > now() - interval '10 minutes'),
  'compact', (select jsonb_agg(jsonb_build_object('at', c.at, 'ms', c.ms, 'houses', c.receipt->'houses', 'due', c.receipt->'due', 'left', c.receipt->'left',
                                                  'oldest', c.receipt->'oldest', 'before', c.receipt->'before', 'ms_house', c.receipt->'ms_house',
                                                  'failed', c.receipt->'failed', 'note', c.receipt->'note') order by c.at desc)
                from (select * from public.compact_runs order by at desc limit 5) c),
  'stats', (select jsonb_agg(jsonb_build_object('at', s.at, 'ms', s.ms, 'phases', s.receipt->'phases') order by s.at desc)
              from (select * from public.stats_runs order by at desc limit 2) s)
) as r;
commit;
`
writeFileSync('scripts/ops/harness/slim-db/before.sql', check('before'))
writeFileSync('scripts/ops/harness/slim-db/after.sql', check('after'))

const rollback = `-- ${NUM} FORWARD ROLLBACK, A DRAFT (written by gen.mjs from the migration's hunks). NOT a prod check and NOT a migration yet: to use it, strip the
-- guard line, give it the next number, add "-- news: none" and deploy it as any migration (owner only).
-- FIRST, WITH NO FILE (owner, one knob each): drift_spread_runs 1 steps every harbour every run again; npc_route_lap_keep 0 stops the merchants' lap
-- trim; city_wants_keep_periods 0 stops the wants' trim; stats_city_good_keep_days 0 stops that trim; npc_retention_hours 6 keeps six hours of the
-- merchants' books again. Rows already deleted do not come back by any of these, nor by this file.
-- This draft takes the code away: the four bodies go back to their text before ${NUM} (the five hunks reversed; each hunk's NEW text must occur once,
-- else it refuses: a later file re-cut those lines and the draft is stale), public.city_wants takes public.forbid_mutation back, the two new functions
-- and the eight new knobs go, the three moved knobs go back (only where they still hold ${NUM}'s value), the index is built again and the Stats count
-- runs four times an hour again. CREATE INDEX here is NOT concurrent (a migration runs in a transaction): on prod build it first, by hand, with
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS (scripts/ops/harness/slim-db/RUNBOOK.md), and this file then finds it there.
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
  drop trigger city_wants_append_only on public.city_wants;
  create trigger city_wants_append_only before delete or update on public.city_wants
    for each row execute function public.forbid_mutation();
  drop function public.city_wants_guard();
  drop function public.drift_ports_due(timestamptz);
  delete from public.world_config where key in ('drift_spread_runs', 'city_wants_keep_periods', 'npc_route_lap_keep', 'npc_route_lap_keep_hours',
                                                'compact_trim_rows', 'compact_budget_ms', 'compact_hold_ms', 'compact_batch_max');
  update public.world_config set value = to_jsonb(0) where key = 'stats_city_good_keep_days' and value = to_jsonb(3);
  update public.world_config set value = to_jsonb(48) where key = 'stats_city_good_fine_hours' and value = to_jsonb(26);
  update public.world_config set value = to_jsonb(6) where key = 'npc_retention_hours' and value = to_jsonb(3);
  create index if not exists standing_route_laps_closed_at on public.standing_route_laps using btree (closed_at) where (closed_at is not null);
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select cron.alter_job(j.jobid, schedule := '6,21,36,51 * * * *') from cron.job j
                where j.jobname = 'byeharu-voyage:stats' and j.schedule = '6,36 * * * *'$q$;
  end if;
  raise notice '${NUM} rollback ok: the four bodies are their text before ${NUM}; city_wants is under public.forbid_mutation; the knobs, the index and the Stats schedule are back.';
end $r$;
`
writeFileSync('scripts/ops/harness/slim-db/rollback-0409.sql'.replace('0409', NUM), rollback)
console.log(`slim-db: ${NUM}, ${hunks.length} hunks -> before.sql, after.sql, rollback-${NUM}.sql`)
