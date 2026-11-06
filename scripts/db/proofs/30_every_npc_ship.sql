-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 30 — EVERY NPC SHIP HAS AN ORIGIN  (migration 0322, owner row 287, W6 of docs/WORLD_POWERS.md)
--
--   0322's self-assert reads the catalog only (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof lights the switch and sails real merchants and a real
--   cargo ship through the REAL voyage.settle, tend, cargo step and hourly job. The sea's roll is stubbed on one setting, so the day that takes the hull is asked for by name. The economy is
--   CLOSED here, as on prod: a kind that mints would be refused.
--
-- @pass NPC_ORIGIN_READER  every NPC fleet of the world has an origin, a cargo ship reads hers, a human's is null, and an empty fleet is never a wreck
-- @pass NPC_DARK           dark: a hull at 0 on a storm day sails on, docks unable, is towed; the step and the job touch nothing
-- @pass NPC_WRECK_DAY      lit: STORM, PIRATES and SHOAL_WATER each end the voyage at her origin: hold gone, queue released, UNABLE_TO_SAIL, RESPAWNED, every purse summed moves 0
-- @pass NPC_WRECK_INSURED  an insured hold pays through the one claim, cause WRECK, moved
-- @pass NPC_NOT_A_WRECK    a calm day takes nothing, a merchant with a hull left is towed as today, a human is left alone
-- @pass NPC_CARGO_RETURNS  a cargo ship's funds go back to the origin; book closed, purses and funds summed move 0, the fold finds no drift
-- @pass NPC_CARGO_WAITS    a wreck is not patched by her own step and crown aid cannot load her
-- @pass NPC_BROKE_WAITS    a city under cost and reserve waits: no flow, no hull; REFIT_WAITING once a day; asked again it pays
-- @pass NPC_PAYS_ONCE      paid: origin less, yard more, moved, hull whole, crew from the quay, ready after the wait; a second run pays nothing
-- @pass NPC_YARD           the yard is not the origin, its own country first; no yard, she waits
-- @pass NPC_REJOINS        a refitted merchant comes back through her tend and sails; a refitted cargo ship closes her lap, loads and sails after the wait
-- @pass NPC_STRAY          a wreck no settled day brought home (docked unable or docked abroad) is found by the job and brought home
-- @pass NPC_SWITCH_OFF     the switch off mid-wait strands nobody: the tow and the patch take them back
-- @pass NPC_TOW_PARITY     public.yards_from answers public.tow_for's old query, port by port
-- @pass NPC_RANSOM         the ransom share is a reader only: it moves no gold, and public.loot_due (0327) alone reads it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled', 'combat_bite');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;

  -- THE SEA ON ONE SETTING: set byeharu.proof_sea to a kind and every day is that day; empty, every day is quiet.
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_30;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$
  select coalesce(current_setting('byeharu.proof_sea', true), '') <> '', nullif(current_setting('byeharu.proof_sea', true), ''), 0.5::numeric, 1::numeric
$b$
  $f$;

  -- every purse of the world, summed: cities, companies, funds aboard
  execute $f$
create function pg_temp.purses()
returns bigint
language sql
as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint
       + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;

  -- a merchant at sea, Lisbon to Funchal, her home neither. p_skip: how many merchants down the list.
  execute $f$
create function pg_temp.merchant_at_sea(p_skip int, p_insured boolean default false)
returns uuid
language plpgsql
as $b$
declare
  v_lis uuid := (select id from public.ports where code = 'LIS');
  v_fnc uuid := (select id from public.ports where code = 'FNC');
  v_f   uuid;
  v_g   text := (select code from public.goods where bulk = 1 order by code limit 1);
  v_voy uuid;
begin
  select nf.fleet_id into v_f
    from public.npc_fleets nf
    join public.fleets f on f.id = nf.fleet_id
   where public.fleet_origin(nf.fleet_id) not in (v_lis, v_fnc)
     and (select count(*) from public.ships s where s.fleet_id = nf.fleet_id) = 1
   order by nf.roster_ord offset p_skip limit 1;
  update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, ready_at = null where id = v_f;
  update public.ships s set crew = c.crew_required, water_t = 40, food_t = 40, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb
    from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_f;
  if public.fleet_load(v_f, v_g, 10, 100) <> 10 then
    raise exception 'PROOF 30 FAIL: the probe''s cargo did not load';
  end if;
  v_voy := (cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'insured', p_insured,
             'path', (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                        from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc)))->>'voyage_id')::uuid;
  if v_voy is null or (select f.status from public.fleets f where f.id = v_f) <> 'SAILING' then
    raise exception 'PROOF 30 FAIL: the probe merchant did not sail';
  end if;
  return v_f;
end
$b$
  $f$;
  execute $f$
create function pg_temp.voyage_of(p_fleet uuid)
returns uuid
language sql
as $b$ select o.id from public.voyages o where o.fleet_id = p_fleet order by o.departed_at desc limit 1 $b$
  $f$;
end
$$;

-- ── THE READER ──
do $$
declare
  v_f uuid;
  v_h uuid;
  v_home uuid;
