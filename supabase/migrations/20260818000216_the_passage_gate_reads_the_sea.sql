-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0216 — THE PASSAGE GATE READS THE SEA  (docs/SEA_CONDITIONS_AND_REGIONS.md, slice S2 — players: public.passage_gate
--        gains the fleet and the course and, WHILE `sea_conditions_bite` IS LIT, asks the one sea rule (public.sea_gate)
--        in place of 0107's region door; dark it is the pre-image to the character)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, 2026-10-20 ───────────────────────────────────────────────────────────────────────
--   Hard wall: "refused when a plan is written and again at departure; the map shades the closed seas."
--   "Navigation's per-leg reach (0107 / 0188, the owner's own rule) stays. Both rules compose in the one passage gate."
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   public.passage_gate (0107, 0112): after the reach, the DESTINATION's region against her exploration
--   (regions.min_exploration_level, E_REGION_CLOSED) — a second authority for "is this place open to her" beside the
--   zone table 0215 built. Lit, this file never reads it: public.sea_gate decides. DARK IT STAYS, to the character:
--   the owner's rule for every dark slice is "no answer changes while the switch is off", and 0107's door refuses
--   real plans today (a level-1 house bound for the Caribbean). The dead branch and its column go in the slice after
--   the switch is lit (S2b), with public.exploration_reach and the route board's `exploration` key — one authority
--   from the moment the switch moves, one body once it has.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   (1) public.passage_gate(player, FLEET, nm, dest, COURSE): the reach as before (0188's one formula), then — lit —
--       public.sea_gate(player, fleet, dest, course); dark — the 0107 region door as before. Arity changes: dropped,
--       recreated, its ACL restored grant by grant (postgres + service_role) and asserted. Merchants and nobody stay
--       exempt at the door (0107 d4): a merchant at sea finishes her trip; the planner judges her (S3).
--   (2) Its four callers hand what they have, one hunk each: voyage.sail_refusal(…, + p_course default null) passes
--       `f.id` and the course (arity change: dropped / recreated / ACL restored); cmd.do_sail hands the measured
--       departure's course; cmd.standing_route_save_for hands the route's fleet (null until assigned: the title alone
--       judges a save) and the stop's course; cmd.issue_lines hands the fleet and the line's course.
--   (3) voyage.reach_passage(player, FLEET, from): lit, her title and her fleet's wave are read ONCE a call and every
--       edge is open or shut by public.sea_leg_asks (the one derivation; the same figures the rule compares); dark,
--       the pre-image. Arity change: dropped / recreated, ACL and plan_cache_mode (0206) kept. world.good_board's two
--       call sites pass the fleet (2 hunks).
--   (4) Nothing is lit here: sea_conditions_bite stays false; the deploy lights it after the push's after-check.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
--   Drop regions.min_exploration_level, public.exploration_reach or re-cut public.route_requirement / world.route_board
--   (S2b, after the flip). Touch the merchant planner (S3). Change any figure of the reach. Change world.trade_routes
--   (it calls sail_refusal with four arguments; the fifth defaults).
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
--   DROP + CREATE FUNCTION ×3, CREATE OR REPLACE ×4, all by hunks; no table is touched. The probe company is made in a
--   sub-transaction rolled back whole (the switch is flipped inside it and rolled back with it).
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0211, LF-normalised, each asserted to occur exactly
-- once and to reverse to its pre-image, ACL / volatility / definer / config unchanged or restored):
--   public.passage_gate(uuid, numeric, uuid) → (uuid, uuid, numeric, uuid, jsonb) (2 hunks), voyage.sail_refusal(uuid,
--   uuid, jsonb, numeric) → (…, jsonb) (2), cmd.do_sail(uuid, jsonb) (1), cmd.standing_route_save_for(uuid, uuid, text,
--   jsonb, bigint, integer, integer) (1), cmd.issue_lines(uuid, jsonb, integer) (1), voyage.reach_passage(uuid, uuid) →
--   (uuid, uuid, uuid) (5), world.good_board(uuid, uuid, uuid, numeric) (2).
--
-- SELF-ASSERT (docs/SEA_CONDITIONS_AND_REGIONS.md §6, S2; own probe rows, rolled back): DARK — the gate, the sail
-- door and the passage table answer exactly as their pre-images on 20 sampled passages for the probe and for every
-- human of the world (E_REGION_CLOSED among them, the positive control), good_board's rows unchanged, timings equal.
-- LIT (inside the rollback) — a title-1 barca at Lisbon: Funchal clear, Las Palmas E_SEA_CLOSED naming Macaronesia
-- (title 2 asked, 1 held, wave 10 asked, 12 held), the plan refused up front with the line named; title 3 (probe
-- turnover and ports) clears Las Palmas; a nau to Havana refused on title at 3, clear at 4, refused on WAVE with two
-- barcas added (21 < 30), the sentence naming the wave; a merchant exempt at the door on a 999,999 nm leg; reach_passage
-- from Lisbon at title 1 reaches every title-1 harbour and no other, at title 8 with a carrack of state every harbour;
-- the walls hold.
-- ROLLBACK (forward migration): reverse the hunks (each OLD text is here verbatim), drop the three new signatures and
-- recreate the old ones from the pre-images, grants as before.
-- VERSION: 0216 (renumber to the prod head + 1 at push; applies on 0215).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0216(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table t0_0216 on commit drop as select clock_timestamp() as t0;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0216 on commit drop as
select f.ord, f.fn, f.new_fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values (1, 'public.passage_gate(uuid,numeric,uuid)',            'public.passage_gate(uuid,uuid,numeric,uuid,jsonb)'),
               (2, 'voyage.sail_refusal(uuid,uuid,jsonb,numeric)',      'voyage.sail_refusal(uuid,uuid,jsonb,numeric,jsonb)'),
               (3, 'cmd.do_sail(uuid,jsonb)',                           'cmd.do_sail(uuid,jsonb)'),
               (4, 'cmd.standing_route_save_for(uuid,uuid,text,jsonb,bigint,integer,integer)',
                   'cmd.standing_route_save_for(uuid,uuid,text,jsonb,bigint,integer,integer)'),
               (5, 'cmd.issue_lines(uuid,jsonb,integer)',               'cmd.issue_lines(uuid,jsonb,integer)'),
               (6, 'voyage.reach_passage(uuid,uuid)',                   'voyage.reach_passage(uuid,uuid,uuid)'),
               (7, 'world.good_board(uuid,uuid,uuid,numeric)',          'world.good_board(uuid,uuid,uuid,numeric)')) f(ord, fn, new_fn);

create temp table before_0216 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

create temp table hunks_0216 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0216 values
('public.passage_gate(uuid,numeric,uuid)', 1,
$h$CREATE OR REPLACE FUNCTION public.passage_gate(p_player uuid, p_nm numeric, p_dest uuid)
$h$,
$h$CREATE OR REPLACE FUNCTION public.passage_gate(p_player uuid, p_fleet uuid, p_nm numeric, p_dest uuid, p_course jsonb DEFAULT NULL::jsonb)
$h$),
('public.passage_gate(uuid,numeric,uuid)', 2,
$h$  if p_dest is not null then
    select r.name, r.min_exploration_level into v_region, v_need
$h$,
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
$h$),
('voyage.sail_refusal(uuid,uuid,jsonb,numeric)', 1,
$h$CREATE OR REPLACE FUNCTION voyage.sail_refusal(p_fleet uuid, p_dest uuid, p_dest_point jsonb, p_nm numeric)
$h$,
$h$CREATE OR REPLACE FUNCTION voyage.sail_refusal(p_fleet uuid, p_dest uuid, p_dest_point jsonb, p_nm numeric, p_course jsonb DEFAULT NULL::jsonb)
$h$),
('voyage.sail_refusal(uuid,uuid,jsonb,numeric)', 2,
$h$  v_gate := public.passage_gate(f.player_id, p_nm, p_dest);
$h$,
$h$  v_gate := public.passage_gate(f.player_id, f.id, p_nm, p_dest, p_course);   -- 0216: her fleet and her course, for the sea
$h$),
('cmd.do_sail(uuid,jsonb)', 1,
$h$  v_gate := voyage.sail_refusal(p_fleet, v_dest, v_point, v_nm);
$h$,
$h$  v_gate := voyage.sail_refusal(p_fleet, v_dest, v_point, v_nm, v_course);   -- 0216: + the course (the sea conditions judge it)
$h$),
('cmd.standing_route_save_for(uuid,uuid,text,jsonb,bigint,integer,integer)', 1,
$h$      v_gate := public.passage_gate(p_player, v_leg_nm, v_port.id);
$h$,
$h$      v_gate := public.passage_gate(p_player, sr.fleet_id, v_leg_nm, v_port.id, s->'course');   -- 0216: + her fleet (none until assigned) and the leg's course
$h$),
('cmd.issue_lines(uuid,jsonb,integer)', 1,
$h$    v_gate := public.passage_gate(v_player, v_nm, v_dest);
$h$,
$h$    v_gate := public.passage_gate(v_player, p_fleet, v_nm, v_dest, v_lpath);   -- 0216: + the fleet and the course
$h$),
('voyage.reach_passage(uuid,uuid)', 1,
$h$CREATE OR REPLACE FUNCTION voyage.reach_passage(p_player uuid, p_from uuid)
$h$,
$h$CREATE OR REPLACE FUNCTION voyage.reach_passage(p_player uuid, p_fleet uuid, p_from uuid)
$h$),
('voyage.reach_passage(uuid,uuid)', 2,
$h$  v_path  text[];
begin
$h$,
$h$  v_path  text[];
  ok      boolean[];   -- 0216: lit, edge i → j is open when public.sea_leg_asks allows it for her title and her fleet's wave
  v_title int;
  v_wave  numeric;
begin
$h$),
('voyage.reach_passage(uuid,uuid)', 3,
$h$    select h.region_id, public.passage_gate(p_player, null, h.id) is null as open
$h$,
$h$    select h.region_id, public.passage_gate(p_player, p_fleet, null, h.id, null) is null as open   -- 0216: lit, the harbour's own zone
$h$),
('voyage.reach_passage(uuid,uuid)', 4,
$h$  if coalesce(array_length(d, 1), 0) <> v_n * v_n then
    raise exception 'voyage.reach_passage: % harbours but % sailed distances — a harbour has no sea_reaches row', v_n, coalesce(array_length(d, 1), 0);
  end if;
$h$,
$h$  if coalesce(array_length(d, 1), 0) <> v_n * v_n then
    raise exception 'voyage.reach_passage: % harbours but % sailed distances — a harbour has no sea_reaches row', v_n, coalesce(array_length(d, 1), 0);
  end if;
  -- 0216: THE SEA, ONCE A CALL. Lit, her title and her fleet's wave are read once and every edge is open or shut by
  -- public.sea_leg_asks (the straight line between the two roadsteads and the destination's zone — the one derivation,
  -- the same figures public.sea_refusal compares); a side she has no figure for (a merchant's title, an empty fleet's
  -- wave) is not asked, as the rule itself skips it. Dark, `ok` stays null and every edge is as before.
  if public.sea_conditions_on() then
    v_title := public.title_level(p_player);
    v_wave  := public.fleet_wave(p_fleet);
    select array_agg(coalesce((v_title is null or s.title_min <= v_title) and (v_wave is null or s.wave_min <= v_wave), true) order by a.i, b.j)
      into ok
      from unnest(v_ids) with ordinality a(id, i)
     cross join unnest(v_ids) with ordinality b(id, j)
      left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = b.id;
    -- and a HARBOUR is open by its own zone (the self row of sea_leg_asks is exactly that), not by its region's first
    -- harbour: 0205's one-door-a-region shortcut holds for the region door, not for the sea (Funchal is home water in
    -- a region whose first harbour by code is the Azores).
    select array_agg(a.id = p_from or coalesce((v_title is null or s.title_min <= v_title) and (v_wave is null or s.wave_min <= v_wave), true) order by a.i)
      into v_open
      from unnest(v_ids) with ordinality a(id, i)
      left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = a.id;
  end if;
$h$),
('voyage.reach_passage(uuid,uuid)', 5,
$h$      if not done[j] and v_open[j] then
$h$,
$h$      if not done[j] and v_open[j] and (ok is null or ok[(u - 1) * v_n + j]) then   -- 0216
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$    from voyage.reach_passage(v_player, v_origin) r;
$h$,
$h$    from voyage.reach_passage(v_player, p_fleet, v_origin) r;   -- 0216: + her fleet (the sea conditions)
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 2,
$h$     cross join lateral voyage.reach_passage(v_player, s.id) r
$h$,
$h$     cross join lateral voyage.reach_passage(v_player, p_fleet, s.id) r   -- 0216
$h$);

