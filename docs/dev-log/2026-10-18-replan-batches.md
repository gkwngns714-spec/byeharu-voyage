# 2026-10-18 — a waiting merchant is asked in turn (migration 0182, `osn-replan-batches`)

**The problem.** 0181 lays up a merchant who has no paying loop and re-plans every laid-up merchant in the hourly
reconcile (`byeharu-voyage:reconcile`, 60 s route budget). The reconcile went from 12–14 s to **57.4 s (12:07)** and
**62.0 s (13:07)**.

**The order (relayed from the owner, mid-slice).** Re-check every laid-up merchant about every **10 minutes**, the
market's drift slot, in bounded batches, round-robin by last-checked time. Keep the reconcile at ≤ ~20 s and the
arrivals sweep at avg ≤ 3 s and p95 < 5 s. If 10 minutes does not fit, report the fastest cadence that does.

## 1. Where the 57 s went (prod, read-only, 12:13–13:35 UTC, head 0181)

Every query ran inside `begin transaction read only; … rollback;` through `supabase db query --linked`. Each function
called is `provolatile` `s` or `i`.

| reconcile run (UTC) | seconds |
|---|---|
| 07:07–11:07 (before 0181) | 12.41, 14.26, 13.66, 12.92, 12.24 |
| 12:07 (first after 0181) | **57.36** |
| 13:07 | **62.03** (over the 60 s route budget) |

- `cron.job_run_details` keeps no receipt; `tick_reconcile` reports through a notice only. So the split comes from the rows
  the run left behind:
  - **12:07:** 225 `ROUTE_PAUSED 'laid_up'` events (192 routes) between the first lay-up at 11:35 and 12:07. 75 routes
    were still laid up with `updated_at` 12:07:00–12:07:58, so they were re-planned and laid up again. About 117 resumed:
    `DEPARTED` was 182 in the 12:07 minute, against 29–35 in every other minute. The re-plans cost ≈ 57.4 − ~13 = **44 s
    for 192, ≈ 230 ms each**.
  - **13:07:** 220 more lay-ups between 12:08 and 13:07, so ~295 were waiting. 179 were re-planned and laid up again,
    and `DEPARTED` was 158 in that minute. ≈ 62.0 − ~12.5 = **49.5 s for ~295, ≈ 170 ms each**.
- The laid-up count does not drain. It was 100 at 12:14, 277 at 12:48, 183 just after 13:07 and 276 at 13:35.
- The arrivals sweep got lighter after 0181: avg 3.0–3.3 s per 15-minute window before it, **2.06–2.52 s** after;
  p95 3.2–3.6 s.

**Prod-shaped PGlite** (`measure.mjs`: the head-0180 image + 0181, prod's knobs, stocks, purses, treasuries and 837
loops, every merchant docked at stop 0 at a lap start; the kickoff lays up 295). The reconcile's route steps, timed one
by one:

| merchants | n | total | each |
|---|---|---|---|
| laid up, re-planned, laid up again | 292 | 17.1 s | 58 ms |
| laid up, re-planned, resumed | 3 | 0.3 s | 111 ms |
| every other merchant | 542 | 1.6 s | 3 ms |

The companies' step, the compactor and the invariants took 0.36 s together. **The re-plans are 91 % of the reconcile.**
Prod runs a re-plan ~3–4× slower than PGlite (170–230 ms against 58 ms).

## 2. The migration (0182, `a_waiting_merchant_is_asked_in_turn`)

1. **The queue: `public.npc_waiting_queue(now)`**, stable and server-only. It lists every laid-up merchant with:
   - her **last ask**: the later of her route's `updated_at` (every plan saves through the save door, which dates it)
     and the new `npc_fleets.asked_at` (stamped by the sweep, so a plan that fails is not asked again at once);
   - when she is **due**: last ask + `npc_replan_every_minutes` (**10**, the drift slot);
   - whether she is **overdue**: last ask ≥ `npc_replan_within_minutes` (**60**) ago.
