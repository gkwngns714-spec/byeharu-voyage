-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 48 — THE NAVY HUNTS  (migration 0340, owner rows 284, 285, W19 of docs/WORLD_POWERS.md 6.4)
--
--   0340's self-assert reads the catalog only (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof lights both switches and runs the REAL job, the REAL step, the REAL voyage engine,
--   the REAL fight writer and the REAL wreck and refit. THE ECONOMY IS CLOSED HERE, as on prod. The sea is quiet (no hazard day). Instants are handed to every call.
--   The fight is asked for by name where a scene needs a known hull loss (as proof 40 asks it); NH_REAL takes what the real engine gives. It builds on W17's contract: public.pirate_ships, public.pirates_on,
--   public.pirate_ship_in_sea, public.pirate_side (0339), and makes its pirate ships by the hands every fleet is made by, their rows written straight, because W17's own doings (the hoard, the haunt) are W17's proof's.
--
-- @pass NH_DARK      both off: the job answers the keys it had, she lies up, no card key; navy on and pirates off: she patrols, and a pirate ship in her very sea is not fought; navy off and pirates on: nothing
-- @pass NH_HUNT      lit: at her station she sails for the nearest harbour of the most dangerous sea in reach (a pressed sea beats the authored figures; one beyond reach does not count; her own sea excluded), a real voyage, mission HUNT, her card says so
-- @pass NH_OWN_SEA   her own sea the most dangerous in reach: she lies at her station (HUNTING) for navy_hunt_hours, then picks again
-- @pass NH_LIES      at the hunt harbour she lies until hunt_until, then sails home with the hunt still on her; the pirates gone dark, she patrols as before
-- @pass NH_ARRIVALS  arrivals bound: a hunt is two legs and a lie of navy_hunt_hours; her patrol is navy_patrol_stops + 1 legs; the hunt makes no more legs than the patrol
-- @pass NH_FIGHT     a navy ship and a pirate ship in one sea at a pass: ONE fight, hull loss written on BOTH exactly, both hour-stamps written, one public NAVY_FIGHT event naming both, her card keeps it, W unchanged
-- @pass NH_ONCE      two passes inside an hour fight once; a pass past the hour fights again; the pirate's own stamp holds a second navy ship off her
-- @pass NH_AT_SEA    her sea at sea is the sea of her voyage's current segment, in port her harbour's; a navy ship sailing through the pirate's sea fights her
-- @pass NH_WRECK     every pirate hull at 0: she is a wreck by 0322's rule, respawned at her home at once, and her home pays her refit (REFIT, moved); a navy ship sunk in port cannot sail and her station pays
-- @pass NH_BOUND     at most navy_hunts_per_run fights a run; a laid-up ship, an unpaid ship, a ship over the number and a ship in a battle do not fight
-- @pass NH_REAL      through the real engine: a galion against a xebec, hull_lost adds up to the hull lost on both, both stamps, W unchanged
-- @pass NH_REGARD    a company that beats a pirate ship earns regard_pirate with every great power but the pirates, once; beaten by her, nothing; sinking her costs nothing with the pirates; a cargo ship beaten earns none of it
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'navy_enabled', 'pirates_bite', 'regard_enabled', 'npc_refits_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  update public.ports p set crew_pool = 2000;

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_48;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$ select false, null::text, 0::numeric, 0::numeric $b$
  $f$;

  -- THE FIGHT, BY NAME where a scene needs a known loss: HIT (10 off every pirate hull, 7 off every navy hull, the pirate throws her back), WON (the same, boarded), SUNK (every pirate hull), NAVY_SUNK (every navy hull),
  -- PLUNDERED / DRIVEN_OFF / RANSOM for an attack's close. Empty, the real engine. It records the sides it was handed.
  alter function public.fight_sides(uuid, integer, jsonb, jsonb, jsonb) rename to fight_sides_real_48;
  execute $f$
