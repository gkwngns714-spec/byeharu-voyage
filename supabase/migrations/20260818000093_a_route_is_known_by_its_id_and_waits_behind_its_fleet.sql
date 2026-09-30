-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0093 — A ROUTE IS KNOWN BY ITS ID, AND WAITS BEHIND ITS FLEET
--        The adversarial review of 0092 (PR #89, 2026-09-30), applied before 0092 was ever
--        deployed. 0092 is NOT edited (the no-edit law, docs/NO_SPAGHETTI.md §3): everything here
--        supersedes it forward, and the two ship together or not at all.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT THE REVIEW FOUND, AND WHAT THIS FILE DOES ABOUT EACH ──────────────────────────────────
--   MUST 1  A REFUSED START LEFT A HIDDEN ROUTE THAT BLOCKED ITS OWN NAME FOR EVER. The editor saves,
--           then assigns; a refused assign (E_NO_KEEP) left a route with no fleet, and the next
--           press of Start (same ports, same generated name) was E_NAME_TAKEN with no way out.
--           -> The name index is DROPPED: a name is a label, a route is found by its id (every
--              verb already takes the id). The E_NAME_TAKEN arm of cmd.standing_route_save goes
--              with it. The client lists routes without a fleet (RouteFold), so none is hidden.
--   SHOULD 2 OPPOSITE LOCK ORDER. voyage.settle, cmd.issue, the tick and the read lock the FLEET
--           and then reach the ROUTE (cmd.run_standing_route); assign and pause locked the route
--           first — a 40P01 waiting for the minute tick. -> assign, pause and delete now lock the
--           fleet(s) first, in id order, then the route; the read settles its fleets in id order.
--   SHOULD 3 PAUSE SENTENCES PRINTED PORT CODES AND A BARE NUMBER ("less than 5000000 kept back",
--           "not at LIS or FNC", "\"SELL x ALL\" could not be queued (E_QUEUE_FULL)"). -> port
--           NAMES, no figure in prose (the client words each reason; docs/WORDS.md law 2), and the
--           E_ROUTE_BROKEN sentences say what happened in plain words.
--   SHOULD 4 A FLEET THAT CANNOT MOVE READ "On route". -> the read serves `blocked` for any status
--           but DOCKED / SAILING / REPAIRING (UNABLE_TO_SAIL, ADRIFT, ANCHORED).
--   SHOULD 5 THE ARRIVAL ORDER STOOD ASIDE EVEN WHEN THE ROUTE WOULD NOT REFILL (the player had queued
--           an order of their own, or the fleet made port off the route) — it sailed on unsupplied,
--           breaking 0034's "a queued onward SAIL departs provisioned". -> it stands aside only
--           when the route is about to refill HERE: nothing pending or failed in the queue, and the
--           fleet at the stop the route is bound for.
--   NIT 7    THE SKIP RULE WORKED WITH THE SWITCH OFF. -> gated on standing_routes_on(): dark is the
--           ordinary halt.
--   NIT 10   ASSIGN CLEARED lap_id WITHOUT CLOSING THE LAP (a lap left open for good). -> the open
--           lap is closed (cmd.standing_route_close_lap, the one closer) when a route changes
--           fleet or is taken off one.
--   and one the review did not name, found while re-cutting assign: a REFUSED assign to another
--           fleet had already released the old fleet's pending route orders (the release ran
--           before the checks). -> every check runs first; a refused assign changes nothing.
--   Rejected / deferred, with reasons, in docs/TRADE_ROUTES.md §13.1: NIT 8 (CLEAR does not run
--   the queue — the app's clear re-reads, and cmd.clear is 0007's, untouched here).
--
-- ── WHAT THIS FILE SUPERSEDES ──────────────────────────────────────────────────────────────────
--   SLICED from pg_get_functiondef (every hunk asserted to occur exactly once, LF-normalised,
--   parity proven by REVERSE substitution back to the pre-image, ACLs unmoved):
--     cmd.advance(uuid, timestamptz)                 0092's skip rule: one hunk (the switch gate).
--     cmd.run_standing_provision(uuid)               0092's route return: one hunk (refill-here test).
--     cmd.run_standing_route(uuid, timestamptz)      eight hunks: port names in, codes and figures out.
--     cmd.standing_route_save(uuid,text,jsonb,bigint,int)  one hunk: the E_NAME_TAKEN arm goes.
--     world.standing_routes()                        two hunks: settle in fleet-id order; `blocked`.
--   REPLACED WHOLE (small bodies whose ORDER of statements is the fix; behaviour proven below):
--     cmd.standing_route_assign(uuid, uuid)          fleet-first locks; checks before any change;
--                                                    the open lap is closed, never orphaned.
--     cmd.standing_route_pause(uuid, boolean)        fleet-first locks.
--     cmd.standing_route_delete(uuid)                fleet-first locks.
--   DROPPED: index standing_routes_player_name_unique (0092:164).
--   With the switch OFF (it still is — this file does not touch it) every changed path is inert
--   exactly as 0092's was: the verbs refuse E_UNAVAILABLE before reaching any change here.
--
-- ── SECOND CALLERS ─────────────────────────────────────────────────────────────────────────────
--   `blocked` is read by src/domain/route (RouteFold's state word, FLEETS' caption). The pause
--   REASON (not the sentence) is what the client words, in src/domain/route; the sentence is kept
--   for `error`, where it is the refusal's own.
--
-- Depends on: 0007 (advance), 0034 (run_standing_provision), 0092 (everything route).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. THE HUNKS, written ONCE, read by the cut and by the parity proof ────────────────────────
create temporary table hunks_0093 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n));

