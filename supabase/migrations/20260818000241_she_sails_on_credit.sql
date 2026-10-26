-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0241 — SHE SAILS ON CREDIT
--        (owner row 230: while the economy is closed, money never stops a voyage. The stores a SAIL buys for its own
--         leg, and the dock fee at the harbour she makes, are paid from her purse as far as it goes; the rest is OWED
--         to the city that supplied or charged her, and paid out of her next sale — any sale, anywhere. A company
--         still short after selling (or after making port) is given her starting money by her country's capital —
--         players too now, not only merchants — and the gift pays what she owes first.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 230, 2026-10-26) ────────────────────────────
--   "right now i cannot move to a location because i have no money for supplies and wages. These fees will have to be
--    paid when things are sold. If sold and don't have money due to these fees, you will receive donation from your
--    capital."
--
-- ── WHAT STOPPED HIM (prod, read-only, 2026-10-26 ~08:20 UTC, head 0240) ─────────────────────────
--   Purse 0, Gaivota docked at Banten with 45,085 of cargo at cost, 267 owed to Banten in dock fees. Every SAIL runs
--   cmd.do_sail → cmd.do_provision (0225) for the leg's stores, and do_provision refused E_INSUFFICIENT_FUNDS
--   ("the purse will not cover the stores"). Merchants hit the same refusal (two failed SAILs at 08:07 UTC).
--   WAGES NEVER STOPPED A SAIL: since 0128 a sea-day's wage is OWED (public.fleet_wages) and paid only out of a sale's
--   profit (public.pay_wages) — the owner's own rule ("pay wages only when a profit is made"). That ledger is left as
--   it is: folding it into the debts below would change who is paid when, and it already never refuses.
--
-- ── ONE DEBT LEDGER ─────────────────────────────────────────────────────────────────────────────
--   public.port_fee_debts (0237) BECOMES the one ledger of what a company owes a city: a `kind` column (PORT_FEE,
--   PROVISION) joins the key (player, port, kind). Not renamed: its two readers are re-cut here, nothing else reads it.
--   * public.debt_owe(player, port, kind, ducats, at) — THE one writer of owing (port_call's dock fee, do_provision's
--     stores).
--   * public.port_fee_collect(player, port, net) — THE one payer of debts, re-cut whole: every debt of hers, this
--     port's first, then the oldest, up to the net given and her purse, each paid to the city it is owed to under its
--     own kind (pay_city: her ledger −, that city's flow +). Called by cmd.do_sell (the sale's net) and by the gift
--     pass (the gift).
--   Nothing is created: an owed ducat is not money — the city has not been paid, and is paid when she pays.
--
-- ── WHERE CREDIT IS GIVEN ───────────────────────────────────────────────────────────────────────
--   public.credit_on(port) — economy closed AND the purses lit AND a harbour with a purse. Only then, and only for the
--   stores a SAIL buys itself (cmd.do_sail passes on_credit; a PROVISION she orders herself still refuses — decided
--   by default: credit for the voyage, not a shop on tick). Open, every path is what it was.
--
-- ── THE CAPITAL HELPS PLAYERS TOO ───────────────────────────────────────────────────────────────
--   public.capital_gift_pass (0234/0236) gains a second kind of company: a PLAYER's, but only when the pass is asked
--   for her alone (p_only) — the hourly pass stays merchants-only, so no idle account is paid. Her "capital" is the
--   starting money (starting_ducats, 8,000); she is broke when public.player_worth (purse + cargo at cost − what she
--   owes) is under merchant_broke_pct (20 %) of it. Same cooldown (24 h), same weekly cap (3), same payer
--   (public.capital_pays: her country's capital, the realm's call if short), same rows (capital_gifts, CAPITAL_GIFT
--   event and ledger). public.player_gift(player, now) asks it — after every sale of hers (cmd.do_sell) and every
--   harbour she makes (public.port_call; with an empty hold she could never sell to be helped). After any gift, to a
--   merchant or a player, the gift pays what she owes first.
--
-- ── THE READS ───────────────────────────────────────────────────────────────────────────────────
--   world.player gains `owed` (Σ her debts, when > 0) and `on_credit` (true while credit is lit) — neither while the
--   economy is open and she owes nothing, so a dark read is byte for byte. cmd.do_sail's answer (and so the SAIL
--   preview's estimate) gains `on_credit` (what this SAIL's stores left owed, when > 0). cmd.do_sell's answer gains
--   `debt_paid` and `gift` (when > 0).
--
-- ── HUNKS SLICED FROM THE LIVE BODIES (prod head 0240, LF-normalised; each asserted to occur exactly once and to
--    reverse to its pre-image; ACL / volatility / definer / config unchanged) ────────────────────────────────────
--   cmd.do_provision ×4        v_owed; the refusal spares a SAIL's stores on credit; pay what the purse covers; owe
--                              the rest and answer on_credit
--   cmd.do_sail ×3             v_prov; the SAIL's stores bought on_credit; on_credit in the answer
--   cmd.do_sell ×3             v_debt / v_gift; the debts paid, then the capital's help; debt_paid / gift in the answer
--   public.port_call ×2        the owed fee through debt_owe; the capital's help at the harbour she makes
--   public.port_fee_collect ×1 the whole body: every debt, not only this harbour's fee
--   public.capital_gift_pass ×2 players' companies (p_only); the gift pays her debts first
--   world.player ×1            owed / on_credit
--
-- ── WHAT IT SELF-ASSERTS (probe rows only; flows counted are above a mark taken in-block AND at this transaction's
--    now(); every probe in a sub-transaction, rolled back, asserted) ──────────────────────────────────────────────
--   (a) the hunks reverse; ACL / volatility / definer / config unmoved; the new functions server-only; the debts table
--       still holds no client grant; registry unchanged; walls 0.
--   (b) DARK (economy open, purses lit): a broke Portuguese probe company at Lisbon is refused her SAIL with
--       E_INSUFFICIENT_FUNDS (the preview too), nothing is owed, world.player serves neither key.
--   (c) LIT (economy closed): the preview passes with on_credit; the SAIL leaves, her stores owed to Lisbon
--       (PROVISION); she makes Funchal with her dock fee owed (PORT_FEE) and no gift (her cargo is worth plenty);
--       world.player serves owed and on_credit; she sells — Funchal's fee first, then Lisbon's stores, out of the net;
--       still short (the stores priced ×10,000 in-probe, so the debt outruns the sale), Lisbon gives her 8,000, one
--       capital_gifts row and one CAPITAL_GIFT event, and the gift pays what she still owes; a second ask gives nothing
--       (cooldown). CLOSED: every ducat the probe moved sums to zero (her ledger + the cities' flows) — nothing created.
--   No growing table is counted; nothing DELETEd from an append-only table; no `set role`; no tick is RUN; nothing
--   reads the hour of day.
-- ROLLBACK (forward): reverse the sixteen hunks (each OLD text is here verbatim); drop the six functions; restore the
--   key (player, port) after folding each company's kinds per port; drop `kind`. Or the switch off: every path dark.
-- VERSION: 0241 = prod head 0240 + 1. Deploys first; other in-flight slices renumber after it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.mint_guard(text,bigint)') is null or to_regclass('public.port_fee_debts') is null
     or to_regprocedure('public.capital_gift_pass(timestamptz,uuid)') is null then
    raise exception '0241 refuses: 0237 / 0234 / 0240 (E4b, E4, E7) is not in this world';
  end if;
  if to_regprocedure('public.debt_owe(uuid,uuid,text,bigint,timestamptz)') is not null then
    raise exception '0241 refuses: public.debt_owe already exists — this has been applied once';
  end if;
  if not exists (select 1 from pg_constraint c where c.conrelid = 'public.port_fee_debts'::regclass
                    and c.conname = 'port_fee_debts_pkey' and c.contype = 'p') then
    raise exception '0241 refuses: port_fee_debts has no key port_fee_debts_pkey';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0241(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0241 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('cmd.do_provision(uuid,jsonb)'),
               ('cmd.do_sail(uuid,jsonb)'),
               ('cmd.do_sell(uuid,jsonb)'),
               ('public.port_call(uuid,uuid,uuid,timestamptz,timestamptz,uuid)'),
               ('public.port_fee_collect(uuid,uuid,bigint)'),
               ('public.capital_gift_pass(timestamptz,uuid)'),
               ('world.player()')) f(fn);

create temp table before_0241 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- ── 1. THE ONE DEBT LEDGER ──────────────────────────────────────────────────────────────────────
alter table public.port_fee_debts
  add column kind text not null default 'PORT_FEE' check (kind in ('PORT_FEE', 'PROVISION'));
alter table public.port_fee_debts drop constraint port_fee_debts_pkey;
alter table public.port_fee_debts add primary key (player_id, port_id, kind);
comment on table public.port_fee_debts is
  '0237 / 0241: THE one ledger of what a company owes a city — the dock fee (PORT_FEE) and the stores her SAIL bought (PROVISION) her purse could not cover. Paid out of her next sale (any sale) or a capital''s gift, to the city it is owed to (public.port_fee_collect). One writer each way: public.debt_owe (owed), public.port_fee_collect (paid). Server-only.';
comment on column public.port_fee_debts.kind is
  '0241: what is owed for — PORT_FEE (0237) or PROVISION (a SAIL''s stores on credit). The kind the city is paid under.';

-- ── 2. THE NEW FUNCTIONS ────────────────────────────────────────────────────────────────────────
create function public.credit_on(p_port uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0241 (owner row 230): may a cost here go on credit? The economy closed, the purses lit, a harbour with a purse.
  select public.economy_closed() and public.city_treasury_on()
     and exists (select 1 from public.port_treasury t join public.ports p on p.id = t.port_id
                  where t.port_id = p_port and p.kind = 'HARBOUR')
$$;
comment on function public.credit_on(uuid) is
  '0241: true when a cost at this harbour may be owed instead of refused (economy closed, purses lit, a harbour with a purse). Server-only.';
revoke all on function public.credit_on(uuid) from public, anon, authenticated;

create function public.debt_owe(p_player uuid, p_port uuid, p_kind text, p_ducats bigint, p_at timestamptz default now())
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0241: THE one writer of owing — company p_player owes city p_port p_ducats for p_kind (PORT_FEE, PROVISION). Added
-- to what she already owes it for that kind. Nothing moves: the city is paid when she pays (public.port_fee_collect).
-- Answers what she now owes it for that kind (0 when nothing was owed).
declare
  v_n bigint;
begin
  if coalesce(p_ducats, 0) <= 0 or p_player is null or p_port is null then
    return 0;
  end if;
  insert into public.port_fee_debts as d (player_id, port_id, kind, ducats, updated_at)
  values (p_player, p_port, p_kind, p_ducats, coalesce(p_at, now()))
  on conflict (player_id, port_id, kind) do update set ducats = d.ducats + excluded.ducats, updated_at = excluded.updated_at
  returning d.ducats into v_n;
  return v_n;
end $$;
comment on function public.debt_owe(uuid, uuid, text, bigint, timestamptz) is
  '0241: the one writer of a company''s debt to a city (dock fee, a SAIL''s stores). Server-only.';
revoke all on function public.debt_owe(uuid, uuid, text, bigint, timestamptz) from public, anon, authenticated;

create function public.company_owed(p_player uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0241: Σ what company p_player owes every city (public.port_fee_debts).
  select coalesce(sum(d.ducats), 0)::bigint from public.port_fee_debts d where d.player_id = p_player
$$;
comment on function public.company_owed(uuid) is '0241: what a company owes all cities together. Server-only.';
revoke all on function public.company_owed(uuid) from public, anon, authenticated;

create function public.player_worth(p_player uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0241: a player's company's worth for the capital's help — her purse, the cargo in all her fleets' holds at what it
  -- cost (public.fleet_stock_at_cost, as npc_worth counts it), less what she owes the cities.
  select coalesce((select pl.ducats from public.players pl where pl.id = p_player), 0)
       + coalesce((select sum(public.fleet_stock_at_cost(f.id)) from public.fleets f where f.player_id = p_player), 0)::bigint
       - public.company_owed(p_player)
$$;
comment on function public.player_worth(uuid) is
  '0241: purse + cargo at cost − debts: a player''s company is broke when this is under merchant_broke_pct × starting_ducats. Server-only.';
revoke all on function public.player_worth(uuid) from public, anon, authenticated;

create function public.player_gift(p_player uuid, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0241 (owner row 230): "If sold and don't have money due to these fees, you will receive donation from your capital."
-- A PLAYER's company that is broke now (public.player_worth under the line) is asked for by the capital's gift pass,
-- for her alone (public.capital_gift_pass p_only — its rules: 24 h cooldown, 3 a week, her capital pays). Null while
-- the economy is open, for a merchant (the hourly pass is hers), or when nothing was given; else {gift: ducats}.
declare
  v jsonb;
begin
  if p_player is null or not public.economy_closed() or not public.city_treasury_on()
     or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return null;
  end if;
  v := public.capital_gift_pass(p_now, p_player);
  if coalesce((v->>'gifted')::int, 0) > 0 then
    return jsonb_build_object('gift', (v->>'gift_ducats')::bigint);
  end if;
  return null;
end $$;
comment on function public.player_gift(uuid, timestamptz) is
  '0241: a broke player''s company is helped by her capital (capital_gift_pass for her alone). Called by cmd.do_sell and public.port_call. Server-only.';
revoke all on function public.player_gift(uuid, timestamptz) from public, anon, authenticated;

create function public.company_debt_key(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0241: world.player's keys — `owed` (Σ her debts, when > 0) and `on_credit` (true while credit is lit). '{}' while
  -- the economy is open and she owes nothing, so a dark read is the read it always was.
  select case when o.n > 0 then jsonb_build_object('owed', o.n) else '{}'::jsonb end
      || case when public.economy_closed() and public.city_treasury_on() then jsonb_build_object('on_credit', true) else '{}'::jsonb end
    from (select public.company_owed(p_player) as n) o
$$;
comment on function public.company_debt_key(uuid) is '0241: {owed, on_credit} for world.player. Server-only.';
revoke all on function public.company_debt_key(uuid) from public, anon, authenticated;

-- ── 3. THE HUNKS (each occurs exactly once in the live body) ─────────────────────────────────────
create temp table hunks_0241 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0241 values
-- cmd.do_provision
('cmd.do_provision(uuid,jsonb)', 1,
$h$  v_tf     numeric;   -- 0150: food
$h$,
$h$  v_tf     numeric;   -- 0150: food
  v_owed   bigint := 0;   -- 0241: what a SAIL's stores leave owed to this city (public.debt_owe)
$h$),
('cmd.do_provision(uuid,jsonb)', 2,
$h$  if v_purse < v_cost then
    perform cmd.refuse('E_INSUFFICIENT_FUNDS', 'the purse will not cover the stores',
$h$,
$h$  -- 0241 (owner row 230): SHE SAILS ON CREDIT — the stores a SAIL buys for its own leg (args.on_credit, set by
  -- cmd.do_sail only) are never refused for money where credit is lit (public.credit_on): what the purse cannot cover
  -- is owed to this city and paid out of her next sale. A PROVISION she orders herself still refuses.
  if v_purse < v_cost and coalesce((p_args->>'on_credit')::boolean, false) and public.credit_on(f.port_id) then
    v_owed := v_cost - greatest(coalesce(v_purse, 0), 0);
  end if;
  if v_purse < v_cost and v_owed = 0 then
    perform cmd.refuse('E_INSUFFICIENT_FUNDS', 'the purse will not cover the stores',
$h$),
('cmd.do_provision(uuid,jsonb)', 3,
$h$  perform public.pay_city(f.player_id, f.port_id, 'PROVISION', v_cost,
    public.emit_event(f.player_id, 'PROVISIONED', jsonb_build_object(
      'fleet', f.name, 'water_t', v_water, 'food_t', v_food, 'cost', v_cost)
$h$,
$h$  -- 0241: what the purse covers is paid now; the rest (v_owed) is owed below
  perform public.pay_city(f.player_id, f.port_id, 'PROVISION', v_cost - v_owed,
    public.emit_event(f.player_id, 'PROVISIONED', jsonb_build_object(
      'fleet', f.name, 'water_t', v_water, 'food_t', v_food, 'cost', v_cost)
      || case when v_owed > 0 then jsonb_build_object('on_credit', v_owed) else '{}'::jsonb end
$h$),
('cmd.do_provision(uuid,jsonb)', 4,
$h$  return jsonb_build_object('water_t', v_water, 'food_t', v_food, 'cost', v_cost,
                            'endurance_days', round(voyage.endurance_days(p_fleet), 1));
$h$,
$h$  if v_owed > 0 then
    perform public.debt_owe(f.player_id, f.port_id, 'PROVISION', v_owed, now());   -- 0241: owed to this city
  end if;
  return jsonb_build_object('water_t', v_water, 'food_t', v_food, 'cost', v_cost,
                            'endurance_days', round(voyage.endurance_days(p_fleet), 1))
      || case when v_owed > 0 then jsonb_build_object('on_credit', v_owed) else '{}'::jsonb end;
$h$),
-- cmd.do_sail
('cmd.do_sail(uuid,jsonb)', 1,
$h$  v_need   record;    -- 0225: what the leg asks of her stores (public.supply_need)
$h$,
$h$  v_need   record;    -- 0225: what the leg asks of her stores (public.supply_need)
  v_prov   jsonb;     -- 0241: what the stores' purchase answered (on_credit: what it left owed)
$h$),
('cmd.do_sail(uuid,jsonb)', 2,
$h$      perform cmd.do_provision(p_fleet, jsonb_build_object('mode', 'DAYS', 'days', v_need.days));
$h$,
$h$      -- 0241 (owner row 230): ON CREDIT — where credit is lit, money never stops the stores of her own leg
      v_prov := cmd.do_provision(p_fleet, jsonb_build_object('mode', 'DAYS', 'days', v_need.days, 'on_credit', true));
$h$),
('cmd.do_sail(uuid,jsonb)', 3,
$h$                            'insurance', public.insure_voyage(v_voyage, coalesce((p_args->>'insured')::boolean, false)));
$h$,
$h$                            'insurance', public.insure_voyage(v_voyage, coalesce((p_args->>'insured')::boolean, false)))
      -- 0241: what this SAIL's stores left owed (absent when nothing was)
      || case when (v_prov->>'on_credit') is not null then jsonb_build_object('on_credit', (v_prov->>'on_credit')::bigint) else '{}'::jsonb end;
$h$),
-- cmd.do_sell
('cmd.do_sell(uuid,jsonb)', 1,
$h$  v_demand  bigint;        -- 0174: the premium the city's people pay (IMPORT_DEMAND)
$h$,
$h$  v_demand  bigint;        -- 0174: the premium the city's people pay (IMPORT_DEMAND)
  v_debt    bigint := 0;   -- 0241: what this sale paid of her debts to the cities
  v_gift    jsonb;         -- 0241: her capital's help, when still short after the sale
$h$),
('cmd.do_sell(uuid,jsonb)', 2,
$h$  perform public.port_fee_collect(f.player_id, f.port_id, q.total - v_tax - v_wages);
$h$,
$h$  -- 0241: every debt of hers (this harbour's first, then the oldest), not only this harbour's fee.
  v_debt := public.port_fee_collect(f.player_id, f.port_id, q.total - v_tax - v_wages);
  -- 0241 (owner row 230): still short after selling → her capital gives her starting money (players; lit only).
  v_gift := public.player_gift(f.player_id, now());
$h$),
('cmd.do_sell(uuid,jsonb)', 3,
$h$                            'spread_total', q.spread_total, 'haggle_saved', q.haggle_saved);
$h$,
$h$                            'spread_total', q.spread_total, 'haggle_saved', q.haggle_saved)
      -- 0241: what the sale paid of her debts, and her capital's gift (absent when none)
      || case when v_debt > 0 then jsonb_build_object('debt_paid', v_debt) else '{}'::jsonb end
      || coalesce(v_gift, '{}'::jsonb);
$h$),
-- public.port_call
('public.port_call(uuid,uuid,uuid,timestamptz,timestamptz,uuid)', 1,
$h$      insert into public.port_fee_debts as d (player_id, port_id, ducats, updated_at)
      values (p_player, p_port, v_owed, p_now)
      on conflict (player_id, port_id) do update set ducats = d.ducats + excluded.ducats, updated_at = excluded.updated_at;
$h$,
$h$      perform public.debt_owe(p_player, p_port, 'PORT_FEE', v_owed, p_now);   -- 0241: the one writer of owing
$h$),
('public.port_call(uuid,uuid,uuid,timestamptz,timestamptz,uuid)', 2,
$h$  return jsonb_build_object('fee', v_fee, 'paid', v_pay, 'owed', v_owed, 'ready_at', v_ready);
$h$,
$h$  -- 0241 (owner row 230): broke when she makes port (an empty hold could never sell to be helped) → her capital gives.
  perform public.player_gift(p_player, p_now);
  return jsonb_build_object('fee', v_fee, 'paid', v_pay, 'owed', v_owed, 'ready_at', v_ready);
$h$),
-- public.port_fee_collect: the whole body
('public.port_fee_collect(uuid,uuid,bigint)', 1,
$h$-- 0237 (§4c): what company p_player owes harbour p_port is paid out of a sale there — up to the sale's net (p_net) and
-- her purse — to the city (PORT_FEE). Nothing owed (always, while the economy has never been closed): one key read,
-- nothing written. Answers the ducats taken.
declare
  v_debt bigint;
  v_take bigint;
begin
  select d.ducats into v_debt from public.port_fee_debts d where d.player_id = p_player and d.port_id = p_port for update;
  if v_debt is null or not public.city_treasury_on() then
    return 0;
  end if;
  v_take := least(v_debt, greatest(coalesce(p_net, 0), 0),
                  greatest(coalesce((select pl.ducats from public.players pl where pl.id = p_player), 0), 0));
  if v_take <= 0 then
    return 0;
  end if;
  perform public.pay_city(p_player, p_port, 'PORT_FEE', v_take, null);
  if v_take >= v_debt then
    delete from public.port_fee_debts d where d.player_id = p_player and d.port_id = p_port;
  else
    update public.port_fee_debts d set ducats = d.ducats - v_take, updated_at = now()
     where d.player_id = p_player and d.port_id = p_port;
  end if;
  return v_take;
end $function$
$h$,
$h$-- 0237 (§4c) / 0241 (owner row 230): THE one payer of a company's debts. Everything company p_player owes the cities
-- (public.port_fee_debts: dock fees, a SAIL's stores) is paid out of p_net — a sale's net, or a capital's gift — and
-- her purse, whichever is less: harbour p_port's first, then the oldest; each to the city it is owed to, under its own
-- kind (public.pay_city). Nothing owed: two reads, nothing written. Answers the ducats paid.
declare
  d      record;
  v_left bigint;
  v_take bigint;
  v_all  bigint := 0;
begin
  if not public.city_treasury_on()
     or not exists (select 1 from public.port_fee_debts x where x.player_id = p_player) then
    return 0;
  end if;
  select least(greatest(coalesce(p_net, 0), 0), greatest(coalesce(pl.ducats, 0), 0)) into v_left
    from public.players pl where pl.id = p_player for update;   -- the house first (pay_city's order)
  for d in select x.port_id, x.kind, x.ducats from public.port_fee_debts x
            where x.player_id = p_player
            order by (x.port_id is not distinct from p_port) desc, x.updated_at, x.port_id, x.kind
              for update loop
    exit when coalesce(v_left, 0) <= 0;
    v_take := least(d.ducats, v_left);
    perform public.pay_city(p_player, d.port_id, d.kind, v_take, null);
    if v_take >= d.ducats then
      delete from public.port_fee_debts x where x.player_id = p_player and x.port_id = d.port_id and x.kind = d.kind;
    else
      update public.port_fee_debts x set ducats = x.ducats - v_take, updated_at = now()
       where x.player_id = p_player and x.port_id = d.port_id and x.kind = d.kind;
    end if;
    v_left := v_left - v_take;
    v_all  := v_all + v_take;
  end loop;
  return v_all;
end $function$
$h$),
-- public.capital_gift_pass
('public.capital_gift_pass(timestamptz,uuid)', 1,
$h$      from public.npc_houses h
      join public.players pl on pl.id = h.player_id and pl.is_npc
      left join public.nations n on n.id = pl.nation_id
      left join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR'
      cross join lateral (select public.npc_worth(h.player_id) as worth) w
     where (p_only is null or h.player_id = p_only)
       and pl.ducats < h.capital * v_pct               -- 0236: BROKE = her purse (cash) under the line; cargo aboard does not count
$h$,
$h$      -- 0241 (owner row 230): A PLAYER'S COMPANY TOO, but only when asked for her alone (p_only — public.player_gift,
      -- after her sale or at the harbour she makes); the hourly pass stays merchants'. Her capital is the starting money.
      from (select nh.player_id, nh.capital, false as human from public.npc_houses nh
            union all
            select hp.id, public.wc_int('starting_ducats')::bigint, true from public.players hp
             where not hp.is_npc and p_only is not null and hp.id = p_only) h
      join public.players pl on pl.id = h.player_id and pl.is_npc = not h.human
      left join public.nations n on n.id = pl.nation_id
      left join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR'
      cross join lateral (select case when h.human then public.player_worth(h.player_id) else public.npc_worth(h.player_id) end as worth) w
     where (p_only is null or h.player_id = p_only)
       and pl.ducats < h.capital * v_pct               -- 0236: BROKE = her purse (cash) under the line; cargo aboard does not count
       and (not h.human or w.worth < h.capital * v_pct)   -- 0241: a player — her worth (purse + cargo − debts) under it too
$h$),
('public.capital_gift_pass(timestamptz,uuid)', 2,
$h$      v_d := v_d + r.capital;
$h$,
$h$      v_d := v_d + r.capital;
      perform public.port_fee_collect(r.player_id, null, r.capital);   -- 0241: the gift pays what she owes first
$h$),
-- world.player
('world.player()', 1,
$h$      'nation_change_at', public.nation_change_next_at(v_id)));
$h$,
$h$      'nation_change_at', public.nation_change_next_at(v_id))
      -- 0241 (owner row 230): what she owes the cities (`Owed 1,240`) and whether a SAIL may run on credit — neither
      -- while the economy is open and she owes nothing
      || public.company_debt_key(v_id));
$h$);

create or replace function pg_temp.recut_0241(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0241 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0241 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0241(v_def, h.old);
    if v_n <> 1 then
      raise exception '0241 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0241(fn) from defs_before_0241 order by fn;

-- ── 4. THE PROBE'S EYES ─────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.seen_0241(p_mark bigint, p_p uuid)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'flows', coalesce((select jsonb_agg(jsonb_build_array(p.code, f.kind, f.ducats) order by f.id)
                         from public.treasury_flows f join public.ports p on p.id = f.port_id
                        where f.id > p_mark and f.created_at = now() and f.kind <> 'PROBE_0241'), '[]'::jsonb),
    'flow_sum', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f
                  where f.id > p_mark and f.created_at = now() and f.kind not in ('PROBE_0241', 'FOUNDING')),
    'purse', (select pl.ducats from public.players pl where pl.id = p_p),
    'ledger_sum', (select coalesce(sum(l.ducats_delta), 0) from public.ledger l
                    where l.player_id = p_p and l.kind not in ('PROBE_0241', 'FOUNDING')),
    'debts', coalesce((select jsonb_agg(jsonb_build_array(p.code, d.kind, d.ducats) order by p.code, d.kind)
                         from public.port_fee_debts d join public.ports p on p.id = d.port_id where d.player_id = p_p), '[]'::jsonb),
    'gifts', coalesce((select jsonb_agg(jsonb_build_array(p.code, g.ducats)) from public.capital_gifts g
                         join public.ports p on p.id = g.port_id where g.player_id = p_p), '[]'::jsonb),
    'gift_events', (select count(*) from public.events e where e.player_id = p_p and e.kind = 'CAPITAL_GIFT'),
    'status', (select jsonb_build_array(f.status, p.code) from public.fleets f left join public.ports p on p.id = f.port_id
                where f.player_id = p_p))
$$;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0241-4000-8000-000000000001';
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  v_mark   bigint := (select coalesce(max(f.id), 0) from public.treasury_flows f);
  v_lis    uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_fnc    uuid := (select p.id from public.ports p where p.code = 'FNC' and p.kind = 'HARBOUR');
  v_good   uuid; v_gcode text;
  v_p      uuid; v_f uuid; v_voy uuid;
  v_course jsonb;
  v_res    jsonb;
  v_a      jsonb; v_c jsonb;
  v_fee    bigint;
  v_cost   bigint;
  v_n      numeric;
begin
  select * into v_before from before_0241;

  -- (a) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0241 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0241 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0241(v_def, v_h.new) <> 1 then
        raise exception '0241 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0241 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0241 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if exists (select 1 from (values ('public.credit_on(uuid)'), ('public.debt_owe(uuid,uuid,text,bigint,timestamptz)'),
                                   ('public.company_owed(uuid)'), ('public.player_worth(uuid)'),
                                   ('public.player_gift(uuid,timestamptz)'), ('public.company_debt_key(uuid)')) f(fn)
              where has_function_privilege('authenticated', f.fn, 'execute') or has_function_privilege('anon', f.fn, 'execute')) then
    raise exception '0241 self-assert FAIL: a client role can execute a server-only function';
  end if;
  if has_table_privilege('authenticated', 'public.port_fee_debts', 'select') or has_table_privilege('anon', 'public.port_fee_debts', 'select') then
    raise exception '0241 self-assert FAIL: a client role can read the debts';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0241 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0241 self-assert FAIL: a wall moved';
  end if;
  if v_lis is null or v_fnc is null
     or (select n.capital_port_code from public.nations n where n.code = 'PRT') is distinct from 'LIS' then
    raise exception '0241 self-assert FAIL: no Lisbon, no Funchal, or Lisbon is not Portugal''s capital';
  end if;

  -- (b)(c) A BROKE PORTUGUESE COMPANY AT LISBON
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled');
    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
    update public.world_config set value = '0'::jsonb where key = 'hazard_p_max';   -- a quiet passage: no lottery
    perform set_config('request.jwt.claim.sub', c_uid::text, true);
    v_p := public.new_house(c_uid, 'Casa do Credito 0241', 'PRT', 'LIS');
    select f.id into v_f from public.fleets f where f.player_id = v_p;
    select g.id, g.code into v_good, v_gcode from public.goods g join public.ports p on p.id = v_fnc
     where g.bulk = 1 and not public.culture_refuses(p.culture, g.culture_mask) order by g.code limit 1;
    -- 40 t at a dear cost: her cargo is worth far more than she will owe, so making port asks for no gift
    if public.fleet_load(v_f, v_gcode, 40, 1000000) <> 40 then
      raise exception '0241 self-assert FAIL: the probe''s 40 t of % did not load', v_gcode;
    end if;
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_f;   -- empty casks: the SAIL must buy her stores
    update public.world_config set value = to_jsonb(public.wc_num(key) * 10000)
     where key in ('provision_water_price', 'provision_food_price');          -- dear stores: the debt outruns the sale
    update public.port_treasury set reserve = 0 where port_id in (v_lis, v_fnc);
    perform public.treasury_post(v_lis, 'PROBE_0241', 10000000, null, null, true);
    perform public.treasury_post(v_fnc, 'PROBE_0241', 10000000, null, null, true);
    perform public.credit(v_p, 'PROBE_0241', -(select pl.ducats from public.players pl where pl.id = v_p));   -- purse 0
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_course
      from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc;

    -- (b) DARK: the economy open — the broke SAIL is refused as before
    begin
      v_a := jsonb_build_object('preview', cmd.preview(v_f, 'SAIL TO FNC', v_course));
      v_a := v_a || jsonb_build_object('player_keys', (world.player()->'player') ?| array['owed', 'on_credit']);
      begin
        perform cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'path', v_course));
        v_a := v_a || jsonb_build_object('sail', 'sailed');
      exception when others then
        v_a := v_a || jsonb_build_object('sail', sqlerrm);
      end;
      v_a := v_a || jsonb_build_object('seen', pg_temp.seen_0241(v_mark, v_p));
      raise exception using errcode = 'ZY241', message = v_a::text;
    exception when sqlstate 'ZY241' then
      v_a := sqlerrm::jsonb;
    end;

    -- (c) LIT: the economy closed
    update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
    v_c := jsonb_build_object('preview', cmd.preview(v_f, 'SAIL TO FNC', v_course));
    v_res := cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'path', v_course));
    v_voy := (v_res->>'voyage_id')::uuid;
    v_cost := (select (e.payload->>'cost')::bigint from public.events e where e.player_id = v_p and e.kind = 'PROVISIONED');
    v_c := v_c || jsonb_build_object('sail', v_res, 'cost', v_cost, 'sailed', pg_temp.seen_0241(v_mark, v_p));
    -- she landed 30 s ago (the whole passage moved back by one interval: its days keep their shape)
    update public.voyages vo
       set departed_at = vo.departed_at - (vo.eta - (now() - interval '30 seconds')), eta = now() - interval '30 seconds'
     where vo.id = v_voy;
    v_fee := public.port_fee(v_fnc, v_p, public.fleet_stock_at_cost(v_f));
    perform voyage.settle(v_f, now());
    v_c := v_c || jsonb_build_object('fee', v_fee, 'docked', pg_temp.seen_0241(v_mark, v_p), 'player', world.player()->'player');
    v_res := cmd.do_sell(v_f, jsonb_build_object('good', v_good));
    v_c := v_c || jsonb_build_object('sale', v_res, 'sold', pg_temp.seen_0241(v_mark, v_p),
                                     'player_after', world.player()->'player',
                                     'again', public.player_gift(v_p, now()));
    raise exception using errcode = 'ZX241', message = jsonb_build_object('a', v_a, 'c', v_c)::text;
  exception when sqlstate 'ZX241' then
    v_res := sqlerrm::jsonb;
    v_a := v_res->'a'; v_c := v_res->'c';
  end;

  -- (b) dark
  if v_a is null or (v_a->'preview'->>'ok')::boolean or v_a->'preview'->>'error_code' <> 'E_INSUFFICIENT_FUNDS'
     or position('E_INSUFFICIENT_FUNDS' in v_a->>'sail') <> 1
     or (v_a->>'player_keys')::boolean
     or v_a->'seen'->'debts' <> '[]'::jsonb or v_a->'seen'->'status' <> '["DOCKED", "LIS"]'::jsonb then
    raise exception '0241 self-assert FAIL: dark, a broke SAIL is not refused E_INSUFFICIENT_FUNDS as before (or a debt or key appeared): %', v_a;
  end if;

  -- (c) lit: the SAIL on credit
  if v_c->'sail'->>'voyage_id' is null or coalesce(v_c->>'cost', '0')::bigint <= 0
     or (v_c->'sail'->>'on_credit')::bigint is distinct from (v_c->>'cost')::bigint
     or not (v_c->'preview'->>'ok')::boolean
     or (v_c->'preview'->'estimate'->>'on_credit')::bigint is distinct from (v_c->>'cost')::bigint
     or v_c->'sailed'->'debts' <> jsonb_build_array(jsonb_build_array('LIS', 'PROVISION', (v_c->>'cost')::bigint))
     or (v_c->'sailed'->>'purse')::bigint <> 0 or v_c->'sailed'->'flows' <> '[]'::jsonb
     or v_c->'sailed'->'status'->>0 <> 'SAILING' then
    raise exception '0241 self-assert FAIL: lit, the broke SAIL did not leave with her stores owed to Lisbon: %', v_c;
  end if;
  -- (c) lit: making Funchal — the dock fee owed, no gift, the reads
  if coalesce((v_c->>'fee')::bigint, 0) <= 0
     or v_c->'docked'->'status' <> '["DOCKED", "FNC"]'::jsonb
     or v_c->'docked'->'debts' <> jsonb_build_array(jsonb_build_array('FNC', 'PORT_FEE', (v_c->>'fee')::bigint),
                                                     jsonb_build_array('LIS', 'PROVISION', (v_c->>'cost')::bigint))
     or v_c->'docked'->'gifts' <> '[]'::jsonb
     or (v_c->'player'->>'owed')::bigint <> (v_c->>'cost')::bigint + (v_c->>'fee')::bigint
     or not coalesce((v_c->'player'->>'on_credit')::boolean, false) then
    raise exception '0241 self-assert FAIL: lit, making Funchal did not owe the dock fee (or a gift was given with a full hold, or world.player is wrong): %', v_c;
  end if;
  -- (c) lit: the sale pays Funchal first, then Lisbon; still short → Lisbon gives 8,000, and the gift pays the debt
  v_n := (v_c->>'cost')::bigint + (v_c->>'fee')::bigint;   -- owed before the sale
  if (v_c->'sale'->>'qty')::numeric <> 40
     or (v_c->'sale'->>'debt_paid')::bigint is distinct from least(v_n, (v_c->'sale'->>'net')::bigint)
     or not (v_c->'sold'->'flows' @> jsonb_build_array(jsonb_build_array('FNC', 'PORT_FEE', least((v_c->>'fee')::bigint, (v_c->'sale'->>'net')::bigint))))
     or (v_c->'sale'->>'gift')::bigint <> public.wc_int('starting_ducats')
     or v_c->'sold'->'gifts' <> jsonb_build_array(jsonb_build_array('LIS', public.wc_int('starting_ducats')))
     or (v_c->'sold'->>'gift_events')::int <> 1
     or not (v_c->'sold'->'flows' @> jsonb_build_array(jsonb_build_array('LIS', 'CAPITAL_GIFT', -public.wc_int('starting_ducats'))))
     -- the gift paid what she still owed, up to itself: she owes n − (the sale's part) − (the gift's part)
     or coalesce((select sum((e->>2)::bigint) from jsonb_array_elements(v_c->'sold'->'debts') e), 0)
        <> v_n - (v_c->'sale'->>'debt_paid')::bigint
               - least(v_n - (v_c->'sale'->>'debt_paid')::bigint,
                       public.wc_int('starting_ducats') + (v_c->'sale'->>'net')::bigint - (v_c->'sale'->>'debt_paid')::bigint,
                       public.wc_int('starting_ducats'))
     or coalesce((v_c->'player_after'->>'owed')::bigint, 0)
        <> coalesce((select sum((e->>2)::bigint) from jsonb_array_elements(v_c->'sold'->'debts') e), 0)
     or v_c->'again' is distinct from 'null'::jsonb then
    raise exception '0241 self-assert FAIL: lit, the sale did not pay the debts first, or the capital''s gift (8,000, once, paying the debt) is wrong: %', v_c;
  end if;
  -- CLOSED: every ducat the probe moved, her ledger and the cities' flows, sums to zero
  if (v_c->'sold'->>'flow_sum')::numeric + (v_c->'sold'->>'ledger_sum')::numeric <> 0 then
    raise exception '0241 self-assert FAIL: the probe created or destroyed money: flows % + ledger % <> 0',
      v_c->'sold'->>'flow_sum', v_c->'sold'->>'ledger_sum';
  end if;

  -- nothing of the probe survives
  if exists (select 1 from public.players p where p.company_name = 'Casa do Credito 0241')
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now())
     or exists (select 1 from public.port_fee_debts d where d.player_id = v_p)
     or coalesce(current_setting('request.jwt.claim.sub', true), '') <> '' then
    raise exception '0241 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0241 self-assert ok: SHE SAILS ON CREDIT. Seven bodies re-cut by sixteen hunks (do_provision, do_sail, do_sell, port_call, port_fee_collect, capital_gift_pass, world.player), each reversed, ACL unmoved; six functions server-only; the debts table keyed (player, port, kind), no client grant; registry unchanged; walls 0. DARK: a broke company''s SAIL at Lisbon refused E_INSUFFICIENT_FUNDS as before, no debt, no new key. LIT: the preview and the SAIL passed, her stores (%) owed to Lisbon; at Funchal her dock fee (%) owed, no gift with a full hold; world.player owed %; the sale paid % of it (Funchal first); still short, Lisbon gave % and it paid the debt down to %; no second gift; the probe''s money summed to 0. Rolled back.',
    v_c->>'cost', v_c->>'fee', v_c->'player'->>'owed', v_c->'sale'->>'debt_paid', v_c->'sale'->>'gift',
    coalesce(v_c->'player_after'->>'owed', '0');
end $$;
