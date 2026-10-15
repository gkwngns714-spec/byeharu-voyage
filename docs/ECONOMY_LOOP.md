# ECONOMY_LOOP — the market is the city's purse; tax falls on profit only; cities build with investors' money

**Status: DESIGN v3, BUILD-READY (2026-10-15 late). Nothing in this file is built. No migration,
no code, no production change. Prod head is 0121 (`docs/RESUME.md:18`); this plan is 0122 and 0123.
Debt, aid, donations and war are designed but NOT scheduled — §12.**

The owner, 2026-10-15, verbatim: *"i want to economy to be circulative, meaning that there should be
a way for these merchants gold to be reduced, weather it is by investing in cities. Then cities
should have gold too, and the city must use it for the whole world and so on, any ideas?"*

**The owner's decisions, in the order they were taken (each later one overrides an earlier one):**

- Round 1 (approved): city treasuries; bounties for goods a city lacks; city spending on works;
  merchant investment in cities.
- Round 2: **limited money — the market IS the city's purse** (full conservation); **merchants pay
  full running costs (1.0)**; **"goods a city lacks" = only goods the city does not sell** (0087's
  rule, kept — nothing new built); debt with war / donations / NPC aid; **everyone may invest
  anywhere**.
- Round 3 (this version): **build only the purse (0122) and investment (0123) now; debt, aid,
  donations and war are deferred** (§12, kept). **A city cannot go below zero**: it buys only what it
  can pay for, and its buy price falls as its purse empties (§2.3). **Tax or any fee is paid only
  when a trade makes a profit** — tax on the profit of a sale, nothing on a loss or break-even
  (§2.2); merchants follow the same rule through the same body. **A Town Hall** joins Market | Port
  | Inn: the purse, the works, Invest, and who invested (§5). **The seed stays** ten game-days of
  what a harbour pays sellers, never under 20 k (§6).

Everything below is grounded in the live chain (`supabase/migrations/`, head 0121) and cites
`NNNN:line` (the file is `20260818000NNNN_*.sql`). Where a function has been re-cut by later slices,
the line cited is its last full definition and the slices are named; every migration here reads the
LIVE body with `pg_get_functiondef` (LF-normalised, the helper shape of 0114:606-619) and asserts
each hunk occurs exactly once before replacing it.

---

## 0. The answer in ten lines

