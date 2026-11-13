# 0371: a fleet fights, flees or pays (lights `raid_orders_enabled`)

Owner, 2026-11-13 (row 324): *"do all, make everything work. open them if everything is built and is workable."* Row 315 asked for the fight log and an order per fleet.

0353 built the standing order dark (slice C2 of `docs/COMBAT_LOG.md`). This is the light: one migration in the form of 0178 and 0179. **Nothing here was run on production. No switch and no knob was touched.** Measured on the local PGlite world, cached prefix at `origin/batch-6`.

## What was owed: design R7, the flee knobs
`docs/COMBAT_LOG.md` 7, R7: *"The flee knobs (0.15, 0.05) are reasoned, not measured. Run sim.mjs with each order ... before lighting, and put the table in the dev-log."* Prod has almost no recorded raid on a company ("no company was raided in the window", `docs/WORK_QUEUE.md`), so the table is measured with the real engine on the cached world instead: `scripts/ops/harness/combat-log/flee-knobs-scene.sql` (new). Real hulls read as the raid reads them, 1,000 seeded raids a cell, through `voyage.raid_report` (the skin `voyage.settle` calls). The raid sizes are the two of `docs/COMBAT_LOG.md` 2.5: one xebec (12.7) and five (63.5). A raid's cost is priced as the settle prices it: plunder takes 37.5 % of the cargo on average, Pay takes 8 %.

### At the seed knobs (base 0.15, floor 0.05): what each order costs, per raid
| Fleet | Raid | Fight | Flee | Pay |
|---|---|---|---|---|
| Barca, no guns, 30,000 d. aboard | one xebec | 11,250 d., hull −15.9 % | away 32 %; 7,605 d., hull −13.3 % | **2,400 d., hull 0** |
| | five xebecs | 11,250 d., hull −76.3 % | away 32 %; 7,605 d., hull −63.9 % | **2,400 d., hull 0** |
| The same barca with a lookout (sighting 20) | one xebec | 8,258 d., hull −10.5 % | **away or unseen 92 %; 911 d., hull −3.7 %** | 1,762 d., hull 0 |
| | five xebecs | 8,258 d., hull −50.7 % | **911 d.**, hull −18.2 % | 1,762 d., **hull 0** |
| Navire, guns, 200,000 d. aboard | one xebec | **0 d., hull −0.4 %** (she wins every time) | 0 d., hull −0.5 % | 14,160 d. for nothing |
| | five xebecs | 63,600 d., hull −8.4 % | **away or unharmed 87 %; 10,125 d., hull −2.5 %** | 14,160 d., hull 0 |

### Flee, with the knobs moved (the other orders do not read them)
Cargo and ransom lost per raid, and the share of raids she gets away from or is not harmed in.

| Fleet, raid | base 0.10 | **base 0.15 (seed)** | base 0.20 | base 0.25 | base 0.15, floor 0.10 | Pay, for comparison |
|---|---|---|---|---|---|---|
| Barca, either raid | 8,168 d. (27 %) | **7,605 d. (32 %)** | 5,445 d. (52 %) | 4,005 d. (64 %) | 5,805 d. (48 %) | 2,400 d. |
| Barca with a lookout, either raid | 911 d. (92 %) | **911 d. (92 %)** | 911 d. | 911 d. | 911 d. | 1,762 d. |
| Navire, five xebecs | 15,900 d. (79 %) | **10,125 d. (87 %)** | 7,125 d. (91 %) | 7,125 d. (91 %) | 10,125 d. | 14,160 d. |

