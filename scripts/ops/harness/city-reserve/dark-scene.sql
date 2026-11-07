-- 0343 DARK PARITY SCENE: run by proof-0343.mjs on the world BEFORE the file and AFTER it, rolled back each time. Every SCENE line must be equal.
-- It covers what 0343 cuts, with the switch off (as the file ships): the aid target, a donor's room and the hall's funds on the way at every harbour; the load room and the origins of every realm;
-- the REAL public.crown_aid over the whole world (the instant path, every flow digested); and the REAL wind procedure, one pass over the world with its count holding the pace (not the clock),
-- every request and rest row it wrote digested. It names only what existed before 0343.
do $$
declare
  v_mark bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_r    jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
  update public.world_config set value = 'false'::jsonb where key in ('convoys_enabled', 'convoy_rich_enabled');
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  update public.world_config set value = to_jsonb(60000) where key = 'contract_wind_ms';
  update public.world_config set value = to_jsonb(6) where key = 'contract_wind_posts';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  -- a spread of purses: some broke, some at the floor, some rich, a few with a rolled reserve above the floor; the same spread before and after (by code order, not by id)
  update public.port_treasury t set ducats = x.d, reserve = x.r
    from (select p.id, (array[1000, 49999, 50000, 50001, 120000, 900000, 25000000])[1 + (row_number() over (order by p.code) % 7)] as d,
                       (array[0, 0, 70000, 0, 0, 900, 0])[1 + (row_number() over (order by p.code) % 7)] as r
            from public.ports p where p.kind = 'HARBOUR') x
   where t.port_id = x.id;
  delete from public.contract_wind;

  raise notice 'SCENE: targets %', (select md5(string_agg(p.code || ':' || public.city_aid_target(p.id) || ':' || public.crown_call_room(p.id) || ':' || coalesce(public.funds_on_way(p.id)::text, ''), ',' order by p.code))
                                       from public.ports p where p.kind = 'HARBOUR');
  raise notice 'SCENE: under_target %', (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.treasury_balance(p.id) < public.city_aid_target(p.id));
  raise notice 'SCENE: realms %', (select md5(string_agg(n.code || ':' || coalesce(public.cargo_origins(g.nation_id)::text, '') || ':' || coalesce(public.cargo_load_room(public.realm_capital(g.nation_id), g.nation_id)::text, ''), ',' order by n.code))
                                      from public.great_powers g join public.nations n on n.id = g.nation_id where not g.pirate);

  -- the real instant aid over the whole world
  v_r := public.crown_aid(null);
  raise notice 'SCENE: aid % %', v_r, (select md5(coalesce(string_agg(p.code || ':' || f.kind || ':' || f.ducats, ',' order by p.code, f.kind, f.ducats), ''))
                                          from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > v_mark);
  raise notice 'SCENE: purses %', (select md5(string_agg(p.code || ':' || public.treasury_balance(p.id), ',' order by p.code)) from public.ports p where p.kind = 'HARBOUR');

  -- the real wind, one pass over the world, six harbours asked
  call public.tick_contract_wind(false, null);
  raise notice 'SCENE: wind % %', (select r.receipt - 'note' from public.contract_wind_runs r order by r.at desc limit 1),
                                  (select md5(coalesce(string_agg(p.code, ',' order by p.code), '')) from public.contract_wind w join public.ports p on p.id = w.port_id);
  raise notice 'SCENE: requests %', (select md5(coalesce(string_agg(p.code || ':' || c.good_id || ':' || c.qty || ':' || c.status, ',' order by p.code, c.good_id, c.qty), ''))
                                        from public.trade_contracts c join public.ports p on p.id = c.port_id where c.status = 'open');
end $$;
