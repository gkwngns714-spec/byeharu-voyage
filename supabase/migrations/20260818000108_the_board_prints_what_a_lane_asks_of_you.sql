-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0108 — THE BOARD PRINTS WHAT A LANE ASKS OF YOU
--        Owner row 117 (docs/OWNER_REQUESTS.md, 2026-10-11) — its second half.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK, AND WHICH HALF WAS MISSING ─────────────────────────────────────────────────────────
-- The owner, 2026-10-11: *"set levels (requirements)."* Row 117's own words for what that means on
-- a board: *"the route board PRINTS the requirement, so a player reads why a route is closed to
-- them instead of discovering it at sea."*
--
-- 0107 built the refusing half: a leg beyond a captain's NAVIGATION and a region beyond her
-- EXPLORATION are refused by `public.passage_gate`, at the sea's door and at the route's. But the
-- ROUTES board (0106) showed no requirement at all — deliberately, because a column of "—" would
-- have been the screen inventing a rule the server did not keep. Now the server keeps it, so the
-- board can print it.
--
-- ── IT IS NOT A NEW RULE, IT IS THE SAME ONE READ FORWARD ───────────────────────────────────────
-- `public.passage_gate` answers "may SHE sail THIS leg". A board needs the inverse: "what would
-- anyone need in order to sail this whole loop". `public.route_requirement` is that inverse, and it
-- is derived from the same two knobs and the same two stored figures — the leg lengths 0106 wrote
-- on each stop and the region levels 0107 wrote on each region. Nothing is measured again:
--
--   NAVIGATION — the smallest level whose reach covers her LONGEST leg. 0107's reach is
--   `nav_leg_nm_base × 2^(L−1)`, so the level is `1 + ceil(log2(longest / base))`, floored at 1.
--   Null when a leg is unmeasured (0106: a course the sea disputes), because a requirement nobody
--   can state is an absence and not a 1.
--
--   EXPLORATION — the dearest `min_exploration_level` among the harbours she calls at. A loop is
--   only as open as its most distant call.
--
-- ── AND WHETHER IT IS CLOSED TO *YOU* ───────────────────────────────────────────────────────────
-- The board also serves `closed`: true when the caller could not sail this loop today. That is a
-- SECOND statement of a rule `passage_gate` already owns, and this chain's rule for one of those is
-- that it is checked rather than trusted — so the self-assert below walks every route on the board
-- and requires `closed` to agree with what `passage_gate` says about that route's own stops, with
-- no disagreement allowed.
--
-- It is computed from the caller's levels read ONCE rather than by calling the gate per stop:
-- `public.player_progress` walks the ledger and the voyage reports every time it is asked (0069,
-- and deliberately — it cannot drift and cannot be inflated), and a board of 220 routes would ask
-- it some eight hundred times. The agreement assertion is what makes the shortcut safe.
--
-- `closed` IS ABOUT YOU AND NOT ABOUT WHOSE ROUTE IT IS, and a merchant's lane carries it too.
-- Merchants are exempt from the gates (0107) — a company founded with a 13,000 nm carreira has no
-- academy to go to — so "closed" could not mean "she may not sail it". It means YOU may not, which
-- is exactly the useful reading of another house's carreira: here is the lane, here is what it
-- would take. Computed identically for every row, hers and theirs.
--
-- ── WHAT THIS SUPERSEDES ────────────────────────────────────────────────────────────────────────
-- `world.route_board` (0106) by one hunk: two keys added to each row and nothing else moved. The
-- re-cut is proven below to be its pre-image plus only that hunk with its ACL unmoved, and the row
-- key set is asserted EXACTLY, so nothing can creep in beside them. WHEN THE NEW KEYS ARE IGNORED
-- the board is 0106's answer: the cap, the order, `total`, `omitted` and every other field are
-- untouched, and a client that does not read them sees no change.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. WHAT A LANE ASKS OF ANYONE ──────────────────────────────────────────────────────────────

