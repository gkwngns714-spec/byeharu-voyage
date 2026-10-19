# 2026-10-19: a leg reads its quays once (migration 0209, `osn-arrivals-cache`)

The arrivals sweep (`tick_arrivals`, every 15 s; bound avg ≤ 3 s, p95 < 5 s) runs 2–3 s on prod. 0207-the-first (fewer loops) made laps worse and was parked (`2026-10-19-arrivals-fast.md` § 5). Its § 4 suggested the next lever: cache each leg's price for one sweep, so that no merchant's choice changes. This file measures that idea, finds it does not pay, and ships the cut that does. That cut also changes no choice.

## 1. Where a leg's time goes

**PGlite (prod-shaped kickoff, 300 merchants, 2,447 legs):** time spent in each section of `npc_leg_lines`.

| section | total ms | avg ms a leg |
|---|---|---|
| the other merchants' buyers at the harbour (one query) | 17,264 | 7.1 |
| the ranking (`world.trade_routes`, from → to) | 10,579 | 4.3 |
| the parcels' quotes (size, the purse's walk, buy, sell + tax, ceiling) | ~8,900 | ~3.6 |
| the day caps | 1,868 | 0.8 |
| the rest | ~1,600 | ~0.6 |

**Prod (read-only; every function called was provolatile `s`):**

- `world.trade_routes` for one leg: 13.75 ms (120 calls in one session, steady).
- One `world.quote`: 1.8 ms. Of that, 1.2 ms is its quay's terms (`world.quote_terms`: the spread, the spread with no bargain, the tax, and the city's bid factor). A leg asks about 8 quotes at its two quays, and each quote re-read the same four figures.
- The buyers query: 2.9 ms. It is a sequential scan of every stop of every route (2,710 rows) to find the stops at one harbour.
- The bodies of `npc_leg_lines`, `npc_affordable`, `npc_buy_ceiling`, `trade_routes`, `quote_priced` and `quote_terms` on prod are byte-identical to the chain's (md5 of `pg_get_functiondef`).

## 2. A cache across one sweep does not pay (measured, not built)

