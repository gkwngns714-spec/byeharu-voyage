-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0413 - A DAY LASTS AN HOUR  (the whole world runs five times slower: time_compression 960 -> 192; a day of the game's clock is 3,600 real seconds,
--        was 720; the market's day, its drift slot, its want period and the population's step are five times as long, counted on without a break)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-14: "change the game day - 1 hour." He had been told a game day is 12 real minutes and that a longer day means fewer events per
-- real minute on a database that is too small. Decided by default (the coordinator, the same day): the day he sees goes from 12 minutes to 60, a
-- factor of 5, and EVERYTHING KEEPS ITS PROPORTION: the ships and the market slow together, so that per voyage-day the market regenerates and
-- drifts exactly as much as before (slowing only the ships would let a price walk five times as far between a merchant's buy and her arrival).
-- docs/dev-log/2026-11-14-day-hour.md has the table of what scales and what stays.
--
-- WHAT A "DAY" WAS (four numbers, found by reading; none of them was derived from another on the server):
--   * the day of the top bar's clock and of the map's Sun: 720 real seconds. A CLIENT constant only (src/lib/format/time.ts GAME_CLOCK_RATE =
--     TIME_COMPRESSION / 8): eight voyage-days. The server had no such number.
--   * a voyage-day (sailing, stores, wages, the day's weather and raid roll, every "N days" on a screen): 86,400 / time_compression = 90 real seconds.
--   * the market's day (world.game_day: stock regeneration, the daily caps, a request's deadline): game_day_seconds, 2,880 in this chain and 60 on
--     prod by the owner's hand since 2026-10-30. The drift slot (drift_slot_seconds: 900 here, 60 on prod) and the want period beside it.
--   * the date's day: 2,880 s, a client constant.
--
-- WHAT THIS FILE DOES:
--   1. ONE RATE, WITH THE RATIO STATED. world_config.time_compression stays the one rate (every sailing body already reads it; it is already
--      served). clock_voyage_days (new, 8) states what the client only assumed: a day of the clock and the Sun is that many voyage-days. So the day's
--      length is 86,400 x clock_voyage_days / time_compression = 3,600 real seconds, and nothing holds a second copy: world.snapshot() serves
--      clock_voyage_days and clock_anchor beside time_compression, and the client reads them (its 960 and its 8 were mirrors).
--   2. time_compression 960 -> 192. A voyage-day is 450 real seconds. Knots, miles, stores, wages and rolls per voyage-day are as they were.
--   3. THE ONE DOOR TO MOVE THE RATE, public.clock_set(compression, at). By old / new (5 here) it moves, in one statement group:
--      * the knob;
--      * EVERY VOYAGE AT SEA, RE-TIMED ABOUT THE INSTANT: departed_at and eta both by t' = at + (t - at) x old / new. Her miles run, her days settled
--        and her next boundary are the same at the instant; what is left of her passage takes old / new times as long. A battle's hold running
--        across the instant keeps its end and is re-timed the same way (such a battle runs to its full length);
--      * THE MARKET'S FOUR COUNTERS, COUNTED ON WITHOUT A BREAK: game_day_seconds, drift_slot_seconds, want_period_seconds and population_slot_seconds
--        (new: the population's step, 600 s until now as a literal) are multiplied by old / new, and each counter is anchored
--        (world_config.market_clock_anchor): its count at the instant is what it was, the period it is in is stretched about the instant like a
--        voyage (the part of it already run stays run; what is left takes old / new times as long), and every count before the instant reads as
--        it did. So no day is regenerated twice or five at once, none is skipped, no slot is drifted twice, no open request moves its place in the
--        count: it ends at the same day number, which now comes old / new times as far off in real time and exactly as far off in voyage-days;
--      * drift_spread_runs (0409: a harbour is drifted once in so many one-minute runs) by old / new, so a harbour is still stepped once in the same
--        number of slots and the drift job writes a fifth of the rows a real minute;
--      * THE ECONOMY'S RATES PER REAL TIME (not a person's pacing), so that each is the same per voyage-day: navy_upkeep_day, works_coupon_day,
--        pirate_spend_day_pct and population_tax_per_1000 are divided by old / new; glut_half_life_hours and invested_half_life_hours multiplied;
--      * the clock's anchor (the top bar's date and hour do not jump).
--      The rollback is the same door with 960: everything above moves back the same way, continuous too.
--   4. ONE AUTHORITY FOR EVERY COUNTER: public.clock_count(kind, at) and its inverse public.clock_start(kind, count). world.game_day,
--      public.drift_slot_of, public.want_period and public.next_drift_change_at are those two (their one line each); public.tick_market_drift and
--      public.population_tick read the slot through them instead of dividing the epoch themselves; world.contracts and public.city_coupons turn a
--      day number into an instant through public.clock_start instead of multiplying by the knob (the only two places that did).
--   5. THE CLOCK AND THE DATE DO NOT JUMP, and are one clock from the switch on (clock_anchor): the date turns when the hour passes midnight; a
--      month is 30 of those days, 30 real hours (was 24). Decided by default.
--
-- STAYS AS IT IS (real time, a person's pacing or the world's turns): port_prep_seconds 60, battle_seconds, attack and gift cooldowns, the gift's
--   week, the back-off's minutes, navy and pirate lie-up hours, skill training per hour, the daily caps (real UTC days), the loot cap, regard's
--   half-life, contract_npc_after_hours, every cron cadence. A rest or repair already running keeps its stored end.
-- KNOWN SEAMS (the dev-log has each): the first dividend after the switch is paid at the new rate for its whole real day (a fifth of a day's coupon,
--   once, not five); the Stats' "an hour ago" and "a day ago" lookups count slots, and for the first days read across the seam at the new slot length.
--
-- LOCKS: CREATE FUNCTION x3; CREATE OR REPLACE x9 by one hunk each; knobs; one UPDATE of every SAILING voyage (and the knob's 0242 trigger re-keeps
--   due_at once): row locks only, with the clock jobs unwound by the deploy. The probe does the same once more and is rolled back.
-- TIME: about four writes per voyage at sea in all (about 1,300 at sea on prod: under 10 s expected). No market row is written.
--   BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above 40 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/day-hour/rollback-0413.sql, a draft: select public.clock_set(960).
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then two probe voyages
--   (one plain, one held by a battle) and the four counters, moved in a rolled-back sub-transaction; only the probe's own rows are read.
-- VERSION: 0413 = 0412 + 1 (0412 sets autovacuum per table and touches no function).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $g$
begin
  if exists (select 1 from public.world_config where key in ('clock_voyage_days', 'clock_anchor', 'market_clock_anchor', 'population_slot_seconds'))
     or to_regprocedure('public.clock_set(integer,timestamp with time zone)') is not null then
    raise exception '0413 refuses: it has been applied once';
  end if;
  if public.wc_num('time_compression') <> 960 then
    raise exception '0413 refuses: time_compression is %, not the 960 this file was written against (a day of the clock is not 720 s here)', public.wc_num('time_compression');
  end if;
  if to_regprocedure('public.drift_ports_due(timestamp with time zone)') is null or not exists (select 1 from public.world_config where key = 'drift_spread_runs') then
    raise exception '0413 refuses: the drift job of 0409 is not in this world';
  end if;
