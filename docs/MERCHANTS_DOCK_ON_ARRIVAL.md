# MERCHANTS_DOCK_ON_ARRIVAL — a merchant is in port the moment she arrives, the way a player is

**Status: BUILT as migration 0125 (`a_merchant_docks_the_moment_she_arrives`) + `src/live/seaRoster.ts`,
2026-10-15, on PR (osn-0125-merchants-dock). Prod head 0124. Not deployed.**

The owner, 2026-10-15: *"the merchant npc should also be like me."* And on the design: "in port"
is the ship's actual position — the same function the map uses — having reached her destination,
never a stored eta; the arrival is not known at departure (weather can slow her mid-passage);
trading, the lap close and the next departure stay in the sweep, which runs every 15 seconds.

`NNNN:line` is `supabase/migrations/20260818000NNNN_*.sql`.

---

## 1. What was wrong

The merchant reads (`world.sea_roster` 0118, `world.port_merchants` 0113/0104,
`world.npc_fleet_card` 0099 as cut by 0124) served `status` / `port` / `voyage` straight off
`public.fleets`, which only the minute sweep (`public.tick_arrivals`, cron `* * * * *`, 0012:97)
writes. An arrived merchant lay off the quay as a SAILING hull until the sweep reached her — up to a
minute plus the sweep's own run (prod, 2026-10-15 16:10, last hour: avg 17 s, max 39.8 s, 60 runs).
At 960× that is a day of ship's time.

## 2. What weather is in the code today (the owner's question)

- The position function is `voyage.progress_nm(voyage, t)` (0006): elapsed sim-hours **minus the
  delay recorded so far** (`voyage.delay_before_day` sums `public.voyage_events.payload.delay_hours`),
  consumed leg by leg at each leg's speed (`voyages.speed_profile`, fixed at departure).
  `voyage.position` and the chart's drift read it.
- The only things that change a passage's pace are the daily hazard roll's delay arms inside
  `voyage.settle`: **STORM** +36 h, **CALM** +24…96 h, **FAIR_WIND** gives back up to what was
  already lost. Each is RECORDED as a voyage_event when the sweep resolves that day, and
  `voyage.recompute_eta` re-derives `voyages.eta = departed + (sim-hours + recorded delay)`.
- The roll is seeded (`voyage.hazard_roll` = pure function of voyage, day, world secret), but its
  effect exists **only from the moment the day is resolved**. Nothing reads ahead. There is no
  "speed change" system — a delay holds her in place for N hours; speeds per leg never change
  mid-passage.
- Stored eta is therefore exact only as of the last resolved day. A CALM on the day still to be
  resolved will move it.

## 3. The design (built)

**One verdict, from the one position function.**

- `voyage.arrived(voyage, t)` — has her `progress_nm` at t reached the end of the path progress_nm
  walks (`least(round(Σ legs nm, 4), total_nm)`). **It reads no eta.** Cost guard: a passage cannot
  be done before its undelayed sailing time (recorded delay is never negative), so the walk runs only
  for one that could be. Stable, server-only.
- `voyage.where_now(fleet, t)` — her own status / port / SAILING voyage, except that a passage whose
  position has reached a HARBOUR reads `DOCKED` there with no voyage. Writes nothing.
- The three merchant reads take status / port / roadstead / voyage from `voyage.where_now`
  (sliced hunks; they stay STABLE). `world.fleet_trades` serves no position and is untouched.
  `world.fleets` (players) is untouched — it settles on read (0009).
- The roster delta also carries a fleet whose passage gained a **delaying event** since `p_since`
  (before 0125 an eta change never reached the delta at all, only the 10-minute full read).
- **Client:** `src/live/seaRoster.ts` `trafficRowAt` — the merchant placement function — docks her
  when the SAME `placedFrac` that draws her reaches 1 and she is bound for a harbour: DOCKED in that
  port, at the roadstead her course ends on, no voyage. `whereabouts` (`domain/fleet/where.ts`), the
  one classifier, then reads her as docked with no rule of its own. The placement is re-run on every
  beat (7.5 s at 960×).
