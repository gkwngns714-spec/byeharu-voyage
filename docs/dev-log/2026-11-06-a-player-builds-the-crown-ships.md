# A player builds the crown's ships (migration 0332, live on deploy)

The owner, 2026-11-06: *"you need to make ships too, so that players can build these cargo and navy ships too."*

**State: built, PR open, not deployed.** Stacked on W12 (0331, #537), which deploys first: this file reads `navy_ship_class`.

## What already existed

**All three hulls could already be built.** A crown ship is a class, every class has a row in `hull_recipes`, and `cmd.do_build` is one verb over that table with no list of hulls in it. Before this slice a player could lay down `qpinnace`, `navire` and `galion` at the right yard with the right skills. Proof 39's build, gate, money and ordinary-ship checks exercise that verb, which this file does not touch.

What was missing is that nothing said so. The yard and the Codex list 103 hulls, and none was named as the ship a player sees at sea. The Codex's cargo card named no class.

So this slice adds no shipyard path, no flag and no class row, and it moves no price.

## What it does

- **`public.crown_classes()`** reads the three knobs that already decide a crown's class: `convoy_ship_class`, `convoy_armed_class`, `navy_ship_class`. A flag on the class would be a second copy of those knobs. No rule reads it: it is a label.
- **`crown`, 'CARGO' or 'NAVY'**, served on `world.snapshot` `ship_classes[]` and `world.building_yard` `hulls[]`. Absent on every other class, so those rows are byte for byte what they were.
- **Yard:** the badge on the tile, those hulls first in their group, a Type row and one line in the tray: "Yours to run: you pay crew and supplies."
- **Codex:** the badge, a Type filter, the search finds "cargo ship" and "navy ship", a tray row, and each side card says which class to build. `HullCrown` is the one renderer. The word is the chart's own (`map.cargoShip`, `map.navyShip`).
- **No switch.** Nothing a player could not already do is opened, so there is no balance change to hold back.

Re-cut by hunks, each once and reversing: `world.snapshot` (2), `world.building_yard` (2).

## Prod figures, head 0330, read-only

A player pays labour plus materials: the existing rule, a quarter of `build_cost` plus goods. The materials figure is `base_value`, not a market price. A capital pays full `build_cost` for a navy hull (`BUILD_NAVY`, 0331), because it brings no materials.

| | `qpinnace` | `navire` | `galion` |
|---|---|---|---|
| Is | Cargo ship today | Armed cargo ship (W8, dark) | Navy ship (W12, dark) |
| Size, yard tier | 1, 1 | 3, 3 | 4, 3 |
| `build_cost` | 126,000 | 630,000 | 1,156,000 |
| Labour paid by a player | 31,500 | 157,500 | 289,000 |
| Materials at base value | 4,838 | 20,388 | 28,543 |
| Hold, attack, speed | 96, 0, 21.3 | 1,200, 130, 13.8 | 1,260, 250, 14.4 |
| Yards today | London, Antwerp | Marseille, Genoa | Marseille, Genoa |
| Skills | English Small 5, Survey Ships 1 | French Light 3, French Medium 1 | French Heavy 1, French Medium 3, Ships of War 1 |
| Study, with prerequisites, at 1,800 SP an hour | 1,210.7 h | 16.7 h | 44.3 h |

- Yards follow the port's flag, `public.yard_wrong_country`. France's third yard, Bordeaux, is tier 2, too small for `navire` and `galion`.
- `navire` and `galion` are T1 hulls, on the ladder. `qpinnace` is a T2 explorer.
- Stock at those four yards covers each recipe: Marseille, the lowest, holds 4,740 timber, 3,140 masts and spars, 5,100 tar, 1,964 nails.
- No human on prod holds any of these skills yet. The second-richest house holds 235,000 d., so it could pay for `navire` but not `galion`.
- Study hours are a sum of `skill_sp_for` over the first prerequisite of each skill, at the base rate. They are arithmetic, not a played run.

## Balance, measured, labour plus materials at base value, 103 hulls

| | Hold per ducat, rank | Attack per ducat, rank |
|---|---|---|
| `navire` | 27 | 30 |
| `galion` | 56 | 22 |
| `qpinnace` | 78 | 90 (no guns) |

The best hold per ducat stays `buss`, `shachuan`, `fluyt`. None of the three beats every hull. No risk appeared, so nothing is behind a switch.

## A player's such ship

An ordinary player ship. `public.fleet_kind` asks `cargo_ships` and `navy_ships`, never the class, so she answers COMPANY. Proof 39 proves it for each class: no origin, no crown row, no crown figure moved, nowhere on the crown's sea read, her own wages and dock fees, her repair paid by her purse, and `public.attack_for` refuses her with E_HUMAN_TARGET. Reading `glyphs.ts`, `shipKindOf` draws only from those served kinds, so nothing in the client reads her class to draw a crown's colours. No browser spec draws a built hull.

## Proof

- `scripts/db/proofs/39_a_player_builds_the_crown_ships.sql`: 10 markers. Every class comes from `public.crown_classes`, so a turned knob is proved too. Closed as on prod, one build open as CI's default world.
- `scripts/ops/harness/crown-ships/proof-0332.mjs`: red first, parity equal (37 lines: the snapshot and every yard, with the new key off), real file green, 14 mutations each red for its own reason.
- `tests/crown.ships.spec.ts`: 1440, 1024, 390 at DPR 2, plus Korean at 390: the badge, the order, no sideways scroll, a press moves nothing.
- Prod read-only, 2026-11-06, head 0330: `before.sql` found all 4 hunks once. `after.sql` is the check after deploy.

Reading the renders found what the spec could not, both fixed: at 1440 "Cargo ship" split across two lines inside its pill, now pinned by the spec; and the tray's note sat on the Type row's rule.

First runs found two weak checks, both fixed:
- The self-assert compared with `<>`, and `string_agg` over no rows is null, so a missing mark passed it. It now uses `is distinct from`.
- The proof took its expected price from `yard_labour`, the function a build calls, so a cheap crown hull would have passed. It now reads the recipe.

## Not verified

- **The Codex's side cards with `Build: ...`.** A local world has no cargo ship, so the card does not draw there. It needs a live `cargo_ships` count. The list, filter and tray are verified.
- **A full build by a browser press.** No spec presses Build: proof 39 runs the verb and the spec stops at the tray.
- **The materials and study figures in play.** They are read and summed, not played through by a real company.

## Decided by default

- **Both cargo classes are named.** `qpinnace` sails today and `navire` is what W9 lights.
- **No price, gate or yard changes.** `ship_classes` and `hull_recipes` are data, so the owner can change them.
- **Crown hulls stand first in their yard group.** A presentation of the served list.

## Owner must see

- `qpinnace` takes 1,210.7 hours of study, so the cargo ship sailing today is close to out of reach. `navire` takes 16.7.
- From Lisbon these hulls show under "Built abroad only". Each is built at only two yards today.
- The Codex's navy card stays hidden until a navy ship exists. The Galion row and its filter show now.
- `navire` is a French trade hull and `galion` a French warship, because the knobs point there. Any other class is one knob away.

## Rollback

Forward, a new migration: reverse the four hunks and drop the function. No row, ship or gold depends on it.
