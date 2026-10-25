-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0218 — THERE IS NO REGION DOOR  (owner row 204: "remove the region door, let me sail anywhere" — every harbour
--        is open to every house and every merchant as far as regions go; the leg's length, the stores, the money
--        and the sea conditions (0215/0216, dark) are the rules that remain, exactly as they are)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, 2026-10-25 (docs/OWNER_REQUESTS.md row 204) ──────────────────────────────────────
--   "remove the region door, let me sail anywhere"
--   This REVERSES the region-unlock default of 0107 ("the ocean is earned at the academy") and of the sea design's
--   S2b (docs/SEA_CONDITIONS_AND_REGIONS.md: the door was to go at the flip). It goes now, dark, and nothing is
--   left behind it (docs/NO_SPAGHETTI.md): not a bypass, not a column, not a knob, not a word on the client.
--
-- ── WHAT THE DOOR WAS, NAMED (docs/COMMAND_REDESIGN.md §1a, row 1 — the top cause of "I can't reach places") ──
--   regions.min_exploration_level (0107:122; 1 + floor(sailed nm from Lisbon / 2,500), capped at 5) against
--   public.exploration_reach(player) (0112:115), refused as E_REGION_CLOSED by public.passage_gate (0107:270,
--   0112 hunk 1, kept as the DARK path by 0216 hunk 2). Every harbour was asked it by voyage.reach_passage (0188,
--   0205's one-door-a-region CTE, 0216), so the Plan's board, the quay and the standing-route writer all shut the
--   same 126 of 237 harbours to a Lisbon starter (measured, COMMAND_REDESIGN §1a: a level-1 house reached 111).
--   The route board printed it as `requires.exploration` (0108's public.route_requirement) and shut a lane by it
--   (`closed`, 0108/0110/0112). The client said "needs exploration N" / "Nav N · Exp N" (RoutesScreen) and had a
--   sentence for E_REGION_CLOSED (dict/codes.ts). All of that is cut in this slice (client in the same PR).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   (1) public.passage_gate(uuid, uuid, numeric, uuid, jsonb): the dark region-door block is CUT (3 hunks: its three
--       declared figures, the header comment, the block itself). Dark, the gate is the leg's length alone; lit, the
--       sea gate as 0216 wrote it. Merchants and nobody stay exempt (0107 d4) — nothing there changes.
--   (2) voyage.reach_passage(uuid, uuid, uuid): 0205's `door` CTE is CUT (3 hunks: the header comment, the CTE, the
--       0216 note): dark, every harbour is open and the only gate is the leg; lit, 0216's zone reading of v_open is
--       untouched. The dark passage table no longer calls passage_gate at all.
--   (3) public.route_requirement(uuid): the `exploration` key is CUT (2 hunks); a lane asks {navigation} alone.
--   (4) world.route_board(): `closed` and the ordering read navigation alone (3 hunks); the exploration reading goes.
--   (5) DROP public.exploration_reach(uuid), DROP COLUMN regions.min_exploration_level, DELETE the two knobs
--       region_level_nm_step and region_level_max from world_config — after the self-assert, which still needs the
--       pre-images to run. Nothing in the chain reads them afterwards: asserted over every live body.
--
-- ── WHAT IT KEEPS, ON PURPOSE ───────────────────────────────────────────────────────────────────
--   The EXPLORATION track itself (0069 player_progress: fame, level, ports reached, nm sailed) — it drives rank,
--   the You tab and the captains; only its use as a door is cut. The 1,700 nm leg (public.passage_reach_nm, 0188).
--   Supplies and endurance (voyage.sail_refusal). The sea conditions (0215/0216), dark. The route board's `regions`
--   count (informational). 0107's E_LEG_TOO_FAR.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
--   CREATE OR REPLACE ×4 by hunks; one DROP FUNCTION; one ALTER TABLE ... DROP COLUMN on public.regions (25 rows,
--   an AccessExclusiveLock for milliseconds, lock_timeout 5 s); a DELETE of two config rows. The probe company is
--   made in a sub-transaction rolled back whole.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0217, LF-normalised, each asserted to occur exactly
-- once and to reverse to its pre-image, ACL / volatility / definer / config / owner unchanged):
--   public.passage_gate(uuid,uuid,numeric,uuid,jsonb) (3 hunks), voyage.reach_passage(uuid,uuid,uuid) (3),
--   public.route_requirement(uuid) (2), world.route_board() (3).
--
-- SELF-ASSERT (own probe rows, rolled back): a level-1 house at Lisbon (a barca, NAVIGATION as founded): the passage
-- table from Lisbon loses no harbour and no mile against its pre-image and GAINS harbours, every one of them in a
-- region whose former level was above 1; a harbour of the FORMER TOP LEVEL is reached by legs, and the gate answers
-- null for it where the pre-image said E_REGION_CLOSED (the positive control), with the passage's longest leg named
-- and with none; the sail door for it says neither E_REGION_CLOSED nor E_LEG_TOO_FAR; a 999,999 nm leg is still
-- E_LEG_TOO_FAR (the leg rule stands); a merchant is exempt before and after. For EVERY human of the world, from
-- where her first fleet lies: nothing lost, nothing longer. The route board: same lanes, `requires` is {navigation}
-- on every row, no lane shut now that was open before, `closed` equal to the navigation rule on
-- every row (0109's cap ranks sailable lanes first, so the shut count is reported, not required). Timed 6 + 6 calls of
-- reach_passage and of passage_gate in this session. Then, after the drops: no live body in cmd/voyage/world/public
-- names E_REGION_CLOSED, min_exploration_level or exploration_reach; the column, the function and the knobs are
-- gone; the walls hold; the registry is unmoved.
-- ROLLBACK (forward migration): reverse the hunks (each OLD text is here verbatim), recreate public.exploration_reach
-- from 0112 §2, re-add the column and re-derive it as 0107 §2 does, re-insert the two knobs (0107 §1).
-- VERSION: 0218 (renumber to the prod head + 1 at push; applies on 0217).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0218(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table t0_0218 on commit drop as select clock_timestamp() as t0;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0218 on commit drop as
select f.ord, f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values (1, 'public.passage_gate(uuid,uuid,numeric,uuid,jsonb)'),
               (2, 'voyage.reach_passage(uuid,uuid,uuid)'),
               (3, 'public.route_requirement(uuid)'),
               (4, 'world.route_board()')) f(ord, fn);

create temp table before_0218 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.regions) as regions;

