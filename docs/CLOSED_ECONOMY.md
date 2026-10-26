# CLOSED_ECONOMY — restock by investment, prices like stocks, no new gold, capital-city gifts

**Status: DESIGN, build-ready (2026-10-26). Nothing here is built. No migration, no code.** Owner row 212.
Prod head at writing: **0226**. Slices are numbered "next" (after whatever is in flight at build time).

**The owner (2026-10-26):** *"i want city to restock trade goods based on their invested amount. i want
prices to be moved like stocks, and i want the gold to be stopped here, meaning no more excess gold
produced - so that the economy circulates like real world."* On the restatement: *"yes, but broke merchants
will receive donation (starting money) from their capital city (show this too). lets try this model and
see the stats after few days."*

Standing owner rules this design keeps: **no forced hand-in of merchant surplus** (0184: *"no need to hand in
surplus... wtf"*), **no harbour dues** (ECONOMY_LOOP §11), **a city never goes below zero** (0122).

Every "decided by default" below is mine; the owner reverses afterwards.

---

## 0. The answer in eight lines

1. **One flag, `economy_closed`** (false). One reader `public.economy_closed()`. Lit once by
   `select public.economy_close_switch(true)`. Off = today's game, byte for byte.
2. **No new gold.** Lit, the four live faucets stop: EARNINGS, IMPORT_DEMAND, SEED, unpaid FOUNDING.
   One guard at the two money writers (`treasury_post`, `credit`) refuses any "minted" kind.
3. **Costs already go to cities** (measured: 0 removed in 24 h). Nothing to re-route; stated per kind (§2).
4. **Restock by investment.** A city's restock rate = f(money invested there), one reader
   `public.restock_rate(port)`. No investment = slow (never zero).
5. **Prices like stocks.** Every trade moves the price both ways inside its own walk (buy up, sell down,
   ∝ size / depth); a fast "pressure" fades in ~48 min, the stock gap refills at the city's restock rate.
6. **Broke merchants get a gift = their starting money, from their country's capital.** Capital short →
   it calls the gap from its realm's richest harbour. Shown in Stats, the Town Hall and her sheet.
7. **New players' starting money** is paid by their country's capital too. No reserve needed.
8. **Watch 3 days.** New money must read 0, world total flat; switch back on the §7 triggers.

---

## 1. Measured on prod (read-only, 2026-10-26 ~01:30 UTC, head 0226)

| Figure | Value | Source |
|---|---|---|
| World total (players + merchants + cities + set aside) | **1,968,004,265** | `stats_world` 01:21 |
| … 24 h earlier / at 10-20 23:51 | 1,897,777,160 (**+70.2 M/24 h**) / 1,710,276,398 (+257.7 M in 5 d) | `stats_world` |
| Held by cities / merchants / players / set aside | 1,126.3 M (246) / 827.8 M (821) / 0.23 M (19) / 13.7 M | `stats_world` |
| Minted 24 h | **EARNINGS 28.23 M · IMPORT_DEMAND 25.43 M · SEED 16.00 M** (8 new harbours, 0217) · FOUNDING 8,000 · NPC_REFOUND 0 · GRANT 0 | `stats_world.period` |
| Removed 24 h | **0** | `stats_world.removed` |
| SELL paid 24 h | 424.0 M: purse **398.6 M (94 %)**, minted premium **25.4 M (6 %)** | SELL vs IMPORT_DEMAND |
| BUY taken in 24 h | 363.1 M | `period` |
| City purses | p10 21.9 k · p50 528 k · p90 15.6 M · max 49.3 M (Genoa); **105/246 under reserve**; 14 under 10 k; 0 at zero; 39 over 10 M | `port_treasury` |
| Great-power capitals | Karachi **1,790** · Sakai **2,569** · Marseille 29.6 k · Busan 94 k · Guangzhou 175 k · Lisbon 204 k · London 293 k · Istanbul 304 k · Amsterdam 437 k · Seville 454 k | `port_treasury` |
| Their realms' surplus (above reserve) | 55.6 M (FRA) … 165.2 M (MUG); every realm ≥ 55 M | `port_nation` × `port_treasury` |
| Merchants | 821 in the 10 powers; capital p50 **5,000** (5 k–729 k), Σ 26.1 M; Σ purse **830 M (32× capital)**; 550 above 2× capital | `npc_houses` |
| Broke merchants (purse < 20 % capital) | **38**, Σ capital **480 k**, max 145 k | `npc_houses` |
| Refounds | 0 in 7 d — retired by 0213 | `ledger` |
| Restock | `stock_regen_fraction` 0.15 / game-day (48 min) → half-life ≈ 3.4 h; **`production_rate` = 0 on all 138,990 rows, so the production works level (1,115 levels) changes nothing**; 99.1 % of rows at target | `port_goods` |
| Investment | Σ `city_shares.paid` 127.7 M over 232 ports (p50 504 k, max 1.25 M); SHARE + DONATION inflow 21.5–31 M/day; last day per port p50 20 k, **114/246 got nothing** | `city_shares`, daybook |
| Trades 24 h | 59,867 trades, 7.14 M units → **mean 119 units**; depth p50 1,330 (p10 600, p90 3,080) | `stats_world` |
| Price move | buy of 119 u at depth 1,330 ≈ +4.8 % (elasticity 0.5); a sale also adds glut 0.30 × 119/1330 ≈ 2.7 %; spread 0.06 base, 0.02 floor | knobs |
| Chart motion (10-min steps, 24 h) | **median 0 (54 % flat)**, p90 2.6 %, p99 7.9 %. Flat because the drift slot is 15 min and the snapshot 10 min | `price_history` |
| Game day | 2,880 s (30 game-days = 1 real day) | `world_config` |

Organic city flow, minted removed: cities +37.8 M/24 h − 44.2 M minted into them = **−6.4 M/day**; closed,
they also pay the 25.4 M premium → **≈ −32 M/day at today's trade** (an estimate; the bid factor lowers it as
purses thin). Average runway 1,126 M / 32 M ≈ 35 days; thin cities feel it first.

