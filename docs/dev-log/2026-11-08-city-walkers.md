# 2026-11-08 — the HQ's people walk (D1 of the drive audit)

**The owner, three times** (docs/OWNER_REQUESTS.md rows 241, 242, 248, 2026-10-31): *"these dots are
population, it can stop it can go back and forth, random movements"* · *"make the dot speed 3 times
slower"* · *"does this look like a city with citizens?"*.

**The defect** (docs/dev-log/2026-11-08-drive-audit.md §2 D1): on the HQ, on every fresh load at 1280
and 390, **0 of 36 walkers moved**. The drive audit sampled every dot's rect inside the page over 4 s,
read the first dot's x every 100 ms (one value), compared two clips of the plan 3 s apart (byte-
identical), and found the svg's SMIL clock running with nothing paused and no remount. The same
markup alone on a blank page moved; `svg.setCurrentTime(svg.getCurrentTime())` woke the app's dots.
`tests/city.page.spec.ts` "the people walk" was green on main because it read one dot right after a
viewport change (390 → 320 → 360 → 1280 → 1440 → 390), when the plate re-scaled under the dot.

**The cause.** `src/features/city/CityScene.tsx` animated the 36 walkers and the 24 strollers with SVG
`<animateMotion path dur begin repeatCount>` (SMIL) on circles without cx/cy. The scene's SMIL
timeline was never serviced until something seeked it: the clock advanced, the positions did not. A
SMIL timeline is also paused in a hidden document, is not watchable, and cannot be driven by the app.

## Red first — the honest read on the OLD code (main 2353770b), served build on 4207, DPR 2

The new law (`tests/cityWalk.fixture.ts`, used by `city.page.spec.ts` and `drive.hq.spec.ts`): a FRESH
load, nothing touched, every walker's on-glass centre sampled inside the page 12 times 250 ms apart,
plus two clips of the plan before and after. Most walkers must travel more than a pixel, no walker may
step more than 3 plan units between two samples (a lap restart or a re-scale is a step the size of a
street), and the two clips must differ.

```
the people walk @1280: {"dots":36,"moved":0,"farthest":0,"maxStepUnits":0,"witnessDistinct":1,"visible":"visible","framesDiffer":false}
  ✘ the people walk at 1280 … (10.2s)   "@1280: 0 of 36 walkers moved over 3 s (farthest 0 px) — the people stand still"
                                        "@1280: the plan's two clips 3 s apart are byte-identical"
the people walk @390:  {"dots":36,"moved":0,"farthest":0,"maxStepUnits":0,"witnessDistinct":1,"visible":"visible","framesDiffer":false}
  ✘ the people walk at 390 … (9.9s)     "@390: 0 of 36 walkers moved over 3 s (farthest 0 px) — the people stand still"
                                        "@390: the plan's two clips 3 s apart are byte-identical"
2 failed
```

## The choice: CSS `offset-path` keyframes or one `requestAnimationFrame` loop — measured

Both candidates were built on the SAME lifted scene markup (the real HQ plan's svg and the app's
stylesheet on a blank page, so only the mover differs) and measured in headless Chromium through CDP
`Performance.getMetrics` over a 10 s window: main-thread task time, style recalcs (count and ms),
layouts, script time, the renderer process's CPU, rAF frames a second and long tasks. Two glasses:
a phone (390×844, DPR 2, **4× CPU throttle**) and the owner's desktop (1280×800, DPR 2).

**Desktop 1280×800, DPR 2, no throttle** (per 10 s; "still" = the same plan with no mover at all):

| mover | fps | main-thread task ms | script ms | style recalcs (ms) | layouts (ms) | renderer process CPU ms | long tasks |
|---|---|---|---|---|---|---|---|
| still plan (floor) | 60.1 | 376 | 71 | 0 | 0 | 655 | 0 |
| SMIL as designed (kicked awake) | 60.0 | 736 | 61 | 0 | 601 (19) | 4,757 | 0 |
| (a) CSS `offset-path` keyframes, 60 Hz | 60.0 | 832 | 79 | 600 (111) | 600 (58) | 4,772 | 0 |
| (b) rAF loop, `transform`, 60 Hz | 60.0 | 770 | 146 | 601 (139) | 601 (16) | 5,593 | 0 |
| **(b) rAF loop, `transform`, 20 Hz** | 60.0 | **541** | 150 | **200 (44)** | **200 (6)** | **2,244** | 0 |

**Phone 390×844, DPR 2, 4× CPU throttle** (per 10 s; this read is noisy by about ±1 s, the floor itself
carried 15 long tasks from the throttled boot and the sampler):

