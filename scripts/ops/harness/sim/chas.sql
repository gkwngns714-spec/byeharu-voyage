begin transaction read only;
with h as (select pl.id pid from public.players pl where pl.company_name ilike 'Comptoir Chastellain%'),
 r as (select sr.* from public.standing_routes sr join h on h.pid = sr.player_id)
select json_build_object(
 'now', now(),
 'player', (select json_build_object('id', pl.id, 'name', pl.company_name, 'ducats', pl.ducats) from public.players pl join h on h.pid=pl.id),
 'routes', (select json_agg(json_build_object('id', r.id, 'name', r.name, 'fleet', r.fleet_id, 'paused', r.paused_reason, 'hold', r.hold_until, 'lap_no', r.lap_no, 'lap_id', r.lap_id, 'cursor', r.stop_cursor, 'updated', r.updated_at,
     'stops', (select json_agg(json_build_array(s.ord, p.code, s.repair) order by s.ord) from public.standing_route_stops s join public.ports p on p.id=s.port_id where s.route_id=r.id),
     'lines', (select json_agg(json_build_array(l.stop_ord, l.kind, (select code from public.goods g where g.id=l.good_id), l.qty, l.price_limit) order by l.stop_ord, l.ord) from public.standing_route_lines l where l.route_id=r.id))) from r),
 'fleet', (select json_agg(json_build_object('name', f.name, 'status', f.status, 'port', (select code from public.ports where id=f.port_id), 'cargo', (select json_agg(s.cargo) from public.ships s where s.fleet_id=f.id), 'ships', (select json_agg(c.code) from public.ships s join public.ship_classes c on c.id=s.class_id where s.fleet_id=f.id))) from public.fleets f join h on h.pid=f.player_id),
 'laps', (select json_agg(z) from (select lp.lap_no, lp.started_at, lp.closed_at, lp.bought, lp.sold, lp.net, lp.supplies, lp.repairs, lp.wages, lp.taxes, lp.trades, lp.skipped from public.standing_route_laps lp join r on r.id=lp.route_id order by lp.started_at desc limit 8) z)
) j;
rollback;
