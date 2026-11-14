# 2026-11-15: the map's filter, Off / Regions / Seas (branch `seas-filter`, client only)

The owner: *"also in map, make filter, like regions, no in regions, have option to see seas, showing waves, requirement to pass etc."*

## What changed

- The Regions button on the map's zoom column is now a filter: one press opens a short list, **Off / Regions / Seas**, one at a
  time. The button reads the layer that is on ("Regions", "Seas") or "Filter" when none is. The choice is kept per device
  (`src/chart/regionsFilter.ts`, key `byeharu-voyage.map.layer.v1`; the old Regions key is still read once, so a player who left
  Regions on finds it on). The Command tab's small chart offers Off and Regions only (it draws no seas).
- **Seas** draws, for every sea zone the server serves:
  - its border with each neighbouring zone, a dashed hairline on the water (never along a shore: that is the coast);
  - its name at its deepest water on the glass (the deepest cell of the zone in each 1.5° block, at least 1° from any other
    zone or shore, deepest first: the whole zone's deepest at the world view, the part on the glass close in), with what it
    asks on a smaller line under it ("Title 3 · Waves 6");
  - a zone CLOSED to the fleet in hand (the server's verdict, only while the sea conditions bite) says what it lacks
    ("Needs title 3") in the danger ink, and its name in the quiet ink.
  - The backdrop's water names give way while Seas is on (two sets of names for the same water only crowd each other).
- A press on the water while Seas is on opens that sea's tray: what it asks, the fleet in hand Open/Closed with the wall's
  own sentences, her title, the fleet's waves, its harbours, and **All seas**, which opens the Codex on its Seas face
  (`/compendium?face=seas`, a new deep link).

## How it stays smooth and light

- No fill: the 2026-11-14 "square, not in sync" (#668/#669/#672) was a fill of the zone raster. The borders are traced along the
  raster's cell edges, set through the edges' midpoints (a stair becomes its diagonal), thinned (Douglas-Peucker, 0.35 cell) and
  rounded twice (Chaikin). A cut on a parallel or meridian stays one straight line. One path for the world, built once per
  raster (`zoneShapes`, cached by the raster object), drawn on the night coast sheet that a pan only translates: no new
  per-frame work, the same line at every zoom and pan.
- The names go through the one label planner (a `note` line was added to a centred request; the planned box holds both lines).
- Reads: `world.sea_conditions` (already read by the map) and `world.sea_zone_map` (already read by the map once a session while
  the conditions bite; with Seas on it is read once a session also while they are dark). No polling, no new read, no migration.

## Decided by default (the owner may reverse)

- One layer at a time (Regions and Seas do not stack).
- Borders only, no tint per zone.
- A closed zone shows what it lacks instead of both asks; an open zone shows both asks.
- A single press on water opens the sea while Seas is on (a double press still pinpoints the water to sail to).

## Checked

`tsc`, `eslint`, `vite build`; `tests/map.seasFilter.spec.ts` (pure: the border, the anchor, the kept choice; browser on the
lit world at 390 EN, 320 KO, 320 EN, 1440 EN: three choices, zones named with their asks, closed marked, water names gone, the
tray opens on a press, the chrome column keeps one right edge, kept across a reload). Screenshots looked at by night (Atlantic,
phone) and by day (desktop world view, day-side Europe at 1440, open water at 320 KO), wide and close, plus the tray at 390 and
1440. The borders first vanished on the day sea (the night ink on pale blue): the day face now draws the same line in the day
coast's ink at 45 %. Close in on open water, names first went missing (one place per zone): hence the per-block places.
Measured: 390 EN 8 zones named (3 closed), 320 KO 10 (5), 320 EN 5 (2), 1440 EN 9 (2) at the 32 % view; the world view at 1440
names about 50 of the 64.

Local reds NOT from this branch (same on main's files): `map.atmosphere` "an ocean is named..." (the Korean machine locale, passes
on CI), `map.atmosphere` "--color-chart-day-deep is defined and never drawn", `map.regions` "region-tint.json is byte-identical".
