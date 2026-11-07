-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 44 — A CAPTAIN HAS A SHEET  (migration 0337, owner row 288: "captains should also have stats")
--
--   world.captain_stats(code) is a read that composes the readers that own each figure: a level is public.captain_level, a part is HER OWN TERM, what public.crew_terms gives for her seat (the arithmetic
--   public.crew_pct sums and world.crew_bonuses lists by source). A cap is the crew's, not hers. This proof builds a probe crew of NINE signings in two hulls (the Captain's cabin, a cabin of her own focus, a cabin off it, a promoted captain, a Gunner and a Navigator on the second hull, one ashore, one with no xp row),
--   asks every captain for her sheet, and holds each figure to the reader that owns it, to a number worked out here from the tables (the amount, not "non-zero"), and to the fight. Everything rolls back with proof.mjs's
--   transaction. No part of it sets a knob it does not put back: the switches it needs are written here, in this transaction, and the world it runs in is its own.
--
-- @pass SHEET_DOOR         authenticated reads; anon is refused 42501; a stranger, a signed-out caller and a code nobody keeps read null, never an error; the code is read as the verbs read it
-- @pass SHEET_SHAPE        five stats in the design's order, each with its own track, each effect once, in order; the sheet's `line` is the server's words over the part
-- @pass SHEET_EQUALS_CREW  below the cap and with no Command, for every effect of the five stats, on every hull, the parts of the captains in a crew add up to crew_pct x 100, and a captain alone reads crew_pct itself
-- @pass SHEET_AMOUNT       a part is worked out here from the tables: base (or the grade's floor once promoted) x the level x the cabin's rate, to the digit, and it is the very term public.crew_terms gives
-- @pass SHEET_CAP          the cap is the crew's: a part above the cap still reads whole, and crew_pct x 100 is the least of the parts' sum and the cap
-- @pass SHEET_LIFT         Command lifts the crew's answer, not her part: crew_pct x 100 is the parts' sum x the lift; Hospitality is the company's number for every seated captain
-- @pass SHEET_LEVELS       three tracks, three different company levels: each stat reads its own track, capped by the company's; no xp row reads null; the level is served ashore
-- @pass SHEET_BLANKS       ashore: parts null; seated and not hers: 0 and no line; combat off: ship parts null, fleet parts numbers; skills off: no Hospitality; nothing raises
-- @pass SHEET_DARK         crew_bite off: the job trait alone, and the parts still add up to crew_pct; levels_bite off: parts without a level, the level still served
-- @pass SHEET_FIGHT_BYTES  30 seeded fights are byte for byte the same before and after every captain's sheet is read; the same fights DO change when the Gunners are taken from the crew (the comparison can fail)
-- @pass SHEET_READ_ONLY    the read is STABLE; no tuple is written anywhere by reading nine sheets, and no event
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create temp table sheets_44 (scene text not null, code text not null, sheet jsonb);
create temp table fights_44 (set text not null, raider numeric not null, day int not null, result jsonb not null);

create function pg_temp.read_44(p_scene text, p_codes text[]) returns void language plpgsql as $f$
begin
  delete from pg_temp.sheets_44 where scene = p_scene;
  insert into pg_temp.sheets_44 select p_scene, c, world.captain_stats(c) from unnest(p_codes) c;
end $f$;

-- every part of every sheet of a scene, with the hull its captain sits on
create function pg_temp.parts_44(p_scene text, p_player uuid)
returns table (code text, ship uuid, seated boolean, stat text, track text, level int, effect text, pct numeric, line text)
language sql as $f$
  select h.code, cs.ship_id, (h.sheet ->> 'seated')::boolean, s ->> 'stat', s ->> 'track', (s ->> 'level')::int, p ->> 'effect', (p ->> 'pct')::numeric, p ->> 'line'
    from pg_temp.sheets_44 h
    join public.officers o on o.code = h.code
    join public.player_officers po on po.officer_id = o.id and po.player_id = p_player
    left join public.captain_seats cs on cs.player_officer_id = po.id
   cross join lateral jsonb_array_elements(h.sheet -> 'stats') s
   cross join lateral jsonb_array_elements(s -> 'parts') p
   where h.scene = p_scene and h.sheet is not null
$f$;

-- worked out here, from the tables: a trait's value = greatest(base, the grade's floor once promoted) x (1 + pct per level x (level - 1)) x the cabin's rate
create function pg_temp.worked_44(p_code text, p_trait text, p_level int, p_rate numeric, p_floor_grade text default null) returns numeric language sql stable as $f$
  select greatest(ct.base_pct, coalesce((select g.floor_pct from public.captain_grades g where g.code = p_floor_grade), 0))
         * (1 + public.wc_num('captain_level_pct_per_level') / 100 * (p_level - 1)) * p_rate
    from public.captain_traits ct join public.officers o on o.id = ct.officer_id where o.code = p_code and ct.trait = p_trait
$f$;

-- the gap between the parts and crew_pct, over every effect of the five stats, on the fleet and on each hull: the biggest, how many effects had a part above 0, and which was worst
create function pg_temp.gaps_44(p_scene text, p_player uuid, p_fleet uuid, p_ships uuid[]) returns jsonb language plpgsql as $f$
declare
  e record;
  s uuid;
  v_parts numeric;
  v_crew  numeric;
  v_gap   numeric := 0;
  v_live  int := 0;
  v_worst text := '';
