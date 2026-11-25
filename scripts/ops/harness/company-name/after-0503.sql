-- 0503 A COMPANY TAKES A NEW NAME, AFTER. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/company-name/after-0503.sql
-- Expect: head 20260818000503; new_fns 4; column true; index true where before-0503's case_twins was 0 (else false: the notice said so);
--   door true (cmd.rename_company for authenticated) and reach false (no other new function callable by anon, authenticated or
--   service_role; the door not by anon or service_role); renamed 0 at first, then the companies that used their free rename;
--   over_free 0 ALWAYS (no company has renamed more than once: a later rename is refused until payment is decided);
--   companies the same as before (no row is added or removed).
--   `old_names_the_rule_refuses`: the companies of players whose name stood before the rule and would be refused today. THEY KEEP
--   THEIR NAMES; the figure is for the owner (it can only fall, as they rename).
-- ROLLBACK (forward, owner only): a migration reversing the three hunks, dropping the four functions and the index.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, the catalog, public.players (the companies of players: counts; no
--   name is printed), public.events of the last hour by kind. public.company_name_refusal is STABLE and writes nothing; it is asked
--   once a company of a player (static tables and public.players, all small). ROLLBACK: nothing to roll back (read only).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname, p.proname) in (('public', 'company_name_refusal'), ('public', 'company_rename_free'), ('public', 'rename_company'), ('cmd', 'rename_company'))),
  'column', exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'players' and c.column_name = 'renames'),
  'index', to_regclass('public.players_company_name_lower_key') is not null,
  'door', has_function_privilege('authenticated', 'cmd.rename_company(text)', 'execute'),
  'reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')
                                    or (n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute'))), false)
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname, p.proname) in (('public', 'company_name_refusal'), ('public', 'company_rename_free'), ('public', 'rename_company'), ('cmd', 'rename_company'))),
  'companies', (select count(*) from public.players p where not p.is_npc),
  'renamed', (select count(*) from public.players p where p.renames > 0),
  'over_free', (select count(*) from public.players p where p.renames > 1),
  'renames_last_hour', (select count(*) from public.events e where e.kind = 'COMPANY_RENAMED' and e.created_at > now() - interval '1 hour'),
  'old_names_the_rule_refuses', (select count(*) from public.players p where not p.is_npc and public.company_name_refusal(p.company_name, p.id) is not null)
);
rollback;