-- ── THE CEILING THIS FILE NEEDS, AND WHY IT IS HERE AND NOT IN A RUNBOOK ───────────────────────
-- This migration takes about 145 s to apply, because its self-assert walks the whole roster — 838
-- routes and 3,302 calls since 0105, where the same assertions walked 77 and 230. A hosted
-- Postgres caps how long one statement may run, and on 2026-10-11 that cap ABORTED the production
-- push: `ERROR: canceling statement due to statement timeout (SQLSTATE 57014)` on 0105, which
-- rolled back whole and left the chain head at 0104 — a migration nobody chose, which is exactly
-- what docs/DEPLOY_RUNBOOK.md §2 exists to prevent.
--
-- IT PASSED LOCALLY BECAUSE PGLITE HAS NO SUCH CAP. That is the gap: the chain was proven against
-- a Postgres that cannot fail this way, and "proven" was claimed on the strength of it. The gate
-- is honest about everything it checks and silent about the one thing only the target can say.
--
-- So the file raises its own ceiling, for its own transaction only. `set_config(..., true)` is SET
-- LOCAL, so it reverts when this migration commits and cannot leak into the next one — and it is
-- written as set_config rather than `set local` because a bare SET LOCAL outside a transaction
-- block raises a WARNING, and the local gate reads every notice a migration prints.
--
-- TWENTY MINUTES AND NOT NOUGHT. Unbounded would mean a genuinely stuck statement holding locks on
-- production for ever; twenty minutes is several times the measured cost and still ends.
do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

create or replace function public.route_requirement(p_route uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0108 (owner row 117): {navigation, exploration} — the levels this loop asks of ANY captain, the
  -- inverse of public.passage_gate's "may she sail this leg". Both from figures already stored:
  -- 0106's course_nm per stop and 0107's min_exploration_level per region. NAVIGATION is null when
  -- any leg is unmeasured, because a requirement nobody can state is an absence and not a 1.
  select case when exists (select 1 from public.standing_routes r where r.id = p_route) then
    jsonb_build_object(
      'navigation', (
        select case when count(*) filter (where st.course_nm is null) > 0 then null
                    else greatest(1, 1 + ceil(log(2::numeric,
                           greatest(max(st.course_nm), 1) / public.wc_num('nav_leg_nm_base')))::int)
               end
          from public.standing_route_stops st where st.route_id = p_route),
      'exploration', coalesce((
        select max(r.min_exploration_level)
          from public.standing_route_stops st
          join public.ports po on po.id = st.port_id
          join public.regions r on r.id = po.region_id
         where st.route_id = p_route), 1))
  end
$$;

comment on function public.route_requirement(uuid) is
  '0108 (owner row 117): {navigation, exploration} — what a standing route asks of any captain, '
  'the inverse of public.passage_gate. NAVIGATION from the longest leg against nav_leg_nm_base x '
  '2^(L-1); EXPLORATION the dearest region the loop calls at. Derived from 0106''s stored leg '
  'lengths and 0107''s region levels, so nothing is measured twice. Server-only.';

-- ── 2. THE BOARD, RE-CUT ───────────────────────────────────────────────────────────────────────
create temporary table hunks_0108 (fn text not null, n int not null, old text not null, new text not null);
create temporary table defs_before_0108 (fn text primary key, def text not null, acl text not null);

insert into hunks_0108 values
('world.route_board()', 1,
$h$           'state', pick.state,$h$,
$h$           -- 0108 (owner row 117): WHAT THIS LANE ASKS, and whether it is shut to YOU. The
           -- requirement is the same rule passage_gate refuses by, read forward; `closed` compares
           -- it to the caller's own levels, read ONCE above rather than by calling the gate once
           -- per stop — player_progress walks the ledger every time it is asked, and a board of 220
           -- routes would ask it eight hundred times. The self-assert holds `closed` to agreeing
           -- with passage_gate on every route, which is what makes that shortcut safe.
           'requires', public.route_requirement(pick.id),
           -- `greatest(1, v_nav)` and not v_nav: a captain who has never studied navigation has the
           -- reach of level ONE, because passage_gate's own reach is nav_leg_nm_base x
           -- 2^greatest(0, NAVIGATION-1). Comparing against the raw 0 would shut every lane in the
           -- world to a beginner, including the 525 nm hop the gate happily allows — and the
           -- agreement assertion below caught exactly that.
           'closed', coalesce((public.route_requirement(pick.id)->>'navigation')::int, 1) > greatest(1, v_nav)
                     or coalesce((public.route_requirement(pick.id)->>'exploration')::int, 1) > v_exp,
           'state', pick.state,$h$),
('world.route_board()', 2,
$h$  v_total int;
  v_rows  jsonb;
begin$h$,
$h$  v_total int;
  v_rows  jsonb;
  v_nav   int;     -- 0108: the caller's own NAVIGATION, read once
  v_exp   int;     -- 0108: ...and her EXPLORATION level
begin$h$),
('world.route_board()', 3,
$h$  v_max   int := greatest(1, public.wc_int('route_board_max'));$h$,
$h$  v_max   int := greatest(1, public.wc_int('route_board_max'));
  -- 0108: her levels, ONCE. public.player_progress is derived from the append-only record on every
  -- call (0069) and is not a counter to be read per row.$h$);

insert into defs_before_0108
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', ''),
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '')
  from (select distinct fn from hunks_0108) as f(fn);

