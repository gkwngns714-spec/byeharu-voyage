-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0139 — ANY HULL ENTERS ANY HARBOUR  (the draft gate is removed, entirely)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, in chat (2026-10-17): remove the draft restriction entirely — any hull may enter any
-- harbour.
--
-- ── WHERE DRAFT WAS A RULE ON PROD (pg_get_functiondef over public / cmd / world / voyage, read-only)
--   * voyage.sail_refusal — the E_DRAFT gate: the deepest hull's draft against the destination's
--     max_draft + city_level(docks) / docks_draft_per_levels (0036 → 0047 → 0050 → 0123).
--   * public.npc_feasible_legs — the merchants' leg filter `p.max_draft >= p_draft` (0120), fed by
--     public.npc_loop_candidates' `max(cl.draft)`.
--   * world_config `docks_draft_per_levels` — read by sail_refusal only (0123).
--   Everything else that names draft only SHOWS it: world.snapshot serves ports.max_draft,
--   world.ship_stats and world.building_yard serve a hull's draft; public.passage_gate and
--   voyage.settle mention it in comments. Those stay — a hull still sits as deep as it sits.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) voyage.sail_refusal: the E_DRAFT block and its two variables go. Ice (E_PORT_CLOSED) stays.
-- (2) public.npc_feasible_legs(port, speed, days) — the draft parameter and its filter go. The
--     signature changes, so it is dropped and created from its own re-cut pre-image with the same
--     owner, ACL, language, volatility, definer and search_path (asserted).
-- (3) public.npc_loop_candidates: no longer reads max(draft); its three calls lose the argument.
-- (4) the knob docks_draft_per_levels is deleted (it has no reader left — asserted). The docks work
--     now raises nothing a rule reads; that is the owner's ruling made visible, not hidden.
--
-- ── THE PROOF (in this file) ────────────────────────────────────────────────────────────────────
-- Every re-cut body reverses to its pre-image; ACL / volatility / definer / config / language /
-- owner unmoved. No function in public / cmd / world / voyage contains E_DRAFT, compares max_draft or
-- reads docks_draft_per_levels. A probe house (rolled back) with a hull of the deepest class, docked
-- at home, is refused E_DRAFT by the OLD body for a nearby harbour too shallow for it, and is NOT
-- refused by the new one (the stores margin neutralised inside the probe, so null is the answer).
-- npc_feasible_legs: for a spread of harbours × drafts × (speed, days), the new answer equals the old
-- answer at draft 0 (no filter), contains every old leg, and adds exactly the harbours shallower than
-- that draft. npc_loop_candidates equals its pre-image for every sampled merchant whose deepest hull
-- every harbour already took (the old filter was vacuous there). Timings: raise notice only.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE / DROP + CREATE FUNCTION; one DELETE on world_config; the probe's writes are
-- rolled back. No LOCK TABLE, no set role.
--
-- ROLLBACK: a forward migration restoring the three pre-image bodies (each is here as the hunks' OLD
-- text), npc_feasible_legs' four-argument signature and the knob row (value 2).
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once:
-- voyage.sail_refusal (0123), public.npc_feasible_legs (0120), public.npc_loop_candidates (0120/0129).
-- VERSION: 0139. Applies on prod head 0138 (0137, PR #142, touches none of these bodies).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0139(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0139 on commit drop as
select f.fn, f.new_fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proparallel from pg_proc p where p.oid = f.fn::regprocedure) as par,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner,
       (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = f.fn::regprocedure) as lang
  from (values ('voyage.sail_refusal(uuid, uuid, jsonb, numeric)', 'voyage.sail_refusal(uuid, uuid, jsonb, numeric)'),
               ('public.npc_feasible_legs(uuid, integer, numeric, integer)', 'public.npc_feasible_legs(uuid, numeric, integer)'),
               ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 'public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)')) f(fn, new_fn);

-- THE OLD COPIES, under pg_temp names, for the side-by-side proof. The old loop builder is pointed at
-- the old leg filter, so the old tree is closed.
do $$
declare
  v_def text;
