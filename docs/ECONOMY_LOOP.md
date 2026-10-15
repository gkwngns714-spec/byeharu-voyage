# ECONOMY_LOOP — the market is the city's purse; a city can owe; debt makes cities act on each other

**Status: DESIGN v2, BUILD-READY (2026-10-15 late). Nothing in this file is built. No migration,
no code, no production change. Prod head is 0121 (`docs/RESUME.md:18`); this plan starts at 0122.**

The owner, 2026-10-15, verbatim: *"i want to economy to be circulative, meaning that there should be
a way for these merchants gold to be reduced, weather it is by investing in cities. Then cities
should have gold too, and the city must use it for the whole world and so on, any ideas?"*

**The owner's answers (2026-10-15), which this plan is cut to. They override the first draft:**

1. **Limited money. The market IS the city's purse.** A city pays sellers from its treasury and
   keeps what buyers pay. Full conservation: no infinite market.
2. **Merchants pay full running costs (1.0)**, the same as a player. Some laps will lose.
3. **"Goods a city lacks" = only goods the city does not sell** (0087's rule, kept). Decided; the
   under-target variant is dropped.
4. **Debt, not decay.** A city may go below zero. Debt drives city-to-city interaction: war,
   donations, help from NPCs.
5. **Everyone may invest in cities**: players, and merchants at any harbour on their loop.

Also decided 10-15: the 70k-ships idea is dropped; the soft day/night edge stays; merchant ship
slots + combat stats, more ship types and more gear are wanted (not this plan).

Everything below is grounded in the live chain (`supabase/migrations/`, head 0121) and cites
`file:line` as `NNNN:line` (the file is `20260818000NNNN_*.sql`). Where a function has been re-cut
by later slices, the line cited is its last full definition and the slices are named; every
migration here reads the LIVE body with `pg_get_functiondef` (LF-normalised, the helper shape of
0114:606-619) and asserts each hunk occurs exactly once before replacing it.

---

## 0. The answer in twelve lines

1. **A city has one purse, `public.port_treasury.ducats`, with no floor**, and ONE mover,
   `public.treasury_post`, the way a house has `players.ducats` and `public.credit` (0004:216-241).
   Nothing else writes a treasury.
2. **The market is that purse.** `cmd.do_buy`'s whole payment goes into the city and `cmd.do_sell`'s
   whole receipt comes out of it (0022:761, 0022:831 — one-line hunks). The tax and spread are not
   separate flows any more: they are the city's margin on the round trip. Wages, dues, supplies,
   repairs, hire, building, tuition and officer wages are paid INTO the city where they happen.
3. **Every house↔city transfer is one of two functions**, `public.pay_city` (house → city) and
   `public.city_pays` (city → house), each `credit()` + `treasury_post()` in one transaction, with
   the same argument shape as `credit()` so every verb is a one-line hunk and its event payload
   stays byte-identical.
4. **Income is posted at the charge, never by a tick**: one INSERT into append-only
   `treasury_flows`, no treasury row lock on the trade path. **One hourly job, `byeharu-voyage:city`
   at :37**, rolls flows into balances and a per-(port, game-day, kind) daybook, computes each
   city's state, moves aid, runs wars, subscribes works, accrues coupons, and asserts
   `balance = Σ daybook` for every harbour.
5. **Merchants pay 1.0** (`npc_cost_mult` 0 → 1; the one reader `public.running_cost_mult`,
   0114:92-103, is untouched). The 0120 planner already subtracts wages at that multiplier
   (0120:244-245, 267-268), so fewer loops pay, more laps sail in ballast, and some lose.
6. **A city in debt is a city with worse prices and nothing to spend.** The ONE price reader of
   tax, `world.tax_rate` (0005:318-324), gains a debt surcharge that grows with debt ÷ credit line,
   and a war tax. Every quote (0022:390), the planner, the board and the Market tab read it.
   In debt a city refounds nobody, posts no request, builds nothing, gives no aid — it still pays
   sellers (a broke city keeps buying, as the owner said) and still pays its coupons.
7. **Default** = debt past the credit line (`city_credit_days` of its own trade income). In default
   the surcharge is at its cap, coupons are suspended, and the war clock starts. Debt cannot run
   away: the only outflow left is paying sellers at the capped price, and a knob
   (`city_debt_floor_mult`, off by default) makes the quay refuse to buy past a floor.
8. **Three ways out of debt that touch other actors**: **aid** (richer harbours in the region give
   a tenth of their excess an hour), **donations** (a player's `DONATE`; a merchant with a surplus
   whose home is broke gives — the "NPC aid"), and **war** (a harbour in default for
   `war_debt_days` raids the richest harbour of its region; the winner takes a quarter of the
   loser's balance). Two more that are its own doing: buyers pay the surcharged ask, and houses
   buy its shares.
9. **Works are built with other people's money.** A level of docks / market / production / inn is
   100 shares; houses buy them (`INVEST`, players docked there; merchants at any stop of their
   loop from their surplus), the city subscribes the rest from its own surplus — and that
   subscription is paid to its region's other harbours, not destroyed. A level pays its holders a
   fixed coupon per game-day: that coupon is the upkeep that can push a city into debt. Nothing is
   minted or burned: **world money is constant** after one stated seed.
10. **Refounds stop minting.** `npc_tend`'s refound (0115:204-209) draws from the home harbour above
    its reserve, partially if that is all there is, or not at all.
11. **Bounties are the request board (0087), funded by escrow** at posting, only for goods the city
    does not sell (0087:241, the owner's answer 3), only when solvent and not at war.
12. **Dark first, seeded once.** `city_treasury_enabled` false (the 0092:124-129 shape). Flows post
    from day one; nothing else changes until `select public.city_treasury_switch(true)`, which
    seeds every harbour from its own first day of books and refuses to light a world that is
    arithmetically broke (§7.1).

---

## 1. The money as it moves today, and after

### 1.1 Every faucet and every sink on the live chain (head 0121)

Gold exists only as `players.ducats` (CHECK ≥ 0, 0004:54), moved only by `public.credit`
(0004:216-241: locks the player row :228, refuses an overdraft :233-236 — re-cut to `cmd.refuse`
by 0050:673-677 — writes one `ledger` row :238-239). Every `credit()` call on the chain and where
its money comes from or goes to:

| Kind | Where | Direction | Counterparty today |
|---|---|---|---|
| `FOUNDING` | `new_house` 0004:300-302 → 0096:469-472 (`p_ducats`, `p_is_npc`); `starting_ducats` 8,000 | **faucet** | nothing. Each merchant at seeding: capital + officer wages + tuition (`npc_found` 0097:287-298) |
| `NPC_REFOUND` | `npc_tend` 0114:550-553 → sliced 0115:204-209: purse < capital × `npc_purse_floor_pct` (0.20, 0097:84) and no refound in `npc_refound_cooldown_game_days` (30) → `credit(house, 'NPC_REFOUND', capital − purse)` | **faucet** | nothing. The weekly cap was deleted in 0115 (0115:22-23), so one top-up per company per real day, unbounded |
| `SELL` | `cmd.do_sell` 0022:770-838 (sliced 0050, 0061, 0080-0083, 0096): `credit(SELL, +q.total)` :831. bid = mid × (1 − spread/2) × (1 − tax) (0022:407) | **faucet** | the market, an infinite purse |
| `PREMIUM` | `cmd.run_fulfil` 0087:445-449 | **faucet** | nothing (8–20 % of mid × qty, 0087:172-175) |
| `BUY` | `cmd.do_buy` 0022:674-768 (sliced 0050, 0061, 0080-0083, 0096): `credit(BUY, −q.total)` :761; ask = mid × (1 + tax + spread/2) (0022:400) | **sink** | the market |
| `WAGES` | `voyage.settle` 0027:299-308 → 0086:162-169 (`crew_wages`) → 0114:622-630 (`× running_cost_mult`): `−least(wages, purse)` per settled sea-day (0027:306-307) | sink | nothing. **Merchants pay 0 since 0116:40-44** |
| `PROVISION` | `cmd.do_provision` 0017:327-329 (cost × mult, 0114:632-636) | sink | nothing; merchants 0 |
| `REPAIR` | `cmd.do_repair` 0007:751-753 (cost × mult, 0114:638-643) | sink | nothing; merchants 0 |
| `HIRE` | `cmd.do_hire` 0007:689-692 (pool floor for merchants 0097:944-959) | sink | nothing. Merchants DO pay this |
| `BUILD` | `cmd.do_build` 0072:269-271 (`−h.ducats`) | sink | nothing. `ship_classes.build_cost` (0002:162) is read by nothing |
| `TUITION` | `cmd.study_skill` 0016:235-241 | sink | nothing |
| `OFFICER_WAGE` | `public.sign_officer` 0096:562-568 | sink | nothing |
| harbour dues | `port_fee_per_ship` 50 (0001:166) | — | **read by nothing** |
| pirates | `voyage.settle` 0027:340-351: `RANSOM` "We paid them off" costs 0; `PLUNDERED` leaves the cargo | — | no money moves |

Transfers between purses: **none**. No player-to-player trade, no city purse. Every movement is a
house against the void. For a merchant since 0116: SELL ≥ (paid + 5 %), costs ≈ HIRE only, so every
lap is net-positive and nothing takes it back. That is the owner's complaint.

### 1.2 After this plan: one closed loop

```
  FOUNDING (new player, 8,000)        SEED (once, at the switch — §7.1)
            │                                   │
            ▼                                   ▼
   ┌────────────────────┐   BUY (whole ask) · DUES · WAGES · PROVISION · REPAIR · HIRE · BUILD ·
   │  players.ducats    │   TUITION · OFFICER_WAGE · DONATION · SHARE          ──────────────▶  ┌──────────────────────┐
   │  merchants+players │                                                                       │ port_treasury.ducats │
   │                    │ ◀──────────  SELL (whole bid) · REFOUND · PREMIUM (escrowed) ·        │ 237 harbours,        │
   └────────────────────┘              DIVIDEND (coupon)                                        │ may be < 0           │
                                                                                                └──────────┬───────────┘
   city ↔ city, inside the hourly job:   AID_OUT/AID_IN · WORKS_OUT/WORKS_IN (a city's own          │
   subscription is paid to its region) · INDEMNITY_OUT/INDEMNITY_IN (war)   ◀───────────────────────┘
```

**What is still created**: a new player's 8,000, and the one-time seed. **What is still
destroyed**: nothing by design. Two small stated leaks: (a) the wages of a voyage that never
arrives (ADRIFT / UNABLE_TO_SAIL, 0027:412-414 — no verb refloats one) are paid by the house and
never reach a city; (b) voyages already at sea when 0122 lands have settled days without a
`wages_paid` figure, so their earlier wages are not posted. Both are visible in the watch query
(§9.2) as a negative drift, and both are tiny against turnover.

**Conservation, stated as arithmetic.** World money `W = Σ players.ducats + Σ port_treasury.ducats
+ Σ unrolled treasury_flows`. Per merchant lap (0116's net: `sold − bought − supplies − repairs −
wages + stock_out − stock_in`, 0116:101), the cities as a whole lose exactly `net − dues − hire`
of it and gain the rest back as the lap's costs. A merchant whose purse passes
`npc_invest_above × capital` returns the surplus above `npc_invest_keep × capital` to cities the
same hour (shares, or a donation to a broke home — §5, §6). So Σ merchant purses is bounded by
about `npc_invest_above × Σ capital`, and **the cities together hold `W − that`**. Which cities
are in debt is then a distribution question — sinks lose, producers gain — and aid, donations,
investment, the surcharge and war move it around. The seed must make `W` large enough that the
cities together are solvent (§7.1): `city_treasury_switch(true)` refuses to light a world where it
is not.

---

## 2. 0122 — a city keeps a purse: the books, the charges, the roll, the switch (dark)

### 2.1 Tables

```sql
create table public.port_treasury (
  port_id        uuid primary key references public.ports(id) on delete cascade,
  ducats         bigint not null default 0,        -- NO floor: the owner's answer 4
  rolled_at      timestamptz not null default now(),
  -- written by the roll (one UPDATE an hour), read by world.tax_rate and the spenders:
  credit_line    bigint not null default 0,
  reserve        bigint not null default 0,
  state          text   not null default 'solvent' check (state in ('solvent', 'debt', 'default')),
  debt_surcharge numeric(6,4) not null default 0,
  default_since_day int,
  updated_at     timestamptz not null default now()
);
-- one row per HARBOUR (ports.kind = 'HARBOUR', 0036:182-186), seeded at 0 — no faucet at deploy.
-- RLS: readable by anon + authenticated (world data, the port_buildings posture 0067:119-123);
-- written by nobody but the server (client_write_grants() = 0, 0001:291).

create table public.treasury_flows (           -- APPEND-ONLY; the trade path writes here and nothing else
  id         bigint generated always as identity primary key,
  port_id    uuid not null references public.ports(id),
  kind       text not null,                     -- §2.5
  ducats     bigint not null,                   -- signed: + into the city, − out
  player_id  uuid references public.players(id),   -- the house on the other side; null for city↔city and SEED
  ref_event  uuid references public.events(id),    -- the house's event when there is one
  created_at timestamptz not null default now()
);
create index on public.treasury_flows (port_id, created_at);

create table public.treasury_daybook (         -- one row per (port, game-day, kind); the city's book
  port_id uuid not null references public.ports(id),
  game_day int not null, kind text not null, ducats bigint not null,
  primary key (port_id, game_day, kind)
);

alter table public.voyages add column wages_paid bigint not null default 0;   -- §2.3, wages
```

Why flows + daybook and not a per-movement ledger like a house's: `credit()` takes the player row
`for update` (0004:228); a treasury row lock per trade would make every PROVISION at Lisbon wait
for the arrivals tick whenever a merchant traded at Lisbon inside it (`tick_arrivals` settles every
due fleet in one transaction, 0010:67-75, and its locks live to commit). An INSERT locks nothing.
The daybook is `trade_daily`'s shape (0022:748-750, `on conflict … do update set qty = qty +
excluded.qty`); rows older than `treasury_days_kept` collapse into one `CARRIED` row per city
(the `NPC_CARRIED` discipline, 0097:884-885).

Append-only: a trigger `public.tg_treasury_append_only` refuses UPDATE/DELETE on `treasury_flows`
and `treasury_daybook` unless `current_setting('byeharu.treasury_roll', true) = 'on'`, set
transaction-locally by `tick_city` alone — the `forbid_mutation` re-cut's shape (0097:932-943). A
sibling trigger, not a re-cut of `forbid_mutation`, because that one's exemption reads
`old.player_id … is_npc` (0097:938-940), which these rows do not carry. Autovacuum as 0095:87 /
0097:1025-1029 (`scale_factor = 0, threshold = 2000`) on both tables.

### 2.2 The movers — the only four functions that touch a treasury

```sql
public.treasury_post(p_port uuid, p_kind text, p_delta bigint, p_player uuid, p_ref_event uuid) returns bigint
  -- one INSERT into treasury_flows. No floor, no lock. Server-only.
public.treasury_balance(p_port uuid) returns bigint
  -- ducats + Σ flows after rolled_at (≤ 1 h of rows by index). Server-only.
public.pay_city (p_player uuid, p_port uuid, p_kind text, p_amount bigint, p_event uuid) returns bigint
  -- credit(p_player, p_kind, −p_amount, p_event) then post(+p_amount). The house's refusal
  -- (E_INSUFFICIENT_FUNDS, 0050:673-677) stays the house's.
public.city_pays(p_port uuid, p_player uuid, p_kind text, p_amount bigint, p_event uuid) returns bigint
  -- post(−p_amount) then credit(+p_amount). NO floor: this is how a city goes into debt.
public.city_treasury_on() returns boolean     -- wc('city_treasury_enabled') = 'true' (0092:291-294 shape)
```

`pay_city`'s argument order mirrors `credit(p_player, p_kind, p_delta, p_ref_event)` with the port
inserted after the player and the sign flipped, so **every verb's hunk is the first line of its
existing `credit(` call and nothing else** — the event payload after it is not touched. All four
revoked from `public, anon, authenticated` (0050:678's posture).

### 2.3 The charges — each is ONE hunk in a live body, asserted to occur exactly once

| Charge | Live body | Hunk (old → new) |
|---|---|---|
| BUY | `cmd.do_buy` 0022:761 (payload re-cut by 0083:276-278; the first line is unchanged — no file after 0022 contains the literal `credit(f.player_id, 'BUY', -q.total,`, so no slice ever replaced it) | `perform public.credit(f.player_id, 'BUY', -q.total,` → `perform public.pay_city(f.player_id, f.port_id, 'BUY', q.total,` — the city receives the whole ask, tax and spread inside it |
| SELL | `cmd.do_sell` 0022:831 | `perform public.credit(f.player_id, 'SELL', q.total,` → `perform public.city_pays(f.port_id, f.player_id, 'SELL', q.total,` — the city pays the whole bid, from its purse, below zero if it must |
| provisions | `cmd.do_provision` 0017:327 | `perform public.credit(f.player_id, 'PROVISION', -v_cost,` → `perform public.pay_city(f.player_id, f.port_id, 'PROVISION', v_cost,` |
| repairs | `cmd.do_repair` 0007:751 | the same shape, `'REPAIR'` |
| hire | `cmd.do_hire` 0007:690 | the same shape, `'HIRE'` (the merchant pool floor at 0007:689 as re-cut by 0097:944-959 is untouched) |
| build | `cmd.do_build` 0072:269 | `perform public.credit(f.player_id, 'BUILD', -h.ducats,` → `perform public.pay_city(f.player_id, f.port_id, 'BUILD', h.ducats,` |
| tuition | `cmd.study_skill` 0016:235-238 (four lines: `perform public.credit(` / `v_player,` / `'TUITION',` / `-v_cost,`) | → `perform public.pay_city(` / `v_player, v_fleet.port_id,` / `'TUITION',` / `v_cost,` — the harbour the fleet lies in, the one `v_port` is read from (0016:203; `v_port` is a record of code/name/has_academy, not a row with an id) |
| officer wage | `public.sign_officer` 0096:562-565 | → `pay_city(v_player, <port>, 'OFFICER_WAGE', v_off.wage_ducats,` where `<port>` is the fleet's port when `p_fleet` is given, else the officer's home port (the seed carries one per officer, 0073:149) |
| wages of a sea-day | `voyage.settle` 0027:303-308 as re-cut by 0114:626-629 | `perform public.credit(f.player_id, 'WAGES', -least(v_wages, (select ducats …)));` → `v_paid := least(v_wages, (select ducats …)); perform public.credit(f.player_id, 'WAGES', -v_paid); update public.voyages set wages_paid = wages_paid + v_paid where id = v.id;` (plus `v_paid bigint;` in the declare block). The house side is unchanged to the ducat; `v` is re-read each day at 0027:405 |
| wages of the leg + dues + dividends, at arrival | `voyage.settle` arrival branch 0027:417-425; anchor = the two lines `from public.voyage_events ve where ve.voyage_id = v.id)));` + `perform cmd.advance(p_fleet, p_now);` (unique together — `cmd.advance` alone also occurs at 0027:277) | `perform public.emit_event(f.player_id, 'VOYAGE_REPORT',` → `v_report := public.emit_event(f.player_id, 'VOYAGE_REPORT',`; then, before the advance, when the destination is a HARBOUR: `treasury_post(v.dest_port_id, 'WAGES', v.wages_paid, f.player_id, v_report)`; `pay_city(f.player_id, v.dest_port_id, 'DUES', least(purse, round(ships × wc_num('port_fee_per_ship') × running_cost_mult(f.player_id))), v_report)` — 0001:166 finally read, with the wages' own `least(…, purse)` floor; and (0125) the dividend payout §6.4 |
| merchant running costs | knob | `npc_cost_mult` 0 → **1** (0116:40-44 is the live line). Readers untouched: `running_cost_mult` 0114:92-103 in settle / provision / repair / `npc_leg_lines` 0120:244-245 |

Nothing else moves. `cmd.haggle` (0022:430) and the fairs (0026) move no money; `cmd.do_dismiss`
(0086:172) moves none.

### 2.4 The roll, the read, the job, the switch

- `public.tick_city(p_now)` in 0122 does steps 1 (ROLL), 2 (CARRY), 3 (STATE — but with the
  switch off it writes `state = 'solvent'`, `debt_surcharge = 0`), 10 (ASSERT) and 11 (RECEIPT) of
  §8. Cron `byeharu-voyage:city` on `37 * * * *`, **defined inactive** (the 0012:101-119 rule),
  activated by `wind_the_clock()` (0078:182-200), which activates whatever `clock_jobs()` names —
  the `byeharu-voyage:%` prefix (0078:147-148) picks it up without touching 0078. **0078's own
  self-assert pins the job NAMES (0078:262, `c_expected`) at 0078's apply, which on a from-zero
  chain runs before 0122 — not broken by a sixth job; the implementer greps `scripts/db/proofs/*`
  for any literal job list before shipping.** Local (PGlite, no pg_cron): the local backend already
  runs `public.tick_arrivals(now())` before a merchant read (`src/lib/rpc/localBackend.ts:38-41`);
  it runs `public.tick_city(now())` the same way before a `worldTreasury` read.
- `world.treasury(p_port)` — the one read for the city panel (§10): balance, state, credit line,
  reserve, the rate the quay charges (`world.tax_rate`), war (0126), works and the viewer's shares
  (0125), last game-day's book by kind, `enabled`. Authenticated-only; registered in
  `public.client_rpc_entry_points()` by the 0121:326-338 slice shape, anchored on the row
  `('world', 'fleet_trades', 'uuid'),` (0121:336). Catalogue `worldTreasury` in
  `src/lib/rpc/catalog.ts` beside `worldPortMerchants` (:319).
- `public.city_treasury_switch(p_on boolean)` — the 0097:903-920 shape. `true`: if no `SEED` flow
  exists yet, seed every harbour (§7.1) and refuse if the world is broke; set the flag. `false`:
  the flag only — books keep posting, every consequence stops at once (every reader asks
  `city_treasury_on()`).

### 2.5 Flow kinds (all of them, so the daybook's vocabulary is one list)

In: `BUY DUES WAGES PROVISION REPAIR HIRE BUILD TUITION OFFICER_WAGE DONATION SHARE AID_IN
WORKS_IN INDEMNITY_IN BOUNTY_LAPSED SEED`. Out: `SELL REFOUND BOUNTY DIVIDEND AID_OUT WORKS_OUT
INDEMNITY_OUT`. Book-keeping: `CARRIED`. The player-side ledger kinds do not change except three
new ones: `DONATION`, `SHARE`, `DIVIDEND` (plus `DUES`), so the client's ledger words are untouched
and `docs/WORDS.md` gains four words.

### 2.6 Knobs (0122)

| Key | Start | Why |
|---|---|---|
| `city_treasury_enabled` | `false` | dark first |
| `npc_cost_mult` | 0 → **1** | the owner's answer 2. Rollback: `update world_config set value = to_jsonb(0)` |
| `port_fee_per_ship` | 50 (exists, 0001:166) | finally read |
| `treasury_days_kept` | 30 game-days (= 1 real day) | the daybook window |
| `city_seed_days` / `city_seed_min` | 10 / 20,000 | §7.1: what the switch seeds a harbour with — ten game-days (8 real hours) of what it pays sellers, never under 20 k |

### 2.7 Self-asserts (as found, every probe rolled back)

- Shape: the tables; the trigger refuses UPDATE/DELETE without the GUC and allows DELETE with it;
  `city_pays` takes a probe harbour below zero (no refusal) — the positive control for "debt".
- Every hunk occurs exactly once in each live body; the pre-image is byte-identical outside it.
- A probe house BUYs at a probe harbour: the purse moves −`q.total` exactly as the pre-image, the
  BOUGHT payload is byte-identical, and a `BUY` flow of +`q.total` with `ref_event` = that event
  appears; the same for SELL (−`q.total`), PROVISION, REPAIR, HIRE, BUILD, TUITION, OFFICER_WAGE
  (purse delta + flow = 0, ledger kinds unchanged).
- A probe voyage settled to arrival at a HARBOUR: `voyages.wages_paid` = Σ of the per-day WAGES
  debits; a `WAGES` flow of that sum and a `DUES` flow of `ships × 50 × mult`, both with `ref_event`
  = the VOYAGE_REPORT event; a SEA_PLACE arrival posts nothing. `running_cost_mult(merchant) = 1`.
- `tick_city(now())` on the live world inside a rolled-back probe: completes under 20 s (the
  receipt prints `ms` per step), `balance = Σ daybook` for every harbour, flows table empty of
  rows ≤ p_now, and with the switch off every state is `solvent` with surcharge 0.
- Dark: with the switch off a probe BUY still posts a flow; `world.tax_rate(every harbour)` equals
  the pre-image to the digit.
- Grants: the four movers and `tick_city` not executable by `anon` / `authenticated`;
  `world.treasury` authenticated-only and in the registry; `client_write_grants()` = 0; the 0097
  scan (no body contains `auth_uid is null`).
- The job is defined, inactive, named `byeharu-voyage:city`, listed by `clock_jobs()`.

### 2.8 Cost

Trade path: +1 INSERT per BUY/SELL/PROVISION/REPAIR/HIRE/BUILD/TUITION/OFFICER_WAGE, +2 per
arrival, +1 column write per settled sea-day inside an UPDATE the loop already makes (0027:403).
No new lock. Against the arrivals job's 14.3 s average / 46.8 s max (`docs/RESUME.md:29`) that is
tens of milliseconds a minute. `tick_city`: 237 balances, ≤ 2 k daybook upserts, one delete — under
a second. `tick_reconcile` (66.7 s of 120): untouched by 0122.

---

## 3. 0123 — a city that cannot pay owes: the debt rules

### 3.1 The state, computed once an hour (step 3 of `tick_city`), read everywhere

For each harbour, from its daybook over the last `treasury_days_kept` game-days (mean per
game-day over the game-days that have any row, at least 1):

- `trade_in` = mean of `BUY + DUES + WAGES + PROVISION + REPAIR + HIRE + BUILD + TUITION +
  OFFICER_WAGE` per game-day (its own earning power; aid, donations, shares, seed excluded).
- `sell_out` = mean of `SELL` per game-day (what it must keep paying).
- `credit_line = greatest(wc_int('city_credit_min'), round(wc_num('city_credit_days') × trade_in))`.
- `reserve = round(wc_num('treasury_reserve_days') × sell_out)`.
- `state`: `solvent` if `ducats ≥ 0`; `debt` if `−credit_line < ducats < 0`; `default` if
  `ducats ≤ −credit_line`. `default_since_day` is set on entering default, cleared on leaving.
- `debt_surcharge = case when ducats < 0 then round(wc_num('tax_debt_max') × least(1, −ducats /
  credit_line), 4) else 0 end`.

One UPDATE over 237 rows. The rolled balance is used, so prices move once an hour and never flap
inside it (stated).

### 3.2 What debt does — one reader per effect

| Effect | Reader (live) | Composition |
|---|---|---|
| **prices** | `world.tax_rate(p_port)` 0005:318-324 — the one reading, called by `world.price` 0005:388 and `world.quote` 0022:390 (and so by `do_buy`, `do_sell`, the leg planner 0120:260-266, the board's mid 0087:317, the Market tab) | `least(wc_num('tax_rate_max'), coalesce(p.tax_rate, wc_num('tax_rate_default')) + case when public.city_treasury_on() then coalesce(t.debt_surcharge, 0) + case when public.city_at_war(p_port) then wc_num('war_tax') else 0 end else 0 end)` from `ports p left join port_treasury t`. Unknown port → `tax_rate_default`, as today. In debt the ask rises and the bid falls together (0022:400, :407): the city pays sellers less per unit and sells dearer; the 0120 chooser (scores loops through quotes, 0120:609) routes merchants around it by itself — no planner change |
| the Market tab prints the rate the quay charges | every read that prints `'tax_rate', p.tax_rate` (0009:81, 0019:591 and :635, 0028:281, 0029:169, 0032:140 and :226 — the live bodies of `world.market`, last full definition 0032:189, and the port read) | sliced to `'tax_rate', world.tax_rate(p.id)`; the migration greps `pg_proc.prosrc` for the literal and slices every live occurrence |
| **credit limit** | `public.city_can_spend(p_port, p_amount)` = `treasury_balance(p_port) − reserve ≥ p_amount and state = 'solvent' and not city_at_war(p_port)` | the ONE gate every spender asks: refound (§3.3), bounty escrow (§3.4), own subscription and aid out (0124/0125). A city in debt spends nothing |
| **what it can still buy** | `cmd.do_sell` (0022:770; the live refusal shape is 0050's `cmd.refuse`) | nothing changes while `city_debt_floor_mult` = 0: a broke city keeps buying at the surcharged bid. With the knob > 0: before the quote (0022:811), `if public.city_refuses_to_buy(f.port_id) then refuse 'E_CITY_BROKE' ("Cadiz cannot pay for cargo")` where the predicate is `state = 'default' and ducats ≤ −mult × credit_line`. A merchant's refused SELL is skipped by the executor's skip law and the cargo rides on; the 0120 cut-loss rule handles repeats |
| **coupons** (0125) | the accrual statement | paid in `debt`, suspended in `default` |
| **the war clock** (0126) | `default_since_day` | war after `war_debt_days` in default |

Debt cannot run away: in default the surcharge is capped, no spender fires, coupons stop, and the
only remaining outflow is paying sellers at a bid the planner's keep test (≥ 5 % over the source
ask, 0120:267-268) rarely accepts — and the floor knob closes even that if the owner turns it on.

### 3.3 Refounds, paid by the home harbour

`npc_tend`'s refound (0114:550-553 as sliced by 0115:204-209) becomes:

```
        v_can := case when public.city_treasury_on()
                      then greatest(0, least(hh.capital - hh.ducats,
                             public.treasury_balance(hh.home_port_id) - public.treasury_reserve(hh.home_port_id)))
                      else hh.capital - hh.ducats end;
        if v_can > 0 then
          perform public.city_pays(hh.home_port_id, hh.player_id, 'REFOUND', v_can,
            public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
              'company', hh.company_name, 'amount', v_can, 'port', <home code>, 'partial', v_can < hh.capital - hh.ducats)));
          v_refound := v_refound + 1;
        else
          v_unfunded := v_unfunded + 1;      -- in the receipt
        end if;
```

The company loop (0114:514-560) stays a loop (`credit()` is per house; the cooldown bounds it to
one per company per real day). `hh` gains `home_port_id` from `npc_houses` (0097:118). Dark, the
old amount is minted as today — so the switch, not the migration, changes behaviour. The event kind
`NPC_REFOUNDED` is kept (the card reads it; `npc_compact` keeps it, 0097:891). A merchant whose home
cannot pay is not parked (0115): she sails in ballast at full wages (floored at her purse,
0027:306-307) until her home earns, is aided, is donated to, or wins a war. The ledger kind of the
city-side flow is `REFOUND`; the house side stays `NPC_REFOUND`.

### 3.4 Bounties: the request board, escrowed — the owner's answer 3 (a) only

`public.trade_contracts` (0087:178-205) and `public.contract_draw` (0087:215-262) are kept as they
are: a request is for a good the port does NOT offer (`not public.port_offers(p_port, g.id)`,
0087:241; the arbitrage reason at 0087:46-49). Slices:

| Live body | Hunk |
|---|---|
| `public.tick_contracts(uuid, timestamptz)` 0087:272-331 | in the posting loop, after the draw and the mid (0087:317-318) and before the INSERT (0087:319): `continue when public.city_treasury_on() and not public.city_can_spend(p_port, round(v_per_unit × v_draw.qty) × wc_num('bounty_reserve_mult'))` — a city in debt or at war posts nothing; after a successful INSERT: `perform public.treasury_post(p_port, 'BOUNTY', −premium_ducats, null, null)` — **escrow at posting**. The expire UPDATE (0087:297-299) gains `returning premium_ducats` into one `treasury_post(p_port, 'BOUNTY_LAPSED', +Σ, null, null)` |
| `cmd.run_fulfil(uuid, uuid)` 0087:391-469 | **unchanged**: `credit(f.player_id, 'PREMIUM', c.premium_ducats, v_event)` (0087:449) stays — the escrow already left the treasury at posting. Dark, the escrow is posted too (the books are full when the switch flips); the premium is still minted on the house side, which is why §7 lights the switch after a day, not two |
| `world.contracts(p_port)` 0087:342-380 | unchanged (an unfunded request is never posted, so the client needs no new state) |

Merchants do not fulfil requests (the planner reads `world.trade_routes`, not the board). Bounties
stay a player's income and a city's spend.

### 3.5 Knobs (0123)

| Key | Start | Why |
|---|---|---|
| `city_credit_days` / `city_credit_min` | 10 / 20,000 | a city may owe ten game-days (8 real hours) of its own trade income before default; never less than 20 k so a quiet harbour has credit |
| `treasury_reserve_days` | 3 | a city keeps 2.4 real hours of what it pays sellers before it refounds, posts, builds or gives |
| `tax_debt_max` | 0.12 | at the credit line the quay charges 3 % + 12 %: bid ≈ 0.82 × mid, ask ≈ 1.18 × mid — long hauls still pay (the affinity span reaches 1.76×, 0120:29-32), neighbours do not |
| `tax_rate_max` | 0.25 | the cap on the composed rate; the column's own band stays 0–8 % (0002:101) |
| `city_debt_floor_mult` | 0 (off) | > 0: a harbour this many credit lines into default refuses to buy (`E_CITY_BROKE`) |
| `bounty_reserve_mult` | 2 | a request is posted only when the surplus covers it twice |

### 3.6 Self-asserts (0123)

- Probe harbours at balances `+100 k`, `−1`, `−credit_line`, `−3 × credit_line`: states
  `solvent / debt / default / default`; `debt_surcharge` 0 / ≈0 / 0.12 / 0.12; `world.tax_rate`
  reads `0.03`, `0.03 + ε`, `0.15`, `0.15` with the switch on and `0.03` for all four with it off;
  `world.quote` sell-side at the defaulted harbour pays `(1 − 0.15)/(1 − 0.03)` of the pre-image per
  unit on the same stock, buy-side `(1.15 + s/2)/(1.03 + s/2)`.
- `city_can_spend`: false for every state but `solvent`, false under reserve, false at war (0126
  re-asserts).
- `do_sell` at a probe harbour at `−3 × credit_line`: with the floor knob 0, the sale lands and the
  balance falls by `q.total`; with the knob 2, `E_CITY_BROKE` and nothing moves.
- Refound: funded home → `REFOUND` flow − and `NPC_REFOUNDED` with `partial` false; home at
  reserve + 100 → 100, `partial` true; home at reserve → no flow, receipt `refound_unfunded` = 1;
  switch off → the old amount is minted. The live `npc_tend` body no longer contains
  `'NPC_REFOUND', hh.capital - hh.ducats` outside the dark branch.
- Board: a probe harbour in debt posts 0 where the pre-image posted 1; solvent and funded: posts 1
  and a `BOUNTY` flow of −`premium_ducats`, Σ(treasury + escrow) unchanged; warp past expiry →
  `BOUNTY_LAPSED` of the same sum; fulfil with a probe house → `PREMIUM` ledger row = the row's
  `premium_ducats` (0087's own assert), no treasury flow at fulfilment. No posted request names an
  offered good (`port_offers` false on every open row — 0087 (b) re-asserted).
- The Market read prints `tax_rate` = `world.tax_rate(p.id)` on a probe harbour in debt.

---

## 4. 0124 — a city in debt is helped: aid, donations, NPC aid

### 4.1 City → city aid (step 5 of `tick_city`, one CTE per hour)

Per region (`ports.region_id`, 0002:89; 25 regions, 0003:115-122):

- donors: harbours with `state = 'solvent'`, not at war, with `excess = ducats − wc_num('aid_donor_mult') × reserve > 0`;
  each gives `round(wc_num('aid_rate') × excess)`.
- recipients: harbours with `ducats < 0`, not at war; each receives the region's pool × its debt ÷ Σ debts,
  capped at its debt; rounding goes to the largest debtor; a pool larger than Σ debts is cut to Σ debts (donors give less, pro rata).
- flows `AID_OUT` (donor) and `AID_IN` (recipient); Σ over the region is 0 to the ducat.

Not a loop: one INSERT … SELECT of flows; the balances move at the next roll. A region with no
donor moves nothing (the harbour then waits for a donation, investment or its war).

### 4.2 A player's donation

`public.donate_for(p_player, p_port, p_amount)` (the `_for` core shape of 0096:774 /
0096:1028 / 0096:1069) = `pay_city(p_player, p_port, 'DONATION', p_amount, emit_event(DONATED))`;
refuses under `donate_min_ducats` and a port that is not a HARBOUR. Skin `cmd.donate(p_port,
p_amount)` + `cmd.preview_donate` (the `cmd.fulfil` / `cmd.preview_fulfil` pair, 0087:481 /
0087:532): docked at that harbour only — "you hand the purse to the harbourmaster". Not a queue
verb: no change to `cmd.parse`'s grammar. Registered, authenticated-only, `client_write_grants()`
stays 0. A donation to a city at war ends the war early if it lifts the attacker out of debt
(§7.2) — the one way a player can stop a war.

### 4.3 NPC aid — a merchant whose home is broke gives from her surplus

In `npc_tend`'s company loop (0114:514-560), one rule in front of the refound test, under the same
60 s budget (`npc_upkeep_spent()`, 0114:107-119) and the same `≤ npc_invest_max_per_hour` cap it
shares with investment (§6.5):

```
  purse > npc_invest_above × capital
  and home harbour state in ('debt', 'default')
  → public.pay_city(hh.player_id, hh.home_port_id, 'DONATION',
                    least(purse − npc_invest_keep × capital, −home balance),
                    emit_event(hh.player_id, 'NPC_DONATED', {company, port, amount}))
```

A merchant gives before she invests; her home's debt is paid first. Counted `donated` in the
receipt. `NPC_DONATED` joins the kept event kinds of `npc_compact` (0097:891) so the card can say
"gave 4,000 d. to Cadiz".

### 4.4 Knobs (0124)

| Key | Start | Why |
|---|---|---|
| `aid_donor_mult` | 2 | a donor keeps twice its reserve before giving |
| `aid_rate` | 0.10 per hour | a tenth of the excess an hour; a region's rich harbour refloats a neighbour in a few hours, never in one |
| `donate_min_ducats` | 100 | no dust |
| `npc_invest_above` / `npc_invest_keep` | 2.0 / 1.5 × capital | the surplus rule shared with §6.5 |

### 4.5 Self-asserts (0124)

- A probe region with balances (+100 k, +10 k, −5 k, −1 k), reserves 10 k: the first gives
  `0.10 × (100 k − 20 k) = 8 k`, the second nothing (excess 0 → not a donor), the two debtors
  receive 5 k and 1 k (the pool exceeds Σ debts → cut), Σ of the region's flows = 0; a region with
  one donor at war moves nothing.
- `cmd.donate` by a probe house docked there: ledger `DONATION` −n, flow +n, event; not docked →
  refused; under the minimum → refused; `client_write_grants()` = 0; registry rows present.
- NPC aid: a probe merchant at 3 × capital with a home at −2,000 gives 2,000 (not 1.5 × capital
  worth); at a solvent home gives nothing; the receipt counts it; the budget cuts the loop.

---

## 5. 0125 — a city builds with other people's money: works, shares, coupons

### 5.1 Tables

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
  accrued_day int  not null,                        -- accrued through this game-day
  primary key (port_id, kind, player_id)
);
```

Not `ports.*` and not `port_buildings.tier`: `has_yard`, `yard_tier`, `max_draft`, `dev_*`,
`crew_pool` are authored in `data/ports.json` and world-guard holds the applied world equal to the
file (CHAIN.md header); `public.furnish_harbours` (0089:95) holds `port_buildings` (0067:106-111)
to `harbour_buildings`. A level a city raises lives in its own row and composes into a reader;
the authored truth is never written. `public.city_level(p_port, p_kind)` = `coalesce(level, 0)` is
the one reader.

### 5.2 The rules

- `cost(L) = works_cost_base × works_cost_growth ^ (L − 1)`; a level is `shares_per_level` (100)
  shares at `cost(L + 1) / 100` each. A city OFFERS `100 − subscribed` shares of its next level
  while `level < works_level_max`, in every state (buying shares is one way a broke city gets
  money; the preview says coupons are suspended in default).
- **Houses buy**: `public.invest_for(p_player, p_port, p_kind, p_shares)` = refuse `E_NOT_OFFERED`
  / `E_OVERSUBSCRIBED` / under `invest_min_ducats`, then `pay_city(p_player, p_port, 'SHARE',
  price × n, emit_event(INVESTED))`, upsert `city_shares` (+shares, +paid), `subscribed += n`.
  Skins `cmd.invest(p_port, p_kind, p_shares)` + `cmd.preview_invest`, docked there only.
- **The city subscribes the rest** (step 7 of `tick_city`): one (port, kind) per harbour per hour —
  its lowest-level work, ties by kind order — when `city_can_spend(port, k × price)` for
  `k = least(100 − subscribed, floor((balance − reserve) / price))` ≥ 1: `subscribed += k`, and
  the money is **paid to the region's other harbours** split by `size_tier` (0002:91) as
  `WORKS_OUT` / `WORKS_IN` (stone, timber and hands from the coast — "the city must use it for the
  whole world"; nothing is destroyed). A region of one keeps it (no flow).
- **A level completes** when `subscribed = 100`: `level + 1`, `subscribed = 0`, one window UPDATE.
- **Coupon** (step 9): per game-day, each `city_shares` row earns `round(paid ×
  wc_num('works_coupon_pct') × days)` where `days = today − accrued_day`, for harbours whose state
  is not `default`; one UPDATE over all rows, one `DIVIDEND` flow per harbour (−Σ). The city pays
  it from its purse, into debt if it must — **this coupon is the upkeep that keeps a city from
  growing for ever**: a harbour whose trade cannot carry its investors' coupons slides into debt,
  and in default the coupons stop.
- **Payout rides an arrival** (the §2.3 arrival hunk): for each `city_shares` row of (f.player_id,
  v.dest_port_id) with `accrued > 0`: `credit(player, 'DIVIDEND', accrued, v_report)`; `accrued :=
  0`. The flow was posted at accrual, so the books stay conserved whether or not the holder calls;
  a holder who never comes back leaves the float with the city. Merchants dock at every stop of
  their loop every lap, so they are paid each lap.
- The city's own shares are `100 × level − Σ house shares` and pay nothing to nobody.

### 5.3 What a level does — one reader each

| Work | Reader (live) | Composition |
|---|---|---|
| `docks` | `voyage.sail_refusal` E_DRAFT 0036:443-448 (`max(draft) > max_draft`; live via 0047:358 → 0050:316) | `v_maxd + public.city_level(p_dest, 'docks') / wc_int('docks_draft_per_levels')` → +1 draft at levels 2 and 4 |
| `market` | `world.daily_cap_remaining` 0027:445 (`daily_cap_fraction × stock_target …`) and `world.spread` 0026:277-293 | allowance × `(1 + wc_num('market_cap_per_level') × level)`; spread: one more term inside the `greatest(floor, base − per_dev × dev_commerce − per_dev × level)`, floored as today |
| `production` | `public.tick_market_drift` regeneration UPDATE 0010:120-126 (`production_rate × (v_day − last_regen_day)`) | `production_rate × (1 + wc_num('production_per_level') × coalesce(cw.level, 0))` via `left join city_works cw on cw.port_id = pg.port_id and cw.kind = 'production'` — the statement is already set-based over every `port_goods` row once a game-day |
| `inn` | `cmd.do_hire` draws `ports.crew_pool` (0007:689) and no tick refills it (0097:98-99) | a set-based hourly statement in `tick_city` (step 8): `update ports set crew_pool = least(size_tier × wc_int('inn_pool_per_tier'), crew_pool + wc_int('inn_hands_per_level') × level)` for harbours with an inn level, `for update skip locked` (the minute tick's `do_hire` writes the same column) |

Patrols are **not** in this plan: pirates cost no money (0027:349, RANSOM 0) and `voyage.hazard_roll`
must stay pure in (voyage, day) for proof 01's byte-identity (0006:135-138, 0059:13) — a level
that reads a mutable table would break it. A later slice, said so.

### 5.4 Merchants invest anywhere on their loop (the owner's answer 5)

In `npc_tend`'s company loop, after the NPC-aid rule (§4.3) and before the refound test: a company
with `purse > npc_invest_above × capital` and a solvent home buys, through `invest_for`, at the
harbour on any of her routes' stops (`npc_fleets.route_id → standing_route_stops.port_id`) that
offers the most shares, `least(offered, floor((purse − npc_invest_keep × capital) / price))`
shares; at most `npc_invest_max_per_hour` companies an hour (shared with §4.3), oldest purse first,
under the hour's budget. Players and merchants use the same door. Counted `invested` in the
receipt. The merchant card (`world.npc_fleet_card`, 0099:238; `src/live/MerchantSheet.tsx`) gains
one line, `Invested 24,000 d. at Lisbon`.

### 5.5 Knobs (0125)

| Key | Start | Why |
|---|---|---|
| `works_cost_base` / `works_cost_growth` / `works_level_max` | 20,000 / 1.6 / 5 | level 5 = 131 k; the `port_buildings.tier` range (0067:109) |
| `shares_per_level` | 100 | a share of a 20 k level is 200 d.; a 5,000-capital merchant can hold a few |
| `works_coupon_pct` | 0.003 per game-day of what was paid (≈ 9 % a real day; a level pays back in ~11 days) | the upkeep that bites; the first lever if cities slide into debt too fast |
| `invest_min_ducats` | 1,000 | no dust |
| `npc_invest_max_per_hour` | 50 | bounds the loop inside the hour's budget (≤ 50 `credit()`s ≈ 50 ms) |
| `docks_draft_per_levels` / `market_cap_per_level` / `production_per_level` | 2 / 0.10 / 0.10 | +1 draft at docks 2 and 4; +50 % allowance and production at level 5 |
| `inn_hands_per_level` / `inn_pool_per_tier` | 2 per hour / 40 | a level-5 inn restores 10 hands an hour, never past `size_tier × 40` |

### 5.6 Self-asserts (0125)

- Buy: refuses a kind not offered, more than offered, under the minimum; purse + treasury
  conserved; the INVESTED event; `subscribed` moves; a 100th share completes the level.
- Subscription: a probe harbour at reserve + 50 × price subscribes exactly 50 of its lowest work,
  pays `WORKS_OUT` = Σ `WORKS_IN` over its region to the ducat; in debt subscribes nothing; a
  region of one posts no flow.
- Coupon: a probe row `paid 10,000`, warp one game-day → `accrued 30`, a `DIVIDEND` flow of −30 at
  the city; at a harbour in default, nothing accrues. Payout: settle a probe voyage into that
  harbour → `credit(DIVIDEND, 30)`, `accrued 0`, no new flow.
- Composition, each against its pre-image at level 0 (byte parity) and at 5: `sail_refusal` admits
  `max_draft + 2`; `daily_cap_remaining` × 1.5; `world.spread` − 5 × `spread_per_dev` (floored);
  the regen statement's `production_rate × 1.5` on a probe producer row; `crew_pool` + 10 and never
  past the cap.
- `npc_tend`: a probe merchant at 3 × capital with a solvent home buys down to 1.5 × capital at the
  stop that offers most; at 1.9 × buys nothing; the budget cuts the loop (the 0114 `deferred`
  count).

---

## 6. 0126 — a city in default goes to war

### 6.1 Table

```sql
create table public.city_wars (
  id            uuid primary key default gen_random_uuid(),
  attacker_port uuid not null references public.ports(id),
  defender_port uuid not null references public.ports(id),
  declared_at   timestamptz not null default now(),
  declared_day  int  not null,
  ends_day      int  not null,
  status        text not null default 'open' check (status in ('open', 'won', 'lost', 'peace')),  -- from the attacker's side
  indemnity     bigint not null default 0,
  ended_at      timestamptz,
  check (attacker_port <> defender_port)
);
create index on public.city_wars (status);
create unique index city_wars_one_open_per_attacker on public.city_wars (attacker_port) where status = 'open';
create unique index city_wars_one_open_per_defender on public.city_wars (defender_port) where status = 'open';
```

`public.city_at_war(p_port)` = `exists (open war where attacker = p_port or defender = p_port)` —
the one predicate; 0123 ships it as `select false` and this file restates it whole.

### 6.2 How a war starts, what it does, how it ends — all in `tick_city` step 6

- **Declare** (after AID has moved): a harbour with `state = 'default'` and
  `today − default_since_day ≥ wc_int('war_debt_days')`, not at war, with no war ended within
  `war_cooldown_days`, declares on the **richest harbour of its own region** (highest rolled
  balance ≥ `war_target_min_ducats`, not at war, not in cooldown). `ends_day = today + war_days`.
  At most `war_max_declared_per_hour` declarations an hour world-wide. One INSERT … SELECT with a
  window per region. Flavour: the bankrupt harbour sends privateers against its rich neighbour.
- **While open**, both belligerents: `war_tax` on every quote (through `world.tax_rate`, §3.2 — the
  planner routes around them); no requests posted (`tick_contracts`: `continue when
  public.city_at_war(p_port)` — one hunk, 0087:306); no own subscription, no aid given or received
  (`city_can_spend` is false; the AID CTE excludes them). Coupons continue. Trade continues:
  houses are not at war, cities are.
- **Peace**: at any roll where the attacker's balance is ≥ 0 (aid cannot do it — it is excluded —
  so this is a donation, shares bought, or its own trade): `status = 'peace'`, no indemnity. A
  player can end a war by donating.
- **Resolve** at `today ≥ ends_day`: `u = voyage.rng(war.id, ends_day, 'war')` (pure in the war's
  id and day, 0006:127-138); `p_attacker = least(0.9, greatest(0.1, wc_num('war_base_p') +
  wc_num('war_works_p') × (city_level(attacker, 'docks') − city_level(defender, 'docks'))))`.
  Winner takes `round(wc_num('war_indemnity_pct') × greatest(0, loser's balance))` as
  `INDEMNITY_OUT` / `INDEMNITY_IN`. An attacker who loses has nothing to take: it stays in default,
  in cooldown, and its only ways out are the economic ones. Events `WAR_DECLARED` / `WAR_ENDED`
  with `player_id` null (the column is nullable, 0004:113) for the record; the panel reads
  `world.treasury`, not events.
- **Hazard is not touched** (§5.3's reason). War is economic and server-side: two statements an hour.

### 6.3 Knobs (0126)

| Key | Start | Why |
|---|---|---|
| `war_debt_days` | 3 game-days (2.4 real h) in default | long enough for aid and donations to act first |
| `war_days` | 5 game-days (4 real h) | visible for an evening, over by morning |
| `war_cooldown_days` | 10 | no serial raiding |
| `war_target_min_ducats` | 50,000 | nobody raids a pauper |
| `war_tax` | 0.05 | both quays dearer while it lasts |
| `war_base_p` / `war_works_p` | 0.45 / 0.05 per docks level of difference | the desperate side is slightly the weaker; docks are the only strength this plan knows |
| `war_indemnity_pct` | 0.25 | a quarter of the loser's purse |
| `war_max_declared_per_hour` | 10 | a tick bound, not a game rule |

### 6.4 Self-asserts (0126)

- A probe region: harbour A at `−2 × credit_line` for 4 game-days, B at +200 k, C at +60 k, D at
  +10 k: A declares on B (not C); with B at war already, on C; D is never a target. A second
  harbour in default in the same hour declares on the next richest. The cap stops the 11th.
- While open: `world.tax_rate(A) = 0.03 + 0.12 + 0.05`, `world.tax_rate(B) = 0.08`; `tick_contracts(B)`
  posts 0 where the pre-image posted 1; `city_can_spend(B, 1)` false; the AID CTE skips both.
- Peace: A donated to ≥ 0 → `peace`, no flow.
- Resolve: warp to `ends_day`; with `war_base_p` set to 1 the attacker wins and the flows are
  `0.25 × B's balance` both ways (Σ 0); with it 0 the defender wins and nothing moves (A ≤ 0);
  `voyage.rng(war.id, ends_day, 'war')` is the same number twice.
- The unique indexes refuse a second open war per side.

---

## 7. The switch, the seed, and the arithmetic that must hold

### 7.1 `city_treasury_switch(true)` seeds once, then lights

The treasuries start at 0 and the market is the purse, so the first SELL at any harbour would put
it in debt. The switch therefore seeds every harbour **from its own first day of books** (0122 runs
dark for a day first): `seed(port) = greatest(wc_int('city_seed_min'), round(wc_num('city_seed_days')
× mean game-day SELL outflow))`, posted once as a `SEED` flow (the one stated faucet; the receipt
prints Σ). It then asserts the world is not born broke:

```
W_after = Σ players.ducats + Σ seeds   ≥   wc_num('npc_invest_above') × Σ npc_houses.capital + Σ reserve
```

— merchants will hold up to `npc_invest_above × capital` each before they give anything back
(§1.2), so anything less leaves the cities together in debt from day one. If it does not hold the
switch refuses with the two figures, and the owner raises `city_seed_days` (one knob) and calls
again. The first draft quoted Σ capital ≈ 19.7 M from 0105's receipt; the switch reads it, not
this file.

### 7.2 Targets and the levers

| Measure | Target | How it is read |
|---|---|---|
| World money `W` | flat over a day (± new players' 8,000s, − the two stated leaks) | §9.2 |
| Harbours in `debt` / `default` | some, not most: under a third in debt, under a tenth in default, after the first day | `select state, count(*) from port_treasury group by 1` |
| Wars | a few a day, not every hour | `select count(*) from city_wars where declared_at > now() − interval '1 day'` |
| Σ merchant purses / Σ capital | between 1.0 and `npc_invest_above`; flat | `select sum(p.ducats) / sum(h.capital) from players p join npc_houses h on h.player_id = p.id` |
| Merchant lap net | mean positive over a day; a losing share under a third | `select avg(net), avg((net < 0)::int) from standing_route_laps where closed_at > now() − interval '1 day'` |
| Refounds | mostly funded: `refound_unfunded` under a tenth of `refounded` | `tick_reconcile`'s receipt in `cron.job_run_details` |

| Drift | Turn |
|---|---|
| Most harbours in debt | `works_coupon_pct` down; `aid_rate` up; `tax_debt_max` up (debtors earn more per BUY); `city_seed_days` up and re-seed is **not** possible — the seed is once; instead `npc_invest_above` 2.0 → 1.5 (merchants return money sooner) |
| Harbours hoard, merchants starve | `treasury_reserve_days` 3 → 1; `aid_donor_mult` 2 → 1; `works_cost_base` down (they build more and pay the region) |
| Too many wars | `war_debt_days` up; `aid_rate` up |
| Merchants lose too often | `npc_min_return_pct` 5 → 8 (0120:88-92); `npc_cost_mult` 1 → 0.5 (the owner's call) |
| One harbour runs away rich | its `ports.tax_rate` down within the band (0002:101) so it keeps less per trade; `aid_donor_mult` down |

None of these needs a migration; each is one knob with one reader.

---

## 8. `public.tick_city(p_now)` — the one hourly job

Cron `byeharu-voyage:city` on `37 * * * *`. Why :37: `reconcile` is `7 * * * *` (0012:99) and runs
61–72 s; `arrivals` is every minute (0012:97); `drift`, `price-snapshot` and `buff-calendar` are
`tick_cron_expression(600)` = `*/10` (0012:98, 0013:199, 0026:468). :37 is clear of all but the
minute tick. Never waits: `set local lock_timeout = '2s'` (the 0097:971 line) and every UPDATE of a
row the minute tick may hold (`ports`, `voyages`) goes through `for update skip locked`
(0010:72's idiom). Each step in its own `begin … exception when others` block with its error in the
receipt (0097:972-986's shape), except ROLL and ASSERT, which abort the hour (a broken book must
not be rolled past).

```
 1. ROLL      set_config('byeharu.treasury_roll','on',true);
              with f as (select * from treasury_flows where created_at <= p_now for update skip locked),
                   d as (insert into treasury_daybook … select port_id, world.game_day(created_at), kind, sum(ducats)
                         from f group by 1,2,3 on conflict do update set ducats = daybook.ducats + excluded.ducats),
                   b as (update port_treasury t set ducats = t.ducats + x.s, rolled_at = p_now from (…) x …)
              delete from treasury_flows where id in (select id from f);
 2. CARRY     daybook rows with game_day < today − treasury_days_kept → one CARRIED row per port
 3. STATE     §3.1: credit_line, reserve, state, debt_surcharge, default_since_day — one UPDATE
 4. (refounds live in npc_tend, inside tick_reconcile's budget — not here)
 5. AID       §4.1 — one INSERT … SELECT of AID_OUT / AID_IN
 6. WAR       §6.2 — resolve ended wars (flows), make peace, declare new ones
 7. BUILD     §5.2 — own subscription (WORKS_OUT / WORKS_IN), level completions
 8. INN       §5.3 — crew_pool regeneration, skip locked
 9. ACCRUE    §5.2 — coupons, one UPDATE + one INSERT of DIVIDEND flows
10. ASSERT    select count(*) from port_treasury t join (select port_id, sum(ducats) s from treasury_daybook group by 1) x
                using (port_id) where t.ducats <> x.s   → must be 0;
              and Σ AID_OUT + Σ AID_IN = 0, Σ WORKS_OUT + Σ WORKS_IN = 0, Σ INDEMNITY_* = 0 for this hour's flows
11. RECEIPT   jsonb: flows_rolled, states {solvent, debt, default}, aid_moved, wars {declared, peace, resolved},
              subscribed, levels_built, coupons, refound hints, world_ducats =
              Σ players.ducats + Σ port_treasury.ducats + Σ treasury_flows.ducats (unrolled), ms per step
```

Spending flows are written in exactly three places: `tick_city` (aid, subscription, coupons,
indemnity), `npc_tend` (refound, donation, investment — inside `tick_reconcile` at :07, never
concurrent with :37) and `tick_contracts` (escrow, lazy on a read; `bounty_reserve_mult` 2 bounds
the overdraw a lazy post can cause between two rolls). Income flows are written by the verbs
(§2.3) and by `city_treasury_switch` (SEED, once).

Cost: 237 harbours, ≤ 1,000 works rows, ≤ a few thousand share rows, ≤ 2 h of flows, ≤ 60 open wars.
Estimated 1–5 s on prod; the self-assert refuses > 20 s on the live world. Rows/hour ≈ 5–8 k, ~0.5 MB
before vacuum. `tick_market_drift` gains one `left join` on ≤ 237 rows inside an UPDATE that already
touches every `port_goods` row once a game-day. `world.tax_rate` gains one PK join per quote.

---

## 9. Watching it

### 9.1 What to read on day one (dark) and on switch day

Dark day: `select kind, sum(ducats) from treasury_daybook group by 1` — the gross in and out per
kind; `select port_id, sum(ducats) … where kind = 'SELL'` — what each harbour will have to pay; the
city job's receipt times. Switch day: the switch's own receipt (Σ seed, `W`, the inequality's two
sides), then `port_treasury.state` counts every hour for a day.

### 9.2 The one query

```sql
-- world money, hour by hour, from the city job's own receipts (cron keeps the return value)
select start_time, (return_message::jsonb ->> 'world_ducats')::bigint as world_ducats,
       (return_message::jsonb ->> 'world_ducats')::bigint
         - lag((return_message::jsonb ->> 'world_ducats')::bigint) over (order by start_time) as delta,
       return_message::jsonb -> 'states' as states, return_message::jsonb -> 'wars' as wars
  from cron.job_run_details
 where jobname = 'byeharu-voyage:city' and status = 'succeeded'
 order by start_time desc limit 24;
```

`delta` should be ≈ 0 (+8,000 per new player, − the stated leaks). A steady positive delta means a
faucet survived (grep `credit(` for a kind not in §2.5); a steady negative one means a sink
survived or the leaks are bigger than stated.

---

## 10. What the owner will see in the game

- **On a city's Port tab**, at the top: `Treasury 123,456 d.` — or `Owes 12,300 d. · credit
  40,000` in a warning tone, or `Defaulted · owes 61,000 d.` in red. When at war: `At war with
  Seville · 2 game-days left` (and on Seville, `Attacked by Cadiz`). Under it, the works as dots —
  `Docks ●●○○○ · Market ●○○○○ · Production ○○○○○ · Inn ●●●○○` — with `40 of 100 shares offered ·
  200 d. each` and an **Invest** press for a work that is selling, a **Donate** press, and `You hold
  12 · 1,340 d. owed` when the viewer holds shares. The last game-day's book as a few short rows:
  `Trade in · Trade out · Dues · Wages · Aid · Coupons`. A merchant's sheet gains `Invested 24,000 d.
  at Lisbon` and `Gave 4,000 d. to Cadiz` from the card.
- **Prices**: a harbour in debt sells dearer and buys cheaper — the Market tab prints the rate it
  actually charges (`Tax 11 %`), so the owner can see why merchants stopped calling there.
- **Merchants**: with full costs, laps close at a loss sometimes; the lap pills on the fleet panel
  show red laps. A merchant whose home is broke sits at her purse floor sailing in ballast until
  her home is refloated. A rich merchant's purse stops climbing past 2 × her capital: the Port tabs
  of harbours on her loop show her shares.
- **Day one after the switch**: a burst — merchants that earned at zero cost for a day are far above
  2 × capital and invest it within the hour; the rich harbours build a level or two; the sink
  harbours (where merchants sell dear) slide into debt over the first hours, their regions' rich
  harbours send aid, and the first wars start the same evening. Said here so it is not read as a bug.
- **Players**: a new `DONATE` and `INVEST` at a harbour they are docked in; `DUES` of 50 per ship on
  every arrival (a visible new ledger line); a city's request board goes quiet when it is broke.
- **Nothing to press to run a city**: a city spends by itself (the owner's words, "the city must use
  it for the whole world").

---

## 11. Risks, handled and stated

- **The arrivals tick** (14.3 s avg, 46.8 s max, 2-min limit): +1 INSERT per trade, +2 flows and
  ≤ 2 dividend credits per arrival, one column write per sea-day. Tens of milliseconds a minute.
  The hourly job never touches a fleet row and skips what is locked, so the :07/:08 pattern
  (reconcile vs arrivals on fleets) gains no new edge.
- **`tick_reconcile` at 61–72 s of 120**: `npc_tend`'s company loop gains the aid/investment rule
  (≤ 50 `credit()`s an hour) and loses minting refounds, all under the existing 60 s deadline
  (0114:573-603). The roll and every city step live in the new job.
- **`world.tax_rate` is on the hot path** (every quote, 0022:390; the planner prices ≤ 16 loops × 3
  legs × ~5 quotes at a lap start, 0120:74-78): one PK join on a 237-row table and one `wc()` read.
  The surcharge is precomputed hourly, never derived per quote.
- **Determinism of settlement** (proof 01): hazard is untouched; `wages_paid` is a sum of figures
  the loop already computes. The war roll is pure in (war id, day).
- **A from-zero apply** (CI apply-proof, `npm run db:apply`) sees 0078's name assert before 0122
  exists; the implementer still greps the proofs for a literal job list. The world guard holds
  `ports.*` equal to `data/ports.json`; this plan writes `ports.crew_pool` only (which `do_hire`
  already writes) — if a proof holds that column equal, the proof learns it is live.
- **Merchant purses today** (0116 let them earn at zero cost for a day): the day-one burst above.
- **Seed sizing**: the one real unknown; the switch refuses a broke world and prints the two
  figures (§7.1) rather than guessing.
- **The two leaks** (§1.2) are measured by the watch query, not papered over.
- **A city nobody visits in default** sits there inert, surcharge capped, owing — harmless, visible
  on its panel, refloated only by aid, a donation or a war it wins.
- **PGlite** (local saves are fragile — memory): five migrations each `alter`/`create`; the local
  save is demolished by any migration edit anyway, so the local world is rebuilt per step.

---

## 12. Build list, in order

Every migration: self-asserts hold **as found** (lit or dark), every probe rolled back, no long
block run on prod through `db query`; deploy by the runbook `unwind_the_clock()` → `db push` →
`wind_the_clock()` (RESUME 10-14 rules), dry-run on prod inside `begin … rollback` first (the
0119-0121 method, `docs/RESUME.md:18`). Rollback of any step = (1) `city_treasury_switch(false)`
(instant, no migration: every consequence reads the switch); (2) a forward migration that puts the
sliced hunks back (each slice's old text is in the file) — the chain never deletes a migration.
Tables are left in place; they are inert without readers.

| # | Name | What it changes | Self-assert (§) | Knobs | Rollback |
|---|---|---|---|---|---|
| **0122** | `a_city_keeps_a_purse` | tables `port_treasury`, `treasury_flows`, `treasury_daybook`, trigger; `voyages.wages_paid`; movers `treasury_post`, `treasury_balance`, `pay_city`, `city_pays`, `city_treasury_on`; eight verb hunks (six one-line, two four-line) + the settle wages/arrival hunks (§2.3); `tick_city` (roll, carry, state-as-solvent, assert, receipt) + cron `byeharu-voyage:city` inactive; `world.treasury` + registry row; `city_treasury_switch` (seed + flag) | §2.7 | `city_treasury_enabled` false, `npc_cost_mult` 1, `treasury_days_kept` 30, `city_seed_days` 10, `city_seed_min` 20,000 | `npc_cost_mult` back to 0 by knob; a forward slice restoring `credit(` in the nine bodies; `cron.unschedule('byeharu-voyage:city')` |
| **0123** | `a_city_that_cannot_pay_owes` | step 3 STATE for real; `world.tax_rate` debt term + `city_at_war` stub; `'tax_rate', p.tax_rate` prints → `world.tax_rate(p.id)`; `city_can_spend`, `treasury_reserve`, `city_refuses_to_buy` + the `do_sell` floor hunk; `npc_tend` refound from the home harbour; `tick_contracts` escrow + `BOUNTY_LAPSED`, posting gated | §3.6 | `city_credit_days` 10, `city_credit_min` 20,000, `treasury_reserve_days` 3, `tax_debt_max` 0.12, `tax_rate_max` 0.25, `city_debt_floor_mult` 0, `bounty_reserve_mult` 2 | the switch; `tax_debt_max` 0 flattens prices at once; a forward slice restoring the refound and the board hunks |
| **0124** | `a_city_in_debt_is_helped` | step 5 AID in `tick_city`; `donate_for` + `cmd.donate` + `cmd.preview_donate` + registry; `npc_tend` NPC-aid rule; `NPC_DONATED` kept by `npc_compact` | §4.5 | `aid_donor_mult` 2, `aid_rate` 0.10, `donate_min_ducats` 100, `npc_invest_above` 2.0, `npc_invest_keep` 1.5 | `aid_rate` 0 stops aid; the switch stops the rest; a forward slice removes the `npc_tend` rule |
| **0125** | `a_city_builds_with_other_peoples_money` | tables `city_works`, `city_shares`; `city_level`, `invest_for`, `cmd.invest`, `cmd.preview_invest` + registry; steps 7, 8, 9 of `tick_city`; the four reader slices (`sail_refusal`, `daily_cap_remaining`, `world.spread`, `tick_market_drift`); the dividend payout in the settle arrival hunk; `npc_tend` investment rule; `world.treasury` works/shares; `npc_fleet_card` line | §5.6 | `works_cost_base` 20,000, `works_cost_growth` 1.6, `works_level_max` 5, `shares_per_level` 100, `works_coupon_pct` 0.003, `invest_min_ducats` 1,000, `npc_invest_max_per_hour` 50, `docks_draft_per_levels` 2, `market_cap_per_level` 0.10, `production_per_level` 0.10, `inn_hands_per_level` 2, `inn_pool_per_tier` 40 | `works_level_max` 0 offers nothing; `works_coupon_pct` 0 stops coupons; readers at level 0 are byte-parity with their pre-images, so a forward slice restoring them is optional |
| **0126** | `a_city_in_default_goes_to_war` | table `city_wars`; `city_at_war` restated; step 6 of `tick_city`; the `tick_contracts` war hunk; `world.treasury` war block | §6.4 | `war_debt_days` 3, `war_days` 5, `war_cooldown_days` 10, `war_target_min_ducats` 50,000, `war_tax` 0.05, `war_base_p` 0.45, `war_works_p` 0.05, `war_indemnity_pct` 0.25, `war_max_declared_per_hour` 10 | `war_max_declared_per_hour` 0 declares nothing; `update city_wars set status = 'peace'` ends the open ones; the switch |

**Deploy order and the switch**: 0122 → one day dark (§9.1 readings; `npc_cost_mult` 1 is live
from here — if too many laps lose, 0.5 by knob) → 0123 + 0124 together → `select
public.city_treasury_switch(true)` (seeds, asserts §7.1, lights) → a day of §7.2 readings → 0125 →
0126. 0125 and 0126 could land before the switch; landing them after gives the owner a day of
plain debt/aid dynamics to read first. The 0120 check in the RESUME queue (zero-net laps, tick
durations) comes before 0122.

**Client PRs** (each after its migration is LIVE; `src/features/map/CityTabs.tsx`,
`CityHarbour.tsx` is the Port tab; `src/features/port/PortPrices.tsx` the Market tab,
`PortInn.tsx` the Inn tab; `src/lib/rpc/catalog.ts` the catalogue; `docs/WORDS.md` the words):
after 0122 the treasury line (read-only, `worldTreasury`); after 0123 the debt/default words and
the printed tax; after 0124 **Donate** (the step tray of `src/live/useOrderPreview.ts` with
`cmd.preview_donate`); after 0125 the works dots, **Invest**, the viewer's holding, the merchant
sheet line (`src/live/MerchantSheet.tsx`); after 0126 the war line. The LEDGER needs nothing but
words for `DUES`, `DONATION`, `SHARE`, `DIVIDEND`. After every game change: `npm run refresh` in
`tools/projectmap` (memory rule).

---

## 13. Remaining owner questions (three, none blocking 0122)

1. **The seed.** The switch seeds each harbour with ten game-days of what it pays sellers, never
   under 20,000, and refuses to light a world where the cities together would be broke (§7.1).
   Accept that rule, or name a figure per harbour?
2. **The floor.** By default a broke city keeps buying for ever at its capped price (your answer
   4). Should the quay refuse to buy once a city is three credit lines into default
   (`city_debt_floor_mult` 3), or stay open (0)?
3. **Who attacks.** Only the bankrupt harbour raids its rich neighbour (this plan). Should a rich
   harbour also be able to attack a defaulted neighbour to collect? (One more trigger in step 6,
   not needed for 0126.)

Answered 2026-10-15: Q1 limited money (the market is the purse) — built here; Q2 merchants pay 1.0
— 0122's knob; **Q3 goods a city lacks = only goods it does not sell — 0087's rule kept, nothing
new built (§3.4)**; Q4 debt, not decay — §3, §4, §6; Q5 everyone invests anywhere — §5.4.
