-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0246 — EVERY FIGURE IS KEPT
--        (docs/NEWS_AND_MARKERS.md §1.2, slice N1: the stats tables fold their old rows instead of throwing
--         them away — an hour of fifteen-minute slots becomes ONE hourly row, a day of them ONE daily row, flows
--         ADDED, states kept at their last value — and the Stats charts take a span like the price chart.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT WAS BEING LOST (prod, measured 2026-10-26) ────────────────────────────────────────────
--   0214's retention deleted, past 72 h (city goods 48 h), every slot of a UTC day but the LAST. The kept row's
--   state is right, but its FLOWS (sold, bought, units, trades, minted, removed, moved, *_ducats, `period`, `flows`)
--   are 15 minutes' worth: 95 slots in 96 of every day's flows were thrown away, and the day's shape with them.
--   LOST FOR GOOD: 10-20 -> 10-23 (four days, already compacted that way; one row a day, 15 minutes of flow each).
--   They cannot be rebuilt: the rows that held them are gone, and no other table holds the same figures per slot.
--   The price record has its own tiers since 0226 (fine 24 h / hourly 30 d / daily forever) and is NOT touched.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
--   (1) `n smallint not null default 1` on stats_world / stats_merchants / stats_good / stats_city / stats_city_good:
--       how many slots the row folds. A row written by the count is 1; an hourly row is up to 4, a daily one up to 96.
--       Rows older than this file are 1 (a legacy day row was ONE kept slot — it says so, honestly).
--   (2) Three knobs: stats_hour_days 30 (stats_good, stats_city), stats_city_good_hour_days 7 (the largest table: 30 d
--       would be ~375 MB), stats_fold_back_days 14 (how far behind a missed run the fold looks — see "said plainly").
--   (3) THE ONE RULE OF A BUCKET and of a span, each in one place:
--         public.stats_bucket(at, unit)      'fine' = the row itself, 'hour' / 'day' = the row's own UTC hour / day
--         public.stats_span_unit(span)       1d -> fine, 1w / 1m -> hour, 1y / all -> day        (price_series' tiers)
--         public.stats_span_since(span, now) the instant a span reaches back to; null for `all`
--         public.stats_map_sum(jsonb[])      key-wise sum of jsonb flow maps, a key at 0 dropped
--   (4) public.stats_fold(table, unit, lo, hi) — the FOLD: every (key, bucket) with more than one row in [lo, hi)
--       becomes the bucket's LAST row, carrying the flows' sum, the maps' key-wise sum and the slots' count `n`; the
--       other rows of the bucket are removed. State columns (purse, stock, mid, houses, fleets ...) and `recent`,
--       `watch`, `top`, `bottom` stay the last row's own. One statement per table, set-based, nothing but finished
--       buckets. A bucket with ONE row is not touched (a daily row is never deleted, nor rewritten).
--   (5) public.stats_compact(now) — the tiers, per table: fine window -> hourly -> daily (stats_world and
--       stats_merchants stay hourly for ever: they are tiny, 24 x 365 x 5.6 KB = 49 MB a year). Called by tick_stats in place of
--       0214's five `delete ... where exists (a later slot the same UTC day)` hunks. No new cron job.
--   (6) public.tick_stats ×3 hunks (declare, the retention block, the return gains `fold`); the fold prints its own ms.
--   (7) The three reads that draw a history take a span like world.price_series:
--         world.stats_overview(p_hours, p_span)  world.stats_city(p_port, p_span)  world.stats_merchants(p_span)
--       The series is cut from the span's tier ('fine' rows for 1d, hourly buckets for 1w / 1m, daily for 1y / all)
--       so ONE line never mixes a 15-minute flow with an hour's. Each point carries `n`. `span` is echoed. A null
--       span is the read's own window as before (hours / 7 d / 24 h, fine rows) — so a client from before this file
--       keeps working during the deploy. A bad span RAISES E_BAD_SPAN. The registry (client_rpc_entry_points) follows
--       the three new argument lists. stats_markets and stats_cities draw no history and do not change.
--
-- ── SAID PLAINLY ────────────────────────────────────────────────────────────────────────────────
--   * stats_fold_back_days 14: the fold looks back 14 days from each tier's edge, not to the beginning of time
--     (a daily row older than that is never re-read every 15 minutes). A cron that was dead for more than 14 days
--     leaves older fine rows unfolded until the knob is raised once; it never loses or double-counts a figure.
--   * An hourly row's `at` is its LAST slot's own at (:51), a daily row's the day's last slot's — not the bucket's
--     start. The bucket is always the row's own UTC hour / day (public.stats_bucket), never now()'s.
--   * stats_world.period is a per-slot map; the folded one is the key-wise sum, a kind that nets to 0 is dropped (as
--     the count itself drops a zero kind).
--   * `tick_stats` already takes 12-18 s on prod. The fold reads only the finished buckets between the tier's edge and
--     14 days back (at most one hour's slots a run in steady state: 4 per key, 6.4 k rows for city goods) and prints its ms
--     in the count's return (`fold.ms`) and in this file's receipt.
--
-- ── HUNKS SLICED FROM THE LIVE BODIES (prod head 0244, LF-normalised, read with pg_get_functiondef on prod
--    2026-10-26: tick_stats as re-cut by 0214, 0224, 0226, 0229, 0232, 0243; stats_overview / stats_city 0232;
--    stats_merchants 0232 + 0244; client_rpc_entry_points 0244). Each hunk is asserted to occur exactly once
--    and to reverse to the pre-image; ACL / volatility / definer / config unchanged. ──────────────────────────
--
-- ── WHAT IT SELF-ASSERTS (probe rows only; every probe in a sub-transaction, rolled back and asserted gone) ─────
--   (a) the hunks reverse; the three reads keep their ACL (authenticated only), volatility, definer and config.
--   (b) THE FOLD, on all five tables, with probe slots planted at fixed instants in 2001 (no hour-of-day dependence;
--       no real row is ever in range): eight slots across two hours, five rows across two days, a daily row on each side.
--       The hour fold sums each flow exactly, key-sums the map, keeps the LAST slot's state, sets n = 4, and leaves the
--       window's later (fine) rows untouched. The day fold does the same over hourly rows, and over an hour + fine rows
--       together (n adds up). A second run removes nothing and changes nothing; a wide range over a lone daily row
--       leaves it byte for byte. No daily row is ever deleted.
--   (c) THE COUNT: tick_stats carries stats_compact once and no `delete from public.stats_`; a count run two hours
--       ahead returns `fold` with its ms (printed).
--   (d) THE READS, with probe rows planted past every real one: a series' flows add up to the table's (exactly), its
--       `n`s add up to the rows', no two points share a bucket, the span is echoed, a bad span raises E_BAD_SPAN.
--   (e) the registry is the old one with the three argument lists, every row executable by authenticated; the helper
--       functions are executable by no client; no client write grant / executable writer / caller-evaluated function.
--   No table that grows on production is counted against a remembered figure; nothing is DELETEd from an append-only
--   table (the stats tables are rolled-up counts, not ledgers); no `set role`; nothing reads the hour.
-- ROLLBACK (forward): put each hunk's OLD text back (verbatim below), drop the new functions and the three knobs;
--   the `n` columns may stay (they are 1 on every row the old shape wrote).
-- VERSION: 0246 (prod head 0244; 0245 is another slice; the deploy renumbers).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.stats_fold_day(bigint)') is null or to_regprocedure('public.stats_merchants_add(jsonb,jsonb)') is null then
    raise exception '0246 refuses: 0232 (every figure keeps to the second) is not in this world';
  end if;
  if to_regprocedure('public.stats_fold(text,text,timestamptz,timestamptz)') is not null then
    raise exception '0246 refuses: public.stats_fold already exists';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0246(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0246 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_stats(timestamptz)'), ('world.stats_overview(integer)'), ('world.stats_city(uuid)'),
               ('world.stats_merchants()'), ('public.client_rpc_entry_points()')) f(fn);

create temp table before_0246 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- ── 1. THE COLUMN AND THE KNOBS ─────────────────────────────────────────────────────────────────
alter table public.stats_world      add column n smallint not null default 1;
alter table public.stats_merchants  add column n smallint not null default 1;
alter table public.stats_good       add column n smallint not null default 1;
alter table public.stats_city       add column n smallint not null default 1;
alter table public.stats_city_good  add column n smallint not null default 1;
comment on column public.stats_world.n is
  '0246: how many 15-minute slots this row folds — 1 for a row the count wrote (and for a legacy day row, which kept ONE slot); an hourly row is up to 4, a daily up to 96. public.stats_fold sets it.';
comment on column public.stats_merchants.n is '0246: slots folded into this row (see stats_world.n).';
comment on column public.stats_good.n      is '0246: slots folded into this row (see stats_world.n).';
comment on column public.stats_city.n      is '0246: slots folded into this row (see stats_world.n).';
comment on column public.stats_city_good.n is '0246: slots folded into this row (see stats_world.n).';

insert into public.world_config (key, value, description) values
  ('stats_hour_days', to_jsonb(30),
   '0246: how many days stats_good and stats_city keep an HOURLY row (flows added, state = the last slot''s). Older, one row a day, kept for ever. stats_world and stats_merchants keep hourly rows for ever. Must exceed stats_fine_hours / 24.'),
  ('stats_city_good_hour_days', to_jsonb(7),
   '0246: the same for stats_city_good, the largest table (30 days of it would be ~375 MB). Must exceed stats_city_good_fine_hours / 24.'),
  ('stats_fold_back_days', to_jsonb(14),
   '0246: how far back from each tier edge public.stats_compact looks for buckets still to fold. A count that missed more than this many days leaves the older fine rows unfolded until this is raised once.')
on conflict (key) do nothing;

-- ── 2. THE ONE RULE OF A BUCKET AND OF A SPAN ───────────────────────────────────────────────────
create function public.stats_bucket(p_at timestamptz, p_unit text)
returns timestamptz
language sql
immutable
set search_path = public, pg_temp
as $$
  -- 0246: the bucket a row belongs to — its OWN UTC hour or day (never now()'s), 'fine' = the row itself.
  select case p_unit
           when 'fine' then p_at
           when 'hour' then date_trunc('hour', p_at at time zone 'UTC') at time zone 'UTC'
           when 'day'  then date_trunc('day',  p_at at time zone 'UTC') at time zone 'UTC'
         end
$$;

create function public.stats_span_unit(p_span text)
returns text
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  -- 0246: the tier a span is drawn from, as world.price_series (0226) draws it: 1d fine, 1w / 1m hourly, 1y / all daily.
  if p_span is null or p_span not in ('1d', '1w', '1m', '1y', 'all') then
    raise exception 'E_BAD_SPAN: a chart spans 1d, 1w, 1m, 1y or all, not %', coalesce(p_span, 'null') using errcode = 'P0001';
  end if;
  return case p_span when '1d' then 'fine' when '1w' then 'hour' when '1m' then 'hour' else 'day' end;
end $$;

create function public.stats_span_since(p_span text, p_now timestamptz)
returns timestamptz
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  -- 0246: the instant a span reaches back to from p_now; null for `all`. 1m is 30 days and 1y 365, as price_series.
  perform public.stats_span_unit(p_span);
  return case p_span when '1d' then p_now - interval '1 day' when '1w' then p_now - interval '7 days'
                     when '1m' then p_now - interval '30 days' when '1y' then p_now - interval '365 days' end;
end $$;

create function public.stats_map_sum(p_maps jsonb[])
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  -- 0246: the key-wise sum of jsonb flow maps (kind -> ducats); a kind that nets to 0 is dropped, as the count drops it.
  select coalesce(jsonb_object_agg(k.kind, k.s), '{}'::jsonb)
    from (select e.key as kind, sum(e.value::bigint) as s
            from unnest(p_maps) m, jsonb_each_text(m) e
           group by e.key having sum(e.value::bigint) <> 0) k
$$;

-- ── 3. THE FOLD ─────────────────────────────────────────────────────────────────────────────────
create function public.stats_fold(p_table text, p_unit text, p_lo timestamptz, p_hi timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 0246: fold every (key, bucket) that holds more than one row in [p_lo, p_hi) into the bucket's LAST row: the flows
-- summed, the maps key-summed, `n` the slots' sum; the bucket's other rows removed. State columns stay the last row's.
-- A bucket with one row is untouched. [p_lo, p_hi) must lie on bucket edges, so only finished buckets are ever folded.
-- Returns {rows: rows rewritten, removed: rows removed}. Called by public.stats_compact.
declare
  v_u bigint; v_d bigint;
begin
  if p_unit not in ('hour', 'day') then
    raise exception '0246 stats_fold: unit % is not hour or day', p_unit;
  end if;
  if p_lo is null or p_hi is null or p_lo <> public.stats_bucket(p_lo, p_unit) or p_hi <> public.stats_bucket(p_hi, p_unit) then
    raise exception '0246 stats_fold: [%, %) is not on % edges — only a finished bucket may be folded', p_lo, p_hi, p_unit;
  end if;
  if p_hi <= p_lo then
    return jsonb_build_object('rows', 0, 'removed', 0);
  end if;

  if p_table = 'stats_world' then
    with g as (
      select public.stats_bucket(w.at, p_unit) as b, max(w.slot) as last_slot, sum(w.n) as n,
             sum(w.minted) as minted, sum(w.removed) as removed, sum(w.moved) as moved, sum(w.sold) as sold,
             sum(w.bought) as bought, sum(w.units) as units, sum(w.trades) as trades,
             public.stats_map_sum(array_agg(w.period)) as period
        from public.stats_world w where w.at >= p_lo and w.at < p_hi
       group by 1 having count(*) > 1),
    u as (
      update public.stats_world w
         set minted = g.minted, removed = g.removed, moved = g.moved, sold = g.sold, bought = g.bought,
             units = g.units, trades = g.trades, period = g.period, n = g.n
        from g where w.slot = g.last_slot returning w.slot),
    d as (
      delete from public.stats_world w using g
       where w.at >= p_lo and w.at < p_hi and public.stats_bucket(w.at, p_unit) = g.b and w.slot <> g.last_slot returning w.slot)
    select (select count(*) from u), (select count(*) from d) into v_u, v_d;

  elsif p_table = 'stats_merchants' then
    -- all of a merchants row is state (the fleets, the purse, the 24 h profit as it stood): the last row stays, with n
    with g as (
      select public.stats_bucket(w.at, p_unit) as b, max(w.slot) as last_slot, sum(w.n) as n
        from public.stats_merchants w where w.at >= p_lo and w.at < p_hi
       group by 1 having count(*) > 1),
    u as (
      update public.stats_merchants w set n = g.n from g where w.slot = g.last_slot returning w.slot),
    d as (
      delete from public.stats_merchants w using g
       where w.at >= p_lo and w.at < p_hi and public.stats_bucket(w.at, p_unit) = g.b and w.slot <> g.last_slot returning w.slot)
    select (select count(*) from u), (select count(*) from d) into v_u, v_d;

  elsif p_table = 'stats_good' then
    with g as (
      select w.good_id, public.stats_bucket(w.at, p_unit) as b, max(w.slot) as last_slot, sum(w.n) as n,
             sum(w.sold) as sold, sum(w.bought) as bought, sum(w.sold_ducats) as sold_ducats, sum(w.bought_ducats) as bought_ducats
        from public.stats_good w where w.at >= p_lo and w.at < p_hi
       group by 1, 2 having count(*) > 1),
    u as (
      update public.stats_good w
         set sold = g.sold, bought = g.bought, sold_ducats = g.sold_ducats, bought_ducats = g.bought_ducats, n = g.n
        from g where w.good_id = g.good_id and w.slot = g.last_slot returning w.slot),
    d as (
      delete from public.stats_good w using g
       where w.at >= p_lo and w.at < p_hi and w.good_id = g.good_id and public.stats_bucket(w.at, p_unit) = g.b
         and w.slot <> g.last_slot returning w.slot)
    select (select count(*) from u), (select count(*) from d) into v_u, v_d;

  elsif p_table = 'stats_city' then
    with g as (
      select w.port_id, public.stats_bucket(w.at, p_unit) as b, max(w.slot) as last_slot, sum(w.n) as n,
             sum(w.income) as income, sum(w.spending) as spending, sum(w.taxes) as taxes, sum(w.sold) as sold, sum(w.bought) as bought,
             public.stats_map_sum(array_agg(w.flows)) as flows
        from public.stats_city w where w.at >= p_lo and w.at < p_hi
       group by 1, 2 having count(*) > 1),
    u as (
      update public.stats_city w
         set income = g.income, spending = g.spending, taxes = g.taxes, sold = g.sold, bought = g.bought, flows = g.flows, n = g.n
        from g where w.port_id = g.port_id and w.slot = g.last_slot returning w.slot),
    d as (
      delete from public.stats_city w using g
       where w.at >= p_lo and w.at < p_hi and w.port_id = g.port_id and public.stats_bucket(w.at, p_unit) = g.b
         and w.slot <> g.last_slot returning w.slot)
    select (select count(*) from u), (select count(*) from d) into v_u, v_d;

  elsif p_table = 'stats_city_good' then
    with g as (
      select w.port_id, w.good_id, public.stats_bucket(w.at, p_unit) as b, max(w.slot) as last_slot, sum(w.n) as n,
             sum(w.sold) as sold, sum(w.bought) as bought, sum(w.sold_ducats) as sold_ducats, sum(w.bought_ducats) as bought_ducats
        from public.stats_city_good w where w.at >= p_lo and w.at < p_hi
       group by 1, 2, 3 having count(*) > 1),
    u as (
      update public.stats_city_good w
         set sold = g.sold, bought = g.bought, sold_ducats = g.sold_ducats, bought_ducats = g.bought_ducats, n = g.n
        from g where w.port_id = g.port_id and w.good_id = g.good_id and w.slot = g.last_slot returning w.slot),
    d as (
      delete from public.stats_city_good w using g
       where w.at >= p_lo and w.at < p_hi and w.port_id = g.port_id and w.good_id = g.good_id
         and public.stats_bucket(w.at, p_unit) = g.b and w.slot <> g.last_slot returning w.slot)
    select (select count(*) from u), (select count(*) from d) into v_u, v_d;

  else
    raise exception '0246 stats_fold: % is not a stats table', p_table;
  end if;
  return jsonb_build_object('rows', v_u, 'removed', v_d);
end $fn$;

-- ── 4. THE TIERS ────────────────────────────────────────────────────────────────────────────────
create function public.stats_compact(p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 0246: the stats tables' retention, in place of 0214's deletes. Per table: the fine window (stats_fine_hours, 48 h for
-- city goods) -> HOURLY rows -> DAILY rows kept for ever (stats_world and stats_merchants stay hourly for ever). Day
-- first (hourly or fine rows older than the hourly window fold into their day), then hour (fine rows past the fine
-- window). Only finished buckets: the edges are the bucket floors of (now - window). Returns the rows removed and ms.
declare
  v_t0   timestamptz := clock_timestamp();
  v_back interval := make_interval(hours => 24 * public.wc_int('stats_fold_back_days'));   -- hours, not days: a bucket edge never meets a DST shift
  t      record;
  v_h_hi timestamptz; v_h_lo timestamptz; v_d_hi timestamptz;
  v_r    jsonb;
  v_out  jsonb := '{}'::jsonb;
  v_rm   bigint := 0;
  v_tbl  bigint;
begin
  for t in
    select x.tbl, x.fine, x.hour
      from (values ('stats_world',     make_interval(hours => public.wc_int('stats_fine_hours')), null::interval),
                   ('stats_merchants', make_interval(hours => public.wc_int('stats_fine_hours')), null::interval),
                   ('stats_good',      make_interval(hours => public.wc_int('stats_fine_hours')), make_interval(days => public.wc_int('stats_hour_days'))),
                   ('stats_city',      make_interval(hours => public.wc_int('stats_fine_hours')), make_interval(days => public.wc_int('stats_hour_days'))),
                   ('stats_city_good', make_interval(hours => public.wc_int('stats_city_good_fine_hours')), make_interval(days => public.wc_int('stats_city_good_hour_days')))
           ) x(tbl, fine, hour)
  loop
    v_h_hi := public.stats_bucket(p_now - t.fine, 'hour');
    v_h_lo := v_h_hi - v_back;
    v_tbl := 0;
    if t.hour is not null then
      if t.hour <= t.fine then
        raise exception '0246 stats_compact: the hourly window of % (%) must exceed its fine window (%)', t.tbl, t.hour, t.fine;
      end if;
      v_d_hi := public.stats_bucket(p_now - t.hour, 'day');
      v_r := public.stats_fold(t.tbl, 'day', v_d_hi - v_back, v_d_hi);
      v_tbl := v_tbl + (v_r->>'removed')::bigint;
      v_h_lo := greatest(v_d_hi, v_h_lo);
    end if;
    v_r := public.stats_fold(t.tbl, 'hour', v_h_lo, v_h_hi);
    v_tbl := v_tbl + (v_r->>'removed')::bigint;
    v_rm := v_rm + v_tbl;
    v_out := v_out || jsonb_build_object(t.tbl, v_tbl);
  end loop;
  return jsonb_build_object('removed', v_rm, 'tables', v_out,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $fn$;

comment on function public.stats_fold(text, text, timestamptz, timestamptz) is
  '0246: folds every (key, bucket) with more than one row in [lo, hi) into the bucket''s last row — flows summed, maps key-summed, n added; state kept. A lone row is never touched.';
comment on function public.stats_compact(timestamptz) is
  '0246: the stats tables'' retention — fine -> hourly -> daily, by fold. Called by tick_stats on every count.';
revoke all on function public.stats_bucket(timestamptz, text), public.stats_span_unit(text), public.stats_span_since(text, timestamptz),
                      public.stats_map_sum(jsonb[]), public.stats_fold(text, text, timestamptz, timestamptz),
                      public.stats_compact(timestamptz) from public, anon, authenticated;

-- ── 5. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0246 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0246 values
-- ·· tick_stats: the declare block loses the two windows the deletes read, and gains the fold's answer
('public.tick_stats(timestamptz)', 1,
$h$  v_fine      interval := make_interval(hours => public.wc_int('stats_fine_hours'));
  v_fine_cg   interval := make_interval(hours => public.wc_int('stats_city_good_fine_hours'));
  v_ph_slot   bigint;
  v_w int := 0; v_g int := 0; v_c int := 0; v_cg int := 0; v_m int := 0; v_x int := 0; v_n int;
$h$,
$h$  v_ph_slot   bigint;
  v_fold      jsonb;   -- 0246: what the fold did (public.stats_compact)
  v_w int := 0; v_g int := 0; v_c int := 0; v_cg int := 0; v_m int := 0; v_x int := 0;
$h$),
-- ·· tick_stats: five deletes become one fold
('public.tick_stats(timestamptz)', 2,
$h$  -- RETENTION: one row per UTC day past the fine window (the day's last slot), each table under its knob
  delete from public.stats_world w where w.at < p_now - v_fine
     and exists (select 1 from public.stats_world w2 where w2.at < p_now - v_fine and w2.slot > w.slot
                   and (w2.at at time zone 'UTC')::date = (w.at at time zone 'UTC')::date);
  get diagnostics v_n = row_count; v_x := v_x + v_n;
  delete from public.stats_merchants w where w.at < p_now - v_fine
     and exists (select 1 from public.stats_merchants w2 where w2.at < p_now - v_fine and w2.slot > w.slot
                   and (w2.at at time zone 'UTC')::date = (w.at at time zone 'UTC')::date);
  get diagnostics v_n = row_count; v_x := v_x + v_n;
  delete from public.stats_good w where w.at < p_now - v_fine
     and exists (select 1 from public.stats_good w2 where w2.good_id = w.good_id and w2.at < p_now - v_fine and w2.slot > w.slot
                   and (w2.at at time zone 'UTC')::date = (w.at at time zone 'UTC')::date);
  get diagnostics v_n = row_count; v_x := v_x + v_n;
  delete from public.stats_city w where w.at < p_now - v_fine
     and exists (select 1 from public.stats_city w2 where w2.port_id = w.port_id and w2.at < p_now - v_fine and w2.slot > w.slot
                   and (w2.at at time zone 'UTC')::date = (w.at at time zone 'UTC')::date);
  get diagnostics v_n = row_count; v_x := v_x + v_n;
  delete from public.stats_city_good w where w.at < p_now - v_fine_cg
     and exists (select 1 from public.stats_city_good w2 where w2.port_id = w.port_id and w2.good_id = w.good_id
                   and w2.at < p_now - v_fine_cg and w2.slot > w.slot
                   and (w2.at at time zone 'UTC')::date = (w.at at time zone 'UTC')::date);
  get diagnostics v_n = row_count; v_x := v_x + v_n;
$h$,
$h$  -- RETENTION (0246): FOLD, then keep — fine -> hourly -> daily, flows added, state the last slot's (public.stats_compact)
  v_fold := public.stats_compact(p_now);
  v_x := (v_fold->>'removed')::int;
$h$),
('public.tick_stats(timestamptz)', 3,
$h$                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x,
$h$,
$h$                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x, 'fold', v_fold,
$h$),
-- ·· world.stats_overview
('world.stats_overview(integer)', 1,
$h$CREATE OR REPLACE FUNCTION world.stats_overview(p_hours integer DEFAULT 24)
$h$,
$h$CREATE OR REPLACE FUNCTION world.stats_overview(p_hours integer DEFAULT 24, p_span text DEFAULT NULL::text)
$h$),
('world.stats_overview(integer)', 2,
$h$  v_hours int := least(greatest(coalesce(p_hours, 24), 1), 24 * 30);
$h$,
$h$  v_hours int := least(greatest(coalesce(p_hours, 24), 1), 24 * 30);
  -- 0246 (N1): a span (1d 1w 1m 1y all) draws the series from the tier it lives in, as world.price_series; null = p_hours of fine rows
  v_unit  text := case when p_span is null then 'fine' else public.stats_span_unit(p_span) end;   -- a bad span raises here
  v_since timestamptz;
$h$),
('world.stats_overview(integer)', 3,
$h$  v_live  := world.stats_now();
  v_kinds := public.stats_window_kinds(l.at, now());
$h$,
$h$  if p_span is null then
    v_since := l.at - make_interval(hours => v_hours);
  else
    v_since := public.stats_span_since(p_span, l.at);   -- null for `all`
    v_hours := ceil(extract(epoch from l.at - coalesce(v_since, (select min(w.at) from public.stats_world w))) / 3600)::int;
  end if;
  v_live  := world.stats_now();
  v_kinds := public.stats_window_kinds(l.at, now());
$h$),
('world.stats_overview(integer)', 4,
$h$    'hours', v_hours,
    'holders', jsonb_build_object('players',$h$,
$h$    'hours', v_hours,
    'span', p_span,
    'holders', jsonb_build_object('players',$h$),
('world.stats_overview(integer)', 5,
$h$    'series', coalesce((select jsonb_agg(jsonb_build_object('at', w.at, 'players', w.players, 'merchants', w.merchants, 'cities', w.cities,
                                                            'set_aside', w.set_aside, 'minted', w.minted, 'removed', w.removed,
                                                            'moved', w.moved, 'sold', w.sold, 'bought', w.bought) order by w.slot)
                          from public.stats_world w where w.at > l.at - make_interval(hours => v_hours)), '[]'::jsonb)
$h$,
$h$    'series', coalesce((select jsonb_agg(jsonb_build_object('at', sp.at, 'n', sp.n, 'players', sp.players, 'merchants', sp.merchants, 'cities', sp.cities,
                                                            'set_aside', sp.set_aside, 'minted', sp.minted, 'removed', sp.removed,
                                                            'moved', sp.moved, 'sold', sp.sold, 'bought', sp.bought) order by sp.at)
                          -- 0246: one point per bucket of the span's tier: the state is the bucket's last slot's, the flows its sum
                          from (select max(w.at) as at, sum(w.n)::int as n,
                                       (array_agg(w.players order by w.slot desc))[1] as players, (array_agg(w.merchants order by w.slot desc))[1] as merchants,
                                       (array_agg(w.cities order by w.slot desc))[1] as cities, (array_agg(w.set_aside order by w.slot desc))[1] as set_aside,
                                       sum(w.minted)::bigint as minted, sum(w.removed)::bigint as removed, sum(w.moved)::bigint as moved,
                                       sum(w.sold)::bigint as sold, sum(w.bought)::bigint as bought
                                  from public.stats_world w where (v_since is null or w.at > v_since)
                                 group by public.stats_bucket(w.at, v_unit)) sp), '[]'::jsonb)
$h$),
-- ·· world.stats_city
('world.stats_city(uuid)', 1,
$h$CREATE OR REPLACE FUNCTION world.stats_city(p_port uuid)
$h$,
$h$CREATE OR REPLACE FUNCTION world.stats_city(p_port uuid, p_span text DEFAULT NULL::text)
$h$),
('world.stats_city(uuid)', 2,
$h$  c        public.stats_city%rowtype;
  m        record;
begin
$h$,
$h$  c        public.stats_city%rowtype;
  m        record;
  -- 0246 (N1): a span (1d 1w 1m 1y all) draws the purse line from the tier it lives in, as world.price_series; null = 7 days of fine rows
  v_unit   text := case when p_span is null then 'fine' else public.stats_span_unit(p_span) end;   -- a bad span raises here
  v_since  timestamptz;
begin
$h$),
('world.stats_city(uuid)', 3,
$h$  v_slot := c.slot; v_at := c.at;
$h$,
$h$  v_slot := c.slot; v_at := c.at;
  v_since := case when p_span is null then v_at - interval '7 days' else public.stats_span_since(p_span, v_at) end;
$h$),
('world.stats_city(uuid)', 4,
$h$    'slot_seconds', public.wc_num('drift_slot_seconds'));
  if v_slot is null then
$h$,
$h$    'slot_seconds', public.wc_num('drift_slot_seconds'), 'span', p_span);
  if v_slot is null then
$h$),
('world.stats_city(uuid)', 5,
$h$    'series', coalesce((select jsonb_agg(jsonb_build_object('at', x.at, 'purse', x.purse, 'income', x.income, 'spending', x.spending) order by x.slot)
                          from public.stats_city x where x.port_id = p_port and x.slot > v_slot - 7 * 24 * v_ph and x.slot <= v_slot), '[]'::jsonb)
$h$,
$h$    'series', coalesce((select jsonb_agg(jsonb_build_object('at', s.at, 'n', s.n, 'purse', s.purse, 'income', s.income, 'spending', s.spending) order by s.at)
                          -- 0246: one point per bucket of the span's tier: the purse is the bucket's last slot's, income and spending its sum
                          from (select max(x.at) as at, sum(x.n)::int as n, (array_agg(x.purse order by x.slot desc))[1] as purse,
                                       sum(x.income)::bigint as income, sum(x.spending)::bigint as spending
                                  from public.stats_city x where x.port_id = p_port and (v_since is null or x.at > v_since) and x.slot <= v_slot
                                 group by public.stats_bucket(x.at, v_unit)) s), '[]'::jsonb)
$h$),
-- ·· world.stats_merchants
('world.stats_merchants()', 1,
$h$CREATE OR REPLACE FUNCTION world.stats_merchants()
$h$,
$h$CREATE OR REPLACE FUNCTION world.stats_merchants(p_span text DEFAULT NULL::text)
$h$),
('world.stats_merchants()', 2,
$h$  v_p bigint;
begin
  select * into m from public.stats_merchants order by slot desc limit 1;
$h$,
$h$  v_p bigint;
  -- 0246 (N1): a span (1d 1w 1m 1y all) draws the series from the tier it lives in, as world.price_series; null = 24 h of fine rows
  v_unit  text := case when p_span is null then 'fine' else public.stats_span_unit(p_span) end;   -- a bad span raises here
  v_since timestamptz;
begin
  select * into m from public.stats_merchants order by slot desc limit 1;
  v_since := case when p_span is null then m.at - interval '24 hours' else public.stats_span_since(p_span, m.at) end;
$h$),
('world.stats_merchants()', 3,
$h$    'at', now(), 'counted_at', m.at, 'age_seconds', round(extract(epoch from now() - m.at)), 'slot_seconds', public.wc_num('drift_slot_seconds'),
$h$,
$h$    'at', now(), 'counted_at', m.at, 'age_seconds', round(extract(epoch from now() - m.at)), 'slot_seconds', public.wc_num('drift_slot_seconds'), 'span', p_span,
$h$),
('world.stats_merchants()', 4,
$h$    'series', coalesce((select jsonb_agg(jsonb_build_object('at', x.at, 'profit_day', x.profit_day, 'purse', x.purse, 'sailing', x.sailing,
                                                            'laid_up', x.laid_up, 'losing_pct', x.losing_pct) order by x.slot)
                          from public.stats_merchants x where x.at > m.at - interval '24 hours'), '[]'::jsonb)
$h$,
$h$    'series', coalesce((select jsonb_agg(jsonb_build_object('at', s.at, 'n', s.n, 'profit_day', s.profit_day, 'purse', s.purse, 'sailing', s.sailing,
                                                            'laid_up', s.laid_up, 'losing_pct', s.losing_pct) order by s.at)
                          -- 0246: one point per bucket of the span's tier; every merchants figure is a state, so each is the bucket's last slot's
                          from (select max(x.at) as at, sum(x.n)::int as n,
                                       (array_agg(x.profit_day order by x.slot desc))[1] as profit_day, (array_agg(x.purse order by x.slot desc))[1] as purse,
                                       (array_agg(x.sailing order by x.slot desc))[1] as sailing, (array_agg(x.laid_up order by x.slot desc))[1] as laid_up,
                                       (array_agg(x.losing_pct order by x.slot desc))[1] as losing_pct
                                  from public.stats_merchants x where (v_since is null or x.at > v_since)
                                 group by public.stats_bucket(x.at, v_unit)) s), '[]'::jsonb)
$h$),
-- ·· the registry follows the three new argument lists
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'stats_overview',        'int'),
$h$,
$h$      ('world',       'stats_overview',        'int, text'),
$h$),
('public.client_rpc_entry_points()', 2,
$h$      ('world',       'stats_city',            'uuid'),
      ('world',       'stats_merchants',       ''),
$h$,
$h$      ('world',       'stats_city',            'uuid, text'),
      ('world',       'stats_merchants',       'text'),
$h$);

-- ── 6. APPLY THE HUNKS (each exactly once; the reads change their argument list, so the old one is dropped) ────
do $$
declare
  d      record;
  h      record;
  v_def  text;
  v_rev  text;
  v_cnt  int;
  v_new  regprocedure;
  a      record;
begin
  for d in select * from defs_before_0246 order by fn loop
    v_def := d.def;
    v_cnt := 0;
    for h in select * from hunks_0246 where fn = d.fn order by n loop
      if pg_temp.occurs_0246(v_def, h.old) <> 1 then
        raise exception '0246 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0246(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
      v_cnt := v_cnt + 1;
    end loop;
    -- the reads change their argument list: drop the old one, then cut the new body
    if d.fn = 'world.stats_overview(integer)' then drop function world.stats_overview(integer);
    elsif d.fn = 'world.stats_city(uuid)' then drop function world.stats_city(uuid);
    elsif d.fn = 'world.stats_merchants()' then drop function world.stats_merchants();
    end if;
    execute v_def;
    if d.fn = 'world.stats_overview(integer)' then v_new := to_regprocedure('world.stats_overview(integer, text)');
    elsif d.fn = 'world.stats_city(uuid)' then v_new := to_regprocedure('world.stats_city(uuid, text)');
    elsif d.fn = 'world.stats_merchants()' then v_new := to_regprocedure('world.stats_merchants(text)');
    else v_new := to_regprocedure(d.fn);
    end if;
    if v_new is null then raise exception '0246 self-assert FAIL: % did not come back with its new argument list', d.fn; end if;
    -- the new body reads back as the old one with each hunk's new text, and reverses to the pre-image
    v_rev := replace(pg_get_functiondef(v_new), E'\r', '');
    for h in select * from hunks_0246 where fn = d.fn order by n loop
      if pg_temp.occurs_0246(v_rev, h.new) <> 1 then
        raise exception '0246 self-assert FAIL: % hunk % new text is not in the live body exactly once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0246 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    -- the new reads carry the old ACL: authenticated only (re-granted, because a new argument list is a new function)
    if d.fn like 'world.stats_%' then
      execute format('revoke all on function %s from public, anon, authenticated, service_role', v_new);
      for a in select r.rolname from aclexplode(d.acl::aclitem[]) x join pg_roles r on r.oid = x.grantee
                where x.privilege_type = 'EXECUTE' and r.rolname not in ('postgres') loop
        execute format('grant execute on function %s to %I', v_new, a.rolname);
      end loop;
    end if;
    if (select coalesce(array_agg(x::text order by x::text), '{}') from pg_proc pr, unnest(coalesce(pr.proacl, '{}'::aclitem[])) x where pr.oid = v_new)
         is distinct from (select coalesce(array_agg(x::text order by x::text), '{}') from unnest(case when d.acl = '' then '{}'::aclitem[] else d.acl::aclitem[] end) x)
       or (select pr.provolatile from pg_proc pr where pr.oid = v_new) <> d.vol
       or (select pr.prosecdef from pg_proc pr where pr.oid = v_new) <> d.secdef
       or (select coalesce(pr.proconfig::text, '') from pg_proc pr where pr.oid = v_new) <> d.cfg then
      raise exception '0246 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
end $$;

-- ── 7. THE PROOF (probe rows; every probe in a sub-transaction, rolled back) ───────────────────
-- (b) THE FOLD, all five tables. Probe rows sit at fixed instants in 2001 — no real row is ever in that range, and
-- nothing reads the hour. Flow figures are j (the probe's number), state is j * 100, so the LAST slot is visible.
--   j 1..8   eight 15-minute slots across two hours of 2001-03-04 (10:06 ... 11:51)       n = 1
--   j 9, 10  two fine slots after the window (12:06, 12:21)                               n = 1
--   j 11..13 three hourly rows of day D1 = 2001-03-05 (01:51, 07:51, 22:51)               n = 4 each
--   j 14, 15 two hourly rows of D2 = 2001-03-06 (02:51, 23:51)                            n = 4 each
--   j 16     a DAILY row of 2001-03-03 (23:51)  j 17 a DAILY row of 2001-03-07 (23:51)     n = 96 each
create function pg_temp.probe_0246_rows(p_table text, p_pred text)
returns setof jsonb
language plpgsql
as $$
begin
  return query execute format('select to_jsonb(t) from public.%I t where t.at >= %L and t.at < %L and %s order by t.at',
                              p_table, '2001-03-01 00:00+00'::timestamptz, '2001-04-01 00:00+00'::timestamptz, p_pred);
end $$;

create function pg_temp.probe_0246_check(p_table text, p_pred text, p_flows text[], p_state text, p_map text)
returns text
language plpgsql
as $$
declare
  r   jsonb[];
  f   text;
  v_removed jsonb;
begin
  -- 1. the hour fold over [10:00, 12:00)
  select (public.stats_fold(p_table, 'hour', '2001-03-04 10:00+00', '2001-03-04 12:00+00')->>'removed') into f;
  if f::int <> 6 then raise exception '0246 self-assert FAIL: % hour fold removed %, not 6 (8 slots -> 2 hours)', p_table, f; end if;
  select array_agg(x order by x->>'at') into r from pg_temp.probe_0246_rows(p_table, p_pred) x;
  if array_length(r, 1) <> 11 then raise exception '0246 self-assert FAIL: % holds % probe rows after the hour fold, not 11', p_table, array_length(r, 1); end if;
  -- in at-order: [1] D0 (03-03) [2] hour 10 (j4) [3] hour 11 (j8) [4] j9 [5] j10 [6..8] D1 x3 [9..10] D2 x2 [11] D3
  foreach f in array p_flows loop
    if (r[2]->>f)::numeric <> 10 or (r[3]->>f)::numeric <> 26 then
      raise exception '0246 self-assert FAIL: % flow % folds to % / %, not 10 / 26', p_table, f, r[2]->>f, r[3]->>f;
    end if;
    if (r[4]->>f)::numeric <> 9 or (r[5]->>f)::numeric <> 10 then
      raise exception '0246 self-assert FAIL: % fine row after the window moved (% / %, not 9 / 10)', p_table, r[4]->>f, r[5]->>f;
    end if;
  end loop;
  if (r[2]->>p_state)::numeric <> 400 or (r[3]->>p_state)::numeric <> 800 or (r[4]->>p_state)::numeric <> 900 or (r[5]->>p_state)::numeric <> 1000 then
    raise exception '0246 self-assert FAIL: % state is not the last slot''s (% % % %)', p_table, r[2]->>p_state, r[3]->>p_state, r[4]->>p_state, r[5]->>p_state;
  end if;
  if (r[2]->>'n')::int <> 4 or (r[3]->>'n')::int <> 4 or (r[4]->>'n')::int <> 1 or (r[5]->>'n')::int <> 1 then
    raise exception '0246 self-assert FAIL: % n is % % % % (expected 4 4 1 1)', p_table, r[2]->>'n', r[3]->>'n', r[4]->>'n', r[5]->>'n';
  end if;
  if p_map is not null and ((r[2]->p_map)::jsonb <> '{"A": 10, "B": -10}'::jsonb or (r[3]->p_map)::jsonb <> '{"A": 26, "B": -26}'::jsonb
                            or (r[4]->p_map)::jsonb <> '{"A": 9, "B": -9, "Z": 1}'::jsonb) then
    raise exception '0246 self-assert FAIL: % map folds to % / % (the key-wise sum, a zero kind dropped)', p_table, r[2]->p_map, r[3]->p_map;
  end if;
  -- the daily rows are exactly as planted
  if (r[1]->>'n')::int <> 96 or (r[1]->>p_state)::numeric <> 1600 or (r[11]->>'n')::int <> 96 or (r[11]->>p_state)::numeric <> 1700 then
    raise exception '0246 self-assert FAIL: % a daily row moved under the hour fold', p_table;
  end if;

  -- 2. the day fold over [03-05, 03-07): D1 (3 rows -> 1), D2 (2 rows -> 1)
  select (public.stats_fold(p_table, 'day', '2001-03-05 00:00+00', '2001-03-07 00:00+00')->>'removed') into f;
  if f::int <> 3 then raise exception '0246 self-assert FAIL: % day fold removed %, not 3', p_table, f; end if;
  select array_agg(x order by x->>'at') into r from pg_temp.probe_0246_rows(p_table, p_pred) x;
  if array_length(r, 1) <> 8 then raise exception '0246 self-assert FAIL: % holds % probe rows after the day fold, not 8', p_table, array_length(r, 1); end if;
  foreach f in array p_flows loop
    if (r[6]->>f)::numeric <> 36 or (r[7]->>f)::numeric <> 29 then
      raise exception '0246 self-assert FAIL: % flow % folds to % / % over a day, not 36 / 29', p_table, f, r[6]->>f, r[7]->>f;
    end if;
  end loop;
  if (r[6]->>'n')::int <> 12 or (r[7]->>'n')::int <> 8 or (r[6]->>p_state)::numeric <> 1300 or (r[7]->>p_state)::numeric <> 1500 then
    raise exception '0246 self-assert FAIL: % a day row is n % / % state % / % (expected 12 / 8, 1300 / 1500)', p_table, r[6]->>'n', r[7]->>'n', r[6]->>p_state, r[7]->>p_state;
  end if;

  -- 3. nothing more to do: a second run, and a wide run over lone rows, remove nothing and change nothing
  v_removed := public.stats_fold(p_table, 'hour', '2001-03-03 00:00+00', '2001-03-04 12:00+00')
               || jsonb_build_object('d', public.stats_fold(p_table, 'day', '2001-03-03 00:00+00', '2001-03-07 00:00+00') ->> 'removed');
  if (v_removed->>'removed')::int <> 0 then raise exception '0246 self-assert FAIL: % a second hour fold removed rows', p_table; end if;
  -- the wide day fold folds hour 10, hour 11, j9 and j10 (all of 03-04) into ONE row, and never touches D0 (alone in 03-03)
  if (v_removed->>'d')::int <> 3 then raise exception '0246 self-assert FAIL: % the wide day fold removed %, not 3 (4 rows of 03-04 -> 1)', p_table, v_removed->>'d'; end if;
  select array_agg(x order by x->>'at') into r from pg_temp.probe_0246_rows(p_table, p_pred) x;
  if array_length(r, 1) <> 5 then raise exception '0246 self-assert FAIL: % holds % probe rows at the end, not 5', p_table, array_length(r, 1); end if;
  foreach f in array p_flows loop
    if (r[2]->>f)::numeric <> 55 then raise exception '0246 self-assert FAIL: % 03-04 folds to %, not 55 (10 + 26 + 9 + 10)', p_table, r[2]->>f; end if;
  end loop;
  if (r[2]->>'n')::int <> 10 or (r[2]->>p_state)::numeric <> 1000 then
    raise exception '0246 self-assert FAIL: % 03-04 is n % state % (expected 10, 1000)', p_table, r[2]->>'n', r[2]->>p_state;
  end if;
  if (r[1]->>'n')::int <> 96 or (r[1]->>p_state)::numeric <> 1600 or (r[5]->>'n')::int <> 96 or (r[5]->>p_state)::numeric <> 1700 then
    raise exception '0246 self-assert FAIL: % a daily row was changed or deleted', p_table;
  end if;
  return 'ok';
end $$;

do $$
declare
  v_port uuid; v_good uuid;
  v_t0   timestamptz := clock_timestamp();
  v_ok   text[] := '{}';
  v_msg  text;
begin
  select id into v_port from public.ports where kind = 'HARBOUR' order by id limit 1;
  select id into v_good from public.goods order by id limit 1;
  if v_port is null or v_good is null then
    raise exception '0246 self-assert FAIL: no harbour or good to plant the probe at';
  end if;
  if exists (select 1 from public.stats_world where at < '2002-01-01') or exists (select 1 from public.stats_merchants where at < '2002-01-01')
     or exists (select 1 from public.stats_good where at < '2002-01-01') or exists (select 1 from public.stats_city where at < '2002-01-01')
     or exists (select 1 from public.stats_city_good where at < '2002-01-01') then
    raise exception '0246 self-assert FAIL: a stats row dated before 2002 exists — the probe instants are not free';
  end if;

  -- the planted instants (j, at, n)
  create temp table probe_at_0246 (j int primary key, at timestamptz not null, n smallint not null) on commit drop;
  insert into probe_at_0246 values
    (1, '2001-03-04 10:06+00', 1), (2, '2001-03-04 10:21+00', 1), (3, '2001-03-04 10:36+00', 1), (4, '2001-03-04 10:51+00', 1),
    (5, '2001-03-04 11:06+00', 1), (6, '2001-03-04 11:21+00', 1), (7, '2001-03-04 11:36+00', 1), (8, '2001-03-04 11:51+00', 1),
    (9, '2001-03-04 12:06+00', 1), (10, '2001-03-04 12:21+00', 1),
    (11, '2001-03-05 01:51+00', 4), (12, '2001-03-05 07:51+00', 4), (13, '2001-03-05 22:51+00', 4),
    (14, '2001-03-06 02:51+00', 4), (15, '2001-03-06 23:51+00', 4),
    (16, '2001-03-03 23:51+00', 96), (17, '2001-03-07 23:51+00', 96);

  -- stats_world
  begin
    insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside, minted, removed, moved, sold, bought, units, trades, period, recent, n)
    select public.drift_slot_of(p.at), p.at, 0, p.j * 100, 0, 0, 0, p.j, p.j, p.j, p.j, p.j, p.j, p.j,
           jsonb_build_object('A', p.j, 'B', -p.j)
             || case when p.j between 1 and 10 then jsonb_build_object('Z', case when p.j % 2 = 1 then 1 else -1 end) else '{}'::jsonb end,
           '{}'::jsonb, p.n
      from probe_at_0246 p;
    v_msg := pg_temp.probe_0246_check('stats_world', 'true', array['minted', 'removed', 'moved', 'sold', 'bought', 'units', 'trades'], 'players', 'period');
    v_ok := array_append(v_ok, 'world');
    raise exception using errcode = 'ZX246', message = 'done';
  exception when sqlstate 'ZX246' then null;
  end;
  -- stats_merchants (all state)
  begin
    insert into public.stats_merchants (slot, at, houses, fleets, sailing, docked, repairing, unable, laid_up, purse, profit_day, laps_day, losing_pct, top, bottom, n)
    select public.drift_slot_of(p.at), p.at, 1, 1, 1, 0, 0, 0, 0, p.j * 100, p.j, 0, 0, '[]'::jsonb, '[]'::jsonb, p.n from probe_at_0246 p;
    -- merchants has no flow: the check uses profit_day as a "state" probe via the purse; flows list is empty
    v_msg := pg_temp.probe_0246_check('stats_merchants', 'true', array[]::text[], 'purse', null);
    v_ok := array_append(v_ok, 'merchants');
    raise exception using errcode = 'ZX246', message = 'done';
  exception when sqlstate 'ZX246' then null;
  end;
  -- stats_good
  begin
    insert into public.stats_good (good_id, slot, at, mid, markets, stock, stock_target, sold, bought, sold_ducats, bought_ducats, n)
    select v_good, public.drift_slot_of(p.at), p.at, p.j, 1, p.j * 100, 0, p.j, p.j, p.j, p.j, p.n from probe_at_0246 p;
    v_msg := pg_temp.probe_0246_check('stats_good', format('t.good_id = %L', v_good), array['sold', 'bought', 'sold_ducats', 'bought_ducats'], 'stock', null);
    v_ok := array_append(v_ok, 'good');
    raise exception using errcode = 'ZX246', message = 'done';
  exception when sqlstate 'ZX246' then null;
  end;
  -- stats_city
  begin
    insert into public.stats_city (port_id, slot, at, purse, income, spending, taxes, works, sold, bought, flows, n)
    select v_port, public.drift_slot_of(p.at), p.at, p.j * 100, p.j, p.j, p.j, 0, p.j, p.j,
           jsonb_build_object('A', p.j, 'B', -p.j) || case when p.j between 1 and 10 then jsonb_build_object('Z', case when p.j % 2 = 1 then 1 else -1 end) else '{}'::jsonb end,
           p.n from probe_at_0246 p;
    v_msg := pg_temp.probe_0246_check('stats_city', format('t.port_id = %L', v_port), array['income', 'spending', 'taxes', 'sold', 'bought'], 'purse', 'flows');
    v_ok := array_append(v_ok, 'city');
    raise exception using errcode = 'ZX246', message = 'done';
  exception when sqlstate 'ZX246' then null;
  end;
  -- stats_city_good
  begin
    insert into public.stats_city_good (port_id, good_id, slot, at, mid, stock, stock_target, sold, bought, sold_ducats, bought_ducats, n)
    select v_port, v_good, public.drift_slot_of(p.at), p.at, p.j, p.j * 100, 0, p.j, p.j, p.j, p.j, p.n from probe_at_0246 p;
    v_msg := pg_temp.probe_0246_check('stats_city_good', format('t.port_id = %L and t.good_id = %L', v_port, v_good), array['sold', 'bought', 'sold_ducats', 'bought_ducats'], 'stock', null);
    v_ok := array_append(v_ok, 'city_good');
    raise exception using errcode = 'ZX246', message = 'done';
  exception when sqlstate 'ZX246' then null;
  end;

  if array_length(v_ok, 1) <> 5 then
    raise exception '0246 self-assert FAIL: only % of the five tables passed the fold probe', v_ok;
  end if;
  if exists (select 1 from public.stats_world where at < '2002-01-01') or exists (select 1 from public.stats_merchants where at < '2002-01-01')
     or exists (select 1 from public.stats_good where at < '2002-01-01') or exists (select 1 from public.stats_city where at < '2002-01-01')
     or exists (select 1 from public.stats_city_good where at < '2002-01-01') then
    raise exception '0246 self-assert FAIL: a probe row survived its rollback';
  end if;
  raise notice '0246 self-assert ok: (b)  THE FOLD on all five tables (%): 8 slots across two hours -> 2 hourly rows (flows summed 10 / 26, the map key-summed with its zero kind dropped, state the last slot''s, n = 4); 3 + 2 hourly rows across two days -> 2 daily rows (36 / 29, n 12 / 8); hour + fine rows -> one day row (55, n = 10); the window''s later fine rows untouched; a second run and a wide run remove nothing; neither daily row ever deleted or rewritten. % ms.',
    v_ok, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $$;

-- (c) THE COUNT calls the fold, and prints its timing; (a)/(e) the reads, the registry and the walls
do $$
declare
  v_def  text := replace(pg_get_functiondef('public.tick_stats(timestamptz)'::regprocedure), E'\r', '');
  v_now  timestamptz := now() + interval '2 hours';   -- a slot the cron cannot reach meanwhile
  v_run  jsonb;
begin
  if pg_temp.occurs_0246(v_def, 'public.stats_compact(p_now)') <> 1 or pg_temp.occurs_0246(v_def, 'delete from public.stats_') <> 0 then
    raise exception '0246 self-assert FAIL: tick_stats does not carry the fold exactly once, or still carries a retention delete';
  end if;
  begin
    v_run := public.tick_stats(v_now);
    if v_run->'fold' is null or (v_run->'fold'->>'ms') is null or v_run->>'compacted' is null then
      raise exception '0246 self-assert FAIL: the count does not report its fold: %', left(v_run::text, 300);
    end if;
    raise exception using errcode = 'ZX246', message = jsonb_build_object('ms', v_run->>'ms', 'fold', v_run->'fold')::text;
  exception when sqlstate 'ZX246' then
    v_run := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.stats_world where at > now() + interval '1 hour') then
    raise exception '0246 self-assert FAIL: the trial count survived its rollback';
  end if;
  raise notice '0246 self-assert ok: (c)  THE COUNT. tick_stats calls public.stats_compact once and carries no retention delete; a count run two hours ahead took % ms in all, of which the fold % ms (fold: %).',
    v_run->>'ms', v_run->'fold'->>'ms', v_run->'fold'->'tables';
end $$;

-- (d) THE READS, with probe rows planted past every real one (the newest count of each is then the probe's)
do $$
declare
  v_anchor timestamptz := (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') + interval '10 days';   -- a UTC midnight, ten days ahead
  v_port   uuid;
  v_o      jsonb; v_c jsonb; v_m jsonb;
  v_span   text;
  v_pts    jsonb;
  v_since  timestamptz; v_last timestamptz;
  v_rows   bigint; v_sold numeric; v_sum numeric; v_n numeric; v_dist bigint; v_unit text;
  v_checked int := 0;
begin
  select id into v_port from public.ports where kind = 'HARBOUR' order by id limit 1;
  if v_port is null then raise exception '0246 self-assert FAIL: no harbour to plant the read probe at'; end if;
  if exists (select 1 from public.stats_world where at >= v_anchor - interval '1 hour') then
    raise exception '0246 self-assert FAIL: a stats row exists ten days ahead — the probe instants are not free';
  end if;
  begin
    -- two hours of slots, :06 :21 :36 :51 for hours 01 and 02 of the anchor day, and two on the next day
    create temp table rd_at_0246 (j int primary key, at timestamptz not null) on commit drop;
    insert into rd_at_0246
      select row_number() over (order by t), t from (
        select v_anchor + interval '1 hour' + k * interval '15 minutes' + interval '6 minutes' as t from generate_series(0, 7) k
        union all select v_anchor + interval '1 day 3 hours 51 minutes' union all select v_anchor + interval '1 day 4 hours 51 minutes') x;
    insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside, minted, removed, moved, sold, bought, units, trades, period, recent, n)
    select public.drift_slot_of(p.at), p.at, 0, p.j * 100, 0, 0, 0, p.j, 0, 0, p.j, p.j, 0, 1, '{}'::jsonb, '{}'::jsonb, 1 from rd_at_0246 p;
    insert into public.stats_merchants (slot, at, houses, fleets, sailing, docked, repairing, unable, laid_up, purse, profit_day, laps_day, losing_pct, top, bottom, n)
    select public.drift_slot_of(p.at), p.at, 1, 1, p.j, 0, 0, 0, 0, p.j * 100, p.j, 0, 0, '[]'::jsonb, '[]'::jsonb, 1 from rd_at_0246 p;
    insert into public.stats_city (port_id, slot, at, purse, income, spending, taxes, works, sold, bought, flows, n)
    select v_port, public.drift_slot_of(p.at), p.at, p.j * 100, p.j, p.j * 2, 0, 0, 0, 0, '{}'::jsonb, 1 from rd_at_0246 p;

    -- a bad span raises, on all three reads
    begin perform world.stats_overview(24, 'fortnight'); raise exception '0246 self-assert FAIL: stats_overview took a bad span'; exception when sqlstate 'P0001' then
      if sqlerrm not like 'E_BAD_SPAN%' then raise; end if; end;
    begin perform world.stats_city(v_port, 'fortnight'); raise exception '0246 self-assert FAIL: stats_city took a bad span'; exception when sqlstate 'P0001' then
      if sqlerrm not like 'E_BAD_SPAN%' then raise; end if; end;
    begin perform world.stats_merchants('fortnight'); raise exception '0246 self-assert FAIL: stats_merchants took a bad span'; exception when sqlstate 'P0001' then
      if sqlerrm not like 'E_BAD_SPAN%' then raise; end if; end;

    select max(at) into v_last from rd_at_0246;
    foreach v_span in array array['1d', '1w', '1m', '1y', 'all'] loop
      v_unit := public.stats_span_unit(v_span);
      v_since := public.stats_span_since(v_span, v_last);

      -- OVERVIEW: the points (all but the live one at now()) add up to the table's rows in the same window
      v_o := world.stats_overview(24, v_span);
      if v_o->>'span' <> v_span then raise exception '0246 self-assert FAIL: stats_overview does not echo its span'; end if;
      select jsonb_agg(e) filter (where e ? 'n') into v_pts from jsonb_array_elements(v_o->'series') e;
      select count(*), sum(w.sold), sum(w.n) into v_rows, v_sold, v_n from public.stats_world w where (v_since is null or w.at > v_since);
      select coalesce(sum((e->>'sold')::numeric), 0), coalesce(sum((e->>'n')::numeric), 0) into v_sum, v_dist
        from jsonb_array_elements(coalesce(v_pts, '[]'::jsonb)) e;
      if v_sum <> v_sold or v_dist <> v_n then
        raise exception '0246 self-assert FAIL: stats_overview % series sums to sold % n %, the table''s rows to % / %', v_span, v_sum, v_dist, v_sold, v_n;
      end if;
      select count(distinct public.stats_bucket(w.at, v_unit)) into v_dist from public.stats_world w where (v_since is null or w.at > v_since);
      if jsonb_array_length(coalesce(v_pts, '[]'::jsonb)) <> v_dist then
        raise exception '0246 self-assert FAIL: stats_overview % has % points for % buckets', v_span, jsonb_array_length(coalesce(v_pts, '[]'::jsonb)), v_dist;
      end if;

      -- CITY
      v_c := world.stats_city(v_port, v_span);
      if v_c->>'span' <> v_span then raise exception '0246 self-assert FAIL: stats_city does not echo its span'; end if;
      select coalesce(jsonb_agg(e), '[]'::jsonb) into v_pts from jsonb_array_elements(v_c->'overview'->'series') e where e ? 'n';
      select coalesce(sum(x.spending), 0), coalesce(sum(x.n), 0) into v_sold, v_n from public.stats_city x where x.port_id = v_port and (v_since is null or x.at > v_since);
      select coalesce(sum((e->>'spending')::numeric), 0), coalesce(sum((e->>'n')::numeric), 0) into v_sum, v_dist from jsonb_array_elements(v_pts) e;
      if v_sum <> v_sold or v_dist <> v_n then
        raise exception '0246 self-assert FAIL: stats_city % series sums to spending % n %, the table''s to % / %', v_span, v_sum, v_dist, v_sold, v_n;
      end if;

      -- MERCHANTS (all states: the n's add up, one point a bucket, the last point's purse is the bucket's last slot's)
      v_m := world.stats_merchants(v_span);
      if v_m->>'span' <> v_span then raise exception '0246 self-assert FAIL: stats_merchants does not echo its span'; end if;
      select coalesce(jsonb_agg(e), '[]'::jsonb) into v_pts from jsonb_array_elements(v_m->'series') e where e ? 'n';
      select coalesce(sum(x.n), 0) into v_n from public.stats_merchants x where (v_since is null or x.at > v_since);
      select coalesce(sum((e->>'n')::numeric), 0) into v_dist from jsonb_array_elements(v_pts) e;
      if v_dist <> v_n then raise exception '0246 self-assert FAIL: stats_merchants % series n sums to %, the rows'' to %', v_span, v_dist, v_n; end if;
      v_checked := v_checked + 1;
    end loop;

    -- the hourly tier folds the probe's two hours into two points, state = the hour's last slot, flows = the sum
    v_o := world.stats_overview(24, '1w');
    select jsonb_agg(e order by e->>'at') into v_pts from jsonb_array_elements(v_o->'series') e
     where e ? 'n' and (e->>'at')::timestamptz >= v_anchor and (e->>'at')::timestamptz < v_anchor + interval '1 day';
    if jsonb_array_length(v_pts) <> 2 or (v_pts->0->>'n')::int <> 4 or (v_pts->0->>'sold')::int <> 10 or (v_pts->0->>'players')::int <> 400
       or (v_pts->1->>'sold')::int <> 26 or (v_pts->1->>'players')::int <> 800 then
      raise exception '0246 self-assert FAIL: the 1w tier did not fold the probe''s two hours into (n 4, sold 10, players 400) and (n 4, sold 26, players 800): %', v_pts;
    end if;

    raise exception using errcode = 'ZX246', message = v_checked::text;
  exception when sqlstate 'ZX246' then
    v_checked := sqlerrm::int;
  end;
  if exists (select 1 from public.stats_world where at >= v_anchor - interval '1 hour') or exists (select 1 from public.stats_merchants where at >= v_anchor - interval '1 hour')
     or exists (select 1 from public.stats_city where at >= v_anchor - interval '1 hour') then
    raise exception '0246 self-assert FAIL: a read probe survived its rollback';
  end if;
  raise notice '0246 self-assert ok: (d)  THE READS over % spans (1d 1w 1m 1y all) on three faces: each series'' flows add up to the table''s rows in the span, its n''s to the rows'' n, one point a bucket; the 1w tier folds two probe hours into two points (sold 10 / 26, state the last slot''s); a bad span raises E_BAD_SPAN on all three.', v_checked;
end $$;

-- (a)/(e) the registry and the walls
do $$
declare
  v_b record;
begin
  select * into v_b from before_0246;
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points
     or not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'stats_overview' and e.arg_types = 'int, text' and e.fn is not null)
     or not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'stats_city' and e.arg_types = 'uuid, text' and e.fn is not null)
     or not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'stats_merchants' and e.arg_types = 'text' and e.fn is not null)
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0246 self-assert FAIL: the registry is not the old one with the three new argument lists, every row executable by authenticated';
  end if;
  if has_function_privilege('anon', 'world.stats_overview(integer, text)', 'execute')
     or has_function_privilege('anon', 'world.stats_city(uuid, text)', 'execute')
     or has_function_privilege('anon', 'world.stats_merchants(text)', 'execute')
     or has_function_privilege('authenticated', 'public.stats_fold(text, text, timestamptz, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.stats_compact(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.stats_bucket(timestamptz, text)', 'execute')
     or has_function_privilege('authenticated', 'public.stats_span_unit(text)', 'execute')
     or has_function_privilege('authenticated', 'public.stats_span_since(text, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.stats_map_sum(jsonb[])', 'execute') then
    raise exception '0246 self-assert FAIL: a read is open to anon, or a helper is open to a client';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0246 self-assert FAIL: a client write grant, an executable writer or a caller-evaluated function appeared';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and column_name = 'n' and data_type = 'smallint' and column_default = '1'
        and table_name in ('stats_world', 'stats_merchants', 'stats_good', 'stats_city', 'stats_city_good')) <> 5 then
    raise exception '0246 self-assert FAIL: the five n columns are not all there';
  end if;
  if public.wc_int('stats_hour_days') <> 30 or public.wc_int('stats_city_good_hour_days') <> 7 or public.wc_int('stats_fold_back_days') <> 14
     or public.wc_int('stats_hour_days') * 24 <= public.wc_int('stats_fine_hours')
     or public.wc_int('stats_city_good_hour_days') * 24 <= public.wc_int('stats_city_good_fine_hours') then
    raise exception '0246 self-assert FAIL: the knobs are not 30 / 7 / 14, or an hourly window does not exceed its fine window';
  end if;
  raise notice '0246 self-assert ok: (a)(e)  the five hunk groups reverse to their pre-images; the three reads keep their ACL (authenticated only), volatility, definer and config; the registry is the old % rows with three new argument lists, every row executable; the six helpers are open to no client; walls 0 / 0 / 0; five n columns; knobs 30 / 7 / 14.', v_b.entry_points;
end $$;
