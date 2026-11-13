-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 49 — THE NAVY KEEPS OFF PIRATE PORTS  (migration 0342, owner rows 284, 285; the W19 review's leak, closed everywhere)
-- ═══════════════════════════════════════════════════════════════════════════════
--   The real job, step, patrol builder, call, escort, pay and sail door, through the real voyage engine, the economy CLOSED as prod. A harbour is handed to the Brethren the way the daily count would hand
--   it (its flag row, the home guard disabled by name for the fixture as 0338 and proof 48 do, the flag clock untouched), and the navy is read against it. Every scene ends with W (purses + companies +
--   funds aboard) unchanged. Red first: the file's reader public.navy_harbour_ok is the first thing asked for.
--
-- @pass NP_DARK      navy off, pirates off and pirates on: the job answers the keys it had, she lies up at her station, no NAVY_PAY, W unchanged; the reader: false at Port Royal, true at the capital and at a harbour nobody holds
-- @pass NP_PATROL    lit: the stop the builder would take first, handed to the Brethren, is left out of the patrol (and so is every harbour of theirs); the patrol is still written, and ends at the station
-- @pass NP_CALL      lit: the harbour nearest the site handed to the Brethren, a call sends her to the next nearest; a called ship whose harbour falls before she sails is freed, 'infinity' on the sheet, and sails nowhere
-- @pass NP_ESCORT    lit: the richest cargo ship bound for a harbour the Brethren hold is not escorted (she patrols); the harbour back, she is
-- @pass NP_HOME      lit: her station fallen, her home is the capital (she sails there, her station moves); no hull is laid at a fallen station, and it is once it is back; a patrol's next stop fallen, she ends her patrol
--                    and the station's is dropped and written again without it; the first stop fallen, she lies at her station (IDLE) till it is written again
-- @pass NP_PAY       lit: an hour of upkeep with a ship at the capital, one at a crown harbour, one at a fallen harbour and one at a harbour nobody holds: the crown's and the free one are paid, the fallen one's slice
--                    stays at the capital, nothing reaches the hoard, every ship counts as paid; the same for a ship at sea whose last port fell; the harbour back, it is paid again
-- @pass NP_HANDS     lit: sailing from a fallen harbour she takes no hands from its quay and sails as she is; from a crown harbour she is manned as before
-- @pass NP_TARGETS   the hunt's targets name no harbour the Brethren hold, through the one reader; the rest stand
-- @pass NP_ONLY      every harbour theirs: the patrol builder writes no leg, the call's reader answers no harbour, her step answers IDLE where she lies, the hour moves nothing; no error anywhere
-- @pass NP_MONEY     W unchanged over the whole proof
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_nat uuid;
  v_n   int;
begin
  if to_regprocedure('public.navy_harbour_ok(uuid)') is null or to_regprocedure('public.navy_patrol_drop(bigint)') is null then
    raise exception 'PROOF 49 FAIL: 0342 is not in this world (public.navy_harbour_ok / public.navy_patrol_drop)';
  end if;
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'navy_enabled', 'pirates_bite', 'regard_enabled', 'npc_refits_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  update public.ports p set crew_pool = 2000;

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_49;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$ select false, null::text, 0::numeric, 0::numeric $b$
  $f$;

  -- THE FIGHT, BY NAME (a battle is opened here only to make a call; it is closed DRIVEN_OFF, nothing moves). Empty, the real engine.
  alter function public.fight_sides(uuid, integer, jsonb, jsonb, jsonb) rename to fight_sides_real_49;
  execute $f$
create function public.fight_sides(p_seed uuid, p_round integer, p_a jsonb, p_b jsonb, p_opts jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
as $b$
declare
  v_x text := coalesce(current_setting('byeharu.proof_fight', true), '');
begin
  if v_x = '' then
    return public.fight_sides_real_49(p_seed, p_round, p_a, p_b, p_opts);
  end if;
  return jsonb_build_object('outcome', v_x, 'stood_off', false, 'slipped', false, 'broke_off', false, 'first', 'BOTH', 'rounds_fought', 0, 'rounds', '[]'::jsonb,
    'hull_lost', jsonb_build_object('a', '{}'::jsonb, 'b', '{}'::jsonb), 'hull', jsonb_build_object('a', 0, 'b', 0, 'a_start', 1, 'b_start', 1), 'hits', jsonb_build_object('a', 0, 'b', 0));
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
create function pg_temp.navy_49(p_nation uuid, p_port uuid, p_at timestamptz)
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

  -- she leaves her voyage and lies docked at a harbour, as if she had arrived
  execute $f$
create function pg_temp.dock_49(p_fleet uuid, p_port uuid)
returns void
language sql
as $b$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = p_port, lat = null, lon = null, ready_at = null, version = f.version + 1 where f.id = p_fleet
$b$
  $f$;

  -- a harbour changes hands, as the daily count would have it (the home guard disabled BY NAME for the fixture, as 0338 and proof 48 do; the flag clock, `since`, is not moved). Answers the holder it had.
  execute $f$
create function pg_temp.hand_49(p_port uuid, p_nation uuid)
returns uuid
language plpgsql
as $b$
declare
  v_old uuid := (select a.nation_id from public.port_allegiance a where a.port_id = p_port);
begin
  alter table public.port_allegiance disable trigger port_allegiance_home_never_changes;
  update public.port_allegiance a set nation_id = p_nation where a.port_id = p_port;
  if not found then
    insert into public.port_allegiance (port_id, nation_id) values (p_port, p_nation);
  end if;
  alter table public.port_allegiance enable trigger port_allegiance_home_never_changes;
  return v_old;
end
$b$
  $f$;

  execute $f$
create function pg_temp.flows_49(p_mark bigint, p_kind text)
returns jsonb
language sql
as $b$
  select coalesce(jsonb_agg(jsonb_build_array(p.code, f.ducats) order by f.ducats, p.code), '[]'::jsonb)
    from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > p_mark and f.kind = p_kind
$b$
  $f$;

  -- the scene's ships struck from the rolls (their fleets stay, nowhere), so the next scene's first ship is ord 1 and her station the capital
  execute $f$
create function pg_temp.clear_49()
returns void
language sql
as $b$
  update public.players p set company_name = 'struck ' || substr(md5(gen_random_uuid()::text), 1, 12)
   where p.id in (select n.player_id from public.navy_ships n);
  delete from public.navy_ships n where true;
  update public.navy_realms r set added_at = null, paid_at = null
$b$
  $f$;

  -- a human company of Portugal, her one fleet with 100 hands, the best guns, her hold empty
  execute $f$
create function pg_temp.house_49(p_n int)
returns uuid
language plpgsql
as $b$
declare
  v_uid uuid := ('00000000-0342-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid;
  v_p   uuid := public.new_house(v_uid, 'Casa Costa ' || p_n, 'PRT', 'LIS', 'Costa ' || p_n,
                                 (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Costa ' || p_n, null, false);
  v_f   uuid;
begin
  select id into v_f from public.fleets where player_id = v_p;
  update public.ships set crew = 100, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_f;
  return v_f;
end
$b$
  $f$;

  -- the next cargo ship, at sea with p_ducats aboard, slowed so she stays there: of p_nation, or of any crown but Portugal; bound for a harbour other than p_not (the capital a scene's navy ship lies at)
  execute $f$
create function pg_temp.ship_49(p_ducats bigint, p_at timestamptz, p_nation text default null, p_not uuid default null)
returns uuid
language plpgsql
as $b$
declare
  c    public.cargo_ships%rowtype;
  v_st text;
  v_to uuid;
begin
  for c in select x.*
             from public.cargo_ships x join public.nations n on n.id = x.nation_id join public.fleets f on f.id = x.fleet_id
            where f.status = 'DOCKED' and x.out_load is null
              and ((p_nation is null and n.code <> 'PRT') or n.code = p_nation)
              and not exists (select 1 from public.cargo_ship_aboard(x.fleet_id))
            order by n.code, x.ord loop
    update public.fleets set ready_at = null where id = c.fleet_id;
    perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, p_ducats);
    v_st := public.cargo_ship_step(c.fleet_id, p_at);
    if v_st <> 'SAILED' then
      raise exception 'PROOF 49 FAIL: the cargo ship did not sail: %', v_st;
    end if;
    select v.dest_port_id into v_to from public.voyages v where v.fleet_id = c.fleet_id and v.status = 'SAILING';
    if p_not is null or v_to is distinct from p_not then
      update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
       where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
      perform voyage.recompute_eta((select vo.id from public.voyages vo where vo.fleet_id = c.fleet_id and vo.status = 'SAILING'));
      return c.fleet_id;
    end if;
  end loop;
  raise exception 'PROOF 49 FAIL: no cargo ship left to sail';
end
$b$
  $f$;

  execute $f$
create function pg_temp.lie_by_49(p_fleet uuid, p_target uuid, p_at timestamptz)
returns void
language sql
as $b$
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon, version = f.version + 1
    from voyage.fleet_point(p_target, p_at) p where f.id = p_fleet
$b$
  $f$;

  execute $f$
create function pg_temp.attack_49(p_fleet uuid, p_target uuid, p_at timestamptz)
returns uuid
language sql
as $b$
  select (public.attack_for((select f.player_id from public.fleets f where f.id = p_fleet), p_fleet, p_target, null, p_at) ->> 'battle_id')::uuid
$b$
  $f$;

  -- close a battle at p_at, the fight by name
  execute $f$
create function pg_temp.close_49(p_battle uuid, p_at timestamptz, p_outcome text)
returns jsonb
language plpgsql
as $b$
begin
  update public.battles b set resolves_at = least(b.resolves_at, p_at) where b.id = p_battle;
  perform set_config('byeharu.proof_fight', p_outcome, true);
  if not public.battle_resolve(p_battle, p_at) then
    raise exception 'PROOF 49 FAIL: the battle did not resolve';
  end if;
  perform set_config('byeharu.proof_fight', '', true);
  return (select b.result from public.battles b where b.id = p_battle);
end
$b$
  $f$;

  -- the p_k-th nearest harbour to p_to a course reaches, within a call's reach, that the pirates do not hold: where a called ship may lie
  execute $f$
create function pg_temp.near_49(p_nation uuid, p_to uuid, p_k int default 1)
returns uuid
language plpgsql
as $b$
declare
  r   record;
  v_k int := 0;
begin
  for r in select x.port_id from voyage.reach_from(p_to) x join public.ports p on p.id = x.port_id
            where p.kind = 'HARBOUR' and not p.is_ice_closed and x.port_id <> p_to and x.nm <= public.wc_num('navy_reach_nm') and public.navy_harbour_ok(x.port_id) order by x.nm, x.code loop
    if public.cargo_circuit_plan(p_nation, r.port_id, p_to) #> '{legs,0}' is not null then
      v_k := v_k + 1;
      if v_k = p_k then
        return r.port_id;
      end if;
    end if;
  end loop;
  raise exception 'PROOF 49 FAIL: no harbour % within reach of %', p_k, p_to;
end
$b$
  $f$;

  -- the stops public.navy_patrol_build would take from a station WITHOUT the rule: its own order (the country's first, nearest next), its limit, the pirates' harbours included
  execute $f$
create function pg_temp.cands_49(p_station uuid, p_nation uuid)
returns uuid[]
language sql
as $b$
  select coalesce(array_agg(x.port_id order by x.o), '{}')
    from (select r.port_id, row_number() over (order by coalesce(public.port_nation(r.port_id) = p_nation, false) desc, r.nm, r.code) as o
            from voyage.reach_from(p_station) r join public.ports p on p.id = r.port_id
           where p.kind = 'HARBOUR' and not p.is_ice_closed and r.port_id <> p_station and r.nm <= public.wc_num('navy_reach_nm')) x
   where x.o <= public.wc_int('navy_patrol_stops')
$b$
  $f$;

  -- the patrol of a station: its legs' harbours in order
  execute $f$
create function pg_temp.legs_49(p_station bigint)
returns uuid[]
language sql
as $b$ select coalesce(array_agg(l.to_port order by l.ord), '{}') from public.navy_patrol_legs l where l.station_id = p_station $b$
  $f$;

  -- the plan, run until it has nothing to do (stations, then one patrol a run), at most p_max runs
  execute $f$
create function pg_temp.plan_49(p_nation uuid, p_at timestamptz, p_max int default 20)
returns int
language plpgsql
as $b$
declare
  v_i int := 0;
begin
  while public.navy_plan_step(p_at, p_nation) is not null loop
    v_i := v_i + 1;
    exit when v_i >= p_max;
  end loop;
  return v_i;
end
$b$
  $f$;

  -- every crown's cargo ships and circuits, as the world has them (the escort's ward, the call's ship set upon)
  for v_nat in select g.nation_id from public.great_powers g where not g.pirate loop
    for v_n in 1 .. 2 loop
      perform public.tick_cargo_ships(now(), v_nat);
    end loop;
  end loop;
  create temp table w_49 as select pg_temp.purses() as w0;
end
$$;

-- ── DARK ──
do $$
declare
  v_t    timestamptz := now();
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_por  uuid := (select p.id from public.ports p where p.code = 'POR');
  v_free uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) is null order by p.code limit 1);
  n      uuid;
  v_j    jsonb;
  v_w    bigint;
  v_mark bigint := coalesce((select max(id) from public.treasury_flows), 0);
begin
  if public.economy_closed() is distinct from true then
    raise exception 'PROOF 49 FAIL: the economy is not closed here';
  end if;
  -- the reader
  if public.navy_harbour_ok(v_por) or not public.navy_harbour_ok(v_cap) or (v_free is not null and not public.navy_harbour_ok(v_free))
     or exists (select 1 from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id where g.pirate and public.navy_harbour_ok(a.port_id)) then
    raise exception 'PROOF 49 FAIL: the reader: POR %, capital %, free %', public.navy_harbour_ok(v_por), public.navy_harbour_ok(v_cap), public.navy_harbour_ok(v_free);
  end if;
  n := pg_temp.navy_49(v_nat, v_cap, v_t);
  v_w := pg_temp.purses();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);   -- after her hull is paid for
  -- navy off, pirates off: the job answers the keys it had, she lies up at her station, no pay
  v_j := public.tick_navy(v_t, v_nat);
  if (select string_agg(k, ',' order by k) from jsonb_object_keys(v_j) k) <> 'added,paid,plan,steps' or (v_j -> 'steps' ->> 'LAID_UP')::int is distinct from 1 or (v_j ->> 'paid')::bigint <> 0 then
    raise exception 'PROOF 49 FAIL: dark, the job answers %', v_j;
  end if;
  if (select x.laid_up_at is null from public.navy_ships x where x.fleet_id = n) or (select f.port_id from public.fleets f where f.id = n) <> v_cap then
    raise exception 'PROOF 49 FAIL: dark, she did not lie up at her station';
  end if;
  -- navy off, pirates on (prod, 2026-11-07 17:55 UTC): the same
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  update public.navy_ships x set laid_up_at = null where x.fleet_id = n;
  v_j := public.tick_navy(v_t + interval '1 minute', v_nat);
  if (select string_agg(k, ',' order by k) from jsonb_object_keys(v_j) k) <> 'added,paid,plan,steps' or (v_j -> 'steps' ->> 'LAID_UP')::int is distinct from 1 or (v_j ->> 'paid')::bigint <> 0
     or (select x.laid_up_at is null from public.navy_ships x where x.fleet_id = n) then
    raise exception 'PROOF 49 FAIL: navy off and pirates on, the job answers %', v_j;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_bite';
  if pg_temp.flows_49(v_mark, 'NAVY_PAY') <> '[]'::jsonb or pg_temp.flows_49(v_mark, 'BUILD_NAVY') <> '[]'::jsonb or pg_temp.purses() <> v_w then
    raise exception 'PROOF 49 FAIL: dark, gold moved: %', pg_temp.flows_49(v_mark, 'NAVY_PAY');
  end if;
  raise notice 'PASS: NP_DARK — keys %, laid up at her station in both darks, no flow, W unchanged; the reader refuses % harbours (theirs), takes the capital and %', (select string_agg(k, ',' order by k) from jsonb_object_keys(v_j) k),
    (select count(*) from public.ports p where p.kind = 'HARBOUR' and not public.navy_harbour_ok(p.id)), case when v_free is null then 'no free harbour here' else 'a free harbour' end;
end
$$;

update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';

-- ── A PATROL IS WRITTEN WITHOUT THEIR HARBOUR ──
do $$
declare
  v_t    timestamptz := now();
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
  n      uuid;
  v_st   bigint;
  v_stop uuid;
  v_hold uuid;
  v_c    uuid[];
  v_legs uuid[];
  v_s    text;
  v_stops int := public.wc_int('navy_patrol_stops');
begin
  perform pg_temp.clear_49();
  n := pg_temp.navy_49(v_nat, v_cap, v_t);
  if public.navy_plan_step(v_t, v_nat) <> 'STATIONS' then
    raise exception 'PROOF 49 FAIL: the stations were not planned';
  end if;
  select s.id into v_st from public.navy_stations s where s.nation_id = v_nat and s.port_id = v_cap and s.retired_at is null;
  if v_st is null then
    raise exception 'PROOF 49 FAIL: the capital is no station';
  end if;
  -- the stop the builder would take FIRST (its own order, with a course from the station), handed to the Brethren; the builder's limit widened so the handed harbour, now foreign, is still inside what it would take without the rule
  update public.world_config set value = to_jsonb(12) where key = 'navy_patrol_stops';
  select c.port into v_stop from unnest(pg_temp.cands_49(v_cap, v_nat)) with ordinality c(port, o)
   where public.cargo_circuit_plan(v_nat, v_cap, c.port) #> '{legs,0}' is not null order by c.o limit 1;
  if v_stop is null then
    raise exception 'PROOF 49 FAIL: no stop with a course from the capital';
  end if;
  v_hold := pg_temp.hand_49(v_stop, v_pir);
  v_c := pg_temp.cands_49(v_cap, v_nat);
  if not (v_stop = any (v_c)) then
    raise exception 'PROOF 49 FAIL: the scene is vacuous: % is not among the % stops the builder would take without the rule', (select p.code from public.ports p where p.id = v_stop), cardinality(v_c);
  end if;
  v_s := public.navy_plan_step(v_t, v_nat);
  if v_s is distinct from 'PATROL' or (select s.legs_at from public.navy_stations s where s.id = v_st) is null then
    raise exception 'PROOF 49 FAIL: the capital''s patrol was not written: plan %, stations %', v_s,
      (select jsonb_agg(jsonb_build_array(s.id, p.code, s.rank, s.legs_at, s.retired_at) order by s.rank) from public.navy_stations s join public.ports p on p.id = s.port_id where s.nation_id = v_nat);
  end if;
  v_legs := pg_temp.legs_49(v_st);
  if cardinality(v_legs) < 3 or v_legs[cardinality(v_legs)] <> v_cap then
    raise exception 'PROOF 49 FAIL: the patrol is % legs and ends at %', cardinality(v_legs), (select p.code from public.ports p where p.id = v_legs[cardinality(v_legs)]);
  end if;
  if v_stop = any (v_legs) or exists (select 1 from unnest(v_legs) l where not public.navy_harbour_ok(l)) then
    raise exception 'PROOF 49 FAIL: the patrol calls at a harbour the Brethren hold: %', (select jsonb_agg(p.code) from unnest(v_legs) with ordinality l(port, o) join public.ports p on p.id = l.port);
  end if;
  perform pg_temp.hand_49(v_stop, v_hold);
  update public.world_config set value = to_jsonb(v_stops) where key = 'navy_patrol_stops';
  if pg_temp.purses() <> (select w0 from w_49) then
    raise exception 'PROOF 49 FAIL: writing a patrol moved gold';
  end if;
  raise notice 'PASS: NP_PATROL — % (the builder''s first stop) handed to the Brethren is left out; % legs written, ending at the station', (select p.code from public.ports p where p.id = v_stop), cardinality(v_legs);
end
$$;

-- ── A CALL GOES TO THE NEXT HARBOUR; A HARBOUR THAT FALLS BEFORE SHE SAILS FREES HER ──
do $$
declare
  v_t    timestamptz := now();
  v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
  a      uuid;
  d      uuid;
  v_nat  uuid;
  v_near uuid;
  v_hold uuid;
  v_to   uuid;
  v_from uuid;
  v_q    uuid;
  n      uuid;
  n2     uuid;
  b      uuid;
  v_vo   public.voyages%rowtype;
  v_s    text;
  v_hold2 uuid;
  v_keep numeric := public.wc_num('battle_seconds');
  v_keep_round jsonb := (select c.value from public.world_config c where c.key = 'battle_round_seconds');   -- 0357: null in a world before it, where both lines below write nothing
begin
  perform pg_temp.clear_49();
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  update public.world_config set value = '86400'::jsonb where key = 'battle_seconds';   -- a day-long battle, so both ships are in time and both are called (as proof 40 reads a call)
  update public.world_config set value = '86400'::jsonb where key = 'battle_round_seconds';   -- 0357: an attack's clock is the lesser of battle_seconds and its rounds, so a day-long battle needs both
  a := pg_temp.house_49(1);
  d := pg_temp.ship_49(100000, v_t);
  v_nat := public.crown_nation(d);
  select public.harbour_nearest(p.lat::float8, p.lon::float8) into v_near from voyage.fleet_point(d, v_t) p;
  v_hold := pg_temp.hand_49(v_near, v_pir);
  select public.harbour_nearest(p.lat::float8, p.lon::float8) into v_to from voyage.fleet_point(d, v_t) p;
  if v_to is null or v_to = v_near or not public.navy_harbour_ok(v_to) then
    raise exception 'PROOF 49 FAIL: with % handed to the Brethren the call''s reader answers %', (select p.code from public.ports p where p.id = v_near), (select p.code from public.ports p where p.id = v_to);
  end if;
  v_from := pg_temp.near_49(v_nat, v_to, 1);
  v_q := pg_temp.near_49(v_nat, v_to, 2);
  n := pg_temp.navy_49(v_nat, v_from, v_t);
  n2 := pg_temp.navy_49(v_nat, v_q, v_t);
  update public.fleets f set ready_at = v_t + interval '10 minutes' where f.id = n2;   -- her port time is not over: the call takes her, she sails at her next step
  perform pg_temp.lie_by_49(a, d, v_t);
  b := pg_temp.attack_49(a, d, v_t);
  select * into v_vo from public.voyages v where v.fleet_id = n and v.status = 'SAILING';
  if (select x.mission || ':' || x.called_to::text from public.navy_ships x where x.fleet_id = n) <> 'REINFORCE:' || v_to::text or v_vo.id is null or v_vo.dest_port_id <> v_to or v_vo.origin_port_id <> v_from then
    raise exception 'PROOF 49 FAIL: the call did not send her to the next harbour: % %', (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n), to_jsonb(v_vo) - 'path' - 'speed_profile';
  end if;
  if (select x.mission || ':' || x.called_to::text from public.navy_ships x where x.fleet_id = n2) <> 'REINFORCE:' || v_to::text or exists (select 1 from public.voyages v where v.fleet_id = n2 and v.status = 'SAILING') then
    raise exception 'PROOF 49 FAIL: the second ship was not called, or sailed before her port time: %', (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n2);
  end if;
  -- the harbour falls to the Brethren before the second ship sails: at her step she is freed, 'infinity' on the sheet, and sails nowhere
  v_hold2 := pg_temp.hand_49(v_to, v_pir);
  v_s := public.navy_ship_step(n2, v_t + interval '11 minutes');
  if v_s <> 'IDLE' or exists (select 1 from public.voyages v where v.fleet_id = n2 and v.status = 'SAILING')
     or (select x.mission || ':' || coalesce(x.called_to::text, '-') || ':' || coalesce(x.battle_id::text, '-') from public.navy_ships x where x.fleet_id = n2) <> 'PATROL:-:-'
     or (select bs.arrives_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n2) <> 'infinity'::timestamptz then
    raise exception 'PROOF 49 FAIL: her harbour fallen, the called ship was not freed: % % %', v_s, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n2),
      (select bs.arrives_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n2);
  end if;
  perform pg_temp.hand_49(v_to, v_hold2);
  perform pg_temp.hand_49(v_near, v_hold);
  perform pg_temp.close_49(b, v_t + interval '1 second', 'DRIVEN_OFF');
  update public.world_config set value = to_jsonb(v_keep) where key = 'battle_seconds';
  update public.world_config set value = v_keep_round where key = 'battle_round_seconds';
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
  if pg_temp.purses() <> (select w0 from w_49) then
    raise exception 'PROOF 49 FAIL: the call moved gold';
  end if;
  raise notice 'PASS: NP_CALL — % handed to the Brethren, the call went to % (from %); the second ship''s harbour fell before she sailed: freed, infinity, nowhere', (select p.code from public.ports p where p.id = v_near),
    (select p.code from public.ports p where p.id = v_to), (select p.code from public.ports p where p.id = v_from);
end
$$;

-- ── AN ESCORT NEVER FOLLOWS INTO THEIR HARBOUR ──
do $$
declare
  v_t    timestamptz := now();
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
  n      uuid;
  c      uuid;
  v_x    uuid;
  v_hold uuid;
  v_s    text;
begin
  perform pg_temp.clear_49();
  n := pg_temp.navy_49(v_nat, v_cap, v_t);
  c := pg_temp.ship_49(100000, v_t, 'PRT', v_cap);
  select v.dest_port_id into v_x from public.voyages v where v.fleet_id = c and v.status = 'SAILING';
  v_hold := pg_temp.hand_49(v_x, v_pir);
  v_s := public.navy_escort_step(n, v_cap, true, v_t);
  if v_s is not null or (select x.mission || ':' || coalesce(x.escort_of::text, '-') from public.navy_ships x where x.fleet_id = n) <> 'PATROL:-' or exists (select 1 from public.voyages v where v.fleet_id = n and v.status = 'SAILING') then
    raise exception 'PROOF 49 FAIL: she escorted a cargo ship into a harbour the Brethren hold: % %', v_s, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  perform pg_temp.hand_49(v_x, v_hold);
  v_s := public.navy_escort_step(n, v_cap, true, v_t);
  if v_s is distinct from 'ESCORT' or (select x.mission || ':' || x.escort_of::text from public.navy_ships x where x.fleet_id = n) <> 'ESCORT:' || c::text
     or (select v.dest_port_id from public.voyages v where v.fleet_id = n and v.status = 'SAILING') is distinct from v_x then
    raise exception 'PROOF 49 FAIL: the harbour back, she did not escort: % %', v_s, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  perform pg_temp.dock_49(c, v_x);   -- her ward in port: no funds at sea, so no later scene's last ship is an escort
  if pg_temp.purses() <> (select w0 from w_49) then
    raise exception 'PROOF 49 FAIL: the escort moved gold';
  end if;
  raise notice 'PASS: NP_ESCORT — the richest cargo ship bound for % (the Brethren''s): not escorted; the harbour back: escorted there', (select p.code from public.ports p where p.id = v_x);
end
$$;

-- ── A HARBOUR FALLS UNDER HER: HER HOME, A HULL'S STATION, A PATROL ALREADY WRITTEN ──
do $$
declare
  v_t    timestamptz := now();
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
  n      uuid;
  n2     uuid;
  n3     uuid;
  v_s2   uuid;
  v_st   bigint;
  v_hold uuid;
  v_hold2 uuid;
  v_s    text;
  v_legs uuid[];
  v_l2   uuid;
  v_l1   uuid;
  v_add  text;
begin
  perform pg_temp.clear_49();
  n := pg_temp.navy_49(v_nat, v_cap, v_t);
  perform pg_temp.plan_49(v_nat, v_t);
  select s.id into v_st from public.navy_stations s where s.nation_id = v_nat and s.port_id = v_cap and s.retired_at is null;
  v_s2 := public.navy_station_of(v_nat, 2);
  if v_s2 is null or v_s2 = v_cap then
    raise exception 'PROOF 49 FAIL: the scene needs a second station';
  end if;
  -- (1) her station falls under her: her home is the capital; she sails there and her station moves
  n2 := pg_temp.navy_49(v_nat, v_s2, v_t);
  v_hold := pg_temp.hand_49(v_s2, v_pir);
  v_s := public.navy_ship_step(n2, v_t);
  if v_s <> 'SAILED' or (select v.dest_port_id from public.voyages v where v.fleet_id = n2 and v.status = 'SAILING') is distinct from v_cap
     or (select x.station_port from public.navy_ships x where x.fleet_id = n2) <> v_cap then
    raise exception 'PROOF 49 FAIL: her station fallen, she did not sail for the capital: % % %', v_s, (select p.code from public.voyages v join public.ports p on p.id = v.dest_port_id where v.fleet_id = n2 and v.status = 'SAILING'),
      (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n2);
  end if;
  -- the capital fallen too: no crown harbour to go to, she stays where she lies, no error
  v_hold2 := pg_temp.hand_49(v_cap, v_pir);
  v_s := public.navy_ship_step(n, v_t);
  if v_s <> 'IDLE' or exists (select 1 from public.voyages v where v.fleet_id = n and v.status = 'SAILING') then
    raise exception 'PROOF 49 FAIL: no crown harbour at all, she did not stay: %', v_s;
  end if;
  perform pg_temp.hand_49(v_cap, v_hold2);
  -- (2) no hull is laid at a fallen station: ord 2's station is the fallen one; the realm waits, and builds there once it is back
  update public.players p set company_name = 'struck ' || substr(md5(gen_random_uuid()::text), 1, 12) where p.id = (select x.player_id from public.navy_ships x where x.fleet_id = n2);
  delete from public.navy_ships x where x.fleet_id = n2;
  update public.navy_realms r set ships = 2, added_at = null where r.nation_id = v_nat;
  v_add := public.navy_add(v_t, v_nat);
  if v_add is not null or exists (select 1 from public.navy_ships x where x.nation_id = v_nat and x.ord = 2) then
    raise exception 'PROOF 49 FAIL: a hull was laid at a station the Brethren hold: %', v_add;
  end if;
  perform pg_temp.hand_49(v_s2, v_hold);
  v_add := public.navy_add(v_t, v_nat);
  if v_add is distinct from 'BUILT' or (select x.station_port from public.navy_ships x where x.nation_id = v_nat and x.ord = 2) <> v_s2
     or (select f.port_id from public.fleets f join public.navy_ships x on x.fleet_id = f.id where x.nation_id = v_nat and x.ord = 2) <> v_s2 then
    raise exception 'PROOF 49 FAIL: the station back, no hull was laid there: %', v_add;
  end if;
  select x.fleet_id into n3 from public.navy_ships x where x.nation_id = v_nat and x.ord = 2;
  -- (3) a patrol already written whose next stop falls: she ends her patrol at the stop before it and sails home; the station's patrol is dropped and written again without the fallen stop
  v_legs := pg_temp.legs_49(v_st);
  if cardinality(v_legs) < 3 then
    raise exception 'PROOF 49 FAIL: the scene needs a patrol of three legs or more at the capital, it has %', cardinality(v_legs);
  end if;
  v_l2 := v_legs[2];
  perform pg_temp.dock_49(n, v_cap);
  update public.navy_ships x set patrol = null, leg = 0, station_port = v_cap where x.fleet_id = n;
  v_s := public.navy_ship_step(n, v_t);
  if v_s <> 'SAILED' or (select v.dest_port_id from public.voyages v where v.fleet_id = n and v.status = 'SAILING') is distinct from v_legs[1] then
    raise exception 'PROOF 49 FAIL: she did not sail her first leg: %', v_s;
  end if;
  v_hold := pg_temp.hand_49(v_l2, v_pir);
  perform pg_temp.dock_49(n, v_legs[1]);
  v_s := public.navy_ship_step(n, v_t + interval '1 hour');
  if v_s <> 'SAILED' or (select v.dest_port_id from public.voyages v where v.fleet_id = n and v.status = 'SAILING') is distinct from v_cap
     or (select x.patrol is not null or x.leg <> 0 from public.navy_ships x where x.fleet_id = n)
     or cardinality(pg_temp.legs_49(v_st)) <> 0 or (select s.legs_at from public.navy_stations s where s.id = v_st) is not null then
    raise exception 'PROOF 49 FAIL: the next stop fallen, she did not end her patrol and sail home, or the patrol was not dropped: % % legs %', v_s,
      (select p.code from public.voyages v join public.ports p on p.id = v.dest_port_id where v.fleet_id = n and v.status = 'SAILING'), cardinality(pg_temp.legs_49(v_st));
  end if;
  if public.navy_plan_step(v_t + interval '1 hour', v_nat) <> 'PATROL' then
    raise exception 'PROOF 49 FAIL: the dropped patrol was not written again';
  end if;
  v_legs := pg_temp.legs_49(v_st);
  if cardinality(v_legs) < 2 or v_l2 = any (v_legs) or exists (select 1 from unnest(v_legs) l where not public.navy_harbour_ok(l)) then
    raise exception 'PROOF 49 FAIL: the patrol written again still calls at the fallen stop: %', (select jsonb_agg(p.code) from unnest(v_legs) with ordinality l(port, o) join public.ports p on p.id = l.port);
  end if;
  -- (4) the first stop of a written patrol falls: at her station she lies (IDLE), the patrol is dropped and written again without it, and then she sails
  v_l1 := v_legs[1];
  v_hold2 := pg_temp.hand_49(v_l1, v_pir);
  perform pg_temp.dock_49(n, v_cap);
  update public.navy_ships x set patrol = null, leg = 0 where x.fleet_id = n;
  v_s := public.navy_ship_step(n, v_t + interval '2 hours');
  if v_s <> 'IDLE' or cardinality(pg_temp.legs_49(v_st)) <> 0 or (select s.legs_at from public.navy_stations s where s.id = v_st) is not null then
    raise exception 'PROOF 49 FAIL: the first stop fallen, she did not lie at her station with the patrol dropped: % legs %', v_s, cardinality(pg_temp.legs_49(v_st));
  end if;
  if public.navy_plan_step(v_t + interval '2 hours', v_nat) <> 'PATROL' then
    raise exception 'PROOF 49 FAIL: the dropped patrol (first stop) was not written again';
  end if;
  v_s := public.navy_ship_step(n, v_t + interval '2 hours 1 minute');
  if v_s <> 'SAILED' or v_l1 = any (pg_temp.legs_49(v_st)) or not public.navy_harbour_ok((select v.dest_port_id from public.voyages v where v.fleet_id = n and v.status = 'SAILING')) then
    raise exception 'PROOF 49 FAIL: the patrol written again, she did not sail its first leg to an open harbour: %', v_s;
  end if;
  perform pg_temp.hand_49(v_l1, v_hold2);
  perform pg_temp.hand_49(v_l2, v_hold);
  if pg_temp.purses() <> (select w0 from w_49) then
    raise exception 'PROOF 49 FAIL: going home moved gold';
  end if;
  raise notice 'PASS: NP_HOME — % fallen: home is the capital, no hull laid there till it is back; stop % fallen: patrol ended, dropped, written again without it; first stop % fallen: IDLE, written again, sailed',
    (select p.code from public.ports p where p.id = v_s2), (select p.code from public.ports p where p.id = v_l2), (select p.code from public.ports p where p.id = v_l1);
end
$$;

-- ── AN HOUR OF UPKEEP, WITH A SHIP AT A FALLEN HARBOUR ──
do $$
declare
  v_t    timestamptz := now();
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
  v_slice bigint := round(public.wc_num('navy_upkeep_day') / 24);
  v_s2   uuid;
  v_h3   uuid;
  v_free uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) is null order by p.code limit 1);
  n1     uuid;
  n2     uuid;
  n3     uuid;
  n4     uuid;
  v_hold uuid;
  v_mark bigint;
  v_w    bigint;
  v_hoard bigint;
  v_a    bigint;
  v_want jsonb;
  v_k    int;
