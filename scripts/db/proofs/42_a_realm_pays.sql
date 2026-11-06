-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 42 — A REALM PAYS FOR ITS NAVY  (migration 0335, owner row 285, question 9)
--
--   0335's self-assert runs the draw on a probe nation of its own and no game step (docs/OPS_HEALTH.md section 4). This proof lights navy_enabled and runs the REAL job and the REAL purses, on a real realm: a capital that
--   cannot pay, and the cities of its realm that can. The economy is CLOSED here, as on prod (CI's own world is open), and RP_OPEN runs the money once more with it open. No ship sails: navy_steps_per_run is 0, because proof 37 sails them.
--   Every purse is set by the proof's own hand, before the mark each reader counts from. Subjects are picked by code, and the proof checks it has them.
--
-- @pass RP_FOLD         public.crown_donors reads what 0307's statement read, for every capital: same harbours, same order, same room; public.capital_can_draw adds up the same rows
-- @pass RP_DARK         off: a poor capital and a rich realm: the job moves nothing, calls nothing
-- @pass RP_SHORT        a realm 1 d. short of a hull, the reserve's gap counted, writes nothing, run after run, and no gold walks to the capital
-- @pass RP_BUSY         a busy richest city leaves the realm short: the second city's call is rolled back, nothing moved, no hull, no error, and a busy capital still is passed over
-- @pass RP_BUILD        the richest city pays: exactly the need, by CROWN_CALL to the capital, then the capital pays the yard; nothing minted, no ledger row, the capital left with nothing above its reserve, a city outside the realm untouched
-- @pass RP_TWO          the richest gives its room and the next the rest, each once
-- @pass RP_RICH         a capital that can pay calls nothing
-- @pass RP_NO_FLOOR     no donor goes under its reserve, its aid target or its cover
-- @pass RP_PAY          an hour: the realm fills the capital for every ship at work; a ship at the capital moves nothing, and her slice stays there, so the next call is smaller by it and it cannot climb
-- @pass RP_PAY_PART     a realm that can pay one ship pays the lowest ord; the rest are unpaid, go home and lie up; no debt, no error
-- @pass RP_WAKE         a laid-up ship wakes on what the realm can give, and the wake moves no gold; the next hour pays her; a realm that cannot, wakes nobody
-- @pass RP_SHARE0       crown_call_share 0, 0307's rollback: no room, so the capital alone pays, as 0331
-- @pass RP_OPEN         with the economy open the same rows move
-- ════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_t     timestamptz := now();
  v_nat   uuid;
  v_cap   uuid;
  v_yard  uuid;
  v_st2   uuid;
  v_d1    uuid;
  v_d2    uuid;
  v_far   uuid;
  v_fl1   uuid;
  v_fl2   uuid;
  v_fl3   uuid;
  v_c     text;
  v_c1    text;
  v_c2    text;
  v_cost  bigint := (select c.build_cost from public.ship_classes c where c.code = public.wc_text('navy_ship_class'));
  v_slice bigint := round(public.wc_num('navy_upkeep_day') / 24);
  v_mark  bigint;
  v_led   bigint;
  v_ev    bigint;
  v_sum   bigint;
  v_gap   bigint;
  v_a     numeric;
  v_n     int;
  v_away  int;
  v_step  text;
  v_r     jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled');
  update public.world_config set value = 'false'::jsonb where key = 'navy_enabled';
  update public.world_config set value = to_jsonb(0.10) where key = 'crown_call_share';
  update public.world_config set value = to_jsonb(20) where key = 'crown_call_cover';
  update public.world_config set value = to_jsonb(0) where key = 'navy_steps_per_run';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 0, reserve = 0;

  execute $f$
create function pg_temp.purses()
returns bigint
language sql
as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;
  execute $f$
create function pg_temp.purse(p_port uuid, p_d bigint, p_reserve bigint default 0)
returns void
language plpgsql
as $b$
declare
  v_by bigint := p_d - public.treasury_balance(p_port);
begin
  update public.port_treasury t set reserve = p_reserve where t.port_id = p_port;
  if v_by <> 0 then
    perform public.treasury_post(p_port, 'CROWN_CALL', v_by, null, null, true);   -- a probe's hand on a purse: every reader below takes its mark after this
  end if;
end
$b$
  $f$;
  -- A purse whose room is exactly p_room: share 10 %, its aid target under it, reserve 0, so the cover asks nothing.
  execute $f$
create function pg_temp.room(p_port uuid, p_room bigint)
returns void
language plpgsql
as $b$
begin
  perform pg_temp.purse(p_port, public.city_aid_target(p_port) + p_room * 10);
  if public.crown_call_room(p_port) <> p_room then
    raise exception 'PROOF 42 FAIL: the proof''s own purse: room % asked, % read', p_room, public.crown_call_room(p_port);
  end if;
end
$b$
  $f$;
  -- Every harbour of a realm but the capital back to nothing, so the proof alone decides who can give.
  execute $f$
create function pg_temp.realm_bare(p_cap uuid)
returns void
language plpgsql
as $b$
declare
  h record;
begin
  for h in select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> p_cap and public.city_capital(p.id) = p_cap order by p.code loop
    perform pg_temp.purse(h.id, 0);
  end loop;
end
$b$
  $f$;
  execute $f$
create function pg_temp.moved(p_mark bigint, p_kind text)
returns jsonb
language sql
as $b$
  select coalesce(jsonb_object_agg(x.code, x.d), '{}'::jsonb)
    from (select p.code, sum(f.ducats)::bigint as d from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > p_mark and f.kind = p_kind group by p.code) x
$b$
  $f$;
  execute $f$
create function pg_temp.flows_from(p_mark bigint)
returns bigint
language sql
as $b$
  select count(*) from public.treasury_flows f where f.id > p_mark
$b$
  $f$;

  -- ── SUBJECTS ──
  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = 'PRT';
  v_yard := public.refit_yard(v_cap);
  v_far := (select public.realm_capital(g.nation_id) from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
  v_d1 := (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id not in (v_cap, v_yard) and public.city_capital(p.id) = v_cap order by p.code limit 1);
  v_d2 := (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id not in (v_cap, v_yard, v_d1) and public.city_capital(p.id) = v_cap order by p.code limit 1);
  if v_cap is null or v_yard is null or v_far is null or v_d1 is null or v_d2 is null then
    raise exception 'PROOF 42 FAIL: this proof needs a capital, a yard, two cities of its realm and a foreign harbour: % % % % %', v_cap, v_yard, v_d1, v_d2, v_far;
  end if;
  select p.code into v_c from public.ports p where p.id = v_cap;
  select p.code into v_c1 from public.ports p where p.id = v_d1;
  select p.code into v_c2 from public.ports p where p.id = v_d2;
  update public.ports p set crew_pool = 500;

  -- ── THE FOLD ──
  perform pg_temp.purse(v_d1, 90000000);
  perform pg_temp.purse(v_d2, 7050000, 1000);
  perform pg_temp.purse(v_far, 90000000);
  update public.port_treasury t set ducats = 3000000 + (abs(hashtextextended(t.port_id::text, 0)) % 1000000), reserve = abs(hashtextextended(t.port_id::text, 1)) % 50000
   where t.port_id not in (v_cap, v_d1, v_d2, v_far);
  v_n := 0;
  for v_r in select to_jsonb(g.nation_id) from public.great_powers g loop
    declare
      v_k     uuid := public.realm_capital((v_r #>> '{}')::uuid);
      v_new   jsonb;
      v_old   jsonb;
    begin
      select jsonb_agg(jsonb_build_array(d.id, d.room) order by d.rank) into v_new from public.crown_donors(v_k) d;
      select jsonb_agg(jsonb_build_array(y.id, y.room) order by y.room desc, y.code) into v_old
        from (select h.id, h.code, c.room from public.ports h join public.port_treasury t on t.port_id = h.id
               cross join lateral (select public.crown_call_room(h.id) as room) c
               where h.kind = 'HARBOUR' and h.id <> v_k and public.city_capital(h.id) = v_k and c.room > 0) y;
      if v_new is distinct from v_old then
        raise exception 'PROOF 42 FAIL: the lifted read differs from 0307''s at %: % against %', v_k, v_new, v_old;
      end if;
      if v_new is not null then
        v_n := v_n + jsonb_array_length(v_new);
        v_gap := public.city_surplus(v_k) + (select sum((e ->> 1)::bigint) from jsonb_array_elements(v_new) e);
        if not public.capital_can_draw(v_k, v_gap) or public.capital_can_draw(v_k, v_gap + 1) then
          raise exception 'PROOF 42 FAIL: can_draw at % does not stop exactly at what the realm can give, %', v_k, v_gap;
        end if;
      end if;
    end;
  end loop;
  if v_n < 2 then
    raise exception 'PROOF 42 FAIL: the fold was read over % donors', v_n;
  end if;
  update public.port_treasury set ducats = 0, reserve = 0;
  for v_r in select to_jsonb(p.id) from public.ports p where p.kind = 'HARBOUR' and public.treasury_balance(p.id) <> 0 loop
    perform pg_temp.purse((v_r #>> '{}')::uuid, 0);
  end loop;
  raise notice 'PASS: RP_FOLD — % donors over every capital, same harbours, same order, same room; can_draw stops at the last ducat', v_n;

  -- ── DARK ──
  perform pg_temp.purse(v_cap, 0);
  perform pg_temp.room(v_d1, v_cost * 4);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.tick_navy(v_t);
  if v_r <> jsonb_build_object('plan', null, 'steps', '{}'::jsonb, 'added', null, 'paid', 0) or pg_temp.flows_from(v_mark) <> 0 or exists (select 1 from public.navy_ships) then
    raise exception 'PROOF 42 FAIL: off, the job moved something: %', v_r;
  end if;
  raise notice 'PASS: RP_DARK — a poor capital, a rich realm, the switch off: nothing';

  -- ── LIT ──
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  perform public.navy_read(v_t);
  perform public.navy_stations_build(v_nat, v_t);
  update public.navy_realms r set stations_at = v_t + interval '1 day' where r.nation_id <> v_nat;
  update public.navy_realms r set ships = 3, read_at = v_t where r.nation_id = v_nat;
  v_st2 := public.navy_station_of(v_nat, 2);
  if v_st2 = v_cap then
    raise exception 'PROOF 42 FAIL: this proof needs a second station that is not the capital';
  end if;

  -- ── A REALM 1 D. SHORT ──
  perform pg_temp.realm_bare(v_cap);
  perform pg_temp.purse(v_cap, 1000, 7777);   -- 6,777 under its reserve: the realm must make that up too
  v_gap := v_cost + 6777;
  perform pg_temp.room(v_d1, v_gap - 1);
  perform pg_temp.purse(v_far, 9000000000);   -- the richest of all is abroad
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_sum := pg_temp.purses();
  v_led := (select count(*) from public.ledger);
  v_ev := (select count(*) from public.events);
  for v_n in 1 .. 3 loop
    v_r := public.tick_navy(v_t + make_interval(mins => v_n), v_nat);
    if v_r -> 'added' <> 'null'::jsonb or v_r -> 'steps' ? 'ERROR' or exists (select 1 from public.navy_ships) or pg_temp.flows_from(v_mark) <> 0 then
      raise exception 'PROOF 42 FAIL: a realm 1 d. short moved something on run %: % %', v_n, v_r, pg_temp.moved(v_mark, 'CROWN_CALL');
    end if;
  end loop;
  if pg_temp.purses() <> v_sum or (select count(*) from public.ledger) <> v_led or (select count(*) from public.events) <> v_ev then
    raise exception 'PROOF 42 FAIL: a realm that waited changed the world';
  end if;
  if public.capital_can_draw(v_cap, v_cost) or not public.capital_can_draw(v_cap, v_cost - 1) then
    raise exception 'PROOF 42 FAIL: can_draw does not stop at the last ducat, the reserve counted';
  end if;
  raise notice 'PASS: RP_SHORT — short by 1 d., three runs: no hull, no flow, no gold walked to the capital';

  -- ── A BUSY RICHEST CITY ──
  perform pg_temp.room(v_d1, v_cost * 2);
  perform pg_temp.room(v_d2, v_cost / 2);     -- on paper the two can pay; without the richest the second cannot
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  begin
    execute format('create or replace function public.treasury_try_lock(p_port uuid) returns boolean language sql as %L', format('select p_port <> %L::uuid', v_d1));
    if not public.capital_can_draw(v_cap, v_cost) then
      raise exception 'PROOF 42 FAIL: the busy scene needs a realm that can pay on paper';
    end if;
    v_r := public.tick_navy(v_t, v_nat);
    raise exception using errcode = 'ZX342', message = jsonb_build_object('r', v_r, 'calls', pg_temp.moved(v_mark, 'CROWN_CALL'), 'n', pg_temp.flows_from(v_mark), 'ships', (select count(*) from public.navy_ships))::text;
  exception when sqlstate 'ZX342' then
    v_r := sqlerrm::jsonb;
  end;
  if v_r #> '{r,added}' <> 'null'::jsonb or v_r #> '{r,steps}' ? 'ERROR' or (v_r ->> 'n')::int <> 0 or (v_r ->> 'ships')::int <> 0 then
    raise exception 'PROOF 42 FAIL: a busy donor: the short call stayed: %', v_r;
  end if;
  begin
    execute 'create or replace function public.treasury_try_lock(p_port uuid) returns boolean language sql as $b$ select false $b$';
    v_r := public.tick_navy(v_t, v_nat);
    raise exception using errcode = 'ZX342', message = jsonb_build_object('r', v_r, 'n', pg_temp.flows_from(v_mark))::text;
  exception when sqlstate 'ZX342' then
    v_r := sqlerrm::jsonb;
  end;
  if v_r #> '{r,added}' <> 'null'::jsonb or (v_r ->> 'n')::int <> 0 then
    raise exception 'PROOF 42 FAIL: a busy capital was taken: %', v_r;
  end if;
  raise notice 'PASS: RP_BUSY — the richest busy, the realm short: the other city''s call rolled back, nothing moved, no error; a busy capital passed over';

  -- ── THE RICHEST PAYS ──
  perform pg_temp.purse(v_cap, 1000, 7777);
  perform pg_temp.room(v_d1, v_cost * 2);
  perform pg_temp.room(v_d2, v_cost / 2);
  update public.navy_realms r set paid_at = v_t where r.nation_id = v_nat;   -- this hour is paid: the build is what is read here, RP_PAY reads the pay
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_sum := pg_temp.purses();
  v_led := (select count(*) from public.ledger);
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' <> 'BUILT' or (select count(*) from public.navy_ships) <> 1 then
    raise exception 'PROOF 42 FAIL: a rich realm built nothing: %', v_r;
  end if;
  if pg_temp.moved(v_mark, 'CROWN_CALL') <> jsonb_build_object(v_c, v_gap, v_c1, -v_gap) then
    raise exception 'PROOF 42 FAIL: the call was not the need, from the richest: % wanted %', pg_temp.moved(v_mark, 'CROWN_CALL'), jsonb_build_object(v_c, v_gap, v_c1, -v_gap);
  end if;
  if pg_temp.moved(v_mark, 'BUILD_NAVY') <> jsonb_build_object(v_c, -v_cost, (select p.code from public.ports p where p.id = v_yard), v_cost) then
    raise exception 'PROOF 42 FAIL: the capital did not pay the yard one hull: %', pg_temp.moved(v_mark, 'BUILD_NAVY');
  end if;
  if pg_temp.flows_from(v_mark) <> 4 or pg_temp.purses() <> v_sum or (select count(*) from public.ledger) <> v_led then
    raise exception 'PROOF 42 FAIL: more than four rows, or gold made, or a ledger row: % rows, sum moved %', pg_temp.flows_from(v_mark), pg_temp.purses() - v_sum;
  end if;
  if public.city_surplus(v_cap) <> 0 or public.treasury_balance(v_far) <> 9000000000 or (select count(*) from public.navy_ships where player_id in (select id from public.players where ducats <> 0)) <> 0 then
    raise exception 'PROOF 42 FAIL: the capital is not left at its reserve, or a foreign city paid, or her house has a purse: %', public.city_surplus(v_cap);
  end if;
  v_fl1 := (select n.fleet_id from public.navy_ships n where n.nation_id = v_nat and n.ord = 1);
  v_r := public.tick_navy(v_t + interval '23 hours', v_nat);
  if v_r -> 'added' <> 'null'::jsonb then
    raise exception 'PROOF 42 FAIL: two hulls in a day on the realm''s money: %', v_r;
  end if;
  raise notice 'PASS: RP_BUILD — % d. from the richest city to the capital, % d. capital to the yard, four rows, nothing minted, capital at its reserve', v_gap, v_cost;

  -- ── THE NEXT CITY GIVES THE REST ──
  perform pg_temp.realm_bare(v_cap);
  perform pg_temp.purse(v_cap, 0);
  perform pg_temp.room(v_d1, 300000);
  perform pg_temp.room(v_d2, 900000);
  if v_cost - 900000 > 300000 or v_cost <= 900000 then
    raise exception 'PROOF 42 FAIL: the scene wants a class between the two rooms, and it costs %', v_cost;
  end if;
  v_t := v_t + interval '1 day';
  update public.navy_realms r set paid_at = v_t where r.nation_id = v_nat;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_sum := pg_temp.purses();
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' <> 'BUILT' or pg_temp.moved(v_mark, 'CROWN_CALL') <> jsonb_build_object(v_c, v_cost, v_c2, -900000, v_c1, -(v_cost - 900000)) or pg_temp.purses() <> v_sum then
    raise exception 'PROOF 42 FAIL: the richest did not give its room and the next the rest: % %', v_r, pg_temp.moved(v_mark, 'CROWN_CALL');
  end if;
  v_fl2 := (select n.fleet_id from public.navy_ships n where n.nation_id = v_nat and n.ord = 2);
  raise notice 'PASS: RP_TWO — 900,000 d. from % and the rest from %, each once', v_c2, v_c1;

  -- ── A CAPITAL THAT CAN PAY ──
  perform pg_temp.realm_bare(v_cap);
  perform pg_temp.purse(v_cap, v_cost);
  perform pg_temp.room(v_d1, v_cost * 2);
  v_t := v_t + interval '1 day';
  update public.navy_realms r set paid_at = v_t where r.nation_id = v_nat;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' <> 'BUILT' or pg_temp.moved(v_mark, 'CROWN_CALL') <> '{}'::jsonb or public.city_surplus(v_cap) <> 0 then
    raise exception 'PROOF 42 FAIL: a capital that could pay called: % %', v_r, pg_temp.moved(v_mark, 'CROWN_CALL');
  end if;
  v_fl3 := (select n.fleet_id from public.navy_ships n where n.nation_id = v_nat and n.ord = 3);
  raise notice 'PASS: RP_RICH — a capital with the whole cost called nothing';

  -- ── THE FLOORS ──
  perform pg_temp.realm_bare(v_cap);
  perform pg_temp.purse(v_cap, 0);
  perform pg_temp.purse(v_d1, 1990000, 90000);   -- 1,900,000 above its target: a share of 190,000, but only 100,000 above 20 reserves of cover
  if public.crown_call_room(v_d1) <> 100000 then
    raise exception 'PROOF 42 FAIL: the floor scene wants a room of 100,000 and reads %', public.crown_call_room(v_d1);
  end if;
  perform public.treasury_try_lock(v_cap);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_a := case when public.capital_draw(v_cap, 5000000) then 1 else 0 end;
  if v_a <> 0 or pg_temp.moved(v_mark, 'CROWN_CALL') <> jsonb_build_object(v_c, 100000, v_c1, -100000)
     or public.treasury_balance(v_d1) < public.city_aid_target(v_d1) or public.treasury_balance(v_d1) < (select t.reserve from public.port_treasury t where t.port_id = v_d1) then
    raise exception 'PROOF 42 FAIL: a donor gave past its limit: %', pg_temp.moved(v_mark, 'CROWN_CALL');
  end if;
  raise notice 'PASS: RP_NO_FLOOR — asked for 5,000,000 d., the donor gave its 100,000 and stopped at its cover';

  -- ── AN HOUR, ON THE REALM ──
  perform pg_temp.realm_bare(v_cap);
  perform pg_temp.purse(v_cap, 0);
  perform pg_temp.room(v_d1, v_cost);
  update public.navy_realms r set paid_at = null where r.nation_id = v_nat;
  v_away := (select count(*) from public.navy_ships n join public.fleets f on f.id = n.fleet_id where n.nation_id = v_nat and f.port_id <> v_cap);
  if v_away = 0 or v_away = 3 then
    raise exception 'PROOF 42 FAIL: the hour wants a ship at the capital and one away, and % are away', v_away;
  end if;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_sum := pg_temp.purses();
  v_a := public.navy_pay(v_t, v_nat);
  if v_a <> v_away * v_slice or pg_temp.moved(v_mark, 'CROWN_CALL') <> jsonb_build_object(v_c, 3 * v_slice, v_c1, -3 * v_slice) or pg_temp.purses() <> v_sum then
    raise exception 'PROOF 42 FAIL: the hour: paid %, called %', v_a, pg_temp.moved(v_mark, 'CROWN_CALL');
  end if;
  if exists (select 1 from public.navy_ships n where n.nation_id = v_nat and n.unpaid_since is not null) or public.city_surplus(v_cap) <> (3 - v_away) * v_slice then
    raise exception 'PROOF 42 FAIL: paid on the realm, a ship stayed unpaid, or the ship at the capital''s slice did not stay: %', public.city_surplus(v_cap);
  end if;
  for v_n in 1 .. 3 loop
    v_mark := coalesce((select max(id) from public.treasury_flows), 0);
    v_a := public.navy_pay(v_t + make_interval(hours => v_n), v_nat);
    if v_a <> v_away * v_slice or pg_temp.moved(v_mark, 'CROWN_CALL') <> jsonb_build_object(v_c, v_away * v_slice, v_c1, -v_away * v_slice) or public.city_surplus(v_cap) <> (3 - v_away) * v_slice then
      raise exception 'PROOF 42 FAIL: hour %: the call climbs: %, surplus %', v_n, pg_temp.moved(v_mark, 'CROWN_CALL'), public.city_surplus(v_cap);
    end if;
  end loop;
  v_t := v_t + interval '3 hours';
  raise notice 'PASS: RP_PAY — three ships, % d. called the first hour, % d. each hour after, the capital steady at % d.', 3 * v_slice, v_away * v_slice, (3 - v_away) * v_slice;

  -- ── A REALM THAT CAN PAY ONE ──
  perform pg_temp.realm_bare(v_cap);
  perform pg_temp.purse(v_cap, 0);
  perform pg_temp.room(v_d1, v_slice + v_slice / 2);
  v_t := v_t + interval '1 hour';
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.tick_navy(v_t, v_nat);
  if v_r -> 'steps' ? 'ERROR' or (select n.unpaid_since from public.navy_ships n where n.fleet_id = v_fl1) is not null
     or (select n.unpaid_since from public.navy_ships n where n.fleet_id = v_fl2) is distinct from v_t or (select n.unpaid_since from public.navy_ships n where n.fleet_id = v_fl3) is distinct from v_t then
    raise exception 'PROOF 42 FAIL: one slice of realm did not pay the lowest ord alone: %', v_r;
  end if;
  if pg_temp.moved(v_mark, 'CROWN_CALL') <> jsonb_build_object(v_c, v_slice + v_slice / 2, v_c1, -(v_slice + v_slice / 2)) then
    raise exception 'PROOF 42 FAIL: what the realm had was not taken: %', pg_temp.moved(v_mark, 'CROWN_CALL');
  end if;
  v_step := public.navy_ship_step(v_fl3, v_t);
  if v_step <> 'LAID_UP' or (select n.laid_up_at from public.navy_ships n where n.fleet_id = v_fl3) is null then
    raise exception 'PROOF 42 FAIL: unpaid at her station, she is not laid up: %', v_step;
  end if;
  raise notice 'PASS: RP_PAY_PART — the realm had one and a half slices: the lowest ord paid, the others unpaid, no error, no debt';

  -- ── A WAKE ──
  perform pg_temp.realm_bare(v_cap);
  perform pg_temp.purse(v_cap, 0);
  v_t := v_t + interval '1 day';
  update public.navy_realms r set added_at = v_t - interval '1 day', paid_at = v_t where r.nation_id = v_nat;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.tick_navy(v_t, v_nat);
  if v_r -> 'added' <> 'null'::jsonb or (select n.laid_up_at from public.navy_ships n where n.fleet_id = v_fl3) is null or pg_temp.flows_from(v_mark) <> 0 then
    raise exception 'PROOF 42 FAIL: a realm with nothing woke a ship: %', v_r;
  end if;
  perform pg_temp.room(v_d1, v_slice * 10);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' <> 'WOKEN' or pg_temp.flows_from(v_mark) <> 0 or (select n.laid_up_at from public.navy_ships n where n.fleet_id = v_fl3) is not null
     or (select count(*) from public.navy_ships n where n.nation_id = v_nat) <> 3 then
    raise exception 'PROOF 42 FAIL: a realm that can pay did not wake her, or the wake moved gold: % % rows', v_r, pg_temp.flows_from(v_mark);
  end if;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_a := public.navy_pay(v_t + interval '1 hour', v_nat);
  if v_a <= 0 or (select n.unpaid_since from public.navy_ships n where n.fleet_id = v_fl3) is not null or pg_temp.moved(v_mark, 'CROWN_CALL') -> v_c1 is null then
    raise exception 'PROOF 42 FAIL: the next hour did not pay her from the realm: % %', v_a, pg_temp.moved(v_mark, 'CROWN_CALL');
  end if;
  v_t := v_t + interval '1 hour';
  raise notice 'PASS: RP_WAKE — no realm money no wake; with it she wakes the same fleet, no gold moved, and the next hour pays her';

  -- ── 0307's ROLLBACK ──
  update public.world_config set value = to_jsonb(0) where key = 'crown_call_share';
  perform pg_temp.purse(v_cap, 0);
  update public.navy_realms r set ships = 4, added_at = null, paid_at = v_t where r.nation_id = v_nat;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.tick_navy(v_t, v_nat);
  if v_r -> 'added' <> 'null'::jsonb or pg_temp.flows_from(v_mark) <> 0 then
    raise exception 'PROOF 42 FAIL: share 0, the realm still paid: %', v_r;
  end if;
  update public.world_config set value = to_jsonb(0.10) where key = 'crown_call_share';
  raise notice 'PASS: RP_SHARE0 — crown_call_share 0: the capital alone, and it waits';

  -- ── THE ECONOMY OPEN, AS CI'S OWN WORLD ──
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  perform pg_temp.realm_bare(v_cap);
  perform pg_temp.purse(v_cap, 0);
  perform pg_temp.room(v_d1, v_cost * 2);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_sum := pg_temp.purses();
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' <> 'BUILT' or pg_temp.purses() <> v_sum or pg_temp.moved(v_mark, 'CROWN_CALL') <> jsonb_build_object(v_c, v_cost, v_c1, -v_cost) or pg_temp.flows_from(v_mark) <> 4 then
    raise exception 'PROOF 42 FAIL: open, the money moved differently: % %', v_r, pg_temp.moved(v_mark, 'CROWN_CALL');
  end if;
  raise notice 'PASS: RP_OPEN — open, the same four rows and the same sum';
end
$$;
