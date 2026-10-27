-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0250 — A BEAT READS EACH HULL ONCE  (the arrivals beat: the same answers for less work)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, MEASURED (prod, read-only, 2026-10-27, head 0248) ───────────────────────────────
-- After 0248 the arrivals beat runs every second in one warm session (public.arrivals_beats):
--   30 min to 12:32 UTC: 1,635 beats, p50 0.39 s, p95 1.82 s, max 11.7 s, 0 failed.
-- What a beat costs follows what it does. Fitted over 1,494 beats (second 6-59 of each minute), a beat
-- costs ~32 ms a sea-day and ~214 ms a DEPARTURE (an arrival whose route sails on: the lap closes and
-- opens, the stop's lines are planned, the sells, buys, supplies and the sail run).
--   beats with no departure: p95 0.62 s;  beats with a departure: p95 2.06 s.
-- So the departure path makes the p95, and the first 5 s of a minute (cold) make little of it
-- (p95 2.16 s cold, 1.81 s warm). Sampling the beat's backend (pg_stat_activity, 30 samples): 15
-- asleep between beats, 11 on CPU, 3 reading data files. Mostly CPU, some disk.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- (1) CPU. The same readers are asked the same question again and again inside one statement:
--   * public.crew_pct computes ALL of public.crew_terms (a 12-table join, a function call per row) for
--     every question, then keeps one effect. Most questions are about an effect no seated captain of the
--     fleet bears ('hold', 'supplies', 'category_spread' on most fleets; every effect on the 339
--     fleets with no captain seated), and the answer is 0.
--   * voyage.ship_speed_at reads world.ship_stats TWICE (hold, then speed) — every hull it weighs.
--   * public.supply_needs, public.supply_reach, public.npc_provision_for and public.fleet_load read
--     public.ship_hold_capacity (→ world.ship_stats + crew_pct) TWICE for every hull.
--   * voyage.ship_speed_at and public.ship_cargo_tuns weigh a hold by joining every good (prod: goods
--     read whole ~35 times a second); public.house_skill_scopes reads every skill and every skill effect
--     to find the few a house holds (prod: skills / skill_effects read whole ~30-45 times a second).
-- (2) DISK. standing_route_laps is 162,580 rows, 215 MB (200 laps kept a route). A lap that closes and
--     the next that opens read EVERY lap of the route from the heap (plain EXPLAIN on prod):
--     max(started_at) — an index scan of all ~195 laps; max(closed_at) — the closed_at index walked
--     backward through other routes' laps; the old orders' delete — all ~195 laps by id; the old
--     trades' fade — all ~195 laps to find the few with trades. ~600 random heap pages a lap, mostly
--     not in shared_buffers (256 MB for a 2.2 GB database).
-- Local (PGlite, head 0248 + prod's switches, 835 merchants at sea, the same 120 seconds of the clock
-- in one session, old bodies vs these, interleaved): crew_terms skipped → −15 %; all of (1) → −19 to
-- −25 % a beat. (PGlite holds no 215 MB laps table; (2) is measured on prod after.)
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- Eleven hunks in eight bodies, each the same STABLE question answered from the same snapshot:
--   (a) public.crew_pct: crew_terms is computed only when a captain seated in the fleet (on p_ship, for
--       a ship effect) has an active trait or a job that bears p_effect — crew_terms' own joins, both
--       arms (crew_bite lit: captain_active; dark: captain_job); with none, every term crew_terms could
--       return for p_effect is absent, so the sum is 0, exactly as before.
--   (b) voyage.ship_speed_at: world.ship_stats once, read for hold and for speed, with world.ship_stat's
--       own refusal (E_NO_SUCH_STAT) when either is missing; each good's bulk looked up by its key.
--   (c) public.ship_cargo_tuns: each good's bulk looked up by its key (an unknown key weighs nothing,
--       as the inner join dropped it).
--   (d) public.house_skill_scopes: driven from the house's own skills (the same set, array_agg DISTINCT).
--   (e) public.supply_needs, supply_reach, npc_provision_for, fleet_load: ship_hold_capacity once a hull
--       (a LATERAL with OFFSET 0, so it is not pulled back up and called twice).
-- Three indexes on standing_route_laps, read by those four queries (and the Stats / route cards):
--   (route_id, started_at) INCLUDE (id); (route_id, closed_at) WHERE closed_at IS NOT NULL;
--   (route_id, lap_no) WHERE trades IS NOT NULL.
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Change a rule, a knob, a flag, a grant, a client read, the arrivals job or its schedule. Cache
-- anything across statements: every answer is still read when it is asked. The arrivals loop stays one
-- minute: pg_cron's CALL runs under the server's 120 s statement_timeout (a COMMIT inside does not reset
-- it), and a two-minute loop would either lose its last seconds or be cancelled; the cold seconds are
-- not what makes the p95 (above).
--
-- ── THE PROOF (the self-assert) ─────────────────────────────────────────────────────────────────
-- The old bodies are kept as pg_temp copies. Old and new answer the same questions on this database:
-- crew_pct for every effect on seated and unseated fleets (each hull for a ship effect; a good for
-- category_spread; refusals compared as refusals), ship_speed_at at four fills, ship_cargo_tuns,
-- house_skill_scopes for every house and every hull, supply_needs at six distances, supply_reach,
-- npc_provision_for, and fleet_load in a rolled-back probe (what went aboard, every hull's cargo and
-- basis). Then all of it again on a rolled-back probe where the hulls carry cargo (a real good, a second
-- one, and a key that is no good) and the seated captains have taken up every trait they hold (and a
-- few they do not). Every answer must be identical.
-- Local, end to end (scratch harness, not in this file): 60 beats of the clock from three starting
-- points, old bodies and new from the same state in one transaction — 855 / 1,070 / 1,035 fleets,
-- 841 / 1,745 / 2,835 sea-days, 507 / 703 arrivals, 441 / 672 departures, 344 / 515 sells — every row
-- of all 128 public tables identical (uuids blanked, clock columns dropped; the same run against itself
-- is the control).
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reversing the hunks below (every OLD text is here verbatim, and the self-assert
-- proves the live bodies reverse to their pre-images by them); the indexes can be dropped or left.
--
-- SUPERSEDES: the eight bodies named above, sliced from the LIVE bodies (LF-normalised; prod md5 equal
-- to the chain's at head 0248). VERSION: 0250 (after 0249).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.crew_terms(uuid,timestamptz)') is null
     or to_regprocedure('public.crew_pct(uuid,uuid,text,uuid,timestamptz)') is null
     or to_regprocedure('public.supply_needs(uuid,numeric[])') is null
     or to_regclass('public.standing_route_laps') is null then
    raise exception '0250 refuses: 0157 / 0161 / 0203 is not in this world';
  end if;
  if to_regclass('public.standing_route_laps_route_started') is not null then
    raise exception '0250 refuses: standing_route_laps_route_started already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0250(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGE (LF-normalised) ────────────────────────────────────────────────────────────
