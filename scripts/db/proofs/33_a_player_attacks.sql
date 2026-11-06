-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 33 — A PLAYER ATTACKS  (migration 0327, slice W11 of docs/WORLD_POWERS.md)
--
--   0327's own self-assert reads the catalog: a migration never runs a real game step (docs/OPS_HEALTH.md section 4). This proof runs them, on probes, rolled back by the runner.
--   THE ECONOMY IS CLOSED HERE, as on prod: a kind that mints would be refused, so LOOT passing here is LOOT passing there. The sea is quiet. Instants are handed to every call, so nothing waits.
--   The fight's outcome is asked for by name on one setting, because each row of the table needs its own outcome. ATTACK_REAL_FIGHT alone takes what the real engine gives.
--
-- @pass ATTACK_DARK          dark: both doors refuse before anything is read or written, the card serves no key, and the old bodies answer the same
-- @pass ATTACK_REFUSALS      every refusal has its own code, and moves nothing
-- @pass ATTACK_OPENS         an attack holds both ships at sea, marks her lap, costs regard at once, moves no gold, and a sailing or a docked fleet may attack
-- @pass ATTACK_PREVIEW       the dry run says what the press would, writes nothing, and answers a refusal alike
-- @pass LOOT_BOARDED         boarded: 15 % of what is aboard, to the ducat, moved: every purse summed moves 0, the fold finds no drift, no city row, one book row, one ledger row
-- @pass LOOT_CAPS            never above the share, the ship, the company's day or what is aboard, and the day comes back
-- @pass LOOT_THE_REST        a looted ship closes the rest of her load, and not a ducat more
-- @pass LOOT_RANSOM          she paid off: ransom_share, moved, capped alike
-- @pass ATTACK_BEATEN        beaten or broken off: no gold, hands lost on both sides, regard stands; she slipped: nobody loses a hand
-- @pass ATTACK_SUNK          every hull at 0: regard falls more; lit, the loot is paid and the rest goes home; dark, she sails on
-- @pass ATTACK_ONCE          a retry pays nothing and reports nothing
-- @pass ATTACK_SWITCH_OFF    the switch off stops new attacks, and a running battle still pays
-- @pass ATTACK_REPORT        the report goes to the human alone and says what she took
-- @pass ATTACK_PROBE         a probe battle closes as it did: no gold, no hands, no new key
-- @pass ATTACK_REAL_FIGHT    through the real engine: gold if and only if the fight says so, every purse summed moves 0
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'regard_enabled', 'npc_refits_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;

  -- THE SEA IS QUIET
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_33;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$ select false, null::text, 0::numeric, 0::numeric $b$
  $f$;

  -- THE FIGHT, BY NAME: set byeharu.proof_fight to an outcome, or SLIPPED, BROKE, SUNK. Empty, the real engine.
  alter function public.fight_sides(uuid, integer, jsonb, jsonb, jsonb) rename to fight_sides_real_33;
  execute $f$
create function public.fight_sides(p_seed uuid, p_round integer, p_a jsonb, p_b jsonb, p_opts jsonb default '{}'::jsonb)
returns jsonb
language plpgsql stable
as $b$
declare
  v_x   text := coalesce(current_setting('byeharu.proof_fight', true), '');
  v_out text := case v_x when 'SLIPPED' then 'EVADED' when 'BROKE' then 'EVADED' when 'SUNK' then 'PLUNDERED' else v_x end;
begin
  if v_x = '' then
    return public.fight_sides_real_33(p_seed, p_round, p_a, p_b, p_opts);
  end if;
  return jsonb_build_object('outcome', v_out, 'stood_off', false, 'slipped', v_x = 'SLIPPED', 'broke_off', v_x = 'BROKE', 'first', 'BOTH', 'rounds_fought', 0, 'rounds', '[]'::jsonb,
    'hull_lost', jsonb_build_object('a', case when v_x = 'SUNK' then (select jsonb_object_agg(e->>'id', e->'hull') from jsonb_array_elements(p_a) e) else '{}'::jsonb end, 'b', '{}'::jsonb),
    'hull', jsonb_build_object('a', 0, 'b', 0, 'a_start', 1, 'b_start', 1), 'hits', jsonb_build_object('a', 0, 'b', 0));
end
$b$
  $f$;

  -- every purse of the world, summed: cities, companies, funds aboard
  execute $f$
create function pg_temp.purses()
returns bigint language sql as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint
       + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;

  -- a human company of Portugal, her one fleet in Lisbon, 100 hands, the best guns there are, her hold empty
  execute $f$
create function pg_temp.house_33(p_n int)
returns uuid
language plpgsql
as $b$
declare
  v_uid uuid := ('00000000-0327-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid;
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

  -- the next cargo ship at sea, not of p_own's realm unless asked, with p_ducats aboard, sailed at p_at
  execute $f$
create function pg_temp.ship_33(p_ducats bigint, p_at timestamptz, p_nation text default null)
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
    raise exception 'PROOF 33 FAIL: no cargo ship left to sail';
  end if;
  update public.fleets set ready_at = null where id = c.fleet_id;
  perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, p_ducats);
  v_st := public.cargo_ship_step(c.fleet_id, p_at);
  if v_st <> 'SAILED' then
    raise exception 'PROOF 33 FAIL: the cargo ship did not sail: %', v_st;
  end if;
  -- a leg is minutes at this clock: slowed, so she is still at sea when the proof looks
  update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
   where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
  perform voyage.recompute_eta((select vo.id from public.voyages vo where vo.fleet_id = c.fleet_id and vo.status = 'SAILING'));
  return c.fleet_id;
end
$b$
  $f$;

  -- lay a fleet at anchor at the very point of her target
  execute $f$
create function pg_temp.lie_by(p_fleet uuid, p_target uuid, p_at timestamptz)
returns void
language sql
as $b$
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon, version = f.version + 1
    from voyage.fleet_point(p_target, p_at) p where f.id = p_fleet
$b$
  $f$;

  -- the code a call of the attack refuses with, or null
  execute $f$
