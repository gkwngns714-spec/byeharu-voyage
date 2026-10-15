-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0125 — A MERCHANT DOCKS THE MOMENT SHE ARRIVES  (docs/MERCHANTS_DOCK_ON_ARRIVAL.md, step M1)
--        "in port" is where her position says she is; and the arrivals sweep runs every 15 s
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
--   "the merchant npc should also be like me."  (2026-10-15)
--   And, on the design: "in port" is a pure function of time — the ship's actual position (the same
--   function the map uses) has reached her destination, never a stored eta; the arrival is not known
--   at departure (weather can slow her mid-passage); trading, the lap close and the next departure
--   stay in the sweep, which runs every 15 seconds.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- The merchant reads served her `status` / `port` / `voyage` straight off public.fleets, which only
-- the minute sweep (public.tick_arrivals, cron `* * * * *` at 0012:97) writes — so an arrived
-- merchant lay off the quay as a SAILING hull until the sweep reached her: up to a minute plus the
-- sweep's own run (prod, last hour, 2026-10-15 16:10: avg 17 s, max 39.8 s, 60 runs). At 960x that
-- is a day of ship's time. world.sea_roster (0118), world.port_merchants (0113, body 0104) and
-- world.npc_fleet_card (0099 as cut by 0124) all read `f.status` / `f.port_id` / "the SAILING voyage".
--
-- ── THE POSITION IS THE ONE AUTHORITY (and what weather is today) ──────────────────────────────
-- voyage.progress_nm(voyage, t) (0006) is THE position function: elapsed sim-hours minus the delay
-- RECORDED so far (voyage.delay_before_day reads public.voyage_events), consumed leg by leg at the
-- leg's speed. voyage.position and the chart's drift read it. Today the only things that change a
-- passage's pace are the daily hazard roll's delay arms in voyage.settle — STORM (+36 h), CALM
-- (+24..96 h), FAIR_WIND (gives back up to what was lost) — each RECORDED as a voyage_event and
-- folded into voyages.eta by voyage.recompute_eta. Nothing is known ahead: a day's delay exists from
-- the moment the sweep resolves that day, and not before. So:
--   * voyage.arrived(voyage, t) — NEW, the one "has she reached the end of her path": her
--     progress_nm at t has reached the end of the path progress_nm walks. It reads no eta. A later
--     weather system that changes speed must flow through progress_nm, and both the map and "in port"
--     follow it with no second edit (it holds whether weather is rolled from a seed and recorded when
--     resolved, or rolled live and recorded: progress_nm reads what is recorded).
--   * voyage.where_now(fleet, t) — NEW, the one "where is this fleet NOW": her own status / port /
--     SAILING voyage, except that a SAILING fleet whose position has reached a HARBOUR reads
--     DOCKED at that harbour with no voyage. It writes nothing; the sweep still docks her, trades,
--     closes the lap and sails her on — through voyage.settle, unchanged.
--   The client places a roster merchant linearly in time from departure to the served eta
--   (src/live/seaRoster.ts); recompute_eta writes eta = departed + (sim-hours + recorded delay), the
--   instant progress_nm reaches the end, so the two arrive on the same instant — asserted below over
--   every merchant at sea. A delay recorded after the read moves her eta; world.sea_roster's delta
--   now carries a fleet whose passage gained a delaying event since p_since, so the map learns it on
--   its next 30 s beat (before 0125 an eta change never reached the delta at all).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) voyage.arrived, voyage.where_now — stable, server-only.
-- (2) world.sea_roster, world.port_merchants, world.npc_fleet_card — sliced: status / port /
--     roadstead / voyage through voyage.where_now (the reads stay STABLE: they write nothing). The
--     roster's delta also carries a passage whose arrival moved (a recorded delaying event).
-- (3) public.tick_arrivals — sliced: a wall-clock budget (arrivals_tick_budget_ms, 10 000), checked
--     before each settle and each wake, so a run stays short and the next run takes the rest (the
--     arrivals are taken first: the loop is in eta order).
-- (4) The cron job byeharu-voyage:arrivals: '* * * * *' → '15 seconds' (pg_cron >= 1.5; prod runs
--     1.6.4). cron.alter_job keeps the job's active flag as found (0078: the chain defines, the
--     runbook winds). pg_cron runs at most one instance of a job at a time — a run due while one is
--     running is queued and starts when it ends — so runs never overlap and at most one waits. Lock
--     order inside a run is the sweep's own and unchanged, so the drift / reconcile behaviour is the
--     same; only the cadence moves.
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Touch voyage.settle, voyage.progress_nm, voyage.recompute_eta, cmd.advance, the executor, any
-- table, any grant, world.fleets (a player's read settles her own fleets, 0009) or
-- world.fleet_trades (it serves no position). public.merchant_doing_at is not re-cut: an arrived,
-- not-yet-swept merchant reads `ending` / `passing` for the seconds until the sweep docks her.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
--   select cron.alter_job((select jobid from cron.job where jobname = 'byeharu-voyage:arrivals'),
--                         schedule := '* * * * *');                     -- the cadence, one statement
--   update public.world_config set value = '600000' where key = 'arrivals_tick_budget_ms';  -- no cut
-- and a forward migration restoring the reads: every OLD hunk is in this file (hunks_0125.old) and
-- the self-assert proves each live body reverses to its pre-image by them.
--
-- SUPERSEDES: world.sea_roster (0118), world.port_merchants (0113), world.npc_fleet_card (0099 as
-- cut by 0124), public.tick_arrivals (0092) — hunks sliced from the LIVE bodies (LF-normalised),
-- each asserted to occur exactly once. The card's hunks are clear of 0123's 'refounded_at' line
-- and of 0124's 'ships' line. Self-asserts hold AS FOUND; every probe rolls back. No table, no client
-- grant, no new entry point.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0125 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol
  from unnest(array['world.sea_roster(timestamptz)', 'world.port_merchants(uuid)',
                    'world.npc_fleet_card(uuid)', 'public.tick_arrivals(timestamptz)',
                    'voyage.settle(uuid, timestamptz)', 'voyage.progress_nm(uuid, timestamptz)']) f(fn);

create temp table before_0125 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config where key = 'arrivals_tick_budget_ms') as knobs_found;

