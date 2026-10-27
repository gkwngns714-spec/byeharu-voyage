# 2026-10-27 — The arrivals beat does less work for the same answers (`osn-arrivals-trim`, migration 0250)

Follows `2026-10-27-arrivals-gaps.md` (0248). The goal: beat p95 under 1 s, with the same game results.

## The finding (prod, read-only, head 0248)

`public.arrivals_beats`, 30 min to 12:32 UTC: 1,635 beats (54.5 a minute), p50 0.39 s, p95 1.82 s, max 11.7 s, 0 errors.

- **Departures make the p95, not the cold seconds.** A least-squares fit over 1,494 beats (seconds 6-59), joined to the
  voyages that departed in each beat's second: ~32 ms a sea-day, **~214 ms a departure** (an arrival whose route sails
  on: lap closes and opens, the stop's lines, sells, buys, supplies, the sail).
  - Beats with no departure: p95 **0.62 s**. Beats with a departure: p95 **2.06 s**.
  - Cold seconds (0-4 of each minute): p95 2.16 s. Warm (15-59): p95 1.81 s. So a longer loop would gain little, and
    it cannot be longer anyway (below).
- **Mostly CPU.** 30 samples of the beat's backend in `pg_stat_activity`: 15 asleep between beats, 11 on CPU,
  3 in `IO: DataFileRead`.
- **Prod is ~2.5× slower than PGlite per reader call.** The same STABLE readers timed on prod, read-only (CLI wall
  time minus a baseline query): `wc_num` 25 µs, `crew_pct` 1.1 ms, `endurance_days` 1.6 ms, `ship_stats` 0.8 ms,
  `fleet_speed` 5.3 ms. Locally: 14 µs, 0.41 ms, 0.63 ms, 0.46 ms, 1.1 ms.
- **The disk reads are standing_route_laps.** 162,580 rows, 215 MB (200 laps kept a route). In one 19 s window,
  1,168 heap blocks a second were read from outside shared_buffers (256 MB for a 2.2 GB database), almost all from
  this table. Plain `EXPLAIN (GENERIC_PLAN)` on prod: `max(started_at)` of a route reads all ~195 of its laps,
  `max(closed_at)` walks the `closed_at` index backward through other routes' laps, the old orders' delete reads all
  ~195 lap ids, the trades' fade reads all ~195 laps to find the few that still carry trades.
- `pg_stat_user_tables` over 70 s: `goods` read whole 35 times a second, `skills` 44, `skill_effects` 33,
  `class_profile` 62.

## The cause, from a local profile

PGlite, head 0248 + prod's knobs, 835 merchants at sea (`npc_traders_switch`), the clock run second by second in one
session. `track_functions = 'all'` for the profile; the timings below are measured with it off.

- `public.crew_pct` computes all of `public.crew_terms` (a 12-table join, a function call per row) for every question,
  then keeps one effect. Most questions are about an effect no seated captain of that fleet bears, and the answer is 0.
- `voyage.ship_speed_at` reads `world.ship_stats` twice (hold, then speed) for every hull it weighs.
- `supply_needs`, `supply_reach`, `npc_provision_for` and `fleet_load` read `ship_hold_capacity` twice per hull
  (each read is `ship_stats` + `crew_pct`).
- `ship_speed_at` and `ship_cargo_tuns` weigh a hold by joining every good. `house_skill_scopes` reads every skill and
  every skill effect to find the few the house holds.

Diagnostic arms, to weigh each part (not shipped): `crew_pct` always 0 → −23 %; `ship_stats` a constant → −19 %;
`wc` inlined → −9 %. `wc` stays as it is: it is ~4 µs a call, and making it cheaper means dropping its
`SECURITY DEFINER` / fail-closed shape (the one knob reader).

## The fix (0250)

Eleven hunks in eight bodies. Each answers the same STABLE question from the same snapshot:

1. `crew_pct` computes `crew_terms` only when a captain seated in the fleet (on `p_ship`, for a ship effect) has an
   active trait or a job that bears `p_effect`. Those are `crew_terms`' own joins, both arms. With none, the sum is 0,
   exactly as before.
2. `ship_speed_at` reads `ship_stats` once. It keeps `ship_stat`'s own refusal text if hold or speed is missing. Each
   good's bulk is looked up by its key.
3. `ship_cargo_tuns` looks each good's bulk up by its key. An unknown key weighs nothing, as the inner join dropped it.
4. `house_skill_scopes` starts from the house's own skills. Same set, `array_agg(DISTINCT)`.
5. `supply_needs`, `supply_reach`, `npc_provision_for`, `fleet_load` read `ship_hold_capacity` once a hull
   (`LATERAL … OFFSET 0`, so the planner cannot pull it back up and call it twice).

Three indexes on `standing_route_laps`: `(route_id, started_at) INCLUDE (id)`, `(route_id, closed_at) WHERE closed_at
IS NOT NULL`, `(route_id, lap_no) WHERE trades IS NOT NULL`. Checked locally on 162 k synthetic laps (837 × 195): the
generic plans of all four queries use them (index-only scans backward for both `max`es).

