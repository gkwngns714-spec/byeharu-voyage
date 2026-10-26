# Route builder on the map (owner row 209, with R3 row 191)

Owner, 2026-10-26 (row 209): *"in the map, let me click set route, and let me press city, undo, then confirm each visiting city, then press final - something like that."*

Design only. No code, no migration in this PR. **Decided by default** = mine; the owner may reverse it.

## 0. The map law, and this exception

- `docs/DESIGN.md` law 3: *"The map is an output device ... It never accepts input."*
- **The owner's word outranks it** (row 209). This flow is **the one exception**: in route mode a city tap adds a stop. Outside route mode the map works as it does today: a tap selects. (The map's `Send fleet` tray, from the owner's 2026-08-24 order, is the earlier exception. It is unchanged.)
- B2 amends law 3's text in `DESIGN.md` so that it names both exceptions.

## 1. The flow

| Step | Press (EN / KO) | What happens |
|---|---|---|
| 1 | **Set route / 항로** | Shown in a fleet's tray (her own fleet only). Route mode starts. Stop 0 is "Now": her port, or her destination when she is at sea (`sailOrigin`). City trays stop opening. |
| 2 | tap a city | It becomes the **next stop, not yet kept**. The leg is drawn dashed, with its days and its verdict (§3). Another tap replaces it, so a press selects. |
| 3 | **Confirm / 확정** | The stop is kept: the leg turns solid and the stop is numbered. Disabled while the verdict is not open. In that case the button shows the reason in place of its label. |
| 4 | **Undo / 뒤로** | Removes the next stop if one is shown, else the last kept stop. With nothing left it does nothing. |
| 5 | **Final / 완료** | Queues the whole trip (§2), all or none. On success route mode ends and the fleet's track shows the queue. |
| — | **Cancel / 취소** | Leaves route mode, and nothing is sent. |