---

## 2. Money: every faucet → closed, every sink → which purse

### 2.1 Faucets

| Kind | 24 h | Today | Lit (closed) |
|---|---|---|---|
| `EARNINGS` | 28.23 M | `city_day`: dev income up to the standing purse | **stops** (gate in `city_day`) |
| `IMPORT_DEMAND` | 25.43 M | `cmd.do_sell`: townsfolk pay the distance premium | **stops**: the purse pays the whole SELL; the empty-purse rule judges the whole total |
| `SEED` | 16.00 M | switch / new-harbour migrations | **never again**: a new harbour starts at 0 and is funded by `CROWN_AID` from its capital (moved) |
| `GRANT` | 0 | one-off 0172 | never again (guard) |
| `FOUNDING` (player 8,000 · merchant capital · `npc_fix_hull_skills` tuition) | 8,000 | `credit` from nothing | **paid by the country's capital** (`city_pays`, realm call if short — §5) |
| `NPC_REFOUND` | 0 | retired 0213 | replaced by `CAPITAL_GIFT` (§5) |
| `PREMIUM` | — | escrowed at posting (`BOUNTY`) | unchanged (moved) |
| `CROWN_AID` / `CROWN_TAX` | net 0 | city → city, **mislabelled** minted / removed in `stats_flow_words` | relabel `moved` (E1) |

### 2.2 Sinks — all already land in a purse (removed = 0)

| Kind | Receiving purse |
|---|---|
| BUY | the city of the trade |
| TAX (on profit) | the city of the sale; 10 % on to its capital (CROWN_TAX) |
| WAGES | the harbour the voyage reaches |
| PROVISION · REPAIR · HIRE · TUITION · OFFICER_WAGE · BUILD | the city where it happens |
| INSURANCE | the underwriting city (departure) |
| TOW | the shipyard city |
| SHARE · DONATION | the city given to |
| DIVIDEND | city → set aside → the holder at arrival |

Known leak (0122 §1.2a): wages of a voyage that never arrives. It shows as the residual in §7.

### 2.3 The invariant

**Σ players + Σ merchants + Σ cities (rolled + unrolled flows) + set aside = constant** while lit.
No reserve is needed: new players and broke merchants are paid by capitals, which are cities.
*Decided by default: no world reserve.*

---

## 3. Restock by investment

**Invested** `I(port)` = a decayed sum of money put into the city (SHARE + DONATION), not the frozen share
register — shares are near sold out (4,457 of 4,920 levels built), donations are where merchants' money goes now.

