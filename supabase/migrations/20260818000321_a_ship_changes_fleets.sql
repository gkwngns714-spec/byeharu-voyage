-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0321 — A SHIP CHANGES FLEETS: the room a company has is counted, and a ship can move to another fleet in the same port. DARK
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner row 180, slice W4 of docs/WORLD_POWERS.md, which is F1 + F2 of docs/FLEETS_AND_SLOTS.md. It is the first way a player can have a second fleet. Nothing here attacks anyone: no-PvP stands.
--
-- WHAT THIS FILE ADDS, ALL DARK (`fleet_room_bite` false):
--   public.house_room        (company, FLEET or SHIP, steps bought). F3 is its writer; nothing writes it here, so it stays empty.
--   public.fleet_room_on     THE one reader of the switch.
--   public.fleet_room_caps   THE ladders of section 2.2, lit: fleets and ships per fleet. Read only through public.earned_caps, so every face and the trigger keep one reading.
--   public.move_ship         THE core of F2: same port, docked, not busy, flagship rule, empty fleet, new fleet through public.form_fleet. Dark: refuses E_NOT_IN_USE.
--   cmd.move_ship            The door. No player id. In the client registry.
--   world.ship_moves         What the fleet page may offer. Dark: {on: false}, so nothing is drawn.
--
-- THE HUNKS, each occurs once and reverses to its pre-image:
--   public.earned_caps (1): lit, the ladders. public.house_ship_max (2): lit, for a human, fleets x ships per fleet.
--   cmd.enqueue (1): a fleet with no ship takes no order, E_FLEET_EMPTY. public.tow_for (1): nor a tow. public.client_rpc_entry_points (1): the two new rows.
--   world.fleets (1): an empty fleet's speed is 0. voyage.fleet_speed_at raises E_NO_SHIPS, and that read would otherwise fail the player's whole list.
-- SUPERSEDES (re-cut): public.earned_caps (0107), public.house_ship_max (0133), cmd.enqueue (0092), public.tow_for (0152), public.client_rpc_entry_points (0319 cuts it too, on another line), world.fleets (0009). By hunks, not whole bodies.
--
-- AN EMPTY FLEET IS `UNABLE_TO_SAIL` AT THE PORT HER LAST SHIP LEFT. Design Q9 keeps the empty fleet; the design did not say what it is, and DOCKED would be a hole: every presence test in the chain
--   (donate, invest, forge, hire, the hall's `you.docked`, the quay) reads status = 'DOCKED', so a DOCKED empty fleet would be a free permanent presence where no ship lies, against the NO-HOME law.
--   UNABLE_TO_SAIL closes all of them with no hunk: cmd.advance runs nothing, lap_starts_due starts nothing, public.standing_route_state already answers 'blocked' (design: "Blocked").
--   Two doors would still take her, so they are hunked: cmd.enqueue and public.tow_for (a tow would lay her DOCKED at a yard). The next ship to join sets her DOCKED at that ship's port, from any port.
--
-- DARK IS BYTE-IDENTICAL. No existing knob moves: the design's `fleet_ship_max` 8 -> 7 is NOT written, because that would change every merchant's cap on deploy. The lit cap is a new knob, `fleet_ship_top`.
--   public.fleet_room_on costs one world_config read per cap check. public.earned_caps and public.house_ship_max answer as before; proof 29 compares them against the pre-images.
--   cmd.enqueue's test costs one primary-key-side read per order, dark or lit, and answers as before for every fleet that has a ship. No empty fleet exists on prod.
--
-- DECIDED BY DEFAULT (owner may reverse):
--   - One switch: `fleet_room_bite` lights the ladders and the door together. Two would allow a door with the wrong caps.
--   - A fleet's port time (fleets.ready_at) counts as busy, on both fleets. Without it a ship could skip her port time by moving to a rested fleet.
--   - A failed order standing in a queue is a record, not a busy fleet (0186).
--   - A flagship's heir: tier, then hold, then name (section 2.4 stops at hold; a tie must still have one answer).
--   - Levels and bought steps add up for fleets too, as the design says of ships: 2 + each level rung reached + bought, never above `fleet_hard_max`.
--   - Lit, a merchant keeps today's hull cap (public.house_ship_max): "merchants keep the flat rules". Her per-fleet cap meets `fleet_ship_top`; none is near it (largest on prod: 3).
--   - Captains go with the ship: seats are per ship (public.captain_seats). Section 2.4's "officers stay" predates 0157; fleets hold no officer now.
--   - What a fleet owes in wages stays on that fleet (public.fleet_wages), as a debt of the fleet's. An empty fleet keeps it until a ship joins and she next pays.
--
-- NOT HERE: F3 buying room (`house_room` stays empty, the price knobs stand unread), F4 the fleet's totals, the rest of F5, F6 lighting. No money moves in this file.
--
-- SELF-ASSERT: the catalog only: hunks once and reversing; ACL, volatility and config unmoved; no other function; no existing knob; no row. THIS FILE RUNS NO GAME STEP, in every environment
-- (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 29, scripts/db/proofs/29_fleet_room.sql, and tests/rpc.fleetroom.spec.ts for the seam.
-- Mutation controls: scripts/ops/harness/fleet-room/proof-0321.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): `fleet_room_bite` false closes the door and restores the caps; a second fleet already formed stays a fleet. To remove: swap this file's old and new, then drop what it created.
-- VERSION: 0321, after 0318 (#514), 0319 (#513) and 0320 (#515). Of those only 0319 touches a body hunked here, public.client_rpc_entry_points, on another line. Applied after all three by the harness (--first). Prod head 0318 when cut.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_n    int;
  v_fn_before  text;
  v_cfg_before text;
  v_meta_before text;
  c_new_fns constant text[] := array[
    'public.fleet_room_on()', 'public.fleet_room_caps(uuid)', 'public.move_ship(uuid,uuid,uuid,text)', 'cmd.move_ship(uuid,uuid,text)', 'world.ship_moves(uuid)'];
  c_hunked constant text[] := array[
    'public.earned_caps(uuid)', 'public.house_ship_max(uuid)', 'cmd.enqueue(uuid,jsonb,text,jsonb,uuid)', 'public.tow_for(uuid,uuid)', 'public.client_rpc_entry_points()', 'world.fleets()'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.house_room') is not null or to_regprocedure('public.move_ship(uuid,uuid,uuid,text)') is not null
     or exists (select 1 from public.world_config c where c.key = 'fleet_room_bite') then
    raise exception '0321 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.form_fleet(uuid,text,uuid)') is null or to_regprocedure('public.earned_caps(uuid)') is null then
    raise exception '0321 refuses: public.form_fleet or public.earned_caps is not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));

  -- ── 1. THE TABLE ──
  create table public.house_room (
    player_id  uuid        not null references public.players(id) on delete cascade,
    kind       text        not null check (kind in ('FLEET', 'SHIP')),
    steps      int         not null default 0 check (steps >= 0),
    updated_at timestamptz not null default now(),
    primary key (player_id, kind)
  );
  comment on table public.house_room is
    '0321 (docs/FLEETS_AND_SLOTS.md section 2.2): the steps of room a company has BOUGHT. Levels are derived. One reader: public.fleet_room_caps. Its writer is cmd.buy_room (F3), not built: empty until then.';
  alter table public.house_room enable row level security;
  revoke all on table public.house_room from public, anon, authenticated;

  -- ── 2. THE KNOBS (all new; no existing key is touched) ──
  insert into public.world_config (key, value, description) values
    ('fleet_room_bite', 'false'::jsonb, '0321: THE switch of counted room and of moving ships. False: every company reads today''s caps, cmd.move_ship refuses E_NOT_IN_USE, world.ship_moves answers {on: false}.'),
    ('fleet_hard_max', '5'::jsonb, '0321: fleets a company may open at most, lit.'),
    ('fleet_ship_top', '7'::jsonb, '0321: ships in one fleet at most, lit, for every company. The design''s 8 -> 7 of fleet_ship_max, on a new key so that deploying moves no cap.'),
    ('fleet_room_levels', '[3, 6]'::jsonb, '0321: each Trading level here opens one more fleet, lit.'),
    ('fleet_room_prices', '[60000, 1000000]'::jsonb, '0321: ducats for a fleet''s room, in order. Unread until F3 (cmd.buy_room).'),
    ('ship_room_prices', '[10000, 20000, 40000, 80000, 160000]'::jsonb, '0321: ducats for each step of ship room, in order. Unread until F3 (cmd.buy_room).');

  -- ── 3. THE READERS ──
  execute $f$
create function public.fleet_room_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0321: THE one reader of fleet_room_bite.
  select public.wc('fleet_room_bite') = 'true'::jsonb
$$
  $f$;

  execute $f$
create function public.fleet_room_caps(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0321 (docs/FLEETS_AND_SLOTS.md section 2.2): THE ladders, lit. Read only through public.earned_caps.
  -- FLEETS: the free two (fleet_max), one per Trading rung reached, plus bought; never above fleet_hard_max.
  -- SHIPS PER FLEET: fleet_ship_base, plus the higher of Seamanship and Command, plus bought; never above fleet_ship_top.
  -- A merchant is not playing this: the flat numbers, with the top.
  select case when coalesce((select p.is_npc from public.players p where p.id = p_player), true)
    then jsonb_build_object('fleet_max', public.wc_int('fleet_max'),
                            'fleet_ship_max', least(public.wc_int('fleet_ship_max'), public.wc_int('fleet_ship_top')),
                            'earned', false)
    else jsonb_build_object(
      'fleet_max', least(public.wc_int('fleet_hard_max'),
                         public.wc_int('fleet_max')
                         + (select count(*)::int from jsonb_array_elements_text(public.wc('fleet_room_levels')) r
                             where (public.player_progress(p_player)->'trading'->>'level')::int >= r.value::int)
                         + coalesce((select h.steps from public.house_room h where h.player_id = p_player and h.kind = 'FLEET'), 0)),
      'fleet_ship_max', least(public.wc_int('fleet_ship_top'),
                              public.wc_int('fleet_ship_base')
                              + greatest(public.skill_level(p_player, 'SEAMANSHIP'), public.skill_level(p_player, 'COMMAND'))
                              + coalesce((select h.steps from public.house_room h where h.player_id = p_player and h.kind = 'SHIP'), 0)),
      'earned', true) end
$$
  $f$;

  execute $f$
create function world.ship_moves(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0321: what the fleet page may offer for this fleet's ships: the fleets of yours docked in the same port with room, every empty fleet of yours, and a new fleet. The judge is public.move_ship;
-- this only keeps the page from offering what cannot be. Dark or not yours: {on: false}, before any cap is read.
declare
  f      public.fleets%rowtype;
  v_caps jsonb;
begin
  if not public.fleet_room_on() then
    return jsonb_build_object('on', false);
  end if;
  select * into f from public.fleets x where x.id = p_fleet and x.player_id = public.current_player_id();
  if f.id is null then
    return jsonb_build_object('on', false);
  end if;
  if f.status <> 'DOCKED' or (f.ready_at is not null and f.ready_at > now())
     or exists (select 1 from public.orders q where q.fleet_id = f.id and q.status in ('pending', 'active')) then
    return jsonb_build_object('on', true, 'targets', '[]'::jsonb, 'can_new', false);
  end if;
  v_caps := public.earned_caps(f.player_id);
  return jsonb_build_object('on', true,
    'targets', coalesce((
      select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'empty', o.n = 0) order by o.n = 0, o.name)
        from (select t.id, t.name, t.status, t.port_id, t.ready_at,
                     (select count(*) from public.ships s where s.fleet_id = t.id) as n
                from public.fleets t where t.player_id = f.player_id and t.id <> f.id) o
       where o.n = 0
          or (o.status = 'DOCKED' and o.port_id = f.port_id
              and o.n < (v_caps->>'fleet_ship_max')::int
              and (o.ready_at is null or o.ready_at <= now())
              and not exists (select 1 from public.orders q where q.fleet_id = o.id and q.status in ('pending', 'active')))), '[]'::jsonb),
    'can_new', (select count(*) from public.fleets t where t.player_id = f.player_id) < (v_caps->>'fleet_max')::int);
end $$
  $f$;

  -- ── 4. THE CORE AND THE DOOR ──
  execute $f$
create function public.move_ship(p_player uuid, p_ship uuid, p_to uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0321 (docs/FLEETS_AND_SLOTS.md section 2.4): THE one way a ship changes fleets. Into p_to, or, with p_name, into a new fleet at her port. Everything aboard goes with her, because
-- cargo, stores, crew and seats are the ship's. No money moves, no hull moves: this is paper at the quay. The caps are the trigger's (0021), which runs on `update of fleet_id`.
declare
  v_name  text := btrim(coalesce(p_name, ''));
  s       public.ships%rowtype;
  a       public.fleets%rowtype;
  b       public.fleets%rowtype;
  v_from  uuid;
  v_left  int;
  v_taken int;
  v_heir  uuid;
  v_new   boolean := false;
  v_port  text;
begin
  if not public.fleet_room_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'moving ships is not in use yet');
  end if;
  if (p_to is null) = (v_name = '') then
    perform cmd.refuse('E_PARSE', 'name one fleet, or a new one');
  end if;
  select x.fleet_id into v_from from public.ships x where x.id = p_ship and x.player_id = p_player;
  if v_from is null then
    perform cmd.refuse('E_NO_SUCH_SHIP', 'there is no such ship of yours');
  end if;
  if p_to = v_from then
    perform cmd.refuse('E_SAME_FLEET', 'she is already in that fleet');
  end if;
  if p_to is not null and not exists (select 1 from public.fleets x where x.id = p_to and x.player_id = p_player) then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'there is no such fleet of yours');
  end if;

  -- what has landed, lands first; then THE LOCK ORDER every verb takes, the fleets (by id, so two opposite moves cannot deadlock), then the ship
  perform voyage.settle(v_from);
  if p_to is not null then
    perform voyage.settle(p_to);
  end if;
  perform 1 from public.fleets x where x.id in (v_from, p_to) order by x.id for update;
  select * into s from public.ships x where x.id = p_ship for update;
  if s.fleet_id is distinct from v_from then
    perform cmd.refuse('E_STALE', 'she moved while you pressed');
  end if;
  select * into a from public.fleets x where x.id = v_from;

  if a.status <> 'DOCKED' then
    perform cmd.refuse('E_NOT_DOCKED', format('%s is %s and ships change fleets in port only', a.name, lower(replace(a.status, '_', ' '))));
  end if;
  if (a.ready_at is not null and a.ready_at > now())
     or exists (select 1 from public.orders o where o.fleet_id = a.id and o.status in ('pending', 'active')) then
    perform cmd.refuse('E_FLEET_BUSY', format('%s has orders or port time running', a.name));
  end if;

  if p_to is null then
    if length(v_name) < 3 or length(v_name) > 24 then
      perform cmd.refuse('E_PARSE', 'a fleet is named in 3 to 24 letters');
    end if;
    if exists (select 1 from public.fleets x where x.player_id = p_player and lower(x.name) = lower(v_name)) then
      perform cmd.refuse('E_NAME_TAKEN', format('you already keep a fleet called %s', v_name));
    end if;
    p_to := public.form_fleet(p_player, v_name, a.port_id);   -- the room is the trigger's: E_FLEET_MAX
    v_new := true;
    perform 1 from public.fleets x where x.id = p_to for update;
  end if;
  select * into b from public.fleets x where x.id = p_to;
  select count(*) into v_taken from public.ships x where x.fleet_id = b.id;

  if v_taken > 0 then
    if b.status <> 'DOCKED' then
      perform cmd.refuse('E_NOT_DOCKED', format('%s is %s and ships change fleets in port only', b.name, lower(replace(b.status, '_', ' '))));
    end if;
    if b.port_id is distinct from a.port_id then
      perform cmd.refuse('E_NOT_SAME_PORT', format('%s lies in another port', b.name));
    end if;
    if (b.ready_at is not null and b.ready_at > now())
       or exists (select 1 from public.orders o where o.fleet_id = b.id and o.status in ('pending', 'active')) then
      perform cmd.refuse('E_FLEET_BUSY', format('%s has orders or port time running', b.name));
    end if;
  elsif not v_new then
    -- AN EMPTY FLEET TAKES THE PORT OF THE SHIP THAT JOINS HER, from any port: she has nothing physical anywhere. Written before the ship, so the arrival trigger sees no cargo of hers.
    update public.fleets set status = 'DOCKED', port_id = a.port_id, lat = null, lon = null, ready_at = null where id = b.id;
  end if;

  -- THE FLAGSHIP (one a fleet, by index, so she stands down before anything else). Her heir: tier, hold, name. A fleet with no flagship takes her as one, as a fleet that has one does not.
  update public.ships set is_flagship = false where id = s.id and is_flagship;
  select count(*) into v_left from public.ships x where x.fleet_id = a.id and x.id <> s.id;
  if s.is_flagship and v_left > 0 then
    select x.id into v_heir
      from public.ships x join public.ship_classes c on c.id = x.class_id
     where x.fleet_id = a.id and x.id <> s.id
     order by c.tier desc, public.ship_hold_capacity(x.id) desc, x.name, x.id limit 1;
    update public.ships set is_flagship = true where id = v_heir;
  end if;
  update public.ships
     set fleet_id = b.id,
         is_flagship = not exists (select 1 from public.ships y where y.fleet_id = b.id and y.is_flagship)
   where id = s.id;

  -- HER LAST SHIP GONE, A FLEET IS `UNABLE_TO_SAIL` where she lay: no presence, no orders, a route on her reads Blocked. The header says why.
  update public.fleets
     set status = case when id = a.id and v_left = 0 then 'UNABLE_TO_SAIL' else status end,
         version = version + 1
   where id in (a.id, b.id);

  select p.code into v_port from public.ports p where p.id = a.port_id;
  perform public.emit_event(p_player, 'SHIP_MOVED', jsonb_build_object(
    'ship', s.name, 'from', a.name, 'to', b.name, 'port', v_port, 'new_fleet', v_new, 'empty', v_left = 0));
  return jsonb_build_object('ok', true, 'ship', s.name, 'from', a.name, 'to', b.name, 'fleet_id', b.id, 'port', v_port, 'new_fleet', v_new, 'empty', v_left = 0);
end $$
  $f$;

  execute $f$
create function cmd.move_ship(p_ship uuid, p_to uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0321: the caller's company moves a ship. The core is public.move_ship.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.move_ship(v_player, p_ship, p_to, p_name);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$
  $f$;

  revoke all on function public.fleet_room_on() from public, anon, authenticated;
  revoke all on function public.fleet_room_caps(uuid) from public, anon, authenticated;
  revoke all on function public.move_ship(uuid, uuid, uuid, text) from public, anon, authenticated;
  revoke all on function cmd.move_ship(uuid, uuid, text) from public, anon;
  grant execute on function cmd.move_ship(uuid, uuid, text) to authenticated;
  revoke all on function world.ship_moves(uuid) from public, anon;
  grant execute on function world.ship_moves(uuid) to authenticated;

  -- ── 5. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0321 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0321 values
  ('public.earned_caps(uuid)', 1,
$h$  select case when exists (select 1 from public.players p where p.id = p_player and p.is_npc)
$h$,
$h$  select case when public.fleet_room_on() then public.fleet_room_caps(p_player)   -- 0321: lit, the ladders; dark, what follows
    when exists (select 1 from public.players p where p.id = p_player and p.is_npc)
$h$),
  ('public.house_ship_max(uuid)', 1,
$h$  select public.wc_int('ship_max')
$h$,
$h$  select case when public.fleet_room_on() and not coalesce((select p.is_npc from public.players p where p.id = p_player), true)   -- 0321: lit, a human company's hull cap is its room
    then (select (c->>'fleet_max')::int * (c->>'fleet_ship_max')::int from public.earned_caps(p_player) c)
    else public.wc_int('ship_max')
$h$),
  ('public.house_ship_max(uuid)', 2,
$h$                else 0 end
$h$,
$h$                else 0 end end
$h$),
  ('cmd.enqueue(uuid,jsonb,text,jsonb,uuid)', 1,
$h$  select count(*) into v_depth from public.orders
   where fleet_id = v_fleet and status in ('pending', 'active');
$h$,
$h$  -- 0321: a fleet with no ship takes no order; orders would wait on her and block the next ship that joins
  if not exists (select 1 from public.ships s where s.fleet_id = v_fleet) then
    return jsonb_build_object('ok', false, 'error_code', 'E_FLEET_EMPTY',
      'error_message', 'That fleet has no ships.');
  end if;

  select count(*) into v_depth from public.orders
   where fleet_id = v_fleet and status in ('pending', 'active');
$h$),
  ('public.tow_for(uuid,uuid)', 1,
$h$  if f.port_id is null then
$h$,
$h$  if not exists (select 1 from public.ships s where s.fleet_id = f.id) then   -- 0321: an empty fleet is not a wreck; a tow would lay her DOCKED where no ship lies
    perform cmd.refuse('E_FLEET_EMPTY', format('%s has no ships', f.name));
  end if;
  if f.port_id is null then
$h$),
  ('world.fleets()', 1,
$h$    'speed_kn', voyage.fleet_speed(f.id),
$h$,
$h$    'speed_kn', case when exists (select 1 from public.ships s where s.fleet_id = f.id) then voyage.fleet_speed(f.id) else 0 end,   -- 0321: an empty fleet has no speed to ask for
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'tow',                   'uuid, int'),
$h$,
$h$      ('cmd',         'tow',                   'uuid, int'),
      -- 0321: a ship changes fleets in port, and what the fleet page may offer. Dark until fleet_room_bite.
      ('cmd',         'move_ship',             'uuid, uuid, text'),
      ('world',       'ship_moves',            'uuid'),
$h$);

  for v_h in select h.fn from hunks_0321 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    declare
      x record;
      v_pre text := v_def;
    begin
      for x in select * from hunks_0321 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0321 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0321 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0321 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0321 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog only ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x))
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> v_fn_before then
    raise exception '0321 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c
       where c.key not in ('fleet_room_bite', 'fleet_hard_max', 'fleet_ship_top', 'fleet_room_levels', 'fleet_room_prices', 'ship_room_prices')) <> v_cfg_before then
    raise exception '0321 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0321 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if public.fleet_room_on() then
    raise exception '0321 self-assert FAIL: the room is not dark';
  end if;
  if exists (select 1 from public.house_room) then
    raise exception '0321 self-assert FAIL: a row stands in public.house_room';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where has_function_privilege('anon', f::regprocedure, 'execute')
                 or (has_function_privilege('authenticated', f::regprocedure, 'execute') <> (f in ('cmd.move_ship(uuid,uuid,text)', 'world.ship_moves(uuid)')))) then
    raise exception '0321 self-assert FAIL: the grants are not the contract: only the door and the read, only to authenticated';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name in ('move_ship', 'ship_moves') and e.fn is not null) <> 2 then
    raise exception '0321 self-assert FAIL: the door or the read is not in the client registry';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0321 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0321 self-assert ok: A SHIP CHANGES FLEETS, dark. % hunks once each and reversing; no other function, no existing knob, no row; no game step ran (proof 29 runs them in CI). % ms.',
    (select count(*) from hunks_0321), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0321;
end
$m$;
