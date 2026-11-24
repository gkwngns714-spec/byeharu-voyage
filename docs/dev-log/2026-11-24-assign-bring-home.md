# 2026-11-24 — 0492 `assign-bring-home`: a fleet brings her goods home (dark, proof 195)

The owner: *"in hq we will be able to assign the fleet to do trade - designate an item to buy, and then sell at different location, or
bring them to the HQ - warehouse."* Plan: `docs/design/hq-corp-2026-11-24.md`, B2, B3 and slice 0492.

## What it is (server only; the HQ Assign sheet is H1's)

The standing fleet job of 0481 is the sea Assignment. Its `fixed` kind gains two settings, through the same door and the same tick:

- `end`: `'sell'` (today's job) or `'store'`: buy at A, sail to the company's home harbour (`public.home_port_of`), `STORE <good> ALL`
  into the home Warehouse through the STORE verb (`cmd.do_store` -> `public.storage_put`, the one storage writer and its cap).
- `times`: absent / null = until stopped; 1-999 = that many loaded runs. The job keeps `left`; each run that starts with the BUY at A
  counts it down; when `left` is 0 and the last delivery is done, the next turn clears the job (the receipt says `wait: done`).

The warehouse's room (decided by default): at A, the plan reads the home shed's room in units of the good (less what she already
carries). None: the job stops, `E_SHED_FULL`, "the warehouse at LIS is full", nothing bought. Fewer units than her hold takes:
`BUY <good> <units>` (no more than `fleet_buy_capacity`). If the shed fills while she sails, her STORE is refused by the shed's own rule,
the cargo stays aboard and the job stops on `E_SHED_FULL`. Nothing is ever dumped.

Dark (`assign_home_enabled` false): the door refuses `end` / `times` (`E_NOT_IN_USE`); a job that carries them (set while lit) stops at
its next turn; every other job is byte for byte today's. Decided by default: refusing beats silently ignoring the two names (no client
sends them today: `JobControl.tsx` sends good / buy / sell only).

## One authority

No new table, column or cron job. Two new STABLE helpers judge the end once at the door (`public.fleet_job_end`) and once at the plan
(`public.fleet_job_ends`); the switch reader `public.assign_home_on()`. Ten hunks: `fleet_job_set_for` x2, `fleet_job_plan` x6,
`fleet_job_open` x1 (the countdown, in the one writer of a run), `fleet_job_note` x1 (the clear). All three new functions are revoked from
public, anon, authenticated and service_role. No role is changed anywhere (no `set role`).

## For H1 (the call shape)

- Set: `cmd.set_fleet_job(p_fleet, 'fixed', {good, buy, end: 'store', times})` for Bring home (no `sell`: the server sets it to home);
  `{good, buy, sell, end: 'sell', times}` for Sell at B. `times` omitted or null = Repeat (until stopped); a number = Once (1) or n runs.
  Refusals: `E_NOT_IN_USE` (dark), `E_BAD_ORDER` (end not sell/store, times not 1-999), `E_NO_HOME`, `E_NO_WAREHOUSE`, `E_SAME_DEST`
  (A is home), and 0481's own (`E_NO_COURSE`, ...).
- Read: `world.away_report().jobs[]`: `params.{good, buy, sell, stops, end, times, left}`; `last.{end, leg ('out' on a loaded run),
  left}` after a run; `state 'stopped'` + `paused 'E_SHED_FULL'` + `last.sentence` when the warehouse is full. A cleared job leaves the list.
- Quote (no server change): `world.good_board(good, fleet, from, qty)`'s `buy` row at A (`units`, `cost`) and
  `world.trip_cost(fleet, legs A -> home)` (`days`, `total`); 0491 made those miles the sail's. A bring-home run earns 0 until sold.
- Stop: `cmd.clear_fleet_job(p_fleet)` (unchanged).

## Measurements (local, PGlite, the chain's world at 0491 + 0492)

- The migration: 424 ms for the whole file, self-assert included. The dark-identity scene (one fixed job set, planned, opened by one
  tick at OPO for cork) digested before and after the hunks: equal (`3b0e38c9`).
- Proof 195: 5/5 PASS in 0.6 s. Cork bought at Porto (nearest lane from Lisbon): 155 units for 8,428 (54.37 each), stored at Lisbon
  0 -> 155 at basis 54.37 (the price paid); two runs -> 310, then cleared; full shed (750 of 750 t) -> `E_SHED_FULL`, nothing bought;
  shed filled while sailing -> STORE refused ("the shed here holds 0. more tun(s) and 155 of Cork wants 186."), 155 still aboard.
- Proofs 185 (8/8) and 186 (7/7) pass with 0492. Proof 184 fails locally at FJ_BEST ("wait: nothing") WITH AND WITHOUT 0492 (checked by
  moving the file out): a local best_sales result, not this change; main's CI apply proof was green on b13a8339.
- `tests/news.lint.spec.ts` + `tests/db.budget.spec.ts`: 8 passed. `check-versions`: 452 distinct.

## Not verified

- Nothing was driven in a browser (no client in this slice).
- Prod: the before / after reads are in `scripts/ops/harness/assign-bring-home/`; their results are in the PR.
