-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 36 — THE CARGO SHIP IS ARMED  (migration 0328, owner row 283, W8 of docs/WORLD_POWERS.md)
--
--   0328's self-assert reads the catalog only (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof starts where prod is, crewless ships lit at their capitals, lights
--   convoy_armed_enabled and runs the REAL public.city_day, cargo step, voyage engine and fight. The lap is sailed on the REAL sea, as proof 19's; elsewhere the sea is stubbed on one setting.
--   The economy is CLOSED here, as on prod. No count of ships is assumed: the proof takes what the job makes of one realm, so it reads the same before and after 0326 retires convoy_ships_per_nation.
--
-- @pass ARMED_DARK       off: the class is the old one, an idle ship keeps her hull, her upkeep is 0 with no flow, and no hull has guns
-- @pass ARMED_LOADED     lit: a ship with funds aboard sails her lap in her old hull, crewless, with no upkeep, and takes the new hull only when the lap has closed
-- @pass ARMED_HULL       lit: an idle ship at home is refitted free, once: same fleet, house, number and name, the armed class, no purse moved, no ledger, flow or event row
-- @pass ARMED_LAID_UP    a laid-up ship is not refitted by the real job, in the run that refits the ship beside her; woken, she is
-- @pass ARMED_LAP        one real lap on the real sea: every stop in order, hands and stores at every departure, the funds delivered, the sum unmoved, no fold drift
-- @pass ARMED_NO_DEBT    the lap leaves no dock fee, no wage, no ledger row, no forced home, purse 0, hull whole at home
-- @pass ARMED_UPKEEP     her origin paid the knob for each leg but the one she left it by, two rows each, to the harbour she left, netting 0
-- @pass ARMED_WAGE       a cargo ship with hands owes no wage; a company with hands owes what it always did
-- @pass ARMED_QUAY       hands come from the quay above its floor; a quay at its floor gives none, takes no hands and holds nobody; she never sails over her complement
-- @pass ARMED_PURSE      a broke origin pays nothing and a poor one what its surplus covers, a reserve is respected, a busy donor is passed over, and she has her stores in each case
-- @pass ARMED_REBASE     a rebase leg passes the upkeep too
-- @pass ARMED_FIGHT      voyage.fight takes her hulls at four strengths; printed against the old hull; a real PIRATES day settles with no wage and no raise, and her lost hands are back as she leaves
-- @pass ARMED_WRECK      a wrecked armed ship costs her city the refit of her own class, and keeps her class
-- @pass ARMED_SWITCH_OFF off with a ship at sea: she is still looked after, comes home, goes back to the old class, hands on the quay, nothing moved
-- @pass ARMED_NEW        a ship made lit is laid as the armed class
-- @pass ARMED_STORES     convoy_store_days covers the longest leg of every circuit of the world, hull at its floor, at endurance_margin
-- @pass ARMED_NEEDS_SHIPS convoys off: the knob alone lights nothing
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_last  int := world.game_day() - 1;
  v_k     int;
  v_nat   uuid;
  v_cap   uuid;
  v_cir   bigint;
  v_legs  int;
  v_s1    uuid;
  v_s2    uuid;
  v_far   uuid;
  v_fl    uuid[];
  v_pl    uuid[];
  v_hum   uuid;
  v_hfl   uuid;
  v_id    uuid;
  v_id2   uuid;
  v_voy   uuid;
  v_end   timestamptz;
  v_now   timestamptz;
  v_step  text;
  v_seq   text[] := '{}';
  v_left  text[] := '{}';
  v_want  text[];
  v_kinds jsonb := '{}'::jsonb;
  v_guard int := 0;
  v_dep   int := 0;
  v_mark  bigint;
  v_sum   bigint;
  v_tot0  bigint;
  v_load  bigint;
  v_up    bigint := public.wc_int('convoy_upkeep_per_leg');
  v_days  numeric := public.wc_num('convoy_store_days');
  v_floor int := public.wc_int('npc_crew_pool_floor');
  v_need  int;
  v_pool  int;
  v_a     numeric;
  v_b     numeric;
  v_sp0   numeric;
  v_sp1   numeric;
  v_old   jsonb;
  v_new   jsonb;
  v_r     jsonb;
  v_x     jsonb;
  v_seg   jsonb;
  v_n     int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('npc_refits_enabled', 'convoy_rich_enabled', 'convoy_armed_enabled');
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set earned_day = v_last, ducats = 50000, reserve = 0;   -- only the aid runs; everyone exactly at target

  -- THE SEA ON ONE SETTING: empty, every day is quiet. REAL, the real roll. A kind, every day is that day.
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_36;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
declare
  v_s text := coalesce(current_setting('byeharu.proof_sea', true), '');
begin
  if v_s = 'REAL' then
    return query select * from voyage.hazard_roll_real_36(p_voyage, p_day);
    return;
  end if;
  return query select v_s <> '', nullif(v_s, ''), 0.5::numeric, 1::numeric;
end
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
  execute $f$
create function pg_temp.class_of(p_fleet uuid)
returns text
language sql
as $b$ select string_agg(k.code, ',' order by k.code) from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = p_fleet $b$
  $f$;
  execute $f$
