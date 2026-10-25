-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0224 — THE FIGURES KEEP TO THE SECOND
--        (the live figures of the Stats tab are kept CURRENT in the same transactions that change them,
--         through ONE helper; one read, world.stats_now(), serves them; the 15-minute rollup reconciles)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 200, 2026-10-25; it REPLACES row 187's default) ──
--   "i told you that stats, i want to be updated every second, is this possible? right now it updates
--    every 10? 15 min?"   — asked three times (rows 187, 200, and again in the queue).
--
-- ── WHAT 0214 BUILT, AND WHAT IT CANNOT DO ──────────────────────────────────────────────────────
-- 0214's public.tick_stats writes one rollup per 15-minute slot by SUMMING the game's tables (every
-- purse, every treasury, the period's events). Served every second that sum would be an aggregate scan
-- per viewer per second. So the figures a player watches move are kept as RUNNING COUNTERS instead:
-- a count is added to at the moment the world changes it, inside the writer's own transaction, and a
-- read of the counters costs one row plus the few rows written since the last count. The rollup, its
-- history tables and the charts stay exactly as 0214 left them; this file ADDS the live path.
--
-- ── ONE HELPER, ONE JOURNAL, ONE BASE ROW (the shape, and why not one UPDATE) ───────────────────
--   public.stats_live        ONE row: the figures as of the last count (`counted_at`, `counted_through`),
--                            written by public.stats_live_fold alone.
--   public.stats_live_deltas the journal: one row per change since that count, INSERTED by
--                            public.stats_live_add, the one helper every writer calls. Folded into the
--                            base row and deleted by stats_live_fold inside tick_stats, every 15 minutes.
--   world.stats_now()        the read: base + Σ journal, in one statement.
-- Why a journal and not `update stats_live set x = x + d`: an UPDATE takes the row lock until commit.
-- The merchants' tick holds its transaction for seconds while it credits house after house, and a player's
-- sale takes the harbour's advisory lock (public.treasury_post) before it would reach that row — a shared
-- row locked late, from transactions that already hold other locks in different orders, is a deadlock
-- waiting for a busy evening. An INSERT takes no shared lock: writers never wait on each other for the
-- figures, and the read sums at most one slot's worth of rows.
--
-- ── WHAT IS COUNTED, AND BY WHOM (each figure has ONE authority, and the hook sits in it) ───────
--   players, merchants   money by holder (Σ players.ducats by is_npc) — public.credit, THE ONE money mover
--                        (0004: the deferred constraint triggers make every other write of ducats fail).
--   cities               Σ public.treasury_balance — public.treasury_post, the one writer of a city's money.
--   set_aside            Σ open requests' escrow + Σ dividends accrued and not collected — the two tables
--                        themselves (trade_contracts, city_shares), through one trigger function,
--                        public.stats_live_track: escrow and accrued are written by four bodies
--                        (tick_contracts, run_fulfil, tick_city, collect_coupons) and the table is the
--                        one place they all pass through.
--   at_sea, at_sea_merchants   fleets whose status is SAILING (all; of merchants) — fleets.status, through
--                        the same trigger: depart, settle, divert and tow each write it, and a transition
--                        counted at the table cannot miss a writer this file did not read.
--   trades, units, sold, bought   SINCE THE LAST COUNT — cmd.do_sell and cmd.do_buy, the two bodies every
--                        sale and purchase in the game passes through (a merchant's lap goes
--                        cmd.advance → cmd.execute_order → the same two; cmd.preview's dry run rolls its
--                        journal row back with everything else). The definition of "a trade" is 0214's:
--                        a SOLD / BOUGHT event whose good is a goods row.
--   NOT counted here, said plainly (decided by default): minted / removed / moved money by kind stays a
--   15-minute period figure (its per-kind history is rolled into the daybook and carried, so no state
--   aggregate can reconcile it); a price index stays per slot because every price is re-drawn per slot
--   (0013) and only trades move one between slots; "players online" is not a figure this game keeps (no
--   presence column exists) and is not invented here.
--
-- ── THE RECONCILE (public.stats_live_fold, inside tick_stats, every count) ─────────────────────
-- ONE statement: delete the journal (returning its sums), recompute the five state aggregates, count the
-- trades stamped after the count's end (`p_through`), and set the base row — all under one snapshot, so a
-- transaction is either in the journal AND the aggregate or in neither. The state figures are SET to the
-- aggregate (so a missed writer can never drift for more than one slot) and the difference is kept as
-- `drift` (expected all zero; a non-zero state drift raises a WARNING with the figures). The trade
-- counters restart from the trades the row did not cover (stamped after p_through). A trade transaction
-- that straddles a count is attributed by its `created_at`, as 0214's windows already do.
--
-- ── ALSO FIXED IN tick_stats (one hunk) ────────────────────────────────────────────────────────
-- 0214's set_aside summed EVERY request's escrow, fulfilled and expired rows included (a lapsed escrow is
-- posted back to the city as BOUNTY_LAPSED and the row keeps its figure until pruned). The rollup now
-- sums OPEN requests only, the same sum the live figure keeps, so the two agree.
--
-- ── HUNKS SLICED FROM THE LIVE BODIES (each occurs once; reverses to its pre-image; ACL / volatility /
--    definer / config unchanged; this file SUPERSEDES nothing — it re-cuts seven bodies by one hunk) ──
--   public.credit ×2 (read is_npc; add), public.treasury_post ×1, cmd.do_sell ×1, cmd.do_buy ×1,
--   public.tick_stats ×2 (open escrow; the fold on the return), public.client_rpc_entry_points ×1.
--
-- ── WHAT IT SELF-ASSERTS (own probe rows; the whole probe is rolled back) ───────────────────────
--   (a) the two tables (server-only), the helper, the trigger function and its three triggers, the fold,
--       the read; registry +1 (authenticated, never anon); the three walls at 0.
--   (b) the seed: stats_now() equals the five state aggregates, trades since the count 0, the journal empty.
--   (c) POSITIVE CONTROLS, BY AMOUNT: a probe company founded at Lisbon sells 10 and buys 5 of one good
--       through cmd.do_sell / cmd.do_buy: trades 2, units 15, sold and bought equal the probe's own two
--       events' totals; every state figure still equals its aggregate in the same statement; her fleet
--       put to sea and brought back moves at_sea by exactly one each way; an open request's escrow and an
--       accrued dividend planted on the probe move set_aside by their amounts.
--   (d) the fold (through now() + 1 s): state drift all zero; trade counters 0 after it; one more buy → 1. No assert
--       counts or sums a table that grows on prod: the state aggregates are bounded tables (players, fleets, treasuries,
--       requests, shares), the events read is the probe's own rows, and tick_stats is never RUN here.
--   (e) TIMINGS, notice only: world.stats_now() ×6 in one session (target < 5 ms); cmd.do_sell and
--       cmd.do_buy ×6 BEFORE the hooks and ×6 AFTER; the status write a departure and an arrival make ×6
--       before and after the trigger (target: the added cost under 2 ms per write).
-- ROLLBACK (forward): drop the three triggers, the trigger function, the fold, the helper, the read, the
-- two tables; reverse the eight hunks (each old text is in this file).
-- VERSION: 0224 = prod head 0220 + 0221–0223 (ahead in the queue) + 1 at the time of writing — RENUMBER
-- TO PROD HEAD + 1 AT PUSH (and the _0224 suffixes, the probe uuid and this header's tags with it).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.stats_world') is null or to_regprocedure('public.tick_stats(timestamptz)') is null then
    raise exception '0224 refuses: 0214 (the stats rollup) is not in this world';
  end if;
  if to_regprocedure('public.credit(uuid, text, bigint, uuid)') is null
     or to_regprocedure('public.treasury_post(uuid, text, bigint, uuid, uuid, boolean)') is null
     or to_regprocedure('cmd.do_sell(uuid, jsonb)') is null or to_regprocedure('cmd.do_buy(uuid, jsonb)') is null
     or to_regclass('public.trade_contracts') is null or to_regclass('public.city_shares') is null then
    raise exception '0224 refuses: the writers of 0004, 0122, 0022, 0087 or 0123 are not in this world';
  end if;
  if to_regclass('public.stats_live') is not null then
    raise exception '0224 refuses: public.stats_live already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0224(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0224 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('public.credit(uuid,text,bigint,uuid)'),
               ('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)'),
               ('cmd.do_sell(uuid,jsonb)'),
               ('cmd.do_buy(uuid,jsonb)'),
               ('public.tick_stats(timestamptz)'),
               ('public.client_rpc_entry_points()')) f(fn);

