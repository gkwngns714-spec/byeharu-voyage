# 2026-11-11 S9: the shell and the shared card (the remaster's look pass, part two)

S4 (#571) reached only the tokens. This pass does what lives outside them, once, in the shell and the shared card, so every screen moves together. No feature screen's content was edited.

## What changed
- **A left rail from `lg` (1,024 px).** The same `NavBar` stands down the window's left edge, 96 px wide (`RAIL_REM`), the lit cell on a soft gold plate, the Menu at the rail's foot. Phones keep the 56-px bottom bar exactly as it was.
- **One layout authority for it** (`src/components/ui/screenLayout.ts`, "THE SHELL"): two variables set once with the page's (`--nav-h`: 3.5 rem on a phone, 0 from `lg`; `--rail-w`: 0 on a phone, 6 rem from `lg`), and the classes every anchored surface reads: the frame, the nav slot, the Menu tray's anchor, the tap-away plane, the glass beside the rail. The docked page tray, the map's slide-in panels, the Menu tray, the arrival card and the detail page all read them; nothing else spells the bar's height or the rail's width.
- **One shell frame** (`src/app/ShellFrame.tsx`): status strip, page, nav. AppShell and the HQ (`/city`, outside AppShell for its own clock and world beat) both draw it, so **the HQ now has the same status strip every other screen has** (game date, KST clock, purse), not a copy.
- **Trays on a wide glass:** the docked page tray now runs from under the strip to the window's bottom edge (the bar it stopped above is gone from `lg`), its right edge the page's margin measured on what the rail leaves. The Menu tray stands beside the rail on the window's foot, `--page-side` wide. The map's panels reach the bottom edge.
- **Detail pages** (a fleet's page, the yard's, the inn's) stand beside the rail and hold their header and body in one centred 64-rem column (`detailColumnClass`) instead of three islands across 1,280 px.
- **The card, once** (`src/components/ui/cardStyles.ts`, shared by `Card` and `ListPanel look="card"`, which had two copies): 16-px corners, the hairline, one faint raise (`--shadow-raise`, both schemes), 24-px padding from 768 (16 on a phone, unchanged), the title at 20 px from 768 over a hairline that closes the head.

## Measured laws moved (and why)
- `tests/wide.layout.spec.ts`: the docked tray's right offset is now `max(--page-pad, 50% − rail/2 − PAGE_REM/2)`: the page is centred on what the rail leaves.
- `tests/hq.design.spec.ts` (h) and `tests/profile.design.spec.ts` (b): "the rail's top" is the bottom bar's top only when the nav is a bar (wider than tall); from `lg` the rail takes nothing off the glass's foot, so the page's limit there is the glass.

## Not done
- `src/features/command/buysell/TradeToast.tsx` still centres on the window, not on the page beside the rail (48 px off at 1280): another slice owns the file.
- The HQ's "Your earnings" card now repeats the purse the status strip shows; whether to drop it is a content call for the HQ slice.
- The fleet page's ship tile (`ShipTile`) lets "4 / 180 tons" run past its right edge at 390, before and after this pass.
