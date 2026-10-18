# 2026-10-18 — a merchant does not sail for nothing (migration 0181, `osn-no-empty-laps`)

**The order.** The owner: *"redesign the routes that are like this, and also that gives negative cash"* — the merchant
laps that close at zero or less. Earlier slices of the same order: 0142, 0150, 0180.

**What 0180 left.** 0180 stopped BUY lines being born dead, and laps carrying a BUY price-limit refusal fell from 24.5 %
to 6.3 %. But the share of merchant laps closing at ≤ 0 stayed at ~75 % (the 0180 watch, 07:29–09:11 UTC):

| | short laps (< 45 min), pre-0180 | short laps, post-0180 |
|---|---|---|
| laps closing ≤ 0 | 78.9 % | 76.5 % |
| mean net | 189 | 188 |
| median net | −18 | −16 |
| plan no BUY at all | 63 % | 59 % |

## 1. Why ~60 % of short laps plan no BUY (prod, read-only, 09:16–09:58 UTC, head 0180)

Every probe was `begin transaction read only; … rollback;` through `supabase db query --linked`. Every function called
was checked first in `pg_proc.provolatile` and is `s` or `i`: `world.trade_routes`, `world.quote`,
`world.daily_cap_remaining`, `npc_affordable`, `npc_buy_budget`, `npc_buy_ceiling`, `profit_tax`, `npc_loop_candidates`,
`npc_feasible_legs`, `fleet_free_hold`, `ship_cargo_tuns`, `voyage.fleet_speed`. The leg planner itself
(`npc_leg_lines`) is volatile, so its filters were re-stated in one read-only SQL over the same stable authorities
(scratch `diag.sql`, `diag2.sql`).

- **The routes.** At 09:16, **283 of the 837** merchant routes carried no BUY line at any stop. 281 of them are 2- or
  3-stop loops; 262 sail under 4,000 nm a lap.
- **A zero lap is an empty lap.** Sample closed laps: `trades [["TRO",[],[]],["SNT",[],[]],["HAM",[],[]]]`, sold 0,
  bought 0, net −14 … −26 (the stores), and one refusal: `REPAIR E_UNAVAILABLE "nothing aboard needs repair"`.
