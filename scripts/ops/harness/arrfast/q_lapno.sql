begin transaction read only;
select json_agg(json_build_array(pl.company_name, f.name, sr.lap_no)) j
  from standing_routes sr join npc_fleets nf on nf.route_id = sr.id join fleets f on f.id = nf.fleet_id join players pl on pl.id = nf.player_id;
rollback;
