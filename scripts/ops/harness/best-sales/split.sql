do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- LOCAL SCENE (measure.mjs rolls it back): WHERE world.best_sales SPENDS ITS TIME. A probe house at its home harbour.
do $s$
declare
  c_uid constant uuid := '00000000-0350-4000-8000-0000000000aa';
  v_pl uuid; v_fl uuid; v_home uuid; v_near uuid; v_o jsonb; v_sp jsonb; t timestamptz; gd record; a record; v_rows jsonb;
  v_ms numeric; v_tot numeric := 0; v_n int; v_arr numeric[]; v_ctx jsonb; v_port public.ports%rowtype;
begin
  v_pl := public.new_house(c_uid, 'Probe split', 'PRT');
  select id, port_id into v_fl, v_home from public.fleets where player_id = v_pl;
  perform cmd.assume_identity(c_uid);
  select * into v_port from public.ports where id = v_home;
  for v_n in 1 .. 3 loop
    t := clock_timestamp(); perform world.best_sales(v_fl, v_home);
    raise notice 'best_sales at % run %: % ms', v_port.code, v_n, round(extract(epoch from clock_timestamp() - t) * 1000);
  end loop;
  t := clock_timestamp(); v_o := world.board_origin(v_fl);
  raise notice 'board_origin (incl. reach_passage once): % ms, % passages', round(extract(epoch from clock_timestamp() - t) * 1000), jsonb_array_length(v_o->'passages');
  t := clock_timestamp(); perform public.supply_reach(v_fl);
  raise notice '  supply_reach: % ms', round(extract(epoch from clock_timestamp() - t) * 1000);
  for gd in select g.id, g.code from public.port_goods pg join public.goods g on g.id = pg.good_id
             where pg.port_id = v_home and public.port_offers(v_home, g.id) order by g.code loop
    select * into a from world.board_amount(v_fl, gd.id, null);
    v_ctx := v_o || jsonb_build_object('units', a.units, 'basis', a.basis, 'cost_each', a.cost_each,
                'src', jsonb_build_object('code', v_port.code), 'src_cut', false, 'src_name', v_port.name, 'fit', true, 'lean', true);
    t := clock_timestamp(); v_rows := world.board_sell(gd.id, v_fl, v_ctx);
    v_ms := round(extract(epoch from clock_timestamp() - t) * 1000); v_tot := v_tot + v_ms;
    -- the parts, asked alone
    t := clock_timestamp();
    select count(world.mid_price(p.id, gd.id, pg.stock)) into v_n from public.ports p join public.port_goods pg on pg.port_id = p.id and pg.good_id = gd.id
     where p.kind = 'HARBOUR' and not public.culture_refuses(p.culture, (select culture_mask from public.goods where id = gd.id));
    raise notice '% board_sell % ms (% priced rows) | mid_price x %: % ms', gd.code, v_ms, jsonb_array_length(v_rows), v_n, round(extract(epoch from clock_timestamp() - t) * 1000);
  end loop;
  raise notice 'sum of board_sell: % ms', v_tot;
  -- the other parts, for the last good
  select array_agg((e->>'max_leg_nm')::numeric) into v_arr from jsonb_array_elements(v_o->'passages') e;
  t := clock_timestamp(); perform count(*) from public.supply_needs(v_fl, v_arr);
  raise notice 'supply_needs over % legs: % ms', cardinality(v_arr), round(extract(epoch from clock_timestamp() - t) * 1000);
  t := clock_timestamp();
  perform count(q.total) from (select p.id from public.ports p join public.port_goods pg on pg.port_id = p.id and pg.good_id = gd.id where p.kind = 'HARBOUR' order by p.code limit 15) s
    cross join lateral world.quote(s.id, gd.id, 50, 'sell', null, v_fl) q;
  raise notice 'world.quote sell x 15: % ms', round(extract(epoch from clock_timestamp() - t) * 1000);
  t := clock_timestamp();
  perform count(q.total) from generate_series(41, 50) n cross join lateral world.quote(v_home, gd.id, n, 'buy', null, v_fl) q;
  raise notice 'world.quote buy x 10 counts: % ms', round(extract(epoch from clock_timestamp() - t) * 1000);
  t := clock_timestamp();
  perform count(public.profit_tax(s.id, 1000, v_pl)) from (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 15) s;
  raise notice 'profit_tax x 15: % ms', round(extract(epoch from clock_timestamp() - t) * 1000);
  t := clock_timestamp();
  perform count(*) from jsonb_to_recordset(v_o->'passages') r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric);
  raise notice 'jsonb_to_recordset(passages) once: % ms', round(extract(epoch from clock_timestamp() - t) * 1000);
end $s$;
