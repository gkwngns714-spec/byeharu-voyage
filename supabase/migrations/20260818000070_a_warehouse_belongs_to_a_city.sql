-- ===============================================================================================
-- 0070 - A WAREHOUSE BELONGS TO A CITY
-- ===============================================================================================
--
-- The owner, 2026-09-01:
--
--     "make a storage, where i can buy trade goods and then store it. The storage is not shared
--      between cities, an independeant building."
--
-- and, legislating the same thing in their other game, where it is already law:
--
--     items have VOLUME and a LOCATION; storage is PER-PORT; reachable only while DOCKED there.
--
-- -- WHAT A WAREHOUSE IS ------------------------------------------------------------------------
-- A row per (player, port, good). Not a global stash with a port column bolted on: the LOCATION is
-- half of what a warehouse IS. Goods put ashore at Bilbao are at Bilbao, and a fleet lying at
-- Lisboa cannot touch them - which is the whole reason the building is interesting. It turns "buy
-- cheap here, sell dear there" into "buy cheap here, LEAVE it here, and come back with a bigger
-- hull", and it is the first thing in this game that makes a city somewhere you keep something.
--
-- -- WHAT IT COSTS TO KEEP: NOTHING --------------------------------------------------------------
-- An earlier draft of the design put 0.5 d./tun/game-day rent in front of the owner as though it
-- were theirs. It was not:
--
--     "wtf is warehoure's rent? i didn't say anything about this. remove"
--
-- Removed, and it stays removed. The limit on a warehouse is SPACE, not a tax on time - and a
-- per-day charge would mean a player who stops playing comes back poorer, which no rule in this
-- game does.
--
-- -- ONE VOLUME MODEL, NOT TWO -------------------------------------------------------------------
-- A warehouse holds units, and units cost volume folded by goods.bulk - exactly as a hold does. The
-- cap is the building's tier, which is what a tier is FOR (0067): a great city holds more than a
-- fishing village because it is a great city, not because a list says so.
--
-- -- ONE CARGO MOVER, STILL ----------------------------------------------------------------------
-- STORE composes public.fleet_unload and TAKE composes public.fleet_load. Nothing here writes
-- ships.cargo. A second way of moving a good in or out of a hold is the defect this chain keeps
-- removing, and a warehouse is exactly the feature that would tempt one.
--
-- -- IT MAY HOLD WHAT THE CITY DOES NOT TRADE ----------------------------------------------------
-- 0061 gates BUY and deliberately never gates SELL, so a hold is never stranded. A warehouse
-- inherits that: you may land anything you are carrying. A city that refuses to BUY your olive oil
-- will still let you leave it in a shed.
--
-- -- THE DISK QUESTION, ANSWERED -----------------------------------------------------------------
-- A per-(player, port, good) table is the shape that once filled production's disk. It is not the
-- same shape: price_history was DENSE - every port x every good x every slot, 7.3M rows by
-- construction. This is SPARSE: one row per thing actually stored. public.trade_daily and
-- public.haggle_daily are the same shape and are tiny.
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
      raise exception '0070 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

create temporary table defs_before_0070 as
  select 'cmd.verb_schema'::text as fn, pg_get_functiondef('cmd.verb_schema()'::regprocedure) as def;

-- -- 1. EVERY CITY KEEPS A SHED --------------------------------------------------------------
-- A warehouse is not a facility a city may lack. Somewhere to put a crate is what a harbour IS,
-- and a world where two thirds of the map cannot hold anything would make the feature a scavenger
-- hunt rather than a decision. What VARIES is how much - which is the tier, and the tier is the
-- city's size, because a great port has more shed than a fishing village.
insert into public.port_buildings (port_id, kind, tier)
select p.id, 'warehouse', greatest(1, least(5, p.size_tier))
  from public.ports p where p.kind = 'HARBOUR'
on conflict (port_id, kind) do update set tier = excluded.tier;

insert into public.world_config (key, value, description) values
  ('warehouse_tuns_per_tier', to_jsonb(150::numeric),
   'How much a warehouse holds, per tier of the building - so a tier 1 shed takes 150 tuns and a '
   'tier 5 one 750. The starter Barca carries 60, so even the smallest shed is worth more than two '
   'holds and the largest is worth twelve: enough that leaving a cargo behind is a real decision, '
   'and short of enough to hoard a city out of a good.')
on conflict (key) do update set value = excluded.value, description = excluded.description;

