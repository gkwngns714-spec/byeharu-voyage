# 2026-11-25 — `jobs-never-lose`: 0498 (dark: `jobs_wait_enabled`), proof 200

**Renumbered 2026-11-25: this file was 0497 and is 0498.** 0497 is `a-wreck-can-sell` (urgent, off main); the stack moved up by one (jobs-never-lose 0498, near-round 0499, fit-to-sail 0500). The numbers below are the new ones; the measurements were taken under the old.

Stacked on `workers-read` (0496). Server only. Nothing touched production; no knob but the new switch.

## Measured first (local PGlite, real job tick, all rolled back)

Harness: `scripts/ops/harness/hq-figures/` (`measure-repeat.mjs`, `measure-day.mjs`, `measure-rotation.mjs`).

**One game day (14,400 s), a fresh Barca.** "Repeat as today" runs on at a loss; "waits" stops at the first run whose quote loses.

| Home | Purse | Best near run | Repeat as today | Repeat that waits | Best run (rough) |
|---|---|---|---|---|---|
| Lisbon | 40,000 | raw silk to Setubal | +421/h | +2,488/h | +12,019/h |
| Lisbon | 200,000 | raw silk to Setubal | +116/h | +2,847/h | +40,923/h |
| Amsterdam | 40,000 | gunpowder to Hoorn | -204/h | +702/h | +11,591/h |
| Amsterdam | 200,000 | gunpowder to Hoorn | -55/h | +802/h | +39,698/h |
| Venice | 40,000 | velvet to Ancona | +1,245/h | +3,129/h | -9,133/h |
| Venice | 200,000 | velvet to Ancona | +3,273/h | +4,189/h | +41,033/h |
| Genoa | 40,000 | armour to Toulon | +545/h | +724/h | +8,293/h |
| Genoa | 200,000 | velvet to Naples | -3,928/h | +2,557/h | -3,893/h |
| Nagasaki | 40,000 | soy sauce to Goto | +330/h | +371/h | +8,375/h |
| Nagasaki | 200,000 | soy sauce to Goto | +328/h | +372/h | +49,154/h |

The Best-run column has one instant for hours-long voyages (the day never turns) and counts unsold cargo as nothing: rough.

**Two game days that turn** (`measure-rotation.mjs`: the market clock's anchor moved on a day, every sale's mark aged a day, the
world's own `public.tick_market_drift` run: stock returns, the allowance is new). Not turned: the hourly drift, other traders, events.
"Rotation": each cycle the best paying card within 30 minutes of sailing, cut to the sale harbour's allowance, never at a loss; she
does not sail home.

| Home | Purse | Repeat that waits | Rotation | Rotation / Repeat |
|---|---|---|---|---|
| Lisbon | 40,000 | 2,264/h | 2,246/h | 1.0x |
| Lisbon | 200,000 | 2,344/h | 4,906/h | 2.1x |
| Amsterdam | 40,000 | 665/h | 3,786/h | 5.7x |
| Amsterdam | 200,000 | 673/h | 401/h | 0.6x |
| Venice | 40,000 | 1,222/h | 616/h | 0.5x |
| Venice | 200,000 | 3,875/h | 2,090/h | 0.5x |
| Genoa | 40,000 | 669/h | 362/h | 0.5x |
| Genoa | 200,000 | 272/h | 2,872/h | 10.6x |
| Nagasaki | 40,000 | 183/h | 2,837/h | 15.5x |
| Nagasaki | 200,000 | 188/h | 3,285/h | 17.5x |

**Rotation is not clearly better: at 40,000 it is over 3x at two homes of five and under 1x at two (the middle is 1.0x). Nothing was
built for it.** Where it loses she sails one leg to a harbour where nothing pays within 30 minutes and stands there (1 run in 2
days). Where it wins she makes 11 to 13 runs of 8 to 11 kinds. It never passes 5,000/h. A rotation that knew its way home, or looked
two legs ahead, might do better; that is a design, not a parameter.

## What 0498 does (lit; dark every body answers as before)

- **A fixed job that sells waits instead of losing.** At its buy harbour `public.fleet_job_plan` asks `public.fleet_run_quote`: the
  units she can buy cut to what the sale's harbour takes, `world.quote` both ways, `public.profit_tax`, and the trip there and back
  (`public.job_trip`). No profit: `{wait: low}`, nothing bought, nothing sails. `public.fleet_job_note` sets `next_at` 600 s on (the
  longer of that and `fleet_jobs_wait_s`): the job is not stopped, and `public.fleet_jobs_due` does not take it sooner, so one quote
  in 10 minutes at most. It starts by itself when the quote pays.
- A run already at its sale's harbour still sells. A bring-home is exempt.
- **A card is priced for what its sale's harbour takes today** (`public.sale_fit`, through `public.cards_fit`): the Best plan,
  `world.actions` and the HQ board read the cut cards. `world.best_sales` itself is not touched.
- **The HQ board's coin an hour is the day's** (`public.run_day`, through `public.cards_fit`); the ranking uses it; `profit` stays
  the one trip's.
- **`public.run_day` follows the job:** lit, the day is its gaining runs and ends at the first that would not pay (`stop: low`).
- `world.workers`: a fleet's row gains `wait {code, sentence, retry_at}`.

## Checked

- 0498's self-assert on the snapshot at 0496: passed (1.2 s). Proof 200: 9/9. Proofs 199, 184, 195, 197: 8/8, 7/7, 5/5, 7/7.
- **The Osaka case (proof 200, JW_OSAKA):** the card said 328 armillary spheres and +555,918; Osaka takes 153 today; cut to 153
  units and +313,782; the Best plan's line is `BUY armillary-spheres 153`.
- **Lit, through the real tick** (`measure-repeat.mjs --lit`), served against measured over the day:

| Run | Purse | Runs before she waits | Measured | Served |
|---|---|---|---|---|
| Quicksilver Lisbon to Setubal | 5,000,000 | 1 | +5,036/h | +5,034/h |
| Raw silk | 5,000,000 | 2 | +2,847/h | +2,845/h |
| Raw silk | 40,000 | 4 | +2,728/h | +2,713/h |
| Black pepper | 40,000 | 1 | +523/h | +521/h |
| Porcelain | 40,000 | 1 | +369/h | +367/h |

  The quote that made her wait said -441 where the run played dark had lost -425.
- Cost: the board 395 ms dark, 542 ms lit (three cards; the fit stops adding the day after 400 ms); the cut of twelve cards 10 ms.
- `tsc -b`, eslint, `vite build` (the browser image with 0498), `db.budget`, `news.lint`: passed.

## Decided by default (the owner may reverse)

- Everything in 0498 is behind the one switch, the board's new coin an hour too: the board is lit on prod, and its figure should not
  move at a deploy.
- A counted job (Once, N runs) waits too: a run at a loss is no better for being the only one.
- "Nothing to buy now" and "the day's allowance is spent" are the same wait, each with its own sentence.
- A board card whose day reads a loss keeps its place at the foot of its band (its one trip still pays).

## Not verified

- Prod: nothing was read. `tests/rpc.surface.spec.ts` was not run locally. No client reads `wait` yet.
- The days after the first in `run_day`. The hourly drift, other traders.
- `world.best_sales` at about 1.6 s on prod Lisbon: the added board cost was measured on PGlite only (+147 ms).
- The before / after reads: `scripts/ops/harness/jobs-never-lose/`.