| mover | fps | main-thread task ms | script ms | style recalcs (ms) | layouts (ms) | renderer process CPU ms | long tasks (ms) |
|---|---|---|---|---|---|---|---|
| still plan (floor) | 58.6 | 2,403 | 529 | 0 | 0 | 10,628 | 15 (1,242) |
| SMIL as designed (kicked awake) | 58.8 | 3,883 | 346 | 0 | 589 (91) | 13,028 | 8 (652) |
| (a) CSS `offset-path` keyframes, 60 Hz | 57.5 | 5,213 | 517 | 574 (689) | 574 (342) | 13,518 | 29 (2,321) |
| (b) rAF loop, `transform`, 60 Hz | 58.4 | 4,414 | 953 | 584 (802) | 584 (77) | 13,602 | 30 (1,962) |
| **(b) rAF loop, `transform`, 20 Hz** | 58.1 | **4,170** | 1,214 | **195 (380)** | **195 (30)** | **11,735** | 42 (3,248) |

The app itself, old code as served (SMIL never serviced, so a still picture): desktop 367 ms main /
735 ms process; phone 2,328 / 10,726 — the floor. (`scratchpad/bench/bench-walkers.mjs`, results in
`bench-results.json` of that run.)

What the table says, and the choice:

- **Every 60 Hz mover pays the plan's raster sixty times a second**, and at DPR 2 that is the whole
  cost: the renderer process spends ~4-5 s of every 10 s on the desktop for CSS, SMIL and the 60 Hz
  loop alike, against 0.66 s for a still plan — the main thread is a small part of it (0.7-0.8 s).
  The 60 dots are scattered over the whole plate, so each frame's damage is most of the plan, and the
  plan carries the 2,200-speck stipple, the lights and the crowd as round-capped stroke paths.
- **A 20 Hz loop pays a third of that**: 2.2 s process / 0.54 s main on the desktop, 200 style
  recalcs instead of 600. A walker's pace is 2-5 plan units a second — 0.2-0.7 px a step at the
  owner's widest glass — so finer steps buy nothing the eye can see.
- **(a) CSS `offset-path`** is the dearest mover here (most style recalc time), it cannot be
  throttled, and it does follow the path in viewBox units in Chromium (the dot's centre 0.09 px /
  0.3 px off its path at the two glasses, `CSS.supports('offset-path', path())` true) — but on an SVG
  circle that is the browser's SVG motion-path support, which the owner's Safari would have to be
  trusted for exactly the way SMIL was trusted and failed. WebKit was not measured here (no WebKit
  build on this machine); the CSS path lost on Chromium's own numbers before that question arose.
- **Chosen: (b), one `requestAnimationFrame` loop at 20 Hz**, writing one `transform` per person who
  moved (a person standing at a stop costs no write). It runs wherever rAF runs, pauses itself in a
  hidden tab, and is gated by the document's visibility, the plan's intersection with the glass and
  `prefers-reduced-motion`.

## What changed

- `src/features/city/cityWalk.ts` (new): the pure walk — a route is the street's curve sampled by
  distance (`routeOf`, `pointAt`), a person's cycle is a list of legs (`walkOf`: walk out with one
  stop on the way, rest at the end, walk back with another stop, rest; a stroller goes there and back
  with a breath at each end), `walkAt(walk, t)` is the point at document time t — and ONE
  `requestAnimationFrame` loop per scene (`useCityWalk`) writing one `transform` per moving circle
  **20 times a second** (`WALK_HZ`). It stops while the document is hidden and while the plan is off
  the glass (IntersectionObserver), and never starts under `prefers-reduced-motion: reduce` (the
  people stand where their phase puts them).
- `src/features/city/CityScene.tsx`: the 60 `<animateMotion>` elements are gone (scene nodes 391 →
  331, under the 400 budget of row 246). The strollers keep their lines, laps (18-42 s) and starts;
  the walkers keep their streets, laps (42-78 s — one traverse, the ×3 of row 248) and starts; where a
  walker stops and for how long is the city's seed. Each moving circle names its walk (`data-walk`),
  each walker its lap and start (`data-lap`, `data-begin`) for the specs. React renders every circle
  at its document-time-0 place — a value that never changes between renders — so the hall's 1 Hz
  re-render never writes a position back under the loop; the loop places them before the first paint.
- `tests/cityWalk.fixture.ts` (new): the one sampler and verdict.
- `tests/city.page.spec.ts`: "the people walk" is its own test, on a fresh load at 1280 and 390 at
  DPR 2, no viewport change (red above on the old code; green below).
- `tests/drive.hq.spec.ts`: the audit's fixme is the law, through the same sampler; the ×3 law reads
  `data-lap` (a missing attribute reads 0 and fails loudly); the SMIL-clock read is gone.

## Green — the same specs on the fixed build (served on 4207, one worker)

