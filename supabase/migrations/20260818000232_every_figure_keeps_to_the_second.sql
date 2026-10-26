-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0232 — EVERY FIGURE KEEPS TO THE SECOND
--        (every Stats read answers NOW: the count's completed quarter hours plus the minutes since, read
--         through ONE set of window functions the fifteen-minute job itself uses; the job stays the history)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 213, 2026-10-26; asked before as rows 187 and 200) ──
--   "and why is next count in minutes? i told you it should be in seconds?"
--
-- ── WHAT 0224 LEFT ON THE COUNT ─────────────────────────────────────────────────────────────────
-- 0224 made the money by holder, the fleets at sea and the trades since the count live (world.stats_now).
-- Every other figure on the five faces still came from the fifteen-minute rollup (0214's public.tick_stats,
-- 12–18 s a run on prod), so the faces waited for the count. This file makes EVERY Stats read answer the
-- second it is asked, with one rule for every windowed figure:
--
--     a figure over the last 24 h  =  the count's 24 h (the quarter hours up to the last count, as 0214 sums
--                                     them)  +  the minutes since that count (read live, below)
--     a figure "since the count"   =  the minutes since that count (the period in progress)
--     a state figure               =  read now (a purse, a fleet's status, a merchant's money)
--     a chart                      =  the counts' points  +  one live point at now()
--
-- ── ONE READING OF A WINDOW (docs/NO_SPAGHETTI.md: no second copy of a rule) ─────────────────────
-- 0214's job read its period inline (temp tables trades_0214, city_trades_0214, city_flows_0214, houses_0214).
-- The live reads need the SAME readings for (last count, now]. So the readings move into functions and the
-- job calls them (hunks below) — the count and the second ask one authority each:
--   public.stats_window_trades(from, to)       a trade: a SOLD / BOUGHT event of a goods row (0214's rule)
--   public.stats_window_totals(from, to)       the world's trades, units, sold, bought ducats
--   public.stats_window_goods(from, to)        the same by good
--   public.stats_window_city_trades(from, to)  a trade a city still remembers (its SELL / BUY flow)
--   public.stats_window_city_goods(from, to)   the same by (city, good)
--   public.stats_window_flows(from, to)        a city's flows by kind
--   public.stats_window_cities(from, to)       a city's period: income, spending, taxes, units, kinds
--   public.stats_window_founded(from, to)      money minted to a house (ledger FOUNDING / NPC_REFOUND)
--   public.stats_window_kinds(from, to)        the world's money by kind for the minutes since the count
--   public.stats_sides(kinds)                  minted / removed / moved, by the words table (0214)
--   public.stats_merchant_fleets()             where the merchants' fleets are
--   public.stats_merchants_window(from, to)    the merchants' closed laps: net, count, losing, by house
--   public.stats_merchants_add(a, b)           two such windows as one
--   public.stats_merchants_board(day)          a window as the board: profit, laps, % losing, top 5, bottom 5
--
-- ── WHAT THE COUNT KEEPS FOR THE SECOND (one jsonb `day` on the NEWEST slot's rows) ──────────────
-- Summing 96 quarter hours per good, per city and per house on every ask is what made the reads slow
-- (prod 2026-10-26: world.stats_markets 478–1,421 ms, world.stats_cities 1,117 ms; the merchants' 24 h of
-- laps 1,562–6,409 ms). So the count, which already reads all of it, keeps its 24 h on the newest rows:
--   stats_good.day       the good's whole served row as of the count: sold / bought units and ducats over the
--                        count's 24 h; the mid 1 h / 1 d / 7 d before the count; the 24 newest recorded mids
--   stats_city.day       income, spending, taxes, units sold / bought, money by kind over the 24 h; the city's
--                        name and flag
--   stats_merchants.day  the 24 h of closed laps: net, count, losing, and every house's day and laps
-- written by public.stats_fold_day(slot) (goods, cities; called by tick_stats on its return) and by the
-- merchants' insert, and CLEARED from older rows by the same fold — `day` lives on the newest slot only.
--
-- ── THE PROVISIONAL MINUTES, SAID PLAINLY ──────────────────────────────────────────────────────
-- The world's money by kind is counted exactly by the job from daybook + flows (0214's `recent`, 438–917 ms
-- on prod — too slow for a second). The minutes since the count read the flows themselves; tick_city rolls
-- the flows away at :37, so between :37 and the :51 count the minute :36–:37 is missing from the LIVE kinds
-- (0214's own city rows miss the same minute, by design). The :51 count puts it back.
--
-- ── NOT MADE LIVE, SAID PLAINLY (decided by default) ────────────────────────────────────────────
-- A good's price across every market (Markets: mid, rose / fell, stock, markets) stays the price record's
-- (price_history, the price job's slot): computing ~1,380 live prices costs 320–470 ms per ask on prod
-- (measured 2026-10-26, set-wise through world.mid_from_terms), ten times the budget. A CITY's own prices
-- and stock ARE live (world.mid_price on a handful of goods).
--
-- ── SUPERSEDES ─────────────────────────────────────────────────────────────────────────────────
--   public.tick_stats(timestamptz)   9 hunks sliced from the LIVE body (0214 as re-cut by 0224 and 0226),
--                                    each asserted to occur once and to reverse to the pre-image
--   world.stats_overview(int), world.stats_markets(), world.stats_cities(), world.stats_city(uuid),
--   world.stats_merchants()          WHOLE (create or replace), each guarded by a line of the live body
--                                    asserted to occur exactly once; ACL / volatility / definer / config
--                                    asserted unchanged. world.stats_me and world.books are already live.
-- No writer hook: the trade path is untouched (cost 0). Registry unchanged (no new read).
--
-- ── WHAT IT SELF-ASSERTS (own probe rows; the probe and the job's trial run are rolled back) ────
--   (a) the functions, the three columns, the walls at 0, the registry unchanged; the hunks.
--   (b) the seed: the newest rows carry `day`.
--   (c) BY AMOUNT, pure: stats_sides, stats_merchants_add, stats_merchants_board on planted input.
--   (d) POSITIVE CONTROL, BY AMOUNT: a probe company at Lisbon sells 10 and buys 5; a lap of 777 is planted on
--       a merchant's route. Over THIS transaction's instant (its own rows only) the window functions say
--       trades 2, units 15, sold / bought = the probe's own events, the good 10 / 5, Lisbon 10 / 5, the
--       founding money, the lap 777. Then each read, in ONE statement with its own window, equals the
--       count's figure + the window's (an identity that holds whatever else trades meanwhile).
--   (e) THE JOB RUNS: tick_stats at a slot two hours ahead (no clash with the cron), rolled back: every table
--       written, `day` on the new rows and gone from the old.
--   (f) TIMINGS, notice only: each read ×6 in one session; the trial run's ms.
-- ROLLBACK (forward): reverse the 9 hunks; re-create the five reads from 0214 / 0223; drop the functions and
-- the three columns.
-- VERSION: 0232 = prod head 0226 + 0227 (city good trades) + 0228–0229 (economy E1 / E2) + 0231 (legs fit supplies) ahead in the queue + 1 — RENUMBER TO PROD HEAD + 1 AT PUSH (and the _0232
-- suffixes, the probe uuid and this header's tags with it).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.stats_live') is null or to_regprocedure('world.stats_now()') is null then
    raise exception '0232 refuses: 0224 (the live figures) is not in this world';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'price_history' and column_name = 'ask') then
    raise exception '0232 refuses: 0226 (the price record both ways) is not in this world';
  end if;
  if to_regprocedure('public.stats_window_trades(timestamptz, timestamptz)') is not null then
    raise exception '0232 refuses: public.stats_window_trades already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0232(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0232 on commit drop as
select f.fn, f.guard,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values
    ('public.tick_stats(timestamptz)', null),
    ('world.stats_overview(integer)',
     $g$    'day', (select jsonb_build_object('since', min(w.at), 'minted', sum(w.minted), 'removed', sum(w.removed), 'moved', sum(w.moved),$g$),
    ('world.stats_markets()',
     $g$        cross join lateral (select coalesce(sum(x.sold), 0) as sold, coalesce(sum(x.bought), 0) as bought,$g$),
    ('world.stats_cities()',
     $g$                      'income_1d',   (select coalesce(sum(x.income), 0)   from public.stats_city x where x.port_id = p.id and x.at > v_at - interval '24 hours'),$g$),
    ('world.stats_city(uuid)',
     $g$  if v_slot is not null then  -- 0223: the detail, for everyone$g$),
    ('world.stats_merchants()',
     $g$  select * into m from public.stats_merchants order by slot desc limit 1;$g$)) f(fn, guard);

create temp table before_0232 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

do $$
declare
  d record;
begin
  for d in select * from defs_before_0232 where guard is not null loop
    if pg_temp.occurs_0232(d.def, d.guard) <> 1 then
      raise exception '0232 self-assert FAIL: % does not carry the line this file supersedes exactly once (% times) — the deployed body is not the one read',
        d.fn, pg_temp.occurs_0232(d.def, d.guard);
    end if;
  end loop;
end $$;

-- ── 1. THE COLUMNS (`day` on the newest slot's rows only; the fold clears the rest) ─────────────
alter table public.stats_good      add column day jsonb;
alter table public.stats_city      add column day jsonb;
alter table public.stats_merchants add column day jsonb;
comment on column public.stats_good.day is
  '0232: on the NEWEST slot''s rows only — the count''s 24 h for this good (sold / bought units and ducats), the mid '
  '1 h / 1 d / 7 d before the count and the 24 newest recorded mids. Written and cleared by public.stats_fold_day.';
comment on column public.stats_city.day is
  '0232: on the NEWEST slot''s rows only — the count''s 24 h for this city: income, spending, taxes, units sold / '
  'bought, money by kind. Written and cleared by public.stats_fold_day.';
comment on column public.stats_merchants.day is
  '0232: on the NEWEST slot''s row only — the count''s 24 h of closed laps (public.stats_merchants_window): net, n, '
  'neg and every house''s day and laps. Written by public.tick_stats, cleared by public.stats_fold_day.';

-- ── 2. ONE READING OF A WINDOW (the job and the live reads ask the same functions) ──────────────
create function public.stats_window_trades(p_from timestamptz, p_to timestamptz)
returns table (id uuid, kind text, player_id uuid, good_id uuid, qty numeric, total bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats): a trade is a SOLD / BOUGHT event of a goods row, stamped in (p_from, p_to].
  select e.id, e.kind, e.player_id, g.id,
         (e.payload->>'qty')::numeric, round((e.payload->>'total')::numeric)::bigint
    from public.events e
    join public.goods g on g.name = e.payload->>'good'
   where e.kind in ('SOLD', 'BOUGHT') and e.created_at > p_from and e.created_at <= p_to
$$;

create function public.stats_window_totals(p_from timestamptz, p_to timestamptz)
returns table (sold bigint, bought bigint, units numeric, trades bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232: the world's trades of a window — ducats sold to cities, ducats bought from them, units, trades.
  select coalesce(sum(t.total) filter (where t.kind = 'SOLD'), 0)::bigint,
         coalesce(sum(t.total) filter (where t.kind = 'BOUGHT'), 0)::bigint,
         coalesce(sum(t.qty), 0),
         count(*)
    from public.stats_window_trades(p_from, p_to) t
$$;

create function public.stats_window_goods(p_from timestamptz, p_to timestamptz)
returns table (good_id uuid, sold numeric, bought numeric, sold_d numeric, bought_d numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats): a window's trades by good — units and ducats, each side.
  select t.good_id,
         sum(t.qty) filter (where t.kind = 'SOLD'), sum(t.qty) filter (where t.kind = 'BOUGHT'),
         sum(t.total) filter (where t.kind = 'SOLD'), sum(t.total) filter (where t.kind = 'BOUGHT')
    from public.stats_window_trades(p_from, p_to) t
   group by t.good_id
$$;

create function public.stats_window_city_trades(p_from timestamptz, p_to timestamptz)
returns table (port_id uuid, good_id uuid, kind text, qty numeric, total bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats): the window's trades a city still remembers — its SELL / BUY flow carries
  -- the event's id and names the harbour (tick_city rolls flows away at :37; 0214's header: the :36–:37 minute).
  select f.port_id, t.good_id, t.kind, t.qty, t.total
    from public.treasury_flows f
    join public.stats_window_trades(p_from, p_to) t on t.id = f.ref_event
   where f.kind in ('SELL', 'BUY') and f.created_at > p_from and f.created_at <= p_to
$$;

create function public.stats_window_city_goods(p_from timestamptz, p_to timestamptz)
returns table (port_id uuid, good_id uuid, sold numeric, bought numeric, sold_d numeric, bought_d numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats): a window's city trades by (city, good).
  select t.port_id, t.good_id,
         sum(t.qty) filter (where t.kind = 'SOLD'), sum(t.qty) filter (where t.kind = 'BOUGHT'),
         sum(t.total) filter (where t.kind = 'SOLD'), sum(t.total) filter (where t.kind = 'BOUGHT')
    from public.stats_window_city_trades(p_from, p_to) t
   group by 1, 2
$$;

create function public.stats_window_flows(p_from timestamptz, p_to timestamptz)
returns table (port_id uuid, kind text, ducats bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats): a window's money flows by (city, kind).
  select f.port_id, f.kind, sum(f.ducats)::bigint
    from public.treasury_flows f
   where f.created_at > p_from and f.created_at <= p_to
   group by 1, 2
$$;

create function public.stats_window_cities(p_from timestamptz, p_to timestamptz)
returns table (port_id uuid, income bigint, spending bigint, taxes bigint, sold numeric, bought numeric, kinds jsonb)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats): a city's period — income = Σ of its kinds that came in, spending = Σ of the
  -- ones that went out, taxes = TAX; units sold to it and bought from it; money by kind. Cities with neither are absent.
  with b as (
    select f.port_id,
           coalesce(sum(f.ducats) filter (where f.ducats > 0), 0)::bigint as income,
           coalesce(-sum(f.ducats) filter (where f.ducats < 0), 0)::bigint as spending,
           coalesce(sum(f.ducats) filter (where f.kind = 'TAX'), 0)::bigint as taxes,
           jsonb_object_agg(f.kind, f.ducats) as kinds
      from public.stats_window_flows(p_from, p_to) f
     group by f.port_id
  ), u as (
    select t.port_id, coalesce(sum(t.sold), 0) as sold, coalesce(sum(t.bought), 0) as bought
      from public.stats_window_city_goods(p_from, p_to) t
     group by t.port_id
  )
  select coalesce(b.port_id, u.port_id), coalesce(b.income, 0), coalesce(b.spending, 0), coalesce(b.taxes, 0),
         coalesce(u.sold, 0), coalesce(u.bought, 0), coalesce(b.kinds, '{}'::jsonb)
    from b full join u on u.port_id = b.port_id
$$;

create function public.stats_window_founded(p_from timestamptz, p_to timestamptz)
returns table (kind text, ducats bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats): money minted to a house in a window — a company's founding, a merchant's refound.
  select l.kind, sum(l.ducats_delta)::bigint
    from public.ledger l
   where l.kind in ('FOUNDING', 'NPC_REFOUND') and l.created_at > p_from and l.created_at <= p_to
   group by l.kind
$$;

create function public.stats_window_kinds(p_from timestamptz, p_to timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232: the world's money by kind for the minutes since the count — every city's flows by kind plus the money
  -- minted to houses. Provisional by one minute an hour (the header): the count reads daybook + flows.
  select coalesce(jsonb_object_agg(k.kind, k.ducats) filter (where k.ducats <> 0), '{}'::jsonb)
    from (select x.kind, sum(x.ducats)::bigint as ducats
            from (select f.kind, f.ducats from public.stats_window_flows(p_from, p_to) f
                  union all
                  select h.kind, h.ducats from public.stats_window_founded(p_from, p_to) h) x
           group by x.kind) k
$$;

create function public.stats_sides(p_kinds jsonb)
returns table (minted bigint, removed bigint, moved bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats): money by kind on its three sides, by the words table (public.stats_flow_words)
  -- — minted, removed (as a positive figure), moved (Σ |ducats|). A kind not in the table is moved.
  select coalesce(sum(case when w.side = 'minted' then p.v end), 0)::bigint,
         coalesce(sum(case when w.side = 'removed' then -p.v end), 0)::bigint,
         coalesce(sum(case when coalesce(w.side, 'moved') = 'moved' then abs(p.v) end), 0)::bigint
    from jsonb_each_text(coalesce(p_kinds, '{}'::jsonb)) p0(kind, v0), lateral (select p0.kind, p0.v0::bigint as v) p
    left join public.stats_flow_words w on w.kind = p.kind
$$;

create function public.stats_merchant_fleets()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats): the merchant companies and where their fleets are, now.
  select jsonb_build_object(
           'houses',    (select count(*) from public.npc_houses),
           'fleets',    (select count(*) from public.npc_fleets),
           'sailing',   count(*) filter (where f.status = 'SAILING'),
           'docked',    count(*) filter (where f.status in ('DOCKED', 'ANCHORED')),
           'repairing', count(*) filter (where f.status = 'REPAIRING'),
           'unable',    count(*) filter (where f.status in ('UNABLE_TO_SAIL', 'ADRIFT')),
           'laid_up',   (select count(*) from public.npc_fleets nf join public.standing_routes r on r.id = nf.route_id
                          where r.paused_reason = 'laid_up'))
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
$$;

create function public.stats_merchants_window(p_from timestamptz, p_to timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats, which read the laps twice): the closed laps of a window, lap 2 onwards (0097's
  -- rule: lap 1 holds a purchase and no sale) — Σ net, how many, how many lost, and every merchant house's day and laps.
  with l as materialized (
    select l.route_id, l.net
      from public.standing_route_laps l
     where l.closed_at > p_from and l.closed_at <= p_to and l.lap_no >= 2
  ), h as (
    select p.company_name as name, n.code as nation, sum(l.net)::bigint as day, count(*)::int as laps
      from l
      join public.standing_routes r on r.id = l.route_id
      join public.players p on p.id = r.player_id and p.is_npc
      left join public.nations n on n.id = p.nation_id
     group by p.company_name, n.code
  )
  select jsonb_build_object(
           'net', coalesce((select sum(l.net) from l), 0)::bigint,
           'n', (select count(*) from l),
           'neg', (select count(*) from l where l.net <= 0),
           'houses', coalesce((select jsonb_agg(jsonb_build_object('name', h.name, 'nation', h.nation, 'day', h.day, 'laps', h.laps)
                                                order by h.name, h.nation) from h), '[]'::jsonb))
$$;

create function public.stats_merchants_add(a jsonb, b jsonb)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  -- 0232: two windows of laps as one (the count's 24 h + the minutes since) — sums, and houses summed by name.
  select jsonb_build_object(
           'net', coalesce((a->>'net')::bigint, 0) + coalesce((b->>'net')::bigint, 0),
           'n', coalesce((a->>'n')::bigint, 0) + coalesce((b->>'n')::bigint, 0),
           'neg', coalesce((a->>'neg')::bigint, 0) + coalesce((b->>'neg')::bigint, 0),
           'houses', coalesce((select jsonb_agg(jsonb_build_object('name', h.name, 'nation', h.nation, 'day', h.day, 'laps', h.laps)
                                                order by h.name, h.nation)
                                 from (select x.name, x.nation, sum(x.day)::bigint as day, sum(x.laps)::int as laps
                                         from (select * from jsonb_to_recordset(coalesce(a->'houses', '[]'::jsonb)) r(name text, nation text, day bigint, laps int)
                                               union all
                                               select * from jsonb_to_recordset(coalesce(b->'houses', '[]'::jsonb)) r(name text, nation text, day bigint, laps int)) x
                                        group by x.name, x.nation) h), '[]'::jsonb))
$$;

create function public.stats_merchants_board(p_day jsonb)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  -- 0232 (moved from 0214's tick_stats): a window of laps as the board — Σ net, laps, the share that lost, the five
  -- best and five worst houses by their day (name breaks a tie).
  with h as (
    select * from jsonb_to_recordset(coalesce(p_day->'houses', '[]'::jsonb)) r(name text, nation text, day bigint, laps int)
  ), n as (
    select coalesce((p_day->>'net')::bigint, 0) as net, coalesce((p_day->>'n')::bigint, 0) as n, coalesce((p_day->>'neg')::bigint, 0) as neg
  )
  select jsonb_build_object(
           'profit_day', n.net, 'laps_day', n.n,
           'losing_pct', coalesce(round(100.0 * n.neg / nullif(n.n, 0), 1), 0),
           'top', coalesce((select jsonb_agg(jsonb_build_object('name', t.name, 'nation', t.nation, 'day', t.day, 'laps', t.laps) order by t.day desc, t.name)
                              from (select * from h order by h.day desc, h.name limit 5) t), '[]'::jsonb),
           'bottom', coalesce((select jsonb_agg(jsonb_build_object('name', t.name, 'nation', t.nation, 'day', t.day, 'laps', t.laps) order by t.day asc, t.name)
                                 from (select * from h order by h.day asc, h.name limit 5) t), '[]'::jsonb))
    from n
$$;

create function public.stats_fold_day(p_slot bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0232: what the count keeps for the second — each good's and each city's 24 h up to slot p_slot, on that slot's rows;
-- `day` cleared from every older row (it lives on the newest slot only). Called by tick_stats on its return.
declare
  v_ph   bigint := greatest(1, round(3600 / public.wc_num('drift_slot_seconds')))::bigint;   -- slots an hour
  v_from bigint := p_slot - 24 * v_ph;
  v_g int; v_c int;
begin
  -- a good's whole served row (world.stats_markets), as of the count: the read adds only the minutes since, to the
  -- goods that traded in them (building 565 rows of 17 figures every second cost 30–40 ms on prod by itself)
  update public.stats_good n
     set day = jsonb_build_object(
           'code', g.code, 'name', g.name, 'category', g.category,
           'mid', n.mid, 'markets', n.markets, 'stock', n.stock, 'stock_target', n.stock_target, 'sold', 0, 'bought', 0,
           'sold_1d', d.sold, 'bought_1d', d.bought, 'sold_ducats_1d', d.sold_d, 'bought_ducats_1d', d.bought_d,
           'mid_1h', (select x.mid from public.stats_good x where x.good_id = n.good_id and x.slot <= p_slot - v_ph and x.mid is not null order by x.slot desc limit 1),
           'mid_1d', (select x.mid from public.stats_good x where x.good_id = n.good_id and x.slot <= p_slot - 24 * v_ph and x.mid is not null order by x.slot desc limit 1),
           'mid_7d', (select x.mid from public.stats_good x where x.good_id = n.good_id and x.slot <= p_slot - 7 * 24 * v_ph and x.mid is not null order by x.slot desc limit 1),
           'spark', (select coalesce(jsonb_agg(s.mid order by s.slot), '[]'::jsonb)
                       from (select x.mid, x.slot from public.stats_good x where x.good_id = n.good_id and x.slot <= p_slot and x.mid is not null
                              order by x.slot desc limit 24) s))
    from (select x.good_id, coalesce(sum(x.sold), 0) as sold, coalesce(sum(x.bought), 0) as bought,
                 coalesce(sum(x.sold_ducats), 0) as sold_d, coalesce(sum(x.bought_ducats), 0) as bought_d
            from public.stats_good x where x.slot > v_from and x.slot <= p_slot
           group by x.good_id) d, public.goods g
   where n.slot = p_slot and d.good_id = n.good_id and g.id = n.good_id;
  get diagnostics v_g = row_count;

  update public.stats_city n
     set day = jsonb_build_object('row', jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name,
                                                            'nation', (select nn.code from public.nations nn where nn.id = public.port_nation(p.id))),
                                  'income', d.income, 'spending', d.spending, 'taxes', d.taxes, 'sold', d.sold, 'bought', d.bought,
                                  'kinds', coalesce((select jsonb_object_agg(k.kind, k.s)
                                                       from (select e.key as kind, sum(e.value::bigint) as s
                                                               from public.stats_city x, jsonb_each_text(x.flows) e
                                                              where x.port_id = n.port_id and x.slot > v_from and x.slot <= p_slot
                                                              group by e.key) k), '{}'::jsonb))
    from (select x.port_id, coalesce(sum(x.income), 0) as income, coalesce(sum(x.spending), 0) as spending,
                 coalesce(sum(x.taxes), 0) as taxes, coalesce(sum(x.sold), 0) as sold, coalesce(sum(x.bought), 0) as bought
            from public.stats_city x where x.slot > v_from and x.slot <= p_slot
           group by x.port_id) d, public.ports p
   where n.slot = p_slot and d.port_id = n.port_id and p.id = n.port_id;
  get diagnostics v_c = row_count;

  update public.stats_good      set day = null where slot < p_slot and day is not null;
  update public.stats_city      set day = null where slot < p_slot and day is not null;
  update public.stats_merchants set day = null where slot < p_slot and day is not null;
  return jsonb_build_object('goods', v_g, 'cities', v_c);
end $$;

comment on function public.stats_window_trades(timestamptz, timestamptz) is
  '0232: THE one reading of "the trades of a window" (0214''s rule). public.tick_stats and the Stats reads both ask it. Server-only.';
comment on function public.stats_fold_day(bigint) is
  '0232: keeps the count''s 24 h on the newest slot''s stats_good / stats_city rows and clears `day` from older rows. Server-only.';

revoke all on function public.stats_window_trades(timestamptz, timestamptz), public.stats_window_totals(timestamptz, timestamptz),
                       public.stats_window_goods(timestamptz, timestamptz), public.stats_window_city_trades(timestamptz, timestamptz),
                       public.stats_window_city_goods(timestamptz, timestamptz), public.stats_window_flows(timestamptz, timestamptz),
                       public.stats_window_cities(timestamptz, timestamptz), public.stats_window_founded(timestamptz, timestamptz),
                       public.stats_window_kinds(timestamptz, timestamptz), public.stats_sides(jsonb),
                       public.stats_merchant_fleets(), public.stats_merchants_window(timestamptz, timestamptz),
                       public.stats_merchants_add(jsonb, jsonb), public.stats_merchants_board(jsonb), public.stats_fold_day(bigint)
  from public, anon, authenticated;

-- ── 3. THE JOB'S HUNKS (its window readings become the functions above; `day` on its return) ────
create temp table hunks_0232 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0232 values
('public.tick_stats(timestamptz)', 1,
$h$  -- the trades of the period, once: from the append-only events (the good and the fleet are NAMES there)
  -- (a second run in one transaction — the probe — finds the last run's temp tables still there)
  if to_regclass('pg_temp.trades_0214') is not null then
    drop table trades_0214, city_trades_0214, city_flows_0214, houses_0214;
  end if;
  create temp table trades_0214 on commit drop as
  select e.id, e.kind, e.player_id, g.id as good_id,
         (e.payload->>'qty')::numeric as qty, round((e.payload->>'total')::numeric)::bigint as total
    from public.events e
    join public.goods g on g.name = e.payload->>'good'
   where e.kind in ('SOLD', 'BOUGHT') and e.created_at > v_prev_at and e.created_at <= p_now;
  -- …and the ones a city still remembers (its flow names the harbour; header: the :36–:37 minute)
  create temp table city_trades_0214 on commit drop as
  select f.port_id, t.good_id, t.kind, t.qty, t.total
    from public.treasury_flows f
    join trades_0214 t on t.id = f.ref_event
   where f.kind in ('SELL', 'BUY') and f.created_at > v_prev_at and f.created_at <= p_now;
  create temp table city_flows_0214 on commit drop as
  select f.port_id, f.kind, sum(f.ducats)::bigint as ducats
    from public.treasury_flows f
   where f.created_at > v_prev_at and f.created_at <= p_now
   group by 1, 2;
$h$,
$h$  -- 0232: the period's trades, flows and laps are read through the public.stats_window_* functions — THE ONE reading
  -- of a window, which the Stats tab's live reads ask for the minutes since this count. No temp tables.
$h$),
('public.tick_stats(timestamptz)', 2,
$h$          select l.kind, sum(l.ducats_delta)::bigint
            from public.ledger l
           where l.kind in ('FOUNDING', 'NPC_REFOUND') and l.created_at > v_prev_at and l.created_at <= p_now
           group by l.kind) k;
$h$,
$h$          select h.kind, h.ducats from public.stats_window_founded(v_prev_at, p_now) h) k;   -- 0232: one reading of the window
$h$),
('public.tick_stats(timestamptz)', 3,
$h$  select coalesce(sum(case when w.side = 'minted' then p.v end), 0),
         coalesce(sum(case when w.side = 'removed' then -p.v end), 0),
         coalesce(sum(case when coalesce(w.side, 'moved') = 'moved' then abs(p.v) end), 0)
    into v_minted, v_removed, v_moved
    from jsonb_each_text(v_period) p0(kind, v0), lateral (select p0.kind, p0.v0::bigint as v) p
    left join public.stats_flow_words w on w.kind = p.kind;
$h$,
$h$  select s.minted, s.removed, s.moved into v_minted, v_removed, v_moved
    from public.stats_sides(v_period) s;   -- 0232: the words table's sides, one rule
$h$),
('public.tick_stats(timestamptz)', 4,
$h$         coalesce((select sum(t.total) from trades_0214 t where t.kind = 'SOLD'), 0),
         coalesce((select sum(t.total) from trades_0214 t where t.kind = 'BOUGHT'), 0),
         coalesce((select sum(t.qty) from trades_0214 t), 0),
         (select count(*) from trades_0214),
         v_period, v_recent
  on conflict (slot) do nothing;
$h$,
$h$         t.sold, t.bought, t.units, t.trades,
         v_period, v_recent
    from public.stats_window_totals(v_prev_at, p_now) t   -- 0232: one reading of the window
  on conflict (slot) do nothing;
$h$),
('public.tick_stats(timestamptz)', 5,
$h$    left join (select t.good_id,
                      sum(t.qty) filter (where t.kind = 'SOLD') as sold, sum(t.qty) filter (where t.kind = 'BOUGHT') as bought,
                      sum(t.total) filter (where t.kind = 'SOLD') as sold_d, sum(t.total) filter (where t.kind = 'BOUGHT') as bought_d
                 from trades_0214 t group by t.good_id) t on t.good_id = g.id
$h$,
$h$    left join public.stats_window_goods(v_prev_at, p_now) t on t.good_id = g.id   -- 0232: one reading of the window
$h$),
('public.tick_stats(timestamptz)', 6,
$h$  select p.id, v_slot, p_now, public.treasury_balance(p.id),
         coalesce((select sum(f.ducats) from city_flows_0214 f where f.port_id = p.id and f.ducats > 0), 0),
         coalesce((select -sum(f.ducats) from city_flows_0214 f where f.port_id = p.id and f.ducats < 0), 0),
         coalesce((select sum(f.ducats) from city_flows_0214 f where f.port_id = p.id and f.kind = 'TAX'), 0),
         coalesce((select sum(w.level) from public.city_works w where w.port_id = p.id), 0),
         coalesce((select sum(t.qty) from city_trades_0214 t where t.port_id = p.id and t.kind = 'SOLD'), 0),
         coalesce((select sum(t.qty) from city_trades_0214 t where t.port_id = p.id and t.kind = 'BOUGHT'), 0),
         coalesce((select jsonb_object_agg(f.kind, f.ducats) from city_flows_0214 f where f.port_id = p.id), '{}'::jsonb)
    from public.ports p
   where p.kind = 'HARBOUR'
$h$,
$h$  select p.id, v_slot, p_now, public.treasury_balance(p.id),
         coalesce(c.income, 0), coalesce(c.spending, 0), coalesce(c.taxes, 0),
         coalesce((select sum(w.level) from public.city_works w where w.port_id = p.id), 0),
         coalesce(c.sold, 0), coalesce(c.bought, 0), coalesce(c.kinds, '{}'::jsonb)
    from public.ports p
    left join public.stats_window_cities(v_prev_at, p_now) c on c.port_id = p.id   -- 0232: one reading of the window
   where p.kind = 'HARBOUR'
$h$),
('public.tick_stats(timestamptz)', 7,
$h$          select t.port_id, t.good_id from city_trades_0214 t) k
$h$,
$h$          select t.port_id, t.good_id from public.stats_window_city_goods(v_prev_at, p_now) t) k   -- 0232
$h$),
('public.tick_stats(timestamptz)', 8,
$h$    left join (select t.port_id, t.good_id,
                      sum(t.qty) filter (where t.kind = 'SOLD') as sold, sum(t.qty) filter (where t.kind = 'BOUGHT') as bought,
                      sum(t.total) filter (where t.kind = 'SOLD') as sold_d, sum(t.total) filter (where t.kind = 'BOUGHT') as bought_d
                 from city_trades_0214 t group by 1, 2) t on t.port_id = k.port_id and t.good_id = k.good_id
$h$,
$h$    left join public.stats_window_city_goods(v_prev_at, p_now) t on t.port_id = k.port_id and t.good_id = k.good_id   -- 0232
$h$),
('public.tick_stats(timestamptz)', 9,
$h$  -- THE MERCHANTS: each company's last 24 real hours of closed laps (lap 2 onwards — 0097's rule: lap 1 holds a
  -- purchase and no sale), read once for the five best and the five worst
  create temp table houses_0214 on commit drop as
  select p.company_name as name, n.code as nation, sum(l.net)::bigint as day, count(*)::int as laps
    from public.standing_route_laps l
    join public.standing_routes r on r.id = l.route_id
    join public.players p on p.id = r.player_id and p.is_npc
    left join public.nations n on n.id = p.nation_id
   where l.closed_at > p_now - interval '24 hours' and l.closed_at <= p_now and l.lap_no >= 2
   group by p.company_name, n.code;
  insert into public.stats_merchants (slot, at, houses, fleets, sailing, docked, repairing, unable, laid_up, purse,
                                      profit_day, laps_day, losing_pct, top, bottom)
  select v_slot, p_now,
         (select count(*) from public.npc_houses),
         (select count(*) from public.npc_fleets),
         (select count(*) from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.status = 'SAILING'),
         (select count(*) from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.status in ('DOCKED', 'ANCHORED')),
         (select count(*) from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.status = 'REPAIRING'),
         (select count(*) from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.status in ('UNABLE_TO_SAIL', 'ADRIFT')),
         (select count(*) from public.npc_fleets nf join public.standing_routes r on r.id = nf.route_id where r.paused_reason = 'laid_up'),
         coalesce((select sum(p.ducats) from public.players p where p.is_npc), 0),
         coalesce(d.net, 0), coalesce(d.n, 0), coalesce(round(100.0 * d.neg / nullif(d.n, 0), 1), 0),
         coalesce((select jsonb_agg(jsonb_build_object('name', h.name, 'nation', h.nation, 'day', h.day, 'laps', h.laps) order by h.day desc, h.name)
                     from (select * from houses_0214 order by day desc, name limit 5) h), '[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('name', h.name, 'nation', h.nation, 'day', h.day, 'laps', h.laps) order by h.day asc, h.name)
                     from (select * from houses_0214 order by day asc, name limit 5) h), '[]'::jsonb)
    from (select sum(l.net) as net, count(*) as n, count(*) filter (where l.net <= 0) as neg
            from public.standing_route_laps l
           where l.closed_at > p_now - interval '24 hours' and l.closed_at <= p_now and l.lap_no >= 2) d
  on conflict (slot) do nothing;
$h$,
$h$  -- THE MERCHANTS (0232: the fleets, the window's laps — read ONCE, where 0214 read them twice — and the board are
  -- each one function, which the live read asks for the minutes since this count): the last 24 real hours of closed
  -- laps, lap 2 onwards (0097), kept whole as `day` for the live read
  insert into public.stats_merchants (slot, at, houses, fleets, sailing, docked, repairing, unable, laid_up, purse,
                                      profit_day, laps_day, losing_pct, top, bottom, day)
  select v_slot, p_now,
         (f.f->>'houses')::int, (f.f->>'fleets')::int, (f.f->>'sailing')::int, (f.f->>'docked')::int,
         (f.f->>'repairing')::int, (f.f->>'unable')::int, (f.f->>'laid_up')::int,
         coalesce((select sum(p.ducats) from public.players p where p.is_npc), 0),
         (b.b->>'profit_day')::bigint, (b.b->>'laps_day')::int, (b.b->>'losing_pct')::numeric, b.b->'top', b.b->'bottom', d.d
    from (select public.stats_merchant_fleets() as f) f
   cross join (select public.stats_merchants_window(p_now - interval '24 hours', p_now) as d) d
   cross join lateral (select public.stats_merchants_board(d.d) as b) b
  on conflict (slot) do nothing;
$h$),
('public.tick_stats(timestamptz)', 10,
$h$                            'live', public.stats_live_fold(p_now),   -- 0224: the live figures reconciled on every count
$h$,
$h$                            'day', public.stats_fold_day(v_slot),     -- 0232: the 24 h the live reads add their minutes to
                            'live', public.stats_live_fold(p_now),   -- 0224: the live figures reconciled on every count
$h$);

do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0232 where guard is null order by fn loop
    v_def := d.def;
    for h in select * from hunks_0232 where fn = d.fn order by n loop
      if pg_temp.occurs_0232(v_def, h.old) <> 1 then
        raise exception '0232 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0232(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def ~ '(trades|city_trades|city_flows|houses)_0214' then
      raise exception '0232 self-assert FAIL: % still names a temp table of 0214 after the hunks', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0232 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0232(v_rev, h.new) <> 1 then
        raise exception '0232 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0232 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0232 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config', d.fn, d.acl, p.acl;
    end if;
  end loop;
end $$;

-- ── 4. THE READS: each answers NOW (the count's figure + the minutes since; charts end at now()) ─
create or replace function world.stats_overview(p_hours int default 24)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: the world's money — by holder now and over the window; this period's and the last day's minted, removed,
-- moved, sold, bought, by kind. Public.
-- 0232 (owner row 213: every figure to the second): `holders` are the live counters (world.stats_now, 0224);
-- `period` is the count in progress (the minutes since the last count); `day` is the count's 24 h plus those
-- minutes; the series ends with a live point at now(). `at` is now(); `counted_at` is the last count.
declare
  v_hours int := least(greatest(coalesce(p_hours, 24), 1), 24 * 30);
  l       public.stats_world%rowtype;
  v_live  jsonb;
  v_kinds jsonb;
  s       record;
  t       record;
begin
  select * into l from public.stats_world order by slot desc limit 1;
  if l.slot is null then
    return jsonb_build_object('at', now(), 'counted_at', null, 'age_seconds', null, 'slot_seconds', public.wc_num('drift_slot_seconds'),
                              'hours', v_hours, 'holders', null, 'period', null, 'day', null, 'series', '[]'::jsonb);
  end if;
  v_live  := world.stats_now();
  v_kinds := public.stats_window_kinds(l.at, now());
  select * into s from public.stats_sides(v_kinds);
  select * into t from public.stats_window_totals(l.at, now());
  return jsonb_build_object(
    'at', now(),
    'counted_at', l.at,
    'age_seconds', round(extract(epoch from now() - l.at)),
    'slot_seconds', public.wc_num('drift_slot_seconds'),
    'hours', v_hours,
    'holders', jsonb_build_object('players', (v_live->>'players')::bigint, 'merchants', (v_live->>'merchants')::bigint,
                                  'cities', (v_live->>'cities')::bigint, 'set_aside', (v_live->>'set_aside')::bigint,
                                  'total', (v_live->>'total')::bigint),
    'period', jsonb_build_object('since', l.at, 'minted', s.minted, 'removed', s.removed, 'moved', s.moved,
                                 'sold', t.sold, 'bought', t.bought, 'units', t.units, 'trades', t.trades,
                                 'flows', public.stats_flow_lines(v_kinds)),
    'day', (select jsonb_build_object('since', min(w.at),
                                      'minted', sum(w.minted) + s.minted, 'removed', sum(w.removed) + s.removed, 'moved', sum(w.moved) + s.moved,
                                      'sold', sum(w.sold) + t.sold, 'bought', sum(w.bought) + t.bought,
                                      'units', sum(w.units) + t.units, 'trades', sum(w.trades) + t.trades,
                                      'flows', public.stats_flow_lines((select jsonb_object_agg(k.kind, k.s)
                                                                           from (select x.kind, sum(x.v) as s
                                                                                   from (select e.key as kind, e.value::bigint as v
                                                                                           from public.stats_world y, jsonb_each_text(y.period) e
                                                                                          where y.at > l.at - interval '24 hours'
                                                                                         union all
                                                                                         select e.key, e.value::bigint from jsonb_each_text(v_kinds) e) x
                                                                                  group by x.kind) k)))
              from public.stats_world w where w.at > l.at - interval '24 hours'),
    'series', coalesce((select jsonb_agg(jsonb_build_object('at', w.at, 'players', w.players, 'merchants', w.merchants, 'cities', w.cities,
                                                            'set_aside', w.set_aside, 'minted', w.minted, 'removed', w.removed,
                                                            'moved', w.moved, 'sold', w.sold, 'bought', w.bought) order by w.slot)
                          from public.stats_world w where w.at > l.at - make_interval(hours => v_hours)), '[]'::jsonb)
              || jsonb_build_array(jsonb_build_object('at', now(), 'players', (v_live->>'players')::bigint, 'merchants', (v_live->>'merchants')::bigint,
                                                      'cities', (v_live->>'cities')::bigint, 'set_aside', (v_live->>'set_aside')::bigint,
                                                      'minted', s.minted, 'removed', s.removed, 'moved', s.moved, 'sold', t.sold, 'bought', t.bought)));
end $$;

create or replace function world.stats_markets()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: every good once, across every market that sells it: the mean price, its moves, what was traded, Σ stock vs
-- normal, a line. Public (an aggregate over all markets; no city can be read out of it).
-- 0232 (owner row 213): what was traded is NOW — `sold` / `bought` the minutes since the count, `*_1d` the count's 24 h
-- (stats_good.day) plus those minutes. The price, its moves, the stock and the line are the price record's, as the
-- count read them (the header of 0232: ~1,380 live prices a second do not fit the budget). `at` is now().
declare
  v_slot bigint;
  v_at   timestamptz;
begin
  -- the newest count's slot, from the world's row (its key is the slot; max(slot) of stats_good is a scan of every row
  -- — 62 ms on prod — and the job writes both in one transaction)
  select w.slot, w.at into v_slot, v_at from public.stats_world w order by w.slot desc limit 1;
  if v_slot is null or not exists (select 1 from public.stats_good x join public.goods g on g.id = x.good_id where x.slot = v_slot) then
    return jsonb_build_object('at', now(), 'counted_at', null, 'age_seconds', null, 'slot_seconds', public.wc_num('drift_slot_seconds'), 'goods', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'at', now(), 'counted_at', v_at, 'age_seconds', round(extract(epoch from now() - v_at)), 'slot_seconds', public.wc_num('drift_slot_seconds'),
    'goods', coalesce((
      select jsonb_agg(case when t.good_id is null then n.day
                            else n.day || jsonb_build_object(
                                   'sold', coalesce(t.sold, 0), 'bought', coalesce(t.bought, 0),
                                   'sold_1d', (n.day->>'sold_1d')::numeric + coalesce(t.sold, 0),
                                   'bought_1d', (n.day->>'bought_1d')::numeric + coalesce(t.bought, 0),
                                   'sold_ducats_1d', (n.day->>'sold_ducats_1d')::numeric + coalesce(t.sold_d, 0),
                                   'bought_ducats_1d', (n.day->>'bought_ducats_1d')::numeric + coalesce(t.bought_d, 0)) end
                       order by g.name)
        from public.stats_good n
        join public.goods g on g.id = n.good_id
        left join public.stats_window_goods(v_at, now()) t on t.good_id = n.good_id
       where n.slot = v_slot and n.day is not null), '[]'::jsonb));
end $$;

create or replace function world.stats_cities()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: every harbour: name, flag, the purse, works and the last day's income, spending, taxes and units.
-- 0223 (the owner: "on cities, i want to see all the info without investment"): served to EVERYONE.
-- 0232 (owner row 213): NOW — the purse is the live balance (public.treasury_balance), the works as they stand, and
-- every day-figure the count's 24 h (stats_city.day) plus the minutes since (public.stats_window_cities). `at` is now().
declare
  v_slot   bigint;
  v_at     timestamptz;
begin
  -- the newest count's slot, from the world's row (the job writes both in one transaction; see stats_markets)
  select w.slot, w.at into v_slot, v_at from public.stats_world w order by w.slot desc limit 1;
  return jsonb_build_object(
    'at', now(), 'counted_at', v_at, 'age_seconds', case when v_at is null then null else round(extract(epoch from now() - v_at)) end,
    'slot_seconds', public.wc_num('drift_slot_seconds'),
    'cities', coalesce((
      select jsonb_agg(
               coalesce(c.day->'row', jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name,
                                                         'nation', (select n.code from public.nations n where n.id = public.port_nation(p.id))))
               || case when c.port_id is not null then
                    jsonb_build_object('purse', public.treasury_balance(p.id),
                      'works', coalesce((select sum(w.level) from public.city_works w where w.port_id = p.id), 0),
                      'income_1d',   coalesce((c.day->>'income')::bigint, 0)   + coalesce(m.income, 0),
                      'spending_1d', coalesce((c.day->>'spending')::bigint, 0) + coalesce(m.spending, 0),
                      'taxes_1d',    coalesce((c.day->>'taxes')::bigint, 0)    + coalesce(m.taxes, 0),
                      'sold_1d',     coalesce((c.day->>'sold')::numeric, 0)    + coalesce(m.sold, 0),
                      'bought_1d',   coalesce((c.day->>'bought')::numeric, 0)  + coalesce(m.bought, 0))
                  else '{}'::jsonb end
               order by p.name)
        from public.ports p
        left join public.stats_city c on c.port_id = p.id and c.slot = v_slot
        left join public.stats_window_cities(v_at, now()) m on m.port_id = p.id
       where p.kind = 'HARBOUR'), '[]'::jsonb));
end $$;

create or replace function world.stats_city(p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: one harbour: the city, then `overview` and `detail` once the job has written its first row.
-- 0223 (the owner: "on cities, i want to see all the info without investment"): served to EVERYONE.
-- 0232 (owner row 213): NOW — the purse is the live balance; every day-figure, the money by kind and what it buys and
-- sells most are the count's 24 h plus the minutes since; each good's price and stock are LIVE (world.mid_price where
-- the city sells it); the purse line and the spark end at now(). `at` is now().
declare
  v_slot   bigint;
  v_at     timestamptz;
  v_ph     bigint := greatest(1, round(3600 / public.wc_num('drift_slot_seconds')))::bigint;
  v_purse  bigint := public.treasury_balance(p_port);
  v_out    jsonb;
  c        public.stats_city%rowtype;
  m        record;
begin
  if p_port is null or not exists (select 1 from public.ports p where p.id = p_port and p.kind = 'HARBOUR') then
    raise exception 'E_NO_SUCH_PORT: no harbour has that id' using errcode = 'P0001';
  end if;
  select * into c from public.stats_city x where x.port_id = p_port order by x.slot desc limit 1;
  v_slot := c.slot; v_at := c.at;
  v_out := jsonb_build_object(
    'city', (select jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name,
                                       'nation', (select n.code from public.nations n where n.id = public.port_nation(p.id)))
               from public.ports p where p.id = p_port),
    'at', now(), 'counted_at', v_at, 'age_seconds', case when v_at is null then null else round(extract(epoch from now() - v_at)) end,
    'slot_seconds', public.wc_num('drift_slot_seconds'));
  if v_slot is null then
    return v_out;
  end if;
  select w.income, w.spending, w.taxes, w.sold, w.bought, w.kinds into m
    from public.stats_window_cities(v_at, now()) w where w.port_id = p_port;
  v_out := v_out || jsonb_build_object('overview', jsonb_build_object(
    'purse', v_purse,
    'works', (select coalesce(jsonb_agg(jsonb_build_object('kind', w.kind, 'level', w.level) order by w.kind), '[]'::jsonb)
                from public.city_works w where w.port_id = p_port),
    'income_1d',   coalesce((c.day->>'income')::bigint, 0)   + coalesce(m.income, 0),
    'spending_1d', coalesce((c.day->>'spending')::bigint, 0) + coalesce(m.spending, 0),
    'taxes_1d',    coalesce((c.day->>'taxes')::bigint, 0)    + coalesce(m.taxes, 0),
    'sold_1d',     coalesce((c.day->>'sold')::numeric, 0)    + coalesce(m.sold, 0),
    'bought_1d',   coalesce((c.day->>'bought')::numeric, 0)  + coalesce(m.bought, 0),
    'flows_1d', public.stats_flow_lines((select jsonb_object_agg(k.kind, k.s)
                                            from (select x.kind, sum(x.v) as s
                                                    from (select e.key as kind, e.value::bigint as v from jsonb_each_text(coalesce(c.day->'kinds', '{}'::jsonb)) e
                                                          union all
                                                          select e.key, e.value::bigint from jsonb_each_text(coalesce(m.kinds, '{}'::jsonb)) e) x
                                                   group by x.kind) k)),
    'series', coalesce((select jsonb_agg(jsonb_build_object('at', x.at, 'purse', x.purse, 'income', x.income, 'spending', x.spending) order by x.slot)
                          from public.stats_city x where x.port_id = p_port and x.slot > v_slot - 7 * 24 * v_ph and x.slot <= v_slot), '[]'::jsonb)
              || jsonb_build_array(jsonb_build_object('at', now(), 'purse', v_purse, 'income', coalesce(m.income, 0), 'spending', coalesce(m.spending, 0))),
    'top_sold', coalesce((select jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'units', s.u, 'ducats', s.d) order by s.u desc, g.name)
                            from (select y.good_id, sum(y.u) as u, sum(y.d) as d
                                    from (select x.good_id, x.sold as u, x.sold_ducats as d from public.stats_city_good x
                                           where x.port_id = p_port and x.slot > v_slot - 24 * v_ph and x.slot <= v_slot
                                          union all
                                          select t.good_id, t.sold, t.sold_d from public.stats_window_city_goods(v_at, now()) t where t.port_id = p_port) y
                                   group by y.good_id having sum(y.u) > 0 order by 2 desc limit 5) s
                            join public.goods g on g.id = s.good_id), '[]'::jsonb),
    'top_bought', coalesce((select jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'units', s.u, 'ducats', s.d) order by s.u desc, g.name)
                              from (select y.good_id, sum(y.u) as u, sum(y.d) as d
                                      from (select x.good_id, x.bought as u, x.bought_ducats as d from public.stats_city_good x
                                             where x.port_id = p_port and x.slot > v_slot - 24 * v_ph and x.slot <= v_slot
                                            union all
                                            select t.good_id, t.bought, t.bought_d from public.stats_window_city_goods(v_at, now()) t where t.port_id = p_port) y
                                     group by y.good_id having sum(y.u) > 0 order by 2 desc limit 5) s
                              join public.goods g on g.id = s.good_id), '[]'::jsonb)));
  v_out := v_out || jsonb_build_object('detail', jsonb_build_object('goods', coalesce((
    select jsonb_agg(jsonb_build_object(
             'code', g.code, 'name', g.name, 'category', g.category,
             'mid', q.mid, 'stock', case when x.stock is not null then pg.stock end, 'stock_target', x.stock_target,
             'mid_1d', (select y.mid from public.stats_city_good y where y.port_id = p_port and y.good_id = g.id
                          and y.slot <= v_slot - 24 * v_ph and y.mid is not null order by y.slot desc limit 1),
             'sold_1d',   (select coalesce(sum(y.sold), 0) from public.stats_city_good y
                            where y.port_id = p_port and y.good_id = g.id and y.slot > v_slot - 24 * v_ph and y.slot <= v_slot) + coalesce(t.sold, 0),
             'bought_1d', (select coalesce(sum(y.bought), 0) from public.stats_city_good y
                            where y.port_id = p_port and y.good_id = g.id and y.slot > v_slot - 24 * v_ph and y.slot <= v_slot) + coalesce(t.bought, 0),
             'spark', (select coalesce(jsonb_agg(s.mid order by s.slot), '[]'::jsonb)
                         from (select y.mid, y.slot from public.stats_city_good y where y.port_id = p_port and y.good_id = g.id and y.mid is not null
                                order by y.slot desc limit case when q.mid is null then 24 else 23 end) s)
                      || case when q.mid is null then '[]'::jsonb else jsonb_build_array(q.mid) end)
           order by g.name)
      from public.stats_city_good x
      join public.goods g on g.id = x.good_id
      left join public.port_goods pg on pg.port_id = p_port and pg.good_id = x.good_id
      left join public.stats_window_city_goods(v_at, now()) t on t.port_id = p_port and t.good_id = x.good_id
      cross join lateral (select case when x.mid is not null and pg.good_id is not null
                                      then world.mid_price(p_port, x.good_id, pg.stock) end as mid) q
     where x.port_id = p_port and x.slot = v_slot), '[]'::jsonb)));
  return v_out;
