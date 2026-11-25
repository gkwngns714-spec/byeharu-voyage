-- 0505 EACH CITY SETS ITS TAX, 0 TO 30 %, AND HOME PAYS HALF, AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/tax-to-thirty/after-0505.sql
-- Expect, AS DEPLOYED (dark): head 0505; knobs as the file seeds them (the switch false); new_fns 3; client_reach false;
--   bodies = the chain's world at 0505:
--   tax_rate 9a9da687b6ad125df2f1bc9715d9382e, set_tax 2b4dbc2e2ed1f66881dad48292d30a32, tax_thirty_on e64bbc3a353bcf48887a46564e5e5a66, tax_cap b1429b243eeab521a0816e0cf083c976, tax_home_half e4f27883a61ed55603b8df7d910207e1.
--   rates.md5 = before-0505.sql's (no rate moved at deploy); mayors.over_max 0.
-- LIT (read 30 minutes after the owner lights the switch): rates.md5 STILL before-0505.sql's until a mayor presses (the light
--   moves no rate); mayors.over_max = the cities a mayor has taken above tax_rate_max (each by her own press), max_rate <= 0.30.
-- ROLLBACK: tax_thirty_enabled false (owner): the dial stops at tax_rate_max again and home gives
--   nothing. A mayor's rate already above tax_rate_max stays in her row and is served (world.tax_rate never capped a mayor's rate): read
--   mayors.over_max first; the owner decides whether those rows are lowered by a forward migration.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, ports and port_mayor (one row a city), world.tax_rate (STABLE) once a harbour. No function that writes is
--   called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(json_object_agg(c.key, c.value), '{}'::json) from public.world_config c where c.key in ('tax_thirty_enabled', 'tax_rate_cap', 'home_tax_cut', 'tax_rate_max', 'profit_tax_scale')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname in ('public', 'world', 'cmd') and p.proname in ('tax_thirty_on', 'tax_cap', 'tax_home_half')),
  'client_reach', (select coalesce(bool_or(has_function_privilege('public', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                                           or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname in ('public', 'world', 'cmd') and p.proname in ('tax_thirty_on', 'tax_cap', 'tax_home_half')),
  'bodies', (select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'world', 'cmd') and p.proname in ('tax_rate', 'set_tax', 'tax_thirty_on', 'tax_cap', 'tax_home_half')),
  'rates', (select json_build_object('md5', md5(string_agg(h.code || ':' || world.tax_rate(h.id)::text, ',' order by h.code)), 'min', min(world.tax_rate(h.id)), 'max', max(world.tax_rate(h.id)), 'harbours', count(*)) from public.ports h where h.kind = 'HARBOUR'),
  'mayors', (select json_build_object('rows', count(*), 'with_rate', count(m.tax_rate), 'max_rate', max(m.tax_rate), 'over_max', count(*) filter (where m.tax_rate > (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'tax_rate_max'))) from public.port_mayor m)
);
rollback;
