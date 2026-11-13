# 2026-11-13: the seas say why (sea conditions: the impact read, the workable version, client C3)

Owner row 324: *"do all, make everything work. open them if everything is built and is workable."* Row 166: far seas are earned by title and
by the ships sailed; a hard wall; NPCs under the same rule. Design: `docs/SEA_CONDITIONS_AND_REGIONS.md`, section 10 (new, this slice).

Nothing here is deployed and no switch is thrown. `sea_conditions_bite` stays false.

## What this branch holds

| Piece | Where |
|---|---|
| The impact read for prod (read-only, one statement) and its volatility check | `scripts/ops/harness/sea-conditions/impact.sql`, `volatility.sql` |
| A runner for scenes on the cached local world | `scripts/ops/harness/sea-conditions/run.mjs` |
| The workable version, written down | `docs/SEA_CONDITIONS_AND_REGIONS.md` section 10 |
| ONE reading of the sea rule's answer | `src/lib/rpc/seaWall.ts` (`readSeaWall`, `seaWallOf`; `Refusal.sea` filled in `result.ts`) |
| ONE wording of a closed sea, EN and KO | `src/components/ui/seaWallWords.ts`, `src/lib/i18n/dict/seas.ts`; `Note` takes `sea` |
| A fleet's seas, and the zone of a point of water | `src/domain/seas/` (`fleetSeas`, `unpackZoneMap`, `zoneAt`, `closedMask`), `src/live/useFleetSeas.ts` |
| The Codex's Seas face | `src/features/compendium/SeasFace.tsx` |
| The map's shading, and the sea named on a place's tray | `src/chart/ClosedSeasLayer.tsx`, `useClosedSeasVeil.ts`, `MapScreen.tsx`, `SendFleet.tsx` |
| The wall on the Send row, the armada row, the route builder, Trade, routes, the queue | `SendFleetRow.tsx`, `SendArmadaRow.tsx`, `RouteBar.tsx`, `useRouteBuilder.ts`, `planLines.ts`, `TradePanel.tsx`, `RouteFold.tsx`, `RouteEditor.tsx`, `Queue.tsx`, `orderCheck.tsx`, `Armadas.tsx`, `TradeTray.tsx` |
| The figures | Codex ship sheet (a hull's wave resistance), the fleet's totals line (the fleet's) |
| The Start sheet offers only countries in open water, lit | `SignTheBook.tsx`, `NationPicker.tsx` (`closed`) |
| Korean names for the 18 seas cut out of the oceans | `src/lib/i18n/names/realms.ts` |
| The lit drive | `tests/seas.lit.spec.ts`, `tests/seasLit.fixture.ts` |

The server side it reads is 0376 (PR #636, `seas-wall`, merged into this branch): `short_title` / `short_wave` in the rule's figures,
`fleets[].seas`, `zones[].harbours`, `far_powers`, `world.route_legs` `sea`, `world.sea_zone_map`.

## One reading, not copies

Before this slice a closed sea reached a screen four ways and was read four ways: the order envelope dropped the sea's figures (it kept
only `have / need / unit`), Trade read `sea.refusal.figures` in `planLines.ts`, the route builder switched on the code, and the Map printed
the server's English sentence. Now every one goes through `seaWallOf` and is printed by `seaWallWords`. The client compares no number:
which ask is short is the server's `short_title` / `short_wave`. On a world before 0376 the wall prints both asks beside both of hers and
gives no advice.

## What the screens did before, checked

| Screen | Before | Now |
|---|---|---|
| Map, Send fleet row | The dry run refused with the server's English sentence; in Korean the same English | The wall, EN and KO |
| Map, a far city behind a closed sea | "Too far" and "no port to stop at" (the gate judges length first, and no chain exists) | The sea on the direct course, when the server names one (0376) |
| Map, a chain with a leg shut by a sea | "Too far" plus "A to B is shut" | The wall of that leg's sea |
| Map, armada row | The server's sentence | The wall |
| Map, route builder | The button "Sea shut", no sea named | The same button, and "sea: Needs title N" in the route's line |
| Trade | "Sea X: title 2, waves 10 · you: title 1, waves 12" | The wall |
| Codex | No sea anywhere | The Seas face |
| A ship's or fleet's wave resistance | Not printed on any remastered screen | Codex ship sheet, fleet totals |

## Measured (local; the cached world at head 0367)

See section 10.2 of the design for the impact figures and the ladder. `impact.sql` runs in about 9 s on PGlite.

## Checks run (local; preview on port 4423, the private in-browser world)

- `tsc -b`, `eslint src`, `npm run build` (the world image is built from the cached chain with 0376 applied, so its self-assert ran).
- `tests/seas.lit.spec.ts` (new), 9 of 9: the Codex's Seas face and the Map, lit, at 390 and 320 px in English and Korean (64 seas,
  12 open and 52 closed for the founding company; the shade covers 52 seas; Las Palmas is refused by Macaronesia with the wall's words
  and no passage figure; Funchal is priced and, at 390 px in English, sails); and the shipped dark world (no shade, no closed sea).
- One run of `trade.flow`, `trade.layout`, `map.sendfleet`, `map.autoroute` (without its sailed trip), `map.labels`, `codex.design`,
  `captains.codex`, `names.whole`, `onepage`, `sections`, `i18n.keys`, `i18n.ko`, `rpc.surface`, `news.lint`, `duplication`,
  `harness.guard`, `planWords`: 181 passed, 12 failed. All 12 are `planWords.spec.ts`, a plain-Node word spec that reads the machine's
  locale: this PC is Korean, so it prints Korean where the spec expects English. 7 of them fail the same way on the branch's base;
  the other 5 are this slice's sea cases, which print the right Korean sentence. CI (English) is the judge.
- A mistake to record: two `playwright` runs were started at once in this worktree and wiped each other's `test-results`; that run's
  11 "ENOENT" reds were the harness, not the code. Every run after it was one at a time.

## Not verified

- Nothing was read on prod. Every figure is LOCAL.
- The armada row and the route builder were not driven lit in a browser; they read the wall through the same `seaWallOf` the Send row does.
- The far-city case (`world.route_legs` `sea`) was not driven in a browser; proof 69 holds the server side.
- The veil's colour was judged on a headless Chromium screenshot at night and day; not on a phone.
- The Korean names of the 18 cut seas and the Korean wall sentences are unchecked translations.
- Trade can still list a far city as reachable that the door refuses at the press (design 10.2 and 10.6, "the board and the door").

## Decided by default

1. The 64 approved rows stay (design 10.3).
2. A press on open water still needs two presses to open its tray (the owner's 2026-10 rule); the shade is explained there.
3. The shade follows the fleet in hand (the app-wide draft's fleet), her first fleet when none is.
4. Dark, nothing is shaded, no sea is called closed and the zone raster is not asked for.
5. The route builder's button keeps "Sea shut"; the reason goes in the line above, so the bar keeps its height.
6. The wall's wording uses 직함 for title (as the Levels page does) and 내파 for wave resistance (the owner's word).
