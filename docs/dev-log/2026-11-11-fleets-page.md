# 2026-11-11 - The Fleets page a player can build fleets with (F5, client only, on top of 0354, DARK on prod)

Branch `fleets-page`, cut from `fleet-room` (migration 0354, built, not deployed). No migration, no new server door, no new read. **No pull request is open: the base migration is not deployed.** Nothing here was run on production and no switch or knob was touched; every lit flow below ran in a headless browser on a throwaway copy of the local world with `fleet_room_bite` set true inside the copy only (`tests/fleetsPage.fixture.ts`).

## The order
Owner rows 180 and 316: *"fleets - multiple fleets, with multiple ships"*; *"create multiple fleet... assign multiple ships (total of 7). Show stats of individual ship and also as a fleet... unlock slots by purchasing with gold, and some with levels."* `docs/SUCCESS_PLAN.md` section D, F5. Design: `docs/FLEETS_AND_SLOTS.md` 2.7. The look rules: screens not packed, names never cut, a press selects and moves nothing, every screen leavable both ways.

## What is built
| Part | Where |
|---|---|
| **New fleet**, on the Fleets list itself: a row under her fleets, and a page to pick the lead ship, name the fleet and press once (`cmd.move_ship` with a new name) | `src/features/fleets/NewFleet.tsx`, mounted at `FleetsScreen.tsx:159` |
| ... with one ship in the company: "A new fleet needs a second ship. Build one at a build yard." and the press that goes to the HQ's Port place | `NewFleet.tsx` `NeedShip`; the link is `yardHref` in `src/live/cityFaces.ts`; `CityScreen.tsx:262` now opens `?place=port` |
| ... with no fleet room: the next level ("Trading 3") and the next price with its Buy; after the Buy the page turns into the picker | `NewFleet.tsx` `NeedRoom` |
| **Her seven places** on a fleet's page: ship tiles, Empty tiles for room she has, Locked tiles with the level and the price next in line, one Buy on the first locked tile | `src/features/fleets/FleetShips.tsx` (`Places`) |
| **Stats**: one press on a ship's tile opens the game's one ship sheet over the fleet's page; its close, and Escape, give the same fleet back | `src/features/fleets/FleetShipSheet.tsx`; `src/live/ShipPanel.tsx` gained `overPage` |
| **Move**, in the tile (it was a grid cell of its own beside the tile), and the Move page now shows the ship's own figures, the totals of the fleet she leaves and of each fleet she may join | `src/features/fleets/MoveShip.tsx` |
| **The empty fleet** says what it is and what to do | `FleetFold.tsx:97`, word `fleets.emptyFleet` |
| **You**: one line, "Fleets a / b · Ships c / d", a link to Fleets | `src/features/you/YouScreen.tsx` `RoomLine` |
| The room read, the Buy press and a step's words, in ONE place for the Room card, the tiles and the New fleet page | `src/live/houseRoom.ts` (the Room card `FleetRoom.tsx` now reads it too) |
| Escape leaves ONE layer, the one opened last (before, every open page heard the key and all of them closed) | `src/components/ui/useBackLayer.ts`, used by `DetailPage` |
| A tile can keep a name whole, wrapped at its spaces; a tile's two figures wrap instead of running out of the tile | `src/components/ui/Tile.tsx` (`wrapName`), `ShipTile.tsx` |
| Words, EN and KO | `src/lib/i18n/dict/fleets.ts`, `you.ts` |

