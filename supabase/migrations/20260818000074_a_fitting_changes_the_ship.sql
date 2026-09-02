-- ===============================================================================================
-- 0074 - A FITTING CHANGES THE SHIP
-- ===============================================================================================
--
-- The owner, 2026-09-01:
--
--     "design - ship. each ship will have slots for items equipment, such as sail, anchor, and
--      more. Make 12 item (선수상 etc - in english) so that we can design our own ship."
--
--     "there should be also defense, speed, etc. and items should have speed related stats,
--      attack, accuracy, range, etc."
--
-- -- WHAT WAS MISSING, AND IT WAS THE POINT ------------------------------------------------------
-- 0068 made the twelve fittings and said plainly that none of them was MOUNTED. 0072 spent them as
-- raw material for a hull, which is a different thing again. Until now a suit of sails has been an
-- object you could own and destroy, and never once a sail.
--
-- This mounts them, and it is what makes "design our own ship" a sentence about this game.
--
-- -- THE RULE THAT MAKES IT A DESIGN AND NOT A SHOPPING LIST ------------------------------------
-- DESIGN_V1 1.3: EVERY FITTING BUYS ONE STAT AND SPENDS ANOTHER. Without it, designing a ship
-- means fitting everything, and the best hull is the one with the most slots. The generator refuses
-- data that breaks it and the self-assert refuses a world that breaks it - in both directions, so
-- it cannot be quietly relaxed by editing one of them.
--
-- The figurehead is the one exception and it is deliberate (1.4): it costs no stat, only ducats.
-- Until crew morale exists it changes NOTHING, and the row says so rather than inventing an effect
-- to look busy.
--
-- -- SLOTS ARE TYPED --------------------------------------------------------------------------
-- The owner: "for tier 1, sail, weapon, anchor would do. and 3 captain slot. it will grow as the
-- tier of the ship grows". So a barca has one rig, one weapon and one ground-tackle slot, and a nau
-- has seven slots across six kinds. A tier-3 hull is not simply more of anything.
--
-- `guns` stops being a stat and becomes what it always was: how many WEAPON fittings a hull may
-- carry. 1.2 - "that retires a dead column into a real one".
--
-- -- WHY THIS IS SAFE ON A LIVE WORLD ------------------------------------------------------------
-- world.ship_stat() is the one reading of an effective stat, and public.ship_hold_capacity and
-- voyage.ship_speed are RE-CUT to ask it. Both are supersedes of functions every fleet depends on -
-- so the property that matters is that the change is a NO-OP WHILE NOTHING IS FITTED, and no ship
-- in the world has anything fitted the moment this file runs. The self-assert proves it on every
-- hull that exists: effective equals rated, to the digit, for all of them.
-- ===============================================================================================

create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $fn$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0074 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

-- EVERY HULL AFLOAT, AS SHE SAILS TODAY. The two re-cuts below must not move one of these numbers.
create temporary table hulls_before_0074 as
  select s.id, public.ship_hold_capacity(s.id) as hold, voyage.ship_speed(s.id) as speed
    from public.ships s;

-- -- 1. THE SIX STATS A HULL DID NOT HAVE ---------------------------------------------------------
alter table public.ship_classes
  add column if not exists handling int not null default 50 check (handling between 0 and 100),
  add column if not exists armour   int not null default 0  check (armour between 0 and 100),
  add column if not exists attack   int not null default 0  check (attack >= 0),
  add column if not exists accuracy int not null default 0  check (accuracy between 0 and 100),
  add column if not exists reach    int not null default 0  check (reach between 0 and 100),
  add column if not exists sighting numeric(5,1) not null default 8 check (sighting > 0),
  add column if not exists stat_note text;

comment on column public.ship_classes.reach is
  'The band she fights at: low is boarding, high is gunnery (DESIGN 1.2). Boarding gear pulls it '
  'DOWN on purpose - a fitting that makes her worse at range is what makes her good up close.';
comment on column public.ship_classes.guns is
  '0074: this is no longer a stat. It is how many WEAPON fittings this hull may mount - the count '
  'that public.class_slots carries for every other kind of slot.';

create temporary table want_class_stats_0074 (
  class_code text, handling int, armour int, attack int, accuracy int, reach int,
  sighting numeric, note text);
