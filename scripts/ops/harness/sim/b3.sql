begin transaction read only;
select json_build_object(
 'made_only_in', (select replace(pg_get_functiondef('public.made_only_in(text,uuid)'::regprocedure), E'\r', '')),
 'kind_readers', (select json_agg(n.nspname||'.'||p.proname order by 1) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','cmd','voyage','world') and p.prosrc ~ '\.kind\s*(=|<>|in)\s*\(?''(fitting|promotion)'),
 'kinds', (select json_object_agg(kind, c) from (select kind, count(*) c from public.item_kinds group by 1) z),
 'kind_check', (select json_agg(pg_get_constraintdef(c.oid)) from pg_constraint c where c.conrelid='public.item_kinds'::regclass),
 'made_in_readers', (select json_agg(n.nspname||'.'||p.proname order by 1) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','cmd','voyage','world') and p.prosrc ~ 'made_only_in')
) j;
rollback;
