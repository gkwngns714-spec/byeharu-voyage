# 2026-11-02 — 0300: the hour ends in time (the hourly safety net runs again) — first pushed as 0296, reworked after it froze the game clock

**Branch** `reconcile-wall` (PR #453) · migration `supabase/migrations/20260818000300_the_hour_ends_in_time.sql` · deploys AFTER 0299 (the Stats period, live since 20:10 UTC 2026-11-01; 0297, the quiet disk, since 19:38; the numbers 0295, 0296 and 0298
stay unused — `db push` refuses a number below the head; this file was 0296, then 0298, and is 0300 because the Stats period fix took 0299). Owner, 2026-10-31 (row 256, the slowdown): *"FIND THE ROOT, FIX IT. BUT DO NOT CHANGE ANYTHING REGARDING TIME"* — no knob, cron job, schedule or switch moves here.

## 0. What happened to the first push (0296), and the rule it wrote

The first version (then numbered 0296; CI green, 0.9 s there) was pushed to prod on 2026-11-01 at 19:25 UTC (04:25 KST on the 2nd). Its last statement, the self-assert (`do $assert$`), ran into the file's own `statement_timeout = 10min`
(SQLSTATE 57014) at 19:35. `bv-deploy.sh` unwinds the clock first (`unwind_the_clock()`: every cron job paused) and winds it again after the push, so **the game clock stood still for ten minutes**. Nothing was kept — head
0294, `tick_reconcile` the pre-image, the helper absent: on prod the file runs as one transaction.

**Why it was slow.** The probes ran the real hourly steps on real merchants: per case a pg_temp copy of the procedure (OLD, NEW, bare-time, late variants; a second attempt on any difference — ~14 case runs) walked 3 real
merchants and their houses, each running the real `npc_tend_route` (a plan: 0.4–1.1 s warm, 5–10× cold on this disk), `npc_invest_one`, `capital_gift_one` (prod has the traders on, the city treasury on and the economy
closed, so they do real work) and `assert_ledger_reconciles`, plus a digest of the merchant's rows before and after (read-only on prod: ~0.34 s a merchant — her 200 laps 0.10 s, her voyages 0.17 s, the port's goods 0.05 s; the events and ledger probes are index reads). CI's world has
all three switches off and no history, so the same probes took 0.9 s there. And I had set the file's `statement_timeout` to ten minutes "for headroom": that turned a slow self-assert from a fast, clean failure into a freeze.

