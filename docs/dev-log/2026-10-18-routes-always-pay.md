# 2026-10-18/19 — a merchant's route always pays (migration 0197, `osn-routes-pay`)

**The order.** The owner, 2026-10-18 ~13:25 UTC: *"if they wait when there is no profitable route, how long would they
wait? why is there a route that has no profit? this is design defect."* (docs/OWNER_REQUESTS.md row 155.)

## 1. What prod showed (read-only)

Every probe was `begin transaction read only; … rollback;` through `supabase db query --linked`. Every function called
was checked first in `pg_proc.provolatile` and is `s` or `i`. The leg planner (`npc_leg_lines`) and the planner
(`npc_plan`) are volatile, so they were run only on the prod-shaped PGlite world (§3), never on prod.

### The laps (head 0181–0182 at 13:55 UTC; re-measured at head 0194, 2026-10-18 ~17:45 UTC)

| | head 0181 (13:55) | head 0194 (17:45) |
|---|---|---|
| merchant laps closed in 2 h | 1,804 | 1,759 |
| closing ≤ 0 | 927 (51 %) | 902 (51 %) |
| ≤ 0 and traded | 753 | 702 |
| laid up, of 837 routes | 323 | 202 |
| arrivals sweep, last hour | avg 2.14 s, p95 3.30 s | avg 2.98 s, p95 4.26 s |
| reconcile, last four | 62 · 57 · 12 · 13 s | 11 · 13 · 66 · 62 s |

**By the loop's length** (laps closed in three hours, head 0194):

| nm a lap | routes | laps | ≤ 0 | mean a route (3 h) |
|---|---|---|---|---|
| < 1,000 | 25 | 80 | 78 % | 152 |
| 1,000–2,000 | 147 | 605 | 60 % | 973 |
| 2,000–4,000 | 439 | 1,616 | 55 % | 1,687 |
| 4,000–8,000 | 76 | 199 | 26 % | 33,194 |
| 8,000–16,000 | 107 | 137 | 1 % | 121,297 |
| ≥ 16,000 | 43 | 33 | 3 % | 552,271 |

The losing laps are the short loops. 0173's premium is haul 1.03 at 1,000 nm, 1.13 at 2,000 and 1.32 at 3,000. On
a short hop the price gap is smaller than spread + tax + wages + stores. The long loops almost never lose.

### Comptoir Chastellain (the owner's example)

"Voyage Hamburg", a barque (56 tuns, 8 hands), Le Havre ↔ Gdansk, purse 5,576. She had sailed 168 laps, the last
seven at −15, −16, −15, −15, −15, −15, −15. Read at 13:55 UTC:

- **She was not laid up because her loop carried parcels.** 0181 lays a merchant up only when no leg carries a
  parcel (`v_any`), not when the lap loses.
- **The −15 is stores only, on the laps that sold nothing.** Lap 168 bought 3,149 at Gdansk and sold nothing; lap
  166 bought 1,247.
- **When she did sell, the sale did not cover the lap.** Lap 167 sold 1,329 of what lap 166 bought for 1,247: +82.
  Then wages 70, tax 12 and stores 16 left −16.
- **The parcel looked paying at plan time and failed on arrival.** In lap 169 (sailing at 13:55), all three SELLs
  were refused `E_PRICE_LIMIT` at Le Havre *and* at Gdansk ("bid below your limit"). She carries the cargo, so she
  sails, and the lay-up rule never looks at her.
- **On the prod-shaped world** (prices of 13:57) her LEH-GDA loop prices at +508 a lap at plan time. The trade loops
  on offer price at +5,238 to +5,798 a lap.

### Can the loops pay at all? (prod-shaped PGlite, prod's state of 13:57 UTC; `measure.mjs`)

Each of the 837 merchants was put at her lap start, alone, with her present loop and her lap-start candidates priced as
`npc_plan` prices them (the leg planner, tax, wages, stores):

| | 0120 candidates | far open to every hull | **0197 trade candidates** |
|---|---|---|---|
| present loop pays (net > 0) | 702 (84 %) | 702 | 702 |
| present loop carries a parcel but loses | 93 | 93 | 93 |
| some loop on offer pays | 757 (90 %) | 790 | **793 (95 %)** |
| none pays | 80 | 47 | **44** |
| candidates / merchant | 3.5 | 4.7 | 6.3 |

- **The 44 left:** 40 hold under 10,000 d. (25 under 2,000); 21 have two candidates or fewer (a harbour with one known
  leg, e.g. La Rochelle ↔ Salvador).
- **The best loop's kind:** trade 601, kept 172, near 32, near3 32. The best loops' median is 9,656 nm a lap.
- **Why** (this is the measure of "can a loop pay at all"): 0120's far loops were offered only to a hold of 200 tuns or
  more. A far city pays by the unit, so a small hull is paid there too.

