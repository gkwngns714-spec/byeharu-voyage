# 2026-10-18 — the circulation watch after 0172/0173, and 0174 (a city's people pay for what came from afar)

**The owner (2026-10-17 ~23:50 UTC):** *"Cities are powerful … and then make the economy circulate."* A city must
never go broke under normal trade. 0172 (00:32 UTC) topped every purse up to 2 M (capitals 10 M). 0173 (00:55)
priced a sale by the sea it crossed, up to 600×. The 0173 agent flagged the risk: merchants' planned loop profit
rose × 24 against ~660 M of city purses. This page watches prod and records what it found.

## 1. Method (prod, READ-ONLY)

- Every probe is `begin transaction read only; … rollback;` through `supabase db query --linked`.
- It calls only functions whose `pg_proc.provolatile` is `s`: `city_bid_factor`, `city_standing`,
  `treasury_balance`, `world.game_day`, `city_capital`, `city_surplus`. Each was checked before the first call.
  No volatile function was called. No EXPLAIN ANALYZE was run on anything volatile.
- **One reading** (scratch `watch.sql`) records:
  - per harbour: rolled purse, live purse (`port_treasury.ducats` + this hour's `treasury_flows`), reserve,
    `city_bid_factor`, standing purse, and the hour's flows by kind;
  - the merchants (`players` ⋈ `npc_houses`): purses, capital, how many are above 2× capital and by how much;
  - the players' purses;
  - the laps closed in the last hour;
  - `E_CITY_BROKE` refusals;
  - the arrivals sweep (`cron.job_run_details`, job 1 `byeharu-voyage:arrivals`, last hour).
- **Where refusals are logged.** A refusal is never written alone. A merchant's refused line goes into
  `standing_route_laps.skipped` (jsonb: port, line, verb, code, sentence) of the lap it belongs to, and is
  visible only once that lap closes. It carries no timestamp of its own, so refusals are bucketed by lap
  close (per half hour) and split by when the lap STARTED: after the grant (00:32:44), after the first lit
  roll (00:37), after 0173 (00:55). A player's refusal is the RPC's error and is not stored at all.
- `treasury_flows` holds only the flows not yet rolled. The `:37` roll (`tick_city`) moves them into
  `treasury_daybook` and the purse, so "the last hour's flows" is the flows table read just before `:37`.

## 2. Readings

"Other in − out" is every kind except BUY and SELL (from 01:58 it includes IMPORT_DEMAND). Row 00:58 counts
refusals in every lap that closed in the hour. From 01:12 it counts only refusals in laps that STARTED after the
grant, and from 01:58 also those in laps started after 0174. Long laps that straddle the grant escape this column;
§8 times every refusal by the stop instead. **0174 went live at 01:58:14** (the first IMPORT_DEMAND flow).

| UTC | last roll | city purses (live) | capitals | below reserve / thin / below standing | lowest city (live) | merchants | houses > 2× cap / over it | players | BUY in | SELL out | other in − out | E_CITY_BROKE (laps started after the grant) | arrivals avg / p95 / max s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 00:58 | 00:37 | 659.52 M | 231.30 M | 0 / 0 / 92 | 1.49 M (SLV) | 39.54 M | 76 / 8.60 M | 0.21 M | 6.77 M | -7.30 M | 0.36 M | 111 | 3.09 / 5.03 / 10.25 |
| 01:12 | 00:37 | 656.85 M | 231.86 M | 0 / 0 / 106 | 0.68 M (CLL) | 42.21 M | 70 / 9.44 M | 0.21 M | 10.80 M | -15.32 M | 1.68 M | 0 | 2.99 / 4.65 / 10.25 |
| 01:20 | 00:37 | 653.66 M | 231.77 M | 1 / 0 / 116 | 0.23 M (CLL) | 45.40 M | 89 / 11.66 M | 0.21 M | 13.54 M | -21.60 M | 2.05 M | 0 | 3.02 / 4.64 / 10.25 |
| 01:35 | 00:37 | 648.05 M | 231.87 M | 2 / 0 / 130 | 0.05 M (ACA) | 51.02 M | 122 / 15.70 M | 0.21 M | 16.76 M | -31.18 M | 2.79 M | 0 | 3.02 / 4.44 / 10.25 |
| 01:41 | 01:37 | 647.40 M | 230.59 M | 0 / 2 / 113 | 0.54 M (ACA) | 52.26 M | 141 / 16.30 M | 0.21 M | 0.60 M | -1.72 M | 0.67 M | 0 | 2.93 / 4.36 / 10.25 |
| 01:50 | 01:37 | 646.69 M | 231.31 M | 1 / 2 / 122 | 0.00 M (HIR) | 52.99 M | 142 / 17.53 M | 0.21 M | 3.50 M | -5.60 M | 0.93 M | 0 | 2.92 / 4.44 / 10.25 |
| 01:58 | 01:37 | 646.16 M | 231.60 M | 2 / 2 / 122 | 0.01 M (HIR) | 53.66 M | 143 / 17.82 M | 0.21 M | 5.98 M | -8.98 M | 1.32 M | 0 / post-0174 0 | 2.81 / 4.19 / 5.72 |
| 02:05 | 01:37 | 645.80 M | 231.73 M | 2 / 2 / 125 | 0.01 M (HIR) | 55.00 M | 154 / 18.02 M | 0.21 M | 7.29 M | -11.86 M | 2.52 M | 0 / post-0174 0 | 2.81 / 4.18 / 5.72 |
| 02:20 | 01:37 | 649.87 M | 231.79 M | 1 / 1 / 122 | 0.34 M (ACA) | 56.36 M | 104 / 18.85 M | 0.21 M | 10.02 M | -22.02 M | 14.03 M | 0 / post-0174 0 | 2.77 / 4.02 / 5.72 |
| 02:35 | 01:37 | 648.64 M | 231.75 M | 1 / 1 / 122 | 0.35 M (ACA) | 62.77 M | 147 / 24.55 M | 0.21 M | 13.04 M | -32.15 M | 19.90 M | 0 / post-0174 0 | 2.78 / 4.01 / 5.72 |
| 02:41 | 02:37 | 648.96 M | 231.44 M | 0 / 0 / 108 | 0.50 M (HIR) | 63.36 M | 150 / 25.07 M | 0.21 M | 1.08 M | -1.77 M | 0.99 M | 0 / post-0174 0 | 2.79 / 3.98 / 5.32 |
| 02:50 | 02:37 | 649.55 M | 231.94 M | 1 / 1 / 112 | 0.50 M (HIR) | 64.46 M | 146 / 26.36 M | 0.21 M | 3.26 M | -5.29 M | 2.93 M | 0 / post-0174 0 | 2.79 / 3.98 / 5.64 |
| 03:05 | 02:37 | 649.45 M | 232.33 M | 1 / 1 / 114 | 0.50 M (HIR) | 66.45 M | 160 / 28.09 M | 0.21 M | 6.88 M | -11.31 M | 5.22 M | 0 / post-0174 0 | 2.77 / 3.98 / 9 |
| 03:20 | 02:37 | 653.57 M | 232.69 M | 0 / 0 / 110 | 0.72 M (ANG) | 65.68 M | 101 / 26.40 M | 0.21 M | 8.71 M | -17.99 M | 14.18 M | 0 / post-0174 0 | 2.75 / 3.88 / 9 |
| 03:35 | 02:37 | 654.29 M | 233.38 M | 0 / 0 / 107 | 0.68 M (ANG) | 66.15 M | 121 / 27.71 M | 0.21 M | 12.01 M | -22.05 M | 15.67 M | 0 / post-0174 0 | 2.77 / 3.86 / 9 |
| 03:41 | 03:37 | 654.80 M | 233.29 M | 0 / 0 / 95 | 0.64 M (ANG) | 67.45 M | 120 / 29.09 M | 0.21 M | 1.00 M | -2.70 M | 2.00 M | 0 / post-0174 0 | 2.77 / 3.91 / 9 |
| 03:50 | 03:37 | 653.96 M | 233.42 M | 0 / 0 / 96 | 0.56 M (ANG) | 69.21 M | 138 / 30.32 M | 0.21 M | 2.43 M | -6.06 M | 3.10 M | 0 / post-0174 0 | 2.7 / 3.84 / 9 |
| 04:05 | 03:37 | 653.74 M | 233.54 M | 0 / 0 / 98 | 0.51 M (ANG) | 72.38 M | 158 / 33.18 M | 0.21 M | 5.50 M | -12.81 M | 6.56 M | 0 / post-0174 0 | 2.8 / 3.9 / 10.29 |
| 04:20 | 03:37 | 659.67 M | 234.12 M | 0 / 0 / 96 | 0.44 M (ANG) | 68.63 M | 91 / 30.16 M | 0.21 M | 8.64 M | -17.73 M | 14.28 M | 0 / post-0174 0 | 2.87 / 3.95 / 10.29 |
| 04:35 | 03:37 | 658.55 M | 234.37 M | 1 / 1 / 96 | 0.17 M (TEN) | 73.58 M | 121 / 33.37 M | 0.21 M | 11.31 M | -25.97 M | 18.73 M | 0 / post-0174 0 | 2.86 / 3.92 / 10.29 |
| 04:41 | 04:37 | 658.61 M | 233.99 M | 0 / 0 / 84 | 0.26 M (TEN) | 74.01 M | 132 / 33.46 M | 0.21 M | 0.19 M | -0.65 M | 0.33 M | 0 / post-0174 0 | 2.85 / 3.91 / 10.29 |
| 04:50 | 04:37 | 658.37 M | 234.22 M | 2 / 2 / 87 | 0.23 M (ANG) | 75.59 M | 144 / 34.36 M | 0.21 M | 1.48 M | -3.75 M | 1.91 M | 0 / post-0174 0 | 2.87 / 3.92 / 10.29 |
| 05:05 | 04:37 | 659.74 M | 234.51 M | 2 / 2 / 86 | 0.18 M (ANG) | 75.75 M | 131 / 35.22 M | 0.21 M | 4.72 M | -7.44 M | 3.72 M | 0 / post-0174 0 | 2.83 / 3.98 / 5.51 |
| 05:20 | 04:37 | 662.84 M | 234.84 M | 2 / 2 / 91 | 0.18 M (ANG) | 76.53 M | 99 / 36.27 M | 0.21 M | 7.29 M | -15.01 M | 11.83 M | 0 / post-0174 0 | 2.81 / 4.01 / 5.51 |
| 05:35 | 04:37 | 662.49 M | 234.91 M | 2 / 2 / 94 | 0.18 M (ANG) | 78.44 M | 120 / 37.88 M | 0.21 M | 9.00 M | -18.94 M | 13.69 M | 0 / post-0174 0 | 2.83 / 4.21 / 10.1 |
| 05:41 | 05:37 | 662.65 M | 234.55 M | 1 / 1 / 86 | 0.28 M (ANG) | 79.83 M | 127 / 39.22 M | 0.21 M | 0.35 M | -1.62 M | 1.34 M | 0 / post-0174 0 | 2.86 / 4.25 / 10.1 |

### What one hour looked like (00:37 → 01:37, rolled)

| | 00:37 | 01:37 | change |
|---|---|---|---|
| city purses | 659.7 M | 647.9 M | **−11.8 M** |
| merchant purses | 39.5 M | 52.3 M | **+12.7 M** |
| players | 0.21 M | 0.21 M | 0 |

- **The hour's city flows:**
  - BUY +16.8 M against SELL −31.2 M;
  - TAX +1.5 M, SHARE +1.38 M (one batch at the `:07` reconcile), WAGES +0.50 M, DONATION +0.16 M,
    PROVISION / REPAIR / TOW +0.15 M;
  - NPC_REFOUND −0.87 M, DIVIDEND −0.04 M.
- **The drain was rising:**
  - 4.6 M/h measured at 01:12;
  - 8.4 M/h at 01:20;
  - 11.8 M/h over the full hour.
  - More of 0173's long loops were landing: 29 post-0173 laps had closed at 01:12, 484 at 01:41 (max net +392 k).
- **Callao (CLL)** went 2.00 M → 0.68 M (01:12) → 0.23 M (01:20, under its 244 k reserve) → 0.17 M (01:35).
  - One merchant (Hermanos Tapia, fleet *Ruta Sofala*) sold Mace and Bird-of-Paradise Plumes there at ~27 k/t
    that she had bought at ~1.2 k/t: three lines of ~590 k at 01:07.
  - Profit 570 k on a 596 k line; tax 85 k back.
- **Acapulco (ACA)** went 2.00 M → 0.05 M (01:35).
- **The bid factor stayed 1 at both** while their live purses emptied. It read the ROLLED purse, so nothing
  slowed the drain inside the hour.
- **At the 01:37 roll** CROWN_AID topped both up to their reserves from their capitals:
  - CLL +500 k from AYU;
  - ACA +505 k.
  - The reserves had jumped with the haul, because the reserve is 3× the SELL day: CLL 244 k → 669 k,
    ACA 146 k → 542 k. So both now bid 0.62 / 0.55.
- **EARNINGS:** +0.68 M world-wide at the first day step.
- **Refusals, by lap close (half hour, UTC):**

| 23:00 | 23:30 | 00:00 | 00:30 | 01:00 | 01:30 |
|---|---|---|---|---|---|
| 180 | 188 | 69 | 32 | 30 | 1 |

  - In laps that started after 00:32:44, after 00:37 and after 00:55: **0, 0, 0**.
  - **CORRECTION (05:45, see §8):** that count missed long laps that STARTED before the grant. When each refusal
    is timed by the fleet's departure from the refusing port, **3 refusals happened after the grant**, at
    Callao and Acapulco between 01:00 and 01:30, while those two ran dry (before 0174). Callao's was Galeón de
    Acapulco at 01:19: she sold one Mace line for 624,656, and her other lines were refused.

### Where the money went (the distance premium)

- Every SELL flow between the 00:37 roll and 01:24 was matched to its event and its `port_goods` row (1,814 of
  1,814; scratch `prem.sql`, read-only).
- Cities paid **27.45 M** for cargo:
  - the base, Σ round(total / haul): **17.23 M**;
  - the distance premium, Σ total − base: **10.23 M (37 %)**, all of it to merchants (no player sold far).
- The purse's base share (17.2 M) against BUY taken in (~16 M) is the own-trade swing the 2 M / 10 M purses
  were sized for. **The premium is the one-way transfer.**
- A city sells its own goods at the maker's price (haul 1) and buys a far good at up to 600×. Each long haul
  therefore moves city money to the trader. The return paths that hour were 10× too small: TAX 1.5 M, SHARE
  1.38 M, DONATION 0.16 M.

### The return path's capacity (shares)

- 29.5 M of shares are offered world-wide at today's works levels: 80,011 shares over 952 works, level mean
  1.10, max 5.
- `npc_invest` took at most 50 houses an hour, one stake each, at the `:07` reconcile.
- The houses above the cap grew 76 → 141 in 43 minutes. The 50-a-hour door left most of them holding.

## 3. Projection

- **Total city money is falling steadily while merchant money climbs.** This is one of the two triggers.
  - −11.8 M in the first full hour, and the rate was still rising as post-0173 loops landed.
  - At 12 M/h the purses lose ~290 M a day. The 0173 planner figure (861 fleets × ~575 k a loop) is far above that.
- **Individual far ports empty inside an hour**, faster than the hourly roll can react: Callao 2.0 M → 0.17 M in
  58 minutes, Acapulco 2.0 M → 0.05 M. Each was saved only by CROWN_AID at `:37`.
  - A capital holds 10 M and gives only what it holds above its own reserve. With several of its cities
    draining at once, a capital empties within hours.
  - After that, `E_CITY_BROKE` is the only brake.

## 4. The fix — migration 0174 (`osn-circulation`)

The shape of (1) was the coordinator's (01:25 UTC): "the premium is paid by the city's people, not its purse".

1. **The base and the premium.**
   - `public.cargo_haul(port, good)` is the one reader of the stored haul a sale is priced with
     (`port_goods.haul`, ≥ 1).
   - In `cmd.do_sell` (the one SELL body), the city's PURSE pays the base, round(total / haul).
   - The premium, total − base, is posted first as `IMPORT_DEMAND` (+) through `treasury_post`. Then the SELL
     (−total) pays the seller in full.
   - The empty-purse rule judges the BASE: a partial fill shrinks to the steps the purse's share covers, and
     `E_CITY_BROKE` fires only when the purse cannot pay one step's base.
   - At a maker (haul 1) nothing changes.
   - The distance factor is untouched (`haul_at`, `haul_rows`, `port_goods.haul`, `mid_from_terms`).
2. **The reserve counts what the purse paid.** `city_sell_outflow` sizes the reserve (3 ×) from SELL net of
   IMPORT_DEMAND. A far city's reserve no longer balloons with the haul, the way CLL's 244 k → 669 k did.
3. **The bid reads the live purse.** `city_bid_factor` now reads `treasury_balance` (rolled + this hour's
   flows) against the rolled reserve.
   - Measured on prod with EXPLAIN ANALYZE of the stable reads over 4,760 calls: 0.224 ms a call as it was, about
     0.30 ms live (+0.07 ms).
   - The arrivals sweep averages 2.9–3.1 s against a 10 s budget.
4. **Merchants give back every hour.** `npc_invest_max_per_hour` 50 → 1000: every house above
   `npc_invest_above` × capital invests (or gives, 0145) at the hourly reconcile.
   - Measured locally (PGlite, a lit head-0174 world, merchants and influence on, N houses credited 2× capital):

     | houses | invested | gave | time |
     |---|---|---|---|
     | 50 | 50 | 2 | 194 ms |
     | 200 | 200 | 22 | 507 ms |
     | 821 | 821 | 189 | 2,456 ms |

   - 0114's 60 s deadline (`npc_upkeep_spent`) still defers what an hour cannot fit.
5. **The client.** The Town Hall's "Yesterday" shows *Paid by its people* (`src/features/map/CityTownHall.tsx`).

**Why this, and not the return paths alone.** The premium was 10.2 M in 47 minutes. TAX + SHARE + DONATION
together were 3.0 M in the hour, and the shares on offer are 29.5 M in all. No setting of the share knobs closes a
gap that size. Making the premium the townsfolk's leaves each purse with exactly the trade it was sized for.

## 5. The money supply after 0174 (stated; the owner decides on a sink)

- **Minted:**
  - IMPORT_DEMAND, ≈ the premium: ~13 M an hour at today's rate (10.23 M in 47 minutes), and rising as long
    loops land;
  - EARNINGS (0172), ~0.7 M at a day step;
  - FOUNDING of new houses.
- **Where it lands:**
  - The sellers' purses: today all merchants, since no player sold far in the window.
  - From them it returns to cities as TAX (≈ 15 % of the profit at a 3 % column × 5), SHARE and DONATION, and
    through services (PROVISION, REPAIR, WAGES).
  - Players' purses are flat (0.21 M).
- **Existing sinks:** none destroy money. Wages, repairs, provisions, builds, tuition, tow and hire are all paid
  INTO the harbour (0122; WAGES go to the harbour the voyage makes). The two stated leaks of ECONOMY_LOOP §1.2
  are ≈ 0.
- **So total money grows without bound** by roughly the premium, ~300 M a real day at the present rate,
  against ~700 M today.
  - Once the 29.5 M of offered shares are bought, merchant purses grow by the premium less tax.
  - Prices do not read the world's money (`world.quote` reads stock, affinity, spread, tax and the bid
    factor), so nothing in play inflates. The number itself grows.