1. **A city has one purse, `public.port_treasury.ducats` (CHECK ≥ 0, like a house's, 0004:54)**,
   and ONE mover, `public.treasury_post`. Nothing else writes a treasury.
2. **The market is that purse.** `cmd.do_buy`'s whole payment goes into the city and `cmd.do_sell`'s
   whole receipt comes out of it (0022:761, 0022:831 — one-line hunks). Wages, supplies, repairs,
   hire, building, tuition and officer wages are paid INTO the city where they happen. Nothing is
   destroyed anywhere.
3. **Tax falls on profit only.** The tax term leaves the ask and the bid (`world.quote` 0022:400 /
   :407 price tax-free once the switch is on). At a sale, `cmd.do_sell` — which already knows what
   the tuns cost and what the sale made (0081:312-314) — charges `round(profit × rate)` when the
   profit is positive, and nothing otherwise. No tax on a BUY, none on a loss, none on cargo whose
   cost is unknown, no harbour dues. Merchants pay it through the same body.
4. **A city buys only what it can pay for.** A sale shrinks to the whole steps the purse covers and
   is refused when it covers none (`E_CITY_BROKE`); the bid falls with the purse below its reserve
   (`city_bid_factor`, one reader), so merchants route around a thin purse before it is empty.
5. **Merchants pay 1.0** (`npc_cost_mult` 0 → 1; the one reader `public.running_cost_mult`,
   0114:92-103, untouched). Running costs are purchases, not fees: everyone pays them in full.
6. **Income is posted at the charge, never by a tick**: one INSERT into append-only `treasury_flows`,
   no treasury row lock on the trade path. **One hourly job, `byeharu-voyage:city` at :37**, rolls
   flows into balances and a daybook, computes each city's reserve, subscribes works, pays coupons,
   and asserts `balance = Σ daybook`.
7. **Refounds and bounties stop minting**: a merchant is refounded by her home harbour above its
   reserve (partially, or not at all); a request is escrowed at posting, for goods the city does not
   sell (0087:241), only when the surplus covers it.
8. **Works are built with other people's money.** A level of docks / market / production / inn is
   100 shares; houses buy them (players docked there, merchants at any stop of their loop from their
   surplus), the city subscribes the rest from its own surplus — paid to its region's other harbours
   (stone and timber from the coast), never burned. A level pays its holders a fixed coupon per
   game-day **out of what the city holds above its reserve** — a poor city skips its dividend; it
   never owes.
9. **The Town Hall** is the fourth building on the city panel: the purse, the works and what they
   offer, Invest, and the investors by name with amounts — one read, `world.town_hall(p_port)`.
10. **Dark first, seeded once.** `city_treasury_enabled` false (the 0092:124-129 shape). Flows post
    from day one; prices, tax, refounds, bounties and investment change only at
    `select public.city_treasury_switch(true)`, which seeds every harbour from its own first day of
    books and refuses to light a world that is arithmetically broke (§6).

---

## 1. The money as it moves today, and after

### 1.1 Every faucet and every sink on the live chain (head 0121)

Gold exists only as `players.ducats` (CHECK ≥ 0, 0004:54), moved only by `public.credit`
(0004:216-241: locks the player row :228, refuses an overdraft :233-236 — re-cut to `cmd.refuse`
by 0050:673-677 — writes one `ledger` row :238-239).

| Kind | Where | Direction | Counterparty today |
|---|---|---|---|
| `FOUNDING` | `new_house` 0004:300-302 → 0096:469-472 (`p_ducats`, `p_is_npc`); `starting_ducats` 8,000 | **faucet** | nothing. Each merchant at seeding: capital + officer wages + tuition (`npc_found` 0097:287-298) |
| `NPC_REFOUND` | `npc_tend` 0114:550-553 → sliced 0115:204-209: purse < capital × `npc_purse_floor_pct` (0.20, 0097:84) and no refound in `npc_refound_cooldown_game_days` (30) → `credit(house, 'NPC_REFOUND', capital − purse)` | **faucet** | nothing; one top-up per company per real day, unbounded (0115:22-23 deleted the weekly cap) |
| `SELL` | `cmd.do_sell` 0022:770-838 (sliced 0050, 0061, 0080-0083, 0096): `credit(SELL, +q.total)` :831. bid = mid × (1 − spread/2) × (1 − tax) (0022:407) | **faucet** | the market, an infinite purse |
| `PREMIUM` | `cmd.run_fulfil` 0087:445-449 | **faucet** | nothing (8–20 % of mid × qty, 0087:172-175) |
| `BUY` | `cmd.do_buy` 0022:674-768 (sliced 0050, 0061, 0080-0083, 0096): `credit(BUY, −q.total)` :761; ask = mid × (1 + tax + spread/2) (0022:400) | **sink** | the market |
| `WAGES` | `voyage.settle` 0027:299-308 → 0086:162-169 → 0114:622-630 (`× running_cost_mult`): `−least(wages, purse)` per settled sea-day (0027:306-307) | sink | nothing. **Merchants pay 0 since 0116:40-44** |
| `PROVISION` / `REPAIR` / `HIRE` / `BUILD` / `TUITION` / `OFFICER_WAGE` | 0017:327-329 / 0007:751-753 / 0007:689-692 / 0072:269-271 / 0016:235-241 / 0096:562-568 | sink | nothing (merchants pay 0 of the first two) |
| harbour dues | `port_fee_per_ship` 50 (0001:166) | — | **read by nothing** — and stays so (§2.2) |
| pirates | `voyage.settle` 0027:340-351: `RANSOM` costs 0; `PLUNDERED` leaves the cargo | — | no money moves |

Transfers between purses: **none**. Every movement is a house against the void.

### 1.2 After this plan: one closed loop

```
  FOUNDING (new player, 8,000)        SEED (once, at the switch — §6)
            │                                   │
            ▼                                   ▼
   ┌────────────────────┐   BUY (whole ask, no tax) · TAX (on a sale's profit) · WAGES (the leg, at arrival) ·
   │  players.ducats    │   PROVISION · REPAIR · HIRE · BUILD · TUITION · OFFICER_WAGE · SHARE   ────▶  ┌──────────────────────┐
   │  merchants+players │                                                                               │ port_treasury.ducats │
   │                    │ ◀──────────  SELL (whole bid) · REFOUND · PREMIUM (escrowed at posting) ·     │ 237 harbours, ≥ 0    │
   └────────────────────┘              DIVIDEND (coupon, from the surplus)                              └──────────┬───────────┘
   city → city, inside the hourly job:  WORKS_OUT / WORKS_IN (a city's own subscription is paid to its region)      │
                                                                                                        ◀───────────┘
```

**What is still created**: a new player's 8,000, and the one-time seed. **What is still
destroyed**: nothing by design. Two small stated leaks: (a) the wages of a voyage that never arrives
(ADRIFT / UNABLE_TO_SAIL, 0027:412-414) are paid by the house and reach no city; (b) voyages already
at sea when 0122 lands have settled days without a `wages_paid` figure. Both show in the watch query
(§7.2) as a negative drift, both tiny against turnover.

**Conservation, stated as arithmetic.** World money `W = Σ players.ducats + Σ port_treasury.ducats
+ Σ unrolled treasury_flows`. Per merchant lap (0116's net: `sold − bought − supplies − repairs −
wages + stock_out − stock_in`, 0116:101, less the new `taxes`), the cities as a whole lose exactly
`net − hire` of it. A merchant whose purse passes `npc_invest_above × capital` returns the surplus
above `npc_invest_keep × capital` to cities the same hour as shares (§3.4). So Σ merchant purses is
bounded by about `npc_invest_above × Σ capital`, and **the cities together hold `W − that`** — and
since no city can go below zero, a city that is empty simply stops buying until money comes back
through merchants buying its produce, the profit tax on sales there, shares bought there, or a
neighbour's building (`WORKS_IN`). The seed must make `W` large enough that the cities together can
keep buying (§6); the switch refuses to light a world where it is not.

---

## 2. 0122 — a city keeps a purse: the books, the tax rule, the empty-purse rule, the charges, the roll, the switch (dark)

### 2.1 Tables

```sql
create table public.port_treasury (
  port_id    uuid primary key references public.ports(id) on delete cascade,
  ducats     bigint not null default 0 check (ducats >= 0),   -- a city cannot owe (the owner, round 3)
  rolled_at  timestamptz not null default now(),
  reserve    bigint not null default 0,             -- written by the roll: treasury_reserve_days × mean game-day SELL outflow
  bid_factor numeric(5,4) not null default 1,       -- written by the roll: §2.3, read by world.quote / world.price
  seeded_at  timestamptz,
  updated_at timestamptz not null default now()
);
-- one row per HARBOUR (ports.kind = 'HARBOUR', 0036:182-186), seeded at 0 — no faucet at deploy.
-- RLS: readable by anon + authenticated (the port_buildings posture 0067:119-123); written by nobody but the server.

create table public.treasury_flows (           -- APPEND-ONLY; the trade path writes here and nothing else
  id         bigint generated always as identity primary key,
  port_id    uuid not null references public.ports(id),
  kind       text not null,                     -- §2.6
  ducats     bigint not null,                   -- signed: + into the city, − out
  player_id  uuid references public.players(id),   -- the house on the other side; null for city↔city and SEED
  ref_event  uuid references public.events(id),
  created_at timestamptz not null default now()
);
create index on public.treasury_flows (port_id, created_at);

create table public.treasury_daybook (         -- one row per (port, game-day, kind)
  port_id uuid not null references public.ports(id),
  game_day int not null, kind text not null, ducats bigint not null,
  primary key (port_id, game_day, kind)
);

alter table public.voyages add column wages_paid bigint not null default 0;              -- §2.4, wages
alter table public.standing_route_laps add column taxes bigint not null default 0;      -- §2.2, the lap's tax
```

Why flows + daybook and not a per-movement ledger like a house's: `credit()` takes the player row
`for update` (0004:228); a treasury row lock per trade would make every PROVISION at Lisbon wait for
the arrivals tick whenever a merchant traded at Lisbon inside it (`tick_arrivals` settles every due
fleet in one transaction, 0010:67-75, locks held to commit). An INSERT locks nothing. The daybook is
`trade_daily`'s shape (0022:748-750); rows older than `treasury_days_kept` collapse into one
`CARRIED` row per city (the `NPC_CARRIED` discipline, 0097:884-885). Append-only: a trigger
`public.tg_treasury_append_only` refuses UPDATE/DELETE unless `current_setting('byeharu.treasury_roll',
true) = 'on'`, set transaction-locally by `tick_city` alone — the `forbid_mutation` re-cut's shape
(0097:932-943), a sibling because that one's exemption reads `old.player_id … is_npc`
(0097:938-940). Autovacuum as 0095:87 / 0097:1025-1029.

The movers — the only four functions that touch a treasury:

```sql
public.treasury_post(p_port uuid, p_kind text, p_delta bigint, p_player uuid, p_ref_event uuid) returns bigint
  -- one INSERT; refuses a negative delta that treasury_balance does not cover (E_CITY_BROKE, with have/need
  -- figures — the 0050:676-677 shape). Server-only.
public.treasury_balance(p_port uuid) returns bigint          -- ducats + Σ flows after rolled_at
public.pay_city (p_player uuid, p_port uuid, p_kind text, p_amount bigint, p_event uuid)   -- credit(−) then post(+)
public.city_pays(p_port uuid, p_player uuid, p_kind text, p_amount bigint, p_event uuid)   -- post(−) then credit(+)
public.city_treasury_on() returns boolean                     -- wc('city_treasury_enabled') = 'true' (0092:291-294 shape)
public.city_can_spend(p_port uuid, p_amount bigint) returns boolean   -- treasury_balance − reserve ≥ p_amount: THE spenders' gate
```

`pay_city`'s argument order mirrors `credit(p_player, p_kind, p_delta, p_ref_event)` with the port
inserted after the player and the sign flipped, so **every verb's hunk is the first line of its
existing `credit(` call and nothing else** — the event payload after it is untouched. Revoked from
`public, anon, authenticated` (0050:678's posture).

### 2.2 The tax rule — tax on the profit of a sale, nothing else

**What is true today.** The cost of the cargo aboard IS tracked, per ship: `public.ships.cargo_basis`
(jsonb, goods.code → ducats per tun, 0081:137-142), kept equal across every hull of the fleet by the
one cargo mover `public.fleet_load` (0081:33-38, 55-56, 250-260 — a buy blends into the average), left
unchanged by a sale and dropped with the cargo key by `fleet_unload` (0081:286-287), read ONLY
through `public.fleet_cargo_basis(fleet, code)` (0081:182-205; a JSON null = UNKNOWN, never zero),
served on `world.fleets()` (0081:362); the shed keeps `player_storage.basis` (0081:39-40, 337-342);
the books for pre-0081 cargo were opened by 0082. And **`cmd.do_sell` already realises the profit
at the moment of sale** (0081:309-314): `v_basis := public.fleet_cargo_basis(p_fleet, g.code);
v_cost := round(v_basis * q.units); v_profit := q.total - v_cost;`, served on the SOLD event and the
receipt (0081:317-321) and on `cmd.preview`. **Nothing new is recorded.** The tax composes on
`v_profit`, where it is already computed.

**The rule.** `tax = round(greatest(0, profit) × rate)` at a sale; `rate = world.tax_rate(port)`;
`profit` as do_sell computes it. No tax on a BUY. None on a loss or break-even. None when the basis
is unknown (`v_profit` null — the game cannot prove a profit, so it taxes none; 0082 opened every
book, so unknowns are hand-loaded probe parcels only). No other fee: **harbour dues are not
charged** (`port_fee_per_ship` stays unread, as it is today). Running costs — wages, supplies,
repairs, hire — are purchases of labour and stores, not fees; everyone pays them in full, merchants
at 1.0. **Merchants follow the same rule through the same body** (`cmd.do_sell` is the one sale,
reached by the executor and by `cmd.run_manifest` 0083:346 alike); their planner nets the expected
tax so they do not plan a lap that loses after tax (below).

**The one authority of the rate**: `world.tax_rate(p_port)` (0005:318-324) answers the rate under the
rule in force — dark: the column (on turnover, as today); lit: `coalesce(p.tax_rate,
wc_num('tax_rate_default')) × wc_num('profit_tax_scale')`, capped by `tax_rate_max`. The column's
Mayor band stays 0–8 % (0002:101); the scale re-bases it to a profit tax (3 % → 15 % at scale 5).
**The one authority of the charge**: `public.profit_tax(p_port, p_profit)` = `case when
city_treasury_on() and p_profit > 0 then round(p_profit × world.tax_rate(p_port)) else 0 end` — used
by `do_sell` and by the planner, nowhere else.

| Live body | Hunk |
|---|---|
| `world.quote` 0022:390 as re-cut by 0083:227-233 (`v_tax := world.tax_rate(p_port);`) | → `v_tax := case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end;` — one line. The per-step lines (0022:400, :407) and 0083's parts (0083:237-250) are untouched; lit, `tax_total` reads 0 by construction |
| `world.price` 0005:388 (`v_tax := world.tax_rate(p_port);`) | the same one line; the spot ask/bid (0005:392-393) go tax-free lit |
| (no third body) | by grep, the only other lines with the ask/bid tax arithmetic are inside 0017's own self-assert `do $$` block (0017:743 → :908-911, :1000-1001, :1064), which ran once at apply time; `world.officers()` (live, 0017:703-737) does not price anything. Nothing else to slice |
| `cmd.do_sell` 0081:314 (`v_profit := q.total - v_cost;`) | → `v_profit := q.total - v_cost; v_tax := public.profit_tax(f.port_id, v_profit);` (+ `v_tax bigint;` in the declare block, anchored on `v_profit  bigint;` 0081:306) |
| `cmd.do_sell` SOLD payload tail 0081:318 (`'basis', v_basis, 'cost', v_cost, 'profit', v_profit)));`) | → `…, 'profit', v_profit, 'tax', v_tax, 'net', q.total - v_tax)));` followed by `if v_tax > 0 then perform public.pay_city(f.player_id, f.port_id, 'TAX', v_tax, null); end if;` — its own ledger row, `TAX`, like `PREMIUM` is its own (0087:449); the SOLD event carries the figure |
| `cmd.do_sell` receipt tail 0081:320-321 | → `…, 'profit', v_profit, 'tax', v_tax, 'net', q.total - v_tax);` (`profit` stays pre-tax; `net` is what the house kept) |
| `public.npc_leg_lines` 0120:267-268 and :275 | the keep test and `v_profit` use `(q_sell.total − q_buy.total) − public.profit_tax(p_to, q_sell.total − q_buy.total)` — the parcel's cost IS `q_buy.total`, so that is exactly the taxable profit |
| `cmd.standing_route_close_lap` sums 0092:535-541 (live via 0116:73-103, 0121:188-208) | one more `filter`: `coalesce(round(sum((o.result->>'tax')::numeric) filter (where o.verb = 'SELL')), 0)` into `v_taxes`; the UPDATE writes `taxes = v_taxes` and `net = … − v_taxes` (the 0121:193-196 hunk text, extended); `world.fleet_trades` prints `taxes` beside `wages` (0121:252-256); `route_earnings` reads `net` and needs nothing |
| the reads that print `'tax_rate', p.tax_rate` (0009:81, 0019:591 and :635, 0028:281, 0029:169, 0032:140 and :226 — `world.market`, last full definition 0032:189, and the port read) | → `'tax_rate', world.tax_rate(p.id)`, so the Market tab prints the rate in force (`Tax 15 % on profit`); the migration greps `pg_proc.prosrc` for the literal and slices every live occurrence |

What this does to prices: lit, every ask falls by the tax and every bid rises by it (≈ 3 % each
side), so a round trip pays ≈ 6 % more before tax; the profit tax at 15 % of a 5–15 % margin takes
back ≈ 1–2 % of turnover. **Cities earn less per trade than the first draft assumed and merchants
earn more** — stated, and the lever is `profit_tax_scale` (§7.3). The buy cap at the moment of buying
(0114:725, the next stop's bid ÷ (1 + min return)) is left as it is; the tax shaves the net margin
slightly, which the planner's keep test already accounts for.

### 2.3 The empty-purse rule — a city buys only what it can pay for

Two rules, one hard and one soft, both in the one sale body and the one price authority:

1. **Hard: the lot shrinks to what the purse covers.** In `cmd.do_sell`, after the quote and its
   refusal (0022:811-816) and before 0081's basis lines: when `city_treasury_on()` and `q.total >
   public.treasury_balance(f.port_id)`, re-quote at the largest whole-step quantity the purse covers
   (`floor(balance / q.avg_price / trade_step_tuns) × trade_step_tuns`, stepping one step down while
   `q.total > balance` — a sell order's early steps pay more per unit than its average, so at most a
   few re-quotes, and only when the purse is short); if that is under one step, refuse `E_CITY_BROKE`
   ("Cadiz cannot pay for cargo today", figures have/need, the 0050:676-677 shape). A partial fill
   is an existing outcome (a limit order fills partially, 0022:401-402): the order is done with the
   units sold and the rest stays aboard for the next stop. A merchant's refused line is skipped by
   the executor's skip law and her cargo rides on. `city_pays` refuses below zero as the backstop.
2. **Soft: the bid falls with the purse.** `public.city_bid_factor(p_port)` = `coalesce(least(1,
   greatest(wc_num('city_bid_floor'), t.ducats / nullif(t.reserve, 0))), 1)` when lit, else 1 — the
   rolled balance over the rolled reserve (two PK columns, computed hourly, §4 step 3). Composed
   into the sell-side unit price in `world.quote` (0022:407: `… * (1 - v_tax) * v_bidf`, with
   `v_bidf := public.city_bid_factor(p_port)` read once beside `v_tax`) and into `world.price`'s bid
   (0005:393). Above its reserve a city bids its full price; at half its reserve it bids half-way
   down to the floor; at nothing it bids the floor and the hard rule refuses. Merchants read quotes
   when they plan (0120:260-266, 609), so they stop selling into a thin purse before it is empty.

`treasury_reserve(p_port)` = `treasury_reserve_days` × the mean game-day `SELL` outflow from the
daybook (the roll writes it to `port_treasury.reserve`); it is also what the spenders keep back
(`city_can_spend`).

### 2.4 The charges — each is ONE hunk in a live body, asserted to occur exactly once

| Charge | Live body | Hunk (old → new) |
|---|---|---|
| BUY | `cmd.do_buy` 0022:761 (payload re-cut by 0083:276-278; no file after 0022 contains the literal `credit(f.player_id, 'BUY', -q.total,`, so the first line is live as written) | `perform public.credit(f.player_id, 'BUY', -q.total,` → `perform public.pay_city(f.player_id, f.port_id, 'BUY', q.total,` — the city receives the whole ask (tax-free lit, spread inside it) |
| SELL | `cmd.do_sell` 0022:831 | `perform public.credit(f.player_id, 'SELL', q.total,` → `perform public.city_pays(f.port_id, f.player_id, 'SELL', q.total,` — the city pays the whole bid from its purse; the TAX row follows (§2.2) |
| provisions / repairs / hire / build | 0017:327 / 0007:751 / 0007:690 / 0072:269 | `perform public.credit(f.player_id, '<KIND>', -v_cost,` → `perform public.pay_city(f.player_id, f.port_id, '<KIND>', v_cost,` (build: `h.ducats`). The merchant pool floor at 0007:689 as re-cut by 0097:944-959 is untouched |
| tuition | `cmd.study_skill` 0016:235-238 (`perform public.credit(` / `v_player,` / `'TUITION',` / `-v_cost,`) | → `perform public.pay_city(` / `v_player, v_fleet.port_id,` / `'TUITION',` / `v_cost,` — the harbour the fleet lies in (0016:203; `v_port` there is a record of code/name/has_academy, not a row with an id) |
| officer wage | `public.sign_officer` 0096:562-565 | → `pay_city(v_player, <port>, 'OFFICER_WAGE', v_off.wage_ducats,` — the fleet's port when `p_fleet` is given, else the officer's home port (one per officer in the seed, 0073:149) |
| wages of a sea-day | `voyage.settle` 0027:303-308 as re-cut by 0114:626-629 | `perform public.credit(f.player_id, 'WAGES', -least(v_wages, (select ducats …)));` → `v_paid := least(v_wages, (select ducats …)); perform public.credit(f.player_id, 'WAGES', -v_paid); update public.voyages set wages_paid = wages_paid + v_paid where id = v.id;` (+ `v_paid bigint;` anchored on `v_wages   bigint;` 0027:253). The house side is unchanged to the ducat; `v` is re-read each day at 0027:405 |
| wages of the leg (+ dividends, 0123) at arrival | `voyage.settle` arrival branch 0027:417-425; anchor = the two lines `from public.voyage_events ve where ve.voyage_id = v.id)));` + `perform cmd.advance(p_fleet, p_now);` (unique together — `cmd.advance` alone also occurs at 0027:277) | `perform public.emit_event(f.player_id, 'VOYAGE_REPORT',` → `v_report := public.emit_event(f.player_id, 'VOYAGE_REPORT',`; before the advance, when the destination is a HARBOUR: `treasury_post(v.dest_port_id, 'WAGES', v.wages_paid, f.player_id, v_report)` — and 0123's payout (§3.2). **No dues** |
| merchant running costs | knob | `npc_cost_mult` 0 → **1** (0116:40-44 is the live line). Readers untouched: `running_cost_mult` 0114:92-103 in settle / provision / repair / `npc_leg_lines` 0120:244-245 |

Nothing else moves. `cmd.haggle` (0022:430), the fairs (0026) and `cmd.do_dismiss` (0086:172) move
no money.

### 2.5 Refounds and bounties, paid by the city (the switch gates both)

- **Refounds**: `npc_tend`'s refound (0114:550-553 as sliced by 0115:204-209) becomes `v_can := case
  when city_treasury_on() then greatest(0, least(hh.capital − hh.ducats, treasury_balance(home) −
  reserve(home))) else hh.capital − hh.ducats end;` then, when `v_can > 0`,
  `city_pays(hh.home_port_id, hh.player_id, 'REFOUND', v_can, emit_event(NPC_REFOUNDED {company,
  amount, port, partial}))`, else `v_unfunded + 1` (in the receipt). The company loop (0114:514-560)
  stays a loop; `hh` gains `home_port_id` (0097:118); the event kind is kept (the card reads it;
  `npc_compact` keeps it, 0097:891). A merchant whose home cannot pay is not parked (0115): she sails
  in ballast at full wages, floored at her purse (0027:306-307), until her home earns.
- **Bounties** — the owner's "goods a city lacks" = 0087's rule, kept: `contract_draw` (0087:215-262,
  `not public.port_offers` :241) and the board (0087:178-205) are untouched. `tick_contracts`
  (0087:272-331): in the posting loop after the mid (0087:317-318) and before the INSERT (:319),
  `continue when city_treasury_on() and not city_can_spend(p_port, round(v_per_unit × v_draw.qty) ×
  wc_num('bounty_reserve_mult'))`; after a successful INSERT, `treasury_post(p_port, 'BOUNTY',
  −premium_ducats, null, null)` — escrow at posting; the expire UPDATE (0087:297-299) gains
  `returning premium_ducats` into one `BOUNTY_LAPSED` post. `cmd.run_fulfil` (0087:391-469) is
  unchanged: `credit(PREMIUM)` at 0087:449 stays — the escrow already left the city.

### 2.6 Flow kinds

In: `BUY TAX WAGES PROVISION REPAIR HIRE BUILD TUITION OFFICER_WAGE SHARE WORKS_IN BOUNTY_LAPSED
SEED`. Out: `SELL REFOUND BOUNTY DIVIDEND WORKS_OUT`. Book-keeping: `CARRIED`. New player-side ledger
kinds: `TAX`, `SHARE`, `DIVIDEND` — three words for `docs/WORDS.md`; the client's other ledger words
are untouched.

### 2.7 The roll, the read, the job, the switch

- `public.tick_city(p_now)` in 0122 does steps 1 (ROLL), 2 (CARRY), 3 (STATE: reserve, bid_factor),
  7 (ASSERT) and 8 (RECEIPT) of §4. Cron `byeharu-voyage:city` on `37 * * * *`, **defined inactive**
  (the 0012:101-119 rule), activated by `wind_the_clock()` (0078:182-200) through `clock_jobs()`'s
  `byeharu-voyage:%` prefix (0078:147-148). 0078's own self-assert pins the job NAMES (0078:262,
  `c_expected`) at 0078's apply, which on a from-zero chain runs before 0122 — not broken by a sixth
  job; the implementer greps `scripts/db/proofs/*` for a literal job list before shipping. Local
  (PGlite, no pg_cron): the local backend runs `public.tick_arrivals(now())` before a merchant read
  (`src/lib/rpc/localBackend.ts:38-41`); it runs `public.tick_city(now())` the same way before a
  `worldTownHall` read.
- `world.town_hall(p_port)` — §5. In 0122 it serves the purse and the day's book; 0123 restates it
  whole with the works and the investors.
- `public.city_treasury_switch(p_on boolean)` — the 0097:903-920 shape. `true`: seed (§6) if no
  `SEED` flow exists, assert the world is not broke, set the flag. `false`: the flag only — books
  keep posting; prices, tax, refounds, bounties, investment all fall back to today's rules at once
  (every reader asks `city_treasury_on()`).

### 2.8 Knobs (0122)

| Key | Start | Why |
|---|---|---|
| `city_treasury_enabled` | `false` | dark first |
| `npc_cost_mult` | 0 → **1** | round 2. Rollback: `update world_config set value = to_jsonb(0)` |
| `profit_tax_scale` | 5 | 3 % on turnover becomes 15 % on profit; the owner's level to set (§11) |
| `tax_rate_max` | 0.40 | the cap on the composed rate (8 % × 5) |
| `treasury_days_kept` | 30 game-days (= 1 real day) | the daybook window |
| `treasury_reserve_days` | 3 | a city keeps 2.4 real hours of what it pays sellers before it refounds, posts or builds; also where the bid starts to fall |
| `city_bid_floor` | 0.5 | the bid never falls below half the quay's price; below that the hard rule refuses anyway |
| `bounty_reserve_mult` | 2 | a request is posted only when the surplus covers it twice (a lazy post between two rolls cannot overdraw) |
| `city_seed_days` / `city_seed_min` | 10 / 20,000 | §6 |

### 2.9 Self-asserts (as found, every probe rolled back)

- Shape: the tables; `ducats ≥ 0` bites; the trigger refuses UPDATE/DELETE without the GUC and
  allows DELETE with it; `city_pays` past the balance refuses `E_CITY_BROKE` with have/need.
- Every hunk occurs exactly once in each live body; the pre-image is byte-identical outside it.
- Dark: `world.quote` and `world.price` equal their pre-images on 200 (port, good) pairs (the 0027
  method); a probe BUY/SELL moves the purse exactly as before, the BOUGHT/SOLD payloads are
  byte-identical plus the two new keys (`tax` 0, `net` = total), and flows appear (`BUY` +total,
  `SELL` −total); `world.tax_rate(every harbour)` equals the column.
- Lit (inside the probe, switch flipped and rolled back): `world.quote` buy-side per unit =
  `mid × (1 + s/2)` and sell-side = `mid × (1 − s/2) × bid_factor`, `tax_total` 0; a probe SELL at a
  known basis of 50 for 10 tuns at a bid of 60 pays `TAX` = `round(100 × rate)` as its own ledger row
  and flow, SOLD carries `tax` and `net`; at a bid of 50 or 40, or with an unknown basis, `TAX` 0 and
  no row; a BUY pays no tax. `world.tax_rate` = column × 5. The lap closer books `taxes` and the net
  subtracts it; `world.fleet_trades` prints it.
- Empty purse: a probe harbour with 1,000 d. and a 30-tun sale worth 3,000: the sale fills to the
  whole steps 1,000 covers and the receipt's `qty` says so; with 0 d., `E_CITY_BROKE` and nothing
  moves (cargo, stock, purse); `city_bid_factor` reads 1 above reserve, 0.5 at nothing, 0.75 at
  half, and 1 dark.
- Charges: PROVISION / REPAIR / HIRE / BUILD / TUITION / OFFICER_WAGE: purse delta + flow = 0, kinds
  unchanged. A probe voyage settled to arrival at a HARBOUR: `voyages.wages_paid` = Σ of its per-day
  WAGES debits, one `WAGES` flow of that sum with `ref_event` = the VOYAGE_REPORT event; a SEA_PLACE
  arrival posts nothing; no `DUES` row anywhere. `running_cost_mult(merchant) = 1`.
- Refound: funded home → `REFOUND` flow − and `NPC_REFOUNDED` with `partial` false; home at reserve
  + 100 → 100, `partial` true; home at reserve → no flow, receipt `refound_unfunded` = 1; dark → the
  old amount is minted. Board: a harbour under its reserve posts 0 where the pre-image posted 1;
  funded: posts 1 and a `BOUNTY` flow of −`premium_ducats`, Σ(treasury + escrow) unchanged; warp past
  expiry → `BOUNTY_LAPSED` of the same sum; fulfil → `PREMIUM` ledger row = `premium_ducats`
  (0087's own assert), no treasury flow at fulfilment; no open request names an offered good.
- `tick_city(now())` on the live world inside a rolled-back probe: completes under 20 s (the receipt
  prints `ms` per step), `balance = Σ daybook` for every harbour, flows table empty of rows ≤ p_now.
- Grants: the movers, `profit_tax`, `city_bid_factor`, `tick_city` not executable by `anon` /
  `authenticated`; `world.town_hall` authenticated-only and in the registry; `client_write_grants()`
  = 0; the 0097 scan (no body contains `auth_uid is null`). The job defined, inactive, named,
  listed by `clock_jobs()`.

### 2.10 Cost

Trade path: +1 INSERT per BUY/PROVISION/REPAIR/HIRE/BUILD/TUITION/OFFICER_WAGE, +1–2 per SELL (the
TAX row), +1 per arrival, one column write per settled sea-day inside an UPDATE the loop already
makes (0027:403), one `fleet_cargo_basis` read per sale that do_sell already makes. A sale into a
short purse costs a few extra quotes. `world.quote` gains one switch read and one PK lookup. Against
the arrivals job's 14.3 s average / 46.8 s max (`docs/RESUME.md:29`): tens of milliseconds a minute.
`tick_city`: under a second in 0122. `tick_reconcile` (66.7 s of 120): the refound slice makes fewer
credits, not more.

---

## 3. 0123 — a city builds with other people's money: works, shares, coupons

### 3.1 Tables

```sql
create table public.city_works (
  port_id    uuid not null references public.ports(id) on delete cascade,
  kind       text not null check (kind in ('docks', 'market', 'production', 'inn')),
  level      int  not null default 0 check (level between 0 and 5),
  subscribed int  not null default 0 check (subscribed between 0 and 100),   -- shares of the NEXT level sold so far
  updated_at timestamptz not null default now(),
  primary key (port_id, kind)
);
create table public.city_shares (
  port_id     uuid not null references public.ports(id) on delete cascade,
  kind        text not null,
  player_id   uuid not null references public.players(id) on delete cascade,
  shares      int  not null check (shares > 0),
  paid        bigint not null check (paid > 0),      -- what the house paid, the coupon's base
  accrued     bigint not null default 0,            -- coupons earned, not yet paid out
  accrued_day int  not null,
  primary key (port_id, kind, player_id)
);
```

Not `ports.*` and not `port_buildings.tier`: `has_yard`, `yard_tier`, `max_draft`, `dev_*`,
`crew_pool` are authored in `data/ports.json` and world-guard holds the applied world equal to the
file (CHAIN.md header); `public.furnish_harbours` (0089:95) holds `port_buildings` (0067:106-111).
A level lives in its own row and composes into a reader. `public.city_level(p_port, p_kind)` =
`coalesce(level, 0)` is the one reader.

### 3.2 The rules

- `cost(L) = works_cost_base × works_cost_growth ^ (L − 1)`; a level is `shares_per_level` (100)
  shares at `cost(L + 1) / 100` each. A city OFFERS `100 − subscribed` shares of its next level while
  `level < works_level_max`.
- **Houses buy**: `public.invest_for(p_player, p_port, p_kind, p_shares)` — refuse `E_NOT_OFFERED` /
  `E_OVERSUBSCRIBED` / under `invest_min_ducats`, then `pay_city(p_player, p_port, 'SHARE', price × n,
  emit_event(INVESTED))`, upsert `city_shares` (+shares, +paid), `subscribed += n`. Skins
  `cmd.invest(p_port, p_kind, p_shares)` + `cmd.preview_invest` (the `cmd.fulfil` / `cmd.preview_fulfil`
  pair, 0087:481 / :532; the `_for` core shape of 0096:774 / :1028 / :1069), docked at that harbour
  only; not a queue verb (no change to `cmd.parse`'s grammar).
- **The city subscribes the rest** (§4 step 4): one (port, kind) per harbour per hour — its
  lowest-level work, ties by kind order — `k = least(100 − subscribed, floor((balance − reserve) /
  price))` when `city_can_spend(port, k × price)` and `k ≥ 1`: `subscribed += k`, and the money is
  **paid to the region's other harbours** (`ports.region_id` 0002:89; 25 regions 0003:115-122) split
  by `size_tier` (0002:91) as `WORKS_OUT` / `WORKS_IN` × `works_region_share` — stone, timber and
  hands bought from the coast; "the city must use it for the whole world". A region of one keeps it.
- **A level completes** when `subscribed = 100`: `level + 1`, `subscribed = 0`.
- **Coupon** (§4 step 6): each `city_shares` row earns `due = round(paid × wc_num('works_coupon_pct')
  × (today − accrued_day))`. **A city pays what it holds above its reserve**: per harbour, `payable =
  least(Σ due, greatest(0, balance − reserve))`, split pro rata over its rows; the shortfall is not
  owed — a poor city skips its dividend, like a company that skips one. `accrued_day` advances
  regardless. One UPDATE, one `DIVIDEND` flow per harbour. This is the "cannot grow for ever":
  a city whose trade cannot carry its investors' coupons stops paying them, and investors read that
  on the Town Hall.
- **Payout rides an arrival** (the §2.4 arrival hunk): for each `city_shares` row of (f.player_id,
  v.dest_port_id) with `accrued > 0`: `credit(player, 'DIVIDEND', accrued, v_report)`; `accrued :=
  0`. The flow was posted at accrual, so the books stay conserved whether or not the holder calls.
  Merchants dock at every stop of their loop every lap, so they are paid each lap.
- The city's own shares are `100 × level − Σ house shares` and pay nothing to nobody.

### 3.3 What a level does — one reader each

| Work | Reader (live) | Composition |
|---|---|---|
| `docks` | `voyage.sail_refusal` E_DRAFT 0036:443-448 (`max(draft) > max_draft`; live via 0047:358 → 0050:316) | `v_maxd + public.city_level(p_dest, 'docks') / wc_int('docks_draft_per_levels')` → +1 draft at levels 2 and 4 |
| `market` | `world.daily_cap_remaining` 0027:445 and `world.spread` 0026:277-293 | allowance × `(1 + wc_num('market_cap_per_level') × level)`; spread: one more term inside the `greatest(floor, base − per_dev × dev_commerce − per_dev × level)` |
| `production` | `public.tick_market_drift` regeneration UPDATE 0010:120-126 | `production_rate × (1 + wc_num('production_per_level') × coalesce(cw.level, 0))` via a `left join city_works` — set-based already, once a game-day |
| `inn` | `cmd.do_hire` draws `ports.crew_pool` (0007:689); no tick refills it (0097:98-99) | §4 step 5: `update ports set crew_pool = least(size_tier × wc_int('inn_pool_per_tier'), crew_pool + wc_int('inn_hands_per_level') × level)` for harbours with an inn level, `for update skip locked` |

Patrols are not in this plan: pirates cost no money (0027:349) and `voyage.hazard_roll` must stay
pure in (voyage, day) for proof 01 (0006:135-138, 0059:13).

### 3.4 Merchants invest anywhere on their loop (round 2, answer 5)

In `npc_tend`'s company loop (0114:514-560), before the refound test, under the 60 s budget
(`npc_upkeep_spent()`, 0114:107-119): a company with `purse > npc_invest_above × capital` buys,
through `invest_for`, at the harbour on any of her routes' stops (`npc_fleets.route_id →
standing_route_stops.port_id`) that offers the most shares, `least(offered, floor((purse −
npc_invest_keep × capital) / price))` shares; at most `npc_invest_max_per_hour` companies an hour,
oldest purse first. Players and merchants use the same door. Counted `invested` in the receipt. The
merchant card (`world.npc_fleet_card` 0099:238; `src/live/MerchantSheet.tsx`) gains `Invested 24,000
d. at Lisbon`.

### 3.5 Knobs (0123)

| Key | Start | Why |
|---|---|---|
| `works_cost_base` / `works_cost_growth` / `works_level_max` | 20,000 / 1.6 / 5 | level 5 = 131 k; the `port_buildings.tier` range (0067:109) |
| `shares_per_level` | 100 | a share of a 20 k level is 200 d. |
| `works_coupon_pct` | 0.003 per game-day of what was paid (≈ 9 % a real day) | the first lever if cities stop buying because they pay coupons |
| `works_region_share` | 1.0 | how much of a city's own subscription goes to its region (0 keeps it home — then a rich city builds for free and the money pools) |
| `invest_min_ducats` | 1,000 | no dust |
| `npc_invest_above` / `npc_invest_keep` / `npc_invest_max_per_hour` | 2.0 / 1.5 × capital / 50 | a merchant invests only her surplus; ≤ 50 `credit()`s an hour inside the budget |
| `docks_draft_per_levels` / `market_cap_per_level` / `production_per_level` | 2 / 0.10 / 0.10 | +1 draft at docks 2 and 4; +50 % allowance and production at level 5 |
| `inn_hands_per_level` / `inn_pool_per_tier` | 2 per hour / 40 | a level-5 inn restores 10 hands an hour, never past `size_tier × 40` |
| `town_hall_investors_max` | 50 | the longest investor list the read serves |

### 3.6 Self-asserts (0123)

- Buy: refuses a kind not offered, more than offered, under the minimum, not docked (the skin);
  purse + treasury conserved; the INVESTED event; `subscribed` moves; a 100th share completes the
  level.
- Subscription: a probe harbour at reserve + 50 × price subscribes exactly 50 of its lowest work,
  pays `WORKS_OUT` = Σ `WORKS_IN` over its region to the ducat; under its reserve subscribes nothing;
  a region of one posts no flow.
- Coupon: a probe row `paid 10,000`, warp one game-day → `accrued 30`, a `DIVIDEND` flow of −30; a
  harbour holding reserve + 10 with two rows due 30 and 10 pays 7 and 3 (pro rata) and owes nothing
  more; one holding its reserve exactly pays 0 and `accrued_day` still advances. Payout: settle a
  probe voyage into that harbour → `credit(DIVIDEND, 30)`, `accrued 0`, no new flow.
- Composition against pre-images at level 0 (byte parity) and 5: `sail_refusal` admits `max_draft +
  2`; `daily_cap_remaining` × 1.5; `world.spread` − 5 × `spread_per_dev` (floored); the regen
  statement's `production_rate × 1.5` on a probe producer row; `crew_pool` + 10, never past the cap.
- `npc_tend`: a probe merchant at 3 × capital buys down to 1.5 × capital at the stop that offers
  most; at 1.9 × buys nothing; the budget cuts the loop (the 0114 `deferred` count).
- `world.town_hall` serves the works, the offered shares, the investors by name with `merchant`
  true for an `is_npc` house (0096:85), the viewer's holdings and `docked`; a stranger sees the same
  list (names are public: the card serves a merchant's, Rank a player's) but `docked` false.

---

## 4. `public.tick_city(p_now)` — the one hourly job

Cron `byeharu-voyage:city` on `37 * * * *`: `reconcile` is `7 * * * *` (0012:99) and runs 61–72 s;
`arrivals` every minute (0012:97); `drift`, `price-snapshot`, `buff-calendar` are `*/10` (0012:98,
0013:199, 0026:468). Never waits: `set local lock_timeout = '2s'` (the 0097:971 line); every UPDATE of
a row the minute tick may hold (`ports`) goes through `for update skip locked` (0010:72's idiom).
Each step in its own `begin … exception when others` block with its error in the receipt
(0097:972-986's shape), except ROLL and ASSERT, which abort the hour.

```
 1. ROLL     set_config('byeharu.treasury_roll','on',true);
             with f as (select * from treasury_flows where created_at <= p_now for update skip locked),
                  d as (insert into treasury_daybook … select port_id, world.game_day(created_at), kind, sum(ducats)
                        from f group by 1,2,3 on conflict do update set ducats = daybook.ducats + excluded.ducats),
                  b as (update port_treasury t set ducats = t.ducats + x.s, rolled_at = p_now from (…) x …)
             delete from treasury_flows where id in (select id from f);
 2. CARRY    daybook rows with game_day < today − treasury_days_kept → one CARRIED row per port
 3. STATE    reserve := treasury_reserve_days × mean game-day SELL outflow; bid_factor := §2.3 — one UPDATE
 4. BUILD    (0123) own subscription → WORKS_OUT / WORKS_IN; level completions — one window UPDATE
 5. INN      (0123) crew_pool regeneration, skip locked
 6. COUPONS  (0123) due per row; payable per harbour = least(Σ due, balance − reserve); pro rata; DIVIDEND flows
 7. ASSERT   every harbour: ducats = Σ daybook; this hour's WORKS_OUT + WORKS_IN = 0; no ducats < 0
 8. RECEIPT  jsonb: flows_rolled, reserves, subscribed, levels_built, coupons_paid, coupons_skipped,
             world_ducats = Σ players.ducats + Σ port_treasury.ducats + Σ unrolled flows, ms per step
```

Spending flows are written in exactly three places: `tick_city` (subscription, coupons), `npc_tend`
(refound, investment — inside `tick_reconcile` at :07, never concurrent with :37) and
`tick_contracts` (escrow, lazy on a read). Income flows are written by the verbs (§2.4), `invest_for`
and the switch (SEED, once). Cost: 237 harbours, ≤ 1,000 works rows, a few thousand share rows, ≤ 2 h
of flows — 1–3 s on prod; the self-assert refuses > 20 s on the live world.

---

## 5. The Town Hall — one read, one panel

### 5.1 Server: `world.town_hall(p_port uuid) returns jsonb`

Authenticated-only; registered in `public.client_rpc_entry_points()` by the 0121:326-338 slice shape,
anchored on `('world', 'fleet_trades', 'uuid'),` (0121:336). Reads the rolled state and the daybook —
no settlement, no write (the local backend winds `tick_city` before it, §2.7). One shape, two
versions (0122 serves the first two blocks; 0123 restates the function whole):

```jsonc
{
  "port": "LIS", "enabled": true,
  "purse":  { "ducats": 123456, "reserve": 18000, "bid_factor": 1.0, "rolled_at": "…", "seeded_at": "…",
              "tax_rate": 0.15 },                       // world.tax_rate(p_port): the rate on profit in force
  "day":    { "game_day": 61234,                       // the last FULL game-day's book, by kind
              "in":  { "BUY": 41000, "TAX": 900, "WAGES": 2100, "PROVISION": 300, "HIRE": 200, "SHARE": 4000, "WORKS_IN": 0 },
              "out": { "SELL": 38000, "REFOUND": 5000, "BOUNTY": 0, "DIVIDEND": 600, "WORKS_OUT": 0 } },
  "works":  [ { "kind": "docks", "level": 2, "next_cost": 32000, "share_price": 320, "offered": 60, "subscribed": 40 }, … ],
  "investors": [ { "name": "Casa Lopes & Filhos", "merchant": true,  "kind": "docks", "shares": 12, "paid": 2400 },
                 { "name": "Byeharu Trading",     "merchant": false, "kind": "docks", "shares": 5,  "paid": 1000 }, … ],
                                                       // paid desc, at most town_hall_investors_max rows, every holder named
  "you":    { "docked": true, "holdings": [ { "kind": "docks", "shares": 5, "paid": 1000, "owed": 45 } ] }
}
```

`name` is `players.company_name` (public: the merchant card serves it, 0099; Rank serves a player's,
0025 via `settle_standings`); `merchant` is `players.is_npc` (0096:85). `docked` is whether a fleet of
the caller lies DOCKED at `p_port` (`isDockedAt`'s server twin: `fleets.status = 'DOCKED' and port_id
= p_port`), which is the one condition `cmd.invest` enforces too.

### 5.2 Client

- `src/features/map/cityTab.ts`: `CityTab = 'market' | 'port' | 'inn' | 'townhall'`; `CITY_TABS`
  gains `{ id: 'townhall', label: 'Town Hall' }` (the segmented bar in `CityTabs.tsx:54` draws it).
- `src/features/map/CityTabs.tsx:56-58` renders `<CityTownHall port={port} fleet={acting}
  docked={docked[0] ?? null} trayMode="side-next" />` for the new tab.
- New `src/features/map/CityTownHall.tsx`, read through `worldTownHall` (catalogue entry in
  `src/lib/rpc/catalog.ts` beside `worldPortMerchants` :319; `cmdInvest`, `cmdPreviewInvest` beside
  `worldContracts` :185's verbs), kept in the world store like the city's other reads:
  1. Head: `Treasury 123,456 d.` and one quiet line — `Buys up to its purse · bid 100 %` or, thin,
     `Short of money · bids 70 %` (from `bid_factor`); `Tax 15 % on profit`.
  2. Works: one row per kind — `Docks ●●○○○ · 60 of 100 shares · 320 d. each` with an **Invest**
     press (enabled only when `you.docked`; otherwise the row says `dock here to invest`) that opens
     the step tray (`src/live/useOrderPreview.ts`'s shape with `cmd.preview_invest` → `cmd.invest`),
     and `You hold 5 · 45 d. owed` under a row the viewer holds.
  3. Investors: `Casa Lopes & Filhos · merchant · Docks · 12 shares · 2,400 d.` — the list, paid desc;
     a merchant's row opens her sheet (`MerchantSheet.tsx`), a player's row nothing.
  4. The day's book as a few short rows: `Trade in · Trade out · Tax · Wages · Shares · Coupons`.
- Words (`docs/WORDS.md`): Town Hall, Treasury, Shares, Invest, Coupon (the dividend), Tax (on profit).
- Spec: `tests/map.townhall.spec.ts` on the `npcOn` fixture — the tab opens, the treasury line is
  present, Invest is disabled when the viewer is not docked, the investor list prints the seeded
  merchant investor by name.

---

## 6. The switch, the seed, and the arithmetic that must hold

Treasuries start at 0 and the market is the purse, so the first sale at any harbour would be
refused. `city_treasury_switch(true)` therefore seeds every harbour **from its own first day of
books** (0122 runs dark for a day first): `seed(port) = greatest(wc_int('city_seed_min'),
round(wc_num('city_seed_days') × mean game-day SELL outflow))`, posted once as a `SEED` flow (the
one stated faucet; the receipt prints Σ and `seeded_at` is set). It then asserts the world is not
born broke:

```
W_after = Σ players.ducats + Σ seeds   ≥   wc_num('npc_invest_above') × Σ npc_houses.capital + Σ reserve
```

— merchants hold up to `npc_invest_above × capital` each before they give anything back (§1.2);
anything less leaves the cities together unable to buy from day one. If it does not hold, the
switch refuses with the two figures and the owner raises `city_seed_days` (one knob) and calls
again. The seed is once: a second `true` re-seeds nothing.

---

## 7. Watching it

### 7.1 Targets

| Measure | Target | How it is read |
|---|---|---|
| World money `W` | flat over a day (± new players' 8,000s, − the two stated leaks) | §7.2 |
| Harbours that refused a sale (`E_CITY_BROKE`) in the last hour | a few, not most | count of `E_CITY_BROKE` in `standing_route_laps.skipped` of laps closed in the hour, plus the receipt's `thin` count (bid_factor < 1) |
| Σ merchant purses / Σ capital | between 1.0 and `npc_invest_above`; flat | `select sum(p.ducats) / sum(h.capital) from players p join npc_houses h on h.player_id = p.id` |
| Merchant lap net (after tax) | mean positive over a day; a losing share under a third | `select avg(net), avg((net < 0)::int) from standing_route_laps where closed_at > now() − interval '1 day'` |
| Refounds | mostly funded: `refound_unfunded` under a tenth of `refounded` | `tick_reconcile`'s receipt in `cron.job_run_details` |
| Coupons | `coupons_skipped` under a quarter of `coupons_paid` after the first day | the city job's receipt |

### 7.2 The one query

```sql
select start_time, (return_message::jsonb ->> 'world_ducats')::bigint as world_ducats,
       (return_message::jsonb ->> 'world_ducats')::bigint
         - lag((return_message::jsonb ->> 'world_ducats')::bigint) over (order by start_time) as delta,
       return_message::jsonb -> 'coupons_skipped' as skipped
  from cron.job_run_details
 where jobname = 'byeharu-voyage:city' and status = 'succeeded'
 order by start_time desc limit 24;
```

### 7.3 The levers (one knob, one reader, no migration)

| Drift | Turn |
|---|---|
| Many harbours thin or refusing | `works_coupon_pct` down; `npc_invest_above` 2.0 → 1.5 (merchants return money sooner); `profit_tax_scale` up (cities keep more of each profitable sale); `treasury_reserve_days` down (less held back) |
| Harbours hoard, merchants starve | `treasury_reserve_days` 3 → 1; `works_cost_base` down and `works_region_share` 1.0 (they build more and pay the coast) |
| Merchants lose too often | `npc_min_return_pct` 5 → 8 (0120:88-92); `profit_tax_scale` down; `npc_cost_mult` 1 → 0.5 (the owner's call) |
| One harbour runs away rich | its `ports.tax_rate` down within the band (0002:101); `works_region_share` 1.0 |

---

## 8. What the owner will see in the game

- **A fourth building on every city: Town Hall.** Its purse at the top; the four works as dots with
  the shares on offer and an **Invest** button when one of your fleets is docked there; the list of
  who invested — merchant companies and players by name, with what they paid; and the day's money in
  and out in a few lines.
- **Prices move once**, at the switch: everything is a little cheaper to buy and pays a little more
  to sell (the tax left the prices), and a sale that made money shows a `Tax` line on the receipt
  and in the ledger — `Sold 1,200 · Tax 36`. A sale at a loss shows no tax. Buying shows none.
- **A city that runs short says so**: the Town Hall reads `Short of money · bids 70 %`, its market
  bids less, and when it is empty a sale there is refused with "cannot pay for cargo today" (or
  fills part of the lot). Merchants steer around such a harbour by themselves and come back when it
  has earned.
- **Merchants** pay full wages and supplies: some laps close at a loss (red lap pills on the fleet
  panel). A merchant whose home is empty sits at her purse floor sailing in ballast until her home
  earns. A rich merchant's purse stops climbing past twice her capital: the Town Halls on her loop
  show her name among the investors, and her sheet says `Invested 24,000 d. at Lisbon`.
- **Day one after the switch**: a burst — merchants that earned at zero cost for a day are far above
  twice their capital and invest it within the hour; rich harbours fill their first levels and pay
  their coasts; a few sink harbours run thin in the first hours. Said here so it is not read as a bug.
- **Nothing to press to run a city**: a city spends by itself.

---

## 9. Risks, handled and stated

- **The arrivals tick** (14.3 s avg, 46.8 s max, 2-min limit): one INSERT per trade, one or two per
  sale, one per arrival, ≤ 2 dividend credits per arrival, one column write per sea-day. Tens of
  milliseconds a minute. The hourly job never touches a fleet row and skips what is locked.
- **`tick_reconcile` at 61–72 s of 120**: `npc_tend`'s loop gains ≤ 50 investment credits and loses
  minting refounds, under the existing 60 s deadline (0114:573-603).
- **`world.quote` is the hot path**: it gains one switch read and one PK lookup (`city_bid_factor`)
  per call, no per-step work. The planner prices ≤ 16 loops × 3 legs × ~5 quotes at a lap start
  (0120:74-78) — unmeasurable.
- **The price change at the switch is world-wide** (≈ 3 % each side): every merchant's next lap-start
  plan reads the new prices (0120); routes shift once. Players see cheaper asks the same minute.
- **Cities earn less than the first draft assumed** (tax on profit, no dues): the profit tax at 15 %
  of a thin margin is 1–2 % of turnover. The purse's income is then mostly what merchants BUY from
  the city and what houses invest — `profit_tax_scale` and `works_coupon_pct` are the two levers.
- **Determinism of settlement** (proof 01): hazard untouched; `wages_paid` is a sum of figures the
  loop already computes.
- **A from-zero apply** sees 0078's name assert before 0122; grep the proofs for a literal job list.
  World-guard: this plan writes `ports.crew_pool` only (which `do_hire` already writes).
- **Merchant purses today** (0116): the day-one burst above.
- **Seed sizing**: the one real unknown; the switch refuses a broke world and prints the figures.
- **The two leaks** (§1.2) are measured by the watch query.
- **PGlite**: two migrations each `alter`/`create`; the local save is rebuilt per step (memory rule).

---

## 10. Build list, in order

Every migration: self-asserts hold **as found** (lit or dark), every probe rolled back, no long block
on prod through `db query`; deploy by the runbook `unwind_the_clock()` → `db push` →
`wind_the_clock()` (RESUME 10-14 rules), dry-run on prod inside `begin … rollback` first (the
0119-0121 method, `docs/RESUME.md:18`). Rollback of any step = (1) `city_treasury_switch(false)`
(instant, no migration: every consequence reads the switch — prices, tax, refounds, bounties,
investment all fall back at once); (2) a forward migration that puts the sliced hunks back (each
slice's old text is in the file). Tables are left in place; they are inert without readers.

| # | Name | What it changes | Self-assert | Knobs | Rollback |
|---|---|---|---|---|---|
| **0122** | `a_city_keeps_a_purse` | tables `port_treasury` (≥ 0), `treasury_flows`, `treasury_daybook`, trigger; `voyages.wages_paid`; `standing_route_laps.taxes`; movers + `city_treasury_on` + `city_can_spend` + `treasury_reserve`; **the tax rule** (`world.tax_rate` re-based lit, `profit_tax`, one-line hunks in `world.quote` / `world.price`, `do_sell`'s tax row, the planner's keep test, the lap closer, the `tax_rate` prints); **the empty-purse rule** (`city_bid_factor` in `quote`/`price`, `do_sell` shrink-or-refuse); eight verb hunks (six one-line, two four-line) + the settle wages/arrival hunks (no dues); refounds from the home harbour; bounty escrow (0087's rule kept); `tick_city` (roll, carry, state, assert, receipt) + cron inactive; `world.town_hall` (purse + day) + registry; `city_treasury_switch` (seed + flag) | §2.9 | `city_treasury_enabled` false, `npc_cost_mult` 1, `profit_tax_scale` 5, `tax_rate_max` 0.40, `treasury_days_kept` 30, `treasury_reserve_days` 3, `city_bid_floor` 0.5, `bounty_reserve_mult` 2, `city_seed_days` 10, `city_seed_min` 20,000 | the switch; `npc_cost_mult` 0 by knob; a forward slice restoring `credit(` in the eight bodies and `v_tax := world.tax_rate(…)` in the two price bodies; `cron.unschedule('byeharu-voyage:city')` |
| **0123** | `a_city_builds_with_other_peoples_money` | tables `city_works`, `city_shares`; `city_level`, `invest_for`, `cmd.invest`, `cmd.preview_invest` + registry; steps 4, 5, 6 of `tick_city`; the four reader slices (`sail_refusal`, `daily_cap_remaining`, `world.spread`, `tick_market_drift`); the dividend payout in the settle arrival hunk; `npc_tend` investment rule; `world.town_hall` restated whole (works, investors, you); `npc_fleet_card` line | §3.6 | `works_cost_base` 20,000, `works_cost_growth` 1.6, `works_level_max` 5, `shares_per_level` 100, `works_coupon_pct` 0.003, `works_region_share` 1.0, `invest_min_ducats` 1,000, `npc_invest_above` 2.0, `npc_invest_keep` 1.5, `npc_invest_max_per_hour` 50, `docks_draft_per_levels` 2, `market_cap_per_level` 0.10, `production_per_level` 0.10, `inn_hands_per_level` 2, `inn_pool_per_tier` 40, `town_hall_investors_max` 50 | `works_level_max` 0 offers nothing; `works_coupon_pct` 0 stops coupons; readers at level 0 are byte-parity with their pre-images |

**Deploy order and the switch**: the 0120 check in the RESUME queue (zero-net laps, tick durations)
→ 0122 → one day dark (`npc_cost_mult` 1 is live from here; if too many laps lose, 0.5 by knob;
read the daybook §7.1) → 0123 → `select public.city_treasury_switch(true)` (seeds, asserts §6,
lights prices / tax / refounds / bounties / investment at once) → a day of §7 readings.

**Client PRs** (each after its migration is LIVE; `npm run refresh` in `tools/projectmap` after
every game change — memory rule): after 0122 — the Town Hall tab with the purse and the day's book
(§5.2 items 1 and 4), the `Tax` line on the sell receipt and in the ledger words, `taxes` in the trade
history (`src/live/TradeHistoryPanel.tsx`), the Market tab's printed rate; after 0123 — the works
rows, **Invest** and its tray, the investors list, the merchant sheet line.

---

## 11. Remaining owner decisions (two, neither blocking 0122's build)

1. **The profit-tax level.** The city's 3 % becomes 15 % of a sale's profit (`profit_tax_scale` 5).
   Accept, or name the percentage.
2. **Harbour dues.** "Tax or any fees only on profit" is read here as: no port dues at all
   (`port_fee_per_ship` stays unread, as today). Confirm, or say dues are a cost like provisions.

Decided: the seed rule (ten game-days of what a harbour pays sellers, min 20 k) stays the default.

---

## 12. LATER — designed, kept, NOT scheduled: debt, aid, donations, war

The owner deferred these on 2026-10-15 (round 3). They were designed in full in v2 of this file
and are kept here condensed so nothing is lost. If scheduled they would be 0124–0126 and would
re-open exactly the readers named; none of them is needed for 0122–0123, which stand on their own
(a city that cannot pay simply stops buying, §2.3).

### 12.1 Debt (would replace the `ducats ≥ 0` CHECK)

- A city may go below zero: `city_pays` takes the purse negative; `port_treasury` gains `credit_line`
  (= `city_credit_days` × mean game-day trade income, min `city_credit_min`), `state`
  (`solvent` / `debt` / `default` = debt past the credit line), `debt_surcharge`, `default_since_day`,
  computed hourly by the roll.
- **What debt does, one reader each**: `world.tax_rate` gains a surcharge `tax_debt_max × min(1,
  debt / credit_line)` (both quays worse; the planner routes around it); `city_can_spend` is false in
  any debt (no refound, no request, no subscription, no aid out); coupons are paid in debt and
  **suspended in default**; a `city_debt_floor_mult` knob (off) makes the quay refuse to buy past N
  credit lines. Debt cannot run away: in default the only outflow is paying sellers at a capped bid
  the planner's keep test rarely accepts.
- Ways out: the surcharged ask (buyers pay more), aid, donations, shares bought, a war won.
- Knobs: `city_credit_days` 10, `city_credit_min` 20,000, `tax_debt_max` 0.12, `city_debt_floor_mult` 0.

### 12.2 Aid and donations

- **City → city aid** (hourly, one CTE per region, `ports.region_id`): donors = solvent harbours
  with `excess = balance − aid_donor_mult × reserve > 0`, each gives `aid_rate × excess`; recipients =
  harbours in debt, split by debt, capped at the debt; rounding to the largest debtor; flows
  `AID_OUT` / `AID_IN`, Σ 0 per region. Knobs `aid_donor_mult` 2, `aid_rate` 0.10 per hour.
- **A player's donation**: `public.donate_for(player, port, amount)` core + `cmd.donate` /
  `cmd.preview_donate` skins (the `fulfil` pair's shape), docked there only, `pay_city(…,
  'DONATION', …)`, event `DONATED`; `donate_min_ducats` 100. A Donate press on the Town Hall.
- **NPC aid**: in `npc_tend`'s company loop, a merchant above `npc_invest_above × capital` whose home
  is in debt gives `least(surplus, home's debt)` as `DONATION` before she invests; event
  `NPC_DONATED`, kept by `npc_compact`; the Town Hall lists donors beside investors.

### 12.3 War

- Table `city_wars (attacker, defender, declared_day, ends_day, status open/won/lost/peace,
  indemnity)`, one open war per side (partial unique indexes); `public.city_at_war(port)` the one
  predicate.
- **Start** (hourly, after aid): a harbour in default for `war_debt_days` game-days, not at war and
  not in `war_cooldown_days`, declares on the richest harbour of its region with balance ≥
  `war_target_min_ducats`; `ends_day = today + war_days`; at most `war_max_declared_per_hour`.
- **While open**: `war_tax` on both through `world.tax_rate`; no requests posted (`tick_contracts`
  `continue when city_at_war`); no subscription, no aid for either; trade continues (houses are not
  at war). Hazard untouched (proof 01).
- **Peace**: the attacker's balance back at ≥ 0 (a donation, shares bought, its own trade) ends it
  with no indemnity — the one way a player stops a war.
- **End**: at `ends_day`, `u = voyage.rng(war.id, ends_day, 'war')` (0006:127-138) against
  `war_base_p + war_works_p × (attacker docks − defender docks)` clamped [0.1, 0.9]; the winner takes
  `war_indemnity_pct × max(0, loser's balance)` as `INDEMNITY_OUT` / `INDEMNITY_IN`. A losing attacker
  has nothing to take and stays in default, in cooldown.
- Knobs: `war_debt_days` 3, `war_days` 5, `war_cooldown_days` 10, `war_target_min_ducats` 50,000,
  `war_tax` 0.05, `war_base_p` 0.45, `war_works_p` 0.05, `war_indemnity_pct` 0.25,
  `war_max_declared_per_hour` 10.
- What the owner would see: `Owes 12,300 d. · credit 40,000` / `Defaulted` on the Town Hall; `At war
  with Seville · 2 game-days left`; aid and donations as lines in the day's book.
