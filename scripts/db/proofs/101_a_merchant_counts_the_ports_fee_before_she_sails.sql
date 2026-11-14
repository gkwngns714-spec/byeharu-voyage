-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 101 - A MERCHANT COUNTS THE PORT'S FEE BEFORE SHE SAILS  (migration 0406; docs/dev-log/2026-11-14-plan-fees.md)
--
--   On the world's own merchants, rolled back with proof.mjs's transaction; every plan below is also rolled back alone, so each merchant is planned
--   from the same state every time. The economy is closed and the purses lit, so the dock fee is asked. No price and no choice of the planner is
--   asserted: each merchant's own numbers set her test. For a merchant whose plan pays with the fee at nothing, M is what a lap of the loop she wrote
--   leaves her before fees (her legs through public.npc_leg_lines, her stores by public.stores_cost) and F what its calls charge her at a base of
--   1,000 (public.port_fee, THE fee). Then the base is set so that her loop's fees are half of M (the loop is above its fees), and so that they are
--   just over M (it is under them), and she is planned again by the real planner, alone, at her lap start.
--
-- @pass PF_COST    the leg planner's new `cost` is the sum of the one price authority's buy quotes (world.quote) of the BUY lines it wrote, for every leg of every probe loop
-- @pass PF_ZERO    with the fee knobs at 0 some probe merchants' plans pay (the proof is not vacuous) and the fee of every call is 0
-- @pass PF_ABOVE   a loop above its fees is taken: with her loop's fees at half of M every such merchant sails with cargo, and what the loop she wrote leaves her after fees is above nothing
-- @pass PF_UNDER   a loop under its fees is not taken: with her loop's fees just over M no such merchant sails a loop that leaves her nothing or less after fees; each waits in port or wrote another loop that pays after fees
-- @pass PF_NEVER   at five fee levels (0, 250, 2,000, 20,000 and 1,000,000,000 a call) no probe merchant sails with cargo on a loop whose net after fees is nothing or less; at the last every one whose loop has a charging stop waits in port
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
create function pg_temp.eval_101(p_route uuid) returns jsonb language plpgsql as $f$
-- what a lap of the loop written leaves her, by the planner's own pieces, under the knobs as they stand: {m (before fees), fees, calls, net, cost_ok}
declare
  r        record;
  l        record;
  v_leg    jsonb;
  v_profit numeric := 0; v_wages numeric := 0; v_fees numeric := 0; v_nm numeric := 0; v_calls int := 0; v_stores numeric; v_m numeric;
  v_ok     boolean := true;
  v_q      numeric;
begin
  select sr.player_id, sr.fleet_id,
         (select coalesce(sum(c.crew_required), 0) from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = sr.fleet_id) as crew,
         (select coalesce(sum(public.ship_cargo_tuns(sh.id)), 0) from public.ships sh where sh.fleet_id = sr.fleet_id) + public.fleet_free_hold(sr.fleet_id) as hold,
         greatest(coalesce(voyage.fleet_speed_at(sr.fleet_id, 1), 0), 0.1) as speed
    into r from public.standing_routes sr where sr.id = p_route;
  for l in select st.port_id as a, coalesce(lead(st.port_id) over (order by st.ord), first_value(st.port_id) over (order by st.ord)) as b
             from public.standing_route_stops st where st.route_id = p_route loop
    v_leg := public.npc_leg_lines(p_route, l.a, l.b, r.hold, r.crew::int, r.speed);
    v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
    v_wages  := v_wages + coalesce((v_leg->>'wages')::numeric, 0);
    v_nm     := v_nm + coalesce((v_leg->>'nm')::numeric, 0);
    v_fees   := v_fees + public.port_fee(l.b, r.player_id, coalesce((v_leg->>'cost')::numeric, 0));
    v_calls  := v_calls + 1;
    select coalesce(sum((select q.total from world.quote(l.a, g.id, (x->>'qty')::numeric, 'buy', null, null) q)), 0) into v_q
      from jsonb_array_elements(v_leg->'lines') x join public.goods g on g.code = x->>'good' where x->>'kind' = 'BUY';
    v_ok := v_ok and (v_leg ? 'cost') and (v_leg->>'cost')::numeric = v_q;
  end loop;
  v_stores := public.stores_cost(r.player_id, r.crew * public.wc_num('water_per_crew_day') * v_nm / (r.speed * 24),
                                 r.crew * public.wc_num('food_per_crew_day') * v_nm / (r.speed * 24));
  v_m := v_profit - public.wages_from_profit(v_wages, v_profit) - v_stores;
  return jsonb_build_object('m', v_m, 'fees', v_fees, 'calls', v_calls, 'net', v_m - v_fees, 'cost_ok', v_ok);
