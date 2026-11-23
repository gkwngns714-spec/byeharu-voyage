-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0483 - COURIER CONTRACTS BETWEEN COMPANIES AND HOUSES  (dark: the owner's switch contracts_enabled, false; lit, a merchant house, a city
--        or a company posts "carry these goods from A to B by a time, with collateral and a reward"; a company takes one from HQ in one
--        press, sails it on a stored course, and is paid on delivery or loses her collateral)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/roadmap-2026-11-23.md slice 14 ("Contracts between companies and houses", EVE's courier contracts);
--   docs/design/hq-command-2026-11-23.md (every activity in HQ); docs/dev-log/2026-11-23-contracts.md.
--
-- WHY: the owner, 2026-11-23: "i want this game to be strategical game, where all the work(activities) are done in HQ - words with
--   graphics. choosing best options available, finding best options." Slice 14: "a merchant house, a city or a company posts a courier
--   contract: carry these goods from A to B by a time, with collateral. The carrier risks the collateral (pirates, delay); the poster
--   risks the goods. ... The 'Place a request' verb that nobody used becomes 'Post a contract'."
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure is a knob):
--   THE TABLE public.courier_contracts: one row a contract (poster: house | city | company; from, to, the good and its units; the miles
--     A->B; the goods' value at A; the reward; the collateral; the delivery window; when it lapses untaken), and its life:
--     open -> taken -> delivered | failed, or open -> lapsed | cancelled.
--   ONE WRITER EACH:
--     public.courier_post     posts one (the reward escrowed: a house's or company's purse, CONTRACT_ESCROW; a city's treasury, lit
--                              purses only; a company's goods taken out of her Storage at A).
--     public.courier_draw     a merchant house (or, the city purses lit, a city: contracts_city_share of draws) posts one on its own,
--                              drawn from (the minute, the draw's number): the house (no live contract of its own; its home harbour is
--                              A), a good A offers, B a harbour contracts_nm_min..max sailed miles away that takes the good and does
--                              not make it, the lot (contracts_tons_min..max tons, at most contracts_value_max at A's mid), the reward
--                              (the value x contracts_reward_pct_min..max + contracts_reward_per_100nm a 100 miles), the collateral
--                              (the lot at the dearer mid of A and B x contracts_collateral_mult), the window (the trip at
--                              contracts_speed_kn x contracts_window_mult, at least contracts_window_min_s). Never raises: 0 or 1.
--     public.courier_take_for a company takes one with a fleet lying idle in harbour: the collateral leaves her purse
--                              (CONTRACT_COLLATERAL); at A the goods go aboard now, elsewhere they wait in her Storage at A; then ONE plan
--                              through cmd.issue_lines with stored courses (public.fleet_job_sails, as public.sale_lines): [SAIL A,
--                              TAKE <good> <units>,] SAIL B. All of it or none.
--     public.courier_settle   THE ONE SETTLER: deliver (her fleet lies at B with the units aboard, arrived by the deadline: the units
--                              leave her hold, the reward and her collateral are paid to her: CONTRACT_REWARD, CONTRACT_RETURN; a
--                              company poster's goods land in her Storage at B), fail (the deadline passed, or she gives up: the
--                              collateral goes to the poster, CONTRACT_FORFEIT, and the reward back, CONTRACT_RETURN; the units still
--                              hers to give, from her hold then her Storage at A, are returned, a company's to her Storage at A; the rest
--                              are lost), lapse (untaken past expires_at: the reward and a company's goods back), cancel (her own, open).
--   ONE READING whether a taken contract delivers now, is late, or waits: public.courier_state.
--   THE TICK public.tick_courier_contracts() (pg_cron byeharu-voyage:contracts, every 2 minutes; NOT on the arrivals beat): dark one knob
--     read; lit, settled rows older than contracts_keep_days go (200 at most), the lapsed are refunded, the taken are delivered or failed
--     (SKIP LOCKED: a contract or fleet another session holds waits for the next run), then houses post while the open house and city
--     contracts number under ceil(houses / contracts_houses_per) (845 houses / 20 = 43), contracts_posts_per_tick (3) a run at most.
--   THE BOARD (public.hq_board_for, by ONE hunk: v_moves || public.courier_moves): lit, cards of kind `contract`, band 1, ranked with trade
--     runs and requests by coin an hour: TAKE, for each of her idle fleets, the open contracts not hers whose trip (to A, then A to B, at
--     her fleet's speed) fits the window, whose collateral her purse covers and whose lot her hold (and, away from A, her shed at A) takes;
--     score = reward x 3600 / the trip's seconds; risk = public.hq_course_risk over her port, A and B; act cmd.take_contract. DELIVER, her
--     taken contracts that deliver now: score = reward x 3600 / hq_board_request_floor_s; act cmd.deliver_contract. At most
--     contracts_board_cards (6) take cards.
--   THE DOORS (registered, signed-in companies only, the {ok:false} envelope; dark E_NOT_IN_USE): cmd.take_contract(fleet, contract,
--     version), cmd.deliver_contract(contract), cmd.fail_contract(contract) (the carrier gives up), cmd.post_contract(from, to, good, qty,
--     reward, collateral, hours) ("Post a contract", the Requests face's verb), cmd.cancel_contract(contract) (her own, untaken).
--   THE READ world.courier_contracts() (STABLE, registered): dark {"on": false}; lit, signed out or a merchant {"on": true, "company":
--     false}; lit her company: {open, posted: [...], carried: [...], limits}.
--   THE MONEY LOG: the five kinds are money moved (public.stats_flow_words, side 'moved').
-- ONE AUTHORITY EACH: the contract, public.courier_contracts; its post, public.courier_post; its settle, public.courier_settle; whether it
--   delivers, public.courier_state; its lines, public.fleet_job_sails (the stored course); its cards, public.courier_moves. Money moves by
--   public.credit and public.treasury_post alone; goods by public.fleet_load / fleet_unload / storage_put / storage_take alone.
-- NOT CHANGED: any command, world.best_sales, the beat, the requests (market_requests, trade_contracts), every other card.
-- ROWS. Dark: none. Lit: ~45 open contracts (43 house and city + each company's own); a post writes its row and one ledger row (or one
--   treasury row); a take writes the row, one ledger row, its 1-3 orders and what they do; a settle writes the row and 1-2 ledger rows.
--   Kept contracts_keep_days (3) after settling: about 45 x (24 / 6 h) x 3 = ~550 rows at the most.
-- COST. Dark: one knob read a run. Lit, a run: one count of the houses (845 rows), one index read of the live contracts, at most 3 posts
--   (each one reach_from and two prices: a few ms). A board read adds one reach_from a fleet (~254 rows) and the live contracts (~45).
--   -- budget: one cron job every 2 minutes (byeharu-voyage:contracts); dark 0 rows a run; lit at most 3 posts, 50 lapses and 100 settles a run, about 10 rows a run on a normal day
--   -- retention: public.courier_contracts keeps a settled row contracts_keep_days (3) days, trimmed by public.tick_courier_contracts
-- LOCKS: CREATE TABLE x1 (new), CREATE FUNCTION x16, CREATE OR REPLACE x2 by hunks (public.hq_board_for, public.client_rpc_entry_points),
--   five rows into public.stats_flow_words, the knobs, one cron job (where pg_cron is). TIME: a few seconds. BUDGET: statement_timeout
--   60 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, contracts_enabled false (no post, no take; the doors refuse, the read is {"on": false}, the board
--   shows no contract card; contracts already taken stand until the switch is lit again: their collateral and goods wait). Full: a new
--   migration settling every live contract (lapse or fail), unscheduling byeharu-voyage:contracts, reversing the two hunks (OLD text below
--   verbatim), dropping the functions and the table, deleting the knobs and the five money-log words.
-- SELF-ASSERT: the hunks once each and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; the knobs; the reads STABLE; the six doors registered for authenticated alone; every core and the tick server only; the
--   table no client's. THE PROBE (rolled back; deterministic: no time-budgeted read is asked (world.best_sales never), and nothing is
--   compared twice; one transaction, one now(); every clock is set from 00:00 UTC of the day it runs, so the scene starts before 23:30 UTC
--   and never straddles a UTC midnight): dark the doors refuse, the read is {"on": false} and the tick writes nothing; lit a company posts
--   from Lisbon's Storage (the reward escrowed, the goods out of her shed), another takes it at Lisbon (the collateral out, the goods aboard,
--   ONE plan SAIL <B> with a stored course, and she departs), her board names it; she arrives and the tick delivers it (her hold empties,
--   the poster's shed at B fills, the reward and the collateral are hers, each ledger row to the ducat); a house posts one, she takes it
--   and runs late: the tick fails it (the house takes the collateral and its reward back, the goods are returned out of her hold); a
--   carrier who gives up with the goods gone loses them (lost); an untaken one lapses (the reward back); the tick posts as houses at most
--   to its cap, each post escrowed to the ducat; signed out the read is {"on": true, "company": false}. Proof 186 plays the rest.
-- VERSION: 0483 = 0482 + 1 (prod head 0482; this file's hunks are anchored on 0480's and 0481's own lines).
-- news: none (dark: nothing changes for a player until the owner lights contracts_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- ── 0. GUARD, AND THE PRE-IMAGE (every function this file does not hunk or create: it must not move) ──
do $g$
begin
  if exists (select 1 from public.world_config where key = 'contracts_enabled') or to_regclass('public.courier_contracts') is not null then
    raise exception '0483 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.fleet_job_sails(uuid,uuid,text[])') is null or to_regprocedure('public.sale_lines(uuid,uuid,jsonb,jsonb)') is null
     or to_regprocedure('public.hq_board_for(uuid)') is null or to_regprocedure('public.hq_course_risk(text[])') is null
     or to_regclass('public.fleet_jobs') is null or to_regprocedure('cmd.issue_lines(uuid,jsonb,integer)') is null
     or to_regprocedure('public.storage_put(uuid,uuid,uuid,numeric,numeric)') is null or to_regprocedure('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)') is null then
    raise exception '0483 refuses: 0482, 0481, 0480, 0175 or 0122 is not in this world';
  end if;
  create temp table pre_0483 on commit drop as
    select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text)) as fns,
           (select md5(string_agg(q.oid::regprocedure::text || ':' || coalesce(q.proacl::text, '') || ':' || q.provolatile::text || q.prosecdef::text || coalesce(q.proconfig::text, '') || ':' || q.proowner::text, ',' order by q.oid::regprocedure::text))
              from pg_proc q where q.oid in ('public.hq_board_for(uuid)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure)) as meta
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
       and p.oid not in ('public.hq_board_for(uuid)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure);
end
$g$;

-- ── 1. THE KNOBS ──
insert into public.world_config (key, value, description) values
  ('contracts_enabled', 'false'::jsonb,
   '0483: THE SWITCH (the owner''s). true: merchant houses (and, the city purses lit, cities) post courier contracts on their own, a company posts one from her Storage, takes one from HQ in one press, and is paid on delivery or loses her collateral (public.tick_courier_contracts every 2 minutes). false: the doors refuse E_NOT_IN_USE, the read is {"on": false}, the board shows no contract and the tick returns at once.'),
  ('contracts_houses_per', to_jsonb(20), '0483: one open house-or-city contract for each this many merchant houses (845 houses: 43 open at the most).'),
  ('contracts_posts_per_tick', to_jsonb(3), '0483: the most contracts houses and cities post in one run of public.tick_courier_contracts.'),
  ('contracts_city_share', to_jsonb(0.25), '0483: the share of draws a city posts instead of a house (the city purses lit only; dark every draw is a house''s).'),
  ('contracts_tons_min', to_jsonb(20), '0483: the smallest lot a house or city posts, in tons.'),
  ('contracts_tons_max', to_jsonb(120), '0483: the largest lot a house or city posts, in tons.'),
  ('contracts_value_max', to_jsonb(30000), '0483: the most a house or city lot is worth at A''s mid price (the units are cut to it).'),
  ('contracts_nm_min', to_jsonb(150), '0483: the nearest harbour B a house or city contract goes to, in sailed miles from A.'),
  ('contracts_nm_max', to_jsonb(1500), '0483: the farthest harbour B a house or city contract goes to, in sailed miles from A.'),
  ('contracts_reward_pct_min', to_jsonb(0.06), '0483: the least share of the lot''s value a house or city pays as the reward (before the miles).'),
  ('contracts_reward_pct_max', to_jsonb(0.12), '0483: the most share of the lot''s value a house or city pays as the reward (before the miles).'),
  ('contracts_reward_per_100nm', to_jsonb(0.01), '0483: what each 100 sailed miles A to B adds to the reward''s share of the value.'),
  ('contracts_collateral_mult', to_jsonb(1.25), '0483: the collateral of a house or city contract: the lot at the dearer mid of A and B, times this.'),
  ('contracts_speed_kn', to_jsonb(8), '0483: the speed (knots) a house or city prices the trip A to B at, for the delivery window.'),
  ('contracts_window_mult', to_jsonb(3), '0483: the delivery window of a house or city contract: the trip at contracts_speed_kn, times this.'),
  ('contracts_window_min_s', to_jsonb(1800), '0483: the shortest delivery window of a house or city contract, in real seconds.'),
  ('contracts_open_hours', to_jsonb(6), '0483: an untaken contract lapses this many real hours after it is posted (the reward, and a company''s goods, go back).'),
  ('contracts_hours_min', to_jsonb(1), '0483: the shortest delivery window a company may give her own contract, in real hours.'),
  ('contracts_hours_max', to_jsonb(48), '0483: the longest delivery window a company may give her own contract, in real hours.'),
  ('contracts_post_max', to_jsonb(3), '0483: the most untaken-or-taken contracts one company may have posted at once.'),
  ('contracts_carry_max', to_jsonb(2), '0483: the most contracts one company may carry at once.'),
  ('contracts_board_cards', to_jsonb(6), '0483: the most contracts to take that HQ''s board shows (the best by coin an hour).'),
  ('contracts_keep_days', to_jsonb(3), '0483: a settled contract (delivered, failed, lapsed, cancelled) is kept this many days, then deleted by the tick.');

-- ── 2. THE TABLE ──
-- retention: contracts_keep_days (3): a settled row is deleted by public.tick_courier_contracts that many days after it settled; the live
--   ones are bounded by ceil(houses / contracts_houses_per) + contracts_post_max a company
create table public.courier_contracts (
  id          uuid primary key default gen_random_uuid(),
  poster_kind text not null check (poster_kind in ('house', 'city', 'company')),
  poster_id   uuid references public.players(id) on delete set null,
  from_port   uuid not null references public.ports(id),
  to_port     uuid not null references public.ports(id),
  good_id     uuid not null references public.goods(id),
  qty         numeric not null check (qty > 0),
  nm          numeric not null check (nm >= 0),
  value       bigint not null check (value >= 0),
  reward      bigint not null check (reward > 0),
  collateral  bigint not null check (collateral >= 0),
  window_s    integer not null check (window_s > 0),
  posted_at   timestamptz not null,
  expires_at  timestamptz not null,
  status      text not null default 'open' check (status in ('open', 'taken', 'delivered', 'failed', 'lapsed', 'cancelled')),
  carrier_id  uuid references public.players(id) on delete set null,
  fleet_id    uuid references public.fleets(id) on delete set null,
  taken_at    timestamptz,
  deliver_by  timestamptz,
  settled_at  timestamptz,
  outcome     jsonb,
  check (from_port <> to_port),
  check ((poster_kind = 'city') = (poster_id is null) or poster_kind <> 'city')
);
create index courier_contracts_live on public.courier_contracts (status, expires_at) where status in ('open', 'taken');
create index courier_contracts_carrier on public.courier_contracts (carrier_id) where carrier_id is not null;
create index courier_contracts_poster on public.courier_contracts (poster_id) where poster_id is not null;
create index courier_contracts_settled on public.courier_contracts (settled_at) where settled_at is not null;
alter table public.courier_contracts enable row level security;
revoke all on table public.courier_contracts from public, anon, authenticated;
comment on table public.courier_contracts is
  '0483: courier contracts (EVE''s): carry these goods from A to B within the window, for the reward, against the collateral. Written by public.courier_post, public.courier_take_for and public.courier_settle alone. Server only.';

-- ── 3. THE MONEY LOG'S WORDS (money moved between purses, never made) ──
insert into public.stats_flow_words (kind, side, word, ord) values
  ('CONTRACT_ESCROW', 'moved', 'Contract rewards held', 63),
  ('CONTRACT_COLLATERAL', 'moved', 'Contract collateral held', 64),
  ('CONTRACT_REWARD', 'moved', 'Contract rewards paid', 65),
  ('CONTRACT_RETURN', 'moved', 'Contract money returned', 66),
  ('CONTRACT_FORFEIT', 'moved', 'Contract collateral forfeited', 67);

-- ── 4. THE RULES ──
create function public.courier_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0483: THE SWITCH, read once: world_config contracts_enabled.
  select public.wc('contracts_enabled') = 'true'::jsonb
$body$;

create function public.courier_post(p_kind text, p_poster uuid, p_from uuid, p_to uuid, p_good uuid, p_qty numeric, p_reward bigint,
                                     p_collateral bigint, p_window_s integer, p_now timestamptz default now())
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0483: THE ONE WRITER OF A POST. The miles A to B (voyage.reach_from; none: E_NO_COURSE), the lot's value at A's mid, the reward escrowed
-- (a house's or a company's purse, CONTRACT_ESCROW; a city's treasury, the purses lit, or E_NOT_IN_USE), a company's goods out of her
-- Storage at A (all of them, or E_NONE_STORED). Raises the refusal; the row's id. Server only.
declare
  g       public.goods%rowtype;
  v_nm    numeric;
  v_mid   numeric;
  v_ev    uuid;
  v_id    uuid := gen_random_uuid();
  v_took  numeric;
begin
  select * into g from public.goods where id = p_good;
  if g.id is null then
    perform cmd.refuse('E_NO_SUCH_GOOD', 'nothing is called that');
  end if;
  if p_kind not in ('house', 'city', 'company') or (p_kind = 'city') <> (p_poster is null)
     or coalesce(p_qty, 0) <= 0 or coalesce(p_reward, 0) <= 0 or coalesce(p_collateral, -1) < 0 or coalesce(p_window_s, 0) <= 0 then
    perform cmd.refuse('E_BAD_ORDER', 'a contract names its goods, a reward, a collateral and a time');
  end if;
  if p_from = p_to or (select count(*) from public.ports p where p.id in (p_from, p_to) and p.kind = 'HARBOUR') <> 2 then
    perform cmd.refuse('E_BAD_ORDER', 'a contract runs between two harbours');
  end if;
  select r.nm into v_nm from voyage.reach_from(p_from) r where r.port_id = p_to;
  if v_nm is null then
    perform cmd.refuse('E_NO_COURSE', format('no water joins %s and %s', (select p.name from public.ports p where p.id = p_from),
                                                                      (select p.name from public.ports p where p.id = p_to)));
  end if;
  select q.mid into v_mid from world.price(p_from, p_good) q;
  v_ev := public.emit_event(p_poster, 'CONTRACT_POSTED', jsonb_build_object('contract', v_id, 'good', g.code, 'qty', p_qty,
            'from', (select p.code from public.ports p where p.id = p_from), 'to', (select p.code from public.ports p where p.id = p_to),
            'reward', p_reward, 'collateral', p_collateral, 'kind', p_kind));
  if p_kind = 'city' then
    if not public.city_treasury_on() then
      perform cmd.refuse('E_NOT_IN_USE', 'a city posts contracts only from a lit purse');
    end if;
    perform public.treasury_post(p_from, 'CONTRACT_ESCROW', -p_reward, null, v_ev);
  else
    perform public.credit(p_poster, 'CONTRACT_ESCROW', -p_reward, v_ev);
  end if;
  if p_kind = 'company' then
    if coalesce((select ps.qty from public.player_storage ps where ps.player_id = p_poster and ps.port_id = p_from and ps.good_id = p_good), 0) < p_qty then
      perform cmd.refuse('E_NONE_STORED', format('you keep fewer than %s %s in this city', trim_scale(p_qty), g.name));
    end if;
    v_took := public.storage_take(p_poster, p_from, p_good, p_qty);
  end if;
  insert into public.courier_contracts (id, poster_kind, poster_id, from_port, to_port, good_id, qty, nm, value, reward, collateral, window_s,
                                        posted_at, expires_at)
  values (v_id, p_kind, p_poster, p_from, p_to, p_good, p_qty, round(v_nm, 1), ceil(p_qty * coalesce(v_mid, 0))::bigint, p_reward, p_collateral,
          p_window_s, p_now, p_now + make_interval(secs => greatest(1, public.wc_num('contracts_open_hours')) * 3600));
  return v_id;
end
$body$;

create function public.courier_draw(p_key text, p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0483: A HOUSE (OR A CITY) POSTS ONE ON ITS OWN, drawn from p_key (the run's minute and the draw's number) and the game day: who (a city
-- for contracts_city_share of draws, the purses lit; else a house with no live contract, its home harbour A), the good (one A offers, with
-- bulk), B (a harbour contracts_nm_min..max sailed miles from A that trades the good, does not make it and whose culture takes it), the
-- lot, the reward, the collateral and the window (0483's header). Answers 1 posted or 0. Never raises: a refused post is 0.
declare
  c_stream constant uuid := '00000000-0483-4000-8000-00000000c0de';
  v_day   int := world.game_day(p_now);
  v_u     numeric;
  v_kind  text := 'house';
  v_who   uuid;
  v_from  uuid;
  v_good  uuid;
  v_bulk  numeric;
  v_to    uuid;
  v_nm    numeric;
  v_mida  numeric;
  v_midb  numeric;
  v_qty   numeric;
  v_val   numeric;
  v_pct   numeric;
  v_rew   bigint;
  v_col   bigint;
  v_trip  numeric;
  v_win   int;
begin
  if not public.courier_on() then
    return 0;
  end if;
  begin
    v_u := voyage.rng(c_stream, v_day, 'contract:' || p_key || ':who');
    if public.city_treasury_on() and v_u < public.wc_num('contracts_city_share') then
      v_kind := 'city';
      select p.id into v_from
        from (select p.id, row_number() over (order by p.code) - 1 as i, count(*) over () as n from public.ports p where p.kind = 'HARBOUR') p
       where p.i = least(p.n - 1, floor(voyage.rng(c_stream, v_day, 'contract:' || p_key || ':city') * p.n)::int);
    else
      select h.player_id, h.home_port_id into v_who, v_from
        from (select h.player_id, h.home_port_id, row_number() over (order by h.roster_ord) - 1 as i, count(*) over () as n
                from public.npc_houses h join public.ports p on p.id = h.home_port_id and p.kind = 'HARBOUR'
               where not exists (select 1 from public.courier_contracts c where c.poster_id = h.player_id and c.status in ('open', 'taken'))) h
       where h.i = least(h.n - 1, floor(voyage.rng(c_stream, v_day, 'contract:' || p_key || ':house') * h.n)::int);
    end if;
    if v_from is null then
      return 0;
    end if;
    -- THE GOOD: one A offers, with bulk and a market row
    select x.gid, x.bulk into v_good, v_bulk
      from (select g.id as gid, g.bulk, row_number() over (order by g.code) - 1 as i, count(*) over () as n
              from public.port_offered_goods(v_from) o join public.goods g on g.id = o.good_id
              join public.port_goods pg on pg.port_id = v_from and pg.good_id = g.id
             where g.bulk > 0) x
     where x.i = least(x.n - 1, floor(voyage.rng(c_stream, v_day, 'contract:' || p_key || ':good') * x.n)::int);
    if v_good is null then
      return 0;
    end if;
    -- B: within the miles, trades the good, does not make it, its culture takes it
    select x.pid, x.nm into v_to, v_nm
      from (select r.port_id as pid, r.nm, row_number() over (order by r.code) - 1 as i, count(*) over () as n
              from voyage.reach_from(v_from) r
              join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR'
              join public.port_goods pg on pg.port_id = r.port_id and pg.good_id = v_good
             where r.port_id <> v_from and r.nm between public.wc_num('contracts_nm_min') and public.wc_num('contracts_nm_max')
               and not exists (select 1 from public.port_specialties s where s.port_id = r.port_id and s.good_id = v_good)
               and not public.culture_refuses(p.culture, (select g.culture_mask from public.goods g where g.id = v_good))) x
     where x.i = least(x.n - 1, floor(voyage.rng(c_stream, v_day, 'contract:' || p_key || ':to') * x.n)::int);
    if v_to is null then
      return 0;
    end if;
    select q.mid into v_mida from world.price(v_from, v_good) q;
    select q.mid into v_midb from world.price(v_to, v_good) q;
    if coalesce(v_mida, 0) <= 0 or coalesce(v_midb, 0) <= 0 then
      return 0;
    end if;
    -- THE LOT, THE REWARD, THE COLLATERAL, THE WINDOW
    v_u   := voyage.rng(c_stream, v_day, 'contract:' || p_key || ':tons');
    v_qty := floor(least((public.wc_num('contracts_tons_min') + v_u * (public.wc_num('contracts_tons_max') - public.wc_num('contracts_tons_min'))) / v_bulk,
                         public.wc_num('contracts_value_max') / v_mida));
    if v_qty >= 20 then
      v_qty := floor(v_qty / 5) * 5;   -- a round lot reads as a job
    end if;
    if v_qty < 5 then
      return 0;
    end if;
    v_val := v_qty * v_mida;
    v_u   := voyage.rng(c_stream, v_day, 'contract:' || p_key || ':reward');
    v_pct := public.wc_num('contracts_reward_pct_min') + v_u * (public.wc_num('contracts_reward_pct_max') - public.wc_num('contracts_reward_pct_min'))
             + v_nm / 100 * public.wc_num('contracts_reward_per_100nm');
    v_rew := greatest(50, ceil(v_val * v_pct))::bigint;
    v_col := ceil(v_qty * greatest(v_mida, v_midb) * public.wc_num('contracts_collateral_mult'))::bigint;
    v_trip := v_nm * 3600 / (greatest(public.wc_num('contracts_speed_kn'), 1) * greatest(public.wc_num('time_compression'), 1));
    v_win := greatest(public.wc_int('contracts_window_min_s'), ceil(v_trip * public.wc_num('contracts_window_mult'))::int);
    perform public.courier_post(v_kind, v_who, v_from, v_to, v_good, v_qty, v_rew, v_col, v_win, p_now);
    return 1;
  exception when others then
    return 0;
  end;
end
$body$;

create function public.courier_state(p_contract uuid, p_now timestamptz default now())
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0483: THE ONE READING of a taken contract now: 'deliver' (her fleet lies DOCKED at B with the units aboard, and she came in by the
  -- deadline: now, or a voyage of hers that ended at B between the take and the deadline), 'late' (it does not deliver and the deadline
  -- has passed), 'wait'. Null for a contract not taken.
  select case
           when f.id is not null and f.status = 'DOCKED' and f.port_id = c.to_port
                and public.fleet_cargo_qty(f.id, g.code) >= c.qty
                and (p_now <= c.deliver_by
                     or exists (select 1 from public.voyages v where v.fleet_id = f.id and v.dest_port_id = c.to_port and v.status <> 'SAILING'
                                                                 and v.eta >= c.taken_at and v.eta <= c.deliver_by)) then 'deliver'
           when p_now > c.deliver_by then 'late'
           else 'wait' end
    from public.courier_contracts c
    join public.goods g on g.id = c.good_id
    left join public.fleets f on f.id = c.fleet_id and f.player_id = c.carrier_id
   where c.id = p_contract and c.status = 'taken'
$body$;

create function public.courier_settle(p_contract uuid, p_how text, p_why text default null, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0483: THE ONE SETTLER (0483's header): deliver | fail | lapse | cancel. Locks the contract (and, to move goods, the carrier's fleet,
-- SKIP LOCKED: E_BUSY when another session holds her). Raises the refusal; the settled row's outcome. Server only.
declare
  c       public.courier_contracts%rowtype;
  g       public.goods%rowtype;
  v_ev    uuid;
  v_back  numeric := 0;
  v_got   numeric;
  v_lost  numeric := 0;
  v_out   jsonb;
  v_state text;
begin
  select * into c from public.courier_contracts x where x.id = p_contract for update;
  if c.id is null then
    perform cmd.refuse('E_NO_CONTRACT', 'there is no such contract');
  end if;
  select * into g from public.goods where id = c.good_id;

  if p_how in ('lapse', 'cancel') then
    if c.status <> 'open' then
      perform cmd.refuse('E_TAKEN', 'that contract is no longer open');
    end if;
    v_ev := public.emit_event(c.poster_id, case when p_how = 'lapse' then 'CONTRACT_LAPSED' else 'CONTRACT_CANCELLED' end,
                              jsonb_build_object('contract', c.id, 'good', g.code, 'qty', c.qty, 'reward', c.reward));
    if c.poster_kind = 'city' then
      perform public.treasury_post(c.from_port, 'CONTRACT_RETURN', c.reward, null, v_ev, true);
    elsif c.poster_id is not null then
      perform public.credit(c.poster_id, 'CONTRACT_RETURN', c.reward, v_ev);
    end if;
    if c.poster_kind = 'company' and c.poster_id is not null then
      begin
        perform public.storage_put(c.poster_id, c.from_port, c.good_id, c.qty, null);
        v_back := c.qty;
      exception when others then
        v_lost := c.qty;   -- her shed at A is full: the goods are lost
      end;
    end if;
    v_out := jsonb_build_object('how', p_how, 'returned', v_back, 'lost', v_lost, 'why', p_why);
    update public.courier_contracts set status = case when p_how = 'lapse' then 'lapsed' else 'cancelled' end, settled_at = p_now, outcome = v_out
     where id = c.id;
    return v_out;
  end if;

  if c.status <> 'taken' then
    perform cmd.refuse('E_NOT_TAKEN', 'that contract is not being carried');
  end if;
  if c.fleet_id is not null then
    perform 1 from public.fleets f where f.id = c.fleet_id for update skip locked;
    if not found then
      perform cmd.refuse('E_BUSY', 'the fleet is busy; try again in a moment');
    end if;
  end if;

  if p_how = 'deliver' then
    v_state := public.courier_state(c.id, p_now);
    if v_state is distinct from 'deliver' then
      if v_state = 'late' then
        perform cmd.refuse('E_LATE', 'the contract''s time ran out');
      end if;
      perform cmd.refuse('E_NOT_THERE', format('bring %s %s to %s', trim_scale(c.qty), g.name, (select p.name from public.ports p where p.id = c.to_port)));
    end if;
    perform public.fleet_unload(c.fleet_id, g.code, c.qty);
    v_ev := public.emit_event(c.carrier_id, 'CONTRACT_DELIVERED', jsonb_build_object('contract', c.id, 'good', g.code, 'qty', c.qty,
              'to', (select p.code from public.ports p where p.id = c.to_port), 'reward', c.reward, 'collateral', c.collateral));
    perform public.credit(c.carrier_id, 'CONTRACT_REWARD', c.reward, v_ev);
    if c.collateral > 0 then
      perform public.credit(c.carrier_id, 'CONTRACT_RETURN', c.collateral, v_ev);
    end if;
    if c.poster_kind = 'company' and c.poster_id is not null then
      begin
        perform public.storage_put(c.poster_id, c.to_port, c.good_id, c.qty, null);
      exception when others then
        -- her shed at B is full: a delivery is never refused for it; the goods stand in her shed over its size until she takes them
        insert into public.player_storage (player_id, port_id, good_id, qty, basis) values (c.poster_id, c.to_port, c.good_id, c.qty, null)
        on conflict (player_id, port_id, good_id) do update set qty = public.player_storage.qty + excluded.qty;
      end;
      perform public.emit_event(c.poster_id, 'CONTRACT_DONE', jsonb_build_object('contract', c.id, 'good', g.code, 'qty', c.qty));
    end if;
    v_out := jsonb_build_object('how', 'deliver', 'reward', c.reward, 'collateral', c.collateral);
    update public.courier_contracts set status = 'delivered', settled_at = p_now, outcome = v_out where id = c.id;
    return v_out;
  end if;

  if p_how <> 'fail' then
    perform cmd.refuse('E_BAD_ORDER', 'a contract is delivered, failed, lapsed or cancelled');
  end if;
  -- FAIL: the units still hers to give go back (her hold first, then her shed at A); the rest are lost
  if c.fleet_id is not null then
    v_back := public.fleet_unload(c.fleet_id, g.code, least(c.qty, public.fleet_cargo_qty(c.fleet_id, g.code)));
  end if;
  if v_back < c.qty and c.carrier_id is not null then
    v_back := v_back + public.storage_take(c.carrier_id, c.from_port, c.good_id, c.qty - v_back);
  end if;
  v_lost := c.qty - v_back;
  if c.poster_kind = 'company' and c.poster_id is not null and v_back > 0 then
    begin
      perform public.storage_put(c.poster_id, c.from_port, c.good_id, v_back, null);
    exception when others then
      v_lost := c.qty;   -- her shed at A is full: what came back is lost too
      v_back := 0;
    end;
  end if;
  v_ev := public.emit_event(c.carrier_id, 'CONTRACT_FAILED', jsonb_build_object('contract', c.id, 'good', g.code, 'qty', c.qty,
            'collateral', c.collateral, 'why', p_why, 'returned', v_back, 'lost', v_lost));
  if c.poster_kind = 'city' then
    perform public.treasury_post(c.from_port, 'CONTRACT_FORFEIT', c.collateral, null, v_ev, true);
    perform public.treasury_post(c.from_port, 'CONTRACT_RETURN', c.reward, null, v_ev, true);
  elsif c.poster_id is not null then
    if c.collateral > 0 then
      perform public.credit(c.poster_id, 'CONTRACT_FORFEIT', c.collateral, v_ev);
    end if;
    perform public.credit(c.poster_id, 'CONTRACT_RETURN', c.reward, v_ev);
  end if;
  v_out := jsonb_build_object('how', 'fail', 'why', p_why, 'returned', v_back, 'lost', v_lost, 'collateral', c.collateral);
  update public.courier_contracts set status = 'failed', settled_at = p_now, outcome = v_out where id = c.id;
  return v_out;
end
$body$;

create function public.courier_take_for(p_player uuid, p_fleet uuid, p_contract uuid, p_version integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0483: SHE TAKES A CONTRACT with a fleet lying idle in harbour (0483's header): the collateral, the goods (aboard at A, else into her
-- Storage at A), ONE plan with stored courses ([SAIL A, TAKE <good> <units>,] SAIL B) through cmd.issue_lines AS HER (the caller). All of it
-- or none: a refused plan rolls the take back and its envelope is the answer. Raises the other refusals. Server only.
declare
  c       public.courier_contracts%rowtype;
  f       public.fleets%rowtype;
  g       public.goods%rowtype;
  v_a     text;
  v_b     text;
  v_s1    jsonb := jsonb_build_object('lines', '[]'::jsonb);
  v_s2    jsonb;
  v_lines jsonb;
  v_ev    uuid;
  v_r     jsonb;
begin
  if not exists (select 1 from public.fleets x where x.id = p_fleet and x.player_id = p_player) then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'that fleet is not yours');
  end if;
  perform voyage.settle(p_fleet);
  select * into f from public.fleets x where x.id = p_fleet;
  select * into c from public.courier_contracts x where x.id = p_contract for update;
  if c.id is null then
    perform cmd.refuse('E_NO_CONTRACT', 'there is no such contract');
  end if;
  if c.status <> 'open' or c.expires_at <= now() then
    perform cmd.refuse('E_TAKEN', 'that contract is no longer open');
  end if;
  if c.poster_id = p_player then
    perform cmd.refuse('E_OWN_CONTRACT', 'you cannot carry your own contract');
  end if;
  if (select count(*) from public.courier_contracts x where x.carrier_id = p_player and x.status = 'taken') >= public.wc_int('contracts_carry_max') then
    perform cmd.refuse('E_TOO_MANY', format('you carry %s contracts already', public.wc_int('contracts_carry_max')));
  end if;
  if f.status <> 'DOCKED' or (select p.kind from public.ports p where p.id = f.port_id) is distinct from 'HARBOUR' then
    perform cmd.refuse('E_NOT_DOCKED', format('%s is not in harbour', f.name));
  end if;
  if exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active')) then
    perform cmd.refuse('E_BUSY', format('%s has orders waiting', f.name));
  end if;
  if (coalesce(public.standing_routes_on(), false) and exists (select 1 from public.standing_routes r where r.fleet_id = f.id))
     or exists (select 1 from public.fleet_jobs j where j.fleet_id = f.id) then
    perform cmd.refuse('E_ROUTE_TAKEN', format('%s has a standing job', f.name));
  end if;
  select * into g from public.goods where id = c.good_id;
  v_a := (select p.code from public.ports p where p.id = c.from_port);
  v_b := (select p.code from public.ports p where p.id = c.to_port);
  if public.fleet_free_hold(f.id) < c.qty * g.bulk then
    perform cmd.refuse('E_HOLD_FULL', format('%s has no room for %s %s', f.name, trim_scale(c.qty), g.name));
  end if;

  v_ev := public.emit_event(p_player, 'CONTRACT_TAKEN', jsonb_build_object('contract', c.id, 'fleet', f.name, 'good', g.code, 'qty', c.qty,
            'from', v_a, 'to', v_b, 'reward', c.reward, 'collateral', c.collateral));
  if c.collateral > 0 then
    perform public.credit(p_player, 'CONTRACT_COLLATERAL', -c.collateral, v_ev);
  end if;
  if f.port_id = c.from_port then
    if public.fleet_load(f.id, g.code, c.qty, null) < c.qty then
      perform cmd.refuse('E_HOLD_FULL', format('%s has no room for %s %s', f.name, trim_scale(c.qty), g.name));
    end if;
  else
    perform public.storage_put(p_player, c.from_port, c.good_id, c.qty, null);
    v_s1 := public.fleet_job_sails(f.id, f.port_id, array[v_a]);
  end if;
  v_s2 := public.fleet_job_sails(f.id, c.from_port, array[v_b]);
  if v_s1 ? 'missing' or v_s2 ? 'missing' then
    perform cmd.refuse('E_NO_COURSE', format('no stored course reaches %s', coalesce(v_s1->>'missing', v_s2->>'missing')));
  end if;
  v_lines := (v_s1->'lines')
             || case when f.port_id = c.from_port then '[]'::jsonb
                     else jsonb_build_array(jsonb_build_object('text', format('TAKE %s %s', g.code, trim_scale(c.qty)))) end
             || (v_s2->'lines');
  update public.courier_contracts
     set status = 'taken', carrier_id = p_player, fleet_id = f.id, taken_at = now(), deliver_by = now() + make_interval(secs => c.window_s)
   where id = c.id;
  v_r := cmd.issue_lines(f.id, v_lines, p_version);
  if not coalesce((v_r->>'ok')::boolean, false) then
    raise exception using errcode = 'ZC483', message = coalesce(v_r::text, '{}');
  end if;
  return jsonb_build_object('ok', true, 'contract', c.id, 'fleet', f.id, 'from', v_a, 'to', v_b,
                            'deliver_by', now() + make_interval(secs => c.window_s), 'orders', v_r->'orders');
end
$body$;

create function public.courier_moves(p_player uuid, p_purse bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0483: HER CONTRACT CARDS for HQ's board (public.hq_board_for's one hunk). Dark: []. Lit (0483's header): TAKE, for each idle fleet of
-- hers (DOCKED in a harbour, nothing queued, no standing route or job), each open contract not hers whose trip (her port to A, then A to
-- B, at her fleet's speed) fits its window, whose collateral her purse covers, whose lot her hold takes (and, away from A, her shed at A);
-- the best contracts_board_cards by coin an hour; and DELIVER, her taken contracts that deliver now (public.courier_state). Writes nothing.
declare
  v_tc    numeric := greatest(coalesce(public.wc_num('time_compression'), 1), 1);
  v_floor numeric := greatest(1, coalesce(public.wc_num('hq_board_request_floor_s'), 900));
  v_cards int := greatest(0, coalesce(public.wc_int('contracts_board_cards'), 6));
  v_routes boolean := coalesce(public.standing_routes_on(), false);
  v_full  boolean;
  v_take  jsonb;
  v_give  jsonb;
begin
  if not public.courier_on() or p_player is null then
    return '[]'::jsonb;
  end if;
  v_full := (select count(*) from public.courier_contracts x where x.carrier_id = p_player and x.status = 'taken') >= public.wc_int('contracts_carry_max');

  if not v_full then
    with fl as materialized (
      select f.id, f.name, f.version, f.port_id, p.code as at, greatest(coalesce(voyage.fleet_speed(f.id), 0), 0.5) as kn,
             public.fleet_free_hold(f.id) as free
        from public.fleets f join public.ports p on p.id = f.port_id
       where f.player_id = p_player and f.status = 'DOCKED' and p.kind = 'HARBOUR'
         and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active'))
         and not (v_routes and exists (select 1 from public.standing_routes r where r.fleet_id = f.id))
         and not exists (select 1 from public.fleet_jobs j where j.fleet_id = f.id)
    ), cc as materialized (
      select c.id, c.poster_kind, c.poster_id, c.from_port, c.to_port, c.qty, c.nm, c.reward, c.collateral, c.window_s, c.expires_at,
             g.code as gcode, g.bulk, pa.code as a, pb.code as b,
             case when c.poster_kind = 'city' then pa.name else (select pl.company_name from public.players pl where pl.id = c.poster_id) end as poster_name
        from public.courier_contracts c
        join public.goods g on g.id = c.good_id
        join public.ports pa on pa.id = c.from_port
        join public.ports pb on pb.id = c.to_port
       where c.status = 'open' and c.expires_at > now() and c.poster_id is distinct from p_player and c.collateral <= p_purse
    ), rr as materialized (
      select fl.id as fid, r.port_id, r.nm from fl cross join lateral voyage.reach_from(fl.port_id) r
       where r.port_id in (select cc.from_port from cc)
    ), k as (
      select fl.id as fid, fl.name as fname, fl.version, fl.at, cc.*,
             (case when cc.from_port = fl.port_id then 0 else rr.nm end + cc.nm) * 3600 / (fl.kn * v_tc) as secs
        from fl cross join cc
        left join rr on rr.fid = fl.id and rr.port_id = cc.from_port
       where (cc.from_port = fl.port_id or rr.nm is not null)
         and cc.qty * cc.bulk <= fl.free
         and (cc.from_port = fl.port_id or public.storage_cap(cc.from_port) - public.storage_used(p_player, cc.from_port) >= cc.qty * cc.bulk)
    )
    select coalesce(jsonb_agg(z.o order by z.score desc, z.id), '[]'::jsonb) into v_take
      from (select k.id::text || ':' || k.fid::text as id, round(k.reward * 3600 / greatest(k.secs, 1)) as score,
                   jsonb_build_object(
                     'id', format('contract:%s:%s', k.id, k.fid), 'kind', 'contract', 'band', 1,
                     'fleet', k.fid, 'fleet_name', k.fname, 'at', k.at,
                     'score', round(k.reward * 3600 / greatest(k.secs, 1)), 'profit', k.reward, 'seconds', round(k.secs),
                     'risk', public.hq_course_risk(array[k.at, k.a, k.b]),
                     'needs', jsonb_build_object('good', k.gcode, 'units', k.qty, 'from', k.a, 'to', k.b, 'collateral', k.collateral,
                                                 'window', k.window_s, 'poster', k.poster_kind, 'poster_name', k.poster_name, 'expires_at', k.expires_at),
                     'act', jsonb_build_object('rpc', 'cmd.take_contract', 'args', jsonb_build_object('fleet', k.fid, 'contract', k.id, 'version', k.version))) as o
              from k
             where k.secs <= k.window_s
             order by k.reward / greatest(k.secs, 1) desc, k.id, k.fid
             limit v_cards) z;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', format('deliver:%s', c.id), 'kind', 'contract', 'band', 1,
           'fleet', c.fleet_id, 'fleet_name', f.name, 'at', pb.code,
           'score', round(c.reward * 3600 / v_floor), 'profit', c.reward, 'seconds', null,
           'risk', null,
           'needs', jsonb_build_object('good', g.code, 'units', c.qty, 'from', pa.code, 'to', pb.code, 'collateral', c.collateral,
                                       'deliver_by', c.deliver_by, 'poster', c.poster_kind),
           'act', jsonb_build_object('rpc', 'cmd.deliver_contract', 'args', jsonb_build_object('contract', c.id))) order by c.deliver_by, c.id), '[]'::jsonb)
    into v_give
    from public.courier_contracts c
    join public.goods g on g.id = c.good_id
    join public.ports pa on pa.id = c.from_port
    join public.ports pb on pb.id = c.to_port
    join public.fleets f on f.id = c.fleet_id
   where c.carrier_id = p_player and c.status = 'taken' and public.courier_state(c.id) = 'deliver';

  return coalesce(v_take, '[]'::jsonb) || v_give;
end
$body$;

create function public.courier_rows(p_player uuid, p_as text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0483: her contracts as poster ('posted') or as carrier ('carried'), the live first, then the settled newest first (as kept).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'status', c.status, 'poster', c.poster_kind, 'good', g.code, 'qty', c.qty, 'from', pa.code, 'to', pb.code, 'nm', c.nm,
           'value', c.value, 'reward', c.reward, 'collateral', c.collateral, 'window', c.window_s, 'posted_at', c.posted_at,
           'expires_at', c.expires_at, 'taken_at', c.taken_at, 'deliver_by', c.deliver_by, 'settled_at', c.settled_at,
           'fleet', c.fleet_id, 'fleet_name', (select f.name from public.fleets f where f.id = c.fleet_id),
           'state', public.courier_state(c.id), 'outcome', c.outcome)
         order by (c.status in ('open', 'taken')) desc, coalesce(c.settled_at, c.posted_at) desc, c.id), '[]'::jsonb)
    from public.courier_contracts c
    join public.goods g on g.id = c.good_id
    join public.ports pa on pa.id = c.from_port
    join public.ports pb on pb.id = c.to_port
   where (p_as = 'posted' and c.poster_id = p_player) or (p_as = 'carried' and c.carrier_id = p_player)
$body$;

create function world.courier_contracts()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0483: HER CONTRACTS (the client's one read). Dark {"on": false}; lit, signed out or a merchant {"on": true, "company": false}; lit her
-- company {"on", "company", open (the open contracts in the world), posted, carried (public.courier_rows), limits}. Writes nothing.
declare
  v_me uuid := public.current_player_id();
begin
  if not public.courier_on() then
    return jsonb_build_object('on', false);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('on', true, 'company', false);
  end if;
  return jsonb_build_object('on', true, 'company', true,
    'open', (select count(*) from public.courier_contracts c where c.status = 'open'),
    'posted', public.courier_rows(v_me, 'posted'),
    'carried', public.courier_rows(v_me, 'carried'),
    'limits', jsonb_build_object('post_max', public.wc_int('contracts_post_max'), 'carry_max', public.wc_int('contracts_carry_max'),
                                 'hours_min', public.wc_num('contracts_hours_min'), 'hours_max', public.wc_num('contracts_hours_max')));
end
$body$;

create function public.courier_door(p_what text, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0483: THE FIVE DOORS' ONE BODY (cmd.take_contract, cmd.deliver_contract, cmd.fail_contract, cmd.post_contract, cmd.cancel_contract): the
-- switch (E_NOT_IN_USE), her company (E_NO_HOUSE), then the act as her; every refusal as the {ok: false} envelope. Server only.
declare
  v_me  uuid := public.current_player_id();
  c     public.courier_contracts%rowtype;
  v_r   jsonb;
  v_det text;
  v_s   numeric;
begin
  if not public.courier_on() then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_USE', 'error_message', 'Contracts are not open yet.', 'fixes', '[]'::jsonb);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    if p_what = 'take' then
      return public.courier_take_for(v_me, (p_args->>'fleet')::uuid, (p_args->>'contract')::uuid, (p_args->>'version')::int);
    end if;
    if p_what = 'post' then
      if (select count(*) from public.courier_contracts x where x.poster_id = v_me and x.status in ('open', 'taken')) >= public.wc_int('contracts_post_max') then
        perform cmd.refuse('E_TOO_MANY', format('you have %s contracts posted already', public.wc_int('contracts_post_max')));
      end if;
      v_s := (p_args->>'hours')::numeric;
      if v_s is null or v_s < public.wc_num('contracts_hours_min') or v_s > public.wc_num('contracts_hours_max') then
        perform cmd.refuse('E_BAD_ORDER', format('give %s to %s hours', public.wc_num('contracts_hours_min'), public.wc_num('contracts_hours_max')));
      end if;
      if coalesce((p_args->>'qty')::numeric, 0) <> floor(coalesce((p_args->>'qty')::numeric, 0)) then
        perform cmd.refuse('E_NO_QTY', 'a whole number of units');
      end if;
      if public.storage_cap((p_args->>'to')::uuid) <= 0 then
        perform cmd.refuse('E_NO_SHED', 'the harbour you send to keeps no warehouse for you');
      end if;
      v_r := jsonb_build_object('ok', true, 'contract',
               public.courier_post('company', v_me, (p_args->>'from')::uuid, (p_args->>'to')::uuid, (p_args->>'good')::uuid,
                                    (p_args->>'qty')::numeric, (p_args->>'reward')::bigint, (p_args->>'collateral')::bigint, ceil(v_s * 3600)::int));
      return v_r;
    end if;
    select * into c from public.courier_contracts x where x.id = (p_args->>'contract')::uuid;
    if c.id is null then
      perform cmd.refuse('E_NO_CONTRACT', 'there is no such contract');
    end if;
    if p_what = 'cancel' then
      if c.poster_id is distinct from v_me then
        perform cmd.refuse('E_NO_CONTRACT', 'that contract is not yours');
      end if;
      return jsonb_build_object('ok', true, 'outcome', public.courier_settle(c.id, 'cancel', 'cancelled'));
    end if;
    if c.carrier_id is distinct from v_me then
      perform cmd.refuse('E_NO_CONTRACT', 'you do not carry that contract');
    end if;
    if p_what = 'deliver' then
      if c.fleet_id is not null then
        perform voyage.settle(c.fleet_id);
      end if;
      return jsonb_build_object('ok', true, 'outcome', public.courier_settle(c.id, 'deliver'));
    end if;
    if p_what = 'fail' then
      return jsonb_build_object('ok', true, 'outcome', public.courier_settle(c.id, 'fail', 'given up'));
    end if;
    perform cmd.refuse('E_BAD_ORDER', 'no such contract act');
  exception
    when sqlstate 'ZC483' then
      return sqlerrm::jsonb;   -- the plan's own refusal (cmd.issue_lines' envelope); the take is rolled back with it
    when others then
      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
      get stacked diagnostics v_det = pg_exception_detail;
      return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$;

create function cmd.take_contract(p_fleet uuid, p_contract uuid, p_expected_version integer default null)
returns jsonb language sql security definer set search_path = public, pg_temp as $body$
  -- 0483: TAKE A CONTRACT with this fleet: the collateral, the goods, one plan sailed on stored courses (public.courier_take_for). The board's one press.
  select public.courier_door('take', jsonb_build_object('fleet', p_fleet, 'contract', p_contract, 'version', p_expected_version))
$body$;

create function cmd.deliver_contract(p_contract uuid)
returns jsonb language sql security definer set search_path = public, pg_temp as $body$
  -- 0483: DELIVER IT NOW (her fleet lies at B with the units, in time): the reward and the collateral are hers (public.courier_settle).
  select public.courier_door('deliver', jsonb_build_object('contract', p_contract))
$body$;

create function cmd.fail_contract(p_contract uuid)
returns jsonb language sql security definer set search_path = public, pg_temp as $body$
  -- 0483: GIVE IT UP: the collateral is the poster's, the goods still hers to give go back (public.courier_settle).
  select public.courier_door('fail', jsonb_build_object('contract', p_contract))
$body$;

create function cmd.post_contract(p_from uuid, p_to uuid, p_good uuid, p_qty numeric, p_reward bigint, p_collateral bigint, p_hours numeric)
returns jsonb language sql security definer set search_path = public, pg_temp as $body$
  -- 0483: POST A CONTRACT ("Post a contract"): her goods out of her Storage at A, the reward held, for another company to carry to B.
  select public.courier_door('post', jsonb_build_object('from', p_from, 'to', p_to, 'good', p_good, 'qty', p_qty, 'reward', p_reward,
                                                         'collateral', p_collateral, 'hours', p_hours))
$body$;

create function cmd.cancel_contract(p_contract uuid)
returns jsonb language sql security definer set search_path = public, pg_temp as $body$
  -- 0483: TAKE HER OWN UNTAKEN CONTRACT DOWN: the reward and the goods back (public.courier_settle).
  select public.courier_door('cancel', jsonb_build_object('contract', p_contract))
$body$;

create function public.tick_courier_contracts(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0483: THE RUN (pg_cron byeharu-voyage:contracts, every 2 minutes; never on the arrivals beat). Dark: one knob read. Lit: the settled rows
-- past contracts_keep_days go (200 at most); the untaken past their time lapse (50 at most); the taken deliver or fail (100 at most, the
-- nearest deadline first; SKIP LOCKED, a busy one waits for the next run); then houses and cities post while the open ones number under
-- ceil(houses / contracts_houses_per), contracts_posts_per_tick at most. A receipt.
declare
  v_t0    timestamptz := clock_timestamp();
  x       record;
  v_gone  int := 0;
  v_lapse int := 0;
  v_done  int := 0;
  v_fail  int := 0;
  v_post  int := 0;
  v_cap   int;
  v_open  int;
  v_st    text;
begin
  if not public.courier_on() then
    return jsonb_build_object('on', false);
  end if;
  with d as (
    delete from public.courier_contracts c
     where c.id in (select y.id from public.courier_contracts y
                     where y.settled_at < p_now - make_interval(days => greatest(1, public.wc_int('contracts_keep_days')))
                     order by y.settled_at limit 200)
    returning 1)
  select count(*) into v_gone from d;

  for x in select c.id from public.courier_contracts c where c.status = 'open' and c.expires_at <= p_now
            order by c.expires_at, c.id limit 50 for update skip locked loop
    begin
      perform public.courier_settle(x.id, 'lapse', 'untaken', p_now);
      v_lapse := v_lapse + 1;
    exception when others then
      null;   -- tried again next run
    end;
  end loop;

  for x in select c.id from public.courier_contracts c where c.status = 'taken'
            order by c.deliver_by, c.id limit 100 for update skip locked loop
    v_st := public.courier_state(x.id, p_now);
    continue when v_st = 'wait';
    begin
      perform public.courier_settle(x.id, case when v_st = 'deliver' then 'deliver' else 'fail' end, case when v_st = 'late' then 'late' end, p_now);
      if v_st = 'deliver' then v_done := v_done + 1; else v_fail := v_fail + 1; end if;
    exception when others then
      null;   -- her fleet is busy (E_BUSY) or another settle holds it: next run
    end;
  end loop;

  v_cap  := ceil((select count(*) from public.npc_houses)::numeric / greatest(public.wc_int('contracts_houses_per'), 1))::int;
  v_open := (select count(*) from public.courier_contracts c where c.status = 'open' and c.poster_kind <> 'company');
  for i in 1 .. least(greatest(public.wc_int('contracts_posts_per_tick'), 0), greatest(v_cap - v_open, 0)) loop
    v_post := v_post + public.courier_draw(format('%s:%s', floor(extract(epoch from p_now) / 60)::bigint, i), p_now);
  end loop;

  return jsonb_build_object('on', true, 'deleted', v_gone, 'lapsed', v_lapse, 'delivered', v_done, 'failed', v_fail, 'posted', v_post,
                            'cap', v_cap, 'open', v_open + v_post, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end
$body$;

-- grants: the six doors to authenticated alone; every core and the tick server only (service_role too: the platform grants execute on a
-- new function by default, 0459's first push)
do $gr$
declare
  q text;
begin
  foreach q in array array['cmd.take_contract(uuid,uuid,integer)', 'cmd.deliver_contract(uuid)', 'cmd.fail_contract(uuid)',
                           'cmd.post_contract(uuid,uuid,uuid,numeric,bigint,bigint,numeric)', 'cmd.cancel_contract(uuid)', 'world.courier_contracts()'] loop
    execute format('revoke all on function %s from public, anon', q::regprocedure);
    execute format('grant execute on function %s to authenticated', q::regprocedure);
  end loop;
  foreach q in array array['public.courier_on()', 'public.courier_post(text,uuid,uuid,uuid,uuid,numeric,bigint,bigint,integer,timestamptz)',
                           'public.courier_draw(text,timestamptz)', 'public.courier_state(uuid,timestamptz)', 'public.courier_settle(uuid,text,text,timestamptz)',
                           'public.courier_take_for(uuid,uuid,uuid,integer)', 'public.courier_moves(uuid,bigint)', 'public.courier_rows(uuid,text)',
                           'public.courier_door(text,jsonb)', 'public.tick_courier_contracts(timestamptz)'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', q::regprocedure);
  end loop;
end
$gr$;
comment on function world.courier_contracts() is
  '0483: her courier contracts (dark {"on": false}): those she posted and those she carries, live and lately settled, and the limits. A read. Client door.';

-- ── 5. THE HUNKS, THE SELF-ASSERT, THE PROBE, THE JOB ──
do $m$
declare
  c_new    constant text[] := array['public.courier_on()', 'public.courier_post(text,uuid,uuid,uuid,uuid,numeric,bigint,bigint,integer,timestamptz)',
                                    'public.courier_draw(text,timestamptz)', 'public.courier_state(uuid,timestamptz)', 'public.courier_settle(uuid,text,text,timestamptz)',
                                    'public.courier_take_for(uuid,uuid,uuid,integer)', 'public.courier_moves(uuid,bigint)', 'public.courier_rows(uuid,text)',
                                    'public.courier_door(text,jsonb)', 'public.tick_courier_contracts(timestamptz)',
                                    'cmd.take_contract(uuid,uuid,integer)', 'cmd.deliver_contract(uuid)', 'cmd.fail_contract(uuid)',
                                    'cmd.post_contract(uuid,uuid,uuid,numeric,bigint,bigint,numeric)', 'cmd.cancel_contract(uuid)', 'world.courier_contracts()'];
  c_doors  constant text[] := array['cmd.take_contract(uuid,uuid,integer)', 'cmd.deliver_contract(uuid)', 'cmd.fail_contract(uuid)',
                                    'cmd.post_contract(uuid,uuid,uuid,numeric,bigint,bigint,numeric)', 'cmd.cancel_contract(uuid)', 'world.courier_contracts()'];
  c_ua     constant uuid := '00000000-0483-4000-8000-0000000000a1';
  c_ub     constant uuid := '00000000-0483-4000-8000-0000000000b1';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_note      text := '';
  v_lived     boolean := false;
  v_day       timestamptz := date_trunc('day', now() at time zone 'utc') at time zone 'utc';   -- 00:00 UTC of today: before 23:30 UTC, never straddling midnight
  v_a         uuid;
  v_b         uuid;
  v_fb        uuid;
  v_lis       uuid;
  v_to        uuid;
  v_tocode    text;
  v_good      uuid;
  v_gcode     text;
  v_house     uuid;
  v_hp0       bigint;
  v_pa0       bigint;
  v_pb0       bigint;
  v_c         uuid;
  v_r         jsonb;
  v_moves     jsonb;
  v_texts     text;
  v_tick      jsonb;
  v_ver       int;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0483 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0483 values
  ('public.hq_board_for(uuid)', 1,
$h$  -- THE YARD: the second ship (fewer than hq_board_build_below ships, none on order), the cheapest hull at a yard where she lies
$h$,
$h$  -- 0483 (contracts_enabled): the courier contracts she can take now, and those she can deliver (public.courier_moves); dark none
  v_moves := v_moves || public.courier_moves(p_player, v_purse);

  -- THE YARD: the second ship (fewer than hq_board_build_below ships, none on order), the cheapest hull at a yard where she lies
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'away_report',           ''),$h$,
$h$      ('world',       'away_report',           ''),
      -- 0483: courier contracts (dark: the doors E_NOT_IN_USE, the read {"on": false})
      ('cmd',         'take_contract',         'uuid, uuid, integer'),
      ('cmd',         'deliver_contract',      'uuid'),
      ('cmd',         'fail_contract',         'uuid'),
      ('cmd',         'post_contract',         'uuid, uuid, uuid, numeric, bigint, bigint, numeric'),
      ('cmd',         'cancel_contract',       'uuid'),
      ('world',       'courier_contracts',     ''),$h$);

  for v_h in select h.fn from hunks_0483 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0483 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0483 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0483 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0483 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0483 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── SELF-ASSERT: the catalog, the knobs, the doors ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in ('public.hq_board_for(uuid)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure)
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) is distinct from (select pre.fns from pre_0483 pre) then
    raise exception '0483 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(q.oid::regprocedure::text || ':' || coalesce(q.proacl::text, '') || ':' || q.provolatile::text || q.prosecdef::text || coalesce(q.proconfig::text, '') || ':' || q.proowner::text, ',' order by q.oid::regprocedure::text))
        from pg_proc q where q.oid in ('public.hq_board_for(uuid)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure))
     is distinct from (select pre.meta from pre_0483 pre) then
    raise exception '0483 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select count(*) from pg_proc p
       where p.oid = any (array['public.courier_on()', 'public.courier_state(uuid,timestamptz)', 'public.courier_moves(uuid,bigint)',
                                'public.courier_rows(uuid,text)', 'world.courier_contracts()']::regprocedure[]::oid[])
         and p.provolatile = 's') <> 5 then
    raise exception '0483 self-assert FAIL: a read is not STABLE (the switch, the state, the cards, the rows and the read are reads)';
  end if;
  if public.wc('contracts_enabled') <> 'false'::jsonb or public.wc_int('contracts_houses_per') <> 20 or public.wc_int('contracts_posts_per_tick') <> 3
     or public.wc_int('contracts_carry_max') <> 2 or public.wc_int('contracts_post_max') <> 3 or public.wc_int('contracts_keep_days') <> 3
     or (select count(*) from public.world_config c where c.key like 'contracts\_%') <> 23 then
    raise exception '0483 self-assert FAIL: the knobs are not as written';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) in (('cmd', 'take_contract', 'uuid, uuid, integer'), ('cmd', 'deliver_contract', 'uuid'),
                                                              ('cmd', 'fail_contract', 'uuid'), ('cmd', 'post_contract', 'uuid, uuid, uuid, numeric, bigint, bigint, numeric'),
                                                              ('cmd', 'cancel_contract', 'uuid'), ('world', 'courier_contracts', ''))
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 6
     or exists (select 1 from unnest(c_new) u(q)
                 where u.q <> all (c_doors)
                   and (has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                        or has_function_privilege('service_role', u.q::regprocedure, 'execute')))
     or has_table_privilege('authenticated', 'public.courier_contracts', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.courier_contracts', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.courier_contracts'::regclass)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0483 self-assert FAIL: a door is not registered for authenticated alone, a core or the tick is reachable by a client, or the table is';
  end if;

  -- ── THE PROBE, rolled back by a raised sentinel (no time-budgeted read is asked; nothing is compared twice) ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_a := public.new_house(c_ua, 'Casa do Porte 0483', 'PRT');
    v_b := public.new_house(c_ub, 'Casa da Carga 0483', 'PRT');
    select f.id into v_fb from public.fleets f where f.player_id = v_b;
    update public.players p set ducats = 200000 where p.id in (v_a, v_b);
    update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_fb;
    -- the good: the lightest Lisbon offers; B: the nearest harbour 150 miles or more from Lisbon that trades it, with a stored course
    select g.id, g.code into v_good, v_gcode
      from public.port_offered_goods(v_lis) o join public.goods g on g.id = o.good_id
      join public.port_goods pg on pg.port_id = v_lis and pg.good_id = g.id
     where g.bulk > 0 order by g.bulk, g.code limit 1;
    select r.port_id, r.code into v_to, v_tocode
      from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR'
      join public.port_goods pg on pg.port_id = r.port_id and pg.good_id = v_good
     where r.nm >= 150 and public.sea_course(v_lis, r.port_id) is not null and public.storage_cap(r.port_id) > 0
     order by r.nm, r.code limit 1;
    select h.player_id into v_house from public.npc_houses h join public.players p on p.id = h.player_id order by p.ducats desc, h.roster_ord limit 1;
    if v_good is null or v_to is null or v_house is null or public.storage_cap(v_lis) <= 0 then
      raise exception '0483 self-assert FAIL: the world has no good at Lisbon, no harbour with a stored course to post to, no house, or no shed at Lisbon (% / % / %)', v_gcode, v_tocode, v_house;
    end if;
    perform public.storage_put(v_a, v_lis, v_good, 10, 0);
    perform cmd.assume_identity(c_ua);

    -- (a) DARK: the doors refuse, the read is {"on": false}, the tick and the cards are nothing
    if world.courier_contracts() is distinct from '{"on": false}'::jsonb
       or cmd.post_contract(v_lis, v_to, v_good, 10, 100, 500, 4)->>'error_code' is distinct from 'E_NOT_IN_USE'
       or cmd.take_contract(v_fb, gen_random_uuid(), null)->>'error_code' is distinct from 'E_NOT_IN_USE'
       or cmd.deliver_contract(gen_random_uuid())->>'error_code' is distinct from 'E_NOT_IN_USE'
       or cmd.fail_contract(gen_random_uuid())->>'error_code' is distinct from 'E_NOT_IN_USE'
       or cmd.cancel_contract(gen_random_uuid())->>'error_code' is distinct from 'E_NOT_IN_USE'
       or public.tick_courier_contracts(v_day + interval '1 hour') is distinct from '{"on": false}'::jsonb
       or public.courier_moves(v_b, 200000) <> '[]'::jsonb
       or exists (select 1 from public.courier_contracts) then
      raise exception '0483 self-assert FAIL: dark, a door opened, the read is not {"on": false}, a card showed or the tick wrote';
    end if;
    update public.world_config set value = 'true'::jsonb where key in ('contracts_enabled', 'sea_courses_enabled');
    update public.world_config set value = to_jsonb(0) where key = 'contracts_posts_per_tick';   -- the houses post in (f) alone

    -- (b) A COMPANY POSTS from Lisbon's Storage: the reward held, her goods out of her shed; the wrong ones refused
    if cmd.post_contract(v_lis, v_to, v_good, 11, 100, 500, 4)->>'error_code' is distinct from 'E_NONE_STORED'
       or cmd.post_contract(v_lis, v_to, v_good, 10, 100, 500, 400)->>'error_code' is distinct from 'E_BAD_ORDER'
       or cmd.post_contract(v_lis, v_lis, v_good, 10, 100, 500, 4)->>'error_code' is distinct from 'E_BAD_ORDER' then
      raise exception '0483 self-assert FAIL: a wrong post was not refused by its own code';
    end if;
    v_pa0 := (select p.ducats from public.players p where p.id = v_a);
    v_r := cmd.post_contract(v_lis, v_to, v_good, 10, 1000, 5000, 4);
    v_c := (v_r->>'contract')::uuid;
    if (v_r->>'ok')::boolean is not true or (select p.ducats from public.players p where p.id = v_a) <> v_pa0 - 1000
       or coalesce((select ps.qty from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = v_good), 0) <> 0
       or (select c.status from public.courier_contracts c where c.id = v_c) <> 'open'
       or (select l.ducats_delta from public.ledger l where l.player_id = v_a and l.kind = 'CONTRACT_ESCROW') <> -1000
       or jsonb_array_length(world.courier_contracts()->'posted') <> 1 then
      raise exception '0483 self-assert FAIL: the post did not hold the reward and her goods: %', v_r;
    end if;

    -- (c) ANOTHER TAKES IT at Lisbon from HQ's card: the collateral out, the goods aboard, ONE plan SAIL <B> with a stored course; she departs
    perform cmd.assume_identity(c_ub);
    v_moves := public.courier_moves(v_b, 200000);
    if not exists (select 1 from jsonb_array_elements(v_moves) e
                    where e->>'kind' = 'contract' and e #>> '{act,rpc}' = 'cmd.take_contract' and (e #>> '{act,args,contract}')::uuid = v_c
                      and (e->>'profit')::bigint = 1000 and (e->>'score')::numeric > 0 and e #>> '{needs,to}' = v_tocode and e ? 'risk') then
      raise exception '0483 self-assert FAIL: her board does not offer the contract to take: %', left(v_moves::text, 600);
    end if;
    v_pb0 := (select p.ducats from public.players p where p.id = v_b);
    v_ver := (select f.version from public.fleets f where f.id = v_fb);
    v_r := cmd.take_contract(v_fb, v_c, v_ver);
    select string_agg(o.raw_text, ' / ' order by o.seq) into v_texts from public.orders o
     where o.fleet_id = v_fb and o.plan_id = (select o2.plan_id from public.orders o2 where o2.fleet_id = v_fb order by o2.issued_at desc, o2.seq desc limit 1);
    if (v_r->>'ok')::boolean is not true or (select p.ducats from public.players p where p.id = v_b) <> v_pb0 - 5000
       or public.fleet_cargo_qty(v_fb, v_gcode) <> 10 or v_texts is distinct from 'SAIL ' || v_tocode
       or exists (select 1 from public.orders o where o.fleet_id = v_fb and o.verb = 'SAIL' and jsonb_typeof(o.args->'path') <> 'array')
       or (select f.status from public.fleets f where f.id = v_fb) <> 'SAILING'
       or (select c.status from public.courier_contracts c where c.id = v_c) <> 'taken'
       or public.courier_state(v_c) <> 'wait' then
      raise exception '0483 self-assert FAIL: the take did not hold the collateral, load the goods and sail for % on a stored course: % / % (%)', v_tocode, v_r, v_texts,
        (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fb);
    end if;

    -- (d) SHE ARRIVES (her voyage ended at B a minute ago, placed by hand: the voyage's own settle, with its sea risk, is proof 186's) and
    --     THE TICK DELIVERS: her hold empties, the poster's shed at B fills, the reward and her collateral are hers
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute', status = 'ARRIVED'
     where fleet_id = v_fb and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_to where id = v_fb;
    update public.orders set status = 'done' where fleet_id = v_fb and status in ('pending', 'active');
    if public.courier_state(v_c) <> 'deliver' then
      raise exception '0483 self-assert FAIL: arrived at %, the contract does not deliver: % at %', v_tocode,
        (select f.status from public.fleets f where f.id = v_fb), (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fb);
    end if;
    v_pb0 := (select p.ducats from public.players p where p.id = v_b);
    v_tick := public.tick_courier_contracts(now());
    if (v_tick->>'delivered')::int <> 1 or (select c.status from public.courier_contracts c where c.id = v_c) <> 'delivered'
       or public.fleet_cargo_qty(v_fb, v_gcode) <> 0
       or (select p.ducats from public.players p where p.id = v_b) <> v_pb0 + 6000
       or (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_b and l.kind in ('CONTRACT_REWARD', 'CONTRACT_RETURN', 'CONTRACT_COLLATERAL')) <> 1000
       or coalesce((select ps.qty from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_to and ps.good_id = v_good), 0) <> 10 then
      raise exception '0483 self-assert FAIL: the tick did not deliver to the ducat: %', v_tick;
    end if;
    v_note := format('company LIS-%s %s x10 delivered', v_tocode, v_gcode);

    -- (e) A HOUSE POSTS, she takes it at B (now her port: the goods wait in her shed at A, so her plan is SAIL LIS / TAKE / SAIL B), runs
    --     late: the tick fails it; the house takes the collateral and its reward back; the goods are returned (out of her shed)
    v_hp0 := (select p.ducats from public.players p where p.id = v_house);
    v_c := public.courier_post('house', v_house, v_lis, v_to, v_good, 8, 300, 900, 3600, now());
    if (select p.ducats from public.players p where p.id = v_house) <> v_hp0 - 300 then
      raise exception '0483 self-assert FAIL: the house''s reward was not held';
    end if;
    update public.orders set status = 'cancelled' where fleet_id = v_fb and status in ('pending', 'active');
    v_ver := (select f.version from public.fleets f where f.id = v_fb);
    v_r := cmd.take_contract(v_fb, v_c, v_ver);
    select string_agg(o.raw_text, ' / ' order by o.seq) into v_texts from public.orders o
     where o.fleet_id = v_fb and o.plan_id = (select o2.plan_id from public.orders o2 where o2.fleet_id = v_fb order by o2.issued_at desc, o2.seq desc limit 1);
    if (v_r->>'ok')::boolean is not true or v_texts is distinct from format('SAIL LIS / TAKE %s 8 / SAIL %s', v_gcode, v_tocode) then
      raise exception '0483 self-assert FAIL: taken away from A, the plan is not SAIL LIS / TAKE / SAIL B: % / %', v_r, v_texts;
    end if;
    update public.courier_contracts set deliver_by = now() - interval '1 second' where id = v_c;
    v_pb0 := (select p.ducats from public.players p where p.id = v_b);
    v_tick := public.tick_courier_contracts(now());
    if (v_tick->>'failed')::int <> 1 or (select c.status from public.courier_contracts c where c.id = v_c) <> 'failed'
       or (select (c.outcome->>'returned')::numeric from public.courier_contracts c where c.id = v_c) <> 8
       or (select p.ducats from public.players p where p.id = v_house) <> v_hp0 + 900
       or (select p.ducats from public.players p where p.id = v_b) <> v_pb0
       or coalesce((select ps.qty from public.player_storage ps where ps.player_id = v_b and ps.port_id = v_lis and ps.good_id = v_good), 0) <> 0 then
      raise exception '0483 self-assert FAIL: late, the tick did not fail it to the ducat: % / %', v_tick, (select c.outcome from public.courier_contracts c where c.id = v_c);
    end if;

    -- (f) GIVEN UP WITH THE GOODS GONE: lost; AN UNTAKEN ONE LAPSES: the reward back; THE HOUSES POST at most to the cap, each escrowed
    update public.orders set status = 'cancelled' where fleet_id = v_fb and status in ('pending', 'active');
    update public.voyages set status = 'ARRIVED' where fleet_id = v_fb and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_fb;
    v_c := public.courier_post('house', v_house, v_lis, v_to, v_good, 6, 200, 700, 3600, now());
    v_r := cmd.take_contract(v_fb, v_c, (select f.version from public.fleets f where f.id = v_fb));
    perform public.fleet_unload(v_fb, v_gcode, public.fleet_cargo_qty(v_fb, v_gcode));   -- the goods gone (a raid, a sale)
    v_r := cmd.fail_contract(v_c);
    if (v_r->>'ok')::boolean is not true or (v_r #>> '{outcome,lost}')::numeric <> 6 or (v_r #>> '{outcome,returned}')::numeric <> 0 then
      raise exception '0483 self-assert FAIL: given up with the goods gone, they are not lost: %', v_r;
    end if;
    v_hp0 := (select p.ducats from public.players p where p.id = v_house);
    v_c := public.courier_post('house', v_house, v_lis, v_to, v_good, 5, 150, 600, 3600, now());
    update public.courier_contracts set expires_at = now() - interval '1 second' where id = v_c;   -- untaken past its time
    v_tick := public.tick_courier_contracts(now());
    if (v_tick->>'lapsed')::int <> 1 or (select c.status from public.courier_contracts c where c.id = v_c) <> 'lapsed'
       or (select p.ducats from public.players p where p.id = v_house) <> v_hp0 then
      raise exception '0483 self-assert FAIL: the untaken one did not lapse with its reward back: %', v_tick;
    end if;
    update public.world_config set value = to_jsonb(3) where key = 'contracts_posts_per_tick';
    update public.world_config set value = to_jsonb((select count(*) from public.npc_houses)) where key = 'contracts_houses_per';   -- the cap: 1
    v_tick := public.tick_courier_contracts(now());
    if (v_tick->>'cap')::int <> 1 or (v_tick->>'posted')::int > 1
       or (select count(*) from public.courier_contracts c where c.status = 'open' and c.poster_kind <> 'company') > 1
       or exists (select 1 from public.courier_contracts c
                   where c.status = 'open' and c.poster_kind = 'house'
                     and (select l.ducats_delta from public.ledger l join public.events e on e.id = l.ref_event_id
                           where l.player_id = c.poster_id and l.kind = 'CONTRACT_ESCROW' and e.payload->>'contract' = c.id::text) is distinct from -c.reward) then
      raise exception '0483 self-assert FAIL: the houses posted past the cap, or a post is not escrowed to the ducat: %', v_tick;
    end if;
    v_note := v_note || format(', house late failed (8 returned), given up (6 lost), lapsed, houses posted %s of cap 1', v_tick->>'posted');

    -- (g) SIGNED OUT: no company
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{}', true);
    if world.courier_contracts() is distinct from '{"on": true, "company": false}'::jsonb then
      raise exception '0483 self-assert FAIL: lit and signed out, the read is not {"on": true, "company": false}';
    end if;
    raise exception using errcode = 'ZX483', message = 'PROBE_ROLLBACK_0483';
  exception when sqlstate 'ZX483' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0483 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0483' or p.auth_uid in (c_ua, c_ub))
     or exists (select 1 from public.courier_contracts)
     or public.wc('contracts_enabled') is distinct from 'false'::jsonb or public.wc_int('contracts_houses_per') <> 20
     or public.current_player_id() is not null then
    raise exception '0483 self-assert FAIL: the probe left something behind';
  end if;

  -- ── THE JOB (where pg_cron is): every 2 minutes; dark it reads one knob and returns ──
  -- budget: dark 0 rows a run; lit at most 3 posts, 50 lapses and 100 settles a run, about 10 rows a run on a normal day
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('byeharu-voyage:contracts', '*/2 * * * *', 'select public.tick_courier_contracts()');
  else
    raise notice '0483: pg_cron is not installed here (PGlite) - byeharu-voyage:contracts was NOT scheduled. Call public.tick_courier_contracts() by hand.';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0483 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0483 self-assert ok: COURIER CONTRACTS (dark). % hunks once and reversing; grants and volatility unmoved; no other function moved; six doors registered for authenticated alone, every core and the tick server only; one table (RLS, no client grant); 23 knobs (contracts_enabled false). Probe (rolled back): dark the doors refuse, no card, the tick writes nothing; lit %. % ms.',
    (select count(*) from hunks_0483), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