begin
  v_def := replace((select def from defs_before_0139 where fn like 'voyage.sail_refusal%'),
                   'CREATE OR REPLACE FUNCTION voyage.sail_refusal(', 'CREATE OR REPLACE FUNCTION pg_temp.sail_refusal_old_0139(');
  if strpos(v_def, 'CREATE OR REPLACE FUNCTION pg_temp.sail_refusal_old_0139(') <> 1 then
    raise exception '0139 self-assert FAIL: the old copy of voyage.sail_refusal was not renamed';
  end if;
  execute v_def;
  v_def := replace((select def from defs_before_0139 where fn like 'public.npc_feasible_legs%'),
                   'CREATE OR REPLACE FUNCTION public.npc_feasible_legs(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_feasible_legs_old_0139(');
  if strpos(v_def, 'CREATE OR REPLACE FUNCTION pg_temp.npc_feasible_legs_old_0139(') <> 1 then
    raise exception '0139 self-assert FAIL: the old copy of public.npc_feasible_legs was not renamed';
  end if;
  execute v_def;
  v_def := replace(replace((select def from defs_before_0139 where fn like 'public.npc_loop_candidates%'),
                   'CREATE OR REPLACE FUNCTION public.npc_loop_candidates(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_loop_candidates_old_0139('),
                   'public.npc_feasible_legs(', 'pg_temp.npc_feasible_legs_old_0139(');
  if strpos(v_def, 'CREATE OR REPLACE FUNCTION pg_temp.npc_loop_candidates_old_0139(') <> 1
     or pg_temp.occurs_0139(v_def, 'pg_temp.npc_feasible_legs_old_0139(') <> 3
     or strpos(v_def, 'public.npc_feasible_legs(') > 0 then
    raise exception '0139 self-assert FAIL: the old copy of public.npc_loop_candidates was not renamed and pointed at the old leg filter';
  end if;
  execute v_def;
end $$;

-- ── 2. THE RE-CUTS (hunks: old = verbatim from the live bodies; new = what replaces it) ─────────
create temp table hunks_0139 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0139 values
('voyage.sail_refusal(uuid, uuid, jsonb, numeric)', 1,
$h$  v_flag  numeric;
  v_draft int;
  v_maxd  int;
  v_kind  text;$h$,
$h$  v_flag  numeric;
  v_kind  text;$h$),
('voyage.sail_refusal(uuid, uuid, jsonb, numeric)', 2,
$h$      select max(c.draft) into v_draft from public.ships s join public.ship_classes c on c.id = s.class_id
       where s.fleet_id = p_fleet;
      select max_draft into v_maxd from public.ports where id = p_dest;
      v_maxd := v_maxd + public.city_level(p_dest, 'docks') / public.wc_int('docks_draft_per_levels');   -- 0123
      if v_draft > v_maxd then
        return cmd.refusal('E_DRAFT', 'her deepest hull draws more than that quay takes',
                           cmd.figures(v_maxd, v_draft, 'depth'));
      end if;
$h$,
$h$      -- 0139: no draft gate — any hull enters any harbour (owner, 2026-10-17).
$h$),
('public.npc_feasible_legs(uuid, integer, numeric, integer)', 1,
$h$public.npc_feasible_legs(p_port uuid, p_draft integer, p_speed numeric, p_days integer)$h$,
$h$public.npc_feasible_legs(p_port uuid, p_speed numeric, p_days integer)$h$),
('public.npc_feasible_legs(uuid, integer, numeric, integer)', 2,
$h$  -- 0120: the known legs out of p_port (public.npc_known_legs) a fleet of draft p_draft and speed
  -- p_speed may sail with p_days of stores: a harbour that takes her draft, open (the two berth
  -- facts voyage.sail_refusal reads), and a passage her stores cover at endurance_margin, one day
  -- spare — the stores gate as the sail gate judges it. Nearest first, then the port id.$h$,
$h$  -- 0120: the known legs out of p_port (public.npc_known_legs) a fleet of speed p_speed may sail
  -- with p_days of stores: an open harbour (the berth fact voyage.sail_refusal reads; 0139 removed
  -- the draft gate — any hull enters any harbour), and a passage her stores cover at
  -- endurance_margin, one day spare — the stores gate as the sail gate judges it. Nearest first,
  -- then the port id.$h$),
('public.npc_feasible_legs(uuid, integer, numeric, integer)', 3,
$h$   where p.kind = 'HARBOUR' and p.max_draft >= p_draft and not p.is_ice_closed$h$,
$h$   where p.kind = 'HARBOUR' and not p.is_ice_closed$h$),
('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 1,
$h$-- returns home). Bounded by the knobs; every destination must be a harbour that takes her draft,
-- open, and within the days of stores she can carry.$h$,
$h$-- returns home). Bounded by the knobs; every destination must be an open harbour (0139: any hull
-- enters any harbour) within the days of stores she can carry.$h$),
('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 2,
$h$  v_days_cap int;
  v_draft   int;
  v_capacity numeric;$h$,
$h$  v_days_cap int;
  v_capacity numeric;$h$),
