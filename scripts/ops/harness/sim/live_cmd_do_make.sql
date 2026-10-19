CREATE OR REPLACE FUNCTION cmd.do_make(p_fleet uuid, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f       public.fleets%rowtype;
  k       public.item_kinds%rowtype;
  v_qty   int := greatest(1, coalesce((p_args->>'qty')::int, 1));
  v_tier  int;
  v_short text;
  v_spent jsonb := '[]'::jsonb;
  r       record;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and a fitting is made ashore', f.name, f.status using errcode = 'P0001';
  end if;

  select * into k from public.item_kinds where code = p_args->>'item';
  if k.code is null then
    raise exception 'E_NO_SUCH_ITEM: nothing is called "%"', coalesce(p_args->>'item', '') using errcode = 'P0001';
  end if;

  -- THE BUILDING DECIDES, NOT A LIST OF CITY NAMES (0067). A city makes what its workstation is
  -- good enough to make, which is where "some cities can craft" lives.
  select b.tier into v_tier from public.port_buildings b
   where b.port_id = f.port_id and b.kind = 'workstation';
  if v_tier is null then
    raise exception 'E_NO_WORKSTATION: this city keeps no workstation' using errcode = 'P0001';
  end if;
  if v_tier < k.ws_tier then
    raise exception 'E_WORKSTATION_TOO_SMALL: % needs a tier % workstation and this one is tier %',
      k.name, k.ws_tier, v_tier using errcode = 'P0001';
  end if;
  -- 0159 (S15, §6.2): A NAMED ITEM IS MADE ONLY IN ITS OWN CITY — public.made_only_in, the one sentence
  -- (the workshop screen serves the same one).
  if public.made_only_in(k.code, f.port_id) is not null then
    perform cmd.refuse('E_NOT_MADE_HERE', public.made_only_in(k.code, f.port_id));
  end if;
  -- 0135: WHAT THE ITEM NEEDS OF THE COMPANY — public.requirements_met, the one rule (skill_requirements),
  -- exactly as cmd.do_build asks it of a hull and public.mount_fitting of a fitting: gear that cannot be
  -- fitted cannot be made either. Dark (skills_bite off) no level counts, so a gated item is refused with
  -- " — ship skills are not in use yet"; an item that needs nothing (every G1 the live world makes, the
  -- nine ungated new G1, the figurehead grades) is made exactly as before.
  if not public.requirements_met(f.player_id, 'item', k.code) then
    perform cmd.refuse('E_NEEDS_SKILL', public.requirements_refusal(f.player_id, 'item', k.code),
      (select cmd.figures(u.have, u.need, 'level')
         from public.requirements_unmet(f.player_id, 'item', k.code) u order by u.skill_name limit 1));
  end if;

  -- THE MATERIALS COME OUT OF HER HOLD, so a fitting is the far end of a voyage: the inputs are
  -- ship-supplies, and 0065 put every good in one to three cities.
  select string_agg(format('%s (%s of %s)', g.name,
                           trim(to_char(public.fleet_cargo_qty(p_fleet, g.code), 'FM999999.99')),
                           trim(to_char(ir.qty * v_qty, 'FM999999.99'))), ', ' order by g.name)
    into v_short
    from public.item_recipes ir join public.goods g on g.id = ir.good_id
   where ir.item_code = k.code and public.fleet_cargo_qty(p_fleet, g.code) < ir.qty * v_qty;
  if v_short is not null then
    raise exception 'E_NO_MATERIALS: % is short of %', f.name, v_short using errcode = 'P0001';
  end if;

  for r in select g.code, g.name, ir.qty * v_qty as need
             from public.item_recipes ir join public.goods g on g.id = ir.good_id
            where ir.item_code = k.code order by g.code loop
    -- The ONE cargo mover (0007). A second way of taking a good out of a hold is the defect.
    perform public.fleet_unload(p_fleet, r.code, r.need);
    v_spent := v_spent || jsonb_build_object('good', r.code, 'qty', r.need);
  end loop;

  insert into public.player_items (player_id, port_id, item_code, qty)
  values (f.player_id, f.port_id, k.code, v_qty)
  on conflict (player_id, port_id, item_code) do update set qty = public.player_items.qty + excluded.qty;

  perform public.emit_event(f.player_id, 'MADE', jsonb_build_object(
    'fleet', f.name, 'item', k.name, 'qty', v_qty, 'spent', v_spent));

  return jsonb_build_object('item', k.code, 'name', k.name, 'qty', v_qty, 'spent', v_spent);
end $function$
