# 2026-11-08 — the HQ's Investors drawer slides from the window's edge; Production's cargo list counts the supplies (client only)

The drive audit (#560, `docs/dev-log/2026-11-08-drive-audit.md` §2) found three defects on the HQ. This slice fixes them: product
code only, no migration, no server change. Worktree `fix-hq-drawer-production` from origin/main 2353770b; the local PGlite world (no
`.env.local`; production never touched); `vite preview --port 4208 --host localhost`; every spec `--workers=1`, headless, DPR 2.

## The defects, in the owner's words

- **D2 (row 247)** — *"investors - tappable where when tapped, a list slides to the right where you can close"*. The list APPEARED:
  sampled frame by frame from before the press, its first painted frame was already where it lands (left 856 at 1280, 0 at 390),
  `data-tray-mode="docked"`, computed animation none.
- **D3 (rows 247, 278)** — at a wide glass the drawer stood inside the window's right edge by the page's margin: x 856–1240 at 1280
  (40 px), 944–1360 at 1440 (80 px). The owner refused exactly that look on the map one day later (row 278: *"not totally fully on
  the right. i want it to slide from the right slide from the edge of the page"*); #491/#493 fixed the map's tray alone.
- **D4 (row 302)** — the Production page's Cargo column read "cargo 4 / 180 tons" over "Cargo empty." on an empty hold; the Fleets
  row said the same "cargo 4 / 180 tons".

## Cause

- D2, D3: `src/features/city/CityHallPanel.tsx` opened the drawer as `Tray mode="docked"`. On a wide glass a docked tray takes
  `trayDockPageClass()` (`src/components/ui/screenLayout.ts`): the page's side-column dock, whose right edge is
  `max(--page-pad, 50% − 40rem)` — the page's margin — and which carries no entering animation. The slide (`bv-slide-in-right`) and
  the window's edge (`right-0`) belong to `traySideEdgeClass()`, `Tray mode="side"`, the map's panel. The drawer had been docked on
  2026-11-04 because the side panel was 39 rem wide then; the same day's map redesign made the side panel `--page-side` wide, so the
  reason for the dock was gone.
- D4: `src/live/PortProduction.tsx` composed the shared `CargoBar` (used = `fleetHoldUsed`: goods AND supplies, the one hold of
  DESIGN C.3) over its own goods-only list from `world.warehouse`. The four tons were her supplies (15 days).

## The change

- `CityHallPanel.tsx`: the Investors drawer is `Tray mode="side"`. `traySideEdgeClass` is the one authority for how it enters (slides
  in from the window's right edge; ✕ slides it back out) and where it lands (the window's edge; from 1,024 px the side column's width,
  below that the whole glass between the status strip and the nav). Nothing copied; the page dock of every other docked tray (Stats,
  Fleets, the desk) is untouched. The doc comments in `Tray.tsx` and `screenLayout.ts` name the second user.
- `PortProduction.tsx`: the cargo list carries the supplies as a plain line — "Supplies" / "보급" (`fleets.holdProvisions`, the word
  the Fleets page's hold already uses), the tons from the same fold the Fleets page draws (`fleetHoldBreakdown().provisionsT`), no act
  (STORE and TAKE move goods). "Cargo empty." stands only over a hold with nothing in it. The bar's meaning is unchanged.
- Specs: the three `test.fixme` laws are real tests. `tests/drive.hq.spec.ts`: the slide at 1280 and 390, the drawer's left edge
  recorded on every painted frame from before the press (the `map.tray.edge` method: first frame off the window, then it travels
  in); the edge at 1280, 1440 and 390 (right edge = window ±1, the side column's width from 1,024, no sideways scroll, the frame
  behind unmoved before, during and after). `tests/drive.market.spec.ts`: the bar's tons on board = the sum of the list's lines, to
  the ton; "Cargo empty." only over a bar at 0. `tests/hq.design.spec.ts` law (d) held "the side column's x" — the very look D3 names —
  and now holds the window's edge and the side column's width, at five glasses, read after the slide has landed (`arrivedAtEdge`).

## Red first, then green

RED on the old build (2353770b, with the new specs):

| law | 1280 | 1440 | 390 |
|---|---|---|---|
| the list SLIDES in | 609 frames, left 856 on every one; `docked`, animation none | — | 13 frames, left 0 on every one |
| lands on the window's edge | x 856–1240, inset 40 | x 944–1360, inset 80 | x 0–390 (passes: the phone sheet is the glass) |
| bar and list agree | "cargo 4 / 180 tons Cargo empty." — the list adds to 0 | | |

GREEN with the fix:

| law | 1280 | 1440 | 390 |
|---|---|---|---|
| the list SLIDES in | 32 frames, lefts 1280, 1173, 1077, 1012, 971, 946 … 896; `side`, `bv-slide-in-right` | — | 31 frames, lefts 390, 281, 184, 118, 77, 51 … 0 |
| lands on the window's edge | x 896–1280, inset 0, 384 wide = the side column | x 1024–1440, inset 0, 416 wide = the side column | x 0–390 |
| bar and list agree | "cargo 4 / 185 tons · Supplies 4.2 tons" — bar 4, list 4.2 | | |

Then, one worker each, on the same build: `city.production` 4/4, `hq.design` 15/15, `city.page` 1/1, `city.audit` 9/9, `consistency`
17/17, `map.tray.edge` 8/8, `fleets.design` 12/12, `drive.market` 4/4, `drive.hq` 9/9 (1 skipped: the audit's D1 walkers fixme, not this
slice); `tsc -b`, `eslint .` and `vite build` green. No CSS and no RPC touched.

## Pictures (`docs/dev-log/2026-11-08-hq-drawer-production/`, DPR 2)

`before-hq-investors-{1280,1440,390}@2x.png` → `hq-investors-{1280,1440,390}@2x.png` (the drawer 40 / 80 px inside the edge, then on
it); `before-production-cargo-1280@2x.png` → `production-cargo-1280@2x.png` ("Cargo empty." under 4 tons, then "Supplies 4.2 tons").

## What a player sees

Press Investors on the city hall: the list slides in from the right edge of the window and stops ON it, the side column's width, over
the hall panel and the purse; nothing behind it moves; ✕ slides it back out. On a phone it slides in over the page between the top strip
and the tab bar, as the map's pop-up does (before, a sheet covered the whole glass with no slide). On Production, the Cargo column's bar
and list say one hold: "4 / 180 tons" over "Supplies 4.2 tons" (the picture; the total read 185 on one boot), and the goods aboard each
with their tons.

## What is not proven

- Never driven on production. The local company has no investors ("Nobody yet."): the drawer was driven, the list's rows were not.
- The hold total read 180 on the red run, 185 on the laws' green run and 180 again on the full run: a served figure that moves between
  boots of the same cached image, not this change — bar and list read the same served fleet, which is what the law compares.
