begin transaction read only;
select json_agg(json_build_array(p.oid::regprocedure::text, p.provolatile::text)) j from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname in ('treasury_balance','quote','haul_rows','reach_from','trade_routes','npc_feasible_legs','npc_known_legs','npc_loop_candidates','affinity_at','daily_cap_remaining','npc_buy_ceiling','npc_affordable','npc_buy_budget','profit_tax','wages_from_profit','stores_cost','crew_wages','running_cost_mult','fleet_speed','city_bid_factor');
rollback;