do $$
begin
  execute replace((select def from defs_before_0125 where fn = 'world.sea_roster(timestamptz)'),
    'CREATE OR REPLACE FUNCTION world.sea_roster(', 'CREATE OR REPLACE FUNCTION pg_temp.sea_roster_before_0125(');
  execute replace((select def from defs_before_0125 where fn = 'world.port_merchants(uuid)'),
    'CREATE OR REPLACE FUNCTION world.port_merchants(', 'CREATE OR REPLACE FUNCTION pg_temp.port_merchants_before_0125(');
  execute replace((select def from defs_before_0125 where fn = 'world.npc_fleet_card(uuid)'),
    'CREATE OR REPLACE FUNCTION world.npc_fleet_card(', 'CREATE OR REPLACE FUNCTION pg_temp.card_before_0125(');
end $$;

-- ── 2. THE KNOB ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('arrivals_tick_budget_ms', to_jsonb(10000),
   '0125: the wall-clock budget of one public.tick_arrivals run, in ms, checked before each settle '
   'and each wake; what is left is the next run''s (the job runs every 15 s; arrivals come first, '
   'the loop is in eta order). 600000 = no cut in practice.')
on conflict (key) do nothing;

-- ── 3. THE POSITION'S VERDICT, AND WHERE A FLEET IS NOW ────────────────────────────────────────
create or replace function voyage.arrived(p_voyage uuid, p_at timestamptz default now())
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0125: HAS SHE REACHED THE END OF HER PATH at p_at — by voyage.progress_nm, THE position function,
-- against the farthest point progress_nm itself can report (the walked legs, capped at total_nm,
-- rounded as it rounds). No eta is read. Cost guard: a passage cannot be done before its undelayed
-- sailing time (recorded delay is never negative: voyages.delay_hours >= 0 and FAIR_WIND gives back
-- at most what was lost), so progress_nm is walked only for a passage that could be.
declare
  v public.voyages%rowtype;
