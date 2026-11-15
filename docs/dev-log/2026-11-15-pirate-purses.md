# 2026-11-15 · pirate-purses · 0429 THE PIRATE CITIES HAVE PURSES (owner row 348)

The owner, 2026-11-15: *"raise the cap more, pirates should never be laid up. allocate gold to pirate cities and hub, 10m each, port royal 30m.
they should also have like 5 cargo ship (pirates) to move gold to poorer pirate cities. port royal will be capital for pirates."*

## What production showed (read-only, 2026-11-15 02:11 UTC, head 0426, gate green: beat 119 ms, 1,005 MB)

`scripts/ops/harness/pirate-war/before-0429.sql` and `cargo-0429.sql`:

| figure | value |
|---|---|
| pirate fleets | 93; **66 laid up, all unpaid**, all of them fleets the pirates keep |
| the day's room | 0.24 % of the hoard = ~2.28 M; **2,008,500 spent by 02:11 UTC**, 270,730 left |
| Port Royal (capital, `nations.capital_port_code` POR) | 949,568,351 — the hoard is 949,679,405, so Port Royal IS the hoard (99.99 %) |
| the other eight pirate harbours | DGA 4,500 · DJE 1,962 · FLO 55,364 · GOT 2,487 · LGA 1,186 · MWY 648 · PTC 12,202 · TDC 32,705 |
| cargo ships | lit (`convoys_on`), `convoy_rich_enabled` true, class `navire`, `convoy_ships_min` 20, no pirate cargo ship |

## Why pirates are laid up

Every payment of the hoard goes through `public.pirate_pay`, which refused whenever the day's room (`pirate_spend_day_pct` of the hoard a UTC
day) was short. The hour's pay (`public.pirate_pay_hour`) marks a fleet it cannot pay unpaid; `public.pirate_ship_step` sends an unpaid fleet home
and lays it up; a wake (`public.pirate_add`) needs the room too, one a run. So once the room is spent (gifts, refits and 90 ships' pay), the
fleets are laid up one by one until 00:00 UTC, and woken one at a time after. On a 950 M hoard, a 2.3 M room was the only thing in the way.

## What 0429 does (all decided by default; the owner may reverse any)

1. **Never laid up for pay** (`public.pirate_pay`, one hunk; `public.pirate_add`, one hunk): an hour's pay (NAVY_PAY) and a wreck's refit (REFIT) are
   paid (a 0339 hull stays inside the room, as proof 106 holds) while the hoard stays at or above **`pirate_hoard_floor` 100,000,000** after the payment. That floor is the only
   stop. The day's room still bounds everything else (the gifts, the pirate merchants' foundings), and "raise the cap more": `pirate_spend_day_pct`
   0.006 -> 0.01. Every payment is still written to the day. Who pays a refit is unchanged (own purse, home, another pirate city, then the hoard).
2. **Every laid-up fleet is woken** (`public.pirate_purse_step`, called by `public.tick_pirates`, one hunk): up to **`pirate_wakes_per_run` 20**
   a minute, the fleets the pirates keep (`public.pirate_ord_wanted`), while the hoard is above its floor. 66 are back at work within four minutes.
3. **The purses, once** (`public.pirate_purses_allot`, run by the migration): every pirate harbour but Port Royal is topped up to
   **`pirate_city_purse` 10,000,000** from Port Royal. Two `treasury_flows` rows a city, new kind **PIRATE_ALLOT** (moved; feed word "Pirate purses" /
   "해적 금고"). On prod ~79.89 M moves (eight cities); nothing is made.
4. **Port Royal: 30 M.** Port Royal's purse and the hoard are ONE balance (the hoard is the pirate harbours' purses summed, and Port Royal holds
   nearly all of it), so "Port Royal 30 M" cannot be a second pot. It is kept as a floor: **`pirate_capital_purse` 30,000,000** — no cargo load takes
   Port Royal under it — and the pay stops at the 100 M hoard floor before that. After the allotment Port Royal holds ~869.7 M.