begin
  if exists (select 1 from public.fleets f join public.players p on p.id = f.player_id where p.is_npc and public.fleet_origin(f.id) is null) then
    raise exception 'PROOF 30 FAIL: an NPC fleet has no origin';
  end if;
  v_f := (select nf.fleet_id from public.npc_fleets nf order by nf.roster_ord limit 1);
  if public.fleet_origin(v_f) is distinct from (select h.home_port_id from public.fleets f join public.npc_houses h on h.player_id = f.player_id where f.id = v_f) then
    raise exception 'PROOF 30 FAIL: a merchant does not read her house';
  end if;
  v_h := public.new_house(gen_random_uuid(), 'Casa Origem 30', 'PRT', 'LIS', 'Origem 30', 'barca', 'Origem 30', null);
  v_f := (select f.id from public.fleets f where f.player_id = v_h);
  if public.fleet_origin(v_f) is not null then
    raise exception 'PROOF 30 FAIL: a human''s fleet has an origin';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'npc_refits_enabled';
  update public.ships s set durability = 0 where s.fleet_id = v_f;
  if public.npc_wrecked(v_f) then
    raise exception 'PROOF 30 FAIL: a human is a wreck by this rule';
  end if;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_f;
  v_f := (select nf.fleet_id from public.npc_fleets nf order by nf.roster_ord limit 1);
  if public.npc_wrecked(v_f) then
    raise exception 'PROOF 30 FAIL: a whole merchant is a wreck';
  end if;
  -- no hull at all is not "every hull at 0"
  v_home := gen_random_uuid();
  perform set_config('byeharu.proof_30_nobody', v_home::text, true);
  if public.npc_wrecked(v_home) then
    raise exception 'PROOF 30 FAIL: a fleet with no hull is a wreck';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  raise notice 'PASS: NPC_ORIGIN_READER — % NPC fleets, each with an origin; a human has none', (select count(*) from public.fleets f join public.players p on p.id = f.player_id where p.is_npc);
end
$$;

-- ── DARK: today, untouched ──
do $$
declare
  v_f    uuid := pg_temp.merchant_at_sea(0);
  v_v    uuid := pg_temp.voyage_of(v_f);
  v_home uuid := public.fleet_origin(v_f);
  v_flow bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_r    jsonb;
  v_rt   uuid := (select nf.route_id from public.npc_fleets nf where nf.fleet_id = v_f);
  v_pl   uuid := (select f.player_id from public.fleets f where f.id = v_f);
begin
  update public.ships s set durability = 0 where s.fleet_id = v_f;
  perform set_config('byeharu.proof_sea', 'STORM', true);
  perform voyage.settle(v_f, voyage.day_ends_at(v_v, 1));
  perform set_config('byeharu.proof_sea', '', true);
  if (select f.status from public.fleets f where f.id = v_f) <> 'SAILING' or (select o.status from public.voyages o where o.id = v_v) <> 'SAILING' then
    raise exception 'PROOF 30 FAIL: dark, a wreck did not sail on: %', (select f.status from public.fleets f where f.id = v_f);
  end if;
  perform voyage.settle(v_f, (select o.eta from public.voyages o where o.id = v_v) + interval '1 second');
  if (select f.status from public.fleets f where f.id = v_f) <> 'UNABLE_TO_SAIL' or (select f.port_id from public.fleets f where f.id = v_f) <> (select id from public.ports where code = 'FNC') then
    raise exception 'PROOF 30 FAIL: dark, she did not dock unable where she was bound';
  end if;
  if public.npc_refit_step(v_f) <> 'NOT_A_WRECK' then
    raise exception 'PROOF 30 FAIL: dark, the step took her';
  end if;
  call public.tick_npc_refits(false);
  if exists (select 1 from public.treasury_flows t where t.id > v_flow and t.kind = 'REFIT') or exists (select 1 from public.events e where e.player_id = v_pl and e.kind in ('RESPAWNED', 'REFIT_WAITING', 'REFITTED')) then
    raise exception 'PROOF 30 FAIL: dark, the wreck rule wrote something';
  end if;
  update public.players p set ducats = 5000000 where p.id = v_pl;
  v_r := public.npc_tend_route(now(), v_f, v_rt, 1);
  if (select f.status from public.fleets f where f.id = v_f) = 'UNABLE_TO_SAIL' then
    raise exception 'PROOF 30 FAIL: dark, the tow arm did not take her: %', v_r;
  end if;
  raise notice 'PASS: NPC_DARK — sailed on with no hull, docked unable at Funchal, towed by the tend; no REFIT, no event';
end
$$;

