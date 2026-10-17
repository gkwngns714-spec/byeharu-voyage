# 2026-10-18 — 0169: a day is counted once and a quay is read once — `osn-arrivals-4`

**Symptom (prod, read-only `cron.job_run_details`):** after 0164 (the chart unrolled) went live at about 22:05 UTC on
2026-10-17, `byeharu-voyage:arrivals` (every 15 s, 10 s budget) ran 216 times between 22:10 and 23:14 UTC.

| | 22:xx | 23:xx (to 23:14) |
|---|---|---|
| runs | 164 | 56 |
| avg s | 3.83 | 3.52 |
| p50 s | 3.23 | 3.29 |
| p95 s | 10.10 | 5.22 |
| runs at the budget | 13 | 0 |
| max s | 10.46 | 6.53 |

An average run did 7.5 lap starts, 16.6 departures, 16.5 arrivals and about 151 sea-days. That is about twice the load of
the 2.6 s mornings, and it is legitimate load.

**Where a run's time goes now.** I regressed each run's time on what it did (215 runs, r² 0.83). Departures and arrivals come
from the rows each run wrote. Sea-days come from `voyage_events.resolved_at` between runs. The fit is:

- 0.83 s a run
- 0.23 s a lap start, which is 1.74 s of the average run
- 0.009 s a sea-day, which is 1.36 s
- 0.017 s a departure, which is 0.28 s

So lap starts and sea-days are the two halves of a run, over a floor of about 0.8 s.

**Which of the three named levers dominate (prod, read-only).**

1. **Lap-start planning. This is the biggest lever.**
   - A lap start prices about 11 distinct legs: her own loop plus up to 16 candidates, each leg once. Each leg costs 25–28 ms,
     and `npc_loop_candidates` adds 27 ms. Nearly all of a leg is `world.trade_routes(from, …, to)`.
   - One ranking (LIS→CAD, explain analyze) took 38 ms. 21 ms of that was its 10 quotes (5 BUY, 5 SELL), at 1.1–2.6 ms each,
     plus about 6 ms of `mid_price`.
   - Each quote is about 1.25 ms (2,220 market rows), and about 1.0 ms of that is its **prelude**: `spread_effective` 0.47,
     `city_bid_factor` 0.19, `tax_rate` 0.15, the treasury switch and the step knob. The walk itself is about 0.1 ms a step.
   - With no fleet named, those four terms belong to the port: they are the same for every good, every size and both sides.
     A ranking read them about 10 times for two ports.
2. **The day walk.**
   - At each fleet's next day, `voyage.days_complete` costs 1.69 ms and `voyage.leg_at_day` 2.46 ms (757 voyages at sea).
   - `day_ends_at` is 0.17 ms a call, and `days_complete` walked `d` of them from day 0.
   - The average voyage at sea has total_days 16 and has settled 6.8 days; the longest has 141. Σ T² is 411k.
3. **The candidate scan.** `day_ends_at` costs about 0.17 ms × about 760 voyages, which is 0.13 s a run.

**Fix (migration 0169, provisional number; it applies on prod head 0168).**

- `voyage.day_end_from(eta, departed_at, day, delay_before, k)` is new. It holds `day_ends_at`'s arithmetic, moved verbatim.
  It is PL/pgSQL, STABLE and invoker, reads nothing, and is server-only.
  - `day_ends_at` composes it (one hunk).
  - `days_complete` does the same walk, but reads the voyage row and the knob once. Each step is `day_end_from` over
    `delay_before_day` (two hunks).
  - `tick_arrivals`' candidate test is built from the row it already holds, with the knob read once a run (two hunks).
- `world.quote_terms(port, good, fleet)` is new. It holds the four term readings, moved verbatim out of `world.quote`.
- `world.quote_priced(…, spread, nohag, tax, bidf)` is new. It is generated from the **live** `world.quote` body. It reads its
  terms through `quote_terms` at the same point as before, unless the caller passes them in. `world.quote` is now just
  `quote_priced(…, null × 4)`: same answers, same refusals in the same order, same ACL.
- `world.trade_routes`: with no fleet named, it reads the source's terms once per ranking and each sink's once (two CTEs), and
  passes them to every BUY and SELL quote. With a fleet named nothing is passed, because a purser's spread differs per good.
  The joins are untouched: the terms are passed as scalar sub-selects (two hunks).
- No rule, price, hazard, schedule, knob, table, ACL or entry point moves. Nothing is cached across calls.

**Proof (in the file).** The old tree is kept under `pg_temp`: day_ends_at, days_complete, progress_nm, leg_at_day,
hazard_roll, arrival_at, quote, trade_routes, npc_leg_lines, npc_affordable and npc_buy_ceiling. Its closure is checked
against prod's callers. Old and new are compared as text:

- **Every voyage at sea:**
  - day ends for days 0..T+2
  - **hazard rolls** for days 1..T+1
  - day count and progress at now, before departure, at departure, at the eta, and an hour and a day past it
  - arrival_at at now and at the eta
  - for an md5 sample of 40, also every leg, every boundary and 1 ms either side of it, and arrival_at a day past the eta
- **Probe voyages of the file's own (rolled back):**
  - one with no events
  - one with a STORM / FAIR_WIND / CALM / FAIR_WIND run (93.85 h net)
  - one long passage
  - one voyage that does not exist (its refusals compared)