-- the former door, kept for the self-assert (the column goes in §4)
create temp table former_0218 on commit drop as
select r.id as region_id, r.min_exploration_level as lvl from public.regions r;

create temp table hunks_0218 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0218 values
-- ── public.passage_gate: the door's three figures, its header, its block ──
('public.passage_gate(uuid,uuid,numeric,uuid,jsonb)', 1,
$h$  v_reach   numeric;
  v_level   int;
  v_need    int;
  v_region  text;
begin
$h$,
$h$  v_reach   numeric;
begin
$h$),
('public.passage_gate(uuid,uuid,numeric,uuid,jsonb)', 2,
$h$-- Two gates, and both read what playing has already earned rather than a stored counter:
--   the LENGTH of the leg against nav_leg_nm_base x 2^(NAVIGATION-1);
--   the DESTINATION's region against her EXPLORATION level.
-- A destination that is not a harbour has no region and is gated on length alone — open water
-- belongs to nobody, which is the same ruling 0047 made about draft and ice.
$h$,
$h$-- One gate, and it reads what playing has already earned rather than a stored counter: the LENGTH
-- of the leg against nav_leg_nm_base x 2^(NAVIGATION-1). 0218 (owner row 204, "remove the region
-- door, let me sail anywhere") cut the second gate: no harbour asks an exploration level any more.
$h$),
('public.passage_gate(uuid,uuid,numeric,uuid,jsonb)', 3,
$h$  -- 0216 (docs/SEA_CONDITIONS_AND_REGIONS.md, S2): WHILE THE SEA CONDITIONS BITE, the destination's waters and the
  -- course's are asked of the one rule (public.sea_gate: her title, her fleet's wave resistance, the zones) and the
  -- 0107 region door below is never read — the zone table is the one authority for "is this place open to her".
  -- Dark, the body below is the pre-image to the character (the region door goes with its column in the slice
  -- after the switch is lit).
  if public.sea_conditions_on() then
    return public.sea_gate(p_player, p_fleet, p_dest, p_course);
  end if;

  if p_dest is not null then
    select r.name, r.min_exploration_level into v_region, v_need
      from public.ports po join public.regions r on r.id = po.region_id
     where po.id = p_dest and po.kind = 'HARBOUR';
    if v_need is not null then
      -- 0112: the region she is already in, or has already made harbour in, is never shut to her.
      v_level := public.exploration_reach(p_player);
      if v_level < v_need then
        return cmd.refusal('E_REGION_CLOSED',
                 format('%s asks exploration level %s and yours is %s — sail farther first',
                        v_region, v_need, v_level),
                 jsonb_build_object('needs', v_need, 'has', v_level, 'region', v_region));
      end if;
    end if;
  end if;
$h$,
$h$  -- 0216 (docs/SEA_CONDITIONS_AND_REGIONS.md, S2): WHILE THE SEA CONDITIONS BITE, the destination's waters and the
  -- course's are asked of the one rule (public.sea_gate: her title, her fleet's wave resistance, the zones).
  -- 0218 (owner row 204): dark, there is no second gate — the leg's length above is the whole answer. The region
  -- door of 0107/0112 (a level each region asked of her exploration) is gone with its column.
  if public.sea_conditions_on() then
    return public.sea_gate(p_player, p_fleet, p_dest, p_course);
  end if;