end $$;

create or replace function world.stats_merchants()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: the merchant companies now, and the last day of them. Public (names, nations and day nets of companies the
-- world keeps; never a player's purse).
-- 0232 (owner row 213): NOW — where the fleets are (public.stats_merchant_fleets), their money (world.stats_now,
-- 0224), and the board over the count's 24 h of laps (stats_merchants.day) plus the laps closed since; the series
-- ends with a live point at now(). `at` is now().
declare
  m   public.stats_merchants%rowtype;
  v_f jsonb;
  v_b jsonb;
  v_p bigint;
begin
  select * into m from public.stats_merchants order by slot desc limit 1;
  if m.slot is null then
    return jsonb_build_object('at', now(), 'counted_at', null, 'age_seconds', null, 'slot_seconds', public.wc_num('drift_slot_seconds'), 'series', '[]'::jsonb);
  end if;
  v_f := public.stats_merchant_fleets();
  v_p := (world.stats_now()->>'merchants')::bigint;
  v_b := case when m.day is null
              then jsonb_build_object('profit_day', m.profit_day, 'laps_day', m.laps_day, 'losing_pct', m.losing_pct, 'top', m.top, 'bottom', m.bottom)
              else public.stats_merchants_board(public.stats_merchants_add(m.day, public.stats_merchants_window(m.at, now()))) end;
  return jsonb_build_object(
    'at', now(), 'counted_at', m.at, 'age_seconds', round(extract(epoch from now() - m.at)), 'slot_seconds', public.wc_num('drift_slot_seconds'),
    'houses', (v_f->>'houses')::int, 'fleets', (v_f->>'fleets')::int, 'sailing', (v_f->>'sailing')::int, 'docked', (v_f->>'docked')::int,
    'repairing', (v_f->>'repairing')::int, 'unable', (v_f->>'unable')::int, 'laid_up', (v_f->>'laid_up')::int, 'purse', v_p,
    'profit_day', (v_b->>'profit_day')::bigint, 'laps_day', (v_b->>'laps_day')::int, 'losing_pct', (v_b->>'losing_pct')::numeric,
    'top', v_b->'top', 'bottom', v_b->'bottom',
    'series', coalesce((select jsonb_agg(jsonb_build_object('at', x.at, 'profit_day', x.profit_day, 'purse', x.purse, 'sailing', x.sailing,
                                                            'laid_up', x.laid_up, 'losing_pct', x.losing_pct) order by x.slot)
                          from public.stats_merchants x where x.at > m.at - interval '24 hours'), '[]'::jsonb)
              || jsonb_build_array(jsonb_build_object('at', now(), 'profit_day', (v_b->>'profit_day')::bigint, 'purse', v_p,
                                                      'sailing', (v_f->>'sailing')::int, 'laid_up', (v_f->>'laid_up')::int,
                                                      'losing_pct', (v_b->>'losing_pct')::numeric)));
end $$;

-- the five reads keep what they were (ACL, owner, volatility, definer, config)
do $$
declare
  d record;
  p record;
begin
  for d in select * from defs_before_0232 where guard is not null loop
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0232 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config', d.fn, d.acl, p.acl;
    end if;
  end loop;
end $$;

-- ── 5. THE SEED: the newest count's 24 h, kept on its rows ─────────────────────────────────────
do $$
declare
  v_slot bigint;
begin
  select max(slot) into v_slot from public.stats_good;
  if v_slot is not null then
    perform public.stats_fold_day(v_slot);
  end if;
  update public.stats_merchants m
     set day = public.stats_merchants_window(m.at - interval '24 hours', m.at)
   where m.slot = (select max(x.slot) from public.stats_merchants x);
end $$;

-- ── 6. THE PROOF ───────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0232-4000-8000-000000000002';
  v_lo     timestamptz := now() - interval '1 microsecond';   -- THIS transaction's instant: its own rows only
  v_p      uuid;
  v_f      uuid;
  v_g      uuid;
  v_code   text;
  v_port   uuid;
  v_route  uuid;
  v_house  text;
  v_sold   bigint;
  v_bought bigint;
  v_found  bigint;
  v_r      jsonb;
  v_j      jsonb;
  v_ok     boolean;
  v_flows  boolean;   -- the city purses are kept here (public.treasury_post wrote this transaction's flows)
  v_run    jsonb;
  v_out    jsonb := '{}'::jsonb;
  v_ms     numeric[];
  v_names  text[] := array['overview', 'markets', 'cities', 'city', 'merchants', 'me', 'books'];
  v_name   text;
  t0       timestamptz;
  i        int;
  r        record;
begin
  -- (a) what exists, and the walls
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname in ('stats_window_trades', 'stats_window_totals', 'stats_window_goods', 'stats_window_city_trades',
             'stats_window_city_goods', 'stats_window_flows', 'stats_window_cities', 'stats_window_founded', 'stats_window_kinds', 'stats_sides',
             'stats_merchant_fleets', 'stats_merchants_window', 'stats_merchants_add', 'stats_merchants_board', 'stats_fold_day')) <> 15 then
    raise exception '0232 self-assert FAIL: the fifteen functions are not all there';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and column_name = 'day'
        and table_name in ('stats_good', 'stats_city', 'stats_merchants')) <> 3 then
    raise exception '0232 self-assert FAIL: the three `day` columns are not all there';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0232)
     or has_function_privilege('authenticated', 'public.stats_window_trades(timestamptz, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.stats_fold_day(bigint)', 'execute')
     or not has_function_privilege('authenticated', 'world.stats_overview(integer)', 'execute')
     or has_function_privilege('anon', 'world.stats_overview(integer)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0232 self-assert FAIL: the registry, the grant wall or the read wall moved';
  end if;

  -- (b) the seed: the newest rows carry their 24 h
  if exists (select 1 from public.stats_good where slot = (select max(slot) from public.stats_good) and day is null)
     or exists (select 1 from public.stats_city where slot = (select max(slot) from public.stats_city) and day is null)
     or exists (select 1 from public.stats_merchants where slot = (select max(slot) from public.stats_merchants) and day is null)
     or exists (select 1 from public.stats_good where slot < (select max(slot) from public.stats_good) and day is not null) then
    raise exception '0232 self-assert FAIL: the seed left a newest row without its day, or an older row with one';
  end if;

  -- (c) BY AMOUNT, pure
  -- (kinds whose side no file changes: FOUNDING is minted, SELL / BUY moved, an unknown kind moved; a removed kind is
  -- the words table's own — 0228 leaves none — so its arithmetic is asserted against whichever the table names)
  select * into r from public.stats_sides('{"FOUNDING": 100, "SELL": -50, "BUY": 20, "NO_SUCH_KIND": 7}'::jsonb);
  if r.minted <> 100 or r.removed <> 0 or r.moved <> 77 then
    raise exception '0232 self-assert FAIL: stats_sides read minted % removed % moved %, not 100 / 0 / 77', r.minted, r.removed, r.moved;
  end if;
  select * into r from public.stats_sides(coalesce((select jsonb_object_agg(w.kind, -30) from public.stats_flow_words w where w.side = 'removed'), '{}'::jsonb));
  if r.removed <> 30 * (select count(*) from public.stats_flow_words w where w.side = 'removed') or r.minted <> 0 then
    raise exception '0232 self-assert FAIL: the removed kinds read removed % minted %', r.removed, r.minted;
  end if;
  v_j := public.stats_merchants_board(public.stats_merchants_add(
           '{"net": 2, "n": 3, "neg": 1, "houses": [{"name": "A", "nation": "PRT", "day": 5, "laps": 2}, {"name": "B", "nation": null, "day": -3, "laps": 1}]}'::jsonb,
           '{"net": 11, "n": 2, "neg": 0, "houses": [{"name": "A", "nation": "PRT", "day": 2, "laps": 1}, {"name": "C", "nation": "ESP", "day": 9, "laps": 1}]}'::jsonb));
  if (v_j->>'profit_day')::bigint <> 13 or (v_j->>'laps_day')::int <> 5 or (v_j->>'losing_pct')::numeric <> 20.0
     or v_j->'top' <> '[{"name": "C", "nation": "ESP", "day": 9, "laps": 1}, {"name": "A", "nation": "PRT", "day": 7, "laps": 3}, {"name": "B", "nation": null, "day": -3, "laps": 1}]'::jsonb
     or v_j->'bottom'->0->>'name' <> 'B' then
    raise exception '0232 self-assert FAIL: two windows added and boarded read %', v_j;
  end if;

  -- (d) THE POSITIVE CONTROL, rolled back whole
  begin
    -- a world with no count yet (CI, a local world) gets one first, so every read has its newest row
    if not exists (select 1 from public.stats_world) then
      perform public.tick_stats(now() - interval '1 second');
    end if;

    -- a world whose city purses are dark (CI, a local world) lights them for the probe alone, so the city readings are
    -- proven by amount everywhere; on prod they are lit and nothing is written
    if not public.city_treasury_on() then
      update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
      perform public.treasury_post((select p.id from public.ports p where p.code = 'LIS'), 'SEED', 1000000);   -- a purse to buy with
    end if;
    v_p := public.new_house(c_uid, 'Casa do Segundo 0232', 'PRT', 'LIS');
    select f.id into v_f from public.fleets f where f.player_id = v_p order by f.id limit 1;
    select pg.port_id, pg.good_id, g.code into v_port, v_g, v_code
      from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
     where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask)
       and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)
     order by g.code limit 1;
    if v_g is null then
      raise exception '0232 self-assert FAIL: Lisbon offers no good with stock over 50 for the probe to trade';
    end if;
    perform public.fleet_load(v_f, v_code, 60, 1);
    v_r := cmd.do_sell(v_f, jsonb_build_object('good', v_g, 'qty', 10));
    v_r := cmd.do_buy(v_f, jsonb_build_object('good', v_g, 'qty', 5));
    select coalesce(sum(round((e.payload->>'total')::numeric)) filter (where e.kind = 'SOLD'), 0),
           coalesce(sum(round((e.payload->>'total')::numeric)) filter (where e.kind = 'BOUGHT'), 0)
      into v_sold, v_bought
      from public.events e where e.player_id = v_p and e.kind in ('SOLD', 'BOUGHT');
    select coalesce(sum(l.ducats_delta), 0) into v_found from public.ledger l where l.player_id = v_p and l.kind = 'FOUNDING';
    if v_sold <= 0 or v_bought <= 0 or v_found <= 0 then
      raise exception '0232 self-assert FAIL: the probe did not trade or was not founded (sold % bought % founded %)', v_sold, v_bought, v_found;
    end if;
    -- a lap of 777 closed now on a merchant's route
    select sr.id, p.company_name into v_route, v_house
      from public.standing_routes sr join public.players p on p.id = sr.player_id and p.is_npc order by sr.id limit 1;
    if v_route is not null then
      insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, net)
      values (v_route, (select coalesce(max(l.lap_no), 1) + 1 from public.standing_route_laps l where l.route_id = v_route),
              now() - interval '1 hour', now(), 777);
    end if;

    -- THE WINDOW FUNCTIONS, BY AMOUNT, over this transaction's instant (its own rows only)
    select * into r from public.stats_window_totals(v_lo, now());
    if r.trades <> 2 or r.units <> 15 or r.sold <> v_sold or r.bought <> v_bought then
      raise exception '0232 self-assert FAIL: the window read trades % units % sold % bought %, the probe made 2 / 15 / % / %', r.trades, r.units, r.sold, r.bought, v_sold, v_bought;
    end if;
    select * into r from public.stats_window_goods(v_lo, now()) w where w.good_id = v_g;
    if r.sold <> 10 or r.bought <> 5 or r.sold_d <> v_sold or r.bought_d <> v_bought
       or (select count(*) from public.stats_window_goods(v_lo, now())) <> 1 then
      raise exception '0232 self-assert FAIL: the window by good read % / % (% / % ducats)', r.sold, r.bought, r.sold_d, r.bought_d;
    end if;
    v_flows := exists (select 1 from public.treasury_flows f where f.created_at > v_lo);
    select * into r from public.stats_window_cities(v_lo, now()) w where w.port_id = v_port;
    if not v_flows then
      if r.port_id is not null then
        raise exception '0232 self-assert FAIL: no flow was written, yet the window has a row for Lisbon';
      end if;
    elsif r.sold <> 10 or r.bought <> 5
       or r.taxes <> (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.port_id = v_port and f.kind = 'TAX' and f.created_at > v_lo)
       or r.income - r.spending <> (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.port_id = v_port and f.created_at > v_lo)
       or (r.kinds->>'SELL') is null or (r.kinds->>'BUY') is null then
      raise exception '0232 self-assert FAIL: Lisbon''s window read sold % bought % taxes % in % out % kinds %', r.sold, r.bought, r.taxes, r.income, r.spending, r.kinds;
    end if;
    if (select w.ducats from public.stats_window_founded(v_lo, now()) w where w.kind = 'FOUNDING') <> v_found
       or (public.stats_window_kinds(v_lo, now())->>'FOUNDING')::bigint <> v_found then
      raise exception '0232 self-assert FAIL: the founding money (%) is not the window''s', v_found;
    end if;
    if v_route is not null then
      v_j := public.stats_merchants_window(v_lo, now());
      if (v_j->>'net')::bigint <> 777 or (v_j->>'n')::int <> 1 or (v_j->>'neg')::int <> 0
         or jsonb_array_length(v_j->'houses') <> 1 or v_j->'houses'->0->>'name' <> v_house or (v_j->'houses'->0->>'day')::bigint <> 777 then
        raise exception '0232 self-assert FAIL: the planted lap of 777 read %', v_j;
      end if;
    end if;

    -- THE READS: each, in ONE statement with its own window, is the count's figure + the minutes since — and the
    -- minutes since hold the probe (so each figure moved with it)
    select (o->'period'->>'trades')::bigint = w.trades and (o->'period'->>'trades')::bigint >= 2
           and (o->'day'->>'trades')::bigint = (select sum(x.trades) from public.stats_world x where x.at > l.at - interval '24 hours') + w.trades
           and (o->'day'->>'sold')::bigint = (select sum(x.sold) from public.stats_world x where x.at > l.at - interval '24 hours') + w.sold
           and (o->'holders'->>'players')::bigint = (n->>'players')::bigint and (o->'holders'->>'total')::bigint = (n->>'total')::bigint
           and (o->'series'->-1->>'at')::timestamptz = now() and (o->'series'->-1->>'sold')::bigint = w.sold
           and (o->>'counted_at')::timestamptz = l.at
      into v_ok
      from (select world.stats_overview(24) as o, world.stats_now() as n) q,
           (select * from public.stats_world order by slot desc limit 1) l,
           lateral public.stats_window_totals(l.at, now()) w;
    if not coalesce(v_ok, false) then
      raise exception '0232 self-assert FAIL: world.stats_overview is not the count + the minutes since: %', world.stats_overview(24);
    end if;
    select (x->>'sold_1d')::numeric = coalesce((n.day->>'sold_1d')::numeric, 0) + w.sold and (x->>'sold')::numeric = w.sold and w.sold >= 10
           and (x->>'bought_1d')::numeric = coalesce((n.day->>'bought_1d')::numeric, 0) + w.bought and w.bought >= 5
      into v_ok
      from (select world.stats_markets() as m) q,
           lateral jsonb_array_elements(q.m->'goods') x,
           public.stats_good n,
           lateral public.stats_window_goods(n.at, now()) w
     where x->>'code' = v_code and n.good_id = v_g and n.slot = (select max(slot) from public.stats_good) and w.good_id = v_g;
    if not coalesce(v_ok, false) then
      raise exception '0232 self-assert FAIL: world.stats_markets for % is not the count + the minutes since', v_code;
    end if;
    select (x->>'purse')::bigint = public.treasury_balance(v_port)
           and (x->>'sold_1d')::numeric = coalesce((c.day->>'sold')::numeric, 0) + coalesce(w.sold, 0) and (not v_flows or w.sold >= 10)
           and (x->>'income_1d')::bigint = coalesce((c.day->>'income')::bigint, 0) + coalesce(w.income, 0)
      into v_ok
      from (select world.stats_cities() as m) q
     cross join lateral jsonb_array_elements(q.m->'cities') x
     cross join public.stats_city c
      left join lateral (select * from public.stats_window_cities(c.at, now()) w0 where w0.port_id = v_port) w on true
     where x->>'id' = v_port::text and c.port_id = v_port and c.slot = (select max(slot) from public.stats_city);
    if not coalesce(v_ok, false) then
      raise exception '0232 self-assert FAIL: world.stats_cities for Lisbon is not the live purse + the count + the minutes since';
    end if;
    select (o->'overview'->>'purse')::bigint = public.treasury_balance(v_port)
           and (o->'overview'->>'sold_1d')::numeric = coalesce((c.day->>'sold')::numeric, 0) + coalesce(w.sold, 0)
           and (o->'overview'->'series'->-1->>'at')::timestamptz = now()
           and exists (select 1 from jsonb_array_elements(o->'detail'->'goods') g
                        where g->>'code' = v_code and (g->>'mid')::numeric = world.mid_price(v_port, v_g, (select pg.stock from public.port_goods pg where pg.port_id = v_port and pg.good_id = v_g))
                          and (g->>'stock')::numeric = (select pg.stock from public.port_goods pg where pg.port_id = v_port and pg.good_id = v_g)
                          and (g->'spark'->>-1)::numeric = (g->>'mid')::numeric
                          and (not v_flows or ((g->>'sold_1d')::numeric >= 10 and (g->>'bought_1d')::numeric >= 5)))
      into v_ok
      from (select world.stats_city(v_port) as o) q
     cross join public.stats_city c
      left join lateral (select * from public.stats_window_cities(c.at, now()) w0 where w0.port_id = v_port) w on true
     where c.port_id = v_port and c.slot = (select max(slot) from public.stats_city);
    if not coalesce(v_ok, false) then
      raise exception '0232 self-assert FAIL: world.stats_city for Lisbon is not live: %', world.stats_city(v_port);
    end if;
    select (o->>'profit_day')::bigint = coalesce((m.day->>'net')::bigint, m.profit_day) + (w.w->>'net')::bigint
           and (o->>'laps_day')::bigint = coalesce((m.day->>'n')::bigint, m.laps_day) + (w.w->>'n')::bigint
           and (o->>'purse')::bigint = (n->>'merchants')::bigint
           and (o->>'sailing')::int = (f->>'sailing')::int
           and (o->'series'->-1->>'at')::timestamptz = now()
           and (v_route is null or (w.w->>'net')::bigint >= 777)
      into v_ok
      from (select world.stats_merchants() as o, world.stats_now() as n, public.stats_merchant_fleets() as f) q,
           (select * from public.stats_merchants order by slot desc limit 1) m,
           lateral (select public.stats_merchants_window(m.at, now()) as w) w;
    if not coalesce(v_ok, false) then
      raise exception '0232 self-assert FAIL: world.stats_merchants is not the count + the laps since: %', world.stats_merchants();
    end if;

    -- (f) TIMINGS: each read ×6 in one session, as the probe company (world.stats_me / world.books need a caller)
    perform set_config('request.jwt.claim.sub', c_uid::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', c_uid)::text, true);
    if public.current_player_id() is distinct from v_p then
      raise exception '0232 self-assert FAIL: the probe is not the caller for the timings';
    end if;
    foreach v_name in array v_names loop
      v_ms := '{}';
      for i in 1..6 loop
        t0 := clock_timestamp();
        case v_name
          when 'overview' then perform world.stats_overview(24);
          when 'markets' then perform world.stats_markets();
          when 'cities' then perform world.stats_cities();
          when 'city' then perform world.stats_city(v_port);
          when 'merchants' then perform world.stats_merchants();
          when 'me' then perform world.stats_me();
          else perform world.books(7);
        end case;
        v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
      end loop;
      v_out := v_out || jsonb_build_object(v_name, to_jsonb(v_ms));
    end loop;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    raise exception using errcode = 'ZX227', message = jsonb_build_object('ms', v_out, 'good', v_code, 'sold', v_sold, 'bought', v_bought, 'lap', v_route is not null, 'flows', v_flows)::text;
  exception when sqlstate 'ZX227' then
    v_out := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.players where company_name = 'Casa do Segundo 0232') then
    raise exception '0232 self-assert FAIL: the probe survived its rollback';
  end if;

  -- (e) THE JOB RUNS (rolled back): a count two hours ahead — no slot the cron can reach meanwhile
  begin
    t0 := clock_timestamp();
    v_run := public.tick_stats(now() + interval '2 hours');
    if (v_run->>'world')::int <> 1 or (v_run->>'merchants')::int <> 1
       or (v_run->>'goods')::int <> (select count(*) from public.goods)
       or (v_run->>'cities')::int <> (select count(*) from public.ports where kind = 'HARBOUR')
       or (v_run->'day'->>'goods')::int <> (select count(*) from public.goods)
       or (v_run->'day'->>'cities')::int <> (select count(*) from public.ports where kind = 'HARBOUR')
       or (v_run->'live') is null then
      raise exception '0232 self-assert FAIL: the re-cut job wrote %', v_run;
    end if;
    if exists (select 1 from public.stats_good where slot < (v_run->>'slot')::bigint and day is not null)
       or exists (select 1 from public.stats_merchants where slot < (v_run->>'slot')::bigint and day is not null)
       or not exists (select 1 from public.stats_merchants where slot = (v_run->>'slot')::bigint and day is not null and top is not null)
       or exists (select 1 from public.stats_city where slot = (v_run->>'slot')::bigint and day is null) then
      raise exception '0232 self-assert FAIL: after the run `day` is not on the new slot alone';
    end if;
    raise exception using errcode = 'ZX227', message = jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - t0) * 1000), 'wrote', v_run->'wrote')::text;
  exception when sqlstate 'ZX227' then
    v_run := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.stats_world where at > now() + interval '1 hour') then
    raise exception '0232 self-assert FAIL: the trial count survived its rollback';
  end if;

  raise notice '0232 self-assert ok: EVERY FIGURE KEEPS TO THE SECOND. Fifteen window functions, the job re-cut by 10 hunks (each once, each reversing) and the five reads superseded. By amount: a probe company at Lisbon sold 10 and bought 5 of % (% / % ducats) and the window read trades 2, units 15, those ducats, the good 10 / 5, Lisbon 10 / 5, the founding money; a planted lap of 777 read 777 (planted: %; city flows kept here: %). Every read, in one statement, equals the count''s figure + the minutes since, with the probe in them; the city''s price is world.mid_price''s. The re-cut job ran once two hours ahead (rolled back) in % ms, wrote %, and kept `day` on the new slot alone. TIMINGS (ms, 6 calls each in one session): %. Registry unchanged; walls 0.',
    v_out->>'good', v_out->>'sold', v_out->>'bought', v_out->>'lap', v_out->>'flows', v_run->>'ms', v_run->>'wrote', v_out->'ms';
end $$;
