# 2026-11-25 — `hq-figures`: a repeating run's per hour is its day's (0496 edited before its deploy)

The lead: *"a sample option read +536,213/h from one 225-unit quicksilver run; measured repeats fall about 6 % a run. Decide from the
code whether per_hour for a repeating job overstates, measure it, and if it overstates by more than 15 % fix it inside 0496."*

0496 was not deployed, so it is edited in place (branch `workers-read`). Nothing here touched production.

## What the code said

`public.action_shape` served `per_hour = net x 3600 / interval_s` of ONE run. For a run set to repeat that is wrong four ways, each
the server's own rule:

- **The job tick.** A job's fleet lying idle in port is started by `public.tick_fleet_jobs`, every 2 minutes. A fixed run waits for
  it twice a cycle (at the sale's harbour, then at home): 120 s on average that the interval left out. A near run of 135 s is really
  about 255 s.
- **The quay's own walk.** `world.quote` walks the stock shelf by shelf, and stock returns only at the game day's turn. So the second
  run buys dearer and sells cheaper than the first, and so on.
- **The mark a sale leaves** (`port_goods.glut`, `cmd.do_sell`): every sale lowers the next sale's price there by
  `glut_per_depth x units / stock_target`.
- **The day's allowance** (`world.daily_cap_remaining`): 0.35 of the stock mark a good, a harbour, a company, a game day, at BOTH ends.
  A full hold spends it in 2 to 5 runs; the sale then takes only a part and the job stops with goods aboard.

A job set to repeat is not stopped by a loss: `public.fleet_job_plan` buys ALL and sells ALL each time.

## Measured (local PGlite, the chain's cached world, everything rolled back)

`scripts/ops/harness/hq-figures/measure-repeat.mjs`: a fresh company at Lisbon takes a run from `world.actions`, sets it through
`cmd.set_fleet_job`, and the REAL tick runs it back to back (each voyage's stamps moved into the past, `world.fleets()` settles the
arrival: proof 184's way). Ten runs were asked for; the day's allowance stopped every near run before the tenth. Coin is her
ledger's. "Measured" is the whole runs' coin over the game day (14,400 s here), because she then stands until the allowance returns.

| Run (Lisbon to Setubal) | Purse | Whole runs before the stop | First run | Served before | Measured | Served now |
|---|---|---|---|---|---|---|
| Quicksilver, 225 to 247 units | 5,000,000 | 3 | +20,765 | **+537,909 /h** | -13,484 /h | -13,605 /h |
| Raw silk, 200 units | 5,000,000 | 4 | +8,671 | +234,794 /h | +116 /h | +75 /h |
| Black pepper, 300 units | 5,000,000 | 2 | +2,140 | +57,224 /h | -314 /h | -327 /h |
| Cork, 150 units | 5,000,000 | 5 | +576 | +15,432 /h | -142 /h | -154 /h |
| Raw silk, 80 to 100 units | 40,000 | 8 | +4,105 | +132,876 /h | +419 /h | -183 /h |
| Black pepper, 230 to 270 units | 40,000 | 3 | +2,090 | +62,985 /h | -831 /h | -904 /h |
| Porcelain, 70 to 100 units | 40,000 | 5 | +1,476 | +48,933 /h | -2,519 /h | -3,050 /h |

- **Before: every figure overstated, by hundreds of times, and its sign was wrong for five of seven.** The quicksilver run's second
  run already lost 12,545; its fourth sold only a part (`E_DAILY_CAP`).
- **Now: no figure overstates.** Each is at or a little under what was measured: by 1 to 9 % where the run's units held, and by a few
  hundred coin an hour where a small purse grew and bought more each run (the rule prices every run at the first run's units).
- "About 6 % a run" (the economy plan) was one purse-bound pepper run. A full hold falls far faster: the second run loses.

**The Best run** (ten runs, each another sale from another harbour): served +528,596 /h and +119,177 /h; measured 7,715 /h (it stopped
at the sixth for crew) and 1,850 /h. One card over its seconds is not a rate, so the Best run is now served with NO `per_hour`.

## What changed in 0496

- `public.run_day` (new, STABLE, server only): one run repeated over one game day by the server's own rules. Whole runs = what the
  day's allowance takes at both ends, what the buying quay holds, and what the day's length has time for. The buys of n runs cost
  what `world.quote` says ONE buy of n x units costs (the quay's own walk); the sales the same, scaled for the mark each sale leaves
  (`public.press_after`, the one rule) while the quote does not walk the press itself. Each run pays the first run's costs; the
  profit tax (`public.profit_tax`) is charged on the runs that still gain. Stopped by the allowance, the time is the whole day.
- `public.action_over_day` (new, IMMUTABLE): the one place a repeating run's `per_hour`, `xp_per_hour` and `items_per_hour` are made:
  the day's coin, experience and units over the day's seconds. The day rides as `day {runs, coin, seconds, stop}`.
- `public.fleet_job_tick_s` (new, IMMUTABLE): 120, the job's period. `interval_s` now holds the waits: two half periods a run there
  and back and a bring-home, one for the Best run.
- A fixed run and a bring-home carry `day`, and their three rates are the day's. `net`, `interval_s`, `inputs`, `outputs` stay ONE
  run's (what Once does).
- The Best run, as an option and under way in `world.workers`: its sale's `net` and `interval_s`, and `per_hour`, `xp_per_hour`,
  `items_per_hour` null. Her own runs (basis `runs`) give its rate.
- The options are still ordered by `per_hour`: now the day's, so a far run that pays stands over a near run that loses.
- Self-assert and proof 199: a run's `per_hour` is its day's coin over its day's seconds, a day never reads better than its first
  run repeated, one run a day is that run, the Best run has no rate. Eleven functions (two reads, nine cores server only).
- The before / after reads (`scripts/ops/harness/workers-read/`) name the three new functions.

## Cost (local PGlite)

- `world.actions(fleet)`: 820 to 1,013 ms (it was 744 to 1,017; budget 1.5 s). A quote of 900 units is about 2 ms; a run of more
  than one a day asks two.
- 0496 on the snapshot at 0494: self-assert passed. Proof 199: 8/8. Proofs 184, 195, 197: 7/7, 5/5, 7/7.

## For the owner (not changed here)

- **A run set to Repeat goes on at a loss.** On a near run with a full hold the second run already loses, and the job then stops at
  the allowance with goods aboard. The honest figure says so (a loss an hour), but the job itself could stop when a run stops paying.
- **A board card can promise a sale the harbour will not take.** In the Best-run measurement a card said +555,908 and the sale left
  -13,840 (the day's allowance or the city's purse took only a part). `world.best_sales` is deployed and was not touched.

## Not verified

- Prod: nothing was read. The game day is 14,400 s locally; the rule reads `game_day_seconds`, whatever it is.
- The days after the first are not counted (stock returns toward its mark a game day at the harbour's restock rate, so a quay she
  empties every day pays less the next). The part run after the last whole one is not counted. Other traders are not counted.
- Far runs (longer than a game day) were not measured: the harness has one instant, so it cannot turn the day. Their figure is the
  one run's, as before, with the two waits.
- The dock turn was 0 s locally (the local economy is open).
- `world.actions` on real Postgres 17 was not timed.
