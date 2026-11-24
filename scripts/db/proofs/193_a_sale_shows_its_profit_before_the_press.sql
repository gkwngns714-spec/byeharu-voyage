-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 193 - A SALE SHOWS ITS PROFIT BEFORE THE PRESS  (migration 0490; docs/design/simplify-2026-11-24.md, slice S2)
--
--   The owner, 2026-11-24: "when i sell, i want to see the price i bought, the price i will get, how much profit earn and such."
--   The sell face reads the sale's dry run (cmd.preview -> cmd.do_sell, rolled back). This proof plays a scene with all three costs
--   (the economy closed and the city purses lit, as production runs; the profit tax, her crew's wages, the dock fee her call left): the
--   figure the preview shows is the SOLD event's trip_net to the unit, and her purse moved exactly that (plus the goods' cost) from
--   before her call to after the sale. Rolled back by proof.mjs.
--
-- @pass SP_PREVIEW_IS_THE_SALE  tax, wages and a dock fee all above 0: the preview's trip_net, dock_fee, wages and tax equal the sale's
--                               result and its SOLD event's, and trip_net = profit - tax - wages - dock fee
-- @pass SP_PURSE                her purse moved trip_net + cost from before the call to after the sale (the one profit, 0474)
-- @pass SP_SECOND_SALE          a second good sold at the same call previews and settles with no dock fee, one trip_net again
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0490-4000-8000-0000000000a1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a    uuid;
  v_fa   uuid;
  v_g1   record;
  v_g2   record;
  v_call jsonb;
  v_pv   jsonb;
  v_r    jsonb;
  v_ev   jsonb;
  v_p0   bigint;
  v_p1   bigint;
