-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0316 — GRAPHS BY DAY, WEEK AND MONTH: one small row a day per subject; a week and a month are those rows grouped
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05 (row 289): "beside these, the market data, as well as gold earned data / loss graphs record. i want to be able to see them by days, weeks,
-- months. how much data can we store? i want to optimize data storage, for example just having a record on graph would be enough or something."
-- docs/dev-log/2026-11-05-history-graphs.md holds every measurement, the storage answer and what history is gone for good.
--
-- WHAT THIS FILE ADDS (nothing live changes: no game function is touched, asserted)
--   1. FOUR DAILY TABLES, ONE ROW PER (SUBJECT, UTC DAY), THE ONE AUTHORITY OF A GRAPH:
--        history_world_day    the four holders at the day's end; printed, burned, sold, bought in the day
--        history_city_day     purse at the day's end; income, spending, profit in the day (profit by public.flow_is_profit, 0312's one list)
--        history_good_day     the mean market price's open, high, low, close; units sold and bought
--        history_company_day  each player's and merchant company's gold earned and lost
--   2. public.history_bucket(day, period): THE ONE RULE OF A PERIOD. A week is Monday to Sunday, a month a calendar month, both UTC like stats_bucket.
--   3. public.history_fill_day(day): the world, city and good rows of one UTC day, from public.stats_world / stats_city / stats_good. A recount, so it can run
--      any number of times, and a row that did not change is not written.
--   4. public.ledger_is_earning(kind), public.history_ledger_add(from, to): the company rows, ADDED from one window of public.ledger, READ ONLY. Earned is
--      money in, lost is money out, as world.report reads the same rows: FOUNDING and PROBE_ out, and NPC_REFOUND (capital) and NPC_CARRIED (a merchant's old
--      rows rolled into one) out with them.
--   5. public.tick_history(now), pg_cron byeharu-voyage:history at 12, 27, 42, 57: its own small job, six minutes after each Stats count, never in the beat. It
--      moves the ledger window, closes one past day a run and recounts today. public.history_runs keeps each run's receipt for 7 days: its cost, measured on prod.
--   6. world.history(what, subject, period): the client's one read. 120 periods. Public for the world, a city, a good and a merchant company; 'me' is the
--      caller's own; a player's books are never served to anyone else.
--   7. public.history_trim(now): knob stats_city_good_keep_days, 0 = OFF, and it ships OFF. See TRIM below.
--
-- DECIDED BY DEFAULT (owner may reverse):
--   - WEEK AND MONTH ARE NOT STORED. They are a GROUP BY over the day rows in one function, so they cannot disagree with the days, and they cost no bytes. The
--     brief's "one row per (subject, period)" is met for the day; storing the other two would add 18 % and a second writer for nothing a reader could feel:
--     the widest read, 120 months, is about 3,650 index-ordered rows of one subject.
--   - A BACKFILL IS NOT IN THIS FILE. The job closes one past day a run from the oldest public.stats_world row, the same path that heals a dead job, so the file
--     runs in milliseconds and the 16 days fill in about four hours. The ledger's first window is all of it: 0.5 s measured on prod.
--   - NO FOREIGN KEY: a history row outlives its subject, and a key would make the job take a share lock per row on goods, ports and players.
--   - THE LEDGER WINDOW STOPS history_ledger_lag_seconds (600) BEFORE NOW: created_at is the writer's transaction start, so a row can commit after its own instant,
--     and an additive job that passed it would miss it for ever. A merchant's rows live npc_retention_hours (6), so the job may stop for about 5 hours and lose
--     nothing; past that the rows are rolled into NPC_CARRIED and those hours read as nothing. docs/OPS_HEALTH.md alerts at 45 minutes.
--   - FLOWS BEFORE 2026-10-23 ARE NULL, NOT SMALL: 0214's old retention kept one 15-minute row of those days, so a sum of it would draw a day as nearly nothing.
--     The state on those days (a purse, a holder, a price) is true and is kept.
--
-- TRIM: stats_city_good is the fastest grower (about 800 KB a day for ever) and nothing reads its old rows: its one reader, world.stats_city, reads the newest slot,
-- the last 24 hours, the row at 24 hours, and the newest 24 prices of a pair. public.history_trim deletes rows older than the knob, 20,000 a run, and never younger
-- than 3 days. Whether to light it is the owner's: it is a retention knob, and it ships at 0.
--
-- NOT TOUCHED: public.ledger's rows and meaning, public.tick_stats, public.stats_compact, world.report, every beat, every switch. The ledger is read only.
--
-- SELF-ASSERT: on probe rows alone, on days no real row has (2099, and a 2004 day for the flows rule), all rolled back. No real game step, no real row counted. THE REAL JOB
-- OVER THE WHOLE WORLD IS PROVED IN CI: proof 25, scripts/db/proofs/25_history.sql. Mutation controls: scripts/ops/harness/history/proof-0316.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. The one index is on a table of hundreds of rows. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): docs/dev-log/2026-11-05-history-graphs.md. Stop at once: cron.unschedule('byeharu-voyage:history'); nothing in play reads these tables.
-- VERSION: 0316 - prod head 0312 when cut, deploys after 0313, 0314 and 0315 (2026-11-05).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_fn_before text;
  v_fn_after  text;
  v_cfg_before text;
  v_cfg_after  text;
  v_cron_before text;
  v_cron_after  text;
  v_trig_before text;
  v_trig_after  text;
  v_new_fn    constant text[] := array[
    'public.history_bucket(date,text)', 'public.history_fill_day(date)', 'public.ledger_is_earning(text)', 'public.history_ledger_add(timestamp with time zone,timestamp with time zone)',
    'public.history_trim(timestamp with time zone)', 'public.tick_history(timestamp with time zone)', 'world.history(text,text,text)'];
  v_res  jsonb;
  v_x    jsonb;
  v_n    int;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.flow_is_profit(text)') is null or to_regclass('public.stats_city') is null or to_regclass('public.stats_good') is null then
    raise exception '0316 refuses: 0214 / 0312 (the figures, the profit list) are not in this world';
  end if;
  if to_regclass('public.history_world_day') is not null then
    raise exception '0316 refuses: it has been applied once';
  end if;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_before from pg_trigger t where not t.tgisinternal;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 1. THE TABLES ──
  create table public.history_world_day (
    day        date primary key,
    players    bigint not null,
    merchants  bigint not null,
    cities     bigint not null,
    set_aside  bigint not null,
    minted     bigint,
    removed    bigint,
    sold       bigint,
    bought     bigint
  );
  create table public.history_city_day (
    port_id    uuid not null,
    day        date not null,
    purse      bigint not null,
    income     bigint,
    spending   bigint,
    profit     bigint,
    primary key (port_id, day)
  );
  create table public.history_good_day (
    good_id    uuid not null,
    day        date not null,
    open       numeric(12,4),
    high       numeric(12,4),
    low        numeric(12,4),
    close      numeric(12,4),
    sold       bigint,
    bought     bigint,
    primary key (good_id, day)
  );
  create table public.history_company_day (
    player_id  uuid not null,
    day        date not null,
    earned     bigint not null default 0,
    lost       bigint not null default 0,
    primary key (player_id, day)
  );
  -- where the job has got to: ONE row. ledger_through: the ledger is added up to here. open_day: the oldest day not yet closed; null until the first run.
  create table public.history_mark (
    id             boolean primary key default true check (id),
    ledger_through timestamptz not null default '2000-01-01 00:00:00+00',
    open_day       date
  );
  insert into public.history_mark (id) values (true);
  create table public.history_runs (
    at      timestamptz primary key,
    ms      numeric not null,
    receipt jsonb not null
  );
  alter table public.history_world_day   enable row level security;
  alter table public.history_city_day    enable row level security;
  alter table public.history_good_day    enable row level security;
  alter table public.history_company_day enable row level security;
  alter table public.history_mark        enable row level security;
  alter table public.history_runs        enable row level security;
  revoke all on table public.history_world_day, public.history_city_day, public.history_good_day, public.history_company_day, public.history_mark, public.history_runs
    from public, anon, authenticated;

  -- a day's worth of stats_world rows is found by `at`, as its siblings stats_good and stats_city are: this table is kept hourly for ever
  create index stats_world_at on public.stats_world (at);

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('history_ledger_lag_seconds', to_jsonb(600),
     '0316: public.tick_history adds the ledger up to this many seconds before now, because a row''s created_at is its writer''s transaction start and it may commit later. Must stay below npc_retention_hours, or a merchant''s rows are rolled away unread.'),
    ('stats_city_good_keep_days', to_jsonb(0),
     '0316: public.tick_history deletes stats_city_good rows older than this many days, 20,000 a run. 0 = OFF, nothing is deleted. Never below 3 days. Nothing reads the old rows (docs/dev-log/2026-11-05-history-graphs.md); owner decision.');

  -- ── 3. THE RULE OF A PERIOD ──
  execute $f$
