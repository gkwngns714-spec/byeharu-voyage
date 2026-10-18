# 2026-10-18 — plan reach: a refused order does not freeze the queue (0186), and the desk plans only what she can sail — `osn-plan-reach`

The owner, 2026-10-18 ~14:00 UTC: *"Gaivota stopped at order 29 and will not skip it. that leg is 14015 nm and your
navigation carries you 1700 nm — study navigation, what is this?"*

## What happened to Gaivota (prod, read-only, `begin transaction read only; … rollback;`)

Fleet `51b8f474…` (player `c85b31cb…`), ANCHORED at 53.875 N 1.375 E, version 72. At 13:41:40 the D4 plan builder
queued, through `cmd.issue_lines` (0175):

| seq | line | state |
|---|---|---|
| 29 | `SAIL MTY` (Monterey) | failed `E_LEG_TOO_FAR` — "that leg is 14015 nm and your navigation carries you 1700 nm" |
| 30 | `BUY abalone-shell ALL` | pending |
| 31 | `SAIL TRI` | pending |
| 32 | `SELL abalone-shell ALL` | pending |

**Why 1,700 nm.** `public.passage_gate` (0107): reach = `nav_leg_nm_base` × 2^max(0, NAVIGATION − 1). On prod
`nav_leg_nm_base` = 1,700 and `skill_level(owner, 'NAVIGATION')` = **0** (never studied), so reach = 1,700 nm.
The rule is the owner's (row 113) and it read correctly. The defects were around it:

1. **The halt rule froze the queue.** `cmd.advance` (0007 §F.3) exits whenever *any* order of the fleet is `failed`,
   until CLEAR or CANCEL. So 30–32 waited forever behind a passage that can never be sailed.
2. **The ✕ did nothing.** `Queue.tsx` passed the order's **seq** to `cmd.cancel_at`, which reads a 1-based **index**
   over the live rows. `cancel_at(fleet, 30)` looked for the 30th live row and found none ("There is no such order in
   that queue"). And a failed row had no ✕ at all. The note itself said "will not skip it".
3. **The desk planned a 14,015 nm leg for a 1,700 nm captain.** Neither `world.good_board`, the plan builder nor
   `cmd.issue_lines` asked `passage_gate` at plan time. (Slice 2.)

Every fleet a failed order held, read on prod: 11 fleets have a failed order, 5 of them NPC route laps (`E_ENDURANCE`
SAILs, released by `npc_tend_route`). **Only Gaivota had pending lines behind an ordinary failed order.**

## Slice 1 — 0186 `a_refused_order_does_not_freeze_the_queue` (provisional number; main head 0184 (0182–0184 merged after this was written), 0185 in #224)

- `public.orders.plan_id` (uuid, null). `cmd.issue_lines` stamps the plan's lines with its first line's id (one hunk,
  before its `cmd.advance`).
- `cmd.release_failed(order)` (new, server-only): cancels what depended on a refused order — the rest of its plan, and
  everything pending behind a refused SAIL — each row with the reason, e.g. `cancelled: the passage to Monterey was
  refused — that leg is 14015 nm …`. A refused single BUY/SELL/… cancels nothing; the queue moves on.
- `cmd.advance`, two hunks: the halt check reads only a **route's** failed line (`route_lap_id is not null` — exactly
  the halt 0092/0093 keep for a route's refused SAIL); an order's refusal calls `cmd.release_failed` and continues.
  Route lines are unchanged.
- `cmd.cancel_at`, one hunk: the index counts the rows `cmd.queue` serves (pending, active **and failed**), so a
  refused row can be dismissed.
- **The release, now:** every fleet whose ordinary failed order still holds pending lines is released through
  `cmd.release_failed` and logged by `raise notice`. The selection, run read-only on prod: exactly Gaivota, seq 29
  (`SAIL MTY` → Monterey) would cancel `30 BUY abalone-shell ALL`, `31 SAIL TRI`, `32 SELL abalone-shell ALL`. Nothing
  else of his is written except `fleets.version` + 1 (every cancel path bumps it). After the deploy his fleet is free:
  the halt no longer reads his failed line 29, and nothing is pending.
- Every hunk occurs exactly once in the **live prod body** (checked against `pg_get_functiondef` dumped read-only),
  reverses to its pre-image, ACL unchanged.

**Client.** `Queue.tsx`: the ✕ sends the row's 1-based position; a refused row shows `refused` and its own ✕
(*Dismiss refused order N*); the note reads *Order 29 was refused: … Anything that depended on it was cancelled;
Gaivota is free.*; the Clear button always reads *Clear all orders* (it always did clear everything).
`Plans.tsx` passes the position.

**Proof in the migration (own probe company at Lisbon, rolled back):** a plan refused at its first line cancelled its
three other lines with the reason, all four carrying the plan id, and the fleet then bought at once; a refused single
BUY (limit missed) let the SELL behind it run; a refused SAIL to a harbour beyond a first captain's reach cancelled the
line behind it, naming the passage; the ✕ at position 1 dismissed a refused row and CLEAR emptied the rest; the release
is not client-executable; the walls hold.

**Spec:** `rpc.issueLines.spec` +1 test (execution-time refusal cancels the rest with the reason, the fleet is free,
the ✕ by position dismisses, CLEAR empties) — 5 passed.