**The rule, for this file and every migration after it (also in `docs/OPS_HEALTH.md` §4):**
1. `statement_timeout` ≤ 90 s (this file: 60 s — a lower one would be a trap: the "in time" probes below must run inside the hard end the file's own timeout implies, 60 − 25 = 35 s, and they run inside the first second) and `lock_timeout` 5 s,
   set in the FIRST statement: a slow file fails fast and rolls back whole.
2. The whole file ≤ 45 s on prod (this one: ~1 s, §6).
3. A self-assert never executes a real game step or digests live rows: it stubs them, or the proof lives in CI (`scripts/db/proofs/`), and the file SAYS so deterministically — header, this log and a printed notice — in
   every environment alike. No environment switch skips a proof.
4. Its runtime is measured on a POPULATED world (hundreds of merchants, prod-sized history), not CI's tiny one.

## 1. The defect, measured (prod, read-only SELECTs, 2026-11-01 / 02)

`call public.tick_reconcile()` (pg_cron `byeharu-voyage:reconcile`, minute :07, a PROCEDURE with COMMITs between steps) ends in an invariants pass (every player's ledger reconciles,
`voyage.assert_sailing_invariant`, no client write grant). That pass is the LAST thing the call does. The call has one wall: `statement_timeout` = 120000 ms
(`pg_settings`, source `configuration file`; `pg_db_role_setting` has no override for `postgres`), and COMMITs inside a procedure do not reset it.

**Outcomes** — `cron.job_run_details`, which keeps two days (`byeharu-voyage:cron-purge`): 61 runs, 10-30 05:07 → 11-01 18:07 UTC.

| outcome | runs | detail |
|---|---|---|
| succeeded | 28 | 42–110 s; all but a few in 01–09 UTC |
| `canceling statement due to statement timeout` | 31 | 120.0–121.4 s; **29 inside `SELECT public.hold_the_quay()`** — 28 at body line 120 (the merchants' loop) and 1 at line 164 (the investment loop) — 1 at line 140 (the assignment right after a step's COMMIT) and 1 at line 177 (the gift loop's roster, `FOR over SELECT rows`) |
| `job canceled` | 2 | 33 s and 107 s — a different failure (not addressed here) |

By UTC hour, over the three days: 00 0 ok / 2 fail · 01 2/0 · 02 1/1 · 03 1/1 · 04 2/0 · 05–08 3/0 each · 09 2/0 · **10–13 1/2 each · 14 0/3 · 15–18 1/2 each · 19–23 0/2 each**.
Every run from 11-01 10:07 to 18:07 failed (nine in a row; the 09:07 run left no row). The invariants pass therefore did not run in any of them: **the world has gone unchecked for about two days.**

**Receipts** — `public.reconcile_runs` keeps 7 days, but only for the hours that FINISHED (a call that dies writes none):

| window (UTC) | receipts | total s min / med / p90 / max | tend s | companies s | check s |
|---|---|---|---|---|---|
| 10-27 14:07 → 10-28 09:07 | 20 | 34.9 / 62.9 / 82.5 / 108.3 | 14.4 / 29.8 / 51.7 / 63.3 | 4.3 / 5.9 / 9.2 / 10.8 | 1.2 / 4.0 / 4.8 / 5.2 |
| **10-28 10:07 → 10-29 19:07 (healthy)** | 34 | 11.8 / **19.0** / 23.1 / 109.9 (one hour) | 7.4 / 11.5 / 14.3 / 99.4 | 4.2 / 6.7 / 9.5 / 15.0 | 0.2 / 0.3 / 0.6 / 1.6 |
| **10-29 20:07 → 11-01 08:07 (the hours that finished)** | 39 | 38.8 / **71.4** / 102.1 / 113.3 | 29.4 / 53.3 / 73.4 / 84.4 | 3.7 / 20.0 / 28.7 / 41.3 | 0.2 / 0.6 / 1.0 / 1.3 |

Where the time goes (`receipt.quay`, the per-step tally 0267 keeps): the quay wait per tend step was a median **7 ms** (total 5.7 s over 837 steps) in the healthy window and **32 ms** (total 25.4 s
over 800 steps; companies 5 → 20 ms, 2.5 → 11.5 s over ~500 steps) since 10-29 20:07. The longest single wait in a kept receipt: 9.0 s (tend), 4.9 s (companies); the longest hold 2.6 s.
The arrivals beat is I/O-bound now (2–12 s, was 0.7 s; `docs/OPS_HEALTH.md`): every step queues for the quay a whole beat.

## 2. The mechanism (read in the live bodies, not assumed)

- `public.hold_the_quay()` = `pg_advisory_xact_lock(hashtextextended('byeharu.quay_or_upkeep', 249))`, shared with the arrivals beat. In the loops it is called BEFORE
  `public.npc_upkeep_scope()`, which sets the 2 s `lock_timeout` — and `lock_timeout` is 0 in the session — so the wait has no bound but the wall.
- The hour's deadline (`v_deadline` = start + `npc_upkeep_budget_seconds` 60 s) is read by `public.npc_upkeep_spent()`, which only `public.npc_tend_route` (the dear work: plan, start, resume,
  clear), `public.npc_invest_one` and `public.npc_plan` call — that is, INSIDE a step, after its quay. Past the deadline the loop still queues for the quay for **every remaining merchant (~840)**, only to
  defer her.
- The companies' step opens a second 60 s (`v_cdl`, 0143) — so 60 + 60 + the check can exceed 120 s by construction.
- **Finding that corrects the brief:** `public.capital_gift_one` does NOT read the deadline (no `npc_upkeep_spent` in its text; checked over every function in the database: only `npc_tend_route`, `npc_invest_one`, `npc_plan` call it). The gift
  loop has no budget; `v_cdl` never ended it. Ending it at `v_cdl` would have been a behaviour change while there is time, so its end is the hard end alone.

## 3. The fix — three parts, five exact hunks, no step decides anything differently

1. **Skip before the quay.** In the three loops, after `p_commit` and the loop's end: the step is counted deferred through `public.npc_tend_sum(v_tend, {deferred 1})` (the one place a receipt is added up;
   exactly what `npc_invest_one` answers past the deadline) and `continue`d — no pass, no quay, no transaction. The merchants' loop ends at `least(v_deadline, v_stop)`, the investment loop at
   `least(v_cdl, v_stop)`, the gift loop at `v_stop` only. The skip stands after the 0182 `waiting` count (a waiting merchant is still counted `waiting`) and before her plan/clear passes.
