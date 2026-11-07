-- 0337 PROD CHECK AFTER DEPLOY, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/captain-sheet/after.sql
-- Every function called here is STABLE or a catalog read; every type is cast. It runs clean BEFORE the deploy too (fn null, registered false): that is how it was run on prod before the PR. The one call of the new function is
-- after-call.sql, which cannot be parsed until the function exists.
-- Wanted: head 20260818000337; fn.present true, fn.vol 's', fn.secdef true, fn.cfg {"search_path=public, pg_temp"}; acl_as_sibling true (== world.levels()); anon_can_execute false; authenticated_can_execute true;
--         registered true; levels_bite true (read, never set); one_registry_row true.
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'fn', (select jsonb_build_object('present', true, 'vol', p.provolatile::text, 'secdef', p.prosecdef, 'cfg', coalesce(p.proconfig::text, ''), 'acl', coalesce(p.proacl::text, ''))
           from pg_proc p where p.oid = to_regprocedure('world.captain_stats(text)')),
  'acl_as_sibling', (select coalesce(a.proacl::text, '') = coalesce(b.proacl::text, '')
                       from pg_proc a cross join pg_proc b where a.oid = to_regprocedure('world.captain_stats(text)') and b.oid = 'world.levels()'::regprocedure),
  'anon_can_execute', has_function_privilege('anon', to_regprocedure('world.captain_stats(text)'), 'execute'),
  'authenticated_can_execute', has_function_privilege('authenticated', to_regprocedure('world.captain_stats(text)'), 'execute'),
  'registered', exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'captain_stats' and e.arg_types = 'text' and e.fn is not null),
  'one_registry_row', (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'captain_stats') = 1,
  'levels_bite', (select c.value::text from public.world_config c where c.key = 'levels_bite'),
  'siblings_stable', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile::text) from pg_proc p
                       where p.oid in ('public.crew_terms(uuid,timestamp with time zone)'::regprocedure, 'public.crew_pct(uuid,uuid,text,uuid,timestamp with time zone)'::regprocedure, 'world.levels()'::regprocedure))
) as checks;
