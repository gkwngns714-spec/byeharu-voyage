-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0122 — A CITY KEEPS A PURSE
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-15: *"i want to economy to be circulative, meaning that there should be a way for these
-- merchants gold to be reduced, weather it is by investing in cities. Then cities should have gold
-- too, and the city must use it for the whole world and so on"*. Decisions (docs/ECONOMY_LOOP.md
-- v3, §0-§2, §11): each city has its OWN purse; a purse never goes below zero (no debt — §12 is
-- LATER and not built); tax is paid ONLY on the profit of a sale, per city, capped at 20 %; no
-- harbour dues; merchants pay full running costs; a city buys only what it can pay for. The Mayor
-- is not built. Investment and the Town Hall's works are 0123.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE BOOKS. public.port_treasury (one purse per harbour, CHECK ducats >= 0), append-only
--     public.treasury_flows (the trade path INSERTs here and locks nothing), public.treasury_daybook
--     (one row per port, game-day, kind). voyages.wages_paid, standing_route_laps.taxes,
--     trade_contracts.escrow.
-- (2) THE MOVERS — the only functions that write a treasury: treasury_post (one INSERT; refuses an
--     outflow the purse does not cover, E_CITY_BROKE), pay_city (credit(-) then post(+)),
--     city_pays (post(-) then credit(+)); readers treasury_balance, city_surplus, city_can_spend,
--     city_sell_outflow, treasury_reserve, city_bid_factor, profit_tax, city_treasury_on.
-- (3) THE TAX RULE. world.tax_rate is re-based: dark it is the column (on turnover, as today); lit
--     it is column × profit_tax_scale, capped at tax_rate_max (0.20) — the one place a Mayor's
--     choice will plug in. Lit, world.quote and world.price price TAX-FREE (one line each), and
--     cmd.do_sell charges public.profit_tax(port, v_profit) on the profit it already realises
--     (0081) — nothing on a loss, a break-even, or cargo whose cost is unknown; nothing on a BUY;
--     no harbour dues. The planner (npc_leg_lines) keeps a leg only if it pays AFTER that tax; the
--     lap closer books `taxes` and nets them; world.market / world.snapshot print the rate in force.
-- (4) THE EMPTY-PURSE RULE (lit). cmd.do_sell shrinks a sale to the whole steps the purse covers
--     and refuses E_CITY_BROKE when it covers none; city_bid_factor lowers the bid linearly from
--     1 at the reserve to city_bid_floor (0.5) at nothing, in world.quote and world.price.
-- (5) THE CHARGES — one hunk each, sliced from the LIVE body: BUY, SELL, PROVISION, REPAIR, HIRE,
--     BUILD, TUITION (public.raise_skill, the 0096 core — the tuition moved there from
--     cmd.study_skill), OFFICER_WAGE (public.sign_officer), the wages of every sea-day
--     (voyages.wages_paid) paid INTO the harbour she makes at arrival. Merchants pay 1.0
--     (npc_cost_mult 0 -> 1; the one reader public.running_cost_mult is untouched).
-- (6) REFOUNDS AND BOUNTIES (lit). npc_tend's refound is paid by the company's home harbour from
--     what it holds above its reserve (partially, or not at all — counted refound_unfunded);
--     tick_contracts posts a request only when the surplus covers it bounty_reserve_mult times and
--     ESCROWS its premium at posting (BOUNTY), returned on expiry (BOUNTY_LAPSED). 0087's rule
--     (only goods the city does not sell) is untouched.
-- (7) public.tick_city — the roll (flows -> daybook + purse), the carry, the reserves, the assert,
--     the receipt. Cron `byeharu-voyage:city` at :37, DEFINED INACTIVE (0078's rule).
-- (8) world.town_hall(port) — the purse and the day's book (0123 restates it whole). Registered,
--     authenticated-only. The client tab is a later PR.
-- (9) public.city_treasury_switch(p_on) — seeds every harbour once (city_seed_days × its mean
--     game-day SELL outflow, never under city_seed_min) and refuses a world born broke. NOT CALLED.
--
-- ── DECISIONS TAKEN HERE (stated, not hidden) ───────────────────────────────────────────────────
-- * DARK BOOKS DO NOT MOVE A PURSE. The market is the purse only once lit; dark, every flow is
--   still written (the seed and the reserve are computed from the dark day's books, §6), but the
--   flow carries `lit = false` and the roll adds to port_treasury.ducats only what was posted lit.
--   Otherwise a dark day's SELLs would roll a purse below zero against its own CHECK. The daybook
--   keeps both figures: `ducats` (the books) and `lit_ducats` (what moved the purse); the roll's
--   assert is ducats = Σ lit_ducats.
-- * NO FOREIGN KEY from treasury_flows.ref_event / player_id: npc_compact deletes a merchant's old
--   events (0097), and a flow that pinned one would break the compactor between two rolls.
-- * LIT OUTFLOWS SERIALISE PER HARBOUR (a transaction-scoped advisory lock in treasury_post), so
--   two sales cannot both pass the "can the purse pay?" test and roll a purse below zero.
--   Inflows lock nothing. Dark, nothing is locked.
-- * city_bid_factor is floor + (1 - floor) × min(1, ducats / reserve): §2.3's prose ("half-way
--   down to the floor at half its reserve") and §2.9's figures (0.75 at half), not §2.3's
--   greatest() shorthand, which disagrees with both. Read live from the rolled purse and reserve;
--   no stored copy.
-- * A refound's ledger AND flow kind stay NPC_REFOUND (the client's word exists); the event gains
--   `port` and `partial` when lit.
-- * npc_invest_above (2.0) is inserted here because the switch's broke test reads it (§6); 0123
--   uses it for investment.
--
-- ── COST ────────────────────────────────────────────────────────────────────────────────────────
-- +1 INSERT per BUY/PROVISION/REPAIR/HIRE/BUILD/TUITION/OFFICER_WAGE, +1-2 per SELL, +1 per
-- arrival at a harbour, one column write per settled sea-day; world.quote / world.price gain one
-- switch read (and, lit, one PK lookup). tick_city: one CTE over at most an hour of flows.
--
-- SUPERSEDES, one hunk each from the LIVE body (asserted exactly once): world.quote, world.price,
-- world.market, world.snapshot, cmd.do_buy, cmd.do_sell, cmd.do_provision, cmd.do_repair,
-- cmd.do_hire, cmd.do_build, public.raise_skill, public.sign_officer, voyage.settle,
-- public.npc_leg_lines, cmd.standing_route_close_lap, world.fleet_trades, public.npc_tend,
-- public.tick_contracts, public.client_rpc_entry_points; world.tax_rate restated whole (a
-- one-line authority). Self-asserts hold AS FOUND; every probe rolls back.
-- ROLLBACK: city_treasury_switch(false) is instant; npc_cost_mult 0 by knob; a forward slice
-- restores the credit( lines (each old text is in this file); cron.unschedule('byeharu-voyage:city').

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('city_treasury_enabled', 'false'::jsonb,
   '0122: THE switch of the city purses (public.city_treasury_on). Off: flows are booked but no purse '
   'moves, prices carry the turnover tax, refounds and bounties mint as before. Lit only through '
   'public.city_treasury_switch(true), which seeds every harbour once.'),
  ('profit_tax_scale', to_jsonb(5),
   '0122: lit, world.tax_rate = ports.tax_rate × this, capped at tax_rate_max: 3 % on turnover becomes 15 % on profit.'),
  ('tax_rate_max', to_jsonb(0.20),
   '0122 (owner, 2026-10-15): the profit tax of any city never exceeds 20 %.'),
  ('treasury_days_kept', to_jsonb(30),
   '0122: game-days of treasury_daybook kept per kind; older rows collapse into one CARRIED row per city.'),
  ('treasury_reserve_days', to_jsonb(3),
   '0122: a city''s reserve = this × its mean game-day SELL outflow. It spends (refounds, bounties) only '
   'above it, and its bid starts to fall below it.'),
  ('city_bid_floor', to_jsonb(0.5),
   '0122: the lowest fraction of the quay''s price a city bids as its purse empties (city_bid_factor).'),
  ('bounty_reserve_mult', to_jsonb(2),
   '0122: a request is posted (and its premium escrowed) only when the city''s surplus covers it this many times.'),
  ('city_seed_days', to_jsonb(10),
   '0122: the one-time seed at city_treasury_switch(true) = this × the harbour''s mean game-day SELL outflow.'),
  ('city_seed_min', to_jsonb(20000),
   '0122: no harbour is seeded with less than this.'),
  ('npc_invest_above', to_jsonb(2.0),
   '0122/0123: a merchant holds up to this × capital before investing (0123). The switch refuses a world '
   'whose money cannot cover this × Σ capital plus Σ reserves (docs/ECONOMY_LOOP.md §6).')
on conflict (key) do nothing;

-- Merchants pay full running costs (owner, round 2). The one reader, public.running_cost_mult, is untouched.
update public.world_config set value = to_jsonb(1) where key = 'npc_cost_mult';

-- ── 2. THE BOOKS ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.port_treasury (
  port_id    uuid primary key references public.ports(id) on delete cascade,
  ducats     bigint not null default 0 check (ducats >= 0),
  rolled_at  timestamptz not null default now(),
  reserve    bigint not null default 0 check (reserve >= 0),
  seeded_at  timestamptz,
  updated_at timestamptz not null default now()
);
comment on table public.port_treasury is
  '0122: a city''s purse, as of its last roll (public.tick_city). The live balance is '
  'public.treasury_balance (this + the lit flows not yet rolled). Never below zero: a city cannot owe.';

create table if not exists public.treasury_flows (
  id         bigint generated always as identity primary key,
  port_id    uuid not null references public.ports(id),
  kind       text not null,
  ducats     bigint not null,
  lit        boolean not null,
  player_id  uuid,
  ref_event  uuid,
  created_at timestamptz not null default now()
);
create index if not exists treasury_flows_port_at on public.treasury_flows (port_id, created_at);
alter table public.treasury_flows set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);
comment on table public.treasury_flows is
  '0122: APPEND-ONLY. Every movement into (+) or out of (-) a city, written by public.treasury_post '
  'alone; rolled hourly into treasury_daybook and port_treasury by public.tick_city, which alone may '
  'delete (byeharu.treasury_roll). `lit` = posted while city_treasury_enabled: only lit flows move a purse.';

create table if not exists public.treasury_daybook (
  port_id    uuid not null references public.ports(id),
  game_day   int  not null,
  kind       text not null,
  ducats     bigint not null,
  lit_ducats bigint not null default 0,
  primary key (port_id, game_day, kind)
);
comment on table public.treasury_daybook is
  '0122: a city''s books, one row per (game-day, kind). `ducats` is everything booked, `lit_ducats` the '
  'part that moved the purse; port_treasury.ducats = Σ lit_ducats (tick_city asserts it). Rows older '
  'than treasury_days_kept collapse into one CARRIED row (game_day 0).';

alter table public.voyages add column if not exists wages_paid bigint not null default 0;
comment on column public.voyages.wages_paid is
  '0122: Σ of the WAGES this voyage''s house actually paid per settled sea-day; paid into the harbour she makes.';
alter table public.standing_route_laps add column if not exists taxes bigint not null default 0;
comment on column public.standing_route_laps.taxes is
  '0122: the profit tax this lap''s sales paid (cmd.do_sell''s `tax`); net is after it.';
alter table public.trade_contracts add column if not exists escrow bigint not null default 0;
comment on column public.trade_contracts.escrow is
  '0122: the premium the city set aside when it posted this request lit (BOUNTY flow); returned as '
  'BOUNTY_LAPSED when it expires. 0 for a request posted dark.';

insert into public.port_treasury (port_id)
select p.id from public.ports p where p.kind = 'HARBOUR'
on conflict (port_id) do nothing;

-- RLS: the purse is public (the port_buildings posture, 0067); the flows and the daybook are the
-- server's. Supabase's default privileges grant ALL on a new table to the client roles: revoked.
alter table public.port_treasury    enable row level security;
alter table public.treasury_flows   enable row level security;
alter table public.treasury_daybook enable row level security;
revoke all on table public.port_treasury, public.treasury_flows, public.treasury_daybook from public, anon, authenticated;
revoke all on sequence public.treasury_flows_id_seq from public, anon, authenticated;
grant select on table public.port_treasury to anon, authenticated;
drop policy if exists port_treasury_read on public.port_treasury;
create policy port_treasury_read on public.port_treasury for select to anon, authenticated using (true);

create or replace function public.tg_treasury_append_only()
returns trigger
language plpgsql
as $$
begin
  -- 0122: the ONE exemption — tick_city's roll deletes what it has rolled, with the GUC set
  -- transaction-locally by that function and nowhere else. Nothing ever UPDATEs a flow.
  if tg_op = 'DELETE' and current_setting('byeharu.treasury_roll', true) = 'on' then
    return old;
  end if;
  raise exception '% is append-only: % is not permitted', tg_table_name, tg_op using errcode = '42501';
end $$;
revoke all on function public.tg_treasury_append_only() from public, anon, authenticated;
drop trigger if exists treasury_flows_append_only on public.treasury_flows;
create trigger treasury_flows_append_only before update or delete on public.treasury_flows
  for each row execute function public.tg_treasury_append_only();

-- ── 3. THE READERS AND THE MOVERS ──────────────────────────────────────────────────────────────
create or replace function public.city_treasury_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select public.wc('city_treasury_enabled') = 'true'::jsonb $$;

create or replace function public.treasury_balance(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0122: THE live balance: the rolled purse plus the LIT flows not yet rolled.
  select coalesce((select t.ducats from public.port_treasury t where t.port_id = p_port), 0)
       + coalesce((select sum(f.ducats) from public.treasury_flows f where f.port_id = p_port and f.lit), 0)::bigint
$$;

create or replace function public.city_surplus(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0122: what a city holds above its reserve — the one figure every spender reads.
  select public.treasury_balance(p_port)
       - coalesce((select t.reserve from public.port_treasury t where t.port_id = p_port), 0)
$$;

create or replace function public.city_can_spend(p_port uuid, p_amount bigint)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select public.city_surplus(p_port) >= p_amount $$;

create or replace function public.city_sell_outflow(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0122: THE mean game-day SELL outflow over the kept window's FULL days (today excluded), per
  -- game-day the city kept any book. The reserve and the seed are both multiples of it.
  select coalesce(round(-sum(d.ducats) filter (where d.kind = 'SELL')
                        / nullif(count(distinct d.game_day), 0)), 0)::bigint
    from public.treasury_daybook d
   where d.port_id = p_port and d.kind <> 'CARRIED'
     and d.game_day >= world.game_day() - public.wc_int('treasury_days_kept')
     and d.game_day < world.game_day()
$$;

create or replace function public.treasury_reserve(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select greatest(0, round(public.wc_num('treasury_reserve_days') * public.city_sell_outflow(p_port)))::bigint $$;

create or replace function public.city_bid_factor(p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0122: THE soft half of the empty-purse rule. 1 dark, 1 at or above the reserve (or with no
  -- reserve yet), falling linearly to city_bid_floor at an empty purse. Rolled figures only.
  select case when not public.city_treasury_on() then 1::numeric
              else coalesce((select case when t.reserve <= 0 then 1::numeric
                                         else public.wc_num('city_bid_floor')
                                              + (1 - public.wc_num('city_bid_floor'))
                                                * least(1::numeric, t.ducats::numeric / t.reserve) end
                               from public.port_treasury t where t.port_id = p_port), 1::numeric) end
$$;

create or replace function public.profit_tax(p_port uuid, p_profit numeric)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0122: THE charge. Tax on the profit of a sale, nothing on a loss, a break-even, or a profit the
  -- game cannot know (null). Dark: nothing (the turnover tax still rides the quote).
  select case when public.city_treasury_on() and p_profit > 0
              then round(p_profit * world.tax_rate(p_port))::bigint else 0::bigint end
$$;

create or replace function public.treasury_post(p_port uuid, p_kind text, p_delta bigint,
                                                p_player uuid default null, p_ref_event uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0122: THE one writer of a city's money. One INSERT. Lit, an outflow is refused when the purse
-- does not cover it (E_CITY_BROKE, have/need) and outflows at one harbour take turns (an advisory
-- lock to the end of the transaction); dark, nothing is refused and nothing is locked. Returns the
-- live balance after (lit) or null (dark).
declare
  v_lit boolean := public.city_treasury_on();
  v_bal bigint;
begin
  if p_port is null or coalesce(p_delta, 0) = 0 then
    return null;
  end if;
  if v_lit and p_delta < 0 then
    perform pg_advisory_xact_lock(hashtextextended('byeharu.treasury:' || p_port::text, 0));
    v_bal := public.treasury_balance(p_port);
    if v_bal + p_delta < 0 then
      perform cmd.refuse('E_CITY_BROKE',
        format('%s cannot pay %s d. today', (select p.name from public.ports p where p.id = p_port), -p_delta),
        cmd.figures(greatest(v_bal, 0), -p_delta, 'ducats'));
    end if;
  end if;
  insert into public.treasury_flows (port_id, kind, ducats, lit, player_id, ref_event)
  values (p_port, p_kind, p_delta, v_lit, p_player, p_ref_event);
  return case when v_lit then coalesce(v_bal, public.treasury_balance(p_port) - p_delta) + p_delta end;
end $$;

create or replace function public.pay_city(p_player uuid, p_port uuid, p_kind text, p_amount bigint,
                                           p_event uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0122: a house pays a city — public.credit(-amount) then treasury_post(+amount). The argument
-- order is credit's with the port inserted after the player and the sign flipped. Returns the
-- house's purse after (credit's answer). A null port (no harbour to pay — a founding-time charge)
-- moves the house alone, as before 0122.
declare
  v_after bigint;
begin
  v_after := public.credit(p_player, p_kind, -p_amount, p_event);
  perform public.treasury_post(p_port, p_kind, p_amount, p_player, p_event);
  return v_after;
end $$;

create or replace function public.city_pays(p_port uuid, p_player uuid, p_kind text, p_amount bigint,
                                            p_event uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0122: a city pays a house — treasury_post(-amount), refused lit when the purse cannot, then
-- public.credit(+amount). Returns the house's purse after.
begin
  perform public.treasury_post(p_port, p_kind, -p_amount, p_player, p_event);
  return public.credit(p_player, p_kind, p_amount, p_event);
end $$;

revoke all on function public.city_treasury_on()                                from public, anon, authenticated;
revoke all on function public.treasury_balance(uuid)                            from public, anon, authenticated;
revoke all on function public.city_surplus(uuid)                                from public, anon, authenticated;
revoke all on function public.city_can_spend(uuid, bigint)                      from public, anon, authenticated;
revoke all on function public.city_sell_outflow(uuid)                           from public, anon, authenticated;
revoke all on function public.treasury_reserve(uuid)                            from public, anon, authenticated;
revoke all on function public.city_bid_factor(uuid)                             from public, anon, authenticated;
revoke all on function public.profit_tax(uuid, numeric)                         from public, anon, authenticated;
revoke all on function public.treasury_post(uuid, text, bigint, uuid, uuid)     from public, anon, authenticated;
revoke all on function public.pay_city(uuid, uuid, text, bigint, uuid)          from public, anon, authenticated;
revoke all on function public.city_pays(uuid, uuid, text, bigint, uuid)         from public, anon, authenticated;

-- ── 4. THE ONE AUTHORITY OF THE RATE, re-based (restated whole: it is one line) ─────────────────
create or replace function world.tax_rate(p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0122: dark, the column (a tax on turnover, riding the quote — as since 0005). Lit, a tax on
  -- PROFIT: the column × profit_tax_scale, never above tax_rate_max (20 %). Each city keeps its own
  -- rate; a Mayor's choice (not built) will plug in HERE and nowhere else.
  select case when public.city_treasury_on()
              then least(coalesce((select tax_rate from public.ports where id = p_port), public.wc_num('tax_rate_default'))
                         * public.wc_num('profit_tax_scale'), public.wc_num('tax_rate_max'))
              else coalesce((select tax_rate from public.ports where id = p_port), public.wc_num('tax_rate_default')) end
$$;

-- ── 5. THE PRE-IMAGE the dark parity assert compares against (taken BEFORE any price slice) ────
create temp table pre_0122 as
select s.port_id, s.good_id,
       to_jsonb(qb) as qb, to_jsonb(qs) as qs, to_jsonb(pr) as pr
  from (select pg.port_id, pg.good_id from public.port_goods pg
          join public.ports po on po.id = pg.port_id and po.kind = 'HARBOUR'
         order by md5(pg.port_id::text || pg.good_id::text) limit 200) s
 cross join lateral world.quote(s.port_id, s.good_id, 35, 'buy', null, null) qb
 cross join lateral world.quote(s.port_id, s.good_id, 35, 'sell', null, null) qs
 cross join lateral world.price(s.port_id, s.good_id) pr;

-- ── 6. THE SLICES — each hunk asserted to occur EXACTLY ONCE in the LIVE body (LF-normalised) ───
create or replace function pg_temp.slice_0122(p_fn text, p_old text, p_new text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  v_n   int  := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
begin
  if v_n <> 1 then
    raise exception '0122 self-assert FAIL: a hunk of % occurs % time(s), not once — the live body is not what this file was cut against: %',
      p_fn, v_n, left(p_old, 120);
  end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- (a) THE PRICE: tax-free lit, the bid times the purse's factor. Dark: byte-for-byte the same figures.
select pg_temp.slice_0122('world.quote(uuid, uuid, numeric, text, numeric, uuid)',
$h$  v_tax    numeric;
  v_left   numeric := p_qty;
$h$,
$h$  v_tax    numeric;
  v_bidf   numeric;   -- 0122: the city's bid factor (1 dark)
  v_left   numeric := p_qty;
$h$);
select pg_temp.slice_0122('world.quote(uuid, uuid, numeric, text, numeric, uuid)',
$h$  v_tax    := world.tax_rate(p_port);
$h$,
$h$  -- 0122: lit, the tax leaves the price — it is charged on a sale's PROFIT in cmd.do_sell.
  v_tax    := case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end;
  v_bidf   := public.city_bid_factor(p_port);
$h$);
select pg_temp.slice_0122('world.quote(uuid, uuid, numeric, text, numeric, uuid)',
$h$      v_unit := round(v_mid * (1 - v_spread / 2) * (1 - v_tax), 2);
$h$,
$h$      v_unit := round(v_mid * (1 - v_spread / 2) * (1 - v_tax) * v_bidf, 2);
$h$);
select pg_temp.slice_0122('world.quote(uuid, uuid, numeric, text, numeric, uuid)',
$h$      v_hag_t := v_hag_t + (v_unit - round(v_mid * (1 - v_nohag / 2) * (1 - v_tax), 2)) * v_n;
$h$,
$h$      v_hag_t := v_hag_t + (v_unit - round(v_mid * (1 - v_nohag / 2) * (1 - v_tax) * v_bidf, 2)) * v_n;
$h$);
select pg_temp.slice_0122('world.price(uuid, uuid)',
$h$  v_tax    := world.tax_rate(p_port);
$h$,
$h$  v_tax    := case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end;   -- 0122
$h$);
select pg_temp.slice_0122('world.price(uuid, uuid)',
$h$  bid    := round(v_mid * (1 - v_spread / 2) * (1 - v_tax), 2);  -- what you receive
$h$,
$h$  bid    := round(v_mid * (1 - v_spread / 2) * (1 - v_tax) * public.city_bid_factor(p_port), 2);  -- what you receive (0122: × the purse's factor)
$h$);

-- (b) THE RATE IN FORCE is what the reads print (dark: the same column value).
select pg_temp.slice_0122('world.market(uuid)',
$h$'tax_rate', p.tax_rate,$h$, $h$'tax_rate', world.tax_rate(p.id),$h$);
select pg_temp.slice_0122('world.snapshot()',
$h$'tax_rate', p.tax_rate,$h$, $h$'tax_rate', world.tax_rate(p.id),$h$);

-- (c) THE SALE: the city pays the whole bid, shrinks the lot to its purse, taxes the profit.
select pg_temp.slice_0122('cmd.do_sell(uuid, jsonb)',
$h$  v_profit  bigint;
begin
$h$,
$h$  v_profit  bigint;
  v_tax     bigint := 0;   -- 0122: the profit tax this sale pays
  v_bal     bigint;        -- 0122: the city's purse, read when lit
  v_need    bigint;
  v_fit     numeric;
begin
$h$);
select pg_temp.slice_0122('cmd.do_sell(uuid, jsonb)',
$h$  -- 0081: what these tuns COST is read before they leave — the average paid per tun, through
$h$,
$h$  -- 0122: THE EMPTY-PURSE RULE (docs/ECONOMY_LOOP.md §2.3). Lit, a city buys only what it can
  -- pay for: the lot shrinks to the whole steps its purse covers (a partial fill — the rest stays
  -- aboard), and a purse that covers none refuses E_CITY_BROKE before anything moves.
  if public.city_treasury_on() then
    v_bal := public.treasury_balance(f.port_id);
    if q.total > v_bal then
      v_need := q.total;
      v_fit  := floor(greatest(v_bal, 0) / nullif(q.avg_price, 0) / public.wc_num('trade_step_tuns'))
                * public.wc_num('trade_step_tuns');
      loop
        exit when coalesce(v_fit, 0) < public.wc_num('trade_step_tuns');
        select * into q from world.quote(f.port_id, g.id, v_fit, 'sell',
                                         nullif((p_args->>'limit'), '')::numeric, p_fleet);
        exit when q.total <= v_bal;
        v_fit := v_fit - public.wc_num('trade_step_tuns');
      end loop;
      if coalesce(v_fit, 0) < public.wc_num('trade_step_tuns') or q.units <= 0 or q.total > v_bal then
        perform cmd.refuse('E_CITY_BROKE',
          format('%s cannot pay for cargo today', (select p.name from public.ports p where p.id = f.port_id)),
          cmd.figures(greatest(v_bal, 0), v_need, 'ducats'));
      end if;
    end if;
  end if;

  -- 0081: what these tuns COST is read before they leave — the average paid per tun, through
$h$);
select pg_temp.slice_0122('cmd.do_sell(uuid, jsonb)',
$h$  v_profit := q.total - v_cost;
$h$,
$h$  v_profit := q.total - v_cost;
  v_tax    := public.profit_tax(f.port_id, v_profit);   -- 0122: on the profit, nothing else
$h$);
select pg_temp.slice_0122('cmd.do_sell(uuid, jsonb)',
$h$  perform public.credit(f.player_id, 'SELL', q.total,
$h$,
$h$  perform public.city_pays(f.port_id, f.player_id, 'SELL', q.total,
$h$);
select pg_temp.slice_0122('cmd.do_sell(uuid, jsonb)',
$h$      'basis', v_basis, 'cost', v_cost, 'profit', v_profit,
      'mid_total', q.mid_total, 'tax_total', q.tax_total, 'spread_total', q.spread_total,
      'haggle_saved', q.haggle_saved)));
$h$,
$h$      'basis', v_basis, 'cost', v_cost, 'profit', v_profit, 'tax', v_tax, 'net', q.total - v_tax,
      'mid_total', q.mid_total, 'tax_total', q.tax_total, 'spread_total', q.spread_total,
      'haggle_saved', q.haggle_saved)));
  -- 0122: the profit tax is its own ledger row and its own flow, paid to the city of the sale.
  if v_tax > 0 then
    perform public.pay_city(f.player_id, f.port_id, 'TAX', v_tax, null);
  end if;
$h$);
select pg_temp.slice_0122('cmd.do_sell(uuid, jsonb)',
$h$                            'basis', v_basis, 'cost', v_cost, 'profit', v_profit,
$h$,
$h$                            'basis', v_basis, 'cost', v_cost, 'profit', v_profit,
                            'tax', v_tax, 'net', q.total - v_tax,
$h$);

-- (d) THE CHARGES — the first line of each existing credit( call, nothing else.
select pg_temp.slice_0122('cmd.do_buy(uuid, jsonb)',
$h$  perform public.credit(f.player_id, 'BUY', -q.total,
$h$,
$h$  perform public.pay_city(f.player_id, f.port_id, 'BUY', q.total,
$h$);
select pg_temp.slice_0122('cmd.do_provision(uuid, jsonb)',
$h$  perform public.credit(f.player_id, 'PROVISION', -v_cost,
$h$,
$h$  perform public.pay_city(f.player_id, f.port_id, 'PROVISION', v_cost,
$h$);
select pg_temp.slice_0122('cmd.do_repair(uuid, jsonb)',
$h$  perform public.credit(f.player_id, 'REPAIR', -v_cost,
$h$,
$h$  perform public.pay_city(f.player_id, f.port_id, 'REPAIR', v_cost,
$h$);
select pg_temp.slice_0122('cmd.do_hire(uuid, jsonb)',
$h$  perform public.credit(f.player_id, 'HIRE', -v_cost,
$h$,
$h$  perform public.pay_city(f.player_id, f.port_id, 'HIRE', v_cost,
$h$);
select pg_temp.slice_0122('cmd.do_build(uuid, jsonb)',
$h$  perform public.credit(f.player_id, 'BUILD', -h.ducats,
$h$,
$h$  perform public.pay_city(f.player_id, f.port_id, 'BUILD', h.ducats,
$h$);
select pg_temp.slice_0122('public.raise_skill(uuid, text, text)',
$h$  perform public.credit(
    v_player,
    'TUITION',
    -v_cost,
$h$,
$h$  perform public.pay_city(   -- 0122: the academy's harbour is paid
    v_player, (select p.id from public.ports p where p.code = v_port.code),
    'TUITION',
    v_cost,
$h$);
select pg_temp.slice_0122('public.sign_officer(uuid, text, uuid)',
$h$  perform public.credit(
    v_player,
    'OFFICER_WAGE',
    -v_off.wage_ducats,
$h$,
$h$  perform public.pay_city(   -- 0122: the fleet's harbour, else the officer's home port
    v_player, coalesce((select f2.port_id from public.fleets f2 where f2.id = p_fleet), v_off.home_port_id),
    'OFFICER_WAGE',
    v_off.wage_ducats,
$h$);

-- (e) THE WAGES: what the house paid each sea-day is counted on the voyage, and paid INTO the
--     harbour she makes. No dues.
select pg_temp.slice_0122('voyage.settle(uuid, timestamptz)',
$h$  v_wages   bigint;
$h$,
$h$  v_wages   bigint;
  v_paid    bigint;   -- 0122: what the house actually paid this sea-day
  v_report  uuid;     -- 0122: the VOYAGE_REPORT the wages flow references
$h$);
select pg_temp.slice_0122('voyage.settle(uuid, timestamptz)',
$h$      perform public.credit(f.player_id, 'WAGES',
        -least(v_wages, (select ducats from public.players where id = f.player_id)));
$h$,
$h$      v_paid := least(v_wages, (select ducats from public.players where id = f.player_id));
      perform public.credit(f.player_id, 'WAGES', -v_paid);
      update public.voyages set wages_paid = wages_paid + v_paid where id = v.id;   -- 0122
$h$);
select pg_temp.slice_0122('voyage.settle(uuid, timestamptz)',
$h$    perform public.emit_event(f.player_id, 'VOYAGE_REPORT', jsonb_build_object(
$h$,
$h$    v_report := public.emit_event(f.player_id, 'VOYAGE_REPORT', jsonb_build_object(
$h$);
select pg_temp.slice_0122('voyage.settle(uuid, timestamptz)',
$h$                  from public.voyage_events ve where ve.voyage_id = v.id)));
    -- 0034 STANDING ORDER$h$,
$h$                  from public.voyage_events ve where ve.voyage_id = v.id)));
    -- 0122: the leg's wages reach the HARBOUR she made (a sea place or open water has no purse).
    if v.wages_paid > 0
       and exists (select 1 from public.ports hp where hp.id = v.dest_port_id and hp.kind = 'HARBOUR') then
      perform public.treasury_post(v.dest_port_id, 'WAGES', v.wages_paid, f.player_id, v_report);
    end if;
    -- 0034 STANDING ORDER$h$);

-- (f) THE PLANNER keeps a leg only if it pays AFTER the profit tax (0 dark: unchanged).
select pg_temp.slice_0122('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)',
$h$  v_profit  numeric := 0;
$h$,
$h$  v_profit  numeric := 0;
  v_net     numeric;   -- 0122: a parcel's margin after the sink's profit tax
$h$);
select pg_temp.slice_0122('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)',
$h$      continue when q_sell.total - q_buy.total - v_wages <= 0
                 or (q_sell.total - q_buy.total) * 100 < v_minret * q_buy.total;
$h$,
$h$      -- 0122: the parcel's cost IS q_buy.total, so this is exactly the profit do_sell will tax.
      v_net := (q_sell.total - q_buy.total) - public.profit_tax(p_to, q_sell.total - q_buy.total);
      continue when v_net - v_wages <= 0
                 or v_net * 100 < v_minret * q_buy.total;
$h$);
select pg_temp.slice_0122('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)',
$h$      v_profit := v_profit + (q_sell.total - q_buy.total);
$h$,
$h$      v_profit := v_profit + v_net;   -- 0122: after tax
$h$);

-- (g) THE LAP books its taxes and nets them; the read prints them beside the wages.
select pg_temp.slice_0122('cmd.standing_route_close_lap(uuid, timestamptz)',
$h$  v_in     bigint;   -- 0116: the previous closed lap's v_out
$h$,
$h$  v_in     bigint;   -- 0116: the previous closed lap's v_out
  v_taxes  bigint;   -- 0122: the profit tax her sales paid
$h$);
select pg_temp.slice_0122('cmd.standing_route_close_lap(uuid, timestamptz)',
$h$         coalesce(round(sum((o.result->>'cost')::numeric)  filter (where o.verb = 'REPAIR')), 0)
    into v_sold, v_bought, v_supp, v_rep
$h$,
$h$         coalesce(round(sum((o.result->>'cost')::numeric)  filter (where o.verb = 'REPAIR')), 0),
         coalesce(round(sum((o.result->>'tax')::numeric)   filter (where o.verb = 'SELL')), 0)   -- 0122
    into v_sold, v_bought, v_supp, v_rep, v_taxes
$h$);
select pg_temp.slice_0122('cmd.standing_route_close_lap(uuid, timestamptz)',
$h$         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in,
$h$,
$h$         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in - v_taxes,
         taxes = v_taxes,   -- 0122
$h$);
select pg_temp.slice_0122('world.fleet_trades(uuid)',
$h$           'wages', x.wages, 'stock_in', x.stock_in,$h$,
$h$           'wages', x.wages, 'taxes', x.taxes, 'stock_in', x.stock_in,$h$);
select pg_temp.slice_0122('world.fleet_trades(uuid)',
$h$           'wages', coalesce((select sum(w.wages) from w), 0),
$h$,
$h$           'wages', coalesce((select sum(w.wages) from w), 0),
           'taxes', coalesce((select sum(w.taxes) from w), 0),   -- 0122
$h$);

-- (h) THE REFOUND is paid by the company's home harbour, from what it holds above its reserve.
select pg_temp.slice_0122('public.npc_tend(timestamptz, uuid)',
$h$  v_deferred int := 0;                                          -- 0114
$h$,
$h$  v_deferred int := 0;                                          -- 0114
  v_can      bigint;                                            -- 0122
  v_unfunded int := 0;                                          -- 0122
$h$);
select pg_temp.slice_0122('public.npc_tend(timestamptz, uuid)',
$h$    for hh in select h.player_id, h.capital, pl.ducats, pl.company_name
$h$,
$h$    for hh in select h.player_id, h.capital, pl.ducats, pl.company_name, h.home_port_id
$h$);
select pg_temp.slice_0122('public.npc_tend(timestamptz, uuid)',
$h$        perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
          public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
            'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
        v_refound := v_refound + 1;
$h$,
$h$        if not public.city_treasury_on() then
          perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
            public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
              'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
          v_refound := v_refound + 1;
        else
          -- 0122: lit, the HOME HARBOUR pays, from its surplus — partially, or not at all. A merchant
          -- whose home cannot pay sails on at her purse floor until it earns (never parked, 0115).
          v_can := greatest(0, least(hh.capital - hh.ducats, public.city_surplus(hh.home_port_id)));
          if v_can > 0 then
            perform public.city_pays(hh.home_port_id, hh.player_id, 'NPC_REFOUND', v_can,
              public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
                'company', hh.company_name, 'amount', v_can, 'week', coalesce(v_week, 0) + 1,
                'port', (select p.code from public.ports p where p.id = hh.home_port_id),
                'partial', v_can < hh.capital - hh.ducats)));
            v_refound := v_refound + 1;
          else
            v_unfunded := v_unfunded + 1;
          end if;
        end if;
$h$);
select pg_temp.slice_0122('public.npc_tend(timestamptz, uuid)',
$h$'refounded', v_refound,$h$,
$h$'refounded', v_refound, 'refound_unfunded', v_unfunded,$h$);

-- (i) THE BOARD: lit, a request is posted only when the surplus covers it, and its premium is
--     escrowed at posting and returned on expiry. 0087's draw (goods the city does not sell) stays.
select pg_temp.slice_0122('public.tick_contracts(uuid, timestamptz)',
$h$  v_posted   int := 0;
$h$,
$h$  v_posted   int := 0;
  v_lapsed   bigint;                                           -- 0122
  v_open     boolean;                                          -- 0122
$h$);
select pg_temp.slice_0122('public.tick_contracts(uuid, timestamptz)',
$h$  update public.trade_contracts
     set status = 'expired'
   where port_id = p_port and status = 'open' and expires_day <= v_day;
$h$,
$h$  with x as (
    update public.trade_contracts
       set status = 'expired'
     where port_id = p_port and status = 'open' and expires_day <= v_day
    returning escrow)
  select coalesce(sum(x.escrow), 0) into v_lapsed from x;
  -- 0122: what the city set aside for a request nobody delivered comes back to it.
  if v_lapsed > 0 then
    perform public.treasury_post(p_port, 'BOUNTY_LAPSED', v_lapsed, null, null);
  end if;
$h$);
select pg_temp.slice_0122('public.tick_contracts(uuid, timestamptz)',
$h$      v_per_unit := round(v_mid * v_draw.premium_pct, 2);
$h$,
$h$      v_per_unit := round(v_mid * v_draw.premium_pct, 2);
      -- 0122: lit, an OPEN request is posted only when the city's surplus covers its premium
      -- bounty_reserve_mult times; a later read back-fills it when the city can.
      v_open := v_d + v_deadline > v_day;
      continue when public.city_treasury_on() and v_open
        and not public.city_can_spend(p_port, round(v_per_unit * v_draw.qty)::bigint * public.wc_int('bounty_reserve_mult'));
$h$);
select pg_temp.slice_0122('public.tick_contracts(uuid, timestamptz)',
$h$         status)
$h$,
$h$         status, escrow)
$h$);
select pg_temp.slice_0122('public.tick_contracts(uuid, timestamptz)',
$h$         case when v_d + v_deadline <= v_day then 'expired' else 'open' end)
      on conflict (port_id, posted_day, seq) do nothing;
      if found then v_posted := v_posted + 1; end if;
$h$,
$h$         case when v_d + v_deadline <= v_day then 'expired' else 'open' end,
         case when public.city_treasury_on() and v_open then round(v_per_unit * v_draw.qty)::bigint else 0 end)
      on conflict (port_id, posted_day, seq) do nothing;
      if found then
        v_posted := v_posted + 1;
        -- 0122: ESCROW AT POSTING — the premium leaves the city now; cmd.run_fulfil's credit(PREMIUM)
        -- pays it out of nothing new.
        if public.city_treasury_on() and v_open then
          perform public.treasury_post(p_port, 'BOUNTY', -round(v_per_unit * v_draw.qty)::bigint, null, null);
        end if;
      end if;
$h$);

-- ── 7. THE ONE HOURLY JOB ───────────────────────────────────────────────────────────────────────
create or replace function public.tick_city(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0122: docs/ECONOMY_LOOP.md §4 steps 1 ROLL, 2 CARRY, 3 STATE, 7 ASSERT, 8 RECEIPT (0123 adds
-- 4-6). Never waits: lock_timeout 2 s, the flows it rolls are taken SKIP LOCKED. ROLL and ASSERT
-- abort the hour; CARRY and STATE report an error in the receipt and roll back alone.
declare
  v_t0      timestamptz := clock_timestamp();
  v_t       timestamptz;
  v_ms      jsonb := '{}'::jsonb;
  v_err     jsonb := '{}'::jsonb;
  v_today   int := world.game_day(p_now);
  v_rolled  int := 0;
  v_carried int := 0;
  v_ports   int := 0;
  v_thin    int := 0;
  v_bad     int;
  v_world   bigint;
begin
  perform set_config('lock_timeout', '2s', true);

  -- 1. ROLL: every flow up to p_now into the daybook (all of it) and the purse (the lit part).
  v_t := clock_timestamp();
  perform set_config('byeharu.treasury_roll', 'on', true);
  with f as (
    select tf.id, tf.port_id, tf.kind, tf.ducats, tf.lit, world.game_day(tf.created_at) as gd
      from public.treasury_flows tf where tf.created_at <= p_now
       for update skip locked
  ), d as (
    insert into public.treasury_daybook (port_id, game_day, kind, ducats, lit_ducats)
    select f.port_id, f.gd, f.kind, sum(f.ducats), coalesce(sum(f.ducats) filter (where f.lit), 0)
      from f group by 1, 2, 3
    on conflict (port_id, game_day, kind) do update
       set ducats = public.treasury_daybook.ducats + excluded.ducats,
           lit_ducats = public.treasury_daybook.lit_ducats + excluded.lit_ducats
    returning 1
  ), b as (
    insert into public.port_treasury (port_id, ducats, rolled_at)
    select f.port_id, coalesce(sum(f.ducats) filter (where f.lit), 0), p_now from f group by 1
    on conflict (port_id) do update
       set ducats = public.port_treasury.ducats + excluded.ducats, rolled_at = p_now, updated_at = now()
    returning 1
  ), x as (
    delete from public.treasury_flows t using f where t.id = f.id returning 1
  )
  select count(*) into v_rolled from x;
  perform set_config('byeharu.treasury_roll', 'off', true);
  v_ms := v_ms || jsonb_build_object('roll', round(extract(epoch from clock_timestamp() - v_t) * 1000));

  -- 2. CARRY: books older than the window collapse into one CARRIED row per city (game_day 0).
  v_t := clock_timestamp();
  begin
    with old as (
      delete from public.treasury_daybook d
       where d.game_day < v_today - public.wc_int('treasury_days_kept') and d.kind <> 'CARRIED'
      returning d.port_id, d.ducats, d.lit_ducats
    )
    insert into public.treasury_daybook (port_id, game_day, kind, ducats, lit_ducats)
    select o.port_id, 0, 'CARRIED', sum(o.ducats), sum(o.lit_ducats) from old o group by 1
    on conflict (port_id, game_day, kind) do update
       set ducats = public.treasury_daybook.ducats + excluded.ducats,
           lit_ducats = public.treasury_daybook.lit_ducats + excluded.lit_ducats;
    get diagnostics v_carried = row_count;
  exception when others then
    v_err := v_err || jsonb_build_object('carry', sqlerrm);
  end;
  v_ms := v_ms || jsonb_build_object('carry', round(extract(epoch from clock_timestamp() - v_t) * 1000));

  -- 3. STATE: every harbour has a purse row, and its reserve is today's.
  v_t := clock_timestamp();
  begin
    insert into public.port_treasury (port_id)
    select p.id from public.ports p where p.kind = 'HARBOUR'
    on conflict (port_id) do nothing;
    update public.port_treasury t
       set reserve = public.treasury_reserve(t.port_id), rolled_at = p_now, updated_at = now();
    get diagnostics v_ports = row_count;
    select count(*) into v_thin from public.port_treasury t where public.city_bid_factor(t.port_id) < 1;
  exception when others then
    v_err := v_err || jsonb_build_object('state', sqlerrm);
  end;
  v_ms := v_ms || jsonb_build_object('state', round(extract(epoch from clock_timestamp() - v_t) * 1000));

  -- 7. ASSERT: every purse equals its books; none below zero (the CHECK holds it too).
  select count(*) into v_bad
    from public.port_treasury t
   where t.ducats < 0
      or t.ducats <> coalesce((select sum(d.lit_ducats) from public.treasury_daybook d where d.port_id = t.port_id), 0);
  if v_bad > 0 then
    raise exception 'TICK_CITY FAIL: % city purse(s) disagree with their daybook or are below zero', v_bad
      using errcode = 'P0001';
  end if;

  -- 8. RECEIPT
  select coalesce((select sum(p.ducats) from public.players p), 0)
       + coalesce((select sum(t.ducats) from public.port_treasury t), 0)
       + coalesce((select sum(f.ducats) from public.treasury_flows f where f.lit), 0)
    into v_world;
  return jsonb_build_object('enabled', public.city_treasury_on(), 'flows_rolled', v_rolled,
                            'carried', v_carried, 'reserves', v_ports, 'thin', v_thin,
                            'world_ducats', v_world, 'errors', v_err,
                            'ms', v_ms || jsonb_build_object('total', round(extract(epoch from clock_timestamp() - v_t0) * 1000)),
                            'at', p_now);
end $$;
comment on function public.tick_city(timestamptz) is
  '0122: the city job — rolls the flows into the books and the purses, carries old books, sets the '
  'reserves, asserts every purse equals its books. Cron byeharu-voyage:city at :37. Server-only.';
revoke all on function public.tick_city(timestamptz) from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0122: pg_cron is not installed here, so byeharu-voyage:city was NOT scheduled — as expected under PGlite. Call public.tick_city() by hand.';
    return;
  end if;
  perform cron.schedule('byeharu-voyage:city', '37 * * * *', 'select public.tick_city()');
  -- 0078: DEFINED, NOT RUNNING. public.wind_the_clock() starts it with the others.
  perform cron.alter_job(jobid, active := false) from cron.job where jobname = 'byeharu-voyage:city';
  raise notice '0122: pg_cron present — byeharu-voyage:city on "37 * * * *", SCHEDULED BUT INACTIVE until wind_the_clock().';
end $$;

-- ── 8. THE SWITCH AND THE SEED (not called by this file) ───────────────────────────────────────
create or replace function public.city_treasury_switch(p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0122: docs/ECONOMY_LOOP.md §2.7 / §6. false: the flag only — books keep posting; prices, tax,
-- refounds and bounties fall back to the dark rules at once. true: every harbour has a purse,
-- reserves are today's, each harbour is SEEDED ONCE (the one stated faucet) unless a SEED was ever
-- posted, and the world must not be born broke — or nothing happens and the figures say why.
declare
  r        record;
  v_seeded int := 0;
  v_sum    bigint := 0;
  v_have   numeric;
  v_need   numeric;
begin
  if not coalesce(p_on, false) then
    update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
    return jsonb_build_object('enabled', false);
  end if;

  insert into public.port_treasury (port_id)
  select p.id from public.ports p where p.kind = 'HARBOUR'
  on conflict (port_id) do nothing;
  update public.port_treasury t set reserve = public.treasury_reserve(t.port_id), updated_at = now();
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';

  if not exists (select 1 from public.treasury_flows where kind = 'SEED')
     and not exists (select 1 from public.treasury_daybook where kind = 'SEED') then
    for r in select p.id,
                    greatest(public.wc_int('city_seed_min'),
                             round(public.wc_num('city_seed_days') * public.city_sell_outflow(p.id)))::bigint as s
               from public.ports p where p.kind = 'HARBOUR' order by p.code loop
      perform public.treasury_post(r.id, 'SEED', r.s, null, null);
      v_seeded := v_seeded + 1;
      v_sum := v_sum + r.s;
    end loop;
    update public.port_treasury t set seeded_at = now()
     where t.port_id in (select p.id from public.ports p where p.kind = 'HARBOUR');
  end if;

  -- THE WORLD MUST NOT BE BORN BROKE (§6): merchants keep up to npc_invest_above × capital before
  -- they give any back, and every city keeps its reserve.
  select coalesce((select sum(p.ducats) from public.players p), 0)
       + coalesce((select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR'), 0)
    into v_have;
  select public.wc_num('npc_invest_above') * coalesce((select sum(h.capital) from public.npc_houses h), 0)
       + coalesce((select sum(t.reserve) from public.port_treasury t), 0)
    into v_need;
  if v_have < v_need then
    perform cmd.refuse('E_WORLD_BROKE',
      'the world''s money cannot carry the merchants and the cities'' reserves — raise city_seed_days and call again',
      cmd.figures(v_have, v_need, 'ducats'));
  end if;

  return jsonb_build_object('enabled', public.city_treasury_on(), 'seeded', v_seeded, 'seed_total', v_sum,
                            'world_ducats', v_have, 'world_need', v_need);
end $$;
comment on function public.city_treasury_switch(boolean) is
  '0122: THE switch of the city purses. Seeds once; refuses a broke world. Server-only — the owner runs it.';
revoke all on function public.city_treasury_switch(boolean) from public, anon, authenticated;

-- ── 9. THE READ: the Town Hall's purse and the day's book ──────────────────────────────────────
create or replace function world.town_hall(p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0122: one harbour's purse and its last FULL game-day's book, by kind. Reads the rolled state
-- and the daybook; writes nothing. 0123 restates it whole with the works and the investors.
declare
  p     public.ports%rowtype;
  t     public.port_treasury%rowtype;
  v_day int := world.game_day() - 1;
begin
  select x.* into p from public.ports x where x.id = p_port;
  if p.id is null or p.kind <> 'HARBOUR' then
    raise exception 'E_NOT_FOUND: there is no such harbour' using errcode = 'P0001';
  end if;
  select x.* into t from public.port_treasury x where x.port_id = p_port;
  return jsonb_build_object(
    'port', p.code, 'enabled', public.city_treasury_on(),
    'purse', jsonb_build_object(
       'ducats', public.treasury_balance(p_port), 'reserve', coalesce(t.reserve, 0),
       'bid_factor', round(public.city_bid_factor(p_port), 4),
       'rolled_at', t.rolled_at, 'seeded_at', t.seeded_at,
       'tax_rate', world.tax_rate(p_port)),
    'day', jsonb_build_object(
       'game_day', v_day,
       'in',  coalesce((select jsonb_object_agg(d.kind, d.ducats order by d.kind) from public.treasury_daybook d
                         where d.port_id = p_port and d.game_day = v_day and d.ducats > 0), '{}'::jsonb),
       'out', coalesce((select jsonb_object_agg(d.kind, -d.ducats order by d.kind) from public.treasury_daybook d
                         where d.port_id = p_port and d.game_day = v_day and d.ducats < 0), '{}'::jsonb)));
end $$;
comment on function world.town_hall(uuid) is
  '0122: one harbour''s purse (balance, reserve, bid factor, profit-tax rate in force) and its last '
  'full game-day''s money in and out by kind. Read at a tap. Authenticated only.';
revoke all on function world.town_hall(uuid) from public, anon;
grant execute on function world.town_hall(uuid) to authenticated;

select pg_temp.slice_0122('public.client_rpc_entry_points()',
$h$      ('world',       'fleet_trades',          'uuid'),
$h$,
$h$      ('world',       'fleet_trades',          'uuid'),
      -- 0122: one harbour's purse and day's book (the Town Hall, docs/ECONOMY_LOOP.md §5).
      ('world',       'town_hall',             'uuid'),
$h$);

-- ── 10. SELF-ASSERT ────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_was_on   boolean := public.city_treasury_on();
  v_npc_on   jsonb   := public.wc('npc_traders_enabled');
  v_rt_on    jsonb   := public.wc('standing_routes_enabled');
  v_step     numeric := public.wc_num('trade_step_tuns');
  v_n        int;
  v_fn       text;
  v_fleet    uuid;
  v_player   uuid;
  v_port     uuid;
  v_good     uuid;
  v_code     text;
  v_purse    bigint;
  v_r        jsonb;
  v_q        record;
  v_bal      bigint;
  v_tax      bigint;
  v_fund     bigint;
  v_cargo    numeric;
  v_ev       jsonb;
  v_x        bigint;
  v_y        bigint;
  v_house    record;
  v_exp      bigint;
  v_route    uuid;
  v_lap      public.standing_route_laps%rowtype;
  v_ms       numeric;
  v_detail   text;
  v_notes    text := '';
  v_city     jsonb;
  v_posted   int;
begin
  -- (a) THE WALL: movers server-only, the read authenticated-only and registered, no client writes.
  foreach v_fn in array array[
    'public.city_treasury_on()', 'public.treasury_balance(uuid)', 'public.city_surplus(uuid)',
    'public.city_can_spend(uuid, bigint)', 'public.city_sell_outflow(uuid)', 'public.treasury_reserve(uuid)',
    'public.city_bid_factor(uuid)', 'public.profit_tax(uuid, numeric)',
    'public.treasury_post(uuid, text, bigint, uuid, uuid)', 'public.pay_city(uuid, uuid, text, bigint, uuid)',
    'public.city_pays(uuid, uuid, text, bigint, uuid)', 'public.tick_city(timestamptz)',
    'public.city_treasury_switch(boolean)'] loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0122 self-assert FAIL: % is client-callable', v_fn;
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'world.town_hall(uuid)', 'execute')
     or has_function_privilege('anon', 'world.town_hall(uuid)', 'execute') then
    raise exception '0122 self-assert FAIL: world.town_hall is not exactly authenticated-only';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e
                  where e.schema_name = 'world' and e.function_name = 'town_hall' and e.fn is not null) then
    raise exception '0122 self-assert FAIL: world.town_hall is not a registered entry point';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0122 self-assert FAIL: a client write grant exists: %', (select jsonb_agg(to_jsonb(g)) from public.client_write_grants() g);
  end if;
  if has_table_privilege('anon', 'public.treasury_flows', 'select')
     or has_table_privilege('authenticated', 'public.treasury_daybook', 'select')
     or not has_table_privilege('anon', 'public.port_treasury', 'select') then
    raise exception '0122 self-assert FAIL: the books are readable by a client, or the purse is not';
  end if;
  -- the charges are gone from credit( in every body that was cut (one authority: pay_city / city_pays)
  if exists (select 1 from pg_proc p where p.prosrc ~ $re$public\.credit\(f\.player_id, '(BUY|SELL|PROVISION|REPAIR|HIRE|BUILD)'$re$)
     or exists (select 1 from pg_proc p where p.prosrc like '%''tax_rate'', p.tax_rate%') then
    raise exception '0122 self-assert FAIL: a cut body still charges through credit( or prints the raw column';
  end if;
  if public.running_cost_mult((select h.player_id from public.npc_houses h order by h.roster_ord limit 1)) is distinct from 1 then
    raise exception '0122 self-assert FAIL: a merchant does not pay full running costs';
  end if;
  if v_was_on then
    raise exception '0122 self-assert FAIL: the city purses are lit at deploy; this file ships them dark';
  end if;

  -- (b) THE SHAPE: a purse cannot go below zero; the flows are append-only but to the roll.
  begin
    update public.port_treasury set ducats = -1 where port_id = (select port_id from public.port_treasury limit 1);
    raise exception '0122 self-assert FAIL: a purse went below zero';
  exception when check_violation then null;
  end;
  begin
    insert into public.treasury_flows (port_id, kind, ducats, lit) values ((select port_id from public.port_treasury limit 1), 'PROBE', 1, false);
    begin
      update public.treasury_flows set ducats = 2 where kind = 'PROBE';
      raise exception '0122 self-assert FAIL: a flow was updated';
    exception when insufficient_privilege then null;
    end;
    begin
      delete from public.treasury_flows where kind = 'PROBE';
      raise exception '0122 self-assert FAIL: a flow was deleted without the roll';
    exception when insufficient_privilege then null;
    end;
    perform set_config('byeharu.treasury_roll', 'on', true);
    delete from public.treasury_flows where kind = 'PROBE';
    get diagnostics v_n = row_count;
    perform set_config('byeharu.treasury_roll', 'off', true);
    if v_n <> 1 then raise exception '0122 self-assert FAIL: the roll could not delete a flow'; end if;
    raise exception 'ROLLBACK_0122';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0122' then raise; end if;
  end;

  -- (c) DARK PARITY: quote and price equal their pre-images on the 200 pairs; the rate is the column.
  select count(*) into v_n from pre_0122 s
   cross join lateral world.quote(s.port_id, s.good_id, 35, 'buy', null, null) qb
   cross join lateral world.quote(s.port_id, s.good_id, 35, 'sell', null, null) qs
   cross join lateral world.price(s.port_id, s.good_id) pr
   where to_jsonb(qb) <> s.qb or to_jsonb(qs) <> s.qs or to_jsonb(pr) <> s.pr;
  if v_n <> 0 or (select count(*) from pre_0122) < 50 then
    raise exception '0122 self-assert FAIL: dark, % of % quotes/prices moved', v_n, (select count(*) from pre_0122);
  end if;
  if exists (select 1 from public.ports p where p.kind = 'HARBOUR'
              and world.tax_rate(p.id) is distinct from coalesce(p.tax_rate, public.wc_num('tax_rate_default'))) then
    raise exception '0122 self-assert FAIL: dark, world.tax_rate is not the column';
  end if;

  -- THE PROBE FLEET: a fleet docked at a harbour (a merchant first), and a good its quay offers.
  select f.id, f.player_id, f.port_id, g.id, g.code into v_fleet, v_player, v_port, v_good, v_code
    from (select f0.* from public.fleets f0
            join public.players p0 on p0.id = f0.player_id
            join public.ports po on po.id = f0.port_id and po.kind = 'HARBOUR'
           where f0.status = 'DOCKED'
           order by p0.is_npc desc, f0.id limit 40) f
    cross join lateral (
      select g1.id, g1.code from public.port_goods pg
        join public.goods g1 on g1.id = pg.good_id
        join public.ports pr on pr.id = pg.port_id
       where pg.port_id = f.port_id and pg.stock >= 40 and public.port_offers(f.port_id, g1.id)
         and not public.culture_refuses(pr.culture, g1.culture_mask)
         and world.daily_cap_remaining(f.player_id, f.port_id, g1.id) >= 120
       order by g1.bulk, g1.code limit 1) g
   limit 1;
  if v_fleet is null then
    raise exception '0122 self-assert FAIL: no docked fleet and offered good to probe';
  end if;

  -- (d)-(h) THE PROBE WORLD (rolled back whole).
  begin
    perform public.credit(v_player, 'PROBE_0122', 50000000);
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb, water_t = 0, food_t = 0
     where fleet_id = v_fleet;

    -- (d) DARK: a BUY and a SELL move the purse as before, flows are booked (lit = false), no tax.
    select ducats into v_purse from public.players where id = v_player;
    v_r := cmd.do_buy(v_fleet, jsonb_build_object('good', v_good, 'qty', 10));
    if (select ducats from public.players where id = v_player) <> v_purse - (v_r->>'total')::bigint
       or not exists (select 1 from public.treasury_flows tf where tf.port_id = v_port and tf.kind = 'BUY'
                       and tf.ducats = (v_r->>'total')::bigint and not tf.lit and tf.player_id = v_player) then
      raise exception '0122 self-assert FAIL: dark BUY % did not book a BUY flow or moved the purse wrongly', v_r;
    end if;
    select ducats into v_purse from public.players where id = v_player;
    v_r := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 10));
    select e.payload into v_ev from public.events e where e.player_id = v_player and e.kind = 'SOLD'
     order by e.created_at desc, e.id limit 1;
    if (select ducats from public.players where id = v_player) <> v_purse + (v_r->>'total')::bigint
       or (v_r->>'tax')::bigint <> 0 or (v_r->>'net')::bigint <> (v_r->>'total')::bigint
       or (v_ev->>'tax')::bigint <> 0 or (v_ev->>'net')::bigint <> (v_r->>'total')::bigint
       or not exists (select 1 from public.treasury_flows tf where tf.port_id = v_port and tf.kind = 'SELL'
                       and tf.ducats = -(v_r->>'total')::bigint and not tf.lit) then
      raise exception '0122 self-assert FAIL: dark SELL % (event %) is not the old sale plus tax 0 / net', v_r, v_ev;
    end if;
    if public.treasury_balance(v_port) <> coalesce((select ducats from public.port_treasury where port_id = v_port), 0) then
      raise exception '0122 self-assert FAIL: dark flows moved a purse';
    end if;

    -- LIT.
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    if world.tax_rate(v_port) <> least(coalesce((select tax_rate from public.ports where id = v_port), public.wc_num('tax_rate_default')) * 5, 0.20) then
      raise exception '0122 self-assert FAIL: lit, world.tax_rate(%) = % is not the column × 5 capped at 20 %%', v_port, world.tax_rate(v_port);
    end if;
    select * into v_q from world.quote(v_port, v_good, v_step, 'buy', null, null);
    if v_q.tax_total <> 0
       or v_q.avg_price <> round(world.mid_price(v_port, v_good, (select stock from public.port_goods where port_id = v_port and good_id = v_good))
                                 * (1 + world.spread(v_port) / 2), 2) then
      raise exception '0122 self-assert FAIL: lit, the ask still carries a tax: %', to_jsonb(v_q);
    end if;

    -- (e) THE BID FACTOR: 1 with no reserve, 0.5 empty, 0.75 at half, 1 at the reserve; 1 dark.
    update public.port_treasury set reserve = 1000, ducats = 0 where port_id = v_port;
    if public.city_bid_factor(v_port) <> 0.5 then raise exception '0122 self-assert FAIL: empty bid factor %', public.city_bid_factor(v_port); end if;
    update public.port_treasury set ducats = 500 where port_id = v_port;
    if public.city_bid_factor(v_port) <> 0.75 then raise exception '0122 self-assert FAIL: half bid factor %', public.city_bid_factor(v_port); end if;
    update public.port_treasury set ducats = 2000 where port_id = v_port;
    if public.city_bid_factor(v_port) <> 1 then raise exception '0122 self-assert FAIL: full bid factor %', public.city_bid_factor(v_port); end if;
    update public.port_treasury set ducats = 0, reserve = 0 where port_id = v_port;
    if public.city_bid_factor(v_port) <> 1 then raise exception '0122 self-assert FAIL: no-reserve bid factor'; end if;

    -- (f) THE EMPTY PURSE: nothing in it refuses and moves nothing; a short purse fills part.
    perform public.fleet_load(v_fleet, v_code, 60, 1);
    select ducats into v_purse from public.players where id = v_player;
    begin
      perform cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 30));
      raise exception '0122 self-assert FAIL: an empty city bought cargo';
    exception when others then
      if sqlerrm not like 'E_CITY_BROKE%' then raise; end if;
      get stacked diagnostics v_detail = pg_exception_detail;
    end;
    if public.fleet_cargo_qty(v_fleet, v_code) <> 60 or (select ducats from public.players where id = v_player) <> v_purse
       or v_detail not like '%have%need%' then
      raise exception '0122 self-assert FAIL: a refused sale moved something, or the refusal carries no figures (%)', v_detail;
    end if;
    select * into v_q from world.quote(v_port, v_good, v_step, 'sell', null, null);
    v_fund := floor(v_q.total * 1.5);
    perform public.treasury_post(v_port, 'SEED', v_fund);
    v_r := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 30));
    if (v_r->>'qty')::numeric >= 30 or (v_r->>'qty')::numeric < v_step or (v_r->>'total')::bigint > v_fund
       or public.fleet_cargo_qty(v_fleet, v_code) <> 60 - (v_r->>'qty')::numeric
       or public.treasury_balance(v_port) <> v_fund - (v_r->>'total')::bigint + (v_r->>'tax')::bigint then
      raise exception '0122 self-assert FAIL: a short purse (% d.) did not fill part of a 30-tun sale: %', v_fund, v_r;
    end if;
    v_notes := v_notes || format('a %s d. purse filled %s of 30 t; ', v_fund, v_r->>'qty');

    -- (g) THE PROFIT TAX: on a profit, its own ledger row and flow; none on a loss, an unknown cost, a BUY.
    perform public.treasury_post(v_port, 'SEED', 100000000);
    update public.ships set cargo_basis = cargo_basis || jsonb_build_object(v_code, 1) where fleet_id = v_fleet;
    v_r := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 10));
    v_tax := round(((v_r->>'total')::bigint - 10) * world.tax_rate(v_port));
    if (v_r->>'profit')::bigint <> (v_r->>'total')::bigint - 10 or (v_r->>'tax')::bigint <> v_tax or v_tax <= 0
       or (v_r->>'net')::bigint <> (v_r->>'total')::bigint - v_tax or (v_r->>'tax_total')::numeric <> 0
       or (select l.ducats_delta from public.ledger l where l.player_id = v_player and l.kind = 'TAX'
            order by l.id desc limit 1) is distinct from -v_tax
       or not exists (select 1 from public.treasury_flows tf where tf.port_id = v_port and tf.kind = 'TAX' and tf.ducats = v_tax and tf.lit) then
      raise exception '0122 self-assert FAIL: a profitable sale % did not pay % tax as its own row and flow', v_r, v_tax;
    end if;
    select count(*) into v_n from public.ledger l where l.player_id = v_player and l.kind = 'TAX';
    update public.ships set cargo_basis = cargo_basis || jsonb_build_object(v_code, 1000000) where fleet_id = v_fleet;
    v_r := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 10));
    if (v_r->>'tax')::bigint <> 0 or (v_r->>'profit')::bigint >= 0 then
      raise exception '0122 self-assert FAIL: a sale at a loss paid tax: %', v_r;
    end if;
    update public.ships set cargo_basis = cargo_basis || jsonb_build_object(v_code, null) where fleet_id = v_fleet;
    v_r := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 10));
    if (v_r->>'tax')::bigint <> 0 or v_r->>'profit' is not null then
      raise exception '0122 self-assert FAIL: a sale of unknown cost paid tax: %', v_r;
    end if;
    v_r := cmd.do_buy(v_fleet, jsonb_build_object('good', v_good, 'qty', 10));
    if (v_r->>'tax_total')::numeric <> 0
       or (select count(*) from public.ledger l where l.player_id = v_player and l.kind = 'TAX') <> v_n then
      raise exception '0122 self-assert FAIL: a loss, an unknown cost or a BUY wrote a TAX row (buy %)', v_r;
    end if;

    -- (h) A CHARGE: provisions are paid INTO the harbour, kind unchanged, to the ducat.
    v_r := cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
    if (v_r->>'cost')::bigint <= 0
       or (select l.ducats_delta from public.ledger l where l.player_id = v_player and l.kind = 'PROVISION'
            order by l.id desc limit 1) is distinct from -(v_r->>'cost')::bigint
       or not exists (select 1 from public.treasury_flows tf where tf.port_id = v_port and tf.kind = 'PROVISION'
                       and tf.ducats = (v_r->>'cost')::bigint and tf.lit) then
      raise exception '0122 self-assert FAIL: a provision % was not paid into the harbour', v_r;
    end if;

    -- (i) THE BOARD: under its reserve a city posts no open request; funded, it posts and escrows;
    --     at expiry the escrow comes back to the ducat.
    delete from public.trade_contracts where port_id = v_port;
    update public.port_treasury set reserve = 1000000000000 where port_id = v_port;
    perform public.tick_contracts(v_port, now());
    if exists (select 1 from public.trade_contracts where port_id = v_port and status = 'open') then
      raise exception '0122 self-assert FAIL: a city under its reserve posted an open request';
    end if;
    update public.port_treasury set reserve = 0 where port_id = v_port;
    v_posted := public.tick_contracts(v_port, now());
    select coalesce(sum(escrow), 0), count(*) into v_x, v_n from public.trade_contracts
     where port_id = v_port and status = 'open';
    if exists (select 1 from public.trade_contracts where port_id = v_port and status = 'open' and escrow <> premium_ducats)
       or v_x <> -coalesce((select sum(tf.ducats) from public.treasury_flows tf where tf.port_id = v_port and tf.kind = 'BOUNTY'), 0) then
      raise exception '0122 self-assert FAIL: open requests were not escrowed at posting (Σ escrow %)', v_x;
    end if;
    perform public.tick_contracts(v_port, now() + make_interval(secs => ((public.wc_int('contract_deadline_days') + 1)
                                                                         * public.wc_num('game_day_seconds'))::double precision));
    if coalesce((select sum(tf.ducats) from public.treasury_flows tf where tf.port_id = v_port and tf.kind = 'BOUNTY_LAPSED'), 0) <> v_x then
      raise exception '0122 self-assert FAIL: the lapsed requests returned % not the % escrowed',
        (select sum(tf.ducats) from public.treasury_flows tf where tf.port_id = v_port and tf.kind = 'BOUNTY_LAPSED'), v_x;
    end if;
    v_notes := v_notes || format('the board escrowed %s request(s), %s d., and took it back at expiry; ', v_n, v_x);

    -- (j) THE REFOUND is paid by the home harbour from its surplus (partially when short).
    select h.player_id, h.capital, h.home_port_id, h.roster_ord into v_house from public.npc_houses h
     where not exists (select 1 from public.events ev where ev.player_id = h.player_id and ev.kind = 'NPC_REFOUNDED'
                         and ev.created_at > now() - make_interval(secs => (public.wc_num('npc_refound_cooldown_game_days')
                                                                             * public.wc_num('game_day_seconds'))::double precision))
     order by h.roster_ord limit 1;
    if v_house.player_id is not null then
      update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
      perform public.treasury_post(v_house.home_port_id, 'SEED', 1100);
      update public.port_treasury set reserve = public.treasury_balance(v_house.home_port_id) - 100
       where port_id = v_house.home_port_id;
      update public.players set ducats = 0 where id = v_house.player_id;
      v_exp := least(v_house.capital, public.city_surplus(v_house.home_port_id));
      perform set_config('byeharu.npc_upkeep_deadline', (clock_timestamp() - interval '1 hour')::text, true);
      v_city := public.npc_tend(now());
      perform set_config('byeharu.npc_upkeep_deadline', '', true);
      select e.payload into v_ev from public.events e where e.player_id = v_house.player_id and e.kind = 'NPC_REFOUNDED'
       order by e.created_at desc, e.id limit 1;
      if (select ducats from public.players where id = v_house.player_id) <> v_exp
         or (v_ev->>'amount')::bigint <> v_exp or (v_ev->>'partial')::boolean is distinct from (v_exp < v_house.capital)
         or not exists (select 1 from public.treasury_flows tf where tf.port_id = v_house.home_port_id
                          and tf.kind = 'NPC_REFOUND' and tf.ducats = -v_exp and tf.player_id = v_house.player_id)
         or not (v_city ? 'refound_unfunded') then
        raise exception '0122 self-assert FAIL: the refound was not paid by the home harbour''s surplus (% expected, event %, tend %)',
          v_exp, v_ev, v_city;
      end if;
      v_notes := v_notes || format('a refound of %s d. came from its home''s surplus (partial %s); ', v_exp, v_ev->>'partial');
    else
      v_notes := v_notes || 'every company was inside its refound cooldown, so the refound probe did not run; ';
    end if;

    -- (k) THE LAP CLOSER books the taxes and nets them; the read prints them.
    select nf.route_id into v_route from public.npc_fleets nf where nf.route_id is not null
     order by nf.roster_ord, nf.fleet_id limit 1;
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
    insert into public.standing_route_laps (route_id, lap_no, started_at)
    values (v_route, 900122, now()) returning * into v_lap;
    update public.standing_routes set lap_id = v_lap.id, lap_no = 900122 where id = v_route;
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status, result, route_lap_id, executed_at)
    select nf.fleet_id, nf.player_id, 900122, 'SELL', 'SELL', '{}', 'done',
           jsonb_build_object('good', v_code, 'qty', 10, 'total', 300, 'tax', 30), v_lap.id, now()
      from public.npc_fleets nf where nf.route_id = v_route;
    perform cmd.standing_route_close_lap(v_route, now());
    select * into v_lap from public.standing_route_laps where id = v_lap.id;
    if v_lap.taxes <> 30 or v_lap.net is distinct from v_lap.sold - v_lap.bought - v_lap.supplies - v_lap.repairs - v_lap.wages
                                                     + v_lap.stock_out
                                                     - coalesce((select x.stock_out from public.standing_route_laps x
                                                                  where x.route_id = v_route and x.closed_at is not null and x.lap_no < 900122
                                                                  order by x.lap_no desc limit 1), 0) - 30 then
      raise exception '0122 self-assert FAIL: the closer booked taxes % net % for a lap that paid 30', v_lap.taxes, v_lap.net;
    end if;
    v_r := world.fleet_trades((select nf.fleet_id from public.npc_fleets nf where nf.route_id = v_route limit 1));
    if (v_r->'laps'->0->>'taxes')::bigint <> 30 or not (v_r->'day' ? 'taxes') then
      raise exception '0122 self-assert FAIL: world.fleet_trades does not print the lap''s taxes: %', v_r->'laps'->0;
    end if;

    -- (l) THE READ, and THE ROLL on the whole world: books = purses, the flows rolled, under 20 s.
    v_r := world.town_hall(v_port);
    if (v_r->'purse'->>'ducats')::bigint <> public.treasury_balance(v_port) or not (v_r->>'enabled')::boolean
       or (v_r->'purse'->>'tax_rate')::numeric <> world.tax_rate(v_port) then
      raise exception '0122 self-assert FAIL: world.town_hall read %', v_r;
    end if;
    v_bal := public.treasury_balance(v_port);
    v_ms := extract(epoch from clock_timestamp());
    v_city := public.tick_city(now());
    v_ms := round((extract(epoch from clock_timestamp()) - v_ms) * 1000);
    if exists (select 1 from public.treasury_flows where created_at <= now())
       or (select ducats from public.port_treasury where port_id = v_port) <> v_bal
       or public.treasury_balance(v_port) <> v_bal
       or v_city->'errors' <> '{}'::jsonb or v_ms > 20000 then
      raise exception '0122 self-assert FAIL: tick_city left flows, moved a purse or took % ms: %', v_ms, v_city;
    end if;
    v_notes := v_notes || format('tick_city rolled %s flow(s) over the whole world in %s ms; ', v_city->>'flows_rolled', v_ms);

    raise exception 'ROLLBACK_0122';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0122' then raise; end if;
  end;

  -- (m) THE SWITCH: a broke world is refused and nothing is lit; a sound one is seeded once.
  begin
    update public.world_config set value = to_jsonb(1000000000) where key = 'npc_invest_above';
    begin
      perform public.city_treasury_switch(true);
      raise exception '0122 self-assert FAIL: the switch lit a broke world';
    exception when others then
      if sqlerrm not like 'E_WORLD_BROKE%' then raise; end if;
    end;
    if public.city_treasury_on() or exists (select 1 from public.treasury_flows where kind = 'SEED') then
      raise exception '0122 self-assert FAIL: a refused switch left the purses lit or seeded';
    end if;
    update public.world_config set value = to_jsonb(0) where key = 'npc_invest_above';
    v_r := public.city_treasury_switch(true);
    if not public.city_treasury_on() or (v_r->>'seeded')::int <> (select count(*) from public.ports where kind = 'HARBOUR')
       or exists (select 1 from public.ports p where p.kind = 'HARBOUR'
                   and public.treasury_balance(p.id) < public.wc_int('city_seed_min')) then
      raise exception '0122 self-assert FAIL: the switch did not seed every harbour: %', v_r;
    end if;
    if (public.city_treasury_switch(true)->>'seeded')::int <> 0 then
      raise exception '0122 self-assert FAIL: a second switch re-seeded';
    end if;
    v_notes := v_notes || format('the switch seeded %s harbours with %s d.; ', v_r->>'seeded', v_r->>'seed_total');
    perform public.city_treasury_switch(false);
    if public.city_treasury_on() then raise exception '0122 self-assert FAIL: the switch would not go dark'; end if;
    raise exception 'ROLLBACK_0122';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0122' then raise; end if;
  end;

  -- (n) THE CLOCK: defined, inactive, listed (where there is a clock).
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and not exists (select 1 from public.clock_jobs() j where j.jobname = 'byeharu-voyage:city' and j.schedule = '37 * * * *') then
    raise exception '0122 self-assert FAIL: byeharu-voyage:city is not defined';
  end if;

  if public.city_treasury_on() or public.wc('npc_traders_enabled') <> v_npc_on or public.wc('standing_routes_enabled') <> v_rt_on
     or exists (select 1 from public.treasury_flows where kind in ('PROBE', 'SEED'))
     or exists (select 1 from public.standing_route_laps where lap_no = 900122) then
    raise exception '0122 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0122 self-assert ok: A CITY KEEPS A PURSE. The movers, the roll and the switch are server-only, world.town_hall authenticated-only and registered, no client write grant, the books unreadable and the purse public; a purse cannot go below zero and the flows are append-only but to the roll; no cut body charges through credit( or prints the raw rate; merchants pay running costs at 1. Dark: 200 quotes and prices equal their pre-images, the rate is the column, a BUY and a SELL moved the purse exactly as before and booked unlit flows (SOLD carries tax 0, net = total). Lit: the rate is the column × 5 capped at 20 %%, the ask carries no tax, the bid factor read 0.5 / 0.75 / 1 / 1; an empty city refused E_CITY_BROKE with figures and moved nothing; %a profitable sale paid its tax as its own TAX row and flow, a loss, an unknown cost and a BUY paid none; a provision was paid into the harbour; %the closer booked taxes and netted them and the read printed them; %the switch refused a broke world and left it dark. Rolled back; the purses ship DARK.',
    split_part(v_notes, '; ', 1) || '; ', split_part(v_notes, '; ', 2) || '; ' || split_part(v_notes, '; ', 3) || '; ',
    split_part(v_notes, '; ', 4) || '; ' || split_part(v_notes, '; ', 5) || '; ';
end $$;

drop table pg_temp.pre_0122;