create function public.history_bucket(p_day date, p_period text)
returns date
language plpgsql
immutable
set search_path = public, pg_temp
as $body$
begin
  -- 0316: THE ONE RULE OF A PERIOD: the first day of the period a UTC day stands in. A week starts on Monday.
  if p_period = 'day' then
    return p_day;
  elsif p_period = 'week' then
    return date_trunc('week', p_day::timestamp)::date;
  elsif p_period = 'month' then
    return date_trunc('month', p_day::timestamp)::date;
  end if;
  raise exception 'E_BAD_PERIOD: a graph is by day, week or month, not %', coalesce(p_period, 'null') using errcode = 'P0001';
end
$body$
  $f$;

  -- ── 4. ONE DAY OF THE WORLD, THE CITIES AND THE GOODS ──
  execute $f$
create function public.history_fill_day(p_day date)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0316: the day rows of the world, the cities and the goods, recounted from the Stats tables, whatever tier their rows now stand in: a fold adds a row's flows and keeps its last
-- state in the same UTC day, so a day adds to the same figures at any age. A state is the day's last, a flow its sum. A row that did not change is not written.
declare
  c_flows_from constant date := date '2026-10-23';   -- 0214's old retention kept one 15-minute row of each day before this: those flows are gone, not small
  v_flows boolean := p_day >= c_flows_from;
  v_lo    timestamptz := p_day::timestamp at time zone 'UTC';
  v_hi    timestamptz := (p_day + 1)::timestamp at time zone 'UTC';
  v_w     int;
  v_c     int;
  v_g     int;