$h$),
-- ── voyage.reach_passage: the header, 0205's door CTE, 0216's note on it ──
('voyage.reach_passage(uuid,uuid,uuid)', 1,
$h$-- open when it is no longer than public.passage_reach_nm and the harbour it ends at is open to her
-- (public.passage_gate's region check, asked of passage_gate). Dijkstra, O(n²) over the harbours, float8 arrays
$h$,
$h$-- open when it is no longer than public.passage_reach_nm (0218, owner row 204: no harbour is shut by its region
-- any more; lit, the sea conditions below still shut a leg). Dijkstra, O(n²) over the harbours, float8 arrays
$h$),
('voyage.reach_passage(uuid,uuid,uuid)', 2,
$h$  -- 0205: THE REGION DOOR ASKED ONCE A REGION, not once a harbour. With no leg length named, passage_gate's
  -- answer for a harbour is its region's door against her exploration (0107, 0112), the same for every harbour
  -- of that region; each ask re-derived her exploration from her record (~1.7 ms × 238 on prod). The gate is
  -- still the one asked, of each region's first harbour.
  with door as materialized (
    select h.region_id, public.passage_gate(p_player, p_fleet, null, h.id, null) is null as open   -- 0216: lit, the harbour's own zone
      from (select distinct on (p.region_id) p.region_id, p.id
              from public.ports p where p.kind = 'HARBOUR' order by p.region_id, p.code) h
  )
  select array_agg(p.id order by p.code), array_agg(p.code order by p.code),
         array_agg(p.id = p_from
                   or coalesce((select d.open from door d where d.region_id is not distinct from p.region_id), true)
                   order by p.code)
    into v_ids, v_codes, v_open
    from public.ports p
   where p.kind = 'HARBOUR' or p.id = p_from;
$h$,
$h$  -- 0218 (owner row 204): NO REGION DOOR. Dark, every harbour is open to her and the leg's length is the only
  -- gate; lit, 0216 below re-reads v_open from each harbour's own zone (public.sea_leg_asks).
  select array_agg(p.id order by p.code), array_agg(p.code order by p.code),
         array_agg(true order by p.code)
    into v_ids, v_codes, v_open
    from public.ports p
   where p.kind = 'HARBOUR' or p.id = p_from;
$h$),
('voyage.reach_passage(uuid,uuid,uuid)', 3,
$h$    -- and a HARBOUR is open by its own zone (the self row of sea_leg_asks is exactly that), not by its region's first
    -- harbour: 0205's one-door-a-region shortcut holds for the region door, not for the sea (Funchal is home water in
    -- a region whose first harbour by code is the Azores).
$h$,
$h$    -- and a HARBOUR is open by its own zone (the self row of sea_leg_asks is exactly that); dark, v_open above is
    -- all true (0218: there is no region door).
$h$),
-- ── public.route_requirement: {navigation} alone ──
('public.route_requirement(uuid)', 1,
$h$  -- 0108 (owner row 117): {navigation, exploration} — the levels this loop asks of ANY captain, the
  -- inverse of public.passage_gate's "may she sail this leg". Both from figures already stored:
  -- 0106's course_nm per stop and 0107's min_exploration_level per region. NAVIGATION is null when
  -- any leg is unmeasured, because a requirement nobody can state is an absence and not a 1.
$h$,
$h$  -- 0108 (owner row 117): {navigation} — the level this loop asks of ANY captain, the inverse of
  -- public.passage_gate's "may she sail this leg", from 0106's stored course_nm per stop. NAVIGATION
  -- is null when any leg is unmeasured, because a requirement nobody can state is an absence and not
  -- a 1. 0218 (owner row 204) cut `exploration` with the region door.
$h$),
('public.route_requirement(uuid)', 2,
$h$          from public.standing_route_stops st where st.route_id = p_route),
      'exploration', coalesce((
        select max(r.min_exploration_level)
          from public.standing_route_stops st
          join public.ports po on po.id = st.port_id
          join public.regions r on r.id = po.region_id
         where st.route_id = p_route), 1))