-- ── LIT: THE DAY THAT TAKES THE LAST OF HER ──
do $$
declare
  k      text;
  v_i    int := 1;
  v_f    uuid;
  v_v    uuid;
  v_home uuid;
  v_sum  bigint;
  v_pl   uuid;
  v_e    jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key = 'npc_refits_enabled';
  foreach k in array array['STORM', 'PIRATES', 'SHOAL_WATER'] loop
    v_f := pg_temp.merchant_at_sea(v_i);
    v_v := pg_temp.voyage_of(v_f);
    v_home := public.fleet_origin(v_f);
    v_pl := (select f.player_id from public.fleets f where f.id = v_f);
    update public.ships s set durability = 0 where s.fleet_id = v_f;
    -- a queued order, written for the voyage's end: it must not run at home
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args) values (v_f, v_pl, 99999, 'REPAIR', 'REPAIR', '{}'::jsonb);
    v_sum := pg_temp.purses();
    perform set_config('byeharu.proof_sea', k, true);
    perform voyage.settle(v_f, voyage.day_ends_at(v_v, 1));
    perform set_config('byeharu.proof_sea', '', true);
    if (select f.status from public.fleets f where f.id = v_f) <> 'UNABLE_TO_SAIL'
       or (select f.port_id from public.fleets f where f.id = v_f) is distinct from v_home
       or (select f.lat from public.fleets f where f.id = v_f) is not null then
      raise exception 'PROOF 30 FAIL: % did not put her at her origin: %', k, (select to_jsonb(f) from public.fleets f where f.id = v_f);
    end if;
    if (select o.status from public.voyages o where o.id = v_v) <> 'ABORTED' then
      raise exception 'PROOF 30 FAIL: % left her voyage open', k;
    end if;
    if exists (select 1 from public.ships s where s.fleet_id = v_f and s.cargo <> '{}'::jsonb) then
      raise exception 'PROOF 30 FAIL: % left goods in her hold', k;
    end if;
    if exists (select 1 from public.orders o where o.fleet_id = v_f and o.status in ('pending', 'failed')) then
      raise exception 'PROOF 30 FAIL: % left a queue', k;
    end if;
    select e.payload into v_e from public.events e where e.player_id = v_pl and e.kind = 'RESPAWNED' order by e.created_at desc limit 1;
    if v_e is null or v_e ->> 'port' <> (select p.code from public.ports p where p.id = v_home) or (v_e #>> '{cargo_lost}') is null or v_e ->> 'voyage_id' <> v_v::text then
      raise exception 'PROOF 30 FAIL: % wrote no true RESPAWNED: %', k, v_e;
    end if;
    if pg_temp.purses() <> v_sum then
      raise exception 'PROOF 30 FAIL: % moved the sum of purses by %', k, pg_temp.purses() - v_sum;
    end if;
    if not exists (select 1 from jsonb_array_elements(world.sea_roster() -> 'fleets') x where x ->> 'id' = v_f::text and x ->> 'status' = 'UNABLE_TO_SAIL' and jsonb_typeof(x -> 'voyage') = 'null' and jsonb_typeof(x -> 'anchor') = 'null') then
      raise exception 'PROOF 30 FAIL: the map still has her at sea: %', (select x from jsonb_array_elements(world.sea_roster() -> 'fleets') x where x ->> 'id' = v_f::text);
    end if;
    v_i := v_i + 1;
  end loop;
  raise notice 'PASS: NPC_WRECK_DAY — STORM, PIRATES, SHOAL_WATER: at her origin, hold gone, queue gone, RESPAWNED, sum of purses moved 0';
end
$$;

do $$
declare
  v_f   uuid := pg_temp.merchant_at_sea(4, true);
  v_v   uuid := pg_temp.voyage_of(v_f);
  v_sum bigint := pg_temp.purses();
  v_pl  uuid := (select f.player_id from public.fleets f where f.id = v_f);
  v_e   jsonb;
begin
  if not exists (select 1 from public.insured_voyages i where i.voyage_id = v_v) then
    raise exception 'PROOF 30 FAIL: the probe is not insured';
  end if;
  update public.ships s set durability = 0 where s.fleet_id = v_f;
  v_sum := pg_temp.purses();
  perform set_config('byeharu.proof_sea', 'STORM', true);
  perform voyage.settle(v_f, voyage.day_ends_at(v_v, 1));
  perform set_config('byeharu.proof_sea', '', true);
  select e.payload into v_e from public.events e where e.player_id = v_pl and e.kind = 'INSURANCE_PAID' order by e.created_at desc limit 1;
  if v_e is null or v_e ->> 'cause' <> 'WRECK' or (v_e ->> 'paid')::bigint <= 0 then
    raise exception 'PROOF 30 FAIL: the claim is not the wreck''s: %', v_e;
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 30 FAIL: the claim moved the sum by %', pg_temp.purses() - v_sum;
  end if;
  raise notice 'PASS: NPC_WRECK_INSURED — % d. paid, cause WRECK, sum of purses moved 0', v_e ->> 'paid';
end
$$;

-- ── WHAT IS NOT A WRECK ──
do $$
declare
  v_f    uuid := pg_temp.merchant_at_sea(5);
  v_v    uuid := pg_temp.voyage_of(v_f);
  v_h    uuid;
  v_hf   uuid;
  v_hv   uuid;
  v_fl2  uuid;
  r      record;
  v_res  jsonb;
begin
  -- a calm day cannot take a hull, so it is not asked
  update public.ships s set durability = 0 where s.fleet_id = v_f;
  perform set_config('byeharu.proof_sea', 'CALM', true);
  perform voyage.settle(v_f, voyage.day_ends_at(v_v, 1));
  perform set_config('byeharu.proof_sea', '', true);
  if (select f.status from public.fleets f where f.id = v_f) <> 'SAILING' then
    raise exception 'PROOF 30 FAIL: a calm day wrecked her';
  end if;
  -- a merchant with a flagship at 0 and a hull left: unable, not a wreck, and the tow still takes her
  select nf.fleet_id, nf.route_id, f.player_id, h.id as flag into r
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
    join public.ships h on h.fleet_id = f.id and h.is_flagship
   where (select count(*) from public.ships s where s.fleet_id = f.id) >= 2 and f.status = 'DOCKED'
   order by nf.roster_ord limit 1;
  if r.fleet_id is null then
    raise exception 'PROOF 30 FAIL: no merchant of two hulls in this world';
  end if;
  update public.ships s set durability = 0 where s.id = r.flag;
  update public.fleets f set status = 'UNABLE_TO_SAIL' where f.id = r.fleet_id;
  update public.players p set ducats = 5000000 where p.id = r.player_id;
  if public.npc_wrecked(r.fleet_id) then
    raise exception 'PROOF 30 FAIL: a hull left and still a wreck';
  end if;
  if public.npc_refit_step(r.fleet_id) <> 'NOT_A_WRECK' then
    raise exception 'PROOF 30 FAIL: the refit took a fleet with a hull left';
  end if;
  v_res := public.npc_tend_route(now(), r.fleet_id, r.route_id, 1);
  if (select f.status from public.fleets f where f.id = r.fleet_id) = 'UNABLE_TO_SAIL' then
    raise exception 'PROOF 30 FAIL: lit, the tow left a fleet with a hull left: %', v_res;
  end if;
  raise notice 'PASS: NPC_NOT_A_WRECK — a calm day sailed on; a flagship down with a hull left was towed; a human never counts';
end
$$;

-- ── A CARGO SHIP ──
do $$
declare
  v_nat  uuid;
  v_cap  uuid;
  v_fl   uuid;
  v_pl   uuid;
  v_v    uuid;
  v_load bigint;
  v_sum  bigint;
  v_tot0 bigint;
  v_mark bigint;
  v_r    jsonb;
  v_step text;
  v_n    int;
begin
  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = 'PRT';
  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
  update public.cargo_fleet_sizes set ships = 5, read_at = now();   -- 0326 re-cut: a country's number by hand; proof 35 proves the number
  update public.world_config set value = to_jsonb(1) where key = 'convoy_idle_every';
  for v_n in 1 .. 3 loop
    perform public.tick_cargo_ships(now(), v_nat);
  end loop;
  v_fl := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1);
  v_pl := (select c.player_id from public.cargo_ships c where c.fleet_id = v_fl);
  if public.fleet_origin(v_fl) is distinct from v_cap then
    raise exception 'PROOF 30 FAIL: a cargo ship does not read her own home';
  end if;
  perform public.stats_live_fold(now());
  v_tot0 := (world.stats_now() ->> 'total')::bigint;
  v_load := public.convoy_book('LOADED', v_fl, v_pl, v_cap, 40000);
  v_step := public.cargo_ship_step(v_fl, now());
  if v_step <> 'SAILED' then
    raise exception 'PROOF 30 FAIL: the loaded ship did not sail: %', v_step;
  end if;
  v_v := pg_temp.voyage_of(v_fl);
  update public.ships s set durability = 0 where s.fleet_id = v_fl;
  v_sum := pg_temp.purses();
  perform set_config('byeharu.proof_sea', 'STORM', true);
  perform voyage.settle(v_fl, voyage.day_ends_at(v_v, 1));
  perform set_config('byeharu.proof_sea', '', true);
  if (select f.status from public.fleets f where f.id = v_fl) <> 'UNABLE_TO_SAIL' or (select f.port_id from public.fleets f where f.id = v_fl) <> v_cap then
    raise exception 'PROOF 30 FAIL: a cargo ship did not lie at her origin';
  end if;
  if exists (select 1 from public.cargo_ship_aboard(v_fl))
     or (select count(*) from public.convoy_cargo k where k.load_id = v_load and k.stage = 'RETURNED' and k.ducats = 40000 and k.port_id = v_cap) <> 1 then
    raise exception 'PROOF 30 FAIL: her book did not close at home';
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 30 FAIL: her funds moved the sum by %', pg_temp.purses() - v_sum;
  end if;
  if (world.stats_now() ->> 'total')::bigint <> v_tot0 then
    raise exception 'PROOF 30 FAIL: the live world total moved by %', (world.stats_now() ->> 'total')::bigint - v_tot0;
  end if;
  v_r := public.stats_live_fold(now());
  if (v_r #>> '{drift,cities}')::bigint <> 0 or (v_r #>> '{drift,set_aside}')::bigint <> 0 then
    raise exception 'PROOF 30 FAIL: the fold found a drift after a wreck: %', v_r;
  end if;
  raise notice 'PASS: NPC_CARGO_RETURNS — 40,000 d. RETURNED at her origin, sum of purses and funds moved 0, world total moved 0, no drift';

  -- her own step leaves her; crown aid passes her over (she is ord 1, the first it would take)
  v_step := public.cargo_ship_step(v_fl, now());
  if v_step <> 'WRECK' or (select f.status from public.fleets f where f.id = v_fl) <> 'UNABLE_TO_SAIL'
     or exists (select 1 from public.ships s where s.fleet_id = v_fl and s.durability > 0) then
    raise exception 'PROOF 30 FAIL: a wreck patched herself: %', v_step;
  end if;
  v_mark := coalesce((select max(k.id) from public.convoy_cargo k), 0);
  v_r := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap order by p.code limit 1),
                                                                      'target', 99000000, 'cap', v_cap)));
  if exists (select 1 from public.convoy_cargo k where k.id > v_mark and k.fleet_id = v_fl) then
    raise exception 'PROOF 30 FAIL: crown aid loaded a wreck';
  end if;
  raise notice 'PASS: NPC_CARGO_WAITS — her step answers WRECK, no hull restored; crown aid loaded %, not her', v_r;
  perform set_config('byeharu.proof_cargo', v_fl::text, true);
