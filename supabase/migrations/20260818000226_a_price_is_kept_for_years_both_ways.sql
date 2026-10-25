-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0226 — A PRICE IS KEPT FOR YEARS, BOTH WAYS
--        (the record keeps what a city PAYS as well as what it ASKS; fine points for a day, an hour's
--         open/high/low/close for a month, a day's for ever; ONE read for every chart, by span)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md rows 189 and 205) ───────────────────────────────
--   189 (2026-10-25): "why is the selling price chart is flat? where as buying chart is good?"
--   205 (2026-10-26): "the chart and data of the game, is it too far for me to ask to save like all
--        the price data graph? right now i can see up to 24 hours, but i want to see them in weeks,
--        years even. only by charts? is this possible?"
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
--   * public.tick_price_snapshot (0013:97, re-cut by 0057:302, 0061:361 and 0170:270) records ONE
--     figure, the mid, and only `where public.port_offers(pg.port_id, pg.good_id)` — so a city that
--     only BUYS a good has no row at all, world.price_history serves nothing for it, and the client
--     (src/features/command/markets/GoodChart.tsx:110) draws the estimate alone: row 189's flat line.
--   * public.price_history_window() (0057:214) keeps greatest(48, 600 MiB ÷ (ALL 138,990 pairs × 201 B))
--     = 48 slots of 900 s = 12 h, and the same number prunes the table. Nothing older exists to read.
--   * world.price_history(uuid, int) (0013:139, re-cut 0057:313, 0183:158) is the only chart read,
--     and it can only answer in slots of that window.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   1. BOTH SIDES. price_history gains `ask` (what the city asks, null where it does not sell the
--      good — 0061's law: a price nobody can buy at is not a record) and `bid` (what it pays). Both
--      come from THE ONE pricing authority: world.price(port, good) is world.mid_price + world.price_terms
--      + world.price_sides (0170), and the writer composes those same three leaves set-wise — the
--      terms once a port, the mid once a pair — exactly as world.price_outlook does. The self-assert
--      proves the recorded sides equal world.price's to the cent. NO second formula.
--   2. WHICH PAIRS. Every pair a city SELLS (1,380 on production) and every pair a player has asked
--      to see (public.price_watch, written by cmd.watch_price the first time a chart opens on a city
--      that only buys the good; capped by price_watch_cap, the stalest ask making room). THE ARITHMETIC
--      THAT FORBIDS "EVERY PAIR": 138,990 pairs × 365 days × ~150 B a day row = 7.6 GB a YEAR on an
--      8 GB plan, and the fine tier alone for all pairs at 24 h = 13.3M rows. So "every pair a city
--      buys" is kept as "every pair anyone has looked at", and the header of docs/dev-log/
--      2026-10-26-price-history.md carries the measured sizes.
--   3. THREE TIERS, ONE JOB. price_history keeps price_history_fine_slots (96 = 24 h) fine points;
--      price_history_hour keeps an hour's open/high/low/close of both sides for price_history_hour_days
--      (30); price_history_day keeps a UTC day's for ever. tick_price_snapshot — the SAME cron job,
--      byeharu-voyage:price-snapshot, no new schedule — records, then folds fine → hour and hour → day
--      from the marks in public.price_rollup (set-based, only the hours and days that have finished),
--      then prunes the fine window (0057's law, now over the RECORDED pairs) and hours beyond 30 days.
--      Day rows are never deleted.
--   4. ONE READ. world.price_series(port, good, span) with span in 1d / 1w / 1m / 1y / all picks the
--      tier by span and serves both sides of every point. world.price_history(uuid, int) is DROPPED and
--      leaves the registry: no second path stands beside the new one.
--   5. BACKFILL, ONCE. The 48 slots production already holds carry a mid only; their sides are made
--      here from that recorded mid and the port's terms AS THEY STAND AT THIS DEPLOY (spread, tax,
--      purse factor), through world.price_sides — the only point where a recorded side is not from the
--      tick that recorded its mid; stated, bounded to 12 hours of history. Then the job runs once so the
--      hours already kept are folded.
--
-- ── SUPERSEDES ──────────────────────────────────────────────────────────────────────────────────
--   * public.tick_price_snapshot: 0013:97 as re-cut by 0057:302 (window), 0061:361 (offered pairs) and
--     0170:270 (prune rows numbered on another clock) — SUPERSEDED whole by `create or replace` below;
--     every one of those three rules is carried (window, roster for the ASK, the 0170 prune).
--   * public.price_history_window: 0057:214 — SUPERSEDED: the budget law stands (price_history_window_for
--     is untouched) but it now divides by the pairs the record KEEPS, capped at price_history_fine_slots.
--   * world.price_history(uuid, int): 0013:139 — DROPPED (see 4).
--   * public.tick_stats (0214:328): two hunks RE-CUT — its city-good key set and its mid join read
--     price_history, which until today held offered pairs only; both now say `and public.port_offers`,
--     so the Stats tab's city goods stay "the goods the city sells", a no-op on today's rows.
--   * public.client_rpc_entry_points: two hunks RE-CUT — price_history leaves, price_series and
--     watch_price join.
--
-- ── WHAT IT DELIBERATELY DOES NOT TOUCH ─────────────────────────────────────────────────────────
--   * public.stats_city_good (0214) — the Stats tab's books, a sample of the mid the day's last slot,
--     gated at tier 2. It is not a chart record and does not become one; the chart's record is here.
--   * world.price_outlook (0170) — the ESTIMATE to the right of now is unchanged; the chart draws it
--     beside the record as before.
--   * price_history's `mid` and `stock` — every reader of them (world.watchlist, world.good_board,
--     tick_stats) reads the same columns it did.
--
-- Depends on: 0005 (port_goods, world.mid_price), 0013 (price_history, drift_slot_of, the cron),
-- 0057 (price_history_window_for), 0061 (port_offers), 0136 (port_offered_goods), 0170 (price_terms,
-- price_sides, world.price), 0214 (tick_stats), 0018 (current_player_id, the registry).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create or replace function pg_temp.occurs_0226(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES of the two bodies this file re-cuts (LF-normalised), with their ACL / volatility /
--       definer / config, so the self-assert can prove each reverses and nothing else moved ──────────
create temp table defs_before_0226 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_stats(timestamptz)'), ('public.client_rpc_entry_points()')) f(fn);

create temp table before_0226 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- ── 1. THE KNOBS ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('price_history_fine_slots', to_jsonb(96),
   '0226: how many drift slots of FINE price points the record keeps per recorded (city, good) pair — 96 × 900 s = 24 h, the 1-day chart. public.price_history_window() is the lesser of this and 0057''s disk-budget figure, never under 48.'),
  ('price_history_hour_days', to_jsonb(30),
   '0226: how many days of HOURLY open/high/low/close the record keeps per pair (the 1-week and 1-month charts). Day rows are kept for ever.'),
  ('price_watch_cap', to_jsonb(2000),
   '0226: how many (city, good) pairs a city does NOT sell may be recorded because a player asked (cmd.watch_price). Beyond it the stalest ask stops being recorded; its day rows stay. 2,000 + the 1,380 offered pairs = 3,380 recorded pairs: measured 189 / 213 / 201 bytes a row (fine / hour / day, heap + index), so about 60 MB fine + 520 MB hourly steady and 250 MB of day rows a year.')
on conflict (key) do nothing;

-- ── 2. THE TABLES ───────────────────────────────────────────────────────────────────────────────
-- Both sides on the fine record. Null `ask` = the city does not sell the good (0061). Null `bid` only
-- on a row older than this file, and the backfill below leaves none.
alter table public.price_history
  add column if not exists ask numeric(12,2) check (ask > 0),
  add column if not exists bid numeric(12,2) check (bid > 0);
comment on column public.price_history.ask is
  '0226: what the city ASKED a unit at sample time — world.price(port, good).ask, the one authority''s own side; null where the city does not sell the good.';
comment on column public.price_history.bid is
  '0226: what the city PAID a unit at sample time — world.price(port, good).bid.';

-- An hour of both sides. Row ≈ 24 B header + 16 + 16 + 8 + 8 numerics(12,2) at 5–9 B each + 2 ≈ 120 B,
-- plus its one index (≈ 60 B): measured in the dev-log, not assumed here.
create table public.price_history_hour (
  port_id uuid not null references public.ports(id) on delete cascade,
  good_id uuid not null references public.goods(id) on delete cascade,
  hour    timestamptz not null,
  ask_o numeric(12,2), ask_h numeric(12,2), ask_l numeric(12,2), ask_c numeric(12,2),
  bid_o numeric(12,2) not null, bid_h numeric(12,2) not null, bid_l numeric(12,2) not null, bid_c numeric(12,2) not null,
  n smallint not null check (n > 0),
  primary key (port_id, good_id, hour)
);
comment on table public.price_history_hour is
  '0226: one finished hour of one good at one city: the open, high, low and close of what it asked (null where it does not sell the good) and of what it paid, folded from price_history by tick_price_snapshot; n = fine points folded. Kept price_history_hour_days. Server-only; world.price_series serves it.';

create table public.price_history_day (
  port_id uuid not null references public.ports(id) on delete cascade,
  good_id uuid not null references public.goods(id) on delete cascade,
  day     date not null,
  ask_o numeric(12,2), ask_h numeric(12,2), ask_l numeric(12,2), ask_c numeric(12,2),
  bid_o numeric(12,2) not null, bid_h numeric(12,2) not null, bid_l numeric(12,2) not null, bid_c numeric(12,2) not null,
  n smallint not null check (n > 0),
  primary key (port_id, good_id, day)
);
comment on table public.price_history_day is
  '0226: one finished UTC day of one good at one city, folded from price_history_hour; n = fine points in the day. KEPT FOR EVER — nothing deletes a day row. Server-only; world.price_series serves it.';

-- The pairs a player asked to see at a city that does not sell the good.
create sequence public.price_watch_seq;
create table public.price_watch (
  port_id   uuid not null references public.ports(id) on delete cascade,
  good_id   uuid not null references public.goods(id) on delete cascade,
  since     timestamptz not null default now(),
  asked_at  timestamptz not null default now(),
  asked_seq bigint not null default nextval('public.price_watch_seq'),
  primary key (port_id, good_id)
);
comment on table public.price_watch is
  '0226: the (city, good) pairs the record keeps BECAUSE A PLAYER ASKED (cmd.watch_price) — the city does not sell the good, so nothing else would record what it pays. asked_at / asked_seq are the last press (the sequence orders presses strictly, where two in one transaction share a now()); past price_watch_cap the stalest leave. Server-only.';
revoke all on sequence public.price_watch_seq from public, anon, authenticated;

-- Where the fold stands: hours folded up to hour_done, days up to day_done. One row.
create table public.price_rollup (
  one       boolean primary key default true check (one),
  hour_done timestamptz not null,
  day_done  date not null
);
comment on table public.price_rollup is
  '0226: the one row that says how far the fold has run — every finished hour before hour_done is in price_history_hour, every finished UTC day before day_done in price_history_day. Moved forward only by tick_price_snapshot.';

alter table public.price_history_hour set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);   -- 0095's reason: a daily prune, not 20 % of the table
alter table public.price_history_hour enable row level security;
alter table public.price_history_day  enable row level security;
alter table public.price_watch        enable row level security;
alter table public.price_rollup       enable row level security;
revoke all on table public.price_history_hour, public.price_history_day, public.price_watch, public.price_rollup from public, anon, authenticated;

-- ── 3. THE PAIRS THE RECORD KEEPS — one authority ───────────────────────────────────────────────
create function public.price_record_pairs()
returns table (port_id uuid, good_id uuid, offered boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with o as (
    select p.id as port_id, g.good_id
      from public.ports p cross join lateral public.port_offered_goods(p.id) g
     where p.kind = 'HARBOUR'
  )
  select o.port_id, o.good_id, true from o
  union all
  select w.port_id, w.good_id, false
    from public.price_watch w
   where not exists (select 1 from o where o.port_id = w.port_id and o.good_id = w.good_id)
$$;
comment on function public.price_record_pairs() is
  '0226: THE pairs the price record keeps — every (city, good) the city sells (public.port_offered_goods, 0136) and every pair a player asked for (public.price_watch) that the city does not sell. tick_price_snapshot writes exactly these; price_history_window() divides the disk budget by their count. Server-only.';
revoke all on function public.price_record_pairs() from public, anon, authenticated;

-- ── 4. THE WINDOW LAW — SUPERSEDES 0057:214 ─────────────────────────────────────────────────────
-- 0057's budget (600 MiB ÷ pairs × 201 B, floor 48) is kept whole in price_history_window_for; the pairs
-- it divides by are now the RECORDED ones, and the answer is capped at the fine tier's own span, because
-- beyond a day the hourly tier carries the line.
create or replace function public.price_history_window()
returns int
language sql
stable
set search_path = public, pg_temp
as $$
  select greatest(48, least(public.wc_int('price_history_fine_slots'),
                            public.price_history_window_for((select count(*)::int from public.price_record_pairs()))))
$$;
comment on function public.price_history_window() is
  '0226: how many fine slots price_history keeps per recorded pair — the lesser of price_history_fine_slots (24 h) and 0057''s disk budget over public.price_record_pairs(), never under 48. SUPERSEDES 0057:214, which divided the budget by every port_goods row. tick_price_snapshot prunes by it; world.watchlist and world.good_board read it.';
revoke all on function public.price_history_window() from public, anon, authenticated;

-- ── 5. THE WRITER AND THE FOLD — SUPERSEDES 0013:97 (0057:302, 0061:361, 0170:270) ──────────────
create or replace function public.tick_price_snapshot(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_slot      bigint := public.drift_slot_of(p_now);
  v_keep      int    := public.price_history_window();
  v_hour_now  timestamptz := date_trunc('hour', p_now);
  v_day_now   date   := (p_now at time zone 'UTC')::date;
  v_hour_days int    := public.wc_int('price_history_hour_days');
  v_wrote int; v_pruned int; v_hours int := 0; v_days int := 0; v_hpruned int := 0;
  m public.price_rollup%rowtype;
begin
  -- 1. RECORD (0013's idiom: ON CONFLICT DO NOTHING — the first sample in a slot is the sample). The mid as
  --    0013 wrote it; the ask and the bid through the one authority's own three leaves (0170: world.price =
  --    world.mid_price + world.price_terms + world.price_sides), the terms read once a port. The ask is
  --    recorded only where the city sells the good (0061).
  with t as materialized (
    select p.id as port_id, q.spread, q.tax, q.bid_factor
      from public.ports p cross join lateral world.price_terms(p.id) q
     where p.kind = 'HARBOUR'
  )
  insert into public.price_history (port_id, good_id, slot, at, mid, stock, ask, bid)
  select pg.port_id, pg.good_id, v_slot, p_now, x.mid, pg.stock,
         case when r.offered then s.ask end, s.bid
    from public.price_record_pairs() r
    join public.port_goods pg on pg.port_id = r.port_id and pg.good_id = r.good_id
    join t on t.port_id = pg.port_id
    cross join lateral (select world.mid_price(pg.port_id, pg.good_id, pg.stock) as mid) x
    cross join lateral world.price_sides(x.mid, t.spread, t.tax, t.bid_factor) s
  on conflict (port_id, good_id, slot) do nothing;
  get diagnostics v_wrote = row_count;

  -- 2. FOLD fine → hour, every finished hour since the mark (set-based; a retried run writes nothing)
  select * into m from public.price_rollup where one;
  if m.one is null then
    raise exception 'E_NO_ROLLUP_MARK: price_rollup has no row — the fold cannot know where it stands' using errcode = 'P0001';
  end if;
  if m.hour_done < v_hour_now then
    insert into public.price_history_hour (port_id, good_id, hour, ask_o, ask_h, ask_l, ask_c, bid_o, bid_h, bid_l, bid_c, n)
    select h.port_id, h.good_id, date_trunc('hour', h.at),
           (array_agg(h.ask order by h.slot))[1], max(h.ask), min(h.ask), (array_agg(h.ask order by h.slot desc))[1],
           (array_agg(h.bid order by h.slot))[1], max(h.bid), min(h.bid), (array_agg(h.bid order by h.slot desc))[1],
           count(*)::smallint
      from public.price_history h
     where h.at >= m.hour_done and h.at < v_hour_now and h.bid is not null
     group by h.port_id, h.good_id, date_trunc('hour', h.at)
    on conflict (port_id, good_id, hour) do nothing;
    get diagnostics v_hours = row_count;
    update public.price_rollup set hour_done = v_hour_now where one;
  end if;

  -- 3. FOLD hour → day, every finished UTC day since the mark
  if m.day_done < v_day_now then
    insert into public.price_history_day (port_id, good_id, day, ask_o, ask_h, ask_l, ask_c, bid_o, bid_h, bid_l, bid_c, n)
    select h.port_id, h.good_id, (h.hour at time zone 'UTC')::date,
           (array_agg(h.ask_o order by h.hour))[1], max(h.ask_h), min(h.ask_l), (array_agg(h.ask_c order by h.hour desc))[1],
           (array_agg(h.bid_o order by h.hour))[1], max(h.bid_h), min(h.bid_l), (array_agg(h.bid_c order by h.hour desc))[1],
           sum(h.n)::smallint
      from public.price_history_hour h
     where h.hour >= (m.day_done::timestamp at time zone 'UTC') and h.hour < (v_day_now::timestamp at time zone 'UTC')
     group by h.port_id, h.good_id, (h.hour at time zone 'UTC')::date
    on conflict (port_id, good_id, day) do nothing;
    get diagnostics v_days = row_count;
    update public.price_rollup set day_done = v_day_now where one;
  end if;

  -- 4. PRUNE: the fine window (0057's law) and rows numbered on another clock (0170); hours past the knob.
  --    Day rows are never deleted.
  delete from public.price_history where slot <= v_slot - v_keep or slot > v_slot;
  get diagnostics v_pruned = row_count;
  delete from public.price_history_hour where hour < v_hour_now - make_interval(days => v_hour_days);
  get diagnostics v_hpruned = row_count;

  return jsonb_build_object('slot', v_slot, 'wrote', v_wrote, 'pruned', v_pruned, 'keep', v_keep,
                            'hours', v_hours, 'days', v_days, 'hours_pruned', v_hpruned);
end $$;
comment on function public.tick_price_snapshot(timestamptz) is
  '0226: samples every recorded pair (public.price_record_pairs) once per drift slot — mid, stock, ask and bid — folds finished hours into price_history_hour and finished UTC days into price_history_day from the marks in price_rollup, then prunes the fine window and hours past price_history_hour_days. Idempotent by primary key everywhere. SUPERSEDES 0013:97 as re-cut by 0057, 0061 and 0170. Still byeharu-voyage:price-snapshot''s one statement.';
revoke all on function public.tick_price_snapshot(timestamptz) from public, anon, authenticated;

-- ── 6. THE BACKFILL, ONCE ───────────────────────────────────────────────────────────────────────
-- (a) the sides of the rows already kept: the recorded mid × the port's terms as they stand now, through
--     world.price_sides — the same leaf the writer and world.price compose. Stated in the header.
create temp table terms_0226 on commit drop as
select p.id as port_id, q.spread, q.tax, q.bid_factor
  from public.ports p cross join lateral world.price_terms(p.id) q
 where p.kind = 'HARBOUR';

update public.price_history h
   set (ask, bid) = (select case when public.port_offers(h.port_id, h.good_id) then s.ask end, s.bid
                       from world.price_sides(h.mid, t.spread, t.tax, t.bid_factor) s)
  from terms_0226 t
 where t.port_id = h.port_id and h.bid is null;

-- (b) the marks: every hour the fine tier still holds is unfolded; no day has finished under this file
insert into public.price_rollup (one, hour_done, day_done)
select true,
       date_trunc('hour', now()) - make_interval(secs => (public.wc_int('price_history_fine_slots') * public.wc_num('drift_slot_seconds'))::double precision),
       (now() at time zone 'UTC')::date
on conflict (one) do nothing;

-- (c) the job, once: folds the hours already kept (and records the present slot for every recorded pair —
--     a no-op where the live job already has)
create temp table backfill_0226 on commit drop as
select public.tick_price_snapshot(now()) as r;

-- ── 7. THE READ — one for every chart ───────────────────────────────────────────────────────────
create function world.price_series(p_port uuid, p_good uuid, p_span text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0226: ONE good's price at ONE city over a SPAN, both sides of every point, from the tier that span lives
-- in: 1d = the fine record (every drift slot, 24 h); 1w and 1m = the hourly open/high/low/close; 1y and all
-- = the daily. Each point: at, ask (null where the city does not sell the good), bid; the fine tier adds the
-- stock (0183's strip); the folded tiers add ask_lo/ask_hi and bid_lo/bid_hi (the hour's or day's low and
-- high; ask/bid are its close). `recording`
-- says whether the record keeps this pair at all — a client that gets false asks cmd.watch_price once.
declare
  v_now  timestamptz := now();
  v_tier text; v_step int; v_points jsonb;
begin
  if p_port is null then
    raise exception 'E_NO_SUCH_PORT: a price series needs a port' using errcode = 'P0001';
  end if;
  if p_good is null or not exists (select 1 from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good) then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;
  if p_span is null or p_span not in ('1d', '1w', '1m', '1y', 'all') then
    raise exception 'E_BAD_SPAN: a price series spans 1d, 1w, 1m, 1y or all, not %', coalesce(p_span, 'null') using errcode = 'P0001';
  end if;

  if p_span = '1d' then
    v_tier := 'fine'; v_step := public.wc_int('drift_slot_seconds');
    select jsonb_agg(jsonb_build_object('at', h.at, 'ask', h.ask, 'bid', h.bid, 'stock', h.stock) order by h.slot) into v_points
      from public.price_history h
     where h.port_id = p_port and h.good_id = p_good and h.at > v_now - interval '1 day' and h.bid is not null;
  elsif p_span in ('1w', '1m') then
    v_tier := 'hour'; v_step := 3600;
    select jsonb_agg(jsonb_build_object('at', h.hour, 'ask', h.ask_c, 'ask_lo', h.ask_l, 'ask_hi', h.ask_h,
                                        'bid', h.bid_c, 'bid_lo', h.bid_l, 'bid_hi', h.bid_h) order by h.hour) into v_points
      from public.price_history_hour h
     where h.port_id = p_port and h.good_id = p_good
       and h.hour >= v_now - case when p_span = '1w' then interval '7 days' else interval '30 days' end;
  else
    v_tier := 'day'; v_step := 86400;
    select jsonb_agg(jsonb_build_object('at', (d.day::timestamp at time zone 'UTC'), 'ask', d.ask_c, 'ask_lo', d.ask_l, 'ask_hi', d.ask_h,
                                        'bid', d.bid_c, 'bid_lo', d.bid_l, 'bid_hi', d.bid_h) order by d.day) into v_points
      from public.price_history_day d
     where d.port_id = p_port and d.good_id = p_good
       and (p_span = 'all' or d.day >= ((v_now - interval '365 days') at time zone 'UTC')::date);
  end if;

  return jsonb_build_object(
    'port', p_port, 'good', p_good, 'span', p_span, 'tier', v_tier, 'step_seconds', v_step, 'now', v_now,
    'offered', public.port_offers(p_port, p_good),
    'recording', public.port_offers(p_port, p_good)
                 or exists (select 1 from public.price_watch w where w.port_id = p_port and w.good_id = p_good),
    'points', coalesce(v_points, '[]'::jsonb));
end $$;
comment on function world.price_series(uuid, uuid, text) is
  '0226: THE chart read — one good at one city over 1d / 1w / 1m / 1y / all, both sides of every point, from the tier the span lives in. Replaces world.price_history (dropped). Reads; decides nothing.';
revoke all on function world.price_series(uuid, uuid, text) from public, anon, authenticated;
grant execute on function world.price_series(uuid, uuid, text) to authenticated;

drop function world.price_history(uuid, int);

-- ── 8. THE PRESS THAT STARTS A RECORD ───────────────────────────────────────────────────────────
create function cmd.watch_price(p_port uuid, p_good uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0226: "keep this city's price of this good" — a city that does not sell the good has no record of what it
-- pays until someone asks; this is the ask. Identity is the JWT's (E_NOT_SIGNED_IN otherwise); a pair the
-- city sells is already recorded and is not watched. Past price_watch_cap the stalest asks leave the list
-- (their day rows stay; their fine and hourly rows age out by the tiers' own rules).
declare
  v_player  uuid := public.current_player_id();
  v_cap     int  := public.wc_int('price_watch_cap');
  v_evicted int  := 0;
begin
  if v_player is null then
    raise exception 'E_NOT_SIGNED_IN: sign in to keep a price' using errcode = 'P0001';
  end if;
  if p_port is null or p_good is null
     or not exists (select 1 from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good) then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;
  if public.port_offers(p_port, p_good) then
    return jsonb_build_object('recording', true, 'watched', false, 'pairs', (select count(*) from public.price_watch), 'evicted', 0);
  end if;
  insert into public.price_watch (port_id, good_id) values (p_port, p_good)
  on conflict (port_id, good_id) do update set asked_at = now(), asked_seq = nextval('public.price_watch_seq');
  -- the stalest PRESS leaves first — by the press sequence, which is strict where asked_at is not (two presses in
  -- one transaction share a now(); CI run 40229893305 evicted the newer one on that tie)
  delete from public.price_watch w
   where (w.port_id, w.good_id) in (select x.port_id, x.good_id from public.price_watch x
                                     order by x.asked_seq desc offset v_cap);
  get diagnostics v_evicted = row_count;
  return jsonb_build_object('recording', true, 'watched', true, 'pairs', (select count(*) from public.price_watch), 'evicted', v_evicted);
end $$;
comment on function cmd.watch_price(uuid, uuid) is
  '0226: a signed-in player asks the record to keep what a city pays for a good it does not sell. Idempotent; capped by price_watch_cap, the stalest ask making room.';
revoke all on function cmd.watch_price(uuid, uuid) from public, anon, authenticated;
grant execute on function cmd.watch_price(uuid, uuid) to authenticated;

-- ── 9. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each reverses) ──────────
create temp table hunks_0226 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0226 values
('public.tick_stats(timestamptz)', 1,
$h$    from (select h.port_id, h.good_id from public.price_history h where h.slot = v_ph_slot
          union$h$,
$h$    from (select h.port_id, h.good_id from public.price_history h where h.slot = v_ph_slot
            and public.port_offers(h.port_id, h.good_id)   -- 0226: the record keeps watched pairs too; a city's goods are still the ones it sells
          union$h$),
('public.tick_stats(timestamptz)', 2,
$h$    left join public.price_history h on h.port_id = k.port_id and h.good_id = k.good_id and h.slot = v_ph_slot
$h$,
$h$    left join public.price_history h on h.port_id = k.port_id and h.good_id = k.good_id and h.slot = v_ph_slot
                                       and public.port_offers(h.port_id, h.good_id)   -- 0226: a mid only where the city sells it
$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'price_history',       'uuid, int'),
$h$,
$h$$h$),
('public.client_rpc_entry_points()', 2,
$h$      ('world',       'stats_now',             '')
    ) as t(s, f, a)$h$,
$h$      ('world',       'stats_now',             ''),
      -- 0226: a good's price at a city for years, both sides, by span — and the press that keeps a city's price for a good it does not sell.
      ('world',       'price_series',          'uuid, uuid, text'),
      ('cmd',         'watch_price',           'uuid, uuid')
    ) as t(s, f, a)$h$);

create or replace function pg_temp.recut_0226(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0226 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0226 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0226(v_def, h.old);
    if v_n <> 1 then
      raise exception '0226 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0226(fn) from defs_before_0226 order by fn;

-- ── 10. THE SELF-ASSERT (own probe rows; the probe is rolled back whole) ─────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0226-4000-8000-000000000001';
  v_d      record; v_h record; v_pp record; v_def text;
  v_port   uuid; v_pcode text;
  v_good   uuid; v_gcode text;     -- the probe pair the city does NOT sell
  v_good2  uuid;                   -- a second unsold good, for the cap
  v_ogood  uuid; v_ocode text;     -- a good the city sells
  v_h0     timestamptz;            -- the first planted hour (yesterday)
  v_r      jsonb; v_run jsonb; v_s jsonb;
  pr       record; hr record; dr record; fr record;
  v_n      int; v_pairs int;
  v_t      timestamptz; v_ms numeric; v_tick_ms numeric;
  v_sms    numeric[] := '{}';
  v_out    jsonb;
  v_bf     jsonb := (select r from backfill_0226);
  v_before record;
begin
  select * into v_before from before_0226;

  -- (a) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0226 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0226 where fn = v_d.fn order by n desc loop
      if v_h.new <> '' and pg_temp.occurs_0226(v_def, v_h.new) <> 1 then
        raise exception '0226 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      if v_h.new = '' then
        if pg_temp.occurs_0226(v_def, v_h.old) <> 0 then
          raise exception '0226 self-assert FAIL: hunk % of % was to be removed and is still there', v_h.n, v_d.fn;
        end if;
        -- a removed hunk reverses by putting it back before the row that followed it
        v_def := replace(v_def, $r$      ('world',       'player',              ''),$r$, v_h.old || $r$      ('world',       'player',              ''),$r$);
      else
        v_def := replace(v_def, v_h.new, v_h.old);
      end if;
    end loop;
    if v_def <> v_d.def then
      raise exception '0226 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0226 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;

  -- (b) THE REGISTRY AND THE WALLS: +2 −1 rows, each executable by authenticated and not by anon; the
  --     dropped read is gone; no client write grant, executable writer or caller-evaluated function appeared
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points + 1
     or not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'price_series')
     or not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'watch_price')
     or exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'price_history')
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0226 self-assert FAIL: the registry is not the old one + price_series + watch_price − price_history, every row executable by authenticated';
  end if;
  if has_function_privilege('anon', 'world.price_series(uuid, uuid, text)', 'execute')
     or has_function_privilege('anon', 'cmd.watch_price(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.price_record_pairs()', 'execute')
     or has_function_privilege('authenticated', 'public.tick_price_snapshot(timestamptz)', 'execute') then
    raise exception '0226 self-assert FAIL: a client role can execute a server-only function, or anon the new read';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'world' and p.proname = 'price_history') then
    raise exception '0226 self-assert FAIL: world.price_history still exists';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0226 self-assert FAIL: a wall moved';
  end if;

  -- (c) THE PROBE SUBJECTS — deterministic: the first harbour by code that sells something, the first good by
  --     code it does NOT sell (and a second), the first good by code it does sell
  select p.id, p.code into v_port, v_pcode from public.ports p
   where p.kind = 'HARBOUR' and exists (select 1 from public.port_offered_goods(p.id)) order by p.code limit 1;
  select g.id, g.code into v_good, v_gcode from public.goods g join public.port_goods pg on pg.port_id = v_port and pg.good_id = g.id
   where not public.port_offers(v_port, g.id) and not exists (select 1 from public.price_watch w where w.port_id = v_port and w.good_id = g.id)
   order by g.code limit 1;
  select g.id into v_good2 from public.goods g join public.port_goods pg on pg.port_id = v_port and pg.good_id = g.id
   where not public.port_offers(v_port, g.id) and g.id <> v_good and not exists (select 1 from public.price_watch w where w.port_id = v_port and w.good_id = g.id)
   order by g.code limit 1;
  select g.id, g.code into v_ogood, v_ocode from public.goods g join public.port_offered_goods(v_port) o on o.good_id = g.id order by g.code limit 1;
  if v_port is null or v_good is null or v_good2 is null or v_ogood is null then
    raise exception '0226 self-assert FAIL: no probe subjects (port %, unsold goods %/%, sold good %)', v_pcode, v_good, v_good2, v_ogood;
  end if;

  -- (d) THE BACKFILL landed — read on the SOLD PROBE PAIR's rows only, never a whole table that grows on
  --     production (and whose live job keeps writing and pruning beside this transaction): every fine row it
  --     kept before this hour has both sides, and every finished hour those rows stand in has an hour row.
  --     (A row the live job writes in the present slot, with the old body, stands at this hour and is not read.)
  if exists (select 1 from public.price_history h where h.port_id = v_port and h.good_id = v_ogood
              and h.at < date_trunc('hour', now()) and (h.bid is null or h.ask is null)) then
    raise exception '0226 self-assert FAIL: a kept fine row of %/% before this hour has no side after the backfill', v_pcode, v_ocode;
  end if;
  if exists (select 1 from (select distinct date_trunc('hour', h.at) as hr from public.price_history h
                             where h.port_id = v_port and h.good_id = v_ogood and h.at < date_trunc('hour', now())) z
              where not exists (select 1 from public.price_history_hour x where x.port_id = v_port and x.good_id = v_ogood and x.hour = z.hr)) then
    raise exception '0226 self-assert FAIL: a finished hour of %/% in the fine tier has no hour row after the backfill run', v_pcode, v_ocode;
  end if;
  if (select hour_done from public.price_rollup) <> date_trunc('hour', now()) or (select day_done from public.price_rollup) <> (now() at time zone 'UTC')::date then
    raise exception '0226 self-assert FAIL: the marks do not stand at this hour and this day after the backfill run';
  end if;

  -- (e) THE PROBE (rolled back whole)
  begin
    if exists (select 1 from public.players p where p.id = c_uid or p.auth_uid = c_uid or p.company_name = 'Casa dos Preços 0226') then
      raise exception '0226 self-assert FAIL: the probe house already exists';
    end if;
    perform public.new_house(c_uid, 'Casa dos Preços 0226', 'PRT', 'LIS');
    perform cmd.assume_identity(c_uid);

    -- before the press: the unsold pair is not recorded, and the series says so, empty
    v_s := world.price_series(v_port, v_good, '1d');
    if (v_s->>'recording')::boolean or (v_s->>'offered')::boolean or jsonb_array_length(v_s->'points') <> 0 or v_s->>'tier' <> 'fine' then
      raise exception '0226 self-assert FAIL: before the press the unsold pair reads recording=% offered=% points=%', v_s->>'recording', v_s->>'offered', jsonb_array_length(v_s->'points');
    end if;
    -- a sold pair is recorded with no press
    v_r := cmd.watch_price(v_port, v_ogood);
    if not (v_r->>'recording')::boolean or (v_r->>'watched')::boolean then
      raise exception '0226 self-assert FAIL: watching a sold pair should be recording without a watch: %', v_r;
    end if;
    -- the press
    v_r := cmd.watch_price(v_port, v_good);
    if not (v_r->>'watched')::boolean or not exists (select 1 from public.price_watch w where w.port_id = v_port and w.good_id = v_good)
       or not exists (select 1 from public.price_record_pairs() r where r.port_id = v_port and r.good_id = v_good and not r.offered) then
      raise exception '0226 self-assert FAIL: the press did not put the pair in the record set: %', v_r;
    end if;
    v_pairs := (v_r->>'pairs')::int;

    -- plant two finished hours of yesterday for the probe pair, four slots each, bids 10..17, and set the marks
    -- back so the next run folds them (the planted hours are > 24 h old, so the run prunes them AFTER folding)
    v_h0 := date_trunc('hour', now()) - interval '26 hours';
    insert into public.price_history (port_id, good_id, slot, at, mid, stock, ask, bid)
    select v_port, v_good, public.drift_slot_of(v_h0 + make_interval(mins => 15 * i)), v_h0 + make_interval(mins => 15 * i),
           10 + i, 0, null, 10 + i
      from generate_series(0, 7) i;
    update public.price_rollup set hour_done = v_h0, day_done = (v_h0 at time zone 'UTC')::date;

    -- the run, at the NEXT slot (its rows are the probe's and vanish with it), timed
    v_t := clock_timestamp();
    v_run := public.tick_price_snapshot(now() + make_interval(secs => public.wc_num('drift_slot_seconds')::double precision));
    v_tick_ms := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);

    -- (f) BOTH SIDES RECORDED, EQUAL TO THE AUTHORITY TO THE CENT: the sold pair's ask and bid, the unsold pair's
    --     bid with no ask — against world.price(port, good) in this same transaction
    select h.* into fr from public.price_history h where h.port_id = v_port and h.good_id = v_ogood and h.slot = (v_run->>'slot')::bigint;
    select * into pr from world.price(v_port, v_ogood);
    if fr.port_id is null or fr.ask is distinct from pr.ask or fr.bid is distinct from pr.bid or fr.mid is distinct from pr.mid then
      raise exception '0226 self-assert FAIL: the sold pair %/% recorded ask % bid % mid %, world.price says ask % bid % mid %',
        v_pcode, v_ocode, fr.ask, fr.bid, fr.mid, pr.ask, pr.bid, pr.mid;
    end if;
    select h.* into fr from public.price_history h where h.port_id = v_port and h.good_id = v_good and h.slot = (v_run->>'slot')::bigint;
    select * into pr from world.price(v_port, v_good);
    if fr.port_id is null or fr.ask is not null or fr.bid is distinct from pr.bid then
      raise exception '0226 self-assert FAIL: the unsold pair %/% recorded ask % bid %, world.price says bid % (ask must be null)',
        v_pcode, v_gcode, fr.ask, fr.bid, pr.bid;
    end if;

    -- (g) THE FOLD: two hour rows with the planted open/high/low/close and n = 4; one day row over both
    select count(*) into v_n from public.price_history_hour h where h.port_id = v_port and h.good_id = v_good and h.hour in (v_h0, v_h0 + interval '1 hour');
    if v_n <> 2 then
      raise exception '0226 self-assert FAIL: % hour row(s) at the planted hours for the probe pair, expected 2 (run: %)', v_n, v_run;
    end if;
    select h.* into hr from public.price_history_hour h where h.port_id = v_port and h.good_id = v_good and h.hour = v_h0;
    if hr.bid_o <> 10 or hr.bid_h <> 13 or hr.bid_l <> 10 or hr.bid_c <> 13 or hr.n <> 4 or hr.ask_o is not null or hr.ask_c is not null then
      raise exception '0226 self-assert FAIL: hour 1 folded o % h % l % c % n % ask_o %', hr.bid_o, hr.bid_h, hr.bid_l, hr.bid_c, hr.n, hr.ask_o;
    end if;
    select h.* into hr from public.price_history_hour h where h.port_id = v_port and h.good_id = v_good and h.hour = v_h0 + interval '1 hour';
    if hr.bid_o <> 14 or hr.bid_h <> 17 or hr.bid_l <> 14 or hr.bid_c <> 17 or hr.n <> 4 then
      raise exception '0226 self-assert FAIL: hour 2 folded o % h % l % c % n %', hr.bid_o, hr.bid_h, hr.bid_l, hr.bid_c, hr.n;
    end if;
    select d.* into dr from public.price_history_day d where d.port_id = v_port and d.good_id = v_good and d.day = (v_h0 at time zone 'UTC')::date;
    if dr.port_id is null or dr.bid_o <> 10 or dr.bid_h <> 17 or dr.bid_l <> 10 or dr.bid_c <> 17 or dr.n <> 8 then
      raise exception '0226 self-assert FAIL: the day folded day % o % h % l % c % n %', dr.day, dr.bid_o, dr.bid_h, dr.bid_l, dr.bid_c, dr.n;
    end if;
    if (select count(*) from public.price_history h where h.port_id = v_port and h.good_id = v_good and h.at < now() - interval '1 day') <> 0 then
      raise exception '0226 self-assert FAIL: the planted fine rows outlived the fine window';
    end if;
    if (select hour_done from public.price_rollup) <> date_trunc('hour', now() + make_interval(secs => public.wc_num('drift_slot_seconds')::double precision)) then
      raise exception '0226 self-assert FAIL: hour_done did not move forward to the run''s hour';
    end if;

    -- (h) THE SERIES, EACH SPAN, from the tier it lives in — six timed calls in ONE session (0205's lesson)
    for i in 1..6 loop
      v_t := clock_timestamp();
      v_s := world.price_series(v_port, v_good, (array['1d', '1w', '1m', '1y', 'all', '1w'])[i]);
      v_sms := v_sms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
      -- the +1-slot row is the LAST fine point; the planted hours and day are the EARLIEST of their tiers (a run
      -- near midnight UTC may fold this hour and today behind them, so nothing here pins a count)
      if i = 1 and (jsonb_array_length(v_s->'points') < 1 or v_s->>'tier' <> 'fine' or (v_s->'points'->-1->>'ask') is not null
                    or (v_s->'points'->-1->>'bid')::numeric <> pr.bid or not (v_s->>'recording')::boolean) then
        raise exception '0226 self-assert FAIL: 1d served % (% point(s)): %', v_s->>'tier', jsonb_array_length(v_s->'points'), v_s->'points';
      end if;
      if i in (2, 3) and (jsonb_array_length(v_s->'points') < 2 or v_s->>'tier' <> 'hour' or (v_s->>'step_seconds')::int <> 3600
                          or (v_s->'points'->0->>'bid')::numeric <> 13 or (v_s->'points'->0->>'bid_lo')::numeric <> 10 or (v_s->'points'->0->>'bid_hi')::numeric <> 13
                          or (v_s->'points'->1->>'bid')::numeric <> 17 or (v_s->'points'->1->>'bid_lo')::numeric <> 14 or (v_s->'points'->1->>'bid_hi')::numeric <> 17) then
        raise exception '0226 self-assert FAIL: % served % (% point(s)): %', (array['1d', '1w', '1m', '1y', 'all', '1w'])[i], v_s->>'tier', jsonb_array_length(v_s->'points'), v_s->'points';
      end if;
      if i in (4, 5) and (jsonb_array_length(v_s->'points') < 1 or v_s->>'tier' <> 'day' or (v_s->>'step_seconds')::int <> 86400
                          or (v_s->'points'->0->>'bid')::numeric <> 17 or (v_s->'points'->0->>'bid_lo')::numeric <> 10 or (v_s->'points'->0->>'bid_hi')::numeric <> 17) then
        raise exception '0226 self-assert FAIL: % served % (% point(s)): %', (array['1d', '1w', '1m', '1y', 'all', '1w'])[i], v_s->>'tier', jsonb_array_length(v_s->'points'), v_s->'points';
      end if;
    end loop;
    -- the sold pair's day series carries an ask side
    v_s := world.price_series(v_port, v_ogood, '1d');
    if jsonb_array_length(v_s->'points') < 1 or (v_s->'points'->-1->>'ask') is null or not (v_s->>'offered')::boolean then
      raise exception '0226 self-assert FAIL: the sold pair''s 1d series has no ask on its last point';
    end if;
    -- refusals
    begin
      perform world.price_series(v_port, v_good, '2w');
      raise exception '0226 self-assert FAIL: a bad span was not refused';
    exception when others then
      if sqlerrm not like 'E_BAD_SPAN%' then raise; end if;
    end;

    -- (i) THE CAP: cap 1, a second press evicts the stalest
    update public.world_config set value = to_jsonb(1) where key = 'price_watch_cap';
    v_r := cmd.watch_price(v_port, v_good2);
    if (v_r->>'evicted')::int <> 1
       or (select count(*) from public.price_watch) <> 1
       or exists (select 1 from public.price_watch w where w.port_id = v_port and w.good_id = v_good) then
      raise exception '0226 self-assert FAIL: with cap 1 the list holds % pair(s) and the first press % survived: %', (select count(*) from public.price_watch),
        case when exists (select 1 from public.price_watch w where w.port_id = v_port and w.good_id = v_good) then 'STILL' else 'no longer' end, v_r;
    end if;
    -- and a watch that stopped keeps its day row
    if not exists (select 1 from public.price_history_day d where d.port_id = v_port and d.good_id = v_good) then
      raise exception '0226 self-assert FAIL: a day row was lost when its watch left';
    end if;
    -- an identity with no house cannot press
    perform cmd.assume_identity('00000000-0226-4000-8000-000000000002');
    begin
      perform cmd.watch_price(v_port, v_good);
      raise exception '0226 self-assert FAIL: a press with no identity was not refused';
    exception when others then
      if sqlerrm not like 'E_NOT_SIGNED_IN%' then raise; end if;
    end;

    raise exception using errcode = 'ZX226', message = jsonb_build_object(
      'tick_ms', v_tick_ms, 'series_ms', to_jsonb(v_sms), 'run', v_run, 'port', v_pcode, 'good', v_gcode, 'sold', v_ocode,
      'pairs', v_pairs)::text;
  exception when sqlstate 'ZX226' then
    v_out := sqlerrm::jsonb;
  end;

  -- (j) nothing of the probe survives
  if exists (select 1 from public.players p where p.auth_uid = c_uid)
     or exists (select 1 from public.price_watch w where w.port_id = v_port and w.good_id in (v_good, v_good2))
     or exists (select 1 from public.price_history_hour h where h.port_id = v_port and h.good_id = v_good)
     or exists (select 1 from public.price_history_day d where d.port_id = v_port and d.good_id = v_good)
     or public.wc_int('price_watch_cap') <> 2000 then
    raise exception '0226 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0226 self-assert ok: A PRICE IS KEPT FOR YEARS, BOTH WAYS. Backfill: the job run once (%). Probe at % — % (unsold, pressed → recorded; bid = world.price''s, no ask) and % (sold; ask and bid = world.price''s to the cent): two planted hours folded to o/h/l/c 10-13-10-13 and 14-17-14-17 (n 4), the day to 10-17-10-17 (n 8), the planted fine rows pruned after; 1d/1w/1m/1y/all served from fine/hour/hour/day/day; cap 1 evicted the stalest and kept its day row; no identity refused. Timings this session: the run % ms (wrote % rows; % watched pair(s)), price_series × 6 = % ms. Registry +2 −1; walls 0; world.price_history dropped.',
    v_bf, v_out->>'port', v_out->>'good', v_out->>'sold', v_out->>'tick_ms', v_out->'run'->>'wrote', v_out->>'pairs', v_out->'series_ms';
end $$;
