# NAVIGATION — the plan, and what is measured

Written 2026-08-24 for the owner, who asked to see the plan before anything is built.

> *"do all the work in appropriate order, after research, build what you think it is best without
> ruining this game"*

**Status of this document:** BUILT, 2026-08-24 — landed as migrations **0046**
(`the_water_knows_the_way`) and **0047** (`the_sea_is_a_free_plane`) — corrected 2026-08-25: this
was originally cut in the `bv-mover` worktree as 0038/0039 against a 37-migration base, but generated migrations are
regenerated against the current chain rather than textually merged, so the files that actually
shipped on `main` are 0046 and 0047 (see `supabase/migrations/`; `docs/RESUME.md`'s "LANDED
2026-08-24" section spells this out). Other 0038/0039 references below name the slice as it was
planned, not the file that landed. With the client in `src/lib/sea` + `src/domain/passage` and the
chart drawing the served course whole. `docs/DEV_LOG.md` D22 records what landed and what it
measured; proof 09 (renumbered here: 08 is the sea-membership proof) holds the never-touch-land law and the Arctic door shut on every run. The
prototype in `scripts/proto/` was CONSUMED by the build (the pathfinder moved into
`src/lib/sea/pathfind.ts`, the plpgsql A* was rejected by its own measurements) and is deleted;
the measurements below are its record. The reference-game research
(`DESIGN_RESEARCH_NAVIGATION.md`) was **not finished** — the agent writing it hit the session
limit. That gap is stated rather than papered over; the owner supplied the design directly, which
is what the built system rests on. Wind (§6 step 5) and encounters (§6 step 6) are deliberately
NOT in the built slice; the wind seam (per-segment frozen speeds) is.

---

## 1. WHAT IS WRONG TODAY, measured

byeharu-voyage sails a **fixed graph of 782 precomputed legs** between ports. The owner's verdict:

> *"it should go by sea without the fixed route — but fastest way possible. Also, in map, i should be
> able to pinpoint anywhere in the ocean to make a fleet move."*

The prototype pathfinder was run against the shipping leg graph. It is worse than previously
diagnosed:

```
sea-grid.mjs's Lisboa→Nagasaki reaches 88.6°N
proto's        Lisboa→Nagasaki reaches 38.7°N
```

**The game currently routes Europe to Japan over the North Pole.** Its distances look *shorter*
because of it:

| route | shipping graph | honest path | ratio |
|---|---|---|---|
| Lisboa → Nagasaki | 7,565 nm | **12,989 nm** | ×1.72 |
| Antwerp → Honolulu | 6,501 nm | **14,040 nm** | ×2.16 |
| Nagasaki → Lisboa | 7,570 nm | **13,131 nm** | ×1.73 |
| Lisboa → Manila | 8,779 nm | **11,858 nm** | ×1.35 |

Every one of these numbers is served to a player, gates the endurance check, and prices
`world.trade_routes`. **The Asian trade is being quoted at roughly half its true distance.**

This is the same single cause as the four defects already logged: Brazil via Iceland, ships drawn
over land, 41 ports teleporting 20–72 nm, lanes across continents. One wrong model, five symptoms.

---

## 2. THE MODEL, as the owner specified it

- **The sea is a free plane.** Any water point is a destination.
- **Auto-sail pathfinds** the fastest way through the 0.25° water raster, computed at departure.
- **Wind and current change speed** — and the point is **provision risk**: a slow passage burns more
  stores.
- **NPCs distributed by area, with levels.** A panel on the map lists nearby contacts and their
  **distance**; the player clicks one to engage.
- **The empty ocean is filled by consequence:** attacks, and disasters that take crew, stores, cargo.

**A path found through water cells cannot cross land by construction.** The owner's law — *"i don't
want the fleet to ever touch land"* — stops needing a guard bolted on afterwards and becomes a
property of how a route is made.

---

## 3. IS IT FAST ENOUGH? — measured in Node

```
worst single search                    166 ms   (Nagasaki → Lisboa)
Lisboa → Nagasaki, 5 consecutive        75 ms each
40 random port pairs                    47 ms each   (38/40 routable)
verifying an 11-point path is all water  0.02 ms
```

**Yes, in Node.** A search is tens of milliseconds, and *verifying* a path is water costs
essentially nothing — which matters, because that verification is how the never-touch-land law is
enforced rather than hoped for.

### And in PGlite — measured 2026-08-24, and it settles the design

```
route                  |      ms |  expanded |   nm
-----------------------+---------+-----------+------
Lisboa -> Cadiz        |     330 |        74 |  286
Lisboa -> Amsterdam    |   3 549 |       957 | 1122
Lisboa -> Salvador     |  42 619 |     11150 | 3731
Amsterdam -> Venice    |  67 729 |     17775 | 3246
Lisboa -> Calicut      | 302 438 |     85268 | 9802
```

**A\* written in plpgsql is about 1,800x slower than the same algorithm in JavaScript.** Five
minutes to issue one order is not a tuning problem, and no constant factor rescues it: the search
expands 85,000 cells and plpgsql pays interpreter cost on every one. Raster load and storage are
fine (163 ms, and 1 MiB of raster TOASTs to 27 KiB) — **the loop is the problem, not the data.**

**So the pathfinding does not run in SQL.**

### THE ANSWER: the client proposes, the server verifies

The asymmetry the prototype measured is the whole design:

| | cost |
|---|---|
| FINDING a path (JS) | 47-166 ms |
| VERIFYING a path is all water | **0.02 ms** |

Finding is expensive; checking is free. So the client — which is JavaScript, and fast — proposes a
water path, and the **server verifies it and measures it**. Verification is the authoritative act.

**This does not weaken server authority, and it is worth being precise about why.** The server
independently (a) samples every segment against its own raster and refuses anything touching land,
and (b) computes the distance itself from the polyline. A client cannot gain by lying:
- a path crossing land is **refused**;
- a longer path only **costs the player** more days and more stores;
- a *shorter* water-valid path is not a cheat — it is a better route, and legal water is legal water.

The one thing the server must never do is take the client's word for the DISTANCE. It measures.

**Rejected, and why:** a precomputed waypoint mesh is a fixed graph wearing a new name and the owner
has refused that three times. Edge Functions would put the search on a server but add a service and a
second runtime for one function. A coarse-then-refine pass in plpgsql still pays interpreter cost on
the refinement, and 330 ms for Lisboa-Cadiz — the SHORTEST case measured — is already too slow to
build on.

---

## 4. WHAT IT REPLACES — and this is the constraint that matters most

It **REPLACES** `voyage.reach_from`, `voyage.sail_refusal`, `voyage.route_direct` and `voyage.route`.
It does **not** join them.

The predecessor's recorded catastrophe was **four overlapping movement paths**: four ships stuck at
`traveling` with nothing behind them, five teleported to the wrong ports, a global cron wedge, a
player's fleet destroyed because the brake refused, and *"is this fleet docked?"* reaching **eleven**
hand-copied definitions. Adding free movement beside the leg graph would recreate that exactly.

**One mover.** `data/sea-routes.json` and `scripts/build-sea-routes.mjs` are deleted; the raster
becomes the one source of what water connects to what.

---

## 5. WHAT MUST SURVIVE

**Offline settlement stays byte-identical.** `voyages.speed_profile` is frozen at departure and
proof 01 rests on it — it is why a voyage settles while the player is asleep. Wind that varies along
a passage *appears* to break this and must not: **wind must be a pure function of (position, time,
world secret)** — the shape `voyage.rng` already has, `immutable`, so Postgres itself forbids it
reading the clock. Integrate a known field over a known path and any two evaluations agree to the
digit. Losing this means the game only advances while someone is watching.

**Consequence:** if wind moves speed, the ETA quoted at departure is a **forecast, not a promise**.
`docs/UI_DIRECTION.md` forbids printing a number the game will not honour, so the player must be told
which it is.

---

## 6. ORDER OF WORK

1. **Finish the PGlite measurement.** Everything below depends on it.
2. **The pathfinder as the one mover** — replacing the four route authorities, with the water-path
   guard as its acceptance test (walk every path at sub-cell intervals, assert every sample is water,
   proven able to catch a straight line across Iberia).
3. **The chart follows the served path** — `src/chart/route.ts` draws straight lines *deliberately*,
   to agree with the server's straight-line interpolation. Both change together or the ship is drawn
   off its own track.
4. **Pinpoint anywhere** — the map's tap becomes a destination.
5. **Wind and current**, pure, with the ETA honestly labelled.
6. **Encounters** — the contacts panel with distances. `0035` already made *what befalls a fleet at
   sea* a table with a foreign key, so the disasters are largely authoring, not machinery.

**Sea places and diverting (0036, 0037) already landed** and compose the current model. `cmd.divert`
turns at the far node of the leg she is on; under free movement it becomes a supersede that turns
where she stands. That is a normal supersede, not rework.

---

## 7. THE SEA IS ROUND — the course convention at the antimeridian (0088, 2026-09-14)

The owner, row 98: *"the map should be continuous on left to right, and the ship going from tokyo
to callao should cross south pacific ocean."*

**What was measured first.** The grid was always round — `colOf`/`isWater` wrap the column
(`src/lib/sea/grid.ts:66`), the A* neighbour expansion wraps, every server cell lookup wraps — and
the search FOUND the Pacific: Tokyo → Acapulco came back `[[35.13,140.38],[39.13,179.88],
[39.13,-179.88],[16.63,-99.88]]`, 6,223.5 nm. Two readers then refused to believe it:
`segmentIsWater` returned false for any |Δlon| > 180 (so the straightener left that kink at the
seam), and `voyage.path_refusal` (0046:443) answered the 0.25° hop with *"segment 1 jumps the
antimeridian the long way round"* — a Pacific crossing could be found and drawn and never sailed.
Two more readers would have swept the world had that refusal not stood in front of them:
`segments_from_course` (500-nm pieces by `lon1 + (lon2 − lon1)·k/n`) and `position`
(`a + (b − a)·frac`) both walk 359.75° westward on such a segment.

**THE CONVENTION — one rule, written on both sides of the wire:**

1. Every vertex of a course lies in **[−180, 180]**.
2. A segment **MAY straddle the antimeridian** — its two vertices on opposite sides of ±180 — and
   it is **ALWAYS read the short way round**, the way whose |Δlon| ≤ 180. There is no long way;
   nothing can express one.
3. Every reader steps longitude through **ONE rule**: `voyage.lon_lerp(lon1, lon2, f)` on the
   server, `lonLerp` in `src/lib/geo` on the client (`shortLonDelta` is the step;
   `unwrapLongitudes` is that step accumulated). Never `a + (b − a)·f` on raw degrees again.

Rejected: forbidding straddles and having the pathfinder split a crossing into `[lat, 180]`,
`[lat, −180]`. That makes a zero-length segment which `segments_from_course` drops, after which
`course_of` re-joins the two sides into exactly the straddling segment it meant to avoid, and
`position`/drift would divide by that zero length. A rule every reader must special-case is not one
rule.

**Who composes it today:** `path_refusal`, `segments_from_course`, `position` (server, 0088);
`segmentIsWater` (client); `src/chart/route.ts` — `sheetPieces` cuts a straddling segment at ±180
into two pieces on the one unrolled sheet, off the right edge at (180, lat*) and back in at
(−180, lat*), lat* being the lat/lon-linear crossing latitude, and the arrowhead's heading is read
over `unwrapLongitudes` so a last segment that straddles points across the seam; `src/chart/drift.ts`
steps her through `lonLerp`. The served `position.lon` is always in range; `seg_index` still names
the straddling segment she is on.

**The continuous left-to-right sheet — measured 2026-09-14, and it is the NEXT slice, not this
one.** What `chartView.ts` does at the seam today: `clampView` keeps the visible box INSIDE the
world (`cx` clamped to ±(180 − span/2); at the world span the centre is pinned to 0), so the view
cannot pan past ±180 and the seam always sits at the sheet's two edges; the coastline, tints,
islets, ports, roads, fleets and names are each drawn ONCE at x = lon. A wrapped view means: the
view's x becomes periodic (`clampView` wraps `cx` instead of clamping it); every layer draws a
±360°-shifted copy of the same paths when the box touches the seam; and every "is this point on
the glass" question answers for the copy too. That question is written **four times today** —
`chartModel.ts:295` (`portMarks`), `seaNames.ts:77`, `regions.ts:169`, `SmallChart.tsx:161` — plus
`labels.ts`'s viewBox clipping, `hitTest.ts`'s distance, the minimap's viewport rectangle
(`Minimap.tsx`), and `openingBounds`/`withCoastInView`, which frame Tokyo + Callao the long way
round (`boundsOf` spans 140 → −77 as 217°, and the clamp turns it into the globe). Twelve files,
and the four copies are a `docs/NO_SPAGHETTI.md` §1 finding in their own right: the slice folds
them into ONE `onGlass(point, box)` first, then makes that one periodic. Half of that in this PR
would have been a second lon rule in the chart; none of it is.

**Measured on the applied chain, 2026-09-14** (`tests/sea.dateline.spec.ts` re-measures live):
Tokyo's roads → Callao's roads is ONE straight segment: chord 8,337.3 nm on an 8,337.3 nm great
circle (×1.000); the 17 pieces she sails sum to 8,615.2 nm (×1.033 — 0047 measures the lat/lon-
straight line, not the arc; on the short segments of every earlier course the two agree within
0.1 %); one straddle, no vertex left on the seam; Lisbon → Amsterdam byte-identical. Before: the
same search proposed 8,358.4 nm with a kink on the seam and the server refused it.

---

## 8. NO COURSE CROSSES THE DRAWN LAND — the rule, and the procedure (0440, owner row 352, 2026-11-15)

The owner: *"some ships go pass through land - such as hadibu ... fix this properly, and make
procedures that this won't happen again"*.

**The cause.** The raster above is Natural Earth 1:110m at 0.25°: it has no Socotra at all, no
Bangka, and coasts straight for 60 nm. The search straightens its course against that raster
alone, and the server judges the same line the same way, so every course was legal water and was
then drawn on the chart's 1:10m coast (`public/coast`) straight over islands, capes and peninsulas.
On the main world: 774 of 1,141 stored lanes, 2,422 of 3,350 route legs and 62,024 of 71,556
harbour-to-harbour courses ran over more than 2 nm of drawn land.

**The rule now.** Every course is re-sailed off the land the chart draws before it is offered:
`src/lib/sea/refine.ts` searches the stretch round the land again on a 1.5 nm grid whose cells are
water by BOTH the raster and the coast mask (`public/coast/mask.json`, `src/lib/sea/coastMask.ts`:
the chart's 1:10m land inside every raster water cell, at 0.75 nm). The result is still raster
water by `voyage.path_refusal`'s own rule, or the search's course is kept. One function, used by
the browser's course author (`src/domain/passage` `proposeCourse`) and by the generator of the
stored lanes (`scripts/build-land-channels.mjs`). The server's law is unchanged: the raster.

**The guard.** `tests/sea.noLandCrossing.spec.ts` runs on every PR that touches the pathfinder,
the coast, the sea grid, the ports, or a migration that writes `npc_courses`,
`standing_route_stops`, `sea_reaches`, `sea_raster` or `cargo_circuit_legs`. It fails on any course
over more than 2 nm of drawn land that is not on `scripts/db/land-crossings.known.json` (the
courses whose water the raster closes, for a later raster slice), on a known one that no longer
crosses (the list only shrinks), on a stale mask, and on the owner's own example (Hadibu to Kilwa).

### Adding a harbour, a lane, a channel, or changing the coast

1. Make the change, then `npm run build` (it writes the world image the tools read; no prod load).
2. If the raster or the coast tiles changed: `node scripts/build-coast-mask.mjs`.
3. If lanes or routes were seeded, a channel was charted, a harbour was added, or the raster changed:
   export prod's courses (read only: `scripts/ops/harness/no-land/prod-courses.sql`, gate green first),
   then `node scripts/build-land-channels.mjs <image of the chain before your migration> --prod courses.json`
   writes the re-sailing migration (set MIGRATION_NAME to prod head + 1). It re-sails prod's own rows too:
   prod holds courses no image has.
4. `node scripts/db/audit-land-crossings.mjs [image] [--apply <your migration>]` lists every
   crossing with its lane, its ports and where the land is. Zero new ones, or fix them.
   `--pairs` adds every harbour-to-harbour course the browser would propose (about 30 minutes).
5. Only when a crossing is FIXED: `--write-known` rewrites the known list (it may only shrink).
6. Every day (the lead), and after any deploy that writes courses: export prod's courses and legs
   (`prod-courses.sql`, `prod-legs.sql`, read only) and run the audit with `--prod courses.json --legs legs.json`
   on an image of prod's chain. It fails on anything not on `scripts/db/land-crossings.prod-known.json` (empty).

### 0440, second half: the straits opened, the roads put on the water, production re-sailed (owner row 352)

The first draft left 52 lanes and 50 route legs over land, and 57 roadsteads on it, and it was cut from the
world image alone: production held 937 crossing lanes, 682 route-stop courses and 732 frozen legs of its own
(`docs/dev-log/2026-11-15-land-channels.md`). One migration, 0440, now takes all of it. Three causes, three fixes:

- **A turn on an island.** A course's turning points are raster cell centres, and the raster cannot see
  an island, so a turn could sit on drawn land (Strangford Lough, Oland, Saaremaa). The refiner searched
  segment by segment, so each half began or ended in a pocket of the coast the 1.5 nm grid cannot leave,
  and the course was kept as it was. `src/lib/sea/refine.ts` now measures the land runs along the whole
  course, so one search window spans the turn; a stretch kept from the old course whose samples touch a
  raster land cell is searched again (`mend`); a course that runs exactly along an edge of the land
  bitmap's pixels is read on both sides of it. This alone cleared the Hebrides, the North Channel,
  Moon Sound, Oland and Chios.
- **Water the raster closes and the chart draws.** `scripts/sea-grid.mjs` CHANNELS entries with
  `charted: true`: `corfu` (both Corfu channels), `tsugaru` (the strait's northern half, which
  1:110m draws as Hokkaido) and `western-scheldt` (the Wielingen). Unlike a river carve, a charted
  channel's drawn land stays land in the coast mask and in the audit
  (`riverCarvedCells()` is the cells the mask and the audit leave alone). Each new polyline runs down
  the drawn water; the generator refuses one that touches drawn land. Eight straits carved long before
  are charted too (Kerch, Bab-el-Mandeb, Hormuz, Malacca, Sunda, Seto, the White Sea's Gorlo, the Baltic
  gulfs): their raster is unchanged, but the land the chart draws in their cells now counts, and 98
  more stored courses that ran over it there are re-sailed. Measured and NOT charted: the Danish straits and
  the Gulf of Suez (their drawn water is not continuous on the 1.5 nm grid inside a one-cell carve: 65
  courses could not be re-sailed), the Dardanelles and the Bosphorus (narrower than the chart's pixel).
- **A roadstead on the land, or in a pocket.** A harbour whose raster roadstead lies on drawn land, or in
  drawn water the open sea cannot reach on the 1.5 nm grid (Toulon's inner harbour, New York's upper
  bay), is reached from the nearest point to its quay that is drawn water with 1.5 nm of drawn water
  round it and joined to the open sea. `voyage.drawn_roadsteads` holds the point; `voyage.water_roadstead`
  answers it for that quay, and `scripts/build-sea-migration.mjs`'s `roadsteadOf` reads the same table,
  so the rule stays one answer. Harbours that shared one raster roadstead (Hormuz, Bandar Abbas) share
  one drawn point. No move is over 12 nm, so a stored route's first point stays inside course_join_nm.
  Stockholm's own water (Saltsjon) is not joined to the sea even in the 1:10m drawing, so its roads are
  in the archipelago, 15 nm off the quay.

`node scripts/build-land-channels.mjs` does all three for the stored courses (lanes, route legs, coast
courses, and the cargo circuits' and navy patrols' frozen pieces) and writes the migration, the mask, the
prod checks and the forward rollback. Run it again, as the next migration, whenever a channel is charted
or a harbour is added: it moves only what is on land or in a pocket.

Not covered by the audit, by design: a RIVER carve's cells (the Thames, the Scheldt above Flushing, the
Gironde), where the chart draws land over the water the game sails on purpose, and the three straits
named above that the fine grid cannot pass.

### 0441: an approach is not a canal (owner row 352)

0440 left one case: Panama City to Portobelo. Their roadsteads lie 45.9 nm apart across the isthmus, and
`voyage.path_refusal` skipped every sample within 25 nm of each end of a course unread, so the straight line
had no sample left. **The rule now: an approach is the land an end stands in, and nothing else.** A land sample
is passed only when the stated end is itself in a land cell and the sample is in the unbroken run of land from
that end, inside its allowance. A roadstead is raster water (all 268; proof 143), so a course between two
harbours has every sample read. A course with no water between two land ends is refused. The browser's
`segmentIsWater` and `courseRefusedAt` (src/lib/sea) read the same rule, sample for sample.

What this adds to the procedure above:

- The audit lists a stored lane, route leg or coast course that the SERVER'S LAW refuses beside the crossings
  (image, `--prod`, and the guard spec). A merchant sent down such a lane is refused E_LAND.
- `node scripts/db/audit-land-crossings.mjs --allowance`: the straight line between every two roadsteads, by
  the rule as it stood and as it stands. It exits 1 if the rule accepts a line with raster land under it. Run
  it after a harbour is added or a roadstead moves.
- A new roadstead must lie in a raster water cell: a roadstead in a land cell would have an approach again.
- When the approach rule, the raster or the roadsteads change: `node scripts/build-isthmus.mjs <image> --prod
  courses.json` re-sails every stored course the rule refuses or that is over drawn land (set MIGRATION_NAME),
  and `node scripts/ops/harness/isthmus/prod-shaped.mjs <image> courses.json legs.json --rollback` applies it
  to prod's own lanes, stops and frozen legs in an image and audits the result.
- Still open: the server holds no coast mask (a hand-made straight course over an island the raster cannot
  see is accepted: 593 harbour pairs), and `course_join_nm` lets a course begin 15 nm from where she lies.

### 0442: the pair table keeps step with the courses (owner row 352)

`public.sea_leg_asks` names the seas between every two harbours (what title and wave a leg asks). Trade's board and the server's
pathfinder read it. Its author is a build (`scripts/build-sea-legs.mjs`, `data/sea-legs.json`, 0403): the seas of the course the
browser plots, and of any course the world remembers on the pair. 0440 moved 69 roadsteads and re-sailed the lanes and did not
re-run it: 18 lanes (24 on prod) crossed a sea their row did not hold, and Galle's own row named the sea its roadstead had left.
Proofs 97 and 98 went red on main. 0442 is the repair. What this adds to the procedure above:

- A migration that re-sails a stored course or moves a roadstead calls `public.sea_leg_asks_keep()` (the templates of
  `build-land-channels.mjs` and `build-isthmus.mjs` now do): own rows name their roadstead's sea, a row holds every sea of its
  remembered course, and wave and title are the most those seas ask. It adds seas and never removes one.
- Then re-run the build, in this order (about 40 minutes; local only):
  1. `BYEHARU_PREFIX_CACHE=required node scripts/build-sea-legs.mjs --before=<next> --courses=<file.json>` writes `data/sea-legs.json`.
     It plots as the browser's course author does (the search, then the re-sailing off the coast mask) and adds the chain's lanes' seas.
  2. `BYEHARU_PREFIX_CACHE=required node scripts/build-sea-legs-migration.mjs --before=<next> --name=<file> --courses=<file.json> --proof98`
     writes the migration, the prod check, the forward rollback, and proof 98's courses.
- The quoted distances (`public.sea_reaches.reaches`) are the length of the course a fleet really sails. When roadsteads or the course
  author change, measure them again with `node scripts/ops/harness/seas-memo/measure-reaches.mjs <image> <out.json>` (it prints what the
  new figures do to prices through `world.haul_rows()`; read that before shipping) and pass `--reaches=<out.json>` to step 2.
- The guards: the world guard (the table equals the file), proofs 97, 98 and 144, and `tests/sea.noLandCrossing.spec.ts` (the three
  laws, `scripts/sea-legs.sql.mjs` `LAWS_SQL`). The prod read is `scripts/ops/harness/seas-memo/before.sql`.