-- -- 2. WHAT IS PUT ASHORE, AND WHERE -------------------------------------------------------------
create table if not exists public.player_storage (
  player_id uuid    not null references public.players(id) on delete cascade,
  port_id   uuid    not null references public.ports(id),
  good_id   uuid    not null references public.goods(id),
  qty       numeric(12,2) not null check (qty >= 0),
  primary key (player_id, port_id, good_id)
);

comment on table public.player_storage is
  'What a house has left ashore, per (player, port, good). The PORT is half of what this is: goods '
  'stored at Bilbao are at Bilbao and are unreachable from anywhere else. Sparse - one row per '
  'thing actually stored - unlike the dense price_history that once filled the disk.';

alter table public.player_storage enable row level security;
drop policy if exists player_storage_read on public.player_storage;
create policy player_storage_read on public.player_storage for select to authenticated
  using (player_id = (select p.id from public.players p where p.auth_uid = auth.uid()));

-- -- 3. HOW MUCH ROOM IS LEFT ---------------------------------------------------------------------
-- ONE definition of "how full is this shed", because STORE, the read and the self-assert all need
-- it and three implementations of a volume sum is three chances to disagree.
create or replace function public.storage_used(p_player uuid, p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $su$
  select coalesce(sum(ps.qty * g.bulk), 0)
    from public.player_storage ps join public.goods g on g.id = ps.good_id
   where ps.player_id = p_player and ps.port_id = p_port
$su$;

create or replace function public.storage_cap(p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $sc$
  select coalesce((select b.tier from public.port_buildings b
                    where b.port_id = p_port and b.kind = 'warehouse'), 0)
         * public.wc_num('warehouse_tuns_per_tier')
$sc$;

revoke all on function public.storage_used(uuid, uuid) from public, anon, authenticated;
revoke all on function public.storage_cap(uuid) from public, anon, authenticated;

-- -- 4. PUTTING SOMETHING ASHORE, AND TAKING IT BACK ------------------------------------------------
create or replace function cmd.do_store(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $ds$
declare
  f      public.fleets%rowtype;
  g      public.goods%rowtype;
  v_have numeric;
  v_qty  numeric;
  v_room numeric;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and a cargo is landed alongside', f.name, f.status using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.port_buildings b where b.port_id = f.port_id and b.kind = 'warehouse') then
    raise exception 'E_NO_WAREHOUSE: this city keeps no warehouse' using errcode = 'P0001';
  end if;

  select * into g from public.goods where id = (p_args->>'good')::uuid;
  if g.id is null then
    raise exception 'E_NO_SUCH_GOOD: nothing is called that' using errcode = 'P0001';
  end if;

  v_have := public.fleet_cargo_qty(p_fleet, g.code);
  -- ALL means all of it, and the same words mean the same thing here as on a SELL (0008's grammar).
  v_qty  := case when coalesce(p_args->>'qty_mode', '') = 'ALL' then v_have
                 else least(coalesce((p_args->>'qty')::numeric, 0), v_have) end;
  if v_have <= 0 or v_qty <= 0 then
    raise exception 'E_NO_CARGO: % carries no %', f.name, g.name using errcode = 'P0001';
  end if;

  v_room := public.storage_cap(f.port_id) - public.storage_used(f.player_id, f.port_id);
  if v_qty * g.bulk > v_room then
    raise exception 'E_SHED_FULL: the shed here holds % more tun(s) and % of % wants %',
      trim(to_char(greatest(v_room, 0), 'FM999999.9')), trim(to_char(v_qty, 'FM999999')),
      g.name, trim(to_char(v_qty * g.bulk, 'FM999999.9')) using errcode = 'P0001';
  end if;

  -- THE ONE CARGO MOVER. Nothing here writes ships.cargo.
  perform public.fleet_unload(p_fleet, g.code, v_qty);
  insert into public.player_storage (player_id, port_id, good_id, qty)
  values (f.player_id, f.port_id, g.id, v_qty)
  on conflict (player_id, port_id, good_id) do update set qty = public.player_storage.qty + excluded.qty;

  perform public.emit_event(f.player_id, 'STORED', jsonb_build_object(
    'fleet', f.name, 'good', g.name, 'qty', v_qty));

  return jsonb_build_object('good', g.code, 'qty', v_qty,
    'stored_here', (select ps.qty from public.player_storage ps
                     where ps.player_id = f.player_id and ps.port_id = f.port_id and ps.good_id = g.id));
end $ds$;

create or replace function cmd.do_take(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $dt$
declare
  f      public.fleets%rowtype;
  g      public.goods%rowtype;
  v_have numeric;
  v_qty  numeric;
  v_took numeric;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and a cargo is taken up alongside', f.name, f.status using errcode = 'P0001';
  end if;

  select * into g from public.goods where id = (p_args->>'good')::uuid;
  if g.id is null then
    raise exception 'E_NO_SUCH_GOOD: nothing is called that' using errcode = 'P0001';
  end if;

  select ps.qty into v_have from public.player_storage ps
   where ps.player_id = f.player_id and ps.port_id = f.port_id and ps.good_id = g.id;
  v_qty := case when coalesce(p_args->>'qty_mode', '') = 'ALL' then coalesce(v_have, 0)
                else least(coalesce((p_args->>'qty')::numeric, 0), coalesce(v_have, 0)) end;
  if coalesce(v_have, 0) <= 0 or v_qty <= 0 then
    -- NAMED FOR WHERE YOU ARE. "You have none" would be a lie: they may have a shed full of it
    -- three ports away, and the whole point of the building is that it matters which city.
    raise exception 'E_NONE_STORED: you keep no % in this city', g.name using errcode = 'P0001';
  end if;

  -- fleet_load returns what actually FITTED, which is the honest answer when a hold is nearly
  -- full: she takes what she can and the rest stays ashore, exactly where it was.
  v_took := public.fleet_load(p_fleet, g.code, v_qty);
  if v_took <= 0 then
    raise exception 'E_HOLD_FULL: % has no room for %', f.name, g.name using errcode = 'P0001';
  end if;
  update public.player_storage set qty = qty - v_took
   where player_id = f.player_id and port_id = f.port_id and good_id = g.id;
  delete from public.player_storage
   where player_id = f.player_id and port_id = f.port_id and good_id = g.id and qty <= 0;

  perform public.emit_event(f.player_id, 'TAKEN', jsonb_build_object(
    'fleet', f.name, 'good', g.name, 'qty', v_took));

  return jsonb_build_object('good', g.code, 'qty', v_took,
    'stored_here', coalesce((select ps.qty from public.player_storage ps
                              where ps.player_id = f.player_id and ps.port_id = f.port_id
                                and ps.good_id = g.id), 0));
end $dt$;

revoke all on function cmd.do_store(uuid, jsonb) from public, anon, authenticated;
revoke all on function cmd.do_take(uuid, jsonb) from public, anon, authenticated;

-- -- 5. TWO MORE WORDS ------------------------------------------------------------------------------
-- STORE and TAKE parse EXACTLY as BUY and SELL do - a good, then a quantity or ALL - because they
-- are the same sentence about the same thing and a player should not have to learn a second shape
-- to say it. That is why the branch is folded into the existing one rather than written beside it.
select pg_temp.recut('cmd.parse(uuid, uuid, text)'::regprocedure, false,
  $g0$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','MAKE','CANCEL','CLEAR') then$g0$,
  $g1$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','MAKE','STORE','TAKE','CANCEL','CLEAR') then$g1$,
  $g2$  elsif v_verb in ('BUY','SELL') then$g2$,
  $g3$  elsif v_verb in ('BUY','SELL','STORE','TAKE') then$g3$);

select pg_temp.recut('cmd.verb_schema()'::regprocedure, false,
  $v0$    {"verb":"REPAIR","args":[$v0$,
  $v1$    {"verb":"STORE","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"good","type":"good","required":true},
       {"name":"qty","type":"quantity","required":true}],
     "help":"Land a cargo in this city and leave it there.",
     "note":"A warehouse belongs to the city it stands in. What you leave at one port cannot be reached from another, and it costs nothing to keep."},
    {"verb":"TAKE","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"good","type":"good","required":true},
       {"name":"qty","type":"quantity","required":true}],
     "help":"Take a cargo back out of this city and put it aboard.",
     "note":"Only what you left in THIS city, and only as much as her hold has room for."},
    {"verb":"REPAIR","args":[$v1$);

select pg_temp.recut('cmd.execute_order(uuid)'::regprocedure, false,
  $e0$               when 'MAKE'      then cmd.do_make(o.fleet_id, o.args)$e0$,
  $e1$               when 'MAKE'      then cmd.do_make(o.fleet_id, o.args)
               when 'STORE'     then cmd.do_store(o.fleet_id, o.args)
               when 'TAKE'      then cmd.do_take(o.fleet_id, o.args)$e1$);

select pg_temp.recut('cmd.preview(uuid, text, jsonb)'::regprocedure, false,
  $p0$               when 'MAKE'      then cmd.do_make((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p0$,
  $p1$               when 'MAKE'      then cmd.do_make((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'STORE'     then cmd.do_store((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'TAKE'      then cmd.do_take((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p1$);

-- -- 6. WHAT THE WAREHOUSE SERVES --------------------------------------------------------------------
create or replace function world.warehouse(p_port uuid, p_fleet uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $wh$
declare
  v_player uuid := (select id from public.players where auth_uid = auth.uid());
  v_tier   int;
begin
  select b.tier into v_tier from public.port_buildings b
   where b.port_id = p_port and b.kind = 'warehouse';

  return jsonb_build_object(
    'port_id', p_port,
    'tier',    v_tier,
    'cap',     public.storage_cap(p_port),
    'used',    public.storage_used(v_player, p_port),
    -- WHAT IS ASHORE HERE, and what she is carrying that could join it. Both in one read, because
    -- the screen's whole job is to move things between the two and asking twice would let them
    -- disagree by a trade in between.
    'stored', (select coalesce(jsonb_agg(jsonb_build_object(
        'good', g.code, 'name', g.name, 'qty', ps.qty, 'bulk', g.bulk,
        'tuns', round(ps.qty * g.bulk, 2)) order by g.name), '[]'::jsonb)
      from public.player_storage ps join public.goods g on g.id = ps.good_id
     where ps.player_id = v_player and ps.port_id = p_port and ps.qty > 0),
    'aboard', case when p_fleet is null then '[]'::jsonb else (
      select coalesce(jsonb_agg(jsonb_build_object(
          'good', g.code, 'name', g.name, 'qty', public.fleet_cargo_qty(p_fleet, g.code),
          'bulk', g.bulk) order by g.name), '[]'::jsonb)
        from public.goods g
       where public.fleet_cargo_qty(p_fleet, g.code) > 0) end);
end $wh$;

grant execute on function world.warehouse(uuid, uuid) to authenticated;

-- -- SELF-ASSERT ----------------------------------------------------------------------------------
do $$
declare
  v_player uuid;
  v_fleet  uuid;
  v_port   uuid;
  v_good   uuid;
  v_code   text;
  v_res    jsonb;
  v_qty    numeric;
  v_cap    numeric;
  v_sheds  int;
  v_grants int;
  v_before text;
  c_uid constant uuid := '00000000-0070-4000-8000-000000000001';
begin
  -- (a) EVERY HARBOUR KEEPS ONE, and the cap follows the city rather than a list.
  select count(*) into v_sheds from public.port_buildings where kind = 'warehouse';
  if v_sheds <> (select count(*) from public.ports where kind = 'HARBOUR') then
    raise exception '0070 self-assert FAIL: % shed(s) for % harbour(s)', v_sheds,
      (select count(*) from public.ports where kind = 'HARBOUR');
  end if;
  if (select count(distinct tier) from public.port_buildings where kind = 'warehouse') < 2 then
    raise exception '0070 self-assert FAIL: every warehouse is the same size, so the tier means nothing';
  end if;

  -- (b) IT WORKS, END TO END, THROUGH THE ONE DOOR. Found a house, buy nothing - put what she
  --     already carries ashore, and take it back.
  v_player := public.new_house(c_uid, 'Casa Almacen', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  select port_id into v_port from public.fleets where id = v_fleet;
  perform cmd.assume_identity(c_uid);

  -- Something to land. Chosen from what this quay actually trades, never named: 0065 put every
  -- good in one to three cities, and a test that names one asserts a WORLD.
  select g.id, g.code into v_good, v_code
    from public.goods g join public.port_goods pg on pg.good_id = g.id and pg.port_id = v_port
   where public.port_offers(v_port, g.id) order by g.code limit 1;
  perform public.fleet_load(v_fleet, v_code, 10);

  v_res := cmd.issue(v_fleet, format('STORE %s 10', v_code), null, null);
  if not (v_res->>'ok')::boolean then
    raise exception '0070 self-assert FAIL: STORE was refused: %', v_res->'refusal';
  end if;
  select qty into v_qty from public.player_storage
   where player_id = v_player and port_id = v_port and good_id = v_good;
  if coalesce(v_qty, 0) <> 10 then
    raise exception '0070 self-assert FAIL: % in the shed after storing 10', coalesce(v_qty, 0);
  end if;
  if public.fleet_cargo_qty(v_fleet, v_code) <> 0 then
    raise exception '0070 self-assert FAIL: the cargo is ashore AND aboard - it was copied, not moved';
  end if;

  v_res := cmd.issue(v_fleet, format('TAKE %s ALL', v_code), null, null);
  if not (v_res->>'ok')::boolean then
    raise exception '0070 self-assert FAIL: TAKE was refused: %', v_res->'refusal';
  end if;
  if public.fleet_cargo_qty(v_fleet, v_code) <> 10 then
    raise exception '0070 self-assert FAIL: she took back % of 10', public.fleet_cargo_qty(v_fleet, v_code);
  end if;
  if coalesce((select qty from public.player_storage
                where player_id = v_player and port_id = v_port and good_id = v_good), 0) <> 0 then
    raise exception '0070 self-assert FAIL: the shed still holds what she took back';
  end if;

  -- (c) A SHED IN ANOTHER CITY IS ANOTHER CITY'S. This is the law the whole file exists for, so it
  --     is proven rather than described: store here, sail nowhere, just move her, and ask again.
  v_res := cmd.issue(v_fleet, format('STORE %s ALL', v_code), null, null);
  if not (v_res->>'ok')::boolean then
    raise exception '0070 self-assert FAIL: the second STORE was refused: %', v_res->'refusal';
  end if;
  perform cmd.clear(v_fleet, true);
  update public.fleets set port_id = (select p.id from public.ports p
                                       where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1)
   where id = v_fleet;
  v_res := cmd.issue(v_fleet, format('TAKE %s ALL', v_code), null, null);
  if (v_res->>'ok')::boolean then
    raise exception '0070 self-assert FAIL: she took a cargo out of a shed in a DIFFERENT city';
  end if;
  if v_res->'refusal'->>'code' <> 'E_NONE_STORED' then
    raise exception '0070 self-assert FAIL: a far-off shed refused with % rather than E_NONE_STORED',
      v_res->'refusal'->>'code';
  end if;

  -- (d) THE CAP BINDS, and it is the building's. Filled to the brim by hand, one more tun refuses.
  v_cap := public.storage_cap(v_port);
  if v_cap <= 0 then
    raise exception '0070 self-assert FAIL: the first shed holds nothing';
  end if;
  update public.player_storage set qty = floor(v_cap / (select bulk from public.goods where id = v_good))
   where player_id = v_player and port_id = v_port and good_id = v_good;
  if public.storage_used(v_player, v_port) > v_cap then
    raise exception '0070 self-assert FAIL: the shed is over its own cap before anything was refused';
  end if;
  update public.fleets set port_id = v_port where id = v_fleet;
  perform public.fleet_load(v_fleet, v_code, 20);
  perform cmd.clear(v_fleet, true);
  v_res := cmd.issue(v_fleet, format('STORE %s 20', v_code), null, null);
  if (v_res->>'ok')::boolean then
    raise exception '0070 self-assert FAIL: a full shed took 20 more tuns';
  end if;
  if v_res->'refusal'->>'code' <> 'E_SHED_FULL' then
    raise exception '0070 self-assert FAIL: a full shed refused with % rather than E_SHED_FULL',
      v_res->'refusal'->>'code';
  end if;

  -- (e) THE GRAMMAR GREW BY EXACTLY TWO WORDS.
  select def into v_before from defs_before_0070 where fn = 'cmd.verb_schema';
  if position('STORE' in v_before) <> 0 then
    raise exception '0070 self-assert FAIL: the pre-image already knew STORE';
  end if;
  if jsonb_array_length(cmd.verb_schema()) <> 11 then
    raise exception '0070 self-assert FAIL: the grammar serves % verbs, expected 11',
      jsonb_array_length(cmd.verb_schema());
  end if;

  -- (f) POSTURE.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0070 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0070 self-assert ok: A WAREHOUSE BELONGS TO A CITY. Every one of % harbours keeps a shed and their tiers differ, so how much a city holds is a fact about the city. It works end to end through the one door: a house landed ten tuns with STORE - and her hold was EMPTY afterwards, so the cargo was MOVED and not copied - then took it all back with TAKE and the shed was empty. THE LAW IS PROVEN, not described: with the goods still ashore at the first city she was moved to another and TAKE refused E_NONE_STORED, because a warehouse cannot be reached from anywhere but the city it stands in. The cap binds and it is the BUILDING''S: filled to the brim, twenty more tuns refused E_SHED_FULL. Nothing writes ships.cargo here - STORE composes fleet_unload and TAKE composes fleet_load, and TAKE moves only what actually fitted. The grammar grew by exactly two words, from 9 verbs to 11; 0 client write grants. A warehouse costs nothing to keep.',
    v_sheds;
end $$;