create function pg_temp.code_of(p_fleet uuid, p_target uuid, p_at timestamptz, p_version int default null)
returns text
language plpgsql
as $b$
begin
  perform public.attack_for((select f.player_id from public.fleets f where f.id = p_fleet), p_fleet, p_target, p_version, p_at);
  return null;
exception when others then
  return split_part(sqlerrm, ':', 1);
end
$b$
  $f$;

  -- open a battle and close it, the fight by name. Answers the battle.
  execute $f$
create function pg_temp.fight_33(p_fleet uuid, p_target uuid, p_at timestamptz, p_outcome text)
returns uuid
language plpgsql
as $b$
declare
  v_b uuid;
begin
  v_b := (public.attack_for((select f.player_id from public.fleets f where f.id = p_fleet), p_fleet, p_target, null, p_at) ->> 'battle_id')::uuid;
  perform set_config('byeharu.proof_fight', p_outcome, true);
  if not public.battle_resolve(v_b, p_at + interval '601 seconds') then
    raise exception 'PROOF 33 FAIL: the battle did not resolve';
  end if;
  perform set_config('byeharu.proof_fight', '', true);
  return v_b;
end
$b$
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
  c_uid constant uuid := '00000000-0327-4000-8000-000000000001';
  a     uuid := pg_temp.house_33(1);
  d     uuid := pg_temp.ship_33(100000, now());
  v_x   jsonb;
  v_rows int;
  v_new text;
  v_old text;
  v_def text;
  v_flows text;
  v_flows_old text;
  c_card_new constant text := $h$
    || case when public.attack_on() then '{"attack": true}'::jsonb else '{}'::jsonb end;   -- 0327: the key is served only while attacks are lit, and the card's button reads it$h$;
begin
  perform pg_temp.lie_by(a, d, now());
  if public.economy_closed() is distinct from true then
    raise exception 'PROOF 33 FAIL: the economy is not closed here';
  end if;
  perform cmd.assume_identity(c_uid);
  v_rows := (select count(*) from public.voyage_events ve where ve.day_index >= voyage.hold_floor());
  v_x := cmd.attack(a, d);
  if v_x ->> 'error_code' is distinct from 'E_NOT_IN_USE' then
    raise exception 'PROOF 33 FAIL: dark, cmd.attack answered %', v_x;
  end if;
  v_x := cmd.preview_attack(a, d);
  if v_x ->> 'error_code' is distinct from 'E_NOT_IN_USE' then
    raise exception 'PROOF 33 FAIL: dark, cmd.preview_attack answered %', v_x;
  end if;
  -- a door of a dark world reads no fleet: not even a fleet that does not exist is judged
  if pg_temp.code_of(gen_random_uuid(), gen_random_uuid(), now()) is distinct from 'E_NOT_IN_USE' then
    raise exception 'PROOF 33 FAIL: dark, a bad fleet was judged before the switch';
  end if;
  if exists (select 1 from public.battles) or (select count(*) from public.voyage_events ve where ve.day_index >= voyage.hold_floor()) <> v_rows
     or exists (select 1 from public.cargo_ships c where c.last_attacked_lap is not null) then
    raise exception 'PROOF 33 FAIL: dark, a door wrote something';
  end if;
  if world.cargo_ship_card(d) ? 'attack' then
    raise exception 'PROOF 33 FAIL: dark, the card serves the attack key';
  end if;

  -- THE OLD BODIES: the card, every ship
  select string_agg(world.cargo_ship_card(c.fleet_id)::text, '|' order by c.fleet_id) into v_new from public.cargo_ships c;
  v_def := replace(pg_get_functiondef('world.cargo_ship_card(uuid)'::regprocedure), E'\r', '');
  if v_def not like '%' || c_card_new || '%' then
    raise exception 'PROOF 33 FAIL: the card has no hunk to take out';
  end if;
  execute replace(v_def, c_card_new, ';');
  select string_agg(world.cargo_ship_card(c.fleet_id)::text, '|' order by c.fleet_id) into v_old from public.cargo_ships c;
  execute v_def;
  if v_new is distinct from v_old then
    raise exception 'PROOF 33 FAIL: dark, the card is not the old card';
  end if;
  raise notice 'PASS: ATTACK_DARK';
end
$$;


-- ── THE BOOK'S OLD STAGES, the old body against the new ──
do $$
declare
  d     uuid := pg_temp.ship_33(100000, now());
  c     public.cargo_ships%rowtype;
  v_load bigint;
  v_def text;
  v_old text;
  v_t   bigint;
  v_a   text;
  v_b   text;
  c_new constant text := $h$  if p_stage <> 'LOOTED' then   -- 0327: looted gold goes to a player, not to a purse: public.loot_take credits her, and no city moves
    perform public.treasury_post(p_port,
      case p_stage when 'LOADED' then 'CONVOY_LOAD' when 'DELIVERED' then 'CONVOY_DELIVER' when 'RETURNED' then 'CONVOY_RETURN' end,
      case when p_stage = 'LOADED' then -p_ducats else p_ducats end, null, null, p_stage <> 'LOADED');
  end if;$h$;
  c_old constant text := $h$  perform public.treasury_post(p_port,
    case p_stage when 'LOADED' then 'CONVOY_LOAD' when 'DELIVERED' then 'CONVOY_DELIVER' when 'RETURNED' then 'CONVOY_RETURN' end,
    case when p_stage = 'LOADED' then -p_ducats else p_ducats end, null, null, p_stage <> 'LOADED');$h$;