### What the table says
- **No order is best everywhere, and none is useless.** Guns make Fight free against a small raid and the worst order against a large one. Against the large raid Flee beats Pay for a gunned fleet at the seed knobs (10,125 against 14,160), and Pay leaves her hull whole.
- **For a gunless ship with no lookout, Pay beats Flee in every case** (2,400 d. and no hull lost, against 7,605 d. and 13 to 64 % of her hull). Flee is still better than Fight for her. This is the design's own line (2.5): "Pay beats Flee without a lookout; a lookout turns that round." A lookout does turn it (911 d. against 1,762).
- **No value of the base inside its cap makes Flee beat Pay for that ship**: she would need to get away 79 % of the time, a chance of 0.23 a round with a sighting lead of −3, which is a base of 0.32, above the top of 0.30. So the weak trader's choice between Flee and Pay is decided by her lookout and her insurance (plunder is insured, a ransom is not), not by these two knobs.
- **The base matters most for the gunned fleet against a large raid.** At 0.10 Pay wins there (15,900 against 14,160); at 0.15 and above Flee wins. At 0.15 the two sit 4,000 d. apart, which is a real choice. At 0.20 and above Flee becomes the plain answer for a gunned fleet, and it gets her away from more than half of all raids even with no guns and no lookout.
- **The floor (0.05) is not what the barca stands on at the seed** (her chance is 0.06 a round). Raised to 0.10 it gives every hopeless ship a 48 % escape, which takes away the point of a lookout.

**Proposal: keep both knobs as they are (0.15, 0.05).** This file changes no knob, and it refuses if the two are not those values. If the owner wants Flee to be kinder to a new player's gunless barca, the smallest move is the base to 0.20 (stated here as a possible default, not done).

### Open points left at their defaults (`docs/COMBAT_LOG.md` 7)
- O2: a fleet that never chose is Fight, even with no guns. The table says a gunless ship should Pay or Flee; the picker's read tells her ("Raiders: Far stronger", "No guns"). Defaulting her to Flee changes live results unasked; not built.
- R3: a purse that cannot pay the whole ransom pays what it holds.
- R5: Pay moves RANSOM to the raider or the pirate capital.

## What the file does
`supabase/migrations/20260818000371_a_fleet_fights_flees_or_pays.sql`, one DO block:
1. **Refuses** unless the switch reads exactly false, nobody holds an order (`fleet_raid_orders` empty), and the flee knobs read 0.15 and 0.05.
2. Not a guard, on purpose: whether someone can take a ransom. Without a payee a Pay is refused and she fights; the log says why. The local world has none (its purses are dark); prod had one on 11-12 (`payee.sql`). The receipt prints which.
3. Writes the one row.
4. A probe company and a probe merchant, rolled back: the door keeps Flee and Pay and refuses a bad word and a merchant's fleet; the read says on; a departure's segments freeze the order for her fleet only; Fight leaves no row; with the switch set back inside the probe a frozen order is read as none and the door refuses `E_NOT_IN_USE`.
5. No function moved, no other knob moved. News: **"Raids: Fight, Flee or Pay" / "습격: 전투, 도주, 지불"**. Budget 30 s. Locally 0.13 s.

## Proof 72 (`scripts/db/proofs/72_raid_orders_lit.sql`), the lit world as the chain leaves it
Through the client's doors, which proof 56 does not use: a SAIL through `cmd.issue` and **a turn at sea through `cmd.divert`** (the 0353 dev-log listed the turn as not proven).

| Marker | Result |
|---|---|
| LIT_BY_0371 | switch true, no order held, knobs 0.15 / 0.05, one news row |
| LIT_PICKER_READ | on, order FIGHT, guns false, slip poor, pay 0, 5 danger levels with the raiders' word |
| LIT_SAIL_FREEZES | Flee, then SAIL LIS to CAD: 3 segments, each frozen FLEE; the raid reads FLEE |
| LIT_FLEE_FOUGHT | 200 raid days of one xebec under the frozen order: away on 56, caught on 144; no day paid, her guns hit on none |
| LIT_TURN_REFREEZES | Pay chosen at sea left the voyage as it was; the turn wrote a new voyage frozen PAY |
| LIT_FIGHT_IS_NO_ROW | FIGHT deleted her row; no merchant holds or carries an order |