### NOT the owner's — confirm

- (1) The premium is minted as townsfolk demand, not taken from the purse.
- (2) The reserve counts the purse's net outflow. (3) The live bid. (4) 1000 an hour.
- **No sink is built.** Options for the owner:
  - (a) a ceiling on a merchant's purse, above which the surplus is given to the cities of her loop;
  - (b) the premium paid only while a city is under its standing purse;
  - (c) a share of the premium kept by the city (the townsfolk pay the city, not all of it to the seller);
  - (d) merchants spend their surplus on bigger hulls (S18 yards).

## 6. Verify (run once each, worktree `~/dev/bv-circ` off main `11b8a9e`, real `npm ci`, the main clone's `node_modules/.cache` copied, no `.env.local`)

- **Hunks against prod.**
  - `cmd.do_sell`, `city_sell_outflow` and `city_bid_factor` were re-dumped from prod at head 0173 with
    `pg_get_functiondef` (read-only).
  - Each of the 7 hunks occurs exactly once, and the three bodies reverse to the dumps (scratch check on the LF
    file).
- **Cached-prefix build** (`BYEHARU_PREFIX_CACHE=required npm run build`):
  - restored 128/166, applied 38 including 0174;
  - world-guard ok;
  - `tsc -b` + vite built (10 m 25 s, most of it the 38 files the copied cache lacked).
