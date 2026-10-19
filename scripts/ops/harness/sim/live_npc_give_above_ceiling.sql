CREATE OR REPLACE FUNCTION public.npc_give_above_ceiling(p_now timestamp with time zone DEFAULT now(), p_player uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0180 (a): every merchant house above her purse ceiling (public.npc_purse_ceiling) gives the whole
-- excess to the harbours of her loop — every distinct harbour her routes call at, by code, in equal
-- parts (the remainder rounded down the list); none, her home. At each: SHARES first, as many as a
-- work there offers and the part covers (public.invest_for, the players' door; most offered first),
-- the rest as MERCHANT_SURPLUS (public.pay_city — no influence). Her purse ends AT her ceiling. Lit
-- only (dark, a payment to a city writes nothing, so nothing is given). Composed by
-- public.npc_tend_houses after public.npc_invest, while the merchants are on. Budgeted by 0114's
-- deadline (public.npc_upkeep_spent): a house not reached is deferred to the next hour. p_player, when
-- given, limits the pass to that one house (the hourly caller gives none: every house).
declare
  hh        record;
  w         record;
  v_ports   uuid[];
  v_over    bigint;
  v_n       int;
  i         int;
  v_cum     bigint;
  v_prev    bigint;
  v_part    bigint;
  v_buy     int;
  v_houses  int := 0;
  v_shares  bigint := 0;
  v_given   bigint := 0;
  v_deferred int := 0;
  v_failed  int := 0;
  v_notes   jsonb := '[]'::jsonb;
begin
  if not public.city_treasury_on() then
    return jsonb_build_object('ceiling', 0, 'given', 0, 'shares', 0, 'deferred', 0, 'failed', 0, 'notes', v_notes);
  end if;
  for hh in select h.player_id, h.home_port_id, pl.company_name
              from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
             where pl.ducats > public.npc_purse_ceiling(h.player_id)
               and (p_player is null or h.player_id = p_player)
             order by h.roster_ord loop
    if public.npc_upkeep_spent() then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    begin
      -- 0122's ONE LOCK ORDER: the house's row first (then each city's, inside the doors).
      select pl.ducats - public.npc_purse_ceiling(pl.id) into v_over
        from public.players pl where pl.id = hh.player_id for update;
      continue when v_over is null or v_over <= 0;
      v_ports := array(select st.port_id
                         from (select distinct s.port_id from public.npc_fleets nf
                                 join public.standing_route_stops s on s.route_id = nf.route_id
                                where nf.player_id = hh.player_id) st
                         join public.ports po on po.id = st.port_id and po.kind = 'HARBOUR'
                        order by po.code);
      if cardinality(v_ports) = 0 then
        v_ports := array[hh.home_port_id];
      end if;
      v_n := cardinality(v_ports);
      v_prev := 0;
      for i in 1 .. v_n loop
        v_cum := floor(v_over::numeric * i / v_n)::bigint;
        v_part := v_cum - v_prev;
        v_prev := v_cum;
        continue when v_part <= 0;
        for w in select cw.kind, public.city_offered(cw.port_id, cw.kind) as offered,
                        public.works_share_price(cw.level) as price
                   from public.city_works cw
                  where cw.port_id = v_ports[i] and public.city_offered(cw.port_id, cw.kind) > 0
                  order by 2 desc, array_position(array['docks', 'market', 'production', 'inn'], cw.kind) loop
          v_buy := least(w.offered, floor(v_part / w.price))::int;
          continue when v_buy < 1 or v_buy * w.price < public.wc_int('invest_min_ducats');
          perform public.invest_for(hh.player_id, v_ports[i], w.kind, v_buy);
          v_part := v_part - v_buy * w.price;
          v_shares := v_shares + v_buy * w.price;
        end loop;
        if v_part > 0 then
          perform public.pay_city(hh.player_id, v_ports[i], 'MERCHANT_SURPLUS', v_part,
            public.emit_event(hh.player_id, 'SURPLUS_GIVEN', jsonb_build_object(
              'company', hh.company_name, 'amount', v_part,
              'port', (select p.code from public.ports p where p.id = v_ports[i]))));
          v_given := v_given + v_part;
        end if;
      end loop;
      v_houses := v_houses + 1;
    exception when others then
      v_failed := v_failed + 1;
      v_notes := v_notes || jsonb_build_object('company', hh.company_name, 'ceiling_error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('ceiling', v_houses, 'given', v_given, 'shares', v_shares,
                            'deferred', v_deferred, 'failed', v_failed, 'notes', v_notes);
end $function$
