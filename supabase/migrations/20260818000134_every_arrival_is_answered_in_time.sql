-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0134 — EVERY ARRIVAL IS ANSWERED IN TIME  (the arrivals sweep, made faster — nothing it decides moves)
--        plus: 0132's retired table (ship_fittings_retired_0132) is dropped, as the last step
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/RESUME.md (2026-10-17): "Before throwing skills_bite: lit ≈ 2× merchant ship reads; prod
-- arrivals avg 4.5 s / max 11 s vs 10 s budget → speed up arrivals first and re-measure on prod."
-- Prod, cron.job_run_details, byeharu-voyage:arrivals, 2026-10-16 03:31–05:31 UTC (461 runs, 0133 live
-- for the last 15 min): avg 4.55 s, p95 8.48 s, max 11.05 s against arrivals_tick_budget_ms 10 000.
--
-- ── THE PROFILE (prod, READ-ONLY: `begin transaction read only; set local track_functions = 'all';`
--    then pg_stat_xact_user_functions — no write, no sweep, nothing that writes was called) ─────────
--   * Where a run's time goes. Last hour: 2,139 arrivals, 924 laps started → ~9 arrivals and ~3.9 LAP
--     STARTS per 15 s run. A lap start runs public.npc_plan (cmd.run_standing_route, 0114/0120): up to
--     npc_route_candidates (16) loops, every distinct leg priced by public.npc_leg_lines. One merchant
--     (route 03020fb2…, home 5733e295…): candidates 144 ms + 12 distinct legs 1,104 ms ≈ 1.3 s — × 3.9
--     ≈ the whole 4.5 s average. The sweep's candidate scan is 120 ms a run (429 passages at sea).
--   * Inside that lap start (track_functions; totals inflated by the tracking itself):
--       world.trade_routes 519 ms / 12 calls · world.quote 387 ms / 194 · world.mid_price 1,051 calls
--       (≈ 900 of them the quote's own 10-tun steps, each re-reading the market row AND four knobs) ·
--       public.wc / wc_num 5,769 knob reads (227 ms self) · public.npc_known_legs 77 ms / 6 (12 ms each:
--       every merchant route's 2,466 stops windowed to find the legs at ONE harbour) ·
--       public.buff_multiplier 0.26 ms SELF per call, public.city_level 0.12, public.skill_level_at 0.45,
--       voyage.delay_before_day 0.16 (412 calls in the scan) — SQL-language bodies that read a table.
--   * Why a two-line SQL function costs a quarter of a millisecond: PostgreSQL 17 (prod 17.6) re-plans a
--     non-inlined SQL function's body on every call from PL/pgSQL; every one of these is SECURITY DEFINER
--     with a SET (so never inlined). PL/pgSQL caches its plans. (0133 measured the same on CI: dark
--     ship_view +46 % from SQL bodies; PGlite is PG 18, which caches SQL plans, and under-states it.)
--
-- ── WHAT THIS FILE DOES (one authority per concept; every answer is the pre-image — asserted) ─────
-- (1) world.mid_terms(port, good) — NEW: THE one reader of what a market row's price is made of (the
--     row's seven terms and the four price knobs), moved verbatim out of world.mid_price (it refuses
--     E_NO_SUCH_GOOD exactly as mid_price did). world.mid_price composes it with world.mid_from_terms
--     (0053's one expression) — the same answer, the same refusal.
-- (2) world.quote reads mid_terms ONCE per quote and walks its 10-tun steps on world.mid_from_terms —
--     before, every step called mid_price (one market-row read + four knob reads a step). Same steps,
--     same stock walk, same rounding: the same numbers (asserted over a grid, old and new in one
--     statement).
-- (3) public.npc_known_legs windows only the routes that call at the harbour asked about (a route's
--     lead / first_value are its own; a leg from or to p_from can only be on such a route) — the same
--     rows (asserted, every harbour), and PL/pgSQL so its plan is cached.
-- (4) Eleven hot SQL-language readers become PL/pgSQL with their query UNTOUCHED (`return (<the same
--     select>)`, `#variable_conflict use_column` = SQL's own rule that a column outranks a parameter):
--       voyage.delay_before_day, voyage.day_ends_at, voyage.sim_hours, voyage.total_days   (the scan,
--       voyage.settle's day loop, arrival_at) · public.skill_level_at, public.player_skill_bonus   (every
--       skill read: speed, endurance, trade cap) · public.buff_multiplier, public.city_level, world.spread,
--       public.haggle_concession   (every quote) · world.daily_cap_remaining   (the planner, buy / sell).
--     Each was SECURITY DEFINER + SET (asserted) — never inlined — so no caller loses an inlining.
-- The dark / lit semantics of 0133 are untouched: skills_bite, levels_bite, city_treasury are read
-- where they were read, by the same bodies.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Change any rule, price, refusal, schedule, cadence, budget, knob, table, client grant or entry point.
-- Touch npc_plan / npc_leg_lines / world.trade_routes / tick_arrivals / voyage.settle (they read faster
-- through the bodies above; their own text is unchanged). Cache anything across calls (no session state,
-- no memo table). Fix port_offers' per-row probe in trade_routes (555 calls a ranking, 74 ms a lap
-- start): its authority is an inlinable SQL function, left for a later cut.
--
-- ── THE PROOF (all in this file; old and new on the SAME snapshot) ──────────────────────────────
-- §1 keeps the pre-image TREE: every function on a path from the reads below to a changed body is
-- copied under a pg_temp name, its calls to that tree pointed at the copies (asserted: no copy reaches
-- a changed body). §4 then reads old and new side by side IN ONE STATEMENT (one snapshot) and requires
-- byte-equal text: quotes (buy / sell, sized, limited, with and without a fleet), mid prices, spreads,
-- buffs, city levels, haggles, daily caps, skill levels and bonuses, every harbour's known legs, every
-- fleet's speed and endurance, every passage at sea (arrival_at now and a day and a half past her eta —
-- to the microsecond — day boundaries, days, sim hours, delays) plus 2,000 settled passages, the
-- sweep's candidate set, and whole lap-start plans (loops + every leg's lines) for 12 merchants.
-- A world with fewer than 12 passages at sea (PGlite / CI) is topped up through the one start door
-- (cmd.standing_route_assign_for, as 0125 did) inside a rolled-back block. §5 TIMES the lap-start reads,
-- old tree vs new, faster of two passes each, on the same data, and REFUSES less than 10 % off.
--
-- ── WHAT IT BUYS (measured where it could be; ESTIMATED for prod, said plainly) ──────────────────
-- PGlite (PG 18 — it caches SQL plans, so the language wrap barely shows there), the cached world, 12
-- merchants' lap-start reads: 9,451 → 7,546 ms (−20 %); 4,742 quotes 4,922 → 3,205 ms (−35 %).
-- Prod, ESTIMATED from the read-only profile above (one lap start ≈ 780 ms tracked): the quote steps'
-- mid_price ≈ −125 ms, npc_known_legs ≈ −65, buff_multiplier / city_level / skill_level_at / the rest
-- ≈ −90 → ≈ −35 % a lap start, and the scan ≈ 120 → ≈ 40 ms; the sweep ≈ avg 4.5 → ≈ 3 s, p95 8.5 →
-- ≈ 5.5 s. RE-MEASURE ON PROD (cron.job_run_details) after the push, before throwing skills_bite.
--
-- ── LOCKS (db push holds every lock to commit; deploy with the clock unwound) ───────────────────
-- Until §6 nothing here takes a lock any live statement waits on: ACCESS SHARE on what it reads;
-- CREATE OR REPLACE FUNCTION (no table lock); pg_temp objects. The voyage probe (only where < 12
-- passages are at sea, i.e. never on prod) writes inside a rolled-back block.
-- §6 LAST, one short retried step: ACCESS EXCLUSIVE NOWAIT on ship_fittings_retired_0132, then
-- public.ships, then public.item_kinds (its two FKs' triggers live on them; ships → item_kinds is the
-- live order of cmd.do_build / do_fit) → drop. Every lock NOWAIT, so this file never waits while holding
-- one; a busy table is 55P03 at once, the step's subtransaction rolls back, sleeps 0.2 s, retries (10
-- tries), then "LOCK CONTENTION, not a result". Held from there to commit: catalogue reads only.
--
-- ROLLBACK: a forward migration restoring the bodies — every OLD text is here (the conversions' pre-image
-- is the live SQL body, recovered by inverting the wrap; the hunks of mid_price / quote / known_legs are
-- verbatim), and the self-assert proves each live body reverses to its pre-image; drop world.mid_terms.
-- ship_fittings_retired_0132 is not restored (2,113 rows on prod, read by nothing since 0132).
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once:
-- world.mid_price (0053), world.quote (0122), public.npc_known_legs (0120); and, by the language wrap,
-- voyage.delay_before_day / day_ends_at / sim_hours / total_days (0006 line), public.skill_level_at (0131),
-- public.player_skill_bonus (0133), public.buff_multiplier (0026), public.city_level (0123), world.spread
-- (0123), public.haggle_concession (0017), world.daily_cap_remaining (0123).
-- VERSION: 0134. Applies on prod head 0133.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);   -- never queue the arrivals sweep for long
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
-- Run a statement that takes locks; a lock the live world holds (55P03, 40P01) is not an answer:
-- retry, then fail as LOCK CONTENTION. Returns the milliseconds it took.
create or replace function pg_temp.locked_0134(p_sql text, p_what text)
returns numeric
language plpgsql
as $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
  v_t0    timestamptz := clock_timestamp();