create function pg_temp.crew_of(p_fleet uuid)
returns int
language sql
as $b$ select sum(s.crew)::int from public.ships s where s.fleet_id = p_fleet $b$
  $f$;
  execute $f$
create function pg_temp.hull_of(p_fleet uuid)
returns uuid
language sql
as $b$ select s.id from public.ships s where s.fleet_id = p_fleet and s.is_flagship $b$
  $f$;
  execute $f$
create function pg_temp.upkeep_rows(p_mark bigint)
returns bigint
language sql
as $b$ select count(*) from public.treasury_flows f where f.id > p_mark and f.kind = 'CONVOY_UPKEEP' $b$
  $f$;
  execute $f$
create function pg_temp.reach_port(p_fleet uuid)
returns timestamptz
language plpgsql
as $b$
declare
  v_v uuid;
  v_e timestamptz;
begin
  select o.id, o.eta into v_v, v_e from public.voyages o where o.fleet_id = p_fleet and o.status = 'SAILING';
  loop
    perform voyage.settle(p_fleet, v_e);
    exit when (select f.status from public.fleets f where f.id = p_fleet) <> 'SAILING';
    v_e := (select o.eta from public.voyages o where o.id = v_v);
  end loop;
  return v_e;
end
$b$
  $f$;
  -- four strengths, 80 fights each: read, nothing written (voyage.fight is STABLE). Held: she saw them off.
  execute $f$
create function pg_temp.fights(p_voy uuid, p_fl uuid)
returns jsonb
language plpgsql
as $b$
declare
  v_out  jsonb := '{}'::jsonb;
  v_s    numeric;
  v_d    int;
  v_r    jsonb;
  v_held int;
  v_lost numeric;
  v_of   numeric := (select sum(b.durability) from public.ships s cross join lateral public.ship_base(s.id) b where s.fleet_id = p_fl);
begin
  foreach v_s in array array[10, 27, 40, 100]::numeric[] loop
    v_held := 0;
    v_lost := 0;
    for v_d in 1 .. 80 loop
      v_r := voyage.fight(p_voy, v_d, p_fl, v_s);
      if v_r is null or v_r ->> 'outcome' is null then
        raise exception 'PROOF 36 FAIL: no fight at raider %: %', v_s, v_r;
      end if;
      if exists (select 1 from jsonb_object_keys(v_r -> 'hull_lost') k where k::uuid not in (select s.id from public.ships s where s.fleet_id = p_fl)) then
        raise exception 'PROOF 36 FAIL: the fight names a hull that is not hers: %', v_r -> 'hull_lost';
      end if;
      if v_r ->> 'outcome' in ('EVADED', 'DRIVEN_OFF') then
        v_held := v_held + 1;
      end if;
      v_lost := v_lost + (select coalesce(sum(h.value::numeric), 0) from jsonb_each_text(v_r -> 'hull_lost') h);
    end loop;
    v_out := v_out || jsonb_build_object(v_s::text, jsonb_build_object('held', v_held, 'hull_lost_pct', round(v_lost / 80 / v_of * 100, 1)));
  end loop;
  return v_out;
