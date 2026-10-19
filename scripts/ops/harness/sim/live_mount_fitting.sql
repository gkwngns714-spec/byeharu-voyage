CREATE OR REPLACE FUNCTION public.mount_fitting(p_ship uuid, p_item_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  k       public.item_kinds%rowtype;
  v_ship  public.ships%rowtype;
  v_slots int;
  v_used  int;
  v_open  jsonb;
  v_lvl   int;
  v_rack  text;      -- 0132: the RACK this item goes in, and the word the player reads for it
  v_word  text;
  v_deck  int;       -- 0132: what one unit costs of the two fitting budgets
  v_hands int;
  v_bud   jsonb;
begin
  -- 0126: PUT ONE FITTING ON ONE HULL. The lines below the lookups are cut verbatim out of
  -- cmd.do_fit (0074, re-cut by 0077); the door that called them keeps the store and the event.
  select * into k from public.item_kinds where code = p_item_code;
  if k.code is null then
    raise exception 'E_NO_SUCH_ITEM: nothing is called "%"', coalesce(p_item_code, '') using errcode = 'P0001';
  end if;
  select * into v_ship from public.ships where id = p_ship;
  if v_ship.id is null then
    raise exception 'E_NO_SUCH_SHIP: there is no ship %', p_ship using errcode = 'P0001';
  end if;
  -- 0132: ONE HOUSE'S FITTINGS, ONE AT A TIME (re-entrant: the doors took it first).
  perform public.fitting_lock(v_ship.player_id);
  -- 0133: WHAT THE ITEM NEEDS OF THE COMPANY that owns the hull — public.requirements_met, the one rule
  -- (nothing while skills_bite is off; the G1 items need nothing, so a merchant's loadout mounts as before).
  if not public.requirements_met(v_ship.player_id, 'item', k.code) then
    perform cmd.refuse('E_NEEDS_SKILL', public.requirements_refusal(v_ship.player_id, 'item', k.code),
      (select cmd.figures(u.have, u.need, 'level')
         from public.requirements_unmet(v_ship.player_id, 'item', k.code) u order by u.skill_name limit 1));
  end if;
  -- 0132: the item's RACK and its costs — public.item_profile, the one home of both — and what she
  -- carries in that rack, counted unit by unit ONCE (a RACK takes any item of its rack, EVE).
  select ip.rack, gr.word, ip.deck, ip.hands into v_rack, v_word, v_deck, v_hands
    from public.item_profile ip join public.gear_racks gr on gr.code = ip.rack
   where ip.item_code = k.code;
  -- 0158 (S13, §6.8): A REFIT IS FITTED ONLY AT A BUILD YARD — the port her fleet is docked at has a
  -- `building_yard` row (the one reading of a building, 0067). A merchant's loadout carries no refit.
  if v_rack = 'refit'
     and not exists (select 1 from public.fleets fl
                       join public.port_buildings b on b.port_id = fl.port_id and b.kind = 'building_yard'
                      where fl.id = v_ship.fleet_id and fl.status = 'DOCKED') then
    perform cmd.refuse('E_NO_YARD',
      format('%s is a refit, fitted only at a build yard, and %s has none', k.name,
             coalesce((select p.name from public.fleets fl join public.ports p on p.id = fl.port_id
                        where fl.id = v_ship.fleet_id), 'this place')));
  end if;
  -- 0133: GUN DRILL — what this unit needs of Hands, counted as world.ship_budget counts it.
  v_hands := public.drilled_hands(v_hands, v_rack, world.skill_pct(v_ship.player_id, v_ship.id, 'high_hands'));
  select count(*) into v_used
    from public.fitted_units u join public.item_profile ip on ip.item_code = u.item_code
   where u.ship_id = v_ship.id and ip.rack = v_rack;

  -- 0127: HER SLOTS OF THIS KIND AT HER LEVEL IN FORCE — world.ship_slots, the one reading of class_slots.
  -- While levels_bite is off nothing below refuses but 0077's E_NO_SLOT / E_SLOTS_FULL, as before.
  v_open  := world.ship_slots(v_ship.id);
  v_slots := coalesce((v_open->'open'->>v_rack)::int, 0);   -- 0132: her slots of this item's RACK
  if public.levels_bite_on() then
    v_lvl := public.level_in_force(coalesce((select sx.xp from public.ship_xp sx where sx.ship_id = v_ship.id), 0));
    -- 0133: "may I fit this" is no longer the SHIP's level (0127's gear level asks, empty, dropped here):
    -- it is the company's skills — public.requirements_met, above, for every hull.
    -- A kind whose open slots are taken and which a level opens more of is LOCKED, not full.
    if v_open->'locked' ? v_rack and v_used >= v_slots then
      perform cmd.refuse('E_SLOT_LOCKED',
        format('%s opens another %s slot at level %s', v_ship.name, v_word, v_open->'locked'->v_rack->>'at_level'),
        cmd.figures(v_lvl, (v_open->'locked'->v_rack->>'at_level')::int, 'level'));
    end if;
  end if;
  if coalesce(v_slots, 0) < 1 then
    raise exception 'E_NO_SLOT: a % has nowhere to put a %',
      (select name from public.ship_classes where id = v_ship.class_id), k.name using errcode = 'P0001';
  end if;

  -- 0132: her places in the item's RACK, against what she carries there (counted above, once).
  if v_used >= v_slots then
    perform cmd.refuse('E_SLOTS_FULL',
      format('%s has no free %s slot (%s / %s used)', v_ship.name, v_word, v_used, v_slots));
  end if;

  -- 0132: THE TWO FITTING BUDGETS (world.ship_budget, the one reading). Checked on a FIT only, so
  -- nothing already mounted is ever refused after the fact; an item that costs nothing never is.
  v_bud := world.ship_budget(v_ship.id);
  if v_deck > 0 and (v_bud->'deck'->>'used')::int + v_deck > (v_bud->'deck'->>'max')::int then
    perform cmd.refuse('E_OVER_DECK',
      format('Fitting %s takes %s deck; %s has %s / %s deck left', k.name, v_deck, v_ship.name,
             greatest(0, (v_bud->'deck'->>'max')::int - (v_bud->'deck'->>'used')::int), (v_bud->'deck'->>'max')::int),
      cmd.figures(greatest(0, (v_bud->'deck'->>'max')::int - (v_bud->'deck'->>'used')::int), v_deck, 'deck'));
  end if;
  if v_hands > 0 and (v_bud->'hands'->>'used')::int + v_hands > (v_bud->'hands'->>'max')::int then
    perform cmd.refuse('E_OVER_HANDS',
      format('Fitting %s takes %s hands; %s has %s / %s hands left', k.name, v_hands, v_ship.name,
             greatest(0, (v_bud->'hands'->>'max')::int - (v_bud->'hands'->>'used')::int), (v_bud->'hands'->>'max')::int),
      cmd.figures(greatest(0, (v_bud->'hands'->>'max')::int - (v_bud->'hands'->>'used')::int), v_hands, 'hands'));
  end if;

  -- 0132: ONE ROW PER MOUNTED UNIT.
  insert into public.fitted_units (ship_id, item_code) values (v_ship.id, k.code);
end $function$