begin
  for e in select ce.code, ce.scope from public.crew_effects ce
            where ce.code in ('accuracy', 'reach', 'attack', 'speed', 'storm', 'supplies', 'hold', 'spread', 'crew_saved', 'homesick_relief') order by ce.ord loop
    for s in select x from unnest(case when e.scope = 'ship' then p_ships else array[null::uuid] end) x loop
      select coalesce(sum(p.pct), 0) into v_parts from pg_temp.parts_44(p_scene, p_player) p where p.effect = e.code and p.pct is not null and (s is null or p.ship = s);
      v_crew := public.crew_pct(p_fleet, s, e.code) * 100;
      if v_parts > 0 or v_crew > 0 then v_live := v_live + 1; end if;
      if abs(v_parts - v_crew) > v_gap then
        v_gap := abs(v_parts - v_crew);
        v_worst := e.code || '/' || coalesce(s::text, 'fleet') || ': parts ' || v_parts || ' crew ' || v_crew;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('gap', v_gap, 'live', v_live, 'worst', v_worst);
end $f$;

do $p$
declare
  c_uid1  constant uuid := '00000000-0344-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0344-4000-8000-000000000002';
  c_seed  constant uuid := '00000000-0344-4000-8000-0000000000f1';
  -- the cast, by officer code (data/officers.json; kits read below, never assumed)
  c_codes constant text[] := array['PIRIREIS', 'YIJANGSON', 'ELCANO', 'TURGUT', 'TARTAGLIA', 'COENQM', 'WELSER', 'GARCIAORTA', 'MURAKAMI'];
  v_p     uuid;
  v_p2    uuid;
  v_fleet uuid;
  v_s1    uuid;   -- the navire: seats 1 captain, 2 trading, 3 exploration, 4 combat, 5 trading
  v_s2    uuid;   -- the barca:  seats 1 captain, 2 trading, 3 exploration
  v_voy   uuid;
  v_r     jsonb;
  v_x     jsonb;
  v_g     jsonb;
  v_n     numeric;
  v_m     numeric;
  v_i     int;
  v_c     text;
  v_po    uuid;
  v_t     text;
  v_ev0   bigint;
  v_w0    bigint;
  v_w1    bigint;
  v_digest0 text;
  v_digest1 text;
  v_cnt   int;
  v_hit   int;
  v_denied boolean := false;
  v_err   text;
  v_all   text[] := c_codes;
  v_seat  jsonb;
  v_lit   numeric;
  v_raw1  numeric;
  v_raw2  numeric;
