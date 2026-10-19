-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0207 — A REVIEW PRICES EIGHT LOOPS, THE TRADE LOOPS FIRST  (npc_route_candidates 16 → 8, and
--        public.npc_loop_candidates offers the trade loops before the nearest out-and-backs)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ██ NOT FOR DEPLOY (2026-10-19 ~05:10 UTC). It failed its own gate in BOTH paired sims: the sweep is
-- ██ faster (avg x 0.85 / x 0.91), but laps closed at or under nothing went 46 % → 53 % and 46 % → 59 %,
-- ██ median lap net +11.5 / +13 → 0, lay-ups at the end 100 → 122 and 117 → 133.
-- ██ docs/dev-log/2026-10-19-arrivals-fast.md § 5 has the numbers. Kept on the branch as the record.
--
-- ── WHAT PROD SHOWED (read-only, 2026-10-19 01:30–01:45 UTC, head 0204;
--    docs/dev-log/2026-10-19-arrivals-fast.md)
-- * The arrivals sweep (byeharu-voyage:arrivals, every 15 s, bound avg ≤ 3 s) read 2.2–2.6 s a 5-minute
--   bucket from 00:50 to 01:15 and 3.62 / 3.68 s after 0203 + 0204 went live at 01:21.
-- * THE LOAD DID NOT MOVE. Voyages at sea 662 / 723 / 702 / 730 before, 729 / 747 after, of the same
--   length; lap starts (ROUTE_LAP) 83–100 per 10 minutes before, 120 after; the candidate scan of
--   tick_arrivals 76 ms (EXPLAIN ANALYZE, stable functions only). voyage.delay_before_day reads ~15
--   indexed rows a voyage (voyage_events_pkey) — the settle side is not what grew.
-- * THE COST PER LAP START DID. standing_routes rewritten 124 / 129 per 10 minutes before, 225 after.
--   0203 taught every harbour its remembered legs (homes knowing ≤ 1 leg 113 → 0), so a review prices
--   ~15 loops where it priced ~7 (prod-shaped harness: 267–291 ms a plan at 16 candidates).
-- * NOT THE FIGHT: 0200 alone (the fight lit, before 0203) measured 2.42 s against 2.32 s dark, and
--   raids are fewer than 30 events in the 50 minutes read.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (0) public.npc_loop_candidates, two hunks: THE TRADE LOOPS ARE OFFERED FIRST (up to
--     npc_route_trade_candidates, 6), then the nearest out-and-backs into the room left, then the three-stop
--     loops. At 16 the same set is offered in another order (self-assert A, 120 merchants); at 8 every trade
--     loop offered at 16 is still offered (self-assert B: 693 of 693 on the 0204 harness world).
-- (1) npc_route_candidates 16 → 8. A review prices her present loop and the first seven on offer.
--     BEFORE (0) — the knob alone, the out-and-backs first — it measured as follows:
--     Measured on the prod-shaped harness (prod's stocks, purses, treasuries, 837 loops and knobs at
--     01:39 UTC; 250 merchants at a lap start, each reviewed):
--       16: 291 ms a plan (p95 374), 15.1 loops priced, 194 switched, the switches gain 11.02 M d./h,
--           3 wait;
--        8: 189 ms a plan (p95 244), 8 loops priced, 174 switched, the switches gain 10.95 M d./h
--           (99.4 %), 5 wait.
--     Three-knob variants (neighbours 3, 2 or 1, trade 4 or 5) were measured and gained less for the same cost;
--     pricing the trade loops first (an npc_plan hunk) was measured in the sweep sim and bought nothing.
--     THE SWEEP, 20 minutes paired on the same world (avg / p95, the last 10 minutes): 2,186 / 4,023 ms at 16,
--     1,823 / 3,302 ms at 8 (x 0.83); prod's 3.45 s projects to ~2.9 s.
--     THE COST, the same 20 minutes: laps closed at or under nothing 41 of 125 → 73 of 142, lay-ups at the end
--     120 → 146 of 837 (a second pair: 44 of 129 → 83 of 152; 114 → 146).
--     WITH (0), 2026-10-19 04:00–05:05 UTC, a world refreshed from prod at 03:24 UTC (20 minutes each,
--     arms run side by side): sweep avg 7,237 → 6,158 ms and 7,231 → 6,545 ms; laps ≤ 0 42 / 92 (46 %) →
--     33 / 62 (53 %) and 35 / 76 (46 %) → 30 / 51 (59 %). The knob alone in the first pair: 5,779 ms, 69 / 116 (59 %).
-- (2) NOTHING ELSE. Every leg the planner writes is still judged at her laden speed after the plan's own
--     PROVISION (0203's public.npc_provision_for / voyage.stores_need_days); npc_courses and
--     npc_known_legs are untouched; npc_route_review_laps stays 6.
--
-- ── SELF-ASSERT (its own probes; every probe row rolled back) ──────────────────────────────────
-- (A)  the body: each hunk occurs once and reverses to its pre-image, the ACL and STABLE kept; at 16 the
--      first 120 merchants of the roster are offered the same loops by both bodies.
-- (B)  at 8, the same 120 lose no trade loop they are offered at 16.
-- (i)  COMPTOIR CHASTELLAIN's first merchant fleet at her lap start, on a review lap, at 8: the loop
--      written leaves her more than nothing a lap, sails (no lay-up), carries a BUY, and every leg is
--      covered after its PROVISION at a full hold.
-- (ii) THE FIRST 20 MERCHANTS OF THE ROSTER at their lap starts, on a review lap, at 8: none is written a
--      loop the door refuses after its PROVISION. The same 20 at 16 and at 8 are timed (notice only).
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- One world_config UPDATE. The probes write only their merchants' own rows inside sub-transactions that
-- are rolled back whole; a merchant whose rows a live sweep holds is skipped and counted (busy). No
-- LOCK TABLE, no set role, no set local, no begin. Timings are notices only. One function body changes
-- (public.npc_loop_candidates, STABLE, two hunks).
-- ROLLBACK: update public.world_config set value = '16'::jsonb where key = 'npc_route_candidates'; and the
-- two hunks reversed (each new text back to its old, in reverse order).
-- VERSION: 0207.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.npc_courses') is null or to_regprocedure('public.npc_provision_for(uuid,numeric)') is null then
    raise exception '0207 refuses: 0203 (the remembered legs, the provision measure) is not in this world';
  end if;
  if public.wc_int('npc_route_candidates') is distinct from 16 then
    raise exception '0207 refuses: npc_route_candidates is % — this file''s pre-image is 16', public.wc('npc_route_candidates');
  end if;
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
-- A MERCHANT AT HER LAP START, ON A REVIEW LAP (her own rows, rolled back with the rest): her fleet docked
-- at her stop 0 between laps, nothing aboard, no order, her lap count a multiple of npc_route_review_laps.
create or replace function pg_temp.at_review_0207(p_fleet uuid, p_route uuid)
returns void
language plpgsql
as $$
declare
  v_home uuid := (select s.port_id from public.standing_route_stops s where s.route_id = p_route and s.ord = 0);
begin
  update public.voyages set status = 'ABORTED' where fleet_id = p_fleet and status = 'SAILING';
  update public.orders set status = 'cancelled' where fleet_id = p_fleet and status in ('pending', 'active', 'failed');
  update public.fleets set status = 'DOCKED', port_id = v_home, lat = null, lon = null, busy_until = null where id = p_fleet;
  update public.ships set cargo = '{}'::jsonb where fleet_id = p_fleet;
  update public.standing_route_laps set closed_at = now() where route_id = p_route and closed_at is null;
  update public.standing_routes set fleet_id = p_fleet, lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null,
         lap_no = 0
   where id = p_route;
end $$;

-- THE LOOP WRITTEN, AS THE DOOR WILL JUDGE IT (0203's measure): after the plan's PROVISION (cmd.do_provision
-- DAYS her preset), every leg's course measured as cmd.do_sail measures it (voyage.segments_from_course)
-- and judged at the full hold's speed against voyage.endurance_days; and what a lap of it leaves her.
create or replace function pg_temp.loop_door_0207(p_route uuid)
returns jsonb
language plpgsql
as $$
declare
  sr      public.standing_routes%rowtype;
  v_fleet uuid;
  v_hold  numeric;
  v_crew  int;
  v_speed numeric;
  v_ports uuid[];
  v_n     int;
  v_leg   jsonb;
  v_profit numeric := 0;
  v_wages numeric := 0;
  v_nm    numeric := 0;
  v_sea_d numeric;
  v_end   numeric;
  v_prov  text := 'ok';
  v_bad   int := 0;
  v_cnm   numeric;
  s       record;
  j       int;
begin
  select * into sr from public.standing_routes where id = p_route;
  v_fleet := coalesce(sr.fleet_id, (select nf.fleet_id from public.npc_fleets nf where nf.route_id = p_route));
  select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(sh.id)), 0) into v_crew, v_hold
    from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = v_fleet;
  v_hold := v_hold + public.fleet_free_hold(v_fleet);
  v_speed := greatest(coalesce(voyage.fleet_speed_at(v_fleet, 1), 0), 0.1);
  v_ports := array(select st.port_id from public.standing_route_stops st where st.route_id = p_route order by st.ord);
  v_n := cardinality(v_ports);
  for j in 1 .. v_n loop
    v_leg := public.npc_leg_lines(p_route, v_ports[j], v_ports[j % v_n + 1], v_hold, v_crew, v_speed);
    v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
    v_wages := v_wages + coalesce((v_leg->>'wages')::numeric, 0);
    v_nm := v_nm + coalesce((v_leg->>'nm')::numeric, 0);
  end loop;
  v_sea_d := v_nm / (v_speed * 24);
  begin
    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'DAYS',
              'days', (select pr.days from public.fleets f join public.provision_presets pr on pr.id = f.provision_preset_id where f.id = v_fleet)));
  exception when others then
    v_prov := split_part(sqlerrm, ':', 1);
  end;
  v_end := voyage.endurance_days(v_fleet);
  for s in select st.course from public.standing_route_stops st where st.route_id = p_route order by st.ord loop
    select coalesce(sum((g->>'nm')::numeric), 0) into v_cnm from jsonb_array_elements(voyage.segments_from_course(s.course)) g;
    if v_end < voyage.stores_need_days(v_cnm, v_speed) then
      v_bad := v_bad + 1;
    end if;
  end loop;
  return jsonb_build_object('net', round(v_profit - public.wages_from_profit(v_wages, v_profit)
           - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d,
                                v_crew * public.wc_num('food_per_crew_day') * v_sea_d)),
         'stops', (select string_agg(p.code, '-' order by st.ord) from public.standing_route_stops st
                     join public.ports p on p.id = st.port_id where st.route_id = p_route),
         'buys', (select count(*) from public.standing_route_lines l where l.route_id = p_route and l.kind = 'BUY'),
         'reason', sr.paused_reason, 'provision', v_prov, 'legs_refused', v_bad);
