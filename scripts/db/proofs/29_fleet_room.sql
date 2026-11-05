-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 29 — A SHIP CHANGES FLEETS  (migration 0321, slice W4 of docs/WORLD_POWERS.md, F1 + F2 of docs/FLEETS_AND_SLOTS.md)
--
--   0321's own self-assert reads the catalog only: a migration never runs a real game step (docs/OPS_HEALTH.md section 4). This proof runs the REAL caps, trigger and core on probe companies,
--   all rolled back. The pre-images are the live bodies with 0321's hunks taken out again, so "dark equals today's caps" is measured, not taken on trust.
--
-- @pass ROOM_DARK_CAPS     dark, a human and a merchant, levels and bought rows planted: earned_caps and house_ship_max read exactly the pre-images, and the trigger still refuses as today
-- @pass MOVE_DARK          dark, the core refuses E_NOT_IN_USE and nothing moves; no row, no event
-- @pass ROOM_LIT_FLEETS    lit, fleets: the free two, each Trading rung, bought steps, never above fleet_hard_max; the trigger reads it
-- @pass ROOM_LIT_SHIPS     lit, ships: base + the higher of Seamanship and Command + bought, never above fleet_ship_top; a merchant keeps her flat cap and hull cap; house_ship_max is fleets x ships
-- @pass MOVE_ABOARD        a ship moves with cargo, stores and crew, no money moves, both fleets' versions rise, the event is written, and each fleet's figures follow her
-- @pass MOVE_FLAGSHIP      her heir is tier, then hold; a ship joining a flagship's fleet is not one; each fleet has exactly one
-- @pass MOVE_REFUSALS      every refusal: not hers, other company's fleet, same fleet, both or neither target, at sea, anchored, repairing, other port, pending order, port time, full fleet, bad name, name taken, no room
-- @pass MOVE_NEW_FLEET     a new fleet is formed at her port through public.form_fleet, DOCKED, she its flagship
-- @pass MOVE_EMPTY         her last ship gone, a fleet lies UNABLE_TO_SAIL, no presence, no order, no tow, counts as open, a route on her reads blocked; the next ship places her from any port, DOCKED
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_lis uuid := (select id from public.ports where code = 'LIS');
  v_opo uuid := (select id from public.ports where code = 'OPO');
  v_prt uuid := (select id from public.nations where code = 'PRT');
  v_a   uuid;      -- a probe human company
  v_b   uuid;      -- another human company
  v_m   uuid;      -- a probe merchant
  v_f1  uuid;
  v_f2  uuid;
  v_f3  uuid;
  v_fb  uuid;
  v_s1  uuid;
  v_s2  uuid;
  v_s3  uuid;
  v_s4  uuid;
  v_s5  uuid;
  v_good text;
  v_r   jsonb;
  v_x   jsonb;
  v_n   bigint;
  v_v1  int;
  v_v2  int;
  v_ev0 bigint;
  v_gold bigint;
  v_c1  numeric;
  v_err text;
  v_def text;
  v_route uuid;
  s     record;
