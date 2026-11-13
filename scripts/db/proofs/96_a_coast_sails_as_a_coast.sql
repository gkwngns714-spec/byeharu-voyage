-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 96 - A COAST SAILS AS A COAST  (migration 0401; docs/SEA_CONDITIONS_AND_REGIONS.md section 2: coasts for any hull, the weight on the crossings)
--
--   0401's self-assert holds the data and the derivations. This proof asks the REAL readers a player meets, on the courses the world remembers (real
--   sailed lines) and with real companies founded here and rolled back: the one rule, the sail door, her conditions read, the merchants' guard.
--
-- @pass CC_GUINEA   a barca's wave (12) holds every remembered course from Europe and Macaronesia to the Gulf of Guinea, and Guinea to Angola; a title-1 company of Portugal is refused on such a course by her TITLE alone (Macaronesia asks 2), not by her hull
-- @pass CC_OCEAN    the crossings are walls still: Lisbon to Recife, Cape Verde to Recife and Luanda to Recife refuse a barca on wave whatever her title (the last by the new ocean box of the South Atlantic); Manila to Guam asks the Philippine Sea's 50
-- @pass CC_COASTS   the Guianas (Belem to Willemstad), the Philippines' Pacific side (Tainan to Cebu, Manila to Naha) and the way out of the Seto (Osaka to Busan, Hirado to Sakai) each hold a barca
-- @pass CC_JAPAN    lit, a new title-1 company of Japan in her barca at Sakai may sail a remembered course out of the Seto Inland Sea to another harbour of her home's rank (home waters, and now her hull holds the way)
-- @pass CC_READS    her conditions read no longer calls the Kuroshio closed to a barca of Japan; the map's zone at a point off Liberia is the Gulf of Guinea and in mid-Atlantic still The Doldrums; the merchants' guard reads no course unremembered
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_a constant uuid := '00000000-0401-4000-8000-0000000000a1';
  c_j constant uuid := '00000000-0401-4000-8000-0000000000b1';
  v_pa  uuid;
  v_fa  uuid;
  v_pj  uuid;
  v_fj  uuid;
  v_n   int;
  v_bad text;
  v_r   jsonb;
  v_c   record;
