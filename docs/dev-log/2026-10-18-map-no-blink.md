# 2026-10-18 — a fast pan never blinks — `osn-map-noblink` (client only, no migration)

Owner, 2026-10-17: *"when i move map, it blinks too much..."*, then *"move the map faster, it will show
blink, way faster."*

## The cause, from running state

The app was served from a fresh build (`npm run build`, `vite preview`, no `.env.local`, so a local
PGlite world). It was driven in **headed** Playwright Chromium on this machine's GPU. Every
composited frame was recorded with the CDP screencast while the probe made fast pans: 3,000 px in
300 ms, by mouse and by touch, at 1440×900 and 390×844. The view was first centred on the
terminator, so day and night were both on the glass. Then I counted the painted classes in each
frame (day sea, day land, night land, any lit pixel). A **blink** is a frame whose coverage drops
more than 5 points below the best of the 3 frames before it and the best of the 3 after it.

- **Headless shows nothing.** Software raster had no blink frame either before or after the fix, so a
  headless frame grab cannot prove this bug.
- **Headed, on main:** every run blinked, 4–17 frames in 8 strokes and **124 in 24 strokes**. What
  the frames show:
  - whole rectangles of the coast unpainted (`before-1440-mouse-coast.jpg`);
  - the day side going to night for one frame;
  - once the entire page dark, the top bar included (`before-1440-mouse.jpg`).

  These are tiles Chrome had not rasterised when it drew the frame.
- **It was Chrome's tile-memory budget.** The same drags with `--force-gpu-mem-available-mb=4096`
  showed **0** blink frames in two runs; the default showed 5 and more. `--disable-gpu-rasterization`
  also showed none, at 36 fps.
- **What spent the budget.** The CDP `LayerTree` at 1440×900 counts 8 compositor layers as large as
  the glass, plus two masked render surfaces:
  - the night sea, re-rasterised with the page on every frame;
  - the day sea's picture, re-rasterised on every frame because its svg took the view box;
  - two `mask-image` layers;
  - the graticule svg, a glass of its own, re-drawn every frame;
  - the night coast sheet;
  - the day coast sheet, **nested inside the night coast sheet** with its mask riding that sheet's
    translate;
  - the marks.
- **Isolating it** (CSS injected into the running page):
  - hiding the day coast's nested sheet left 0 blinks;
  - hiding all the day sheets left 0;
  - hiding only the graticule svg left 0 in one run.

  The chart sat just past the budget, and a fast pan pushed it over.
- **Not the cause:**
  - The coast sheet's re-base (`paperOf`, every half glass) was not it on its own. With the day
    sheets hidden, 38 re-bases in a run gave no blink.
  - The `PAPER_SETTLE_MS` narrow/wide swap does not fire during a pan (`nextCoastPaper` keeps the
    wide sheet when the width is unchanged).
  - No React keys change and no element remounts. The new spec watches for that.

## The fix (one render authority, `src/chart/ChartCanvas.tsx`)

Fewer surfaces, and nothing re-drawn that a pan only moves:

- **The seas are pictures of the glass** (`SeaLayer.tsx`, `SEA_VIEWBOX`). The night sea and the day
  sea are drawn on the glass's unit square with `preserveAspectRatio="none"`, so a pan never touches
  them. It is the same ellipse, because the vignette was already in the rect's bounding box.
- **The graticule rides the night coast's paper** (`CoastSheet`), under the coast. A pan moves it by
  the sheet's translate, and a re-base redraws it with the sheet. The separate glass-sized graticule
  svg is gone.
- **The day coast is a sheet beside the night one, not inside it.** Its `DaylightSheet` is the glass
  itself, as the day sea's always was, and the day coast's paper moves under that mask by the
  night sheet's own translate.
- **The paint order is unchanged:** night sea, day sea through the Sun's mask, graticule, night
  coast, day coast through the Sun's mask, marks.
  - A pinned-clock screenshot of main and of this build at 1440×900 differs by at most 4/255 on
    any pixel.
  - A merged single mask was tried first. It was dropped because it put the night shallows under
    the day sea and changed the day shallows' tone.
- **The marks svg is now the view sheet**, `data-testid="map-view"`: the one svg whose viewBox is
  the view. The specs and `appReady.fixture.ts`'s `zoomStepMs` read the view there. They used to read
  "the first svg", which was the sea's.

After the fix the layer tree has 7 glass-sized layers (root, the day sea picture, two masks, the
two coast sheets, the marks), and neither sea is among those that repaint on a pan.

## Evidence (headed Chromium, GPU, fast pans of 3,000 px in 300 ms)

| run | build | strokes | blink frames | rAF median | rAF p95 |
|---|---|---|---|---|---|
| 1440×900 mouse | main | 24 | **124** | 71.9 fps | 138.8 ms |
| 1440×900 mouse | fix | 24 | **0** (1 flagged: the terminator sweeping open ocean, fully painted) | 142.9 fps | 131.8 ms |
| 1440×900 touch | fix | 24 | **0** | 142.9 fps | 104.1 ms |
| 390×844 touch | fix | 12 | **0** | 142.9 fps | 118.1 ms |
| 390×844 mouse | main / fix | 12 | 0 / 0 blank (fix: 17 flagged, all fully painted frames of the terminator crossing; checked by eye) | 14.4 / 11.1 fps | 160 / 153 ms |

- **The 390×844 mouse row is the extreme case.** 8 glasses in 300 ms means a coast re-base on
  nearly every frame. Both builds run at the same rate there.
- **Frame strips:**
  - `2026-10-18-map-no-blink/before-1440-mouse.jpg`: the day sea, then a black frame, then the day
    sea;
  - `before-1440-mouse-coast.jpg`: half the coast unpainted;
  - `after-1440-mouse.jpg` and `after-390-touch.jpg`: consecutive frames of the same pans, all
    painted.

## The spec — `tests/map.noblink.spec.ts` (in `shard-weights.json`; selected by rules C and I)

It checks this at 1440×900 and 390×844, on real fast pans by mouse and by touch:

- neither sea's svg is mutated;
- the graticule is on the coast sheet;
- no daylight mask sits inside a moving sheet;
- the day coast is a sheet under a mask;
- no chart sheet is unmounted;
- the night coast sheet covers the glass on every animation frame;
- at most 7 compositor layers are half the glass or larger (`LayerTree`).

The mechanism is asserted because headless cannot see the blink. On main it fails at both viewports;
on the fix it passes.

**Touched specs, updated:**

- `map.lag` counts the graticule's re-base with the viewBox, and holds that no mask is inside the
  coast sheet;
- `map.wrap` finds the day coast's `<use>`s on `map-coast-sheet-day` and skips both coast sheets
  when it looks for the marks;
- `appReady.fixture`, `map.lag`, `map.marks`, `map.perf`, `map.sendfleet`, `map.sun` and `map.wrap`
  read the view from `map-view`.

**Run once on the fix: 91 passed, 0 skipped.** Those are noblink, lag, wrap, sun, perf, marks,
sendfleet, landfall, regions, chart.ink, atmosphere and coastline. `tsc -b` and `eslint` are clean.

**CI:** `appReady.fixture.ts` changed, so the PR runs the full suite (rule F). That cannot be
avoided: the fixture read the view from the first svg.
