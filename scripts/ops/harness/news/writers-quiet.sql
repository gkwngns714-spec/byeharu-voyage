-- 0347 PROD CHECK (the writers never fire in live play), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/news/writers-quiet.sql
-- Wanted: fns_writing_ports 0, fns_writing_relations 0, triggers_on_them 0. 0347 hangs its two news writers on public.ports (insert) and public.power_relations;
-- if no function body writes either table and neither carries a trigger, only a migration ever fires them, so no tick, trade or voyage does: no live play and no tick cost moves.
begin transaction read only;
select (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~* 'insert\s+into\s+(public\.)?ports\b') as fns_writing_ports,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage')
           and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?power_relations\b') as fns_writing_relations,
       (select count(*) from pg_trigger t where not t.tgisinternal and t.tgrelid in ('public.ports'::regclass, 'public.power_relations'::regclass)) as triggers_on_them,
       (select count(*) from public.power_relations) as relations,
       (select count(*) from public.ports where kind = 'HARBOUR') as harbours;
commit;