- **Why her legs carry nothing** (60 no-BUY routes, 140 legs, every ranked good through the planner's filters):

  | the best a leg's goods reached | legs |
  |---|---|
  | the ranking has no profitable good from → to at all | 48 |
  | the sink takes nothing above cost × (1 + `npc_sell_margin`): spread + tax eat the gap of a short leg | 52 |
  | held by `npc_buyers_per_good` (three other merchant routes already buy every paying good here) | 22 |
  | the BUY ceiling under the ask | 13 |
  | a parcel would pass now (the market moved since her plan) | 5 |

- **The candidates are not the bug.** At a lap start `npc_plan` prices her loop and up to 15 candidates from where she
  lies (`npc_loop_candidates`: 5 nearest out-and-back, near3, far only at ≥ 200 tuns), and a loop that pays wins
  (`npc_loop_switches`: a paying best beats a losing present loop). Small hulls (55–90 tuns) get 1–9 candidates. For 30
  no-BUY routes the candidates' legs were re-priced now: 19 had a candidate leg with a paying parcel at this moment
  (buyer cap and ceiling not applied), 11 had none — the market moves, and at her last lap start none paid.
- **What is wrong is the else.** When no loop pays, 0115 ("a merchant is never parked") writes her own loop in ballast and
  she sails it, paying her stores. That is the planned-empty lap.
- **Not the cause:** the 0101 home rest (it only delays the lap start), founding SELL-only routes (every route is
  re-planned at each lap start), the buyer cap alone (22 of 140 legs).

### Lines that die after birth

- At 09:20, of **1,681** live BUY lines, **694** would be refused if executed at that moment's ask:
  - **345** only by the limit stored at plan time — the ask had passed it while her next stop's bid still paid
    `npc_min_return_pct` over the ask;
  - **349** because the parcel no longer pays at all (the next stop's bid / 1.05 is under the ask).
- At 09:58, of 1,446 live lines, 254 would be refused (215 only by the stored limit, 39 because they no longer pay).
  **Under 0181's rule: 40** (39 that no longer pay, 1 whose size walks the price past her patience).

### REPAIR E_UNAVAILABLE

- In laps closed 07:30–09:30: **2,407** REPAIR E_UNAVAILABLE of 3,789 refusals, and **every one** reads "nothing aboard needs
  repair" (one other REPAIR refusal: E_INSUFFICIENT_FUNDS). **0 E_NO_YARD**: 0142 already keeps REPAIR off yardless ports.
- The cause: `npc_plan` marks the first shipyard of every loop `repair` (0142), and `cmd.standing_route_lines` wrote
  `REPAIR` whenever a stop is marked, whether or not anything was worn. Merchant hulls rarely wear, so it is refused on
  almost every lap.

The other refusals in that window: BUY E_PRICE_LIMIT 548, SELL E_PRICE_LIMIT 552, BUY E_HOLD_FULL 164, SELL E_NO_CARGO 56,
BUY E_INSUFFICIENT_FUNDS 53, PROVISION E_INSUFFICIENT_FUNDS 8.

## 2. The migration (0181, `a_merchant_does_not_sail_for_nothing`)

1. **She waits in port** (`public.npc_plan`).
   - At a lap start (docked at her stop 0, no open lap, planned alone), when the loop she would sail has no paying parcel
     — every loop on offer was priced and none carries one — and she carries nothing, she is laid up where she lies.
   - The lay-up goes through `cmd.standing_route_pause_for(…, 'laid_up', 'No cargo pays on any leg of her loops at
     present; she waits in port.')`. It is written once: a lay-up already standing is not written again. She is counted
     `waiting`.
   - `cmd.run_standing_route` already refuses to open a lap that its own plan paused (0114), so the lap never starts and
     no store is bought.
   - With cargo aboard she still sails, so her SELLs and 0142's cut-loss can clear it. Mid-lap, off her loop and on the
     switch's pass nothing changes.
2. **She re-plans at every tend** (`public.npc_tend_route`).
   - The hourly tend already lifts `laid_up` by re-planning her from where she lies. A plan that lays her up again
     (receipt `waiting`) now leaves her waiting and counts it. A plan that pays resumes her through the same door as before.
   - `npc_tend_sum` adds `waiting`.
   - The client already names the state: "Laid up" (`src/live/merchantWords.ts`, `world.port_merchants`).
3. **A BUY limit is priced as she arrives.**
   - `public.npc_buy_ceiling(port, good, patience)` is now the ask at the quay now (`world.quote`, one unit) × (1 +
     patience). Before, it was the ask carried to the stock the port is supposed to hold, which under target sits below
     the ask itself.
   - `cmd.standing_route_lines`, as she arrives, reads that ceiling live for a merchant's BUY instead of the limit stored at
     plan time. It is still never above what her next stop's bid lets her pay (0114's `npc_min_return_pct` bound).
   - The planner stores the same reading at plan time. 0180's "never born refused" check now drops only a parcel whose
     own size walks the price past her patience.
4. **REPAIR only when due.**
   - `public.fleet_repair_due(fleet, to %)` is the one reading of what a repair would mend: hull points, the worst hull's
     per cent and, while gear wear bites, the gear and its price. It is lifted out of `cmd.do_repair`, which now reads it.
   - `cmd.standing_route_lines` writes `REPAIR` at a marked stop only when something is due, as it writes `PROVISION` only
     below the keep level. This holds for players' routes too.

**Hunks:** 18, in 8 live bodies: `npc_plan` (5), `npc_tend_route` (3), `npc_tend_sum` (1), `npc_tend` (1, comment),
`npc_leg_lines` (1, comment), `npc_buy_ceiling` (1), `cmd.standing_route_lines` (4), `cmd.do_repair` (2). Each is asserted
to occur once, each body reverses to its pre-image, and every ACL is unchanged. **All 18 occur exactly once in prod's live
bodies** (read-only check, scratch `prodcheck.mjs`). One new function: `public.fleet_repair_due`, server-only.

**Self-assert receipt** (head-0180 image):

> (i) WAIT: nothing paying on any of her 11 loop(s), her lap-start plan laid her up DOCKED at her stop 0, no lap opened,
> no order written, one ROUTE_PAUSED; the tend kept her waiting without writing it twice and the arrivals path opened
> nothing; one unit aboard, the tend resumed her (positive control). (ii) REPAIR: sound, no REPAIR written (the old
> renderer wrote one) and do_repair still refuses E_UNAVAILABLE; one hull at half, REPAIR written, 900 points due = 900
> by hand, worst 50 %, do_repair mended 900. (iii) LIMIT: BUY anise stored AT 0.01 — the old renderer wrote AT 0.01, the
> new one AT 63.35 (ask 48.73, her patience 0.3 over the ask now = 63.35, her next stop lets her pay 336.38).

The probes touch one merchant's own rows. They set their own preconditions inside blocks that roll back whole:
`npc_buyers_per_good` 0 so nothing pays anywhere; gear wear dark; her fleet docked and empty; her stop 0 marked for repair.

## 3. Proved on prod-shaped data (local, PGlite)

Scratch `lapsim.mjs` (in `~/dev/bv-laps-scratch`) loads the head-0180 world image and then:

- sets prod's 215 knobs (read-only export at 09:27), lit treasury, merchants and routes on;
- loads prod's 1,996 off-target maker stocks, 821 merchant purses, 238 city purses and all 837 merchant loops (written
  through `cmd.standing_route_save_for`);
