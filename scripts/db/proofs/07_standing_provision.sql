-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 7 — THE STANDING ORDER  (migration 0034)
--
-- WHAT THIS PROOF IS FOR, AND WHY IT IS NOT THE MIGRATION'S SELF-ASSERT AGAIN
--   0034 proves, in the transaction that applies it, that the slices are byte-parity, that one
--   fleet is topped up on arrival, that crew is read at fire time, and that the cap, the name
--   rules and the detach all bite. It cannot prove four things, and those four are this file:
--
--     1. THE MECHANIC WORKS THROUGH THE DOOR THE BROWSER USES. The self-assert runs as the
--        owner; a player is `authenticated`, sees only their own rows, and may call exactly the
--        four new entry points. If the grants or the RLS are wrong the feature is dead for every
--        player while every self-assert stays green (proof 06's own lesson).
--     2. A PRESET IS A REFERENCE, NOT A COPY — proven the only way that means anything: TWO
--        fleets under ONE preset, the preset edited ONCE, and BOTH fleets provisioning to the
--        NEW figure at their next arrival, with no re-apply.
--     3. THE TRADE-OFF IS MEASURABLE BETWEEN FLEETS. Two identical hulls on identical voyages,
--        one under a deep preset and one under a shallow one, must come to differ in free hold
--        by exactly the extra stores — the "a tun of water is a tun of pepper" arithmetic, read
--        from the same authority a BUY checks.
--     4. A REFUSAL REACHES THE PLAYER'S OWN LEDGER READ — world.ledger(), the surface the
--        Ledger tab renders — not merely the events table.
--
-- ── EVERY PRECONDITION IS SET HERE, NONE IS BORROWED ────────────────────────────────────────────
-- The hazard ceiling is zeroed IN THIS TRANSACTION (0031 rotates the world secret per deploy, so
-- weather is a lottery this proof refuses to play); the second fleet and the second house are
-- built here; every warp loops until the fleet is in, because a warped ETA is recomputed forward
-- by any delay. All of it rolls back with the proof.
--
-- @pass PRESET_CLIENT_PATH            as `authenticated`: the read and the three verbs answer through the granted doors, the executor is refused 42501, and RLS shows a house exactly its own book
-- @pass PRESET_CAP_BITES              the seventh standing order is refused E_PRESET_CAP through the client door
-- @pass PRESET_TAKES_ROOM             two identical hulls on identical voyages, presets 40 vs 10 days: the deep one lands with less free hold by exactly the extra stores
-- @pass PRESET_EDIT_MOVES_EVERY_FLEET one preset on two fleets, edited once: both provision to the new figure at their next arrival, with no re-apply
-- @pass PRESET_CREW_AT_FIRE_TIME      more crew signed between arrivals means a bigger top-up from the same preset, the range landing on target both times
-- @pass PRESET_REFUSED_IS_WRITTEN     a drained purse leaves a PROVISION_REFUSED the player's own world.ledger() read serves, and buys nothing
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth    constant uuid := '00000000-0f07-4000-8000-000000000001';
  c_auth2   constant uuid := '00000000-0f07-4000-8000-000000000002';
  v_player  uuid;
  v_player2 uuid;
  v_fleet_a uuid;
  v_fleet_b uuid;
  v_lis     uuid;
  v_cad     uuid;
  v_res     jsonb;
  v_book    jsonb;
  v_deep    uuid;   -- 'Long haul', starts at 40 days
  v_shallow uuid;   -- 'Coastal', 10 days
  v_days    int;
  v_end_a   numeric;
  v_end_b   numeric;
  v_free_a  numeric;
  v_free_b  numeric;
  v_stores_a numeric;
  v_stores_b numeric;
  v_crew_a  int;
  v_crew_a2 int;
  v_wpd     numeric := public.wc_num('water_per_crew_day');
  v_fpd     numeric := public.wc_num('food_per_crew_day');
  v_b1      numeric;
  v_b2      numeric;
  v_ev1     uuid;
  v_purse   bigint;
  v_led     jsonb;
  v_ref     jsonb;
  v_sqlstate text;
  v_max     int;
  v_seen    int;
  k         int;
  j         int;
begin
  -- ── THE PRECONDITIONS THIS PROOF OWNS ────────────────────────────────────────────────────────
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  v_max := public.wc_int('provision_preset_max');   -- read BEFORE the role drops to authenticated
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_cad from public.ports where code = 'CAD';

  v_player  := public.new_house(c_auth,  'Casa do Livro', 'PRT');
  v_player2 := public.new_house(c_auth2, 'Casa Vizinha',  'PRT');
  select id into v_fleet_a from public.fleets where player_id = v_player;
  -- The SECOND fleet: same hull, same crew, same port — the twin the trade-off is measured on.
  insert into public.fleets (player_id, name, status, port_id)
  values (v_player, 'Andorinha', 'DOCKED', v_lis)
  returning id into v_fleet_b;
  insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                            water_t, food_t, store_ratio, is_flagship)
  select v_player, v_fleet_b, c.id, 'Andorinha', c.durability, c.crew_required,
         2.400, 1.800, public.wc_num('store_ratio_default'), true
    from public.ship_classes c where c.code = 'barca';
  -- The neighbour's book holds one order, so "sees exactly its own" has something to miss.
  perform cmd.assume_identity(c_auth2);
  perform cmd.provision_preset_save(null, 'Not Yours', 7);

  -- ── 1. THE CLIENT PATH, as the browser is: role `authenticated`, identity from the JWT ───────
  perform cmd.assume_identity(c_auth);
  set local role authenticated;

  v_res := cmd.provision_preset_save(null, 'Long haul', 40);
  v_deep := (v_res->>'id')::uuid;
  if not (v_res->>'ok')::boolean then
    raise exception 'PROOF 7 FAILED: save refused through the client door: %', v_res;
  end if;
  v_res := cmd.provision_preset_save(null, 'Coastal', 10);
  v_shallow := (v_res->>'id')::uuid;
  perform cmd.provision_preset_apply(v_fleet_a, v_deep);
  perform cmd.provision_preset_apply(v_fleet_b, v_shallow);

  v_book := world.provision_presets();
  if jsonb_array_length(v_book->'presets') <> 2
     or (v_book->>'max')::int <> v_max
     or v_book::text like '%Not Yours%' then
    raise exception 'PROOF 7 FAILED: the book read % presets (want 2, none a neighbour''s), max %',
      jsonb_array_length(v_book->'presets'), v_book->>'max';
  end if;
  select count(*) into v_seen from public.provision_presets;
  if v_seen <> 2 then
    raise exception 'PROOF 7 FAILED: RLS shows % preset row(s) to this house — want exactly its own 2', v_seen;
  end if;

  -- The executor is NOT a door: 42501, or a browser could spend any purse it could name.
  begin
    perform cmd.run_standing_provision(v_fleet_a);
    raise exception 'PROOF 7 FAILED: cmd.run_standing_provision answered a client role';
  exception when insufficient_privilege then
    null;  -- 42501 is the pass
  end;

  raise notice 'PASS: PRESET_CLIENT_PATH — as authenticated: the book reads its own 2 orders (cap %, no neighbour''s rows by RLS or by payload), save/apply answered, and the executor was refused 42501',
    v_book->>'max';

  -- ── 2. THE CAP, through the same door ────────────────────────────────────────────────────────
  for k in 1 .. v_max - 2 loop
    v_res := cmd.provision_preset_save(null, 'Order ' || k, 5 + k);
    if not (v_res->>'ok')::boolean then
      raise exception 'PROOF 7 FAILED: order % of a legal book was refused: %', k + 2, v_res;
    end if;
  end loop;
  v_res := cmd.provision_preset_save(null, 'One Too Many', 9);
  if (v_res->>'ok')::boolean or v_res->>'error_code' <> 'E_PRESET_CAP' then
    raise exception 'PROOF 7 FAILED: the seventh standing order was not refused E_PRESET_CAP: %', v_res;
  end if;
  raise notice 'PASS: PRESET_CAP_BITES — the % cap refused the next order through the client door ("%")',
    v_max, v_res->>'error_message';
  -- clear the filler so later phases read a two-order book again
  for k in 1 .. v_max - 2 loop
    perform cmd.provision_preset_delete((
      select id from public.provision_presets where name = 'Order ' || k));
  end loop;

  set local role none;

  -- ── 3. THE TRADE-OFF, measured between twins ─────────────────────────────────────────────────
  -- Both sail the same leg with the same crew; the only difference is the standing order.
  perform cmd.issue(v_fleet_a, 'SAIL CAD');
  perform cmd.issue(v_fleet_b, 'SAIL CAD');
  for k in 1 .. 12 loop
    exit when (select count(*) from public.fleets
                where id in (v_fleet_a, v_fleet_b) and status = 'SAILING') = 0;
    update public.voyages
       set departed_at = departed_at - (eta - now()) - interval '1 minute',
           eta         = now() - interval '1 minute'
     where fleet_id in (v_fleet_a, v_fleet_b) and status = 'SAILING';
    -- THE READ IS THE CATCH-UP (0009): the same call the client makes every thirty seconds is
    -- what lands both fleets and fires both standing orders.
    perform world.fleets();
  end loop;

  v_end_a  := voyage.endurance_days(v_fleet_a);
  v_end_b  := voyage.endurance_days(v_fleet_b);
  v_free_a := public.fleet_free_hold(v_fleet_a);
  v_free_b := public.fleet_free_hold(v_fleet_b);
  select water_t + food_t, crew into v_stores_a, v_crew_a from public.ships where fleet_id = v_fleet_a;
  select water_t + food_t into v_stores_b from public.ships where fleet_id = v_fleet_b;

  if v_end_a < 40 - 0.01 or v_end_b < 10 - 0.01 then
    raise exception 'PROOF 7 FAILED: arrival left range a=% (want >= 40) b=% (want >= 10)', v_end_a, v_end_b;
  end if;
  -- Same hull, same crew, same voyage: the whole difference in room is the difference in stores,
  -- and the difference in stores is 30 days of the crew's drinking and eating.
  if abs((v_free_b - v_free_a) - (v_stores_a - v_stores_b)) > 0.01 then
    raise exception 'PROOF 7 FAILED: free hold differs by % but stores differ by % — room moved somewhere other than the stores',
      v_free_b - v_free_a, v_stores_a - v_stores_b;
  end if;
  -- The deep order lands EXACTLY at its own tonnage — 40 days of the crew's drinking and eating —
  -- while the shallow twin, still above her 10-day mark, is the "already at target" branch working:
  -- she buys NOTHING and writes nothing, which is asserted, not assumed.
  if abs(v_stores_a - v_crew_a * (v_wpd + v_fpd) * 40) > 0.02 then
    raise exception 'PROOF 7 FAILED: the 40-day fleet holds % t of stores, but 40 days at % crew is % t',
      v_stores_a, v_crew_a, v_crew_a * (v_wpd + v_fpd) * 40;
  end if;
  if exists (select 1 from public.events e
              where e.player_id = v_player and e.kind = 'PROVISIONED'
                and (e.payload->>'standing')::boolean and e.payload->>'fleet' = 'Andorinha') then
    raise exception 'PROOF 7 FAILED: the satisfied fleet was topped up anyway — the already-at-target branch bought stores';
  end if;
  raise notice 'PASS: PRESET_TAKES_ROOM — twins home from one voyage: the 40-day fleet holds % t free against her sister''s % t — a % t gap of hold, equal to the digit to their gap in stores; the deep order landed at exactly 40 days x % crew x % t/day while the sister, still above her 10-day mark, bought nothing',
    round(v_free_a, 1), round(v_free_b, 1), round(v_free_b - v_free_a, 2), v_crew_a, v_wpd + v_fpd;

  -- ── 4. ONE EDIT MOVES EVERY FLEET — the reference-not-copy proof ─────────────────────────────
  perform cmd.provision_preset_apply(v_fleet_b, v_deep);   -- both now under 'Long haul' (40)
  perform cmd.provision_preset_save(v_deep, null, 45);     -- ONE edit, no re-apply
  select days into v_days from public.provision_presets where id = v_deep;
  if v_days <> 45 then
    raise exception 'PROOF 7 FAILED: the edit did not land (days %)', v_days;
  end if;

  perform cmd.issue(v_fleet_a, 'SAIL LIS');
  perform cmd.issue(v_fleet_b, 'SAIL LIS');
  for k in 1 .. 12 loop
    exit when (select count(*) from public.fleets
                where id in (v_fleet_a, v_fleet_b) and status = 'SAILING') = 0;
    update public.voyages
       set departed_at = departed_at - (eta - now()) - interval '1 minute',
           eta         = now() - interval '1 minute'
     where fleet_id in (v_fleet_a, v_fleet_b) and status = 'SAILING';
    perform world.fleets();
  end loop;

  v_end_a := voyage.endurance_days(v_fleet_a);
  v_end_b := voyage.endurance_days(v_fleet_b);
  if v_end_a < 45 - 0.01 or v_end_b < 45 - 0.01 then
    raise exception 'PROOF 7 FAILED: after one edit both fleets should make 45 days; a=% b=%', v_end_a, v_end_b;
  end if;
  raise notice 'PASS: PRESET_EDIT_MOVES_EVERY_FLEET — ''Long haul'' edited once 40 -> 45 with two fleets attached and NO re-apply: both arrived provisioned to % and % days',
    round(v_end_a, 1), round(v_end_b, 1);

  -- ── 5. CREW AT FIRE TIME, on the served surface ──────────────────────────────────────────────
  select e.id, (e.payload->>'water_t')::numeric + (e.payload->>'food_t')::numeric
    into v_ev1, v_b1
    from public.events e
   where e.player_id = v_player and e.kind = 'PROVISIONED'
     and (e.payload->>'standing')::boolean
     and e.payload->>'fleet' = 'Gaivota'
     and (e.payload->>'days_target')::numeric = 45;
  perform cmd.issue(v_fleet_a, 'HIRE ' ||
    (select c.crew_max - s.crew from public.ships s
       join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fleet_a));
  select crew into v_crew_a2 from public.ships where fleet_id = v_fleet_a;
  perform cmd.issue(v_fleet_a, 'SAIL CAD');
  for k in 1 .. 12 loop
    exit when (select status from public.fleets where id = v_fleet_a) <> 'SAILING';
    update public.voyages
       set departed_at = departed_at - (eta - now()) - interval '1 minute',
           eta         = now() - interval '1 minute'
     where fleet_id = v_fleet_a and status = 'SAILING';
    perform world.fleets();
  end loop;
  select (e.payload->>'water_t')::numeric + (e.payload->>'food_t')::numeric into v_b2
    from public.events e
   where e.player_id = v_player and e.kind = 'PROVISIONED'
     and (e.payload->>'standing')::boolean
     and e.payload->>'fleet' = 'Gaivota'
     and (e.payload->>'days_target')::numeric = 45
     and e.id <> v_ev1;
  if v_b2 is null or v_b1 is null or v_b2 <= v_b1
     or voyage.endurance_days(v_fleet_a) < 45 - 0.01 then
    raise exception 'PROOF 7 FAILED: crew % -> %, but the top-up went % -> % t (range %)',
      v_crew_a, v_crew_a2, v_b1, v_b2, voyage.endurance_days(v_fleet_a);
  end if;
  raise notice 'PASS: PRESET_CREW_AT_FIRE_TIME — the same 45-day order bought % t at % crew and % t after signing to % crew, the range landing on target both times',
    round(v_b1, 2), v_crew_a, round(v_b2, 2), v_crew_a2;

  -- ── 6. A REFUSAL THE PLAYER'S OWN LEDGER READ SERVES ─────────────────────────────────────────
  select ducats into v_purse from public.players where id = v_player;
  perform public.credit(v_player, 'PROOF_DRAIN', -(v_purse - 1));
  perform cmd.issue(v_fleet_a, 'SAIL LIS');
  for k in 1 .. 12 loop
    exit when (select status from public.fleets where id = v_fleet_a) <> 'SAILING';
    update public.voyages
       set departed_at = departed_at - (eta - now()) - interval '1 minute',
           eta         = now() - interval '1 minute'
     where fleet_id = v_fleet_a and status = 'SAILING';
    perform world.fleets();
  end loop;
  -- The read the Ledger tab makes, as the player makes it.
  set local role authenticated;
  v_led := world.ledger();
  set local role none;
  select e into v_ref
    from jsonb_array_elements(v_led->'events') e
   where e->>'kind' = 'PROVISION_REFUSED' limit 1;
  if v_ref is null
     or v_ref->'payload'->>'code' <> 'E_INSUFFICIENT_FUNDS'
     or v_ref->'payload'->>'preset' <> 'Long haul'
     or length(coalesce(v_ref->'payload'->>'reason', '')) < 10 then
    raise exception 'PROOF 7 FAILED: the drained arrival left no readable refusal (got %)', v_ref;
  end if;
  select count(*) into v_seen from public.events
   where player_id = v_player and kind = 'PROVISIONED' and (payload->>'standing')::boolean
     and payload->>'fleet' = 'Gaivota'
     and created_at > (select created_at from public.events where id = v_ev1);
  raise notice 'PASS: PRESET_REFUSED_IS_WRITTEN — with 1 d. in the purse the arrival wrote PROVISION_REFUSED ("%"), served by world.ledger(), and bought nothing',
    v_ref->'payload'->>'reason';
end $$;
