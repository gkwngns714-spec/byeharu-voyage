begin transaction read only;
select json_build_object(
 'loops2', (select json_agg(json_build_array(pl.company_name, f.name, (select json_agg(json_build_array(p.code, s.course) order by s.ord) from standing_route_stops s join ports p on p.id=s.port_id where s.route_id=sr.id))) from standing_routes sr join npc_fleets nf on nf.route_id=sr.id join fleets f on f.id=nf.fleet_id join players pl on pl.id=nf.player_id),
 'ships2', (select json_agg(json_build_array(pl.company_name, f.name, s.name, c.code)) from npc_fleets nf join fleets f on f.id=nf.fleet_id join players pl on pl.id=nf.player_id join ships s on s.fleet_id=f.id join ship_classes c on c.id=s.class_id)
) j;
rollback;