begin
  insert into public.history_world_day as t (day, players, merchants, cities, set_aside, minted, removed, sold, bought)
  select p_day,
         (array_agg(w.players order by w.at desc))[1], (array_agg(w.merchants order by w.at desc))[1],
         (array_agg(w.cities order by w.at desc))[1], (array_agg(w.set_aside order by w.at desc))[1],
         case when v_flows then sum(w.minted)::bigint end, case when v_flows then sum(w.removed)::bigint end,
         case when v_flows then sum(w.sold)::bigint end, case when v_flows then sum(w.bought)::bigint end
    from public.stats_world w
   where w.at >= v_lo and w.at < v_hi
  having count(*) > 0
  on conflict (day) do update
     set players = excluded.players, merchants = excluded.merchants, cities = excluded.cities, set_aside = excluded.set_aside,
         minted = excluded.minted, removed = excluded.removed, sold = excluded.sold, bought = excluded.bought
   where (t.players, t.merchants, t.cities, t.set_aside, t.minted, t.removed, t.sold, t.bought)
         is distinct from (excluded.players, excluded.merchants, excluded.cities, excluded.set_aside, excluded.minted, excluded.removed, excluded.sold, excluded.bought);
  get diagnostics v_w = row_count;

  insert into public.history_city_day as t (port_id, day, purse, income, spending, profit)
  select c.port_id, p_day, (array_agg(c.purse order by c.at desc))[1],
         case when v_flows then sum(c.income)::bigint end, case when v_flows then sum(c.spending)::bigint end,
         case when v_flows then coalesce(sum((select sum(e.value::numeric) from jsonb_each_text(c.flows) e where public.flow_is_profit(e.key))), 0)::bigint end
    from public.stats_city c
   where c.at >= v_lo and c.at < v_hi
   group by c.port_id
  on conflict (port_id, day) do update
     set purse = excluded.purse, income = excluded.income, spending = excluded.spending, profit = excluded.profit
   where (t.purse, t.income, t.spending, t.profit) is distinct from (excluded.purse, excluded.income, excluded.spending, excluded.profit);
  get diagnostics v_c = row_count;

  insert into public.history_good_day as t (good_id, day, open, high, low, close, sold, bought)
  select g.good_id, p_day,
         (array_agg(g.mid order by g.at) filter (where g.mid is not null))[1], max(g.mid), min(g.mid),
         (array_agg(g.mid order by g.at desc) filter (where g.mid is not null))[1],
         case when v_flows then sum(g.sold)::bigint end, case when v_flows then sum(g.bought)::bigint end
    from public.stats_good g
   where g.at >= v_lo and g.at < v_hi
   group by g.good_id
  having count(g.mid) > 0 or sum(g.sold) > 0 or sum(g.bought) > 0   -- a good no market sells and nobody traded takes no row
  on conflict (good_id, day) do update
     set open = excluded.open, high = excluded.high, low = excluded.low, close = excluded.close, sold = excluded.sold, bought = excluded.bought
   where (t.open, t.high, t.low, t.close, t.sold, t.bought) is distinct from (excluded.open, excluded.high, excluded.low, excluded.close, excluded.sold, excluded.bought);
  get diagnostics v_g = row_count;

  return jsonb_build_object('day', p_day, 'world', v_w, 'cities', v_c, 'goods', v_g);
end
$body$
  $f$;

  -- ── 5. EARNED AND LOST ──
  execute $f$
create function public.ledger_is_earning(p_kind text)
returns boolean
language sql
immutable
as $body$
  -- 0316: what a company's graph counts: world.report's rows (FOUNDING is capital, a PROBE_ row never shows), and of a merchant's own kinds not NPC_REFOUND (capital again) nor
  -- NPC_CARRIED (her old rows rolled into one, already counted when they were new).
  select p_kind not in ('FOUNDING', 'NPC_REFOUND', 'NPC_CARRIED') and left(p_kind, 6) <> 'PROBE_'
$body$
  $f$;

  execute $f$
create function public.history_ledger_add(p_from timestamptz, p_to timestamptz)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0316: adds the ledger rows of the window (p_from, p_to] to each company's days. It reads public.ledger and never writes it. It ADDS, so it runs once per window:
-- public.tick_history moves the mark in the same transaction. Each row counts on its own UTC day.
declare
  v_n int;
begin
  insert into public.history_company_day as t (player_id, day, earned, lost)
  select l.player_id, (l.created_at at time zone 'UTC')::date,
         coalesce(sum(l.ducats_delta) filter (where l.ducats_delta > 0), 0)::bigint,
         coalesce(-sum(l.ducats_delta) filter (where l.ducats_delta < 0), 0)::bigint
    from public.ledger l
   where l.created_at > p_from and l.created_at <= p_to
     and public.ledger_is_earning(l.kind)
   group by 1, 2
  on conflict (player_id, day) do update
     set earned = t.earned + excluded.earned, lost = t.lost + excluded.lost;
  get diagnostics v_n = row_count;
  return v_n;
end
$body$
  $f$;

  -- ── 6. THE TRIM, OFF ──
  execute $f$
create function public.history_trim(p_now timestamptz)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0316: knob stats_city_good_keep_days, 0 = OFF. Deletes 20,000 stats_city_good rows a run older than the knob, and never a row younger than 3 days: world.stats_city
-- reads the last 24 hours and the row at 24 hours. Its other tables are not trimmed: their old rows are read by the year and All charts.
declare
  v_keep int := public.wc_int('stats_city_good_keep_days');
  v_n    int;
begin
  if v_keep <= 0 then
    return 0;
  end if;
  delete from public.stats_city_good s
   where s.ctid = any (array(select x.ctid from public.stats_city_good x
                              where x.at < p_now - make_interval(days => greatest(v_keep, 3))
                              limit 20000));
  get diagnostics v_n = row_count;
  return v_n;
end
$body$
  $f$;

  -- ── 7. THE JOB ──
  execute $f$