## 2. The migration (0197, `a_merchants_route_always_pays`)

1. **A loop pays when a lap of it leaves her more than nothing.**
   - `npc_plan` already priced each loop's net: parcels' profit after tax, less wages and stores (0142).
   - It wrote and sailed a loop whenever some leg carried a parcel. Now `v_pays` = the chosen loop's net > 0.
   - A loop that does not pay is written with **no BUY**: SELL at a profit at every stop, and the cut-loss. She never
     buys into a loss.
   - At her lap start with nothing aboard she is laid up (0181) and re-asked every ~10 min (0182).
   - A paying loop on offer replaces a losing one of hers outright. Her score is ≤ 0, so `npc_loop_switches` passes,
     unchanged.
2. **Loops built from paying trades.** 0120's `far` is replaced by `trade`, for every hull.
   - The `npc_route_trade_candidates` (6) destinations are ranked by the distance premium (`port_goods.haul`, 0173's one
     derivation; `haul_nm = 0` is a city that makes the good): the best haul any good her harbour makes fetches there,
     plus the best haul any good made there fetches at home. So the way back carries a paying good where one exists.
   - Destinations are drawn from every feasible known leg of hers, and every known leg of `npc_route_far_nm` or more
     out of a neighbour (home → X → D → X → home).
   - Each is priced by THE leg planner like every other loop (`world.quote`, the sailed distance, tax, the buyer
     cap), and (1) decides.
3. **Her own loop is priced first.** The candidates are fetched and priced only when it does not pay, when she lies
   off it, or on a review lap (every `npc_route_review_laps`-th, 3). See §3 for why: pricing six trade loops at every
   lap start made the arrivals sweep 2–3 × dearer.
4. **Knobs:** `npc_route_trade_candidates` 6 and `npc_route_review_laps` 3 are new. `npc_route_far_candidates` and
   `npc_route_far_hold_tuns` are deleted; their only reader is gone.

**Kept:** the founding home port and nation (a loop starts and ends at her stop 0), 0101's rest, `npc_fleet_max`, the
one planner (`npc_plan` + `npc_loop_candidates`, no second path), and the buyer cap `npc_buyers_per_good` 3 (§4).

**Hunks:** 14, in two live bodies: `npc_plan` (9) and `npc_loop_candidates` (5). Both bodies were re-dumped from prod at
head 0194 and are byte-equal to the ones the hunks were cut from (and so is `npc_leg_lines`, which is read, not cut).
Every hunk was checked read-only on prod at head 0194 to occur exactly once.

**Self-assert receipt** (the head-0194 image):

> 0197 self-assert ok: A MERCHANT'S ROUTE ALWAYS PAYS. COMPTOIR CHASTELLAIN (Voyage Hamburg; loop set to LEH-GDA true):
> from LEH-GDA (net 279 a lap, 0 BUY) the planner wrote LEH-LUB-CAP-LUB — net 10818 a lap over 10891 nm, 5 BUY,
> sailing; POSITIVE CONTROL, wages eating every parcel: the OLD planner wrote LEH-GDA with 3 BUY at -15 a lap and
> sailed it, the new one laid her up with 0 BUY. THE ROSTER'S FIRST 30: 30 on a loop that pays, 0 waiting (no BUY),
> 0 written a BUY on a loop that leaves nothing; their candidates {"near": 134, "near3": 93, "trade": 178}; …

- **The probe is named for her:** Comptoir Chastellain, her first fleet, laid on her prod loop LEH ↔ GDA where the world
  knows both legs.
- **The positive control** multiplies `wage_per_crew_day` by 10,000 in her own block, so every parcel's profit goes to
  wages and every loop with a parcel nets minus its stores. That is the −15 lap exactly. The OLD planner (a `pg_temp`
  copy of the pre-image, with the old candidates and the two old knobs restored in that block) sails it with its BUYs.
  The new one lays her up with no BUY.
- **Own rows only:** her fleet and the roster's first 30, each set at her lap start inside blocks rolled back whole.
- **The selections, run read-only on prod (head 0194):** Comptoir Chastellain exists ("Voyage Hamburg"). LEH → GDA and
  GDA → LEH are known legs. The first 30 roster routes have two stops or more. The two old knobs exist and their only
  reader is `npc_loop_candidates`.

## 3. Proved on prod-shaped data

The harness (`~/dev/bv-harness/redesign-scratch/sim.mjs`, built from `laps-scratch/lapsim.mjs`) loads prod's knobs,
off-target stocks, merchant and city purses, treasuries and loops into a throwaway PGlite world. It puts every merchant
docked at her stop 0 at a lap start, runs the kickoff (`cmd.advance` for all 837), and then real time: the arrivals
sweep every 15 s, the drift every 10 min and the reconcile at fixed minutes.

