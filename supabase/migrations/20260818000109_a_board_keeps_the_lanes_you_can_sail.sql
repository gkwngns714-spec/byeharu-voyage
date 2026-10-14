-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0109 — A BOARD KEEPS THE LANES YOU CAN SAIL
--        Owner row 123 (docs/OWNER_REQUESTS.md) — found by the ×10 roster, not asked for.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, AND HOW IT WAS MEASURED ─────────────────────────────────────────────────────────
-- 0106 caps the route board at `route_board_max` (400) and keeps, after the caller's own routes,
-- the LONGEST — on the argument that "a board of the world's trade that drops the India run and
-- keeps a coastal hop is not a board of the world's trade". That argument was made against 76
-- routes, where 400 was no cap at all and the order decided nothing.
--
-- 0105 founded 761 merchant companies over 219 loops. At 838 routes the order decides everything,
-- and 0108's own agreement assertion measured what it decides: **399 shut, 1 open** — the one open
-- lane being her own Lisbon-Funchal hop. A new captain opens ROUTES and reads four hundred
-- carreiras she cannot sail. Every lane she COULD sail is a short one, and short ones are exactly
-- what "the longest survive" throws away.
--
-- The gates are right (0107) and the flag that says a lane is shut is right (0108). The ORDER is
-- wrong, and it is wrong in a way nothing could have caught before the roster existed.
--
-- ── WHAT CHANGES, AND WHAT DOES NOT ─────────────────────────────────────────────────────────────
-- One clause. The cap now keeps, in this order:
--
--   1. HER OWN routes, always and whatever they measure — 0106's rule, unchanged. They are hers.
--   2. The lanes she CAN SAIL TODAY, longest first. This is the new rung.
--   3. The lanes she cannot, longest first — so the India run is still on the board when there is
--      room for it, which is what 0106's argument was actually protecting.
--
-- `total` and `omitted` are untouched, so the board still owns up to everything it held back; the
-- ROWS are untouched, key for key; and with fewer routes in the world than the cap NOTHING moves at
-- all — the same set is served, and only its order can differ. That last point is asserted below
-- against a shrunk world, because "no change when the new input is absent" is this chain's standing
-- requirement and a re-ordering is the easiest kind of change to make accidentally sweeping.
--
-- ── WHY THE REACH TEST MOVES INTO THE CTE ───────────────────────────────────────────────────────
-- 0108 computes `closed` in the row it builds, from the caller's two levels read once. The cap is
-- decided one step earlier, in `pick`'s `row_number()`, so the same comparison has to be available
-- there. It is the SAME comparison, written once and used twice — the ordering reads it and the
-- served `closed` key reads it — rather than two statements of "can she sail this" that could come
-- to disagree. 0108's assertion that `closed` agrees with `public.passage_gate` on every row of the
-- board still runs, and now covers the ordering too, because they are one expression.
--
-- ── WHAT THIS SUPERSEDES ────────────────────────────────────────────────────────────────────────
-- `world.route_board` (0106, re-cut by 0108) by one hunk on its `pick` CTE. The re-cut is proven
-- below to be its pre-image plus only that hunk with its ACL unmoved. Nothing else in the chain is
-- touched: no knob moves, no column is added, no other function is re-cut.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════


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

create temporary table hunks_0109 (fn text not null, n int not null, old text not null, new text not null);
create temporary table defs_before_0109 (fn text primary key, def text not null, acl text not null);

insert into hunks_0109 values
('world.route_board()', 1,
$h$    select r.*, row_number() over (order by r.mine desc, r.nm desc nulls last, r.name, r.id) as rk
      from r$h$,
$h$    -- 0109 (owner row 123): WHAT SHE CAN SAIL SURVIVES THE CAP. 0106 kept her own routes and then
    -- the longest, which decided nothing over 76 routes and decided everything over 838: measured
    -- at the full roster, a beginner's board was 399 lanes shut and 1 open. So the middle rung is
    -- new — hers, then what she can sail today longest-first, then the rest longest-first, which
    -- still leaves the India run on the board when there is room for it. `within` is the SAME
    -- comparison the served `closed` key is built from (0108), written once here and read twice, so
    -- the order and the flag cannot come to disagree.
    select r.*,
           not (coalesce((public.route_requirement(r.id)->>'navigation')::int, 1) > greatest(1, v_nav)
                or coalesce((public.route_requirement(r.id)->>'exploration')::int, 1) > v_exp) as within,
           row_number() over (order by r.mine desc,
                                       not (coalesce((public.route_requirement(r.id)->>'navigation')::int, 1) > greatest(1, v_nav)
                                            or coalesce((public.route_requirement(r.id)->>'exploration')::int, 1) > v_exp) desc,
                                       r.nm desc nulls last, r.name, r.id) as rk
      from r$h$);

