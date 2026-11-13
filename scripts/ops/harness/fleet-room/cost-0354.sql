do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- cost-0354.sql — LOCAL SCENE (it writes probe houses and lights the room; its runner, proof-0354.mjs --cost, rolls it back). Run AFTER 0354 is applied in the same transaction.
-- What world.fleets() costs with and without 0354's two hunks, on three houses: 1 fleet of 1 ship (most of prod), 2 fleets of 2, and the largest a company can be lit (5 fleets of 7).
-- OLD is the live body with the hunks taken out again (as proof 57 builds it). The two are called in turn, so a drifting machine moves both.
do $$
declare
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_prt  uuid := (select id from public.nations where code = 'PRT');
  v_def  text;
  v_p    uuid;
  v_f    uuid;
  v_t    timestamptz;
  v_old  numeric;
  v_new  numeric;
  v_tot  numeric;
  v_x    jsonb;
  s      record;
  i      int;
  j      int;
  c_n constant int := 60;
begin
  v_def := replace(pg_get_functiondef('world.fleets()'::regprocedure), E'\r', '');
  v_def := regexp_replace(v_def, E'    ''ships'', sv\\.ships,[^\n]*\n    ''totals'', public\\.fleet_totals\\(f\\.id, sv\\.ships\\),[^\n]*\n',
    E'    ''ships'', (select coalesce(jsonb_agg(world.ship_view(s.id) order by s.is_flagship desc, s.name), ''[]''::jsonb) from public.ships s where s.fleet_id = f.id),\n');
  v_def := regexp_replace(v_def, E'    from public\\.fleets f\n   cross join lateral \\(select coalesce\\(jsonb_agg\\(world\\.ship_view\\(s\\.id\\)[^\n]*\n[^\n]*\n[^\n]*\n[^\n]*offset 0\\) sv[^\n]*\n   where f\\.player_id = v_player\\);',
    E'    from public.fleets f where f.player_id = v_player);');
  if position('fleet_totals' in v_def) > 0 then raise exception 'cost-0354: the pre-image still carries 0354'; end if;
  execute replace(replace(v_def, 'CREATE OR REPLACE FUNCTION world.fleets()', 'CREATE OR REPLACE FUNCTION pg_temp.pre_fleets()'), 'SECURITY DEFINER', '');
  update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite';

  for s in select * from (values (1, 1, '00000000-0354-4000-8000-0000000000c1'::uuid), (2, 2, '00000000-0354-4000-8000-0000000000c2'::uuid),
                                 (5, 7, '00000000-0354-4000-8000-0000000000c3'::uuid)) t(fleets, ships, uid) loop
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (s.uid, format('Custo %sx%s 0354', s.fleets, s.ships), v_prt, 0, false) returning id into v_p;
    insert into public.house_room (player_id, kind, steps) values (v_p, 'FLEET', 9), (v_p, 'SHIP', 9);
    for i in 1 .. s.fleets loop
      v_f := public.form_fleet(v_p, format('Custo %s', i), v_lis);
      for j in 1 .. s.ships loop
        perform public.commission_ship(v_p, v_f, case when j % 2 = 0 then 'nau' else 'barca' end, format('Navio %s %s', i, j), j = 1, true);
      end loop;
    end loop;
    perform set_config('request.jwt.claim.sub', s.uid::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', s.uid)::text, true);
    v_x := pg_temp.pre_fleets(); v_x := world.fleets();   -- warm both plans
    v_old := 0; v_new := 0; v_tot := 0;
    for i in 1 .. c_n loop
      v_t := clock_timestamp(); v_x := pg_temp.pre_fleets(); v_old := v_old + extract(epoch from clock_timestamp() - v_t) * 1000;
      v_t := clock_timestamp(); v_x := world.fleets();       v_new := v_new + extract(epoch from clock_timestamp() - v_t) * 1000;
    end loop;
    v_t := clock_timestamp();
    for i in 1 .. c_n loop
      perform public.fleet_totals((e.value ->> 'id')::uuid, e.value -> 'ships') from jsonb_array_elements(v_x) e;
    end loop;
    v_tot := extract(epoch from clock_timestamp() - v_t) * 1000;
    raise notice 'COST world.fleets() % fleet(s) of % ship(s), % pairs: OLD % ms, NEW % ms, difference % ms (% %%); public.fleet_totals alone, all her fleets: % ms; the answer % bytes',
      s.fleets, s.ships, c_n, round(v_old / c_n, 3), round(v_new / c_n, 3), round((v_new - v_old) / c_n, 3), round((v_new - v_old) / v_old * 100, 1), round(v_tot / c_n, 3), length(v_x::text);
  end loop;
  v_t := clock_timestamp();
  for i in 1 .. c_n loop v_x := world.house_room(); end loop;
  raise notice 'COST world.house_room() on the 5x7 house: % ms a read (asked when the Fleets page opens, not every 30 s)', round(extract(epoch from clock_timestamp() - v_t) * 1000 / c_n, 3);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;