begin
  select * into c from public.cargo_ships x where x.fleet_id = d;
  v_load := (select a.load_id from public.cargo_ship_aboard(d) a);
  v_t := (select coalesce(max(f.id), 0) from public.treasury_flows f);
  perform public.convoy_book('DELIVERED', d, c.player_id, c.home_port_id, 7, v_load);
  perform public.convoy_book('RETURNED', d, c.player_id, c.home_port_id, 11, v_load);
  select string_agg(f.kind || f.ducats, ',' order by f.id) into v_a from public.treasury_flows f where f.id > v_t;

  v_def := replace(pg_get_functiondef('public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)'::regprocedure), E'\r', '');
  if v_def not like '%' || c_new || '%' then
    raise exception 'PROOF 33 FAIL: the book has no hunk to take out';
  end if;
  execute replace(v_def, c_new, c_old);
  v_t := (select coalesce(max(f.id), 0) from public.treasury_flows f);
  perform public.convoy_book('DELIVERED', d, c.player_id, c.home_port_id, 7, v_load);
  perform public.convoy_book('RETURNED', d, c.player_id, c.home_port_id, 11, v_load);
  select string_agg(f.kind || f.ducats, ',' order by f.id) into v_b from public.treasury_flows f where f.id > v_t;
  execute v_def;
  if v_a is distinct from v_b or v_a is distinct from 'CONVOY_DELIVER7,CONVOY_RETURN11' then
    raise exception 'PROOF 33 FAIL: the book''s old stages moved: % against %', v_a, v_b;
  end if;
end
$$;

-- ── EVERY REFUSAL ──
do $$
declare
  t0    timestamptz := now();
  a     uuid := pg_temp.house_33(2);
  own   uuid := pg_temp.ship_33(100000, t0, 'PRT');
  d     uuid := pg_temp.ship_33(100000, t0);
  rival uuid := pg_temp.house_33(3);
  guns  uuid := pg_temp.house_33(4);
  full_hold uuid := pg_temp.house_33(5);
  far   uuid := pg_temp.house_33(6);
  stale uuid := pg_temp.house_33(7);
  home  uuid;
  v_m   uuid := (select nf.fleet_id from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.ships s on s.fleet_id = f.id limit 1);
  v_sum bigint;
  v_b   uuid;
  v_ev  bigint;
  x     record;
  v_got text;
  v_msg text;
begin
  update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'regard_enabled');
  if v_m is null then
    raise exception 'PROOF 33 FAIL: no merchant in this world to refuse';
  end if;
  perform pg_temp.lie_by(a, d, t0);
  perform pg_temp.lie_by(guns, d, t0);
  perform pg_temp.lie_by(full_hold, d, t0);
  perform pg_temp.lie_by(stale, d, t0);
  update public.ships s set class_id = (select c.id from public.ship_classes c where c.attack = 0 order by c.code limit 1) where s.fleet_id = guns;   -- an unarmed hull
  update public.ships s set cargo = jsonb_build_object((select g.code from public.goods g order by g.code limit 1), 1) where s.fleet_id = full_hold;
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = 0, lon = 0, version = f.version + 1 where f.id = far;

  -- a ship in port: her house's own, docked, with no load
  select c.fleet_id into home from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
   where f.status = 'DOCKED' and c.nation_id <> (select n.id from public.nations n where n.code = 'PRT') order by c.fleet_id limit 1;

  v_sum := pg_temp.purses();
  v_ev := (select count(*) from public.events e where e.kind = 'REGARD_CHANGED');
  for x in select * from (values
      ('the wrong owner',     rival,  d,    'E_NO_SUCH_FLEET', true),
      ('no such ship',        a,      gen_random_uuid(), 'E_NOT_FOUND', false),
      ('a player',            a,      rival, 'E_HUMAN_TARGET', false),
      ('herself',             a,      a,    'E_HUMAN_TARGET', false),
      ('a merchant',          a,      v_m,  'E_NOT_A_TARGET', false),
      ('her own country',     a,      own,  'E_YOUR_OWN_COUNTRY', false),
      ('a ship in port',      a,      home, 'E_TARGET_DOCKED', false),
      ('no guns',             guns,   d,    'E_NO_GUNS', false),
      ('a hold not empty',    full_hold, d, 'E_HOLD_NOT_EMPTY', false),
      ('out of reach',        far,    d,    'E_OUT_OF_REACH', false)) c(what, f, tg, code, wrong_owner) loop
    if x.wrong_owner then
      begin
        perform public.attack_for((select f.player_id from public.fleets f where f.id = a), x.f, x.tg, null, t0);
        v_got := null;
      exception when others then
        v_got := split_part(sqlerrm, ':', 1);
      end;
    else
      v_got := pg_temp.code_of(x.f, x.tg, t0);
    end if;
    if v_got is distinct from x.code then
      raise exception 'PROOF 33 FAIL: %: wanted %, got %', x.what, x.code, coalesce(v_got, 'no refusal');
    end if;
  end loop;

  -- reach prints the distance
  begin
    perform public.attack_for((select f.player_id from public.fleets f where f.id = far), far, d, null, t0);
  exception when others then
    v_msg := sqlerrm;
  end;
  if v_msg !~ '[0-9]+ miles off, and you reach 240' then
    raise exception 'PROOF 33 FAIL: the reach refusal prints no distance: %', v_msg;
  end if;

  -- just inside the reach is in reach: 239 miles north of her, and 241 are not
  update public.fleets f set lat = p.lat + (239.0 / 60), lon = p.lon, version = f.version + 1 from voyage.fleet_point(d, t0) p where f.id = far;
  if pg_temp.code_of(far, d, t0) is not null then
    raise exception 'PROOF 33 FAIL: 239 miles off was refused: %', pg_temp.code_of(far, d, t0);
  end if;

  if pg_temp.code_of(stale, pg_temp.ship_33(1000, t0), t0, -1) is distinct from 'E_STALE' then
    raise exception 'PROOF 33 FAIL: a stale version was not refused';
  end if;

  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 33 FAIL: a refusal moved money';
  end if;
end
$$;

-- E_FLEET_BUSY, E_SHIP_FOUGHT_THIS_LAP, E_ATTACK_COOLDOWN: each needs a battle before it
do $$
declare
  t0  timestamptz := now();
  a   uuid := pg_temp.house_33(8);
  b   uuid := pg_temp.house_33(9);
  d   uuid := pg_temp.ship_33(100000, t0);
  e   uuid := pg_temp.ship_33(100000, t0);
  f   uuid := pg_temp.ship_33(100000, t0 + interval '29 minutes');
  v_b uuid;
