-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 107 — LEVELS ARE MANY, AND EACH IS RAISED BY DOING  (migration 0411, docs/LEVELS.md)
--
--   The migration's self-assert proves the writer's arithmetic on stubs. This proof plays the doors the hooks stand in: a real
--   voyage that voyage.settle lands, real standing-route laps, a real share bought of a city; and holds a merchant to nothing.
--   Every figure is worked out here from public.level_activity_terms() (the rates the writer reads), never typed.
--   Everything rolls back with proof.mjs's transaction, the knobs set here with it (hazard_p_max 0, as proofs 04, 55 and 59).
--
-- @pass LVL_MERCHANT_NOTHING  a merchant's direct grant, her arrival, her 20 real laps closed at a gain and her real share bought of a city write no tuple to the level tables (pg_stat_xact_user_tables); a human's grant is the positive control
-- @pass LVL_ARRIVAL           a new house's first real voyage through voyage.settle grants Supplies its days at sea x the rate once, by the voyage's key; settled again it writes nothing
-- @pass LVL_LAP               a real standing-route lap closed at a gain grants Routes its rate once (key lap:<lap id>); a lap with no gain grants nothing
-- @pass LVL_SHARE             a real share bought through public.invest_for grants Investment floor(cost / per), inside the cap a day
-- @pass LVL_LEVEL_UP          every level a grant crossed is ONE LEVEL_UP event {track, level, reputation} and ONE Reputation book row of rep_level_per_level x the level
-- @pass LVL_RECORD_UNMOVED    public.player_progress is byte-equal before and after grants (Trading, Exploration and Combat stay its own), and the page's three old tracks are what it serves there
-- @pass LVL_READ              world.levels() serves every level's points, today and recent grants as the book holds them, and its curve is public.level_points
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0411-4000-8000-0000000000a1';
  c_tabs  constant text[] := array['level_skills', 'level_activities', 'level_xp', 'level_book'];
  v_gift  constant int := public.wc_int('rep_level_per_level');
  v_npc   uuid;
  v_nfl   uuid;
  v_a     uuid;
  v_fleet uuid;
  v_lis   uuid;
  v_dest_code text;
  v_good_code text;
  v_mcode text;
  v_qty   numeric;
  v_voy   uuid;
  v_nm    numeric;
  v_days  int;
  v_route uuid;
  v_nroute uuid;
  v_lap   uuid;
  v_w     bigint;
  v_n     int;
  v_m     int;
  v_want  int;
  v_cost  bigint;
  v_r     jsonb;
  v_s     jsonb;
  v_pp    jsonb;
  v_fed   numeric;
  v_lap_xp numeric;
  v_share_per numeric;
  v_cap   int;
  v_note  text;