$h$,
$h$          from public.standing_route_stops st where st.route_id = p_route))
$h$),
-- ── world.route_board: `closed` and the order read navigation alone ──
('world.route_board()', 1,
$h$  v_nav   int;     -- 0108: the caller's own NAVIGATION, read once
  v_exp   int;     -- 0108: ...and her EXPLORATION level
$h$,
$h$  v_nav   int;     -- 0108: the caller's own NAVIGATION, read once (0218: the one level a lane asks)
$h$),
('world.route_board()', 2,
$h$  v_exp := public.exploration_reach(v_me);   -- 0112: the gate's own reading, so `closed` agrees
$h$,
$h$  -- 0218 (owner row 204): no exploration is read — the region door is gone; a lane asks navigation alone
$h$),
('world.route_board()', 3,
$h$    select r.*,
           not (coalesce((r.requires->>'navigation')::int, 1) > greatest(1, v_nav)
                or coalesce((r.requires->>'exploration')::int, 1) > v_exp) as within,
           row_number() over (order by r.mine desc,
                                       not (coalesce((r.requires->>'navigation')::int, 1) > greatest(1, v_nav)
                                            or coalesce((r.requires->>'exploration')::int, 1) > v_exp) desc,
                                       r.nm desc nulls last, r.name, r.id) as rk
      from r$h$,
$h$    select r.*,
           not (coalesce((r.requires->>'navigation')::int, 1) > greatest(1, v_nav)) as within,   -- 0218: navigation alone
           row_number() over (order by r.mine desc,
                                       not (coalesce((r.requires->>'navigation')::int, 1) > greatest(1, v_nav)) desc,
                                       r.nm desc nulls last, r.name, r.id) as rk
      from r$h$);

-- the pre-images under pg_temp names, for the before/after proof: the old gate, the old passage table calling it,
-- the old requirement and the old board calling that
do $$
begin
  if (select count(*) from defs_before_0218 where def is not null) <> 4 then
    raise exception '0218 self-assert FAIL: % of the 4 bodies found', (select count(*) from defs_before_0218 where def is not null);
  end if;
  execute replace((select def from defs_before_0218 where ord = 1),
                  'CREATE OR REPLACE FUNCTION public.passage_gate(', 'CREATE OR REPLACE FUNCTION pg_temp.passage_gate_old_0218(');
  execute replace(replace((select def from defs_before_0218 where ord = 2),
                  'CREATE OR REPLACE FUNCTION voyage.reach_passage(', 'CREATE OR REPLACE FUNCTION pg_temp.reach_passage_old_0218('),
                  'public.passage_gate(', 'pg_temp.passage_gate_old_0218(');
  execute replace((select def from defs_before_0218 where ord = 3),
                  'CREATE OR REPLACE FUNCTION public.route_requirement(', 'CREATE OR REPLACE FUNCTION pg_temp.route_requirement_old_0218(');
  execute replace(replace((select def from defs_before_0218 where ord = 4),
                  'CREATE OR REPLACE FUNCTION world.route_board(', 'CREATE OR REPLACE FUNCTION pg_temp.route_board_old_0218('),
                  'public.route_requirement(', 'pg_temp.route_requirement_old_0218(');
