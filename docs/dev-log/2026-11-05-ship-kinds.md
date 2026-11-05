# 2026-11-05 Each kind its look (W0a, owner row 291)

Owner: *"the ship type (cargo, merchant, navy) should be distinguished, as in graphics or as in color. day and night"*.
Client only. No migration, no server change. Design: `docs/WORLD_POWERS.md` section 9.

## What changed

- **One table.** `KIND_LOOK` in `src/chart/glyphs.ts`: one row each for merchant, cargo and yours (hull, mark, fill, shortest size, thinned or not). `shipKindOf` reads the kind off a served row (a merchant row still has no key). `shipMarks` now asks the table whether a kind is thinned, instead of testing `merchant.cargo`.
- **One renderer.** `HullGroup` in `FleetsLayer.tsx` takes the kind and draws a second `<path>` from `kindMarkPath` when the table has a mark. `FleetsLayer.tsx` no longer names any kind.
- **Cargo.** 0310's crown hole is gone (5.9 x 5 px at 1x, read as mush). Two solid bars across her beam name her instead, each 0.3 of her half-length thick (2.7 px at her 9).
- **Day keyline.** New `.bv-sun-hull-keyline`: by day the outline of a hull is `--color-chart-day-mark` (#16212c) instead of the day sea (which shows nothing by construction); at night it is the sea, as before. Ports keep the old `.bv-sun-keyline`, so nothing else on the map moves.
- **Cargo day hull** keeps 45 % of her nation's ink over the pale deck (`--kind-day-share`, set from the table); a merchant keeps 0, so her fill is unchanged.
- **Mark ink** `--color-kind-mark` (#0b0f14), turned over to the day's near-black at `--night` 0.5, like a name.

## The proof, red then green

`tests/map.kinds.spec.ts` server-renders the real `FleetsLayer` for each kind, lays it on each ground in a headless browser with the BUILT stylesheet, and reads the colours the browser computed.

Red on main (11 of 14 failed, the rest are the structure checks that need the new table; this is the first run, before the code existed): day shallow merchant fill 1.64, her keyline 2.43; yours on day sea 2.34, on deep 2.78, keyline 1.00.

Green here (15 tests, all pass): fill or keyline is at least 3 : 1 for merchant, cargo x 8 nation inks and yours, on night sea, night sea in the light theme, day sea, day deep, day shallow, and at `--night` 0, 0.25, 0.5, 0.75, 1 on the mixed sea; the mark is at least 7.3 : 1 on every cargo fill. A few real figures (best of fill and keyline):

| Ground | merchant | cargo (worst nation) | yours |
|---|---:|---:|---:|
| night sea | 3.07 | 7.40 | 10.19 |
| day sea | 3.99 | 3.63 (keyline) | 3.63 (keyline) |
| day deep | 7.31 | 4.97 (fill) | 3.04 (keyline) |
| day shallow | 8.81 (keyline) | 8.81 (keyline) | 4.84 (keyline) |

Also checked: cargo differs from each of the twelve merchant silhouettes by at least 20 % of her area at 1x and 2x; bars at least 2 px; FleetsLayer has one `hullPath(`, one `HullGroup`, one `kindMarkPath(`, and no kind name; a merchant row carries no kind and no merchant hull gains an element.

## What the doc got wrong (found by measuring)

- The "light sea" ground never occurs on a chart: `.bv-chart-night` puts the night palette back on the chart in both schemes. So the mark ink has no pale variant, and the light theme measures the same as the dark one.
- 45 % held: the day cargo fill alone is 2.7 to 3.2 : 1 on day sea, 1.1 to 1.3 on the shallows, which is why the dark keyline matters there. On the shallows it is the keyline that carries her.

## Pictures

`docs/dev-log/2026-11-05-ship-kinds/kinds-1x.png` and `kinds-2x.png` (the owner's laptop is DPR 2). Each kind at chart size, bow up and on a course, on night, twilight, day sea, day deep and day shallow, and 4x to read the shapes. Rows: merchant (Regions off, the one blue), merchant in a nation ink (Regions on), cargo in three nations, yours.

Honest reading of them: the cargo ship is told from a merchant by her wide blunt hull and the two dark bars, at 1x as well as 2x, by night and by day. By day, her tint (a pastel of her nation) is a weak second channel next to a merchant's white. The bars carry her, not the colour. A merchant's day hull is still the same white for every nation, as before; I did not change that.

## What these pictures are not

They are the real `FleetsLayer` and the built CSS in a headless browser on flat grounds. They are not a served map with a real cargo ship on it: no cargo ship exists yet (0310 stands dark), so this is not verified on the live map. Navy and pirate are not drawn: they have no shape and no row (W12, W17).

## Rollback

A client revert. No server state.
