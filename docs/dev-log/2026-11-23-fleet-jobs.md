# 2026-11-23 — 0481 standing fleet jobs (dark: `fleet_jobs_enabled`)

`docs/design/hq-command-2026-11-23.md` section 2, v2: "Standing fleet jobs", "Land → yard carry" and "The away report" (owner idea 3).
The owner, 2026-11-23: "i want this game to be strategical game, where all the work(activities) are done in HQ - words with graphics.
choosing best options available, finding best options."

## What it does (lit)
- **One job a fleet** (`public.fleet_jobs`, the fleet is the key). Three kinds:
  - **best** ("repeat the best run"): each time she lies idle in port, her best paying sale from there. That is `world.best_sales`,
    the desk's own read, with v1's filter, ranked by coin an hour. The job takes the first of the best `fleet_jobs_runs` (12) whose
    every leg has a known course. Lines: `BUY <good> <units>` (none for her own cargo), `SAIL` through the passage's stops
    (`world.board_passages`), `SELL <good> ALL`.
  - **fixed** ("a fixed route", `{good, buy, sell, stops}`): at `buy` it sends `BUY <good> ALL`, `SAIL` to `sell`, `SELL <good> ALL`.
    Anywhere else she sails back to `buy`, first selling what she still carries of the good when she lies at `sell`.
  - **land** ("carry Land output to the yard", `{to, good}`): at the Land party's harbour it sends `TAKE <good> ALL` from the Storage
    the Land fills, `SAIL` to `to`, `STORE <good> ALL`. Anywhere else she sails back to the party's harbour. The party is collected first
    (`public.land_collect_for`).
- **A course is one already sailed.** The server cannot plot a course: `cmd.do_sail` refuses a SAIL with no course when land is in the
  way, and a straight line from Lisbon to any of its sales crosses land. So a job sails only a course already sailed and verified, in
  either direction (`public.fleet_job_course`). The sources, in order:
  1. a merchant lane (`public.npc_known_legs`);
  2. a coast course (`public.npc_coast_legs`);
  3. the newest voyage her own company sailed between the two harbours, ended or under way (`voyage.course_of` over the stored
     segments). This is what her chart plotted, returned exactly, read through the two partial indexes of a fleet's voyages (ended and
     sailing).

  `cmd.do_sail` judges the course again at every departure. A trip she has sent once by hand can be her job from then on.
- **The doors** are registered for signed-in players, check the owner, and refuse with the `{ok: false}` envelope. Dark, every door
  refuses `E_NOT_IN_USE`.
  - `cmd.set_fleet_job(fleet, kind, params)` refuses a fleet that is not hers, a bad kind, a fixed route with one harbour, and a fixed
    route whose leg out or back has no known course (`E_NO_COURSE`). It also refuses a fleet on a standing route (`E_ROUTE_TAKEN`): that
    route is her job already.
  - `cmd.clear_fleet_job(fleet)` takes the job away.
  - `cmd.fleet_jobs_seen()` marks the away report read, so its tallies start again.
- **The tick** is `public.tick_fleet_jobs(p_commit)`, a procedure that pg_cron calls as `byeharu-voyage:fleet-jobs` every 2 minutes. It
  never runs on the arrivals beat. Dark, it returns after one knob read. Lit, it takes the due jobs (`public.fleet_jobs_due`: the job is
  not stopped or waiting, and her fleet is DOCKED with nothing queued and on no standing route). It starts with the job that has waited
  longest, takes at most `fleet_jobs_per_tick` (4) of them, and starts no new plan after `fleet_jobs_budget_ms` (1,500). The first plan
  always runs. Each job runs in two transactions, as the lap-start job does (0266):
  - **(A) The plan.** It runs outside the quay, as her: the identity is set for that transaction only. `public.fleet_job_plan` is a
    STABLE read that returns one of:
    - the lines to send;
    - a wait, when there is nothing to do: the job is asked again `fleet_jobs_wait_s` (900) later;
    - a stop: the plan before failed when it ran, no known course, or the Land is shut.
  - **(B) The open.** It runs under the quay, in the gap after the second's beat. It locks her fleet, job and house with SKIP LOCKED,
    then checks again that the job is due and the fleet's version is unchanged. Then it calls `cmd.issue_lines` as her. A refusal stops
    the job on the server's code; `E_STALE` is tried again at the next run.

  Each lit run writes one receipt into a ring of 720 slots (`public.fleet_job_runs`).
- **A stopped job waits for her.** A plan whose lines fail when they run stops the job at its next turn, with that order's own code
  (`cmd.release_failed` has already cancelled the rest of the plan). Setting the job again starts it.
- **The read** is `world.away_report()`: STABLE, registered. For her company it returns, for each job:
  - its kind and settings;
  - its state: working (at sea by `public.fleet_state`, or orders queued), waiting, or stopped;
  - the runs it started since she last pressed OK;
  - `earned`: her fleet's ledger rows since then, with FOUNDING and probes left out, as `world.report` does;
  - its last act, or the code it stopped on.

## Client (HQ, lit only; dark nothing new is drawn)
- **While away** stands at the top of HQ (`features/city/board/JobsAway.tsx`). It shows only when something happened. Each job gets one
  line: the kind's glyph, her whole name, ×runs, then the coin she made, or the code it stopped on. Under the lines, a total and OK.
