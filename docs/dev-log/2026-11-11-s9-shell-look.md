# 2026-11-11 S9: the shell and the shared card (the remaster's look pass, part two)

S4 (#571) reached only the tokens. This pass does what lives outside them, once, in the shell and the shared card, so every screen moves together. No feature screen's content was edited.

## What changed
- **A left rail from `lg` (1,024 px).** The same `NavBar` stands down the window's left edge, 96 px wide (`RAIL_REM`), the lit cell on a soft gold plate, the Menu at the rail's foot. Phones keep the 56-px bottom bar exactly as it was.
- **One layout authority for it** (`src/components/ui/screenLayout.ts`, "THE SHELL"): two variables set once with the page's (`--nav-h`: 3.5 rem on a phone, 0 from `lg`; `--rail-w`: 0 on a phone, 6 rem from `lg`), and the classes every anchored surface reads: the frame, the nav slot, the Menu tray's anchor, the tap-away plane, the glass beside the rail. The docked page tray, the map's slide-in panels, the Menu tray, the arrival card and the detail page all read them; nothing else spells the bar's height or the rail's width.
- **One shell frame** (`src/app/ShellFrame.tsx`): status strip, page, nav. AppShell and the HQ (`/city`, outside AppShell for its own clock and world beat) both draw it, so **the HQ now has the same status strip every other screen has** (game date, KST clock, purse), not a copy.
- **Trays on a wide glass:** the docked page tray now runs from under the strip to the window's bottom edge (the bar it stopped above is gone from `lg`), its right edge the page's margin measured on what the rail leaves. The Menu tray stands beside the rail on the window's foot, `--page-side` wide. The map's panels reach the bottom edge.
- **Detail pages** (a fleet's page, the yard's, the inn's) stand beside the rail and hold their header and body in one centred 64-rem column (`detailColumnClass`) instead of three islands across 1,280 px.
- **The card, once** (`src/components/ui/cardStyles.ts`, shared by `Card` and `ListPanel look="card"`, which had two copies): 16-px corners, the hairline, one faint raise (`--shadow-raise`, both schemes), 24-px padding from 768 (16 on a phone, unchanged), the title at 20 px from 768 over a hairline that closes the head.

- **The Trade desk's header** (`CommandScreen.tsx`, one class): from 1,024 to about 1,100 px the rail's 96 px left the title, the fleet strip and the five faces too little room and the strip was cut (measured: 527 px of content in a 481-px box at 1,024). The faces now step to a second line at the right where the line is full; at 1,280 it is one line, as before.

- **The desk's middle pane keeps 16 rem** (`DeskFrame.tsx`, one class): the side panes grew to their 22-rem caps before the middle got anything, so at 1,024 the rail left it 176 px and "Your cargo" and the small map were cut (command.design). With a 16-rem floor the sides give way first; from 1,280 every pane is as it was.
- **The rail's width lives only in the shell's frame** (`shellFrameClass`); a route outside the shell (the /ui gallery) has no rail, so its docked tray still stands over its side column.

## Measured laws moved (and why)
- `tests/wide.layout.spec.ts`: the docked tray's right offset is now `max(--page-pad, 50% − rail/2 − PAGE_REM/2)`: the page is centred on what the rail leaves.
- `tests/wide.layout.spec.ts` (COMMAND Route at 1440): a detail page is the full glass BESIDE the rail (x = 96, width = window − 96), not the whole window.
- `tests/map.wrap.spec.ts`: the antimeridian drive pans EAST as its own comment says; it took "the short way", and the rail's narrower chart moved the fitted opening frame across 0°, so the short way became west (copies −1, 0 instead of 0, 1). The law (the seam on the glass, both copies drawn, a tap works) is unchanged.
- `tests/primitives.geometry.spec.ts` (the page): a card's corner is 16 px (was 12) and its padding 24 from 768 (was 20 at 768-1,279): the new card look.
- `tests/desk.terminal.spec.ts` (1440×731): the list starts at the margin measured from the rail's edge (96 + 26), not the window's.
- `tests/unfold.fixture.ts` (the text-on-control measure): a text is clipped by its own host too. A `truncate` name's hidden tail was read as text standing on the next column's row (You at 1,280, nothing of it drawn). A measurement fix, not a law moved.
- `tests/hq.design.spec.ts` (h) and `tests/profile.design.spec.ts` (b): "the rail's top" is the bottom bar's top only when the nav is a bar (wider than tall); from `lg` the rail takes nothing off the glass's foot, so the page's limit there is the glass.

## Proved locally (local world, headless)
wide.layout, nav.geometry, nav.rails, hq.design, profile.design: 36 tests, 35 passed and the one red (the detail page's width, above) moved and re-run green. Shots at 1024×768, 667×375, 320×568, 1920×1080: no screen scrolls sideways; the Menu tray stands whole beside the rail (1024: x 96..448, foot on the window's edge) and on the bar (phones).

## Not done
- `src/features/command/buysell/TradeToast.tsx` still centres on the window, not on the page beside the rail (48 px off at 1280): another slice owns the file.
- The HQ's "Your earnings" card now repeats the purse the status strip shows; whether to drop it is a content call for the HQ slice.
- The fleet page's ship tile (`ShipTile`) lets "4 / 180 tons" run past its right edge at 390, before and after this pass.