('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 3,
$h$  select max(cl.draft), coalesce(sum(public.ship_hold_capacity(s.id)), 0), coalesce(sum(s.crew), 0)
    into v_draft, v_capacity, v_crew$h$,
$h$  select coalesce(sum(public.ship_hold_capacity(s.id)), 0), coalesce(sum(s.crew), 0)
    into v_capacity, v_crew$h$),
('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 4,
$h$public.npc_feasible_legs(p_home, v_draft, p_speed, v_days_cap)$h$,
$h$public.npc_feasible_legs(p_home, p_speed, v_days_cap)$h$),
('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 5,
$h$public.npc_feasible_legs((b->>'port_id')::uuid, v_draft, p_speed, v_days_cap)$h$,
$h$public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap)$h$),
('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 6,
$h$public.npc_feasible_legs((v_xf->>'port_id')::uuid, v_draft, p_speed, v_days_cap)$h$,
$h$public.npc_feasible_legs((v_xf->>'port_id')::uuid, p_speed, v_days_cap)$h$);

create or replace function pg_temp.recut_0139(p_fn text)
returns text
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0139 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0139 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0139(v_def, h.old);
    if v_n <> 1 then
      raise exception '0139 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  return v_def;
end $$;

-- every hunk is checked against its live body BEFORE anything is dropped
create temp table recut_0139 on commit drop as
select fn, pg_temp.recut_0139(fn) as def from defs_before_0139;

-- (1) the sailing gate, (3) the loop builder: same signature, replaced in place
do $$
begin
  execute (select def from recut_0139 where fn = 'voyage.sail_refusal(uuid, uuid, jsonb, numeric)');
  execute (select def from recut_0139 where fn = 'public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)');
end $$;

-- (2) the leg filter: the signature changes, so drop and create, then give it EXACTLY the old
--     function's grants (read off its ACL here, not written out: they differ between a local chain
--     and prod, and the self-assert compares the ACL text)
create temp table grants_0139 on commit drop as
select a.grantee, a.privilege_type
  from pg_proc p cross join lateral aclexplode(p.proacl) a
 where p.oid = 'public.npc_feasible_legs(uuid, integer, numeric, integer)'::regprocedure
   and a.grantee <> p.proowner;
drop function public.npc_feasible_legs(uuid, integer, numeric, integer);
do $$
declare
  g record;
begin
  execute (select def from recut_0139 where fn = 'public.npc_feasible_legs(uuid, integer, numeric, integer)');
  revoke all on function public.npc_feasible_legs(uuid, numeric, integer) from public;
  for g in select a.grantee from pg_proc p cross join lateral aclexplode(p.proacl) a
            where p.oid = 'public.npc_feasible_legs(uuid, numeric, integer)'::regprocedure
              and a.grantee <> p.proowner loop
    execute format('revoke all on function public.npc_feasible_legs(uuid, numeric, integer) from %s',
                   case when g.grantee = 0 then 'public' else quote_ident(g.grantee::regrole::text) end);
  end loop;
  for g in select * from grants_0139 order by grantee loop
    execute format('grant %s on function public.npc_feasible_legs(uuid, numeric, integer) to %s', g.privilege_type,
                   case when g.grantee = 0 then 'public' else quote_ident(g.grantee::regrole::text) end);
  end loop;
end $$;

-- ── 3. THE PROOF — old and new side by side ────────────────────────────────────────────────────
create temp table proven_0139 (k text primary key, v text) on commit drop;

-- (a) THE PROBE HOUSE: a hull of the deepest class, at a harbour, bound for a harbour too shallow
--     for it. Old body: E_DRAFT. New body: not refused. Rolled back.
do $$
declare
  c_uid    constant uuid := '00000000-0139-4000-8000-000000000001';
  v_base   int;
  v_player uuid;
  v_fleet  uuid;
  v_home   uuid;
  v_dest   uuid;
  v_dcode  text;
  v_depth  int;
  v_cls    uuid;
  v_ccode  text;
  v_draft  int;
  v_nm     numeric;
  v_old    jsonb;
  v_new    jsonb;
  v_newm   jsonb;
