CREATE OR REPLACE FUNCTION cmd.do_build(p_fleet uuid, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f        public.fleets%rowtype;
  c        public.ship_classes%rowtype;
  h        public.hull_recipes%rowtype;
  v_tier   int;
  v_wrong  text;   -- 0130: the country rule's refusal, or null
  v_name   text := btrim(coalesce(p_args->>'name', ''));
  v_short  text;
  v_purse  bigint;
  v_ship   uuid;
  r        record;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and a hull is laid down ashore', f.name, f.status using errcode = 'P0001';
  end if;

  select * into c from public.ship_classes where code = p_args->>'class';
  if c.code is null then
    raise exception 'E_NO_SUCH_CLASS: no ship is called "%"', coalesce(p_args->>'class', '') using errcode = 'P0001';
  end if;
  select * into h from public.hull_recipes where class_code = c.code;
  if h.class_code is null then
    raise exception 'E_NOT_BUILDABLE: % is not a hull any yard lays down', c.name using errcode = 'P0001';
  end if;
  -- 0135: what the yard charges is public.hull_labour — the recipe's ducats × hull_labour_mult, the one
  -- reading (every later use of h.ducats — the purse check, the payment, the event — reads it).
  h.ducats := public.yard_labour(f.player_id, c.code);   -- 0154 (K2): hull_labour less Shipwright, the one reading

  select b.tier into v_tier from public.port_buildings b
   where b.port_id = f.port_id and b.kind = 'building_yard';
  if v_tier is null then
    raise exception 'E_NO_BUILDING_YARD: this city lays down no hulls' using errcode = 'P0001';
  end if;
  if v_tier < h.yard_tier then
    raise exception 'E_YARD_TOO_SMALL: a % wants a tier % yard and this one is tier %',
      c.name, h.yard_tier, v_tier using errcode = 'P0001';
  end if;
  -- 0130: a hull is built only in its line's countries — the one rule, public.yard_wrong_country.
  v_wrong := public.yard_wrong_country(f.port_id, c.code);
  if v_wrong is not null then
    raise exception 'E_WRONG_YARD: %', v_wrong using errcode = 'P0001';
  end if;
  -- 0133: WHAT THE HULL NEEDS OF THE COMPANY — public.requirements_met, the one rule (skill_requirements;
  -- nothing while skills_bite is off). The sentence and its figures are the rule's own.
  if not public.requirements_met(f.player_id, 'hull', c.code) then
    perform cmd.refuse('E_NEEDS_SKILL', public.requirements_refusal(f.player_id, 'hull', c.code),
      (select cmd.figures(u.have, u.need, 'level')
         from public.requirements_unmet(f.player_id, 'hull', c.code) u order by u.skill_name limit 1));
  end if;
  -- 0165 (S17): ONE OF EACH FAMOUS SHIP TO A HOUSE — public.famous_held, the one sentence (the build yard
  -- serves the same one). A famous hull takes the house's row first, so two orders of one house wait on
  -- each other and the second meets the first one's ship.
  if exists (select 1 from public.class_profile cp where cp.class_code = c.code and cp.tech = 'F') then
    perform 1 from public.players where id = f.player_id for update;
    if public.famous_held(f.player_id, c.code) is not null then
      perform cmd.refuse('E_FAMOUS_HELD', public.famous_held(f.player_id, c.code));
    end if;
  end if;

  -- A NAME IS THE PLAYER'S, and the same rule the founding ship is held to (0004).
  if length(v_name) < 3 or length(v_name) > 24 then
    raise exception 'E_PARSE: a ship is named in 3 to 24 letters' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.ships s where s.player_id = f.player_id and lower(s.name) = lower(v_name)) then
    raise exception 'E_NAME_TAKEN: you already keep a ship called %', v_name using errcode = 'P0001';
  end if;

  -- THE TIMBER, out of THIS city's shed. Named in full when short, because "you are short of
  -- materials" is the sentence that sends a player to count crates by hand.
  select string_agg(format('%s (%s of %s)', g.name,
                           trim(to_char(coalesce(ps.qty, 0), 'FM999999.99')),
                           trim(to_char(hg.qty, 'FM999999.99'))), ', ' order by g.name)
    into v_short
    from public.hull_recipe_goods hg
    join public.goods g on g.id = hg.good_id
    left join public.player_storage ps
      on ps.player_id = f.player_id and ps.port_id = f.port_id and ps.good_id = hg.good_id
   where hg.class_code = c.code and coalesce(ps.qty, 0) < hg.qty;
  if v_short is not null then
    raise exception 'E_NO_TIMBER: the shed here is short of %', v_short using errcode = 'P0001';
  end if;

  -- AND THE FITTINGS, standing in the same city (0068).
  select string_agg(format('%s (%s of %s)', k.name,
                           coalesce(pi.qty, 0), hi.qty), ', ' order by k.name)
    into v_short
    from public.hull_recipe_items hi
    join public.item_kinds k on k.code = hi.item_code
    left join public.player_items pi
      on pi.player_id = f.player_id and pi.port_id = f.port_id and pi.item_code = hi.item_code
   where hi.class_code = c.code and coalesce(pi.qty, 0) < hi.qty;
  if v_short is not null then
    raise exception 'E_NO_FITTINGS: you keep no % in this city', v_short using errcode = 'P0001';
  end if;

  select ducats into v_purse from public.players where id = f.player_id;
  if v_purse < h.ducats then
    raise exception 'E_NO_FUNDS: the yard asks % d. for the work and you hold %', h.ducats, v_purse
      using errcode = 'P0001';
  end if;

  -- SPEND. The shed and the store first, so a purse check that passed cannot leave a hull half paid
  -- for: any refusal after this point rolls the whole order back (0007's one-transaction rule).
  for r in select hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = c.code loop
    update public.player_storage set qty = qty - r.qty
     where player_id = f.player_id and port_id = f.port_id and good_id = r.good_id;
  end loop;
  delete from public.player_storage where player_id = f.player_id and port_id = f.port_id and qty <= 0;

  for r in select hi.item_code, hi.qty from public.hull_recipe_items hi where hi.class_code = c.code loop
    update public.player_items set qty = qty - r.qty
     where player_id = f.player_id and port_id = f.port_id and item_code = r.item_code;
  end loop;
  delete from public.player_items where player_id = f.player_id and port_id = f.port_id and qty <= 0;

  -- The ONE money mover, and the ONE record (0004). There is no debit function in this game: a payment is
  -- a credit of a NEGATIVE amount, so the ledger has one direction and one function, and every
  -- movement in the book is the same shape.
  perform public.pay_city(f.player_id, f.port_id, 'BUILD', h.ducats,
    public.emit_event(f.player_id, 'HULL_LAID_DOWN', jsonb_build_object(
      'fleet', f.name, 'ship', v_name, 'class', c.name, 'ducats', h.ducats)));

  -- SHE JOINS THE FLEET LYING HERE. The ship_max trigger (0021) is what refuses a ninth hull, and
  -- it is not re-implemented here: one cap, one place.
  -- 0096: THE ONE SHIP INSERT (public.commission_ship), the hull laid down empty and uncrewed.
  v_ship := public.commission_ship(f.player_id, p_fleet, c.code, v_name, false, false);

  return jsonb_build_object('ship', v_ship, 'name', v_name, 'class', c.code,
                            'fleet', f.name, 'ducats', h.ducats);
end $function$