2. **The sweep asks them in turn: `public.npc_ask_waiting(now, until)`**. It runs at the end of `tick_arrivals`, after
   every arrival, yard release and wake.
   - It takes the due merchants longest-waiting first (round-robin by last ask), SKIP LOCKED.
   - It stamps each one and puts her through `public.npc_tend_route`, THE per-merchant upkeep: re-plan from where she
     lies, then resume on a loop that pays or wait.
   - It begins a merchant only while the batch has run < `npc_replan_sweep_ms` (**600**) and asked fewer than
     `npc_replan_per_sweep_max` (**12**), inside the sweep's own 10 s budget.
   - Whoever is not reached stays due, first in line for the next sweep.
   - If the batch raises, it is rolled back alone and warned, and the sweep's arrivals still commit.
3. **The reconcile asks only the overdue.** `tick_reconcile` skips a laid-up merchant who is not overdue (counted
   `waiting`). It re-plans an overdue one as before, so whatever the sweeps did not reach within the hour is still
   carried to the hour.

**Hunks:** 5, in 2 live bodies: `tick_arrivals` (2) and `tick_reconcile` (3). Each is asserted to occur once, each body
reverses to its pre-image, and every ACL is unchanged. **All 5 occur exactly once in prod's live bodies** (read-only,
13:35 UTC). New: two server-only functions (added to `rpc.surface.spec`'s server-only list), one nullable column and four
knobs.

**Self-assert receipt** (head-0181 world):

> Laid up at her lap start (nothing paying), she is in the queue, due in 5000000 min (the probe's
> npc_replan_every_minutes), not overdue — the hour skips her. Aged ten years she is due and first in line: the sweep
> asked her (119 ms), re-planned her, she waits again, stamped, the lay-up not written twice; then not due, not overdue,
> and the next ask passed her by. Past the promise she is overdue — the hour asks her (positive control). One unit
> aboard, the ask resumed her (positive control). Bodies reverse, ACLs unchanged.

**The probe stays on its own rows.**

- It uses one merchant: the roster's first two-stop route.
- Inside a block that rolls back whole, it sets `npc_buyers_per_good` 0 (nothing pays), `npc_replan_per_sweep_max` 1 and
  `npc_replan_every_minutes` ~9.5 years. With that cadence no real merchant is due, only her (aged ten years).
- The asserts count only her row.

## 3. Proved on prod-shaped data (PGlite, real time, 40 minutes)

Three arms ran side by side (`sim.mjs`), each on the same prod-shaped world with 295 laid up at the kickoff. Each ran the
real arrivals sweep every 15 s, the drift every 10 min, and `call tick_reconcile()` at +20 and +37 min.

- **old:** 0181.
- **new:** 0181 + 0182 at the defaults.
- **new170:** 0182 with `npc_replan_sweep_ms` 170, which approximates prod's slower re-plan (a 600 ms batch on prod asks
  about what a 170 ms batch asks on PGlite).

**Contention warning.** The three arms shared one CPU, and the 0182 build and the proofs ran during the first ~20 min. So
the absolute sweep times are inflated in every arm. The old arm's p95 was 8.1 s with no batch in it at all. Compare the
arms with each other, not with prod.

| | old (0181) | new (0182) | new170 (prod pace) |
|---|---|---|---|
| **reconcile at +20 min** | **61.0 s, 74 routes deferred** (re-planned 256: 214 resumed, 42 waiting) | **14.6 s**, 0 deferred (164 waiting skipped) | **13.8 s**, 0 deferred (252 skipped) |
| reconcile at +37 min | 28.5 s | 6.2 s | 5.8 s |
| sweep avg / p95 / max, whole run (contended) | 2,790 / 8,092 / 10,281 ms | 3,451 / 8,927 / 10,609 ms | 2,727 / 7,247 / 10,431 ms |
| waiting merchants asked by the sweeps | 0 | 413 (≤ 11 a sweep) | 183 (≤ 4 a sweep) |
| laid up, kickoff → end | 300 → 66 | 300 → 57 | 300 → 162 |
| **oldest last ask ever seen** | 38.1 min (until the hour came) | **27.4 min** (the kickoff burst); **9.1–9.9 min** at +34–37 | 41.4 min (still draining the burst at the end) |
| laid-up merchant ≥ 60 min since her last ask | **0** at every sweep | **0** at every sweep | **0** at every sweep |

