-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 41 — WANTED  (migration 0334, owner rows 285, 286, W14 of docs/WORLD_POWERS.md)
--
--   0334's self-assert reads the catalog: a migration never runs a real game step (docs/OPS_HEALTH.md section 4). This proof lights the hunt and runs the REAL voyage.depart, voyage.hazard_roll, voyage.settle, regard, fine and purses.
--   THE ECONOMY IS CLOSED HERE, as on prod: a kind that mints would be refused, so FINE passing here is FINE passing there. WANTED_OPEN runs the money once more with it open, as CI's own world is.
--   Every leg is one day, hazard_mult 0, so the sea itself is quiet and only the navy can happen. The fight's outcome is asked for by name on one setting, because each row of the table needs its own. WANTED_SAME_TWICE takes the real engine.
--
-- @pass WANTED_DARK        the knob at 0: a Hostile, WANTED company sails with no side row, a path byte for byte what 0330 froze, and no NAVY day
-- @pass WANTED_MARK        one row a battle and a nation; 48 h; one event; a merchant none; a mark that has run out is no mark
-- @pass WANTED_BATTLE      a battle's end marks her when she won or no ship came, and not when a ship came and she lost; a ship that came too late is no ship
-- @pass WANTED_FREEZE      the row: frozen chance, WANTED twice as likely, the ship of the station that covers most, her sheet; only that station's waters are marked; no ship or no water, no row
-- @pass WANTED_FROZEN      a voyage that left before she was Hostile never meets a navy; one that left Hostile still may, after the fine, the knob and the ship have moved
-- @pass WANTED_NO_MERCHANT a merchant departs, rolls and settles with public.wanted, public.voyage_hostile and public.house_regard gone from the world; a company cannot
-- @pass WANTED_SAME_TWICE  the same days settled at once, day by day, and after her ship has changed read byte for byte alike, through the real fight
-- @pass WANTED_ONCE        at most one NAVY day a voyage, on a marked leg, with the days around it untouched
-- @pass WANTED_QUOTE       a NAVY day leaves p_hazard the sea's, and the premium's quote what it was
-- @pass WANTED_FLOOR       no hull below navy_hull_floor of its size, whatever the shot; a hull below it loses nothing; none is raised
-- @pass WANTED_PLUNDERED   boarded: 25-50 % of every good, -10 % hands, goods moved to the capital's stock to the unit, the fine moved, every purse summed moves 0
-- @pass WANTED_INSURED     insurance pays what it covers, from the insuring city, moved
-- @pass WANTED_FINE_CAP    the fine is the share under its cap; a purse that cannot cover it pays what it holds and is left no debt, and the day's words do not change
-- @pass WANTED_TABLE       paid off: the fine alone. Thrown back, slipped: no goods, no hands, no fine
-- @pass WANTED_HER_SHIP    the navy's real ship takes her hurt; sunk, regard falls through the one writer
-- @pass WANTED_FINE_CLEARS a fine that leaves nothing owed ends the mark, at the capital or at sea; a part of one does not; a fine buys back no more than is owed
-- @pass WANTED_REPORT      the voyage report tells the day, in the shape of a raid: its line and its rounds
-- @pass WANTED_HALL        the hall's line says how long, only while that country's mark stands
-- @pass WANTED_CAPITALS    every great power's capital lists every good, so nothing taken is lost on the way
-- @pass WANTED_OPEN        with the economy open the fine and the goods move exactly the same
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_t     timestamptz := now();
  v_nat   uuid;
  v_cap   uuid;
  v_esp   uuid;
  v_st    uuid;
  v_navy  uuid;
  v_nship uuid;
  v_in    uuid[];
  v_out   uuid;
  v_seas  uuid[];
  v_fl    uuid;
  v_fl2   uuid;
  v_pl    uuid;
  v_voy   uuid;
  v_voy2  uuid;
  v_mer   uuid;
  v_b     uuid;
  v_ship  uuid;
  v_g1    text;
  v_g2    text;
  v_g1id  uuid;
  v_q1    numeric;
  v_q2    numeric;
  v_n     int;
  v_k     int;
  v_mark  bigint;
  v_sum   bigint;
  v_fine  bigint;
  v_a     text;
  v_a2    text;
  v_c     text;
  v_num   numeric;
  v_num2  numeric;
  v_ev    jsonb;
  v_r     jsonb;
  v_eta   timestamptz;
  v_d     int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'regard_enabled', 'npc_refits_enabled', 'navy_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  update public.ports p set crew_pool = 500;

  -- THE FIGHT, BY NAME: byeharu.proof_fight is an outcome, or SLIPPED, FLOOR (she takes every hull's whole size), SINKHER (the navy's ship is lost). Empty, the real engine.
  alter function public.fight_sides(uuid, integer, jsonb, jsonb, jsonb) rename to fight_sides_real_41;
  execute $f$
create function public.fight_sides(p_seed uuid, p_round integer, p_a jsonb, p_b jsonb, p_opts jsonb default '{}'::jsonb)
returns jsonb
language plpgsql stable
as $b$
declare
  v_x   text := coalesce(current_setting('byeharu.proof_fight', true), '');
  v_out text := case v_x when 'SLIPPED' then 'EVADED' when 'FLOOR' then 'DRIVEN_OFF' when 'SINKHER' then 'DRIVEN_OFF' else v_x end;
begin
  if v_x = '' then
    return public.fight_sides_real_41(p_seed, p_round, p_a, p_b, p_opts);
  end if;
  return jsonb_build_object('outcome', v_out, 'stood_off', false, 'slipped', v_x = 'SLIPPED', 'broke_off', false, 'first', 'BOTH', 'rounds_fought', 0, 'rounds', '[]'::jsonb,
    'hull_lost', jsonb_build_object(
      'a', case when v_x = 'FLOOR' then (select jsonb_object_agg(e->>'id', 100000) from jsonb_array_elements(p_a) e) else '{}'::jsonb end,
      'b', case when v_x = 'SINKHER' then (select jsonb_object_agg(e->>'id', 100000) from jsonb_array_elements(p_b) e) else '{}'::jsonb end),
    'hull', jsonb_build_object('a', 1, 'b', case when v_x = 'SINKHER' then 0 else 1 end, 'a_start', 1, 'b_start', 1), 'hits', jsonb_build_object('a', 0, 'b', 0));
end
$b$
  $f$;

  execute $f$
