-- ═══════════════════════════════════════════════════════════════════════════════════════════════════
-- 0392 - A MERCHANT SAILS THE SEAS HER HULL CAN HOLD  (slice S3 of docs/SEA_CONDITIONS_AND_REGIONS.md; owner row 166). DARK behind its own switch.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing a player can see changes; the file that lights sea_conditions_bite_npc carries the news)
--
-- THE OWNER (docs/OWNER_REQUESTS.md row 166, 2026-10-20): far seas ask a title and the fleet's wave resistance, a hard wall, and "NPCs under the same rule":
-- small-ship houses drop far loops at their next review, carrack houses keep them, fleets at sea finish their trip (the design's header and section 4).
-- 0215 built the data and the one rule (public.sea_refusal), 0216 the player's gate. THIS FILE IS S3 AND NOTHING ELSE: the merchant planner asks the same
-- rule. No switch is lit, no knob moved, no house founded (S4, the far traders, is not here), nothing a player reads changes.
--
-- WHAT LANDS (everything behind public.sea_conditions_npc_on(); with it false the planner offers and chooses byte for byte what it did before this file)
--   * THE SWITCH sea_conditions_bite_npc (false) and its one reader public.sea_conditions_npc_on(), written as public.sea_conditions_on() is. It is
--     independent of sea_conditions_bite (the players' switch): either may be lit without the other.
--   * A MERCHANT IS JUDGED ON WAVE ONLY (the design's Q3: she has no title). public.npc_sea_shut(wave, dest, course) is public.sea_refusal(null, wave, zones)
--     over the zones public.sea_gate gathers for a player: every zone the leg's course crosses and the destination harbour's own. The comparison is written
--     nowhere here: the one rule answers.
--   * THE ZONES OF A KNOWN COURSE ARE REMEMBERED. Sampling a course costs about 2 ms and a lap start prices some 150 known legs, so public.npc_course_zones(course)
--     reads public.npc_course_zones_memo (keyed by the md5 of the course's own text, so no route save can make a row stale) and falls back to
--     public.course_zones, the one sampler, for a course it has not seen. public.npc_course_zones_fill() writes the memo from that same sampler for every
--     course of public.npc_courses and of every merchant route, both ways (a known leg is also sailed backwards); it is run here once and must be run again
--     by any file that changes public.sea_zones or its boxes (the proof holds every memo row to the sampler).
--   * public.npc_feasible_legs GAINS THE FLEET (port, fleet, speed, days): lit, a known leg whose seas her hull cannot hold is not feasible, so it is in no
--     loop offered to her. The three-argument function is dropped; its one caller, public.npc_loop_candidates, passes p_fleet at its three call sites.
--   * public.npc_plan: lit, her PRESENT loop with a leg her hull cannot hold (public.npc_loop_sea_shut) is unsailable in 0203's own sense (v_unsail): it is
--     never bought into, it loses to any loop that can be sailed, and it is reviewed at that lap start, not at the sixth (the candidates are fetched at once).
--     A merchant with nothing sailable that pays waits in port, as she does today when nothing pays (0181).
--   * THE SAIL DOOR IS NOT TOUCHED: public.passage_gate keeps its is_npc exemption (0107), so a merchant at sea or mid-lap is never refused a departure and
--     finishes her trip. Only the planner judges her, and only when it plans.
--
-- THE RE-CUTS (hunks sliced from the LIVE bodies of the cached head after 0367; each hunk occurs exactly once and reverses to its pre-image; ACL, volatility,
-- definer, config, parallel safety, owner and language unmoved): public.npc_loop_candidates (last cut by 0120, 0186, 0264, 0341: three hunks, each the call of
-- npc_feasible_legs inside a line 0341 wrapped), public.npc_plan (last cut by 0142, 0150, 0152, 0181, 0186, 0203: three hunks, on 0203's and 0186's lines).
-- Dropped and recreated with one more argument: public.npc_feasible_legs (0120, 0139, 0203). New: public.sea_conditions_npc_on, public.npc_course_zones,
-- public.npc_course_zones_fill, public.npc_sea_shut, public.npc_loop_sea_shut; the table public.npc_course_zones_memo (server-only); one knob.
-- NOT touched: public.sea_refusal, public.sea_gate, public.passage_gate, public.course_zones, public.fleet_wave, any world.* read, any cmd.* door.
--
-- ALL OR NOTHING: the whole file is ONE `do` block. statement_timeout 90 s and lock_timeout 5 s are its first act; BUDGET 45 s on prod (the memo's fill is
-- the cost: one public.course_zones a distinct course, about 2,500 of them; locally about 6 s). LOCKS: CREATE TABLE, DROP/CREATE FUNCTION, two CREATE OR
-- REPLACE; no ALTER on a live table, no lock on fleets, ships or routes.
-- COST while dark: public.npc_feasible_legs reads the switch once a call (an InitPlan); public.npc_plan reads it once a fleet. Measured in the dev-log.
--
-- SELF-ASSERT (this block): every hunk once and reversing; no other function moved (md5 over every one); the new functions server-only, definer, pinned, of
-- the declared volatility; only the one knob added; the memo equal to the sampler on a sample; OFF = UNCHANGED on a bounded sample: the feasible legs of 48
-- merchant fleets spread over hull sizes and seas, digested before the cut (the old function) and after it (the new one, switch off), are the same text; and,
-- with the switch lit INSIDE A PROBE THAT ROLLS BACK, a caravel's feasible legs out of a European harbour lose the Western Ocean and keep her coast, and the
-- door still answers null for a merchant. THE LIVE PATHS (the planner dropping a closed loop, a nau keeping the Atlantic, a barca keeping her coast, a
-- merchant mid-voyage not refused, dark parity of a real plan pass) ARE PROVED IN CI by scripts/db/proofs/92_a_merchant_sails_the_seas_her_hull_can_hold.sql
-- and locally by scripts/ops/harness/sea-merchants/ (proof-0392.mjs: the dark scene equal before and after; sim.mjs: every merchant planned lit and dark).
--
-- ROLLBACK: the switch (sea_conditions_bite_npc false, owner only): at once every feasible-leg set and every plan is what it was before this file. The
-- rest, forward, a NEW migration, owner only: scripts/ops/harness/sea-merchants/rollback-0392.sql (a draft).
-- VERSION: 0392. 0391 is held by the players' side of the same design (a wall says what is short); neither file reads the other.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_fns        constant text[] := array['sea_conditions_npc_on', 'npc_course_zones', 'npc_course_zones_fill', 'npc_sea_shut', 'npc_loop_sea_shut', 'npc_feasible_legs'];
  v_t0         timestamptz := clock_timestamp();
  v_ms         jsonb := '{}'::jsonb;
  v_n          int;
  v_x          int;
  v_def        text;
  v_rev        text;
  v_fn_before  text;
  v_cfg_before text;
  v_cfg_probe  text;
  v_entry      int;
  v_legs_before text;
  v_legs_after  text;
  v_memo       int;
  v_lit        jsonb;
  v_dark       jsonb;
  v_car        uuid;
  v_port       uuid;
  r_d          record;
  r_hk         record;
  r_x          record;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: nothing of this file exists, and the premises it was cut against hold (else NOTHING is applied) ──
  if to_regprocedure('public.sea_conditions_npc_on()') is not null or to_regprocedure('public.npc_course_zones(jsonb)') is not null
     or to_regprocedure('public.npc_sea_shut(numeric, uuid, jsonb)') is not null or to_regprocedure('public.npc_loop_sea_shut(uuid, jsonb)') is not null
     or to_regprocedure('public.npc_feasible_legs(uuid, uuid, numeric, integer)') is not null or to_regclass('public.npc_course_zones_memo') is not null
     or exists (select 1 from public.world_config where key = 'sea_conditions_bite_npc') then
    raise exception '0392 refuses: the merchants'' sea rule is already in this world';
  end if;
  if to_regprocedure('public.sea_refusal(integer, numeric, text[])') is null or to_regprocedure('public.course_zones(jsonb)') is null
     or to_regprocedure('public.harbour_zone(uuid)') is null or to_regprocedure('public.fleet_wave(uuid)') is null
     or to_regprocedure('public.sea_conditions_on()') is null or to_regprocedure('public.npc_feasible_legs(uuid, numeric, integer)') is null
     or to_regprocedure('public.npc_known_legs(uuid)') is null or to_regprocedure('public.npc_leg_days(numeric, numeric)') is null
     or to_regprocedure('public.npc_legs_open(jsonb, uuid)') is null or to_regprocedure('public.passage_gate(uuid, uuid, numeric, uuid, jsonb)') is null
     or to_regclass('public.npc_courses') is null or to_regclass('public.sea_zones') is null
     or not exists (select 1 from public.world_config where key = 'sea_conditions_bite') then
    raise exception '0392 refuses: a function, table or knob this file reads is not in this world (0215 the seas, 0216 the gate, 0120 and 0203 the planner, 0341 the pirate homes)';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_entry := (select count(*) from public.client_rpc_entry_points());
  create temp table defs_0392 on commit drop as
  select f.fn, f.ord, p.oid,
         replace(pg_get_functiondef(p.oid), E'\r', '') as def,
         coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef,
         coalesce(p.proconfig::text, '') as cfg, p.proparallel as par, p.proowner as owner, l.lanname as lang
    from (values
      ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 1),
      ('public.npc_plan(timestamp with time zone, uuid)', 2)) f(fn, ord)
    join pg_proc p on p.oid = to_regprocedure(f.fn)
    join pg_language l on l.oid = p.prolang;
  if (select count(*) from defs_0392) <> 2 then
    raise exception '0392 self-assert FAIL: % of the 2 bodies this file re-cuts are in this world', (select count(*) from defs_0392);
  end if;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> all (select t.oid from defs_0392 t)
     and p.oid <> to_regprocedure('public.npc_feasible_legs(uuid, numeric, integer)');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  create temp table xact0_0392 on commit drop as
  select s.relname::text as relname, s.n_tup_ins, s.n_tup_upd, s.n_tup_del from pg_stat_xact_user_tables s;

  -- THE SAMPLE OF "OFF = UNCHANGED": 48 merchant fleets, 16 of each hull size where the world has them, spread over the roster; each one's feasible legs
  -- out of the first stop of her loop at her own speed, with 10 days of stores (the stores test binds) and with 60, read through the OLD function now and
  -- through the new one after the cut.
  create temp table sample_0392 on commit drop as
  select q.fleet_id, q.port_id, q.speed
    from (select nf.fleet_id,
                 (select st.port_id from public.standing_route_stops st where st.route_id = nf.route_id order by st.ord limit 1) as port_id,
                 greatest(coalesce(voyage.fleet_speed_at(nf.fleet_id, 1), 0), 0.1) as speed,
                 row_number() over (partition by sz.size order by nf.roster_ord) as k, count(*) over (partition by sz.size) as of
            from public.npc_fleets nf
            cross join lateral (select max(cp.size) as size from public.ships s join public.ship_classes c on c.id = s.class_id
                                  join public.class_profile cp on cp.class_code = c.code where s.fleet_id = nf.fleet_id) sz
           where nf.route_id is not null and sz.size is not null) q
   where q.port_id is not null and (q.k - 1) % greatest(q.of / 16, 1) = 0 and (q.k - 1) / greatest(q.of / 16, 1) < 16;
  select md5(coalesce(string_agg(s.fleet_id::text || ':' || public.npc_feasible_legs(s.port_id, s.speed, 10)::text || public.npc_feasible_legs(s.port_id, s.speed, 60)::text, ';' order by s.fleet_id), '')) into v_legs_before
    from sample_0392 s;
  v_ms := v_ms || jsonb_build_object('pre', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 2. THE SWITCH ──
  insert into public.world_config (key, value, description) values
    ('sea_conditions_bite_npc', 'false'::jsonb, '0392 (docs/SEA_CONDITIONS_AND_REGIONS.md, S3): THE switch of the sea conditions for MERCHANTS. false = the merchant planner is what it was before 0392; true = a known leg whose seas ask more wave resistance than her fleet holds is not offered to her, and a present loop with such a leg is unsailable (public.npc_plan). A merchant has no title; the sail door never refuses her. Independent of sea_conditions_bite. Owner only.');

  execute $f$
create function public.sea_conditions_npc_on()
returns boolean
language sql
stable
as $body$
  -- 0392: THE switch of the sea conditions for merchants, read as public.sea_conditions_on reads the players' own: a plain SQL read of world_config,
  -- inlinable, missing row = off.
  select coalesce((select c.value = 'true'::jsonb from public.world_config c where c.key = 'sea_conditions_bite_npc'), false)
$body$
  $f$;
  revoke all on function public.sea_conditions_npc_on() from public, anon, authenticated;
  comment on function public.sea_conditions_npc_on() is '0392 (S3): THE one reader of sea_conditions_bite_npc. Server-only.';

  -- ── 3. THE MEMO OF A KNOWN COURSE'S ZONES ──
  create table public.npc_course_zones_memo (
    course_md5 text primary key,
    zones      text[] not null
  );
  comment on table public.npc_course_zones_memo is
    '0392 (S3): the zones a merchant course crosses, remembered: public.course_zones (the one sampler) of every course of public.npc_courses and of every merchant route, both ways, keyed by md5(course::text). Derived, never authored: written by public.npc_course_zones_fill only, read by public.npc_course_zones only. A file that changes public.sea_zones or its boxes runs the fill again. Server-only.';
  alter table public.npc_course_zones_memo enable row level security;
  revoke all on table public.npc_course_zones_memo from public, anon, authenticated;

  execute $f$
create function public.npc_course_zones(p_course jsonb)
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0392 (S3): THE ZONES A MERCHANT'S COURSE CROSSES: the memo's row for this very course (its own text is the key), else public.course_zones, the one
  -- sampler the sail door reads. The memo holds what that sampler answered; a course it has not seen is sampled, so the answer is the sampler's either way.
  select coalesce((select m.zones from public.npc_course_zones_memo m where m.course_md5 = md5(p_course::text)), public.course_zones(p_course))
$body$
  $f$;
  revoke all on function public.npc_course_zones(jsonb) from public, anon, authenticated;
  comment on function public.npc_course_zones(jsonb) is '0392 (S3): the zones a merchant course crosses, from the memo or the one sampler. Server-only.';

  execute $f$
create function public.npc_course_zones_fill()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0392 (S3): WRITE THE MEMO AFRESH from the one sampler: every course the merchant planner can be handed (public.npc_known_legs: the courses the world has
-- held, and every merchant route's legs), forwards and backwards (a known leg is also sailed the other way: the same water, so the same zones). Returns the
-- rows written. Run by 0392 once; run it again whenever public.sea_zones or its boxes change.
declare
  v_n int;
begin
  delete from public.npc_course_zones_memo;
  with c as (
    select distinct x.course
      from (select nc.course from public.npc_courses nc
            union all
            select st.course
              from public.standing_route_stops st
              join public.standing_routes sr on sr.id = st.route_id
              join public.players p on p.id = sr.player_id and p.is_npc) x
     where jsonb_typeof(x.course) = 'array' and jsonb_array_length(x.course) > 0),
  z as materialized (
    select c.course, public.course_zones(c.course) as zones from c)
  insert into public.npc_course_zones_memo (course_md5, zones)
  select distinct on (k.h) k.h, k.zones
    from (select md5(z.course::text) as h, z.zones from z
          union all
          select md5((select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(z.course) with ordinality t(x, i))::text), z.zones from z) k
   order by k.h;
  get diagnostics v_n = row_count;
  return v_n;
end
$body$
  $f$;
  revoke all on function public.npc_course_zones_fill() from public, anon, authenticated;
  comment on function public.npc_course_zones_fill() is '0392 (S3): rewrites public.npc_course_zones_memo from public.course_zones. Server-only; a migration that changes the sea zones calls it.';
  v_memo := public.npc_course_zones_fill();
  v_ms := v_ms || jsonb_build_object('memo', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 4. THE MERCHANT'S READING OF THE ONE RULE ──
  execute $f$
create function public.npc_sea_shut(p_wave numeric, p_dest uuid, p_course jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0392 (S3, the design's Q3): MAY A MERCHANT FLEET OF THIS WAVE RESISTANCE SAIL THIS LEG? Null when she may; otherwise public.sea_refusal's own refusal.
  -- The zones are the ones public.sea_gate gathers for a player: every zone the course crosses and the destination harbour's own. Her title is null (a
  -- merchant has none), so the one rule judges the wave alone. Nothing is compared here. It does not read the switch: its callers do.
  select public.sea_refusal(null, p_wave, public.npc_course_zones(p_course) || array_remove(array[public.harbour_zone(p_dest)], null))
$body$
  $f$;
  revoke all on function public.npc_sea_shut(numeric, uuid, jsonb) from public, anon, authenticated;
  comment on function public.npc_sea_shut(numeric, uuid, jsonb) is '0392 (S3): the one rule (public.sea_refusal) asked of a merchant leg on wave only. Server-only.';

  execute $f$
create function public.npc_loop_sea_shut(p_fleet uuid, p_loop jsonb)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0392 (S3): HAS THIS LOOP A LEG HER HULL CANNOT HOLD? p_loop is public.npc_plan's own shape: [{port_id, code, course, nm}], stop i's course the leg to
  -- stop i + 1, the last leg home. Her wave is read once. It does not read the switch: public.npc_plan does.
  select exists (
    select 1
      from jsonb_array_elements(p_loop) with ordinality a(x, i)
      join jsonb_array_elements(p_loop) with ordinality b(x, i) on b.i = a.i % jsonb_array_length(p_loop) + 1
     where public.npc_sea_shut((select public.fleet_wave(p_fleet)), (b.x->>'port_id')::uuid, a.x->'course') is not null)
$body$
  $f$;
  revoke all on function public.npc_loop_sea_shut(uuid, jsonb) from public, anon, authenticated;
  comment on function public.npc_loop_sea_shut(uuid, jsonb) is '0392 (S3): whether a merchant loop has a leg whose seas her fleet''s wave resistance cannot hold. Server-only.';

  drop function public.npc_feasible_legs(uuid, numeric, integer);
  execute $f$
create function public.npc_feasible_legs(p_port uuid, p_fleet uuid, p_speed numeric, p_days integer)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0120: the known legs out of p_port (public.npc_known_legs) a fleet of speed p_speed may sail
  -- with p_days of stores: an open harbour (the berth fact voyage.sail_refusal reads; 0139 removed
  -- the draft gate — any hull enters any harbour), and a passage her stores cover at
  -- endurance_margin, one day spare — the stores gate as the sail gate judges it. Nearest first,
  -- then the port id.
  -- 0392 (S3): AND, WHILE THE SEA CONDITIONS BITE FOR MERCHANTS, a leg whose seas her hull can hold (public.npc_sea_shut: the one rule, on wave only). The
  -- function gained p_fleet for it. The switch and her wave are read once a call; with the switch off the leg's seas are never read.
  -- The legs the old rule allows are gathered first (a materialised step: the sea is asked of those legs only, once each, whatever the planner would prefer).
  with legs as materialized (
    select l.to_port, l.code, l.course, l.nm
      from public.npc_known_legs(p_port) l
      join public.ports p on p.id = l.to_port
     where p.kind = 'HARBOUR' and not p.is_ice_closed
       and public.npc_leg_days(l.nm, p_speed) <= p_days)   -- 0203: the door's measure (voyage.stores_need_days), one day spare
  select coalesce(jsonb_agg(jsonb_build_object('port_id', l.to_port, 'code', l.code, 'course', l.course, 'nm', l.nm)
                            order by l.nm, l.to_port), '[]'::jsonb)
    from legs l
   where case when (select public.sea_conditions_npc_on())
              then public.npc_sea_shut((select public.fleet_wave(p_fleet)), l.to_port, l.course) is null
              else true end
$body$
  $f$;
  revoke all on function public.npc_feasible_legs(uuid, uuid, numeric, integer) from public, anon, authenticated;
  v_ms := v_ms || jsonb_build_object('fns', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 5. THE RE-CUTS: hunks sliced from the live bodies ──
  create temp table hunks_0392 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0392 values
  ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 1,
$h$public.npc_feasible_legs(p_home, p_speed, v_days_cap)$h$,
$h$public.npc_feasible_legs(p_home, p_fleet, p_speed, v_days_cap)$h$),
  ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 2,
$h$public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap)$h$,
$h$public.npc_feasible_legs((b->>'port_id')::uuid, p_fleet, p_speed, v_days_cap)$h$),
  ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 3,
$h$public.npc_feasible_legs((t->>'d')::uuid, p_speed, v_days_cap)$h$,
$h$public.npc_feasible_legs((t->>'d')::uuid, p_fleet, p_speed, v_days_cap)$h$),
  ('public.npc_plan(timestamp with time zone, uuid)', 1,
$h$  v_notes   jsonb := '[]'::jsonb;
begin
  if not public.npc_traders_on() then
$h$,
$h$  v_notes   jsonb := '[]'::jsonb;
  v_sea     boolean := false;   -- 0392 (S3): her present loop has a leg her hull cannot hold (only while sea_conditions_bite_npc is on)
begin
  if not public.npc_traders_on() then
$h$),
  ('public.npc_plan(timestamp with time zone, uuid)', 2,
$h$        v_unsail := coalesce(v_unsail, true);
$h$,
$h$        v_unsail := coalesce(v_unsail, true);
        -- 0392 (S3, docs/SEA_CONDITIONS_AND_REGIONS.md section 4): WHILE THE SEA CONDITIONS BITE FOR MERCHANTS, HER PRESENT LOOP WITH A LEG HER HULL CANNOT
        -- HOLD IS UNSAILABLE (public.npc_loop_sea_shut: the one rule, on wave only). The loops on offer need no such test: public.npc_feasible_legs never
        -- offers her such a leg. The sail door stays exempt for a merchant, so she finishes the lap she is on.
        if i = 0 then
          v_sea := public.sea_conditions_npc_on() and public.npc_loop_sea_shut(r.fleet_id, v_loop);
          v_unsail := v_unsail or v_sea;
        end if;
$h$),
  ('public.npc_plan(timestamp with time zone, uuid)', 3,
$h$        if i = 0 and v_choose and (v_net <= 0 or v_off or sr.lap_no % greatest(v_review, 1) = 0) then
$h$,
$h$        if i = 0 and v_choose and (v_net <= 0 or v_off or v_sea or sr.lap_no % greatest(v_review, 1) = 0) then   -- 0392 (S3): a loop the sea closes to her is reviewed at this lap start, not at the next review lap
$h$);

  if (select count(distinct h.fn) from hunks_0392 h) <> (select count(*) from defs_0392)
     or exists (select 1 from hunks_0392 h where h.fn not in (select t.fn from defs_0392 t)) then
    raise exception '0392 self-assert FAIL: a pre-imaged body has no hunk, or a hunk names a body not pre-imaged';
  end if;
  for r_d in select * from defs_0392 t order by t.ord loop
    v_def := r_d.def;
    for r_hk in select * from hunks_0392 h where h.fn = r_d.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, r_hk.old, ''))) / length(r_hk.old);
      if v_n <> 1 then
        raise exception '0392 self-assert FAIL: hunk % of % occurs % time(s), not once: the live body is not what this file was cut against', r_hk.ord, r_hk.fn, v_n;
      end if;
      v_def := replace(v_def, r_hk.old, r_hk.new);
    end loop;
    execute v_def;
  end loop;
  v_ms := v_ms || jsonb_build_object('recut', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 6. THE SELF-ASSERT ──
  -- 6a every re-cut reverses to its pre-image; attributes unmoved
  for r_d in select * from defs_0392 t order by t.ord loop
    v_rev := replace(pg_get_functiondef(r_d.oid), E'\r', '');
    for r_hk in select * from hunks_0392 h where h.fn = r_d.fn order by h.ord desc loop
      v_n := (length(v_rev) - length(replace(v_rev, r_hk.new, ''))) / length(r_hk.new);
      if v_n <> 1 then
        raise exception '0392 self-assert FAIL: % - the new text of hunk % is not in the live body exactly once', r_d.fn, r_hk.ord;
      end if;
      v_rev := replace(v_rev, r_hk.new, r_hk.old);
    end loop;
    if v_rev <> r_d.def then
      raise exception '0392 self-assert FAIL: % does not reverse to its pre-image', r_d.fn;
    end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = r_d.oid) <> r_d.acl
       or (select p.provolatile from pg_proc p where p.oid = r_d.oid) <> r_d.vol
       or (select p.prosecdef from pg_proc p where p.oid = r_d.oid) <> r_d.secdef
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = r_d.oid) <> r_d.cfg
       or (select p.proparallel from pg_proc p where p.oid = r_d.oid) <> r_d.par
       or (select p.proowner from pg_proc p where p.oid = r_d.oid) <> r_d.owner
       or (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = r_d.oid) <> r_d.lang then
      raise exception '0392 self-assert FAIL: % - ACL, volatility, definer, config, parallel safety, owner or language moved', r_d.fn;
    end if;
  end loop;

  -- 6b no other function moved; the new ones are server-only, of the declared volatility; the three-argument npc_feasible_legs is gone; one knob, false
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> all (select t.oid from defs_0392 t)
         and not (n.nspname = 'public' and p.proname = any (c_fns))) is distinct from v_fn_before then
    raise exception '0392 self-assert FAIL: a function this file does not re-cut moved';
  end if;
  if to_regprocedure('public.npc_feasible_legs(uuid, numeric, integer)') is not null
     or (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = any (c_fns)) <> 6
     or exists (select 1 from pg_proc p where p.prosrc like '%npc_feasible_legs(%' and p.oid::regprocedure::text not in
                  ('npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 'npc_leg_days(numeric,numeric)', 'npc_feasible_legs(uuid,uuid,numeric,integer)')
                  and p.pronamespace in (select n.oid from pg_namespace n where n.nspname in ('public', 'cmd', 'world', 'voyage'))) then
    raise exception '0392 self-assert FAIL: the old npc_feasible_legs still stands, the new functions are not exactly six, or a caller this file did not re-cut names npc_feasible_legs';
  end if;
  for r_x in select p.proname, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, '') as cfg, p.oid
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = any (c_fns) loop
    if r_x.provolatile <> (case when r_x.proname = 'npc_course_zones_fill' then 'v' else 's' end)
       or (r_x.proname <> 'sea_conditions_npc_on' and (not r_x.prosecdef or r_x.cfg <> '{"search_path=public, pg_temp"}'))
       or has_function_privilege('anon', r_x.oid, 'execute') or has_function_privilege('authenticated', r_x.oid, 'execute')
       or exists (select 1 from aclexplode(coalesce((select p.proacl from pg_proc p where p.oid = r_x.oid), acldefault('f', (select p.proowner from pg_proc p where p.oid = r_x.oid)))) a where a.grantee = 0) then
      raise exception '0392 self-assert FAIL: public.% is not of its declared volatility, pinned and server-only', r_x.proname;
    end if;
  end loop;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> 'sea_conditions_bite_npc') is distinct from v_cfg_before
     or (select c.value from public.world_config c where c.key = 'sea_conditions_bite_npc') is distinct from 'false'::jsonb
     or public.sea_conditions_npc_on() then
    raise exception '0392 self-assert FAIL: a knob moved, or sea_conditions_bite_npc is not shipped false';
  end if;
  if has_table_privilege('anon', 'public.npc_course_zones_memo', 'select') or has_table_privilege('authenticated', 'public.npc_course_zones_memo', 'select')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.npc_course_zones_memo'::regclass) then
    raise exception '0392 self-assert FAIL: public.npc_course_zones_memo is readable by a client or has no row level security';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_entry
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0392 self-assert FAIL: the registry or a wall moved (no new door; the posture must read zero)';
  end if;

  -- 6c the memo: written, and equal to the one sampler on a sample of the courses the world holds, forwards and backwards
  if v_memo < 1 or v_memo <> (select count(*) from public.npc_course_zones_memo) then
    raise exception '0392 self-assert FAIL: the memo holds % rows and the fill said %', (select count(*) from public.npc_course_zones_memo), v_memo;
  end if;
  select count(*) into v_n
    from (select c.course from public.npc_courses c order by c.from_port, c.to_port limit 60) q
   where public.npc_course_zones(q.course) is distinct from public.course_zones(q.course)
      or not exists (select 1 from public.npc_course_zones_memo m where m.course_md5 = md5(q.course::text))
      or not exists (select 1 from public.npc_course_zones_memo m
                      where m.course_md5 = md5((select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(q.course) with ordinality t(x, i))::text));
  if v_n <> 0 then
    raise exception '0392 self-assert FAIL: % of 60 sampled courses are not in the memo both ways, or the memo disagrees with public.course_zones', v_n;
  end if;
  if public.npc_course_zones('[[38.6,-9.3],[23.1,-82.4]]'::jsonb) is distinct from public.course_zones('[[38.6,-9.3],[23.1,-82.4]]'::jsonb) then
    raise exception '0392 self-assert FAIL: a course the memo has not seen is not answered by the sampler';
  end if;

  -- 6d OFF = UNCHANGED: the sample's feasible legs through the new function, switch off, are the text the old function gave
  if (select count(*) from sample_0392) < 40 then
    raise notice '0392 NOTE: this world has % merchant fleets on a loop to sample (40 wanted): the parity sample is what it has', (select count(*) from sample_0392);
  end if;
  select md5(coalesce(string_agg(s.fleet_id::text || ':' || public.npc_feasible_legs(s.port_id, s.fleet_id, s.speed, 10)::text || public.npc_feasible_legs(s.port_id, s.fleet_id, s.speed, 60)::text, ';' order by s.fleet_id), '')) into v_legs_after
    from sample_0392 s;
  if v_legs_after is distinct from v_legs_before then
    raise exception '0392 self-assert FAIL: with the switch off the feasible legs of the % sampled merchant fleets are not what they were before this file', (select count(*) from sample_0392);
  end if;

  -- 6e LIT, INSIDE A PROBE THAT ROLLS BACK: a merchant fleet of a size-2 hull (wave under 30) with a known leg across the Western Ocean loses it and keeps
  -- another; a fleet whose wave covers every leg keeps every leg; the door still answers null for a merchant. Skipped, and said, in a world with no such fleet.
  v_cfg_probe := (select md5(string_agg(c.key || ':' || c.value::text, ',' order by c.key)) from public.world_config c);
  select s.fleet_id, s.port_id into v_car, v_port
    from sample_0392 s
   where public.fleet_wave(s.fleet_id) < 30
     and exists (select 1 from jsonb_array_elements(public.npc_feasible_legs(s.port_id, s.fleet_id, s.speed, 400)) x
                  where public.npc_sea_shut(public.fleet_wave(s.fleet_id), (x->>'port_id')::uuid, x->'course') is not null)
     and exists (select 1 from jsonb_array_elements(public.npc_feasible_legs(s.port_id, s.fleet_id, s.speed, 400)) x
                  where public.npc_sea_shut(public.fleet_wave(s.fleet_id), (x->>'port_id')::uuid, x->'course') is null)
   order by s.fleet_id limit 1;
  if v_car is null then
    raise notice '0392 NOTE: no sampled merchant fleet has both a leg her hull cannot hold and one it can: the lit probe is proof 92''s alone in this world';
  else
    v_dark := public.npc_feasible_legs(v_port, v_car, 5, 400);
    begin
      update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite_npc';
      if not public.sea_conditions_npc_on() then
        raise exception '0392 self-assert FAIL: the probe lit sea_conditions_bite_npc and the reader still answers false';
      end if;
      v_lit := public.npc_feasible_legs(v_port, v_car, 5, 400);
      if jsonb_array_length(v_lit) >= jsonb_array_length(v_dark) or jsonb_array_length(v_lit) < 1
         or exists (select 1 from jsonb_array_elements(v_lit) x where public.npc_sea_shut(public.fleet_wave(v_car), (x->>'port_id')::uuid, x->'course') is not null)
         or v_lit <> (select jsonb_agg(x order by o) from jsonb_array_elements(v_dark) with ordinality t(x, o)
                       where public.npc_sea_shut(public.fleet_wave(v_car), (x->>'port_id')::uuid, x->'course') is null) then
        raise exception '0392 self-assert FAIL: lit, the feasible legs are not the dark ones less those her hull cannot hold (% lit, % dark)', jsonb_array_length(v_lit), jsonb_array_length(v_dark);
      end if;
      if public.passage_gate((select f.player_id from public.fleets f where f.id = v_car), v_car, 999999, null, null) is not null then
        raise exception '0392 self-assert FAIL: lit, the sail door refuses a merchant (0107''s exemption must stand: a fleet at sea finishes her trip)';
      end if;
      raise exception 'PROBE_ROLLBACK_0392';
    exception when others then
      if sqlerrm <> 'PROBE_ROLLBACK_0392' then raise; end if;
    end;
  end if;
  if public.sea_conditions_npc_on() or (select md5(string_agg(c.key || ':' || c.value::text, ',' order by c.key)) from public.world_config c) is distinct from v_cfg_probe then
    raise exception '0392 self-assert FAIL: the probe left sea_conditions_bite_npc on, or a knob changed';
  end if;

  -- 6f BY CONSTRUCTION: this transaction wrote no row to any table of money, houses, ships, routes or events; the knob and the memo are the positive control
  for r_x in select a.relname, a.n_tup_ins - coalesce(b.n_tup_ins, 0) as i, a.n_tup_upd - coalesce(b.n_tup_upd, 0) as u, a.n_tup_del - coalesce(b.n_tup_del, 0) as dl
             from pg_stat_xact_user_tables a left join xact0_0392 b on b.relname = a.relname
            where a.relname in ('players', 'npc_houses', 'npc_fleets', 'fleets', 'ships', 'ledger', 'events', 'standing_routes', 'standing_route_stops', 'standing_route_lines', 'npc_courses', 'voyages', 'orders') loop
    if r_x.i <> 0 or r_x.u <> 0 or r_x.dl <> 0 then
      raise exception '0392 self-assert FAIL: this file wrote % row(s) to %, which it must never touch', r_x.i + r_x.u + r_x.dl, r_x.relname;
    end if;
  end loop;
  select a.n_tup_ins - coalesce(b.n_tup_ins, 0) into v_n from pg_stat_xact_user_tables a left join xact0_0392 b on b.relname = a.relname where a.relname = 'world_config';
  select a.n_tup_ins into v_x from pg_stat_xact_user_tables a where a.relname = 'npc_course_zones_memo';
  if v_n <> 1 or coalesce(v_x, 0) < v_memo then
    raise exception '0392 self-assert FAIL: the transaction counters saw % knob(s) and % memo rows inserted, not 1 and % (the proof by construction would be vacuous)', v_n, v_x, v_memo;
  end if;
  v_ms := v_ms || jsonb_build_object('assert', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0392 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;

  -- ── 7. RECEIPT ──
  raise notice '0392 NOTE: the live paths (the planner dropping a loop the sea closes and choosing one her hull can hold, a nau keeping the Atlantic, a barca keeping her coast, a merchant mid-voyage not refused, a real plan pass equal dark) are proved in CI by scripts/db/proofs/92_a_merchant_sails_the_seas_her_hull_can_hold.sql and locally by scripts/ops/harness/sea-merchants/.';
  raise notice '0392 timings ms (cumulative): %', v_ms;
  raise notice '0392 self-assert ok: A MERCHANT SAILS THE SEAS HER HULL CAN HOLD - 2 bodies re-cut by 6 hunks (every hunk once, each reverses, attributes unmoved), npc_feasible_legs now takes the fleet, no other function moved, 5 new server-only functions, the switch sea_conditions_bite_npc shipped false, the memo % rows and equal to the sampler, off = unchanged on % sampled fleets, lit probe %, nothing of money, ships or routes written', v_memo, (select count(*) from sample_0392), case when v_car is null then 'skipped (said above)' else 'ok' end;
end
$m$;
