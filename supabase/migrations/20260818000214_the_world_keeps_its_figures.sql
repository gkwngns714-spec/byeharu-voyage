-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0214 — THE WORLD KEEPS ITS FIGURES  (the STATS tab: one job every fifteen minutes writes the world's
--        money, every good's market, every city's books and the merchants' day into its own tables; six
--        reads serve them; a city's figures are intelligence a company buys by investing there)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (2026-10-20) ────────────────────────────────────────────────────────────
--   "i want there to be a statistic tab along with command, map etc. where i can see the world economy,
--    npc economy, cities, trade good stocks, and much much more - that is updated regularly. like in stock
--    market how much was bought, left amount trading goods, how much price moved. etc."
--   "a statistic info of a city is added only when you invest certain amount."
--
-- ── WHAT EXISTS, AND WHY A ROLLUP (docs/dev-log/2026-10-20-stats-tab.md) ────────────────────────
-- Every figure the tab wants already has ONE authority: a purse is players.ducats (public.credit moves it,
-- 0004); a city's purse is public.treasury_balance (0122) and its books treasury_daybook + treasury_flows
-- (public.treasury_post writes, tick_city rolls hourly); a trade is a SOLD / BOUGHT event (0007) and, on the
-- city's side, a SELL / BUY flow carrying that event's id; a price is price_history's recorded mid (0013);
-- a merchant's day is route_earnings over standing_route_laps (0097). None of them keeps TIME: the ledger is
-- compacted for merchants (npc_compact, 6 h), the flows are rolled and deleted hourly, the price record keeps
-- twelve hours (0057). So "how much was bought in the last hour" and "the world's money a week ago" have no
-- answer today. This file ADDS a memory and DECIDES nothing: tick_stats only reads the game's tables and
-- writes its own five, keyed by the drift slot (public.drift_slot_of, 0013) so a retried run writes nothing
-- (ON CONFLICT DO NOTHING, 0013's idiom). It is not a second price, purse or trade authority: every number in
-- its rows is a sum of what the authorities above already said.
--
-- ── THE PERIOD, HONESTLY ─────────────────────────────────────────────────────────────────────────
-- A row's figures cover (previous row's at, this at]. Trades (events) and the ledger are append-only, so
-- their windows are exact. The WORLD's flows by kind are exact too: each row keeps `recent` = the newest
-- three game days' sums per kind over daybook + flows (the roll moves money between the two without
-- changing the sum; the carry only touches days older than treasury_days_kept), and the period is the
-- difference of two `recent`s. A CITY's flows by kind, and every per-city unit count, come from the flows
-- that still exist (joined to their event for the good and the quantity): tick_city deletes flows at :37,
-- so the job runs at :06 :21 :36 :51 and only the minute :36–:37 can be missed, once an hour, in the city
-- rows alone. Said here so nobody "fixes" a 1.7 % gap into a second clock.
--
-- ── MINTED, REMOVED, MOVED (one table, public.stats_flow_words) ─────────────────────────────────
-- A flow with no company on the other side is the world printing or burning money: IMPORT_DEMAND (0174),
-- EARNINGS (0172), SEED, CROWN_AID, GRANT are MINTED; CROWN_TAX is REMOVED. A company's founding money
-- (ledger FOUNDING) and a merchant's refound (ledger NPC_REFOUND) are minted to a house. Everything else —
-- BUY, SELL, TAX, WAGES, SHARE, DIVIDEND (set aside for the holders), WORKS_IN/OUT (a region's money between
-- its cities, Σ = 0 by 0123's own assert), BOUNTY (escrow), INSURANCE / INSURANCE_PAID (0213's premium and
-- payout) — only changes hands: MOVED, counted once per flow as its absolute value. The kinds are READ from the
-- flows themselves (treasury_flows / treasury_daybook, the one authority); this table only names and sides
-- them, and an unknown kind is moved and wears its own name, so a kind a later migration adds is counted
-- the day it appears, never dropped.
-- Money by holder: players · merchants (players.is_npc) · cities (Σ treasury_balance) · set aside (request
-- escrow + dividends accrued and not yet collected).
--
-- ── THE GATE (the owner's rule; decided by default where he did not say) ────────────────────────
-- The world's figures are public: the overview, every good's index across ALL markets (no city can be read
-- out of a sum over 1,348 pairs), the merchants' day, your own books and the leaderboard (rank and name;
-- no other company's purse, ever). A CITY's figures are gated by the VIEWER'S OWN stake there — the share
-- register public.city_shares (0123), Σ paid for (viewer, city), the same sum world.holdings prints — read
-- through public.stats_city_tier, the one place that turns a stake into a tier. Tier 0: the city is a locked
-- row (name, flag, what to invest). Tier 1 (≥ stats_city_tier1): purse trend, income and spending, taxes,
-- the goods it buys and sells most. Tier 2 (≥ stats_city_tier2): every good — price, stock vs normal,
-- bought / sold. ENFORCED HERE: world.stats_cities and world.stats_city build a city's figures only for the
-- tier the caller holds; the client never receives what it may not show. A merchant's stake is irrelevant
-- (the gate is per viewer). The thresholds are knobs, 20,000 and 100,000 🪙 (prod 2026-10-20: a share costs
-- 200–819 🪙; merchant lap nets p50 1,071 / p90 31,556; no player holds a share yet). The money fix (haul
-- cap) changes what a voyage earns: retune the two knobs, nothing else.
--
-- ── RETENTION (in the same job) ─────────────────────────────────────────────────────────────────
-- Fine rows for stats_fine_hours (72); the city-good table, the largest, for stats_city_good_fine_hours
-- (48); older than that, one row per UTC day is kept forever (the day's last slot) and the rest deleted.
-- Steady size ≈ 50 MB. Each table keeps one index, its key, and 0095's autovacuum settings. Three small
-- indexes are added to the game's tables so the job's windows are index scans, not seq scans of 66 MB:
-- events (created_at), ledger (created_at), standing_route_laps (closed_at). Measured on prod read-only
-- 2026-10-20: the laps window took 565 ms and the ledger 177 ms without them.
--
-- ── WHAT IT SELF-ASSERTS (its own probe rows; everything the probe plants is rolled back) ────────
--   (a) five tables, server-only; the three indexes; the knobs; the words table covers the live kinds.
--   (b) one run writes a world row, a row per good, a row per harbour, the offered pairs and a merchants
--       row; its sums equal the authorities recomputed inline; a second run in the same slot writes 0 rows.
--   (c) POSITIVE CONTROLS, BY AMOUNT: a probe company founded before run 1 (its FOUNDING in run 1's period);
--       then one sale planted as an event + its flows + credit (1,234 🪙 for 50 units, 100 tax), 5,000 🪙 SEED,
--       777 🪙 IMPORT_DEMAND and a 300 🪙 INSURANCE premium (0213's kind, read from the flow like any other):
--       the next row's minted 5,777, moved 1,634, sold 1,234, units 50, trades 1; players +834; cities +4,943;
--       the city's row income 6,177 / spending 1,234 / taxes 100 / sold 50 / INSURANCE 300; the city-good and
--       good rows 50; the overview's line "Insurance premiums" 300, moved.
--   (d) THE GATE: at 0 🪙 the city is locked (no figures served); at stats_city_tier1 the overview and no
--       detail; at stats_city_tier2 the detail with the probe good's 50 units.
--   (e) compaction keeps one row per old day, per table, under each table's own knob.
--   (f) registry +6 (authenticated, never anon); the three walls at 0; the job defined INACTIVE.
-- ROLLBACK (forward): drop the five tables, the words table, the eight functions, the three indexes, the
-- four knobs, the cron job; reverse the registry hunk.
-- VERSION: 0214 = prod head 0213 (insurance) + 1 at the time of writing — RENUMBER TO PROD HEAD + 1 AT PUSH
-- (and the _0214 suffixes, the probe uuid and this header's tags with it).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.treasury_balance(uuid)') is null or to_regprocedure('public.drift_slot_of(timestamptz)') is null
     or to_regprocedure('world.game_day(timestamptz)') is null or to_regclass('public.city_shares') is null
     or to_regclass('public.npc_fleets') is null or to_regclass('public.trade_contracts') is null then
    raise exception '0214 refuses: 0013, 0122, 0123, 0097 or 0087 is not in this world';
  end if;
  if to_regclass('public.stats_world') is not null then
    raise exception '0214 refuses: public.stats_world already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0214(p_hay text, p_needle text)
returns int language sql immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table before_0214 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def,
       (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure) as acl;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('stats_fine_hours', to_jsonb(72),
   '0214: how many real hours the stats tables keep a row per slot (public.tick_stats). Older rows are '
   'compacted to one per UTC day, kept forever.'),
  ('stats_city_good_fine_hours', to_jsonb(48),
   '0214: the same for public.stats_city_good, the largest table (one row per city per good per slot).'),
  ('stats_city_tier1', to_jsonb(20000),
   '0214 (owner: "a statistic info of a city is added only when you invest certain amount"): the stake in a '
   'city (Σ city_shares.paid for the viewer there) that opens its overview — purse, income and spending, '
   'taxes, what it buys and sells most. Retune with the economy; public.stats_city_tier reads it.'),
  ('stats_city_tier2', to_jsonb(100000),
   '0214: the stake that opens a city''s full detail — every good''s price, stock vs normal, bought and sold.')
on conflict (key) do nothing;

-- ── 2. THE TABLES (server-only: RLS on, no client grant; one index each, 0095''s autovacuum) ───
create table public.stats_world (
  slot       bigint primary key,
  at         timestamptz not null,
  game_day   int not null,
  players    bigint not null,
  merchants  bigint not null,
  cities     bigint not null,
  set_aside  bigint not null,
  minted     bigint not null,
  removed    bigint not null,
  moved      bigint not null,
  sold       bigint not null,
  bought     bigint not null,
  units      bigint not null,
  trades     int    not null,
  period     jsonb  not null,
  recent     jsonb  not null
);
comment on table public.stats_world is
  '0214: the world''s money by holder at each slot, and what moved since the previous row: minted, removed, '
  'moved (Σ |flow| over the moved kinds), sold / bought (ducats, from SOLD / BOUGHT events), units, trades. '
  '`period` is kind → ducats this period; `recent` is {game_day: {kind: ducats}} for the newest three game '
  'days over daybook + flows, the next row''s baseline. Written by public.tick_stats alone.';

create table public.stats_good (
  good_id       uuid   not null references public.goods(id) on delete cascade,
  slot          bigint not null,
  at            timestamptz not null,
  mid           numeric(12,4),
  markets       int    not null,
  stock         numeric(14,2) not null,
  stock_target  numeric(14,2) not null,
  sold          bigint not null,
  bought        bigint not null,
  sold_ducats   bigint not null,
  bought_ducats bigint not null,
  primary key (good_id, slot)
);
comment on table public.stats_good is
  '0214: one good across EVERY market that sells it (price_history''s newest slot): the mean mid, how many '
  'cities sell it, Σ stock and Σ normal stock there; and the units and ducats traded this period anywhere '
  '(sold = ships sold to cities, bought = ships bought from cities). Public: no city can be read out of it.';

create table public.stats_city (
  port_id  uuid   not null references public.ports(id) on delete cascade,
  slot     bigint not null,
  at       timestamptz not null,
  purse    bigint not null,
  income   bigint not null,
  spending bigint not null,
  taxes    bigint not null,
  works    int    not null,
  sold     bigint not null,
  bought   bigint not null,
  flows    jsonb  not null,
  primary key (port_id, slot)
);
comment on table public.stats_city is
  '0214: a harbour at each slot: its live purse (public.treasury_balance), its works'' levels summed, and '
  'this period''s flows by kind (income = Σ in, spending = Σ out, taxes = TAX) and units sold to / bought '
  'from it. GATED: served only at the viewer''s tier (public.stats_city_tier).';

create table public.stats_city_good (
  port_id       uuid   not null references public.ports(id) on delete cascade,
  good_id       uuid   not null references public.goods(id) on delete cascade,
  slot          bigint not null,
  at            timestamptz not null,
  mid           numeric(12,4),
  stock         numeric(12,2),
  stock_target  numeric(12,2),
  sold          bigint not null,
  bought        bigint not null,
  sold_ducats   bigint not null,
  bought_ducats bigint not null,
  primary key (port_id, good_id, slot)
);
comment on table public.stats_city_good is
  '0214: one good at one city: its recorded mid, stock and normal stock where the city sells it (null '
  'otherwise), and the units and ducats traded there this period. Rows exist for the offered pairs and for '
  'any pair that traded. GATED at tier 2.';

create table public.stats_merchants (
  slot       bigint primary key,
  at         timestamptz not null,
  houses     int not null,
  fleets     int not null,
  sailing    int not null,
  docked     int not null,
  repairing  int not null,
  unable     int not null,
  laid_up    int not null,
  purse      bigint not null,
  profit_day bigint not null,
  laps_day   int not null,
  losing_pct numeric(5,1) not null,
  top        jsonb not null,
  bottom     jsonb not null
);
comment on table public.stats_merchants is
  '0214: the merchant companies at each slot: how many, where their fleets are, their purses summed, the '
  'last 24 real hours of closed laps (lap 2 onwards, 0097''s rule): Σ net, count, the share that lost; the '
  'five best and five worst companies by that day (name, nation, day, laps). Public.';

create table public.stats_flow_words (
  kind text primary key,
  side text not null check (side in ('minted', 'removed', 'moved')),
  word text not null,
  ord  int  not null
);
comment on table public.stats_flow_words is
  '0214: THE one reading of a money flow''s kind for the Stats tab: minted / removed / moved, and the player''s '
  'word. A kind not here is moved and wears initcap(kind).';
insert into public.stats_flow_words (kind, side, word, ord) values
  ('IMPORT_DEMAND', 'minted',  'New money: import demand',        1),
  ('EARNINGS',      'minted',  'New money: townsfolk earnings',   2),
  ('SEED',          'minted',  'New money: city seed',            3),
  ('CROWN_AID',     'minted',  'New money: crown aid',            4),
  ('GRANT',         'minted',  'New money: grant',                5),
  ('FOUNDING',      'minted',  'New money: companies founded',    6),
  ('NPC_REFOUND',   'minted',  'New money: merchants refounded',  7),
  ('CROWN_TAX',     'removed', 'Crown tax',                       10),
  ('SELL',          'moved',   'Goods sold to cities',            20),
  ('BUY',           'moved',   'Goods bought from cities',        21),
  ('TAX',           'moved',   'Profit tax',                      22),
  ('WAGES',         'moved',   'Wages paid in port',              23),
  ('PROVISION',     'moved',   'Supplies',                        24),
  ('REPAIR',        'moved',   'Repairs',                         25),
  ('HIRE',          'moved',   'Hiring',                          26),
  ('SHARE',         'moved',   'Investments',                     27),
  ('DIVIDEND',      'moved',   'Dividends set aside',             28),
  ('DONATION',      'moved',   'Donations',                       29),
  ('WORKS_IN',      'moved',   'Works money between cities',      30),
  ('WORKS_OUT',     'moved',   'Works money between cities',      31),
  ('BOUNTY',        'moved',   'Request bounties',                32),
  ('BOUNTY_LAPSED', 'moved',   'Request bounties returned',       33),
  ('TOW',           'moved',   'Tows',                            34),
  -- 0213: a cargo's insurance — the premium a company pays a city, and what the city pays back on a loss
  ('INSURANCE',      'moved',  'Insurance premiums',              35),
  ('INSURANCE_PAID', 'moved',  'Insurance payouts',               36);

alter table public.stats_world      set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);
alter table public.stats_good       set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);
alter table public.stats_city       set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);
alter table public.stats_city_good  set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);
alter table public.stats_merchants  set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);
alter table public.stats_world      enable row level security;
alter table public.stats_good       enable row level security;
alter table public.stats_city       enable row level security;
alter table public.stats_city_good  enable row level security;
alter table public.stats_merchants  enable row level security;
alter table public.stats_flow_words enable row level security;
revoke all on table public.stats_world, public.stats_good, public.stats_city, public.stats_city_good,
                    public.stats_merchants, public.stats_flow_words from public, anon, authenticated;

