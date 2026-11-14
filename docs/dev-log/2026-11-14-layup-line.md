# 2026-11-14: a laid-up merchant is asked again in time (0405)

**State: built, PR open, not deployed.** Prod head 0404. It changes live play (merchants leave the waiting line sooner), so it gets a 30-minute
after-check. No live function body is re-cut.

## The finding

Merchants laid up (`standing_routes.paused_reason = 'laid_up'`, the 0181 rule) rose every day for a week while merchants sailing fell
(`public.stats_merchants`, daily means):

| day | laid up | sailing | fleets |
|---|---:|---:|---:|
| 11-03 | 33 | 601 | 837 |
| 11-05 | 37 | 611 | 837 |
| 11-07 | 51 | 599 | 840 |
| 11-09 | 68 | 594 | 861 |
| 11-10 | 98 | 568 | 861 |
| 11-12 | 123 | 549 | 861 |
| 11-13 | 161 | 525 | 885 |

## What four read-only prod queries showed (2026-11-14 00:03 to 00:08 UTC, head 0404)

The four files were pure SELECTs inside `begin transaction read only`, tables only. Their line and beat reads live on in
`scripts/ops/harness/layup-line/before.sql` and `after.sql`.

**Ruled out**
- Cities' purses draining. Cities closing a day under 50,000 d. fell from 109 (11-05) to 47 to 53 (11-11, 11-12); the median purse rose from
  57,000 to 517,000. The harbours where the laid-up lie are rich (London 4.1 M, Lisbon 253 M).
- Costs a lap rising. Wages, port fees, provisions, repairs and insurance all fall day by day.
- Merchants' purses in general. The laid-up's median purse is 290,000; 23 of 203 cannot pay for their usual cargo.

**Found**
- 178 of 203 laid-up closed a lap under six hours before (106 under one hour), with healthy last laps (mean net +3,945). It is a line that
  merchants pass through. A lap takes about 19 minutes (64,000 laps a day over 861 fleets).
- About 25 are broke and never wake: purse 0, last lap six hours to fifteen days back. 13 of the 24 pirate houses (DJE, LGA, GOT) and about ten
  ordinary houses. Not this slice; see the end.
- The jump on 11-13 is the merchants' sea light: CAP 15 of 17 laid up, TOK 8 of 8, most after 19:20 UTC.
- The market fills slowly: stock against normal 1.066 (11-01) to 1.129 (11-12), sinks now at 1.44 to 1.46 of normal. Trades a day fell from
  75,000 to 62,000 while the profit of the laps that do sail rose. So more lap starts answer "nothing pays", and each sends a merchant into the line.
- **The line is not served.** 199 in it, 162 due. Minutes since the last ask: p50 21.9, p90 43.9, max 52.4. In the last hour 239 merchants were
  asked, one in each of 239 beats out of 3,287. A due merchant should be asked every 10 minutes: 6 x 199 = about 1,200 an hour.

So the number laid up = how many enter the line x how long each waits, and the wait is n / 4 minutes: the longer the line, the longer each waits.

## Why 240 an hour, whatever the line (the code as it stands at 0404)

1. **One beat in fifteen asks.** `public.tick_arrivals` asks the waiting merchants only when `public.npc_ask_slot(p_now)` is true:
   epoch second mod `npc_ask_every_seconds` (15) = 0 (`20260818000242_the_quay_is_read_every_second.sql:165-176`, the call at `:210-214`).
   That is 240 beats an hour: 7 % of beats, as measured.
2. **One merchant in such a beat.** `public.npc_ask_waiting` begins another merchant only if the time the batch has run plus the last ask's own
   cost stays inside `npc_replan_sweep_ms`, 300 since 0199 (`20260818000199_a_waiting_merchants_batch_keeps_its_budget.sql:14-18`; the rule is
   the live body's `exit when v_n >= v_max or clock_timestamp() + v_last >= v_stop`). An ask costs 290 to 460 ms on prod (the hourly reconcile's
   own receipts, `tend_plan.ms / tend_plan.n`, 11-07 to 11-13), so the first ask always spends the budget. The first of a beat is always begun, so
   it is exactly one.
3. The hourly reconcile asks only a merchant not asked for 60 minutes (0182). The line's own slowness kept everyone just under that: overdue 0.

