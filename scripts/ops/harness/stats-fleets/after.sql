-- after.sql: READ ONLY on prod, one statement, AFTER 0419 (and again after the next Stats count, at minute 6 or 36). The table, the read in the
-- registry and granted, the rows kept (one a count, at most ~52), the newest count's receipt with its `fleets` phase in ms beside the whole count,
-- and the face's read itself (world.stats_fleets: STABLE, three index probes, ~52 rows).
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'table', to_regclass('public.stats_fleets') is not null,
  'registry', exists (select 1 from public.client_rpc_entry_points() e where e.schema_name = 'world' and e.function_name = 'stats_fleets' and e.fn is not null),
  'granted', has_function_privilege('authenticated', 'world.stats_fleets()', 'execute') and not has_function_privilege('anon', 'world.stats_fleets()', 'execute'),
  'rows', (select count(*) from public.stats_fleets),
  'runs', (select jsonb_agg(jsonb_build_object('at', x.at, 'ms', x.ms, 'fleets_ms', x.receipt -> 'phases' -> 'fleets', 'merchants_ms', x.receipt -> 'phases' -> 'merchants') order by x.at desc)
             from (select r.at, r.ms, r.receipt from public.stats_runs r order by r.at desc limit 4) x),
  'read', world.stats_fleets()
) as after_0419;
commit;