-- the pre-images under pg_temp names, for the dark-identity proof: the old gate, the old door, the old passage table
-- and the old board, each calling the old one below it
do $$
begin
  if (select count(*) from defs_before_0216 where def is not null) <> 7 then
    raise exception '0216 self-assert FAIL: % of the 7 bodies found', (select count(*) from defs_before_0216 where def is not null);
  end if;
  execute replace((select def from defs_before_0216 where ord = 1),
                  'CREATE OR REPLACE FUNCTION public.passage_gate(', 'CREATE OR REPLACE FUNCTION pg_temp.passage_gate_old_0216(');
  execute replace(replace((select def from defs_before_0216 where ord = 2),
                  'CREATE OR REPLACE FUNCTION voyage.sail_refusal(', 'CREATE OR REPLACE FUNCTION pg_temp.sail_refusal_old_0216('),
                  'public.passage_gate(', 'pg_temp.passage_gate_old_0216(');
  execute replace(replace((select def from defs_before_0216 where ord = 6),
                  'CREATE OR REPLACE FUNCTION voyage.reach_passage(', 'CREATE OR REPLACE FUNCTION pg_temp.reach_passage_old_0216('),
                  'public.passage_gate(', 'pg_temp.passage_gate_old_0216(');
  execute replace(replace((select def from defs_before_0216 where ord = 7),
                  'CREATE OR REPLACE FUNCTION world.good_board(', 'CREATE OR REPLACE FUNCTION pg_temp.good_board_old_0216('),
                  'voyage.reach_passage(', 'pg_temp.reach_passage_old_0216(');
