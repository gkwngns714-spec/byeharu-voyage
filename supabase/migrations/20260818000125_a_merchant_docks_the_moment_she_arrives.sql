-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0125 — A MERCHANT DOCKS THE MOMENT SHE ARRIVES  (docs/MERCHANTS_DOCK_ON_ARRIVAL.md, step M1)
--        "in port" is her TRUE arrival — never before it; and the arrivals sweep runs every 15 s
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
--   "the merchant npc should also be like me."  (2026-10-15)
--   On the design: "in port" is a pure function of time — she is shown docked the moment she really
--   arrives, never before (weather can slow her on the last day); trading, the lap close and the next
--   departure stay in the sweep, which runs every 15 seconds.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- The merchant reads served her `status` / `port` / `voyage` straight off public.fleets, which only
-- the minute sweep (public.tick_arrivals, cron `* * * * *` at 0012:97) writes — so an arrived
-- merchant lay off the quay as a SAILING hull until the sweep reached her: up to a minute plus the
-- sweep's own run (prod, 2026-10-15 16:10, last hour: avg 17 s, max 39.8 s, 60 runs). At 960x that is
-- a day of ship's time. world.sea_roster (0118), world.port_merchants (0113, body 0104) with
-- public.merchant_doing_at (0104), and world.npc_fleet_card (0099 as cut by 0123/0124) all read
-- `f.status` / `f.port_id` / "the SAILING voyage".
--
-- ── THE TRUE ARRIVAL (and what weather is today) ───────────────────────────────────────────────
-- voyage.progress_nm (0006) is the position function: elapsed sim-hours minus the delay RECORDED so
-- far, leg by leg. The only things that change a passage's pace are the daily hazard roll's delay
-- arms in voyage.settle — STORM +36 h, CALM +24..96 h, FAIR_WIND gives back up to what was lost —
-- RECORDED as voyage_events when the sweep resolves the day, and folded into voyages.eta by
-- voyage.recompute_eta. With nothing unresolved, progress_nm reaches the end exactly at the stored
-- eta (asserted below over every merchant at sea). But voyage.day_ends_at CLAMPS every remaining day
-- at the eta, so at the stored eta the last day(s) are still to be rolled — and a CALM there keeps
-- her at sea. The roll is a PURE function (voyage.hazard_roll: voyage, day, world secret; voyage.rng
-- is IMMUTABLE, 0006), so her true arrival is computable without waiting for the sweep:
--   * voyage.day_delay_hours(kind, magnitude, prior) — NEW, THE table of what a day's roll does to
--     the passage (STORM / CALM / FAIR_WIND, moved verbatim out of voyage.settle, which now reads it:
--     three hunks). One answer to "how many hours did that day cost her".
--   * voyage.arrival_at(voyage, t) — NEW. While the stored eta is ahead of t, the stored eta (the
--     days ahead have not happened). Once it is not, the fixed point voyage.settle itself reaches:
--     every unresolved day rolled in order through hazard_roll + day_delay_hours, the day count
--     growing with each delay as voyage.total_days does, the eta re-derived as recompute_eta derives
--     it. Asserted below against voyage.settle on a probe whose remaining days roll a delay. Only
--     passages at or past their stored eta (a handful: the sweep clears them within 15 s) walk.
--   * voyage.where_now(fleet, t) — NEW, the one "where is this fleet NOW": her own status / port /
--     SAILING voyage, except that a passage whose TRUE arrival at a HARBOUR has come reads DOCKED
--     there with no voyage; a passage past its stored eta but delayed serves its true arrival as eta.
--     A plain SQL function (no SECURITY DEFINER, no SET), so the planner inlines it into each read
--     instead of calling it once per merchant.
-- The client never decides an arrival on its own (src/live/seaRoster.ts clamps her at the end of her
-- course until a read serves the docked fact). world.sea_roster's delta now also carries every
-- merchant at or past her stored eta, so the docked fact (or a held passage's true arrival) reaches
-- the map on its next roster beat. (A delta clause on recorded delaying events was measured on prod
-- at +1 s per full read — a hashed scan of voyage_events — and is not here: a mid-passage delay
-- reaches the map when her moved eta passes, as before 0125, and she is never shown in port early.)
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) voyage.day_delay_hours, voyage.arrival_at, voyage.where_now — stable, server-only.
-- (2) voyage.settle — three hunks: the delay arms read voyage.day_delay_hours (values unchanged,
--     asserted over a grid). Clear of 0123's coupon hunk.
-- (3) world.sea_roster, world.port_merchants, world.npc_fleet_card, public.merchant_doing_at — sliced:
--     status / port / roadstead / voyage / eta through voyage.where_now (all stay STABLE). The
--     harbour list's `doing` and its order come from merchant_doing_at, which now reads where_now too.
-- (4) public.tick_arrivals — a wall-clock budget (arrivals_tick_budget_ms, 10 000) measured from the
--     run's start (the candidate scan included), checked before each settle, each yard release and
--     each wake; the next run takes the rest (arrivals first: the loop is in eta order).
-- (5) Cron: byeharu-voyage:arrivals '* * * * *' → '15 seconds' (pg_cron >= 1.5; prod 1.6.4, read
--     2026-10-15), active flag kept as found. pg_cron runs at most one instance of a job at a time — a
--     run due while one is running is queued — so runs never overlap and at most one waits; lock order
--     inside a run is unchanged, so drift / reconcile see the same behaviour, more often.
--     byeharu-voyage:cron-purge (daily 04:23) deletes cron.job_run_details older than 2 days (the
--     arrivals job now writes four rows a minute). Defined INACTIVE (0078: migrations define,
--     wind_the_clock() starts).
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Touch voyage.progress_nm, voyage.recompute_eta, voyage.hazard_roll, cmd.advance, the executor, any
-- table, any client grant, world.fleets (a player's read settles her own fleets, 0009) or
-- world.fleet_trades (it serves no position).
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
--   select cron.alter_job((select jobid from cron.job where jobname = 'byeharu-voyage:arrivals'),
--                         schedule := '* * * * *');                     -- the cadence, one statement
-- and a forward migration restoring the bodies: every OLD hunk is in this file (hunks_0125.old) and
-- the self-assert proves each live body reverses to its pre-image by them.
--
-- SUPERSEDES: voyage.settle (0114 as cut by 0123), world.sea_roster (0118), world.port_merchants
-- (0113), public.merchant_doing_at (0104), world.npc_fleet_card (0099 as cut by 0123/0124),
-- public.tick_arrivals (0092) — hunks sliced from the LIVE bodies (LF-normalised), each asserted to
-- occur exactly once. Self-asserts hold AS FOUND; every probe rolls back. No table, no client grant,
-- no new entry point.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0125 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol
  from unnest(array['world.sea_roster(timestamptz)', 'world.port_merchants(uuid)',
                    'world.npc_fleet_card(uuid)', 'public.merchant_doing_at(uuid, uuid, uuid, timestamptz)',
                    'public.tick_arrivals(timestamptz)', 'voyage.settle(uuid, timestamptz)',
                    'voyage.progress_nm(uuid, timestamptz)']) f(fn);

create temp table before_0125 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config where key = 'arrivals_tick_budget_ms') as knobs_found;

