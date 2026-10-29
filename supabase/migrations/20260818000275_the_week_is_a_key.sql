-- 0275 — THE WEEK IS A KEY: the city's giving and a route's laps start fresh each week, and keep their past
--
-- Owner row 173 (2026-10-20): *"The investment in city, Lap records should be reset every week. There will be a
-- history tab where you can see the last week's investment records when pressing a city."* The owner accepted
-- EVERY default of docs/WEEKLY_ROLLOVER.md on 2026-10-25: the week runs Monday 00:00 UTC; the Investors board and
-- the route lap counters reset; shares, works, influence and flags do not; no backfill; the History tab keeps 8
-- weeks; no cron. The design is that document, and the build is its slices W1-W4 in this one file (the client's
-- W3/W4 faces ship in the same PR; the slice is never half-shipped).
--
-- THE ONE IDEA: a "reset" is not a delete and not a job that zeroes rows. THE WEEK IS A KEY. Every figure the
-- owner wants reset is written under the week it happened in, the live faces read the current week's key, and the
-- history tab reads the earlier keys of the same table. Nothing is ever deleted, `events` and the ledger are
-- untouched, and there is no moment at which a row is rewritten.
--
-- WHAT MOVES (one authority per concept):
--   1. world.week_of(p_at timestamptz default now()) -> bigint = floor((epoch(p_at) - epoch(week_anchor)) / 604800),
--      and world.week_start(p_week bigint) -> timestamptz = week_anchor + p_week weeks. Both stable, security
--      definer, server-side; they live next to world.game_day (0005) because they are the same kind of thing: the
--      one clock reading. week_anchor is a world_config knob = 2026-10-26T00:00:00Z (a Monday), read by these two
--      functions alone. THE CLIENT NEVER COMPUTES A WEEK: it prints the week, starts and ends served.
--   2. public.city_week_book (port_id, week, player_id, kind in ('SHARE','DONATION'), ducats, gifts, updated_at),
--      PK (port_id, week, player_id, kind), index (port_id, week). Written by public.city_week_post ALONE, called
--      from public.pay_city's SHARE/DONATION branch — the same branch 0144 gave influence_post. An upsert ADDS
--      ducats (gifts += 1 on a DONATION). RLS on, revoked from clients, read through world.* only. Never deleted.
--   3. public.route_week_laps (route_id, week, player_id, route_name, laps, sold, bought, supplies, repairs, wages,
--      net, updated_at), PK (route_id, week), index (player_id, week). Written by cmd.standing_route_close_lap
--      ALONE, one hunk after the lap row is closed, stamped world.week_of(p_now). route_id has NO FK: a deleted
--      route keeps its history (today standing_route_laps cascades away with the route). player_id cascades with
--      the house.
--   4. world.city_history(p_port uuid, p_weeks int default 8) — the city's giving by week: the current week and the
--      past min(p_weeks, 8), newest first, each with starts / ends / total / investors {name, merchant, invested,
--      donated, total} (ordered total desc, name; capped by town_hall_investors_max). Authenticated only, like the
--      Town Hall; registered in public.client_rpc_entry_points.
--
-- SUPERSEDE / RE-CUTS (supabase/migrations/README.md:43-48). This file re-cuts SIX live functions by hunks sliced
-- from their bodies (each hunk asserts it occurs exactly once and reverses to its pre-image; ACL / volatility /
-- definer / config unmoved; the md5 of every other function in the four schemas unmoved):
--   * public.pay_city(uuid,uuid,text,bigint,uuid) — 0122's body as re-cut by 0144; one hunk: the SHARE/DONATION
--     branch gains the city_week_post call beside influence_post (the week book's ONE writer).
--   * world.town_hall(uuid) — 0123's body as re-cut by 0144, 0234, 0237; one hunk: `investors` re-cut from the
--     all-time city_shares board to THIS WEEK's city_week_book (owner: the board resets weekly). Shares, works,
--     influence, dues and gifts are untouched.
--   * cmd.standing_route_close_lap(uuid,timestamptz) — 0092's body as re-cut by 0116, 0121, 0122, 0128, 0129, 0213;
--     one hunk: after the lap row is closed, its figures upsert into this week's route_week_laps row (the book's
--     ONE writer).
--   * public.route_earnings(uuid) — 0097's body as re-cut by 0128; one hunk: gains `week {laps, net, sold, bought,
--     supplies, repairs, wages}` (this week's book row, zeros when none), `last_week {laps, net}` (null when none),
--     `laps_done` becomes this week's count and `laps_done_all` keeps the old figure for one release, then goes.
--   * world.standing_routes() — 0092's body as re-cut by 0093, 0096, 0099, 0154; one hunk: each route gains the
--     served `earnings` object (public.route_earnings composed, not recomputed) — the face W4 prints `week` and
--     `last_week` from. This is the one serve that reaches the command fold and the voyage tray, the two faces
--     docs/WEEKLY_ROLLOVER.md §5 W4 names; the design names the faces but not the serve, so this re-cut is decided
--     by default and said here.
--   * public.client_rpc_entry_points() — 0083's body, re-cut by many slices since (last: 0246's two stats
--     rows; the live tail ends at 0235's money_feed); one hunk: the world.city_history row.
-- IT IS A NO-OP WHEN THE NEW INPUT IS ABSENT. pay_city: a kind other than SHARE/DONATION posts nothing, exactly as
-- before 0275. town_hall: an empty week book reads an empty board (the old board read city_shares; that register
-- and `you.holdings` are untouched). close_lap: a route with no open lap returns before the hunk, as before; a
-- closed lap adds one upsert to a write that already does an event, a treasury post and an influence post.
-- route_earnings: a route with no week rows reads week {0…} / last_week null. standing_routes: earnings was
-- already served on the route board and the merchant card; this adds it to the company's own routes book.
-- Everything that must move together moves in this one file: the clock, the two books, their two writers, the four
-- readers, and the client faces that print them (the same PR).
--
-- WHAT IS NOT PROVEN (said plainly; the dev-log says it again). The deploy week's board starts empty: no backfill
-- from `events` (the merchants' events are compacted, 0097:889, so a backfill would show players and not merchants)
-- — decided by default, the board simply starts. The two books keep every week; compaction is not needed for years
-- (a few thousand rows a week, no table is scanned at the boundary: town_hall and city_history read (port_id, week)
-- by index, route_earnings reads (route_id, week) by primary key, the same cost as its 24-hour lap window today).
--
-- PROD CHECKS (before the push; read-only; in the PR body): pg_get_functiondef of the six live bodies contain the
-- pre-image hunks once each (their md5s, the ones the local chain printed); `select count(*) from city_shares` and
-- INVESTED / DONATED events of the last 7 days per port (sizes the book: today's giving is a few hundred rows a
-- week across 238 harbours); `select count(*) from standing_route_laps where closed_at > now() - interval '7 days'`
-- (the upsert count per week, one row per route per week); week_of/week_start do not exist yet. AFTER THE DEPLOY:
-- the first INVESTED / DONATED and the first lap close land rows under world.week_of(now()); the Town Hall board
-- reads this week alone; the History tab folds the current week open; the command fold prints "N laps this week".
--
-- ROLLBACK (forward): reverse the six hunks to their pre-images (the re-cut loop's own reversal, re-run with old
-- and new swapped); drop world.city_history, public.city_week_post, world.week_of, world.week_start; drop the two
-- tables and their indexes; delete the week_anchor knob; reverse the registry hunk. The books can stay (append-
-- only, read by nothing after the readers reverse) — the same forward shape 0144 chose for its book.
--
-- VERSION: 0275 (prod head 0272 at the time of writing; 0273 and 0274 are applied before this one, in number
-- order; neither re-cuts a body this file cuts against — if one lands differently, the hunk self-asserts fail
-- loudly at apply, which is the safe failure).

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
    raise exception '0275 refuses: 0122/0123/0092/0097/0083 are not in this world';
  end if;
  if to_regclass('public.city_week_book') is not null then
    raise exception '0275 refuses: public.city_week_book already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0275(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0275 on commit drop as
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

-- EVERY function in the four schemas except the six this file re-cuts: one md5 over the lot, so a body that moves
-- without being named here is caught. The four new functions this file mints are excluded from the after-reading.
create temp table before_0275 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid not in (to_regprocedure('public.pay_city(uuid,uuid,text,bigint,uuid)'),
                             to_regprocedure('world.town_hall(uuid)'),
                             to_regprocedure('cmd.standing_route_close_lap(uuid,timestamptz)'),
                             to_regprocedure('public.route_earnings(uuid)'),
                             to_regprocedure('world.standing_routes()'),
                             to_regprocedure('public.client_rpc_entry_points()'))) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid not in (to_regprocedure('public.pay_city(uuid,uuid,text,bigint,uuid)'),
                             to_regprocedure('world.town_hall(uuid)'),
                             to_regprocedure('cmd.standing_route_close_lap(uuid,timestamptz)'),
                             to_regprocedure('public.route_earnings(uuid)'),
                             to_regprocedure('world.standing_routes()'),
                             to_regprocedure('public.client_rpc_entry_points()'))) as others_md5;

-- ── 1. THE WEEK: the knob and the one pair of readings ─────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('week_anchor', to_jsonb('2026-10-26T00:00:00Z'::text),
   '0275 (docs/WEEKLY_ROLLOVER.md §3): the Monday 00:00 UTC that the week numbers count from — read by '
   'world.week_of and world.week_start ALONE (the one week authority; a real week is 604800 seconds, '
   '210 game days of game_day_seconds). The owner accepted Monday 00:00 UTC (Monday 09:00 KST) on 2026-10-25.')
on conflict (key) do nothing;

create or replace function world.week_of(p_at timestamptz default now())
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0275 (docs/WEEKLY_ROLLOVER.md §3): THE one reading of "which week is it" — floor((epoch(p_at) −
  -- epoch(week_anchor)) / 604800). world.game_day's sibling: the same kind of thing, one clock. The
  -- client never computes a week; it prints the week, starts and ends served.
  select floor((extract(epoch from p_at)
                - extract(epoch from (public.wc_text('week_anchor'))::timestamptz)) / 604800)::bigint
$$;
comment on function world.week_of(timestamptz) is
  '0275 (docs/WEEKLY_ROLLOVER.md §3): the week number of an instant, counted from the week_anchor knob — '
  'THE one reading of the current week. world.game_day''s sibling. Server-only.';
revoke all on function world.week_of(timestamptz) from public, anon, authenticated;

create or replace function world.week_start(p_week bigint)
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0275 (docs/WEEKLY_ROLLOVER.md §3): the instant a week begins — week_anchor + p_week weeks. The pair
  -- (week_of, week_start) is the one week authority; a face prints starts and ends, never computes them.
  select (public.wc_text('week_anchor'))::timestamptz + p_week * interval '1 week'
$$;
comment on function world.week_start(bigint) is
  '0275 (docs/WEEKLY_ROLLOVER.md §3): the instant the week p_week begins — world.week_of''s pair, the one '
  'week authority (week_anchor + p_week weeks). Server-only.';
revoke all on function world.week_start(bigint) from public, anon, authenticated;

-- ── 2. THE CITY BOOK: who gave what to a city, under the week she gave it in ────────────────────
create table public.city_week_book (
  port_id    uuid    not null references public.ports(id) on delete cascade,
  week       bigint  not null,
  player_id  uuid    not null references public.players(id) on delete cascade,
  kind       text    not null check (kind in ('SHARE', 'DONATION')),
  ducats     bigint  not null default 0 check (ducats >= 0),
  gifts      int     not null default 0 check (gifts >= 0),
  updated_at timestamptz not null default now(),
  primary key (port_id, week, player_id, kind)
);
comment on table public.city_week_book is
  '0275 (docs/WEEKLY_ROLLOVER.md §3): the coin a company gave INTO a city — an investment (SHARE) or a '
  'gift (DONATION) — under the week it was given in (world.week_of). Written by public.city_week_post '
  'alone, from public.pay_city''s SHARE/DONATION branch. The week is a KEY: nothing is ever deleted, the '
  'live board reads the current week''s key and the History tab the earlier ones. Append-only.';
create index city_week_book_port_week on public.city_week_book (port_id, week);
alter table public.city_week_book set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);
alter table public.city_week_book enable row level security;
revoke all on table public.city_week_book from public, anon, authenticated;

create or replace function public.city_week_post(p_player uuid, p_port uuid, p_kind text, p_amount bigint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0275 (docs/WEEKLY_ROLLOVER.md §3): THE one writer of public.city_week_book — called by public.pay_city
-- alone, from the same SHARE / DONATION branch 0144 gave public.influence_post. One row per (port, week,
-- giver, kind); a second giving in the same week ADDS, never duplicates. The week key is world.week_of's
-- alone — this body computes no week.
begin
  insert into public.city_week_book (port_id, week, player_id, kind, ducats, gifts, updated_at)
  values (p_port, world.week_of(), p_player, p_kind, coalesce(p_amount, 0),
          case when p_kind = 'DONATION' then 1 else 0 end, now())
  on conflict (port_id, week, player_id, kind) do update
     set ducats = public.city_week_book.ducats + excluded.ducats,
         gifts = public.city_week_book.gifts + excluded.gifts,
         updated_at = now();
end $$;
comment on function public.city_week_post(uuid, uuid, text, bigint) is
  '0275 (docs/WEEKLY_ROLLOVER.md §3): the one writer of public.city_week_book — the coin a company gives '
  'INTO a city, under the week it was given in. Called by public.pay_city alone for SHARE and DONATION. '
  'Server-only.';
revoke all on function public.city_week_post(uuid, uuid, text, bigint) from public, anon, authenticated;

-- ── 3. THE LAP BOOK: a route's laps, under the week they closed in ─────────────────────────────
create table public.route_week_laps (
  route_id   uuid    not null,   -- no FK: a deleted route keeps its history (its lap rows cascade away today)
  week       bigint  not null,
  player_id  uuid    not null references public.players(id) on delete cascade,
  route_name text    not null,
  laps       int     not null check (laps > 0),
  sold       bigint  not null default 0,
  bought     bigint  not null default 0,
  supplies   bigint  not null default 0,
  repairs    bigint  not null default 0,
  wages      bigint  not null default 0,
  net        bigint  not null default 0,
  updated_at timestamptz not null default now(),
  primary key (route_id, week)
);
comment on table public.route_week_laps is
  '0275 (docs/WEEKLY_ROLLOVER.md §3): a route''s closed laps and their figures, under the week they closed '
  'in (world.week_of(p_now), written by cmd.standing_route_close_lap alone after each lap closes). The week '
  'is a KEY: the live counters read the current week''s key; the table keeps every week. The route''s lap '
  'rows stay bounded by standing_route_lap_keep, so a route that closes more than 200 laps a week keeps its '
  'true week count here. route_id has no FK on purpose: a deleted route keeps its history. Append-only.';
create index route_week_laps_player_week on public.route_week_laps (player_id, week);
alter table public.route_week_laps set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);
alter table public.route_week_laps enable row level security;
revoke all on table public.route_week_laps from public, anon, authenticated;

-- ── 4. THE HISTORY READ: the city's giving by week ─────────────────────────────────────────────
create or replace function world.city_history(p_port uuid, p_weeks int default 8)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0275 (docs/WEEKLY_ROLLOVER.md §4): the city's giving by week — the current week and the past
-- min(p_weeks, 8), newest first, each with its starts / ends / total and its givers {name, merchant,
-- invested, donated, total} (total desc, name; capped by town_hall_investors_max, the Town Hall's own
-- cap). The table keeps every week; this door serves eight. Weeks are world.week_of's — this body
-- computes none. Authenticated only, like the Town Hall; no tier gate (the investor board is not gated).
declare
  v_week bigint := world.week_of();
  v_w    bigint;
  v_port public.ports%rowtype;
begin
  select x.* into v_port from public.ports x where x.id = p_port;
  if v_port.id is null or v_port.kind <> 'HARBOUR' then
    raise exception 'E_NOT_FOUND: there is no such harbour' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'port', v_port.code,
    'week', v_week,
    'weeks', (select jsonb_agg(jsonb_build_object(
               'week', w,
               'starts', world.week_start(w),
               'ends', world.week_start(w + 1),
               'current', w = v_week,
               'total', coalesce((select sum(b.ducats) from public.city_week_book b
                                   where b.port_id = p_port and b.week = w), 0),
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
                                    where b2.port_id = p_port and b2.week = w
                                    group by b2.player_id) b
                             join public.players pl on pl.id = b.player_id
                            order by b.total desc, pl.company_name
                            limit public.wc_int('town_hall_investors_max')) x), '[]'::jsonb))
               order by w desc)
             from generate_series(v_week, v_week - least(greatest(coalesce(p_weeks, 8), 0), 8), -1) w)
  );
end $$;
comment on function world.city_history(uuid, int) is
  '0275 (docs/WEEKLY_ROLLOVER.md §4): one harbour''s giving by week — the current week and the past eight, '
  'newest first, each with its dates, total and givers. The History tab''s one read. Authenticated only.';
revoke all on function world.city_history(uuid, int) from public, anon;
grant execute on function world.city_history(uuid, int) to authenticated;

-- ── 5. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0275 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0275 (fn, n, old, new) values
-- ── public.pay_city: the same branch 0144 gave influence_post gains the week book's one writer ──
('public.pay_city(uuid,uuid,text,bigint,uuid)', 1,
$h$  if p_kind in ('SHARE', 'DONATION') then
    perform public.influence_post(p_player, p_port, p_amount, p_kind);
  end if;
  return v_after;$h$,
$h$  if p_kind in ('SHARE', 'DONATION') then
    perform public.influence_post(p_player, p_port, p_amount, p_kind);
    -- 0275 (docs/WEEKLY_ROLLOVER.md §3): the same coin also lands in THIS WEEK's giving book — the
    -- board the Town Hall and the History tab read. The week is world.week_of's alone.
    perform public.city_week_post(p_player, p_port, p_kind, p_amount);
  end if;
  return v_after;$h$),
-- ── world.town_hall: the investors board reads THIS WEEK's book (the all-time register stays for `you`) ──
('world.town_hall(uuid)', 1,
$h$    'investors', coalesce((select jsonb_agg(jsonb_build_object(
                    'name', x.company_name, 'merchant', x.is_npc, 'kind', x.kind,
                    'shares', x.shares, 'paid', x.paid) order by x.paid desc, x.company_name, x.kind)
                    from (select pl.company_name, pl.is_npc, s.kind, s.shares, s.paid
                            from public.city_shares s join public.players pl on pl.id = s.player_id
                           where s.port_id = p_port
                           order by s.paid desc, pl.company_name, s.kind
                           limit public.wc_int('town_hall_investors_max')) x), '[]'::jsonb),$h$,
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
                           limit public.wc_int('town_hall_investors_max')) x), '[]'::jsonb),$h$),
-- ── cmd.standing_route_close_lap: the closed lap's figures land in this week's book ──
('cmd.standing_route_close_lap(uuid,timestamptz)', 1,
$h$  returning * into l;
  update public.standing_routes set lap_id = null, updated_at = now() where id = p_route;$h$,
$h$  returning * into l;
  -- 0275 (docs/WEEKLY_ROLLOVER.md §3): the lap's figures land in THIS WEEK's book — one row per route
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
         updated_at = p_now;
  update public.standing_routes set lap_id = null, updated_at = now() where id = p_route;$h$),
-- ── public.route_earnings: the week counters ride the one earnings reading ──
('public.route_earnings(uuid)', 1,
$h$    'laps_done', coalesce((select max(x.lap_no) from public.standing_route_laps x
                            where x.route_id = p_route and x.closed_at is not null), 0))
$h$,
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
                   where rwl.route_id = p_route and rwl.week = world.week_of() - 1))
$h$),
-- ── world.standing_routes: each route gains the served earnings (W4's faces print from it) ──
('world.standing_routes()', 1,
$h$                          order by x0.lap_no desc limit 10) x)
      ) order by sr.created_at, sr.id), '[]'::jsonb)
$h$,
$h$                          order by x0.lap_no desc limit 10) x),
        -- 0275 (docs/WEEKLY_ROLLOVER.md §5 W4): the week counters ride the one earnings reading —
        -- composed here, never recomputed; the fold and the tray print week / last_week from it.
        'earnings', public.route_earnings(sr.id)
      ) order by sr.created_at, sr.id), '[]'::jsonb)
$h$),
-- ── public.client_rpc_entry_points: the History tab's one read ──
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'money_feed',            'timestamptz, int')
    ) as t(s, f, a)$h$,
$h$      ('world',       'money_feed',            'timestamptz, int'),
      -- 0275 (docs/WEEKLY_ROLLOVER.md §4): the city's giving by week — the History tab's read.
      ('world',       'city_history',          'uuid, int')
    ) as t(s, f, a)$h$);

-- THE HUNKS, each once, then the new bodies
do $$
declare
  d   record;
  h   record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0275 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0275 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0275(v_def, h.old);
      if v_n <> 1 then
        raise exception '0275 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 6. THE PROBES' TOOLS ───────────────────────────────────────────────────────────────────────
-- One probe house, one probe city: the first harbour (by code) whose works offer a stake the probe can
-- buy AND that has the fewest book rows, so the probe's rows are served under every cap.
create or replace function pg_temp.probe_city_0275()
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
   order by (select count(*) from public.city_week_book b where b.port_id = w.port_id), p.code, w.kind
   limit 1;
  if v_city is null then
    raise exception '0275 self-assert FAIL: no harbour offers a stake to invest in';
  end if;
  return jsonb_build_object('city', v_city, 'kind', v_kind, 'offer', v_offer);
end $$;

-- ── 7. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b       record;
  v_d       record;
  v_h       record;
  v_pp      record;
  v_def     text;
  v_city    uuid;
  v_work    text;
  v_offer   int;
  v_house   uuid;
  v_house_uid constant uuid := '00000000-0275-4000-8000-000000000001';
  v_cost    bigint;
  v_r       jsonb;
  v_anchor  timestamptz;
  v_fleet   uuid;
  v_route   uuid;
  v_lid     uuid;
  v_boundary timestamptz;
  i         int;
  v_players int;
  v_book    int;
  v_lapbook int;
  v_treas   jsonb;
  v_infl    jsonb;
begin
  select * into v_b from before_0275;
  -- SNAPSHOTS before any probe touches them: the two switches the city probe writes inside its rolled-back
  -- block, the probe's table counts, and the two books' counts (the probe's own rows must all roll back).
  select value into v_treas from public.world_config where key = 'city_treasury_enabled';
  select value into v_infl  from public.world_config where key = 'influence_enabled';
  v_players := (select count(*) from public.players);
  v_book    := (select count(*) from public.city_week_book);
  v_lapbook := (select count(*) from public.route_week_laps);

  -- (a) THE HUNKS reverse to the live pre-images; ACL / volatility / definer / config unmoved; nothing else
  -- in the four schemas moved; exactly the four new functions were minted, each in one place; the registry
  -- gained exactly the one row; the two books are server-only.
  for v_d in select * from defs_before_0275 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0275 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0275(v_def, v_h.new) <> 1 then
        raise exception '0275 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0275 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0275 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in (to_regprocedure('public.pay_city(uuid,uuid,text,bigint,uuid)'),
                           to_regprocedure('world.town_hall(uuid)'),
                           to_regprocedure('cmd.standing_route_close_lap(uuid,timestamptz)'),
                           to_regprocedure('public.route_earnings(uuid)'),
                           to_regprocedure('world.standing_routes()'),
                           to_regprocedure('public.client_rpc_entry_points()'))) <> v_b.fns + 4 then
    raise exception '0275 self-assert FAIL: the four schemas did not gain exactly the four new functions';
  end if;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in (to_regprocedure('public.pay_city(uuid,uuid,text,bigint,uuid)'),
                           to_regprocedure('world.town_hall(uuid)'),
                           to_regprocedure('cmd.standing_route_close_lap(uuid,timestamptz)'),
                           to_regprocedure('public.route_earnings(uuid)'),
                           to_regprocedure('world.standing_routes()'),
                           to_regprocedure('public.client_rpc_entry_points()'),
                           to_regprocedure('world.week_of(timestamptz)'),
                           to_regprocedure('world.week_start(bigint)'),
                           to_regprocedure('public.city_week_post(uuid,uuid,text,bigint)'),
                           to_regprocedure('world.city_history(uuid,int)'))) <> v_b.others_md5 then
    raise exception '0275 self-assert FAIL: a function this file does not re-cut moved';
  end if;
  foreach v_def in array array['world.week_of(timestamptz)', 'world.week_start(bigint)',
                                'public.city_week_post(uuid,uuid,text,bigint)', 'world.city_history(uuid,int)'] loop
    if (select count(*) from pg_proc p where p.oid = v_def::regprocedure) <> 1 then
      raise exception '0275 self-assert FAIL: % is not in one place', v_def;
    end if;
  end loop;
  -- the registry: exactly one new row, resolving, granted to authenticated and to no one else
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points + 1
     or (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'city_history') <> 1
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.function_name = 'city_history'
                   and (e.fn is null
                        or not has_function_privilege('authenticated', e.fn, 'execute')
                        or has_function_privilege('anon', e.fn, 'execute')
                        or has_function_privilege('public', e.fn, 'execute'))) then
    raise exception '0275 self-assert FAIL: the registry did not gain world.city_history as an authenticated-only door';
  end if;
  -- the server-side rules: no client role runs the clock or the book's writer; the books hold no client grant
  foreach v_def in array array['world.week_of(timestamptz)', 'world.week_start(bigint)',
                                'public.city_week_post(uuid,uuid,text,bigint)'] loop
    if has_function_privilege('authenticated', v_def::regprocedure, 'execute')
       or has_function_privilege('anon', v_def::regprocedure, 'execute') then
      raise exception '0275 self-assert FAIL: a client role may execute %', v_def;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.city_week_book', 'select')
     or has_table_privilege('anon', 'public.city_week_book', 'select')
     or has_table_privilege('authenticated', 'public.route_week_laps', 'select')
     or has_table_privilege('anon', 'public.route_week_laps', 'select') then
    raise exception '0275 self-assert FAIL: a client role may read a week book';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.city_week_book'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.route_week_laps'::regclass) then
    raise exception '0275 self-assert FAIL: a week book stands without row level security';
  end if;
  -- ONE WRITER each: the book's post is called by pay_city alone; the lap book is written by close_lap alone
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage')
         and p.prosrc like '%city_week_post(%' and p.proname not in ('city_week_post')) <> 1
     or (select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage')
            and p.prosrc like '%city_week_post(%' and p.proname not in ('city_week_post')) <> 'pay_city' then
    raise exception '0275 self-assert FAIL: city_week_post is not called by public.pay_city alone';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage')
         and p.prosrc like '%insert into public.route_week_laps%') <> 1
     or (select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage')
            and p.prosrc like '%insert into public.route_week_laps%') <> 'standing_route_close_lap' then
    raise exception '0275 self-assert FAIL: route_week_laps is not written by cmd.standing_route_close_lap alone';
  end if;

  -- (b) THE WEEK ITSELF: the truth table of the one clock, read off the knob.
  v_anchor := (public.wc_text('week_anchor'))::timestamptz;
  if world.week_of(v_anchor - interval '1 second') <> -1
     or world.week_of(v_anchor) <> 0
     or world.week_of(v_anchor + interval '7 days' - interval '1 second') <> 0
     or world.week_of(v_anchor + interval '7 days') <> 1
     or world.week_start(world.week_of()) > now()
     or now() >= world.week_start(world.week_of() + 1) then
    raise exception '0275 self-assert FAIL: the week clock reads wrong off the % knob', v_anchor;
  end if;

  -- (c) THE CITY BOOK, through the real doors — one probe house invests, gives twice, and the two readers
  -- serve it under the current week. Every row this block writes rolls back with it (the switches too).
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'influence_enabled';
    v_house := public.new_house(v_house_uid, 'Casa Semanal 0275', 'PRT', 'LIS', 'Gaivota',
                                'barca', 'Gaivota', 1000000, false);
    v_r := pg_temp.probe_city_0275();
    v_city  := (v_r->>'city')::uuid;
    v_work  := v_r->>'kind';
    v_offer := (v_r->>'offer')::int;
    v_r := public.invest_for(v_house, v_city, v_work, v_offer);
    -- the cost is the EXECUTED row's own reported figure (prod-proof rule: never assert a write
    -- against a price or offer read taken before it — live traders move the works in between).
    v_cost := (v_r->>'cost')::bigint;
    if v_cost is null or v_cost <= 0 then
      raise exception '0275 self-assert FAIL: the probe stake reported no real cost: %', v_r;
    end if;
    -- the book gained EXACTLY one row, the AMOUNT, under the current week, with no gifts on a share
    if (select count(*) from public.city_week_book b where b.port_id = v_city and b.player_id = v_house) <> 1
       or (select b.ducats from public.city_week_book b
            where b.port_id = v_city and b.player_id = v_house and b.kind = 'SHARE') <> v_cost
       or (select b.gifts from public.city_week_book b
            where b.port_id = v_city and b.player_id = v_house and b.kind = 'SHARE') <> 0
       or (select b.week from public.city_week_book b
            where b.port_id = v_city and b.player_id = v_house) <> world.week_of() then
      raise exception '0275 self-assert FAIL: an Invest of % did not land as one % book row under the current week',
        v_cost, v_cost;
    end if;
    -- a second gift in the same week ADDS and does not duplicate
    perform public.donate_for(v_house, v_city, 1000);
    perform public.donate_for(v_house, v_city, 500);
    if (select count(*) from public.city_week_book b where b.port_id = v_city and b.player_id = v_house) <> 2
       or (select b.ducats from public.city_week_book b
            where b.port_id = v_city and b.player_id = v_house and b.kind = 'DONATION') <> 1500
       or (select b.gifts from public.city_week_book b
            where b.port_id = v_city and b.player_id = v_house and b.kind = 'DONATION') <> 2 then
      raise exception '0275 self-assert FAIL: two gifts of 1000 and 500 did not add to one DONATION row of 1500 with gifts 2';
    end if;
    -- the Town Hall board serves the probe at that figure, from the week book
    v_r := world.town_hall(v_city)->'investors';
    if not exists (select 1 from jsonb_array_elements(v_r) e
                    where e->>'name' = 'Casa Semanal 0275'
                      and (e->>'invested')::bigint = v_cost
                      and (e->>'donated')::bigint = 1500
                      and (e->>'total')::bigint = v_cost + 1500) then
      raise exception '0275 self-assert FAIL: the Town Hall board does not serve the probe''s week giving: %', v_r;
    end if;
    -- the History read holds it under the current week and serves an empty earlier week
    v_r := world.city_history(v_city, 8);
    if (v_r->>'week')::bigint <> world.week_of()
       or jsonb_array_length(v_r->'weeks') <> 9
       or (v_r->'weeks'->0->>'current')::boolean is not true
       or (v_r->'weeks'->0->>'total')::bigint <> v_cost + 1500
       or not exists (select 1 from jsonb_array_elements(v_r->'weeks'->0->'investors') e
                       where e->>'name' = 'Casa Semanal 0275' and (e->>'total')::bigint = v_cost + 1500)
       or (v_r->'weeks'->1->>'current')::boolean is not false
       or (v_r->'weeks'->1->>'total')::bigint <> 0
       or jsonb_array_length(v_r->'weeks'->1->'investors') <> 0
       or world.week_start((v_r->'weeks'->0->>'week')::bigint) <> (v_r->'weeks'->0->>'starts')::timestamptz then
      raise exception '0275 self-assert FAIL: the History read does not fold the weeks as served: %', v_r;
    end if;
    -- the book wrote no event of its own: the house's events are the founding, the invest's own and
    -- the two gifts' own — nothing more
    if (select count(*) from public.events e where e.player_id = v_house) <> 4
       or (select count(*) from public.events e where e.player_id = v_house and e.kind = 'INVESTED') <> 1
       or (select count(*) from public.events e where e.player_id = v_house and e.kind = 'DONATED') <> 2 then
      raise exception '0275 self-assert FAIL: the book moved the events stream (the house holds %)',
        (select jsonb_agg(e.kind) from public.events e where e.player_id = v_house);
    end if;
    raise exception 'PROBE_ROLLBACK_0275_CITY';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0275_CITY' then raise; end if;
  end;

  -- (d) THE LAP BOOK: three laps of one probe route — two closed in the week BEFORE this one (one and two
  -- hours before the boundary), one closed now (this week). Each lap carries one done SELL of 1,000 d. with
  -- 10 tax and 50 wages, so a lap nets 940 and the sums are real. The third lap opens a new week row; the
  -- earnings reading and the served route book read the weeks; deleting the route keeps its week history.
  begin
    v_house := public.new_house(v_house_uid, 'Casa Semanal 0275', 'PRT', 'LIS', 'Gaivota',
                                'barca', 'Gaivota', 1000000, false);
    select x.id into v_city from public.ports x where x.kind = 'HARBOUR' order by x.code limit 1;
    v_fleet := public.form_fleet(v_house, 'Frota 0275', v_city);
    insert into public.standing_routes (player_id, name, fleet_id)
    values (v_house, 'Rota 0275', v_fleet) returning id into v_route;
    v_boundary := world.week_start(world.week_of());
    for i in 1..3 loop
      insert into public.standing_route_laps (route_id, lap_no, started_at)
      values (v_route, i, v_boundary - interval '3 hours' - i * interval '1 minute') returning id into v_lid;
      update public.standing_routes set lap_id = v_lid where id = v_route;
      insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, result, route_lap_id)
      values (v_fleet, v_house, i, 'SELL probe 0275', 'SELL', 'done',
              jsonb_build_object('total', 1000, 'tax', 10, 'wages', 50), v_lid);
      perform cmd.standing_route_close_lap(v_route,
              case when i <= 2 then v_boundary - (3 - i) * interval '1 hour' else now() end);
    end loop;
    -- one row for the week before this one (laps 1+2: 2 laps, net 1,880 to the ducat), one for this week (lap 3)
    if (select count(*) from public.route_week_laps w where w.route_id = v_route) <> 2
       or (select w.laps from public.route_week_laps w
            where w.route_id = v_route and w.week = world.week_of() - 1) <> 2
       or (select w.net from public.route_week_laps w
            where w.route_id = v_route and w.week = world.week_of() - 1) <> 1880
       or (select w.laps from public.route_week_laps w
            where w.route_id = v_route and w.week = world.week_of()) <> 1
       or (select w.net from public.route_week_laps w
            where w.route_id = v_route and w.week = world.week_of()) <> 940
       or (select w.sold from public.route_week_laps w
            where w.route_id = v_route and w.week = world.week_of()) <> 1000
       or (select w.wages from public.route_week_laps w
            where w.route_id = v_route and w.week = world.week_of()) <> 50
       or (select w.player_id from public.route_week_laps w
            where w.route_id = v_route and w.week = world.week_of()) is distinct from v_house
       or (select w.route_name from public.route_week_laps w
            where w.route_id = v_route and w.week = world.week_of()) is distinct from 'Rota 0275' then
      raise exception '0275 self-assert FAIL: the three laps did not land as two week rows with laps 2/1 and nets 1880/940';
    end if;
    -- the earnings reading: this week 1 lap / 940, last week 2 laps / 1,880; laps_done is the week's, the
    -- all-time figure kept beside it
    v_r := public.route_earnings(v_route);
    if (v_r->'week'->>'laps')::int <> 1 or (v_r->'week'->>'net')::bigint <> 940
       or (v_r->'week'->>'sold')::bigint <> 1000 or (v_r->'week'->>'wages')::bigint <> 50
       or (v_r->'last_week'->>'laps')::int <> 2 or (v_r->'last_week'->>'net')::bigint <> 1880
       or (v_r->>'laps_done')::int <> 1 or (v_r->>'laps_done_all')::int <> 3 then
      raise exception '0275 self-assert FAIL: route_earnings does not read the weeks: %', v_r;
    end if;
    -- the served route book carries the same earnings object (the face W4 prints from)
    perform cmd.assume_identity(v_house_uid);
    v_r := world.standing_routes();
    if (select count(*) from jsonb_array_elements(v_r->'routes') r
         where r->>'id' = v_route::text
           and (r->'earnings'->'week'->>'laps')::int = 1
           and (r->'earnings'->'last_week'->>'laps')::int = 2) <> 1 then
      raise exception '0275 self-assert FAIL: world.standing_routes does not serve the probe route''s week earnings';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    -- delete the probe route: the week rows remain (no cascade), the lap rows go as today
    delete from public.standing_routes where id = v_route;
    if (select count(*) from public.route_week_laps w where w.route_id = v_route) <> 2
       or (select count(*) from public.standing_route_laps x where x.route_id = v_route) <> 0 then
      raise exception '0275 self-assert FAIL: deleting the route did not keep the week rows and drop the lap rows';
    end if;
    raise exception 'PROBE_ROLLBACK_0275_LAPS';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0275_LAPS' then raise; end if;
  end;

  -- (e) THE PROBES LEFT NOTHING: every row they wrote went with its transaction, the two switches stand
  -- exactly where the world had them, and the books hold only what the live world held before this file.
  if (select count(*) from public.players) <> v_players
     or (select count(*) from public.city_week_book) <> v_book
     or (select count(*) from public.route_week_laps) <> v_lapbook
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from v_treas
     or (select value from public.world_config where key = 'influence_enabled') is distinct from v_infl then
    raise exception '0275 self-assert FAIL: a probe row or a switch write escaped its transaction (players % vs %, book % vs %, lap book % vs %, switches %/% vs %/%)',
      (select count(*) from public.players), v_players,
      (select count(*) from public.city_week_book), v_book,
      (select count(*) from public.route_week_laps), v_lapbook,
      (select value from public.world_config where key = 'city_treasury_enabled'), v_treas,
      (select value from public.world_config where key = 'influence_enabled'), v_infl;
  end if;

  raise notice '0275 self-assert ok: THE WEEK IS A KEY. The six bodies (pay_city, town_hall, close_lap, route_earnings, standing_routes, the registry) reverse to their pre-images hunk by hunk, ACLs unmoved, every other function in the four schemas unmoved (md5), exactly world.week_of / world.week_start / public.city_week_post / world.city_history minted, the registry +1 (city_history, authenticated only), the two books server-only under RLS, one writer each (pay_city alone, close_lap alone). The clock: week_of(anchor - 1 s) = -1, week_of(anchor) = 0, week_of(anchor + 7 d - 1 s) = 0, and now() stands inside its own week. The city book through the real doors: an Invest of % lands one SHARE row under the current week, two gifts add to one DONATION row of 1500 with gifts 2, the Town Hall board serves the probe at those figures, the History read folds the current week with them and an empty earlier one, and the events stream is untouched (the founding and the two verbs'' own). The lap book: three probe laps — two an hour apart before the boundary, one now — land as two week rows (laps 2/1, nets 1,880/940 to the ducat), route_earnings reads week / last_week / laps_done 1 with laps_done_all 3, the served route book carries the same object, and deleting the route keeps the week rows while the lap rows go. Rolled back.',
    v_cost;
end $$;
