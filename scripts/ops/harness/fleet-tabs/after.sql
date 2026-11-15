-- after.sql: READ ONLY on prod, one statement, AFTER 0431 (again after the next Stats count, and once more after an hour). The tables, the battle
-- trigger, the two reads in the registry and granted; what the book has written (rows and lines, by the last three hours: the rows a minute the PR
-- body promised, +3 to +8), its size; the newest count's receipt (its `fleets` phase now builds the three lists) beside the whole count; the three
-- lists' heads; and one navy ship's page. Reads only the three new small tables, the catalog, stats_runs and the two STABLE reads.
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'tables', to_regclass('public.fleet_book') is not null and to_regclass('public.fleet_lines') is not null and to_regclass('public.stats_fleet_list') is not null,
  'trigger', exists (select 1 from pg_trigger t where t.tgrelid = 'public.battles'::regclass and t.tgname = 'fleet_book_battle' and t.tgenabled = 'O'),
  'registry', (select count(*) from public.client_rpc_entry_points() e where e.schema_name = 'world' and e.function_name in ('stats_fleet_list', 'stats_fleet') and e.fn is not null),
  'granted', has_function_privilege('authenticated', 'world.stats_fleet(uuid)', 'execute') and not has_function_privilege('anon', 'world.stats_fleet(uuid)', 'execute')
             and has_function_privilege('authenticated', 'world.stats_fleet_list(text)', 'execute') and not has_function_privilege('anon', 'world.stats_fleet_list(text)', 'execute'),
  'book', jsonb_build_object('rows', (select count(*) from public.fleet_book), 'fleets', (select count(distinct b.fleet_id) from public.fleet_book b),
                             'by_hour', (select jsonb_object_agg(to_char(b.hour, 'HH24:MI'), b.n) from (select x.hour, count(*) as n from public.fleet_book x where x.hour >= now() - interval '3 hours' group by x.hour) b),
                             'lines', (select count(*) from public.fleet_lines), 'lines_3h', (select count(*) from public.fleet_lines l where l.at >= now() - interval '3 hours'),
                             'lines_by_kind', (select jsonb_object_agg(k.kind, k.n) from (select l.kind, count(*) as n from public.fleet_lines l group by l.kind) k),
                             'kb', (select (pg_total_relation_size('public.fleet_book') + pg_total_relation_size('public.fleet_lines') + pg_total_relation_size('public.stats_fleet_list')) / 1024)),
  'runs', (select jsonb_agg(jsonb_build_object('at', x.at, 'ms', x.ms, 'fleets_ms', x.receipt -> 'phases' -> 'fleets') order by x.at desc)
             from (select r.at, r.ms, r.receipt from public.stats_runs r order by r.at desc limit 4) x),
  'lists', (select jsonb_object_agg(k.kind, world.stats_fleet_list(k.kind) - 'list') from (values ('NAVY'), ('PIRATE'), ('CARGO')) k(kind)),
  'page', (select world.stats_fleet(n.fleet_id) - 'ships' from public.navy_ships n order by n.fleet_id limit 1)
) as after_0431;
commit;