begin
  loop
    v_try := v_try + 1;
    begin
      execute p_sql;
      return round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 10 then
      raise exception '0134 self-assert FAIL: LOCK CONTENTION, not a result — % could not get its locks in 10 tries (%: %). Re-run the push.',
        p_what, v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- How many times p_needle occurs in p_hay.
create or replace function pg_temp.occurs_0134(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- THE LANGUAGE WRAP (§3 (4)): a SQL body `AS $function$<core><tail>$function$` (tail = the trailing
-- blanks and at most one `;`) becomes `#variable_conflict use_column / begin / return (<core>); / end`,
-- and nothing else moves: the header keeps every line but the language word. Its inverse recovers the
-- pre-image byte for byte (asserted in §7 on every converted body).
create or replace function pg_temp.wrap_0134(p_def text)
returns text
language plpgsql
immutable
as $$
declare
  c_as    constant text := 'AS $function$';
  c_lang  constant text := E'\n LANGUAGE sql\n';
  v_open  int;
  v_close int;
  v_body  text;
  v_core  text;
begin
  if pg_temp.occurs_0134(p_def, c_lang) <> 1 or pg_temp.occurs_0134(p_def, c_as) <> 1
     or right(p_def, length(E'$function$\n')) <> E'$function$\n' then
    raise exception '0134 self-assert FAIL: a body to wrap is not the shape this file was cut against: %', left(p_def, 120);
  end if;
  v_open  := strpos(p_def, c_as) + length(c_as);
  v_close := length(p_def) - length(E'$function$\n') + 1;
  v_body  := substr(p_def, v_open, v_close - v_open);
  v_core  := regexp_replace(v_body, E'\\s*;?\\s*$', '');
  return replace(substr(p_def, 1, v_open - 1), c_lang, E'\n LANGUAGE plpgsql\n')
         || E'\n#variable_conflict use_column\nbegin\n  return (' || v_core || E'\n  );\nend'
         || substr(v_body, length(v_core) + 1) || E'$function$\n';
end $$;

create or replace function pg_temp.unwrap_0134(p_def text)
returns text
language plpgsql
immutable
as $$
declare
  c_open  constant text := E'AS $function$\n#variable_conflict use_column\nbegin\n  return (';
  c_close constant text := E'\n  );\nend';
  v_open  int;
  v_last  int;
begin
  if pg_temp.occurs_0134(p_def, c_open) <> 1 or pg_temp.occurs_0134(p_def, E'\n LANGUAGE plpgsql\n') <> 1 then
    return null;
  end if;
  v_open := strpos(p_def, c_open);
  v_last := length(p_def) - strpos(reverse(p_def), reverse(c_close)) - length(c_close) + 2;
  return replace(substr(p_def, 1, v_open - 1), E'\n LANGUAGE plpgsql\n', E'\n LANGUAGE sql\n')
         || 'AS $function$' || substr(p_def, v_open + length(c_open), v_last - v_open - length(c_open))
         || substr(p_def, v_last + length(c_close));
end $$;

-- ── 1. THE PRE-IMAGES — every heavy read and the old tree, before anything moves ────────────────
-- (a) the bodies this file changes
create temp table defs_before_0134 on commit drop as
select f.fn, f.how,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef and p.proconfig is not null from pg_proc p where p.oid = f.fn::regprocedure) as sd_set,
       (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = f.fn::regprocedure) as lang
  from (values ('world.mid_price(uuid, uuid, numeric)', 'hunks'),
               ('world.quote(uuid, uuid, numeric, text, numeric, uuid)', 'hunks'),
               ('public.npc_known_legs(uuid)', 'hunks'),
               ('voyage.delay_before_day(uuid, integer)', 'wrap'),
               ('voyage.day_ends_at(uuid, integer)', 'wrap'),
               ('voyage.sim_hours(uuid)', 'wrap'),
               ('voyage.total_days(uuid)', 'wrap'),
               ('public.skill_level_at(uuid, text, timestamp with time zone)', 'wrap'),
               ('public.player_skill_bonus(uuid, text)', 'wrap'),
               ('public.buff_multiplier(text, uuid, text, timestamp with time zone)', 'wrap'),
               ('public.city_level(uuid, text)', 'wrap'),
               ('world.spread(uuid)', 'wrap'),
               ('public.haggle_concession(uuid, uuid, uuid)', 'wrap'),
               ('world.daily_cap_remaining(uuid, uuid, uuid)', 'wrap')) f(fn, how);

create temp table before_0134 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc where pronamespace = 'world'::regnamespace and proname = 'mid_terms') as mid_terms_found,
       to_regclass('public.ship_fittings_retired_0132') is not null as retired_found;