begin
  select id into v_lis from public.ports where code = 'LIS';
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'reputation_on', 'level_skills_on') and value is distinct from 'true'::jsonb;
  select t.xp / t.per into v_fed from public.level_activity_terms() t where t.code = 'fed';
  select t.xp into v_lap_xp from public.level_activity_terms() t where t.code = 'lap';
  select t.per / t.xp into v_share_per from public.level_activity_terms() t where t.code = 'share';
  select s.day_cap into v_cap from public.level_skills s where s.code = 'investment';

  -- ── LVL_MERCHANT_NOTHING (asked first: the counters are this transaction's) ──
  v_npc := public.new_house(null, 'Casa Mercante 107', 'PRT', 'LIS', 'Mercante', 'barca', 'Mercante', 5000000, true);
  select id into v_nfl from public.fleets where player_id = v_npc;
  select g.code into v_mcode
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and g.bulk <= 1 and pg.stock_target > 0
   order by pg.stock_target desc, g.code limit 1;
  if public.level_grant(v_npc, 'hull', 1, 'hull:m107') <> 0 or public.level_grant(v_npc, 'share', 9000000) <> 0 then
    raise exception 'PROOF 107 FAILED: a merchant was granted experience';
  end if;
  v_voy := gen_random_uuid();
  insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  values (v_voy, v_nfl, v_npc, '[]', 1200, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
  insert into public.voyage_events (voyage_id, day_index, kind, payload)
  select v_voy, g, case g when 2 then 'STORM' else 'CLEAR' end, '{"short_rations": false}' from generate_series(1, 5) g;
  if public.level_arrival(v_npc, v_voy) <> 0 then
    raise exception 'PROOF 107 FAILED: a merchant''s arrival was granted experience';
  end if;
  insert into public.standing_routes (player_id, name, fleet_id) values (v_npc, 'Rota 107 M', v_nfl) returning id into v_nroute;
  v_n := 0;
  for i in 1 .. 20 loop
    perform public.fleet_load(v_nfl, v_mcode, 1, 100);   -- more aboard than the lap before: every lap closes at a gain, the arm in which a merchant goes furthest into the writer
    insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_nroute, i, now()) returning id into v_lap;
    update public.standing_routes set lap_id = v_lap, lap_no = i where id = v_nroute;
    perform cmd.standing_route_close_lap(v_nroute, now());
    if (select x.net from public.standing_route_laps x where x.id = v_lap) > 0 then v_n := v_n + 1; end if;
  end loop;
  v_r := public.invest_for(v_npc, v_lis, 'docks', 10);
  v_w := (select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) from pg_stat_xact_user_tables where schemaname = 'public' and relname = any (c_tabs));
  if v_n <> 20 or (v_r ->> 'ok')::boolean is not true or v_w <> 0
     or exists (select 1 from public.events e where e.player_id = v_npc and e.kind = 'LEVEL_UP') then
    raise exception 'PROOF 107 FAILED: % of 20 merchant laps closed at a gain, her share answered %, and the merchant wrote % tuple(s) to the level tables', v_n, v_r, v_w;
  end if;

  -- ── the house that plays ──
  v_a := public.new_house(c_a, 'Casa dos Niveis 107', 'PRT');
  perform cmd.assume_identity(c_a);
  select id into v_fleet from public.fleets where player_id = v_a;
  -- the positive control of the count above: a human's grant IS counted by the same view
  if public.level_grant(v_a, 'made', 1) < 1
     or (select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) from pg_stat_xact_user_tables where schemaname = 'public' and relname = any (c_tabs)) < 2 then
    raise exception 'PROOF 107 FAILED: the control counted no write for a human''s grant (the merchant''s zero proves nothing)';
  end if;
  raise notice 'PASS: LVL_MERCHANT_NOTHING — a merchant''s direct grants answered 0, her arrival (five days, one a storm) 0, her 20 real laps closed at a gain and her real share of Lisbon''s docks: % tuples written to the four level tables; a human''s one grant wrote its rows (the control).', v_w;

  -- ── LVL_ARRIVAL: a real voyage, landed by voyage.settle ──
  v_pp := public.player_progress(v_a);
  perform cmd.issue(v_fleet, 'PROVISION FULL');
  v_r := world.trade_routes(v_lis, v_fleet, 1700, null);
  select e -> 'to' ->> 'code', e ->> 'code', floor((e ->> 'qty')::numeric)
    into v_dest_code, v_good_code, v_qty
    from jsonb_array_elements(v_r -> 'routes') e join public.goods g on g.code = e ->> 'code'
   where g.bulk <= 1.0 and (e ->> 'qty')::numeric >= 2
     and (e ->> 'nm')::numeric >= (select t.voyage_nm from public.level_activity_terms() t where t.code = 'fed')
   order by (e ->> 'profit')::numeric desc, e ->> 'code' limit 1;
  if v_dest_code is null then
    raise exception 'PROOF 107 FAILED: the quay at Lisbon names no trade a starter can sail';
  end if;
  v_r := proof.sail(v_fleet, v_dest_code);
  if not (v_r ->> 'ok')::boolean then
    raise exception 'PROOF 107 FAILED: SAIL was refused: %', v_r;
  end if;
  select v.id, v.total_nm into v_voy, v_nm from public.voyages v where v.fleet_id = v_fleet and v.status = 'SAILING';
  update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where id = v_voy;
  perform world.fleets();   -- the read is the catch-up: voyage.settle runs here
  if (select f.status from public.fleets f where f.id = v_fleet) <> 'DOCKED' then
    raise exception 'PROOF 107 FAILED: she did not make %', v_dest_code;
  end if;
  select count(*) filter (where ve.kind not in ('LANDFALL', 'FORCED_HOME')),
         count(*) filter (where ve.kind = 'SHORT_RATIONS' or coalesce((ve.payload ->> 'short_rations')::boolean, false))
    into v_days, v_m from public.voyage_events ve where ve.voyage_id = v_voy;
  if v_days < 1 or v_m <> 0 then
    raise exception 'PROOF 107 FAILED: the probe voyage had % day(s) at sea and % hungry: it proves nothing about days fed', v_days, v_m;
  end if;
  v_want := floor(v_days * v_fed);
  if coalesce((select x.xp from public.level_xp x where x.player_id = v_a and x.skill = 'supplies'), 0) <> v_want
     or (select b.activity || ':' || b.xp || ':' || b.key from public.level_book b where b.player_id = v_a and b.skill = 'supplies' and b.seq = 1)
        is distinct from 'fed:' || v_want || ':fed:' || v_voy
     or exists (select 1 from public.level_xp x where x.player_id = v_a and x.skill = 'weather') then
    raise exception 'PROOF 107 FAILED: a real arrival after % day(s) at sea, none hungry, did not grant Supplies % once (hazards are off: Weather must have nothing)', v_days, v_want;
  end if;
  select count(*) into v_n from public.level_book b where b.player_id = v_a;
  perform voyage.settle(v_fleet, now());
  perform world.fleets();
  if public.level_arrival(v_a, v_voy) <> 0 or (select count(*) from public.level_book b where b.player_id = v_a) <> v_n then
    raise exception 'PROOF 107 FAILED: the same arrival settled again granted something';
  end if;
  raise notice 'PASS: LVL_ARRIVAL — a new house sailed % nm to % in % day(s) at sea, none hungry: voyage.settle granted Supplies % (% a day) once, key fed:<voyage>; Weather nothing (no hazard); settled again and asked again: nothing.',
    round(v_nm), v_dest_code, v_days, v_want, v_fed;

  -- ── LVL_LAP: real laps of her route ──
  if public.fleet_load(v_fleet, v_mcode, 5, 100) <> 5 then
    raise exception 'PROOF 107 FAILED: the probe''s cargo did not go aboard';
  end if;
  insert into public.standing_routes (player_id, name, fleet_id) values (v_a, 'Rota 107', v_fleet) returning id into v_route;
  insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_route, 1, now()) returning id into v_lap;
  update public.standing_routes set lap_id = v_lap, lap_no = 1 where id = v_route;
  perform cmd.standing_route_close_lap(v_route, now());
  if (select x.net from public.standing_route_laps x where x.id = v_lap) <= 0
     or (select x.xp from public.level_xp x where x.player_id = v_a and x.skill = 'routes') is distinct from v_lap_xp::int
     or (select b.activity || ':' || b.key from public.level_book b where b.player_id = v_a and b.skill = 'routes' and b.seq = 1) is distinct from 'lap:lap:' || v_lap
     or public.level_grant(v_a, 'lap', 1, 'lap:' || v_lap) <> 0 then
    raise exception 'PROOF 107 FAILED: a real lap closed at a gain did not grant Routes % once', v_lap_xp;
  end if;
  insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_route, 2, now()) returning id into v_lap;
  update public.standing_routes set lap_id = v_lap, lap_no = 2 where id = v_route;
  perform cmd.standing_route_close_lap(v_route, now());
  if (select x.net from public.standing_route_laps x where x.id = v_lap) > 0
     or (select x.xp from public.level_xp x where x.player_id = v_a and x.skill = 'routes') <> v_lap_xp::int then
    raise exception 'PROOF 107 FAILED: a real lap closed with no gain granted Routes something';
  end if;
  raise notice 'PASS: LVL_LAP — a real lap closed at a gain granted Routes % once (key lap:<lap id>; asked again by its key: 0); a real lap with no gain granted nothing.', v_lap_xp;

  -- ── LVL_SHARE: a real share of a city ──
  update public.players set ducats = ducats + 50000000 where id = v_a;   -- the probe's own purse
  v_r := public.invest_for(v_a, v_lis, 'docks', 10);
  if (v_r ->> 'ok')::boolean is not true then
    raise exception 'PROOF 107 FAILED: the share was refused: %', v_r;
  end if;
  v_cost := (v_r ->> 'cost')::bigint;
  v_want := least(floor(v_cost / v_share_per), v_cap);
  if coalesce((select x.xp from public.level_xp x where x.player_id = v_a and x.skill = 'investment'), 0) <> v_want
     or (v_want > 0 and (select x.day_earned from public.level_xp x where x.player_id = v_a and x.skill = 'investment') <> v_want) then
    raise exception 'PROOF 107 FAILED: a share of % d. did not grant Investment %', v_cost, v_want;
  end if;
  v_note := format('ten shares of Lisbon''s docks for %s d. granted Investment %s (1 a %s d., at most %s a day)', v_cost, v_want, v_share_per, v_cap);
  -- and the cap: grants to the cap, then nothing more that day
  v_n := public.level_grant(v_a, 'share', 1000000000);
  if v_n <> v_cap - v_want or public.level_grant(v_a, 'share', 1000000000) <> 0
     or (select x.day_earned from public.level_xp x where x.player_id = v_a and x.skill = 'investment') <> v_cap then
    raise exception 'PROOF 107 FAILED: Investment''s day did not stop at % (% more granted)', v_cap, v_n;
  end if;
  raise notice 'PASS: LVL_SHARE — %; a great sum after it granted % more, to the cap, and the next nothing.', v_note, v_n;

  -- ── LVL_LEVEL_UP: every crossing so far, one event and one gift each ──
  if v_gift <= 0 then
    raise exception 'PROOF 107 FAILED: rep_level_per_level is % in this chain: the gift cannot be proved', v_gift;
  end if;
  select count(*) into v_n from public.level_xp x where x.player_id = v_a and public.level_from_points(x.xp) > 1;
  if v_n < 1
     or exists (select 1 from public.level_xp x cross join lateral generate_series(2, public.level_from_points(x.xp)) g
                 where x.player_id = v_a
                   and ((select count(*) from public.events e where e.player_id = v_a and e.kind = 'LEVEL_UP' and e.payload ->> 'track' = x.skill
                                                                 and (e.payload ->> 'level')::int = g and (e.payload ->> 'reputation')::int = v_gift * g) <> 1
                     or (select count(*) from public.reputation_book k where k.player_id = v_a and k.kind = 'level' and k.key = 'level:' || x.skill || ':' || g and k.delta = v_gift * g) <> 1))
     or (select count(*) from public.events e where e.player_id = v_a and e.kind = 'LEVEL_UP'
           and e.payload ->> 'track' in (select s.code from public.level_skills s where s.kept = 'book'))
        <> (select coalesce(sum(public.level_from_points(x.xp) - 1), 0) from public.level_xp x where x.player_id = v_a) then
    raise exception 'PROOF 107 FAILED: a level crossed did not fire exactly one LEVEL_UP event with one gift of % x the level', v_gift;
  end if;
  select string_agg(x.skill || ' ' || public.level_from_points(x.xp), ', ' order by x.skill) into v_note from public.level_xp x where x.player_id = v_a and public.level_from_points(x.xp) > 1;
  raise notice 'PASS: LVL_LEVEL_UP — she stands at %: each level crossed is ONE LEVEL_UP event {track, level, reputation} and ONE book row of % x the level (key level:<code>:<L>), and there is no other.', v_note, v_gift;

  -- ── LVL_RECORD_UNMOVED: the three old levels are still public.player_progress's ──
  v_r := world.levels();
  if public.player_progress(v_a) -> 'combat' is distinct from v_pp -> 'combat'
     or exists (select 1 from jsonb_array_elements(v_r -> 'level_skills' -> 'skills') e
                 where e ->> 'kept' = 'record'
                   and ((e ->> 'points')::numeric <> (public.player_progress(v_a) -> (e ->> 'code') ->> 'points')::numeric
                     or (e ->> 'level')::int <> (public.player_progress(v_a) -> (e ->> 'code') ->> 'level')::int
                     or (e ->> 'level')::int <> (v_r -> 'tracks' -> (e ->> 'code') ->> 'level')::int
                     or jsonb_typeof(e -> 'recent') <> 'null'))
     or exists (select 1 from pg_proc p where p.oid = 'public.player_progress(uuid)'::regprocedure and p.prosrc like '%level\_xp%') then
    raise exception 'PROOF 107 FAILED: a level counted from the record moved, or the page serves it from somewhere else';
  end if;
  v_pp := public.player_progress(v_a);
  perform public.level_grant(v_a, 'made', 3);
  perform public.level_grant(v_a, 'hull', 1, 'hull:p107');
  if public.player_progress(v_a)::text <> v_pp::text then
    raise exception 'PROOF 107 FAILED: a grant moved public.player_progress';
  end if;
  raise notice 'PASS: LVL_RECORD_UNMOVED — Trading, Exploration and Combat on the page are public.player_progress''s points and levels, to the figure, with no grant rows; two more grants left public.player_progress byte-equal; its body does not name the book.';

  -- ── LVL_READ: the page is the book ──
  v_r := world.levels() -> 'level_skills';
  if exists (select 1 from jsonb_array_elements(v_r -> 'skills') e
              left join public.level_xp x on x.player_id = v_a and x.skill = e ->> 'code'
              where e ->> 'kept' = 'book'
                and ((e ->> 'points')::int <> coalesce(x.xp, 0)
                  or (e ->> 'level')::int <> public.level_from_points(coalesce(x.xp, 0))
                  or (e ->> 'today')::int <> coalesce(x.day_earned, 0)
                  or (e ->> 'cap')::int <> (select s.day_cap from public.level_skills s where s.code = e ->> 'code')
                  or jsonb_array_length(e -> 'recent') <> least(coalesce(x.seq, 0), 5)
                  or (coalesce(x.seq, 0) > 0 and (e -> 'recent' -> 0 ->> 'xp')::int
                        <> (select b.xp from public.level_book b where b.player_id = v_a and b.skill = x.skill and b.seq = x.seq))))
     or exists (select 1 from generate_series(1, (v_r ->> 'top')::int) g where (v_r -> 'curve' ->> (g - 1))::numeric <> public.level_points(g))
     or exists (select 1 from jsonb_array_elements(v_r -> 'skills') e cross join jsonb_array_elements(e -> 'activities') a
                 join public.level_activity_terms() t on t.code = a ->> 'code'
                where (a ->> 'xp')::numeric <> t.xp or (a ->> 'per')::numeric <> t.per) then
    raise exception 'PROOF 107 FAILED: the page does not serve the book, the curve or the rates as they are: %', left(v_r::text, 400);
  end if;
  raise notice 'PASS: LVL_READ — world.levels() serves % levels; every book level''s points, level, today, cap and newest grant are the book''s own rows; every activity''s figures are public.level_activity_terms''; the curve''s % steps are public.level_points.',
    jsonb_array_length(v_r -> 'skills'), (v_r ->> 'top')::int;
end
$p$;
