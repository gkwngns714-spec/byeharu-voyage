# 2026-11-05 - The harbours have their islands (migration 0319, number set at deploy)

Branch `islands-on-the-chart` · migration `supabase/migrations/20260818000319_the_harbours_have_their_islands.sql` · owner row 297, which reopens row 92.

## The order
Row 92: *"some cities are in the ocean, not on land such as istanbul. I want you to fix it."* Reconfirmed 2026-11-05: *"some cities are in ocean, they are meant to be like that yes?"* Row 41: the fleet never touches land.

## What was wrong
28 harbours stood on islands the Natural Earth 110m file has no polygon for. Each was drawn in water, on a 4 px speck.

## What was done
- `scripts/build-world.mjs` adds those 28 islands from the 10m sheet, and nothing else: the 177 old features are byte-identical. Decimated once at 0.015 deg, marked `HARBOUR_ISLAND`.
- `src/chart/coastlineBuild.ts` draws a marked ring point for point. `scripts/sea-grid.mjs` closes every raster cell the same points touch. A row's centre line could miss a small island altogether, so scan-fill alone would have drawn land fleets sail through. `tests/map.islands.spec.ts` holds the two together.
- The islet speck is removed: nothing is stranded, so it was dead code. `landfallPorts` now returns the list.
- A closed cell keeps its `sea_cells` name, as ICE does: most of the cell is still water and nobody sails it. Decided by default. It leaves `sea_cells`, `sea_zone_cells` and `region-tint.json` alone.

## Measured
| | Before | After |
|---|---|---|
| Harbours stranded in drawn water | 28 | **0** |
| Harbours whose mark moves onto the shore | 53 | 55 (Santa Cruz 0.08 nm, Banda Neira 1.69 nm) |
| Land file | 280,378 B, 97.9 KB gzip | 292,884 B, 101.7 KB gzip (+12.5 KB, +3.8 KB gzip) |
| Rendered coast path | 78.9 KB | 85.5 KB |
| JavaScript total | 22,886,619 B | 22,886,032 B (-587 B) |
| Water cells | 545,972 | 545,790 (182 closed, 0 opened) |

**Routes** (every one of the 33,670 pairs among 260 places, old water against new, both by today's pathfinder):
- 0 pairs unreachable.
- 12,359 pairs change, mean +7.83 nm, widest +169.6 nm (Hadibu to Kupang) and -257.8 nm (Aden to Darwin, a straightener tie, not a new way).
- A pair takes the new figure only if the two measures differ at the tenth. Among the 246 harbours, 6,459 changed pairs have an island harbour at one end and 5,050 do not.
- Chios to Rhodes is the sharpest in proportion: 162.6 to 247.3 nm.
- 28 roadsteads move 8.2 to 29.2 nm off their quays (table in the migration header). Zanzibar is the widest, 29.2 nm.

**Stored courses** (world image, 3,302 stops, 1,043 merchant courses, 1,036 distinct): 320 mended; every leg then passes `voyage.path_refusal` against its own ports' roadsteads, 0 refused; 0 enter a drawn island, walked at 0.005 deg. Merchant course length: mean +7.76 nm, widest +104.4 / -30.2 nm.

**Prices:** 41,094 of 154,734 market rows take a new haul, mean 0.083 %, widest 2.04 %.

**Migration time:** 102 s on PGlite, of which the mend is 93 s. World guard passes on the result. The rollback returns the raster, reaches, stops, merchant courses, hauls and asks to byte-identical pre-images (`scripts/ops/rollback-islands-0319.sql`).

## Known limit, not fixed
The approach rule lets a course's last 21 nm (client) or 25 nm (server) skip the land check, so a freshly plotted course can clip the corner of its OWN harbour's island. Measured over all harbour pairs: 81 of 30,135 (Rhodes 67, Ponta Delgada 11, Banda Neira, Male and Torshavn 1 each). No course crosses any OTHER island. It is the rule every mainland harbour already sails by; changing it moves every course in the world and is its own slice.

A voyage at sea when this deploys keeps her frozen course and docks on her ETA, so she may cross an island once.
