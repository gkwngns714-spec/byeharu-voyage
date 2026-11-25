-- 0525 PROD CHECK, after the deploy; read-only, ONE statement. Wanted: asks 0; off 0; classes = figures; lit as before.
begin transaction read only;
select (select sum(z.ice_min + z.current_min + z.light_min) from public.sea_zones z) as asks,
       (select count(*) from public.sea_stats_derive() d left join public.sea_stats_class c on d.kind = 'class' and c.class_code = d.code left join public.sea_stats_item t on d.kind = 'item' and t.item_code = d.code and t.stat = d.stat
         where d.val is distinct from case when d.kind = 'item' then t.delta else case d.stat when 'ice' then c.ice when 'current' then c.current else c.light end end) as off,
       (select count(*) from public.ship_classes) as classes, (select count(*) from public.sea_stats_class) as figures,
       (select value from public.world_config where key = 'sea_conditions_bite') as lit;
rollback;