- **The candidate test**, at now and 1 ms either side of each voyage's next boundary.
- **7,608 quotes:**
  - both sides, five sizes, limits, with no fleet and with a fleet
  - the refusals in their order
  - both with the switches as found and with them flipped (rolled back)
  - 6,080 of them again with the quay's terms passed in
  - `quote_terms(port, good, no fleet)` = `quote_terms(port, null, null)` on 950 rows
- **144 rankings and 12 whole lap-start reads.**
- **Catalogue checks:** each body reverses to its pre-image, and ACL, owner, volatility, definer and config are unchanged. The
  three helpers are server-only PL/pgSQL. The boundary arithmetic and the quote terms each live in one place. No new entry
  point.
- **Prod vs fresh chain:** prod's live bodies of all 18 functions involved have the same `md5(pg_get_functiondef)` as the
  fresh chain's, so the hunks cut here apply on prod.

**Measured locally.**

- Cached-prefix image build: 156 of 157 restored, 1 applied, chain applied in 24.3 s, image certified. `tsc -b` + vite
  passed, and `npm run lint` passed.
- The `0169 self-assert ok` receipt printed:
  - on a saved merchants-on world: 578 voyages at sea, 123 hazards that befell them, 2,312 candidate tests, 49 s to apply
  - on the fresh chain, with an earlier revision whose only difference was the comparison sampling: 17.5 s
- Whole sweep, from one saved merchants-on PGlite world, pinned `p_now`, `analyze` first (837 merchant fleets, 578 at sea;
  the sweep resolves 5,053 sea-days, starts 247 laps and touches 829 fleets):
  - before: **30.8 s**
  - after: **27.2 s** with this file (30.0 s with the earlier revision)
  - both end in the **same state**: identical md5 of every pre-existing voyage's eta, delay and day, and of every voyage
    event; 760 sailing, 1,234 laps, 2,516 reports
- Profile, before → after:
  - `world.spread` calls per sweep: 44,883 → 11,841
  - `wc` calls: 1.08 M → 0.74 M
  - `trade_routes` total: 16.0 → 12.0 s
  - `npc_plan` total: 24.2 → 20.4 s
- In the receipt: rankings −19 % to −33 %, lap-start reads −5 % to −11 %, days_complete at the next day −22 % (local
  voyages are only about 1.5 days in).
- PGlite's function calls cost about a sixth of prod's (`trade_routes` 3.5 ms vs 22–27 ms), so the gains on prod should be
  larger in proportion.

**Expected on prod (not measured; verify after the push, with the same query):**

- About 10 of a ranking's quote preludes are no longer read, about 1.0 ms each, across about 11 legs. That is 0.09–0.13 s of
  a 0.25 s lap start, or about 0.7–0.9 s a run.
- The day count drops from about 1.7 ms to about 0.4 ms at today's average day, about 0.2 s a run, and it is now linear in
  the day rather than quadratic.
- The candidate scan drops from about 0.13 s to about 0.06 s.
- Together that is about 1.0 s of today's 3.7 s, so about **2.7 s** at today's load.

**Push time:** estimated at 3–6 min, almost all of it the OLD walk on every voyage at sea. Deploy with the clock unwound.

**Left, and the next levers:**

- About 3 quote preludes a leg are still read inside `npc_leg_lines` itself: q_size, q_buy, q_sell, `npc_affordable` and
  `npc_buy_ceiling`.
- `world.mid_terms` reads four knobs on every call: about 370 `mid_terms` a lap start locally, 0.165 ms each on prod.
- `voyage.arrival_at` and `voyage.recompute_eta` keep their own copies of the schedule arithmetic, left as found.
- About 0.8 s of each run is the floor: a new cron backend each run compiles every PL/pgSQL body again.

**A production write I made by mistake.** While timing helpers read-only, I ran
`explain analyze select count(voyage.recompute_eta(v.id)) from voyages where status = 'SAILING'`. I took
`recompute_eta` for a read; it is VOLATILE and writes. It rewrote `delay_hours` and `eta` for the 757 voyages at sea from
their own events, which is the same derivation settle applies after every delay.

- Checked right after: every voyage at sea, and every voyage that arrived in the last 3 hours (9,316, untouched by it),
  satisfies `delay_hours` = Σ event delays and `eta` = `departed_at` + (sim_hours + delay) / k. **0 mismatches.**
- `voyages` has no triggers and is in no publication.
- So the values written equal the values that were there, but I cannot prove that from a snapshot before the write.
- From then on I checked each function's volatility before calling it.

**Not done:** merge, `db push`, or any further production write. Renumbered 0168 → 0169 after 0165–0168 (K9, S17, S18, S4 + K10) landed; rebased on main at 0168, and every body cut here was re-dumped from prod at head 0168 and compared (below).

**Re-checked at prod head 0168 (after the renumber).**

- I re-dumped the five bodies cut here from prod, read-only. Each of the 11 hunks occurs exactly once: 8 re-cuts and the 3
  `quote_priced` slices of `world.quote`.
- All 21 functions involved, including 0168's `voyage.escort_score`, `public.crew_pct` and `world.ship_stats`, have the same
  `md5(pg_get_functiondef)` on prod as on the fresh chain at 0168.
- On the rebased chain, the image build restored 156 of 161, applied 5 including 0169, and certified the image.
- The coordinator's baseline after 0164 is avg ≈ 3.3 s and max ≈ 5–6.5 s. The expected cut of ≈ 1.0 s puts it at
  ≈ 2.3 s. Measure after the push with the hourly query.
