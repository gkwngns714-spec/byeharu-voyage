-- 0409 PROD CHECK, AFTER the deploy (the same read as before.sql, under its own name), read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/slim-db/after.sql
-- Written by gen.mjs from the migration's hunks. One row, one jsonb column `r`. It reads the catalog, world_config, cron.job, the ports and the
-- newest rows of three small ring tables; no large table.
-- BEFORE, wanted: head 20260818000408; applied false; hunks: every `old` 1 and every `new` 0 (prod's bodies are the
--   pre-images); index_closed_at true; wants_trigger forbid_mutation; stats_schedule "6,21,36,51 * * * *"; knobs: npc_retention_hours 6,
--   stats_city_good_keep_days 0, stats_city_good_fine_hours 48 (if the owner has set another value 0409 leaves it: say so in the after read).
-- AFTER, wanted: head 20260818000409; applied true; hunks: every `new` 1 and every `old` 0, but hunk 5, whose new text ends with its old line
--   (its `old` reads 1); index_closed_at false; wants_trigger city_wants_guard; stats_schedule "6,36 * * * *"; knobs:
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
  (1, 'public.tick_market_drift(timestamp with time zone,uuid)', E'     set drift = case when pg.drift_slot < v_slot then greatest(-v_clamp, least(v_clamp,\n                   v_theta * pg.drift\n                   + v_sigma * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random()))) else pg.drift end,\n', E'     -- 0409: ONE COMPOUNDED STEP FOR THE SLOTS MISSED. A row k slots behind (the drift job steps one harbour in drift_spread_runs a run; a\n     -- skipped harbour; a job that was down) takes theta^k x drift + sigma x sqrt((1 - theta^2k) / (1 - theta^2)) x N(0,1): the law of k\n     -- one-slot steps, so a price moves as far in a game day whatever the spread. k = 1 is the step as it always was (theta x drift +\n     -- sigma x N). k is read to 10,000 slots: past that the walk has forgotten where it was.\n     set drift = case when pg.drift_slot < v_slot then greatest(-v_clamp, least(v_clamp,\n                   case when v_slot - pg.drift_slot <= 1 then v_theta\n                        else power(v_theta, least(v_slot - pg.drift_slot, 10000)::numeric) end * pg.drift\n                   + v_sigma * case when v_slot - pg.drift_slot <= 1 or abs(v_theta) >= 1 then 1\n                                    else sqrt((1 - power(v_theta, (2 * least(v_slot - pg.drift_slot, 10000))::numeric)) / (1 - v_theta * v_theta)) end\n                     * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random()))) else pg.drift end,\n'),
  (2, 'public.tick_market_drift_each_port()', E'  for p in select po.id, po.code from public.ports po order by po.id loop\n', E'  -- 0409: the harbours whose turn this minute is (public.drift_ports_due: one in drift_spread_runs; the step is compounded over the slots missed)\n  for p in select d.id, d.code from public.drift_ports_due(v_now) d order by d.id loop\n'),
  (3, 'public.npc_compact_houses(uuid[],timestamp with time zone)', E'  get diagnostics v_ev = row_count;\n\n  perform set_config(''byeharu.npc_compact'', ''off'', true);\n', E'  get diagnostics v_ev = row_count;\n\n  -- 0409: A MERCHANT''S LAP HISTORY. A closed lap of one of these houses'' routes that is BOTH past the route''s newest npc_route_lap_keep AND\n  -- closed more than npc_route_lap_keep_hours ago goes, at most compact_trim_rows a batch (the rest at her next visit). What stays is what\n  -- the game reads of a merchant''s laps: the last 24 hours and the lap before them (public.route_earnings, world.fleet_trades,\n  -- public.stats_merchants_window), the newest 20 inside three days (public.npc_share_budget), the newest few. A player''s route is not read\n  -- here (v_hs holds merchants alone); cmd.standing_route_close_lap keeps standing_route_lap_keep of it, as before. 0 = OFF.\n  if public.wc_int(''npc_route_lap_keep'') > 0 then\n    delete from public.standing_route_laps x\n     where x.id = any(array(\n             select l.id\n               from public.standing_routes sr\n               join public.standing_route_laps l on l.route_id = sr.id\n              where sr.player_id = any(v_hs)\n                and l.closed_at is not null\n                and l.closed_at < p_now - make_interval(hours => greatest(public.wc_int(''npc_route_lap_keep_hours''), 25))\n                and l.lap_no <= sr.lap_no - greatest(public.wc_int(''npc_route_lap_keep''), 20)\n                and l.id is distinct from sr.lap_id\n              limit greatest(public.wc_int(''compact_trim_rows''), 1)));\n  end if;\n\n  perform set_config(''byeharu.npc_compact'', ''off'', true);\n'),
  (4, 'public.tick_compact(boolean,boolean)', E'  c_budget constant interval := interval ''8 seconds'';   -- the minute''s work, at most\n  c_hold   constant numeric := 200;                     -- ms: the longest a transaction should hold its houses\n  c_bmax   constant int := 25;                          -- houses a transaction, at most\n', E'  -- 0409: the three limits are knobs, at the values the constants had (8 s, 200 ms, 25)\n  c_budget constant interval := make_interval(secs => greatest(public.wc_int(''compact_budget_ms''), 1) / 1000.0);   -- the minute''s work, at most\n  c_hold   constant numeric := greatest(public.wc_int(''compact_hold_ms''), 1);   -- ms: the longest a transaction should hold its houses\n  c_bmax   constant int := greatest(public.wc_int(''compact_batch_max''), 1);     -- houses a transaction, at most\n'),
  (5, 'public.tick_compact(boolean,boolean)', E'  insert into public.compact_runs (slot, at, ms, receipt)\n', E'  -- 0409: THE CITY WANTS OF PAST PERIODS, oldest first, compact_trim_rows a run. The game reads the current period and the one before\n  -- (public.wants_draw, world.city_wants_now, world.want_left); city_wants_keep_periods are kept, never fewer than 2. The table is\n  -- append-only: public.city_wants_guard lets this delete through, and no other (byeharu.wants_trim, this transaction only). 0 = OFF.\n  if public.wc_int(''city_wants_keep_periods'') > 0 then\n    begin\n      perform set_config(''byeharu.wants_trim'', ''on'', true);\n      delete from public.city_wants w\n       where w.ctid = any(array(select x.ctid from public.city_wants x\n                                 where x.period < public.want_period(v_now) - greatest(public.wc_int(''city_wants_keep_periods''), 2)\n                                 order by x.period\n                                 limit greatest(public.wc_int(''compact_trim_rows''), 1)));\n      perform set_config(''byeharu.wants_trim'', ''off'', true);\n    exception when others then\n      v_fail := v_fail + 1;\n      v_note := coalesce(v_note, ''wants: '' || sqlerrm);\n    end;\n    if p_commit then commit; end if;\n  end if;\n  insert into public.compact_runs (slot, at, ms, receipt)\n')
), body as (
  select hk.ord, hk.fn, hk.old, hk.new, replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '') as def from hk
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
