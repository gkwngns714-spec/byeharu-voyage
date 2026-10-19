# 2026-10-19: a review prices eight loops (migration 0205, `osn-arrivals-fast`)

0203 and 0204 went live back to back at 01:21 UTC. Afterwards the arrivals sweep (`byeharu-voyage:arrivals`, every 15 s, bound avg ≤ 3 s, p95 < 5 s) read 3.45 s avg and 5.47 s p95 (01:22–01:52), against 2.2–2.6 s before.

## 1. Where the time went (prod, read-only)

Every function called was provolatile `s`, inside `begin transaction read only … rollback`.

- **`pg_stat_statements` cannot attribute this.** It is on, but `track = top`, so it records only `select public.tick_arrivals()` (94,619 calls, mean 1,073 ms). Nested functions are not counted. `cron.job_run_details` returns only `1 row`.
- **The load did not move:**

| | before 01:21 | after |
|---|---|---|
| voyages at sea (00:00 / 00:30 / 01:00 / 01:15 → 01:25 / 01:35) | 662 / 723 / 702 / 730 | 729 / 747 |
| mean voyage, nm | 3,869–3,994 | 3,919–3,921 |
| ROUTE_LAP per 10 min | 83–100 | 120 (01:20) |
| VOYAGE_REPORT per 10 min | 247–286 | 294 |

- **The settle side is not the cost on prod:**
  - the tick's candidate scan takes 76 ms (EXPLAIN ANALYZE, stable functions only);
  - `voyage.delay_before_day` reads `voyage_events` through its primary key (voyage_id, day_index), about 15 rows a voyage;
  - `voyages.delay_hours` equals `delay_before_day(v, last_settled_day + 1)` for all 775 sailing voyages.
- **The cost per lap start rose.** `standing_routes` rewrites went from 124 / 129 per 10 min to 225. 0203 taught every harbour its remembered legs, so a review prices about 15 loops instead of about 7.
- **It is not the fight.** 0200 alone measured 2.42 s lit against 2.32 s dark. Raids are fewer than 30 events in the 50 minutes read.

## 2. The levers, measured

**Harness:** the 0204 world image with `redesign-scratch`'s setup, refreshed from prod at 01:39 UTC: stocks, purses, treasuries, 837 loops and 234 knobs. Scripts: `bv-harness/arrfast/lever.mjs`, `chosen.mjs`, `sim.mjs`.

**One review at a lap start, 250 merchants, each reviewed:**

| variant | ms a plan (p95) | loops priced | switched | gain of the switches, d./h | wait |
|---|---|---|---|---|---|
| `npc_route_candidates` 16 (prod) | 291 (374) | 15.1 | 194 | 11.02 M | 3 |
| **candidates 8** | **189 (244)** | 8 | 174 | **10.95 M (99.4 %)** | 5 |
| neighbours 3, candidates 10 | 246 (314) | 9.9 | 181 | 10.50 M | 5 |
| neighbours 3, trade 4, candidates 8 | 192 (249) | 8 | 180 | 10.42 M | 3 |
| neighbours 2, trade 5, candidates 8 | 200 (252) | 8 | 169 | 9.92 M | 3 |
| neighbours 2 (candidates 16) | 254 (330) | 10.2 | 171 | 9.95 M | 2 |
| neighbours 1 | 188 (232) | 7.9 | 153 | 9.40 M | 7 |

**What wins at 16.** Of 194 switches:
- 178 go to a trade loop (114 of them among the first seven offered);
- 12 go to a three-stop loop;
- 4 go to one of the 1,141 near out-and-backs offered.

**The sweep, 20 minutes paired on the same world** (all sweeps, then the last 10 minutes):

| | avg | p95 | last 10 min avg | last 10 min p95 | laps ≤ 0 | lay-ups at the end |
|---|---|---|---|---|---|---|
| base (16), pair 1 | 2,022 | 4,023 | 2,186 | 4,023 | 41 / 125 (33 %) | 120 |
| **0205 (8), pair 1** | **1,589** | **3,222** | **1,823** | **3,302** | 73 / 142 (51 %) | 146 |
| base (16), pair 2 | 2,161 | 4,555 | 2,437 | 4,555 | 44 / 129 (34 %) | 114 |
| 8 + trade loops priced first (npc_plan hunk), pair 2 | 1,694 | 4,294 | 2,005 | 4,955 | 83 / 152 (55 %) | 146 |

- **Projection for prod:** 3.45 s × 0.83 ≈ 2.9 s avg, and 5.47 s × 0.82 ≈ 4.5 s p95.
- **The trade-first hunk bought nothing,** so it is not in 0205.
- **The cost is real and consistent in both pairs.** At 8:
  - about 30 more merchants of 837 lie laid up;
  - more short laps close at or under nothing in the 20-minute window. Most of them sold nothing within the lap: 67 / 74 against 35 / 37.
  - 0203's "laps ≤ 0, 55 % → 36 %" is not held in this window.
- **The owner judges the trade.** The way back is in the file header (`npc_route_candidates` 16).

## 3. Self-assert (prod-shaped, applied after the setup as prod will apply it)

> 0205 self-assert ok: A REVIEW PRICES EIGHT LOOPS — npc_route_candidates 8. COMPTOIR CHASTELLAIN (Voyage Hamburg; review lap): LEH-LUB — net 2038 a lap, 1 BUY, 0 legs refused after PROVISION, sailing. THE ROSTER'S FIRST 20: 0 written a loop the door refuses, 0 laid up; 258 ms a plan at 16 → 157 ms at 8 (0 busy, skipped).

At 16, the same review wrote Chastellain LEH-COP-LUB at +3,300 a lap.

## 4. What is left

The sweep's cost is still per leg priced. `npc_leg_lines` runs about 11 ms a leg in PGlite, and each plan re-prices legs that the merchant before her priced on the same market. A memo across one sweep would cut that cost without changing any choice. It was not built here.

## HAND-OFF (coordinator, 2026-10-19 ~03:20 UTC): the owner moved to another PC, and the agent was stopped mid-work
- **Measured:** knob-only `npc_route_candidates` 16 → 8. The paired sim gave sweep time ×0.83, but laps ≤ 0 went 33 → 51 %, median net +73 → 0, and lay-ups 120 → 146. **Do NOT ship the knob alone.**
- **In progress:** one `npc_plan` hunk that prices the trade loops (ranked by `port_goods.haul`) FIRST, then the near loops, capped at 8. Check whether the migration file in this commit already carries that hunk or only the knob before using it.
- **Left to do:**
  1. finish or verify the hunk;
  2. re-run the paired sim (harness `scripts/ops/harness/sim/`) against a fresh prod-shaped base;
  3. ship only if the sweep is ≤ 3 s projected AND laps ≤ 0 is not worse;
  4. open the PR and deploy with `~/bin/bv-deploy.sh`.
- **Not urgent:** prod arrivals eased by themselves to 2.6–2.8 s (bound 3 s) after the 01:22–01:52 window.