- **Each fleet row** gets the job's mark and a setter (`JobControl.tsx`):
  - the mark is the kind's glyph (a trophy for the best run, a route for a fixed route, a pick for the Land haul) in the tone of its
    state (working green, waiting muted, stopped red), with ×runs;
  - the setter is two chips, Best and Land (plus Fixed once one is set). Pressing the chip that is on takes the job away.
- **A trade card** offers **Repeat**, which works in one press:
  - On a served card it first sends the trip through the card's own act, the same as pressing the card. Then it sets that trip (her
    port, the sale's harbour, the passage's stops) as her fixed route. The voyage now under way is the course the route keeps, so a trip
    no merchant lane covers can still be repeated.
  - On v1's card it sets the route alone.
  - The chip is on while that trip is her job. A refusal stands under the card in the server's own words.
- **The read** is `live/useAwayReport.ts`. It is asked when HQ opens, when one of her fleets acts (a new version), and after a press
  here. It is never asked on the beat. A dark answer is kept a minute.
- **Screens:** headless shots at 390 and 1280 are at
  `C:\Users\gkwng\AppData\Local\Temp\claude\f5388e2006711d23\20c3c33b-2e64-4a9f-9933-ae93974d7413\scratchpad\hq-jobs\` (`jobs-390.png`, `jobs-1280.png`, local to the PC that took them). `tests/hq.board.spec.ts` covers them: "standing
  fleet jobs (0481, lit)" checks that Best sets the mark and that a served card's Repeat sends the trip and keeps it as a working fixed
  route. It also checks that nothing scrolls sideways and that every press is at least 44 px.
- **Words** (EN / KO, `dict/hq.ts`): Job, Best run, Fixed run, Land haul, Working, Waiting, Stopped, Repeat, While away, {n} runs, OK.

## Measured
- **Local chain (PGlite), proof 184.**
  - One run with one best job at Lisbon: **~0.5 s**. The plan is ~0.47-0.53 s: `world.best_sales` ~0.44 s, `board_passages` ~0.08 s,
    and the course lookups a few ms. The open (`cmd.issue_lines` under the quay) is **~20-35 ms**.
  - The self-assert takes about half a second.
- **Prod (`before-0481`, the one read, 2026-11-23).** Head 0480. The hunk's anchor occurs once and its new marker is absent.
  - One `world.best_sales` for the newest company's oldest idle fleet took **2,757 ms** (`cut`: its own 2.5 s budget ran out), with 8
    paying sales. One `world.board_passages` took **274 ms**, and the known legs out of her harbour **10 ms** (20 legs).
  - There are 19 companies and 18 idle fleets, at most 1 to a company.
  - **0 of her 8 paying sales end at a harbour a merchant lane reaches directly.** This is why her own voyages became the third course
    source (above).
  - So a best job's plan on prod is about 2.8 s + 0.3 s + ms. With the 1.5 s budget, a run that starts with a Lisbon-sized plan starts
    no second one. A run stays under about 1.5 s + 3.1 s + 0.3 s + at most 1.5 s of gap wait, every 2 minutes, in its own session.

## Load (budget lines in the file)
- **Two new tables.**
  - `fleet_jobs` holds one row a fleet (its key, deleted with the fleet).
  - `fleet_job_runs` is a ring of 720 rows.
- **One new cron job**, every 2 minutes.
  - Dark, it writes 0 rows.
  - Lit, a run starts at most 4 jobs and writes under ~60 rows (each started job's 3-6 orders and what they do as they run, its job
    row, one receipt). That is about 30 rows a minute at the very most, and nothing while no job is due.
- **No step on the arrivals beat.**
- **Read the gate before lighting it.** With 18 idle fleets on prod, a lit switch alone starts nothing until a player sets a job.

## Decided by default (the owner may reverse)
- **The kinds.** "Repeat best run" is `best`. "A fixed route" is `fixed` (`{good, buy, sell, stops}`). A player's existing standing route
  is not wrapped: a fleet on a route is refused a job (`E_ROUTE_TAKEN`), because the route is her job.
- **Courses are only courses already sailed:** merchant lanes, coasts and her own voyages. The server plots none. A best run tries the
  12 best sales by coin an hour for one it can sail. With none it waits 15 minutes.
- **Fixed buys ALL, and sells ALL.** A best run buys the units `world.best_sales` priced.
- **The Land haul's yard** defaults to the nearest harbour, by remembered lane, with a building yard and a warehouse, other than the
  party's own harbour. The good is the party's own, remembered once seen.
- **The cadence:** every 2 minutes, at most 4 jobs a run, a 1,500 ms budget, 15 minutes between asks when there is nothing to do.
- **A plan that fails when it runs stops the job,** so it never loops on a refusal. Setting the job again restarts it.
- **The away report's window** is "since she last pressed OK" (`cmd.fleet_jobs_seen`), not a device's last visit. The existing
  route-and-purse "While you were away" overlay (`app/AwayCard.tsx`, local to the device) is unchanged.
- **The fleet row sets Best and Land.** A fixed route is set from a trade card's Repeat, because it needs the card's good and harbours.
  On a served card, Repeat sends the trip first, so its voyage is the course the route keeps.
- **A fixed route with stops** needs a sailed course for every leg, out and back. The voyage under way covers only its first leg, so
  such a Repeat is refused (`E_NO_COURSE`) until each leg has been sailed.