- Stored: `port_treasury.invested bigint` — one writer, `tick_city`'s roll, hourly:
  `I ← round(I × 0.5^(1/72)) + Σ(SHARE + DONATION posted at the port this hour)` (half-life 3 real days).
- Seeded once at the switch: `I = Σ city_shares.paid` at that port (127.7 M total). Equilibrium at today's
  inflow ≈ 25 M/day × 4.3 days ≈ 108 M — so day one ≈ steady state. *Decided by default.*
- **Rate** (per game-day), one reader `public.restock_rate(port)`:

  `rate = r0 + (r1 − r0) × I / (I + I½)`, `r0 = 0.03`, `r1 = 0.30`, `I½ = 500,000`

| Invested | Rate | Half-life (real) |
|---|---|---|
| 0 | 0.03 | 18 h |
| 100 k | 0.075 | 7 h |
| 504 k (median today) | 0.165 | 3.1 h (today 3.4 h) |
| 1.25 M (max today) | 0.223 | 2.2 h |
| cap | 0.30 | 1.5 h |

- **Zero investment:** 0.03 — goods still come back, slowly. Never zero. *Decided by default.*
- **OWNER 2026-10-26 (overrides the default above): the MAX STOCK moves with investment too, and both settings are set ONCE PER DAY.**
  *"the max trade good stock, should increase and decrease depending on the investment of that city too, and the settings set by should be once per day."*
  - **Once a day** (the daily job, 00:00 UTC), per harbour: read `I`, write `port_treasury.restock_rate` and `port_treasury.depth_mult`. Every reader uses the stored day's values; nothing recomputes them between days.
  - **Max stock:** `stock_target = base_target × depth_mult`, `depth_mult = 0.5 + 1.0 × I / (I + I½)` → I = 0: 0.5× · median 504 k: ≈ 1.0× (today) · cap: 1.5×.
  - **No jump:** a day's change is capped at ±10 % of depth (`depth_step_max`), and stock is NOT rescaled — it walks to the new max by the day's restock rate (goods are never created or destroyed by the re-set). The price moves only as the stock/max ratio moves.
  - Dark: `depth_mult` = 1, `restock_rate` = `stock_regen_fraction` (byte parity). Folded into slice E5.
- Readers re-cut: `tick_market_drift` (regen) and `public.price_path` (the outlook) read `restock_rate`
  instead of `stock_regen_fraction`. Dark, `restock_rate` returns `stock_regen_fraction` (byte parity).
- The production works level's term (`works_factor(…,'production',…)` × `production_rate` = 0) stays as is:
  it multiplies 0 today. Investment in production now counts through `I` like any other share.
- Row 173 (weekly reset of investment records) must not reset `invested` — it is a decayed figure already.

---

## 4. Prices like stocks

**One authority stays:** `world.mid_from_terms` is the one price expression, `world.quote_priced` the one
walk, `tick_market_drift` the one mover over time, `cmd.do_buy` / `cmd.do_sell` the one writer of a trade.

```
mid = band(base × affinity × demand × (target/stock)^0.5 × (1+drift) × (1+season) × dev) × haul × (1 − press)
```

- **press** = today's `port_goods.glut`, made **signed** (CHECK `[0, 0.5]` → `[−0.30, 0.30]`).
  `> 0` price down (sold into), `< 0` price up (bought out). Same column, same term: no second price path.
- **Impact:** each 10-tun shelf of a walk moves press by `0.30 × units / stock_target` (buy −, sell +),
  **inside the walk**, like the stock term (0211 shelves). So buy N then sell N at once returns the spread
  only — 0211's "a round trip never pays" holds. (Today the glut is raised after the walk and only on sells:
  sell → buy back is a small arbitrage at low-spread quays. This closes it.)
- **Recovery:** press × 0.5 per game-day (48-min half-life, existing `glut_decay`); the stock gap refills at
  the city's `restock_rate` (§3). Fast fade + investment-paced refill = a ticker that snaps then drifts back.
- **Example** (median quay, 119 units bought): stock term +4.8 %, press +2.7 % → ≈ **+7.6 %** after the trade;
  the buyer pays ≈ half of it on average.
- **Noise:** drift slot 900 s → **600 s** (= the drift job and the 10-min snapshot, so no flat steps);
  θ 0.90 → 0.932, σ 0.020 → 0.0166 (same hourly variance).
