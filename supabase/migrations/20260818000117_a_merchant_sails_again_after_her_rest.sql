-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0117 — A MERCHANT SAILS AGAIN THE MOMENT HER REST IS OVER, AND THE SEA IS READ IN TIME
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-14: remove the merchant lap pacing, so that the two-minute rest (0116) is the ONLY wait
-- at home.
--
-- ── WHAT WAS FOUND ──────────────────────────────────────────────────────────────────────────────
-- With 822 merchants sailing (0114-0116), world.sea_traffic — the live map's read — passed 30 s for
-- a 12°×8° window as `authenticated`, which has an 8 s statement timeout, so every map call
-- failed 57014. The read computed world.voyage_view (progress, waters ahead, position) and the
-- route lane for EVERY merchant fleet in its first CTE, and only then applied the window and the
-- sea_traffic_max cap.
-- (The first cut of this file re-saved all 837 routes through the save door in one long
-- transaction. That push was cancelled on prod before it committed; prod stayed at 0116.)
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) world.sea_traffic, by slices of its LIVE body (0111). Every fleet's whole course is read off
--     the frozen path (voyage.course_of, the course her served voyage is cut from). A fleet is a
--     CANDIDATE only if a point of that course, or the midpoint of two consecutive points, lies in
--     the padded window. That is an exact superset of the 0102 test, which samples her current
--     segment's two ends and midpoint. world.voyage_view is asked only of candidates (a window), or
--     only of the sea_traffic_max picked rows (the world view). public.route_lane is asked only of
--     picked rows. The output is the pre-image's to the byte, and the self-assert compares the two
--     over the live roster.
-- (2) A MERCHANT'S PACE IS THE KNOB. `npc_laps_per_game_day` goes from 6 to 0. docs/NPC_TRADERS.md
--     §4.2: 0 means she starts her next lap the moment she can. cmd.run_standing_route (sliced)
--     reads that knob for a merchant route instead of a per-route copy of it, so nothing is
--     re-saved and nothing waits on 837 writes. The 0101 rest floor is then her only wait at home.
--     A player's route keeps its own pace, else standing_route_laps_per_game_day.
--
-- SUPERSEDES (slices of the live bodies, each hunk asserted to occur exactly once):
-- world.sea_traffic (0111) and cmd.run_standing_route (0114).
-- Self-asserts hold AS FOUND (0113); the probes roll back.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

update public.world_config set value = to_jsonb(0),
       description = '0117: laps a merchant route may START per game-day — THE merchant pace (cmd.run_standing_route '
                     'reads it for every merchant route). 0: no pacing, so the 0101 rest at home '
                     '(route_rest_voyage_days) is her only wait between laps.'
 where key = 'npc_laps_per_game_day';

-- THE PRE-IMAGE of the read, kept under pg_temp so the self-assert compares rather than trusts.
do $$
declare
  v_def text := replace(pg_get_functiondef('world.sea_traffic(jsonb)'::regprocedure), E'\r', '');
begin
  if strpos(v_def, 'CREATE OR REPLACE FUNCTION world.sea_traffic(p_view jsonb DEFAULT NULL::jsonb)') <> 1 then
    raise exception '0117 self-assert FAIL: world.sea_traffic(jsonb) is not where this file expects it';
  end if;
  execute replace(v_def, 'CREATE OR REPLACE FUNCTION world.sea_traffic(p_view jsonb DEFAULT NULL::jsonb)',
                         'CREATE OR REPLACE FUNCTION pg_temp.traffic_before_0117(p_view jsonb DEFAULT NULL::jsonb)');
end $$;