end $f$;

create function pg_temp.plan_101(p_route uuid, p_base numeric) returns jsonb language plpgsql as $f$
-- she is planned alone at her lap start under a dock fee of p_base a call (no share of the cargo); answers what she wrote and what it leaves her
declare
  v_r jsonb;
  v_e jsonb;
begin
  update public.world_config set value = to_jsonb(p_base) where key = 'port_fee_base';
  update public.world_config set value = to_jsonb(0) where key = 'port_fee_pct';
  v_r := public.npc_plan(now(), p_route);
  v_e := pg_temp.eval_101(p_route);
  return v_e || jsonb_build_object(
    'planned', v_r->'planned', 'waiting', v_r->'waiting', 'failed', v_r->'failed',
    'paused', (select sr.paused_reason from public.standing_routes sr where sr.id = p_route),
    'buys', (select count(*) from public.standing_route_lines x where x.route_id = p_route and x.kind = 'BUY'),
    'loop', (select string_agg(p.code, '-' order by st.ord) from public.standing_route_stops st join public.ports p on p.id = st.port_id where st.route_id = p_route),
    'charging', (select count(*) from public.standing_route_stops st join public.standing_routes sr on sr.id = st.route_id
                  where st.route_id = p_route and public.port_fee(st.port_id, sr.player_id, 0) > 0));
end $f$;

do $p$
declare
  r        record;
  v        jsonb;
  v0       jsonb;
  v_f1000  numeric;
  v_lo     numeric;
  v_hi     numeric;
  v_base   numeric;
  v_paying int := 0;
  v_above  int := 0;
  v_under_wait int := 0;
  v_under_other int := 0;
  v_levels int := 0;
  v_wait_top int := 0;
  v_cost   int := 0;