end $$;

-- ONE REVIEW, ROLLED BACK: the merchant at her lap start on a review lap, npc_route_candidates at p_cand,
-- planned; what was written, judged by the door. A merchant whose rows a live sweep holds answers busy.
create or replace function pg_temp.review_0207(p_fleet uuid, p_route uuid, p_cand int)
returns jsonb
language plpgsql
as $$
declare
  v_r   jsonb;
  v_t0  timestamptz;
  v_out jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('standing_routes_enabled', 'npc_traders_enabled');
    update public.world_config set value = to_jsonb(p_cand) where key = 'npc_route_candidates';
    perform pg_temp.at_review_0207(p_fleet, p_route);
    v_t0 := clock_timestamp();
    v_r := public.npc_plan(now(), p_route);
    v_out := jsonb_build_object('ms', extract(epoch from clock_timestamp() - v_t0) * 1000,
                                'plan', v_r - 'notes', 'wrote', pg_temp.loop_door_0207(p_route));
    raise exception 'PROBE_ROLLBACK_0207:%', v_out::text;
  exception
    when lock_not_available then
      return jsonb_build_object('busy', true);
    when others then
      if sqlerrm not like 'PROBE_ROLLBACK_0207:%' then raise; end if;
      return substr(sqlerrm, length('PROBE_ROLLBACK_0207:') + 1)::jsonb;
  end;
