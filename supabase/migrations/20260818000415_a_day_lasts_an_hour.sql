-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0415 - A DAY LASTS AN HOUR  (the clock runs five times slower: time_compression 960 -> 192; a day of the game's clock is 3,600 real seconds, was 720)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-14: "change the game day - 1 hour." He had been told a game day is 12 real minutes and that a longer day means fewer events per
-- real minute on a database that is too small. Decided by default (the coordinator, the same day): the day he sees goes from 12 minutes to 60, a
-- factor of 5, and sailing keeps its proportion to it. docs/dev-log/2026-11-14-day-hour.md has the table of what scales and what stays.
--
-- WHAT A "DAY" WAS (three numbers, found by reading; none of them was derived from another on the server):
--   * the day of the top bar's clock and of the map's Sun: 720 real seconds. A CLIENT constant only (src/lib/format/time.ts GAME_CLOCK_RATE =
--     TIME_COMPRESSION / 8): eight voyage-days. The server had no such number.
--   * a voyage-day (sailing, stores, wages, the day's weather and raid roll, every "N days" on a screen): 86,400 / time_compression = 90 real seconds.
--   * the market's day (world.game_day: stock regeneration, the daily caps, a request's deadline): game_day_seconds, 2,880 in this chain and 60 on
--     prod by the owner's hand since 2026-10-30. NOT TOUCHED HERE, nor drift_slot_seconds: see NOT BUILT.
--
-- WHAT THIS FILE DOES:
--   1. ONE AUTHORITY, WITH THE RATIO STATED. world_config.time_compression stays the one rate (every sailing body already reads it; it is already
--      served). clock_voyage_days (new, 8) states what the client only assumed: a day of the clock and the Sun is that many voyage-days. So the day's
--      length is 86,400 x clock_voyage_days / time_compression = 3,600 real seconds, and nothing holds a second copy: world.snapshot() serves
--      clock_voyage_days and clock_anchor beside time_compression (one hunk), and the client reads them (its 960 and its 8 were mirrors).
--   2. time_compression 960 -> 192. A voyage-day is 450 real seconds. Knots, miles, stores, wages and rolls per voyage-day are as they were: every
--      passage is the same number of days and costs what it cost; she is watched for five times as long.
--   3. THE ONE DOOR TO MOVE THE RATE, public.clock_set(compression, at): the knob, every voyage at sea and the clock's anchor in one statement group,
--      so that nothing jumps. A voyage is a pure function of departed_at and the rate (0006), so a voyage under way is RE-TIMED ABOUT THE INSTANT:
--      departed_at and eta are both moved by t' = at + (t - at) x old / new. Her miles run, her days settled and her next boundary are the same at
--      the instant; what is left of her passage takes old / new times as long. No ship moves on the chart, none arrives early, none is stranded.
--      A battle's hold running across the instant keeps its end and is re-timed the same way (its start and its hours); such a battle runs to its
--      full length (an early end no longer finds the hold by its start; ten minutes at the most).
--      The rollback is the same door with 960: continuous too.
--   4. THE CLOCK AND THE DATE DO NOT JUMP. clock_anchor = {at, day}: the instant of the switch and the clock's own reading then (whole days: the date
--      as the top bar printed it, 1 January 1500 + a day per 2,880 s; the fraction: the hour hand as it stood). From the anchor on, date and hour
--      are ONE clock, a day per 3,600 s: the date turns when the hour passes midnight (before, the date turned every 48 minutes and the hour hand
--      went round every 12). A month is 30 of those days: 30 real hours (was 24). Decided by default; the owner may reverse it.
--
-- STAYS AS IT IS (real time, pacing a person or the world's turns): port_prep_seconds 60, battle_seconds, attack and gift cooldowns, the back-off's
--   minutes, navy and pirate lie-up hours, skill training per hour, the daily caps (real UTC days), dividends per real day, every cron cadence.
--   A rest or repair already running keeps its stored end.
-- NOT BUILT (said loudly): the market's clock. game_day_seconds and drift_slot_seconds are absolute counters (floor(epoch / knob)) stored in a dozen
--   columns (port_goods.last_regen_day and drift_slot, trade_contracts.expires_day, trade_daily.game_day ...): dividing the index by five freezes
--   regeneration and drift until the count catches up, and the by-hand move of 2026-10-30 broke dividends (0312). It needs its own file with an
--   offset and its own measured window. Until then the market regenerates and drifts five times as much per voyage-day as before.
--
-- LOCKS: CREATE FUNCTION x1; CREATE OR REPLACE x1 by one hunk (world.snapshot); two knobs; one UPDATE of every SAILING voyage (and the knob's 0242
--   trigger re-keeps due_at once): row locks only, with the clock jobs unwound by the deploy. The probe does the same once more and is rolled back.
-- TIME: about four writes per voyage at sea in all (about 1,300 at sea on prod: under 10 s expected). BUDGET: statement_timeout 60 s, lock_timeout 5 s;
--   fails above 40 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/day-hour/rollback-0415.sql, a draft: select public.clock_set(960).
-- SELF-ASSERT: the hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then two probe voyages
--   (one plain, one held by a battle) re-timed in a rolled-back sub-transaction; only the probe's own rows are read.
-- VERSION: 0415 (provisional; it re-cuts world.snapshot only and may be renumbered below the files it was written beside).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $g$
begin
  if exists (select 1 from public.world_config where key in ('clock_voyage_days', 'clock_anchor')) or to_regprocedure('public.clock_set(integer,timestamp with time zone)') is not null then
    raise exception '0415 refuses: it has been applied once';
  end if;
  if public.wc_num('time_compression') <> 960 then
    raise exception '0415 refuses: time_compression is %, not the 960 this file was written against (a day of the clock is not 720 s here)', public.wc_num('time_compression');
  end if;
end $g$;

insert into public.world_config (key, value, description) values
  ('clock_voyage_days', to_jsonb(8),
   '0415: a day of the game''s clock (the top bar''s hour and date, the Sun on the map) is this many voyage-days. THE DAY''S LENGTH IS DERIVED, never typed: 86,400 x clock_voyage_days / time_compression real seconds (3,600 at 192; 720 at the 960 it replaced). Served by world.snapshot(). It was a client constant (the owner, 2026-10-15 and 2026-10-17: the clock and the light slowed to an eighth of the ships).'),
  ('clock_anchor', '{}'::jsonb,
   '0415: where the game''s clock stood when its rate last moved: {at: the instant, day: days since 1 January 1500 with the hour as its fraction, was, is: the rates}. Written only by public.clock_set. From it the clock runs a day per 86,400 x clock_voyage_days / time_compression seconds, so a change of rate never moves the date or the hour. Empty: the clock as it was before 0415. Served by world.snapshot().');

create function public.clock_set(p_compression integer, p_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $f$
-- 0415: THE ONE DOOR TO MOVE THE CLOCK'S RATE (world_config.time_compression). Owner only. It moves three things together so that nothing jumps:
--   the knob; every voyage at sea, re-timed about p_at (t' = p_at + (t - p_at) x old / new on departed_at and eta: a voyage is a pure function of the
--   two and the rate, so her miles, her settled days and her next boundary are the same at p_at and the rest of her passage runs at the new rate);
--   and the clock's anchor (its reading at p_at at the old rate, from which it runs at the new one).
-- A hold (a battle, 0323) running across p_at keeps its end; its start and its hours are re-timed the same way, so she stands where she stood.
-- The same rate: nothing is written. Returns what it did.
declare
  v_old    numeric := public.wc_num('time_compression');
  v_cvd    numeric := public.wc_num('clock_voyage_days');
  v_anchor jsonb   := (select value from public.world_config where key = 'clock_anchor');
  v_f      numeric;
  v_day    numeric;
  v_x      numeric;
  v_n      int;
  v_held   uuid[];
  v_id     uuid;
begin
  if p_compression is null or p_compression < 1 or p_at is null then
    raise exception 'E_BAD_CLOCK: a rate of % at %', p_compression, p_at using errcode = 'P0001';
  end if;
  if p_compression = v_old then
    return jsonb_build_object('moved', false, 'time_compression', v_old);
  end if;
  v_f := v_old / p_compression;

  -- the clock's reading at p_at, at the old rate: from the anchor, or (none yet) as the client drew it before 0415: the date a day per 2,880 s
  -- from 2026-08-18 UTC, the hour hand the second of the UTC day at old / clock_voyage_days times real time.
  if v_anchor ? 'at' then
    v_day := (v_anchor->>'day')::numeric + extract(epoch from p_at - (v_anchor->>'at')::timestamptz) * v_old / (86400 * v_cvd);
  else
    v_x   := mod(extract(epoch from p_at)::numeric, 86400) * v_old / v_cvd / 86400;
    v_day := floor(extract(epoch from p_at - '2026-08-18 00:00:00+00'::timestamptz) / 2880) + (v_x - floor(v_x));
  end if;

  update public.world_config
     set value = to_jsonb(p_compression), updated_at = now(),
         description = 'DESIGN D.1, THE CLOCK''S ONE RATE: voyage-time per real time. A voyage-day is 86,400 / this real seconds (450 at 192); a day of the game''s clock is clock_voyage_days of those (3,600 s at 192). 0415 (the owner, 2026-11-14: "change the game day - 1 hour"): 960 -> 192. Move it ONLY through public.clock_set, which re-times the voyages at sea and the clock''s anchor with it. Was ' || v_old || ' until ' || p_at || '.'
   where key = 'time_compression';
  update public.world_config
     set value = jsonb_build_object('at', p_at, 'day', round(v_day, 8), 'was', v_old, 'is', p_compression), updated_at = now()
   where key = 'clock_anchor';

  with h as (
    update public.voyage_events ve
       set payload = ve.payload || jsonb_build_object(
             'held_from', p_at - ((p_at - (ve.payload->>'held_from')::timestamptz) * v_f::double precision),
             'delay_hours', trim_scale(round((extract(epoch from (ve.payload->>'held_until')::timestamptz - p_at)
                                              + extract(epoch from p_at - (ve.payload->>'held_from')::timestamptz) * v_f) * p_compression / 3600, 10)),
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
                            'clock_day_seconds', round(86400 * v_cvd / p_compression, 3));
end
$f$;
revoke all on function public.clock_set(integer, timestamptz) from public, anon, authenticated;

do $m$
declare
  c_cut constant text[] := array['world.snapshot()'];
  c_new constant text[] := array['public.clock_set(integer,timestamp with time zone)'];
  c_uid_a constant uuid := '00000000-0000-4000-8000-00000000415a';
  c_uid_b constant uuid := '00000000-0000-4000-8000-00000000415b';
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
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0415 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0415
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid);

  -- ── 2. THE HUNK: the snapshot serves the ratio and the anchor beside the rate ──
  create temp table hunk_0415 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0415 values
  (1, c_cut[1],
$h$        'time_compression',  public.wc_int('time_compression'),
$h$,
$h$        'time_compression',  public.wc_int('time_compression'),
        -- 0415: THE CLOCK'S DAY, beside the rate it is derived from: 86,400 x clock_voyage_days / time_compression real seconds; and where the
        -- 0415: clock stood when the rate last moved (public.clock_set), so the date and the hour never jump.
        'clock_voyage_days', public.wc_num('clock_voyage_days'),
        'clock_anchor',      (select wc.value from public.world_config wc where wc.key = 'clock_anchor'),
$h$);
  for h in select * from hunk_0415 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0415 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0415 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0415 p where p.fn = h.fn) then
      raise exception '0415 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0415 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0415 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0415 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0415 self-assert FAIL: another function moved';
  end if;
  if has_function_privilege('anon', 'public.clock_set(integer,timestamp with time zone)', 'execute')
     or has_function_privilege('authenticated', 'public.clock_set(integer,timestamp with time zone)', 'execute') then
    raise exception '0415 self-assert FAIL: a player can move the clock';
  end if;

  -- ── 3. THE PROBE: two houses put to sea Lisbon to Setubal (0100's pair), one of them held by a battle, the clock moved while they sail, all rolled
  --      back. Only these two voyages are read. The instants are passed in, so nothing waits.
  begin
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_set from public.ports where code = 'SET';
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_course from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_set;
    if v_course is null then
      raise exception '0415 self-assert FAIL: Lisbon or Setubal has no roadstead to sail between';
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
      raise exception '0415 self-assert FAIL: the probe passage is too short to move the clock inside it (% to %, held to %)', v_dep, v_eta_a, v_b;
    end if;
    v_mid  := v_at + (v_eta_a - v_at) / 2;
    v_post := v_b + (v_eta_b - v_b) / 2;
    v_pa_at   := voyage.progress_nm(v_va, v_at);
    v_pa_mid  := voyage.progress_nm(v_va, v_mid);
    v_da      := voyage.days_complete(v_va, v_at);
    v_pb_at   := voyage.progress_nm(v_vb, v_at);
    v_pb_post := voyage.progress_nm(v_vb, v_post);
    if v_pa_at <= 0 or v_pa_mid <= v_pa_at or v_pb_at <= 0 or v_pb_post <= v_pb_at or abs(v_pb_at - voyage.progress_nm(v_vb, v_a)) > 0.01 then
      raise exception '0415 self-assert FAIL: the probe voyages are not under way as staged (A % then %, B % then %)', v_pa_at, v_pa_mid, v_pb_at, v_pb_post;
    end if;

    v_r := public.clock_set(v_new, v_at);

    if public.wc_num('time_compression') <> v_new or (v_r->>'voyages')::int < 2 or (v_r->>'holds')::int < 1 then
      raise exception '0415 self-assert FAIL: the door did not move the rate with the probe voyages and the hold (%)', v_r;
    end if;
    -- A, plain: where she was at the instant; the rest of her passage five times as long; the same mile at five times the wait; the eta's own authority agrees
    select eta into v_e from public.voyages where id = v_va;
    if abs(voyage.progress_nm(v_va, v_at) - v_pa_at) > 0.01 or voyage.days_complete(v_va, v_at) <> v_da then
      raise exception '0415 self-assert FAIL: the plain voyage moved at the switch (% nm, was %; days %, was %)', voyage.progress_nm(v_va, v_at), v_pa_at, voyage.days_complete(v_va, v_at), v_da;
    end if;
    if abs(extract(epoch from v_e - (v_at + (v_eta_a - v_at) * 5))) > 0.005 or abs(extract(epoch from voyage.recompute_eta(v_va) - v_e)) > 0.005 then
      raise exception '0415 self-assert FAIL: the plain voyage''s arrival is %, not five times what was left after % (was %)', v_e, v_at, v_eta_a;
    end if;
    if abs(voyage.progress_nm(v_va, v_at + (v_mid - v_at) * 5) - v_pa_mid) > 0.01 then
      raise exception '0415 self-assert FAIL: the plain voyage is not at the same mile five times later (% nm, was %)', voyage.progress_nm(v_va, v_at + (v_mid - v_at) * 5), v_pa_mid;
    end if;
    if (select v.due_at from public.voyages v where v.id = v_va) is null or (select v.departed_at from public.voyages v where v.id = v_va) >= v_dep then
      raise exception '0415 self-assert FAIL: the plain voyage was not re-timed about the instant';
    end if;
    -- B, held: she stands where she stood until the hold's own end, then sails the rest five times as long
    select eta into v_e from public.voyages where id = v_vb;
    if abs(voyage.progress_nm(v_vb, v_at) - v_pb_at) > 0.01 or abs(voyage.progress_nm(v_vb, v_b) - v_pb_at) > 0.01
       or abs(voyage.progress_nm(v_vb, v_at + (v_b - v_at) / 2) - v_pb_at) > 0.01 then
      raise exception '0415 self-assert FAIL: the held voyage moved inside her hold (% / % / % nm, was %)', voyage.progress_nm(v_vb, v_at), voyage.progress_nm(v_vb, v_at + (v_b - v_at) / 2), voyage.progress_nm(v_vb, v_b), v_pb_at;
    end if;
    if abs(extract(epoch from v_e - (v_b + (v_eta_b - v_b) * 5))) > 0.005 then
      raise exception '0415 self-assert FAIL: the held voyage''s arrival is %, not five times what was left after her hold ended at % (was %)', v_e, v_b, v_eta_b;
    end if;
    if abs(voyage.progress_nm(v_vb, v_b + (v_post - v_b) * 5) - v_pb_post) > 0.01 then
      raise exception '0415 self-assert FAIL: the held voyage is not at the same mile five times later (% nm, was %)', voyage.progress_nm(v_vb, v_b + (v_post - v_b) * 5), v_pb_post;
    end if;
    -- the clock: anchored at the instant, on the date it showed
    select value into v_r from public.world_config where key = 'clock_anchor';
    if (v_r->>'at')::timestamptz <> v_at or floor((v_r->>'day')::numeric) <> floor(extract(epoch from v_at - '2026-08-18 00:00:00+00'::timestamptz) / 2880)
       or (v_r->>'was')::numeric <> v_old or (v_r->>'is')::numeric <> v_new then
      raise exception '0415 self-assert FAIL: the clock''s anchor is % at %', v_r, v_at;
    end if;
    if (world.snapshot()->'config'->>'time_compression')::numeric <> v_new or (world.snapshot()->'config'->>'clock_voyage_days')::numeric <> 8
       or world.snapshot()->'config'->'clock_anchor' is distinct from v_r then
      raise exception '0415 self-assert FAIL: the snapshot does not serve the clock (%)', world.snapshot()->'config';
    end if;
    v_note := 'a plain voyage and a held one, re-timed ' || round(extract(epoch from v_at - v_dep), 2) || ' s out: same mile at the instant, the rest x5 (' ||
              round(extract(epoch from v_eta_a - v_at), 2) || ' s left became ' || round(extract(epoch from (select eta from public.voyages where id = v_va) - v_at), 2) || ' s)';
    raise exception sqlstate 'BV415';
  exception when sqlstate 'BV415' then null;
  end;
  if v_note = '' then
    raise exception '0415 self-assert FAIL: the probe did not run to its end';
  end if;
  if public.wc_num('time_compression') <> v_old or exists (select 1 from public.players where auth_uid in (c_uid_a, c_uid_b))
     or (select value from public.world_config where key = 'clock_anchor') <> '{}'::jsonb then
    raise exception '0415 self-assert FAIL: the probe was not rolled back';
  end if;

  -- ── 4. THE SWITCH, at this transaction's instant ──
  v_r := public.clock_set(v_new, now());
  if public.wc_num('time_compression') <> 192 or 86400 * public.wc_num('clock_voyage_days') / public.wc_num('time_compression') <> 3600
     or 86400 / public.wc_num('time_compression') <> 450 then
    raise exception '0415 self-assert FAIL: a day of the clock is % s and a voyage-day % s, not 3,600 and 450', 86400 * public.wc_num('clock_voyage_days') / public.wc_num('time_compression'), 86400 / public.wc_num('time_compression');
  end if;

  perform public.news_update('0415', 'A game day now lasts one hour: ships sail five times slower', '게임의 하루가 이제 한 시간입니다. 배가 다섯 배 느리게 항해합니다');

  if clock_timestamp() - v_t0 > interval '40 seconds' then
    raise exception '0415 self-assert FAIL: the file took % (budget 40 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0415 self-assert ok: A DAY LASTS AN HOUR. time_compression % -> 192; a voyage-day is 450 s; a day of the clock is 8 of them, 3,600 s, derived and served (one hunk over world.snapshot, once and reversing; no other function moved). The switch: %. Probe: %; % ms.',
    v_old, v_r, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