begin
  -- ── THE SCENE: closed, the purses lit, the merchants lit, every one on her route where she lies ──
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled', 'economy_closed', 'city_treasury_enabled');
  if not public.npc_traders_on() or not public.economy_closed() or not public.city_treasury_on() then
    raise exception 'proof 101: the closed economy, the purses or the merchants cannot be lit in this world';
  end if;
  -- 0410: a merchant carries only what the city's purse can pay for, and this world's purses are empty: every city is made rich, so the fee is the test
  update public.port_treasury set ducats = 1000000000000;
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null, hold_until = null
    from public.npc_fleets nf where nf.route_id = sr.id;
  create temp table pf101 on commit drop as
  select nf.fleet_id, nf.route_id, nf.player_id, row_number() over (order by nf.roster_ord) as i
    from public.npc_fleets nf
    join public.players pl on pl.id = nf.player_id and not public.pirate_power(pl.nation_id)
    join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
    join public.standing_routes sr on sr.id = nf.route_id
    join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
   where nf.roster_ord <= public.wc_int('npc_fleet_max')
     and not exists (select 1 from public.orders o where o.fleet_id = nf.fleet_id and o.status in ('pending', 'failed'))
     and not exists (select 1 from public.ships sh where sh.fleet_id = nf.fleet_id and public.ship_cargo_tuns(sh.id) > 0)
   order by nf.roster_ord limit 6;
  if (select count(*) from pf101) < 6 then
    raise exception 'proof 101: only % merchants lie in port at their first stop with an empty hold; 6 are wanted', (select count(*) from pf101);
  end if;

  for r in select * from pf101 order by i loop
    -- the fee at nothing
    begin
      v0 := pg_temp.plan_101(r.route_id, 0);
      raise exception sqlstate 'PF101';
    exception when sqlstate 'PF101' then null;
    end;
    if (v0->>'planned')::int <> 1 or (v0->>'failed')::int <> 0 then raise exception 'proof 101: merchant % was not planned: %', r.i, v0; end if;
    if not (v0->>'cost_ok')::boolean then raise exception 'PF_COST: a leg of merchant %''s loop % answers a cost that is not its BUY lines'' quotes', r.i, v0->>'loop'; end if;
    v_cost := v_cost + (v0->>'calls')::int;
    if (v0->>'fees')::numeric <> 0 then raise exception 'PF_ZERO: with the knobs at 0 the calls of % charge %', v0->>'loop', v0->>'fees'; end if;

    -- five levels: never a loop at or under nothing after fees
    foreach v_base in array array[0, 250, 2000, 20000, 1000000000]::numeric[] loop
      begin
        v := pg_temp.plan_101(r.route_id, v_base);
        raise exception sqlstate 'PF101';
      exception when sqlstate 'PF101' then null;
      end;
      if (v->>'planned')::int <> 1 or (v->>'failed')::int <> 0 then raise exception 'proof 101: merchant % was not planned at a fee of %: %', r.i, v_base, v; end if;
      if v->>'paused' is null and (v->>'buys')::int > 0 and (v->>'net')::numeric <= 0 then
        raise exception 'PF_NEVER: at a fee of % a call merchant % sails % with cargo and it leaves her % after fees (before fees %, fees %)', v_base, r.i, v->>'loop', v->>'net', v->>'m', v->>'fees';
      end if;
      if v_base = 1000000000 and (v->>'charging')::int > 0 then
        if v->>'paused' is distinct from 'laid_up' or (v->>'buys')::int <> 0 then
          raise exception 'PF_NEVER: at a fee of 1,000,000,000 a call merchant % does not wait in port: %', r.i, v;
        end if;
        v_wait_top := v_wait_top + 1;
      end if;
      v_levels := v_levels + 1;
    end loop;

    -- her own threshold, when her plan pays with the fee at nothing
    continue when v0->>'paused' is not null or (v0->>'buys')::int = 0 or (v0->>'m')::numeric < 200;
    -- F: what the calls of the loop SHE WROTE AT FEE 0 charge at a base of 1,000 (her stance at each harbour she makes)
    begin
      perform pg_temp.plan_101(r.route_id, 0);
      update public.world_config set value = to_jsonb(1000) where key = 'port_fee_base';
      v_f1000 := (pg_temp.eval_101(r.route_id)->>'fees')::numeric;
      raise exception sqlstate 'PF101';
    exception when sqlstate 'PF101' then null;
    end;
    continue when coalesce(v_f1000, 0) <= 0;   -- no call of her loop charges her (free quays): nothing to test on her
    v_paying := v_paying + 1;
    v_lo := floor((v0->>'m')::numeric * 500 / v_f1000);
    v_hi := ceil(((v0->>'m')::numeric + 10) * 1000 / v_f1000) + 1;

    -- ABOVE: her loop's fees are half of M
    begin
      v := pg_temp.plan_101(r.route_id, v_lo);
      raise exception sqlstate 'PF101';
    exception when sqlstate 'PF101' then null;
    end;
    if v->>'paused' is not null or (v->>'buys')::int = 0 or (v->>'net')::numeric <= 0 then
      raise exception 'PF_ABOVE: merchant %''s loop % leaves % before fees; with a fee of % a call (half of it over the loop) she does not sail a paying loop: %', r.i, v0->>'loop', v0->>'m', v_lo, v;
    end if;
    v_above := v_above + 1;

    -- UNDER: her loop's fees are just over M
    begin
      v := pg_temp.plan_101(r.route_id, v_hi);
      raise exception sqlstate 'PF101';
    exception when sqlstate 'PF101' then null;
    end;
    if v->>'paused' is null and (v->>'buys')::int > 0 then
      if (v->>'net')::numeric <= 0 then
        raise exception 'PF_UNDER: merchant %''s loop % leaves % before fees; with a fee of % a call she sails % with cargo for % after fees', r.i, v0->>'loop', v0->>'m', v_hi, v->>'loop', v->>'net';
      end if;
      v_under_other := v_under_other + 1;
    elsif v->>'paused' = 'laid_up' and (v->>'buys')::int = 0 then
      v_under_wait := v_under_wait + 1;
    else
      raise exception 'PF_UNDER: merchant % neither waits in port nor sails a paying loop at a fee of %: %', r.i, v_hi, v;
    end if;
  end loop;

  if v_paying < 2 then
    raise exception 'PF_ZERO: only % of the 6 probe merchants plan a paying loop with a charging call at fee 0: the proof would be vacuous', v_paying;
  end if;
  raise notice 'PASS: PF_COST the leg planner''s cost is the sum of world.quote over its BUY lines on all % legs of the 6 probe loops', v_cost;
  raise notice 'PASS: PF_ZERO with the knobs at 0 every call charges 0 and % of 6 merchants plan a paying loop with a charging call', v_paying;
  raise notice 'PASS: PF_ABOVE with her loop''s fees at half of what it leaves her, % of % sail with cargo and keep more than nothing after fees', v_above, v_paying;
  raise notice 'PASS: PF_UNDER with her loop''s fees just over what it leaves her, % wait in port and % wrote another loop that pays after fees; none sails for nothing', v_under_wait, v_under_other;
  raise notice 'PASS: PF_NEVER % plans at five fee levels: no merchant sails with cargo for nothing or less after fees; at 1,000,000,000 a call all % with a charging stop wait in port', v_levels, v_wait_top;
end $p$;
