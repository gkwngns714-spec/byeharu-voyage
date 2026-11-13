# 0372: crown and pirate hulls fight at level five (lights `npc_ship_level_enabled`)

Owner, 2026-11-13 (row 324): *"do all, make everything work. open them if everything is built and is workable."* Row 288 and `docs/WORLD_POWERS.md` 2.3: *"Crown and pirate hulls take a fixed level by knob, npc_ship_level 5."*

0344 built it dark (`docs/dev-log/2026-11-10-crown-hulls-have-a-level.md`). This is the light: one migration in the form of 0178 and 0179. **Nothing here was run on production. No switch was touched.** Measured on the local PGlite world, cached prefix at `origin/batch-6`.

## The finding: a raid on a player does not get harder
The audit said: "Players lose more to named pirate ships." **Measured, that is not so.** A raid on a voyage never reads the raider's level:
- the raiders of a raid are a FIGURE: the sea's danger for an anonymous raid, or `voyage.pirate_strength` for a named pirate ship, which reads her class's attack, crew and tier and the hull she has left, and nothing else;
- `voyage.raider_hulls` turns that figure into hulls of the raider CLASS (`fight_raider_class`), with the class's own accuracy and sighting.

So the level of a pirate ship cannot reach a raid. Proof 73 holds it (`LIT_RAID_UNCHANGED`): the same pirate ship is a raid of 12.70 at level 5 and at level 1, and 60 raid days against it are the same text.

Where level 5 does count is a fight that reads the crown hull herself (`voyage.fleet_hulls`):
- a battle where a company attacks a cargo, navy or pirate ship (0323 / 0357, **dark** behind `attack_enabled`);
- the navy coming to such a battle (0333, 0334), and a navy meeting at sea (`navy_hunt_per_day` is 0);
- the navy against a pirate ship (0340): both sides are level 5, so it is even;
- a crown cargo ship set upon by a raid: she shoots a little straighter.

### The tables (`scripts/ops/harness/crown-level/raids-scene.sql`, new; 500 seeded fights a cell, the real engine, real hulls)
One raider hull is a xebec: accuracy 38 and sighting 11.0 at level 1; **accuracy 44 and sighting 11.6 at level 5**. As a raid figure she is 12.70 at both.

**A raid, as the game fights it today (`voyage.raid_report`). Level 1 and level 5 are the same, to the fight:**

| Company fleet | 1 raider hull | 2 raider hulls | 5 raider hulls |
|---|---|---|---|
| Barca (no guns) | plundered 500 of 500, hull −16.7 % | plundered 500, hull −32.9 % | plundered 500, hull −79.7 % |
| Armed trader (navire) | held 500 (383 evaded, 117 drove off), hull −0.4 % | held 389, paid 111, hull −1.8 % | plundered 407, held 93, hull −7.5 % |
| Nau | held 500 (349, 151), hull −0.7 % | held 325, paid 175, hull −2.4 % | plundered 436, held 64, hull −8.6 % |