create function pg_temp.purses()
returns bigint
language sql
as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;
  -- one voyage day to a leg, the sea quiet: the leg's own hazard_mult is 0.
  -- A leg is her speed x 24 TO THE DIGIT, never rounded: n legs are then n voyage-days exactly, for any
  -- speed (nm / speed is 24, an exact numeric division). round(speed * 24, 2) was a no-op for a house
  -- (her speed x 24 has two decimals) but not for a merchant: 14.4245 kn gave 346.19 nm for 346.188, six
  -- legs ran 3 ms into a seventh day and the merchant block below counted 7 days for 6 (main, 2026-11-11).
  execute $f$
create function pg_temp.legs(p_fleet uuid, p_seas uuid[])
returns jsonb
language sql
as $b$
  select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', voyage.fleet_speed(p_fleet) * 24, 'sea_id', x.s, 'hazard_mult', 0) order by x.n)
    from unnest(p_seas) with ordinality x(s, n)
$b$
  $f$;
  -- a human company, one armed hull with 100 hands, stores for a year, a purse of p_ducats, in Lisbon. It is Spain's, so a Portuguese ship is a foreign one.
  execute $f$
create function pg_temp.house_41(p_n int, p_ducats bigint default 1000000)
returns uuid
language plpgsql
as $b$
declare
  v_p uuid;
  v_f uuid;
begin
  insert into public.players (company_name, nation_id, ducats) values ('Proof 41 house ' || p_n, (select n.id from public.nations n where n.code = 'ESP'), p_ducats) returning id into v_p;
  v_f := public.form_fleet(v_p, 'Proof 41 fleet ' || p_n, (select p.id from public.ports p where p.code = 'LIS'));
  perform public.commission_ship(v_p, v_f, 'navire', 'Proof 41 hull ' || p_n, true, true);
  update public.ships s set crew = 100, water_t = 5000, food_t = 5000, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_f;
  return v_f;
end
$b$
  $f$;
  execute $f$
create function pg_temp.owner(p_fleet uuid)
returns uuid
language sql
as $b$ select f.player_id from public.fleets f where f.id = p_fleet $b$
  $f$;
  execute $f$
create function pg_temp.hostile(p_fleet uuid, p_nation uuid, p_points numeric default -2000)
returns void
language sql
as $b$
  insert into public.house_regard (player_id, nation_id, points, as_of) values (pg_temp.owner(p_fleet), p_nation, p_points, now())
  on conflict (player_id, nation_id) do update set points = excluded.points, as_of = excluded.as_of
$b$
  $f$;
  execute $f$
create function pg_temp.sail(p_fleet uuid, p_seas uuid[], p_at timestamptz)
returns uuid
language sql
as $b$ select voyage.depart(p_fleet, pg_temp.legs(p_fleet, p_seas), (select p.id from public.ports p where p.code = 'LIS'), null, p_at) $b$
  $f$;
  execute $f$
create function pg_temp.to_end(p_voyage uuid, p_fleet uuid)
returns timestamptz
language plpgsql
as $b$
declare
  v_e timestamptz := (select v.eta from public.voyages v where v.id = p_voyage);
begin
  perform voyage.settle(p_fleet, v_e);
  return v_e;
end
$b$
  $f$;
  -- what a voyage has written, whole
  execute $f$
create function pg_temp.days(p_voyage uuid)
returns text
language sql
as $b$
  select coalesce(string_agg(e.day_index || ':' || e.kind || ':' || e.resolved_at::text || ':' || e.payload::text, E'\n' order by e.day_index), '') from public.voyage_events e where e.voyage_id = p_voyage
$b$
  $f$;
  execute $f$
create function pg_temp.state(p_fleet uuid)
returns text
language sql
as $b$
  select coalesce(string_agg(s.id::text || ':' || s.durability || ':' || s.crew || ':' || s.cargo::text, ',' order by s.id), '') from public.ships s where s.fleet_id = p_fleet
$b$
  $f$;
  execute $f$
create function pg_temp.navy_day(p_voyage uuid)
returns jsonb
language sql
as $b$ select e.payload from public.voyage_events e where e.voyage_id = p_voyage and e.kind = 'NAVY' $b$
  $f$;
  execute $f$
create function pg_temp.a_battle(p_at timestamptz)
returns uuid
language sql
as $b$
  insert into public.battles (kind, site, started_at, resolves_at, status, result)
  values ('ATTACK', '{}'::jsonb, p_at, p_at + interval '10 minutes', 'RESOLVED', '{}'::jsonb) returning id
