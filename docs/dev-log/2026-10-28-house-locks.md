# 2026-10-28: each house is cut under her own lock, every minute (`osn-house-locks`, migration 0265)

Owner order 2026-10-28: bugs first, find the root cause on prod, fix the root. 0258, 0259 and 0260 each re-tuned the compactor's batch, and none of them stopped the backlog growing.

## The root cause, measured (prod, read-only, head 0263, 10-28 02:07-02:24 UTC)

**The backlog grows.** Merchant ledger rows waiting past the 6 h cut: 809 k (10-27 20:41), 898 k (10-28 02:10), **901,951 (02:24)**.
- 20,199 rows crossed the cut in the last hour, and 21,409 were written. A run of 0260 clears 4.6-6.0 k.
- All 821 houses still have rows from 10-25 23:0x-23:5x waiting (their oldest unrolled row: p5 23:09, p50 23:19, p95 23:53). The first 6 h slice has never finished: `upto` is null in every receipt since 0259.
- A house's ledger holds p50 1,207 rows (p95 2,173, max 3,748). Summing all 821 of them (`ledger_sum`, which is stable) takes **3.3 s**.

**Why.** One global lock, `public.hold_the_quay()` (0249), serialises every reconcile write step against the per-second arrivals beat. The compactor gets one 30 s window an hour inside that queue.
- 0260's receipts: the compactor held the quay 13.9 / 17.0 s and **waited for it 14.9 / 16.9 s** (01:07 / 02:07). Half its window goes to queueing behind beats.
- The beats are slowed by the same queue. At 02:07 the beat at :32 waited 5.6 s (the companies step, 5.9 s), and the beats during the compaction waited 0.5-4.0 s each. Then they ran 2.7-7.2 s, because 57-77 fleets had come due meanwhile.
- 0258-0260 changed the batch inside the window. None of them could change the window.

**Who takes the quay** (every `pg_proc` body that names `hold_the_quay`, prod): the beat (`tick_arrivals_each_second`), and four places in `tick_reconcile`: each merchant's tend step, the companies' step, the orders' step, and each compaction transaction.

## The design (0265), and how it differs from the brief

The brief proposed per-house locks in one fixed order for **every** writer. Checked against the code, that is sound for the compactor and unsound for the others:
- The beat, the tend step and the companies' step also lock the **harbours**. `city_pays` / `treasury_post` lock the house's row first, then the harbour's (`public.treasury_lock`, 0122/0123). That order holds for one act.
- The beat does many acts in one transaction (house A, harbour X, then house B, harbour X...). So it holds a harbour while it asks for the next house. A tend step that holds house B and asks for harbour X closes the cycle. That was the 10-27 04:07 deadlock that 0249's quay ended.
- Putting those writers in house order would mean the beat locks every house and harbour it will touch before its first act. That is a rewrite of `tick_arrivals`, and the arrivals agent is changing it now (0264).
- **The compactor is different.** It never touches a harbour, a quay or a purse. The only row it shares with another writer is the house's `players` row (the foreign key of the `NPC_CARRIED` insert). So the compactor alone leaves the quay. **Decided by default.** The tend and companies steps keep the quay, unchanged. The drain then shrinks every house's ledger, and the ledger sums are most of the companies' step (3.3 s) and of the hourly check (~4 s).

What 0265 does:
1. **`public.npc_compact_locked(houses[], at)`** is one compaction transaction's lock. It locks the batch's merchant rows in `players`, ascending id, `FOR NO KEY UPDATE SKIP LOCKED`, then runs THE rules (`npc_compact_houses`, unchanged) on the houses it got.
   - A house that a beat or a tend step is writing is skipped, not waited for. She is first in line next minute.
   - A beat that touches a house being cut waits for that one transaction. A beat that does not touch one waits for nothing.