do $$
begin
  execute replace((select def from defs_before_0125 where fn = 'world.sea_roster(timestamptz)'),
    'CREATE OR REPLACE FUNCTION world.sea_roster(', 'CREATE OR REPLACE FUNCTION pg_temp.sea_roster_before_0125(');
  -- the harbour list's pre-image keeps its own doing: its merchant_doing_at call is pointed at a
  -- pre-image of that too.
  execute replace(replace((select def from defs_before_0125 where fn = 'public.merchant_doing_at(uuid, uuid, uuid, timestamptz)'),
    'CREATE OR REPLACE FUNCTION public.merchant_doing_at(', 'CREATE OR REPLACE FUNCTION pg_temp.doing_before_0125('), E'\r', '');
  execute replace(replace((select def from defs_before_0125 where fn = 'world.port_merchants(uuid)'),
    'CREATE OR REPLACE FUNCTION world.port_merchants(', 'CREATE OR REPLACE FUNCTION pg_temp.port_merchants_before_0125('),
    'public.merchant_doing_at(', 'pg_temp.doing_before_0125(');
  execute replace((select def from defs_before_0125 where fn = 'world.npc_fleet_card(uuid)'),
    'CREATE OR REPLACE FUNCTION world.npc_fleet_card(', 'CREATE OR REPLACE FUNCTION pg_temp.card_before_0125(');
end $$;

-- ── 2. THE KNOB ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('arrivals_tick_budget_ms', to_jsonb(10000),
   '0125: the wall-clock budget of one public.tick_arrivals run, in ms, from the run''s start (the '
   'candidate scan included), checked before each settle, yard release and wake; what is left is the '
   'next run''s (the job runs every 15 s; arrivals first, the loop is in eta order).')
on conflict (key) do nothing;

-- ── 3. WHAT A DAY'S ROLL COSTS HER, HER TRUE ARRIVAL, AND WHERE SHE IS NOW ─────────────────────
create or replace function voyage.day_delay_hours(p_kind text, p_magnitude numeric, p_prior numeric)
returns numeric
language sql
immutable
as $$
  -- 0125: THE one table of what a day's roll does to the passage, in sim-hours (DESIGN B.6; moved
  -- verbatim out of voyage.settle's arms, which read it). p_prior: the delay accrued before the day
  -- (voyage.delay_before_day) — a fair wind gives back at most that, so a passage never lands before
  -- she could have sailed (0059).
  select case p_kind
           when 'STORM'     then 36::numeric                                      -- +1.5 voyage-days
           when 'CALM'      then round((1 + 3 * p_magnitude) * 24, 2)             -- 1-4 voyage-days
           when 'FAIR_WIND' then -least(round((0.25 + 0.70 * p_magnitude) * 24, 2), p_prior)
           else 0::numeric end
$$;
comment on function voyage.day_delay_hours(text, numeric, numeric) is
  '0125: THE table of what a day''s hazard roll does to a passage, in sim-hours. voyage.settle and '
  'voyage.arrival_at read it. Server-only.';
revoke all on function voyage.day_delay_hours(text, numeric, numeric) from public, anon, authenticated;

create or replace function voyage.arrival_at(p_voyage uuid, p_at timestamptz default now())
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0125: HER TRUE ARRIVAL as seen at p_at. While the stored eta is ahead of p_at, it is the stored eta:
-- the days ahead have not happened. Once it is not, the fixed point voyage.settle reaches — every
-- unresolved day rolled in order (voyage.hazard_roll, pure), its cost from voyage.day_delay_hours,
-- the day count growing with the delay as voyage.total_days grows, the eta derived as
-- voyage.recompute_eta derives it. Writes nothing.
declare
  v       public.voyages%rowtype;
  v_sim   numeric;
  v_delay numeric;
  v_k     numeric;
  v_eta   timestamptz;
  v_floor timestamptz := '-infinity';
  d       int;
  h       record;