$b$
  $f$;

  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = 'PRT';
  v_esp := (select n.id from public.nations n where n.code = 'ESP');
  select g.code, g.id into v_g1, v_g1id from public.goods g order by g.base_value, g.code limit 1;
  select g.code into v_g2 from public.goods g order by g.base_value, g.code offset 1 limit 1;

  -- ── EVERY CAPITAL LISTS EVERY GOOD ──
  if exists (select 1 from public.great_powers g cross join public.goods x
              where not exists (select 1 from public.port_goods pg where pg.port_id = public.realm_capital(g.nation_id) and pg.good_id = x.id)) then
    raise exception 'PROOF 41 FAIL: a capital does not list a good, so a seizure of it would be lost';
  end if;
  raise notice 'PASS: WANTED_CAPITALS — every capital lists every good';

  -- ── A NAVY SHIP OF PORTUGAL: from the real job ──
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  update public.port_treasury t set ducats = 900000000 where t.port_id = v_cap;
  for v_k in 1 .. 200 loop
    perform public.tick_navy(v_t, v_nat);
    exit when exists (select 1 from public.navy_ships n where n.nation_id = v_nat);
  end loop;
  select n.fleet_id, n.station_port into v_navy, v_st from public.navy_ships n where n.nation_id = v_nat order by n.ord limit 1;
  if v_navy is null then
    raise exception 'PROOF 41 FAIL: the job built no ship';
  end if;
  update public.ships s set crew = 130 where s.fleet_id = v_navy;
  select s.id into v_nship from public.ships s where s.fleet_id = v_navy limit 1;
  update public.port_treasury t set ducats = 50000000 where t.port_id = v_cap;
  v_in := voyage.navy_waters(v_st);
  select s.id into v_out from public.seas s where not s.id = any (v_in) order by s.code limit 1;
  if cardinality(v_in) < 2 or v_out is null then
    raise exception 'PROOF 41 FAIL: this proof needs two seas in her waters and one out: % in', cardinality(v_in);
  end if;
  if not (select p.sea_id from public.ports p where p.id = v_st) = any (v_in) then
    raise exception 'PROOF 41 FAIL: her station''s own sea is not in her waters';
  end if;
  v_seas := array[v_out, v_out, v_in[1], v_in[2], v_in[1], v_out];

  -- ── DARK ──
  update public.world_config set value = 'true'::jsonb where key = 'regard_enabled';
  v_fl := pg_temp.house_41(1);
  perform pg_temp.hostile(v_fl, v_nat);
  v_b := pg_temp.a_battle(v_t);
  perform public.wanted_mark(pg_temp.owner(v_fl), v_nat, v_b, v_t);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  if exists (select 1 from public.voyage_hostile h where h.voyage_id = v_voy)
     or (select v.path from public.voyages v where v.id = v_voy) is distinct from voyage.freeze_danger(pg_temp.legs(v_fl, v_seas), v_t) then
    raise exception 'PROOF 41 FAIL: at 0 the hunt wrote something';
  end if;
  perform pg_temp.to_end(v_voy, v_fl);
  if exists (select 1 from public.voyage_events e where e.voyage_id = v_voy and e.kind <> 'CLEAR') then
    raise exception 'PROOF 41 FAIL: at 0 a day was not clear: %', pg_temp.days(v_voy);
  end if;
  raise notice 'PASS: WANTED_DARK — at 0 nothing is frozen and nothing happens';

  -- the hunt lit for what follows. The proof's own figure: every marked day finds her, so the marked day is known. A real chance is the owner's.
  update public.world_config set value = to_jsonb(0.5) where key = 'navy_hunt_per_day';

  -- ── THE MARK ──
  v_fl := pg_temp.house_41(2);
  v_pl := pg_temp.owner(v_fl);
  v_b := pg_temp.a_battle(v_t);
  v_mark := (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'WANTED');
  if not public.wanted_mark(v_pl, v_nat, v_b, v_t) or public.wanted_mark(v_pl, v_nat, v_b, v_t + interval '1 hour') then
    raise exception 'PROOF 41 FAIL: a battle did not mark her once';
  end if;
  if (select count(*) from public.wanted w where w.battle_id = v_b) <> 1
     or (select w.until - w.since from public.wanted w where w.battle_id = v_b) <> make_interval(hours => public.wc_int('wanted_hours'))
     or public.wc_int('wanted_hours') <> 48
     or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'WANTED') <> v_mark + 1 then
    raise exception 'PROOF 41 FAIL: the row or its event is wrong';
  end if;
  v_ev := (select e.payload from public.events e where e.player_id = v_pl and e.kind = 'WANTED' limit 1);
  if v_ev ->> 'nation' <> 'PRT' or (v_ev ->> 'hours')::int <> 48 then
    raise exception 'PROOF 41 FAIL: the event does not say who or how long: %', v_ev;
  end if;
  if (select count(*) from public.wanted_nations(v_pl, v_t + interval '47 hours')) <> 1 or (select count(*) from public.wanted_nations(v_pl, v_t + interval '48 hours')) <> 0 then
    raise exception 'PROOF 41 FAIL: a mark does not end at its hour';
  end if;
  v_mer := (select nf.player_id from public.npc_fleets nf order by nf.roster_ord limit 1);
  if public.wanted_mark(v_mer, v_nat, pg_temp.a_battle(v_t), v_t) or exists (select 1 from public.wanted w where w.player_id = v_mer) then
    raise exception 'PROOF 41 FAIL: a merchant was marked';
  end if;
  raise notice 'PASS: WANTED_MARK — one row, 48 hours, one event, no merchant';

  -- ── A BATTLE'S END ──
  perform public.tick_cargo_ships(v_t, v_nat);
  select c.fleet_id into v_ship from public.cargo_ships c where c.nation_id = v_nat order by c.ord limit 1;
  if v_ship is null then
    raise exception 'PROOF 41 FAIL: no cargo ship to attack';
  end if;
  v_fl := pg_temp.house_41(3);
  v_pl := pg_temp.owner(v_fl);
  v_b := pg_temp.a_battle(v_t);   -- nobody came, and she lost: marked
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_b, v_fl, 'ATTACKER', v_t, v_t), (v_b, v_ship, 'DEFENDER', v_t, v_t);
  perform public.attack_close(v_b, '{"outcome": "DRIVEN_OFF", "broke_off": false}'::jsonb, v_t);
  if not exists (select 1 from public.wanted w where w.battle_id = v_b and w.player_id = v_pl and w.nation_id = v_nat) then
    raise exception 'PROOF 41 FAIL: nobody came and she was not marked';
  end if;
  v_b := pg_temp.a_battle(v_t);   -- a ship came in time, and she lost: no mark
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_b, v_fl, 'ATTACKER', v_t, v_t), (v_b, v_ship, 'DEFENDER', v_t, v_t), (v_b, v_navy, 'DEFENDER', v_t, v_t + interval '10 minutes');
  perform public.attack_close(v_b, '{"outcome": "DRIVEN_OFF", "broke_off": false}'::jsonb, v_t);
  if exists (select 1 from public.wanted w where w.battle_id = v_b) then
    raise exception 'PROOF 41 FAIL: a ship came in time and she was marked';
  end if;
  v_b := pg_temp.a_battle(v_t);   -- a ship came in time, and she won: marked
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_b, v_fl, 'ATTACKER', v_t, v_t), (v_b, v_ship, 'DEFENDER', v_t, v_t), (v_b, v_navy, 'DEFENDER', v_t, v_t);
  perform public.attack_close(v_b, '{"outcome": "RANSOM", "broke_off": false}'::jsonb, v_t);
  if not exists (select 1 from public.wanted w where w.battle_id = v_b) then
    raise exception 'PROOF 41 FAIL: she won and was not marked';
  end if;
  v_b := pg_temp.a_battle(v_t);   -- a ship one second late is no ship
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_b, v_fl, 'ATTACKER', v_t, v_t), (v_b, v_ship, 'DEFENDER', v_t, v_t), (v_b, v_navy, 'DEFENDER', v_t, v_t + interval '10 minutes 1 second');
  perform public.attack_close(v_b, '{"outcome": "DRIVEN_OFF", "broke_off": false}'::jsonb, v_t);
  if not exists (select 1 from public.wanted w where w.battle_id = v_b) then
    raise exception 'PROOF 41 FAIL: a late ship counted as an answer';
  end if;
  v_b := pg_temp.a_battle(v_t);   -- the ship set upon is no answer to the attack on her
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_b, v_fl, 'ATTACKER', v_t, v_t), (v_b, v_navy, 'DEFENDER', v_t, v_t);
  if public.navy_arrived(v_b, v_nat, v_navy) or not public.navy_arrived(v_b, v_nat, v_ship) or public.navy_arrived(v_b, v_esp, v_ship) then
    raise exception 'PROOF 41 FAIL: public.navy_arrived';
  end if;
  raise notice 'PASS: WANTED_BATTLE — marked when she won or nobody came in time, not when a ship came and she lost';

  -- ── THE FREEZE ──
  v_fl := pg_temp.house_41(4);
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  if (select h.chance from public.voyage_hostile h where h.voyage_id = v_voy and h.nation_id = v_nat) <> 0.5
     or (select h.fleet_id from public.voyage_hostile h where h.voyage_id = v_voy) is distinct from v_navy
     or (select h.sheet from public.voyage_hostile h where h.voyage_id = v_voy) is distinct from voyage.fleet_hulls(v_navy) then
    raise exception 'PROOF 41 FAIL: the Hostile row is wrong: %', (select to_jsonb(h) from public.voyage_hostile h where h.voyage_id = v_voy);
  end if;
  select count(*), count(*) filter (where e.seg ->> 'navy' = v_nat::text and (e.seg ->> 'sea_id')::uuid = any (v_in))
    into v_n, v_k
    from jsonb_array_elements((select v.path from public.voyages v where v.id = v_voy)) e(seg) where e.seg ? 'navy';
  if v_n <> 3 or v_k <> 3 then
    raise exception 'PROOF 41 FAIL: the marks are not her waters: % of %', v_k, v_n;
  end if;
  if exists (select 1 from jsonb_array_elements((select v.path from public.voyages v where v.id = v_voy)) e(seg) where (e.seg - 'navy') <> e.seg and e.seg ->> 'sea_id' = v_out::text) then
    raise exception 'PROOF 41 FAIL: a sea outside her waters is marked';
  end if;
  if (select jsonb_agg(e.seg - 'navy') from jsonb_array_elements((select v.path from public.voyages v where v.id = v_voy)) e(seg)) is distinct from voyage.freeze_danger(pg_temp.legs(v_fl, v_seas), v_t) then
    raise exception 'PROOF 41 FAIL: the mark moved something else on her path';
  end if;
  v_fl := pg_temp.house_41(5);
  v_b := pg_temp.a_battle(v_t);
  perform public.wanted_mark(pg_temp.owner(v_fl), v_nat, v_b, v_t);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  if (select h.chance from public.voyage_hostile h where h.voyage_id = v_voy) <> 1 then
    raise exception 'PROOF 41 FAIL: WANTED is not twice as likely, or a Hostile regard was needed too';
  end if;
  v_fl := pg_temp.house_41(6);
  perform pg_temp.hostile(v_fl, v_nat, -100);   -- Wary, not Hostile: no row
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  if exists (select 1 from public.voyage_hostile h where h.voyage_id = v_voy) or (select v.path::text from public.voyages v where v.id = v_voy) like '%"navy"%' then
    raise exception 'PROOF 41 FAIL: a company that is not Hostile was frozen';
  end if;
  v_fl := pg_temp.house_41(7);
  perform pg_temp.hostile(v_fl, v_esp);   -- Hostile to a country with no ship: no row
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  if exists (select 1 from public.voyage_hostile h where h.voyage_id = v_voy) then
    raise exception 'PROOF 41 FAIL: a country with no ship has a row';
  end if;
  v_fl := pg_temp.house_41(8);
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, array[v_out, v_out], v_t);   -- a course that keeps clear: no row
  if exists (select 1 from public.voyage_hostile h where h.voyage_id = v_voy) then
    raise exception 'PROOF 41 FAIL: a course outside her waters has a row';
  end if;
  v_fl := pg_temp.house_41(9);
  perform pg_temp.hostile(v_fl, v_nat);
  update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);   -- regard dark: no regard hunts her
  if exists (select 1 from public.voyage_hostile h where h.voyage_id = v_voy) then
    raise exception 'PROOF 41 FAIL: a dark regard hunted her';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'regard_enabled';
  v_fl := pg_temp.house_41(10);
  perform pg_temp.hostile(v_fl, v_nat);
  update public.world_config set value = 'false'::jsonb where key = 'navy_enabled';
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);   -- the navy dark: nobody to send
  if exists (select 1 from public.voyage_hostile h where h.voyage_id = v_voy) then
    raise exception 'PROOF 41 FAIL: a dark navy hunted her';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  raise notice 'PASS: WANTED_FREEZE — frozen chance, ship and sheet, her waters only, WANTED double; no ship, no water or a dark switch writes nothing';

  update public.world_config set value = to_jsonb(1) where key = 'navy_hunt_per_day';

  -- ── FROZEN AT DEPARTURE ──
  perform set_config('byeharu.proof_fight', 'EVADED', true);
  v_fl := pg_temp.house_41(11);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);   -- she left clean
  perform pg_temp.hostile(v_fl, v_nat);
  perform public.wanted_mark(pg_temp.owner(v_fl), v_nat, pg_temp.a_battle(v_t), v_t);
  perform pg_temp.to_end(v_voy, v_fl);
  if exists (select 1 from public.voyage_events e where e.voyage_id = v_voy and e.kind = 'NAVY') or exists (select 1 from public.voyage_hostile h where h.voyage_id = v_voy) then
    raise exception 'PROOF 41 FAIL: a voyage that left before she was Hostile met a navy';
  end if;
  v_fl := pg_temp.house_41(12);
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);   -- she left Hostile, and then everything changed
  delete from public.house_regard r where r.player_id = pg_temp.owner(v_fl);
  update public.world_config set value = to_jsonb(0) where key = 'navy_hunt_per_day';
  update public.world_config set value = 'false'::jsonb where key = 'navy_enabled';
  update public.navy_ships n set laid_up_at = v_t where n.fleet_id = v_navy;
  perform pg_temp.to_end(v_voy, v_fl);
  if not exists (select 1 from public.voyage_events e where e.voyage_id = v_voy and e.kind = 'NAVY') then
    raise exception 'PROOF 41 FAIL: a frozen voyage read what came after it: %', pg_temp.days(v_voy);
  end if;
  update public.world_config set value = to_jsonb(1) where key = 'navy_hunt_per_day';
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  update public.navy_ships n set laid_up_at = null where n.fleet_id = v_navy;
  raise notice 'PASS: WANTED_FROZEN — before, never; after, still, whatever moved since';

  -- ── NO READ FOR A MERCHANT ──
  select nf.fleet_id into v_fl2 from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
   where f.status = 'DOCKED' and not exists (select 1 from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING') order by nf.roster_ord limit 1;
  if v_fl2 is null then
    raise exception 'PROOF 41 FAIL: no merchant in port';
  end if;
  update public.ships s set water_t = 5000, food_t = 5000 where s.fleet_id = v_fl2;
  v_fl := pg_temp.house_41(13);
  perform pg_temp.hostile(v_fl, v_nat);
  begin
    alter table public.wanted rename to wanted_gone_41;
    alter table public.voyage_hostile rename to voyage_hostile_gone_41;
    alter table public.house_regard rename to house_regard_gone_41;
    v_voy := pg_temp.sail(v_fl2, v_seas, v_t);
    perform pg_temp.to_end(v_voy, v_fl2);
    if (select count(*) from public.voyage_events e where e.voyage_id = v_voy) <> cardinality(v_seas) then
      raise exception 'PROOF 41 FAIL: the merchant did not settle every day';
    end if;
    -- the positive control: with the tables gone, a company's departure cannot run. So the merchant's did not reach them.
    begin
      perform pg_temp.sail(v_fl, v_seas, v_t);
      raise exception 'PROOF 41 FAIL: a company departed with the tables gone, so this test proves nothing';
    exception when undefined_table then
      null;
    end;
    raise exception using errcode = 'ZX341', message = 'ok';
  exception when sqlstate 'ZX341' then
    null;
  end;
  raise notice 'PASS: WANTED_NO_MERCHANT — a merchant sailed and settled with the three tables gone from the world, and a company could not';

  -- ── THE SAME DAY SETTLED TWICE ──
  perform set_config('byeharu.proof_fight', '', true);
  v_fl := pg_temp.house_41(14);
  update public.ships s set cargo = jsonb_build_object(v_g1, 400, v_g2, 90), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  v_eta := (select v.eta from public.voyages v where v.id = v_voy);
  v_d := voyage.total_days(v_voy);
  begin   -- at once
    perform voyage.settle(v_fl, v_eta);
    raise exception using errcode = 'ZX341', message = pg_temp.days(v_voy) || E'\n#\n' || pg_temp.state(v_fl);
  exception when sqlstate 'ZX341' then
    v_a := sqlerrm;
  end;
  begin   -- day by day
    for v_k in 1 .. v_d loop
      perform voyage.settle(v_fl, voyage.day_ends_at(v_voy, v_k));
    end loop;
    perform voyage.settle(v_fl, v_eta);
    raise exception using errcode = 'ZX341', message = pg_temp.days(v_voy) || E'\n#\n' || pg_temp.state(v_fl);
  exception when sqlstate 'ZX341' then
    v_a2 := sqlerrm;
  end;
  begin   -- late, and after her ship was hurt, unmanned and laid up, the country's stock moved, the fine's knobs moved, the regard forgiven
    update public.ships s set durability = 1, crew = 0 where s.fleet_id = v_navy;
    update public.navy_ships n set laid_up_at = v_t where n.fleet_id = v_navy;
    delete from public.house_regard r where r.player_id = pg_temp.owner(v_fl);
    update public.world_config set value = to_jsonb(0) where key = 'navy_hunt_per_day';
    perform voyage.settle(v_fl, v_eta + interval '3 days');
    raise exception using errcode = 'ZX341', message = pg_temp.days(v_voy) || E'\n#\n' || pg_temp.state(v_fl);
  exception when sqlstate 'ZX341' then
    v_c := sqlerrm;
  end;
  if v_a is distinct from v_a2 or v_a is distinct from v_c then
    raise exception 'PROOF 41 FAIL: the same days read differently. AT ONCE: % DAY BY DAY: % LATE: %', v_a, v_a2, v_c;
  end if;
  if v_a not like '%:NAVY:%' then
    raise exception 'PROOF 41 FAIL: no NAVY day in the comparison: %', v_a;
  end if;
  raise notice 'PASS: WANTED_SAME_TWICE — at once, day by day and late read byte for byte alike, % characters', length(v_a);

  -- ── AT MOST ONCE ──
  perform set_config('byeharu.proof_fight', 'EVADED', true);
  v_fl := pg_temp.house_41(15);
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, array[v_out, v_in[1], v_in[1], v_in[1], v_in[1], v_out], v_t);
  perform pg_temp.to_end(v_voy, v_fl);
  if (select count(*) from public.voyage_events e where e.voyage_id = v_voy and e.kind = 'NAVY') <> 1 then
    raise exception 'PROOF 41 FAIL: not one NAVY day: %', pg_temp.days(v_voy);
  end if;
  select e.day_index into v_n from public.voyage_events e where e.voyage_id = v_voy and e.kind = 'NAVY';
  if not voyage.leg_at_day(v_voy, v_n) ? 'navy' or exists (select 1 from generate_series(1, v_n - 1) d where voyage.leg_at_day(v_voy, d) ? 'navy') then
    raise exception 'PROOF 41 FAIL: the NAVY day is not her first marked day: %', v_n;
  end if;
  if exists (select 1 from public.voyage_events e where e.voyage_id = v_voy and e.kind not in ('NAVY', 'CLEAR')) then
    raise exception 'PROOF 41 FAIL: another kind stood beside it: %', pg_temp.days(v_voy);
  end if;
  raise notice 'PASS: WANTED_ONCE — day %, one', v_n;

  -- ── THE QUOTE ──
  v_fl := pg_temp.house_41(16);
  perform pg_temp.hostile(v_fl, v_nat);
  update public.seas s set hazard_base = 0.05 where s.id = any (v_seas);
  v_voy2 := voyage.depart(v_fl, (select jsonb_agg(e || '{"hazard_mult": 1}'::jsonb) from jsonb_array_elements(pg_temp.legs(v_fl, v_seas)) e), v_cap, null, v_t);
  v_num := voyage.risk_quote(v_voy2);
  if not exists (select 1 from generate_series(1, 6) d cross join lateral voyage.hazard_roll(v_voy2, d) h where h.kind = 'NAVY') then
    raise exception 'PROOF 41 FAIL: the quote was read on a voyage with no NAVY day';
  end if;
  update public.voyages v set path = (select jsonb_agg(x.seg - 'navy' order by o) from jsonb_array_elements(v.path) with ordinality x(seg, o)) where v.id = v_voy2;
  if v_num is distinct from voyage.risk_quote(v_voy2) then
    raise exception 'PROOF 41 FAIL: the premium moves with the hunt: % against %', v_num, voyage.risk_quote(v_voy2);
  end if;
  update public.seas s set hazard_base = 0.02 where s.id = any (v_seas);
  raise notice 'PASS: WANTED_QUOTE — p_hazard stays the sea''s';

  -- ── THE FLOOR ──
  perform set_config('byeharu.proof_fight', 'FLOOR', true);
  v_fl := pg_temp.house_41(17);
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  perform pg_temp.to_end(v_voy, v_fl);
  select s.durability, (select b.durability from public.ship_base(s.id) b) into v_num, v_num2 from public.ships s where s.fleet_id = v_fl;
  if v_num <> v_num2 * 0.25 or public.wc_num('navy_hull_floor') <> 0.25 or (select f.status from public.fleets f where f.id = v_fl) = 'UNABLE_TO_SAIL' then
    raise exception 'PROOF 41 FAIL: the floor did not hold: % of %', v_num, v_num2;
  end if;
  v_fl := pg_temp.house_41(18);
  perform pg_temp.hostile(v_fl, v_nat);
  update public.ships s set durability = 3 where s.fleet_id = v_fl;
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  perform pg_temp.to_end(v_voy, v_fl);
  if (select s.durability from public.ships s where s.fleet_id = v_fl) <> 3 then
    raise exception 'PROOF 41 FAIL: a hull below the floor was moved: %', (select s.durability from public.ships s where s.fleet_id = v_fl);
  end if;
  raise notice 'PASS: WANTED_FLOOR — % of % and no lower; a hull under it stays', v_num, v_num2;

  -- ── BOARDED ──
  perform set_config('byeharu.proof_fight', 'PLUNDERED', true);
  v_fl := pg_temp.house_41(19);
  v_pl := pg_temp.owner(v_fl);
  update public.ships s set cargo = jsonb_build_object(v_g1, 1000, v_g2, 7), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  v_num := (select pg.stock from public.port_goods pg where pg.port_id = v_cap and pg.good_id = v_g1id);
  v_sum := pg_temp.purses();
  v_mark := coalesce((select max(t.id) from public.treasury_flows t), 0);
  v_fine := least(100000, round(0.05 * (1000 * (select g.base_value from public.goods g where g.code = v_g1) + 7 * (select g.base_value from public.goods g where g.code = v_g2))))::bigint;
  perform pg_temp.to_end(v_voy, v_fl);
  v_ev := pg_temp.navy_day(v_voy);
  v_q1 := (v_ev -> 'cargo_lost' ->> v_g1)::numeric;
  v_q2 := coalesce((v_ev -> 'cargo_lost' ->> v_g2)::numeric, 0);
  if v_q1 is null or v_q1 < 250 or v_q1 > 500 or v_q2 > 3 then
    raise exception 'PROOF 41 FAIL: not 25-50 %%: %', v_ev;
  end if;
  if (select (s.cargo ->> v_g1)::numeric from public.ships s where s.fleet_id = v_fl) <> 1000 - v_q1 then
    raise exception 'PROOF 41 FAIL: her hold does not say what the day says';
  end if;
  if (select pg.stock from public.port_goods pg where pg.port_id = v_cap and pg.good_id = v_g1id) <> v_num + v_q1 then
    raise exception 'PROOF 41 FAIL: the stock did not gain what she lost: % to %, took %', v_num, (select pg.stock from public.port_goods pg where pg.port_id = v_cap and pg.good_id = v_g1id), v_q1;
  end if;
  if (select s.crew from public.ships s where s.fleet_id = v_fl) <> 90 or (v_ev ->> 'crew_lost')::numeric <> 10 or (v_ev ->> 'base_loss')::numeric <> 0.10 then
    raise exception 'PROOF 41 FAIL: the hands are not -10 %%: %', v_ev;
  end if;
  if (v_ev ->> 'fine')::bigint <> v_fine or v_fine <= 0 then
    raise exception 'PROOF 41 FAIL: the fine is % and the day says %', v_fine, v_ev ->> 'fine';
  end if;
  if (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.id > v_mark and t.kind = 'FINE' and t.port_id = v_cap) <> v_fine
     or (select count(*) from public.treasury_flows t where t.id > v_mark and t.kind = 'FINE') <> 1
     or (select -sum(l.ducats_delta) from public.ledger l where l.player_id = v_pl and l.kind = 'FINE') <> v_fine then
    raise exception 'PROOF 41 FAIL: the fine did not move from her purse to the capital';
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 41 FAIL: every purse summed moved by %', pg_temp.purses() - v_sum;
  end if;
  if (select (e.payload ->> 'amount')::bigint from public.events e where e.player_id = v_pl and e.kind = 'FINE_PAID') <> v_fine then
    raise exception 'PROOF 41 FAIL: FINE_PAID does not say what moved';
  end if;
  raise notice 'PASS: WANTED_PLUNDERED — % of 1000 to the stock, -10 %% hands, fine % moved, every purse summed moves 0', v_q1, v_fine;

  -- ── INSURED ──
  v_fl := pg_temp.house_41(20);
  v_pl := pg_temp.owner(v_fl);
  update public.ships s set cargo = jsonb_build_object(v_g1, 1000), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  insert into public.insured_voyages (voyage_id, fleet_id, player_id, port_id, cargo, basis, value, risk, price, keep_pct)
  values (v_voy, v_fl, v_pl, v_cap, jsonb_build_object(v_g1, 1000), jsonb_build_object(v_g1, 100), 100000, 0.01, 1000, 0.1);
  v_sum := pg_temp.purses();
  perform pg_temp.to_end(v_voy, v_fl);
  v_q1 := (pg_temp.navy_day(v_voy) -> 'cargo_lost' ->> v_g1)::numeric;
  if (select i.paid from public.insured_voyages i where i.voyage_id = v_voy) <> round(v_q1 * 100 * 0.9)
     or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'INSURANCE_PAID' and e.payload ->> 'cause' = 'NAVY') <> 1 then
    raise exception 'PROOF 41 FAIL: insurance did not pay what it covers: % on %', (select i.paid from public.insured_voyages i where i.voyage_id = v_voy), v_q1;
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 41 FAIL: insured, every purse summed moved by %', pg_temp.purses() - v_sum;
  end if;
  raise notice 'PASS: WANTED_INSURED — paid %, moved', (select i.paid from public.insured_voyages i where i.voyage_id = v_voy);

  -- ── THE CAP AND A SHORT PURSE ──
  perform set_config('byeharu.proof_fight', 'RANSOM', true);
  select g.code into v_a from public.goods g order by g.base_value desc, g.code limit 1;
  v_fl := pg_temp.house_41(21, 5000000);
  v_pl := pg_temp.owner(v_fl);
  update public.ships s set cargo = jsonb_build_object(v_a, ceil(4000000 / (select g.base_value from public.goods g where g.code = v_a))), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  perform pg_temp.to_end(v_voy, v_fl);
  if (pg_temp.navy_day(v_voy) ->> 'fine')::bigint <> 100000 or (select p.ducats from public.players p where p.id = v_pl) <> 4900000 then
    raise exception 'PROOF 41 FAIL: the cap: %', pg_temp.navy_day(v_voy);
  end if;
  v_fl := pg_temp.house_41(22, 700);
  v_pl := pg_temp.owner(v_fl);
  update public.ships s set cargo = jsonb_build_object(v_a, ceil(4000000 / (select g.base_value from public.goods g where g.code = v_a))), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  v_sum := pg_temp.purses();
  perform pg_temp.to_end(v_voy, v_fl);
  if (pg_temp.navy_day(v_voy) ->> 'fine')::bigint <> 100000 or (select p.ducats from public.players p where p.id = v_pl) <> 0 or pg_temp.purses() <> v_sum
     or (select (e.payload ->> 'amount')::bigint from public.events e where e.player_id = v_pl and e.kind = 'FINE_PAID') <> 700 then
    raise exception 'PROOF 41 FAIL: a short purse: %', pg_temp.navy_day(v_voy);
  end if;
  v_fl := pg_temp.house_41(23, 0);
  v_pl := pg_temp.owner(v_fl);
  update public.ships s set cargo = jsonb_build_object(v_a, 100), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  perform pg_temp.to_end(v_voy, v_fl);
  if exists (select 1 from public.events e where e.player_id = v_pl and e.kind = 'FINE_PAID') or exists (select 1 from public.ledger l where l.player_id = v_pl and l.kind = 'FINE') then
    raise exception 'PROOF 41 FAIL: an empty purse paid something';
  end if;
  raise notice 'PASS: WANTED_FINE_CAP — 100,000 at most; 700 d. pays 700 and owes nothing; nothing pays nothing';

  -- ── THE REST OF THE TABLE ──
  v_fl := pg_temp.house_41(24);
  v_pl := pg_temp.owner(v_fl);
  update public.ships s set cargo = jsonb_build_object(v_g1, 1000), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  perform pg_temp.to_end(v_voy, v_fl);
  v_ev := pg_temp.navy_day(v_voy);
  if v_ev ->> 'outcome' <> 'RANSOM' or v_ev ? 'cargo_lost' or (v_ev ->> 'crew_lost')::numeric <> 0 or (v_ev ->> 'fine')::bigint <= 0 or (select (s.cargo ->> v_g1)::numeric from public.ships s where s.fleet_id = v_fl) <> 1000 then
    raise exception 'PROOF 41 FAIL: paid off: %', v_ev;
  end if;
  foreach v_c in array array['DRIVEN_OFF', 'EVADED', 'SLIPPED'] loop
    perform set_config('byeharu.proof_fight', v_c, true);
    v_fl := pg_temp.house_41(25 + (select count(*)::int from public.players));
    v_pl := pg_temp.owner(v_fl);
    update public.ships s set cargo = jsonb_build_object(v_g1, 1000), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
    perform pg_temp.hostile(v_fl, v_nat);
    v_voy := pg_temp.sail(v_fl, v_seas, v_t);
    v_sum := (select p.ducats from public.players p where p.id = v_pl);
    perform pg_temp.to_end(v_voy, v_fl);
    v_ev := pg_temp.navy_day(v_voy);
    if v_ev ? 'cargo_lost' or (v_ev ->> 'crew_lost')::numeric <> 0 or (v_ev ->> 'fine')::bigint <> 0 or (select p.ducats from public.players p where p.id = v_pl) <> v_sum
       or (select (s.cargo ->> v_g1)::numeric from public.ships s where s.fleet_id = v_fl) <> 1000 or (select s.crew from public.ships s where s.fleet_id = v_fl) <> 100 then
      raise exception 'PROOF 41 FAIL: %: %', v_c, v_ev;
    end if;
  end loop;
  raise notice 'PASS: WANTED_TABLE — paid off: the fine; thrown back or slipped: nothing but the shot';

  -- ── HER SHIP ──
  perform set_config('byeharu.proof_fight', 'SINKHER', true);
  v_fl := pg_temp.house_41(90);
  v_pl := pg_temp.owner(v_fl);
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  v_num := public.regard_of(v_pl, v_nat);
  perform pg_temp.to_end(v_voy, v_fl);
  if (select s.durability from public.ships s where s.id = v_nship) <> 0 then
    raise exception 'PROOF 41 FAIL: her real ship took no hurt';
  end if;
  if public.regard_of(v_pl, v_nat) >= v_num - 99 or public.wc_num('regard_sink') <> -100
     or not exists (select 1 from public.events e where e.player_id = v_pl and e.kind = 'REGARD_CHANGED' and e.payload ->> 'reason' = 'SINK_NAVY') then
    raise exception 'PROOF 41 FAIL: sunk, regard did not fall through the writer: % to %', v_num, public.regard_of(v_pl, v_nat);
  end if;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.id = v_nship;
  raise notice 'PASS: WANTED_HER_SHIP — her hull at 0, regard falls by regard_sink';

  -- ── A FINE ENDS THE MARK ──
  v_fl := pg_temp.house_41(91, 5000000);
  v_pl := pg_temp.owner(v_fl);
  perform pg_temp.hostile(v_fl, v_nat, -500);
  v_b := pg_temp.a_battle(v_t);
  perform public.wanted_mark(v_pl, v_nat, v_b, v_t);
  update public.fleets f set port_id = v_cap, status = 'DOCKED' where f.id = v_fl;
  v_r := public.fine_for(v_pl, v_cap, public.wc_int('regard_fine_per_point'));
  if (select count(*) from public.wanted_nations(v_pl, now())) <> 1 then
    raise exception 'PROOF 41 FAIL: a part of a fine ended the mark: %', v_r;
  end if;
  v_r := public.fine_for(v_pl, v_cap, 100000000);
  if (select count(*) from public.wanted_nations(v_pl, now())) <> 0 or public.fine_owed(v_pl, v_nat) <> 0 then
    raise exception 'PROOF 41 FAIL: a fine that left nothing owed did not end the mark: %', v_r;
  end if;
  perform set_config('byeharu.proof_fight', 'RANSOM', true);
  v_fl := pg_temp.house_41(92, 5000000);   -- at sea
  v_pl := pg_temp.owner(v_fl);
  update public.ships s set cargo = jsonb_build_object(v_a, ceil(4000000 / (select g.base_value from public.goods g where g.code = v_a))), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
  perform pg_temp.hostile(v_fl, v_nat, -400);
  perform public.wanted_mark(v_pl, v_nat, pg_temp.a_battle(v_t), v_t);
  v_num := public.regard_of(v_pl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  v_eta := pg_temp.to_end(v_voy, v_fl);
  if public.fine_owed(v_pl, v_nat) <> 0 or (select count(*) from public.wanted_nations(v_pl, v_eta)) <> 0 then
    raise exception 'PROOF 41 FAIL: at sea a fine that left nothing owed did not end the mark';
  end if;
  if public.regard_of(v_pl, v_nat) > public.regard_of(v_pl, v_esp) + 300 then
    raise exception 'PROOF 41 FAIL: 100,000 d. bought more than was owed: % against %', public.regard_of(v_pl, v_nat), v_num;
  end if;
  if exists (select 1 from public.house_regard r where r.player_id = v_pl and r.nation_id = v_nat and r.points > 0.001) then
    raise exception 'PROOF 41 FAIL: a fine lifted her above what she had earned: %', (select r.points from public.house_regard r where r.player_id = v_pl and r.nation_id = v_nat);
  end if;
  raise notice 'PASS: WANTED_FINE_CLEARS — a part leaves it, all of it ends it, at the capital or at sea, and buys no more than was owed';

  -- ── THE REPORT ──
  perform set_config('byeharu.proof_fight', '', true);
  v_fl := pg_temp.house_41(93);
  v_pl := pg_temp.owner(v_fl);
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  perform pg_temp.to_end(v_voy, v_fl);
  v_ev := (select e.payload from public.events e where e.player_id = v_pl and e.kind = 'VOYAGE_REPORT' and e.payload ->> 'voyage_id' = v_voy::text);
  v_n := (select e.day_index from public.voyage_events e where e.voyage_id = v_voy and e.kind = 'NAVY');
  if v_ev is null or (v_ev -> 'lines' ->> (v_n - 1)) not like format('Day %s. %%navy ship of Portugal%%', v_n) then
    raise exception 'PROOF 41 FAIL: the report has no line for the day: %', v_ev -> 'lines';
  end if;
  if (v_ev -> 'fights' -> 0 ->> 'line')::int is distinct from v_n - 1 or coalesce(jsonb_array_length(v_ev -> 'fights' -> 0 -> 'rounds'), 0) < 1
     or coalesce(v_ev -> 'fights' -> 0 -> 'rounds' ->> 0, '') not like 'Navy: one %' then
    raise exception 'PROOF 41 FAIL: the report has no rounds for the day: %', v_ev -> 'fights';
  end if;
  raise notice 'PASS: WANTED_REPORT — %', v_ev -> 'lines' ->> (v_n - 1);

  -- ── THE HALL ──
  v_fl := pg_temp.house_41(94);
  v_pl := pg_temp.owner(v_fl);
  if public.regard_line(v_cap, v_pl) -> 'regard' ? 'wanted_hours' then
    raise exception 'PROOF 41 FAIL: the hall says wanted of a clean company';
  end if;
  perform public.wanted_mark(v_pl, v_nat, pg_temp.a_battle(now()), now());
  if (public.regard_line(v_cap, v_pl) -> 'regard' ->> 'wanted_hours')::int <> 48 then
    raise exception 'PROOF 41 FAIL: the hall does not say how long: %', public.regard_line(v_cap, v_pl);
  end if;
  if public.regard_line((select p.id from public.ports p where p.code = 'SVQ'), v_pl) -> 'regard' ? 'wanted_hours' then
    raise exception 'PROOF 41 FAIL: Spain''s hall read Portugal''s mark';
  end if;
  raise notice 'PASS: WANTED_HALL — that country''s halls alone, for as long as it stands';

  -- ── THE ECONOMY OPEN ──
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  perform set_config('byeharu.proof_fight', 'PLUNDERED', true);
  v_fl := pg_temp.house_41(95);
  v_pl := pg_temp.owner(v_fl);
  update public.ships s set cargo = jsonb_build_object(v_g1, 1000), cargo_basis = '{}'::jsonb where s.fleet_id = v_fl;
  perform pg_temp.hostile(v_fl, v_nat);
  v_voy := pg_temp.sail(v_fl, v_seas, v_t);
  v_num := (select pg.stock from public.port_goods pg where pg.port_id = v_cap and pg.good_id = v_g1id);
  v_sum := pg_temp.purses();
  perform pg_temp.to_end(v_voy, v_fl);
  v_ev := pg_temp.navy_day(v_voy);
  if pg_temp.purses() <> v_sum or (select pg.stock from public.port_goods pg where pg.port_id = v_cap and pg.good_id = v_g1id) <> v_num + (v_ev -> 'cargo_lost' ->> v_g1)::numeric
     or (v_ev ->> 'fine')::bigint <= 0 then
    raise exception 'PROOF 41 FAIL: open, the money or the goods moved otherwise: %', v_ev;
  end if;
  raise notice 'PASS: WANTED_OPEN — fine %, goods moved alike', v_ev ->> 'fine';
end
$$;