2. **`public.tick_compact()`** is THE compactor, every minute (pg_cron `byeharu-voyage:compact`, `* * * * *`, CALL). It is defined inactive, and `wind_the_clock()` starts it.
   - **Due houses:** a merchant whose oldest unrolled ledger row is over an hour past the cut. They go oldest first.
   - **Batches:** each batch is compacted as of its newest house's oldest row + retention + 6 h, and never later than now. So a backlog is walked oldest hours first, six hours a visit, and a batch's houses read the same pages (0253/0259's slices). The progress is kept in the rows themselves: no slice state, and nothing is done twice.
   - **0258's clock:** each transaction is timed from its lock to its commit. The next one takes as many houses as fit in **200 ms** (1-25). None starts unless it ends inside the minute's **8 s** budget. A failed batch is redone a house at a time.
   - **The hour's sweep, at :07:** first every merchant NOT due, compacted as of now, then the orders' step. This is the hourly pass `npc_compact` always made, so a house with no ledger row to roll still loses her old events, voyages and trade days. It is cheap, because a house the sweep reaches has under an hour of rows past the cut. (Found by the first local end-to-end run: without the sweep, 1,629 events of houses with nothing to roll stayed.)
   - **Receipt:** `public.compact_runs`, one row a minute (a 1,440-row ring).
3. **`tick_reconcile`** (2 hunks): the compactor's block and its locals leave the hourly run. The merchants' tend steps and the companies' step keep the quay, unchanged.

## The proof

**No deadlock, by construction.** A deadlock is a cycle of waits, and a transaction that never waits is on no cycle.
- The compactor's transaction shares one kind of row lock with other writers, the house's `players` row, and it takes that with SKIP LOCKED, which never waits.
- Every other row it locks is a row no other writer locks: a merchant's ledger rows and events past the cut (append-only, so `forbid_mutation` lets only the compactor delete them), her ended voyages that no open lap reads and their `voyage_events` / insurance rows, her past `trade_daily` days, and finished orders past the cut. The beat's own lock clauses (prod, read-only) are on SAILING voyages that are due, their insurance, and fleets: none of them is a row the compactor deletes.
- The self-assert checks this mechanically, against the live catalogue:
  - `tick_compact` has no lock clause, no advisory lock, no quay and no `credit`, and runs each transaction through `npc_compact_locked` under `lock_timeout` 50 ms.
  - `npc_compact_locked` has exactly one lock clause: `players`, `order by p.id for no key update skip locked`.
  - Nothing that transaction runs takes a lock another writer takes. The functions checked are the rules, the orders' step, `assert_ledger_reconciles`, `ledger_sum`, the two triggers it fires (`forbid_mutation`, `tg_reconcile_from_ledger`) and the knob readers: none has a lock clause, an advisory lock, the quay, `treasury_lock`, `credit` or `city_pays`.
  - No other trigger fires on the tables it deletes from, and no other foreign key names a row it deletes.
- **The guard:** `lock_timeout` 50 ms on each compaction transaction. A wait that should not exist ends in 50 ms, far below `deadlock_timeout` (1 s), and rolls that batch back.
- **Two sessions in opposite order:** session 1 (a beat) holds house H2 and asks for H1. Session 2 (the compactor) can hold H1, but it never asks for H2 while holding anything: H2 is skipped. So the second wait of the cycle cannot happen.
- Two compactors cannot overlap (pg_cron runs one instance of a job at a time). If they did, NO KEY UPDATE would keep them off the same house.
- Not shown live: a test with two real sessions. PGlite has one connection, prod is read-only for checks, and CI's chain has no `dblink`. The proof is the construction plus these catalogue checks.

**Byte-identical results.**
- The rules are `npc_compact_houses`, unchanged (md5-asserted, with `npc_compact`, the house and orders steps, the purse functions, `credit`, the quay, the beat and `tick_arrivals`).
- **Probe (rolled back), five ways from the same state:** 0260's houses (3 merchants + 1 player, rows before a 2026-08-01 cut, an open lap keeping one old voyage). The five ways: two slices, one cut, the house step, `npc_compact`, and the new locked transaction. They must leave byte-identical rows. The locked transaction must take exactly the 3 merchants and skip none.
- **End to end (local):** from the same state, `tick_compact` run until nothing is due, and `npc_compact`, each in one rolled-back transaction as of the same instant. Their digests of every house's ledger, events, voyages, voyage_events, insurance and trade_daily are compared below.

## Measurements

**Local** (PGlite, cached prefix → 0265; 837 merchant fleets, merchants lit, kickoff, `tick_reconcile(true)` once):
- 0265 self-assert ok (five ways identical; the locked transaction took the 3 merchants and skipped none).
- `tick_reconcile(true)`: its receipt has no `compact` any more; phases tend / companies / check.
- `tick_compact(true)` at prod's 6 h retention, on the seed rows (10-15): run 1 compacted all **821 due houses in 37 transactions, 2.4 s, longest hold 80 ms** (up to 25 houses), 3,063 ledger rows rolled into 821 carried rows. Run 2 took the 57 houses still due (429 rows, longest hold 65 ms). Run 3: nothing due, 6 ms. Every purse reconciles.
- **End to end, the same state, the same instant (retention set to -2 h locally so every row is past the cut), each in one rolled-back transaction:** `tick_compact` (the sweep, then until nothing is due: 2 runs, 2.6 s) against `npc_compact` (46.8 s on wasm). **Digests IDENTICAL**: every house's ledger, events, voyages, voyage_events count, insurance count and trade_daily (834 houses; 821 ledger rows, 3,249 events, 349 voyages, 495 trade days left in each).
- `call tick_arrivals_each_second(2)` afterwards: no error.

Prod before: above. Prod after: below.