begin
  -- ── THE PRECONDITIONS THIS PROOF OWNS ──
  update public.world_config set value = 'true'::jsonb  where key in ('levels_bite', 'crew_bite', 'combat_bite', 'skills_bite');
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  if (select count(*) from public.world_config where key in ('levels_bite', 'crew_bite', 'combat_bite', 'skills_bite', 'economy_closed')) <> 5 then
    raise exception 'PROOF 44 FAIL: a switch the proof sets has no world_config row';
  end if;

  -- ── THE PROBE HOUSE, ITS TWO HULLS, ITS COMPANY'S PROGRESS ──
  v_p  := public.new_house(c_uid1, 'Casa da Folha 0344', 'PRT', 'LIS', 'Folha', 'navire', 'Folha', 400000);
  v_p2 := public.new_house(c_uid2, 'Casa do Vizinho 0344', 'PRT', 'LIS');
  select f.id into v_fleet from public.fleets f where f.player_id = v_p;
  select s.id into v_s1 from public.ships s where s.fleet_id = v_fleet;
  v_s2 := public.commission_ship(v_p, v_fleet, 'barca', 'Segunda', false, true);
  if v_fleet is null or v_s1 is null or v_s2 is null then
    raise exception 'PROOF 44 FAIL: the probe house has no fleet or no two hulls';
  end if;
  if (select string_agg(public.cabin_focus(c.code, n), ',' order by n) from public.ships s join public.ship_classes c on c.id = s.class_id, generate_series(1, 5) n where s.id = v_s1) <> 'captain,trading,exploration,combat,trading'
     or (select string_agg(public.cabin_focus(c.code, n), ',' order by n) from public.ships s join public.ship_classes c on c.id = s.class_id, generate_series(1, 3) n where s.id = v_s2) <> 'captain,trading,exploration' then
    raise exception 'PROOF 44 FAIL: the hulls'' cabins are not the ones this proof seats for (navire: captain,trading,exploration,combat,trading; barca: captain,trading,exploration)';
  end if;

  -- the company's three tracks, made different on purpose: exploration 4, trading 3, combat 2
  v_voy := gen_random_uuid();
  insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id, created_at)
  select v_voy, v_fleet, v_p, '[]', 100, '{}', now() - interval '3 days', now() - interval '2 days', 'ARRIVED', f.port_id, f.port_id, now() - interval '3 days' from public.fleets f where f.id = v_fleet;
  insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at) values
    (v_voy, 1, 'PIRATES', jsonb_build_object('outcome', 'DRIVEN_OFF'), now()),
    (v_voy, 2, 'PIRATES', jsonb_build_object('outcome', 'DRIVEN_OFF'), now());
  perform public.emit_event(v_p, 'VOYAGE_REPORT', jsonb_build_object('to', 'LIS', 'total_nm', 30000, 'voyage_id', v_voy));
  perform public.credit(v_p, 'PROBE_44', 75000, public.emit_event(v_p, 'BOUGHT', '{}'::jsonb));
  v_g := public.player_progress(v_p);
  if (v_g -> 'exploration' ->> 'level')::int <> 4 or (v_g -> 'trading' ->> 'level')::int <> 3 or (v_g -> 'combat' ->> 'level')::int <> 2 then
    raise exception 'PROOF 44 FAIL: the company is not exploration 4, trading 3, combat 2: %', v_g;
  end if;

  -- ── THE CAST: signed ashore, then seated one by one (the doors the game uses) ──
  foreach v_c in array c_codes loop
    v_r := public.sign_officer(v_p, v_c, null);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception 'PROOF 44 FAIL: %''s signing was refused: %', v_c, v_r;
    end if;
  end loop;
  for v_seat in select * from jsonb_array_elements('[["PIRIREIS",1,1],["YIJANGSON",1,2],["ELCANO",1,3],["TURGUT",1,4],["TARTAGLIA",1,5],["COENQM",2,1],["WELSER",2,2],["GARCIAORTA",2,3]]'::jsonb) loop
    v_r := public.seat_captain_for(v_p, v_seat ->> 0, case when (v_seat ->> 1)::int = 1 then v_s1 else v_s2 end, (v_seat ->> 2)::int);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception 'PROOF 44 FAIL: could not seat %: %', v_seat, v_r;
    end if;
  end loop;
  -- what each uses (every one knows all ten: S, or A / B / C with enough known; the tool refuses a trait she does not)
  for v_seat in select * from jsonb_array_elements('[["PIRIREIS",["NAVIGATOR"]],["YIJANGSON",["GUNNER"]],["ELCANO",["NAVIGATOR","PILOT","PROVISIONER"]],["TURGUT",["BOARDER","GUNNER"]],["TARTAGLIA",["GUNNER"]],["COENQM",["QUARTERMASTER","GUNNER"]],["WELSER",["PURSER","NAVIGATOR"]],["GARCIAORTA",["SURGEON"]],["MURAKAMI",["BOARDER"]]]'::jsonb) loop
    v_r := public.captain_traits_set_for(v_p, v_seat ->> 0, array(select jsonb_array_elements_text(v_seat -> 1)));
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception 'PROOF 44 FAIL: could not set the traits %: %', v_seat, v_r;
    end if;
  end loop;
  -- TARTAGLIA was signed a C and stands a B: her grade's floor (5.5) lifts her Gunner (4.5) once she stands above her birth grade
  update public.captain_state set grade = 'B' where player_officer_id = (select po.id from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_p and o.code = 'TARTAGLIA');
  -- her own experience: well past the company's, except two (the company's cap, and no level at all)
  update public.captain_xp x set exploration = public.level_points(10), trading = public.level_points(10), combat = public.level_points(10)
   where x.player_officer_id in (select po.id from public.player_officers po where po.player_id = v_p);
  update public.captain_xp x set exploration = public.level_points(2)
   where x.player_officer_id = (select po.id from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_p and o.code = 'PIRIREIS');
  update public.captain_xp x set combat = 0
   where x.player_officer_id = (select po.id from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_p and o.code = 'TARTAGLIA');
  -- the ninth, MURAKAMI, stays ashore. A tenth signing with no xp row would be a hand-built one; it is made below.
  perform cmd.assume_identity(c_uid1);
  v_ev0 := (select count(*) from public.events e where e.player_id = v_p);

  -- ══ SHEET_DOOR ══
  set local role authenticated;
  v_r := world.captain_stats('ELCANO');
  reset role;
  set local role anon;
  begin
    perform world.captain_stats('ELCANO');
  exception when insufficient_privilege then v_denied := true;
  end;
  reset role;
  if v_denied is not true or v_r is null or (v_r ->> 'code') <> 'ELCANO' or (v_r ->> 'seated')::boolean is not true then
    raise exception 'PROOF 44 FAIL: the door: anon refused %, authenticated read %', v_denied, v_r;
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'world.captain_stats(text)'::regprocedure) <> 's' then
    raise exception 'PROOF 44 FAIL: the read is not STABLE';
  end if;
  if world.captain_stats('  elcano ') is distinct from v_r then
    raise exception 'PROOF 44 FAIL: the code is not read as the verbs read it (upper-cased, trimmed)';
  end if;
  perform cmd.assume_identity(c_uid2);
  if world.captain_stats('ELCANO') is not null then
    raise exception 'PROOF 44 FAIL: a stranger read a captain she does not keep: %', world.captain_stats('ELCANO');
  end if;
  perform cmd.assume_identity('00000000-0344-4000-8000-0000000000ff');
  if world.captain_stats('ELCANO') is not null then
    raise exception 'PROOF 44 FAIL: a caller with no company read a sheet';
  end if;
  perform cmd.assume_identity(c_uid1);
  if world.captain_stats('NOBODY') is not null or world.captain_stats('') is not null or world.captain_stats(null) is not null then
    raise exception 'PROOF 44 FAIL: a code nobody keeps did not read null';
  end if;
  raise notice 'PASS: SHEET_DOOR — authenticated reads, anon is refused, a stranger, a signed-out caller and a code nobody keeps read null, the code is trimmed and upper-cased';

  -- ══ SHEET_SHAPE ══
  perform pg_temp.read_44('lit', v_all);
  if (select count(*) from pg_temp.sheets_44 where scene = 'lit' and sheet is not null) <> 9 then
    raise exception 'PROOF 44 FAIL: not every captain read a sheet';
  end if;
  for v_c in select unnest(v_all) loop
    v_r := (select sheet from pg_temp.sheets_44 where scene = 'lit' and code = v_c);
    if (select string_agg(s ->> 'stat', ',' order by o) from jsonb_array_elements(v_r -> 'stats') with ordinality x(s, o)) <> 'gunnery,boarding,seamanship,trade,care'
       or (select string_agg(coalesce(s ->> 'track', '-'), ',' order by o) from jsonb_array_elements(v_r -> 'stats') with ordinality x(s, o)) <> 'combat,combat,exploration,trading,-'
       or (select string_agg(q ->> 'effect', ',' order by s_o, q_o) from jsonb_array_elements(v_r -> 'stats') with ordinality x(s, s_o), jsonb_array_elements(s -> 'parts') with ordinality y(q, q_o))
          <> 'accuracy,reach,attack,speed,storm,supplies,hold,spread,crew_saved,homesick_relief,hospitality' then
      raise exception 'PROOF 44 FAIL: the sheet of % is not the five stats, their tracks and their effects in order: %', v_c, v_r;
    end if;
  end loop;
  -- ELCANO is a Navigator in an exploration cabin at exploration 4: speed 9 x 1.06; her line is the server's words over it
  v_x := (select p from jsonb_array_elements((select sheet from pg_temp.sheets_44 where scene = 'lit' and code = 'ELCANO') -> 'stats' -> 2 -> 'parts') p where p ->> 'effect' = 'speed');
  if (v_x ->> 'line') <> '+9.5% speed' then
    raise exception 'PROOF 44 FAIL: ELCANO''s speed line reads %, not "+9.5%% speed"', v_x;
  end if;
  v_x := (select p from jsonb_array_elements((select sheet from pg_temp.sheets_44 where scene = 'lit' and code = 'ELCANO') -> 'stats' -> 0 -> 'parts') p where p ->> 'effect' = 'accuracy');
  if (v_x ->> 'pct')::numeric <> 0 or (v_x ->> 'line') is not null or (v_x -> 'line') <> 'null'::jsonb then
    raise exception 'PROOF 44 FAIL: a part that is not hers carries a line or a number: %', v_x;
  end if;
  raise notice 'PASS: SHEET_SHAPE — five stats in order, their tracks, eleven parts in order on every sheet; "+9.5%% speed" is the server''s words, and a part that is not hers has no line';

  -- ══ SHEET_EQUALS_CREW ══
  v_g := pg_temp.gaps_44('lit', v_p, v_fleet, array[v_s1, v_s2]);
  if (v_g ->> 'gap')::numeric > 0.000000001 or (v_g ->> 'live')::int < 10 then
    raise exception 'PROOF 44 FAIL: the parts do not add up to crew_pct (or the crew is too thin to say): %', v_g;
  end if;
  -- a captain alone in her crew reads crew_pct ITSELF: hold has COENQM alone, spread WELSER alone, crew_saved and homesick_relief GARCIAORTA alone, attack TURGUT alone on the navire, accuracy COENQM alone on the barca
  for v_seat in select * from jsonb_array_elements('[["COENQM","hold",null],["WELSER","spread",null],["GARCIAORTA","crew_saved",null],["GARCIAORTA","homesick_relief",null],["TURGUT","attack","s1"],["COENQM","accuracy","s2"]]'::jsonb) loop
    v_n := (select p.pct from pg_temp.parts_44('lit', v_p) p where p.code = v_seat ->> 0 and p.effect = v_seat ->> 1);
    v_m := public.crew_pct(v_fleet, case v_seat ->> 2 when 's1' then v_s1 when 's2' then v_s2 end, v_seat ->> 1) * 100;
    if v_n is distinct from v_m or v_m <= 0 then
      raise exception 'PROOF 44 FAIL: % alone in her crew reads % for %, crew_pct x 100 reads %', v_seat ->> 0, v_n, v_seat ->> 1, v_m;
    end if;
  end loop;
  raise notice 'PASS: SHEET_EQUALS_CREW — % effects, fleet and each hull: below the cap and with no Command the parts add up to crew_pct x 100 within %, and six captains alone in a crew read crew_pct itself', v_g ->> 'live', (v_g ->> 'gap');

  -- ══ SHEET_AMOUNT ══ (levels in force: exploration 4, trading 3, combat 2; PIRIREIS'S exploration is her own 2; TARTAGLIA's combat is her own 1)
  for v_seat in select * from jsonb_array_elements($j$[
      ["ELCANO",    "speed",           "NAVIGATOR",     4, 1.0, null],
      ["ELCANO",    "storm",           "PILOT",         4, 1.0, null],
      ["ELCANO",    "supplies",        "PROVISIONER",   4, 1.0, null],
      ["PIRIREIS",  "speed",           "NAVIGATOR",     2, 1.0, null],
      ["COENQM",    "hold",            "QUARTERMASTER", 3, 1.0, null],
      ["WELSER",    "spread",          "PURSER",        3, 1.0, null],
      ["GARCIAORTA","crew_saved",      "SURGEON",       4, 1.0, null],
      ["GARCIAORTA","homesick_relief", "SURGEON",       4, 1.0, null],
      ["TURGUT",    "attack",          "BOARDER",       2, 1.0, null],
      ["TURGUT",    "accuracy",        "GUNNER",        2, 1.0, null],
      ["TURGUT",    "reach",           "GUNNER",        2, 1.0, null],
      ["YIJANGSON", "accuracy",        "GUNNER",        2, 0.5, null],
      ["YIJANGSON", "reach",           "GUNNER",        2, 0.5, null],
      ["TARTAGLIA", "accuracy",        "GUNNER",        1, 0.5, "B"],
      ["COENQM",    "accuracy",        "GUNNER",        2, 1.0, null],
      ["WELSER",    "speed",           "NAVIGATOR",     4, 0.5, null]
    ]$j$::jsonb) loop
    v_n := pg_temp.worked_44(v_seat ->> 0, v_seat ->> 2, (v_seat ->> 3)::int, (v_seat ->> 4)::numeric, v_seat ->> 5);
    -- the term public.crew_terms gives for her seat, the sheet's part, and the figure worked out here from the tables: one number three ways
    select sum(t.value_pct) into v_m from public.crew_terms(v_fleet) t
     where t.effect = v_seat ->> 1 and t.player_officer_id = (select po.id from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_p and o.code = v_seat ->> 0);
    v_lit := (select p.pct from pg_temp.parts_44('lit', v_p) p where p.code = v_seat ->> 0 and p.effect = v_seat ->> 1);
    if v_m is distinct from v_n or v_lit is distinct from v_n or v_n is null or v_n <= 0 then
      raise exception 'PROOF 44 FAIL: % %: crew_terms gives %, the sheet %, worked out from the tables % (base x level x cabin rate, the grade''s floor once promoted)', v_seat ->> 0, v_seat ->> 1, v_m, v_lit, v_n;
    end if;
    v_cnt := coalesce(v_cnt, 0) + 1;
  end loop;
  -- ELCANO's speed, said in numbers: 9 x (1 + 0.02 x 3) = 9.54; the crew's whole speed is hers, PIRIREIS's 8.5 x 1.02 = 8.67 and WELSER's, on the other hull and off her cabin's focus, 5.4 x 1.06 x 0.5 = 2.862: 21.072
  if round(pg_temp.worked_44('ELCANO', 'NAVIGATOR', 4, 1.0), 6) <> 9.54 or round(public.crew_pct(v_fleet, null, 'speed') * 100, 6) <> 21.072 then
    raise exception 'PROOF 44 FAIL: ELCANO speed worked out as %, the crew''s as % (9.54 and 21.072 expected)', pg_temp.worked_44('ELCANO', 'NAVIGATOR', 4, 1.0), public.crew_pct(v_fleet, null, 'speed') * 100;
  end if;
  -- TARTAGLIA: the grade's floor lifted her Gunner above its base, and her level 1 and off-focus cabin did the rest
  if pg_temp.worked_44('TARTAGLIA', 'GUNNER', 1, 0.5, 'B') <= pg_temp.worked_44('TARTAGLIA', 'GUNNER', 1, 0.5) then
    raise exception 'PROOF 44 FAIL: the probe promotion does not lift TARTAGLIA above her base';
  end if;
  raise notice 'PASS: SHEET_AMOUNT — % terms worked out from the tables are the term crew_terms gives and the part the sheet serves; speed 9.54 + 8.67 + 2.862 = 21.072 across two hulls; a promoted C stands on her B floor', v_cnt;

  -- ══ SHEET_CAP ══ (a cap of 8 on speed: ELCANO's 9.54 and PIRIREIS's 8.67 are each above it, and the crew is given 8)
  update public.crew_effects set cap_pct = 8 where code = 'speed';
  perform pg_temp.read_44('cap', v_all);
  v_n := (select p.pct from pg_temp.parts_44('cap', v_p) p where p.code = 'ELCANO' and p.effect = 'speed');
  v_m := (select p.pct from pg_temp.parts_44('cap', v_p) p where p.code = 'PIRIREIS' and p.effect = 'speed');
  v_lit := (select p.pct from pg_temp.parts_44('cap', v_p) p where p.code = 'WELSER' and p.effect = 'speed');
  if round(v_n, 6) <> 9.54 or round(v_m, 6) <> 8.67 or round(v_lit, 6) <> 2.862
     or abs(public.crew_pct(v_fleet, null, 'speed') * 100 - 8) > 0.000000001
     or abs(public.crew_pct(v_fleet, null, 'speed') * 100 - least(v_n + v_m + v_lit, 8)) > 0.000000001 then
    raise exception 'PROOF 44 FAIL: a cap of 8 is the crew''s: the parts should stay 9.54, 8.67 and 2.862 and crew_pct x 100 be least(their sum, 8) = 8; they read %, %, % and the crew %', v_n, v_m, v_lit, public.crew_pct(v_fleet, null, 'speed') * 100;
  end if;
  update public.crew_effects set cap_pct = 25 where code = 'speed';
  raise notice 'PASS: SHEET_CAP — a cap of 8 on speed: the parts stay ELCANO %, PIRIREIS %, WELSER %, and the crew is given 8 = least(%, 8)', round(v_n, 4), round(v_m, 4), round(v_lit, 4), round(v_n + v_m + v_lit, 4);

  -- ══ SHEET_LIFT ══ (Command level 5 lifts the crew by 10 %; Hospitality 2 is 4 points)
  insert into public.player_skills (player_id, skill_id, level)
  select v_p, s.id, x.l from public.skills s join (values ('COMMAND', 5), ('HOSPITALITY', 2)) x(code, l) on x.code = s.code;
  if world.skill_pct(v_p, null, 'officer_bonus') <> 10 or world.skill_pct(v_p, null, 'homesick') <> 4 then
    raise exception 'PROOF 44 FAIL: Command 5 / Hospitality 2 do not read 10 / 4: % / %', world.skill_pct(v_p, null, 'officer_bonus'), world.skill_pct(v_p, null, 'homesick');
  end if;
  perform pg_temp.read_44('lift', v_all);
  v_n := (select p.pct from pg_temp.parts_44('lift', v_p) p where p.code = 'ELCANO' and p.effect = 'speed');
  v_m := (select sum(p.pct) from pg_temp.parts_44('lift', v_p) p where p.effect = 'speed');
  if abs(v_n - 9.54) > 0.000000001 or abs(v_m - 21.072) > 0.000000001 or abs(public.crew_pct(v_fleet, null, 'speed') * 100 - 21.072 * 1.10) > 0.000000001 then
    raise exception 'PROOF 44 FAIL: Command lifts the crew by 10 %%, not her part: ELCANO should still read 9.54 (of 21.072) and crew_pct x 100 be 21.072 x 1.10; she reads %, the parts add up to %, the crew %', v_n, v_m, public.crew_pct(v_fleet, null, 'speed') * 100;
  end if;
  -- Hospitality: the company's, so every SEATED captain reads 4 points and a captain ashore reads none
  for v_c in select unnest(v_all) loop
    v_n := (select (q ->> 'pct')::numeric from jsonb_array_elements((select sheet from pg_temp.sheets_44 where scene = 'lift' and code = v_c) -> 'stats' -> 4 -> 'parts') q where q ->> 'effect' = 'hospitality');
    if (v_c = 'MURAKAMI' and v_n is not null) or (v_c <> 'MURAKAMI' and v_n is distinct from 4) then
      raise exception 'PROOF 44 FAIL: % reads Hospitality % (4 for a seated captain, blank ashore)', v_c, v_n;
    end if;
  end loop;
  v_x := (select q from jsonb_array_elements((select sheet from pg_temp.sheets_44 where scene = 'lift' and code = 'ELCANO') -> 'stats' -> 4 -> 'parts') q where q ->> 'effect' = 'hospitality');
  if (v_x ->> 'line') <> '−4 points of homesickness' then
    raise exception 'PROOF 44 FAIL: Hospitality''s line is %', v_x;
  end if;
  raise notice 'PASS: SHEET_LIFT — Command 5 lifts the crew 21.072 to %, and ELCANO still reads her own 9.54; Hospitality 2 is 4 points on every seated sheet and blank ashore', round(public.crew_pct(v_fleet, null, 'speed') * 100, 4);
  delete from public.player_skills where player_id = v_p;

  -- ══ SHEET_LEVELS ══
  perform pg_temp.read_44('lit', v_all);
  for v_seat in select * from jsonb_array_elements('[["ELCANO",4,3,2],["PIRIREIS",2,3,2],["TARTAGLIA",4,3,1],["MURAKAMI",4,3,2]]'::jsonb) loop
    -- [code, exploration, trading, combat]: the company's levels, except PIRIREIS'S own exploration 2 and TARTAGLIA'S own combat 1; MURAKAMI sits ashore and reads the company's three all the same
    select po.id into v_po from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_p and o.code = v_seat ->> 0;
    if (select count(distinct x.level) from pg_temp.parts_44('lit', v_p) x where x.code = v_seat ->> 0 and x.stat in ('gunnery', 'boarding')) <> 1
       or (select max(x.level) from pg_temp.parts_44('lit', v_p) x where x.code = v_seat ->> 0 and x.stat = 'gunnery') is distinct from (v_seat ->> 3)::int
       or (select max(x.level) from pg_temp.parts_44('lit', v_p) x where x.code = v_seat ->> 0 and x.stat = 'boarding') is distinct from (v_seat ->> 3)::int
       or (select max(x.level) from pg_temp.parts_44('lit', v_p) x where x.code = v_seat ->> 0 and x.stat = 'seamanship') is distinct from (v_seat ->> 1)::int
       or (select max(x.level) from pg_temp.parts_44('lit', v_p) x where x.code = v_seat ->> 0 and x.stat = 'trade') is distinct from (v_seat ->> 2)::int
       or public.captain_level(v_po, 'combat') <> (v_seat ->> 3)::int or public.captain_level(v_po, 'exploration') <> (v_seat ->> 1)::int or public.captain_level(v_po, 'trading') <> (v_seat ->> 2)::int then
      raise exception 'PROOF 44 FAIL: % reads levels that are not exploration %, trading %, combat % through her three tracks', v_seat ->> 0, v_seat ->> 1, v_seat ->> 2, v_seat ->> 3;
    end if;
  end loop;
  if exists (select 1 from pg_temp.parts_44('lit', v_p) x where x.stat = 'care' and x.level is not null) then
    raise exception 'PROOF 44 FAIL: Care carries a level';
  end if;
  -- no xp row: a signing hand-made without one reads level null, never a made-up 1, and still raises nothing
  v_r := public.sign_officer(v_p, 'MUGPURSER', null);
  select po.id into v_po from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_p and o.code = 'MUGPURSER';
  delete from public.captain_xp where player_officer_id = v_po;
  v_r := world.captain_stats('MUGPURSER');
  if v_r is null or exists (select 1 from jsonb_array_elements(v_r -> 'stats') s where (s ->> 'level') is not null) or (v_r ->> 'seated')::boolean is not false then
    raise exception 'PROOF 44 FAIL: a signing with no xp row does not read a blank level: %', v_r;
  end if;
  raise notice 'PASS: SHEET_LEVELS — exploration 4, trading 3, combat 2 read through the right stats, capped by the company where her own is higher, her own where it is lower, served ashore; no xp row reads null';

  -- ══ SHEET_BLANKS ══
  -- ashore (MURAKAMI): every part blank, her levels hers
  if exists (select 1 from pg_temp.parts_44('lit', v_p) x where x.code = 'MURAKAMI' and x.pct is not null) or (select (sheet ->> 'seated')::boolean from pg_temp.sheets_44 where scene = 'lit' and code = 'MURAKAMI') is not false
     or (select count(*) from pg_temp.parts_44('lit', v_p) x where x.code = 'MURAKAMI' and x.stat <> 'care' and x.level is not null) <> 8 then
    raise exception 'PROOF 44 FAIL: a captain ashore does not read blank parts with her levels';
  end if;
  -- seated and not hers: 0 and no line (a Navigator's Gunnery, a Quartermaster's speed)
  if exists (select 1 from pg_temp.parts_44('lit', v_p) x where x.pct = 0 and x.line is not null)
     or exists (select 1 from pg_temp.parts_44('lit', v_p) x where x.pct > 0 and x.line is null)
     or (select x.pct from pg_temp.parts_44('lit', v_p) x where x.code = 'COENQM' and x.effect = 'speed') is distinct from 0
     or (select x.pct from pg_temp.parts_44('lit', v_p) x where x.code = 'PIRIREIS' and x.effect = 'accuracy') is distinct from 0 then
    raise exception 'PROOF 44 FAIL: a role that is not hers is not a bare 0 with no line, or a part above 0 has none';
  end if;
  -- combat off: the ship parts go blank, the fleet parts stay numbers, and nothing raises
  update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
  perform pg_temp.read_44('nocombat', v_all);
  if exists (select 1 from pg_temp.parts_44('nocombat', v_p) x where x.effect in ('accuracy', 'reach', 'attack') and x.seated and x.pct is not null)
     or not exists (select 1 from pg_temp.parts_44('nocombat', v_p) x where x.effect in ('accuracy', 'reach', 'attack'))
     or (select x.pct from pg_temp.parts_44('nocombat', v_p) x where x.code = 'ELCANO' and x.effect = 'speed') is distinct from (select x.pct from pg_temp.parts_44('lit', v_p) x where x.code = 'ELCANO' and x.effect = 'speed') then
    raise exception 'PROOF 44 FAIL: combat off: ship parts are not blank or fleet parts moved';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
  -- skills off: no Hospitality, no lift, and no error
  update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
  insert into public.player_skills (player_id, skill_id, level) select v_p, s.id, 2 from public.skills s where s.code = 'HOSPITALITY';
  perform pg_temp.read_44('noskills', v_all);
  if exists (select 1 from pg_temp.parts_44('noskills', v_p) x where x.effect = 'hospitality' and x.pct is not null) then
    raise exception 'PROOF 44 FAIL: skills off, a sheet still reads Hospitality';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
  delete from public.player_skills where player_id = v_p;
  raise notice 'PASS: SHEET_BLANKS — ashore blank with her levels; a role not hers is 0 with no line; combat off blanks the ship parts and leaves the fleet parts; skills off blanks Hospitality; nothing raised';

  -- ══ SHEET_DARK ══
  -- crew_bite off: each captain's job trait alone, live effects only (public.crew_terms' dark arm) — and the parts still add up to what crew_pct says
  update public.world_config set value = 'false'::jsonb where key = 'crew_bite';
  perform pg_temp.read_44('darkcrew', v_all);
  v_g := pg_temp.gaps_44('darkcrew', v_p, v_fleet, array[v_s1, v_s2]);
  if (v_g ->> 'gap')::numeric > 0.000000001
     or (select x.pct from pg_temp.parts_44('darkcrew', v_p) x where x.code = 'ELCANO' and x.effect = 'storm') is distinct from 0
     or (select x.pct from pg_temp.parts_44('darkcrew', v_p) x where x.code = 'ELCANO' and x.effect = 'speed') is distinct from (select x.pct from pg_temp.parts_44('lit', v_p) x where x.code = 'ELCANO' and x.effect = 'speed') then
    raise exception 'PROOF 44 FAIL: crew_bite off: the job trait alone should be left (storm 0, speed unmoved by the cabin it fills at 100 %%): %', v_g;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
  -- levels_bite off: a level does not bite, so a part loses it — and the level is still served
  update public.world_config set value = 'false'::jsonb where key = 'levels_bite';
  perform pg_temp.read_44('darklevels', v_all);
  v_g := pg_temp.gaps_44('darklevels', v_p, v_fleet, array[v_s1, v_s2]);
  v_n := (select p.pct from pg_temp.parts_44('darklevels', v_p) p where p.code = 'ELCANO' and p.effect = 'speed');
  if (v_g ->> 'gap')::numeric > 0.000000001 or abs(v_n - 9) > 0.000000001
     or (select max(x.level) from pg_temp.parts_44('darklevels', v_p) x where x.code = 'ELCANO' and x.stat = 'seamanship') is distinct from 4 then
    -- the company's progress is read through player_progress, whose combat track is dark with levels_bite: so the level served is captain_level's own, whatever it reads dark
    raise exception 'PROOF 44 FAIL: levels_bite off: ELCANO''s speed should be her base 9 with her level still served: % %', v_n, v_g;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
  raise notice 'PASS: SHEET_DARK — crew_bite off leaves the job trait alone and the parts still add up to crew_pct; levels_bite off takes the level out of the part (9, not 9.54) and the level is still served';

  -- ══ SHEET_FIGHT_BYTES ══
  -- The same seeded fights (the seed, the day, the fleet, the raiders' strength: voyage.fight reads every captain through crew_pct) are fought before the sheets are read and after, and kept WHOLE: the full result, rounds and all.
  perform pg_temp.read_44('lit', v_all);   -- the scene is the lit world again
  insert into pg_temp.fights_44 select 'before', r, d, voyage.fight(c_seed, d, v_fleet, r) from unnest(array[16, 40]::numeric[]) r, generate_series(1, 15) d;
  v_w0 := (select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) from pg_stat_xact_user_tables);
  select string_agg(c.relname || '=' || (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from public.%I', c.relname), false, true, '')))[1]::text, ',' order by c.relname) into v_digest0
    from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r';
  v_ev0 := (select count(*) from public.events e where e.player_id = v_p);
  for v_c in select unnest(v_all) loop
    perform world.captain_stats(v_c);
    perform world.captain_stats(v_c);   -- twice: a second read must find what the first left
  end loop;
  v_w1 := (select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) from pg_stat_xact_user_tables);
  select string_agg(c.relname || '=' || (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from public.%I', c.relname), false, true, '')))[1]::text, ',' order by c.relname) into v_digest1
    from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r';
  insert into pg_temp.fights_44 select 'after', r, d, voyage.fight(c_seed, d, v_fleet, r) from unnest(array[16, 40]::numeric[]) r, generate_series(1, 15) d;
  select count(*), count(*) filter (where b.result::text is distinct from a.result::text), count(*) filter (where a.result ->> 'outcome' <> 'EVADED')
    into v_cnt, v_i, v_hit
    from pg_temp.fights_44 a join pg_temp.fights_44 b on b.set = 'after' and b.raider = a.raider and b.day = a.day where a.set = 'before';
  if v_cnt <> 30 or v_hit < 10 then
    raise exception 'PROOF 44 FAIL: only % of % fights are fought out (a fight that is never fought proves nothing)', v_hit, v_cnt;
  end if;
  if v_i <> 0 then
    raise exception 'PROOF 44 FAIL: % of % fights changed after the sheets were read', v_i, v_cnt;
  end if;
  -- the comparison can fail: take the Gunners from the crew and the same fights are not the same
  delete from public.captain_active where trait = 'GUNNER' and player_officer_id in (select po.id from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_p and o.code in ('TURGUT', 'YIJANGSON', 'TARTAGLIA', 'COENQM'));
  insert into pg_temp.fights_44 select 'nogunners', r, d, voyage.fight(c_seed, d, v_fleet, r) from unnest(array[16, 40]::numeric[]) r, generate_series(1, 15) d;
  if not exists (select 1 from pg_temp.fights_44 a join pg_temp.fights_44 b on b.set = 'nogunners' and b.raider = a.raider and b.day = a.day where a.set = 'before' and b.result::text is distinct from a.result::text) then
    raise exception 'PROOF 44 FAIL: taking every Gunner from the crew did not change a fight: the comparison cannot fail';
  end if;
  raise notice 'PASS: SHEET_FIGHT_BYTES — % seeded fights (% fought out) byte for byte the same after 18 reads of 9 sheets; the same fights differ when the Gunners go', v_cnt, v_hit;

  -- ══ SHEET_READ_ONLY ══
  if (select p.provolatile from pg_proc p where p.oid = 'world.captain_stats(text)'::regprocedure) <> 's'
     or v_w1 <> v_w0 or v_digest1 is distinct from v_digest0
     or (select count(*) from public.events e where e.player_id = v_p) <> v_ev0 then
    raise exception 'PROOF 44 FAIL: the read is not stable or it wrote: tuples % -> %, events %, tables equal %', v_w0, v_w1, (select count(*) from public.events e where e.player_id = v_p) - v_ev0, v_digest1 is not distinct from v_digest0;
  end if;
  raise notice 'PASS: SHEET_READ_ONLY — stable; 18 reads wrote no tuple (%), no event, and left every public table at its row count', v_w1 - v_w0;
end
$p$;