- **The 0174 receipt**, applied to the head-0173 snapshot, dark (fresh chain) and lit (`city_treasury_switch(true)`
  first), 389–489 ms. Both said: *"sold 10 t for 181744: people paid 179373, purse 2371 (haul 76.65); a purse
  of the base 2274 bought all 10 t (total 174323); one ducat short of a step's base refused E_CITY_BROKE; the
  bid at half the reserve (live) is 0.75 … city_sell_outflow is SELL net of IMPORT_DEMAND at 238 harbours …
  bodies reverse … no client door moved."*
- **`npx eslint .`** clean. **`npx tsc -b`** clean. **`db:check-versions`**: 166 distinct, no collisions.

## 7. Deploy

- PR #200 was merged and `db push`ed by the coordinator. Prod head is **0174**, verified read-only at 01:58:
  - `schema_migrations` head is `20260818000174`;
  - the first `IMPORT_DEMAND` flow is at 01:58:14;
  - `npc_invest_max_per_hour` = 1000;
  - `city_bid_factor` reads `treasury_balance`;
  - all 8 cron jobs are active.
- PR #200's CI:

  | check | result |
  |---|---|
  | select | pass |
  | build | pass |
  | disposable-chain | pass (real Supabase applied 0174 on the 165-file snapshot) |
  | pglite-gate (ledger) | pass (02 6/6) |
  | pglite-gate (the rest) | pass |
  | pglite-gate (merchants) | **FAIL** |

  - The merchants failure is PROOF 12: *"the probe merchant closed no profitable lap: net −9"*.
  - It is **not 0174's**: main had the identical red at `707408b` (run 39086615230, the same net −9) without 0174.