- **History (0226):** unchanged — it records what the price does.
- **Dark:** press is never pushed negative and the walk does not step it → byte parity.

---

## 4b. City wants — every city needs 1–3 goods and pays far more for them (OWNER 2026-10-26)

*"i want you to create for each city, the trade good that city needs, and the city will pay much more money. this should be for every city, 1~3 trade goods. First make it random? or any other method needed so that the economy circulates even further on a closed gold."*

| | Decided by default |
|---|---|
| How many | 1–3 per harbour: 1 base, +1 if `I` ≥ median, +1 if `I` ≥ top quartile (richer cities want more) |
| Which goods | **Weighted random, not pure random.** Candidates = goods this city does NOT sell (`port_offered_goods`) that ARE sold somewhere ≥ 1,500 nm away. Weight = distance to the nearest seller (far goods weigh more) × 1.5 if the good is in the city's real regional wants (`docs/REGIONAL_GOODS.md`). Seeded per (port, day) so every reader agrees. Pure random would often pick a good sold next door — no voyage, no circulation |
| When | **Re-drawn once a day** with the other daily settings (00:00 UTC). A good wanted yesterday can't be drawn today (routes must move) |
| Pays | **×2 the normal sell price** (`want_mult`), paid from the CITY PURSE — never minted. The empty-purse rule still holds: a city that can't pay shrinks the premium first, then refuses |
| Size | Max units at the premium per day = 10 % of the city's max stock of that good; past it the normal price |
| Shows | City view and Trade sell list: "Wanted ×2" / "수요 ×2" beside the good; Stats → Cities: a city's wants; the daily draw is logged (`city_wants` table, append-only) |
| Merchants | NPC merchants see wants like players do (their route planner already reads the board's prices) |

**Why it helps a closed economy:** money flows FROM rich, invested cities TO the traders who bring what they lack; traders then spend and invest elsewhere — gold moves across the map instead of pooling. The ×2 is the knob to watch in §7 (if rich cities drain too fast, lower it).

Slice **E6b** `a_city_wants_what_it_lacks` (before E7): `city_wants` table + the daily draw in the daily job + `want_mult` read by `world.quote_priced`'s sell side and the board; dark = no wants drawn, price byte-identical; lit in-block: a probe port draws 1–3 wants, none sold locally, a probe sale pays ×2 from the purse.

---

## 5. City purse limits, broke merchants, capital gifts

### 5.1 Empty-purse rule — confirmed holds everywhere

- `treasury_post` refuses any outflow its live balance cannot cover (`E_CITY_BROKE`), `port_treasury.ducats ≥ 0`
  by CHECK. Every city payer goes through it: SELL, INSURANCE_PAID (pays what it can — 16 short payouts in 24 h),
  DIVIDEND / BOUNTY / CROWN_AID / own works (from surplus only).
- `cmd.do_sell` shrinks a sale to what the purse covers. Today it judges the **base** (total / haul); lit it
  judges the **whole total** (E3). Bid factor (0.5 at empty → 1 at reserve) unchanged.

### 5.2 The capital's gift (`CAPITAL_GIFT`)

| Rule | Decided by default |
|---|---|
| Who | a merchant company (`npc_houses`) — players are not gifted |
| Trigger | hourly, in `npc_tend_houses` (where the 0213 refound stood): `npc_worth` (purse + cargo at cost, 0203) **< 20 % of capital** |
| Amount | **her capital = her starting money** (p50 5,000) |
| Cooldown | one per 24 h, at most 3 per 7 days (`gift_max_per_week` 3) |
| Payer | her country's capital (`nations.capital_port_code` of `players.nation_id`) |
| Capital short | the capital first **calls** the gap from the harbour of its realm (`port_nation`) with the largest surplus — `CROWN_CALL` (−/+) — then pays. Every realm has ≥ 55 M surplus today |
| Realm short too | no gift this hour; one `GIFT_WAITING` event a day; retried hourly; she sails on with what she has |
| Hourly cap | 50 companies, longest-broke first (`gift_max_per_hour`) |
| Expected volume | 38 broke now, Σ capital 480 k — under 0.5 M/day |

### 5.3 How it shows

| Where | What | EN | KO |
|---|---|---|---|
| Her purse | ledger `CAPITAL_GIFT` (+) | Capital gift | 수도 지원 |
| Capital's book | flow `CAPITAL_GIFT` (−); `CROWN_CALL` (−/+) | Gifts · Crown call | 지원금 · 왕실 징수 |
| Gift list | table `capital_gifts(id, port_id, player_id, ducats, called_from, created_at)`, index `(port_id, created_at)`, append-only | — | — |
| Event | `CAPITAL_GIFT` to the merchant: `{port, port_name, ducats, worth}` | — | — |
| Town Hall (city view) | "Gifts" list, last 10: **"Gave Casa X 5,000 · 2 h ago"** | Gave {name} {n} | {name}에 {n} 지원 |
| Merchant sheet | **"From Lisbon 5,000"** | From {city} {n} | {city} 지원 {n} |
| Stats → Merchants | Broke · Gifts 24 h (count, Σ) | Broke · Gifts | 파산 · 지원 |
| Stats → Overview | New money · World total | New money · World total | 신규 화폐 · 세계 총액 |
| Starting money | ledger `FOUNDING`, paid by the capital | Starting money | 창업 자금 |

### 5.4 Starting money (new player / new company)

`new_house`, `npc_found`, `npc_fix_hull_skills`: lit, `credit(…'FOUNDING'…)` → `city_pays(capital, …, 'FOUNDING', …)`
with the same realm call. If the realm cannot pay, the world's richest harbour pays (never block a sign-up).
5 new players in 14 days (40,000).

---

## 6. The switch

- `economy_closed` false; every slice ships dark, each asserts byte parity dark.
- `public.economy_close_switch(p_on boolean)` (E7): lit = seeds `invested`, sets drift knobs (600 s, 0.932,
  0.0166), records `economy_closed_at` + the world total at that second, flips the flag. Off = flag false,
  drift knobs back (900 s, 0.90, 0.020). Money already moved stays.
- Lit after E7 deploys, by one `select`, with the deploy note. Not inside the migration.

---

## 7. Watch (3 days) and switch-back triggers

| Stats figure | Healthy | Today | Switch back (or fix) if |
|---|---|---|---|
| New money / slot | **0** | 0.5–1 M / 15 min | any non-zero → a writer slipped the guard: fix forward |
| World total Δ / 24 h | 0 ± leak | +70.2 M | \|Δ\| > 0.1 % / day |
| Σ cities | slow fall, then flat | 1,126 M | falls > 5 % / day two days running |
| Harbours under reserve | < 150 | 105 | > 150 of 246 |
| Harbours under 10 k | < 40 | 14 | > 40 |
| Broke merchants | < 100 | 38 | > 120 |
| Capital gifts / day | < 2 M | — | > 5 M |
| E_CITY_BROKE share of sells | < 5 % | — | > 10 % |
| Price swing, 10-min, p90 | 3–12 % | 2.6 % (median 0) | > 15 %, or median still 0 |
| Merchant Σ purse | flat or slow rise | 830 M | rising > 30 M / day (cities paying for it) |

E2 adds these to Stats before anything is lit. Switch back = `economy_close_switch(false)`.

---

## 8. Slices — one migration each, "next" in number order, smallest first, all dark until E7

Common self-assert rules (every slice): count **only probe rows** (probe ids, `id >` a mark taken in-block);
never count/sum a growing table or compare a rollup with live; never DELETE from append-only tables
(`ledger`, `treasury_flows`, `events`, `capital_gifts`); no `set role`; probes inside sub-transactions
rolled back (asserted); every replaced body is the LIVE body (`pg_get_functiondef`, LF-normalised), each hunk
asserted to occur exactly once and to reverse to its pre-image, ACL unchanged; files saved LF.

| # | Name | Does | Self-asserts | Prod checks after deploy |
|---|---|---|---|---|
| **E1** | `the_books_say_what_moves` | `world_config.economy_closed` false + `public.economy_closed()`; `stats_flow_words`: CROWN_AID, CROWN_TAX → moved; add CAPITAL_GIFT, CROWN_CALL (moved); `capital_gifts` table (empty, append-only trigger, RLS read-all); `port_treasury.invested` (nullable) | reader false; 2 words moved, 2 added; table empty; trigger refuses UPDATE/DELETE on a probe row | flag false; `stats_flow_words` minted = EARNINGS, IMPORT_DEMAND, SEED, GRANT, FOUNDING, NPC_REFOUND |
| **E2** | `the_figures_watch_the_money` | `tick_stats` / `world.stats_now`: new money (slot, 24 h), world total + Δ24 h, harbours under reserve / under 10 k, broke merchants, gifts 24 h, price swing p50/p90 over the last hour of `price_history` (time-windowed). Client: Stats lines (EN/KO) | probe rollup over planted probe rows only; new keys present; old keys unchanged | Stats shows New money ≈ 70 M/day (truth before the switch) |
| **E3** | `no_city_is_paid_by_nobody` | lit only: `city_day` skips EARNINGS; `cmd.do_sell` skips IMPORT_DEMAND and judges the whole total for shrink/refuse; `city_sell_outflow` counts SELL whole | dark: probe sale byte-identical (flows, purse, payload); lit in-block: no IMPORT_DEMAND/EARNINGS row from the probe, purse pays whole, a short purse shrinks on the whole total | EARNINGS / IMPORT_DEMAND still flow (dark) |
| **E4** | `a_capital_gives` | lit only: gift pass in `npc_tend_houses`; `CROWN_CALL`; `capital_gifts` rows; events; FOUNDING via capital in `new_house`, `npc_found`, `npc_fix_hull_skills`; `world.town_hall` gains `gifts`; merchant card gains last gift. Client: Town Hall list, sheet line, words | lit in-block on a probe merchant: worth < 20 % → one gift = capital, purse +capital, capital −capital, one row, one event; second call within 24 h → none; capital short → CROWN_CALL from the richest probe-realm harbour; realm short → GIFT_WAITING, no money; dark → no gift | 0 gifts while dark; `capital_gifts` empty |
| **E5** | `a_city_restocks_by_what_is_invested` | `restock_rate(port)`; `tick_city` roll writes `invested` (decay + this hour's SHARE + DONATION, read from the hour's flows it already rolls); `tick_market_drift`, `price_path` read the rate | dark: rate = 0.15 for every harbour, regen of a probe row identical; lit in-block: I = 0 → 0.03, 500 k → 0.165, cap 0.30; decay step exact on a probe port | regen unchanged dark; `invested` null |
| **E6** | `a_trade_moves_the_price_both_ways` | glut CHECK → `[−0.30, 0.30]`; lit: `do_buy` pushes press negative, both sides step press per shelf in `quote_priced`; decay unchanged | dark: quotes byte-identical over a sample; lit in-block: buy N then sell N ≤ buy total (0211), press sign right, a 119-unit buy at depth 1,330 moves mid +7–8 % | no price moved (dark) |
| **E7** | `the_economy_is_closed` | `economy_close_switch`; the **guard**: lit, `treasury_post` refuses `p_delta > 0` of a minted kind, `credit` refuses a minted kind unless `byeharu.paid_by_city = on` (set_config local by `city_pays`) | lit in-block: bare `credit(FOUNDING)` refused, via `city_pays` ok; `treasury_post(EARNINGS,+)` refused; switch seeds `invested` = Σ shares.paid on probe ports; off restores knobs | not lit by the migration; after `select economy_close_switch(true)`: §7 figures each hour |

Client parts ship in the same PR as their slice (E2, E4) — never half a slice.

---

## 9. Risks

| Risk | Size | Handling |
|---|---|---|
| Cities drain | ≈ −32 M/day est.; 105 already under reserve | bid factor falls to 0.5, empty purse refuses; CROWN_AID moves capital surplus; §7 triggers; switch back |
| Merchants hoard | 830 M, +33 M/day | no forced hand-in (owner 0184); thinner bids cut margins; voluntary donations continue |
| Mass bankruptcy | 38 broke today, Σ capital 480 k | gift = capital, 24 h cooldown, 3/week, 50/hour; realm call; GIFT_WAITING |
| Poor capitals | Karachi 1,790, Sakai 2,569 | realm call (every realm ≥ 55 M surplus) |
| Live players' money | 19 players, 226 k total | never touched; only bids in thin cities fall |
| Deflation | fixed 1.97 B | prices do not read the money stock (0172); effect is distribution, watched |
| Restock slows | 114 cities with no inflow last day | seed from Σ shares (232 ports), r0 = 0.03 floor |
| Price runaway | press ±0.30, band 0.35–3.5 | caps; §7 swing trigger |
| Hidden mint | — | the E7 guard at the two writers; New money must read 0 |
