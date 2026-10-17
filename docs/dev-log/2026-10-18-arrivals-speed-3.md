# 2026-10-18 — 0166: the chart is unrolled once a reading — `osn-arrivals-3`

**Symptom (prod, read-only `cron.job_run_details`):** `byeharu-voyage:arrivals` (every 15 s, 10 s budget)
averaged 2.5–2.8 s an hour through 14:00 UTC on 2026-10-17. It then rose: 2.75 s (15:00), 3.19 s (16:00),
3.97 s (17:00 and 18:00), 4.45 s (19:00), 4.43 s (20:00), and 4.9–6.0 s after 0160–0163 (21:15–21:40).
The max sat at the 10 s budget.

**Where the line moved: load, not per-arrival cost.**

| hour (UTC, 10-17) | 06–14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|
| merchant laps started | 735–795 | 767 | 963 | 1136 | 1257 | 1377 | 1403 |
| distinct routes sailing | 314–352 | 320 | 407 | 497 | 543 | 614 | 645 |
| sweep seconds per closed stop | 0.34–0.37 | 0.29 | 0.27 | 0.29 | 0.27 | 0.26 | 0.29 |

- 0150 (stuck laps answered) and 0152 (wrecks towed) put about twice as many merchants back to sea. That is legitimate load.
- I regressed each run's time on what that run did, over 1,296 runs since 15:30 (r² 0.68). The fit is ≈ 0.76 s a run
  + 0.012 s an arrival + 0.0106 s a sea-day + 0.38 s a lap start.
- Lap starts alone, over 5,450 runs since 2026-10-16 22:00: 0.42–0.46 s each before 15:00, 0.37 s after. Per-unit cost did not rise.
- The hourly reconcile and the drift are not the cause. Runs overlapping them average 4.6–7.1 s, but 51 of the 54 budget-length
  runs since 15:00 overlapped nothing.
- I timed today's K/S lookups per call on 200 merchant fleets, read-only. All are small:
  - `world.ship_stats` 0.44 ms
  - `public.crew_pct` 0.45 ms
  - `fleet_wage` 0.30 ms
  - `day_delay_for` 0.06 ms
  - `storm_hull_lost` 0.44 ms

**Where a run's time goes.** I profiled one sweep on a merchants-on PGlite world with `track_functions = 'all'` (200 fleets,
1,755 sea-days, 185 departures). `voyage.segments_from_course` and `voyage.path_refusal` took 36–38 % of it. Each is called
once per departure, by `cmd.do_sail`. On prod, read-only, over 100 merchant stop courses: **107 ms** and **43 ms** a call.
That is about 150 ms of chart reading for every SAIL, or about 2 s of a 5 s run at ~13 departures a run.

**The cause.** `public.sea_raster.cells` is 259,200 bytes stored compressed (`pg_column_size` 14,684). Both functions, and
`voyage.water_roadstead`, read it into a record and then call `get_bit(r.cells, …)`. A compressed value held in a PL/pgSQL
record stays compressed, so every `get_bit` decompresses the whole chart again. On prod, 1,000 `get_bit` calls on the column
took **152 ms**. The same calls on the bytes unrolled once (`cells || ''::bytea`) took **2.5 ms**.

**Fix (migration 0166, provisional number).**
- Each of the three bodies gets one hunk: `r.cells := r.cells || ''::bytea;` right after the raster is read. The bits are the same, uncompressed.
- The hunks are sliced from production's live bodies (head 0163, read-only `pg_get_functiondef`), and each is asserted to occur once.
- Nothing else moves: no rule, table, storage, ACL or entry point.

**Self-assert.** Old copies under `pg_temp`, compared with the new bodies as text:
- `segments_from_course`: 94 courses (88 live merchant stop courses, the longest and antimeridian ones among them, plus own inland, antimeridian,
  ocean, polar, one-point and zero-length courses). The inland one raises, and the raise is compared too. 811 segments, 3 shelter classes.
- `path_refusal`: 194 calls (163 legal water, 21 `E_LAND`, plus `E_BAD_PATH` and `E_OFF_COURSE`).
- `water_roadstead`: 338 points (every port, plus a world grid): 114 on water, 210 searched, 14 with no water near.
- Each body reverses to its pre-image. ACL, owner, volatility, definer and config are unchanged. No other body probes the chart. No new entry point.

**Measured locally** (cached-prefix image build: 155 of 156 restored, 1 applied in 31.9 s; the `0166 self-assert ok` receipt printed). Timings on PGlite:
- `segments_from_course` ×88: 7,004 → 135 ms (−98 %)
- `path_refusal` ×88: 2,934 → 302 ms (−90 %)
- `water_roadstead` ×252: 265 → 52 ms (−80 %)

The same merchants-on sweep, from the same saved world, took **35.1 s before** and **23.9 s after** (−32 %). It ended in the same state
(194 sailing, 4,992 voyage events, 323 laps, 564 reports).
`npm run build` (tsc + vite, image reused) and `npm run lint` passed once each.

**Expected on prod (not measured; verify after the push):** about 150 ms → a few ms per departure. At today's ~3,100 departures an hour,
that is ≈ 450 s of the sweep's ≈ 1,100–1,200 s an hour. The 20:00 load would drop from 4.4 s to ≈ 2.6 s; the 21:xx load from 5.5 s to ≈ 3.2 s.
The max should fall with it, because a lap-start burst carries its departures.

**Left, and the next levers if the average stays above 3 s:**
- A lap start's planning (`npc_leg_lines`, about 0.2 s a lap start on prod after this file).
- The hazard roll's `voyage.days_complete` walk inside `voyage.progress_nm`: 2 ms a sea-day on prod, quadratic in the day number.
- The candidate scan's per-voyage `day_ends_at`: 132 ms a run.

**Not done:** merge, `db push`, or any production write. The number moves to head + 1 at deploy (K9 0164 and S17 0165 are in flight).
This file deploys first.
