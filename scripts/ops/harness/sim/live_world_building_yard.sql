CREATE OR REPLACE FUNCTION world.building_yard(p_port uuid)
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
   where b.port_id = p_port and b.kind = 'building_yard';

  return jsonb_build_object(
    'port_id', p_port,
    'tier', v_tier,
    'hulls', (select coalesce(jsonb_agg(jsonb_build_object(
        'class', c.code, 'name', c.name, 'tier', c.tier, 'note', h.note,
        'yard_tier', h.yard_tier, 'ducats', public.yard_labour(v_player, h.class_code),   -- 0135: what the door charges
        'hold', c.hold, 'speed_kn', c.speed_kn, 'crew_required', c.crew_required,
        'durability', c.durability, 'draft', c.draft,
        'buildable', v_tier is not null and v_tier >= h.yard_tier and yw.wrong is null   -- 0130: and its country
                     and yw.needs is null                                                -- 0133: and its skills
                     and yw.held is null,                                                -- 0165: and, a famous ship, not one it keeps
        -- 0130: the two halves of `buildable`, answered here so the screen re-derives neither: the
        -- tier half, and the country rule's own sentence (null where this port's country builds it).
        'tier_ok', v_tier is not null and v_tier >= h.yard_tier,
        'wrong_yard', yw.wrong,
        -- 0133: the skills it needs that you lack — cmd.do_build's own E_NEEDS_SKILL sentence, or null.
        'needs', yw.needs,
        -- 0130: the hull's country — its line and the flag it is shown under.
        'line', cp.line_code, 'line_name', sl.name, 'line_nation', sl.home_nation,
        -- WHAT IS ASHORE AGAINST WHAT SHE WANTS, both halves, so the screen states a shortfall
        -- rather than working one out. The rule is cmd.do_build's and this is a reading of it.
        --
        -- ONE SHAPE for timber and fittings alike - code, name, qty, have - because the screen
        -- draws them as one list of materials and a second shape would be a second renderer.
        'goods', (select coalesce(jsonb_agg(jsonb_build_object(
            'code', g.code, 'name', g.name, 'qty', hg.qty,
            'have', coalesce((select ps.qty from public.player_storage ps
                                 where ps.player_id = v_player and ps.port_id = p_port
                                   and ps.good_id = hg.good_id), 0))
            order by g.name), '[]'::jsonb)
          from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id
         where hg.class_code = h.class_code),
        'items', (select coalesce(jsonb_agg(jsonb_build_object(
            'code', k.code, 'name', k.name, 'qty', hi.qty,
            'have', coalesce((select pi.qty from public.player_items pi
                               where pi.player_id = v_player and pi.port_id = p_port
                                 and pi.item_code = hi.item_code), 0))
            order by k.name), '[]'::jsonb)
          from public.hull_recipe_items hi join public.item_kinds k on k.code = hi.item_code
         where hi.class_code = h.class_code))
        -- 0159: a hull's tech where it is not T1 (the yard's T2 badge); a T1 hull's entry is as before
        || case when cp.tech is distinct from 'T1' then jsonb_build_object('tech', cp.tech) else '{}'::jsonb end
        -- 0165: a famous ship the company keeps already says so (public.famous_held), only then
        || case when yw.held is null then '{}'::jsonb else jsonb_build_object('famous_held', yw.held) end
        order by h.yard_tier, c.name), '[]'::jsonb)
      from public.hull_recipes h join public.ship_classes c on c.code = h.class_code
      left join public.class_profile cp on cp.class_code = c.code      -- 0130
      left join public.ship_lines sl on sl.code = cp.line_code         -- 0130
      cross join lateral (select public.yard_wrong_country(p_port, c.code) as wrong,                -- 0130: once per hull
                                 public.requirements_refusal(v_player, 'hull', c.code) as needs,         -- 0133
                                 public.famous_held(v_player, c.code) as held) yw));                     -- 0165
end $function$
