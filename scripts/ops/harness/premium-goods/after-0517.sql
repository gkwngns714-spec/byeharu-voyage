-- 0517 PREMIUM GOODS, AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, the gate first (the lead runs it).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/premium-goods/after-0517.sql
-- Expect, as deployed: head 0517; premium_goods_enabled false; new_fns 9; client_reach false; cities 100; offered_where_wanted 0; taken_today 0.
-- Lit: `most` at most 30; purses_under_0 0. ROLLBACK: premium_goods_enabled false.
-- Bodies: board_sell_memo a0e37e672f7c0ec7649961ff5d6b64b2, do_sell 79fb9368812037129d2f409a0941781a, good_mids 0ad985218d7d8433ab9cf52f1973caee,
--   goods_forge 65eb608342f9e8bfb9706eb7e0c11e7e, market fb2acd089346ad56b2a2d67a12b50d62, mid_terms fcf53336d03bcc4944f7c1ac4df14cdf, quote_priced 4550b703b3f65f00e810a1e571761ee1.
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(json_object_agg(c.key, c.value), '{}'::json) from public.world_config c where c.key like 'premium\_%' or c.key in ('economy_closed', 'city_treasury_enabled')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('premium_on','premium_lift','premium_mult','premium_units','premium_left','premium_hold','premium_spend','premium_port','premium_face')),
  'client_reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('premium_on','premium_lift','premium_mult','premium_units','premium_left','premium_hold','premium_spend','premium_port','premium_face')),
  'bodies', (select json_object_agg(n.nspname || '.' || p.proname, md5(replace(pg_get_functiondef(p.oid), E'
', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('world', 'cmd') and p.proname in ('quote_priced','do_sell','mid_terms','good_mids','market','goods_forge','board_sell_memo')),
  'cities', (select count(*) from public.goods where premium_port_id is not null),
  'offered_where_wanted', (select count(*) from public.goods g where g.premium_port_id is not null and public.port_offers(g.premium_port_id, g.id)),
  'taken_today', (select json_build_object('cities', count(*), 'units', sum(pg.premium_units), 'most', max(pg.premium_units)) from public.port_goods pg where pg.premium_day = public.real_day(now())),
  'purses_under_0', (select count(*) from public.port_treasury t where t.ducats < 0)
);
rollback;