create temp table defs_before_0250 on commit drop as
select f.fn, f.name, f.old_name,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values
    ('public.crew_pct(uuid,uuid,text,uuid,timestamp with time zone)', 'public.crew_pct', 'pg_temp.crew_pct_old_0250'),
    ('voyage.ship_speed_at(uuid,numeric)',                            'voyage.ship_speed_at', 'pg_temp.ship_speed_at_old_0250'),
    ('public.ship_cargo_tuns(uuid)',                                  'public.ship_cargo_tuns', 'pg_temp.ship_cargo_tuns_old_0250'),
    ('public.house_skill_scopes(uuid,uuid)',                          'public.house_skill_scopes', 'pg_temp.house_skill_scopes_old_0250'),
    ('public.supply_needs(uuid,numeric[])',                           'public.supply_needs', 'pg_temp.supply_needs_old_0250'),
    ('public.supply_reach(uuid)',                                     'public.supply_reach', 'pg_temp.supply_reach_old_0250'),
    ('public.npc_provision_for(uuid,numeric)',                        'public.npc_provision_for', 'pg_temp.npc_provision_for_old_0250'),
    ('public.fleet_load(uuid,text,numeric,numeric)',                  'public.fleet_load', 'pg_temp.fleet_load_old_0250')
  ) f(fn, name, old_name);

create temp table before_0250 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- the old bodies, kept for the self-assert's comparison
do $$
declare
  d record;
begin
  for d in select * from defs_before_0250 loop
    if pg_temp.occurs_0250(d.def, 'FUNCTION ' || d.name || '(') <> 1 then
      raise exception '0250 self-assert FAIL: %''s definition does not name itself once', d.fn;
    end if;
    execute replace(d.def, 'FUNCTION ' || d.name || '(', 'FUNCTION ' || d.old_name || '(');
  end loop;
end $$;

