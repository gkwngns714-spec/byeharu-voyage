-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 67 — MORE SHIPS, TO TRADE, TO CARRY AND ABOVE ALL TO FIGHT  (migration 0366, owner row 322)
--
--   0366 writes catalogue rows and runs no game step (docs/OPS_HEALTH.md section 4). This proof lays the new hulls down through the REAL cmd.do_build, the one
--   BUILD verb, at a yard of each hull's own country, and fights the built ships through the REAL engine: voyage.fleet_hulls (a fleet as a side, as a raid reads
--   her) and public.fight_sides. A hull of each job is picked by the figures that make the job; the four the fights need are named.
--
-- @pass MORE_SHIPS_SERVED    the Codex read and a yard of her own country serve every new class with its line, size, role and tech, at the recipe's labour
-- @pass MORE_SHIPS_GATES     a new hull meets the existing gates, in order: another country's yard, her skills, her materials, the purse
-- @pass MORE_SHIPS_BUILD     a hull of every role and job (raider, gunship, boarder, line, escort, armed trader, cargo carrier, plain trader) is laid down by the one verb, at her line's yard: she joins the fleet, of that class, the materials spent, the labour paid once
-- @pass MORE_SHIPS_REACH     two built fleets fight through the engine: at long range only the longer reach fires, and the same fight twice is the same fight
-- @pass MORE_SHIPS_CREW      a built boarder with her full crew is never taken by a raid of one xebec, and throws it back
-- @pass MORE_SHIPS_ESCORT    a built cargo carrier's fleet alone is taken by a raid of one xebec every time; the same side with a built escort beside it holds in most fights
-- @pass MORE_SHIPS_NPC       no merchant, loadout, crown knob or NPC ship is given a new class, and the classes the NPC knobs name have the figures they had
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_seeds constant int := 40;
  v_new   text[];
  v_n     int := 0;
  v_c     record;
  v_ok    uuid;
  v_wrong uuid;
  v_pl    uuid;
  v_fl    uuid;
  v_ship  uuid;
  v_price bigint;
  v_purse bigint;
  v_r     jsonb;
  v_err   text;
  v_built jsonb := '{}'::jsonb;   -- job word -> the fleet that holds the built hull
  v_a     jsonb;
  v_b     jsonb;
  v_f     jsonb;
  v_f2    jsonb;
  v_held  int;
  v_held2 int;
  v_long  int := 0;
  v_fleets uuid[] := '{}';
  v_i     int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'combat_bite', 'skills_bite');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 1000000, reserve = 0;

  execute $f$
create function pg_temp.refused_67(p_fleet uuid, p_args jsonb)
returns text
language plpgsql
as $b$
begin
  perform cmd.do_build(p_fleet, p_args);
  return 'BUILT';
exception when others then
  return sqlerrm;
end
$b$
  $f$;
  execute $f$
