-- 0505 EACH CITY SETS ITS TAX, 0 TO 30 %, AND HOME PAYS HALF, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate's three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/tax-to-thirty/before-0505.sql
-- Expect: head = the migration before 0505; knobs {} (none of this file's exists); new_fns 0; the hunked bodies equal to the chain's
--   world before 0505 (so each hunk occurs there exactly once, as the self-assert proved on that world):
--   tax_rate 01bfcd04df2051c271599605e23169eb, set_tax e1d222859a6c98049c1502462bd1e8f0.
--   A different digest: 0505 refuses at the push (its hunk count), nothing changes.
--   knobs shows the owner's tax_rate_max and profit_tax_scale too (0505 changes neither). rates = every harbour's served rate (no company),
--   as an md5 and its spread: after-0505.sql must show the same md5, dark and lit. sea_places_free >= 1 (the self-assert's scene
--   stands on a SEA_PLACE that no country holds and no mayor has; 0 = it refuses, nothing changes). mayors = the dial's users.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, ports and port_mayor (one row a city), world.tax_rate (STABLE) once a harbour. No function that writes is
--   called. ROLLBACK: nothing (read only).
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
  'column_over_max', (select count(*) from public.ports h where h.kind = 'HARBOUR' and h.tax_rate * (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'profit_tax_scale') > (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'tax_rate_max')),
  'mayors', (select json_build_object('rows', count(*), 'with_rate', count(m.tax_rate), 'max_rate', max(m.tax_rate)) from public.port_mayor m),
  'sea_places_free', (select count(*) from public.ports q where q.kind = 'SEA_PLACE' and not exists (select 1 from public.port_allegiance a where a.port_id = q.id) and not exists (select 1 from public.port_mayor pm where pm.port_id = q.id))
);
rollback;
