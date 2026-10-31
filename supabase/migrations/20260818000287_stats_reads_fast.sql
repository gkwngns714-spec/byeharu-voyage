-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0287 — THE STATS READ TOUCHES ONLY THE ROWS IT SERVES
--        (three covering indexes; NO function body is re-cut, so every served figure is identical by
--         construction: the same SQL over the same rows, with the access path moved off the heap scans)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE MEASURED STATE (prod, read-only, 2026-10-31, head 20260818000285) ──────────────────────
--   The Stats face shows "World figures not loaded." The read under it is world.stats_overview(24, '1d')
--   / (24, '1w'), 0232's count plus the minutes since it, through public.stats_window_totals →
--   public.stats_window_trades. Measured:
--     the last count is 2026-10-30 18:06:00 UTC — 64,368 s (17.9 h) old at the first read today,
--       65,781 s at the 1d replay. The count's cron (every 15 min) has FAILED since 18:21 that day:
--       71 failed runs in 24 h, every one "canceling statement due to statement timeout" at 120.2 s,
--       in the merchants insert inside public.stats_merchants_window (its 24-hour window of closed
--       laps); one later run ran out of time in the city-good insert first. A missed count cannot
--       shrink its own window (v_prev_at is the last SUCCESSFUL row), so the read's window has grown
--       from 15 min to 17.9 h: 228,565 events (the whole live table; 24,953 are SOLD / BOUGHT),
--       183,861 ledger rows (FOUNDING / NPC_REFOUND: none), 5,648 treasury flows, 384 stats rows.
--       The count has also not folded public.stats_live_deltas since 18:06 — 1,005,498 rows.
--     MEASURED, the read's pieces (EXPLAIN (ANALYZE, BUFFERS) over plain tables; read-only):
--       world.stats_now()            17.5 s   (Σ 1,005,498 journal rows — the count backlog, not a plan)
--       public.stats_window_kinds     4.7 s
--       public.stats_window_founded  26.4 s   (Bitmap Heap Scan on ledger: 183,861 rows kept 0)
--       public.stats_window_flows     2.0 s
--       public.stats_window_totals    4.3 s warm / 84.7 s cold / the events half alone >110 s (57014)
--       world.stats_overview('1d')   17.1 s (12:23:14 → 12:23:31 UTC, answered); the SAME read on '1w'
--                                    timed out at 110 s in stats_window_trades minutes later.
--   THE SINGLE MOST EXPENSIVE STEP is the events scan inside public.stats_window_trades. public.events
--   carries events_created_at (created_at) only, so the read heap-reads every event in the window and
--   then throws the non-trades away: the measured plan removed 203,762 of 228,754 rows. The goods join is
--   not the cost (a 629-row Hash, 0.5 ms). The existing events_trades_port_good cannot help a
--   created_at range (its leading columns are payload->>'port', payload->>'good'; the 24 h attempt was a
--   Bitmap Index Scan over itself, 24.9 s). The count's own killer is the same shape on the laps table:
--   standing_route_laps_closed_at (closed_at) heap-fetches route_id and net for ~28,700 laps (est.
--   53,797) from a 238 MB heap (167,359 rows), and the 24 h window then times out at 120 s.
--
-- ── THE FIX, AND WHY IT IS CHEAPER THAN A RE-CUT ──────────────────────────────────────────────
--   Three indexes; no body changes. The same SQL reads the same rows; only the access path moves from
--   "read everything in the window, keep a few" to "read the few":
--     1. public.events_trades_window   events (created_at) INCLUDE (id, kind, player_id, payload)
--                                      WHERE kind IN ('SOLD','BOUGHT')
--        the read's window (and every public.stats_window_* that shares it, and public.stats_live_fold's
--        trade query) scans ~25k covering entries instead of 228k heap rows. All 25,360 live trade
--        payloads were measured on prod (the newest 5,000 average 372 bytes) and top out at 460 bytes,
--        so the index is a few MB, not a copy of the heap.
--     2. public.ledger_founded_window  ledger (created_at) WHERE kind IN ('FOUNDING','NPC_REFOUND')
--        the founded window's range scan holds only founding rows, where the current plan reads 183,861
--        ledger rows to keep none.
--     3. public.standing_route_laps_window  standing_route_laps (closed_at) INCLUDE (route_id, net, lap_no)
--                                      WHERE lap_no >= 2
--        the count's 24 h merchants window becomes an index-only scan of the laps it sums, instead of
--        ~28,700 heap fetches from a 238 MB heap.
--   The third index is the count's; it is in this file because the read's 17.9 h window IS the dead
--   count (the same public.stats_merchants_window statement, measured in cron.job_run_details, is what
--   times out). With the count current the read's window is minutes, and public.stats_live_deltas folds
--   back to the one-slot size 0224 designed, which is what makes stats_now cheap again.
--   SAID PLAINLY: the one-time backlog (1.0 M journal rows, 17.9 h of events) is folded by the next
--   successful count. Until that count runs, stats_now still pays for the journal; this file makes every
--   other step of the read cheap and lets the count complete. The after-check
--   (docs/dev-log/2026-10-31-stats-timeout.md) watches the next :06/:21/:36/:51 runs and names the one
--   write that clears the backlog under a longer statement_timeout if the cron's 2 minutes cannot.
--
-- ── WHAT DOES NOT MOVE ─────────────────────────────────────────────────────────────────────────
--   No function body. The md5 of every function in public/cmd/world/voyage is asserted unchanged, and
--   each read-path function's ACL / volatility / definer / config is asserted as found. No table row,
--   column, grant, knob or switch. No client read added or removed (the registry count is asserted
--   unchanged). The indexes are the whole change; every served figure is identical by construction.
--
-- ── SELF-ASSERT (probe rows only; every probe in a sub-transaction, rolled back and asserted gone) ──
--   (a) as found: the read path exists, every function md5-unmoved, the registry count, the walls
--       (0 client write grants / 0 executable writers / 0 caller-evaluated functions) and the two owner
--       switches read back as found.
--   (b) WITHOUT THE INDEXES: probe rows at fixed instants on 2004-06-01 (no real row is ever there) —
--       four trades (2 SOLD, 2 BOUGHT) on one good, five city flows (SELL -1000, SELL -600, BUY 400,
--       BUY 100, TAX 30), two ledger mints (FOUNDING 500, NPC_REFOUND 300) — read through
--       stats_window_trades / _totals / _goods / _city_trades / _city_goods / _cities / _flows /
--       _founded / _kinds; every figure asserted against its hand-computed amount (sold 1600, bought
--       500, units 25, trades 4; the good 15 / 10; the city income 530, spending 1600, taxes 30, sold
--       15, bought 10; kinds SELL -1600, BUY 500, TAX 30, FOUNDING 500, NPC_REFOUND 300). The answers
--       are kept and the probe is rolled back.
--   (c) THE INDEXES: created; each asserted present, valid, partial, with its key and INCLUDE columns.
--   (d) WITH THE INDEXES: the same probe answers BYTE-IDENTICALLY to (b) and to the hand amounts; the
--       exact queries of the read, the founded window and the merchants window plan (seq scans
--       discouraged) through events_trades_window / ledger_founded_window / standing_route_laps_window.
--       Rolled back and asserted gone.
--   (e) THE READ: world.stats_overview(24, '1d') and (24, '1w') over probe count rows planted ten days
--       ahead (the probe's own newest slot) answer with every section — holders adding to their four
--       parts, period, day, a series ending at the read's own now() — and the measured ms are printed.
--       On prod before this file the same calls were 17.1 s and >110 s (57014); the assert is the
--       property the failure broke (they must answer, with the sections intact, inside the API's 120 s
--       wall), and the ms are in the receipt.
--   (f) the registry, the walls and the owner switches are as found; the temp probe function is the only
--       function created (pg_temp, gone with the session).
-- ROLLBACK (forward): drop the three indexes; nothing else was written.
-- VERSION: 0287 — prod head 0286 after the report PR deploys; this file must deploy AFTER 0286.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.stats_window_trades(timestamptz,timestamptz)') is null
     or to_regprocedure('public.stats_window_totals(timestamptz,timestamptz)') is null
     or to_regprocedure('public.stats_merchants_window(timestamptz,timestamptz)') is null
     or to_regprocedure('world.stats_overview(integer,text)') is null then
    raise exception '0287 refuses: 0232 / 0246 (the Stats reads) are not in this world';
  end if;
  if to_regclass('public.events_trades_window') is not null
     or to_regclass('public.ledger_founded_window') is not null
     or to_regclass('public.standing_route_laps_window') is not null then
    raise exception '0287 refuses: one of the three indexes already exists — this has been applied once';
  end if;
end $guard$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0287 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')) as md5,
       coalesce((select pr.proacl::text from pg_proc pr where pr.oid = f.fn::regprocedure), '') as acl,
       (select pr.provolatile from pg_proc pr where pr.oid = f.fn::regprocedure) as vol,
       (select pr.prosecdef from pg_proc pr where pr.oid = f.fn::regprocedure) as secdef,
       (select coalesce(pr.proconfig::text, '') from pg_proc pr where pr.oid = f.fn::regprocedure) as cfg
  from (values
    ('public.stats_window_trades(timestamptz,timestamptz)'),
    ('public.stats_window_totals(timestamptz,timestamptz)'),
    ('public.stats_window_goods(timestamptz,timestamptz)'),
    ('public.stats_window_city_trades(timestamptz,timestamptz)'),
    ('public.stats_window_city_goods(timestamptz,timestamptz)'),
    ('public.stats_window_flows(timestamptz,timestamptz)'),
    ('public.stats_window_cities(timestamptz,timestamptz)'),
    ('public.stats_window_founded(timestamptz,timestamptz)'),
    ('public.stats_window_kinds(timestamptz,timestamptz)'),
    ('public.stats_merchants_window(timestamptz,timestamptz)'),
    ('public.stats_live_fold(timestamptz,boolean)'),
    ('world.stats_overview(integer,text)')) f(fn);

create temp table before_0287 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns_md5,
       (select value from public.world_config where key = 'economy_closed') as economy_closed,
       (select value from public.world_config where key = 'city_treasury_enabled') as city_treasury_enabled;

-- ── 1. THE PROBE (plants its own rows; the caller rolls the sub-transaction back) ───────────────
create temp table probe_before_0287 (k text primary key, v jsonb) on commit drop;

create or replace function pg_temp.probe_0287()
returns jsonb
language plpgsql
as $fn$
-- 0287: plant the read's rows at fixed instants on 2004-06-01 (no real row is ever there), assert every
-- figure against its hand-computed amount, and return the answers. The caller aborts the sub-transaction,
-- so the rows (and this transaction's ledger/event writes) never commit; the append-only tables are never
-- DELETEd.
declare
  c_from constant timestamptz := '2004-06-01 00:00:00+00';
  c_to   constant timestamptz := '2004-06-02 00:00:00+00';
  v_player uuid;
  v_good uuid;
  v_good_name text;
  v_port uuid;
  v_totals jsonb; v_trades jsonb; v_goods jsonb; v_ctrades jsonb; v_cgoods jsonb;
  v_cities jsonb; v_flows jsonb; v_founded jsonb; v_kinds jsonb;
  v_n int;
begin
  if exists (select 1 from public.events where created_at >= c_from and created_at < c_to)
     or exists (select 1 from public.ledger where created_at >= c_from and created_at < c_to)
     or exists (select 1 from public.treasury_flows where created_at >= c_from and created_at < c_to) then
    raise exception '0287 self-assert FAIL: a row already sits in the probe window (2004-06-01) — the probe cannot prove its own rows';
  end if;
  select g.id, g.name into v_good, v_good_name from public.goods g order by g.code limit 1;
  select p.id into v_port from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
  if v_good is null or v_port is null then
    raise exception '0287 self-assert FAIL: no good or harbour to plant the probe at';
  end if;

  insert into public.players (id, auth_uid, company_name, nation_id, ducats, is_npc)
  values ('00000000-0287-4000-8000-0000000000a0', '00000000-0287-4000-8000-0000000000a1', 'Casa da Prova 0287',
          (select id from public.nations where code = 'PRT'), 0, false)
  returning id into v_player;
  insert into public.events (id, player_id, kind, payload, created_at) values
    ('00000000-0287-4000-8000-000000000001', v_player, 'SOLD',   jsonb_build_object('good', v_good_name, 'qty', 10, 'total', 1000), c_from + interval '1 minute'),
    ('00000000-0287-4000-8000-000000000002', v_player, 'SOLD',   jsonb_build_object('good', v_good_name, 'qty', 5,  'total', 600),  c_from + interval '2 minutes'),
    ('00000000-0287-4000-8000-000000000003', v_player, 'BOUGHT', jsonb_build_object('good', v_good_name, 'qty', 8,  'total', 400),  c_from + interval '3 minutes'),
    ('00000000-0287-4000-8000-000000000004', v_player, 'BOUGHT', jsonb_build_object('good', v_good_name, 'qty', 2,  'total', 100),  c_from + interval '4 minutes');
  insert into public.treasury_flows (port_id, kind, ducats, player_id, ref_event, created_at) values
    (v_port, 'SELL', -1000, v_player, '00000000-0287-4000-8000-000000000001', c_from + interval '1 minute'),
    (v_port, 'SELL', -600,  v_player, '00000000-0287-4000-8000-000000000002', c_from + interval '2 minutes'),
    (v_port, 'BUY',   400,  v_player, '00000000-0287-4000-8000-000000000003', c_from + interval '3 minutes'),
    (v_port, 'BUY',   100,  v_player, '00000000-0287-4000-8000-000000000004', c_from + interval '4 minutes'),
    (v_port, 'TAX',    30,  null,     null,                                   c_from + interval '5 minutes');
  insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at) values
    (v_player, 'FOUNDING',    500, 500, c_from + interval '10 minutes'),
    (v_player, 'NPC_REFOUND', 300, 800, c_from + interval '11 minutes');

  -- the world totals, by amount
  select to_jsonb(t) into v_totals from public.stats_window_totals(c_from, c_to) t;
  if v_totals is null or (v_totals->>'sold')::bigint <> 1600 or (v_totals->>'bought')::bigint <> 500
     or (v_totals->>'units')::numeric <> 25 or (v_totals->>'trades')::bigint <> 4 then
    raise exception '0287 self-assert FAIL: the probe window totalled %, not sold 1600 / bought 500 / units 25 / trades 4', v_totals;
  end if;
  select jsonb_agg(to_jsonb(t) order by t.id) into v_trades from public.stats_window_trades(c_from, c_to) t;
  if v_trades is null or jsonb_array_length(v_trades) <> 4
     or (select count(*) from public.stats_window_trades(c_from, c_to) t where t.kind = 'SOLD') <> 2
     or (select count(*) from public.stats_window_trades(c_from, c_to) t where t.kind = 'BOUGHT') <> 2 then
    raise exception '0287 self-assert FAIL: the probe window''s trades are %, not 4 (2 SOLD, 2 BOUGHT)', v_trades;
  end if;

  select jsonb_agg(to_jsonb(t) order by t.good_id) into v_goods from public.stats_window_goods(c_from, c_to) t;
  if v_goods is null or jsonb_array_length(v_goods) <> 1
     or (v_goods->0->>'good_id')::uuid <> v_good
     or (v_goods->0->>'sold')::numeric <> 15 or (v_goods->0->>'bought')::numeric <> 10
     or (v_goods->0->>'sold_d')::numeric <> 1600 or (v_goods->0->>'bought_d')::numeric <> 500 then
    raise exception '0287 self-assert FAIL: the probe good is %, not 15 sold / 10 bought / 1600 / 500', v_goods;
  end if;

  select jsonb_agg(to_jsonb(t) order by t.port_id, t.good_id, t.kind, t.qty, t.total) into v_ctrades
    from public.stats_window_city_trades(c_from, c_to) t;
  if v_ctrades is null or jsonb_array_length(v_ctrades) <> 4 then
    raise exception '0287 self-assert FAIL: the probe city remembers %, not 4 trades', v_ctrades;
  end if;
  select jsonb_agg(to_jsonb(t) order by t.port_id, t.good_id) into v_cgoods from public.stats_window_city_goods(c_from, c_to) t;
  if v_cgoods is null or jsonb_array_length(v_cgoods) <> 1
     or (v_cgoods->0->>'sold')::numeric <> 15 or (v_cgoods->0->>'bought')::numeric <> 10
     or (v_cgoods->0->>'sold_d')::numeric <> 1600 or (v_cgoods->0->>'bought_d')::numeric <> 500 then
    raise exception '0287 self-assert FAIL: the probe city''s good is %, not 15 / 10 / 1600 / 500', v_cgoods;
  end if;

  select to_jsonb(t) into v_cities from public.stats_window_cities(c_from, c_to) t;
  if v_cities is null or (v_cities->>'income')::bigint <> 530 or (v_cities->>'spending')::bigint <> 1600
     or (v_cities->>'taxes')::bigint <> 30 or (v_cities->>'sold')::numeric <> 15 or (v_cities->>'bought')::numeric <> 10
     or (v_cities->'kinds') is distinct from '{"SELL": -1600, "BUY": 500, "TAX": 30}'::jsonb then
    raise exception '0287 self-assert FAIL: the probe city is %, not income 530 / spending 1600 / taxes 30 / sold 15 / bought 10 / the three kinds', v_cities;
  end if;

  select jsonb_agg(to_jsonb(t) order by t.kind) into v_flows from public.stats_window_flows(c_from, c_to) t;
  if v_flows is null or jsonb_array_length(v_flows) <> 3
     or (select sum(t.ducats) from public.stats_window_flows(c_from, c_to) t where t.kind = 'SELL') <> -1600
     or (select sum(t.ducats) from public.stats_window_flows(c_from, c_to) t where t.kind = 'BUY') <> 500
     or (select sum(t.ducats) from public.stats_window_flows(c_from, c_to) t where t.kind = 'TAX') <> 30 then
    raise exception '0287 self-assert FAIL: the probe flows are %, not SELL -1600 / BUY 500 / TAX 30', v_flows;
  end if;

  select jsonb_agg(to_jsonb(t) order by t.kind) into v_founded from public.stats_window_founded(c_from, c_to) t;
  if v_founded is null or jsonb_array_length(v_founded) <> 2
     or (select sum(t.ducats) from public.stats_window_founded(c_from, c_to) t where t.kind = 'FOUNDING') <> 500
     or (select sum(t.ducats) from public.stats_window_founded(c_from, c_to) t where t.kind = 'NPC_REFOUND') <> 300 then
    raise exception '0287 self-assert FAIL: the probe mints are %, not FOUNDING 500 / NPC_REFOUND 300', v_founded;
  end if;

  v_kinds := public.stats_window_kinds(c_from, c_to);
  if v_kinds is distinct from '{"SELL": -1600, "BUY": 500, "TAX": 30, "FOUNDING": 500, "NPC_REFOUND": 300}'::jsonb then
    raise exception '0287 self-assert FAIL: the probe kinds are %, not SELL -1600 / BUY 500 / TAX 30 / FOUNDING 500 / NPC_REFOUND 300', v_kinds;
  end if;

  return jsonb_build_object('totals', v_totals, 'trades', v_trades, 'goods', v_goods, 'city_trades', v_ctrades,
                            'city_goods', v_cgoods, 'cities', v_cities, 'flows', v_flows, 'founded', v_founded, 'kinds', v_kinds);
end $fn$;

-- ── 2. PROBE, WITHOUT THE INDEXES (the rolled-back pre-image) ──────────────────────────────────
do $probe1$
declare
  v_answers jsonb;
begin
  begin
    v_answers := pg_temp.probe_0287();
    raise exception using errcode = 'ZX287', message = 'rollback';
  exception when sqlstate 'ZX287' then
    null;
  end;
  if exists (select 1 from public.players where auth_uid = '00000000-0287-4000-8000-0000000000a1')
     or exists (select 1 from public.events where id in ('00000000-0287-4000-8000-000000000001',
                                                         '00000000-0287-4000-8000-000000000002',
                                                         '00000000-0287-4000-8000-000000000003',
                                                         '00000000-0287-4000-8000-000000000004'))
     or exists (select 1 from public.ledger where created_at >= '2004-06-01 00:00:00+00' and created_at < '2004-06-02 00:00:00+00')
     or exists (select 1 from public.treasury_flows where created_at >= '2004-06-01 00:00:00+00' and created_at < '2004-06-02 00:00:00+00') then
    raise exception '0287 self-assert FAIL: the rolled-back probe left a row behind';
  end if;
  insert into probe_before_0287 (k, v) values ('answers', v_answers);
  raise notice '0287 self-assert ok: (b)  WITHOUT THE INDEXES the probe window (2004-06-01, its own rows only) reads sold 1600 / bought 500 / units 25 / trades 4; the good 15 / 10; the city income 530 / spending 1600 / taxes 30 / sold 15 / bought 10; the kinds SELL -1600 / BUY 500 / TAX 30 / FOUNDING 500 / NPC_REFOUND 300. The probe is rolled back and asserted gone.';
end $probe1$;

-- ── 3. THE THREE INDEXES (plain CREATE INDEX: the transaction holds SHARE on the three tables until
--    the commit, which is the deploy's own cost; 0264's shape) ───────────────────────────────────
create index events_trades_window on public.events (created_at)
  include (id, kind, player_id, payload)
  where kind in ('SOLD', 'BOUGHT');
comment on index public.events_trades_window is
  '0287: the trades of a window — public.stats_window_trades'' own predicate (kind SOLD / BOUGHT) keyed by created_at, covering the columns the read returns. Replaces reading every event in the window from the heap.';

create index ledger_founded_window on public.ledger (created_at)
  where kind in ('FOUNDING', 'NPC_REFOUND');
comment on index public.ledger_founded_window is
  '0287: the mints of a window — public.stats_window_founded''s predicate, so the range scan holds only founding rows instead of every ledger row.';

create index standing_route_laps_window on public.standing_route_laps (closed_at)
  include (route_id, net, lap_no)
  where lap_no >= 2;
comment on index public.standing_route_laps_window is
  '0287: the laps of a window — public.stats_merchants_window''s 24 h predicate (lap 2 onwards), covering route_id and net, so the count reads the laps it sums instead of heap-fetching them from a 238 MB table.';

-- ── 4. PROBE AGAIN, COMPARE, AND THE READ ──────────────────────────────────────────────────────
do $probe2$
declare
  v_before jsonb;
  v_after jsonb;
  v_t0 timestamptz;
  v_ms numeric;
  v_ms2 numeric;
  v_anchor timestamptz := (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') + interval '10 days 1 hour 51 minutes';
  v_o jsonb;
  v_o2 jsonb;
  v_series jsonb;
  d record;
  x record;
begin
  -- (c) the three indexes are present and built as declared
  if (select count(*) from pg_index i
       where i.indexrelid in (to_regclass('public.events_trades_window'),
                              to_regclass('public.ledger_founded_window'),
                              to_regclass('public.standing_route_laps_window'))
         and i.indisvalid) <> 3 then
    raise exception '0287 self-assert FAIL: the three indexes are not all present and valid';
  end if;
  if not exists (select 1 from pg_index i where i.indexrelid = 'public.events_trades_window'::regclass
                  and i.indpred is not null and i.indnkeyatts = 1 and i.indnatts = 5) then
    raise exception '0287 self-assert FAIL: events_trades_window is not (created_at) INCLUDE (id, kind, player_id, payload) WHERE kind IN (SOLD, BOUGHT)';
  end if;
  if not exists (select 1 from pg_index i where i.indexrelid = 'public.ledger_founded_window'::regclass
                  and i.indpred is not null and i.indnkeyatts = 1 and i.indnatts = 1) then
    raise exception '0287 self-assert FAIL: ledger_founded_window is not (created_at) WHERE kind IN (FOUNDING, NPC_REFOUND)';
  end if;
  if not exists (select 1 from pg_index i where i.indexrelid = 'public.standing_route_laps_window'::regclass
                  and i.indpred is not null and i.indnkeyatts = 1 and i.indnatts = 4) then
    raise exception '0287 self-assert FAIL: standing_route_laps_window is not (closed_at) INCLUDE (route_id, net, lap_no) WHERE lap_no >= 2';
  end if;

  -- (d) the same probe, WITH the indexes: byte-identical answers and the hand amounts
  select v into v_before from probe_before_0287 where k = 'answers';
  begin
    v_after := pg_temp.probe_0287();
    raise exception using errcode = 'ZX287', message = 'rollback';
  exception when sqlstate 'ZX287' then
    null;
  end;
  if v_after is distinct from v_before then
    raise exception '0287 self-assert FAIL: with the indexes the window answers differ from without them (%)', v_after;
  end if;
  if exists (select 1 from public.players where auth_uid = '00000000-0287-4000-8000-0000000000a1')
     or exists (select 1 from public.events where created_at >= '2004-06-01 00:00:00+00' and created_at < '2004-06-02 00:00:00+00')
     or exists (select 1 from public.ledger where created_at >= '2004-06-01 00:00:00+00' and created_at < '2004-06-02 00:00:00+00')
     or exists (select 1 from public.treasury_flows where created_at >= '2004-06-01 00:00:00+00' and created_at < '2004-06-02 00:00:00+00') then
    raise exception '0287 self-assert FAIL: the rolled-back probe left a row behind';
  end if;

  -- (d) THE INDEXES, BY DEFINITION — data-independent. Never assert a planner's choice here: it varies
  -- with a world's statistics (CI's first red on this PR was exactly that — the disposable chain chose
  -- another plan while the index was valid). The prod plans and timings are measured in PROD CHECKS /
  -- docs/dev-log/2026-10-31-stats-timeout.md; this file asserts the definitions, which are invariant.
  if (select count(*) from pg_index i
       where i.indexrelid in (to_regclass('public.events_trades_window'),
                              to_regclass('public.ledger_founded_window'),
                              to_regclass('public.standing_route_laps_window'))
         and i.indisvalid and i.indisready and i.indislive and i.indpred is not null and i.indnkeyatts = 1) <> 3 then
    raise exception '0287 self-assert FAIL: the three indexes are not all present, valid, ready, live and partial (one key column each)';
  end if;
  if (select i.indrelid from pg_index i where i.indexrelid = 'public.events_trades_window'::regclass) <> 'public.events'::regclass
     or (select i.indnatts from pg_index i where i.indexrelid = 'public.events_trades_window'::regclass) <> 5
     or (select array_agg(a.attname order by u.ord)
           from pg_index i
           cross join lateral unnest(string_to_array(i.indkey::text, ' ')::int2[]) with ordinality u(attnum, ord)
           join pg_attribute a on a.attrelid = i.indrelid and a.attnum = u.attnum
          where i.indexrelid = 'public.events_trades_window'::regclass)
        is distinct from array['created_at', 'id', 'kind', 'player_id', 'payload']
     or (select pg_get_expr(i.indpred, i.indrelid) from pg_index i where i.indexrelid = 'public.events_trades_window'::regclass)
        not like '%kind = ANY%'
     or (select pg_get_expr(i.indpred, i.indrelid) from pg_index i where i.indexrelid = 'public.events_trades_window'::regclass)
        not like '%SOLD%'
     or (select pg_get_expr(i.indpred, i.indrelid) from pg_index i where i.indexrelid = 'public.events_trades_window'::regclass)
        not like '%BOUGHT%' then
    raise exception '0287 self-assert FAIL: events_trades_window is not events(created_at) INCLUDE (id, kind, player_id, payload) WHERE kind IN (SOLD, BOUGHT): %',
      pg_get_indexdef('public.events_trades_window'::regclass);
  end if;
  if (select i.indrelid from pg_index i where i.indexrelid = 'public.ledger_founded_window'::regclass) <> 'public.ledger'::regclass
     or (select i.indnatts from pg_index i where i.indexrelid = 'public.ledger_founded_window'::regclass) <> 1
     or (select array_agg(a.attname order by u.ord)
           from pg_index i
           cross join lateral unnest(string_to_array(i.indkey::text, ' ')::int2[]) with ordinality u(attnum, ord)
           join pg_attribute a on a.attrelid = i.indrelid and a.attnum = u.attnum
          where i.indexrelid = 'public.ledger_founded_window'::regclass)
        is distinct from array['created_at']
     or (select pg_get_expr(i.indpred, i.indrelid) from pg_index i where i.indexrelid = 'public.ledger_founded_window'::regclass)
        not like '%FOUNDING%'
     or (select pg_get_expr(i.indpred, i.indrelid) from pg_index i where i.indexrelid = 'public.ledger_founded_window'::regclass)
        not like '%NPC_REFOUND%' then
    raise exception '0287 self-assert FAIL: ledger_founded_window is not ledger(created_at) WHERE kind IN (FOUNDING, NPC_REFOUND): %',
      pg_get_indexdef('public.ledger_founded_window'::regclass);
  end if;
  if (select i.indrelid from pg_index i where i.indexrelid = 'public.standing_route_laps_window'::regclass) <> 'public.standing_route_laps'::regclass
     or (select i.indnatts from pg_index i where i.indexrelid = 'public.standing_route_laps_window'::regclass) <> 4
     or (select array_agg(a.attname order by u.ord)
           from pg_index i
           cross join lateral unnest(string_to_array(i.indkey::text, ' ')::int2[]) with ordinality u(attnum, ord)
           join pg_attribute a on a.attrelid = i.indrelid and a.attnum = u.attnum
          where i.indexrelid = 'public.standing_route_laps_window'::regclass)
        is distinct from array['closed_at', 'route_id', 'net', 'lap_no']
     or (select pg_get_expr(i.indpred, i.indrelid) from pg_index i where i.indexrelid = 'public.standing_route_laps_window'::regclass)
        not like '%lap_no >= 2%' then
    raise exception '0287 self-assert FAIL: standing_route_laps_window is not standing_route_laps(closed_at) INCLUDE (route_id, net, lap_no) WHERE lap_no >= 2: %',
      pg_get_indexdef('public.standing_route_laps_window'::regclass);
  end if;

  -- (e) THE READ over probe count rows ten days ahead: every section, and the measured ms
  if exists (select 1 from public.stats_world w where w.at >= v_anchor - interval '1 day' and w.at < v_anchor + interval '1 day') then
    raise exception '0287 self-assert FAIL: a stats row sits at the read probe''s anchor — the instants are not free';
  end if;
  begin
    insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside,
                                    minted, removed, moved, sold, bought, units, trades, period, recent, n)
    values
      (public.drift_slot_of(v_anchor - interval '2 hours'), v_anchor - interval '2 hours', 0, 0, 0, 0, 0, 100, 1, 10, 1, 4, 10, 1, '{"TAX": 2}'::jsonb, '{}'::jsonb, 1),
      (public.drift_slot_of(v_anchor - interval '1 hour'),  v_anchor - interval '1 hour',  0, 0, 0, 0, 0, 200, 2, 20, 2, 5, 20, 2, '{"TAX": 2}'::jsonb, '{}'::jsonb, 1),
      (public.drift_slot_of(v_anchor),                      v_anchor,                      0, 0, 0, 0, 0, 300, 3, 30, 3, 6, 30, 3, '{"TAX": 2}'::jsonb, '{}'::jsonb, 1);
    v_t0 := clock_timestamp();
    v_o := world.stats_overview(24, '1d');
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
    v_t0 := clock_timestamp();
    v_o2 := world.stats_overview(24, '1w');
    v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
    if v_o is null or v_o2 is null or v_ms is null or v_ms2 is null then
      raise exception '0287 self-assert FAIL: the read did not answer';
    end if;
    if v_ms >= 120000 or v_ms2 >= 120000 then
      raise exception '0287 self-assert FAIL: the read answered outside the API''s own 120 s wall (1d % ms, 1w % ms)', v_ms, v_ms2;
    end if;
    if v_o->>'span' is distinct from '1d' or v_o2->>'span' is distinct from '1w' then
      raise exception '0287 self-assert FAIL: the read does not echo its span (% / %)', v_o->>'span', v_o2->>'span';
    end if;
    if (v_o->>'counted_at')::timestamptz is distinct from v_anchor then
      raise exception '0287 self-assert FAIL: the read''s counted_at is %, not the probe''s newest slot %', v_o->>'counted_at', v_anchor;
    end if;
    if v_o->'holders' is null
       or (v_o->'holders'->>'total')::bigint <> (v_o->'holders'->>'players')::bigint + (v_o->'holders'->>'merchants')::bigint
                                                      + (v_o->'holders'->>'cities')::bigint + (v_o->'holders'->>'set_aside')::bigint then
      raise exception '0287 self-assert FAIL: the read''s holders do not add up: %', v_o->'holders';
    end if;
    if (v_o->'period'->>'trades')::bigint <> 0 or (v_o->'period'->>'sold')::bigint <> 0 or (v_o->'period'->>'minted')::bigint <> 0 then
      raise exception '0287 self-assert FAIL: the read''s period is not empty over the probe''s future anchor: %', v_o->'period';
    end if;
    if (v_o->'day'->>'minted')::bigint <> 600 or (v_o->'day'->>'removed')::bigint <> 6 or (v_o->'day'->>'moved')::bigint <> 60
       or (v_o->'day'->>'sold')::bigint <> 6 or (v_o->'day'->>'bought')::bigint <> 15
       or (v_o->'day'->>'units')::bigint <> 60 or (v_o->'day'->>'trades')::bigint <> 6 then
      raise exception '0287 self-assert FAIL: the read''s day is not the probe rows'' sum: %', v_o->'day';
    end if;
    if jsonb_array_length(v_o->'series') <> 4 or jsonb_array_length(v_o2->'series') <> 4 then
      raise exception '0287 self-assert FAIL: the read''s series lengths are % / %, not 4 / 4', jsonb_array_length(v_o->'series'), jsonb_array_length(v_o2->'series');
    end if;
    if (v_o->'series'->(jsonb_array_length(v_o->'series') - 1)->>'at')::timestamptz is distinct from (v_o->>'at')::timestamptz then
      raise exception '0287 self-assert FAIL: the read''s series does not end at its own now()';
    end if;
    raise exception using errcode = 'ZX287', message = 'rollback';
  exception when sqlstate 'ZX287' then
    null;
  end;

  if exists (select 1 from public.stats_world where at >= v_anchor - interval '1 day' and at < v_anchor + interval '1 day') then
    raise exception '0287 self-assert FAIL: the read probe survived its rollback';
  end if;

  -- (a)(f) no function, registry, wall or switch moved
  for d in select * from defs_before_0287 loop
    select md5(replace(pg_get_functiondef(pr.oid), E'\r', '')) as md5,
           coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg
      into x
      from pg_proc pr where pr.oid = d.fn::regprocedure;
    if x.md5 is distinct from d.md5 or x.acl is distinct from d.acl or x.vol is distinct from d.vol
       or x.secdef is distinct from d.secdef or x.cfg is distinct from d.cfg then
      raise exception '0287 self-assert FAIL: % moved (md5 / ACL / volatility / definer / config) — this file re-cuts no body', d.fn;
    end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> (select fns from before_0287)
     or (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> (select fns_md5 from before_0287) then
    raise exception '0287 self-assert FAIL: a function in public/cmd/world/voyage moved or was added — this file creates none';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0287)
     or (select value from public.world_config where key = 'economy_closed') is distinct from (select economy_closed from before_0287)
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from (select city_treasury_enabled from before_0287) then
    raise exception '0287 self-assert FAIL: the registry or an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0287 self-assert FAIL: a wall moved';
  end if;

  raise notice '0287 self-assert ok: THE STATS READ TOUCHES ONLY THE ROWS IT SERVES. Three indexes, no body re-cut: events_trades_window (created_at INCLUDE id/kind/player_id/payload, kind SOLD/BOUGHT), ledger_founded_window (created_at, kind FOUNDING/NPC_REFOUND), standing_route_laps_window (closed_at INCLUDE route_id/net/lap_no, lap 2+). Every function in public/cmd/world/voyage unmoved by md5 (% functions); registry % unchanged; walls 0; both owner switches as found. Probe (2004-06-01, its own rows, planted twice and rolled back and asserted gone): without the indexes sold 1600 / bought 500 / units 25 / trades 4, the good 15 / 10, the city income 530 / spending 1600 / taxes 30 / sold 15 / bought 10, kinds SELL -1600 / BUY 500 / TAX 30 / FOUNDING 500 / NPC_REFOUND 300; with the indexes the answers are byte-identical, and each index is valid, ready and exactly as declared (table, key / INCLUDE columns, predicate — from the catalog, never a planner's choice; prod plans and timings are the measured record). The read over probe counts: world.stats_overview(24,''1d'') % ms, (24,''1w'') % ms, sections and holders intact (prod before this file: 17.1 s and >110 s / 57014); prod''s one-time journal backlog folds at the next successful count.',
    (select fns from before_0287), (select entry_points from before_0287), v_ms, v_ms2;
end $probe2$;
