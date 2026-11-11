do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- LOCAL SCENE (measure.mjs rolls it back): WHAT THE TEN CARDS SAY, AND WHAT A CALL COSTS, for a new company where she lies (Lisbon, a new company's purse) — run it without and with
-- --apply=20260818000351_a_best_sale_she_can_pay_for.sql to read before and after on the same machine in the same minute (docs/dev-log/2026-11-11-near-sale.md).
-- Prints: her purse; every card (city, profit, units, days, and after 0351 the real seconds, the cost and the far choice); world.best_sales x8 where she lies and x4 from the nearest
-- other selling harbour; and what the tray's Max (public.fleet_buy_capacity) costs for every good, with what binds it.
do $s$
declare
  c_uid constant uuid := '00000000-0351-4000-8000-0000000000aa';
  v_pl uuid; v_fl uuid; v_home uuid; v_near uuid; t timestamptz; v_n int; gd record; e jsonb; v_b jsonb; v_cap jsonb; ms text := ''; v_tot numeric := 0;
begin
  v_pl := public.new_house(c_uid, 'Probe cards', 'PRT');
  select id, port_id into v_fl, v_home from public.fleets where player_id = v_pl;
  perform cmd.assume_identity(c_uid);
  select p.id into v_near
    from public.ports p, public.ports hb
   where hb.id = v_home and p.kind = 'HARBOUR' and p.id <> v_home
     and exists (select 1 from public.port_goods pg where pg.port_id = p.id and public.port_offers(p.id, pg.good_id))
   order by voyage.gc_distance_nm(hb.lat, hb.lon, p.lat, p.lon), p.code limit 1;
  raise notice 'she lies at %, purse %, stores on credit there: %, one game day is % real seconds', (select code from public.ports where id = v_home),
    (select ducats from public.players where id = v_pl), public.credit_on(v_home), round(86400 / public.wc_num('time_compression'));
  v_b := world.best_sales(v_fl, v_home);
  for e in select x from jsonb_array_elements(v_b->'goods') x loop
    raise notice 'card % | % % x % | % days% | cost % | far %', rpad(e->>'good', 13), coalesce(e->>'port', case when (e->>'short')::boolean then 'NO MONEY' else 'none' end),
      coalesce(e->>'profit', '-'), coalesce(e->>'units', '-'), coalesce(e->>'days', '-'), coalesce(' = ' || (e->>'seconds') || ' s', ''), coalesce(e->>'cost', '(not served)'),
      coalesce(e->'far'->>'port' || ' ' || (e->'far'->>'profit') || ' x ' || (e->'far'->>'units') || ' | ' || (e->'far'->>'days') || ' days = ' || (e->'far'->>'seconds') || ' s | cost ' || (e->'far'->>'cost'), '-');
  end loop;
  for v_n in 1 .. 8 loop
    t := clock_timestamp(); perform world.best_sales(v_fl, v_home); ms := ms || ' ' || round(extract(epoch from clock_timestamp() - t) * 1000);
  end loop;
  raise notice 'best_sales where she lies x8 (ms):%', ms; ms := '';
  for v_n in 1 .. 4 loop
    t := clock_timestamp(); perform world.best_sales(v_fl, v_near); ms := ms || ' ' || round(extract(epoch from clock_timestamp() - t) * 1000);
  end loop;
  raise notice 'best_sales at % (not where she lies) x4 (ms):%', (select code from public.ports where id = v_near), ms; ms := '';
  for gd in select g.id, g.code from public.port_goods pg join public.goods g on g.id = pg.good_id
             where pg.port_id = v_home and public.port_offers(v_home, g.id) order by g.code loop
    t := clock_timestamp(); v_cap := public.fleet_buy_capacity(v_fl, gd.id);
    ms := ms || format(' %s %s/%s %sms', gd.code, v_cap->>'max_qty', v_cap->>'bound_by', round(extract(epoch from clock_timestamp() - t) * 1000, 1));
    v_tot := v_tot + extract(epoch from clock_timestamp() - t) * 1000;
  end loop;
  raise notice 'the tray''s Max per good (units/what binds, ms):% | sum % ms', ms, round(v_tot);
end $s$;