2. **One hard end.** `v_stop = public.upkeep_hard_end(statement_timestamp(), statement_timeout from pg_settings)` = the statement's start + its wall − **25 s** (95 s of 120). `statement_timeout` 0 =
   unlimited → no hard end (`least(deadline, NULL)` is the deadline). `statement_timestamp()` is what the timer counts from; it does not move across the procedure's COMMITs.
3. **The receipt** gains `skipped` `{tend, companies}` and `hard_end_s` (seconds from the start to the hard end; null = none).

`p_commit = false` is unchanged: every new test is `p_commit and …`. The invariants pass (checks, order, raising), the phases and their order, the knobs, the cron job and the schedule are untouched.
The re-cut logic is exactly the one reviewed under 0296; the only change to the body is the number in its comments (`-- 0300:`), so its pinned post-image md5 is `61b15323b59e20e0f793ffc70ef152da`.

**One new function, pure:** `public.upkeep_hard_end(p_start, p_timeout_ms, p_reserve_s default 25)` (stable, invoker, `revoke … from public, anon, authenticated`, listed in `tests/rpc.surface.spec.ts`). It exists so the
end-of-upkeep rule is unit-tested on its own and the 25 s is written once. Why 25 s: the check measured 0.2–5.2 s (1.3 s since 10-29); the longest single quay wait kept is 9.0 s and the longest hold 2.6 s, so a step admitted just
before the end uses ≤ ~12 s of the 25 and still leaves the check ≥ 13 s.

### A busy hour, now
`0 s` call starts → `0–60 s` merchants (the budget) → `~60–70 s` the step in flight finishes; every later merchant is skipped in microseconds → investment loop until `min(v_cdl, 95 s)` → gift loop until 95 s →
**the check starts by ~95 s + one quay wait (≤ ~10 s seen) + the gift roster's query (1.7 s, read-only on prod 2026-11-01 ~19:50 UTC: 7 gifts due, `economy_closed` true; it runs before its loop whether or not the steps are
skipped) and takes ≤ ~1.3 s (5 s worst ever) → done ≈ 100–112 s < 120 s.** The 25 s reserve is the sum of those worst cases (≈ 12 + 2–5 + 1–5 s) with a little to spare; it is not shown to hold against a failing hour's
longest wait, which no receipt kept (§8.3). The investment roster is 535 companies and the merchants' 837; both queries together took ~0.2 s.

## 4. What a skipped merchant misses (said plainly)
Past the end her step would have done only its UNCONDITIONAL light work — a tow, a dark pause, a laid-up note, the off-route re-assign (0114 already deferred the dear work). That waits one hour; the roster
(`order by sr0.updated_at`, the route written longest ago first) reaches an unwritten route sooner than the ones written since. `deferred` now counts every skipped step; it counted only steps with dear work left
(0–54 an hour in the kept receipts), so it reads larger in a busy hour — `skipped` is the honest count. A skipped gift is re-read next hour (cool-down hours).