end
$$;

-- ── A BROKE CITY, THEN PAID, ONCE ──
do $$
declare
  v_f    uuid := (select e.fleet from (select nf.fleet_id as fleet, nf.roster_ord from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.status = 'UNABLE_TO_SAIL' and public.npc_wrecked(nf.fleet_id) order by nf.roster_ord limit 1) e);
  v_home uuid := public.fleet_origin(v_f);
  v_pl   uuid := (select f.player_id from public.fleets f where f.id = v_f);
  v_cost bigint := public.npc_refit_cost(v_f);
  v_yard uuid := public.refit_yard(v_home);
  v_flow bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_now  timestamptz := now();
  v_sum  bigint;
  v_b    bigint;
  v_y    bigint;
  v_pool int;
  v_crew int;
  v_short int;
  v_hands int;
  v_s    text;
begin
  if v_f is null or v_cost <= 0 or v_yard is null then
    raise exception 'PROOF 30 FAIL: no wreck to refit: fleet %, cost %, yard %', v_f, v_cost, v_yard;
  end if;
  -- the other wrecks of this proof are paid for first, and the cargo ship's capital is empty until NPC_REJOINS, so the flows below are this one wreck's
  update public.port_treasury t set ducats = 0 where t.port_id = public.fleet_origin(current_setting('byeharu.proof_cargo')::uuid);
  perform public.npc_refit_step(nf.fleet_id, v_now) from public.npc_fleets nf where nf.fleet_id <> v_f and public.npc_wrecked(nf.fleet_id);
  v_flow := coalesce((select max(id) from public.treasury_flows), 0);
  -- short by one ducat of cost + reserve: she has the cost, not the cost and the reserve
  update public.port_treasury t set ducats = v_cost + 500 - 1, reserve = 500 where t.port_id = v_home;
  if public.treasury_balance(v_home) <> v_cost + 499 then
    update public.port_treasury t set ducats = t.ducats + (v_cost + 499 - public.treasury_balance(v_home)) where t.port_id = v_home;
  end if;
  v_s := public.npc_refit_step(v_f, v_now);
  if v_s <> 'WAITING' or public.npc_refit_step(v_f, v_now + interval '1 hour') <> 'WAITING' then
    raise exception 'PROOF 30 FAIL: a city short of cost and reserve did not wait: %', v_s;
  end if;
  if exists (select 1 from public.treasury_flows t where t.id > v_flow and t.kind = 'REFIT')
     or exists (select 1 from public.ships s where s.fleet_id = v_f and s.durability > 0)
     or (select f.status from public.fleets f where f.id = v_f) <> 'UNABLE_TO_SAIL' then
    raise exception 'PROOF 30 FAIL: a broke city moved something';
  end if;
  if (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'REFIT_WAITING') <> 1 then
    raise exception 'PROOF 30 FAIL: REFIT_WAITING is not once a day: %', (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'REFIT_WAITING');
  end if;
  perform public.npc_refit_step(v_f, v_now + interval '25 hours');
  if (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'REFIT_WAITING') <> 2 then
    raise exception 'PROOF 30 FAIL: a day on, the wait is not told again';
  end if;
  -- with gold of her own she is still not towed: she is her city's to set afloat
  update public.players p set ducats = 5000000 where p.id = v_pl;
  perform public.npc_tend_route(now(), v_f, (select nf.route_id from public.npc_fleets nf where nf.fleet_id = v_f), 1);
  if (select f.status from public.fleets f where f.id = v_f) <> 'UNABLE_TO_SAIL' or (select f.port_id from public.fleets f where f.id = v_f) <> v_home then
    raise exception 'PROOF 30 FAIL: lit, the tow took a wreck';
  end if;
  raise notice 'PASS: NPC_BROKE_WAITS — one ducat short of cost and reserve: three asks, no flow, no hull, two words a day apart';

  -- the money comes; the crew is short; the job pays
  update public.port_treasury t set ducats = t.ducats + 1 where t.port_id = v_home;
  update public.ships s set crew = 0 where s.fleet_id = v_f;
  v_short := public.fleet_crew_shortfall(v_f);
  update public.ports p set crew_pool = public.wc_int('npc_crew_pool_floor') + 2 where p.id = v_home;
  v_sum := pg_temp.purses();
  v_b := public.treasury_balance(v_home);
  v_y := public.treasury_balance(v_yard);
  call public.tick_npc_refits(false);
  if (select f.status from public.fleets f where f.id = v_f) <> 'DOCKED' then
    raise exception 'PROOF 30 FAIL: the job did not pay when the city could';
  end if;
  if public.treasury_balance(v_home) <> v_b - v_cost or public.treasury_balance(v_yard) <> v_y + v_cost or pg_temp.purses() <> v_sum then
    raise exception 'PROOF 30 FAIL: the refit is not moved: origin %, yard %, sum %', public.treasury_balance(v_home) - v_b, public.treasury_balance(v_yard) - v_y, pg_temp.purses() - v_sum;
  end if;
  if (select count(*) from public.treasury_flows t where t.id > v_flow and t.kind = 'REFIT') <> 2 then
    raise exception 'PROOF 30 FAIL: a refit is two rows';
  end if;
  if exists (select 1 from public.ships s where s.fleet_id = v_f and s.durability <> (select b.durability from public.ship_base(s.id) b)) then
    raise exception 'PROOF 30 FAIL: no hull whole';
  end if;
  v_crew := (select sum(s.crew) from public.ships s where s.fleet_id = v_f);
  v_pool := (select p.crew_pool from public.ports p where p.id = v_home);
  if v_crew <> 2 or v_pool <> public.wc_int('npc_crew_pool_floor') then
    raise exception 'PROOF 30 FAIL: the crew is not the quay''s two above its floor: % aboard, % left, short was %', v_crew, v_pool, v_short;
  end if;
  if (select f.ready_at from public.fleets f where f.id = v_f) is null
     or abs(extract(epoch from (select f.ready_at from public.fleets f where f.id = v_f) - now()) - public.wc_int('npc_refit_minutes') * 60) > 300 then
    raise exception 'PROOF 30 FAIL: she is not held for the wait';
  end if;
  if exists (select 1 from public.npc_refit_waits w where w.fleet_id = v_f) then
    raise exception 'PROOF 30 FAIL: her wait stands';
  end if;
  if public.npc_refit_step(v_f, v_now) <> 'NOT_A_WRECK' then
    raise exception 'PROOF 30 FAIL: she can be paid for twice';
  end if;
  call public.tick_npc_refits(false);
  if (select count(*) from public.treasury_flows t where t.id > v_flow and t.kind = 'REFIT' and t.port_id = v_home) <> 1 then
    raise exception 'PROOF 30 FAIL: a second run paid for her again';
  end if;
  raise notice 'PASS: NPC_PAYS_ONCE — % d. moved origin to yard, sum 0, hull whole, 2 hands from the quay of % short, held %, a second run paid nothing', v_cost, v_short, (select f.ready_at - now() from public.fleets f where f.id = v_f);
  perform set_config('byeharu.proof_refit', v_f::text, true);