end $g$;

insert into public.world_config (key, value, description) values
  ('clock_voyage_days', to_jsonb(8),
   '0413: a day of the game''s clock (the top bar''s hour and date, the Sun on the map) is this many voyage-days. THE DAY''S LENGTH IS DERIVED, never typed: 86,400 x clock_voyage_days / time_compression real seconds (3,600 at 192; 720 at the 960 it replaced). Served by world.snapshot(). It was a client constant (the owner, 2026-10-15 and 2026-10-17: the clock and the light slowed to an eighth of the ships).'),
  ('clock_anchor', '{}'::jsonb,
   '0413: where the game''s clock stood when its rate last moved: {at: the instant, day: days since 1 January 1500 with the hour as its fraction, was, is: the rates}. Written only by public.clock_set. From it the clock runs a day per 86,400 x clock_voyage_days / time_compression seconds, so a change of rate never moves the date or the hour. Empty: the clock as it was before 0413. Served by world.snapshot().'),
  ('market_clock_anchor', '{}'::jsonb,
   '0413: where each of the market''s counters stood when the clock''s rate last moved, by kind (game_day, drift_slot, want_period, population_slot): {at: the instant in epoch seconds, count: the counter then, start: when that period had begun, epoch: its start as re-timed about the instant, was: the length before}. Written only by public.clock_set; read only by public.clock_count and public.clock_start. A kind not in it: the counter is floor(epoch / its length), as before 0413.'),
  ('population_slot_seconds', to_jsonb(600),
   '0413: the length of the population''s step (public.population_tick steps a harbour once a slot; the job runs every 10 minutes and steps nothing inside a slot already stepped). It was the literal 600. Moved with the clock''s rate by public.clock_set.');