create or replace function pg_temp.slice_0117(p_fn text, p_old text, p_new text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  v_n   int  := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
begin
  if v_n <> 1 then
    raise exception '0117 self-assert FAIL: a hunk of % occurs % time(s), not once — the live body is not what this file was cut against: %',
      p_fn, v_n, left(p_old, 120);
  end if;
  execute replace(v_def, p_old, p_new);
end $$;

select pg_temp.slice_0117('world.sea_traffic(jsonb)',
$h$           (select world.voyage_view(v.id, false) from public.voyages v
             where v.fleet_id = f.id and v.status = 'SAILING') as vv,
           -- HER LANE (owner row 125, 0111). Read HERE, in the one CTE that already gathers a
           -- fleet's per-row facts, so it is asked once per fleet and not once per mention — which
           -- is the whole of what 0110 had to go back and fix on the route board. The threshold is
           -- tested in SQL rather than inside route_lane so a fleet below it costs not even a call.
           case when (select count(*) from public.ships s where s.fleet_id = f.id)
                     >= greatest(1, public.wc_int('fleet_lane_min_ships'))
                then public.route_lane(nf.route_id) end as lane
$h$,
$h$           -- 0117: ONLY WHERE SHE IS, HERE. Her whole course read off the frozen path (the very
           -- `course` her served voyage is cut from); the served voyage itself and her lane are
           -- asked below, only for the fleets the window can keep.
           (select v.id from public.voyages v
             where v.fleet_id = f.id and v.status = 'SAILING') as voyage_id,
           (select voyage.course_of(v.path) from public.voyages v
             where v.fleet_id = f.id and v.status = 'SAILING') as course,
           nf.route_id
$h$);
select pg_temp.slice_0117('world.sea_traffic(jsonb)',
$h$  ), pts as (
$h$,
$h$  ), cand as (
    -- 0117: THE FLEETS THE WINDOW CAN KEEP — A SUPERSET, EXACTLY. The test below samples her
    -- CURRENT segment: its two ends and its short-way midpoint. Both ends are points of her whole
    -- course, and the midpoint is the midpoint of two consecutive points of it, computed by the
    -- same expression. So any course point or consecutive midpoint inside the padded window keeps
    -- every fleet the test can keep, and the dear served voyage is asked of nobody else. A fleet in
    -- port is always a candidate (her test is a roadstead, which costs nothing). The world view
    -- (p_view null) keeps everyone and reads her voyage only once she is picked.
    select m.* from m
     where p_view is null or m.voyage_id is null
        or exists (
             select 1
               from jsonb_array_elements(m.course) with ordinality c(pt, i)
              where ((c.pt->>0)::double precision between v_s - v_pad and v_n + v_pad
                     and public.lon_in_view((c.pt->>1)::double precision, v_w - v_pad, v_e + v_pad))
                 or (m.course->(c.i::int) is not null
                     and ((c.pt->>0)::double precision + (m.course->(c.i::int)->>0)::double precision) / 2
                         between v_s - v_pad and v_n + v_pad
                     and public.lon_in_view(voyage.lon_lerp((c.pt->>1)::double precision,
                                                            (m.course->(c.i::int)->>1)::double precision, 0.5),
                                            v_w - v_pad, v_e + v_pad)))
  ), mv as (
    select cand.*,
           case when p_view is not null and cand.voyage_id is not null
                then world.voyage_view(cand.voyage_id, false) end as vv
      from cand
  ), pts as (
$h$);
select pg_temp.slice_0117('world.sea_traffic(jsonb)',
$h$      from m
      cross join lateral (
$h$,
$h$      from mv m   -- 0117
      cross join lateral (
$h$);
select pg_temp.slice_0117('world.sea_traffic(jsonb)',
$h$      from m
      left join near on near.fleet_id = m.fleet_id
$h$,
$h$      from mv m   -- 0117
      left join near on near.fleet_id = m.fleet_id
$h$);
select pg_temp.slice_0117('world.sea_traffic(jsonb)',
$h$           'voyage', pick.vv,
$h$,
$h$           -- 0117: read in the window's pass for a candidate, or here once she is picked.
           'voyage', case when pick.voyage_id is null then null
                          when p_view is not null then pick.vv
                          else world.voyage_view(pick.voyage_id, false) end,
$h$);
select pg_temp.slice_0117('world.sea_traffic(jsonb)',
$h$           'lane', pick.lane,
$h$,
$h$           'lane', case when pick.ships >= greatest(1, public.wc_int('fleet_lane_min_ships'))
                        then public.route_lane(pick.route_id) end,   -- 0117: picked rows only
$h$);
select pg_temp.slice_0117('cmd.run_standing_route(uuid, timestamptz)',
$h$      v_per := coalesce(sr.laps_per_game_day, public.wc_int('standing_route_laps_per_game_day'));
$h$,
$h$      -- 0117: A MERCHANT'S PACE IS THE KNOB, not a copy of it on each of 837 routes:
      -- npc_laps_per_game_day (0 = none; her rest at home is the only wait). A player's route keeps
      -- its own pace, else standing_route_laps_per_game_day.
      v_per := case when v_npc then public.wc_int('npc_laps_per_game_day')
                    else coalesce(sr.laps_per_game_day, public.wc_int('standing_route_laps_per_game_day')) end;
$h$);

revoke all on function world.sea_traffic(jsonb) from public, anon;
grant execute on function world.sea_traffic(jsonb) to authenticated;

do $$
declare
  v_was_on  boolean := public.npc_traders_on();
  v_routes_on boolean := public.standing_routes_on();
  v_view    jsonb := '{"south":34,"north":42,"west":-14,"east":-2}'::jsonb;
  v_t0      timestamptz;
  v_old_ms  numeric;
  v_new_ms  numeric;
  v_old     jsonb;
  v_new     jsonb;
  v_rows    int;
begin
  -- (a) THE KNOB, and the executor reads it for merchants.
  if public.wc_int('npc_laps_per_game_day') <> 0
     or position($q$when v_npc then public.wc_int('npc_laps_per_game_day')$q$
                 in pg_get_functiondef('cmd.run_standing_route(uuid, timestamptz)'::regprocedure)) = 0 then
    raise exception '0117 self-assert FAIL: the merchant pace is not the knob, at 0';
  end if;
  -- (b) THE WALL DID NOT MOVE.
  if not has_function_privilege('authenticated', 'world.sea_traffic(jsonb)', 'execute')
     or has_function_privilege('anon', 'world.sea_traffic(jsonb)', 'execute') then
    raise exception '0117 self-assert FAIL: world.sea_traffic is not exactly authenticated-only';
  end if;
  -- (c) THE READ IS ITS PRE-IMAGE TO THE BYTE, lit, over the live roster — a window and the world.
  --     voyage_view is no longer asked of a fleet the window drops.
  if position('voyage_view' in split_part(pg_get_functiondef('world.sea_traffic(jsonb)'::regprocedure), '), cand as (', 1)) > 0 then
    raise exception '0117 self-assert FAIL: sea_traffic still reads her voyage for every fleet before the window';
  end if;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    v_t0 := clock_timestamp(); v_new := world.sea_traffic(v_view); v_new_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
    v_t0 := clock_timestamp(); v_old := pg_temp.traffic_before_0117(v_view); v_old_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
    v_rows := jsonb_array_length(v_new->'fleets');
    if v_new is distinct from v_old then
      raise exception '0117 self-assert FAIL: the window read differs from its pre-image';
    end if;
    -- @@WORLD_PARITY@@
    if world.sea_traffic(null) is distinct from pg_temp.traffic_before_0117(null) then
      raise exception '0117 self-assert FAIL: the world read differs from its pre-image';
    end if;
    raise exception 'ROLLBACK_0117';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0117' then raise; end if;
  end;
  if public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on then
    raise exception '0117 self-assert FAIL: the switch was not left as found';
  end if;

  raise notice '0117 self-assert ok: A MERCHANT SAILS AGAIN THE MOMENT HER REST IS OVER. npc_laps_per_game_day 0, '
    'read by the executor for every merchant route; sea_traffic answers its pre-image to the byte (a 12x8 window, '
    '% row(s): % ms against % ms before; and the whole world). Switch as found (%).',
    v_rows, round(v_new_ms), round(v_old_ms), case when v_was_on then 'lit' else 'dark' end;
end $$;
