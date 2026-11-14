# The night half of the map: a night version of the same world (2026-11-14)

Owner: *"fix the graphics overall, especially map. it is weird"*, and of the dim night half: *"find the root cause, make it so
that this problem does not occur again"*.

The map shows real day and night. The day half looked right. The night half was a near-black sea, dull grey land and a coast
that was hard to follow.

## The root cause

The night sea was never chosen as a water colour, and no check measured whether the ground itself could be seen.

1. **The sea was the page's background.** `--color-chart-sea` was an alias of `--color-sea-2` (#070c14), a step of the app's
   own page colour, since `df045ba9` (2026-09-09, "one family, one scale and two schemes"). Its contrast against pure black
   is 1.07 to 1. On a phone that is black.
2. **Every law was a ratio against that ground.** `tests/chart.ink.spec.ts` (from `9b97d02f`, 2026-08-23) holds the coast to
   3 to 1 on the sea and the land inside [1.9, 2.6) of the sea. Both are measured against the ground, and nothing measured
   the ground. A ground nobody can see passes every one of them. And the land's ceiling, 2.6 to 1 on a black sea, is a dull
   dark grey: the law that kept the land quiet also kept it dim.
3. **A second law pinned the sea black.** The merchants' one dark blue, #2a5bb8 (`f5597510`, 2026-10-13, the owner's "dark
   blue"), must read 3 to 1 on the night sea (`tests/map.kinds.spec.ts`, `2c515c7b`, 2026-11-05). That blue reads 3.07 on
   #070c14 and under 3 on anything lighter, so the sea could not be lifted without a red, and nobody was looking for the
   cause there.
4. **The vignette went darker still.** `--color-chart-deep` #03060b at 62 % at the glass's edge (`9c9e245e`, 2026-09-13):
   1.05 to 1 off black. PR #672 took the vignette off the same day as this change (the sea is flat: a point of water has
   one colour by night and one by day), so this slice adds no gradient and nothing keyed to the glass or the zoom.
5. **Then the day arrived beside it.** The Sun (2026-10-14) painted a bright day half next to that night, and its notes say
   "the night tokens did not move". Black beside a lit ocean is what the owner saw.

