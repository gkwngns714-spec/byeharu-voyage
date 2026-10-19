CREATE OR REPLACE FUNCTION world.workstation(p_port uuid, p_fleet uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_player uuid := (select id from public.players where auth_uid = auth.uid());
  v_tier   int;
begin
  select b.tier into v_tier from public.port_buildings b
   where b.port_id = p_port and b.kind = 'workstation';

  return jsonb_build_object(
    'port_id', p_port,
    'tier', v_tier,
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', k.code, 'name', k.name, 'slot', k.slot, 'buys', k.buys, 'spends', k.spends,
        'note', k.note, 'volume', k.volume, 'ws_tier', k.ws_tier,
        'makeable', v_tier is not null and v_tier >= k.ws_tier
                    and kn.needs is null                                    -- 0135: and its skills (cmd.do_make)
                    and kn.made_in is null,                                 -- 0159: and, a Named item, its city
        -- 0135: this workshop's tier alone, so the screen can say WHICH of the two closed it.
        'tier_ok', v_tier is not null and v_tier >= k.ws_tier,
        -- 0133: the skills it needs that you lack — the E_NEEDS_SKILL sentence cmd.do_make (0135) and
        -- public.mount_fitting refuse with, or null.
        'needs', kn.needs,
        'owned_here', coalesce((select pi.qty from public.player_items pi
                                 where pi.player_id = v_player and pi.port_id = p_port
                                   and pi.item_code = k.code), 0),
        'recipe', (select coalesce(jsonb_agg(jsonb_build_object(
            'good', g.code, 'name', g.name, 'qty', ir.qty,
            'aboard', case when p_fleet is null then null
                           else public.fleet_cargo_qty(p_fleet, g.code) end)
            order by g.name), '[]'::jsonb)
          from public.item_recipes ir join public.goods g on g.id = ir.good_id
         where ir.item_code = k.code))
        -- 0159: a Named item away from its city says where it is made (public.made_only_in), only then
        || case when kn.made_in is null then '{}'::jsonb else jsonb_build_object('made_only_in', kn.made_in) end
        order by k.ws_tier, k.name), '[]'::jsonb)
      from public.item_kinds k
     cross join lateral (select public.requirements_refusal(v_player, 'item', k.code) as needs,
                                public.made_only_in(k.code, p_port) as made_in) kn
     where k.kind = 'fitting'));   -- 0135: once per item (0159: and its city); 0162: fittings only (a promotion item is never made)
end $function$
