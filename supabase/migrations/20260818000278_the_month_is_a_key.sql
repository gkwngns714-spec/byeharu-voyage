-- 0278 — THE MONTH IS A KEY: the city's giving and a route's laps are keyed by the calendar month, and the
--        MONEY IS ALL-TIME (the board never resets; the History tab folds the months)
--
-- OWNER (2026-10-30): rewrite 0275's weekly rollover into a MONTHLY one, with the money all-time. The design
-- decisions are the owner's and are not altered here:
--   1. PERIOD = CALENDAR MONTH. A `month_anchor` knob = 2026-10-01T00:00:00Z (a first-of-month); October 2026
--      is month 0. `world.month_of(p_at)` is the calendar-month number since that anchor, and
--      `world.month_start(p_month)` is the instant a month begins. Both are STABLE, SECURITY DEFINER and
--      server-only, and both read the calendar in UTC — the anchor's own zone — so a session's TimeZone
--      cannot move a month (the local gate runs Asia/Seoul; Supabase runs UTC; the answer must not differ).
--   2. 0275's `world.week_of`, `world.week_start` and the `week_anchor` knob are DROPPED — superseded, not kept
--      beside the new pair (one authority per concept).
--   3. The books are RENAMED, not recreated: `public.city_week_book` -> `public.city_month_book` (column
--      `week` -> `month`), `public.route_week_laps` -> `public.route_month_laps` (column `week` -> `month`).
--      PKs, indexes, RLS, autovacuum settings and the revoked ACL ride along with the table. NO RE-STAMP: at
--      authoring every existing row is week 0 (the week anchor was 2026-10-26) and month 0 (the month anchor is
--      2026-10-01); the self-assert REFUSES if any row reads other than 0, so a deploy after the week rolls
--      fails loudly instead of silently filing last week's giving under a month. That is the safe failure.
--   4. MONEY IS ALL-TIME. The Town Hall's investors board sums city_month_book over ALL months (no month
--      filter); `route_earnings` serves one all-time `total {laps, net, sold, bought, supplies, repairs,
--      wages}` summed over ALL months and `laps_done` is the old all-time max(lap_no) figure. No `week`, no
--      `last_week`, no `laps_done_all`.
--   5. `world.city_history(p_port, p_months)` serves months: the current month and the past eight, newest
--      first, each {month, starts, ends, current, total, investors:[{name, merchant, invested, donated,
--      total}]}. The month, the dates and the totals are served; the client computes none of them.
--
-- SUPERSEDE / RE-CUTS (supabase/migrations/README.md:43-48). This file re-cuts SIX live functions by hunks
-- sliced from their CURRENT (post-0275) bodies; each hunk asserts it occurs exactly once and reverses to its
-- pre-image, and ACL / volatility / definer / config must be unmoved:
--   * public.pay_city(uuid,uuid,text,bigint,uuid) — the SHARE/DONATION branch calls the renamed writer
--     public.city_month_post (the month book's ONE writer) in place of city_week_post.
--   * world.town_hall(uuid) — `investors` sums public.city_month_book over ALL months: invested = Σ SHARE,
--     donated = Σ DONATION, total = Σ all, ordered total desc, company_name, capped by
--     town_hall_investors_max. Shares, works, influence, dues and gifts are untouched.
--   * cmd.standing_route_close_lap(uuid,timestamptz) — the closed lap's figures upsert into this MONTH's
--     route_month_laps row, stamped world.month_of(p_now) (the book's ONE writer).
--   * public.route_earnings(uuid) — `laps_done` returns to the all-time max(lap_no) form; `week`, `last_week`
--     and `laps_done_all` are replaced by ONE all-time `total` object summed over every month (zeros when
--     none).
--   * world.standing_routes() — the served `earnings` object is public.route_earnings composed, never
--     recomputed; its shape is now all-time (the key is still `earnings`).
--   * public.client_rpc_entry_points() — the city_history row STAYS; month_of / month_start / city_month_post
--     are server-only and are NOT registered.
--
-- IT IS A NO-OP WHEN THE NEW INPUT IS ABSENT. pay_city: a kind other than SHARE/DONATION posts nothing, as
-- before. town_hall: an empty month book reads an empty board. close_lap: a route with no open lap returns
-- before the hunk. route_earnings: a route with no month rows reads total {0...}. city_history: a harbour
-- with no giving serves nine empty months.
--
-- WHAT IS NOT PROVEN (said plainly). The books keep every month, forever; compaction is not needed for years
-- (a few thousand rows a month, and every read is by index / primary key). The deploy does not backfill the
-- week book into months: 0275's week numbers are NOT calendar months, so copying them would invent a history;
-- the self-assert instead proves every pre-existing row is week 0 = month 0, which is the only case in which
-- no copy is needed.
--
-- PROD CHECKS (before the push; read-only; in the PR body): pg_get_functiondef of the six live bodies contains
-- the pre-image hunks once each (the md5s are the local chain's); `select count(*) from public.city_week_book`
-- and `select count(*) from public.route_week_laps`, and both are 0 rows in every month but 0
-- (`select count(*) from public.city_week_book where week <> 0`, same for route_week_laps); world.week_of /
-- world.week_start / city_week_post exist and the week_anchor knob is 2026-10-26T00:00:00Z. AFTER THE DEPLOY:
-- the first INVESTED / DONATED lands in city_month_book under world.month_of(now()); the Town Hall board
-- shows all-time giving; the History tab folds the current month open; the route fold prints the all-time
-- total.
--
-- ROLLBACK (forward): reverse the six hunks (the re-cut loop's own reversal, old and new swapped); recreate
-- world.city_history with p_weeks; drop world.month_of, world.month_start, public.city_month_post; recreate
-- public.city_week_post and world.week_of / world.week_start from 0275; rename the tables and columns back;
-- restore the week_anchor knob. The books are append-only and read by nothing after the readers reverse, so
-- they may stay.
--
-- VERSION: 0278 (prod head 0276 at authoring; 0277 is another in-flight slice and is applied before this one
-- in number order. If 0277 re-cuts a body this file cuts against, the hunk self-asserts fail loudly at apply,
-- which is the safe failure).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.pay_city(uuid,uuid,text,bigint,uuid)') is null
     or to_regprocedure('world.town_hall(uuid)') is null
     or to_regprocedure('cmd.standing_route_close_lap(uuid,timestamptz)') is null
     or to_regprocedure('public.route_earnings(uuid)') is null
     or to_regprocedure('world.standing_routes()') is null
     or to_regprocedure('public.client_rpc_entry_points()') is null then
    raise exception '0278 refuses: 0122/0123/0092/0097/0083 are not in this world';
  end if;
  if to_regclass('public.city_month_book') is not null then
    raise exception '0278 refuses: public.city_month_book already exists — this has been applied once';
  end if;
  -- It renames 0275's books and drops 0275's clock: both must be here, or this is not the world it was cut
  -- against.
  if to_regclass('public.city_week_book') is null
     or to_regclass('public.route_week_laps') is null
     or to_regprocedure('world.week_of(timestamptz)') is null
     or to_regprocedure('world.week_start(bigint)') is null
     or to_regprocedure('public.city_week_post(uuid,uuid,text,bigint)') is null then
    raise exception '0278 refuses: 0275''s week books or week clock are not in this world';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0278(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0278 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.pay_city(uuid,uuid,text,bigint,uuid)'),
               ('world.town_hall(uuid)'),
               ('cmd.standing_route_close_lap(uuid,timestamptz)'),
               ('public.route_earnings(uuid)'),
               ('world.standing_routes()'),
               ('public.client_rpc_entry_points()')) f(fn);

-- EVERY function in the four schemas except the ones this file touches: one md5 over the lot. The exclusion
-- is BY NAME because two of these names are DROPPED and three are MINTED — a `not in (to_regprocedure(...))`
-- over a function that does not exist would exclude every row through NULL.
create temp table before_0278 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and (n.nspname, p.proname) not in (
                 ('public', 'pay_city'), ('world', 'town_hall'), ('cmd', 'standing_route_close_lap'),
                 ('public', 'route_earnings'), ('world', 'standing_routes'),
                 ('public', 'client_rpc_entry_points'), ('world', 'city_history'),
                 ('world', 'week_of'), ('world', 'week_start'), ('public', 'city_week_post'),
                 ('world', 'month_of'), ('world', 'month_start'), ('public', 'city_month_post'))) as others_md5;

-- ── 1. THE MONTH: the knob and the one pair of readings ────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('month_anchor', to_jsonb('2026-10-01T00:00:00Z'::text),
   '0278: the first of the month the month numbers count from — a calendar month, read by world.month_of '
   'and world.month_start ALONE (the one month authority; 2026-10-01 is month 0, October 2026).')
on conflict (key) do nothing;

create or replace function world.month_of(p_at timestamptz default now())
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
set timezone = 'UTC'
as $$
  -- 0278: THE one reading of "which calendar month is it" — (year * 12 + month) since the month_anchor's
  -- own month. world.game_day's sibling: the same kind of thing, one clock. The client never computes a
  -- month; it prints the month, starts and ends served. The calendar is read in UTC, the anchor's own
  -- zone: `extract` otherwise follows the session's TimeZone, and a month that moved with a viewer's
  -- clock would be a second month authority.
  select ((extract(year from p_at)::int * 12 + extract(month from p_at)::int)
          - (2026 * 12 + 10))::bigint
$$;
comment on function world.month_of(timestamptz) is
  '0278: the calendar-month number of an instant, counted from the month_anchor knob — THE one reading of '
  'the current month. world.game_day''s sibling. Server-only.';
revoke all on function world.month_of(timestamptz) from public, anon, authenticated;

create or replace function world.month_start(p_month bigint)
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
set timezone = 'UTC'
as $$
  -- 0278: the instant a month begins — month_anchor + p_month calendar months, read in UTC (the anchor's
  -- own zone) so a session's TimeZone cannot move it. The pair (month_of, month_start) is the one month
  -- authority; a face prints starts and ends, never computes them.
  select (public.wc_text('month_anchor'))::timestamptz + p_month * interval '1 month'
$$;
comment on function world.month_start(bigint) is
  '0278: the instant the month p_month begins — world.month_of''s pair, the one month authority '
  '(month_anchor + p_month months). Server-only.';
revoke all on function world.month_start(bigint) from public, anon, authenticated;

-- ── 2. THE BOOKS, RENAMED: week -> month (structure, RLS, ACL and autovacuum ride along) ───────
alter table public.city_week_book rename to city_month_book;
alter table public.city_month_book rename column week to month;
alter index public.city_week_book_port_week rename to city_month_book_port_month;
alter table public.city_month_book rename constraint city_week_book_pkey to city_month_book_pkey;
comment on table public.city_month_book is
  '0278: the coin a company gave INTO a city — an investment (SHARE) or a gift (DONATION) — under the '
  'calendar month it was given in (world.month_of). Written by public.city_month_post alone, from '
  'public.pay_city''s SHARE/DONATION branch. The month is a KEY: nothing is ever deleted, the History tab '
  'reads every month, and the Town Hall board sums them ALL (money stays). Append-only.';

alter table public.route_week_laps rename to route_month_laps;
alter table public.route_month_laps rename column week to month;
alter index public.route_week_laps_player_week rename to route_month_laps_player_month;
alter table public.route_month_laps rename constraint route_week_laps_pkey to route_month_laps_pkey;
comment on table public.route_month_laps is
  '0278: a route''s closed laps and their figures, under the calendar month they closed in '
  '(world.month_of(p_now), written by cmd.standing_route_close_lap alone after each lap closes). The month '
  'is a KEY: public.route_earnings sums EVERY month here (all-time), and the table keeps every month. The '
  'route''s lap rows stay bounded by standing_route_lap_keep. route_id has no FK on purpose: a deleted route '
  'keeps its history. Append-only.';

-- ── 3. THE CITY BOOK'S ONE WRITER (renamed from public.city_week_post) ─────────────────────────
create or replace function public.city_month_post(p_player uuid, p_port uuid, p_kind text, p_amount bigint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0278: THE one writer of public.city_month_book — called by public.pay_city alone, from the same
-- SHARE / DONATION branch 0144 gave public.influence_post. One row per (port, month, giver, kind); a
-- second giving in the same month ADDS, never duplicates. The month key is world.month_of's alone —
-- this body computes no month.
begin
  insert into public.city_month_book (port_id, month, player_id, kind, ducats, gifts, updated_at)
  values (p_port, world.month_of(), p_player, p_kind, coalesce(p_amount, 0),
          case when p_kind = 'DONATION' then 1 else 0 end, now())
  on conflict (port_id, month, player_id, kind) do update
     set ducats = public.city_month_book.ducats + excluded.ducats,
         gifts = public.city_month_book.gifts + excluded.gifts,
         updated_at = now();
end $$;
comment on function public.city_month_post(uuid, uuid, text, bigint) is
  '0278: the one writer of public.city_month_book — the coin a company gives INTO a city, under the month '
  'it was given in. Called by public.pay_city alone for SHARE and DONATION. Server-only.';
revoke all on function public.city_month_post(uuid, uuid, text, bigint) from public, anon, authenticated;

-- ── 4. THE HISTORY READ: the city's giving by month (recreated to rename p_weeks -> p_months) ──
-- CREATE OR REPLACE cannot rename an input parameter, so the 0275 function is dropped; its one client grant
-- is restored below. It is not in the six re-cut bodies (this file owns its whole body).
drop function world.city_history(uuid, int);

create function world.city_history(p_port uuid, p_months int default 8)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0278: the city's giving by month — the current month and the past min(p_months, 8), newest first, each
-- with its starts / ends / total and its givers {name, merchant, invested, donated, total} (total desc,
-- name; capped by town_hall_investors_max, the Town Hall's own cap). The table keeps every month; this
-- door serves nine. Months are world.month_of's — this body computes none. Authenticated only, like the
-- Town Hall; no tier gate (the investor board is not gated).
declare
  v_month bigint := world.month_of();
  v_m     bigint;
  v_port  public.ports%rowtype;
begin
  select x.* into v_port from public.ports x where x.id = p_port;
  if v_port.id is null or v_port.kind <> 'HARBOUR' then
    raise exception 'E_NOT_FOUND: there is no such harbour' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'port', v_port.code,
    'month', v_month,
    'months', (select jsonb_agg(jsonb_build_object(
               'month', m,
               'starts', world.month_start(m),
               'ends', world.month_start(m + 1),
               'current', m = v_month,
               'total', coalesce((select sum(b.ducats) from public.city_month_book b
                                   where b.port_id = p_port and b.month = m), 0),
               'investors', coalesce((select jsonb_agg(jsonb_build_object(
                     'name', x.company_name, 'merchant', x.is_npc,
                     'invested', x.invested, 'donated', x.donated, 'total', x.total)
                     order by x.total desc, x.company_name)
                     from (select pl.company_name, pl.is_npc, b.invested, b.donated, b.total
                             from (select b2.player_id,
                                          coalesce(sum(b2.ducats) filter (where b2.kind = 'SHARE'), 0)    as invested,
                                          coalesce(sum(b2.ducats) filter (where b2.kind = 'DONATION'), 0) as donated,
                                          coalesce(sum(b2.ducats), 0)                                     as total
                                     from public.city_month_book b2
                                    where b2.port_id = p_port and b2.month = m
                                    group by b2.player_id) b
                             join public.players pl on pl.id = b.player_id
                            order by b.total desc, pl.company_name
                            limit public.wc_int('town_hall_investors_max')) x), '[]'::jsonb))
               order by m desc)
             from generate_series(v_month, v_month - least(greatest(coalesce(p_months, 8), 0), 8), -1) m)
  );
end $$;
comment on function world.city_history(uuid, int) is
  '0278: one harbour''s giving by month — the current month and the past eight, newest first, each with '
  'its dates, total and givers. The History tab''s one read. Authenticated only.';
revoke all on function world.city_history(uuid, int) from public, anon;
grant execute on function world.city_history(uuid, int) to authenticated;

-- ── 5. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0278 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0278 (fn, n, old, new) values
-- ── public.pay_city: the SHARE/DONATION branch calls the renamed month book's one writer ──
('public.pay_city(uuid,uuid,text,bigint,uuid)', 1,
$h$  if p_kind in ('SHARE', 'DONATION') then
    perform public.influence_post(p_player, p_port, p_amount, p_kind);
    -- 0275 (docs/WEEKLY_ROLLOVER.md §3): the same coin also lands in THIS WEEK's giving book — the
    -- board the Town Hall and the History tab read. The week is world.week_of's alone.
    perform public.city_week_post(p_player, p_port, p_kind, p_amount);
  end if;
  return v_after;$h$,
$h$  if p_kind in ('SHARE', 'DONATION') then
    perform public.influence_post(p_player, p_port, p_amount, p_kind);
    -- 0278 (the month): the same coin also lands in THIS MONTH's giving book — the board the Town
    -- Hall and the History tab read. The month is world.month_of's alone, and the money is all-time.
    perform public.city_month_post(p_player, p_port, p_kind, p_amount);
  end if;
  return v_after;$h$),
-- ── world.town_hall: the investors board sums the month book over ALL months (money stays) ──
('world.town_hall(uuid)', 1,
$h$    -- 0275 (docs/WEEKLY_ROLLOVER.md): the board is THIS WEEK's giving (city_week_book) — the owner's
    -- weekly reset. Shares and coupons are money and stay on the register (`you.holdings`).
    'investors', coalesce((select jsonb_agg(jsonb_build_object(
                    'name', x.company_name, 'merchant', x.is_npc,
                    'invested', x.invested, 'donated', x.donated, 'total', x.total)
                    order by x.total desc, x.company_name)
                    from (select pl.company_name, pl.is_npc, b.invested, b.donated, b.total
                            from (select b2.player_id,
                                         coalesce(sum(b2.ducats) filter (where b2.kind = 'SHARE'), 0)    as invested,
                                         coalesce(sum(b2.ducats) filter (where b2.kind = 'DONATION'), 0) as donated,
                                         coalesce(sum(b2.ducats), 0)                                     as total
                                    from public.city_week_book b2
                                   where b2.port_id = p_port and b2.week = world.week_of()
                                   group by b2.player_id) b
                            join public.players pl on pl.id = b.player_id
                           order by b.total desc, pl.company_name
                           limit public.wc_int('town_hall_investors_max')) x), '[]'::jsonb),$h$,
$h$    -- 0278 (the month): the board is the city's giving over ALL time (city_month_book, every month) —
    -- money stays. Shares and coupons stay on the register (`you.holdings`) as well.
    'investors', coalesce((select jsonb_agg(jsonb_build_object(
                    'name', x.company_name, 'merchant', x.is_npc,
                    'invested', x.invested, 'donated', x.donated, 'total', x.total)
                    order by x.total desc, x.company_name)
                    from (select pl.company_name, pl.is_npc, b.invested, b.donated, b.total
                            from (select b2.player_id,
                                         coalesce(sum(b2.ducats) filter (where b2.kind = 'SHARE'), 0)    as invested,
                                         coalesce(sum(b2.ducats) filter (where b2.kind = 'DONATION'), 0) as donated,
                                         coalesce(sum(b2.ducats), 0)                                     as total
                                    from public.city_month_book b2
                                   where b2.port_id = p_port
                                   group by b2.player_id) b
                            join public.players pl on pl.id = b.player_id
                           order by b.total desc, pl.company_name
                           limit public.wc_int('town_hall_investors_max')) x), '[]'::jsonb),$h$),
-- ── cmd.standing_route_close_lap: the closed lap's figures land in this MONTH's book ──
('cmd.standing_route_close_lap(uuid,timestamptz)', 1,
$h$  -- 0275 (docs/WEEKLY_ROLLOVER.md §3): the lap's figures land in THIS WEEK's book — one row per route
  -- and week, keyed by world.week_of(p_now) alone (the one week authority). The prune below forgets
  -- old laps by count; the book keeps their week by key, so the live counters are the week's own.
  insert into public.route_week_laps (route_id, week, player_id, route_name, laps, sold, bought,
                                      supplies, repairs, wages, net, updated_at)
  values (p_route, world.week_of(p_now), sr.player_id, sr.name, 1, l.sold, l.bought, l.supplies,
          l.repairs, l.wages, l.net, p_now)
  on conflict (route_id, week) do update
     set laps = public.route_week_laps.laps + 1,
         sold = public.route_week_laps.sold + excluded.sold,
         bought = public.route_week_laps.bought + excluded.bought,
         supplies = public.route_week_laps.supplies + excluded.supplies,
         repairs = public.route_week_laps.repairs + excluded.repairs,
         wages = public.route_week_laps.wages + excluded.wages,
         net = public.route_week_laps.net + excluded.net,
         updated_at = p_now;$h$,
$h$  -- 0278 (the month): the lap's figures land in THIS MONTH's book — one row per route and month,
  -- keyed by world.month_of(p_now) alone (the one month authority). The prune below forgets old laps
  -- by count; the book keeps their month by key, so the all-time counters read every month.
  insert into public.route_month_laps (route_id, month, player_id, route_name, laps, sold, bought,
                                       supplies, repairs, wages, net, updated_at)
  values (p_route, world.month_of(p_now), sr.player_id, sr.name, 1, l.sold, l.bought, l.supplies,
          l.repairs, l.wages, l.net, p_now)
  on conflict (route_id, month) do update
     set laps = public.route_month_laps.laps + 1,
         sold = public.route_month_laps.sold + excluded.sold,
         bought = public.route_month_laps.bought + excluded.bought,
         supplies = public.route_month_laps.supplies + excluded.supplies,
         repairs = public.route_month_laps.repairs + excluded.repairs,
         wages = public.route_month_laps.wages + excluded.wages,
         net = public.route_month_laps.net + excluded.net,
         updated_at = p_now;$h$),
-- ── public.route_earnings: the all-time counters ride the one earnings reading ──
('public.route_earnings(uuid)', 1,
$h$    -- 0275 (docs/WEEKLY_ROLLOVER.md §5 W2): laps_done is THIS WEEK's count (the book's row for
    -- world.week_of()); laps_done_all keeps the old all-time figure for one release, then goes.
    'laps_done', coalesce((select rwl.laps from public.route_week_laps rwl
                            where rwl.route_id = p_route and rwl.week = world.week_of()), 0),
    'laps_done_all', coalesce((select max(x.lap_no) from public.standing_route_laps x
                            where x.route_id = p_route and x.closed_at is not null), 0),
    'week', coalesce((select jsonb_build_object(
                'laps', rwl.laps, 'net', rwl.net, 'sold', rwl.sold, 'bought', rwl.bought,
                'supplies', rwl.supplies, 'repairs', rwl.repairs, 'wages', rwl.wages)
               from public.route_week_laps rwl
              where rwl.route_id = p_route and rwl.week = world.week_of()),
             jsonb_build_object('laps', 0, 'net', 0, 'sold', 0, 'bought', 0,
                                'supplies', 0, 'repairs', 0, 'wages', 0)),
    'last_week', (select case when rwl.week is null then null
                              else jsonb_build_object('laps', rwl.laps, 'net', rwl.net) end
                    from public.route_week_laps rwl
                   where rwl.route_id = p_route and rwl.week = world.week_of() - 1))$h$,
$h$    -- 0278 (the month): money and laps are all-time. `laps_done` is every closed lap ever; `total`
    -- sums every month of the lap book (zeros when none). No week keys, no last week.
    'laps_done', coalesce((select max(x.lap_no) from public.standing_route_laps x
                            where x.route_id = p_route and x.closed_at is not null), 0),
    'total', (select jsonb_build_object(
                'laps', coalesce(sum(rwl.laps), 0), 'net', coalesce(sum(rwl.net), 0),
                'sold', coalesce(sum(rwl.sold), 0), 'bought', coalesce(sum(rwl.bought), 0),
                'supplies', coalesce(sum(rwl.supplies), 0), 'repairs', coalesce(sum(rwl.repairs), 0),
                'wages', coalesce(sum(rwl.wages), 0))
               from public.route_month_laps rwl
              where rwl.route_id = p_route))$h$),
-- ── world.standing_routes: each route's served earnings is now the all-time shape ──
('world.standing_routes()', 1,
$h$        -- 0275 (docs/WEEKLY_ROLLOVER.md §5 W4): the week counters ride the one earnings reading —
        -- composed here, never recomputed; the fold and the tray print week / last_week from it.
        'earnings', public.route_earnings(sr.id)$h$,
$h$        -- 0278 (the month): the all-time counters ride the one earnings reading — composed here,
        -- never recomputed; the fold and the tray print laps_done / total from it.
        'earnings', public.route_earnings(sr.id)$h$),
-- ── public.client_rpc_entry_points: the History tab's one read stays; the month clock does not ──
('public.client_rpc_entry_points()', 1,
$h$      -- 0275 (docs/WEEKLY_ROLLOVER.md §4): the city's giving by week — the History tab's read.
      ('world',       'city_history',          'uuid, int')$h$,
$h$      -- 0278 (the month): the city's giving by month — the History tab's read. The month clock
      -- (world.month_of / world.month_start) and the book's writer (public.city_month_post) are
      -- server-only and are NOT registered.
      ('world',       'city_history',          'uuid, int')$h$);

-- THE HUNKS, each once, then the new bodies
do $$
declare
  d   record;
  h   record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0278 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0278 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0278(v_def, h.old);
      if v_n <> 1 then
        raise exception '0278 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 6. THE WEEK IS GONE: its clock, its writer and its knob ────────────────────────────────────
drop function world.week_of(timestamptz);
drop function world.week_start(bigint);
drop function public.city_week_post(uuid, uuid, text, bigint);
delete from public.world_config where key = 'week_anchor';

-- ── 7. THE PROBES' TOOLS ───────────────────────────────────────────────────────────────────────
-- One probe city: a harbour whose works offer a stake the probe can buy AND that has the fewest month-book
-- rows, so the probe's rows are served under every cap.
create or replace function pg_temp.probe_city_0278()
returns jsonb
language plpgsql
as $$
declare
  v_city  uuid;
  v_kind  text;
  v_offer int;
begin
  select w.port_id, w.kind,
         least(public.city_offered(w.port_id, w.kind), 10)
    into v_city, v_kind, v_offer
    from public.city_works w join public.ports p on p.id = w.port_id and p.kind = 'HARBOUR'
   where public.city_offered(w.port_id, w.kind) >= 1
     and public.works_share_price(w.level) * least(public.city_offered(w.port_id, w.kind), 10)
         >= public.wc_int('invest_min_ducats')
   order by (select count(*) from public.city_month_book b where b.port_id = w.port_id), p.code, w.kind
   limit 1;
  if v_city is null then
    raise exception '0278 self-assert FAIL: no harbour offers a stake to invest in';
  end if;
  return jsonb_build_object('city', v_city, 'kind', v_kind, 'offer', v_offer);
end $$;

-- ── 8. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b        record;
  v_d        record;
  v_h        record;
  v_pp       record;
  v_def      text;
  v_city     uuid;
  v_work     text;
  v_offer    int;
  v_house    uuid;
  v_house_uid constant uuid := '00000000-0278-4000-8000-000000000001';
  v_cost     bigint;
  v_past     constant bigint := 777;   -- a giving in the PREVIOUS month: the board is all-time
  v_r        jsonb;
  v_anchor   timestamptz;
  v_fleet    uuid;
  v_route    uuid;
  v_lid      uuid;
  v_boundary timestamptz;
  i          int;
  v_players  int;
  v_book     int;
  v_lapbook  int;
  v_treas    jsonb;
  v_infl     jsonb;
begin
  select * into v_b from before_0278;
  -- SNAPSHOTS before any probe touches them: the two switches the city probe writes inside its rolled-back
  -- block, the probe's table counts, and the two books' counts (the probe's own rows must all roll back).
  select value into v_treas from public.world_config where key = 'city_treasury_enabled';
  select value into v_infl  from public.world_config where key = 'influence_enabled';
  v_players := (select count(*) from public.players);
  v_book    := (select count(*) from public.city_month_book);
  v_lapbook := (select count(*) from public.route_month_laps);

  -- (a) NO RE-STAMP: every row 0275 wrote is week 0, which IS month 0 under the 2026-10-01 anchor. If a row
  --     reads otherwise, this file is deploying after the week rolled and would silently file it under the
  --     wrong month — refuse instead.
  if exists (select 1 from public.city_month_book where month <> 0)
     or exists (select 1 from public.route_month_laps where month <> 0) then
    raise exception '0278 self-assert FAIL: an existing book row is not week 0 = month 0 — this file is deploying after the week rolled; no re-stamp is done';
  end if;

  -- (b) THE HUNKS reverse to the live pre-images; ACL / volatility / definer / config unmoved; nothing else
  -- in the four schemas moved; exactly the two new month readings and the renamed writer were minted; the
  -- registry still carries exactly the one city_history row; the two books are server-only.
  for v_d in select * from defs_before_0278 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0278 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0278(v_def, v_h.new) <> 1 then
        raise exception '0278 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0278 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0278 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_b.fns then
    raise exception '0278 self-assert FAIL: the four schemas'' function count moved (%, expected %)',
      (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')), v_b.fns;
  end if;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and (n.nspname, p.proname) not in (
               ('public', 'pay_city'), ('world', 'town_hall'), ('cmd', 'standing_route_close_lap'),
               ('public', 'route_earnings'), ('world', 'standing_routes'),
               ('public', 'client_rpc_entry_points'), ('world', 'city_history'),
               ('world', 'week_of'), ('world', 'week_start'), ('public', 'city_week_post'),
               ('world', 'month_of'), ('world', 'month_start'), ('public', 'city_month_post'))) <> v_b.others_md5 then
    raise exception '0278 self-assert FAIL: a function this file does not re-cut moved';
  end if;
  foreach v_def in array array['world.month_of(timestamptz)', 'world.month_start(bigint)',
                                'public.city_month_post(uuid,uuid,text,bigint)', 'world.city_history(uuid,int)'] loop
    if (select count(*) from pg_proc p where p.oid = v_def::regprocedure) <> 1 then
      raise exception '0278 self-assert FAIL: % is not in one place', v_def;
    end if;
  end loop;
  -- the old week names are gone from the catalog
  if to_regprocedure('world.week_of(timestamptz)') is not null
     or to_regprocedure('world.week_start(bigint)') is not null
     or to_regprocedure('public.city_week_post(uuid,uuid,text,bigint)') is not null
     or to_regclass('public.city_week_book') is not null
     or to_regclass('public.route_week_laps') is not null
     or exists (select 1 from public.world_config where key = 'week_anchor') then
    raise exception '0278 self-assert FAIL: a week name survived the rename';
  end if;
  -- the two books, under their new names and columns
  if to_regclass('public.city_month_book') is null or to_regclass('public.route_month_laps') is null
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'city_month_book' and column_name = 'month')
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'route_month_laps' and column_name = 'month')
     or exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'city_month_book' and column_name = 'week')
     or exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'route_month_laps' and column_name = 'week') then
    raise exception '0278 self-assert FAIL: the month books do not have the shape this file claims';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.city_month_book'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.route_month_laps'::regclass) then
    raise exception '0278 self-assert FAIL: a month book stands without row level security';
  end if;
  -- the registry: the one city_history row, resolving, granted to authenticated and to no one else
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points
     or (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'city_history') <> 1
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.function_name = 'city_history'
                   and (e.fn is null
                        or not has_function_privilege('authenticated', e.fn, 'execute')
                        or has_function_privilege('anon', e.fn, 'execute')
                        or has_function_privilege('public', e.fn, 'execute'))) then
    raise exception '0278 self-assert FAIL: the registry no longer carries world.city_history as an authenticated-only door';
  end if;
  -- the server-side rules: no client role runs the month clock or the book's writer; the books hold no
  -- client grant
  foreach v_def in array array['world.month_of(timestamptz)', 'world.month_start(bigint)',
                                'public.city_month_post(uuid,uuid,text,bigint)'] loop
    if has_function_privilege('authenticated', v_def::regprocedure, 'execute')
       or has_function_privilege('anon', v_def::regprocedure, 'execute') then
      raise exception '0278 self-assert FAIL: a client role may execute %', v_def;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.city_month_book', 'select')
     or has_table_privilege('anon', 'public.city_month_book', 'select')
     or has_table_privilege('authenticated', 'public.route_month_laps', 'select')
     or has_table_privilege('anon', 'public.route_month_laps', 'select') then
    raise exception '0278 self-assert FAIL: a client role may read a month book';
  end if;
  -- ONE WRITER each: the book's post is called by pay_city alone; the lap book is written by close_lap alone
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage')
         and p.prosrc like '%city_month_post(%' and p.proname not in ('city_month_post')) <> 1
     or (select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage')
            and p.prosrc like '%city_month_post(%' and p.proname not in ('city_month_post')) <> 'pay_city' then
    raise exception '0278 self-assert FAIL: city_month_post is not called by public.pay_city alone';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage')
         and p.prosrc like '%insert into public.route_month_laps%') <> 1
     or (select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage')
            and p.prosrc like '%insert into public.route_month_laps%') <> 'standing_route_close_lap' then
    raise exception '0278 self-assert FAIL: route_month_laps is not written by cmd.standing_route_close_lap alone';
  end if;

  -- (c) THE MONTH ITSELF: the truth table of the one clock, read off the knob.
  v_anchor := (public.wc_text('month_anchor'))::timestamptz;
  if v_anchor <> '2026-10-01T00:00:00Z'::timestamptz
     or world.month_of(v_anchor - interval '1 second') <> -1
     or world.month_of(v_anchor) <> 0
     or world.month_of(v_anchor + interval '1 month' - interval '1 second') <> 0
     or world.month_of(v_anchor + interval '1 month') <> 1
     or world.month_start(0) <> v_anchor
     or world.month_start(1) <> v_anchor + interval '1 month'
     or world.month_start(world.month_of()) > now()
     or now() >= world.month_start(world.month_of() + 1) then
    raise exception '0278 self-assert FAIL: the month clock reads wrong off the % knob', v_anchor;
  end if;

  -- (d) THE CITY BOOK, through the real doors — one probe house invests, gives twice, and a past-month row
  -- is laid beside them: the Town Hall board sums ALL months and the History read folds the months. Every row
  -- this block writes rolls back with it (the switches too).
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'influence_enabled';
    v_house := public.new_house(v_house_uid, 'Casa Mensal 0278', 'PRT', 'LIS', 'Gaivota',
                                'barca', 'Gaivota', 1000000, false);
    v_r := pg_temp.probe_city_0278();
    v_city  := (v_r->>'city')::uuid;
    v_work  := v_r->>'kind';
    v_offer := (v_r->>'offer')::int;
    v_r := public.invest_for(v_house, v_city, v_work, v_offer);
    -- the cost is the EXECUTED row's own reported figure (never assert a write against a price read before it)
    v_cost := (v_r->>'cost')::bigint;
    if v_cost is null or v_cost <= 0 then
      raise exception '0278 self-assert FAIL: the probe stake reported no real cost: %', v_r;
    end if;
    -- the book gained EXACTLY one row, the AMOUNT, under the current month, with no gifts on a share
    if (select count(*) from public.city_month_book b where b.port_id = v_city and b.player_id = v_house) <> 1
       or (select b.ducats from public.city_month_book b
            where b.port_id = v_city and b.player_id = v_house and b.kind = 'SHARE') <> v_cost
       or (select b.gifts from public.city_month_book b
            where b.port_id = v_city and b.player_id = v_house and b.kind = 'SHARE') <> 0
       or (select b.month from public.city_month_book b
            where b.port_id = v_city and b.player_id = v_house) <> world.month_of() then
      raise exception '0278 self-assert FAIL: an Invest of % did not land as one % book row under the current month',
        v_cost, v_cost;
    end if;
    -- a second gift in the same month ADDS and does not duplicate
    perform public.donate_for(v_house, v_city, 1000);
    perform public.donate_for(v_house, v_city, 500);
    if (select count(*) from public.city_month_book b where b.port_id = v_city and b.player_id = v_house) <> 2
       or (select b.ducats from public.city_month_book b
            where b.port_id = v_city and b.player_id = v_house and b.kind = 'DONATION') <> 1500
       or (select b.gifts from public.city_month_book b
            where b.port_id = v_city and b.player_id = v_house and b.kind = 'DONATION') <> 2 then
      raise exception '0278 self-assert FAIL: two gifts of 1000 and 500 did not add to one DONATION row of 1500 with gifts 2';
    end if;
    -- a giving in the PREVIOUS month, laid directly (this whole block rolls back): the board must include it.
    insert into public.city_month_book (port_id, month, player_id, kind, ducats, gifts, updated_at)
    values (v_city, world.month_of() - 1, v_house, 'SHARE', v_past, 0, now());
    -- the Town Hall board serves the probe at the ALL-TIME sum
    v_r := world.town_hall(v_city)->'investors';
    if not exists (select 1 from jsonb_array_elements(v_r) e
                    where e->>'name' = 'Casa Mensal 0278'
                      and (e->>'invested')::bigint = v_cost + v_past
                      and (e->>'donated')::bigint = 1500
                      and (e->>'total')::bigint = v_cost + v_past + 1500) then
      raise exception '0278 self-assert FAIL: the Town Hall board does not sum the months: %', v_r;
    end if;
    -- the History read folds the months: this month holds the invest and the gifts, last month holds the
    -- past giving, and the dates are world.month_start's own.
    v_r := world.city_history(v_city, 8);
    if (v_r->>'month')::bigint <> world.month_of()
       or jsonb_array_length(v_r->'months') <> 9
       or (v_r->'months'->0->>'current')::boolean is not true
       or (v_r->'months'->0->>'total')::bigint <> v_cost + 1500
       or not exists (select 1 from jsonb_array_elements(v_r->'months'->0->'investors') e
                       where e->>'name' = 'Casa Mensal 0278' and (e->>'total')::bigint = v_cost + 1500)
       or (v_r->'months'->1->>'current')::boolean is not false
       or (v_r->'months'->1->>'month')::bigint <> world.month_of() - 1
       or (v_r->'months'->1->>'total')::bigint <> v_past
       or not exists (select 1 from jsonb_array_elements(v_r->'months'->1->'investors') e
                       where e->>'name' = 'Casa Mensal 0278'
                         and (e->>'invested')::bigint = v_past and (e->>'total')::bigint = v_past)
       or world.month_start((v_r->'months'->0->>'month')::bigint) <> (v_r->'months'->0->>'starts')::timestamptz
       or world.month_start((v_r->'months'->1->>'month')::bigint) <> (v_r->'months'->1->>'starts')::timestamptz then
      raise exception '0278 self-assert FAIL: the History read does not fold the months as served: %', v_r;
    end if;
    -- the book wrote no event of its own: the house's events are the founding, the invest's own and
    -- the two gifts' own — nothing more
    if (select count(*) from public.events e where e.player_id = v_house) <> 4
       or (select count(*) from public.events e where e.player_id = v_house and e.kind = 'INVESTED') <> 1
       or (select count(*) from public.events e where e.player_id = v_house and e.kind = 'DONATED') <> 2 then
      raise exception '0278 self-assert FAIL: the book moved the events stream (the house holds %)',
        (select jsonb_agg(e.kind) from public.events e where e.player_id = v_house);
    end if;
    raise exception 'PROBE_ROLLBACK_0278_CITY';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0278_CITY' then raise; end if;
  end;

  -- (e) THE LAP BOOK: three laps of one probe route — two closed in the month BEFORE this one (one and two
  -- hours before the boundary), one closed now (this month). Each lap carries one done SELL of 1,000 d. with
  -- 10 tax and 50 wages, so a lap nets 940. The third lap opens a new month row; route_earnings reads the
  -- all-time total; deleting the route keeps its month history.
  begin
    v_house := public.new_house(v_house_uid, 'Casa Mensal 0278', 'PRT', 'LIS', 'Gaivota',
                                'barca', 'Gaivota', 1000000, false);
    select x.id into v_city from public.ports x where x.kind = 'HARBOUR' order by x.code limit 1;
    v_fleet := public.form_fleet(v_house, 'Frota 0278', v_city);
    insert into public.standing_routes (player_id, name, fleet_id)
    values (v_house, 'Rota 0278', v_fleet) returning id into v_route;
    v_boundary := world.month_start(world.month_of());
    for i in 1..3 loop
      insert into public.standing_route_laps (route_id, lap_no, started_at)
      values (v_route, i, v_boundary - interval '3 hours' - i * interval '1 minute') returning id into v_lid;
      update public.standing_routes set lap_id = v_lid where id = v_route;
      insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, result, route_lap_id)
      values (v_fleet, v_house, i, 'SELL probe 0278', 'SELL', 'done',
              jsonb_build_object('total', 1000, 'tax', 10, 'wages', 50), v_lid);
      perform cmd.standing_route_close_lap(v_route,
              case when i <= 2 then v_boundary - (3 - i) * interval '1 hour' else now() end);
    end loop;
    -- one row for the month before this one (laps 1+2: 2 laps, net 1,880 to the ducat), one for this
    -- month (lap 3)
    if (select count(*) from public.route_month_laps w where w.route_id = v_route) <> 2
       or (select w.laps from public.route_month_laps w
            where w.route_id = v_route and w.month = world.month_of() - 1) <> 2
       or (select w.net from public.route_month_laps w
            where w.route_id = v_route and w.month = world.month_of() - 1) <> 1880
       or (select w.laps from public.route_month_laps w
            where w.route_id = v_route and w.month = world.month_of()) <> 1
       or (select w.net from public.route_month_laps w
            where w.route_id = v_route and w.month = world.month_of()) <> 940
       or (select w.sold from public.route_month_laps w
            where w.route_id = v_route and w.month = world.month_of()) <> 1000
       or (select w.wages from public.route_month_laps w
            where w.route_id = v_route and w.month = world.month_of()) <> 50
       or (select w.player_id from public.route_month_laps w
            where w.route_id = v_route and w.month = world.month_of()) is distinct from v_house
       or (select w.route_name from public.route_month_laps w
            where w.route_id = v_route and w.month = world.month_of()) is distinct from 'Rota 0278' then
      raise exception '0278 self-assert FAIL: the three laps did not land as two month rows with laps 2/1 and nets 1880/940';
    end if;
    -- the earnings reading is ALL-TIME: laps_done 3, total 3 laps / 2,820 net / 3,000 sold / 150 wages,
    -- and no week key of any kind
    v_r := public.route_earnings(v_route);
    if (v_r->>'laps_done')::int <> 3
       or (v_r->'total'->>'laps')::int <> 3
       or (v_r->'total'->>'net')::bigint <> 2820
       or (v_r->'total'->>'sold')::bigint <> 3000
       or (v_r->'total'->>'bought')::bigint <> 0
       or (v_r->'total'->>'supplies')::bigint <> 0
       or (v_r->'total'->>'repairs')::bigint <> 0
       or (v_r->'total'->>'wages')::bigint <> 150
       or v_r ? 'week' or v_r ? 'last_week' or v_r ? 'laps_done_all' then
      raise exception '0278 self-assert FAIL: route_earnings does not read all-time: %', v_r;
    end if;
    -- the served route book carries the same all-time object
    perform cmd.assume_identity(v_house_uid);
    v_r := world.standing_routes();
    if (select count(*) from jsonb_array_elements(v_r->'routes') r
         where r->>'id' = v_route::text
           and (r->'earnings'->'total'->>'laps')::int = 3
           and (r->'earnings'->>'laps_done')::int = 3
           and not (r->'earnings' ? 'week')) <> 1 then
      raise exception '0278 self-assert FAIL: world.standing_routes does not serve the probe route''s all-time earnings';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    -- delete the probe route: the month rows remain (no cascade), the lap rows go as today
    delete from public.standing_routes where id = v_route;
    if (select count(*) from public.route_month_laps w where w.route_id = v_route) <> 2
       or (select count(*) from public.standing_route_laps x where x.route_id = v_route) <> 0 then
      raise exception '0278 self-assert FAIL: deleting the route did not keep the month rows and drop the lap rows';
    end if;
    raise exception 'PROBE_ROLLBACK_0278_LAPS';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0278_LAPS' then raise; end if;
  end;

  -- (f) THE PROBES LEFT NOTHING: every row they wrote went with its transaction, the two switches stand
  -- exactly where the world had them, and the books hold only what the live world held before this file.
  if (select count(*) from public.players) <> v_players
     or (select count(*) from public.city_month_book) <> v_book
     or (select count(*) from public.route_month_laps) <> v_lapbook
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from v_treas
     or (select value from public.world_config where key = 'influence_enabled') is distinct from v_infl then
    raise exception '0278 self-assert FAIL: a probe row or a switch write escaped its transaction (players % vs %, book % vs %, lap book % vs %, switches %/% vs %/%)',
      (select count(*) from public.players), v_players,
      (select count(*) from public.city_month_book), v_book,
      (select count(*) from public.route_month_laps), v_lapbook,
      (select value from public.world_config where key = 'city_treasury_enabled'), v_treas,
      (select value from public.world_config where key = 'influence_enabled'), v_infl;
  end if;

  raise notice '0278 self-assert ok: THE MONTH IS A KEY. The six bodies (pay_city, town_hall, close_lap, route_earnings, standing_routes, the registry) reverse to their pre-images hunk by hunk, ACLs unmoved, every other function in the four schemas unmoved (md5), the function count unchanged (week_of / week_start / city_week_post gone, month_of / month_start / city_month_post minted), the registry still +0 (city_history authenticated only), the two books server-only under RLS, one writer each (pay_city alone, close_lap alone). The month clock: month_of(anchor - 1 s) = -1, month_of(anchor) = 0, month_of(anchor + 1 month - 1 s) = 0, month_of(anchor + 1 month) = 1, and now() stands inside its own month. No re-stamp: every pre-existing row is week 0 = month 0. The city book through the real doors: an Invest of % lands one SHARE row under the current month, two gifts add to one DONATION row of 1500 with gifts 2, a past-month row is laid beside them, the Town Hall board sums all three (all-time), the History read folds this month and the one before it, and the events stream is untouched. The lap book: three probe laps — two before the boundary, one now — land as two month rows (laps 2/1, nets 1,880/940 to the ducat), and route_earnings reads laps_done 3 and total 3 / 2,820 / 3,000 / 150 all-time, with no week key; the served route book carries the same object; deleting the route keeps the month rows while the lap rows go. Rolled back.',
    v_cost;
end $$;