begin
  perform pg_temp.clear_49();
  v_s2 := public.navy_station_of(v_nat, 2);
  select c.port into v_h3 from unnest(pg_temp.cands_49(v_cap, v_nat)) with ordinality c(port, o) where c.port not in (v_cap, v_s2) and public.navy_harbour_ok(c.port) order by c.o limit 1;
  if v_s2 is null or v_h3 is null then
    raise exception 'PROOF 49 FAIL: the scene needs a second station and a third harbour';
  end if;
  n1 := pg_temp.navy_49(v_nat, v_cap, v_t);
  n2 := pg_temp.navy_49(v_nat, v_s2, v_t);
  n3 := pg_temp.navy_49(v_nat, v_h3, v_t);
  if v_free is not null then
    n4 := pg_temp.navy_49(v_nat, v_free, v_t);
  end if;
  v_hold := pg_temp.hand_49(v_h3, v_pir);
  update public.navy_realms r set paid_at = null where r.nation_id = v_nat;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_w := pg_temp.purses();
  v_hoard := public.pirate_hoard();
  v_a := public.navy_pay(v_t, v_nat);
  v_k := 1 + case when n4 is null then 0 else 1 end;
  v_want := jsonb_build_array(jsonb_build_array((select p.code from public.ports p where p.id = v_cap), -v_k * v_slice))
            || (select jsonb_agg(jsonb_build_array(p.code, v_slice) order by p.code) from public.ports p where p.id in (v_s2, v_free));
  if v_a <> v_k * v_slice or pg_temp.flows_49(v_mark, 'NAVY_PAY') <> v_want then
    raise exception 'PROOF 49 FAIL: the hour: % %, wanted %', v_a, pg_temp.flows_49(v_mark, 'NAVY_PAY'), v_want;
  end if;
  if public.pirate_hoard() <> v_hoard or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.port_id = v_h3) then
    raise exception 'PROOF 49 FAIL: the hoard took her slice: % -> %', v_hoard, public.pirate_hoard();
  end if;
  if exists (select 1 from public.navy_ships x where x.nation_id = v_nat and x.unpaid_since is not null) then
    raise exception 'PROOF 49 FAIL: a ship counts as unpaid: %', (select jsonb_agg(x.ord) from public.navy_ships x where x.nation_id = v_nat and x.unpaid_since is not null);
  end if;
  if pg_temp.purses() <> v_w then
    raise exception 'PROOF 49 FAIL: the hour minted or lost gold';
  end if;
  -- at sea, her last port the fallen harbour: the same
  update public.fleets f set status = 'SAILING', port_id = null, lat = null, lon = null where f.id = n3;
  update public.navy_ships x set last_port = v_h3 where x.fleet_id = n3;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_a := public.navy_pay(v_t + interval '1 hour', v_nat);
  if v_a <> v_k * v_slice or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.port_id = v_h3) or public.pirate_hoard() <> v_hoard then
    raise exception 'PROOF 49 FAIL: at sea from a fallen harbour, the hour: % %', v_a, pg_temp.flows_49(v_mark, 'NAVY_PAY');
  end if;
  -- the harbour back: her last port is paid, as before this file
  perform pg_temp.hand_49(v_h3, v_hold);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_a := public.navy_pay(v_t + interval '2 hours', v_nat);
  if v_a <> (v_k + 1) * v_slice or not exists (select 1 from public.treasury_flows f where f.id > v_mark and f.port_id = v_h3 and f.ducats = v_slice) then
    raise exception 'PROOF 49 FAIL: the harbour back, it was not paid: % %', v_a, pg_temp.flows_49(v_mark, 'NAVY_PAY');
  end if;
  update public.fleets f set status = 'DOCKED', port_id = v_h3 where f.id = n3;
  if pg_temp.purses() <> v_w then
    raise exception 'PROOF 49 FAIL: the hours minted or lost gold';
  end if;
  raise notice 'PASS: NP_PAY — % d. a ship: the crown harbour % and % paid, the fallen % not (her slice stayed at the capital, the hoard unmoved, she counts as paid), at sea the same; the harbour back, paid', v_slice,
    (select p.code from public.ports p where p.id = v_s2), case when v_free is null then 'no free harbour here' else (select p.code from public.ports p where p.id = v_free) end, (select p.code from public.ports p where p.id = v_h3);
