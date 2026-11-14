-- 0425 PROD CHECK, BEFORE and AFTER the deploy (+30 min and +3 h), read-only, ONE statement, stable functions only:
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/at-sea-2/after.sql
-- One row, one jsonb column `r`. Run scripts/ops/harness/db-health/gate.sql first (gate_ok true).
-- Reads navy_ships (~45) and cargo_ships (~370) with their fleets by key, each cargo ship's newest LOADED row through convoy_cargo's
-- (fleet_id, id) index, and the beat's ring. No big table is scanned.
-- BEFORE, wanted: head 20260818000424; applied false; old_hunk 1, new_hunk 0; knobs convoy_load_max 1000000, convoy_loads_per_run 10,
--   navy_hunt_hours 0.0625, navy_own_sea_patrol true. Write `ships` down: it is the "before" of the after-check.
-- AFTER, wanted: head 20260818000425; applied true; old_hunk 0, new_hunk 1; knobs 250000 and 20 (an owner's own value is left by 0425 and
--   named in its receipt); the gate green.
-- READING after the deploy: navy.lying_stale 0 within 2 minutes (every lie longer than navy_hunt_hours is cut at the ship's next step);
--   navy.lying falls from ~30 to the few at another sea's harbour (225 s each); navy.at_sea from ~10 toward ~35-40 within 15 minutes (those
--   away sail home first, then patrol or hunt again). cargo.loads_largest_1h at most 250000 after the next :37 city run; cargo.at_sea rises
--   over the hours as the loaded ships come home and their realms' need is loaded again in quarters. beat.mean_ms under 1,000.
begin transaction read only;
with body as (
  select replace(pg_get_functiondef('public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)'::regprocedure), E'\r', '') as def
), n as (
  select x.mission, x.hunt_until, x.hunt_port, x.station_port, f.status, f.port_id, f.ready_at
    from public.navy_ships x join public.fleets f on f.id = x.fleet_id
), c as (
  select x.laid_up_at, f.status, f.port_id, x.home_port_id,
         (select a.aboard from public.cargo_ship_aboard(x.fleet_id) a) as aboard,
         l.created_at as last_at, l.ducats as last_d
    from public.cargo_ships x join public.fleets f on f.id = x.fleet_id
    left join lateral (select b.created_at, b.ducats from public.convoy_cargo b where b.fleet_id = x.fleet_id and b.stage = 'LOADED' order by b.id desc limit 1) l on true
), c2 as (
  select * from c
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', (select position('-- 0425:' in b.def) > 0 from body b),
  'old_hunk', (select (length(b.def) - length(replace(b.def, E'  if n.mission = ''HUNT'' and n.hunt_port = p_port then\n    if n.hunt_until is not null and n.hunt_until > p_now then\n      return ''HUNTING'';\n', '')))
                      / length(E'  if n.mission = ''HUNT'' and n.hunt_port = p_port then\n    if n.hunt_until is not null and n.hunt_until > p_now then\n      return ''HUNTING'';\n') from body b),
  'new_hunk', (select (length(b.def) - length(replace(b.def, E'    -- 0425: A LIE IS NEVER LONGER THAN THE KNOB SAYS NOW.', ''))) / length(E'    -- 0425: A LIE IS NEVER LONGER THAN THE KNOB SAYS NOW.') from body b),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('convoy_load_max', 'convoy_loads_per_run', 'navy_hunt_hours', 'navy_own_sea_patrol', 'navy_hunt_per_day', 'navy_steps_per_run')),
  'navy', (select jsonb_build_object('n', count(*), 'at_sea', count(*) filter (where n.status = 'SAILING'),
                                     'lying', count(*) filter (where n.status <> 'SAILING' and n.mission = 'HUNT' and n.hunt_until > now()),
                                     'lying_stale', count(*) filter (where n.status <> 'SAILING' and n.mission = 'HUNT'
                                                                      and n.hunt_until > now() + make_interval(secs => (public.wc_num('navy_hunt_hours') * 3600)::double precision) + interval '1 minute'),
                                     'lying_at_station', count(*) filter (where n.status <> 'SAILING' and n.mission = 'HUNT' and n.hunt_until > now() and n.port_id = n.station_port),
                                     'port_time', count(*) filter (where n.status <> 'SAILING' and n.ready_at > now()),
                                     'mission', (select jsonb_object_agg(coalesce(z.m, 'none'), z.k) from (select n2.mission as m, count(*) as k from n n2 group by 1) z))
             from n),
  'cargo', (select jsonb_build_object('n', count(*), 'at_sea', count(*) filter (where c2.status = 'SAILING'),
                                      'at_sea_funds', count(*) filter (where c2.status = 'SAILING' and c2.aboard > 0),
                                      'aboard', coalesce(sum(c2.aboard), 0),
                                      'home_idle', count(*) filter (where c2.laid_up_at is null and c2.status = 'DOCKED' and c2.port_id = c2.home_port_id and c2.aboard is null),
                                      'laid_up', count(*) filter (where c2.laid_up_at is not null),
                                      'loads_1h', count(*) filter (where c2.last_at > now() - interval '1 hour'),
                                      'loads_largest_1h', max(c2.last_d) filter (where c2.last_at > now() - interval '1 hour'))
              from c2),
  'beat', (select jsonb_build_object('beats', count(*), 'mean_ms', round(avg(a.ms)), 'p95_ms', round(percentile_cont(0.95) within group (order by a.ms)::numeric))
             from public.arrivals_beats a where a.at > now() - interval '30 minutes')
) as r;
commit;
