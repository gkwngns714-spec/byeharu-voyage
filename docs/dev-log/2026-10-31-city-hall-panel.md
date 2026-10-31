# 2026-10-31 — the HQ split: plan left, Town Hall in place right; alleys; calm dots

Owner, verbatim: *"the HQ tab, when pressed town hall, the city image you've created should show up.
right now the city image is at center, move it the left side, and then at the right side show what
you would see the page pop up,. no need market info. tax info. influence yes, investors - tappable
where when tapped, a list slides to the right where you can close."* Then: *"the town hall screen is
on the same HQ screen, but where the city is."* Then: *"you know that this game is also for mobile
right?"* Same day, two more: *"add more roads that leads to the buildings too"* · *"make the dot
speed 3 times slower"*.

## The split

The City page (HQ) main area is one split at every glass:

- **LEFT** — the city plan (the whole 240 plate, `CityScene`, square at the phones), with the
  figures card beneath it (Population estimate · Gold · Status · Relationship).
- **RIGHT** — the TOWN HALL IN PLACE (`features/city/CityHallPanel.tsx`). It composes the same
  served block the hall face read (`world.town_hall`): the city's GOLD (the purse), the INFLUENCE
  book (holder, shares, your influence, Donate) with the tax rows OFF (`TownHallInfluence
  showTax={false}`), and one tappable INVESTORS row. No market/day-book rows, no works/Invest.
- The other five buildings keep their full-screen faces; the hall has NO face and NO overlay — the
  `CityFace` hall branch and the `'hall'` building type are removed.
- The Investors row (44 px) is pinned under the panel's own scroll. It opens the served board in
  the design system's **side Tray** (`mode="side"`, `bv-slide-in-right`): full width below `lg`
  (the owner's mobile rule), 39rem on a wide glass, its own 44-px ✕, fixed over the page — the page
  behind never reflows. One shared `InvestorRow` serves the town hall face and the drawer.

## Measured (headless chromium, 4208; screenshots read)

| glass | plan | hall panel | investors row | drawer | page |
|---|---|---|---|---|---|
| 390×844 | 179×179 (square, left) | 171×477 (right) | 44 px | full width 390, right edge, y 32 | no scroll |
| 320×568 | 144×144 (square, left) | 136×201 (inner scroll) | 44 px | full width 320, right edge | no scroll |
| 1280×900 | 624×545 (drawing square via meet) | 616×533 | 44 px | — | no scroll |

At 320 the panel's deeper influence rows sit behind its own inner scroll (the panel is 201 px tall
between the plan row and the five doors); the row and the treasury stay on screen. The summary's
Relationship word wraps to two short lines at 320 and stands on one at 390. Compact caption labels
("Gold", "Investors") keep the panel's words on one line at both phones.

## The alleys

`CityScene` gains ONE `<path>` of thin lanes (`stroke-ink-faint`, 0.7): a service lane around every
block (sides that would run under a named building are left out), a connector to the nearest lane or
street (or a short alley mouth), and a lane of its own to the warehouses (between their rows), the
hall plaza, the forge yard and the inn yard. Connectors are refused under a named building or into
the river mouth, so the ink never crosses a building or the water. Scene nodes 390 → 391.

## The calm walk

Every moving person's duration is ×3 (strollers 18-42 s, walkers 42-78 s); the begin phases are
unchanged, so they stay out of step. The spec's walker window moved from 900 ms to 2500 ms and still
requires more than 0.5 px of movement — measured green.

## Gates

- `npx tsc -b`, `npx eslint src/features/city src/live/TownHallInfluence.tsx src/live/CityTownHall.tsx
  src/live/CityInvestors.tsx`, `npm run build` — clean.
- `tests/duplication.spec.ts` — 11/11 (the first run caught a hand-written drawer header recipe;
  the drawer now IS the design system's side Tray and the copy is gone).
- `tests/city.page.spec.ts` — PASS (21.4 s): the HQ split at 390/320/1280/1440 (plan left of the
  panel, plan square at the phones), the panel's treasury + influence + investors row with no
  market/tax rows, the drawer full-width at the right edge on both phones with its own 44-px close,
  nothing behind moving on open or close, no page scroll, scene 391 nodes, and the five doors' faces.

## Screenshots (DPR 2, kept outside the repo at C:\Users\gkwng\dev\hall-shots\)

`hall-split-390x844.png`, `hall-split-320x568.png`, `hall-split-1280x900.png`,
`hall-drawer-390x844.png`, `hall-drawer-320x568.png`. Judged: the split holds at both phones, the
words hold on one line, the drawer covers the width with its own close, and the alleys read as fine
streets around the blocks without crossing a building.
