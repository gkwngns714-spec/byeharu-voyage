# 2026-11-11: the route builder on the map (owner row 209, B1 + B2)

Owner, 2026-10-26: *"in the map, let me click set route, and let me press city, undo, then confirm each visiting city, then press final - something like that."* Design: docs/ROUTE_BUILDER.md (§7 says what was built and what was decided by default).

## What was built

- **B1, migration 0346 `a_route_is_judged_leg_by_leg`:** `world.route_legs(fleet, legs)`, a STABLE read granted to authenticated only, plus one registry row (anchored after `cmd.issue_lines`). Every leg's `shut` is `voyage.leg_refusal` (0231/0345), the one leg judge. `supplies` comes from one `public.supply_needs` call, and `via` from `voyage.reach_passage`, asked only for a leg shut by its length or its stores. No knob, no switch, no table. No other function body changes.
- **B2, the client:** a fleet's tray on the map has **Set route**. In route mode only a harbour answers a tap (the next stop), and the bar at the foot of the chart offers **Undo, Confirm, Final, Cancel**. Confirm is enabled only when the server calls the leg open; otherwise it shows the reason in one or two words. **Final** sends one `SAIL <city>` line per kept stop, each with its proposed course, through `cmd.issue_lines` (all or none). The fleet is then selected, so her queue is drawn. Files: `src/features/map/useRouteBuilder.ts` (decisions), `RouteBar.tsx` (markup), `MapScreen.tsx` (mode and drawing), `VoyageTray.tsx` (the press), `src/live/LegLines.tsx` (the leg lines, now shared with the Trade mini map).

## Measured

- Local apply (PGlite, the build's prefix cache: 329 files restored, 0346 applied): the self-assert passed. Its notice was not printed by the build.
- Prod, read-only, 2026-11-11 (`scripts/ops/harness/route-legs/before.sql`): head 20260818000345, `world.route_legs` absent, the registry anchor occurs once and no route_legs row is present, every composed reader is `s` (cmd.refusal `i`), and the sibling ACL is `{postgres=X/postgres,authenticated=X/postgres}`.
- Prod cost, read-only (`cost.sql`, the docked human fleet with the most ships): one `reach_passage` (248 rows) + `supply_reach` + 2 `leg_refusal` + `supply_needs` came to 5.49 s of wall time against 4.74 s for the bare head query, so about 0.75 s for the shut-leg arm. An open leg skips `reach_passage`.
- Browser drive `tests/map.routebuilder.spec.ts`, local world, headless, DPR 2, at 390x844 and 1280x800: Set route → tap → tap another (it replaces the first) → Undo → tap → Confirm → tap → Confirm → Final. Both passed. The bar's box was identical before and after the stops. There was no sideways scroll. After Final the fleet tray opens, she is bound for the first stop, the second is queued ("Ahead 1"), and a city tap opens the city tray again.

## Not done

- `cmd.issue_lines` and `cmd.standing_route_save_for` were not re-cut to ask `leg_refusal`. That change would alter plans for players who never use the builder, so it needs its own PR and window.
- B3 (Via) and B4 (Repeat) are not built.
- No shut city is tapped in the browser drive: every named city near Lisbon is in reach. The shut verdict is proved in `tests/rpc.routeLegs.spec.ts` and in the self-assert.
- At 390 the start's "Now" word can overlap Lisbon's name on the chart (the path layer's labels are not in the name planner). The Trade mini map has the same behaviour.
