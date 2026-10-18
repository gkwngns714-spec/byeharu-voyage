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

**CI, PR #226 (slice 1):** the first run went red only on numbering: main took 0182–0184 under the branch. It was renumbered to 0186 and rebased. The re-run was green on all checks: build, disposable-chain, pglite-gate (ledger, merchants, the rest), select. The local full-proof run (`proof.mjs`, a cold prefix for the node variant) was stopped unfinished. The pglite-gate shards ran the proofs on CI.

**Drive (local PGlite build, 1440×731, DPR 2):**
- A plan with an impossible BUY limit was queued.
- The ✕ on its last row cancelled exactly that row.
- On arrival the BUY was refused. The note read *"Order 2 was refused: Aniseed opened above your limit of 0.01 and nothing was bought. Anything that depended on it was cancelled; Gaivota is free."* The SAIL behind it was cancelled, and one refused row stayed.
- *Clear all orders* emptied the queue.

## Slice 2 — 0188 `the_desk_plans_only_what_she_can_sail` (provisional; on top of 0186)

- **One formula.** `public.passage_reach_at(level)` is now the arithmetic that `passage_gate` reads, through one hunk. These read it too:
  - `passage_reach_nm(player)`: null for a merchant;
  - `passage_reach(player)`: `{navigation, reach_nm}`;
  - `passage_needs(player, nm)`: the least Navigation that sails a leg, with that level's reach. Navigation is null past `skill_max_level`.
- **`voyage.reach_passage(player, from)`.** Dijkstra over `public.sea_reaches` (the one pathfinder's sailed miles). A leg counts only when it is ≤ her reach and its harbour passes `passage_gate`'s region check. It returns, per harbour: `nm` (null if unreachable), `direct_nm`, `stops` and `max_leg_nm`. The arrays are float8 for O(1) subscripts.
- **`world.good_board`** (10 hunks on the post-0183 body):
  - The `reach`/`reach2` CTEs read `reach_passage`. Miles, days, arrival, wages, net and the net ranking are now the reachable passage's.
  - The dearest **reachable** cities are the ones priced in full. Unreachable ones rank last.
  - Every buy and sell row carries:
    - `stops`: string[], or null when unreachable;
    - `needs`: `{navigation, reach_nm}` for a direct leg past her reach, or null;
    - `sailable`: boolean. Every leg must be within reach and within her stores: `voyage.endurance_days` ≥ the leg's days × `endurance_margin`, sail_refusal's rule. Her present stores are the floor, and she can provision at every stop;
    - `longest_leg`: `{miles, days}`.
  - The board carries `reach` and `supplies` `{days, margin}`.
  - At anchor, 0183's nearest harbour is the first stop, and the lead counts as a leg.
- **`cmd.issue_lines`.** Every SAIL is asked of `passage_gate` at plan time, from where the line before leaves her. The distance is the course measured by `voyage.segments_from_course` (as `do_sail` measures it), or else the sailed miles between harbours. A leg she cannot sail refuses the whole plan, naming the line: `Line 1 (SAIL MTY): that leg is …`.
- Every hunk occurs once in the live prod body (prod head 0185, read-only). Each reverses to its pre-image, and the ACLs are unchanged.

**Client.**
- `planLines` sails through the board's stops.
- `PROVISION FULL` is written only where her casks would not cover the next leg. Each leg's days are the proposed course's length at the board's speed, times the margin. At the buy city the provisioning goes before the BUY, so a full hold never refuses the casks.
- `PlanBuilder`:
  - shows `via …`;
  - refuses to queue an unsailable city, saying why: *"… cannot be reached in legs of 1,700 nm — needs Navigation 5 (reach 27,200 nm)"*, or the stores sentence.
- The types carry the new fields.
- The terminal's Best-trade card (`GoodTicket.tsx`, the terminal agent's file) is untouched. Its figures are the server's, so they are already the reachable passage's. The terminal agent reads `sailable`.

**Proof in the migration** (probe at Lisbon, NAVIGATION 0):
- A harbour beyond her reach is reached through stops. Every leg is ≤ 1,700 nm, and the legs sum to the passage.
- A plan sailing straight there is refused up front at line 1, and at line 2.
- The board's reach is 1,700. A far sell row carries stops, `needs`, a boolean `sailable` and the passage's miles, counted from the city it would be bought at.
- The passage through the stops is accepted whole.
- A merchant has no reach, and the walls hold.

**Specs:**
- `rpc.issueLines.spec` +1 (far: `LUA 3990 nm via SAI, CAP; needs Navigation 3`).
- `rpc.goodBoard.spec` updated: an unreachable dearest city has no net and ranks after the reachable ones.
- `desk.plan.spec` passes. Its queued plan: `Resupply to full · Buy Aniseed · Sail Tangier · Resupply · Sail Saint-Louis · Resupply · Sail Cape Coast · Resupply · Sail Soyo · Sell Aniseed`.
- 12 passed.

**Known limits:**
- The queue holds 12 lines (`order_queue_max`). A very long passage needing more refuses `E_QUEUE_FULL` when queued, whole and named. Korea → London in 1,700 nm legs will hit it.
- The anchor lead is the great circle (0183's estimate).
