# COMMAND FIX — the last three audit rows (33 · 37 · 38)

2026-10-31. The consistency audit's follow-up slice: the three remaining Command-owned violations.

## Row 33 — the 36-px City view

`src/features/command/city/City.tsx` drew its "City view" button at `size="sm"` (36 px), the one
live user of the design system's sanctioned sub-44 size, declared by test id in
`tests/consistency.spec.ts` (`SM_ALLOWED`). The size attribute is gone (the default md is 44 px),
and the allowlist entry is **deleted in the same commit** (`SM_ALLOWED` is now empty), so the 44-px
floor proves the control instead of excusing it.

## Row 37 — the good sparkline's "—"

The root was `src/components/ui/Sparkline.tsx` itself: below two values it returned a `—` span.
The desk's good cards therefore printed a dash wherever the served series was empty or one point
long, and the audit read it as a placeholder where a figure was owed. It now returns **null** —
the absence is drawn as an absence. A caller that wants a word beside the gap says it itself.

The consistency walk now applies the dash ban to the desk too, and a new `sparkAbsence(page, where)`
reads each card's served `data-points`: a line iff ≥ 2 points, and where < 2 nothing at all
(no `<svg>`, no text).

## Row 38 — the route's in-place unfold

`RouteFold` unfolded its editor in flow above the queue: pressing it re-flowed everything after it,
the exact press-law violation. The row now opens the ONE `DetailPage` (`data-testid="route-page"`),
fixed over the desk and out of flow by construction; closing the page clears the map pick.
`tests/layout.spec.ts` and `tests/wide.layout.spec.ts` were rewritten to the page law: the row, the
queue below it and everything above keep their boxes to the pixel; `desk.plantab`, `command.buySell`,
`desk.city` and `desk.layout` still drive the same flows through the page.

## Gates (served build of this branch, headless, localhost:4317)

- `npx tsc -b` clean · `npx eslint .` clean · `npm run build` clean.
- Suite: `consistency · layout · wide.layout · desk.layout · desk.city · desk.plantab ·
  command.buySell · route.stopface` — **52 passed, 1 skipped, 2 failed**.
- The 2 failures are `route.stopface.spec.ts` pure-function word assertions: the machine locale is
  Korean, so `routeStopLines` renders Korean words while the spec expects English. This is the
  repo's documented local-locale artifact (CI runs the English locale) — no code change follows
  from it; CI re-runs the spec.
