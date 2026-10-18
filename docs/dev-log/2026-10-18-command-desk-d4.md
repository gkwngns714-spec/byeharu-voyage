# 2026-10-18 — 0174: COMMAND DESK D4, several orders are one, and the plan builder — `osn-desk-d4`

`docs/COMMAND_DESK.md` §3.5, §7.4, §10 row D4. The owner, 2026-10-17: *"buy and sell plans … setting up trade
routes for my fleet"*. **Not deployed.** The number 0174 is provisional: prod head was 0173 (distance pricing) when
written. Re-read the head and take head + 1 at the push.

## Server — `cmd.issue_lines(fleet, lines, expected_version)`

The verb is registered for signed-in players only.

`lines` is `[{text, path}]`: lines of the one grammar, each SAIL carrying the course the chart proposed. The call:

- checks the fleet is yours (`E_NO_SUCH_FLEET`) and the version is current (`E_STALE`), and settles the fleet first,
  exactly as `cmd.issue` does;
- parses **every** line through `cmd.parse` before **any** is queued. A refusal names its line: `line: 3`,
  `Line 3 (SELL nosuchgood ALL): …`. A line naming another fleet, or a CANCEL / CLEAR line, is refused;
- checks the queue's room for the whole plan (`E_QUEUE_FULL` with the counts);
- queues every line through `cmd.enqueue`, the one enqueuer, inside one sub-transaction, so any refusal takes every
  line back;
- runs `cmd.advance` once at the end, so a docked fleet starts on the first line at once.

It adds no executor, no grammar and no switch: it can do only what N `cmd.issue` calls can.

**Proof (own probe company at Lisbon, rolled back; 167 ms on PGlite):**
- a bad third line queues nothing and is named;
- a CLEAR line, an empty plan, a stale version and another company's fleet are refused;
- 13 lines (the queue limit plus one) are refused whole;
- four lines are queued in order, each with exactly `cmd.parse`'s verb and args (the SAIL with its path), and the
  version moves once a line;
- the docked fleet starts its first line (`["failed","pending","pending","pending"]` — the first, a SELL of nothing,
  refuses and halts, as after `cmd.issue`);
- the registry grows by one and reverses to its pre-image; the walls hold.

**Read-only on prod:** the registry's last row occurs exactly once in the live body.

## Client — the plan builder

**`features/command/plans/PlanBuilder.tsx`** — `Plan · Aniseed`:
- **Buy at:** chips for the cities that sell it, plus `N units on board` when there is cargo. Units and Max fields.
- **Sell at:** chips for the board's priced cities. A Min field.
- **Estimate:** Cost · You get · Net, then `for 93 units · 131.2 days · arrive 13:53`. These are **world.good_board's
  own row**, asked from the chosen buy city for the chosen amount. Nothing is added up on the client.
- **Queue it once** sends the plan through `cmd.issue_lines`, then the desk turns to Plans, where the lines stand in
  the queue.
- **Make it a route** seeds the route editor's own draft. The route fold stands open on a new route drafted from it.

**How it opens:** from a **Plan** cell on every Buy at row that is not the docked city; the docked row keeps
**Buy**. The plan builder takes the desk's one slot, as the trade tray does.

**Supporting pieces:**
- `plans/planLines.ts` (pure) builds the grammar's text (`SAIL X` · `BUY good N AT <= max` · `SAIL Y` ·
  `SELL good ALL AT >= min`). Each SAIL's course comes from `proposeCourse`, between `sailOrigin` /
  `sailTarget` — the same author as a typed SAIL and the route editor.
- `plans/planDraft.ts` holds the plan draft and the route seed (session storage). It lives in features/command, not
  src/store, because its hand-off is the route editor's type.
- `RouteEditor` takes an optional `initial` draft.
- `useGoodBoard` can be asked from a chosen city.
- **RPC:** `cmdIssueLines`, the `PlanLine` and `IssueLinesResult` types, and `worldStore.issueLines`.
  `rpc.surface`'s pin moved.

**Money at 7–8 digits (your note):** prices, nets and net per ton never wrap (`whitespace-nowrap`). The market price
column grows to fit its figure instead of a fixed 96 px, and the name truncates instead. Shot
`desk-big-figures-390.png` (kimchi, distance-priced): `89,215 🪙` and `+89,080 🪙 / ton` on one line each at
390 px. Shot `desk-plan-390.png`: `Net +2,438,336 🪙`.

## A defect found and fixed while verifying

`route.stopface.spec` failed deterministically on this branch only. Bisected: the route fold's new subscription
to the plan store read `routeSeed` as **undefined**, not null, so the fold stood open on a "seeded" new-route
editor and the page sat scrolled differently.

The store's `merge` now reads any missing field as none (`plan ?? null`, `routeSeed ?? null`), and the spec
passes. I did not find why the field arrived undefined; the merge makes it irrelevant.

## Verify (once)

- Build on the cached prefix: 163 restored, then 0172, 0173 and 0174 applied. `tsc -b` and `eslint .` are clean.
- `rpc.issueLines.spec` (new): 4 passed.
- `desk.plan.spec` (new, 390): good → Plan → builder → sell city pressed (the estimate does not move) → Queue it
  once → Plans shows `Buy Aniseed · All that fit`, `Sail Tokyo`, `Sell Aniseed · All` (the first SAIL already ran):
  passed.
- Against `localhost:4260`: flicker, layout, desk.layout, desk.plan, wide.layout and route.stopface: 39 passed.
  verbHomes, rpc.surface, words, duplication, sections and rpc.issueLines: 56 passed.
- Selection map: both new specs are in `tests/shard-weights.json`; rule S selects `rpc.issueLines` by name.
- Shots: `docs/dev-log/2026-10-18-command-desk-d4/` — `desk-plan`, `desk-plan-queued` and `desk-big-figures`, each
  at 1440 and 390.
