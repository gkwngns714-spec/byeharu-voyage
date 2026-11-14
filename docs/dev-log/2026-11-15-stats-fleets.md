# 2026-11-15 · stats-fleets · 0419 THE STATS COUNT EVERY FLEET (owner row 339)

The owner, 2026-11-15: *"in stats, show like merchants navy, pirates, anad cargo"*: on the Stats screen, the merchants, the navy, the pirates and the
cargo ships.

## What the player sees

A new Stats face, **Ships / 선박**, after Merchants. A card for each kind: how many ships and fleets; where the fleets are (one bar: at sea, in port,
laid up, wrecked; the server puts each fleet in ONE of them, so they add up); and the kind's own figures:

| kind | figures (last 24 h unless said) |
|---|---|
| Merchants | earned (the count's own 24 h, as the Merchants face), laps closed |
| Navy | fights, pirates sunk |
| Pirates | plunder (ransom and cargo-ship gold the pirate cities took), paid raids, wrecked, rebuilt |
| Cargo ships | cargo aboard (tons) and funds aboard, as they stand |

And one list, as every Stats face has: the navy by country (flag, ships, fleets) or the pirates by home. A line says when the figures were counted
(and, while the record is younger than a day, since when the 24 h figures run).

## Where it comes from (the database budget)

ONE read, `world.stats_fleets()`, of ONE small row a count: `public.stats_fleets`, written by the Stats count (`public.tick_stats`, twice an hour)
in a new phase `fleets`, kept 26 hours (about 52 rows). The read takes the newest row, the newest `stats_merchants` row (already written by the
same count) and sums the last 24 hours of the rows' windows: three index probes and at most ~52 rows, 0.05 ms locally. Nothing is scanned live, so
the face may ask every second as every Stats face does.

The count's phase reads the three small ship tables (prod 2026-11-15: 43 navy, ~10 pirate, 372 cargo rows), their fleets and ships by key, the
merchants' ships through `npc_fleets` (~943), and the window's RANSOM / LOOT rows of `treasury_flows` into pirate cities (the created_at index).

**Measured** (`scripts/ops/harness/stats-fleets/cost.sql`, the local world at production's size: 370 cargo, 40 navy and 7 pirate fleets, 916
merchant ships, every cargo ship with a hold): `public.stats_fleets_count` 28 to 35 ms a call (five calls), the whole count 235 ms locally with the
phase 32 ms. On prod the whole count takes 23.7 to 36.1 s (its last four runs, read 2026-11-15): the phase is well under 1 % of it. Writes: 1 row
and about 1 delete a count. No cron change, nothing in any beat.

## How the window figures are counted (and what is not)

- **Navy fights**: a navy ship fights at most once an hour (`public.navy_hunt_pass`), so her `fought_at` inside a 30-minute window is exactly one
  fight; `fought.result = 'SUNK'` is a pirate sunk. (A count window longer than an hour, after a missed count, could miss a ship's earlier fight.)
- **Pirate wrecks**: `wrecked_at` inside the window. **Rebuilt**: wrecks lying at the last count + wrecks since - wrecks lying now
  (`pirate_respawn_minutes` is 60: none is wrecked and rebuilt between two counts).
- **Plunder / paid raids**: the RANSOM and LOOT flows into a city the pirates hold (`public.port_nation`): one flow per ransom
  (`public.pirate_ransom`, `public.raid_ransom`) and per cargo ship's gold (`public.pirate_loot_book`).
- **NOT COUNTED, decided by default: every raid.** A raid is settled inside `voyage.settle` and written only to `voyage_events` (304,000 rows,
  35 MB on prod, no time index). Counting it would read that table each count, the kind of read 0409 took out of this job. "Paid raids" says what
  it counts: a raid driven off, or one that took only goods, is not in it.

## Prod reads (2 of 2, read only)

1. `scripts/ops/harness/stats-fleets/premise.sql`: the shape (navy 43 in 10 nations, 21 navy ships fought in the last 24 h: 14 SUNK, 7 WON; pirate
   fleets by home; the cargo ships), the sizes of the books (voyage_events 304,207 rows / 35 MB; events 91,728 / 39 MB; ledger 43,374 / 6 MB)
   and the count's last runs.
2. `scripts/ops/harness/stats-fleets/before.sql`: each of the four hunks occurs once on the live bodies (1 1 1 1), nothing of 0419 there, head 0418.

**Seen on prod:** `public.stats_runs`' newest row is 2026-11-14 16:06 UTC (read 2026-11-15). The Stats count has not written a row since; the
lead should check the `byeharu-voyage:stats` job. Until a count runs after 0419 the face says "No figures yet."

## Files

- `supabase/migrations/20260818000419_the_stats_count_every_fleet.sql`: the table (`-- retention:`), the count's figures, the read, four hunks
  (three on `public.tick_stats` with its `-- budget:` line, one registry row), self-assert with a rolled-back probe (the figures read once, timed
  under 3 s; three planted rows read back, the one 25 h old left out), the news line.
- `scripts/db/proofs/116_the_stats_count_every_fleet.sql`: SF_COUNT, SF_KEEP, SF_READ (two real counts on a world with every kind of ship).
- `scripts/ops/harness/stats-fleets/`: `premise.sql`, `before.sql`, `after.sql` (prod, read only), `cost.sql` (local scene), `rollback-0419.sql`
  (the forward rollback draft, local guard; tested: after it `tick_stats` and the registry are main's bodies to the byte).
- Client: `src/features/stats/Ships.tsx`, `StatsScreen.tsx`, `statsFaces.ts`, `src/lib/rpc/{catalog,index,types,localBackend}.ts`,
  `src/lib/i18n/dict/stats.ts`; specs `tests/rpc.surface.spec.ts` (the pin), `tests/consistency.spec.ts` (the face list).

Screenshots looked at (390x844, 320x640, desktop 1440; EN and KO; no name cut, no sideways scroll): `C:\Users\gkwng\dev\stats-fleets-shots\`.
