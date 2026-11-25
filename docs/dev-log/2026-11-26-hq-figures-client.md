# 2026-11-26 — `hq-figures-client`: HQ reads the live 0496 (client only, no migration)

Off `origin/main` (0496 live, #860, #864 WorkerFix, 0495). It carries `hq-figures`' client half and merges `origin/stale-refusal`.
0497 and 0498 are not in this chain: what they serve is drawn only when served.

## What it does

- **Worker rows are `world.workers()`' rows.** Coin an hour and XP an hour as served; none for basis `none`.
- **A worker that digs goods for Storage shows goods, not coin.** Prod's party read `per_hour` 0 and `net` 0 for 30 coal a trip
  (basis `terms`). The row now says the served `items_per_hour` ("10.3 goods / h") and XP an hour, and no coin figure. The same in
  her sheet and in Assign's terms. The rule: no coin figure when the served coin an hour is nought and the action brings goods (or
  is a land job's terms). Design A2.1 already serves `items_per_hour`.
- **Assign reads `world.actions` once an opening.** Runs priced for her purse, in the order of the served coin an hour.
- **"Trade nearby"** is drawn only when the server serves `sea:near`. Here it does not, and a spec says so.
- **"Prices low" and its retry clock** are drawn only when a row serves `wait`.
- **`closed` E_SLOW** (the read took too long): its plain sentence, no code, and one press, Try again, which asks once more.
- **WorkerFix kept.** The fix comes from the served stop's code (`fixOf`), a repair or a hire only while she lies docked. Her row is
  still one press at one height, wearing "Repair 659".
- **`stale-refusal` merged and driven** (`tests/refusal.drive.spec.ts`, 390 and 1440): a wrecked flagship's refusal names her,
  says why, prints no code and carries Repair at the server's price; repaired, the note is gone and the refused order is still a
  row of her queue. No time stands on that row here: 0499 serves it, and 0499 is not in this chain.

## Specs (headless, port 4793, a private image cache)

- `hq.join` (incl. the slow read and "no Trade nearby"), `hq.corp`, `hq.board`, `hq.design`, `hq.fix`, `hq.inplace`,
  `hq.rateWhy`, `pages.standStill`, `refusal.stale`, `refusal.drive`: see the PR body for the counts.
- `hq.board`'s card test was written for the old sheet (good chips, sale rows); it now reads the picked run.
- The four near-round and wait tests skip here (no 0498 in the chain); they pass on `hq-figures`.
- Shots: `C:\Users\gkwng\dev\hq-figures-shots2\`.

## Not verified

- Prod: nothing was read. A sea row with a served coin an hour (basis `runs`) was not drawn in a spec.
- "Trade nearby" and "Prices low" in the browser on this branch (they need 0497 and 0498).
