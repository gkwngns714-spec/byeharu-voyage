-- 0503 A COMPANY TAKES A NEW NAME, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/company-name/before-0503.sql
-- Expect: head 20260818000502; new_fns 0; column false; index false; hunked 3 (the three bodies 0503 hunks are there).
--   `case_twins` is what decides the index: 0 and 0503 builds players_company_name_lower_key; above 0 it leaves the index out and
--   says so in its notice (the rule then stands in the function alone; nothing fails and no name is touched).
--   `companies` and `longest` are for the record. The digests are printed for the record: 0503 refuses at the push if a hunk does
--   not occur exactly once, and nothing changes.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, the catalog, and public.players (the companies of players only:
--   counts, no name is printed). No function that writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
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
  'hunked', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where (n.nspname, p.proname) in (('cmd', 'found_house'), ('world', 'player'), ('public', 'client_rpc_entry_points'))),
  'digests', (select json_object_agg(n.nspname || '.' || p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', ''))) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where (n.nspname, p.proname) in (('cmd', 'found_house'), ('world', 'player'), ('public', 'client_rpc_entry_points'))),
  'companies', (select count(*) from public.players p where not p.is_npc),
  'longest', (select max(char_length(p.company_name)) from public.players p where not p.is_npc),
  'case_twins', (select count(*) from (select 1 from public.players p where not p.is_npc group by lower(p.company_name) having count(*) > 1) t)
);
rollback;