begin
  perform pg_temp.lie_by(a, d, t0);
  perform pg_temp.lie_by(b, d, t0);
  v_b := (public.attack_for((select f.player_id from public.fleets f where f.id = a), a, d, null, t0) ->> 'battle_id')::uuid;
  if pg_temp.code_of(a, e, t0 + interval '1 second') is distinct from 'E_FLEET_BUSY' then
    raise exception 'PROOF 33 FAIL: a fleet in a battle started another: %', pg_temp.code_of(a, e, t0 + interval '1 second');
  end if;
  if pg_temp.code_of(b, d, t0 + interval '1 second') is distinct from 'E_FLEET_BUSY' then
    raise exception 'PROOF 33 FAIL: a ship in a battle took a second: %', pg_temp.code_of(b, d, t0 + interval '1 second');
  end if;
  perform set_config('byeharu.proof_fight', 'DRIVEN_OFF', true);
  if not public.battle_resolve(v_b, t0 + interval '601 seconds') then
    raise exception 'PROOF 33 FAIL: the first battle did not close';
  end if;
  perform set_config('byeharu.proof_fight', '', true);
  -- the same lap: another fleet, close by, free, is refused
  perform pg_temp.lie_by(b, d, t0 + interval '602 seconds');
  if pg_temp.code_of(b, d, t0 + interval '602 seconds') is distinct from 'E_SHIP_FOUGHT_THIS_LAP' then
    raise exception 'PROOF 33 FAIL: one lap, two attacks: %', pg_temp.code_of(b, d, t0 + interval '602 seconds');
  end if;
  -- the cooldown: 29 minutes on, another ship, refused; 30 minutes on, not
  perform pg_temp.lie_by(a, f, t0 + interval '29 minutes');
  if pg_temp.code_of(a, f, t0 + interval '29 minutes') is distinct from 'E_ATTACK_COOLDOWN' then
    raise exception 'PROOF 33 FAIL: the cooldown did not hold: %', pg_temp.code_of(a, f, t0 + interval '29 minutes');
  end if;
  perform pg_temp.lie_by(a, f, t0 + interval '30 minutes 1 second');
  if pg_temp.code_of(a, f, t0 + interval '30 minutes 1 second') is not null then
    raise exception 'PROOF 33 FAIL: the cooldown outlived itself: %', pg_temp.code_of(a, f, t0 + interval '30 minutes 1 second');
  end if;
  raise notice 'PASS: ATTACK_REFUSALS';
end
$$;

-- ── THE ATTACK OPENS ──
do $$
declare
  c_uid constant uuid := '00000000-0327-4000-8000-000000000010';
  t0  timestamptz := now();
  a   uuid := pg_temp.house_33(10);
  p   uuid := (select f.player_id from public.fleets f where f.id = a);
  d   uuid := pg_temp.ship_33(100000, t0);
  c   public.cargo_ships%rowtype;
  sea uuid := pg_temp.house_33(11);
  e   uuid := pg_temp.ship_33(100000, t0);
  v_sum bigint;
  v_r0 numeric;
  v_x jsonb;
  v_b uuid;
  v_pos0 record;
  v_pos1 record;
begin
  select * into c from public.cargo_ships x where x.fleet_id = d;
  perform pg_temp.lie_by(a, d, t0);
  v_sum := pg_temp.purses();
  v_r0 := public.regard_of(p, c.nation_id);
  perform cmd.assume_identity(c_uid);
  v_x := public.attack_for(p, a, d, null, t0);
  v_b := (v_x ->> 'battle_id')::uuid;
  if (select b.kind from public.battles b where b.id = v_b) <> 'ATTACK' or (select count(*) from public.battle_sides s where s.battle_id = v_b) <> 2
     or not exists (select 1 from public.battle_sides s where s.battle_id = v_b and s.fleet_id = a and s.side = 'ATTACKER') then
    raise exception 'PROOF 33 FAIL: no ATTACK battle stands';
  end if;
  if (select f.status from public.fleets f where f.id = d) <> 'SAILING' or (select f.status from public.fleets f where f.id = a) <> 'IN_BATTLE' then
    raise exception 'PROOF 33 FAIL: a sailing ship is held and one at anchor is IN_BATTLE, and these are not';
  end if;
  select * into v_pos0 from voyage.position((select v.id from public.voyages v where v.fleet_id = d and v.status = 'SAILING'), t0);
  select * into v_pos1 from voyage.position((select v.id from public.voyages v where v.fleet_id = d and v.status = 'SAILING'), t0 + interval '300 seconds');
  if v_pos0.nm_done is distinct from v_pos1.nm_done then
    raise exception 'PROOF 33 FAIL: she moved in the battle';
  end if;
  if (select x.last_attacked_lap from public.cargo_ships x where x.fleet_id = d) is distinct from c.out_load then
    raise exception 'PROOF 33 FAIL: her lap is not marked';
  end if;
  if round(public.regard_of(p, c.nation_id) - v_r0, 3) <> -150 then
    raise exception 'PROOF 33 FAIL: the attack cost % regard, not 150', round(public.regard_of(p, c.nation_id) - v_r0, 3);
  end if;
  if not exists (select 1 from public.events e2 where e2.player_id = p and e2.kind = 'REGARD_CHANGED' and e2.payload ->> 'reason' = 'ATTACK_CARGO') then
    raise exception 'PROOF 33 FAIL: no REGARD_CHANGED';
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 33 FAIL: an attack moved gold before it ended';
  end if;

  -- a fleet at sea attacks from where she is, and is held; one in port attacks, and comes back to port
  perform pg_temp.lie_by(sea, e, t0);
  update public.fleets f set status = 'DOCKED', port_id = (select r.port_id from public.sea_reaches r order by voyage.gc_distance_nm(r.roadstead_lat::float8, r.roadstead_lon::float8, f.lat::float8, f.lon::float8) limit 1), lat = null, lon = null where f.id = sea;
  update public.world_config set value = '100000'::jsonb where key = 'attack_reach_nm';
  v_x := public.attack_for((select f.player_id from public.fleets f where f.id = sea), sea, e, null, t0);
  if (select f.status from public.fleets f where f.id = sea) <> 'IN_BATTLE' then
    raise exception 'PROOF 33 FAIL: a docked attacker is not in battle';
  end if;
  perform set_config('byeharu.proof_fight', 'DRIVEN_OFF', true);
  perform public.battle_resolve((v_x ->> 'battle_id')::uuid, t0 + interval '601 seconds');
  perform set_config('byeharu.proof_fight', '', true);
  update public.world_config set value = '240'::jsonb where key = 'attack_reach_nm';
  if (select f.status from public.fleets f where f.id = sea) <> 'DOCKED' then
    raise exception 'PROOF 33 FAIL: a docked attacker did not come back to port';
  end if;
  raise notice 'PASS: ATTACK_OPENS';