-- the three windows the job reads, made index scans
create index if not exists events_created_at on public.events (created_at);
create index if not exists ledger_created_at on public.ledger (created_at);
create index if not exists standing_route_laps_closed_at on public.standing_route_laps (closed_at) where closed_at is not null;

-- ── 3. THE GATE: a stake becomes a tier, in one place ──────────────────────────────────────────
create function public.stats_city_tier(p_player uuid, p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0214: THE one reading of "what may this company see of this city": its stake there (Σ city_shares.paid,
  -- the register 0123 keeps and world.holdings prints), against the two knobs. `need` is what more buys the
  -- next tier (null at the top).
  with s as (
    select coalesce((select sum(c.paid) from public.city_shares c where c.player_id = p_player and c.port_id = p_port), 0)::bigint as paid,
           public.wc_num('stats_city_tier1')::bigint as t1,
           public.wc_num('stats_city_tier2')::bigint as t2
  )
  select jsonb_build_object(
           'paid', s.paid,
           'tier', case when s.paid >= s.t2 then 2 when s.paid >= s.t1 then 1 else 0 end,
           'need', case when s.paid >= s.t2 then null when s.paid >= s.t1 then s.t2 - s.paid else s.t1 - s.paid end,
           'tier1', s.t1, 'tier2', s.t2)
    from s
$$;
revoke all on function public.stats_city_tier(uuid, uuid) from public, anon, authenticated;

-- ── 4. THE JOB ─────────────────────────────────────────────────────────────────────────────────
create function public.tick_stats(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0214: one rollup per slot (header). Reads the game's tables; writes only stats_*. Idempotent by slot.
declare
  v_t0        timestamptz := clock_timestamp();
  v_slot      bigint := public.drift_slot_of(p_now);
  v_secs      numeric := public.wc_num('drift_slot_seconds');
  v_prev_at   timestamptz;
  v_prev_rec  jsonb;
  v_recent    jsonb;
  v_period    jsonb;
  v_minted    bigint;
  v_removed   bigint;
  v_moved     bigint;
  v_fine      interval := make_interval(hours => public.wc_int('stats_fine_hours'));
  v_fine_cg   interval := make_interval(hours => public.wc_int('stats_city_good_fine_hours'));
  v_ph_slot   bigint;
  v_w int := 0; v_g int := 0; v_c int := 0; v_cg int := 0; v_m int := 0; v_x int := 0; v_n int;
begin
  perform set_config('lock_timeout', '2s', true);
  if exists (select 1 from public.stats_world where slot = v_slot) then
    return jsonb_build_object('slot', v_slot, 'wrote', 0, 'at', p_now, 'note', 'this slot already has its row');
  end if;

  select w.at, w.recent into v_prev_at, v_prev_rec from public.stats_world w order by w.slot desc limit 1;
  v_prev_at := coalesce(v_prev_at, p_now - make_interval(secs => v_secs::double precision));
  v_ph_slot := (select max(h.slot) from public.price_history h where h.slot <= v_slot);

  -- the trades of the period, once: from the append-only events (the good and the fleet are NAMES there)
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

  -- THE WORLD: the newest three game days per kind over daybook + flows, and the period as the difference
  select coalesce(jsonb_object_agg(d.gd, d.kinds), '{}'::jsonb) into v_recent
    from (select x.gd, jsonb_object_agg(x.kind, x.s) as kinds
            from (select d.game_day as gd, d.kind, sum(d.ducats) as s
                    from public.treasury_daybook d
                   where d.kind <> 'CARRIED' and d.game_day >= world.game_day(p_now) - 2
                   group by 1, 2
                  union all
                  select world.game_day(f.created_at), f.kind, sum(f.ducats)
                    from public.treasury_flows f
                   where f.created_at <= p_now and world.game_day(f.created_at) >= world.game_day(p_now) - 2
                   group by 1, 2) x
           group by x.gd) d;
  select coalesce(jsonb_object_agg(k.kind, k.ducats) filter (where k.ducats <> 0), '{}'::jsonb) into v_period
    from (select n.kind, sum(n.v - coalesce((v_prev_rec -> n.gd ->> n.kind)::bigint, 0))::bigint as ducats
            from jsonb_each(v_recent) r(gd, kinds), jsonb_each_text(r.kinds) kv(kind, v0),
                 lateral (select r.gd, kv.kind, kv.v0::bigint as v) n
           where v_prev_rec is not null
           group by n.kind
          union all
          select l.kind, sum(l.ducats_delta)::bigint
            from public.ledger l
           where l.kind in ('FOUNDING', 'NPC_REFOUND') and l.created_at > v_prev_at and l.created_at <= p_now
           group by l.kind) k;
  select coalesce(sum(case when w.side = 'minted' then p.v end), 0),
         coalesce(sum(case when w.side = 'removed' then -p.v end), 0),
         coalesce(sum(case when coalesce(w.side, 'moved') = 'moved' then abs(p.v) end), 0)
    into v_minted, v_removed, v_moved
    from jsonb_each_text(v_period) p0(kind, v0), lateral (select p0.kind, p0.v0::bigint as v) p
    left join public.stats_flow_words w on w.kind = p.kind;

  insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside,
                                  minted, removed, moved, sold, bought, units, trades, period, recent)
  select v_slot, p_now, world.game_day(p_now),
         coalesce((select sum(p.ducats) from public.players p where not p.is_npc), 0),
         coalesce((select sum(p.ducats) from public.players p where p.is_npc), 0),
         coalesce((select sum(public.treasury_balance(t.port_id)) from public.port_treasury t), 0)
           + coalesce((select sum(f.ducats) from public.treasury_flows f where f.created_at <= p_now
                        and not exists (select 1 from public.port_treasury t where t.port_id = f.port_id)), 0),
         coalesce((select sum(c.escrow) from public.trade_contracts c), 0) + coalesce((select sum(s.accrued) from public.city_shares s), 0),
         v_minted, v_removed, v_moved,
         coalesce((select sum(t.total) from trades_0214 t where t.kind = 'SOLD'), 0),
         coalesce((select sum(t.total) from trades_0214 t where t.kind = 'BOUGHT'), 0),
         coalesce((select sum(t.qty) from trades_0214 t), 0),
         (select count(*) from trades_0214),
         v_period, v_recent
  on conflict (slot) do nothing;
  get diagnostics v_w = row_count;

  -- EVERY GOOD, across the markets that sell it
  insert into public.stats_good (good_id, slot, at, mid, markets, stock, stock_target, sold, bought, sold_ducats, bought_ducats)
  select g.id, v_slot, p_now, m.mid, coalesce(m.markets, 0), coalesce(m.stock, 0), coalesce(m.target, 0),
         coalesce(t.sold, 0), coalesce(t.bought, 0), coalesce(t.sold_d, 0), coalesce(t.bought_d, 0)
    from public.goods g
    left join (select h.good_id, avg(h.mid) as mid, count(*) as markets, sum(h.stock) as stock, sum(pg.stock_target) as target
                 from public.price_history h
                 join public.port_goods pg on pg.port_id = h.port_id and pg.good_id = h.good_id
                where h.slot = v_ph_slot
                group by h.good_id) m on m.good_id = g.id
    left join (select t.good_id,
                      sum(t.qty) filter (where t.kind = 'SOLD') as sold, sum(t.qty) filter (where t.kind = 'BOUGHT') as bought,
                      sum(t.total) filter (where t.kind = 'SOLD') as sold_d, sum(t.total) filter (where t.kind = 'BOUGHT') as bought_d
                 from trades_0214 t group by t.good_id) t on t.good_id = g.id
  on conflict (good_id, slot) do nothing;
  get diagnostics v_g = row_count;

  -- EVERY HARBOUR
  insert into public.stats_city (port_id, slot, at, purse, income, spending, taxes, works, sold, bought, flows)
  select p.id, v_slot, p_now, public.treasury_balance(p.id),
         coalesce((select sum(f.ducats) from city_flows_0214 f where f.port_id = p.id and f.ducats > 0), 0),
         coalesce((select -sum(f.ducats) from city_flows_0214 f where f.port_id = p.id and f.ducats < 0), 0),
         coalesce((select sum(f.ducats) from city_flows_0214 f where f.port_id = p.id and f.kind = 'TAX'), 0),
         coalesce((select sum(w.level) from public.city_works w where w.port_id = p.id), 0),
         coalesce((select sum(t.qty) from city_trades_0214 t where t.port_id = p.id and t.kind = 'SOLD'), 0),
         coalesce((select sum(t.qty) from city_trades_0214 t where t.port_id = p.id and t.kind = 'BOUGHT'), 0),
         coalesce((select jsonb_object_agg(f.kind, f.ducats) from city_flows_0214 f where f.port_id = p.id), '{}'::jsonb)
    from public.ports p
   where p.kind = 'HARBOUR'
  on conflict (port_id, slot) do nothing;
  get diagnostics v_c = row_count;

  -- EVERY (CITY, GOOD) the city sells or that traded there this period
  insert into public.stats_city_good (port_id, good_id, slot, at, mid, stock, stock_target, sold, bought, sold_ducats, bought_ducats)
  select k.port_id, k.good_id, v_slot, p_now, h.mid, h.stock, pg.stock_target,
         coalesce(t.sold, 0), coalesce(t.bought, 0), coalesce(t.sold_d, 0), coalesce(t.bought_d, 0)
    from (select h.port_id, h.good_id from public.price_history h where h.slot = v_ph_slot
          union
          select t.port_id, t.good_id from city_trades_0214 t) k
    left join public.price_history h on h.port_id = k.port_id and h.good_id = k.good_id and h.slot = v_ph_slot
    left join public.port_goods pg on pg.port_id = k.port_id and pg.good_id = k.good_id and h.good_id is not null
    left join (select t.port_id, t.good_id,
                      sum(t.qty) filter (where t.kind = 'SOLD') as sold, sum(t.qty) filter (where t.kind = 'BOUGHT') as bought,
                      sum(t.total) filter (where t.kind = 'SOLD') as sold_d, sum(t.total) filter (where t.kind = 'BOUGHT') as bought_d
                 from city_trades_0214 t group by 1, 2) t on t.port_id = k.port_id and t.good_id = k.good_id
  on conflict (port_id, good_id, slot) do nothing;
  get diagnostics v_cg = row_count;

  -- THE MERCHANTS: each company's last 24 real hours of closed laps (lap 2 onwards — 0097's rule: lap 1 holds a
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
  get diagnostics v_m = row_count;

  -- RETENTION: one row per UTC day past the fine window (the day's last slot), each table under its knob
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

  return jsonb_build_object('slot', v_slot, 'at', p_now, 'since', v_prev_at,
                            'wrote', v_w + v_g + v_c + v_cg + v_m, 'world', v_w, 'goods', v_g, 'cities', v_c,
                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $$;
comment on function public.tick_stats(timestamptz) is
  '0214: the stats job — one rollup per drift slot into stats_world / stats_good / stats_city / '
  'stats_city_good / stats_merchants, then the retention. Reads the game; writes only its own tables. '
  'Cron byeharu-voyage:stats at :06 :21 :36 :51. Server-only.';
revoke all on function public.tick_stats(timestamptz) from public, anon, authenticated;

-- ── 5. THE READS (registered; authenticated only; each reads the stats tables and the gate, decides nothing) ──
create function public.stats_flow_lines(p_kinds jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0214: kind → ducats becomes the player's lines: word, side, ducats, in the words table's order.
  select coalesce(jsonb_agg(jsonb_build_object('kind', e.key, 'word', coalesce(w.word, initcap(replace(lower(e.key), '_', ' '))),
                                               'side', coalesce(w.side, 'moved'), 'ducats', e.value::bigint)
                            order by coalesce(w.ord, 99), e.key), '[]'::jsonb)
    from jsonb_each_text(coalesce(p_kinds, '{}'::jsonb)) e
    left join public.stats_flow_words w on w.kind = e.key
$$;
revoke all on function public.stats_flow_lines(jsonb) from public, anon, authenticated;

create function world.stats_overview(p_hours int default 24)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: the world's money — by holder now and over the window; this period's and the last day's minted,
-- removed, moved, sold, bought, by kind. Public.
declare
  v_hours int := least(greatest(coalesce(p_hours, 24), 1), 24 * 30);
  l       public.stats_world%rowtype;
begin
  select * into l from public.stats_world order by slot desc limit 1;
  if l.slot is null then
    return jsonb_build_object('at', null, 'age_seconds', null, 'slot_seconds', public.wc_num('drift_slot_seconds'),
                              'hours', v_hours, 'holders', null, 'period', null, 'day', null, 'series', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'at', l.at,
    'age_seconds', round(extract(epoch from now() - l.at)),
    'slot_seconds', public.wc_num('drift_slot_seconds'),
    'hours', v_hours,
    'holders', jsonb_build_object('players', l.players, 'merchants', l.merchants, 'cities', l.cities, 'set_aside', l.set_aside,
                                  'total', l.players + l.merchants + l.cities + l.set_aside),
    'period', jsonb_build_object('since', (select max(w.at) from public.stats_world w where w.slot < l.slot),
                                 'minted', l.minted, 'removed', l.removed, 'moved', l.moved,
                                 'sold', l.sold, 'bought', l.bought, 'units', l.units, 'trades', l.trades,
                                 'flows', public.stats_flow_lines(l.period)),
    'day', (select jsonb_build_object('since', min(w.at), 'minted', sum(w.minted), 'removed', sum(w.removed), 'moved', sum(w.moved),
                                      'sold', sum(w.sold), 'bought', sum(w.bought), 'units', sum(w.units), 'trades', sum(w.trades),
                                      'flows', public.stats_flow_lines((select jsonb_object_agg(k.kind, k.s)
                                                                           from (select e.key as kind, sum(e.value::bigint) as s
                                                                                   from public.stats_world x, jsonb_each_text(x.period) e
                                                                                  where x.at > l.at - interval '24 hours'
                                                                                  group by e.key) k)))
              from public.stats_world w where w.at > l.at - interval '24 hours'),
    'series', coalesce((select jsonb_agg(jsonb_build_object('at', w.at, 'players', w.players, 'merchants', w.merchants, 'cities', w.cities,
                                                            'set_aside', w.set_aside, 'minted', w.minted, 'removed', w.removed,
                                                            'moved', w.moved, 'sold', w.sold, 'bought', w.bought) order by w.slot)
                          from public.stats_world w where w.at > l.at - make_interval(hours => v_hours)), '[]'::jsonb));
end $$;

create function world.stats_markets()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: every good once, across every market that sells it: the mean price now and 1 h / 1 d / 7 d ago, what
-- was traded this period and in the last day, Σ stock vs normal, and a 24-point line. Public (an aggregate
-- over all markets; no city can be read out of it).
declare
  v_slot bigint;
  v_at   timestamptz;
  v_ph   bigint := greatest(1, round(3600 / public.wc_num('drift_slot_seconds')))::bigint;   -- slots an hour
begin
  select max(slot) into v_slot from public.stats_good;
  if v_slot is null then
    return jsonb_build_object('at', null, 'age_seconds', null, 'slot_seconds', public.wc_num('drift_slot_seconds'), 'goods', '[]'::jsonb);
  end if;
  -- every row of a slot carries the same `at`, so any one of them is the one
  select at into v_at from public.stats_good where slot = v_slot limit 1;
  return jsonb_build_object(
    'at', v_at, 'age_seconds', round(extract(epoch from now() - v_at)), 'slot_seconds', public.wc_num('drift_slot_seconds'),
    'goods', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', g.code, 'name', g.name, 'category', g.category,
               'mid', n.mid, 'markets', n.markets, 'stock', n.stock, 'stock_target', n.stock_target,
               'sold', n.sold, 'bought', n.bought,
               'mid_1h', (select x.mid from public.stats_good x where x.good_id = g.id and x.slot <= v_slot - v_ph and x.mid is not null order by x.slot desc limit 1),
               'mid_1d', (select x.mid from public.stats_good x where x.good_id = g.id and x.slot <= v_slot - 24 * v_ph and x.mid is not null order by x.slot desc limit 1),
               'mid_7d', (select x.mid from public.stats_good x where x.good_id = g.id and x.slot <= v_slot - 7 * 24 * v_ph and x.mid is not null order by x.slot desc limit 1),
               'sold_1d', d.sold, 'bought_1d', d.bought, 'sold_ducats_1d', d.sold_d, 'bought_ducats_1d', d.bought_d,
               'spark', (select coalesce(jsonb_agg(s.mid order by s.slot), '[]'::jsonb)
                           from (select x.mid, x.slot from public.stats_good x where x.good_id = g.id and x.mid is not null order by x.slot desc limit 24) s))
             order by g.name)
        from public.stats_good n
        join public.goods g on g.id = n.good_id
        cross join lateral (select coalesce(sum(x.sold), 0) as sold, coalesce(sum(x.bought), 0) as bought,
                                   coalesce(sum(x.sold_ducats), 0) as sold_d, coalesce(sum(x.bought_ducats), 0) as bought_d
                              from public.stats_good x where x.good_id = g.id and x.at > v_at - interval '24 hours') d
       where n.slot = v_slot), '[]'::jsonb));