-- (b) THE OLD TREE: every function on a path from the reads §4 compares and §5 times (npc_loop_candidates,
-- npc_leg_lines, fleet_speed, fleet_free_hold, endurance_days, arrival_at, day_ends_at, total_days, and the
-- changed bodies themselves) down to a changed body — computed from the call graph of the live bodies on
-- 2026-10-17 and checked below (no copy may still reach a changed body). Every overload of a name.
create temp table tree_0134 (nsp text, name text) on commit drop;
insert into tree_0134 values
  ('public', 'buff_multiplier'), ('public', 'city_level'), ('public', 'fleet_buy_capacity'),
  ('public', 'fleet_free_hold'), ('public', 'fleet_officer_bonus'), ('public', 'haggle_concession'),
  ('public', 'npc_affordable'), ('public', 'npc_buy_ceiling'), ('public', 'npc_feasible_legs'),
  ('public', 'npc_known_legs'), ('public', 'npc_leg_lines'), ('public', 'npc_loop_candidates'),
  ('public', 'passage_gate'), ('public', 'player_skill_bonus'), ('public', 'ship_hold_capacity'),
  ('public', 'skill_level'), ('public', 'skill_level_at'), ('public', 'works_factor'),
  ('voyage', 'arrival_at'), ('voyage', 'day_ends_at'), ('voyage', 'days_complete'),
  ('voyage', 'delay_before_day'), ('voyage', 'endurance_days'), ('voyage', 'fleet_speed'),
  ('voyage', 'hazard_roll'), ('voyage', 'leg_at_day'), ('voyage', 'progress_nm'), ('voyage', 'sail_refusal'),
  ('voyage', 'ship_speed'), ('voyage', 'sim_hours'), ('voyage', 'total_days'),
  ('world', 'daily_cap_remaining'), ('world', 'mid_price'), ('world', 'quote'), ('world', 'ship_stat'),
  ('world', 'ship_stats'), ('world', 'skill_bonuses'), ('world', 'skill_pct'), ('world', 'spread'),
  ('world', 'spread_effective'), ('world', 'trade_routes');

-- Point a text at the old tree: every `nsp.name(` of the tree → `pg_temp.nsp_name_0134(`. A trailing
-- `(` keeps `skill_level(` from touching `skill_level_at(`.
create or replace function pg_temp.old_sql_0134(p_sql text)
returns text
language plpgsql
stable
as $$
declare
  t record;
  v text := p_sql;
begin
  for t in select nsp, name from tree_0134 order by length(name) desc, nsp, name loop
    v := replace(v, t.nsp || '.' || t.name || '(', 'pg_temp.' || t.nsp || '_' || t.name || '_0134(');
  end loop;
  return v;
end $$;

create temp table old_tree_0134 on commit drop as
select n.nspname as nsp, p.proname as name, p.oid::regprocedure::text as sig,
       pg_temp.old_sql_0134(replace(pg_get_functiondef(p.oid), E'\r', '')) as def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join tree_0134 t on t.nsp = n.nspname and t.name = p.proname;

do $$
declare
  d   record;
  c   record;
  v_n int;
begin
  if (select count(*) from old_tree_0134) < (select count(*) from tree_0134) then
    raise exception '0134 self-assert FAIL: the old tree lists % name(s) but only % live function(s) were found',
      (select count(*) from tree_0134), (select count(*) from old_tree_0134);
  end if;
  -- NO COPY REACHES A CHANGED BODY (and every copy was renamed).
  for d in select * from old_tree_0134 loop
    if strpos(d.def, 'CREATE OR REPLACE FUNCTION pg_temp.' || d.nsp || '_' || d.name || '_0134(') <> 1 then
      raise exception '0134 self-assert FAIL: the old copy of % was not renamed', d.sig;
    end if;
    for c in select split_part(fn, '(', 1) as q from defs_before_0134 loop
      if strpos(d.def, c.q || '(') > 0 then
        raise exception '0134 self-assert FAIL: the old copy of % still calls the live %', d.sig, c.q;
      end if;
    end loop;
  end loop;
  -- SQL copies are parsed at create: the tree is created in one go with body checks off.
  perform set_config('check_function_bodies', 'off', true);
  for d in select * from old_tree_0134 order by nsp, name, sig loop
    execute d.def;
  end loop;
  perform set_config('check_function_bodies', 'on', true);
  select count(*) into v_n from pg_proc where pronamespace = pg_my_temp_schema() and proname like '%\_0134';
  if v_n < (select count(*) from old_tree_0134) then
    raise exception '0134 self-assert FAIL: % old cop(ies) made of %', v_n, (select count(*) from old_tree_0134);
  end if;
end $$;

-- (c) THE LAP-START READ, as npc_plan reads it (0114/0120, as cut by 0129): her hold, crew and speed;
-- her present loop and up to npc_route_candidates others; every distinct leg priced by npc_leg_lines.
-- A probe (pg_temp) — npc_plan itself writes; this reads exactly what it reads, in its order. The OLD
-- variant is the same text pointed at the old tree.
create or replace function pg_temp.lap_read_0134(p_route uuid)
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
  v_def text := replace(pg_get_functiondef('pg_temp.lap_read_0134(uuid)'::regprocedure), E'\r', '');
begin
  v_def := replace(pg_temp.old_sql_0134(v_def), 'FUNCTION pg_temp.lap_read_0134(', 'FUNCTION pg_temp.lap_read_old_0134(');
  -- pg_get_functiondef names a pg_temp function by its real schema; point that line at pg_temp
  v_def := regexp_replace(v_def, 'FUNCTION pg_temp_[0-9]+\.lap_read_0134\(', 'FUNCTION pg_temp.lap_read_old_0134(');
  if strpos(v_def, 'lap_read_old_0134(') = 0 or strpos(v_def, 'pg_temp.public_npc_leg_lines_0134(') = 0
     or strpos(v_def, 'pg_temp.voyage_fleet_speed_0134(') = 0 or strpos(v_def, 'pg_temp.public_npc_loop_candidates_0134(') = 0 then
    raise exception '0134 self-assert FAIL: the old lap read was not pointed at the old tree';
  end if;
  execute v_def;
end $$;

-- the merchants whose lap-start reads are compared and timed: 12, spread by a hash of the route id
create temp table lap_sample_0134 on commit drop as
select sr.id as route_id
  from public.standing_routes sr
  join public.players p on p.id = sr.player_id and p.is_npc
 where (select count(*) from public.standing_route_stops s where s.route_id = sr.id) >= 2
   and exists (select 1 from public.ships s
                where s.fleet_id = coalesce(sr.fleet_id, (select nf.fleet_id from public.npc_fleets nf where nf.route_id = sr.id limit 1)))
 order by md5(sr.id::text), sr.id
 limit 12;