-- ── 1. THE RE-CUT ───────────────────────────────────────────────────────────────────────────────
create temp table hunks_0250 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0250 (fn, n, old, new) values
('public.crew_pct(uuid,uuid,text,uuid,timestamp with time zone)', 1,
$h$  select coalesce(sum(t.value_pct), 0) into v_sum from public.crew_terms(p_fleet, p_at) t
   where t.effect = p_effect
     and (v_scope = 'fleet' or t.ship_id = p_ship)   -- 0168: a ship effect counts her own captains only
     and (p_effect <> 'category_spread'
          or exists (select 1 from public.traits tr join public.goods g on g.category = tr.goods
                      where tr.code = t.trait and g.id = p_good));$h$,
$h$  -- 0250: a term of p_effect exists only for a captain seated in this fleet (on p_ship, for a ship effect)
  -- whose active trait or job bears it (public.crew_terms' own joins, both arms): with none, the sum is 0
  -- and crew_terms is not computed.
  if exists (select 1 from public.ships s
               join public.captain_seats cs on cs.ship_id = s.id
               join public.player_officers po on po.id = cs.player_officer_id
              where s.fleet_id = p_fleet and (v_scope = 'fleet' or cs.ship_id = p_ship)
                and (exists (select 1 from public.captain_active ca
                               join public.trait_effects te on te.trait = ca.trait and te.effect = p_effect
                              where ca.player_officer_id = po.id)
                     or exists (select 1 from public.captain_job j
                                  join public.trait_effects te on te.trait = j.job and te.effect = p_effect
                                 where j.officer_id = po.officer_id))) then
  select coalesce(sum(t.value_pct), 0) into v_sum from public.crew_terms(p_fleet, p_at) t
   where t.effect = p_effect
     and (v_scope = 'fleet' or t.ship_id = p_ship)   -- 0168: a ship effect counts her own captains only
     and (p_effect <> 'category_spread'
          or exists (select 1 from public.traits tr join public.goods g on g.category = tr.goods
                      where tr.code = t.trait and g.id = p_good));
  else
    v_sum := 0;
  end if;$h$),
('voyage.ship_speed_at(uuid,numeric)', 1,
$h$  v_cargo_t numeric;
begin$h$,
$h$  v_cargo_t numeric;
  v_stats   jsonb;     -- 0250: world.ship_stats read once (it was read twice: hold, then speed)
begin$h$),
('voyage.ship_speed_at(uuid,numeric)', 2,
$h$  select coalesce(sum((e.value)::text::numeric * g.bulk), 0) into v_cargo_t
    from jsonb_each(s.cargo) e join public.goods g on g.code = e.key;$h$,
$h$  -- 0250: each good's bulk by its key (was a join that read every good to weigh a few)
  select coalesce(sum((select (e.value)::text::numeric * g.bulk from public.goods g where g.code = e.key)), 0) into v_cargo_t
    from jsonb_each(s.cargo) e;$h$),
('voyage.ship_speed_at(uuid,numeric)', 3,
$h$  v_fill := case when p_fill is null then least(1.0, (v_cargo_t + s.water_t + s.food_t) / world.ship_stat(p_ship, 'hold'))$h$,
$h$  if p_fill is null then
    v_stats := world.ship_stats(p_ship);
    if (v_stats ->> 'hold') is null then
      raise exception 'E_NO_SUCH_STAT: no ship % has a stat called "%"', p_ship, 'hold' using errcode = 'P0001';
    end if;
  end if;
  v_fill := case when p_fill is null then least(1.0, (v_cargo_t + s.water_t + s.food_t) / (v_stats ->> 'hold')::numeric)$h$),
('voyage.ship_speed_at(uuid,numeric)', 4,
$h$  return round(world.ship_stat(p_ship, 'speed') * v_hull * v_load * v_crew * public.wc_num('wind_mult_v0'), 4);$h$,
$h$  if v_stats is null then
    v_stats := world.ship_stats(p_ship);
  end if;
  if (v_stats ->> 'speed') is null then
    raise exception 'E_NO_SUCH_STAT: no ship % has a stat called "%"', p_ship, 'speed' using errcode = 'P0001';
  end if;
  return round((v_stats ->> 'speed')::numeric * v_hull * v_load * v_crew * public.wc_num('wind_mult_v0'), 4);$h$),
('public.house_skill_scopes(uuid,uuid)', 1,
$h$    (select array_agg(distinct e.scope)
       from public.skill_effects e
      where e.scope <> 'company'
        and e.skill_code in (select sk.code
                               from public.skills sk
                              where sk.id in (select ps.skill_id from public.player_skills ps
                                               where ps.player_id = v_player
                                              union all
                                              select q.skill_id from public.skill_queue q
                                               where q.player_id = v_player and q.finishes_at <= now()))),$h$,
$h$    (select array_agg(distinct e.scope)   -- 0250: driven from her own skills (was: every skill, every effect)
       from (select ps.skill_id from public.player_skills ps
              where ps.player_id = v_player
             union all
             select q.skill_id from public.skill_queue q
              where q.player_id = v_player and q.finishes_at <= now()) h
       join public.skills sk on sk.id = h.skill_id
       join public.skill_effects e on e.skill_code = sk.code
      where e.scope <> 'company'),$h$),
('public.supply_needs(uuid,numeric[])', 1,
$h$           'room', public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id),
           'full', public.ship_hold_capacity(s.id) * s.store_ratio)), '[]'::jsonb)
    into v_hulls
    from public.ships s where s.fleet_id = p_fleet;$h$,
