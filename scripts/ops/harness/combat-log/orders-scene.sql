-- 0353 ORDERS SCENE: run by proof-0353.mjs --orders on the world AFTER the file, rolled back. IS THE CHOICE REAL? (docs/COMBAT_LOG.md 2.5, measured instead of reasoned.)
-- Two probe fleets of REAL hulls, read as the raid reads them (voyage.fleet_hulls, voyage.escort_score): a WEAK TRADER (one barca, no guns, 30,000 d. of cargo at cost) and a
-- GUNNED FLEET (one navire, 200,000 d.). Each meets c_n seeded raids (one seed a raid: the voyage day) of one xebec (12.7), of the worst sea's mid roll (0.45 x 40 = 18) and of five
-- xebecs (63.5), under Fight, Flee and Pay, through the real skin and engine (voyage.raid_report). What a raid costs is priced as voyage.settle prices it: plunder takes 25 to 50 per
-- cent of every good (37.5 on average), Pay takes ransom_share (8 per cent) of the cargo at cost, a boarding thrown back costs 2 per cent of the hands and a plunder 10.
-- Prints ORDERS: lines, and LOG: one sample log (the raw shape the client draws). Pure reads but for the two probe fleets it builds.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  c_n    constant int := 1000;
  c_seed constant uuid := '00000000-0353-4000-8000-0000000000e1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_hum  uuid;
  v_fl   uuid;
  v_h    jsonb;
  v_esc  numeric;
  v_who  text;
  v_cls  text;
  v_cargo numeric;
  v_raid numeric;
  v_ord  text;
  v_f    jsonb;
  d      int;
  v_ends jsonb;
  v_hull numeric;
  v_cost numeric;
  v_hands numeric;
  v_rounds numeric;
  v_h0   numeric;
  v_sample jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('combat_bite');
  insert into public.players (company_name, nation_id, ducats) values ('Orders 0353 house', (select n.id from public.nations n where n.code = 'PRT'), 1000000) returning id into v_hum;
  foreach v_who in array array['weak trader', 'gunned fleet'] loop
    v_cls := case v_who when 'weak trader' then 'barca' else 'navire' end;
    v_cargo := case v_who when 'weak trader' then 30000 else 200000 end;
    v_fl := public.form_fleet(v_hum, 'Orders 0353 ' || v_cls, v_lis);
    perform public.commission_ship(v_hum, v_fl, v_cls, 'Probe ' || v_cls, true, true);
    v_h := voyage.fleet_hulls(v_fl);
    v_esc := voyage.escort_score(v_fl);
    v_h0 := (select sum((e ->> 'hull')::numeric) from jsonb_array_elements(v_h) e);
    raise notice 'ORDERS: % = one % (hull %, crew %, attack %, accuracy %, reach %, armour %, sighting %; escort score %), cargo % d. at cost',
      v_who, v_cls, v_h -> 0 ->> 'hull', v_h -> 0 ->> 'crew', v_h -> 0 ->> 'attack', v_h -> 0 ->> 'accuracy', v_h -> 0 ->> 'reach', v_h -> 0 ->> 'armour', v_h -> 0 ->> 'sighting', round(v_esc, 2), v_cargo;
    foreach v_raid in array array[12.7, 18, 63.5] loop
      foreach v_ord in array array['FIGHT', 'FLEE', 'PAY'] loop
        v_ends := '{}'::jsonb; v_hull := 0; v_cost := 0; v_hands := 0; v_rounds := 0;
        for d in 1 .. c_n loop
          v_f := voyage.raid_report(c_seed, d, v_raid, v_esc, v_h, jsonb_build_object('log', true) || case v_ord when 'FIGHT' then '{}'::jsonb else jsonb_build_object('order', v_ord) end);
          v_ends := jsonb_set(v_ends, array[v_f -> 'log' ->> 'end'], to_jsonb(coalesce((v_ends ->> (v_f -> 'log' ->> 'end'))::int, 0) + 1));
          v_hull := v_hull + (select coalesce(sum(x.value::numeric), 0) from jsonb_each_text(v_f -> 'hull_lost') x);
          v_rounds := v_rounds + (v_f ->> 'rounds_fought')::int;
          v_cost := v_cost + case when v_f -> 'log' ->> 'end' in ('TAKEN', 'GAVE') then 0.375 * v_cargo
                                  when v_f -> 'log' ->> 'end' = 'PAID' then floor(v_cargo * public.wc_num('ransom_share')) else 0 end;
          v_hands := v_hands + case when v_f ->> 'outcome' = 'DRIVEN_OFF' then 0.02 when v_f ->> 'outcome' = 'PLUNDERED' then 0.10 else 0 end;
          if v_sample is null and v_who = 'weak trader' and v_ord = 'FLEE' and v_raid = 18 and (v_f ->> 'fled')::boolean and (v_f ->> 'rounds_fought')::int >= 3 then
            v_sample := v_f;
          end if;
        end loop;
        raise notice 'ORDERS: % | raid % | % | ends % | cargo and ransom lost % d. a raid | hull lost % %% a raid | hands lost % %% a raid | % rounds a raid',
          v_who, v_raid, rpad(v_ord, 5), v_ends, round(v_cost / c_n), round(v_hull / c_n / v_h0 * 100, 1), round(v_hands / c_n * 100, 2), round(v_rounds / c_n, 2);
      end loop;
    end loop;
  end loop;
  raise notice 'LOG: %', v_sample -> 'log';
  raise notice 'LOG: rounds %', v_sample -> 'rounds';
  raise notice 'LOG: sentence %', v_sample ->> 'sentence';
end
$$;