## 8. The watch with 0174 live (01:58 → 05:41 UTC)

### Money, reading to reading

World = city purses (live) + merchant purses + players.

| UTC | cities | merchants | world | Δ cities | Δ merchants | Δ world |
|---|---|---|---|---|---|---|
| 00:58 | 659.52 M | 39.54 M | 699.27 M | | | |
| 01:12 | 656.85 M | 42.21 M | 699.27 M | -2.67 | +2.67 | +0.01 |
| 01:20 | 653.66 M | 45.40 M | 699.27 M | -3.19 | +3.19 | +0.00 |
| 01:35 | 648.05 M | 51.02 M | 699.28 M | -5.61 | +5.62 | +0.00 |
| 01:41 | 647.40 M | 52.26 M | 699.87 M | -0.65 | +1.24 | +0.60 |
| 01:50 | 646.69 M | 52.99 M | 699.89 M | -0.71 | +0.73 | +0.02 |
| 01:58 | 646.16 M | 53.66 M | 700.04 M | -0.53 | +0.67 | +0.15 |
| 02:05 | 645.80 M | 55.00 M | 701.01 M | -0.36 | +1.34 | +0.98 |
| 02:20 | 649.87 M | 56.36 M | 706.44 M | +4.06 | +1.36 | +5.43 |
| 02:35 | 648.64 M | 62.77 M | 711.62 M | -1.23 | +6.41 | +5.18 |
| 02:41 | 648.96 M | 63.36 M | 712.53 M | +0.32 | +0.59 | +0.91 |
| 02:50 | 649.55 M | 64.46 M | 714.22 M | +0.59 | +1.10 | +1.69 |
| 03:05 | 649.45 M | 66.45 M | 716.11 M | -0.10 | +1.99 | +1.89 |
| 03:20 | 653.57 M | 65.68 M | 719.45 M | +4.12 | -0.77 | +3.34 |
| 03:35 | 654.29 M | 66.15 M | 720.65 M | +0.72 | +0.47 | +1.19 |
| 03:41 | 654.80 M | 67.45 M | 722.46 M | +0.51 | +1.30 | +1.81 |
| 03:50 | 653.96 M | 69.21 M | 723.37 M | -0.84 | +1.75 | +0.91 |
| 04:05 | 653.74 M | 72.38 M | 726.33 M | -0.22 | +3.18 | +2.96 |
| 04:20 | 659.67 M | 68.63 M | 728.52 M | +5.94 | -3.75 | +2.19 |
| 04:35 | 658.55 M | 73.58 M | 732.34 M | -1.12 | +4.94 | +3.82 |
| 04:41 | 658.61 M | 74.01 M | 732.82 M | +0.06 | +0.43 | +0.49 |
| 04:50 | 658.37 M | 75.59 M | 734.17 M | -0.24 | +1.58 | +1.35 |
| 05:05 | 659.74 M | 75.75 M | 735.70 M | +1.36 | +0.16 | +1.53 |
| 05:20 | 662.84 M | 76.53 M | 739.59 M | +3.11 | +0.78 | +3.89 |
| 05:35 | 662.49 M | 78.44 M | 741.14 M | -0.36 | +1.90 | +1.55 |
| 05:41 | 662.65 M | 79.83 M | 742.68 M | +0.16 | +1.39 | +1.55 |

