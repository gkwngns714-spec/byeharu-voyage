-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0094 — A RESUMED ROUTE SAILS, AND A DELETED ONE CLOSES ITS LAP
--        Found by driving PR #89 in a real browser against the local PGlite build (2026-09-30),
--        before 0092/0093 were ever deployed. 0092 and 0093 are NOT edited (the no-edit law,
--        docs/NO_SPAGHETTI.md §3): this file supersedes them forward, and the three ship together.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT THE DRIVE FOUND, AND WHAT THIS FILE DOES ABOUT EACH ───────────────────────────────────
--   1. RESUME DID NOTHING AFTER A "LOSING" PAUSE. Lisbon ⇄ Porto lost money three laps running and
--      paused itself ("Paused: the last laps lost money.") — the guard working. The player edited
--      the Max price and pressed Resume: the verb cleared the reason, ran the queue, and
--      cmd.run_standing_route, standing at the first stop with NO lap open (it was closed when the
--      route paused), judged the same three closed laps again and paused the route on the spot. A
--      second ROUTE_PAUSED row, no lap, and a Resume button that could never resume — the only way
--      out was Delete. -> The loss guard is judged ONLY when this very call has just closed a lap
--      (the lap boundary the guard was written for). A Resume, an Edit or a fresh Start therefore
--      sails one more lap; if that lap loses too, the last N laps still lost money and the route
--      pauses again at its end — the streak is not forgotten, it is just not re-judged without
--      a new lap to judge.
--   2. DELETE LEFT THE OPEN LAP'S MONEY OFF HISTORY. Deleting a route mid-lap cascaded the lap
--      away without its ROUTE_LAP line (0093 closed the open lap on assign and unassign, not on
--      delete): History showed the BUY of 2,038 🪙 and no lap that owned it. -> delete closes the
--      open lap with the one closer (cmd.standing_route_close_lap) before the row goes.
--
-- ── WHAT THIS FILE SUPERSEDES ──────────────────────────────────────────────────────────────────
--   SLICED from pg_get_functiondef (every hunk asserted to occur exactly once, LF-normalised,
--   parity proven by REVERSE substitution back to the pre-image, ACLs unmoved):
--     cmd.run_standing_route(uuid, timestamptz)   two hunks: a `v_closed` flag; the guard reads it.
--     cmd.standing_route_delete(uuid)             one hunk: the open lap is closed first.
--   With the switch OFF (it still is — this file does not touch it) both paths are inert exactly
--   as before: run_standing_route returns 0 at its first line and the verb refuses E_UNAVAILABLE.
--
-- ── SECOND CALLERS ─────────────────────────────────────────────────────────────────────────────
--   None new. The ROUTE_LAP line delete now writes is the same event History already words
--   (src/features/ledger/headline.ts).
--
-- Depends on: 0092 (everything route), 0093 (the delete body, the closer on assign).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. THE HUNKS, written ONCE, read by the cut and by the parity proof ────────────────────────
create temporary table hunks_0094 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n));