## The flows, as measured (headless Chromium, 390×844 and 1280×800, English and Korean)
- **A second fleet: 3 presses and a name.** New fleet (1) → the ship that leads it (2) → type the name → Make fleet (3). The list then shows two fleets and the new one carries the chosen name ("Armada do Sul Dourado", whole at both widths). Before this slice it was also 3 presses, but nothing on the Fleets list said so: the fleet's row, then Move on a ship, then New fleet inside that ship's pop-up, and with one ship it emptied the fleet she came from.
- **A ship place bought:** on the fleet's page the first Locked tile reads "Seamanship or Command 1 / 10,000" with Buy. One press: the purse falls by exactly 10,000, that tile becomes Empty, the next Locked tile now carries the Buy at 20,000. No ship tile, totals line or foot button moved (boxes compared to the pixel).
- **A ship's sheet:** Stats on the tile, one press. The sheet stands over the fleet's page (the whole glass on a phone, a side panel at the window's edge on a laptop). Its ✕ and Escape each give the same fleet's page back; a second Escape leaves the fleet's page.
- **A ship moved back:** Move on the tile, one press, opens the Move page: "This ship" (attack, hull, crew, speed), "From <fleet>" with that fleet's totals, "Move to" with each fleet she may join and its totals, and the line "These are the totals now. A move changes both fleets." A press on the fleet moves her.
- **The empty fleet:** her page reads "No ships" and "This fleet has no ships, so it cannot sail. Open a ship in another fleet and press Move to bring it here.", with Rename and no Command. Her row in the list reads "No ships".
- **No fleet room left** (an empty fleet still counts as a fleet): New fleet opens on "No room for another fleet. More room opens this way:", then "Trading 3", then "60,000" with Buy. One press: the purse falls by exactly 60,000 and the same page becomes the picker. The Room card then reads Fleets 2 / 3.
- **You:** "Fleets 2 / 3 · Ships 2 / 9" after the above; dark, "Fleets 1 / 2 · Ships 2 / " and the server's dark hull cap. A press lands on Fleets.
- **One ship only:** New fleet says a second ship comes from a build yard; its press lands on `/city?port=<her port>&place=port`, and the browser's Back returns to Fleets.
- **Dark** (the real state on prod): the New fleet row is a line, "New fleet · Not open yet", not a button; the Room card says "Not open yet" with no button; each Locked tile says "Not open yet"; there is no Move, no Buy and no Make fleet anywhere. Totals, Rename, Command and each ship's Stats are there.

## Pictures (docs/dev-log/img/2026-11-11-fleets-page-*.jpg)
Before (branch `fleet-room`, the same lit world of two ships): `before-list-lit-390-en`, `before-list-lit-1280-en`, `before-fleet-page-390-en`, `before-fleet-page-1280-en`, `before-you-390-en`, `before-you-1280-en`.

After, each at `-390-en` and `-1280-en`: `list-lit`, `new-fleet`, `two-fleets`, `fleet-page`, `ship-sheet`, `move`, `empty-fleet`, `new-fleet-no-room`, `you`, `new-fleet-one-ship`, `list-dark`, `fleet-page-dark`. In Korean at 390: `new-fleet-390-ko`, `fleet-page-390-ko`, `fleet-page-dark-390-ko`, `empty-fleet-390-ko`.

They are written by the spec itself when `FLEETS_PAGE_SHOTS=1` is set.

## What F5 could not show without a migration
- **The totals AFTER a move.** `public.fleet_totals` answers for a fleet as she stands, and the wage a day and the slowest ship are the server's own rules. No read answers "this fleet without that ship" or "with it". Adding one is a migration, so the Move page shows what is served (the ship's figures, both fleets' totals now) and says so. A cheap read for it would be one STABLE function, `world.move_preview(ship, to_fleet)`, calling `fleet_totals` twice on edited ship lists.
- **The waves warning** of design 2.5 ("Waves 24 → 21. The North Atlantic will be closed"). The fleet's wave figure after a move is the same missing read.
- **Why a fleet may not found a new one.** `world.ship_moves` answers `can_new` true or false with no reason. The page says the rule in one sentence ("docked with no orders running") instead of the case.
- **Which locked place a mixed step opens.** Levels and bought steps add up (0321), so the tiles pair the Nth locked place with the Nth level rung and the Nth price still shut. A level and a price together open it sooner than its line says; the tiles are read again after every step.
- **Guns, and crew able to board:** not served (0354's dev-log), so not drawn.

## Decided by default (the owner may reverse)
- **Where New fleet stands:** the last row of the fleets list, with a plus mark. Not a button in the title, not a card of its own.
- **Only a fleet of two or more ships offers a lead ship.** Taking a fleet's only ship would leave that fleet empty. The Move press on a tile still allows it, as before.
- **The name is typed, not suggested.** The field starts empty; the button wakes at 3 letters, the server's own floor.
- **A ship's tile carries two small buttons, Stats and Move,** rather than making the whole tile one press: two different things on one tile need two targets.
- **The sheet opened from Fleets seats captains while the fleet is docked,** exactly as the same sheet does on the Map. (Captains' own files were not touched.)
- **Locked tiles are drawn dark too,** each saying "Not open yet" and nothing else: no level and no price, because dark the server's rule is different (2 + Seamanship; Command and gold do not count yet).
- **The ships, cargo and supplies stay three columns on a laptop** (owner row 89), so seven tiles stand two across in the first column. One wide row of seven was the other choice; it would break row 89.
- **Words:** "Empty" and "Room for a ship" for a place she can fill, "Locked" for one she cannot, "Stats" for the sheet, "Make fleet" for the press. `docs/WORDS.md` bans "slot" and "berth", so neither is printed.
- **You's second pair is the company's ships over the company's ship cap** (`hulls` of `world.house_room`), not "room for N ships each" as design 2.7 sketched: the brief asked for "Ships c / d".
- **The yard link opens the HQ's Port place** of the port a fleet of hers lies in. The Build row is one more press from there; a port with no build yard says so on that panel.
- **The map's fleet pill is not changed:** `src/features/map` was another builder's in this window.

## Checks run (this PC, headless, one worker, served build on port 4963)
- `tsc -b`, `eslint .`, `vite build` (the world image restored from a private copy of the cache; the shared cache was not written): clean.
- New: `tests/fleets.page.spec.ts`, 12 of 12 (three tests at each of 390×844 and 1280×800, in English and in Korean). It does not skip when nothing is served: it fails.
- `fleets.design` `fleets.move` `fleets.room` `fleets.you.grow` `you.design` `captains.sheet` `fleet.supplies` `onepage` `layout` (whole) `wide.layout` (whole) `consistency` (whole) `sections` `duplication` `words` `i18n.keys`: all passed, none skipped.
- Two reds on the way, both the same cause and fixed: the tile's Stats button was 36 px tall, under the 44 px reach floor (`layout` FLEETS and `consistency` at both widths). The tile's buttons are now the full 44 px.
- The before pictures were taken from branch `fleet-room`'s own build, served on a second port for one run and stopped.

## Not proven
- Nothing ran on production, and the page has never met a real lit server: the lit flows are the local PGlite world.
- A company at the top (5 fleets, or 7 ships a fleet) and a company whose next step is level only (every price bought): the tiles and the New fleet page were written for them ("You have every fleet there is.", a Locked tile with a level and no price) but no test world reaches them.
- A purse too small for the next price ("Not enough gold" in place of Buy): the lit worlds here are paid 200,000, so it is not pressed in a test. The Room card's own spec (`tests/fleets.room.spec.ts`) proves the server's `can_pay` on a founding purse.
- Two fleets in different ports, a fleet at sea, a fleet with orders running: the New fleet page then prints the one-sentence rule. Not walked in a browser.
- The yard link when no fleet is in a port (all at sea): it goes to `/city?place=port`, the HQ's own choice of port. Not walked.
- Seven real ship tiles with the locked tiles gone (a full fleet) at 390: the tiles are the same `ShipTile` field `tests/drive.nav.spec.ts` already draws seven of, but that spec was not run here.
- Korean on the laptop width was run and passed the laws, but its pictures were not kept.
