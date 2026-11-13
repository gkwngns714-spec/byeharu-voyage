-- 0372 RAIDS SCENE: what does npc_ship_level_enabled (0344: cargo, navy and pirate hulls at level 5) do to a fight? Measured by the REAL engine on the cached world, level 1 against level 5.
--   node scripts/ops/harness/more-ships/q.mjs scripts/ops/harness/crown-level/raids-scene.sql
-- Three company fleets of REAL hulls, read as a fight reads them (voyage.fleet_hulls): a BARCA (no guns), an ARMED TRADER (one navire) and a NAU. Three raider squadrons of 1, 2 and 5 REAL
-- xebecs (pirate_ship_class), each a crown house's fleet (public.crown_house) so that public.crown_hull_level_fix, the one writer of 0344, gives them their level. Each pair is fought twice,
-- with the switch dark (level 1) and lit (level 5), over c_n seeds:
--   RAID   the way the game fights a raid on a voyage today: the raiders are a FIGURE (voyage.pirate_strength for a named pirate ship, the sea's danger for an anonymous raid) that
--          voyage.raider_hulls turns into class hulls. Through voyage.raid_report, the skin voyage.settle calls.
--   HULLS  hull against hull: public.fight_sides with the squadron's own hulls as the other side (voyage.fleet_hulls). This is how a BATTLE reads a crown hull (0323: a company attacks a
--          cargo, navy or pirate ship; 0333 / 0334 the navy comes; 0340 the navy against a pirate ship). It is NOT how a raid is fought.
-- And one crown hull set upon: a CARGO SHIP (an armed navire of a crown house) against anonymous raids of 12.7 and 63.5, dark and lit (CARGO lines).
-- Prints LEVELS: lines. LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server
-- (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  c_n     constant int := 500;
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_prt   uuid := (select n.id from public.nations n where n.code = 'PRT');
  v_xebec text := public.wc_text('pirate_ship_class');
  v_pl    uuid;
  v_fl    uuid;
  v_who   text;
  v_k     int;
  v_lvl   int;
  i       int;
  d       int;
  v_n     int;
  v_a     jsonb;
  v_b     jsonb;
  v_esc   numeric;
  v_fig   numeric;
  v_f     jsonb;
  v_ends  jsonb;
  v_al    numeric;
  v_bl    numeric;
  v_a0    numeric;
  v_b0    numeric;
  v_raid  numeric;
  ours    jsonb := '{}'::jsonb;   -- who -> fleet id
  theirs  jsonb := '{}'::jsonb;   -- n -> {fleet, player}
  v_cargo uuid;
  v_cpl   uuid;
begin
  update public.world_config set value = 'true'::jsonb where key in ('combat_bite', 'levels_bite');
  -- the company fleets
  foreach v_who in array array['barca', 'navire', 'nau'] loop
    insert into public.players (company_name, nation_id, ducats) values ('Levels 0372 ' || v_who, v_prt, 1000000) returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Levels ' || v_who, v_lis);
    perform public.commission_ship(v_pl, v_fl, v_who, 'Probe ' || v_who, true, true);
    ours := ours || jsonb_build_object(v_who, v_fl);
    v_a := voyage.fleet_hulls(v_fl);
    raise notice 'LEVELS: company % = hull %, crew %, attack %, accuracy %, reach %, armour %, sighting %', v_who, v_a -> 0 ->> 'hull', v_a -> 0 ->> 'crew', v_a -> 0 ->> 'attack',
      v_a -> 0 ->> 'accuracy', v_a -> 0 ->> 'reach', v_a -> 0 ->> 'armour', v_a -> 0 ->> 'sighting';
  end loop;
  -- the raider squadrons: crown houses (a navy_ships row makes public.crown_house true, as 0344's own probe does), 1, 2 and 5 xebecs
  foreach v_k in array array[1, 2, 5] loop
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Raiders 0372 x' || v_k, v_prt, 0, true) returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Raiders x' || v_k, v_lis);
    for i in 1 .. v_k loop
      perform public.commission_ship(v_pl, v_fl, v_xebec, 'Raider ' || v_k || '-' || i, i = 1, true);
    end loop;
    insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port)
    values (v_fl, v_pl, v_prt, 1 + coalesce((select max(x.ord) from public.navy_ships x where x.nation_id = v_prt), 0), v_lis, v_lis);
    theirs := theirs || jsonb_build_object(v_k::text, jsonb_build_object('fleet', v_fl, 'player', v_pl));
  end loop;
  -- a crown cargo hull: an armed navire of a crown house
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Cargo 0372', v_prt, 0, true) returning id into v_cpl;
  v_cargo := public.form_fleet(v_cpl, 'Cargo 0372', v_lis);
  perform public.commission_ship(v_cpl, v_cargo, 'navire', 'Cargo 0372', true, true);
  insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port)
  values (v_cargo, v_cpl, v_prt, 1 + coalesce((select max(x.ord) from public.navy_ships x where x.nation_id = v_prt), 0), v_lis, v_lis);

  foreach v_lvl in array array[1, 5] loop
    update public.world_config set value = to_jsonb(v_lvl = 5) where key = 'npc_ship_level_enabled';
    v_n := public.crown_hull_level_fix();
    v_b := voyage.fleet_hulls((theirs -> '1' ->> 'fleet')::uuid);
    raise notice 'LEVELS: level % | one raider hull (%) = hull %, crew %, attack %, accuracy %, reach %, armour %, sighting %; as a raid figure %', v_lvl, v_xebec, v_b -> 0 ->> 'hull', v_b -> 0 ->> 'crew',
      v_b -> 0 ->> 'attack', v_b -> 0 ->> 'accuracy', v_b -> 0 ->> 'reach', v_b -> 0 ->> 'armour', v_b -> 0 ->> 'sighting', round(voyage.pirate_strength((theirs -> '1' ->> 'fleet')::uuid), 2);
    foreach v_who in array array['barca', 'navire', 'nau'] loop
      v_a := voyage.fleet_hulls((ours ->> v_who)::uuid);
      v_esc := voyage.escort_score((ours ->> v_who)::uuid);
      v_a0 := (select sum((e ->> 'hull')::numeric) from jsonb_array_elements(v_a) e);
      foreach v_k in array array[1, 2, 5] loop
        v_b := voyage.fleet_hulls((theirs -> v_k::text ->> 'fleet')::uuid);
        v_b0 := (select sum((e ->> 'hull')::numeric) from jsonb_array_elements(v_b) e);
        v_fig := voyage.pirate_strength((theirs -> v_k::text ->> 'fleet')::uuid);
        -- RAID: as the game fights it
        v_ends := '{}'::jsonb; v_al := 0;
        for d in 1 .. c_n loop
          v_f := voyage.raid_report(md5('0372:' || v_who || v_k)::uuid, d, v_fig, v_esc, v_a, '{}'::jsonb);
          v_ends := jsonb_set(v_ends, array[v_f ->> 'outcome'], to_jsonb(coalesce((v_ends ->> (v_f ->> 'outcome'))::int, 0) + 1));
          v_al := v_al + (select coalesce(sum(x.value::numeric), 0) from jsonb_each_text(v_f -> 'hull_lost') x);
        end loop;
        raise notice 'LEVELS: RAID  | level % | % against % raider hull(s) (figure %) | % | her hull lost % %%', v_lvl, v_who, v_k, round(v_fig, 1), v_ends, round(v_al / c_n / v_a0 * 100, 1);
        -- HULLS: hull against hull
        v_ends := '{}'::jsonb; v_al := 0; v_bl := 0;
        for d in 1 .. c_n loop
          v_f := public.fight_sides(md5('0372:' || v_who || v_k)::uuid, d, v_a, v_b, '{}'::jsonb);
          v_ends := jsonb_set(v_ends, array[v_f ->> 'outcome'], to_jsonb(coalesce((v_ends ->> (v_f ->> 'outcome'))::int, 0) + 1));
          v_al := v_al + ((v_f -> 'hull' ->> 'a_start')::numeric - (v_f -> 'hull' ->> 'a')::numeric);
          v_bl := v_bl + ((v_f -> 'hull' ->> 'b_start')::numeric - (v_f -> 'hull' ->> 'b')::numeric);
        end loop;
        raise notice 'LEVELS: HULLS | level % | % against % raider hull(s) | % | her hull lost % %% | theirs lost % %%', v_lvl, v_who, v_k, v_ends, round(v_al / c_n / v_a0 * 100, 1), round(v_bl / c_n / v_b0 * 100, 1);
      end loop;
    end loop;
    -- CARGO: a crown hull set upon by an anonymous raid
    v_a := voyage.fleet_hulls(v_cargo);
    v_esc := voyage.escort_score(v_cargo);
    v_a0 := (select sum((e ->> 'hull')::numeric) from jsonb_array_elements(v_a) e);
    foreach v_raid in array array[12.7, 63.5] loop
      v_ends := '{}'::jsonb; v_al := 0;
      for d in 1 .. c_n loop
        v_f := voyage.raid_report(md5('0372:cargo')::uuid, d, v_raid, v_esc, v_a, '{}'::jsonb);
        v_ends := jsonb_set(v_ends, array[v_f ->> 'outcome'], to_jsonb(coalesce((v_ends ->> (v_f ->> 'outcome'))::int, 0) + 1));
        v_al := v_al + (select coalesce(sum(x.value::numeric), 0) from jsonb_each_text(v_f -> 'hull_lost') x);
      end loop;
      raise notice 'LEVELS: CARGO | level % | a crown navire (accuracy %, sighting %) set upon by a raid of % | % | her hull lost % %%', v_lvl, v_a -> 0 ->> 'accuracy', v_a -> 0 ->> 'sighting',
        v_raid, v_ends, round(v_al / c_n / v_a0 * 100, 1);
    end loop;
  end loop;
end
$$;
