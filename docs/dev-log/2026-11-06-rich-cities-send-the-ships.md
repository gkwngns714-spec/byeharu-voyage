# Rich cities send the ships (W7, migration 0324, owner row 282, dark)

Owner: *"rich cities should send cargo ship (Gold carrying ships) to other low cities for support"*; *"not instantly. it should see on the map"*.

**State: built, dark, PR open, not deployed.** `convoy_rich_enabled` false. Nothing changes for any ship or city until the owner lights it (W9).

## It has its own switch, and the design said it would not need one

`docs/WORLD_POWERS.md` wrote W7 as dark when ships were dark. Ships have sailed since 2026-11-05 18:46 UTC, so anything behind `convoys_on()` would have changed live play the minute it deployed. So: **`convoy_rich_enabled`, false, read by `public.rich_cities_on()` alone**, which also needs `convoys_on()`.

- **Off, today:** the capital calls on its realm (`CROWN_CALL`) and loads at the capital. Same flows, ships, stops.
- **On:** no `CROWN_CALL` from `crown_aid` or `capital_pays`. A ship loads at her origin. The capital is a stop.
- This keeps a second path while the switch is a window. **Once the owner keeps it on, the off arm of `crown_aid` and the call in `capital_pays` die in their own slice.**

## What it does, lit

