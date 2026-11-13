-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 91 — A WALL SAYS WHAT IS SHORT  (migration 0396, owner rows 166 and 324)
--
--   The migration's self-assert reads the rule with typed figures and one probe company. Here the companies are real (the real founding door, the real
--   passage gate, the real leg judge), the switch is turned both ways, and each new key is held to the authority it copies. Everything rolls back with
--   proof.mjs's transaction; every switch this proof needs it writes here.
--
-- @pass WALL_SHORT       the real passage gate, lit: a barca company at title 1 is refused the Western Ocean with short_title and short_wave true; in a nau (wave 39) the same sea says short_title only; the six old figures and the sentence are the rule's as before
-- @pass WALL_HOME_WATERS  founding is refused nowhere, dark or lit: lit, a new company of Japan is founded at Sakai, her capital's sea and the seas of its rank that her barca holds are open to her at title 1 (the door and her read agree, and her read names her home sea), a sea of another rank still refuses her with her true title 1 in the figures; a country change moves her home with it at once
-- @pass WALL_CONDITIONS  her read: every zone is in a fleet's `seas` exactly when the one rule refuses that zone alone, with the rule's own figures; the nau's fleet has fewer closed seas than the barca's and none of them short of wave below 39; `port` is where she lies; `harbours` adds up to every harbour; nobody signed in reads no fleet and the same far powers
-- @pass WALL_ORDER       lit, the real order paths: cmd.preview and cmd.issue of SAIL LPA for the title-1 barca answer E_SEA_CLOSED with the rule's own figures (Macaronesia, title 2 asked, 1 held, short of title and not of wave); the catcher (cmd.refusal_caught) still keeps cmd.figures' shape (have, need, unit) and still drops every other: a leg's own figures, a PostgreSQL DETAIL, half the sea's shape, the sea's keys with the wrong types
-- @pass WALL_LEGS        lit, a leg from Lisbon to Honolulu is shut by its length with no harbours between and names the sea the gate refuses on; Porto names none; no leg names a sea while it has harbours between; dark, no leg names a sea and the other keys are the same text as lit
-- @pass WALL_WAY_HOME    lit, the way home (public.sea_floor): the same title-1 barca lying at Acapulco (a sea that asks title 8) may sail on in her own waters, is refused the open Pacific on her hull alone, with her own title and wave in the figures; her read does not call her own sea closed; back at Lisbon the wall is as before
-- @pass WALL_MAP         world.sea_zone_map decoded at every harbour's roadstead names the harbour's own sea (public.harbour_zone), and at three points of land names none; anon may not call it, a signed-in caller may; it is registered
-- @pass WALL_COST        the conditions read for a company of five fleets and the map, timed (printed, never judged)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_a constant uuid := '00000000-0396-4000-8000-0000000000a1';
  c_b constant uuid := '00000000-0396-4000-8000-0000000000b1';
  c_c constant uuid := '00000000-0396-4000-8000-0000000000c1';
  c_d constant uuid := '00000000-0396-4000-8000-0000000000d1';
  v_pa  uuid;
  v_pb  uuid;
  v_fa  uuid;
  v_fb  uuid;
  v_lis uuid := (select id from public.ports where code = 'LIS');
  v_hav uuid := (select id from public.ports where code = 'HAV');
  v_r   jsonb;
  v_r2  jsonb;
  v_ra  jsonb;
  v_rb  jsonb;
  v_map jsonb;
  v_n   int;
  v_bad text;
  v_t   timestamptz;
  v_ms1 numeric;
  v_ms2 numeric;
  i     int;
