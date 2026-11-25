-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 210 - STORES IN THE HOLD  (migration 0508; docs/design/owner-spec-plan-2026-11-25.md 0.5, 0.6; docs/dev-log/2026-11-25-stores-in-hold.md;
--             the owner, 2026-11-25: "Food and water take cargo space.")
--
--   The migration's self-assert plays one departure. This proof plays the standing jobs as a company lives them, with the stores in
--   their own space (today) and in the hold (0345's switch thrown here, rolled back by proof.mjs): a fixed run over several laps, the
--   long run harbour by harbour that stopped at Luanda before 0508, the run's quote against what she then carried, a Best run, a fleet
--   over her hold, and the light step.
--   THE MARKET IS PINNED (proof.pin_market, its own key) AND THE SEA IS CALMED (hazard_p_max 0): which good a Best run takes and what a
--   quay holds are the market's, dealt anew by every apply, and a voyage's days are rolled on its own id. No marker asks a price for
--   its sign: the fixed runs are planned with 0498's wait dark (BUY ALL whatever the prices) and judged by her hold, her casks and her
--   orders alone. A hull is rolled anew for every company, so both worlds are played on the SAME company, each in a block undone whole.
--
-- @pass SH_OWN     stores in their own space: nothing is asked of her hold, the plan is BUY ALL with no PROVISION, three laps run, none stopped
-- @pass SH_HOLD    in the hold: every plan at the buy harbour provisions first; three laps run, none stopped, no order failed; at each
--                  departure every hull's cargo, water and food are within her hold; she carries fewer units than with her own space
-- @pass SH_QUOTE   in the hold: the units the run's quote names are the units she then carries (the quote is of the run she sails)
-- @pass SH_FAR     in the hold: a run too long for one leg (Lisbon to Cape Town, harbour by harbour) reaches its sale and sells, no order
--                  failed, within her hold at every departure (before 0508 it stopped at Luanda with its cargo aboard)
-- @pass SH_BEST    in the hold: a Best run sails too (its units are the cards' own, which take the stores off since 0345), within her hold
-- @pass SH_OVER    a fleet over her hold on the day of the light: free hold 0 (never under), nothing can be bought, she sails, her cargo
--                  and her stores are what they were; public.stores_in_hold_ready counts her
-- @pass SH_GRACE   the light gives the laden hull 7 days of grace (and no empty one): a full hold, casks eaten empty, she takes on stores
--                  and sails, and can load nothing; lapsed, the sail's stores find no room
-- @pass SH_LIGHT   the light step: the switch false and one news row; a second call refuses and changes nothing
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- every hull of the fleet within her hold (cargo + water + food), to the hundredth
create function pg_temp.within_210(p_fleet uuid) returns boolean language sql as $f$
  select not exists (select 1 from public.ships s where s.fleet_id = p_fleet and public.ship_hold_over(s.id) > 0.01);
$f$;

-- one lap of her job: the tick, then every voyage brought home by moving its clock back (proof 4's way). Answers whether a plan at the
-- buy harbour began with PROVISION, and whether she was within her hold at every departure.
create function pg_temp.lap_210(p_fleet uuid, out provisioned boolean, out within boolean, out units numeric, out good text) language plpgsql as $f$
declare
  v_k int;
  v_plan uuid;
begin
  provisioned := null; within := true; units := null;
  update public.fleet_jobs set next_at = null where fleet_id = p_fleet and paused_reason is null;
  call public.tick_fleet_jobs(false);
  select j.last_plan into v_plan from public.fleet_jobs j where j.fleet_id = p_fleet;
  if exists (select 1 from public.orders o where o.plan_id = v_plan and o.verb in ('BUY', 'TAKE')) then
    provisioned := (select o.verb = 'PROVISION' from public.orders o where o.plan_id = v_plan order by o.seq limit 1);
    good := (select o.args->>'good' from public.orders o where o.plan_id = v_plan and o.verb = 'BUY' limit 1);
  end if;
  for v_k in 1 .. 16 loop
    exit when (select f.status from public.fleets f where f.id = p_fleet) <> 'SAILING';
    within := within and pg_temp.within_210(p_fleet);
    units := coalesce(units, (select sum(public.ship_cargo_tuns(s.id)) from public.ships s where s.fleet_id = p_fleet));
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = p_fleet and status = 'SAILING';
    perform world.fleets();
  end loop;
end $f$;

do $p$
declare
  c_a    constant uuid := '00000000-0508-4000-8000-0000000002a1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a    uuid;
  v_fa   uuid;
  v_good text;
  v_gid  uuid;
  v_bulk numeric;
  v_sell text;
  v_ts   jsonb;
  v_p    jsonb;
  v_rq   jsonb;
  v_r    jsonb;
  v_l    record;
  v_j    public.fleet_jobs%rowtype;
  v_own  numeric;
  v_in   numeric;
  v_qu   numeric;
  v_n    int;
  v_prov int;
  v_ok   boolean;
  v_w0   numeric;
  v_c0   numeric;
  v_sail jsonb;
  v_note text;
  v_news int;
begin
  if (proof.pin_market('00000000-0508-4000-8000-000000000210'::uuid, 'proof-210') ->> 'nonzero')::int < 14000 then
    raise exception 'PROOF 210: the market was not pinned';
  end if;
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled');
  update public.world_config set value = 'false'::jsonb where key = 'jobs_wait_enabled';
  if public.wc_num('hazard_p_max') <> 0 or not public.ship_stores_separate() then
    raise exception 'PROOF 210: the sea was not calmed, or the stores are not in their own space in the shipped world';
  end if;

  v_a := public.new_house(c_a, 'Casa do Porao 210', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  update public.players set ducats = 20000000 where id = v_a;
  -- a full crew and empty casks: the most a way's stores ask of a hold
  update public.ships s set crew = c.crew_max, water_t = 0, food_t = 0 from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fa;
  perform cmd.assume_identity(c_a);
  -- the pair, from static rows: a good Lisbon offers and her nearest remembered harbour that takes it; Lisbon's quay made full (her
  -- hold is what binds a BUY ALL, never the stock or the day's allowance), the sale's allowance wide
  select g.code, g.id, g.bulk, k.code into v_good, v_gid, v_bulk, v_sell
    from public.npc_known_legs(v_lis) k
    join public.port_goods ps on ps.port_id = k.to_port
    join public.goods g on g.id = ps.good_id
    join public.ports pd on pd.id = k.to_port and pd.kind = 'HARBOUR'
   where public.port_offers(v_lis, g.id) and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
     and not public.culture_refuses(pd.culture, g.culture_mask) and public.fleet_free_hold(v_fa) >= 20 * g.bulk
   order by k.nm, g.code limit 1;
  update public.port_goods pg set stock_target = 1000000, stock = 1000000000 where pg.good_id = v_gid and pg.port_id = v_lis;
  update public.port_goods pg set stock_target = 1000000 where pg.good_id = v_gid and pg.port_id in (select p.id from public.ports p where p.code in (v_sell, 'CPT'));

  -- ── SH_OWN: stores in their own space ──
  begin
    perform cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell));
    v_ts := public.fleet_trip_stores(v_fa, v_lis, array[v_sell]);
    v_p := public.fleet_job_plan(v_fa);
    if (v_ts->>'tons')::numeric <> 0 or v_p #>> '{lines,0,text}' is distinct from format('BUY %s ALL', v_good) then
      raise exception 'PROOF 210 FAIL: own space, her hold is asked for stores or the plan is not BUY ALL: % / %', v_ts, left(v_p::text, 300);
    end if;
    v_n := 0;
    for i in 1 .. 12 loop
      select * into v_l from pg_temp.lap_210(v_fa);
      if v_l.provisioned then
        raise exception 'PROOF 210 FAIL: own space, a plan provisioned first';
      end if;
      v_own := coalesce(v_own, v_l.units);
      select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
      exit when v_j.paused_reason is not null or v_j.runs >= 6;
    end loop;
    if v_j.paused_reason is not null or v_j.runs < 6 or exists (select 1 from public.orders o where o.fleet_id = v_fa and o.status = 'failed') then
      raise exception 'PROOF 210 FAIL: own space, three laps did not run: %', to_jsonb(v_j);
    end if;
    raise notice 'PASS: SH_OWN — % from LIS to %, crew %: BUY ALL, no stores asked of her hold, % runs (out and home), % t of cargo a lap',
      v_good, v_sell, (select sum(s.crew) from public.ships s where s.fleet_id = v_fa), v_j.runs, v_own;
    raise exception using errcode = 'ZP210', message = 'undo';
  exception when sqlstate 'ZP210' then null;
  end;

  -- ── SH_HOLD, SH_QUOTE: the same company, the same run, the stores in the hold ──
  update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';
  begin
    perform cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell));
    v_ts := public.fleet_trip_stores(v_fa, v_lis, array[v_sell]);
    v_rq := public.fleet_run_quote(v_a, v_fa, v_lis, v_good, v_sell, array[v_sell, 'LIS']);
    v_p := public.fleet_job_plan(v_fa);
    if coalesce((v_ts->>'tons')::numeric, 0) <= 0 or v_p #>> '{lines,0,text}' is distinct from format('PROVISION DAYS %s', v_ts->>'days')
       or v_p #>> '{lines,1,text}' is distinct from format('BUY %s ALL', v_good) then
      raise exception 'PROOF 210 FAIL: in the hold, the plan does not take her stores on first: % / %', v_ts, left(v_p::text, 300);
    end if;
    v_n := 0; v_prov := 0; v_ok := true;
    for i in 1 .. 12 loop
      select * into v_l from pg_temp.lap_210(v_fa);
      v_ok := v_ok and v_l.within;
      if v_l.provisioned is not null then
        v_n := v_n + 1;
        v_prov := v_prov + case when v_l.provisioned then 1 else 0 end;
        v_in := coalesce(v_in, v_l.units);
        v_qu := coalesce(v_qu, public.fleet_cargo_qty(v_fa, v_good));
      end if;
      v_qu := coalesce(v_qu, (select sum(o.qty_done) from (select (o.result->>'qty')::numeric as qty_done from public.orders o
                                where o.fleet_id = v_fa and o.verb = 'BUY' and o.status = 'done' order by o.seq limit 1) o));
      select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
      exit when v_j.paused_reason is not null or v_j.runs >= 6;
    end loop;
    if v_j.paused_reason is not null or v_j.runs < 6 or not v_ok or v_n < 3
       or exists (select 1 from public.orders o where o.fleet_id = v_fa and o.status = 'failed') then
      raise exception 'PROOF 210 FAIL: in the hold, three laps did not run within her hold (% buys, within %): % / %', v_n, v_ok, to_jsonb(v_j),
        (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fa and o.status = 'failed');
    end if;
    -- she provisions whenever her casks are under her way's days: the first lap for certain (empty casks)
    if v_prov < 1 or v_in >= v_own then
      raise exception 'PROOF 210 FAIL: in the hold, no plan provisioned first, or she carries no less than with her own space (% against % t)', v_in, v_own;
    end if;
    raise notice 'PASS: SH_HOLD — in the hold: % of % plans at the buy harbour took her stores on first (% days, % t), % runs, none stopped, within her hold at every departure; % t of cargo a lap against % with her own space',
      v_prov, v_n, v_ts->>'days', v_ts->>'tons', v_j.runs, v_in, v_own;
    -- the quote of the first run: its units are the tuns she carried
    if (v_rq->>'units')::numeric * v_bulk is distinct from v_in or (v_rq->>'cut')::boolean is not true then
      raise exception 'PROOF 210 FAIL: in the hold, the quote named % units (% t) and she carried % t: %', v_rq->>'units', (v_rq->>'units')::numeric * v_bulk, v_in, v_rq;
    end if;
    raise notice 'PASS: SH_QUOTE — in the hold: the quote named % units (cut to what fits beside her stores) and she carried %', v_rq->>'units', trim_scale(v_in / v_bulk);
    raise exception using errcode = 'ZP210', message = 'undo';
  exception when sqlstate 'ZP210' then null;
  end;

  -- ── SH_FAR: harbour by harbour to Cape Town ──
  begin
    v_r := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', 'CPT'));
    v_p := public.fleet_job_plan(v_fa);
    if (v_r->>'ok')::boolean is not true or (select count(*) from jsonb_array_elements(v_p->'lines') l where l->>'text' like 'SAIL %') < 2
       or v_p #>> '{lines,0,text}' not like 'PROVISION DAYS %' then
      raise exception 'PROOF 210 FAIL: the run to Cape Town is not a provision and several sails: % / %', v_r, left(v_p::text, 400);
    end if;
    select * into v_l from pg_temp.lap_210(v_fa);
    select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
    if v_j.paused_reason is not null or not v_l.within or v_j.runs <> 1
       or (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fa) is distinct from 'CPT'
       or coalesce(public.fleet_cargo_qty(v_fa, v_good), 0) <> 0
       or exists (select 1 from public.orders o where o.fleet_id = v_fa and o.status in ('failed', 'cancelled', 'pending', 'active')) then
      raise exception 'PROOF 210 FAIL: in the hold, the run to Cape Town did not reach its sale and sell within her hold: % / %', to_jsonb(v_j),
        (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fa);
    end if;
    raise notice 'PASS: SH_FAR — in the hold: % : she reached Cape Town and sold, within her hold at every departure',
      (select string_agg(l->>'text', ' / ') from jsonb_array_elements(v_p->'lines') l);
    raise exception using errcode = 'ZP210', message = 'undo';
  exception when sqlstate 'ZP210' then null;
  end;

  -- ── SH_BEST: a Best run in the hold ──
  begin
    perform cmd.set_fleet_job(v_fa, 'best', '{}'::jsonb);
    v_p := public.fleet_job_plan(v_fa);
    if not (v_p ? 'lines') then
      raise exception 'PROOF 210 FAIL: on the pinned market a Best run at Lisbon has no plan: %', v_p;
    end if;
    select * into v_l from pg_temp.lap_210(v_fa);
    select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
    if v_j.paused_reason is not null or v_j.runs <> 1 or not v_l.within
       or exists (select 1 from public.orders o where o.fleet_id = v_fa and o.status in ('failed', 'cancelled')) then
      raise exception 'PROOF 210 FAIL: in the hold, a Best run did not sail within her hold: % / %', to_jsonb(v_j),
        (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fa);
    end if;
    raise notice 'PASS: SH_BEST — in the hold: a Best run (% to %) sailed and sold, within her hold', v_p #>> '{note,good}', v_p #>> '{note,to}';
    raise exception using errcode = 'ZP210', message = 'undo';
  exception when sqlstate 'ZP210' then null;
  end;

  -- ── SH_OVER: loaded while her stores had their own space, then the light ──
  begin
    update public.world_config set value = 'true'::jsonb where key = 'ship_stores_separate';
    v_r := cmd.issue_lines(v_fa, jsonb_build_array(jsonb_build_object('text', format('BUY %s ALL', v_good))), null);
    update public.ships s set water_t = s.crew * public.wc_num('water_per_crew_day') * 9, food_t = s.crew * public.wc_num('food_per_crew_day') * 9 where s.fleet_id = v_fa;
    select sum(s.water_t + s.food_t), sum(public.ship_cargo_tuns(s.id)) into v_w0, v_c0 from public.ships s where s.fleet_id = v_fa;
    v_n := (public.stores_in_hold_ready()->>'ships_over')::int;
    update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';
    v_sail := (select l from jsonb_array_elements(public.fleet_job_sails(v_fa, v_lis, array[v_sell])->'lines') l limit 1);
    if pg_temp.within_210(v_fa) or public.fleet_free_hold(v_fa) <> 0 or (public.fleet_buy_capacity(v_fa, v_gid)->>'max_qty')::numeric <> 0
       or (cmd.preview(v_fa, format('BUY %s 1', v_good))->>'ok')::boolean is not false
       or v_n < 1 or (public.stores_in_hold_ready()->>'ships_over')::int <> v_n or (public.stores_in_hold_ready()->>'in_hold')::boolean is not true then
      raise exception 'PROOF 210 FAIL: over her hold, her free hold is not 0, she can load, or the count does not hold her: free %, capacity %, ready %',
        public.fleet_free_hold(v_fa), public.fleet_buy_capacity(v_fa, v_gid), public.stores_in_hold_ready();
    end if;
    v_r := cmd.issue_lines(v_fa, jsonb_build_array(v_sail), null);
    if (v_r->>'ok')::boolean is not true or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING'
       or (select sum(public.ship_cargo_tuns(s.id)) from public.ships s where s.fleet_id = v_fa) <> v_c0
       or (select sum(s.water_t + s.food_t) from public.ships s where s.fleet_id = v_fa) < v_w0 then
      raise exception 'PROOF 210 FAIL: over her hold, she did not sail with what she had: %', left(v_r::text, 300);
    end if;
    raise notice 'PASS: SH_OVER — % t of cargo and % t of stores in a hold of %: free hold 0, nothing bought, she sailed with both; the rule counts % ship(s) over',
      v_c0, v_w0, (select sum(public.ship_hold_capacity(s.id)) from public.ships s where s.fleet_id = v_fa), v_n;
    raise exception using errcode = 'ZP210', message = 'undo';
  exception when sqlstate 'ZP210' then null;
  end;

  -- ── SH_GRACE: the light's own stamp on a laden fleet ──
  begin
    update public.world_config set value = 'true'::jsonb where key = 'ship_stores_separate';
    v_r := cmd.issue_lines(v_fa, jsonb_build_array(jsonb_build_object('text', format('BUY %s ALL', v_good))), null);
    v_r := public.stores_in_hold_light();
    if (v_r->>'graced')::int < 1 or exists (select 1 from public.ships s where s.fleet_id = v_fa and s.hold_grace_until is null)
       or exists (select 1 from public.ships s where s.hold_grace_until is not null and public.ship_cargo_tuns(s.id) = 0) then
      raise exception 'PROOF 210 FAIL: the light did not grace the laden hull, or graced an empty one: %', v_r;
    end if;
    update public.ships s set water_t = 0, food_t = 0, hold_grace_until = now() - interval '1 second' where s.fleet_id = v_fa;
    if (select n.fits from public.supply_need(v_fa, 100) n) is not false then
      raise exception 'PROOF 210 FAIL: with the grace lapsed a full hold found room for a sail''s stores';
    end if;
    update public.ships s set hold_grace_until = now() + interval '1 day' where s.fleet_id = v_fa;
    v_sail := (select l from jsonb_array_elements(public.fleet_job_sails(v_fa, v_lis, array[v_sell])->'lines') l limit 1);
    v_r := cmd.issue_lines(v_fa, jsonb_build_array(v_sail), null);
    if (v_r->>'ok')::boolean is not true or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING'
       or (select sum(s.water_t + s.food_t) from public.ships s where s.fleet_id = v_fa) <= 0 or public.fleet_free_hold(v_fa) <> 0 then
      raise exception 'PROOF 210 FAIL: in the grace she did not take on stores and sail, or she can load: %', left(v_r::text, 300);
    end if;
    raise notice 'PASS: SH_GRACE — % hull(s) graced by the light; a full hold and empty casks: no room without it, stores taken on and sailed with it, free hold 0',
      (select count(*) from public.ships s where s.hold_grace_until is not null);
    raise exception using errcode = 'ZP210', message = 'undo';
  exception when sqlstate 'ZP210' then null;
  end;

  -- ── SH_LIGHT ──
  update public.world_config set value = 'true'::jsonb where key = 'ship_stores_separate';
  v_news := (select count(*) from public.world_news);
  v_r := public.stores_in_hold_light();
  if public.ship_stores_separate() or (v_r->>'in_hold')::boolean is not true or (select count(*) from public.world_news) <> v_news + 1 then
    raise exception 'PROOF 210 FAIL: the light step did not put the stores in the hold with one news row: %', v_r;
  end if;
  begin
    perform public.stores_in_hold_light();
    raise exception 'PROOF 210 FAIL: the light step ran twice';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'stores_in_hold_light refuses:%' then raise; end if;
  end;
  if public.ship_stores_separate() or (select count(*) from public.world_news) <> v_news + 1 then
    raise exception 'PROOF 210 FAIL: a refused second light changed something';
  end if;
  raise notice 'PASS: SH_LIGHT — the light step: the switch false, one news row; a second call refuses and changes nothing';
end $p$;