end $$;

-- ── 2. THE NEW BODIES ─────────────────────────────────────────────────────────────────────────
do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
  v_n   int := 0;
begin
  for d in select * from defs_before_0218 order by ord loop
    v_def := d.def;
    for h in select * from hunks_0218 where fn = d.fn order by n loop
      if pg_temp.occurs_0218(v_def, h.old) <> 1 then
        raise exception '0218 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0218(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0218 self-assert FAIL: % has no hunk', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0218 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0218(v_rev, h.new) <> 1 then
        raise exception '0218 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0218 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0218 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config (% → %)', d.fn, d.acl, p.acl, d.cfg, p.cfg;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 4 then
    raise exception '0218 self-assert FAIL: % bodies re-cut, not 4', v_n;
  end if;
end $$;

comment on function public.passage_gate(uuid, uuid, numeric, uuid, jsonb) is
  '0107 (owner rows 113a/113c), 0216, 0218 (owner row 204): THE earned-passage predicate — null, or a cmd.refusal in '
  'voyage.sail_refusal''s own shape (0050). Dark: the LENGTH of a leg against NAVIGATION (E_LEG_TOO_FAR) and nothing '
  'else — the region door is gone. Lit (sea_conditions_bite): public.sea_gate for the destination''s waters and the '
  'course''s. Called by voyage.sail_refusal, cmd.standing_route_save_for, cmd.issue_lines. Merchants and a null '
  'player are exempt. Server-only.';

comment on function public.route_requirement(uuid) is
  '0108 (owner row 117), 0218 (owner row 204): {navigation} — what a standing route asks of any captain, the inverse '
  'of public.passage_gate: the smallest NAVIGATION whose reach (nav_leg_nm_base x 2^(L-1)) covers the longest leg, '
  'null when a leg is unmeasured. No exploration: there is no region door. Server-only.';

-- ── 3. SELF-ASSERT (own probe rows, rolled back) ───────────────────────────────────────────────
do $$
declare
  c_uid     constant uuid := '00000000-0218-4000-8000-000000000001';
  v_player  uuid;
  v_fleet   uuid;
  v_npc     uuid;
  v_lis     uuid;
  v_target  uuid;
  v_tcode   text;
  v_tlvl    int;
  v_tleg    numeric;
  v_top     int;
  v_lvl     int;
  j_old     jsonb;
  j_new     jsonb;
  c         record;
  v_i       int;
  v_t0      timestamptz;
  v_old_n   int;
  v_new_n   int;
  v_total   int;
  v_lost    int;
  v_longer  int;
  v_gained  int;
  v_gained1 int;
  v_h       int := 0;
  v_hgain   int := 0;
  v_hlost   int := 0;
  v_hlonger int := 0;
  v_rows    int;
  v_shut    int;
  v_open    int;
  v_bad     int;
  v_rp_old  numeric[] := '{}';
  v_rp_new  numeric[] := '{}';
  v_pg_old  numeric[] := '{}';
  v_pg_new  numeric[] := '{}';
  v_on_before boolean := public.npc_traders_on();
