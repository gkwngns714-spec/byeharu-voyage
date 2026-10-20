# 2026-10-20 — the passage gate reads the sea, slice S2 (migration 0216 at writing, `osn-sea-s2`, stacked on S1)

**The design:** docs/SEA_CONDITIONS_AND_REGIONS.md §6 S2. **Version.** 0216 at writing (applies on 0215); prod head
0211 when the pre-images were read; renumber at push. **Dark:** `sea_conditions_bite` stays false. Not deployed, not
flipped.

## 1. What landed

- `public.passage_gate(player, fleet, nm, dest, course)` — arity change (dropped, recreated, ACL restored grant by grant:
  postgres + service_role, asserted). The reach (0188) first, as before; then **lit** → `public.sea_gate(player, fleet,
  dest, course)`; **dark** → 0107's region door, the pre-image to the character. Merchants and nobody stay exempt.
- `voyage.sail_refusal(…, p_course jsonb default null)` — arity change; passes `f.id` and the course. `cmd.do_sail`
  hands the measured departure's course (one hunk); `world.trade_routes` and proof 05 call it with four arguments and are
  untouched.
- `cmd.standing_route_save_for` hands the route's fleet (null until assigned: the title alone judges a save) and the
  stop's course; `cmd.issue_lines` hands the fleet and the line's course.
- `voyage.reach_passage(player, fleet, from)` — arity change (ACL and 0206's `plan_cache_mode` kept): lit, her title and
  her fleet's wave are read once and every edge is open or shut by `public.sea_leg_asks`, and a harbour is open by its
  OWN zone (the self row of the asks) — 0205's one-door-a-region shortcut is kept for the dark region door only: lit,
  the first run reached 79 of 81 title-1 harbours because Funchal's region's first harbour by code is the Azores and
  Bergen's is Arkhangelsk; dark, `ok` is null and every edge is as before.
  `world.good_board`'s two call sites pass the fleet. `tests/rpc.issueLines.spec.ts` passes a fleet to it.

## 2. Decided by default: the region door is retired at the FLIP, its body and column in S2b

The design's §6 says the region gate goes "in the same slice". The owner's standing rule for every dark slice is
that no answer changes while the switch is off, and the region door refuses real plans today: read-only on prod
2026-10-20, **13 of 17 houses are refused Havana with `E_REGION_CLOSED`** (exploration 1 against the Caribbean's 2).
Dropping it dark would open the world until the switch is lit. So: lit, the door is never read (one authority — the
zone table — from the moment the switch moves); dark, the pre-image; and the slice after the flip (S2b: drop the dark
branch, `regions.min_exploration_level`, `public.exploration_reach`; re-cut `public.route_requirement` /
`world.route_board` from `exploration` to title and wave) leaves one body. Recorded in the design doc §9.

Between the flip and S2b the Routes board's `closed` flag still follows the region rule while the gate follows the sea
rule — a display flag, named here; S2b is the fix.

## 3. The self-assert (own probe rows, rolled back)

DARK: the gate / door / sail door equal their pre-images on 20 passages out of Lisbon (nearest 10, farthest 10) for the
probe and for every human of the world, with and without the miles; `E_REGION_CLOSED` among them (the positive
control); `reach_passage` from Lisbon equal 6 × 6 and timed; every human's passage table equal; the good board's
passage keys (port, stops, needs, sailable, miles) equal, timed 3 × 3.
LIT (switch flipped inside the rollback): a title-1 barca — Funchal clear; Las Palmas `E_SEA_CLOSED` at Macaronesia
(title 2 asked / 1 held, wave 10 asked / 12 held, the sentence verbatim); the plan `SAIL LPA` refused up front, line 1,
nothing queued; a route to Las Palmas refused at save. Title 3 (10,000 d. of probe turnover, four harbours) clears Las
Palmas. A nau to Havana: refused on title at 3, clear at 4, refused on WAVE at 21 with two barcas (the Western Ocean, 30
asked, "your fleet holds 21"). A merchant and nobody exempt at the door on a 999,999 nm leg. `reach_passage` at title 1
reaches every title-1 harbour and no other; at title 8 with a carrack of state, every harbour. Walls hold; the registry
is unmoved.

## 4. Measured (local PGlite, the chain restored from the prefix cache; 0216 applied in 16 s)

The receipt: 580 gate / door / sail answers equal their pre-images for the probe and the 13 humans of the PGlite
world, 140 of them `E_REGION_CLOSED` (the dark door exercised); `reach_passage` from Lisbon equal 6 × 6, every human's
passage table equal, the good board's passage keys equal. Lit: every check of §3 as promised; title 1 reaches 81
harbours (every title-1 harbour), title 8 with a carrack of state all 237.

Timing, one session: `reach_passage` dark old 153 ms → new 142 ms (last 3 of 6: 147 → 130; no generic-plan cliff),
lit 244 ms (the asks matrix, 56,644 rows read once); `good_board` dark old 1,494 ms → new 1,200 ms (3 calls each).
Nothing got slower dark. Prod's receipt at push is the measurement that counts (0205/0206 measured ~2 s a board there).

## 5. Not verified

- Not run on prod (no db push by order); the 20-passage dark identity for the 17 humans runs at push.
- `cmd.do_sail`'s new argument is exercised by the proofs that sail (04, 05) in CI, not by a probe here.