create temp table before_0224 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- the probe's own set-up, in one place for the two timing runs and the proof: a company at Lisbon with 60
-- of a good Lisbon sells and the probe can buy (0194's pick, ordered — never a lottery)
create or replace function pg_temp.probe_0224(p_uid uuid, p_name text)
returns table (player uuid, fleet uuid, good uuid, good_code text, port uuid)
language plpgsql
as $$
declare v_p uuid; v_f uuid; v_g uuid; v_code text; v_port uuid;
begin
  v_p := public.new_house(p_uid, p_name, 'PRT', 'LIS');
  select f.id into v_f from public.fleets f where f.player_id = v_p order by f.id limit 1;
  select pg.port_id, pg.good_id, g.code into v_port, v_g, v_code
    from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
   where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask)
     and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)
   order by g.code limit 1;
  if v_g is null then
    raise exception '0224 self-assert FAIL: Lisbon offers no good with stock over 50 for the probe to trade';
  end if;
  perform public.fleet_load(v_f, v_code, 60, 1);
  return query select v_p, v_f, v_g, v_code, v_port;
end $$;

-- six timed trades and six timed status writes, as a jsonb of millisecond arrays (the caller rolls back)
create or replace function pg_temp.time_writers_0224(p_fleet uuid, p_good uuid, p_port uuid)
returns jsonb
language plpgsql
as $$
declare t0 timestamptz; v_sell numeric[] := '{}'; v_buy numeric[] := '{}'; v_status numeric[] := '{}'; i int;
begin
  for i in 1..6 loop
    t0 := clock_timestamp();
    perform cmd.do_sell(p_fleet, jsonb_build_object('good', p_good, 'qty', 1));
    v_sell := v_sell || round(extract(epoch from clock_timestamp() - t0) * 1000, 2);
  end loop;
  for i in 1..6 loop
    t0 := clock_timestamp();
    perform cmd.do_buy(p_fleet, jsonb_build_object('good', p_good, 'qty', 1));
    v_buy := v_buy || round(extract(epoch from clock_timestamp() - t0) * 1000, 2);
  end loop;
  -- the one row a departure (voyage.depart) and an arrival (voyage.settle) write to put her to sea / bring her in
  for i in 1..6 loop
    t0 := clock_timestamp();
    if i % 2 = 1 then
      update public.fleets set status = 'SAILING', port_id = null, lat = null, lon = null, version = version + 1 where id = p_fleet;
    else
      update public.fleets set status = 'DOCKED', port_id = p_port, lat = null, lon = null, version = version + 1 where id = p_fleet;
    end if;
    v_status := v_status || round(extract(epoch from clock_timestamp() - t0) * 1000, 2);
  end loop;
  return jsonb_build_object('do_sell', to_jsonb(v_sell), 'do_buy', to_jsonb(v_buy), 'status', to_jsonb(v_status));
