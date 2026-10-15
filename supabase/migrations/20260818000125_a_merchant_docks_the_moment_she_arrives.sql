-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0125 — A MERCHANT DOCKS THE MOMENT SHE ARRIVES  (docs/MERCHANTS_DOCK_ON_ARRIVAL.md, step M1)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
--   "the merchant npc should also be like me."  (2026-10-15)
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- A player's fleet docks on the first read after her eta: world.fleets() settles every one of the
-- house's fleets through voyage.settle before it answers (0009:161-165). A merchant docked only when
-- the minute sweep reached her (public.tick_arrivals, 0010:54-87, cron `* * * * *`), because the four
-- reads that report her were declared STABLE and so could settle nothing:
--   world.sea_roster (0118:38), world.port_merchants (0113:70-71), world.npc_fleet_card (0099:241),
--   world.fleet_trades (0121:214).
-- At 960x that left an arrived merchant lying off the quay as a SAILING hull for up to a minute and
-- a half of real time — sixteen to twenty-eight voyage-hours. The 2026-10-08 decision "the map read
-- does not settle" (N13) is revisited in the plan's §7: what stands of it is "no viewer WAITS".
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) Five knobs (world_config): merchant_settle_on_read (THE switch, lit), merchant_settle_per_read
--     12, merchant_wake_per_read 2, merchant_settle_budget_ms 1500, merchant_settle_lock_ms 500.
-- (2) public.merchant_settle_on_read() — the one reader of the switch. Server-only.
-- (3) voyage.settle_due(fleets, now, limit, wake_max, budget_ms) — THE MERCHANT CATCH-UP ON READ.
--     A CALLER of voyage.settle, never an author: it picks the merchants that are due — arrivals
--     (eta passed, oldest first, the sweep's order) and rests that are over (the sweep's wake
--     predicate) — locks each one `for update skip locked` exactly as the sweep does, and settles it
--     through voyage.settle in its own subtransaction under a short lock_timeout. Arrival is judged
--     inside voyage.settle; the dock, the lap close, the rest and the next lap inside cmd.advance →
--     cmd.run_standing_route. Nothing is re-derived here. Sea-day boundaries are NOT chased (a read
--     that chased them would find hundreds due every beat — N13's objection); only arrivals and wakes.
--     Bounded: a count, a wake sub-cap, a wall-clock budget checked before each settle. A held row is
--     `busy`, never a wait; a settle that fails is rolled back alone and counted `failed`.
-- (4) The four reads become VOLATILE (the shape world.fleets() has had since 0009) and call
--     voyage.settle_due FIRST, on exactly the merchants they report, after their own dark/E_NOT_FOUND
--     gate, then answer as before. world.fleet_trades settles a MERCHANT only: a player's own fleet is
--     settled by world.fleets(), its one settling read.
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Touch voyage.settle, cmd.advance, cmd.run_standing_route, public.tick_arrivals or the cron (the
-- sweep stays, unchanged, the fallback for merchants nobody is looking at); world.sea_traffic or
-- world.route_board; any table; any grant; the client. No key is added to any read's answer.
-- world.port_merchants stays a `language sql` function: a volatile SQL function runs its statements
-- in order with each one seeing the last, so the settle is one statement placed before its select —
-- a slice, not a restatement (the plan's §3.2 named a plpgsql restatement; the slice is less text and
-- the same one authority).
--
-- ── COST (bounds, by the plan's measurements; this file's receipt prints the PGlite numbers) ────
-- Per settle: an arrival ~0.06-0.1 s, a home arrival ~0.01 s, a wake (the lap-start plan) 0.5-1.3 s
-- (docs/DEV_LOG.md:8959-8960). Defaults 12 arrivals + 2 wakes inside a 1,500 ms budget checked before
-- each settle: the worst overrun is one wake, so the worst read is ~3 s against the 8 s
-- `authenticated` statement timeout (0117:10-14). A card or a trade history settles at most one fleet.
-- MEASURED on prod, 2026-10-15, this file's self-assert inside begin…rollback (on 0122 + 0124): the
-- harbour's read docking an arrival 521 ms, the roster delta 295 ms, the card 948 ms; a trade history
-- settling one WHOLE rewound passage 3.9 s (every sea-day of the voyage at once — a probe artefact: in
-- play the sweep resolves the days and a read meets at most the last one); a wake through the card
-- (a halted merchant's lap-start plan) 4.1 s. The budget is checked BEFORE each settle, so the worst
-- read is budget + one wake + the read itself, ~6 s against 8 s — merchant_settle_budget_ms is the
-- knob to lower if pg_stat_statements shows a read near it.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- (1) Instant: update world_config set value = 'false' where key = 'merchant_settle_on_read' — every
--     read is then its pre-image to the byte (asserted below, (c)). (2) A forward migration: every OLD
--     hunk is in this file verbatim (hunks_0125.old) and the self-assert proves each live body reverses
--     to its pre-image by them; then drop voyage.settle_due and public.merchant_settle_on_read.
--
-- SUPERSEDES: world.sea_roster (0118), world.port_merchants (0113), world.npc_fleet_card (0099 as cut
-- by 0124), world.fleet_trades (0121) — hunks sliced from the LIVE bodies (LF-normalised), each
-- asserted to occur exactly once. The npc_fleet_card hunk sits at the E_NOT_FOUND gate, clear of the
-- 'refounded_at' line 0123 slices and of the 'ships' line 0124 cut.
-- Self-asserts hold AS FOUND; every probe rolls back. No table, no client grant, no new entry point.
-- VERSION: 0125, stacked on 0124 (one_ship_one_builder).

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0125 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol
  from unnest(array['world.sea_roster(timestamptz)', 'world.port_merchants(uuid)',
                    'world.npc_fleet_card(uuid)', 'world.fleet_trades(uuid)',
                    'voyage.settle(uuid, timestamptz)', 'public.tick_arrivals(timestamptz)']) f(fn);

create temp table before_0125 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not like 'pg_temp%' and p.prosrc like '%voyage.settle(%') as settle_callers,
       (select count(*) from public.world_config
         where key in ('merchant_settle_on_read', 'merchant_settle_per_read', 'merchant_wake_per_read',
                       'merchant_settle_budget_ms', 'merchant_settle_lock_ms')) as knobs_found;

-- The four reads as they were, callable under pg_temp for the parity asserts.
do $$
begin
  execute replace((select def from defs_before_0125 where fn = 'world.sea_roster(timestamptz)'),
    'CREATE OR REPLACE FUNCTION world.sea_roster(', 'CREATE OR REPLACE FUNCTION pg_temp.sea_roster_before_0125(');
  execute replace((select def from defs_before_0125 where fn = 'world.port_merchants(uuid)'),
    'CREATE OR REPLACE FUNCTION world.port_merchants(', 'CREATE OR REPLACE FUNCTION pg_temp.port_merchants_before_0125(');
  execute replace((select def from defs_before_0125 where fn = 'world.npc_fleet_card(uuid)'),
    'CREATE OR REPLACE FUNCTION world.npc_fleet_card(', 'CREATE OR REPLACE FUNCTION pg_temp.card_before_0125(');
  execute replace((select def from defs_before_0125 where fn = 'world.fleet_trades(uuid)'),
    'CREATE OR REPLACE FUNCTION world.fleet_trades(', 'CREATE OR REPLACE FUNCTION pg_temp.trades_before_0125(');
end $$;

-- ── 2. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('merchant_settle_on_read', 'true'::jsonb,
   '0125: THE switch. True: the four merchant reads (sea_roster, port_merchants, npc_fleet_card, '
   'fleet_trades) settle the merchants they report through voyage.settle_due before answering, so a '
   'merchant docks on the first read after her eta, as a player''s fleet does. False: every one of '
   'those reads is its pre-0125 body to the byte and the minute sweep alone docks merchants. One '
   'reader: public.merchant_settle_on_read().'),
  ('merchant_settle_per_read', to_jsonb(12),
   '0125: the most arrivals one merchant read may settle (eta ascending, the sweep''s order). '
   'voyage.settle_due.'),
  ('merchant_wake_per_read', to_jsonb(2),
   '0125: the most rested merchants one read may put back to sea (each runs the lap-start plan, '
   '0.5-1.3 s). voyage.settle_due.'),
  ('merchant_settle_budget_ms', to_jsonb(1500),
   '0125: the wall-clock budget of one read''s settling, in ms, checked BEFORE each settle — the '
   'overrun is at most one settle. 0 settles nothing. voyage.settle_due.'),
  ('merchant_settle_lock_ms', to_jsonb(500),
   '0125: lock_timeout (ms) while a read settles a merchant. A row it cannot lock in time is counted '
   'busy and left to the sweep — a player never waits on it. voyage.settle_due.')
on conflict (key) do nothing;

-- ── 3. THE SWITCH'S ONE READER ─────────────────────────────────────────────────────────────────
create or replace function public.merchant_settle_on_read()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.wc('merchant_settle_on_read') = 'true'::jsonb
$$;
comment on function public.merchant_settle_on_read() is
  '0125: the one reader of world_config.merchant_settle_on_read. Server-only.';
revoke all on function public.merchant_settle_on_read() from public, anon, authenticated;

-- ── 4. THE MERCHANT CATCH-UP ON READ ───────────────────────────────────────────────────────────
create or replace function voyage.settle_due(
  p_fleets    uuid[]      default null,
  p_now       timestamptz default now(),
  p_limit     int         default null,
  p_wake_max  int         default null,
  p_budget_ms int         default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0125: THE MERCHANT CATCH-UP ON READ. p_fleets: the merchants the calling read reports (null =
-- every merchant). Locks as the sweep locks, settles through the one catch-up (voyage.settle), and
-- decides nothing: arrival, dock, lap close, rest and the next lap are all judged downstream of
-- voyage.settle. Server-only; never an entry point.
declare
  v_t0      timestamptz := clock_timestamp();
  v_lock    text := current_setting('lock_timeout');
  v_limit   int;
  v_wake    int;
  v_budget  interval;
  v_settled int := 0;
  v_woken   int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_over    int := 0;
  v_notes   jsonb := '[]'::jsonb;
  r         record;
begin
  if not public.merchant_settle_on_read() or not public.npc_traders_on() then
    return jsonb_build_object('settled', 0, 'woken', 0, 'busy', 0, 'failed', 0, 'over_budget', 0, 'ms', 0,
                              'notes', '[]'::jsonb);
  end if;
  v_limit  := greatest(0, coalesce(p_limit, public.wc_int('merchant_settle_per_read')));
  v_wake   := greatest(0, coalesce(p_wake_max, public.wc_int('merchant_wake_per_read')));
  v_budget := make_interval(secs => greatest(0, coalesce(p_budget_ms, public.wc_int('merchant_settle_budget_ms'))) / 1000.0);
  perform set_config('lock_timeout', public.wc_int('merchant_settle_lock_ms') || 'ms', true);

  -- ARRIVALS, oldest eta first (the sweep's order). `eta <= p_now` picks candidates; voyage.settle
  -- judges the arrival. players.is_npc is the one predicate: a player's fleet is never settled here.
  for r in select v.id, v.fleet_id
             from public.voyages v
             join public.fleets f on f.id = v.fleet_id
             join public.players p on p.id = f.player_id and p.is_npc
            where v.status = 'SAILING' and v.eta <= p_now
              and (p_fleets is null or v.fleet_id = any(p_fleets))
            order by v.eta
            limit v_limit loop
    if clock_timestamp() >= v_t0 + v_budget then
      v_over := v_over + 1;
      exit;
    end if;
    begin
      perform 1 from public.voyages where id = r.id and status = 'SAILING' for update skip locked;
      if not found then
        v_busy := v_busy + 1;          -- the sweep or another read holds her
      else
        perform voyage.settle(r.fleet_id, p_now);
        v_settled := v_settled + 1;
      end if;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('fleet', r.fleet_id, 'error', sqlerrm);
    end;
  end loop;

  -- WAKES: a rest that is over, soonest first — the sweep's wake predicate (0092). voyage.settle of a
  -- fleet with no voyage is cmd.advance, which refills through cmd.run_standing_route; the lap start
  -- there writes hold_until, so it is not cleared here.
  if v_over = 0 and v_wake > 0 and public.standing_routes_on() then
    for r in select f.id
               from public.fleets f
               join public.players p on p.id = f.player_id and p.is_npc
               join public.standing_routes sr on sr.fleet_id = f.id
              where sr.paused_reason is null and sr.hold_until is not null and sr.hold_until <= p_now
                and f.status = 'DOCKED'
                and (p_fleets is null or f.id = any(p_fleets))
              order by sr.hold_until
              limit v_wake loop
      if clock_timestamp() >= v_t0 + v_budget then
        v_over := v_over + 1;
        exit;
      end if;
      begin
        perform 1 from public.fleets where id = r.id for update skip locked;
        if not found then
          v_busy := v_busy + 1;
        else
          perform voyage.settle(r.id, p_now);
          v_woken := v_woken + 1;
        end if;
      exception
        when lock_not_available then
          v_busy := v_busy + 1;
        when others then
          v_failed := v_failed + 1;
          v_notes := v_notes || jsonb_build_object('fleet', r.id, 'error', sqlerrm);
      end;
    end loop;
  end if;

  perform set_config('lock_timeout', v_lock, true);
  return jsonb_build_object('settled', v_settled, 'woken', v_woken, 'busy', v_busy, 'failed', v_failed,
                            'over_budget', v_over,
                            'ms', round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1),
                            'notes', v_notes);
end $$;
comment on function voyage.settle_due(uuid[], timestamptz, int, int, int) is
  '0125: THE merchant catch-up on read. Settles the due merchants among p_fleets (null = all) through '
  'voyage.settle, skip-locked, bounded by merchant_settle_per_read / merchant_wake_per_read / '
  'merchant_settle_budget_ms. Called first by the four merchant reads. Server-only.';
revoke all on function voyage.settle_due(uuid[], timestamptz, int, int, int) from public, anon, authenticated;

-- ── 5. THE HUNKS (old = verbatim from the live bodies; new = what replaces it) ─────────────────
create temp table hunks_0125 (fn text, n int, old text, new text) on commit drop;

-- n = 0 on every read: STABLE → volatile (the header line pg_get_functiondef prints).
insert into hunks_0125
select fn, 0, E'\n STABLE SECURITY DEFINER\n', E'\n SECURITY DEFINER\n'
  from unnest(array['world.sea_roster(timestamptz)', 'world.port_merchants(uuid)',
                    'world.npc_fleet_card(uuid)', 'world.fleet_trades(uuid)']) fn;

insert into hunks_0125 values
('world.sea_roster(timestamptz)', 1,
$h$    return jsonb_build_object('enabled', false, 'at', now(), 'full', p_since is null, 'fleets', '[]'::jsonb);
  end if;
$h$,
$h$    return jsonb_build_object('enabled', false, 'at', now(), 'full', p_since is null, 'fleets', '[]'::jsonb);
  end if;

  -- 0125: SHE DOCKS ON THIS READ. The merchants due are settled through the one catch-up first, so
  -- a settled arrival is in this very answer (her lap close / refill moves updated_at; a stop she
  -- sails on from departs a new voyage).
  perform voyage.settle_due(null, now());
$h$),

('world.port_merchants(uuid)', 1,
$h$  select case when not public.npc_traders_on()
$h$,
$h$  -- 0125: SHE DOCKS ON THIS READ. The merchants whose loop calls here are settled first through the
  -- one catch-up (voyage.settle_due, a no-op dark or switched off); the answer below is read after it.
  select voyage.settle_due(array(select nf.fleet_id from public.npc_fleets nf
                                  where exists (select 1 from public.standing_route_stops st
                                                 where st.route_id = nf.route_id and st.port_id = p_port)),
                           now());
  select case when not public.npc_traders_on()
$h$),

('world.npc_fleet_card(uuid)', 1,
$h$    raise exception 'E_NOT_FOUND: there is no such merchant fleet' using errcode = 'P0001';
  end if;
  select * into p from public.players where id = f.player_id;
$h$,
$h$    raise exception 'E_NOT_FOUND: there is no such merchant fleet' using errcode = 'P0001';
  end if;
  -- 0125: SHE DOCKS ON THIS READ (voyage.settle_due), and the card is built from the fleet after it.
  perform voyage.settle_due(array[f.id], now());
  select x.* into f from public.fleets x where x.id = f.id;
  select * into p from public.players where id = f.player_id;
$h$),

('world.fleet_trades(uuid)', 1,
$h$    raise exception 'E_NOT_FOUND: there is no such merchant fleet' using errcode = 'P0001';
  end if;
  if v_npc then
$h$,
$h$    raise exception 'E_NOT_FOUND: there is no such merchant fleet' using errcode = 'P0001';
  end if;
  if v_npc then
    -- 0125: a MERCHANT docks on this read. A player's own fleet is settled by world.fleets(), never here.
    perform voyage.settle_due(array[f.id], now());
$h$);

-- ── 6. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
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
                                           ('world.npc_fleet_card(uuid)'), ('world.fleet_trades(uuid)')) x(fn);

-- ── 7. THE SELF-ASSERT ─────────────────────────────────────────────────────────────────────────
do $$
declare
  c_reads   constant text[] := array['world.sea_roster(timestamptz)', 'world.port_merchants(uuid)',
                                     'world.npc_fleet_card(uuid)', 'world.fleet_trades(uuid)'];
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  r         record;
  v_n       int;
  v_was_on  boolean := public.npc_traders_on();
  v_routes_on boolean := public.standing_routes_on();
  v_subj    uuid[];        -- A, B, C, D, E: sailing merchants; W: a rested one
  v_route   uuid[];
  v_vid     uuid[];        -- their first voyages
  v_dest    uuid[];
  v_w       uuid;
  v_wroute  uuid;
  v_wlap    uuid;
  v_port    uuid;
  v_r       jsonb;
  v_row     jsonb;
  v_a       jsonb;
  v_b       jsonb;
  v_t0      timestamptz;
  v_ms_harbour numeric;
  v_ms_roster  numeric;
  v_ms_card    numeric;
  v_ms_wake    numeric;
  v_ms_trades  numeric;
  v_arm_d   text;
  v_arm_e   text;
  v_arm_w   text;
  v_msg     text;
  i         int;
begin
  -- (a) POSTURE: the four reads volatile (each was stable); ACLs unmoved; the two new functions
  --     server-only; no new entry point; no client write; the knobs are this file's, at its values.
  for v_fn in select unnest(c_reads) loop
    if (select vol from defs_before_0125 where fn = v_fn) <> 's'
       or (select p.provolatile from pg_proc p where p.oid = v_fn::regprocedure) <> 'v' then
      raise exception '0125 self-assert FAIL: % was not stable before or is not volatile now', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0125 where fn = v_fn) then
      raise exception '0125 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;
  if has_function_privilege('anon', 'voyage.settle_due(uuid[], timestamptz, int, int, int)', 'execute')
     or has_function_privilege('authenticated', 'voyage.settle_due(uuid[], timestamptz, int, int, int)', 'execute')
     or has_function_privilege('anon', 'public.merchant_settle_on_read()', 'execute')
     or has_function_privilege('authenticated', 'public.merchant_settle_on_read()', 'execute') then
    raise exception '0125 self-assert FAIL: voyage.settle_due or the switch reader is client-callable';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0125)
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0125 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;
  if (select knobs_found from before_0125) <> 0 then
    raise exception '0125 self-assert FAIL: a merchant_settle knob existed before this file — a drift, not a default';
  end if;
  if public.wc('merchant_settle_on_read') <> 'true'::jsonb or public.wc_int('merchant_settle_per_read') <> 12
     or public.wc_int('merchant_wake_per_read') <> 2 or public.wc_int('merchant_settle_budget_ms') <> 1500
     or public.wc_int('merchant_settle_lock_ms') <> 500
     or exists (select 1 from public.world_config where key like 'merchant_settle%' and coalesce(description, '') = '') then
    raise exception '0125 self-assert FAIL: the knobs do not read this file''s values';
  end if;

  -- (b) ONE AUTHORITY. Each read reverses to its pre-image hunk by hunk, each hunk once; each read
  --     calls voyage.settle_due exactly once; voyage.settle has exactly one new caller (settle_due);
  --     voyage.settle and the sweep are their pre-images; the wrapper locks as the sweep does and its
  --     candidates are merchants only.
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
    if (length(v_def) - length(replace(v_def, 'voyage.settle_due(', ''))) / length('voyage.settle_due(') <> 1
       or strpos(v_def, 'voyage.settle(') > 0 then
      raise exception '0125 self-assert FAIL: % does not call voyage.settle_due exactly once, or calls voyage.settle itself', v_fn;
    end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not like 'pg_temp%' and p.prosrc like '%voyage.settle(%')
     <> (select settle_callers from before_0125) + 1 then
    raise exception '0125 self-assert FAIL: voyage.settle gained a caller other than voyage.settle_due';
  end if;
  foreach v_fn in array array['voyage.settle(uuid, timestamptz)', 'public.tick_arrivals(timestamptz)'] loop
    if replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '') <> (select def from defs_before_0125 where fn = v_fn) then
      raise exception '0125 self-assert FAIL: % was re-cut', v_fn;
    end if;
  end loop;
  v_def := pg_get_functiondef('voyage.settle_due(uuid[], timestamptz, int, int, int)'::regprocedure);
  if (length(v_def) - length(replace(v_def, 'for update skip locked', ''))) / length('for update skip locked') <> 2
     or (length(v_def) - length(replace(v_def, 'p.is_npc', ''))) / length('p.is_npc') <> 2
     or strpos(v_def, 'set_config(''lock_timeout''') = 0 then
    raise exception '0125 self-assert FAIL: voyage.settle_due does not lock as the sweep does, or reads a non-merchant';
  end if;

  -- THE PROBES, rolled back. Six merchants by roster order, docked at their home stop: five put to
  -- sea on their routes (the one start door, cmd.standing_route_assign_for), one rested at home.
  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
    -- A-E: merchants AT SEA on their route for one of its harbours, by roster order — the live
    -- world has hundreds; a world where none sails (a fresh chain) is topped up through the one
    -- start door, cmd.standing_route_assign_for, from merchants lying at their home stop.
    select coalesce(array_agg(x.fleet_id order by x.ord, x.fleet_id), '{}'), coalesce(array_agg(x.route_id order by x.ord, x.fleet_id), '{}')
      into v_subj, v_route
      from (select nf.fleet_id, nf.route_id, nf.roster_ord as ord
              from public.npc_fleets nf
              join public.voyages v on v.fleet_id = nf.fleet_id and v.status = 'SAILING'
              join public.ports po on po.id = v.dest_port_id and po.kind = 'HARBOUR'
             where nf.route_id is not null
               and v.eta > now() + interval '5 minutes'   -- not one the sweep is about to arrive
               and exists (select 1 from public.standing_route_stops st where st.route_id = nf.route_id and st.port_id = v.dest_port_id)
             order by nf.roster_ord, nf.fleet_id limit 5) x;
    for r in select nf.fleet_id, nf.route_id, f.player_id
               from public.npc_fleets nf
               join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
               join public.standing_route_stops st on st.route_id = nf.route_id and st.ord = 0 and st.port_id = f.port_id
               join public.players pl on pl.id = f.player_id
               join public.standing_routes sr on sr.id = nf.route_id
              where nf.route_id is not null and pl.ducats >= sr.reserve
                and not exists (select 1 from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING')
                -- not inside her rest (on a lit world the start door would hold her at home)
                and not exists (select 1 from public.standing_route_laps x
                                 where x.route_id = nf.route_id and x.closed_at > now() - interval '30 minutes')
              order by nf.roster_ord, nf.fleet_id limit 6 loop
      if coalesce(array_length(v_subj, 1), 0) >= 5 then
        v_w := r.fleet_id;        -- W: the first one left lying at home
        v_wroute := r.route_id;
        exit;
      end if;
      v_r := cmd.standing_route_assign_for(r.player_id, r.route_id, r.fleet_id);
      if not coalesce((v_r->>'ok')::boolean, false) then
        raise exception '0125 self-assert FAIL: the start door refused a probe: %', v_r;
      end if;
      v_subj := v_subj || r.fleet_id;
      v_route := v_route || r.route_id;
    end loop;
    if coalesce(array_length(v_subj, 1), 0) <> 5 or v_w is null then
      raise exception '0125 self-assert FAIL: five merchants at sea and one at home to probe were not found (%, %)',
        coalesce(array_length(v_subj, 1), 0), v_w;
    end if;
    select array_agg(v.id order by k), array_agg(v.dest_port_id order by k) into v_vid, v_dest
      from unnest(v_subj[1:5]) with ordinality s(fid, k)
      left join public.voyages v on v.fleet_id = s.fid and v.status = 'SAILING';
    if array_position(v_vid, null) is not null
       or exists (select 1 from unnest(v_dest) d join public.ports po on po.id = d where po.kind <> 'HARBOUR') then
      raise exception '0125 self-assert FAIL: a probe merchant did not put to sea for a harbour';
    end if;
    -- The probes' passages are held for the rest of the block: on a live world the minute sweep
    -- (for update skip locked) passes them by instead of arriving one under the probe's feet.
    perform 1 from public.voyages where id = any(v_vid) for update;
    -- Due now: each passage REWOUND whole, as proof 12 rewinds it for the cron (departed_at and eta
    -- moved back together, so every sea-day of hers is due and voyage.settle resolves them on the way
    -- to the arrival, exactly as for a fleet left alone), hazards off so no delay re-derives her eta
    -- past now. voyage.recompute_eta stays THE ETA author; this is a probe-only move of the clock.
    -- B's route clock is put back too: the roster's delta since 15 s ago can only carry her if this
    -- read moved her.
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.voyages v set departed_at = v.departed_at - (v.eta - now()) - interval '1 minute',
                                eta = now() - interval '1 minute'
     where v.id = any(v_vid[2:5]);   -- A is rewound just before her own read, (d), below
    update public.standing_routes set updated_at = now() - interval '2 minutes' where id = v_route[2];

    -- (c) PARITY WHEN OFF: switch off, on the lit world with four merchants due — the four reads are
    --     their pre-images to the byte, and nobody moved.
    update public.world_config set value = 'false'::jsonb where key = 'merchant_settle_on_read';
    select st.port_id into v_port from public.standing_route_stops st join public.ports po on po.id = st.port_id
      join public.npc_fleets nf on nf.route_id = st.route_id order by po.code limit 1;
    -- (asked twice at most: on a live world another job may commit between the two halves of a pair)
    for i in 1 .. 2 loop
      v_n := (world.sea_roster(null) is distinct from pg_temp.sea_roster_before_0125(null))::int
           + (world.sea_roster(now() - interval '15 seconds') is distinct from pg_temp.sea_roster_before_0125(now() - interval '15 seconds'))::int
           + (world.port_merchants(v_port) is distinct from pg_temp.port_merchants_before_0125(v_port))::int
           + (world.port_merchants(v_dest[3]) is distinct from pg_temp.port_merchants_before_0125(v_dest[3]))::int
           + (world.npc_fleet_card(v_subj[3]) is distinct from pg_temp.card_before_0125(v_subj[3]))::int
           + (world.fleet_trades(v_subj[3]) is distinct from pg_temp.trades_before_0125(v_subj[3]))::int;
      exit when v_n = 0;
    end loop;
    if v_n <> 0 then
      raise exception '0125 self-assert FAIL: switched off, % merchant read(s) are not their pre-image', v_n;
    end if;
    if (select count(*) from public.voyages where id = any(v_vid) and status = 'SAILING') <> 5 then
      raise exception '0125 self-assert FAIL: switched off, a read settled a merchant';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'merchant_settle_on_read';

    -- (h) DARK, NOTHING: the switch on but the merchants dark — each read is its dark pre-image.
    update public.world_config set value = 'false'::jsonb where key = 'npc_traders_enabled';
    if world.sea_roster(null) is distinct from pg_temp.sea_roster_before_0125(null)
       or world.port_merchants(v_dest[3]) is distinct from pg_temp.port_merchants_before_0125(v_dest[3])
       or voyage.settle_due(array[v_subj[3]])->>'settled' <> '0'
       or (select count(*) from public.voyages where id = any(v_vid) and status = 'SAILING') <> 5 then
      raise exception '0125 self-assert FAIL: dark, a merchant read moved a merchant or changed its answer';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';

    -- (f) THE BUDGET BITES: at 0 ms her card settles nothing; the receipt says over_budget.
    update public.world_config set value = to_jsonb(0) where key = 'merchant_settle_budget_ms';
    perform world.npc_fleet_card(v_subj[3]);
    v_r := voyage.settle_due(array[v_subj[3]]);
    if (select status from public.voyages where id = v_vid[3]) <> 'SAILING'
       or (v_r->>'over_budget')::int < 1 or (v_r->>'settled')::int <> 0 then
      raise exception '0125 self-assert FAIL: a zero budget still settled (%)', v_r;
    end if;
    update public.world_config set value = to_jsonb(1500) where key = 'merchant_settle_budget_ms';

    -- (f) THE COUNT BITES: two due (D, E), a limit of one — exactly one settled, the other untouched.
    v_r := voyage.settle_due(array[v_subj[4], v_subj[5]], now(), 1);
    if (v_r->>'settled')::int <> 1
       or (select count(*) from public.voyages where id in (v_vid[4], v_vid[5]) and status = 'SAILING') <> 1 then
      raise exception '0125 self-assert FAIL: a limit of one settled % (%)',
        2 - (select count(*) from public.voyages where id in (v_vid[4], v_vid[5]) and status = 'SAILING'), v_r;
    end if;

    -- the card and the trade history each settle their one merchant.
    v_t0 := clock_timestamp();
    v_a := world.npc_fleet_card(v_subj[3]);
    v_ms_card := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1);
    if (select status from public.voyages where id = v_vid[3]) <> 'ARRIVED'
       or v_a->'fleet'->>'status' is distinct from (select status from public.fleets where id = v_subj[3]) then
      raise exception '0125 self-assert FAIL: her card did not dock her, or was built from the fleet before it: %', v_a->'fleet';
    end if;
    i := case when (select status from public.voyages where id = v_vid[4]) = 'SAILING' then 4 else 5 end;
    v_t0 := clock_timestamp();
    perform world.fleet_trades(v_subj[i]);
    v_ms_trades := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1);
    if (select status from public.voyages where id = v_vid[i]) <> 'ARRIVED' then
      raise exception '0125 self-assert FAIL: her trade history did not dock her';
    end if;

    -- (f) THE WAKE CAP BITES. W lies at home with her rest over: at 0 her card leaves her be; at 1 it
    --     puts her back to sea through the executor — a new lap, or at sea, or paused with a reason.
    -- (her queue released through the one CLEAR core first, as the upkeep releases a halted merchant:
    --  on a live world the merchants lying at home are mostly ones a refused SAIL has halted)
    perform cmd.clear_for((select player_id from public.fleets where id = v_w), v_w, false);
    update public.standing_routes
       set fleet_id = v_w, stop_cursor = 0, lap_id = null, paused_reason = null,
           hold_until = now() - interval '1 second', updated_at = now() - interval '1 hour'
     where id = v_wroute;
    update public.world_config set value = to_jsonb(0) where key = 'merchant_wake_per_read';
    perform world.npc_fleet_card(v_w);
    if (select status from public.fleets where id = v_w) <> 'DOCKED'
       or (select lap_id from public.standing_routes where id = v_wroute) is not null
       or (select hold_until from public.standing_routes where id = v_wroute) is distinct from now() - interval '1 second' then
      raise exception '0125 self-assert FAIL: a wake cap of 0 still woke her';
    end if;
    update public.world_config set value = to_jsonb(1) where key = 'merchant_wake_per_read';
    v_t0 := clock_timestamp();
    perform world.npc_fleet_card(v_w);
    v_ms_wake := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1);
    select case when sr.paused_reason is not null then 'paused ' || sr.paused_reason
                when exists (select 1 from public.voyages v where v.fleet_id = v_w and v.status = 'SAILING') then 'at sea'
                when sr.lap_id is not null then 'new lap'
           end into v_arm_w
      from public.standing_routes sr where sr.id = v_wroute;
    if v_arm_w is null then
      raise exception '0125 self-assert FAIL: a wake cap of 1 did not wake her';
    end if;
    update public.world_config set value = to_jsonb(2) where key = 'merchant_wake_per_read';

    -- (e)/(d) run LAST, and with the count and the budget opened: the harbour's read and the map's
    -- read settle every due merchant they report, and on a live world others may be due ahead of the
    -- probe. The bounds themselves are (f)'s.
    update public.world_config set value = to_jsonb(1000) where key = 'merchant_settle_per_read';
    update public.world_config set value = to_jsonb(60000) where key = 'merchant_settle_budget_ms';
    -- (e) THE MAP'S READ CARRIES HER IN THE SAME ANSWER. Positive control: the old roster's delta
    --     does not carry B at all; the new one does, docked or on a new voyage, never at the old eta.
    if exists (select 1 from jsonb_array_elements(pg_temp.sea_roster_before_0125(now() - interval '15 seconds')->'fleets') x
                where x->>'id' = v_subj[2]::text) then
      raise exception '0125 self-assert FAIL: the control — the old delta already carried the probe';
    end if;
    v_t0 := clock_timestamp();
    v_r := world.sea_roster(now() - interval '15 seconds');
    v_ms_roster := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1);
    select x into v_row from jsonb_array_elements(v_r->'fleets') x where x->>'id' = v_subj[2]::text;
    if v_row is null or (select status from public.voyages where id = v_vid[2]) <> 'ARRIVED'
       or (jsonb_typeof(v_row->'voyage') = 'object' and (v_row->'voyage'->>'eta')::timestamptz <= now()) then
      raise exception '0125 self-assert FAIL: the roster''s delta did not carry her settled: %', v_row;
    end if;
    v_arm_e := case when jsonb_typeof(v_row->'voyage') = 'object' then 'sailed on' else 'docked' end;

    -- A's passage, rewound now (the map's read above settles every merchant due, so she is made due
    -- only for her harbour's read).
    update public.voyages v set departed_at = v.departed_at - (v.eta - now()) - interval '1 minute',
                                eta = now() - interval '1 minute'
     where v.id = v_vid[1];

    -- (d) AN ARRIVAL DOCKS ON THE HARBOUR'S READ, called as a player: the old voyage ARRIVED, nothing
    --     of hers is left due for the sweep, and her row in THIS answer is her state after it — at the
    --     quay (port = the harbour, no voyage) or, at a stop she trades and sails on from, a NEW voyage.
    execute 'set local role authenticated';
    v_t0 := clock_timestamp();
    v_r := world.port_merchants(v_dest[1]);
    v_ms_harbour := round((extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric, 1);
    execute 'reset role';
    select m into v_row from jsonb_array_elements(v_r->'merchants') m where m->>'id' = v_subj[1]::text;
    if (select status from public.voyages where id = v_vid[1]) <> 'ARRIVED'
       or exists (select 1 from public.voyages where fleet_id = v_subj[1] and status = 'SAILING' and eta <= now())
       or v_row is null
       or v_row->>'status' is distinct from (select status from public.fleets where id = v_subj[1]) then
      raise exception '0125 self-assert FAIL: the harbour''s read did not dock her: voyage %, row %',
        (select status from public.voyages where id = v_vid[1]), v_row;
    end if;
    if v_row->>'port' = (select code from public.ports where id = v_dest[1]) and jsonb_typeof(v_row->'voyage') is distinct from 'object' then
      v_arm_d := 'docked, ' || (v_row->>'doing');
    elsif jsonb_typeof(v_row->'voyage') = 'object' and (v_row->'voyage'->>'eta')::timestamptz > now()
          and exists (select 1 from public.voyages where fleet_id = v_subj[1] and status = 'SAILING' and id <> v_vid[1]) then
      v_arm_d := 'traded and sailed on';
    else
      raise exception '0125 self-assert FAIL: her harbour row is neither at the quay nor on a new voyage: %', v_row;
    end if;

    update public.world_config set value = to_jsonb(12) where key = 'merchant_settle_per_read';
    update public.world_config set value = to_jsonb(1500) where key = 'merchant_settle_budget_ms';

    raise exception 'ROLLBACK_0125|%|%|%|%|%|%|%|%', v_ms_harbour, v_ms_roster, v_ms_card, v_ms_trades, v_ms_wake,
      v_arm_d, v_arm_e, v_arm_w;
  exception when others then
    if sqlerrm not like 'ROLLBACK_0125|%' then raise; end if;
    v_msg := sqlerrm;
  end;
  if public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on
     or public.wc('merchant_settle_on_read') <> 'true'::jsonb or public.wc_int('merchant_wake_per_read') <> 2
     or public.wc_int('merchant_settle_budget_ms') <> 1500 or current_user <> session_user
     -- a rewound passage left behind (on a live world the probes' voyages are real and stay)
     or exists (select 1 from public.voyages v where v.id = any(v_vid) and v.eta = now() - interval '1 minute')
     or exists (select 1 from public.standing_routes where id = v_wroute and fleet_id is not distinct from v_w
                   and hold_until = now() - interval '1 second') then
    raise exception '0125 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0125 self-assert ok: A MERCHANT DOCKS THE MOMENT SHE ARRIVES. sea_roster, port_merchants, npc_fleet_card and fleet_trades are volatile, reverse to their pre-images hunk by hunk, ACLs unmoved, and each calls voyage.settle_due once; voyage.settle has exactly one new caller and neither it nor the sweep was re-cut; settle_due locks as the sweep does, reads merchants only, is server-only; no new entry point, no client write; five knobs at true/12/2/1500/500. Switched off and dark, every read is its pre-image to the byte and nobody moves. Probes: the harbour''s read (as authenticated) docked an arrival in % ms (%); the roster delta carried an arrival only this read moved, in % ms (%); the card % ms, the trade history % ms; a wake through the card % ms (%); a 0 ms budget settles nothing, a limit of one settles one of two, a wake cap of 0 wakes none. Rolled back.',
    split_part(v_msg, '|', 2), split_part(v_msg, '|', 7), split_part(v_msg, '|', 3), split_part(v_msg, '|', 8),
    split_part(v_msg, '|', 4), split_part(v_msg, '|', 5), split_part(v_msg, '|', 6), split_part(v_msg, '|', 9);
end $$;