$h$           'room', hc.cap - public.ship_cargo_tuns(s.id),
           'full', hc.cap * s.store_ratio)), '[]'::jsonb)
    into v_hulls
    from public.ships s
   cross join lateral (select public.ship_hold_capacity(s.id) as cap offset 0) hc   -- 0250: read once a hull (was twice)
   where s.fleet_id = p_fleet;$h$),
('public.ship_cargo_tuns(uuid)', 1,
$h$  select coalesce(sum((e.value)::text::numeric * g.bulk), 0)
    from public.ships s
   cross join lateral jsonb_each(s.cargo) e
    join public.goods g on g.code = e.key
   where s.id = p_ship$h$,
$h$  select coalesce(sum((select (e.value)::text::numeric * g.bulk from public.goods g where g.code = e.key)), 0)   -- 0250: by key
    from public.ships s
   cross join lateral jsonb_each(s.cargo) e
   where s.id = p_ship$h$),
('public.fleet_load(uuid,text,numeric,numeric)', 1,
$h$                  public.ship_hold_capacity(s.id) as cap,
                  public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id)
                    - s.water_t - s.food_t as free
             from public.ships s
            where$h$,
$h$                  hc.cap,
                  hc.cap - public.ship_cargo_tuns(s.id)
                    - s.water_t - s.food_t as free
             from public.ships s
            cross join lateral (select public.ship_hold_capacity(s.id) as cap offset 0) hc   -- 0250: read once a hull
            where$h$),
('public.npc_provision_for(uuid,numeric)', 1,
$h$    from public.ships s
   cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t, public.ship_hold_capacity(s.id),
                                          p_days, public.ship_hold_capacity(s.id) * s.store_ratio) t$h$,
$h$    from public.ships s
   cross join lateral (select public.ship_hold_capacity(s.id) as cap offset 0) hc   -- 0250: read once a hull
   cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t, hc.cap,
                                          p_days, hc.cap * s.store_ratio) t$h$),
('public.supply_reach(uuid)', 1,
$h$            from public.ships s
           cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t,
                                                  public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id),
                                                  1000000, public.ship_hold_capacity(s.id) * s.store_ratio) t$h$,
$h$            from public.ships s
           cross join lateral (select public.ship_hold_capacity(s.id) as cap offset 0) hc   -- 0250: read once a hull
           cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t,
                                                  hc.cap - public.ship_cargo_tuns(s.id),
                                                  1000000, hc.cap * s.store_ratio) t$h$);

