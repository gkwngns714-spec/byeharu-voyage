# 2026-11-06 One colour and a smaller hull for the cargo ship

Owner: *"unify the color of cargoship. and make more, reduce size like normal ship but slightly bigger"*. Client only, no migration. (The "make more" is the ship count, not this change.)

## What changed

- **One colour.** `--color-cargo-hull` (#ff9460, a light coral) in `src/index.css`, named once by `KIND_LOOK.cargo.fill.token` in `src/chart/glyphs.ts`. `KIND_LOOK.fill` is now `{ token }` (the old `dayShare` and `inked` are gone). `HullGroup`/`FleetsLayer` read the token and write `--kind-fill`; `.bv-sun-kind-fill` paints it. The same colour by day and by night, whatever her nation and whatever the Regions filter says. No kind is named in the renderer. Her card, the Compendium entry and the cargo sheet all draw `CargoHull`, which now fills with the same token (it was the gold accent).
- **Why this colour.** It must hold 3 : 1 as fill or keyline on every ground (night sea, day sea, deep, shallow, and the twilight mixes). #e8643c and #ff7a45 failed at `--night` 0.25 and on day deep; #ff9460 passes everywhere. Not gold (yours), not the pale day deck or the blue of a merchant.
- **Size.** `cargoHullHalfLength` 9 to 7: 15 % over the heavy galleon (6.1), 31 % over the nau (5.35). Owner said reduce, so this is a reduction. The old design test that made her longer than every hull, flagship (8.3) included, now covers ordinary hulls (sizes 1 to 4). Bars are 0.3 x 7 = 2.1 px thick, still at least 2 px; they read at 1x (`kinds-1x.png`).
- **`thin`.** `KIND_LOOK.cargo.thin` is false, so `shipMarks` never drops her at any zoom. Only merchants are thinned (widest tier, keep 6 of 8). 100 cargo ships are all drawn; no change needed.

## Proof

`tests/map.kinds.spec.ts` (contrast law, one colour for 8 nations at night and by day, size) and `tests/cargo.design.spec.ts`, plus `map.hulls` and `map.wrap`, pass. Pictures at 1x and 2x: `docs/dev-log/2026-11-06-cargo-colour/kinds-1x.png`, `kinds-2x.png`.

## Update (owner, later 2026-11-06: "don't like the color. change the size smaller too")

- **Colour.** `--color-cargo-hull` is now #2fd4b0, a teal green (was coral #ff9460). Still one token, still no other colour logic. The law holds on every ground: the hull fill or keyline is at least 3 : 1 (day sea fill 2.39 but keyline 3.63; day deep fill 4.38; night 10.42; day shallow keyline 8.81; twilight steps pass), and the bars are 8.67 : 1 or better on the fill.
- **Size.** `cargoHullHalfLength` 7 to 5.8: 8 % over the nau (5.35), 5 % under the heavy galleon (6.1). She no longer exceeds the galleon, only ordinary merchants up to the nau. `tests/cargo.design.spec.ts` now compares her with sizes 1 to 3 and says so.
- **Bars.** At 5.8 the old 0.3 proportion gave 1.74 px, under the 2 px rule. Bar thickness is now 0.36 of the half-length = 2.09 px, gap 0.1 (both bars end at 0.94 of the half-length, inside the hull). The size was not touched for this.
- **Beam.** 0.74 to 0.8 of the half-length (hull and bar width both): at the smaller size she differed from the capital hull by 19.6 % of her area, under the 20 % silhouette test; the wider beam restores it.
- **Proof.** Headless render of the real FleetsLayer on the built stylesheet (no live game, no writes), DPR 1 and 2, night, twilight and three day grounds: `docs/dev-log/2026-11-06-cargo-colour/kinds-1x.png`, `kinds-2x.png` (regenerated). Specs map.kinds, cargo.design, map.hulls, map.wrap: 45 passed, 2 skipped (they need a served build).
