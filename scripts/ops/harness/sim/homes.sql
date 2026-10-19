begin transaction read only;
select json_build_object(
 'per_port', (select json_object_agg(n, c) from (select n, count(*) c from (select s.port_id, count(*) n from public.standing_route_stops s join public.npc_fleets nf on nf.route_id=s.route_id where s.ord=0 group by 1) a group by 1 order by 1) b),
 'offered_per_port', (select json_object_agg(n, c) from (select n, count(*) c from (select p.id, (select count(*) from public.port_offered_goods(p.id)) n from public.ports p where p.kind='HARBOUR') a group by 1 order by 1) b),
 'laid_up_now', (select count(*) from public.standing_routes sr join public.npc_fleets nf on nf.route_id=sr.id where sr.paused_reason='laid_up')
) j;
rollback;
