-- 0423 PROD CHECK, AFTER the deploy (+30 min and +3 h; before.sql is this read under its own name, run before), read-only, ONE statement, stable functions only:
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/at-sea/after.sql
-- One row, one jsonb column `r`. Run scripts/ops/harness/db-health/gate.sql first (gate_ok true).
-- BEFORE, wanted: head 20260818000421; applied false; old_hunks every count 1 (each pre-image text once in the live body); knobs
--   route_rest_voyage_days 1.333333, npc_route_neighbours 5, npc_route_trade_candidates 6, npc_route_candidates 16, navy_hunt_hours 6
--   (an owner's own value is left by 0423 and named in its receipt: say so). Write `ships` down: it is the "before" of the after-check.
-- AFTER, wanted: head 20260818000423; applied true; new_hunks every count 1; old_hunks 0 but 4 (1: its old lines stand inside the new); knobs 0.266667, 8, 10, 24, 0.0625 and the new four
--   (npc_ask_wait_max_minutes 30, convoy_loads_per_run 10, convoy_load_max 1000000, navy_own_sea_patrol true); the gate green.
-- WHAT `ships` SAYS, per kind (merchants, cargo ships, navy): at_sea, in_port, laid_up, and why in port:
--   merchants: resting (her rest at home), port_time (60 s after a call), laid_up ('no loop pays'), mid_lap, due, other.
--   cargo: home_idle (nothing aboard), home_loaded, away, wreck, laid_up (over her country's number).
--   navy: lying (HUNTING at a harbour), port_time, at_station, elsewhere, laid_up.
-- READING after the deploy (+30 min, +3 h): merchants resting falls from ~110 toward ~25 within 15 minutes (each rest is 2 min, not 10);
--   merchants laid_up falls over the first hour as the line is asked (each at most 30 minutes apart now); cargo at_sea rises at the next :37
--   (the hourly city run loads up to 10 ships a capital); navy lying falls to the few hunting another sea (225 s each) within an hour.
--   beat.mean_ms stays under 1,000 (half the gate's 2,000); waiting_asks spent, if the job's receipts are read, under npc_ask_job_ms.
begin transaction read only;
with hk(ord, fn, old, new) as (values
  (1, 'public.npc_waiting_queue(timestamp with time zone)', E'                      public.wc_int(''npc_ask_broke_under'') as broke) w   -- 0407\n',
      E'                      public.wc_int(''npc_ask_wait_max_minutes'') as cap) w   -- 0423\n'),
  (2, 'public.npc_waiting_queue(timestamp with time zone)', E'                                                         greatest(w.e_min, w.w_min - w.e_min)) end),\n',
      E'                                                         -- 0423: and never past npc_ask_wait_max_minutes (0: 0407''s longest wait alone)\n'),
  (3, 'public.cargo_ships_load(jsonb)', E'  v_ships  int := 0;\nbegin\n', E'  v_i      int;   -- 0423: the ships loaded for this capital this run\n'),
  (4, 'public.cargo_ships_load(jsonb)', E'    v_fleet := null;\n    select c.fleet_id, c.player_id, c.home_port_id, c.nation_id into v_fleet, v_player, v_home, v_nat\n',
      E'    for v_i in 1 .. greatest(1, public.wc_int(''convoy_loads_per_run'')) loop\n'),
  (5, 'public.cargo_ships_load(jsonb)', E'    continue when v_fleet is null or not public.treasury_try_lock(v_home);\n',
      E'    exit when v_fleet is null or not public.treasury_try_lock(v_home);'),
  (6, 'public.cargo_ships_load(jsonb)', E'                 public.cargo_load_room(v_home, v_nat));\n    continue when v_a <= 0;\n',
      E'                 nullif(public.wc_int(''convoy_load_max''), 0));'),
  (9, 'public.cargo_ships_load(jsonb)', E'       and c.ord <= public.convoy_ships_of(c.nation_id)
       and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id))
',
      E'       and coalesce((v_rooms ->> c.home_port_id::text)::bigint, 1) > 0'),
  (7, 'public.cargo_ships_load(jsonb)', E'    v_ships := v_ships + 1;\n  end loop;\n', E'    end loop;   -- 0423\n'),
  (8, 'public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)', E'    if t.port_id = p_home then\n      perform public.fleet_mend(p_fleet);\n',
      E'      if public.wc(''navy_own_sea_patrol'') = ''true''::jsonb then\n')
), body as (
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
    from (values ('public.npc_waiting_queue(timestamp with time zone)'), ('public.cargo_ships_load(jsonb)'),
                 ('public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)')) f(fn)
), m as (
  select case
           when ro.k > public.wc_int('npc_fleet_max') then 'dark'
           when f.status = 'SAILING' then 'at_sea'
           when sr.paused_reason = 'laid_up' then 'laid_up'
           when sr.paused_reason is not null then 'paused'
           when f.status <> 'DOCKED' then 'other'
           when sr.hold_until > now() then 'resting'
           when f.ready_at > now() then 'port_time'
           when sr.lap_id is not null then 'mid_lap'
           else 'due' end as st
    from public.npc_tend_roster() ro
    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
    join public.fleets f on f.id = nf.fleet_id
    join public.standing_routes sr on sr.id = nf.route_id
), c as (
  select case
           when x.laid_up_at is not null then 'laid_up'
           when f.status = 'SAILING' then 'at_sea'
           when public.npc_wrecked(x.fleet_id) then 'wreck'
           when f.status <> 'DOCKED' then 'other'
           when f.port_id = x.home_port_id and exists (select 1 from public.cargo_ship_aboard(x.fleet_id)) then 'home_loaded'
           when f.port_id = x.home_port_id then 'home_idle'
           else 'away' end as st
    from public.cargo_ships x join public.fleets f on f.id = x.fleet_id
), n as (
  select case
           when f.status = 'SAILING' then 'at_sea'
           when x.laid_up_at is not null then 'laid_up'
           when public.npc_wrecked(x.fleet_id) then 'wreck'
           when f.status <> 'DOCKED' then 'other'
           when f.ready_at > now() then 'port_time'
           when x.mission = 'HUNT' and x.hunt_until > now() then 'lying'
           when f.port_id = x.station_port then 'at_station'
           else 'elsewhere' end as st
    from public.navy_ships x join public.fleets f on f.id = x.fleet_id
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', exists (select 1 from public.world_config where key = 'npc_ask_wait_max_minutes'),
  'old_hunks', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.old, ''))) / length(hk.old)) from hk join body b on b.fn = hk.fn),
  'new_hunks', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.new, ''))) / length(hk.new)) from hk join body b on b.fn = hk.fn),
  'bodies', (select jsonb_object_agg(b.fn, md5(b.def)) from body b),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('route_rest_voyage_days', 'npc_route_neighbours', 'npc_route_trade_candidates', 'npc_route_candidates', 'navy_hunt_hours',
                             'npc_ask_wait_max_minutes', 'convoy_loads_per_run', 'convoy_load_max', 'navy_own_sea_patrol', 'time_compression',
                             'npc_replan_every_minutes', 'npc_replan_within_minutes', 'npc_ask_broke_under', 'npc_ask_job_ms', 'navy_hunt_per_day')),
  'ships', jsonb_build_object(
     'merchants', (select jsonb_build_object('n', count(*), 'at_sea', count(*) filter (where m.st = 'at_sea'),
                                             'in_port', count(*) filter (where m.st not in ('at_sea', 'dark')),
                                             'laid_up', count(*) filter (where m.st = 'laid_up'),
                                             'why', (select jsonb_object_agg(z.st, z.k) from (select m2.st, count(*) as k from m m2 group by m2.st) z)) from m),
     'cargo', (select jsonb_build_object('n', count(*), 'at_sea', count(*) filter (where c.st = 'at_sea'),
                                         'in_port', count(*) filter (where c.st not in ('at_sea', 'laid_up')),
                                         'laid_up', count(*) filter (where c.st = 'laid_up'),
                                         'why', (select jsonb_object_agg(z.st, z.k) from (select c2.st, count(*) as k from c c2 group by c2.st) z)) from c),
     'navy', (select jsonb_build_object('n', count(*), 'at_sea', count(*) filter (where n.st = 'at_sea'),
                                        'in_port', count(*) filter (where n.st not in ('at_sea', 'laid_up')),
                                        'laid_up', count(*) filter (where n.st = 'laid_up'),
                                        'why', (select jsonb_object_agg(z.st, z.k) from (select n2.st, count(*) as k from n n2 group by n2.st) z)) from n)),
  'beat', (select jsonb_build_object('beats', count(*), 'mean_ms', round(avg(a.ms)), 'p95_ms', round(percentile_cont(0.95) within group (order by a.ms)::numeric),
                                     'fleets_min', round(sum(a.fleets)::numeric / 30, 1), 'days_min', round(sum(a.days)::numeric / 30, 1))
             from public.arrivals_beats a where a.at > now() - interval '30 minutes')
) as r;
commit;