**Hull against hull (`public.fight_sides` with the raiders' own hulls): how a BATTLE reads her. This is what changes:**

| Company fleet | Raiders | Level 1 | Level 5 |
|---|---|---|---|
| Barca | 1 | plundered 500; her hull −16.7 % | plundered 500; her hull **−19.6 %** |
| | 2 | plundered 500; −32.9 % | plundered 500; **−39.0 %** |
| | 5 | plundered 500; −79.7 % | plundered 500; **−88.7 %** |
| Armed trader (navire) | 1 | held 500; her hull −0.5 %, theirs −18.2 % | held 500; −0.6 %, theirs −18.7 % |
| | 2 | held 391, paid 109; −1.8 % | held 390, paid 110; −2.1 % |
| | 5 | plundered 411, held 89; −7.5 % | plundered **425**, held 75; **−9.1 %** |
| Nau | 1 | held 500; −0.9 %, theirs −19.4 % | held 500; −1.0 %, theirs −19.8 % |
| | 2 | held 337, paid 163; −2.3 % | held 334, paid 166; −2.7 % |
| | 5 | plundered 438, held 62; −8.6 % | plundered **449**, held 51; **−10.4 %** |

In a battle against level-5 hulls a company loses about a fifth more hull, and against five of them is plundered 2 to 3 points more often. Who wins a fight she was winning does not change.

**A crown cargo ship (an armed navire) set upon by an anonymous raid:**

| Raid | Level 1 (accuracy 59, sighting 15.0) | Level 5 (accuracy 65, sighting 15.6) |
|---|---|---|
| 12.7 (one xebec) | held 500 (393 evaded, 107 drove off), hull −0.4 % | held 500 (411, 89), hull −0.4 % |
| 63.5 (five) | plundered 410, held 90, hull −8.6 % | plundered **392**, held 108, hull −8.4 % |

The crown's cargo ships lose a little less to large raids (about 4 % fewer plunders).

## What the file does
`supabase/migrations/20260818000372_crown_and_pirate_hulls_fight_at_level_five.sql`:
1. **Refuses** unless the switch reads exactly false, `npc_ship_level` reads 5 (the level the tables were measured at), and no crown or pirate hull holds a level row (0344's dark posture).
2. Writes the one row.
3. **Runs the one writer of 0344 once** (`public.crown_hull_level_fix`, for each crown house that stood before the write), so the level stands at the deploy and not up to ten minutes later, and so a world with no job runner has it. Every such hull is then level 5, or the file fails.
4. A probe navy hull and a probe merchant, rolled back: level 5 in one write, handling +4, accuracy +6, sighting +0.6 and nothing else; the merchant never written; the rollback played (switch back, writer run: the row gone, the hull as before).
5. No function moved, no other knob moved. News: **"Navy and pirate ships: level 5" / "해군·해적선: 레벨 5"**. Budget 30 s.

Decided by default: the file compares no merchant's or company's level row before and after. Those rows grow under live play (a voyage, the merchants' own job), so such an assert could fail a deploy for no fault; the probe merchant holds the rule instead.

## Measured (local)
- The file on the cached world: 0.07 s. The local world has **no** crown hull (no job runner lays them), so a scratch scene put 40 navy hulls there first: **40 hulls, 40 rows written in 7 ms, all level 5**, and `after-light.sql` read crown_hulls 40, crown_at_level 40, crown_other_level 0. Prod had 385 crown hulls on 11-10.
- The file applied a second time: refused ("is not false in this world").
- `rollback-0372.sql` run on the world after 0372: green.
- Proof 73 (5 of 5): real makers lay a cargo, a navy and a pirate hull AFTER the light; they hold no row until the job's own command runs, then each is level 5; stats where the fight reads them; the raid unchanged; hull against hull changed. Proof 51 (6 of 6) green with 0372 in the chain (it sets the switch itself).

## The dev-log's after-light SQL, as a harness file
`scripts/ops/harness/crown-level/after-light.sql` (new, read-only, one statement): the switch, the level, the job, the news row, crown hulls, how many hold a row, how many are at the level, how many at another level, how many have no row yet, and the same by kind (cargo, navy, pirate). It runs before the deploy too (wanted: `crown_rows` 0).

## Specs
No spec names the switch. Nothing a player's screen draws changes in the local world, which holds no crown hull. No build or browser run was needed for this light; `news.lint` and `harness.guard` were run.

## What a player sees the moment it is lit
- **Nothing on a raid.** Her raids are fought exactly as before.
- A cargo, navy or pirate ship's card reads level 5.
- One news row.
- Later, when attacks are lit: the ships she attacks, and the navy that answers, shoot at +6 accuracy.

## Rollback
One line (owner only): `update public.world_config set value = 'false'::jsonb where key = 'npc_ship_level_enabled';` Within ten minutes the job deletes every such row. As a migration that also runs the writer at once: `scripts/ops/harness/crown-level/rollback-0372.sql` (draft).

## Not proven
- Nothing ran on prod. The writer's time over prod's 385 hulls (locally 40 rows in 7 ms).
- `levels_bite` must be true on prod for the level to move a stat (recorded true, `docs/WORK_QUEUE.md`); the file does not guard it, because the local chain world has it false.
- The attack sim on what really sails (the audit's 3.1) should now be run with level-5 hulls: the tables above are the first cut of it.
