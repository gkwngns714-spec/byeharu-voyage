-- 0336 PROD CHECK AFTER DEPLOY, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/origins-fence/after.sql
-- Every function read here is STABLE (pg_get_functiondef, md5, replace, position, public.rich_cities_on, public.cargo_origins in its off arm, public.realm_capital). No game function is called and no row is written.
-- Wanted: head 20260818000336; body_is_new true (body_md5 81997c67fc00c74f748aeab9c0bf2695: the live body of before.sql with the one hunk of 0336 in it, nothing else); hunk_old_times 0; fence_in_body true; volatility s; definer true;
-- acl {postgres=X/postgres,service_role=X/postgres}; config {"search_path=public, pg_temp"}; overloads 1 (all as before.sql read them); switch false; rich_on false;
-- off_capital 0 (with the switch off, every great power's origins are its capital, and not one is read from the cities); probe_codes 0.
with h(old) as (values ($h$                                       from public.ports h
                                      cross join lateral (select public.crown_call_room(h.id) as room) x
                                      where h.kind = 'HARBOUR' and public.port_nation(h.id) = p_nation and x.room > 0
                                        and exists (select 1 from public.npc_courses c where c.from_port = h.id or c.to_port = h.id)
$h$))
select jsonb_build_object(
  'head', (select max(s.version) from supabase_migrations.schema_migrations s),
  'body_md5', md5(d.def),
  'body_is_new', md5(d.def) = '81997c67fc00c74f748aeab9c0bf2695',
  'hunk_old_times', (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old),
  'fence_in_body', position('offset 0) h' in d.def) > 0,
  'volatility', f.provolatile::text,
  'definer', f.prosecdef,
  'acl', coalesce(f.proacl::text, ''),
  'config', coalesce(f.proconfig::text, ''),
  'overloads', (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'cargo_origins'),
  'switch', (select c.value from public.world_config c where c.key = 'convoy_rich_enabled'),
  'rich_on', public.rich_cities_on(),
  'off_capital', (select count(*) from public.great_powers g where public.cargo_origins(g.nation_id) is distinct from array[public.realm_capital(g.nation_id)]),
  'probe_codes', (select count(*) from public.ports p where p.code like 'QY_') + (select count(*) from public.nations n where n.code in ('QX6', 'QX7'))
) as checks
  from (select replace(pg_get_functiondef('public.cargo_origins(uuid)'::regprocedure), E'\r', '') as def) d
 cross join h
 cross join (select p.provolatile, p.prosecdef, p.proacl, p.proconfig from pg_proc p where p.oid = 'public.cargo_origins(uuid)'::regprocedure) f;