insert into defs_before_0109
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', ''),
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '')
  from (select distinct fn from hunks_0109) as f(fn);

create or replace function pg_temp.recut_0109(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0109 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0109 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0109: hunk % of % matches the pre-image % time(s), not once', h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0109(fn) from (select distinct fn from hunks_0109) x order by fn;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0109-4000-8000-0000000000a1';
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
  v_world   int;
  v_open    int;
  v_shut    int;
  v_sk      uuid;
  v_before  jsonb;
  v_after   jsonb;
  v_bad     int;
  v_ctrl    int;   -- what 0106's own order would have capped off: the positive control's count
  v_ms      numeric;
  v_t0      timestamptz;
begin
  -- (a) THE BOARD IS ITS PRE-IMAGE PLUS ONLY THIS FILE'S ONE HUNK, ACL UNMOVED.
  for v_fn in select distinct fn from hunks_0109 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0109 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0109 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0109 where fn = v_fn) or v_def = v_back then
      raise exception '0109 self-assert FAIL: % is not its pre-image plus only 0109''s hunk', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0109 where fn = v_fn) then
      raise exception '0109 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0109 self-assert FAIL: the grant wall or the read wall';
  end if;

  -- (b) ON A PROBE HOUSE, AT THE FULL ROSTER, rolled back.
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
    v_me := public.new_house(c_auth, 'Casa da Escada', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_me;
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fleet;
    v_route := (cmd.standing_route_save_for(v_me, null, 'A minha rota',
                  jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                    jsonb_build_object('port', 'FNC', 'course', v_back_c)),
                  null, null, 0)->>'id')::uuid;
    perform cmd.assume_identity(c_auth);
    perform public.npc_traders_switch(true);

    v_board := world.route_board();
    v_world := (v_board->>'total')::int;
    select count(*) filter (where not (x->>'closed')::boolean),
           count(*) filter (where (x->>'closed')::boolean)
      into v_open, v_shut from jsonb_array_elements(v_board->'routes') x;

    -- (b1) THE WORLD IS BIG ENOUGH FOR THE CAP TO DECIDE ANYTHING. Without this the whole file is
    --      a no-op dressed as a fix, which is exactly what 0106's order was for five migrations.
    if v_world <= public.wc_int('route_board_max') then
      raise exception '0109 self-assert FAIL: the world holds % route(s) and the cap is % — the order decides nothing and nothing here is proven',
        v_world, public.wc_int('route_board_max');
    end if;

    -- (b2) EVERY LANE SHE CAN SAIL IS ON THE BOARD. The claim, stated as a count: there is no route
    --      in the world that she could sail and that the board left out. Re-derived off
    --      public.passage_gate — the authority — and not off the key the board served.
    select count(*) into v_bad from public.standing_routes sr
      join public.players p on p.id = sr.player_id
     where (sr.player_id = v_me or p.is_npc)
       and not exists (select 1 from public.standing_route_stops st
                        where st.route_id = sr.id
                          and public.passage_gate(v_me, st.course_nm, st.port_id) is not null)
       and not exists (select 1 from jsonb_array_elements(v_board->'routes') x
                        where (x->>'id')::uuid = sr.id);
    if v_bad <> 0 then
      raise exception '0109 self-assert FAIL: % lane(s) she can sail were capped off the board', v_bad;
    end if;
    -- ...and her own is on it, whatever it measures (0106's rule, still standing).
    if not exists (select 1 from jsonb_array_elements(v_board->'routes') x where (x->>'id')::uuid = v_route) then
      raise exception '0109 self-assert FAIL: her own route is not on the board';
    end if;

    -- (b3) THE ORDER IS THE ORDER THIS FILE CLAIMS: hers, then open longest-first, then shut
    --      longest-first. Checked as a monotonicity over the served array rather than by
    --      re-sorting it, so the assertion cannot accidentally restate the implementation.
    select count(*) into v_bad from (
      select (x->>'closed')::boolean as closed, (x->>'mine')::boolean as mine,
             row_number() over () as i
        from jsonb_array_elements(v_board->'routes') x) a
      join (
      select (x->>'closed')::boolean as closed, (x->>'mine')::boolean as mine,
             row_number() over () as i
        from jsonb_array_elements(v_board->'routes') x) b on b.i = a.i + 1
     where (a.mine < b.mine) or (a.mine = b.mine and a.closed > b.closed);
    if v_bad <> 0 then
      raise exception '0109 self-assert FAIL: the board is out of order in % place(s) — hers then open then shut', v_bad;
    end if;

    -- (b4) AND IT IS A REAL CHANGE: the 0106 order, re-derived here, would have left lanes she can
    --      sail OFF the board. This is the positive control, and the number is the defect row 123
    --      measured.
    select count(*) into v_ctrl from (
      select sr.id,
             row_number() over (order by (sr.player_id = v_me) desc,
                                         public.route_nm(sr.id) desc nulls last, sr.name, sr.id) as rk
        from public.standing_routes sr
        join public.players p on p.id = sr.player_id
       where sr.player_id = v_me or p.is_npc) old
     where old.rk > public.wc_int('route_board_max')
       and not exists (select 1 from public.standing_route_stops st
                        where st.route_id = old.id
                          and public.passage_gate(v_me, st.course_nm, st.port_id) is not null);
    if v_ctrl = 0 then
      raise exception '0109 self-assert FAIL: 0106''s own order would have capped off NO lane she can sail, so this file fixes nothing';
    end if;

    -- (b5) NOTHING MOVES IN A WORLD SMALLER THAN THE CAP. The standing requirement: with the new
    --      input absent — here, with no route beyond the cap — the same SET is served. 0106's
    --      promise about `total` and `omitted` is re-checked in the same breath.
    v_before := world.route_board();
    update public.world_config set value = to_jsonb(v_world + 10) where key = 'route_board_max';
    v_after := world.route_board();
    if (v_after->>'omitted')::int <> 0 or (v_after->>'total')::int <> v_world
       or jsonb_array_length(v_after->'routes') <> v_world then
      raise exception '0109 self-assert FAIL: with the cap above the world the board still held something back (% of %, omitted %)',
        jsonb_array_length(v_after->'routes'), v_after->>'total', v_after->>'omitted';
    end if;
    if (select count(*) from (
          select x->>'id' as id from jsonb_array_elements(v_after->'routes') x
          except
          select sr.id::text from public.standing_routes sr
            join public.players p on p.id = sr.player_id
           where sr.player_id = v_me or p.is_npc) q) <> 0 then
      raise exception '0109 self-assert FAIL: an uncapped board served a route the world does not hold';
    end if;

    -- (b6) STUDYING MOVES THE BOARD, which is the point of the middle rung: the same world, the
    --      same cap, a captain who has learned something, and MORE of what she can sail survives.
    update public.world_config set value = to_jsonb(400) where key = 'route_board_max';
    select id into v_sk from public.skills where code = 'NAVIGATION';
    insert into public.player_skills (player_id, skill_id, level) values (v_me, v_sk, 5);
    select count(*) filter (where not (x->>'closed')::boolean) into v_bad
      from jsonb_array_elements(world.route_board()->'routes') x;
    if v_bad <= v_open then
      raise exception '0109 self-assert FAIL: NAVIGATION 5 left the open count at % against % — the board does not follow her',
        v_bad, v_open;
    end if;
    delete from public.player_skills where player_id = v_me and skill_id = v_sk;

    -- (b7) WHAT IT COSTS, with the requirement now read in the ordering as well as the row.
    v_t0 := clock_timestamp();
    for v_n in 1..5 loop perform world.route_board(); end loop;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 5, 2);

    raise exception 'ROLLBACK_0109';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0109' then raise; end if;
  end;

  if (select count(*) from public.players) <> v_base
     or public.wc_int('route_board_max') <> 400
     or public.npc_traders_on() then
    raise exception '0109 self-assert FAIL: the probe did not leave the world as it found it';
  end if;

  raise notice '0109 self-assert ok: A BOARD KEEPS THE LANES YOU CAN SAIL. world.route_board is its '
    'pre-image plus only this file''s one hunk on the pick CTE, ACL unmoved, grant and read walls at '
    'zero. On a probe house at the FULL roster, rolled back: the world holds % route(s) against a cap '
    'of %, so the order decides something — which it did not when 0106 wrote it over 76. NOT ONE lane '
    'she can sail is capped off the board, re-derived off public.passage_gate itself rather than off '
    'the key the board served, and her own route is on it whatever it measures. The served array is '
    'monotone in the order this file claims — hers, then what she can sail longest-first, then what '
    'she cannot — checked as a walk over consecutive rows and not by re-sorting them. THE POSITIVE '
    'CONTROL: 0106''s own order, re-derived here, would have capped off % lane(s) she can sail, which '
    'is the defect row 123 measured (399 shut, 1 open). With the cap lifted above the world the same '
    'SET is served, nothing held back, no route invented — the no-op when the new input is absent. '
    'And the board FOLLOWS HER: NAVIGATION 5 left more open lanes on it than before, same world, same '
    'cap, not a stop moved. % ms a call over 5 calls at % route(s).',
    v_world, public.wc_int('route_board_max'), v_ctrl, v_ms, v_world;
end $$;
