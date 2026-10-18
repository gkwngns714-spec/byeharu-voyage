# 2026-10-19 — the daylight masks stop repainting every frame

## Why

The owner still sees black blinks while panning. A probe on his own machine (Intel Arc B390, DPR 2,
Chrome 155) did not reproduce them, and Chrome's tile manager showed no out-of-memory. It did find
one real waste. Both `map-daylight-mask` layers, 2884×1288 device px each, were re-rasterised on every
animation frame, at rest as well as in a pan: ~4,670 tile rasters each per probe run, against ~1,020
for each coast sheet and ~910 for the marks svg (`map-view`).

The cause was `DaylightSheet`'s Sun glide (`src/chart/DaylightSheet.tsx`). It wrote a fresh
`mask-position`, to 1/100 px, on every `requestAnimationFrame`, and every new value repaints the mask.

## A 1-device-pixel threshold would not have helped at the opening view

The brief suggested writing only once the terminator has moved a device pixel. Measured on the
opening view (1440×900, DPR 2), the mask tile is 34,839 css px, so the Sun moves **96.8 device px a
real second**. That is 1.6 px a frame at 60 Hz. A pixel threshold would still write on almost every
frame there, and on every frame at deeper zooms (at the 1.5° harbour zoom it is ~960 px/s).

## The fix: a step read off the raster

The glide now writes only once the Sun has travelled `GLIDE_STEP_DEG = 0.1°` of longitude, or one
device pixel where that is more. A pan or a zoom is still placed at once and exactly, in the layout
effect.

Why 0.1° keeps the look:

- The steepest the daylight ever falls is between sunrise (−0.833°) and civil dusk (−6°, daylight
  0.62). That is 0.38 over 5.17° of elevation, or 18.8/255 per degree.
- A degree of longitude moves the elevation by at most a degree.
- So a mask lagging by 0.1° is at most 1.9/255 off, even where the day and night pictures differ by
  the full 255.

The Sun goes 0.5° a real second, so the mask now moves ~5 times a second instead of every frame
(60–144).

## Measured

All runs below use the same harness (`bv-harness/dpr-scratch/_probe-dpr.mjs`, with `--trace`, and
`--idle 10` added for a 10 s run with no input). Tile rasters are `RasterTask` events per cc layer,
counted by `bv-harness/dpr-scratch/_rasters.mjs`. Builds: main `db7c956` and this branch.

**Headless** (the owner was using the PC, so no headed browser was allowed after the first run).
Software raster, so tiles are smaller and the counts are higher than headed. Compare these runs only
with each other.

| run | build | mask rasters (each) | `map-view` | coast (each) | rAF p50 / p95 / worst ms | black frames |
|---|---|---|---|---|---|---|
| 10 s idle | main | **6,552** | 192 | 32 | 33.3 / 33.4 / 66.7 (30 fps) | 0 |
| 10 s idle | fix | **918** | 231 | 32 | 16.7 / 33.4 / 50.1 (60 fps) | 0 |
| pan run (8 mouse, 8 touch, 4 slow strokes) | main | 10,113 | 3,422 | ~1,980 | 33.3 / 50.0 / 83.4 (30 fps) | 0 |
| pan run | fix | 11,239 | 9,743 | ~3,100 | 16.7 / 33.4 / 50.1 (60 fps) | 0 |

- **At rest:** mask rasters fell 7.1×. The renderer went from 30 fps to 60 fps, because main's
  per-frame mask repaint was costing every other frame in software raster.
- **In a pan:** every frame of a pan still moves the mask on the glass (the view moves under the
  Sun), so a pan still repaints it on each frame drawn. The fix draws twice as many frames (60 vs
  30 fps), so its per-run totals are higher. Per frame drawn, they are lower.

**Headed, Playwright Chromium, DPR 2, main only:** 144.9 fps median, rAF p95 7.6 ms, worst 361 ms,
0 black frames. Mask rasters 4,676 and 4,673, `map-view` 914, coast 1,019 and 1,018. The headed run
of the fix was stopped before it finished, when the owner's screen was being taken over. No headed or
plain-Chrome (`--raw`) figures exist for the fix. **The plain-Chrome frame-time p95 and worst were
therefore not measured** for either build.

**Look at rest:** both builds were frozen at the same instant, with the terminator through the middle
of the glass and the marks hidden. Then the clock was moved 190 ms (0.095°, just under the step, the
fix's worst lag). The full-glass pixel diff against main:

- at T: max 2/255;
- at T+190 ms: **max 3/255**, 0 pixels over 3.

## The marks svg (`map-view`): not changed

Its viewBox is the view, and its content changes on every pan frame. The ports are culled to the
view's window, and the names are re-planned against the view and the chrome keep-out boxes
(`ChartCanvas.tsx`, the `labels` memo keyed on `box`). A translate-only sheet would still repaint, and
would have to be padded past the glass. That adds a layer about 2× the glass, against the tile
budget the 2026-10-18 no-blink fix cut. That trade was not made blind.

## The proof

`tests/map.daylight.raster.spec.ts` (1440×900, DPR 2) works as follows:

1. Freezes the clock (`page.clock.setFixedTime`).
2. Advances it in 20 steps over 2 s so the Sun moves 0.5 device px in all.
3. Reads Chrome's LayerTree `paintCount` of both mask layers before and after. LayerTree is enabled
   across the window, because it counts paints only while enabled.
4. Control: one degree of travel must repaint.

Results:

- main: **40 paints**, red;
- fix: **0 paints**, then 2 on the control, green.

It is in `tests/shard-weights.json`, and the selection picks it through rule I (it names
`map-daylight-mask`) and rule G.

Verified once: `tsc -b`, `eslint` on the touched files, the new spec on both builds.
