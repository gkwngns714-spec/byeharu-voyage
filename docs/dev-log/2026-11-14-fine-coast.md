# A harbour's coast is a coast (2026-11-14)

The owner: *"fix the graphics overall, especially map. it is weird"*, and on the blocky coast: *"find the root cause, make it so that this problem does not occur again"*.

Zoomed right into a harbour, the coast was a few straight lines, each many kilometres long. Portugal was five of them.

## The root cause, with numbers

Two numbers were chosen in the same commit, `600d0fb3` (2026-08-18, "map: the chart declutters itself instead of overprinting"), and nothing related one to the other.

| number | value | what it was tuned for |
|---|---|---|
| the coast's data | Natural Earth 1:110m, then simplified to **0.2 degrees** (`COASTLINE_TOLERANCE_DEG`) | "about 2 px at the opening view" (the file's own header) |
| the closest zoom | **1.5 degrees** across the glass (`MIN_SPAN_X`) | names and marks not overprinting |

What those two make together, at the closest zoom:

| | phone, 390 px | desktop, 1,280 px |
|---|---|---|
| ground per pixel (at Lisbon's latitude, east-west) | 0.33 km | 0.10 km |
| the tolerance, 0.2 degrees (22 km north-south) | **52 px** | **171 px** |
| the whole glass, east-west | 130 km | 130 km |
| longest straight shore within 250 px of Lisbon / Nagasaki / Venice (desktop) | | **712 / 681 / 756 px** |

The world file keeps 3,251 shore points for the whole Earth. The drawn shore near those three harbours is one line 60 to 80 km long, on a glass that shows 130 km. The data was tuned for a view 10 times wider than the closest one on a phone and, in pixels, 85 times coarser than it was meant to look on a desktop (2 px intended, 171 px shown).

The comment on `MIN_SPAN_X` said the opposite: *"Tighter than that and the 110m coastline is visibly a polygon"*, as if 1.5 degrees were safe. It was never measured. The zoom was allowed to go far past the data, and a sentence said it had not.

**Which check should have caught it and did not.** `tests/map.coastline.spec.ts`, "simplification moves no point further than the tolerance": it holds the tolerance in DEGREES and never asks what a degree is on the glass at the zoom limit. `tests/map.perf.spec.ts` and the lag specs guard the path's size, which pushes the other way. And this morning's look pass (`2026-11-14-map-look.md`) saw it and wrote it under "Left".

## The fix, at that cause

The data that is drawn now follows the zoom, by one rule (`src/chart/fineCoastBuild.ts`, `fineLevelFor`), keyed on degrees per pixel:

| view | data drawn | simplified to | worst error on the glass |
|---|---|---|---|
| wider than 0.03 degrees a pixel | the 110m world file, as before | 0.2 degrees | 6.7 px |
| 0.03 to 0.006 | Natural Earth 1:10m land, "mid" tiles of 20 degrees | 0.03 degrees | 5.0 px |
| closer than 0.006 | Natural Earth 1:10m land, "fine" tiles of 5 degrees | 0.003 degrees (330 m) | 2.6 px at 1,280 px; 7.7 px on a 3,840 px glass |

At the closest zoom the longest straight shore near Lisbon, Nagasaki and Venice is now **93, 94 and 153 px** (it was 712, 681, 756).

How it is built and drawn:

- `scripts/build-fine-coast.mjs` cuts Natural Earth 1:10m land (public domain; 446,175 points) into tiles under `public/coast/`: 135 mid tiles (62,692 points) and 920 fine tiles (283,421 points). A tile that is all sea has no file. A tile that is all land has no file either (533 of them): the index names it and the chart paints a square. The index is `src/chart/fineCoast.generated.ts`. The 10 MB source is not in the repository; the script fetches it.
- A tile is the land inside it as closed rings of small whole numbers. The shore line is not stored: it is the rings' edges minus the ones on the tile's border (`tilePaths`).
- `src/chart/useFineCoast.ts` fetches only the tiles under the coast's sheet, only inside a level's limit, each once. `ChartCanvas` hands the coast's sheet the tiles' two path strings in place of the world file's. Nothing else changed: the same layer, the same strokes, the same sheet moved by a transform.
- A set of tiles is drawn only when every one of them has arrived. Until then the last whole set stays while it still covers the glass, and failing that the 110m coast. The strings change only when the set of tiles changes, never on a frame of a pan, so the sheet is repainted no more often than before.
- **A picture only.** The routes, the server's water and land rule, the landfall (`landfall.ts`), every harbour's position, the minimap and the wide chart all still read what they read before.

## The guard

`tests/map.fineCoast.spec.ts`, plain Node, on the real data:

- **(6)** At every zoom from `MIN_SPAN_X` to the whole world, on glasses 320 to 3,840 px wide, the data drawn there was simplified by at most **8 px**. Today's worst is 7.7. Move `MIN_SPAN_X` closer, coarsen a level, or move a level's limit, and it fails. The same law holds the 110m file alone to over 40 px at the closest zoom on a phone, so the ruler is known to see the old fault.
- **(7)** At the closest zoom on a 1,280 px glass, no straight shore within 250 px of Lisbon, Nagasaki or Venice is longer than **200 px**, read from the shipped tiles. The 110m file is measured the same way and must be over the bound (it is 3.4 to 3.8 times over).
- (1) to (4): which level, which tiles (across the antimeridian too), the shipped tiles are exactly the index, no tile over 40 KB, a tile's border is never drawn as shore.
- (5), in the browser, phone and desktop: the wide chart fetches no tile; at the closest zoom fine tiles are fetched, every one exists, and the coast on the glass is no longer the world file's; zoomed back out it is the world file again.

The false sentence on `MIN_SPAN_X` is replaced by one that names the guard.

## Weight

| | files | bytes | gzipped |
|---|---|---|---|
| mid tiles | 135 | 433 KB (heaviest 19.6 KB) | 167 KB |
| fine tiles | 920 | 2,060 KB (heaviest 28.3 KB) | 825 KB |
| the index and the code, in the map's script | | about 12 KB | about 4 KB |

Nobody downloads the totals. What a player pays, measured in the browser:

| | tiles | gzipped |
|---|---|---|
| first load, any page | 0 | 0 |
| the map opened, phone (15 degrees across) | 0 | 0 |
| the map opened, desktop (15 degrees across 1,184 px: inside the mid level) | 2 | 3.7 KB |
| the whole world, any glass | 0 | 0 |
| zooming from the world into Lisbon / Cadiz / Venice, phone | 6 / 4 / 4 | 8.9 / 11.3 / 9.7 KB |
| zooming from the world into Nagasaki / Malacca, phone | 11 / 7 | 27.7 / 14.8 KB |
| the same into Nagasaki, desktop (the heaviest seen) | 19 | 40.3 KB |

A tile is fetched after the map is already drawn, and once: the browser keeps it. The world file, for scale, is 99.5 KB gzipped on every map open.

## Looked at

Before and after, phone 390 x 844 at 2 device pixels a pixel and desktop 1,280 x 800, closest zoom, at Lisbon, Cadiz, Venice, Nagasaki and Malacca: `C:\Users\gkwng\dev\fine-coast-shots\before-<place>-<glass>.png` and `after-…`. Every "after" was opened and read: the Tagus mouth and Setúbal, the bay of Cadiz, the Lido, the Nagasaki peninsula with Shimabara, Amakusa and the Goto islands, the Malacca shore. Each of the five harbours stands on the drawn shore or right beside it.

## Harbours against the new shore, all 249

Harbour positions did not change (they are still set on the 110m shore by the landfall, as before). Measured against the fine shore at those unchanged positions: the median harbour is 1.05 nautical miles from it, 121 are within 1 mile, 202 within 3. At the closest zoom a mile is 4 px on a phone and 14 px on a desktop.

Two groups do not sit on it:

- **River cities** (Seville 29 miles, London 19, Hanoi 45, Amsterdam 12 and so on): the land file has no rivers. They were inland before too.
- **29 harbours the landfall moved onto the 110m shore now stand 2 to 8 miles from the real one**, where their true coordinate is nearer (Tainan 8.4, Tripoli 8.3, Algiers 6.6, Hoi An 5.9, Matsumae 5.6, Malindi 5.3, Toulon 4.8, Galle 4.6, Macau 4.0 …). On a phone at the closest zoom that is up to 36 px inland; four (Ternate, Salvador, Ceuta, Tidore) stand 2 to 4 miles out on the water. This is the next slice and it is not in this one, because it moves marks: close in, draw a harbour at its served coordinate (or set it on the fine shore) and not on the 110m one.

## Left, and why

- **The 29 harbours above.**
- **The speck of land under an island harbour** (30 harbours whose island the 110m file lacks) is still drawn close in, where 28 of the 30 now have their real island under them. It is a 4 px disc in the land's colour and reads as part of the island.
- **The Regions filter's land tint** is still cut from the 110m countries, so close in, with the filter on, a strip of real shore can be untinted. The filter is off by default.
- **Natural Earth 1:10m is itself drawn for about 1:10,000,000.** At the closest zoom on a desktop its own vertices are 30 to 150 px apart: a real coast's shape, not a surveyed one. Finer needs another source (for example GSHHG, 10 times heavier).
- **Venice's lagoon is land** in Natural Earth; the city stands just inside the Lido.

## Decided by default (the owner may reverse)

- **Keyed on pixels, not on the span.** The other rungs of the chart are keyed on degrees so a phone and a desktop show the same picture. Blockiness is a matter of pixels, so a desktop gets the finer data at a wider span than a phone does.
- **The desktop's opening view fetches 2 mid tiles (3.7 KB)**, because 15 degrees across 1,184 px is already close enough for the 110m file to show 17 px of error.
- **A failed tile is not retried in the session**; that neighbourhood stays on the 110m coast.

## Proven, and not

Run locally: `tsc -b --noEmit`, `eslint` on the touched files, `vite build`, `tests/map.fineCoast.spec.ts` (10 tests, the two browser ones against the served build). Not run: every other spec. Main's Acceptance run is the net: a spec that reads the coast path's size or content at a close zoom would now read the tiles' path.

Panning was not re-measured with a profiler. By construction a pan writes the same one transform as before; the path strings change only when the sheet reaches a new tile.