end $$;

create temp table times_0224 (phase text, t jsonb) on commit drop;

-- (e) BEFORE: the writers as they are today, on a probe company that is rolled back
do $$
declare
  c_uid constant uuid := '00000000-0224-4000-8000-000000000001';
  pr record; v_t jsonb;
begin
  begin
    select * into pr from pg_temp.probe_0224(c_uid, 'Casa do Segundo 0224');
    v_t := pg_temp.time_writers_0224(pr.fleet, pr.good, pr.port);
    raise exception using errcode = 'ZX224', message = v_t::text;
  exception when sqlstate 'ZX224' then
    insert into times_0224 values ('before', sqlerrm::jsonb);
  end;
  if exists (select 1 from public.players where company_name = 'Casa do Segundo 0224') then
    raise exception '0224 self-assert FAIL: the timing probe survived its rollback';
  end if;
end $$;

-- ── 1. THE TABLES (server-only: RLS on, no client grant) ───────────────────────────────────────
create table public.stats_live (
  id               boolean primary key default true check (id),
  players          bigint not null default 0,
  merchants        bigint not null default 0,
  cities           bigint not null default 0,
  set_aside        bigint not null default 0,
  at_sea           bigint not null default 0,
  at_sea_merchants bigint not null default 0,
  trades           bigint not null default 0,
  units            numeric not null default 0,
  sold             bigint not null default 0,
  bought           bigint not null default 0,
  counted_through  timestamptz not null,
  counted_at       timestamptz not null default clock_timestamp(),
  folded           int not null default 0,
  drift            jsonb not null default '{}'::jsonb
);
comment on table public.stats_live is
  '0224: the live figures of the Stats tab as of the last count — money by holder (players, merchants, cities, set '
  'aside), fleets at sea (all, merchants), and the trades since the count (trades, units, sold, bought ducats). '
  'ONE row, written by public.stats_live_fold alone (inside public.tick_stats). The rows written since are in '
  'public.stats_live_deltas; world.stats_now() serves base + Σ deltas. `drift` = what the last fold corrected.';

create table public.stats_live_deltas (
  at               timestamptz not null default clock_timestamp(),
  players          bigint not null default 0,
  merchants        bigint not null default 0,
  cities           bigint not null default 0,
  set_aside        bigint not null default 0,
  at_sea           bigint not null default 0,
  at_sea_merchants bigint not null default 0,
  trades           bigint not null default 0,
  units            numeric not null default 0,
  sold             bigint not null default 0,
  bought           bigint not null default 0
);
comment on table public.stats_live_deltas is
  '0224: the journal of the live figures — one row per change, inserted by public.stats_live_add in the writer''s '
  'own transaction (an INSERT takes no shared lock, so writers never wait on each other for a figure). Folded into '
  'public.stats_live and deleted every count. No index: it holds at most one slot''s worth of rows.';

alter table public.stats_live        set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 50);
alter table public.stats_live_deltas set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);
alter table public.stats_live        enable row level security;
alter table public.stats_live_deltas enable row level security;
revoke all on table public.stats_live, public.stats_live_deltas from public, anon, authenticated;

