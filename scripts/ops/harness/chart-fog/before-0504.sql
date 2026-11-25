-- 0504 THE CHART IS BLACK UNTIL SHE SAILS, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/chart-fog/before-0504.sql
-- Expect: head 20260818000503; knobs 0 and table null (not applied); settle_anchor 1 and registry_anchor 1 (each hunk's OLD text is in
--   the live body once: 0499-0503 did not move them); needs 5 (the logbook's arrival, the skill level, the two sea functions, the home
--   port). (The probe founds its own company with the economy
--   open, rolled back: no purse of prod's is read or can refuse it.)
--   `companies`: how many charts the backfill will write (one row each). `voyages`: WHAT PROD REALLY KEEPS of the companies' ended
--   voyages (the chain never deletes a company's): how many, the oldest, and the most any one fleet holds, which is what
--   public.chart_backfill's second argument (500 a fleet) is weighed against. `logbook_harbours`: her cities, each backfilled a circle.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, players (not merchants), their fleets,
--   the ended voyages of those fleets by the (fleet_id, eta) index (counted, no path read), logbook by key. No function that writes.
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select count(*) from public.world_config c where c.key in ('chart_fog_enabled', 'chart_sight_nm')),
  'table', to_regclass('public.company_chart'),
  'settle_anchor', (select (length(z.d) - length(replace(z.d, z.a, ''))) / length(z.a)
                      from (select replace(pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure), E'\r', '') as d,
                                   '      || public.logbook_arrival(f.player_id, v.origin_port_id, v.dest_port_id, v.eta));' as a) z),
  'registry_anchor', (select (length(z.d) - length(replace(z.d, z.a, ''))) / length(z.a)
                        from (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as d,
                                     '      (''world'',       ''logbook'',               ''''),' as a) z),
  'needs', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where (n.nspname, p.proname) in (('public', 'logbook_arrival'), ('public', 'skill_level'), ('voyage', 'gc_distance_nm'), ('voyage', 'lon_lerp'), ('public', 'home_port_of'))),
  'companies', (select count(*) from public.players pl where not pl.is_npc),
  'voyages', (select json_build_object('ended', coalesce(sum(x.n), 0), 'oldest', min(x.oldest), 'most_a_fleet', max(x.n), 'fleets', count(*))
                from public.players pl join public.fleets f on f.player_id = pl.id
                cross join lateral (select count(*) as n, min(v.eta) as oldest from public.voyages v
                                     where v.fleet_id = f.id and v.status <> 'SAILING') x
               where not pl.is_npc),
  'logbook_harbours', (select count(*) from public.logbook l where l.kind = 'harbour'),
  'logbook_enabled', (select c.value from public.world_config c where c.key = 'logbook_enabled'));
rollback;
