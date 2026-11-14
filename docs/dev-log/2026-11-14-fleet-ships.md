# 2026-11-14: a fleet shows her ships; a ship shows her cargo and supplies

The owner's order, verbatim: *"in fleets, when pressed a fleet, show only ships, then when i press the ship, show cargo and supplies."*

Client only. No migration, no server change, no switch touched.

## What a pressed fleet showed before

Everything at once, on one page (`fleet-page`):

1. The voyage, while she sails: where she is bound, how far along, when.
2. Her totals: attack, hull, crew, wages, wave resistance, the slowest ship, a ship short of crew.
3. Ships: a count line ("2 / 2 ships · 7 at most"), one tile a ship (name, class, speed, crew, hold, hull bar, the Power line, what is mounted, a Stats button, a Move button), then the empty and locked ship places with their Buy.
4. Cargo: the goods of the whole fleet added together, a total, and what the hold is made of.
5. Supplies: supply room, days of supplies, crew.
6. The "If attacked" picker (Fight, Flee, Pay).
7. A battle, while she is in one.
8. Command and Rename.

## What it shows now

**Step 1, press a fleet:** her ships, one row each, and nothing above them. A row is the ship's name (whole, it wraps and is never cut), her class, a hull bar with its per cent, and the cargo bar with tons used of tons she holds. Under the ships stands one plain row, `More`.

**Step 2, press a ship:** her own page, titled with her name, with the page's back arrow (and Escape) leading back to the ships list as it stood.

- Her hull bar and her cargo bar (used / capacity).
- Cargo: each good and its amount, the total in tons, and what her hold is made of.
- Supplies: water in tons, food in tons, her supply room (while the server serves one), the fleet's days of supplies under the label "Whole fleet", and her crew.
- The Power line her tile carried (owner row 288), then Stats (her whole sheet) and Move.

## Where each thing went

| Was on the fleet's page | Is now |
| --- | --- |
| Ship tiles | Ship rows on the fleet's page (name, class, hull, cargo) |
| A ship's crew, speed, mounted gear | Her Stats sheet (crew also on her page) |
| A ship's Power line | Her page |
| Stats, Move | Her page |
| Cargo (fleet total) | Each ship's page, her own goods |
| Supplies | Each ship's page |
| Totals line | More |
| Voyage progress | More |
| "If attacked" picker | More |
| A battle in progress | More (the More row says "Battle" while she is in one) |
| Command, Rename | More |
| Ship places and their Buy | More, under "Room" |
| An empty fleet (No ships, how to fill it, Rename) | Unchanged, on the fleet's page |

## Is cargo per ship or per fleet?

Per ship, and served. `world.fleets` hands the client `cargo`, `cargo_tuns`, `water_t`, `food_t`, `hold` and `stores_cap` for every ship (`FleetShip`, src/lib/rpc/types.ts). The old page added them up across the fleet; the ship's page prints one ship's own figures. Nothing is split or invented by the client.

Two things are NOT served per ship:

- **Days of supplies.** The server serves one figure a fleet (`endurance_days`). It stands on the ship's page as "Whole fleet · 15.0 days" so it is not read as the ship's own.
- **`store_ratio`.** The column exists on `public.ships` but no read serves it to the client, so it is not shown. Showing it would need a server change; not done.

## Decided by default (the owner may reverse any of these)

1. **Fleet-wide things are folded behind one `More` row** at the foot of the ships. Nothing a player could do before became impossible; each is one press further.
2. **The fleet's added-up cargo list is gone.** The fleet's row in the list still shows her total cargo bar and days of supplies, and the company card her total hold. The goods themselves are read ship by ship.
3. **A battle is behind More too**, because the order says "only ships". So it is not hidden behind a word that does not name it, the More row reads "Battle" while she fights.
4. **Stats, Move and the Power line went to the ship's page.** They belong to one ship.
5. **The empty and locked ship places went to More**, under "Room". The Room card beside the fleet list still carries the same Buy.
6. **Only the Fleets screen changed.** The map's fleet tray, the Send tray and the HQ do not use this page (the map tray has its own ship list and opens the same ship sheet), so they are untouched.

## One authority, not two

- `FleetCargo`, `FleetHold` and `FleetStores` were not copied for a ship. Their folds in `domain/fleet` now ask for `Hulls` (`{ ships }`), so the same face reads a whole fleet or `{ ships: [ship] }`.
- `HullGauge` is the hull bar of the fleet's row and of a ship's row: the tone rule is written once.
- `ShipPowerLine` is the Power line of `ShipTile`, exported so the ship's page prints the same line.

## Words

Two new, EN and KO, in `src/lib/i18n/dict/fleets.ts`: `More` / `더 보기`, `Whole fleet` / `선단 전체`. `Water` / `물` and `Food` / `식량` were already in the dictionary.

## Checks

- `npx tsc -b --noEmit`, eslint on the touched files, `npx vite build`: clean.
- New spec `tests/fleets.ships.spec.ts`: the two steps, the More page, Stats and both ways back, at 390×844, 320×640 and 1280×800, in English and Korean (6 tests).
- Specs updated for the two steps: `fleets.page`, `fleets.move`, `fleets.room`, `fleet.supplies`, `fleet.supplyRoom`, `raid.order.lit`, `fight.log.page`, `gear.wear`, `captains.sheet`, `drive.nav`, `layout`, `wide.layout`, `lit.screens`.
- An armada: `tests/fleets.armada.spec.ts` run unchanged. The armada's page lists fleets, not ships, and does not use this page.

## Pictures

Before and after, phone (390 and 320) and desktop, English and Korean, in `C:\Users\gkwng\dev\fleet-ships-shots\` (not committed): `before-fleet-*`, `after-fleet-*`, `after-ship-*`, `after-more-*`.