begin
  select count(*) into v_base from public.players;
  begin
    v_player := public.new_house(c_uid, 'Casa do Calado 0139', 'PRT');
    select id, port_id into v_fleet, v_home from public.fleets where player_id = v_player;
    update public.fleets set status = 'DOCKED' where id = v_fleet;
    select c.id, c.code, c.draft into v_cls, v_ccode, v_draft
      from public.ship_classes c order by c.draft desc, c.code limit 1;
    update public.ships s set class_id = v_cls where s.fleet_id = v_fleet;
    update public.ships s set crew = c.crew_required from public.ship_classes c
     where c.id = s.class_id and s.fleet_id = v_fleet;
    -- the nearest open harbour her home roadstead knows whose quay (with its docks) is shallower
    -- than the hull
    select p.id, p.code, p.max_draft + public.city_level(p.id, 'docks') / public.wc_int('docks_draft_per_levels'),
           (sr.reaches->>p.code)::numeric
      into v_dest, v_dcode, v_depth, v_nm
      from public.sea_reaches sr
      join public.ports p on sr.reaches ? p.code
     where sr.port_id = v_home and p.kind = 'HARBOUR' and not p.is_ice_closed and p.id <> v_home
       and p.max_draft + public.city_level(p.id, 'docks') / public.wc_int('docks_draft_per_levels') < v_draft
     order by (sr.reaches->>p.code)::numeric, p.code limit 1;
    if v_dest is null then
      raise exception '0139 self-assert FAIL: the probe found no harbour shallower than a % (draft %) near its home', v_ccode, v_draft;
    end if;
    -- the old body, as it stood: refused on draft (the gate precedes the stores)
    v_old := pg_temp.sail_refusal_old_0139(v_fleet, v_dest, null, v_nm);
    -- the new body: with the stores margin neutralised (so the one remaining question is the berth),
    -- she is not refused at all; and with the real margin, whatever she is refused is not draft
    v_newm := voyage.sail_refusal(v_fleet, v_dest, null, v_nm);
    update public.world_config set value = to_jsonb(0) where key = 'endurance_margin';
    v_new := voyage.sail_refusal(v_fleet, v_dest, null, v_nm);
    raise exception 'ROLLBACK_0139';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0139' then raise; end if;
  end;
  if (select count(*) from public.players) <> v_base then
    raise exception '0139 self-assert FAIL: the probe did not leave the world as it found it';
  end if;
  if v_old is null or v_old->>'code' <> 'E_DRAFT' then
    raise exception '0139 self-assert FAIL: POSITIVE CONTROL — the old body did not refuse a % (draft %) for % (depth %) on draft: %',
      v_ccode, v_draft, v_dcode, v_depth, coalesce(v_old::text, '(allowed)');
  end if;
  if v_new is not null then
    raise exception '0139 self-assert FAIL: a % (draft %) was refused entry to % (depth %): %', v_ccode, v_draft, v_dcode, v_depth, v_new;
  end if;
  if v_newm is not null and v_newm->>'code' = 'E_DRAFT' then
    raise exception '0139 self-assert FAIL: the new body still refuses on draft: %', v_newm;
  end if;
  insert into proven_0139 values ('probe', format('a %s (draft %s) bound for %s (depth %s, %s nm): old body %s, new body not refused (real stores margin: %s)',
    v_ccode, v_draft, v_dcode, v_depth, round(v_nm), v_old->>'code', coalesce(v_newm->>'code', 'not refused')));
end $$;

-- (b) THE LEG FILTER: new = old at draft 0; old at draft d ⊆ new; new \ old(d) = the harbours shallower than d
create temp table legs_0139 on commit drop as
select h.id as port_id, d.d, x.speed, x.days,
       public.npc_feasible_legs(h.id, x.speed, x.days) as new_v,
       pg_temp.npc_feasible_legs_old_0139(h.id, 0, x.speed, x.days) as old0,
       pg_temp.npc_feasible_legs_old_0139(h.id, d.d, x.speed, x.days) as oldd
  from (select p.id from public.ports p where p.kind = 'HARBOUR' order by md5(p.id::text || '0139') limit 24) h
 cross join (select generate_series(1, (select max(draft) from public.ship_classes)) as d) d
 cross join (values (5::numeric, 60), (8::numeric, 20)) x(speed, days);

do $$
declare
  v_n     int;
  v_bad0  int;
  v_sub   int;
  v_extra int;
  v_more  int;
  v_rows  int;