end
$$;

-- ── NO HANDS FROM THEIR QUAY ──
do $$
declare
  v_t    timestamptz := now();
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
  v_s2   uuid := public.navy_station_of((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'), 2);
  n      uuid;
  v_hold uuid;
  v_leg  jsonb;
  v_need int;
  v_pool int;
  v_s    text;
begin
  perform pg_temp.clear_49();
  n := pg_temp.navy_49(v_nat, v_s2, v_t);
  v_need := (select c.crew_required from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = n);
  update public.ships s set crew = 10 where s.fleet_id = n;
  v_leg := public.cargo_circuit_plan(v_nat, v_s2, v_cap) #> '{legs,0}';
  if v_leg is null then
    raise exception 'PROOF 49 FAIL: no course from the second station to the capital';
  end if;
  v_hold := pg_temp.hand_49(v_s2, v_pir);
  v_pool := (select p.crew_pool from public.ports p where p.id = v_s2);
  v_s := public.navy_sail(n, v_s2, voyage.segments_from_course(v_leg -> 'course'), v_cap, null, 0, v_t);
  if v_s <> 'SAILED' or (select s.crew from public.ships s where s.fleet_id = n) <> 10 or (select p.crew_pool from public.ports p where p.id = v_s2) <> v_pool then
    raise exception 'PROOF 49 FAIL: she took hands from a quay the Brethren hold: % crew %, pool % -> %', v_s, (select s.crew from public.ships s where s.fleet_id = n), v_pool, (select p.crew_pool from public.ports p where p.id = v_s2);
  end if;
  perform pg_temp.hand_49(v_s2, v_hold);
  -- from a crown harbour she is manned, as before
  perform pg_temp.dock_49(n, v_s2);
  v_s := public.navy_sail(n, v_s2, voyage.segments_from_course(v_leg -> 'course'), v_cap, null, 0, v_t + interval '1 hour');
  if v_s <> 'SAILED' or (select s.crew from public.ships s where s.fleet_id = n) <> v_need or (select p.crew_pool from public.ports p where p.id = v_s2) <> v_pool - (v_need - 10) then
    raise exception 'PROOF 49 FAIL: from her own harbour she was not manned: % crew %, pool %', v_s, (select s.crew from public.ships s where s.fleet_id = n), (select p.crew_pool from public.ports p where p.id = v_s2);
  end if;
  if pg_temp.purses() <> (select w0 from w_49) then
    raise exception 'PROOF 49 FAIL: hands moved gold';
  end if;
  raise notice 'PASS: NP_HANDS — from % fallen she sailed with her 10 hands and the quay kept its %; from it as a crown harbour she took % and sailed full', (select p.code from public.ports p where p.id = v_s2), v_pool, v_need - 10;
end
$$;

-- ── THE HUNT'S TARGETS, THROUGH THE ONE READER ──
do $$
declare
  v_t    timestamptz := now();
  v_cap  uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
  v_h    uuid;
  v_hold uuid;
  v_k    int;
begin
  select t.port_id into v_h from public.navy_hunt_targets(v_cap, v_t) t where t.port_id <> v_cap order by t.nm, t.port_id limit 1;
  v_k := (select count(*) from public.navy_hunt_targets(v_cap, v_t));
  if v_h is null or v_k < 2 then
    raise exception 'PROOF 49 FAIL: the capital has no target but its own sea';
  end if;
  v_hold := pg_temp.hand_49(v_h, v_pir);
  if exists (select 1 from public.navy_hunt_targets(v_cap, v_t) t where t.port_id = v_h or not public.navy_harbour_ok(t.port_id))
     or (select count(*) from public.navy_hunt_targets(v_cap, v_t)) not between v_k - 1 and v_k then
    raise exception 'PROOF 49 FAIL: the targets name a harbour the Brethren hold: %', (select jsonb_agg(p.code) from public.navy_hunt_targets(v_cap, v_t) t join public.ports p on p.id = t.port_id where not public.navy_harbour_ok(t.port_id));
  end if;
  perform pg_temp.hand_49(v_h, v_hold);
  raise notice 'PASS: NP_TARGETS — % handed to the Brethren is no target of the capital; % of % seas stand', (select p.code from public.ports p where p.id = v_h), (select count(*) from public.navy_hunt_targets(v_cap, v_t)), v_k;
end
$$;

-- ── EVERY HARBOUR THEIRS: NOTHING SAILS, NOTHING MOVES, NOTHING BREAKS ──
do $$
declare
  v_t    timestamptz := now();
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
  v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
  v_por  public.ports%rowtype;
  n      uuid;
  v_st   bigint;
  v_s    text;
  v_mark bigint;
  v_w    bigint;
  v_a    bigint;
begin
  perform pg_temp.clear_49();
  n := pg_temp.navy_49(v_nat, v_cap, v_t);
  select s.id into v_st from public.navy_stations s where s.nation_id = v_nat and s.port_id = v_cap and s.retired_at is null;
  select * into v_por from public.ports p where p.code = 'POR';
  create temp table flags_49 on commit drop as select a.port_id, a.nation_id from public.port_allegiance a;
  alter table public.port_allegiance disable trigger port_allegiance_home_never_changes;
  update public.port_allegiance a set nation_id = v_pir;
  insert into public.port_allegiance (port_id, nation_id) select p.id, v_pir from public.ports p where p.kind = 'HARBOUR' and not exists (select 1 from public.port_allegiance a where a.port_id = p.id);
  alter table public.port_allegiance enable trigger port_allegiance_home_never_changes;
  if exists (select 1 from public.ports p where p.kind = 'HARBOUR' and public.navy_harbour_ok(p.id)) then
    raise exception 'PROOF 49 FAIL: the scene did not hand every harbour over';
  end if;
  perform public.navy_patrol_drop(v_st);
  v_a := public.navy_patrol_build(v_st, v_t);
  if v_a <> 0 or cardinality(pg_temp.legs_49(v_st)) <> 0 then
    raise exception 'PROOF 49 FAIL: a patrol was written with every harbour theirs: % legs', v_a;
  end if;
  if public.harbour_nearest(v_por.lat::float8, v_por.lon::float8) is not null or public.harbour_nearest(38.7, -9.1) is not null then
    raise exception 'PROOF 49 FAIL: the call''s reader named a harbour with every harbour theirs';
  end if;
  v_s := public.navy_ship_step(n, v_t);
  if v_s <> 'IDLE' or exists (select 1 from public.voyages v where v.fleet_id = n and v.status = 'SAILING') then
    raise exception 'PROOF 49 FAIL: with every harbour theirs she did not stay: %', v_s;
  end if;
  update public.navy_realms r set paid_at = null where r.nation_id = v_nat;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_w := pg_temp.purses();
  v_a := public.navy_pay(v_t, v_nat);
  if v_a <> 0 or pg_temp.flows_49(v_mark, 'NAVY_PAY') <> '[]'::jsonb or (select x.unpaid_since from public.navy_ships x where x.fleet_id = n) is not null or pg_temp.purses() <> v_w then
    raise exception 'PROOF 49 FAIL: with every harbour theirs the hour moved %: %', v_a, pg_temp.flows_49(v_mark, 'NAVY_PAY');
  end if;
  alter table public.port_allegiance disable trigger port_allegiance_home_never_changes;
  delete from public.port_allegiance a where not exists (select 1 from flags_49 f where f.port_id = a.port_id);
  update public.port_allegiance a set nation_id = f.nation_id from flags_49 f where f.port_id = a.port_id;
  alter table public.port_allegiance enable trigger port_allegiance_home_never_changes;
  if (select count(*) from public.ports p where p.kind = 'HARBOUR' and not public.navy_harbour_ok(p.id)) <> (select count(*) from flags_49 f join public.great_powers g on g.nation_id = f.nation_id join public.ports p on p.id = f.port_id where g.pirate and p.kind = 'HARBOUR') then
    raise exception 'PROOF 49 FAIL: the flags were not put back';
  end if;
  raise notice 'PASS: NP_ONLY — every harbour theirs: no leg, no harbour for a call, IDLE where she lies, the hour moved nothing, no error';
end
$$;

do $$
begin
  if pg_temp.purses() <> (select w0 from w_49) then
    raise exception 'PROOF 49 FAIL: W moved over the proof: % -> %', (select w0 from w_49), pg_temp.purses();
  end if;
  raise notice 'PASS: NP_MONEY — W % unchanged over the whole proof', (select w0 from w_49);
end
$$;
