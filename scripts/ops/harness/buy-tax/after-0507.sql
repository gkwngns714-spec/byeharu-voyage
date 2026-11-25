-- 0507 A TAX WHEN BUYING, 0 TO 3 %, AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/buy-tax/after-0507.sql
-- Expect, as deployed: head 0507; buy_tax_enabled false; new_fns 2; client_reach false; the bodies:
--   public.buy_tax_on 2ea7858f94bbcafaa66a82aa9a3e6c48, public.buy_tax_rate 02caa3bb1356e699df418cbfd8a206d8, world.quote_priced 0e837b48ff97d74c5392ce9633a1f91f.
-- ROLLBACK: buy_tax_enabled false (the owner's switch).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(json_object_agg(c.key, c.value), '{}'::json) from public.world_config c where c.key in ('buy_tax_enabled', 'buy_tax_share', 'buy_tax_max')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('buy_tax_on', 'buy_tax_rate')),
  'client_reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                           or has_function_privilege('service_role', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname in ('buy_tax_on', 'buy_tax_rate')),
  'bodies', (select json_object_agg(n.nspname || '.' || p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'world', 'cmd') and p.proname in ('quote_priced', 'buy_tax_on', 'buy_tax_rate')),
  'city_rates', (select json_build_object('min', min(world.tax_rate(h.id)), 'max', max(world.tax_rate(h.id)), 'mean', round(avg(world.tax_rate(h.id)), 4)) from public.ports h where h.kind = 'HARBOUR')
);
rollback;
