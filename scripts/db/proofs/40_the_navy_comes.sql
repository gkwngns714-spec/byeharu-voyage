-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 40 — THE NAVY COMES  (migration 0333, owner rows 285, 286, W13 of docs/WORLD_POWERS.md)
--
--   0333's self-assert reads the catalog only (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof lights both switches and runs the REAL attack, the REAL voyage engine, the REAL step and the REAL close.
--   THE ECONOMY IS CLOSED HERE, as on prod. The sea is quiet. Instants are handed to every call. The clock a scene is judged by is written on the battle, so the bar is exact whatever the probe world's distances are.
--   The fight's outcome is asked for by name; NC_REAL takes what the real engine gives. WANTED is W14's (0334): this proof holds what it reads, and the row itself when that file is in the world.
--
-- @pass NC_DARK        off: both doors refuse, no card key; attacks lit and navy off: no ship is called, the close still says so, and nothing else moved
-- @pass NC_CALL        a call is a real voyage from where she lies to the harbour nearest the site: she sails now, on the sheet with her voyage's eta, and it costs no gold
-- @pass NC_JOINS       a ship whose arrival is exactly the battle's clock is in the fight, on the side set upon, and the report says so
-- @pass NC_ONE_MINUTE  a ship one minute past the clock is not in the fight, whether the job ran before she arrived or after; she is on the list, freed, and she sails on; the hook is called
-- @pass NC_WANTED      what W14 reads: a ship in time stands on the sheet at or before the clock, a late one after it, the ship set upon apart; with 0334 in the world, the row itself, once
-- @pass NC_AT_SEA      a ship at sea finishes her leg: the voyage is not cut, and from that port she sails on, her arrival re-read; a storm that makes her late counts
-- @pass NC_ONCE        no ship is counted twice: one call a ship, one line on a sheet, a retry changes nothing, and a called ship cannot be attacked
-- @pass NC_BOUND       at most navy_call_ships answer; if none can be in time one sails, the soonest; out of navy_reach_nm none; unpaid, laid up and wrecked ships do not
-- @pass NC_ESCORT      the last ship of the line follows the richest cargo ship's next leg; she joins at once and is held, and goes on escorting; no funds or navy_escorts 0, she patrols
-- @pass NC_SPOILS      gold and hands are the ship set upon's alone: every purse summed moves 0 with the navy on the sheet
-- @pass NC_NAVY_TARGET a navy ship can be attacked: regard_attack_navy, attack_ship_minutes, your own refused, a merchant still refused, no gold, her card offers it
-- @pass NC_NAVY_SUNK   every hull at 0: regard_sink, her station takes her; a ship called and sunk in port is found by her step
-- @pass NC_PREVIEW     the dry run says when the navy would come and leaves no trace; the card's clock reads the same side, and a free fleet serves no key
-- @pass NC_REAL        through the real engine: a joined ship's guns change the fight, every purse summed moves 0
-- @pass NC_OPEN        with the economy open, as CI's own world: the same battle moves the same gold, every purse summed moves 0
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'navy_enabled', 'regard_enabled', 'npc_refits_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  update public.ports p set crew_pool = 2000;

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_40;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$ select false, null::text, 0::numeric, 0::numeric $b$
  $f$;

  -- THE FIGHT, BY NAME, and it says how many hulls stood on each side. Empty, the real engine.
  alter function public.fight_sides(uuid, integer, jsonb, jsonb, jsonb) rename to fight_sides_real_40;
  execute $f$
