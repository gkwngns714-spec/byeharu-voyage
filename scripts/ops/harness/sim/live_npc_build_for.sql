CREATE OR REPLACE FUNCTION public.npc_build_for(p_fleet uuid, p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0180 (d): ONE hull for a merchant fleet that lies DOCKED at a harbour with a build yard, while her
-- house stands above her purse ceiling and the fleet and the house have room (public.earned_caps,
-- public.house_ship_max). The class: her flagship's class as her country's line builds it here
-- (public.npc_hull_for). Through the players' doors — cmd.do_build (the yard's labour, BUILD, into
-- this city; every rule of the yard: tier, country, skills, famous, name), cmd.do_hire (HIRE, her
-- hull's crew) and cmd.do_provision (PROVISION, her standing order's days) — with the hull's timber
-- and fittings endowed into this city's shed first, as her founding hulls were, then her gear
-- (public.npc_fit_loadout) and her level (public.npc_fix_level). She pays only from what stands above
-- her ceiling: a purchase that would take her under it, or any refusal (E_…), rolls the whole of it
-- back and is answered {built: 0, refused}. Null when there is nothing to try. Writes nothing on
-- standing_routes and leaves the fleet DOCKED (the 0101 rest is the route's). Lit only.
declare
  f        public.fleets%rowtype;
  v_purse  bigint;
  v_ceil   bigint;
  v_class  text;
  v_n      int;
  v_k      int;
  v_name   text;
  v_res    jsonb;
  v_ship   uuid;
  v_crew   int;
  v_days   int;
  v_after  bigint;
begin
  if not public.city_treasury_on() then
    return null;
  end if;
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or f.status <> 'DOCKED' or f.port_id is null then
    return null;
  end if;
  v_ceil := public.npc_purse_ceiling(f.player_id);
  select pl.ducats into v_purse from public.players pl where pl.id = f.player_id and pl.is_npc;
  if v_ceil is null or v_purse is null or v_purse <= v_ceil then
    return null;
  end if;
  if not exists (select 1 from public.port_buildings b where b.port_id = f.port_id and b.kind = 'building_yard') then
    return null;
  end if;
  select count(*) into v_n from public.ships where fleet_id = p_fleet;
  if v_n < 1
     or v_n >= (public.earned_caps(f.player_id)->>'fleet_ship_max')::int
     or (select count(*) from public.ships where player_id = f.player_id) >= public.house_ship_max(f.player_id) then
    return null;
  end if;
  select c.code into v_class
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet order by s.is_flagship desc, s.name limit 1;
  v_class := public.npc_hull_for(coalesce((select h.live_class from public.npc_line_hulls h where h.class_code = v_class), v_class),
                                 f.port_id);
  v_k := v_n + 1;
  loop
    v_name := left(btrim(f.name), 20) || ' ' || v_k;
    exit when not exists (select 1 from public.ships s where s.player_id = f.player_id and lower(s.name) = lower(v_name));
    v_k := v_k + 1;
  end loop;

  begin
    insert into public.player_storage (player_id, port_id, good_id, qty, basis)
    select f.player_id, f.port_id, hg.good_id, hg.qty, 0 from public.hull_recipe_goods hg where hg.class_code = v_class
    on conflict (player_id, port_id, good_id) do update set qty = public.player_storage.qty + excluded.qty;
    insert into public.player_items (player_id, port_id, item_code, qty)
    select f.player_id, f.port_id, hi.item_code, hi.qty from public.hull_recipe_items hi where hi.class_code = v_class
    on conflict (player_id, port_id, item_code) do update set qty = public.player_items.qty + excluded.qty;
    v_res := cmd.do_build(p_fleet, jsonb_build_object('class', v_class, 'name', v_name));
    v_ship := (v_res->>'ship')::uuid;
    perform public.npc_fit_loadout(v_ship);
    perform public.npc_fix_level(f.player_id);
    select c.crew_required into v_crew from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = v_ship;
    if coalesce(v_crew, 0) > 0 then
      perform cmd.do_hire(p_fleet, jsonb_build_object('count', v_crew));
    end if;
    select pr.days into v_days from public.provision_presets pr where pr.id = f.provision_preset_id;
    if v_days is not null then
      perform cmd.do_provision(p_fleet, jsonb_build_object('mode', 'DAYS', 'days', v_days));
    end if;
    select pl.ducats into v_after from public.players pl where pl.id = f.player_id;
    if v_after < v_ceil then
      perform cmd.refuse('E_UNDER_CEILING', format('the hull would take %s under her purse ceiling of %s', f.name, v_ceil),
                         cmd.figures(v_purse - v_ceil, v_purse - v_after, 'ducats'));
    end if;
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then
      raise;
    end if;
    return jsonb_build_object('built', 0, 'fleet', f.name, 'class', v_class,
                              'port', (select p.code from public.ports p where p.id = f.port_id),
                              'refused', split_part(sqlerrm, ':', 1));
  end;
  return jsonb_build_object('built', 1, 'fleet', f.name, 'ship', v_name, 'class', v_class,
                            'port', (select p.code from public.ports p where p.id = f.port_id),
                            'paid', v_purse - v_after);
end $function$
