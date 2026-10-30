# 2026-10-30 — The City is the game's face, drawn from above

Two owner instructions in one client-only slice (rows 235/236).

## 1. "the city graphic should be in bird's eye view"

`src/features/city/CityScene.tsx` was a side-on skyline. It is now a **plan view of the harbour
town**, looked down on:

- **THE SEA** along the bottom edge, the quay line, two piers and three hulls alongside.
- **THE STREETS** — three roads across the town, five up it, drawn wide with a lit centre.
- **THE BLOCKS** — roofed blocks with a ridge line and a lit slope; a garden in some. The seed moves
  a roof by a pixel or two, so every harbour plans differently and one harbour is identical on
  every render and machine (`seed = port.code`).
- **THE SIX BUILDINGS** stand in their own blocks, matching the six the page offers: the Town Hall
  and its plaza fountain, the Market's six stalls, the long quay warehouses (Storage), the Forge
  with its chimney and rising smoke, the Inn's courtyard, and the Port, which IS the quay.
- **BEYOND THE WALL** — two field strips with furrows and the north wall with its towers.
- **THE HOUR** — the same served clock as before: the town darkens at night, the streets light six
  lamps, windows warm. Tokens only (fill-surface-2 roofs, stroke-edge / stroke-ink-faint streets,
  fill-info water, fill-accent sun and stalls).

The people dots remain from the shell slice: count from the served `size_tier`, no invented number.

## 2. "is there a two version of the game? i mean i keep getting the old screen."

**There was one deployment; the new screen was simply not the screen the game opened on.** The City
page shipped at `/city`, behind the desk — so an opened or refreshed game still showed Command, and
the new screen was reachable only by pressing `City view`.

Fixed by making the city the app's landing screen:

- **`HOME_TAB` = `/city`** (`src/app/navTabs.ts`) — the root route, the wildcard and the post-sign-in
  landing all go there.
- **The rail gained a Command cell** (`compass`), borrowing the tab's own word from
  `shell.tab_Command`; the **Levels placeholder cell is gone** (it opened a "next slice" note), and
  so are its two dictionary keys.
- **The rail stands on the non-ready branches too** (loading, failed, no city in hand), so the
  landing screen can never be a dead end: map, stats, the menu and the desk stay one press away.

Decided by default; the owner may reverse it by moving `HOME_TAB` back to `/command`.

## Measured (local-mode build, `vite preview` on 4201, headless)

`tests/city.page.spec.ts` **PASS**, including the new section 3b:

- the root route lands on `/city`, and the rail's Command cell returns to `/command`;
- the page does not scroll: **390/390 wide, 844/844 tall, scrollY 0, rail bottom 844** at 390×844;
- **320/320 wide, 568/568 tall, rail bottom 568** at 320×568;
- the six building tiles stay ≥ 44 px at 320; a face press moves nothing behind it; the Forge
  face does not scroll the page.

Also green: `tsc`, `eslint`, `vite build`.