create or replace function pg_temp.recut_0250(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0250 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0250 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0250(v_def, h.old);
    if v_n <> 1 then
      raise exception '0250 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0250(fn) from defs_before_0250 order by fn;

-- ── 2. THE LAPS, BY ROUTE ───────────────────────────────────────────────────────────────────────
-- max(started_at) of a route (cmd.run_standing_route's pace) and the route's lap ids (the old orders'
-- delete in cmd.standing_route_close_lap) from the index alone;
create index standing_route_laps_route_started on public.standing_route_laps (route_id, started_at) include (id);
-- max(closed_at) of a route (the merchant's rest), and a route's laps closed in a window (route_earnings,
-- world.fleet_trades);
create index standing_route_laps_route_closed on public.standing_route_laps (route_id, closed_at)
  where closed_at is not null;
-- the few laps of a route that still carry trades (the fade in standing_route_close_lap).
create index standing_route_laps_route_traded on public.standing_route_laps (route_id, lap_no)
  where trades is not null;

-- ── 3. THE PROBE: old and new answer the same questions ─────────────────────────────────────────
-- p_cargo: the probe hulls are first given cargo (a real good, a second, and a key that is no good) and
-- their seated captains every trait they have (and a few they do not) taken up, inside this block, which
-- is rolled back with everything fleet_load wrote. p_dark: crew_terms' other arm — crew_bite turned the
-- other way and the probe captains' traits put down inside the block (rolled back with it), so only a
-- job bears an effect; only the crew questions asked.
create or replace function pg_temp.probe_0250(p_cargo boolean, p_dark boolean default false)
returns jsonb
language plpgsql
as $$
declare
  v_fleets  uuid[];
  v_ships   uuid[];
  v_good    record;
  v_good2   record;
  v_cgood   uuid;
  v_g       uuid;
  f         uuid;
  s         uuid;
  e         record;
  v_fill    numeric;
  v_days    numeric;
  v_qty     numeric;
  v_a       text;
  v_b       text;
  v_n       int := 0;
  v_bad     jsonb := '[]'::jsonb;
  v_nonzero int := 0;   -- crew_pct answers above 0 (a bearer seated)
  v_skipped int := 0;   -- seated fleets asked about an effect none of their captains bears (the new skip)
  v_refused int := 0;   -- answers that are refusals, on both sides
  v_loaded  numeric := 0;
  v_carry   int := 0;
  v_traits  int := 0;
  v_res     jsonb;
begin
  begin
    -- up to 40 fleets with a captain seated and 15 with none, with ships; in id order
    v_fleets := array(
      (select f0.id from public.fleets f0
        where exists (select 1 from public.ships s0 join public.captain_seats cs on cs.ship_id = s0.id where s0.fleet_id = f0.id)
        order by f0.id limit 40)
      union all
      (select f0.id from public.fleets f0
        where exists (select 1 from public.ships s0 where s0.fleet_id = f0.id)
          and not exists (select 1 from public.ships s0 join public.captain_seats cs on cs.ship_id = s0.id where s0.fleet_id = f0.id)
        order by f0.id limit 15));
    v_ships := array(select s0.id from public.ships s0 where s0.fleet_id = any(v_fleets) order by s0.id);
    select g.id, g.code into v_good from public.goods g where g.bulk > 0 order by g.code limit 1;
    select g.id, g.code into v_good2 from public.goods g where g.bulk > 0 and g.code <> v_good.code order by g.bulk desc, g.code limit 1;
    select g.id into v_cgood from public.goods g join public.traits tr on tr.goods = g.category order by g.code limit 1;

    if p_cargo then
      update public.ships sh
         set cargo = jsonb_build_object(v_good.code, 12.5, v_good2.code, 3, 'no-such-good-0250', 4)
       where sh.id = any(v_ships);
      get diagnostics v_carry = row_count;
      -- and every seated captain of the probe fleets takes up all her traits (not only her job), and the
      -- first few one more she does not have (a trait crew_terms joins to nothing): both arms of the skip
      insert into public.captain_active (player_officer_id, trait)
      select cs.player_officer_id, ct.trait
        from public.ships s0 join public.captain_seats cs on cs.ship_id = s0.id
        join public.player_officers po on po.id = cs.player_officer_id
        join public.captain_traits ct on ct.officer_id = po.officer_id
       where s0.fleet_id = any(v_fleets)
      on conflict do nothing;
      get diagnostics v_traits = row_count;
      insert into public.captain_active (player_officer_id, trait)
      select x.player_officer_id, tr.code
        from (select cs.player_officer_id, po.officer_id from public.ships s0 join public.captain_seats cs on cs.ship_id = s0.id
                join public.player_officers po on po.id = cs.player_officer_id
               where s0.fleet_id = any(v_fleets) order by cs.player_officer_id limit 5) x
        join public.traits tr on tr.code in ('NAVIGATOR', 'QUARTERMASTER', 'GUNNER', 'PROVISIONER')
       where not exists (select 1 from public.captain_traits ct where ct.officer_id = x.officer_id and ct.trait = tr.code)
      on conflict do nothing;
    end if;

    if p_dark then
      update public.world_config set value = to_jsonb(not public.crew_bite_on()) where key = 'crew_bite';
      -- and no captain of the probe fleets has a trait taken up, so only her job can bear an effect
      delete from public.captain_active ca
       using public.ships s0 join public.captain_seats cs on cs.ship_id = s0.id
       where s0.fleet_id = any(v_fleets) and ca.player_officer_id = cs.player_officer_id;
      get diagnostics v_traits = row_count;
    end if;

    -- (a) crew_pct: every effect, every probe fleet; a ship effect for each of her hulls; category_spread with a good
    foreach f in array v_fleets loop
      for e in select ce.code, ce.scope from public.crew_effects ce order by ce.code loop
        for s in select x.id from (select null::uuid as id union all
                                   select s0.id from public.ships s0 where s0.fleet_id = f and e.scope <> 'fleet') x loop
          foreach v_g in array (case when e.code = 'category_spread' then array[null::uuid, v_cgood] else array[null::uuid] end) loop
            begin v_a := pg_temp.crew_pct_old_0250(f, s, e.code, v_g)::text; exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
            begin v_b := public.crew_pct(f, s, e.code, v_g)::text;            exception when others then v_b := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
            v_n := v_n + 1;
            if v_a is distinct from v_b then
              v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'crew_pct', 'fleet', f, 'ship', s, 'effect', e.code, 'good', v_g, 'old', v_a, 'new', v_b));
            elsif v_b like 'ERR %' then v_refused := v_refused + 1;
            elsif v_b::numeric > 0 then v_nonzero := v_nonzero + 1;
            elsif exists (select 1 from public.ships s0 join public.captain_seats cs on cs.ship_id = s0.id
                           where s0.fleet_id = f and (e.scope = 'fleet' or cs.ship_id = s))
                  and not exists (select 1 from public.ships s0
                                    join public.captain_seats cs on cs.ship_id = s0.id
                                    join public.player_officers po on po.id = cs.player_officer_id
                                    join public.trait_effects te on te.effect = e.code
                                     and te.trait in (select ca.trait from public.captain_active ca where ca.player_officer_id = po.id
                                                      union all select j.job from public.captain_job j where j.officer_id = po.officer_id)
                                   where s0.fleet_id = f and (e.scope = 'fleet' or cs.ship_id = s)) then
              v_skipped := v_skipped + 1;
            end if;
          end loop;
        end loop;
      end loop;
    end loop;
    select g.id into v_cgood from public.goods g join public.traits tr on tr.goods = g.category order by g.code limit 1;

    if p_dark then
      raise exception using errcode = 'ZY250', message = jsonb_build_object('asked', v_n, 'fleets', cardinality(v_fleets),
        'nonzero', v_nonzero, 'skipped', v_skipped, 'bite', public.crew_bite_on(), 'traits', v_traits, 'bad', jsonb_array_length(v_bad), 'first_bad', v_bad -> 0)::text;
    end if;

    -- (b)(c) ship_speed_at at four fills, ship_cargo_tuns; (d) house_skill_scopes by hull
    foreach s in array v_ships loop
      foreach v_fill in array array[null, 0, 0.37, 1]::numeric[] loop
        begin v_a := pg_temp.ship_speed_at_old_0250(s, v_fill)::text; exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
        begin v_b := voyage.ship_speed_at(s, v_fill)::text;            exception when others then v_b := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
        v_n := v_n + 1;
        if v_a is distinct from v_b then
          v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'ship_speed_at', 'ship', s, 'fill', v_fill, 'old', v_a, 'new', v_b));
        end if;
      end loop;
      v_a := pg_temp.ship_cargo_tuns_old_0250(s)::text;
      v_b := public.ship_cargo_tuns(s)::text;
      v_n := v_n + 1;
      if v_a is distinct from v_b then
        v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'ship_cargo_tuns', 'ship', s, 'old', v_a, 'new', v_b));
      end if;
    end loop;
    for s in select s0.id from public.ships s0 order by s0.id loop
      v_a := pg_temp.house_skill_scopes_old_0250(null, s)::text;
      v_b := public.house_skill_scopes(null, s)::text;
      v_n := v_n + 1;
      if v_a is distinct from v_b then
        v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'house_skill_scopes', 'ship', s, 'old', v_a, 'new', v_b));
      end if;
    end loop;
    -- (d) house_skill_scopes by house (every house, and none)
    for f in select p.id from public.players p union all select null::uuid order by 1 loop
      v_a := pg_temp.house_skill_scopes_old_0250(f, null)::text;
      v_b := public.house_skill_scopes(f, null)::text;
      v_n := v_n + 1;
      if v_a is distinct from v_b then
        v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'house_skill_scopes', 'house', f, 'old', v_a, 'new', v_b));
      end if;
    end loop;

    -- (e) supply_needs at six distances, supply_reach, npc_provision_for at two lengths
    foreach f in array v_fleets loop
      begin
        select jsonb_agg(to_jsonb(n) order by n.nm nulls first)::text into v_a from pg_temp.supply_needs_old_0250(f, array[0, 250, 1500, 6000, 60000, null]::numeric[]) n;
      exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
      begin
        select jsonb_agg(to_jsonb(n) order by n.nm nulls first)::text into v_b from public.supply_needs(f, array[0, 250, 1500, 6000, 60000, null]::numeric[]) n;
      exception when others then v_b := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
      v_n := v_n + 1;
      if v_a is distinct from v_b then
        v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'supply_needs', 'fleet', f, 'old', v_a, 'new', v_b));
      end if;
      begin v_a := pg_temp.supply_reach_old_0250(f)::text; exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
      begin v_b := public.supply_reach(f)::text;            exception when others then v_b := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
      v_n := v_n + 1;
      if v_a is distinct from v_b then
        v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'supply_reach', 'fleet', f, 'old', v_a, 'new', v_b));
      end if;
      foreach v_days in array array[5, 30]::numeric[] loop
        begin select to_jsonb(x)::text into v_a from pg_temp.npc_provision_for_old_0250(f, v_days) x; exception when others then v_a := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
        begin select to_jsonb(x)::text into v_b from public.npc_provision_for(f, v_days) x;            exception when others then v_b := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
        v_n := v_n + 1;
        if v_a is distinct from v_b then
          v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'npc_provision_for', 'fleet', f, 'days', v_days, 'old', v_a, 'new', v_b));
        end if;
      end loop;
    end loop;

    -- (e) fleet_load (it writes): each side in its own rolled-back block — what went aboard, and every hull's cargo and basis
    foreach f in array v_fleets[1:8] || v_fleets[greatest(1, cardinality(v_fleets) - 3):] loop
      foreach v_qty in array array[7, 100000]::numeric[] loop
        v_a := pg_temp.load_0250(false, f, v_good.code, v_qty);
        v_b := pg_temp.load_0250(true, f, v_good.code, v_qty);
        v_n := v_n + 1;
        if v_a is distinct from v_b then
          v_bad := v_bad || jsonb_build_array(jsonb_build_object('fn', 'fleet_load', 'fleet', f, 'qty', v_qty, 'old', v_a, 'new', v_b));
        else
          v_loaded := v_loaded + coalesce((v_b::jsonb->>'loaded')::numeric, 0);
        end if;
      end loop;
    end loop;

    v_res := jsonb_build_object('asked', v_n, 'fleets', cardinality(v_fleets), 'ships', cardinality(v_ships),
                                'nonzero', v_nonzero, 'skipped', v_skipped, 'refused', v_refused, 'loaded', v_loaded,
                                'carry', v_carry, 'traits', v_traits, 'bad', jsonb_array_length(v_bad), 'first_bad', v_bad -> 0);
    raise exception using errcode = 'ZY250', message = v_res::text;
  exception when sqlstate 'ZY250' then
    return sqlerrm::jsonb;
  end;