end $$;

-- ── 2. THE NEW BODIES ──────────────────────────────────────────────────────────────────────────
do $$
declare
  d     record;
  h     record;
  p     record;
  g     record;
  v_def text;
  v_rev text;
  v_n   int := 0;
begin
  for d in select * from defs_before_0216 order by ord loop
    v_def := d.def;
    for h in select * from hunks_0216 where fn = d.fn order by n loop
      if pg_temp.occurs_0216(v_def, h.old) <> 1 then
        raise exception '0216 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0216(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0216 self-assert FAIL: % has no hunk', d.fn;
    end if;
    -- a widened signature is a new function: the old one is dropped first (its callers name it by its first
    -- arguments, which the new one takes with the same names and positions — or through the default)
    if d.fn <> d.new_fn then
      execute format('drop function %s', d.fn);
    end if;
    execute v_def;
    if d.fn <> d.new_fn then
      execute format('revoke all on function %s from public', d.new_fn);
      for g in select r.rolname from pg_roles r where r.rolname in ('anon', 'authenticated', 'service_role') loop
        execute format('revoke all on function %s from %I', d.new_fn, g.rolname);
      end loop;
      for g in select distinct case when a.grantee = 0 then 'public' else a.grantee::regrole::text end as who
                 from pg_proc pp, aclexplode(coalesce(nullif(d.acl, '')::aclitem[], '{}'::aclitem[])) a
                where pp.oid = d.new_fn::regprocedure and a.grantee <> pp.proowner and a.privilege_type = 'EXECUTE' loop
        execute format('grant execute on function %s to %s', d.new_fn, g.who);
      end loop;
    end if;
    v_rev := replace(pg_get_functiondef(d.new_fn::regprocedure), E'\r', '');
    for h in select * from hunks_0216 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0216(v_rev, h.new) <> 1 then
        raise exception '0216 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0216 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.new_fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0216 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config (% → %)', d.fn, d.acl, p.acl, d.cfg, p.cfg;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 7 then
    raise exception '0216 self-assert FAIL: % bodies re-cut, not 7', v_n;
  end if;
  if exists (select 1 from pg_proc pp join pg_namespace ns on ns.oid = pp.pronamespace
              where (ns.nspname, pp.proname) in (('public', 'passage_gate'), ('voyage', 'sail_refusal'), ('voyage', 'reach_passage'))
              group by ns.nspname, pp.proname having count(*) <> 1) then
    raise exception '0216 self-assert FAIL: an old signature survived beside the new one';
  end if;
