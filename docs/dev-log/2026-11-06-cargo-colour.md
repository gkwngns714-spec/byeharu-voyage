# 2026-11-06 One colour and a smaller hull for the cargo ship

Owner: *"unify the color of cargoship. and make more, reduce size like normal ship but slightly bigger"*. Client only, no migration. (The "make more" is the ship count, not this change.)

## What changed

- **One colour.** `--color-cargo-hull` (#ff9460, a light coral) in `src/index.css`, named once by `KIND_LOOK.cargo.fill.token` in `src/chart/glyphs.ts`. `KIND_LOOK.fill` is now `{ token }` (the old `dayShare` and `inked` are gone). `HullGroup`/`FleetsLayer` read the token and write `--kind-fill`; `.bv-sun-kind-fill` paints it. The same colour by day and by night, whatever her nation and whatever the Regions filter says. No kind is named in the renderer. Her card, the Compendium entry and the cargo sheet all draw `CargoHull`, which now fills with the same token (it was the gold accent).
- **Why this colour.** It must hold 3 : 1 as fill or keyline on every ground (night sea, day sea, deep, shallow, and the twilight mixes). #e8643c and #ff7a45 failed at `--night` 0.25 and on day deep; #ff9460 passes everywhere. Not gold (yours), not the pale day deck or the blue of a merchant.
- **Size.** `cargoHullHalfLength` 9 to 7: 15 % over the heavy galleon (6.1), 31 % over the nau (5.35). Owner said reduce, so this is a reduction. The old design test that made her longer than every hull, flagship (8.3) included, now covers ordinary hulls (sizes 1 to 4). Bars are 0.3 x 7 = 2.1 px thick, still at least 2 px; they read at 1x (`kinds-1x.png`).
- **`thin`.** `KIND_LOOK.cargo.thin` is false, so `shipMarks` never drops her at any zoom. Only merchants are thinned (widest tier, keep 6 of 8). 100 cargo ships are all drawn; no change needed.

## Proof

`tests/map.kinds.spec.ts` (contrast law, one colour for 8 nations at night and by day, size) and `tests/cargo.design.spec.ts`, plus `map.hulls` and `map.wrap`, pass. Pictures at 1x and 2x: `docs/dev-log/2026-11-06-cargo-colour/kinds-1x.png`, `kinds-2x.png`.