end
$b$
  $f$;

  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = 'PRT';
  update public.port_treasury t set ducats = 10000000 where t.port_id = v_cap;
  update public.ports p set crew_pool = 500 where public.city_capital(p.id) = v_cap;
  for v_n in 1 .. 12 loop
    perform public.tick_cargo_ships(now(), v_nat);
    v_k := (select count(*) from public.cargo_ships c where c.nation_id = v_nat);
    exit when v_k >= 6;
  end loop;
  if v_k < 6 then
    raise exception 'PROOF 36 FAIL: the realm has % ships, and this proof needs 6', v_k;
  end if;
  v_fl := array(select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat order by c.ord);
  v_pl := array(select c.player_id from public.cargo_ships c where c.nation_id = v_nat order by c.ord);
  v_cir := public.cargo_circuit_of(v_nat, v_cap);
  v_legs := (select count(*) from public.cargo_circuit_legs l where l.circuit_id = v_cir);
  if v_legs < 3 then
    raise exception 'PROOF 36 FAIL: Portugal''s circuit has % legs', v_legs;
  end if;
  v_s1 := (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = v_cir and l.ord = 1);
  v_s2 := (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = v_cir and l.ord = v_legs - 1);
  select l.segments, l.to_port into v_seg, v_far from public.cargo_circuit_legs l where l.circuit_id = v_cir order by l.nm desc limit 1;   -- the longest leg: more than a day at sea

  -- ── OFF ──
  if public.cargo_armed_on() or public.cargo_class() <> public.wc_text('convoy_ship_class')
     or exists (select 1 from public.cargo_ships c where public.cargo_armed(c.fleet_id)) then
    raise exception 'PROOF 36 FAIL: off, something is armed';
  end if;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_id := pg_temp.hull_of(v_fl[1]);
  v_step := public.cargo_ship_step(v_fl[1], now());
  if v_step <> 'IDLE' or pg_temp.hull_of(v_fl[1]) <> v_id or public.cargo_upkeep(v_fl[1], v_s1) <> 0 or pg_temp.upkeep_rows(v_mark) <> 0 then
    raise exception 'PROOF 36 FAIL: off, an idle ship moved: %', v_step;
  end if;
  v_old := null;
  v_voy := voyage.depart(v_fl[v_k], v_seg, null, v_far, now());   -- the old hull, for the table
  v_sp0 := voyage.fleet_speed(v_fl[v_k]);
  v_old := pg_temp.fights(v_voy, v_fl[v_k]);
  raise notice 'PASS: ARMED_DARK — class %, hull kept, upkeep 0, % kn crewless', public.cargo_class(), v_sp0;

  -- ── LIT, A SHIP WITH FUNDS ABOARD KEEPS HER HULL UNTIL HER LAP CLOSES ──
  update public.world_config set value = 'true'::jsonb where key = 'convoy_armed_enabled';
  if public.cargo_class() <> public.wc_text('convoy_armed_class') then
    raise exception 'PROOF 36 FAIL: lit, the class is %', public.cargo_class();
  end if;
  perform public.convoy_book('LOADED', v_fl[2], v_pl[2], v_cap, 1000);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_step := public.cargo_ship_step(v_fl[2], now());
  if v_step <> 'SAILED' or pg_temp.class_of(v_fl[2]) <> public.wc_text('convoy_ship_class') or pg_temp.crew_of(v_fl[2]) <> 0 or pg_temp.upkeep_rows(v_mark) <> 0 then
    raise exception 'PROOF 36 FAIL: lit, a loaded ship was touched at the quay: % % %', v_step, pg_temp.class_of(v_fl[2]), pg_temp.crew_of(v_fl[2]);
  end if;
  update public.cargo_ships c set leg = v_legs - 1 where c.fleet_id = v_fl[2];   -- her lap, short
  v_end := pg_temp.reach_port(v_fl[2]);
  v_step := public.cargo_ship_step(v_fl[2], v_end + interval '61 seconds');
  if v_step <> 'SAILED' or pg_temp.class_of(v_fl[2]) <> public.wc_text('convoy_ship_class') then
    raise exception 'PROOF 36 FAIL: she changed hull on her lap: % %', v_step, pg_temp.class_of(v_fl[2]);
  end if;
  v_end := pg_temp.reach_port(v_fl[2]);
  v_step := public.cargo_ship_step(v_fl[2], v_end);
  if v_step <> 'HOME' or pg_temp.class_of(v_fl[2]) <> public.wc_text('convoy_ship_class') then
    raise exception 'PROOF 36 FAIL: she took a hull as her lap closed, with funds on the book: % %', v_step, pg_temp.class_of(v_fl[2]);
  end if;
  perform public.cargo_ship_step(v_fl[2], v_end + interval '61 seconds');
  if pg_temp.class_of(v_fl[2]) <> public.wc_text('convoy_armed_class') then
    raise exception 'PROOF 36 FAIL: her lap closed and she was not refitted: %', pg_temp.class_of(v_fl[2]);
  end if;
  raise notice 'PASS: ARMED_LOADED — sailed in her old hull, no upkeep, refitted when idle';

  -- ── LIT, THE REFIT ──
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_sum := pg_temp.purses();
  v_id := pg_temp.hull_of(v_fl[1]);
  v_x := (select jsonb_build_object('name', s.name, 'ord', c.ord, 'player', c.player_id, 'home', c.home_port_id)
            from public.cargo_ships c join public.ships s on s.fleet_id = c.fleet_id where c.fleet_id = v_fl[1]);
  v_step := public.cargo_ship_step(v_fl[1], now());
  v_id2 := pg_temp.hull_of(v_fl[1]);
  if v_step <> 'IDLE' or v_id2 = v_id or exists (select 1 from public.ships s where s.id = v_id)
     or (select count(*) from public.ships s where s.fleet_id = v_fl[1]) <> 1
     or pg_temp.class_of(v_fl[1]) <> public.wc_text('convoy_armed_class') then
    raise exception 'PROOF 36 FAIL: an idle ship was not refitted once: % %', v_step, pg_temp.class_of(v_fl[1]);
  end if;
  if v_x <> (select jsonb_build_object('name', s.name, 'ord', c.ord, 'player', c.player_id, 'home', c.home_port_id)
               from public.cargo_ships c join public.ships s on s.fleet_id = c.fleet_id where c.fleet_id = v_fl[1])
     or (select f.player_id from public.fleets f where f.id = v_fl[1]) <> v_pl[1] then
    raise exception 'PROOF 36 FAIL: the refit changed who she is';
  end if;
  if pg_temp.purses() <> v_sum or exists (select 1 from public.treasury_flows f where f.id > v_mark)
     or exists (select 1 from public.ledger l where l.player_id = v_pl[1]) or exists (select 1 from public.events e where e.player_id = v_pl[1])
     or (select p.ducats from public.players p where p.id = v_pl[1]) <> 0 then
    raise exception 'PROOF 36 FAIL: the refit moved something';
  end if;
  perform public.cargo_ship_step(v_fl[1], now());
  if pg_temp.hull_of(v_fl[1]) <> v_id2 then
    raise exception 'PROOF 36 FAIL: she was refitted twice';
  end if;
  raise notice 'PASS: ARMED_HULL — % at home, same fleet and house, nothing moved, once', pg_temp.class_of(v_fl[1]);

  -- ── LAID UP (0326). Every idle ship takes her step this run, so only the roster can spare her. Ship 3 is the control: the same run must refit her ──
  update public.world_config set value = to_jsonb(1) where key = 'convoy_idle_every';
  v_n := public.convoy_ships_of(v_nat);
  update public.cargo_fleet_sizes z set ships = 4, read_at = now() where z.nation_id = v_nat;   -- her ord is above her country's number, or the job wakes her
  update public.cargo_ships c set laid_up_at = now() where c.fleet_id = v_fl[5];
  v_id := pg_temp.hull_of(v_fl[5]);
  perform public.tick_cargo_ships(now(), v_nat);
  if pg_temp.class_of(v_fl[3]) <> public.wc_text('convoy_armed_class') then
    raise exception 'PROOF 36 FAIL: the control: the job did not refit an idle ship: %', pg_temp.class_of(v_fl[3]);
  end if;
  if pg_temp.hull_of(v_fl[5]) <> v_id or pg_temp.class_of(v_fl[5]) <> public.wc_text('convoy_ship_class') or public.cargo_armed(v_fl[5]) or pg_temp.crew_of(v_fl[5]) <> 0
     or (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl[5]) is null then
    raise exception 'PROOF 36 FAIL: a laid-up ship was refitted: %', pg_temp.class_of(v_fl[5]);
  end if;
  update public.cargo_fleet_sizes z set ships = v_n, read_at = now() where z.nation_id = v_nat;
  perform public.cargo_ships_commission(v_nat);   -- the real wake
  if (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl[5]) is not null then
    raise exception 'PROOF 36 FAIL: she was not woken';
  end if;
  perform public.tick_cargo_ships(now(), v_nat);
  if pg_temp.class_of(v_fl[5]) <> public.wc_text('convoy_armed_class') or pg_temp.crew_of(v_fl[5]) <> 0 then
    raise exception 'PROOF 36 FAIL: woken, she was not refitted: %', pg_temp.class_of(v_fl[5]);
  end if;
  raise notice 'PASS: ARMED_LAID_UP — left in her old hull by the run that refitted ship 3; woken, refitted';

  -- ── ONE REAL LAP ON THE REAL SEA. Two cities short: the first stop and the last ──
  update public.port_treasury t set ducats = 1000 where t.port_id in (v_s1, v_s2);
  perform public.stats_live_fold(now());
  v_tot0 := (world.stats_now() ->> 'total')::bigint;
  v_sum := pg_temp.purses();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  perform public.city_day();
  v_load := (select a.aboard from public.cargo_ship_aboard(v_fl[1]) a);
  if coalesce(v_load, 0) <= 0 then
    raise exception 'PROOF 36 FAIL: the armed ship did not load: %', (select jsonb_agg(c.ord) from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.nation_id = v_nat);
  end if;
  v_want := array(select p.code from public.cargo_circuit_legs l join public.ports p on p.id = l.to_port where l.circuit_id = v_cir order by l.ord);
  v_need := (select k.crew_required from public.ship_classes k where k.code = public.wc_text('convoy_armed_class'));
  v_now := now();
  perform set_config('byeharu.proof_sea', 'REAL', true);
  loop
    v_guard := v_guard + 1;
    exit when v_guard > 800;
    v_left := v_left || (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fl[1]);
    v_step := public.cargo_ship_step(v_fl[1], v_now);
    exit when v_step = 'HOME';
    if v_step = 'SAILED' then
      v_dep := v_dep + 1;
      select o.id into v_voy from public.voyages o where o.fleet_id = v_fl[1] and o.status = 'SAILING';
      if pg_temp.crew_of(v_fl[1]) <> v_need or voyage.endurance_days(v_fl[1]) < v_days - 0.01 then
        raise exception 'PROOF 36 FAIL: she left with % hands and % days of stores', pg_temp.crew_of(v_fl[1]), voyage.endurance_days(v_fl[1]);
      end if;
      if v_dep = 1 then
        v_sp1 := (select (o.speed_profile ->> 0)::numeric from public.voyages o where o.id = v_voy);
      end if;
      v_seq := v_seq || (select p.code from public.voyages o join public.ports p on p.id = o.dest_port_id where o.id = v_voy);
      v_now := pg_temp.reach_port(v_fl[1]);
      select v_kinds || coalesce(jsonb_object_agg(x.kind, x.n), '{}'::jsonb) into v_kinds
        from (select e.kind, coalesce((v_kinds ->> e.kind)::int, 0) + count(*) as n from public.voyage_events e where e.voyage_id = v_voy group by 1) x;
    elsif v_step = 'IN_PORT' then
      v_now := v_now + interval '61 seconds';
    else
      raise exception 'PROOF 36 FAIL: step % on the lap, at %', v_step, v_seq;
    end if;
  end loop;
  perform set_config('byeharu.proof_sea', '', true);
  if v_step <> 'HOME' or v_seq <> v_want then
    raise exception 'PROOF 36 FAIL: she did not sail the circuit: % % against %', v_step, v_seq, v_want;
  end if;
  if public.treasury_balance(v_s1) < 50000 or (select coalesce(sum(k.ducats), 0) from public.convoy_cargo k where k.fleet_id = v_fl[1] and k.stage = 'DELIVERED') <= 0
     or exists (select 1 from public.cargo_ship_aboard(v_fl[1])) then
    raise exception 'PROOF 36 FAIL: the stops were not served or her book did not close';
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 36 FAIL: the lap moved the sum of purses and funds aboard by %', pg_temp.purses() - v_sum;
  end if;
  if (world.stats_now() ->> 'total')::bigint <> v_tot0 then
    raise exception 'PROOF 36 FAIL: the live world total moved by %', (world.stats_now() ->> 'total')::bigint - v_tot0;
  end if;
  v_r := public.stats_live_fold(now());
  if (v_r #>> '{drift,cities}')::bigint <> 0 or (v_r #>> '{drift,set_aside}')::bigint <> 0 then
    raise exception 'PROOF 36 FAIL: the fold found a drift: %', v_r;
  end if;
  raise notice 'PASS: ARMED_LAP — % stops, in order, % d. loaded, the sum moved 0, the sea gave %', cardinality(v_seq), v_load, v_kinds;

  if exists (select 1 from public.port_fee_debts d where d.player_id = v_pl[1])
     or exists (select 1 from public.fleet_wages w where w.fleet_id = v_fl[1])
     or exists (select 1 from public.ledger l where l.player_id = v_pl[1])
     or (select p.ducats from public.players p where p.id = v_pl[1]) <> 0
     or (v_kinds ? 'FORCED_HOME')
     or exists (select 1 from public.ships s where s.fleet_id = v_fl[1] and s.durability <> (select b.durability from public.ship_base(s.id) b)) then
    raise exception 'PROOF 36 FAIL: the lap left something owing or broken: %', jsonb_build_object('kinds', v_kinds, 'debts', (select count(*) from public.port_fee_debts d where d.player_id = v_pl[1]),
      'wages', (select count(*) from public.fleet_wages w where w.fleet_id = v_fl[1]), 'ledger', (select count(*) from public.ledger l where l.player_id = v_pl[1]));
  end if;
  raise notice 'PASS: ARMED_NO_DEBT — no fee, wage, ledger row or forced home; purse 0; hull whole at home';

  v_x := (select jsonb_build_object('rows', count(*), 'in', coalesce(sum(f.ducats) filter (where f.ducats > 0), 0), 'net', coalesce(sum(f.ducats), 0),
                                    'from', count(distinct f.port_id) filter (where f.ducats < 0))
            from public.treasury_flows f where f.id > v_mark and f.kind = 'CONVOY_UPKEEP');
  if (v_x ->> 'rows')::int <> 2 * (v_dep - 1) or (v_x ->> 'in')::bigint <> v_up * (v_dep - 1) or (v_x ->> 'net')::bigint <> 0 or (v_x ->> 'from')::int <> 1
     or (select p.code from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > v_mark and f.kind = 'CONVOY_UPKEEP' and f.ducats < 0 limit 1)
        <> (select p.code from public.ports p where p.id = v_cap)
     or array(select p.code from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > v_mark and f.kind = 'CONVOY_UPKEEP' and f.ducats > 0 order by f.id) <> v_want[1 : v_dep - 1] then
    raise exception 'PROOF 36 FAIL: the upkeep is not one moved knob a leg to the harbour she left: % on % departures', v_x, v_dep;
  end if;
  if exists (select 1 from public.treasury_flows f where f.id > v_mark and f.kind = 'CONVOY_UPKEEP' and f.player_id is not null) then
    raise exception 'PROOF 36 FAIL: an upkeep row names a house';
  end if;
  raise notice 'PASS: ARMED_UPKEEP — % departures, % d. moved, net 0, her origin to the harbour she left; a real day at 300 stops an hour is about % d.', v_dep, v_x ->> 'in', 300 * 24 * v_up;

  -- ── THE WAGE ──
  insert into public.players (company_name, nation_id, ducats) values ('Proof 36 house', v_nat, 0) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Proof 36 fleet', v_cap);
  perform public.commission_ship(v_hum, v_hfl, public.wc_text('convoy_armed_class'), 'Proof 36 hull', true, true);
  if public.fleet_wage(v_fl[1], false) <> 0 or pg_temp.crew_of(v_fl[1]) <= 0 or public.fleet_wage(v_hfl, false) <= 0
     or public.fleet_wage(v_hfl, false) <> round(public.crew_wages(pg_temp.crew_of(v_hfl), false) * public.running_cost_mult(v_hum), 4) then
    raise exception 'PROOF 36 FAIL: the wages: % and %', public.fleet_wage(v_fl[1], false), public.fleet_wage(v_hfl, false);
  end if;
  raise notice 'PASS: ARMED_WAGE — her % hands owe 0; a company''s % hands owe %', pg_temp.crew_of(v_fl[1]), pg_temp.crew_of(v_hfl), public.fleet_wage(v_hfl, false);

  -- ── THE QUAY ──
  perform public.cargo_ship_step(v_fl[3], now());
  if pg_temp.class_of(v_fl[3]) <> public.wc_text('convoy_armed_class') or pg_temp.crew_of(v_fl[3]) <> 0 then
    raise exception 'PROOF 36 FAIL: ship 3 is not a fresh armed hull';
  end if;
  update public.ports p set crew_pool = v_floor where p.id = v_cap;
  perform public.cargo_upkeep(v_fl[3], v_cap);
  if pg_temp.crew_of(v_fl[3]) <> 0 or (select p.crew_pool from public.ports p where p.id = v_cap) <> v_floor then
    raise exception 'PROOF 36 FAIL: a quay at its floor gave hands';
  end if;
  update public.ports p set crew_pool = v_floor + 10 where p.id = v_cap;
  perform public.cargo_upkeep(v_fl[3], v_cap);
  v_a := voyage.fleet_speed(v_fl[3]);
  if pg_temp.crew_of(v_fl[3]) <> 10 or (select p.crew_pool from public.ports p where p.id = v_cap) <> v_floor or voyage.endurance_days(v_fl[3]) < v_days - 0.01 then
    raise exception 'PROOF 36 FAIL: the quay gave % hands, down to %', pg_temp.crew_of(v_fl[3]), (select p.crew_pool from public.ports p where p.id = v_cap);
  end if;
  update public.ports p set crew_pool = 500 where p.id = v_cap;
  perform public.cargo_upkeep(v_fl[3], v_cap);
  perform public.cargo_upkeep(v_fl[3], v_cap);
  v_b := voyage.fleet_speed(v_fl[3]);
  if pg_temp.crew_of(v_fl[3]) <> v_need or (select p.crew_pool from public.ports p where p.id = v_cap) <> 500 - (v_need - 10) or v_b <= v_a then
    raise exception 'PROOF 36 FAIL: she has % hands of %, % kn then % kn', pg_temp.crew_of(v_fl[3]), v_need, v_a, v_b;
  end if;
  raise notice 'PASS: ARMED_QUAY — the floor held, 10 hands sailed at % kn, a full complement at % kn, never more', v_a, v_b;

  -- ── THE PURSE: ship 3 lies at a stop of her realm ──
  update public.fleets f set port_id = v_s1 where f.id = v_fl[3];
  update public.ships s set water_t = 0, food_t = 0 where s.fleet_id = v_fl[3];
  perform pg_temp.purse(v_cap, 200);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_load := public.cargo_upkeep(v_fl[3], v_s1);
  if v_load <> 200 or public.treasury_balance(v_cap) <> 0 or pg_temp.upkeep_rows(v_mark) <> 2 then
    raise exception 'PROOF 36 FAIL: a poor origin did not pay what it had: %', public.treasury_balance(v_cap);
  end if;
  update public.ships s set water_t = 0, food_t = 0 where s.fleet_id = v_fl[3];
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_load := public.cargo_upkeep(v_fl[3], v_s1);
  if v_load <> 0 or pg_temp.upkeep_rows(v_mark) <> 0 or voyage.endurance_days(v_fl[3]) < v_days - 0.01 then
    raise exception 'PROOF 36 FAIL: a broke origin paid, or she has no stores';
  end if;
  perform pg_temp.purse(v_cap, 1000000, 1000000);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_load := public.cargo_upkeep(v_fl[3], v_s1);
  if v_load <> 0 or pg_temp.upkeep_rows(v_mark) <> 0 then
    raise exception 'PROOF 36 FAIL: an origin paid out of its reserve';
  end if;
  perform pg_temp.purse(v_cap, 10000000, 0);
  begin
    alter function public.treasury_try_lock(uuid) rename to treasury_try_lock_real_36;
    execute $f$
create function public.treasury_try_lock(p_port uuid)
returns boolean
language sql
as $b$ select false $b$
    $f$;
    v_mark := coalesce((select max(id) from public.treasury_flows), 0);
    update public.ships s set water_t = 0, food_t = 0 where s.fleet_id = v_fl[3];
    v_load := public.cargo_upkeep(v_fl[3], v_s1);
    v_r := jsonb_build_object('pay', v_load, 'rows', pg_temp.upkeep_rows(v_mark), 'days', voyage.endurance_days(v_fl[3]));
    raise exception using errcode = 'ZX336', message = v_r::text;
  exception when sqlstate 'ZX336' then
    v_r := sqlerrm::jsonb;
  end;
  if (v_r ->> 'pay')::bigint <> 0 or (v_r ->> 'rows')::bigint <> 0 or (v_r ->> 'days')::numeric < v_days - 0.01 then
    raise exception 'PROOF 36 FAIL: a busy donor: %', v_r;
  end if;
  update public.fleets f set port_id = v_cap where f.id = v_fl[3];
  raise notice 'PASS: ARMED_PURSE — 200 d. paid by a purse of 200, 0 by a broke one, 0 from a reserve, 0 by a busy donor; she had her stores each time';

  -- ── A REBASE LEG. Off her lap at a stop, she sails home, and that leg passes her upkeep ──
  perform public.cargo_ship_step(v_fl[4], now());
  update public.fleets f set port_id = v_s1, ready_at = null where f.id = v_fl[4];
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_step := public.cargo_ship_step(v_fl[4], now());
  if v_step <> 'SAILED' or pg_temp.crew_of(v_fl[4]) <> v_need or voyage.endurance_days(v_fl[4]) < v_days - 0.01 or pg_temp.upkeep_rows(v_mark) <> 2 then
    raise exception 'PROOF 36 FAIL: a rebase leg passed no upkeep: % % %', v_step, pg_temp.crew_of(v_fl[4]), pg_temp.upkeep_rows(v_mark);
  end if;
  v_end := pg_temp.reach_port(v_fl[4]);
  raise notice 'PASS: ARMED_REBASE — hands, stores and the upkeep on the leg home';

  -- ── THE FIGHT ──
  v_voy := voyage.depart(v_fl[1], v_seg, null, v_far, now());
  v_new := pg_temp.fights(v_voy, v_fl[1]);
  if (select sum((x.value ->> 'held')::int) from jsonb_each(v_new) x) <= (select sum((x.value ->> 'held')::int) from jsonb_each(v_old) x) then
    raise exception 'PROOF 36 FAIL: her guns saw off no more raiders than the old hull: % against %', v_new, v_old;
  end if;
  raise notice 'SIM: raider strength: {held of 80, hull lost %%}. Old hull, crewless: %', v_old;
  raise notice 'SIM: raider strength: {held of 80, hull lost %%}. Armed hull: %', v_new;
  update public.ships s set crew = v_need - 20 where s.fleet_id = v_fl[1];
  perform set_config('byeharu.proof_sea', 'PIRATES', true);
  perform voyage.settle(v_fl[1], voyage.day_ends_at(v_voy, 1));
  perform set_config('byeharu.proof_sea', '', true);
  v_r := (select e.payload from public.voyage_events e where e.voyage_id = v_voy and e.day_index = 1 and e.kind = 'PIRATES');
  if v_r is null or v_r ->> 'outcome' is null or (v_r ->> 'wages')::numeric <> 0 then
    raise exception 'PROOF 36 FAIL: no PIRATES day through voyage.settle: %', v_r;
  end if;
  v_end := pg_temp.reach_port(v_fl[1]);
  update public.fleets f set ready_at = null where f.id = v_fl[1];
  v_step := public.cargo_ship_step(v_fl[1], v_end);
  if v_step <> 'SAILED' or pg_temp.crew_of(v_fl[1]) <> v_need then
    raise exception 'PROOF 36 FAIL: her hands did not come back as she left: % %', v_step, pg_temp.crew_of(v_fl[1]);
  end if;
  v_end := pg_temp.reach_port(v_fl[1]);
  perform public.cargo_ship_step(v_fl[1], v_end);
  raise notice 'PASS: ARMED_FIGHT — four strengths on her hulls, a real % day settled, her hands back as she left', v_r ->> 'outcome';

  -- ── A WRECK. Ship 3, one point of hull, a storm ──
  update public.world_config set value = 'true'::jsonb where key = 'npc_refits_enabled';
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_sum := pg_temp.purses();
  update public.ships s set durability = 1 where s.fleet_id = v_fl[3];
  v_voy := voyage.depart(v_fl[3], v_seg, null, v_far, now());
  perform set_config('byeharu.proof_sea', 'STORM', true);
  perform voyage.settle(v_fl[3], voyage.day_ends_at(v_voy, 1));
  perform set_config('byeharu.proof_sea', '', true);
  if (select f.status from public.fleets f where f.id = v_fl[3]) <> 'UNABLE_TO_SAIL' or (select f.port_id from public.fleets f where f.id = v_fl[3]) <> v_cap then
    raise exception 'PROOF 36 FAIL: she is no wreck at her origin: %', (select f.status from public.fleets f where f.id = v_fl[3]);
  end if;
  v_step := public.npc_refit_step(v_fl[3], now());
  v_a := round(public.wc_num('npc_refit_share') * (select k.build_cost from public.ship_classes k where k.code = public.wc_text('convoy_armed_class')));
  if v_step <> 'PAID' or pg_temp.class_of(v_fl[3]) <> public.wc_text('convoy_armed_class')
     or (select sum(f.ducats) filter (where f.ducats > 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'REFIT') <> v_a
     or pg_temp.purses() <> v_sum
     or exists (select 1 from public.ships s where s.fleet_id = v_fl[3] and s.durability <> (select b.durability from public.ship_base(s.id) b)) then
    raise exception 'PROOF 36 FAIL: her refit: % against %', v_step, v_a;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  raise notice 'PASS: ARMED_WRECK — her city paid % d., she keeps her class, the sum moved 0', v_a;

  -- ── THE SWITCH GOES OFF WITH A SHIP AT SEA ──
  perform public.convoy_book('LOADED', v_fl[4], v_pl[4], v_cap, 1000);
  v_step := public.cargo_ship_step(v_fl[4], v_end + interval '1 day');
  if v_step <> 'SAILED' then
    raise exception 'PROOF 36 FAIL: ship 4 did not sail: %', v_step;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'convoy_armed_enabled';
  update public.cargo_ships c set leg = v_legs - 1 where c.fleet_id = v_fl[4];
  v_end := pg_temp.reach_port(v_fl[4]);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_step := public.cargo_ship_step(v_fl[4], v_end + interval '61 seconds');
  if v_step <> 'SAILED' or pg_temp.upkeep_rows(v_mark) <> 2 or voyage.endurance_days(v_fl[4]) < v_days - 0.01 then
    raise exception 'PROOF 36 FAIL: off, a ship at sea was dropped: % %', v_step, pg_temp.upkeep_rows(v_mark);
  end if;
  v_end := pg_temp.reach_port(v_fl[4]);
  if public.cargo_ship_step(v_fl[4], v_end) <> 'HOME' or pg_temp.class_of(v_fl[4]) <> public.wc_text('convoy_armed_class') then
    raise exception 'PROOF 36 FAIL: off, she did not close her lap armed';
  end if;
  v_sum := pg_temp.purses();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_pool := (select p.crew_pool from public.ports p where p.id = v_cap);
  v_n := pg_temp.crew_of(v_fl[4]);
  perform public.cargo_ship_step(v_fl[4], v_end + interval '61 seconds');
  if pg_temp.class_of(v_fl[4]) <> public.wc_text('convoy_ship_class') or pg_temp.crew_of(v_fl[4]) <> 0 or public.cargo_armed(v_fl[4])
     or (select p.crew_pool from public.ports p where p.id = v_cap) <> v_pool + v_n
     or (select s.water_t + s.food_t from public.ships s where s.fleet_id = v_fl[4]) <> 0
     or pg_temp.purses() <> v_sum or exists (select 1 from public.treasury_flows f where f.id > v_mark) then
    raise exception 'PROOF 36 FAIL: off, she did not go back: % % %', pg_temp.class_of(v_fl[4]), pg_temp.crew_of(v_fl[4]), (select p.crew_pool from public.ports p where p.id = v_cap);
  end if;
  raise notice 'PASS: ARMED_SWITCH_OFF — looked after at sea, home, back to %, % hands on the quay, nothing moved', pg_temp.class_of(v_fl[4]), v_n;

  -- ── A NEW SHIP ──
  update public.world_config set value = 'true'::jsonb where key = 'convoy_armed_enabled';
  v_id := (select n.id from public.nations n where n.code = 'ESP');   -- a realm with no ship yet
  if public.cargo_ships_commission(v_id) < 1 then
    raise exception 'PROOF 36 FAIL: no new ship';
  end if;
  if exists (select 1 from public.cargo_ships c join public.players p on p.id = c.player_id where c.nation_id = v_id
              and (pg_temp.class_of(c.fleet_id) <> public.wc_text('convoy_armed_class') or pg_temp.crew_of(c.fleet_id) <> 0 or p.ducats <> 0)) then
    raise exception 'PROOF 36 FAIL: a new ship is not a crewless armed hull with an empty purse';
  end if;
  raise notice 'PASS: ARMED_NEW — a new ship is laid %', (select pg_temp.class_of(c.fleet_id) from public.cargo_ships c where c.nation_id = v_id limit 1);

  -- ── EVERY LEG OF THE WORLD ──
  update public.world_config set value = 'false'::jsonb where key = 'convoy_armed_enabled';   -- circuits only: no hull changes for this
  for v_id in select g.nation_id from public.great_powers g where public.cargo_circuit_of(g.nation_id, public.realm_capital(g.nation_id)) is null loop
    perform public.cargo_circuit_build(v_id);
  end loop;
  select max(l.nm) into v_a from public.cargo_circuit_legs l;
  v_b := voyage.stores_need_days(v_a, (select k.speed_kn from public.ship_classes k where k.code = public.wc_text('convoy_armed_class')) * public.wc_num('hull_speed_floor'));
  if (select count(distinct k.nation_id) from public.cargo_circuits k) <> (select count(*) from public.great_powers) or v_b > v_days then
    raise exception 'PROOF 36 FAIL: the longest leg, % nm, asks % days of stores at her floor, and she carries %', v_a, v_b, v_days;
  end if;
  raise notice 'PASS: ARMED_STORES — the longest leg of the world, % nm, asks % days at the slowest she can sail; she carries %', v_a, round(v_b, 1), v_days;

  -- ── THE KNOB ALONE ──
  update public.world_config set value = 'true'::jsonb where key = 'convoy_armed_enabled';
  update public.world_config set value = 'false'::jsonb where key = 'convoys_enabled';
  if public.cargo_armed_on() or public.cargo_class() <> public.wc_text('convoy_ship_class') then
    raise exception 'PROOF 36 FAIL: with no ships sailing the knob lit something';
  end if;
  raise notice 'PASS: ARMED_NEEDS_SHIPS — convoys off, class %', public.cargo_class();

  raise notice 'SPEED: old hull crewless % kn = % nm a real minute; armed, crewed, stores aboard % kn = % nm a real minute; the same lap takes % times as long at sea',
    v_sp0, round(v_sp0 * public.wc_num('time_compression') / 60), v_sp1, round(v_sp1 * public.wc_num('time_compression') / 60), round(v_sp0 / v_sp1, 3);
end
$$;
