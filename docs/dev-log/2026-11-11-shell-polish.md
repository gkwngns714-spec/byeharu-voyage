# 2026-11-11 shell-polish: the two leftovers of S9

Client only, no migration. S9 (`2026-11-11-s9-shell-look.md`, "Not done") left two things as they stood before the rail and the HQ's status strip.

## 1. The trade toast centres on the page, not the window
- `src/features/command/buysell/TradeToast.tsx`: its fixed layer was `fixed inset-x-0`, the whole window. It now reads the shell's own class, `glassBesideRailClass()` (`screenLayout.ts`, THE SHELL): the window on a phone, what the rail leaves from 1,024. The same class the arrival card and the detail page stand on; no new number.
- Measured (local world, headless, a real Buy 1 on Trade):

| glass | toast centre before | after | page centre | window centre |
|---|---|---|---|---|
| 1280×800 | 640.0 | 688.0 | 688.0 | 640 |
| 390×844 | 195.0 | 195.0 | 195.0 | 195 |

  48 px off at 1280 (half the 96-px rail), 0 now. The phone did not move.

## 2. The HQ's "Your earnings" card is removed
- It was a duplicate. Both it and the status strip's purse print `useWorld((s) => s.ducats)`. Rendered before the change: at 390 the strip read `40,000 🪙` (x 296, y 4) and the card `Your earnings 40,000 🪙` (y 271); at 1280 the strip `40,000 🪙` (x 1186, y 4) and the card the same figure (x 881, y 229).
- `src/features/city/CityScreen.tsx`: the `StatCard`, the `ducats` read and prop, and two imports are deleted. `src/lib/i18n/dict/city.ts`: `earnings` deleted, EN and KO. Nothing is hidden with CSS.
- After: no `city-summary` and no "Your earnings" on any of the five places, at 390 and 1280; the strip's purse stands once.
- The side column now begins with the open place's panel (28 px + a gutter higher on a phone, 52 px + a gutter at 1280).

## Specs
- New: `tests/shell.polish.spec.ts` (both laws, at 1280×800 and 390×844; it failed on the old build for the toast at 1280 and the card at both glasses, and passes now).
- Moved, because they named the card: `hq.design` (law (e) and U3 read the panel; U3 now requires the strip's purse), `consistency` (the doors stand above the split's own box, `city-top`; the card left the frame list), `city.audit` and `drive.hq` (the card left the frame's boxes), `drive.hq` and `drive.market` (the purse before and after a purchase is read from the strip, `purse`), `city.page` (a comment).

## Not done
- The Trade desk's own leftovers (near-empty side panes, port chips at 390) are other slices; PR #578's files were not touched.
