-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 69 — A WALL SAYS WHAT IS SHORT  (migration 0376, owner rows 166 and 324)
--
--   The migration's self-assert reads the rule with typed figures and one probe company. Here the companies are real (the real founding door, the real
--   passage gate, the real leg judge), the switch is turned both ways, and each new key is held to the authority it copies. Everything rolls back with
--   proof.mjs's transaction; every switch this proof needs it writes here.
--
-- @pass WALL_SHORT       the real passage gate, lit: a barca company at title 1 is refused the Western Ocean with short_title and short_wave true; in a nau (wave 39) the same sea says short_title only; the six old figures and the sentence are the rule's as before
-- @pass WALL_FAR_POWER   dark, the real founding door lets Japan in; lit, Japan and (pirates joinable) the Brethren are refused E_FAR_POWER with the sea and the title it asks, the fixes name only powers in open water, no row is written; Portugal and the Ottomans are let in; the doors before it answer first
-- @pass WALL_CONDITIONS  her read: every zone is in a fleet's `seas` exactly when the one rule refuses that zone alone, with the rule's own figures; the nau's fleet has fewer closed seas than the barca's and none of them short of wave below 39; `port` is where she lies; `harbours` adds up to every harbour; nobody signed in reads no fleet and the same far powers
-- @pass WALL_ORDER       lit, the real order paths: cmd.preview and cmd.issue of SAIL LPA for the title-1 barca answer E_SEA_CLOSED with the rule's own figures (Macaronesia, title 2 asked, 1 held, short of title and not of wave); the catcher (cmd.refusal_caught) still keeps cmd.figures' shape (have, need, unit) and still drops every other: a leg's own figures, a PostgreSQL DETAIL, half the sea's shape, the sea's keys with the wrong types
-- @pass WALL_LEGS        lit, a leg from Lisbon to Honolulu is shut by its length with no harbours between and names the sea the gate refuses on; Porto names none; no leg names a sea while it has harbours between; dark, no leg names a sea and the other keys are the same text as lit
-- @pass WALL_MAP         world.sea_zone_map decoded at every harbour's roadstead names the harbour's own sea (public.harbour_zone), and at three points of land names none; anon may not call it, a signed-in caller may; it is registered
-- @pass WALL_COST        the conditions read for a company of five fleets and the map, timed (printed, never judged)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_a constant uuid := '00000000-0376-4000-8000-0000000000a1';
  c_b constant uuid := '00000000-0376-4000-8000-0000000000b1';
  c_c constant uuid := '00000000-0376-4000-8000-0000000000c1';
  c_d constant uuid := '00000000-0376-4000-8000-0000000000d1';
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
    raise exception 'PROOF 69 FAIL: the two companies are not title 1 in a barca (12) and a nau (39): title %, waves % and %', public.title_level(v_pa), public.fleet_wave(v_fa), public.fleet_wave(v_fb);
  end if;

  -- ── WALL_SHORT ──
  if public.passage_gate(v_pa, v_fa, 100, v_hav, null) is not null then
    raise exception 'PROOF 69 FAIL: dark, the passage gate refuses a short leg to Havana';
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
    raise exception 'PROOF 69 FAIL: lit, the gate on a course into the ocean: barca % ; nau %', v_ra, v_rb;
  end if;
  raise notice 'PASS: WALL_SHORT — the gate refuses % to both: the barca is short of title and wave, the nau of title only; eight figures, the sentence unmoved', v_ra -> 'figures' ->> 'zone_name';

  -- ── WALL_FAR_POWER ──
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  perform cmd.assume_identity(c_c);
  v_r := cmd.found_house('Casa Muro Longe', 'JPN');
  if (v_r ->> 'ok') <> 'true' then
    raise exception 'PROOF 69 FAIL: dark, founding under Japan answered %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key in ('sea_conditions_bite', 'pirates_joinable');
  select count(*) into v_n from public.players;
  perform cmd.assume_identity(c_d);
  v_r := cmd.found_house('Casa Muro Perto', 'JPN');
  v_r2 := cmd.found_house('Casa Muro Perto', 'PIR');
  if (v_r ->> 'error_code') is distinct from 'E_FAR_POWER' or (v_r2 ->> 'error_code') is distinct from 'E_FAR_POWER'
     or (v_r ->> 'ok') <> 'false' or (v_r -> 'figures' ->> 'nation') <> 'JPN' or (v_r2 -> 'figures' ->> 'capital') <> 'POR'
     or (v_r -> 'figures' ->> 'zone') is distinct from public.harbour_zone((select p.id from public.ports p join public.nations n on n.capital_port_code = p.code where n.code = 'JPN'))
     or (v_r -> 'figures' ->> 'needs_title')::int is distinct from (select z.title_min from public.sea_zones z where z.code = v_r -> 'figures' ->> 'zone')
     or (v_r ->> 'error_message') !~ ('^Japan lies in ' || (v_r -> 'figures' ->> 'zone_name') || ', which asks title ' || (v_r -> 'figures' ->> 'needs_title'))
     or exists (select 1 from jsonb_array_elements_text(v_r -> 'fixes') x, unnest(public.far_powers()) fp where x like '(sail under ' || fp || ' %')
     or (v_r -> 'fixes')::text !~ 'PRT' or (v_r -> 'fixes')::text !~ 'OTT'
     or (select count(*) from public.players) <> v_n then
    raise exception 'PROOF 69 FAIL: lit, founding under Japan % ; under the Brethren %', v_r, v_r2;
  end if;
  if (cmd.found_house('Casa Muro Perto', 'VEN') ->> 'error_code') <> 'E_MINOR_POWER' or (cmd.found_house('Casa Muro Perto', 'ZZZ') ->> 'error_code') <> 'E_NO_SUCH_NATION' then
    raise exception 'PROOF 69 FAIL: lit, the doors before the far-power door moved';
  end if;
  v_r := cmd.found_house('Casa Muro Perto', 'OTT');
  if (v_r ->> 'ok') <> 'true' then
    raise exception 'PROOF 69 FAIL: lit, founding under the Ottomans answered %', v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_joinable';
  raise notice 'PASS: WALL_FAR_POWER — dark Japan is let in; lit Japan (her sea asks title %) and the Brethren are refused E_FAR_POWER, % fixes in open water, no row written; the Ottomans are let in',
    (select z.title_min from public.sea_zones z where z.code = public.harbour_zone((select p.id from public.ports p join public.nations n on n.capital_port_code = p.code where n.code = 'JPN'))),
    (select count(*) from public.nations o where public.nation_joinable(o.id) and not (o.code = any (public.far_powers())));

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
    raise exception 'PROOF 69 FAIL: `seas` is not the rule''s verdict at: %', v_bad;
  end if;
  if (v_ra -> 'fleets' -> 0 ->> 'port') <> 'LIS' or (v_ra -> 'fleets' -> 0 ->> 'wave')::numeric <> 12 or (v_rb -> 'fleets' -> 0 ->> 'wave')::numeric <> 39
     or (select count(*) from jsonb_object_keys(v_rb -> 'fleets' -> 0 -> 'seas')) > (select count(*) from jsonb_object_keys(v_ra -> 'fleets' -> 0 -> 'seas'))
     or exists (select 1 from jsonb_each(v_rb -> 'fleets' -> 0 -> 'seas') e where (e.value ->> 'short_wave')::boolean and (e.value ->> 'needs_wave')::int <= 39)
     or (v_ra -> 'fleets' -> 0 -> 'seas') ? 'NOR-EU'
     or (select sum((z ->> 'harbours')::int) from jsonb_array_elements(v_ra -> 'zones') z) <> (select count(*) from public.ports where kind = 'HARBOUR')
     or (v_ra -> 'far_powers') <> to_jsonb(public.far_powers()) or not (v_ra ->> 'bite')::boolean then
    raise exception 'PROOF 69 FAIL: her conditions: barca % ; nau %', v_ra -> 'fleets', v_rb -> 'fleets';
  end if;
  update public.fleets set port_id = null, status = 'SAILING' where id = v_fa;   -- at sea: no port
  perform cmd.assume_identity(c_a);
  if (world.sea_conditions() -> 'fleets' -> 0 -> 'port') <> 'null'::jsonb then
    raise exception 'PROOF 69 FAIL: a fleet at sea reads a port';
  end if;
  update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fa;
  perform cmd.assume_identity(null);
  v_r := world.sea_conditions();
  if jsonb_array_length(v_r -> 'fleets') <> 0 or (v_r -> 'far_powers') <> (v_ra -> 'far_powers') or (v_r -> 'zones') <> (v_ra -> 'zones') or (v_r -> 'title') <> 'null'::jsonb then
    raise exception 'PROOF 69 FAIL: nobody signed in reads fleets, a title, or other zones';
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
    raise exception 'PROOF 69 FAIL: lit, SAIL LPA at title 1: preview % ; issue %', v_r, v_r2;
  end if;
  v_ra := cmd.refusal_caught('E_INSUFFICIENT_FUNDS: you hold 5 d. and it costs 9 d.', '{"have": 5, "need": 9, "unit": "d."}');
  v_rb := cmd.refusal_caught('E_ENDURANCE: too long', '{"nm": 500, "leg_days": 3, "need_days": 4}');
  if (v_ra -> 'figures') is distinct from '{"have": 5, "need": 9, "unit": "d."}'::jsonb or v_rb ? 'figures'
     or cmd.refusal_caught('E_NAME_TAKEN: taken', 'Key (id)=(1) already exists') ? 'figures'
     or cmd.refusal_caught('E_SEA_CLOSED: half', '{"zone": "NOR-MID", "needs_title": 4}') ? 'figures'
     or cmd.refusal_caught('E_SEA_CLOSED: wrong types', '{"zone": 3, "needs_title": 4, "needs_wave": 30}') ? 'figures' then
    raise exception 'PROOF 69 FAIL: the catcher: have/need/unit % ; another shape %', v_ra, v_rb;
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
    raise exception 'PROOF 69 FAIL: lit, the legs from Lisbon: %', v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  v_r2 := world.route_legs(v_fa, '[{"from":"LIS","to":"HNL"},{"from":"LIS","to":"OPO"},{"from":"LIS","to":"STO"},{"from":"LIS","to":"NAG"},{"from":"LIS","to":"HAV"}]'::jsonb);
  if exists (select 1 from jsonb_array_elements(v_r2 -> 'legs') l where (l -> 'sea') <> 'null'::jsonb)
     -- Porto is open both ways: its row is the same text dark and lit
     or (v_r2 -> 'legs' -> 1) <> (v_r -> 'legs' -> 1) then
    raise exception 'PROOF 69 FAIL: dark, a leg names a sea, or an open leg''s row moved: %', v_r2;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  raise notice 'PASS: WALL_LEGS — lit, Lisbon to Honolulu is shut % with no harbours between and names %; Porto names none; % of 5 legs name a sea; dark none does',
    v_r -> 'legs' -> 0 -> 'shut' ->> 'code', v_r -> 'legs' -> 0 -> 'sea' -> 'figures' ->> 'zone_name',
    (select count(*) from jsonb_array_elements(v_r -> 'legs') l where (l -> 'sea') <> 'null'::jsonb);

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
    raise exception 'PROOF 69 FAIL: the map decoded at % roadsteads does not name the sea public.sea_zone_at names: %', v_n, v_bad;
  end if;
  if pg_temp.map_at_69(v_map, 40.4, -3.7) is not null or pg_temp.map_at_69(v_map, 15.0, 20.0) is not null or pg_temp.map_at_69(v_map, 35.0, 100.0) is not null
     or pg_temp.map_at_69(v_map, 36.0, -40.0) is distinct from public.sea_zone_at(36.0, -40.0) or pg_temp.map_at_69(v_map, 36.0, -40.0) is null then
    raise exception 'PROOF 69 FAIL: the map names a sea at Madrid, in the Sahara or in China, or none in the mid-Atlantic';
  end if;
  if has_function_privilege('anon', 'world.sea_zone_map()', 'execute') or not has_function_privilege('authenticated', 'world.sea_zone_map()', 'execute')
     or not exists (select 1 from public.client_rpc_entry_points() e where e.schema_name = 'world' and e.function_name = 'sea_zone_map') then
    raise exception 'PROOF 69 FAIL: world.sea_zone_map is not to authenticated only, or not registered';
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
    raise exception 'PROOF 69 FAIL: the company of five fleets reads %', jsonb_array_length(v_r -> 'fleets');
  end if;
  raise notice 'PASS: WALL_COST — world.sea_conditions for five fleets % ms (% bytes); world.sea_zone_map % ms (% bytes)', v_ms1, length(v_r::text), v_ms2, length(v_map::text);
end
$$;