insert into hunks_0093 values
-- cmd.advance — NIT 7: the skip rule is dark when the switch is.
('cmd.advance(uuid, timestamptz)', 1,
$h$      exit when o.route_lap_id is null or o.verb = 'SAIL';$h$,
$h$      exit when o.route_lap_id is null or o.verb = 'SAIL' or not public.standing_routes_on();   -- 0093: dark = the ordinary halt$h$),

-- cmd.run_standing_provision — SHOULD 5: stand aside only when the route refills HERE.
('cmd.run_standing_provision(uuid)', 1,
$h$  if public.standing_routes_on()
     and exists (select 1 from public.standing_routes sr
                  where sr.fleet_id = p_fleet and sr.paused_reason is null) then
    return null;
  end if;$h$,
$h$  -- 0093: ...and ONLY when that route is about to refill right here: nothing pending or failed in
  -- the queue, and the fleet at the stop the route is bound for. A queued order of the player's
  -- own, or a port off the route, means no refill — so 0034's promise holds and it leaves supplied.
  if public.standing_routes_on()
     and exists (select 1 from public.standing_routes sr
                   join public.standing_route_stops s on s.route_id = sr.id
                  where sr.fleet_id = p_fleet and sr.paused_reason is null
                    and s.port_id = f.port_id
                    and s.ord = sr.stop_cursor % greatest(1, (select count(*) from public.standing_route_stops s2
                                                               where s2.route_id = sr.id)))
     and not exists (select 1 from public.orders o
                      where o.fleet_id = p_fleet and o.status in ('pending', 'failed')) then
    return null;
  end if;$h$),

-- cmd.run_standing_route — SHOULD 3: names, not codes; no figure in prose; plain E_ROUTE_BROKEN.
('cmd.run_standing_route(uuid, timestamptz)', 1,
$h$      raise exception 'E_ROUTE_BROKEN: the route has % stop(s) and needs two', v_n using errcode = 'P0001';$h$,
$h$      raise exception 'E_ROUTE_BROKEN: This route has fewer than two stops.' using errcode = 'P0001';$h$),
('cmd.run_standing_route(uuid, timestamptz)', 2,
$h$    select s.*, p.code, p.kind into cur$h$,
$h$    select s.*, p.code, p.kind, p.name as port_name into cur$h$),
('cmd.run_standing_route(uuid, timestamptz)', 3,
$h$      raise exception 'E_ROUTE_BROKEN: stop % (%) is not a harbour', cur.ord, cur.code using errcode = 'P0001';$h$,
$h$      raise exception 'E_ROUTE_BROKEN: % has no market, so the route cannot stop there.', cur.port_name using errcode = 'P0001';$h$),
('cmd.run_standing_route(uuid, timestamptz)', 4,
$h$      select s.*, p.code into prv$h$,
$h$      select s.*, p.code, p.name as port_name into prv$h$),
('cmd.run_standing_route(uuid, timestamptz)', 5,
$h$          raise exception 'E_ROUTE_BROKEN: the onward SAIL could not be queued (%)', v_res->>'error_code' using errcode = 'P0001';$h$,
$h$          raise exception 'E_ROUTE_BROKEN: The queue was too full to add the sail onward.' using errcode = 'P0001';$h$),
('cmd.run_standing_route(uuid, timestamptz)', 6,
$h$        format('%s is not at %s or %s.', f.name, cur.code, prv.code));$h$,
$h$        format('%s is not at %s or %s.', f.name, cur.port_name, prv.port_name));$h$),
('cmd.run_standing_route(uuid, timestamptz)', 7,
$h$        format('The company has less than %s kept back.', sr.reserve));$h$,
$h$        'The company has less than it keeps back.');$h$),
('cmd.run_standing_route(uuid, timestamptz)', 8,
$h$        raise exception 'E_ROUTE_BROKEN: "%" could not be queued (%)', v_lines[i], v_res->>'error_code' using errcode = 'P0001';$h$,
$h$        raise exception 'E_ROUTE_BROKEN: The queue was too full to add the next stop''s orders.' using errcode = 'P0001';$h$),

