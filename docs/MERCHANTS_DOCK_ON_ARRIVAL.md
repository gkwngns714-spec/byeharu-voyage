# MERCHANTS_DOCK_ON_ARRIVAL — a merchant is in port the moment she truly arrives, never before

**Status: BUILT as migration 0125 (`a_merchant_docks_the_moment_she_arrives`), PR #123
(osn-0125-merchants-dock), 2026-10-15. Prod head 0126. Not deployed. 0125 sits before 0126 in the
chain (number taken first, landed second).**

The owner, 2026-10-15: *"the merchant npc should also be like me."* On the design: "in port" is a
pure function of time — shown docked the moment she really arrives, never before (weather can slow
her on her last day); trading, the lap close and the next departure stay in the sweep, every 15 s.

`NNNN:line` is `supabase/migrations/20260818000NNNN_*.sql`.

---

## 1. What was wrong

The merchant reads (`world.sea_roster` 0118, `world.port_merchants` 0113/0104 with
`public.merchant_doing_at` 0104, `world.npc_fleet_card` 0099 as cut by 0123/0124) served `status` /
`port` / `voyage` straight off `public.fleets`, which only the minute sweep (`public.tick_arrivals`,
cron `* * * * *`, 0012:97) writes. An arrived merchant lay off the quay as a SAILING hull until the
sweep reached her (prod, 2026-10-15 16:10, last hour: avg 17 s, max 39.8 s per run, 60 runs).

## 2. Weather in the code today (the owner's question)

- Position: `voyage.progress_nm(voyage, t)` (0006) — elapsed sim-hours minus the delay **recorded**
  so far (`voyage_events`), leg by leg at fixed per-leg speeds.
- The only pace changes are the daily hazard roll's delay arms in `voyage.settle`: STORM +36 h, CALM
  +24…96 h, FAIR_WIND gives back up to what was lost. Each day is resolved by the sweep at its
  boundary (`voyage.day_ends_at`), recorded, and folded into `voyages.eta` by `voyage.recompute_eta`.
- No speed changes mid-leg exist; a delay holds her in place.
- `day_ends_at` **clamps** the remaining days at the eta, so at the stored eta her last day(s) are
  still to be rolled — a CALM there keeps her at sea. That is why a stored eta is not her arrival.
- The roll is pure (`voyage.hazard_roll`: voyage, day, world secret; `voyage.rng` IMMUTABLE), so her
  true arrival is computable without waiting for the sweep.

## 3. The design (built)

- `voyage.day_delay_hours(kind, magnitude, prior)` — THE table of what a day's roll costs (moved
  verbatim out of `voyage.settle`'s three arms, which now read it; equal over a grid, asserted).
- `voyage.arrival_at(voyage, t)` — her TRUE arrival. While the stored eta is ahead of t, the stored
  eta (the days ahead have not happened — nothing is revealed early). Once it is not: every unresolved
  day rolled in order through `hazard_roll` + `day_delay_hours`, the day count growing as
  `total_days` grows, each day happening at its (clamped) boundary — so a fair wind that pulls the eta
  behind its own day lands her at that day's boundary. Asserted against `voyage.settle` itself: at sea
  a second before the true arrival, ARRIVED at it.
- `voyage.where_now(fleet, t)` — her own status / port / voyage, except: true arrival at a harbour has
  come → DOCKED there, no voyage; past the stored eta but held → served `eta` = true arrival. Plain
  SQL (no SECURITY DEFINER, no SET) so the reads inline it; `arrival_at` is fenced (OFFSET 0) so it
  runs once per passage and only for passages at or past their stored eta (a handful).
- The three reads and `merchant_doing_at` (so the harbour list's `doing` and order) take where she is
  from `where_now`. All stay STABLE; they write nothing. `world.fleets` (players) and
  `world.fleet_trades` are untouched.
- Roster delta also carries every merchant at or past her stored eta, so the docked fact (or a held
  passage's true arrival) reaches the map on its next roster beat.
- **Client:** unchanged. It never decides an arrival itself: it clamps her at the end of her course
  until a read serves the docked fact (≤ one roster beat, 30 s; `ROSTER_ASK_EVERY_MS` is the lever if
  that is too slow).
- A mid-passage delay (recorded by the sweep as its day comes) still reaches the map only when her
  moved eta passes — as before 0125. A delta clause on recorded delay events cost +1 s per full roster
  read on prod (a hashed scan of `voyage_events`) and was removed. She is never shown in port early.
- Future weather: anything that changes pace must be a recorded day effect read by `progress_nm` /
  `recompute_eta` **and** expressed in `day_delay_hours`, so `arrival_at` stays the same fixed point
  as `voyage.settle`. Seeded rolls stay computable by the server and unpredictable to players (nothing
  ahead of the stored eta is served).

**The sweep.**
- `byeharu-voyage:arrivals`: `* * * * *` → `15 seconds` (prod pg_cron 1.6.4). pg_cron runs at most one
  instance of a job at a time (a due run is queued), so runs never overlap.
- `tick_arrivals`: wall-clock budget `arrivals_tick_budget_ms` = 10 000 from the run's start (the
  candidate scan included), checked before each settle, yard release and wake.
- `byeharu-voyage:cron-purge` (daily 04:23): deletes `cron.job_run_details` older than 2 days.
  Defined inactive; `wind_the_clock()` starts it (0078).
- Rollback of the cadence, one statement: `select cron.alter_job((select jobid from cron.job where
  jobname = 'byeharu-voyage:arrivals'), schedule := '* * * * *');`

## 4. Measured (prod dry-run, begin…rollback, prod head 0126)

| | value |
|---|---|
| full roster read | 659 ms (before 596 ms) |
| `where_now` over every merchant | 5 ms |
| passages agreeing position ↔ eta | 438 of 438 |
| sweep before | avg 17 s, max 39.8 s per minute run |

## 5. Self-assert (0125)

Posture; every cut body is its pre-image plus only 0125's hunks; `day_delay_hours` equals the old
arms; `where_now` is inlinable; cron on `15 seconds`, purge defined inactive; over every merchant at
sea `progress_nm` reaches the end at the eta; parity with nobody arriving; **a probe past her naive
eta whose remaining days roll a delay is AT SEA on every read with her true arrival as eta, and
`voyage.settle` agrees** (break-tested: serving the naive eta goes red); a truly arrived probe is
DOCKED on roster, card and harbour (as `authenticated`) with nothing written; a 0 ms sweep settles
nobody.

---

## Rejected

- **Settle-on-read** (first M1 cut): each read would call a skip-locked `voyage.settle_due` and turn
  volatile. Built, dry-run, replaced by the owner's design — reads must not write; a woken merchant's
  lap-start plan cost 4.1 s inside a read on prod.
- **Position-only verdict** (second cut): "in port" = `progress_nm` reached the end. Rejected in
  review: at the stored eta the last day is unrolled, so a CALM there showed her in port and then
  back at sea. Replaced by the true arrival above.

Found on prod (pre-existing, not fixed here): 73 merchants idle at home and 67 merchant SAILs failed
`E_ENDURANCE` in one hour.