insert into want_class_stats_0074 values
  ('barca', 70, 5, 0, 0, 20, 8, 'A coaster: turns on a sixpence, carries nothing that shoots, and sees as far as her one short mast allows.'),
  ('carlat', 75, 12, 20, 40, 45, 10, 'The lateen caravel — the handiest hull afloat, with two guns aboard because the coast is not always friendly.'),
  ('nau', 45, 30, 120, 55, 70, 14, 'Four hundred tuns of ship: slow to answer the helm, hard to hurt, and she fights at a distance because she must.');

update public.ship_classes c
   set handling = w.handling, armour = w.armour, attack = w.attack, accuracy = w.accuracy,
       reach = w.reach, sighting = w.sighting, stat_note = w.note
  from want_class_stats_0074 w where w.class_code = c.code;

-- -- 2. SLOTS, TYPED AND BY TIER -------------------------------------------------------------------
create table if not exists public.class_slots (
  class_code text not null references public.ship_classes(code) on delete cascade,
  slot       text not null,
  count      int  not null check (count > 0),
  primary key (class_code, slot)
);

create table if not exists public.class_cabins (
  class_code text primary key references public.ship_classes(code) on delete cascade,
  cabins     int not null check (cabins > 0)
);

comment on table public.class_slots is
  'How many fittings of each KIND a hull may carry. Typed on purpose (DESIGN 1.5): a tier-3 hull is '
  'not simply more of anything. The weapon count is public.ship_classes.guns, which is why it is '
  'not repeated here.';
comment on table public.class_cabins is
  'How many captains a hull can berth. The owner: "3 captain slot. it will grow as the tier of the '
  'ship grows". Nothing reads it yet - captain ranks and cabins are their own slice - and it is '
  'authored now so that slice does not have to re-open this one.';

insert into public.class_slots (class_code, slot, count) values
  ('barca', 'rig', 1),
  ('barca', 'weapon', 1),
  ('barca', 'ground-tackle', 1),
  ('carlat', 'rig', 1),
  ('carlat', 'weapon', 2),
  ('carlat', 'ground-tackle', 1),
  ('carlat', 'steering', 1),
  ('nau', 'rig', 2),
  ('nau', 'weapon', 3),
  ('nau', 'ground-tackle', 1),
  ('nau', 'steering', 1),
  ('nau', 'hull', 1),
  ('nau', 'lookout', 1),
  ('nau', 'flourish', 1)
on conflict (class_code, slot) do update set count = excluded.count;

insert into public.class_cabins (class_code, cabins) values
  ('barca', 3),
  ('carlat', 4),
  ('nau', 5)
on conflict (class_code) do update set cabins = excluded.cabins;

-- -- 3. WHAT EACH FITTING DOES, IN NUMBERS ----------------------------------------------------------
create table if not exists public.item_effects (
  item_code text not null references public.item_kinds(code) on delete cascade,
  stat      text not null check (stat in ('hold','speed','handling','draft','durability','armour','attack','accuracy','reach','sighting')),
  delta     numeric(8,2) not null check (delta <> 0),
  primary key (item_code, stat)
);

comment on table public.item_effects is
  'DESIGN 1.3 in numbers: every fitting buys one stat and spends another. item_kinds.buys and '
  '.spends say the same thing in words, and 0074 asserts the two agree in SHAPE - at least one '
  'positive and one negative for everything except the figurehead.';

insert into public.item_effects (item_code, stat, delta) values
  ('suit-of-sails', 'speed', 0.6),
  ('suit-of-sails', 'handling', -8),
  ('bowsprit-and-jib', 'handling', 10),
  ('bowsprit-and-jib', 'speed', 0.2),
  ('bowsprit-and-jib', 'durability', -40),
  ('rudder-and-helm', 'handling', 14),
  ('rudder-and-helm', 'hold', -6),
  ('anchor-and-cable', 'handling', 4),
  ('anchor-and-cable', 'hold', -8),
  ('ballast', 'handling', 8),
  ('ballast', 'armour', 6),
  ('ballast', 'speed', -0.4),
  ('copper-sheathing', 'armour', 14),
  ('copper-sheathing', 'durability', 120),
  ('copper-sheathing', 'speed', -0.3),
  ('broadside-guns', 'attack', 60),
  ('broadside-guns', 'reach', 15),
  ('broadside-guns', 'hold', -20),
  ('broadside-guns', 'handling', -6),
  ('boarding-gear', 'attack', 35),
  ('boarding-gear', 'reach', -20),
  ('powder-magazine', 'attack', 25),
  ('powder-magazine', 'accuracy', 12),
  ('powder-magazine', 'hold', -10),
  ('powder-magazine', 'durability', -60),
  ('crows-nest', 'sighting', 5),
  ('crows-nest', 'handling', -4),
  ('hold-fittings', 'hold', 25),
  ('hold-fittings', 'speed', -0.35),
  ('hold-fittings', 'handling', -5)
