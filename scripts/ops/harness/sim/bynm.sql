begin transaction read only;
with rl as (select sr.id, (select sum(s.course_nm) from public.standing_route_stops s where s.route_id=sr.id) nm, (select count(*) from public.standing_route_stops s where s.route_id=sr.id) n,
   (select coalesce(sum(c.hold),0) from public.ships sh join public.ship_classes c on c.id=sh.class_id where sh.fleet_id=nf.fleet_id) hold
   from public.standing_routes sr join public.npc_fleets nf on nf.route_id=sr.id),
 l as (select lp.route_id, lp.net, lp.bought, lp.sold from public.standing_route_laps lp where lp.closed_at > now()-interval '3 hours'),
 per as (select rl.id, rl.nm, rl.hold, count(l.*) laps, coalesce(sum(l.net),0) s, count(*) filter (where l.net<=0) le0 from rl left join l on l.route_id=rl.id group by 1,2,3)
select json_agg(json_build_object('b', b, 'routes', n, 'laps', laps, 'lap_le0_pct', round(100.0*le0/nullif(laps,0)), 'routes_sum_le0', rle0, 'mean_route_3h', mr, 'hold_med', hm) order by b) j from (
 select case when nm is null then -1 when nm < 1000 then 0 when nm < 2000 then 1000 when nm < 4000 then 2000 when nm < 8000 then 4000 when nm < 16000 then 8000 else 16000 end b,
   count(*) n, sum(laps) laps, sum(le0) le0, count(*) filter (where s <= 0) rle0, round(avg(s)) mr, percentile_cont(0.5) within group (order by hold) hm
 from per group by 1) z;
rollback;