end $$;

-- How many times p_needle occurs in p_hay.
create or replace function pg_temp.occurs_0207(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / greatest(length(p_needle), 1) $$;

-- ── 1. THE BODY: THE TRADE LOOPS ARE OFFERED FIRST (public.npc_loop_candidates, two hunks) ──────
-- The pre-image, kept as pg_temp.npc_loop_candidates_old_0207 for the probes below.
create temp table defs_before_0207 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)')) f(fn);

do $$
begin
  execute replace((select def from defs_before_0207),
                  'CREATE OR REPLACE FUNCTION public.npc_loop_candidates(',
                  'CREATE OR REPLACE FUNCTION pg_temp.npc_loop_candidates_old_0207(');
end $$;

create temporary table hunks_0207 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n)) on commit drop;
insert into hunks_0207 values
-- (1) the out-and-backs to the nearest no longer come first: only the neighbours' known legs are read here
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 1,
$h$  -- OUT AND BACK to the nearest. The way back is a known leg of the destination's.
  for b in select x from jsonb_array_elements(v_nearset) x loop
    exit when v_out >= v_max - 1;
    if not v_cache ? (b->>'port_id') then
      v_cache := v_cache || jsonb_build_object(b->>'port_id',
                   public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap));
    end if;
    select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
    continue when v_ret is null;
    stops := jsonb_build_array(v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
                              jsonb_build_object('port_id', b->'port_id', 'code', b->'code',
                                                 'course', v_ret->'course', 'nm', v_ret->'nm'));
    kind := 'near';
    v_out := v_out + 1;
    return next;
  end loop;
