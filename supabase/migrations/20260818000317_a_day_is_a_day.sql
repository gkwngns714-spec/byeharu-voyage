-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0317 — A DAY IS A DAY: what a person reads as a day, and what must outlast the hourly tick, stops counting in game days
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- docs/dev-log/2026-11-05-game-day-audit.md holds every use of world.game_day read on prod, its real meaning, the measurements and what is left for the owner.
--
-- WHY. game_day_seconds went 2880 -> 60 by hand on 2026-10-30, so a game day is one real minute. The market was meant to tick that fast. Report's Day and Week
-- were a minute and seven; "paid today" and the hall's "Yesterday" were minutes; the market's "today" was a minute; three haggles "a day" were three a minute;
-- a fair lasted 4 minutes in a 30-minute season; the crown tax paid on half the tax (5.2 to 5.5 % against the knob's 10 %, measured 11-03 and 11-04), because
-- step 2 CARRY keeps 30 game days, 30 minutes, and step 6b read what was left an hour later.
--
-- WHAT THIS FILE DOES (one pattern: a number that means a real day never passes through game_day_seconds again)
--   1. world.report, world.holdings: real UTC days through public.real_day (0312). Wire: `game_day` becomes `day`.
--   2. world.town_hall `day`: the last 24 hours, by kind, as of the last count (stats_city.day, the newest row, one primary-key read: the hall is read every second).
--   3. public.traded_today, world.price_why `volume`: the last 24 hours of stats_city_good. `houses` goes: no store keeps it (merchant trade_daily rows live a minute).
--   4. haggle_daily: keyed by real day, column `game_day` is now `day`; its 2 rows of September go.
--   5. buff_kinds: duration_seconds 11,520 and season_seconds 86,400, the design's 4 and 30 days of 2,880 s, in seconds; the running calendar is re-drawn.
--   6. port_treasury.tax_unshared: TAX not yet shared with the crown, added in the roll (as 0312's profit), read and closed by public.city_day.
--
-- NOT TOUCHED, BALANCE CHOICES FOR THE OWNER (measured in the dev-log): treasury_reserve_days and treasury_days_kept (a real 3 days: cities under reserve 74 -> 208
-- of 246, mean sale bid 0.894 -> 0.594), the daily cap (a real day refuses 17 % of the units of 6 hours), the merchant lap floor, a player route's pace, restock and
-- drift (owner-directed on 10-30), city_earnings (dark while the economy is closed). No knob, no switch, no game step.
--
-- MOVES THE ECONOMY: only 6, about +1.4 M d. a day from cities to their capitals, nothing minted. Fairs: the same 1.6 % of harbours in a fair, 3.2 hours long.
--
-- SELF-ASSERT (probe rows, rolled back; no real game step, docs/OPS_HEALTH.md section 4): every hunk once and reversing, grants, nothing else moved, no knob moved;
-- a season and a bargain are the same at both clocks; the volume's 24 hours. THE REAL READS AND THE REAL tick_city ARE PROVED IN CI: proof 26,
-- scripts/db/proofs/26_a_day.sql. Mutation controls: scripts/ops/harness/a-day/proof-0317.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Deploy away from minute :37. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): docs/dev-log/2026-11-05-game-day-audit.md.
-- VERSION: 0317 - prod head 0313 when cut (2026-11-05); follows 0314, 0315, 0316.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_fns constant text[] := array[
    'public.tick_city(timestamp with time zone)', 'public.city_day(timestamp with time zone)', 'public.tick_buff_calendar(timestamp with time zone)',
    'world.report(text)', 'world.holdings()', 'world.town_hall(uuid)', 'world.price_why(uuid,uuid)', 'world.buffs(uuid)', 'world.haggle_state(uuid,uuid)',
    'cmd.do_buy(uuid,jsonb)', 'cmd.do_sell(uuid,jsonb)', 'cmd.haggle(uuid,uuid,text)',
    'public.haggle_concession(uuid,uuid,uuid)', 'public.haggle_odds(uuid,uuid,uuid,uuid)'];
  v_h    record;
  v_fn   text;
  v_def  text;
  v_n    int;
  v_fn_before  text;
  v_cfg_before text;
  v_meta_before text;
  v_t0   timestamptz := clock_timestamp();
  v_port uuid;
  v_good uuid;
  v_p    uuid;
  v_nat  uuid;
  v_gds  int;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.real_day(timestamp with time zone)') is null or to_regprocedure('public.city_coupons(uuid,timestamp with time zone)') is null then
    raise exception '0317 refuses: 0312 (public.real_day) is not in this world';
  end if;
  if exists (select 1 from information_schema.columns c where c.table_schema = 'public'
              and ((c.table_name = 'port_treasury' and c.column_name = 'tax_unshared') or (c.table_name = 'buff_kinds' and c.column_name = 'season_seconds')
                   or (c.table_name = 'haggle_daily' and c.column_name = 'day'))) then
    raise exception '0317 refuses: it has been applied once';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_fns) x))
     and p.oid not in ('public.traded_today(uuid,uuid)'::regprocedure, 'public.buff_season_of(timestamp with time zone,numeric)'::regprocedure);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_fns) x));

  -- ── 1. THE TABLES ──
  alter table public.port_treasury add column tax_unshared bigint not null default 0;
  comment on column public.port_treasury.tax_unshared is
    '0317: TAX rolled and not yet shared with the crown, added in the roll of public.tick_city, closed to 0 by public.city_day. Not read from public.treasury_daybook: treasury_days_kept is 30 game days, 30 minutes today, so step 2 CARRY has eaten half an hour-old roll before step 6b runs.';

  alter table public.haggle_daily rename column game_day to day;
  comment on column public.haggle_daily.day is '0317: the real day (public.real_day) of the bargaining.';
  delete from public.haggle_daily;   -- rows keyed by the old clock: none can ever be today

  alter table public.buff_kinds rename column duration_game_days to duration_seconds;
  alter table public.buff_kinds rename column season_game_days to season_seconds;
  alter table public.buff_kinds alter column duration_seconds type numeric, alter column season_seconds type numeric;
  alter table public.buff_kinds rename constraint buff_kinds_duration_game_days_check to buff_kinds_duration_seconds_check;
  update public.buff_kinds set duration_seconds = duration_seconds * 2880, season_seconds = season_seconds * 2880;   -- the days they were written in: 2,880 s, the design's
  comment on column public.buff_kinds.duration_seconds is '0317: how long it runs, in real seconds, whatever game_day_seconds says.';
  comment on column public.buff_kinds.season_seconds is '0317: its season, in real seconds, whatever game_day_seconds says. Null: not on the calendar.';
  delete from public.active_buffs where season is not null;   -- seasons numbered by the old clock; public.tick_buff_calendar draws today's at its next call

  -- ── 2. THE WHOLE BODIES: their arguments or their answer change, so they are dropped and made again ──
  drop function public.traded_today(uuid, uuid);
  execute $f$
