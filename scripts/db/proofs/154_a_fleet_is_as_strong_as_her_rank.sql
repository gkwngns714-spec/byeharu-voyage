-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 154 - A FLEET IS AS STRONG AS HER RANK  (migration 0451; docs/dev-log/2026-11-16-npc-ladder.md; the owner, 2026-11-16: "every pirate
--   ship's graphic is same. the one with stronger ships, multiple fleets should have different graphics. this goes to every kinds of ship too")
--
--   Lit as prod is (the purses, the closed economy, the pirates, the refit rule, attacks, the armed cargo ships), through the pirates' own minute
--   job (public.tick_pirates), a pirate's own step (public.pirate_ship_step) and a cargo ship's own refit (public.cargo_hull), rolled back with
--   proof.mjs's transaction. EVERY MARKER FAILS BEFORE 0451: no fleet was ever re-rated, a navy ship was one galion and a cargo ship one navire.
--
-- @pass NL_LADDER  the ladder is data: five pirate rungs, four navy, three cargo; Spain's navy is her own line (galeón real + galeón, galeón, two zabras, two cutters); the rule's table for a navy of six and a cargo share of eight
-- @pass NL_ROSTER  a NEW roster fleet is built as her rung: the first squadron of a hub is a Dread (kalyon + 3 xebec), her lead ship under the fleet's name; she is not re-rated again
-- @pass NL_PASS    an old squadron (galeoncete + 3 xebec) lying in harbour is re-rated by the minute's job to the Dread she is: four hulls, one flagship under her name, every hull holding her level's points (npc_ship_level), her hands conserved; the one count (public.fleet_census) says 4 ships
-- @pass NL_HELD    never on a side of a battle being fought, never with goods in a hold, never at sea, never busy: each time she stays as she is; freed, she is taken, and the hands her smaller hull does not need are back on the quay
-- @pass NL_PACE    at most npc_ladder_per_minute (2) of a kind a minute: of five due pirates one run takes two, the next minute two more, the third the last
-- @pass NL_REBORN  a pirate wreck is reborn as her rung: her own step brings her home, she lies, pays the refit of the hull she was, and sails again as two xebec, whole
-- @pass NL_NAVY    a navy of six galions is re-rated by station in three minutes: the capital's a Ship of the line with her frigate, two Frigates, two pairs of Brigs, a pair of Cutters; a ship called to a fight waits
-- @pass NL_CARGO   a cargo ship's own refit makes her Large, Medium or Small by her country's share and her seniority; one hull each, under her name
-- @pass NL_DARK    the switch off: the job re-rates nobody, a fleet stays as she is, and a cargo ship's refit is 0328's class again
-- @pass NL_GOLD    not a ducat is made or lost by any of it: the world's money (purses, houses, funds aboard) is the same at the end
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.w_154() returns numeric language sql as $f$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$f$;
-- a fleet's hulls as public.npc_hulls_sig writes them
create function pg_temp.sig_154(p_fleet uuid) returns text language sql as $f$
  select string_agg(h.code || '*' || h.n, '+' order by h.code)
    from (select k.code, count(*) as n from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = p_fleet group by k.code) h
$f$;
-- a fleet made by the hands every fleet is made by, full of hands, docked; the first class is her flagship
create function pg_temp.fleet_154(p_nation uuid, p_name text, p_port uuid, p_classes text[]) returns uuid language plpgsql as $f$
declare
  v_pl uuid;
  v_fl uuid;
  i    int;
begin
  insert into public.players (company_name, nation_id, ducats, is_npc) values (p_name, p_nation, 0, true) returning id into v_pl;
  v_fl := public.form_fleet(v_pl, p_name, p_port);
  for i in 1 .. cardinality(p_classes) loop
    perform public.commission_ship(v_pl, v_fl, p_classes[i], case when i = 1 then p_name else p_name || ' ' || i end, i = 1, false);
  end loop;
  update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl;
  return v_fl;
end
$f$;
create function pg_temp.pirate_154(p_ord int, p_port uuid, p_classes text[]) returns uuid language plpgsql as $f$
declare
  v_fl uuid := pg_temp.fleet_154(public.pirate_nation(), 'Proof 154 pirate ' || p_ord, p_port, p_classes);
begin
  insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port, created_at)
  values (v_fl, (select f.player_id from public.fleets f where f.id = v_fl), p_ord, p_port, p_port, now());
  return v_fl;
