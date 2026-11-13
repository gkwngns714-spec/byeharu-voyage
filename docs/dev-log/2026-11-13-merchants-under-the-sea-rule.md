# 2026-11-13: a merchant sails the seas her hull can hold (0392, slice S3, dark)

**Owner row 166** (2026-10-20): far seas ask a title and the fleet's wave resistance, a hard wall, and *"NPCs under the same rule"*. Design:
docs/SEA_CONDITIONS_AND_REGIONS.md sections 1, 4 and the S3 row of section 6. 0215 built the data and the one rule, 0216 the player's gate. This is the
merchants' half. **Nothing is lit and nothing is deployed by this PR**: `sea_conditions_bite_npc` ships false and the planner is byte for byte what it was.

## What landed

| Piece | What it is |
|---|---|
| `sea_conditions_bite_npc` (false) + `public.sea_conditions_npc_on()` | the merchants' own switch, independent of the players' `sea_conditions_bite` |
| `public.npc_sea_shut(wave, dest, course)` | the one rule (`public.sea_refusal`) asked with a null title: a merchant is judged on wave only (design Q3). Zones = the course's and the destination harbour's, as `public.sea_gate` gathers them for a player |
| `public.npc_course_zones(course)` + table `public.npc_course_zones_memo` + `public.npc_course_zones_fill()` | the zones of a known course, remembered (2,032 rows locally: every course of `npc_courses` and of every merchant route, both ways), keyed by the md5 of the course's own text; an unseen course falls back to `public.course_zones` |
| `public.npc_feasible_legs(port, fleet, speed, days)` | gained the fleet; lit, a known leg her hull cannot hold is not feasible. The three-argument function is dropped; its one caller passes `p_fleet` (three hunks in `public.npc_loop_candidates`) |
| `public.npc_loop_sea_shut(fleet, loop)` and three hunks in `public.npc_plan` | lit, her PRESENT loop with a closed leg is unsailable in 0203's sense: no BUY, loses to any loop she can sail, and is reviewed at that lap start (not at the sixth lap) |
| the sail door | NOT touched. `public.passage_gate` keeps the `is_npc` exemption, so a merchant at sea or mid-lap is never refused and finishes her trip |

