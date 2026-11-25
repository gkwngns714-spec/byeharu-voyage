-- 0512 PROD CHECK, after the deploy; read-only, ONE statement. Wanted: switch false, set_steps 0, perks 0, opened 0, hq_rows as before.
select (select value from public.world_config where key = 'hq_cities_enabled') as switch, (select count(*) from public.hq_steps where slot > 1 and coalesce(total_level, ducats, reputation) is not null) as set_steps,
       (select count(*) from public.hq_perks) as perks, (select count(*) from public.company_hqs where slot > 1) as opened, (select count(*) from public.company_hqs) as hq_rows;
