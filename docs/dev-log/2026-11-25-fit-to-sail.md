# 2026-11-25 — `fit-to-sail`: 0499 (a repair, no switch), proof 202

Stacked on `near-round` (0498). Server here; the client half is the branch `fit-client` (on `hq-join`). Nothing touched production:
no prod read was run. No knob or switch is changed.

## The lead's prod facts (24 Nov, after 0494 went live 17:40 UTC)

One company, one fleet docked at Island of Mozambique (towed there after a ransom on 23 Nov).

- **A.** Her stopped land job was retried: the tick said ok, runs 1, and two minutes later the job stopped with
  `E_FLAGSHIP_DISABLED`, "the flagship is not fit to sail". HQ showed no way to mend it.
- **B.** That tick took 10,659 ms (its plan 3,055 ms), against 40-120 ms.

## A: the cause (read in the bodies, then reproduced to the letter)

- The only place that asked whether her flagship is fit was `voyage.sail_refusal`, when a SAIL runs. `public.fleet_job_plan`,
  `cmd.issue_lines` and the job door (`public.fleet_job_set_for`) asked nothing of her hull.
- So the tick planned seven SAILs, `cmd.issue_lines` queued them and counted the run, `cmd.advance` ran the first, it was refused,
  `cmd.release_failed` cancelled the other six, and the next run's plan read that failed order and stopped the job on its code.
- A stop on that code waited for the player for ever (0494 retries only `E_LEG_TOO_FAR` and `E_ENDURANCE`).
- Local, before the hunks (`profile-tick.mjs --wreck`): tick 1 `started 1`, runs 1, orders 7 (1 failed `E_FLAGSHIP_DISABLED`, 6
  cancelled); tick 2 `stopped 1`, the job stopped on `E_FLAGSHIP_DISABLED`. The report.

## C: short of crew is the same class (the lead, 25 Nov: "Crew 7 / 8" after a raid)

- The sail has two gates that no harbour between mends: her crew, then her flagship. `public.fleet_unfit` is both, lifted whole and
  in their order; `voyage.sail_refusal` asks it for both (one hunk). Its answer for crew is the sail's own: `E_CREW_SHORT`, "Crew 7 /
  8", with the figures.
- **Where crew can be hired she WAITS** (`last.wait = E_CREW_SHORT`), nothing issued, no run; manned, the next run starts her.
- **"Where crew can be hired"** is `public.port_hires(port)`: hands on the quay (`crew_pool` above 0). That is the fact
  `cmd.do_hire` refuses `E_CREW_POOL` by, lifted; the hire door asks it there now (one hunk). No building is asked: the hire door
  asks for none.
- **Where none can be hired her job STOPS** on `E_CREW_SHORT` (nothing issued): she cannot mend it where she lies and cannot sail
  to where she could. It goes on once she is manned (a quay's pool is never refilled by a tick: 0097's note).
- A job already stopped on `E_CREW_SHORT` (the reported one) goes on at the first run after she is manned, as for the flagship.
- The door refuses a new job for her, with the figures.
- The Inn's price (`public.crew_hire_cost`): one hand at Island of Mozambique for a starter Barca is 100 coin (local).

## D: "Order 200 was refused ... Gaivota is free", read six hours late (the owner, 24 Nov about 23:43 UTC)

- Where: the note at the head of a fleet's queue (`src/features/command/Queue.tsx`: her sheet over HQ, the Trade desk).
- Why "late": it was not late. A refused order stays in the served queue until dismissed (0186; `cmd.queue` serves pending, active
  and failed rows) and the note announced any failed row each time the sheet opened, with no time. Order 200 failed at 17:40; she
  was repaired at 23:36; at 23:43 the record still read as news.
- Server half, here: `cmd.queue` serves `at` (`orders.executed_at`) on every row (one hunk). No other key moves.
- Client half, branch `stale-refusal`: a refusal whose cause is mended (the flagship has a hull, no ship lacks hands) or that is
  older than her standing job is a row with its time, not a note and not a "stuck" dot; a fresh one names the fleet (no order
  number) and carries Repair / Hire crew.

## The fix (one rule, no second one)

- **`public.fleet_unfit(fleet)`**: the sail's own flagship gate, lifted whole out of `voyage.sail_refusal`, which now asks it (one
  hunk: the same place in the gate order, the same answer). The sail, the tick and the door ask one rule.
- The state rule (`public.fleet_state_of`) and this rule are not the same question. Wrecked there means no hull above 0; a fleet with
  a dead flagship and a live escort reads `port` and still cannot sail. Every fleet the state rule calls wrecked is unfit (her
  flagship is one of her hulls); proof 202 holds both.