create function public.traded_today(p_port uuid, p_good uuid)
returns numeric
language sql
stable security definer
set search_path = public, pg_temp
as $body$
  -- 0317 (0190's, moved off public.trade_daily, whose merchant rows live a minute): the units of this good bought and sold at this port in the last 24 hours,
  -- players and merchants alike, as of the last count. Read by world.price_why.
  select coalesce(sum(coalesce(s.sold, 0) + coalesce(s.bought, 0)), 0)::numeric
    from public.stats_city_good s
   where s.port_id = p_port and s.good_id = p_good and s.at > now() - interval '24 hours'
$body$
  $f$;
  revoke all on function public.traded_today(uuid, uuid) from public, anon, authenticated;

  drop function public.buff_season_of(timestamptz, numeric);
  execute $f$
create function public.buff_season_of(p_at timestamptz, p_season_seconds numeric)
returns integer
language sql
stable security definer
set search_path = public, pg_temp
as $body$ select floor(extract(epoch from p_at) / p_season_seconds)::int $body$
  $f$;
  revoke all on function public.buff_season_of(timestamptz, numeric) from public, anon, authenticated;

  -- ── 3. THE HUNKS: each occurs exactly once on the live body and reverses to it ──
  create temp table hunks_0317 (ord serial primary key, fn text not null, old text not null, new text not null) on commit drop;
  insert into hunks_0317 (fn, old, new) values
  -- the roll keeps the tax
  ('public.tick_city(timestamp with time zone)',
$h$           profit = t.profit + s.earned,   -- 0312: what public.city_coupons may pay out; the daybook keeps too few days to say
$h$,
$h$           profit = t.profit + s.earned,   -- 0312: what public.city_coupons may pay out; the daybook keeps too few days to say
           tax_unshared = t.tax_unshared + s.tax,   -- 0317: what public.city_day shares with the crown; the same reason
$h$),
  ('public.tick_city(timestamp with time zone)',
$h$                   coalesce(sum(f.ducats) filter (where public.flow_is_profit(f.kind)), 0) as earned,
$h$,
$h$                   coalesce(sum(f.ducats) filter (where public.flow_is_profit(f.kind)), 0) as earned,
                   coalesce(sum(f.ducats) filter (where f.kind = 'TAX'), 0) as tax,
$h$),
  -- the crown's share reads it
  ('public.city_day(timestamp with time zone)',
$h$--   CROWN_TAX  crown_tax_share of the TAX the city took on those days, to its capital (never more
--              than it holds; a capital pays none to itself);
$h$,
$h$--   CROWN_TAX  crown_tax_share of the TAX rolled since it was last shared (0317: port_treasury.tax_unshared), to its capital (never more
--              than it holds; a capital pays none to itself);
$h$),
  ('public.city_day(timestamp with time zone)',
$h$  v_tax    bigint;
  v_s      bigint;
$h$,
$h$  v_s      bigint;
$h$),
  ('public.city_day(timestamp with time zone)',
$h$  for r in select t.port_id, t.earned_day from public.port_treasury t
$h$,
$h$  for r in select t.port_id, t.earned_day, t.tax_unshared from public.port_treasury t
$h$),
  ('public.city_day(timestamp with time zone)',
$h$    -- THE CROWN'S SHARE of the city's tax on those days
$h$,
$h$    -- THE CROWN'S SHARE of the city's tax
$h$),
  ('public.city_day(timestamp with time zone)',
$h$      select coalesce(sum(d.ducats), 0) into v_tax from public.treasury_daybook d
       where d.port_id = r.port_id and d.kind = 'TAX' and d.game_day > v_since and d.game_day <= v_last;
      v_s := round(v_tax * public.wc_num('crown_tax_share'))::bigint;
$h$,
$h$      v_s := round(r.tax_unshared * public.wc_num('crown_tax_share'))::bigint;
$h$),
  ('public.city_day(timestamp with time zone)',
$h$    update public.port_treasury set earned_day = v_last where port_id = r.port_id;
$h$,
$h$    update public.port_treasury set earned_day = v_last, tax_unshared = 0 where port_id = r.port_id;
$h$),
  -- the calendar, in seconds
  ('public.tick_buff_calendar(timestamp with time zone)',
$h$  v_season int;
  v_gds    numeric := public.wc_num('game_day_seconds');
$h$,
$h$  v_season int;
$h$),
  ('public.tick_buff_calendar(timestamp with time zone)',
$h$            where season_game_days is not null and subject_kind = 'PORT'
$h$,
$h$            where season_seconds is not null and subject_kind = 'PORT'
$h$),
  ('public.tick_buff_calendar(timestamp with time zone)',
$h$    v_season := public.buff_season_of(p_at, k.season_game_days);
$h$,
$h$    v_season := public.buff_season_of(p_at, k.season_seconds);
$h$),
  ('public.tick_buff_calendar(timestamp with time zone)',
$h$             to_timestamp((d.open_day * v_gds)::double precision),
             to_timestamp(((d.open_day + k.duration_game_days) * v_gds)::double precision),
$h$,
$h$             to_timestamp(d.open_at::double precision),
             to_timestamp((d.open_at + k.duration_seconds)::double precision),
$h$),
  ('public.tick_buff_calendar(timestamp with time zone)',
$h$        -- The fair opens somewhere INSIDE its season, on a game-day this port draws for itself, so
$h$,
$h$        -- The fair opens somewhere INSIDE its season, at a second this port draws for itself, so
$h$),
  ('public.tick_buff_calendar(timestamp with time zone)',
$h$         select v_season * k.season_game_days
                + floor(voyage.rng(p.id, v_season, 'buff-day:' || k.code)
                        * (k.season_game_days - k.duration_game_days)) as open_day
$h$,
$h$         select v_season * k.season_seconds
                + floor(voyage.rng(p.id, v_season, 'buff-day:' || k.code)
                        * (k.season_seconds - k.duration_seconds)) as open_at
$h$),
  ('world.buffs(uuid)',
$h$               'duration_game_days', k.duration_game_days,
               'season_game_days', k.season_game_days,
$h$,
$h$               'duration_seconds', k.duration_seconds,
               'season_seconds', k.season_seconds,
$h$),
  -- the Report
  ('world.report(text)',
$h$-- span (game days), by the design's fixed sections and by point (port, else voyage, else Earlier).
$h$,
$h$-- span (0317: real UTC days, public.real_day), by the design's fixed sections and by point (port, else voyage, else Earlier).
$h$),
  ('world.report(text)',
$h$  v_today  int := world.game_day();
  v_gds    numeric := public.wc_num('game_day_seconds');
$h$,
$h$  v_today  int := public.real_day(now());
$h$),
  ('world.report(text)',
$h$    -- the EXACT game-day boundary: world.game_day(t) = floor(epoch(t) / game_day_seconds)
    v_from := to_timestamp(((v_today - v_span + 1) * v_gds)::double precision);
$h$,
$h$    -- the EXACT day boundary: public.real_day(t) = floor(epoch(t) / 86400)
    v_from := to_timestamp(((v_today - v_span + 1) * 86400)::double precision);
$h$),
  ('world.report(text)',
$h$           world.game_day(l.created_at) as day
$h$,
$h$           public.real_day(l.created_at) as day
$h$),
  ('world.report(text)',
$h$    select d as game_day,
$h$,
$h$    select d as day,
$h$),
  ('world.report(text)',
$h$           'game_day', v_today,
           'total', coalesce((select sum(s.ducats) from section_json s), 0),
$h$,
$h$           'day', v_today,
           'total', coalesce((select sum(s.ducats) from section_json s), 0),
$h$),
  ('world.report(text)',
$h$                                                 'day', world.game_day(p.departed_at),
$h$,
$h$                                                 'day', public.real_day(p.departed_at),
$h$),
  ('world.report(text)',
$h$             (select jsonb_agg(jsonb_build_object('game_day', a.game_day, 'net', a.net) order by a.game_day)
$h$,
$h$             (select jsonb_agg(jsonb_build_object('day', a.day, 'net', a.net) order by a.day)
$h$),
  -- what you were paid
  ('world.holdings()',
$h$-- leaf), and the dividends collected (public.ledger, kind DIVIDEND) today and in the last full game day
-- (world.game_day). Reads; writes nothing.
$h$,
$h$-- leaf), and the dividends collected (public.ledger, kind DIVIDEND) today and yesterday, real UTC days
-- (0317: public.real_day). Reads; writes nothing.
$h$),
  ('world.holdings()',
$h$  v_today  int := world.game_day();
$h$,
$h$  v_today  int := public.real_day(now());
$h$),
  ('world.holdings()',
$h$                'today', coalesce(sum(l.ducats_delta) filter (where world.game_day(l.created_at) = v_today), 0),
                'yesterday', coalesce(sum(l.ducats_delta) filter (where world.game_day(l.created_at) = v_today - 1), 0))
$h$,
$h$                'today', coalesce(sum(l.ducats_delta) filter (where public.real_day(l.created_at) = v_today), 0),
                'yesterday', coalesce(sum(l.ducats_delta) filter (where public.real_day(l.created_at) = v_today - 1), 0))