```
the people walk @1280: {"dots":36,"moved":35,"farthest":22.6,"maxStepUnits":1.29,"witnessDistinct":12,"visible":"visible","framesDiffer":true}
  ok tests/city.page.spec.ts › the people walk › the people walk at 1280: on a fresh load, sampled over 3 s with no viewport change, most walkers move and none jumps (10.5s)
the people walk @390:  {"dots":36,"moved":35,"farthest":16.3,"maxStepUnits":1.3,"witnessDistinct":12,"visible":"visible","framesDiffer":true}
  ok tests/city.page.spec.ts › the people walk › the people walk at 390: … (10.1s)
  ok tests/drive.hq.spec.ts › HQ @1280: the people walk — … (rows 241/242/248) (10.4s)   35 of 36 moved, farthest 22.2 px, largest step 1.09 units
  ok tests/drive.hq.spec.ts › HQ @390:  the people walk — … (rows 241/242/248) (10.1s)   35 of 36 moved, farthest 16.4 px, largest step 1.29 units
```

(The one walker that did not move in a 3 s window is a person standing at a stop — the owner's "it
can stop".) The witness dot's x took 12 distinct values in 12 samples: a walk, not a jump.

The specs that touch the city, each file whole, `--workers=1`: `city.page` 3/3, `city.audit` 9/9
(scene **331 nodes** at 390 and 1280, 89 circles, under the 400 budget of row 246; 391 before),
`city.live` 1/1 (the hall's 1 Hz poll and its hidden-document pause untouched), `hq.design` 15/15
(en-US and ko-KR at five glasses), `drive.hq` 6 passed + the audit's own two fixmes for D2/D3
(the Investors drawer, not this fix), `consistency` HQ parts 4/4 — **34 passed, 2 skipped, 6.9 min**
and **4 passed, 37.5 s**. `tsc -b`, `eslint` on the changed files, `vite build` clean.

**The fixed app itself** (the same CDP read as the bench, 10 s, DPR 2, the plan on the glass):
desktop 1280 — **542 ms main / 2,246 ms renderer process, 200 style recalcs, 200 layouts, 60 fps,
0 long tasks** (the bench's 20 Hz row to the millisecond); the old app's still picture read 367 /
735. Phone 390, 4× throttle — **3,547 ms main / 12,147 ms renderer process, 194 style recalcs, 4 long tasks (418 ms), 36 of 36 walkers moved** (the floor of that throttled read, the old app's still picture: 2,328 / 10,726; the bench's 20 Hz row: 4,170 / 11,735).

**The pause gates, read**: with the plan BELOW the fold inside the page's sheet at 390×844 (the
phone's first screen is the hall panel), the app read **0 style recalcs and 0 walkers moved in 10 s**
— the IntersectionObserver gate held the loop; brought onto the glass, they walk. The
hidden-document gate is a law in `city.page.spec.ts` (fake `visibilityState`, the city.live spec's
own method): hidden, 0 move; visible again, they walk on — read green at both glasses: hidden 0 moved over 1 s, visible again 32 moved.

## Pictures (DPR 2, `docs/dev-log/2026-11-08-city-walkers/`)

- `before-plan-1280@2x-t0.png` / `-t3.png`, `before-plan-390@2x-t0.png` / `-t3.png`: the old code,
  the plan clipped twice 3 s apart. Read: the engraved walled town, the warm crowd at the market, the
  quay and the hall, the people on the streets — and the two frames are the same picture; the notes
  (`before-notes.json`) put the first six walkers at the same six points at t0 and t3.
- `after-plan-1280@2x-t0.png` / `-t3.png`, `after-plan-390@2x-t0.png` / `-t3.png`: the fixed build.
  Read: the same town, the same crowd, the same picture when still — nothing in the drawing changed;
  the people on the streets stand at different points in the two frames. `after-notes.json`: at 1280
  the first walkers went (345.7, 481.9) → (365.3, 482.2), (393.6, 481.6) → (407.0, 481.0),
  (399.7, 377.6) → (414.4, 377.7) in 3 s; at 390 (129.2, 578.8) → (143.1, 579.1), (164.0, 578.6) →
  (173.5, 578.2).
- `before-hq-1280@2x.png`, `after-hq-1280@2x.png`: the whole HQ at the owner's desktop glass, for
  the frame around the plan (unchanged).

## What a player sees

On the HQ the people on the streets and lanes walk — out, a pause somewhere on the way, on to the
end, a rest, and back — each at its own pace and phase, so the crowd never marches in step; the
strollers at the market and the quay pace their short lines. Nothing else in the picture changed; a
player who asked for reduced motion sees the same still plan as before, with the people spread along
the streets.
