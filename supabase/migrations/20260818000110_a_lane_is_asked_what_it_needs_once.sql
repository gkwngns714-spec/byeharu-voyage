-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0110 — A LANE IS ASKED WHAT IT NEEDS ONCE
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE MEASUREMENT THIS FILE EXISTS FOR ────────────────────────────────────────────────────────
-- 0106 got the route board down to 10.4 ms a call by moving the distance measure to the write. 0108
-- added the level requirement to every row and 0109 added it to the cap's ordering, and 0109's own
-- timing line says what that cost: **256.80 ms a call over 5 calls at 838 route(s)**. Twenty-five
-- times slower, on a read the ROUTES screen re-asks on the world's beat for as long as it is open.
--
-- Nothing is wrong with the figure or the rule. `public.route_requirement(route)` is simply CALLED
-- THREE TIMES for every row — once for the served `requires` key, and twice more inside the
-- ordering expression, which repeats it for `navigation` and for `exploration`. At 838 rows that is
-- some two and a half thousand calls, each a pair of aggregates over that route's stops, to answer
-- a question whose answer cannot change between the three asks.
--
-- ── WHAT CHANGES ────────────────────────────────────────────────────────────────────────────────
-- The requirement is asked ONCE PER ROW, in the `r` CTE beside the other per-route readings, and
-- the three places that wanted it read that column. One hunk on `r`, one on `pick`, one on the row.
--
-- The answers do not move — the same function on the same route in the same statement — and that is
-- asserted rather than assumed: the board is read before and after, and every row's `requires`,
-- `closed`, `nm` and ORDER must come back byte-identical, which is a stronger claim than "it is
-- faster". A re-cut that changes an answer while making a number look better is the worst kind, so
-- the number is reported last and the identity first.
--
-- ── WHAT THIS SUPERSEDES ────────────────────────────────────────────────────────────────────────
-- `world.route_board` (0106, re-cut by 0108 and 0109) by three hunks, all of them inside its own
-- body: the `r` CTE gains the reading, `pick`'s ordering reads the column, and the served row reads
-- the column. Proven below to be its pre-image plus only those hunks, ACL unmoved. No knob moves,
-- no column is added, no other function is touched, and `public.route_requirement` itself is
-- unchanged — this file moves WHERE it is called and nothing about WHAT it says.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create temporary table hunks_0110 (fn text not null, n int not null, old text not null, new text not null);
create temporary table defs_before_0110 (fn text primary key, def text not null, acl text not null);

insert into hunks_0110 values
-- (i) ASKED ONCE, in the CTE that already gathers everything else a route is.
('world.route_board()', 1,
$h$           public.standing_route_state(sr.id, case when p.is_npc then v_on else true end) as state,
           public.route_earnings(sr.id) as earnings$h$,
$h$           public.standing_route_state(sr.id, case when p.is_npc then v_on else true end) as state,
           public.route_earnings(sr.id) as earnings,
           -- 0110: ONCE. 0108 asked this for the served key and 0109 asked it twice more inside the
           -- cap's ordering; at 838 routes that was ~2,500 calls a read for an answer that cannot
           -- change between them, and the board went from 10.4 ms a call to 256.8.
           public.route_requirement(sr.id) as requires$h$),
-- (ii) THE ORDERING READS THE COLUMN.
('world.route_board()', 2,
$h$    select r.*,
           not (coalesce((public.route_requirement(r.id)->>'navigation')::int, 1) > greatest(1, v_nav)
                or coalesce((public.route_requirement(r.id)->>'exploration')::int, 1) > v_exp) as within,
           row_number() over (order by r.mine desc,
                                       not (coalesce((public.route_requirement(r.id)->>'navigation')::int, 1) > greatest(1, v_nav)
                                            or coalesce((public.route_requirement(r.id)->>'exploration')::int, 1) > v_exp) desc,
                                       r.nm desc nulls last, r.name, r.id) as rk
      from r$h$,
$h$    select r.*,
           not (coalesce((r.requires->>'navigation')::int, 1) > greatest(1, v_nav)
                or coalesce((r.requires->>'exploration')::int, 1) > v_exp) as within,
           row_number() over (order by r.mine desc,
                                       not (coalesce((r.requires->>'navigation')::int, 1) > greatest(1, v_nav)
                                            or coalesce((r.requires->>'exploration')::int, 1) > v_exp) desc,
                                       r.nm desc nulls last, r.name, r.id) as rk
      from r$h$),
-- (iii) AND SO DOES THE ROW.
('world.route_board()', 3,
$h$           'requires', public.route_requirement(pick.id),$h$,
$h$           'requires', pick.requires,$h$),
('world.route_board()', 4,
$h$           'closed', coalesce((public.route_requirement(pick.id)->>'navigation')::int, 1) > greatest(1, v_nav)
                     or coalesce((public.route_requirement(pick.id)->>'exploration')::int, 1) > v_exp,$h$,
$h$           'closed', not pick.within,$h$);

insert into defs_before_0110
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', ''),
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '')
  from (select distinct fn from hunks_0110) as f(fn);

-- THE ANSWER BEFORE THE CHANGE, from the body about to be replaced, so "nothing moved" is measured
-- and not believed. Cloned into pg_temp exactly as 0102 cloned sea_traffic.
do $$
declare
  v_def text := replace(pg_get_functiondef('world.route_board()'::regprocedure), E'\r', '');
begin
  execute replace(v_def, 'CREATE OR REPLACE FUNCTION world.route_board()',
                         'CREATE OR REPLACE FUNCTION pg_temp.board_before_0110()');
end $$;

