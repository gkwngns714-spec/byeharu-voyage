-- 0343 COST SCENE: the price of the two re-cut readers, DARK (the switch off, as the file ships), run by proof-0343.mjs --cost before and after the file on the same world, rolled back. A stopwatch on wasm: read for the order of the cost.
do $$
declare
  v_t0 timestamptz;
  v_n  bigint;
  v_i  int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  -- warm
  select count(*) into v_n from public.ports p where p.kind = 'HARBOUR' and public.city_aid_target(p.id) > 0;
  -- the aid target over every harbour, ten times (the roster read of public.crown_aid, the hourly city job)
  v_t0 := clock_timestamp();
  for v_i in 1 .. 10 loop
    select count(*) into v_n from public.ports p where p.kind = 'HARBOUR' and public.city_aid_target(p.id) > 0;
  end loop;
  raise notice 'COST: city_aid_target over every harbour: % ms a pass (% harbours)', round(extract(epoch from clock_timestamp() - v_t0) * 100, 2), v_n;
  -- the wind's candidate select, ten times (the gate runs on every harbour row)
  v_t0 := clock_timestamp();
  for v_i in 1 .. 10 loop
    select count(*) into v_n
      from public.ports p
      left join public.contract_wind w on w.port_id = p.id
     cross join lateral (select count(*) as n from public.trade_contracts c where c.port_id = p.id and c.status = 'open') o
     where p.kind = 'HARBOUR' and o.n < public.wc_int('contract_open_max') and (w.next_try is null or w.next_try <= now())
       and public.treasury_balance(p.id) >= public.wc_int('treasury_reserve_floor');
  end loop;
  raise notice 'COST: the wind''s candidate read with the flat knob: % ms a pass', round(extract(epoch from clock_timestamp() - v_t0) * 100, 2);
  if to_regprocedure('public.city_floor(uuid)') is not null then
    v_t0 := clock_timestamp();
    for v_i in 1 .. 10 loop
      select count(*) into v_n
        from public.ports p
        left join public.contract_wind w on w.port_id = p.id
       cross join lateral (select count(*) as n from public.trade_contracts c where c.port_id = p.id and c.status = 'open') o
       where p.kind = 'HARBOUR' and o.n < public.wc_int('contract_open_max') and (w.next_try is null or w.next_try <= now())
         and public.treasury_balance(p.id) >= public.city_floor(p.id);
    end loop;
    raise notice 'COST: the wind''s candidate read with public.city_floor: % ms a pass', round(extract(epoch from clock_timestamp() - v_t0) * 100, 2);
  end if;
end $$;