- **The plan:** a docked, idle fleet that is not fit is not planned: `{wait: unfit, code, sentence}`. No course is read, no leg
  judged, no line issued, no run counted.
- **The wait** (`public.fleet_job_note`): `last = {wait: E_FLAGSHIP_DISABLED, sentence}`, asked again 10 minutes on. Not stopped.
- **Going on by herself** (`public.fleet_jobs_due`): a job that waits for her repair is due at the first run after she is fit (not
  10 minutes later). A job ALREADY stopped on the code (prod's row) is due once she is fit; its stop and its failed plan are lifted
  when it is asked, whatever the new plan says (so it cannot loop on the old failed order). Neither is asked while she is unfit.
- **The door:** `cmd.set_fleet_job` refuses a job for her: `E_FLAGSHIP_DISABLED`, "the flagship is not fit to sail".
- **`world.workers`:** not hunked. Her row already serves `wait` from the job's `last` and `next_at` (0497): it reads
  `wait {code: E_FLAGSHIP_DISABLED, sentence, retry_at}`, state `waiting`, `worker_state` wrecked. A job stopped on the code keeps
  `stop {code, sentence}`.
- Fifteen hunks over nine bodies, two new STABLE server-only functions (with C and D above).

## What a wrecked company must do today (read in the bodies; proof 202 plays it)

- **The door:** the order `REPAIR` (the Shipyard's tray: `cmd.preview` for the price, `cmd.issue` to pay), which runs
  `cmd.do_repair`. `REPAIR TO <per cent>` mends less for less.
- **Where:** only docked at a harbour with a shipyard (`public.port_has_shipyard`: 117 of the 254 harbours in the chain's world;
  Island of Mozambique has one). A tow (`public.tow_for`) always ends at the nearest yard, so a towed fleet lies at one.
- **The price** (`public.fleet_repair_cost`): hull points to mend x `repair_rate_per_point` (10) x (1 - the port's industry %) x
  her running-cost factor x (1 - her Shipbuilding perk) x `running_cost_level` (0.2), plus her worn fittings' repair in full
  (`public.gear_repair_quote`, whatever the per cent asked). A starter Barca from 0 hull at ISL: **736 coin** whole, **74** for
  `REPAIR TO 10` (local).
- **Time:** she is `REPAIRING` for the damage's per cent x `repair_sim_hours_per_pct`, then docked again. The job is not asked
  while she is in the yard.
- **A purse that cannot pay:** refused whole, `E_INSUFFICIENT_FUNDS`, "Money 0 / 736". Nothing is mended, nothing is owed. There is
  no credit for a repair and no part payment; the player must ask for a lower per cent herself.
- **Can a company be stuck for ever? Yes.** A company whose every fleet is unfit, whose purse is under the price of the smallest
  repair that leaves the flagship above 0 (a few coin of hull, plus ALL her worn fittings), and which has nothing to sell (cargo
  aboard sells where she lies; her Storage; a land party's haul) has no way to earn. I found no gift, loan or free repair for a
  player's company: the broke-merchant gift is the merchants' (0408), the forced-home donation is for a fleet out of stores at sea
  (0279), a tow needs `UNABLE_TO_SAIL` and coin. Not checked: dividends and investment income as a way out. This file does not
  change that; it is the owner's to decide.

## B: the ten seconds (not reproduced; say so plainly)

`scripts/ops/harness/fit-to-sail/profile-tick.mjs` (the reported scene on the chain's world, the four switches lit; local PGlite):

| Part | Before | After |
|---|---|---|
| The tick, healthy fleet, 7 SAILs (plan + open) | 74 ms (plan 54, open 20) | 58 ms (plan 41, open 15) |
| The same with every cached plan thrown away (`--cold`) | 93 ms (plan 65, open 26) | 64 ms (plan 44, open 18) |
| The tick, wrecked fleet | 45 ms (plan 37, open 8), then a stop | 2 ms (plan 1), then nothing asked |
| The plan alone | 40-52 ms | the same healthy; 0.3-0.5 ms wrecked |
| of it: the pathfinder (`voyage.reach_passage`) | 20-30 ms | unchanged |
| of it: 8 courses measured and judged (`fleet_job_leg_shut`) | 3.1-3.6 ms each | unchanged |
| The open: `cmd.issue_lines`, 7 lines | 10-23 ms (parse 0.6-1.0, reach gate 1.0-1.6 ms a line) | unchanged |
| The same scene with `sea_conditions_bite` lit | plan 113-120 ms (pathfinder 89 ms) | unchanged |

(Before / after differences on the healthy rows are run-to-run noise: no hunk touches that path except three clock reads.)

- **The reported tick is 140 to 230 times what the same scene costs here, in every part, warm or cold. I could not reproduce it and
  I do not know where prod's ten seconds went.** Nothing measured says the SAIL lines are the cost (about 5 ms a line, plan and
  open together), so no line is split across ticks: that would change what a fixed job does at a harbour between, for no measured
  gain.
- What changes for prod: a fleet that cannot sail is no longer planned at all (one flagship row read), so THIS tick cannot recur.
  A healthy seven-leg job costs what it cost.
- **The receipt now names its parts**, so the next slow tick says where it went: a step carries `collect_ms` (a land job's
  collect; it was hidden inside `plan_ms`), `wait_ms` (the wait for the gap after the beat, up to 1,500 ms; it was in no figure)
  and `quay_ms` (the wait for the quay lock; it was hidden inside `open_ms`), beside `plan_ms` and `open_ms`.
- **Not measured, and where I would look first with those stamps:** the quay lock held by a slow arrivals beat; the land collect
  of a party away since the 23rd; disk reads on a cold cache (the stored courses, the miles matrix, the raster
  `voyage.segments_from_course` unrolls 16 times in such a tick); prod's PG 17 plans and its shared CPU. PGlite is one in-memory
  WASM Postgres 18: none of those exist in it.

## Checked

- 0499's self-assert on the snapshot at 0498: passed (434 ms). The scene before and after: a healthy fleet's plan identical
  (`33139d1d`, the seven SAILs); the sail's refusal reads as it did.
- Proof 202: 10/10 (FS_CREW, FS_NO_HANDS, FS_QUEUE_AT added). Proofs 29, 143, 150, 183, 184, 185, 186, 195, 197, 198, 199, 200, 201 pass with 0499 on the chain rebased onto `near-round` (0495-0498). Proofs 02, 05, 09, 61 and 65 (they touch crew or the queue) were NOT run: they need `proof.mjs`'s own helper schema or several statements, which this reader does not give; CI runs them. (All run one at a time through
  `hq-figures/q.mjs`, which writes no snapshot and prunes nothing.)
- `tsc -b`, eslint, `db.budget`, `news.lint`: see the commit.
- The before / after reads: `scripts/ops/harness/fit-to-sail/before-0499.sql`, `after-0499.sql` (their selects run on the local
  world).

## Decided by default (the owner may reverse)

- A job already stopped on the code is NOT turned into a wait by the migration: it stays stopped (HQ shows Repair) and goes on
  after her repair.
- The wait is asked again every 10 minutes while she is unfit (a constant, as 0494's); mended, at the next 2-minute run.
- The door refuses every kind of job for an unfit fleet, a land job too.
- Short of crew where no crew can be hired, the job stops (it does not wait): nothing she can press where she lies mends it.

## The two `duplication.spec` reds in this worktree (diagnosed; not this slice's)

- `no raw palette literal`: `src/features/city/board/RateWhy.tsx:145`, `bg-black`. `no class recipe is hand-written twice`:
  `RateWhy.tsx:165` repeats `components/ui/Detail.tsx:150`'s close-press recipe.
- Both lines came in with b0247734, the `rate-why` BRANCH's own commit of 0493, which this stack (`workers-read` ->
  `jobs-never-lose` -> `near-round`) is built on. Main's 0493 is the squash 664fa466 (#856), whose `RateWhy.tsx` has neither
  (the PR fixed them before it merged), and b0247734 is not an ancestor of main.
- So they are red on every branch of this stack and green on main; they go when the stack is rebased onto main. Nothing in 0499
  touches a screen.

## Driven (the client half, `fit-client`, with this migration in its world)

Headless, 390 x 844 and 1440 x 900, a lit local world, the founding company with a wrecked fleet and an undermanned one, a Best job
each: `C:\Users\gkwng\dev\fit-shots\` (the drive itself is `fit-drive.spec.ts` there; it is not a CI spec: the client branch
has no 0499 in its image).

## Not verified

- Prod: nothing was read. Whether Island of Mozambique has a shipyard on prod (it has in the chain's world, and a tow ends at one).
- `vite build` and `tests/rpc.surface.spec.ts` were not run in THIS worktree (a build prunes the shared snapshot cache). The
  client worktree built this chain against a private copy of the cache: the browser image applies 0496-0499 and their self-asserts.
- The ten seconds (above).
