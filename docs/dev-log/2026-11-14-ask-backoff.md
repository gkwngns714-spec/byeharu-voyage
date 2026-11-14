# 2026-11-14: a merchant refused again waits longer before she is asked (0407)

**State: built, PR open, not deployed.** Prod head 0406 (0405 and 0406 live since about 02:10 and 02:14 UTC). It changes live play (when a laid-up
merchant is asked again), so it gets an after-check.

## What prod showed after 0405 (2026-11-14, 02:10 to 02:35 UTC; the lead's reads)

0405 did what it was for: the waiting line's backlog cleared in about twenty minutes (line 176 to 143, `due_left` 139 to 0-4, the oldest ask 40.5 to
10.0-10.5 minutes, none failed). Its steady state is too dear:

| | before 0405 (01:30-02:05) | after (02:10-02:25) |
|---|---|---|
| the job | - | 9-12 asked a minute, 2-5 resumed, `spent_ms` 20,100-20,700 EVERY minute, run 22-28 s |
| in a minute of the job | - | plan 12-20 s for 8-14 asks, wait 3-8 s, open 3.6-8.4 s (max 5.6 s) |
| the beat, 5-minute blocks | mean 442-555 ms, p95 1,504-1,977, 20-31 over 1 s, 258-282 beats | mean 615-693, p95 2,508-3,393, 29-35 over 1 s, 213-254 beats |
| lap starts, per 10 minutes | started 411-441, plan 632-679 ms a start, late 41-46, due_left max 2-7 | started 364-399, plan 659-821, late 56-62, due_left max 72-84 |

No errors, ships on time. But the database is near its capacity, and about 70 % of the asks answer "nothing pays" again.

## Why an ask costs about 1.5 to 2 s there, where 0405 reckoned 0.3 to 0.46 s

**I took the wrong figure in 0405.** The 290-460 ms was the hourly reconcile's `tend_plan`: the re-plan of a merchant in mid-lap, which prices ONE
loop, her own. An ask is the planner's dearest path:

- `public.npc_plan` prices her own loop first and fetches the loops on offer (`public.npc_loop_candidates`, up to `npc_route_candidates` = 16) only
  when her loop leaves her nothing, she lies off it, the sea closes it, or on a review lap (0197's rule, the live line:
  `if i = 0 and v_choose and (v_net <= 0 or v_off or v_sea or sr.lap_no % greatest(v_review, 1) = 0)`). A laid-up merchant is by definition one whose
  loop leaves her nothing. So **every ask prices up to sixteen more loops**, each leg through the leg planner and its quotes.
- Prod's own lap starts agree. A lap start's plan is 632-679 ms on average, and one lap in six is a review (`npc_route_review_laps` 6): if a
  one-loop plan is about 420 ms, the sixth must be about 1,800 ms for that mean. The job's 12-20 s for 8-14 asks is 1.4 to 1.5 s a plan.
- On the cached world the full plan is about 300 ms (measured, below), so prod is about five times slower on it, as elsewhere.
- **0406 is not it**: `public.port_fee` is asked once a leg and kept; a plan measured 296 ms before 0406 and 294 ms after on the cached world. I did
  not measure it against prod's regard and tax rows.
- **The open step's 1.5 s is not explained by its work.** A lap start's open, the same `cmd.advance`, reads 180 ms on prod. The job's `open_ms`
  included its wait for the quay behind the beat. 0407 times that wait apart (`quay_ms`), so the first read after the deploy says which it is. No
  prod query is needed before the deploy: the receipts already give the figures above.

## The design

1. **The due rule backs off, in its one place.** `public.npc_waiting_queue` (0182) is the one answer to who waits and who is due; the beat's hand,
   the job and the reconcile all read it. It now makes a merchant due `npc_replan_every_minutes` x 2^(refusals in a row - 1) after her last ask:
   10, 20, 40 minutes, capped at `npc_replan_within_minutes` less one step: **50**, not 60.
   - Why 50: at 60 she would be due at the very minute the hourly reconcile calls her overdue. The reconcile would then plan the long-refused
     itself, inside its 60 s budget. Ten minutes ahead, the job reaches her first.
2. **The count has one writer, the planner.** `npc_fleets.refused` (new, 0). `public.npc_plan` adds one exactly where it decides "she waits in
   port" (0181's lines) and sets it to 0 where a loop pays at a lap start. Whoever asked (the lap start, the job, the beat's hand, the reconcile),
   the count is the planner's own answer. A merchant newly laid up has 1: asked in ten minutes, as 0405 won. A merchant who sails starts afresh.
3. **A broke house waits the longest at once.** Purse under `npc_ask_broke_under` (100 d.): due at the cap from her first refusal. Her purse is
   read live, so a gift lifts the rule.
   - Asked for: "not asked by this job at all (the hourly reconcile keeps her)". Built: asked once in fifty minutes, by the job. If the job never
     asked the 25 broke houses, each would turn overdue and the reconcile would plan all of them every hour: about 40 s of its 60 s budget. One ask
     in fifty minutes each is under a second a minute for all of them, and a gift is still noticed within the hour.