end
$$;

-- ── THE DRY RUN ──
do $$
declare
  c_uid constant uuid := '00000000-0327-4000-8000-000000000012';
  t0  timestamptz := now();
  a   uuid := pg_temp.house_33(12);
  p   uuid := (select f.player_id from public.fleets f where f.id = a);
  d   uuid := pg_temp.ship_33(1000000, t0);
  dd  uuid := pg_temp.ship_33(1000, t0);
  v_x jsonb;
  v_y jsonb;
  v_n int := (select count(*) from public.battles);
  v_e int := (select count(*) from public.events e where e.player_id = p);
begin
  perform pg_temp.lie_by(a, d, t0);
  perform cmd.assume_identity(c_uid);
  v_x := cmd.preview_attack(a, d);
  if not (v_x ->> 'ok')::boolean or v_x -> 'estimate' ? 'battle_id' then
    raise exception 'PROOF 33 FAIL: the preview answered %', v_x;
  end if;
  if (select count(*) from public.battles) <> v_n or (select count(*) from public.events e where e.player_id = p) <> v_e
     or (select c.last_attacked_lap from public.cargo_ships c where c.fleet_id = d) is not null
     or (select f.busy_until from public.fleets f where f.id = d) is not null
     or (select f.status from public.fleets f where f.id = a) <> 'ANCHORED' then
    raise exception 'PROOF 33 FAIL: the preview wrote something';
  end if;
  if v_x -> 'estimate' ->> 'funds' <> 'heavy' or v_x -> 'estimate' ->> 'word' not in ('weaker', 'even', 'stronger', 'far_stronger') or (v_x -> 'estimate' ->> 'nm')::numeric <> 0 then
    raise exception 'PROOF 33 FAIL: the preview''s words: %', v_x;
  end if;
  if (cmd.preview_attack(a, dd) -> 'estimate' ->> 'funds') <> 'light' then
    raise exception 'PROOF 33 FAIL: a little aboard is not light';
  end if;
  v_y := cmd.attack(a, d, (select f.version from public.fleets f where f.id = a));
  if not (v_y ->> 'ok')::boolean or (v_y ->> 'word') is distinct from (v_x -> 'estimate' ->> 'word') or (v_y ->> 'funds') is distinct from (v_x -> 'estimate' ->> 'funds')
     or (v_y ->> 'target') is distinct from (v_x -> 'estimate' ->> 'target') then
    raise exception 'PROOF 33 FAIL: the press and the dry run disagree: % against %', v_y, v_x;
  end if;
  v_x := cmd.preview_attack(a, dd);
  if v_x ->> 'error_code' is distinct from 'E_FLEET_BUSY' then
    raise exception 'PROOF 33 FAIL: the preview of a refusal: %', v_x;
  end if;
  v_y := cmd.attack(a, dd);
  if v_y ->> 'error_code' is distinct from 'E_FLEET_BUSY' or (v_y -> 'ok')::boolean then
    raise exception 'PROOF 33 FAIL: the door''s refusal: %', v_y;
  end if;
  raise notice 'PASS: ATTACK_PREVIEW';
end
$$;

-- ── LOOT ──
do $$
declare
  t0  timestamptz := now();
  a   uuid := pg_temp.house_33(13);
  p   uuid := (select f.player_id from public.fleets f where f.id = a);
  d   uuid := pg_temp.ship_33(200000, t0);
  v_sum bigint;
  v_total bigint;
  v_set bigint;
  v_purse bigint;
  v_flows bigint;
  v_load bigint := (select x.load_id from public.cargo_ship_aboard(d) x);
  v_b uuid;
begin
  perform pg_temp.lie_by(a, d, t0);
  perform public.stats_live_fold(now());
  v_sum := pg_temp.purses();
  v_total := (world.stats_now() ->> 'total')::bigint;
  v_set := public.funds_aboard();
  v_purse := (select pl.ducats from public.players pl where pl.id = p);
  v_flows := (select count(*) from public.treasury_flows);
  v_b := pg_temp.fight_33(a, d, t0, 'PLUNDERED');
  if (select pl.ducats from public.players pl where pl.id = p) - v_purse <> 30000 then
    raise exception 'PROOF 33 FAIL: boarded, 15 %% of 200,000 is 30,000, and she took %', (select pl.ducats from public.players pl where pl.id = p) - v_purse;
  end if;
  if public.funds_aboard() <> v_set - 30000 or (select x.aboard from public.cargo_ship_aboard(d) x) is distinct from 170000::bigint then
    raise exception 'PROOF 33 FAIL: the funds aboard did not fall by what she took';
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 33 FAIL: every purse summed moved by %', pg_temp.purses() - v_sum;
  end if;
  if (select count(*) from public.treasury_flows) <> v_flows then
    raise exception 'PROOF 33 FAIL: a city purse moved';
  end if;
  if (select count(*) from public.convoy_cargo c where c.load_id = v_load and c.stage = 'LOOTED' and c.ducats = 30000) <> 1
     or (select count(*) from public.ledger l where l.player_id = p and l.kind = 'LOOT' and l.ducats_delta = 30000) <> 1 then
    raise exception 'PROOF 33 FAIL: one book row and one ledger row';
  end if;
  if (world.stats_now() ->> 'total')::bigint <> v_total then
    raise exception 'PROOF 33 FAIL: the live figure moved: % against %', (world.stats_now() ->> 'total')::bigint, v_total;
  end if;
  perform public.stats_live_fold(now());
  if (world.stats_now() ->> 'total')::bigint <> v_total then
    raise exception 'PROOF 33 FAIL: the fold found drift: % against %', (world.stats_now() ->> 'total')::bigint, v_total;
  end if;
  if ((select b.result from public.battles b where b.id = v_b) ->> 'loot')::bigint is distinct from 30000::bigint then
    raise exception 'PROOF 33 FAIL: the battle does not say what it paid';
  end if;
  if (select w.side from public.stats_flow_words w where w.kind = 'LOOT') <> 'moved' then
    raise exception 'PROOF 33 FAIL: LOOT is not moved';
  end if;

  -- THE REST SAILS ON: her load closes, to the ducat, and no further. A ship cannot give what she has lost.
  begin
    perform public.convoy_book('RETURNED', d, (select c.player_id from public.cargo_ships c where c.fleet_id = d), (select l.port_id from public.convoy_cargo l where l.id = v_load), 170001, v_load);
    raise exception 'PROOF 33 FAIL: a load closed past what she carried';
  exception when others then
    if sqlerrm !~ '^E_CARGO_OVER' then raise; end if;
  end;
  perform public.convoy_book('RETURNED', d, (select c.player_id from public.cargo_ships c where c.fleet_id = d), (select l.port_id from public.convoy_cargo l where l.id = v_load), 170000, v_load);
  if exists (select 1 from public.cargo_ship_aboard(d)) or pg_temp.purses() <> v_sum then
    raise exception 'PROOF 33 FAIL: the rest did not go home whole';
  end if;
  raise notice 'PASS: LOOT_BOARDED';
  raise notice 'PASS: LOOT_THE_REST';
