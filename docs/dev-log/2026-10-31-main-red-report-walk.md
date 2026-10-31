# MAIN RED after #416 — the walk pressed a face that no longer exists

2026-10-31. Main `48ae21a1` (#416, Report) failed its own Acceptance at
`tests/consistency.spec.ts:337` — "every route, face and page obeys the laws" — at 390×844 AND
1280×800, both with `Error: locator.click: Test timeout of 1800000ms exceeded` (30 minutes each).

## Cause

#416 turned the fourth desk face **Profit → Report** (`deskView.ts` `DESK_FACES` id `report`,
label `command.f_report`) and updated its own specs — but `tests/consistency.spec.ts` still carried

    const DESK_FACES = ['Trade', 'City', 'Invest', 'Profit']

Playwright's `locator.click()` has no time bound of its own: it waits for the tab to appear until
the TEST timeout. A one-word defect therefore looked like a 30-minute hang, with no name to it.
The app was fine; the walk never reached the Report face.

## Fix (tests only — no product change)

1. `DESK_FACES` → `['Trade', 'City', 'Invest', 'Report']`.
2. `pressFace(tabs, face, where, failures)` — every face-tab click (Stats faces and desk faces) is
   bounded to **10 s**; a tab that never becomes pressable records a named violation and the walk
   moves on. A vanished word is now a one-line red, not half an hour.

## Proof (served build of this branch, headless, localhost)

| check | result |
|---|---|
| walk @390×844 | **0 violations, PASS 44.0 s** |
| walk @1280×800 | **0 violations, PASS 44.9 s** |
| negative proof: `'Profit'` added back as a fifth word | walk **fails in ~10 s** with `390 desk/Profit: the "Profit" tab was not pressable within 10 s — does the tablist still carry that word?` — reverted |

`npx tsc -b`, `npx eslint .`, `npm run build` clean.