create function public.fight_sides(p_seed uuid, p_round integer, p_a jsonb, p_b jsonb, p_opts jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
as $b$
declare
  v_x   text := coalesce(current_setting('byeharu.proof_fight', true), '');
  v_out text := case v_x when 'HIT' then 'DRIVEN_OFF' when 'WON' then 'PLUNDERED' when 'SUNK' then 'PLUNDERED' when 'NAVY_SUNK' then 'DRIVEN_OFF' else v_x end;
  v_la  jsonb := case v_x when 'SUNK' then (select jsonb_object_agg(e->>'id', e->'hull') from jsonb_array_elements(p_a) e)
                          when 'HIT' then (select jsonb_object_agg(e->>'id', 10) from jsonb_array_elements(p_a) e)
                          when 'WON' then (select jsonb_object_agg(e->>'id', 10) from jsonb_array_elements(p_a) e)
                          else '{}'::jsonb end;
  v_lb  jsonb := case v_x when 'NAVY_SUNK' then (select jsonb_object_agg(e->>'id', e->'hull') from jsonb_array_elements(p_b) e)
                          when 'HIT' then (select jsonb_object_agg(e->>'id', 7) from jsonb_array_elements(p_b) e)
                          when 'WON' then (select jsonb_object_agg(e->>'id', 7) from jsonb_array_elements(p_b) e)
                          else '{}'::jsonb end;
begin
  perform set_config('byeharu.proof_seed', p_seed::text || ':' || p_round::text, true);
  perform set_config('byeharu.proof_sides', jsonb_array_length(p_a)::text || ':' || jsonb_array_length(p_b)::text, true);
  if v_x = '' then
    return public.fight_sides_real_48(p_seed, p_round, p_a, p_b, p_opts);
  end if;
  return jsonb_build_object('outcome', v_out, 'stood_off', false, 'slipped', false, 'broke_off', false, 'first', 'BOTH', 'rounds_fought', 0, 'rounds', '[]'::jsonb,
    'hull_lost', jsonb_build_object('a', v_la, 'b', v_lb),
    'hull', jsonb_build_object('a', 0, 'b', 0, 'a_start', 1, 'b_start', 1), 'hits', jsonb_build_object('a', 0, 'b', 0));
end
$b$
  $f$;

  execute $f$
create function pg_temp.purses()
returns bigint language sql as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint
       + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;

  -- a navy ship of p_nation in service, lying at p_port, on duty, whole, with her hands
  execute $f$
create function pg_temp.navy_48(p_nation uuid, p_port uuid, p_at timestamptz)
returns uuid
language plpgsql
as $b$
declare
  v_cap uuid := public.realm_capital(p_nation);
  v_ord int := coalesce((select max(n.ord) from public.navy_ships n where n.nation_id = p_nation), 0) + 1;
  v_f   uuid;
begin
  insert into public.navy_realms (nation_id, ships, read_at) values (p_nation, v_ord + 24, p_at) on conflict (nation_id) do update set ships = v_ord + 24, read_at = p_at;   -- a scene's ord is never above the number
  v_f := public.navy_commission(p_nation, v_ord, v_cap, public.refit_yard(v_cap), p_port, p_at);
  update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_f;
  return v_f;
end
$b$
  $f$;

  -- a pirate ship of the Brethren, made by the hands every fleet is made by, her row written straight: cruising sea p_sea, lying at p_port, her home Port Royal
  execute $f$
create function pg_temp.pirate_48(p_port uuid, p_sea uuid, p_at timestamptz)
returns uuid
language plpgsql
as $b$
declare
  v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
  v_home uuid := (select p.id from public.ports p where p.code = 'POR');
  v_ord  int := coalesce((select max(x.ord) from public.pirate_ships x), 0) + 1;
  v_pl   uuid;
  v_f    uuid;
begin
  insert into public.players (company_name, nation_id, ducats, is_npc) values (format('Brethren %s', v_ord), v_pir, 0, true) returning id into v_pl;
  v_f := public.form_fleet(v_pl, format('Pirate ship %s', v_ord), p_port);
  perform public.commission_ship(v_pl, v_f, public.wc_text('pirate_ship_class'), format('Pirate ship %s', v_ord), true, false);
  update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_f;
  insert into public.pirate_ships (fleet_id, player_id, ord, home_port, sea_id, mission, haunt_port, last_port, created_at)
  values (v_f, v_pl, v_ord, v_home, p_sea, 'CRUISE', p_port, p_port, p_at);
  return v_f;
end
$b$
  $f$;

  -- a human company of Portugal, her one fleet with 100 hands, the best guns, her hold empty
  execute $f$
create function pg_temp.house_48(p_n int)
returns uuid
language plpgsql
as $b$
declare
  v_uid uuid := ('00000000-0340-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid;
  v_p   uuid := public.new_house(v_uid, 'Casa Caza ' || p_n, 'PRT', 'LIS', 'Caza ' || p_n,
                                 (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Caza ' || p_n, null, false);
  v_f   uuid;
begin
  select id into v_f from public.fleets where player_id = v_p;
  update public.ships set crew = 100, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_f;
  return v_f;
end
$b$
  $f$;

  -- she leaves her voyage and lies docked at a harbour, as if she had arrived
  execute $f$
create function pg_temp.dock_48(p_fleet uuid, p_port uuid)
returns void
language sql
as $b$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = p_port, lat = null, lon = null, ready_at = null, version = f.version + 1 where f.id = p_fleet
$b$
  $f$;

  -- she lies at sea-anchor on another fleet's very point
  execute $f$
create function pg_temp.lie_by_48(p_fleet uuid, p_target uuid, p_at timestamptz)
returns void
language sql
as $b$
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon, version = f.version + 1
    from voyage.fleet_point(p_target, p_at) p where f.id = p_fleet
$b$
  $f$;

  -- a navy ship's leg from one harbour to another, as her step sails it
  execute $f$
create function pg_temp.sail_48(p_fleet uuid, p_from uuid, p_to uuid, p_at timestamptz)
returns uuid
language plpgsql
as $b$
declare
  v_leg jsonb := public.cargo_circuit_plan((select n.nation_id from public.navy_ships n where n.fleet_id = p_fleet), p_from, p_to) #> '{legs,0}';
begin
  if v_leg is null then
    raise exception 'PROOF 48 FAIL: no course from % to %', p_from, p_to;
  end if;
  perform public.navy_sail(p_fleet, p_from, voyage.segments_from_course(v_leg -> 'course'), p_to, null, 0, p_at);
  return (select v.id from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING');
end
$b$
  $f$;

  -- the k-th harbour of the targets of a station, counted over the seas that are not the station's own and have a course from it
  execute $f$
create function pg_temp.target_48(p_nation uuid, p_station uuid, p_k int, p_at timestamptz)
returns table (port_id uuid, sea_id uuid)
language plpgsql
as $b$
declare
  r   record;
  v_k int := 0;
begin
  for r in select t.port_id, t.sea_id from public.navy_hunt_targets(p_station, p_at) t where t.port_id <> p_station order by t.nm, t.port_id loop
    if public.cargo_circuit_plan(p_nation, p_station, r.port_id) #> '{legs,0}' is not null then
      v_k := v_k + 1;
      if v_k = p_k then
        port_id := r.port_id;
        sea_id := r.sea_id;
        return next;
        return;
      end if;
    end if;
  end loop;
  raise exception 'PROOF 48 FAIL: no %th sea in reach of the station with a course', p_k;
end
$b$
  $f$;

  -- the pass, by name
  execute $f$
create function pg_temp.pass_48(p_at timestamptz, p_nation uuid)
returns int
language plpgsql
as $b$
declare
  v int;
begin
  v := public.navy_hunt_pass(p_at, p_nation);
  return v;
end
$b$
  $f$;

  execute $f$
create function pg_temp.fought_48(p_fleet uuid)
returns timestamptz language sql as $b$
  select coalesce((select n.fought_at from public.navy_ships n where n.fleet_id = p_fleet), (select x.fought_at from public.pirate_ships x where x.fleet_id = p_fleet))
$b$
  $f$;

  execute $f$
create function pg_temp.fights_48()
returns bigint language sql as $b$ select count(*) from public.events e where e.player_id is null and e.kind = 'NAVY_FIGHT' $b$
  $f$;

  -- the world's line of one fight: the public NAVY_FIGHT naming this navy ship at this instant (every event of one transaction shares created_at, so the line is found by what it says)
  execute $f$
create function pg_temp.line_48(p_navy uuid, p_at timestamptz)
returns public.events language sql as $b$
  select e.* from public.events e where e.kind = 'NAVY_FIGHT' and e.payload #>> '{navy,fleet}' = p_navy::text and e.payload -> 'at' = to_jsonb(p_at) order by e.id limit 1
$b$
  $f$;

  -- the scene's ships struck from the rolls (their fleets stay, nowhere), so the next scene's first ship is ord 1 and her station the capital (public.navy_station_of); no pressure anywhere
  execute $f$
create function pg_temp.clear_48(p_at timestamptz)
returns void
language sql
as $b$
  update public.players p set company_name = 'struck ' || substr(md5(gen_random_uuid()::text), 1, 12)   -- 3 to 24 characters, unique enough for a scene
   where p.id in (select n.player_id from public.navy_ships n union select x.player_id from public.pirate_ships x);
  delete from public.navy_ships n where true;
  delete from public.pirate_ships x where true;
  delete from public.sea_pressure
$b$
  $f$;

  -- every great power's ships and circuits, as the world has them
  declare
    v_nat uuid;
    v_n   int;
  begin
    for v_nat in select g.nation_id from public.great_powers g where not g.pirate loop
      for v_n in 1 .. 2 loop
        perform public.tick_cargo_ships(now(), v_nat);
      end loop;
    end loop;
  end;
end
$$;

-- ── DARK ──
do $$
declare
  v_t   timestamptz := now();
  v_nat uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_sea uuid := (select p.sea_id from public.ports p where p.id = public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT')));
  n     uuid;
  p     uuid;
  v_j   jsonb;
  v_s   text;
  v_w   bigint;
  v_ev  bigint := (select count(*) from public.events);
begin
  if public.economy_closed() is distinct from true then
    raise exception 'PROOF 48 FAIL: the economy is not closed here';
  end if;
  n := pg_temp.navy_48(v_nat, v_cap, v_t);
  p := pg_temp.pirate_48(v_cap, v_sea, v_t);
  v_w := pg_temp.purses();
  -- both off: the job's answer has no `fights`, she lies up at her station, no card key, nothing stamped
  v_j := public.tick_navy(v_t, v_nat);
  if v_j ? 'fights' or (select string_agg(k, ',' order by k) from jsonb_object_keys(v_j) k) <> 'added,paid,plan,steps' then
    raise exception 'PROOF 48 FAIL: dark, the job answers %', v_j;
  end if;
  if (select x.laid_up_at is null or x.mission <> 'PATROL' or x.hunt_port is not null or x.fought_at is not null from public.navy_ships x where x.fleet_id = n) or world.navy_ship_card(n) ? 'fought' then
    raise exception 'PROOF 48 FAIL: dark, she did not lie up as before, or her card serves a key';
  end if;
  if pg_temp.fights_48() <> 0 or pg_temp.fought_48(p) is not null then
    raise exception 'PROOF 48 FAIL: dark, a fight happened';
  end if;
  -- navy on, pirates off: she wakes and patrols; a pirate ship in her very sea is not fought; the answer has no `fights`
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  update public.navy_ships x set laid_up_at = null where x.fleet_id = n;
  perform public.navy_plan_step(v_t, v_nat);
  perform public.navy_plan_step(v_t, v_nat);
  v_j := public.tick_navy(v_t, v_nat);
  if v_j ? 'fights' or (select x.mission || ':' || coalesce(x.patrol::text, '-') || ':' || x.leg::text from public.navy_ships x where x.fleet_id = n) !~ '^PATROL:[0-9]+:1$' then
    raise exception 'PROOF 48 FAIL: navy on and pirates off, she is not on her patrol: % %', v_j, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  if pg_temp.fights_48() <> 0 or pg_temp.fought_48(p) is not null or pg_temp.fought_48(n) is not null then
    raise exception 'PROOF 48 FAIL: navy on and pirates off, a fight happened';
  end if;
  v_s := public.navy_ship_step(n, v_t);
  if v_s <> 'AWAY' then
    raise exception 'PROOF 48 FAIL: she is not away on her patrol: %', v_s;
  end if;
  -- navy off, pirates on: nothing
  update public.world_config set value = 'false'::jsonb where key = 'navy_enabled';
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  v_j := public.tick_navy(v_t + interval '1 minute', v_nat);
  if v_j ? 'fights' or pg_temp.fights_48() <> 0 or public.navy_hunts_on() then
    raise exception 'PROOF 48 FAIL: navy off and pirates on, the hunt read lit: %', v_j;
  end if;
  if pg_temp.purses() <> v_w then
    raise exception 'PROOF 48 FAIL: dark, gold moved';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_bite';
  raise notice 'PASS: NH_DARK — both darks answer as before: keys %, no fight, no key, W unchanged', (select string_agg(k, ',' order by k) from jsonb_object_keys(v_j) k);
end
$$;

update public.world_config set value = 'true'::jsonb where key in ('navy_enabled', 'pirates_bite');

-- ── THE HUNT ──
do $$
declare
  v_t   timestamptz := now();
  v_nat uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_own uuid := (select p.sea_id from public.ports p where p.id = public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT')));
  v_por uuid := (select p.id from public.ports p where p.code = 'POR');
  v_pir uuid := (select n.id from public.nations n where n.code = 'PIR');
  t1    record;
  t2    record;
  v_far uuid;
  v_h1  uuid;
  v_hold uuid;
  n     uuid;
  v_s   text;
  v_vo  public.voyages%rowtype;
  v_leg int;
  v_homeleg int;
  v_pat int;
  v_hours numeric := public.wc_num('navy_hunt_hours');
begin
  perform pg_temp.clear_48(v_t);
  select * into t1 from pg_temp.target_48(v_nat, v_cap, 1, v_t);
  select * into t2 from pg_temp.target_48(v_nat, v_cap, 2, v_t);
  -- a sea beyond reach of the station, pressed harder than anything: it must not count
  select p.sea_id into v_far from public.ports p join public.sea_reaches r on r.port_id = v_cap
   where p.kind = 'HARBOUR' and p.id <> v_cap and p.sea_id not in (select t.sea_id from public.navy_hunt_targets(v_cap, v_t) t)
   order by p.code limit 1;
  if v_far is null then
    raise exception 'PROOF 48 FAIL: every sea is in reach of the capital; the scene needs one beyond it';
  end if;
  insert into public.sea_pressure (sea_id, value, updated_at) values (t2.sea_id, 40, v_t), (v_far, 400, v_t);
  n := pg_temp.navy_48(v_nat, v_cap, v_t);
  perform public.navy_plan_step(v_t, v_nat);
  perform public.navy_plan_step(v_t, v_nat);
  if (select t.sea_id from public.navy_hunt_targets(v_cap, v_t) t limit 1) <> t2.sea_id then
    raise exception 'PROOF 48 FAIL: the pressed sea in reach is not the first target: %', (select jsonb_agg(jsonb_build_array(t.sea_id, t.danger, t.nm)) from public.navy_hunt_targets(v_cap, v_t) t);
  end if;
  v_s := public.navy_ship_step(n, v_t);
  select * into v_vo from public.voyages v where v.fleet_id = n and v.status = 'SAILING';
  if v_s <> 'HUNT' or v_vo.id is null or v_vo.origin_port_id <> v_cap or (select p.sea_id from public.ports p where p.id = v_vo.dest_port_id) <> t2.sea_id or v_vo.departed_at <> v_t then
    raise exception 'PROOF 48 FAIL: she did not sail for the pressed sea: % %', v_s, to_jsonb(v_vo) - 'path' - 'speed_profile';
  end if;
  if (select x.mission || ':' || (x.hunt_port = v_vo.dest_port_id)::text || ':' || (x.hunt_until = v_vo.eta + make_interval(secs => (v_hours * 3600)::double precision))::text || ':' || (x.patrol is null)::text
        from public.navy_ships x where x.fleet_id = n) <> 'HUNT:true:true:true' then
    raise exception 'PROOF 48 FAIL: her row does not say HUNT to that harbour until her arrival plus the hours: %', (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  if world.navy_ship_card(n) ->> 'mission' is distinct from 'HUNT' or world.navy_ship_card(n) ->> 'to' is distinct from (select p.code from public.ports p where p.id = v_vo.dest_port_id) then
    raise exception 'PROOF 48 FAIL: her card does not say HUNT: %', world.navy_ship_card(n) - 'ships';
  end if;
  if (select s.crew from public.ships s where s.fleet_id = n) <= 0 then
    raise exception 'PROOF 48 FAIL: she sailed with no hands';
  end if;
  -- a harbour the pirates hold is never a hunt's harbour (their quay would man her, navy_pay would feed the hoard): the harbour she just sailed for given to the Brethren, no target names it or any of theirs,
  -- and from her station she hunts another (the next harbour of that sea, or the next sea, or lies at station)
  v_h1 := v_vo.dest_port_id;
  v_hold := (select a.nation_id from public.port_allegiance a where a.port_id = v_h1);
  alter table public.port_allegiance disable trigger port_allegiance_home_never_changes;   -- a proof's fixture: the harbour may be a home city; the trigger is back on two lines down
  update public.port_allegiance a set nation_id = v_pir where a.port_id = v_h1;
  alter table public.port_allegiance enable trigger port_allegiance_home_never_changes;
  if not public.pirate_power(public.port_nation(v_h1)) or exists (select 1 from public.navy_hunt_targets(v_cap, v_t) t where public.pirate_power(public.port_nation(t.port_id))) then
    raise exception 'PROOF 48 FAIL: a harbour the pirates hold is a target: %', (select jsonb_agg(t.port_id) from public.navy_hunt_targets(v_cap, v_t) t where public.pirate_power(public.port_nation(t.port_id)));
  end if;
  perform pg_temp.dock_48(n, v_cap);
  update public.navy_ships x set mission = 'PATROL', hunt_port = null, hunt_until = null where x.fleet_id = n;
  v_s := public.navy_ship_step(n, v_t + interval '1 second');
  if v_s not in ('HUNT', 'HUNTING') or (select x.hunt_port from public.navy_ships x where x.fleet_id = n) is distinct from (select x.hunt_port from public.navy_ships x where x.fleet_id = n and x.hunt_port <> v_h1)
     or public.pirate_power(public.port_nation((select x.hunt_port from public.navy_ships x where x.fleet_id = n))) then
    raise exception 'PROOF 48 FAIL: she hunted a harbour the pirates hold: % %', v_s, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  alter table public.port_allegiance disable trigger port_allegiance_home_never_changes;
  update public.port_allegiance a set nation_id = v_hold where a.port_id = v_h1;
  alter table public.port_allegiance enable trigger port_allegiance_home_never_changes;
  raise notice 'PASS: NH_HUNT — % nm to % in the pressed sea; the sea beyond reach pressed ten times harder did not count; % given to the Brethren, she hunts % instead',
    round(v_vo.total_nm), (select p.code from public.ports p where p.id = v_h1), (select p.code from public.ports p where p.id = v_h1),
    (select p.code from public.ports p join public.navy_ships x on x.hunt_port = p.id where x.fleet_id = n);

  -- her own sea the most dangerous: she lies at her station, watching, for the hours, then picks again
  delete from public.sea_pressure;
  insert into public.sea_pressure (sea_id, value, updated_at) values (v_own, 40, v_t);
  perform pg_temp.dock_48(n, v_cap);
  update public.navy_ships x set mission = 'PATROL', hunt_port = null, hunt_until = null where x.fleet_id = n;
  v_s := public.navy_ship_step(n, v_t);
  if v_s <> 'HUNTING' or (select x.mission || ':' || (x.hunt_port = v_cap)::text || ':' || (x.hunt_until = v_t + make_interval(secs => (v_hours * 3600)::double precision))::text from public.navy_ships x where x.fleet_id = n) <> 'HUNT:true:true'
     or exists (select 1 from public.voyages v where v.fleet_id = n and v.status = 'SAILING') then
    raise exception 'PROOF 48 FAIL: her own sea pressed, she did not lie at her station: %', v_s;
  end if;
  v_s := public.navy_ship_step(n, v_t + interval '5 hours');
  if v_s <> 'HUNTING' then
    raise exception 'PROOF 48 FAIL: five hours in she did not keep watching: %', v_s;
  end if;
  v_s := public.navy_ship_step(n, v_t + interval '6 hours 1 second');
  if v_s <> 'HUNTING' or (select x.hunt_until from public.navy_ships x where x.fleet_id = n) <> v_t + interval '6 hours 1 second' + make_interval(secs => (v_hours * 3600)::double precision) then
    raise exception 'PROOF 48 FAIL: past the hours she did not pick again: %', v_s;
  end if;
  raise notice 'PASS: NH_OWN_SEA — HUNTING at her station, % h, picked again past them', v_hours;

  -- at the hunt harbour: she lies until hunt_until, then sails home still hunting; the pirates dark, she patrols
  delete from public.sea_pressure;
  perform pg_temp.dock_48(n, t1.port_id);
  update public.navy_ships x set mission = 'HUNT', hunt_port = t1.port_id, hunt_until = v_t + interval '6 hours', last_port = t1.port_id where x.fleet_id = n;
  v_s := public.navy_ship_step(n, v_t + interval '1 hour');
  if v_s <> 'HUNTING' then
    raise exception 'PROOF 48 FAIL: at the hunt harbour inside the hours she did not lie: %', v_s;
  end if;
  v_s := public.navy_ship_step(n, v_t + interval '6 hours 1 second');
  select * into v_vo from public.voyages v where v.fleet_id = n and v.status = 'SAILING';
  if v_s <> 'SAILED' or v_vo.dest_port_id <> v_cap or (select x.mission || ':' || (x.hunt_port is null)::text from public.navy_ships x where x.fleet_id = n) <> 'HUNT:true' then
    raise exception 'PROOF 48 FAIL: past the hours she did not sail home: % %', v_s, to_jsonb(v_vo) - 'path' - 'speed_profile';
  end if;
  perform pg_temp.dock_48(n, v_cap);
  update public.world_config set value = 'false'::jsonb where key = 'pirates_bite';
  v_s := public.navy_ship_step(n, v_t + interval '7 hours');
  if v_s <> 'SAILED' or (select x.mission || ':' || (x.patrol is not null)::text || ':' || x.leg::text from public.navy_ships x where x.fleet_id = n) <> 'PATROL:true:1' then
    raise exception 'PROOF 48 FAIL: the pirates dark, she did not patrol: % %', v_s, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  -- off duty (unpaid) with the pirates lit, at her station: no hunt; she lies up as 0331 says
  perform pg_temp.dock_48(n, v_cap);
  update public.navy_ships x set mission = 'HUNT', hunt_port = null, hunt_until = null, patrol = null, leg = 0, unpaid_since = v_t where x.fleet_id = n;
  v_s := public.navy_ship_step(n, v_t + interval '8 hours');
  if v_s <> 'LAID_UP' or (select x.mission || ':' || (x.hunt_port is null)::text || ':' || (x.laid_up_at is not null)::text from public.navy_ships x where x.fleet_id = n) <> 'PATROL:true:true' then
    raise exception 'PROOF 48 FAIL: off duty she hunted: % %', v_s, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  update public.navy_ships x set unpaid_since = null, laid_up_at = null where x.fleet_id = n;
  -- a call or an escort took her off the hunt (0333 sets mission alone, as navy_close leaves her): the hunt's fields go at her next step as anything but a hunter, wherever she is. Port Royal, the pirates', can be no
  -- fresh target, so a stale Port Royal is told from a new pick.
  perform pg_temp.dock_48(n, t1.port_id);
  update public.navy_ships x set mission = 'PATROL', hunt_port = v_por, hunt_until = v_t - interval '1 hour', last_port = t1.port_id where x.fleet_id = n;
  v_s := public.navy_ship_step(n, v_t + interval '9 hours');
  if v_s <> 'SAILED' or (select (x.hunt_port is null and x.hunt_until is null)::text || ':' || x.mission from public.navy_ships x where x.fleet_id = n) <> 'true:PATROL' then
    raise exception 'PROOF 48 FAIL: a stale hunt survived a call: % %', v_s, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  -- the pirates gone dark (a forward rollback) with a stale hunt on a ship at her station: cleared, and she patrols
  perform pg_temp.dock_48(n, v_cap);
  update public.navy_ships x set mission = 'PATROL', hunt_port = v_por, hunt_until = v_t + interval '1 hour', patrol = null, leg = 0 where x.fleet_id = n;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_bite';
  v_s := public.navy_ship_step(n, v_t + interval '10 hours');
  if v_s <> 'SAILED' or (select (x.hunt_port is null and x.hunt_until is null)::text || ':' || x.mission || ':' || (x.patrol is not null)::text from public.navy_ships x where x.fleet_id = n) <> 'true:PATROL:true' then
    raise exception 'PROOF 48 FAIL: a stale hunt survived the rollback: % %', v_s, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  raise notice 'PASS: NH_LIES — lies to hunt_until, home still hunting, patrols when the pirates go dark, lies up unpaid; a stale hunt after a call or a rollback is cleared';

  -- arrivals bound: a hunt is 2 legs (out and home) and a lie; her patrol is navy_patrol_stops + 1 legs
  -- her legs in the window: two hunts begun from her station (one out-leg each: NH_HUNT's, and the one after a harbour went to the Brethren), one home-leg (NH_LIES), nothing else: a hunt is one leg out and one home
  select count(*) filter (where v.origin_port_id = v_cap and v.dest_port_id <> v_cap), count(*) filter (where v.dest_port_id = v_cap)
    into v_leg, v_homeleg
    from public.voyages v where v.fleet_id = n and v.departed_at >= v_t and v.departed_at < v_t + interval '7 hours';
  select count(*) into v_pat from public.navy_patrol_legs l join public.navy_stations s on s.id = l.station_id where s.nation_id = v_nat and s.port_id = v_cap and s.retired_at is null;
  if v_leg <> 2 or v_homeleg <> 1 or v_pat < 2 or 2 > v_pat then
    raise exception 'PROOF 48 FAIL: a hunt''s legs are not one out and one home (% out, % home), within her patrol''s (%)', v_leg, v_homeleg, v_pat;
  end if;
  raise notice 'PASS: NH_ARRIVALS — a hunt is 2 legs (% out-legs for 2 hunts begun, % home-leg) and a lie of % h; her patrol is % legs in about 45 min; the hunt adds no leg beyond the patrol''s rate', v_leg, v_homeleg, v_hours, v_pat;
end
$$;

-- ── THE FIGHT, ONCE AN HOUR ──
do $$
declare
  v_t   timestamptz := now();
  v_nat uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_sea uuid := (select p.sea_id from public.ports p where p.id = public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT')));
  n     uuid;
  n2    uuid;
  p     uuid;
  v_hn  numeric;
  v_hp  numeric;
  v_w   bigint;
  v_led bigint;
  v_fl  bigint;
  v_k   int;
  v_e   public.events%rowtype;
  v_c   jsonb;
begin
  perform pg_temp.clear_48(v_t);
  n := pg_temp.navy_48(v_nat, v_cap, v_t);
  p := pg_temp.pirate_48(v_cap, v_sea, v_t);
  select s.durability into v_hn from public.ships s where s.fleet_id = n;
  select s.durability into v_hp from public.ships s where s.fleet_id = p;
  v_w := pg_temp.purses();
  v_led := (select count(*) from public.ledger);
  v_fl := (select count(*) from public.treasury_flows);
  perform set_config('byeharu.proof_fight', 'HIT', true);
  v_k := pg_temp.pass_48(v_t, v_nat);
  perform set_config('byeharu.proof_fight', '', true);
  if v_k <> 1 then
    raise exception 'PROOF 48 FAIL: one navy ship and one pirate ship in one sea fought % times', v_k;
  end if;
  if current_setting('byeharu.proof_seed', true) <> n::text || ':' || floor(extract(epoch from v_t) / 3600)::int::text or current_setting('byeharu.proof_sides', true) <> '1:1' then
    raise exception 'PROOF 48 FAIL: the fight was not seeded by her fleet and the hour with one hull a side: % %', current_setting('byeharu.proof_seed', true), current_setting('byeharu.proof_sides', true);
  end if;
  if (select s.durability from public.ships s where s.fleet_id = n) <> v_hn - 7 or (select s.durability from public.ships s where s.fleet_id = p) <> v_hp - 10 then
    raise exception 'PROOF 48 FAIL: hull loss did not land on both exactly: navy % -> %, pirate % -> %', v_hn, (select s.durability from public.ships s where s.fleet_id = n), v_hp, (select s.durability from public.ships s where s.fleet_id = p);
  end if;
  if pg_temp.fought_48(n) is distinct from v_t or pg_temp.fought_48(p) is distinct from v_t then
    raise exception 'PROOF 48 FAIL: the hour-stamps were not both written: % %', pg_temp.fought_48(n), pg_temp.fought_48(p);
  end if;
  v_e := pg_temp.line_48(n, v_t);
  if pg_temp.fights_48() <> 1 or v_e.id is null or v_e.player_id is not null or v_e.payload #>> '{navy,fleet}' is distinct from n::text or v_e.payload #>> '{pirate,fleet}' is distinct from p::text
     or v_e.payload ->> 'result' is distinct from 'LOST' or v_e.payload ->> 'sea' is distinct from (select s.code from public.seas s where s.id = v_sea)
     or (v_e.payload #>> '{hull_lost,navy}')::numeric is distinct from 7::numeric or (v_e.payload #>> '{hull_lost,pirate}')::numeric is distinct from 10::numeric
     or v_e.payload #>> '{pirate,home}' is distinct from 'POR' or v_e.payload #>> '{navy,nation}' is distinct from 'PRT' then
    raise exception 'PROOF 48 FAIL: the world''s line is not one public NAVY_FIGHT naming both: %', to_jsonb(v_e);
  end if;
  v_c := world.navy_ship_card(n);
  if v_c -> 'fought' ->> 'result' is distinct from 'LOST' or v_c -> 'fought' ->> 'foe' is distinct from (select f.name from public.fleets f where f.id = p)
     or (v_c -> 'fought' ->> 'at')::timestamptz is distinct from v_t or v_c -> 'fought' ->> 'sea' is distinct from v_e.payload ->> 'sea' then
    raise exception 'PROOF 48 FAIL: her card does not keep the fight: %', v_c -> 'fought';
  end if;
  if pg_temp.purses() <> v_w or (select count(*) from public.ledger) <> v_led or (select count(*) from public.treasury_flows) <> v_fl then
    raise exception 'PROOF 48 FAIL: a fight moved gold';
  end if;
  if (select f.status from public.fleets f where f.id = n) <> 'DOCKED' or (select f.status from public.fleets f where f.id = p) <> 'DOCKED' then
    raise exception 'PROOF 48 FAIL: a fight that sank nobody changed a status';
  end if;
  raise notice 'PASS: NH_FIGHT — one fight, navy -7, pirate -10, both stamped, one public line, her card keeps it, W unchanged';

  -- inside the hour: no second fight; past it: one more. The pirate's own stamp holds a second navy ship off her.
  n2 := pg_temp.navy_48(v_nat, v_cap, v_t);
  perform set_config('byeharu.proof_fight', 'HIT', true);
  v_k := pg_temp.pass_48(v_t + interval '30 minutes', v_nat);
  if v_k <> 0 or pg_temp.fights_48() <> 1 or pg_temp.fought_48(n) is distinct from v_t or pg_temp.fought_48(p) is distinct from v_t or pg_temp.fought_48(n2) is not null then
    raise exception 'PROOF 48 FAIL: inside the hour % more fight(s)', v_k;
  end if;
  -- the navy ship's OWN stamp holds her (the second ship laid up, the pirate's stamp wiped): still nothing inside the hour
  update public.navy_ships x set laid_up_at = v_t where x.fleet_id = n2;
  update public.pirate_ships x set fought_at = null where x.fleet_id = p;
  v_k := pg_temp.pass_48(v_t + interval '31 minutes', v_nat);
  if v_k <> 0 or pg_temp.fought_48(n) is distinct from v_t then
    raise exception 'PROOF 48 FAIL: the navy ship''s own stamp did not hold her: % fight(s)', v_k;
  end if;
  update public.pirate_ships x set fought_at = v_t where x.fleet_id = p;
  v_k := pg_temp.pass_48(v_t + interval '59 minutes 59 seconds', v_nat);
  if v_k <> 0 then
    raise exception 'PROOF 48 FAIL: a second before the hour % fight(s)', v_k;
  end if;
  v_k := pg_temp.pass_48(v_t + interval '1 hour', v_nat);
  perform set_config('byeharu.proof_fight', '', true);
  if v_k <> 1 or pg_temp.fights_48() <> 2 or pg_temp.fought_48(n) is distinct from v_t + interval '1 hour' or pg_temp.fought_48(p) is distinct from v_t + interval '1 hour' then
    raise exception 'PROOF 48 FAIL: past the hour % fight(s), stamps % %', v_k, pg_temp.fought_48(n), pg_temp.fought_48(p);
  end if;
  if (select s.durability from public.ships s where s.fleet_id = n) <> v_hn - 14 or (select s.durability from public.ships s where s.fleet_id = p) <> v_hp - 20 then
    raise exception 'PROOF 48 FAIL: the second fight did not land';
  end if;
  raise notice 'PASS: NH_ONCE — 30 min and 59:59 later nothing, at the hour one more; the pirate''s stamp held the second ship off';
end
$$;

-- ── AT SEA ──
do $$
declare
  v_t   timestamptz := now();
  v_nat uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  t1    record;
  n     uuid;
  p     uuid;
  v_vo  public.voyages%rowtype;
  v_s0  uuid;
  v_s1  uuid;
  v_k   int;
begin
  perform pg_temp.clear_48(v_t);
  select * into t1 from pg_temp.target_48(v_nat, v_cap, 1, v_t);
  n := pg_temp.navy_48(v_nat, v_cap, v_t);
  if public.fleet_sea(n, v_t) <> (select x.sea_id from public.ports x where x.id = v_cap) then
    raise exception 'PROOF 48 FAIL: in port her sea is not her harbour''s';
  end if;
  perform pg_temp.sail_48(n, v_cap, t1.port_id, v_t);
  select * into v_vo from public.voyages v where v.fleet_id = n and v.status = 'SAILING';
  v_s0 := (v_vo.path -> 0 ->> 'sea_id')::uuid;
  v_s1 := (v_vo.path -> (jsonb_array_length(v_vo.path) - 1) ->> 'sea_id')::uuid;
  if public.fleet_sea(n, v_t + interval '1 second') <> v_s0 or public.fleet_sea(n, v_vo.eta - interval '1 second') <> v_s1 then
    raise exception 'PROOF 48 FAIL: at sea her sea is not her segment''s: % % / % %', public.fleet_sea(n, v_t + interval '1 second'), v_s0, public.fleet_sea(n, v_vo.eta - interval '1 second'), v_s1;
  end if;
  if public.fleet_sea(n, v_vo.eta + interval '1 second') <> (select x.sea_id from public.ports x where x.id = t1.port_id) then
    raise exception 'PROOF 48 FAIL: arrived, her sea is not her harbour''s';
  end if;
  -- a pirate ship in the sea she is sailing through: a fight at sea, no status touched, her voyage goes on
  p := pg_temp.pirate_48(t1.port_id, v_s0, v_t);
  perform set_config('byeharu.proof_fight', 'HIT', true);
  v_k := pg_temp.pass_48(v_t + interval '1 second', v_nat);
  perform set_config('byeharu.proof_fight', '', true);
  if v_k <> 1 or pg_temp.fought_48(n) is distinct from v_t + interval '1 second' or (select f.status from public.fleets f where f.id = n) <> 'SAILING' or (select v.status from public.voyages v where v.id = v_vo.id) <> 'SAILING' then
    raise exception 'PROOF 48 FAIL: at sea she did not fight, or her voyage was touched: % %', v_k, (select f.status from public.fleets f where f.id = n);
  end if;
  -- the pirate in another sea: no fight for a ship whose segment is not there (her stamp cleared, so only the sea holds her off)
  update public.navy_ships x set fought_at = null where x.fleet_id = n;
  update public.pirate_ships x set fought_at = null, sea_id = (select s.id from public.seas s where s.id not in (v_s0, v_s1) order by s.code limit 1) where x.fleet_id = p;
  v_k := pg_temp.pass_48(v_t + interval '2 seconds', v_nat);
  if v_k <> 0 or pg_temp.fought_48(n) is not null or pg_temp.fought_48(p) is not null then
    raise exception 'PROOF 48 FAIL: a pirate in another sea was fought';
  end if;
  raise notice 'PASS: NH_AT_SEA — first segment % last %; fought at sea, voyage untouched; another sea, nothing', (select s.code from public.seas s where s.id = v_s0), (select s.code from public.seas s where s.id = v_s1);
end
$$;

-- ── A WRECK ──
do $$
declare
  v_t   timestamptz := now();
  v_nat uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_sea uuid := (select p.sea_id from public.ports p where p.id = public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT')));
  v_por uuid := (select p.id from public.ports p where p.code = 'POR');
  t1    record;
  n     uuid;
  p     uuid;
  v_vo  uuid;
  v_k   int;
  v_w   bigint;
  v_home0 bigint;
  v_yard  uuid;
  v_yard0 bigint;
  v_cost  bigint;
  v_s   text;
  v_e   jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key = 'npc_refits_enabled';
  perform pg_temp.clear_48(v_t);
  select * into t1 from pg_temp.target_48(v_nat, v_cap, 1, v_t);
  n := pg_temp.navy_48(v_nat, v_cap, v_t);
  -- the pirate ship at sea, bound for the capital's harbour, cruising the capital's sea: sunk, she respawns home at once
  p := pg_temp.pirate_48(t1.port_id, v_sea, v_t);
  update public.pirate_ships x set home_port = v_por where x.fleet_id = p;
  perform public.fleet_hands(p, t1.port_id);
  perform public.fleet_stores(p, 30);
  perform voyage.depart(p, voyage.segments_from_course(public.cargo_circuit_plan(v_nat, t1.port_id, v_cap) #> '{legs,0,course}'), t1.port_id, v_cap, v_t);
  select v.id into v_vo from public.voyages v where v.fleet_id = p and v.status = 'SAILING';
  if v_vo is null then
    raise exception 'PROOF 48 FAIL: the pirate ship did not sail';
  end if;
  v_w := pg_temp.purses();
  v_cost := public.npc_refit_cost(p);
  v_home0 := public.treasury_balance(v_por);
  perform set_config('byeharu.proof_fight', 'SUNK', true);
  v_k := pg_temp.pass_48(v_t + interval '1 second', v_nat);
  perform set_config('byeharu.proof_fight', '', true);
  if v_k <> 1 or exists (select 1 from public.ships s where s.fleet_id = p and s.durability > 0) then
    raise exception 'PROOF 48 FAIL: she was not sunk: %', v_k;
  end if;
  if (select f.status || ':' || (f.port_id = v_por)::text from public.fleets f where f.id = p) <> 'UNABLE_TO_SAIL:true' or (select v.status from public.voyages v where v.id = v_vo) <> 'ABORTED'
     or not exists (select 1 from public.events e where e.kind = 'RESPAWNED' and e.player_id = (select f.player_id from public.fleets f where f.id = p)) then
    raise exception 'PROOF 48 FAIL: a sunk pirate ship at sea did not respawn at her home: %', (select to_jsonb(f) - 'id' from public.fleets f where f.id = p);
  end if;
  v_e := (pg_temp.line_48(n, v_t + interval '1 second')).payload;
  if v_e ->> 'result' is distinct from 'SUNK' or (v_e #>> '{sunk,pirate}')::boolean is not true or world.navy_ship_card(n) -> 'fought' ->> 'result' is distinct from 'SUNK' then
    raise exception 'PROOF 48 FAIL: the line does not say SUNK: %', v_e;
  end if;
  if pg_temp.purses() <> v_w then
    raise exception 'PROOF 48 FAIL: the sinking moved gold';
  end if;
  -- her home pays her refit, moved, by 0322's hourly step
  v_yard := public.refit_yard(v_por);
  v_yard0 := public.treasury_balance(v_yard);
  v_s := public.npc_refit_step(p, v_t + interval '2 seconds');
  if v_s <> 'PAID' or public.treasury_balance(v_por) <> v_home0 - v_cost or public.treasury_balance(v_yard) <> v_yard0 + v_cost
     or exists (select 1 from public.ships s where s.fleet_id = p and s.durability <= 0) or pg_temp.purses() <> v_w then
    raise exception 'PROOF 48 FAIL: her home did not pay her refit: % home % -> %, yard % -> %', v_s, v_home0, public.treasury_balance(v_por), v_yard0, public.treasury_balance(v_yard);
  end if;
  -- a navy ship sunk in port: she cannot sail; her station pays
  perform pg_temp.clear_48(v_t);
  n := pg_temp.navy_48(v_nat, v_cap, v_t);
  p := pg_temp.pirate_48(v_cap, v_sea, v_t);
  perform set_config('byeharu.proof_fight', 'NAVY_SUNK', true);
  v_k := pg_temp.pass_48(v_t + interval '3 seconds', v_nat);
  perform set_config('byeharu.proof_fight', '', true);
  if v_k <> 1 or (select f.status from public.fleets f where f.id = n) <> 'UNABLE_TO_SAIL' or world.navy_ship_card(n) -> 'fought' ->> 'result' is distinct from 'LOST' then
    raise exception 'PROOF 48 FAIL: a navy ship sunk in port can still sail: % %', v_k, (select f.status from public.fleets f where f.id = n);
  end if;
  v_s := public.navy_ship_step(n, v_t + interval '4 seconds');
  if v_s <> 'WRECK' then
    raise exception 'PROOF 48 FAIL: her step does not find the wreck: %', v_s;
  end if;
  v_home0 := public.treasury_balance(v_cap);
  v_cost := public.npc_refit_cost(n);
  v_s := public.npc_refit_step(n, v_t + interval '5 seconds');
  if v_s <> 'PAID' or public.treasury_balance(v_cap) <> v_home0 - v_cost or pg_temp.purses() <> v_w then
    raise exception 'PROOF 48 FAIL: her station did not pay her refit: %', v_s;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  raise notice 'PASS: NH_WRECK — the pirate wreck respawned at Port Royal and it paid % REFIT; the navy wreck in port cannot sail and her station paid %; W unchanged', public.npc_refit_cost(p), v_cost;
end
$$;

-- ── BOUND ──
do $$
declare
  v_t   timestamptz := now();
  v_nat uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_sea uuid := (select p.sea_id from public.ports p where p.id = public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT')));
  t1    record;
  n1    uuid;
  n2    uuid;
  n3    uuid;
  n4    uuid;
  n5    uuid;
  p1    uuid;
  p2    uuid;
  v_k   int;
  b     uuid;
  a     uuid;
begin
  perform pg_temp.clear_48(v_t);
  select * into t1 from pg_temp.target_48(v_nat, v_cap, 1, v_t);
  n1 := pg_temp.navy_48(v_nat, v_cap, v_t);
  n2 := pg_temp.navy_48(v_nat, t1.port_id, v_t);
  p1 := pg_temp.pirate_48(v_cap, v_sea, v_t);
  p2 := pg_temp.pirate_48(t1.port_id, t1.sea_id, v_t);
  update public.world_config set value = to_jsonb(1) where key = 'navy_hunts_per_run';
  perform set_config('byeharu.proof_fight', 'HIT', true);
  v_k := pg_temp.pass_48(v_t, v_nat);
  if v_k <> 1 or (select count(*) from public.navy_ships x where x.fleet_id in (n1, n2) and x.fought_at = v_t) <> 1 then
    raise exception 'PROOF 48 FAIL: the bound did not hold: % fight(s)', v_k;
  end if;
  v_k := pg_temp.pass_48(v_t + interval '1 minute', v_nat);
  if v_k <> 1 or (select count(*) from public.navy_ships x where x.fleet_id in (n1, n2) and x.fought_at is not null) <> 2 then
    raise exception 'PROOF 48 FAIL: the next run did not take the rest: % fight(s)', v_k;
  end if;
  update public.world_config set value = to_jsonb(5) where key = 'navy_hunts_per_run';
  -- not on duty: laid up (n2), unpaid (n1), over the number (n3, n4, n5): none fights, though a pirate ship lies in each one's sea
  update public.navy_ships x set fought_at = null, fought = null where x.fleet_id in (n1, n2);
  update public.pirate_ships x set fought_at = null where x.fleet_id in (p1, p2);
  n3 := pg_temp.navy_48(v_nat, v_cap, v_t);
  n4 := pg_temp.navy_48(v_nat, v_cap, v_t);
  n5 := pg_temp.navy_48(v_nat, v_cap, v_t);
  update public.navy_ships x set unpaid_since = v_t where x.fleet_id = n1;
  update public.navy_ships x set laid_up_at = v_t where x.fleet_id = n2;
  update public.navy_realms r set ships = (select x.ord from public.navy_ships x where x.fleet_id = n3) - 1 where r.nation_id = v_nat;   -- n3, n4, n5 are over the number
  v_k := pg_temp.pass_48(v_t + interval '2 minutes', v_nat);
  if v_k <> 0 or exists (select 1 from public.navy_ships x where x.fleet_id in (n1, n2, n3, n4, n5) and x.fought_at is not null) then
    raise exception 'PROOF 48 FAIL: a ship off duty fought: %', v_k;
  end if;
  update public.navy_realms r set ships = 40 where r.nation_id = v_nat;
  update public.navy_ships x set unpaid_since = null where x.fleet_id = n1;
  update public.navy_ships x set laid_up_at = v_t where x.fleet_id in (n4, n5);
  -- n3 in a battle, and p1 (the pirate in n1's sea) set upon in it at anchor off the capital: neither n1 nor n3 fights; she answers one thing
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  a := pg_temp.house_48(1);
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat + 0.01, lon = p.lon + 0.01, version = f.version + 1 from public.ports p where f.id = p1 and p.id = v_cap;
  perform pg_temp.lie_by_48(a, p1, v_t);
  b := public.battle_open('PROBE', a, p1, v_t);
  update public.navy_ships x set battle_id = b where x.fleet_id = n3;
  v_k := pg_temp.pass_48(v_t + interval '3 minutes', v_nat);
  if v_k <> 0 or exists (select 1 from public.navy_ships x where x.fleet_id in (n1, n3) and x.fought_at is not null) then
    raise exception 'PROOF 48 FAIL: a ship in a battle, or one whose pirate is in a battle, fought: %', v_k;
  end if;
  perform set_config('byeharu.proof_fight', 'DRIVEN_OFF', true);   -- by name, so the pirate keeps her hull for the scene below
  perform public.battle_resolve(b, v_t + interval '601 seconds');
  perform set_config('byeharu.proof_fight', '', true);
  update public.navy_ships x set battle_id = null where x.fleet_id = n3;
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
  -- a ship whose sea cannot be read (at anchor where no sea claims the point: voyage.sea_near raises E_NO_SEA) is skipped with a warning, and the rest fight
  update public.navy_ships x set laid_up_at = null, fought_at = null, fought = null where x.fleet_id in (n1, n4);
  update public.pirate_ships x set fought_at = null where x.fleet_id = p1;
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = 46, lon = 90, version = f.version + 1 where f.id = n4;   -- Dzungaria: no sea within two degrees
  perform set_config('byeharu.proof_fight', 'HIT', true);
  v_k := pg_temp.pass_48(v_t + interval '4 minutes', v_nat);
  perform set_config('byeharu.proof_fight', '', true);
  if v_k <> 1 or (select x.fought_at from public.navy_ships x where x.fleet_id = n1) is distinct from v_t + interval '4 minutes' or (select x.fought_at from public.navy_ships x where x.fleet_id = n4) is not null then
    raise exception 'PROOF 48 FAIL: a ship with no sea stopped the pass: % fight(s)', v_k;
  end if;
  raise notice 'PASS: NH_BOUND — navy_hunts_per_run 1 held, the rest next run; laid up, unpaid, over the number and in a battle: none fought; a ship with no sea is skipped, the rest fight';
end
$$;

-- ── THE REAL ENGINE ──
do $$
declare
  v_t   timestamptz := now();
  v_nat uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_sea uuid := (select p.sea_id from public.ports p where p.id = public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT')));
  n     uuid;
  p     uuid;
  v_hn  numeric;
  v_hp  numeric;
  v_w   bigint;
  v_k   int;
  v_e   jsonb;
begin
  perform pg_temp.clear_48(v_t);
  n := pg_temp.navy_48(v_nat, v_cap, v_t);
  p := pg_temp.pirate_48(v_cap, v_sea, v_t);
  select sum(s.durability) into v_hn from public.ships s where s.fleet_id = n;
  select sum(s.durability) into v_hp from public.ships s where s.fleet_id = p;
  v_w := pg_temp.purses();
  v_k := pg_temp.pass_48(v_t, v_nat);
  v_e := (pg_temp.line_48(n, v_t)).payload;
  if v_k <> 1 or v_e ->> 'result' not in ('WON', 'LOST', 'DREW', 'SUNK') or v_e ->> 'outcome' not in ('EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED') then
    raise exception 'PROOF 48 FAIL: the real engine: % %', v_k, v_e;
  end if;
  if v_hn - (select sum(s.durability) from public.ships s where s.fleet_id = n) <> (v_e #>> '{hull_lost,navy}')::numeric
     or v_hp - (select sum(s.durability) from public.ships s where s.fleet_id = p) <> (v_e #>> '{hull_lost,pirate}')::numeric then
    raise exception 'PROOF 48 FAIL: hull_lost does not add up to the hull lost: navy % -> % (%), pirate % -> % (%)', v_hn, (select sum(s.durability) from public.ships s where s.fleet_id = n), v_e #>> '{hull_lost,navy}',
      v_hp, (select sum(s.durability) from public.ships s where s.fleet_id = p), v_e #>> '{hull_lost,pirate}';
  end if;
  if pg_temp.fought_48(n) is distinct from v_t or pg_temp.fought_48(p) is distinct from v_t or pg_temp.purses() <> v_w then
    raise exception 'PROOF 48 FAIL: the real engine: stamps or gold';
  end if;
  raise notice 'PASS: NH_REAL — galion against xebec: %, navy lost %, pirate lost %, W unchanged', v_e ->> 'result', v_e #>> '{hull_lost,navy}', v_e #>> '{hull_lost,pirate}';
end
$$;

-- ── REGARD ──
do $$
declare
  v_t   timestamptz := now();
  v_nat uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_sea uuid := (select p.sea_id from public.ports p where p.id = public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT')));
  v_pir uuid := (select n.id from public.nations n where n.code = 'PIR');
  t1    record;
  a     uuid;
  p     uuid;
  b     uuid;
  v_pl  uuid;
  v_r0  numeric;
  v_n   int;
  v_ev  int;
  v_sink int;
  d     uuid;
begin
  update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'regard_enabled');
  perform pg_temp.clear_48(v_t);
  select * into t1 from pg_temp.target_48(v_nat, v_cap, 1, v_t);
  a := pg_temp.house_48(2);
  v_pl := (select f.player_id from public.fleets f where f.id = a);
  p := pg_temp.pirate_48(t1.port_id, v_sea, v_t);
  perform public.fleet_hands(p, t1.port_id);
  perform public.fleet_stores(p, 30);
  perform voyage.depart(p, voyage.segments_from_course(public.cargo_circuit_plan(v_nat, t1.port_id, v_cap) #> '{legs,0,course}'), t1.port_id, v_cap, v_t);
  perform pg_temp.lie_by_48(a, p, v_t);
  v_r0 := public.regard_of(v_pl, v_nat);
  v_ev := (select count(*) from public.events e where e.kind = 'REGARD_CHANGED');
  -- she beats the pirate ship: regard_pirate with every great power but the pirates, once
  b := public.battle_open('ATTACK', a, p, v_t);
  perform set_config('byeharu.proof_fight', 'PLUNDERED', true);
  perform public.battle_resolve(b, v_t + interval '601 seconds');
  perform set_config('byeharu.proof_fight', '', true);
  select count(*) into v_n from public.events e where e.kind = 'REGARD_CHANGED' and e.player_id = v_pl and e.payload ->> 'reason' = 'DROVE_OFF_PIRATE';
  if v_n <> (select count(*) from public.great_powers g where not g.pirate) or (select count(*) from public.great_powers g where not g.pirate) < 10
     or exists (select 1 from public.events e where e.kind = 'REGARD_CHANGED' and e.player_id = v_pl and e.payload ->> 'nation' = 'PIR')
     or round(public.regard_of(v_pl, v_nat) - v_r0) <> public.wc_num('regard_pirate_beaten')
     or exists (select 1 from public.great_powers g where not g.pirate and round(public.regard_of(v_pl, g.nation_id) - (public.wc('regard_stance_base') ->> public.power_stance(v_nat, g.nation_id))::numeric) <> public.wc_num('regard_pirate_beaten')) then
    raise exception 'PROOF 48 FAIL: beating a pirate ship earned % lines, PRT moved %', v_n, public.regard_of(v_pl, v_nat) - v_r0;
  end if;
  if (select count(*) from public.events e where e.kind = 'REGARD_CHANGED') - v_ev <> v_n then
    raise exception 'PROOF 48 FAIL: another regard moved with the pirate beaten';
  end if;
  -- beaten by her: nothing
  perform pg_temp.clear_48(v_t);
  v_ev := (select count(*) from public.events e where e.kind = 'REGARD_CHANGED');
  a := pg_temp.house_48(3);
  v_pl := (select f.player_id from public.fleets f where f.id = a);
  p := pg_temp.pirate_48(t1.port_id, v_sea, v_t);
  perform public.fleet_hands(p, t1.port_id);
  perform public.fleet_stores(p, 30);
  perform voyage.depart(p, voyage.segments_from_course(public.cargo_circuit_plan(v_nat, t1.port_id, v_cap) #> '{legs,0,course}'), t1.port_id, v_cap, v_t);
  perform pg_temp.lie_by_48(a, p, v_t);
  b := public.battle_open('ATTACK', a, p, v_t);
  perform set_config('byeharu.proof_fight', 'DRIVEN_OFF', true);
  perform public.battle_resolve(b, v_t + interval '601 seconds');
  perform set_config('byeharu.proof_fight', '', true);
  if (select count(*) from public.events e where e.kind = 'REGARD_CHANGED') <> v_ev then
    raise exception 'PROOF 48 FAIL: beaten by a pirate ship, regard moved';
  end if;
  -- sinking her: regard_pirate_beaten with each of the ten; the only other line is 0333's sink with the Brethren (0339's crown_nation answers them for her), never a DROVE_OFF line with them
  perform pg_temp.clear_48(v_t);
  update public.world_config set value = 'true'::jsonb where key = 'npc_refits_enabled';
  a := pg_temp.house_48(4);
  v_pl := (select f.player_id from public.fleets f where f.id = a);
  p := pg_temp.pirate_48(t1.port_id, v_sea, v_t);
  perform public.fleet_hands(p, t1.port_id);
  perform public.fleet_stores(p, 30);
  perform voyage.depart(p, voyage.segments_from_course(public.cargo_circuit_plan(v_nat, t1.port_id, v_cap) #> '{legs,0,course}'), t1.port_id, v_cap, v_t);
  perform pg_temp.lie_by_48(a, p, v_t);
  b := public.battle_open('ATTACK', a, p, v_t);
  perform set_config('byeharu.proof_fight', 'SUNK', true);
  perform public.battle_resolve(b, v_t + interval '601 seconds');
  perform set_config('byeharu.proof_fight', '', true);
  select count(*) into v_sink from public.events e where e.kind = 'REGARD_CHANGED' and e.player_id = v_pl and e.payload ->> 'reason' = 'SINK_CARGO' and e.payload ->> 'nation' = 'PIR';
  if (select count(*) from public.events e where e.kind = 'REGARD_CHANGED' and e.player_id = v_pl and e.payload ->> 'reason' = 'DROVE_OFF_PIRATE') <> (select count(*) from public.great_powers g where not g.pirate)
     or exists (select 1 from public.events e where e.kind = 'REGARD_CHANGED' and e.player_id = v_pl and e.payload ->> 'reason' = 'DROVE_OFF_PIRATE' and e.payload ->> 'nation' = 'PIR')
     or (select count(*) from public.events e where e.kind = 'REGARD_CHANGED' and e.player_id = v_pl and e.payload ->> 'reason' <> 'DROVE_OFF_PIRATE') <> v_sink
     or v_sink <> (select count(*) from public.pirate_ships x join public.nations n on n.id = public.crown_nation(x.fleet_id) where x.fleet_id = p and n.code = 'PIR')   -- 0339's crown_nation: one sink line with the Brethren; the contract's null: none
     or (select f.status from public.fleets f where f.id = p) <> 'UNABLE_TO_SAIL' then
    raise exception 'PROOF 48 FAIL: sinking a pirate ship: %', (select jsonb_agg(e.payload) from public.events e where e.kind = 'REGARD_CHANGED' and e.player_id = v_pl);
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  -- a cargo ship beaten: the cargo row, none of the pirate row
  perform pg_temp.clear_48(v_t);
  a := pg_temp.house_48(5);
  v_pl := (select f.player_id from public.fleets f where f.id = a);
  select c.fleet_id into d from public.cargo_ships c join public.nations x on x.id = c.nation_id join public.fleets f on f.id = c.fleet_id
   where x.code <> 'PRT' and f.status = 'DOCKED' and c.out_load is null order by x.code, c.ord limit 1;
  if d is null then
    raise exception 'PROOF 48 FAIL: no cargo ship to be beaten';
  end if;
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = 10, lon = -30, ready_at = null where f.id = d;
  perform pg_temp.lie_by_48(a, d, v_t);
  b := public.battle_open('ATTACK', a, d, v_t);
  perform set_config('byeharu.proof_fight', 'PLUNDERED', true);
  perform public.battle_resolve(b, v_t + interval '601 seconds');
  perform set_config('byeharu.proof_fight', '', true);
  if exists (select 1 from public.events e where e.kind = 'REGARD_CHANGED' and e.player_id = v_pl and e.payload ->> 'reason' = 'DROVE_OFF_PIRATE') then
    raise exception 'PROOF 48 FAIL: a cargo ship beaten earned the pirate row';
  end if;
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'regard_enabled');
  raise notice 'PASS: NH_REGARD — beaten: +% with % powers, none with the pirates; beaten by her: none; sunk: the same ten and % sink line with the Brethren (0333''s line, 0339''s nation); a cargo ship: none of it',
    public.wc_num('regard_pirate_beaten'), v_n, v_sink;
end
$$;