Not the cause: the beat's whole elapsed time (the 300 ms is counted from the ask's own start), and the sleep to the next second.

## Why the beat cannot simply ask more, and why not the lap-start job

- An ask in the beat runs under the quay, inside the beat, ahead of the next second's arrivals. 1,200 asks an hour at 290 to 460 ms is 6 to 9 s a
  minute of the one session that keeps arrivals on time (mean beat 468 ms, p95 about 1.5 s). The law is arrivals first.
- A knob alone (`npc_ask_every_seconds` 15 to 2 or 3) would do exactly that: correct count, wrong place.
- The lap-start job (0266) is full. In an hour it spends 1.47 M ms planning, 0.45 M opening and 0.70 M waiting for its gap: 77 % of its 57 s a
  minute, with the rest in its own reads and commits. Its lap starts already run late (the median minute's p50 lag is 4.5 to 12.7 s). Asks put
  there would starve, or push the lap starts further back.
- "Do not re-plan a merchant whose quotes did not move" would need a second answer to "does a loop pay" beside the planner's. Not built.

## What 0405 does

A job of its own for the line, in the lap start's own two steps (0266), so the dear part never holds the quay:

- `public.tick_waiting_asks()` on `byeharu-voyage:waiting-asks`, every minute, one warm session. It takes the merchants due from
  `public.npc_waiting_queue` (the one answer to who waits and who is due, untouched), longest waiting first.
- **Step A, `public.waiting_ask_plan(fleet)`, not under the quay.** Her roster row, fleet, route and house, all SKIP LOCKED; due re-checked under
  them; she is stamped asked (`npc_fleets.asked_at`, as the beat stamps her) and planned by `public.npc_plan`, the same call
  `public.npc_tend_route` makes. Nothing pays: she waits on and is due again in ten minutes.
- **Step B, `public.waiting_ask_open(fleet, stamp)`, under the quay, placed in the gap after the second's beat has committed.** Only when her
  plan pays and nobody has asked her since (her stamp is still step A's). She is resumed through the same door as ever
  (`cmd.standing_route_pause_for(..., false)`). The route finds her lines under a minute old and does not plan again (0114), so the quay is held
  for the opening of her lap alone.
- `npc_ask_job_ms` (20,000): the work a minute the job may spend. 0 = off.
- `public.waiting_ask_runs`: one receipt a minute of the day.

Nothing live is re-cut. The beat's own ask and the hourly reconcile stay as they are; the two hands share the one queue and the one stamp, and both
take her roster row SKIP LOCKED. Once the job keeps up, the beat's slot finds nobody due, so the beat loses its 240 asks an hour under the quay.

**A 23rd cron job.** The game has 22. I found no rule against one more; 0315 added `contract-wind` and 0322 `npc-refits` the same way. It is
scheduled inactive and `wind_the_clock()` starts it, as 0266's was (`bv-deploy.sh` unwinds and winds the clock).

## Measured (the cached world at head 0404, `scripts/ops/harness/layup-line/measure.mjs`)

200 merchants staged laid up and due, the job called as pg_cron calls it, with its commits, for one clock minute:

| | |
|---|---|
| asked in the minute | 60 (all 60 resumed: this world's market is fresh, every plan pays) |
| work spent | 20,275 ms of 20,000 (the budget plus the ask in hand) |
| an ask | 338 ms: plan 305 ms outside the quay, open 33 ms under it |
| the 200 | asked in under four minutes |

The plan here costs what it costs on prod (305 ms against prod's 290 to 460), because the planner's work is the same reads.

**Expected on prod**, from prod's own cost of an ask:

| an ask | asks a minute in 20,000 ms | an hour | line asked every 10 minutes |
|---:|---:|---:|---:|
| 300 ms | 66 | 3,960 | 660 |
| 460 ms | 43 | 2,580 | 430 |
| 560 ms (a lap start's plan) | 35 | 2,100 | 350 |

Wanted for a line of 200: 1,200 an hour, 6 to 9 s of work a minute. For 300: 1,800 an hour, 9 to 14 s a minute. Added database time: that
much, in a third session, of which only the opens (about a tenth of the asks' time when most plans pay, far less when most wait) are under the
quay and placed after the beat. A due merchant is then asked within her ten minutes plus the job's dead three seconds a minute: about 10 to 11
minutes. The line itself should shrink, since each merchant waits ten minutes where she waited n / 4.

## Proof

- **The file's self-assert**: the three bodies, the book, the knob and the job as written and server-only; then ONE merchant asked by the job's
  own pass in a rolled-back sub-transaction: off asks nobody; on she is asked once, stamped, and waits or is resumed; asked again at once nobody
  is asked. Fails above 15 s. `probe.mjs` runs it on three worlds: dark as cached (no probe, 34 ms), lit with nobody laid up (one staged, 0.7 s),
  lit with a line of 30 (the longest waiting taken, 0.4 s). A first cut failed the second and third (a null comparison); found here, fixed.
- **Proof 100** (`scripts/db/proofs/100_a_laid_up_merchant_is_asked_again_in_time.sql`, 8 markers, about 14 s): 45 merchants laid up by hand, 40
  due. LL_OFF, LL_NO_QUAY (the plan step takes no advisory lock), LL_ORDER (a budget of one ask asks the one waiting longest), LL_ALL (one pass
  asks every merchant still due, each stamped, none failed, nobody left due), LL_OUTCOME (each waits on or sails; the ten with no purse wait), LL_NOT_DUE, LL_TWO_HANDS (after the pass the beat's hand
  asks 0), LL_STAMP (the open step refuses a moved stamp and holds the quay). It asserts no price and no choice of the planner.
- **Dice** (`dice.mjs`): proof 100 under 4 other secrets and markets (every stock x 0.2 to 1.8): 4 of 4 green. Every plan paid in all four, so the
  proof now also stages ten of its due merchants with an empty purse: their plans cannot pay whatever the market, and they must wait on (waiting 10,
  resumed 29 on the fixture market).
- Proof 12 (merchant companies; it covers the lap start and the waiting line of 0181, 0182, 0199) green with the file applied.
- `before.sql`, `after.sql` pass the read-only reader and run on the cached world; the rollback draft takes everything of 0405 away.

## PROD CHECKS

1. Before: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/layup-line/before.sql`. Wanted: head `20260818000404`,
   `applied_already` false, every volatility `s` or `i`, 22 jobs. Write down `bodies`, `line`, `beats`, `lap_starts`.
2. Deploy: `~/bin/bv-deploy.sh <pr>`. Expected time of the file on prod: under 10 s (one plan at 0.3 to 1.2 s, and one lap opened and rolled back);
   its budget is 30 s and its probe fails above 15 s.
3. After, at +5, +15 and +30 minutes: `... -f scripts/ops/harness/layup-line/after.sql`. Wanted: the job scheduled and active; the same six body
   md5s; `line.mins_p90` under 12 and `mins_max` under 15; `asks.failed` 0; `asks.spent_ms_max` near 20,000 at most; **`beats.ms_mean`, `ms_p95`
   and `over_1s` not above the before read**; `beats.asked` falling toward 0; lap-start lag not above the before read.
4. If the beat slows or asks fail: the owner sets `npc_ask_job_ms` to 0. The forward rollback draft is `rollback-0405.sql`.

## Not verified

- Prod. Everything above the "expected on prod" table is the cached world; the prod figures are arithmetic from prod's own cost of an ask.
- How far the line falls. The inflow (lap starts that answer "nothing pays") is the market's and is not changed here.
- The job under real concurrency with the beat and the lap-start job: PGlite has one session. The locks are SKIP LOCKED in the order the beat's
  hand takes them, and the open step is 0266's placing, but the first lit half hour is the test. The after-check reads it.
- The self-assert's probe on prod resumes or re-plans one real merchant inside the deploy transaction and rolls her back. It ran here on staged
  merchants only.

## Decided by default

1. A job of its own rather than more asks in the beat or in the lap-start job (measurements above).
2. The beat's ask stays (no live body re-cut, the local worlds and the proofs unchanged). Removing it, with `npc_ask_slot` and its three knobs, is
   a later slice once the job is proven on prod.
3. 20,000 ms a minute: enough for a line of 350 at the dearest ask measured.
4. No news row: nothing a player reads changes.

## The broke houses (reported, not built)

About 25 laid-up houses have a purse of 0 and never wake: 13 pirate houses and about ten ordinary ones. An ask cannot help them: with no purse
every parcel is sized to nothing (0129). The owner decides; see the PR body.
