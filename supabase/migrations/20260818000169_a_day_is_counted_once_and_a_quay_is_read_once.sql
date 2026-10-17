-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0169 — A DAY IS COUNTED ONCE AND A QUAY IS READ ONCE  (the arrivals sweep, step 4 — nothing it decides moves)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- Prod, cron.job_run_details, byeharu-voyage:arrivals (every 15 s, budget 10 s), read-only, after 0164
-- (the chart unrolled) had run from 22:10 UTC on 2026-10-17:
--   216 runs 22:10–23:14 UTC: avg 3.74 s (22:xx 3.83 s, 23:xx 3.52 s), p50 3.2–3.3 s, p95 10.1 s / 5.2 s,
--   max 10.46 s; 13 budget-length runs in 22:xx. A run did 7.5 lap starts, 16.6 departures, 16.5
--   arrivals and ~151 sea-days on average (it was 2.6 s at half this load on 2026-10-17 morning).
-- A regression of each run's time on what it did (runs since 22:10, departures / arrivals from the rows
-- each run wrote, sea-days from voyage_events.resolved_at between runs):
--   ≈ 0.83 s a run + 0.23 s a lap start (1.74 s of the average) + 0.009 s a sea-day (1.36 s)
--   + 0.017 s a departure (0.28 s); arrivals −0.03 s (collinear with the rest); r² 0.83 over 215 runs.
-- So a run is now about half LAP STARTS and half SEA-DAYS, over a ~0.8 s floor.
--
-- WHERE THE LAP START GOES (prod, read-only, 40 md5-spread merchant legs and 10 lap starts):
--   * a lap start prices ~11 distinct legs (her loop + npc_route_candidates = 16 others, each leg once)
--     through public.npc_leg_lines, ~25–28 ms a leg — of which world.trade_routes(from, …, to) is
--     ~22–27 ms: npc_leg_lines' own work is ~1 ms a leg;
--   * a ranking's time is its QUOTES (~10 a ranking: a BUY at the source and a SELL at the sink for every
--     good with a gap) — 1.1–2.6 ms each — and ~1.17 ms of every quote is its PRELUDE: the port's spread
--     (world.spread_effective → world.spread: four knobs, the market works, the buffs), its tax, its bid
--     factor and the treasury switch. With no fleet named, those four terms are the PORT's: the same
--     for every good, every size, both sides. A ranking read them ~10 times for two ports.
-- WHERE A SEA-DAY GOES: its hazard roll asks voyage.leg_at_day → voyage.progress_nm →
--   voyage.days_complete, which walked the schedule from day 0 through voyage.day_ends_at — a fresh
--   read of the voyage row, the knob and the delay sum for EVERY day walked: 1.7 ms at the fleet's next
--   day on prod today (avg day 7), and growing with the SQUARE of the day number (the longest passage
--   at sea is 141 days).
-- THE CANDIDATE SCAN (tick_arrivals' first query) asks voyage.day_ends_at for every voyage at sea:
--   ~0.17 ms × ~760 = 0.13 s of every run.
--
-- ── WHAT THIS FILE DOES (every answer is the pre-image — asserted) ─────────────────────────────
-- (1) voyage.day_end_from(eta, departed_at, day, delay_before, k) — NEW: the day boundary's arithmetic,
--     moved out of voyage.day_ends_at verbatim (`least(eta, departed_at + (day × 24 + delay before it)
--     × 3600 / time_compression)`). PL/pgSQL, STABLE, invoker, reads nothing; server-only.
--     voyage.day_ends_at composes it (one hunk) — the voyage row, voyage.delay_before_day and the knob,
--     exactly as before.
-- (2) voyage.days_complete — the same walk, the voyage row and the knob read ONCE: each day walked is
--     voyage.day_end_from over voyage.delay_before_day (the one reading of the delay accrued before a
--     day). O(days) cheap steps instead of a fresh day_ends_at per step. One hunk.
-- (3) public.tick_arrivals' candidate scan — the same test, composed from the row it already holds:
--     voyage.day_end_from(v.eta, v.departed_at, n, voyage.delay_before_day(v.id, n), k) is
--     voyage.day_ends_at(v.id, n) for that row, with the knob read once a run. Two hunks.
-- (4) world.quote_terms(port, good, fleet) — NEW: the quote's four port terms (spread, no-bargain
--     spread, tax, bid factor), the four readings MOVED out of world.quote verbatim.
--     world.quote_priced(port, good, qty, side, limit, fleet, spread, nohag, tax, bidf) — NEW: world.quote's
--     body, generated here from the LIVE body: the side test, the market row, world.mid_terms and the
--     stock walk, with its terms read through world.quote_terms AT THE SAME POINT as ever — unless the
--     caller hands them over. world.quote becomes `world.quote_priced(…, null, null, null, null)`:
--     the same answer, the same refusals in the same order, the same ACL.
-- (5) world.trade_routes — with no fleet named, the source's terms are read once a ranking and each
--     sink's once (two CTEs), and the BUY / SELL quotes hand them to world.quote_priced. With a fleet
--     named nothing is handed over and every quote reads its own (a purser's spread is per good).
--     Two hunks; the joins and the row order are untouched (the terms are scalar sub-selects).
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Change any rule, price, ranking, refusal, hazard, schedule, knob, table, client grant or entry point.
-- Touch voyage.settle, voyage.hazard_roll, voyage.leg_at_day, voyage.progress_nm, voyage.arrival_at,
-- npc_plan, npc_leg_lines, npc_affordable, npc_buy_ceiling (they read faster through the bodies above).
-- Cache anything across calls or statements. Fold voyage.arrival_at's or voyage.recompute_eta's own
-- schedule arithmetic onto (1) (they are their own copies, left as found; see the dev-log).
--
-- ── THE PROOF (all in this file; old and new on the SAME snapshot, as text) ────────────────────
-- §1 keeps the pre-image TREE (day_ends_at, days_complete, progress_nm, leg_at_day, hazard_roll,
-- arrival_at, quote, trade_routes, npc_leg_lines, npc_affordable, npc_buy_ceiling — every function on a
-- path from the reads below to a changed body) under pg_temp names. §4 compares, old vs new:
--   (a) EVERY voyage at sea: voyage.day_ends_at for every day 0 .. total+2; voyage.hazard_roll for every
--       day 1 .. total+1 (THE HAZARD ROLLS — pure in the voyage id); voyage.days_complete and
--       voyage.progress_nm now, before departure, at it, at the eta and past it; voyage.arrival_at now and
--       at the eta. On a md5 sample of 40 also voyage.leg_at_day for every day, days_complete and
--       progress_nm at every day boundary and 1 ms either side of it, and arrival_at a day past the eta;
--   (b) the same on voyages of this file's own (rolled back): no event, a STORM / FAIR_WIND / CALM /
--       FAIR_WIND run that pulls her schedule in and pushes it out, and a long passage; and a voyage that
--       does not exist (a refusal is compared by its sqlstate and message);
--   (c) the sweep's candidate test for every voyage at sea, at now and 1 ms either side of her next
--       boundary;
--   (d) world.quote on a md5 spread of market rows × both sides × five sizes × limits × no fleet / a
--       fleet, its refusals (a bad side, no market row), and the terms trade_routes hands over — in the
--       world as found AND with the city treasury and influence switched the other way (rolled back);
--   (e) every sampled ranking (merchant legs as npc_leg_lines asks them; open scans) and 12 whole
--       lap-start reads (loops + every leg's lines, which carry the quotes).
-- A difference RAISES; each comparison must also be non-vacuous.
-- §5 TIMES old vs new and REPORTS it (raise notice, not gated — prod runs on burstable CPU; the verdict
-- is cron.job_run_details after the push).
--
-- ── WHAT IT BUYS (EXPECTED; prod is the verdict) ───────────────────────────────────────────────
--   * a lap start: ~10 of a ranking's ~10–12 quote preludes are handed over (prod: ~1.0 ms each of a
--     ~1.25 ms quote) × ~11 distinct legs ≈ 0.09–0.13 s of a ~0.25 s lap start → ≈ 0.7–0.9 s a run;
--   * a sea-day: the hazard roll's day count ~1.7 ms → ~0.4 ms at today's average day (and linear, not
--     quadratic, in the day) ≈ 0.2 s a run; the candidate scan ~0.13 s → ~0.06 s a run;
--   together ≈ 1.0 s of today's ~3.7 s → ≈ 2.7 s, and less growth per merchant added.
--   Measured on a merchants-on PGlite world (whose function calls cost ~1/6 of prod's, so the gains read
--   smaller): rankings −19 % to −33 %, lap-start reads −5 % to −11 %, world.quote's term readings
--   44,883 → 11,841 a sweep, the whole sweep 30.8 s → 30.0 s from one saved world to the same end state.
--
-- ── LOCKS, AND HOW LONG THE PUSH TAKES ──────────────────────────────────────────────────────────
-- ACCESS SHARE on what it reads; CREATE FUNCTION / CREATE OR REPLACE FUNCTION (no table lock); pg_temp
-- objects; the probes of §4(b)/(d) write inside sub-transactions that are rolled back (asserted). No
-- LOCK TABLE, no set role, no set local, no begin. ESTIMATED on prod: 3–6 min (locally 52 s on a world of
-- 578 voyages at sea, 17 s on a fresh chain), almost all of it the OLD bodies on every voyage at sea — the
-- walk this file removes. Deploy with the clock unwound (DEPLOY_RUNBOOK).
--
-- ROLLBACK: a forward migration putting the pre-image bodies back (each hunk's OLD text is here verbatim;
-- the self-assert proves each live body reverses to its pre-image) and dropping the three new functions.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0168, LF-normalised), each asserted to occur
-- exactly once: voyage.day_ends_at (0006/0125), voyage.days_complete (0006), public.tick_arrivals (0125),
-- world.quote (0134), world.trade_routes (0136).
-- VERSION: 0169 (provisional; renumbered to head + 1 at deploy). Applies on prod head 0168.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '30min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0169(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0169 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proparallel from pg_proc p where p.oid = f.fn::regprocedure) as par,
       (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = f.fn::regprocedure) as lang,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('voyage.day_ends_at(uuid, integer)'),
               ('voyage.days_complete(uuid, timestamp with time zone)'),
               ('public.tick_arrivals(timestamp with time zone)'),
               ('world.quote(uuid, uuid, numeric, text, numeric, uuid)'),
               ('world.trade_routes(uuid, uuid, numeric, integer, uuid)')) f(fn);