-- ── 2. THE ONE READER OF A PRICE'S TERMS ───────────────────────────────────────────────────────
create or replace function world.mid_terms(p_port uuid, p_good uuid,
                                           out m_base numeric, out m_affinity numeric, out m_demand numeric,
                                           out m_target numeric, out m_drift numeric, out m_season numeric,
                                           out m_dev integer, out m_elasticity numeric, out m_dev_discount numeric,
                                           out m_band_lo numeric, out m_band_hi numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0134: WHAT A MARKET ROW'S PRICE IS MADE OF — the row's seven terms and the four price knobs, moved
-- verbatim out of world.mid_price (0053), which now composes this with world.mid_from_terms, as does
-- world.quote once per quote (its steps then walk the stock on the one expression alone). Refuses a
-- missing market row E_NO_SUCH_GOOD, as mid_price did, before any knob is read. Server-only.
begin
  select g.base_value, pg.affinity, pg.demand, pg.stock_target, pg.drift, pg.season_mod, p.dev_commerce
    into m_base, m_affinity, m_demand, m_target, m_drift, m_season, m_dev
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id
    join public.ports p on p.id = pg.port_id
   where pg.port_id = p_port and pg.good_id = p_good;

  if m_base is null then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;

  m_elasticity   := public.wc_num('price_elasticity');
  m_dev_discount := public.wc_num('mid_dev_discount');
  m_band_lo      := public.wc_num('price_band_lo');
  m_band_hi      := public.wc_num('price_band_hi');
end $$;
comment on function world.mid_terms(uuid, uuid) is
  '0134: THE reader of a market row''s price terms (row + the four price knobs). world.mid_price and '
  'world.quote compose it with world.mid_from_terms. Server-only.';
revoke all on function world.mid_terms(uuid, uuid) from public, anon, authenticated;

-- ── 3. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
-- (a) hunks (old = verbatim from the live bodies; new = what replaces it)
create temp table hunks_0134 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0134 values
-- world.mid_price: the terms from the one reader
('world.mid_price(uuid, uuid, numeric)', 1,
$h$declare
  v_base   numeric;
  v_aff    numeric;
  v_target numeric;
  v_drift  numeric;
  v_season numeric;
  v_dev    int;
  v_dem    numeric;
begin
  select g.base_value, pg.affinity, pg.demand, pg.stock_target, pg.drift, pg.season_mod, p.dev_commerce
    into v_base, v_aff, v_dem, v_target, v_drift, v_season, v_dev
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id
    join public.ports p on p.id = pg.port_id
   where pg.port_id = p_port and pg.good_id = p_good;

  if v_base is null then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;

  -- The arithmetic left this body in 0053; it did not multiply. This is the row-at-a-time door to
  -- the one expression, and it costs exactly what it cost before, because the callee is inlined.
  return world.mid_from_terms(v_base, v_aff, v_dem, v_target, p_stock, v_drift, v_season, v_dev,
                              public.wc_num('price_elasticity'), public.wc_num('mid_dev_discount'),
                              public.wc_num('price_band_lo'),    public.wc_num('price_band_hi'));
end $function$$h$,
$h$declare
  t record;   -- 0134: the row's terms and the price knobs, from world.mid_terms
begin
  -- 0134: WHAT THE PRICE IS MADE OF is world.mid_terms' (moved there verbatim; it refuses a missing row
  -- E_NO_SUCH_GOOD as this body did). The arithmetic left this body in 0053; it did not multiply. This
  -- is the row-at-a-time door to the one expression (inlined).
  select * into t from world.mid_terms(p_port, p_good);
  return world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, p_stock, t.m_drift,
                              t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
end $function$$h$),
-- world.quote: the terms once; the steps walk the stock on the one expression
('world.quote(uuid, uuid, numeric, text, numeric, uuid)', 1,
$h$  v_hag_t  numeric := 0;
begin$h$,
$h$  v_hag_t  numeric := 0;
  t        record;    -- 0134: the market row's price terms, read ONCE (world.mid_terms)
begin$h$),
('world.quote(uuid, uuid, numeric, text, numeric, uuid)', 2,
$h$    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;
$h$,
$h$    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;
  -- 0134: WHAT THE PRICE IS MADE OF, read once: each step below re-priced through world.mid_price,
  -- which re-read this row and four knobs every 10 tuns. The stock walk is unchanged.
  select * into t from world.mid_terms(p_port, p_good);
$h$),
('world.quote(uuid, uuid, numeric, text, numeric, uuid)', 3,
$h$      exit when v_n <= 0;
      v_mid  := world.mid_price(p_port, p_good, v_stock);
$h$,
$h$      exit when v_n <= 0;
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_stock, t.m_drift,   -- 0134
                                     t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
$h$),
('world.quote(uuid, uuid, numeric, text, numeric, uuid)', 4,
$h$    else
      v_mid  := world.mid_price(p_port, p_good, v_stock);
$h$,
$h$    else
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_stock, t.m_drift,   -- 0134
                                     t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
$h$),
-- public.npc_known_legs: PL/pgSQL (plan cached), and only the routes that call at p_from are windowed
('public.npc_known_legs(uuid)', 1,
$h$
 LANGUAGE sql
$h$,
$h$
 LANGUAGE plpgsql
$h$),
('public.npc_known_legs(uuid)', 2,
$h$AS $function$
  -- 0120: THE COURSES THE WORLD HOLDS$h$,
$h$AS $function$
#variable_conflict use_column
begin
  -- 0120: THE COURSES THE WORLD HOLDS$h$),
('public.npc_known_legs(uuid)', 3,
$h$  with ms as ($h$,
$h$  return query
  with ms as ($h$),
('public.npc_known_legs(uuid)', 4,
$h$      join public.players p on p.id = sr.player_id and p.is_npc),$h$,
$h$      join public.players p on p.id = sr.player_id and p.is_npc
     -- 0134: ONLY THE ROUTES THAT CALL AT p_from — a leg from or to it lies on such a route, and a
     -- route's lead / first_value are its own (was: every merchant route's stops, 12 ms a harbour).
     where s.route_id in (select t.route_id from public.standing_route_stops t where t.port_id = p_from)),$h$),
('public.npc_known_legs(uuid)', 5,
$h$   order by w.to_port, w.reversed, jsonb_array_length(w.course)
$function$$h$,
$h$   order by w.to_port, w.reversed, jsonb_array_length(w.course);
end
$function$$h$);