end
$$;

-- ── THE YARD ──
do $$
declare
  r       record;
  v_n     int := 0;
  v_yard  uuid;
  v_near  uuid;
  v_f     uuid;
  v_home  uuid;
  v_nat   uuid;
begin
  -- a city whose nearest yard is foreign and which holds a further yard of its own country
  for r in select p.id from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) is not null order by p.code limit 40 loop
    v_yard := public.refit_yard(r.id);
    if v_yard = r.id then
      raise exception 'PROOF 30 FAIL: a city pays itself';
    end if;
    v_near := (select y.port_id from public.yards_from(r.id) y where y.port_id <> r.id order by y.nm, y.code limit 1);
    if exists (select 1 from public.yards_from(r.id) y where y.port_id <> r.id and public.port_nation(y.port_id) = public.port_nation(r.id))
       and public.port_nation(v_yard) is distinct from public.port_nation(r.id) then
      raise exception 'PROOF 30 FAIL: a foreign yard was chosen over its own country''s';
    end if;
    if v_near <> v_yard then
      v_n := v_n + 1;
    end if;
  end loop;
  if v_n = 0 then
    raise exception 'PROOF 30 FAIL: same country first was never put to the test';
  end if;
  -- no yard can be reached: she waits, no flow
  v_f := (select nf.fleet_id from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.status = 'DOCKED' and (select count(*) from public.ships s where s.fleet_id = f.id) = 1 order by nf.roster_ord desc limit 1);
  v_home := public.fleet_origin(v_f);
  update public.ships s set durability = 0, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_f;
  update public.fleets f set status = 'UNABLE_TO_SAIL', port_id = v_home where f.id = v_f;
  delete from public.port_buildings b where b.kind = 'shipyard';
  if public.refit_yard(v_home) is not null or public.npc_refit_step(v_f) <> 'WAITING'
     or (select e.payload ->> 'why' from public.events e where e.player_id = (select f.player_id from public.fleets f where f.id = v_f) and e.kind = 'REFIT_WAITING' order by e.created_at desc limit 1) <> 'no_yard' then
    raise exception 'PROOF 30 FAIL: with no yard she did not wait';
  end if;
  raise exception using errcode = 'ZX322', message = 'undo';
