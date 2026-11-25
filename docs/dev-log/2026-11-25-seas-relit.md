# 2026-11-25: `seas-relit`: 0514 (lights nothing), the client, proof 218

Stacked on 0513. Nothing touched production; no switch moved.

- `public.seas_relit_ready()` is the read before the light (`scripts/ops/harness/seas-relit/before-0514.sql`): the rung table and its mark; every live company, her rung, and where
  each fleet lies against it; `beyond`, `trapped`, `jobs_shut`. `public.seas_relit_light(mark)` is the only step: it refuses without the mark of the table the owner was shown.
- `public.sea_conditions_light()` (0398) is untouched and has no such guard: do not use it.
- Screen word: **Wave resistance** (R11), in the wall, Trade's tag, ships and fleets; the server's wall says it too.
- Client, only while the seas bite: the course author goes round the seas shut to a fleet (`src/lib/sea/shut.ts`; the world's grid, its straits and stored courses are untouched);
  the Seas page gives each sea's level and wave resistance and what the first fleet is short of; the map's Seas filter says under a closed sea's name what it asks (words, not a
  fill: the owner refused a fill on 2026-11-14). With no way round, the whole water is proposed and the server says which sea is closed.
- Not covered by the course author: the Route editor and the HQ board's own presses (the server's pathfinder and gate judge them all the same).
- Measured (PGlite, 16 fleets): the read 1.3 s, 79 ms a fleet, once. The beat: 0.
