# 2026-10-18 — a ship's panel stands over her fleet's tray on a phone — `osn-ship-panel-over-tray`

**The defect.** Map → press a fleet → press one of her ships: on a 390 px phone the ship's panel
(`src/live/ShipPanel.tsx`, `Tray mode="side-next"`) opened BEHIND the fleet tray (`VoyageTray.tsx`,
`Tray mode="side"`) — mounted, but invisible and unpressable. Predates 0157; the owner saw only
the fleet tray after the press.

**The cause, one line.** `src/components/ui/Tray.tsx` orders the two side panels with
`mode === 'side-next' ? 'z-30' : 'z-40'`: the second panel one layer UNDER the first. That is the
desktop shape — from `lg` the ship's panel stands to the fleet tray's LEFT (`traySideNextClass`,
`right-[39rem] w-[26rem]`) and slides out from under its edge (`lg:bv-slide-out-left`), so the
layer only matters during the slide. Below `lg` (PR #134, `screenLayout.ts`) BOTH panels cover the
whole width at the same right edge, so the layer alone decides which one is seen, and the desktop
order put the one opened last underneath. The two are fixed SIBLINGS (`VoyageTray.tsx` renders
`<ShipPanel>` after `</Tray>`), so no stacking context of the parent saves it. The same line
ordered `TradeHistoryPanel` (also `side-next`, from the fleet tray and the merchant sheet) the same
way.

**The fix.** That one line: `'z-50 lg:z-30'` for `side-next`. Below `lg` the second panel is on
top; from `lg` nothing changes (the proof measures it). No per-panel z-index, no layout change —
pressing a ship still SELECTS and the fleet tray stands where it was; closing the ship's panel
gives it back as it stood (`onClose` → `setOpenShipId(null)`, unchanged).

**The proof.** `tests/map.shipPanel.spec.ts` (new): map → fleets corner → her row → `tray-ship` →
`map-ship-panel`, then asks the BROWSER which tray a finger lands on (`document.elementFromPoint`
at the panel's centre and at its ✕, resolved to the nearest `[data-tray-mode]`) — never a class
name, since a z-index read off the DOM passes a panel still covered in another stacking context.
- 390×844: the panel covers the glass, is the topmost tray at its centre and its ✕, its ✕ takes a
  real press (Playwright refuses a covered control), and after it the fleet tray is the topmost
  tray again with her ship row visible.
- 1280×800: the fleet tray at the right edge, 39 rem; the ship's panel 26 rem, its right edge on
  the tray's left edge (±1 px); each topmost at its own centre; close returns to the tray.

Driven on a local PGlite build (no `.env.local`, worktree `~/dev/bv-stack`, `vite preview
--port 4220` via `localhost`):
- unfixed bundle: **1 failed** (phone: `Expected "map-ship-panel", Received "map-detail-tray"`),
  1 passed (wide), 0 skipped — `before-390.png` is that run's frame: the fleet tray alone after the
  ship was pressed;
- fixed bundle: **2 passed**, 0 failed, 0 skipped — `ship-panel-390.png`, `ship-panel-closed-390.png`,
  `ship-panel-1280.png` in `docs/dev-log/2026-10-18-ship-panel-over-tray/`.

Gates: `tsc -b` (in `npm run build`) clean, `eslint .` clean, the spec once red on main's bundle and
once green on the fix. CI on this PR selects every browser spec (rule A: `src/components/ui/**`).

**Not done.** The merchant sheet's own `side-next` panels (`TradeHistoryPanel`, her ship) are fixed
by the same line but not separately measured here; `map.merchants.spec.ts` asserts the merchant's
ship panel `toBeVisible` at 390, which does not see layering.
