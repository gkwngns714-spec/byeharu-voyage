-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0239 — THE QUAY IS READ EVERY SECOND  (the arrivals job runs every second and reads only what is due)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, row 224 (2026-10-26) ─────────────────────────────────────────────────────────────
--   Money must move every 1 second, for real. And: "change to 1 sec, compare how much server cost it needs".
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- * cron byeharu-voyage:arrivals runs `select public.tick_arrivals()` on '15 seconds' (0125). Every coin an
--   arrival, a sea-day's wage or a sale moves is written with the instant its run began, so the money books
--   take 60-90 rows at a time, every 15 s (prod 2026-10-26: 72 ledger + 46 city-flow rows a run).
-- * public.tick_arrivals' candidate scan (0169) evaluates voyage.day_end_from over voyage.delay_before_day for
--   EVERY voyage at sea, every run, to find the ~10 that are due: prod 2026-10-26, a pure read of the same
--   predicate, 71 ms over 774 voyages at sea (9,726 buffers). At one run a second that is 256 s of database an
--   hour spent finding nothing new.
-- * public.npc_ask_waiting reads public.npc_waiting_queue — the whole merchant roster through
--   public.npc_tend_roster() — every run (prod 12 ms) for merchants due every ~10 minutes.
-- * The yard release and the route wake scan public.fleets and public.standing_routes with no index on their
--   due instants (`busy_until`, `hold_until`).
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- (1) voyages.due_at — a voyage's next due instant, KEPT ON THE ROW: the end of her next unsettled sea-day, or
--     her eta if that is sooner — exactly `voyage.day_end_from(eta, departed_at, last_settled_day + 1,
--     voyage.delay_before_day(id, last_settled_day + 1), time_compression)`, the expression 0169 put in the
--     scan (day_end_from is least(eta, …), so `due_at <= now` IS the old `eta <= now or day_end … <= now`).
--     ONE WRITER: the BEFORE trigger voyage.keep_due_at, on every insert and on every update of the columns
--     the expression reads (status, eta, departed_at, last_settled_day, delay_hours — and due_at itself, so
--     nobody can hand-set it). Null unless SAILING. A sea-day's delay lands in voyage_events before settle
--     moves last_settled_day, so the sum it reads is the one the old scan read. The four writers of public.voyages
--     (voyage.depart, voyage.settle, voyage.recompute_eta, cmd.divert) are untouched: the trigger sees them all.
--     If time_compression ever moves, voyage.due_at_follows_the_clock re-keeps every voyage at sea.
--     Partial index voyages_due_at (due_at) WHERE status = 'SAILING'.
-- (2) public.tick_arrivals reads `v.due_at <= p_now` through that index (two hunks; the knob it no longer
--     needs leaves its declaration). Order, FOR UPDATE SKIP LOCKED, the budget, the settle: unchanged.
-- (3) The yard release and the route wake get partial indexes on their due instants (fleets_repair_due,
--     standing_routes_hold_due); their queries are unchanged.
-- (4) The waiting merchants are asked once every npc_ask_every_seconds (15, new knob) of the clock, not every
--     run: public.npc_ask_slot(p_now) = floor(epoch(p_now)) mod 15 = 0. A slot a run misses (a run that began
--     a second late) is the next slot's; a waiting merchant is due every ~10 minutes, so the delay is nothing.
--     Arithmetic on the instant only — no time of day, no state.
-- (5) Cron: byeharu-voyage:arrivals '15 seconds' → '1 seconds' (pg_cron 1.6.4 on prod; `[1-59] seconds`).
--     pg_cron runs ONE instance of a job at a time: a run due while one is running is queued and starts when
--     it ends (pg_cron README), and the scans already take their rows FOR UPDATE SKIP LOCKED. The active flag
--     is kept as found (0078: migrations define, public.wind_the_clock() starts — it only flips `active`, so
--     it starts the job on '1 seconds').
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Change what a run DOES to a fleet that is due: voyage.settle, cmd.advance, the route core, the merchants'
-- tend, the dock fee and port time (0237), the budget (arrivals_tick_budget_ms 10 000) — not one line. Change
-- any client grant, entry point or read; the client is untouched (its 7.5-s read beat is derived from
-- time_compression, not from this job; the Money log asks every second already).
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
--   select cron.alter_job((select jobid from cron.job where jobname = 'byeharu-voyage:arrivals'),
--                         schedule := '15 seconds');                    -- the cadence, one statement
-- and a forward migration restoring tick_arrivals: its OLD hunks are in this file (hunks_0239.old) and the
-- self-assert proves the live body reverses to its pre-image by them. The column, trigger and indexes are
-- additive and harmless left in place.
--
-- SUPERSEDES: public.tick_arrivals (0182 as cut by 0237) — hunks sliced from the LIVE body (LF-normalised),
-- each asserted to occur exactly once. Self-assert: own probe rows only, rolled back.
-- VERSION: 0239 = 0238 + 1.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.port_time_wake(timestamptz,timestamptz,uuid)') is null
     or to_regprocedure('public.npc_ask_waiting(timestamptz,timestamptz)') is null
     or to_regprocedure('voyage.day_end_from(timestamptz,timestamptz,integer,numeric,numeric)') is null then
    raise exception '0239 refuses: 0169 / 0182 / 0237 is not in this world';
  end if;
  if exists (select 1 from pg_attribute where attrelid = 'public.voyages'::regclass and attname = 'due_at' and not attisdropped) then
    raise exception '0239 refuses: voyages.due_at already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0239(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGE (LF-normalised) ────────────────────────────────────────────────────────────
