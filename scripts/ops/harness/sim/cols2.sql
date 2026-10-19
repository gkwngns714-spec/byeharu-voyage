begin transaction read only;
select json_object_agg(table_name, cols) j from (select table_name, json_agg(column_name order by ordinal_position) cols from information_schema.columns where table_schema='public' and table_name in ('standing_route_lines','standing_route_stops','standing_route_laps','standing_routes','npc_fleets','npc_houses','orders') group by 1) z;
rollback;