create function pg_temp.house_67(p_n int, p_port uuid, p_ducats bigint)
returns uuid
language plpgsql
as $b$
declare
  v_p uuid := public.new_house(('00000000-0366-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid, 'Casa Proof ' || p_n, 'PRT', 'LIS', 'Proof ' || p_n, 'barca', 'Proof ' || p_n, null, false);
  v_f uuid;
begin
  select id into v_f from public.fleets where player_id = v_p;
  update public.fleets set port_id = p_port where id = v_f;
  update public.players set ducats = p_ducats where id = v_p;
  return v_f;
end
$b$
  $f$;
  execute $f$
create function pg_temp.equip_67(p_player uuid, p_port uuid, p_class text)
returns void
language plpgsql
as $b$
begin
  insert into public.player_skills (player_id, skill_id, level)
  select p_player, s.id, r.level from public.skill_requirements r join public.skills s on s.code = r.skill_code
   where r.subject_kind = 'hull' and r.subject_code = p_class
  on conflict (player_id, skill_id) do update set level = greatest(public.player_skills.level, excluded.level);
  insert into public.player_storage (player_id, port_id, good_id, qty)
  select p_player, p_port, hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = p_class
  on conflict (player_id, port_id, good_id) do update set qty = public.player_storage.qty + excluded.qty;
end
$b$
  $f$;
  execute $f$
create function pg_temp.yard_67(p_class text)
returns uuid
language sql
stable
as $b$
  select b.port_id from public.port_buildings b join public.hull_recipes h on h.class_code = p_class
   where b.kind = 'building_yard' and b.tier >= h.yard_tier and public.yard_wrong_country(b.port_id, p_class) is null and public.port_has_shipyard(b.port_id)
   order by b.port_id limit 1
$b$
  $f$;

  -- THE NEW CLASSES, by code (Wave E of data/ships.generated.json; scripts/db/world-guard.mjs holds the catalogue to that file on every apply, this proof's too).
  -- The list is for the two reads and the NPC law; the builds below pick a class of each job by the figures that make the job.
  select array_agg(c.code order by c.code) into v_new
    from public.ship_classes c join public.class_profile cp on cp.class_code = c.code
   where c.code in ('bergantim', 'schnigge', 'balinger', 'brigantin', 'galeotta', 'firkate', 'lancaran', 'shaochuan', 'bahansen', 'sahuseon', 'galeoncete', 'greatgalley', 'roberge', 'goke', 'wugong',
                    'gale', 'galera', 'galcapitana', 'kalyata', 'parau', 'ghali', 'mengchong', 'mekura', 'geomseon', 'daemaeng', 'naucap', 'kraweel', 'nef', 'barza', 'louchuan', 'tekkosen',
                    'friedeschiff', 'wafter', 'almiranta', 'jungmaeng', 'caravelao', 'chalupa', 'tartana', 'boum', 'sayka', 'bezaisen', 'nao', 'kogge', 'byeongjo', 'kenminsen', 'kotia',
                    'hoy', 'holk', 'cocca', 'caochuan', 'taforeia', 'hourque', 'jong', 'navegrossa');
  if coalesce(cardinality(v_new), 0) <> 54 then
    raise exception 'PROOF 67 FAIL: % of the 54 classes of 0366 are in the catalogue', coalesce(cardinality(v_new), 0);
  end if;

  -- ── SERVED ──
  if (select count(*) from jsonb_array_elements(world.snapshot() -> 'ship_classes') s
       where s ->> 'code' = any (v_new) and s ->> 'tech' = 'T1' and (s ->> 'size')::int between 1 and 6 and s ->> 'line' is not null
         and s ->> 'role' in ('trade', 'combat', 'support') and (s ->> 'hold')::int > 0 and (s ->> 'speed_kn')::numeric > 0) <> 54 then
    raise exception 'PROOF 67 FAIL: the snapshot does not serve the 54 classes whole';
  end if;
  if (select count(*) from jsonb_array_elements(world.snapshot() -> 'ship_classes') s where s ->> 'code' = any (v_new) and s ->> 'role' = 'combat') < 27
     or (select count(*) from jsonb_array_elements(world.snapshot() -> 'ship_classes') s where s ->> 'code' = any (v_new) and s ->> 'role' = 'trade') < 15 then
    raise exception 'PROOF 67 FAIL: the new classes are not combat first, then trade';
  end if;
  for v_c in select c.code from public.ship_classes c where c.code = any (v_new) order by c.code loop
    v_ok := pg_temp.yard_67(v_c.code);
    if v_ok is null then
      raise exception 'PROOF 67 FAIL: % has no build yard of her own country with a shipyard', v_c.code;
    end if;
    if not exists (select 1 from jsonb_array_elements(world.building_yard(v_ok) -> 'hulls') s
                    where s ->> 'class' = v_c.code and (s ->> 'ducats')::bigint = public.hull_labour(v_c.code)) then
      raise exception 'PROOF 67 FAIL: the yard of her own country does not offer % at the recipe''s labour', v_c.code;
    end if;
  end loop;
  raise notice 'PASS: MORE_SHIPS_SERVED — 54 classes on the Codex read, each offered by a yard of her own country at the recipe''s labour';

  -- ── A HULL OF EVERY JOB, THROUGH THE ONE VERB. The job is read from the figures that make it (scripts/build-ships.mjs JOBS), the hull picked by code order. ──
  for v_c in
    select j.job, c.code, c.id as class_id, h.yard_tier
      from (values ('raider'), ('gunship'), ('boarder'), ('line'), ('escort'), ('armed'), ('carrier'), ('plain')) j(job)
      cross join lateral (
        select c.code from public.ship_classes c join public.class_profile cp on cp.class_code = c.code
         where c.code = any (v_new)
           and case j.job
                 when 'gunship' then c.code = 'greatgalley'       -- the fights below want these four by name: an English gunship,
                 when 'boarder' then c.code = 'daemaeng'          -- a Joseon boarder,
                 when 'escort'  then c.code = 'wafter'            -- an English escort
                 when 'carrier' then c.code = 'hoy'               -- and an English cargo carrier
                 when 'raider'  then cp.role = 'combat' and cp.size <= 2 and c.sighting >= 12 and c.crew_max < 130 and c.reach >= 20 and c.code not in ('wugong')
                 when 'line'    then cp.role = 'combat' and cp.size >= 4 and c.armour >= 48 and c.reach >= 74 and c.code <> 'daemaeng'
                 when 'armed'   then cp.role = 'trade' and c.attack >= 120 and c.accuracy >= 51 and cp.size in (3, 4) and c.crew_max >= 178
                 else cp.role = 'trade' and cp.size <= 2 and c.code not in ('hoy', 'kogge') end
         order by c.code limit 1) p
      join public.ship_classes c on c.code = p.code join public.hull_recipes h on h.class_code = c.code
     order by j.job loop
    v_n := v_n + 1;
    v_ok := pg_temp.yard_67(v_c.code);
    select b.port_id into v_wrong from public.port_buildings b
     where b.kind = 'building_yard' and b.tier >= v_c.yard_tier and public.yard_wrong_country(b.port_id, v_c.code) is not null order by b.port_id limit 1;
    v_price := (select round(h.ducats * public.wc_num('hull_labour_mult'))::bigint from public.hull_recipes h where h.class_code = v_c.code);
    v_fl := pg_temp.house_67(v_n, coalesce(v_wrong, v_ok), 100000000);
    select player_id into v_pl from public.fleets where id = v_fl;

    if v_c.job = 'gunship' then
      if v_wrong is null then
        raise exception 'PROOF 67 FAIL: no yard of another country to prove the country rule on';
      end if;
      v_err := pg_temp.refused_67(v_fl, jsonb_build_object('class', v_c.code, 'name', 'Proof Hull'));
      if v_err not like '%E_WRONG_YARD%' then
        raise exception 'PROOF 67 FAIL: % at another country''s yard: %', v_c.code, v_err;
      end if;
      update public.fleets set port_id = v_ok where id = v_fl;
      v_err := pg_temp.refused_67(v_fl, jsonb_build_object('class', v_c.code, 'name', 'Proof Hull'));
      if v_err not like '%E_NEEDS_SKILL%' then
        raise exception 'PROOF 67 FAIL: % with no skills: %', v_c.code, v_err;
      end if;
      insert into public.player_skills (player_id, skill_id, level)
      select v_pl, s.id, r.level from public.skill_requirements r join public.skills s on s.code = r.skill_code
       where r.subject_kind = 'hull' and r.subject_code = v_c.code
      on conflict (player_id, skill_id) do update set level = excluded.level;
      v_err := pg_temp.refused_67(v_fl, jsonb_build_object('class', v_c.code, 'name', 'Proof Hull'));
      if v_err not like '%E_NO_TIMBER%' then
        raise exception 'PROOF 67 FAIL: % with an empty shed: %', v_c.code, v_err;
      end if;
      perform pg_temp.equip_67(v_pl, v_ok, v_c.code);
      update public.players set ducats = v_price - 1 where id = v_pl;
      v_err := pg_temp.refused_67(v_fl, jsonb_build_object('class', v_c.code, 'name', 'Proof Hull'));
      if v_err not like '%E_NO_FUNDS%' then
        raise exception 'PROOF 67 FAIL: % a ducat short: %', v_c.code, v_err;
      end if;
      update public.players set ducats = 100000000 where id = v_pl;
      raise notice 'PASS: MORE_SHIPS_GATES — % refused at another country''s yard, with no skills, with an empty shed and a ducat short, in that order', v_c.code;
    else
      update public.fleets set port_id = v_ok where id = v_fl;
      perform pg_temp.equip_67(v_pl, v_ok, v_c.code);
    end if;

    select p.ducats into v_purse from public.players p where p.id = v_pl;
    v_r := cmd.do_build(v_fl, jsonb_build_object('class', v_c.code, 'name', 'Proof ' || v_c.job));
    v_ship := (v_r ->> 'ship')::uuid;
    if (select s.fleet_id from public.ships s where s.id = v_ship) is distinct from v_fl
       or (select s.class_id from public.ships s where s.id = v_ship) is distinct from v_c.class_id
       or (select s.durability from public.ships s where s.id = v_ship) <= 0
       or exists (select 1 from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_ok)
       or (select p.ducats from public.players p where p.id = v_pl) <> v_purse - v_price
       or (v_r ->> 'ducats')::bigint <> v_price then
      raise exception 'PROOF 67 FAIL: % (%) was not laid down whole: %', v_c.code, v_c.job, v_r;
    end if;
    -- she is manned for the fights below: her full crew (a company hires them; the proof seats them)
    update public.ships s set crew = (select c.crew_max from public.ship_classes c where c.id = s.class_id) where s.id = v_ship;
    v_built := v_built || jsonb_build_object(v_c.job, v_fl, v_c.job || '_class', v_c.code);
    v_fleets := v_fleets || v_fl;
  end loop;
  if v_n <> 8 or not (v_built ?& array['raider', 'gunship', 'boarder', 'line', 'escort', 'armed', 'carrier', 'plain']) then
    raise exception 'PROOF 67 FAIL: not every job found a hull to lay down: %', v_built;
  end if;
  raise notice 'PASS: MORE_SHIPS_BUILD — laid down by cmd.do_build at their own lines'' yards: raider %, gunship %, boarder %, line %, escort %, armed %, carrier %, plain %',
    v_built ->> 'raider_class', v_built ->> 'gunship_class', v_built ->> 'boarder_class', v_built ->> 'line_class', v_built ->> 'escort_class', v_built ->> 'armed_class',
    v_built ->> 'carrier_class', v_built ->> 'plain_class';

  -- ── THE FIGHTS, THROUGH THE ENGINE, ON THE BUILT SHIPS ──
  -- reach: the gunship's fleet set upon by the boarder's
  v_a := voyage.fleet_hulls((v_built ->> 'gunship')::uuid);
  v_b := voyage.fleet_hulls((v_built ->> 'boarder')::uuid);
  if (select max((x ->> 'reach')::numeric) from jsonb_array_elements(v_a) x where (x ->> 'attack')::numeric > 0)
     <= (select max((x ->> 'reach')::numeric) from jsonb_array_elements(v_b) x where (x ->> 'attack')::numeric > 0) then
    raise exception 'PROOF 67 FAIL: the built gunship does not out-reach the built boarder: % against %', v_a, v_b;
  end if;
  for v_i in 1 .. c_seeds loop
    v_f := public.fight_sides(md5('proof67:reach:' || v_i)::uuid, 1, v_a, v_b, '{}'::jsonb);
    v_f2 := public.fight_sides(md5('proof67:reach:' || v_i)::uuid, 1, v_a, v_b, '{}'::jsonb);
    if v_f is distinct from v_f2 or v_f ->> 'outcome' not in ('EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED') then
      raise exception 'PROOF 67 FAIL: the same fight twice is not the same fight, or it has no ending: %', v_f;
    end if;
    if exists (select 1 from jsonb_array_elements(v_f -> 'rounds') r where r ->> 'range' = 'LONG' and (r -> 'b' ->> 'fired')::int <> 0) then
      raise exception 'PROOF 67 FAIL: the shorter reach fired at long range: %', v_f;
    end if;
    v_long := v_long + (select count(*) from jsonb_array_elements(v_f -> 'rounds') r where r ->> 'range' = 'LONG' and (r -> 'a' ->> 'fired')::int > 0)::int;
  end loop;
  if v_long = 0 then
    raise exception 'PROOF 67 FAIL: the gunship never fired a long round in % fights', c_seeds;
  end if;
  raise notice 'PASS: MORE_SHIPS_REACH — % fights of the built % set upon by the built %: % long rounds fired by the longer reach alone, none by the shorter; each fight the same twice',
    c_seeds, v_built ->> 'gunship_class', v_built ->> 'boarder_class', v_long;

  -- crew: the boarder's fleet set upon by a raid of one xebec (voyage.raider_hulls, as a raid is built)
  v_a := voyage.fleet_hulls((v_built ->> 'boarder')::uuid);
  v_held := 0;
  for v_i in 1 .. c_seeds loop
    v_f := public.fight_sides(md5('proof67:crew:' || v_i)::uuid, 1, v_a, voyage.raider_hulls(12.7), '{}'::jsonb);
    if v_f ->> 'outcome' in ('RANSOM', 'PLUNDERED') then
      raise exception 'PROOF 67 FAIL: a boarder with her full crew was taken by one xebec: %', v_f;
    end if;
    v_held := v_held + 1;
  end loop;
  raise notice 'PASS: MORE_SHIPS_CREW — the built % held all % raids of one xebec', v_built ->> 'boarder_class', v_held;

  -- escort: the carrier's fleet alone (she and her house's barca), then the same side with the built escort beside them. A new house's fleet sails two ships
  -- (fleet room), so the escort is another house's hull, read through the same voyage.fleet_hulls and set beside the carrier's side.
  v_a := voyage.fleet_hulls((v_built ->> 'carrier')::uuid);
  v_b := v_a || (select jsonb_agg(x) from jsonb_array_elements(voyage.fleet_hulls((v_built ->> 'escort')::uuid)) x
                  where (x ->> 'id')::uuid in (select s.id from public.ships s join public.ship_classes c on c.id = s.class_id where c.code = v_built ->> 'escort_class'));
  if jsonb_array_length(v_a) <> 2 or jsonb_array_length(v_b) <> 3 then
    raise exception 'PROOF 67 FAIL: the sides are not the carrier with her barca, and those two with one escort: %', v_b;
  end if;
  v_held := 0;
  v_held2 := 0;
  for v_i in 1 .. c_seeds loop
    if public.fight_sides(md5('proof67:escort:' || v_i)::uuid, 1, v_a, voyage.raider_hulls(12.7), '{}'::jsonb) ->> 'outcome' in ('EVADED', 'DRIVEN_OFF') then
      v_held := v_held + 1;
    end if;
    if public.fight_sides(md5('proof67:escort:' || v_i)::uuid, 1, v_b, voyage.raider_hulls(12.7), '{}'::jsonb) ->> 'outcome' in ('EVADED', 'DRIVEN_OFF') then
      v_held2 := v_held2 + 1;
    end if;
  end loop;
  if v_held <> 0 or v_held2 * 2 <= c_seeds then
    raise exception 'PROOF 67 FAIL: the carrier alone held % of % raids (wanted none) and with her escort % (wanted most)', v_held, c_seeds, v_held2;
  end if;
  raise notice 'PASS: MORE_SHIPS_ESCORT — the built % alone held 0 of % raids of one xebec; with the built % beside her, % of %',
    v_built ->> 'carrier_class', c_seeds, v_built ->> 'escort_class', v_held2, c_seeds;

  -- ── NO NPC IS GIVEN ONE ──
  if exists (select 1 from public.npc_line_hulls x where x.class_code = any (v_new) or x.live_class = any (v_new))
     or exists (select 1 from public.npc_loadouts x where x.class_code = any (v_new))
     or exists (select 1 from public.world_config k where jsonb_typeof(k.value) = 'string' and k.value #>> '{}' = any (v_new))
     or exists (select 1 from public.crown_classes() c where c.class_code = any (v_new))
     or exists (select 1 from public.ships s join public.ship_classes c on c.id = s.class_id
                 where c.code = any (v_new) and s.fleet_id <> all (v_fleets)) then
    raise exception 'PROOF 67 FAIL: a merchant, a loadout, a knob, a crown or a ship that is not this proof''s names a new class';
  end if;
  -- the raiders' class, as docs/COMBAT_LOG.md 2.5 reads it, and one xebec of raid is one xebec
  if (select row(c.durability, c.crew_required, c.attack, c.accuracy, c.reach, c.armour, c.sighting::int, c.tier)::text from public.ship_classes c where c.code = 'xebec') <> '(530,35,60,38,26,12,11,2)'
     or (voyage.raider_hulls(12.7) -> 0 ->> 'hull')::numeric <> 530 or (voyage.raider_hulls(12.7) -> 0 ->> 'crew')::numeric <> 35 or (voyage.raider_hulls(12.7) -> 0 ->> 'class') <> 'xebec' then
    raise exception 'PROOF 67 FAIL: the raiders'' class moved: %', voyage.raider_hulls(12.7);
  end if;
  raise notice 'PASS: MORE_SHIPS_NPC — no merchant, loadout, knob, crown or NPC ship names a new class; one xebec of raid is still hull 530, crew 35, attack 60';
end
$$;
