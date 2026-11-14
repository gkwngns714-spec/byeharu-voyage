# 2026-11-15: the map keeps its detail when zoomed out, and the names are bigger (owner row 339)

The owner: *"in map, when i zoom out, the details of the map disappears, make it so that it stays as long as possible. the
names of the cities as well as regions, countries, flags, should be bigger, city icon slightly bigger."*

Client only; no migration, no production access.

## What hid the detail, and what it is now

Every rule that thinned the map as the view widened, old -> new:

| rule | where | old | new |
|---|---|---|---|
| a city nothing of yours uses asks for its name only inside this span | `chartView.ts` `LABEL_SPAN_LIMIT` | 70° | no limit: every full mark asks; the planner hides by collision |
| a sea's name (not an ocean's) only inside this span | `chartView.ts` `SEA_NAME_SPAN_LIMIT` | 110° | no limit (lowest priority, so only on water no place wants) |
| every tier wears its full mark (and so asks for its name) | `chartView.ts` `PORT_TIER_BANDS` | to ~28° (`ALL_NAMES_SPAN`, the 47 % rung) | to 45° (`ALL_NAMES_FULL_SPAN`) |
| the middling tier 3 wears its full mark | same | to 45° (tier 5 alone beyond) | at every span |
| past this span every harbour is a dot and its light only | `chartView.ts` `DOT_SPAN_DEG` | 135° | 180° (the globe is still lights only, row 125) |
| the mid coast tiles are drawn | `fineCoast.generated.ts` / `scripts/build-fine-coast.mjs` mid `maxUnitsPerPx` | 0.03°/px | 0.045°/px (its 0.03° tolerance is 0.67 px there) |
| merchants: every one drawn up to | `shipMarks.ts` `THIN_DENSITY` | 40/390 °/px | 50/390 °/px |
| merchants: one in eight from | same | 0.33 °/px | 0.4 °/px |
| merchants: none from | same | 0.66 °/px | 0.8 °/px |
| a capital's name | `labels.ts` `LABEL_PRIORITY.capital` (new) | asked as any harbour of its size | asks at 16, above every other quiet harbour (15 at most), below regions and yours; a capital wears its full mark at every zoom (`MapPort.capital`) |
| a capital whose name will not fit | `labels.ts` `flagOnlyFallback` (new) | nothing | its flag alone, beside its mark, then on a further ring with a leader; it gives way only to its betters' marks |
| a capital with no recorded holder | `labels.ts`, `MapPort.capital` | no flag | its own nation's flag (Copenhagen, Hamburg, Gdansk, Genoa and Venice had none in the local world) |
| a fleet's name past a coast | `labels.ts` | blocked by every mark | gives way only to the marks of its equals and betters (it was boxed in at Lisbon by the middling marks that now stay) |

