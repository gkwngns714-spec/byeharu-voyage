# 0395: an armada fights as one (row 323, behind `attack_enabled`)

Owner row 323: *"with more than one fleet, max 6 fleet - an armada."* Migration 0367 built the sailing and the raid. This is the part `docs/ARMADA.md` section 7 designed and left unbuilt: the battle she starts is fought by her whole armada.

**Everything here is behind the owner's switch `attack_enabled`.** This file does not write that switch or any knob, and adds none. It takes the switch as it finds it:

- **off:** nothing changes for anyone;
- **on:** a fleet in no armada attacks, fights and closes exactly as she did. An armada's fleets fight together from this deploy.

Both arms are proved, in the migration's own self-assert and in proof 69.

Stacked on #628 (0364, fight rings) and #629 (0367, armada). Built on the combined tree `batch-6`.

## The number, and where it stands now

First written as 0368, then 0379, now **0395**, each time on the lead's word: migrations land in number order and others went first. It is merged onto main at 0375.

- **Attacks are LIT on prod since 0375.** So this file deploys lit: from the moment it lands, a company whose attacking fleet is in an armada fights with all of her. A fleet in no armada fights exactly as she did (proved, old bodies against new, as text).
- The file takes the switch as it finds it and never writes it. Its probe sets the switch off and then on, on its own rows, and rolls back.
- Because attacks are lit, it posts its news row: "Armada battles" / "대함대 해전".
- The probe does not call the minute job: on a lit world it would fight other companies' battles inside the probe.
- A battle being fought at the deploy has no ARMADA side, so every re-cut body reads it as it did.
- The deploy holds `public.battle_sides` for about a second (the constraint is swapped). A read of a battle's sides waits that long.
- 0380, 0381 and 0390 to 0394 deploy before it and were not there to read. If one re-cuts a line this file anchors on, the migration refuses by name and `before.sql` shows `old_times` 0 on prod before the deploy.

## With 0374 (loot follows the risk taken)

0374 changed one line of `public.loot_take` and one of `public.battle_sheet_freeze`. Neither is a line this file anchors on: all 13 hunks were found once on main, none was re-anchored.

The two rules compose with no change to either:

1. **The gold is 0374's figure.** `G = loot_due(outcome, floor(aboard × loot_risk(result)), the day's loot so far)`. The risk is read on side b of the battle's kept result, and side b is the **whole armada's** hull: (hull all her fleets lost) ÷ (hull all her fleets brought) ÷ 0.075, never over 1, never under the floor.
2. **Then it is shared by guns.** A fleet that joined is counted `floor(G × her guns ÷ all the guns)`. The fleet that attacked is counted the rest. The shares add up to G to the ducat.

Proof 69 holds `G` to that formula in every play, computed from 0374's own leaves, and the shares to theirs. Measured on an armada of two (guns 770 and 550) against a ship with 100,000 aboard, boarded:

| setting | risk | gold | shares |
|---|---|---|---|
| as shipped (floor 0), no hull lost | 0 | 0 | 0 / 0 |
| floor 0.4 | 0.4 | 6,000 | 3,500 / 2,500 |
| rule off (`loot_risk_full` 0) | 1 | 15,000 | 8,750 / 6,250 |

**Worth knowing:** the risk is a share of her own hull. A bigger armada brings more hull, so the same damage is a smaller share and pays less. Six fleets that lose one ship's worth of hull are paid as a fleet that lost a sixth of hers. That is 0374's rule read plainly on the sheet; nothing here changes it.

## The merge

`git merge origin/main` conflicted in 13 files. Main's side was taken for all 13. Then only this branch's own changes were put back, in the 6 files it touches: `docs/ARMADA.md`, `scripts/ops/harness/README.md`, `src/lib/i18n/dict/fight.ts`, `src/lib/rpc/types.ts`, `src/live/AttackSection.tsx` (clean) and `src/live/BattleView.tsx` (by hand, onto 0374's reworked card: the navy clock and the "By hull risked" line are main's, the armada rows and "Whole armada" are added). The seven fight-ring files are main's, untouched. The tree is main plus this branch's 18 files and nothing else.

## The rules, in plain words

- **Who takes part.** The fleet that attacks, and every other fleet of her armada that is *there* and has a ship:
  - she lies in port: the fleets of hers docked in that same port;
  - she is at sea: the fleets sailing under the same lead voyage and within 240 miles of her (`attack_reach_nm`);
  - she lies at anchor: nobody.
  A fleet of hers that is elsewhere takes no part and is not held.
- **All or none.** Each fleet that would take part must be free, have an empty hold, and be outside the 30-minute cooldown. If one is not, the whole attack is refused under that fleet's name. Nothing moves.
- **The sheet.** All their hulls stand on her side, the fleet that attacked first, then the armada's own order. The sheet says the armada's name and her fleets.
- **Held and freed.** All of them are held for the battle and freed at its end. At sea they are held for the same span, so they still arrive together.
- **Stance.** One for the whole side. Fight or Flee, pressed once, acts for every fleet.
- **Hull damage.** Each ship loses what the one fight says for her.
- **Crew loss.** If she is thrown back, breaks off or flees, every fleet on her side loses 10 % of each ship's hands (the existing "beaten" row), each softened by her own surgeon.
- **Loot.** Gold goes to the company's one purse, once, as before. The report says each fleet's share: in proportion to the guns she brought, rounded down, the remainder to the fleet that attacked.
- **One report** a battle, with the shares.
- **No player fights a player.** Both refusals (`E_HUMAN_TARGET`) are untouched and come before anything of this file.

## What a player will see once attacks are lit

- The attack preview on a ship's card shows a row "Armada" with her name, "N fleets · M ships" and the fleets' names. The strength word (Weaker, Even, Stronger) is read with all of her.
- A sister that cannot fight refuses the attack in words that name her, for example "Guarda carries cargo: a war fleet sails with an empty hold".
- The red ring on the map is bigger: it counts each of her fleets.
- The fight sheet lists each of her fleets on the attacker's side.
- Her battle card says the armada's name, lists her fleets, and says "Whole armada" beside Fight and Flee.
- At the end each fleet's row shows her share: gold, crew lost, hull lost.
- History has one battle report, with the shares.

## How it is built

- Seven new server-only functions. No table, no column, no knob, no door. `battle_sides.how` takes a fourth word, `ARMADA`.
- 13 hunks on 9 bodies, each cut once and reversing:

| body | hunks | what |
|---|---|---|
| `public.attack_for` | 2 | the armada's gates before the fleets are settled; the answer names the armada |
| `public.battle_open` | 1 | the stop loop also takes the fleets that joined |
| `public.battle_sheet_freeze` | 1 | the armada's name, fleets and word on the sheet |
| `public.battle_resolve` | 1 | one report a battle |
| `public.attack_close` | 2 | "the attacker" is the fleet that opened it; the shares |
| `public.battle_log` | 1 | the log names her fleets |
| `world.battle` | 2 | any fleet of hers reads the battle; the armada's view |
| `public.navy_close` | 2 | her own armada is never "the navy that came" |
| `public.battle_navy_served` | 1 | nor the navy's clock on her card |

- **Overlaps with batch 6.** 0364, 0366 and 0367 cut none of these nine bodies. 0357 (on main) cut `battle_open` and `battle_resolve` and made `battle_sheet_freeze`, `battle_log` and `world.battle`. No hunk here stands inside a text 0357 added: proof 60 still reverses 0357's 23 hunks on these bodies and is green.
- Not cut: the engine (`public.fight_sides`), `public.battle_fight`, `public.battle_advance`, `cmd.battle_stance`, `cmd.attack`, `cmd.preview_attack`, `public.fight_card`, `world.fights`, the registry.
- The sisters' side rows are written a microsecond apart, in the armada's order. Every existing reading that orders a battle's sides by the time they joined then lists her fleets in order, with no change to those readings.

## Two faults the design would have had

Section 7 said the ring and the freeze need no change. That holds. But two other readings counted every side whose `how` is not `OPENED` as the navy:

- `public.navy_close` would have reported "The navy came up before it ended" for her own second fleet.
- `public.battle_navy_served` would have shown "Navy arrives" on her card at once.

Both are cut, and proof 69 holds the navy's count at 0 with two fleets on her side.

Also, section 7 said loot goes "into the attacking fleet's hold". Loot is gold and goes to the company's purse (`public.loot_take`). So there is nothing to split into holds; the share is a figure in the report.

## Decided by default (the owner may reverse each)

| # | question | default |
|---|---|---|
| D21 | Who is "there" | Same port; or the same lead voyage and within 240 miles. Nobody for a fleet at anchor |
| D22 | A sister that is busy, carries cargo, or is inside the cooldown | The whole attack is refused under her name |
| D23 | A sister with no guns | She joins. Only the fleet that attacks must have guns (the existing gate, untouched) |
| D24 | The cooldown | Every fleet that fought has it |
| D25 | The stance | One for the whole side |
| D26 | Crew loss | The same 10 % row for every fleet on her side, each by her own surgeon |
| D27 | Loot | Gold to the one purse; shares by guns brought, remainder to the fleet that attacked |
| D28 | `armada_enabled` off | The battle does not read it. `attack_enabled` is the switch |
| D29 | News | One row, posted only if attacks are lit at the deploy. They are, so it is posted |
| D33 | Loot with 0374 | The gold is 0374's figure, read on the whole armada's hull; shared by guns as D27 |
| D30 | A watcher's log | Does not name her fleets (0364 cuts a watcher's log to nine keys); the sheet's side list does |
| D31 | Korean words | 대함대 (Armada), 대함대 전체 (Whole armada), 선체 손실 (Hull lost) |
| D32 | The navy's answer | Unchanged: it answers the ship set upon, not the size of the armada |

## Measured locally (PGlite, the cached world at batch 6)

- The migration applies in about 0.5 s: catalog 0.3 s, probe 0.1 s. Budget 40 s.
- Proof 69: 11 of 11 markers, about 2.7 s.
- The loot figures are in the table above.

## Any dice

Every built world has its own `world_secret`, so no check here asserts one outcome of a fight (the lesson at the end of `2026-11-12-live-rounds.md`).

- On main at 0375: proof 69 under **12 world secrets**, green 12 of 12. (On batch 6 it had held under 24.)
- The self-assert ran on a lit world under 7 secrets on batch 6, and on main's lit chain under the world's own.

## Checks run on main at 0375 (attacks lit)

- Cached apply and self-assert: green. All 13 hunks once.
- Proofs on top of 0395: 69, 56, 60, 66, 68, 74 (both files), 75: all green.
- `tsc`, `eslint`, `vite build`: clean.
- Specs, all green (136 tests): `rpc.armadaBattle`, `map.armadaBattle`, `battle.card`, `battle.live`, `rpc.battle`, `rpc.fights`, `rpc.armada`, `fleets.armada`, `map.fight`, `rpc.surface`, `news.lint`, `duplication`, `sections`, `harness.guard`, `i18n.*`, `names.whole`. `rpc.fights` is main's fixed version and no longer goes red in a long run.
- The rollback draft was run locally on batch 6 (13 hunks back at their pre-images). It was regenerated for 0395 and not run again.

## Local body digests (`before.sql` and `after.sql` print prod's as `bodies`)

| body | before 0395 | after 0395 |
|---|---|---|
| `public.attack_for` | 53309a5e81154c4588eedf997a166c2d | 7f3695dc3fbcec99193bcad55f6730d9 |
| `public.battle_open` | 7b1a737e3c518d0ec5be90e7246dbaa3 | 354464e2b2d43640381eb6993942dfb3 |
| `public.battle_sheet_freeze` | 921b33c0901e48fc9a48de5fc16b9ab6 | b043ca11f0cbf65a79f929738dcd7a3b |
| `public.battle_resolve` | e0beecd55c31f9e556c7f917f38f45ba | 2e8959c0ed161add876475541843fea8 |
| `public.attack_close` | c7412676e7e69ca7e62546ed20c34da5 | fefa8b15e507293acdf61d71421812e6 |
| `public.battle_log` | 6969af50b1069af36b1bc46546f19619 | 2eaf93932e5346f4e6a69ddf5e96ef25 |
| `world.battle` | 08ab13cc73fc2bb5d927ae22963a67dc | 22c7083d304e078f27455f9a874b6acd |
| `public.navy_close` | 4d35f86e3f6d328ff93fd8dddd6056e8 | 2790d7ceb8d088d67d8128e4eb51904c |
| `public.battle_navy_served` | d3b26cb2b625efd1603567cca950d741 | 613f5982b143dbf6d0ac1da196c58a7b |

These are batch 6's. 0374 re-cut `public.battle_sheet_freeze`, so that row differs on main and on prod; the others should match. What must hold is `old_times` 1 on every row of `before.sql`.

## Prod checks (read-only, one statement a file), in order

1. `scripts/ops/harness/armada-battle/volatility.sql`: every function the checks call is `s` or `i`.
2. `before.sql`: 13 rows, **every `old_times` 1** and `new_times` 0, `made` 0, `how_check` without ARMADA, `armada_sides` 0, `pvp` "both refusals stand", `attack` true. Head: whatever is highest when it deploys, at least 20260818000390. `fighting` says how many battles are being fought now: a quiet moment is kinder. **An `old_times` 0 means do not deploy.**
3. Deploy.
4. `after.sql`: 13 rows `new_times` 1, `made` 7, `client_fns` 0, `anon_fns` 0, `how_check` with ARMADA, `attack` true, `pvp` "both refusals stand", `switch_first` "yes", head 20260818000395. The News face has one new row, "Armada battles".
5. It changes live play for a company with an armada: the 30-minute after-check.

None of these was run on prod by the builder.

## Not proven

- Nothing was run on prod.
- The attack preview's armada row was not driven in a browser: a cargo ship's card is not reachable on the page while the shipped world's merchants are dark. The receipt it draws is proved on the built world (`rpc.armadaBattle`).
- A real fight in which her fleets take hull damage: the cargo ship and the navy ship of the proof never hit. The hull share's arithmetic is proved in the self-assert on a fight written there.
- A navy called against an armada with ships that come up: proof 69 lays every other navy ship up.
- Two attacks of one armada pressed at the same instant (the armada's row is locked first so they wait on each other; no test runs two sessions).
- The bodies of 0380, 0381 and 0390 to 0394 were not there to read: the anchors are proved against main at 0375.
- A deploy while a real battle is being fought was not played end to end; the probe plays the same thing on its own battle.
- **A thing to know about the ring.** Seven fleets make a ring 52 px wide. A wide ring leaves a harbour under it its own press (0364's rule), and a harbour's reach is about 40 px. So when her armada lies in port right beside the ship she set upon, only the ring's rim opens the fight. The browser spec presses there. In play the ship is usually far from the port and the ring is mostly open water. 0364's rule was not touched.

## Rollback

Forward, owner only. The switch off stops new battles. The whole slice: `scripts/ops/harness/armada-battle/rollback-0395.sql` is the draft of the reversing migration. It refuses while a battle is being fought or while a side row says ARMADA.