create function public.clock_count(p_kind text, p_at timestamptz)
returns bigint
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $f$
  -- 0413: THE ONE COUNTER of the market's periods: which game day, drift slot, want period or population slot an instant falls in. floor(epoch /
  -- the kind's length) until the clock's rate has moved; from then on counted from the anchor public.clock_set wrote (the count at that instant,
  -- on at the new length from the period's re-timed start), and an instant before it reads on the length there was. A kind it does not know: null.
  select case when a.j is null then floor(extract(epoch from p_at) / l.len)::bigint
              when extract(epoch from p_at) >= (a.j ->> 'at')::numeric
                then (a.j ->> 'count')::bigint + floor((extract(epoch from p_at) - (a.j ->> 'epoch')::numeric) / l.len)::bigint
              else (a.j ->> 'count')::bigint + floor((extract(epoch from p_at) - (a.j ->> 'start')::numeric) / (a.j ->> 'was')::numeric)::bigint end
    from (select public.wc_num(case p_kind when 'game_day' then 'game_day_seconds' when 'drift_slot' then 'drift_slot_seconds'
                                            when 'want_period' then 'want_period_seconds' when 'population_slot' then 'population_slot_seconds' end) as len) l
   cross join (select (select wc.value -> p_kind from public.world_config wc where wc.key = 'market_clock_anchor') as j) a
$f$;
revoke all on function public.clock_count(text, timestamptz) from public, anon, authenticated;

create function public.clock_start(p_kind text, p_count bigint)
returns timestamptz
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $f$
  -- 0413: THE INSTANT A PERIOD BEGINS, the inverse of public.clock_count and the one place a count becomes a time: count x length until the
  -- clock's rate has moved; after it, from the anchor (a period after the anchored one at the new length, the anchored one at its own true start,
  -- one before it at the length there was).
  select to_timestamp((case when a.j is null then p_count * l.len
                            when p_count > (a.j ->> 'count')::bigint then (a.j ->> 'epoch')::numeric + (p_count - (a.j ->> 'count')::bigint) * l.len
                            else (a.j ->> 'start')::numeric + (p_count - (a.j ->> 'count')::bigint) * (a.j ->> 'was')::numeric end)::double precision)
    from (select public.wc_num(case p_kind when 'game_day' then 'game_day_seconds' when 'drift_slot' then 'drift_slot_seconds'
                                            when 'want_period' then 'want_period_seconds' when 'population_slot' then 'population_slot_seconds' end) as len) l
   cross join (select (select wc.value -> p_kind from public.world_config wc where wc.key = 'market_clock_anchor') as j) a
$f$;
revoke all on function public.clock_start(text, bigint) from public, anon, authenticated;

create function public.clock_set(p_compression integer, p_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $f$
-- 0413: THE ONE DOOR TO MOVE THE CLOCK'S RATE (world_config.time_compression). Owner only. By f = old / new it moves together, so that nothing jumps
-- and everything keeps its proportion to a voyage-day:
--   the knob; every voyage at sea, re-timed about p_at (t' = p_at + (t - p_at) x f on departed_at and eta: a voyage is a pure function of the two
--   and the rate, so her miles, her settled days and her next boundary are the same at p_at and the rest of her passage runs at the new rate);
--   the market's four counters (their lengths x f, each anchored: the count at p_at is what it was, the period it is in re-timed about p_at the
--   same way); the drift job's spread (x f); the economy's rates per real time (/ f) and its half-lives (x f); and the clock's anchor.
-- A hold (a battle, 0323) running across p_at keeps its end; its start and its hours are re-timed the same way, so she stands where she stood.
-- The same rate: nothing is written. Returns what it did.
declare
  c_len  constant text[] := array['game_day', 'game_day_seconds', 'drift_slot', 'drift_slot_seconds', 'want_period', 'want_period_seconds',
                                  'population_slot', 'population_slot_seconds'];
  c_long constant text[] := array['glut_half_life_hours', 'invested_half_life_hours'];                                   -- x f: a time
  c_rate constant text[] := array['navy_upkeep_day', 'works_coupon_day', 'pirate_spend_day_pct', 'population_tax_per_1000'];   -- / f: an amount per real time
  v_old    numeric := public.wc_num('time_compression');
  v_cvd    numeric := public.wc_num('clock_voyage_days');
  v_anchor jsonb   := (select value from public.world_config where key = 'clock_anchor');
  v_at     numeric := extract(epoch from p_at);
  v_f      numeric;
  v_day    numeric;
  v_x      numeric;
  v_n      int;
  v_held   uuid[];
  v_id     uuid;
  v_m      jsonb := '{}'::jsonb;
  v_cnt    bigint;
  v_start  numeric;
  v_virt   numeric;
  v_len    numeric;
  v_mkt    jsonb := (select value from public.world_config where key = 'market_clock_anchor');
  i        int;