create temp table defs_before_0239 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_arrivals(timestamptz)')) f(fn);

create temp table before_0239 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- the old body, kept for the self-assert's comparison run
do $$
begin
  if pg_temp.occurs_0239((select def from defs_before_0239), 'FUNCTION public.tick_arrivals(') <> 1 then
    raise exception '0239 self-assert FAIL: tick_arrivals'' definition does not name itself once';
  end if;
  execute replace((select def from defs_before_0239), 'FUNCTION public.tick_arrivals(', 'FUNCTION pg_temp.tick_arrivals_old_0239(');
end $$;

-- ── 1. THE DUE INSTANT, KEPT ON THE ROW ─────────────────────────────────────────────────────────
alter table public.voyages add column due_at timestamptz;
comment on column public.voyages.due_at is
  '0239: her next due instant — the end of her next unsettled sea-day, or her eta if sooner (voyage.day_end_from over voyage.delay_before_day). One writer: the trigger voyage.keep_due_at. Null unless SAILING. public.tick_arrivals reads only voyages whose due_at has passed (index voyages_due_at).';

create function voyage.keep_due_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
-- 0239: the ONE writer of voyages.due_at — the expression public.tick_arrivals' scan evaluated per voyage per run
-- since 0169, evaluated once per write of a column it reads instead.
begin
  new.due_at := case when new.status = 'SAILING' then
                  voyage.day_end_from(new.eta, new.departed_at, new.last_settled_day + 1,
                                      voyage.delay_before_day(new.id, new.last_settled_day + 1),
                                      public.wc_num('time_compression')) end;
  return new;
end $$;
comment on function voyage.keep_due_at() is
  '0239: keeps voyages.due_at (BEFORE INSERT / UPDATE OF status, eta, departed_at, last_settled_day, delay_hours, due_at). Server-only.';
revoke all on function voyage.keep_due_at() from public, anon, authenticated;

create trigger voyages_keep_due_at
  before insert or update of status, eta, departed_at, last_settled_day, delay_hours, due_at on public.voyages
  for each row execute function voyage.keep_due_at();

create function voyage.due_at_follows_the_clock()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
-- 0239: the due instant reads time_compression; when the knob moves, every voyage at sea is re-kept (the trigger
-- above recomputes due_at on any write of it).
begin
  update public.voyages set due_at = null where status = 'SAILING';
  return null;
end $$;
comment on function voyage.due_at_follows_the_clock() is
  '0239: re-keeps voyages.due_at for every voyage at sea when world_config.time_compression changes. Server-only.';
revoke all on function voyage.due_at_follows_the_clock() from public, anon, authenticated;