begin
  select id into v_lis from public.ports where code = 'LIS';
  if public.sea_conditions_on() then
    raise exception '0218 self-assert FAIL: sea_conditions_bite is lit — this file is cut for the dark gate';
  end if;
  select max(lvl) into v_top from former_0218;
  if v_top < 2 then
    raise exception '0218 self-assert FAIL: the former door had no level above 1 (top %) — nothing to open', v_top;
  end if;

  begin
    -- THE PROBE: a level-1 house at Lisbon, a barca, NAVIGATION as founded (the leg rule is left to speak)
    v_player := public.new_house(c_uid, 'Casa 0218', 'PRT', 'LIS', 'Gaivota', 'barca', 'Gaivota 0218', 500000);
    select f.id into v_fleet from public.fleets f where f.player_id = v_player order by f.created_at limit 1;
    perform cmd.assume_identity(c_uid);
    if public.current_player_id() is distinct from v_player then
      raise exception '0218 self-assert FAIL: the probe is not the signed-in house';
    end if;
    v_lvl := coalesce((public.player_progress(v_player)->'exploration'->>'level')::int, 1);
    if v_lvl <> 1 or public.exploration_reach(v_player) <> 1 then
      raise exception '0218 self-assert FAIL: the probe is exploration % (reach %), not 1', v_lvl, public.exploration_reach(v_player);
    end if;

    -- (a) THE PASSAGE TABLE FROM LISBON, old and new, timed 6 + 6 in this session
    for v_i in 1 .. 6 loop
      v_t0 := clock_timestamp();
      perform count(*) from pg_temp.reach_passage_old_0218(v_player, v_fleet, v_lis);
      v_rp_old := v_rp_old || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
      v_t0 := clock_timestamp();
      perform count(*) from voyage.reach_passage(v_player, v_fleet, v_lis);
      v_rp_new := v_rp_new || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
    end loop;
    create temp table rp_old_0218 on commit drop as
      select r.port_id, r.code, r.nm, r.stops, r.max_leg_nm from pg_temp.reach_passage_old_0218(v_player, v_fleet, v_lis) r;
    create temp table rp_new_0218 on commit drop as
      select r.port_id, r.code, r.nm, r.stops, r.max_leg_nm from voyage.reach_passage(v_player, v_fleet, v_lis) r;
    select count(*), count(*) filter (where stops is not null) into v_total, v_old_n from rp_old_0218;
    select count(*) filter (where stops is not null) into v_new_n from rp_new_0218;
    if (select count(*) from rp_new_0218) <> v_total then
      raise exception '0218 self-assert FAIL: the passage table has % rows, the pre-image %', (select count(*) from rp_new_0218), v_total;
    end if;
    -- nothing lost, nothing longer (a passage may now be SHORTER through a harbour that was shut)
    select count(*) filter (where n.stops is null),
           count(*) filter (where n.nm > o.nm)
      into v_lost, v_longer
      from rp_old_0218 o join rp_new_0218 n on n.port_id = o.port_id
     where o.stops is not null;
    if v_lost <> 0 or v_longer <> 0 then
      raise exception '0218 self-assert FAIL: from Lisbon % harbour(s) lost and % passage(s) longer than before', v_lost, v_longer;
    end if;
    -- harbours gained, every one of them behind the former door (a level-1 region was never shut)
    select count(*), count(*) filter (where f.lvl = 1)
      into v_gained, v_gained1
      from rp_old_0218 o join rp_new_0218 n on n.port_id = o.port_id
      join public.ports p on p.id = n.port_id join former_0218 f on f.region_id = p.region_id
     where o.stops is null and n.stops is not null;
    if v_gained < 1 then
      raise exception '0218 self-assert FAIL: a Lisbon starter reaches % harbours before and % after — the door opened nothing', v_old_n, v_new_n;
    end if;
    if v_gained1 <> 0 then
      raise exception '0218 self-assert FAIL: % gained harbour(s) lie in a level-1 region, which was never shut', v_gained1;
    end if;

    -- (b) A HARBOUR OF THE FORMER TOP LEVEL, reached by legs: the gate opens where the pre-image refused
    select n.port_id, n.code, f.lvl, n.max_leg_nm into v_target, v_tcode, v_tlvl, v_tleg
      from rp_new_0218 n join public.ports p on p.id = n.port_id join former_0218 f on f.region_id = p.region_id
     where n.stops is not null and f.lvl = v_top
     order by n.code limit 1;
    if v_target is null then
      raise exception '0218 self-assert FAIL: no harbour of the former level % is reached by legs from Lisbon (reach %)', v_top, v_new_n;
    end if;
    for v_i in 1 .. 6 loop
      v_t0 := clock_timestamp();
      j_old := pg_temp.passage_gate_old_0218(v_player, v_fleet, null, v_target, null);
      v_pg_old := v_pg_old || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
      v_t0 := clock_timestamp();
      j_new := public.passage_gate(v_player, v_fleet, null, v_target, null);
      v_pg_new := v_pg_new || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
    end loop;
    if j_old->>'code' is distinct from 'E_REGION_CLOSED' or (j_old->'figures'->>'needs')::int <> v_top then
      raise exception '0218 self-assert FAIL: the pre-image did not refuse % for its region (positive control): %', v_tcode, j_old;
    end if;
    if j_new is not null then
      raise exception '0218 self-assert FAIL: the gate still refuses % with no miles: %', v_tcode, j_new;
    end if;
    j_new := public.passage_gate(v_player, v_fleet, v_tleg, v_target, null);
    if j_new is not null then
      raise exception '0218 self-assert FAIL: the gate refuses % on its passage''s longest leg (% nm): %', v_tcode, v_tleg, j_new;
    end if;
    j_new := voyage.sail_refusal(v_fleet, v_target, null, v_tleg);
    if j_new->>'code' in ('E_REGION_CLOSED', 'E_LEG_TOO_FAR') then
      raise exception '0218 self-assert FAIL: the sail door shuts % for region or leg: %', v_tcode, j_new;
    end if;
    -- the leg rule stands: a 999,999 nm leg is still refused, for its length
    j_new := public.passage_gate(v_player, v_fleet, 999999, v_target, null);
    if j_new->>'code' is distinct from 'E_LEG_TOO_FAR' then
      raise exception '0218 self-assert FAIL: a 999,999 nm leg reads % — the leg rule moved', j_new;
    end if;
    -- a merchant is exempt, before and after
    select p.id into v_npc from public.players p where p.is_npc order by p.created_at limit 1;
    if v_npc is not null and (pg_temp.passage_gate_old_0218(v_npc, null, null, v_target, null) is not null
                              or public.passage_gate(v_npc, null, null, v_target, null) is not null) then
      raise exception '0218 self-assert FAIL: a merchant is asked at the door';
    end if;

    -- (c) EVERY HUMAN OF THE WORLD, from where her first fleet lies: nothing lost, nothing longer (a read)
    for c in select p.id, f.id as fleet, f.port_id
               from public.players p join public.fleets f on f.player_id = p.id and f.port_id is not null
              where not p.is_npc and p.id <> v_player order by p.created_at, f.created_at loop
      select count(*) filter (where o.stops is not null and n.stops is null),
             count(*) filter (where o.stops is not null and n.nm > o.nm),
             count(*) filter (where o.stops is null and n.stops is not null)
        into v_lost, v_longer, v_gained
        from pg_temp.reach_passage_old_0218(c.id, c.fleet, c.port_id) o
        join voyage.reach_passage(c.id, c.fleet, c.port_id) n on n.port_id = o.port_id;
      v_h := v_h + 1;
      v_hlost := v_hlost + v_lost;
      v_hlonger := v_hlonger + v_longer;
      v_hgain := v_hgain + v_gained;
    end loop;
    if v_hlost <> 0 or v_hlonger <> 0 then
      raise exception '0218 self-assert FAIL: over % humans, % harbour(s) lost and % passage(s) longer', v_h, v_hlost, v_hlonger;
    end if;

    -- (d) THE ROUTE BOARD for the probe: same lanes; `requires` is {navigation}; no lane shut now that was open.
    -- The board serves merchant lanes only while the merchants are on (0106): on a dark world they are lit here by
    -- their two keys, rolled back with the probe (the switch function itself would put the roster to sea).
    if not public.npc_traders_on() then
      update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
    end if;
    j_old := pg_temp.route_board_old_0218();
    j_new := world.route_board();
    select count(*) into v_rows from jsonb_array_elements(j_new->'routes');
    if v_rows <> (select count(*) from jsonb_array_elements(j_old->'routes')) or v_rows < 1 then
      raise exception '0218 self-assert FAIL: the board serves % lanes, the pre-image %', v_rows, (select count(*) from jsonb_array_elements(j_old->'routes'));
    end if;
    select count(*) into v_bad
      from jsonb_array_elements(j_new->'routes') n
     where (select array_agg(k order by k) from jsonb_object_keys(n->'requires') k) <> array['navigation'];
    if v_bad <> 0 then
      raise exception '0218 self-assert FAIL: % lane(s) still carry a requirement other than navigation', v_bad;
    end if;
    select count(*) into v_bad
      from jsonb_array_elements(j_new->'routes') n
      join jsonb_array_elements(j_old->'routes') o on o->>'id' = n->>'id'
     where (n->>'closed')::boolean and not (o->>'closed')::boolean;
    if v_bad <> 0 then
      raise exception '0218 self-assert FAIL: % lane(s) are shut now that were open before', v_bad;
    end if;
    -- (0109's cap ranks the lanes she can sail first, so a capped board may hold no shut lane at all: the shut
    -- count is reported, not required)
    select count(*) filter (where (n->>'closed')::boolean), count(*) filter (where not (n->>'closed')::boolean)
      into v_shut, v_open from jsonb_array_elements(j_new->'routes') n;
    if v_open < 1 then
      raise exception '0218 self-assert FAIL: the board holds no open lane (% shut)', v_shut;
    end if;
    select count(*) into v_bad
      from jsonb_array_elements(j_new->'routes') n
     where (n->>'closed')::boolean <> (coalesce((n->'requires'->>'navigation')::int, 1) > 1);
    if v_bad <> 0 then
      raise exception '0218 self-assert FAIL: % lane(s) disagree with the navigation rule about being shut', v_bad;
    end if;

    raise notice '0218 probe: Lisbon starter reaches % of % harbours (was %; +% gained); % reached at former level % on a % nm longest leg; % humans gained % passages; board % lanes, % shut; reach_passage old/new %/% ms (calls 4-6 %/%), passage_gate old/new %/% ms',
      v_new_n, v_total, v_old_n, v_gained, v_tcode, v_tlvl, v_tleg, v_h, v_hgain, v_rows, v_shut,
      round((select avg(x) from unnest(v_rp_old) x), 1), round((select avg(x) from unnest(v_rp_new) x), 1),
      round((select avg(x) from unnest(v_rp_old[4:6]) x), 1), round((select avg(x) from unnest(v_rp_new[4:6]) x), 1),
      round((select avg(x) from unnest(v_pg_old) x), 2), round((select avg(x) from unnest(v_pg_new) x), 2);
    raise exception using errcode = 'ZX218', message = 'probe done';
  exception when sqlstate 'ZX218' then
    null;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid or company_name = 'Casa 0218') then
    raise exception '0218 self-assert FAIL: the probe survived its rollback';
  end if;
  if public.npc_traders_on() <> v_on_before then
    raise exception '0218 self-assert FAIL: the merchant switch survived the rollback';
  end if;