**The method.** I logged every ranking `npc_leg_lines` asks in the paired sim, with an exact-input version key:
- the `(ctid, xmin)` of every row the ranking reads (port_goods for the source's goods at both quays, specialties, goods, both ports, both reach rows, world_config);
- the two quays' spread, bid factor and tax.

**The kickoff, then 32 sweeps:**

| | rankings | repeats in the SAME sweep with the same key | repeats in ANY earlier sweep |
|---|---|---|---|
| sweeps | 1,015 (11,392 ms) | **62 (6 %), 903 ms** | 592 (58 %), 6,672 ms |

- **The key cost 3,154 ms.** That is 3.5× what the same-sweep repeats would save. So a sweep-scoped memo makes the sweep slower.
- **The key is complete.** No key ever had two different answers.
- A cache that outlives its sweep would need a persistent table: a second copy of the market. Not built.
- **On prod, the key costs about 4.5 ms against a 13.75 ms ranking.** Most of it is the spread and bid factor (2 ms). Those are the same four terms every quote re-reads, which points to the cut below.

## 3. What 0209 does (no rule moves)

1. `npc_leg_lines` reads `world.quote_terms(p_from)` and `world.quote_terms(p_to)` ONCE a leg. It hands them to every quote of the leg through `world.quote_priced`, as `world.trade_routes` has done since 0169.
   - With no fleet named, a quote's terms are the quay's: the same for every good, size and side (0169).
   - The leg writes nothing between its quotes.
2. `npc_affordable` and `npc_buy_ceiling` take the four terms as optional trailing arguments (default null).
   - If they are not handed over, the quote reads its own. `world.quote` IS `quote_priced` with the four terms null.
   - Other callers (`cmd.standing_route_lines`) are unchanged.
   - Each function is dropped and created. Its ACL is restored and asserted: `{postgres=X/postgres,service_role=X/postgres}` on prod.
3. A new index, `standing_route_stops_port`, on `standing_route_stops (port_id)`, for the buyers count.

**Concurrency, stated plainly.**
- On prod, a player's trade can commit at one of the leg's two quays during the few milliseconds the leg is priced. Before 0209, a later quote in that leg would have seen the new bid factor; now the whole leg uses the terms read at its start.
- This is the same read-once rule `world.trade_routes` already follows.
- In the sim (no concurrent writers) the plans are identical. See § 4.

## 4. Proof

**Self-assert** (on the chain's own world and on each sim world):
- every leg is priced by the new body and by the pre-image: 80 legs of a probe company (Lisboa ↔ its 40 nearest harbours) and the legs of the roster's first 20 merchants;
- they must be byte-equal, and some must carry a parcel (otherwise the proof is vacuous);
- a negative control (one hunk handing the source's spread to a sale) FAILS it: 24 of 80 probe legs and 32 of 62 roster legs differ.

**The paired sim** (`scripts/ops/harness/arrfast`):
- Both arms of a pair run side by side from the same prod-shaped world and the same kickoff (all 837 merchants at a lap start). Each runs 20 minutes of real-time sweeps.
- "Plans after the kickoff" compares each merchant's written stops, lines and pause between the two arms.
- After that, the windows differ only by timing: the faster arm reaches each sweep's merchants at a different moment, so the markets they meet differ.

Pair 1 ran on the 0205 world, pair 2 on 0207 (×10 market depth), and pair 3 on 0208 (holds ×3, prices ×0.2, haul premium ×0.5), the prod head. Each pair used a fresh read-only export of prod's state.

| world | arm | kickoff | sweep avg / p95 ms | last 10 min avg / p95 | laps ≤ 0 | median lap net | lay-ups at end | plans after kickoff |
|---|---|---|---|---|---|---|---|---|
| 0205, pair 1 | base | 397 s | 4,124 / 10,119 | 5,615 / 12,082 | 32 / 76 (42 %) | 26 | 96 | — |
| 0205, pair 1 | **0209** | 226 s | **3,005 / 10,096** | 4,180 / 10,241 | 33 / 76 (43 %) | 26 | 94 | **837 of 837 identical** |
| 0207, pair 2 | base | 490 s | 5,039 / 10,365 | 5,574 / 10,705 | 35 / 114 (31 %) | 60.5 | 36 | — |
| 0207, pair 2 | **0209** | 238 s | **3,531 / 8,757** | 4,183 / 8,815 | 33 / 103 (32 %) | 47 | 29 | **837 of 837 identical** |
| **0208 (prod head), pair 3** | base | 616 s | 3,220 / 10,057 | 2,807 / 6,537 | 49 / 154 (32 %) | 65 | 98 | — |
| **0208 (prod head), pair 3** | **0209** | 303 s | **2,550 / 6,269** | 2,178 / 4,923 | 47 / 144 (33 %) | 59 | 92 | **837 of 837 identical** |

- **The sweep, on the prod-head world:** avg ×0.79 and p95 ×0.62. Across the three pairs the avg is ×0.70–0.79. The kickoff (837 lap starts) is about ×0.5 in every pair.
- **Plans:**
  - Every merchant's plan after the kickoff is identical in every pair.
  - The SHADOW run (§ 4a) prices every leg of the 20-minute window with both bodies in the same state, and finds no difference.
  - So the windows' lap figures differ by timing, not by choice: laps ≤ 0 within a point (42/43 %, 31/32 %, 32/33 %), lay-ups at the end fewer in every pair (96 → 94, 36 → 29, 98 → 92). The median lap net moves both ways with the window (26 = 26, 60.5 → 47, 65 → 59): fewer laps close in the faster arm's window, and the set that closes differs.

**Repeated calls in one session** (a generic plan can fall off a cliff after about 5 calls; 0205 did):
- **The test:** `npc_leg_lines` (3 roster legs), `npc_affordable` and `npc_buy_ceiling`, old and new, each called 12 times on the same arguments in one PGlite session (0208 chain + 0209), under each `plan_cache_mode`.
- **Default (`auto`):** no cliff. New leg times run 22.9–31.5, 12.3–13.8 and 13.1–22.1 ms against old 23.6–28.3, 12.5–17.3 and 14.9–25.0 ms. `npc_affordable` takes 0.8–0.9 ms (old 1.0–1.7), `npc_buy_ceiling` 0.9–1.1 ms (old 0.6–1.0).
- **`force_generic_plan`:** steady. New legs 20.1–21.9 ms (one 35.7 outlier), 12–15 ms, and 13–24 ms.
- **`force_custom_plan`:** about twice as slow for both bodies (leg 37–63 ms). So 0209 does NOT force custom plans. The default (auto) is steady past the fifth call.
- **In the self-assert** (80 probe calls in one session): the first 6 calls average 27.8 ms and the last 6 average 30.5 ms on the 0208 world. That is flat.

### 4a. Shadow run
`scripts/ops/harness/arrfast/shadow.mjs`, on the 0208 world, for 20 minutes:
- The run is the 0209 arm with `public.npc_leg_lines` wrapped. Every leg any plan prices is priced by the pre-image AND the new body, in the same state, one call after the other.
- **Kickoff:** 11,250 legs compared, 0 differ (5,454 with a parcel).
- **The 80 sweeps after it:** 2,572 more legs, 0 differ. In all: **13,822 legs, 0 differences, 6,491 with a parcel.**

## 5. Left
- The ranking (`world.trade_routes`, 13.75 ms a leg on prod) is now the largest cost of a leg. It repeats across sweeps (58 %) but not within one (6 %).
- `cmd.standing_route_lines` (the live renderer at each arrival) still asks `npc_affordable` and `npc_buy_ceiling` without terms. It could read them once a stop the same way.

## HAND-OFF (2026-10-19 ~08:45 UTC, the owner moved PCs; agent stopped)
- **Done:** migration 0209 built. Self-assert passes on the 0205, 0207 and 0208 worlds, and the negative control fails it. Three paired sims and the shadow run are in § 4. PR **#267** is open.
- **Measured:** on the 0208 (prod head) world, sweep avg 3,220 → 2,550 ms and p95 10,057 → 6,269 ms. All 837 plans after the kickoff are identical. The shadow run found 0 differences in 13,822 legs. Lay-ups at the end 98 → 92, laps ≤ 0 32 → 33 %.
- **CI on #267:** every check passed except `acceptance-shard (3/3)` and its `acceptance` roll-up (red). Its log was NOT read: the run was still in progress when logs were asked for.
- **Next step:**
  1. Read shard 3's log to its last error: `gh run view 39221616499 --job 117958077277 --log`.
  2. If the red is unrelated (a UI spec; 0209 changes no client code), re-run it once as a diagnostic and record why.
  3. Remove the NOT FOR DEPLOY line from the migration header.
  4. Deploy with `~/bin/bv-deploy.sh 267` (renumber to the prod head + 1 if 0209 is taken).
- `.arrwork/` (the prod export) is deleted.
