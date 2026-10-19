CREATE OR REPLACE FUNCTION public.npc_leg_lines(p_route uuid, p_from uuid, p_to uuid, p_hold numeric, p_crew integer, p_speed numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- The lines a merchant route writes at p_from bound for p_to, and what they pay. 0114:246-293
-- moved here whole so a loop can be priced without being written (npc_plan prices every candidate
-- loop through this and writes only the winner):
--   1. RANK with THE ranking (world.trade_routes, p_from to p_to, twelve rows), priced end to end
--      through world.quote.
--   2. FILTER: the house's authored wares first (all rows only when no listed good passes), and at
--      most npc_buyers_per_good OTHER merchant routes buying that good here (a laid-up or failed
--      route holds no place) — the count taken ONCE per port, as a good -> buyers map.
--   3. SIZE each kept good with the quote authority's own answer: the units the SINK takes above
--      the probe's cost x (1 + npc_sell_margin), capped by the daily cap at both ends, (0129) what
--      her working capital still covers at the source (public.npc_affordable) and the hold
--      left. KEEP only if the two quotes at that size pay after the profit tax (0128: the leg's
--      wages, running_cost_mult, come out of its profit — public.wages_from_profit) and
--      return >= npc_min_return_pct on the outlay. The first npc_lines_per_stop.
--   4. LINES: SELL everything above cost (paid + npc_sell_margin); for a good refused E_PRICE_LIMIT
--      on a SELL here in BOTH of the last two closed laps, the cut-loss: SELL <good> ALL at the
--      quay's bid, no floor (0142: the at-cost floor 0120 put here was never asked for — removed);
--      BUY <good> <q> AT <ceiling>.
-- Answers {lines, profit, wages, nm, any}: `profit` is the sum of (sink quote - source quote) less
-- the sink's profit tax over the kept goods; `wages` what the leg's sea-days owe (0142: npc_plan
-- takes them out of the LOOP's profit, once — a ballast leg's days are owed too); `nm` the sailed
-- distance from the reach table (the figure the ranking's rows carry); `any` whether anything was kept.
declare
  v_k       int     := public.wc_int('npc_lines_per_stop');
  v_margin  numeric := public.wc_num('npc_sell_margin');
  v_minret  numeric := public.wc_num('npc_min_return_pct');
  v_kmax    int     := public.wc_int('npc_buyers_per_good');
  sr        public.standing_routes%rowtype;
  h         public.npc_houses%rowtype;
  v_code    text;
  v_nm      numeric;
  v_lines   jsonb := jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true));
  v_cut     text;
  v_rows    jsonb;
  v_buyers  jsonb;
  e         jsonb;
  v_good    uuid;
  v_bulk    numeric;
  v_cap     numeric;
  v_q       numeric;
  v_ceiling numeric;
  v_left    numeric;
  v_wages   numeric;
  v_kept    int := 0;
  v_pass    int;
  v_profit  numeric := 0;
  v_net     numeric;   -- 0122: a parcel's margin after the sink's profit tax
  v_budget  numeric;   -- 0129: her working capital left for this leg's parcels
  v_any     boolean := false;
  q_size    record;
  q_sell    record;
  q_buy     record;