So each later pass (the last was #667, `f3a5d710`, earlier today) could only move the land and the coast inside the band the
black sea allowed. That is why #667 ended with "anything brighter is a redesign of the night and was left".

**Which check should have caught it and did not:** `tests/chart.ink.spec.ts`, "the coast is drawn on the chart's OWN sea, and
stands clear of it". It is the chart's colour law and it was green the whole time, because it measured ink against ground and
never the ground, never the land's colour, never the coast against the land, and never night against day.

## The fix, at the cause

The three inks are colours of their own, not mixes into a page colour (`src/index.css`).

| token | old | new | what it is |
|---|---|---|---|
| `--color-chart-sea` | #070c14 (`--color-sea-2`) | **#0b1b33** | a deep navy |
| `--color-chart-land` | #3f4d4b | **#37523f** | a dark green: the land's colour at night |
| `--color-chart-coast` | #6a7481 | **#8aa0b0** | a pale edge, seen from both sides |
| `--color-merchant` | #2a5bb8 | **#3066c8** | still the dark blue; 3 to 1 on the navy sea |
| `--color-navy-hull` | #c4a1ff | **#c9a8ff** | see below |
| `--color-pirate-hull` | #ff9696 | **#ff9d9d** | see below |

The last two: `map.kinds` holds every hull to 3 to 1 on the twilight grounds too, and at a quarter night the ground is a little
lighter on the navy sea. The violet fell to 2.97 and the coral to 3.02. Seven units of lightness each puts them back where
they were (3.17 and 3.18). Nobody will see the difference in the hulls.

The shallows, the relief, the names' halos, the hulls' keylines and the minimap all read the sea token, so they followed with
no change. The day half and the Sun's mask were not touched.

## The numbers (measured in the running game by `chart.ink.spec`, 390 px)

| what | old | new | the law |
|---|---|---|---|
| night sea, off pure black | 1.07 | **1.22** | at least 1.15 (new) |
| night sea is blue (blue minus red) | 13 | **40** | at least 30, and blue over green over red (new) |
| land on sea | 2.22 | **2.00** | [1.9, 2.6), unchanged |
| land's colour (green over red and blue) | 2 | **19** | at least 12 (new) |
| coast on sea | 4.13 | **6.35** | at least 4.5 (was 3; the 3 still stands as WCAG's floor) |
| coast on land | 1.86 | **3.17** | at least 2.5 (new) |
| a quiet harbour's mark on land | 2.54 | **2.49** | above land on sea, unchanged |
| day sea over night sea | 4.36 | **3.84** | at least 3 (new): night is still night |
| day land over night land | 3.28 | **3.19** | at least 2.5 (new) |
| the dark end of the painted night glass, off black | 1.06 (with the vignette) | **1.22** | at least 1.12 (new, pixels) |
| the day glass over the night glass (medians) | 3.79 | **3.63** | at least 2 (new, pixels) |
| merchant hull on the night sea (`map.kinds`) | 3.07 | **3.17** | 3 |

## The guard

`tests/chart.ink.spec.ts`, section 3, in the same test that was green through the defect. No old number was loosened: every
old law still stands, and these are added.

- From the elements that wear the tokens: the sea's own light and that it is blue; the land's colour; the coast on the sea AND on the land; the day sea and land over the night's.
- From the pixels: Playwright's clock holds the game's Sun on the far side of the world from the middle of the glass, the
  glass is photographed, and the dark end of its pixels (the 10th percentile) must be 1.12 to 1 off black. Then the Sun is
  held overhead and the same glass must be 2 to 1 lighter. A sheet, an overlay or a gradient that paints the night black
  again fails here whatever its token says.

Proved red: with the old tokens put back on the page (before the rebase on #672, so with the vignette), the test failed on the
sea 1.07, not blue, land grey, coast on sea 4.13, coast on land 1.86 and the dark end of the glass 1.06.

## What was looked at

Before and after, same views, the clock held: phone 390 x 844 (2 device pixels a pixel) and desktop 1280 x 800; the widest
view, Europe at a middle zoom, Lisbon close; night, the terminator and day; in the merchants-on world, and the fight's world
by night. `C:\Users\gkwng\dev\night-look-shots\before` and `\after`, the same file names. (The "before" set is main before
#672, so it also shows the vignette that PR removed.) And the night Pacific at 1920 x 1000, brightened four times, for
bands or blocks: `after\big-wide-day.png` and `after\big-night-pacific-x4.png`.

Harbour lights, merchants' lamps and hulls, the fleet's gold mark and name, harbour names, sea names (on the water and across
land), the routes' lines, the minimap and the glass's corners were read on the new night. The day pictures are the same as
before.

## The dark Arctic at the widest view: not a defect of the raster or the mask

At the widest desktop view the sea north of about 75 N is dark all the way across, over the day half too, with a soft edge,
while the top bar says 11 May. The raster (`sun.ts`) and the mask (`DaylightSheet.tsx`) are right for the instant they are
given. The instant is `gameSunInstantMs` (`src/lib/format/time.ts`): **today's REAL date** at the game clock's hour, and its
own comment says so ("so the season is the real one"). The real date is 14 November: the Sun stands 18 degrees south, so the
polar night begins near 72 N (full daylight at noon ends at 72.6 N, 80 N is half twilight, the pole is dark), and the same
picture shows Antarctica lit all the way round. The printed date runs on the calendar clock (a game month a real day), which
the code keeps apart from the hour hand on purpose (D.3).

So it is a decision, not a fault: the Sun's season is the real world's, the printed date is the game's, and in November they
disagree by half a year. Putting the Sun's season on the game's date is one line in `gameSunInstantMs`, but it turns the
seasons round every twelve real days and moves `map.sun`'s expectation. Left for the owner to choose; nothing changed here.

## Left, and why

- **The night land is one green everywhere** (the Sahara and Greenland too). The day land is a gradient by latitude; a second
  one by night is another full paint of the land on every zoom step, and the chart's laws pin the body to one token. A flat
  dusk green reads as land; the bands were left.
- **`map.kinds` writes two pictures into `docs/dev-log/2026-11-06-cargo-colour/`** when it runs. They were not staged here.

## Checks

`tsc -b --noEmit`, `eslint` on the touched files, `vite build`. `tests/chart.ink.spec.ts`: 9 green. `tests/map.kinds.spec.ts`
(it measures the hull tokens this moved): 24 green. No wide run. No migration.
