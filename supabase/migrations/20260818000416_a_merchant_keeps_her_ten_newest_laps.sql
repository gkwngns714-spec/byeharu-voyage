-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0416 - A MERCHANT KEEPS HER TEN NEWEST LAPS  (the day's figures are read from an hour book, not from a day of lap rows)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
--
-- THE OWNER'S ORDER (2026-11-14, on reading 0409's cuts, verbatim): "do all that. merchant lap records should be newest 10 only, without any
--   hours. pre-city goods statistics - is there a way for it to keep for a longer time? would this cost much?? rest sounds okay"
--
-- WHY IT NEEDS MORE THAN A KNOB (docs/dev-log/2026-11-14-slim-laps.md). A merchant closes about 68 laps a day, so her ten newest are about three
--   and a half hours. Four readers want more of her laps than that: the 24 hours of public.route_earnings (the fleet card's "today"), of
--   world.fleet_trades (the card's day) and of public.stats_merchants_window (the Stats tab's merchants), and the newest 20 of
--   public.npc_share_budget. 0409 kept 26 hours of laps for them (about 65,000 rows). This file gives them something else to read.
--
-- WHAT THIS FILE DOES:
--   1. THE HOUR BOOK. public.route_hour_laps (new): one row per route per hour a lap of it closed in: how many laps, their figures summed (net,
--      sold, bought, supplies, repairs, wages, taxes, insurance, the cargo carried in and out at cost), the same for laps 2 onwards (0097: lap 1
--      holds a purchase and no sale), how many of those lost, the dearest lap, the first and the last close. About 900 rows an hour; kept
--      route_hour_keep_hours (80), trimmed by the compactor, compact_trim_rows a run.
--   2. ITS ONE WRITER IS A TRIGGER on public.standing_route_laps (public.route_hour_post): a lap that closes is added to its hour, in the
--      closing statement's own transaction. cmd.standing_route_close_lap is NOT touched (0410 and 0411 re-cut it). A closed lap whose figures or
--      instant are changed afterwards is taken out of its hour and put in again; a lap DELETED is not taken out: that is the point.
--   3. ONE READING OF A ROUTE'S WINDOW: public.route_day(route, from, to) (new) = the hours wholly inside the window, from the book, plus the
--      laps of the window's two part-hours, from the lap rows that are still there. For a player's route (100 laps kept) and for any window
--      inside a merchant's kept laps that is exact, lap for lap, as before. For a merchant's 24 hours the oldest part-hour's laps are gone:
--      her "today" is the last 23 to 24 hours. public.route_day_full says whether a whole window is held.
--   4. THE FOUR READERS, by hunks: public.route_earnings (day, day_laps, day_since, day_full), world.fleet_trades (the day's totals; the laps
--      listed and the goods by harbour still come from the lap rows, the newest 7 of which carry their trades, as before),
--      public.stats_merchants_window (whole hours from the book, part-hours from the lap rows: the Stats count's 24 hours and the tab's
--      "minutes since" are one function still), public.npc_share_budget (the dearest lap of the last npc_invest_lap_hours (8) from the book:
--      it read the newest 20 laps inside three days, which is about seven hours of a merchant's sailing).
--   5. THE KEEP: npc_route_lap_keep 24 -> 10 and npc_route_lap_keep_hours 26 -> 0 (0 = no hours' window: the newest 10 alone), in
--      public.npc_compact_houses (0409's lines). Never under 10: the fleet card lists 7 and reads 8, the trades are kept on 7. A PLAYER's route
--      keeps standing_route_lap_keep (100), as before.
--   6. THE CITY-GOOD STATISTICS ARE KEPT A MONTH, AT A DAY'S GRAIN: stats_city_good_keep_days 3 -> 30 and stats_city_good_hour_days 7 -> 2.
--      A daily row of every city's every good is about 1,300 rows, 0.3 MB a day with its index; the hourly rows nobody reads (5 days of them
--      were 150,000 rows) pay for it. The table is about the size 0409 left it.
--   7. THE BOOK IS FILLED ONCE from the lap rows that stand (the last 80 hours of them), so every figure is right from the first minute.
--
-- WHAT A PLAYER LOSES: a merchant's fleet card says what she earned in the last 23 to 24 hours where it said exactly 24 (the laps listed, the
--   trades and the average are unchanged). Nothing on a player's own route.
-- NOT BUILT: the month graphs on daily rows (world.price_series, the Stats spans and four specs): still its own slice.
-- LOCKS: CREATE TABLE; CREATE TRIGGER on standing_route_laps (SHARE ROW EXCLUSIVE for an instant, lock_timeout 5 s); CREATE OR REPLACE x6 by hunks.
-- TIME: the fill reads every lap row once (one pass of the table: 87,000 rows before 0409's trim, 65,000 after; seconds once the RUNBOOK's
--   rewrite of standing_route_laps has run, up to a minute on the 226 MB heap of 2026-11-14 with the disk throttled: run the rewrite first).
--   The probe stages 40 laps on one merchant route and rolls them back. BUDGET: statement_timeout 150 s; fails above 120 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/slim-laps/rollback-0416.sql, a draft. At once, with no file: npc_route_lap_keep 0 stops
--   the trim (a merchant's route then keeps 100 laps like a player's, and within a day every reader is exact again).
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then the probe.
-- VERSION: 0416 (0410 to 0415 are other builders' open work; it re-cuts no function they re-cut). It stands on 0409.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.route_earnings(uuid)', 'world.fleet_trades(uuid)',
                                 'public.stats_merchants_window(timestamp with time zone,timestamp with time zone)',
                                 'public.npc_share_budget(timestamp with time zone,uuid,bigint)',
                                 'public.npc_compact_houses(uuid[],timestamp with time zone)', 'public.tick_compact(boolean,boolean)'];
  c_new constant text[] := array['public.route_hour_post()', 'public.route_day(uuid,timestamp with time zone,timestamp with time zone)',
                                 'public.route_day_full(uuid,timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_house     uuid;
  v_route     uuid;
  v_fleet     uuid;
  v_fill      bigint;
  v_e0        jsonb;
  v_e1        jsonb;
  v_true      bigint;
  v_edge      bigint;
  v_note      text := 'no merchant route to probe in this world';
  v_base      timestamptz := date_trunc('hour', now());
begin
  perform set_config('statement_timeout', '150s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.route_hour_laps') is not null or exists (select 1 from public.world_config where key = 'route_hour_keep_hours') then
    raise exception '0416 refuses: it has been applied once';
  end if;
  if not exists (select 1 from public.world_config where key = 'npc_route_lap_keep') or to_regprocedure('public.drift_ports_due(timestamp with time zone)') is null then
    raise exception '0416 refuses: 0409 (the world fits the harbour it has) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0416 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0416
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('route_hour_keep_hours', to_jsonb(80),
     '0416: public.route_hour_laps (a route''s closed laps by the hour) keeps this many hours; public.tick_compact deletes older rows, compact_trim_rows a run. Never under 30: the day figures read 24 hours and the hour before them.'),
    ('npc_invest_lap_hours', to_jsonb(8),
     '0416: public.npc_share_budget keeps npc_invest_keep_laps x the DEAREST lap each of a merchant''s routes closed in the last this-many hours (from public.route_hour_laps). Before 0416 it read the newest 20 laps inside three days: about seven hours of a merchant''s sailing.');
  update public.world_config
     set value = to_jsonb(10),
         description = '0409: a MERCHANT route keeps its newest this-many laps; a lap past them (and, while npc_route_lap_keep_hours is above 0, also closed longer ago than that) goes in public.npc_compact_houses. Never under 10 (the fleet card reads 8, the trades are kept on 7). 0 = OFF: a merchant route keeps standing_route_lap_keep laps like a player''s. 24 at 0409; 10 at 0416 (the owner, 2026-11-14: "newest 10 only, without any hours"): the day figures are read from public.route_hour_laps.'
   where key = 'npc_route_lap_keep' and value = to_jsonb(24);
  update public.world_config
     set value = to_jsonb(0),
         description = '0409: see npc_route_lap_keep. 0 = no hours'' window: the newest npc_route_lap_keep alone (0416; 26 at 0409).'
   where key = 'npc_route_lap_keep_hours' and value = to_jsonb(26);
  update public.world_config
     set value = to_jsonb(30),
         description = '0316: public.tick_history deletes stats_city_good rows older than this many days, 20,000 a run. 0 = OFF, nothing is deleted. Never below 3 days. 0 before 0409; 3 at 0409; 30 at 0416 (the owner asked for longer: past stats_city_good_hour_days a day is one row a city''s good, about 0.3 MB a day).'
   where key = 'stats_city_good_keep_days' and value = to_jsonb(3);
  update public.world_config set value = to_jsonb(2)
   where key = 'stats_city_good_hour_days' and value = to_jsonb(7);

  -- ── 3. THE HOUR BOOK, ITS WRITER AND ITS TWO READINGS ──
  create table public.route_hour_laps (
    route_id   uuid        not null,
    hour       timestamptz not null,
    player_id  uuid,
    laps       int         not null default 0,
    net        bigint      not null default 0,
    sold       bigint      not null default 0,
    bought     bigint      not null default 0,
    supplies   bigint      not null default 0,
    repairs    bigint      not null default 0,
    wages      bigint      not null default 0,
    taxes      bigint      not null default 0,
    insurance  bigint      not null default 0,
    stock_in   bigint      not null default 0,
    stock_out  bigint      not null default 0,
    laps2      int         not null default 0,
    net2       bigint      not null default 0,
    neg2       int         not null default 0,
    spend_max  bigint      not null default 0,
    first_at   timestamptz not null,
    last_at    timestamptz not null,
    primary key (route_id, hour)
  ) with (fillfactor = 70);
  create index route_hour_laps_hour on public.route_hour_laps (hour);
  alter table public.route_hour_laps enable row level security;
  revoke all on table public.route_hour_laps from public, anon, authenticated;
  comment on table public.route_hour_laps is
    '0416: a route''s CLOSED laps by the hour they closed in (hour = date_trunc(''hour'', closed_at)): how many, their figures summed, the cargo carried in and out at cost, the same for laps 2 onwards (laps2, net2, neg2 = how many of those netted nothing or less), the dearest lap''s spend, the first and last close. Written by the trigger public.route_hour_post on public.standing_route_laps and by nothing else; read by public.route_day, public.route_day_full, public.stats_merchants_window and public.npc_share_budget, so that a merchant''s lap rows can be cut to her newest ten. No FK on route_id (as route_month_laps): a deleted route''s hours age out. Kept route_hour_keep_hours.';

  create function public.route_hour_post()
  returns trigger
  language plpgsql
  security definer
  set search_path = public, pg_temp
  as $f$
  -- 0416: THE ONE WRITER of public.route_hour_laps. A lap that is closed (inserted closed, or its closed_at set) is ADDED to the hour it closed
  -- in; a closed lap whose instant or figures change is first TAKEN OUT of the hour it stood in (its sums; the dearest-lap and first / last
  -- marks are not wound back). A deleted lap is not taken out: the book is what lets the lap rows go. The cargo carried in is the stock_out of
  -- the route's closed lap before this one, as cmd.standing_route_close_lap reads it.
  declare
    v_in bigint;
  begin
    if tg_op = 'UPDATE' and old.closed_at is not null then
      select coalesce((select x.stock_out from public.standing_route_laps x
                        where x.route_id = old.route_id and x.closed_at is not null and x.lap_no < old.lap_no
                        order by x.lap_no desc limit 1), 0) into v_in;
      update public.route_hour_laps b
         set laps = b.laps - 1, net = b.net - old.net, sold = b.sold - old.sold, bought = b.bought - old.bought, supplies = b.supplies - old.supplies,
             repairs = b.repairs - old.repairs, wages = b.wages - old.wages, taxes = b.taxes - old.taxes, insurance = b.insurance - old.insurance,
             stock_in = b.stock_in - v_in, stock_out = b.stock_out - old.stock_out,
             laps2 = b.laps2 - (old.lap_no >= 2)::int, net2 = b.net2 - case when old.lap_no >= 2 then old.net else 0 end,
             neg2 = b.neg2 - (old.lap_no >= 2 and old.net <= 0)::int
       where b.route_id = old.route_id and b.hour = date_trunc('hour', old.closed_at);
      delete from public.route_hour_laps b where b.route_id = old.route_id and b.hour = date_trunc('hour', old.closed_at) and b.laps <= 0;
    end if;
    if new.closed_at is not null then
      select coalesce((select x.stock_out from public.standing_route_laps x
                        where x.route_id = new.route_id and x.closed_at is not null and x.lap_no < new.lap_no
                        order by x.lap_no desc limit 1), 0) into v_in;
      insert into public.route_hour_laps as b (route_id, hour, player_id, laps, net, sold, bought, supplies, repairs, wages, taxes, insurance,
                                               stock_in, stock_out, laps2, net2, neg2, spend_max, first_at, last_at)
      values (new.route_id, date_trunc('hour', new.closed_at), (select r.player_id from public.standing_routes r where r.id = new.route_id),
              1, new.net, new.sold, new.bought, new.supplies, new.repairs, new.wages, new.taxes, new.insurance, v_in, new.stock_out,
              (new.lap_no >= 2)::int, case when new.lap_no >= 2 then new.net else 0 end, (new.lap_no >= 2 and new.net <= 0)::int,
              new.bought + new.supplies + new.repairs + new.wages + new.taxes + new.insurance, new.closed_at, new.closed_at)
      on conflict (route_id, hour) do update
         set laps = b.laps + 1, net = b.net + excluded.net, sold = b.sold + excluded.sold, bought = b.bought + excluded.bought,
             supplies = b.supplies + excluded.supplies, repairs = b.repairs + excluded.repairs, wages = b.wages + excluded.wages,
             taxes = b.taxes + excluded.taxes, insurance = b.insurance + excluded.insurance,
             stock_in = b.stock_in + excluded.stock_in, stock_out = b.stock_out + excluded.stock_out,
             laps2 = b.laps2 + excluded.laps2, net2 = b.net2 + excluded.net2, neg2 = b.neg2 + excluded.neg2,
             spend_max = greatest(b.spend_max, excluded.spend_max),
             first_at = least(b.first_at, excluded.first_at), last_at = greatest(b.last_at, excluded.last_at);
    end if;
    return null;
  end $f$;
  revoke all on function public.route_hour_post() from public, anon, authenticated;

  create function public.route_day(p_route uuid, p_from timestamptz, p_to timestamptz)
  returns table (laps bigint, net bigint, sold bigint, bought bigint, supplies bigint, repairs bigint, wages bigint, taxes bigint,
                 stock_in bigint, stock_out bigint, since timestamptz)
  language sql stable security definer
  set search_path = public, pg_temp
  as $f$
    -- 0416: THE ONE reading of a route's closed laps in the window (p_from, p_to]: the hours wholly inside it from public.route_hour_laps, and
    -- the laps of its two part-hours (before the first whole hour, from the last one on) from the lap rows that are still kept. Exact, lap for
    -- lap, wherever the part-hours' laps are kept (a player's route; any window inside a merchant's newest laps); for a merchant's 24 hours the
    -- oldest part-hour's laps are gone, so the window read is the last 23 to 24 hours. One row always (zeros and a null `since` for none).
    with e as (
      select date_trunc('hour', p_from) + case when p_from > date_trunc('hour', p_from) then interval '1 hour' else interval '0' end as lo,
             date_trunc('hour', p_to) as hi
    ), x as (
      select b.laps::bigint as laps, b.net, b.sold, b.bought, b.supplies, b.repairs, b.wages, b.taxes, b.stock_in, b.stock_out, b.first_at as at
        from public.route_hour_laps b, e
       where b.route_id = p_route and b.hour >= e.lo and b.hour < e.hi
      union all
      select 1, l.net, l.sold, l.bought, l.supplies, l.repairs, l.wages, l.taxes,
             coalesce((select y.stock_out from public.standing_route_laps y
                        where y.route_id = l.route_id and y.closed_at is not null and y.lap_no < l.lap_no
                        order by y.lap_no desc limit 1), 0),
             l.stock_out, l.closed_at
        from public.standing_route_laps l, e
       where l.route_id = p_route and l.closed_at > p_from and l.closed_at <= p_to
         and (l.closed_at < e.lo or l.closed_at >= e.hi)
    )
    select coalesce(sum(x.laps), 0)::bigint, coalesce(sum(x.net), 0)::bigint, coalesce(sum(x.sold), 0)::bigint, coalesce(sum(x.bought), 0)::bigint,
           coalesce(sum(x.supplies), 0)::bigint, coalesce(sum(x.repairs), 0)::bigint, coalesce(sum(x.wages), 0)::bigint, coalesce(sum(x.taxes), 0)::bigint,
           coalesce(sum(x.stock_in), 0)::bigint, coalesce(sum(x.stock_out), 0)::bigint, min(x.at)
      from x
  $f$;
  revoke all on function public.route_day(uuid, timestamptz, timestamptz) from public, anon, authenticated;

  create function public.route_day_full(p_route uuid, p_from timestamptz)
  returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
  as $f$
    -- 0416: whether the route closed a lap at or before p_from that is still on record (a lap row, or an hour of the book): a whole window from
    -- p_from is held. The fleet card prints "so far today" until it is.
    select exists (select 1 from public.standing_route_laps x where x.route_id = p_route and x.closed_at <= p_from)
        or exists (select 1 from public.route_hour_laps b where b.route_id = p_route and b.hour <= p_from and b.first_at <= p_from)
  $f$;
  revoke all on function public.route_day_full(uuid, timestamptz) from public, anon, authenticated;

  -- ── 4. THE BOOK IS FILLED ONCE, from the lap rows that stand (one pass), BEFORE the trigger is there to add to it ──
  insert into public.route_hour_laps (route_id, hour, player_id, laps, net, sold, bought, supplies, repairs, wages, taxes, insurance,
                                      stock_in, stock_out, laps2, net2, neg2, spend_max, first_at, last_at)
  select z.route_id, date_trunc('hour', z.closed_at), (select r.player_id from public.standing_routes r where r.id = z.route_id),
         count(*)::int, sum(z.net), sum(z.sold), sum(z.bought), sum(z.supplies), sum(z.repairs), sum(z.wages), sum(z.taxes), sum(z.insurance),
         sum(z.stock_in), sum(z.stock_out),
         (count(*) filter (where z.lap_no >= 2))::int, coalesce(sum(z.net) filter (where z.lap_no >= 2), 0),
         (count(*) filter (where z.lap_no >= 2 and z.net <= 0))::int,
         max(z.bought + z.supplies + z.repairs + z.wages + z.taxes + z.insurance), min(z.closed_at), max(z.closed_at)
    from (select l.*, coalesce(lag(l.stock_out) over (partition by l.route_id order by l.lap_no), 0) as stock_in
            from public.standing_route_laps l
           where l.closed_at is not null) z
   where z.closed_at > now() - interval '80 hours'
   group by z.route_id, date_trunc('hour', z.closed_at);
  get diagnostics v_fill = row_count;
  create trigger standing_route_laps_hour_book
    after insert or update of closed_at, net, sold, bought, supplies, repairs, wages, taxes, insurance, stock_out
    on public.standing_route_laps
    for each row execute function public.route_hour_post();

  -- ── 5. THE HUNKS ──
  create temp table hunk_0416 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0416 values
  (1, c_cut[1],
$h$    'day',       coalesce((select sum(x.net) from public.standing_route_laps x
                            where x.route_id = p_route and x.closed_at > now() - interval '24 hours'), 0),
    'day_laps',  (select count(*) from public.standing_route_laps x
                   where x.route_id = p_route and x.closed_at > now() - interval '24 hours'),
    'day_since', (select min(x.closed_at) from public.standing_route_laps x
                   where x.route_id = p_route and x.closed_at > now() - interval '24 hours'),
    'day_full',  exists (select 1 from public.standing_route_laps x
                          where x.route_id = p_route and x.closed_at <= now() - interval '24 hours'),
$h$,
$h$    -- 0416: the day is read by public.route_day (the hour book for the whole hours, the lap rows for the part-hours), so a merchant's
    -- lap rows can be her newest ten
    'day',       (select d.net from public.route_day(p_route, now() - interval '24 hours', now()) d),
    'day_laps',  (select d.laps from public.route_day(p_route, now() - interval '24 hours', now()) d),
    'day_since', (select d.since from public.route_day(p_route, now() - interval '24 hours', now()) d),
    'day_full',  public.route_day_full(p_route, now() - interval '24 hours'),
$h$),
  (2, c_cut[2],
$h$  select jsonb_build_object(
           'since', (select min(w.closed_at) from w),
           'full', exists (select 1 from public.standing_route_laps y
                            where y.route_id = sr.id and y.closed_at <= now() - interval '24 hours'),
           'laps', (select count(*) from w),
           'laps_traded', (select count(*) from w where w.trades is not null),
           'sold', coalesce((select sum(w.sold) from w), 0),
           'bought', coalesce((select sum(w.bought) from w), 0),
           'supplies', coalesce((select sum(w.supplies) from w), 0),
           'repairs', coalesce((select sum(w.repairs) from w), 0),
           'wages', coalesce((select sum(w.wages) from w), 0),
           'taxes', coalesce((select sum(w.taxes) from w), 0),   -- 0122
           'stock_in', coalesce((select sum(w.stock_in) from w), 0),
           'stock_out', coalesce((select sum(w.stock_out) from w), 0),
           'net', coalesce((select sum(w.net) from w), 0),
$h$,
$h$  -- 0416: the day's totals are public.route_day's (the hour book and the part-hours' lap rows: the figures route_earnings prints); the laps
  -- that still carry their trades, and the goods below, are read from the lap rows as before
  select (select jsonb_build_object(
           'since', d.since,
           'full', public.route_day_full(sr.id, now() - interval '24 hours'),
           'laps', d.laps,
           'laps_traded', (select count(*) from w where w.trades is not null),
           'sold', d.sold,
           'bought', d.bought,
           'supplies', d.supplies,
           'repairs', d.repairs,
           'wages', d.wages,
           'taxes', d.taxes,   -- 0122
           'stock_in', d.stock_in,
           'stock_out', d.stock_out,
           'net', d.net)
            from public.route_day(sr.id, now() - interval '24 hours', now()) d)
         || jsonb_build_object(
$h$),
  (3, c_cut[3],
$h$    select l.route_id, l.net
      from public.standing_route_laps l
     where l.closed_at > p_from and l.closed_at <= p_to and l.lap_no >= 2
  ), h as (
    select p.company_name as name, n.code as nation, sum(l.net)::bigint as day, count(*)::int as laps
$h$,
$h$    -- 0416: the whole hours of the window from public.route_hour_laps (laps 2 onwards: net2, laps2, neg2), its two part-hours from the lap
    -- rows still kept (a merchant keeps her newest ten). The tab's "minutes since the count" lies inside one or two part-hours: exact.
    select b.route_id, b.net2 as net, b.laps2 as n, b.neg2 as neg
      from public.route_hour_laps b
     where b.hour >= date_trunc('hour', p_from) + case when p_from > date_trunc('hour', p_from) then interval '1 hour' else interval '0' end
       and b.hour < date_trunc('hour', p_to) and b.laps2 > 0
    union all
    select l.route_id, l.net, 1, (l.net <= 0)::int
      from public.standing_route_laps l
     where l.closed_at > p_from and l.closed_at <= p_to and l.lap_no >= 2
       and (l.closed_at < date_trunc('hour', p_from) + case when p_from > date_trunc('hour', p_from) then interval '1 hour' else interval '0' end
            or l.closed_at >= date_trunc('hour', p_to))
  ), h as (
    select p.company_name as name, n.code as nation, sum(l.net)::bigint as day, sum(l.n)::int as laps
$h$),
  (4, c_cut[3],
$h$           'n', (select count(*) from l),
           'neg', (select count(*) from l where l.net <= 0),
$h$,
$h$           'n', coalesce((select sum(l.n) from l), 0),
           'neg', coalesce((select sum(l.neg) from l), 0),
$h$),
  (5, c_cut[4],
$h$            cross join lateral (select x.bought + x.supplies + x.repairs + x.wages + x.taxes + x.insurance as spend
                                  from public.standing_route_laps x
                                 where x.route_id = nf.route_id and x.closed_at > p_now - interval '3 days'
                                 order by x.lap_no desc limit 20) l
$h$,
$h$            -- 0416: the dearest lap of the last npc_invest_lap_hours, from the hour book (it read her newest 20 lap rows; she keeps ten)
            cross join lateral (select b.spend_max as spend
                                  from public.route_hour_laps b
                                 where b.route_id = nf.route_id
                                   and b.hour >= date_trunc('hour', p_now - make_interval(hours => greatest(public.wc_int('npc_invest_lap_hours'), 1)))) l
$h$),
  (6, c_cut[5],
$h$                and l.closed_at < p_now - make_interval(hours => greatest(public.wc_int('npc_route_lap_keep_hours'), 25))
                and l.lap_no <= sr.lap_no - greatest(public.wc_int('npc_route_lap_keep'), 20)
$h$,
$h$                -- 0416: her newest npc_route_lap_keep alone (never under 10); the hours' window only while its knob is above 0. The day
                -- figures no longer read these rows (public.route_hour_laps).
                and (public.wc_int('npc_route_lap_keep_hours') <= 0
                     or l.closed_at < p_now - make_interval(hours => public.wc_int('npc_route_lap_keep_hours')))
                and l.lap_no <= sr.lap_no - greatest(public.wc_int('npc_route_lap_keep'), 10)
$h$),
  (7, c_cut[6],
$h$    if p_commit then commit; end if;
  end if;
  insert into public.compact_runs (slot, at, ms, receipt)
$h$,
$h$    if p_commit then commit; end if;
  end if;
  -- 0416: THE HOUR BOOK'S OLD HOURS (public.route_hour_laps past route_hour_keep_hours, never under 30), compact_trim_rows a run.
  begin
    delete from public.route_hour_laps b
     where b.ctid = any(array(select x.ctid from public.route_hour_laps x
                               where x.hour < v_now - make_interval(hours => greatest(public.wc_int('route_hour_keep_hours'), 30))
                               order by x.hour
                               limit greatest(public.wc_int('compact_trim_rows'), 1)));
  exception when others then
    v_fail := v_fail + 1;
    v_note := coalesce(v_note, 'hour book: ' || sqlerrm);
  end;
  if p_commit then commit; end if;
  insert into public.compact_runs (slot, at, ms, receipt)
$h$);
  for h in select * from hunk_0416 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0416 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0416 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0416 p where p.fn = h.fn) then
      raise exception '0416 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0416 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0416 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0416 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0416 self-assert FAIL: another function moved';
  end if;
  if public.wc_int('route_hour_keep_hours') <> 80 or public.wc_int('npc_invest_lap_hours') <> 8 then
    raise exception '0416 self-assert FAIL: the knobs are not this file''s';
  end if;

  -- ── 6. THE PROBE: 40 laps on one merchant route, one every 45 minutes back from 10 minutes ago, numbered a million up; rolled back.
  --      Before the cut the day is exact (the book's whole hours and the part-hours' lap rows): it must equal the sum of the staged laps of
  --      the last 24 hours. Then her laps are cut to the newest ten (the compactor's rule, as of now): the day may only have lost the laps of
  --      the oldest part-hour, and the laps left and the card must be right. (The Stats window is proved in proof 112: here other houses' laps move.)
  select sr.player_id, sr.id, nf.fleet_id into v_house, v_route, v_fleet
    from public.standing_routes sr
    join public.players p on p.id = sr.player_id and p.is_npc
    join public.npc_fleets nf on nf.route_id = sr.id
   order by sr.id limit 1;
  if v_route is not null then
    begin
      update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
      update public.world_config set value = to_jsonb(10) where key = 'npc_route_lap_keep';
      update public.world_config set value = to_jsonb(0) where key = 'npc_route_lap_keep_hours';
      if not public.npc_traders_on() then
        v_note := 'the merchants cannot be lit in this world: not probed';
      else
        delete from public.route_hour_laps where route_id = v_route;
        delete from public.standing_route_laps where route_id = v_route;
        update public.standing_routes set lap_id = null, lap_no = 1000040 where id = v_route;
        insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, net, sold, bought, stock_out)
        select v_route, 1000000 + g, now() - make_interval(mins => 10 + 45 * (40 - g) + 20), now() - make_interval(mins => 10 + 45 * (40 - g)),
               case when g % 4 = 0 then -100 - g else 1000 + g end, 5000 + g, 4000, 70 + g
          from generate_series(1, 40) g order by g;
        select coalesce(sum(l.net), 0), coalesce(sum(l.net) filter (where l.closed_at < date_trunc('hour', now() - interval '24 hours') + interval '1 hour'), 0)
          into v_true, v_edge
          from public.standing_route_laps l where l.route_id = v_route and l.closed_at > now() - interval '24 hours';
        v_e0 := public.route_earnings(v_route);
        if (v_e0->>'day')::bigint <> v_true or (v_e0->>'day_laps')::int <> (select count(*) from public.standing_route_laps l where l.route_id = v_route and l.closed_at > now() - interval '24 hours')
           or not (v_e0->>'day_full')::boolean then
          raise exception '0416 self-assert FAIL: with every lap row there, the day reads % over % laps; the staged laps of 24 hours sum to %', v_e0->>'day', v_e0->>'day_laps', v_true;
        end if;
        perform public.npc_compact_houses(array[v_house], now() - interval '3650 days');   -- as of ten years ago: none of her books is before any cut; the lap rule reads no clock
        if (select count(*) from public.standing_route_laps l where l.route_id = v_route) <> 10
           or (select min(l.lap_no) from public.standing_route_laps l where l.route_id = v_route) <> 1000031 then
          raise exception '0416 self-assert FAIL: the cut left % laps from lap % (her newest ten: 1000031 to 1000040)',
            (select count(*) from public.standing_route_laps l where l.route_id = v_route), (select min(l.lap_no) from public.standing_route_laps l where l.route_id = v_route);
        end if;
        v_e1 := public.route_earnings(v_route);
        if (v_e1->>'day')::bigint <> v_true - v_edge or not (v_e1->>'day_full')::boolean
           or (v_e1->'laps_recent') <> (v_e0->'laps_recent') or (v_e1->>'lap') is distinct from (v_e0->>'lap') then
          raise exception '0416 self-assert FAIL: after the cut the day reads % (before % less the oldest part-hour''s % = %), or the newest laps'' figures moved',
            v_e1->>'day', v_true, v_edge, v_true - v_edge;
        end if;
        if jsonb_array_length(world.fleet_trades(v_fleet)->'laps') <> 7
           or (world.fleet_trades(v_fleet)->'day'->>'net')::bigint <> v_true - v_edge then
          raise exception '0416 self-assert FAIL: the fleet card lists % laps (7) and a day of % (%)',
            jsonb_array_length(world.fleet_trades(v_fleet)->'laps'), world.fleet_trades(v_fleet)->'day'->>'net', v_true - v_edge;
        end if;
        v_note := format('one merchant route, 40 probe laps 45 minutes apart: the day read %s exactly with every lap row there; cut to her newest ten it reads %s (the oldest part-hour''s %s gone, nothing else), the card lists 7 laps and the same day',
                         v_true, v_true - v_edge, v_edge);
      end if;
      raise exception sqlstate 'BV416';
    exception when sqlstate 'BV416' then null;
    end;
    if v_note not like 'one merchant route%' and v_note not like 'the merchants cannot%' then
      raise exception '0416 self-assert FAIL: the probe did not run to its end';
    end if;
    if exists (select 1 from public.standing_route_laps l where l.route_id = v_route and l.lap_no > 1000000) then
      raise exception '0416 self-assert FAIL: the probe was not rolled back';
    end if;
  end if;

  if clock_timestamp() - v_t0 > interval '120 seconds' then
    raise exception '0416 self-assert FAIL: the file took % (budget 120 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0416 self-assert ok: A MERCHANT KEEPS HER TEN NEWEST LAPS. Seven hunks over six bodies, each once and reversing; grants and volatility unmoved; no other function moved; public.route_hour_laps filled with % hour(s) and written by public.route_hour_post; npc_route_lap_keep %, npc_route_lap_keep_hours %, stats_city_good_keep_days %, stats_city_good_hour_days %. Probe: %; % ms.',
    v_fill, public.wc_int('npc_route_lap_keep'), public.wc_int('npc_route_lap_keep_hours'), public.wc_int('stats_city_good_keep_days'),
    public.wc_int('stats_city_good_hour_days'), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