create function public.fight_sides(p_seed uuid, p_round integer, p_a jsonb, p_b jsonb, p_opts jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
as $b$
declare
  v_x   text := coalesce(current_setting('byeharu.proof_fight', true), '');
  v_out text := case v_x when 'SUNK' then 'PLUNDERED' else v_x end;
begin
  perform set_config('byeharu.proof_sides', jsonb_array_length(p_a)::text, true);
  perform set_config('byeharu.proof_ids', (select string_agg(e->>'id', ',' order by e->>'id') from jsonb_array_elements(p_a) e), true);
  if v_x = '' then
    return public.fight_sides_real_40(p_seed, p_round, p_a, p_b, p_opts);
  end if;
  return jsonb_build_object('outcome', v_out, 'stood_off', false, 'slipped', false, 'broke_off', false, 'first', 'BOTH', 'rounds_fought', 0, 'rounds', '[]'::jsonb,
    'hull_lost', jsonb_build_object('a', case when v_x = 'SUNK' then (select jsonb_object_agg(e->>'id', e->'hull') from jsonb_array_elements(p_a) e) else '{}'::jsonb end, 'b', '{}'::jsonb),
    'hull', jsonb_build_object('a', 0, 'b', 0, 'a_start', 1, 'b_start', 1), 'hits', jsonb_build_object('a', 0, 'b', 0));
end
$b$
  $f$;

  -- W14's reading, or its plain words while 0334 is not in the world: did a ship of her country reach the battle in time? The ship set upon is no answer to her own attack.
  execute $f$
create function pg_temp.came_40(p_battle uuid, p_nation uuid, p_target uuid)
returns boolean
language plpgsql
as $b$
declare
  v boolean;
begin
  if to_regprocedure('public.navy_arrived(uuid,uuid,uuid)') is not null then
    execute 'select public.navy_arrived($1, $2, $3)' into v using p_battle, p_nation, p_target;
    return v;
  end if;
  return exists (select 1 from public.battle_sides bs join public.battles b on b.id = bs.battle_id join public.navy_ships n on n.fleet_id = bs.fleet_id
                  where bs.battle_id = p_battle and n.nation_id = p_nation and bs.fleet_id is distinct from p_target and bs.arrives_at <= b.resolves_at);
end
$b$
  $f$;

  -- rows of public.wanted for a battle, or null while 0334 is not in the world
  execute $f$
create function pg_temp.marks_40(p_battle uuid)
returns int
language plpgsql
as $b$
declare
  v int;
begin
  if to_regclass('public.wanted') is null then
    return null;
  end if;
  execute 'select count(*)::int from public.wanted w where w.battle_id = $1' into v using p_battle;
  return v;
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

  -- a human company of Portugal, her one fleet at sea-anchor, 100 hands, the best guns there are, her hold empty
  execute $f$
create function pg_temp.house_40(p_n int)
returns uuid
language plpgsql
as $b$
declare
  v_uid uuid := ('00000000-0333-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid;
  v_p   uuid := public.new_house(v_uid, 'Casa Guerra ' || p_n, 'PRT', 'LIS', 'Guerra ' || p_n,
                                 (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Guerra ' || p_n, null, false);
  v_f   uuid;
begin
  select id into v_f from public.fleets where player_id = v_p;
  update public.ships set crew = 100, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_f;
  return v_f;
end
$b$
  $f$;

  -- the next cargo ship of another country, at sea, with p_ducats aboard, slowed so she stays there
  execute $f$
create function pg_temp.ship_40(p_ducats bigint, p_at timestamptz, p_nation text default null)
returns uuid
language plpgsql
as $b$
declare
  c    public.cargo_ships%rowtype;
  v_st text;
begin
  select x.* into c
    from public.cargo_ships x join public.nations n on n.id = x.nation_id join public.fleets f on f.id = x.fleet_id
   where f.status = 'DOCKED' and x.out_load is null
     and ((p_nation is null and n.code <> 'PRT') or n.code = p_nation)
     and not exists (select 1 from public.cargo_ship_aboard(x.fleet_id))
   order by n.code, x.ord limit 1;
  if c.fleet_id is null then
    raise exception 'PROOF 40 FAIL: no cargo ship left to sail';
  end if;
  update public.fleets set ready_at = null where id = c.fleet_id;
  perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, p_ducats);
  v_st := public.cargo_ship_step(c.fleet_id, p_at);
  if v_st <> 'SAILED' then
    raise exception 'PROOF 40 FAIL: the cargo ship did not sail: %', v_st;
  end if;
  update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
   where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
  perform voyage.recompute_eta((select vo.id from public.voyages vo where vo.fleet_id = c.fleet_id and vo.status = 'SAILING'));
  return c.fleet_id;
end
$b$
  $f$;

  execute $f$
create function pg_temp.lie_by(p_fleet uuid, p_target uuid, p_at timestamptz)
returns void
language sql
as $b$
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon, version = f.version + 1
    from voyage.fleet_point(p_target, p_at) p where f.id = p_fleet
$b$
  $f$;

  -- the harbour a battle on this ship would send a ship to
  execute $f$
create function pg_temp.site_40(p_target uuid, p_at timestamptz)
returns uuid
language sql
as $b$
  select public.harbour_nearest(p.lat::float8, p.lon::float8) from voyage.fleet_point(p_target, p_at) p
$b$
  $f$;

  -- the p_k-th nearest harbour to p_to a course reaches, within a call's reach
  execute $f$
create function pg_temp.near_40(p_nation uuid, p_to uuid, p_k int default 1)
returns uuid
language plpgsql
as $b$
declare
  r   record;
  v_k int := 0;
begin
  for r in select x.port_id from voyage.reach_from(p_to) x join public.ports p on p.id = x.port_id
            where p.kind = 'HARBOUR' and not p.is_ice_closed and x.port_id <> p_to and x.nm <= public.wc_num('navy_reach_nm') order by x.nm, x.code loop
    if public.cargo_circuit_plan(p_nation, r.port_id, p_to) #> '{legs,0}' is not null then
      v_k := v_k + 1;
      if v_k = p_k then
        return r.port_id;
      end if;
    end if;
  end loop;
  raise exception 'PROOF 40 FAIL: no harbour % within reach of the site', p_k;
end
$b$
  $f$;

  -- every ship laid up, so a scene has only the ships it makes
  execute $f$
create function pg_temp.clear_40(p_at timestamptz)
returns void
language sql
as $b$
  update public.navy_ships n set laid_up_at = p_at, mission = 'PATROL', battle_id = null, called_to = null, escort_of = null where n.laid_up_at is null
$b$
  $f$;

  -- a navy ship of p_nation in service, lying at p_port, on duty, whole
  execute $f$
create function pg_temp.navy_40(p_nation uuid, p_port uuid, p_at timestamptz)
returns uuid
language plpgsql
as $b$
declare
  v_cap uuid := public.realm_capital(p_nation);
  v_ord int := coalesce((select max(n.ord) from public.navy_ships n where n.nation_id = p_nation), 0) + 1;
begin
  insert into public.navy_realms (nation_id, ships, read_at) values (p_nation, v_ord + 24, p_at) on conflict (nation_id) do update set ships = v_ord + 24, read_at = p_at;   -- a scene's ord is never above the number
  return public.navy_commission(p_nation, v_ord, v_cap, public.refit_yard(v_cap), p_port, p_at);
end
$b$
  $f$;

  execute $f$
create function pg_temp.attack_40(p_fleet uuid, p_target uuid, p_at timestamptz)
returns uuid
language sql
as $b$
  select (public.attack_for((select f.player_id from public.fleets f where f.id = p_fleet), p_fleet, p_target, null, p_at) ->> 'battle_id')::uuid
$b$
  $f$;

  execute $f$
create function pg_temp.code_of(p_fleet uuid, p_target uuid, p_at timestamptz)
returns text
language plpgsql
as $b$
begin
  perform public.attack_for((select f.player_id from public.fleets f where f.id = p_fleet), p_fleet, p_target, null, p_at);
  return null;
exception when others then
  return split_part(sqlerrm, ':', 1);
end
$b$
  $f$;

  -- close a battle at p_at, the fight by name
  execute $f$
create function pg_temp.close_40(p_battle uuid, p_at timestamptz, p_outcome text)
returns jsonb
language plpgsql
as $b$
begin
  perform set_config('byeharu.proof_fight', p_outcome, true);
  perform set_config('byeharu.proof_sides', '', true);
  if not public.battle_resolve(p_battle, p_at) then
    raise exception 'PROOF 40 FAIL: the battle did not resolve';
  end if;
  perform set_config('byeharu.proof_fight', '', true);
  return (select b.result from public.battles b where b.id = p_battle);
end
$b$
  $f$;

  -- her voyage takes p_by times as long
  execute $f$
create function pg_temp.slow_40(p_fleet uuid, p_by numeric)
returns timestamptz
language plpgsql
as $b$
begin
  update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / p_by) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
   where vo.fleet_id = p_fleet and vo.status = 'SAILING';
  return voyage.recompute_eta((select vo.id from public.voyages vo where vo.fleet_id = p_fleet and vo.status = 'SAILING'));
end
$b$
  $f$;

  -- she leaves her voyage and lies at anchor a little off a harbour
  execute $f$
create function pg_temp.anchor_off_40(p_fleet uuid, p_port uuid)
returns void
language sql
as $b$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat + 0.01, lon = p.lon + 0.01 from public.ports p where f.id = p_fleet and p.id = p_port
$b$
  $f$;

  -- the clock a scene is judged by
  execute $f$
create function pg_temp.clock_40(p_battle uuid, p_at timestamptz)
returns void
language sql
as $b$ update public.battles b set resolves_at = p_at where b.id = p_battle $b$
  $f$;

  execute $f$
create function pg_temp.sheet_40()
returns int language sql as $b$ select nullif(current_setting('byeharu.proof_sides', true), '')::int $b$
  $f$;

  -- every great power's ships and circuits
  declare
    v_nat uuid;
    v_n   int;
  begin
    for v_nat in select g.nation_id from public.great_powers g loop
      for v_n in 1 .. 3 loop
        perform public.tick_cargo_ships(now(), v_nat);
      end loop;
    end loop;
  end;
end
$$;

-- ── DARK ──
do $$
declare
  c_uid constant uuid := '00000000-0333-4000-8000-000000000001';
  v_t  timestamptz := now();
  a    uuid := pg_temp.house_40(1);
  d    uuid := pg_temp.ship_40(100000, v_t);
  v_nat uuid := public.crown_nation(d);
  v_to  uuid := pg_temp.site_40(d, v_t);
  n     uuid;
  b     uuid;
  v_x   jsonb;
  v_r   jsonb;
begin
  if public.economy_closed() is distinct from true then
    raise exception 'PROOF 40 FAIL: the economy is not closed here';
  end if;
  perform pg_temp.lie_by(a, d, v_t);
  n := pg_temp.navy_40(v_nat, pg_temp.near_40(v_nat, v_to), v_t);
  perform cmd.assume_identity(c_uid);
  v_x := cmd.attack(a, n);
  if v_x ->> 'error_code' is distinct from 'E_NOT_IN_USE' or (cmd.preview_attack(a, n)) ->> 'error_code' is distinct from 'E_NOT_IN_USE' then
    raise exception 'PROOF 40 FAIL: dark, a door answered %', v_x;
  end if;
  if world.navy_ship_card(n) ? 'attack' then
    raise exception 'PROOF 40 FAIL: dark, the navy card serves the attack key';
  end if;
  if exists (select 1 from public.battles) or exists (select 1 from public.battle_sides) or (select x.mission from public.navy_ships x where x.fleet_id = n) <> 'PATROL' then
    raise exception 'PROOF 40 FAIL: dark, something was written';
  end if;

  -- attacks lit, navies off: a battle has no reinforcement, as the design's rollback says. Not even her escort.
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  update public.navy_ships x set mission = 'ESCORT', escort_of = d where x.fleet_id = n;
  b := pg_temp.attack_40(a, d, v_t);
  if (select count(*) from public.battle_sides bs where bs.battle_id = b) <> 2 or (select f.status from public.fleets f where f.id = n) <> 'DOCKED' then
    raise exception 'PROOF 40 FAIL: with the navy off a ship answered';
  end if;
  v_r := pg_temp.close_40(b, v_t + interval '601 seconds', 'DRIVEN_OFF');
  if v_r #>> '{navy,came}' <> '0' or v_r #>> '{navy,late}' <> '0' or v_r #>> '{navy,line}' <> 'No navy came.' then
    raise exception 'PROOF 40 FAIL: with the navy off the close said %', v_r -> 'navy';
  end if;
  raise notice 'PASS: NC_DARK — doors refuse, no key, navy off no call, close says %', v_r #>> '{navy,line}';
end
$$;

update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'navy_enabled');

-- ── A CALL IS A REAL VOYAGE, AND THE JOIN RULE ──
do $$
declare
  v_t   timestamptz := now();
  a     uuid := pg_temp.house_40(2);
  d     uuid := pg_temp.ship_40(100000, v_t);
  v_nat uuid := public.crown_nation(d);
  v_to  uuid := pg_temp.site_40(d, v_t);
  v_from uuid := pg_temp.near_40(v_nat, v_to);
  n     uuid;
  b     uuid;
  v_vo  public.voyages%rowtype;
  v_e   timestamptz;
  v_sum bigint;
  v_led bigint;
  v_rep jsonb;
  v_r   jsonb;
begin
  perform pg_temp.clear_40(v_t);
  perform pg_temp.lie_by(a, d, v_t);
  n := pg_temp.navy_40(v_nat, v_from, v_t);
  v_sum := pg_temp.purses();
  v_led := (select count(*) from public.ledger);
  b := pg_temp.attack_40(a, d, v_t);
  select * into v_vo from public.voyages v where v.fleet_id = n and v.status = 'SAILING';
  v_e := v_vo.eta;
  if v_vo.id is null or v_vo.origin_port_id <> v_from or v_vo.dest_port_id <> v_to or v_vo.departed_at <> v_t then
    raise exception 'PROOF 40 FAIL: the call was no voyage from % to %: %', v_from, v_to, to_jsonb(v_vo) - 'path' - 'speed_profile';
  end if;
  if (select x.mission from public.navy_ships x where x.fleet_id = n) <> 'REINFORCE' or (select x.called_to from public.navy_ships x where x.fleet_id = n) <> v_to
     or (select x.battle_id from public.navy_ships x where x.fleet_id = n) <> b then
    raise exception 'PROOF 40 FAIL: she does not know her call';
  end if;
  if (select bs.arrives_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n) <> v_e
     or (select bs.how || bs.side from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n) <> 'CALLEDDEFENDER' then
    raise exception 'PROOF 40 FAIL: her line on the sheet is not her voyage';
  end if;
  if pg_temp.purses() <> v_sum or (select count(*) from public.ledger) <> v_led or exists (select 1 from public.navy_ships x where x.fleet_id = n and x.patrol is not null) then
    raise exception 'PROOF 40 FAIL: a call moved gold or kept a patrol';
  end if;
  if (select s.crew from public.ships s where s.fleet_id = n) <= 0 then
    raise exception 'PROOF 40 FAIL: she sailed with no hands from a full quay';
  end if;
  raise notice 'PASS: NC_CALL — % nm, % s', round(v_vo.total_nm), round(extract(epoch from v_e - v_t));
  declare
    v_cap uuid := public.realm_capital(v_nat);
    v_q   uuid := pg_temp.near_40(v_nat, v_cap, 3);
    d2    uuid := pg_temp.ship_40(100000, v_t, (select x.code from public.nations x where x.id = v_nat));
    a2    uuid := pg_temp.house_40(102);
    n2    uuid;
    b2    uuid;
  begin
    perform pg_temp.anchor_off_40(d2, v_q);
    perform pg_temp.lie_by(a2, d2, v_t);
    n2 := pg_temp.navy_40(v_nat, v_cap, v_t);
    b2 := pg_temp.attack_40(a2, d2, v_t);
    if (select x.called_to from public.navy_ships x where x.fleet_id = n2) is distinct from v_q then
      raise exception 'PROOF 40 FAIL: the call went to the wrong harbour';
    end if;
    perform pg_temp.close_40(b2, v_t + interval '1 day', 'DRIVEN_OFF');
    update public.navy_ships x set laid_up_at = v_t where x.fleet_id = n2;
  end;

  -- exactly at the clock she is in the fight, on the side set upon
  perform pg_temp.clock_40(b, v_e);
  v_r := pg_temp.close_40(b, v_e + interval '1 second', 'DRIVEN_OFF');
  if pg_temp.sheet_40() <> 2 or v_r #>> '{navy,came}' <> '1' or v_r #>> '{navy,late}' <> '0' then
    raise exception 'PROOF 40 FAIL: on the clock she did not join: sheet %, %', pg_temp.sheet_40(), v_r -> 'navy';
  end if;
  if position((select s.id::text from public.ships s where s.fleet_id = n) in current_setting('byeharu.proof_ids')) = 0 then
    raise exception 'PROOF 40 FAIL: her hull is not on the side set upon';
  end if;
  select e.payload into v_rep from public.events e where e.kind = 'BATTLE_REPORT' and e.payload ->> 'battle_id' = b::text;
  if v_rep -> 'lines' -> 1 is distinct from '"The navy came up before it ended."'::jsonb or v_rep #>> '{navy,came}' is distinct from '1' then
    raise exception 'PROOF 40 FAIL: the report does not say she came: %', v_rep;
  end if;
  if (select x.battle_id is not null or x.called_to is not null or x.mission <> 'PATROL' from public.navy_ships x where x.fleet_id = n) then
    raise exception 'PROOF 40 FAIL: she was not freed';
  end if;
  if not pg_temp.came_40(b, v_nat, d) or coalesce(pg_temp.marks_40(b), 0) <> 0 then
    raise exception 'PROOF 40 FAIL: she came and the attacker lost, and W14 reads otherwise';
  end if;
  raise notice 'PASS: NC_JOINS — sheet 2, the report says so';
end
$$;

-- ── ONE MINUTE PAST ──
do $$
declare
  v_t   timestamptz := now();
  a1    uuid := pg_temp.house_40(3);
  a2    uuid := pg_temp.house_40(4);
  d1    uuid := pg_temp.ship_40(100000, v_t);
  d2    uuid := pg_temp.ship_40(100000, v_t);
  v_nat uuid := public.crown_nation(d1);
  v_to  uuid;
  n     uuid;
  b     uuid;
  v_e   timestamptz;
  v_r   jsonb;
  v_rep jsonb;
  i     int;
  d     uuid;
  a     uuid;
begin
  -- once with the job running before she arrives, once with it lagging past her arrival: the clock decides, never the job
  for i in 1 .. 2 loop
    d := case i when 1 then d1 else d2 end;
    a := case i when 1 then a1 else a2 end;
    v_nat := public.crown_nation(d);
    v_to := pg_temp.site_40(d, v_t);
    perform pg_temp.clear_40(v_t);
    perform pg_temp.lie_by(a, d, v_t);
    n := pg_temp.navy_40(v_nat, pg_temp.near_40(v_nat, v_to), v_t);
    b := pg_temp.attack_40(a, d, v_t);
    v_e := pg_temp.slow_40(n, 20);   -- a probe world's legs are shorter than the minute this scene is about
    perform pg_temp.clock_40(b, v_e - interval '60 seconds');
    v_r := pg_temp.close_40(b, case i when 1 then v_e - interval '59 seconds' else v_e + interval '5 seconds' end, 'EVADED');
    if pg_temp.sheet_40() <> 1 or v_r #>> '{navy,came}' <> '0' or v_r #>> '{navy,late}' <> '1' or v_r #>> '{navy,line}' <> 'The navy came too late.' then
      raise exception 'PROOF 40 FAIL: a minute past she joined (run %): sheet %, %', i, pg_temp.sheet_40(), v_r -> 'navy';
    end if;
    if (select bs.arrives_at - b2.resolves_at from public.battle_sides bs join public.battles b2 on b2.id = bs.battle_id where bs.battle_id = b and bs.fleet_id = n) <> interval '60 seconds' then
      raise exception 'PROOF 40 FAIL: her line does not say she was a minute late';
    end if;
    if pg_temp.came_40(b, v_nat, d) or coalesce(pg_temp.marks_40(b), 1) <> 1 then
      raise exception 'PROOF 40 FAIL: a late ship reads as come, or wrote no mark';
    end if;
    select e.payload into v_rep from public.events e where e.kind = 'BATTLE_REPORT' and e.payload ->> 'battle_id' = b::text;
    if v_rep -> 'lines' -> 1 is distinct from '"The navy came too late."'::jsonb then
      raise exception 'PROOF 40 FAIL: the report: %', v_rep;
    end if;
    if (select x.battle_id is not null or x.mission <> 'PATROL' from public.navy_ships x where x.fleet_id = n) then
      raise exception 'PROOF 40 FAIL: the late ship is still tied to the battle';
    end if;
    if i = 1 then
      if (select f.status from public.fleets f where f.id = n) <> 'SAILING' then
        raise exception 'PROOF 40 FAIL: the late ship stopped';
      end if;
      perform voyage.settle(n, v_e + interval '1 second');
    end if;
    if (select f.port_id from public.fleets f where f.id = n) <> v_to or (select f.status from public.fleets f where f.id = n) <> 'DOCKED' then
      raise exception 'PROOF 40 FAIL: the late ship did not make her port';
    end if;
    -- freed, the next step is an ordinary one: not the call's
    if public.navy_ship_step(n, v_e + interval '10 minutes') = 'CALLED' then
      raise exception 'PROOF 40 FAIL: the late ship still waits for a battle that is over';
    end if;
  end loop;
  raise notice 'PASS: NC_ONE_MINUTE — sheet 1, on the list, freed, before and after her arrival';
end
$$;

-- ── WANTED, W14's HOOK ──
do $$
declare
  v_t   timestamptz := now();
  a1    uuid := pg_temp.house_40(5);
  a2    uuid := pg_temp.house_40(6);
  d1    uuid := pg_temp.ship_40(100000, v_t);
  d2    uuid := pg_temp.ship_40(100000, v_t);
  n     uuid;
  b     uuid;
  v_nat uuid := public.crown_nation(d1);
  v_to  uuid := pg_temp.site_40(d1, v_t);
  v_r   jsonb;
begin
  perform pg_temp.clear_40(v_t);
  perform pg_temp.lie_by(a1, d1, v_t);
  n := pg_temp.navy_40(v_nat, pg_temp.near_40(v_nat, v_to), v_t);
  b := pg_temp.attack_40(a1, d1, v_t);
  perform pg_temp.clock_40(b, v_t + interval '1 day');
  v_r := pg_temp.close_40(b, v_t + interval '1 day', 'PLUNDERED');
  if v_r #>> '{navy,came}' <> '1' or not pg_temp.came_40(b, v_nat, d1) or coalesce(pg_temp.marks_40(b), 1) <> 1 then
    raise exception 'PROOF 40 FAIL: she won with the navy there: %', v_r -> 'navy';
  end if;
  -- none in reach: not at all
  perform pg_temp.clear_40(v_t);
  perform pg_temp.lie_by(a2, d2, v_t);
  b := pg_temp.attack_40(a2, d2, v_t);
  if (select count(*) from public.battle_sides bs where bs.battle_id = b) <> 2 then
    raise exception 'PROOF 40 FAIL: a laid-up ship answered';
  end if;
  v_r := pg_temp.close_40(b, v_t + interval '601 seconds', 'DRIVEN_OFF');
  if pg_temp.came_40(b, public.crown_nation(d2), d2) or coalesce(pg_temp.marks_40(b), 1) <> 1 then
    raise exception 'PROOF 40 FAIL: nobody came and it reads otherwise: %', v_r -> 'navy';
  end if;
  raise notice 'PASS: NC_WANTED — came and beaten no mark, won a mark, none a mark; 0334 %', case when to_regclass('public.wanted') is null then 'not in this world: its reading only' else 'in this world: the rows' end;
end
$$;

-- ── A SHIP AT SEA ──
do $$
declare
  v_t   timestamptz := now();
  a     uuid := pg_temp.house_40(7);
  d     uuid := pg_temp.ship_40(100000, v_t);
  v_nat uuid := public.crown_nation(d);
  v_to  uuid := pg_temp.site_40(d, v_t);
  v_p   uuid := pg_temp.near_40(v_nat, v_to, 1);
  v_q   uuid := pg_temp.near_40(v_nat, v_to, 2);
  n     uuid;
  b     uuid;
  v_vo  public.voyages%rowtype;
  v_path text;
  v_est timestamptz;
  v_end timestamptz;
  v_e   timestamptz;
  v_r   jsonb;
  v_leg jsonb;
begin
  perform pg_temp.clear_40(v_t);
  perform pg_temp.lie_by(a, d, v_t);
  n := pg_temp.navy_40(v_nat, v_p, v_t);
  v_leg := public.cargo_circuit_plan(v_nat, v_p, v_q) #> '{legs,0}';
  perform public.navy_sail(n, v_p, voyage.segments_from_course(v_leg -> 'course'), v_q, null, 0, v_t - interval '10 seconds');
  select * into v_vo from public.voyages v where v.fleet_id = n and v.status = 'SAILING';
  v_path := v_vo.path::text;
  b := pg_temp.attack_40(a, d, v_t);
  v_est := (select bs.arrives_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n);
  if v_est <= v_vo.eta or (select v.id from public.voyages v where v.fleet_id = n and v.status = 'SAILING') <> v_vo.id
     or (select v.path::text from public.voyages v where v.id = v_vo.id) <> v_path or (select v.eta from public.voyages v where v.id = v_vo.id) <> v_vo.eta
     or (select v.dest_port_id from public.voyages v where v.id = v_vo.id) <> v_q then
    raise exception 'PROOF 40 FAIL: the call touched the voyage she was on, or read her arrival wrong';
  end if;
  v_end := v_vo.eta + interval '1 second';
  perform voyage.settle(n, v_end);
  update public.fleets f set ready_at = null where f.id = n;
  if public.navy_ship_step(n, v_end) <> 'SAILED' then
    raise exception 'PROOF 40 FAIL: from her port she did not sail on';
  end if;
  v_e := (select v.eta from public.voyages v where v.fleet_id = n and v.status = 'SAILING' and v.dest_port_id = v_to);
  if v_e is null or (select bs.arrives_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n) <> v_e then
    raise exception 'PROOF 40 FAIL: her line does not follow her new voyage';
  end if;
  -- in port she waits for the close: she does not sail off her call
  perform voyage.settle(n, v_e + interval '1 second');
  update public.fleets f set ready_at = null where f.id = n;
  if public.navy_ship_step(n, v_e + interval '2 seconds') <> 'CALLED' or (select f.port_id from public.fleets f where f.id = n) <> v_to then
    raise exception 'PROOF 40 FAIL: on station for a battle she did not stay';
  end if;
  perform pg_temp.clock_40(b, v_e + interval '1 minute');
  v_r := pg_temp.close_40(b, v_e + interval '1 minute', 'DRIVEN_OFF');
  if pg_temp.sheet_40() <> 2 then
    raise exception 'PROOF 40 FAIL: she came by her leg and was not on the sheet: %', v_r -> 'navy';
  end if;

  -- a storm that holds her past the clock counts, though the call's estimate was in time
  declare
    a2 uuid := pg_temp.house_40(8);
    d2 uuid := pg_temp.ship_40(100000, v_t);
    v_was timestamptz;
  begin
    v_nat := public.crown_nation(d2);
    v_to := pg_temp.site_40(d2, v_t);
    perform pg_temp.clear_40(v_t);
    perform pg_temp.lie_by(a2, d2, v_t);
    n := pg_temp.navy_40(v_nat, pg_temp.near_40(v_nat, v_to), v_t);
    b := pg_temp.attack_40(a2, d2, v_t);
    v_was := (select bs.arrives_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n);
    perform pg_temp.clock_40(b, v_was);
    perform pg_temp.slow_40(n, 2);
    v_r := pg_temp.close_40(b, v_was + interval '1 second', 'EVADED');
    if pg_temp.sheet_40() <> 1 or v_r #>> '{navy,late}' <> '1' or (select bs.arrives_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n) <= v_was then
      raise exception 'PROOF 40 FAIL: a delayed ship stood on her old estimate: %', v_r -> 'navy';
    end if;
  end;
  raise notice 'PASS: NC_AT_SEA — her leg is left as it was, she sails on from her port, a delay counts';
end
$$;

-- ── NO SHIP IS COUNTED TWICE ──
do $$
declare
  v_t   timestamptz := now();
  a1    uuid := pg_temp.house_40(9);
  a2    uuid := pg_temp.house_40(10);
  a3    uuid := pg_temp.house_40(11);
  d1    uuid := pg_temp.ship_40(100000, v_t);
  d2    uuid := pg_temp.ship_40(100000, v_t);
  v_nat uuid := public.crown_nation(d1);
  v_to  uuid := pg_temp.site_40(d1, v_t);
  n     uuid;
  b1    uuid;
  b2    uuid;
  v_e   timestamptz;
  v_k   bigint;
  v_r   jsonb;
begin
  if public.crown_nation(d2) <> v_nat then
    raise exception 'PROOF 40 FAIL: the two ships are of two countries: the scene needs one';
  end if;
  perform pg_temp.clear_40(v_t);
  perform pg_temp.lie_by(a1, d1, v_t);
  perform pg_temp.lie_by(a2, d2, v_t);
  perform pg_temp.lie_by(a3, d1, v_t);
  n := pg_temp.navy_40(v_nat, pg_temp.near_40(v_nat, v_to), v_t);
  b1 := pg_temp.attack_40(a1, d1, v_t);
  b2 := pg_temp.attack_40(a2, d2, v_t);
  if (select count(*) from public.battle_sides bs where bs.fleet_id = n) <> 1 or (select bs.battle_id from public.battle_sides bs where bs.fleet_id = n) <> b1 then
    raise exception 'PROOF 40 FAIL: one ship answered two battles';
  end if;
  if pg_temp.code_of(a3, n, v_t) is distinct from 'E_FLEET_BUSY' then
    raise exception 'PROOF 40 FAIL: a called ship was attacked: %', pg_temp.code_of(a3, n, v_t);
  end if;
  v_e := (select bs.arrives_at from public.battle_sides bs where bs.fleet_id = n);
  perform pg_temp.clock_40(b1, v_e);
  v_r := pg_temp.close_40(b1, v_e, 'DRIVEN_OFF');
  if pg_temp.sheet_40() <> 2 then
    raise exception 'PROOF 40 FAIL: sheet % on the battle she answered', pg_temp.sheet_40();
  end if;
  v_k := (select count(*) from public.events e where e.kind = 'BATTLE_REPORT');
  perform set_config('byeharu.proof_sides', '', true);
  if public.battle_resolve(b1, v_e + interval '1 minute') or pg_temp.sheet_40() is not null or (select count(*) from public.events e where e.kind = 'BATTLE_REPORT') <> v_k
     or (select b.result from public.battles b where b.id = b1) is distinct from v_r then
    raise exception 'PROOF 40 FAIL: a retry did something';
  end if;
  perform pg_temp.clock_40(b2, v_e);
  v_r := pg_temp.close_40(b2, v_e, 'DRIVEN_OFF');
  if pg_temp.sheet_40() <> 1 then
    raise exception 'PROOF 40 FAIL: the other battle counted her too';
  end if;
  raise notice 'PASS: NC_ONCE — one call, one line, a retry is nothing, a called ship cannot be attacked';
end
$$;

-- ── THE BOUND ──
do $$
declare
  v_t   timestamptz := now();
  a1    uuid := pg_temp.house_40(12);
  a2    uuid := pg_temp.house_40(13);
  a3    uuid := pg_temp.house_40(14);
  a4    uuid := pg_temp.house_40(104);
  d1    uuid := pg_temp.ship_40(100000, v_t);
  d2    uuid := pg_temp.ship_40(100000, v_t, (select x.code from public.nations x where x.id = public.crown_nation(d1)));
  d3    uuid := pg_temp.ship_40(100000, v_t, (select x.code from public.nations x where x.id = public.crown_nation(d1)));
  d4    uuid := pg_temp.ship_40(100000, v_t, (select x.code from public.nations x where x.id = public.crown_nation(d1)));
  v_nat uuid := public.crown_nation(d1);
  v_to  uuid := pg_temp.site_40(d1, v_t);
  v_near uuid := pg_temp.near_40(v_nat, v_to, 1);
  v_far  uuid := pg_temp.near_40(v_nat, v_to, 2);
  x     uuid[] := '{}';
  b     uuid;
  i     int;
  v_keep numeric := public.wc_num('battle_seconds');
begin
  perform pg_temp.clear_40(v_t);
  for i in 1 .. 5 loop
    x := x || pg_temp.navy_40(v_nat, v_near, v_t);
  end loop;
  update public.navy_ships n set unpaid_since = v_t where n.fleet_id = x[1];        -- unpaid
  update public.navy_ships n set laid_up_at = v_t where n.fleet_id = x[2];          -- laid up
  update public.ships s set durability = 0 where s.fleet_id = x[3];                 -- a wreck
  perform pg_temp.lie_by(a1, d1, v_t);
  update public.world_config set value = '86400'::jsonb where key = 'battle_seconds';
  update public.world_config set value = '6'::jsonb where key = 'navy_call_ships';
  x := x || pg_temp.navy_40(v_nat, v_near, v_t);
  b := pg_temp.attack_40(a1, d1, v_t);
  if (select count(*) from public.battle_sides bs where bs.battle_id = b and bs.how = 'CALLED') <> 3
     or exists (select 1 from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = any (x[1:3])) then
    raise exception 'PROOF 40 FAIL: the call took %', (select jsonb_agg(bs.fleet_id) from public.battle_sides bs where bs.battle_id = b and bs.how = 'CALLED');
  end if;
  perform pg_temp.close_40(b, v_t + interval '86401 seconds', 'DRIVEN_OFF');

  -- the knob: of the three fit ships, two
  update public.navy_ships n set mission = 'PATROL' where n.fleet_id = any (x);
  update public.voyages v set status = 'ABORTED' where v.fleet_id = any (x[4:6]) and v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = v_near, lat = null, lon = null, ready_at = null where f.id = any (x[4:6]);
  update public.world_config set value = '2'::jsonb where key = 'navy_call_ships';
  perform pg_temp.lie_by(a4, d4, v_t);
  b := pg_temp.attack_40(a4, d4, v_t);
  if (select count(*) from public.battle_sides bs where bs.battle_id = b and bs.how = 'CALLED') <> 2 then
    raise exception 'PROOF 40 FAIL: the call took % of 2', (select count(*) from public.battle_sides bs where bs.battle_id = b and bs.how = 'CALLED');
  end if;
  perform pg_temp.close_40(b, v_t + interval '86401 seconds', 'DRIVEN_OFF');

  -- nobody in time: one sails, the soonest, and only she
  perform pg_temp.clear_40(v_t);
  update public.world_config set value = '1'::jsonb where key = 'battle_seconds';
  update public.world_config set value = '3'::jsonb where key = 'navy_call_ships';
  x := array[pg_temp.navy_40(v_nat, v_far, v_t), pg_temp.navy_40(v_nat, v_near, v_t), pg_temp.navy_40(v_nat, v_far, v_t)];
  perform pg_temp.lie_by(a2, d2, v_t);
  if pg_temp.site_40(d2, v_t) <> v_to then
    raise notice 'NOTE: the second scene''s site differs';
  end if;
  b := pg_temp.attack_40(a2, d2, v_t);
  if (select count(*) from public.battle_sides bs where bs.battle_id = b and bs.how = 'CALLED') <> 1 then
    raise exception 'PROOF 40 FAIL: past the clock % sailed', (select count(*) from public.battle_sides bs where bs.battle_id = b and bs.how = 'CALLED');
  end if;
  if (select bs.arrives_at from public.battle_sides bs join public.battles z on z.id = bs.battle_id where bs.battle_id = b and bs.how = 'CALLED')
     <= (select z.resolves_at from public.battles z where z.id = b) then
    raise exception 'PROOF 40 FAIL: this scene''s ship was in time';
  end if;
  if public.battle_navy_served(a2) <> '{}'::jsonb then
    raise exception 'PROOF 40 FAIL: the clock promises a ship that will be late';
  end if;
  perform pg_temp.close_40(b, v_t + interval '1 hour', 'DRIVEN_OFF');

  -- out of reach: no call at all
  perform pg_temp.clear_40(v_t);
  update public.world_config set value = to_jsonb(v_keep) where key = 'battle_seconds';
  update public.world_config set value = '1'::jsonb where key = 'navy_reach_nm';
  x := array[pg_temp.navy_40(v_nat, v_far, v_t)];
  perform pg_temp.lie_by(a3, d3, v_t);
  b := pg_temp.attack_40(a3, d3, v_t);
  if exists (select 1 from public.battle_sides bs where bs.battle_id = b and bs.how = 'CALLED') then
    raise exception 'PROOF 40 FAIL: a ship beyond navy_reach_nm was called';
  end if;
  update public.world_config set value = '2400'::jsonb where key = 'navy_reach_nm';
  perform pg_temp.close_40(b, v_t + interval '1 hour', 'DRIVEN_OFF');
  raise notice 'PASS: NC_BOUND — at most the knob, one if none in time, none out of reach, none unpaid, laid up or wrecked';
end
$$;

-- ── ESCORT ──
do $$
declare
  v_t   timestamptz := now();
  a     uuid := pg_temp.house_40(15);
  d     uuid := pg_temp.ship_40(900000, v_t);
  v_nat uuid := public.crown_nation(d);
  v_to  uuid := pg_temp.site_40(d, v_t);
  v_dst uuid := (select v.dest_port_id from public.voyages v where v.fleet_id = d and v.status = 'SAILING');
  v_p   uuid := public.realm_capital(v_nat);   -- a harbour of her own country
  first uuid;
  e     uuid;
  b     uuid;
  v_p0  jsonb;
  v_vo  uuid;
  v_r   jsonb;
  v_was numeric;
begin
  perform pg_temp.clear_40(v_t);
  update public.world_config set value = '0'::jsonb where key = 'navy_call_ships';
  first := pg_temp.navy_40(v_nat, v_p, v_t);
  e := pg_temp.navy_40(v_nat, v_p, v_t);
  if (select max(n.ord) from public.navy_ships n where n.nation_id = v_nat and n.laid_up_at is null) <> (select n.ord from public.navy_ships n where n.fleet_id = e) then
    raise exception 'PROOF 40 FAIL: this scene needs her last in the line';
  end if;
  -- the first of the line is on her patrol, whatever is at sea
  if public.navy_escort_step(first, v_p, true, v_t) is not null then
    raise exception 'PROOF 40 FAIL: the first ship of the line went on escort';
  end if;
  update public.ships s set durability = 10 where s.fleet_id = e;
  if v_p = v_dst then
    raise exception 'PROOF 40 FAIL: this scene needs the cargo ship bound away from her capital';
  end if;
  if public.navy_ship_step(e, v_t) <> 'ESCORT' then
    raise exception 'PROOF 40 FAIL: she did not take the escort';
  end if;
  if (select n.mission || n.escort_of::text from public.navy_ships n where n.fleet_id = e) <> 'ESCORT' || d::text
     or (select v.dest_port_id from public.voyages v where v.fleet_id = e and v.status = 'SAILING') <> v_dst then
    raise exception 'PROOF 40 FAIL: she does not follow the richest ship''s leg';
  end if;
  if (select s.durability from public.ships s where s.fleet_id = e) <= 10 then
    raise exception 'PROOF 40 FAIL: she was not mended in her own country''s harbour';
  end if;

  perform pg_temp.lie_by(a, d, v_t + interval '1 second');
  select v.id into v_vo from public.voyages v where v.fleet_id = e and v.status = 'SAILING';
  update public.world_config set value = '3'::jsonb where key = 'navy_call_ships';
  b := pg_temp.attack_40(a, d, v_t + interval '1 second');
  if (select bs.how from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = e) <> 'ESCORT'
     or (select bs.arrives_at = bs.joined_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = e) is not true then
    raise exception 'PROOF 40 FAIL: she did not join at once';
  end if;
  if (select count(*) from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = e) <> 1 or (select x.battle_id from public.navy_ships x where x.fleet_id = e) is distinct from b then
    raise exception 'PROOF 40 FAIL: the escort stands twice, or does not know her battle';
  end if;
  if (select f.busy_until from public.fleets f where f.id = e) is distinct from (select z.resolves_at from public.battles z where z.id = b)
     or not exists (select 1 from public.voyage_events ve where ve.voyage_id = v_vo and ve.day_index >= voyage.hold_floor()) then
    raise exception 'PROOF 40 FAIL: she is not held by the battle';
  end if;
  select to_jsonb(p) into v_p0 from voyage.fleet_point(e, v_t + interval '2 seconds') p;
  if to_jsonb((select p from voyage.fleet_point(e, v_t + interval '300 seconds') p)) <> v_p0 then
    raise exception 'PROOF 40 FAIL: held, she moved';
  end if;
  v_r := pg_temp.close_40(b, v_t + interval '602 seconds', 'DRIVEN_OFF');
  if pg_temp.sheet_40() < 2 or v_r #>> '{navy,came}' < '1' then
    raise exception 'PROOF 40 FAIL: the escort was not in the fight: sheet %, %', pg_temp.sheet_40(), v_r -> 'navy';
  end if;
  if (select n.mission || coalesce(n.battle_id::text, '') from public.navy_ships n where n.fleet_id = e) <> 'ESCORT' or (select f.busy_until from public.fleets f where f.id = e) is not null then
    raise exception 'PROOF 40 FAIL: after the fight she is not an escort, free';
  end if;

  -- no funds at sea, or the knob at 0: she patrols
  update public.world_config set value = '0'::jsonb where key = 'navy_escorts';
  if public.navy_escort_step(e, v_p, true, v_t + interval '1 hour') is not null then
    raise exception 'PROOF 40 FAIL: the knob at 0 and she took the escort';
  end if;
  if (select n.mission || coalesce(n.escort_of::text, '') from public.navy_ships n where n.fleet_id = e) <> 'PATROL' then
    raise exception 'PROOF 40 FAIL: the knob at 0 left her on escort: %', (select to_jsonb(n) from public.navy_ships n where n.fleet_id = e);
  end if;
  update public.world_config set value = '1'::jsonb where key = 'navy_escorts';
  if public.navy_escort_step(e, v_p, false, v_t + interval '1 hour') is not null then
    raise exception 'PROOF 40 FAIL: an unpaid or unwanted ship went on escort';
  end if;
  raise notice 'PASS: NC_ESCORT — she follows, joins at once, held, an escort after, patrols with no job';
end
$$;

-- ── THE SPOILS ──
do $$
declare
  v_t   timestamptz := now();
  a     uuid := pg_temp.house_40(16);
  d     uuid := pg_temp.ship_40(100000, v_t);
  v_nat uuid := public.crown_nation(d);
  v_to  uuid := pg_temp.site_40(d, v_t);
  n     uuid;
  b     uuid;
  v_sum bigint;
  v_was bigint;
  v_crew int;
  v_e   timestamptz;
  v_r   jsonb;
begin
  perform pg_temp.clear_40(v_t);
  perform pg_temp.lie_by(a, d, v_t);
  n := pg_temp.navy_40(v_nat, pg_temp.near_40(v_nat, v_to), v_t);
  b := pg_temp.attack_40(a, d, v_t);
  v_e := (select bs.arrives_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n);
  perform pg_temp.clock_40(b, v_e + interval '1 second');
  v_sum := pg_temp.purses();
  v_was := (select p.ducats from public.players p join public.fleets f on f.player_id = p.id where f.id = a);
  v_crew := (select s.crew from public.ships s where s.fleet_id = n);
  v_r := pg_temp.close_40(b, v_e + interval '2 seconds', 'PLUNDERED');
  if (v_r ->> 'loot')::bigint <> 15000 or pg_temp.sheet_40() <> 2 then
    raise exception 'PROOF 40 FAIL: the loot: %', v_r;
  end if;
  if (select p.ducats from public.players p join public.fleets f on f.player_id = p.id where f.id = a) <> v_was + 15000 or pg_temp.purses() <> v_sum then
    raise exception 'PROOF 40 FAIL: the money moved wrong';
  end if;
  if (select s.crew from public.ships s where s.fleet_id = n) <> v_crew then
    raise exception 'PROOF 40 FAIL: the ship that came lost the hands of the ship set upon';
  end if;
  raise notice 'PASS: NC_SPOILS — 15000 moved, sum 0, her hands untouched';
end
$$;

-- ── A NAVY SHIP AS THE TARGET ──
do $$
declare
  c_uid constant uuid := '00000000-0333-4000-8000-000000000017';
  v_t   timestamptz := now();
  a     uuid := pg_temp.house_40(17);
  a2    uuid := pg_temp.house_40(18);
  v_nat uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
  v_prt uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_p   uuid := public.realm_capital(v_nat);
  v_st  uuid := pg_temp.near_40(v_nat, v_p);
  n     uuid;
  own   uuid;
  b     uuid;
  v_leg jsonb;
  v_pl  uuid := (select f.player_id from public.fleets f where f.id = a);
  v_sum bigint;
  v_r   jsonb;
  v_x   jsonb;
begin
  perform pg_temp.clear_40(v_t);
  update public.world_config set value = 'true'::jsonb where key = 'regard_enabled';
  n := pg_temp.navy_40(v_nat, v_st, v_t);
  v_leg := public.cargo_circuit_plan(v_nat, v_st, v_p) #> '{legs,0}';
  perform public.navy_sail(n, v_st, voyage.segments_from_course(v_leg -> 'course'), v_p, null, 0, v_t);
  perform pg_temp.slow_40(n, 5000);   -- at sea for the whole scene
  perform pg_temp.lie_by(a, n, v_t);
  if not (world.navy_ship_card(n) ? 'attack') then
    raise exception 'PROOF 40 FAIL: lit, her card offers no attack';
  end if;
  v_sum := pg_temp.purses();
  b := pg_temp.attack_40(a, n, v_t);
  if (select r.points from public.house_regard r where r.player_id = v_pl and r.nation_id = v_nat) <> -250 then
    raise exception 'PROOF 40 FAIL: regard % after attacking a navy ship', (select r.points from public.house_regard r where r.player_id = v_pl and r.nation_id = v_nat);
  end if;
  if (select e.payload ->> 'reason' from public.events e where e.kind = 'REGARD_CHANGED' and e.player_id = v_pl order by e.created_at desc limit 1) <> 'ATTACK_NAVY' then
    raise exception 'PROOF 40 FAIL: the regard names no navy';
  end if;
  v_r := pg_temp.close_40(b, v_t + interval '601 seconds', 'PLUNDERED');
  if (v_r ->> 'loot')::bigint <> 0 or pg_temp.purses() <> v_sum then
    raise exception 'PROOF 40 FAIL: a navy ship carries no gold: %', v_r;
  end if;
  if (select x.battle_id from public.navy_ships x where x.fleet_id = n) is not null then
    raise exception 'PROOF 40 FAIL: the ship set upon was not freed';
  end if;

  -- her limit: attack_ship_minutes, from anyone
  perform pg_temp.lie_by(a2, n, v_t + interval '700 seconds');
  if pg_temp.code_of(a2, n, v_t + interval '700 seconds') is distinct from 'E_SHIP_FOUGHT_THIS_LAP' then
    raise exception 'PROOF 40 FAIL: inside the hour: %', pg_temp.code_of(a2, n, v_t + interval '700 seconds');
  end if;
  if pg_temp.code_of(a2, n, v_t + interval '61 minutes') is not null then
    raise exception 'PROOF 40 FAIL: past the hour: %', pg_temp.code_of(a2, n, v_t + interval '61 minutes');
  end if;

  -- your own country, a merchant
  own := pg_temp.navy_40(v_prt, public.realm_capital(v_prt), v_t);
  perform public.navy_sail(own, public.realm_capital(v_prt), voyage.segments_from_course(public.cargo_circuit_plan(v_prt, public.realm_capital(v_prt), pg_temp.near_40(v_prt, public.realm_capital(v_prt))) #> '{legs,0,course}'),
                           pg_temp.near_40(v_prt, public.realm_capital(v_prt)), null, 0, v_t + interval '61 minutes');
  perform pg_temp.lie_by(a2, own, v_t + interval '61 minutes');
  if pg_temp.code_of(a2, own, v_t + interval '61 minutes') is distinct from 'E_YOUR_OWN_COUNTRY' then
    raise exception 'PROOF 40 FAIL: your own navy: %', pg_temp.code_of(a2, own, v_t + interval '61 minutes');
  end if;
  if pg_temp.code_of(a2, (select nf.fleet_id from public.npc_fleets nf order by nf.roster_ord limit 1), v_t + interval '61 minutes') is distinct from 'E_NOT_A_TARGET' then
    raise exception 'PROOF 40 FAIL: a merchant was not refused';
  end if;
  -- she beat him alone: her country was there, and he is not marked for it
  declare
    a3 uuid := pg_temp.house_40(103);
    n2 uuid := pg_temp.navy_40(v_nat, v_st, v_t);
    b3 uuid;
  begin
    perform public.navy_sail(n2, v_st, voyage.segments_from_course(v_leg -> 'course'), v_p, null, 0, v_t);
    perform pg_temp.slow_40(n2, 5000);
    perform pg_temp.lie_by(a3, n2, v_t);
    b3 := pg_temp.attack_40(a3, n2, v_t);
    if (select x.battle_id from public.navy_ships x where x.fleet_id = n2) is distinct from b3 then
      raise exception 'PROOF 40 FAIL: the ship set upon holds no battle';
    end if;
    v_r := pg_temp.close_40(b3, v_t + interval '601 seconds', 'DRIVEN_OFF');
    if v_r #>> '{navy,line}' <> 'Her country''s ship fought alone.' then
      raise exception 'PROOF 40 FAIL: she fought alone: %', v_r -> 'navy';
    end if;
  end;
  raise notice 'PASS: NC_NAVY_TARGET — -250, ATTACK_NAVY, no gold, an hour, own and merchant refused, her card offers it';

  -- SUNK, with the refit rule lit: her station takes her
  update public.world_config set value = 'true'::jsonb where key = 'npc_refits_enabled';
  b := (select bs.battle_id from public.battle_sides bs where bs.fleet_id = a2);   -- the attack made past the hour, above
  v_r := pg_temp.close_40(b, v_t + interval '2 hours', 'SUNK');
  if (select r.points from public.house_regard r where r.player_id = (select f.player_id from public.fleets f where f.id = a2) and r.nation_id = v_nat) > -349 then
    raise exception 'PROOF 40 FAIL: a sunk navy ship cost no more regard';
  end if;
  if not exists (select 1 from public.events e where e.kind = 'REGARD_CHANGED' and e.payload ->> 'reason' = 'SINK_NAVY') then
    raise exception 'PROOF 40 FAIL: the sink names no navy';
  end if;
  if (select f.status || f.port_id::text from public.fleets f where f.id = n) <> 'UNABLE_TO_SAIL' || (select x.station_port::text from public.navy_ships x where x.fleet_id = n) then
    raise exception 'PROOF 40 FAIL: she is not at her station a wreck';
  end if;
  if exists (select 1 from public.voyages v where v.fleet_id = n and v.status = 'SAILING') then
    raise exception 'PROOF 40 FAIL: her voyage did not end';
  end if;
  raise notice 'PASS: NC_NAVY_SUNK — regard_sink, SINK_NAVY, her station';
end
$$;

-- ── THE DRY RUN AND THE CARD'S CLOCK ──
do $$
declare
  c_uid constant uuid := '00000000-0333-4000-8000-000000000019';
  v_t   timestamptz := now();
  a     uuid := pg_temp.house_40(19);
  d     uuid := pg_temp.ship_40(100000, v_t);
  v_nat uuid := public.crown_nation(d);
  v_to  uuid := pg_temp.site_40(d, v_t);
  n     uuid;
  v_x   jsonb;
  v_f   jsonb;
  v_b   int := (select count(*) from public.battles);
  v_v   int := (select count(*) from public.voyages);
begin
  perform pg_temp.clear_40(v_t);
  update public.world_config set value = 'false'::jsonb where key in ('regard_enabled', 'npc_refits_enabled');
  update public.world_config set value = '86400'::jsonb where key = 'battle_seconds';
  perform pg_temp.lie_by(a, d, v_t);
  n := pg_temp.navy_40(v_nat, pg_temp.near_40(v_nat, v_to), now());
  perform cmd.assume_identity(c_uid);

  v_f := (select e from jsonb_array_elements(world.fleets()) e where e ->> 'id' = a::text);
  if v_f ? 'navy_at' then
    raise exception 'PROOF 40 FAIL: a free fleet serves navy_at';
  end if;
  v_x := cmd.preview_attack(a, d);
  if (v_x ->> 'ok') is distinct from 'true' or (v_x #>> '{estimate,navy_minutes}') is null or (v_x #>> '{estimate,navy_minutes}')::numeric < 1 then
    raise exception 'PROOF 40 FAIL: the dry run says nothing of the navy: %', v_x;
  end if;
  if (select count(*) from public.battles) <> v_b or (select count(*) from public.voyages) <> v_v or (select x.mission from public.navy_ships x where x.fleet_id = n) <> 'PATROL'
     or (select f.status from public.fleets f where f.id = n) <> 'DOCKED' then
    raise exception 'PROOF 40 FAIL: the dry run left a trace';
  end if;
  v_x := cmd.attack(a, d);
  if (v_x ->> 'ok') is distinct from 'true' or (v_x ->> 'navy_minutes') is null then
    raise exception 'PROOF 40 FAIL: the press: %', v_x;
  end if;
  v_f := (select e from jsonb_array_elements(world.fleets()) e where e ->> 'id' = a::text);
  if (v_f ->> 'navy_at')::timestamptz is distinct from (select bs.arrives_at from public.battle_sides bs where bs.fleet_id = n) then
    raise exception 'PROOF 40 FAIL: the card''s clock is not the sheet: %', v_f ->> 'navy_at';
  end if;
  if public.battle_navy_served(d) <> '{}'::jsonb then
    raise exception 'PROOF 40 FAIL: the side set upon read as the attacker';
  end if;
  update public.world_config set value = '600'::jsonb where key = 'battle_seconds';
  raise notice 'PASS: NC_PREVIEW — % minutes, no trace, the card reads the sheet', v_x ->> 'navy_minutes';
end
$$;

-- ── THE REAL ENGINE ──
do $$
declare
  v_t   timestamptz := now();
  a     uuid := pg_temp.house_40(20);
  d     uuid := pg_temp.ship_40(100000, v_t);
  v_nat uuid := public.crown_nation(d);
  v_to  uuid := pg_temp.site_40(d, v_t);
  n     uuid;
  b     uuid;
  v_e   timestamptz;
  v_sum bigint;
  v_r   jsonb;
begin
  perform pg_temp.clear_40(v_t);
  perform pg_temp.lie_by(a, d, v_t);
  n := pg_temp.navy_40(v_nat, pg_temp.near_40(v_nat, v_to), v_t);
  b := pg_temp.attack_40(a, d, v_t);
  v_e := (select bs.arrives_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n);
  perform pg_temp.clock_40(b, v_e);
  v_sum := pg_temp.purses();
  v_r := pg_temp.close_40(b, v_e, '');
  if pg_temp.purses() <> v_sum or pg_temp.sheet_40() <> 2 then
    raise exception 'PROOF 40 FAIL: the real engine: sheet %, sum moved %', pg_temp.sheet_40(), pg_temp.purses() - v_sum;
  end if;
  if (v_r ->> 'outcome') in ('PLUNDERED', 'RANSOM') and (v_r ->> 'loot')::bigint <= 0 then
    raise exception 'PROOF 40 FAIL: the fight won and no gold: %', v_r;
  end if;
  raise notice 'PASS: NC_REAL — %, loot %, came %', v_r ->> 'outcome', v_r ->> 'loot', v_r #>> '{navy,came}';
end
$$;

-- ── THE ECONOMY OPEN, as CI's own world ──
do $$
declare
  v_t   timestamptz := now();
  a     uuid := pg_temp.house_40(21);
  d     uuid := pg_temp.ship_40(100000, v_t);
  v_nat uuid := public.crown_nation(d);
  v_to  uuid := pg_temp.site_40(d, v_t);
  n     uuid;
  b     uuid;
  v_e   timestamptz;
  v_sum bigint;
  v_r   jsonb;
begin
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  perform pg_temp.clear_40(v_t);
  perform pg_temp.lie_by(a, d, v_t);
  n := pg_temp.navy_40(v_nat, pg_temp.near_40(v_nat, v_to), v_t);
  b := pg_temp.attack_40(a, d, v_t);
  v_e := (select bs.arrives_at from public.battle_sides bs where bs.battle_id = b and bs.fleet_id = n);
  perform pg_temp.clock_40(b, v_e);
  v_sum := pg_temp.purses();
  v_r := pg_temp.close_40(b, v_e, 'PLUNDERED');
  if (v_r ->> 'loot')::bigint <> 15000 or pg_temp.purses() <> v_sum or pg_temp.sheet_40() <> 2 then
    raise exception 'PROOF 40 FAIL: with the economy open: %, sum moved %', v_r, pg_temp.purses() - v_sum;
  end if;
  raise notice 'PASS: NC_OPEN — 15000 moved, sum 0';
end
$$;