$h$,
$h$  -- 0207: THE TRADE LOOPS ARE OFFERED FIRST, the out-and-backs to the nearest after them (below the
  -- trade loops), the three-stop loops last. npc_plan prices the first npc_route_candidates - 1 on offer;
  -- at 16 every kind fitted, at 8 the nearest out-and-backs took five of the seven places and the trade
  -- loops (178 of 194 switches at 16 went to one) were crowded out. The neighbours' known legs are read
  -- here, first, because a trade loop through a neighbour needs them.
  for b in select x from jsonb_array_elements(v_nearset) x loop
    if not v_cache ? (b->>'port_id') then
      v_cache := v_cache || jsonb_build_object(b->>'port_id',
                   public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap));
    end if;
  end loop;
$h$),
-- (2) the out-and-backs to the nearest, after the trade loops, into the room they leave
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 2,
$h$  -- THREE STOPS among the neighbours, the shortest first, into the room that is left.
$h$,
$h$  -- OUT AND BACK to the nearest, into the room the trade loops leave (0207: after them). The way back
  -- is a known leg of the destination's.
  for b in select x from jsonb_array_elements(v_nearset) x loop
    exit when v_out >= v_max - 1;
    select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
    continue when v_ret is null;
    stops := jsonb_build_array(v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
                              jsonb_build_object('port_id', b->'port_id', 'code', b->'code',
                                                 'course', v_ret->'course', 'nm', v_ret->'nm'));
    kind := 'near';
    v_out := v_out + 1;
    return next;
  end loop;

  -- THREE STOPS among the neighbours, the shortest first, into the room that is left.
$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0207 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0207 where fn = d.fn order by n loop
      if pg_temp.occurs_0207(v_def, h.old) <> 1 then
        raise exception '0207 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.n, d.fn, pg_temp.occurs_0207(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0207 self-assert FAIL: no hunk for %', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0207 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0207(v_rev, h.new) <> 1 then
        raise exception '0207 self-assert FAIL: hunk % of % is not in the new body once', h.n, d.fn;
      end if;
    end loop;
    for h in select * from hunks_0207 where fn = d.fn order by n desc loop
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0207 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0207 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
    if (select p.provolatile from pg_proc p where p.oid = d.fn::regprocedure) <> 's' then
      raise exception '0207 self-assert FAIL: % is no longer STABLE', d.fn;
    end if;
  end loop;