-- cmd.standing_route_save — MUST 1: a name is a label, not a key.
('cmd.standing_route_save(uuid, text, jsonb, bigint, integer)', 1,
$h$    when unique_violation then
      return cmd.standing_route_refusal('E_NAME_TAKEN', format('You already keep a route named "%s".', v_name), '(pick another name)');
$h$,
$h$    -- 0093: no unique_violation arm — a name is a label, not a key (the name index is dropped).
$h$),

-- world.standing_routes — SHOULD 2 (settle in fleet-id order) and SHOULD 4 (`blocked`).
('world.standing_routes()', 1,
$h$              where player_id = v_player and fleet_id is not null loop$h$,
$h$              where player_id = v_player and fleet_id is not null
              order by fleet_id loop   -- 0093: fleets are locked in id order, as the verbs lock them$h$),
('world.standing_routes()', 2,
$h$                      when sr.hold_until is not null and sr.hold_until > now() then 'waiting'$h$,
$h$                      when f.status not in ('DOCKED', 'SAILING', 'REPAIRING') then 'blocked'   -- 0093: cannot move on by itself
                      when sr.hold_until is not null and sr.hold_until > now() then 'waiting'$h$);

-- ── 0b. THE PRE-IMAGES, captured before anything is cut ────────────────────────────────────────
create temporary table defs_before_0093 as
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
    from (select distinct fn from hunks_0093
          union select 'cmd.standing_route_assign(uuid, uuid)'
          union select 'cmd.standing_route_pause(uuid, boolean)'
          union select 'cmd.standing_route_delete(uuid)') as f(fn);

