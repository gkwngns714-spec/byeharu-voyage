# 2026-11-11 S4: the type-and-surface pass (rows 309, 310)

One pass in the tokens (`src/index.css`) and the nav primitive (`src/components/ui/Nav.tsx`), so every screen moves together. No feature screen was edited.

## What changed
- Type: the eight token names land on six sizes, not eight. caption 12 -> 13 (line 16 -> 18), label 14, body 16, title 20, card 18 -> 20, figure 24, hero 34 -> 28, page 30 -> 28 (line 32).
- Ink, night: ink-muted #a9b3c0 -> #b6c0cc (9.32 : 1 on surface). ink-faint unchanged: the chart is mixed from it and the map must not move.
- Ink, day: ink-faint #6b7280 -> #5b6472 (was under AA on surface-2 4.42, bg 4.30, sea-1 3.88; now 5.47, 5.32, 4.80).
- Nav from `lg`: cells 7 rem each, centred on the band; the band keeps its 56 px, so every `bottom-14` tray is unchanged.

## Why not the four steps 14 / 16 / 20 / 28 (tried first, measured, rolled back)
- caption 14: "Merchants" stood 4 px on its neighbours in the Stats tabs at 320 (tests/stats.design.spec.ts, 51-px segments).
- figure 28: a Row's cells share one 24-px line (`.bv-row-line`); a 28-px figure pulled the shipyard's Damage row 4.5 px and a gallery stat line 10.5 px off true (tests/align.spec.ts, 2-px law).
- title line 28: the Menu tray scrolled 2 px inside itself at 320x640 and 1280x800 (tests/nav.geometry.spec.ts), because NavBar's tray floor counts a 26-px head.
With the final values: nav.geometry, primitives.geometry, command.design, align, wide.layout, stats.design, fleets.design: 57 passed locally (local world).

## Measured (local world, DPR 2, headless; visible text nodes by computed size)
390 Fleet detail: before 12 px x40, 14 x8, 16 x13, 20 x1, 24 x5; after 13 x40, 14 x8, 16 x13, 20 x1, 24 x5.
1280 Command: before 12 x40, 14 x13, 16 x41, 18 x1, 24 x2; after 13 x40, 14 x13, 16 x39, 20 x1, 24 x2.
No screen shot (HQ hall, HQ market, its tray, Fleets, Fleet detail, Command, its buy tray, Map, Stats, Menu; 390 and 1280; dark and light) scrolls sideways, before or after.

## Not done, and why
- A left rail: the Menu tray hangs off the bar in `src/app/NavBar.tsx` and every docked tray stops `bottom-14` above the bar (`screenLayout.ts`); a rail is a shell change.
- Card padding and content width: set in `Card.tsx` / `screenLayout.ts` / the detail page, not in tokens.
- Command's port chips (`src/features/command/buysell/TradeBoard.tsx`, `city-chips`): four columns at 390 leave 41 px for a name. "Setubal" and "Sanlucar de Barrameda" already broke mid-word at 12 px; at 13 px "Lisbon" does too. The fix is the grid (three columns on a phone), in a file another slice owns.

Hard-coded sizes outside the scale: `src/components/ui/typography.ts` fineClass `text-[11px]` (1 caller), `src/components/ui/Rarity.tsx:52` `text-[10px]`, `src/live/ShipPanel.tsx:213` and `src/live/TradeHistoryPanel.tsx:331,366` `text-[0.6875rem]`.