begin
  select * into v from public.voyages where id = p_voyage;
  if v.id is null then return null; end if;
  if v.eta > p_at then return v.eta; end if;
  v_sim   := voyage.sim_hours(v.id);
  v_k     := public.wc_num('time_compression');
  v_delay := v.delay_hours;
  d       := v.last_settled_day + 1;
  loop
    v_eta := v.departed_at + make_interval(secs => ((v_sim + v_delay) * 3600 / v_k)::double precision);
    exit when d > greatest(1, ceil((v_sim + v_delay) / 24)::int);
    -- the day's boundary as voyage.day_ends_at sets it (clamped at the eta of the moment): a day's
    -- weather happens THEN, so a fair wind that pulls her eta behind it lands her at its boundary.
    v_floor := greatest(v_floor, least(v_eta, v.departed_at + make_interval(secs =>
                 ((d * 24 + v_delay) * 3600 / v_k)::double precision)));
    select * into h from voyage.hazard_roll(v.id, d);
    if h.occurred then
      v_delay := v_delay + voyage.day_delay_hours(h.kind, h.magnitude, v_delay);
    end if;
    d := d + 1;
  end loop;
  return greatest(v_eta, v_floor);
end $$;
comment on function voyage.arrival_at(uuid, timestamptz) is
  '0125: a passage''s TRUE arrival as seen at p_at — the stored eta while it is ahead, else the fixed '
  'point voyage.settle reaches over the unresolved days (pure rolls). Server-only.';
revoke all on function voyage.arrival_at(uuid, timestamptz) from public, anon, authenticated;

create or replace function voyage.where_now(p_fleet uuid, p_at timestamptz default now())
returns table (status text, port_id uuid, voyage_id uuid, eta timestamptz)
language sql
stable
as $$
  -- 0125: WHERE THIS FLEET IS NOW. Her own status / port / SAILING voyage — except that a passage
  -- whose TRUE arrival (voyage.arrival_at) at a harbour has come reads DOCKED there with no voyage,
  -- and a passage past its stored eta but held at sea serves its true arrival as `eta`. Plain SQL with
  -- no SECURITY DEFINER and no SET, so a read that joins it gets it inlined: arrival_at is only ever
  -- asked of a passage at or past its stored eta. Writes nothing — the sweep still docks her.
  select case when x.done then 'DOCKED' else f.status end,
         case when x.done then v.dest_port_id else f.port_id end,
         case when x.done then null else v.id end,
         case when x.done then null else a.arrives end
    from public.fleets f
    left join public.voyages v on v.fleet_id = f.id and v.status = 'SAILING'
    -- OFFSET 0 keeps this a subquery of its own, so arrival_at runs once per passage, not once per
    -- column that reads it (a flattened lateral would substitute the call into every reference).
    cross join lateral (select case when v.eta <= p_at then voyage.arrival_at(v.id, p_at) else v.eta end as arrives
                        offset 0) a
    cross join lateral (select coalesce(v.dest_port_id is not null and a.arrives <= p_at, false) as done) x
   where f.id = p_fleet
$$;
comment on function voyage.where_now(uuid, timestamptz) is
  '0125: THE one "where is this fleet now" for the merchant reads: DOCKED at her harbour from her TRUE '
  'arrival (voyage.arrival_at), never before. Inlinable SQL. Server-only.';
revoke all on function voyage.where_now(uuid, timestamptz) from public, anon, authenticated;

-- ── 4. THE HUNKS (old = verbatim from the live bodies; new = what replaces it) ─────────────────
create temp table hunks_0125 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0125 values
-- voyage.settle: the delay arms read the one table
('voyage.settle(uuid, timestamptz)', 1,
$h$      v_delay   := 36;   -- DESIGN B.6: +1.5 voyage-days
$h$,
$h$      v_delay   := voyage.day_delay_hours(h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: DESIGN B.6 +1.5 days, the one table
$h$),
('voyage.settle(uuid, timestamptz)', 2,
$h$      v_delay   := round((1 + 3 * h.magnitude) * 24, 2);   -- DESIGN B.6: 1-4 voyage-days
$h$,
$h$      v_delay   := voyage.day_delay_hours(h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: DESIGN B.6 1-4 days, the one table
$h$),
('voyage.settle(uuid, timestamptz)', 3,
$h$      v_gain    := least(round((0.25 + 0.70 * h.magnitude) * 24, 2),
                         voyage.delay_before_day(v.id, d));
$h$,
$h$      v_gain    := -voyage.day_delay_hours(h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: the one table
$h$),
-- world.sea_roster
('world.sea_roster(timestamptz)', 1,
$h$           'name', f.name, 'status', f.status,
$h$,
$h$           'name', f.name, 'status', w.status,
$h$),
('world.sea_roster(timestamptz)', 2,
$h$           'roadstead', case when f.port_id is not null
$h$,
$h$           'roadstead', case when w.port_id is not null
$h$),
('world.sea_roster(timestamptz)', 3,
$h$                         'eta', v.eta, 'total_nm', v.total_nm, 'departed_at', v.departed_at)
                        from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING'),
$h$,
$h$                         'eta', w.eta, 'total_nm', v.total_nm, 'departed_at', v.departed_at)
                        from public.voyages v where v.id = w.voyage_id),
$h$),
('world.sea_roster(timestamptz)', 4,
$h$    left join public.standing_routes sr on sr.id = nf.route_id
    left join public.nations nn on nn.id = p.nation_id
    left join public.ports po on po.id = f.port_id
    left join public.sea_reaches rs on rs.port_id = f.port_id
$h$,
$h$    left join public.standing_routes sr on sr.id = nf.route_id
    -- 0125: where she is NOW — her TRUE arrival's verdict (voyage.where_now), not the sweep's last write.
    cross join lateral voyage.where_now(f.id) w
    left join public.nations nn on nn.id = p.nation_id
    left join public.ports po on po.id = w.port_id
    left join public.sea_reaches rs on rs.port_id = w.port_id
$h$),
('world.sea_roster(timestamptz)', 5,
$h$                  where v2.fleet_id = f.id and v2.status = 'SAILING' and v2.departed_at >= p_since);
$h$,
$h$                  where v2.fleet_id = f.id and v2.status = 'SAILING' and v2.departed_at >= p_since)
      -- 0125: or she is at or past her stored eta — arrived, or held by her last day's weather (a
      -- handful: the sweep clears them within 15 s). So the docked fact, or the true arrival of a
      -- passage held at sea, reaches the map on its next roster beat.
      or exists (select 1 from public.voyages v3
                  where v3.fleet_id = f.id and v3.status = 'SAILING' and v3.eta <= now());