- **Before 0174** the world's money was CONSERVED to the ducat: 699.27 M from 00:58 to 01:35. The cities lost
  exactly what the merchants gained, 11.8 M an hour.
- **With 0174:**

  | 01:58 → 05:41 (3 h 43 m) | change | per hour |
  |---|---|---|
  | cities | 646.2 → 662.7 M, **+16.5 M** | **+4.4 M/h** |
  | merchants | 53.7 → 79.8 M, +26.2 M | +7.0 M/h |
  | players | flat at 0.21 M | 0 |
  | **world** | 700.0 → 742.7 M, **+42.6 M** | **+11.5 M/h**, ≈ **275 M a real day**, ≈ +39 % a day on today's 700 M |

### Per roll

| hour (rolled) | Δ cities | IMPORT_DEMAND minted | SHARE back | DONATION | TAX | EARNINGS |
|---|---|---|---|---|---|---|
| 00:37 → 01:37 (before 0174) | **−11.8 M** | — | 1.38 M | 0.16 M | 1.52 M | (0.68 M at 01:37) |
| 01:37 → 02:37 (0174 from 01:58) | +0.8 M | 11.7 M | 4.86 M | 0.66 M | 1.76 M | 0.68 M |
| 02:37 → 03:37 | +5.8 M | 8.6 M | 4.91 M | 0.33 M | 1.05 M | 0.36 M |
| 03:37 → 04:37 | +4.2 M | 11.3 M | 4.81 M | 0.33 M | 1.54 M | 0.31 M |
| 04:37 → 05:37 | +3.9 M (rolled 658.7 → 662.6) | 8.3 M | 3.61 M | 0.07 M | 1.12 M | 0.28 M |