insert into hunks_0094 values
-- cmd.run_standing_route — 1: the flag.
('cmd.run_standing_route(uuid, timestamptz)', 1,
$h$  v_lap    uuid;
$h$,
$h$  v_lap    uuid;
  v_closed boolean := false;   -- 0094: this call closed a lap, so the loss guard may judge
$h$),
-- cmd.run_standing_route — 2: the guard judges only at a lap this call closed.
('cmd.run_standing_route(uuid, timestamptz)', 2,
$h$        sr.lap_id := null;
      end if;
      -- LOSS GUARD: the last N closed laps all lost money.
      if (select count(*)$h$,
$h$        sr.lap_id := null;
        v_closed := true;
      end if;
      -- LOSS GUARD: the last N closed laps all lost money — judged when a lap has just closed
      -- (0094), so a Resume after a losing pause sails one more lap instead of pausing on the spot.
      if v_closed and (select count(*)$h$),
-- cmd.standing_route_delete — the open lap is closed before the route goes.
('cmd.standing_route_delete(uuid)', 1,
$h$  delete from public.standing_routes where id = sr.id;
$h$,
$h$  -- 0094: the open lap is CLOSED first, so what it traded is a lap line in History.
  if sr.lap_id is not null then
    perform cmd.standing_route_close_lap(sr.id, now());
  end if;
  delete from public.standing_routes where id = sr.id;
$h$);

-- ── 0b. THE PRE-IMAGES, captured before anything is cut ────────────────────────────────────────
create temporary table defs_before_0094 as
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
    from (select distinct fn from hunks_0094) as f(fn);

-- ── 0c. THE SLICE TOOL (its own copy, by necessity — tests/duplication.spec.ts:365-380) ────────
create or replace function pg_temp.recut_0094(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0094 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0094 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against.',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

-- ── 1. THE SLICED RE-CUTS ──────────────────────────────────────────────────────────────────────
select pg_temp.recut_0094(fn) from (select distinct fn from hunks_0094) x order by fn;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0094-4000-8000-000000000001';
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_base    int;
  v_player  uuid;
  v_fleet   uuid;
  v_lis     uuid;
  v_good    text;
  v_leg     jsonb;
  v_back_c  jsonb;
  v_stops   jsonb;
  v_res     jsonb;
  v_route   uuid;
  v_lap_no  int;
  v_ev      int;
  v_paused  int;
  v_reason  text;
  v_status  text;
  v_resumed uuid;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION: every sliced body, with each 0094 hunk put back the other
  --     way (each new hunk occurring exactly once), is its pre-image to the character.
  for v_fn in select distinct fn from hunks_0094 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0094 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0094 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0094 where fn = v_fn) or v_def = v_back then
      raise exception '0094 self-assert FAIL: % is not its pre-image plus only 0094''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0094 where fn = v_fn) then
      raise exception '0094 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) THE PROBE — a real house, the real verbs, the tick; then rolled back.
  select count(*) into v_base from public.players;
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    update public.world_config set value = to_jsonb(0) where key = 'standing_route_laps_per_game_day';
    select id into v_lis from public.ports where code = 'LIS';
    v_player := public.new_house(c_auth, 'Casa da Retoma', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
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
      raise exception '0094 self-assert FAIL: no good is bought at Lisbon for the probe';
    end if;
    v_stops := jsonb_build_array(
      jsonb_build_object('port', 'LIS', 'course', v_leg, 'lines', jsonb_build_array(
        jsonb_build_object('kind', 'SELL'), jsonb_build_object('kind', 'BUY', 'good', v_good, 'qty', 20))),
      jsonb_build_object('port', 'FNC', 'course', v_back_c, 'lines', jsonb_build_array(jsonb_build_object('kind', 'SELL'))));
    v_res := cmd.standing_route_save(null, 'Lisbon ⇄ Funchal', v_stops, 0, 3);
    v_route := (v_res->>'id')::uuid;
    v_res := cmd.provision_preset_save(null, 'Route keep', 12);
    perform cmd.provision_preset_apply(v_fleet, (v_res->>'id')::uuid);
    v_res := cmd.standing_route_assign(v_route, v_fleet);
    if not coalesce((v_res->>'ok')::boolean, false)
       or (select status from public.fleets where id = v_fleet) <> 'SAILING' then
      raise exception '0094 self-assert FAIL: the probe route did not start: %', v_res;
    end if;

    -- Three losing laps already on the book (lap numbers above any the route will open), then the
    -- fleet sails the loop home: at Lisbon it closes lap 1 and the guard judges.
    insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, net)
    select v_route, 100 + g.n, now(), now(), -1 from generate_series(1, 3) as g(n);
    for v_n in 1 .. 2 loop
      update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform public.tick_arrivals(now());
    end loop;

    -- POSITIVE CONTROL: at a lap the tick just closed, the guard still bites.
    select paused_reason into v_reason from public.standing_routes where id = v_route;
    if v_reason is distinct from 'losing'
       or (select port_id from public.fleets where id = v_fleet) <> v_lis
       or (select status from public.fleets where id = v_fleet) <> 'DOCKED' then
      raise exception '0094 self-assert FAIL: three losing laps at a closed lap did not pause the route at Lisbon (reason %, fleet %)',
        v_reason, (select status from public.fleets where id = v_fleet);
    end if;

    -- 1. RESUME SAILS. The verb runs in its OWN statement (a sub-select in the same IF would read
    --    the snapshot taken before the verb's writes — scripts/db/breaktest-0093.mjs).
    select count(*) into v_paused from public.events where player_id = v_player and kind = 'ROUTE_PAUSED';
    v_res := cmd.standing_route_pause(v_route, false);
    select paused_reason, lap_id into v_reason, v_resumed from public.standing_routes where id = v_route;
    select status into v_status from public.fleets where id = v_fleet;
    if not coalesce((v_res->>'ok')::boolean, false) or v_reason is not null or v_resumed is null
       or v_status <> 'SAILING'
       or (select count(*) from public.events where player_id = v_player and kind = 'ROUTE_PAUSED') <> v_paused then
      raise exception '0094 self-assert FAIL: Resume after a losing pause did not sail a new lap (reason %, lap %, fleet %, verb %)',
        v_reason, v_resumed, v_status, v_res;
    end if;

    -- 2. DELETE CLOSES THE OPEN LAP: one more ROUTE_LAP line, for the lap that was open.
    --    Every event of this probe shares one created_at (one transaction), so the lap is found by
    --    its NUMBER, never as "the newest" line.
    select lap_no into v_lap_no from public.standing_route_laps where id = v_resumed;
    select count(*) into v_ev from public.events where player_id = v_player and kind = 'ROUTE_LAP';
    if exists (select 1 from public.events where player_id = v_player and kind = 'ROUTE_LAP'
                and (payload->>'lap')::int = v_lap_no) then
      raise exception '0094 self-assert FAIL: lap % already had its line before the delete — the probe proves nothing', v_lap_no;
    end if;
    v_res := cmd.standing_route_delete(v_route);
    if not coalesce((v_res->>'ok')::boolean, false)
       or exists (select 1 from public.standing_routes where id = v_route)
       or (select count(*) from public.events where player_id = v_player and kind = 'ROUTE_LAP') <> v_ev + 1
       or not exists (select 1 from public.events where player_id = v_player and kind = 'ROUTE_LAP'
                       and (payload->>'lap')::int = v_lap_no) then
      raise exception '0094 self-assert FAIL: deleting a route mid-lap did not write lap %''s line (%)', v_lap_no, v_res;
    end if;

    raise exception using errcode = 'P0940', message = '0094 probe rollback';
  exception when sqlstate 'P0940' then
    null;
  end;

  if (select count(*) from public.players) <> v_base
     or exists (select 1 from public.players where auth_uid = c_auth)
     or exists (select 1 from public.standing_routes) then
    raise exception '0094 self-assert FAIL: the probe leaked a house or a route';
  end if;
  if public.standing_routes_on() then
    raise exception '0094 self-assert FAIL: the switch is on after the probe — routes still ship DARK';
  end if;

  raise notice '0094 self-assert ok: A RESUMED ROUTE SAILS, AND A DELETED ONE CLOSES ITS LAP. Two sliced re-cuts (run_standing_route, standing_route_delete) reverse to their pre-images hunk by hunk, ACLs unmoved. On a thrown-away house with the switch on: three losing laps paused the route at the lap the tick closed (the guard still bites); Resume then sailed a new lap with no second ROUTE_PAUSED; deleting the route mid-lap wrote that lap''s ROUTE_LAP line. Rolled back; the switch ships OFF.';
end $$;