end $$;

create function world.stats_cities()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: every harbour with the CALLER'S tier there (public.stats_city_tier): name, flag, the stake and what more
-- opens the next tier for all; the purse, works and the last day's income, spending, taxes and units ONLY where
-- the caller holds tier 1 or more. The gate is here, not in the client.
declare
  v_player uuid := public.current_player_id();
  v_slot   bigint;
  v_at     timestamptz;
begin
  select max(slot) into v_slot from public.stats_city;
  select at into v_at from public.stats_city where slot = v_slot limit 1;
  return jsonb_build_object(
    'at', v_at, 'age_seconds', case when v_at is null then null else round(extract(epoch from now() - v_at)) end,
    'slot_seconds', public.wc_num('drift_slot_seconds'),
    'tier1', public.wc_num('stats_city_tier1')::bigint, 'tier2', public.wc_num('stats_city_tier2')::bigint,
    'cities', coalesce((
      select jsonb_agg(
               jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name,
                                  'nation', (select n.code from public.nations n where n.id = public.port_nation(p.id)),
                                  'tier', (t.t->>'tier')::int, 'paid', (t.t->>'paid')::bigint, 'need', (t.t->>'need')::bigint)
               || case when (t.t->>'tier')::int >= 1 and c.port_id is not null then
                    jsonb_build_object('purse', c.purse, 'works', c.works,
                      'income_1d',   (select coalesce(sum(x.income), 0)   from public.stats_city x where x.port_id = p.id and x.at > v_at - interval '24 hours'),
                      'spending_1d', (select coalesce(sum(x.spending), 0) from public.stats_city x where x.port_id = p.id and x.at > v_at - interval '24 hours'),
                      'taxes_1d',    (select coalesce(sum(x.taxes), 0)    from public.stats_city x where x.port_id = p.id and x.at > v_at - interval '24 hours'),
                      'sold_1d',     (select coalesce(sum(x.sold), 0)     from public.stats_city x where x.port_id = p.id and x.at > v_at - interval '24 hours'),
                      'bought_1d',   (select coalesce(sum(x.bought), 0)   from public.stats_city x where x.port_id = p.id and x.at > v_at - interval '24 hours'))
                  else '{}'::jsonb end
               order by p.name)
        from public.ports p
        left join public.stats_city c on c.port_id = p.id and c.slot = v_slot
        cross join lateral (select public.stats_city_tier(v_player, p.id) as t) t
       where p.kind = 'HARBOUR'), '[]'::jsonb));