- docks every merchant fleet, empty, at her stop 0 at a lap start, and starts them all (`cmd.advance`, so every lap start
  runs the real `npc_plan`);
- runs the real arrivals sweep every 15 s, the market drift every 10 min and one hourly tend (`call tick_reconcile()`)
  at the half, in real time.

Two arms ran side by side on one machine: **old** (head 0180) and **new** (0181 applied). The first run was 30 min, the
second 45 min. The second run counts only laps that STARTED after the opening burst: the opening laps carry no parcel in
from a previous lap (a lap closes at stop 0 before stop 0's SELL), so they read low in both arms.

| | old (0180) | new (0181) |
|---|---|---|
| lap starts at the opening burst | 837, **336 with no BUY (40.1 %)** | 542, **0 with no BUY**; 295 waiting in port |
| laps closed (45-min run, after the burst) | 268 | 181 |
| **planned no BUY** | **70 (26.1 %)** | **19 (10.5 %)** |
| empty (bought 0, sold 0) | 55 (20.5 %) | 9 (5.0 %) |
| **closing ≤ 0** | **108 (40.3 %)** | **52 (28.7 %)** |
| mean / median net | 687 / 214 | 828 / 302 |
| **merchant working capital gained** (purses + cargo at cost, the tend's own transfers excluded) | **+1.279 M** | **+1.371 M (+7 %)** |
| BUY orders done / refused E_PRICE_LIMIT | 2,172 / 77 | 2,324 / 72 |
| REPAIR refused E_UNAVAILABLE | **1,223** | **0** (REPAIR done 57 → 26: fewer laps) |
| arrivals sweep, avg / p95 / max (PGlite, both arms on one CPU) | 2,750 / 6,276 / 7,948 ms | **1,651 / 4,124 / 6,280 ms (−40 %)** |
| the hourly tend (`tick_reconcile`) | 6.6 s | **38.5 s** |
| at the end: laid up / paused for an error / docked idle | 0 / 0 / 0 | 93 / 0 / 0 |

The 30-minute run agreed. Counting every lap there, closing ≤ 0 fell from 73.1 % to 51.5 %, planned no BUY from 52.0 % to
6.3 %, and empty laps from 256 to 11. The sweep fell from 2,029 to 1,227 ms.

**No merchant is stranded.**

- At the tend, **220 of the 301** waiting merchants (73 %) were re-planned onto a paying loop and resumed: 301 → 81 laid
  up. In the 30-minute run it was 241 of 301.
- The rest were re-planned and stay laid up until a later tend finds a loop that pays.
- Nothing ended paused for an error, and no fleet lay docked with neither a lap nor a pause.
- The waiting state is the one the client already shows ("Laid up").

**The price paid — the hourly tend.**

- In PGlite, re-planning ~300 waiting merchants made the tend 38.5 s instead of 6.6 s (≈ 106 ms a plan, the same as a
  lap-start plan in the sweep).
- Those plans used to run in the 15-second sweep, once per empty lap. They now run once an hour in the tend, which runs
  one transaction per merchant under its own 60 s budget (`npc_upkeep_budget_seconds`; a route not reached is deferred
  to the next hour).
- Prod's reconcile took 13.7 s in the hour to 09:16. If a prod plan costs what a PGlite plan does, it rises by up to
  ~30 s. That is inferred, not measured on prod.
- **Watch `byeharu-voyage:reconcile` after deploy.**

## 4. Prod, read-only, before handing back

- Head **20260818000180**, so this file is 0181.
- All 18 hunks' old texts occur **exactly once** in prod's live bodies (`prodcheck.sql`).
- **The probes' selections, read-only:**
  - the probe merchant is the roster's first two-stop route, Carreira da Índia (3 hulls at 1,800 / 1,800, SAILING on a
    lap: the probe docks her itself);
  - her LIS → LAG leg offers anise;
  - the first shipyard harbour is ACA;
  - the knobs the probes set exist: `npc_buyers_per_good` 3, `gear_wear_bite` false, both switches true;
  - 0 `PROBE_0181` ledger rows, and no `fleet_repair_due` yet.
- The file passed on the head-0180 image and on the prod-shaped world with every merchant docked, every one SAILING and
  every one laid up. After the last edit (the lay-up sentence) it was re-run on the SAILING shape and in the build.

## 5. NOT the owner's — confirm

- **The wait.**
  - Waiting replaces 0115's "a merchant is never parked" only for an empty-handed lap start where no loop on offer pays.
  - She is re-planned at each hourly tend, not at every market drift.
- **The ceiling.** Her patience is measured from the ask now, not from the port's target stock. At a drawn-down maker she
  pays up to her patience over today's ask, still bounded by what her next stop pays.
- **REPAIR.** No REPAIR line is written for a fleet with nothing to mend, on players' routes too. A player who marks a
  stop for repair no longer sees "nothing aboard needs repair" on a sound lap.

## 6. Verify (once each; worktree `~/dev/bv-laps` off main `5b34bba`, real `npm ci`, the main clone's `node_modules/.cache` plus bv-flaky's p0171/p0172 prefix snapshots, no `.env.local`)

- **Cached-prefix build** (`BYEHARU_PREFIX_CACHE=required npm run build`):
  - restored 172/173 from `browser-p0172`, applied 1 (0181);
  - world-guard ok, image certified;
  - tsc + vite built in 17.0 s.
- **`npx tsc -b`** clean, **`npx eslint .`** clean, **`db:check-versions`** 173 distinct, no collisions.
- **Proofs on the built image** (scratch `proofs-on-image.mjs`, `scripts/db/proof.mjs`'s marker, rollback and digest loop):
  **12/12 files, 85/85 PASS markers**, proof 12 (merchants) included. Proof 12 accepts a laid-up merchant only by the
  sentence "No cargo pays …", so 0181 keeps that wording.
- **Pure specs** `duplication.spec.ts` + `flags.spec.ts`: 12 passed, 3 skipped (browser halves; CI runs them).
- **CI selection** (`scripts/ci/select-specs.mjs`):
  - SCOPED, 20 specs;
  - pglite-gate legs: the rest, ledger, merchants;
  - growth test deferred to main; no from-zero.

## 7. PR #217 CI (runs 39122042382 + 39122042422, about 13 min wall-clock)

| check | result |
|---|---|
| select | pass (6 s) — SCOPED |
| build | pass (1 m 16 s) |
| disposable-chain | pass (2 m 30 s) — restored the 172-file snapshot, applied 0181 on real Supabase; no from-zero |
| pglite-gate (merchants) | pass (2 m 37 s) |
| pglite-gate (the rest) | pass (4 m 41 s) |
| pglite-gate (ledger) | pass (12 m 45 s) |

**Not merged and not pushed to the database.** Deploy with `~/bin/bv-deploy.sh 217` (prod head must still be 0180), then
watch `byeharu-voyage:reconcile` and `:arrivals` in `cron.job_run_details`, and the laps closing ≤ 0.
