-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 32 — RICH CITIES SEND THE SHIPS  (migration 0324, owner row 282, W7 of docs/WORLD_POWERS.md)
--
--   0324's self-assert reads the catalog only (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof starts where prod is, ships lit and based at their capitals,
--   lights convoy_rich_enabled and runs the REAL public.city_day, cargo step, job and voyage engine. The sea is stubbed quiet, so a lap is a lap. The economy is CLOSED here, as on prod.
--   Every count of ships reads convoy_ships_per_nation.
--
-- @pass RICH_DARK        off, ships lit: the capital calls on its realm and loads, every ship at her capital, every origin the capital, a capital never in the roster
-- @pass RICH_ORIGINS     lit: the top convoy_rich_ports by room; the knob is read; no room is the capital; a port with no course or of another flag is not an origin
-- @pass RICH_REBASE      lit: each idle ship sails one real leg to her origin, round robin, empty; no teleport; a ship with funds aboard does not move her home
-- @pass RICH_CIRCUIT     a circuit from each origin starts and ends there and stops at every city of the realm, the capital too
-- @pass RICH_NO_CALL     lit: the real city_day writes no CROWN_AID and no CROWN_CALL; a ship loads at her origin the whole need, or the donor's room; the capital's need counts; the sum does not move
-- @pass RICH_BUSY_DONOR  a donor whose lock is held is passed over till the next hour, and nothing moves
-- @pass RICH_LAP         one real lap from a rich city: every stop in order, the capital topped up as a stop and told funds are on the way, the rest back at the rich city; no fold drift
-- @pass RICH_WRECK       W6's constraint: a wreck loaded at a rich city returns there, inside voyage.settle, with no raise; a wreck on her way to a new home lies at that home
-- @pass RICH_STAYS       a home that left the top holds her until convoy_rebase_idle_days after her last book row; a home in the top holds her for good; then one sailed leg
-- @pass RICH_COMMISSION  a ship made lit is made at her origin, round robin, based
-- @pass RICH_GIFT        lit: a gift pays from what the capital holds, else waits, with no call; a founding still pays, from the world's richest harbour; off, the call stands
-- @pass RICH_SWITCH_OFF  off mid-lap: nothing strands, funds return where they loaded, every ship sails back to her capital, the call and the capital's load are back
-- @pass RICH_NEEDS_SHIPS convoys off: the knob alone lights nothing, and the instant path stands
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_last  int := world.game_day() - 1;
  v_flow  bigint;
  v_nat   uuid;
  v_cap   uuid;
  v_cit   uuid[];     -- the realm's other harbours on a course, by code
  v_d1    uuid;
  v_d2    uuid;
  v_d3    uuid;
  v_d4    uuid;
  v_s1    uuid;
  v_s2    uuid;
  v_k     int;
  v_n     int := 0;
  v_fl    uuid;
  v_fl2   uuid;
  v_fl3   uuid;
  v_heavy uuid;
  v_pl    uuid;
  v_o     uuid[];
  v_cir   bigint;
  v_load  bigint;
  v_sum   bigint;
  v_tot0  bigint;
  v_room  bigint;
  v_need  bigint;
  v_now   timestamptz;
  v_end   timestamptz;
  v_voy   uuid;
  v_step  text;
  v_seq   text[] := '{}';
  v_want  text[];
  v_guard int := 0;
  v_r     jsonb;
  v_x     jsonb;
  v_t0    timestamptz;
  v_ms    numeric;
  v_told  jsonb;
  r       record;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled');
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  update public.world_config set value = to_jsonb(0.1) where key = 'crown_call_share';
  update public.world_config set value = to_jsonb(20) where key = 'crown_call_cover';
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  update public.world_config set value = to_jsonb(greatest(5, public.wc_int('convoy_ships_per_nation'))) where key = 'convoy_ships_per_nation';
  update public.world_config set value = to_jsonb(3) where key = 'convoy_rich_ports';
  v_k := public.wc_int('convoy_ships_per_nation');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set earned_day = v_last, ducats = 50000, reserve = 0;   -- only the aid runs; everyone exactly at target

  -- THE SEA ON ONE SETTING: empty, every day is quiet
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_32;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$
  select coalesce(current_setting('byeharu.proof_sea', true), '') <> '', nullif(current_setting('byeharu.proof_sea', true), ''), 0.5::numeric, 1::numeric
$b$
  $f$;
  execute $f$
create function pg_temp.purses()
returns bigint
language sql
as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint
       + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;
  execute $f$
create function pg_temp.purse(p_port uuid, p_d bigint)
returns void
language plpgsql
as $b$
declare
  v_by bigint := p_d - public.treasury_balance(p_port);
begin
  update public.port_treasury t set reserve = 0 where t.port_id = p_port;
  if v_by <> 0 then
    perform public.treasury_post(p_port, 'CROWN_CALL', v_by, null, null, true);   -- a probe's hand on a purse: every reader below takes its mark after this
  end if;
end
$b$
  $f$;
  execute $f$
create function pg_temp.flows(p_mark bigint)
returns jsonb
language sql
as $b$
  select coalesce(jsonb_object_agg(x.kind, x.n), '{}'::jsonb) from (select f.kind, count(*) as n from public.treasury_flows f where f.id > p_mark group by 1) x