$h$),
  ('world.holdings()',
$h$                and l.created_at > now() - interval '1 day'),
    'game_day', v_today);
$h$,
$h$                and l.created_at >= to_timestamp(((v_today - 1) * 86400)::double precision)),
    'day', v_today);
$h$),
  -- the hall's day
  ('world.town_hall(uuid)',
$h$-- 0122: one harbour's purse and its last FULL game-day's book, by kind. 0123: the works (level,
$h$,
$h$-- 0122: one harbour's purse and its last 24 hours' book, by kind (0317). 0123: the works (level,
$h$),
  ('world.town_hall(uuid)',
$h$  t        public.port_treasury%rowtype;
  v_day    int := world.game_day() - 1;
$h$,
$h$  t        public.port_treasury%rowtype;
$h$),
  ('world.town_hall(uuid)',
$h$    'day', jsonb_build_object(
       'game_day', v_day,
       'in',  coalesce((select jsonb_object_agg(d.kind, d.ducats order by d.kind) from public.treasury_daybook d
                         where d.port_id = p_port and d.game_day = v_day and d.ducats > 0), '{}'::jsonb),
       'out', coalesce((select jsonb_object_agg(d.kind, -d.ducats order by d.kind) from public.treasury_daybook d
                         where d.port_id = p_port and d.game_day = v_day and d.ducats < 0), '{}'::jsonb)),
$h$,
$h$    -- 0317: the last 24 hours as of the last count: public.stats_fold_day keeps them on the city's newest row, one primary-key read. The daybook keeps 30 minutes.
    'day', (select jsonb_build_object(
       'in',  coalesce(jsonb_object_agg(e.key, e.value::bigint) filter (where e.value::bigint > 0), '{}'::jsonb),
       'out', coalesce(jsonb_object_agg(e.key, -e.value::bigint) filter (where e.value::bigint < 0), '{}'::jsonb))
       from jsonb_each_text(coalesce((select c.day -> 'kinds' from public.stats_city c where c.port_id = p_port order by c.slot desc limit 1), '{}'::jsonb)) e),
$h$),
  -- the market's day
  ('world.price_why(uuid,uuid)',
$h$    -- 0190: what changed hands here today (public.traded_today — the daily-cap record, bought + sold)
    'volume', (select jsonb_build_object('game_day', world.game_day(), 'units', v.units, 'houses', v.houses)
                 from public.traded_today(p_port, p_good) v),
$h$,
$h$    -- 0190: what changed hands here in the last 24 hours (0317: public.traded_today), bought + sold
    'volume', jsonb_build_object('units', public.traded_today(p_port, p_good)),
$h$),
  -- a bargain lasts a real day
  ('world.haggle_state(uuid,uuid)',
$h$  v_day    int := world.game_day();
$h$,
$h$  v_day    int := public.real_day(now());
$h$),
  ('world.haggle_state(uuid,uuid)',
$h$     and h.good_id = p_good and h.game_day = v_day;
$h$,
$h$     and h.good_id = p_good and h.day = v_day;
$h$),
  ('world.haggle_state(uuid,uuid)',
$h$    'game_day', v_day,
$h$,
$h$    'day', v_day,
$h$),
  ('public.haggle_concession(uuid,uuid,uuid)',
$h$                      and h.good_id = p_good and h.game_day = world.game_day()), 0)
$h$,
$h$                      and h.good_id = p_good and h.day = public.real_day(now())), 0)
$h$),
  ('public.haggle_odds(uuid,uuid,uuid,uuid)',
$h$     and h.good_id = p_good and h.game_day = world.game_day();
$h$,
$h$     and h.good_id = p_good and h.day = public.real_day(now());
$h$),
  ('cmd.do_buy(uuid,jsonb)',
$h$       and good_id = g.id and game_day = world.game_day();
$h$,
$h$       and good_id = g.id and day = public.real_day(now());
$h$),
  ('cmd.do_sell(uuid,jsonb)',
$h$       and good_id = g.id and game_day = world.game_day();
$h$,
$h$       and good_id = g.id and day = public.real_day(now());
$h$),
  ('cmd.haggle(uuid,uuid,text)',
$h$  v_day     int  := world.game_day();
$h$,
$h$  v_day     int  := public.real_day(now());
$h$),
  ('cmd.haggle(uuid,uuid,text)',
$h$     and h.good_id = g.id and h.game_day = v_day;
$h$,
$h$     and h.good_id = g.id and h.day = v_day;
$h$),
  ('cmd.haggle(uuid,uuid,text)',
$h$  insert into public.haggle_daily (player_id, port_id, good_id, game_day, attempts, wins, concession, last_side)
$h$,
$h$  insert into public.haggle_daily (player_id, port_id, good_id, day, attempts, wins, concession, last_side)
$h$),
  ('cmd.haggle(uuid,uuid,text)',
$h$  on conflict (player_id, port_id, good_id, game_day) do update
$h$,
$h$  on conflict (player_id, port_id, good_id, day) do update
$h$),
  ('cmd.haggle(uuid,uuid,text)',
$h$     where player_id = v_player and port_id = f.port_id and good_id = g.id and game_day = v_day;
$h$,
$h$     where player_id = v_player and port_id = f.port_id and good_id = g.id and day = v_day;
$h$);

  create temp table bodies_0317 (fn text primary key, def0 text not null) on commit drop;
  insert into bodies_0317
  select x, replace(pg_get_functiondef(x::regprocedure), E'\r', '') from unnest(c_fns) x;

  foreach v_fn in array c_fns loop
    select b.def0 into v_def from bodies_0317 b where b.fn = v_fn;
    for v_h in select * from hunks_0317 h where h.fn = v_fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, v_h.old, ''))) / length(v_h.old);
      if v_n <> 1 then
        raise exception '0317 self-assert FAIL: hunk % of % occurs % time(s), not once: the live body is not what this file was cut against', v_h.ord, v_fn, v_n;
      end if;
      v_def := replace(v_def, v_h.old, v_h.new);
    end loop;
    execute v_def;
  end loop;

  -- ── 4. THE SELF-ASSERT: hunks, grants, nothing else moved ──
  foreach v_fn in array c_fns loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0317 h where h.fn = v_fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_h.new, ''))) / length(v_h.new) <> 1 then
        raise exception '0317 self-assert FAIL: hunk % is not in the new body of % exactly once', v_h.ord, v_fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> (select b.def0 from bodies_0317 b where b.fn = v_fn) then
      raise exception '0317 self-assert FAIL: % does not reverse to its pre-image', v_fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_fns) x))) <> v_meta_before then
    raise exception '0317 self-assert FAIL: a body''s grants or settings moved';
  end if;
  if has_function_privilege('anon', 'public.traded_today(uuid,uuid)', 'execute') or has_function_privilege('authenticated', 'public.traded_today(uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'public.buff_season_of(timestamp with time zone,numeric)', 'execute') or has_function_privilege('authenticated', 'public.buff_season_of(timestamp with time zone,numeric)', 'execute') then
    raise exception '0317 self-assert FAIL: a client can reach a leaf';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_fns) x))
         and p.oid not in ('public.traded_today(uuid,uuid)'::regprocedure, 'public.buff_season_of(timestamp with time zone,numeric)'::regprocedure)) <> v_fn_before then
    raise exception '0317 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) <> v_cfg_before then
    raise exception '0317 self-assert FAIL: a world_config row moved';
  end if;
  if exists (select 1 from public.buff_kinds k where k.code = 'FAIR' and (k.duration_seconds <> 11520 or k.season_seconds <> 86400)) then
    raise exception '0317 self-assert FAIL: a fair is not 3.2 hours in a day';
  end if;
  v_def := (select string_agg(replace(pg_get_functiondef(p.oid), E'\r', ''), '') from pg_proc p where p.oid in
             ('world.report(text)'::regprocedure, 'world.holdings()'::regprocedure, 'world.haggle_state(uuid,uuid)'::regprocedure, 'cmd.haggle(uuid,uuid,text)'::regprocedure,
              'public.haggle_concession(uuid,uuid,uuid)'::regprocedure, 'public.haggle_odds(uuid,uuid,uuid,uuid)'::regprocedure, 'public.tick_buff_calendar(timestamp with time zone)'::regprocedure,
              'public.buff_season_of(timestamp with time zone,numeric)'::regprocedure, 'world.buffs(uuid)'::regprocedure));
  if position('game_day' in v_def) > 0 then
    raise exception '0317 self-assert FAIL: a body that means a real day still names the game clock';
  end if;

  -- ── 5. THE SELF-ASSERT: a probe harbour, a probe house, every row rolled back ──
  begin
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind)
    select 'QZE', 'Probe QZE', t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, 'HARBOUR'
      from (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t
    returning id into v_port;
    v_good := (select g.id from public.goods g order by g.code limit 1);
    v_nat := (select g.nation_id from public.great_powers g order by g.nation_id limit 1);
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0317', v_nat, 0, true) returning id into v_p;

    -- a bargain struck today holds at any clock, and a season is a real day at any clock
    insert into public.haggle_daily (player_id, port_id, good_id, day, attempts, wins, concession, last_side)
    values (v_p, v_port, v_good, public.real_day(now()), 1, 1, 0.25, 'buy');
    foreach v_gds in array array[60, 2880, 7] loop
      update public.world_config set value = to_jsonb(v_gds) where key = 'game_day_seconds';
      if public.haggle_concession(v_p, v_port, v_good) <> 0.25 then
        raise exception '0317 self-assert FAIL: the clock moved a bargain at % s', v_gds;
      end if;
      if public.buff_season_of(now(), 86400) <> public.real_day(now()) then
        raise exception '0317 self-assert FAIL: the clock moved a season at % s', v_gds;
      end if;
    end loop;
    update public.haggle_daily set day = public.real_day(now()) - 1 where player_id = v_p;
    if public.haggle_concession(v_p, v_port, v_good) <> 0 then
      raise exception '0317 self-assert FAIL: a bargain outlived its day';
    end if;

    -- the volume is 24 hours: two counts inside, one outside
    insert into public.stats_city_good (port_id, good_id, slot, at, sold, bought, sold_ducats, bought_ducats) values
      (v_port, v_good, 9100000000001, now() - interval '1 hour', 7, 4, 0, 0),
      (v_port, v_good, 9100000000002, now() - interval '23 hours', 20, 0, 0, 0),
      (v_port, v_good, 9100000000003, now() - interval '25 hours', 1000, 1000, 0, 0);
    if public.traded_today(v_port, v_good) <> 31 then
      raise exception '0317 self-assert FAIL: the volume of 24 hours is %, not 31', public.traded_today(v_port, v_good);
    end if;

    raise exception using errcode = 'ZX317', message = 'rolled back';
  exception when sqlstate 'ZX317' then
    null;
  end;

  if extract(epoch from clock_timestamp() - v_t0) > 45 then
    raise exception '0317 self-assert FAIL: the file took more than 45 s';
  end if;
  raise notice '0317 self-assert ok: the Report, the hall, the market, a bargain and a fair count real days; the crown''s tax is whole; nothing else moved (% ms)',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
