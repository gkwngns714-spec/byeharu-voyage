-- 0413 PROD CHECK, BEFORE the deploy AND AGAIN AFTER IT (the same read; after.sql is this file under its own name), read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/day-hour/before.sql
-- One row, one jsonb column `r`. It reads world_config, pg_proc, the SAILING voyages (about 1,300 rows, by the partial index), the last half hour of
-- public.arrivals_beats (3,600 rows at most) and public.ports (249). It calls public.drift_ports_due (STABLE, 0409) and no other function of the game.
-- BEFORE, wanted: head 20260818000412; applied false; door false; hunks: every count 1 (each old text once in the live body: prod's bodies are the
--   pre-images); knobs.time_compression 960 (0413 REFUSES at any other value). WRITE DOWN knobs, market and rates: 0413 multiplies or divides
--   whatever stands there by 5.
-- AFTER, wanted: head 20260818000413; applied true; door true; knobs.time_compression 192, clock_voyage_days 8; clock.is 192, clock.was 960;
--   market: game_day_seconds, drift_slot_seconds, want_period_seconds, population_slot_seconds and drift_spread_runs each FIVE TIMES the before read
--   (on prod 60 -> 300, 60 -> 300, ? -> x5, 600 -> 3000, 10 -> 50); rates: navy_upkeep_day, works_coupon_day, pirate_spend_day_pct and
--   population_tax_per_1000 each A FIFTH, glut_half_life_hours and invested_half_life_hours five times; counters: each kind's count is the before
--   read's count or a few more (never less, never thousands more), and `anchor` holds the four kinds.
-- WHAT IT MEASURES (both sides):
--   at_sea       the voyages at sea: n, of players; seconds left to their arrival: median, p90, the longest; overdue. After the deploy the median
--                and the longest are about five times the before read; n does not jump.
--   holds        battles' holds running now on voyages at sea (0413 re-times them; such a battle runs its full length).
--   beat[]       the arrivals beat by 5-minute block, last 30 minutes: beats, mean ms, p95 ms, fleets settled and voyage days settled a minute.
--                READING at +30 min and +2 h: fleets and days a minute fall toward a fifth; the beat's ms falls with the disk.
--   drift_due    how many harbours the drift job steps in this minute's run (public.drift_ports_due): about 25 of 249 before, about 5 after.
begin transaction read only;
with hk(ord, fn, old) as (values
  (1, 'world.snapshot()', E'        ''time_compression'',  public.wc_int(''time_compression''),\n'),
  (2, 'world.game_day(timestamp with time zone)', E' select floor(extract(epoch from p_at) / public.wc_num(''game_day_seconds''))::int '),
  (3, 'public.drift_slot_of(timestamp with time zone)', E'  select floor(extract(epoch from p_at) / public.wc_num(''drift_slot_seconds''))::bigint;\n'),
  (4, 'public.want_period(timestamp with time zone)', E'  select floor(extract(epoch from p_at) / public.wc_num(''want_period_seconds''))::bigint\n'),
  (5, 'public.next_drift_change_at(timestamp with time zone)', E'  select to_timestamp(((public.drift_slot_of(p_at) + 1) * public.wc_num(''drift_slot_seconds''))::double precision);\n'),
  (6, 'public.tick_market_drift(timestamp with time zone,uuid)', E'  v_slot   bigint := floor(extract(epoch from p_now) / public.wc_num(''drift_slot_seconds''))::bigint;\n'),
  (7, 'public.population_tick(timestamp with time zone)', E'  v_slot  bigint := floor(extract(epoch from p_now) / 600)::bigint;\n'),
  (8, 'world.contracts(uuid)', E'        ''expires_at'', to_timestamp(c.expires_day * public.wc_num(''game_day_seconds''))) order by c.expires_day, g.code), ''[]''::jsonb)\n'),
  (9, 'public.city_coupons(uuid,timestamp with time zone)', E'greatest(0, (v_today - s.accrued_day) * v_gds / 86400))\n')
), body as (
  select h.ord, h.fn, (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as n
    from hk h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d
), sea as (
  select v.id, extract(epoch from v.eta - now()) as left_s, pl.is_npc
    from public.voyages v join public.players pl on pl.id = v.player_id
   where v.status = 'SAILING'
), beat as (
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
  'hunks', (select jsonb_object_agg(b.ord || ' ' || b.fn, b.n) from body b),
  'knobs', (select jsonb_object_agg(wc.key, wc.value) from public.world_config wc
             where wc.key in ('time_compression', 'clock_voyage_days', 'route_rest_voyage_days', 'port_prep_seconds', 'battle_seconds', 'npc_fleet_max', 'contract_deadline_days')),
  'clock', (select wc.value from public.world_config wc where wc.key = 'clock_anchor'),
  'market', (select jsonb_object_agg(wc.key, wc.value) from public.world_config wc
              where wc.key in ('game_day_seconds', 'drift_slot_seconds', 'want_period_seconds', 'population_slot_seconds', 'drift_spread_runs', 'drift_sigma', 'drift_theta')),
  'rates', (select jsonb_object_agg(wc.key, wc.value) from public.world_config wc
             where wc.key in ('navy_upkeep_day', 'works_coupon_day', 'pirate_spend_day_pct', 'population_tax_per_1000', 'glut_half_life_hours', 'invested_half_life_hours')),
  'anchor', (select wc.value from public.world_config wc where wc.key = 'market_clock_anchor'),
  'counters', jsonb_build_object(
     'game_day_of_now', floor(extract(epoch from now()) / (select (wc.value #>> '{}')::numeric from public.world_config wc where wc.key = 'game_day_seconds')),
     'drift_slot_of_now', floor(extract(epoch from now()) / (select (wc.value #>> '{}')::numeric from public.world_config wc where wc.key = 'drift_slot_seconds')),
     'note', 'BEFORE: these ARE the counters. AFTER: read the counters from anchor (count + whole periods since epoch); these two are then a fifth and mean nothing'),
  'drift_due', (select count(*) from public.drift_ports_due(now())),
  'at_sea', (select jsonb_build_object('n', count(*), 'players', count(*) filter (where not s.is_npc), 'overdue', count(*) filter (where s.left_s <= 0),
                                       'left_s_median', round((percentile_cont(0.5) within group (order by s.left_s))::numeric),
                                       'left_s_p90', round((percentile_cont(0.9) within group (order by s.left_s))::numeric),
                                       'left_s_max', round(max(s.left_s)::numeric)) from sea s),
  'holds', (select count(*) from sea s join public.voyage_events ve on ve.voyage_id = s.id
             where ve.day_index >= 1000000 and (ve.payload->>'held_from')::timestamptz < now() and (ve.payload->>'held_until')::timestamptz > now()),
  'beat', (select jsonb_agg(to_jsonb(b) order by b.block) from beat b)
) as r;
commit;
