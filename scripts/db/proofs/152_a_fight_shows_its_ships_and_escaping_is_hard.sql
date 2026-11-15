-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 152 - A FIGHT SHOWS ITS SHIPS, AND ESCAPING IS HARD  (migration 0450; docs/dev-log/2026-11-16-battle-stats.md; the owner, 2026-11-16: "in
--   fight, i want to see levels, their stats, their crew state, equipments, etc. levels, escaping should be hard")
--
--   Proof 136's scene, lit as prod is: a hunting pirate at her haunt raids a company's merchant 60 miles off through the pirates' minute job, with
--   levels_bite on and the merchant's hull worked up to level 4. Then the engine itself (public.tick_fight) on fixed sheets, where each term of a
--   run's chance is read alone. Rolled back with proof.mjs's transaction. Nothing here assumes who wins.
--
-- @pass BS_SHEET   the raid's sheet carries every hull's card at its open: her level (public.ship_level), class, guns, the crew she needs and may carry, speed, handling, everything fitted, her captains
-- @pass BS_READ    world.battle_ticks serves `ships` a and b in the timeline's order, without ids; each ship of the timeline carries her level; the timeline serves the run's chance (`rc`)
-- @pass BS_FROZEN  she is worked up further and refitted after the open: a re-run reads the sheet, the card and the fight unmoved
-- @pass BS_MAP     world.fights serves each side's level (her fleet's best) beside her ship count
-- @pass BS_FIGHTS  a level already fights: world.ship_stats gives a worked-up hull more accuracy and sighting (0127), so 0450 adds no second to-hit by level
-- @pass BS_LEVEL   a run's chance: +flee_per_level a level ahead, -flee_per_level a level behind, never beyond flee_level_max either way
-- @pass BS_HURT    a crippled hull or a short crew runs worse: nothing at flee_hurt_under or above, flee_hurt_max at nothing, in proportion between; the worse of the two counts
-- @pass BS_TRIES   on a sheet that runs to the boarding: her guns are silent for the 20 ticks of each run, every roll is the chance served for its tick, and each failed roll makes the next flee_per_try worse, down to the floor
-- @pass BS_BOUNDS  a raid's run is held within raid_flee_floor..raid_flee_max (3..45 %); any other run within 0357's fight_flee_floor..fight_evade_max, the same terms
-- @pass BS_OLD     the rollback is the knobs: with raid_flee_floor 0.10, raid_flee_max 0.80, raid_flee_base 0.15 and the three new terms 0, every roll is 0432's chance to the digit
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.lie_152(p_fleet uuid, p_lat numeric, p_lon numeric) returns void language sql as $f$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p_lat, lon = p_lon, busy_until = null, ready_at = null, version = f.version + 1 where f.id = p_fleet;
$f$;

