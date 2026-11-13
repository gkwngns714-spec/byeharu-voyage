-- 0371 FLEE KNOBS SCENE (docs/COMBAT_LOG.md 7, R7: "the flee knobs (0.15, 0.05) are reasoned, not measured"). Run before raid_orders_enabled is lit:
--   node scripts/ops/harness/more-ships/q.mjs scripts/ops/harness/combat-log/flee-knobs-scene.sql
-- Three probe fleets of REAL hulls, read as the raid reads them (voyage.fleet_hulls, voyage.escort_score): a WEAK TRADER (one barca, no guns, 30,000 d. of cargo at cost), the same
-- barca WITH A LOOKOUT (her sighting set to 20, the design's figure), and a GUNNED FLEET (one navire, 200,000 d.). Each meets c_n seeded raids of ONE xebec (12.7) and of FIVE (63.5),
-- the two raid sizes of docs/COMBAT_LOG.md 2.5, through the real skin and engine (voyage.raid_report). FIGHT and PAY are run once (the flee knobs do not touch them); FLEE is run at
-- fight_flee_base 0.10, 0.15 (the seed), 0.20 and 0.25 with fight_flee_floor 0.05 (the seed), and once at base 0.15 with floor 0.10. The knobs are written inside this scene only.
-- A raid's cost is priced as voyage.settle prices it: plunder takes 37.5 per cent of the cargo on average, Pay takes ransom_share of the cargo at cost.
-- Prints KNOBS: lines. LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server
-- (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  c_n    constant int := 1000;
  c_seed constant uuid := '00000000-0371-4000-8000-0000000000e1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_hum  uuid;
  v_fl   uuid;
  v_h    jsonb;
  v_esc  numeric;
  v_who  text;
  v_cls  text;
  v_cargo numeric;
  v_raid numeric;
  v_run  text[];
  v_f    jsonb;
  d      int;
  v_ends jsonb;
  v_hull numeric;
  v_cost numeric;
  v_rounds numeric;
  v_h0   numeric;
begin
  update public.world_config set value = 'true'::jsonb where key in ('combat_bite');
  foreach v_who in array array['weak trader', 'weak trader with a lookout', 'gunned fleet'] loop
    v_cls := case v_who when 'gunned fleet' then 'navire' else 'barca' end;
    v_cargo := case v_who when 'gunned fleet' then 200000 else 30000 end;
    insert into public.players (company_name, nation_id, ducats) values ('Knobs 0371 ' || left(md5(v_who), 6), (select n.id from public.nations n where n.code = 'PRT'), 1000000) returning id into v_hum;
    v_fl := public.form_fleet(v_hum, 'Knobs ' || left(md5(v_who), 6), v_lis);
    perform public.commission_ship(v_hum, v_fl, v_cls, 'Probe ' || left(md5(v_who), 6), true, true);
    v_h := voyage.fleet_hulls(v_fl);
    if v_who = 'weak trader with a lookout' then
      v_h := jsonb_set(v_h, '{0,sighting}', to_jsonb(20));
    end if;
    v_esc := voyage.escort_score(v_fl);
    v_h0 := (select sum((e ->> 'hull')::numeric) from jsonb_array_elements(v_h) e);
    raise notice 'KNOBS: % = one % (hull %, crew %, attack %, reach %, armour %, sighting %; escort score %), cargo % d. at cost',
      v_who, v_cls, v_h -> 0 ->> 'hull', v_h -> 0 ->> 'crew', v_h -> 0 ->> 'attack', v_h -> 0 ->> 'reach', v_h -> 0 ->> 'armour', v_h -> 0 ->> 'sighting', round(v_esc, 2), v_cargo;
    foreach v_raid in array array[12.7, 63.5] loop
      -- (order, flee base, flee floor)
      foreach v_run slice 1 in array array[['FIGHT', '0.15', '0.05'], ['PAY', '0.15', '0.05'], ['FLEE', '0.10', '0.05'], ['FLEE', '0.15', '0.05'], ['FLEE', '0.20', '0.05'],
                                           ['FLEE', '0.25', '0.05'], ['FLEE', '0.15', '0.10']] loop
        update public.world_config set value = to_jsonb(v_run[2]::numeric) where key = 'fight_flee_base';
        update public.world_config set value = to_jsonb(v_run[3]::numeric) where key = 'fight_flee_floor';
        v_ends := '{}'::jsonb; v_hull := 0; v_cost := 0; v_rounds := 0;
        for d in 1 .. c_n loop
          v_f := voyage.raid_report(c_seed, d, v_raid, v_esc, v_h, jsonb_build_object('log', true) || case v_run[1] when 'FIGHT' then '{}'::jsonb else jsonb_build_object('order', v_run[1]) end);
          v_ends := jsonb_set(v_ends, array[v_f -> 'log' ->> 'end'], to_jsonb(coalesce((v_ends ->> (v_f -> 'log' ->> 'end'))::int, 0) + 1));
          v_hull := v_hull + (select coalesce(sum(x.value::numeric), 0) from jsonb_each_text(v_f -> 'hull_lost') x);
          v_rounds := v_rounds + (v_f ->> 'rounds_fought')::int;
          v_cost := v_cost + case when v_f -> 'log' ->> 'end' in ('TAKEN', 'GAVE') then 0.375 * v_cargo
                                  when v_f -> 'log' ->> 'end' = 'PAID' then floor(v_cargo * public.wc_num('ransom_share')) else 0 end;
        end loop;
        raise notice 'KNOBS: % | raid % | % base % floor % | away or unharmed % of % | ends % | cargo and ransom lost % d. a raid | hull lost % %% a raid | % rounds a raid',
          v_who, v_raid, rpad(v_run[1], 5), v_run[2], v_run[3],
          coalesce((v_ends ->> 'FLED')::int, 0) + coalesce((v_ends ->> 'SLIP')::int, 0) + coalesce((v_ends ->> 'BROKE')::int, 0) + coalesce((v_ends ->> 'THREW')::int, 0), c_n,
          v_ends, round(v_cost / c_n), round(v_hull / c_n / v_h0 * 100, 1), round(v_rounds / c_n, 2);
      end loop;
    end loop;
  end loop;
end
$$;