create or replace function pg_temp.recut_0108(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0108 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0108 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0108: hunk % of % matches the pre-image % time(s), not once', h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0108(fn) from (select distinct fn from hunks_0108) x order by fn;

-- The two readings the hunks DECLARED, now assigned where the body can use them — AFTER the
-- no-house guard, because a caller with no company must be told that rather than asked for her
-- levels. One replacement, checked to match exactly once, and struck back out by the parity
-- assertion below so the re-cut is still provably the pre-image plus only what this file states.
do $$
declare
  v_def text := replace(pg_get_functiondef('world.route_board()'::regprocedure), E'\r', '');
  v_old text := $x$    raise exception 'E_NO_HOUSE: there is no company on this account' using errcode = 'P0001';
  end if;$x$;
begin
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception '0108: the board''s no-house guard is not where this file expects it';
  end if;
  execute replace(v_def, v_old, v_old || $x$

  -- 0108: her levels, ONCE, and only once she is known to have a company.
  v_nav := public.skill_level(v_me, 'NAVIGATION');
  v_exp := coalesce((public.player_progress(v_me)->'exploration'->>'level')::int, 1);$x$);
end $$;

-- ── 3. GRANTS ──────────────────────────────────────────────────────────────────────────────────
revoke all on function public.route_requirement(uuid) from public, anon, authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.okeys_0108(p jsonb)
returns text[]
language sql
immutable
as $$
  select coalesce(array_agg(k order by k collate "C"), '{}') from jsonb_object_keys(p) k
$$;

do $$
declare
  c_auth    constant uuid := '00000000-0108-4000-8000-0000000000a1';
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_base    int;
  v_me      uuid;
  v_fleet   uuid;
  v_lis     uuid;
  v_fnc     uuid;
  v_leg     jsonb;
  v_back_c  jsonb;
  v_route   uuid;
  v_board   jsonb;
  v_row     jsonb;
  v_keys    text[];
  v_req     jsonb;
  v_long    numeric;
  v_need    int;
  v_bad     int;
  v_closed  int;
  v_open    int;
  v_sk      uuid;
  v_ms      numeric;
  v_t0      timestamptz;
begin
  -- (a) THE BOARD IS ITS PRE-IMAGE PLUS ONLY THIS FILE'S HUNKS, ACL UNMOVED.
  for v_fn in select distinct fn from hunks_0108 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0108 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0108 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    -- the two assignments are not hunks, so they are struck out here before the comparison
    v_back := replace(v_back, $x$

  -- 0108: her levels, ONCE, and only once she is known to have a company.
  v_nav := public.skill_level(v_me, 'NAVIGATION');
  v_exp := coalesce((public.player_progress(v_me)->'exploration'->>'level')::int, 1);$x$, '');
    if v_back <> (select def from defs_before_0108 where fn = v_fn) or v_def = v_back then
      raise exception '0108 self-assert FAIL: % is not its pre-image plus only 0108''s changes', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0108 where fn = v_fn) then
      raise exception '0108 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) THE NEW READING IS REACHABLE BY NOBODY; the walls still read zero.
  if has_function_privilege('authenticated', 'public.route_requirement(uuid)', 'execute')
     or has_function_privilege('anon', 'public.route_requirement(uuid)', 'execute') then
    raise exception '0108 self-assert FAIL: route_requirement is reachable by a client';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0108 self-assert FAIL: the grant wall or the read wall';
  end if;

  -- (c) THE REQUIREMENT IS THE SAME RULE READ FORWARD, on the whole world's routes.
  if public.route_requirement('00000000-0000-4000-8000-000000000000'::uuid) is not null then
    raise exception '0108 self-assert FAIL: a route that does not exist asks something';
  end if;
  -- For every route in the world: the NAVIGATION it asks is the smallest level whose reach covers
  -- its longest leg — so that level's reach DOES cover it and one level less does NOT.
  select count(*) into v_bad from public.standing_routes sr
   cross join lateral (select public.route_requirement(sr.id) as req,
                              (select max(st.course_nm) from public.standing_route_stops st
                                where st.route_id = sr.id) as longest) q
   where (q.req->>'navigation') is not null
     and (public.wc_num('nav_leg_nm_base') * power(2::numeric, (q.req->>'navigation')::int - 1) < q.longest
          or ((q.req->>'navigation')::int > 1
              and public.wc_num('nav_leg_nm_base') * power(2::numeric, (q.req->>'navigation')::int - 2) >= q.longest));
  if v_bad <> 0 then
    raise exception '0108 self-assert FAIL: % route(s) ask the wrong NAVIGATION for their longest leg', v_bad;
  end if;
  -- ...and the EXPLORATION it asks is the dearest region it calls at, re-derived here.
  select count(*) into v_bad from public.standing_routes sr
   where (public.route_requirement(sr.id)->>'exploration')::int is distinct from
         coalesce((select max(r.min_exploration_level)
                     from public.standing_route_stops st
                     join public.ports po on po.id = st.port_id
                     join public.regions r on r.id = po.region_id
                    where st.route_id = sr.id), 1);
  if v_bad <> 0 then
    raise exception '0108 self-assert FAIL: % route(s) ask the wrong EXPLORATION for the regions they call at', v_bad;
  end if;
  -- THE LADDER IS NOT FLAT: the merchant roster spans more than one of each, or the column would
  -- print the same number beside every lane and say nothing.
  if (select count(distinct public.route_requirement(sr.id)->>'navigation') from public.standing_routes sr) < 2
     or (select count(distinct public.route_requirement(sr.id)->>'exploration') from public.standing_routes sr) < 2 then
    raise exception '0108 self-assert FAIL: every route in the world asks the same levels, so the column says nothing';
  end if;

  -- (d) THE BOARD, on a probe house, rolled back.
  select count(*) into v_base from public.players;
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_fnc from public.ports where code = 'FNC';
    v_leg := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                       jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                from public.sea_reaches a, public.sea_reaches b
               where a.port_id = v_lis and b.port_id = v_fnc);
    v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
    v_me := public.new_house(c_auth, 'Casa do Quadro Dois', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_me;
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fleet;
    v_route := (cmd.standing_route_save_for(v_me, null, 'A minha rota',
                  jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                    jsonb_build_object('port', 'FNC', 'course', v_back_c)),
                  null, null, 0)->>'id')::uuid;
    if v_route is null then
      raise exception '0108 self-assert FAIL: the probe route was not saved';
    end if;
    perform cmd.assume_identity(c_auth);
    perform public.npc_traders_switch(true);

    v_board := world.route_board();
    -- (d1) THE EXACT ROW KEY SET — 0106's, plus exactly these two.
    select x into v_row from jsonb_array_elements(v_board->'routes') x where (x->>'merchant')::boolean limit 1;
    v_keys := pg_temp.okeys_0108(v_row);
    if v_keys <> array['assigned', 'closed', 'company', 'earnings', 'id', 'ink', 'merchant', 'mine',
                       'name', 'nation_code', 'nm', 'regions', 'requires', 'state', 'stop_count', 'stops'] then
      raise exception '0108 self-assert FAIL: a route row''s keys %', v_keys;
    end if;
    if pg_temp.okeys_0108(v_row->'requires') <> array['exploration', 'navigation'] then
      raise exception '0108 self-assert FAIL: the requirement''s keys %', pg_temp.okeys_0108(v_row->'requires');
    end if;

    -- (d2) `closed` AGREES WITH THE GATE, on every row of the board. This is the whole licence for
    --      computing it from her levels instead of calling the gate per stop.
    select count(*) filter (where x.said is distinct from x.gated) into v_bad from (
      select (r->>'closed')::boolean as said,
             exists (select 1 from public.standing_route_stops st
                      where st.route_id = (r->>'id')::uuid
                        and public.passage_gate(v_me, st.course_nm, st.port_id) is not null) as gated
        from jsonb_array_elements(v_board->'routes') r) x;
    if v_bad <> 0 then
      raise exception '0108 self-assert FAIL: % row(s) disagree with public.passage_gate about being closed', v_bad;
    end if;
    select count(*) filter (where (r->>'closed')::boolean),
           count(*) filter (where not (r->>'closed')::boolean)
      into v_closed, v_open from jsonb_array_elements(v_board->'routes') r;
    if v_closed < 1 or v_open < 1 then
      raise exception '0108 self-assert FAIL: the board is all open or all shut (% closed, % open) — the flag says nothing',
        v_closed, v_open;
    end if;
    -- HER OWN SHORT LANE IS OPEN to her, which is what makes the flag readable at all.
    if (select (r->>'closed')::boolean from jsonb_array_elements(v_board->'routes') r
         where (r->>'id')::uuid = v_route) then
      raise exception '0108 self-assert FAIL: her own Lisbon-Funchal lane is shut to her';
    end if;

    -- (d3) POSITIVE CONTROL ON THE CAPTAIN, not on the route: study navigation and lanes OPEN,
    --      with not a stop moved. If they did not, `closed` would be about the route alone.
    select id into v_sk from public.skills where code = 'NAVIGATION';
    insert into public.player_skills (player_id, skill_id, level) values (v_me, v_sk, 5);
    select count(*) filter (where (r->>'closed')::boolean) into v_bad
      from jsonb_array_elements(world.route_board()->'routes') r;
    if v_bad >= v_closed then
      raise exception '0108 self-assert FAIL: NAVIGATION 5 shut as many lanes as before (% vs %)', v_bad, v_closed;
    end if;
    -- and it still agrees with the gate at the new level
    select count(*) filter (where x.said is distinct from x.gated) into v_bad from (
      select (r->>'closed')::boolean as said,
             exists (select 1 from public.standing_route_stops st
                      where st.route_id = (r->>'id')::uuid
                        and public.passage_gate(v_me, st.course_nm, st.port_id) is not null) as gated
        from jsonb_array_elements(world.route_board()->'routes') r) x;
    if v_bad <> 0 then
      raise exception '0108 self-assert FAIL: % row(s) disagree with the gate once she has studied', v_bad;
    end if;
    delete from public.player_skills where player_id = v_me and skill_id = v_sk;

    -- (d4) A MERCHANT'S LANE STILL PRINTS WHAT **YOU** WOULD NEED. The requirement is served for
    --      her rows precisely so a captain can read a carreira and see what it would take.
    if (select count(*) from jsonb_array_elements(v_board->'routes') r
         where (r->>'merchant')::boolean and (r->'requires'->>'navigation') is not null) < 1 then
      raise exception '0108 self-assert FAIL: no merchant lane prints a navigation requirement';
    end if;

    -- (d5) WHAT IT COSTS, now that every row carries two more derivations.
    v_t0 := clock_timestamp();
    for v_n in 1..10 loop perform world.route_board(); end loop;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 10, 2);
    if v_ms > 400 then
      raise exception '0108 self-assert FAIL: the board now takes % ms a call — the requirement is being measured, not read', v_ms;
    end if;

    raise exception 'ROLLBACK_0108';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0108' then raise; end if;
  end;

  if (select count(*) from public.players) <> v_base or public.npc_traders_on() then
    raise exception '0108 self-assert FAIL: the probe did not leave the world as it found it';
  end if;

  raise notice '0108 self-assert ok: THE BOARD PRINTS WHAT A LANE ASKS OF YOU. world.route_board is '
    'its 0106 pre-image plus only this file''s hunks and the two level readings they declare, ACL '
    'unmoved, and public.route_requirement is reachable by nobody. Over EVERY route in the world: '
    'the NAVIGATION asked is the smallest level whose reach covers the longest leg — that level''s '
    'reach covers it and one level less does not, on all of them — the EXPLORATION asked is the '
    'dearest region the loop calls at, re-derived off the stops, and both span more than one value '
    'across the roster, so the column is not the same number beside every lane. A route that does '
    'not exist asks nothing. On a probe house, rolled back: the row key set is 0106''s plus exactly '
    '`requires` and `closed`, and `closed` AGREES with public.passage_gate about every row of the '
    'board (% shut, % open — not all of one) with her own Lisbon-Funchal lane open to her. The '
    'positive control is on the CAPTAIN and not the route: NAVIGATION 5 OPENED lanes with not a stop '
    'moved, and the flag still agreed with the gate at the new level. A merchant''s lane prints what '
    'YOU would need, which is the point of serving it for her rows. The board takes % ms a call over '
    '10 calls — the requirement is READ off 0106''s stored leg lengths and 0107''s region levels, '
    'never measured again.',
    v_closed, v_open, v_ms;
end $$;
