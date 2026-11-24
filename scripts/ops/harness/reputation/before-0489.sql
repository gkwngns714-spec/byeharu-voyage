-- REPUTATION'S DEFERRED CHECK RUNS AS ITS OWNER (0489), BEFORE. A PROD CHECK: read-only, ONE statement, the catalog alone.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/reputation/before-0489.sql
-- Expect (before 0489): head 20260818000488; `server` 17.x; `fn_definer` false, `fn_config` null, `fn_owner` postgres,
--   `fn_md5` printed (0489's guard holds the body to the md5 of 0352's body, and after-0489.sql expects the same md5);
--   `triggers` 2 (reputation_book and reputation_balance, both deferrable, initially deferred, on public.reputation_reconciles());
--   `invoker_deferred` the one function public.reputation_reconciles() (every deferrable trigger in public, world, cmd and voyage
--   whose function is not SECURITY DEFINER); `auth_reads_balance` false (role authenticated may not SELECT public.reputation_balance).
-- Reads: the catalog only (pg_proc, pg_trigger, pg_class, pg_namespace, supabase_migrations.schema_migrations). Nothing is written.
-- ROLLBACK: nothing (ends with rollback).
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       current_setting('server_version') as server,
       p.prosecdef as fn_definer,
       p.proconfig as fn_config,
       pg_get_userbyid(p.proowner) as fn_owner,
       p.proacl::text as fn_acl,
       md5(replace(p.prosrc, E'\r', '')) as fn_md5,
       (select string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgdeferrable || ':' || t.tginitdeferred || ':' || t.tgfoid::regprocedure::text,
                          ', ' order by t.tgrelid::regclass::text)
          from pg_trigger t where t.tgfoid = p.oid and not t.tgisinternal) as triggers,
       (select string_agg(distinct t.tgfoid::regprocedure::text, ', ')
          from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace join pg_proc f on f.oid = t.tgfoid
         where not t.tgisinternal and t.tgdeferrable and not f.prosecdef and n.nspname in ('public', 'world', 'cmd', 'voyage')) as invoker_deferred,
       has_table_privilege('authenticated', 'public.reputation_balance', 'select') as auth_reads_balance
  from pg_proc p
 where p.oid = 'public.reputation_reconciles()'::regprocedure;
rollback;
