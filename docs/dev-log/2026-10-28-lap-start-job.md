# 2026-10-28: a lap starts in its own job (`osn-lap-job`, migration 0266)

Owner decision 2026-10-28: move the merchant lap-start re-plan OUT of the per-second arrivals beat into its own
job. Same decisions; a merchant may set sail a few seconds after her rest ends. Player-facing beats stay fast.

## Prod before (read-only, head 0265, 10-28 00:47-03:47 UTC)

- **How lap starts are found today:** only by the beat's held loop (0092): `standing_routes.hold_until <= now`,
  not paused, fleet DOCKED (index `standing_routes_hold_due`). 4,227 lap starts in the 3 hours, **all merchants,
  all after her rest** (0 at an arrival: a lap closes on arrival and her 120 s rest always holds her).
- **Rate:** 23.5 a minute (per minute p50 24, p95 35, max 71).
- **Lag** (lap start - (last close + rest)): p50 0.67 s, p95 2.77 s.
- 1 player route on prod (not held). `npc_laps_per_game_day` 0, rest 1.333 voyage-days = 120 s.

## The design (decided by default where the brief left room)

A lap start is the old held wake for one fleet: `hold_until := null; cmd.advance(fleet)`, which runs
`cmd.run_standing_route`: guards, the re-plan (`npc_plan`), the lap row, the stop's lines, then her BUYs and SAIL.

- **The re-plan cannot simply run under the quay in the job.** It is ~450-600 ms on prod; a beat is ~350 ms; the
  quay serialises the job with the beat, so either the beat waits up to 0.6 s or the job fits only ~30 lap starts
  a minute into the gaps, under the p95 rate of 35 and far under the peak of 71.
- **The re-plan does not need the quay.** Everything up to the lap row writes only her own rows (route, stops,
  lines, preset, a lap close, a pause, an event). The quay exists because the BUYs and the SAIL lock harbours,
  quay stock and purses in an order that can cross the beat's (0249, 0265's analysis).
- **So two transactions a lap start**, in one job (`public.tick_lap_starts`, pg_cron `byeharu-voyage:lap-starts`,
  every minute, 0248's one warm session):
  - **(A) plan, outside the quay** (`public.lap_start_plan`): fleet + route, then her house (0265's lock:
    players row, `FOR NO KEY UPDATE SKIP LOCKED`), due re-checked under them. Then the old wake's first statement
    and `cmd.run_standing_route` itself with a transaction-local flag `byeharu.lap_plan_only`: it runs every guard
    and the re-plan exactly as before and returns -1 just before it inserts the lap (and before the off-route
    tail). Her hold is put back, so she is still due. Anything final (laid up, paused, re-held) stays final.
  - **(B) open, under the quay** (`public.lap_start_open`), in the gap after the second's beat has committed
    (read from `arrivals_beats`; at most 1.5 s of waiting): quay, fleet + route + house (SKIP LOCKED), due
    re-checked, then the old wake verbatim. The route finds lines under a minute old (0114's own rule) and does
    not re-plan: the lap opens, her lines are written, BUYs and SAIL run.
  - Player routes and fleets with a queued order skip (A): (B) does all, as before.
- **No double lap:** (B) re-checks `hold_until <= now` under the fleet/route locks and the quay, and the wake
  clears `hold_until` in the transaction that opens the lap. pg_cron never runs two instances of a job.
- **One authority for "due":** `public.lap_starts_due()` holds the old loop's predicate; the beat no longer has it
  (self-asserted: no other function in public/cmd/world/voyage contains `sr.hold_until <= `).
- **Clock:** scheduled inactive; `wind_the_clock()` (the deploy script) starts it; it exits at once when
  switched off (`clock_jobs()` read every loop) and at :57 of its minute.
- **The browser's own clock** (`src/lib/rpc/localBackend.ts`) runs `call public.tick_lap_starts(false)` right
  after its `tick_arrivals`: one pass in its transaction, no waits, inside the arrivals budget, as the beat's loop
  had. Proof 12's AFK soak and dark check call it after each `tick_arrivals`.
- **What a player sees change:** a merchant's re-plan reads prices ~0.5-1 s after her rest ends, and her BUYs the
  prices of the gap after it (~1 s later), instead of both at the beat's instant.

## The proof

Self-assert (rolled back): hunks reverse (tick_arrivals 1, run_standing_route 2); `cmd.advance`, `npc_plan`,
`close_lap`, `credit`, the quay, the beat procedure and the compactor unmoved (md5); the flag is set by the plan
step alone and read by the route alone; the open step takes the quay, then the locks, then re-checks; the plan
step never takes the quay; everything new server-only.
**OLD vs NEW** for up to 4 merchants resting at home with her rest over, each made due alone (every other due
hold pushed a day out inside the block): the old held loop (a pg_temp copy built from this file's own pre-image
text) vs the job's one pass, then old again (control): the same digest of her route, stops, lines, laps, orders,
fleet, ships, voyages, purse, this transaction's ledger rows and events, her port's market and treasury.
**TWICE:** the pass run twice (then A and B by hand answer 0 = not due), and A, A, B, B by hand (answers 1,1,1,0):
the same digest, one lap.
Not shown: two real sessions at once (PGlite has one connection, CI's chain has no dblink, prod is read-only
for checks). The guarantee is the lock + re-check above, plus the prod after-check below (no route with two laps
of the same number or two open laps).

On a dark world (CI's chain) no merchant rests at home with lines, so the OLD vs NEW part probes 0 merchants;
on prod (merchants lit, the clock stopped by the deploy so rests run out) it probes real ones. Locally it was
run on a lit world (below).

## Local (PGlite, chain to 0265 restored, `npc_fleet_max` 240, the switch, 6 rewound beats, rests run out, THEN 0266)

- 0266 applied in 4.8 s: **self-assert ok, 4 merchants probed, 4 opened a lap; old = new = control, twice and
  interleaved alike.**
- The beat after 0266: `held` gone from its splits, no route woken (192 still held).
- One pass of the job (re-plans made stale): 45 laps in the 10 s arrivals budget; **plan step 184 ms a route,
  open step 48 ms a lap** (the open step does not re-plan). A pass with fresh lines: 190 laps, open 51 ms each.
- No route with two laps of one number, no route with two open laps.
- The committing loop (`call tick_lap_starts()`): 18 laps; with no beat running locally every open waited its
  full 1.5 s (`late` 18), as designed; it stopped at :57.

## Prod after

Below, after the deploy.