end $$;

-- ── 4. NOTHING LEFT BEHIND THE DOOR ────────────────────────────────────────────────────────────
drop function public.exploration_reach(uuid);
alter table public.regions drop column min_exploration_level;
delete from public.world_config where key in ('region_level_nm_step', 'region_level_max');

do $$
declare
  v_names text;
begin
  select string_agg(n.nspname || '.' || p.proname, ', ' order by 1) into v_names
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('cmd', 'voyage', 'world', 'public', 'npc')
     and (p.prosrc like '%E_REGION_CLOSED%' or p.prosrc like '%min_exploration_level%' or p.prosrc like '%exploration_reach%');
  if v_names is not null then
    raise exception '0218 self-assert FAIL: the door is still named by %', v_names;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'regions' and column_name = 'min_exploration_level')
     or to_regprocedure('public.exploration_reach(uuid)') is not null
     or exists (select 1 from public.world_config where key in ('region_level_nm_step', 'region_level_max')) then
    raise exception '0218 self-assert FAIL: the column, the function or a knob survived';
  end if;
  if (select count(*) from public.regions) <> (select regions from before_0218) then
    raise exception '0218 self-assert FAIL: the regions moved';
  end if;
  -- the walls: the gate, the passage table and the requirement are server-only; the board is the client's
  if has_function_privilege('authenticated', 'public.passage_gate(uuid, uuid, numeric, uuid, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.passage_gate(uuid, uuid, numeric, uuid, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'voyage.reach_passage(uuid, uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.route_requirement(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'world.route_board()', 'execute') then
    raise exception '0218 self-assert FAIL: the walls do not hold';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0218)
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0218 self-assert FAIL: the registry moved or a row is not executable';
  end if;
  raise notice '0218 self-assert ok: THERE IS NO REGION DOOR (owner row 204). Four bodies re-cut and reversed (11 hunks; ACL, volatility, definer, config, owner unchanged); public.exploration_reach, regions.min_exploration_level and the two region_level knobs are gone; no live body names them; the walls hold; the registry is unmoved. % ms.',
    round(extract(epoch from clock_timestamp() - (select t0 from t0_0218)) * 1000);
end $$;