create trigger world_config_time_compression_keeps_due_at
  after update of value on public.world_config
  for each row when (new.key = 'time_compression' and new.value is distinct from old.value)
  execute function voyage.due_at_follows_the_clock();

update public.voyages set due_at = null where status = 'SAILING';   -- the backfill: the trigger keeps each one
create index voyages_due_at on public.voyages (due_at) where status = 'SAILING';

-- ── 2. THE OTHER DUE INSTANTS, INDEXED ──────────────────────────────────────────────────────────
create index fleets_repair_due on public.fleets (busy_until) where status = 'REPAIRING';
create index standing_routes_hold_due on public.standing_routes (hold_until)
  where hold_until is not null and paused_reason is null;

-- ── 3. THE WAITING MERCHANTS' SLOT ──────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('npc_ask_every_seconds', to_jsonb(15),
   '0239: the arrivals job (every second) asks the waiting merchants (public.npc_ask_waiting) once every this many seconds of the clock — public.npc_ask_slot. 1 = every run.');

create function public.npc_ask_slot(p_now timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (floor(extract(epoch from p_now))::bigint % greatest(1, public.wc_int('npc_ask_every_seconds'))) = 0
$$;
comment on function public.npc_ask_slot(timestamptz) is
  '0239: true on the seconds the arrivals job asks the waiting merchants (epoch second mod npc_ask_every_seconds = 0). Server-only.';
revoke all on function public.npc_ask_slot(timestamptz) from public, anon, authenticated;

-- ── 4. THE SCAN AND THE ASK (public.tick_arrivals) ──────────────────────────────────────────────
create temp table hunks_0239 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0239 (fn, n, old, new) values
('public.tick_arrivals(timestamptz)', 1,
$h$  -- the next run's (the job runs every 15 s).
$h$,
$h$  -- the next run's (the job runs every second since 0239; it was every 15 s).
$h$),
('public.tick_arrivals(timestamptz)', 2,
$h$  v_k       numeric := public.wc_num('time_compression');   -- 0169: the candidate scan's knob, once a run
$h$,
$h$  -- 0239: the candidate scan reads voyages.due_at; the knob is read where that is kept (voyage.keep_due_at)
$h$),
('public.tick_arrivals(timestamptz)', 3,
$h$              -- 0169: voyage.day_ends_at(v.id, n) composed from the row in hand (voyage.day_end_from over
              -- voyage.delay_before_day), the knob read once a run — the same test, one read a voyage
              and (v.eta <= p_now
                   or voyage.day_end_from(v.eta, v.departed_at, v.last_settled_day + 1,
                                          voyage.delay_before_day(v.id, v.last_settled_day + 1), v_k) <= p_now)
$h$,
$h$              -- 0239: her next due instant is kept on the row (voyages.due_at, voyage.keep_due_at: the same
              -- voyage.day_end_from over voyage.delay_before_day 0169 composed here) and indexed (voyages_due_at),
              -- so a run reads the voyages due and no other
              and v.due_at <= p_now
$h$),
('public.tick_arrivals(timestamptz)', 4,
$h$  begin
    v_asked := public.npc_ask_waiting(p_now, v_t0 + v_budget);
$h$,
$h$  -- 0239: once every npc_ask_every_seconds of the clock (public.npc_ask_slot), not every run — the queue reads
  -- the whole roster, and a waiting merchant is due every ~10 minutes.
  begin
    v_asked := case when public.npc_ask_slot(p_now) then public.npc_ask_waiting(p_now, v_t0 + v_budget)
                    else jsonb_build_object('asked', 0) end;
$h$);

create or replace function pg_temp.recut_0239(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0239 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0239 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0239(v_def, h.old);
    if v_n <> 1 then
      raise exception '0239 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0239(fn) from defs_before_0239 order by fn;

-- ── 5. THE CADENCE ──────────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0239: pg_cron is not installed here (PGlite) — the 1 s cadence is not scheduled in this database';
    return;
  end if;
  perform cron.alter_job(j.jobid, schedule := '1 seconds')
     from cron.job j where j.jobname = 'byeharu-voyage:arrivals';
  update public.world_config set description = description || ' 0239: the job runs every second; a run that ends early leaves nothing for the next to wait on.'
   where key = 'arrivals_tick_budget_ms';
end $$;

-- ── 6. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0239-4000-8000-000000000001';
  c_then   constant timestamptz := '2000-01-01 00:00:01+00';   -- the probe's clock: before every real due instant
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  v_lis    uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_fnc    uuid := (select p.id from public.ports p where p.code = 'FNC' and p.kind = 'HARBOUR');
  v_n      int;
  v_cron   text;
  v_c      jsonb;
begin
  select * into v_before from before_0239;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0239 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0239 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0239(v_def, v_h.new) <> 1 then
        raise exception '0239 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0239 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0239 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if position('v_k' in pg_get_functiondef('public.tick_arrivals(timestamptz)'::regprocedure)) > 0 then
    raise exception '0239 self-assert FAIL: tick_arrivals still names the knob it no longer reads';
  end if;
  if exists (select 1 from (values ('voyage.keep_due_at()'), ('voyage.due_at_follows_the_clock()'), ('public.npc_ask_slot(timestamptz)')) f(fn)
              where has_function_privilege('authenticated', f.fn, 'execute') or has_function_privilege('anon', f.fn, 'execute')) then
    raise exception '0239 self-assert FAIL: a client role can execute a server-only function';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0239 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0239 self-assert FAIL: a wall moved';
  end if;

  -- (b) THE KEPT INSTANT IS THE OLD SCAN'S EXPRESSION for every voyage at sea, and nothing else holds one
  select count(*) into v_n
    from public.voyages v
   where v.status = 'SAILING'
     and v.due_at is distinct from voyage.day_end_from(v.eta, v.departed_at, v.last_settled_day + 1,
                                                       voyage.delay_before_day(v.id, v.last_settled_day + 1),
                                                       public.wc_num('time_compression'));
  if v_n <> 0 then
    raise exception '0239 self-assert FAIL: % voyage(s) at sea keep a due_at that is not day_end_from of their next day', v_n;
  end if;
  if exists (select 1 from public.voyages v where v.status <> 'SAILING' and v.due_at is not null) then
    raise exception '0239 self-assert FAIL: a voyage not at sea keeps a due instant';
  end if;
  -- the index answers the scan
  if not exists (select 1 from pg_indexes where indexname = 'voyages_due_at')
     or not exists (select 1 from pg_indexes where indexname = 'fleets_repair_due')
     or not exists (select 1 from pg_indexes where indexname = 'standing_routes_hold_due') then
    raise exception '0239 self-assert FAIL: an index is missing';
  end if;

  -- (c) THE SLOT is arithmetic on the instant: the 15th seconds and no others
  if not public.npc_ask_slot('2000-01-01 00:00:00+00') or not public.npc_ask_slot('2000-01-01 00:00:15.9+00')
     or public.npc_ask_slot('2000-01-01 00:00:01+00') or public.npc_ask_slot('2000-01-01 00:00:14.99+00') then
    raise exception '0239 self-assert FAIL: npc_ask_slot is not floor(epoch) mod 15 = 0';
  end if;

  -- (d) THE CADENCE, where there is a scheduler
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute 'select schedule from cron.job where jobname = ''byeharu-voyage:arrivals''' into v_cron;
    if v_cron is distinct from '1 seconds' then
      raise exception '0239 self-assert FAIL: arrivals on "%", not "1 seconds"', v_cron;
    end if;
  end if;

  -- (e) A PROBE ARRIVAL SETTLES IN ONE RUN, AND NOTHING ELSE IS TOUCHED. A probe company sails Lisbon → Funchal;
  -- her passage is moved back whole into 1999, and one run is made at 2000-01-01 00:00:01 — an instant before every
  -- real voyage's, yard's, route's and port time's due instant, and not an ask slot — through the NEW body, then the
  -- same from the same state through the OLD body. Both must answer alike. Nothing else is touched: the run's own
  -- count of fleets it touched is 1 and of merchants asked 0, nothing else was due at that instant (asserted before the
  -- run), and every merchant's fleet and voyage at sea reads as before (a digest of their rows — the merchants, because
  -- the clock is stopped during a deploy and only a player's own read can move a player's fleet meanwhile). Rolled back.
  if v_lis is null or v_fnc is null then
    raise exception '0239 self-assert FAIL: no Lisbon or no Funchal';
  end if;
  begin
    declare
      v_p uuid; v_f uuid; v_voy uuid; v_course jsonb; v_days int;
      v_others0 text; v_others1 text; v_fleets0 text; v_fleets1 text;
      v_new jsonb; v_old jsonb; v_seen_new jsonb; v_seen_old jsonb;
    begin
      update public.world_config set value = '0'::jsonb where key = 'hazard_p_max';   -- a quiet passage
      perform set_config('request.jwt.claim.sub', c_uid::text, true);
      v_p := public.new_house(c_uid, 'Probe 0239', 'NLD', 'LIS');
      select f.id into v_f from public.fleets f where f.player_id = v_p;
      select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
        into v_course
        from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc;
      v_voy := (cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'path', v_course))->>'voyage_id')::uuid;
      if v_voy is null then
        raise exception using errcode = 'ZX239', message = jsonb_build_object('fail', 'no voyage')::text;
      end if;
      -- the departure kept her due instant: her first day's end
      if (select v.due_at is distinct from voyage.day_end_from(v.eta, v.departed_at, 1, 0, public.wc_num('time_compression'))
            from public.voyages v where v.id = v_voy) then
        raise exception using errcode = 'ZX239', message = jsonb_build_object('fail', 'departure due_at')::text;
      end if;
      -- her whole passage moved back so that she made Funchal at 1999-12-31 23:59 (its days keep their shape)
      update public.voyages vo
         set departed_at = vo.departed_at - (vo.eta - timestamptz '1999-12-31 23:59:00+00'), eta = timestamptz '1999-12-31 23:59:00+00'
       where vo.id = v_voy;
      v_days := voyage.total_days(v_voy);
      if (select v.due_at > c_then from public.voyages v where v.id = v_voy)
         or exists (select 1 from public.voyages v where v.status = 'SAILING' and v.id <> v_voy and v.due_at <= c_then)
         or exists (select 1 from public.fleets f where f.status = 'REPAIRING' and f.busy_until <= c_then)
         or exists (select 1 from public.standing_routes sr where sr.paused_reason is null and sr.hold_until <= c_then)
         or exists (select 1 from public.fleets f where f.ready_at <= c_then)
         or public.npc_ask_slot(c_then) then
        raise exception using errcode = 'ZX239', message = jsonb_build_object('fail', 'the probe is not alone in being due')::text;
      end if;
      select md5(string_agg(v.id::text || v.status || v.last_settled_day || v.eta || coalesce(v.due_at::text, ''), ',' order by v.id))
        into v_others0 from public.voyages v join public.fleets f on f.id = v.fleet_id join public.players pl on pl.id = f.player_id and pl.is_npc
         where v.status = 'SAILING';
      select md5(string_agg(f.id::text || f.status || coalesce(f.port_id::text, '') || f.version, ',' order by f.id))
        into v_fleets0 from public.fleets f join public.players pl on pl.id = f.player_id and pl.is_npc;

      -- ONE RUN, THE NEW BODY
      begin
        v_new := public.tick_arrivals(c_then);
        select md5(string_agg(v.id::text || v.status || v.last_settled_day || v.eta || coalesce(v.due_at::text, ''), ',' order by v.id))
          into v_others1 from public.voyages v join public.fleets f on f.id = v.fleet_id join public.players pl on pl.id = f.player_id and pl.is_npc
         where v.status = 'SAILING';
        select md5(string_agg(f.id::text || f.status || coalesce(f.port_id::text, '') || f.version, ',' order by f.id))
          into v_fleets1 from public.fleets f join public.players pl on pl.id = f.player_id and pl.is_npc;
        raise exception using errcode = 'ZY239', message = jsonb_build_object(
          'run', v_new - 'at',
          'voyage', (select jsonb_build_array(v.status, v.last_settled_day, v.due_at) from public.voyages v where v.id = v_voy),
          'fleet', (select jsonb_build_array(f.status, p.code) from public.fleets f left join public.ports p on p.id = f.port_id where f.id = v_f),
          'days', (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy),
          'others_same', v_others1 = v_others0, 'fleets_same', v_fleets1 = v_fleets0)::text;
      exception when sqlstate 'ZY239' then
        v_seen_new := sqlerrm::jsonb;
      end;
      -- ONE RUN, THE OLD BODY, from the same state
      begin
        v_old := pg_temp.tick_arrivals_old_0239(c_then);
        raise exception using errcode = 'ZY239', message = jsonb_build_object(
          'run', v_old - 'at',
          'voyage', (select jsonb_build_array(v.status, v.last_settled_day, v.due_at) from public.voyages v where v.id = v_voy),
          'fleet', (select jsonb_build_array(f.status, p.code) from public.fleets f left join public.ports p on p.id = f.port_id where f.id = v_f),
          'days', (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy))::text;
      exception when sqlstate 'ZY239' then
        v_seen_old := sqlerrm::jsonb;
      end;
      raise exception using errcode = 'ZX239', message = jsonb_build_object('new', v_seen_new, 'old', v_seen_old, 'total_days', v_days)::text;
    end;
  exception when sqlstate 'ZX239' then
    v_c := sqlerrm::jsonb;
  end;
  if v_c ? 'fail' then
    raise exception '0239 self-assert FAIL: the probe: %', v_c;
  end if;
  if (v_c->'new'->'run'->>'fleets_touched')::int <> 1
     or (v_c->'new'->'run'->>'days_resolved')::int <> (v_c->>'total_days')::int
     or (v_c->'new'->'run'->>'asked')::int <> 0
     or v_c->'new'->'voyage'->>0 <> 'ARRIVED' or v_c->'new'->'voyage'->2 <> 'null'::jsonb
     or v_c->'new'->'fleet' <> '["DOCKED", "FNC"]'::jsonb
     or not (v_c->'new'->>'others_same')::boolean or not (v_c->'new'->>'fleets_same')::boolean then
    raise exception '0239 self-assert FAIL: one run did not settle the probe''s arrival alone: %', v_c;
  end if;
  if ((v_c->'new') - 'others_same' - 'fleets_same') <> (v_c->'old') then
    raise exception '0239 self-assert FAIL: the new run and the old run answer differently: %', v_c;
  end if;

  -- (f) THE CLOCK KNOB MOVES → every voyage at sea is re-kept (rolled back)
  begin
    update public.world_config set value = to_jsonb(public.wc_num('time_compression') * 2) where key = 'time_compression';
    select count(*) into v_n
      from public.voyages v
     where v.status = 'SAILING'
       and v.due_at is distinct from voyage.day_end_from(v.eta, v.departed_at, v.last_settled_day + 1,
                                                         voyage.delay_before_day(v.id, v.last_settled_day + 1),
                                                         public.wc_num('time_compression'));
    raise exception using errcode = 'ZX239', message = v_n::text;
  exception when sqlstate 'ZX239' then
    v_n := sqlerrm::int;
  end;
  if v_n <> 0 then
    raise exception '0239 self-assert FAIL: % voyage(s) kept a stale due_at when time_compression moved', v_n;
  end if;

  raise notice '0239 self-assert ok: THE QUAY IS READ EVERY SECOND. voyages.due_at = day_end_from of her next day for every voyage at sea (kept by one trigger, re-kept when the clock knob moves), null otherwise; tick_arrivals reads due_at through voyages_due_at (two hunks + two comments), reverses to its pre-image, ACL unmoved; the waiting merchants asked on the 15th seconds only; yard and route wakes indexed; arrivals on "%". PROBE: Lisbon → Funchal moved into 1999, one run at 2000-01-01 00:00:01 settled her % day(s) and docked her (touched 1, asked 0), nothing else due then, every merchant''s fleet and voyage at sea unchanged; the old body answered the same from the same state. Rolled back.',
    coalesce(v_cron, 'no scheduler here'), v_c->>'total_days';
end $$;