begin
  if not exists (select 1 from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id where s.code = 'NOR' and b.zone_code = 'GUL') then
    raise exception 'PROOF 96 FAIL: 0401 is not in this world';
  end if;
  create temp table c96 on commit drop as
  select a.code as a, b.code as b, c.course, c.to_port, public.course_zones(c.course) || array[public.harbour_zone(c.to_port)] as zones,
         (select z.code from public.sea_zones z where z.code = public.harbour_zone(c.from_port)) as za, public.harbour_zone(c.to_port) as zb
    from public.npc_courses c join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port;

  -- ── CC_GUINEA ──
  select count(*), string_agg(c.a || '-' || c.b, ' ') filter (where public.sea_refusal(null, 12, c.zones) is not null) into v_n, v_bad
    from c96 c join public.sea_zones z1 on z1.code = c.za
   where (c.zb = 'GUL' and z1.title_min <= 2) or (c.za = 'GUL' and c.zb = 'SOU-ANG') or (c.za = 'SOU-ANG' and c.zb = 'GUL');
  if v_n < 15 or v_bad is not null then
    raise exception 'PROOF 96 FAIL: of % remembered courses to Guinea and on to Angola, a barca''s wave is refused on: %', v_n, v_bad;
  end if;
  v_pa := public.new_house(c_a, 'Casa Costa 96', 'PRT', 'LIS', 'Costa', 'barca', 'Costa', null, false);
  select id into v_fa from public.fleets where player_id = v_pa;
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  select * into v_c from c96 c where c.a = 'LIS' and c.zb = 'GUL' limit 1;
  v_r := public.sea_gate(v_pa, v_fa, v_c.to_port, v_c.course);
  if v_c.a is null or v_r is null or (v_r -> 'figures' -> 'short_title') <> 'true'::jsonb or (v_r -> 'figures' -> 'short_wave') <> 'false'::jsonb then
    raise exception 'PROOF 96 FAIL: a title-1 barca from Lisbon to % is not refused on her title alone: %', v_c.b, v_r;
  end if;
  raise notice 'PASS: CC_GUINEA — a barca''s 12 holds all % remembered courses to Guinea and Guinea to Angola; from Lisbon to % a title-1 company is refused by % on title alone', v_n, v_c.b, v_r -> 'figures' ->> 'zone_name';

  -- ── CC_OCEAN ──
  if exists (select 1 from (values ('LIS', 'REC'), ('CID', 'REC'), ('LUA', 'REC'), ('MNL', 'HAG')) v(a, b)
              join public.sea_reaches ra on ra.code = v.a join public.sea_reaches rb on rb.code = v.b
             where coalesce((public.sea_refusal(11, 12, public.course_zones(jsonb_build_array(jsonb_build_array(ra.roadstead_lat, ra.roadstead_lon), jsonb_build_array(rb.roadstead_lat, rb.roadstead_lon)))
                              || array[public.harbour_zone(rb.port_id)]) -> 'figures' ->> 'needs_wave')::int, 0) < 24)
     or public.sea_zone_at(-10, -15) is distinct from 'NOR-DOL'
     or (select s.wave_min from public.sea_leg_asks s join public.ports a on a.id = s.from_port and a.code = 'MNL' join public.ports b on b.id = s.to_port and b.code = 'HAG') < 50 then
    raise exception 'PROOF 96 FAIL: a crossing no longer refuses a barca of the highest title on her wave';
  end if;
  raise notice 'PASS: CC_OCEAN — Lisbon to Recife, Cape Verde to Recife and Luanda to Recife refuse a title-11 barca on wave (24 or more); Manila to Guam asks 50';

  -- ── CC_COASTS ──
  select string_agg(c.a || '-' || c.b, ' ') filter (where public.sea_refusal(null, 12, c.zones) is not null), count(*) into v_bad, v_n
    from c96 c where (c.a, c.b) in (('BEL', 'WIL'), ('CUM', 'BEL'), ('SAN', 'BEL'), ('TAI', 'CEB'), ('MNL', 'NAH'), ('TON', 'MNL'), ('OSA', 'BUS'), ('HIR', 'SAK'), ('NIN', 'OSA'), ('SAK', 'FUZ'));
  if v_n < 6 or v_bad is not null then
    raise exception 'PROOF 96 FAIL: of % coastal courses of the Guianas, the Philippines and Japan, a barca is refused on: %', v_n, v_bad;
  end if;
  raise notice 'PASS: CC_COASTS — a barca holds all % remembered coastal courses checked along the Guianas, the Philippines'' Pacific side and out of the Seto Inland Sea', v_n;

  -- ── CC_JAPAN ──
  perform cmd.assume_identity(c_j);
  v_r := cmd.found_house('Casa Seto 96', 'JPN');
  v_pj := (v_r ->> 'player_id')::uuid;
  select id into v_fj from public.fleets where player_id = v_pj;
  select c.* into v_c from c96 c join public.sea_zones z on z.code = c.zb
   where c.a = (select n.capital_port_code from public.nations n where n.code = 'JPN') and z.title_min = 7 and c.zb <> c.za order by c.b limit 1;
  if v_pj is null or v_c.a is null or public.fleet_wave(v_fj) <> 12 or public.title_level(v_pj) <> 1
     or public.sea_gate(v_pj, v_fj, v_c.to_port, v_c.course) is not null then
    raise exception 'PROOF 96 FAIL: a title-1 barca of Japan at % is refused the course to %: %', v_c.a, v_c.b, public.sea_gate(v_pj, v_fj, v_c.to_port, v_c.course);
  end if;
  raise notice 'PASS: CC_JAPAN — lit, a new title-1 company of Japan in a barca sails the remembered course % to % out of the Seto Inland Sea', v_c.a, v_c.b;

  -- ── CC_READS ──
  v_r := world.sea_conditions();
  if (v_r -> 'fleets' -> 0 -> 'seas') ? 'PHI-JP' or (v_r -> 'fleets' -> 0 -> 'seas') ? 'SET'
     or public.sea_zone_at(6, -12) is distinct from 'GUL' or public.sea_zone_at(5, -30) is distinct from 'NOR-DOL'
     or (public.sea_conditions_npc_ready() ->> 'courses_not_remembered')::int <> 0 then
    raise exception 'PROOF 96 FAIL: her read still calls the Kuroshio closed, the map is not as drawn, or a merchant course is not remembered: %', public.sea_conditions_npc_ready();
  end if;
  raise notice 'PASS: CC_READS — her read does not call the Kuroshio closed; off Liberia is the Gulf of Guinea, mid-Atlantic The Doldrums; no merchant course unremembered';
end $$;