$b$
  $f$;
  execute $f$
create function pg_temp.arrive(p_fleet uuid)
returns timestamptz
language plpgsql
as $b$
declare
  v_id  uuid;
  v_eta timestamptz;
  v_g   int := 0;
begin
  select o.id, o.eta into v_id, v_eta from public.voyages o where o.fleet_id = p_fleet and o.status = 'SAILING';
  loop
    v_g := v_g + 1;
    perform voyage.settle(p_fleet, v_eta);
    exit when (select f.status from public.fleets f where f.id = p_fleet) <> 'SAILING' or v_g > 50;
    v_eta := (select o.eta from public.voyages o where o.id = v_id);
  end loop;
  return v_eta;
end
$b$
  $f$;
  execute $f$
create function pg_temp.ship(p_nation uuid, p_ord int)
returns uuid
language sql
as $b$
  select c.fleet_id from public.cargo_ships c where c.nation_id = p_nation and c.ord = p_ord
$b$
  $f$;

  select g.nation_id into v_nat from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT';
  v_cap := public.realm_capital(v_nat);
  v_cit := array(select p.id from public.ports p
                  where p.kind = 'HARBOUR' and p.id <> v_cap and public.port_nation(p.id) = v_nat
                    and exists (select 1 from public.npc_courses c where c.from_port = p.id or c.to_port = p.id)
                  order by p.code);
  if cardinality(v_cit) < 6 then
    raise exception 'PROOF 32 FAIL: Portugal has % harbours on a course', cardinality(v_cit);
  end if;
  v_d1 := v_cit[1]; v_d2 := v_cit[2]; v_d3 := v_cit[3]; v_d4 := v_cit[4]; v_s1 := v_cit[5]; v_s2 := v_cit[6];

  -- ── OFF, SHIPS LIT, AS PROD IS ──
  perform public.tick_cargo_ships(now(), v_nat);
  if (select count(*) from public.cargo_ships c where c.nation_id = v_nat and c.home_port_id = v_cap and c.based_at is null) <> v_k then
    raise exception 'PROOF 32 FAIL: off, a ship is not based at her capital';
  end if;
  if public.cargo_origins(v_nat) <> array[v_cap] or (select count(*) from public.cargo_homes(v_nat)) <> 1 or public.rich_cities_on() then
    raise exception 'PROOF 32 FAIL: off, an origin is not the capital: %', public.cargo_origins(v_nat);
  end if;
  if (select start_port from public.cargo_circuits k where k.id = public.cargo_circuit_of(v_nat, v_cap)) <> v_cap then
    raise exception 'PROOF 32 FAIL: off, her circuit does not start at the capital';
  end if;
  perform pg_temp.purse(v_cap, 1000);
  perform pg_temp.purse(v_s1, 1000);
  perform pg_temp.purse(v_d1, 10000000);
  perform pg_temp.purse(v_d2, 10000000);
  v_sum := pg_temp.purses();
  v_flow := coalesce((select max(id) from public.treasury_flows), 0);
  begin
    v_r := public.crown_aid(v_cap);
    raise exception using errcode = 'ZX324', message = jsonb_build_object('aid', v_r, 'flows', pg_temp.flows(v_flow), 'load', (select a.aboard from public.cargo_ship_aboard(pg_temp.ship(v_nat, 1)) a),
      'at', (select k.port_id from public.convoy_cargo k where k.fleet_id = pg_temp.ship(v_nat, 1) and k.stage = 'LOADED'), 'sum', pg_temp.purses())::text;
  exception when sqlstate 'ZX324' then
    v_x := sqlerrm::jsonb;
  end;
  if (v_x #>> '{flows,CROWN_CALL}') is null or (v_x -> 'flows') ? 'CROWN_AID' or (v_x ->> 'load')::bigint is distinct from 49000 or (v_x ->> 'at')::uuid is distinct from v_cap or (v_x ->> 'sum')::bigint <> v_sum then
    raise exception 'PROOF 32 FAIL: off is not the capital calling and loading: %', v_x;
  end if;
  perform pg_temp.purse(v_s1, 50000);
  raise notice 'PASS: RICH_DARK — % ships at the capital, CROWN_CALL ran, the capital loaded %, the roster left the capital out', v_k, v_x ->> 'load';

  -- ── THE SWITCH: gold where it is, and one ship caught with funds aboard ──
  perform pg_temp.purse(t.port_id, 50000) from public.port_treasury t where public.port_nation(t.port_id) = v_nat;
  perform pg_temp.purse(v_cap, 1000000);
  v_heavy := pg_temp.ship(v_nat, v_k);
  perform public.convoy_book('LOADED', v_heavy, (select c.player_id from public.cargo_ships c where c.fleet_id = v_heavy), v_cap, 200000);
  perform pg_temp.purse(v_cap, 50000);
  perform pg_temp.purse(v_d1, 90000000);
  perform pg_temp.purse(v_d2, 60000000);
  perform pg_temp.purse(v_d3, 30000000);
  perform pg_temp.purse(v_d4, 10000000);
  update public.world_config set value = 'true'::jsonb where key = 'convoy_rich_enabled';
  if not public.rich_cities_on() then
    raise exception 'PROOF 32 FAIL: the switch does not light the rule';
  end if;

  -- ── THE ORIGINS ──
  v_o := public.cargo_origins(v_nat);
  if v_o <> array[v_d1, v_d2, v_d3] then
    raise exception 'PROOF 32 FAIL: the origins are not the three with the most room: %', v_o;
  end if;
  if public.crown_call_room(v_d1) <> 8995000 then
    raise exception 'PROOF 32 FAIL: room is not the donor''s room: %', public.crown_call_room(v_d1);
  end if;
  begin
    update public.world_config set value = to_jsonb(2) where key = 'convoy_rich_ports';
    v_x := jsonb_build_object('two', cardinality(public.cargo_origins(v_nat)));
    update public.world_config set value = to_jsonb(3) where key = 'convoy_rich_ports';
    delete from public.npc_courses c where c.from_port = v_d1 or c.to_port = v_d1;
    v_x := v_x || jsonb_build_object('no_course', not (v_d1 = any (public.cargo_origins(v_nat))));
    update public.port_allegiance a set nation_id = (select g.nation_id from public.great_powers g where g.nation_id <> v_nat order by g.nation_id limit 1) where a.port_id = v_d2;
    v_x := v_x || jsonb_build_object('flag', not (v_d2 = any (public.cargo_origins(v_nat))), 'flag_room', public.cargo_load_room(v_d2, v_nat));
    perform pg_temp.purse(t.port_id, 50000) from public.port_treasury t where public.port_nation(t.port_id) = v_nat;
    v_x := v_x || jsonb_build_object('none', public.cargo_origins(v_nat) = array[v_cap]);
    raise exception using errcode = 'ZX324', message = v_x::text;
  exception when sqlstate 'ZX324' then
    v_x := sqlerrm::jsonb;
  end;
  if v_x <> '{"two": 2, "no_course": true, "flag": true, "flag_room": 0, "none": true}'::jsonb then
    raise exception 'PROOF 32 FAIL: origins: %', v_x;
  end if;
  raise notice 'PASS: RICH_ORIGINS — % in room order; the knob, a port off the courses, a lost flag and an empty realm each answered', (select array_agg(p.code order by o.n) from unnest(v_o) with ordinality o(id, n) join public.ports p on p.id = o.id);

  -- ── THE LIVE SHIPS GO TO THEIR ORIGINS ──
  v_t0 := clock_timestamp();
  v_r := public.tick_cargo_ships(now(), v_nat);
  v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  for r in select c.fleet_id, c.ord, c.home_port_id, c.based_at, f.status, f.port_id, o.id as voy, o.dest_port_id, o.eta
             from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
             left join public.voyages o on o.fleet_id = c.fleet_id and o.status = 'SAILING'
            where c.nation_id = v_nat and c.fleet_id <> v_heavy loop
    if r.home_port_id <> v_o[(r.ord - 1) % 3 + 1] or r.based_at is null then
      raise exception 'PROOF 32 FAIL: ship % is not based round robin: %', r.ord, r;
    end if;
    if r.status <> 'SAILING' or r.port_id is not null or r.dest_port_id <> r.home_port_id or r.eta <= now() then
      raise exception 'PROOF 32 FAIL: ship % did not sail there: %', r.ord, r;
    end if;
    if exists (select 1 from public.cargo_ship_aboard(r.fleet_id)) then
      raise exception 'PROOF 32 FAIL: ship % sails with funds', r.ord;
    end if;
  end loop;
  if (select c.home_port_id from public.cargo_ships c where c.fleet_id = v_heavy) <> v_cap or (select f.status from public.fleets f where f.id = v_heavy) <> 'SAILING'
     or (select c.circuit_id from public.cargo_ships c where c.fleet_id = v_heavy) is null or public.cargo_rebase_to(v_heavy, now() + interval '1 year') is not null then
    raise exception 'PROOF 32 FAIL: a ship with funds aboard moved her home, or stayed';
  end if;
  raise notice 'PASS: RICH_REBASE — % ships sailed one leg each, round robin, empty; the ship with funds aboard kept her home and sailed her lap; first tick % ms', v_k - 1, v_ms;

  -- ── THE CIRCUITS ──
  v_guard := 0;
  loop
    v_guard := v_guard + 1;
    exit when v_guard > 12 or (select count(*) from unnest(v_o) o(id) where public.cargo_circuit_of(v_nat, o.id) is not null) = 3;
    perform public.tick_cargo_ships(now(), v_nat);
  end loop;
  for r in select o.id as start, public.cargo_circuit_of(v_nat, o.id) as cir from unnest(v_o) o(id) loop
    if r.cir is null
       or (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = r.cir order by l.ord desc limit 1) <> r.start
       or (select count(distinct l.to_port) from public.cargo_circuit_legs l where l.circuit_id = r.cir) <> (select count(*) from public.ports q where q.kind = 'HARBOUR' and public.port_nation(q.id) = v_nat) - jsonb_array_length((select k.left_out from public.cargo_circuits k where k.id = r.cir))
       or not exists (select 1 from public.cargo_circuit_legs l where l.circuit_id = r.cir and l.to_port = v_cap) then
      raise exception 'PROOF 32 FAIL: a circuit from a rich city is not start, every city, start: %', r;
    end if;
  end loop;
  raise notice 'PASS: RICH_CIRCUIT — three circuits, each ends at its start and calls at the capital';

  -- they arrive, and lie idle at their new homes
  v_fl := pg_temp.ship(v_nat, 1);
  v_fl2 := pg_temp.ship(v_nat, 2);
  v_fl3 := pg_temp.ship(v_nat, 3);
  perform pg_temp.arrive(c.fleet_id) from public.cargo_ships c where c.nation_id = v_nat and c.fleet_id not in (v_heavy, v_fl3);
  v_now := now() + interval '2 days';
  update public.fleets f set ready_at = null where f.id in (v_fl, v_fl2);
  v_step := public.cargo_ship_step(v_fl, v_now);
  if v_step <> 'IDLE' or (select f.port_id from public.fleets f where f.id = v_fl) <> v_d1 or (select c.home_port_id from public.cargo_ships c where c.fleet_id = v_fl) <> v_d1 then
    raise exception 'PROOF 32 FAIL: she did not lie idle at her new home: %', v_step;
  end if;

  -- the ship caught with funds aboard closes her old lap at the capital, and only then may she move
  v_now := now();
  v_guard := 0;
  loop
    v_guard := v_guard + 1;
    exit when v_guard > 400;
    v_step := public.cargo_ship_step(v_heavy, v_now);
    exit when v_step = 'HOME';
    if v_step = 'SAILED' then
      v_now := pg_temp.arrive(v_heavy);
    elsif v_step = 'IN_PORT' then
      v_now := v_now + interval '61 seconds';
    elsif v_step <> 'AWAY' then
      raise exception 'PROOF 32 FAIL: step % on her old lap', v_step;
    else
      v_now := pg_temp.arrive(v_heavy);
    end if;
  end loop;
  if v_step <> 'HOME' or (select c.home_port_id from public.cargo_ships c where c.fleet_id = v_heavy) <> v_cap
     or exists (select 1 from public.convoy_cargo k where k.fleet_id = v_heavy and k.stage = 'RETURNED' and k.port_id <> v_cap)
     or exists (select 1 from public.cargo_ship_aboard(v_heavy)) then
    raise exception 'PROOF 32 FAIL: her old lap did not close at the capital: %', v_step;
  end if;
  v_step := public.cargo_ship_step(v_heavy, v_now + interval '1 hour');
  if v_step <> 'SAILED' or (select c.home_port_id from public.cargo_ships c where c.fleet_id = v_heavy) <> v_o[(v_k - 1) % 3 + 1] then
    raise exception 'PROOF 32 FAIL: with her lap closed she did not go to her origin: % %, wanted %', v_step, public.cargo_rebase_to(v_heavy, v_now + interval '1 hour'), public.cargo_origins(v_nat);
  end if;
  perform pg_temp.arrive(v_heavy);

  -- ── LIT: THE REAL city_day ──
  update public.fleets f set ready_at = null where f.id = v_fl;
  perform pg_temp.purse(v_s1, 1000);
  perform pg_temp.purse(v_s2, 2000);
  perform pg_temp.purse(v_cap, 20000);
  perform pg_temp.purse(v_d1, 90000000);
  perform pg_temp.purse(v_d2, 60000000);
  perform pg_temp.purse(v_d3, 30000000);
  perform pg_temp.purse(t.port_id, 50000) from public.port_treasury t where public.port_nation(t.port_id) = v_nat and t.port_id <> all (array[v_s1, v_s2, v_cap, v_d1, v_d2, v_d3, v_d4]);
  v_need := 49000 + 48000 + 30000;
  perform public.stats_live_fold(now());
  v_tot0 := (world.stats_now() ->> 'total')::bigint;
  v_sum := pg_temp.purses();
  v_flow := coalesce((select max(id) from public.treasury_flows), 0);

  -- the donor's room, smaller than the need: she carries the room and the donor keeps the rest
  begin
    perform pg_temp.purse(v_d1, 950500);
    perform pg_temp.purse(v_d2, 50000);
    perform pg_temp.purse(v_d3, 50000);
    v_room := public.crown_call_room(v_d1);
    v_r := public.city_day();
    raise exception using errcode = 'ZX324', message = jsonb_build_object('room', v_room, 'aboard', (select a.aboard from public.cargo_ship_aboard(v_fl) a), 'left', public.treasury_balance(v_d1))::text;
  exception when sqlstate 'ZX324' then
    v_x := sqlerrm::jsonb;
  end;
  if (v_x ->> 'room')::bigint >= v_need or (v_x ->> 'aboard')::bigint is distinct from (v_x ->> 'room')::bigint or (v_x ->> 'left')::bigint <> 950500 - (v_x ->> 'room')::bigint then
    raise exception 'PROOF 32 FAIL: the load went past the donor''s room: %', v_x;
  end if;

  v_r := public.city_day();
  v_load := (select a.aboard from public.cargo_ship_aboard(v_fl) a);
  v_x := pg_temp.flows(v_flow);
  if (v_x ? 'CROWN_AID') or (v_x ? 'CROWN_CALL') then
    raise exception 'PROOF 32 FAIL: lit, gold moved instantly: %', v_x;
  end if;
  if v_load is distinct from v_need then
    raise exception 'PROOF 32 FAIL: she did not load the whole need, the capital''s among it: % of %', v_load, v_need;
  end if;
  if (select k.port_id from public.convoy_cargo k where k.fleet_id = v_fl and k.stage = 'LOADED' order by k.id desc limit 1) <> v_d1 or public.treasury_balance(v_d1) <> 90000000 - v_need
     or public.treasury_balance(v_cap) <> 20000 or public.treasury_balance(v_s1) <> 1000 then
    raise exception 'PROOF 32 FAIL: the rich city did not load her, or someone was paid at once';
  end if;
  if exists (select 1 from public.cargo_ships c where c.nation_id = v_nat and c.fleet_id <> v_fl and exists (select 1 from public.cargo_ship_aboard(c.fleet_id))) then
    raise exception 'PROOF 32 FAIL: more than one ship loaded in a run';
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 32 FAIL: the sum of purses and funds moved by %', pg_temp.purses() - v_sum;
  end if;
  -- funds aboard hold her: her home out of the top, a year idle, and she is still not due a move
  begin
    perform pg_temp.purse(v_d1, 50000);
    raise exception using errcode = 'ZX324', message = jsonb_build_object('to', public.cargo_rebase_to(v_fl, now() + interval '1 year'))::text;
  exception when sqlstate 'ZX324' then
    v_x := sqlerrm::jsonb;
  end;
  if v_x ->> 'to' is not null then
    raise exception 'PROOF 32 FAIL: a ship with funds aboard is due a move: %', v_x;
  end if;
  -- the next run: what is aboard counts against the need, so nothing more is sent
  v_flow := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.crown_aid(v_cap);
  if (v_r ->> 'loaded')::bigint <> 0 or pg_temp.flows(v_flow) <> '{}'::jsonb then
    raise exception 'PROOF 32 FAIL: what is aboard was not counted: %', v_r;
  end if;
  raise notice 'PASS: RICH_NO_CALL — one CONVOY_LOAD and no call, % d. aboard at the rich city, the capital''s 30,000 d. counted; the room held; sum moved 0; the next run sent nothing', v_load;

  -- a busy donor
  begin
    perform public.convoy_book('RETURNED', v_fl, (select c.player_id from public.cargo_ships c where c.fleet_id = v_fl), v_d1, v_load, (select k.id from public.convoy_cargo k where k.fleet_id = v_fl and k.stage = 'LOADED' order by k.id desc limit 1));
    alter function public.treasury_try_lock(uuid) rename to treasury_try_lock_real_32;
    execute $f$
create function public.treasury_try_lock(p_port uuid)
returns boolean
language sql
as $b$ select false $b$
    $f$;
    v_flow := coalesce((select max(id) from public.treasury_flows), 0);
    v_r := public.crown_aid(v_cap);
    raise exception using errcode = 'ZX324', message = jsonb_build_object('loaded', v_r -> 'loaded', 'flows', pg_temp.flows(v_flow), 'funds', public.funds_aboard())::text;
  exception when sqlstate 'ZX324' then
    v_x := sqlerrm::jsonb;
  end;
  v_flow := coalesce((select max(id) from public.treasury_flows), 0);
  if (v_x ->> 'loaded')::bigint <> 0 or v_x -> 'flows' <> '{}'::jsonb or (v_x ->> 'funds')::bigint <> 0 then
    raise exception 'PROOF 32 FAIL: a busy donor paid: %', v_x;
  end if;
  raise notice 'PASS: RICH_BUSY_DONOR — nothing loaded, no flow';

  -- ── ONE REAL LAP FROM A RICH CITY. The floor falls after the load, so 30,000 d. are left to bring home ──
  update public.world_config set value = to_jsonb(40000) where key = 'treasury_reserve_floor';
  v_cir := public.cargo_circuit_of(v_nat, v_d1);
  v_want := array(select p.code from public.cargo_circuit_legs l join public.ports p on p.id = l.to_port where l.circuit_id = v_cir order by l.ord);
  v_seq := '{}';
  v_guard := 0;
  v_now := now();
  loop
    v_guard := v_guard + 1;
    exit when v_guard > 500;
    v_step := public.cargo_ship_step(v_fl, v_now);
    exit when v_step = 'HOME';
    if v_step = 'SAILED' then
      if v_told is null and not (public.funds_on_way(v_cap) = '{}'::jsonb) then
        v_told := public.funds_on_way(v_cap);
      end if;
      v_seq := v_seq || (select p.code from public.voyages o join public.ports p on p.id = o.dest_port_id where o.fleet_id = v_fl and o.status = 'SAILING');
      v_now := pg_temp.arrive(v_fl);
    elsif v_step = 'IN_PORT' then
      v_now := v_now + interval '61 seconds';
    else
      raise exception 'PROOF 32 FAIL: step % on the lap, at %', v_step, v_seq;
    end if;
  end loop;
  if v_step <> 'HOME' or v_seq <> v_want or v_seq[cardinality(v_seq)] <> (select p.code from public.ports p where p.id = v_d1) then
    raise exception 'PROOF 32 FAIL: she did not sail the circuit from the rich city: % % against %', v_step, v_seq, v_want;
  end if;
  if public.treasury_balance(v_s1) <> 40000 or public.treasury_balance(v_s2) <> 40000 or public.treasury_balance(v_cap) <> 40000 then
    raise exception 'PROOF 32 FAIL: the stops were not served: % % capital %', public.treasury_balance(v_s1), public.treasury_balance(v_s2), public.treasury_balance(v_cap);
  end if;
  if (v_told #>> '{funds_on_way,ducats}')::bigint is distinct from 20000 then
    raise exception 'PROOF 32 FAIL: the capital was not told funds were on the way: %', v_told;
  end if;
  if (select count(*) from public.convoy_cargo k where k.fleet_id = v_fl and k.stage = 'RETURNED' and k.port_id = v_d1 and k.ducats = 30000) <> 1 then
    raise exception 'PROOF 32 FAIL: the rest did not come back to the rich city';
  end if;
  if exists (select 1 from public.cargo_ship_aboard(v_fl)) or (select c.out_load from public.cargo_ships c where c.fleet_id = v_fl) is not null
     or exists (select 1 from public.ships s where s.fleet_id = v_fl and s.durability <> (select b.durability from public.ship_base(s.id) b)) then
    raise exception 'PROOF 32 FAIL: her lap did not close';
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 32 FAIL: the lap moved the sum by %', pg_temp.purses() - v_sum;
  end if;
  if (world.stats_now() ->> 'total')::bigint <> v_tot0 then
    raise exception 'PROOF 32 FAIL: the live world total moved by %', (world.stats_now() ->> 'total')::bigint - v_tot0;
  end if;
  v_r := public.stats_live_fold(now());
  if (v_r #>> '{drift,cities}')::bigint <> 0 or (v_r #>> '{drift,set_aside}')::bigint <> 0 then
    raise exception 'PROOF 32 FAIL: the fold found a drift: %', v_r;
  end if;
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  raise notice 'PASS: RICH_LAP — % stops in order, the capital topped up as a stop, told % d. on the way, 30,000 d. back at the rich city; sum moved 0, total moved 0, no drift', cardinality(v_seq), v_told #>> '{funds_on_way,ducats}';

  -- ── W6's CONSTRAINT: A WRECK LOADED AT A RICH CITY ──
  update public.world_config set value = 'true'::jsonb where key = 'npc_refits_enabled';
  update public.fleets f set ready_at = null where f.id = v_fl2;
  v_pl := (select c.player_id from public.cargo_ships c where c.fleet_id = v_fl2);
  v_load := public.convoy_book('LOADED', v_fl2, v_pl, v_d2, 40000);
  if public.cargo_ship_step(v_fl2, now()) <> 'SAILED' then
    raise exception 'PROOF 32 FAIL: the ship loaded at the rich city did not sail';
  end if;
  update public.ships s set durability = 0 where s.fleet_id = v_fl2;
  v_voy := (select o.id from public.voyages o where o.fleet_id = v_fl2 and o.status = 'SAILING');
  v_sum := pg_temp.purses();
  perform set_config('byeharu.proof_sea', 'STORM', true);
  perform voyage.settle(v_fl2, voyage.day_ends_at(v_voy, 1));
  perform set_config('byeharu.proof_sea', '', true);
  if (select f.status from public.fleets f where f.id = v_fl2) <> 'UNABLE_TO_SAIL' or (select f.port_id from public.fleets f where f.id = v_fl2) <> v_d2 then
    raise exception 'PROOF 32 FAIL: the wreck is not at the rich city she loaded at';
  end if;
  if (select count(*) from public.convoy_cargo k where k.load_id = v_load and k.stage = 'RETURNED' and k.port_id = v_d2 and k.ducats = 40000) <> 1 or pg_temp.purses() <> v_sum then
    raise exception 'PROOF 32 FAIL: her funds did not close at the rich city';
  end if;
  -- a wreck on her way to a new home: she lies at the home she was bound for, with no book
  update public.ships s set durability = 0 where s.fleet_id = v_fl3;
  v_voy := (select o.id from public.voyages o where o.fleet_id = v_fl3 and o.status = 'SAILING');
  if v_voy is null then
    raise exception 'PROOF 32 FAIL: the third ship is not on her way';
  end if;
  perform set_config('byeharu.proof_sea', 'STORM', true);
  perform voyage.settle(v_fl3, voyage.day_ends_at(v_voy, 1));
  perform set_config('byeharu.proof_sea', '', true);
  if (select f.status from public.fleets f where f.id = v_fl3) <> 'UNABLE_TO_SAIL' or (select f.port_id from public.fleets f where f.id = v_fl3) <> v_d3
     or (select c.home_port_id from public.cargo_ships c where c.fleet_id = v_fl3) <> v_d3 then
    raise exception 'PROOF 32 FAIL: a wreck on a rebase leg is not at her new home';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  perform public.cargo_ship_step(v_fl2, now());    -- patched, delayed not lost
  perform public.cargo_ship_step(v_fl3, now());
  update public.fleets f set ready_at = null where f.id in (v_fl2, v_fl3);
  raise notice 'PASS: RICH_WRECK — 40,000 d. RETURNED at the rich city inside voyage.settle, sum moved 0; a wreck on a rebase leg lies at her new home';

  -- ── A HOME THAT LEFT THE TOP ──
  perform pg_temp.purse(v_d1, 50000);                 -- out of the top
  update public.fleets f set ready_at = null where f.id = v_fl;
  v_end := (select max(k.created_at) from public.convoy_cargo k where k.fleet_id = v_fl);
  v_now := v_end + make_interval(secs => public.wc_num('convoy_rebase_idle_days')::double precision * 86400);
  if public.cargo_rebase_to(v_fl, v_now - interval '1 minute') is not null then
    raise exception 'PROOF 32 FAIL: she moved before the idle wait was out';
  end if;
  if public.cargo_rebase_to(v_fl, v_now + interval '1 minute') <> (public.cargo_origins(v_nat))[1] then
    raise exception 'PROOF 32 FAIL: after the wait she is not due the origin her ord falls on: %', public.cargo_rebase_to(v_fl, v_now + interval '1 minute');
  end if;
  if public.cargo_rebase_to(v_fl2, v_now + interval '10 years') is not null then
    raise exception 'PROOF 32 FAIL: a home in the top moved her';
  end if;
  v_step := public.cargo_ship_step(v_fl, v_now + interval '1 minute');
  if v_step <> 'SAILED' or (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
    raise exception 'PROOF 32 FAIL: her move was not a sailed leg';
  end if;
  perform pg_temp.arrive(v_fl);
  -- away from home with no lap: she sails home, she does not raise E_CARGO_NO_LEG for ever
  update public.fleets f set port_id = v_s1, ready_at = null where f.id = v_fl2;
  v_step := public.cargo_ship_step(v_fl2, now());
  if v_step <> 'SAILED' or (select o.dest_port_id from public.voyages o where o.fleet_id = v_fl2 and o.status = 'SAILING') <> v_d2 then
    raise exception 'PROOF 32 FAIL: away with no lap, she did not sail home: %', v_step;
  end if;
  perform pg_temp.arrive(v_fl2);
  update public.fleets f set ready_at = null where f.id = v_fl2;
  raise notice 'PASS: RICH_STAYS — she waits out the days counted from her last book row, a home in the top holds, the move is one leg, a ship astray sails home';

  -- ── A SHIP MADE LIT ──
  update public.world_config set value = to_jsonb(v_k + 1) where key = 'convoy_ships_per_nation';
  v_o := public.cargo_origins(v_nat);
  v_n := public.cargo_ships_commission(v_nat);
  if v_n <> 1 or (select c.home_port_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = v_k + 1) <> v_o[v_k % cardinality(v_o) + 1]
     or (select f.port_id from public.fleets f where f.id = pg_temp.ship(v_nat, v_k + 1)) <> v_o[v_k % cardinality(v_o) + 1]
     or (select c.based_at from public.cargo_ships c where c.nation_id = v_nat and c.ord = v_k + 1) is null then
    raise exception 'PROOF 32 FAIL: a ship made lit is not at her origin';
  end if;
  raise notice 'PASS: RICH_COMMISSION — ship % at the origin her ord falls on, based', v_k + 1;

  -- ── THE SECOND WRITER OF CROWN_CALL ──
  insert into public.players (company_name, nation_id, ducats) values ('Probe 32 house', v_nat, 0) returning id into v_pl;
  perform pg_temp.purse(v_cap, 500);
  v_flow := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.capital_pays(v_cap, v_nat, v_pl, 'CAPITAL_GIFT', 1000, null, false);
  if not (v_r ? 'waiting') or pg_temp.flows(v_flow) <> '{}'::jsonb then
    raise exception 'PROOF 32 FAIL: lit, a gift the capital cannot pay called: % %', v_r, pg_temp.flows(v_flow);
  end if;
  perform pg_temp.purse(v_cap, 60000);
  v_r := public.capital_pays(v_cap, v_nat, v_pl, 'CAPITAL_GIFT', 1000, null, false);
  if (v_r ->> 'port')::uuid <> v_cap or (v_r ->> 'called')::bigint <> 0 then
    raise exception 'PROOF 32 FAIL: lit, the capital did not pay what it holds: %', v_r;
  end if;
  perform pg_temp.purse(v_cap, 500);
  v_flow := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.capital_pays(v_cap, v_nat, v_pl, 'CAPITAL_GIFT', 1000, null, true);
  if (v_r ->> 'port')::uuid = v_cap or (v_r ->> 'paid')::bigint <> 1000 or v_r ? 'minted' or pg_temp.flows(v_flow) ? 'CROWN_CALL' then
    raise exception 'PROOF 32 FAIL: lit, a founding did not pay from the richest harbour: %', v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'convoy_rich_enabled';
  perform pg_temp.purse(v_cap, 500);
  perform pg_temp.purse(v_d2, 60000000);
  v_flow := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.capital_pays(v_cap, v_nat, v_pl, 'CAPITAL_GIFT', 1000, null, false);
  if (v_r ->> 'called')::bigint <> 500 or not (pg_temp.flows(v_flow) ? 'CROWN_CALL') then
    raise exception 'PROOF 32 FAIL: off, the call is gone: %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'convoy_rich_enabled';
  raise notice 'PASS: RICH_GIFT — lit: waits with no call, pays what the capital holds, a founding pays from the richest harbour; off: the call';

  -- ── OFF MID-LAP ──
  perform pg_temp.purse(v_d2, 60000000);
  v_pl := (select c.player_id from public.cargo_ships c where c.fleet_id = v_fl2);
  v_load := public.convoy_book('LOADED', v_fl2, v_pl, v_d2, 70000);
  if public.cargo_ship_step(v_fl2, now()) <> 'SAILED' then
    raise exception 'PROOF 32 FAIL: she did not leave on the lap';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'convoy_rich_enabled';
  update public.fleets f set ready_at = null where f.id = v_fl3;
  v_step := public.cargo_ship_step(v_fl3, now());
  if v_step <> 'SAILED' or (select c.home_port_id from public.cargo_ships c where c.fleet_id = v_fl3) <> v_cap
     or (select c.based_at from public.cargo_ships c where c.fleet_id = v_fl3) is not null then
    raise exception 'PROOF 32 FAIL: off, an idle ship did not sail back to her capital';
  end if;
  perform pg_temp.arrive(v_fl3);
  v_guard := 0;
  v_now := now();
  v_sum := pg_temp.purses();
  loop
    v_guard := v_guard + 1;
    exit when v_guard > 500;
    if (select f.status from public.fleets f where f.id = v_fl2) = 'SAILING' then
      v_now := pg_temp.arrive(v_fl2);
    end if;
    v_step := public.cargo_ship_step(v_fl2, v_now);
    exit when v_step = 'HOME';
    if v_step = 'IN_PORT' then
      v_now := v_now + interval '61 seconds';
    elsif v_step <> 'SAILED' then
      raise exception 'PROOF 32 FAIL: step % on the lap, switch off', v_step;
    end if;
  end loop;
  if v_step <> 'HOME' or exists (select 1 from public.cargo_ship_aboard(v_fl2))
     or exists (select 1 from public.convoy_cargo k where k.load_id = v_load and k.stage = 'RETURNED' and k.port_id <> v_d2)
     or pg_temp.purses() <> v_sum then
    raise exception 'PROOF 32 FAIL: off mid-lap, her funds stranded or moved: %', v_step;
  end if;
  v_step := public.cargo_ship_step(v_fl2, v_now + interval '1 hour');
  if v_step <> 'SAILED' or (select c.home_port_id from public.cargo_ships c where c.fleet_id = v_fl2) <> v_cap then
    raise exception 'PROOF 32 FAIL: off, she did not sail back to her capital after her lap';
  end if;
  perform pg_temp.arrive(v_fl2);
  if public.cargo_load_room(v_d2, v_nat) <> 0 then
    raise exception 'PROOF 32 FAIL: off, a rich city may load';
  end if;
  update public.fleets f set ready_at = null where f.id = v_fl3;
  perform pg_temp.purse(v_s1, 1000);
  perform pg_temp.purse(v_cap, 1000);
  perform pg_temp.purse(v_s2, 50000);
  v_flow := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.crown_aid(v_cap);
  v_x := pg_temp.flows(v_flow);
  if not (v_x ? 'CROWN_CALL') or (v_x ->> 'CONVOY_LOAD')::int <> 1 or (v_x ? 'CROWN_AID')
     or (select k.port_id from public.convoy_cargo k where k.stage = 'LOADED' and k.player_id in (select c.player_id from public.cargo_ships c where c.nation_id = v_nat) order by k.id desc limit 1) <> v_cap then
    raise exception 'PROOF 32 FAIL: off, the capital does not call and load: % %', v_r, v_x;
  end if;
  raise notice 'PASS: RICH_SWITCH_OFF — her funds returned at the rich city, every ship sails back to her capital, the call and the capital''s load stand: %', v_x;

  -- ── THE KNOB ALONE LIGHTS NOTHING ──
  update public.world_config set value = 'true'::jsonb where key = 'convoy_rich_enabled';
  update public.world_config set value = 'false'::jsonb where key = 'convoys_enabled';
  if public.rich_cities_on() then
    raise exception 'PROOF 32 FAIL: the rule is lit with no ships';
  end if;
  perform pg_temp.purse(v_cap, 10000000);
  perform pg_temp.purse(v_s1, 1000);
  v_flow := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.crown_aid(v_cap);
  if not (pg_temp.flows(v_flow) ? 'CROWN_AID') or public.treasury_balance(v_s1) <> 50000 then
    raise exception 'PROOF 32 FAIL: convoys off, the instant path does not stand: %', v_r;
  end if;
  raise notice 'PASS: RICH_NEEDS_SHIPS — convoys off, the rule is off and the instant aid pays';

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_stub_32;
  alter function voyage.hazard_roll_real_32(uuid, integer) rename to hazard_roll;
end
$$;