begin
  select * into v from public.voyages where id = p_voyage;
  if v.id is null then return false; end if;
  if extract(epoch from (p_at - v.departed_at)) * public.wc_num('time_compression') / 3600
     < voyage.sim_hours(v.id) then
    return false;
  end if;
  return voyage.progress_nm(v.id, p_at)
         >= least(round((select coalesce(sum((e->>'nm')::numeric), 0) from jsonb_array_elements(v.path) e), 4),
                  v.total_nm);
end $$;
comment on function voyage.arrived(uuid, timestamptz) is
  '0125: THE one "has she reached the end of her path" — voyage.progress_nm at p_at against the end '
  'of the path it walks. Reads no eta. Server-only.';
revoke all on function voyage.arrived(uuid, timestamptz) from public, anon, authenticated;

create or replace function voyage.where_now(p_fleet uuid, p_at timestamptz default now())
returns table (status text, port_id uuid, voyage_id uuid)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0125: WHERE THIS FLEET IS NOW — her own status / port / SAILING voyage, except that a passage
  -- whose position has reached a HARBOUR reads DOCKED there, with no voyage. Writes nothing: the
  -- sweep (voyage.settle) still docks her, and everything that follows a docking follows it there.
  select case when a.done then 'DOCKED' else f.status end,
         case when a.done then v.dest_port_id else f.port_id end,
         case when a.done then null else v.id end
    from public.fleets f
    left join public.voyages v on v.fleet_id = f.id and v.status = 'SAILING'
    cross join lateral (select v.id is not null and v.dest_port_id is not null
                               and voyage.arrived(v.id, p_at) as done) a
   where f.id = p_fleet
$$;
comment on function voyage.where_now(uuid, timestamptz) is
  '0125: THE one "where is this fleet now" for the merchant reads: a passage whose position '
  '(voyage.arrived) has reached its harbour reads DOCKED there with no voyage. Server-only.';
revoke all on function voyage.where_now(uuid, timestamptz) from public, anon, authenticated;

-- ── 4. THE HUNKS (old = verbatim from the live bodies; new = what replaces it) ─────────────────
create temp table hunks_0125 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0125 values
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
$h$                        from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING'),
$h$,
$h$                        from public.voyages v where v.id = w.voyage_id),
$h$),
('world.sea_roster(timestamptz)', 4,
$h$    left join public.standing_routes sr on sr.id = nf.route_id
    left join public.nations nn on nn.id = p.nation_id
    left join public.ports po on po.id = f.port_id
    left join public.sea_reaches rs on rs.port_id = f.port_id
$h$,
$h$    left join public.standing_routes sr on sr.id = nf.route_id
    -- 0125: where she is NOW — her position's verdict (voyage.where_now), not the sweep's last write.
    cross join lateral voyage.where_now(f.id) w
    left join public.nations nn on nn.id = p.nation_id
    left join public.ports po on po.id = w.port_id
    left join public.sea_reaches rs on rs.port_id = w.port_id
$h$),
('world.sea_roster(timestamptz)', 5,
$h$                  where v2.fleet_id = f.id and v2.status = 'SAILING' and v2.departed_at >= p_since);
$h$,
$h$                  where v2.fleet_id = f.id and v2.status = 'SAILING' and v2.departed_at >= p_since)
      -- 0125: or her passage's arrival MOVED — a delaying event recorded since p_since.
      or exists (select 1 from public.voyages v3 join public.voyage_events ve on ve.voyage_id = v3.id
                  where v3.fleet_id = f.id and v3.status = 'SAILING' and ve.resolved_at >= p_since
                    and coalesce((ve.payload->>'delay_hours')::numeric, 0) <> 0);
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
$h$                     'voyage', (select world.voyage_view(v.id, false) from public.voyages v
                                 where v.id = w.voyage_id),