begin
  select * into sr from public.standing_routes where id = p_route;
  select * into h from public.npc_houses where player_id = sr.player_id;
  select p.code into v_code from public.ports p where p.id = p_from;
  select r.nm into v_nm from voyage.reach_from(p_from) r where r.port_id = p_to;

  -- THE CUT-LOSS: refused E_PRICE_LIMIT on a SELL here in BOTH of the last two closed laps.
  for v_cut in
    select z.g from (
      select split_part(x.e->>'line', ' ', 2) as g, count(distinct x.lap_no) as laps
        from (select l.lap_no, jsonb_array_elements(l.skipped) as e
                from (select lp.lap_no, lp.skipped from public.standing_route_laps lp
                       where lp.route_id = sr.id and lp.closed_at is not null
                       order by lp.lap_no desc limit 2) l) x
       where x.e->>'port' = v_code and x.e->>'verb' = 'SELL' and x.e->>'code' = 'E_PRICE_LIMIT'
       group by 1) z
     where z.laps = 2 and exists (select 1 from public.goods g where g.code = z.g)
     order by z.g limit 2 loop
    v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', false);   -- 0142: at the quay's bid
  end loop;
  -- 0150: THE CUT-LOSS FOR ROOM. Her SAIL from here was refused E_ENDURANCE and a hull of hers
  -- cannot stow this leg's casks beside the cargo the at-profit SELL could not move
  -- (public.npc_casks_blocked): every good aboard goes at the quay's bid, so the PROVISION after
  -- it has room and her lap can close — the two-closed-laps cut-loss above never comes to a lap
  -- that cannot close.
  if public.npc_casks_blocked(sr.fleet_id, p_from, v_nm, p_speed) then
    for v_cut in select distinct e.key from public.ships s cross join lateral jsonb_each(s.cargo) e
                  where s.fleet_id = sr.fleet_id and (e.value)::text::numeric > 0
                  order by 1 loop
      continue when v_lines @> jsonb_build_array(jsonb_build_object('kind', 'SELL', 'good', v_cut));
      v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', false);
    end loop;
  end if;

  -- THE OTHER MERCHANT BUYERS HERE, per good, once (0114 counted them once per candidate good).
  select coalesce(jsonb_object_agg(z.g, z.n), '{}'::jsonb) into v_buyers from (
    select l.good_id::text as g, count(distinct l.route_id) as n
      from public.standing_route_lines l
      join public.standing_route_stops s3 on s3.route_id = l.route_id and s3.ord = l.stop_ord
      join public.standing_routes sr3 on sr3.id = l.route_id
                                     and coalesce(sr3.paused_reason, '') not in ('laid_up', 'error')
      join public.players p3 on p3.id = sr3.player_id and p3.is_npc
     where l.route_id <> sr.id and l.kind = 'BUY' and s3.port_id = p_from
     group by 1) z;

  -- RANK, FILTER, SIZE, KEEP.
  v_rows  := coalesce(world.trade_routes(p_from, null, null, 12, p_to)->'routes', '[]'::jsonb);
  v_left  := p_hold;
  -- 0129: her fleet's working capital — the route's fleet, or (before the switch assigns it) the
  -- merchant fleet the roster keeps for this route.
  v_budget := public.npc_buy_budget(coalesce(sr.fleet_id,
                (select nf.fleet_id from public.npc_fleets nf where nf.route_id = sr.id limit 1)));
  v_wages := public.crew_wages(p_crew, false) * public.running_cost_mult(sr.player_id)
             * coalesce(v_nm, 0) / (greatest(p_speed, 0.1) * 24);
  for v_pass in 1 .. 2 loop
    exit when v_pass = 2 and v_kept > 0;
    for e in select x from jsonb_array_elements(v_rows) x loop
      exit when v_kept >= v_k;
      v_good := (e->>'good_id')::uuid;
      continue when v_pass = 1 and not ((e->>'code') = any(h.wares));
      continue when v_lines @> jsonb_build_array(jsonb_build_object('kind', 'BUY', 'good', e->>'code'));
      continue when coalesce((v_buyers->>(v_good::text))::int, 0) >= v_kmax;
      select g.bulk into v_bulk from public.goods g where g.id = v_good;
      v_cap := floor(least(world.daily_cap_remaining(sr.player_id, p_from, v_good),
                           world.daily_cap_remaining(sr.player_id, p_to, v_good),
                           v_left / greatest(v_bulk, 0.001)));
      continue when v_cap is null or v_cap < 1;
      -- THE SIZE is the sink's own answer: units it takes above the probe's cost plus the margin.
      select * into q_size from world.quote(p_to, v_good, v_cap, 'sell',
                                            round((e->>'buy_price')::numeric * (1 + v_margin), 2), null);
      v_q := floor(coalesce(q_size.units, 0));
      continue when v_q < 1;
      -- 0129: and no more than her working capital covers at the source — the quay refuses a parcel
      -- she cannot pay for WHOLE (E_INSUFFICIENT_FUNDS), and she sails in ballast.
      select a.units into v_q from public.npc_affordable(p_from, v_good, v_q, v_budget) a;
      continue when v_q < 1;
      select * into q_buy from world.quote(p_from, v_good, v_q, 'buy', null, null);
      continue when q_buy.units is null or q_buy.units < v_q or q_buy.total <= 0;
      select * into q_sell from world.quote(p_to, v_good, v_q, 'sell', null, null);
      -- 0122: the parcel's cost IS q_buy.total, so this is exactly the profit do_sell will tax.
      v_net := (q_sell.total - q_buy.total) - public.profit_tax(p_to, q_sell.total - q_buy.total,
                 (select r_0147.player_id from public.standing_routes r_0147 where r_0147.id = p_route));   -- 0147: her rate
      -- 0128: wages are paid out of the profit and never past it, so a parcel that pays is kept.
      continue when v_net <= 0
                 or v_net * 100 < v_minret * q_buy.total;
      v_ceiling := public.npc_buy_ceiling(p_from, v_good, h.patience);
      continue when v_ceiling is null
                 -- 0180: A LINE IS NEVER BORN REFUSED. A line whose limit is below the parcel's own priced
                 -- ask is refused E_PRICE_LIMIT on arrival; such a parcel is not kept, and the ranking's
                 -- next good is tried. 0181: the ceiling is the quay's ask now × (1 + patience), so this
                 -- drops only a parcel whose own size walks the price past her patience.
                 or v_ceiling < q_buy.avg_price;
      v_lines  := v_lines || jsonb_build_object('kind', 'BUY', 'good', e->>'code', 'qty', v_q,
                                                'price_limit', v_ceiling);
      v_left   := v_left - v_q * v_bulk;
      v_budget := v_budget - q_buy.total;   -- 0129
      v_kept   := v_kept + 1;
      v_profit := v_profit + v_net;   -- 0122: after tax
      v_any    := true;
    end loop;
  end loop;

  -- 0142: the leg's profit after tax, and apart from it the wages its sea-days owe — npc_plan takes
  -- the wages out of the LOOP's profit by the rule the sale pays by (public.wages_from_profit).
  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'wages', v_wages,
                            'nm', v_nm, 'any', v_any);
end $function$