create function public.tick_history(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0316: pg_cron byeharu-voyage:history at 12, 27, 42, 57, six minutes after each Stats count, never in the beat. One run: the ledger's new window; the oldest open day, closed if it is
-- a past one (one a run, so a backfill and the day after a dead job are the same path); today; the trim, off by default. It writes history_* alone, and takes no lock on a game table.
declare
  v_t0    timestamptz := clock_timestamp();
  v_tp    timestamptz := clock_timestamp();
  v_ph    jsonb := '{}'::jsonb;
  v_today date := (p_now at time zone 'UTC')::date;
  v_hi    timestamptz := p_now - make_interval(secs => public.wc_num('history_ledger_lag_seconds')::double precision);
  m       public.history_mark%rowtype;
  v_led   int := 0;
  v_open  date;
  v_past  jsonb;
  v_now   jsonb;
  v_trim  int;
  v_ret   jsonb;
begin
  perform set_config('lock_timeout', '2s', true);
  select * into m from public.history_mark for update skip locked;
  if not found then
    return jsonb_build_object('busy', true);   -- a run is still at work
  end if;

  if v_hi > m.ledger_through then
    v_led := public.history_ledger_add(m.ledger_through, v_hi);
    m.ledger_through := v_hi;
  end if;
  v_ph := v_ph || jsonb_build_object('ledger', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();

  v_open := least(coalesce(m.open_day, (select (w.at at time zone 'UTC')::date from public.stats_world w order by w.at limit 1), v_today), v_today);
  if v_open < v_today then
    v_past := public.history_fill_day(v_open);
    v_open := v_open + 1;
  end if;
  v_ph := v_ph || jsonb_build_object('past', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();
  v_now := public.history_fill_day(v_today);
  v_ph := v_ph || jsonb_build_object('today', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();

  update public.history_mark set ledger_through = m.ledger_through, open_day = v_open;
  v_trim := public.history_trim(p_now);
  v_ph := v_ph || jsonb_build_object('trim', public.beat_ms(clock_timestamp() - v_tp));

  v_ret := jsonb_build_object('at', p_now, 'ledger_through', m.ledger_through, 'ledger_rows', v_led, 'open_day', v_open, 'past', v_past, 'today', v_now, 'trimmed', v_trim,
                              'phases', v_ph, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  insert into public.history_runs (at, ms, receipt) values (p_now, (v_ret->>'ms')::numeric, v_ret)
    on conflict (at) do update set ms = excluded.ms, receipt = excluded.receipt;
  delete from public.history_runs where at < p_now - interval '7 days';
  return v_ret;
end
$body$
  $f$;

  -- ── 8. THE ONE READ ──
  execute $f$
create function world.history(p_what text, p_subject text default null, p_period text default 'day')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0316: the newest 120 days, weeks or months of one subject, oldest first. Each point stands at its period's first day (UTC). A flow adds; a state is the period's last day's; a price is
-- first open, highest high, lowest low, last close. p_what: world | city (port code) | good (good code) | company (a merchant company's name) | me (the caller; a player's books are nobody else's).
declare
  c_points constant int := 120;
  v_first  date := public.history_bucket((now() at time zone 'UTC')::date, p_period);   -- a bad period raises here
  v_since  date := case p_period when 'day' then v_first - (c_points - 1)
                                 when 'week' then v_first - 7 * (c_points - 1)
                                 else (v_first::timestamp - make_interval(months => c_points - 1))::date end;
  v_id     uuid;
  v_points jsonb;
begin
  if p_what = 'world' then
    select coalesce(jsonb_agg(jsonb_build_object('at', to_char(x.b, 'YYYY-MM-DD"T"00:00:00"Z"'), 'players', x.players, 'merchants', x.merchants, 'cities', x.cities, 'set_aside', x.set_aside,
                                                 'minted', x.minted, 'removed', x.removed, 'sold', x.sold, 'bought', x.bought) order by x.b), '[]'::jsonb) into v_points
      from (select public.history_bucket(h.day, p_period) as b,
                   (array_agg(h.players order by h.day desc))[1] as players, (array_agg(h.merchants order by h.day desc))[1] as merchants,
                   (array_agg(h.cities order by h.day desc))[1] as cities, (array_agg(h.set_aside order by h.day desc))[1] as set_aside,
                   sum(h.minted)::bigint as minted, sum(h.removed)::bigint as removed, sum(h.sold)::bigint as sold, sum(h.bought)::bigint as bought
              from public.history_world_day h where h.day >= v_since group by 1) x;
  elsif p_what = 'city' then
    select p.id into v_id from public.ports p where p.code = p_subject and p.kind = 'HARBOUR';
    if v_id is null then
      raise exception 'E_NO_SUCH_PORT: no harbour has that code' using errcode = 'P0001';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('at', to_char(x.b, 'YYYY-MM-DD"T"00:00:00"Z"'), 'purse', x.purse, 'income', x.income, 'spending', x.spending, 'profit', x.profit) order by x.b), '[]'::jsonb) into v_points
      from (select public.history_bucket(h.day, p_period) as b, (array_agg(h.purse order by h.day desc))[1] as purse,
                   sum(h.income)::bigint as income, sum(h.spending)::bigint as spending, sum(h.profit)::bigint as profit
              from public.history_city_day h where h.port_id = v_id and h.day >= v_since group by 1) x;
  elsif p_what = 'good' then
    select g.id into v_id from public.goods g where g.code = p_subject;
    if v_id is null then
      raise exception 'E_NO_SUCH_GOOD: no good has that code' using errcode = 'P0001';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('at', to_char(x.b, 'YYYY-MM-DD"T"00:00:00"Z"'), 'open', x.open, 'high', x.high, 'low', x.low, 'close', x.close, 'sold', x.sold, 'bought', x.bought) order by x.b), '[]'::jsonb) into v_points
      from (select public.history_bucket(h.day, p_period) as b,
                   (array_agg(h.open order by h.day) filter (where h.open is not null))[1] as open, max(h.high) as high, min(h.low) as low,
                   (array_agg(h.close order by h.day desc) filter (where h.close is not null))[1] as close,
                   sum(h.sold)::bigint as sold, sum(h.bought)::bigint as bought
              from public.history_good_day h where h.good_id = v_id and h.day >= v_since group by 1) x;
  elsif p_what in ('company', 'me') then
    if p_what = 'me' then
      v_id := public.current_player_id();
      if v_id is null then
        raise exception 'E_NO_PLAYER: there is no company signed in' using errcode = 'P0001';
      end if;
    else
      select p.id into v_id from public.players p where p.company_name = p_subject and p.is_npc;
      if v_id is null then
        raise exception 'E_NOT_PUBLIC: only a merchant company''s books are public' using errcode = 'P0001';
      end if;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('at', to_char(x.b, 'YYYY-MM-DD"T"00:00:00"Z"'), 'earned', x.earned, 'lost', x.lost) order by x.b), '[]'::jsonb) into v_points
      from (select public.history_bucket(h.day, p_period) as b, sum(h.earned)::bigint as earned, sum(h.lost)::bigint as lost
              from public.history_company_day h where h.player_id = v_id and h.day >= v_since group by 1) x;
  else
    raise exception 'E_BAD_HISTORY: a graph is of the world, a city, a good, a company or you, not %', coalesce(p_what, 'null') using errcode = 'P0001';
  end if;
  return jsonb_build_object('what', p_what, 'subject', p_subject, 'period', p_period, 'points', v_points);