begin
  update public.world_config set value = 'false'::jsonb where key in ('sea_conditions_bite', 'pirates_joinable');

  -- two real companies of Portugal at Lisbon: A in a barca, B in a nau
  v_pa := public.new_house(c_a, 'Casa Muro A', 'PRT', 'LIS', 'Muro A', 'barca', 'Muro A', null, false);
  v_pb := public.new_house(c_b, 'Casa Muro B', 'PRT', 'LIS', 'Muro B', 'nau', 'Muro B', null, false);
  select id into v_fa from public.fleets where player_id = v_pa;
  select id into v_fb from public.fleets where player_id = v_pb;
  if public.title_level(v_pa) <> 1 or public.fleet_wave(v_fa) <> 12 or public.fleet_wave(v_fb) <> 39 then
    raise exception 'PROOF 91 FAIL: the two companies are not title 1 in a barca (12) and a nau (39): title %, waves % and %', public.title_level(v_pa), public.fleet_wave(v_fa), public.fleet_wave(v_fb);
  end if;

  -- ── WALL_SHORT ──
  if public.passage_gate(v_pa, v_fa, 100, v_hav, null) is not null then
    raise exception 'PROOF 91 FAIL: dark, the passage gate refuses a short leg to Havana';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  v_ra := public.passage_gate(v_pa, v_fa, 100, null, '[[38.0,-36.0],[36.0,-42.0]]'::jsonb);   -- a course inside the Western Ocean
  v_rb := public.passage_gate(v_pb, v_fb, 100, null, '[[38.0,-36.0],[36.0,-42.0]]'::jsonb);
  if (v_ra ->> 'code') is distinct from 'E_SEA_CLOSED' or (v_rb ->> 'code') is distinct from 'E_SEA_CLOSED'
     or (v_ra -> 'figures' -> 'short_title') <> 'true'::jsonb or (v_ra -> 'figures' -> 'short_wave') <> 'true'::jsonb
     or (v_rb -> 'figures' -> 'short_title') <> 'true'::jsonb or (v_rb -> 'figures' -> 'short_wave') <> 'false'::jsonb
     or (v_ra -> 'figures' ->> 'title')::int <> 1 or (v_ra -> 'figures' ->> 'wave')::numeric <> 12 or (v_rb -> 'figures' ->> 'wave')::numeric <> 39
     or (select count(*) from jsonb_object_keys(v_ra -> 'figures')) <> 8
     or (v_ra ->> 'sentence') <> format('%s asks title %s and wave resistance %s — you are title 1 and your fleet holds 12',
                                        v_ra -> 'figures' ->> 'zone_name', v_ra -> 'figures' ->> 'needs_title', v_ra -> 'figures' ->> 'needs_wave') then
    raise exception 'PROOF 91 FAIL: lit, the gate on a course into the ocean: barca % ; nau %', v_ra, v_rb;
  end if;
  raise notice 'PASS: WALL_SHORT — the gate refuses % to both: the barca is short of title and wave, the nau of title only; eight figures, the sentence unmoved', v_ra -> 'figures' ->> 'zone_name';

  -- ── WALL_HOME_WATERS ──
  declare
    v_pj   uuid;
    v_fj   uuid;
    v_home record;
    v_near uuid;
    v_lpa  uuid := (select id from public.ports where code = 'LPA');
    v_prt  uuid := (select id from public.nations where code = 'PRT');
    v_jpn  uuid := (select id from public.nations where code = 'JPN');
  begin
    update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
    perform cmd.assume_identity(c_c);
    v_r := cmd.found_house('Casa Muro Longe', 'JPN');
    if (v_r ->> 'ok') <> 'true' then
      raise exception 'PROOF 91 FAIL: dark, founding under Japan answered %', v_r;
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    perform cmd.assume_identity(c_d);
    v_r := cmd.found_house('Casa Muro Perto', 'JPN');
    if (v_r ->> 'ok') <> 'true' or (v_r ->> 'nation') <> 'JPN' then
      raise exception 'PROOF 91 FAIL: lit, founding under Japan answered % (founding is refused nowhere)', v_r;
    end if;
    v_pj := (v_r ->> 'player_id')::uuid;
    select f.id into v_fj from public.fleets f where f.player_id = v_pj;
    select z.code, z.title_min, z.wave_min, cap.id as port into v_home
      from public.nations n join public.ports cap on cap.code = n.capital_port_code
      join public.sea_leg_asks a on a.from_port = cap.id and a.to_port = cap.id join public.sea_zones z on z.code = a.zones[1]
     where n.code = 'JPN';
    -- a harbour in ANOTHER sea of her home's rank that her barca holds
    select p.id into v_near
      from public.ports p join public.sea_leg_asks a on a.from_port = p.id and a.to_port = p.id join public.sea_zones z on z.code = a.zones[1]
     where p.kind = 'HARBOUR' and z.title_min = v_home.title_min and z.code <> v_home.code and z.wave_min <= public.fleet_wave(v_fj)
     order by p.code limit 1;
    v_ra := world.sea_conditions();
    v_rb := public.sea_gate(v_pj, v_fj, v_lpa, null);
    if v_home.title_min <= 1 or public.title_level(v_pj) <> 1 or v_near is null
       or public.sea_gate(v_pj, v_fj, v_home.port, null) is not null or public.sea_gate(v_pj, v_fj, v_near, null) is not null
       or (v_ra -> 'home_sea' ->> 'code') is distinct from v_home.code or (v_ra -> 'fleets' -> 0 -> 'seas') ? v_home.code
       or exists (select 1 from public.sea_zones z where z.title_min = v_home.title_min and z.wave_min <= public.fleet_wave(v_fj) and (v_ra -> 'fleets' -> 0 -> 'seas') ? z.code)
       or v_rb is null or (v_rb -> 'figures' ->> 'title')::int <> 1 or (v_rb -> 'figures' -> 'short_title') <> 'true'::jsonb
       or not ((v_ra -> 'fleets' -> 0 -> 'seas') ? 'NOR-MAC') or (v_ra -> 'fleets' -> 0 -> 'seas') ? 'MED' then
      raise exception 'PROOF 91 FAIL: home waters for a title-1 company of Japan: own sea %, a sister sea %, Macaronesia %, her read %',
        public.sea_gate(v_pj, v_fj, v_home.port, null), public.sea_gate(v_pj, v_fj, v_near, null), v_rb, v_ra - 'zones' - 'titles';
    end if;
    -- A COUNTRY CHANGE MOVES HER HOME AT ONCE: sailing for Portugal, Europe is home; she still LIES at Sakai, so the waters of that rank stay hers (the way home)
    update public.players set nation_id = v_prt where id = v_pj;
    v_ra := world.sea_conditions();
    if (v_ra -> 'home_sea' ->> 'title_min')::int <> 1 or (v_ra -> 'fleets' -> 0 -> 'seas') ? 'MED' or (v_ra -> 'fleets' -> 0 -> 'seas') ? v_home.code
       or public.sea_gate(v_pj, v_fj, v_near, null) is not null then
      raise exception 'PROOF 91 FAIL: after a change of country to Portugal her home did not move, or the sea she lies in closed on her: %', v_ra - 'zones' - 'titles';
    end if;
    update public.players set nation_id = v_jpn where id = v_pj;
    raise notice 'PASS: WALL_HOME_WATERS — lit, Japan founds; at title 1 her own sea % (asks title %) and its sister seas are open at the door and in her read, Macaronesia refuses her with title 1 in the figures; sailing for Portugal instead, Europe is home at once and the sea she lies in stays open',
      v_home.code, v_home.title_min;
  end;

  -- ── WALL_CONDITIONS ──
  perform cmd.assume_identity(c_a);
  v_ra := world.sea_conditions();
  perform cmd.assume_identity(c_b);
  v_rb := world.sea_conditions();
  select string_agg(z.code, ' ') into v_bad
    from public.sea_zones z
    cross join lateral (select public.sea_refusal(1, 12, array[z.code]) as a, public.sea_refusal(1, 39, array[z.code]) as b) q
   where ((v_ra -> 'fleets' -> 0 -> 'seas') ? z.code) is distinct from (q.a is not null)
      or ((v_rb -> 'fleets' -> 0 -> 'seas') ? z.code) is distinct from (q.b is not null)
      or (q.a is not null and (v_ra -> 'fleets' -> 0 -> 'seas' -> z.code) <> (q.a -> 'figures'))
      or (q.b is not null and (v_rb -> 'fleets' -> 0 -> 'seas' -> z.code) <> (q.b -> 'figures'));
  if v_bad is not null then
    raise exception 'PROOF 91 FAIL: `seas` is not the rule''s verdict at: %', v_bad;
  end if;
  if (v_ra -> 'fleets' -> 0 ->> 'port') <> 'LIS' or (v_ra -> 'fleets' -> 0 ->> 'wave')::numeric <> 12 or (v_rb -> 'fleets' -> 0 ->> 'wave')::numeric <> 39
     or (select count(*) from jsonb_object_keys(v_rb -> 'fleets' -> 0 -> 'seas')) > (select count(*) from jsonb_object_keys(v_ra -> 'fleets' -> 0 -> 'seas'))
     or exists (select 1 from jsonb_each(v_rb -> 'fleets' -> 0 -> 'seas') e where (e.value ->> 'short_wave')::boolean and (e.value ->> 'needs_wave')::int <= 39)
     or (v_ra -> 'fleets' -> 0 -> 'seas') ? 'NOR-EU'
     or (select sum((z ->> 'harbours')::int) from jsonb_array_elements(v_ra -> 'zones') z) <> (select count(*) from public.ports where kind = 'HARBOUR')
     or (v_ra -> 'far_powers') <> to_jsonb(public.far_powers()) or not (v_ra ->> 'bite')::boolean then
    raise exception 'PROOF 91 FAIL: her conditions: barca % ; nau %', v_ra -> 'fleets', v_rb -> 'fleets';
  end if;
  update public.fleets set port_id = null, status = 'SAILING' where id = v_fa;   -- at sea: no port
  perform cmd.assume_identity(c_a);
  if (world.sea_conditions() -> 'fleets' -> 0 -> 'port') <> 'null'::jsonb then
    raise exception 'PROOF 91 FAIL: a fleet at sea reads a port';
  end if;
  update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fa;
  perform cmd.assume_identity(null);
  v_r := world.sea_conditions();
  if jsonb_array_length(v_r -> 'fleets') <> 0 or (v_r -> 'far_powers') <> (v_ra -> 'far_powers') or (v_r -> 'zones') <> (v_ra -> 'zones') or (v_r -> 'title') <> 'null'::jsonb then
    raise exception 'PROOF 91 FAIL: nobody signed in reads fleets, a title, or other zones';
  end if;
  raise notice 'PASS: WALL_CONDITIONS — `seas` is the rule''s verdict at all % zones for both fleets: % closed to the barca, % to the nau; port LIS, null at sea; harbours add up; nobody reads no fleet',
    (select count(*) from public.sea_zones), (select count(*) from jsonb_object_keys(v_ra -> 'fleets' -> 0 -> 'seas')), (select count(*) from jsonb_object_keys(v_rb -> 'fleets' -> 0 -> 'seas'));

  -- ── WALL_ORDER ──
  perform cmd.assume_identity(c_a);
  v_r := cmd.preview(v_fa, 'SAIL LPA', null);
  v_r2 := cmd.issue(v_fa, 'SAIL LPA', null, null);
  if (v_r ->> 'ok') <> 'false' or (v_r ->> 'error_code') is distinct from 'E_SEA_CLOSED'
     or (v_r -> 'figures') is distinct from (public.sea_refusal(1, 12, array['NOR-MAC']) -> 'figures')
     or (v_r -> 'figures' ->> 'zone') <> 'NOR-MAC' or (v_r -> 'figures' ->> 'needs_title')::int <> 2 or (v_r -> 'figures' ->> 'title')::int <> 1
     or (v_r -> 'figures' -> 'short_title') <> 'true'::jsonb or (v_r -> 'figures' -> 'short_wave') <> 'false'::jsonb
     or (v_r2 ->> 'error_code') is distinct from 'E_SEA_CLOSED' or (v_r2 -> 'figures') is distinct from (v_r -> 'figures') then
    raise exception 'PROOF 91 FAIL: lit, SAIL LPA at title 1: preview % ; issue %', v_r, v_r2;
  end if;
  v_ra := cmd.refusal_caught('E_INSUFFICIENT_FUNDS: you hold 5 d. and it costs 9 d.', '{"have": 5, "need": 9, "unit": "d."}');
  v_rb := cmd.refusal_caught('E_ENDURANCE: too long', '{"nm": 500, "leg_days": 3, "need_days": 4}');
  if (v_ra -> 'figures') is distinct from '{"have": 5, "need": 9, "unit": "d."}'::jsonb or v_rb ? 'figures'
     or cmd.refusal_caught('E_NAME_TAKEN: taken', 'Key (id)=(1) already exists') ? 'figures'
     or cmd.refusal_caught('E_SEA_CLOSED: half', '{"zone": "NOR-MID", "needs_title": 4}') ? 'figures'
     or cmd.refusal_caught('E_SEA_CLOSED: wrong types', '{"zone": 3, "needs_title": 4, "needs_wave": 30}') ? 'figures' then
    raise exception 'PROOF 91 FAIL: the catcher: have/need/unit % ; another shape %', v_ra, v_rb;
  end if;
  raise notice 'PASS: WALL_ORDER — preview and issue of SAIL LPA answer E_SEA_CLOSED with the rule''s figures (% asks title %, she is %); have/need/unit kept as before; other shapes dropped',
    v_r -> 'figures' ->> 'zone_name', v_r -> 'figures' ->> 'needs_title', v_r -> 'figures' ->> 'title';

  -- ── WALL_LEGS ──
  perform cmd.assume_identity(c_a);
  v_r := world.route_legs(v_fa, '[{"from":"LIS","to":"HNL"},{"from":"LIS","to":"OPO"},{"from":"LIS","to":"STO"},{"from":"LIS","to":"NAG"},{"from":"LIS","to":"HAV"}]'::jsonb);
  if (v_r -> 'legs' -> 0 -> 'shut' ->> 'code') not in ('E_LEG_TOO_FAR', 'E_ENDURANCE') or (v_r -> 'legs' -> 0 -> 'via') <> 'null'::jsonb
     or (v_r -> 'legs' -> 0 -> 'sea') is distinct from public.sea_gate(v_pa, v_fa, (select id from public.ports where code = 'HNL'), null)
     or (v_r -> 'legs' -> 0 -> 'sea' ->> 'code') is distinct from 'E_SEA_CLOSED'
     or (v_r -> 'legs' -> 1 -> 'shut') <> 'null'::jsonb or (v_r -> 'legs' -> 1 -> 'sea') <> 'null'::jsonb
     or exists (select 1 from jsonb_array_elements(v_r -> 'legs') l where (l -> 'sea') <> 'null'::jsonb and (l -> 'via') <> 'null'::jsonb) then
    raise exception 'PROOF 91 FAIL: lit, the legs from Lisbon: %', v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  v_r2 := world.route_legs(v_fa, '[{"from":"LIS","to":"HNL"},{"from":"LIS","to":"OPO"},{"from":"LIS","to":"STO"},{"from":"LIS","to":"NAG"},{"from":"LIS","to":"HAV"}]'::jsonb);
  if exists (select 1 from jsonb_array_elements(v_r2 -> 'legs') l where (l -> 'sea') <> 'null'::jsonb)
     -- Porto is open both ways: its row is the same text dark and lit
     or (v_r2 -> 'legs' -> 1) <> (v_r -> 'legs' -> 1) then
    raise exception 'PROOF 91 FAIL: dark, a leg names a sea, or an open leg''s row moved: %', v_r2;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  raise notice 'PASS: WALL_LEGS — lit, Lisbon to Honolulu is shut % with no harbours between and names %; Porto names none; % of 5 legs name a sea; dark none does',
    v_r -> 'legs' -> 0 -> 'shut' ->> 'code', v_r -> 'legs' -> 0 -> 'sea' -> 'figures' ->> 'zone_name',
    (select count(*) from jsonb_array_elements(v_r -> 'legs') l where (l -> 'sea') <> 'null'::jsonb);

  -- ── WALL_WAY_HOME ──
  declare
    v_aca  uuid := (select id from public.ports where code = 'ACA');
    v_hnl  uuid := (select id from public.ports where code = 'HNL');
    v_zone text := (select a.zones[1] from public.sea_leg_asks a join public.ports p on p.id = a.from_port and p.id = a.to_port where p.code = 'ACA');
    v_near uuid;
    v_code text;
    v_reach int;
  begin
    -- a neighbour in her own sea, the nearest
    select p.id, p.code into v_near, v_code
      from public.ports p join public.sea_leg_asks a on a.from_port = p.id and a.to_port = p.id
      join voyage.reach_from(v_aca) r on r.port_id = p.id
     where p.kind = 'HARBOUR' and a.zones[1] = v_zone and p.id <> v_aca order by r.nm limit 1;
    if v_near is null or (select z.title_min from public.sea_zones z where z.code = v_zone) <= 1 then
      raise exception 'PROOF 91 FAIL: Acapulco has no neighbour in its own sea, or its sea asks no title: the premise of the way home is gone';
    end if;
    -- at Lisbon her own figures refuse Acapulco's sea
    if public.sea_gate(v_pa, v_fa, v_near, null) is null then
      raise exception 'PROOF 91 FAIL: from Lisbon, a harbour of the Pacific coast is open to a title-1 barca';
    end if;
    update public.fleets set port_id = v_aca where id = v_fa;
    perform cmd.assume_identity(c_a);
    v_r  := public.sea_gate(v_pa, v_fa, v_near, null);
    v_r2 := public.sea_gate(v_pa, v_fa, v_hnl, null);
    v_ra := cmd.preview(v_fa, 'SAIL ' || v_code, null);
    v_rb := world.sea_conditions();
    select count(*) into v_reach from voyage.reach_passage(v_pa, v_fa, v_aca, null) r where r.nm is not null and r.port_id <> v_aca;
    if v_r is not null or (v_ra ->> 'error_code') is not distinct from 'E_SEA_CLOSED'
       or v_r2 is null or (v_r2 -> 'figures' ->> 'title')::int <> 1 or (v_r2 -> 'figures' ->> 'wave')::numeric <> 12
       or (v_r2 -> 'figures' -> 'short_wave') <> 'true'::jsonb or (v_r2 -> 'figures' -> 'short_title') <> 'false'::jsonb
       or (v_rb -> 'fleets' -> 0 ->> 'port') <> 'ACA' or (v_rb -> 'fleets' -> 0 -> 'seas') ? v_zone
       or not ((v_rb -> 'fleets' -> 0 -> 'seas') ? 'NRT-OPEN') or (v_rb -> 'fleets' -> 0 -> 'seas' -> 'NRT-OPEN' ->> 'title')::int <> 1
       or v_reach < 1 then
      raise exception 'PROOF 91 FAIL: the way home at Acapulco: own sea %, preview %, the open Pacific %, reach %, her read %', v_r, v_ra, v_r2, v_reach, v_rb -> 'fleets' -> 0;
    end if;
    -- dark, the floor is not asked: the gate answers nothing at all
    update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
    if public.sea_gate(v_pa, v_fa, v_hnl, null) is not null then
      raise exception 'PROOF 91 FAIL: dark, the gate refused';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    -- back at Lisbon the wall is the plain rule again
    update public.fleets set port_id = v_lis where id = v_fa;
    if (public.sea_gate(v_pa, v_fa, (select id from public.ports where code = 'LPA'), null) -> 'figures') is distinct from (public.sea_refusal(1, 12, array['NOR-MAC']) -> 'figures') then
      raise exception 'PROOF 91 FAIL: back at Lisbon the gate is not the plain rule';
    end if;
    raise notice 'PASS: WALL_WAY_HOME — lying at Acapulco (%) the title-1 barca may sail to % and reaches % harbours; the open Pacific refuses her on her hull alone (title 1, wave 12 in the figures); her read does not call % closed; at Lisbon the wall is the plain rule', v_zone, v_code, v_reach, v_zone;
  end;

  -- ── WALL_MAP ──
  v_map := world.sea_zone_map();
  execute $f$