begin
  select count(*), count(*) filter (where new_v::text is distinct from old0::text) into v_n, v_bad0 from legs_0139;
  if v_bad0 > 0 then
    raise exception '0139 self-assert FAIL: npc_feasible_legs — % of % answers differ from the old filter at draft 0', v_bad0, v_n;
  end if;
  -- every old leg is still offered
  select count(*) into v_sub
    from legs_0139 l cross join lateral jsonb_array_elements(l.oldd) o(x)
   where not exists (select 1 from jsonb_array_elements(l.new_v) n(y) where n.y = o.x);
  if v_sub > 0 then
    raise exception '0139 self-assert FAIL: npc_feasible_legs — % old leg(s) are no longer offered', v_sub;
  end if;
  -- what is added is exactly the harbours shallower than that draft
  select count(*) into v_extra
    from legs_0139 l
   where jsonb_array_length(l.new_v) - jsonb_array_length(l.oldd)
         <> (select count(*) from jsonb_array_elements(l.new_v) n(y)
               join public.ports p on p.id = (n.y->>'port_id')::uuid where p.max_draft < l.d);
  if v_extra > 0 then
    raise exception '0139 self-assert FAIL: npc_feasible_legs — % answer(s) add something other than the shallower harbours', v_extra;
  end if;
  select count(*) filter (where jsonb_array_length(new_v) > jsonb_array_length(oldd)),
         sum(jsonb_array_length(new_v))
    into v_more, v_rows from legs_0139;
  if v_more < 1 or coalesce(v_rows, 0) < 20 then
    raise exception '0139 self-assert FAIL: the leg comparison is vacuous (% answers grew, % legs)', v_more, v_rows;
  end if;
  insert into proven_0139 values ('legs', format('%s answers (24 harbours × drafts × 2 stores): = the old filter at draft 0; ⊇ the old answer at every draft; %s grew, each by exactly its shallower harbours (%s legs in all)',
    v_n, v_more, v_rows));
end $$;

-- (c) THE LOOP BUILDER: for every sampled merchant whose deepest hull every harbour already took,
--     the old filter was vacuous — so the new answer is the old one, row for row
create temp table loops_0139 on commit drop as
select z.route_id, z.fleet_id, z.home, z.speed,
       (select coalesce(jsonb_agg(jsonb_build_array(c.stops, c.kind)), '[]'::jsonb)
          from public.npc_loop_candidates(z.route_id, z.fleet_id, z.home, 1e9, z.speed) c) as new_v,
       (select coalesce(jsonb_agg(jsonb_build_array(c.stops, c.kind)), '[]'::jsonb)
          from pg_temp.npc_loop_candidates_old_0139(z.route_id, z.fleet_id, z.home, 1e9, z.speed) c) as old_v
  from (select sr.id as route_id, f.fleet_id,
               (select s.port_id from public.standing_route_stops s where s.route_id = sr.id order by s.ord limit 1) as home,
               greatest(coalesce(voyage.fleet_speed(f.fleet_id), 0), 0.1) as speed
          from public.standing_routes sr
          join public.players p on p.id = sr.player_id and p.is_npc
          cross join lateral (select coalesce(sr.fleet_id, (select nf.fleet_id from public.npc_fleets nf where nf.route_id = sr.id limit 1)) as fleet_id) f
         where f.fleet_id is not null
           and (select count(*) from public.standing_route_stops s where s.route_id = sr.id) >= 2
           and (select max(c.draft) from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = f.fleet_id)
               <= (select min(max_draft) from public.ports where kind = 'HARBOUR')
         order by md5(sr.id::text || '0139'), sr.id
         limit 12) z;

do $$
declare
  v_n   int;
  v_bad int;
  v_t0  timestamptz;
  v_old numeric;
  v_new numeric;
  i     int;