end
$$;

do $$
declare
  t0   timestamptz := now();
  a    uuid := pg_temp.house_33(14);
  p    uuid := (select f.player_id from public.fleets f where f.id = a);
  v_t  timestamptz;
  v_k  int := 0;
  v_d  uuid;
  v_was bigint;
  v_sum bigint;
  x    record;
begin
  v_sum := pg_temp.purses();
  -- aboard, what the fight should pay: 1,000,000 × 3 at the ship's cap; 200,000 at the share; 1,000,000 at what is left of the day; then nothing at all
  for x in select * from (values (1000000::bigint, 60000::bigint), (1000000, 60000), (1000000, 60000), (200000, 30000), (1000000, 30000), (1000000, 0)) c(aboard, want) loop
    v_t := t0 + make_interval(mins => v_k * 40);
    v_k := v_k + 1;
    v_d := pg_temp.ship_33(x.aboard, v_t);
    perform pg_temp.lie_by(a, v_d, v_t);
    v_was := (select pl.ducats from public.players pl where pl.id = p);
    perform pg_temp.fight_33(a, v_d, v_t, 'PLUNDERED');
    if (select pl.ducats from public.players pl where pl.id = p) - v_was <> x.want then
      raise exception 'PROOF 33 FAIL: fight %: wanted %, took %', v_k, x.want, (select pl.ducats from public.players pl where pl.id = p) - v_was;
    end if;
    if public.loot_today(p, v_t + interval '11 minutes') > public.wc_num('loot_per_company_day') then
      raise exception 'PROOF 33 FAIL: a company passed her day';
    end if;
  end loop;
  -- a little aboard: never more than is there
  if public.loot_due('PLUNDERED', 3, 0) <> 0 or public.loot_due('RANSOM', 12, 0) <> 0 or public.loot_due('PLUNDERED', 7, 0) <> 1 then
    raise exception 'PROOF 33 FAIL: the small sums do not round down';
  end if;
  -- the day comes back: 25 hours on the ledger's rows are out of the window
  if public.loot_today(p, t0 + interval '25 hours') <> 0 then
    raise exception 'PROOF 33 FAIL: the day did not come back: %', public.loot_today(p, t0 + interval '25 hours');
  end if;
  v_t := t0 + interval '25 hours';
  v_d := pg_temp.ship_33(1000000, v_t);
  perform pg_temp.lie_by(a, v_d, v_t);
  v_was := (select pl.ducats from public.players pl where pl.id = p);
  perform pg_temp.fight_33(a, v_d, v_t, 'PLUNDERED');
  if (select pl.ducats from public.players pl where pl.id = p) - v_was <> 60000 then
    raise exception 'PROOF 33 FAIL: the new day paid %', (select pl.ducats from public.players pl where pl.id = p) - v_was;
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 33 FAIL: every purse summed moved by %', pg_temp.purses() - v_sum;
  end if;
  raise notice 'PASS: LOOT_CAPS';
end
$$;

do $$
declare
  t0  timestamptz := now();
  a   uuid := pg_temp.house_33(15);
  p   uuid := (select f.player_id from public.fleets f where f.id = a);
  d   uuid := pg_temp.ship_33(100000, t0);
  e   uuid;
  v_was bigint := (select pl.ducats from public.players pl where pl.id = p);
  v_sum bigint;
  v_crew int;
begin
  v_sum := pg_temp.purses();
  update public.ships s set crew = 50 where s.fleet_id = d;
  perform pg_temp.lie_by(a, d, t0);
  perform pg_temp.fight_33(a, d, t0, 'RANSOM');
  if (select pl.ducats from public.players pl where pl.id = p) - v_was <> 8000 then
    raise exception 'PROOF 33 FAIL: she paid off, 8 %% of 100,000, and took %', (select pl.ducats from public.players pl where pl.id = p) - v_was;
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 33 FAIL: a ransom moved the sum';
  end if;
  if (select sum(s.crew) from public.ships s where s.fleet_id = d) <> 50 or (select sum(s.crew) from public.ships s where s.fleet_id = a) <> 100 then
    raise exception 'PROOF 33 FAIL: a ransom cost hands';
  end if;
  -- a ransom has the ship's cap too
  e := pg_temp.ship_33(10000000, t0 + interval '40 minutes');
  perform pg_temp.lie_by(a, e, t0 + interval '40 minutes');
  v_was := (select pl.ducats from public.players pl where pl.id = p);
  perform pg_temp.fight_33(a, e, t0 + interval '40 minutes', 'RANSOM');
  if (select pl.ducats from public.players pl where pl.id = p) - v_was <> 60000 then
    raise exception 'PROOF 33 FAIL: a ransom passed the ship''s cap: %', (select pl.ducats from public.players pl where pl.id = p) - v_was;
  end if;
  raise notice 'PASS: LOOT_RANSOM';