end $$;

-- ── 3. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0216-4000-8000-000000000001';
  v_out    text := '';
  v_player uuid;
  v_fleet  uuid;
  v_fleet2 uuid;
  v_fleet3 uuid;
  v_npc    uuid;
  v_lis    uuid;
  v_hav    uuid;
  v_fnc    uuid;
  v_lpa    uuid;
  v_hnl    uuid;
  v_good   uuid;
  v_course jsonb;
  v_hcourse jsonb;
  v_nm     numeric;
  v_ref    jsonb;
  v_res    jsonb;
  j_old    jsonb;
  j_new    jsonb;
  o        record;
  v_n      int;
  v_bad    int := 0;
  v_badl   text := '';
  v_regions int := 0;
  v_cnt    int := 0;
  v_hcnt   int := 0;
  v_hbad   int := 0;
  v_t0     timestamptz;
  v_rp_old numeric[] := '{}';
  v_rp_new numeric[] := '{}';
  v_rp_lit numeric[] := '{}';
  v_gb_old numeric[] := '{}';
  v_gb_new numeric[] := '{}';
  v_i      int;
  v_title  int;
  v_home   int;
  v_reached int;
  v_total  int;
  v_sell   bigint := 0;
  v_ports  int := 0;
  c        record;
begin
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_hav from public.ports where code = 'HAV';
  select id into v_fnc from public.ports where code = 'FNC';
  select id into v_lpa from public.ports where code = 'LPA';
  select id into v_hnl from public.ports where code = 'HNL';
  if public.sea_conditions_on() then
    raise exception '0216 self-assert FAIL: sea_conditions_bite is already lit — this file lands dark';
  end if;

  begin
    -- THE PROBE COMPANY: a barca at Lisbon, title 1, NAVIGATION 5 (so the reach never speaks first: the sea does),
    -- SEAMANSHIP 5 (room for three hulls in one fleet), stores for any passage
    v_player := public.new_house(c_uid, 'Casa 0216', 'PRT', 'LIS', 'Gaivota', 'barca', 'Gaivota 0216', 500000);
    select f.id into v_fleet from public.fleets f where f.player_id = v_player order by f.created_at limit 1;
    insert into public.player_skills (player_id, skill_id, level)
    select v_player, sk.id, 5 from public.skills sk where sk.code in ('NAVIGATION', 'SEAMANSHIP');
    update public.ships set water_t = 20, food_t = 20 where fleet_id = v_fleet;
    perform cmd.assume_identity(c_uid);
    if public.current_player_id() is distinct from v_player then
      raise exception '0216 self-assert FAIL: the probe is not the signed-in house';
    end if;
    v_course := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                   from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc);
    v_hcourse := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                    from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_hav);

    -- ── DARK: every answer is the pre-image's ─────────────────────────────────────────────────
    -- (a) the gate, on 20 passages out of Lisbon (the 10 nearest and the 10 farthest harbours), with the sailed miles
    -- and with no miles (the region door alone), for the probe and for every human of the world
    for o in (select r.port_id, r.nm from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR' order by r.nm limit 10)
             union all
             (select r.port_id, r.nm from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR' order by r.nm desc limit 10) loop
      for c in select p.id, (select f.id from public.fleets f where f.player_id = p.id order by f.created_at limit 1) as fleet
                 from public.players p where p.id = v_player or not p.is_npc loop
        j_old := pg_temp.passage_gate_old_0216(c.id, o.nm, o.port_id);
        j_new := public.passage_gate(c.id, c.fleet, o.nm, o.port_id, null);
        v_cnt := v_cnt + 1;
        if j_old is distinct from j_new then v_bad := v_bad + 1; v_badl := v_badl || format(' gate:%s', (select code from public.ports where id = o.port_id)); end if;
        j_old := pg_temp.passage_gate_old_0216(c.id, null, o.port_id);
        j_new := public.passage_gate(c.id, c.fleet, null, o.port_id, null);
        v_cnt := v_cnt + 1;
        if j_old is distinct from j_new then v_bad := v_bad + 1; v_badl := v_badl || format(' door:%s', (select code from public.ports where id = o.port_id)); end if;
        if j_old->>'code' = 'E_REGION_CLOSED' then v_regions := v_regions + 1; end if;
      end loop;
      -- (b) the sail door, for the probe fleet
      j_old := pg_temp.sail_refusal_old_0216(v_fleet, o.port_id, null, o.nm);
      j_new := voyage.sail_refusal(v_fleet, o.port_id, null, o.nm);
      v_cnt := v_cnt + 1;
      if j_old is distinct from j_new then v_bad := v_bad + 1; v_badl := v_badl || format(' sail:%s', (select code from public.ports where id = o.port_id)); end if;
    end loop;
    if v_bad <> 0 then
      raise exception '0216 self-assert FAIL: dark, % of % answers differ from the pre-image:%', v_bad, v_cnt, v_badl;
    end if;
    if v_regions = 0 then
      raise exception '0216 self-assert FAIL: dark, no sampled passage was refused E_REGION_CLOSED — the dark door was never exercised';
    end if;
    -- the probe to Havana, dark: the region door refuses, old and new alike (the positive control, named)
    j_old := pg_temp.passage_gate_old_0216(v_player, null, v_hav);
    j_new := public.passage_gate(v_player, v_fleet, null, v_hav, v_hcourse);
    if j_old is distinct from j_new or j_new->>'code' <> 'E_REGION_CLOSED' then
      raise exception '0216 self-assert FAIL: dark, Lisbon → Havana reads % (old %)', j_new, j_old;
    end if;
    -- (c) the passage table from Lisbon, dark: old and new row for row, timed 6 + 6 in this session
    for v_i in 1 .. 6 loop
      v_t0 := clock_timestamp();
      select jsonb_agg(jsonb_build_array(r.code, r.nm, r.direct_nm, to_jsonb(r.stops), r.max_leg_nm) order by r.code) into j_old from pg_temp.reach_passage_old_0216(v_player, v_lis) r;
      v_rp_old := v_rp_old || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
      v_t0 := clock_timestamp();
      select jsonb_agg(jsonb_build_array(r.code, r.nm, r.direct_nm, to_jsonb(r.stops), r.max_leg_nm) order by r.code) into j_new from voyage.reach_passage(v_player, v_fleet, v_lis) r;
      v_rp_new := v_rp_new || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
      if j_old is distinct from j_new then
        raise exception '0216 self-assert FAIL: dark, reach_passage from Lisbon differs from its pre-image (call %)', v_i;
      end if;
    end loop;
    if jsonb_array_length(j_new) < 200 then
      raise exception '0216 self-assert FAIL: reach_passage from Lisbon has % rows', jsonb_array_length(j_new);
    end if;
    -- and for every human of the world, from where her first fleet lies (a read; nothing is written)
    for c in select p.id, f.id as fleet, f.port_id
               from public.players p join public.fleets f on f.player_id = p.id and f.port_id is not null
              where not p.is_npc and p.id <> v_player order by p.created_at, f.created_at loop
      select jsonb_agg(jsonb_build_array(r.code, r.nm, to_jsonb(r.stops), r.max_leg_nm) order by r.code) into j_old from pg_temp.reach_passage_old_0216(c.id, c.port_id) r;
      select jsonb_agg(jsonb_build_array(r.code, r.nm, to_jsonb(r.stops), r.max_leg_nm) order by r.code) into j_new from voyage.reach_passage(c.id, c.fleet, c.port_id) r;
      v_hcnt := v_hcnt + 1;
      if j_old is distinct from j_new then v_hbad := v_hbad + 1; end if;
    end loop;
    if v_hbad <> 0 then
      raise exception '0216 self-assert FAIL: dark, % of % humans'' passage tables differ from the pre-image', v_hbad, v_hcnt;
    end if;
    -- (d) the good board, dark: the rows the passage shapes (port, stops, needs, sailable, miles) unchanged, timed 3 + 3
    select pg.good_id into v_good from public.port_goods pg where pg.port_id = v_lis and public.port_offers(v_lis, pg.good_id) order by pg.good_id limit 1;
    if v_good is not null then
      for v_i in 1 .. 3 loop
        v_t0 := clock_timestamp();
        v_res := pg_temp.good_board_old_0216(v_good, v_fleet, null, null);
        v_gb_old := v_gb_old || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
        select jsonb_agg(jsonb_build_array(e->'port', e->'stops', e->'needs', e->'sailable', e->'miles') order by e->>'port') into j_old
          from (select e from jsonb_array_elements(v_res->'buy') e union all select e from jsonb_array_elements(v_res->'sell') e) q;
        v_t0 := clock_timestamp();
        v_res := world.good_board(v_good, v_fleet, null, null);
        v_gb_new := v_gb_new || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
        select jsonb_agg(jsonb_build_array(e->'port', e->'stops', e->'needs', e->'sailable', e->'miles') order by e->>'port') into j_new
          from (select e from jsonb_array_elements(v_res->'buy') e union all select e from jsonb_array_elements(v_res->'sell') e) q;
        if j_old is distinct from j_new then
          raise exception '0216 self-assert FAIL: dark, the good board''s passages differ from the pre-image (call %)', v_i;
        end if;
      end loop;
    end if;

    -- ── LIT (inside the rollback): the sea decides ───────────────────────────────────────────────
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    if not public.sea_conditions_on() then
      raise exception '0216 self-assert FAIL: the switch did not move';
    end if;
    -- a title-1 barca: Funchal clear (home water), Las Palmas refused at Macaronesia — title 2 asked, 1 held, wave 10 asked, 12 held
    v_nm := (select r.nm from voyage.reach_from(v_lis) r where r.port_id = v_fnc);
    if public.passage_gate(v_player, v_fleet, v_nm, v_fnc, v_course) is not null
       or voyage.sail_refusal(v_fleet, v_fnc, null, v_nm, v_course) is not null then
      raise exception '0216 self-assert FAIL: lit, Lisbon → Funchal is refused: % / %',
        public.passage_gate(v_player, v_fleet, v_nm, v_fnc, v_course), voyage.sail_refusal(v_fleet, v_fnc, null, v_nm, v_course);
    end if;
    v_course := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                   from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_lpa);
    v_nm := (select r.nm from voyage.reach_from(v_lis) r where r.port_id = v_lpa);
    v_ref := voyage.sail_refusal(v_fleet, v_lpa, null, v_nm, v_course);
    if v_ref is null or v_ref->>'code' <> 'E_SEA_CLOSED' or v_ref->'figures'->>'zone' <> 'NOR-MAC'
       or (v_ref->'figures'->>'needs_title')::int <> 2 or (v_ref->'figures'->>'title')::int <> 1
       or (v_ref->'figures'->>'needs_wave')::int <> 10 or (v_ref->'figures'->>'wave')::numeric <> 12
       or v_ref->>'sentence' <> 'Macaronesia and the Canary Current asks title 2 and wave resistance 10 — you are title 1 and your fleet holds 12' then
      raise exception '0216 self-assert FAIL: lit, a title-1 barca bound for Las Palmas reads %', v_ref;
    end if;
    if public.passage_gate(v_player, v_fleet, v_nm, v_lpa, v_course) is distinct from v_ref then
      raise exception '0216 self-assert FAIL: the door and the gate disagree on Las Palmas';
    end if;
    -- the plan is refused up front, the line named (cmd.issue_lines, as the signed-in probe)
    v_res := cmd.issue_lines(v_fleet, jsonb_build_array(jsonb_build_object('text', 'SAIL LPA')));
    if coalesce((v_res->>'ok')::boolean, true) or v_res->>'error_code' <> 'E_SEA_CLOSED' or (v_res->>'line')::int <> 1
       or v_res->>'error_message' not like 'Line 1 (SAIL LPA): Macaronesia%' then
      raise exception '0216 self-assert FAIL: lit, the plan SAIL LPA answers %', left(v_res::text, 400);
    end if;
    if exists (select 1 from public.orders where fleet_id = v_fleet) then
      raise exception '0216 self-assert FAIL: a refused plan queued an order';
    end if;
    -- a route saved with the probe's fleet is refused the same way; a route to Funchal is saved
    v_res := cmd.standing_route_save_for(v_player, null, 'Rota 0216', jsonb_build_array(
               jsonb_build_object('port', 'LIS', 'course', v_course),
               jsonb_build_object('port', 'LPA', 'course', jsonb_build_array(v_course->1, v_course->0))), null, null, 0);
    if coalesce((v_res->>'ok')::boolean, true) or v_res->>'error_code' <> 'E_SEA_CLOSED' then
      raise exception '0216 self-assert FAIL: lit, saving a route to Las Palmas answers %', left(v_res::text, 300);
    end if;
    -- reach_passage lit, title 1, a barca, NAVIGATION 5: every title-1 harbour and no other
    select count(*) into v_home from public.ports p join public.sea_zones z on z.code = public.harbour_zone(p.id)
     where p.kind = 'HARBOUR' and p.id <> v_lis and z.title_min = 1;
    for v_i in 1 .. 6 loop
      v_t0 := clock_timestamp();
      select count(*) filter (where r.nm is not null),
             count(*) filter (where r.nm is not null and (select z.title_min from public.sea_zones z where z.code = public.harbour_zone(r.port_id)) > 1)
        into v_reached, v_bad
        from voyage.reach_passage(v_player, v_fleet, v_lis) r;
      v_rp_lit := v_rp_lit || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
    end loop;
    if v_reached <> v_home or v_bad <> 0 then
      raise exception '0216 self-assert FAIL: lit, a title-1 barca reaches % harbours from Lisbon (% are title-1 water), % of them beyond title 1', v_reached, v_home, v_bad;
    end if;
    v_out := format('title 1 reaches %s harbours (every title-1 harbour)', v_reached);

    -- TITLE 3 (probe record: 10,000 d. of turnover, four harbours called): Las Palmas is open
    for v_i in 1 .. 2 loop
      perform public.credit(v_player, 'SELL', 5000, public.emit_event(v_player, 'SOLD', '{"probe": "0216"}'::jsonb));
    end loop;
    for c in select p.code from public.ports p where p.kind = 'HARBOUR' and p.code in ('FNC', 'OPO', 'CAD', 'SAF') loop
      perform public.emit_event(v_player, 'VOYAGE_REPORT', jsonb_build_object('to', c.code, 'total_nm', 100, 'probe', '0216'));
    end loop;
    v_title := public.title_level(v_player);
    if v_title <> 3 then
      raise exception '0216 self-assert FAIL: 10,000 d. and four harbours make title %, not 3', v_title;
    end if;
    if voyage.sail_refusal(v_fleet, v_lpa, null, v_nm, v_course) is not null then
      raise exception '0216 self-assert FAIL: at title 3 Las Palmas is still refused: %', voyage.sail_refusal(v_fleet, v_lpa, null, v_nm, v_course);
    end if;
    -- A NAU TO HAVANA: refused on the TITLE at 3 (the Americas ask 4), clear at 4, refused on the WAVE with two barcas
    v_fleet2 := public.form_fleet(v_player, 'Carreira 0216', v_lis);
    perform public.commission_ship(v_player, v_fleet2, 'nau', 'Nau 0216', true, true);
    update public.ships set water_t = 60, food_t = 60 where fleet_id = v_fleet2;
    v_nm := (select r.nm from voyage.reach_from(v_lis) r where r.port_id = v_hav);
    v_ref := public.passage_gate(v_player, v_fleet2, v_nm, v_hav, v_hcourse);
    if v_ref is null or v_ref->>'code' <> 'E_SEA_CLOSED' or (v_ref->'figures'->>'needs_title')::int <> 4 or (v_ref->'figures'->>'title')::int <> 3
       or (v_ref->'figures'->>'needs_wave')::int > 39 then
      raise exception '0216 self-assert FAIL: a nau at title 3 bound for Havana reads %', v_ref;
    end if;
    perform public.credit(v_player, 'SELL', 12500, public.emit_event(v_player, 'SOLD', '{"probe": "0216"}'::jsonb));
    for c in select p.code from public.ports p where p.kind = 'HARBOUR' and p.code in ('SVQ', 'SET', 'LPA', 'TEN', 'AGA') loop
      perform public.emit_event(v_player, 'VOYAGE_REPORT', jsonb_build_object('to', c.code, 'total_nm', 100, 'probe', '0216'));
    end loop;
    if public.title_level(v_player) <> 4 then
      raise exception '0216 self-assert FAIL: 22,500 d. and nine harbours make title %, not 4', public.title_level(v_player);
    end if;
    if public.passage_gate(v_player, v_fleet2, v_nm, v_hav, v_hcourse) is not null
       or voyage.sail_refusal(v_fleet2, v_hav, null, v_nm, v_hcourse) is not null then
      raise exception '0216 self-assert FAIL: a nau at title 4 is refused Havana: % / %',
        public.passage_gate(v_player, v_fleet2, v_nm, v_hav, v_hcourse), voyage.sail_refusal(v_fleet2, v_hav, null, v_nm, v_hcourse);
    end if;
    perform public.commission_ship(v_player, v_fleet2, 'barca', 'Barca I 0216', false, true);
    perform public.commission_ship(v_player, v_fleet2, 'barca', 'Barca II 0216', false, true);
    if public.fleet_wave(v_fleet2) <> 21 then
      raise exception '0216 self-assert FAIL: a nau and two barcas read %', public.fleet_wave(v_fleet2);
    end if;
    v_ref := voyage.sail_refusal(v_fleet2, v_hav, null, v_nm, v_hcourse);
    if v_ref is null or v_ref->>'code' <> 'E_SEA_CLOSED' or v_ref->'figures'->>'zone' <> 'NOR-MID'
       or (v_ref->'figures'->>'needs_wave')::int <> 30 or (v_ref->'figures'->>'wave')::numeric <> 21 or (v_ref->'figures'->>'title')::int <> 4
       or v_ref->>'sentence' not like '%your fleet holds 21' then
      raise exception '0216 self-assert FAIL: a nau with two barcas bound for Havana reads %', v_ref;
    end if;
    -- A MERCHANT IS EXEMPT AT THE DOOR (0107 d4 kept): a 999,999 nm leg into the Pacific, no refusal
    v_npc := public.new_house(null, 'Comptoir 0216', 'FRA', 'LIS', 'Flotte 0216', 'barca', 'Mouette 0216', 1000, true);
    if public.passage_gate(v_npc, (select f.id from public.fleets f where f.player_id = v_npc limit 1), 999999, v_hnl, null) is not null then
      raise exception '0216 self-assert FAIL: a merchant is refused at the door';
    end if;
    if public.passage_gate(null, null, 999999, v_hnl, null) is not null then
      raise exception '0216 self-assert FAIL: nobody is refused at the door';
    end if;
    -- TITLE 8 and a carrack of state (wave 75): reach_passage from Lisbon reaches every harbour
    perform public.credit(v_player, 'SELL', 100000, public.emit_event(v_player, 'SOLD', '{"probe": "0216"}'::jsonb));
    for c in select p.code from public.ports p where p.kind = 'HARBOUR' and p.code not in ('FNC', 'OPO', 'CAD', 'SAF', 'SVQ', 'SET', 'LPA', 'TEN', 'AGA') order by p.code limit 40 loop
      perform public.emit_event(v_player, 'VOYAGE_REPORT', jsonb_build_object('to', c.code, 'total_nm', 100, 'probe', '0216'));
    end loop;
    if public.title_level(v_player) < 8 then
      raise exception '0216 self-assert FAIL: 122,500 d. and 49 harbours make title %, not 8', public.title_level(v_player);
    end if;
    -- the probe's fleets: her two plus one more would pass fleet_max; the carrack joins the barca's fleet instead
    perform public.commission_ship(v_player, v_fleet, 'carraca', 'Madre 0216', false, true);
    delete from public.ships where fleet_id = v_fleet and name = 'Gaivota 0216';
    v_fleet3 := v_fleet;
    if public.fleet_wave(v_fleet3) <> 75 then
      raise exception '0216 self-assert FAIL: a carrack of state alone reads %', public.fleet_wave(v_fleet3);
    end if;
    select count(*) filter (where r.nm is not null), count(*) into v_reached, v_total from voyage.reach_passage(v_player, v_fleet3, v_lis) r;
    if v_reached <> v_total or v_total < 200 then
      raise exception '0216 self-assert FAIL: title 8 with a carrack reaches % of % harbours', v_reached, v_total;
    end if;
    v_out := v_out || format('; title 8 with a carrack of state reaches all %s', v_total);
    raise exception using errcode = 'ZX216', message = 'probe done';
  exception when sqlstate 'ZX216' then
    null;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid or company_name in ('Casa 0216', 'Comptoir 0216')) then
    raise exception '0216 self-assert FAIL: the probe survived its rollback';
  end if;
  if public.sea_conditions_on() then
    raise exception '0216 self-assert FAIL: the switch is lit after the probe';
  end if;
  -- the walls: the gate and the door are server-only; the registry is as it was; the board is still the client's
  if has_function_privilege('authenticated', 'public.passage_gate(uuid, uuid, numeric, uuid, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.passage_gate(uuid, uuid, numeric, uuid, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'voyage.sail_refusal(uuid, uuid, jsonb, numeric, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'voyage.reach_passage(uuid, uuid, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'world.good_board(uuid, uuid, uuid, numeric)', 'execute')
     or not has_function_privilege('authenticated', 'cmd.issue_lines(uuid, jsonb, integer)', 'execute') then
    raise exception '0216 self-assert FAIL: the walls do not hold';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0216)
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0216 self-assert FAIL: the registry moved or a row is not executable';
  end if;
  raise notice '0216 self-assert ok: THE PASSAGE GATE READS THE SEA (dark). Seven bodies re-cut and reversed (three re-signed, ACL and config restored). DARK: % gate / door / sail answers equal their pre-images for the probe and % human(s) (% refused E_REGION_CLOSED, the dark door exercised); reach_passage from Lisbon equal 6 × 6, the humans'' tables equal, the good board''s passages equal. LIT (rolled back): Funchal clear, Las Palmas E_SEA_CLOSED at Macaronesia (2 / 1, 10 / 12), the plan and the route refused up front; title 3 clears it; a nau at title 3 refused Havana on title, clear at 4, refused on wave at 21 with two barcas; a merchant and nobody exempt at the door; %. TIMING reach_passage dark old % → new % ms (last 3: % → %), lit % ms; good_board dark old % → new % ms. % ms in all.',
    v_cnt, v_hcnt, v_regions, v_out,
    round((select avg(x) from unnest(v_rp_old) x), 1), round((select avg(x) from unnest(v_rp_new) x), 1),
    round((select avg(x) from unnest(v_rp_old[4:6]) x), 1), round((select avg(x) from unnest(v_rp_new[4:6]) x), 1),
    round((select avg(x) from unnest(v_rp_lit) x), 1),
    round(coalesce((select avg(x) from unnest(v_gb_old) x), 0)), round(coalesce((select avg(x) from unnest(v_gb_new) x), 0)),
    round(extract(epoch from clock_timestamp() - (select t0 from t0_0216)) * 1000);
end $$;