exception when sqlstate 'ZX322' then
  raise notice 'PASS: NPC_YARD — never itself, its own country first (% of 40 cities pass a nearer foreign yard); with no yard she waits, named', v_n;
end
$$;

-- ── SHE SAILS AGAIN ──
do $$
declare
  v_f    uuid := current_setting('byeharu.proof_refit')::uuid;
  v_c    uuid := current_setting('byeharu.proof_cargo')::uuid;
  v_rt   uuid := (select nf.route_id from public.npc_fleets nf where nf.fleet_id = v_f);
  v_cap  uuid := public.fleet_origin(v_c);
  v_pl   uuid := (select c.player_id from public.cargo_ships c where c.fleet_id = v_c);
  v_r    jsonb;
  v_step text;
  v_t    timestamptz;
  v_i    int := 0;
begin
  -- the merchant: past the wait, her tend re-joins her from where she lies, and she sails
  v_t := (select f.ready_at from public.fleets f where f.id = v_f) + interval '1 second';
  update public.players p set ducats = 5000000 where p.id = (select f.player_id from public.fleets f where f.id = v_f);
  update public.ships s set crew = c.crew_required, water_t = 40, food_t = 40 from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_f;
  update public.fleets f set ready_at = null where f.id = v_f;   -- port_time_wake's own act; her wait is proved above
  perform cmd.advance(v_f, v_t);
  while v_i < 4 and (select f.status from public.fleets f where f.id = v_f) = 'DOCKED' loop
    v_r := public.npc_tend_route(v_t, v_f, v_rt, 1);
    v_i := v_i + 1;
  end loop;
  if (select f.status from public.fleets f where f.id = v_f) <> 'SAILING' then
    raise exception 'PROOF 30 FAIL: a refitted merchant did not sail: % %, %, route %, orders %', (select f.status from public.fleets f where f.id = v_f), v_i, v_r,
      (select to_jsonb(sr) from public.standing_routes sr where sr.id = v_rt),
      (select jsonb_agg(jsonb_build_object('v', o.verb, 's', o.status, 'e', o.error_code)) from public.orders o where o.fleet_id = v_f);
  end if;

  -- the cargo ship: the refit, she closes her lap, she loads, the wait holds her, she sails
  update public.port_treasury t set ducats = t.ducats + 100000000, reserve = 0 where t.port_id = v_cap;
  if public.npc_refit_step(v_c) <> 'PAID' then
    raise exception 'PROOF 30 FAIL: the cargo ship was not refitted';
  end if;
  if exists (select 1 from public.ships s where s.fleet_id = v_c and s.crew <> 0) then
    raise exception 'PROOF 30 FAIL: she took a crew before W8';
  end if;
  v_step := public.cargo_ship_step(v_c, now());
  if v_step <> 'HOME' or (select c.out_load from public.cargo_ships c where c.fleet_id = v_c) is not null then
    raise exception 'PROOF 30 FAIL: she did not close her lap: %', v_step;
  end if;
  perform public.convoy_book('LOADED', v_c, v_pl, v_cap, 1000);
  v_step := public.cargo_ship_step(v_c, now());
  if v_step <> 'IN_PORT' then
    raise exception 'PROOF 30 FAIL: the wait did not hold her: %', v_step;
  end if;
  v_step := public.cargo_ship_step(v_c, now() + make_interval(mins => public.wc_int('npc_refit_minutes') + 1));
  if v_step <> 'SAILED' then
    raise exception 'PROOF 30 FAIL: she did not sail after the wait: %', v_step;
  end if;
  raise notice 'PASS: NPC_REJOINS — the merchant sails from her origin by her tend (% pass(es)); the cargo ship HOME, IN_PORT, SAILED, crewless', v_i;