begin
  if public.fleet_room_on() then
    raise exception 'PROOF 29 FAIL: the room is not dark in this world';
  end if;
  -- the refusal a call gives, or NOT REFUSED; its sub-transaction takes everything back
  execute $f$
    create function pg_temp.refused(p_who uuid, p_ship uuid, p_to uuid, p_name text) returns text language plpgsql as $b$
    begin
      perform public.move_ship(p_who, p_ship, p_to, p_name);
      return 'NOT REFUSED';
    exception when others then
      if sqlerrm !~ '^E_[A-Z0-9_]+' then raise; end if;
      return split_part(sqlerrm, ':', 1);
    end $b$
  $f$;

  -- ── THE PROBES ──
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Casa Room 0f29', v_prt, 5000000, false) returning id into v_a;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Casa Other 0f29', v_prt, 5000000, false) returning id into v_b;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Merchant Room 0f29', v_prt, 5000000, true) returning id into v_m;

  -- ── THE PRE-IMAGES: the live bodies with 0321's hunks taken out ──
  v_def := replace(pg_get_functiondef('public.earned_caps(uuid)'::regprocedure), E'\r', '');
  if position('public.fleet_room_on() then public.fleet_room_caps(p_player)' in v_def) = 0 then
    raise exception 'PROOF 29 FAIL: earned_caps does not carry its hunk';
  end if;
  v_def := regexp_replace(v_def, E'select case when public\\.fleet_room_on\\(\\) then public\\.fleet_room_caps\\(p_player\\)[^\n]*\n    when exists', 'select case when exists');
  execute regexp_replace(v_def, 'CREATE OR REPLACE FUNCTION public\.earned_caps\(', 'CREATE OR REPLACE FUNCTION pg_temp.pre_earned_caps(');
  v_def := replace(pg_get_functiondef('public.house_ship_max(uuid)'::regprocedure), E'\r', '');
  v_def := regexp_replace(v_def, E'select case when public\\.fleet_room_on\\(\\)[^\n]*\n[^\n]*\n    else public\\.wc_int', 'select public.wc_int');
  v_def := replace(v_def, 'else 0 end end', 'else 0 end');
  execute regexp_replace(v_def, 'CREATE OR REPLACE FUNCTION public\.house_ship_max\(', 'CREATE OR REPLACE FUNCTION pg_temp.pre_house_ship_max(');

  -- ── DARK ──
  insert into public.house_room (player_id, kind, steps) values (v_a, 'FLEET', 3), (v_a, 'SHIP', 5), (v_m, 'FLEET', 3), (v_m, 'SHIP', 5);
  insert into public.player_skills (player_id, skill_id, level) select v_a, k.id, 3 from public.skills k where k.code in ('SEAMANSHIP', 'COMMAND');
  for s in select x as who from (values (v_a), (v_b), (v_m)) t(x) loop
    if public.earned_caps(s.who) is distinct from pg_temp.pre_earned_caps(s.who) then
      raise exception 'PROOF 29 FAIL: dark, the caps moved for %: % against %', s.who, public.earned_caps(s.who), pg_temp.pre_earned_caps(s.who);
    end if;
    if public.house_ship_max(s.who) is distinct from pg_temp.pre_house_ship_max(s.who) then
      raise exception 'PROOF 29 FAIL: dark, the hull cap moved for %: % against %', s.who, public.house_ship_max(s.who), pg_temp.pre_house_ship_max(s.who);
    end if;
  end loop;
  delete from public.house_room where player_id in (v_a, v_m);
  delete from public.player_skills where player_id = v_a;
  v_f1 := public.form_fleet(v_a, 'First 0f29', v_lis);
  v_f2 := public.form_fleet(v_a, 'Second 0f29', v_lis);
  begin
    perform public.form_fleet(v_a, 'Third 0f29', v_lis);
    raise exception 'PROOF 29 FAIL: dark, a third fleet formed';
  exception when others then
    if sqlerrm not like 'E_FLEET_MAX%' then raise; end if;
  end;
  v_s1 := public.commission_ship(v_a, v_f1, 'barca', 'Uno 0f29', true, true);
  v_s2 := public.commission_ship(v_a, v_f1, 'nau', 'Dos 0f29', false, true);
  begin
    perform public.commission_ship(v_a, v_f1, 'barca', 'Tres 0f29', false, true);
    raise exception 'PROOF 29 FAIL: dark, a third ship in a fleet of base 2';
  exception when others then
    if sqlerrm not like 'E_FLEET_SHIP_MAX%' then raise; end if;
  end;
  raise notice 'PASS: ROOM_DARK_CAPS — dark, human and merchant, with rows planted: the pre-images to the byte, and the trigger as today';

  select count(*) into v_ev0 from public.events e where e.player_id = v_a;
  begin
    perform public.move_ship(v_a, v_s2, v_f2, null);
    raise exception 'PROOF 29 FAIL: dark, the core moved a ship';
  exception when others then
    if sqlerrm not like 'E_NOT_IN_USE%' then raise; end if;
  end;
  if (select fleet_id from public.ships where id = v_s2) <> v_f1 or (select count(*) from public.events e where e.player_id = v_a) <> v_ev0
     or exists (select 1 from public.house_room) then
    raise exception 'PROOF 29 FAIL: dark, the refused core left a mark';
  end if;
  raise notice 'PASS: MOVE_DARK — E_NOT_IN_USE, nothing moved';

  -- ── LIT: THE LADDERS ──
  update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite';
  if (public.earned_caps(v_b) ->> 'fleet_max')::int <> 2 then
    raise exception 'PROOF 29 FAIL: lit, a new company has % fleets, not the free two', public.earned_caps(v_b) ->> 'fleet_max';
  end if;
  -- a rung reached: every company is at Trading 1 or more, so a rung at 1 is reached and one at 99 is not
  update public.world_config set value = '[1, 99]'::jsonb where key = 'fleet_room_levels';
  if (public.earned_caps(v_b) ->> 'fleet_max')::int <> 3 then
    raise exception 'PROOF 29 FAIL: lit, one rung reached gives % fleets, not 3', public.earned_caps(v_b) ->> 'fleet_max';
  end if;
  insert into public.house_room (player_id, kind, steps) values (v_b, 'FLEET', 1);
  if (public.earned_caps(v_b) ->> 'fleet_max')::int <> 4 then
    raise exception 'PROOF 29 FAIL: lit, a rung and a bought step give % fleets, not 4', public.earned_caps(v_b) ->> 'fleet_max';
  end if;
  update public.house_room set steps = 9 where player_id = v_b;
  if (public.earned_caps(v_b) ->> 'fleet_max')::int <> public.wc_int('fleet_hard_max') then
    raise exception 'PROOF 29 FAIL: lit, the fleets pass fleet_hard_max: %', public.earned_caps(v_b) ->> 'fleet_max';
  end if;
  update public.house_room set steps = 0 where player_id = v_b;
  update public.world_config set value = '[3, 6]'::jsonb where key = 'fleet_room_levels';
  raise notice 'PASS: ROOM_LIT_FLEETS — free two, a rung, a bought step, the hard top; the trigger is tried in MOVE_REFUSALS';

  if (public.earned_caps(v_b) ->> 'fleet_ship_max')::int <> 2 then
    raise exception 'PROOF 29 FAIL: lit, a new company holds % ships a fleet, not 2', public.earned_caps(v_b) ->> 'fleet_ship_max';
  end if;
  insert into public.player_skills (player_id, skill_id, level) select v_b, k.id, 1 from public.skills k where k.code = 'SEAMANSHIP';
  insert into public.player_skills (player_id, skill_id, level) select v_b, k.id, 2 from public.skills k where k.code = 'COMMAND';
  if (public.earned_caps(v_b) ->> 'fleet_ship_max')::int <> 4 then
    raise exception 'PROOF 29 FAIL: lit, the higher of two skills gives %, not 4', public.earned_caps(v_b) ->> 'fleet_ship_max';
  end if;
  insert into public.house_room (player_id, kind, steps) values (v_b, 'SHIP', 2);
  if (public.earned_caps(v_b) ->> 'fleet_ship_max')::int <> 6 then
    raise exception 'PROOF 29 FAIL: lit, levels and gold do not add up: %, not 6', public.earned_caps(v_b) ->> 'fleet_ship_max';
  end if;
  if public.house_ship_max(v_b) <> 12 then
    raise exception 'PROOF 29 FAIL: lit, the hull cap is %, not 2 fleets x 6', public.house_ship_max(v_b);
  end if;
  update public.house_room set steps = 9 where player_id = v_b and kind = 'SHIP';
  if (public.earned_caps(v_b) ->> 'fleet_ship_max')::int <> public.wc_int('fleet_ship_top') then
    raise exception 'PROOF 29 FAIL: lit, a fleet passes fleet_ship_top: %', public.earned_caps(v_b) ->> 'fleet_ship_max';
  end if;
  delete from public.player_skills where player_id = v_b;
  delete from public.house_room where player_id = v_b;
  if (public.earned_caps(v_m) ->> 'fleet_max')::int <> public.wc_int('fleet_max')
     or (public.earned_caps(v_m) ->> 'fleet_ship_max')::int <> least(public.wc_int('fleet_ship_max'), public.wc_int('fleet_ship_top'))
     or (public.earned_caps(v_m) ->> 'earned')::boolean is not false
     or public.house_ship_max(v_m) <> pg_temp.pre_house_ship_max(v_m) then
    raise exception 'PROOF 29 FAIL: lit, a merchant is not on the flat rules: %, hulls %', public.earned_caps(v_m), public.house_ship_max(v_m);
  end if;
  raise notice 'PASS: ROOM_LIT_SHIPS — base, the higher skill, bought, the top; a merchant flat; hulls = fleets x ships';

  -- ── LIT: A SHIP MOVES ──
  insert into public.house_room (player_id, kind, steps) values (v_a, 'SHIP', 3);   -- room for 5 ships a fleet
  v_s3 := public.commission_ship(v_a, v_f2, 'barca', 'Tres 0f29', true, true);
  v_good := (select g.code from public.goods g order by g.code limit 1);
  update public.ships set cargo = jsonb_build_object(v_good, 3), cargo_basis = jsonb_build_object(v_good, 40), water_t = 2.5, food_t = 1.5 where id = v_s2;
  v_x := (select to_jsonb(x) - 'fleet_id' - 'is_flagship' from public.ships x where x.id = v_s2);
  select version into v_v1 from public.fleets where id = v_f1;
  select version into v_v2 from public.fleets where id = v_f2;
  select ducats into v_gold from public.players where id = v_a;
  select count(*) into v_ev0 from public.events e where e.player_id = v_a;
  select count(*) into v_n from public.ledger l where l.player_id = v_a;
  v_c1 := public.fleet_free_hold(v_f2);
  v_r := public.move_ship(v_a, v_s2, v_f2, null);
  if v_r ->> 'to' <> 'Second 0f29' or (v_r ->> 'new_fleet')::boolean or (v_r ->> 'empty')::boolean then
    raise exception 'PROOF 29 FAIL: the answer is wrong: %', v_r;
  end if;
  if (select fleet_id from public.ships where id = v_s2) <> v_f2
     or (select to_jsonb(x) - 'fleet_id' - 'is_flagship' from public.ships x where x.id = v_s2) is distinct from v_x then
    raise exception 'PROOF 29 FAIL: she did not arrive whole';
  end if;
  if (select ducats from public.players where id = v_a) <> v_gold or (select count(*) from public.ledger l where l.player_id = v_a) <> v_n then
    raise exception 'PROOF 29 FAIL: money moved';
  end if;
  if (select version from public.fleets where id = v_f1) <> v_v1 + 1 or (select version from public.fleets where id = v_f2) <> v_v2 + 1 then
    raise exception 'PROOF 29 FAIL: a fleet version did not rise, so a stale order could pass';
  end if;
  if (select count(*) from public.events e where e.player_id = v_a and e.kind = 'SHIP_MOVED') <> 1
     or (select count(*) from public.events e where e.player_id = v_a) <> v_ev0 + 1 then
    raise exception 'PROOF 29 FAIL: the event is not written once';
  end if;
  if public.fleet_free_hold(v_f2) <= v_c1 or (public.fleet_cargo_basis_map(v_f2) ->> v_good)::numeric <> 40
     or public.fleet_cargo_basis_map(v_f1) ? v_good then
    raise exception 'PROOF 29 FAIL: the fleets'' figures did not follow her';
  end if;
  raise notice 'PASS: MOVE_ABOARD — whole, no money, versions up, one event, the figures follow';

  -- the flagship: Dos joined a fleet with a flagship and is not one
  if (select is_flagship from public.ships where id = v_s2) then
    raise exception 'PROOF 29 FAIL: a ship joining a flagship''s fleet became a flagship';
  end if;
  if (select c.tier from public.ship_classes c where c.code = 'nau') <= (select c.tier from public.ship_classes c where c.code = 'barca') then
    raise exception 'PROOF 29 FAIL: this proof needs a nau above a barca';
  end if;
  v_s4 := public.commission_ship(v_a, v_f1, 'nau', 'Cuatro 0f29', false, true);
  v_s5 := public.commission_ship(v_a, v_f1, 'barca', 'Cinco 0f29', false, true);
  perform public.move_ship(v_a, v_s3, v_f1, null);   -- the flagship of the second leaves: Dos inherits
  if not (select is_flagship from public.ships where id = v_s2) or (select is_flagship from public.ships where id = v_s3) then
    raise exception 'PROOF 29 FAIL: the second fleet''s heir is wrong';
  end if;
  perform public.move_ship(v_a, v_s1, v_f2, null);   -- barcas and a nau stay: tier decides
  if not (select is_flagship from public.ships where id = v_s4) then
    raise exception 'PROOF 29 FAIL: the heir is not the highest tier';
  end if;
  perform public.move_ship(v_a, v_s4, v_f2, null);   -- two barcas stay: hold decides
  if not (select x.is_flagship from public.ships x where x.id = (
            select y.id from public.ships y where y.fleet_id = v_f1 order by public.ship_hold_capacity(y.id) desc, y.name, y.id limit 1)) then
    raise exception 'PROOF 29 FAIL: among one tier, the heir is not the largest hold';
  end if;
  if exists (select 1 from public.fleets f where f.player_id = v_a
              and (select count(*) from public.ships x where x.fleet_id = f.id and x.is_flagship) <> 1) then
    raise exception 'PROOF 29 FAIL: a fleet has not exactly one flagship';
  end if;
  raise notice 'PASS: MOVE_FLAGSHIP — tier, then hold; a joiner stands aside; one flagship each';

  -- ── EVERY REFUSAL ── the first fleet holds Tres and Cinco, the second Dos, Uno, Cuatro; 5 ships, room for 5 a fleet
  v_fb := public.form_fleet(v_b, 'Other 0f29', v_lis);
  perform public.commission_ship(v_b, v_fb, 'barca', 'Otra 0f29', true, true);
  for s in select * from (values
      ('another company''s ship',  v_b, v_s3, v_f2, null::text, 'E_NO_SUCH_SHIP'),
      ('another company''s fleet', v_a, v_s3, v_fb, null,       'E_NO_SUCH_FLEET'),
      ('the same fleet',           v_a, v_s3, v_f1, null,       'E_SAME_FLEET'),
      ('both a fleet and a name',  v_a, v_s3, v_f2, 'Nuevo',    'E_PARSE'),
      ('neither',                  v_a, v_s3, null, null,       'E_PARSE'),
      ('a blank name',             v_a, v_s3, null, '   ',      'E_PARSE'),
      ('a name of two letters',    v_a, v_s3, null, 'ab',       'E_PARSE'),
      ('a name in use',            v_a, v_s3, null, 'SECOND 0F29', 'E_NAME_TAKEN'),
      ('no room for a fleet',      v_a, v_s3, null, 'Third 0f29',  'E_FLEET_MAX')) t(what, who, ship, dest, nm, want) loop
    v_err := pg_temp.refused(s.who, s.ship, s.dest, s.nm);
    if v_err <> s.want then
      raise exception 'PROOF 29 FAIL: %: % and not %', s.what, v_err, s.want;
    end if;
  end loop;
  -- the source fleet's states, then the target's
  for s in select * from (values ('SAILING'), ('ANCHORED'), ('REPAIRING')) t(st) loop
    update public.fleets set status = s.st, port_id = case when s.st = 'REPAIRING' then v_lis end,
                             lat = case when s.st = 'ANCHORED' then 30 end, lon = case when s.st = 'ANCHORED' then -10 end where id = v_f1;
    v_err := pg_temp.refused(v_a, v_s3, v_f2, null);
    if v_err <> 'E_NOT_DOCKED' then
      raise exception 'PROOF 29 FAIL: from a fleet %: %', s.st, v_err;
    end if;
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_f1;
    update public.fleets set status = s.st, port_id = case when s.st = 'REPAIRING' then v_lis end,
                             lat = case when s.st = 'ANCHORED' then 30 end, lon = case when s.st = 'ANCHORED' then -10 end where id = v_f2;
    v_err := pg_temp.refused(v_a, v_s3, v_f2, null);
    if v_err <> 'E_NOT_DOCKED' then
      raise exception 'PROOF 29 FAIL: to a fleet %: %', s.st, v_err;
    end if;
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_f2;
  end loop;
  update public.fleets set port_id = v_opo where id = v_f2;
  v_err := pg_temp.refused(v_a, v_s3, v_f2, null);
  if v_err <> 'E_NOT_SAME_PORT' then
    raise exception 'PROOF 29 FAIL: to another port: %', v_err;
  end if;
  update public.fleets set port_id = v_lis where id = v_f2;
  for s in select * from (values (v_f1), (v_f2)) t(fl) loop
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status) values (s.fl, v_a, 9001, 'HIRE 1', 'HIRE', '{"count":1}'::jsonb, 'active');   -- a pending one would run in the core's own settle
    v_err := pg_temp.refused(v_a, v_s3, v_f2, null);
    if v_err <> 'E_FLEET_BUSY' then
      raise exception 'PROOF 29 FAIL: a pending order: %', v_err;
    end if;
    delete from public.orders where fleet_id = s.fl and seq = 9001;
    update public.fleets set ready_at = now() + interval '1 hour' where id = s.fl;
    v_err := pg_temp.refused(v_a, v_s3, v_f2, null);
    if v_err <> 'E_FLEET_BUSY' then
      raise exception 'PROOF 29 FAIL: port time: %', v_err;
    end if;
    update public.fleets set ready_at = null where id = s.fl;
  end loop;
  update public.house_room set steps = 1 where player_id = v_a and kind = 'SHIP';   -- room for 3 a fleet; the second holds 3
  v_err := pg_temp.refused(v_a, v_s3, v_f2, null);
  if v_err <> 'E_FLEET_SHIP_MAX' then
    raise exception 'PROOF 29 FAIL: a full fleet: %', v_err;
  end if;
  update public.house_room set steps = 3 where player_id = v_a and kind = 'SHIP';
  raise notice 'PASS: MOVE_REFUSALS — every door shut, and the world where it was';

  -- ── A NEW FLEET ──
  insert into public.house_room (player_id, kind, steps) values (v_a, 'FLEET', 1);
  v_r := public.move_ship(v_a, v_s3, null, '  Third 0f29 ');
  v_f3 := (v_r ->> 'fleet_id')::uuid;
  if not (v_r ->> 'new_fleet')::boolean
     or not exists (select 1 from public.fleets f where f.id = v_f3 and f.name = 'Third 0f29' and f.status = 'DOCKED' and f.port_id = v_lis)
     or not (select is_flagship from public.ships where id = v_s3) then
    raise exception 'PROOF 29 FAIL: the new fleet is wrong: %', v_r;
  end if;
  raise notice 'PASS: MOVE_NEW_FLEET — formed at her port, DOCKED, she its flagship';

  -- ── THE EMPTY FLEET ──
  insert into public.standing_routes (player_id, name, fleet_id, hold_until) values (v_a, 'Route 0f29', v_f3, now() - interval '1 hour') returning id into v_route;
  v_r := public.move_ship(v_a, v_s3, v_f1, null);
  if not (v_r ->> 'empty')::boolean
     or not exists (select 1 from public.fleets f where f.id = v_f3 and f.status = 'UNABLE_TO_SAIL' and f.port_id = v_lis) then
    raise exception 'PROOF 29 FAIL: the empty fleet does not lie UNABLE_TO_SAIL at her port';
  end if;
  if (select status from public.fleets where id = v_f1) <> 'DOCKED' then
    raise exception 'PROOF 29 FAIL: the fleet she joined left DOCKED';
  end if;
  if public.standing_route_state(v_route, true) <> 'blocked' then
    raise exception 'PROOF 29 FAIL: a route on an empty fleet reads %', public.standing_route_state(v_route, true);
  end if;
  v_r := cmd.enqueue(v_a, jsonb_build_object('fleet_id', v_f3, 'verb', 'HIRE', 'args', '{"count":1}'::jsonb), 'HIRE 1', null, null);
  if v_r ->> 'error_code' is distinct from 'E_FLEET_EMPTY' or exists (select 1 from public.orders o where o.fleet_id = v_f3) then
    raise exception 'PROOF 29 FAIL: an empty fleet took an order: %', v_r;
  end if;
  begin
    perform public.tow_for(v_a, v_f3);
    raise exception 'PROOF 29 FAIL: an empty fleet was towed';
  exception when others then
    if sqlerrm not like 'E_FLEET_EMPTY%' then raise; end if;
  end;
  -- every figure world.fleets asks of her answers, and raises nothing (speed is world.fleets' own hunk: tests/rpc.fleetroom.spec.ts reads the whole list)
  perform voyage.endurance_days(v_f3), public.fleet_free_hold(v_f3), public.fleet_wave(v_f3), public.fleet_cargo_basis_map(v_f3),
          public.crew_pct(v_f3, null, 'speed'), world.crew_bonuses(v_f3), cmd.queue(v_f3);
  v_err := pg_temp.refused(v_a, v_s5, null, 'Fourth 0f29');
  if v_err <> 'E_FLEET_MAX' then
    raise exception 'PROOF 29 FAIL: an empty fleet does not count as open: %', v_err;
  end if;
  update public.fleets set port_id = v_opo where id = v_f1;   -- the first now lies at Oporto; the empty fleet lay at Lisbon
  v_r := public.move_ship(v_a, v_s5, v_f3, null);
  if not exists (select 1 from public.fleets f where f.id = v_f3 and f.status = 'DOCKED' and f.port_id = v_opo and f.lat is null)
     or not (select is_flagship from public.ships where id = v_s5) or (v_r ->> 'empty')::boolean then
    raise exception 'PROOF 29 FAIL: the empty fleet did not take the joining ship''s port: %', v_r;
  end if;
  if public.standing_route_state(v_route, true) = 'blocked' then
    raise exception 'PROOF 29 FAIL: the route stayed blocked after a ship joined';
  end if;
  raise notice 'PASS: MOVE_EMPTY — no presence, no order, no tow, counted, blocked; refilled from any port';
end
$$;