-- ── 0c. THE SLICE TOOL (its own copy, by necessity — tests/duplication.spec.ts:365-380) ────────
create or replace function pg_temp.recut_0093(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0093 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0093 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against.',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

-- ── 1. MUST 1 — a name is a label, not a key ───────────────────────────────────────────────────
drop index public.standing_routes_player_name_unique;

-- ── 2. THE SLICED RE-CUTS ──────────────────────────────────────────────────────────────────────
select pg_temp.recut_0093(fn) from (select distinct fn from hunks_0093) x order by fn;

-- ── 3. THE WHOLE REPLACEMENTS — the fleet is locked first, then the route ─────────────────────
-- THE ONE LOCK ORDER (SHOULD 2): voyage.settle, cmd.issue, public.tick_arrivals and the read all
-- lock a FLEET row and then reach its ROUTE row (cmd.run_standing_route, `for update`). A verb that
-- held the route and then waited for the fleet was the other half of a deadlock with the minute
-- tick. Each verb below reads which fleet the route is on WITHOUT a lock, locks that fleet (and the
-- one it is given, in id order), and only then locks the route; if the route moved fleets in that
-- instant it answers E_BUSY ("try again", 0083's code for a lock collision) rather than guess.

create or replace function cmd.standing_route_assign(p_route uuid, p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  sr       public.standing_routes%rowtype;
  f        public.fleets%rowtype;
  v_held   uuid;
  v_other  text;
  v_anchor int;
begin
  if v_player is null then
    return cmd.standing_route_refusal('E_NOT_SIGNED_IN', 'Nobody is signed in.', '(sign in first)');
  end if;
  if not public.standing_routes_on() then
    return cmd.standing_route_refusal('E_UNAVAILABLE', 'Routes are not open yet.', '(wait for routes to open)');
  end if;

  -- FLEET BEFORE ROUTE: the fleet it is on now and the fleet it is given, in id order.
  select r.fleet_id into v_held from public.standing_routes r where r.id = p_route and r.player_id = v_player;
  perform 1 from public.fleets where id in (p_fleet, v_held) order by id for update;
  select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
  if sr.id is null then
    return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
  end if;
  if sr.fleet_id is distinct from v_held then
    return cmd.standing_route_refusal('E_BUSY', 'The route changed while you pressed. Try again.', '(try again)');
  end if;

  -- EVERY CHECK FIRST. A refused assign changes nothing: not the route, not the lap, not the old
  -- fleet's queue (0092 released that queue before these checks ran).
  if p_fleet is not null then
    select * into f from public.fleets where id = p_fleet;
    if f.id is null or f.player_id <> v_player then
      return cmd.standing_route_refusal('E_NO_SUCH_FLEET', 'That fleet is not yours.', '(pick one of your own fleets)');
    end if;
    select name into v_other from public.standing_routes where fleet_id = p_fleet and id <> sr.id;
    if v_other is not null then
      return cmd.standing_route_refusal('E_ROUTE_TAKEN', format('%s already runs the route "%s".', f.name, v_other),
        '(stop that route first)');
    end if;
    if f.status <> 'DOCKED' then
      return cmd.standing_route_refusal('E_NOT_DOCKED', format('%s must be in port at one of the route''s stops to start it.', f.name),
        '(start it when the fleet is in port)');
    end if;
    select min(ord) into v_anchor from public.standing_route_stops where route_id = sr.id and port_id = f.port_id;
    if v_anchor is null then
      return cmd.standing_route_refusal('E_NOT_ON_ROUTE',
        format('%s is in %s, which is not a stop on this route.', f.name, (select name from public.ports where id = f.port_id)),
        '(sail to one of the stops first)');
    end if;
    if f.provision_preset_id is null then
      return cmd.standing_route_refusal('E_NO_KEEP', 'Set how many days of supplies to keep first.',
        '(set the supplies to keep for this fleet)');
    end if;
  end if;

  -- Whatever fleet held it is released: its pending route orders become ordinary orders.
  if sr.fleet_id is not null and sr.fleet_id is distinct from p_fleet then
    update public.orders set route_lap_id = null
     where fleet_id = sr.fleet_id and status = 'pending' and route_lap_id is not null;
  end if;
  -- The open lap is CLOSED by the one closer — what it traded so far is a lap in History — never
  -- left open for good (0092 only forgot its id).
  if sr.lap_id is not null then
    perform cmd.standing_route_close_lap(sr.id, now());
  end if;

  if p_fleet is null then
    update public.standing_routes
       set fleet_id = null, lap_id = null, hold_until = null, paused_reason = null, updated_at = now()
     where id = sr.id;
    return jsonb_build_object('ok', true, 'route', sr.name, 'fleet', null);
  end if;

  update public.standing_routes
     set fleet_id = p_fleet, stop_cursor = v_anchor, paused_reason = null, hold_until = null,
         lap_id = null, updated_at = now()
   where id = sr.id;
  -- The route starts NOW: the one queue runner, which refills when the queue is dry.
  perform cmd.advance(p_fleet, now());
  return jsonb_build_object('ok', true, 'route', sr.name, 'fleet', f.name,
    'queue', cmd.queue(p_fleet), 'version', (select version from public.fleets where id = p_fleet));
end $$;

create or replace function cmd.standing_route_pause(p_route uuid, p_paused boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  sr       public.standing_routes%rowtype;
  v_held   uuid;
begin
  if v_player is null then
    return cmd.standing_route_refusal('E_NOT_SIGNED_IN', 'Nobody is signed in.', '(sign in first)');
  end if;
  if not public.standing_routes_on() then
    return cmd.standing_route_refusal('E_UNAVAILABLE', 'Routes are not open yet.', '(wait for routes to open)');
  end if;
  -- FLEET BEFORE ROUTE (0093).
  select r.fleet_id into v_held from public.standing_routes r where r.id = p_route and r.player_id = v_player;
  perform 1 from public.fleets where id = v_held for update;
  select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
  if sr.id is null then
    return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
  end if;
  if sr.fleet_id is distinct from v_held then
    return cmd.standing_route_refusal('E_BUSY', 'The route changed while you pressed. Try again.', '(try again)');
  end if;
  if coalesce(p_paused, true) then
    update public.standing_routes set paused_reason = 'player', updated_at = now() where id = sr.id;
    return jsonb_build_object('ok', true, 'route', sr.name, 'paused', true);
  end if;
  update public.standing_routes set paused_reason = null, hold_until = null, updated_at = now() where id = sr.id;
  if sr.fleet_id is not null then
    perform cmd.advance(sr.fleet_id, now());
  end if;
  return jsonb_build_object('ok', true, 'route', sr.name, 'paused', false);
end $$;

create or replace function cmd.standing_route_delete(p_route uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  sr       public.standing_routes%rowtype;
  v_held   uuid;
begin
  if v_player is null then
    return cmd.standing_route_refusal('E_NOT_SIGNED_IN', 'Nobody is signed in.', '(sign in first)');
  end if;
  if not public.standing_routes_on() then
    return cmd.standing_route_refusal('E_UNAVAILABLE', 'Routes are not open yet.', '(wait for routes to open)');
  end if;
  -- FLEET BEFORE ROUTE (0093): the delete also writes that fleet's orders (route_lap_id -> null).
  select r.fleet_id into v_held from public.standing_routes r where r.id = p_route and r.player_id = v_player;
  perform 1 from public.fleets where id = v_held for update;
  select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
  if sr.id is null then
    return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
  end if;
  if sr.fleet_id is distinct from v_held then
    return cmd.standing_route_refusal('E_BUSY', 'The route changed while you pressed. Try again.', '(try again)');
  end if;
  -- Orders already queued stay, as ORDINARY orders under the ordinary halt law: the laps cascade
  -- away and orders.route_lap_id goes null with them (the FK's on delete set null).
  delete from public.standing_routes where id = sr.id;
  return jsonb_build_object('ok', true, 'deleted', sr.name);
end $$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0093-4000-8000-000000000001';
  c_auth2   constant uuid := '00000000-0093-4000-8000-000000000002';
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_base    int;
  v_player  uuid;
  v_player2 uuid;
  v_fleet   uuid;
  v_fleet2  uuid;
  v_fname   text;
  v_lis     uuid;
  v_fnc     uuid;
  v_cad     uuid;
  v_good    text;
  v_leg     jsonb;
  v_back_c  jsonb;
  v_stops   jsonb;
  v_res     jsonb;
  v_read    jsonb;
  v_route   uuid;
  v_r2      uuid;
  v_lap     uuid;
  v_order   uuid;
  v_ev      int;
  v_state   text;
  v_sent    text;
  v_sent2   text;
  v_skip1   text;
  v_skip2   text;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION: every sliced body, with each 0093 hunk put back the other
  --     way (each new hunk occurring exactly once), is its pre-image to the character.
  for v_fn in select distinct fn from hunks_0093 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0093 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0093 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0093 where fn = v_fn) or v_def = v_back then
      raise exception '0093 self-assert FAIL: % is not its pre-image plus only 0093''s hunks', v_fn;
    end if;
  end loop;
  -- ...and no re-cut or replacement moved an ACL.
  for v_fn in select fn from defs_before_0093 loop
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0093 where fn = v_fn) then
      raise exception '0093 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;
  -- The one lock order, read off the bodies: each verb locks a fleet BEFORE it locks the route.
  foreach v_fn in array array['cmd.standing_route_assign(uuid, uuid)', 'cmd.standing_route_pause(uuid, boolean)',
                              'cmd.standing_route_delete(uuid)'] loop
    v_def := pg_get_functiondef(v_fn::regprocedure);
    if strpos(v_def, 'perform 1 from public.fleets') = 0
       or strpos(v_def, 'player_id = v_player for update') = 0
       or strpos(v_def, 'perform 1 from public.fleets') > strpos(v_def, 'player_id = v_player for update') then
      raise exception '0093 self-assert FAIL: % does not lock the fleet before the route', v_fn;
    end if;
  end loop;
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'standing_routes_player_name_unique') then
    raise exception '0093 self-assert FAIL: the route name is still a key';
  end if;

  -- (b) THE PROBE — real houses, the real verbs, the tick; then rolled back. Baseline first.
  select count(*) into v_base from public.players;
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    update public.world_config set value = to_jsonb(0) where key = 'standing_route_laps_per_game_day';
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_fnc from public.ports where code = 'FNC';
    select id into v_cad from public.ports where code = 'CAD';
    v_player  := public.new_house(c_auth,  'Casa do Registo', 'PRT');
    v_player2 := public.new_house(c_auth2, 'Casa do Lado', 'PRT');
    select id, name into v_fleet, v_fname from public.fleets where player_id = v_player;
    select id into v_fleet2 from public.fleets where player_id = v_player2;
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                             jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_leg from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'FNC';
    v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
    perform cmd.assume_identity(c_auth);
    select gl->>'code' into v_good
      from jsonb_array_elements(world.market(v_lis)->'goods') gl
     where (gl->>'offered')::boolean and (gl->>'available')::boolean and (gl->>'stock')::numeric >= 60
       and (gl->>'buy')::numeric between 5 and 60
     order by gl->>'code' limit 1;
    if v_good is null then
      raise exception '0093 self-assert FAIL: no good is bought at Lisbon for the probe';
    end if;
    v_stops := jsonb_build_array(
      jsonb_build_object('port', 'LIS', 'course', v_leg, 'lines', jsonb_build_array(
        jsonb_build_object('kind', 'SELL'), jsonb_build_object('kind', 'BUY', 'good', v_good, 'qty', 20))),
      jsonb_build_object('port', 'FNC', 'course', v_back_c, 'lines', jsonb_build_array(jsonb_build_object('kind', 'SELL'))));

    -- ── MUST 1: a refused Start leaves a route the read SERVES, and the name is free again ───────
    v_res := cmd.standing_route_save(null, 'Lisbon ⇄ Funchal', v_stops, 0, 20);
    v_route := (v_res->>'id')::uuid;
    if v_route is null or cmd.standing_route_assign(v_route, v_fleet)->>'error_code' <> 'E_NO_KEEP' then
      raise exception '0093 self-assert FAIL: the orphan scenario did not set up (save %)', v_res;
    end if;
    select r->>'state' into v_state from jsonb_array_elements(world.standing_routes()->'routes') r
     where (r->>'id')::uuid = v_route and r->'fleet' = 'null'::jsonb;
    v_res := cmd.standing_route_save(null, 'Lisbon ⇄ Funchal', v_stops, 0, 20);
    v_r2 := (v_res->>'id')::uuid;
    if v_state is distinct from 'unassigned' or v_r2 is null or v_r2 = v_route then
      raise exception '0093 self-assert FAIL: the refused route is not served as unassigned (%), or the same name was refused again: %', v_state, v_res;
    end if;
    if cmd.standing_route_delete(v_r2)->>'ok' <> 'true' then
      raise exception '0093 self-assert FAIL: the second route could not be deleted';
    end if;

    -- The keep level set, the SAME route starts by its id.
    v_res := cmd.provision_preset_save(null, 'Route keep', 12);
    perform cmd.provision_preset_apply(v_fleet, (v_res->>'id')::uuid);
    v_res := cmd.standing_route_assign(v_route, v_fleet);
    select lap_id into v_lap from public.standing_routes where id = v_route;
    if not coalesce((v_res->>'ok')::boolean, false) or v_lap is null
       or (select status from public.fleets where id = v_fleet) <> 'SAILING' then
      raise exception '0093 self-assert FAIL: the route did not start by its id: %', v_res;
    end if;

    -- ── A REFUSED ASSIGN CHANGES NOTHING (the old body released the queue before its checks) ──
    v_res := cmd.enqueue(v_player, jsonb_set(cmd.parse(v_player, v_fleet, format('SELL %s ALL', v_good)),
                         '{fleet_id}', to_jsonb(v_fleet::text)), format('SELL %s ALL', v_good), null, v_lap);
    v_order := (v_res->>'order_id')::uuid;
    -- The verb runs in its OWN statement: a sub-select in the same IF would read the snapshot taken
    -- before the verb's writes and pass whatever it did (scripts/db/breaktest-0093.mjs caught that).
    v_res := cmd.standing_route_assign(v_route, v_fleet2);
    if v_res->>'error_code' <> 'E_NO_SUCH_FLEET'
       or (select route_lap_id from public.orders where id = v_order) is distinct from v_lap
       or (select lap_id from public.standing_routes where id = v_route) is distinct from v_lap
       or (select fleet_id from public.standing_routes where id = v_route) is distinct from v_fleet then
      raise exception '0093 self-assert FAIL: a refused assign changed the route or released its fleet''s orders';
    end if;
    update public.orders set status = 'cancelled' where id = v_order;

    -- ── SHOULD 5: with the player's own onward SAIL queued, the arrival order resupplies ───────
    v_res := cmd.issue(v_fleet, 'SAIL TO LIS', null, v_back_c);
    select count(*) into v_ev from public.events
     where player_id = v_player and kind = 'PROVISIONED' and (payload->>'standing')::boolean;
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fleet and status = 'SAILING';
    perform public.tick_arrivals(now());
    if (select count(*) from public.events
         where player_id = v_player and kind = 'PROVISIONED' and (payload->>'standing')::boolean) <> v_ev + 1
       or (select status from public.fleets where id = v_fleet) <> 'SAILING'
       or (select dest_port_id from public.voyages where fleet_id = v_fleet and status = 'SAILING') <> v_lis then
      raise exception '0093 self-assert FAIL: a queued onward SAIL of the player''s own left Funchal unsupplied (issue %, events %)',
        v_res, (select jsonb_agg(jsonb_build_array(kind, payload)) from public.events where player_id = v_player and kind like 'PROVISION%');
    end if;

    -- ── SHOULD 4: it makes port unable to sail -> the read says `blocked`, not "in port" ───────
    update public.ships set durability = 0 where fleet_id = v_fleet and is_flagship;
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fleet and status = 'SAILING';
    perform public.tick_arrivals(now());
    select r->>'state' into v_state from jsonb_array_elements(world.standing_routes()->'routes') r
     where (r->>'id')::uuid = v_route;
    if (select status from public.fleets where id = v_fleet) <> 'UNABLE_TO_SAIL' or v_state is distinct from 'blocked' then
      raise exception '0093 self-assert FAIL: a fleet unable to sail reads % (status %)', v_state,
        (select status from public.fleets where id = v_fleet);
    end if;
    update public.ships s set durability = c.durability from public.ship_classes c
     where c.id = s.class_id and s.fleet_id = v_fleet;
    update public.fleets set status = 'DOCKED' where id = v_fleet;

    -- ── SHOULD 3: pause sentences carry names, and no figure ───────────────────────────────────
    update public.fleets set port_id = v_cad where id = v_fleet;   -- on no stop of the route
    perform cmd.standing_route_pause(v_route, false);
    select payload->>'sentence' into v_sent from public.events
     where player_id = v_player and kind = 'ROUTE_PAUSED' and payload->>'reason' = 'off_route'
     order by created_at desc limit 1;
    if (select paused_reason from public.standing_routes where id = v_route) is distinct from 'off_route'
       or v_sent is distinct from format('%s is not at %s or %s.', v_fname,
            (select name from public.ports where id = v_fnc), (select name from public.ports where id = v_lis)) then
      raise exception '0093 self-assert FAIL: the off-route sentence is %', v_sent;
    end if;
    update public.fleets set port_id = v_fnc where id = v_fleet;   -- at the stop it is bound for
    update public.standing_routes set reserve = 5000000 where id = v_route;
    perform cmd.standing_route_pause(v_route, false);
    select payload->>'sentence' into v_sent2 from public.events
     where player_id = v_player and kind = 'ROUTE_PAUSED' and payload->>'reason' = 'reserve'
     order by created_at desc limit 1;
    if (select paused_reason from public.standing_routes where id = v_route) is distinct from 'reserve'
       or v_sent2 is null or v_sent2 ~ '[0-9]' then
      raise exception '0093 self-assert FAIL: the reserve sentence is %', v_sent2;
    end if;
    update public.standing_routes set reserve = 0 where id = v_route;

    -- ── NIT 10: taking the route off its fleet CLOSES the open lap ─────────────────────────────
    select count(*) into v_ev from public.events where player_id = v_player and kind = 'ROUTE_LAP';
    v_res := cmd.standing_route_assign(v_route, null);
    if not coalesce((v_res->>'ok')::boolean, false)
       or (select closed_at from public.standing_route_laps where id = v_lap) is null
       or (select count(*) from public.events where player_id = v_player and kind = 'ROUTE_LAP') <> v_ev + 1
       or (select lap_id from public.standing_routes where id = v_route) is not null then
      raise exception '0093 self-assert FAIL: taking the route off its fleet left lap % open (%)', v_lap, v_res;
    end if;

    -- ── NIT 7: a refused route line HALTS while the switch is off, and is stepped over when on ─
    perform cmd.assume_identity(c_auth2);
    update public.world_config set value = 'false'::jsonb where key = 'standing_routes_enabled';
    v_res := cmd.enqueue(v_player2, jsonb_set(cmd.parse(v_player2, v_fleet2, format('SELL %s 10', v_good)),
                         '{fleet_id}', to_jsonb(v_fleet2::text)), format('SELL %s 10', v_good), null, v_lap);
    perform cmd.advance(v_fleet2, now());
    select status into v_skip1 from public.orders where id = (v_res->>'order_id')::uuid;
    perform cmd.clear(v_fleet2, false);
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    v_res := cmd.enqueue(v_player2, jsonb_set(cmd.parse(v_player2, v_fleet2, format('SELL %s 10', v_good)),
                         '{fleet_id}', to_jsonb(v_fleet2::text)), format('SELL %s 10', v_good), null, v_lap);
    perform cmd.advance(v_fleet2, now());
    select status into v_skip2 from public.orders where id = (v_res->>'order_id')::uuid;
    if v_skip1 is distinct from 'failed' or v_skip2 is distinct from 'skipped' then
      raise exception '0093 self-assert FAIL: a refused route line with the switch off was %, on was %', v_skip1, v_skip2;
    end if;

    -- ── DOORS, unchanged ───────────────────────────────────────────────────────────────────────
    foreach v_fn in array array['world.standing_routes()', 'cmd.standing_route_save(uuid, text, jsonb, bigint, integer)',
        'cmd.standing_route_delete(uuid)', 'cmd.standing_route_assign(uuid, uuid)', 'cmd.standing_route_pause(uuid, boolean)'] loop
      if not has_function_privilege('authenticated', v_fn, 'execute') or has_function_privilege('anon', v_fn, 'execute') then
        raise exception '0093 self-assert FAIL: % is not open to authenticated and closed to anon', v_fn;
      end if;
    end loop;
    foreach v_fn in array array['cmd.run_standing_route(uuid, timestamptz)', 'cmd.run_standing_provision(uuid)',
        'cmd.advance(uuid, timestamptz)'] loop
      if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
        raise exception '0093 self-assert FAIL: a client role may execute %', v_fn;
      end if;
    end loop;
    if (select count(*) from public.client_write_grants()) <> 0
       or (select count(*) from public.client_executable_writers()) <> 0
       or (select count(*) from public.caller_evaluated_functions()) <> 0 then
      raise exception '0093 self-assert FAIL: a client write grant, a client-executable writer or a read-wall gap';
    end if;

    raise exception using errcode = 'P0930', message = '0093 probe rollback';
  exception when sqlstate 'P0930' then
    null;
  end;

  if (select count(*) from public.players) <> v_base
     or exists (select 1 from public.players where auth_uid in (c_auth, c_auth2))
     or exists (select 1 from public.standing_routes) then
    raise exception '0093 self-assert FAIL: the probe leaked a house or a route';
  end if;
  if public.standing_routes_on() then
    raise exception '0093 self-assert FAIL: the switch is on after the probe — routes still ship DARK';
  end if;

  raise notice '0093 self-assert ok: A ROUTE IS KNOWN BY ITS ID, AND WAITS BEHIND ITS FLEET. Five sliced re-cuts (advance, run_standing_provision, run_standing_route, standing_route_save, world.standing_routes) reverse to their pre-images hunk by hunk, ACLs unmoved; assign, pause and delete lock the fleet before the route; the name index is gone. On a thrown-away house with the switch on: a refused Start (E_NO_KEEP) left a route the read serves as unassigned, the same name saved again, and the route then started by its id; a refused assign changed neither the route, its lap nor its fleet''s route orders; a queued SAIL of the player''s own left Funchal resupplied by the arrival order; a fleet that made port unable to sail read blocked; the off-route sentence named the ports (%) and the reserve sentence carried no figure (%); taking the route off its fleet closed the open lap; a refused route line halted with the switch off (%) and was stepped over with it on (%); doors unchanged. Rolled back; the switch ships OFF.',
    v_sent, v_sent2, v_skip1, v_skip2;
end $$;
