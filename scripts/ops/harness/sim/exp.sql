begin transaction read only;
select json_build_object(
 'at', now(),
 'stock', (select json_agg(json_build_array(p.code, g.code, pg.stock)) from public.port_goods pg join public.ports p on p.id=pg.port_id join public.goods g on g.id=pg.good_id where pg.stock is distinct from pg.stock_target),
 'purse', (select json_agg(json_build_array(pl.company_name, pl.ducats)) from public.npc_houses h join public.players pl on pl.id=h.player_id),
 'treasury', (select json_agg(json_build_array(p.code, public.treasury_balance(p.id))) from public.port_treasury t join public.ports p on p.id=t.port_id),
 'works', (select json_agg(json_build_array(p.code, w.kind, w.level, w.subscribed)) from public.city_works w join public.ports p on p.id=w.port_id where w.level>0 or w.subscribed>0),
 'loops', (select json_agg(json_build_array(f.name, (select json_agg(json_build_array(p.code, s.course) order by s.ord) from standing_route_stops s join ports p on p.id=s.port_id where s.route_id=sr.id))) from standing_routes sr join npc_fleets nf on nf.route_id=sr.id join fleets f on f.id=nf.fleet_id),
 'ships', (select json_agg(json_build_array(f.name, s.name, c.code)) from npc_fleets nf join fleets f on f.id=nf.fleet_id join ships s on s.fleet_id=f.id join ship_classes c on c.id=s.class_id)
);
rollback;
