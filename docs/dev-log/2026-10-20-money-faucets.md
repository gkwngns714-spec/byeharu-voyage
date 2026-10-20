# 2026-10-20 — Where money enters and leaves the world (the faucets)

A code-reading investigation (no database access). Prod figures quoted are the owner's 30-minute read of
`public.treasury_flows` after migration 0213. Knob values are the defaults the chain writes; check
`world_config` on prod before acting on one.

## In plain English

- **Almost every money move is a hand-over.** A city pays a seller, a buyer pays a city, a city pays its
  capital, and so on. The total stays the same. That covers SELL, BUY, TAX, WAGES, INSURANCE, WORKS,
  CROWN_TAX, CROWN_AID and DIVIDEND.
- **Only two things create money all the time:**
  1. **EARNINGS**: every city below its "standing purse" (2 M for a city, 10 M for a capital) is
     given new money once a game-day. About 1.23 M in the 30 minutes, the biggest faucet by far.
  2. **IMPORT_DEMAND**: the extra price for goods from far away, paid by "the city's people", so it is
     new money. About 0.24 M in the 30 minutes, already cut by 0212.
- **CROWN_AID creates no money.** It moves money from a capital to a poorer city of the same country.
  The 4.36 M looks big for two reasons. First, the table counts both sides of each move: 44 rows are
  22 pairs, so about 2.18 M actually moved. Second, after 0207 ("ten times deeper" markets) a city's
  safety reserve, three days of what it pays out for cargo, grew about ten times, so many cities fall
  under it every hour and their capital tops them up. What the capitals hand out is the 10 M each
  they were given once by 0172 (the GRANT, printed money). That stock is now draining out to traders
  through the cities.
- **Nothing in the game destroys money in any real amount.** There is no sink. Money only piles up.
  The few places where money vanishes are rounding-sized edge cases (listed below).
- **The cleanest single lever:** lower `city_earnings_per_dev` (now 100). It shrinks the biggest
  faucet in proportion, at once, with no code change.

## How the money moves (the four writers)

| Writer | Live definition | What it does |
|---|---|---|
| `public.credit(player, kind, delta)` | `20260818000004_…honest_ledger.sql:216` | THE only writer of `players.ducats` (merchants are players with `is_npc`, so NPC purses too). One-sided: it moves the house alone. |
| `public.treasury_post(port, kind, delta)` | `20260818000122_a_city_keeps_a_purse.sql:307` (lock line re-cut by 0123:461) | THE only writer of a city's money (`treasury_flows`; rolled hourly into `port_treasury.ducats`, conserved). One-sided: it moves the city alone. Writes nothing while the purses are dark. |
| `public.pay_city(player, port, kind, amt)` | `0122:344` (re-cut by 0144:367 for influence) | House → city: `credit(-amt)` and `treasury_post(+amt)`. **TRANSFER.** With a null port, only the house is charged (money destroyed; see below). |
| `public.city_pays(port, player, kind, amt)` | `0122:363` | City → house: `treasury_post(-amt)` and `credit(+amt)`. **TRANSFER.** |

So a flow is a TRANSFER when it goes through `pay_city` / `city_pays`, or posts a `+` and a `−` together.
It **mints** when it calls `treasury_post(+)` or `credit(+)` alone, and **destroys** when it calls
`treasury_post(−)` or `credit(−)` alone.

## Every treasury_flows kind

The prod totals look like sums of |ducats|. CROWN_TAX, CROWN_AID and WORKS are pairs: WORKS_IN equals
WORKS_OUT to the ducat, and the CROWN rows come in even counts. The signed sum of each pair kind is 0.