end $$;

-- What a merchant is offered at her stop 0, by the body p_new or the pre-image, at the knob as it stands:
-- [{kind, stops}] in the order offered (the speed and hold npc_plan reads).
create or replace function pg_temp.offered_0207(p_fleet uuid, p_route uuid, p_new boolean)
returns jsonb
language plpgsql
as $$
declare
  v_home  uuid := (select s.port_id from public.standing_route_stops s where s.route_id = p_route and s.ord = 0);
  v_hold  numeric;
  v_speed numeric;
  v_out   jsonb;
begin
  select coalesce(sum(public.ship_cargo_tuns(s.id)), 0) into v_hold from public.ships s where s.fleet_id = p_fleet;
  v_hold  := v_hold + public.fleet_free_hold(p_fleet);
  v_speed := greatest(coalesce(voyage.fleet_speed_at(p_fleet, 1), 0), 0.1);
  if p_new then
    select coalesce(jsonb_agg(jsonb_build_object('kind', c.kind, 'stops', c.stops)), '[]'::jsonb) into v_out
      from public.npc_loop_candidates(p_route, p_fleet, v_home, v_hold, v_speed) c;
  else
    select coalesce(jsonb_agg(jsonb_build_object('kind', c.kind, 'stops', c.stops)), '[]'::jsonb) into v_out
      from pg_temp.npc_loop_candidates_old_0207(p_route, p_fleet, v_home, v_hold, v_speed) c;
  end if;
  return v_out;
end $$;

-- (A) AT 16, THE SAME LOOPS ARE OFFERED, ONLY IN ANOTHER ORDER: for the first 120 merchants of the roster
-- the new body and the pre-image offer the same set of loops (kind and stops).
do $$
declare
  v_f    record;
  v_n    int := 0;
  v_bad  int := 0;
  v_badl jsonb := '[]'::jsonb;
  v_o    jsonb;
  v_x    jsonb;
begin
  if public.wc_int('npc_route_candidates') is distinct from 16 then
    raise exception '0207 self-assert FAIL: the knob moved before the body was compared at 16';
  end if;
  for v_f in select nf.fleet_id, nf.route_id from public.npc_fleets nf order by nf.roster_ord limit 120 loop
    v_o := pg_temp.offered_0207(v_f.fleet_id, v_f.route_id, false);
    v_x := pg_temp.offered_0207(v_f.fleet_id, v_f.route_id, true);
    v_n := v_n + 1;
    if (select coalesce(jsonb_agg(e order by e::text), '[]'::jsonb) from jsonb_array_elements(v_o) e)
       is distinct from (select coalesce(jsonb_agg(e order by e::text), '[]'::jsonb) from jsonb_array_elements(v_x) e) then
      v_bad := v_bad + 1;
      if jsonb_array_length(v_badl) < 3 then v_badl := v_badl || jsonb_build_array(jsonb_build_object('old', v_o, 'new', v_x)); end if;
    end if;
  end loop;
  if v_n > 0 and v_bad <> 0 then
    raise exception '0207 self-assert FAIL: at 16, % of % merchants are offered another set of loops by the new body: %', v_bad, v_n, v_badl;
  end if;
  raise notice '0207 self-assert (A): at 16, % merchants offered the same loops by both bodies', v_n;
end $$;

-- ── 2. THE KNOB ────────────────────────────────────────────────────────────────────────────────
update public.world_config set value = '8'::jsonb,
       description = 'The loops a merchant''s review prices at her lap start, her present loop included (public.npc_plan '
                     || 'over public.npc_loop_candidates, which offers the trade loops first, then the nearest out-and-backs, '
                     || 'then the three-stop loops). 0207: 16 → 8 — 0203''s remembered legs offer ~15 where ~7 were '
                     || 'offered, and the arrivals sweep paid for it (prod 3.6 s against 2.3 s); at 8 a review prices her '
                     || 'trade loops and one out-and-back (docs/dev-log/2026-10-19-arrivals-fast.md).'
 where key = 'npc_route_candidates';

