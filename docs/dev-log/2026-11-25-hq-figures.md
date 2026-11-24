# 2026-11-25 — `hq-figures`: HQ reads 0496 (client)

Branch `hq-figures` = `hq-join` + `workers-read` (0493, 0494, 0496). The server half (0496 edited before its deploy, with the
measurements) is `docs/dev-log/2026-11-25-per-hour-honest.md`.

**The client ships after 0496.** So the reads it replaced are deleted, not kept as a fall-back. Shipped before 0496 the worker list
would be empty and Assign would offer nothing.

## What HQ reads now

- `src/live/useWorkers.ts` (new): the two reads.
  - `world.workers()`: when HQ opens, once after a command of hers (a fleet's new version, a job set or cleared, the party sent or
    called home) and once when a served stamp passes. A kept answer is good for the served `ask_s` (60 s). Never on the beat.
  - `world.actions(worker)`: ONCE when the Assign sheet opens. The question is frozen when the sheet mounts, so nothing asks again
    while it stands. A kept answer for the same worker as she then stood is good for the served `ask_s` (300 s).
- `src/lib/rpc/index.ts`: `worldWorkers`, `worldActions`. `src/lib/rpc/types.ts`: `WorkerAction.day`.

## The worker row (`workerRows.ts`, `WorkerRow.tsx`)

- Every row is `world.workers()`' row: her state, her action, the two stamps of her bar, why she stopped.
- **Coin an hour and XP an hour as served** ("+1,234 / h", "299 XP / h"). A rate the server does not serve is not drawn: `basis`
  none (a fixed run before two whole runs of hers), a null figure (the Best run), and the Land's nought of coin.
- The adapter that put rows together from `world.away_report` and `world.land` is deleted.
- Kept, each for what `world.workers` does not serve: `world.fleets` (her picture: hull and captain), `world.away_report` (While
  away's own read: a job's tally and last run for her sheet, and whether standing jobs are lit), `world.land` (a land's NAME: the
  action carries its code).
- Her sheet shows the same served rates.

## Assign (`AssignSheet.tsx`)

- **Sea:** the runs `world.actions` serves from where she lies (or is bound for), best served coin an hour first. One list, "good to
  harbour", each with its time and its coin an hour. The foot: what one run leaves, its units, its cost, its time; and, set to
  Repeat, the hour's coin and the runs a day (the served `day`).
- **Purse-bound:** every run is priced by the server for the units she can buy. The "over purse" mark is deleted with the quote it
  stood on (a harbour she did not lie at could not be capped; no such quote is drawn now). The "Buy at" harbours are gone with it:
  the server offers runs from her harbour.
- **Refused actions are not offered:** a run the leg judge shuts, a land job she has no level for, Bring home at home. A door shut
  for all of them (`closed`) says so in the server's words.
- **Bring home** is offered where the server serves it (docked, away from home, lit). Once / Repeat / a count as before.
- **Best run:** the served `sea:best`. **Haul home** is kept as it was: `world.actions` serves no haul option.
- **Land:** the jobs the server would take, each with its served units, trip and XP an hour.
- Deleted from this sheet: `world.good_board`, `world.buy_capacity`, the quay's market read, `world.land`'s job list.

## Words (`dict/corp.ts`, English)

Added: `{n} / h`, `{n} XP / h`, `{n} a day`, Run, No run. Removed with what they named: Over purse, Buy at, Sell at, Good, A turn,
Level, Nothing to buy, Bought at home, No sale, Orders.

## Decided by default (the owner may reverse)

- A worker's rate is written "/ h"; the company's one figure on the Rank strip stays "/ hour".
- Set to Once or a count, the foot shows one run's profit and no hourly figure (the served rate is the repeating day's).
- A fleet with no job that is at sea reads Working (her served `worker_state`), one that is laid up or wrecked reads Stopped.
- "Orders" (queued by hand in port) is no longer a row's word: the served row does not say it.

## Checks

- `tsc -b`, eslint (touched files), `vite build`: clean.
- `tests/hq.corp.spec.ts` (390 and 1440): 2 passed. `tests/hq.join.spec.ts`: see the PR body.
- Shots: `C:\Users\gkwng\dev\hq-figures-shots\`.

## Not verified

- Prod: nothing was read. No Korean.
- A sea row with a served coin an hour (basis `runs`) was not drawn in a spec: it needs three BUYs of hers, hours of play. Its
  drawing is the same code path as the party's XP an hour, which is checked against the served figure.
- The specs read the served figures from the page's own attributes (the local backend has no wire to tap), so they prove the text
  equals the served number and that one request was made; they cannot compare against a second copy of the server's answer.