-- ── 2. THE ONE HELPER, AND THE TRIGGER THAT CALLS IT FOR THE STATE TABLES ──────────────────────
create function public.stats_live_add(p jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0224: THE ONE way a live figure moves. `p` names the figures that changed and by how much:
-- {"players": -1234, "trades": 1, "units": 10, "sold": 1234}. One INSERT into the journal; nothing when every
-- delta is nought. A key that is not a figure is refused — a misspelt figure must fail loudly, never vanish.
declare
  r record;
  v_bad text;
begin
  select string_agg(k, ', ' order by k) into v_bad
    from jsonb_object_keys(p) k
   where k not in ('players', 'merchants', 'cities', 'set_aside', 'at_sea', 'at_sea_merchants', 'trades', 'units', 'sold', 'bought');
  if v_bad is not null then
    raise exception 'stats_live_add(): no such figure(s): %', v_bad;
  end if;
  select coalesce((p->>'players')::bigint, 0) as players, coalesce((p->>'merchants')::bigint, 0) as merchants,
         coalesce((p->>'cities')::bigint, 0) as cities, coalesce((p->>'set_aside')::bigint, 0) as set_aside,
         coalesce((p->>'at_sea')::bigint, 0) as at_sea, coalesce((p->>'at_sea_merchants')::bigint, 0) as at_sea_merchants,
         coalesce((p->>'trades')::bigint, 0) as trades, coalesce((p->>'units')::numeric, 0) as units,
         coalesce((p->>'sold')::bigint, 0) as sold, coalesce((p->>'bought')::bigint, 0) as bought
    into r;
  if r.players = 0 and r.merchants = 0 and r.cities = 0 and r.set_aside = 0 and r.at_sea = 0 and r.at_sea_merchants = 0
     and r.trades = 0 and r.units = 0 and r.sold = 0 and r.bought = 0 then
    return;
  end if;
  insert into public.stats_live_deltas (players, merchants, cities, set_aside, at_sea, at_sea_merchants, trades, units, sold, bought)
  values (r.players, r.merchants, r.cities, r.set_aside, r.at_sea, r.at_sea_merchants, r.trades, r.units, r.sold, r.bought);
end $$;
comment on function public.stats_live_add(jsonb) is
  '0224: the one helper every writer calls to move a live figure (public.credit, public.treasury_post, cmd.do_sell, '
  'cmd.do_buy, and public.stats_live_track for fleets / trade_contracts / city_shares). Server-only.';
revoke all on function public.stats_live_add(jsonb) from public, anon, authenticated;

create function public.stats_live_track()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0224: the state tables' doorway to the one helper — a fleet's status crossing SAILING, an open request's escrow,
-- a dividend accrued. The TABLE is the authority (the header says why), so a writer this file did not read is
-- counted the day it appears.
declare
  v_old bigint := 0;
  v_new bigint := 0;
  v_npc boolean;
begin
  if tg_table_name = 'fleets' then
    v_old := case when tg_op <> 'INSERT' and old.status = 'SAILING' then 1 else 0 end;
    v_new := case when tg_op <> 'DELETE' and new.status = 'SAILING' then 1 else 0 end;
    if v_new <> v_old then
      select p.is_npc into v_npc from public.players p
       where p.id = case when tg_op = 'DELETE' then old.player_id else new.player_id end;
      perform public.stats_live_add(jsonb_build_object('at_sea', v_new - v_old,
                                                       'at_sea_merchants', case when coalesce(v_npc, false) then v_new - v_old else 0 end));
    end if;
  elsif tg_table_name = 'trade_contracts' then
    v_old := case when tg_op <> 'INSERT' and old.status = 'open' then old.escrow else 0 end;
    v_new := case when tg_op <> 'DELETE' and new.status = 'open' then new.escrow else 0 end;
    if v_new <> v_old then
      perform public.stats_live_add(jsonb_build_object('set_aside', v_new - v_old));
    end if;
  elsif tg_table_name = 'city_shares' then
    v_old := case when tg_op <> 'INSERT' then old.accrued else 0 end;
    v_new := case when tg_op <> 'DELETE' then new.accrued else 0 end;
    if v_new <> v_old then
      perform public.stats_live_add(jsonb_build_object('set_aside', v_new - v_old));
    end if;
  else
    raise exception 'stats_live_track(): not written for table %', tg_table_name;
  end if;
  return null;
end $$;
comment on function public.stats_live_track() is
  '0224: after-row trigger on public.fleets (status), public.trade_contracts (status, escrow) and public.city_shares '
  '(accrued): hands the change to public.stats_live_add. Server-only.';
revoke all on function public.stats_live_track() from public, anon, authenticated;

create trigger fleets_stats_live
  after insert or update of status or delete on public.fleets
  for each row execute function public.stats_live_track();
create trigger trade_contracts_stats_live
  after insert or update of status, escrow or delete on public.trade_contracts
  for each row execute function public.stats_live_track();
create trigger city_shares_stats_live
  after insert or update of accrued or delete on public.city_shares
  for each row execute function public.stats_live_track();

-- ── 3. THE FOLD (the reconcile; one statement, one snapshot) ───────────────────────────────────
create function public.stats_live_fold(p_through timestamptz, p_seed boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0224: fold the journal into the base row and SET the state figures to their aggregates (header: the reconcile).
-- Everything below is ONE statement: the journal it deletes, the aggregates it reads and the trades it counts
-- share a snapshot, so a transaction is in all of them or in none. `drift` keeps base + journal − aggregate
-- (expected 0); the trade counters restart from the trades stamped after p_through — the ones the rollup's
-- window (… ≤ p_through, 0214) did not cover. A trade is what 0214 counts: a SOLD / BOUGHT event of a goods row.
declare
  r record;
begin
  with d as (
    delete from public.stats_live_deltas returning *
  ), s as (
    select count(*)::int as n,
           coalesce(sum(d.players), 0)::bigint as players, coalesce(sum(d.merchants), 0)::bigint as merchants,
           coalesce(sum(d.cities), 0)::bigint as cities, coalesce(sum(d.set_aside), 0)::bigint as set_aside,
           coalesce(sum(d.at_sea), 0)::bigint as at_sea, coalesce(sum(d.at_sea_merchants), 0)::bigint as at_sea_merchants,
           coalesce(sum(d.trades), 0)::bigint as trades, coalesce(sum(d.units), 0) as units,
           coalesce(sum(d.sold), 0)::bigint as sold, coalesce(sum(d.bought), 0)::bigint as bought
      from d
  ), a as (
    select (select coalesce(sum(p.ducats), 0) from public.players p where not p.is_npc)::bigint as players,
           (select coalesce(sum(p.ducats), 0) from public.players p where p.is_npc)::bigint as merchants,
           ((select coalesce(sum(t.ducats), 0) from public.port_treasury t)
            + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f))::bigint as cities,
           ((select coalesce(sum(c.escrow), 0) from public.trade_contracts c where c.status = 'open')
            + (select coalesce(sum(sh.accrued), 0) from public.city_shares sh))::bigint as set_aside,
           (select count(*) from public.fleets f where f.status = 'SAILING')::bigint as at_sea,
           (select count(*) from public.fleets f join public.players p on p.id = f.player_id
             where f.status = 'SAILING' and p.is_npc)::bigint as at_sea_merchants
  ), e as (   -- the trades since the LAST count, for the drift
    select count(*)::bigint as trades, coalesce(sum((x.payload->>'qty')::numeric), 0) as units,
           coalesce(sum(round((x.payload->>'total')::numeric)) filter (where x.kind = 'SOLD'), 0)::bigint as sold,
           coalesce(sum(round((x.payload->>'total')::numeric)) filter (where x.kind = 'BOUGHT'), 0)::bigint as bought
      from public.events x join public.goods g on g.name = x.payload->>'good'
     where x.kind in ('SOLD', 'BOUGHT') and x.created_at > (select l.counted_through from public.stats_live l)
  ), st as (  -- the trades stamped after THIS count's end: the next period's, already committed
    select count(*)::bigint as trades, coalesce(sum((x.payload->>'qty')::numeric), 0) as units,
           coalesce(sum(round((x.payload->>'total')::numeric)) filter (where x.kind = 'SOLD'), 0)::bigint as sold,
           coalesce(sum(round((x.payload->>'total')::numeric)) filter (where x.kind = 'BOUGHT'), 0)::bigint as bought
      from public.events x join public.goods g on g.name = x.payload->>'good'
     where x.kind in ('SOLD', 'BOUGHT') and x.created_at > p_through
  )
  update public.stats_live l
     set players = a.players, merchants = a.merchants, cities = a.cities, set_aside = a.set_aside,
         at_sea = a.at_sea, at_sea_merchants = a.at_sea_merchants,
         trades = st.trades, units = st.units, sold = st.sold, bought = st.bought,
         counted_through = p_through, counted_at = clock_timestamp(), folded = s.n,
         drift = jsonb_build_object(
           'players', l.players + s.players - a.players, 'merchants', l.merchants + s.merchants - a.merchants,
           'cities', l.cities + s.cities - a.cities, 'set_aside', l.set_aside + s.set_aside - a.set_aside,
           'at_sea', l.at_sea + s.at_sea - a.at_sea, 'at_sea_merchants', l.at_sea_merchants + s.at_sea_merchants - a.at_sea_merchants,
           'trades', l.trades + s.trades - e.trades, 'units', l.units + s.units - e.units,
           'sold', l.sold + s.sold - e.sold, 'bought', l.bought + s.bought - e.bought)
    from s, a, e, st
   where l.id
  returning l.drift, l.folded, l.counted_through, l.counted_at into r;
  if r.drift is null then
    raise exception 'stats_live_fold(): public.stats_live has no row';
  end if;
  if p_seed then   -- a fold from nothing (this file's seed): the difference is the seed itself, not a drift
    update public.stats_live set drift = '{}'::jsonb;
    r.drift := '{}'::jsonb;
  elsif (r.drift->>'players')::bigint <> 0 or (r.drift->>'merchants')::bigint <> 0 or (r.drift->>'cities')::bigint <> 0
     or (r.drift->>'set_aside')::bigint <> 0 or (r.drift->>'at_sea')::bigint <> 0 or (r.drift->>'at_sea_merchants')::bigint <> 0 then
    raise warning '0224 stats_live: a state figure had drifted and was set to its aggregate: %', r.drift;
  end if;
  return jsonb_build_object('drift', r.drift, 'folded', r.folded, 'through', r.counted_through, 'at', r.counted_at);
end $$;
comment on function public.stats_live_fold(timestamptz, boolean) is
  '0224: the reconcile — folds public.stats_live_deltas into public.stats_live, sets every state figure to its '
  'aggregate in the same snapshot and keeps the difference as drift. Called by public.tick_stats on each count. '
  'Server-only.';
revoke all on function public.stats_live_fold(timestamptz, boolean) from public, anon, authenticated;

-- ── 4. THE READ ────────────────────────────────────────────────────────────────────────────────
create function world.stats_now()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0224: the live figures, this second: the base row plus everything journalled since the last count. Public.
  select jsonb_build_object(
           'at', now(),
           'players', l.players + d.players, 'merchants', l.merchants + d.merchants,
           'cities', l.cities + d.cities, 'set_aside', l.set_aside + d.set_aside,
           'total', l.players + d.players + l.merchants + d.merchants + l.cities + d.cities + l.set_aside + d.set_aside,
           'at_sea', l.at_sea + d.at_sea, 'at_sea_merchants', l.at_sea_merchants + d.at_sea_merchants,
           'since_count', jsonb_build_object('trades', l.trades + d.trades, 'units', l.units + d.units,
                                             'sold', l.sold + d.sold, 'bought', l.bought + d.bought),
           'counted_at', l.counted_at, 'counted_through', l.counted_through, 'drift', l.drift)
    from public.stats_live l,
         (select coalesce(sum(x.players), 0)::bigint as players, coalesce(sum(x.merchants), 0)::bigint as merchants,
                 coalesce(sum(x.cities), 0)::bigint as cities, coalesce(sum(x.set_aside), 0)::bigint as set_aside,
                 coalesce(sum(x.at_sea), 0)::bigint as at_sea, coalesce(sum(x.at_sea_merchants), 0)::bigint as at_sea_merchants,
                 coalesce(sum(x.trades), 0)::bigint as trades, coalesce(sum(x.units), 0) as units,
                 coalesce(sum(x.sold), 0)::bigint as sold, coalesce(sum(x.bought), 0)::bigint as bought
            from public.stats_live_deltas x) d
$$;
comment on function world.stats_now() is
  '0224: the Stats tab''s one live read — money by holder, fleets at sea, the trades since the last count, and when '
  'that count was. Asked every second while the tab is open. Public (authenticated).';
revoke all on function world.stats_now() from public, anon, authenticated;
grant execute on function world.stats_now() to authenticated;

-- ── 5. THE HUNKS ───────────────────────────────────────────────────────────────────────────────
create temp table hunks_0224 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0224 values
('public.credit(uuid,text,bigint,uuid)', 1,
$h$  v_after  bigint;
begin
  select ducats into v_before from public.players where id = p_player for update;
$h$,
$h$  v_after  bigint;
  v_npc    boolean;   -- 0224: whose purse — a player's or a merchant's — for the live figures
begin
  select ducats, is_npc into v_before, v_npc from public.players where id = p_player for update;
$h$),
('public.credit(uuid,text,bigint,uuid)', 2,
$h$  values (p_player, p_kind, p_delta, v_after, p_ref_event);
  return v_after;
$h$,
$h$  values (p_player, p_kind, p_delta, v_after, p_ref_event);
  -- 0224: the live figure moves in the same transaction as the purse (public.stats_live_add, the one helper)
  perform public.stats_live_add(jsonb_build_object(case when v_npc then 'merchants' else 'players' end, p_delta));
  return v_after;
$h$),
('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)', 1,
$h$  values (p_port, p_kind, p_delta, p_player, p_ref_event);
  return public.treasury_balance(p_port);
$h$,
$h$  values (p_port, p_kind, p_delta, p_player, p_ref_event);
  perform public.stats_live_add(jsonb_build_object('cities', p_delta));   -- 0224: the live figure, same transaction
  return public.treasury_balance(p_port);
$h$),
('cmd.do_sell(uuid,jsonb)', 1,
$h$  -- 0160 (K6): the captains seated in the fleet learn Trading from the coin that moved (0069's rate).
  perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num('fame_ducats_per_point'), 0);
$h$,
$h$  -- 0224: the live trade figures, in the sale's own transaction (public.stats_live_add, the one helper)
  perform public.stats_live_add(jsonb_build_object('trades', 1, 'units', q.units, 'sold', round(q.total)::bigint));
  -- 0160 (K6): the captains seated in the fleet learn Trading from the coin that moved (0069's rate).
  perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num('fame_ducats_per_point'), 0);
$h$),
('cmd.do_buy(uuid,jsonb)', 1,
$h$  -- 0160 (K6): the captains seated in the fleet learn Trading from the coin that moved (0069's rate).
  perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num('fame_ducats_per_point'), 0);
$h$,
$h$  -- 0224: the live trade figures, in the purchase's own transaction (public.stats_live_add, the one helper)
  perform public.stats_live_add(jsonb_build_object('trades', 1, 'units', q.units, 'bought', round(q.total)::bigint));
  -- 0160 (K6): the captains seated in the fleet learn Trading from the coin that moved (0069's rate).
  perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num('fame_ducats_per_point'), 0);
$h$),
('public.tick_stats(timestamptz)', 1,
$h$         coalesce((select sum(c.escrow) from public.trade_contracts c), 0) + coalesce((select sum(s.accrued) from public.city_shares s), 0),
$h$,
$h$         coalesce((select sum(c.escrow) from public.trade_contracts c where c.status = 'open'), 0) + coalesce((select sum(s.accrued) from public.city_shares s), 0),   -- 0224: OPEN requests only (a lapsed escrow went back to the city)
$h$),
('public.tick_stats(timestamptz)', 2,
$h$                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x,
$h$,
$h$                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x,
                            'live', public.stats_live_fold(p_now),   -- 0224: the live figures reconciled on every count
$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'sea_conditions',        '')
$h$,
$h$      ('world',       'sea_conditions',        ''),
      -- 0224: the Stats tab's live figures, asked every second while the tab is open.
      ('world',       'stats_now',             '')
$h$);

do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0224 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0224 where fn = d.fn order by n loop
      if pg_temp.occurs_0224(v_def, h.old) <> 1 then
        raise exception '0224 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0224(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0224 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0224(v_rev, h.new) <> 1 then
        raise exception '0224 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0224 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0224 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config (% → %)', d.fn, d.acl, p.acl, d.cfg, p.cfg;
    end if;
  end loop;
end $$;

-- ── 6. THE SEED: the base row, from the aggregates, through the one fold ───────────────────────
-- counted_through is a microsecond before this transaction's now(): an event this transaction stamps (the probe's)
-- is "after the count", as every real trade after the deploy will be.
insert into public.stats_live (counted_through) values (now() - interval '1 microsecond');
do $$
begin
  perform public.stats_live_fold(now() - interval '1 microsecond', true);