Not done, decided by default:
- **No cache across statements.** Every answer is still read when it is asked.
- **The arrivals loop stays one minute.** pg_cron's CALL runs under the server's 120 s `statement_timeout`, and a COMMIT
  inside the procedure does not reset it. A two-minute loop would lose its last seconds or be cancelled, and the cold
  seconds are not what makes the p95.

## The proof

**Self-assert (in the file).** The old bodies are kept as `pg_temp` copies. Old and new answer the same questions:
`crew_pct` for every effect on 40 seated and 15 unseated fleets (each hull for a ship effect, a good for
`category_spread`, refusals compared as refusals), `ship_speed_at` at four fills, `ship_cargo_tuns`,
`house_skill_scopes` for every house and every hull, `supply_needs` at six distances, `supply_reach`,
`npc_provision_for` at two lengths, and `fleet_load` in its own rolled-back block (what went aboard, every hull's
cargo and basis). This runs three times:
- on the database as it stands;
- on a rolled-back probe where the hulls carry cargo (a good, a second good, and a key that is no good) and the seated
  captains have taken up every trait they hold, plus a few they do not;
- on crew_terms' other arm: `crew_bite` turned the other way and the probe captains' traits put down, rolled back.

Every answer must be identical.

- Local, fresh chain: 3,111 + 3,111 + 834 questions, 0 different. 41 crew answers above 0, 439 seated questions skipped,
  `fleet_load` put 5,042 aboard alike.
- **Negative controls:** each one was broken on purpose and the assert went red:
  - crew_pct's active-trait arm (caught by the planted traits);
  - its job arm (caught by the other arm);
  - `ship_speed_at`'s hold;
  - `house_skill_scopes`' scope filter;
  - `fleet_load`'s free room;
  - `ship_cargo_tuns`' unknown-key rule.

  One mutant passed and is equivalent: `supply_needs`' `full` term. `stores_topup` reads `p_full` only when `p_days` is
  null, and `supply_needs` never passes a null day count.

**End to end (scratch harness, not in the file).** 60 beats of the clock from three starting points. Old bodies and new
ran from the same state in one transaction, savepoint per arm. The digest was every row of all 128 public tables, with
uuids blanked, sequence and clock columns dropped, and probe voyage ids made deterministic.

| start | fleets | sea-days | arrivals | departures | sells | buys | tables different |
|---|---|---|---|---|---|---|---|
| +30 s | 855 | 841 | — | — | — | — | 0 |
| +200 s | 1,070 | 1,745 | 507 | 441 | 344 | 267 | 0 |
| +500 s | 1,035 | 2,835 | 703 | 672 | 515 | 358 | 0 |

The same run against itself is the control: 0 different at 60 beats. Past ~90 beats both the control and the pair differ
the same way: two merchants buying the same good in the same second swap order, because ties follow the heap's order.

## Measurements

Local (PGlite, the same 120 beats from the same state, old vs new interleaved A B A B, each arm rolled back):

| | old | 0250 bodies |
|---|---|---|
| 120 beats, total | 4,847 ms | 3,912 ms (**−19 %**; −19 to −25 % over four runs) |
| beat p95 | 141 ms | 109 ms |

Part by part: `crew_pct` skip −13 to −15 %; `ship_speed_at` −5 %; `house_skill_scopes` −3 %; hold once −5 %.
PGlite holds no 215 MB laps table, so the indexes are measured on prod after.

Prod before: see the finding (30 min to 12:32 UTC: p50 0.39 s, p95 1.82 s). The 0248 dev-log's window
(09:24-09:40): p50 0.38 s, p95 1.46 s.

## Deployed and after-check

Deployed 2026-10-27 14:16:52 UTC (PR #363, push landed at head 0250, merged, main Acceptance green on 8a3a3e3).
On prod: the three indexes exist and the eight bodies carry the 0250 cut. No failed cron runs after the deploy.

`public.arrivals_beats`, 15 min each side (the first ~2 min after the deploy, the backlog, left out):

| | before (13:58-14:13, after 0249) | after (14:19-14:34) |
|---|---|---|
| runs a minute | 53.2 | 56.5 |
| failures | 0 | 0 |
| p50 | 417 ms | **368 ms** |
| p95 | 2,038 ms | **1,698 ms** |
| max | 8.7 s | 9.3 s |
| runs over 1 s | 147 (18 %) | 131 (15 %) |

The same fit as in the finding (pre: 13:50-14:13, 1,134 beats; post: 14:19-14:37, 855 beats):

| | per sea-day | per departure | mean beat | p95, beats with no departure | p95, beats with a departure |
|---|---|---|---|---|---|
| before | ~26 ms | ~155 ms | 604 ms | 620 ms | 2,142 ms |
| after | ~15 ms | ~157 ms | 532 ms | 524 ms | 1,916 ms |

**The goal (p95 < 1 s) is NOT met.** Sea-days got ~40 % cheaper. The mean beat dropped 12 % and the p95 17 %. A
departure still costs ~155 ms on prod, and the beats with a departure still set the p95.

Next slice, not started: the departure path itself. Locally, `cmd.standing_route_lines` costs ~4 ms a stop and
`cmd.do_sail` ~13 ms. `world.quote_terms` calls `spread_effective` twice for every quote (with and without the
bargain), and each call asks `crew_pct` twice.