**A harness bug, fixed:** `laps-scratch` mapped prod's loops onto fleets by the fleet's NAME, and fleet names repeat
across companies ("Voyage Hamburg"). 1,491 saves landed on 837 routes, and many merchants were sailing another
company's loop. The loops are now keyed by (company, fleet): 837 / 837 saved, and fleets and hulls match prod (3 hulls
differ: 0180's).

**The kickoff stampede is an artefact of the harness, in both arms.** All 837 plan at once on one market, so the buyer
cap fills in roster order. On prod, lap starts are spread over hours.

### 50 minutes each, one at a time on a quiet machine (head 0184 world, prod's state of 13:57)

| | main (old) | 0197 (new) |
|---|---|---|
| kickoff, 837 lap-start plans | 101 s | 144 s |
| laid up after kickoff → at the end | 233 → 49 | 198 → 46 |
| arrivals sweep avg / p95 / max | 2,859 / 10,046 / 10,432 ms | **2,253 / 5,684 / 10,027 ms** |
| reconcile (+20, +45 min) | 4.7 s, 4.1 s | 31.4 s, 15.6 s |
| merchants' money (purse + cargo at cost) | +1.80 M | +2.17 M |
| cities' purses | +12.90 M | +13.85 M |
| stranded (error / docked idle / adrift) | 0 / 0 / 0 | 0 / 0 / 1 anchored |

- A first cut (every lap start priced all candidates; destinations ranked with `world.mid_price` per good) ran
  **6.1 s avg / 11.2 s p95** with reconciles of 63 s and 40 s.
- That is why (3) exists, and why the rank reads `port_goods.haul` in one set read. A plan at a review costs
  127 ms against 44 ms (PGlite, 60 merchants alone); between reviews she prices her own loop only.

### 150 minutes, both arms side by side (head 0194 world, prod's state of 17:46)

(filled from `long-old.json` / `long-new.json` below)

## 4. The buyer cap (kept at 3)

The kickoff on the head-0194 world with 0197 (837 lap-start plans in roster order, on one market):

| `npc_buyers_per_good` | laid up after the kickoff | routes with a BUY | BUY lines |
|---|---|---|---|
| **3** (kept) | 179 | 658 | 2,497 |
| 6 | 80 | 757 | 3,527 |

Six halves the kickoff's lay-ups. But it doubles the buyers who draw down one maker's stock, and that is the "paying at
plan time, refused on arrival" class this slice exists to end. The kickoff is the harness's stampede, not prod's
steady state: lay-ups fall by themselves as the 0182 re-asks reach them (§3). So the cap is **kept at 3**; 6 is the
measured option if the owner wants fewer merchants waiting.

## 5. NOT the owner's — confirm

- **The counts:** 6 trade candidates; a review every 3rd lap; the rank (best haul out + best haul back).
- **"Pays":** a net above 0 a lap at plan time, with no further cushion.
- **What changes for a merchant:** a merchant on a loop that does not pay carries no BUY on it. A small hull may now sail
  a long haul.

## 6. Verify (once per base; worktree `~/dev/bv-redesign`, branch `osn-routes-pay`, real `npm ci`, prefix snapshots copied from `bv-tariff` / `bv-fight-rb`, no `.env.local`)

The number moved three times while this was built: 0186 → 0195 → 0196 → **0197**. Main took 0186 (queue), 0195 (raids
rolled back) and 0196 (P4 tariffs). It is rebased on main `056550b` + 0196, prod head 0196.

- **The two cut bodies, re-dumped from prod at head 0196:** `npc_plan` and `npc_loop_candidates` are byte-equal to
  what the hunks were cut from, and so is `npc_leg_lines`. P4 re-cut `world.tax_rate` / `world.price_why`; the planner
  reads the tax only through `public.profit_tax` in the leg planner, which this file does not touch.
- **Hunks on prod (head 0196, read-only):** 14 of 14 occur exactly once.
- **0197 on the head-0194 image:** self-assert ok (receipt above), applied in 11.1 s.
- **Cached-prefix build at head 0196:** restored 187/189 and applied 0196 + 0197; the world guard ok.
- **tsc -b**: 0. **eslint .**: 0. **db:check-versions**: 189 distinct, no collisions.
- **Proofs on the built image:** 12 files, 85/85 PASS markers (proof 12, the merchants, included). Run at each base:
  0194, 0195 and 0196.
- **CI selector:** pglite-gate (merchants) and (ledger) run, because the file names their tables. The merchants-on world
  is built.
