-- the loop pricing of public.npc_plan (head 0181), verbatim math, for measurement only
create or replace function pg_temp.price_loop(p_route uuid, p_fleet uuid, p_loop jsonb)
returns jsonb language plpgsql as $$
declare
  v_comp numeric := public.wc_num('time_compression');
  v_rest_h numeric := public.wc_num('route_rest_voyage_days') * 86400 / public.wc_num('time_compression') / 3600;
  v_day_h numeric := public.wc_num('game_day_seconds') / 3600;
  sr public.standing_routes%rowtype; v_hold numeric; v_crew int; v_speed numeric;
  v_len int; v_leg jsonb; v_profit numeric := 0; v_wages numeric := 0; v_nm numeric := 0; v_maxnm numeric := 0; v_any boolean := false;
  v_sea_d numeric; v_net numeric; v_buys int := 0; v_legs jsonb := '[]'::jsonb; j int; v_from uuid; v_to uuid;
begin
  select * into sr from public.standing_routes where id = p_route;
  select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0) into v_crew, v_hold
    from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = p_fleet;
  v_hold := v_hold + public.fleet_free_hold(p_fleet);
  v_speed := greatest(coalesce(voyage.fleet_speed(p_fleet), 0), 0.1);
  v_len := jsonb_array_length(p_loop);
  for j in 0 .. v_len - 1 loop
    v_from := (p_loop->j->>'port_id')::uuid; v_to := (p_loop->((j + 1) % v_len)->>'port_id')::uuid;
    v_leg := public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed);
    v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
    v_wages := v_wages + coalesce((v_leg->>'wages')::numeric, 0);
    v_nm := v_nm + coalesce((v_leg->>'nm')::numeric, 0);
    v_maxnm := greatest(v_maxnm, coalesce((v_leg->>'nm')::numeric, 0));
    v_any := v_any or coalesce((v_leg->>'any')::boolean, false);
    v_buys := v_buys + (select count(*) from jsonb_array_elements(v_leg->'lines') x where x->>'kind' = 'BUY');
    v_legs := v_legs || jsonb_build_array(jsonb_build_array(round(coalesce((v_leg->>'nm')::numeric,0)), round(coalesce((v_leg->>'profit')::numeric,0)), round(coalesce((v_leg->>'wages')::numeric,0))));
  end loop;
  v_sea_d := v_nm / (v_speed * 24);
  v_net := v_profit - public.wages_from_profit(v_wages, v_profit)
           - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d, v_crew * public.wc_num('food_per_crew_day') * v_sea_d);
  return jsonb_build_object('net', round(v_net), 'profit', round(v_profit), 'wages', round(v_wages), 'nm', round(v_nm), 'maxnm', round(v_maxnm),
    'any', v_any, 'buys', v_buys, 'hold', round(v_hold), 'crew', v_crew, 'speed', v_speed, 'legs', v_legs,
    'score', round(v_net / greatest(v_nm / v_speed / v_comp + v_rest_h, v_day_h)));
end $$;
