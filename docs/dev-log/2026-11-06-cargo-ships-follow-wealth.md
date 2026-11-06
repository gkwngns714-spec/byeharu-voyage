# Cargo ships follow wealth (migration 0326)

Owner, 2026-11-06: *"bigger country with more cash - max 50, min 20"*, then *"the country wealth will change, so will the cargoship numbers."*

**State: built, PR open, not deployed.** There is no switch: once deployed, the job makes ships until every country has its number.

## What it does

- A country keeps 20 to 50 cargo ships by its cash: the summed `treasury_balance` of the harbours under its flag.
- `public.convoy_ships_of(nation)` is the one reader. It reads the number the country rests at (`public.cargo_fleet_sizes`). `convoy_ships_per_nation` is deleted, and no live body names it (the self-assert scans the catalog).
- `public.convoy_fleet_settle` reads the curve once an hour and moves a number only when the curve is more than 3 ships away.
- Up: the job makes ships, 10 a run, one country a run.
- Down: `public.cargo_ships_retire` lays up surplus ships, 3 a run, highest ord first. A ship at sea finishes first, and a surplus ship takes no new load, so she always gets there.

## The curve

Measured on prod 2026-11-06 (read only). Realm cash runs from 12.9 M to 4.38 B. 9 of 246 harbours (10.0 B) are under no great power and count for nobody.

| Realm | Cash | Straight | Plain log | Chosen |
|---|---:|---:|---:|---:|
| PRT | 4.38 B | 50 | 50 | **50** |
| FRA | 3.36 B | 43 | 49 | **48** |
| ESP | 2.40 B | 36 | 47 | **46** |
| NLD | 1.60 B | 31 | 45 | **43** |
| MNG | 638 M | 24 | 40 | **37** |
| OTT | 354 M | 22 | 37 | **34** |
| JPN | 295 M | 22 | 36 | **32** |
| MUG | 102 M | 21 | 31 | **26** |
| ENG | 72 M | 20 | 29 | **23** |
| JOS | 13 M | 20 | 20 | **20** |
| Total | | 289 | 384 | **359** |

**Chosen: a log, anchored.** `ships = 20 + 30 * ln(cash / lo) / ln(richest / lo)`, where `lo` is the larger of the poorest realm and richest / `convoy_ships_span` (100), and cash under `lo` counts as `lo`.

- A straight line leaves six countries at 20 to 24, because three realms hold most of the cash.
- A plain log spreads them but hangs on the poorest realm, and JOS has swung between 0 and 13 M in two days. When it nears zero every other country's number moves. Over 168 hours the plain log moved 137-219 ships a day on the same data.
- With `lo` at richest / 100, JOS falls under the floor, and only the top of the curve is the anchor. The poorest is still exactly 20 and the richest exactly 50, whatever the spread.
- All realms level: everyone 20.

## The dead band, measured

Hourly `stats_city` purses for 99 hours since 2026-11-02 (the last world change; before it the purses reset), summed by today's flags, run through the chosen curve:

| Band (ships) | Changes a country a day | Ships moved a day, world | Reversals |
|---:|---:|---:|---:|
| 0 | 1.92 | 53.6 | 37 |
| 1 | 0.99 | 48.5 | 22 |
| 2 | 0.70 | 43.6 | 17 |
| **3** | **0.39** | **32.5** | **5** |
| 4 | 0.32 | 28.6 | 5 |

**Chosen: 3.** It is the knee: reversals fall from 17 to 5, and a band of 4 buys no fewer. A number can rest up to 3 ships off the curve, never outside 20 to 50. The last 48 hours alone: band 3, no change at all.

The band was measured hourly, so the curve is read hourly (`convoy_size_read_minutes` 60). That also keeps its cost out of the other minutes: the read took 45 ms on prod.

## A ship is laid up, never deleted

`public.convoy_cargo` is append-only and its foreign key names the ship, and her house has events that are append-only too. So nothing can be deleted without breaking history. A retired ship keeps every row: `cargo_ships` with `laid_up_at` set, her house (purse 0), her fleet DOCKED at her home, her empty hull, her voyages and her book.

`public.cargo_ships_in_service` is the ships at work. `sea_houses`, `cargo_homes`, `cargo_figures`, `funds_aboard`, `cargo_ships_load` and `tick_cargo_ships` read it. `fleet_kind`, `fleet_origin`, `port_fee`, the stats tracker and `world.cargo_ship_card` still read the table: she is still a cargo ship.

A rise wakes the laid-up ship in that ord, the same fleet and house, where she lies. So an ord slot is reused, and rows are bounded: 50 ships a country, ever.

**What may retire:** ord above her country's number, DOCKED at her home, no lap, nothing open in the book, no wreck.

**A load and a lay-up cannot cross.** `cargo_ships_load` holds her row (`for update of c skip locked`). The retire holds the same row first and reads what is aboard in its own statement after.