end
$$;

-- ── A WRECK NO SETTLED DAY BROUGHT HOME ──
do $$
declare
  v_a    uuid := pg_temp.merchant_at_sea(6);
  v_b    uuid := pg_temp.merchant_at_sea(7);
  v_va   uuid := pg_temp.voyage_of(v_a);
  v_vb   uuid := pg_temp.voyage_of(v_b);
  v_fnc  uuid := (select id from public.ports where code = 'FNC');
begin
  -- A: she arrives with no hull on a quiet day. B: as prod's two, DOCKED abroad with no hull.
  update public.ships s set durability = 0 where s.fleet_id = v_a;
  perform voyage.settle(v_a, (select o.eta from public.voyages o where o.id = v_va) + interval '1 second');
  if (select f.status from public.fleets f where f.id = v_a) <> 'UNABLE_TO_SAIL' or (select f.port_id from public.fleets f where f.id = v_a) <> v_fnc then
    raise exception 'PROOF 30 FAIL: the stray did not arrive unable';
  end if;
  perform voyage.settle(v_b, (select o.eta from public.voyages o where o.id = v_vb) + interval '1 second');
  update public.ships s set durability = 0 where s.fleet_id = v_b;
  if (select f.status from public.fleets f where f.id = v_b) <> 'DOCKED' then
    raise exception 'PROOF 30 FAIL: the second stray is not docked';
  end if;
  update public.port_treasury t set ducats = 5000000, reserve = 0 where t.port_id in (public.fleet_origin(v_a), public.fleet_origin(v_b));
  call public.tick_npc_refits(false);
  if (select f.port_id from public.fleets f where f.id = v_a) is distinct from public.fleet_origin(v_a)
     or (select f.port_id from public.fleets f where f.id = v_b) is distinct from public.fleet_origin(v_b)
     or (select f.status from public.fleets f where f.id = v_a) <> 'DOCKED' or (select f.status from public.fleets f where f.id = v_b) <> 'DOCKED'
     or exists (select 1 from public.ships s where s.fleet_id in (v_a, v_b) and s.durability <= 0) then
    raise exception 'PROOF 30 FAIL: the job did not bring a stray home';
  end if;
  raise notice 'PASS: NPC_STRAY — unable at Funchal and docked at Funchal, both home, paid, whole';
