# Gear wear, made ready to light (`gear_wear_bite`, migration 0158; owner row 324)

Owner, 2026-11-13 (row 324): *"do all, make everything work. open them if everything is built and is workable."* Gear wear (0158, 2026-10-18) has been built and dark ever since; the audit of 2026-11-13 called it "NOT AUDITED: state unknown". This slice reads what it does lit, measures it, fixes what a player would have met, and prepares the lighting.

**State: two PRs, nothing deployed, nothing lit.** `gear-wear` (client, proof 72, harness, this file; no migration) and `gear-wear-light` (migration 0390, "lights gear_wear_bite"). Prod was not read or written. Base: `batch-6`.

**Verdict: READY TO LIGHT**, after `before-light.sql` reads as wanted. At today's knobs wear is a reminder to visit a yard, not a cost: see the measurement.

## What happens when it is lit (read from the live bodies of the chain at 0367, then played)

| | Rule | Where |
|---|---|---|
| What wears | A mounted fitting whose item answers to a sea event (`public.item_use.trigger`): 38 items to MILES (canvas, rigging, lookouts), 95 to STORM (the low rack, hull-keeping gear), 55 to PIRATES (the high rack: guns, boarding gear). 37 never wear (the figurehead, every refit). | `public.item_use` |
| How fast | At each ARRIVAL of a company's fleet: a MILES piece gains the passage's miles / 1,000 x `gear_wear_per_1000nm` (1); a STORM piece 3 a STORM day met (`gear_wear_per_storm`); a PIRATES piece 4 a PIRATES day met (`gear_wear_per_fight`). Held at 100. The Seasoned perk slows it (x 0.75 / 0.5 / 0.25). | `public.wear_units_for`, called once from `voyage.settle` |
| On which events | Sea days of a voyage only. A battle she starts (0323 / 0357), a navy meeting and a day in port wear nothing. | the same |
| Since when | **Since 0158 landed, while dark**: the writer never asked the switch. Companies' fittings on prod already carry wear that nobody can see. | `before-light.sql` reads how much |
| What a worn piece does | Each thing the piece BUYS (a positive effect) counts x (1 - wear / 200): at 100 worn it works at half. What it spends (deck, hands, a negative effect) is spent whole. Nothing breaks. | `public.worn_delta` in `world.ship_stats` |
| What repair costs | Per piece: the recipe's value x wear % x `gear_repair_pct` (0.30) x `running_cost_level` (0.2), rounded to the coin. So a piece at 100 costs 6 % of its recipe: Boarding gear 34 d., a Suit of sails 45 d., Culverins 187 d., the dearest battery 1,116 d. A piece a few points worn rounds to 0 d. | `public.unit_repair_cost` |
| Where | At a repair yard (the city's Repair face), in the same REPAIR order as the hull and the same payment to the city. A whole hull with worn fittings can still be repaired. Also: a worn piece taken off is repaired on its way off for its own price (refused with figures when she cannot pay). | `cmd.do_repair`, `public.unmount_fitting` |
| Merchants and crown, navy, pirate ships | **Exempt, as built.** The one writer is called inside `voyage.settle`'s players-only block. Their fittings stay new, their figures whole, they never pay for a fitting. | proof 72 `WEAR_MERCHANT_EXEMPT`, `npc-scene.sql` |

## The measurement (cached world at 0367, real voyages, `measure-scene.sql`)

Probe companies sail 40 round trips out of Lisbon (Porto, Nantes, Copenhagen in turn: 64,983 nm, about 200 sea days each) through `cmd.issue` BUY / SELL / REPAIR and `voyage.settle`, with pirates, combat, crew, skills, levels, reputation, price impact and the navy lit as on prod and gear wear lit. Each company runs on the same untouched market (her run is rolled back before the next). Two clocks are skipped (port time, the yard's hours); the money is the game's own. City purses are not lit in the local world (they were never seeded there), so dock fees are not in the figures.

**Each world rolls its own sea.** These are one run's figures; the storm and pirate days move from run to run (0 to 4 in 200 sea days here). Nothing in the proofs asserts them.

| Company | Fittings that wear | Sea days | STORM / PIRATES days | Fittings repair, whole run | a sea day | Hull repair a sea day | Trade (sold less bought) a sea day | Fittings repair as a share of trade |
|---|---|---|---|---|---|---|---|---|
| One barca, as founded | 0 | 193 | 1 / 0 | 0 d. | 0 | 0.8 d. | 2,261 d. | 0 |
| One barca, every place filled (what a new company may fit: 2 Storm canvas, 1 Boarding gear) | 3 | 220 | 3 / 0 | 0 d. (3 repairs priced the fittings at 0 d.) | 0 | 1.9 d. | 1,988 d. | 0 |
| Armed trader (carlat; 3 Storm canvas, 2 Boarding gear), repaired each lap | 5 | 191 | 1 / 1 | 2 d. | 0.01 d. | 1.0 d. | 2,520 d. | 0.000 % |
| The same, never repaired | 5 | 197 | 1 / 0 | (none paid; bill left 0 d.) | | | 2,449 d. | |
| Rich company (nau + galion, the dearest pieces that mount: 6 binnacles, 4 bowsprits, 6 broadside guns, 2 swivel guns, 3 deal planking), repaired each lap | 21 | 227 | 2 / 0 | 474 d. | 2.1 d. | 11.6 d. | 1,975 d. | 0.106 % |
| The same, never repaired | 21 | 229 | 1 / 0 | (none paid; bill left 517 d.) | | | 1,937 d. | |

What neglect does (the rich company after 65,000 nm with no repair): her canvas and lookouts stand at 65 worn and work at 67.5 %. The first hull's speed fell 13.05 to 12.65 knots (3 %), handling 62 to 51.6 (17 %), sighting 23 to 20.2 (12 %); attack, armour and hold did not move. The whole bill to mend it: 517 d.

The trading-15 company: a level changes nothing in wear (no rule reads it); what changes her bill is what she carries. The "rich company" row is the ceiling for a two-hull fleet (a fleet sails two ships today). A fleet of seven such hulls would pay about seven times that: about 7 d. a sea day.

**Reading.** At these knobs a company pays 0 to 2 d. a sea day for fittings against about 2,000 d. a sea day of trade; the hull's own repair costs more. A company that never repairs loses a few per cent of speed and a sixth of handling after a year at sea. The feature works and harms nobody; it is not a money sink. If the owner wants it to bite, the levers are the three wear knobs and `gear_repair_pct` (owner only; measure again with `measure-scene.sql` after a change: the lighting file refuses when the knobs are not the measured ones).

## Merchants (`npc-scene.sql`, the real jobs)

| | |
|---|---|
| NPC hulls' figures, dark against lit | 892 hulls digested, equal: lighting moves no NPC figure |
| Sailed lit, hazards on | 60 merchant fleets, 40 beats of the real arrivals beat and lap-start pass: 182 voyages, 245,990 nm, 4 STORM days, 1 PIRATES day |
| What a company would have taken on those voyages | 4.1 wear points a fleet on canvas, 0.2 low rack, 0.07 high rack |
| What the merchants took | 0 of 2,555 fittings worn; 0 repairs with a fittings bill |

**Decided by default: merchants stay exempt** (as 0158 built it, after the owner's 2026-10-15 rule that a merchant's hull is constant). So wear cannot cripple the NPC economy: no path writes it. It is a small edge for NPC hulls in a fight (their guns never tire); at 4 points a raid day it is about 2 % per raid on a company's guns until she repairs.

## What a player sees when it is lit

- Her ship's sheet (Fleets, a ship, Stats): a thin bar under each worn fitting (what is left of it; amber from half worn; a new piece draws none, so a merchant's card looks as it did), and under the racks one line: "Worn fittings: 2 worn, weakest works at 69%. Repair in port mends them." Nothing when nothing is worn.
- The city's Repair face: under Damage, a row "Worn fittings 2" when something is worn, even with a whole hull. Either row opens the repair tray; the tray shows the count, and its price check a row "Fittings: 2 repaired, 12 d." inside the total.
- A new company with a founding barca sees nothing: she carries no fitting.
- Her figures (speed, handling, sighting, attack) fall by the worn share at the minute of lighting, by at most half of each worn piece's buys. `before-light.sql` says how far the most worn piece on prod has gone.

## What was wrong, and fixed (client; PR `gear-wear`)

| Found | Fix |
|---|---|
| The wear was drawn only as a 2-pixel bar with its words in a hover title: nothing readable on a phone. | The sheet says it in a line under the racks (`ship-worn`). |
| Every word about wear came from the server in English only ("12% worn · works at 94%", "4 worn fittings repaired too"): English on a Korean screen. | The client words them from the served figures, EN and KO (`ship.wearWorn`, `ship.wornFittings`, `ship.wornCount`, `ship.wornWeakest`, `ship.wornHelp`, `books.fittingsRepaired`). The server's sentences are no longer drawn. |
| The Repair face showed only hull damage: "0% damaged" with worn fittings gave no reason to press. | A "Worn fittings" row on the face and in the tray (`shipyard-worn`, `step-worn`), from one count (`wornFittings`, `src/domain/fleet`). |
| No lit browser check existed (0158's dev-log: "no browser spec drives the lit wear bar"). | `tests/gear.wear.spec.ts`: lit at 390 and 320, EN and KO (sheet, yard, tray, a real repair), and dark. |

Not changed: item names are English in Korean (every fitting, everywhere; not this slice). The server still serves its English sentences (`wear_words`, `gear.words`); nothing draws them.

## Proof

- **Proof 72** (`scripts/db/proofs/72_gear_wear_lit.sql`, 7 markers, lights the switch inside its own rolled-back transaction, so it holds dark or lit): a probe barca fitted through `public.mount_fitting`, a real passage settled: dark, her canvas wore by its miles and no read shows it; a STORM and a PIRATES day through the one writer, held at 100; lit, the card (50 worn, works at 75), her figures (some fall, none rises, buys x 0.75, spends whole); the yard's price with a whole hull and a REPAIR that charges exactly it; a worn piece off for its own price; the same hull as a merchant's wears nothing; the switch off again hides everything and keeps the wear. The passage is sailed on a quiet sea, so no marker waits on a roll.
- **Browser**: `tests/gear.wear.spec.ts`, 6 passed (preview on port 4425, headless). Pictures: `C:\Users\gkwng\dev\pirate-gear-shots\gear\`.
- **The lighting file** (0390): see its PR.

## Lighting: the checks, in order (all read-only, one statement a file)

1. `scripts/ops/harness/gear-wear/volatility.sql`: every value `s` or `i`.
2. `scripts/ops/harness/gear-wear/before-light.sql`: switch false; the five knobs as measured; `writer` calls 1, players_only true; `merchants.worn` 0; then READ `companies` and `bills` (how much moves at once, `bills_over_purse` wanted 0) and `week`.
3. `scripts/ops/harness/gear-wear/after-light.sql` once, as the baseline.
4. Light: `~/bin/bv-deploy.sh <the lighting PR>` (it posts the news row), about 20 minutes before a :37, never at :06 to :08 or :36 to :38.
5. `after-light.sql` and `bash scripts/ops/health.sh` at +1, +5 and +30 minutes: `switch_reads` true, `news` 1, `merchants.worn` 0, `merchant_repairs_with_fittings` 0, `over_100` 0.

**Rollback, ready:** `update public.world_config set value = 'false'::jsonb where key = 'gear_wear_bite'` (owner only), or `scripts/ops/harness/gear-wear/rollback-0390.sql` as a forward migration. At once every figure is whole again and no bill names a fitting; the wear stays on the units, unseen. **What cannot be undone:** gold a company paid for fittings while it was lit stays paid (it went to the city, as every repair does).

## Decided by default (the owner may reverse any)

- Merchants, crown ships, navy and pirate ships stay exempt from wear.
- The knobs are not touched (owner only). The lighting file refuses if they are not 1 / 4 / 3 / 0.30 / 0.2.
- Wear that accrued while dark is kept as it is: no reset to zero at lighting (a reset would be a write to players' rows; the bills are small; `before-light.sql` reads them first).
- The client words wear itself; the server's English sentences are left served and undrawn (no migration needed for a word).
- Proof number 72 and migration number 0390 (0364 to 0389 are held by other branches).

## Not verified

- Prod: nothing was read. How much wear has accrued, the bills, and the real rate of storm and pirate days are `before-light.sql`'s to say.
- The measurement's dock fees and port time (city purses are not lit locally); neither touches wear.
- Fleets of more than two hulls (dark behind `fleet_room_bite`): the bill scales with the pieces carried.
- A standing route with a REPAIR stop will now repair whenever a fitting is worn at all, often for 0 d. and no yard time. Read in the code (`public.fleet_repair_due`), not driven.
- Korean wording was written by the builder, not checked by a Korean reader.