end $$;

create function world.stats_city(p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: one harbour, at the caller's tier. Always: the city, the stake, the tier, what more opens the next.
-- Tier 1 adds `overview`; tier 2 adds `detail`. Nothing of a locked tier leaves the server.
declare
  v_player uuid := public.current_player_id();
  v_tier   jsonb;
  v_slot   bigint;
  v_at     timestamptz;
  v_ph     bigint := greatest(1, round(3600 / public.wc_num('drift_slot_seconds')))::bigint;
  v_out    jsonb;
  c        public.stats_city%rowtype;
begin
  if p_port is null or not exists (select 1 from public.ports p where p.id = p_port and p.kind = 'HARBOUR') then
    raise exception 'E_NO_SUCH_PORT: no harbour has that id' using errcode = 'P0001';
  end if;
  v_tier := public.stats_city_tier(v_player, p_port);
  select * into c from public.stats_city x where x.port_id = p_port order by x.slot desc limit 1;
  v_slot := c.slot; v_at := c.at;
  v_out := jsonb_build_object(
    'city', (select jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name,
                                       'nation', (select n.code from public.nations n where n.id = public.port_nation(p.id)))
               from public.ports p where p.id = p_port),
    'at', v_at, 'age_seconds', case when v_at is null then null else round(extract(epoch from now() - v_at)) end,
    'slot_seconds', public.wc_num('drift_slot_seconds')) || v_tier;
  if (v_tier->>'tier')::int >= 1 and v_slot is not null then
    v_out := v_out || jsonb_build_object('overview', jsonb_build_object(
      'purse', c.purse,
      'works', (select coalesce(jsonb_agg(jsonb_build_object('kind', w.kind, 'level', w.level) order by w.kind), '[]'::jsonb)
                  from public.city_works w where w.port_id = p_port),
      'income_1d',   (select coalesce(sum(x.income), 0)   from public.stats_city x where x.port_id = p_port and x.at > v_at - interval '24 hours'),
      'spending_1d', (select coalesce(sum(x.spending), 0) from public.stats_city x where x.port_id = p_port and x.at > v_at - interval '24 hours'),
      'taxes_1d',    (select coalesce(sum(x.taxes), 0)    from public.stats_city x where x.port_id = p_port and x.at > v_at - interval '24 hours'),
      'sold_1d',     (select coalesce(sum(x.sold), 0)     from public.stats_city x where x.port_id = p_port and x.at > v_at - interval '24 hours'),
      'bought_1d',   (select coalesce(sum(x.bought), 0)   from public.stats_city x where x.port_id = p_port and x.at > v_at - interval '24 hours'),
      'flows_1d', public.stats_flow_lines((select jsonb_object_agg(k.kind, k.s)
                                              from (select e.key as kind, sum(e.value::bigint) as s
                                                      from public.stats_city x, jsonb_each_text(x.flows) e
                                                     where x.port_id = p_port and x.at > v_at - interval '24 hours'
                                                     group by e.key) k)),
      'series', coalesce((select jsonb_agg(jsonb_build_object('at', x.at, 'purse', x.purse, 'income', x.income, 'spending', x.spending) order by x.slot)
                            from public.stats_city x where x.port_id = p_port and x.at > v_at - interval '7 days'), '[]'::jsonb),
      'top_sold', coalesce((select jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'units', s.u, 'ducats', s.d) order by s.u desc, g.name)
                              from (select x.good_id, sum(x.sold) as u, sum(x.sold_ducats) as d
                                      from public.stats_city_good x where x.port_id = p_port and x.at > v_at - interval '24 hours'
                                     group by x.good_id having sum(x.sold) > 0 order by 2 desc limit 5) s
                              join public.goods g on g.id = s.good_id), '[]'::jsonb),
      'top_bought', coalesce((select jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'units', s.u, 'ducats', s.d) order by s.u desc, g.name)
                                from (select x.good_id, sum(x.bought) as u, sum(x.bought_ducats) as d
                                        from public.stats_city_good x where x.port_id = p_port and x.at > v_at - interval '24 hours'
                                       group by x.good_id having sum(x.bought) > 0 order by 2 desc limit 5) s
                                join public.goods g on g.id = s.good_id), '[]'::jsonb)));
  end if;
  if (v_tier->>'tier')::int >= 2 and v_slot is not null then
    v_out := v_out || jsonb_build_object('detail', jsonb_build_object('goods', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', g.code, 'name', g.name, 'category', g.category,
               'mid', x.mid, 'stock', x.stock, 'stock_target', x.stock_target,
               'mid_1d', (select y.mid from public.stats_city_good y where y.port_id = p_port and y.good_id = g.id
                            and y.slot <= v_slot - 24 * v_ph and y.mid is not null order by y.slot desc limit 1),
               'sold_1d',   (select coalesce(sum(y.sold), 0)   from public.stats_city_good y where y.port_id = p_port and y.good_id = g.id and y.at > v_at - interval '24 hours'),
               'bought_1d', (select coalesce(sum(y.bought), 0) from public.stats_city_good y where y.port_id = p_port and y.good_id = g.id and y.at > v_at - interval '24 hours'),
               'spark', (select coalesce(jsonb_agg(s.mid order by s.slot), '[]'::jsonb)
                           from (select y.mid, y.slot from public.stats_city_good y where y.port_id = p_port and y.good_id = g.id and y.mid is not null
                                  order by y.slot desc limit 24) s))
             order by g.name)
        from public.stats_city_good x
        join public.goods g on g.id = x.good_id
       where x.port_id = p_port and x.slot = v_slot), '[]'::jsonb)));
  end if;
  return v_out;