5. **Port Royal is the capital**: `public.pirate_capital()` reads `nations.capital_port_code` ('POR'). 0429 refuses to apply unless it is Port Royal.
6. **Five pirate cargo ships** (`pirate_cargo_ships` 5), home Port Royal, one made a minute (the hands every cargo ship is made by). The cargo
   ships' own machinery carries them (one authority): `public.cargo_ship_step` sails the circuit, `public.convoy_book` moves the gold (LOADED,
   DELIVERED, RETURNED), `public.cargo_ship_aboard` reads it. The circuit is `public.cargo_circuit_build` for the pirates from Port Royal; its planner
   (`public.cargo_circuit_plan`, two hunks) now takes the pirates' own harbours as stops, because the pirates keep no aiding capital. Each minute
   one idle ship at Port Royal loads what the pirate cities lack of 10 M, less what is already aboard, at most 10 M, never taking Port Royal under
   30 M nor the hoard under 100 M; at each pirate city she tops it up to 10 M (`cargo_ship_step`, one hunk); the rest comes home. A pirate cargo ship
   never takes a new home (one hunk; `convoy_rich_enabled` is on).
7. **Raidable by players, never by pirates.** She is a CARGO_SHIP: a player may attack her (`public.attack_for`; a player of the pirates' country
   is refused as his own country's). The pirates' raids (0427's `public.raid_target`) already pass over the pirates' own country;
   `voyage.freeze_raiders` names no raider for her passage (one hunk); a PIRATES day of `voyage.hazard_roll` passes her by (one hunk, read only on
   such a day).

## Rows a minute

The wake: ~20 rows a minute for four minutes, then 0. A cargo load at most one a minute (2-3 rows). Five ships on the pirates' circuit (nine
harbours) deliver ~3 rows a stop: ~+5 rows a minute. The hour's pay no longer lost to lay-ups: ~+90 rows an hour. **About +10 rows a minute
steady.** One-time: 16 `treasury_flows` rows. No job added or rescheduled, no table made.

## Proofs

- `scripts/db/proofs/130_the_pirate_cities_have_purses.sql`, 7/7 locally: with the day's room SPENT, the hour's pay reaches every fleet (and stops
  under the floor); the step wakes the laid-up (one a run at a knob of 1, then the rest); a wreck's refit is paid by the hoard; the allotment tops
  eight cities to 10 M with two rows each and the world's money unmoved; the step makes 5 cargo ships at POR, builds the circuit, loads exactly what
  the cities lack once, she sails, tops the poor city to 10 M and money is unmoved; idle at home with the rich rule lit she stays; a hunting pirate
  beside her finds no target, and her passage names no raider (a merchant's does).
- 0429's self-assert: 9 hunks once and reversing; the capital is POR; the allotment moves and never changes the purses' sum; a rolled-back tick
  of `pirate_purse_step` (on prod: wakes, makes a ship, builds the circuit, loads one — all rolled back).
- The proofs that read the bodies 0429 cuts were re-run locally (list in the PR).

## The after-check (30 minutes)

1. Gate, then `scripts/ops/harness/pirate-war/before-0429.sql` (applied false; laid_up ~66; cities under 10 M: 8).
2. +5 min `after-0429.sql`: applied true; `cities_under_10m` 0; `allot_rows` 16; `ships.laid_wanted` 0; `cargo.ships` rising to 5, `home_por` 5.
3. +30 min: `ships.unpaid` 0 after the :47 pay; `cargo.raided_by_pirates` 0; Port Royal over 30 M; beat under 1,000 ms; the gate green; no failed
   `byeharu-voyage:pirates` / `:cargo-ships` run.
4. Fail (rollback): a pirate city under 10 M an hour on with Port Royal rich; a raid on a pirate cargo ship by a pirate; a failed run; the beat over 2 s.

## Forward rollback (owner only)

Quick, no file: `pirate_cargo_ships` 0, `pirate_wakes_per_run` 0, `pirate_hoard_floor` 2,000,000,000 (every payment back under the room),
`pirate_spend_day_pct` 0.006. Whole: `scripts/ops/harness/pirate-war/rollback-0429.sql` (a draft: the nine hunks reversed, the two functions
dropped). The allotment is not taken back: it was moved gold the cities now hold.
