# MAIN RED: a skipped test is a failure — and a paused SMIL timeline

2026-11-01. Main's newest acceptance (run 41212925876 on `0ef5281f`) was red twice:

- shard 1/3: **`1 test(s) skipped`** — the declared `test.fixme` at `tests/consistency.spec.ts:564`
  ("HQ at 320: the hall panel never scrolls"). CI counts every skip as a failure, and the city
  slice that fixed that hall merged (#429/#430), so the fixme excused a defect that no longer
  existed.
- shard 3/3: **`1 failed`** — `tests/city.page.spec.ts:155`, "the people are still (moved 0.00 px
  in 2500 ms)".

Both are test defects; no product change.

## 1. The fixme, flipped to a real test — measured first

Measured on the served build at **320×568** (`origin/main 0ef5281f`, headless, English):

| state | page | hall panel | book |
|---|---|---|---|
| folded | **568/568** (flat) | **278/278** (fits) | absent |
| expanded (fold pressed) | **568/568** (flat) | **289/278 → 11 px of scroll INSIDE the panel** | 125 px |

These are exactly #430's stated numbers. The new test asserts: the page is flat in both states; the
folded panel fits; the expanded book scrolls inside the panel (0 ≤ inner ≤ 12 px — its measured
11 + 1 of rounding) and never the page. A regression past those numbers fails. The book must not be
open before its fold is pressed. **PASS 5.7 s.**

## 2. The walkers' motion red — a paused timeline, not a still city

The test sampled one walker's box, waited 2 500 ms, sampled again, and demanded > 0.5 px. It passed
locally (**21.8 s**) but on a loaded CI shard measured **0.00 px**: an SVG `animateMotion` timeline
**pauses in a hidden document**, and a page can be backgrounded under shard parallelism — the city
was fine, the animation had frozen.

Fix: `page.bringToFront()` before sampling, and **poll** for the movement over up to 8 × 800 ms —
the law is unchanged (a walker must move), but a frozen or slow start no longer reads as a still
crowd. **PASS 20.1 s.**

## 3. The skip sweep (CI counts every skip)

- `test.fixme` **call sites after this PR: zero** (the only two remaining occurrences are the
  comments in `consistency.spec.ts` that explain this history).
- Every other `test.skip(` in `tests/` is a **conditional guard** — `!(await reachable(...))` (the
  app was not served, which never fires in CI because it serves the build) or a per-layout
  condition inside a describe loop. None is unconditional; CI's run counted exactly one skip
  before this change and will count zero now.

## Gates (served build, headless)

- `tests/consistency.spec.ts` — the whole file: **17 passed, 0 failed, 0 skipped (3.9 min)**,
  including both walks (390×844 45.6 s · 1280×800 44.0 s) and the new hall test.
- `tests/city.page.spec.ts` entry test: **PASS 20.1 s**.
- `tsc -b`, `eslint .`, `npm run build` clean.
