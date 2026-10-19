CREATE OR REPLACE FUNCTION public.npc_tend_houses(p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0137: THE companies' upkeep — public.npc_tend's investment (public.npc_invest) and refound passes,
-- moved verbatim. npc_tend runs it after the routes when no single route was asked for; the hourly
-- public.tick_reconcile runs it in its own transaction after the routes.
declare
  v_on      boolean := public.npc_traders_on();
  hh        record;
  v_last    timestamptz;
  v_week    int;
  v_refound int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_can      bigint;
  v_unfunded int := 0;
  v_inv      jsonb := '{}'::jsonb;
  v_ceil     jsonb := '{}'::jsonb;   -- 0180 (a): the purse ceiling's pass
  v_notes   jsonb := '[]'::jsonb;
begin
  -- 0123: INVESTMENT — merchants put their surplus into the cities of their loop (public.npc_invest).
  if v_on then
    v_inv := public.npc_invest(p_now);
    v_deferred := v_deferred + coalesce((v_inv->>'deferred')::int, 0);
    v_failed := v_failed + coalesce((v_inv->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_inv->'notes', '[]'::jsonb);
  end if;

  -- 0180 (a): ABOVE HER PURSE CEILING, the rest goes to the cities of her loop (public.npc_give_above_ceiling).
  if v_on then
    v_ceil := public.npc_give_above_ceiling(p_now);
    v_deferred := v_deferred + coalesce((v_ceil->>'deferred')::int, 0);
    v_failed := v_failed + coalesce((v_ceil->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_ceil->'notes', '[]'::jsonb);
  end if;

  -- REFOUNDS, per company, only while the switch is on.
  if v_on then
    for hh in select h.player_id, h.capital, pl.ducats, pl.company_name, h.home_port_id
                from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
               where pl.ducats < h.capital * public.wc_num('npc_purse_floor_pct')
               order by h.roster_ord loop
      begin
        select max(ev.created_at), count(*) filter (where ev.created_at > p_now - interval '7 days')
          into v_last, v_week
          from public.events ev where ev.player_id = hh.player_id and ev.kind = 'NPC_REFOUNDED';
        continue when v_last is not null
          and v_last > p_now - make_interval(secs => (public.wc_num('npc_refound_cooldown_game_days')
                                                       * public.wc_num('game_day_seconds'))::double precision);
        -- 0115: NO WEEKLY CAP THAT PARKS A COMPANY. A purse under the floor is refounded (the
        -- cooldown still spaces refounds); the cap's lay-up and loop swap are deleted.
        if not public.city_treasury_on() then
          perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
            public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
              'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
          v_refound := v_refound + 1;
        else
          -- 0122: lit, the HOME HARBOUR pays, from its surplus — partially, or not at all. A merchant
          -- whose home cannot pay sails on at her purse floor until it earns (never parked, 0115).
          v_can := greatest(0, least(hh.capital - hh.ducats, public.city_surplus(hh.home_port_id)));
          if v_can > 0 then
            perform public.city_pays(hh.home_port_id, hh.player_id, 'NPC_REFOUND', v_can,
              public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
                'company', hh.company_name, 'amount', v_can, 'week', coalesce(v_week, 0) + 1,
                'port', (select p.code from public.ports p where p.id = hh.home_port_id),
                'partial', v_can < hh.capital - hh.ducats)));
            v_refound := v_refound + 1;
          else
            v_unfunded := v_unfunded + 1;
          end if;
        end if;
      exception when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('company', hh.company_name, 'error', sqlerrm);
      end;
    end loop;
  end if;

  return jsonb_build_object('refounded', v_refound, 'refound_unfunded', v_unfunded,
                            'invested', coalesce((v_inv->>'invested')::int, 0),
                            'donated', coalesce((v_inv->>'donated')::int, 0),   -- 0145
                            'ceiling', coalesce((v_ceil->>'ceiling')::int, 0),   -- 0180 (a)
                            'ceiling_given', coalesce((v_ceil->>'given')::bigint, 0) + coalesce((v_ceil->>'shares')::bigint, 0),
                            'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes);
end $function$
