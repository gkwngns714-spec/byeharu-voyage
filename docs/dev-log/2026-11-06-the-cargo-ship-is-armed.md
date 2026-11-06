# The cargo ship is armed (W8, migration 0328, owner row 283, dark)

Owner: *"cargoship should have defense and attacking power too"*.

**State: built, dark, PR open, not deployed.** `convoy_armed_enabled` false. No ship or city changes until the owner lights it.

## It has its own switch, because ships already sail

`docs/WORLD_POWERS.md` section 3.2 wrote this as a change of `convoy_ship_class` when no ship existed. 100 crewless `qpinnace` sail today, so that would have been live. So:

- **`convoy_armed_enabled`, false, read by `public.cargo_armed_on()` alone**, which also needs `convoys_on()`.
- The switch decides one thing: the class she should be (`public.cargo_class`). `convoy_ship_class` stays `qpinnace`; a new knob `convoy_armed_class` holds `navire`.
- Everything else follows from what she is, not from the switch: guns on her hull mean hands, stores and upkeep. So a ship at sea when the switch moves is looked after until she is home.
- **Once the owner keeps it on, `convoy_ship_class` and the switch die in their own slice.**

## The 100 live hulls: refitted in place, free

- A ship is refitted when she lies **idle at home with no load**. A ship on a lap or with funds aboard is left alone, and takes her hull when her lap has closed. Lit, a realm's ships are mixed for up to one lap.
- She stays the same ship: same fleet, house, number, name, book, home. The old hull goes, and `public.commission_ship`, the one place a hull enters `ships`, lays the new one. Her roll is new.
- **No gold moves at a refit and none is minted.** A hull is a world object, as the design says.
- Switch off: the same step, the other way. Each ship goes back to `qpinnace` as she comes idle at home, her hands back on the quay.

## What she does, lit

At each departure of a ship with guns, `public.cargo_upkeep`:

1. **Hands** from the quay she lies at, above `npc_crew_pool_floor`, up to her complement. Free. A quay with none gives none and she sails short, at the short-crew speed. She tries again at the next stop.
2. **Stores** topped up free to `convoy_store_days` (90).
3. **Upkeep:** her origin pays `convoy_upkeep_per_leg` (500) to the harbour she leaves. Moved, two rows, new kind `CONVOY_UPKEEP`.

Her wage is 0 (`public.fleet_wage`), so nothing is ever owed.

## Hot bodies re-cut (8 hunks, each once, each reversing)

`cargo_ship_step` (3), `cargo_rebase` (1), `cargo_ships_commission` (1), `fleet_wage` (1), `npc_refit_step` (2).

Moved, same statements: `public.fleet_hands`, lifted from `npc_refit_step`, so hands from a quay have one copy. It also takes no lock when there is nothing to give.

New: `cargo_armed_on`, `cargo_class`, `cargo_armed`, `fleet_hands`, `cargo_hull`, `cargo_upkeep`. Knobs: `convoy_armed_enabled` false, `convoy_armed_class` `navire`, `convoy_upkeep_per_leg` 500, `convoy_store_days` 90. Client: the word for the Money log, EN and KO, filed under Wages. No cron job, no table, no column.

#527 (0325) and #529 (0327) cut none of these bodies. #534 (0326) cuts `cargo_ships_commission`, not the line cut here, and retires `convoy_ships_per_nation`, so proof 36 assumes no count. Laid-up ships (0326) are out of the job, so no step reaches them and they keep the hull they lay up in; a woken ship takes her hull when next idle at home.

## Why off equals today

No live hull has guns, so `cargo_upkeep` stops at its first read. Every live hull is her class, so `cargo_hull` stops at its first compare. No live cargo ship has hands, so the `fleet_wage` branch is never entered.

**Proved:** 0324's `rich-cities/dark-scene.sql` (15 lines: plans, flows, purses, book, ships, a whole lap, gifts) and `armed-cargo/dark-scene.sql` (5 lines: a commission, the wage of a cargo ship and a company, a cargo refit, a merchant refit from a quay near its floor) are equal before and after the file.

Dark cost: one extra `fleet_kind` read per voyage-day of a crewed fleet, on the beat. Two reads per idle cargo ship per job run. One read per cargo departure. Not measured on prod.

## Printed: the fight (proof 36, `voyage.fight`, 80 fights a strength, one run of one hull each)

Old hull crewless, against the armed hull. Held means she saw them off.

| Raider strength | Old: held | Old: hull lost a fight | Armed: held | Armed: hull lost a fight |
|---:|---:|---:|---:|---:|
| 10 | 2 | 16.5 % | 80 | 0 % |
| 27 | 2 | 43.1 % | 57 | 2.2 % |
| 40 | 2 | 62.6 % | 39 | 4.5 % |
| 100 | 2 | 96.6 % | 5 | 12.7 % |

Prod's seas: the median `piracy_index` is 0.2 and the highest 0.45, so the raider of a real day is `index × 40 × (0.5 + roll)`, about 27 at most. These are outcomes at one hull's roll, not a balance verdict. W11's fight sim is still owed before `attack_enabled`.

## Printed: the speed

Read from a voyage's own frozen speed and `voyage.fleet_speed` in proof 36, over this slice's runs: **14.6 to 15.6 kn crewless (233 to 249 nm a real minute), 11.9 to 14.5 kn armed with stores aboard (190 to 231 nm a real minute).** The spread is each hull's own roll. One ship against one ship, a lap took 1.08 and 1.23 × as long at sea in the two runs printed. The design's "about 7 %" was arithmetic for a hull with a level roll and empty casks.

## Measured on prod (2026-11-06, read only, head 0324)