end $$;

create or replace function pg_temp.load_0250(p_new boolean, p_fleet uuid, p_good text, p_qty numeric)
returns text
language plpgsql
as $$
declare
  v_loaded numeric;
  v_res    text;
begin
  begin
    if p_new then
      v_loaded := public.fleet_load(p_fleet, p_good, p_qty, 25);
    else
      v_loaded := pg_temp.fleet_load_old_0250(p_fleet, p_good, p_qty, 25);
    end if;
    select jsonb_build_object('loaded', v_loaded,
             'hulls', jsonb_agg(jsonb_build_array(sh.id, sh.cargo, sh.cargo_basis) order by sh.id))::text
      into v_res from public.ships sh where sh.fleet_id = p_fleet;
    raise exception using errcode = 'ZY250', message = v_res;
  exception
    when sqlstate 'ZY250' then return sqlerrm;
    when others then return 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
end $$;

-- ── 4. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before record;
  v_d   record; v_h record; v_pp record; v_def text;
  v_live  jsonb;
  v_cargo jsonb;
  v_dark  jsonb;
  v_ix    text;
begin
  select * into v_before from before_0250;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0250 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    if pg_temp.occurs_0250(v_def, '0250') = 0 then
      raise exception '0250 self-assert FAIL: % was not re-cut', v_d.fn;
    end if;
    for v_h in select * from hunks_0250 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0250(v_def, v_h.new) <> 1 then
        raise exception '0250 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0250 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0250 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  -- the readers asked twice are asked once
  if pg_temp.occurs_0250(replace(pg_get_functiondef('voyage.ship_speed_at(uuid,numeric)'::regprocedure), E'\r', ''), 'world.ship_stat(') <> 0
     or pg_temp.occurs_0250(replace(pg_get_functiondef('voyage.ship_speed_at(uuid,numeric)'::regprocedure), E'\r', ''), 'join public.goods') <> 0
     or pg_temp.occurs_0250(replace(pg_get_functiondef('public.ship_cargo_tuns(uuid)'::regprocedure), E'\r', ''), 'join public.goods') <> 0 then
    raise exception '0250 self-assert FAIL: ship_speed_at still reads ship_stat twice, or a hold is still weighed by joining every good';
  end if;
  for v_d in select * from defs_before_0250 where fn in ('public.supply_needs(uuid,numeric[])', 'public.supply_reach(uuid)',
                                                         'public.npc_provision_for(uuid,numeric)', 'public.fleet_load(uuid,text,numeric,numeric)') loop
    if pg_temp.occurs_0250(replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', ''), 'ship_hold_capacity(') <> 1 then
      raise exception '0250 self-assert FAIL: % does not read ship_hold_capacity once', v_d.fn;
    end if;
  end loop;

  -- (b) SAME ANSWERS: old and new, on this database as it stands and on a rolled-back probe of hulls carrying cargo
  v_live  := pg_temp.probe_0250(false);
  v_cargo := pg_temp.probe_0250(true);
  v_dark  := pg_temp.probe_0250(false, true);
  if (v_live->>'bad')::int <> 0 or (v_cargo->>'bad')::int <> 0 or (v_dark->>'bad')::int <> 0 then
    raise exception '0250 self-assert FAIL: old and new answered differently: live % / cargo % / other arm %', v_live, v_cargo, v_dark;
  end if;
  if (v_live->>'fleets')::int = 0 or (v_live->>'nonzero')::int = 0 or (v_live->>'skipped')::int = 0
     or (v_dark->>'nonzero')::int = 0 or (v_dark->>'bite')::boolean = public.crew_bite_on() or (v_dark->>'traits')::int = 0 or (v_cargo->>'carry')::int = 0 or (v_cargo->>'traits')::int = 0 or (v_cargo->>'loaded')::numeric = 0 then
    raise exception '0250 self-assert FAIL: the probe proved nothing (no fleet, no captain bearing an effect, no skipped question, no cargo or nothing loaded): live % / cargo %', v_live, v_cargo;
  end if;

  -- (c) THE LAPS' INDEXES, as written
  select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by c.relname) into v_ix
    from pg_index i join pg_class c on c.oid = i.indexrelid
   where i.indrelid = 'public.standing_route_laps'::regclass
     and c.relname in ('standing_route_laps_route_started', 'standing_route_laps_route_closed', 'standing_route_laps_route_traded');
  if v_ix is distinct from
       'CREATE INDEX standing_route_laps_route_closed ON public.standing_route_laps USING btree (route_id, closed_at) WHERE (closed_at IS NOT NULL)'
       || ' | CREATE INDEX standing_route_laps_route_started ON public.standing_route_laps USING btree (route_id, started_at) INCLUDE (id)'
       || ' | CREATE INDEX standing_route_laps_route_traded ON public.standing_route_laps USING btree (route_id, lap_no) WHERE (trades IS NOT NULL)' then
    raise exception '0250 self-assert FAIL: the laps'' indexes are not as written: %', v_ix;
  end if;

  -- (d) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0250 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0250 self-assert FAIL: a wall moved';
  end if;

  raise notice '0250 self-assert ok: A BEAT READS EACH HULL ONCE. Eight bodies re-cut by eleven hunks (crew_pct, ship_speed_at, ship_cargo_tuns, house_skill_scopes, supply_needs, supply_reach, npc_provision_for, fleet_load), each reversed to its pre-image, ACL / volatility / definer / config unmoved; three standing_route_laps indexes as written; registry unchanged; walls 0. OLD vs NEW, as it stands: % questions over % fleets / % hulls (% crew answers above 0, % seated questions skipped, % refusals alike), 0 different; with cargo aboard % hulls and % more traits taken up (rolled back): % questions, 0 different, fleet_load put % aboard alike; crew_terms'' other arm (crew_bite turned %, % traits put down, rolled back): % crew questions, % above 0, 0 different. Nothing left behind.',
    v_live->>'asked', v_live->>'fleets', v_live->>'ships', v_live->>'nonzero', v_live->>'skipped', v_live->>'refused',
    v_cargo->>'carry', v_cargo->>'traits', v_cargo->>'asked', v_cargo->>'loaded', v_dark->>'bite', v_dark->>'traits', v_dark->>'asked', v_dark->>'nonzero';
end $$;