## 5. Not in this slice (stated, not hidden)
- **Throughput.** In a busy hour the 60 s budget still covers only the merchants it covers; the tail waits. The receipt now says how many (`skipped`). The roster is ordered by the route's `updated_at`, which a step
  that finds nothing to do does not advance — so in a persistently slow hour the same head of the roster is walked each time (this was already true of the dear work, deferred inside the step). If `skipped.tend`
  stays large hour after hour, a rotating start (or a `tended_at` on the route) is the follow-up; the levers (a cheaper quay, the beat's own I/O) are separate. None is a knob change.
- **A quay wait already begun is not bounded** (no `lock_timeout`): a step admitted just before the hard end waits for whatever holds the quay, then runs, and only then does the check start. What must fit in the 25 s that
  follow the hard end is that wait + the step (≤ ~3 s) + the gift roster's query (~1.7 s) + the check (≤ 5 s). **The evidence says the wait can be long even after 0297:** the arrivals beats kept for 20:06:30–20:09:00 UTC on 2026-11-01
  (58 of them) have p50 281 ms but p90 10.7 s and max 12.4 s (almost all `arrive`); at :07 three sessions of ~58–66 s (the arrivals job, the lap-starts job and the hourly) compete for the quay, and the 20:07 hourly died again inside
  `hold_the_quay()` (line 120) with the beat fast — the hourly's own load slows the beats at :07. One slow beat plus a lap-start turn can make a wait of ~15 s: 15 + 3 + 2 + 5 = the 25 s, to the second. **This file makes the failure rare, not impossible.**
  The deterministic completion, deliberately NOT in this file (the reviewed logic stays as reviewed): a helper `public.hold_the_quay_until(end) returns boolean` that sets `lock_timeout` to the time left to the loop's end and answers false when
  the quay was not granted in time (`lock_not_available` caught); each loop calls it in place of `hold_the_quay()`, and a false is counted deferred and skipped like a step past the end. No wait could then outlast the hard end, and the check
  would always have its slack. It is testable without contention (a stub quay that raises 55P03: the wiring, the accounting, the computed bound); real contention would stay UNVERIFIED. It would be a separate slice, after 0300.
- **`job canceled`** (2 of 33) is a different failure and is unchanged. So are the roster queries that run before a skipped loop (plain reads: ~0.2 s for the merchants' and the investment rosters, 1.7 s for the gift roster).

## 6. The file's runtime (this is what 0296 got wrong)

**Prod, read-only SELECTs, 2026-11-01 ~19:40–20:30 UTC (the machine's clock, KST, read 04:4x on the 2nd)** (server-side `clock_timestamp()` deltas inside one statement; the pieces this file uses):

| piece | cost on prod |
|---|---|
| md5 over all 676 functions of public/cmd/world/voyage (the file does it twice) | 84 ms |
| `client_rpc_entry_points()` (84) + the three walls (0 / 0 / 0) | 68 ms in all |
| `npc_tend_roster()` (837 rows) | ~11 ms |
| `npc_waiting_queue()` (47 waiting) | 20–44 ms |
| `ledger_sum()` of a tail house (97 ledger rows) — the one real purse check, in the bite case | ~53 ms |
| *for contrast, what 0296 did per probed merchant:* a digest of her rows (events, ledger, laps, orders, voyages, port goods) | ~340 ms, twice a case |
| *and* the gift roster (7 due) / a real step | 1.7 s / not readable (volatile): 0.4–1.1 s warm, 5–10× cold |

The 0300 self-assert reads none of the big tables and runs no step: its prod cost is these catalog and roster reads plus ~11 stubbed case runs (a few ms each) — **an estimate of ~1 s** (a generous ≤ 3 s if every read is
three times slower), against a 45 s budget and a 60 s hard stop. It was not run on prod (read-only rule); the hard stop is what makes a wrong estimate harmless.

**Local populated world** (PGlite, the restored 283-file chain; planted before applying the file: events 447,029 · standing_route_laps 167,400 · ledger 250,612 as balanced pairs, every purse still equal to its ledger sum ·
voyages 20,925 · orders 13,409 · port_goods 154,734 · 837 merchants — prod's sizes are events 451,583 · laps 167,507 · ledger 250,774 · voyages 21,239 · orders 13,974 · port_goods 154,734; `ANALYZE`d after):

| file | tiny CI-style world | populated | populated + prod-like switches (traders on, treasury on, economy closed) | populated + prod's own `world_config`, `reconcile_runs` and 47 merchants waiting |
|---|---|---|---|---|
| 0296 (first push) — whole file | 0.55 s | 1.03 s | 1.01 s | — |
| **0300 — whole file / its self-assert** | 0.22 s / 0.15 s | **0.23 s / 0.16 s** | **0.26 s / 0.17 s** | **0.33–0.42 s / 0.22–0.28 s** (5 runs) |

The last column reuses the Stats agent's rehearsal idea (`scratchpad/p0299`): prod's own small tables imported read-only — all 291 `world_config` rows (the real knobs and switches: traders on, treasury on, economy closed, 60 s upkeep budget),
the 93 `reconcile_runs` receipts the file's copies delete from and insert into — and 47 routes laid up and not overdue at the tail of the roster (prod's count), which is where the probe's sample looks first. The machine was busier for these
runs than for the others (the same file, 0.22–0.26 s on a quiet one); a noisy neighbour moves the figure, not its shape.

What this does and does not say: PGlite is in-memory wasm, so it shows neither prod's I/O wait nor the cold-cache factor (and 0296's real steps cost tens of milliseconds there, not seconds) — **its seconds are not prod seconds.** What it
shows is the shape: the new self-assert costs the same at zero history and at prod volume and with the switches on or off (it reads no big table and runs no step); the old one grew with volume and with real work.

## 7. Proof (local; CI is the full proof)
- **Bodies.** Prod's `md5(pg_get_functiondef('public.tick_reconcile(boolean)'))` = `3d91fee71b50f7e58b35617c3eb72ef3` (15011 chars; `md5(prosrc)` = `12238b7715ba31e94178c911ff0fc4c2`), read from prod. The chain's body
  — restored from the cached prefix, no from-zero replay — has the same two md5s. The five hunks were cut against that text; each `old` occurs once, `new` adds no non-ASCII, and the
  re-cut text is pinned by its own md5 (`48183c5804cb21b84f73d46dd7814168`), so the body installed is exactly the reviewed one. The file refuses any other pre-image and is re-runnable if a push dies
  after the re-cut (it then skips the re-cut and runs its asserts).
- **Self-assert** (`0300 self-assert ok:` receipt, which prints its own seconds): hunks reverse to the live pre-image (md5); ACL / volatility / definer / config as found; the invariants block byte-identical; the phases in
  their old order; each skip before its quay; the helper (120 s → 95 s, 0 / null / negative → none, short walls → the start, the reserve as asked, server-only); then the loops, on pg_temp copies of the OLD and NEW bodies
  (the 0274 technique) cut to a sample of 3 roster merchants — the traders on, the live waiting queue replaced by an empty one, the statement_timeout a copy reads cut in as a literal (**no probe SETs `statement_timeout`**:
  nothing in the file can touch its own wall), **every step replaced by a stub that writes one line to a call log** (`npc_tend_route`,
  `npc_invest_one`, `capital_gift_one`, the purse checks; the copy's own text is asserted to hold no call to a real step), each case run ONCE (a difference must reproduce on a second attempt). The hunks touch nothing but the
  control flow around the steps, so the control flow is what is proved:

  | case | what it shows |
  |---|---|
  | `p_commit = false`, in time: old = new | the same receipt (a clock's keys and the two new keys apart) and the same call log; every step was reached |
  | the skips cut to the BARE time test, `p_commit = false`, in time | the test alone is false in all three loops while there is time: nothing skipped, the loop = the old loop |
  | `p_commit = false`, every deadline and the hard end past: old = new | the gate holds; the budget is still read in her step |
  | `p_commit = true`, hard end past (the copy's wall cut to 1 s) | every step skipped (merchants 3 + companies 6), none reached (the call log holds only the invariants pass's own walk), the quay tally empty. A COMMIT cannot succeed inside a probe, so **a `p_commit = true` call that finishes reached no step at all** |
  | `p_commit = true`, only the phases' deadlines past, the copy's wall cut to 0 | merchants and investment skip, `hard_end_s` null |
  | the bare-time copy of that, gift loop walking | the gift steps ARE reached (the quay tally counts 3): the gift loop does not stop at `v_cdl` |
  | `p_commit = true`, hard end past, the REAL invariants pass, one ducat with no ledger row | the check **bites** (`LEDGER RECONCILIATION FAILED … difference = 1`) after a fully skipped upkeep |

  Every other function in public/cmd/world/voyage md5-unmoved, the registry (84), the walls 0 / 0 / 0, `economy_closed` and `city_treasury_enabled` as found.
- **NOT proved in the file, by design — said in its header, here and in its printed notice, in every environment alike.** (1) *Real steps, old = new, on the rows a merchant's step writes* (what 0296's digests did): the hunks are
  pure insertions guarded by `p_commit and …`, the pre- and post-image md5 are pinned, and every step function is md5-unmoved — and the re-cut body runs REAL steps under `p_commit = false` in
  `scripts/db/proofs/02_ledger_reconciliation`, `10_manifest` and `12_merchant_companies` (pglite-gate on every PR), which assert the upkeep's outcomes. (2) *The `p_commit = true` path with steps* — nothing rolled back can test a COMMIT (§8.1).
- **The self-assert has teeth.** 22 deliberate breakages of the file (gate removed, or neutralised with its text kept; test inverted or always true; gift loop ended at `v_cdl`; investment loop without `v_cdl`; merchants without the
  hard end; a skip not counted; skipped keys swapped; the wall read in the wrong unit, as a constant, or anchored an hour late; the reserve added; `hard_end_s` missing; a skip before the `waiting` count; the skip that is `if p_commit then`; a purse check, the
  investment step or the bite copy's real check left REAL / lost) — each recomputed with its own md5 so the md5 gate could not stand in, and each checked to fail for the INTENDED reason (a syntax error would "catch" everything) —
  **all 22 fail the self-assert, 22 for the reason they were built to be caught for** (the wrong-unit and constant-wall ones at the copy's cut of the pinned wall read, the anchored-late one at the receipt's `hard_end_s`).
- **Gates run:** `db:check-versions` (284 versions, no collision); the self-assert through the prefix cache (283 restored + 1 applied, `BYEHARU_PREFIX_CACHE=required`, no from-zero replay); the file on the populated world (§6);
  the three proofs that call `tick_reconcile(false)` on the new body. CI on the PR is the rest.

## 8. UNVERIFIED (could not be proved without running the real hour, which this slice does not do)
1. The `p_commit = true` path WITH steps — the quay, the commits, the real beat. A probe cannot commit. It is the old loop plus an `if` that is false while there is time (the bare-time case above).
2. That `statement_timestamp()` in the pg_cron session is the call's start, and the cron session's `statement_timeout` is the 120000 ms read here from the cluster setting (consistent with the 31 cancellations
   at 120.0–121.4 s, and no role override for `postgres`). Grounded, not run: `cron.use_background_workers` = off and `cron.host` = localhost, so a job is an ordinary libpq connection sending the command as one
   query message (the timer and `statement_timestamp()` both start at its arrival). The first :07 after the push shows it: `hard_end_s` = 95.
3. That 25 s is enough in the worst hour: failing hours leave no receipt, so their longest quay wait is unknown (finished hours: ≤ 9.0 s; the kept beats of the 20:07 hour reach 12.4 s, §5) — the residual risk of this file.
4. Throughput and the tail merchants' light work (§4–5).
5. The new file's seconds ON PROD: estimated (§6), not measured — the read-only rule forbids running it; the 60 s `statement_timeout` is the safety.

## 9. After-check (coordinator, read-only; after the push and the first :07 — the next one lands in the busy hours as well)
`cron.job_run_details` for jobid 3: `status = succeeded` and `secs < 120` EVERY hour (busy hours: ~90–110 s). `public.reconcile_runs` newest: `receipt->'hard_end_s'` = 95, `receipt->>'players_checked'` = 840
(the check ran), `receipt->'ms'->>'check'` ≲ 5000, `receipt->'skipped'` = `{tend: n, companies: m}` — 0 / 0 in a quiet hour, hundreds of merchants in a busy one, and `merchant_upkeep.tend.deferred` ≥ skipped.
A failing run, or `hard_end_s` null, is the finding. Forward rollback: a later file re-cutting `tick_reconcile` from 0300 (the helper may stay).