create temp table before_0169 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where (n.nspname, p.proname) in (('voyage', 'day_end_from'), ('world', 'quote_terms'), ('world', 'quote_priced'))) as n_found;

do $$
begin
  if (select count(*) from defs_before_0169 where def is not null) <> 5 then
    raise exception '0169 self-assert FAIL: % of the 5 bodies found', (select count(*) from defs_before_0169 where def is not null);
  end if;
  if (select n_found from before_0169) <> 0 then
    raise exception '0169 self-assert FAIL: voyage.day_end_from / world.quote_terms / world.quote_priced already exist';
  end if;
end $$;

-- THE OLD TREE: every function on a path from the reads §4 compares to a changed body. Every overload.
create temp table tree_0169 (nsp text, name text) on commit drop;
insert into tree_0169 values
  ('voyage', 'day_ends_at'), ('voyage', 'days_complete'), ('voyage', 'progress_nm'), ('voyage', 'leg_at_day'),
  ('voyage', 'hazard_roll'), ('voyage', 'arrival_at'),
  ('world', 'quote'), ('world', 'trade_routes'), ('public', 'npc_leg_lines'), ('public', 'npc_affordable'),
  ('public', 'npc_buy_ceiling');

create or replace function pg_temp.old_sql_0169(p_sql text)
returns text
language plpgsql
stable
as $$
declare
  t record;
  v text := p_sql;
begin
  for t in select nsp, name from tree_0169 order by length(name) desc, nsp, name loop
    v := replace(v, t.nsp || '.' || t.name || '(', 'pg_temp.' || t.nsp || '_' || t.name || '_0169(');
  end loop;
  return v;
end $$;

create temp table old_tree_0169 on commit drop as
select n.nspname as nsp, p.proname as name, p.oid::regprocedure::text as sig,
       pg_temp.old_sql_0169(replace(pg_get_functiondef(p.oid), E'\r', '')) as def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join tree_0169 t on t.nsp = n.nspname and t.name = p.proname;

do $$
declare
  d   record;
  t   record;
  v_n int;