end $$;

create function world.stats_merchants()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: the merchant companies now, and the last day of them. Public (names, nations and day nets of
-- companies the world keeps; never a player's purse).
declare
  m public.stats_merchants%rowtype;
begin
  select * into m from public.stats_merchants order by slot desc limit 1;
  if m.slot is null then
    return jsonb_build_object('at', null, 'age_seconds', null, 'slot_seconds', public.wc_num('drift_slot_seconds'), 'series', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'at', m.at, 'age_seconds', round(extract(epoch from now() - m.at)), 'slot_seconds', public.wc_num('drift_slot_seconds'),
    'houses', m.houses, 'fleets', m.fleets, 'sailing', m.sailing, 'docked', m.docked, 'repairing', m.repairing,
    'unable', m.unable, 'laid_up', m.laid_up, 'purse', m.purse,
    'profit_day', m.profit_day, 'laps_day', m.laps_day, 'losing_pct', m.losing_pct, 'top', m.top, 'bottom', m.bottom,
    'series', coalesce((select jsonb_agg(jsonb_build_object('at', x.at, 'profit_day', x.profit_day, 'purse', x.purse, 'sailing', x.sailing,
                                                            'laid_up', x.laid_up, 'losing_pct', x.losing_pct) order by x.slot)
                          from public.stats_merchants x where x.at > m.at - interval '24 hours'), '[]'::jsonb));
end $$;

create function world.stats_me()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0214: the caller's own week — best sales (own SOLD events, by profit), how many trades — and the
-- leaderboard: every company's RANK by purse, name and flag only. No other company's purse leaves here.
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no company signed in' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'best_trades', coalesce((select jsonb_agg(jsonb_build_object('at', e.created_at, 'good', e.payload->>'good',
                                                                 'qty', (e.payload->>'qty')::numeric, 'total', (e.payload->>'total')::numeric,
                                                                 'profit', (e.payload->>'profit')::numeric, 'fleet', e.payload->>'fleet')
                                              order by (e.payload->>'profit')::numeric desc, e.created_at desc)
                               from (select * from public.events e
                                      where e.player_id = v_player and e.kind = 'SOLD' and (e.payload->>'profit') is not null
                                        and e.created_at > now() - interval '7 days'
                                      order by (e.payload->>'profit')::numeric desc, e.created_at desc limit 5) e), '[]'::jsonb),
    'trades_7d', (select count(*) from public.events e where e.player_id = v_player and e.kind in ('SOLD', 'BOUGHT') and e.created_at > now() - interval '7 days'),
    'sold_7d',   (select coalesce(sum((e.payload->>'total')::numeric), 0) from public.events e where e.player_id = v_player and e.kind = 'SOLD' and e.created_at > now() - interval '7 days'),
    'bought_7d', (select coalesce(sum((e.payload->>'total')::numeric), 0) from public.events e where e.player_id = v_player and e.kind = 'BOUGHT' and e.created_at > now() - interval '7 days'),
    'leaderboard', (with r as (select p.id, p.company_name, n.code, rank() over (order by p.ducats desc, p.created_at, p.id) as rank
                                 from public.players p left join public.nations n on n.id = p.nation_id where not p.is_npc)
                    select jsonb_build_object(
                      'players', (select count(*) from r),
                      'you', (select r.rank from r where r.id = v_player),
                      'board', coalesce((select jsonb_agg(jsonb_build_object('rank', r.rank, 'name', r.company_name, 'nation', r.code, 'is_you', r.id = v_player) order by r.rank)
                                           from r where r.rank <= 10 or r.id = v_player), '[]'::jsonb))));