begin
  select count(*), count(*) filter (where new_v::text is distinct from old_v::text) into v_n, v_bad from loops_0139;
  if v_bad > 0 then
    raise exception '0139 self-assert FAIL: npc_loop_candidates — % of % merchants'' loops differ from the pre-image where the old filter was vacuous', v_bad, v_n;
  end if;
  if v_n > 0 and (select sum(jsonb_array_length(new_v)) from loops_0139) < 1 then
    raise exception '0139 self-assert FAIL: the loop comparison is vacuous (% merchants, no loops)', v_n;
  end if;
  -- timing, reported only (faster of two passes)
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    perform (select count(*) from pg_temp.npc_loop_candidates_old_0139(route_id, fleet_id, home, 1e9, speed)) from loops_0139;
    v_old := least(coalesce(v_old, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    v_t0 := clock_timestamp();
    perform (select count(*) from public.npc_loop_candidates(route_id, fleet_id, home, 1e9, speed)) from loops_0139;
    v_new := least(coalesce(v_new, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  end loop;
  insert into proven_0139 values ('loops', format('%s shallow-hulled merchants'' candidate loops (%s in all) = the pre-image; timing old %s ms, new %s ms (reported, not gated)',
    v_n, (select coalesce(sum(jsonb_array_length(new_v)), 0) from loops_0139), v_old, v_new));
end $$;

-- ── 4. THE KNOB GOES (after the probe, which read it for the old body) ──────────────────────────
delete from public.world_config where key = 'docks_draft_per_levels';

-- ── 5. SELF-ASSERT (catalogue reads) ─────────────────────────────────────────────────────────────
do $$
declare
  d      record;
  h      record;
  p      record;
  v_def  text;
  v_back text;
  v_rev  int := 0;
  v_left text;
begin
  -- every body moved as the header says and reverses to its pre-image; ACL, owner, language,
  -- volatility, definer, config and parallel safety unmoved
  for d in select * from defs_before_0139 order by fn loop
    v_def  := replace(pg_get_functiondef(d.new_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0139 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0139(v_back, h.new) <> 1 then
        raise exception '0139 self-assert FAIL: hunk % of % is not in the live body once', h.n, d.fn;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back is distinct from d.def or v_def = d.def then
      raise exception '0139 self-assert FAIL: % does not reverse to its pre-image', d.new_fn;
    end if;
    v_rev := v_rev + 1;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, pr.proowner as owner,
           coalesce(pr.proconfig::text, '') as cfg, pr.proparallel as par, l.lanname as lang
      into p from pg_proc pr join pg_language l on l.oid = pr.prolang where pr.oid = d.new_fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.par <> d.par
       or p.lang <> d.lang or p.owner <> d.owner then
      raise exception '0139 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer, config, parallel safety or language',
        d.new_fn, d.acl, p.acl;
    end if;
  end loop;
  if v_rev <> 3 then
    raise exception '0139 self-assert FAIL: % bodies checked, not 3', v_rev;
  end if;
  if to_regprocedure('public.npc_feasible_legs(uuid, integer, numeric, integer)') is not null
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'npc_feasible_legs') <> 1 then
    raise exception '0139 self-assert FAIL: npc_feasible_legs is not exactly one function, the three-argument one';
  end if;
  if has_function_privilege('anon', 'public.npc_feasible_legs(uuid, numeric, integer)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_feasible_legs(uuid, numeric, integer)', 'execute') then
    raise exception '0139 self-assert FAIL: public.npc_feasible_legs is callable by a client';
  end if;

  -- NO RULE READS DRAFT: no body in public / cmd / world / voyage refuses E_DRAFT, compares a
  -- port's max_draft, reads the docks knob, or still calls the four-argument leg filter
  select string_agg(n.nspname || '.' || pr.proname, ', ' order by n.nspname, pr.proname) into v_left
    from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and (pr.prosrc like '%E_DRAFT%'
          or pr.prosrc ~ 'max_draft\s*(<|>|=|<=|>=|<>)'
          or pr.prosrc ~ '(<|>|=|<=|>=|<>)\s*(\w+\.)?max_draft'
          or pr.prosrc like '%max_draft into%'
          or pr.prosrc like '%docks_draft_per_levels%'
          or pr.prosrc ~ 'npc_feasible_legs\([^)]*v_draft');
  if v_left is not null then
    raise exception '0139 self-assert FAIL: a body still reads draft as a rule: %', v_left;
  end if;
  if exists (select 1 from public.world_config where key = 'docks_draft_per_levels') then
    raise exception '0139 self-assert FAIL: the knob docks_draft_per_levels is still there';
  end if;

  raise notice '0139 self-assert ok: ANY HULL ENTERS ANY HARBOUR. PROBE %. LEGS %. LOOPS %. BODIES: voyage.sail_refusal has no draft gate (ice stays); public.npc_feasible_legs(port, speed, days) has no draft parameter or filter (dropped and created, owner / ACL / definer / search_path unmoved); public.npc_loop_candidates no longer reads draft; 3 bodies reverse to their pre-images; no function in public / cmd / world / voyage refuses E_DRAFT, compares max_draft or reads docks_draft_per_levels; the knob is gone.',
    (select v from proven_0139 where k = 'probe'), (select v from proven_0139 where k = 'legs'),
    (select v from proven_0139 where k = 'loops');
end $$;