Unchanged on purpose: `quietHarbours` (an unnamed full mark past a coast is a quiet dot), `centredOnMark` (PR #666: past a
coast a name stands over or under its own mark and the lesser one gives way), `WIDE_SCALE` (the hulls, lights and shallows
still shrink with the density, the owner's 2026-11-14 look), the regions' tint (it has no zoom rule), the shallows and relief,
`LABEL_RINGS`, the priority table's order. The 110m world file stays the widest coast.

## The sizes

| what | old | new |
|---|---|---|
| a city's (and a fleet's) name `GLYPH.labelSize` | 10.5 px | 13 px (+24 %) |
| a great harbour's name `greatLabelSize` | 12 px | 15 px (+25 %) |
| a region's name `regionNameSize` | 13 px | 16 px (+23 %) |
| the flag beside a name | 1.25 em of the name: 13.1 / 15 px tall | the same em: 16.3 / 18.8 px tall (+24 %) |
| the halo `labelHaloWidth` | 3.5 px | 4 px |
| the city mark (triangle, lozenge) `GLYPH.markGrowth` | 1 | 1.12 (drawing only; the tap reach and the roads' floor keep their measured ramps) |
| the great harbour's ring | 9.5 px | 10.6 px |
| the city dot `portDotRadius` | 1.6 px | 1.8 px; the light's scales 9 -> 8 and 4 -> 3.55 so the light did not grow |

Sea names are unchanged (11.5 / 14 px). "Countries" is read as the region names: the map has no separate country names
(decided by default).

## Two defects found on the way

- **Two names with one key.** A harbour near the edge of a copy's window is planned on two copies of the sheet; `LabelsLayer` keyed
  names by id alone, and React left the loser's element on the glass, never updated: zoomed in from the whole world on the 1920
  desktop, Seville's flag planned at the globe's scale stood across the Mediterranean ten times its size (screenshot taken). Keys
  are now id plus copy.
- **Every name re-rendered on every pan frame.** The plan is made each frame and each label is a new object; a name is now
  memoised by value (its place is in chart units, which a pan does not change).

## Measured

Before = main 9c983967, after = this branch, both `vite build`, `vite preview` on localhost:4791, the merchants-on world
(`serveNpcOn`), headless Chromium, the same script (a 40 % drag over 60 moves, 16 ms apart, run twice; rAF intervals and
long tasks inside the page).

Pan at 1920x1000:

| view | before | after |
|---|---|---|
| widest (360°) | 57.2 / 55.2 fps; p95 32 / 33 ms; max 41 / 50; no long task | 53.6 / 51.7 fps; p95 32 / 36 ms; max 54 / 67; no long task |
| Europe (37.9°) | 59.9 / 60.4 fps; p95 21 / 20 ms; 3 / 4 long tasks (378 / 396 ms, the coast tiles) | 59.5 / 60.7 fps; p95 24 / 22 ms; 3 / 4 long tasks (492 / 448 ms) |

The single runs above move a few fps between runs on this machine, so the widest view was also measured INTERLEAVED, both
builds served at once (before on :4792, after on :4791), five pans each, in the order before, after, before, after, without
the Sun held: before 32.9 30.4 31.9 31.7 30.7 / 32.5 30.1 31.7 31.4 30.9 fps (mean 31.5), after 32.4 30.9 32.1 31.3 30.9 /
32.0 30.2 31.2 31.1 30.4 fps (mean 31.3); p95 40-46 ms both. No measurable difference. The plan itself costs 0.7 ms at the
whole world on a 1920 glass (214 harbours and 51 waters, measured in Node, 50 runs).

Names on the glass (harbour names / flags / sea names):

| glass, view | before | after |
|---|---|---|
| phone 390x844, widest (93°) | 4 / 4 / 2 | 9 / 12 / 2 |
| phone, two steps in (36°) | 2 / 2 / 1 | 8 / 4 / 1 |
| phone, Europe (26.6°) | 23 / 17 / 0 | 17 / 17 / 0 |
| 1920x1000, widest (360°) | 23 / 19 / 5 | 53 / 46 / 12 |
| 1920, two steps in (141°) | 5 / 5 / 2 | 15 / 14 / 3 |
| 1920, Europe (37.9°) | 31 / 25 / 3 | 52 / 42 / 2 |
| 1280x800, widest | 15 / 11 / 4 | 31 / 33 / 5 |
| 1280, two steps in | 7 / 6 / 2 | 28 / 27 / 5 |
| 1280, Europe | 36 / 26 / 4 | 58 / 46 / 1 |

The cost of bigger names, measured and accepted: on a phone at Europe's mid zoom fewer names fit (bigger names collide sooner;
the lesser one is hidden, never overprinted); row 193's 47 % frames name 3,033 of 3,052 marks (19 unnamed, was 3); the crowded
Mediterranean coast at a phone's 12° names 13 of 14 (Venice, was 14). Each keeps its mark and its tap, and one step in names it.

Pictures (day and night, phone 390x844 at 2x, 1920x1000, 1280x800; widest, two steps in, Europe): `C:\Users\gkwng\dev\map-detail-shots\before\` and `...\after\`.

## Laws

- New: `tests/map.detail.spec.ts`: no span limit on a name; the sizes; a capital asks above every quiet harbour and keeps at least
  its flag at the whole world on a desktop; and on the running game, furthest out on a phone and on a 1920 desktop, at least
  MIN_NAMES harbour names, every capital on the glass flagged, no two names overlapping.
- Moved deliberately (each with the owner's words at the pin): `map.labels` (tier bands, the globe's 114 marks, the wide frame
  asks for every full mark, the crowded coast 13 of 14, row 193's bound 3 -> 20), `map.marks` (114 full at the world view; the
  world's coast is no longer the opening frame's, which now draws the mid tiles), `map.look` (a name's reach from its mark 26 ->
  32 px, the type being 24 % bigger), `map.atmosphere` (every water asks at every zoom), `map.fineCoast` (1) (mid to 0.045).
- Run locally against the served build: `map.detail`, `map.look`, `map.marks`, `map.fineCoast`, `chart.ink`, `map.labels`: 82
  passed. `map.atmosphere`'s sea-name test reads English names and fails on this Korean-locale machine, and its "every chart
  token is drawn" test fails here on main too (`--color-chart-day-deep`); both untouched by this slice.
