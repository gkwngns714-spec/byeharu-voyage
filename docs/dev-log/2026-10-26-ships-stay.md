# 2026-10-26 — ships on the map stay drawn

Owner: ships on the map disappear for a while, then come back.

Cause: `shipMarks` kept ONE merchant per ~10.7 px cell, keyed by each ship's moving position, so ships passing
each other swapped in and out (an offline replay of the live roster, 837 fleets, hid 12-28 % of the on-screen
ships after 7.5-30 s at mid and wide zooms).

Fix (`src/chart/shipMarks.ts`): every merchant in the window is drawn. At spans >= 250 deg only
`stableSlot(id) < 6` of 8 are (FNV-1a of the id), a fact about the ship alone, so the same ships stay wherever
their neighbours sail. The `unitsPerPx` argument and `SHIP_CELL_PX` are gone.

## Measurements (headless Chromium, loaded dev PC, fixture roster, `vite preview`)

Hulls drawn at the globe, old cell rule vs all hulls: 390x844 54 -> 141; 1440x900 141 -> 218. The old rule already
drew most of the ships, so the new rule adds about 1.5x hulls, not 6x.

Wheel zoom step (`zoomStepMs`, two animation frames per step, includes every layer): 390x844 62 ms old, 120 ms
new (full roster, before the tier); 1440x900 215 ms old, 260 ms new. Per-step hull cost is therefore roughly
0.6 ms per added hull under load.

Idle (CDP `Performance.getMetrics`, 10 s windows at the globe, 1440x900): script 9-55 ms/s old (63-103 hulls),
32-80 ms/s new (173-281 hulls): about 0.25 ms of script per hull per 1 Hz tick. Whole-task time (400-1100 ms/s)
is dominated by style recalc and the atmosphere/raster layers and swings 2x run to run on this machine.

Honest limit: on this machine a frame never gets under 8 ms with or without the change (the old build's zoom
step is already 60-215 ms), so a clean "<8 ms" figure could not be measured. The tier is chosen from the hull
ratio above: the widest span (>= 250 deg) draws 6/8 so the globe stays near the old hull count; every closer
zoom draws all hulls. Retune `THIN_TIERS` from a real-device profile if the globe is slow.

Test: `tests/map.wrap.spec.ts` - two ships passing each other keep both drawn; at the thinned span the kept
set is identical before and after the move.