## The job's cost: measured, projected, bounded

Prod, read only, `cron.job_run_details`, 2026-11-06:

| | |
|---|---:|
| `tick_cargo_ships`, 100 ships, 71 docked, last hour | avg 0.77 s, max 1.15 s |
| Same, 50 ships (the evening before) | avg 0.29-0.33 s |
| With 5 ships made and a circuit built | max 3.5 s |
| `compact` | avg 2.9 s, max 8.0 s |
| `arrivals` | runs its minute by design, 7 canceled of 359 before this change |

**Cost grows with docked ships, about 10 ms a step.** Ships sail only when loaded, and the loads do not grow with the ships: at most one load a realm a run, for what cities need. So the new ships would nearly all be idle.

| Ships | Docked | Unbounded, a minute | Bounded (1 idle step in 5) |
|---:|---:|---:|---:|
| 100 (today) | 71 | 0.8 s | 0.2 s |
| 359 | about 330 | about 3.5 s, max about 5.4 s | about 0.7 s |
| 500 | about 470 | about 5 s, max about 7.6 s | about 1 s |

It would fit its minute unbounded. But `convoy_rich_enabled` lit makes an idle step read every harbour of her realm for `crown_call_room` (60 ms for ESP's 39 harbours on prod), which is an estimated 16 s a minute. So this slice bounds it: **an idle ship at home steps one run in 5, by her ord** (`convoy_idle_every`). Nothing is due on an idle step but a change of home. A ship with a load, on a lap, away or wrecked steps every run as before.

The bounded column is a projection from the 10 ms, not a measurement.

**Rising:** 10 ships a run. 259 ships take about 26 runs. A run making ships will take longer than usual; from the 3.5 s above it could reach about 7 s for those 26 minutes. Not measured on prod.

**Compact and arrivals:** they scale with ships at sea, which this does not change. The sailing count should stay near today's 29.

**Rows:** about 5 KB a ship (players, fleets, ships). 259 ships are 1.3 MB; 400 are 2 MB.

## The map

- Full roster on prod: 606 KB. A docked cargo row is 329 B, a sailing one 1,054 B. 259 more docked ships add 85 KB (14 %); 400 add 131 KB. The client takes a full roster every 10 minutes.
- Delta: 43 KB for 20 s. Unchanged: an idle ship is not in a delta.
- `shipMarks`: a ship in port is not on the chart, so marks follow ships at sea, not the count. `thin` stays false.
- `tests/map.cargoload.spec.ts`, real `FleetsLayer`, headless Chromium, DPR 2, 1440x900, 800 merchants:

| Case | Marks | `shipMarks` | Paint |
|---|---:|---:|---:|
| Today, 29 cargo at sea | 629 | 0.17 ms | 55 ms |
| 359 ships, 40 at sea | 640 | 0.27 ms | 65 ms |
| Worst case, 500 all at sea | 1,100 | 0.12 ms | 110 ms |

The layer rendered alone, not the whole page. Headless paints in software.

- A new or woken ship appears, and a laid-up one goes, at the next full roster: up to 10 minutes. A delta never drops a row (`mergeRoster`).

## Proved

- `node scripts/ops/harness/fleet-follows-wealth/proof-0326.mjs`: red with no file; proof 35 green on the real file (9 markers); 21 mutations red, each for its reason.
- Proofs 18, 19, 20, 30, 32 re-cut to the new reader and green locally. They set a country's number by hand and step every idle ship.
- `scripts/ops/harness/fleet-follows-wealth/before.sql` on prod, read only: all 17 hunks occur once.

## Decided by default

- Band 3, span 100, 10 made a run, 3 retired a run, idle 1 in 5, curve read hourly.
- Laid up, not deleted. A laid-up ship stays at her home; she is not moved.
- A ship may only retire at her home.
- A surplus ship takes no load.
- All realms level is 20 each.

## Worth knowing

- **More ships do not move more gold.** A realm loads at most one ship a run, for what its cities need. Today 15 of 100 ships carry funds and 67 lie idle at home. So about 260 extra ships mostly sit in port. They are not seen on the map while they do.
- `tick_cargo_ships` takes the first short country by code. If one country's commission raised on every run, the countries after it would wait. It was so before this file, and it is warned of in the log.

## Not verified

- The load-and-retire lock across two real connections: PGlite has one connection. It is read by reasoning.
- The job on prod with this file, and the bounded projection.
- A run making 10 ships on prod.
- The 10-minute delay of a woken ship in a real client.
- The whole page at DPR 2 with 500 ships: only the layer.

## Rollback

Forward, owner only: set `convoy_ships_min` and `convoy_ships_max` to one number. Surplus ships lay themselves up and nothing strands.

W8 (0328) also cuts cargo bodies and must take its pre-images after this file. `public.cargo_ships_in_service` names its columns, so a column added to `public.cargo_ships` later must be added to it.