-- the chance side a would run on at tick 0 of a fight (nobody hurt by a shot yet, nobody caught yet)
create function pg_temp.open_152(p_a jsonb, p_b jsonb, p_opts jsonb) returns numeric language sql as $f$
  select (public.tick_fight('00000000-0450-4000-8000-0000000149aa'::uuid, p_a, p_b, p_opts) #>> '{rc,a,0,1}')::numeric;
$f$;

update public.world_config set value = case key when 'pirate_strike_from_port' then 'true'::jsonb else to_jsonb(720) end where key in ('pirate_strike_from_port', 'pirate_port_minutes');   -- 0445: this proof's pirate lies at her haunt and raids from it, as proof 136's does (0427's world, by 0445's two way-back knobs); the cruise and the raid under sail are proof 147's

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_uid   uuid := '00000000-0450-4000-8000-0000000000c1';
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_pf    uuid;
  v_m     uuid;
  v_ms    uuid;
  v_hp    uuid;
  v_lat   numeric;
  v_lon   numeric;
  v_r     jsonb;
  v_b     public.battles%rowtype;
  v_tl    jsonb;
  v_x     jsonb;
  v_card  jsonb;
  v_ha    jsonb;
  v_hb    jsonb;
  v_o     jsonb := '{"a_ai": "FLEE", "a_flee": 0.15}'::jsonb;
  v_f     jsonb;
  v_acc1  numeric;
  v_acc4  numeric;
  v_per   numeric := public.wc_num('flee_per_level') * 100;
  v_lmax  numeric := public.wc_num('flee_level_max') * 100;
  v_hurt  numeric := public.wc_num('flee_hurt_max') * 100;
  v_try   numeric := public.wc_num('flee_per_try') * 100;
  v_lo    numeric := round(public.wc_num('raid_flee_floor') * 100);
  v_hi    numeric := round(public.wc_num('raid_flee_max') * 100);
  v_base  numeric;
  v_prev  numeric;
  v_n     int := 0;
  v_low   int := 0;
  r       record;
begin
  -- ── THE SCENE (proof 136's), with levels lit and the merchant's hull worked up ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'pirates_bite', 'npc_refits_enabled', 'attack_enabled', 'levels_bite') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_trade', 'convoys_enabled') and value is distinct from 'false'::jsonb;
  update public.world_config set value = '["RAID", "ATTACK"]'::jsonb where key = 'tick_fight_kinds';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.port_treasury t set ducats = 900000000 where t.port_id = public.pirate_capital();
  update public.pirate_ships set laid_up_at = t0 where laid_up_at is null;
  update public.world_config set value = to_jsonb(0) where key = 'pirate_wakes_per_run';
  update public.pirate_clock set added_at = t0 + interval '1 hour', paid_at = t0 + interval '1 hour';
  select q.ord into r from public.pirate_roster q where q.hub_port = v_hub and q.ord % 1000 = 6;
  v_pf := public.pirate_commission_fleet(r.ord, public.refit_yard(v_hub), t0);
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  select h.port_id, h.sea_id into r from public.pirate_haunt_of(v_hub, (select x.ord from public.pirate_ships x where x.fleet_id = v_pf)) h;
  update public.fleets f set port_id = r.port_id, status = 'DOCKED', ready_at = null where f.id = v_pf;
  update public.pirate_ships x set sea_id = r.sea_id, mission = 'CRUISE', haunt_port = r.port_id, haunt_since = t0 where x.fleet_id = v_pf;
  select p.lat, p.lon into v_lat, v_lon from voyage.fleet_point(v_pf, t0) p;
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = coalesce(f.port_id, v_hub), lat = null, lon = null, busy_until = null where f.status in ('SAILING', 'ANCHORED');
  select nf.fleet_id into v_m
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from public.pirate_nation() and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;
  select s.id into v_ms from public.ships s where s.fleet_id = v_m order by s.is_flagship desc, s.created_at, s.id limit 1;

  -- ── BS_FIGHTS: what a level already does in a fight, read before and after she is worked up ──
  delete from public.ship_xp sx where sx.ship_id = v_ms;
  v_x := world.ship_stats(v_ms);
  v_acc1 := (v_x ->> 'accuracy')::numeric;
  insert into public.ship_xp (ship_id, xp) values (v_ms, public.level_points(4));
  if public.ship_level(v_ms) <> 4 then
    raise exception 'PROOF 152 FAIL: a hull with the points of level 4 reads level %', public.ship_level(v_ms);
  end if;
  v_acc4 := (world.ship_stats(v_ms) ->> 'accuracy')::numeric;
  if v_acc4 <> v_acc1 + 3 * public.wc_num('ship_level_accuracy_per_level')
     or (world.ship_stats(v_ms) ->> 'sighting')::numeric <> (v_x ->> 'sighting')::numeric + 3 * public.wc_num('ship_level_sighting_per_level') then
    raise exception 'PROOF 152 FAIL: level 4 does not give her 3 levels of accuracy and sighting: accuracy % -> %', v_acc1, v_acc4;
  end if;
  raise notice 'PASS: BS_FIGHTS — level 1 -> 4: accuracy % -> % (+% a level), sighting +% a level: her level is in her to-hit already', v_acc1, v_acc4,
    public.wc_num('ship_level_accuracy_per_level'), public.wc_num('ship_level_sighting_per_level');

  perform pg_temp.lie_152(v_m, v_lat + 1, v_lon);   -- sixty miles north
  v_hp := public.new_house(v_uid, 'Casa Ficha 152', 'PRT', 'LIS', 'Ficha 152', 'galion', 'Ficha 152', null, false);   -- a reader (her ship stays in port)

  -- ── BS_SHEET ──
  v_r := public.tick_pirates(t0);
  select b.* into v_b from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_m and s.side = 'DEFENDER';
  if v_b.id is null or v_b.kind <> 'RAID' or v_b.ticks is null then
    raise exception 'PROOF 152 FAIL: the job did not raid the merchant tick by tick: %', v_r;
  end if;
  v_tl := v_b.ticks;
  for r in select h, k from (select h, 'a' as k from jsonb_array_elements(v_b.sheet -> 'a') h union all select h, 'b' from jsonb_array_elements(v_b.sheet -> 'b') h) z loop
    v_n := v_n + 1;
    if not (r.h ?& array['lv', 'cls', 'guns', 'crew_need', 'crew_max', 'speed', 'handling', 'fit', 'caps'])
       or (r.h ->> 'lv')::int <> public.ship_level((r.h ->> 'id')::uuid)
       or (r.h ->> 'cls') is distinct from (select c.name from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = (r.h ->> 'id')::uuid)
       or (r.h ->> 'guns')::int is distinct from (select c.guns from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = (r.h ->> 'id')::uuid)
       or (r.h ->> 'crew_need')::int is distinct from (select c.crew_required from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = (r.h ->> 'id')::uuid)
       or (r.h ->> 'crew_max')::numeric is distinct from (select sb.crew_max from public.ship_base((r.h ->> 'id')::uuid) sb)
       or (r.h ->> 'speed')::numeric is distinct from (world.ship_stats((r.h ->> 'id')::uuid) ->> 'speed')::numeric
       or (r.h ->> 'handling')::numeric is distinct from (world.ship_stats((r.h ->> 'id')::uuid) ->> 'handling')::numeric
       or jsonb_array_length(r.h -> 'fit') <> (select count(*) from public.fitted_units fu where fu.ship_id = (r.h ->> 'id')::uuid)
       or exists (select 1 from jsonb_array_elements(r.h -> 'fit') f where not (f ?& array['n', 's']))
       or jsonb_array_length(r.h -> 'caps') <> (select count(*) from public.captain_seats cs where cs.ship_id = (r.h ->> 'id')::uuid) then
      raise exception 'PROOF 152 FAIL: a hull of side % has no true card: %', r.k, r.h;
    end if;
  end loop;
  v_card := (select h from jsonb_array_elements(v_b.sheet -> 'a') h where (h ->> 'id')::uuid = v_ms);
  if v_card is null or (v_card ->> 'lv')::int <> 4 or (v_card ->> 'accuracy')::numeric <> v_acc4 then
    raise exception 'PROOF 152 FAIL: the merchant worked up to level 4 is not on the sheet at level 4 with its accuracy: %', v_card;
  end if;
  raise notice 'PASS: BS_SHEET — % hull(s), each with her card; the merchant % Lv % (%, % guns, crew %/% of % needed, % kn, handling %, % fitted) against % Lv %',
    v_n, v_card ->> 'name', v_card ->> 'lv', v_card ->> 'cls', v_card ->> 'guns', v_card ->> 'crew', v_card ->> 'crew_max', v_card ->> 'crew_need', v_card ->> 'speed',
    v_card ->> 'handling', jsonb_array_length(v_card -> 'fit'), v_b.sheet #>> '{b,0,name}', v_b.sheet #>> '{b,0,lv}';

  -- ── BS_READ ──
  perform cmd.assume_identity(v_uid);
  v_x := world.battle_ticks(v_b.id);
  if not coalesce((v_x ->> 'on')::boolean, false) or jsonb_array_length(v_x #> '{ships,a}') <> jsonb_array_length(v_tl -> 'a')
     or jsonb_array_length(v_x #> '{ships,b}') <> jsonb_array_length(v_tl -> 'b') then
    raise exception 'PROOF 152 FAIL: the read does not serve a ship for every ship of the timeline: %', left((v_x -> 'ships')::text, 300);
  end if;
  if exists (select 1 from (select 'a' as k union all select 'b') s
              cross join lateral jsonb_array_elements(v_x -> 'ships' -> s.k) with ordinality q(h, o)
              where q.h ? 'id' or q.h ? 'boarder_pct' or q.h ->> 'name' is distinct from (v_tl -> s.k -> (q.o::int - 1) ->> 'n')
                 or (q.h ->> 'lv')::numeric is distinct from (v_tl -> s.k -> (q.o::int - 1) ->> 'lv')::numeric
                 or (q.h ->> 'hull')::numeric is distinct from (v_tl -> s.k -> (q.o::int - 1) ->> 'h')::numeric) then
    raise exception 'PROOF 152 FAIL: the ships served are not the timeline''s, in its order, without ids: %', left((v_x -> 'ships')::text, 400);
  end if;
  if jsonb_typeof(v_tl #> '{rc,a}') <> 'array' or jsonb_array_length(v_tl #> '{rc,a}') < 1 or (v_tl #>> '{rc,a,0,0}')::int <> 0
     or (v_tl #>> '{rc,a,0,1}')::numeric not between v_lo and v_hi then
    raise exception 'PROOF 152 FAIL: the timeline does not serve the chance she would run on from tick 0: %', v_tl -> 'rc';
  end if;
  raise notice 'PASS: BS_READ — ships a % / b % in the timeline''s order, no ids; she would run on % %% at the open (% change(s) served)',
    jsonb_array_length(v_x #> '{ships,a}'), jsonb_array_length(v_x #> '{ships,b}'), v_tl #>> '{rc,a,0,1}', jsonb_array_length(v_tl #> '{rc,a}');

  -- ── BS_MAP ──
  select c into v_x from jsonb_array_elements(world.fights() -> 'fights') c where c ->> 'id' = v_b.id::text;
  if v_x is null or exists (select 1 from jsonb_array_elements(v_x -> 'sides') sd
                             where (sd ->> 'lv')::int is distinct from (select max(public.ship_level(sh.id)) from public.ships sh where sh.fleet_id = (sd ->> 'fleet')::uuid)
                                or (sd ->> 'ships')::int is distinct from (select count(*)::int from public.ships sh where sh.fleet_id = (sd ->> 'fleet')::uuid)) then
    raise exception 'PROOF 152 FAIL: the map''s card does not say each side''s level and ships: %', v_x -> 'sides';
  end if;
  raise notice 'PASS: BS_MAP — %', (select string_agg(format('%s Lv %s, %s ship(s)', sd ->> 'side', sd ->> 'lv', sd ->> 'ships'), '; ') from jsonb_array_elements(v_x -> 'sides') sd);

  -- ── BS_FROZEN ──
  update public.ship_xp set xp = public.level_points(9) where ship_id = v_ms;
  delete from public.fitted_units fu where fu.ship_id = v_ms;
  update public.ships s set crew = 1 where s.id = v_ms;
  v_f := public.tick_battle_run(v_b.id);   -- its own statement: the row it writes is read by the next one
  if (select b.sheet from public.battles b where b.id = v_b.id)::text <> v_b.sheet::text or (v_f -> 'e')::text <> (v_tl -> 'e')::text
     or (v_f -> 'rc')::text <> (v_tl -> 'rc')::text or (v_f ->> 'k')::int <> 1 then
    raise exception 'PROOF 152 FAIL: a re-run after she was worked up, stripped and unmanned moved the sheet or the fight';
  end if;
  raise notice 'PASS: BS_FROZEN — level 4 -> 9, gear off, crew 1 after the open: the re-run (k 1) is the same sheet, the same % events, the same chances', jsonb_array_length(v_f -> 'e');

  -- ── THE ENGINE ON FIXED SHEETS: a merchant that runs from a raider she cannot hurt, level with her (3), whole, fully manned ──
  v_ha := jsonb_build_array(jsonb_build_object('id', '00000000-0450-4000-8000-000000014901', 'name', 'Ficha', 'tier', 2, 'hull', 600, 'maxd', 600, 'crew', 12, 'crew_need', 12,
            'attack', 10, 'accuracy', 40, 'reach', 20, 'armour', 10, 'sighting', 8, 'boarder_pct', 0, 'lv', 3));
  v_hb := jsonb_build_array(jsonb_build_object('id', '00000000-0450-4000-8000-000000014902', 'name', 'Lobo', 'tier', 2, 'hull', 5000, 'maxd', 5000, 'crew', 60, 'crew_need', 40,
            'attack', 30, 'accuracy', 50, 'reach', 22, 'armour', 12, 'sighting', 8, 'boarder_pct', 0.1, 'lv', 3));
  v_base := pg_temp.open_152(v_ha, v_hb, v_o);
  if v_base <> round((public.wc_num('raid_flee_base') + 0.15) * 100) then
    raise exception 'PROOF 152 FAIL: level, whole and manned she would run on % %%, not raid_flee_base + her bonus', v_base;
  end if;

  -- ── BS_LEVEL ──
  if pg_temp.open_152(jsonb_set(v_ha, '{0,lv}', '4'), v_hb, v_o) <> v_base + v_per
     or pg_temp.open_152(jsonb_set(v_ha, '{0,lv}', '5'), v_hb, v_o) <> v_base + 2 * v_per
     or pg_temp.open_152(v_ha, jsonb_set(v_hb, '{0,lv}', '4'), v_o) <> v_base - v_per
     or pg_temp.open_152(v_ha, jsonb_set(v_hb, '{0,lv}', '5'), v_o) <> v_base - 2 * v_per
     or pg_temp.open_152(jsonb_set(v_ha, '{0,lv}', '30'), v_hb, v_o) <> v_base + v_lmax
     or pg_temp.open_152(v_ha, jsonb_set(v_hb, '{0,lv}', '30'), v_o) <> v_base - v_lmax
     or pg_temp.open_152(v_ha - 0 || jsonb_build_array((v_ha -> 0) - 'lv'), v_hb - 0 || jsonb_build_array((v_hb -> 0) - 'lv'), v_o) <> v_base then
    raise exception 'PROOF 152 FAIL: the level difference does not move the run by % a level within +-%: +1 %, +2 %, -1 %, -2 %, +27 %, -27 %', v_per, v_lmax,
      pg_temp.open_152(jsonb_set(v_ha, '{0,lv}', '4'), v_hb, v_o), pg_temp.open_152(jsonb_set(v_ha, '{0,lv}', '5'), v_hb, v_o),
      pg_temp.open_152(v_ha, jsonb_set(v_hb, '{0,lv}', '4'), v_o), pg_temp.open_152(v_ha, jsonb_set(v_hb, '{0,lv}', '5'), v_o),
      pg_temp.open_152(jsonb_set(v_ha, '{0,lv}', '30'), v_hb, v_o), pg_temp.open_152(v_ha, jsonb_set(v_hb, '{0,lv}', '30'), v_o);
  end if;
  raise notice 'PASS: BS_LEVEL — level with her foe % %%; a level ahead +%, two +%, a level behind -%, two -%; 27 ahead +% and 27 behind -% (the most); a sheet with no level: level',
    v_base, v_per, 2 * v_per, v_per, 2 * v_per, v_lmax, v_lmax;

  -- ── BS_HURT ──
  if pg_temp.open_152(jsonb_set(v_ha, '{0,hull}', '300'), v_hb, v_o) <> v_base
     or pg_temp.open_152(jsonb_set(v_ha, '{0,hull}', '150'), v_hb, v_o) <> v_base - v_hurt / 2
     or pg_temp.open_152(jsonb_set(v_ha, '{0,hull}', '30'), v_hb, v_o) <> v_base - v_hurt * 0.9
     or pg_temp.open_152(jsonb_set(v_ha, '{0,crew}', '6'), v_hb, v_o) <> v_base
     or pg_temp.open_152(jsonb_set(v_ha, '{0,crew}', '3'), v_hb, v_o) <> v_base - v_hurt / 2
     or pg_temp.open_152(jsonb_set(jsonb_set(v_ha, '{0,crew}', '3'), '{0,hull}', '30'), v_hb, v_o) <> v_base - v_hurt * 0.9
     or pg_temp.open_152(jsonb_set(v_ha, '{0,crew}', '40'), v_hb, v_o) <> v_base then
    raise exception 'PROOF 152 FAIL: her state does not move the run as the rule says: half hull %, quarter %, a twentieth %, half crew %, quarter %, both %',
      pg_temp.open_152(jsonb_set(v_ha, '{0,hull}', '300'), v_hb, v_o), pg_temp.open_152(jsonb_set(v_ha, '{0,hull}', '150'), v_hb, v_o),
      pg_temp.open_152(jsonb_set(v_ha, '{0,hull}', '30'), v_hb, v_o), pg_temp.open_152(jsonb_set(v_ha, '{0,crew}', '6'), v_hb, v_o),
      pg_temp.open_152(jsonb_set(v_ha, '{0,crew}', '3'), v_hb, v_o), pg_temp.open_152(jsonb_set(jsonb_set(v_ha, '{0,crew}', '3'), '{0,hull}', '30'), v_hb, v_o);
  end if;
  raise notice 'PASS: BS_HURT — whole % %%; half her hull %, a quarter %, a twentieth %; half the crew she needs %, a quarter %; both low: the worse of the two (%)',
    v_base, v_base, v_base - v_hurt / 2, v_base - v_hurt * 0.9, v_base, v_base - v_hurt / 2, v_base - v_hurt * 0.9;

  -- ── BS_BOUNDS ──
  if pg_temp.open_152(v_ha, v_hb, v_o || '{"a_flee": 5}'::jsonb) <> v_hi or pg_temp.open_152(v_ha, v_hb, v_o || '{"a_flee": -5}'::jsonb) <> v_lo
     or pg_temp.open_152(jsonb_set(v_ha, '{0,lv}', '30'), v_hb, v_o || '{"a_flee": 5}'::jsonb) <> v_hi
     or pg_temp.open_152(jsonb_set(v_ha, '{0,hull}', '30'), v_hb, v_o || '{"a_flee": -5}'::jsonb) <> v_lo then
    raise exception 'PROOF 152 FAIL: a raid''s run is not held within % .. %', v_lo, v_hi;
  end if;
  -- a run that is not the side set upon in a raid (no a_flee): 0357's base, floor and cap, the same level term
  if pg_temp.open_152(v_ha, v_hb, '{"a_ai": "FLEE"}'::jsonb) <> round(public.wc_num('fight_flee_base') * 100)
     or pg_temp.open_152(jsonb_set(v_ha, '{0,lv}', '5'), v_hb, '{"a_ai": "FLEE"}'::jsonb) <> round(public.wc_num('fight_flee_base') * 100) + 2 * v_per
     or pg_temp.open_152(jsonb_set(v_ha, '{0,lv}', '30'), v_hb, '{"a_ai": "FLEE"}'::jsonb) <> round(public.wc_num('fight_evade_max') * 100)
     or pg_temp.open_152(v_ha, jsonb_set(v_hb, '{0,lv}', '30'), '{"a_ai": "FLEE"}'::jsonb) <> round(public.wc_num('fight_flee_floor') * 100) then
    raise exception 'PROOF 152 FAIL: a run outside a raid is not 0357''s base within its floor and cap with the level term';
  end if;
  raise notice 'PASS: BS_BOUNDS — a raid''s run % .. % %% whatever her bonus, level or state; any other run base % within % .. % %%', v_lo, v_hi,
    round(public.wc_num('fight_flee_base') * 100), round(public.wc_num('fight_flee_floor') * 100), round(public.wc_num('fight_evade_max') * 100);

  -- ── BS_TRIES: hulls so large and guns so light that it runs to the boarding in every world (proof 140's sheet); she runs again and again ──
  v_ha := jsonb_build_array(jsonb_build_object('id', '00000000-0450-4000-8000-000000014903', 'name', 'Ficha', 'tier', 2, 'hull', 100000, 'maxd', 100000, 'crew', 40, 'crew_need', 40,
            'attack', 6, 'accuracy', 50, 'reach', 20, 'armour', 0, 'sighting', 8, 'boarder_pct', 0, 'lv', 3));
  v_hb := jsonb_build_array(jsonb_build_object('id', '00000000-0450-4000-8000-000000014904', 'name', 'Lobo', 'tier', 2, 'hull', 100000, 'maxd', 100000, 'crew', 60, 'crew_need', 40,
            'attack', 6, 'accuracy', 50, 'reach', 20, 'armour', 0, 'sighting', 8, 'boarder_pct', 0, 'lv', 3));
  -- a seed whose every roll fails is not promised: take the first of a few seeds on which she is caught at least three times
  for r in select g from generate_series(1, 40) g loop
    v_f := public.tick_fight(('00000000-0450-4000-8000-0000001490' || lpad(r.g::text, 2, '0'))::uuid, v_ha, v_hb, v_o);
    exit when (select count(*) from jsonb_array_elements(v_f -> 'e') e where e ->> 2 = 'X' and e ->> 1 = '0' and e ->> 4 = '0') >= 3;
    v_f := null;
  end loop;
  if v_f is null then
    raise exception 'PROOF 152 FAIL: in 40 fights she was never caught three times: the run is not hard';
  end if;
  v_prev := null; v_n := 0;
  for r in select (e ->> 0)::int as t, (e ->> 3)::numeric as pct, e ->> 4 as away, o from jsonb_array_elements(v_f -> 'e') with ordinality q(e, o) where e ->> 2 = 'X' and e ->> 1 = '0' order by o loop
    v_n := v_n + 1;
    if r.pct is distinct from (select (c ->> 1)::numeric from jsonb_array_elements(v_f #> '{rc,a}') with ordinality z(c, o) where (c ->> 0)::int <= r.t order by o desc limit 1) then
      raise exception 'PROOF 152 FAIL: the roll at tick % was on % %%, not the chance served for that tick', r.t, r.pct;
    end if;
    if not exists (select 1 from jsonb_array_elements(v_f -> 'e') e where e ->> 2 = 'U' and e ->> 1 = '0' and e ->> 3 = 'RN' and (e ->> 0)::int = r.t - 20)
       or exists (select 1 from jsonb_array_elements(v_f -> 'e') e where e ->> 1 = '0' and e ->> 2 in ('A', 'BS', 'CH', 'RK', 'GR') and (e ->> 0)::int > r.t - 20 and (e ->> 0)::int <= r.t) then
      raise exception 'PROOF 152 FAIL: the roll at tick % does not end 20 ticks of silent guns', r.t;
    end if;
    if v_prev is not null and r.pct <> greatest(v_lo, v_prev - v_try) then
      raise exception 'PROOF 152 FAIL: after a failed roll on % %% the next was on % %%, not % lower (floor %)', v_prev, r.pct, v_try, v_lo;
    end if;
    if r.pct = v_lo then v_low := v_low + 1; end if;
    v_prev := r.pct;
  end loop;
  raise notice 'PASS: BS_TRIES — % roll(s): % (each after 20 silent ticks, each the chance served, each % lower than the last down to the floor %)',
    v_n, (select string_agg((e ->> 3) || ' %', ', ' order by o) from jsonb_array_elements(v_f -> 'e') with ordinality q(e, o) where e ->> 2 = 'X' and e ->> 1 = '0'), v_try, v_lo;

  -- ── BS_OLD: the rollback is the knobs ──
  update public.world_config set value = to_jsonb(0.10) where key = 'raid_flee_floor';
  update public.world_config set value = to_jsonb(0.80) where key = 'raid_flee_max';
  update public.world_config set value = to_jsonb(0.15) where key = 'raid_flee_base';
  update public.world_config set value = to_jsonb(0) where key in ('flee_per_level', 'flee_hurt_max', 'flee_per_try');
  v_n := 0;
  for r in select g, s from generate_series(1, 6) g cross join (values (-4), (0), (9)) z(s) loop
    v_f := public.tick_fight(('00000000-0450-4000-8000-0000001491' || lpad(r.g::text, 2, '0'))::uuid, jsonb_set(jsonb_set(v_ha, '{0,sighting}', to_jsonb(8 + r.s)), '{0,lv}', to_jsonb(r.g)), v_hb,
                             jsonb_build_object('a_ai', 'FLEE', 'a_flee', (r.g - 3) * 0.07));
    for v_x in select e from jsonb_array_elements(v_f -> 'e') e where e ->> 2 = 'X' and e ->> 1 = '0' loop
      v_n := v_n + 1;
      if (v_x ->> 3)::numeric <> round(least(0.80, greatest(0.10, public.wc_num('fight_flee_base') + r.s * public.wc_num('fight_evade_per_sighting') + (r.g - 3) * 0.07)) * 100) then
        raise exception 'PROOF 152 FAIL: under the old knobs a roll was on % %%, not 0432''s chance (sighting lead %, bonus %)', v_x ->> 3, r.s, (r.g - 3) * 0.07;
      end if;
    end loop;
  end loop;
  if v_n < 6 then
    raise exception 'PROOF 152 FAIL: only % roll(s) under the old knobs: nothing was compared', v_n;
  end if;
  raise notice 'PASS: BS_OLD — % roll(s) over 18 fights (levels 1-6, sighting leads -4, 0, +9, bonuses -0.14..+0.21): each 0432''s chance to the digit', v_n;
end $p$;