$h$),
-- world.port_merchants
('world.port_merchants(uuid)', 1,
$h$                     'name', f.name, 'status', f.status,
$h$,
$h$                     'name', f.name, 'status', w.status,
$h$),
('world.port_merchants(uuid)', 2,
$h$                     'roadstead', case when f.port_id is not null
$h$,
$h$                     'roadstead', case when w.port_id is not null
$h$),
('world.port_merchants(uuid)', 3,
$h$                     'voyage', (select world.voyage_view(v.id, false) from public.voyages v
                                 where v.fleet_id = f.id and v.status = 'SAILING'),
$h$,
$h$                     'voyage', (select world.voyage_view(v.id, false) || jsonb_build_object('eta', w.eta)
                                  from public.voyages v where v.id = w.voyage_id),
$h$),
('world.port_merchants(uuid)', 4,
$h$              left join public.ports po on po.id = f.port_id
              left join public.sea_reaches rs on rs.port_id = f.port_id
$h$,
$h$              -- 0125: where she is NOW — her TRUE arrival's verdict (voyage.where_now).
              cross join lateral voyage.where_now(f.id) w
              left join public.ports po on po.id = w.port_id
              left join public.sea_reaches rs on rs.port_id = w.port_id
$h$),
-- public.merchant_doing_at: `doing` (and so the harbour list's order) from the same fact
('public.merchant_doing_at(uuid, uuid, uuid, timestamptz)', 1,
$h$  select * into f from public.fleets where id = p_fleet;
$h$,
$h$  select * into f from public.fleets where id = p_fleet;
  -- 0125: where she is NOW (voyage.where_now): arrived by her true arrival, she is HERE, not bound.
  select w.status, w.port_id into f.status, f.port_id from voyage.where_now(p_fleet, p_now) w;
$h$),
-- world.npc_fleet_card
('world.npc_fleet_card(uuid)', 1,
$h$  sr  public.standing_routes%rowtype;
begin
$h$,
$h$  sr  public.standing_routes%rowtype;
  w   record;   -- 0125
begin
$h$),
('world.npc_fleet_card(uuid)', 2,
$h$    raise exception 'E_NOT_FOUND: there is no such merchant fleet' using errcode = 'P0001';
  end if;
  select * into p from public.players where id = f.player_id;
$h$,
$h$    raise exception 'E_NOT_FOUND: there is no such merchant fleet' using errcode = 'P0001';
  end if;
  -- 0125: where she is NOW — her TRUE arrival's verdict (voyage.where_now), not the sweep's last write.
  select * into w from voyage.where_now(f.id);
  f.status  := w.status;
  f.port_id := w.port_id;
  select * into p from public.players where id = f.player_id;
$h$),
('world.npc_fleet_card(uuid)', 3,
$h$      'voyage', (select world.voyage_view(v.id, true) - 'id' from public.voyages v
                  where v.fleet_id = f.id and v.status = 'SAILING')),
$h$,
$h$      'voyage', (select (world.voyage_view(v.id, true) - 'id') || jsonb_build_object('eta', w.eta)
                   from public.voyages v where v.id = w.voyage_id)),
$h$),
-- public.tick_arrivals
('public.tick_arrivals(timestamptz)', 1,
$h$  v_days    int := 0;
begin
$h$,
$h$  v_days    int := 0;
  -- 0125: a run's wall-clock budget from its start (the candidate scan included); what is left is
  -- the next run's (the job runs every 15 s).
  v_t0      timestamptz := clock_timestamp();
  v_budget  interval := make_interval(secs => public.wc_int('arrivals_tick_budget_ms') / 1000.0);
begin
$h$),
('public.tick_arrivals(timestamptz)', 2,
$h$              for update skip locked loop
    v_days   := v_days + voyage.settle(r.fleet_id, p_now);
$h$,
$h$              for update skip locked loop
    exit when clock_timestamp() >= v_t0 + v_budget;   -- 0125
    v_days   := v_days + voyage.settle(r.fleet_id, p_now);
$h$),
('public.tick_arrivals(timestamptz)', 3,
$h$              for update skip locked loop
    perform cmd.advance(r.id, p_now);
$h$,
$h$              for update skip locked loop
    exit when clock_timestamp() >= v_t0 + v_budget;   -- 0125
    perform cmd.advance(r.id, p_now);
$h$),
('public.tick_arrivals(timestamptz)', 4,
$h$              for update of f skip locked loop
    update public.standing_routes set hold_until = null where fleet_id = r.id;
$h$,
$h$              for update of f skip locked loop
    exit when clock_timestamp() >= v_t0 + v_budget;   -- 0125
    update public.standing_routes set hold_until = null where fleet_id = r.id;
$h$);

