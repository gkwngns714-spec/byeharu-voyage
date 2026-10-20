# 2026-10-20 — the map's names, and a merchant's name taking you to her (`osn-map-labels`, client only)

Two owner requests, both client only, no migration, nothing on the wire changed.

- **185** *"The map, some city is shown by its name and flag, whereas some cities aren't shown their names in certain
  zoom points. What is the reason? Any way to see the cities all? Without overlapping?"*
- **184** *"I want to be able to click on npc name like location, and then point me to that location like for cities."*

## 1. Why some cities have no name — the rule as it already was

Two separate rules decide it, and the owner was seeing both at once.

**First, is the mark drawn at all?** `PORT_TIER_BANDS` (src/chart/chartView.ts) keys the sheet on how many degrees of
longitude are on the glass: over 45° only the 35 great harbours wear their full mark; 12–45° adds the 79 middling ones;
under 12° every harbour there is. Everything below the band is drawn as a **dot**, and a dot has no name and no flag —
only the FULL half of the sheet (`visiblePorts`) asks to be named. A harbour one of your fleets uses is full at every
zoom, whatever size it is.

**Second, is there room for the name?** `planLabels` (src/chart/labels.ts) places names best-first by
`LABEL_PRIORITY` — the selected thing, then a fleet at sea, a destination, an anchorage, a docked fleet's name, a port
on a route, and last every other harbour at `quiet + size_tier`. Each name tried the eight sides of its mark (right,
left, above, below, then the four diagonals) and took the first box that was inside the glass, clear of every mark,
clear of every name already placed, and out of the screen's own opaque chrome. If none of the eight fitted, **the name
was dropped** — never drawn badly. The flag rides inside that same box (it widens it by `FLAG_ADVANCE_EM`), which is
why a city with no name shows no flag either: they are one unit.

So "some cities aren't shown their names in certain zoom points" is the second rule in a crowd, and `LABEL_SPAN_LIMIT`
is not what the owner was seeing — at any span wide enough for it to bite, the only full marks are great harbours,
which ask for their names at every zoom anyway.

## 2. What changed: a name with nowhere snug steps out, on a leader

`LABEL_RINGS = [1, 2.3, 3.8]`. The eight sides are now tried on three rings instead of one, and a name set on a
further ring carries a hairline from the edge of its mark to its box — the chart-maker's leader line (LabelsLayer, in
the roads' own faint ink, non-scaling, under the letters, light and dark both through `bv-sun-road`).

Three things keep the promise the owner actually asked for:

1. **Two passes, so the rings may only ADD.** Every name is offered the snug ring before any name is allowed to step
   out. Measured as one pass over all three rings, the globe named **29** of its 37 marks where the old snug-only rule
   named 30 — a high-priority name stepping out took the water two lower ones needed. Two passes: whatever fitted
   beside its own mark is placed exactly where it was, same side, same box.
2. **A leader is held to the same promise as a name.** A stepped placement is rejected if its hairline crosses another
   name's box or another harbour's mark — a line through a name is the same overlap, one line thinner. (A mark standing
   on top of this one cannot be avoided and is not counted: that is the case the rings exist for.)
3. **A name never steps further than the mark's own touch reach** (`GLYPH.hitRadius`, 38 px; the furthest ring is
   3.8 × 9 = 34 px), so the name you can read is still a name you can put your thumb on — and a tap on a name's box
   already opens that city (`placedNames` → `hitTest`).

### Measured, on the real 214-harbour table (tests/mapWorld.fixture.ts), named / marks on the glass

| frame | before | after |
|---|---|---|
| Mediterranean coast, 12° across, phone scale | 11 / 14 | **14 / 14** |
| Iberia, 12° across, 1280 px | 6 / 7 | **7 / 7** |
| the opening frame, 1280×800 | 19 / 23 | **20 / 23** |
| a sea, 40° across, 1280 px | 36 / 39 | 36 / 39 |
| the whole world, 1280 px | 30 / 37 | 30 / 37 |

**The honest part.** Pulled back to the whole world nothing is gained, and nothing can be: of the 24 placements each
unnamed great harbour has, **22 to 24 are already filled by another harbour's name** (Antwerp 23, Barcelona 24,
Bordeaux 24, Lisbon 22, Lübeck 23, Marseille 24, Seville 23). Europe's corner of the globe holds ten great harbours
whose names are each wider than the gaps between their marks; no placement rule can name them all at that zoom. One
step in and they appear. "See them all" is therefore: zoom to a coast, where it is now literally every one of them —
or tap the mark, which names it in the city panel as it always did.

**Decided by default:** three rings and no more, with the cap set by the mark's own touch reach. Further rings were
measured — `[1, 2.3, 3.8, 5.5, 7.5]` names the opening phone frame 10/10, the opening desktop 22/23 and the 40° sea
38/39 — but the furthest hairline is then 67 px long, a sixth of a phone's width, and a name that far from its mark
reads as belonging to nothing. The sandbox cannot build the PGlite world, so no screenshot was taken; the geometry is
proved in pure specs instead and CI's acceptance suite drives the real chart.

## 3. A merchant's name takes you to her, wherever she is (184)

Her name was already a `GoToLink` on a city's list (`src/live/MerchantRow`) and on her sheet, and the city rows'
"point me there" is the same mechanism — `goTo` (src/chart/goTo.ts) names a target, MapScreen resolves it and glides
there with a marker. Nothing needed a second copy of that.

**The defect:** the resolution lived inline in MapScreen and had an answer for a merchant `docked` and one `anchored`,
and fell through to `null` for one `sailing` unless the chart happened to be drawing her. The sea read is capped
(`sea_traffic_max`) and a resting merchant is not drawn at all, so the merchants in a city's "Incoming" list — the ones
whose names the owner was pressing — mostly are not on the paper, and pressing them did nothing at all.

**The fix, in one place:**

- `whereabouts` (src/domain/fleet/where.ts) — the one classification — now carries `at` on a sailing row: the SERVED
  position on her leg (`voyage.position`, which `world.voyage_view` serves to the harbour read and the sea read alike),
  the same point the chart draws her at.
- `goToPoint` (src/chart/goTo.ts) is the one resolution, pure and exported: a point is itself, a harbour is its place,
  a fleet or a merchant is the mark the chart drew — failing that her own row, and failing a served position, where she
  is bound (the only other place she is). MapScreen hands it the model and the served rows and holds no copy of the rule.

Proved in tests/map.goto.spec.ts without a browser, one test per state of `where.ts`.

## 4. Specs

- `tests/map.labels.spec.ts`: the crowded-coast test was renamed and **tightened** — it used to say "every name clean,
  and the rest dropped", and now also asserts that every mark on that frame IS named, which is the owner-visible
  promise. A new describe block proves the ring rule: the further rings only add (planned against `rings: [1]`, the old
  rule, pinned for exactly this), a stepped name's leader starts on its mark and ends on its box and crosses no other
  name or mark, a sea's name never steps out, and the furthest ring stays inside `GLYPH.hitRadius`.
- `tests/map.goto.spec.ts`: a pure describe for `goToPoint`, four states, no server needed.
- Ran here: `npx tsc -b`, `npx eslint .`, `npm run build`, and the pure specs (map.labels 37, map.goto's pure 5,
  map.atmosphere, map.coastline, sections, i18n.keys, servedMemo — 77 + 5 green). The world-backed specs are CI's.
