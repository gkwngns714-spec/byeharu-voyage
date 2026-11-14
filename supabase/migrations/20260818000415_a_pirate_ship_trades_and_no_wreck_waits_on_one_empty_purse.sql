-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0415 - A PIRATE SHIP TRADES AS WELL AS RAIDS; THE PIRATE CITIES FUND A PIRATE WITH AN EMPTY PURSE; NO WRECK WAITS ON ONE EMPTY PURSE
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-14, in order: "pirate ships don't trade. they only do and engage combat", then reversed: "actually, make them trade too, but
--   engage combat more aggressively with other npcs and players"; "the pirate cities will fund those that have empty purse."; of the amount: "just
--   enough to start", then taken back: "not just enough to start, just like before./"; and of every fault of the day: "find the root cause, make it
--   so that this problem does not occur again". docs/dev-log/2026-11-14-pirate-trade.md has the reasoning, the arithmetic and what was decided by default.
--
-- A. A PIRATE SHIP TRADES, AS THE ONE SHIP SHE IS. She stays a row of public.pirate_ships moved by the pirates' own job (public.tick_pirates ->
--    public.pirate_ship_step), cruising and raiding exactly as 0339 / 0409 left her: no standing route, no row in npc_houses or npc_fleets, nothing in
--    the merchants' planner, nothing in the arrivals beat. What is new is ONE call at the two moments her step already sends her to sea:
--      at her home, bound for her haunt, and at her haunt, bound for home: public.pirate_trade(fleet, where she is bound).
--    It (1) SELLS what she carries, good by good, through THE sale door (cmd.do_sell) with a limit of what the good cost her x (1 + npc_sell_margin):
--    a sale below cost is never made, and the door's own empty-purse rule (0122 / 0233) pays her only what the city's purse holds; what is refused
--    stays aboard for the next harbour. (2) BUYS for the harbour she is bound for, through THE buy door (cmd.do_buy), what public.pirate_cargo_plan
--    answers: the merchants' own measures in the merchants' own order (THE ranking world.trade_routes; the sink's answer world.quote_priced above cost
--    plus the margin; public.npc_affordable; the day's cap at both ends; AND 0410's rule, the sink's live purse by the door's measure, so no parcel is
--    planned that the city she carries it to cannot pay for; kept only if it pays npc_min_return_pct after the sink's profit tax; at most
--    npc_lines_per_stop goods). She spends on cargo only what her house holds ABOVE the gift's broke line (merchant_broke_pct of her capital), so
--    buying a cargo never makes her "broke", and a house under the line buys nothing until the cities have funded her. Off duty she only sells on her way home.
--    Her house keeps the proceeds. Nothing is minted: every ducat is public.pay_city / public.city_pays, every tun the doors'.
--    KNOB `pirates_trade` (true): false and she cruises and raids as before and trades nothing (the fast lever).
--    NOT DONE (said plainly): plunder still lands in her HOME's stock (public.pirate_stow, 0339), not in her hold; she buys it there like anyone.
-- B. THE PIRATE CITIES FUND A PIRATE WITH AN EMPTY PURSE, "LIKE BEFORE": 0408's rule, the same roster (public.capital_gift_roster), the same body
--    (public.capital_gift_one), the same line (purse under merchant_broke_pct of her capital), the same gift_cooldown_hours and gift_max_per_week,
--    the same book (public.capital_gifts). The house of a pirate ship is admitted to the roster ONLY WHEN ASKED FOR ALONE (p_only), as a player's
--    company is (0241), so she never takes one of the merchants' gift_max_per_hour places; who asks is the pirates' own job, once an hour
--    (public.pirate_gift_hour). HER CAPITAL is public.pirate_house_capital: `pirate_house_capital_pct` (0.5) of what her hulls cost to build: one
--    refit (npc_refit_share 0.25) and as much again to buy a cargo with. WHO PAYS (public.pirate_gift_pay), whole or nothing: her home city; else
--    another city the pirates hold, the richest first; else Port Royal's hoard (public.pirate_pay). All of it inside the day's room
--    (public.pirate_spend_room) and written to the day (public.pirate_spend_day), and a gift never takes the room the rest of the day's pay of the
--    ships needs (so a day of gifts cannot leave the fleets unpaid and laid up). A merchant house of the pirates is paid exactly as 0408 pays her.
--    `pirate_spend_day_pct` is NOT changed (it is 0414's, 2.4 times what the clock's door leaves).
-- C. NO WRECK WAITS ON ONE EMPTY PURSE (the fault 0409 fixed for pirate ships, in the body it came from): public.npc_refit_step let ONLY the home
--    of a merchant, cargo ship or navy ship (her station) pay. Now the payer is public.npc_refit_payer: her home; behind an empty home her
--    country's capital, then the richest other city her country holds (a ship of the pirates' merchants: the hoard, inside the day's room). Whole or
--    nothing, city to yard, kind REFIT, moved. When every payer is dry she waits as before: a row in public.npc_refit_waits, a REFIT_WAITING event
--    once a day, and the hourly job asks again. Her REFITTED event names who paid (`paid_by`).
-- THE RE-CUTS (hunks; each occurs exactly once in the live body and reverses to its pre-image; ACL, volatility, definer, config, owner unmoved;
--   pre-images are the bodies as PR #678 (the pirates' homes) and PR #681 (0410) leave them): public.pirate_ship_step (2), public.tick_pirates (4), public.capital_gift_roster (1),
--   public.capital_gift_one (1), public.npc_refit_step (3).
-- LOAD: nothing in the arrivals beat. In the pirates' own job: one trade call a fleet a departure (two a cruise; a cruise is pirate_haunt_hours, 12 real hours, at the haunt and two passages whose length follows the served game day: about 20 calls an
--   hour for 121 fleets, tens of milliseconds each), and once an hour one roster read for each house under the line. A ship that traded holds
--   the market rows she traded and the purse that paid her until the job's run commits, so the run steps NO MORE SHIPS after her and leaves the
--   adding, the pay and the gift to the next minute: at most one trading fleet a minute (60 an hour against about 20 needed).
-- LOCKS: CREATE OR REPLACE by hunks; ALTER TABLE public.pirate_clock (one row) ADD COLUMN. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails
--   above 30 s. SELF-ASSERT: its own rows and probes only, in a sub-transaction rolled back by a raised sentinel; no growing table counted or summed.
-- ROLLBACK (forward, owner only): scripts/ops/harness/pirate-trade/rollback-0415.sql, a draft. Fast levers: `pirates_trade` false (no trading);
--   `pirate_house_capital_pct` 0 (no pirate ship's house is gifted).
-- VERSION: 0415 = 0414 + 1 (production head 0413 on 2026-11-14; 0414 is the pirates' homes, PR #678). Built on pacific-pirates b5ea75b2 (PR #678 merged with origin/main 517bf154).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.pirate_ship_step(uuid,timestamp with time zone)', 'public.tick_pirates(timestamp with time zone)',
                                 'public.capital_gift_roster(timestamp with time zone,uuid)', 'public.capital_gift_one(timestamp with time zone,uuid)',
                                 'public.npc_refit_step(uuid,timestamp with time zone)'];
  c_new constant text[] := array['public.pirate_house_capital(uuid)', 'public.pirate_gift_pay(uuid,bigint,timestamp with time zone)', 'public.pirate_gift_hour(timestamp with time zone)',
                                 'public.pirate_cargo_plan(uuid,uuid)', 'public.pirate_trade(uuid,uuid,timestamp with time zone)',
                                 'public.npc_refit_payer(uuid,uuid,bigint,timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  v_now       timestamptz := now();
  v_far       timestamptz := now() + interval '30 days';   -- the probe's gift is asked at an instant no gift and no day's spend of the live world has reached
  hk          record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_pir       uuid;
  v_cap       uuid;
  v_fleet     uuid;
  v_house     uuid;
  v_from      uuid;
  v_to        uuid;
  v_capital   bigint;
  v_keep      bigint;
  v_purse     bigint;
  v_r         jsonb;
  v_plan      jsonb;
  v_s         text;
  v_home      uuid;
  v_payer     uuid;
  v_note_a    text := 'no pirate ship to probe in this world';
  v_note_b    text := 'no gift probed';
  v_note_c    text := 'no merchant to wreck in this world';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.pirate_gift_pay(uuid,bigint,timestamp with time zone)') is not null
     or exists (select 1 from public.world_config where key in ('pirates_trade', 'pirate_house_capital_pct')) then
    raise exception '0415 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.pirate_reborn(uuid,timestamp with time zone)') is null or to_regclass('public.pirate_roster') is null then
    raise exception '0415 refuses: the pirates'' homes and grounds (PR #678) is not in this world';
  end if;
  if position('0410' in pg_get_functiondef('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'::regprocedure)) = 0 then
    raise exception '0415 refuses: 0410 (a merchant carries only what the city''s purse can pay for) is not in this world';
  end if;
  if to_regprocedure('cmd.do_sell(uuid,jsonb)') is null or to_regprocedure('cmd.do_buy(uuid,jsonb)') is null
     or to_regprocedure('world.trade_routes(uuid,uuid,numeric,integer,uuid)') is null or to_regprocedure('world.quote_terms(uuid,uuid,uuid)') is null
     or to_regprocedure('public.npc_affordable(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric)') is null
     or to_regprocedure('public.pirate_pay(text,bigint,timestamp with time zone,uuid,uuid)') is null or to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0415 refuses: the doors, the ranking, the hoard''s payer or the news are not all in this world';
  end if;
  v_pir := public.pirate_nation();
  v_cap := public.pirate_capital();

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
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE KNOBS AND THE CLOCK ──
  insert into public.world_config (key, value, description) values
    ('pirates_trade', 'true'::jsonb, '0415: a pirate ship trades as well as raids: as she leaves her home or her haunt she sells what she carries at a gain and buys for the harbour she is bound for (public.pirate_trade). false: she cruises and raids and trades nothing.'),
    ('pirate_house_capital_pct', to_jsonb(0.5), '0415: the capital of the house of a pirate ship, as a share of what its hulls cost to build (public.pirate_house_capital): 0.5 is one refit (npc_refit_share 0.25) and as much again for a cargo. The pirate cities give it to a house whose purse is under merchant_broke_pct of it, by the gift''s own cooldown and weekly limit. 0: no pirate ship''s house is gifted.');
  alter table public.pirate_clock add column gifted_at timestamptz;
  comment on column public.pirate_clock.gifted_at is '0415: when the pirates'' job last asked the gift for the houses of the pirate ships (public.pirate_gift_hour, once an hour).';

  -- ── 3. THE NEW FUNCTIONS ──
  execute $f$
create function public.pirate_house_capital(p_player uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0415: THE capital of the house of a pirate ship: pirate_house_capital_pct of what the hulls of all her fleets cost to build. 0 for a house with no pirate ship (and with the knob at 0), and such a house is never on the gift's roster.
  select round(public.wc_num('pirate_house_capital_pct') * coalesce(sum(c.build_cost), 0))::bigint
    from public.pirate_ships n join public.ships s on s.fleet_id = n.fleet_id join public.ship_classes c on c.id = s.class_id
   where n.player_id = p_player
$$
  $f$;

  execute $f$
create function public.pirate_gift_pay(p_player uuid, p_amount bigint, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0415: WHO PAYS THE GIFT OF A HOUSE OF THE PIRATES (the owner, 2026-11-14: "the pirate cities will fund those that have empty purse"), whole or nothing, moved, never minted. Called by public.capital_gift_one alone.
-- A MERCHANT house (no pirate ship): Port Royal's hoard through public.pirate_pay, exactly 0408's line. The house of a PIRATE SHIP: her home city (HOME); else another city the pirates hold, the richest first (CITY);
-- else the hoard (HOARD). A city pays only from its surplus (public.city_surplus), only when its purse is free (public.treasury_try_lock), and only inside the day's room (public.pirate_spend_room) LESS what the rest of
-- the UTC day's pay of the ships at work still needs: a gift never takes the pay's room. Every payment is written to the day (public.pirate_spend_day). Null: nobody can pay now; she is asked again next hour.
declare
  v_cap  uuid := public.pirate_capital();
  v_home uuid;
  v_keep bigint;
  c      record;
begin
  if v_cap is null or coalesce(p_amount, 0) <= 0 then
    return null;
  end if;
  select n.home_port into v_home from public.pirate_ships n where n.player_id = p_player order by n.ord limit 1;
  if v_home is null then
    return case when public.pirate_pay('CAPITAL_GIFT', p_amount, p_now, p_player := p_player) >= p_amount then 'HOARD' end;
  end if;
  v_keep := (select count(*) from public.pirate_ships_at_work) * round(public.wc_num('navy_upkeep_day') / 24)
            * ceil(extract(epoch from (date_trunc('day', p_now at time zone 'UTC') + interval '1 day') - (p_now at time zone 'UTC')) / 3600);
  if not public.city_treasury_on() or public.pirate_spend_room(p_now) - v_keep < p_amount then
    return null;
  end if;
  perform 1 from public.players pl where pl.id = p_player for update;   -- the house first, the harbour second (public.city_pays's order)
  if v_home = v_cap and public.pirate_pay('CAPITAL_GIFT', p_amount, p_now, p_player := p_player) >= p_amount then
    return 'HOME';   -- her home is the capital: Port Royal pays first, as any home does
  end if;
  for c in select a.port_id from public.port_allegiance a
            where a.nation_id = public.pirate_nation() and a.port_id is distinct from v_cap
            order by (a.port_id = v_home) desc, public.city_surplus(a.port_id) desc, a.port_id loop
    continue when public.city_surplus(c.port_id) < p_amount;
    continue when not public.treasury_try_lock(c.port_id);
    continue when public.city_surplus(c.port_id) < p_amount;
    perform public.city_pays(c.port_id, p_player, 'CAPITAL_GIFT', p_amount, null);
    insert into public.pirate_spend_day (day, spent) values ((p_now at time zone 'UTC')::date, p_amount)
    on conflict (day) do update set spent = public.pirate_spend_day.spent + excluded.spent;
    return case when c.port_id = v_home then 'HOME' else 'CITY' end;
  end loop;
  if v_home is distinct from v_cap and public.pirate_pay('CAPITAL_GIFT', p_amount, p_now, p_player := p_player) >= p_amount then
    return 'HOARD';
  end if;
  return null;
end
$$
  $f$;

  execute $f$
create function public.pirate_gift_hour(p_now timestamptz)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0415: once an hour, in the pirates' own job (public.tick_pirates): every house of a pirate ship at work whose purse is under the broke line (merchant_broke_pct of public.pirate_house_capital) is asked for by THE gift's own
-- body (public.capital_gift_one: its roster, cooldown, weekly limit and book), the smallest capital first so that a short day funds the most houses. Nothing while the economy is open. Answers the gifts given.
declare
  r     record;
  v     jsonb;
  v_n   int := 0;
  v_pct numeric := public.wc_num('merchant_broke_pct');
begin
  if not public.economy_closed() or (select c.gifted_at from public.pirate_clock c) > p_now - interval '1 hour' then
    return 0;
  end if;
  for r in select x.player_id, public.pirate_house_capital(x.player_id) as capital
             from (select distinct n.player_id from public.pirate_ships_at_work n) x join public.players pl on pl.id = x.player_id
            where pl.ducats < public.pirate_house_capital(x.player_id) * v_pct
            order by 2, 1 loop
    v := public.capital_gift_one(p_now, r.player_id);
    v_n := v_n + coalesce((v ->> 'gifted')::int, 0);
  end loop;
  update public.pirate_clock set gifted_at = p_now;
  return v_n;
end
$$
  $f$;

  execute $f$
create function public.pirate_cargo_plan(p_fleet uuid, p_to uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0415: WHAT A PIRATE SHIP LYING IN A HARBOUR BUYS FOR THE HARBOUR SHE IS BOUND FOR. A plain read; public.pirate_trade buys it through the door. The merchants' measures, in the merchants' order (public.npc_leg_lines):
-- THE ranking (world.trade_routes, here to p_to); the size the SINK takes above the probe's cost plus npc_sell_margin (world.quote_priced); the day's cap at both ends; the hold left; what her house can pay
-- (public.npc_affordable) out of what it holds ABOVE the gift's broke line (merchant_broke_pct of public.pirate_house_capital: buying never makes her broke); AND 0410's rule: no more than the sink's live purse can pay for, by the
-- sale door's own measure (round(total / haul), haul 1 while the economy is closed), the purse falling by every parcel kept. Kept only if it pays npc_min_return_pct after the sink's profit tax; at most
-- npc_lines_per_stop goods. Answers [{good, code, qty, cost, due, net}]: `due` is what the sink's purse will pay of the sale. Empty when the purses are dark, the sink cannot pay, or nothing pays.
declare
  v_k      int     := public.wc_int('npc_lines_per_stop');
  v_margin numeric := public.wc_num('npc_sell_margin');
  v_minret numeric := public.wc_num('npc_min_return_pct');
  f        public.fleets%rowtype;
  v_plan   jsonb := '[]'::jsonb;
  v_budget numeric;
  v_left   numeric;
  v_room   numeric;
  v_haul   numeric;
  v_due    numeric;
  v_shrunk int;
  e        jsonb;
  v_good   uuid;
  v_bulk   numeric;
  v_cap    numeric;
  v_q      numeric;
  v_net    numeric;
  q_size   record;
  q_buy    record;
  q_sell   record;
  k_from   record;
  k_to     record;
begin
  select * into f from public.fleets x where x.id = p_fleet;
  if f.port_id is null or p_to is null or p_to = f.port_id or not public.city_treasury_on() then
    return v_plan;
  end if;
  v_budget := coalesce((select pl.ducats from public.players pl where pl.id = f.player_id), 0)
              - ceil(public.pirate_house_capital(f.player_id) * public.wc_num('merchant_broke_pct'));
  v_room := greatest(public.treasury_balance(p_to), 0);
  v_left := public.fleet_free_hold(p_fleet);
  if v_budget < 1 or v_room < 1 or v_left < 1 then
    return v_plan;
  end if;
  select * into k_from from world.quote_terms(f.port_id, null, null);
  select * into k_to   from world.quote_terms(p_to, null, null);
  for e in select x from jsonb_array_elements(coalesce(world.trade_routes(f.port_id, null, null, 12, p_to) -> 'routes', '[]'::jsonb)) x loop
    exit when jsonb_array_length(v_plan) >= v_k or v_room < 1 or v_budget < 1;
    v_good := (e ->> 'good_id')::uuid;
    select g.bulk into v_bulk from public.goods g where g.id = v_good;
    v_cap := floor(least(world.daily_cap_remaining(f.player_id, f.port_id, v_good), world.daily_cap_remaining(f.player_id, p_to, v_good), v_left / greatest(v_bulk, 0.001)));
    continue when v_cap is null or v_cap < 1;
    select * into q_size from world.quote_priced(p_to, v_good, v_cap, 'sell', round((e ->> 'buy_price')::numeric * (1 + v_margin), 2), null, k_to.q_spread, k_to.q_nohag, k_to.q_tax, k_to.q_bidf);
    v_q := floor(coalesce(q_size.units, 0));
    continue when v_q < 1;
    select a.units into v_q from public.npc_affordable(f.port_id, v_good, v_q, v_budget, k_from.q_spread, k_from.q_nohag, k_from.q_tax, k_from.q_bidf) a;
    continue when v_q < 1;
    v_haul := case when public.economy_closed() then 1 else public.cargo_haul(p_to, v_good) end;
    v_due := round(q_size.total / v_haul);
    v_shrunk := 0;
    while v_due > v_room and v_q >= 1 and v_shrunk < 6 loop
      select * into q_sell from world.quote_priced(p_to, v_good, v_q, 'sell', null, null, k_to.q_spread, k_to.q_nohag, k_to.q_tax, k_to.q_bidf);
      v_due := round(q_sell.total / v_haul);
      exit when v_due <= v_room;
      v_q := least(v_q - 1, floor(v_q * v_room / v_due));
      v_shrunk := v_shrunk + 1;
    end loop;
    continue when v_q < 1 or v_due > v_room;
    select * into q_buy from world.quote_priced(f.port_id, v_good, v_q, 'buy', null, null, k_from.q_spread, k_from.q_nohag, k_from.q_tax, k_from.q_bidf);
    continue when q_buy.units is null or q_buy.units < v_q or q_buy.total <= 0 or q_buy.total > v_budget;
    select * into q_sell from world.quote_priced(p_to, v_good, v_q, 'sell', null, null, k_to.q_spread, k_to.q_nohag, k_to.q_tax, k_to.q_bidf);
    v_due := round(q_sell.total / v_haul);
    continue when q_sell.units is null or q_sell.units < v_q or v_due > v_room;
    v_net := (q_sell.total - q_buy.total) - public.profit_tax(p_to, q_sell.total - q_buy.total, f.player_id);
    continue when v_net <= 0 or v_net * 100 < v_minret * q_buy.total;
    v_plan := v_plan || jsonb_build_object('good', v_good, 'code', e ->> 'code', 'qty', v_q, 'cost', q_buy.total, 'due', v_due, 'net', v_net);
    v_left := v_left - v_q * v_bulk;
    v_budget := v_budget - q_buy.total;
    v_room := v_room - v_due;
  end loop;
  return v_plan;
end
$$
  $f$;

  execute $f$
create function public.pirate_trade(p_fleet uuid, p_to uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0415: THE TRADING OF A PIRATE SHIP (the owner, 2026-11-14: "make them trade too"), called by public.pirate_ship_step as she leaves the harbour she lies in, bound for p_to (null: she only sells). The caller holds her fleet row.
-- (1) Every good aboard is offered to THE sale door (cmd.do_sell) with a limit of what it cost her x (1 + npc_sell_margin): never a sale below cost; the door pays only what the city's purse holds (0122) and what it
-- refuses stays aboard. A good whose cost the hold does not know is not offered. (2) What public.pirate_cargo_plan answers for p_to is bought through THE buy door (cmd.do_buy). A door's refusal is hers to bear:
-- nothing here can stop her sailing (any error is a warning and she sails). A trade made sets byeharu.pirate_traded for the transaction (read by public.tick_pirates). Off (`pirates_trade` false) or the purses dark: nothing. Answers {sold, bought, refused} in ducats and lines, or null.
declare
  f         public.fleets%rowtype;
  r         record;
  v_margin  numeric := public.wc_num('npc_sell_margin');
  v_basis   numeric;
  v_res     jsonb;
  v_sold    bigint := 0;
  v_bought  bigint := 0;
  v_refused int := 0;
begin
  if public.wc('pirates_trade') is distinct from 'true'::jsonb or not public.city_treasury_on() then
    return null;
  end if;
  select * into f from public.fleets x where x.id = p_fleet;
  if f.id is null or f.status <> 'DOCKED' or f.port_id is null or not exists (select 1 from public.pirate_ships n where n.fleet_id = p_fleet) then
    return null;
  end if;
  for r in select g.id, g.code from public.ships s cross join lateral jsonb_each(s.cargo) e join public.goods g on g.code = e.key
            where s.fleet_id = p_fleet and jsonb_typeof(e.value) = 'number' and (e.value)::text::numeric > 0 group by g.id, g.code order by g.code loop
    v_basis := public.fleet_cargo_basis(p_fleet, r.code);
    continue when v_basis is null;
    begin
      v_res := cmd.do_sell(p_fleet, jsonb_build_object('good', r.id, 'limit', round(v_basis * (1 + v_margin), 2)));
      v_sold := v_sold + coalesce((v_res ->> 'total')::numeric, 0)::bigint;
    exception when others then
      v_refused := v_refused + 1;   -- the bid is under her cost, the city cannot pay, the day's allowance is spent: she keeps it
    end;
  end loop;
  if p_to is not null then
    for r in select (x ->> 'good')::uuid as good, (x ->> 'qty')::numeric as qty from jsonb_array_elements(public.pirate_cargo_plan(p_fleet, p_to)) x loop
      begin
        v_res := cmd.do_buy(p_fleet, jsonb_build_object('good', r.good, 'qty', r.qty));
        v_bought := v_bought + coalesce((v_res ->> 'total')::numeric, 0)::bigint;
      exception when others then
        v_refused := v_refused + 1;
      end;
    end loop;
  end if;
  if v_sold > 0 or v_bought > 0 then
    perform set_config('byeharu.pirate_traded', 'on', true);   -- she holds the market rows she traded and the purse that paid her until the commit: public.tick_pirates steps no more ships this run
  end if;
  return jsonb_build_object('sold', v_sold, 'bought', v_bought, 'refused', v_refused);
exception when others then
  raise warning 'pirate_trade: fleet % traded nothing (SQLSTATE %: %)', p_fleet, sqlstate, sqlerrm;
  return null;
end
$$
  $f$;

  execute $f$
create function public.npc_refit_payer(p_fleet uuid, p_home uuid, p_cost bigint, p_now timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0415: WHO PAYS THE REFIT OF A MERCHANT, A CARGO SHIP OR A NAVY SHIP (the fault 0409 fixed for pirate ships: a wreck whose home's purse is empty sat for ever, because the home alone could pay). Called by
-- public.npc_refit_step alone, which holds her home's lock. Her HOME (a navy ship's station) when its surplus covers it, as before. Behind an empty home: her country's capital, then the richest other city her
-- country holds (a crown's ship: public.crown_nation; a merchant: her house's nation), from its surplus, its purse free (public.treasury_try_lock), never the yard that is to be paid. A ship of the pirates'
-- merchants: Port Royal's hoard alone, inside the day's room (public.pirate_spend_room; the spend is written to the day here). Answers the city that pays, locked, or null: nobody can pay now and she waits.
declare
  v_nat  uuid;
  v_yard uuid;
  v_cap  uuid;
  c      record;
begin
  if coalesce(p_cost, 0) <= 0 or public.city_surplus(p_home) >= p_cost then
    return p_home;
  end if;
  v_yard := public.refit_yard(p_home);
  v_nat := coalesce(public.crown_nation(p_fleet), (select pl.nation_id from public.fleets f join public.players pl on pl.id = f.player_id where f.id = p_fleet));
  if v_nat is null or v_yard is null then
    return null;
  end if;
  if public.pirate_power(v_nat) then
    v_cap := public.pirate_capital();
    if v_cap is null or v_cap = p_home or v_cap = v_yard or public.pirate_spend_room(p_now) < p_cost or public.city_surplus(v_cap) < p_cost
       or not public.treasury_try_lock(v_cap) or public.city_surplus(v_cap) < p_cost then
      return null;
    end if;
    insert into public.pirate_spend_day (day, spent) values ((p_now at time zone 'UTC')::date, p_cost)
    on conflict (day) do update set spent = public.pirate_spend_day.spent + excluded.spent;
    return v_cap;
  end if;
  for c in select h.id from public.ports h join public.port_treasury t on t.port_id = h.id
            where h.kind = 'HARBOUR' and h.id <> p_home and h.id <> v_yard and public.port_nation(h.id) = v_nat
            order by (h.code = (select n.capital_port_code from public.nations n where n.id = v_nat)) desc, public.city_surplus(h.id) desc, h.code loop
    continue when public.city_surplus(c.id) < p_cost;
    continue when not public.treasury_try_lock(c.id);
    continue when public.city_surplus(c.id) < p_cost;
    return c.id;
  end loop;
  return null;
end
$$
  $f$;

  revoke all on function public.pirate_house_capital(uuid) from public, anon, authenticated;
  revoke all on function public.pirate_gift_pay(uuid, bigint, timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_gift_hour(timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_cargo_plan(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.pirate_trade(uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.npc_refit_payer(uuid, uuid, bigint, timestamptz) from public, anon, authenticated;

  -- ── 4. THE HUNKS ──
  create temp table hunk_0415 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0415 values
  (1, c_cut[1],
$h$    return public.pirate_sail(p_fleet, f.port_id, voyage.segments_from_course(v_course), n.home_port, null, null, 'HOME', p_now);
$h$,
$h$    perform public.pirate_trade(p_fleet, case when v_duty then n.home_port end, p_now);   -- 0415: SHE TRADES TOO: as she leaves her haunt she sells what she carries at a gain and, on duty, buys for her home; off duty she only sells
    return public.pirate_sail(p_fleet, f.port_id, voyage.segments_from_course(v_course), n.home_port, null, null, 'HOME', p_now);
$h$),
  (2, c_cut[1],
$h$  return public.pirate_sail(p_fleet, f.port_id, voyage.segments_from_course(h.course), h.port_id, h.sea_id, h.port_id, 'CRUISE', p_now);
$h$,
$h$  perform public.pirate_trade(p_fleet, h.port_id, p_now);   -- 0415: at home she sells what she brought and buys for her haunt, what its purse can pay for (public.pirate_cargo_plan)
  return public.pirate_sail(p_fleet, f.port_id, voyage.segments_from_course(h.course), h.port_id, h.sea_id, h.port_id, 'CRUISE', p_now);
$h$),
  (3, c_cut[2],
$h$  for r in select n.fleet_id, n.ord from public.pirate_ships_at_work n join public.fleets f on f.id = n.fleet_id
$h$,
$h$  perform set_config('byeharu.pirate_traded', '', true);   -- 0415: set by public.pirate_trade when a ship of this run has traded
  for r in select n.fleet_id, n.ord from public.pirate_ships_at_work n join public.fleets f on f.id = n.fleet_id
$h$),
  (4, c_cut[2],
$h$    exit when v_n >= v_max;
$h$,
$h$    exit when v_n >= v_max or current_setting('byeharu.pirate_traded', true) = 'on';   -- 0415: a ship that traded holds the market rows and the purse of her harbour until this run commits, so the run steps no more ships after her (the rest go next minute; the order turns)
$h$),
  (5, c_cut[2],
$h$  if v_lit then
    begin
      v_add := public.pirate_add(p_now);
$h$,
$h$  if v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then   -- 0415: never behind a trade's locks: a run in which a ship traded leaves the adding, the pay and the gift to the next minute (each has its own clock)
    begin
      v_add := public.pirate_add(p_now);
$h$),
  (6, c_cut[2],
$h$      raise warning 'tick_pirates: nobody was paid (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
$h$,
$h$      raise warning 'tick_pirates: nobody was paid (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
    begin
      perform public.pirate_gift_hour(p_now);   -- 0415: once an hour the pirate cities fund the houses of the pirate ships whose purse is empty (the gift's own rule, 0408's)
    exception when others then
      raise warning 'tick_pirates: nobody was gifted (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
$h$),
  (7, c_cut[3],
$h$      from (select nh.player_id, nh.capital, false as human from public.npc_houses nh
            union all
$h$,
$h$      from (select nh.player_id, nh.capital, false as human from public.npc_houses nh
            union all
            -- 0415: THE HOUSE OF A PIRATE SHIP TOO, but only when asked for her alone (p_only: public.pirate_gift_hour, in the pirates' own job), so she takes none of the hourly pass's places. Her capital is public.pirate_house_capital.
            select x.player_id, public.pirate_house_capital(x.player_id), false
              from (select distinct ps.player_id from public.pirate_ships ps where p_only is not null and ps.player_id = p_only) x
             where public.pirate_house_capital(x.player_id) > 0
            union all
$h$),
  (8, c_cut[4],
$h$      if public.pirate_power(r.nation_id) and exists (select 1 from public.npc_houses nh where nh.player_id = r.player_id) then
        if r.cap_id is distinct from public.pirate_capital()
           or public.pirate_pay('CAPITAL_GIFT', r.capital, p_now, p_player := r.player_id) < r.capital then
$h$,
$h$      if public.pirate_power(r.nation_id) and (exists (select 1 from public.npc_houses nh where nh.player_id = r.player_id)
                                               or exists (select 1 from public.pirate_ships ps where ps.player_id = r.player_id)) then   -- 0415: the house of a pirate ship too
        if r.cap_id is distinct from public.pirate_capital()
           or public.pirate_gift_pay(r.player_id, r.capital, p_now) is null then   -- 0415: THE payer of a pirate house's gift: a merchant by the hoard as 0408; a pirate ship's house by her home city, another pirate city, then the hoard
$h$),
  (9, c_cut[5],
$h$  v_ev     uuid;
begin
$h$,
$h$  v_ev     uuid;
  v_payer  uuid;   -- 0415: the city that pays her refit (public.npc_refit_payer)
begin
$h$),
  (10, c_cut[5],
$h$  if public.city_surplus(v_home) < v_cost then
    v_why := 'broke';
  else
$h$,
$h$  v_payer := public.npc_refit_payer(p_fleet, v_home, v_cost, p_now);   -- 0415: her home; behind an empty home her country's capital, then its richest city (the pirates' merchants: the hoard). Null: every payer is dry
  if v_payer is null then
    v_why := 'broke';
  else
$h$),
  (11, c_cut[5],
$h$    'yard', (select p.code from public.ports p where p.id = v_yard), 'cost', v_cost));
  perform public.treasury_post(v_home, 'REFIT', -v_cost, null, v_ev);
$h$,
$h$    'yard', (select p.code from public.ports p where p.id = v_yard), 'cost', v_cost, 'paid_by', (select p.code from public.ports p where p.id = v_payer)));   -- 0415: who paid
  perform public.treasury_post(v_payer, 'REFIT', -v_cost, null, v_ev);
$h$);
  for hk in select * from hunk_0415 order by ord loop
    v_def := replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, hk.old, ''))) / length(hk.old);
    if v_n <> 1 then
      raise exception '0415 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', hk.ord, hk.fn, v_n;
    end if;
    execute replace(v_def, hk.old, hk.new);
    v_def := replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, hk.new, ''))) / length(hk.new) <> 1 then
      raise exception '0415 self-assert FAIL: hunk % of % is not in the new body once', hk.ord, hk.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = hk.fn::regprocedure) <> (select p.meta from pre_0415 p where p.fn = hk.fn) then
      raise exception '0415 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', hk.fn;
    end if;
  end loop;
  for hk in select p.fn, p.def from pre_0415 p loop
    v_def := replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0415 x where x.fn = hk.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> hk.def then
      raise exception '0415 self-assert FAIL: % does not reverse to its pre-image', hk.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0415 self-assert FAIL: another function moved';
  end if;
  if exists (select 1 from unnest(c_new) f join pg_proc p on p.oid = f::regprocedure
              where not p.prosecdef or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')) then
    raise exception '0415 self-assert FAIL: a new function is not server-only';
  end if;

  -- ── 5. THE NEWS (0347's law) ──
  perform public.news_update('0415', 'Pirates trade as well as raid', '해적도 약탈하며 교역한다');

  -- ── 6. THE PROBE, rolled back by a raised sentinel. The switches lit INSIDE THE PROBE ONLY. It reads and writes only the rows it names.
  --      (a) one pirate ship (a roster fleet built here, or one lying docked that nobody holds): her house's purse emptied, the gift's own body gives her her capital (or she waits, nothing written);
  --          with the purse of the harbour she is bound for at nothing she plans nothing; with it rich every planned parcel is within it and within what she holds above the broke line; she buys it and is not broke.
  --      (b) one merchant fleet wrecked with her home's purse emptied: another city of her country pays and she is mended; with a cost no city has, nobody pays (she would wait).
  begin
    update public.world_config set value = 'true'::jsonb
     where key in ('pirates_bite', 'city_treasury_enabled', 'npc_refits_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;
    if v_cap is not null and public.pirates_on() then
      update public.port_treasury t set ducats = greatest(t.ducats, ceil(5000000 / public.wc_num('pirate_spend_day_pct'))::bigint) where t.port_id = v_cap;   -- the probe's own hoard: a day's room of 5,000,000 whatever the clock (the room is a rate per real day the clock's door moves, 0413)
      select r.ord into v_n from public.pirate_roster r
       where not exists (select 1 from public.pirate_ships n where n.ord = r.ord) and (select sum(x.n) from public.pirate_roster_hulls x where x.ord = r.ord) = 1
         and not exists (select 1 from public.pirate_roster q join public.pirate_ships n on n.ord = q.ord where q.hub_port = r.hub_port and q.house = r.house)
       order by r.ord limit 1;
      if v_n is not null then
        delete from public.pirate_spend_day d where d.day = (v_now at time zone 'UTC')::date;
        v_fleet := public.pirate_commission_fleet(v_n, public.refit_yard((select r.hub_port from public.pirate_roster r where r.ord = v_n)), v_now);
      end if;
      if v_fleet is null then
        select f.id into v_fleet from public.fleets f join public.pirate_ships n on n.fleet_id = f.id
         where f.status = 'DOCKED' and n.laid_up_at is null and f.port_id is not null order by n.ord limit 1 for update of f skip locked;
      end if;
    end if;
    if v_fleet is not null then
      select f.player_id, f.port_id into v_house, v_from from public.fleets f where f.id = v_fleet;
      select case when n.home_port = v_from then (select h.port_id from public.pirate_haunt_of(n.home_port, n.ord) h) else n.home_port end into v_to
        from public.pirate_ships n where n.fleet_id = v_fleet;
      v_capital := public.pirate_house_capital(v_house);
      v_keep := ceil(v_capital * public.wc_num('merchant_broke_pct'));   -- the broke line: what she never spends on cargo
      if v_capital <= 0 or v_capital <> 2 * (select sum(public.npc_refit_cost(n.fleet_id)) from public.pirate_ships n where n.player_id = v_house) then
        raise exception '0415 self-assert FAIL (probe): her capital is %, not twice the refit of her ships', v_capital;
      end if;
      -- the gift, at an instant the live world's books have not reached
      update public.players set ducats = 0 where id = v_house;
      if exists (select 1 from public.capital_gift_roster(v_far, null) g where g.player_id = v_house) then
        raise exception '0415 self-assert FAIL (probe): the house of a pirate ship is on the merchants'' hourly roster';
      end if;
      if not exists (select 1 from public.capital_gift_roster(v_far, v_house) g where g.capital = v_capital) then
        raise exception '0415 self-assert FAIL (probe): a pirate ship''s house with an empty purse is not on the roster when asked for alone';
      end if;
      v_r := public.capital_gift_one(v_far, v_house);
      if (v_r ->> 'gifted')::int = 1 and (v_r ->> 'failed')::int = 0 then
        if (select pl.ducats from public.players pl where pl.id = v_house) <> v_capital
           or (select count(*) from public.capital_gifts g where g.player_id = v_house and g.created_at = v_far and g.ducats = v_capital) <> 1
           or coalesce((select d.spent from public.pirate_spend_day d where d.day = (v_far at time zone 'UTC')::date), 0) <> v_capital
           or exists (select 1 from public.capital_gift_roster(v_far, v_house) g) then
          raise exception '0415 self-assert FAIL (probe): her gift is not her capital once, written to the day''s spend, and she off the roster after: %', v_r;
        end if;
        v_note_b := format('a pirate ship''s house with an empty purse was given her capital of %s d. (one gift row, the day''s spend up by it, off the roster after)', v_capital);
      elsif (v_r ->> 'gifted')::int = 0 and (v_r ->> 'failed')::int = 0 and (v_r ->> 'gift_waiting')::int = 1 then
        if exists (select 1 from public.capital_gifts g where g.player_id = v_house and g.created_at = v_far) or (select pl.ducats from public.players pl where pl.id = v_house) <> 0 then
          raise exception '0415 self-assert FAIL (probe): no pirate purse could pay her and something was written: %', v_r;
        end if;
        v_note_b := 'a pirate ship''s house was on the roster when asked for alone; no pirate purse could pay her at this instant: she waits, nothing written';
        update public.players set ducats = v_capital where id = v_house;   -- the probe goes on with the purse the gift would have left
      else
        raise exception '0415 self-assert FAIL (probe): her turn in the gift answered %', v_r;
      end if;
      -- the plan and the doors
      if v_to is not null then
        insert into public.treasury_flows (port_id, kind, ducats) select t.port_id, 'REFIT', -(public.treasury_balance(t.port_id)) from public.port_treasury t where t.port_id = v_to and public.treasury_balance(t.port_id) > 0;
        if public.pirate_cargo_plan(v_fleet, v_to) <> '[]'::jsonb then
          raise exception '0415 self-assert FAIL (probe): with the purse of the harbour she is bound for at nothing she plans %', public.pirate_cargo_plan(v_fleet, v_to);
        end if;
        update public.port_treasury t set ducats = t.ducats + 50000 where t.port_id = v_to;
        v_plan := public.pirate_cargo_plan(v_fleet, v_to);
        if coalesce((select sum((x ->> 'due')::numeric) from jsonb_array_elements(v_plan) x), 0) > 50000
           or coalesce((select sum((x ->> 'cost')::numeric) from jsonb_array_elements(v_plan) x), 0) > v_capital - v_keep
           or exists (select 1 from jsonb_array_elements(v_plan) x where (x ->> 'net')::numeric <= 0) then
          raise exception '0415 self-assert FAIL (probe): a plan past the purse of the harbour she is bound for (50,000), past what she holds above the broke line (%), or with a parcel that does not pay: %', v_capital - v_keep, v_plan;
        end if;
        v_purse := (select pl.ducats from public.players pl where pl.id = v_house);
        v_r := public.pirate_trade(v_fleet, v_to, v_now);
        if v_r is null or (select pl.ducats from public.players pl where pl.id = v_house) < v_keep
           or (v_n is not null and v_purse - (select pl.ducats from public.players pl where pl.id = v_house) <> coalesce((v_r ->> 'bought')::bigint, 0))
           or coalesce((v_r ->> 'bought')::bigint, 0) > coalesce((select sum((x ->> 'cost')::numeric) from jsonb_array_elements(v_plan) x), 0) then
          raise exception '0415 self-assert FAIL (probe): her trade answered % (purse % then %, cargo at cost %, the broke line %)', v_r, v_purse, (select pl.ducats from public.players pl where pl.id = v_house), public.fleet_stock_at_cost(v_fleet), v_keep;
        end if;
        update public.world_config set value = 'false'::jsonb where key = 'pirates_trade';
        if public.pirate_trade(v_fleet, v_to, v_now) is not null then
          raise exception '0415 self-assert FAIL (probe): with pirates_trade false she still trades';
        end if;
        v_note_a := format('a pirate ship planned nothing for a harbour with no purse, %s parcel(s) within a purse of 50,000 and within what she holds above the broke line, and her trade through the doors answered %s', jsonb_array_length(v_plan), v_r);
      end if;
    end if;

    -- (b) a merchant wrecked, her home's purse emptied
    v_fleet := null;
    for hk in select f.id, h.home_port_id, cp.id as cap
                from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.npc_houses h on h.player_id = f.player_id
                join public.players pl on pl.id = f.player_id join public.nations na on na.id = pl.nation_id
                join public.ports cp on cp.code = na.capital_port_code and cp.kind = 'HARBOUR'
               where f.status = 'DOCKED' and cp.id <> h.home_port_id and exists (select 1 from public.ships s where s.fleet_id = f.id)
               order by h.roster_ord limit 12 for update of f skip locked loop
      continue when public.pirate_power(public.port_nation(hk.cap)) or public.port_nation(hk.cap) is distinct from (select pl.nation_id from public.fleets f join public.players pl on pl.id = f.player_id where f.id = hk.id)
                    or public.refit_yard(hk.home_port_id) is null or public.refit_yard(hk.home_port_id) = hk.cap;
      v_fleet := hk.id;
      v_home := hk.home_port_id;
      exit;
    end loop;
    if v_fleet is not null and public.npc_refits_on() then
      update public.ships s set durability = 0 where s.fleet_id = v_fleet;
      update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_fleet;
      insert into public.treasury_flows (port_id, kind, ducats) select t.port_id, 'REFIT', -(public.city_surplus(t.port_id)) from public.port_treasury t where t.port_id = v_home and public.city_surplus(t.port_id) > 0;
      update public.port_treasury t set ducats = t.ducats + 100000000
       where t.port_id = (select cp.id from public.fleets f join public.players pl on pl.id = f.player_id join public.nations na on na.id = pl.nation_id
                            join public.ports cp on cp.code = na.capital_port_code where f.id = v_fleet);
      if public.npc_refit_payer(v_fleet, v_home, 1000000000000000, v_now) is not null then
        raise exception '0415 self-assert FAIL (probe): a refit no city can pay found a payer';
      end if;
      v_payer := public.npc_refit_payer(v_fleet, v_home, public.npc_refit_cost(v_fleet), v_now);
      v_s := public.npc_refit_step(v_fleet, v_now);
      if v_s <> 'PAID' or v_payer is null or v_payer = v_home or exists (select 1 from public.ships s where s.fleet_id = v_fleet and s.durability <= 0)
         or (select f.status from public.fleets f where f.id = v_fleet) <> 'DOCKED' or exists (select 1 from public.npc_refit_waits w where w.fleet_id = v_fleet) then
        raise exception '0415 self-assert FAIL (probe): a merchant wrecked with her home''s purse empty answered % (payer %), not PAID by another city of her country and whole', v_s, v_payer;
      end if;
      v_note_c := 'a merchant wrecked with her home''s purse emptied was mended, paid for by ' || (select p.code from public.ports p where p.id = v_payer) || '; a refit no city can pay finds no payer';
    end if;
    raise exception using errcode = 'ZP415', message = 'probe done';
  exception when sqlstate 'ZP415' then
    null;
  end;
  if public.wc('pirates_trade') is distinct from 'true'::jsonb or exists (select 1 from public.capital_gifts g where g.created_at = v_far) then
    raise exception '0415 self-assert FAIL: the probe was not rolled back';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0415 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0415 self-assert ok: A PIRATE SHIP TRADES AS WELL AS RAIDS; THE PIRATE CITIES FUND A PIRATE WITH AN EMPTY PURSE; NO WRECK WAITS ON ONE EMPTY PURSE. Eleven hunks over five bodies, each once and reversing; grants and volatility unmoved; no other function moved; six new functions, server-only. Probe: %; %; %. % ms.',
    v_note_a, v_note_b, v_note_c, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