begin
  if (select count(*) from old_tree_0169) <> (select count(*) from tree_0169) then
    raise exception '0169 self-assert FAIL: the old tree lists % name(s) but % live function(s) were found',
      (select count(*) from tree_0169), (select count(*) from old_tree_0169);
  end if;
  -- THE TREE IS CLOSED on the compared paths: the callers of the changed bodies that §4 reads are in it
  -- (settle, tick_arrivals, npc_plan, do_buy / do_sell write and are not read; §4(c) stands in for the
  -- candidate scan, §4(e)'s lap read for npc_plan).
  for t in select * from (values
             ('voyage.day_ends_at(', array['public.tick_arrivals', 'voyage.days_complete', 'voyage.leg_at_day', 'voyage.settle']),
             ('voyage.days_complete(', array['voyage.progress_nm']),
             ('voyage.progress_nm(', array['voyage.leg_at_day', 'voyage.position', 'voyage.waters_ahead', 'world.voyage_view']),
             ('voyage.leg_at_day(', array['voyage.hazard_roll', 'voyage.settle']),
             ('voyage.hazard_roll(', array['voyage.arrival_at', 'voyage.settle']),
             ('world.trade_routes(', array['public.npc_leg_lines']),
             ('public.npc_leg_lines(', array['public.npc_plan'])) x(needle, allowed) loop
    select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.pronamespace <> pg_my_temp_schema() and strpos(p.prosrc, t.needle) > 0
       and not (n.nspname || '.' || p.proname = any (t.allowed))
       and not (n.nspname || '.' || p.proname || '(' = t.needle);
    if v_n > 0 then
      raise exception '0169 self-assert FAIL: % live bod(ies) outside the known callers call % — the old tree is not closed: %', v_n, t.needle,
        (select string_agg(p.oid::regprocedure::text, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where p.pronamespace <> pg_my_temp_schema() and strpos(p.prosrc, t.needle) > 0
            and not (n.nspname || '.' || p.proname = any (t.allowed)) and not (n.nspname || '.' || p.proname || '(' = t.needle));
    end if;
  end loop;
  -- NO COPY REACHES A LIVE TREE BODY (and every copy was renamed).
  for d in select * from old_tree_0169 loop
    if strpos(d.def, 'CREATE OR REPLACE FUNCTION pg_temp.' || d.nsp || '_' || d.name || '_0169(') <> 1 then
      raise exception '0169 self-assert FAIL: the old copy of % was not renamed', d.sig;
    end if;
    for t in select * from tree_0169 loop
      if strpos(d.def, t.nsp || '.' || t.name || '(') > 0 then
        raise exception '0169 self-assert FAIL: the old copy of % still calls the live %.%', d.sig, t.nsp, t.name;
      end if;
    end loop;
  end loop;
  perform set_config('check_function_bodies', 'off', true);
  for d in select * from old_tree_0169 order by nsp, name, sig loop
    execute d.def;
  end loop;
  perform set_config('check_function_bodies', 'on', true);
  select count(*) into v_n from pg_proc where pronamespace = pg_my_temp_schema()
     and proname in (select tt.nsp || '_' || tt.name || '_0169' from tree_0169 tt);
  if v_n <> (select count(*) from tree_0169) then
    raise exception '0169 self-assert FAIL: % old cop(ies) made, not %', v_n, (select count(*) from tree_0169);
  end if;
end $$;

-- THE LAP-START READ, as npc_plan reads it — 0136's probe, verbatim but for its name. The OLD variant is
-- the same text pointed at the old tree.
create or replace function pg_temp.lap_read_0169(p_route uuid)
returns jsonb
language plpgsql
as $$
declare
  sr      public.standing_routes%rowtype;
  v_fleet uuid;
  v_crew  int;
  v_hold  numeric;
  v_speed numeric;
  v_loop  jsonb;
  v_loops jsonb;
  v_legs  jsonb := '{}'::jsonb;
  v_len   int;
  v_from  uuid;
  v_to    uuid;
  v_key   text;
  lp      record;
  i       int;
  j       int;
begin
  select * into sr from public.standing_routes where id = p_route;
  v_fleet := coalesce(sr.fleet_id, (select nf.fleet_id from public.npc_fleets nf where nf.route_id = sr.id limit 1));
  select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
    into v_crew, v_hold
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = v_fleet;
  v_hold  := v_hold + public.fleet_free_hold(v_fleet);
  v_speed := greatest(coalesce(voyage.fleet_speed(v_fleet), 0), 0.1);
  select jsonb_agg(jsonb_build_object('port_id', s.port_id, 'code', p.code, 'course', s.course) order by s.ord)
    into v_loop
    from public.standing_route_stops s join public.ports p on p.id = s.port_id
   where s.route_id = sr.id;
  v_loops := jsonb_build_array(v_loop);
  for lp in select * from public.npc_loop_candidates(sr.id, v_fleet, (v_loop->0->>'port_id')::uuid, v_hold, v_speed) loop
    exit when jsonb_array_length(v_loops) >= public.wc_int('npc_route_candidates');
    v_loops := v_loops || jsonb_build_array(lp.stops);
  end loop;
  for i in 0 .. jsonb_array_length(v_loops) - 1 loop
    v_loop := v_loops->i;
    v_len  := jsonb_array_length(v_loop);
    for j in 0 .. v_len - 1 loop
      v_from := (v_loop->j->>'port_id')::uuid;
      v_to   := (v_loop->((j + 1) % v_len)->>'port_id')::uuid;
      v_key  := v_from::text || '>' || v_to::text;
      if not v_legs ? v_key then
        v_legs := v_legs || jsonb_build_object(v_key, public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('hold', v_hold, 'crew', v_crew, 'speed', v_speed, 'loops', v_loops, 'legs', v_legs);
end $$;

do $$
declare
  v_def text := replace(pg_get_functiondef('pg_temp.lap_read_0169(uuid)'::regprocedure), E'\r', '');
begin
  v_def := regexp_replace(pg_temp.old_sql_0169(v_def), 'FUNCTION pg_temp(_[0-9]+)?\.lap_read_0169\(', 'FUNCTION pg_temp.lap_read_old_0169(');
  if strpos(v_def, 'FUNCTION pg_temp.lap_read_old_0169(') = 0 or strpos(v_def, 'pg_temp.public_npc_leg_lines_0169(') = 0 then
    raise exception '0169 self-assert FAIL: the old lap read was not pointed at the old tree';
  end if;
  execute v_def;
end $$;

-- ONE VOYAGE'S SCHEDULE, read through the old tree or the new, as one text (a refusal is an answer too).
-- Every day boundary 0 .. total+2; every hazard roll 1 .. total+1; days_complete and progress_nm at p_now,
-- before departure, at it, at the eta, an hour and a day past it; arrival_at at p_now and at the eta.
-- p_full (a md5 sample of 40, and this file's own voyages) adds every leg 1 .. total+1, days_complete and
-- progress_nm at each boundary and 1 ms either side of it, and arrival_at a day past the eta. (The OLD
-- walk is what makes this read cost the square of a passage's length: on prod the full read of every
-- voyage would take longer than the push should.)
create or replace function pg_temp.schedule_0169(p_voyage uuid, p_now timestamptz, p_full boolean)
returns text
language plpgsql
as $$
declare
  v       public.voyages%rowtype;
  v_t     int;
  d       int;
  v_at    timestamptz;
  v_out   text[] := '{}';
  h       record;
  v_ats   timestamptz[];
begin
  select * into v from public.voyages where id = p_voyage;
  if v.id is null then
    v_t := 3;
  else
    v_t := voyage.total_days(v.id);
  end if;
  for d in 0 .. v_t + 2 loop
    v_out := v_out || ('E' || d || '=' || coalesce(voyage.day_ends_at(p_voyage, d)::text, 'null'));
  end loop;
  for d in 1 .. v_t + 1 loop
    begin
      select * into h from voyage.hazard_roll(p_voyage, d);
      v_out := v_out || ('H' || d || '=' || row(h.occurred, h.kind, h.magnitude, h.p_hazard)::text);
    exception when others then
      v_out := v_out || ('H' || d || '!' || sqlstate || ' ' || sqlerrm);
    end;
    if p_full then
      begin
        v_out := v_out || ('L' || d || '=' || coalesce(voyage.leg_at_day(p_voyage, d)::text, 'null'));
      exception when others then
        v_out := v_out || ('L' || d || '!' || sqlstate || ' ' || sqlerrm);
      end;
    end if;
  end loop;
  v_ats := array[p_now, v.departed_at - interval '1 second', v.departed_at, v.eta, v.eta + interval '1 hour', v.eta + interval '1 day'];
  if p_full then
    for d in 1 .. v_t + 1 loop
      v_at := voyage.day_ends_at(p_voyage, d);
      v_ats := v_ats || array[v_at - interval '1 millisecond', v_at, v_at + interval '1 millisecond'];
    end loop;
  end if;
  foreach v_at in array v_ats loop
    v_out := v_out || ('D@' || coalesce(v_at::text, 'null') || '=' || coalesce(voyage.days_complete(p_voyage, v_at)::text, 'null'));
    begin
      v_out := v_out || ('P@' || coalesce(v_at::text, 'null') || '=' || coalesce(voyage.progress_nm(p_voyage, v_at)::text, 'null'));
    exception when others then
      v_out := v_out || ('P@' || coalesce(v_at::text, 'null') || '!' || sqlstate || ' ' || sqlerrm);
    end;
  end loop;
  foreach v_at in array case when p_full then array[p_now, v.eta, v.eta + interval '1 day'] else array[p_now, v.eta] end loop
    begin
      v_out := v_out || ('A@' || coalesce(v_at::text, 'null') || '=' || coalesce(voyage.arrival_at(p_voyage, v_at)::text, 'null'));
    exception when others then
      v_out := v_out || ('A@' || coalesce(v_at::text, 'null') || '!' || sqlstate || ' ' || sqlerrm);
    end;
  end loop;
  return array_to_string(v_out, ';');
end $$;

do $$
declare
  v_def text := replace(pg_get_functiondef('pg_temp.schedule_0169(uuid, timestamp with time zone, boolean)'::regprocedure), E'\r', '');
begin
  v_def := regexp_replace(pg_temp.old_sql_0169(v_def), 'FUNCTION pg_temp(_[0-9]+)?\.schedule_0169\(', 'FUNCTION pg_temp.schedule_old_0169(');
  if strpos(v_def, 'FUNCTION pg_temp.schedule_old_0169(') = 0 or strpos(v_def, 'pg_temp.voyage_hazard_roll_0169(') = 0
     or strpos(v_def, 'pg_temp.voyage_days_complete_0169(') = 0 or strpos(v_def, 'pg_temp.voyage_arrival_at_0169(') = 0 then
    raise exception '0169 self-assert FAIL: the old schedule read was not pointed at the old tree';
  end if;
  execute v_def;
end $$;

-- ONE QUOTE, old tree or new, as text (a refusal is an answer too). p_given: the new side hands over the
-- terms world.trade_routes hands over (world.quote_terms(port, null, null)) — only asked with no fleet.
create or replace function pg_temp.quote_try_0169(p_mode text, p_port uuid, p_good uuid, p_qty numeric,
                                                  p_side text, p_limit numeric, p_fleet uuid)
returns text
language plpgsql
as $$
declare
  r record;
  k record;
begin
  if p_mode = 'old' then
    select * into r from pg_temp.world_quote_0169(p_port, p_good, p_qty, p_side, p_limit, p_fleet);
  elsif p_mode = 'new' then
    select * into r from world.quote(p_port, p_good, p_qty, p_side, p_limit, p_fleet);
  else
    select * into k from world.quote_terms(p_port, null, null);
    select * into r from world.quote_priced(p_port, p_good, p_qty, p_side, p_limit, p_fleet,
                                            k.q_spread, k.q_nohag, k.q_tax, k.q_bidf);
  end if;
  return row(r.units, r.total, r.avg_price, r.end_stock, r.mid_total, r.tax_total, r.spread_total, r.haggle_saved)::text;
exception when others then
  return 'RAISED ' || sqlstate || ' ' || sqlerrm;
end $$;

-- the voyages compared: every voyage at sea (and how much of the heavy half each gets)
create temp table voyages_0169 on commit drop as
select x.id, (x.rn <= 40 and voyage.total_days(x.id) <= 60) as full_read
  from (select v.id, row_number() over (order by md5(v.id::text)) as rn from public.voyages v where v.status = 'SAILING') x;

-- the market rows quoted: a md5 spread over every harbour's rows, and a fleet for every fifth
create temp table qrows_0169 on commit drop as
select x.port_id, x.good_id, x.stock, world.mid_price(x.port_id, x.good_id, x.stock) as mid, x.rn,
       case when x.rn % 5 = 0 then (select f.id from public.fleets f order by md5(f.id::text || x.rn::text) limit 1) end as fleet_id
  from (select pg.port_id, pg.good_id, pg.stock,
               row_number() over (order by md5(pg.port_id::text || pg.good_id::text)) as rn
          from public.port_goods pg join public.ports p on p.id = pg.port_id and p.kind = 'HARBOUR'
         order by md5(pg.port_id::text || pg.good_id::text) limit 700) x;

create temp table qcases_0169 (side text, qty numeric, lim text) on commit drop;
insert into qcases_0169 values ('buy', 1, null), ('buy', 50, null), ('buy', 37.5, 'mid'), ('sell', 50, null),
                               ('sell', 400, 'mid'), ('buy', 400, null), ('sell', 0.4, null), ('buy', 0, null);

-- the merchants whose lap-start reads are compared and timed: 12, spread by a hash of the route id
create temp table lap_sample_0169 on commit drop as
select sr.id as route_id
  from public.standing_routes sr
  join public.players p on p.id = sr.player_id and p.is_npc
 where (select count(*) from public.standing_route_stops s where s.route_id = sr.id) >= 2
   and exists (select 1 from public.ships s
                where s.fleet_id = coalesce(sr.fleet_id, (select nf.fleet_id from public.npc_fleets nf where nf.route_id = sr.id limit 1)))
 order by md5(sr.id::text), sr.id
 limit 12;

-- the rankings compared and timed: merchant legs as npc_leg_lines asks them (p_to, twelve rows), and
-- open scans (no p_to) from a spread of harbours — every row, and a 400 nm radius with five rows
create temp table rank_grid_0169 on commit drop as
select * from (
  select distinct on (s.port_id, n.port_id) s.port_id as f, n.port_id as t, null::numeric as radius, 12 as lim
    from public.standing_route_stops s
    join public.standing_routes sr on sr.id = s.route_id
    join public.players p on p.id = sr.player_id and p.is_npc
    join lateral (select s2.port_id from public.standing_route_stops s2
                   where s2.route_id = s.route_id and s2.ord > s.ord order by s2.ord limit 1) n on true
   order by s.port_id, n.port_id) legs
 order by md5(f::text || t::text) limit 120;
insert into rank_grid_0169
select h.id, null, x.radius, x.lim
  from (select p.id from public.ports p where p.kind = 'HARBOUR' order by md5(p.id::text) limit 12) h
 cross join (values (null::numeric, null::int), (400::numeric, 5)) x(radius, lim);

-- the timing's inputs, read through the OLD tree before anything changes (§5 reads them again after)
create temp table timing_0169 (what text, n int, old_ms numeric, new_ms numeric) on commit drop;

-- ── 2. THE NEW HELPERS ─────────────────────────────────────────────────────────────────────────
create function voyage.day_end_from(p_eta timestamptz, p_departed timestamptz, p_day integer,
                                    p_delay_before numeric, p_k numeric)
returns timestamptz
language plpgsql
stable
as $fn$
-- 0169: THE DAY BOUNDARY — voyage.day_ends_at's arithmetic (0006, clamped at the eta by 0006's own
-- reasoning: see voyage.day_ends_at), moved here verbatim so a caller holding the voyage row, the delay
-- accrued before the day (voyage.delay_before_day) and the knob (time_compression) composes it without
-- reading them again: voyage.day_ends_at, voyage.days_complete's walk and tick_arrivals' candidate scan.
-- A voyage-day is 24 SAILING sim-hours, pushed later by the delay the earlier days cost. Reads nothing.
begin
  return least(p_eta,
               p_departed + make_interval(secs =>
                 ((p_day * 24 + p_delay_before) * 3600
                  / p_k)::double precision));
end $fn$;
revoke all on function voyage.day_end_from(timestamptz, timestamptz, integer, numeric, numeric) from public, anon, authenticated;

create function world.quote_terms(p_port uuid, p_good uuid, p_fleet uuid,
                                  out q_spread numeric, out q_nohag numeric, out q_tax numeric, out q_bidf numeric)
returns record
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
-- 0169: A QUOTE'S FOUR TERMS — what this house executes at here (the port's spread, her purser's and
-- today's bargain: world.spread_effective), the same without the bargain, the tax a quote carries (0 lit:
-- it is charged on profit) and the city's bid factor. MOVED out of world.quote verbatim; world.quote_priced
-- reads them here, at the point world.quote always did. WITH NO FLEET NAMED THEY ARE THE PORT'S: p_good is
-- read only on world.spread_effective's fleet branch, so (port, any good, no fleet) = (port, null, null)
-- (asserted over every quoted row) — which is why world.trade_routes reads them once a quay.
begin
  q_spread := world.spread_effective(p_port, p_good, p_fleet);
  -- 0083: what the same house pays with no bargain; with no fleet named there is no bargain.
  q_nohag  := case when p_fleet is null then q_spread
                   else world.spread_effective(p_port, p_good, p_fleet, false) end;
  -- 0122: lit, the tax leaves the price — it is charged on a sale's PROFIT in cmd.do_sell.
  q_tax    := case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end;
  q_bidf   := public.city_bid_factor(p_port);
end $fn$;
revoke all on function world.quote_terms(uuid, uuid, uuid) from public, anon, authenticated;

-- world.quote_priced: world.quote's LIVE body, renamed, its four term readings replaced by the terms
-- handed over or (none handed over) world.quote_terms at the same point. Generated, asserted.
create temp table priced_hunks_0169 (n int, old text, new text) on commit drop;
insert into priced_hunks_0169 values
(1, $h$CREATE OR REPLACE FUNCTION world.quote(p_port uuid, p_good uuid, p_qty numeric, p_side text, p_limit numeric DEFAULT NULL::numeric, p_fleet uuid DEFAULT NULL::uuid)$h$,
$h$CREATE OR REPLACE FUNCTION world.quote_priced(p_port uuid, p_good uuid, p_qty numeric, p_side text, p_limit numeric, p_fleet uuid, p_spread numeric, p_nohag numeric, p_tax numeric, p_bidf numeric)$h$),
(2, $h$  t        record;    -- 0134: the market row's price terms, read ONCE (world.mid_terms)$h$,
$h$  t        record;    -- 0134: the market row's price terms, read ONCE (world.mid_terms)
  k        record;    -- 0169: the four terms (world.quote_terms), when none were handed over$h$),
(3, $h$  v_spread := world.spread_effective(p_port, p_good, p_fleet);
  -- 0083: what the same house pays with no bargain; with no fleet named there is no bargain.
  v_nohag  := case when p_fleet is null then v_spread
                   else world.spread_effective(p_port, p_good, p_fleet, false) end;
  -- 0122: lit, the tax leaves the price — it is charged on a sale's PROFIT in cmd.do_sell.
  v_tax    := case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end;
  v_bidf   := public.city_bid_factor(p_port);
$h$,
$h$  -- 0169: THE FOUR TERMS (world.quote_terms — the readings that stood here, moved whole), read
  -- HERE as always; a caller that read them once for the quay (world.trade_routes, no fleet named)
  -- hands them over instead. None handed over = all four null.
  if p_spread is null and p_nohag is null and p_tax is null and p_bidf is null then
    select * into k from world.quote_terms(p_port, p_good, p_fleet);
    v_spread := k.q_spread;
    v_nohag  := k.q_nohag;
    v_tax    := k.q_tax;
    v_bidf   := k.q_bidf;
  else
    v_spread := p_spread;
    v_nohag  := p_nohag;
    v_tax    := p_tax;
    v_bidf   := p_bidf;
  end if;
$h$);

do $$
declare
  v_def text := (select def from defs_before_0169 where fn = 'world.quote(uuid, uuid, numeric, text, numeric, uuid)');
  h     record;
  v_n   int;
begin
  for h in select * from priced_hunks_0169 order by n loop
    v_n := pg_temp.occurs_0169(v_def, h.old);
    if v_n <> 1 then
      raise exception '0169 self-assert FAIL: world.quote_priced hunk % occurs % time(s) in the live world.quote, not once', h.n, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  if strpos(v_def, 'world.spread_effective(') > 0 or strpos(v_def, 'public.city_bid_factor(') > 0
     or strpos(v_def, 'world.tax_rate(') > 0 or strpos(v_def, 'CREATE OR REPLACE FUNCTION world.quote_priced(') <> 1 then
    raise exception '0169 self-assert FAIL: world.quote_priced still reads a term itself, or was not renamed';
  end if;
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.quote_priced(', 'CREATE FUNCTION world.quote_priced(');
  execute v_def;
end $$;
revoke all on function world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric) from public, anon, authenticated;

-- ── 3. THE RE-CUTS (hunks: old = verbatim from the live bodies; new = what replaces it) ─────────
create temp table hunks_0169 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0169 values
('voyage.day_ends_at(uuid, integer)', 1,
$h$  select least(v.eta,
               v.departed_at + make_interval(secs =>
                 ((p_day * 24 + voyage.delay_before_day(p_voyage, p_day)) * 3600
                  / public.wc_num('time_compression'))::double precision))
    from public.voyages v where v.id = p_voyage
$h$,
$h$  -- 0169: the arithmetic lives in voyage.day_end_from (one home; days_complete's walk and the sweep's
  -- candidate scan compose it too), over what this reads: the row, the delay before the day, the knob.
  select voyage.day_end_from(v.eta, v.departed_at, p_day, voyage.delay_before_day(p_voyage, p_day),
                             public.wc_num('time_compression'))
    from public.voyages v where v.id = p_voyage
$h$),
('voyage.days_complete(uuid, timestamp with time zone)', 1,
$h$  while d < v_cap and voyage.day_ends_at(p_voyage, d + 1) <= p_at loop
    d := d + 1;
  end loop;
$h$,
$h$  -- 0169: THE SAME WALK, the row and the knob read ONCE: each day is voyage.day_end_from over the delay
  -- accrued before it (voyage.delay_before_day) — what voyage.day_ends_at(p_voyage, d + 1) composes — so
  -- a step is one delay read, not a fresh row, knob and delay read (it grew with the square of the day).
  -- No voyage: no row, a null boundary, no day walked — as before.
  select v.eta, v.departed_at into v_eta, v_dep from public.voyages v where v.id = p_voyage;
  v_k := public.wc_num('time_compression');
  while d < v_cap
        and voyage.day_end_from(v_eta, v_dep, d + 1, voyage.delay_before_day(p_voyage, d + 1), v_k) <= p_at loop
    d := d + 1;
  end loop;
$h$),
('voyage.days_complete(uuid, timestamp with time zone)', 2,
$h$  d     int := 0;
$h$,
$h$  d     int := 0;
  v_eta timestamptz;   -- 0169: the row and the knob, read once
  v_dep timestamptz;
  v_k   numeric;
$h$),
('public.tick_arrivals(timestamp with time zone)', 1,
$h$              and (v.eta <= p_now or voyage.day_ends_at(v.id, v.last_settled_day + 1) <= p_now)
$h$,
$h$              -- 0169: voyage.day_ends_at(v.id, n) composed from the row in hand (voyage.day_end_from over
              -- voyage.delay_before_day), the knob read once a run — the same test, one read a voyage
              and (v.eta <= p_now
                   or voyage.day_end_from(v.eta, v.departed_at, v.last_settled_day + 1,
                                          voyage.delay_before_day(v.id, v.last_settled_day + 1), v_k) <= p_now)
$h$),
('public.tick_arrivals(timestamp with time zone)', 2,
$h$  v_budget  interval := make_interval(secs => public.wc_int('arrivals_tick_budget_ms') / 1000.0);
$h$,
$h$  v_budget  interval := make_interval(secs => public.wc_int('arrivals_tick_budget_ms') / 1000.0);
  v_k       numeric := public.wc_num('time_compression');   -- 0169: the candidate scan's knob, once a run
$h$),
('world.quote(uuid, uuid, numeric, text, numeric, uuid)', 1,
$h$
declare
  v_step   numeric := public.wc_num('trade_step_tuns');
  v_stock  numeric;
  v_spread numeric;
  v_tax    numeric;
  v_bidf   numeric;   -- 0122: the city's bid factor (1 dark)
  v_left   numeric := p_qty;
  v_n      numeric;
  v_mid    numeric;
  v_unit   numeric;
  v_units  numeric := 0;
  v_total  numeric := 0;
  -- 0083: the four parts of the money, and the spread this house would pay with no bargain.
  v_nohag  numeric;
  v_mid_t  numeric := 0;
  v_tax_t  numeric := 0;
  v_spr_t  numeric := 0;
  v_hag_t  numeric := 0;
  t        record;    -- 0134: the market row's price terms, read ONCE (world.mid_terms)
begin
  if p_side not in ('buy', 'sell') then
    raise exception 'world.quote: side must be buy or sell, got %', p_side using errcode = '22023';
  end if;

  select pg.stock into v_stock from public.port_goods pg
   where pg.port_id = p_port and pg.good_id = p_good;
  if v_stock is null then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;
  -- 0134: WHAT THE PRICE IS MADE OF, read once: each step below re-priced through world.mid_price,
  -- which re-read this row and four knobs every 10 tuns. The stock walk is unchanged.
  select * into t from world.mid_terms(p_port, p_good);

  -- 0022: the ONE reading of what this house executes at — the port's published spread, her
  -- purser, and any bargain struck on this quay today. With no fleet named, or no purser posted,
  -- or no bargain open, this is world.spread(p_port) to the digit and the arithmetic below is
  -- 0005's and 0017's unchanged.
  v_spread := world.spread_effective(p_port, p_good, p_fleet);
  -- 0083: what the same house pays with no bargain; with no fleet named there is no bargain.
  v_nohag  := case when p_fleet is null then v_spread
                   else world.spread_effective(p_port, p_good, p_fleet, false) end;
  -- 0122: lit, the tax leaves the price — it is charged on a sale's PROFIT in cmd.do_sell.
  v_tax    := case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end;
  v_bidf   := public.city_bid_factor(p_port);

  -- §G.2: "Orders execute in 10-tun steps, each repricing, so a large order pays a genuinely worse
  -- average." The loop IS the price impact; there is no separate impact formula to drift from it.
  while v_left > 0 loop
    v_n := least(v_step, v_left);
    if p_side = 'buy' then
      if v_stock < v_n then v_n := v_stock; end if;
      exit when v_n <= 0;
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_stock, t.m_drift,   -- 0134
                                     t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
      v_unit := round(v_mid * (1 + v_tax + v_spread / 2), 2);
      -- §F.2: a limit order PARTIALLY FILLS to the largest quantity that stays under the limit.
      exit when p_limit is not null and v_unit > p_limit;
      v_total := v_total + v_unit * v_n;
      -- 0083: the same unit price in its parts, from the same v_mid / v_tax / v_spread; the parts
      -- differ from v_unit only by v_unit's rounding to the hundredth.
      v_mid_t := v_mid_t + v_mid * v_n;
      v_tax_t := v_tax_t + v_mid * v_tax * v_n;
      v_spr_t := v_spr_t + v_mid * (v_spread / 2) * v_n;
      v_hag_t := v_hag_t + (round(v_mid * (1 + v_tax + v_nohag / 2), 2) - v_unit) * v_n;
      v_stock := v_stock - v_n;
    else
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_stock, t.m_drift,   -- 0134
                                     t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
      v_unit := round(v_mid * (1 - v_spread / 2) * (1 - v_tax) * v_bidf, 2);
      exit when p_limit is not null and v_unit < p_limit;
      v_total := v_total + v_unit * v_n;
      v_mid_t := v_mid_t + v_mid * v_n;
      v_tax_t := v_tax_t + v_mid * (1 - v_spread / 2) * v_tax * v_n;
      v_spr_t := v_spr_t + v_mid * (v_spread / 2) * v_n;
      v_hag_t := v_hag_t + (v_unit - round(v_mid * (1 - v_nohag / 2) * (1 - v_tax) * v_bidf, 2)) * v_n;
      v_stock := v_stock + v_n;
    end if;
    v_units := v_units + v_n;
    v_left  := v_left - v_n;
  end loop;

  units     := v_units;
  total     := round(v_total)::bigint;
  avg_price := case when v_units > 0 then round(v_total / v_units, 2) else null end;
  end_stock := v_stock;
  -- 0083: `total` remains the ONLY figure the purse moves by. These four are exact sums that
  -- differ from it only by the per-unit 2-dp rounding above; a client prints them and never adds
  -- them back together.
  mid_total    := round(v_mid_t, 2);
  tax_total    := round(v_tax_t, 2);
  spread_total := round(v_spr_t, 2);
  haggle_saved := round(v_hag_t, 2);
  return next;
end $h$,
$h$
-- 0169: THE PRICE AUTHORITY IS world.quote_priced — this body, moved there whole (generated from it and
-- asserted): the side, the market row, its terms (world.quote_terms, read at the same point), the stock
-- walk. Asked here no terms are handed over, so it reads its own: the same answer, the same refusals in
-- the same order. world.trade_routes hands over a quay's terms, read once a ranking.
begin
  return query select * from world.quote_priced(p_port, p_good, p_qty, p_side, p_limit, p_fleet, null, null, null, null);
end $h$),
('world.trade_routes(uuid, uuid, numeric, integer, uuid)', 1,
$h$  bought as materialized (
    select z.good_id, qb.units, qb.total as outlay, qb.avg_price as buy_price
      from sized z
      cross join lateral world.quote(p_from, z.good_id, z.qty, 'buy', null, p_fleet) qb
     where z.qty >= 1
  ),
$h$,
$h$  -- 0169: A QUAY'S QUOTE TERMS, READ ONCE A RANKING. With no fleet named a quote's four terms are the
  -- port's (world.quote_terms: no purser, no bargain — the same for every good, size and side), so the
  -- source's are read once here and each sink's once below, and every quote is handed them
  -- (world.quote_priced). With a fleet named there are none: each quote reads its own, per good.
  qt_from as materialized (
    select k.q_spread, k.q_nohag, k.q_tax, k.q_bidf
      from world.quote_terms(p_from, null, null) k
     where p_fleet is null
  ),
  bought as materialized (
    select z.good_id, qb.units, qb.total as outlay, qb.avg_price as buy_price
      from sized z
      cross join lateral world.quote_priced(p_from, z.good_id, z.qty, 'buy', null, p_fleet,
                                            (select q.q_spread from qt_from q), (select q.q_nohag from qt_from q),
                                            (select q.q_tax from qt_from q), (select q.q_bidf from qt_from q)) qb
     where z.qty >= 1
  ),
  qt_to as materialized (
    select d.port_id, k.q_spread, k.q_nohag, k.q_tax, k.q_bidf
      from (select distinct kk.port_id from kept kk join bought bb on bb.good_id = kk.good_id and bb.units > 0) d
     cross join lateral world.quote_terms(d.port_id, null, null) k
     where p_fleet is null
  ),
$h$),
('world.trade_routes(uuid, uuid, numeric, integer, uuid)', 2,
$h$      cross join lateral world.quote(k.port_id, k.good_id, b.units, 'sell', null, p_fleet) qs
$h$,
$h$      cross join lateral world.quote_priced(k.port_id, k.good_id, b.units, 'sell', null, p_fleet,
                                            (select q.q_spread from qt_to q where q.port_id = k.port_id),
                                            (select q.q_nohag from qt_to q where q.port_id = k.port_id),
                                            (select q.q_tax from qt_to q where q.port_id = k.port_id),
                                            (select q.q_bidf from qt_to q where q.port_id = k.port_id)) qs   -- 0169
$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_n   int;
begin
  for d in select * from defs_before_0169 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0169 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0169(v_def, h.old);
      if v_n <> 1 then
        raise exception '0169 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
          h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 4. THE COMPARISONS — old tree and new, side by side (one snapshot each) ───────────────────
create temp table proven_0169 (k text primary key, v text) on commit drop;

-- (a) every voyage at sea
create temp table sched_0169 on commit drop as
select v.id, v.full_read, pg_temp.schedule_0169(v.id, now(), v.full_read) as new_v,
       pg_temp.schedule_old_0169(v.id, now(), v.full_read) as old_v
  from voyages_0169 v;

-- (c) the candidate test, at now and 1 ms either side of each voyage's next boundary
create temp table cand_0169 on commit drop as
select v.id, x.at,
       (v.eta <= x.at or pg_temp.voyage_day_ends_at_0169(v.id, v.last_settled_day + 1) <= x.at) as old_v,
       (v.eta <= x.at or voyage.day_end_from(v.eta, v.departed_at, v.last_settled_day + 1,
                                             voyage.delay_before_day(v.id, v.last_settled_day + 1),
                                             public.wc_num('time_compression')) <= x.at) as new_v
  from public.voyages v
 cross join lateral (select now() as at
                     union all select voyage.day_ends_at(v.id, v.last_settled_day + 1) - interval '1 millisecond'
                     union all select voyage.day_ends_at(v.id, v.last_settled_day + 1)
                     union all select voyage.day_ends_at(v.id, v.last_settled_day + 1) + interval '1 millisecond') x
 where v.status = 'SAILING';

-- (e) rankings and lap-start reads
create temp table ranks_0169 on commit drop as
select r.*, world.trade_routes(r.f, null, r.radius, r.lim, r.t) as new_v,
       pg_temp.world_trade_routes_0169(r.f, null, r.radius, r.lim, r.t) as old_v
  from rank_grid_0169 r;
create temp table laps_0169 on commit drop as
select s.route_id, pg_temp.lap_read_0169(s.route_id) as new_v, pg_temp.lap_read_old_0169(s.route_id) as old_v
  from lap_sample_0169 s;

do $$
declare
  v_n     int;
  v_bad   int;
  v_ex    text;
  v_rows  int;
  v_legs  int;
  v_kept  int;
  v_hz    int;
  v_kinds int;
begin
  -- (a)
  select count(*), count(*) filter (where new_v is distinct from old_v), min(id::text) filter (where new_v is distinct from old_v)
    into v_n, v_bad, v_ex from sched_0169;
  if v_bad > 0 then
    raise exception '0169 self-assert FAIL: schedules — % of % voyages at sea differ from the pre-image (e.g. %)', v_bad, v_n, v_ex;
  end if;
  select coalesce(sum(array_length(regexp_split_to_array(new_v, ';H[0-9]+=\(t'), 1) - 1), 0) into v_hz from sched_0169;
  insert into proven_0169 values ('live', format('%s voyages at sea (%s read in full; %s hazards that befell them) — every day end, hazard roll, leg, day count, progress and arrival = the pre-image as text',
    v_n, (select count(*) from sched_0169 where full_read), v_hz));

  -- (c)
  select count(*), count(*) filter (where new_v is distinct from old_v) into v_n, v_bad from cand_0169;
  if v_bad > 0 then
    raise exception '0169 self-assert FAIL: the candidate test — % of % (voyage, instant) differ from the pre-image', v_bad, v_n;
  end if;
  if v_n > 0 and ((select count(*) from cand_0169 where new_v) < 1 or (select count(*) from cand_0169 where not new_v) < 1) then
    raise exception '0169 self-assert FAIL: the candidate comparison is vacuous (all one answer over % instants)', v_n;
  end if;
  insert into proven_0169 values ('cand', format('%s (voyage, instant) candidate tests (%s due, %s not) = the pre-image',
    v_n, (select count(*) from cand_0169 where new_v), (select count(*) from cand_0169 where not new_v)));

  -- (e)
  select count(*), count(*) filter (where new_v::text is distinct from old_v::text) into v_n, v_bad from ranks_0169;
  select min(format('%s → %s r %s l %s', f, t, radius, lim)) into v_ex from ranks_0169 where new_v::text is distinct from old_v::text;
  if v_bad > 0 then
    raise exception '0169 self-assert FAIL: rankings — % of % differ from the pre-image (e.g. %)', v_bad, v_n, v_ex;
  end if;
  select sum(jsonb_array_length(new_v->'routes')) into v_rows from ranks_0169;
  if v_n < 20 or coalesce(v_rows, 0) < 20 or (select count(*) from ranks_0169 where t is null and jsonb_array_length(new_v->'routes') > 0) < 1 then
    raise exception '0169 self-assert FAIL: the ranking comparison is vacuous (% rankings, % rows)', v_n, v_rows;
  end if;
  insert into proven_0169 values ('ranks', format('%s rankings (%s merchant legs, %s open scans; %s rows) = the pre-image as text',
    v_n, (select count(*) from ranks_0169 where t is not null), (select count(*) from ranks_0169 where t is null), v_rows));
  select count(*), count(*) filter (where new_v::text is distinct from old_v::text) into v_n, v_bad from laps_0169;
  if v_n < 1 or v_bad > 0 then
    raise exception '0169 self-assert FAIL: lap-start reads — % of % differ from the pre-image', v_bad, v_n;
  end if;
  select sum((select count(*) from jsonb_object_keys(new_v->'legs'))),
         sum((select count(*) from jsonb_each(new_v->'legs') e where (e.value->>'any')::boolean))
    into v_legs, v_kept from laps_0169;
  if v_legs < v_n then
    raise exception '0169 self-assert FAIL: the lap-start reads priced % leg(s) for % merchant(s)', v_legs, v_n;
  end if;
  insert into proven_0169 values ('laps', format('%s merchants'' lap-start reads (%s loops, %s distinct legs priced, %s with a parcel kept) = the pre-image as text',
    v_n, (select sum(jsonb_array_length(new_v->'loops')) from laps_0169), v_legs, v_kept));
end $$;

-- (d) quotes, in the world as found and with the city treasury and influence switched the other way
-- (b) voyages of this file's own
-- Both write only inside sub-transactions that are rolled back; what they prove is kept in variables.
do $$
declare
  v_pass    int;
  v_n       int := 0;
  v_bad     int := 0;
  v_ex      text;
  v_raised  int := 0;
  v_given   int := 0;
  v_terms   int := 0;
  v_partial int := 0;
  v_out     text := '';
  v_tre     jsonb;
  v_inf     jsonb;
  r         record;
  c         record;
  o         text;
  nw        text;
  gv        text;
  v_lim     numeric;
  -- (b)
  v_fleet   uuid;
  v_route   uuid;
  v_course  jsonb;
  v_segs    jsonb;
  v_voy     uuid;
  v_t       int;
  v_probe   text := '';
  v_ghost   uuid := '00000000-0000-4000-8000-000000016900';
begin
  select value into v_tre from public.world_config where key = 'city_treasury_enabled';
  select value into v_inf from public.world_config where key = 'influence_enabled';
  for v_pass in 1 .. 2 loop
    begin
      if v_pass = 2 then
        update public.world_config set value = to_jsonb(not (v_tre::text::boolean)) where key = 'city_treasury_enabled';
        update public.world_config set value = to_jsonb(not (v_inf::text::boolean)) where key = 'influence_enabled';
      end if;
      for r in select * from qrows_0169 where v_pass = 1 or rn <= 250 order by rn loop
        for c in select * from qcases_0169 loop
          v_lim := case when c.lim = 'mid' then round(r.mid, 2) end;
          o  := pg_temp.quote_try_0169('old', r.port_id, r.good_id, c.qty, c.side, v_lim, r.fleet_id);
          nw := pg_temp.quote_try_0169('new', r.port_id, r.good_id, c.qty, c.side, v_lim, r.fleet_id);
          v_n := v_n + 1;
          if nw is distinct from o then
            v_bad := v_bad + 1;
            v_ex := coalesce(v_ex, format('pass %s port %s good %s %s %s lim %s fleet %s: old %s new %s', v_pass, r.port_id, r.good_id,
                                          c.side, c.qty, v_lim, r.fleet_id, o, nw));
          end if;
          if o like 'RAISED%' then v_raised := v_raised + 1; end if;
          if r.fleet_id is null then
            gv := pg_temp.quote_try_0169('given', r.port_id, r.good_id, c.qty, c.side, v_lim, null);
            v_given := v_given + 1;
            if gv is distinct from o then
              v_bad := v_bad + 1;
              v_ex := coalesce(v_ex, format('pass %s (terms handed over) port %s good %s %s %s lim %s: old %s given %s', v_pass, r.port_id,
                                            r.good_id, c.side, c.qty, v_lim, o, gv));
            end if;
          end if;
          if v_lim is not null and o not like 'RAISED%' and split_part(trim(both '()' from o), ',', 1)::numeric < c.qty then
            v_partial := v_partial + 1;
          end if;
        end loop;
        -- the property world.trade_routes relies on: with no fleet named the terms are the port's
        if (select row(k.*)::text from world.quote_terms(r.port_id, r.good_id, null) k)
           is distinct from (select row(k.*)::text from world.quote_terms(r.port_id, null, null) k) then
          raise exception '0169 self-assert FAIL: world.quote_terms(%, %, no fleet) is not the port''s terms', r.port_id, r.good_id;
        end if;
        v_terms := v_terms + 1;
      end loop;
      -- the refusals, in their order: a bad side before a missing row; a missing row; a missing port
      for c in select * from (values ('hold', (select good_id from qrows_0169 order by rn limit 1), (select port_id from qrows_0169 order by rn limit 1)),
                                     ('hold', v_ghost, v_ghost),
                                     ('buy',  v_ghost, (select port_id from qrows_0169 order by rn limit 1)),
                                     ('sell', (select good_id from qrows_0169 order by rn limit 1), v_ghost)) x(side, good, port) loop
        o  := pg_temp.quote_try_0169('old', c.port, c.good, 10, c.side, null, null);
        nw := pg_temp.quote_try_0169('new', c.port, c.good, 10, c.side, null, null);
        v_n := v_n + 1;
        if nw is distinct from o or o not like 'RAISED%' then
          v_bad := v_bad + 1;
          v_ex := coalesce(v_ex, format('refusal %s %s %s: old %s new %s', c.side, c.port, c.good, o, nw));
        end if;
        v_raised := v_raised + 1;
      end loop;
      if v_pass = 2 then
        raise exception 'ROLLBACK_0169_LIT';
      end if;
    exception when others then
      if sqlerrm <> 'ROLLBACK_0169_LIT' then raise; end if;
    end;
  end loop;
  if (select value from public.world_config where key = 'city_treasury_enabled') is distinct from v_tre
     or (select value from public.world_config where key = 'influence_enabled') is distinct from v_inf then
    raise exception '0169 self-assert FAIL: the switched quote pass was not rolled back';
  end if;
  if v_bad > 0 then
    raise exception '0169 self-assert FAIL: quotes — % of % differ from the pre-image (e.g. %)', v_bad, v_n + v_given, v_ex;
  end if;
  if v_n < 1000 or v_raised < 4 or v_partial < 1 or v_given < 500 then
    raise exception '0169 self-assert FAIL: the quote comparison is vacuous (% quotes, % refusals, % partial fills, % handed terms)',
      v_n, v_raised, v_partial, v_given;
  end if;
  insert into proven_0169 values ('quotes', format('%s quotes (%s refused, %s partial fills at a limit; switches as found and the other way) and %s with the quay''s terms handed over = the pre-image; world.quote_terms with no fleet = the port''s on %s rows',
    v_n, v_raised, v_partial, v_given, v_terms));

  -- (b) VOYAGES OF THIS FILE'S OWN — a merchant hull lying in port, put to sea on her own route's course
  -- through voyage.depart, given days of weather by hand, compared, rolled back.
  begin
    select f.id, sr.id into v_fleet, v_route
      from public.fleets f
      join public.standing_routes sr on sr.fleet_id = f.id or sr.id = (select nf.route_id from public.npc_fleets nf where nf.fleet_id = f.id limit 1)
     where f.status = 'DOCKED'
       and not exists (select 1 from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING')
       and exists (select 1 from public.ships s where s.fleet_id = f.id)
     order by md5(f.id::text) limit 1;
    if v_fleet is null then
      raise exception '0169 self-assert FAIL: no docked hull to put to sea for the probes';
    end if;
    for c in select * from (values (1, 'none'), (2, 'weather'), (3, 'long')) x(k, kind) order by k loop
      if c.kind = 'long' then
        select s.course into v_course from public.standing_route_stops s
         where s.course is not null and jsonb_typeof(s.course) = 'array' and jsonb_array_length(s.course) >= 2
         order by voyage.path_nm(s.course) desc, md5(s.course::text) limit 1;
      else
        select s.course into v_course from public.standing_route_stops s
         where s.route_id = v_route and s.course is not null and jsonb_typeof(s.course) = 'array' and jsonb_array_length(s.course) >= 2
         order by s.ord limit 1;
        if v_course is null then
          select s.course into v_course from public.standing_route_stops s
           where s.course is not null and jsonb_typeof(s.course) = 'array' and jsonb_array_length(s.course) >= 2
           order by md5(s.course::text) limit 1;
        end if;
      end if;
      v_segs := voyage.segments_from_course(v_course);
      update public.voyages set status = 'ARRIVED' where fleet_id = v_fleet and status = 'SAILING';
      v_voy := voyage.depart(v_fleet, v_segs, null, null, now() - interval '2 minutes');
      v_t := voyage.total_days(v_voy);
      if c.kind in ('weather', 'long') then
        -- a run that pushes her out and pulls her in (a fair wind gains < 24 h and never more than she lost)
        insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at) values
          (v_voy, 1, 'CLEAR',     '{"wages": 10}'::jsonb, now()),
          (v_voy, 2, 'STORM',     '{"hull_lost": 3, "delay_hours": 36}'::jsonb, now()),
          (v_voy, 3, 'FAIR_WIND', '{"hours_gained": 20.5, "delay_hours": -20.5}'::jsonb, now()),
          (v_voy, 4, 'CALM',      '{"delay_hours": 72.25}'::jsonb, now()),
          (v_voy, 5, 'FAIR_WIND', '{"hours_gained": 23.9, "delay_hours": -23.9}'::jsonb, now()),
          (v_voy, greatest(v_t - 1, 6), 'CALM', '{"delay_hours": 30}'::jsonb, now());
        perform voyage.recompute_eta(v_voy);
        update public.voyages set last_settled_day = least(5, voyage.total_days(v_voy)) where id = v_voy;
      end if;
      o  := pg_temp.schedule_old_0169(v_voy, now(), true);
      nw := pg_temp.schedule_0169(v_voy, now(), true);
      if nw is distinct from o then
        raise exception '0169 self-assert FAIL: the % probe voyage''s schedule differs from the pre-image', c.kind;
      end if;
      if strpos(nw, 'H1=') = 0 or strpos(nw, ';E' || (v_t + 1) || '=') = 0 then
        raise exception '0169 self-assert FAIL: the % probe read no schedule', c.kind;
      end if;
      v_probe := v_probe || format('%s (%s days%s); ', c.kind, voyage.total_days(v_voy),
                                   case when c.kind <> 'none' then format(', %s h of delay net', (select delay_hours from public.voyages where id = v_voy)) else '' end);
      update public.voyages set status = 'ARRIVED' where id = v_voy;
    end loop;
    -- a voyage that does not exist: every read answers (or refuses) as before
    o  := pg_temp.schedule_old_0169(v_ghost, now(), true);
    nw := pg_temp.schedule_0169(v_ghost, now(), true);
    if nw is distinct from o or strpos(nw, '!P0001 E_NO_SUCH_VOYAGE') = 0 then
      raise exception '0169 self-assert FAIL: the missing voyage reads differently (old % / new %)', left(o, 300), left(nw, 300);
    end if;
    v_probe := v_probe || 'and a voyage that does not exist (its refusals compared)';
    raise exception 'ROLLBACK_0169_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0169_PROBE' then raise; end if;
  end;
  if exists (select 1 from public.voyage_events ve where ve.payload ? 'hours_gained' and ve.payload->>'hours_gained' = '23.9'
                and ve.resolved_at = now()) then
    raise exception '0169 self-assert FAIL: the probe voyages were not rolled back';
  end if;
  insert into proven_0169 values ('probes', 'own voyages ' || v_probe);
end $$;

-- ── 5. THE TIMING — REPORTED, NOT GATED (old tree vs new, the same inputs, one pass each) ──────
do $$
declare
  v_t0  timestamptz;
  v_old numeric;
  v_new numeric;
  v_n   int;
  v_k   numeric := public.wc_num('time_compression');
begin
  select count(*) into v_n from public.voyages where status = 'SAILING';
  if v_n > 0 then
    v_t0 := clock_timestamp();
    perform count(pg_temp.voyage_days_complete_0169(v.id, pg_temp.voyage_day_ends_at_0169(v.id, v.last_settled_day + 1)))
       from public.voyages v where v.status = 'SAILING';
    v_old := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    v_t0 := clock_timestamp();
    perform count(voyage.days_complete(v.id, voyage.day_ends_at(v.id, v.last_settled_day + 1)))
       from public.voyages v where v.status = 'SAILING';
    v_new := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    insert into timing_0169 values ('days_complete at her next day', v_n, v_old, v_new);
    v_t0 := clock_timestamp();
    perform count(h.occurred) from public.voyages v
      cross join lateral pg_temp.voyage_hazard_roll_0169(v.id, v.last_settled_day + 1) h where v.status = 'SAILING';
    v_old := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    v_t0 := clock_timestamp();
    perform count(h.occurred) from public.voyages v
      cross join lateral voyage.hazard_roll(v.id, v.last_settled_day + 1) h where v.status = 'SAILING';
    v_new := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    insert into timing_0169 values ('hazard_roll at her next day', v_n, v_old, v_new);
    v_t0 := clock_timestamp();
    perform count(*) from public.voyages v where v.status = 'SAILING'
       and (v.eta <= now() or pg_temp.voyage_day_ends_at_0169(v.id, v.last_settled_day + 1) <= now());
    v_old := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    v_t0 := clock_timestamp();
    perform count(*) from public.voyages v where v.status = 'SAILING'
       and (v.eta <= now() or voyage.day_end_from(v.eta, v.departed_at, v.last_settled_day + 1,
                                                  voyage.delay_before_day(v.id, v.last_settled_day + 1), v_k) <= now());
    v_new := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    insert into timing_0169 values ('the candidate scan', v_n, v_old, v_new);
  end if;
  select count(*) into v_n from rank_grid_0169 where t is not null;
  v_t0 := clock_timestamp();
  perform count(pg_temp.world_trade_routes_0169(r.f, null, r.radius, r.lim, r.t)::text) from rank_grid_0169 r where r.t is not null;
  v_old := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  perform count(world.trade_routes(r.f, null, r.radius, r.lim, r.t)::text) from rank_grid_0169 r where r.t is not null;
  v_new := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  insert into timing_0169 values ('a merchant leg''s ranking', v_n, v_old, v_new);
  select count(*) into v_n from lap_sample_0169;
  v_t0 := clock_timestamp();
  perform count(pg_temp.lap_read_old_0169(route_id)::text) from lap_sample_0169;
  v_old := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  perform count(pg_temp.lap_read_0169(route_id)::text) from lap_sample_0169;
  v_new := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  insert into timing_0169 values ('a lap start''s reads', v_n, v_old, v_new);
end $$;

-- ── 6. SELF-ASSERT (catalogue reads) ─────────────────────────────────────────────────────────────
do $$
declare
  d      record;
  h      record;
  v_def  text;
  v_back text;
  v_rev  int := 0;
  v_tim  text;
  p      record;
begin
  -- every body moved by its hunks and reverses to its pre-image; ACL, owner, language, volatility,
  -- definer, config and parallel safety unmoved
  for d in select * from defs_before_0169 order by fn loop
    v_def  := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0169 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0169(v_back, h.new) <> 1 then
        raise exception '0169 self-assert FAIL: hunk % of % is not in the live body once', h.n, d.fn;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back is distinct from d.def then
      raise exception '0169 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    v_rev := v_rev + 1;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, pr.proowner as owner,
           coalesce(pr.proconfig::text, '') as cfg, pr.proparallel as par, l.lanname as lang
      into p from pg_proc pr join pg_language l on l.oid = pr.prolang where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.par <> d.par
       or p.lang <> d.lang or p.owner <> d.owner then
      raise exception '0169 self-assert FAIL: % changed its ACL, owner, volatility, definer, config, parallel safety or language', d.fn;
    end if;
  end loop;
  if v_rev <> 5 then
    raise exception '0169 self-assert FAIL: % bodies checked, not 5', v_rev;
  end if;
  -- the new helpers: server-only (only the owner may execute), PL/pgSQL, as declared
  for p in select pr.oid::regprocedure::text as sig, coalesce(pr.proacl::text, '') as acl, l.lanname as lang
             from pg_proc pr join pg_language l on l.oid = pr.prolang join pg_namespace n on n.oid = pr.pronamespace
            where (n.nspname, pr.proname) in (('voyage', 'day_end_from'), ('world', 'quote_terms'), ('world', 'quote_priced')) loop
    if p.lang <> 'plpgsql' or p.acl ~ '(^|[{,])=X' or p.acl ~ 'anon=' or p.acl ~ 'authenticated=' then
      raise exception '0169 self-assert FAIL: % is not a server-only PL/pgSQL helper (acl %, language %)', p.sig, p.acl, p.lang;
    end if;
  end loop;
  if (select count(*) from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
       where (n.nspname, pr.proname) in (('voyage', 'day_end_from'), ('world', 'quote_terms'), ('world', 'quote_priced'))) <> 3 then
    raise exception '0169 self-assert FAIL: the three helpers are not there once each';
  end if;
  -- ONE HOME EACH: the day boundary's arithmetic is in voyage.day_end_from alone among the bodies cut
  -- here; the quote's term readings are in world.quote_terms alone; world.quote reads nothing itself.
  if (select count(*) from pg_proc pr where pr.pronamespace <> pg_my_temp_schema()
        and strpos(pr.prosrc, 'p_day * 24 + voyage.delay_before_day') > 0) > 0 then
    raise exception '0169 self-assert FAIL: a body still states the day boundary with day_ends_at''s own arithmetic';
  end if;
  if (select count(*) from pg_proc pr where pr.pronamespace <> pg_my_temp_schema()
        and strpos(pr.prosrc, 'world.spread_effective(p_port, p_good, p_fleet, false)') > 0) <> 1
     or strpos((select prosrc from pg_proc where oid = 'world.quote_terms(uuid, uuid, uuid)'::regprocedure),
               'world.spread_effective(p_port, p_good, p_fleet, false)') = 0 then
    raise exception '0169 self-assert FAIL: the quote''s no-bargain term is read outside world.quote_terms';
  end if;
  if strpos((select prosrc from pg_proc where oid = 'world.quote(uuid, uuid, numeric, text, numeric, uuid)'::regprocedure), 'world.quote_priced(') = 0
     or strpos((select prosrc from pg_proc where oid = 'world.quote(uuid, uuid, numeric, text, numeric, uuid)'::regprocedure), 'public.') > 0 then
    raise exception '0169 self-assert FAIL: world.quote is not world.quote_priced asked with no terms';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0169) then
    raise exception '0169 self-assert FAIL: the client entry points moved (% → %)',
      (select entry_points from before_0169), (select count(*) from public.client_rpc_entry_points());
  end if;

  select string_agg(format('%s ×%s %s ms → %s ms (−%s%%)', what, n, old_ms, new_ms,
                           round(100 * (1 - new_ms / greatest(old_ms, 0.1)))), '; ' order by what)
    into v_tim from timing_0169;

  raise notice '0169 self-assert ok: A DAY IS COUNTED ONCE AND A QUAY IS READ ONCE — nothing the sweep decides moved. SAME ANSWERS (old tree vs new, as text): LIVE %; CANDIDATES %; PROBES %; QUOTES %; RANKINGS %; LAPS %. TIMING (reported, not gated — old vs new, the same inputs, one pass): %. BODIES: day_ends_at, days_complete, tick_arrivals, quote and trade_routes reverse to their pre-images hunk by hunk, ACL / owner / volatility / definer / config unmoved; voyage.day_end_from, world.quote_terms and world.quote_priced are server-only PL/pgSQL; the boundary arithmetic and the quote terms have one home each; no new entry point.',
    (select v from proven_0169 where k = 'live'), (select v from proven_0169 where k = 'cand'),
    (select v from proven_0169 where k = 'probes'), (select v from proven_0169 where k = 'quotes'),
    (select v from proven_0169 where k = 'ranks'), (select v from proven_0169 where k = 'laps'), coalesce(v_tim, 'none');
end $$;