end
$$;

-- ── BEATEN, BROKEN OFF, SLIPPED, BOARDED: THE HANDS ──
do $$
declare
  t0  timestamptz := now();
  v_k int := 15;
  x   record;
  a   uuid;
  d   uuid;
  p   uuid;
  v_was bigint;
  v_r0 numeric;
  c   public.cargo_ships%rowtype;
  v_b uuid;
begin
  for x in select * from (values ('DRIVEN_OFF', 90, 49), ('BROKE', 90, 49), ('SLIPPED', 100, 50), ('EVADED', 100, 50), ('PLUNDERED', 100, 45), ('RANSOM', 100, 50)) c(outcome, a_crew, d_crew) loop
    v_k := v_k + 1;
    a := pg_temp.house_33(v_k);
    p := (select f.player_id from public.fleets f where f.id = a);
    d := pg_temp.ship_33(100000, t0);
    select * into c from public.cargo_ships y where y.fleet_id = d;
    update public.ships s set crew = 50 where s.fleet_id = d;
    perform pg_temp.lie_by(a, d, t0);
    v_was := (select pl.ducats from public.players pl where pl.id = p);
    v_r0 := public.regard_of(p, c.nation_id);
    v_b := pg_temp.fight_33(a, d, t0, x.outcome);
    if x.outcome not in ('PLUNDERED', 'RANSOM') and (select pl.ducats from public.players pl where pl.id = p) <> v_was then
      raise exception 'PROOF 33 FAIL: % paid gold', x.outcome;
    end if;
    if (select sum(s.crew) from public.ships s where s.fleet_id = a) <> x.a_crew or (select sum(s.crew) from public.ships s where s.fleet_id = d) <> x.d_crew then
      raise exception 'PROOF 33 FAIL: %: wanted hands % and %, have % and %', x.outcome, x.a_crew, x.d_crew,
        (select sum(s.crew) from public.ships s where s.fleet_id = a), (select sum(s.crew) from public.ships s where s.fleet_id = d);
    end if;
    if round(public.regard_of(p, c.nation_id) - v_r0, 3) <> -150 then
      raise exception 'PROOF 33 FAIL: %: the regard did not stand', x.outcome;
    end if;
  end loop;
  raise notice 'PASS: ATTACK_BEATEN';
end
$$;

-- ── SUNK ──
do $$
declare
  t0  timestamptz := now();
  a   uuid := pg_temp.house_33(30);
  p   uuid := (select f.player_id from public.fleets f where f.id = a);
  d   uuid := pg_temp.ship_33(100000, t0);
  e   uuid;
  c   public.cargo_ships%rowtype;
  v_sum bigint;
  v_r0 numeric;
  v_home bigint;
begin
  -- DARK WRECKS: she sails on with what is left, and the hull is at 0
  select * into c from public.cargo_ships y where y.fleet_id = d;
  perform pg_temp.lie_by(a, d, t0);
  v_r0 := public.regard_of(p, c.nation_id);
  v_sum := pg_temp.purses();
  perform pg_temp.fight_33(a, d, t0, 'SUNK');
  if round(public.regard_of(p, c.nation_id) - v_r0, 3) <> -250 then
    raise exception 'PROOF 33 FAIL: sinking her cost %, not 250', round(public.regard_of(p, c.nation_id) - v_r0, 3);
  end if;
  if (select f.status from public.fleets f where f.id = d) <> 'SAILING' or (select x.aboard from public.cargo_ship_aboard(d) x) is distinct from 85000::bigint then
    raise exception 'PROOF 33 FAIL: dark, a sunk ship must sail on with the rest';
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 33 FAIL: dark, the sum moved';
  end if;

  -- LIT: loot first, then the rest home, and her voyage ends
  update public.world_config set value = 'true'::jsonb where key = 'npc_refits_enabled';
  e := pg_temp.ship_33(100000, t0 + interval '40 minutes');
  select * into c from public.cargo_ships y where y.fleet_id = e;
  perform pg_temp.lie_by(a, e, t0 + interval '40 minutes');
  v_sum := pg_temp.purses();
  v_home := public.treasury_balance(c.home_port_id);
  perform pg_temp.fight_33(a, e, t0 + interval '40 minutes', 'SUNK');
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  if (select f.status from public.fleets f where f.id = e) <> 'UNABLE_TO_SAIL' or (select f.port_id from public.fleets f where f.id = e) <> c.home_port_id
     or (select f.busy_until from public.fleets f where f.id = e) is not null then
    raise exception 'PROOF 33 FAIL: lit, a wreck did not lie at her origin';
  end if;
  if exists (select 1 from public.voyages v where v.fleet_id = e and v.status = 'SAILING') then
    raise exception 'PROOF 33 FAIL: lit, a wreck''s voyage did not end';
  end if;
  if exists (select 1 from public.cargo_ship_aboard(e)) or public.treasury_balance(c.home_port_id) - v_home <> 85000 then
    raise exception 'PROOF 33 FAIL: lit, the rest did not go home: %', public.treasury_balance(c.home_port_id) - v_home;
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 33 FAIL: lit, the sum moved by %', pg_temp.purses() - v_sum;
  end if;
  raise notice 'PASS: ATTACK_SUNK';
end
$$;

-- ── ONCE, THE SWITCH, THE REPORT ──
do $$
declare
  c_uid constant uuid := '00000000-0327-4000-8000-000000000031';
  t0  timestamptz := now();
  a   uuid := pg_temp.house_33(31);
  p   uuid := (select f.player_id from public.fleets f where f.id = a);
  d   uuid := pg_temp.ship_33(100000, t0);
  e   uuid := pg_temp.ship_33(100000, t0);
  h   uuid := (select c.player_id from public.cargo_ships c where c.fleet_id = d);
  v_b uuid;
  v_was bigint;
  v_rep jsonb;
