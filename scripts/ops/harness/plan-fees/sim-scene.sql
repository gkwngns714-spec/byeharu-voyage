-- 0406 SIM SCENE (run by sim.mjs, once with the dock fee at nothing WHILE PLANNING and once with prod's knobs, rolled back each time): the economy closed
-- and the purses lit, every merchant started on her route where she lies and planned ALONE at her lap start through the real planner,
-- public.npc_plan(now(), route). Then, in BOTH arms, the loop she wrote is priced again with prod's fee knobs: each leg through the leg planner
-- (public.npc_leg_lines: profit, wages, cost) and each call through THE fee (public.port_fee), the stores by the planner's own expression.
-- --purse=N gives every merchant house a purse of N first (the cached world is rich and its market fresh; prod bleeds at the thin end: 0129 sizes a
-- parcel by the purse, the fee does not shrink with it).
-- With the fee at nothing the planner is the pre-image's (0406's self-assert proves the plan equal), so the first arm is "before".
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
create temp table sim_0406 (fleet_id uuid primary key, route_id uuid, player_id uuid, loop_before text, plan jsonb, ms numeric, loop_after text, buys int, paused text,
                            profit numeric, wages numeric, stores numeric, fees numeric, calls int, net numeric) on commit drop;
do $$
declare
  r   record;
  l   record;
  v_t timestamptz;
  v_p jsonb;
  v_leg jsonb;
  v_profit numeric; v_wages numeric; v_fees numeric; v_nm numeric; v_calls int; v_stores numeric;
begin
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled', 'economy_closed', 'city_treasury_enabled');
  update public.world_config set value = to_jsonb(/*BASE*/::numeric) where key = 'port_fee_base';
  update public.world_config set value = to_jsonb(/*PCT*/::numeric) where key = 'port_fee_pct';
  /*PURSE*/
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null, hold_until = null
    from public.npc_fleets nf where nf.route_id = sr.id;
  for r in
    select nf.fleet_id, nf.route_id, nf.player_id,
           (select string_agg(p.code, '-' order by s.ord) from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = nf.route_id) as lp
      from public.npc_fleets nf where nf.route_id is not null order by nf.roster_ord /*LIMIT*/
  loop
    v_t := clock_timestamp();
    v_p := public.npc_plan(now(), r.route_id);
    insert into sim_0406 (fleet_id, route_id, player_id, loop_before, plan, ms, loop_after, buys, paused)
    values (r.fleet_id, r.route_id, r.player_id, r.lp, v_p, round(extract(epoch from clock_timestamp() - v_t) * 1000),
            (select string_agg(p.code, '-' order by st.ord) from public.standing_route_stops st join public.ports p on p.id = st.port_id where st.route_id = r.route_id),
            (select count(*) from public.standing_route_lines x where x.route_id = r.route_id and x.kind = 'BUY'),
            (select sr.paused_reason from public.standing_routes sr where sr.id = r.route_id));
  end loop;
  -- THE LOOPS WRITTEN, PRICED WITH PROD'S FEE KNOBS (both arms)
  update public.world_config set value = to_jsonb(250) where key = 'port_fee_base';
  update public.world_config set value = to_jsonb(0.005) where key = 'port_fee_pct';
  for r in select s.fleet_id, s.route_id, s.player_id,
                  (select coalesce(sum(c.crew_required), 0) from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = s.fleet_id) as crew,
                  (select coalesce(sum(public.ship_cargo_tuns(sh.id)), 0) from public.ships sh where sh.fleet_id = s.fleet_id) + public.fleet_free_hold(s.fleet_id) as hold,
                  greatest(coalesce(voyage.fleet_speed_at(s.fleet_id, 1), 0), 0.1) as speed
             from sim_0406 s where s.paused is null and s.buys > 0 loop
    v_profit := 0; v_wages := 0; v_fees := 0; v_nm := 0; v_calls := 0;
    for l in select st.port_id as a, coalesce(lead(st.port_id) over (order by st.ord), first_value(st.port_id) over (order by st.ord)) as b
               from public.standing_route_stops st where st.route_id = r.route_id loop
      v_leg := public.npc_leg_lines(r.route_id, l.a, l.b, r.hold, r.crew::int, r.speed);
      v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
      v_wages  := v_wages + coalesce((v_leg->>'wages')::numeric, 0);
      v_nm     := v_nm + coalesce((v_leg->>'nm')::numeric, 0);
      v_fees   := v_fees + public.port_fee(l.b, r.player_id, coalesce((v_leg->>'cost')::numeric, 0));
      v_calls  := v_calls + 1;
    end loop;
    v_stores := public.stores_cost(r.player_id, r.crew * public.wc_num('water_per_crew_day') * v_nm / (r.speed * 24),
                                   r.crew * public.wc_num('food_per_crew_day') * v_nm / (r.speed * 24));
    update sim_0406 s set profit = v_profit, wages = public.wages_from_profit(v_wages, v_profit), stores = v_stores, fees = v_fees, calls = v_calls,
           net = v_profit - public.wages_from_profit(v_wages, v_profit) - v_stores - v_fees
     where s.fleet_id = r.fleet_id;
  end loop;
end $$;
select count(*) as merchants,
       count(*) filter (where paused = 'laid_up') as laid_up,
       count(*) filter (where paused is null and buys > 0) as sailing_with_cargo,
       count(*) filter (where paused is null and buys = 0) as sailing_no_buy,
       count(*) filter (where loop_after is distinct from loop_before) as loops_changed,
       count(*) filter (where (plan->>'failed')::int > 0) as failed,
       count(*) filter (where net <= 0) as planned_net_after_fees_at_or_under_0,
       count(*) filter (where net > 0 and net < 500) as planned_net_under_500,
       round(avg(net)) as mean_net_after_fees, round(percentile_cont(0.5) within group (order by net)::numeric) as median_net_after_fees,
       round(avg(profit)) as mean_profit, round(avg(fees)) as mean_fees, round(avg(calls), 1) as mean_calls, round(avg(wages + stores)) as mean_wages_and_stores,
       round(sum(net) filter (where net <= 0)) as sum_of_the_losing_nets,
       round(avg(ms)) as plan_ms_avg, max(ms) as plan_ms_max
  from sim_0406;
