begin transaction read only;
select json_build_object(
 'kinds', (select json_agg(x) from (select (payload ? 'rounds') lit, count(*) n, min(resolved_at) mn, max(resolved_at) mx from public.voyage_events where kind='PIRATES' group by 1) x),
 'dark', (select payload from public.voyage_events where kind='PIRATES' and not payload ? 'rounds' order by resolved_at desc limit 1),
 'lit', (select payload from public.voyage_events where kind='PIRATES' and payload ? 'rounds' order by resolved_at desc limit 1),
 'ships', (select json_agg(column_name||':'||data_type order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='ships'));
rollback;
