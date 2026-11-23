-- CHOICES AT SEA (0486), BEFORE. A PROD CHECK: read-only, ONE statement. It carries the gate's own three figures (the arrivals beat's mean
-- over 5 minutes, the database by the catalog, the sessions waiting on the disk), so it is the builder's one prod read.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/sea-choices/before-0486.sql
-- Expect: head 20260818000485; `knobs` {} (no sea_choices_*); `absent` true (no public.sea_choices, no public.sea_choice* function, no
-- world.sea_choices, no cmd.sea_choose, no SEA_FIND / SEA_LOSS money word); `anchors` 1 for each of the three hunked bodies and `new_absent`
-- true (each hunk's anchor once in prod's live body, its new text nowhere); `bodies` the md5 of the three hunked bodies (the chain's at
-- 0485 are in the dev-log).
-- THE LOAD IT WOULD ADD, from the companies' own voyages of the last 24 hours (by the fleet's voyage indexes, a company fleet at a time):
-- `trips_24h` their voyages that ended in 24 hours or sail now, `harbour_to_harbour`, `long` those of sea_choices_trip_min_s (600 real
-- seconds) or more, and the median and p90 trip. Lit, about 0.35 x `long` events a day, each one insert at departure and one settle (an
-- event, a ledger row, a treasury row) at its arrival. `companies` the companies; `switches` the purses and the closed economy.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog (pg_proc), stats_flow_words, players
-- (the companies), fleets (theirs), voyages by (fleet_id) and (fleet_id, eta), ports by id. No function that writes is called.
-- ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
with bodies as materialized (
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as d, f.anchor, f.added
    from (values
      ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)',
       '    perform public.early_sighting_plan(v_voyage, p_at);   -- 0477: is this the trip a weak pirate sights? (dark: one knob read; never raises)' || E'\n',
       'sea_choice_plan'),
      ('voyage.settle(uuid,timestamp with time zone)', '      perform public.level_arrival(f.player_id, v.id);' || E'\n', 'sea_choice_settle'),
      ('public.client_rpc_entry_points()', '      (''world'',       ''ship_roles'',            ''''),', 'sea_choose')) f(fn, anchor, added)
), trips as materialized (
  select v.id, extract(epoch from v.eta - v.departed_at) as secs,
         v.origin_port_id is not null and v.dest_port_id is not null and v.origin_port_id <> v.dest_port_id
           and (select count(*) from public.ports p where p.id in (v.origin_port_id, v.dest_port_id) and p.kind = 'HARBOUR') = 2 as h2h
    from public.players pl
    join public.fleets f on f.player_id = pl.id
   cross join lateral (select x.id, x.eta, x.departed_at, x.origin_port_id, x.dest_port_id from public.voyages x
                        where x.fleet_id = f.id and x.status <> 'SAILING' and x.eta > now() - interval '24 hours'
                       union all
                       select x.id, x.eta, x.departed_at, x.origin_port_id, x.dest_port_id from public.voyages x
                        where x.fleet_id = f.id and x.status = 'SAILING') v
   where not pl.is_npc
)
select jsonb_build_object(
  'at', now(),
  'gate', jsonb_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'beats', (select count(*) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'sea\_choices\_%'),
  'absent', to_regclass('public.sea_choices') is null and to_regprocedure('world.sea_choices()') is null
            and to_regprocedure('cmd.sea_choose(uuid,text)') is null
            and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'sea\_choice%')
            and not exists (select 1 from public.stats_flow_words w where w.kind in ('SEA_FIND', 'SEA_LOSS')),
  'anchors', (select jsonb_object_agg(b.fn, (length(b.d) - length(replace(b.d, b.anchor, ''))) / length(b.anchor)) from bodies b),
  'new_absent', not exists (select 1 from bodies b where strpos(b.d, b.added) > 0),
  'bodies', (select jsonb_object_agg(b.fn, md5(b.d)) from bodies b),
  'companies', (select count(*) from public.players pl where not pl.is_npc),
  'trips_24h', (select count(*) from trips),
  'harbour_to_harbour', (select count(*) from trips where h2h),
  'long', (select count(*) from trips where h2h and secs >= 600),
  'median_trip_s', (select round((percentile_cont(0.5) within group (order by secs))::numeric) from trips where h2h),
  'p90_trip_s', (select round((percentile_cont(0.9) within group (order by secs))::numeric) from trips where h2h),
  'switches', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key in ('economy_closed', 'city_treasury_enabled'))
);
rollback;