**Functions cut, and who cut them last** (hunks anchored on these lines):
- `public.npc_loop_candidates`: 0120 (written), 0186, 0264, 0341. The three hunks are the three calls of `npc_feasible_legs`, each inside a line 0341 wrapped in `npc_legs_open`. Substring hunks, each once.
- `public.npc_plan`: 0142, 0150, 0152, 0181, 0186, 0203 (by the comments in its live body). Hunks: the last declared variable (`v_notes`), 0203's `v_unsail := coalesce(v_unsail, true);`, 0186's candidate condition.
- `public.npc_feasible_legs`: 0120, 0139, 0203. Dropped and recreated (arity).
- Overlap with open branches: none of 0364, 0366, 0367 (in batch-6) or 0391 (the players' side, another branch) touches these three bodies.

## One correction to the design

The design said (section 4) that "a loop that cannot be sailed is reviewed at once (0203)". The live `npc_plan` does not do that: the loops on offer are fetched
only when her loop leaves her nothing, when she lies off it, or on every sixth lap. Without the third hunk a merchant on a paying loop the sea closes would be
written with no BUY and, with an empty hold, **laid up** until her sixth lap. The third hunk fetches the candidates at once for that case (lit only).

## The "no open loop" simulation (local cached world, head 0367 + 0392; `scripts/ops/harness/sea-merchants/sim.mjs`)

Every one of the 837 merchants started on her route where she lies and planned alone at her lap start by the real `public.npc_plan`, once with the switch
off and once lit, each arm rolled back. "Closed" is the planner's own reading (`npc_loop_sea_shut`), asked in both arms.

| | fleets | closed before | DARK: moved | DARK: closed after | DARK: laid up | LIT: moved | LIT: closed after | LIT: laid up | lit minus dark, laid up |
|---|---|---|---|---|---|---|---|---|---|
| hull size 1 (barca, barque, crayer) | 158 | 2 | 149 | 110 | 8 | 141 | **0** | 15 | **+7** |
| hull size 2 (caravels) | 497 | 92 | 390 | 271 | 37 | 414 | **0** | 37 | 0 |
| hull size 3 (nau, navire, levanter) | 182 | 85 | 103 | 87 | 8 | 151 | **0** | 10 | **+2** |
| all | 837 | 179 | 642 | 468 | 53 | 706 | **0** | 62 | **+9** |

- **Reconciles with `sea-conditions/impact.sql`**: 837 loops, 179 with a closed leg (2 / 92 / 85), as it reads.
- **The old planner loves far loops.** Dark, one plan pass leaves **468** loops with a closed leg (it moves merchants ONTO them: the distance premium). The
  design's "548 of 837" on prod is this figure after many passes; 179 is only the roster as founded. So on prod expect the larger number.
- **Lit, no merchant is left on a closed loop** (0 of 837), all 179 moved, no plan failed.
- **Nine more merchants wait in port lit than dark** (62 against 53): seven small hulls and two naus. Why: the only loops that paid them crossed water their
  hull cannot hold; what stays open to them does not pay its wages and stores on this world's market, so 0181's rule lays them up ("she waits in port") exactly
  as it does for the 53 dark. They are not stuck: a laid-up merchant is planned again at every tend and sails the day a loop pays. Every closed loop's fleet
  keeps at least one open known leg (impact.sql: `closed_loops_with_no_open_leg_from_home` 0; proof 92 SM_BARCA: all 158 small hulls keep a feasible leg).
  **No fix built.** The alternative (mark her loop unsailable only when another loop pays) would keep small hulls crossing oceans whenever nothing else pays,
  which is the thing the rule forbids. Decided by default.
- **Harbours.** Dark, the pass keeps all 237 harbours called at. Lit, **225**: fourteen lose every merchant caller: AMB BND DIL TER TID (the Spice Islands
  and Timor), CPT (Cape Town), KOL (Kollam), PLO (Port Louis), HAG (Guam), HOB SYD (Australia), and GAL, MAK, OLD. They were 115 of the 3,302
  stops before the pass (3.5 %). Stops in all: 3,175 after the dark pass, 2,857 after the lit one (10 % fewer calls: loops get shorter).
  impact.sql's list of 18 is the static count (loops as founded that stay); the planner refills seven of them (HAN HIR JAF MAN QUE STA YEO are served again) and
  the pass loses three others (GAL MAK OLD). **That is the cost of lighting S3 without S4** (the far-trader houses): those fourteen markets see no merchant buying or
  selling until a player or a far trader calls. S4 is NOT built here.

## Cost (local PGlite; `sim.mjs --scene=scripts/ops/harness/sea-merchants/cost.sql`, 60 merchants spread over the roster)

| | loops on offer (`npc_loop_candidates`) avg / max | a lap start (`npc_plan`, alone) avg / max |
|---|---|---|
| before 0392 | 16 ms / 114 ms | 234 ms / 404 ms |
| 0392, switch off | 14 ms / 27 ms | 230 ms / 359 ms |
| 0392, lit | 21 ms / 47 ms | 214 ms / 434 ms |

Whole pass (837 plans): dark 170 s, lit 160 s; per plan 201 ms dark, 189 ms lit. No growth, so 0203's 277 ms line is not crossed by this file.

Two things made that true, both found by measuring:
1. **The memo.** Sampling a course is about 2 ms and a lap start reads some 150 known legs. With the memo the sea test of 1,061 legs takes 40 ms.
2. **The feasible legs are gathered in a materialised step first.** The first cut put the sea test in the same WHERE as the old tests: one call went from 1.7 ms
   to 160 ms (the planner evaluated it badly), and a lit lap start from 500 ms to 1,770 ms. With `with legs as materialized (...)` a lit call is 3.4 ms.

The file itself: 3.3 to 5.3 s locally, 2.6 s of it the memo's fill (budget 45 s; the self-assert fails above it).

## Proofs

- The file's self-assert: hunks once and reversing; no other function moved; one knob, false; the memo equal to the sampler on 60 courses both ways;
  **off = unchanged** on 48 fleets (16 a hull size), at 10 and at 60 days of stores, old function against new; a lit probe that rolls back (the legs are the
  dark ones less those her hull cannot hold; the door answers null for a merchant); nothing of money, ships or routes written.
- `scripts/db/proofs/92_a_merchant_sails_the_seas_her_hull_can_hold.sql`, 9 markers, on the world's own merchants. SM_PLAN's subject is a merchant the OLD
  planner keeps buying on a closed loop (planned dark first), so the marker fails if the planner does not mark her loop.
- `scripts/ops/harness/sea-merchants/proof-0392.mjs`: red first; the dark scene equal before and after (the loops offered to every fourth merchant, and a
  real plan pass over 60 merchants: counters, stops, lines, pauses, presets, all equal); proof 92 green; **proofs 12 and 47 green on it** (the only proofs that
  name the planner); 11 mutations red.
- `tests/news.lint.spec.ts`, `tests/harness.guard.spec.ts` green. Nothing is registered for clients (`rpc.surface` untouched: the entry-point count is asserted
  unmoved by the file).

## Lighting (not here; docs/dev-log/2026-11-13-lighting-the-seas.md)

Before: `sea-merchants/before.sql`. After the deploy: `volatility.sql`, `after.sql` (wanted there). For the light: `after-lit.sql` once as the baseline, then
at +5, +15, +30 minutes. Rollback: the switch.

## Decided by default

1. A merchant is judged on wave only (design Q3).
2. The memo is a table keyed by the course's text, not a column on `npc_courses` and `standing_route_stops`: no trigger on a hot table, no rewrite of live
   rows, and a route save cannot make it stale. A file that changes the sea zones must call `public.npc_course_zones_fill()`.
3. A closed present loop is reviewed at once (the third hunk), lit only.
4. Nine more lay-ups are accepted and watched (`after-lit.sql`, `laid_up`); no softer rule.
5. The two switches are independent in code. The order to light them is the lighting file's matter.
6. S4 (far traders) is not built; its absence costs fourteen harbours their merchant calls (above).
7. Proof number 70 (69 is left for 0391).

## Not verified

- **Nothing was read on prod.** Every figure above is the local cached world's (837 merchants as founded, a static market, no merchant at sea). Prod has
  merchants at sea, live prices and loops the planner has already moved: run `impact.sql` and `after.sql` there.
- The lit pass was one pass at lap 0. What the roster looks like after days lit (do the nine waiting merchants find a paying loop, do more join them as
  prices move) was not simulated.
- The cost on prod's Postgres: PGlite's figures say "no growth", not what the milliseconds will be.
- A merchant founded after the deploy with a course the memo has not seen is sampled live (correct, slower); `after.sql` and `after-lit.sql` count such
  courses, but no test founds one.
- Pirate merchants (0341) lit together with this rule: proof 47 is green with the switch off; the two lit together were not run.
- `rollback-0392.sql` was run once locally (the bodies return to their pre-image by `before.sql`'s reading); it is a draft, not a migration.