end
$body$
  $f$;

  revoke all on function public.history_bucket(date, text) from public, anon, authenticated;
  revoke all on function public.history_fill_day(date) from public, anon, authenticated;
  revoke all on function public.ledger_is_earning(text) from public, anon, authenticated;
  revoke all on function public.history_ledger_add(timestamptz, timestamptz) from public, anon, authenticated;
  revoke all on function public.history_trim(timestamptz) from public, anon, authenticated;
  revoke all on function public.tick_history(timestamptz) from public, anon, authenticated;
  revoke all on function world.history(text, text, text) from public, anon, authenticated;
  grant execute on function world.history(text, text, text) to authenticated;

  -- ── 9. THE JOB'S CLOCK ──
  if to_regclass('cron.job') is not null then
    execute $q$select cron.schedule('byeharu-voyage:history', '12,27,42,57 * * * *', 'select public.tick_history()')$q$;
  end if;

  -- ── 10. THE SELF-ASSERT: catalog first, then a scene of probe rows on days no real row has, rolled back ──
  if exists (select 1 from unnest(array['history_world_day', 'history_city_day', 'history_good_day', 'history_company_day', 'history_mark', 'history_runs']) t(n)
              join pg_class c on c.relname = t.n and c.relnamespace = 'public'::regnamespace
             where not c.relrowsecurity
                or has_table_privilege('anon', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select')) then
    raise exception '0316 self-assert FAIL: a client can reach a history table';
  end if;
  if has_function_privilege('anon', 'world.history(text,text,text)', 'execute') or not has_function_privilege('authenticated', 'world.history(text,text,text)', 'execute') then
    raise exception '0316 self-assert FAIL: world.history is not for signed-in players alone';
  end if;
  if exists (select 1 from unnest(v_new_fn) f where f <> 'world.history(text,text,text)'
              and (has_function_privilege('authenticated', to_regprocedure(f), 'execute') or has_function_privilege('anon', to_regprocedure(f), 'execute'))) then
    raise exception '0316 self-assert FAIL: a client can run the job';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'world.history(text,text,text)'::regprocedure and p.provolatile = 's' and p.prosecdef) then
    raise exception '0316 self-assert FAIL: world.history is not a stable read';
  end if;
  if public.history_bucket(date '2026-11-05', 'week') <> date '2026-11-02' or public.history_bucket(date '2026-11-08', 'week') <> date '2026-11-02'
     or public.history_bucket(date '2026-11-09', 'week') <> date '2026-11-09' or public.history_bucket(date '2026-11-30', 'month') <> date '2026-11-01'
     or public.history_bucket(date '2026-11-30', 'day') <> date '2026-11-30' then
    raise exception '0316 self-assert FAIL: a period is not Monday to Sunday, a calendar month, a day';
  end if;
  begin
    perform public.history_bucket(current_date, 'year');
    raise exception '0316 self-assert FAIL: a year was accepted as a period';
  exception when others then
    if sqlerrm not like 'E_BAD_PERIOD%' then raise; end if;
  end;

  declare
    c_a    constant uuid := '00000000-0316-4000-8000-00000000000a';
    d0     date := public.history_bucket(date '2099-03-10', 'week');   -- a Monday
    v_city record;
    v_good record;
    v_pa   uuid;
    v_pb   uuid;
    v_nat  uuid := (select g.nation_id from public.great_powers g order by g.nation_id limit 1);
    v_at   timestamptz := now();
    v_s    bigint := 9000000000000;
  begin
    select p.id, p.code into v_city from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
    select g.id, g.code into v_good from public.goods g order by g.code limit 1;

    -- the world, two rows of one day: the later one goes in first, so a state that took the row order would read the wrong one
    insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside, minted, removed, moved, sold, bought, units, trades, period, recent, n)
    values (v_s + 2, (d0 + 0)::timestamp at time zone 'UTC' + interval '20 hours', 1, 150, 250, 350, 450, 20, 2, 0, 200, 20, 0, 0, '{}', '{}', 4),
           (v_s + 1, (d0 + 0)::timestamp at time zone 'UTC', 1, 100, 200, 300, 400, 10, 1, 0, 100, 10, 0, 0, '{}', '{}', 4),
           (v_s + 3, (d0 + 1)::timestamp at time zone 'UTC', 1, 1, 2, 3, 4, 7, 3, 0, 70, 30, 0, 0, '{}', '{}', 4),    -- midnight is the next day's first instant
           (v_s + 4, (d0 + 2)::timestamp at time zone 'UTC' + interval '1 hour', 1, 11, 12, 13, 14, 5, 5, 0, 50, 50, 0, 0, '{}', '{}', 4);
    insert into public.stats_city (port_id, slot, at, purse, income, spending, taxes, works, sold, bought, flows, n)
    values (v_city.id, v_s + 2, (d0 + 0)::timestamp at time zone 'UTC' + interval '20 hours', 700, 7, 2, 0, 0, 0, 0, '{"SELL":7,"DIVIDEND":-2}', 4),
           (v_city.id, v_s + 1, (d0 + 0)::timestamp at time zone 'UTC' + interval '10 hours', 500, 8, 1, 0, 0, 0, 0, '{"SELL":5,"CROWN_AID":3,"BUY":-1}', 4),
           (v_city.id, v_s + 3, (d0 + 2)::timestamp at time zone 'UTC', 900, 3, 4, 0, 0, 0, 0, '{"SELL":3,"BUY":-4}', 4),
           (v_city.id, v_s + 4, (d0 + 7)::timestamp at time zone 'UTC', 1100, 1, 0, 0, 0, 0, 0, '{"SELL":1}', 4);
    insert into public.stats_good (good_id, slot, at, mid, markets, stock, stock_target, sold, bought, sold_ducats, bought_ducats, n)
    values (v_good.id, v_s + 4, (d0 + 0)::timestamp at time zone 'UTC' + interval '23 hours', null, 1, 0, 0, 1, 0, 0, 0, 4),
           (v_good.id, v_s + 3, (d0 + 0)::timestamp at time zone 'UTC' + interval '22 hours', 12, 1, 0, 0, 2, 3, 0, 0, 4),
           (v_good.id, v_s + 2, (d0 + 0)::timestamp at time zone 'UTC' + interval '10 hours', 8, 1, 0, 0, 0, 0, 0, 0, 4),
           (v_good.id, v_s + 1, (d0 + 0)::timestamp at time zone 'UTC' + interval '1 hour', 10, 1, 0, 0, 0, 0, 0, 0, 4),
           (v_good.id, v_s + 5, (d0 + 0)::timestamp at time zone 'UTC' + interval '5 hours', 14, 1, 0, 0, 0, 0, 0, 0, 4),
           (v_good.id, v_s + 6, (d0 + 1)::timestamp at time zone 'UTC' + interval '5 hours', 20, 1, 0, 0, 4, 0, 0, 0, 4),
           (v_good.id, v_s + 7, (d0 + 2)::timestamp at time zone 'UTC' + interval '5 hours', 6, 1, 0, 0, 0, 1, 0, 0, 4),
           (v_good.id, v_s + 8, (d0 + 2)::timestamp at time zone 'UTC' + interval '6 hours', 9, 1, 0, 0, 0, 0, 0, 0, 4);

    perform public.history_fill_day(d0);
    perform public.history_fill_day(d0 + 1);
    perform public.history_fill_day(d0 + 2);
    perform public.history_fill_day(d0 + 7);

    v_x := (select to_jsonb(h) from public.history_world_day h where h.day = d0);
    if (v_x ->> 'players')::bigint is distinct from 150 or (v_x ->> 'set_aside')::bigint is distinct from 450 then
      raise exception '0316 self-assert FAIL: a state is not the day''s last: %', v_x;
    end if;
    if (v_x ->> 'minted')::bigint is distinct from 30 or (v_x ->> 'removed')::bigint is distinct from 3 or (v_x ->> 'sold')::bigint is distinct from 300 or (v_x ->> 'bought')::bigint is distinct from 30 then
      raise exception '0316 self-assert FAIL: a flow is not the day''s sum: %', v_x;
    end if;
    if (select h.players from public.history_world_day h where h.day = d0 + 1) <> 1 then
      raise exception '0316 self-assert FAIL: midnight does not start the next day';
    end if;
    v_x := (select to_jsonb(h) from public.history_city_day h where h.port_id = v_city.id and h.day = d0);
    if (v_x ->> 'purse')::bigint is distinct from 700 or (v_x ->> 'income')::bigint is distinct from 15 or (v_x ->> 'spending')::bigint is distinct from 3 then
      raise exception '0316 self-assert FAIL: a city''s day is wrong: %', v_x;
    end if;
    if (v_x ->> 'profit')::bigint is distinct from 11 then
      raise exception '0316 self-assert FAIL: a city''s profit is not by public.flow_is_profit: %', v_x;
    end if;
    v_x := (select to_jsonb(h) from public.history_good_day h where h.good_id = v_good.id and h.day = d0);
    if (v_x ->> 'open')::numeric is distinct from 10 or (v_x ->> 'high')::numeric is distinct from 14 or (v_x ->> 'low')::numeric is distinct from 8 or (v_x ->> 'close')::numeric is distinct from 12 then
      raise exception '0316 self-assert FAIL: a good''s day is not open, high, low, close: %', v_x;
    end if;
    if (v_x ->> 'sold')::bigint is distinct from 3 or (v_x ->> 'bought')::bigint is distinct from 3 then
      raise exception '0316 self-assert FAIL: a good''s volume is not the day''s sum: %', v_x;
    end if;

    -- a recount writes nothing it does not change
    v_x := public.history_fill_day(d0);
    if (v_x ->> 'cities')::int is distinct from 0 or (v_x ->> 'world')::int is distinct from 0 or (v_x ->> 'goods')::int is distinct from 0 then
      raise exception '0316 self-assert FAIL: a recount rewrote a row that did not change: %', v_x;
    end if;

    -- the week and the month are the days grouped
    v_res := world.history('city', v_city.code, 'week');
    v_x := (select p from jsonb_array_elements(v_res -> 'points') p where p ->> 'at' = to_char(d0, 'YYYY-MM-DD"T"00:00:00"Z"'));
    if (v_x ->> 'purse')::bigint is distinct from 900 or (v_x ->> 'income')::bigint is distinct from 18 or (v_x ->> 'spending')::bigint is distinct from 7 or (v_x ->> 'profit')::bigint is distinct from 10 then
      raise exception '0316 self-assert FAIL: a city''s week is not its days: %', v_x;
    end if;
    v_res := world.history('city', v_city.code, 'month');
    v_x := (select p from jsonb_array_elements(v_res -> 'points') p where p ->> 'at' = to_char(public.history_bucket(d0, 'month'), 'YYYY-MM-DD"T"00:00:00"Z"'));
    if (v_x ->> 'purse')::bigint is distinct from 1100 or (v_x ->> 'income')::bigint is distinct from 19 then
      raise exception '0316 self-assert FAIL: a city''s month is not its days: %', v_x;
    end if;
    v_res := world.history('good', v_good.code, 'week');
    v_x := (select p from jsonb_array_elements(v_res -> 'points') p where p ->> 'at' = to_char(d0, 'YYYY-MM-DD"T"00:00:00"Z"'));
    if (v_x ->> 'open')::numeric is distinct from 10 or (v_x ->> 'high')::numeric is distinct from 20 or (v_x ->> 'low')::numeric is distinct from 6 or (v_x ->> 'close')::numeric is distinct from 9 or (v_x ->> 'sold')::bigint is distinct from 7 then
      raise exception '0316 self-assert FAIL: a good''s week is not first open, highest, lowest, last close: %', v_x;
    end if;
    v_res := world.history('world', null, 'week');
    v_x := (select p from jsonb_array_elements(v_res -> 'points') p where p ->> 'at' = to_char(d0, 'YYYY-MM-DD"T"00:00:00"Z"'));
    if (v_x ->> 'players')::bigint is distinct from 11 or (v_x ->> 'minted')::bigint is distinct from 42 then
      raise exception '0316 self-assert FAIL: the world''s week is not its days: %', v_x;
    end if;
    begin
      perform world.history('city', 'NOT A PORT', 'day');
      raise exception '0316 self-assert FAIL: an unknown city was answered';
    exception when others then
      if sqlerrm not like 'E_NO_SUCH_PORT%' then raise; end if;
    end;
    begin
      perform world.history('nothing', null, 'day');
      raise exception '0316 self-assert FAIL: an unknown subject was answered';
    exception when others then
      if sqlerrm not like 'E_BAD_HISTORY%' then raise; end if;
    end;

    -- before 0214's retention was mended a day kept one row: its flows are unknown, its state is true
    insert into public.stats_city (port_id, slot, at, purse, income, spending, taxes, works, sold, bought, flows, n)
    values (v_city.id, v_s + 9, timestamptz '2004-02-29 12:00:00+00', 42, 5, 5, 0, 0, 0, 0, '{"SELL":5}', 1);
    perform public.history_fill_day(date '2004-02-29');
    v_x := (select to_jsonb(h) from public.history_city_day h where h.port_id = v_city.id and h.day = date '2004-02-29');
    if (v_x ->> 'purse')::bigint is distinct from 42 or v_x ->> 'income' is not null or v_x ->> 'profit' is not null then
      raise exception '0316 self-assert FAIL: a thinned day drew a flow: %', v_x;
    end if;

    -- earned and lost, as the ledger says, and the books stay their owner's
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_a, 'Probe 0316 a', v_nat, 0, false) returning id into v_pa;
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0316 b', v_nat, 0, true) returning id into v_pb;
    -- FOUNDING and NPC_REFOUND are minted kinds: prod's closed economy refuses them through credit (E_NO_NEW_GOLD, the first push of this file, 2026-11-05), so the probe writes their ledger rows itself
    insert into public.ledger (player_id, kind, ducats_delta, balance_after) values (v_pa, 'FOUNDING', 1000, 1000);
    perform public.credit(v_pa, 'SELL', 500);
    perform public.credit(v_pa, 'BUY', -200);
    perform public.credit(v_pa, 'NPC_CARRIED', 77);
    insert into public.ledger (player_id, kind, ducats_delta, balance_after) values (v_pa, 'NPC_REFOUND', 5, 1382);
    perform public.credit(v_pa, 'PROBE_0316', 3);
    perform public.credit(v_pb, 'DIVIDEND', 40);
    perform public.history_ledger_add(v_at, v_at + interval '1 second');   -- the window is (from, to]: these rows stand at its open end
    if exists (select 1 from public.history_company_day h where h.player_id = v_pa) then
      raise exception '0316 self-assert FAIL: a window took a row at its open end';
    end if;
    perform public.history_ledger_add(v_at - interval '1 second', v_at);
    v_x := (select to_jsonb(h) from public.history_company_day h where h.player_id = v_pa);
    if (v_x ->> 'earned')::bigint is distinct from 500 or (v_x ->> 'lost')::bigint is distinct from 200 then
      raise exception '0316 self-assert FAIL: earned and lost are not the ledger''s money in and out: %', v_x;
    end if;
    perform public.history_ledger_add(v_at - interval '1 second', v_at);   -- a second window ADDS: the mark, not this function, is what keeps a row to one count
    if (select h.earned from public.history_company_day h where h.player_id = v_pa) is distinct from 1000 then
      raise exception '0316 self-assert FAIL: a window replaced the day instead of adding to it';
    end if;
    if (v_x ->> 'day')::date <> (v_at at time zone 'UTC')::date then
      raise exception '0316 self-assert FAIL: a row was not counted on its own UTC day: %', v_x;
    end if;
    perform cmd.assume_identity(c_a);
    v_res := world.history('me', null, 'month');
    if (v_res -> 'points' -> 0 ->> 'earned')::bigint is distinct from 1000 or jsonb_array_length(v_res -> 'points') <> 1 then
      raise exception '0316 self-assert FAIL: a company does not read its own books: %', v_res;
    end if;
    v_res := world.history('company', 'Probe 0316 b', 'day');
    if (v_res -> 'points' -> 0 ->> 'earned')::bigint is distinct from 80 then
      raise exception '0316 self-assert FAIL: a merchant company''s books are not public: %', v_res;
    end if;
    begin
      perform world.history('company', 'Probe 0316 a', 'day');
      raise exception '0316 self-assert FAIL: a player''s books were served to another';
    exception when others then
      if sqlerrm not like 'E_NOT_PUBLIC%' then raise; end if;
    end;

    -- the trim: off at 0; the knob's age; never under 3 days. Every row in reach is a probe: nothing real stands before 2005
    insert into public.stats_city_good (port_id, good_id, slot, at, mid, stock, stock_target, sold, bought, sold_ducats, bought_ducats, n)
    values (v_city.id, v_good.id, v_s + 1, timestamptz '2004-01-01 00:00:00+00', 1, 0, 0, 0, 0, 0, 0, 1),
           (v_city.id, v_good.id, v_s + 2, timestamptz '2004-03-05 00:00:00+00', 1, 0, 0, 0, 0, 0, 0, 1),
           (v_city.id, v_good.id, v_s + 3, timestamptz '2004-03-08 00:00:00+00', 1, 0, 0, 0, 0, 0, 0, 1);
    if public.history_trim(timestamptz '2004-03-10 00:00:00+00') <> 0 then
      raise exception '0316 self-assert FAIL: the trim ran at 0';
    end if;
    update public.world_config set value = to_jsonb(8) where key = 'stats_city_good_keep_days';
    if public.history_trim(timestamptz '2004-03-10 00:00:00+00') <> 1 then
      raise exception '0316 self-assert FAIL: the trim is not the knob''s age';
    end if;
    update public.world_config set value = to_jsonb(1) where key = 'stats_city_good_keep_days';
    if public.history_trim(timestamptz '2004-03-10 00:00:00+00') <> 1
       or not exists (select 1 from public.stats_city_good c where c.port_id = v_city.id and c.slot = v_s + 3) then
      raise exception '0316 self-assert FAIL: the trim went under 3 days';
    end if;

    raise exception using errcode = 'ZX316', message = 'the scene is rolled back';
  exception when sqlstate 'ZX316' then
    null;
  end;
  if exists (select 1 from public.players p where p.company_name like 'Probe 0316%')
     or exists (select 1 from public.history_city_day) or exists (select 1 from public.history_company_day) then
    raise exception '0316 self-assert FAIL: the probe left rows behind';
  end if;

  -- nothing else moved
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_after
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select to_regprocedure(f)::oid from unnest(v_new_fn) f));
  if v_fn_after is distinct from v_fn_before then
    raise exception '0316 self-assert FAIL: another function moved';
  end if;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_after
    from public.world_config c where c.key not in ('history_ledger_lag_seconds', 'stats_city_good_keep_days');
  if v_cfg_after is distinct from v_cfg_before then
    raise exception '0316 self-assert FAIL: a world_config row moved';
  end if;
  if public.wc_int('stats_city_good_keep_days') <> 0 then
    raise exception '0316 self-assert FAIL: the trim does not ship off';
  end if;
  if public.wc_num('history_ledger_lag_seconds') >= 3600 * public.wc_int('npc_retention_hours') then
    raise exception '0316 self-assert FAIL: the lag is past the merchants'' retention';
  end if;
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_after from pg_trigger t where not t.tgisinternal;
  if v_trig_after is distinct from v_trig_before then
    raise exception '0316 self-assert FAIL: a trigger moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j where j.jobname <> 'byeharu-voyage:history'$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0316 self-assert FAIL: another cron job moved';
    end if;
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:history' and j.schedule = '12,27,42,57 * * * *' and j.active$q$ into v_n;
    if v_n <> 1 then
      raise exception '0316 self-assert FAIL: the job is not scheduled';
    end if;
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0316 self-assert FAIL: the file ran past its 45 s budget: %', clock_timestamp() - v_t0;
  end if;

  raise notice '0316 self-assert ok: GRAPHS BY DAY, WEEK AND MONTH. history_world_day, history_city_day, history_good_day, history_company_day; world.history; byeharu-voyage:history; stats_city_good_keep_days 0 (off); the real job over the world is proof 25 in CI; ran in %', clock_timestamp() - v_t0;
end $m$;