create or replace function pg_temp.recut_0134(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0134 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0134(v_def, h.old);
    if v_n <> 1 then
      raise exception '0134 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0134(fn) from defs_before_0134 where how = 'hunks' order by fn;

-- (b) the language wrap — each body was SQL, SECURITY DEFINER with a SET (never inlined)
do $$
declare
  d record;
begin
  for d in select * from defs_before_0134 where how = 'wrap' order by fn loop
    if d.lang <> 'sql' or not d.sd_set then
      raise exception '0134 self-assert FAIL: % is % / sd+set %, not the SQL SECURITY DEFINER body this file wraps', d.fn, d.lang, d.sd_set;
    end if;
    execute pg_temp.wrap_0134(d.def);
  end loop;
end $$;

comment on function public.npc_known_legs(uuid) is
  '0120/0134: the courses the merchant routes hold out of one harbour (forward, and reversed legs into it), '
  'one per destination, with the reach table''s distance. PL/pgSQL; windows only the routes that call there. '
  'Server-only.';

-- ── 4. THE COMPARISONS — old tree and new, side by side in ONE statement each (one snapshot) ─────
create temp table proven_0134 (k text primary key, v text) on commit drop;

-- (a) quotes: every port's own wares, bought and sold at a working size; a stride of all market rows at
-- one tun and at 200 with a limit; and, with a FLEET named (her purser + today's bargain), every bargain
-- struck today (haggle_daily) plus one fleet per harbour's wares.
create temp table quotes_0134 on commit drop as
with grid as (
  select ps.port_id, ps.good_id, x.qty, x.side, null::numeric as lim, null::uuid as fleet
    from public.port_specialties ps
   cross join (values (60::numeric, 'buy'), (60::numeric, 'sell')) x(qty, side)
  union all
  select pg.port_id, pg.good_id, x.qty, x.side,
         case when x.qty = 200 then round(world.mid_price(pg.port_id, pg.good_id, pg.stock), 2) end, null
    from (select pg0.*, row_number() over (order by pg0.port_id, pg0.good_id) as k from public.port_goods pg0) pg
   cross join (values (1::numeric, 'buy'), (200::numeric, 'sell'), (200::numeric, 'buy')) x(qty, side)
   where pg.k % 211 = 0
  union all
  select h.port_id, h.good_id, 60, x.side, null, f.id
    from (select * from public.haggle_daily order by game_day desc, player_id, port_id, good_id limit 500) h
    join lateral (select fl.id from public.fleets fl where fl.player_id = h.player_id order by fl.id limit 1) f on true
   cross join (values ('buy'), ('sell')) x(side)
  union all
  select ps.port_id, ps.good_id, 40, 'buy', null, f.id
    from (select distinct on (port_id) port_id, good_id from public.port_specialties order by port_id, good_id) ps
    join lateral (select fl.id from public.fleets fl where fl.port_id = ps.port_id order by fl.id limit 1) f on true)
select g.*, to_jsonb(qn) as new_q, to_jsonb(qo) as old_q
  from grid g
 cross join lateral world.quote(g.port_id, g.good_id, g.qty, g.side, g.lim, g.fleet) qn
 cross join lateral pg_temp.world_quote_0134(g.port_id, g.good_id, g.qty, g.side, g.lim, g.fleet) qo;

-- (b) the price primitives over the world
create temp table prims_0134 on commit drop as
select 'mid_price' as what, pg.port_id::text || '/' || pg.good_id::text || '/' || s.stock::text as at,
       world.mid_price(pg.port_id, pg.good_id, s.stock)::text as new_v,
       pg_temp.world_mid_price_0134(pg.port_id, pg.good_id, s.stock)::text as old_v
  from (select pg0.*, row_number() over (order by pg0.port_id, pg0.good_id) as k from public.port_goods pg0) pg
 cross join lateral (values (pg.stock), (pg.stock * 2 + 7), (0::numeric)) s(stock)
 where pg.k % 23 = 0
union all
select 'spread', p.id::text, world.spread(p.id)::text, pg_temp.world_spread_0134(p.id)::text from public.ports p
union all
select 'buff', p.id::text || '/' || e.eff, public.buff_multiplier(e.kind, p.id, e.eff, now())::text,
       pg_temp.public_buff_multiplier_0134(e.kind, p.id, e.eff, now())::text
  from public.ports p cross join (values ('PORT', 'SPREAD'), ('PORT', 'PRICE'), ('port', 'spread')) e(kind, eff)
union all
select 'buff_subject', ab.subject_id::text || '/' || k.effect, public.buff_multiplier(k.subject_kind, ab.subject_id, k.effect, ab.starts_at)::text,
       pg_temp.public_buff_multiplier_0134(k.subject_kind, ab.subject_id, k.effect, ab.starts_at)::text
  from public.active_buffs ab join public.buff_kinds k on k.code = ab.kind_code
union all
select 'city_level', p.id::text || '/' || w.kind, public.city_level(p.id, w.kind)::text, pg_temp.public_city_level_0134(p.id, w.kind)::text
  from public.ports p cross join (values ('market'), ('docks'), ('yard'), ('no_such_work')) w(kind)
union all
select 'city_level_built', cw.port_id::text || '/' || cw.kind, public.city_level(cw.port_id, cw.kind)::text,
       pg_temp.public_city_level_0134(cw.port_id, cw.kind)::text
  from public.city_works cw
union all
select 'haggle', h.player_id::text || '/' || h.port_id::text || '/' || h.good_id::text,
       public.haggle_concession(h.player_id, h.port_id, h.good_id)::text,
       pg_temp.public_haggle_concession_0134(h.player_id, h.port_id, h.good_id)::text
  from (select * from public.haggle_daily order by game_day desc, player_id, port_id, good_id limit 1000) h
union all
select 'daily_cap', td.player_id::text || '/' || td.port_id::text || '/' || td.good_id::text,
       world.daily_cap_remaining(td.player_id, td.port_id, td.good_id)::text,
       pg_temp.world_daily_cap_remaining_0134(td.player_id, td.port_id, td.good_id)::text
  from (select * from public.trade_daily order by game_day desc, player_id, port_id, good_id limit 3000) td
union all
select 'daily_cap_wares', pl.id::text || '/' || ps.port_id::text || '/' || ps.good_id::text,
       world.daily_cap_remaining(pl.id, ps.port_id, ps.good_id)::text,
       pg_temp.world_daily_cap_remaining_0134(pl.id, ps.port_id, ps.good_id)::text
  from (select id from public.players order by id limit 40) pl
 cross join (select * from public.port_specialties order by port_id, good_id limit 60) ps
union all
select 'skill_bonus', pl.id::text || '/' || e.eff, public.player_skill_bonus(pl.id, e.eff)::text,
       pg_temp.public_player_skill_bonus_0134(pl.id, e.eff)::text
  from public.players pl cross join (values ('ENDURANCE'), ('SPEED'), ('TRADE_CAP'), ('SPREAD'), ('speed')) e(eff)
union all
select 'skill_level_at', x.player_id::text || '/' || sk.code || '/' || t.at::text,
       public.skill_level_at(x.player_id, sk.code, t.at)::text,
       pg_temp.public_skill_level_at_0134(x.player_id, sk.code, t.at)::text
  from (select y.player_id, y.skill_id
          from (select player_id, skill_id from public.player_skills
                union select player_id, skill_id from public.skill_queue) y
         order by y.player_id, y.skill_id limit 1500) x
  join public.skills sk on sk.id = x.skill_id
 cross join (values (now()), (now() + interval '3 days'), (now() + interval '400 days')) t(at)
union all
select 'known_legs', p.id::text,
       (select coalesce(jsonb_agg(to_jsonb(l) order by l.to_port), '[]'::jsonb)::text from public.npc_known_legs(p.id) l),
       (select coalesce(jsonb_agg(to_jsonb(l) order by l.to_port), '[]'::jsonb)::text from pg_temp.public_npc_known_legs_0134(p.id) l)
  from public.ports p where p.kind = 'HARBOUR'
union all
select 'fleet_speed', f.id::text, voyage.fleet_speed(f.id)::text, pg_temp.voyage_fleet_speed_0134(f.id)::text
  from public.fleets f where exists (select 1 from public.ships s where s.fleet_id = f.id)
union all
select 'endurance', f.id::text, voyage.endurance_days(f.id)::text, pg_temp.voyage_endurance_days_0134(f.id)::text
  from public.fleets f where exists (select 1 from public.ships s where s.fleet_id = f.id);

-- (c) every passage at sea and the 2,000 latest others: her true arrival now and a day and a half past
-- her eta (the walk over the unresolved days), her next three day boundaries and delays, her days and
-- sim hours — and the sweep's candidate set (fleets due), old predicate against new.
create or replace function pg_temp.voyage_rows_0134()
returns table (what text, at text, new_v text, old_v text)
language sql
as $$
  with vs as (
    select v.* from public.voyages v where v.status = 'SAILING'
    union all
    select x.* from (select v2.* from public.voyages v2 where v2.status <> 'SAILING'
                     order by v2.departed_at desc, v2.id limit 2000) x)
  select 'arrival_now', vs.id::text, voyage.arrival_at(vs.id, now())::text, pg_temp.voyage_arrival_at_0134(vs.id, now())::text from vs
  union all
  select 'arrival_walk', vs.id::text, voyage.arrival_at(vs.id, vs.eta + interval '36 hours')::text,
         pg_temp.voyage_arrival_at_0134(vs.id, vs.eta + interval '36 hours')::text from vs
  union all
  select 'day_ends_at', vs.id::text || '/' || d.d::text, voyage.day_ends_at(vs.id, vs.last_settled_day + d.d)::text,
         pg_temp.voyage_day_ends_at_0134(vs.id, vs.last_settled_day + d.d)::text
    from vs cross join (values (1), (2), (3)) d(d)
  union all
  select 'delay_before_day', vs.id::text || '/' || d.d::text, voyage.delay_before_day(vs.id, vs.last_settled_day + d.d)::text,
         pg_temp.voyage_delay_before_day_0134(vs.id, vs.last_settled_day + d.d)::text
    from vs cross join (values (1), (3), (999)) d(d)
  union all
  select 'total_days', vs.id::text, voyage.total_days(vs.id)::text, pg_temp.voyage_total_days_0134(vs.id)::text from vs
  union all
  select 'sim_hours', vs.id::text, voyage.sim_hours(vs.id)::text, pg_temp.voyage_sim_hours_0134(vs.id)::text from vs
  union all
  select 'scan', 'due', (select coalesce(string_agg(v.fleet_id::text, ',' order by v.fleet_id), '')
                           from public.voyages v where v.status = 'SAILING'
                            and (v.eta <= now() or voyage.day_ends_at(v.id, v.last_settled_day + 1) <= now())),
                        (select coalesce(string_agg(v.fleet_id::text, ',' order by v.fleet_id), '')
                           from public.voyages v where v.status = 'SAILING'
                            and (v.eta <= now() or pg_temp.voyage_day_ends_at_0134(v.id, v.last_settled_day + 1) <= now()))
$$;

create temp table voyages_0134 (what text, at text, new_v text, old_v text) on commit drop;
create temp table voyage_probe_0134 (sailing int, probes int, walked int, scan_old_ms numeric, scan_new_ms numeric) on commit drop;

-- A world with fewer than 12 passages at sea (PGlite, CI) is topped up through the one start door, as
-- 0125 did, inside a block that rolls back; the comparison is read before the rollback. On prod (hundreds
-- at sea) nothing is written and the block only reads.
create or replace function pg_temp.voyage_probe_0134()
returns void
language plpgsql
as $$
declare
  r        record;
  v_rows   jsonb;
  v_sail   int;
  v_probes int := 0;
  v_walked int;
  v_t0     timestamptz;
  v_old    numeric;
  v_new    numeric;
  v_n      int;
  i        int;
begin
  begin
    select count(*) into v_sail from public.voyages where status = 'SAILING';
    if v_sail < 12 then
      update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
      for r in select nf.fleet_id, nf.route_id, f.player_id
                 from public.npc_fleets nf
                 join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
                 join public.standing_route_stops st on st.route_id = nf.route_id and st.ord = 0 and st.port_id = f.port_id
                 join public.players pl on pl.id = f.player_id
                 join public.standing_routes sr on sr.id = nf.route_id
                where nf.route_id is not null and pl.ducats >= sr.reserve
                  and not exists (select 1 from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING')
                order by nf.roster_ord, nf.fleet_id limit 40 loop
        exit when v_probes >= 12;
        perform cmd.standing_route_assign_for(r.player_id, r.route_id, r.fleet_id);
        if exists (select 1 from public.voyages v where v.fleet_id = r.fleet_id and v.status = 'SAILING') then
          v_probes := v_probes + 1;
        end if;
      end loop;
      -- a third of the probes rewound past their eta (departed_at and eta back together, as 0125's proof
      -- 12 rewinds), so the scan finds them due and arrival_at walks their unresolved days
      update public.voyages v
         set departed_at = v.departed_at - (v.eta - now()) - interval '2 hours',
             eta = now() - interval '2 hours'
       where v.status = 'SAILING' and v.id in (select v3.id from public.voyages v3 where v3.status = 'SAILING'
                                                order by v3.id limit greatest(1, v_probes / 3));
    end if;
    select count(*) into v_sail from public.voyages where status = 'SAILING';
    select count(*) into v_walked from public.voyages where status = 'SAILING' and eta <= now();
    select jsonb_agg(jsonb_build_array(x.what, x.at, x.new_v, x.old_v)) into v_rows from pg_temp.voyage_rows_0134() x;
    -- the scan, timed: faster of two passes each
    for i in 1 .. 2 loop
      v_t0 := clock_timestamp();
      select count(*) into v_n from public.voyages v where v.status = 'SAILING'
         and (v.eta <= now() or pg_temp.voyage_day_ends_at_0134(v.id, v.last_settled_day + 1) <= now());
      v_old := least(coalesce(v_old, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
      v_t0 := clock_timestamp();
      select count(*) into v_n from public.voyages v where v.status = 'SAILING'
         and (v.eta <= now() or voyage.day_ends_at(v.id, v.last_settled_day + 1) <= now());
      v_new := least(coalesce(v_new, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    end loop;
    raise exception using errcode = 'P0134', message = 'roll the voyage probe back';
  exception when sqlstate 'P0134' then
    null;
  end;
  insert into voyages_0134 select x->>0, x->>1, x->>2, x->>3 from jsonb_array_elements(coalesce(v_rows, '[]'::jsonb)) x;
  insert into voyage_probe_0134 values (v_sail, v_probes, v_walked, v_old, v_new);
end $$;

select pg_temp.voyage_probe_0134();

-- (d) whole lap-start reads, 12 merchants
create temp table laps_0134 on commit drop as
select s.route_id, pg_temp.lap_read_0134(s.route_id) as new_v, pg_temp.lap_read_old_0134(s.route_id) as old_v
  from lap_sample_0134 s;

do $$
declare
  v_n    int;
  v_bad  int;
  v_ex   text;
  r      record;
  v_legs int;
  v_kept int;
begin
  -- (a) quotes
  select count(*), count(*) filter (where new_q::text is distinct from old_q::text) into v_n, v_bad from quotes_0134;
  select min(format('%s %s %s %s/%s: new %s old %s', side, qty, lim, port_id, good_id, new_q, old_q)) into v_ex
    from quotes_0134 where new_q::text is distinct from old_q::text;
  if v_n < 100 or v_bad > 0 then
    raise exception '0134 self-assert FAIL: quotes — % of % differ from the pre-image (e.g. %)', v_bad, v_n, v_ex;
  end if;
  if (select count(*) from quotes_0134 where fleet is not null) < 1
     or (select count(*) from quotes_0134 where (new_q->>'units')::numeric > 0 and (new_q->>'total')::numeric > 0) < 50 then
    raise exception '0134 self-assert FAIL: the quote grid is vacuous (fleet quotes %, filled quotes %)',
      (select count(*) from quotes_0134 where fleet is not null),
      (select count(*) from quotes_0134 where (new_q->>'units')::numeric > 0 and (new_q->>'total')::numeric > 0);
  end if;
  insert into proven_0134 values ('quotes', format('%s quotes (%s with a fleet, %s limited) = the pre-image as text', v_n,
    (select count(*) from quotes_0134 where fleet is not null), (select count(*) from quotes_0134 where lim is not null)));

  -- (b) primitives
  for r in select what, count(*) as n, count(*) filter (where new_v is distinct from old_v) as bad,
                  min(at) filter (where new_v is distinct from old_v) as ex
             from prims_0134 group by what order by what loop
    if r.bad > 0 then
      raise exception '0134 self-assert FAIL: % — % of % differ from the pre-image (e.g. at %)', r.what, r.bad, r.n, r.ex;
    end if;
  end loop;
  for r in select w.what from (values ('mid_price'), ('spread'), ('buff'), ('city_level'), ('skill_bonus'),
                                      ('known_legs'), ('fleet_speed'), ('endurance'), ('daily_cap_wares')) w(what)
            where not exists (select 1 from prims_0134 p where p.what = w.what) loop
    raise exception '0134 self-assert FAIL: nothing was compared for %', r.what;
  end loop;
  if (select count(*) from prims_0134 where what = 'known_legs' and new_v <> '[]') < 1 then
    raise exception '0134 self-assert FAIL: no harbour has a known leg — the known-legs comparison is vacuous';
  end if;
  insert into proven_0134 values ('prims', (select string_agg(format('%s %s', n, what), ', ' order by what)
                                              from (select what, count(*) n from prims_0134 group by what) z));

  -- (c) voyages
  select count(*), count(*) filter (where new_v is distinct from old_v) into v_n, v_bad from voyages_0134;
  select min(format('%s at %s: new %s old %s', what, at, new_v, old_v)) into v_ex from voyages_0134 where new_v is distinct from old_v;
  if v_bad > 0 then
    raise exception '0134 self-assert FAIL: voyages — % of % differ from the pre-image (e.g. %)', v_bad, v_n, v_ex;
  end if;
  if (select sailing from voyage_probe_0134) < 3 or (select count(*) from voyages_0134 where what = 'arrival_walk') < 3
     or (select new_v from voyages_0134 where what = 'scan') = '' then
    raise exception '0134 self-assert FAIL: the voyage comparison is vacuous (% at sea, % walked, scan "%")',
      (select sailing from voyage_probe_0134), (select count(*) from voyages_0134 where what = 'arrival_walk'),
      (select new_v from voyages_0134 where what = 'scan');
  end if;
  insert into proven_0134 values ('voyages', format('%s reads over %s passage(s) at sea (%s probe(s) added, %s past their eta) and %s settled: arrival_at now and eta + 36 h to the microsecond, day boundaries, delays, days, sim hours, and the sweep''s candidate set (%s fleet(s) due) = the pre-image',
    v_n, (select sailing from voyage_probe_0134), (select probes from voyage_probe_0134), (select walked from voyage_probe_0134),
    (select count(*) from voyages_0134 where what = 'total_days') - (select sailing from voyage_probe_0134),
    array_length(string_to_array((select new_v from voyages_0134 where what = 'scan'), ','), 1)));

  -- (d) lap starts
  select count(*), count(*) filter (where new_v::text is distinct from old_v::text) into v_n, v_bad from laps_0134;
  if v_n < 1 or v_bad > 0 then
    raise exception '0134 self-assert FAIL: lap-start reads — % of % differ from the pre-image', v_bad, v_n;
  end if;
  select sum((select count(*) from jsonb_object_keys(new_v->'legs'))),
         sum((select count(*) from jsonb_each(new_v->'legs') e where (e.value->>'any')::boolean))
    into v_legs, v_kept from laps_0134;
  if v_legs < v_n then
    raise exception '0134 self-assert FAIL: the lap-start reads priced % leg(s) for % merchant(s)', v_legs, v_n;
  end if;
  insert into proven_0134 values ('laps', format('%s merchants'' lap-start reads (%s loops, %s distinct legs priced, %s with a parcel kept) = the pre-image as text',
    v_n, (select sum(jsonb_array_length(new_v->'loops')) from laps_0134), v_legs, v_kept));
end $$;

-- ── 5. THE TIMING — old tree against new, the same merchants, the same data, faster of two passes ──
create temp table timing_0134 (what text, old_ms numeric, new_ms numeric) on commit drop;
do $$
declare
  v_t0  timestamptz;
  v_old numeric;
  v_new numeric;
  v_n   int;
  i     int;
begin
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    select count(pg_temp.lap_read_old_0134(route_id)) into v_n from lap_sample_0134;
    v_old := least(coalesce(v_old, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    v_t0 := clock_timestamp();
    select count(pg_temp.lap_read_0134(route_id)) into v_n from lap_sample_0134;
    v_new := least(coalesce(v_new, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  end loop;
  insert into timing_0134 values ('lap_starts', v_old, v_new);
  v_old := null; v_new := null;
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    select count(*) into v_n from quotes_0134 g
     cross join lateral pg_temp.world_quote_0134(g.port_id, g.good_id, g.qty, g.side, g.lim, g.fleet) q;
    v_old := least(coalesce(v_old, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    v_t0 := clock_timestamp();
    select count(*) into v_n from quotes_0134 g
     cross join lateral world.quote(g.port_id, g.good_id, g.qty, g.side, g.lim, g.fleet) q;
    v_new := least(coalesce(v_new, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  end loop;
  insert into timing_0134 values ('quotes', v_old, v_new);
  -- THE GATE: a lap start — the bulk of a sweep run on prod — must be materially faster.
  select old_ms, new_ms into v_old, v_new from timing_0134 where what = 'lap_starts';
  if v_new > v_old * 0.90 then
    raise exception '0134 self-assert FAIL: the lap-start reads are not materially faster: % ms (old tree) → % ms (new), faster of 2 passes; this file promises at least 10 %% off',
      v_old, v_new;
  end if;
end $$;

-- ── 6. LAST: drop ship_fittings_retired_0132 — one short retried step, NOWAIT, fixed order ────────
-- Nothing may name it: no function body, no view, no rule, no foreign key INTO it (positive controls:
-- the scans find 0132's view public.ship_fittings over fitted_units, and the retired table's own FKs).
do $$
declare
  v_n int;
begin
  if not (select retired_found from before_0134) then
    raise exception '0134 self-assert FAIL: ship_fittings_retired_0132 is not there to drop';
  end if;
  select count(*) into v_n from pg_proc p
   where strpos(p.prosrc, 'ship_fittings_retired_0132') > 0 and p.pronamespace <> pg_my_temp_schema();
  if v_n > 0 then
    raise exception '0134 self-assert FAIL: % function bod(ies) still name ship_fittings_retired_0132', v_n;
  end if;
  if (select count(*) from pg_proc p where strpos(p.prosrc, 'fitted_units') > 0) < 1 then
    raise exception '0134 self-assert FAIL: the body scan is blind (no body names fitted_units)';
  end if;
  select count(*) into v_n from pg_views where strpos(definition, 'ship_fittings_retired_0132') > 0;
  if v_n > 0 then
    raise exception '0134 self-assert FAIL: % view(s) read ship_fittings_retired_0132', v_n;
  end if;
  if (select count(*) from pg_views where schemaname = 'public' and viewname = 'ship_fittings'
                                      and strpos(definition, 'fitted_units') > 0) <> 1 then
    raise exception '0134 self-assert FAIL: the view scan is blind (public.ship_fittings over fitted_units not seen)';
  end if;
  select count(*) into v_n from pg_constraint where confrelid = 'public.ship_fittings_retired_0132'::regclass;
  if v_n > 0 then
    raise exception '0134 self-assert FAIL: % foreign key(s) point INTO ship_fittings_retired_0132', v_n;
  end if;
  if (select count(*) from pg_constraint where conrelid = 'public.ship_fittings_retired_0132'::regclass and contype = 'f') <> 2 then
    raise exception '0134 self-assert FAIL: the retired table''s own two FKs (to ships, item_kinds) were not seen';
  end if;
  select count(*) into v_n from pg_rewrite rw join pg_depend d on d.objid = rw.oid
   where d.refobjid = 'public.ship_fittings_retired_0132'::regclass and rw.ev_class <> 'public.ship_fittings_retired_0132'::regclass;
  if v_n > 0 then
    raise exception '0134 self-assert FAIL: % rule(s) / view(s) depend on ship_fittings_retired_0132', v_n;
  end if;
  insert into proven_0134 values ('retired', format('%s row(s), named by no body / view / rule / FK', (select count(*) from public.ship_fittings_retired_0132)));
end $$;

create temp table swap_0134 (what text, ms numeric, at timestamptz) on commit drop;
insert into swap_0134 (what, ms, at)
select 'last', pg_temp.locked_0134($last$
  lock table public.ship_fittings_retired_0132 in access exclusive mode nowait;
  lock table public.ships in access exclusive mode nowait;
  lock table public.item_kinds in access exclusive mode nowait;
  drop table public.ship_fittings_retired_0132;
$last$, 'the last step (drop ship_fittings_retired_0132)'), clock_timestamp();

-- ── 7. SELF-ASSERT (light: catalogue reads) ───────────────────────────────────────────────────────
do $$
declare
  d      record;
  h      record;
  v_def  text;
  v_back text;
  v_rev  int := 0;
  v_tim  text;
begin
  -- every body moved as the header says, and reverses to its pre-image; ACL, volatility, definer unmoved
  for d in select * from defs_before_0134 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    if d.how = 'wrap' then
      if v_def <> pg_temp.wrap_0134(d.def) then
        raise exception '0134 self-assert FAIL: % is not its wrapped pre-image', d.fn;
      end if;
      v_back := pg_temp.unwrap_0134(v_def);
    else
      v_back := v_def;
      for h in select * from hunks_0134 where fn = d.fn order by n desc loop
        if pg_temp.occurs_0134(v_back, h.new) <> 1 then
          raise exception '0134 self-assert FAIL: hunk % of % is not in the live body once', h.n, d.fn;
        end if;
        v_back := replace(v_back, h.new, h.old);
      end loop;
    end if;
    if v_back is distinct from d.def then
      raise exception '0134 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    v_rev := v_rev + 1;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.acl
       or (select p.provolatile from pg_proc p where p.oid = d.fn::regprocedure) <> d.vol
       or (select p.prosecdef and p.proconfig is not null from pg_proc p where p.oid = d.fn::regprocedure) is distinct from d.sd_set then
      raise exception '0134 self-assert FAIL: % changed its ACL, volatility or definer', d.fn;
    end if;
    if (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = d.fn::regprocedure) <> 'plpgsql' then
      raise exception '0134 self-assert FAIL: % is not PL/pgSQL', d.fn;
    end if;
  end loop;
  if v_rev <> 14 then
    raise exception '0134 self-assert FAIL: % bodies checked, not 14', v_rev;
  end if;

  -- the new reader: server-only; no new entry point
  if (select count(*) from pg_proc where pronamespace = 'world'::regnamespace and proname = 'mid_terms') <> 1
     or (select mid_terms_found from before_0134) <> 0 then
    raise exception '0134 self-assert FAIL: world.mid_terms is not one new function';
  end if;
  if has_function_privilege('anon', 'world.mid_terms(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'world.mid_terms(uuid, uuid)', 'execute') then
    raise exception '0134 self-assert FAIL: world.mid_terms is callable by a client';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0134) then
    raise exception '0134 self-assert FAIL: the client entry points moved (% → %)',
      (select entry_points from before_0134), (select count(*) from public.client_rpc_entry_points());
  end if;
  -- the price terms' two invariants world.quote now reads them under: a market row's good and port exist
  if (select count(*) from pg_constraint where conrelid = 'public.port_goods'::regclass and contype = 'f'
                                          and confrelid in ('public.goods'::regclass, 'public.ports'::regclass)) <> 2 then
    raise exception '0134 self-assert FAIL: port_goods'' foreign keys to goods and ports are not both there';
  end if;
  if to_regclass('public.ship_fittings_retired_0132') is not null then
    raise exception '0134 self-assert FAIL: ship_fittings_retired_0132 is still there';
  end if;

  select string_agg(format('%s %s ms → %s ms (−%s%%)', what, old_ms, new_ms,
                           round(100 * (1 - new_ms / greatest(old_ms, 0.1)))), '; ' order by what)
    into v_tim from timing_0134;

  raise notice '0134 self-assert ok: EVERY ARRIVAL IS ANSWERED IN TIME — nothing the sweep decides moved, it decides it faster. SAME ANSWERS (old tree vs new, one statement each): QUOTES %; PRIMITIVES %; VOYAGES %; LAP STARTS %. TIMING (old tree vs new, the same data, faster of 2 passes): %; the scan over % passage(s) at sea % ms → % ms. BODIES: world.mid_terms is THE reader of a price''s terms (server-only); mid_price composes it; quote reads it once a quote; npc_known_legs windows only the routes at its harbour; eleven SQL readers are PL/pgSQL with their query untouched; 14 bodies reverse to their pre-images, ACLs / volatility / definer unmoved; no new entry point. RETIRED: ship_fittings_retired_0132 (%) dropped in the last step (NOWAIT, % ms); held % ms from it to the end of the file.',
    (select v from proven_0134 where k = 'quotes'), (select v from proven_0134 where k = 'prims'),
    (select v from proven_0134 where k = 'voyages'), (select v from proven_0134 where k = 'laps'),
    v_tim, (select sailing from voyage_probe_0134), (select scan_old_ms from voyage_probe_0134), (select scan_new_ms from voyage_probe_0134),
    (select v from proven_0134 where k = 'retired'), (select ms from swap_0134 where what = 'last'),
    round(extract(epoch from clock_timestamp() - (select at from swap_0134 where what = 'last')) * 1000, 1);
end $$;