- 100 ships, all `qpinnace`, 0 crew. `before.sql`: all 8 hunks occur once.
- 218 cargo departures in the last hour, 1,094 in six hours: about 4,400 to 5,200 a day, so **at most about 2.2 to 2.6 M d. of upkeep a day**, against the design's 3.6 M. Leaving her origin pays nothing, and slower laps mean fewer legs.
- Longest leg of any circuit: ESP 13,911 nm on prod. Proof 36 asserts the world's longest fits in `convoy_store_days` at her slowest crewed speed: 78.6 days on the proof's world against 90.
- **Hands on the quay at the ten capitals, above the floor: 2,080. 100 ships want 6,000.** KAR has 55, under one crew. All 246 harbours: 34,925 above the floor.
- Origins' surplus today: LIS 307 M, SVQ 482 M, SAK 243 M; the other seven 108,228 to 486,446 d. Each pays its own ships' upkeep.

## Read before lighting (owner)

- **Hands.** The first ships home take the capital's whole quay above its floor. The rest sail short (about 30 % slower) and fill at stops over a lap. Merchants at those quays then pay the urgent hire price for a while. Not measured how long; the quay's refill rate was not read.
- **A poor capital pays upkeep.** With `convoy_rich_enabled` off her origin is a capital, and seven capitals have under 500,000 d. spare. Lighting W7 first moves that cost to the rich cities. Decided by default: W8 does not require W7.
- **Laps slow**, so funds arrive later for the same ships.
- **The upkeep is a real flow out of poor purses**, about 500 d. a leg.
- `health.sh` before and after, and a 30-minute after-check, as any change that alters live play.

## Proof

- `scripts/db/proofs/36_armed_cargo.sql`: 16 markers, real `city_day`, step, voyage engine, fight, economy closed, starting from crewless ships lit at capitals as prod is. The lap sails the real sea, as proof 19's. Every count reads `convoy_ships_per_nation`.
- `scripts/ops/harness/armed-cargo/proof-0328.mjs`: red first (proof 36 fails with no file), dark parity equal, real file green, 31 mutations each red for its own reason; also with 0325 and 0327 applied first (31 mutations, before 0326 existed).
- First runs found: a stable read in a self-assert's `WHERE` folded by the planner on the DO block's older snapshot, so it missed the new knob (now a variable); the proof's mistakes, a volatile call beside stable reads in one expression, and a day-long leg that arrived during the test.
- Self-assert: catalog and stable reads only, no game step, 220 to 420 ms locally.
- W8 deploys after 0325, 0326 and 0327. Its hunks must be re-checked against the bodies 0326 leaves, once #534 is on main.

## Decided by default

- The switch, and `convoy_armed_class` beside `convoy_ship_class`: the design changed one knob when no ship existed.
- The live hulls are refitted, free, idle at home, as above. Not replaced by new fleets, because her book, number and house must stay.
- Armed means her hull has guns, read from the class. A class with no attack sails crewless and pays nothing.
- Hands come from the quay, not with the hull, as W6's refit does. The design said only "crew 60". Hands are free: the upkeep is their price.
- `convoy_store_days` 90, a knob the design did not name. "Full" would be about 250 days and would slow her by about 8 % more.
- Leaving her origin she pays nobody: paying yourself moves nothing (W6's rule).
- A city pays from its surplus, what it can. A broke or busy origin pays nothing for that leg and she sails. Stopping her would stop the aid.
- Upkeep is by the origin at the moment she leaves. On a rebase leg that is the home she is leaving.
- A crew lost at sea is refilled at her next departure, free.
- A refit lays a crewless hull with a fresh roll, which can be Poor. A founding hull's floor is not used, because that path also hands her a free crew.
- `CONVOY_UPKEEP` is filed under Wages in the Money log. Words: Cargo upkeep, 화물선 유지비.

## Not verified

- Anything on prod lit. Nothing here has run on prod.
- Real-Postgres behaviour of the file and the proof: CI's disposable-chain is that proof. Local runs are PGlite.
- A real lock contention on a donor or a quay: the busy donor is stubbed; PGlite has one session.
- Whether the map or card reads well with the new hull. No browser was run: the card already serves `world.ship_view`.
- The quay's refill rate, and what the drain does to merchants.
- Cost lit, on prod's beat. One departure's upkeep was not timed.
- Who wins against a player: W11's sim.

## Rows for the coordinator (not written here)

**docs/OWNER_REQUESTS.md row 283:** `PART BUILT - W8 armed cargo ships, migration 0328, dark behind its own switch convoy_armed_enabled, PR open, not deployed. OPEN: W9 owner's switch; player attack is W11 (#529).`

**docs/WORK_QUEUE.md, one line at the top:** `2026-11-06 **THE CARGO SHIP IS ARMED (W8, owner row 283) - migration 0328, DARK behind its own switch convoy_armed_enabled, PR open, NOT deployed, follows 0327:** lit, the live hulls are refitted free as they come idle at home to a navire with guns and 60 hands from the quay; each leg her origin pays 500 d. to the harbour she leaves, moved; no wage, no debt. Read before lighting: the capitals' quays hold a third of the hands wanted; laps slow by about 10 to 25 %; seven capitals have little to pay with. Dev-log docs/dev-log/2026-11-06-the-cargo-ship-is-armed.md.`

## PROD CHECKS

- Before deploy: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/armed-cargo/before.sql`. Every `times` 1, `armed_keys` 0, `upkeep_word` 0, `armed_on` null, `armed_hulls` 0, `class_ok` 1, head 0327.
- After deploy: `scripts/ops/harness/armed-cargo/after.sql`. `armed_on` false, `class` `qpinnace`, `armed_hulls` 0, `crewed` 0, `upkeep_flows` 0.
- `bash scripts/ops/health.sh`.