### Where the minted money goes, and what returns

- **IMPORT_DEMAND lands with the sellers.** Every seller in the window was a merchant; players are flat at 0.21 M.
- **The return path (knob 1000) roughly tripled.** SHARE is +3.6–4.9 M at each `:07` reconcile, against 1.38 M at 50 houses.
  - The houses over 2× capital fall right after each reconcile (154 → 104, 160 → 101, 158 → 91) and climb back
    within the hour.
  - What they hold over the cap still grows: 17.8 M (01:58) → 39.2 M (05:41).
  - The shares absorb ~4–5 M an hour against ~8–12 M minted.
- **Between reconciles the purses still drain slowly.** The base, round(total / haul), still runs a little above
  BUY at the far ports. The cities fall 0.2–1.2 M in a 15-minute window and come back with the hourly
  SHARE / DONATION batch.
- **Thin cities brake themselves inside the hour now (the live bid):**

  | city | low | bid | refilled by |
  |---|---|---|---|
  | HIR | 11.6 k (02:05) | 0.51 | CROWN_AID from SAK |
  | ACA | 202 k (02:05) | 0.69 | CROWN_AID |
  | TEN | 175 k (04:35) | 0.91 | CROWN_AID (+79 k) |
  | ANG | 181 k (05:05) | 0.86 | CROWN_AID |

  - ANG is the one slow loser. It drifts ~0.1–0.15 M an hour and is held at its reserve by its capital each roll.
  - After every roll: 0–1 harbour below reserve. Below the standing purse: 122 → 86.
  - Capitals 231.6 → 234.6 M: the crown is not being drained.