create function pg_temp.map_at_69(p_map jsonb, p_lat numeric, p_lon numeric)
returns text
language plpgsql
as $b$
declare
  v_row int := least((p_map ->> 'rows')::int - 1, greatest(0, floor((90 - p_lat) / (p_map ->> 'cell_deg')::numeric)::int));
  v_col int := least((p_map ->> 'cols')::int - 1, greatest(0, floor((p_lon + 180) / (p_map ->> 'cell_deg')::numeric)::int));
  v_at  int := 0;
  r     text;
begin
  foreach r in array string_to_array(p_map -> 'runs' ->> v_row, ',') loop
    v_at := v_at + split_part(r, ':', 2)::int;
    if v_col < v_at then
      return p_map -> 'codes' ->> split_part(r, ':', 1)::int;
    end if;
  end loop;
  return null;
end
$b$
  $f$;
  select string_agg(p.code, ' '), count(*) into v_bad, v_n
    from public.ports p join public.sea_reaches r on r.port_id = p.id
   where p.kind = 'HARBOUR'
     and pg_temp.map_at_69(v_map, r.roadstead_lat, r.roadstead_lon) is distinct from public.sea_zone_at(r.roadstead_lat::float8, r.roadstead_lon::float8);
  if v_bad is not null then
    raise exception 'PROOF 91 FAIL: the map decoded at % roadsteads does not name the sea public.sea_zone_at names: %', v_n, v_bad;
  end if;
  if pg_temp.map_at_69(v_map, 40.4, -3.7) is not null or pg_temp.map_at_69(v_map, 15.0, 20.0) is not null or pg_temp.map_at_69(v_map, 35.0, 100.0) is not null
     or pg_temp.map_at_69(v_map, 36.0, -40.0) is distinct from public.sea_zone_at(36.0, -40.0) or pg_temp.map_at_69(v_map, 36.0, -40.0) is null then
    raise exception 'PROOF 91 FAIL: the map names a sea at Madrid, in the Sahara or in China, or none in the mid-Atlantic';
  end if;
  if has_function_privilege('anon', 'world.sea_zone_map()', 'execute') or not has_function_privilege('authenticated', 'world.sea_zone_map()', 'execute')
     or not exists (select 1 from public.client_rpc_entry_points() e where e.schema_name = 'world' and e.function_name = 'sea_zone_map') then
    raise exception 'PROOF 91 FAIL: world.sea_zone_map is not to authenticated only, or not registered';
  end if;
  raise notice 'PASS: WALL_MAP — decoded at % roadsteads the map names each harbour''s own sea; land names none; % rows of %, % codes, % bytes; authenticated only, registered',
    (select count(*) from public.ports where kind = 'HARBOUR'), v_map ->> 'rows', v_map ->> 'cols', jsonb_array_length(v_map -> 'codes'), length(v_map::text);

  -- ── WALL_COST ──
  update public.world_config set value = '5'::jsonb where key in ('fleet_max', 'fleet_hard_max');
  for i in 2 .. 5 loop
    perform public.commission_ship(v_pa, public.form_fleet(v_pa, 'Muro A ' || i, v_lis), 'barca', 'Muro A ' || i, true, true);
  end loop;
  perform cmd.assume_identity(c_a);
  v_t := clock_timestamp();
  for i in 1 .. 5 loop v_r := world.sea_conditions(); end loop;
  v_ms1 := round(extract(epoch from clock_timestamp() - v_t) * 200, 1);
  v_t := clock_timestamp();
  for i in 1 .. 3 loop v_map := world.sea_zone_map(); end loop;
  v_ms2 := round(extract(epoch from clock_timestamp() - v_t) * 1000 / 3, 1);
  if jsonb_array_length(v_r -> 'fleets') <> 5 then
    raise exception 'PROOF 91 FAIL: the company of five fleets reads %', jsonb_array_length(v_r -> 'fleets');
  end if;
  raise notice 'PASS: WALL_COST — world.sea_conditions for five fleets % ms (% bytes); world.sea_zone_map % ms (% bytes)', v_ms1, length(v_r::text), v_ms2, length(v_map::text);
end
$$;
