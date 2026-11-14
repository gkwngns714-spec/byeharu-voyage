-- 0412 PROD CHECK, AFTER the deploy (the same read as before.sql, under its own name), read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/day-hour/after.sql
-- One row, one jsonb column `r`. It reads world_config, pg_proc, the SAILING voyages (about 1,300 rows, by the partial index) and the last
-- half hour of public.arrivals_beats (3,600 rows at most). No function of the game is called.
-- BEFORE, wanted: head 20260818000411; applied false; hunk_once 1 (the snapshot's line is as this file was written against);
--   knobs.time_compression 960 (0412 REFUSES at any other value); door false.
-- AFTER, wanted: head 20260818000412; applied true; knobs.time_compression 192, clock_voyage_days 8; clock.is 192, clock.was 960,
--   clock.at the deploy's instant; door true; hunk_once 1 still (the old line is kept inside the new text).
-- WHAT IT MEASURES (both sides; write the before read down):
--   at_sea       the voyages at sea: n, of players (not merchants); seconds left to their arrival: median, p90, the longest; overdue (eta passed, not
--                yet settled). After the deploy the median and the longest are about five times the before read; n does not jump.
--   holds        battles' holds running now on voyages at sea (0412 re-times them; such a battle runs its full length).
--   beat[]       the arrivals beat by 5-minute block, last 30 minutes: beats, mean ms, p95 ms, fleets settled and voyage days settled a minute.
--                READING after the deploy at +30 min and +2 h: fleets and days a minute fall toward a fifth of the before read. The beat's ms
--                will fall less: its fixed cost each second and the market's passes are not sailing.
--   market       game_day_seconds, drift_slot_seconds, drift_sigma, drift_theta, want_period_seconds as they stand: NOT moved by 0412.
begin transaction read only;
with hk(old) as (values (E'        ''time_compression'',  public.wc_int(''time_compression''),\n')),
body as (select replace(pg_get_functiondef('world.snapshot()'::regprocedure), E'\r', '') as def),
sea as (
  select v.id, extract(epoch from v.eta - now()) as left_s, pl.is_npc
    from public.voyages v join public.players pl on pl.id = v.player_id
   where v.status = 'SAILING'
),
beat as (
  select date_trunc('hour', b.at) + floor(extract(minute from b.at) / 5) * interval '5 minutes' as block,
         count(*) as beats, round(avg(b.ms)) as mean_ms, round((percentile_cont(0.95) within group (order by b.ms))::numeric) as p95_ms,
         round(sum(b.fleets) / 5.0, 1) as fleets_min, round(sum(b.days) / 5.0, 1) as days_min, count(*) filter (where b.error is not null) as errors
    from public.arrivals_beats b
   where b.at >= now() - interval '30 minutes'
   group by 1
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', exists (select 1 from public.world_config where key = 'clock_anchor'),
  'door', to_regprocedure('public.clock_set(integer,timestamp with time zone)') is not null,
  'hunk_once', (select (length(b.def) - length(replace(b.def, h.old, ''))) / length(h.old) from body b, hk h),
  'knobs', (select jsonb_object_agg(wc.key, wc.value) from public.world_config wc
             where wc.key in ('time_compression', 'clock_voyage_days', 'route_rest_voyage_days', 'port_prep_seconds', 'battle_seconds', 'npc_fleet_max')),
  'clock', (select wc.value from public.world_config wc where wc.key = 'clock_anchor'),
  'market', (select jsonb_object_agg(wc.key, wc.value) from public.world_config wc
              where wc.key in ('game_day_seconds', 'drift_slot_seconds', 'drift_sigma', 'drift_theta', 'want_period_seconds', 'contract_deadline_days', 'standing_route_laps_per_game_day')),
  'at_sea', (select jsonb_build_object('n', count(*), 'players', count(*) filter (where not s.is_npc), 'overdue', count(*) filter (where s.left_s <= 0),
                                       'left_s_median', round((percentile_cont(0.5) within group (order by s.left_s))::numeric),
                                       'left_s_p90', round((percentile_cont(0.9) within group (order by s.left_s))::numeric),
                                       'left_s_max', round(max(s.left_s)::numeric)) from sea s),
  'holds', (select count(*) from sea s join public.voyage_events ve on ve.voyage_id = s.id
             where ve.day_index >= 1000000 and (ve.payload->>'held_from')::timestamptz < now() and (ve.payload->>'held_until')::timestamptz > now()),
  'beat', (select jsonb_agg(to_jsonb(b) order by b.block) from beat b)
) as r;
commit;