end
$$;

-- ── THE SWITCH GOES OFF WITH WRECKS WAITING ──
do $$
declare
  v_f    uuid := pg_temp.merchant_at_sea(8);
  v_v    uuid := pg_temp.voyage_of(v_f);
  v_c    uuid := (select c.fleet_id from public.cargo_ships c join public.fleets f on f.id = c.fleet_id where f.status = 'DOCKED' and c.ord = 2 limit 1);
  v_rt   uuid := (select nf.route_id from public.npc_fleets nf where nf.fleet_id = v_f);
  v_home uuid := public.fleet_origin(v_f);
  v_r    jsonb;
  v_s    text;
begin
  update public.ships s set durability = 0 where s.fleet_id = v_f;
  perform set_config('byeharu.proof_sea', 'STORM', true);
  perform voyage.settle(v_f, voyage.day_ends_at(v_v, 1));
  perform set_config('byeharu.proof_sea', '', true);
  update public.port_treasury t set ducats = 0, reserve = 0 where t.port_id = v_home;
  if public.npc_refit_step(v_f) <> 'WAITING' then
    raise exception 'PROOF 30 FAIL: the probe did not wait';
  end if;
  update public.ships s set durability = 0 where s.fleet_id = v_c;
  update public.fleets f set status = 'UNABLE_TO_SAIL' where f.id = v_c;
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  update public.players p set ducats = 5000000 where p.id = (select f.player_id from public.fleets f where f.id = v_f);
  v_r := public.npc_tend_route(now(), v_f, v_rt, 1);
  if (select f.status from public.fleets f where f.id = v_f) = 'UNABLE_TO_SAIL' then
    raise exception 'PROOF 30 FAIL: dark again, the tow did not take her: %', v_r;
  end if;
  v_s := public.cargo_ship_step(v_c, now());
  if (select f.status from public.fleets f where f.id = v_c) <> 'DOCKED' or exists (select 1 from public.ships s where s.fleet_id = v_c and s.durability <= 0) then
    raise exception 'PROOF 30 FAIL: dark again, the patch did not take her: %', v_s;
  end if;
  raise notice 'PASS: NPC_SWITCH_OFF — the merchant towed, the cargo ship patched (%), nothing stranded', v_s;
end
$$;

-- ── THE LIFTED QUERY ──
do $$
declare
  r     record;
  v_new text;
  v_old text;
  v_n   int := 0;
begin
  for r in select p.id from public.ports p where p.kind = 'HARBOUR' order by md5(p.code) limit 60 loop
    select y.port_id::text || ':' || y.code || ':' || y.name || ':' || y.nm into v_new from public.yards_from(r.id) y order by y.nm, y.code limit 1;
    select y.id::text || ':' || y.code || ':' || y.name || ':' || (case when y.id = r.id then 0 else q.nm end) into v_old
      from public.ports y
      left join voyage.reach_from(r.id) q on q.port_id = y.id
     where y.kind = 'HARBOUR' and not y.is_ice_closed and public.port_has_shipyard(y.id)
       and (y.id = r.id or q.nm is not null)
     order by case when y.id = r.id then 0 else q.nm end, y.code
     limit 1;
    if v_new is distinct from v_old then
      raise exception 'PROOF 30 FAIL: the lifted query answers % where the old one answered %', v_new, v_old;
    end if;
    v_n := v_n + 1;
  end loop;
  raise notice 'PASS: NPC_TOW_PARITY — % ports, the same nearest yard, the same miles', v_n;
end
$$;

-- ── THE RANSOM SHARE ──
do $$
declare
  v_sum bigint := pg_temp.purses();
  v_f   bigint := coalesce((select max(id) from public.treasury_flows), 0);
begin
  if public.ransom_take(1000000) <> 80000 or public.ransom_take(0) <> 0 or public.ransom_take(null) <> 0 then
    raise exception 'PROOF 30 FAIL: the ransom share is not 8 per cent';
  end if;
  if pg_temp.purses() <> v_sum or exists (select 1 from public.treasury_flows t where t.id > v_f) then
    raise exception 'PROOF 30 FAIL: the ransom reader moved gold';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%ransom_take(%' and p.proname not in ('ransom_take', 'loot_due')) then
    raise exception 'PROOF 30 FAIL: something other than public.loot_due calls the ransom reader';
  end if;
  raise notice 'PASS: NPC_RANSOM — 8 per cent of 1,000,000 is 80,000; nothing calls it, nothing moved';
end
$$;