on conflict (item_code, stat) do update set delta = excluded.delta;

alter table public.class_slots   enable row level security;
alter table public.class_cabins  enable row level security;
alter table public.item_effects  enable row level security;
drop policy if exists class_slots_read on public.class_slots;
create policy class_slots_read on public.class_slots for select to anon, authenticated using (true);
drop policy if exists class_cabins_read on public.class_cabins;
create policy class_cabins_read on public.class_cabins for select to anon, authenticated using (true);
drop policy if exists item_effects_read on public.item_effects;
create policy item_effects_read on public.item_effects for select to anon, authenticated using (true);

-- -- 4. WHAT IS ACTUALLY MOUNTED ---------------------------------------------------------------------
create table if not exists public.ship_fittings (
  ship_id   uuid not null references public.ships(id) on delete cascade,
  item_code text not null references public.item_kinds(code),
  qty       int  not null check (qty > 0),
  primary key (ship_id, item_code)
);

comment on table public.ship_fittings is
  'What this hull is carrying, mounted. A fitting mounted here has LEFT the player''s store at the '
  'port (0068) - it is part of the ship now, which is what DESIGN 6.2 means by "fittings mounted '
  'on a ship leave the inventory".';

alter table public.ship_fittings enable row level security;
drop policy if exists ship_fittings_read on public.ship_fittings;
create policy ship_fittings_read on public.ship_fittings for select to authenticated
  using (exists (select 1 from public.ships s join public.players p on p.id = s.player_id
                  where s.id = ship_id and p.auth_uid = auth.uid()));

-- -- 5. THE ONE READING OF AN EFFECTIVE STAT ----------------------------------------------------------
create or replace function world.ship_stat(p_ship uuid, p_stat text)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $ss$
declare
  v_base  numeric;
  v_delta numeric;
begin
  select case p_stat
           when 'hold'       then c.hold
           when 'speed'      then c.speed_kn
           when 'handling'   then c.handling
           when 'draft'      then c.draft
           when 'durability' then c.durability
           when 'armour'     then c.armour
           when 'attack'     then c.attack
           when 'accuracy'   then c.accuracy
           when 'reach'      then c.reach
           when 'sighting'   then c.sighting
         end
    into v_base
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.id = p_ship;
  if v_base is null then
    raise exception 'E_NO_SUCH_STAT: no ship % has a stat called "%"', p_ship, p_stat using errcode = 'P0001';
  end if;

  select coalesce(sum(e.delta * f.qty), 0) into v_delta
    from public.ship_fittings f
    join public.item_effects e on e.item_code = f.item_code and e.stat = p_stat
   where f.ship_id = p_ship;

  -- A FLOOR, NOT A CLAMP AT THE TOP. Fittings that spend a stat must not be able to drive a hull
  -- to zero speed or negative hold - she would become unsailable and there would be no way back
  -- except unfitting, which a player at sea cannot do.
  return greatest(case when p_stat in ('speed', 'sighting') then 0.5 else 0 end, v_base + v_delta);
end $ss$;

revoke all on function world.ship_stat(uuid, text) from public, anon, authenticated;

-- -- 6. THE TWO AUTHORITIES ASK IT ---------------------------------------------------------------------
-- These are supersedes of functions every fleet in the world depends on. The change is a NO-OP
-- while nothing is fitted, and nothing is fitted the moment this file runs - which the self-assert
-- proves on every hull that exists rather than asserting in prose.
select pg_temp.recut('public.ship_hold_capacity(uuid)'::regprocedure, false,
  $c0$  select floor(c.hold * (1 + public.fleet_officer_bonus(s.fleet_id, 'QUARTERMASTER')))
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
   where s.id = p_ship$c0$,
  $c1$  -- 0074: the RATED hull became the FITTED hull. world.ship_stat is the one reading of what a
  -- stat actually is; the quartermaster's stretch is applied to that, in the same order as before.
  select floor(world.ship_stat(p_ship, 'hold') * (1 + public.fleet_officer_bonus(s.fleet_id, 'QUARTERMASTER')))
    from public.ships s
   where s.id = p_ship$c1$);

