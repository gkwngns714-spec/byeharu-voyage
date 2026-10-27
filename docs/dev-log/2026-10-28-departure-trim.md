# 2026-10-28 — A departure reads each quay once (`osn-departure-trim`, migration 0256)

Follows `2026-10-27-arrivals-trim.md` (0250). The goal: beat p95 under 1 s, with the same game results.

## The finding (prod, read-only, head 0252/0253)

`public.arrivals_beats`, 30 min to ~15:00 UTC 10-27: p50 0.33 s, p95 1.72 s, 15 % of beats over 1 s, 0 errors.

- **Fit by what each beat wrote** (events at the beat's instant; 1,282 beats, seconds 5-59): ~167 ms a DEPARTED,
  ~141 ms a SOLD, ~89 ms a BOUGHT, ~119 ms a ROUTE_LAP, ~7.5 ms a sea-day. R² 0.57, residual sd 406 ms: two beats with the
  same work can differ by half a second. Beats of 0.6-1 s and 1-1.5 s carry nearly the same work (2.3 vs 2.5 departures,
  13 vs 11 sea-days).
- **The beat is mostly CPU.** 24 samples of its backend: 13 asleep between beats, 9 on CPU, 2 `IO: DataFileRead`.
- **Readers timed on prod** (600 calls each, CLI wall time minus a baseline): `world.quote_terms` 4.6 ms,
  `world.spread_effective` 1.8 ms, `world.spread` 0.7 ms, `voyage.fleet_speed` 2.7 ms, `public.crew_pct` 0.57 ms,
  `public.wc_num` ~40 µs, `cmd.standing_route_lines` ~18 ms a stop. 511 captains are seated, so crew_pct often computes
  `crew_terms`.
- Also seen: the 0251 deploy cancelled the arrivals minute at 14:49:26 and skipped 14:50; its backlog made 2 minutes of
  10 s beats. The stats job's minutes (:06/:21/:36/:51, 50-85 s) run at p95 2.8 s. Neither is in this slice.

## The cause, from a local profile

PGlite, head 0252 + prod's knobs, 835 merchants at sea, the clock run 200 s, then each next departure (port wake) and each
next arrival (settle) timed alone and rolled back, with `track_functions` for the counts.

- A SAIL (~17 ms): `voyage.fleet_speed` 5 times (sail_refusal ×2, supply_needs, do_sail, depart); `world.ship_stats`
  6.4 times; insurance ~3 ms.
- An arrival (~33 ms): `cmd.standing_route_lines` ~8 ms (supply_need ~47 %, quotes ~35 %), the sells and buys.
- `world.quote_terms` calls `world.spread_effective` twice (with and without the bargain). Each reads the port's spread,
  two `crew_pct`, her house and the investors' shave. Measured alone: making it one call saves ~8 % of an arrival.
- `cmd.standing_route_lines` asks the quays' terms again for every merchant BUY line: the next stop's (world.quote), this
  stop's (npc_buy_ceiling), and this stop's again on every step of npc_affordable (up to 12). With no fleet named they are
  the port's own, the same for every good (0169), and npc_buy_ceiling / npc_affordable / quote_priced already accept them
  handed over (npc_plan, trade_routes do this).
- `cmd.do_sail` reads `voyage.fleet_speed` for her report's `voyage_days`; `voyage.depart` reads it again on the next line,
  with nothing written between.

## The fix (0256)

- `world.spread_effective_pair(port, good, fleet, with_bargain)` (new, private, stable, definer, as spread_effective):
  spread_effective's arithmetic moved whole. It answers both spreads from one reading; the no-bargain answer keeps the
  bargain at its 0, exactly as `spread_effective(..., false)` did. `world.spread_effective` reads its first answer.
- `world.quote_terms` reads both spreads from one call of it.
- `cmd.standing_route_lines` reads both quays' terms once a stop (at the first merchant BUY) and hands them to
  `world.quote_priced`, `public.npc_buy_ceiling` and `public.npc_affordable`.
- `cmd.do_sail` takes `v_speed` from `voyages.speed_profile[0]`, the speed `voyage.depart` froze (jsonb keeps the numeric's
  scale, so `voyage_days` is the same).

Seven hunks in four bodies, sliced from the live bodies, each reversed in the self-assert. No signature, grant, knob,
flag or client read changes. `world.quote_priced` (E6 / E6b re-cut it), `voyage.depart`, `voyage.sail_refusal` untouched.

## The proof

**Self-assert (in the file).** The old bodies are kept as `pg_temp` copies (the old quote_terms reading the OLD
spread_effective). Old and new answer:
- spread_effective (both bargains) and quote_terms, for 16 seated, 6 unseated and no fleet, on 8 quays × 5 goods;
- the lines of 120 routes at every stop (489 stops, 518 merchant BUYs);
- all of it again on a rolled-back probe where the seated captains take up every trait they hold (144) and every probe
  house strikes a bargain on every probe quay and good (one at 0.0000, the rest 0.0400);
- 40 pending SAILs, each in its own rolled-back block with her port time waived: the answer, her voyage row, fleet,
  ships and the events she wrote.

Local: 3,249 + 3,249 questions (240 / 416 spreads shaved by a purser or trader, 880 quotes moved by the bargain),
40 SAILs (40 sailed), 0 different. ~45 s on PGlite.

**Negative controls**, each broken on purpose, went red: the pair's no-bargain answer using the bargain (880 bad);
quote_terms' q_nohag := q_spread (880 bad); npc_affordable handed the next stop's terms (61 bad); quote_priced handed this
stop's terms for the next stop (176 bad); do_sail's speed ×1.01 (a SAIL differs). One mutant passed: speed + 0.0001. It
moves `voyage_days` (rounded to 0.01) in none of the 40 SAILs; that number is the only place do_sail's own speed goes.

**End to end (scratch harness, not in the file).** 60 beats of the clock from three starting points, both arms in one
transaction, savepoint per arm. Arm A = this file, then the pre-images put back and the pair dropped (so both arms carry
the same probe writes); arm B = this file. Digest: every row of all 129 public tables, uuids blanked, voyage ids from a
sequence. In the harness only, both arms break the clock's ties by id (`tick_arrivals` by eta, fleet; `port_time_wake` by
ready_at, id): without it even the same file against itself differs (two merchants with one eta swap order after the first
arm's rollback). Same as 0250's note, sooner on this world.

| start | fleets | sea-days | departed | sold | bought | tables different |
|---|---|---|---|---|---|---|
| +30 s | 855 | 841 | 14 | 40 | 32 | 0 |
| +200 s | 1,078 | 1,753 | 444 | 354 | 272 | 0 |
| +500 s | 1,029 | 2,816 | 671 | 510 | 355 | 0 |

Control (A against A at +200): 0 different. Negative control (B with npc_affordable handed the next stop's terms):
13 tables differ.

## Measurements

Local (PGlite), old vs new bodies, each departure / arrival / stop rolled back, min of two passes, two rounds:

| | old | 0256 |
|---|---|---|
| a SAIL (80 port wakes) | 16.7-17.5 ms | 15.0 ms (−10 to −14 %) |
| an arrival (80 settles) | 32.9 ms | 29.6-30.3 ms (−8 to −10 %) |
| a stop's lines (200 routes) | 4.33-4.38 ms | 2.92-3.40 ms (−22 to −33 %) |
| 120 beats from +200 s, A B A B ×4 | 30.1 s | 29.4 s (−2.4 %) |

Locally the whole beat is dominated by sea-days; on prod the fit puts most of the cost on departures, sells and laps.

Prod before: see the finding (p50 0.33 s, p95 1.72 s, 15 % over 1 s).

## Deployed and after-check

Pending: deploys after 0255 (E6b) is on prod.
