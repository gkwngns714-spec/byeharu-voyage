-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 7 — SUPPLIES AT SAIL  (migration 0225; this file replaced 07_standing_provision, whose subject is gone)
--
-- WHAT THIS PROOF IS FOR, AND WHY IT IS NOT THE MIGRATION'S SELF-ASSERT AGAIN
--   0225 proves, in the transaction that applies it, that the slices are byte-parity, that a SAIL
--   buys the stores its leg asks and nothing when the casks cover it, that a full hold is refused
--   E_ENDURANCE with nothing bought, that the arrival no longer provisions, and that the board's
--   `supplies.cost` is what the SAIL paid. It cannot prove these, and these are this file:
--
--     1. THE MECHANIC WORKS THROUGH THE DOOR THE BROWSER USES: her SAIL goes through cmd.issue with a
--        proposed course (proof.sail, the fixture that proposes as the Trade page's Go does; the
--        identity is the house's, cmd.assume_identity), and the stores are bought by that path with
--        no PROVISION line anywhere in her queue.
--     2. THE OLD DOORS ARE SHUT TO HER: the four preset entry points answer 42501 to `authenticated`
--        and are out of public.client_rpc_entry_points(); public.supply_need is server-only.
--     3. THE WHOLE TRIP, AS THE OWNER PLAYS IT (row 194): BUY here → SAIL → SELL there from one queue,
--        the stores bought at the SAIL, the voyage warped to arrival, the SELL run, the purse moved —
--        and the arrival bought nothing (the standing order is gone, and nothing fires in its place).
--     4. A STOCKED FLEET BUYS NOTHING: topped up past the leg's need, her SAIL writes no PROVISION row.
--
-- ── EVERY PRECONDITION IS SET HERE, NONE IS BORROWED ────────────────────────────────────────────
-- The hazard ceiling is zeroed IN THIS TRANSACTION; the house is founded here; her casks are run
-- down here; the good she carries home is the first Cádiz offers in stock, by code (no lottery); every warp
-- loops until she is in. All of it rolls back with the proof.
--
-- @pass SAIL_BUYS_ITS_STORES         with empty casks, SAIL LIS → CAD through cmd.issue: her stores land at or above the leg's need (voyage.stores_need_days), ONE PROVISION ledger row equals the purse change, no PROVISION order was queued
-- @pass KEEP_DOORS_SHUT              the four preset entry points answer 42501 to `authenticated`, are out of client_rpc_entry_points(), and public.supply_need is server-only
-- @pass TRIP_FROM_ONE_QUEUE          BUY at Cádiz (the board's units_fit), SAIL, SELL at Lisbon queued together (cmd.issue_lines): the SAIL bought its stores, the arrival ran the SELL, the purse took the proceeds, and the arrivals bought NO stores
-- @pass RETURN_BUYS_THE_DIFFERENCE   a fleet stocked past the leg's need sails and buys nothing: the three PROVISION rows are the two SAILs that needed stores and the top-up itself
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth    constant uuid := '00000000-0f07-4000-8000-000000000221';
  v_player  uuid;
  v_fleet   uuid;
  v_lis     uuid;
  v_cad     uuid;
  v_good    uuid;
  v_gcode   text;
  v_res     jsonb;
  v_need    numeric;
  v_nm      numeric;
  v_speed   numeric;
  v_end     numeric;
  v_purse0  bigint;
  v_purse1  bigint;
  v_prov    int;
  v_prov0   int;
  v_cost    bigint;
  v_exp     bigint;
  v_rows    int;
  v_units   numeric;
  v_fit     numeric;
  v_sold    bigint;
  k         int;
begin
  -- ── THE PRECONDITIONS THIS PROOF OWNS ────────────────────────────────────────────────────────
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_cad from public.ports where code = 'CAD';
  v_player := public.new_house(c_auth, 'Casa das Velas', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  -- her casks run dry, so the SAIL has something to buy
  update public.ships set water_t = 0, food_t = 0 where fleet_id = v_fleet;

  -- ── 1. THE SAIL BUYS ITS STORES, through the client door ──────────────────────────────────────
  perform cmd.assume_identity(c_auth);
  select ducats into v_purse0 from public.players where id = v_player;
  select count(*) into v_prov0 from public.ledger where player_id = v_player and kind = 'PROVISION';
  -- what the one rule says this leg's stores cost her now (proof.course's measure is the course cmd.do_sail measures)
  select n.cost into v_exp from public.supply_need(v_fleet, (select sum((s->>'nm')::numeric)
    from jsonb_array_elements(voyage.segments_from_course(proof.course('LIS', 'CAD'))) s)) n;
  v_res := proof.sail(v_fleet, 'CAD');
  if coalesce((v_res->>'ok')::boolean, false) is not true then
    raise exception 'PROOF 7 FAILED: the SAIL was refused: %', v_res;
  end if;
  select ducats into v_purse1 from public.players where id = v_player;
  select count(*) into v_prov from public.ledger where player_id = v_player and kind = 'PROVISION';
  if v_prov - v_prov0 <> 1 then
    raise exception 'PROOF 7 FAILED: the SAIL wrote % PROVISION ledger row(s), not one', v_prov - v_prov0;
  end if;
  select -ducats_delta into v_cost from public.ledger
   where player_id = v_player and kind = 'PROVISION' order by created_at desc, id desc limit 1;
  if v_cost <> v_exp or v_purse0 - v_purse1 <> v_cost then
    raise exception 'PROOF 7 FAILED: the purse moved % and the PROVISION row says %, against supply_need''s %', v_purse0 - v_purse1, v_cost, v_exp;
  end if;
  select v.total_nm into v_nm from public.voyages v where v.fleet_id = v_fleet and v.status = 'SAILING';
  if v_nm is null then
    raise exception 'PROOF 7 FAILED: no voyage is under way after the SAIL';
  end if;
  v_speed := voyage.fleet_speed(v_fleet);
  v_need  := voyage.stores_need_days(v_nm, v_speed);
  v_end   := voyage.endurance_days(v_fleet);
  if v_end < v_need - 0.01 then
    raise exception 'PROOF 7 FAILED: she sailed with % days of stores against a need of %', round(v_end, 2), round(v_need, 2);
  end if;
  if exists (select 1 from public.orders o where o.fleet_id = v_fleet and o.verb = 'PROVISION') then
    raise exception 'PROOF 7 FAILED: a PROVISION order stands in her queue — the stores were not the SAIL''s own';
  end if;
  raise notice 'PASS: SAIL_BUYS_ITS_STORES — empty casks; SAIL LIS -> CAD (% nm at % kn) bought % d. of stores in one PROVISION row, the purse moved by the same; she holds % days against a need of %',
    round(v_nm), round(v_speed, 2), v_cost, round(v_end, 2), round(v_need, 2);

  -- ── 2. THE OLD DOORS ARE SHUT ──────────────────────────────────────────────────────────────────
  set local role authenticated;
  begin
    perform cmd.provision_preset_save(null, 'Not Any More', 7);
    raise exception 'PROOF 7 FAILED: cmd.provision_preset_save answered a client role';
  exception when insufficient_privilege then null;
  end;
  begin
    perform cmd.provision_preset_apply(v_fleet, null);
    raise exception 'PROOF 7 FAILED: cmd.provision_preset_apply answered a client role';
  exception when insufficient_privilege then null;
  end;
  begin
    perform cmd.provision_preset_delete(gen_random_uuid());
    raise exception 'PROOF 7 FAILED: cmd.provision_preset_delete answered a client role';
  exception when insufficient_privilege then null;
  end;
  begin
    perform world.provision_presets();
    raise exception 'PROOF 7 FAILED: world.provision_presets answered a client role';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.supply_need(v_fleet, 3);
    raise exception 'PROOF 7 FAILED: public.supply_need answered a client role';
  exception when insufficient_privilege then null;
  end;
  set local role none;
  if exists (select 1 from public.client_rpc_entry_points() e
              where e.function_name in ('provision_presets', 'provision_preset_save', 'provision_preset_apply', 'provision_preset_delete')) then
    raise exception 'PROOF 7 FAILED: a preset entry point is still in the registry';
  end if;
  raise notice 'PASS: KEEP_DOORS_SHUT — the four preset doors and public.supply_need refuse `authenticated` (42501), and the registry lists none of the four';

  -- ── 3. THE WHOLE TRIP FROM ONE QUEUE ───────────────────────────────────────────────────────────
  -- land her at Cádiz first (warp the voyage; the read is the catch-up)
  for k in 1 .. 12 loop
    exit when (select status from public.fleets where id = v_fleet) <> 'SAILING';
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fleet and status = 'SAILING';
    perform world.fleets();
  end loop;
  if (select port_id from public.fleets where id = v_fleet) <> v_cad then
    raise exception 'PROOF 7 FAILED: she did not make Cádiz';
  end if;
  select count(*) into v_prov0 from public.ledger where player_id = v_player and kind = 'PROVISION';
  if v_prov0 <> v_prov then
    raise exception 'PROOF 7 FAILED: the arrival bought stores (% PROVISION rows, was %)', v_prov0, v_prov;
  end if;
  -- the trip the Trade page queues: BUY here the units that fit beside the leg's stores (the board's own figure,
  -- supplies.units_fit on the sell row — a BUY ALL would leave no room for the casks and the SAIL would refuse
  -- E_ENDURANCE), SAIL, SELL there — all or none
  -- the good she will carry home: the first Cádiz offers in stock, by code — deterministic
  select g.id, g.code into v_good, v_gcode
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_cad and pg.stock > 0 and public.port_offers(v_cad, g.id)
   order by g.code limit 1;
  if v_good is null then
    raise exception 'PROOF 7 FAILED: Cádiz offers no good in stock';
  end if;
  select ducats into v_purse0 from public.players where id = v_player;
  v_res := world.good_board(v_good, v_fleet, null, null);
  select (e->'supplies'->>'units_fit')::numeric into v_fit from jsonb_array_elements(v_res->'sell') e where e->>'port' = 'LIS';
  if v_fit is null or v_fit <= 0 then
    raise exception 'PROOF 7 FAILED: the board''s LIS row serves no units_fit (%)', v_res->'sell';
  end if;
  v_res := cmd.issue_lines(v_fleet, jsonb_build_array(
             jsonb_build_object('text', format('BUY %s %s', v_gcode, trim_scale(v_fit))),
             jsonb_build_object('text', 'SAIL LIS', 'path', proof.course('CAD', 'LIS')),
             jsonb_build_object('text', format('SELL %s ALL', v_gcode))), null);
  if coalesce((v_res->>'ok')::boolean, false) is not true then
    raise exception 'PROOF 7 FAILED: the trip was refused: %', v_res;
  end if;
  select coalesce(sum((s.cargo->>v_gcode)::numeric), 0) into v_units from public.ships s where s.fleet_id = v_fleet;
  if (select status from public.fleets where id = v_fleet) <> 'SAILING' then
    raise exception 'PROOF 7 FAILED: after the BUY the SAIL did not depart (status %): queue % · issue %',
      (select status from public.fleets where id = v_fleet),
      (select jsonb_agg(to_jsonb(o) - 'path' - 'args') from public.orders o where o.fleet_id = v_fleet), v_res;
  end if;
  if v_units <= 0 then
    raise exception 'PROOF 7 FAILED: the BUY left no % aboard', v_gcode;
  end if;
  for k in 1 .. 12 loop
    exit when (select status from public.fleets where id = v_fleet) <> 'SAILING';
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fleet and status = 'SAILING';
    perform world.fleets();
  end loop;
  select coalesce(sum(ducats_delta), 0) into v_sold from public.ledger where player_id = v_player and kind = 'SELL';
  select count(*) into v_rows from public.ledger where player_id = v_player and kind = 'PROVISION';
  if (select port_id from public.fleets where id = v_fleet) <> v_lis or v_sold <= 0 then
    raise exception 'PROOF 7 FAILED: the SELL did not run at Lisbon (sold %)', v_sold;
  end if;
  if exists (select 1 from public.orders o where o.fleet_id = v_fleet and o.status in ('pending', 'active', 'failed')) then
    raise exception 'PROOF 7 FAILED: the queue is not clear after the trip';
  end if;
  -- the SAIL of the trip bought (she arrived at Cádiz with a fraction of the leg's need); the ARRIVAL bought nothing
  if v_rows <> v_prov0 + 1 then
    raise exception 'PROOF 7 FAILED: the trip wrote % PROVISION row(s) beyond the first SAIL''s; exactly one (its own SAIL) was expected', v_rows - v_prov0;
  end if;
  raise notice 'PASS: TRIP_FROM_ONE_QUEUE — BUY % % (the board''s units_fit; % units aboard) / SAIL LIS / SELL ALL from one queue: she sold for % d., the queue is clear, the SAIL bought its stores and the two arrivals bought none',
    v_gcode, trim_scale(v_fit), round(v_units), v_sold;

  -- ── 4. THE DIFFERENCE, AND NOTHING WHEN STOCKED ────────────────────────────────────────────────
  -- stock her deep (the one top-up, as the owner would through PROVISION), then sail: nothing is bought
  perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'DAYS', 'days', 30));
  select count(*) into v_prov0 from public.ledger where player_id = v_player and kind = 'PROVISION';
  v_res := proof.sail(v_fleet, 'CAD');
  if coalesce((v_res->>'ok')::boolean, false) is not true then
    raise exception 'PROOF 7 FAILED: the stocked SAIL was refused: %', v_res;
  end if;
  select count(*) into v_rows from public.ledger where player_id = v_player and kind = 'PROVISION';
  if v_rows <> v_prov0 then
    raise exception 'PROOF 7 FAILED: a stocked fleet bought stores at the SAIL (% new row(s))', v_rows - v_prov0;
  end if;
  raise notice 'PASS: RETURN_BUYS_THE_DIFFERENCE — stocked to 30 days, the SAIL bought nothing (% PROVISION rows before and after: the first SAIL''s, the trip''s SAIL''s and the 30-day top-up''s)',
    v_rows;
end $$;