**What this shows.**

- **The reconcile:** 61 s (over budget, routes deferred) → **14 s**, under the ~20 s target, in both 0182 arms.
- **The guarantee:** in no arm was any waiting merchant ever 60 minutes past her last ask.
- **The cadence is set by the load.**
  - At PGlite pace the 600 ms batch drained the 300-merchant kickoff burst in ~17 minutes and then held every waiting
    merchant at **≤ 10 minutes** since her last ask (oldest 9.1–9.9 min at +34–37 min).
  - At prod pace (new170, ≤ 4 asks a sweep, ~14 a minute) 300 waiting is more than 10 minutes can hold. The cadence
    stretches toward P ÷ 14 a minute, and the burst was still draining at 40 min.
- **What the batch costs a sweep:** new − old = +660 ms avg (≈ the 600 ms budget plus one re-plan's overrun). new170 −
  old = −63 ms, which is noise. Under contention that is the only clean number: **the batch adds at most
  `npc_replan_sweep_ms` + one re-plan to a sweep.**

## 4. What prod should do (inferred, not measured on prod)

- **Arrivals:** prod's sweep is avg 2.06–2.52 s and p95 3.2–3.6 s with 0181. While waiting merchants are due, the batch
  adds ≤ 0.6 s + one re-plan (170–230 ms). That gives **avg ≈ 2.9–3.3 s worst-case** while the batch is saturated, and
  **p95 ≈ 4.0–4.4 s** (< 5 s).
  - The batch is saturated whenever P > ~150 at a 10-minute cadence, and prod's P has been 180–300.
  - The avg ≤ 3 s target is at the edge. If the first hours measure above 3.0 s, lower `npc_replan_sweep_ms` to 450.
    That is a knob update, not a migration.
- **Cadence:** a 600 ms batch on prod asks ~3–4.5 merchants a sweep, ~12–18 a minute. **Measured cadence on prod-pace
  data:** 10 minutes holds for up to ~120–180 waiting merchants; with prod's 180–300 it is **~10–25 minutes**. That is
  the fastest cadence inside the avg-3 s budget: a 10-minute cadence at 300 would need ~30 asks a minute ≈ 1.3 s a sweep
  on prod, so avg ≈ 3.6 s.
- **Reconcile:** back to ~12–14 s on prod (the non-waiting work it did before 0181), plus any overdue merchants. There
  should be none while the sweep runs.
- **Watch after deploy:** `byeharu-voyage:reconcile` ≤ 20 s; `:arrivals` avg and p95 per 15 min; the laid-up count and
  `max(now − greatest(updated_at, asked_at))` over laid-up routes.

## 5. NOT the owner's — confirm

- `npc_replan_sweep_ms` 600 is the trade between the cadence and the sweep's avg; raising it shortens the first and
  lengthens the second by as much.
- A merchant whose plan fails is asked again 10 minutes later, not at every sweep.

## 6. Verify (once each; worktree `~/dev/bv-replan` off main `440dfb8`, real `npm ci`, the main clone's `node_modules/.cache`, no `.env.local`)

- **Cached-prefix build** (`BYEHARU_PREFIX_CACHE=required npm run build`): restored 173/174 from `browser-p0173`, applied
  1 (0182), world-guard ok, image certified, built in 16.3 s.
- **`npx tsc -b`** clean. **`npx eslint .`** clean. **`db:check-versions`** 174 distinct, no collisions.
- **Proofs on the built image** (`proofs-on-image.mjs`): **12/12 files, 85/85 PASS markers**, proof 12 (merchants) and
  02 (ledger) included.
- **CI selection** (`scripts/ci/select-specs.mjs`): SCOPED. pglite-gate legs: the rest, ledger, merchants. Merchants-on
  world built. Growth test deferred to main. No from-zero.
- **Prod, read-only, before handing back:**
  - head 20260818000181;
  - all 5 hunks once;
  - no `npc_waiting_queue`, `npc_ask_waiting`, `npc_fleets.asked_at` or replan knob yet;
  - the probe merchant is Carreira da Índia (2 stops, LIS, 3 hulls, SAILING: the probe docks her itself);
  - `npc_buyers_per_good` 3 and both switches true.