end $$;

revoke all on function world.stats_overview(int), world.stats_markets(), world.stats_cities(), world.stats_city(uuid),
                       world.stats_merchants(), world.stats_me() from public, anon, authenticated;
grant execute on function world.stats_overview(int), world.stats_markets(), world.stats_cities(), world.stats_city(uuid),
                          world.stats_merchants(), world.stats_me() to authenticated;

-- ── 6. THE JOB IS DEFINED, NOT RUNNING (0078): wind_the_clock() starts it with the rest of the clock ──
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0214: pg_cron is not installed here (PGlite) — byeharu-voyage:stats was NOT scheduled. Call public.tick_stats() by hand.';
    return;
  end if;
  perform cron.schedule('byeharu-voyage:stats', '6,21,36,51 * * * *', 'select public.tick_stats()');
  perform cron.alter_job(jobid, active := false) from cron.job where jobname = 'byeharu-voyage:stats';
  raise notice '0214: pg_cron present — byeharu-voyage:stats SCHEDULED BUT INACTIVE until wind_the_clock().';
end $$;

-- ── 7. THE REGISTRY (one hunk, sliced from the live body; reverses; ACL unchanged) ────────────
do $$
declare
  b     record;
  v_old text := $h$      ('world',       'insurance',             '')
$h$;
  v_new text := $h$      ('world',       'insurance',             ''),
      -- 0214: the Stats tab — the world's figures, every good, every city at your tier, the merchants, you.
      ('world',       'stats_overview',        'int'),
      ('world',       'stats_markets',         ''),
      ('world',       'stats_cities',          ''),
      ('world',       'stats_city',            'uuid'),
      ('world',       'stats_merchants',       ''),
      ('world',       'stats_me',              '')
$h$;
  v_rev text;
begin
  select * into b from before_0214;
  if pg_temp.occurs_0214(b.def, v_old) <> 1 then
    raise exception '0214 self-assert FAIL: the registry''s last row (0213''s insurance) occurs % time(s), not once — the deployed body is not what this file was written against',
      pg_temp.occurs_0214(b.def, v_old);
  end if;
  execute replace(b.def, v_old, v_new);
  v_rev := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if pg_temp.occurs_0214(v_rev, v_new) <> 1 or replace(v_rev, v_new, v_old) <> b.def then
    raise exception '0214 self-assert FAIL: the registry does not reverse to its pre-image';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure), '') <> b.acl then
    raise exception '0214 self-assert FAIL: the registry''s ACL moved';
  end if;
end $$;

-- ── 8. THE PROOF (own probe rows; the whole probe is rolled back) ──────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0214-4000-8000-000000000001';
  c_nil    constant uuid := '00000000-0000-0000-0000-000000000000';
  v_secs   numeric := public.wc_num('drift_slot_seconds');
  v_t1     timestamptz := now() + interval '1 second';
  v_t2     timestamptz;
  v_t3     timestamptz;
  v_port   uuid; v_code text; v_good uuid; v_gname text;
  v_p      uuid; v_ev uuid;
  v_r1 jsonb; v_r1b jsonb; v_r2 jsonb; v_r3 jsonb; v_v jsonb; v_row jsonb;
  w1 public.stats_world%rowtype; w2 public.stats_world%rowtype;
  c1 public.stats_city%rowtype;  c2 public.stats_city%rowtype;
  g1 public.stats_good%rowtype;  g2 public.stats_good%rowtype;
  v_n int; v_n2 int; v_mid numeric; v_offered int; v_founding bigint;
  v_t1ms numeric; v_t2ms numeric;
  v_old timestamptz; v_old_cg timestamptz; v_old_g timestamptz;
  v_out jsonb;