$h$),
('world.port_merchants(uuid)', 4,
$h$              left join public.ports po on po.id = f.port_id
              left join public.sea_reaches rs on rs.port_id = f.port_id
$h$,
$h$              -- 0125: where she is NOW — her position's verdict (voyage.where_now).
              cross join lateral voyage.where_now(f.id) w
              left join public.ports po on po.id = w.port_id
              left join public.sea_reaches rs on rs.port_id = w.port_id
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
  -- 0125: where she is NOW — her position's verdict (voyage.where_now), not the sweep's last write.
  select * into w from voyage.where_now(f.id);
  f.status  := w.status;
  f.port_id := w.port_id;
  select * into p from public.players where id = f.player_id;
$h$),
('world.npc_fleet_card(uuid)', 3,
$h$                  where v.fleet_id = f.id and v.status = 'SAILING')),
$h$,
$h$                  where v.id = w.voyage_id)),
$h$),
-- public.tick_arrivals
('public.tick_arrivals(timestamptz)', 1,
$h$  v_days    int := 0;
begin
$h$,
$h$  v_days    int := 0;
  -- 0125: a run's wall-clock budget; what is left is the next run's (the job runs every 15 s).
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

select pg_temp.recut_0125(fn) from (values ('world.sea_roster(timestamptz)'), ('world.port_merchants(uuid)'),
                                           ('world.npc_fleet_card(uuid)'), ('public.tick_arrivals(timestamptz)')) x(fn);

-- ── 6. THE CADENCE ─────────────────────────────────────────────────────────────────────────────
do $$
begin
  if to_regclass('cron.job') is null then
    raise notice '0125: no pg_cron here (PGlite) — the arrivals cadence is not scheduled in this database';
    return;
  end if;
  perform cron.alter_job(j.jobid, schedule := '15 seconds')
     from cron.job j where j.jobname = 'byeharu-voyage:arrivals';
end $$;

-- ── 7. THE SELF-ASSERT ─────────────────────────────────────────────────────────────────────────
do $$
declare
  c_reads   constant text[] := array['world.sea_roster(timestamptz)', 'world.port_merchants(uuid)',
                                     'world.npc_fleet_card(uuid)', 'public.tick_arrivals(timestamptz)'];
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
  v_eta     timestamptz;
  v_rows    jsonb;
  v_row     jsonb;
  v_card    jsonb;
  v_pm      jsonb;
  v_t0      timestamptz;
  v_ms_where numeric;
  v_ms_new  numeric;
  v_ms_old  numeric;
  v_sailing int;
  v_cron    text;
  v_msg     text;
  i         int;
begin
  -- (a) POSTURE: reads still stable (they write nothing), ACLs unmoved; the helpers server-only;
  --     no new entry point; no client write; the knob is this file's.
  for v_fn in select unnest(c_reads) loop
    if (select p.provolatile from pg_proc p where p.oid = v_fn::regprocedure)
       is distinct from (select vol from defs_before_0125 where fn = v_fn) then
      raise exception '0125 self-assert FAIL: the volatility of % moved', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0125 where fn = v_fn) then
      raise exception '0125 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;
  if has_function_privilege('anon', 'voyage.arrived(uuid, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'voyage.arrived(uuid, timestamptz)', 'execute')
     or has_function_privilege('anon', 'voyage.where_now(uuid, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'voyage.where_now(uuid, timestamptz)', 'execute') then
    raise exception '0125 self-assert FAIL: voyage.arrived or voyage.where_now is client-callable';
  end if;
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

  -- (b) ONE AUTHORITY. Each body reverses to its pre-image hunk by hunk, each hunk once; the three
  --     reads each ask voyage.where_now once and no longer read the SAILING voyage themselves;
  --     voyage.settle and voyage.progress_nm are their pre-images (0125 adds no mover).
  for v_fn in select unnest(c_reads) loop
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
    if v_fn <> 'public.tick_arrivals(timestamptz)'
       and ((length(v_def) - length(replace(v_def, 'voyage.where_now(', ''))) / length('voyage.where_now(') <> 1
            or strpos(v_def, 'v.fleet_id = f.id and v.status = ''SAILING''') > 0) then
      raise exception '0125 self-assert FAIL: % does not take where she is from voyage.where_now alone', v_fn;
    end if;
  end loop;
  foreach v_fn in array array['voyage.settle(uuid, timestamptz)', 'voyage.progress_nm(uuid, timestamptz)'] loop
    if replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '') <> (select def from defs_before_0125 where fn = v_fn) then
      raise exception '0125 self-assert FAIL: % was re-cut', v_fn;
    end if;
  end loop;
  if strpos(pg_get_functiondef('voyage.arrived(uuid, timestamptz)'::regprocedure), 'v.eta') > 0 then
    raise exception '0125 self-assert FAIL: voyage.arrived reads an eta';
  end if;

  -- (c) THE CADENCE, where there is a scheduler.
  if to_regclass('cron.job') is not null then
    execute 'select schedule from cron.job where jobname = ''byeharu-voyage:arrivals''' into v_cron;
    if v_cron is distinct from '15 seconds' then
      raise exception '0125 self-assert FAIL: byeharu-voyage:arrivals runs on "%", not every 15 seconds', v_cron;
    end if;
  end if;

  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');

    -- PROBES: three merchants AT SEA on their route for one of its harbours (the live world has
    -- hundreds; a world where none sails is topped up through the one start door), held FOR UPDATE
    -- so a live sweep passes them by.
    select coalesce(array_agg(x.fleet_id order by x.ord, x.fleet_id), '{}'), coalesce(array_agg(x.route_id order by x.ord, x.fleet_id), '{}')
      into v_subj, v_route
      from (select nf.fleet_id, nf.route_id, nf.roster_ord as ord
              from public.npc_fleets nf
              join public.voyages v on v.fleet_id = nf.fleet_id and v.status = 'SAILING'
              join public.ports po on po.id = v.dest_port_id and po.kind = 'HARBOUR'
             where nf.route_id is not null and v.eta > now() + interval '5 minutes'
               and exists (select 1 from public.standing_route_stops st where st.route_id = nf.route_id and st.port_id = v.dest_port_id)
             order by nf.roster_ord, nf.fleet_id limit 3) x;
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
              order by nf.roster_ord, nf.fleet_id limit 6 loop
      exit when coalesce(array_length(v_subj, 1), 0) >= 3;
      perform cmd.standing_route_assign_for(r.player_id, r.route_id, r.fleet_id);
      if exists (select 1 from public.voyages v where v.fleet_id = r.fleet_id and v.status = 'SAILING') then
        v_subj := v_subj || r.fleet_id;
        v_route := v_route || r.route_id;
      end if;
    end loop;
    select array_agg(v.id order by k), array_agg(v.dest_port_id order by k) into v_vid, v_dest
      from unnest(v_subj) with ordinality s(fid, k)
      join public.voyages v on v.fleet_id = s.fid and v.status = 'SAILING';
    if coalesce(array_length(v_vid, 1), 0) <> 3 then
      raise exception '0125 self-assert FAIL: three merchants at sea to probe were not found (%)', coalesce(array_length(v_vid, 1), 0);
    end if;
    perform 1 from public.voyages where id = any(v_vid) for update;

    -- (d) THE MAP AND THE QUAY AGREE ON THE INSTANT, over every merchant at sea (the world as
    --     found, the probes among them): the position reaches the end exactly at the served eta (the client's placement runs
    --     linearly to it), not a second before.
    select count(*), count(*) filter (where not voyage.arrived(v.id, v.eta + interval '1 millisecond') or voyage.arrived(v.id, v.eta - interval '1 second'))
      into v_sailing, v_bad
      from public.voyages v join public.fleets f on f.id = v.fleet_id
      join public.players p on p.id = f.player_id and p.is_npc
     where v.status = 'SAILING' and v.dest_port_id is not null;
    if v_bad > 0 or v_sailing < 3 then
      raise exception '0125 self-assert FAIL: % of % merchant passages reach the end of their path off their served eta', v_bad, v_sailing;
    end if;

    -- (e) PARITY, nobody arrived: with the three at sea (not yet at their harbours) every read is its
    --     pre-image to the byte — asked twice at most, as another job may commit between a pair.
    for i in 1 .. 2 loop
      v_n := (world.npc_fleet_card(v_subj[1]) is distinct from pg_temp.card_before_0125(v_subj[1]))::int
           + (world.port_merchants(v_dest[1]) is distinct from pg_temp.port_merchants_before_0125(v_dest[1]))::int
           + (world.sea_roster(now() - interval '15 seconds') is distinct from pg_temp.sea_roster_before_0125(now() - interval '15 seconds'))::int
           + (case when exists (select 1 from public.voyages v join public.fleets f on f.id = v.fleet_id
                                  join public.players p on p.id = f.player_id and p.is_npc
                                 where v.status = 'SAILING' and voyage.arrived(v.id))
                   then 0   -- on a live world some merchant is always arriving; the full read differs for her alone
                   else (world.sea_roster(null) is distinct from pg_temp.sea_roster_before_0125(null))::int end);
      exit when v_n = 0;
    end loop;
    if v_n <> 0 then
      raise exception '0125 self-assert FAIL: % read(s) differ from their pre-image while nobody probed has arrived', v_n;
    end if;

    -- (f) SHE IS IN PORT THE INSTANT HER POSITION SAYS SO — nothing written. Each passage REWOUND whole
    --     (departed_at and eta back together, proof 12's rewind) so her position has reached the end.
    update public.voyages v set departed_at = v.departed_at - (v.eta - now()) - interval '1 minute',
                                eta = now() - interval '1 minute'
     where v.id = any(v_vid);
    v_t0 := clock_timestamp();
    select jsonb_agg(to_jsonb(w)) into v_rows from unnest(v_subj) s(fid), voyage.where_now(s.fid) w;
    v_ms_where := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 2);
    v_rows := world.sea_roster(null);
    v_card := world.npc_fleet_card(v_subj[1]);
    execute 'set local role authenticated';
    v_pm := world.port_merchants(v_dest[1]);
    execute 'reset role';
    select x into v_row from jsonb_array_elements(v_rows->'fleets') x where x->>'id' = v_subj[1]::text;
    if not voyage.arrived(v_vid[1])
       or v_row->>'status' <> 'DOCKED' or v_row->>'port' <> (select code from public.ports where id = v_dest[1])
       or jsonb_typeof(v_row->'voyage') <> 'null'
       or v_row->'roadstead' <> (select jsonb_build_array(rs.roadstead_lat, rs.roadstead_lon) from public.sea_reaches rs where rs.port_id = v_dest[1])
       or v_card->'fleet'->>'status' <> 'DOCKED' or v_card->'fleet'->>'port' <> v_row->>'port'
       or jsonb_typeof(v_card->'fleet'->'voyage') <> 'null'
       or (select m->>'status' from jsonb_array_elements(v_pm->'merchants') m where m->>'id' = v_subj[1]::text) <> 'DOCKED'
       or (select m->>'port' from jsonb_array_elements(v_pm->'merchants') m where m->>'id' = v_subj[1]::text) <> v_row->>'port'
       or (select status from public.voyages where id = v_vid[1]) <> 'SAILING'
       or (select status from public.fleets where id = v_subj[1]) <> 'SAILING' then
      raise exception '0125 self-assert FAIL: arrived by her position, she is not in port on every read (or a read wrote): roster %, card %',
        v_row, v_card->'fleet';
    end if;

    -- (g) A DELAY KEEPS HER AT SEA, and the map hears of it. Probe B arrived the same way; then a CALM
    --     is RECORDED on a day already behind her (the way voyage.settle records one) and
    --     voyage.recompute_eta — THE eta author — re-derives her eta. Her position falls short of the
    --     end; every read shows her at sea, bound for the same harbour, with the served eta at the
    --     instant her position will reach it; the roster's delta carries her.
    if not voyage.arrived(v_vid[2]) then
      raise exception '0125 self-assert FAIL: the second probe did not arrive by her position';
    end if;
    update public.standing_routes set updated_at = now() - interval '1 hour' where id = v_route[2];
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    values (v_vid[2], 1, 'CALM', jsonb_build_object('delay_hours', 48, 'short_rations', false, 'wages', 0), now())
    on conflict (voyage_id, day_index) do update set kind = 'CALM',
      payload = public.voyage_events.payload || jsonb_build_object('delay_hours',
                 coalesce((public.voyage_events.payload->>'delay_hours')::numeric, 0) + 48),
      resolved_at = now();
    v_eta := voyage.recompute_eta(v_vid[2]);
    v_rows := world.sea_roster(now() - interval '15 seconds');
    select x into v_row from jsonb_array_elements(v_rows->'fleets') x where x->>'id' = v_subj[2]::text;
    v_card := world.npc_fleet_card(v_subj[2]);
    if voyage.arrived(v_vid[2]) or v_eta <= now()
       or not voyage.arrived(v_vid[2], v_eta + interval '1 millisecond') or voyage.arrived(v_vid[2], v_eta - interval '1 second')
       or v_row is null or v_row->>'status' <> 'SAILING' or (v_row->'voyage'->>'eta')::timestamptz <> v_eta
       or v_row->'voyage'->>'to' <> (select code from public.ports where id = v_dest[2])
       or v_card->'fleet'->>'status' <> 'SAILING' or (v_card->'fleet'->'voyage'->>'eta')::timestamptz <> v_eta then
      raise exception '0125 self-assert FAIL: a recorded delay did not keep her at sea on every read: eta %, roster %', v_eta, v_row;
    end if;

    -- (h) THE SWEEP STILL DOCKS HER, and its budget bites: at 0 ms a run settles nobody; the sweep's
    --     own settle then docks the arrived probe C.
    update public.world_config set value = to_jsonb(0) where key = 'arrivals_tick_budget_ms';
    perform public.tick_arrivals();
    if (select status from public.voyages where id = v_vid[3]) <> 'SAILING' then
      raise exception '0125 self-assert FAIL: a 0 ms sweep still settled a merchant';
    end if;
    update public.world_config set value = to_jsonb(10000) where key = 'arrivals_tick_budget_ms';
    -- (her rewound passage's sea-days are all resolved now; hazards off, as proof 12 rewinds, so a
    --  day's weather cannot — rightly — keep her at sea and make this probe about something else)
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    perform voyage.settle(v_subj[3]);
    if (select status from public.voyages where id = v_vid[3]) <> 'ARRIVED' then
      raise exception '0125 self-assert FAIL: the sweep''s settle did not dock an arrived merchant';
    end if;

    -- (i) COST: where_now over every merchant (the full roster asks it once each), and the full
    --     roster read, new body against old.
    v_t0 := clock_timestamp();
    perform count(*) from public.fleets f join public.players p on p.id = f.player_id and p.is_npc,
                          voyage.where_now(f.id) w;
    v_ms_where := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1);
    v_t0 := clock_timestamp(); perform world.sea_roster(null);
    v_ms_new := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1);
    v_t0 := clock_timestamp(); perform pg_temp.sea_roster_before_0125(null);
    v_ms_old := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1);

    raise exception 'ROLLBACK_0125|%|%|%|%', v_sailing, v_ms_where, v_ms_new, v_ms_old;
  exception when others then
    if sqlerrm not like 'ROLLBACK_0125|%' then raise; end if;
    v_msg := sqlerrm;
  end;
  if public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on
     or public.wc_int('arrivals_tick_budget_ms') <> 10000 or current_user <> session_user
     or exists (select 1 from public.voyages v where v.id = any(v_vid) and v.eta = now() - interval '1 minute') then
    raise exception '0125 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0125 self-assert ok: A MERCHANT DOCKS THE MOMENT SHE ARRIVES. sea_roster, port_merchants and npc_fleet_card take status / port / roadstead / voyage from voyage.where_now alone, reverse to their pre-images hunk by hunk, stay stable, ACLs unmoved; voyage.arrived reads no eta and voyage.settle / progress_nm are untouched; both helpers server-only; no new entry point, no client write. Over % merchant passage(s) at sea the position reaches the end exactly at the served eta. With nobody arrived every read is its pre-image. Arrived by her position, a merchant is DOCKED at her harbour''s roadstead on the roster, the card and the harbour''s read (as authenticated) with nothing written; a recorded CALM keeps her at sea on every read with the served eta at the instant her position reaches the end, and the roster delta carries her. The sweep: % ; a 0 ms budget settles nobody; its settle docks the arrived one. where_now over every merchant % ms; the full roster % ms (before: % ms). Rolled back.',
    split_part(v_msg, '|', 2), coalesce(v_cron, 'no scheduler here'), split_part(v_msg, '|', 3),
    split_part(v_msg, '|', 4), split_part(v_msg, '|', 5);
end $$;