select pg_temp.recut('voyage.ship_speed(uuid)'::regprocedure, false,
  $s0$  v_fill := least(1.0, (v_cargo_t + s.water_t + s.food_t) / c.hold);$s0$,
  $s1$  -- 0074: how full she is, and how fast she is, are both read off the FITTED hull now.
  v_fill := least(1.0, (v_cargo_t + s.water_t + s.food_t) / world.ship_stat(p_ship, 'hold'));$s1$,
  $s2$  return round(c.speed_kn * v_hull * v_load * v_crew * public.wc_num('wind_mult_v0'), 4);$s2$,
  $s3$  return round(world.ship_stat(p_ship, 'speed') * v_hull * v_load * v_crew * public.wc_num('wind_mult_v0'), 4);$s3$);

-- -- 7. MOUNTING ONE, AND TAKING IT OFF ---------------------------------------------------------------
-- A fitting comes out of your store AT THIS PORT (0068) and becomes part of the hull; taking it off
-- puts it back in the same store. That is DESIGN 6.2's "fittings mounted on a ship leave the
-- inventory" in both directions, and it means a hull cannot be fitted from the far side of the map.
create or replace function cmd.do_fit(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $df$
declare
  f       public.fleets%rowtype;
  k       public.item_kinds%rowtype;
  v_ship  public.ships%rowtype;
  v_have  int;
  v_slots int;
  v_used  int;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and a fitting goes on alongside', f.name, f.status using errcode = 'P0001';
  end if;

  select * into k from public.item_kinds where code = p_args->>'item';
  if k.code is null then
    raise exception 'E_NO_SUCH_ITEM: nothing is called "%"', coalesce(p_args->>'item', '') using errcode = 'P0001';
  end if;

  -- WHICH HULL. Named, or the flagship - the ship a player means when they name none.
  if coalesce(p_args->>'ship', '') <> '' then
    select * into v_ship from public.ships
     where fleet_id = p_fleet and cmd.fold(name) = cmd.fold(p_args->>'ship');
    if v_ship.id is null then
      raise exception 'E_NO_SUCH_SHIP: no ship of % is called "%"', f.name, p_args->>'ship' using errcode = 'P0001';
    end if;
  else
    select * into v_ship from public.ships where fleet_id = p_fleet
     order by is_flagship desc, name limit 1;
    if v_ship.id is null then
      raise exception 'E_NO_SHIPS: % has no hull to fit', f.name using errcode = 'P0001';
    end if;
  end if;

  select coalesce(qty, 0) into v_have from public.player_items
   where player_id = f.player_id and port_id = f.port_id and item_code = k.code;
  if coalesce(v_have, 0) < 1 then
    raise exception 'E_NONE_HERE: you keep no % in this city', k.name using errcode = 'P0001';
  end if;

  -- HOW MANY OF THIS KIND SHE MAY CARRY. The weapon count lives on ship_classes.guns, which 0074
  -- retired from being a stat into being exactly this; every other kind is a class_slots row.
  if k.slot = 'weapon' then
    select c.guns into v_slots from public.ship_classes c where c.id = v_ship.class_id;
  else
    select coalesce(cs.count, 0) into v_slots
      from public.ship_classes c
      left join public.class_slots cs on cs.class_code = c.code and cs.slot = k.slot
     where c.id = v_ship.class_id;
  end if;
  if coalesce(v_slots, 0) < 1 then
    raise exception 'E_NO_SLOT: a % has nowhere to put a %',
      (select name from public.ship_classes where id = v_ship.class_id), k.name using errcode = 'P0001';
  end if;

  select coalesce(sum(sf.qty), 0) into v_used
    from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
   where sf.ship_id = v_ship.id and ik.slot = k.slot;
  if v_used >= v_slots then
    raise exception 'E_SLOTS_FULL: % already fills her % % slot(s)',
      v_ship.name, v_slots, k.slot using errcode = 'P0001';
  end if;

  update public.player_items set qty = qty - 1
   where player_id = f.player_id and port_id = f.port_id and item_code = k.code;
  delete from public.player_items
   where player_id = f.player_id and port_id = f.port_id and item_code = k.code and qty <= 0;

  insert into public.ship_fittings (ship_id, item_code, qty) values (v_ship.id, k.code, 1)
  on conflict (ship_id, item_code) do update set qty = public.ship_fittings.qty + 1;

  perform public.emit_event(f.player_id, 'FITTED', jsonb_build_object(
    'fleet', f.name, 'ship', v_ship.name, 'item', k.name));

  return jsonb_build_object('ship', v_ship.name, 'item', k.code,
    'hold', public.ship_hold_capacity(v_ship.id), 'speed', voyage.ship_speed(v_ship.id));
end $df$;

create or replace function cmd.do_unfit(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $du$
declare
  f      public.fleets%rowtype;
  k      public.item_kinds%rowtype;
  v_ship public.ships%rowtype;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    -- THE REASON THE FLOOR IN world.ship_stat EXISTS: there is no taking a fitting off at sea, so a
    -- hull must never be fittable into a standstill.
    raise exception 'E_NOT_DOCKED: % is % and a fitting comes off alongside', f.name, f.status using errcode = 'P0001';
  end if;

  select * into k from public.item_kinds where code = p_args->>'item';
  if k.code is null then
    raise exception 'E_NO_SUCH_ITEM: nothing is called "%"', coalesce(p_args->>'item', '') using errcode = 'P0001';
  end if;

  if coalesce(p_args->>'ship', '') <> '' then
    select * into v_ship from public.ships
     where fleet_id = p_fleet and cmd.fold(name) = cmd.fold(p_args->>'ship');
  else
    select s.* into v_ship from public.ships s
      join public.ship_fittings sf on sf.ship_id = s.id and sf.item_code = k.code
     where s.fleet_id = p_fleet order by s.is_flagship desc, s.name limit 1;
  end if;
  if v_ship.id is null then
    raise exception 'E_NOT_FITTED: no hull of % carries a %', f.name, k.name using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.ship_fittings where ship_id = v_ship.id and item_code = k.code) then
    raise exception 'E_NOT_FITTED: % carries no %', v_ship.name, k.name using errcode = 'P0001';
  end if;

  -- DELETE THE LAST ONE RATHER THAN DECREMENT IT TO ZERO: ship_fittings carries check (qty > 0),
  -- so an update to 0 is refused before any tidying delete could run. The check is right - a row
  -- saying "she carries none of these" is not a fact worth keeping - so the code bends, not it.
  if (select qty from public.ship_fittings where ship_id = v_ship.id and item_code = k.code) <= 1 then
    delete from public.ship_fittings where ship_id = v_ship.id and item_code = k.code;
  else
    update public.ship_fittings set qty = qty - 1 where ship_id = v_ship.id and item_code = k.code;
  end if;

  -- BACK INTO THE STORE IN THIS CITY, which is the same door it came out of.
  insert into public.player_items (player_id, port_id, item_code, qty)
  values (f.player_id, f.port_id, k.code, 1)
  on conflict (player_id, port_id, item_code) do update set qty = public.player_items.qty + 1;

  perform public.emit_event(f.player_id, 'UNFITTED', jsonb_build_object(
    'fleet', f.name, 'ship', v_ship.name, 'item', k.name));

  return jsonb_build_object('ship', v_ship.name, 'item', k.code,
    'hold', public.ship_hold_capacity(v_ship.id), 'speed', voyage.ship_speed(v_ship.id));
end $du$;

revoke all on function cmd.do_fit(uuid, jsonb) from public, anon, authenticated;
revoke all on function cmd.do_unfit(uuid, jsonb) from public, anon, authenticated;

-- -- 8. TWO MORE WORDS ---------------------------------------------------------------------------------
select pg_temp.recut('cmd.parse(uuid, uuid, text)'::regprocedure, false,
  $g0$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','MAKE','STORE','TAKE','BUILD','CANCEL','CLEAR') then$g0$,
  $g1$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','MAKE','STORE','TAKE','BUILD','FIT','UNFIT','CANCEL','CLEAR') then$g1$,
  $g2$  elsif v_verb = 'BUILD' then$g2$,
  $g3$  elsif v_verb in ('FIT','UNFIT') then
    -- FIT <fitting> [ON <ship...>]. The ship is optional and defaults to the flagship, because a
    -- house with one hull should not have to name her.
    if i > n then
      raise exception 'E_PARSE: % needs a fitting', v_verb using errcode = 'P0001';
    end if;
    v_args := jsonb_build_object('item', cmd.resolve_item(t[i]));
    i := i + 1;
    if i <= n and upper(cmd.fold(t[i])) = 'ON' then i := i + 1; end if;
    if i <= n then
      v_args := v_args || jsonb_build_object('ship', btrim(array_to_string(t[i:n], ' ')));
      i := n + 1;
    end if;

  elsif v_verb = 'BUILD' then$g3$);

select pg_temp.recut('cmd.verb_schema()'::regprocedure, false,
  $v0$    {"verb":"REPAIR","args":[$v0$,
  $v1$    {"verb":"FIT","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"item","type":"item","required":true},
       {"name":"ship","type":"text","required":false,"keyword":"ON"}],
     "help":"Mount a fitting on one of her hulls.",
     "note":"It comes out of your store in this city and becomes part of the ship. Every fitting buys one thing and costs another, and a hull has only so many slots of each kind."},
    {"verb":"UNFIT","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"item","type":"item","required":true},
       {"name":"ship","type":"text","required":false,"keyword":"ON"}],
     "help":"Take a fitting off again and put it back in this city.",
     "note":"Alongside only. There is no changing your mind at sea."},
    {"verb":"REPAIR","args":[$v1$);

select pg_temp.recut('cmd.execute_order(uuid)'::regprocedure, false,
  $e0$               when 'BUILD'     then cmd.do_build(o.fleet_id, o.args)$e0$,
  $e1$               when 'BUILD'     then cmd.do_build(o.fleet_id, o.args)
               when 'FIT'       then cmd.do_fit(o.fleet_id, o.args)
               when 'UNFIT'     then cmd.do_unfit(o.fleet_id, o.args)$e1$);

select pg_temp.recut('cmd.preview(uuid, text, jsonb)'::regprocedure, false,
  $p0$               when 'BUILD'     then cmd.do_build((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p0$,
  $p1$               when 'BUILD'     then cmd.do_build((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'FIT'       then cmd.do_fit((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'UNFIT'     then cmd.do_unfit((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p1$);

-- -- 9. THE FLEET SAYS WHAT SHE CARRIES ------------------------------------------------------------------
-- FLEETS is a reading room - "no commands here, every row is a READ" - so what lands there is the
-- FACT of what is mounted and what it is doing to her, beside the rated hull it is changing.
select pg_temp.recut('world.fleets()'::regprocedure, false,
  $w0$                 'water_t', s.water_t, 'food_t', s.food_t) order by s.is_flagship desc, s.name), '[]'::jsonb)$w0$,
  $w1$                 'water_t', s.water_t, 'food_t', s.food_t,
                 -- 0074: what she carries, and what it bought her. `speed_rated` beside `speed` is
                 -- the same shape `hold_rated` beside `hold` has had since 0017: the number the
                 -- hull is rated at, and the number she actually makes.
                 'speed', voyage.ship_speed(s.id), 'speed_rated', c.speed_kn,
                 'handling', world.ship_stat(s.id, 'handling'),
                 'armour', world.ship_stat(s.id, 'armour'),
                 'attack', world.ship_stat(s.id, 'attack'),
                 'accuracy', world.ship_stat(s.id, 'accuracy'),
                 'reach', world.ship_stat(s.id, 'reach'),
                 'sighting', world.ship_stat(s.id, 'sighting'),
                 'fittings', (select coalesce(jsonb_agg(jsonb_build_object(
                     'code', ik.code, 'name', ik.name, 'slot', ik.slot, 'qty', sf.qty)
                     order by ik.slot, ik.name), '[]'::jsonb)
                   from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
                  where sf.ship_id = s.id),
                 'slots', (select coalesce(jsonb_object_agg(cs.slot, cs.count), '{}'::jsonb)
                   from public.class_slots cs where cs.class_code = c.code)
                 || jsonb_build_object('weapon', c.guns),
                 'cabins', (select cabins from public.class_cabins where class_code = c.code)) order by s.is_flagship desc, s.name), '[]'::jsonb)$w1$);

-- -- SELF-ASSERT ------------------------------------------------------------------------------------
do $$
declare
  v_bad   int;
  v_ship  uuid;
  v_hold0 numeric;
  v_hold1 numeric;
  v_spd0  numeric;
  v_spd1  numeric;
  v_grants int;
  v_player uuid;
  v_fleet  uuid;
  v_port   uuid;
  v_ship2  uuid;
  v_res    jsonb;
  c_uid constant uuid := '00000000-0074-4000-8000-000000000001';
begin
  -- (a) EVERY FITTING BUYS ONE AND SPENDS ONE. The rule that makes this a design; checked in the
  --     WORLD as well as in the generator, so relaxing one does not relax the other.
  select count(*) into v_bad from public.item_kinds k
   where k.code <> 'figurehead'
     and not (exists (select 1 from public.item_effects e where e.item_code = k.code and e.delta > 0)
          and exists (select 1 from public.item_effects e where e.item_code = k.code and e.delta < 0));
  if v_bad <> 0 then
    raise exception '0074 self-assert FAIL: % fitting(s) buy a stat without spending one', v_bad;
  end if;
  if exists (select 1 from public.item_effects where item_code = 'figurehead') then
    raise exception '0074 self-assert FAIL: the figurehead costs a stat - 1.4 says it costs only ducats';
  end if;

  -- (b) EVERY FITTING HAS SOMEWHERE TO GO. A fitting no hull in the world can mount is content that
  --     looks real and is not - the same class of defect as a recipe with a dead ingredient.
  select count(*) into v_bad from public.item_kinds k
   where not exists (select 1 from public.class_slots cs where cs.slot = k.slot)
     and not (k.slot = 'weapon' and exists (select 1 from public.ship_classes where guns > 0));
  if v_bad <> 0 then
    raise exception '0074 self-assert FAIL: % fitting(s) fit no hull in the world', v_bad;
  end if;

  -- (c) SLOTS GROW WITH THE TIER, which is the owner's own sentence. A tier-3 hull that carried no
  --     more than a tier-1 would make the whole table decoration.
  if (select sum(count) from public.class_slots where class_code = 'nau')
     <= (select sum(count) from public.class_slots where class_code = 'barca') then
    raise exception '0074 self-assert FAIL: a nau carries no more fittings than a barca';
  end if;
  if (select cabins from public.class_cabins where class_code = 'barca') <> 3 then
    raise exception '0074 self-assert FAIL: a tier-1 hull does not berth the 3 captains the owner asked for';
  end if;

  -- (d) NOTHING MOVED. The claim that makes this safe on a live world: both re-cut authorities
  --     return exactly what they returned before, for every hull afloat, because nothing is fitted.
  select count(*) into v_bad
    from hulls_before_0074 b
   where public.ship_hold_capacity(b.id) is distinct from b.hold
      or voyage.ship_speed(b.id) is distinct from b.speed;
  if v_bad <> 0 then
    raise exception '0074 self-assert FAIL: % hull(s) changed hold or speed without a single fitting mounted', v_bad;
  end if;

  -- (e) AND A FITTING REALLY DOES CHANGE HER. Mounted, measured, and taken off again - which is the
  --     positive control on (d): if mounting changed nothing, (d) would pass on a dead feature.
  select id into v_ship from public.ships order by created_at limit 1;
  if v_ship is null then
    raise exception '0074 self-assert FAIL: no hull exists to test a fitting on';
  end if;
  v_hold0 := world.ship_stat(v_ship, 'hold');
  v_spd0  := world.ship_stat(v_ship, 'speed');
  insert into public.ship_fittings (ship_id, item_code, qty) values (v_ship, 'hold-fittings', 1);
  v_hold1 := world.ship_stat(v_ship, 'hold');
  v_spd1  := world.ship_stat(v_ship, 'speed');
  if v_hold1 <= v_hold0 then
    raise exception '0074 self-assert FAIL: hold fittings bought no hold (% -> %)', v_hold0, v_hold1;
  end if;
  if v_spd1 >= v_spd0 then
    raise exception '0074 self-assert FAIL: hold fittings spent no speed (% -> %)', v_spd0, v_spd1;
  end if;
  -- AND THE HULL AUTHORITY SEES IT, not just the stat function - otherwise a fitting changes a
  -- number nobody reads.
  if public.ship_hold_capacity(v_ship) <= (select hold from hulls_before_0074 where id = v_ship) then
    raise exception '0074 self-assert FAIL: she carries more and her CAPACITY did not move';
  end if;
  delete from public.ship_fittings where ship_id = v_ship;
  if world.ship_stat(v_ship, 'hold') is distinct from v_hold0 then
    raise exception '0074 self-assert FAIL: taking the fitting off did not put the hull back';
  end if;

  -- (f) A HULL CANNOT BE FITTED INTO A STANDSTILL. Everything that spends speed, all at once, must
  --     still leave her able to sail - there is no way to unfit at sea.
  insert into public.ship_fittings (ship_id, item_code, qty)
  select v_ship, e.item_code, 3 from (select distinct item_code from public.item_effects where stat = 'speed' and delta < 0) e;
  if world.ship_stat(v_ship, 'speed') <= 0 then
    raise exception '0074 self-assert FAIL: a hull can be fitted to a dead stop, and nothing can be taken off at sea';
  end if;
  delete from public.ship_fittings where ship_id = v_ship;

  -- (g) AND IT WORKS THROUGH THE ONE DOOR. Everything above tests world.ship_stat; this tests the
  --      VERB, which is the only way a player can reach any of it.
  v_player := public.new_house(c_uid, 'Casa Velame', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  select port_id into v_port from public.fleets where id = v_fleet;
  select id into v_ship2 from public.ships where fleet_id = v_fleet;
  perform cmd.assume_identity(c_uid);

  -- One suit of sails, standing in this city the way 0068 leaves one.
  insert into public.player_items (player_id, port_id, item_code, qty)
  values (v_player, v_port, 'suit-of-sails', 1)
  on conflict (player_id, port_id, item_code) do update set qty = 1;

  v_spd0 := voyage.ship_speed(v_ship2);
  v_res := cmd.issue(v_fleet, 'FIT sails', null, null);
  if not (v_res->>'ok')::boolean then
    raise exception '0074 self-assert FAIL: FIT was refused: %', v_res->'order';
  end if;
  if not exists (select 1 from public.ship_fittings where ship_id = v_ship2 and item_code = 'suit-of-sails') then
    raise exception '0074 self-assert FAIL: FIT said yes and mounted nothing';
  end if;
  -- IT LEFT THE STORE. A fitting that is both on the ship and in the shed has been copied.
  if coalesce((select qty from public.player_items
                where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails'), 0) <> 0 then
    raise exception '0074 self-assert FAIL: the sails are mounted AND still in store';
  end if;
  if voyage.ship_speed(v_ship2) <= v_spd0 then
    raise exception '0074 self-assert FAIL: a suit of sails bought her no speed (% -> %)',
      v_spd0, voyage.ship_speed(v_ship2);
  end if;

  -- A SECOND ONE HAS NOWHERE TO GO: a barca has one rig slot.
  insert into public.player_items (player_id, port_id, item_code, qty)
  values (v_player, v_port, 'suit-of-sails', 1)
  on conflict (player_id, port_id, item_code) do update set qty = 1;
  perform cmd.clear(v_fleet, true);
  v_res := cmd.issue(v_fleet, 'FIT sails', null, null);
  if (v_res->>'ok')::boolean then
    raise exception '0074 self-assert FAIL: a barca mounted two suits of sails in one rig slot';
  end if;
  if v_res->'refusal'->>'code' <> 'E_SLOTS_FULL' then
    raise exception '0074 self-assert FAIL: a full slot refused with % rather than E_SLOTS_FULL',
      v_res->'refusal'->>'code';
  end if;

  -- AND IT COMES OFF AGAIN, back into the same city.
  perform cmd.clear(v_fleet, true);
  v_res := cmd.issue(v_fleet, 'UNFIT sails', null, null);
  if not (v_res->>'ok')::boolean then
    raise exception '0074 self-assert FAIL: UNFIT was refused: %', v_res->'order';
  end if;
  if voyage.ship_speed(v_ship2) is distinct from v_spd0 then
    raise exception '0074 self-assert FAIL: taking the sails off did not put her speed back';
  end if;
  if coalesce((select qty from public.player_items
                where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails'), 0) < 2 then
    raise exception '0074 self-assert FAIL: the sails came off and did not go back into the store';
  end if;

  -- (h) POSTURE.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0074 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0074 self-assert ok: A FITTING CHANGES THE SHIP. The six stats a hull did not have are on the class, `guns` is retired from being a stat into being the count of WEAPON slots, and slots are TYPED and grow with the tier - a barca takes a sail, a weapon and ground tackle, a nau takes seven across six kinds and berths 5 captains against her 3. Every one of the 12 fittings BUYS a stat and SPENDS another, checked in the world as well as in the generator so relaxing one does not relax the other, and the figurehead is the one exception because 1.4 says so. NOTHING MOVED: both re-cut authorities - public.ship_hold_capacity and voyage.ship_speed, which every fleet afloat depends on - return exactly what they returned before for every hull in the world, because nothing is fitted yet. And the POSITIVE CONTROL on that: mounting hold fittings really did buy hold and spend speed, the capacity authority saw it, taking them off put the hull back, and every speed-spending fitting in the catalogue mounted three times over still leaves her able to sail - because there is no way to unfit at sea. AND IT WORKS THROUGH THE ONE DOOR: a house typed FIT sails, the suit went ON and LEFT the store rather than being copied, her speed rose, a second suit was refused E_SLOTS_FULL because a barca has ONE rig slot, and UNFIT put both the speed and the sails back where they were; 0 client write grants.';
end $$;