end
$f$;

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_nat   uuid := (select n.id from public.nations n where n.code = 'ESP');
  v_cap   uuid;
  v_w0    numeric;
  v_f     uuid;
  v_g     uuid;
  v_p     uuid[] := '{}';
  v_n     uuid[] := '{}';
  v_c     uuid[] := '{}';
  v_bat   uuid;
  v_r     jsonb;
  v_s     text;
  v_k     int;
  v_pool  bigint;
  v_hands bigint;
  v_wait  int := public.wc_int('pirate_respawn_minutes');
  v_ok    boolean;
  v_ok2   boolean;
  i       int;
begin
  -- ── THE SCENE ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'pirates_bite', 'npc_refits_enabled', 'attack_enabled', 'convoys_enabled', 'convoy_armed_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_trade') and value is distinct from 'false'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.port_treasury t set ducats = 1900000000 where t.port_id = public.pirate_capital();
  update public.world_config set value = to_jsonb(0) where key in ('pirate_wakes_per_run', 'pirate_cargo_ships');
  update public.pirate_ships set laid_up_at = t0 where laid_up_at is null;
  update public.pirate_clock set added_at = t0 + interval '1 day', paid_at = t0 + interval '1 day';
  v_cap := public.realm_capital(v_nat);
  if not public.pirates_on() or not public.npc_ladder_on() or v_hub is null or v_cap is null or public.wc_int('npc_ladder_per_minute') <> 2 then
    raise exception 'PROOF 154 FAIL: the pirates or the ladder are not lit, or Tristan, Spain''s capital or the pace of 2 is not in this world';
  end if;
  v_w0 := pg_temp.w_154();

  -- ── NL_LADDER ──
  if (select count(*) from public.npc_ladder where kind = 'PIRATE') <> 5 or (select count(*) from public.npc_ladder where kind = 'NAVY') <> 4
     or (select count(*) from public.npc_ladder where kind = 'CARGO') <> 3
     or (select string_agg(h.class || '*' || h.n, '+' order by h.class) from public.npc_ladder_hulls h where h.kind = 'NAVY' and h.rung = 4 and h.line = 'ESP') <> 'galeon*1+galreal*1'
     or (select string_agg(h.class || '*' || h.n, '+' order by h.class) from public.npc_ladder_hulls h where h.kind = 'NAVY' and h.rung = 2 and h.line = 'ESP') <> 'zabra*2'
     or (select string_agg(h.class || '*' || h.n, '+' order by h.class) from public.npc_ladder_hulls h where h.kind = 'PIRATE' and h.rung = 5 and h.line = '*') <> 'kalyon*1+xebec*3'
     or (select array_agg(public.npc_rung_rule('NAVY', o, 6) order by o) from generate_series(1, 6) o) <> array[4, 3, 3, 2, 2, 1]
     or (select array_agg(public.npc_rung_rule('CARGO', o, 8) order by o) from generate_series(1, 8) o) <> array[3, 3, 2, 2, 2, 2, 1, 1] then
    raise exception 'PROOF 154 FAIL: the ladder''s rows or the rule are not 0451''s';
  end if;
  raise notice 'PASS: NL_LADDER — 5 / 4 / 3 rungs; Spain''s Ship of the line %; a navy of six %, a cargo share of eight %',
    (select string_agg(h.class || '*' || h.n, '+' order by h.class) from public.npc_ladder_hulls h where h.kind = 'NAVY' and h.rung = 4 and h.line = 'ESP'),
    (select array_agg(public.npc_rung_rule('NAVY', o, 6) order by o) from generate_series(1, 6) o),
    (select array_agg(public.npc_rung_rule('CARGO', o, 8) order by o) from generate_series(1, 8) o);

  -- ── NL_ROSTER: a new roster fleet is built as her rung (public.pirate_commission_fleet reads public.pirate_roster_hulls) ──
  v_f := public.pirate_commission_fleet(3006, public.refit_yard(v_hub), t0);
  if v_f is null or pg_temp.sig_154(v_f) <> 'kalyon*1+xebec*3' or public.npc_rung_of(v_f) <> 5 or public.npc_hulls_sig(v_f) <> 'kalyon*1+xebec*3'
     or (select k.code from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_f and s.is_flagship) <> 'kalyon'
     or (select s.name from public.ships s where s.fleet_id = v_f and s.is_flagship) <> (select r.fleet_name from public.pirate_roster r where r.ord = 3006) then
    raise exception 'PROOF 154 FAIL: roster fleet 3006 was not built a Dread: %', pg_temp.sig_154(v_f);
  end if;
  v_ok := public.npc_ladder_refit(v_f, t0);
  if v_ok or not exists (select 1 from public.npc_fleet_rungs g where g.fleet_id = v_f and g.rung = 5) then
    raise exception 'PROOF 154 FAIL: a fleet built as her rung was re-rated, or her rung row was not written';
  end if;
  raise notice 'PASS: NL_ROSTER — roster fleet 3006 built %, rung 5 (Dread), lead ship "%"', pg_temp.sig_154(v_f), (select s.name from public.ships s where s.fleet_id = v_f and s.is_flagship);
  update public.pirate_ships set laid_up_at = t0 where fleet_id = v_f;

  -- ── NL_PASS: an old squadron (as 0414 built her), lying in harbour, through the minute's job ──
  v_f := pg_temp.pirate_154(3024, v_hub, array['galeoncete', 'xebec', 'xebec', 'xebec']);
  update public.fleets set ready_at = t0 + interval '30 minutes' where id = v_f;   -- she lies: the job does not step her
  v_hands := (select sum(s.crew) from public.ships s where s.fleet_id = v_f) + (select p.crew_pool from public.ports p where p.id = v_hub);
  v_r := public.tick_pirates(t0);
  if (v_r ->> 'rated')::int is distinct from 1 or pg_temp.sig_154(v_f) <> 'kalyon*1+xebec*3'
     or (select count(*) from public.ships s where s.fleet_id = v_f and s.is_flagship and s.name = 'Proof 154 pirate 3024') <> 1
     or (select count(*) from public.ships s where s.fleet_id = v_f and not s.is_flagship and s.name in ('Proof 154 pirate 3024 2', 'Proof 154 pirate 3024 3', 'Proof 154 pirate 3024 4')) <> 3
     or (select count(*) from public.ships s join public.ship_xp q on q.ship_id = s.id where s.fleet_id = v_f and q.xp = public.level_points(round(public.wc_num('npc_ship_level'))::int)) <> 4
     or (select sum(s.crew) from public.ships s where s.fleet_id = v_f) + (select p.crew_pool from public.ports p where p.id = v_hub) <> v_hands
     or (select c.ships from public.fleet_census(v_f) c) <> 4 or (select c.kind from public.fleet_census(v_f) c) <> 'PIRATE'
     or (select f.status from public.fleets f where f.id = v_f) <> 'DOCKED' then
    raise exception 'PROOF 154 FAIL: the job did not re-rate the old squadron to a Dread: answer %, hulls %, names %, levels %, hands % of %, census %', v_r, pg_temp.sig_154(v_f),
      (select string_agg(s.name, ' | ' order by s.name) from public.ships s where s.fleet_id = v_f),
      (select string_agg(public.level_in_force(q.xp)::text, ',') from public.ships s join public.ship_xp q on q.ship_id = s.id where s.fleet_id = v_f),
      (select sum(s.crew) from public.ships s where s.fleet_id = v_f) + (select p.crew_pool from public.ports p where p.id = v_hub), v_hands,
      (select to_jsonb(c) from public.fleet_census(v_f) c);
  end if;
  if (public.tick_pirates(t0 + interval '1 minute')) ? 'rated' then
    raise exception 'PROOF 154 FAIL: the job re-rated a fleet that is her rung';
  end if;
  raise notice 'PASS: NL_PASS — galeoncete + 3 xebec -> % by public.tick_pirates (rated 1), 4 hulls holding the points of npc_ship_level, hands % conserved, census 4 ships', pg_temp.sig_154(v_f), v_hands;
  update public.pirate_ships set laid_up_at = t0 where fleet_id = v_f;

  -- ── NL_HELD: one of 0339's ships, ord 2 (a Raider: one brigantin), a xebec today ──
  v_f := pg_temp.pirate_154(2, v_hub, array['xebec']);
  update public.fleets set ready_at = t0 + interval '2 hours' where id = v_f;
  insert into public.battles (kind, site, started_at, resolves_at, status) values ('RAID', '{}'::jsonb, t0, t0 + interval '1 hour', 'FIGHTING') returning id into v_bat;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how) values (v_bat, v_f, 'ATTACKER', t0, t0, 'OPENED');
  v_r := public.npc_ladder_pass(t0 + interval '2 minutes');
  if v_r ? 'rated' or pg_temp.sig_154(v_f) <> 'xebec*1' then
    raise exception 'PROOF 154 FAIL: a fleet on a side of a battle being fought was re-rated';
  end if;
  update public.battles set status = 'RESOLVED' where id = v_bat;
  update public.ships s set cargo = '{"canary-sack": 3}'::jsonb where s.fleet_id = v_f;
  v_r := public.npc_ladder_pass(t0 + interval '3 minutes');
  if v_r ? 'rated' or pg_temp.sig_154(v_f) <> 'xebec*1' then
    raise exception 'PROOF 154 FAIL: a fleet with goods in her hold was re-rated';
  end if;
  update public.ships s set cargo = '{}'::jsonb where s.fleet_id = v_f;
  update public.fleets set status = 'SAILING', port_id = null where id = v_f;
  v_ok := public.npc_ladder_refit(v_f, t0 + interval '3 minutes');
  if v_ok or (public.npc_ladder_pass(t0 + interval '3 minutes')) ? 'rated' then
    raise exception 'PROOF 154 FAIL: a fleet at sea was re-rated';
  end if;
  update public.fleets set status = 'DOCKED', port_id = v_hub, busy_until = t0 + interval '1 hour' where id = v_f;
  if (public.npc_ladder_pass(t0 + interval '4 minutes')) ? 'rated' then
    raise exception 'PROOF 154 FAIL: a busy fleet was re-rated';
  end if;
  update public.fleets set busy_until = null where id = v_f;
  v_pool := (select p.crew_pool from public.ports p where p.id = v_hub);
  v_r := public.npc_ladder_pass(t0 + interval '5 minutes');
  if (v_r ->> 'rated')::int is distinct from 1 or pg_temp.sig_154(v_f) <> 'brigantin*1'
     or (select s.crew from public.ships s where s.fleet_id = v_f) <> (select c.crew_required from public.ship_classes c where c.code = 'brigantin')
     or (select p.crew_pool from public.ports p where p.id = v_hub) - v_pool
        <> (select c.crew_required from public.ship_classes c where c.code = 'xebec') - (select c.crew_required from public.ship_classes c where c.code = 'brigantin') then
    raise exception 'PROOF 154 FAIL: freed, she was not re-rated to a brigantin with her hands, the rest on the quay: %, %', v_r, pg_temp.sig_154(v_f);
  end if;
  raise notice 'PASS: NL_HELD — in a battle, with goods aboard, at sea, busy: she stays a xebec; freed: %, % hands back on the quay', pg_temp.sig_154(v_f),
    (select p.crew_pool from public.ports p where p.id = v_hub) - v_pool;
  update public.pirate_ships set laid_up_at = t0 where fleet_id = v_f;

  -- ── NL_PACE: five due pirates (ords 4, 8, 10, 14, 16: Raiders, xebecs today), two a minute ──
  foreach i in array array[4, 8, 10, 14, 16] loop
    v_g := pg_temp.pirate_154(i, v_hub, array['xebec']);
    update public.fleets set ready_at = t0 + interval '2 hours' where id = v_g;
    v_p := v_p || v_g;
  end loop;
  v_s := '';
  for i in 10 .. 12 loop
    v_r := public.npc_ladder_pass(t0 + make_interval(mins => i));
    v_s := v_s || coalesce(v_r ->> 'rated', '0') || ' ';
    if i = 10 then   -- the same minute again: the room is spent
      v_r := public.npc_ladder_pass(t0 + make_interval(mins => i, secs => 30));
      v_s := v_s || '(' || coalesce(v_r ->> 'rated', '0') || ') ';
    end if;
  end loop;
  if v_s <> '2 (0) 2 1 ' or (select count(*) from unnest(v_p) x where pg_temp.sig_154(x) = 'brigantin*1') <> 5 then
    raise exception 'PROOF 154 FAIL: the pace is not two of a kind a minute: % (% of 5 re-rated)', v_s, (select count(*) from unnest(v_p) x where pg_temp.sig_154(x) = 'brigantin*1');
  end if;
  raise notice 'PASS: NL_PACE — five due pirates, three minutes: % (the same minute again in brackets)', v_s;
  update public.pirate_ships set laid_up_at = t0 where fleet_id = any (v_p);

  -- ── NL_REBORN: ord 5 (Consorts: two xebec), one xebec today, every hull at 0, through her own step ──
  v_f := pg_temp.pirate_154(5, v_hub, array['xebec']);
  update public.ships s set durability = 0 where s.fleet_id = v_f;
  v_s := public.pirate_ship_step(v_f, t0 + interval '20 minutes');
  if v_s <> 'WRECK' or pg_temp.sig_154(v_f) <> 'xebec*1' then
    raise exception 'PROOF 154 FAIL: the wreck''s first step answered % (hulls %)', v_s, pg_temp.sig_154(v_f);
  end if;
  v_s := public.pirate_ship_step(v_f, t0 + interval '20 minutes' + make_interval(mins => v_wait + 1));
  if v_s <> 'REBORN' or pg_temp.sig_154(v_f) <> 'xebec*2' or (select f.status from public.fleets f where f.id = v_f) <> 'DOCKED'
     or exists (select 1 from public.ships s where s.fleet_id = v_f and s.durability <> (select b.durability from public.ship_base(s.id) b))
     or (select count(*) from public.ships s where s.fleet_id = v_f and s.is_flagship) <> 1
     or not exists (select 1 from public.npc_fleet_rungs g where g.fleet_id = v_f and g.rung = 3 and g.hulls = 'xebec*2') then
    raise exception 'PROOF 154 FAIL: the wreck was not reborn as two xebec, whole: % (hulls %)', v_s, pg_temp.sig_154(v_f);
  end if;
  raise notice 'PASS: NL_REBORN — WRECK, then % after % min: %, every hull whole', v_s, v_wait + 1, pg_temp.sig_154(v_f);
  update public.pirate_ships set laid_up_at = t0 where fleet_id = v_f;

  -- ── NL_NAVY: Spain keeps six; six galions at her capital, ords 1 to 6 ──
  insert into public.navy_realms (nation_id, ships) values (v_nat, 6) on conflict (nation_id) do update set ships = 6;
  for i in 1 .. 6 loop
    v_g := pg_temp.fleet_154(v_nat, 'Proof 154 navy ' || i, v_cap, array['galion']);
    insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port, created_at)
    values (v_g, (select f.player_id from public.fleets f where f.id = v_g), v_nat, 900 + i, v_cap, v_cap, t0);
    v_n := v_n || v_g;
  end loop;
  update public.navy_ships n set ord = n.ord - 900 where n.fleet_id = any (v_n) and not exists (select 1 from public.navy_ships o where o.nation_id = v_nat and o.ord <= 6);
  if (select count(*) from public.navy_ships n where n.fleet_id = any (v_n) and n.ord between 1 and 6) <> 6 then
    raise exception 'PROOF 154 FAIL: Spain already keeps navy ships of ords 1 to 6 in this world';
  end if;
  update public.navy_ships n set called_to = v_cap where n.fleet_id = v_n[6];   -- called to a fight: she waits
  v_s := '';
  for i in 20 .. 23 loop
    v_r := public.npc_ladder_pass(t0 + make_interval(mins => i));
    v_s := v_s || coalesce(v_r ->> 'rated', '0') || ' ';
  end loop;
  if v_s <> '2 2 1 0 ' or pg_temp.sig_154(v_n[6]) <> 'galion*1' then
    raise exception 'PROOF 154 FAIL: five free navy ships were not re-rated two a minute, or the one called to a fight was: % (ord 6 %)', v_s, pg_temp.sig_154(v_n[6]);
  end if;
  update public.navy_ships n set called_to = null where n.fleet_id = v_n[6];
  v_r := public.npc_ladder_pass(t0 + interval '24 minutes');
  if (select array_agg(pg_temp.sig_154(x) order by o) from unnest(v_n) with ordinality u(x, o))
       <> array['galeon*1+galreal*1', 'galeon*1', 'galeon*1', 'zabra*2', 'zabra*2', 'brigantin*2']
     or (select array_agg(public.npc_rung_of(x) order by o) from unnest(v_n) with ordinality u(x, o)) <> array[4, 3, 3, 2, 2, 1]
     or (select k.code from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_n[1] and s.is_flagship) <> 'galreal'
     or (select s.name from public.ships s where s.fleet_id = v_n[1] and s.is_flagship) <> 'Proof 154 navy 1'
     or (select sum(c.ships) from public.fleet_census() c where c.fleet_id = any (v_n)) <> 10 then
    raise exception 'PROOF 154 FAIL: Spain''s six are not Line, Frigate, Frigate, Brigs, Brigs, Cutters of her own line: %',
      (select array_agg(pg_temp.sig_154(x) order by o) from unnest(v_n) with ordinality u(x, o));
  end if;
  raise notice 'PASS: NL_NAVY — six galions, minutes % then the one called: %', v_s, (select array_agg(pg_temp.sig_154(x) order by o) from unnest(v_n) with ordinality u(x, o));

  -- ── NL_CARGO: Spain's share is eight; ords 1, 4 and 8, each one hull of 0328's class, through her own refit ──
  insert into public.cargo_fleet_sizes (nation_id, ships, cash, set_at, read_at) values (v_nat, 8, 0, t0, t0 + interval '2 hours')
  on conflict (nation_id) do update set ships = 8, read_at = excluded.read_at;
  foreach i in array array[1, 4, 8] loop
    v_g := pg_temp.fleet_154(v_nat, 'Proof 154 cargo ' || i, v_cap, array[public.cargo_class()]);
    insert into public.cargo_ships (fleet_id, player_id, nation_id, home_port_id, ord)
    values (v_g, (select f.player_id from public.fleets f where f.id = v_g), v_nat, v_cap, 900 + i);
    v_c := v_c || v_g;
  end loop;
  update public.cargo_ships c set ord = c.ord - 900 where c.fleet_id = any (v_c) and not exists (select 1 from public.cargo_ships o where o.nation_id = v_nat and o.ord in (1, 4, 8));
  if public.convoy_ships_of(v_nat) <> 8 or (select count(*) from public.cargo_ships c where c.fleet_id = any (v_c) and c.ord in (1, 4, 8)) <> 3 then
    raise exception 'PROOF 154 FAIL: Spain''s share is not 8 here, or she already keeps cargo ships of ords 1, 4, 8';
  end if;
  v_ok := public.cargo_hull(v_c[1]);
  v_ok2 := public.cargo_hull(v_c[2]);
  if not v_ok or not v_ok2 then
    raise exception 'PROOF 154 FAIL: a cargo ship''s refit did not re-rate her';
  end if;
  if public.cargo_hull(v_c[3]) then
    raise exception 'PROOF 154 FAIL: a third cargo ship was re-rated in a minute that allows two';
  end if;
  update public.npc_ladder_clock set minute = null where kind = 'CARGO';   -- the next minute
  v_ok := public.cargo_hull(v_c[3]);
  v_ok2 := public.cargo_hull(v_c[1]);
  if not v_ok
     or (select array_agg(pg_temp.sig_154(x) order by o) from unnest(v_c) with ordinality u(x, o)) <> array['galmanila*1', 'urca*1', 'carabela*1']
     or (select count(*) from public.ships s where s.fleet_id = any (v_c) and s.is_flagship and s.name like 'Proof 154 cargo %') <> 3
     or v_ok2 then
    raise exception 'PROOF 154 FAIL: Spain''s cargo ships 1, 4, 8 of 8 are not Large, Medium, Small of her line: %',
      (select array_agg(pg_temp.sig_154(x) order by o) from unnest(v_c) with ordinality u(x, o));
  end if;
  raise notice 'PASS: NL_CARGO — ords 1, 4, 8 of a share of 8: %', (select array_agg(pg_temp.sig_154(x) order by o) from unnest(v_c) with ordinality u(x, o));

  -- ── NL_DARK ──
  update public.world_config set value = 'false'::jsonb where key = 'npc_ladder_enabled';
  v_f := pg_temp.pirate_154(20, v_hub, array['xebec']);   -- ord 20: a Raider by the rule
  update public.fleets set ready_at = t0 + interval '3 hours' where id = v_f;
  v_r := public.tick_pirates(t0 + interval '40 minutes');
  v_ok := public.npc_ladder_refit(v_f, t0 + interval '41 minutes');
  v_ok2 := public.cargo_hull(v_c[1]);
  if v_r ? 'rated' or pg_temp.sig_154(v_f) <> 'xebec*1' or v_ok
     or not v_ok2 or pg_temp.sig_154(v_c[1]) <> public.cargo_class() || '*1' or pg_temp.sig_154(v_n[1]) <> 'galeon*1+galreal*1' then
    raise exception 'PROOF 154 FAIL: dark, somebody was re-rated, or a cargo ship''s refit is not 0328''s: %, %', v_r, pg_temp.sig_154(v_c[1]);
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'npc_ladder_enabled';
  raise notice 'PASS: NL_DARK — the switch off: the job rated nobody, the pirate stays %, the cargo ship is % again, the navy stays as rated', pg_temp.sig_154(v_f), pg_temp.sig_154(v_c[1]);

  -- ── NL_GOLD ──
  if pg_temp.w_154() <> v_w0 then
    raise exception 'PROOF 154 FAIL: the world''s money moved by % (% -> %)', pg_temp.w_154() - v_w0, v_w0, pg_temp.w_154();
  end if;
  raise notice 'PASS: NL_GOLD — the world''s money % before and after (the roster build and the wreck''s refit were moved, city to yard; no re-rating moved a ducat)', v_w0;
end $p$;
