-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 105 - A LAP PAYS EVERY COST ON THE LIST  (the guard of migration 0410; docs/dev-log/2026-11-14-under-water.md)
--
--   THE GUARD AGAINST A COST THE PLANNER DOES NOT COUNT. 0237 made every harbour charge a dock fee and nobody told the planner (0406 did, five
--   months of laps later) nor the lap's book (0410 did). public.lap_costs is now the one list of what a lap costs, and this proof holds the
--   planner and the book to it FROM REAL LAPS: the world's own merchants are planned and sailed by the real doors (the arrivals beat, the lap
--   starts, the reconcile; the economy closed, the purses lit), and what their purses were really charged is read from the ledger.
--     * A charge of a KIND THAT IS NOT IN THE LIST fails LC_LIST: whoever adds a cost a merchant pays must enter it, and the entry says whether a
--       lap pays it, which column of the book keeps it and which function the planner prices it by.
--     * A listed column the book's net does not take fails LC_BOOK (the identity is built from the list, not written here).
--     * A listed price the planner's bodies do not call fails LC_PLAN; so does an entry "a lap pays it, the planner does not count it" that is
--       not one of the three argued today (REPAIR, INSURANCE, HIRE): a new uncounted cost cannot be entered silently, this line must be edited.
--     * A loop the planner chose to sail with cargo that leaves her nothing or less, with every listed planned cost charged by its own function
--       (the same functions the doors charge by), fails LC_PAYS. The probe prices exactly the listed planned costs, so a new one fails it until
--       the probe prices it too.
--   Rolled back with proof.mjs's transaction. No price and no choice of the planner is asserted.
--
-- @pass LC_LIST   real laps were sailed and closed, the merchants' purses were charged BUY, PORT_FEE and more, and every kind charged is in public.lap_costs
-- @pass LC_BOOK   every lap closed in the soak: its net is its sales less every listed column of the book plus the stock carried out less the stock carried in; the dock fees charged are in the books
-- @pass LC_PLAN   every listed cost with a price is called by the planner's bodies, the probe prices exactly those, and the costs a lap pays that the planner does not count are exactly REPAIR, INSURANCE and HIRE
-- @pass LC_PAYS   no probe merchant sails with cargo a loop that leaves her nothing or less after every listed planned cost; some sail (the proof is not vacuous)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
create function pg_temp.eval_105(p_route uuid) returns jsonb language plpgsql as $f$
-- what a lap of the loop written leaves her, every listed planned cost by its own function: BUY and SELL by the leg planner's quotes
-- (world.quote_priced) with the TAX (public.profit_tax) inside its `profit`, WAGES (public.wages_from_profit), PROVISION (public.stores_cost),
-- PORT_FEE (public.port_fee at every harbour she makes, on the leg's cargo at cost)
declare
  r        record;
  l        record;
  v_leg    jsonb;
  v_profit numeric := 0; v_wages numeric := 0; v_fees numeric := 0; v_nm numeric := 0; v_stores numeric;
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
  end loop;
  v_stores := public.stores_cost(r.player_id, r.crew * public.wc_num('water_per_crew_day') * v_nm / (r.speed * 24),
                                 r.crew * public.wc_num('food_per_crew_day') * v_nm / (r.speed * 24));
  return jsonb_build_object('net', v_profit - public.wages_from_profit(v_wages, v_profit) - v_stores - v_fees, 'fees', v_fees);
end $f$;

do $p$
declare
  c_probe_prices constant text[] := array['world.quote_priced', 'public.profit_tax', 'public.wages_from_profit', 'public.stores_cost', 'public.port_fee'];
  c_not_planned  constant text[] := array['HIRE', 'INSURANCE', 'REPAIR'];
  r        record;
  v        jsonb;
  v_r      jsonb;
  v_k      int;
  v_bad    text;
  v_cols   text;
  v_n      int;
  v_laps   int;
  v_fees   numeric;
  v_kinds  text;
  v_sail   int := 0;
  v_wait   int := 0;
  v_body   text;
begin
  -- ── THE SCENE: closed, the purses lit, the merchants lit, every one on her route where she lies ──
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled', 'economy_closed', 'city_treasury_enabled');
  if not public.npc_traders_on() or not public.economy_closed() or not public.city_treasury_on() then
    raise exception 'proof 105: the closed economy, the purses or the merchants cannot be lit in this world';
  end if;
  update public.port_treasury set ducats = 1000000000000;   -- this world's purses are empty, and a merchant carries only what a city can pay for (0410)
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null, hold_until = now() - interval '1 second'
    from public.npc_fleets nf where nf.route_id = sr.id;   -- her rest is over: the lap-start job takes her (0266)

  -- ── LC_PLAN: the list against the planner's bodies ──
  v_body := pg_get_functiondef('public.npc_plan(timestamp with time zone,uuid)'::regprocedure)
         || pg_get_functiondef('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'::regprocedure);
  select string_agg(c.kind || ' by ' || c.planned, ', ') into v_bad from public.lap_costs c
   where c.planned is not null and position(c.planned || '(' in v_body) = 0;
  if v_bad is not null then raise exception 'LC_PLAN: the list says the planner prices % and its bodies do not call it', v_bad; end if;
  if (select array_agg(distinct c.planned order by c.planned) from public.lap_costs c where c.planned is not null)
     is distinct from (select array_agg(x order by x) from unnest(c_probe_prices) x) then
    raise exception 'LC_PLAN: the list''s planned prices are %, and this proof''s probe prices %: price the new one in eval_105',
      (select array_agg(distinct c.planned order by c.planned) from public.lap_costs c where c.planned is not null), c_probe_prices;
  end if;
  if (select array_agg(c.kind order by c.kind) from public.lap_costs c where c.of_a_lap and c.planned is null) is distinct from c_not_planned then
    raise exception 'LC_PLAN: the costs a lap pays that the planner does not count are %, not %: a cost may not join them silently',
      (select array_agg(c.kind order by c.kind) from public.lap_costs c where c.of_a_lap and c.planned is null), c_not_planned;
  end if;

  -- ── LC_PAYS: six merchants planned alone at their lap start; whoever sails with cargo keeps more than nothing after every listed planned cost ──
  for r in
    select nf.fleet_id, nf.route_id
      from public.npc_fleets nf
      join public.players pl on pl.id = nf.player_id and not public.pirate_power(pl.nation_id)
      join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
      join public.standing_routes sr on sr.id = nf.route_id
      join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
     where nf.roster_ord <= public.wc_int('npc_fleet_max')
       and not exists (select 1 from public.orders o where o.fleet_id = nf.fleet_id and o.status in ('pending', 'failed'))
       and not exists (select 1 from public.ships sh where sh.fleet_id = nf.fleet_id and public.ship_cargo_tuns(sh.id) > 0)
     order by nf.roster_ord limit 6
  loop
    begin
      v_r := public.npc_plan(now(), r.route_id);
      v := pg_temp.eval_105(r.route_id) || jsonb_build_object(
             'planned', v_r->'planned', 'failed', v_r->'failed',
             'paused', (select sr.paused_reason from public.standing_routes sr where sr.id = r.route_id),
             'buys', (select count(*) from public.standing_route_lines x where x.route_id = r.route_id and x.kind = 'BUY'));
      raise exception sqlstate 'LC105';
    exception when sqlstate 'LC105' then null;
    end;
    if (v->>'planned')::int <> 1 or (v->>'failed')::int <> 0 then raise exception 'proof 105: a probe merchant was not planned: %', v; end if;
    if v->>'paused' is null and (v->>'buys')::int > 0 then
      if (v->>'net')::numeric <= 0 then
        raise exception 'LC_PAYS: a merchant sails with cargo a loop that leaves her % after every listed planned cost (dock fees %)', v->>'net', v->>'fees';
      end if;
      v_sail := v_sail + 1;
    else
      v_wait := v_wait + 1;
    end if;
  end loop;
  if v_sail < 2 then raise exception 'LC_PAYS: only % probe merchants sail with cargo: the proof would be vacuous', v_sail; end if;

  -- ── THE SOAK: the whole roster by the real doors, the clock rewound under the voyages (proof 12's loop) ──
  for v_k in 1 .. 12 loop
    update public.voyages vy set departed_at = vy.departed_at - (vy.eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
      from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
     where vy.fleet_id = f.id and vy.status = 'SAILING';
    update public.standing_routes sr set hold_until = now() - interval '1 second'
      from public.players p where p.id = sr.player_id and p.is_npc and sr.hold_until is not null;
    perform public.tick_arrivals(now());
    call public.tick_lap_starts(false);
    if v_k % 5 = 0 then
      call public.tick_reconcile(false);
    end if;
  end loop;

  -- ── LC_LIST: what the purses were really charged ──
  select count(*), coalesce(sum(x.fees), 0) into v_laps, v_fees
    from public.standing_route_laps x join public.npc_fleets nf on nf.route_id = x.route_id where x.closed_at is not null;
  if v_laps < 10 then raise exception 'LC_LIST: the soak closed only % merchant laps: the proof would be vacuous', v_laps; end if;
  select string_agg(distinct g.kind, ', ' order by g.kind) into v_kinds
    from public.ledger g join public.npc_houses h on h.player_id = g.player_id where g.ducats_delta < 0;
  if not exists (select 1 from public.ledger g join public.npc_houses h on h.player_id = g.player_id where g.kind = 'PORT_FEE' and g.ducats_delta < 0)
     or not exists (select 1 from public.ledger g join public.npc_houses h on h.player_id = g.player_id where g.kind = 'BUY' and g.ducats_delta < 0) then
    raise exception 'LC_LIST: the soak charged no BUY or no PORT_FEE (charged: %): the proof would be vacuous', v_kinds;
  end if;
  select string_agg(distinct g.kind, ', ') into v_bad
    from public.ledger g join public.npc_houses h on h.player_id = g.player_id
   where g.ducats_delta < 0 and not exists (select 1 from public.lap_costs c where c.kind = g.kind);
  if v_bad is not null then
    raise exception 'LC_LIST: a merchant''s purse was charged % and public.lap_costs does not list it: enter it (does a lap pay it? which column of the book keeps it? does the planner price it?)', v_bad;
  end if;

  -- ── LC_BOOK: the book's net is built from the list ──
  select string_agg(distinct format('x.%I', c.book), ' + ') into v_cols from public.lap_costs c where c.of_a_lap and c.book is not null;
  execute format($q$
    select count(*) from (
      select x.net, x.sold - (%s) + x.stock_out
                    - coalesce((select y.stock_out from public.standing_route_laps y
                                 where y.route_id = x.route_id and y.closed_at is not null and y.lap_no < x.lap_no order by y.lap_no desc limit 1), 0) as want
        from public.standing_route_laps x join public.npc_fleets nf on nf.route_id = x.route_id
       where x.closed_at is not null) z
     where z.net is distinct from z.want $q$, v_cols) into v_n;
  if v_n <> 0 then
    raise exception 'LC_BOOK: % of % closed laps'' net is not sold - (%) + stock out - stock in: the book does not take every listed cost', v_n, v_laps, v_cols;
  end if;
  if v_fees <= 0 then raise exception 'LC_BOOK: the soak''s closed laps kept no dock fee at all, and PORT_FEE was charged'; end if;

  raise notice 'PASS: LC_LIST % merchant laps closed by the real doors; the purses were charged % and every kind is in public.lap_costs', v_laps, v_kinds;
  raise notice 'PASS: LC_BOOK all % closed laps: net = sold - (%) + stock out - stock in; % d. of dock fees are in their books', v_laps, v_cols, v_fees;
  raise notice 'PASS: LC_PLAN the planner''s bodies call every listed price (%), the probe prices exactly those, and the uncounted costs of a lap are exactly %', c_probe_prices, c_not_planned;
  raise notice 'PASS: LC_PAYS % probe merchants sail with cargo and each keeps more than nothing after every listed planned cost; % wait in port or sail without a BUY', v_sail, v_wait;
end $p$;