begin
  v_t2 := v_t1 + make_interval(secs => v_secs::double precision) + interval '19 seconds';
  v_t3 := v_t2 + make_interval(secs => v_secs::double precision);
  -- (a) the shape
  if (select count(*) from public.world_config where key in ('stats_fine_hours', 'stats_city_good_fine_hours', 'stats_city_tier1', 'stats_city_tier2')) <> 4 then
    raise exception '0214 self-assert FAIL: the four knobs are not all in world_config';
  end if;
  if (select count(*) from pg_indexes where indexname in ('events_created_at', 'ledger_created_at', 'standing_route_laps_closed_at')) <> 3 then
    raise exception '0214 self-assert FAIL: the three window indexes are not all there';
  end if;
  if exists (select 1 from information_schema.role_table_grants g
              where g.table_schema = 'public' and g.table_name like 'stats\_%' and g.grantee in ('anon', 'authenticated', 'PUBLIC')) then
    raise exception '0214 self-assert FAIL: a client role holds a grant on a stats table';
  end if;
  -- the words table names every kind the flows carry today (the amounts are read from the flows; a kind
  -- missing here would still count as moved, but would wear a made-up word)
  if exists (select 1 from (select distinct f.kind from public.treasury_flows f
                            union select distinct d.kind from public.treasury_daybook d where d.kind <> 'CARRIED') k
              where not exists (select 1 from public.stats_flow_words w where w.kind = k.kind)) then
    raise exception '0214 self-assert FAIL: flow kind(s) % have no line in stats_flow_words',
      (select string_agg(k.kind, ', ') from (select distinct f.kind from public.treasury_flows f
                                            union select distinct d.kind from public.treasury_daybook d where d.kind <> 'CARRIED') k
        where not exists (select 1 from public.stats_flow_words w where w.kind = k.kind));
  end if;
  if (select count(*) from public.goods) <> (select count(distinct name) from public.goods) then
    raise exception '0214 self-assert FAIL: two goods share a name — the SOLD / BOUGHT events name the good, so the join would be ambiguous';
  end if;
  -- the subject: the first harbour (by code) that sells something, and the first good (by code) it sells
  select p.id, p.code into v_port, v_code from public.ports p
   where p.kind = 'HARBOUR' and exists (select 1 from public.port_specialties s where s.port_id = p.id)
   order by p.code limit 1;
  select g.id, g.name into v_good, v_gname from public.port_specialties s join public.goods g on g.id = s.good_id
   where s.port_id = v_port order by g.code limit 1;
  if v_port is null or v_good is null then
    raise exception '0214 self-assert FAIL: no harbour sells anything — the probe has no subject';
  end if;

  begin
    -- a current price record, so the goods rows have a mid to agree with (rolled back with the rest)
    perform public.tick_price_snapshot(now());
    -- the probe company BEFORE run 1: its founding money is in run 1's window and in run 1's purse sum
    v_p := public.new_house(c_uid, 'Casa das Contas 0214', 'PRT', 'LIS');
    v_founding := (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'FOUNDING');

    -- (b) RUN 1, and again in the same slot
    v_r1 := public.tick_stats(v_t1);
    v_r1b := public.tick_stats(v_t1);
    if (v_r1->>'world')::int <> 1 or (v_r1->>'merchants')::int <> 1
       or (v_r1->>'goods')::int <> (select count(*) from public.goods)
       or (v_r1->>'cities')::int <> (select count(*) from public.ports where kind = 'HARBOUR') then
      raise exception '0214 self-assert FAIL: run 1 wrote % — not one world row, every good, every harbour and one merchants row', v_r1;
    end if;
    select count(*) into v_offered from public.price_history h where h.slot = (select max(slot) from public.price_history where slot <= public.drift_slot_of(v_t1));
    if (v_r1->>'city_goods')::int < v_offered or v_offered = 0 then
      raise exception '0214 self-assert FAIL: run 1 wrote % city-good rows for % offered pairs', v_r1->>'city_goods', v_offered;
    end if;
    if (v_r1b->>'wrote')::int <> 0 then
      raise exception '0214 self-assert FAIL: a second run in the same slot wrote % row(s)', v_r1b->>'wrote';
    end if;
    select * into w1 from public.stats_world where slot = public.drift_slot_of(v_t1);
    if w1.players <> (select sum(p.ducats) from public.players p where not p.is_npc)
       or w1.merchants <> coalesce((select sum(p.ducats) from public.players p where p.is_npc), 0)
       or w1.cities <> coalesce((select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR'), 0) then
      raise exception '0214 self-assert FAIL: the world row''s holders are not the authorities'' sums: players % merchants % cities %', w1.players, w1.merchants, w1.cities;
    end if;
    if (w1.period->>'FOUNDING')::bigint is null or (w1.period->>'FOUNDING')::bigint < v_founding then
      raise exception '0214 self-assert FAIL: the founding money (%) is not in run 1''s period: %', v_founding, w1.period;
    end if;
    select * into g1 from public.stats_good where good_id = v_good and slot = w1.slot;
    select avg(h.mid), count(*) into v_mid, v_n from public.price_history h
     where h.good_id = v_good and h.slot = (select max(slot) from public.price_history where slot <= w1.slot);
    if g1.markets <> v_n or g1.mid is null or abs(g1.mid - v_mid) > 0.0001 then
      raise exception '0214 self-assert FAIL: the good row (mid %, % markets) is not the record''s mean (% over %)', g1.mid, g1.markets, v_mid, v_n;
    end if;
    select * into c1 from public.stats_city where port_id = v_port and slot = w1.slot;
    if c1.purse <> public.treasury_balance(v_port) then
      raise exception '0214 self-assert FAIL: the city row''s purse % is not treasury_balance %', c1.purse, public.treasury_balance(v_port);
    end if;

    -- (c) THE POSITIVE CONTROLS: one sale at the subject city, planted at now()+2 s so it falls in run 2's
    --     window and nothing the world did before this transaction does
    insert into public.events (id, player_id, kind, payload, created_at)
    values (gen_random_uuid(), v_p, 'SOLD',
            jsonb_build_object('good', v_gname, 'qty', 50, 'total', 1234, 'profit', 100, 'fleet', 'Probe 0214', 'tax', 100),
            now() + interval '2 seconds')
    returning id into v_ev;
    insert into public.treasury_flows (port_id, kind, ducats, player_id, ref_event, created_at) values
      (v_port, 'SEED',          5000, null, null, now() + interval '2 seconds'),
      (v_port, 'IMPORT_DEMAND',  777, null, null, now() + interval '2 seconds'),
      (v_port, 'SELL',         -1234, v_p,  v_ev, now() + interval '2 seconds'),
      (v_port, 'TAX',            100, v_p,  v_ev, now() + interval '2 seconds'),
      -- 0213's insurance: a 300 🪙 premium paid to the city — read from the flow like every other kind
      (v_port, 'INSURANCE',      300, v_p,  v_ev, now() + interval '2 seconds');
    perform public.credit(v_p, 'SELL', 1234, v_ev);
    perform public.credit(v_p, 'TAX', -100, v_ev);
    perform public.credit(v_p, 'INSURANCE', -300, v_ev);

    v_r2 := public.tick_stats(v_t2);
    select * into w2 from public.stats_world where slot = public.drift_slot_of(v_t2);
    if w2.slot is null or (v_r2->>'world')::int <> 1 then
      raise exception '0214 self-assert FAIL: run 2 wrote no world row: %', v_r2;
    end if;
    if w2.minted <> 5777 or w2.removed <> 0 or w2.moved <> 1634 or w2.sold <> 1234 or w2.bought <> 0 or w2.units <> 50 or w2.trades <> 1 then
      raise exception '0214 self-assert FAIL: run 2''s period is minted % removed % moved % sold % bought % units % trades % (expected 5777 / 0 / 1634 / 1234 / 0 / 50 / 1): %',
        w2.minted, w2.removed, w2.moved, w2.sold, w2.bought, w2.units, w2.trades, w2.period;
    end if;
    if (w2.period->>'SEED')::bigint <> 5000 or (w2.period->>'IMPORT_DEMAND')::bigint <> 777 or (w2.period->>'SELL')::bigint <> -1234 or (w2.period->>'TAX')::bigint <> 100
       or (w2.period->>'INSURANCE')::bigint <> 300 then
      raise exception '0214 self-assert FAIL: the period''s kinds are not the planted flows: %', w2.period;
    end if;
    if w2.players - w1.players <> 834 then
      raise exception '0214 self-assert FAIL: the players'' money moved by %, the probe''s purse by 834', w2.players - w1.players;
    end if;
    if w2.cities - w1.cities <> 4943 then
      raise exception '0214 self-assert FAIL: the cities'' money moved by %, the planted flows net 4943', w2.cities - w1.cities;
    end if;
    select * into c2 from public.stats_city where port_id = v_port and slot = w2.slot;
    if c2.income <> 6177 or c2.spending <> 1234 or c2.taxes <> 100 or c2.sold <> 50 or c2.bought <> 0
       or (c2.flows->>'SELL')::bigint <> -1234 or (c2.flows->>'INSURANCE')::bigint <> 300 or c2.purse - c1.purse <> 4943 then
      raise exception '0214 self-assert FAIL: the city row is income % spending % taxes % sold % bought % flows % purse Δ %',
        c2.income, c2.spending, c2.taxes, c2.sold, c2.bought, c2.flows, c2.purse - c1.purse;
    end if;
    select * into g2 from public.stats_good where good_id = v_good and slot = w2.slot;
    if g2.sold <> 50 or g2.sold_ducats <> 1234 or g2.bought <> 0 then
      raise exception '0214 self-assert FAIL: the good row has sold % for % ducats, bought %', g2.sold, g2.sold_ducats, g2.bought;
    end if;
    if not exists (select 1 from public.stats_city_good x where x.port_id = v_port and x.good_id = v_good and x.slot = w2.slot
                    and x.sold = 50 and x.sold_ducats = 1234 and x.mid is not null) then
      raise exception '0214 self-assert FAIL: the city-good row does not carry the 50 units sold at a price';
    end if;
    v_t1ms := (v_r1->>'ms')::numeric; v_t2ms := (v_r2->>'ms')::numeric;

    -- (d) THE GATE, as the probe company
    perform cmd.assume_identity(c_uid);
    v_v := world.stats_city(v_port);
    if (v_v->>'tier')::int <> 0 or (v_v ? 'overview') or (v_v ? 'detail') or (v_v->>'paid')::bigint <> 0
       or (v_v->>'need')::bigint <> public.wc_num('stats_city_tier1')::bigint then
      raise exception '0214 self-assert FAIL: with nothing invested the city is not locked: %', v_v;
    end if;
    select x into v_row from jsonb_array_elements(world.stats_cities()->'cities') x where x->>'code' = v_code;
    if v_row is null or (v_row->>'tier')::int <> 0 or (v_row ? 'purse') or (v_row ? 'income_1d') then
      raise exception '0214 self-assert FAIL: the locked city''s list row carries figures: %', v_row;
    end if;
    if (select count(*) from jsonb_array_elements(world.stats_cities()->'cities') x where x ? 'purse') <> 0 then
      raise exception '0214 self-assert FAIL: a company with no stake anywhere was served a city''s purse';
    end if;
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day)
    values (v_port, 'market', v_p, 1, public.wc_num('stats_city_tier1')::bigint, 0, world.game_day());
    v_v := world.stats_city(v_port);
    if (v_v->>'tier')::int <> 1 or not (v_v ? 'overview') or (v_v ? 'detail')
       or (v_v->'overview'->>'sold_1d')::bigint <> 50 or (v_v->'overview'->>'taxes_1d')::bigint <> 100
       or not exists (select 1 from jsonb_array_elements(v_v->'overview'->'flows_1d') f where f->>'kind' = 'SELL' and (f->>'ducats')::bigint = -1234)
       or not exists (select 1 from jsonb_array_elements(v_v->'overview'->'top_sold') f where f->>'name' = v_gname and (f->>'units')::bigint = 50)
       or (v_v->>'need')::bigint <> public.wc_num('stats_city_tier2')::bigint - public.wc_num('stats_city_tier1')::bigint then
      raise exception '0214 self-assert FAIL: at tier 1 the overview is wrong or the detail leaked: %', v_v;
    end if;
    select x into v_row from jsonb_array_elements(world.stats_cities()->'cities') x where x->>'code' = v_code;
    if (v_row->>'tier')::int <> 1 or (v_row->>'purse')::bigint <> c2.purse or (v_row->>'taxes_1d')::bigint <> 100 then
      raise exception '0214 self-assert FAIL: the tier-1 list row is wrong: %', v_row;
    end if;
    update public.city_shares set paid = public.wc_num('stats_city_tier2')::bigint where port_id = v_port and player_id = v_p;
    v_v := world.stats_city(v_port);
    if (v_v->>'tier')::int <> 2 or not (v_v ? 'overview') or not (v_v ? 'detail') or (v_v->>'need') is not null
       or not exists (select 1 from jsonb_array_elements(v_v->'detail'->'goods') g where g->>'name' = v_gname and (g->>'sold_1d')::bigint = 50 and (g->>'mid') is not null)
       or jsonb_array_length(v_v->'detail'->'goods') < (select count(*) from public.port_specialties s where s.port_id = v_port) then
      raise exception '0214 self-assert FAIL: at tier 2 the detail is wrong: %', left(v_v::text, 600);
    end if;
    -- the public reads
    v_v := world.stats_overview(24);
    if jsonb_array_length(v_v->'series') <> 2 or (v_v->'period'->>'minted')::bigint <> 5777 or (v_v->'holders'->>'players')::bigint <> w2.players
       or not exists (select 1 from jsonb_array_elements(v_v->'period'->'flows') f where f->>'kind' = 'IMPORT_DEMAND' and f->>'side' = 'minted' and (f->>'ducats')::bigint = 777)
       or not exists (select 1 from jsonb_array_elements(v_v->'period'->'flows') f where f->>'kind' = 'INSURANCE' and f->>'side' = 'moved'
                        and f->>'word' = 'Insurance premiums' and (f->>'ducats')::bigint = 300) then
      raise exception '0214 self-assert FAIL: the overview does not serve the two rows: %', left(v_v::text, 600);
    end if;
    v_v := world.stats_markets();
    if jsonb_array_length(v_v->'goods') <> (select count(*) from public.goods)
       or not exists (select 1 from jsonb_array_elements(v_v->'goods') g where g->>'name' = v_gname and (g->>'sold_1d')::bigint = 50 and (g->>'mid') is not null
                        and (g ? 'mid_1h') and jsonb_array_length(g->'spark') = 2) then
      raise exception '0214 self-assert FAIL: the markets read does not serve every good with the probe''s sale: %', left(v_v::text, 400);
    end if;
    v_v := world.stats_merchants();
    if (v_v->>'houses')::int <> (select count(*) from public.npc_houses) or jsonb_array_length(v_v->'series') <> 2 then
      raise exception '0214 self-assert FAIL: the merchants read is wrong: %', left(v_v::text, 400);
    end if;
    v_v := world.stats_me();
    if jsonb_array_length(v_v->'best_trades') <> 1 or (v_v->'best_trades'->0->>'profit')::numeric <> 100
       or (v_v->'leaderboard'->>'you') is null
       or not exists (select 1 from jsonb_array_elements(v_v->'leaderboard'->'board') b where (b->>'is_you')::boolean)
       or exists (select 1 from jsonb_array_elements(v_v->'leaderboard'->'board') b where b ? 'ducats') then
      raise exception '0214 self-assert FAIL: the me read is wrong or exposes a purse: %', left(v_v::text, 400);
    end if;
    perform cmd.assume_identity(c_nil);

    -- (e) RETENTION: rows planted on old days, each table under its own knob (noon UTC, so a day cannot straddle)
    v_old    := (date_trunc('day', v_t3 at time zone 'UTC') - make_interval(hours => public.wc_int('stats_fine_hours') + 24) + interval '12 hours') at time zone 'UTC';
    v_old_cg := (date_trunc('day', v_t3 at time zone 'UTC') - make_interval(hours => public.wc_int('stats_city_good_fine_hours') + 48) + interval '12 hours') at time zone 'UTC';
    v_old_g  := (date_trunc('day', v_t3 at time zone 'UTC') - make_interval(hours => public.wc_int('stats_city_good_fine_hours') + 12) + interval '12 hours') at time zone 'UTC';
    insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside, minted, removed, moved, sold, bought, units, trades, period, recent)
    values (public.drift_slot_of(v_old), v_old, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '{}', '{}'),
           (public.drift_slot_of(v_old) + 1, v_old + make_interval(secs => v_secs::double precision), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '{}', '{}');
    insert into public.stats_city_good (port_id, good_id, slot, at, mid, stock, stock_target, sold, bought, sold_ducats, bought_ducats)
    values (v_port, v_good, public.drift_slot_of(v_old_cg), v_old_cg, 1, 1, 1, 0, 0, 0, 0),
           (v_port, v_good, public.drift_slot_of(v_old_cg) + 1, v_old_cg + make_interval(secs => v_secs::double precision), 1, 1, 1, 0, 0, 0, 0);
    insert into public.stats_good (good_id, slot, at, mid, markets, stock, stock_target, sold, bought, sold_ducats, bought_ducats)
    values (v_good, public.drift_slot_of(v_old_g), v_old_g, 1, 1, 1, 1, 0, 0, 0, 0),
           (v_good, public.drift_slot_of(v_old_g) + 1, v_old_g + make_interval(secs => v_secs::double precision), 1, 1, 1, 1, 0, 0, 0, 0);
    v_r3 := public.tick_stats(v_t3);
    select count(*), max(slot) - public.drift_slot_of(v_old) into v_n, v_n2 from public.stats_world where (at at time zone 'UTC')::date = (v_old at time zone 'UTC')::date;
    if v_n <> 1 or v_n2 <> 1 then
      raise exception '0214 self-assert FAIL: compaction left % world row(s) on the old day (the kept one is slot+%), not one, the day''s last', v_n, v_n2;
    end if;
    if (select count(*) from public.stats_city_good where port_id = v_port and good_id = v_good and (at at time zone 'UTC')::date = (v_old_cg at time zone 'UTC')::date) <> 1 then
      raise exception '0214 self-assert FAIL: compaction did not keep exactly one city-good row on its old day';
    end if;
    if (select count(*) from public.stats_good where good_id = v_good and (at at time zone 'UTC')::date = (v_old_g at time zone 'UTC')::date) <> 2 then
      raise exception '0214 self-assert FAIL: compaction touched good rows inside the %-hour fine window', public.wc_int('stats_fine_hours');
    end if;
    if (v_r3->>'compacted')::int <> 2 then
      raise exception '0214 self-assert FAIL: run 3 reports % compacted row(s), not 2', v_r3->>'compacted';
    end if;

    raise exception using errcode = 'ZX214', message = jsonb_build_object('ms1', v_t1ms, 'ms2', v_t2ms, 'ms3', (v_r3->>'ms')::numeric,
      'r1', v_r1, 'offered', v_offered, 'port', v_code, 'good', v_gname)::text;
  exception when sqlstate 'ZX214' then
    v_out := sqlerrm::jsonb;
  end;

  -- (f) nothing of the probe survives; the registry, the grants and the walls
  if exists (select 1 from public.players where id = v_p) or exists (select 1 from public.stats_world)
     or exists (select 1 from public.stats_good) or exists (select 1 from public.stats_city)
     or exists (select 1 from public.stats_city_good) or exists (select 1 from public.stats_merchants) then
    raise exception '0214 self-assert FAIL: the probe survived its rollback';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0214) + 6
     or not has_function_privilege('authenticated', 'world.stats_overview(integer)', 'execute')
     or not has_function_privilege('authenticated', 'world.stats_markets()', 'execute')
     or not has_function_privilege('authenticated', 'world.stats_cities()', 'execute')
     or not has_function_privilege('authenticated', 'world.stats_city(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'world.stats_merchants()', 'execute')
     or not has_function_privilege('authenticated', 'world.stats_me()', 'execute')
     or has_function_privilege('anon', 'world.stats_overview(integer)', 'execute')
     or has_function_privilege('anon', 'world.stats_city(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.tick_stats(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.stats_city_tier(uuid, uuid)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0214 self-assert FAIL: the registry, the grant wall or the read wall moved';
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and not exists (select 1 from public.clock_jobs() j where j.jobname = 'byeharu-voyage:stats' and not j.active) then
    raise exception '0214 self-assert FAIL: byeharu-voyage:stats is not defined inactive';
  end if;
  raise notice '0214 self-assert ok: THE WORLD KEEPS ITS FIGURES. tick_stats wrote one world row, % goods, % harbours, % city-good rows (% offered pairs) and one merchants row in % ms, and 0 rows when run again in the same slot; the holders equal the authorities'' sums. Positive controls at % (%): a planted sale of 50 units for 1,234 🪙 with 100 tax, 5,000 SEED, 777 IMPORT_DEMAND and a 300 🪙 INSURANCE premium (0213) gave the next row minted 5,777 / moved 1,634 / sold 1,234 / units 50 / trades 1, the players'' money +834, the cities'' +4,943, the city row income 6,177 / spending 1,234 / taxes 100 / sold 50, the good and city-good rows 50 — in % ms. THE GATE: nothing invested → locked, no figures served anywhere; % 🪙 → overview only (sold 50, taxes 100, SELL −1,234, the good on top); % 🪙 → the detail with the good''s 50 units. Compaction kept one row per old day under each table''s own knob (run 3: % ms). Registry +6 (authenticated, not anon); walls 0; the job defined inactive.',
    v_out->'r1'->>'goods', v_out->'r1'->>'cities', v_out->'r1'->>'city_goods', v_out->>'offered', v_out->>'ms1',
    v_out->>'port', v_out->>'good', v_out->>'ms2',
    public.wc_num('stats_city_tier1')::bigint, public.wc_num('stats_city_tier2')::bigint, v_out->>'ms3';
end $$;