**A tap on a city she cannot reach:** the stop is drawn with a muted dashed leg, and **Confirm shows the reason** (from the server's code, 1–2 words, as in COMMAND_REDESIGN §5):

| Code | EN / KO |
|---|---|
| `E_LEG_TOO_FAR` | `Navigation N` / `항해술 N` |
| `E_ENDURANCE` (stores do not fit) | `Hold full` / `화물 가득` |
| `E_SEA_CLOSED` | `Title N` / `작위 N` |
| same as the last stop | `Same city` / `같은 도시` |
| shut, but reachable through harbours (B3) | the button reads **`Via 2 / 경유 2`**. Pressing it keeps those 2 harbours and the city. |

Water taps, ship taps and merchant taps do nothing in route mode. Pan and zoom work as usual.

**Screens**

```
Phone 390×844                          Wide 1440
┌──────────────────────────┐           ┌──────────────────────────────────┬────────────────┐
│        chart             │           │            chart                 │ Route 항로      │
│  0 ── 1 ── 2 ┄┄ ?        │           │   0 ── 1 ── 2 ┄┄ ?               │ 1 LIS→OPO 1.2d │
│                          │           │                                  │ 2 OPO→ANR 5.0d │
├──────────────────────────┤           │                                  │ ? ANR→HAM 2.1d │
│ 3 stops · 8.3 d · −80    │           │                                  │ Supplies −80   │
│ [Undo] [Confirm] [Final] │           ├──────────────────────────────────┤                │
│ [Cancel]                 │           │ [Undo] [Confirm] [Final] [Cancel]│                │
└──────────────────────────┘           └──────────────────────────────────┴────────────────┘
```

- On a phone, the bar is fixed at the bottom with one summary line above the buttons. The leg list opens in place when the line is tapped. Nothing else moves.
- The leg lines are **R3's leg lines** (COMMAND_REDESIGN §3: `1 Lisbon → Cádiz · 1.2 d` plus the sea tag). There is one component for both the Trade mini map and the builder. No second copy.
- Cap: `standing_route_stop_max` (8) kept stops, the existing knob, read through `world.standing_routes`. **Decided by default.** At the cap, Confirm reads `Max 8` / `최대 8`.

## 2. What Final creates

- **A one-off trip: a SAIL line for each kept stop, sent through `cmd.issue_lines` (0175), all or none.** **Decided by default.** The owner described a trip ("each visiting city, then final"), not a loop.
- The courses come from `proposeCourse`, the one course author, as `planLines` uses it. The server re-checks every course when the line runs.
- **Repeat / 반복** (B4) is a second press on the same bar. It seeds the **existing route editor** with the kept stops (`seedRoute` → `RouteStopDraft` → `cmd.standing_route_save` / `_assign`). That gives a loop with no second route system (NO_SPAGHETTI §1). The closing leg, last stop → first, is judged too.
- **Goods: none in the builder.** **Decided by default.** The Trade page (R1) stays the place where goods are chosen. Per-stop buy and sell lines already exist in the route editor, which Repeat opens. A per-stop "Sell all" is not built unless the owner asks.

## 3. How a leg is judged: one server rule, never a client copy

**The rule.** A leg is open when `public.passage_gate(player, fleet, nm, dest, course)` is null (reach, sea) **and** `public.supply_need(fleet, nm).fits` is true (the stores the SAIL will buy fit beside her cargo). This is the SAIL gate: `cmd.do_sail` tops up through `supply_need`, then `voyage.sail_refusal` refuses `E_ENDURANCE`.

**Today the rule is split, and that split is row 208.**

| Caller | Asks passage_gate | Asks fits |
|---|---|---|
| `voyage.sail_refusal` (at departure) | yes | yes (real casks after the top-up) |
| `cmd.issue_lines` (Go / Final) | yes | **no** |
| `cmd.standing_route_save_for` | yes | **no** |
| `voyage.reach_passage` (via harbours) | reach only | **no** → a 7.1-day leg for a 4.3-day hold |

**The fix, one function.** `voyage.leg_refusal(p_fleet, p_dest, p_nm, p_course)` returns `passage_gate` and otherwise `E_ENDURANCE` when `supply_need(...).fits` is false. `issue_lines`, `standing_route_save_for` and the builder's read call it. `reach_passage` keeps a leg only when it is open under the same rule. If **0227** (row 208) already adds this function, B1 reuses it and has no hunks of its own. If it does not, B1's migration adds it.

**The client never computes it.** It prints the server's `shut` code. The client has no copy of `fits`, `endurance_margin` or reach.

**Judged against her hold as it is now.** If she buys cargo later, the stores may no longer fit. The SAIL's own gate still refuses at departure, which is the last net.

## 4. Server reads and writes

| Need | Use |
|---|---|
| Judge legs as stops are tapped | **NEW** `world.route_legs(p_fleet uuid, p_legs jsonb)` → per leg `{from, to, nm, days, supplies:{days,cost,fits}, shut: refusal\|null, via: text[]\|null}`. The input is `[{from, to, course}]`. `nm` is the server's measure of the course (`voyage.path_nm`). The verdict is `voyage.leg_refusal`, and `supplies` is `supply_needs` (one call for every leg). `via` is filled only for a shut leg, from `reach_passage(player, from)` (after 0227). |
| Final | existing `cmd.issue_lines` (with the `leg_refusal` hunk) |
| Repeat | existing `cmd.standing_route_save` / `_assign` (with the `leg_refusal` hunk) |
| Cap | existing `world.standing_routes().stop_max` |

**Migration: yes, one file, 0228** `a_leg_is_judged_once` (renumbered at push; 0227 is reserved for row 208). It adds `world.route_legs`, registered in `client_rpc_entry_points` and granted to authenticated only. It also adds `voyage.leg_refusal` and the `issue_lines` / `standing_route_save_for` hunks, **unless 0227 has them**.

## 5. Slices, shipped in order

| Slice | What | Tests |
|---|---|---|
| **B0** (before this design is built, not in it) | 0227, the row-208 fix. R3, the mini route map, including the leg-line component. | their own |
| **B1**, migration 0228 + catalog | `world.route_legs` (+ `leg_refusal` and hunks if 0227 lacks them) | Self-assert on its own probe company, rolled back. (a) Lisbon→Porto is open, and its `supplies` equals `good_board`'s for that leg. (b) A leg over reach reads `E_LEG_TOO_FAR`. (c) A full hold reads `E_ENDURANCE`, and `issue_lines` refuses the same SAIL with the same code. (d) A shut far city has a `via` in which every leg is open. (e) Every hunk reverses to its pre-image. (f) 6+ timed calls in one session. Spec **new** `tests/rpc.routeLegs.spec.ts`. |
| **B2**, client: the builder + Final | Route mode, tap / Confirm / Undo / Cancel / Final, the bar, the R3 leg lines. The `DESIGN.md` law 3 text. i18n keys EN and KO. | **new** `tests/map.routebuilder.spec.ts` at 1440×900 and 390×844: Set route → 2 cities → Undo → re-tap → Confirm ×2 → Final queues 2 SAILs. A shut city's Confirm shows its reason and does not press. Outside route mode a city tap still opens the city tray (`map.sendfleet.spec.ts` unchanged and green). The bar does not move when a stop is added. |
| **B3**, client: Via | A shut tap with `via` shows `Via N`, and pressing it keeps the harbours and the city. | `map.routebuilder.spec.ts` +1 case: a far city adds N+1 stops, and every leg in them is open. |
| **B4**, client: Repeat | Seeds the route editor (`seedRoute`), and the closing leg is judged. | +1 case: Repeat opens the route editor with the same stops, and saving it lists the route. |

Every slice runs `npx tsc -b`, `npx eslint .`, the pure specs, `duplication` and `sections`. B2 to B4 are client only and need no migration.

## 6. Risks

- **0227 and 0228 overlap.** Both touch the leg judge. B1 is written after 0227 merges, by reading prod's live bodies. Its hunks are sliced from those bodies, never from the chain text.
- **Cost of `reach_passage`.** It runs O(n²) over 237 harbours, so it is called only for a shut leg and never on every tap. B1 times it.
- **Her hold changes after Final.** A leg judged open can be refused at departure. The SAIL gate catches it, and the queue's existing refusal shows on the fleet.
- **Tap noise on a phone.** Route mode uses the existing hit test (`hitTest.ts`). Only cities answer, so ships near a city cannot steal the tap.
- **A merged queue.** If she already has queued orders, Final appends after them, and the queue cap (`order_queue_max`, 48) refuses the overflow all or none.
- **Law drift.** Route mode must not leak. After Cancel or Final, a tap selects exactly as before (B2's spec asserts this).