- **The map and "in port" agree on the instant.** Client placement is linear from departure to the
  served eta; the server's `voyage.arrived` reaches the end exactly at the served eta. Asserted over
  every merchant at sea (prod dry-run: 474 passages).
- **Future weather:** whatever later changes speed mid-voyage must flow through `progress_nm` (and
  so through `recompute_eta`, the one eta author). Then both the map and "in port" follow with no
  second edit. This holds whether weather is rolled from a seed and recorded when resolved
  (unpredictable to players, computable by the server) or rolled live and recorded.
- **What is not exact, said:** a delay on the day the sweep has not yet resolved (at most 15 s +
  run behind) is not known to anyone until it is resolved. If it lands on her final day she may read
  "in port" for those seconds and then return to sea (the roster delta carries the moved eta on the
  next beat). That is the honest consequence of "the arrival is not known in advance".
- `public.merchant_doing_at` is not re-cut: an arrived, not-yet-swept merchant reads
  `ending` / `passing` in the harbour list for those seconds.

**The sweep every 15 s.**

- `cron.alter_job` moves `byeharu-voyage:arrivals` from `* * * * *` to `15 seconds` (pg_cron ≥ 1.5;
  prod runs **1.6.4**, read 2026-10-15). `alter_job` keeps the job's active flag (0078: the chain
  defines, the runbook winds).
- pg_cron runs at most one instance of a job at a time; a run due while one is running is queued
  and starts when it ends — runs never overlap and at most one waits.
- `public.tick_arrivals` gains a wall-clock budget, `arrivals_tick_budget_ms` = 10 000, checked
  before each settle and each wake. Arrivals come first (the loop is in eta order); the next run
  takes the rest. Lock order inside a run is unchanged, so the drift / reconcile deadlock behaviour
  is the same; only the cadence moves.

**Rollback:** `select cron.alter_job((select jobid from cron.job where jobname =
'byeharu-voyage:arrivals'), schedule := '* * * * *');` (one statement). The reads: a forward
migration reversing the hunks (all OLD hunks are in 0125; its self-assert proves the reversal).

## 4. Measured

| | where | value |
|---|---|---|
| sweep today | prod `cron.job_run_details`, last hour | avg 17 s, max 39.8 s, 60 runs |
| `where_now` over every merchant | prod dry-run | 611 ms |
| full roster read | prod dry-run | 1,250 ms (before: 638 ms) — read on open and every 10 min |
| full roster read | PGlite | 196 ms (before 192 ms) |

## 5. Self-assert (0125), what it proves

Posture (stable, ACLs, server-only helpers, no entry point, no client write); every body is its
pre-image plus only 0125's hunks; `voyage.settle` and `voyage.progress_nm` untouched; `voyage.arrived`
reads no eta; the cron runs on `15 seconds` where there is a scheduler; over every merchant at sea
the position reaches the end at the served eta and not a second before; with nobody arrived every
read is its pre-image; a merchant whose passage is rewound to have arrived is DOCKED at her
harbour's roadstead on the roster, the card and the harbour's read (as `authenticated`) with nothing
written; **a recorded CALM** keeps her at sea on every read, the served eta is the instant her
position reaches the end, and the roster delta carries her; a 0 ms sweep budget settles nobody; the
sweep's settle docks the arrived one.

---

## Rejected: settle-on-read (first cut of M1, 2026-10-15)

The first M1 plan had each merchant read call a skip-locked `voyage.settle_due` first and flipped the
four reads from stable to volatile, so a read would dock her (lap close, trades and all) before
answering, bounded by count / wake / budget knobs. It was built and dry-run on prod (passed), then
**replaced by the owner's design** above: the reads should not write, "in port" is a pure function
of position, and the sweep — every 15 s — keeps all trading and departures. Measured during that
cut: one woken merchant's lap-start plan cost 4.1 s inside a read on prod, which is the kind of cost
a player's map read should not carry.

Found on prod during that work (pre-existing, not fixed here): 73 merchants lay idle at their home
stop, and 67 merchant SAILs failed `E_ENDURANCE` in one hour — merchants halted by a refused SAIL.