begin
  perform pg_temp.lie_by(a, d, t0);
  v_b := (public.attack_for(p, a, d, null, t0) ->> 'battle_id')::uuid;

  -- the switch off: new ones refused, this one runs on
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
  if pg_temp.code_of(a, e, t0 + interval '1 second') is distinct from 'E_NOT_IN_USE' then
    raise exception 'PROOF 33 FAIL: the switch off left the door open';
  end if;
  v_was := (select pl.ducats from public.players pl where pl.id = p);
  perform set_config('byeharu.proof_fight', 'PLUNDERED', true);
  perform public.tick_battles(t0 + interval '601 seconds');   -- it also closes what the proofs above left open
  if (select b.status from public.battles b where b.id = v_b) <> 'RESOLVED' then
    raise exception 'PROOF 33 FAIL: the job did not take the battle';
  end if;
  if (select pl.ducats from public.players pl where pl.id = p) - v_was <> 15000 then
    raise exception 'PROOF 33 FAIL: the switch off stopped a running battle''s gold';
  end if;
  raise notice 'PASS: ATTACK_SWITCH_OFF';

  -- once: the job has closed all it can, so a second run finds nothing
  perform public.tick_battles(t0 + interval '1 hour');
  if public.battle_resolve(v_b, t0 + interval '1 hour') or public.tick_battles(t0 + interval '1 hour') <> 0
     or (select pl.ducats from public.players pl where pl.id = p) - v_was <> 15000
     or (select count(*) from public.events e2 where e2.player_id = p and e2.kind = 'BATTLE_REPORT' and (e2.payload ->> 'battle_id')::uuid = v_b) <> 1 then
    raise exception 'PROOF 33 FAIL: a retry did something';
  end if;
  perform set_config('byeharu.proof_fight', '', true);
  raise notice 'PASS: ATTACK_ONCE';

  select e2.payload into v_rep from public.events e2 where e2.player_id = p and e2.kind = 'BATTLE_REPORT' and (e2.payload ->> 'battle_id')::uuid = v_b;
  if (v_rep ->> 'loot')::bigint is distinct from 15000::bigint or (v_rep ->> 'crew_lost')::int is distinct from 0 or v_rep ->> 'outcome' is distinct from 'PLUNDERED' or jsonb_array_length(v_rep -> 'lines') < 1 then
    raise exception 'PROOF 33 FAIL: the report: %', v_rep;
  end if;
  if exists (select 1 from public.events e2 where e2.player_id = h and e2.kind = 'BATTLE_REPORT') then
    raise exception 'PROOF 33 FAIL: an NPC house had a report';
  end if;
  raise notice 'PASS: ATTACK_REPORT';
end
$$;

-- ── A PROBE IS STILL A PROBE: hulls, and nothing else ──
do $$
declare
  t0  timestamptz := now();
  a   uuid := pg_temp.house_33(33);
  p   uuid := (select f.player_id from public.fleets f where f.id = a);
  d   uuid := pg_temp.ship_33(100000, t0);
  v_b uuid;
  v_was bigint := (select pl.ducats from public.players pl where pl.id = p);
begin
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  update public.ships s set crew = 50 where s.fleet_id = d;
  perform pg_temp.lie_by(a, d, t0);
  v_b := public.battle_open('PROBE', a, d, t0);
  perform set_config('byeharu.proof_fight', 'PLUNDERED', true);
  perform public.battle_resolve(v_b, t0 + interval '601 seconds');
  perform set_config('byeharu.proof_fight', '', true);
  if (select pl.ducats from public.players pl where pl.id = p) <> v_was or (select x.aboard from public.cargo_ship_aboard(d) x) is distinct from 100000::bigint
     or (select sum(s.crew) from public.ships s where s.fleet_id = d) <> 50 or (select b.result from public.battles b where b.id = v_b) ? 'loot'
     or (select e.payload from public.events e where e.player_id = p and e.kind = 'BATTLE_REPORT' and (e.payload ->> 'battle_id')::uuid = v_b) ? 'loot' then
    raise exception 'PROOF 33 FAIL: a probe closed as an attack';
  end if;
  raise notice 'PASS: ATTACK_PROBE';
end
$$;

-- ── THE REAL ENGINE ──
do $$
declare
  t0  timestamptz := now();
  a   uuid := pg_temp.house_33(32);
  p   uuid := (select f.player_id from public.fleets f where f.id = a);
  d   uuid := pg_temp.ship_33(100000, t0);
  v_b uuid;
  v_sum bigint;
  v_was bigint := (select pl.ducats from public.players pl where pl.id = p);
  v_r jsonb;
  v_got bigint;
begin
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  perform set_config('byeharu.proof_fight', '', true);
  perform pg_temp.lie_by(a, d, t0);
  v_sum := pg_temp.purses();
  v_b := (public.attack_for(p, a, d, null, t0) ->> 'battle_id')::uuid;
  if not public.battle_resolve(v_b, t0 + interval '601 seconds') then
    raise exception 'PROOF 33 FAIL: the real battle did not close';
  end if;
  v_r := (select b.result from public.battles b where b.id = v_b);
  v_got := (select pl.ducats from public.players pl where pl.id = p) - v_was;
  if v_got <> public.loot_due(v_r ->> 'outcome', 100000, 0) or (v_r ->> 'loot')::bigint <> v_got then
    raise exception 'PROOF 33 FAIL: the real fight said %, and she took %', v_r ->> 'outcome', v_got;
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 33 FAIL: the real fight moved the sum';
  end if;
  raise notice 'PASS: ATTACK_REAL_FIGHT';
end
$$;

do $$
begin
  alter function public.fight_sides(uuid, integer, jsonb, jsonb, jsonb) rename to fight_sides_stub_33;
  alter function public.fight_sides_real_33(uuid, integer, jsonb, jsonb, jsonb) rename to fight_sides;
  drop function public.fight_sides_stub_33(uuid, integer, jsonb, jsonb, jsonb);
  drop function voyage.hazard_roll(uuid, integer);
  alter function voyage.hazard_roll_real_33(uuid, integer) rename to hazard_roll;
end
$$;