-- ── 5. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0125(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0125 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0125 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0125(fn) from (values ('voyage.settle(uuid, timestamptz)'), ('world.sea_roster(timestamptz)'),
                                           ('public.merchant_doing_at(uuid, uuid, uuid, timestamptz)'),
                                           ('world.port_merchants(uuid)'), ('world.npc_fleet_card(uuid)'),
                                           ('public.tick_arrivals(timestamptz)')) x(fn);

-- ── 6. THE CADENCE, AND THE LOG'S KEEP ─────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0125: pg_cron is not installed here (PGlite) — neither the 15 s cadence nor the purge is scheduled in this database';
    return;
  end if;
  perform cron.alter_job(j.jobid, schedule := '15 seconds')
     from cron.job j where j.jobname = 'byeharu-voyage:arrivals';
  perform cron.schedule('byeharu-voyage:cron-purge', '23 4 * * *',
    $c$delete from cron.job_run_details where end_time < now() - interval '2 days'$c$);
  -- 0078: DEFINED, NOT RUNNING — wind_the_clock() starts it with the rest of the clock.
  perform cron.alter_job(jobid, active := false) from cron.job where jobname = 'byeharu-voyage:cron-purge';
end $$;

-- ── 7. THE SELF-ASSERT ─────────────────────────────────────────────────────────────────────────
do $$
declare
  c_cut     constant text[] := array['voyage.settle(uuid, timestamptz)', 'world.sea_roster(timestamptz)',
                                     'world.port_merchants(uuid)', 'world.npc_fleet_card(uuid)',
                                     'public.merchant_doing_at(uuid, uuid, uuid, timestamptz)',
                                     'public.tick_arrivals(timestamptz)'];
  c_reads   constant text[] := array['world.sea_roster(timestamptz)', 'world.port_merchants(uuid)',
                                     'world.npc_fleet_card(uuid)', 'public.merchant_doing_at(uuid, uuid, uuid, timestamptz)'];
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  r         record;
  v_n       int;
  v_bad     int;
  v_was_on  boolean := public.npc_traders_on();
  v_routes_on boolean := public.standing_routes_on();
  v_subj    uuid[];
  v_route   uuid[];
  v_vid     uuid[];
  v_dest    uuid[];
  v_b       int;
  v_true    timestamptz;
  v_naive   timestamptz;
  v_rows    jsonb;
  v_row     jsonb;
  v_card    jsonb;
  v_pm      jsonb;
  v_t0      timestamptz;
  v_ms_new  numeric;
  v_ms_old  numeric;
  v_sailing int;
  v_cron    text;
  v_purge   text;
  v_msg     text;
  i         int;
begin
  -- (a) POSTURE: every cut body keeps its volatility and ACL; the helpers are server-only; no new
  --     entry point; no client write; the knob is this file's.
  for v_fn in select unnest(c_cut) loop
    if (select p.provolatile from pg_proc p where p.oid = v_fn::regprocedure)
       is distinct from (select vol from defs_before_0125 where fn = v_fn) then
      raise exception '0125 self-assert FAIL: the volatility of % moved', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0125 where fn = v_fn) then
      raise exception '0125 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;
  foreach v_fn in array array['voyage.day_delay_hours(text, numeric, numeric)', 'voyage.arrival_at(uuid, timestamptz)',
                              'voyage.where_now(uuid, timestamptz)'] loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0125 self-assert FAIL: % is client-callable', v_fn;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0125)
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0125 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;
  if (select knobs_found from before_0125) <> 0 or public.wc_int('arrivals_tick_budget_ms') <> 10000 then
    raise exception '0125 self-assert FAIL: arrivals_tick_budget_ms existed before this file or is not 10000';
  end if;

  -- (b) ONE AUTHORITY. Each cut body reverses to its pre-image hunk by hunk, each hunk once; the four
  --     merchant bodies ask voyage.where_now exactly once and no longer read the SAILING voyage
  --     themselves; settle's delay arms carry no literal of their own; progress_nm is untouched.
  for v_fn in select unnest(c_cut) loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0125 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0125 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0125 where fn = v_fn) or v_def = v_back then
      raise exception '0125 self-assert FAIL: % is not its pre-image plus only 0125''s hunks', v_fn;
    end if;
    if v_fn = any(c_reads)
       and ((length(v_def) - length(replace(v_def, 'voyage.where_now(', ''))) / length('voyage.where_now(') <> 1
            or strpos(v_def, 'v.fleet_id = f.id and v.status = ''SAILING''),') > 0) then
      raise exception '0125 self-assert FAIL: % does not take where she is from voyage.where_now alone', v_fn;
    end if;
  end loop;
  v_def := pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure);
  if strpos(v_def, ':= 36;') > 0 or strpos(v_def, '(1 + 3 * h.magnitude)') > 0 or strpos(v_def, '(0.25 + 0.70 * h.magnitude)') > 0
     or (length(v_def) - length(replace(v_def, 'voyage.day_delay_hours(', ''))) / length('voyage.day_delay_hours(') <> 3 then
    raise exception '0125 self-assert FAIL: voyage.settle still carries a delay arm of its own';
  end if;
  if replace(pg_get_functiondef('voyage.progress_nm(uuid, timestamptz)'::regprocedure), E'\r', '')
     <> (select def from defs_before_0125 where fn = 'voyage.progress_nm(uuid, timestamptz)') then
    raise exception '0125 self-assert FAIL: voyage.progress_nm was re-cut';
  end if;
  -- THE TABLE IS THE OLD ARMS, to the digit, over a grid (positive control: a kind with no arm is 0).
  select count(*) into v_bad
    from unnest(array['STORM', 'CALM', 'FAIR_WIND', 'PIRATES']) k(kind),
         unnest(array[0, 0.000001, 0.37, 0.5, 0.999999]::numeric[]) m(mag),
         unnest(array[0, 3.5, 24, 200]::numeric[]) pr(prior)
   where voyage.day_delay_hours(k.kind, m.mag, pr.prior) is distinct from
         case k.kind when 'STORM' then 36 when 'CALM' then round((1 + 3 * m.mag) * 24, 2)
                     when 'FAIR_WIND' then -least(round((0.25 + 0.70 * m.mag) * 24, 2), pr.prior) else 0 end;
  if v_bad > 0 then
    raise exception '0125 self-assert FAIL: % cell(s) of voyage.day_delay_hours differ from the arms it replaced', v_bad;
  end if;
  -- where_now is inlinable: plain SQL, no SECURITY DEFINER, no SET.
  if (select p.prosecdef or p.proconfig is not null or l.lanname <> 'sql' from pg_proc p join pg_language l on l.oid = p.prolang
       where p.oid = 'voyage.where_now(uuid, timestamptz)'::regprocedure) then
    raise exception '0125 self-assert FAIL: voyage.where_now cannot be inlined';
  end if;

  -- (c) THE CADENCE AND THE PURGE, where there is a scheduler.
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute 'select schedule from cron.job where jobname = ''byeharu-voyage:arrivals''' into v_cron;
    execute 'select schedule || case when active then '' active'' else '' inactive'' end from cron.job where jobname = ''byeharu-voyage:cron-purge''' into v_purge;
    if v_cron is distinct from '15 seconds' or v_purge is distinct from '23 4 * * * inactive' then
      raise exception '0125 self-assert FAIL: arrivals on "%", purge "%"', v_cron, v_purge;
    end if;
  end if;

  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');

    -- PROBES: merchants AT SEA on their route for one of its harbours (the live world has hundreds; a
    -- world where none sails is topped up through the one start door), held FOR UPDATE so a live
    -- sweep passes them by. Up to 12, so one whose remaining days roll a delay can be found below.
    select coalesce(array_agg(x.fleet_id order by x.ord, x.fleet_id), '{}'), coalesce(array_agg(x.route_id order by x.ord, x.fleet_id), '{}')
      into v_subj, v_route
      from (select nf.fleet_id, nf.route_id, nf.roster_ord as ord
              from public.npc_fleets nf
              join public.voyages v on v.fleet_id = nf.fleet_id and v.status = 'SAILING'
              join public.ports po on po.id = v.dest_port_id and po.kind = 'HARBOUR'
             where nf.route_id is not null and v.eta > now() + interval '5 minutes'
               and exists (select 1 from public.standing_route_stops st where st.route_id = nf.route_id and st.port_id = v.dest_port_id)
             order by nf.roster_ord, nf.fleet_id limit 12) x;
    for r in select nf.fleet_id, nf.route_id, f.player_id
               from public.npc_fleets nf
               join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
               join public.standing_route_stops st on st.route_id = nf.route_id and st.ord = 0 and st.port_id = f.port_id
               join public.players pl on pl.id = f.player_id
               join public.standing_routes sr on sr.id = nf.route_id
              where nf.route_id is not null and pl.ducats >= sr.reserve
                and not exists (select 1 from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING')
                and not exists (select 1 from public.standing_route_laps x
                                 where x.route_id = nf.route_id and x.closed_at > now() - interval '30 minutes')
              order by nf.roster_ord, nf.fleet_id limit 24 loop
      exit when coalesce(array_length(v_subj, 1), 0) >= 12;
      perform cmd.standing_route_assign_for(r.player_id, r.route_id, r.fleet_id);
      if exists (select 1 from public.voyages v where v.fleet_id = r.fleet_id and v.status = 'SAILING'
                    and v.dest_port_id is not null) then
        v_subj := v_subj || r.fleet_id;
        v_route := v_route || r.route_id;
      end if;
    end loop;
    select array_agg(v.id order by k), array_agg(v.dest_port_id order by k) into v_vid, v_dest
      from unnest(v_subj) with ordinality s(fid, k)
      join public.voyages v on v.fleet_id = s.fid and v.status = 'SAILING';
    if coalesce(array_length(v_vid, 1), 0) < 3 then
      raise exception '0125 self-assert FAIL: three merchants at sea to probe were not found (%)', coalesce(array_length(v_vid, 1), 0);
    end if;
    perform 1 from public.voyages where id = any(v_vid) for update;

    -- (d) THE POSITION AND THE STORED ETA AGREE when nothing is left unrolled — over every merchant at
    --     sea (the world as found, the probes among them): progress_nm reaches the end at the eta, not
    --     a second before.
    select count(*), count(*) filter (where
             voyage.progress_nm(v.id, v.eta + interval '1 millisecond')
               < least(round((select sum((e->>'nm')::numeric) from jsonb_array_elements(v.path) e), 4), v.total_nm)
          or voyage.progress_nm(v.id, v.eta - interval '1 second')
               >= least(round((select sum((e->>'nm')::numeric) from jsonb_array_elements(v.path) e), 4), v.total_nm))
      into v_sailing, v_bad
      from public.voyages v join public.fleets f on f.id = v.fleet_id
      join public.players p on p.id = f.player_id and p.is_npc
     where v.status = 'SAILING' and v.dest_port_id is not null;
    if v_bad > 0 or v_sailing < 3 then
      raise exception '0125 self-assert FAIL: % of % merchant passages reach the end of their path off their eta', v_bad, v_sailing;
    end if;

    -- (e) PARITY, nobody arrived: with the probes at sea every read is its pre-image to the byte —
    --     asked twice at most, as another job may commit between a pair. The full roster is compared
    --     only on a world where no merchant is at or past her eta (on a live one somebody always is).
    for i in 1 .. 2 loop
      v_n := (world.npc_fleet_card(v_subj[1]) is distinct from pg_temp.card_before_0125(v_subj[1]))::int
           + (case when exists (select 1 from public.voyages v join public.npc_fleets nf on nf.fleet_id = v.fleet_id
                                  join public.standing_route_stops st on st.route_id = nf.route_id and st.port_id = v_dest[1]
                                 where v.status = 'SAILING' and v.eta <= now())
                   then 0   -- one of this harbour's merchants is arriving on a live world: she differs, rightly
                   else (world.port_merchants(v_dest[1]) is distinct from pg_temp.port_merchants_before_0125(v_dest[1]))::int end)
           + (case when exists (select 1 from public.voyages v join public.fleets f on f.id = v.fleet_id
                                  join public.players p on p.id = f.player_id and p.is_npc
                                 where v.status = 'SAILING' and v.eta <= now())
                   then 0
                   else (world.sea_roster(null) is distinct from pg_temp.sea_roster_before_0125(null))::int
                      + (world.sea_roster(now() - interval '15 seconds') is distinct from pg_temp.sea_roster_before_0125(now() - interval '15 seconds'))::int end);
      exit when v_n = 0;
    end loop;
    if v_n <> 0 then
      raise exception '0125 self-assert FAIL: % read(s) differ from their pre-image while nobody probed has arrived', v_n;
    end if;

    -- (i) COST: the full roster read, new body against old, on the world as found (probes at sea, none
    --     rewound: a rewound passage has every day of it left to roll, which no live passage has).
    v_t0 := clock_timestamp(); perform world.sea_roster(null);
    v_ms_new := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1);
    v_t0 := clock_timestamp(); perform pg_temp.sea_roster_before_0125(null);
    v_ms_old := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1);

    -- Every probe's passage REWOUND whole (departed_at and eta back together, proof 12's rewind):
    -- at the naive eta, a minute ago. Her remaining days are still to be rolled.
    update public.voyages v set departed_at = v.departed_at - (v.eta - now()) - interval '1 minute',
                                eta = now() - interval '1 minute'
     where v.id = any(v_vid);

    -- (f) NEVER IN PORT BEFORE SHE REALLY ARRIVES. The odds raised to the most the schema allows (every
    --     sea's hazard_base 0.05, every leg of the probes' frozen paths hazard_mult 5: p = 0.25 a day;
    --     the roll stays the pure function, only the odds move), find a probe whose remaining days COST
    --     her more than the minute: at the naive eta every read shows her at sea, bound for the same
    --     harbour, with her true arrival as eta — and voyage.settle, run a second before that true
    --     arrival, leaves her at sea, and run AT it, docks her there (her stored eta at or before it: a
    --     fair wind on her last day lands her at that day's boundary).
    update public.seas set hazard_base = 0.05;
    update public.voyages v
       set path = (select jsonb_agg(jsonb_set(e, '{hazard_mult}', '5'::jsonb) order by o)
                     from jsonb_array_elements(v.path) with ordinality t(e, o))
     where v.id = any(v_vid);
    update public.world_config set value = to_jsonb(1.0) where key = 'hazard_p_max';
    v_b := null;
    for i in 1 .. array_length(v_vid, 1) loop
      if voyage.arrival_at(v_vid[i]) > now() + interval '5 seconds' then v_b := i; exit; end if;
    end loop;
    if v_b is null then
      raise exception '0125 self-assert FAIL: no probe''s remaining days rolled a delay — the proof found nothing to prove';
    end if;
    v_naive := (select eta from public.voyages where id = v_vid[v_b]);
    v_true  := voyage.arrival_at(v_vid[v_b]);
    update public.standing_routes set updated_at = now() - interval '1 hour' where id = v_route[v_b];
    v_rows := world.sea_roster(now() - interval '15 seconds');
    select x into v_row from jsonb_array_elements(v_rows->'fleets') x where x->>'id' = v_subj[v_b]::text;
    v_card := world.npc_fleet_card(v_subj[v_b]);
    v_pm := world.port_merchants(v_dest[v_b]);
    if v_row is null or v_row->>'status' <> 'SAILING' or (v_row->'voyage'->>'eta')::timestamptz <> v_true
       or v_row->'voyage'->>'to' <> (select code from public.ports where id = v_dest[v_b])
       or v_card->'fleet'->>'status' <> 'SAILING' or (v_card->'fleet'->'voyage'->>'eta')::timestamptz <> v_true
       or (select m->>'status' from jsonb_array_elements(v_pm->'merchants') m where m->>'id' = v_subj[v_b]::text) <> 'SAILING'
       or (select m->>'doing' from jsonb_array_elements(v_pm->'merchants') m where m->>'id' = v_subj[v_b]::text) not in ('ending', 'passing') then
      raise exception '0125 self-assert FAIL: past her naive eta % but truly arriving %, a read shows her in port: roster %, card %',
        v_naive, v_true, v_row, v_card->'fleet';
    end if;
    perform voyage.settle(v_subj[v_b], v_true - interval '1 second');
    if (select status from public.voyages where id = v_vid[v_b]) <> 'SAILING' then
      raise exception '0125 self-assert FAIL: voyage.settle docked her before the true arrival % it was told', v_true;
    end if;
    perform voyage.settle(v_subj[v_b], v_true);
    if (select status from public.voyages where id = v_vid[v_b]) <> 'ARRIVED'
       or (select eta from public.voyages where id = v_vid[v_b]) > v_true + interval '1 millisecond' then
      raise exception '0125 self-assert FAIL: voyage.settle at the true arrival % left her % with eta %', v_true,
        (select status from public.voyages where id = v_vid[v_b]), (select eta from public.voyages where id = v_vid[v_b]);
    end if;
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';

    -- (g) ONCE SHE HAS TRULY ARRIVED she is in port on every read — with nothing written. Hazards off,
    --     a probe other than B: her remaining days cost nothing, so her true arrival is the naive eta.
    i := case when v_b = 1 then 2 else 1 end;
    if voyage.arrival_at(v_vid[i]) > now() then
      raise exception '0125 self-assert FAIL: with hazards off a probe is still not arrived';
    end if;
    v_rows := world.sea_roster(null);
    v_card := world.npc_fleet_card(v_subj[i]);
    execute 'set local role authenticated';
    v_pm := world.port_merchants(v_dest[i]);
    execute 'reset role';
    select x into v_row from jsonb_array_elements(v_rows->'fleets') x where x->>'id' = v_subj[i]::text;
    if v_row->>'status' <> 'DOCKED' or v_row->>'port' <> (select code from public.ports where id = v_dest[i])
       or jsonb_typeof(v_row->'voyage') <> 'null'
       or v_row->'roadstead' <> (select jsonb_build_array(rs.roadstead_lat, rs.roadstead_lon) from public.sea_reaches rs where rs.port_id = v_dest[i])
       or v_card->'fleet'->>'status' <> 'DOCKED' or v_card->'fleet'->>'port' <> v_row->>'port'
       or jsonb_typeof(v_card->'fleet'->'voyage') <> 'null'
       or (select m->>'status' from jsonb_array_elements(v_pm->'merchants') m where m->>'id' = v_subj[i]::text) <> 'DOCKED'
       or (select m->>'doing' from jsonb_array_elements(v_pm->'merchants') m where m->>'id' = v_subj[i]::text) not in ('starting', 'resting', 'passing', 'laid_up')
       or (select status from public.voyages where id = v_vid[i]) <> 'SAILING'
       or (select status from public.fleets where id = v_subj[i]) <> 'SAILING' then
      raise exception '0125 self-assert FAIL: truly arrived, she is not in port on every read (or a read wrote): roster %, card %, harbour %',
        v_row, v_card->'fleet', (select m from jsonb_array_elements(v_pm->'merchants') m where m->>'id' = v_subj[i]::text);
    end if;

    -- (h) THE SWEEP'S BUDGET BITES: at 0 ms a run settles nobody; the sweep's settle docks her.
    update public.world_config set value = to_jsonb(0) where key = 'arrivals_tick_budget_ms';
    perform public.tick_arrivals();
    if (select status from public.voyages where id = v_vid[i]) <> 'SAILING' then
      raise exception '0125 self-assert FAIL: a 0 ms sweep still settled a merchant';
    end if;
    update public.world_config set value = to_jsonb(10000) where key = 'arrivals_tick_budget_ms';
    perform voyage.settle(v_subj[i]);
    if (select status from public.voyages where id = v_vid[i]) <> 'ARRIVED' then
      raise exception '0125 self-assert FAIL: the sweep''s settle did not dock a truly arrived merchant';
    end if;

    raise exception 'ROLLBACK_0125|%|%|%|%|%', v_sailing, v_ms_new, v_ms_old, v_naive, v_true;
  exception when others then
    if sqlerrm not like 'ROLLBACK_0125|%' then raise; end if;
    v_msg := sqlerrm;
  end;
  if public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on
     or public.wc_int('arrivals_tick_budget_ms') <> 10000 or current_user <> session_user
     or exists (select 1 from public.voyages v where v.id = any(v_vid) and v.eta = now() - interval '1 minute') then
    raise exception '0125 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0125 self-assert ok: A MERCHANT DOCKS THE MOMENT SHE ARRIVES — never before. sea_roster, port_merchants (doing and order through merchant_doing_at), npc_fleet_card take status / port / roadstead / voyage / eta from voyage.where_now alone (inlinable SQL), reverse to their pre-images hunk by hunk, volatility and ACLs unmoved; voyage.settle''s delay arms read voyage.day_delay_hours, equal to the old arms over a grid; progress_nm untouched; helpers server-only; no new entry point, no client write. Over % merchant passage(s) at sea the position reaches the end exactly at the eta. With nobody arrived every read is its pre-image. A probe past her naive eta (%) whose remaining days roll a delay is shown AT SEA on every read with her true arrival (%) as eta, and voyage.settle agrees: at sea a second before it, ARRIVED at it with that eta. Truly arrived, a probe is DOCKED at her harbour''s roadstead on the roster, the card and the harbour''s read (as authenticated) with nothing written. Cron: %, purge %. A 0 ms sweep settles nobody; its settle docks her. Full roster % ms (before: % ms). Rolled back.',
    split_part(v_msg, '|', 2), split_part(v_msg, '|', 5), split_part(v_msg, '|', 6),
    coalesce(v_cron, 'no scheduler here'), coalesce(v_purge, '—'), split_part(v_msg, '|', 3), split_part(v_msg, '|', 4);
end $$;