- **Arrivals sweep:** avg 2.7–2.9 s, p95 3.8–4.3 s, max 5.3–10.3 s. Before: 2.9–3.1 / 4.4–5.0 / 10.25. No regression
  from the live bid; one failed run in the hour before 0174, none after.

### E_CITY_BROKE, timed by the stop (scratch `brk2.sql`, read-only)

- **Method.** Each refusal in a lap closed since the grant is timed by the fleet's last departure from the
  refusing port inside that lap (`voyages.origin_port_id` / `departed_at`; the sale happens at the docking just
  before).
- **The count:** 94 refusals in laps closed since 00:32:44.
  - 85 timed **before** the grant: 46 in 00:00–00:30, 18 in 23:30–00:00, …
  - **3 after the grant, all before 0174:** ACA and CLL in 01:00–01:30, while they ran dry.
  - **0 after 0174.**
  - 6 untimed: no departure from that port inside the lap.

## 9. Projection and the sink (for the owner)

- **No city is on course to fall under its reserve within 24 h without the crown catching it.**
  - City money rises +4.4 M an hour.
  - The slow losers (ANG, TEN, HIR) are refilled by their capitals, whose purses also rise.
- **But total money grows without bound:** +11.5 M an hour, ≈ 275 M a real day. Almost all of it piles up in
  merchant purses (+7 M/h) that the shares cannot absorb.
  - 29.5 M were on offer at the start. After 3.7 h the merchants hold 39.2 M over the cap.
  - Prices do not read money, so nothing in play inflates. The number itself does.
- **Sink options — NOT the owner's, confirm (none built):**
  - **(a)** A ceiling on a merchant's purse (e.g. `npc_invest_keep` × capital): above it, the surplus is given
    to the cities of her loop (a DONATION outside the influence day cap).
  - **(b)** IMPORT_DEMAND paid only while the buying city is under its standing purse; above it the purse pays
    the whole price (0173 as it was).
  - **(c)** A share of the premium kept by the city: the townsfolk pay the city, and only part of it goes to the
    seller.
  - **(d)** Merchants spend their surplus on bigger hulls or refits at their home yard (BUILD / REPAIR, money
    paid into a city).
  - **(e)** A harbour due on each far sale. The owner declined harbour dues on 2026-10-15
    (ECONOMY_LOOP §11), so this one would reverse his decision.
