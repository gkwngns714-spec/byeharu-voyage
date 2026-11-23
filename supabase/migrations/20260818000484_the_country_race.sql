-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0484 - THE COUNTRY RACE  (dark: the owner's switch nation_race_enabled, false; lit, the country picked at sign-up pays: a home perk of
--        cheaper dock fees at its harbours, its jobs (a city's requests in a contested harbour), and a weekly race for the contested cities,
--        shown on HQ and the map; the winner's top companies earn Reputation and the title Champion)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/roadmap-2026-11-23.md slice 15 ("Nations matter"); docs/design/hq-command-2026-11-23.md (every activity in HQ);
--   docs/dev-log/2026-11-23-country-race.md.
--
-- WHY: the owner, 2026-11-23: "i want this game to be strategical game, where all the work(activities) are done in HQ - words with
--   graphics. choosing best options available, finding best options." Slice 15: "the nation picked at sign-up gives a home perk (cheaper
--   dock fees at its ports), nation jobs, and a weekly influence race shown on the map (cities tinted by who leads). The top contributors of
--   the winning nation get Reputation and a title. Influence already exists; this makes it visible and paid."
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure is a knob):
--   THE RACE CITIES are the contested harbours (public.port_allegiance.home false: 210 of 254; a home city never changes hands, so it is no
--     race). The racers are the great powers that are not the pirates (public.great_powers, pirate false: ten). COMPANIES race; a merchant
--     house does not (it writes nothing and is read by one players probe), so a player's work is what moves the race.
--   THE WEEK runs Monday 00:00 UTC to Monday 00:00 UTC (public.nation_race_week: whole weeks since Monday 1970-01-05). Nothing resets: the
--     week is a key of the book, as 0275 taught.
--   THE BOOK public.nation_race_book (week, port, country, company) -> points: ONE writer, public.nation_race_post, from three existing
--     doors, each one hunk:
--       a SALE in a race city (cmd.do_sell's SOLD payload -> public.nation_race_sale): floor(the sale's total / nation_race_sale_per (100));
--         the SOLD event carries {race: {points}} so a card can say it;
--       a JOB, a city's request fulfilled in a race city (cmd.run_fulfil -> public.nation_race_job): floor(its bonus x nation_race_job_mult
--         (3) / 100), on top of the sale's own points;
--       a GIFT or a STAKE into a race city's purse (public.pay_city's SHARE/DONATION branch, beside the influence it already posts ->
--         public.nation_race_gift): floor(the coin x nation_race_gift_mult (10) / 100).
--     The company's country is read at the moment (0144's rule A2). Dark: one knob read, nothing written. A merchant: one players probe.
--   A CITY'S LEADER this week is the country with the most points there (ties: the country code): public.nation_race_leaders(week), the one
--     reader, composed by the board's marks, the read and the settle.
--   THE WEEKLY SETTLE (public.nation_race_settle(week), once a week, by the cron job byeharu-voyage:nation-race, hourly at :21; each run
--     settles at most ONE finished week and trims): the country that leads the most race cities wins (ties: its points, then its code); its
--     top nation_race_champions (3) companies by points that week each get nation_race_rep (200) Reputation (kind nation_race, keyed by the
--     week: once) and hold the title Champion until the next week settles. One row a week in public.nation_race_weeks (the leaders, the
--     countries, the champions). Book rows older than nation_race_keep_weeks (4) are deleted by the same run.
--   THE HOME PERK: a company's dock fee at a harbour her own country holds is nation_race_home_fee_cut (50 %) less, through THE ONE dock fee
--     (public.port_fee, one hunk -> public.nation_fee_factor), so the charge, the trip's figures and the town hall agree. Dark: 1.
--   HQ'S BOARD (public.hq_board_for, one hunk -> public.nation_race_marks): lit, a trade card that sells in a race city and a request card
--     in a race city carry race {points, lead}: the points the move would add for her country, and who leads that city this week ('mine',
--     'rival' or 'open'). The ranking is not changed. Dark: the moves as they were.
--   THE READ world.nation_race() (STABLE, registered): dark {"on": false}; lit, signed out or a merchant {"on": true, "company": false}; lit,
--     her company: the week and its end, every racing country's cities led and points, each race city's leader, her own points, her place
--     among her country's companies, her title, last week's winner and champions, the perk and the rates. The bridge and the map draw it.
-- ONE AUTHORITY EACH: the week, public.nation_race_week; a race city, public.nation_race_city; the points, public.nation_race_post; a
--   city's leader, public.nation_race_leaders; the settle, public.nation_race_settle; the perk, public.nation_fee_factor read by
--   public.port_fee alone; the marks, public.nation_race_marks; the page, world.nation_race(). Influence (port_influence, the daily count, the
--   flags) is not touched: a gift still posts influence exactly as before, and the race is a second book beside it.
-- NOT CHANGED: any price, any tax, the sale, the request, the gift, the influence posted, the flags, the board's ranking, a merchant, anyone
--   while dark.
-- ROWS. Dark: none. Lit: one upsert a counted act of a company (19 companies on prod; a merchant's sale writes nothing); a book row is one
--   (week, city, country, company): at most a few hundred a week. The settle: one week row, up to 3 Reputation rows, and the trim.
--   -- budget: one cron job hourly (byeharu-voyage:nation-race); dark 0 rows a run; lit 0 rows a run except the first of a week: one week row, up to 3 Reputation rows and the trimmed book rows (a few hundred at most)
--   -- retention: public.nation_race_book keeps nation_race_keep_weeks (4) weeks, trimmed by public.tick_nation_race; public.nation_race_weeks one row a week
-- COST. Dark: one knob read at a sale, a fulfil, a gift, a dock fee and a board read. Lit: a sale or a gift of a company one players probe,
--   one allegiance probe and one upsert; a merchant's one players probe; a dock fee one players probe and one allegiance probe; a board read
--   one aggregate over the week's book (hundreds of rows) and the 254 allegiance rows. Nothing on the arrivals beat.
-- LOCKS: CREATE TABLE x2 (new, no foreign key: one would lock public.players), CREATE FUNCTION x14, CREATE OR REPLACE x6 by hunks
--   (cmd.do_sell, cmd.run_fulfil, public.pay_city, public.port_fee, public.hq_board_for, public.client_rpc_entry_points), eight knobs, one
--   reputation kind, one cron job (where pg_cron is). TIME: a second or two. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above
--   45 s.
-- ROLLBACK (forward, owner only): QUICK, nation_race_enabled false (nothing is written, the payloads, the dock fee and the board are their
--   pre-images', the read is {"on": false}, the tick returns at once; the rows stay, inert). Full: a new migration unscheduling
--   byeharu-voyage:nation-race, reversing the six hunks (OLD texts below verbatim), dropping the functions and the two tables, deleting the
--   knobs and the reputation kind (its book rows stay: the book is append-only).
-- SELF-ASSERT: the hunks once each and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; the knobs; the kind; the reads STABLE; world.nation_race registered for authenticated alone; every core and the tick
--   server only; the tables no client's. THE PROBE (rolled back; deterministic: no time-budgeted read is asked (world.best_sales and
--   public.hq_board_for never: the marks are asked of a written list), every comparison of two figures is made in ONE SELECT, the book's
--   now() writes all fall in one week (one transaction, one now()), and every settle and tick names its week or its clock explicitly, so
--   nothing straddles a Monday): DARK a sale, a gift and a job write nothing and add nothing to the SOLD payload; the dock fee equals its
--   pre-image's; the marks are the moves; the read and the tick are {"on": false}. LIT a company's sale in a race city posts the payload's
--   points; her gift posts x10; a rival's job posts x3; a merchant writes nothing; the marks name the points and the leader; the dock fee at
--   her home harbour is the pre-image's halved and elsewhere the pre-image's; last week (written by hand) settles once: the winner, the
--   champion's Reputation once; the tick settles the week before its clock and trims; the read names her points, the leaders, last week's
--   winner and her title; signed out {"on": true, "company": false}. Proof 187 plays it further.
-- VERSION: 0484 = 0483 + 1 (prod head 0483; the board's and the registry's hunks are anchored on 0480's and 0483's own lines).
-- news: none (dark: nothing changes for a player until the owner lights nation_race_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- ── 0. GUARD, AND THE PRE-IMAGE (every function this file does not hunk or create: it must not move) ──
do $g$
begin
  if exists (select 1 from public.world_config where key = 'nation_race_enabled') or to_regclass('public.nation_race_book') is not null then
    raise exception '0484 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.hq_board_for(uuid)') is null or to_regprocedure('public.courier_moves(uuid,bigint)') is null
     or to_regprocedure('public.logbook_fee_factor(uuid,uuid)') is null or to_regprocedure('public.goods_mastery_sale(uuid,uuid,numeric)') is null
     or to_regprocedure('public.city_month_post(uuid,uuid,text,bigint)') is null or to_regprocedure('public.level_grant(uuid,text,numeric,text)') is null
     or to_regprocedure('public.reputation_credit(uuid,text,integer,text,jsonb)') is null or to_regclass('public.great_powers') is null
     or to_regclass('public.port_allegiance') is null then
    raise exception '0484 refuses: 0483, 0480, 0479, 0478, 0411, 0352, 0278, 0187 or 0143 is not in this world';
  end if;
  create temp table pre_0484 on commit drop as
    select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text)) as fns,
           (select md5(string_agg(q.oid::regprocedure::text || ':' || coalesce(q.proacl::text, '') || ':' || q.provolatile::text || q.prosecdef::text || coalesce(q.proconfig::text, '') || ':' || q.proowner::text, ',' order by q.oid::regprocedure::text))
              from pg_proc q
             where q.oid in ('cmd.do_sell(uuid,jsonb)'::regprocedure, 'cmd.run_fulfil(uuid,uuid)'::regprocedure, 'public.pay_city(uuid,uuid,text,bigint,uuid)'::regprocedure,
                             'public.port_fee(uuid,uuid,numeric)'::regprocedure, 'public.hq_board_for(uuid)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure)) as meta
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
       and p.oid not in ('cmd.do_sell(uuid,jsonb)'::regprocedure, 'cmd.run_fulfil(uuid,uuid)'::regprocedure, 'public.pay_city(uuid,uuid,text,bigint,uuid)'::regprocedure,
                         'public.port_fee(uuid,uuid,numeric)'::regprocedure, 'public.hq_board_for(uuid)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure);
  -- the dock fee as it is, kept for the probe's comparisons (a pg_temp copy, gone with the session)
  execute replace(replace(pg_get_functiondef('public.port_fee(uuid,uuid,numeric)'::regprocedure), E'\r', ''),
                  'FUNCTION public.port_fee(', 'FUNCTION pg_temp.port_fee_pre_0484(');
end
$g$;

-- ── 1. THE KNOBS AND THE REPUTATION KIND ──
insert into public.world_config (key, value, description) values
  ('nation_race_enabled', 'false'::jsonb,
   '0484: THE SWITCH (the owner''s). true: a company''s sales, city requests and gifts in the contested harbours count for her country in a weekly race (public.nation_race_book), her dock fee at her own country''s harbours is nation_race_home_fee_cut less, HQ''s cards say what a move adds, world.nation_race() serves the race, and the hourly job settles each finished week (Reputation and the title Champion for the winner''s top companies). false: nothing is written, the payloads, the dock fee and the board are as before, the read is {"on": false}.'),
  ('nation_race_sale_per', to_jsonb(100), '0484: the coin of a sale (its total) that makes one race point; a job''s bonus and a gift are counted against it too.'),
  ('nation_race_job_mult', to_jsonb(3), '0484: a city''s request fulfilled in a contested harbour (her country''s job): its bonus counts this many times, on top of the sale''s own points.'),
  ('nation_race_gift_mult', to_jsonb(10), '0484: a gift or a stake into a contested harbour''s purse counts this many times its coin.'),
  ('nation_race_home_fee_cut', to_jsonb(0.5), '0484: the home perk: a company''s dock fee at a harbour her own country holds is this share less (public.nation_fee_factor, read by public.port_fee).'),
  ('nation_race_champions', to_jsonb(3), '0484: how many of the winning country''s companies (most points that week) are its champions.'),
  ('nation_race_rep', to_jsonb(200), '0484: the Reputation each champion earns, once a week (kind nation_race, keyed by the week).'),
  ('nation_race_keep_weeks', to_jsonb(4), '0484: weeks of the race book kept; older rows are deleted by public.tick_nation_race.');
insert into public.reputation_kinds (code, sign, capped, word) values ('nation_race', 1, false, 'Country race');

-- ── 2. THE TABLES ──
-- retention: nation_race_keep_weeks (4): public.nation_race_book rows of older weeks are deleted by public.tick_nation_race
create table public.nation_race_book (
  week       bigint not null,
  port_id    uuid not null,
  nation_id  uuid not null,
  player_id  uuid not null,
  points     bigint not null check (points >= 0),
  updated_at timestamptz not null,
  primary key (week, port_id, nation_id, player_id)
);
alter table public.nation_race_book enable row level security;
revoke all on table public.nation_race_book from public, anon, authenticated;
comment on table public.nation_race_book is
  '0484: the country race''s book: a company''s points for her country in a contested harbour, by week (Monday 00:00 UTC). Written by public.nation_race_post alone; trimmed by public.tick_nation_race. Server only.';

-- retention: none, bounded by one row a week (52 a year): public.nation_race_weeks
create table public.nation_race_weeks (
  week       bigint primary key,
  winner     uuid,
  cities     jsonb not null,
  nations    jsonb not null,
  champions  jsonb not null,
  settled_at timestamptz not null
);
alter table public.nation_race_weeks enable row level security;
revoke all on table public.nation_race_weeks from public, anon, authenticated;
comment on table public.nation_race_weeks is
  '0484: one settled week of the country race: the winner, each race city''s leader, the countries, the champions. Written by public.nation_race_settle alone. Server only.';

-- ── 3. THE RULES ──
create function public.nation_race_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0484: THE one reader of nation_race_enabled.
  select public.wc('nation_race_enabled') = 'true'::jsonb
$$;

create function public.nation_race_week(p_at timestamptz)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0484: THE race's week: whole weeks since Monday 1970-01-05 00:00 UTC (epoch 345,600 s). A week runs Monday to Monday, UTC.
  select floor((extract(epoch from p_at) - 345600) / 604800)::bigint
$$;

create function public.nation_race_week_start(p_week bigint)
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0484: the Monday 00:00 UTC a race week starts at.
  select to_timestamp(345600 + p_week * 604800)
$$;

create function public.nation_race_city(p_port uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0484: THE one reader of "this harbour is raced for": a contested harbour (a home city never changes hands).
  select exists (select 1 from public.port_allegiance a join public.ports p on p.id = a.port_id
                  where a.port_id = p_port and not a.home and p.kind = 'HARBOUR')
$$;

create function public.nation_race_post(p_player uuid, p_port uuid, p_points bigint)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0484: THE ONE WRITER of the race book. Her country is read now (0144's A2). Dark, nothing (one knob read); a merchant, a company of no
-- racing country, a city that is not raced for, or no points: nothing. Answers the points posted.
declare
  v_nation uuid;
begin
  if coalesce(p_points, 0) <= 0 or p_player is null or p_port is null or not public.nation_race_on() then
    return 0;
  end if;
  select pl.nation_id into v_nation from public.players pl where pl.id = p_player and not pl.is_npc;
  if v_nation is null or not exists (select 1 from public.great_powers g where g.nation_id = v_nation and not g.pirate)
     or not public.nation_race_city(p_port) then
    return 0;
  end if;
  insert into public.nation_race_book as b (week, port_id, nation_id, player_id, points, updated_at)
  values (public.nation_race_week(now()), p_port, v_nation, p_player, p_points, now())
  on conflict (week, port_id, nation_id, player_id) do update set points = b.points + excluded.points, updated_at = excluded.updated_at;
  return p_points;
end
$body$;

create function public.nation_race_sale(p_player uuid, p_port uuid, p_total numeric)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0484: a SALE counts for her country (cmd.do_sell's SOLD payload): floor(total / nation_race_sale_per). Answers {race: {points}} when it
-- counted, else '{}'. Dark: one knob read. A merchant: one players probe, before any guarded block (no subtransaction on a merchant's sale).
-- Never raises: a fault is a warning and '{}', so a sale never fails here.
declare
  v_pts bigint;
begin
  if not public.nation_race_on() or p_player is null then
    return '{}'::jsonb;
  end if;
  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return '{}'::jsonb;
  end if;
  begin
    v_pts := public.nation_race_post(p_player, p_port, floor(greatest(coalesce(p_total, 0), 0) / greatest(public.wc_num('nation_race_sale_per'), 1))::bigint);
  exception when others then
    raise warning '0484 nation_race_sale: % (the sale stands)', sqlerrm;
    return '{}'::jsonb;
  end;
  return case when v_pts > 0 then jsonb_build_object('race', jsonb_build_object('points', v_pts)) else '{}'::jsonb end;
end
$body$;

create function public.nation_race_job(p_player uuid, p_port uuid, p_bonus bigint)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0484: a city's REQUEST fulfilled (cmd.run_fulfil) is a job for her country: floor(bonus x nation_race_job_mult / nation_race_sale_per),
-- on top of the sale's own points. Dark: one knob read. Never raises.
begin
  if not public.nation_race_on() or p_player is null then
    return 0;
  end if;
  return public.nation_race_post(p_player, p_port,
           floor(greatest(coalesce(p_bonus, 0), 0) * greatest(public.wc_num('nation_race_job_mult'), 0) / greatest(public.wc_num('nation_race_sale_per'), 1))::bigint);
exception when others then
  raise warning '0484 nation_race_job: % (the delivery stands)', sqlerrm;
  return 0;
end
$body$;

create function public.nation_race_gift(p_player uuid, p_port uuid, p_coin bigint)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0484: a GIFT or a STAKE into a city's purse (public.pay_city's SHARE/DONATION branch) counts for her country: floor(coin x
-- nation_race_gift_mult / nation_race_sale_per). Dark: one knob read. A merchant house (npc_invest): one players probe. Never raises.
begin
  if not public.nation_race_on() or p_player is null then
    return 0;
  end if;
  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  return public.nation_race_post(p_player, p_port,
           floor(greatest(coalesce(p_coin, 0), 0) * greatest(public.wc_num('nation_race_gift_mult'), 0) / greatest(public.wc_num('nation_race_sale_per'), 1))::bigint);
exception when others then
  raise warning '0484 nation_race_gift: % (the gift stands)', sqlerrm;
  return 0;
end
$body$;

create function public.nation_fee_factor(p_player uuid, p_port uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0484: THE HOME PERK, as a factor on the dock fee (read by public.port_fee alone, so every reader of the fee agrees): at a harbour her own
-- country holds, (1 - nation_race_home_fee_cut). Dark: 1 after one knob read; a merchant, nobody, a company of no country, a city she does
-- not hold: 1.
declare
  v_nation uuid;
begin
  if not public.nation_race_on() or p_player is null then
    return 1;
  end if;
  select pl.nation_id into v_nation from public.players pl where pl.id = p_player and not pl.is_npc;
  if v_nation is null or public.port_nation(p_port) is distinct from v_nation then
    return 1;
  end if;
  return 1 - least(1, greatest(0, coalesce(public.wc_num('nation_race_home_fee_cut'), 0)));
end
$body$;

create function public.nation_race_leaders(p_week bigint)
returns table (port_id uuid, nation_id uuid, points bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0484: THE one reader of a race city's leader in a week: the country with the most points there (ties: the country code).
  select distinct on (t.port_id) t.port_id, t.nation_id, t.points
    from (select b.port_id, b.nation_id, sum(b.points)::bigint as points
            from public.nation_race_book b where b.week = p_week group by b.port_id, b.nation_id) t
    join public.nations n on n.id = t.nation_id
   where t.points > 0
   order by t.port_id, t.points desc, n.code
$$;

create function public.nation_race_standings(p_week bigint)
returns table (nation_id uuid, code text, cities int, points bigint, place int)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0484: every racing country (a great power, not the pirates) in a week: the race cities it leads and its points, in the race's order
  -- (the most cities, then the most points, then the code). The read and the settle compose it.
  select s.nation_id, s.code, s.cities, s.points,
         (row_number() over (order by s.cities desc, s.points desc, s.code))::int as place
    from (select g.nation_id, n.code,
                 (select count(*) from public.nation_race_leaders(p_week) l where l.nation_id = g.nation_id)::int as cities,
                 coalesce((select sum(b.points) from public.nation_race_book b where b.week = p_week and b.nation_id = g.nation_id), 0)::bigint as points
            from public.great_powers g join public.nations n on n.id = g.nation_id
           where not g.pirate) s
$$;

create function public.nation_race_marks(p_player uuid, p_moves jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0484: HQ'S CARDS SAY WHAT A MOVE ADDS FOR HER COUNTRY (public.hq_board_for, one hunk). Lit, her company of a racing country: a trade
-- card selling in a race city (needs.to) and a request card in one (at) gain race {points, lead}: the points (a trade: floor((cost +
-- profit) / nation_race_sale_per), the sale's total; a request: the sale's part of its net and its bonus x nation_race_job_mult), and
-- who leads that city this week ('mine', 'rival', or 'open' when nobody has scored there). Every other card, and the order, as they were.
-- Dark: p_moves after one knob read.
declare
  v_nation uuid;
  v_code   text;
  v_per    numeric;
  v_mult   numeric;
  v_cities jsonb;
  v_lead   jsonb;
begin
  if not public.nation_race_on() or p_player is null or jsonb_typeof(p_moves) is distinct from 'array' or jsonb_array_length(p_moves) = 0 then
    return p_moves;
  end if;
  select pl.nation_id, n.code into v_nation, v_code
    from public.players pl join public.nations n on n.id = pl.nation_id
    join public.great_powers g on g.nation_id = pl.nation_id and not g.pirate
   where pl.id = p_player and not pl.is_npc;
  if v_nation is null then
    return p_moves;
  end if;
  v_per := greatest(public.wc_num('nation_race_sale_per'), 1);
  v_mult := greatest(public.wc_num('nation_race_job_mult'), 0);
  select coalesce(jsonb_object_agg(p.code, true), '{}'::jsonb) into v_cities
    from public.port_allegiance a join public.ports p on p.id = a.port_id where not a.home and p.kind = 'HARBOUR';
  select coalesce(jsonb_object_agg(p.code, n.code), '{}'::jsonb) into v_lead
    from public.nation_race_leaders(public.nation_race_week(now())) l join public.ports p on p.id = l.port_id join public.nations n on n.id = l.nation_id;
  return (
    select coalesce(jsonb_agg(case when r.city is not null and r.pts > 0
                                   then m.e || jsonb_build_object('race', jsonb_build_object(
                                          'points', r.pts,
                                          'lead', case when v_lead ? r.city then case when v_lead->>r.city = v_code then 'mine' else 'rival' end else 'open' end))
                                   else m.e end order by m.i), '[]'::jsonb)
      from jsonb_array_elements(p_moves) with ordinality m(e, i)
     cross join lateral (
       select case when m.e->>'kind' = 'trade' and v_cities ? coalesce(m.e #>> '{needs,to}', '') then m.e #>> '{needs,to}'
                   when m.e->>'kind' = 'request' and v_cities ? coalesce(m.e->>'at', '') then m.e->>'at' end as city,
              case m.e->>'kind'
                when 'trade' then floor((coalesce((m.e #>> '{needs,cost}')::numeric, 0) + greatest(coalesce((m.e->>'profit')::numeric, 0), 0)) / v_per)::bigint
                when 'request' then (floor(greatest(coalesce((m.e->>'profit')::numeric, 0) - coalesce((m.e #>> '{needs,bonus}')::numeric, 0), 0) / v_per)
                                     + floor(coalesce((m.e #>> '{needs,bonus}')::numeric, 0) * v_mult / v_per))::bigint
                else 0 end as pts) r);
end
$body$;

create function public.nation_race_settle(p_week bigint, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0484: THE ONE SETTLER of a race week, once (a settled week answers {"settled": false}): the winner (the most race cities led, then the
-- points, then the code; none when nobody scored), its top nation_race_champions companies by points that week, each paid nation_race_rep
-- Reputation (kind nation_race, keyed by the week: once), and one row in public.nation_race_weeks.
declare
  v_winner uuid;
  v_wcode  text;
  v_cities jsonb;
  v_nats   jsonb;
  v_champs jsonb := '[]'::jsonb;
  c        record;
  v_rep    int;
begin
  if exists (select 1 from public.nation_race_weeks w where w.week = p_week) then
    return jsonb_build_object('settled', false, 'week', p_week);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('port', p.code, 'nation', n.code, 'points', l.points) order by p.code), '[]'::jsonb) into v_cities
    from public.nation_race_leaders(p_week) l join public.ports p on p.id = l.port_id join public.nations n on n.id = l.nation_id;
  select coalesce(jsonb_agg(jsonb_build_object('nation', s.code, 'cities', s.cities, 'points', s.points, 'place', s.place) order by s.place), '[]'::jsonb)
    into v_nats from public.nation_race_standings(p_week) s;
  select s.nation_id, s.code into v_winner, v_wcode from public.nation_race_standings(p_week) s where s.place = 1 and s.points > 0;
  if v_winner is not null then
    for c in
      select b.player_id, pl.company_name, sum(b.points)::bigint as points
        from public.nation_race_book b join public.players pl on pl.id = b.player_id
       where b.week = p_week and b.nation_id = v_winner and not pl.is_npc
       group by b.player_id, pl.company_name
       order by sum(b.points) desc, b.player_id
       limit greatest(coalesce(public.wc_int('nation_race_champions'), 3), 0)
    loop
      v_rep := public.reputation_credit(c.player_id, 'nation_race', greatest(coalesce(public.wc_int('nation_race_rep'), 0), 0),
                                        'nation_race:' || p_week, jsonb_build_object('week', p_week, 'nation', v_wcode, 'points', c.points));
      v_champs := v_champs || jsonb_build_array(jsonb_build_object('player', c.player_id, 'name', c.company_name, 'points', c.points, 'rep', v_rep));
    end loop;
  end if;
  insert into public.nation_race_weeks (week, winner, cities, nations, champions, settled_at)
  values (p_week, v_winner, v_cities, v_nats, v_champs, p_now);
  return jsonb_build_object('settled', true, 'week', p_week, 'winner', v_wcode, 'cities', jsonb_array_length(v_cities), 'champions', jsonb_array_length(v_champs));
end
$body$;

create function public.tick_nation_race(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0484: THE JOB (pg_cron byeharu-voyage:nation-race, hourly at :21). Dark: {"on": false} after one knob read. Lit: the week before
-- p_now's is settled when it is not yet (public.nation_race_settle; at most ONE week a run), and the book's weeks older than
-- nation_race_keep_weeks are deleted. Bounded: one settle and one indexed delete a run.
declare
  v_week bigint;
  v_r    jsonb;
  v_trim int := 0;
begin
  if not public.nation_race_on() then
    return jsonb_build_object('on', false);
  end if;
  perform set_config('lock_timeout', '2s', true);
  v_week := public.nation_race_week(p_now) - 1;
  if not exists (select 1 from public.nation_race_weeks w where w.week = v_week) then
    v_r := public.nation_race_settle(v_week, p_now);
  end if;
  delete from public.nation_race_book b where b.week < v_week + 1 - greatest(coalesce(public.wc_int('nation_race_keep_weeks'), 4), 1);
  get diagnostics v_trim = row_count;
  return jsonb_build_object('on', true, 'week', v_week, 'settled', v_r, 'trimmed', v_trim);
end
$body$;

create function world.nation_race()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0484: THE COUNTRY RACE, the client's one door. Dark {"on": false}; lit, signed out or a merchant {"on": true, "company": false}; lit, her
-- company: this week (its end), every racing country (cities led, points, place), each race city's leader, her own points and her place
-- among her country's companies, last week's winner and champions, her title (a champion of last week), the perk and the rates. Writes
-- nothing.
declare
  v_me     uuid := public.current_player_id();
  v_nation uuid;
  v_code   text;
  v_week   bigint := public.nation_race_week(now());
  v_mine   bigint;
  v_place  int;
  v_last   public.nation_race_weeks%rowtype;
begin
  if not public.nation_race_on() then
    return jsonb_build_object('on', false);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('on', true, 'company', false);
  end if;
  select pl.nation_id, n.code into v_nation, v_code from public.players pl left join public.nations n on n.id = pl.nation_id where pl.id = v_me;
  select coalesce(sum(b.points), 0)::bigint into v_mine from public.nation_race_book b where b.week = v_week and b.player_id = v_me and b.nation_id = v_nation;
  if v_mine > 0 then
    select 1 + count(*) into v_place
      from (select b.player_id from public.nation_race_book b where b.week = v_week and b.nation_id = v_nation and b.player_id <> v_me
             group by b.player_id having sum(b.points) > v_mine) o;
  end if;
  select * into v_last from public.nation_race_weeks w where w.week < v_week order by w.week desc limit 1;
  return jsonb_build_object(
    'on', true, 'company', true,
    'week', v_week, 'starts_at', public.nation_race_week_start(v_week), 'ends_at', public.nation_race_week_start(v_week + 1),
    'nations', (select coalesce(jsonb_agg(jsonb_build_object('nation', s.code, 'cities', s.cities, 'points', s.points, 'place', s.place) order by s.place), '[]'::jsonb)
                  from public.nation_race_standings(v_week) s),
    'cities', (select coalesce(jsonb_agg(jsonb_build_object('port', p.code, 'nation', n.code, 'points', l.points) order by p.code), '[]'::jsonb)
                 from public.nation_race_leaders(v_week) l join public.ports p on p.id = l.port_id join public.nations n on n.id = l.nation_id),
    'mine', jsonb_build_object('nation', v_code, 'points', v_mine, 'place', v_place,
                               'racing', exists (select 1 from public.great_powers g where g.nation_id = v_nation and not g.pirate)),
    'title', case when v_last.week is not null and exists (select 1 from jsonb_array_elements(v_last.champions) c where c->>'player' = v_me::text)
                  then jsonb_build_object('week', v_last.week, 'nation', (select n.code from public.nations n where n.id = v_last.winner)) end,
    'last', case when v_last.week is not null then jsonb_build_object(
              'week', v_last.week, 'winner', (select n.code from public.nations n where n.id = v_last.winner),
              'champions', (select coalesce(jsonb_agg(jsonb_build_object('name', c->>'name', 'points', (c->>'points')::bigint) order by o), '[]'::jsonb)
                              from jsonb_array_elements(v_last.champions) with ordinality x(c, o))) end,
    'perk', jsonb_build_object('fee_cut', public.wc_num('nation_race_home_fee_cut')),
    'rates', jsonb_build_object('sale_per', public.wc_num('nation_race_sale_per'), 'job_mult', public.wc_num('nation_race_job_mult'),
                                'gift_mult', public.wc_num('nation_race_gift_mult')));
end
$body$;

revoke all on function public.nation_race_on() from public, anon, authenticated;
revoke all on function public.nation_race_week(timestamptz) from public, anon, authenticated;
revoke all on function public.nation_race_week_start(bigint) from public, anon, authenticated;
revoke all on function public.nation_race_city(uuid) from public, anon, authenticated;
revoke all on function public.nation_race_post(uuid, uuid, bigint) from public, anon, authenticated;
revoke all on function public.nation_race_sale(uuid, uuid, numeric) from public, anon, authenticated;
revoke all on function public.nation_race_job(uuid, uuid, bigint) from public, anon, authenticated;
revoke all on function public.nation_race_gift(uuid, uuid, bigint) from public, anon, authenticated;
revoke all on function public.nation_fee_factor(uuid, uuid) from public, anon, authenticated;
revoke all on function public.nation_race_leaders(bigint) from public, anon, authenticated;
revoke all on function public.nation_race_standings(bigint) from public, anon, authenticated;
revoke all on function public.nation_race_marks(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.nation_race_settle(bigint, timestamptz) from public, anon, authenticated;
revoke all on function public.tick_nation_race(timestamptz) from public, anon, authenticated;
revoke all on function world.nation_race() from public, anon;
grant execute on function world.nation_race() to authenticated;
comment on function world.nation_race() is
  '0484: the country race (dark {"on": false}): this week''s countries and race cities, her points, place and title, last week''s winner. A read. Client door.';

-- ── 4. THE HUNKS, THE SELF-ASSERT, THE PROBE, THE JOB ──
do $m$
declare
  c_hunked constant text[] := array['cmd.do_sell(uuid,jsonb)', 'cmd.run_fulfil(uuid,uuid)', 'public.pay_city(uuid,uuid,text,bigint,uuid)',
                                    'public.port_fee(uuid,uuid,numeric)', 'public.hq_board_for(uuid)', 'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.nation_race_on()', 'public.nation_race_week(timestamptz)', 'public.nation_race_week_start(bigint)',
                                    'public.nation_race_city(uuid)', 'public.nation_race_post(uuid,uuid,bigint)', 'public.nation_race_sale(uuid,uuid,numeric)',
                                    'public.nation_race_job(uuid,uuid,bigint)', 'public.nation_race_gift(uuid,uuid,bigint)', 'public.nation_fee_factor(uuid,uuid)',
                                    'public.nation_race_leaders(bigint)', 'public.nation_race_standings(bigint)', 'public.nation_race_marks(uuid,jsonb)',
                                    'public.nation_race_settle(bigint,timestamptz)', 'public.tick_nation_race(timestamptz)', 'world.nation_race()'];
  c_ua     constant uuid := '00000000-0484-4000-8000-0000000000a1';
  c_ub     constant uuid := '00000000-0484-4000-8000-0000000000b1';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_note      text := '';
  v_lived     boolean := false;
  v_w0        bigint := public.nation_race_week(now());
  v_a         uuid;
  v_b         uuid;
  v_fa        uuid;
  v_c1        uuid;
  v_c1code    text;
  v_c2        uuid;
  v_home      uuid;
  v_homecode  text;
  v_else      uuid;
  v_good      uuid;
  v_house     uuid;
  v_r         jsonb;
  v_sold      jsonb;
  v_pts       bigint;
  v_moves     jsonb;
  v_f         record;
  v_tick      jsonb;
  v_read      jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0484 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0484 values
  ('cmd.do_sell(uuid,jsonb)', 1,
$h$      || public.goods_mastery_sale(f.player_id, g.id, q.units)));$h$,
$h$      || public.goods_mastery_sale(f.player_id, g.id, q.units)
      -- 0484: the country race: a company's sale in a contested harbour counts for her country (race {points}; '{}' dark, a merchant, elsewhere)
      || public.nation_race_sale(f.player_id, f.port_id, q.total)));$h$),
  ('cmd.run_fulfil(uuid,uuid)', 1,
$h$  perform public.level_grant(f.player_id, 'request', v_pay);$h$,
$h$  perform public.level_grant(f.player_id, 'request', v_pay);
  -- 0484: a request in a contested harbour is a job for her country: its bonus counts nation_race_job_mult times (public.nation_race_job; dark nothing)
  perform public.nation_race_job(f.player_id, c.port_id, v_pay);$h$),
  ('public.pay_city(uuid,uuid,text,bigint,uuid)', 1,
$h$    perform public.city_month_post(p_player, p_port, p_kind, p_amount);$h$,
$h$    perform public.city_month_post(p_player, p_port, p_kind, p_amount);
    -- 0484: and, in a contested harbour, for her country's weekly race (public.nation_race_gift; dark and for a merchant nothing)
    perform public.nation_race_gift(p_player, p_port, p_amount);$h$),
  ('public.port_fee(uuid,uuid,numeric)', 1,
$h$                           * public.logbook_fee_factor(p_player, p_port)))::bigint;$h$,
$h$                           * public.logbook_fee_factor(p_player, p_port)
                           -- 0484: the home perk at her own country's harbours (public.nation_fee_factor: 1 dark, for a merchant, elsewhere)
                           * public.nation_fee_factor(p_player, p_port)))::bigint;$h$),
  ('public.hq_board_for(uuid)', 1,
$h$  return jsonb_build_object(
    -- THE RANKING: the one rule (0480's header): the band, then coin an hour, then the profit, then the id$h$,
$h$  -- 0484 (nation_race_enabled): a trade or request card in a contested harbour says what it adds for her country and who leads there
  -- (public.nation_race_marks; dark the moves as they are). The ranking is not changed.
  v_moves := public.nation_race_marks(p_player, v_moves);

  return jsonb_build_object(
    -- THE RANKING: the one rule (0480's header): the band, then coin an hour, then the profit, then the id$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'courier_contracts',     ''),$h$,
$h$      ('world',       'courier_contracts',     ''),
      -- 0484: the country race (dark: {"on": false})
      ('world',       'nation_race',           ''),$h$);

  for v_h in select h.fn from hunks_0484 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0484 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0484 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0484 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0484 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0484 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── SELF-ASSERT: the catalog, the knobs, the doors ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) is distinct from (select pre.fns from pre_0484 pre) then
    raise exception '0484 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(q.oid::regprocedure::text || ':' || coalesce(q.proacl::text, '') || ':' || q.provolatile::text || q.prosecdef::text || coalesce(q.proconfig::text, '') || ':' || q.proowner::text, ',' order by q.oid::regprocedure::text))
        from pg_proc q where q.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q))))
     is distinct from (select pre.meta from pre_0484 pre) then
    raise exception '0484 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select count(*) from pg_proc p
       where p.oid = any (array['public.nation_race_on()', 'public.nation_race_week(timestamptz)', 'public.nation_race_week_start(bigint)',
                                'public.nation_race_city(uuid)', 'public.nation_fee_factor(uuid,uuid)', 'public.nation_race_leaders(bigint)',
                                'public.nation_race_standings(bigint)', 'public.nation_race_marks(uuid,jsonb)', 'world.nation_race()']::regprocedure[]::oid[])
         and p.provolatile = 's') <> 9 then
    raise exception '0484 self-assert FAIL: a read is not STABLE (the switch, the week, the city, the factor, the leaders, the standings, the marks and the read are reads)';
  end if;
  if public.wc('nation_race_enabled') <> 'false'::jsonb or public.wc_int('nation_race_sale_per') <> 100 or public.wc_int('nation_race_job_mult') <> 3
     or public.wc_int('nation_race_gift_mult') <> 10 or public.wc_num('nation_race_home_fee_cut') <> 0.5 or public.wc_int('nation_race_champions') <> 3
     or public.wc_int('nation_race_rep') <> 200 or public.wc_int('nation_race_keep_weeks') <> 4
     or (select count(*) from public.world_config c where c.key like 'nation\_race\_%') <> 8
     or not exists (select 1 from public.reputation_kinds k where k.code = 'nation_race' and k.sign = 1 and not k.capped) then
    raise exception '0484 self-assert FAIL: the knobs or the reputation kind are not as written';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) = ('world', 'nation_race', '')
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 1
     or exists (select 1 from unnest(c_new) u(q)
                 where u.q <> 'world.nation_race()'
                   and (has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                        or has_function_privilege('service_role', u.q::regprocedure, 'execute')))
     or has_table_privilege('authenticated', 'public.nation_race_book', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.nation_race_book', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.nation_race_weeks', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.nation_race_weeks', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.nation_race_book'::regclass)
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.nation_race_weeks'::regclass)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0484 self-assert FAIL: the read is not registered for authenticated alone, a core or the tick is reachable by a client, or a table is';
  end if;
  if public.nation_race_week('2026-11-23 00:00:00+00'::timestamptz) <> public.nation_race_week('2026-11-29 23:59:59+00'::timestamptz)
     or public.nation_race_week('2026-11-30 00:00:00+00'::timestamptz) <> public.nation_race_week('2026-11-23 00:00:00+00'::timestamptz) + 1
     or public.nation_race_week_start(public.nation_race_week('2026-11-25 12:00:00+00'::timestamptz)) <> '2026-11-23 00:00:00+00'::timestamptz then
    raise exception '0484 self-assert FAIL: the race week is not Monday 00:00 UTC to Monday 00:00 UTC';
  end if;

  -- ── THE PROBE, rolled back by a raised sentinel (no time-budgeted read is asked; every comparison of two figures is one SELECT) ──
  begin
    -- the places: two contested harbours with a purse (the first by code with a good she may sell there), a home harbour of Portugal with a
    -- purse, and a harbour with a purse Portugal does not hold
    select p.id, p.code, g.id into v_c1, v_c1code, v_good
      from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
      join public.port_treasury t on t.port_id = p.id
      cross join lateral (select gg.id from public.port_goods pg join public.goods gg on gg.id = pg.good_id
                           where pg.port_id = p.id and gg.bulk > 0 and not public.culture_refuses(p.culture, gg.culture_mask)
                           order by gg.bulk, gg.code limit 1) g
     where not a.home
     order by p.code limit 1;
    select p.id into v_c2
      from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
     where not a.home and p.id <> v_c1 order by p.code limit 1;
    select p.id, p.code into v_home, v_homecode
      from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' join public.port_treasury t on t.port_id = p.id
     where a.home and a.nation_id = (select n.id from public.nations n where n.code = 'PRT') order by p.code limit 1;
    select p.id into v_else
      from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' join public.port_treasury t on t.port_id = p.id
     where a.nation_id is distinct from (select n.id from public.nations n where n.code = 'PRT') and not public.port_is_free(p.id)
     order by p.code limit 1;
    select h.player_id into v_house from public.npc_houses h join public.players p on p.id = h.player_id order by h.roster_ord limit 1;
    if v_c1 is null or v_c2 is null or v_home is null or v_else is null or v_good is null or v_house is null then
      raise exception '0484 self-assert FAIL: the world has no contested harbour with a purse and a good, no Portuguese home with a purse, no other purse or no house (% % % % %)',
        v_c1code, v_c2, v_homecode, v_else, v_house;
    end if;
    -- the founding and the sale's path as the local chain has them (the purses and the closed economy set dark inside the probe: no capital
    -- pays a founding, no city is broke), and the dock fee's as prod has it (set lit where it is compared)
    update public.world_config set value = 'false'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
    v_a := public.new_house(c_ua, 'Casa da Coroa 0484', 'PRT');
    v_b := public.new_house(c_ub, 'Casa del Rey 0484', 'ESP');
    select f.id into v_fa from public.fleets f where f.player_id = v_a;
    update public.players p set ducats = 200000 where p.id in (v_a, v_b);
    update public.fleets set status = 'DOCKED', port_id = v_c1 where id = v_fa;

    -- (a) DARK: a sale, a gift and a job write nothing and add nothing; the marks are the moves; the read and the tick are {"on": false}
    perform public.fleet_load(v_fa, (select g.code from public.goods g where g.id = v_good), 20, 1);
    v_r := cmd.do_sell(v_fa, jsonb_build_object('good', v_good, 'qty', 10));
    select e.payload into v_sold from public.events e where e.player_id = v_a and e.kind = 'SOLD' order by e.created_at desc, e.id limit 1;
    v_moves := jsonb_build_array(jsonb_build_object('id', 't1', 'kind', 'trade', 'profit', 600, 'needs', jsonb_build_object('to', v_c1code, 'cost', 900)));
    if v_sold is null or v_sold ? 'race'
       or public.nation_race_gift(v_a, v_c1, 1000) <> 0 or public.nation_race_job(v_b, v_c1, 500) <> 0
       or public.nation_race_marks(v_a, v_moves) <> v_moves
       or world.nation_race() is distinct from '{"on": false}'::jsonb
       or public.tick_nation_race(public.nation_race_week_start(v_w0 + 1) + interval '1 hour') is distinct from '{"on": false}'::jsonb
       or exists (select 1 from public.nation_race_book) or exists (select 1 from public.nation_race_weeks) then
      raise exception '0484 self-assert FAIL: dark, the race moved (sale %, read %)', v_sold, world.nation_race();
    end if;
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
    for v_f in select public.port_fee(v_home, v_a, 100000) as now_home, pg_temp.port_fee_pre_0484(v_home, v_a, 100000) as pre_home,
                      public.port_fee(v_else, v_a, 100000) as now_else, pg_temp.port_fee_pre_0484(v_else, v_a, 100000) as pre_else loop
      if v_f.pre_home <= 0 or v_f.now_home <> v_f.pre_home or v_f.now_else <> v_f.pre_else then
        raise exception '0484 self-assert FAIL: dark, the dock fee moved (home % / %, elsewhere % / %)', v_f.now_home, v_f.pre_home, v_f.now_else, v_f.pre_else;
      end if;
    end loop;
    update public.world_config set value = 'false'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
    update public.world_config set value = 'true'::jsonb where key = 'nation_race_enabled';

    -- (b) LIT: her sale in a race city posts the payload's points; her gift x10; a rival's job x3; a merchant nothing
    v_r := cmd.do_sell(v_fa, jsonb_build_object('good', v_good, 'qty', 10));
    select e.payload into v_sold from public.events e where e.player_id = v_a and e.kind = 'SOLD' order by e.created_at desc, (e.payload ? 'race') desc limit 1;
    v_pts := floor((v_sold->>'total')::numeric / 100);
    if v_pts > 0 and ((v_sold #>> '{race,points}')::bigint is distinct from v_pts
                      or (select b.points from public.nation_race_book b where b.week = v_w0 and b.port_id = v_c1 and b.player_id = v_a) <> v_pts) then
      raise exception '0484 self-assert FAIL: lit, her sale of % did not post % points: %', v_sold->>'total', v_pts, v_sold;
    end if;
    if v_pts = 0 and v_sold ? 'race' then
      raise exception '0484 self-assert FAIL: a sale under one point posted: %', v_sold;
    end if;
    -- each write its own statement (an OR's terms run in no promised order), then the book read
    v_r := jsonb_build_array(public.nation_race_gift(v_a, v_c1, 1000), public.nation_race_job(v_b, v_c1, 500));
    v_r := v_r || jsonb_build_array(public.nation_race_sale(v_house, v_c1, 100000), public.nation_race_gift(v_house, v_c1, 100000));
    v_r := v_r || jsonb_build_array(public.nation_race_gift(v_a, v_home, 1000));
    if v_r <> '[100, 15, {}, 0, 0]'::jsonb
       or exists (select 1 from public.nation_race_book b where b.player_id = v_house or b.port_id = v_home)
       or (select b.points from public.nation_race_book b where b.week = v_w0 and b.port_id = v_c1 and b.player_id = v_a) <> v_pts + 100
       or (select b.points from public.nation_race_book b where b.week = v_w0 and b.port_id = v_c1 and b.player_id = v_b
             and b.nation_id = (select n.id from public.nations n where n.code = 'ESP')) <> 15 then
      raise exception '0484 self-assert FAIL: lit, the gift, the job or a merchant did not post as written: %',
        (select jsonb_agg(to_jsonb(b)) from public.nation_race_book b);
    end if;
    -- the gift's door: public.pay_city's DONATION posts it (and influence, as before)
    perform public.pay_city(v_a, v_c2, 'DONATION', 2000, null);
    if (select b.points from public.nation_race_book b where b.week = v_w0 and b.port_id = v_c2 and b.player_id = v_a) <> 200 then
      raise exception '0484 self-assert FAIL: a gift through public.pay_city did not post x10';
    end if;

    -- (c) THE MARKS: a trade card to the race city (the sale's total), one to her home (none), a request (sale part + bonus x3), a yard card as
    --     it was; who leads (hers for her, the rival's for him)
    v_moves := jsonb_build_array(
      jsonb_build_object('id', 't1', 'kind', 'trade', 'profit', 600, 'needs', jsonb_build_object('to', v_c1code, 'cost', 900)),
      jsonb_build_object('id', 't2', 'kind', 'trade', 'profit', 600, 'needs', jsonb_build_object('to', v_homecode, 'cost', 900)),
      jsonb_build_object('id', 'r1', 'kind', 'request', 'at', v_c1code, 'profit', 1000, 'needs', jsonb_build_object('bonus', 200)),
      jsonb_build_object('id', 'y1', 'kind', 'yard', 'profit', null, 'needs', jsonb_build_object('cost', 5000)));
    v_r := public.nation_race_marks(v_a, v_moves);
    if v_r->0->'race' is distinct from '{"points": 15, "lead": "mine"}'::jsonb or v_r->1 ? 'race'
       or v_r->2->'race' is distinct from '{"points": 14, "lead": "mine"}'::jsonb or v_r->3 <> v_moves->3
       or (select array_agg(e->>'id' order by o) from jsonb_array_elements(v_r) with ordinality z(e, o)) <> array['t1', 't2', 'r1', 'y1']
       or public.nation_race_marks(v_b, v_moves)->0->'race'->>'lead' <> 'rival' then
      raise exception '0484 self-assert FAIL: the marks are not as written: %', v_r;
    end if;

    -- (d) THE HOME PERK: at her home harbour the fee is the pre-image's halved, elsewhere the pre-image's; his (Castile's) at her home as it was
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
    for v_f in select public.port_fee(v_home, v_a, 100000) as now_home, pg_temp.port_fee_pre_0484(v_home, v_a, 100000) as pre_home,
                      public.port_fee(v_else, v_a, 100000) as now_else, pg_temp.port_fee_pre_0484(v_else, v_a, 100000) as pre_else,
                      public.port_fee(v_home, v_b, 100000) as now_his, pg_temp.port_fee_pre_0484(v_home, v_b, 100000) as pre_his loop
      if v_f.pre_home < 4 or abs(v_f.now_home * 2 - v_f.pre_home) > 2 or v_f.now_home >= v_f.pre_home
         or v_f.now_else <> v_f.pre_else or v_f.now_his <> v_f.pre_his then
        raise exception '0484 self-assert FAIL: the home perk is not half at home and nothing elsewhere (home % / %, elsewhere % / %, his % / %)',
          v_f.now_home, v_f.pre_home, v_f.now_else, v_f.pre_else, v_f.now_his, v_f.pre_his;
      end if;
      v_note := format('fee at home %s -> %s', v_f.pre_home, v_f.now_home);
    end loop;
    update public.world_config set value = 'false'::jsonb where key in ('city_treasury_enabled', 'economy_closed');

    -- (e) LAST WEEK (written by hand): C1 Portugal 300 / Castile 100, C2 Portugal 50 / Castile 200: one city each, Portugal on points;
    --     she is its one champion, paid once
    insert into public.nation_race_book (week, port_id, nation_id, player_id, points, updated_at)
    select v_w0 - 1, z.port, (select n.id from public.nations n where n.code = z.nat), z.pl, z.pts, now()
      from (values (v_c1, 'PRT', v_a, 300), (v_c2, 'PRT', v_a, 50), (v_c1, 'ESP', v_b, 100), (v_c2, 'ESP', v_b, 200)) z(port, nat, pl, pts);
    v_r := public.nation_race_settle(v_w0 - 1, now());
    v_tick := public.nation_race_settle(v_w0 - 1, now());   -- again: nothing
    if v_r->>'winner' <> 'PRT' or (v_r->>'cities')::int <> 2 or (v_r->>'champions')::int <> 1
       or (select jsonb_array_length(w.champions) from public.nation_race_weeks w where w.week = v_w0 - 1) <> 1
       or (select (w.champions->0->>'player')::uuid from public.nation_race_weeks w where w.week = v_w0 - 1) <> v_a
       or (select count(*) from public.reputation_book rb where rb.player_id = v_a and rb.key = 'nation_race:' || (v_w0 - 1))
          <> (case when public.wc('reputation_on') = 'true'::jsonb then 1 else 0 end)
       or exists (select 1 from public.reputation_book rb where rb.player_id = v_b and rb.kind = 'nation_race')
       or (v_tick->>'settled')::boolean
       or (select count(*) from public.reputation_book rb where rb.player_id = v_a and rb.kind = 'nation_race')
          <> (case when public.wc('reputation_on') = 'true'::jsonb then 1 else 0 end) then
      raise exception '0484 self-assert FAIL: last week did not settle once for Portugal with her as champion: % / %', v_r,
        (select to_jsonb(w) from public.nation_race_weeks w where w.week = v_w0 - 1);
    end if;

    -- (f) THE TICK at next week's Monday 01:00 settles this week (Portugal leads C1 and C2) and trims a book row 10 weeks old; again, nothing
    insert into public.nation_race_book (week, port_id, nation_id, player_id, points, updated_at)
    values (v_w0 - 10, v_c1, (select n.id from public.nations n where n.code = 'PRT'), v_a, 5, now());
    v_tick := public.tick_nation_race(public.nation_race_week_start(v_w0 + 1) + interval '1 hour');
    v_read := public.tick_nation_race(public.nation_race_week_start(v_w0 + 1) + interval '2 hours');   -- again: nothing
    if (v_tick->>'week')::bigint <> v_w0 or v_tick #>> '{settled,winner}' <> 'PRT' or (v_tick->>'trimmed')::int <> 1
       or exists (select 1 from public.nation_race_book b where b.week = v_w0 - 10)
       or not exists (select 1 from public.nation_race_book b where b.week = v_w0 - 1)
       or v_read->'settled' <> 'null'::jsonb or (v_read->>'trimmed')::int <> 0 then
      raise exception '0484 self-assert FAIL: the tick did not settle this week once and trim: %', v_tick;
    end if;

    -- (g) THE READ, as her: this week's points, the race city she leads, last week's winner, her title; signed out, no company
    perform cmd.assume_identity(c_ua);
    v_read := world.nation_race();
    if (v_read->>'on')::boolean is not true or (v_read->>'week')::bigint <> v_w0 or v_read #>> '{mine,nation}' <> 'PRT'
       or (v_read #>> '{mine,points}')::bigint <> v_pts + 100 + 200 or (v_read #>> '{mine,place}')::int <> 1
       or not exists (select 1 from jsonb_array_elements(v_read->'cities') c where c->>'port' = v_c1code and c->>'nation' = 'PRT')
       or v_read #>> '{last,winner}' <> 'PRT' or (v_read #>> '{last,week}')::bigint <> v_w0 - 1
       or v_read->'title' is distinct from jsonb_build_object('week', v_w0 - 1, 'nation', 'PRT')
       or jsonb_array_length(v_read->'nations') <> (select count(*) from public.great_powers g where not g.pirate)
       or (v_read->'nations'->0->>'nation') <> 'PRT' or (v_read #>> '{perk,fee_cut}')::numeric <> 0.5
       or (v_read->>'ends_at')::timestamptz <> public.nation_race_week_start(v_w0 + 1) then
      raise exception '0484 self-assert FAIL: the read is not as written: %', v_read;
    end if;
    perform cmd.assume_identity(c_ub);
    if world.nation_race()->'title' <> 'null'::jsonb or (world.nation_race() #>> '{mine,points}')::bigint <> 15 then
      raise exception '0484 self-assert FAIL: his read: %', world.nation_race();
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{}', true);
    if world.nation_race() is distinct from '{"on": true, "company": false}'::jsonb then
      raise exception '0484 self-assert FAIL: lit and signed out, the read is not {"on": true, "company": false}';
    end if;
    v_note := v_note || format(', sale at %s +%s, gift +100, job +15, marks, last week Portugal, champion paid once, tick settled and trimmed', v_c1code, v_pts);
    raise exception using errcode = 'ZX484', message = 'PROBE_ROLLBACK_0484';
  exception when sqlstate 'ZX484' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0484 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0484' or p.auth_uid in (c_ua, c_ub))
     or exists (select 1 from public.nation_race_book) or exists (select 1 from public.nation_race_weeks)
     or public.wc('nation_race_enabled') is distinct from 'false'::jsonb
     or public.current_player_id() is not null then
    raise exception '0484 self-assert FAIL: the probe left something behind';
  end if;

  -- ── THE JOB (where pg_cron is): hourly at :21; dark it reads one knob and returns ──
  -- budget: dark 0 rows a run; lit 0 rows a run except the first of a week: one week row, up to 3 Reputation rows and the trimmed book rows (a few hundred at most)
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('byeharu-voyage:nation-race', '21 * * * *', 'select public.tick_nation_race()');
  else
    raise notice '0484: pg_cron is not installed here (PGlite) - byeharu-voyage:nation-race was NOT scheduled. Call public.tick_nation_race() by hand.';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0484 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0484 self-assert ok: THE COUNTRY RACE (dark). % hunks once and reversing; grants and volatility unmoved; no other function moved; world.nation_race registered for authenticated alone, every core and the tick server only; two tables (RLS, no client grant); 8 knobs (nation_race_enabled false); one reputation kind. Probe (rolled back): dark nothing moves and the dock fee is its pre-image''s; lit %. % ms.',
    (select count(*) from hunks_0484), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