- **Origins:** the top `convoy_rich_ports` (3) of the realm by `crown_call_room`, on a course. No room anywhere: the capital. `public.cargo_origins`.
- **Ships:** made at their origin, round robin by `ord`. The 100 live ships sail there, one leg each, empty, as a real voyage on the map.
- **Load:** `min(realm need - funds aboard, crown_call_room(home))`, onto the idle ship with the most room. One ship a run, as 0309. A home that is not on the roster is a donor: `treasury_try_lock`, never waited for (0307's rule).
- **Circuit:** one per (realm, start). Same stops, from her home back to it. The capital is a stop.
- **Delivery:** every city of her realm, the capital too. **Return:** to her home.
- **Gifts:** from what the capital holds, else `GIFT_WAITING`. A founding keeps `p_must`: the world's richest harbour, so a sign-up never fails.

## W6's constraint, kept and proved

`tg_convoy_cargo_closes` wants a `RETURNED` row at the port the load left, and `voyage.npc_wreck` returns funds to `fleet_origin` from inside `voyage.settle`. A mismatch would raise inside the beat.
A load is written only at `home_port_id`, and `home_port_id` moves only in `public.cargo_rebase`, which `public.cargo_rebase_to` refuses with funds aboard. Proof 32 `RICH_WRECK`: a ship loaded at a rich city, wrecked at sea, returns there inside the real `voyage.settle`; a wreck on her way to a new home lies at that home with no book.

## Hot bodies re-cut (35 hunks, each once, each reversing)

`crown_aid` (3), `capital_pays` (1), `cargo_ships_load` (6), `cargo_ship_step` (4), `cargo_circuit_plan` (6), `cargo_circuit_build` (4), `cargo_ships_commission` (6), `tick_cargo_ships` (4), `funds_on_way` (1).

Two signatures change: `cargo_circuit_plan(nation, start, to)`, `cargo_circuit_build(nation, start)`, each with defaults, so the old calls read the same. The old signature is dropped in the same file.

Moved, same statements: `public.realm_capital`, lifted from the plan and from commissioning, so there is one copy.

New: `rich_cities_on`, `realm_capital`, `cargo_origins`, `cargo_homes`, `cargo_circuit_of`, `cargo_load_room`, `cargo_rebase_to`, `cargo_rebase`. Columns: `cargo_circuits.start_port` (existing rows take their last stop), `cargo_ships.based_at`. Knobs: `convoy_rich_enabled` false, `convoy_rich_ports` 3, `convoy_rebase_idle_days` 7. No new money kind, no cron job, no client change: the ship already shows on the map, and her card reads `home` as a code.

## Why off equals today

Every live ship has home = her capital and every circuit starts there. Then `port_nation(port) = nation` and `city_capital(port) = home` are one test, `cargo_origins` is the capital, `cargo_homes` is one row, `cargo_circuit_of` is the old read, a rebase answers `IDLE`, the roster is the old roster.

**Proved, not argued:** `scripts/ops/harness/rich-cities/dark-scene.sql` runs on the world before and after the file, convoys off and convoys lit, and all 15 lines are equal: all ten realms' plans, flows, purses, book, ships, one whole lap, an idle step, `funds_on_way`, a called gift, a waiting gift.

Dark cost: `cargo_ship_step` on an idle ship adds three indexed reads and two knob reads (about 60 ships idle a minute on prod). The job adds one read per realm. Not measured on prod.

## Measured on prod (2026-11-06, read only, head 0322)

- `convoys_enabled` true, `convoy_ships_per_nation` 10, `convoy_ship_class` `qpinnace`, `economy_closed` true, `npc_refits_enabled` false.
- 100 ships, 10 a realm, all based at their capital. At reading 35 at sea, 65 docked, 61 of those idle at home. 2,535,201 d. aboard.
- One harbour of 246 has no course, so `cargo_origins` checks for one.
- `before.sql`: all 35 hunks occur once on prod; `lap_elsewhere` 0.
- Two plans (ESP, PRT) took 947 ms together on prod. A rebase leg is the same walker with 2 stops, not 39; its time on prod is **not measured**.

**What lit would have to work with, today:**

| Realm | Short by | Top three, room | Note |
|---|---:|---|---|
| ENG | 538,628 | DUB 6.47 M, ARP 421,728, KIN 7,150 | |
| ESP | 373,745 | PLO 75.2 M, PAN 61.3 M, SVQ 47.9 M | capital is an origin |
| FRA | 317,593 | GOA 335.7 M, TOU 3,912 | **only two have room** |
| JOS | 320,542 | ZAN 271,730, MUS 109,868, JAF 7,632 | **the realm's whole room is about the need** |
| JPN | 522,597 | SAK 24.3 M, HOI 3.96 M, MAS 128,895 | capital is an origin |
| MNG | 216,591 | MAL 46.7 M, BNT 12.8 M, PTT 3.31 M | |
| MUG | 402,129 | BSR 4.02 M, KIL 2.15 M, BAS 1.81 M | |
| NLD | 390,813 | COP 125.6 M, ROT 25.0 M, VIS 7.52 M | |
| OTT | 855,209 | VLL 22.6 M, REY 10.2 M, DBR 1.51 M | |
| PRT | 541,232 | OLD 378.7 M, LIS 31.1 M, ISL 12.0 M | capital is an origin |

## Read before lighting (W9)

- **Gap at light.** Lit, the call stops at the next `:37`. A ship based at a poor capital can load nothing until she has sailed to her origin. So funds to cities stop for as long as that leg takes, up to hours, on top of the first-lap wait. Not measured.
- **A small city in the top three sends a small ship.** FRA's TOU has 3,912 d. of room: a ship based there sails a whole lap with that. The ship with the most room is always taken first, so this only happens when the rich city's ships are all out.
- **JOS:** its whole room is about its need, and the room falls as it is used. This slice cannot fix that: same nation only, per the design.
- **The first tick lit** moves every idle ship in one job run, each a plan read: about 100 ms each on PGlite, by subtraction from one tick. The job is bounded by ships, not by a rebase budget. Watch that first minute.
- `health.sh` before and after, as any change that alters live play.

## Proof

- `scripts/db/proofs/32_rich_cities.sql`: 13 markers, real `city_day`, step, job and voyage engine, economy closed, starting from ships lit at capitals as prod is. Every count reads `convoy_ships_per_nation`.
- `scripts/ops/harness/rich-cities/proof-0324.mjs`: red first (proof 32 fails with no file), dark parity equal, real file green, 31 mutations each red for its own reason; also green with 0323 applied first.
- First runs found three real gaps in the proof, all closed: a `null` slipping past `<>` hid a missing "funds on the way"; a ship at sea hid the funds-aboard refusal; "what is aboard" was not tested.
- Self-assert: catalog and stable reads only, no game step, 75 to 90 ms locally.

## Decided by default

- The switch `convoy_rich_enabled`: the design assumed dark ships.
- `crown_aid`: the design's hunk moves the branch; here a second branch sits above the call, so off stays byte for byte.
- The live ships: the design assumed none. A ship never based by the rule goes at once; after that only when her home has left the top and she has lain idle `convoy_rebase_idle_days`.
- A home already in the top keeps her ships, so ESP's ships stay at SVQ, not round robin.
- Idle is read from her last book row and `based_at`.
- Off, a ship away from her capital sails back at once.
- Her home moves as she leaves, not as she arrives, so a wreck on the way needs no second answer.
- A home that changes flag: she finishes her lap and returns the rest to that port's purse, now foreign, because the load's port is the law. Then she waits the idle days. No gold is lost. Not separately proved.
- The capital joins the roster lit, so its own need counts in the load.
- The load takes the idle ship with the most room, then the lowest `ord`.
- A harbour with no course cannot be an origin.
- A ship away from home with no lap sails home rather than raising `E_CARGO_NO_LEG` for ever.
- A circuit from a start that left the top stays until a ship needs it. Bounded by the realm's harbours.
- `convoy_upkeep_per_leg` and arms stay in W8.

## Not verified

- Anything on prod lit. Nothing here has run on prod.
- A run under real `pg_cron`: no cron change.
- A real lock contention on a donor: the busy donor is stubbed; PGlite has one session.
- The first-tick cost on prod and the gap at light, see above.
- Real-Postgres behaviour of the file: CI's disposable-chain is that proof.

## Rows for the coordinator (not written here)

**docs/OWNER_REQUESTS.md row 282:** `PART BUILT - W7 rich cities load and send, migration 0324, dark behind its own switch convoy_rich_enabled, PR open, not deployed. OPEN: W8 arms, W9 owner's switch.`

**docs/WORK_QUEUE.md, one line at the top:** `2026-11-06 **RICH CITIES SEND THE SHIPS (W7, owner row 282) - migration 0324, DARK behind its own switch convoy_rich_enabled, PR open, NOT deployed, follows 0323:** ships load at the top three cities of the realm by room, sail their circuit from there, the capital is a stop, no CROWN_CALL lit. Read before lighting: funds stop until ships reach their origins; FRA and JOS have little room. Dev-log docs/dev-log/2026-11-06-rich-cities-send-the-ships.md.`

## PROD CHECKS

- Before deploy: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/rich-cities/before.sql`. Every `times` 1, `rich_keys` 0, `start_port` 0, `based_at` 0, `rich_on` and `plan2` null, `no_start` 0, `lap_elsewhere` 0, head 0323.
- After deploy: `scripts/ops/harness/rich-cities/after.sql`. `rich_on` false, `off_capital` 0, `away_from_capital` 0, `based` 0, `no_circuit` 0.
- `bash scripts/ops/health.sh`.
