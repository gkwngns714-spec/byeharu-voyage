do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- rollback-0425.sql: the FORWARD ROLLBACK DRAFT of 0425 (owner only). To deploy it: copy it into supabase/migrations/ under the next number and
-- delete its first line (the guard). It swaps 0425's three hunks back (each must occur once, and the bodies must come out without a trace of
-- 0425), and drops the door, the read and the core. After it public.mount_fitting, world.workstation and public.client_rpc_entry_points are
-- main's bodies before 0425 to the byte, and no starter piece can be bought.
-- WHAT IT KEEPS, ON PURPOSE: the three item rows (item_kinds, item_profile, item_effects, item_recipes, item_use, item_unmade), the price table
-- public.starter_gear and the GEAR word. Pieces already fitted on players' ships keep working and wearing, and a player can still UNFIT and
-- FIT them like any piece (without the one-a-hull rule, which goes with the hunk). Deleting the item rows while a unit is fitted would orphan
-- it (fitted_units has a foreign key to item_kinds): that is a later, separate step, after
--   select count(*) from public.fitted_units where item_code like 'starter-%'   -- and player_items
-- reads 0. The Gear face of the client then reads nothing (it says the gear is not loaded) until the client is reverted too.
do $r$
declare
  h     record;
  v_def text;
  v_n   int;
begin
  perform set_config('lock_timeout', '5s', true);
  create temp table hunk_r425 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into hunk_r425 values
  (1, 'public.mount_fitting(uuid,text)',
$h$  -- 0425: A STARTER PIECE IS ONE OF ITS KIND TO A HULL (public.starter_gear): a cheap piece cannot be stacked. Every other item as before.
  if exists (select 1 from public.starter_gear sg where sg.item_code = k.code)
     and exists (select 1 from public.fitted_units u where u.ship_id = v_ship.id and u.item_code = k.code) then
    perform cmd.refuse('E_STARTER_ONE', format('%s already carries %s; a ship takes one', v_ship.name, k.name));
  end if;

  -- 0132: ONE ROW PER MOUNTED UNIT.
  insert into public.fitted_units (ship_id, item_code) values (v_ship.id, k.code);
$h$,
$h$  -- 0132: ONE ROW PER MOUNTED UNIT.
  insert into public.fitted_units (ship_id, item_code) values (v_ship.id, k.code);
$h$),
  (2, 'world.workstation(uuid,uuid)',
$h$     where k.kind = 'fitting'
       and not exists (select 1 from public.starter_gear sg where sg.item_code = k.code)));   -- 0135: once per item (0159: and its city); 0162: fittings only (a promotion item is never made); 0425: a starter piece is bought at the quay, never made
$h$,
$h$     where k.kind = 'fitting'));   -- 0135: once per item (0159: and its city); 0162: fittings only (a promotion item is never made)
$h$),
  (3, 'public.client_rpc_entry_points()',
$h$      ('world',       'stats_fleets',          ''),
      -- 0425: the Gear face (the starter pieces) and its press: buy one and fit it.
      ('world',       'starter_gear',          'uuid'),
      ('cmd',         'buy_starter',           'uuid, uuid, text'),
$h$,
$h$      ('world',       'stats_fleets',          ''),
$h$);
  for h in select * from hunk_r425 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception 'rollback-0425: hunk % of % occurs % time(s), not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
    if position('0425' in replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '')) > 0 then
      raise exception 'rollback-0425: % still names 0425', h.fn;
    end if;
  end loop;

  drop function cmd.buy_starter(uuid, uuid, text);
  drop function world.starter_gear(uuid);
  drop function public.buy_starter_for(uuid, uuid, uuid, text);

  if exists (select 1 from public.client_rpc_entry_points() e where e.function_name in ('starter_gear', 'buy_starter')) then
    raise exception 'rollback-0425: the registry still names the door or the read';
  end if;
  raise notice 'rollback-0425 ok: three hunks reversed, the door, the read and the core dropped; the pieces and their rows kept (see the header).';
end
$r$;
