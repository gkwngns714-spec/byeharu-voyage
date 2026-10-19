begin transaction read only;
select json_build_object(
 'at', now(),
 'stock', (select json_agg(json_build_array(p.code, g.code, pg.stock)) from port_goods pg join ports p on p.id = pg.port_id join goods g on g.id = pg.good_id),
 'purse', (select json_agg(json_build_array(pl.company_name, pl.ducats)) from players pl where pl.is_npc),
 'treasury', (select json_agg(json_build_array(p.code, public.treasury_balance(p.id))) from port_treasury t join ports p on p.id = t.port_id),
 'loops2', (select json_agg(json_build_array(pl.company_name, f.name, (select json_agg(json_build_array(p.code, s.course) order by s.ord) from standing_route_stops s join ports p on p.id=s.port_id where s.route_id=sr.id))) from standing_routes sr join npc_fleets nf on nf.route_id=sr.id join fleets f on f.id=nf.fleet_id join players pl on pl.id=nf.player_id),
 'wc', (select json_object_agg(key, value) from world_config),
 'n_npc_fleets', (select count(*) from npc_fleets)
) j;
rollback;
