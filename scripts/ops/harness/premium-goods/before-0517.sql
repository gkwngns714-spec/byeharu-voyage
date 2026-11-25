-- 0517 PREMIUM GOODS, BEFORE. A PROD CHECK: read-only, ONE statement, the gate first (the lead runs it).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/premium-goods/before-0517.sql
-- Expect: head = the migration before 0517; knobs: the economy's two, true, and none of premium_; new_fns 0. A different body: 0517 refuses at the push (its hunk count).
-- Bodies: board_sell_memo d1365af1af4640fc6cc3f63f161df36f, do_sell 18fff22b5f80d5d649cad174c624a55f, good_mids e771e478c68d705091b1b6d6c981dadf,
--   goods_forge c73d7948aca0f01cc60590e32b08d878, market c855d403c735e297579032ba6bb81114, mid_terms 6ba0746ba6fc742584de419a895bab4c, quote_priced 0e837b48ff97d74c5392ce9633a1f91f.
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
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('world', 'cmd') and p.proname in ('quote_priced','do_sell','mid_terms','good_mids','market','goods_forge','board_sell_memo'))
);
rollback;