-- (B) AT 8, THE TRADE LOOPS ARE NOT CROWDED OUT: for the same 120 merchants, every trade loop the new body
-- offers at 8 is one it offers at 16, and as many are offered (npc_route_trade_candidates < 7 fit whole).
do $$
declare
  v_f    record;
  v_n    int := 0;
  v_bad  int := 0;
  v_t8   int := 0;
  v_t16  int := 0;
  v_badl jsonb := '[]'::jsonb;
  v_x    jsonb;
  v_o    jsonb;
begin
  if public.wc_int('npc_route_candidates') is distinct from 8 then
    raise exception '0207 self-assert FAIL: npc_route_candidates is %, not 8', public.wc('npc_route_candidates');
  end if;
  for v_f in select nf.fleet_id, nf.route_id from public.npc_fleets nf order by nf.roster_ord limit 120 loop
    v_x := pg_temp.offered_0207(v_f.fleet_id, v_f.route_id, true);
    begin
      update public.world_config set value = to_jsonb(16) where key = 'npc_route_candidates';
      v_o := pg_temp.offered_0207(v_f.fleet_id, v_f.route_id, true);
      raise exception 'PROBE_ROLLBACK_0207:%', v_o::text;
    exception when others then
      if sqlerrm not like 'PROBE_ROLLBACK_0207:%' then raise; end if;
      v_o := substr(sqlerrm, length('PROBE_ROLLBACK_0207:') + 1)::jsonb;
    end;
    v_n := v_n + 1;
    v_t8  := v_t8 + (select count(*) from jsonb_array_elements(v_x) e where e->>'kind' = 'trade');
    v_t16 := v_t16 + (select count(*) from jsonb_array_elements(v_o) e where e->>'kind' = 'trade');
    if (select coalesce(jsonb_agg(e order by e::text), '[]'::jsonb) from jsonb_array_elements(v_x) e where e->>'kind' = 'trade')
       is distinct from (select coalesce(jsonb_agg(e order by e::text), '[]'::jsonb) from jsonb_array_elements(v_o) e where e->>'kind' = 'trade')
       or jsonb_array_length(v_x) > 7 then
      v_bad := v_bad + 1;
      if jsonb_array_length(v_badl) < 3 then v_badl := v_badl || jsonb_build_array(jsonb_build_object('at8', v_x, 'at16', v_o)); end if;
    end if;
  end loop;
  if public.wc_int('npc_route_candidates') is distinct from 8 then
    raise exception '0207 self-assert FAIL: the probe did not roll the knob back to 8';
  end if;
  if v_bad <> 0 then
    raise exception '0207 self-assert FAIL: at 8, % of % merchants lost a trade loop they are offered at 16 (or were offered more than 7): %', v_bad, v_n, v_badl;
  end if;
  raise notice '0207 self-assert (B): at 8, % merchants offered % trade loops (at 16: %)', v_n, v_t8, v_t16;
end $$;

