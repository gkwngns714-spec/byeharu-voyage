-- 0512 PROD CHECK, before the deploy; read-only, ONE statement. Wanted: there 0, switch false, steps the placeholders of 0509 (5 rows). moves_home: companies whose home would
-- move if hq_cities_enabled were lit (0509's figure, by count alone): SHOW IT TO THE OWNER before any light.
select (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname, p.proname) in (('public', 'total_level'), ('public', 'hq_at'), ('public', 'hq_open_refusal'), ('world', 'hq_open'), ('cmd', 'open_hq'))) as there,
       (select value from public.world_config where key = 'hq_cities_enabled') as switch, (select count(*) from public.hq_steps) as steps,
       (select count(*) from public.company_hqs) as hq_rows, (select count(*) from public.company_hqs h where h.slot = 1 and h.port_id is distinct from public.home_port_of(h.player_id)) as moves_home;