| Kind | 30-min prod total | Writer (file:line of the live text) | Class | Formula | Knobs | Notes |
|---|---|---|---|---|---|---|
| **CROWN_AID** | 4,362,460 (44 rows = 22 pairs, ≈2.18 M moved) | `public.city_day` `0172:200`; posts at `0172:279-280`; called by `tick_city` step 6b (`0172:310`), hourly at :37 (`0122:924`) | **TRANSFER** capital → city of the same great power | for each harbour with `balance < reserve`: `least(reserve − balance, city_surplus(capital))`; `reserve = treasury_reserve_days × city_sell_outflow` (`0122:269`, net of IMPORT_DEMAND by 0174) | `treasury_reserve_days` (3); no knob of its own | Not from 0187/0195: 0187 only made the capitals the ten great powers' (`city_capital` → `port_nation`), and 0195 is the raid rollback. Size = Σ (reserve − balance) of the cities under reserve, capped by what the 10 capitals hold above their own reserve. Big because 0207/0208 made the cargo flows (so the reserves) ~10× bigger. Its source is the 0172 GRANT stock (10 M per capital), refilled only slowly by the capitals' EARNINGS. |
| SELL | 3,874,534 | `cmd.do_sell` → `city_pays(…'SELL', q.total)` (`0174:189`, the 0122:528 call as re-cut by 0174 and later slices) | TRANSFER city → seller | the sale's quote | market knobs | The purse pays the base, the people pay the rest (IMPORT_DEMAND, just before). |
| BUY | 3,700,218 | `cmd.do_buy` → `pay_city(…'BUY', q.total)` (`0122:556`) | TRANSFER buyer → city | the quote | market knobs | |
| **EARNINGS** | 1,231,899 (118 rows) | `public.city_day` `0172:262`; amount from `public.city_earnings` `0172:183` | **MINTED** (into the city's purse) | per city, per run: `least(city_earnings × n_days, greatest(0, standing − balance))`; `city_earnings = city_earnings_per_dev × (dev_industry + dev_commerce + dev_military) × (1 + city_earnings_per_level × Σ works levels)`; `standing = city_purse_capital` or `city_purse_city` (`0172:155`) | `city_earnings_per_dev` (100), `city_earnings_per_level` (0.10), `city_purse_city` (2,000,000), `city_purse_capital` (10,000,000), `treasury_days_kept` (30, the back-pay cap) | The "only up to the standing purse" brake caps a city's balance, not the flow: any city that keeps paying out (to sellers, coupons, aid, works) is refilled every game-day, for ever. 118 rows ≈ 10.4 k each ≈ 1.25 game-days (an hour is 60 / 48 game-days) × ~8.4 k a game-day. If that is one hourly run, it is ~1.2 M an hour, ~30 M a real day. 0172's own replay forecast 3.3–6.8 M a real day: 5–9× lower. Likely causes: more cities below standing since 0207, and more works levels (up to ×3). Check for back-pay: a failed `day` step leaves `earned_day` behind, and the next run pays up to 30 game-days at once. |
| **DIVIDEND** | 630,264 (202 rows) | city side: `tick_city` step 6 `0123:620` (coupon formula `0123:600` as re-cut by `0148:180`); house side: `public.collect_coupons` `0123:278`, `credit(…'DIVIDEND')` at `0123:307`, on arrival | TRANSFER city → escrow (`city_shares.accrued`) → house | per share row: `paid × works_coupon_pct × game-days × influence_coupon_mult`; the city pays `least(Σ due, city_surplus)`, pro rata; the shortfall is not owed | `works_coupon_pct` (0.003 a game-day ≈ 9 % a real day), `influence_owner_coupon_mult` (1.5) | One row per harbour per run, so 202 rows = one run. Implies ~170 M of shares outstanding (630 k ÷ 0.00375). A transfer, but in practice it is the main pipe that takes the minted EARNINGS (and the GRANT stock) out of cities into merchants' purses. |
| **IMPORT_DEMAND** | 242,929 | `cmd.do_sell` `0174:186` (hunk 5) | **MINTED** (into the city, passed straight on to the seller with the SELL) | `q.total − round(q.total / cargo_haul(port, good))`; `haul = 1 + haul_premium_share × (haul_max ^ (min(1, nm/haul_reach_nm) ^ haul_curve) − 1)` (0173), stored in `port_goods.haul` | `haul_max` (3 since 0212, was 600), `haul_premium_share` (0.5), `haul_reach_nm` (14,500), `haul_curve` (2.0) | Known. The far end is now 2× (was 300.5×). A knob change only takes effect after a migration refills `port_goods.haul` (as 0208 and 0212 did). |
| CROWN_TAX | 236,500 (390 rows = 195 pairs, ≈118 k moved) | `public.city_day` `0172:252-253` | TRANSFER city → its capital | `least(round(Σ TAX on the counted days × crown_tax_share), balance)` | `crown_tax_share` (0.10) | It reads the daybook TAX of past game-days, so it can exceed this window's TAX. |
| WORKS_IN / WORKS_OUT | 203,868 each | `tick_city` step 4 `0123:537` (OUT), `0123:544` (IN); the gate re-cut by `0172` hunks 2–3 | TRANSFER city → the other harbours of its region, by size_tier | `k shares × works_share_price(level) × works_region_share` | `works_region_share` (1.0), `works_cost_base` (20,000), `works_cost_growth` (1.6), `shares_per_level` (100), `works_level_max` (5) | The tick asserts `WORKS_OUT = Σ WORKS_IN`. A city builds only from what it holds above `greatest(reserve, standing)`. |
| TAX | 62,302 | `cmd.do_sell` → `pay_city(…'TAX', v_tax)` (`0122:542`, kept by `0128:246`) | TRANSFER seller → city | `profit × world.tax_rate(port, house)` (tariff by stance, 0196) | `tariff_stance_mult`, `tariff_rate_max`, city tax rates | |
| INSURANCE | 37,456 (302 rows) | `public.insure_voyage` → `pay_city(…'INSURANCE', v_price)` (`0213:336`) | TRANSFER shipowner → port of departure | `insurance_price(cargo at cost, risk)` | 0213's insurance knobs | Payouts (`INSURANCE_PAID`, `0213:385`) go via `city_pays` from the insuring city's surplus: also a transfer; any `short` is unpaid, not money. |
| WAGES | 15,749 | `public.pay_wages` → `pay_city(…'WAGES', v_pay)` (`0128:188`), out of a sale's profit | TRANSFER shipowner → city of the sale | `wages_from_profit(owed, least(profit, visit net − paid))` | `wages_owed_cap_days` (30), `running_cost_mult` | Wages above the cap are forgiven: a debt is cancelled, no money is destroyed. |

Kinds not in the 30-minute read, for completeness: PROVISION, REPAIR, HIRE, TOW, BUILD, TUITION,
OFFICER_WAGE, SHARE (`0123:257`), DONATION (`0144:261`) and MERCHANT_SURPLUS (`0180:235`) are all
`pay_city`: house → city TRANSFERS. BOUNTY (`0122:792`) is city → a contract's escrow; BOUNTY_LAPSED
(`0122:761`) is escrow → city; PREMIUM (`0087:449`, a `credit`) is escrow → house. All three are
TRANSFERS through `trade_contracts.escrow`. NPC_REFOUND was `city_pays` (a transfer) and 0213 retired it.

## Balances credited with no matching debit (all the mints)

| Where | Writer | Class | Size |
|---|---|---|---|
| City purse: **EARNINGS** | `0172:262` | MINTED, continuous | the biggest: ~1.2 M per hourly run |
| City purse → seller: **IMPORT_DEMAND** | `0174:186` | MINTED, continuous | ~0.24 M / 30 min after 0212 (it was ~500–600 M a real day before) |
| City purse: **GRANT** | `0172:375` (one-off, at deploy) | MINTED, one-off | every harbour topped up to 2 M / 10 M (≈ 700 M by 0172's replay). This is the stock CROWN_AID and DIVIDEND are now draining. |
| City purse: **SEED** | `city_treasury_switch` `0122:966` (one-off, when the switch was turned on) | MINTED, one-off | 20 k floor per harbour at the first switch |
| House purse: **FOUNDING** | `public.new_house` `0096:502` (`starting_ducats` 8,000); merchants via `npc_found` `0097:296` (capital + officers' wages + tuition) | MINTED, per new company | small, one-off per company |
| House purse: FOUNDING for hull skills | `0167:243` (`credit(FOUNDING, v_cost)`, then `raise_skill` pays TUITION to a city) | MINTED (it ends up in a city) | one-off per merchant fix |
| House purse: PREMIUM on a contract posted while the purses were dark (escrow 0) | `0087:449` | MINTED, legacy only | negligible now |
| Crown / great-power treasuries | none of their own: a "crown" is the capital's `port_treasury` | — | the great powers (0187) hold no purse |
| NPC house purses | `credit` only; every live merchant flow goes through `pay_city` / `city_pays` | — | no extra mint since 0213 retired NPC_REFOUND |
| Escrow (`city_shares.accrued`, `trade_contracts.escrow`) | filled by DIVIDEND / BOUNTY, emptied by `collect_coupons` / PREMIUM / BOUNTY_LAPSED | TRANSFER | — |

## Does anything destroy money?

**Essentially no.** No flow is designed as a sink. The only places money vanishes:

- `pay_city` with a **null port** (`0122:344`: "a null port moves the house alone"): a charge made
  where there is no harbour, for example a gear repair with the fleet at sea (`0158:835` passes the
  fleet's `port_id`). The house is charged and no city is paid. Rare and small.
- A deleted company (the `on delete cascade` on `city_shares`) takes its uncollected coupons with it.
- Rounding in pro-rata splits (single ducats).

Things that look like sinks but are not money: forgiven wages above the cap (a debt cancelled),
coupons a city could not pay (never owed), unpaid insurance `short`, and cargo taken in a raid (goods,
not ducats).

So the world's money grows by EARNINGS + IMPORT_DEMAND (+ new companies) and nothing takes it back out.
It all ends up somewhere, mostly in merchants' purses, which 0180's purse ceiling pushes back into
cities as SHARE and MERCHANT_SURPLUS (transfers, which then pay coupons back out).

## The three biggest faucets, ranked

### 1. EARNINGS: city development income, minted (~1.23 M / 30 min)

- **Lever:** `city_earnings_per_dev` (100). Earnings scale with it exactly: 50 halves the faucet, 0
  stops it (0172's own rollback lever). It takes effect at the next `tick_city` run, with no migration.
- Second choice, if the target is the growth that works levels add: `city_earnings_per_level` (0.10).
  Lowering `city_purse_city` / `city_purse_capital` would also cut it, but those two also gate the
  cities' own building (step 4) and the grant meaning, so they are not clean.
- **Measure** (read-only, before and for 30 minutes after):
  - Σ EARNINGS per run, and its rows (expect a proportional drop);
  - the world money stock per hour (Σ `players.ducats` + Σ `treasury_balance` + Σ `city_shares.accrued`
    + open contract escrow), whose growth should slow by the same amount;
  - the number of harbours under their reserve, and under their standing purse, which will rise;
  - `city_bid_factor` (a city under its reserve bids down toward 0.5) and E_CITY_BROKE refusals on SELL;
  - `coupons_skipped` in the `tick_city` receipt (less surplus means fewer coupons paid);
  - merchants' net profit per lap.
  - Also check first whether any EARNINGS row is back-pay: a ducats / `city_earnings` ratio above 2
    means `earned_day` had lagged.

### 2. IMPORT_DEMAND: the distance premium, minted (~0.24 M / 30 min)

- **Lever:** `haul_max` (now 3) or `haul_premium_share` (0.5). At 0 or 1 the premium is gone, and
  with it distance pricing. Unlike EARNINGS, this needs a migration to refill `port_goods.haul` from
  `world.haul_rows()`, as 0212 did. Changing the knob alone does nothing to the stored prices.
- 0212 has just cut it ~2,000-fold. Measure a full day before moving it again.
- **Measure:** Σ IMPORT_DEMAND and its share of Σ SELL; far-route profit per day against short
  routes (the 1.3–1.5× target of 2026-10-19); far-quay prices; merchants' loop mix by distance.

### 3. CROWN_AID: not a mint, but the largest money movement (≈2.18 M moved / 30 min)

It hands the capitals' one-off 10 M GRANT stock to cities under their reserve. Those cities then pay
it out to sellers (SELL) and to shareholders (DIVIDEND). It stops by itself when the ten capitals'
surplus is spent, at which point cities under reserve start bidding lower (`city_bid_factor`).

- **Lever:** `treasury_reserve_days` (3). The aid fills cities up to `reserve = days × mean SELL day`,
  so 1.5 halves the target. It also lowers every city's reserve everywhere else it is read: a higher
  bid factor, a bigger surplus for coupons, refounds and works. So expect more DIVIDEND and WORKS
  while CROWN_AID shrinks. CROWN_AID has no knob of its own. If the owner wants only the aid smaller,
  a one-line migration with an aid cap (for example `crown_aid_share` of the gap) would be the clean
  fix.
- If the concern is money reaching merchants rather than the aid itself, the cleaner lever is
  **`works_coupon_pct`** (0.003 a game-day ≈ 9 % a real day). DIVIDEND (630 k / 30 min) is the pipe
  that turns city money, minted or granted, into house money.
- **Measure:** CROWN_AID per run (pairs and amount); the ten capitals' `city_surplus` over time (how
  long the stock lasts); harbours under reserve; DIVIDEND paid and skipped; city bid factors and
  E_CITY_BROKE; the world money stock (unchanged by this lever directly).

## Caveats

- Read from the chain at main (head 0213), not from prod. The knob values are the defaults the chain
  writes; a hand-set `world_config` value on prod would change the numbers, not the classification.
- "Live definition" is the file where the call's text was written. Several bodies are sliced later
  (`cmd.do_sell` by 0194/0207/0211, `tick_city` by 0148/0150/0172), but those slices leave these
  money calls as they are.
- I could not test the per-row reading of the totals (whether they are |ducats|), the back-pay
  question, or the "one run per window" assumption without the database. The ratios above say how to
  check each one, read-only.