end $$;

-- ── 7. THE PROOF ───────────────────────────────────────────────────────────────────────────────
-- the identity every live figure must satisfy at EVERY instant: stats_now() against the aggregates, one statement
create or replace function pg_temp.identity_0224()
returns jsonb
language sql
as $$
  with n as (select world.stats_now() as v),
  a as (
    select (select coalesce(sum(p.ducats), 0) from public.players p where not p.is_npc)::bigint as players,
           (select coalesce(sum(p.ducats), 0) from public.players p where p.is_npc)::bigint as merchants,
           ((select coalesce(sum(t.ducats), 0) from public.port_treasury t)
            + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f))::bigint as cities,
           ((select coalesce(sum(c.escrow), 0) from public.trade_contracts c where c.status = 'open')
            + (select coalesce(sum(sh.accrued), 0) from public.city_shares sh))::bigint as set_aside,
           (select count(*) from public.fleets f where f.status = 'SAILING')::bigint as at_sea,
           (select count(*) from public.fleets f join public.players p on p.id = f.player_id
             where f.status = 'SAILING' and p.is_npc)::bigint as at_sea_merchants)
  select jsonb_build_object(
           'players', (n.v->>'players')::bigint - a.players, 'merchants', (n.v->>'merchants')::bigint - a.merchants,
           'cities', (n.v->>'cities')::bigint - a.cities, 'set_aside', (n.v->>'set_aside')::bigint - a.set_aside,
           'at_sea', (n.v->>'at_sea')::bigint - a.at_sea, 'at_sea_merchants', (n.v->>'at_sea_merchants')::bigint - a.at_sea_merchants,
           'total', (n.v->>'total')::bigint - (a.players + a.merchants + a.cities + a.set_aside))
    from n, a
