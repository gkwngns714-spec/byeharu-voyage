-- 0510 PROD CHECK, after the deploy; read-only, ONE statement. Wanted: lit as before (false); rungs {15,7,6,2,8,18,2,6}; raised ['ARC']; pairs_off 0.
begin transaction read only;
select (select value from public.world_config where key = 'sea_conditions_bite') as lit,
       (select array_agg(q.n order by q.t) from (select title_min as t, count(*) as n from public.sea_zones group by 1) q) as rungs,
       (select array_agg(code) from public.sea_zones where title_min > title_was) as raised,
       (select count(*) from public.sea_leg_asks s join public.sea_leg_asks own on own.from_port = s.to_port and own.to_port = s.to_port
         where s.title_min <> (select max(z.title_min) from public.sea_zones z where z.code = any (s.zones || own.zones))) as pairs_off,
       (select n_dead_tup from pg_stat_user_tables where relname = 'sea_leg_asks') as dead_pair_rows;
rollback;
