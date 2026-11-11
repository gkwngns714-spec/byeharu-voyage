# 2026-11-11: the route builder's Via and Repeat (owner row 209, B3 + B4)

Design: docs/ROUTE_BUILDER.md (§8 says what was built and what was decided by default). Client only. No migration, no knob, no switch.

## What was built

- **B3, Via.** A tapped city whose leg the server calls shut, and for which it serves `via` (0346), makes Confirm read **Via N / 경유 N**. One press keeps the N harbours and the city: N+1 stops. The harbours are the server's list. Files: `src/features/map/useRouteBuilder.ts` (the `via` hold, `confirm`), `src/features/map/RouteBar.tsx` (the word, `data-via`).
- **A kept leg is judged again.** The server re-judges every kept leg with the course the client proposes. A kept leg it calls shut shows its reason on its line, and Final and Repeat wait until Undo removes it (`blocked`).
- **B4, Repeat / 반복.** A fifth button on the same bar. It opens the one route editor on the one pop-up page over the chart, with her harbour first and then the kept stops. Back, or the editor's Cancel, returns to the builder with every stop kept. Start route saves and assigns through the existing `cmd.standing_route_save` / `_assign`; then route mode ends and the fleet is selected.
- **The closing leg** (last stop → her harbour) is proposed by the one course author and judged by `world.route_legs` in the same read as the other legs. While it is shut, Repeat shows the reason and does not press.
- **The editor moved to `src/live/`** (`RouteEditor.tsx`, `RouteStop.tsx`, `standingRouteDraft.ts`), because the map may not import the command screen (`tests/sections.spec.ts`). It gained `seed` (the harbours, fixed) and tells its caller when the route started. `seedRoute` is in `standingRouteDraft.ts`.
- Words: `map.routeVia`, `map.routeRepeat`, EN and KO, in `src/lib/i18n/dict/map.ts`.

## Measured (local world, headless, DPR 2, a preview on localhost:4683)

- `tests/map.routebuilder.spec.ts`, 6 cases, at 390x844 and 1280x800: all 6 passed.
  - Via: the chart is drawn back with the wheel until a named city reads `Via N`. One press kept N+1 stops, the city last, each leg leaving where the one before ended; the server judged the kept legs and called none shut; Final was enabled; the bar's box did not change. Undo took the stops away one by one, and Cancel ended route mode.
  - Repeat (routes switched on by `tests/routesOn.fixture.ts`): disabled with no stop kept; with stops kept it opened the editor on the same harbours in the same order (seen: Lisbon, Setubal, Gibraltar at 390); Back returned to the builder with the same stops and the bar's box unchanged; Start route closed the page and ended route mode; the desk's route row then read the same harbours joined by ⇄.
  - An exploring run at 390 saw `Via 1` (Alexandria, Gdansk, Venice, Lubeck), `Via 2` (Salvador), `Via 3` (Cartagena, Havana), and plain `Too far` for Callao (the server served no `via`).
- `npx tsc -b`: clean. `npx eslint .`: clean. `npx vite build`: built.
- `tests/sections.spec.ts` (8) and `tests/duplication.spec.ts`: passed.
- `tests/route.stopface.spec.ts` (the editor's own spec, run because the editor moved): the browser case passed. Its two plain-Node word cases failed on this machine because they got Korean words (`최저 14.0`), the known Korean-locale effect; they do not touch a file in this change.

## Not done, not proven

- The server's save (`cmd.standing_route_save_for`) still does not ask `leg_refusal` (§7). The builder's judgement of every leg stands in front of it; the editor's own door (Trade → Route) is as before.
- No closing leg that is shut, no kept leg that turns shut, and no `Max N` on Repeat was seen in a browser: the local world did not produce one. The code paths are typed and read the same served `shut` as Confirm.
- Repeat is disabled, with no word of why, when she is at sea, when routes are switched off, or when she already runs a route.
- With five buttons at 390 a long reason (`Supplies short`) is cut with an ellipsis on its button; the full reason is on the leg's line.
- KO was not driven in a browser; the two new words are in the dictionary.
