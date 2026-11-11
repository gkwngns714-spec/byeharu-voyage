do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- LOCAL SCENE (measure.mjs rolls it back): WHAT A CALL COSTS, steady, on the world as it stands — run it with and without
-- --apply=20260818000350_the_best_sale_reads_the_sea_once.sql to read before and after on the same machine in the same minute.
-- A probe house at its home harbour (Lisbon): world.best_sales there x6 and at the nearest other selling harbour x4,
-- world.board_origin, world.board_legs when it exists, one world.board_sell per good (the legs handed over when they exist),
-- and one world.good_board x4.
do $s$
declare
  c_uid constant uuid := '00000000-0350-4000-8000-0000000000aa';
  v_pl uuid; v_fl uuid; v_home uuid; v_near uuid; t timestamptz; v_n int; v_o jsonb; gd record; a record; v_ctx jsonb; v_legs jsonb;
  v_port public.ports%rowtype; v_rows jsonb; ms text := ''; v_tot numeric := 0;
begin
  v_pl := public.new_house(c_uid, 'Probe calls', 'PRT');
  select id, port_id into v_fl, v_home from public.fleets where player_id = v_pl;
  perform cmd.assume_identity(c_uid);
  select * into v_port from public.ports where id = v_home;
  select p.id into v_near
    from public.ports p, public.ports hb
   where hb.id = v_home and p.kind = 'HARBOUR' and p.id <> v_home
     and exists (select 1 from public.port_goods pg where pg.port_id = p.id and public.port_offers(p.id, pg.good_id))
   order by voyage.gc_distance_nm(hb.lat, hb.lon, p.lat, p.lon), p.code limit 1;
  for v_n in 1 .. 6 loop
    t := clock_timestamp(); perform world.best_sales(v_fl, v_home); ms := ms || ' ' || round(extract(epoch from clock_timestamp() - t) * 1000);
  end loop;
  raise notice 'best_sales at % x6 (ms):%', v_port.code, ms; ms := '';
  for v_n in 1 .. 4 loop
    t := clock_timestamp(); perform world.best_sales(v_fl, v_near); ms := ms || ' ' || round(extract(epoch from clock_timestamp() - t) * 1000);
  end loop;
  raise notice 'best_sales at % (not where she lies) x4 (ms):%', (select code from public.ports where id = v_near), ms; ms := '';
  t := clock_timestamp(); v_o := world.board_origin(v_fl);
  raise notice 'board_origin (one reach_passage): % ms', round(extract(epoch from clock_timestamp() - t) * 1000);
  t := clock_timestamp(); perform world.board_passages(v_pl, v_fl, v_near, (v_o->>'cap')::numeric);
  raise notice 'board_passages from the other city (a second reach_passage): % ms', round(extract(epoch from clock_timestamp() - t) * 1000);
  if to_regprocedure('world.board_legs(uuid,jsonb)') is not null then
    v_ctx := v_o || jsonb_build_object('basis', 'capacity', 'src', jsonb_build_object('code', v_port.code));
    execute 'select world.board_legs($1, $2)' into v_legs using v_fl, v_ctx;
    t := clock_timestamp(); execute 'select world.board_legs($1, $2)' into v_legs using v_fl, v_ctx;
    raise notice 'board_legs (once a call): % ms, % harbours', round(extract(epoch from clock_timestamp() - t) * 1000, 1), jsonb_array_length(v_legs);
  end if;
  for gd in select g.id, g.code from public.port_goods pg join public.goods g on g.id = pg.good_id
             where pg.port_id = v_home and public.port_offers(v_home, g.id) order by g.code loop
    select * into a from world.board_amount(v_fl, gd.id, null);
    v_ctx := v_o || jsonb_build_object('units', a.units, 'basis', a.basis, 'cost_each', a.cost_each,
                'src', jsonb_build_object('code', v_port.code), 'src_cut', false, 'src_name', v_port.name, 'fit', true, 'lean', true)
             || case when v_legs is not null then jsonb_build_object('legs', v_legs) else '{}'::jsonb end;
    t := clock_timestamp(); v_rows := world.board_sell(gd.id, v_fl, v_ctx);
    ms := ms || ' ' || round(extract(epoch from clock_timestamp() - t) * 1000, 1); v_tot := v_tot + extract(epoch from clock_timestamp() - t) * 1000;
  end loop;
  raise notice 'board_sell per good (ms):% | sum %', ms, round(v_tot); ms := '';
  for v_n in 1 .. 4 loop
    t := clock_timestamp(); perform world.good_board(gd.id, v_fl, null, null); ms := ms || ' ' || round(extract(epoch from clock_timestamp() - t) * 1000);
  end loop;
  raise notice 'good_board (%) x4 (ms):%', gd.code, ms;
end $s$;
