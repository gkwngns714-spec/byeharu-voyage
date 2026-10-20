# 2026-10-20 — she glides: smooth ship movement — `osn-smooth-sailing` (client only, no migration)

Owner, OWNER_REQUESTS row 169 (2026-10-20): *"I want the ship speed to be faster for all ships
including npcs. About 3 times faster. And I want the ship movement to be smooth, not by ticks."*

This slice is **169b only** — the smooth movement. **169a (speed ×3) is not touched here**: it is one
knob at the speed authority and an economy change, and it is being costed in Lane A. No migration, no
RPC, no knob.

## What was actually ticking

Not the read, and this is the part worth writing down, because the obvious diagnosis is wrong.

The server settles a voyage on a read and the shell re-reads every `86400 / time_compression / 12`
seconds — 7.5 s at the live compression of 960 (`AppShell.readIntervalMs`). But the chart has not
stepped at the read's pace since 0075: `src/chart/drift.ts` draws her along the served leg at the
shell's clock, so between reads she already moved. **That clock ticks once a second**
(`AppShell`: *"one second is the coarsest tick that still lets a 12s readout look alive"*), and once a
second IS a tick: she stood still for a second and jumped. At the live clock a hull makes about 1.3 nm
a real second, which is a pixel at the globe and five or six on a harbour approach — a visible step,
and the whole of what the owner is describing.

So the fix is not a faster read and not a faster model. Re-running `buildChartModel` at 60 fps is the
thing 2026-10-12 measured and removed (*"the game looks stuck"*): every memo in `ChartCanvas` keyed on
the model would miss every frame, 252 harbours would re-render and the labels would be re-planned, so
that a few hundred hulls could move a pixel.

## What was built

`src/chart/underway.ts` — one animation frame for the whole sheet, outside React.

- **The point is `driftedPoint`'s**, the same interpolation of the same served leg, asked for at the
  frame's instant instead of the second's, off `lib/serverClock`'s `serverNow()` — the one clock. No
  second mover; every property 0075 pinned still holds.
- **What it writes, per frame:** one `transform` per hull group (`FleetsLayer`), the two `d` strings of
  a course split at her and the arrowhead's transform (`TracksLayer`'s new `Course`), and one
  `translate` on a fleet name's group (`LabelsLayer`'s new `FleetName`). The strings are composed in
  the layers that draw them (`hullFrame`, `arrowFrame`, `buildTrack`) — nothing is spelt twice.
- **One berth per fleet**, shared by her hull, her course and her name, so the three cannot be at
  three different points on one frame. Merchants come through the same door: the owner asked for
  *"all ships including npcs"*, and they are hulls like any other.
- **She converges, she never snaps.** The drawn point CHASES the served one, closing `glideShare` of
  the gap each frame at `UNDERWAY_GLIDE_MS` = 200 ms (the zoom glide's own arithmetic, moved into
  `chartView.ts` and now shared by three readings of it). So she trails her served place by a fifth of
  a second of her own passage — about a pixel at the tightest zoom this chart allows — and a read that
  disagrees is absorbed over roughly half a second, in either direction. A frame's point is always a
  blend of two points the server would own, so the convergence cannot carry her anywhere the server
  would not.
- **A gap too big to be a correction is taken at once** (`UNDERWAY_SNAP_DEG` = 1°, 60 nm). A real
  correction after one beat is a few nautical miles; a whole degree is a different passage — she
  arrived and was sent on, she was re-ordered, or she has just come back onto the glass — and easing
  across that would be a hull swimming over water with no passage under it.
- **She stops when she arrives.** `drift.ts` now cuts its elapsed time off at `etaMs`. The 0075 clamp
  already stopped her at the leg's far vertex, but on a course with a corner still ahead those are two
  different instants, and this is the one that is about arriving. A hull sliding past her quay is
  worse than a hull that steps.
- **Reduced motion gets none of it.** With `prefers-reduced-motion: reduce` no frame is asked for at
  all and the chart is exactly the chart before this slice: the served point, once a second. The
  preference is watched, so changing it needs no reload.
- **The twitch at the beat.** React commits the model's own place — up to a second behind the glass —
  and a frame would correct it ~16 ms later, which is a visible jerk backwards once a second. So the
  element is repainted in the same commit, in a layout effect, before the browser paints.

## What it costs

Per frame, per hull on the glass: one `driftedPoint`, one blend, one `setAttribute`. The courses are
re-cut per frame, which sounds expensive and is not: only your own fleets and the one merchant whose
card is open are served a course at all (hundreds of merchant hulls draw no line). Nothing about the
model, the port marks, the label plan or the coast sheets is re-run — the sheet's React work is still
once a second.

## Decided by default

- **200 ms** for the chase, **1°** for the snap. Both are named constants with the reasoning beside
  them; the owner may reverse either.
- **The hit test keeps the model's position.** A tap resolves against the model (`shipMarks`,
  `hitTest`), a fifth of a second behind the glass, which is about a pixel against a 38-pixel reach.
  Making the tap read the frame would put a second position into the surface for no gain anyone can
  feel.
- **Her `--night` is not rewritten on the frame.** The Sun moves a quarter of a degree a minute; the
  group's night value stays the model's.
- **The minimap keeps the model's beat.** It is a 100 px locator showing the whole world, where a
  second of sailing is a fraction of a pixel.
- **The label is MOVED, not re-planned.** Which names fit, and on which side, stays the planner's
  once-a-second decision; the glide only shifts the group it placed (letters, flag and the hairline
  back to her mark together). The shift is a pixel or two, far inside the clearance the planner kept.

## Specs

- `tests/map.smooth.spec.ts` (new, pure): the arrival cut-off on a leg long enough that the 0075 clamp
  cannot be what stops her; one frame pays part of what is owed and never a negative share; her first
  frame is the served point exactly; a ten-mile disagreement is absorbed, monotonically, never past the
  target, and is gone inside a second; a gap past the snap is taken at once while one just inside it is
  eased; a correction at the antimeridian closes the short way and stays on the sheet; and the model
  carries the instant her figures were true (null for a quay, null with no clock asked for).
- `tests/map.atmosphere.spec.ts`: the source pin on the solid/dashed halves was **re-spelt** (the
  halves moved into `Course`), with the reason recorded beside it, and tightened — it now also asserts
  that the dashed half is the water ahead.

## Run here

`npm ci`, `npx tsc -b`, `npx eslint .` — all clean. Pure specs green: map.smooth 9, map.voyage 34,
map.atmosphere 17, duplication + sections 18, map.labels + the rest of the chart batch (marks, wrap,
regions, flag, merchants, goto, dateline, lag, ink) — every pure test passed; **every browser test on
this box fails at `browserType.launch` (no chromium in the sandbox image), so nothing that drives the
real chart was proved here.** `npm run build` was NOT run to completion: it triggers the world-image
step and that is a ~2.5 h build in a sandbox. CI's own `build` job and the acceptance suite are what
prove the bundle and the chart in a browser.

**Not verified by eye.** No one has looked at the running app from this machine; the smoothness itself
is argued from the arithmetic and the specs, not seen.
