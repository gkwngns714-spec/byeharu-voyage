# 2026-10-18 — merchant sinks (d) + (a), and why most laps earned nothing (migration 0180, `osn-merchant-sinks`)

**The order.** The owner (2026-10-17 ~23:50 UTC): *"Cities are powerful … make the economy circulate."* After 0174 the
world's money grew +11.5 M/h, almost all of it into merchant purses (docs/dev-log/2026-10-18-circulation-watch.md §8–9).
The owner was offered sinks (a)–(e) and did not answer. The coordinator chose **(d) + (a) by default. The owner may
reverse it.** The distance factor and the 0174 rule are untouched.

## 1. What prod showed first (read-only, 05:37–06:20 UTC, head 0179)

Every probe was `begin transaction read only; … rollback;` through `supabase db query --linked`, calling only stable
functions (`npc_purse_ceiling`'s inputs, `world.quote`, `npc_buy_ceiling`, `city_bid_factor`, `treasury_balance`).

### Merchant purses against capital

| | |
|---|---|
| houses / purses / capital | 821 / 83.27 M / 26.06 M |
| purse ÷ capital, percentiles 10–25–50–75–90–99 | 0.32 · 0.94 · 1.50 · 1.84 · 2.76 · 36.6 |
| above 2× / 3× / 5× capital | 43.0 M / 36.0 M / 26.8 M |

The money sits in a few houses: nau hulls on long 2-stop loops (Casa de Contratación 5.27 M, Factoría de Concepcion
3.39 M at 97× capital, Compañía de Manila 2.83 M …).

### Choosing the ceiling (the hour before 06:03)

Merchants gained +8.27 M net in that hour, after giving 3.68 M through `npc_invest`.

| ceiling k × capital | over it now | houses over | gain of the houses over it | net gain of the band under it | houses whose largest lap (4 h) > 0.9 k × capital | premium they mint, kept (linear) |
|---|---|---|---|---|---|---|
| 2 | 43.3 M | 143 | 12.2 M | −1.43 M | 202 | 79 % |
| **3** | **36.3 M** | **83** | **10.9 M** | **−0.43 M** | **90** | **85 %** |
| 5 | 27.0 M | 55 | 9.3 M | +0.62 M | 33 | 95 % |
| 10 | 17.4 M | 31 | 5.6 M | +3.62 M | 0 | 100 % |

- **3× is the knob** (`npc_purse_ceiling` = 3). It is the smallest multiple at which the band under it stops gaining
  money net, so the merchants' money stops growing.
- The cost: 90 houses (11 %) had a lap bigger than 0.9 × 3 × capital, so their working capital is trimmed. The premium
  they mint falls about 15 % (linear estimate on 25 min of IMPORT_DEMAND, all 5.27 M matched to its seller).

### Why most laps earn nothing (the coordinator's question)

The lighting agent's after-check: laps closing at ≤ 0 rose 53 → 77.5 % since 01:00, and mean bought fell 11.8 k → 5.5 k.

| half hour (UTC) | laps | ≤ 0 | no BUY | no SELL | mean bought | mean net |
|---|---|---|---|---|---|---|
| 01:00 | 627 | 53.4 % | 26.3 % | 30.8 % | 12,173 | 1,074 |
| 03:00 | 770 | 65.2 % | 53.1 % | 48.8 % | 7,901 | 5,237 |
| 05:30 | 748 | 77.5 % | 65.9 % | 62.7 % | 5,506 | 5,644 |

- A zero lap is almost always an **empty lap**. It buys nothing, sells nothing, and pays its stores: net −8 … −22.
  Sample: `[["TUN", [], []], ["LIV", [], []]]`.
- **Refusals in laps closed in the last 90 min:**
  - REPAIR E_UNAVAILABLE 1,969 (harmless);
  - BUY E_PRICE_LIMIT **957**;
  - SELL E_PRICE_LIMIT 406;
  - BUY E_HOLD_FULL 152;
  - SELL E_CITY_BROKE 8.
- **Not the candidates:**
  - **Not saturated far buyers.** Only 31 of the 404 SELL limit refusals were at a city bidding under 1 (TEN 0.88,
    ANG 0.86).
  - **Not exhausted makers.** The BUY refusals spread over 448 port-goods (top: GDA rye 25). Maker stock sits at
    ~0.67–0.83 of target, never under half.
  - **Not the buyer cap.**
- **Plans are fresh:** median plan age is 7–9 minutes.
- **The cause is the planner itself.** `npc_leg_lines` writes `BUY <good> <q> AT <ceiling>`, where
  `npc_buy_ceiling` = the ask carried to the maker's TARGET stock × (1 + patience; houses 0.10–0.26). When the maker is
  under target, the ask is dearer than that, so the line's limit is below the price the planner had just priced the
  parcel at. The line is refused on arrival by construction.
- **Measured on the 2,306 live BUY lines** (06:20): **1,070 are refused by their own limit at today's quote.** The
  ceiling now sits below the ask in 795 of them even for 1 unit.
  - By maker stock ÷ target:

    | stock ÷ target | refused |
    |---|---|
    | 0.5–0.6 | 11 of 11 |
    | 0.6–0.7 | 379 of 436 |
    | 0.7–0.8 | 560 of 1,071 |
    | 0.8–0.9 | 119 of 556 |
    | ≥ 0.9 | 1 of 232 |

  - Routes: 231 plan no BUY at all, 173 have every BUY line dead, 258 have some dead, 175 have none dead.
- **Why it rose:** as merchants drew makers down after 0173, more lines were born dead.

## 2. The migration (0180, `a_merchant_spends_what_she_earns`)

1. **(3) A BUY line is never born refused.**
   - One hunk in `public.npc_leg_lines`: `continue when v_ceiling is null or v_ceiling < q_buy.avg_price`.
   - The parcel is dropped and the ranking's next good is tried.
   - The ceiling's own rule (patience) is unchanged.
2. **(a) The purse ceiling.**
   - `public.npc_purse_ceiling(house)` is the one reading: floor(capital × `npc_purse_ceiling`).
   - `public.npc_give_above_ceiling(now)` runs hourly in `npc_tend_houses`, after `npc_invest`, while the merchants are
     on. Each house above her ceiling gives the whole excess to the distinct harbours of her loop, in equal parts:
     - SHARES first, where a work offers them (`invest_for`, the players' door);
     - the rest as **`MERCHANT_SURPLUS`** (`pay_city`).
   - She ends AT her ceiling, and nothing is destroyed.
   - MERCHANT_SURPLUS counts no influence. An uncapped DONATION would swamp D7's 20,000-a-day race cap.
3. **(d) A hull at the yard she lies at.**
   - `public.npc_build_for(fleet)` runs hourly in `npc_tend_route`, before the halt law.
   - It applies to a house above her ceiling whose fleet lies DOCKED at a harbour with a build yard, while
     `earned_caps` / `house_ship_max` leave room. She lays down ONE hull: her flagship's class as her country's line
     builds it there (`npc_hull_for`).
   - The money goes through the players' doors:
     - `cmd.do_build`: BUILD = the yard's labour, into that city, with every yard rule;
     - `cmd.do_hire`: HIRE, her hull's crew;
     - `cmd.do_provision`: PROVISION, her standing order's days.
   - Endowed as at founding: timber and fittings, gear (`npc_fit_loadout`) and level (`npc_fix_level`).
   - She pays only from what stands above the ceiling. Any refusal rolls the whole purchase back.
   - Neither `standing_routes` nor the fleet's status is written, so the 0101 rest holds.
4. **Receipt and client.**
   - The receipt adds `built`, `ceiling` and `ceiling_given` (`npc_tend_sum`).
   - The Town Hall's "Yesterday" shows *Merchants' surplus* (`src/live/CityTownHall.tsx`).

**Hunks:** 9, in four live bodies: `npc_leg_lines` (1), `npc_tend_route` (3), `npc_tend_houses` (3), `npc_tend_sum` (1).
Each is asserted to occur once, each body reverses to its pre-image, and every ACL is unchanged.

**Self-assert receipt** (the head-0179 image):

> 40 merchant legs at 65 % maker stock — the new planner wrote 14 BUY lines, 0 refused by their own limit; the old one
> 33 lines, 19 refused (positive control) … a house AT her ceiling is offered none; 2,000,000 d. above it, her fleet at
> LIS laid down a carlat (1 → 2 hulls) through cmd.do_build: BUILD 7000 = the yard's labour, HIRE 240 for 12 hands,
> PROVISION 99, her gear 2 = her flagship's, still DOCKED, her rest untouched, no flow outside the city, the world's
> money unchanged (31 ms). A house 1,234,567 above her ceiling gave 560,000 in shares + 674,567 as MERCHANT_SURPLUS to 7
> harbours of her loop and stands at her ceiling 678,000; no influence, the world's money unchanged (36 ms).

## 3. Simulated locally on prod-shaped numbers

The scratch `sim.mjs` ran on the head-0179 world image with 0180 applied. It loaded prod's 1,868 off-target maker
stocks, 821 merchant purses and 238 city purses (exported read-only at 06:05), lit the treasury, and switched routes and
merchants on.

| | before | after 0180 |
|---|---|---|
| merchant purses | 81.43 M | **46.91 M** |
| city purses | 666.51 M | **701.02 M** (+34.5 M; the world's total unchanged) |
| houses above the ceiling | 57 (34.5 M over) | 0 |
| harbours below their standing purse | 81 | 63 |

- **The ceiling pass:** 57 houses, 21.72 M in shares + 12.65 M as MERCHANT_SURPLUS, in 0.9–1.0 s.
  - The image's works offer more shares than prod's, which are largely bought. On prod the split leans to
    MERCHANT_SURPLUS.
  - A second hour (10 % of houses +50 k) gave 0.64 M from 38 houses, alongside 134 investments and 54 gifts by
    `npc_invest`. `npc_tend_houses` took 0.64 s.
- **The build pass:** every rich house's fleet tried once at its home berth.
  - 29 were at a yard: 9 built, and 20 were refused `E_YARD_TOO_SMALL` (a nau at a tier-2 yard), rolled back whole.
  - 145 k was paid into cities. 0.16 s for all 62.
- **The planner** (all 837 routes, old body vs new, on prod stocks):

  | | old | new |
  |---|---|---|
  | BUY lines | 3,024 | 2,436 |
  | lines refused by their own limit | **949 (31 %)** | **0** |
  | routes with every BUY line dead | 41 | 0 |
  | routes with no BUY at all | 231 | 233 |
  | live buying planned (Σ qty × ask) | 27.78 M | **32.97 M (+19 %)** |
  | time, 837 plans (PGlite) | 64 s | 74 s (+15 %) |

  The new planner fills the hold and budget the dead lines held with parcels that clear.

## 4. Money after the change (projection from the measured hour, stated)

- **Merchants:** the band under 3× gained −0.43 M net in the measured hour, so merchant money stops growing. The houses
  above it gave their 10.9 M/h to cities.
- **Cities:** +4.4 M/h (measured with 0174) plus roughly the merchants' former gain, about +8 M/h, for **≈ +12–13 M/h**.
  Every harbour of a rich house's loop receives a share.
- **The world: not much lower.**
  - Neither (a) nor (d) destroys money, and the mint (IMPORT_DEMAND ≈ 12.6 M/h, 05:37–06:01) is untouched by order.
  - Total growth falls only by the trimmed laps (≈ −15 % of the premium, ≈ −1.9 M/h), to ≈ +9.5–11 M/h.
  - (3) may push it back up: +19 % live buying planned means more cargo actually lands, and more premium.
  - **The target "total money growth comes down sharply" is NOT reachable by (d) + (a).** Only a change to the mint
    (option (b) or (c), or a sink that removes money) does that. That is the owner's call.
- **Fleet count:** `npc_fleet_max` is untouched. (d) adds hulls, not fleets.
  - Eligible right now: 72 rich fleets, 45 with a yard on their loop. 6.8 % of merchant fleets are docked at any
    moment, and 0 rich fleets were docked at a yard at 06:18. Two-thirds of the local attempts were refused for yard
    tier.
  - Expect about one hull an hour, against 892 merchant hulls.
- **Sweep cost:**
  - The arrivals sweep was **already avg 3.07 s / p95 4.38 s** in the hour to 06:18, before this change.
  - (d) adds about one hull an hour: negligible.
  - (3) makes a plan ~15 % dearer on PGlite, where a plan cost ≈ 77 → 89 ms. At ~25 lap closes a minute that is
    ≈ +5 ms per 15 s sweep if plans run in it (inferred, not measured on prod).
  - Watch the avg after deploy.
- **New refusals:**
  - None for players.
  - Merchants: `E_YARD_TOO_SMALL` / `E_WRONG_YARD` / `E_NEEDS_SKILL` / `E_UNDER_CEILING` on a hull attempt. These are
    rolled back and noted in the reconcile receipt, not in any lap.

## 5. NOT the owner's — confirm

- **The choice and the knob:**
  - (d) + (a) themselves, chosen by default;
  - the ceiling 3 × capital;
  - equal parts to her loop's harbours;
  - MERCHANT_SURPLUS counting no influence.
- **The hull purchase (d):**
  - one hull an hour, only while docked at a yard;
  - timber, fittings and gear endowed (only labour, hire and stores paid).
- **Not bought:** refits and gear repairs. Gear wear is dark (`gear_wear_bite` false), a merchant's loadout carries no
  refit (0158), and her hull repairs are already paid every lap.
- **The planner fix (3):** a parcel whose ceiling is under its ask is dropped, not bought dearer.

## 6. Verify (once each; worktree `~/dev/bv-sink` off main `d233edd`, real `npm ci`, the main clone's `node_modules/.cache` plus bv-light's p0171 prefix snapshot, no `.env.local`)

- **0180 on the head-0179 image:** self-assert ok, receipt above.
- **Cached-prefix build** (`BYEHARU_PREFIX_CACHE=required npm run build`):
  - restored 171/172, applied 1 (0180), world-guard ok;
  - tsc + vite built in 19.7 s.
- **tsc -b** clean, **eslint .** clean, **db:check-versions** 172 distinct, no collisions.
- **Proofs on the built image** (scratch `proofs-on-image.mjs`): 12/12 green, proof 12 (merchants) included.
- **Prod head re-read at push:** `20260818000179`, so this file is 0180.
- **PR #211 CI** (run 39104305593, about 10 min wall-clock):

  | check | result |
  |---|---|
  | select | pass (8 s) |
  | build | pass (1 m 2 s) |
  | disposable-chain | pass (2 m 25 s) |
  | pglite-gate (the rest) | pass (6 m 15 s) |
  | pglite-gate (merchants) | pass (3 m 19 s) |
  | pglite-gate (ledger) | pass (9 m 37 s) |