4. **The job says what the quay cost it** (`quay_ms`, `quay_ms_max`), no longer inside `open_ms` nor counted against the budget.
5. **`npc_ask_job_ms` 20,000 to 12,000** (only if it still holds 0405's 20,000).

**Not built:** resetting the back-off when her harbour's quotes move, and a pre-test "her best leg's spread has not moved, so still no". Both need
a second answer to "does a loop pay" beside the planner's. The back-off is that pre-test without the second answer: after three refusals the
market must be asked again, but only once in fifty minutes.

## Measured (the cached world at head 0406 with 0407, `scripts/ops/harness/ask-backoff/measure.mjs`)

The line staged in its steady state: 35 merchants newly laid up (one refusal, last asked 0 to 10 minutes ago; prod resumes 2 to 5 a minute, so
about as many are laid up) and the rest refused four times (last asked 0 to 50 minutes ago). The job called as pg_cron calls it, with its
commits, for one clock minute:

| line | due in the minute by the rule | asked | work spent here | under the old rule, due a minute |
|---:|---:|---:|---:|---:|
| 150 | 5.5 | 7 | 2.1 s | 15 |
| 250 | 7.4 | 9 | 2.5 s | 25 |

(A plan here: 262 to 271 ms; an open 26 ms; `quay_ms` 0 to 1: nothing else holds the quay in this world.)

**Expected on prod**, from prod's 1,450 ms a plan, the long-refused refused again and the new ones resumed:

| line | with an open at 200 ms (a lap start's) | with an open at 1,700 ms (as read, wait in it) | old rule, the same line |
|---:|---:|---:|---:|
| 150 | 9.1 s a minute | 14.4 s | 22 to 28 s |
| 250 | 12.0 s a minute | 17.3 s | 37 to 42 s |

**The target of under 6 s a minute is not met, and cannot be by a back-off alone.** The asks of the long-refused fall from 11.5-21.5 a minute to
2.3-4.3. What is left is the merchants who do wake: 3.5 a minute at 1.45 s a plan is 5 s a minute before anything else, and that plan is the one a
lap start would have cost. The job's work should about halve at today's line. If the open's 1.7 s turns out to be the wait for the quay, the
lower column holds.

**The budget, 12,000 ms:** it covers a line of 150 with room and a line of 250 if the opens are cheap. It also caps the harm if the estimate is
wrong: the job can no longer take 20 s of a minute. If `due_left` grows with `spent_ms` pinned at 12,000, the owner raises it.

## Proof

- **The file's self-assert**: each of the seven hunks once and reversing; grants, volatility, definer, search path, owner unmoved; no other
  function moved; the column and the knobs. Then one merchant's rows in a rolled-back sub-transaction: the steps by the queue itself
  (10 10 20 40 50 50, a broke house 50, the rule off 10), and ONE plan of a house with an empty purse: she waits and her count goes 2 to 3.
  450 ms on the cached world. Fails above 15 s.
- **Proof 102** (7 markers, 4.5 s): BO_STEPS; BO_COUNT (the planner lays an empty-pursed house up with 1; asked by the job 2 and due at 20, then
  3 and 40); BO_RESET (of ten staged at 3 and asked, those who paid have 0 and those refused 4: 5 and 5); BO_BROKE (not asked 11 minutes after her
  ask, due at 50, overdue at 60, with the knob at 0 due at 10); BO_NEW (208 in the line, 200 refused four times: the pass asks one merchant, the one
  newly laid up 10.5 minutes ago); BO_ONE (the beat's hand asks 0 by the same rule, and finds them due at 51 minutes); BO_QUAY.
- Proofs 12, 100 and 101 green with the file applied.
- `before.sql` / `after.sql` pass the read-only reader and run on the cached world; the rollback draft reverses the seven hunks there (its first
  cut removed a variable before its use and was refused by the engine; fixed).

## PROD CHECKS

1. Before: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/ask-backoff/before.sql`. Wanted: head `20260818000406`, `applied`
   false, `hunks` every count 1, volatility `s` / `i`. Write down `job`, `beat`, `lap_starts`, `line`.
2. Deploy: `~/bin/bv-deploy.sh <pr>`. Expected time on prod: under 8 s (the column is added with a default and no rewrite; one plan of one merchant,
   about 1.5 s, rolled back). Budget 30 s; fails above 15 s.
3. After, at +30 min, +2 h, +24 h: `... -f scripts/ops/harness/ask-backoff/after.sql`. The back-off needs about an hour to settle (everyone starts
   unrefused). Wanted: `job.asked` falling toward 5 to 7 a minute; `job.spent_ms` no longer pinned at the budget; `due_left` 0 or a handful;
   `line.first_oldest_min` near 10 (what 0405 won holds); the beat's mean and p95 back toward 442-555 ms and 1.5-2.0 s; lap starts' late back
   toward 41-46 per ten minutes. Read `job.quay_ms` against `job.ms_an_open`.
4. If not: `npc_ask_job_ms` 0 stops the job; `npc_ask_broke_under` 0 lifts the broke rule; the forward rollback draft is `rollback-0407.sql`.

## Not verified

- Prod: every prod figure after the deploy is arithmetic from the reads above.
- The mix of the line. The estimate assumes the long-refused are refused again and the new ones wake. If refusals are spread evenly over the
  line instead, a back-off spreads the same asks over a longer stay and saves less. Read against it: half the laid-up had closed no lap for over
  an hour (106 of 203 under one hour, the first lay-up read), which an even 30 % chance an ask could not produce.
- That the line does not grow because the long-refused are asked less often: a merchant whose market turns waits up to fifty minutes for it.
- Why the open reads 1.7 s. `quay_ms` will say.

## Decided by default

1. The cap is 50 minutes, not 60 (above).
2. A broke house is asked once in fifty minutes by the job, not left to the reconcile (above).
3. `npc_ask_job_ms` 12,000.
4. The count is written by the planner alone.
5. No news row: nothing a player reads changes.