begin
  -- founded first: a closed economy makes no new gold (E_NO_NEW_GOLD)
  v_a := public.new_house(c_a, 'Casa do Lucro A 193', 'PRT');
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  select f.id into v_fa from public.fleets f where f.player_id = v_a limit 1;
  -- two goods Lisbon bids for, bought (written straight) at half her bid, five units each
  select g.id, g.code, g.name, q.avg_price as bid into v_g1
    from public.goods g cross join lateral world.quote(v_lis, g.id, 5, 'sell', null, v_fa) q
   where public.port_offers(v_lis, g.id) and q.units = 5 and q.avg_price > 50
   order by g.code limit 1;
  select g.id, g.code, g.name, q.avg_price as bid into v_g2
    from public.goods g cross join lateral world.quote(v_lis, g.id, 5, 'sell', null, v_fa) q
   where public.port_offers(v_lis, g.id) and q.units = 5 and q.avg_price > 50 and g.id <> v_g1.id
   order by g.code limit 1;
  if v_g1.id is null or v_g2.id is null then
    raise exception 'PROOF 193 FAILED: Lisbon bids for fewer than two goods';
  end if;
  update public.ships set cargo = jsonb_build_object(v_g1.code, 5, v_g2.code, 5),
                          cargo_basis = jsonb_build_object(v_g1.code, floor(v_g1.bid / 2), v_g2.code, floor(v_g2.bid / 2))
   where fleet_id = v_fa;
  insert into public.fleet_wages (fleet_id, owed, visit_net, visit_paid) values (v_fa, 40, 0, 0)
    on conflict (fleet_id) do update set owed = 40, visit_net = 0, visit_paid = 0;
  update public.port_treasury set ducats = 1000000000000 where port_id = v_lis;   -- this world's purses are thin (proof 105): Lisbon can pay
  select p.ducats into v_p0 from public.players p where p.id = v_a;
  v_call := public.port_call(v_fa, v_lis, v_a, now(), now(), null);
  if coalesce((v_call ->> 'fee')::bigint, 0) <= 0 then
    raise exception 'PROOF 193 FAILED: the call charged no dock fee: %', v_call;
  end if;

  -- ── SP_PREVIEW_IS_THE_SALE ──
  v_pv := cmd.preview(v_fa, 'SELL ' || v_g1.code || ' 5', null::jsonb);
  if coalesce((v_pv ->> 'ok')::boolean, false) is not true then
    raise exception 'PROOF 193 FAILED: the preview refused: %', v_pv;
  end if;
  v_pv := v_pv -> 'estimate';
  v_r := cmd.do_sell(v_fa, jsonb_build_object('good', v_g1.id, 'qty', 5));
  select e.payload into v_ev from public.events e where e.player_id = v_a and e.kind = 'SOLD' and e.payload ->> 'good' = v_g1.name;
  if v_ev is null or (v_pv ->> 'trip_net') is null
     or coalesce((v_pv ->> 'tax')::bigint, 0) <= 0 or coalesce((v_pv ->> 'wages')::bigint, 0) <= 0 or coalesce((v_pv ->> 'dock_fee')::bigint, 0) <= 0
     or (v_pv ->> 'trip_net')::bigint is distinct from (v_ev ->> 'trip_net')::bigint
     or (v_r ->> 'trip_net')::bigint is distinct from (v_ev ->> 'trip_net')::bigint
     or (v_pv ->> 'dock_fee')::bigint is distinct from (v_ev ->> 'dock_fee')::bigint
     or (v_pv ->> 'dock_fee')::bigint is distinct from (v_call ->> 'fee')::bigint
     or (v_pv ->> 'wages')::bigint is distinct from (v_ev ->> 'wages')::bigint
     or (v_pv ->> 'tax')::bigint is distinct from (v_ev ->> 'tax')::bigint
     or (v_pv ->> 'cost')::bigint is distinct from (v_ev ->> 'cost')::bigint
     or (v_pv ->> 'total')::bigint is distinct from (v_ev ->> 'total')::bigint
     or (v_ev ->> 'trip_net')::bigint is distinct from (v_ev ->> 'profit')::bigint - (v_ev ->> 'tax')::bigint - (v_ev ->> 'wages')::bigint - (v_ev ->> 'dock_fee')::bigint then
    raise exception 'PROOF 193 FAILED: the preview % is not the sale % / its event %', v_pv, v_r, v_ev;
  end if;
  raise notice 'PASS: SP_PREVIEW_IS_THE_SALE — % x5 at Lisbon: shown before the press sells for %, cost %, tax %, wages %, dock fee % -> profit %; the SOLD event says %.',
    v_g1.code, v_pv ->> 'total', v_pv ->> 'cost', v_pv ->> 'tax', v_pv ->> 'wages', v_pv ->> 'dock_fee', v_pv ->> 'trip_net', v_ev ->> 'trip_net';

  -- ── SP_PURSE ──
  select p.ducats into v_p1 from public.players p where p.id = v_a;
  if v_p1 - v_p0 <> (v_pv ->> 'trip_net')::bigint + (v_pv ->> 'cost')::bigint then
    raise exception 'PROOF 193 FAILED: her purse moved % (% -> %), not the shown profit % + cost %', v_p1 - v_p0, v_p0, v_p1, v_pv ->> 'trip_net', v_pv ->> 'cost';
  end if;
  raise notice 'PASS: SP_PURSE — her purse moved % = the shown profit % + the goods'' cost %.', v_p1 - v_p0, v_pv ->> 'trip_net', v_pv ->> 'cost';

  -- ── SP_SECOND_SALE ──
  v_pv := cmd.preview(v_fa, 'SELL ' || v_g2.code || ' 5', null::jsonb) -> 'estimate';
  v_r := cmd.do_sell(v_fa, jsonb_build_object('good', v_g2.id, 'qty', 5));
  select e.payload into v_ev from public.events e where e.player_id = v_a and e.kind = 'SOLD' and e.payload ->> 'good' = v_g2.name;
  if v_ev is null or (v_pv ->> 'dock_fee')::bigint <> 0 or (v_ev ->> 'dock_fee')::bigint <> 0
     or (v_pv ->> 'trip_net')::bigint is distinct from (v_ev ->> 'trip_net')::bigint
     or (v_r ->> 'trip_net')::bigint is distinct from (v_ev ->> 'trip_net')::bigint then
    raise exception 'PROOF 193 FAILED: the second sale previewed % and settled % / %', v_pv, v_r, v_ev;
  end if;
  raise notice 'PASS: SP_SECOND_SALE — % x5: dock fee 0, shown % = settled %.', v_g2.code, v_pv ->> 'trip_net', v_ev ->> 'trip_net';
end $p$;