Proofs 56 (11 of 11), 60 (14), 64 (6), 66 (9) are green with 0371 in the chain: each sets the switch itself.

## In a browser, lit (headless, port 4421)
- New `tests/raid.order.lit.spec.ts`, the world as shipped: the picker on **the fleet page** and on **the map's Send tray**, at **390 and 320 px, English and Korean**. The three words stand in her language; a press is kept by the real door and shown back by the real read; nothing is cut or off the glass. 8 passed. Pictures read (the tray at 320 px in Korean: 전투 / 도주 / 지불, 해적 훨씬 강함, 이탈 낮음, 지불 화물 없음, 포 없음).
  - The first run failed the four tray tests: the picker stands only under the PICKED fleet, and the test had not picked her. The test was wrong, not the page.
- `fight.log.page` (6: 390 EN and KO, 1280 EN and KO, 320 EN, and the dark page), `arrival.card`, `fight.log`, `ledger.fights`, `map.sendfleet`, `rpc.raid-order`: 48 passed in that run.

## Specs that assumed orders dark (each changed)
| File | What it assumed | Change |
|---|---|---|
| `tests/rpc.raid-order.spec.ts` | the built world is dark | Sets its own database dark first |
| `tests/fight.log.page.spec.ts` | "the world as it ships" draws no picker | The dark page is proven on a copy of the image with the switch set back |

## What a player sees the moment it is lit
- A **Fight / Flee / Pay** picker on the map's Send tray (under the fleet she picks) and on her fleet's page, with three reads: the raiders' word against her, her chance to slip as a word, and what Pay would cost now.
- It takes hold at her next departure. A voyage under way keeps Fight.
- One news row.

## PROD CHECKS, rollback
In the PR. Rollback, one line (owner only): `update public.world_config set value = 'false'::jsonb where key = 'raid_orders_enabled';` As a migration: `scripts/ops/harness/combat-log/rollback-0371.sql` (draft; run on the local world after 0371).

## Not proven
- Nothing ran on prod. The knobs were not measured on prod's recorded raids (there are too few on companies); the table is the real engine on real hulls with seeded raids.
- Pay to a NAMED raider through the real settle (unchanged from the 0353 dev-log).
- A ransom moving on the local world as shipped: its purses are dark, so a Pay there is refused (NO_PAYEE). Proof 56 lights them and proves the money.

## Found on the combined tree (batch-7): the picker moved the page under it
`tests/fleets.page.spec.ts`, "the press on Move moved the page under it", at some sizes and not others. Cause: on a fleet's page `src/live/RaidOrder.tsx` drew nothing until `world.raid_read` answered, then appeared and pushed the foot (Command, Rename) down 351 px. The spec measured the foot, pressed Move, and measured again; when the picker's read landed in between, the foot had moved. It never showed on the fleet-room branch (no picker there) and I had not run `fleets.page` on this one.

Fixed here, at the source: while the read is on its way the SAME rows stand with no figures (`RaidOrderWaiting`: the heading, the three orders unmarked and unpressable, Raiders, Slip, Pay, and the last line), and the last line keeps its place whether it says "No guns" or nothing. Measured by the lit spec at 390 and 320, EN and KO: **327 px waiting, 327 px landed**, the waiting state caught in all four. A world where orders are off draws nothing; that answer is remembered for the session, so only the first mount there holds the room open for a moment.

On main with 0369, 0370 and 0371: `fleets.page` 18 of 18, `raid.order.lit` 8 of 8 (twice), `fight.log.page` 6 of 6.

Seen while measuring, not changed: a fleet page's ship places (the locked and empty tiles of 0354 / #617) also land on their own read, `world.house_room`, and move the foot when they do. `fleets.page` waits for them before it measures, so no spec is red; it is the same kind of late landing and belongs to the Fleets page.