create or replace function pg_temp.recut_0110(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0110 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0110 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0110: hunk % of % matches the pre-image % time(s), not once', h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0110(fn) from (select distinct fn from hunks_0110) x order by fn;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0110-4000-8000-0000000000a1';
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
  v_before  jsonb;
  v_after   jsonb;
  v_world   int;
  v_calls   int;
  v_t0      timestamptz;
  v_ms_old  numeric;
  v_ms_new  numeric;
  v_sk      uuid;
begin
  -- (a) THE BOARD IS ITS PRE-IMAGE PLUS ONLY THIS FILE'S HUNKS, ACL UNMOVED.
  for v_fn in select distinct fn from hunks_0110 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0110 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0110 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0110 where fn = v_fn) or v_def = v_back then
      raise exception '0110 self-assert FAIL: % is not its pre-image plus only 0110''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0110 where fn = v_fn) then
      raise exception '0110 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;
  -- AND IT IS ASKED ONCE: the deployed body names route_requirement exactly once now, where it
  -- named it four times. A count, because "once" is the whole claim of this file.
  v_calls := (length(pg_get_functiondef('world.route_board()'::regprocedure))
              - length(replace(pg_get_functiondef('world.route_board()'::regprocedure),
                               'public.route_requirement(', '')))
             / length('public.route_requirement(');
  if v_calls <> 1 then
    raise exception '0110 self-assert FAIL: the board names public.route_requirement % time(s), not once', v_calls;
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0110 self-assert FAIL: the grant wall or the read wall';
  end if;

  -- (b) THE ANSWER DID NOT MOVE, and only then is it faster. On a probe house at the full roster.
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
    v_me := public.new_house(c_auth, 'Casa de Uma Vez', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_me;
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fleet;
    v_route := (cmd.standing_route_save_for(v_me, null, 'A minha rota',
                  jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                    jsonb_build_object('port', 'FNC', 'course', v_back_c)),
                  null, null, 0)->>'id')::uuid;
    perform cmd.assume_identity(c_auth);
    perform public.npc_traders_switch(true);

    -- BYTE FOR BYTE, ROW FOR ROW, IN THE SAME ORDER — the old body against the new one. `at` is
    -- the only key that may differ, and it is now(), which is the same inside one transaction
    -- anyway; it is struck out rather than relied on.
    v_before := pg_temp.board_before_0110();
    v_after  := world.route_board();
    if (v_after - 'at') is distinct from (v_before - 'at') then
      raise exception '0110 self-assert FAIL: the board''s answer MOVED. before % row(s), after % row(s); first disagreement at %',
        jsonb_array_length(v_before->'routes'), jsonb_array_length(v_after->'routes'),
        coalesce((select min(i) from generate_series(0, jsonb_array_length(v_after->'routes') - 1) i
                   where v_after->'routes'->i is distinct from v_before->'routes'->i)::text, '(top level)');
    end if;
    v_world := (v_after->>'total')::int;
    if v_world <= public.wc_int('route_board_max') then
      raise exception '0110 self-assert FAIL: the world holds % route(s) against a cap of % — nothing here is measured at scale',
        v_world, public.wc_int('route_board_max');
    end if;

    -- AND IT STILL MOVES WITH HER, so the identity above is not the identity of two frozen things:
    -- one skill row, and both bodies must agree on the NEW answer too.
    select id into v_sk from public.skills where code = 'NAVIGATION';
    insert into public.player_skills (player_id, skill_id, level) values (v_me, v_sk, 5);
    if (world.route_board() - 'at') is distinct from (pg_temp.board_before_0110() - 'at') then
      raise exception '0110 self-assert FAIL: the two bodies disagree once she has studied';
    end if;
    if (world.route_board() - 'at') is not distinct from (v_after - 'at') then
      raise exception '0110 self-assert FAIL: NAVIGATION 5 changed nothing, so the comparison above compared two frozen boards';
    end if;
    delete from public.player_skills where player_id = v_me and skill_id = v_sk;

    -- (c) ONLY NOW, THE NUMBER. Both bodies timed in the same transaction on the same world, so the
    --     figure is a comparison and not a boast about a machine.
    v_t0 := clock_timestamp();
    for v_n in 1..5 loop perform pg_temp.board_before_0110(); end loop;
    v_ms_old := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 5, 2);
    v_t0 := clock_timestamp();
    for v_n in 1..5 loop perform world.route_board(); end loop;
    v_ms_new := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 5, 2);
    if v_ms_new >= v_ms_old then
      raise exception '0110 self-assert FAIL: asking once took % ms against % ms for asking four times — the point of this file is unproven',
        v_ms_new, v_ms_old;
    end if;

    raise exception 'ROLLBACK_0110';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0110' then raise; end if;
  end;

  if (select count(*) from public.players) <> v_base or public.npc_traders_on() then
    raise exception '0110 self-assert FAIL: the probe did not leave the world as it found it';
  end if;

  raise notice '0110 self-assert ok: A LANE IS ASKED WHAT IT NEEDS ONCE. world.route_board is its '
    'pre-image plus only this file''s four hunks, ACL unmoved, walls at zero, and the deployed body '
    'now names public.route_requirement EXACTLY ONCE where it named it four times. On a probe house '
    'at the full roster of % route(s) against a cap of %, rolled back: the old body and the new one '
    'answer BYTE FOR BYTE the same board — every row, every key, in the same order — and they still '
    'agree after she studies NAVIGATION 5, which also proves the comparison was not two frozen '
    'boards. Only then the number, both bodies timed in the same transaction on the same world: '
    '% ms a call asking once, against % ms asking four times.',
    v_world, public.wc_int('route_board_max'), v_ms_new, v_ms_old;
end $$;