-- ── 2. SELF-ASSERT (its own probes, rolled back; the world's rows are reported only) ───────────
do $$
declare
  v_c     jsonb;
  v_f     record;
  v_try   int;
  v_x     jsonb;
  v_n     int := 0;
  v_busy  int := 0;
  v_bad   int := 0;
  v_laid  int := 0;
  v_ms16  numeric := 0;
  v_ms8   numeric := 0;
  v_m16   numeric;
  v_badl  jsonb := '[]'::jsonb;
begin
  if public.wc_int('npc_route_candidates') is distinct from 8 then
    raise exception '0207 self-assert FAIL: npc_route_candidates is %, not 8', public.wc('npc_route_candidates');
  end if;

  -- (i) the owner's case
  select nf.fleet_id, nf.route_id, f.name into v_f
    from public.npc_fleets nf join public.players pl on pl.id = nf.player_id and pl.company_name = 'Comptoir Chastellain'
    join public.fleets f on f.id = nf.fleet_id
   order by nf.roster_ord limit 1;
  if v_f.fleet_id is null then
    raise exception '0207 self-assert FAIL: the roster holds no Comptoir Chastellain — the probe is named for her';
  end if;
  for v_try in 1 .. 5 loop
    v_c := pg_temp.review_0207(v_f.fleet_id, v_f.route_id, 8);
    exit when not coalesce((v_c->>'busy')::boolean, false);
    perform pg_sleep(1);
  end loop;
  if coalesce((v_c->>'busy')::boolean, false) then
    raise exception '0207 self-assert FAIL: LOCK CONTENTION, not a result — Comptoir Chastellain''s rows were held by a live sweep 5 times. Re-run the push.';
  end if;
  if not ((v_c->'wrote'->>'net')::numeric > 0 and v_c->'wrote'->>'reason' is null
          and (v_c->'wrote'->>'legs_refused')::int = 0 and (v_c->'wrote'->>'buys')::int > 0) then
    raise exception '0207 self-assert FAIL: Comptoir Chastellain (%) was written % — net % a lap, % leg(s) refused, % BUY, %: %',
      v_f.name, v_c->'wrote'->>'stops', v_c->'wrote'->>'net', v_c->'wrote'->>'legs_refused', v_c->'wrote'->>'buys',
      coalesce(v_c->'wrote'->>'reason', 'sailing'), v_c;
  end if;

  -- (ii) the first 20 of the roster, at 16 (timed) and at 8 (timed and judged)
  for v_f in select nf.fleet_id, nf.route_id from public.npc_fleets nf order by nf.roster_ord limit 20 loop
    v_x := pg_temp.review_0207(v_f.fleet_id, v_f.route_id, 16);
    if coalesce((v_x->>'busy')::boolean, false) then v_busy := v_busy + 1; continue; end if;
    v_m16 := (v_x->>'ms')::numeric;
    v_x := pg_temp.review_0207(v_f.fleet_id, v_f.route_id, 8);
    if coalesce((v_x->>'busy')::boolean, false) then v_busy := v_busy + 1; continue; end if;
    v_ms16 := v_ms16 + v_m16;
    v_ms8 := v_ms8 + (v_x->>'ms')::numeric;
    v_n := v_n + 1;
    if (v_x->'wrote'->>'legs_refused')::int > 0 then
      v_bad := v_bad + 1;
      v_badl := v_badl || jsonb_build_array(v_x->'wrote');
    end if;
    if v_x->'wrote'->>'reason' = 'laid_up' then v_laid := v_laid + 1; end if;
  end loop;
  if v_n < 10 then
    raise exception '0207 self-assert FAIL: LOCK CONTENTION, not a result — only % of 20 roster merchants could be probed (% busy). Re-run the push.', v_n, v_busy;
  end if;
  if v_bad <> 0 then
    raise exception '0207 self-assert FAIL: at 8, % of % merchants were written a loop the door refuses after its PROVISION: %', v_bad, v_n, v_badl;
  end if;
  if public.wc_int('npc_route_candidates') is distinct from 8 then
    raise exception '0207 self-assert FAIL: the probes did not roll the knob back';
  end if;

  raise notice '0207 self-assert ok: A REVIEW PRICES EIGHT LOOPS — npc_route_candidates 8. COMPTOIR CHASTELLAIN (%; review lap): % — net % a lap, % BUY, 0 legs refused after PROVISION, sailing. THE ROSTER''S FIRST %: 0 written a loop the door refuses, % laid up; % ms a plan at 16 → % ms at 8 (% busy, skipped).',
    (select f.name from public.npc_fleets nf join public.players pl on pl.id = nf.player_id and pl.company_name = 'Comptoir Chastellain'
       join public.fleets f on f.id = nf.fleet_id order by nf.roster_ord limit 1),
    v_c->'wrote'->>'stops', v_c->'wrote'->>'net', v_c->'wrote'->>'buys',
    v_n, v_laid, round(v_ms16 / v_n), round(v_ms8 / v_n), v_busy;
end $$;
