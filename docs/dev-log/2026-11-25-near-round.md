# 2026-11-25 — `near-round`: 0499 (dark: `near_round_enabled`), proof 201

**Renumbered 2026-11-25: this file was 0498 and is 0499.** 0497 is `a-wreck-can-sell` (urgent, off main); the stack moved up by one (jobs-never-lose 0498, near-round 0499, fit-to-sail 0500). The numbers below are the new ones; the measurements were taken under the old.

Stacked on `jobs-never-lose` (0498). Server only here; the client half is on `hq-figures`. Nothing touched production; no knob but
the new switch.

## What it is

A `best` job with `{within: nm}` (and an optional `base` harbour; her home by default). **The best plan, extended: no second planner.**

- Each run: the best paying card of `world.best_sales` where she lies, by profit a second, whose lines (0494's harbour legs,
  `public.sale_lines`) are within her miles. Never at a loss: a profit above nought, for the units the sale's harbour takes (0498).
- Nothing pays: away from her base she sails to it; at her base she waits as 0498 waits (asked again 10 minutes on, not stopped).
- The door (`cmd.set_fleet_job 'best'`) keeps `{within, base}`; `within` is held between 50 and 3,000 nm in the function (no knob).
- `world.actions` offers it first: `sea:near`, "Trade near Lisbon", the door's job `{within: 1440}`.
- `world.workers`: her action is `sea:near` with `within`, `base` and `sentence`.

## Its per hour: none is served (basis `none`)

A round's hour is what the next harbours pay. Only a `world.best_sales` read at each of them can say that (about a second each), so
a day of it cannot be simulated inside a read; and one card over its seconds is wrong by tens of times (0496's Best-run
measurement). So it could not be put within 15 % of measured, and it carries no rate until her own runs give one (basis `runs`,
0496: after three buys).

## Not done, said

"Prefers legs that end where something pays": what pays at a card's far end is a `world.best_sales` read there, and the plan makes
one such read (where she lies). She takes the best card within her round and comes home when nothing pays. Measured, that already
passes the bar.

## Measured: the real job, the real tick, three game days that turn (local PGlite, rolled back)

`scripts/ops/harness/hq-figures/measure-near.mjs`. A fresh Barca, 40,000 coin, `{within: 1440}`, 0498 lit.

| Home | Near round | Waiting Repeat (same world, `measure-cap.mjs`) | selling runs a day | kinds | sails home | runs that lost coin | plan, mean / max |
|---|---|---|---|---|---|---|---|
| Lisbon | 19,753/h | 3,328/h | 22.7 | 29 | 46 | 0 | 489 / 1,031 ms |
| Amsterdam | 2,723/h | 562/h | 10.7 | 20 | 21 | 0 | 394 / 716 ms |
| Venice | 16,070/h | 2,917/h | 10.0 | 18 | 20 | 0 | 412 / 957 ms |
| Genoa | 13,263/h | 555/h | 20.3 | 33 | 38 | 0 | 470 / 1,089 ms |
| Nagasaki | 8,523/h | 148/h | 14.3 | 30 | 23 | 0 | 450 / 1,172 ms |

- 5 to 58 times the waiting Repeat. No run lost coin in 234 selling runs. It matches the harness's own loop of the day before
  (20,198 / 2,749 / 13,891 / 6,719 / 7,467).
- About two of every five sails are the empty sail home.
- The plan is one `world.best_sales` read: 0.4 to 1.2 s on PGlite. One plan a job a tick.

## Checked

- 0499's self-assert on the snapshot at 0498: passed. Proof 201: 7/7. Proofs 200, 199, 184, 195, 197: pass.
- `tsc -b`, eslint, `vite build` (the browser image with 0499), `db.budget`, `news.lint`: passed.
- The before / after reads: `scripts/ops/harness/near-round/`.

## Decided by default (the owner may reverse)

- `within` is offered at 1,440 nm and held between 50 and 3,000.
- No rate is served for the round (above).
- Lit without 0498's switch the round still runs, but its cards are not cut to the sale harbour's allowance.

## Not verified

- Prod: nothing was read. `tests/rpc.surface.spec.ts` was not run locally. The plan's time on real Postgres.
- Other traders, the price drift inside a day, world events: not in the local world. One run a row.