$$;

do $$
declare
  c_uid    constant uuid := '00000000-0224-4000-8000-000000000001';
  c_zero   constant jsonb := '{"players": 0, "merchants": 0, "cities": 0, "set_aside": 0, "at_sea": 0, "at_sea_merchants": 0, "total": 0}'::jsonb;
  pr       record;
  v_id     jsonb;
  v_now    jsonb;
  v_sc     jsonb;
  v_fold   jsonb;
  v_r      jsonb;
  v_ev     record;
  v_sold   bigint;
  v_bought bigint;
  v_port   uuid;
  v_t      jsonb;
  v_out    jsonb;
  v_ms     numeric[] := '{}';
  t0       timestamptz;
  i        int;
  v_tbefore jsonb;
begin
  -- (a) what exists, and the walls
  if (select count(*) from pg_trigger t where t.tgname in ('fleets_stats_live', 'trade_contracts_stats_live', 'city_shares_stats_live') and not t.tgisinternal) <> 3 then
    raise exception '0224 self-assert FAIL: the three triggers are not all there';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0224) + 1
     or not has_function_privilege('authenticated', 'world.stats_now()', 'execute')
     or has_function_privilege('anon', 'world.stats_now()', 'execute')
     or has_function_privilege('authenticated', 'public.stats_live_add(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.stats_live_fold(timestamptz, boolean)', 'execute')
     or has_table_privilege('authenticated', 'public.stats_live', 'select')
     or has_table_privilege('authenticated', 'public.stats_live_deltas', 'select')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0224 self-assert FAIL: the registry, the grant wall or the read wall moved';
  end if;

  -- (b) the seed
  v_id := pg_temp.identity_0224();
  if v_id <> c_zero then
    raise exception '0224 self-assert FAIL: the seed does not equal the aggregates: %', v_id;
  end if;
  v_now := world.stats_now();
  if (v_now->'since_count'->>'trades')::bigint <> 0 or (select count(*) from public.stats_live_deltas) <> 0 or v_now->'drift' <> '{}'::jsonb then
    raise exception '0224 self-assert FAIL: the seed is not clean: %', v_now;
  end if;

  -- (c) + (d) + (e) the probe, rolled back whole
  begin
    select * into pr from pg_temp.probe_0224(c_uid, 'Casa do Segundo 0224');
    -- the founding money is a credit: the players' figure moved with it, and the identity holds
    v_id := pg_temp.identity_0224();
    if v_id <> c_zero or (select count(*) from public.stats_live_deltas where players > 0) < 1 then
      raise exception '0224 self-assert FAIL: after the founding the live figures do not equal the aggregates: %', v_id;
    end if;

    -- THE POSITIVE CONTROL, BY AMOUNT: she sells 10 and buys 5
    v_r := cmd.do_sell(pr.fleet, jsonb_build_object('good', pr.good, 'qty', 10));
    v_r := cmd.do_buy(pr.fleet, jsonb_build_object('good', pr.good, 'qty', 5));
    select coalesce(sum(round((e.payload->>'total')::numeric)) filter (where e.kind = 'SOLD'), 0),
           coalesce(sum(round((e.payload->>'total')::numeric)) filter (where e.kind = 'BOUGHT'), 0)
      into v_sold, v_bought
      from public.events e where e.player_id = pr.player and e.kind in ('SOLD', 'BOUGHT');
    v_now := world.stats_now();
    v_sc := v_now->'since_count';
    if (v_sc->>'trades')::bigint <> 2 or (v_sc->>'units')::numeric <> 15 or (v_sc->>'sold')::bigint <> v_sold
       or (v_sc->>'bought')::bigint <> v_bought or v_sold <= 0 or v_bought <= 0 then
      raise exception '0224 self-assert FAIL: a sale of 10 and a purchase of 5 (sold % / bought % by their events) read %', v_sold, v_bought, v_sc;
    end if;
    v_id := pg_temp.identity_0224();
    if v_id <> c_zero then
      raise exception '0224 self-assert FAIL: after the trades the live figures do not equal the aggregates: %', v_id;
    end if;

    -- to sea and back (the one row voyage.depart / voyage.settle write): at_sea +1, then −1; a player's, not a merchant's
    update public.fleets set status = 'SAILING', port_id = null, lat = null, lon = null, version = version + 1 where id = pr.fleet;
    if (select coalesce(sum(x.at_sea), 0) from public.stats_live_deltas x) <> 1
       or (select coalesce(sum(x.at_sea_merchants), 0) from public.stats_live_deltas x) <> 0
       or pg_temp.identity_0224() <> c_zero then
      raise exception '0224 self-assert FAIL: putting the probe fleet to sea did not move at_sea by one';
    end if;
    update public.fleets set status = 'DOCKED', port_id = pr.port, lat = null, lon = null, version = version + 1 where id = pr.fleet;
    if pg_temp.identity_0224() <> c_zero
       or (select coalesce(sum(x.at_sea), 0) from public.stats_live_deltas x) <> 0
       or (select coalesce(sum(x.at_sea_merchants), 0) from public.stats_live_deltas x) <> 0 then
      raise exception '0224 self-assert FAIL: bringing the probe fleet in did not move at_sea back';
    end if;

    -- set aside: an open request's escrow and an accrued dividend, planted on the probe's own rows
    select c.port_id into v_port from public.trade_contracts c where c.status = 'open' order by c.id limit 1;
    if v_port is not null then
      update public.trade_contracts set escrow = escrow + 777
       where id = (select c.id from public.trade_contracts c where c.status = 'open' order by c.id limit 1);
      if (select coalesce(sum(x.set_aside), 0) from public.stats_live_deltas x) <> 777 or pg_temp.identity_0224() <> c_zero then
        raise exception '0224 self-assert FAIL: 777 more escrow on an open request did not move set_aside by 777';
      end if;
    end if;
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day)
    values (pr.port, 'docks', pr.player, 1, 100, 55, world.game_day());
    if (select coalesce(sum(x.set_aside), 0) from public.stats_live_deltas x) <> (case when v_port is null then 55 else 832 end)   -- parenthesised: plpgsql's IF stops at a bare THEN
       or pg_temp.identity_0224() <> c_zero then
      raise exception '0224 self-assert FAIL: 55 accrued on a planted share did not move set_aside by 55';
    end if;

    -- (d) THE FOLD: state drift all zero; the trade counters restart at 0 (nothing is stamped after now() + 1 s)
    v_fold := public.stats_live_fold(now() + interval '1 second');
    if (v_fold->'drift'->>'players')::bigint <> 0 or (v_fold->'drift'->>'merchants')::bigint <> 0
       or (v_fold->'drift'->>'cities')::bigint <> 0 or (v_fold->'drift'->>'set_aside')::bigint <> 0
       or (v_fold->'drift'->>'at_sea')::bigint <> 0 or (v_fold->'drift'->>'at_sea_merchants')::bigint <> 0
       or (v_fold->>'folded')::int < 4 then
      raise exception '0224 self-assert FAIL: the fold found a drift, or folded too little: %', v_fold;
    end if;
    v_now := world.stats_now();
    if (v_now->'since_count'->>'trades')::bigint <> 0 or (select count(*) from public.stats_live_deltas) <> 0
       or pg_temp.identity_0224() <> c_zero then
      raise exception '0224 self-assert FAIL: after the fold the counters did not restart clean: %', v_now;
    end if;
    -- …and the next trade is counted from there
    v_r := cmd.do_buy(pr.fleet, jsonb_build_object('good', pr.good, 'qty', 1));
    v_now := world.stats_now();
    if (v_now->'since_count'->>'trades')::bigint <> 1 or (v_now->'since_count'->>'units')::numeric <> 1 then
      raise exception '0224 self-assert FAIL: a purchase after the fold read %', v_now->'since_count';
    end if;
    -- the rollup carries the fold on its return: proven by the hunk (it occurs once and reverses), never by RUNNING
    -- tick_stats here — on prod that would write and prune the 15-minute tables inside the deploy transaction, under a
    -- 2-s lock_timeout against the cron's own run, for no proof the hunk check does not already give.

    -- (e) AFTER: the same six-fold timings as before the hooks, and the read ×6
    v_t := pg_temp.time_writers_0224(pr.fleet, pr.good, pr.port);
    for i in 1..6 loop
      t0 := clock_timestamp();
      perform world.stats_now();
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0) * 1000, 2);
    end loop;
    raise exception using errcode = 'ZX224', message = jsonb_build_object('after', v_t, 'now', to_jsonb(v_ms), 'fold', v_fold,
      'good', pr.good_code, 'sold', v_sold, 'bought', v_bought)::text;
  exception when sqlstate 'ZX224' then
    v_out := sqlerrm::jsonb;
  end;

  -- (f) nothing of the probe survives; the live row is as the seed left it
  if exists (select 1 from public.players where id = pr.player) or (select count(*) from public.stats_live_deltas) <> 0
     or exists (select 1 from public.city_shares where player_id = pr.player) then
    raise exception '0224 self-assert FAIL: the probe survived its rollback';
  end if;
  if pg_temp.identity_0224() <> c_zero then
    raise exception '0224 self-assert FAIL: after the rollback the live figures do not equal the aggregates: %', pg_temp.identity_0224();
  end if;
  select t into v_tbefore from times_0224 where phase = 'before';
  raise notice '0224 self-assert ok: THE FIGURES KEEP TO THE SECOND. The seed equals the aggregates; a probe company at Lisbon sold 10 and bought 5 of % through cmd.do_sell / cmd.do_buy and the live read said trades 2, units 15, sold % and bought % (its own events'' totals) while every state figure still equalled its aggregate; to sea and back moved at_sea by one each way; escrow and an accrued dividend moved set_aside by their amounts; the fold found drift % and the counters restarted at 0, then 1 after one more purchase. TIMINGS (ms, 6 calls in one session): stats_now %; do_sell before % after %; do_buy before % after %; the status write before % after %. Registry +1 (authenticated, not anon); walls 0.',
    v_out->>'good', v_out->>'sold', v_out->>'bought', v_out->'fold'->'drift',
    v_out->'now', v_tbefore->'do_sell', v_out->'after'->'do_sell', v_tbefore->'do_buy', v_out->'after'->'do_buy',
    v_tbefore->'status', v_out->'after'->'status';
end $$;