begin
  if p_compression is null or p_compression < 1 or p_at is null then
    raise exception 'E_BAD_CLOCK: a rate of % at %', p_compression, p_at using errcode = 'P0001';
  end if;
  if p_compression = v_old then
    return jsonb_build_object('moved', false, 'time_compression', v_old);
  end if;
  v_f := v_old / p_compression;

  -- the clock's reading at p_at, at the old rate: from the anchor, or (none yet) as the client drew it before 0413: the date a day per 2,880 s
  -- from 2026-08-18 UTC, the hour hand the second of the UTC day at old / clock_voyage_days times real time.
  if v_anchor ? 'at' then
    v_day := (v_anchor->>'day')::numeric + extract(epoch from p_at - (v_anchor->>'at')::timestamptz) * v_old / (86400 * v_cvd);
  else
    v_x   := mod(v_at, 86400) * v_old / v_cvd / 86400;
    v_day := floor(extract(epoch from p_at - '2026-08-18 00:00:00+00'::timestamptz) / 2880) + (v_x - floor(v_x));
  end if;

  -- the market's counters as they stand at p_at, read BEFORE anything moves: the count, when its period began, its length. The period is re-timed
  -- about p_at as a voyage is: epoch = p_at - (p_at - start) x f, so the part of it already run stays run and what is left takes f times as long.
  for i in 1 .. array_length(c_len, 1) / 2 loop
    v_cnt   := public.clock_count(c_len[2 * i - 1], p_at);
    v_start := extract(epoch from public.clock_start(c_len[2 * i - 1], v_cnt));
    v_len   := public.wc_num(c_len[2 * i]);
    -- the period the last move anchored is counted from that move's re-timed start, so a second move inside it re-times it from there
    v_virt  := case when (v_mkt -> c_len[2 * i - 1] ->> 'count')::bigint = v_cnt then (v_mkt -> c_len[2 * i - 1] ->> 'epoch')::numeric else v_start end;
    v_m := v_m || jsonb_build_object(c_len[2 * i - 1],
             jsonb_build_object('at', v_at, 'count', v_cnt, 'start', v_start, 'epoch', v_at - (v_at - v_virt) * v_f, 'was', v_len, 'is', trim_scale(v_len * v_f)));
  end loop;

  update public.world_config
     set value = to_jsonb(p_compression), updated_at = now(),
         description = 'DESIGN D.1, THE CLOCK''S ONE RATE: voyage-time per real time. A voyage-day is 86,400 / this real seconds (450 at 192); a day of the game''s clock is clock_voyage_days of those (3,600 s at 192). 0413 (the owner, 2026-11-14: "change the game day - 1 hour"): 960 -> 192. Move it ONLY through public.clock_set, which re-times the voyages at sea, the market''s counters, the economy''s rates per real time and the clock''s anchor with it. Was ' || v_old || ' until ' || p_at || '.'
   where key = 'time_compression';
  update public.world_config
     set value = jsonb_build_object('at', p_at, 'day', round(v_day, 8), 'was', v_old, 'is', p_compression), updated_at = now()
   where key = 'clock_anchor';
  update public.world_config set value = v_m, updated_at = now() where key = 'market_clock_anchor';
  update public.world_config wc
     set value = to_jsonb(trim_scale((wc.value #>> '{}')::numeric * v_f)), updated_at = now()
   where wc.key = any (c_long) or wc.key in (select c_len[2 * g] from generate_series(1, array_length(c_len, 1) / 2) g);
  update public.world_config wc
     set value = to_jsonb(greatest(1, round((wc.value #>> '{}')::numeric * v_f))::int), updated_at = now()
   where wc.key = 'drift_spread_runs';
  update public.world_config wc
     set value = to_jsonb(trim_scale((wc.value #>> '{}')::numeric / v_f)), updated_at = now()
   where wc.key = any (c_rate);

  with h as (
    update public.voyage_events ve
       set payload = ve.payload || jsonb_build_object(
             'held_from', p_at - ((p_at - (ve.payload->>'held_from')::timestamptz) * v_f::double precision),
             'delay_hours', trim_scale(round((extract(epoch from (ve.payload->>'held_until')::timestamptz - p_at)
                                              + extract(epoch from p_at - (ve.payload->>'held_from')::timestamptz) * v_f) * p_compression / 3600, 3)),   -- three places, as voyages.delay_hours keeps them: a hold's free hours must not differ from the row's delay
             'retimed_from', ve.payload->'held_from')
      from public.voyages v
     where v.id = ve.voyage_id and v.status = 'SAILING' and ve.day_index >= voyage.hold_floor()
       and (ve.payload->>'held_from')::timestamptz < p_at and (ve.payload->>'held_until')::timestamptz > p_at
    returning ve.voyage_id)
  select array_agg(distinct h.voyage_id) into v_held from h;

  update public.voyages v
     set departed_at = p_at - ((p_at - v.departed_at) * v_f::double precision),
         eta         = p_at + ((v.eta - p_at) * v_f::double precision)
   where v.status = 'SAILING';
  get diagnostics v_n = row_count;

  if v_held is not null then
    foreach v_id in array v_held loop
      perform voyage.recompute_eta(v_id);   -- her hold's hours moved: the eta's one authority
    end loop;
  end if;

  return jsonb_build_object('moved', true, 'was', v_old, 'time_compression', p_compression, 'at', p_at, 'voyages', v_n,
                            'holds', coalesce(array_length(v_held, 1), 0), 'clock_day', round(v_day, 8),
                            'clock_day_seconds', round(86400 * v_cvd / p_compression, 3), 'market', v_m);
end
$f$;
revoke all on function public.clock_set(integer, timestamptz) from public, anon, authenticated;

do $m$
declare
  c_cut constant text[] := array['world.snapshot()', 'world.game_day(timestamp with time zone)', 'public.drift_slot_of(timestamp with time zone)',
                                 'public.want_period(timestamp with time zone)', 'public.next_drift_change_at(timestamp with time zone)',
                                 'public.tick_market_drift(timestamp with time zone,uuid)', 'public.population_tick(timestamp with time zone)',
                                 'world.contracts(uuid)', 'public.city_coupons(uuid,timestamp with time zone)'];
  c_new constant text[] := array['public.clock_set(integer,timestamp with time zone)', 'public.clock_count(text,timestamp with time zone)',
                                 'public.clock_start(text,bigint)'];
  c_kinds constant text[] := array['game_day', 'drift_slot', 'want_period', 'population_slot'];
  c_uid_a constant uuid := '00000000-0000-4000-8000-00000000413a';
  c_uid_b constant uuid := '00000000-0000-4000-8000-00000000413b';
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_old       numeric := public.wc_num('time_compression');
  v_new       int := (public.wc_num('time_compression') / 5)::int;
  v_lis       uuid;
  v_set       uuid;
  v_course    jsonb;
  v_segs      jsonb;
  v_ha        uuid;
  v_hb        uuid;
  v_fa        uuid;
  v_fb        uuid;
  v_va        uuid;
  v_vb        uuid;
  v_dep       timestamptz;
  v_at        timestamptz;
  v_a         timestamptz;
  v_b         timestamptz;
  v_eta_a     timestamptz;
  v_eta_b     timestamptz;
  v_mid       timestamptz;
  v_post      timestamptz;
  v_pa_at     numeric;
  v_pa_mid    numeric;
  v_pb_at     numeric;
  v_pb_post   numeric;
  v_da        int;
  v_r         jsonb;
  v_e         timestamptz;
  v_note      text := '';
  v_k         text;
  v_c0        jsonb := '{}'::jsonb;
  v_keys      jsonb;
  v_mk        text := '';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0413 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0413
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid);

  -- ── 2. THE HUNKS: the snapshot serves the clock; every counter of the market is the one authority's ──
  create temp table hunk_0413 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0413 values
  (1, c_cut[1],
$h$        'time_compression',  public.wc_int('time_compression'),
$h$,
$h$        'time_compression',  public.wc_int('time_compression'),
        -- 0413: THE CLOCK'S DAY, beside the rate it is derived from: 86,400 x clock_voyage_days / time_compression real seconds; and where the
        -- 0413: clock stood when the rate last moved (public.clock_set), so the date and the hour never jump.
        'clock_voyage_days', public.wc_num('clock_voyage_days'),
        'clock_anchor',      (select wc.value from public.world_config wc where wc.key = 'clock_anchor'),
$h$),
  (2, c_cut[2],
$h$ select floor(extract(epoch from p_at) / public.wc_num('game_day_seconds'))::int $h$,
$h$ select public.clock_count('game_day', p_at)::int   /* 0413: the one counter (public.clock_count), counted on across a change of the clock's rate */ $h$),
  (3, c_cut[3],
$h$  select floor(extract(epoch from p_at) / public.wc_num('drift_slot_seconds'))::bigint;
$h$,
$h$  select public.clock_count('drift_slot', p_at);   -- 0413: the one counter, counted on across a change of the clock's rate
$h$),
  (4, c_cut[4],
$h$  select floor(extract(epoch from p_at) / public.wc_num('want_period_seconds'))::bigint
$h$,
$h$  select public.clock_count('want_period', p_at)   -- 0413: the one counter, counted on across a change of the clock's rate
$h$),
  (5, c_cut[5],
$h$  select to_timestamp(((public.drift_slot_of(p_at) + 1) * public.wc_num('drift_slot_seconds'))::double precision);
$h$,
$h$  select public.clock_start('drift_slot', public.drift_slot_of(p_at) + 1);   -- 0413: the instant the next slot begins, by the counter's own inverse
$h$),
  (6, c_cut[6],
$h$  v_slot   bigint := floor(extract(epoch from p_now) / public.wc_num('drift_slot_seconds'))::bigint;
$h$,
$h$  v_slot   bigint := public.drift_slot_of(p_now);   -- 0413: the slot's one authority (it was this function's own division of the epoch)
$h$),
  (7, c_cut[7],
$h$  v_slot  bigint := floor(extract(epoch from p_now) / 600)::bigint;
$h$,
$h$  v_slot  bigint := public.clock_count('population_slot', p_now);   -- 0413: population_slot_seconds (it was the literal 600), counted on across a change of the clock's rate
$h$),
  (8, c_cut[8],
$h$        'expires_at', to_timestamp(c.expires_day * public.wc_num('game_day_seconds'))) order by c.expires_day, g.code), '[]'::jsonb)
$h$,
$h$        'expires_at', public.clock_start('game_day', c.expires_day)) order by c.expires_day, g.code), '[]'::jsonb)   -- 0413: by the counter's own inverse
$h$),
  (9, c_cut[9],
$h$greatest(0, (v_today - s.accrued_day) * v_gds / 86400))
$h$,
$h$greatest(0, extract(epoch from public.clock_start('game_day', v_today) - public.clock_start('game_day', s.accrued_day)) / 86400))   -- 0413: the real days between the two day numbers, by the counter's own inverse (it was their difference x the knob)
$h$);
  for h in select * from hunk_0413 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0413 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0413 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0413 p where p.fn = h.fn) then
      raise exception '0413 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0413 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0413 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0413 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0413 self-assert FAIL: another function moved';
  end if;
  if exists (select 1 from unnest(c_new) f, unnest(array['anon', 'authenticated']) r where has_function_privilege(r, f, 'execute')) then
    raise exception '0413 self-assert FAIL: a player can call the clock''s door or its counters';
  end if;
  -- with no anchor every counter is what it was: floor(epoch / its length), and its inverse the count x the length
  if world.game_day(now()) <> floor(extract(epoch from now()) / public.wc_num('game_day_seconds'))::int
     or public.drift_slot_of(now()) <> floor(extract(epoch from now()) / public.wc_num('drift_slot_seconds'))::bigint
     or public.want_period(now()) <> floor(extract(epoch from now()) / public.wc_num('want_period_seconds'))::bigint
     or public.clock_count('population_slot', now()) <> floor(extract(epoch from now()) / 600)::bigint
     or public.next_drift_change_at(now()) <> to_timestamp(((public.drift_slot_of(now()) + 1) * public.wc_num('drift_slot_seconds'))::double precision)
     or public.clock_start('game_day', world.game_day(now()) + 3) <> to_timestamp(((world.game_day(now()) + 3) * public.wc_num('game_day_seconds'))::double precision) then
    raise exception '0413 self-assert FAIL: before the clock moves a counter is not floor(epoch / its length)';
  end if;

  -- ── 3. THE PROBE: two houses put to sea Lisbon to Setubal (0100's pair), one of them held by a battle, the clock moved while they sail, all rolled
  --      back. Only these two voyages and the knobs are read. The instants are passed in, so nothing waits.
  begin
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_set from public.ports where code = 'SET';
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_course from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_set;
    if v_course is null then
      raise exception '0413 self-assert FAIL: Lisbon or Setubal has no roadstead to sail between';
    end if;
    v_segs := voyage.segments_from_course(v_course);
    v_dep  := now();
    v_ha := public.new_house(c_uid_a, 'Casa Hora', 'PRT');
    v_hb := public.new_house(c_uid_b, 'Casa Relogio', 'PRT');
    select f.id into v_fa from public.fleets f where f.player_id = v_ha limit 1;
    select f.id into v_fb from public.fleets f where f.player_id = v_hb limit 1;
    v_va := voyage.depart(v_fa, v_segs, v_lis, v_set, v_dep);
    v_vb := voyage.depart(v_fb, v_segs, v_lis, v_set, v_dep);
    select eta into v_eta_a from public.voyages where id = v_va;
    -- B is held from a fifth of her passage for four tenths of its length; the clock moves a quarter of the way into the hold
    v_a  := v_dep + (v_eta_a - v_dep) * 0.2;
    v_b  := v_a + (v_eta_a - v_dep) * 0.4;
    v_at := v_a + (v_eta_a - v_dep) * 0.1;
    perform voyage.hold(v_fb, v_b, v_a);
    select eta into v_eta_b from public.voyages where id = v_vb;
    if v_at >= v_eta_a or v_eta_b <= v_b then
      raise exception '0413 self-assert FAIL: the probe passage is too short to move the clock inside it (% to %, held to %)', v_dep, v_eta_a, v_b;
    end if;
    v_mid  := v_at + (v_eta_a - v_at) / 2;
    v_post := v_b + (v_eta_b - v_b) / 2;
    v_pa_at   := voyage.progress_nm(v_va, v_at);
    v_pa_mid  := voyage.progress_nm(v_va, v_mid);
    v_da      := voyage.days_complete(v_va, v_at);
    v_pb_at   := voyage.progress_nm(v_vb, v_at);
    v_pb_post := voyage.progress_nm(v_vb, v_post);
    if v_pa_at <= 0 or v_pa_mid <= v_pa_at or v_pb_at <= 0 or v_pb_post <= v_pb_at or abs(v_pb_at - voyage.progress_nm(v_vb, v_a)) > 0.01 then
      raise exception '0413 self-assert FAIL: the probe voyages are not under way as staged (A % then %, B % then %)', v_pa_at, v_pa_mid, v_pb_at, v_pb_post;
    end if;
    -- the market's counters and the knobs that move, as they stand before
    foreach v_k in array c_kinds loop
      v_c0 := v_c0 || jsonb_build_object(v_k, jsonb_build_object(
                'now', public.clock_count(v_k, v_at), 'past', public.clock_count(v_k, v_at - interval '3 days'),
                'next', extract(epoch from public.clock_start(v_k, public.clock_count(v_k, v_at) + 1) - v_at)));
    end loop;
    select jsonb_object_agg(wc.key, wc.value) into v_keys from public.world_config wc
     where wc.key in ('game_day_seconds', 'drift_slot_seconds', 'want_period_seconds', 'population_slot_seconds', 'drift_spread_runs', 'glut_half_life_hours',
                      'invested_half_life_hours', 'navy_upkeep_day', 'works_coupon_day', 'pirate_spend_day_pct', 'population_tax_per_1000');

    v_r := public.clock_set(v_new, v_at);

    if public.wc_num('time_compression') <> v_new or (v_r->>'voyages')::int < 2 or (v_r->>'holds')::int < 1 then
      raise exception '0413 self-assert FAIL: the door did not move the rate with the probe voyages and the hold (%)', v_r - 'market';
    end if;
    -- A, plain: where she was at the instant; the rest of her passage five times as long; the same mile at five times the wait; the eta's own authority agrees
    select eta into v_e from public.voyages where id = v_va;
    if abs(voyage.progress_nm(v_va, v_at) - v_pa_at) > 0.01 or voyage.days_complete(v_va, v_at) <> v_da then
      raise exception '0413 self-assert FAIL: the plain voyage moved at the switch (% nm, was %; days %, was %)', voyage.progress_nm(v_va, v_at), v_pa_at, voyage.days_complete(v_va, v_at), v_da;
    end if;
    if abs(extract(epoch from v_e - (v_at + (v_eta_a - v_at) * 5))) > 0.005 or abs(extract(epoch from voyage.recompute_eta(v_va) - v_e)) > 0.005 then
      raise exception '0413 self-assert FAIL: the plain voyage''s arrival is %, not five times what was left after % (was %)', v_e, v_at, v_eta_a;
    end if;
    if abs(voyage.progress_nm(v_va, v_at + (v_mid - v_at) * 5) - v_pa_mid) > 0.01 then
      raise exception '0413 self-assert FAIL: the plain voyage is not at the same mile five times later (% nm, was %)', voyage.progress_nm(v_va, v_at + (v_mid - v_at) * 5), v_pa_mid;
    end if;
    if (select v.due_at from public.voyages v where v.id = v_va) is null or (select v.departed_at from public.voyages v where v.id = v_va) >= v_dep then
      raise exception '0413 self-assert FAIL: the plain voyage was not re-timed about the instant';
    end if;
    -- B, held: she stands where she stood until the hold's own end, then sails the rest five times as long
    select eta into v_e from public.voyages where id = v_vb;
    if abs(voyage.progress_nm(v_vb, v_at) - v_pb_at) > 0.01 or abs(voyage.progress_nm(v_vb, v_b) - v_pb_at) > 0.01
       or abs(voyage.progress_nm(v_vb, v_at + (v_b - v_at) / 2) - v_pb_at) > 0.01 then
      raise exception '0413 self-assert FAIL: the held voyage moved inside her hold (% / % / % nm, was %)', voyage.progress_nm(v_vb, v_at), voyage.progress_nm(v_vb, v_at + (v_b - v_at) / 2), voyage.progress_nm(v_vb, v_b), v_pb_at;
    end if;
    if abs(extract(epoch from v_e - (v_b + (v_eta_b - v_b) * 5))) > 0.05 then   -- her hold's hours are kept to three places: a few milliseconds
      raise exception '0413 self-assert FAIL: the held voyage''s arrival is %, not five times what was left after her hold ended at % (was %)', v_e, v_b, v_eta_b;
    end if;
    if abs(voyage.progress_nm(v_vb, v_b + (v_post - v_b) * 5) - v_pb_post) > 0.01 then
      raise exception '0413 self-assert FAIL: the held voyage is not at the same mile five times later (% nm, was %)', voyage.progress_nm(v_vb, v_b + (v_post - v_b) * 5), v_pb_post;
    end if;
    -- the clock: anchored at the instant, on the date it showed
    select value into v_r from public.world_config where key = 'clock_anchor';
    if (v_r->>'at')::timestamptz <> v_at or floor((v_r->>'day')::numeric) <> floor(extract(epoch from v_at - '2026-08-18 00:00:00+00'::timestamptz) / 2880)
       or (v_r->>'was')::numeric <> v_old or (v_r->>'is')::numeric <> v_new then
      raise exception '0413 self-assert FAIL: the clock''s anchor is % at %', v_r, v_at;
    end if;
    if (world.snapshot()->'config'->>'time_compression')::numeric <> v_new or (world.snapshot()->'config'->>'clock_voyage_days')::numeric <> 8
       or world.snapshot()->'config'->'clock_anchor' is distinct from v_r then
      raise exception '0413 self-assert FAIL: the snapshot does not serve the clock (%)', world.snapshot()->'config';
    end if;
    -- THE MARKET'S COUNTERS: each count at the instant is what it was; a count three days back reads as it did; the period it is in ends five
    -- times as far off; a millisecond before that end the count has not moved and at it it is one more; and its length is five times what it was
    foreach v_k in array c_kinds loop
      if public.clock_count(v_k, v_at) <> (v_c0 -> v_k ->> 'now')::bigint or public.clock_count(v_k, v_at - interval '3 days') <> (v_c0 -> v_k ->> 'past')::bigint
         or abs(extract(epoch from public.clock_start(v_k, public.clock_count(v_k, v_at) + 1) - v_at) - 5 * (v_c0 -> v_k ->> 'next')::numeric) > 0.001
         or public.clock_count(v_k, v_at + make_interval(secs => (5 * (v_c0 -> v_k ->> 'next')::numeric - 0.01)::double precision)) <> (v_c0 -> v_k ->> 'now')::bigint
         or public.clock_count(v_k, v_at + make_interval(secs => (5 * (v_c0 -> v_k ->> 'next')::numeric + 0.01)::double precision)) <> (v_c0 -> v_k ->> 'now')::bigint + 1
         or public.clock_count(v_k, public.clock_start(v_k, (v_c0 -> v_k ->> 'now')::bigint + 7)) <> (v_c0 -> v_k ->> 'now')::bigint + 7
         or public.clock_count(v_k, public.clock_start(v_k, (v_c0 -> v_k ->> 'now')::bigint - 7)) <> (v_c0 -> v_k ->> 'now')::bigint - 7 then
        raise exception '0413 self-assert FAIL: the counter % is not counted on across the switch (before %, at the instant %, its next start % s off)', v_k, v_c0 -> v_k,
          public.clock_count(v_k, v_at), extract(epoch from public.clock_start(v_k, public.clock_count(v_k, v_at) + 1) - v_at);
      end if;
      v_mk := v_mk || v_k || ' ' || (v_c0 -> v_k ->> 'now') || ' ';
    end loop;
    if world.game_day(v_at) <> (v_c0 -> 'game_day' ->> 'now')::int or public.drift_slot_of(v_at) <> (v_c0 -> 'drift_slot' ->> 'now')::bigint
       or public.want_period(v_at) <> (v_c0 -> 'want_period' ->> 'now')::bigint
       or public.next_drift_change_at(v_at) <> public.clock_start('drift_slot', (v_c0 -> 'drift_slot' ->> 'now')::bigint + 1) then
      raise exception '0413 self-assert FAIL: a counter''s old name does not read the one authority';
    end if;
    if exists (select 1 from public.world_config wc
                where (wc.key in ('game_day_seconds', 'drift_slot_seconds', 'want_period_seconds', 'population_slot_seconds', 'drift_spread_runs', 'glut_half_life_hours', 'invested_half_life_hours')
                       and (wc.value #>> '{}')::numeric <> 5 * (v_keys ->> wc.key)::numeric)
                   or (wc.key in ('navy_upkeep_day', 'works_coupon_day', 'pirate_spend_day_pct', 'population_tax_per_1000')
                       and abs((wc.value #>> '{}')::numeric * 5 - (v_keys ->> wc.key)::numeric) > (v_keys ->> wc.key)::numeric * 0.000000001)) then
      raise exception '0413 self-assert FAIL: a length is not five times what it was or a rate not a fifth (before %)', v_keys;
    end if;
    -- THE INVARIANT: market days, drift slots, want periods and population steps per voyage-day are what they were
    if exists (select 1 from unnest(array['game_day_seconds', 'drift_slot_seconds', 'want_period_seconds', 'population_slot_seconds']) k
                where v_old * (v_keys ->> k)::numeric <> v_new * public.wc_num(k)) then   -- (86,400 / rate) / length, cross-multiplied
      raise exception '0413 self-assert FAIL: a counter''s periods per voyage-day moved';
    end if;
    v_note := 'a plain voyage and a held one, re-timed ' || round(extract(epoch from v_at - v_dep), 2) || ' s out: same mile at the instant, the rest x5 (' ||
              round(extract(epoch from v_eta_a - v_at), 2) || ' s left became ' || round(extract(epoch from (select eta from public.voyages where id = v_va) - v_at), 2) ||
              ' s); the counters counted on (' || trim(v_mk) || '), their periods per voyage-day unmoved';
    raise exception sqlstate 'BV413';
  exception when sqlstate 'BV413' then null;
  end;
  if v_note = '' then
    raise exception '0413 self-assert FAIL: the probe did not run to its end';
  end if;
  if public.wc_num('time_compression') <> v_old or exists (select 1 from public.players where auth_uid in (c_uid_a, c_uid_b))
     or (select value from public.world_config where key = 'clock_anchor') <> '{}'::jsonb
     or (select value from public.world_config where key = 'market_clock_anchor') <> '{}'::jsonb or public.wc_num('population_slot_seconds') <> 600 then
    raise exception '0413 self-assert FAIL: the probe was not rolled back';
  end if;

  -- ── 4. THE SWITCH, at this transaction's instant ──
  v_r := public.clock_set(v_new, now());
  if public.wc_num('time_compression') <> 192 or 86400 * public.wc_num('clock_voyage_days') / public.wc_num('time_compression') <> 3600
     or 86400 / public.wc_num('time_compression') <> 450 or public.wc_num('population_slot_seconds') <> 3000 then
    raise exception '0413 self-assert FAIL: a day of the clock is % s and a voyage-day % s, not 3,600 and 450', 86400 * public.wc_num('clock_voyage_days') / public.wc_num('time_compression'), 86400 / public.wc_num('time_compression');
  end if;

  perform public.news_update('0413', 'A game day now lasts one hour: ships and markets run five times slower', '게임의 하루가 이제 한 시간입니다. 배와 시장이 다섯 배 느리게 움직입니다');

  if clock_timestamp() - v_t0 > interval '40 seconds' then
    raise exception '0413 self-assert FAIL: the file took % (budget 40 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0413 self-assert ok: A DAY LASTS AN HOUR. time_compression % -> 192; a voyage-day is 450 s; a day of the clock is 8 of them, 3,600 s, derived and served. Nine hunks over nine bodies, each once and reversing; no other function moved. The market: game_day_seconds %, drift_slot_seconds %, want_period_seconds %, population_slot_seconds %, drift_spread_runs %; navy_upkeep_day %, works_coupon_day %. The switch: %. Probe: %; % ms.',
    v_old, public.wc_num('game_day_seconds'), public.wc_num('drift_slot_seconds'), public.wc_num('want_period_seconds'), public.wc_num('population_slot_seconds'),
    public.wc_num('drift_spread_runs'), public.wc_num('navy_upkeep_day'), public.wc_num('works_coupon_day'), v_r - 'market', v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
