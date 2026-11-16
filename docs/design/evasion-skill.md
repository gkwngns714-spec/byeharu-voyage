# Evasion: a level for running away, and a run that is her ship against theirs

Status: **DESIGN ONLY**, 2026-11-16. This branch (`evasion-skill`) holds this file and nothing else: no migration, no `src` change.
A builder implements from it. The slice is migration **0452** (prod head 0451 + 1; read the head again before naming the file).

**The owner, 2026-11-16**, answering "how hard should it be to flee?" (about 1 runner in 10 gets away since 0450):
*"number 5 needs a new skill, related to combat - evasion or something, like parley or speech or whatever. This skill will increase
your chance of running away along with speed level (or agility, you get the idea). Of course the success of evasion depends on both
myself and the other ships condition, it has to be relative."*

Every choice in this file is **decided by default**; the owner may reverse any. Section 7 lists them all in one place.

## 0. In short

- **The skill: Evasion / 회피.** One more row of the levels a company raises by doing (`public.level_skills`, 0411): the eleventh tile,
  under "Other levels" on the You page and on Command → Levels. Level 1 to 20 on the one curve. It is earned by running from a
  pirate's raid: 40 for the run that gets her away, 5 for each roll that fails. Each level above 1 makes her side sail 10 % better
  in a chase. A ship of the world has no experience: her hull's level stands for it (a merchant 1 to 5, a pirate or navy ship 5).
- **The formula, one line.** In the one place the run's chance is computed now (`public.tick_fight`, each tick, served as `rc`):

  `chance = clamp(1 %, 15 % x ( her sailing x her skill / (their sailing x their skill) )² - 5 points x her failed attempts, 50 %)`

  `sailing` of a ship = speed x (0.6 + 0.4 x hull left) x (0.7 if short-handed) x (1 + handling / 200). She runs as her slowest
  ship afloat that began the fight; they chase as their fastest ship afloat. `skill` = 1 + 10 % x (Evasion level - 1).
  Equal sides: **15 % a roll**, about 3 fights in 10 if she keeps trying and is not hurt meanwhile.
- **Numbers** (the real engine on the chain's own world, 150 fights a cell; section 4): a new player in a Barca gets away from a
  Raider in about 1 fight in 11 and from a Dread squadron in 1 in 30; Evasion 10 in a Caravela latina 4 in 10; Evasion 20 in the same
  ship 9 in 10; crippled and short-handed in a slow Nau 1 in 50. The world's merchants that run get away 10 in 100 (13.6 in 100 under
  today's rule on the same fights; prod's own 100 sheets said 4 of 39).
- **Rollback is one knob:** `chase_enabled` false gives 0450's chance to the digit. The old rule stays in the body for that, and a
  later slice deletes it (section 5.9).
- **Three things the brief did not know** (section 1.3): the run is rolled in a second place too (a voyage day's raid, the round
  engine: not touched here); today's speed term is pinned at its worst for every runner, because it reads the speed that counts a
  pirate 4.5 times as fast; and a player's ship is the last a pirate picks, so the level may rise slowly (a prod read sizes it).

## 1. What is there today

Read on `origin/main` at `7feee03e` (paths below are from the repo root; `NNNN:a-b` is migration `supabase/migrations/20260818000NNNN_*.sql`,
lines a to b), and on the chain's own world at head 0451 (the live bodies, `pg_get_functiondef`; appendix C says how). This branch
stands on `190edb6e`, which moved none of the files named here. **No production read was made.**

### 1.1 Levels and skills, as a player has them

There are three things with a level. Only the first is where a new skill belongs.

| Thing | Where it lives | How it rises | How the server reads it |
|---|---|---|---|
| **A company's levels** (ten today) | `public.level_skills` (the list: code, order, word, `kept`, `day_cap`), `0411:142-164`; `public.level_activities` (what raises each and by how much), `0411:166-203` | Two kinds. `kept = 'record'` (Trading, Exploration, Combat): recounted from her whole record by `public.player_progress`, `0069:119`. `kept = 'book'` (the seven of 0411): **`public.level_grant(player, activity, units, key)`**, the one writer, `0411:285-370`, writes `public.level_xp` (`0411:205-217`) and the append-only `public.level_book` (`0411:219-234`); at most `day_cap` (300) a day; a key pays once; a level crossed pays Reputation and one `LEVEL_UP` event (`0411:354-366`) | `public.level_from_points(xp)`, `0069:105`: `floor(sqrt(xp / 25)) + 1`, 1 to 20 (knob `level_points_per_step`). What a level gives: steps in `public.level_perks`, read by `public.level_perk(player, perk)`, `0417:128-189` (knob `level_perks_on`) |
| **A hull's level** | `public.ship_xp` | a player's: by the mile and by a voyage's pirate days (`public.voyage_xp`, 0127). A merchant's: fixed once at founding, 1 + her four skills / 3 (`public.npc_fix_level`, `0127:316`; 1 to 4 on the chain's world: 590 / 241 / 59 / 26 hulls). A crown's or a pirate's: `npc_ship_level` 5 (`public.crown_hull_level_fix`, `0344:101`) | `public.ship_level(ship)`, `0450:133-145` = `public.level_in_force` (`0127:216`): 1 while `levels_bite` is off. It adds +1 handling, +1.5 accuracy, +0.15 sighting a level in `world.ship_stats` |
| **Academy skills** (107, studied) | `player_skills`, `world.skill_bonuses` | bought and studied at the Academy | per cents inside `world.ship_stats`; `world.skill_pct(player, ship, 'handling')` is what 0432's flee bonus reads |

- **A new level is two inserts and one hook line** (`docs/LEVELS.md:204-205`): a row in `level_skills`, rows in `level_activities`,
  a `perform public.level_grant(...)` where the thing happens. `world.levels()` serves every row (`public.level_skills_card`,
  `0411:467-516`), so the page draws a new tile with no change.
- **NPCs get no company level.** `public.level_grant` leaves after one probe of `players.is_npc` (`0411:313-315`). An NPC's only
  level is her hull's (above).
- **The client.** The You page: three bars (Trading, Exploration, Combat) and "Other levels" (`command.lvAll`), the tiles of every
  other served level: `src/features/you/YouScreen.tsx:153-195`. Tiles and a level's detail: `src/live/LevelTiles.tsx`. Names, marks
  and sentences: `src/live/levelWords.ts` (`levelName` at 14-16 falls back to the served word; `MARKS` at 21-41; `perkLine` at 77-79).
  Words: `src/lib/i18n/dict/command.ts` (`lv<Code>`, `lvAct_<activity>`, `lvPerk_<perk>`; EN 68-139, KO 233-302). Command → Levels:
  `src/features/command/levels/Levels.tsx`.

### 1.2 The run's chance: where it is computed, and every reader

**A battle fought tick by tick** (kinds RAID and ATTACK, knob `tick_fight_kinds`):

| What | Where |
|---|---|
| **The formula** | `public.tick_fight`, the block headed `A RUN ENDS IN ITS ROLL`: created `0435:492-510`, rewritten by 0450's third hunk, `0450:226-267`. Each tick, each side: `f_p[s]` = base + sighting lead x 3 points + `a_flee` + level difference x 3 points (most 15) - up to 20 points under half her hull or crew - 5 points a failed attempt, clamped. A raid's side set upon: base 0.10, floor 0.03, cap 0.45. Any other run: 0.15, 0.05, 0.30, no `a_flee` |
| The roll | same block: at the end of a Run's 20 silent ticks (`tick_abilities.RN`, `0435:122`), her keyed draw against `f_p[s]`; event `X`. At most five rolls a fight (ticks 20, 41, 62, 83, 104) |
| `a_flee` | `public.flee_bonus(fleet, foe)`, `0432:103-118`: a speed term and her company's Academy `handling` per cent; frozen on the sheet for a RAID by `public.battle_sheet_freeze` (`0432:150-154`); passed on by `public.tick_battle_run` (`0435:603-605`) |
| What the formula reads of a hull | her card, frozen on the sheet at her first run: `public.battle_hull_card`, `0450:147-178` (`lv`, `crew_need`, and `speed`, `handling`, which the formula does not read yet) |
| Served | the timeline's `rc: {a: [[tick, per cent], ...], b: [...]}`, `0450:272-275`; `world.battle_ticks` also serves every hull's card as `ships` (`0450:289-295`) |
| The Run button | `src/live/battle/timeline.ts:232-244` (`runChanceAt`) → `src/live/battle/BattleScreen.tsx:543-577` ("Run 30%") |
| The log | `src/live/battle/lines.ts:23-50`: the chance of each roll, from its `X` event |
| Who orders a run | the AI of a side whose stance is FLEE (`0435:392-394`); a player's press, `cmd.battle_act` code `RN`, only a fleet that began the fight (`0439:252-254`) |
| Who opens FLEE | a merchant or cargo ship outgunned by the raider (`raid_flee_ratio`, `0432:155-160`); a player's fleet by her standing order (`public.battle_opening_stance`, `0357:519`) |
| The knobs | `raid_flee_base` 0.10, `raid_flee_floor` 0.03, `raid_flee_max` 0.45, `flee_per_level` 0.03, `flee_level_max` 0.15, `flee_hurt_under` 0.5, `flee_hurt_max` 0.20, `flee_per_try` 0.05 (`0450:118-130`); `fight_flee_base` 0.15, `fight_flee_floor` 0.05, `fight_evade_max` 0.30, `fight_evade_per_sighting` 0.03; `raid_flee_per_speed` 0.30, `raid_flee_per_handling` 0.5 (`0432:93-99`) |

The queue's words hold: one formula each tick, `rc` on the timeline, a raid's floor 0.03, cap 0.45, base 0.10, 3 points a level
(most 15), minus 20 crippled or short-handed, minus 5 a failed attempt, the old chance kept as knobs.

### 1.3 Found on the way

1. **The run is rolled in a second place, and it is live.** `public.fight_sides` (the round engine, `0320:175`; its flee rule cut by
   `0432:167-175`) rolls 0357's chance: 15 % + 3 points a point of sighting lead, 5 to 30 %, each round. It is not only the rollback
   engine: `voyage.raid_report` calls it for **a voyage day's raid** (the PIRATES day inside a voyage, for merchants and players),
   and a company's FLEE standing order runs there by that rule; `public.fight_flee_chance` (`0353:443`) is its read, and
   `world.raid_read` (`0353:743`) prints it as poor / fair / good beside the order's picker. 0450 did not touch it. At 15 % a round
   for six rounds about 6 in 10 would get clear there (the rule's own arithmetic, 1 - 0.85^6; not measured), against 1 in 10 in a
   battle. **This slice does not touch it either** (section 6).
2. **Today's speed term is the same for every runner.** `public.flee_bonus` reads `voyage.fleet_speed`, which since 0422 multiplies a
   pirate's speed by 4.5 (`fleet_speed_by_kind`, `0422:231`): the map's pace, by the owner's order. So her speed / theirs - 1 is under
   -0.7 for anyone, and the speed term sits on its floor, -0.15. On the chain's world every pair tried gave `a_flee` -0.1500 (the
   0450 dev-log read -0.15 to -0.09 on prod: the rest is the Academy's handling). A faster ship buys nothing today. The hull's own
   speed (`world.ship_stats`, the figure a ship's card prints) was left as it was by 0422, on purpose.
3. **The game already has a rule for how a hurt ship sails.** `voyage.ship_speed_at` (`0203:443-446`): speed x (`hull_speed_floor`
   0.60 + 0.40 x hull left) x (`crew_short_speed_mult` 0.70 when her crew is under what her class needs) x (1 - `load_speed_penalty`
   0.25 x how full she is). 0450's "minus 20 points under half" is a second rule for the same thing.
4. **A RAID battle raises no level today.** Combat is counted from a voyage's PIRATES days only (`public.player_progress`).
5. **A player's ship is the last a pirate picks.** `public.raid_target` (`0427:132`, order cut by `0432:143-145`) sorts the world's
   ships before any player's and looks at eight. A player is set upon only where fewer than eight of the world's ships are within
   360 miles of the pirate. How often that is on prod is not known here (appendix B, read B2).
6. **The pirates' ships are fast.** A Raider is a `brigantin` (20.4 kn, handling 92), a Corsair a `xebec` (19.5, 90); a Squadron
   and a Dread sail three xebecs beside a slow flagship (0451's ladder). A merchant's Caravela latina makes 18.0 / 75, a Nau 13.2 / 45,
   a new player's Barca 15.0 / 70. Pirate hulls carry no gear and are all level 5.

## 2. The skill

| | |
|---|---|
| **Name** | **Evasion / 회피**. Code `evasion`. The owner's own word; no label in the game uses 회피 yet. (Near miss, EN only: Combat's activity "Evade pirates", `command.lvAct_evaded`. If it confuses, the next best pair is Escape / 탈출) |
| **Kind** | a company's level raised by doing: row eleven of `public.level_skills`, `kept = 'book'`, `day_cap` 300. Not an Academy skill, not a new system |
| **Range** | 1 to 20, the one curve: level 2 at 25 experience, 5 at 400, 10 at 2,025, 20 at 9,025 |
| **Where it shows** | the You page under "Other levels" and Command → Levels: its tile, experience, what raises it, what each level gives, the table (all served; the page needs no code). In a fight: on each ship's card (section 5.5). The arrival card and History name it when it rises |

### 2.1 How it is earned

Only one thing raises it: **her fleet is set upon by a pirate's raid (a RAID battle) and runs.**

| Activity (`level_activities`) | Experience | When |
|---|---|---|
| `run_away`: a pirate raid escaped by running | **40** | the battle closed with `fled` (her run's roll got her away) |
| `run_try`: a run from a pirate raid that failed | **5 each** | every roll of her run that did not get her away (at most five a fight) |

- Granted once, at the battle's close, in `public.raid_close` (the one place a raid's end is settled, under the battle's lock), by
  `public.level_grant` with the keys `run_away:<battle>` and `run_try:<battle>`. The rolls are counted from the result itself
  (a window she ran in carries `flee`), so it holds for the tick engine and for the round engine alike.
- A raid she runs from is worth 5 to 60 (four failed rolls and the fifth away). About 30 on average for a beginner and 40 for a
  master (27 to 43 in the fights of 4.1: a beginner fails more rolls, a master gets away sooner). Level 5 is about 15 raids, level 10
  about 60, level 20 about 250; at the limit of 300 a day, level 20 is 30 days at the least.

**Why it cannot be farmed cheaply:**
- A raid cannot be made. The pirate picks her prey, the world's ships first (1.3, item 5).
- Only the side set upon earns. A fleet that attacks and then runs earns nothing (that would be free: attack an unarmed merchant, press Run).
  A fleet that joined a fight cannot order a run at all (0439).
- Every roll costs 12 seconds of silent guns under fire, and a failed fight costs cargo, crew and hull as today.
- Once a battle; five minutes of peace between two raids on a fleet (0432); 300 a day, as every level.
- A merchant earns nothing (`level_grant`'s first probe; and the hook stands inside `raid_close`'s players-only block).
- Nothing for an escape without running (the raider broke off, or she slipped away unseen): that is not this skill.

### 2.2 What it gives

- **Each level above 1: her side sails 10 % better in a chase** (level 5: +40 %, level 10: +90 %, level 20: +190 %). Nineteen steps in
  `public.level_perks` (perk `run`, unit `pct_more`, amount 10, levels 2 to 20), so the page lists it with the mechanism that lists
  every other benefit, and `level_perks_on` false switches it off with the rest.
- And the Reputation every level gives (10 x the level, once).

### 2.3 What NPCs have

**Her hull's level stands for her Evasion level**: `public.ship_level`, so a merchant 1 to 5 as she was founded, a cargo ship, a navy
ship and a pirate 5 (`npc_ship_level`). No new data, no new knob, nothing to keep in step. With `levels_bite` off every NPC is 1.
So a pirate chases at Evasion 5: a new player is behind her until level 5, level with her at 5, well ahead by 10.

## 3. The formula

One rule for every run (the side set upon in a raid, and the side that closed), computed each tick as the fight stands, in the block
of `public.tick_fight` where the chance is computed today.

```
sailing(ship)  = speed x (hull_speed_floor + (1 - hull_speed_floor) x hull left / her size)      -- 0.6 .. 1.0, the sailing rule's own knob
                       x (crew_short_speed_mult when her crew is under what her class needs)      -- 0.7, the sailing rule's own knob
                       x (1 + chase_per_handling x handling / 100)                                -- handling 100 = +50 %
her sailing    = the LEAST sailing among her hulls afloat that began the fight                    -- a fleet runs as her slowest ship
their sailing  = the MOST sailing among their hulls afloat that are up                            -- one fast ship is enough to hold her
skill(side)    = 1 + (the best `run` among her hulls that are up) / 100                           -- `run` = 10 x (Evasion level - 1), on her card

chance = clamp(chase_floor 0.01,
               chase_base 0.15 x ( her sailing x her skill / (their sailing x their skill) ) ^ chase_power 2
               - her failed attempts in this fight x flee_per_try 0.05,
               chase_cap 0.50)
```

- **Relative by construction.** Only the ratio counts. Make both sides twice as fast and nothing moves; swap the sides and the ratio turns over.
- **Equal sides: 15 % a roll** (`chase_base`). Over a fight her rolls are 15, 10, 5, 1, 1: she gets away in about 3 fights in 10 if nobody hurts her meanwhile.
- **A much better runner usually gets away.** A ratio of 1.83 is the cap, 50 % a roll: 50, 45, 40, 35, 30 is 92 in 100 over a fight;
  a runner further ahead holds 50 through her failed rolls.
- **A crippled runner against a healthy fast pursuer almost never does.** A hull near nothing and a short crew leave her 0.6 x 0.7 =
  0.42 of her sailing, so 0.18 of her chance; behind a faster ship that is the floor, 1 % a roll, at most 5 in 100 over a fight.
- **Floor 1 %, cap 50 %** a roll.
- **Speed** is the ship's own, the figure on her card (`world.ship_stats`: class, roll, gear as worn as it is, Academy skills, captains),
  not `voyage.fleet_speed` (1.3, item 2).
- **Condition is both sides', and it follows the fight.** Her hull falls as she is hit during the 20 silent ticks, so her next roll is
  worse for it; a pursuer hurt before she runs chases worse (her chance x 1.56 with their fastest ship at half her hull).
- **The hull's level is folded in, not stacked.** A level already gives +1 handling (0127), and handling is in the sailing. The separate
  "3 points a level" of 0450 is not in this rule: it would count a level twice (0450's own reason for adding no second to-hit).
- **The crippled penalty is folded in** as the sailing rule's two factors, which the game already uses for a hurt or short-handed ship
  (1.3, item 3): one set of knobs for "how a hurt ship sails", in the voyage and in the chase.
- **Each failed attempt still costs 5 points** (`flee_per_try`, 0450's knob, unmoved).
- **Not in the roll** (decided by default): the sighting lead (it keeps its two jobs: who is caught unready for the first window,
  and the slip before a shot); how full her hold is; the wind (pinned at 1); the number of ships beyond the slowest and the fastest.
- **A ship with no speed on her sheet does not sail**: she cannot run (the floor) and cannot chase (the cap). No second formula stands
  behind this one. A battle opened before the deploy has cards without `run`: both skills read 1, and the rule works on the ships alone.

### 3.1 The knobs

| Knob | Value | What |
|---|---|---|
| `chase_enabled` | true | **the switch.** false: every roll is 0450's chance, to the digit |
| `chase_base` | 0.15 | the chance between equal sides: the one dial for "harder" or "softer" |
| `chase_power` | 2 | how sharply a better or worse ratio counts (the ratio squared) |
| `chase_floor`, `chase_cap` | 0.01, 0.50 | the least and the most a run rolls |
| `chase_per_handling` | 0.5 | what handling 100 adds to a ship's sailing |
| `hull_speed_floor`, `crew_short_speed_mult` | 0.60, 0.70 | read, not moved: the sailing rule's own |
| `flee_per_try` | 0.05 | read by both rules, not moved |
| the steps of perk `run` | 10 at each of levels 2 to 20 | rows of `public.level_perks`: what a level is worth |

**The existing knobs are not moved and not deleted.** `raid_flee_base`, `raid_flee_floor`, `raid_flee_max`, `flee_per_level`,
`flee_level_max`, `flee_hurt_under`, `flee_hurt_max`, `raid_flee_per_speed`, `raid_flee_per_handling` and the frozen `a_flee` are read
only by the old rule from now on: they are the rollback. `fight_flee_base`, `fight_flee_floor`, `fight_evade_max` and
`fight_evade_per_sighting` are also the voyage day's and the round engine's (1.3, item 1), and the last two the slip before a shot.

## 4. Numbers

Made with the real engine (`public.tick_fight` with the hunks of appendix A laid over the live body) on the chain's own world at
head 0451, in memory, `levels_bite` on as prod has it. Fleets made by the game's own hands (`form_fleet`, `commission_ship`); sheets
as the open freezes them (`voyage.fleet_hulls` + `public.battle_hull_card`). Pirates: 0451's ladder, level 5, manned to what their
class needs. Player ships at a roll of 1.000 with no gear unless said. **Every runner opens FLEE** and runs again after each failed roll.

### 4.1 Match-ups: chance at the open, and the share of fights she gets away by running

150 fights a cell, the same seeds for both rules (so a cell is right to about 4 points). "Today" is 0450's rule on the same fights.

| Runner | vs Raider (1 brigantin) | vs Corsair (1 xebec) | vs Dread (kalyon + 3 xebec) | Today, the three |
|---|---|---|---|---|
| **New player**: Evasion 1, Barca, starter sails | 4 % → **9 in 100** | 4 % → **11** | 4 % → **3** | 3 % → 17 / 17 / 3 |
| Evasion 5, Caravela latina | 10 % → **19** | 11 % → **16** | 11 % → **16** | 3 % → 15 / 13 / 13 |
| **Mid**: Evasion 10, Caravela latina | 19 % → **39** | 21 % → **47** | 21 % → **28** | 3 % → 9 / 20 / 12 |
| Evasion 10, Nau (a slow hauler) | 8 % → **19** | 9 % → **16** | 9 % → **15** | 3-4 % → 18 / 15 / 11 |
| Evasion 10, Pinnace (fast, frail) | 27 % → **56** | 30 % → **58** | 30 % → **22** | 3 % → 11 / 10 / 5 |
| **Max**: Evasion 20, Caravela latina | 46 % → **92** | 50 % → **96** | 50 % → **66** | 3-9 % → 18 / 24 / 9 |
| Evasion 20, Nau | 20 % → **37** | 22 % → **46** | 22 % → **47** | 12-21 % → 28 / 44 / 25 |
| Evasion 20, Balinger (fast) | 50 % → **91** | 50 % → **89** | 50 % → **83** | 12-21 % → 33 / 41 / 22 |
| **Crippled**: Evasion 10, Caravela latina at a quarter of her hull | 9 % → **17** | 10 % → **13** | 10 % → **5** | 3 % → 15 / 10 / 1 |
| Evasion 10, Caravela latina, half the crew she needs | 9 % → **15** | 10 % → **25** | 10 % → **15** | 3 % → 11 / 18 / 13 |
| Evasion 10, Nau at a quarter of her hull and half her crew | 2 % → **2** | 2 % → **2** | 2 % → **8** | 3 % → 11 / 11 / 10 |
| **NPC merchant**: Caravela latina, hull level 2 | 6 % → **11** | 7 % → **13** | 7 % → **9** | 3 % → 14 / 13 / 12 |
| NPC merchant: Nau, hull level 1 | 2 % → **9** | 2 % → **6** | 2 % → **4** | 3 % → 14 / 14 / 15 |
| NPC merchant: Barca, hull level 1 | 3 % → **8** | 4 % → **7** | 4 % → **3** | 3 % → 15 / 14 / 5 |
| NPC cargo ship: Navire, crown hull level 5 | 5 % → **11** | 6 % → **9** | 6 % → **7** | 3-7 % → 17 / 14 / 8 |

How to read it:
- **A Raider chases best.** Her brigantin is the fastest and handiest pirate hull, so the chance at the open is a little lower against
  her than against a Corsair. A Dread squadron chases as her xebecs do, no better: what makes her deadly is her guns. A runner is shot
  to pieces during the silent ticks (against a Dread a Barca has 1 % of her hull left at the end, a Caravela latina 12 to 50 %), so
  her later rolls fall and many fights end before the second roll.
- **Today everyone rolls the floor, 3 %,** and gets away by having five tries: 9 to 18 in 100, whatever the ship or the level, unless
  her hull is many levels above a pirate's. That is what the owner's order replaces.
- **A slow ship stays hard to save.** Evasion 20 in a Nau gets away 4 times in 10: the skill doubles and redoubles her chance, but a
  Nau sails at 56 % of a xebec. Speed and handling count as the owner said.
- A new player is a little worse off than today (9 to 11 in 100 against 17) until about level 5.

The same figures from the formula, for the ships of the table (no gear, against a Corsair's xebec at level 5):

| Her ship | speed / handling | her sailing / theirs | squared |
|---|---|---|---|
| Nau | 13.2 / 45 | 0.56 | 0.32 |
| Barca | 15.0 / 70 | 0.71 | 0.50 |
| Caravela latina | 18.0 / 75 | 0.86 | 0.75 |
| Pinnace | 20.1 / 92 | 1.02 | 1.05 |
| Balinger | 21.9 / 98 | 1.14 | 1.30 |

| Her Evasion level against a pirate's 5 | 1 | 3 | 5 | 8 | 10 | 15 | 20 |
|---|---|---|---|---|---|---|---|
| her skill / theirs, squared | 0.51 | 0.73 | 1.00 | 1.47 | 1.84 | 2.94 | 4.29 |

Chance at the open = 15 % x the ship's figure x the level's figure. (Evasion 10 in a level-5 Caravela latina: 15 x 0.77 x 1.84 = 21 %, as the engine served.)

| Her state | sailing left | her chance x |
|---|---|---|
| whole, manned | 1.00 | 1.00 |
| half her hull | 0.80 | 0.64 |
| a quarter of her hull | 0.70 | 0.49 |
| short-handed | 0.70 | 0.49 |
| a quarter of her hull and short-handed | 0.49 | 0.24 |
| the pursuer's fastest ship at half her hull | (theirs 0.80) | 1.56 |

### 4.2 The overall escape rate, against today's

**The 100 frozen prod sheets were not replayed.** The method's tools are in the repo (`scripts/ops/harness/battle-stats/prod-sheets.sql`,
`replay.mjs`), but the sheets are a prod read, the file is not on this PC, and this design made no prod read. Appendix B gives the
lead the read; 5.7 gives the builder the replay. What stands in for it here:

**A stand-in on the chain's own world:** 300 of its 861 real merchant fleets (their own classes, rolls, gear and founded levels; of
their 912 hulls 53 % are Caravela latinas, 20 % Naus, 18 % Barcas), each set upon by a pirate drawn by the roster's mix of ranks (40 brigantin Raiders, 18 fusta
Raiders, 25 Corsairs, 20 Consorts, 10 Squadrons, 8 Dreads of 121), opening by 0432's own rule. 110 of the 300 opened FLEE (prod's
sheets: 39 of 100). Each of the 110 fought ten times a rule, the same seeds: 1,100 fights a line.

| Rule | got away by running | chance at the open (min / median / max) |
|---|---|---|
| **today (0450)** | **13.6 in 100** (prod's own 100 sheets: 4 of 39) | 3 / 3 / 9 % |
| **proposed** (`chase_base` 0.15) | **10.1 in 100** | 3 / 7 / 10 % |
| harder: `chase_base` 0.10 | 7.3 | 2 / 4 / 6 % |
| softer: `chase_base` 0.20 | 13.5 | 4 / 9 / 13 % |
| softer still: `chase_base` 0.25 | 16.7 | 4 / 11 / 16 % |
| flatter: `chase_power` 1 | 16.3 | 6 / 10 / 12 % |
| steeper: `chase_power` 3 | 6.9 | 1 / 4 / 8 % |
| today's floor kept: `chase_floor` 0.03 | 16.2 | 3 / 7 / 10 % |

- **Expected: the world's runners get away about 1 in 10, as today.** The stand-in puts today's rule a little higher than prod's own
  sheets did (13.6 against 4 of 39, which is 10 give or take 5), and the proposed rule at 10.1. `chase_base` 0.20 holds the
  stand-in's "today" exactly. The fights that do not run are not touched by the rule.
- **Who gets away changes.** Of 74 Caravela latinas that ran once each, 7 got away today and 6 proposed; of 13 Naus, none either way;
  the chance at the open is 7 to 10 % for a Caravela latina and 3 to 4 % for a Nau, where today it is 3 % for both.
- A raider alone rarely makes a merchant run (she is not outgunned by one brigantin): the 110 ran from Consorts, Corsairs, Dreads and Squadrons.
- **For a player the rate is her own doing:** 1 in 11 untrained in a Barca, 4 in 10 at Evasion 10 in a Caravela latina, 9 in 10 at
  Evasion 20, 1 in 50 crippled in a Nau.

## 5. The slice plan (for the builder)

One PR: migration 0452, proof 155, three proofs amended, the client's words and one stat, specs, docs. Deployed with `~/bin/bv-deploy.sh <pr>`.

### 5.1 The migration

- **Number:** prod head + 1. The head is 20260818000451 as the queue says, so `20260818000452_a_run_is_a_chase.sql`; read the head
  again first (`select max(version) from supabase_migrations.schema_migrations`), and take the next number if the queue moved.
- **Shape:** one `do` block as 0450 (`statement_timeout` 45 s, `lock_timeout` 5 s, fails above 30 s): guard, pre-image digests, data,
  knobs, new functions, hunks (each once, each reversing), self-assert, news, probe rolled back by a raised sentinel.
- **Guard:** refuses if `chase_enabled` exists (applied once); refuses if `public.battle_hull_card(uuid)`, `public.level_perk(uuid,text)`
  or the knob `flee_per_try` is missing (0417 / 0450 not in this world), or if `level_skills` already holds order 11.

### 5.2 Tables, rows, knobs (no table, no column, no job, no index)

| What | Rows |
|---|---|
| `public.level_skills` | `('evasion', 11, 'Evasion', 'book', 300)` |
| `public.level_activities` | `('run_away', 'evasion', 1, 'A pirate raid escaped by running', 'each', 40, 1, ...)`, `('run_try', 'evasion', 2, 'A run from a pirate raid that failed', 'each', 5, 1, ...)`; no knob, no `most_xp`, not `once`, not `at_gain` |
| `public.level_perks` | `('run', L, 'evasion', 'pct_more', 10, 'Runs better')` for L = 2 .. 20 (19 rows) |
| `public.world_config` | `chase_enabled` true, `chase_base` 0.15, `chase_power` 2, `chase_floor` 0.01, `chase_cap` 0.50, `chase_per_handling` 0.5, each with its description |

The header lines the database budget asks for (the spec asks nothing of this file: it creates no table and schedules nothing; they are written anyway, as 0450's are):

```
-- LOAD: -- budget: no table, no job, no cron, no index. Rows: at most 2 level_book rows and 1 level_xp row at the close of a RAID on a PLAYER'S ship
--   (public.level_grant), none for a ship of the world: under 1 row a minute at ~100 raids an hour, nearly all on the world's ships. A level crossed is one
--   event and one Reputation row, 19 times ever a company. The sheet carries ~20 bytes more a hull (`ev`, `run`); the timeline nothing more. The engine: one
--   more loop over the hulls a tick, eight knobs read once a fight. At a battle's open: one more indexed read a hull (players, level_xp or ship_xp, level_perks).
-- RETENTION: -- retention: none new. public.level_book is 0411's (append-only, bounded by the level's cap a day); the card lives and dies with its battle row.
```

### 5.3 New functions (server-only: `revoke all ... from public, anon, authenticated`; STABLE, SECURITY DEFINER, `search_path = public, pg_temp`)

- **`public.level_perk_at(p_perk text, p_level int) returns numeric`**: what a benefit's steps are worth at a level: the sum of
  `level_perks.amount` at or below it; 0 while `level_perks_on` is false. `public.level_perk` reads a company's level into it (one hunk
  below), so the sum is written once.
- **`public.evasion_of(p_ship uuid) returns jsonb`**: `{ev, run}`: the Evasion a hull sails with, the one reading for the sheet. `ev`:
  a company's ship: `level_from_points` of her company's `level_xp` row for `evasion` (1 with none); a ship of the world
  (`players.is_npc`): `public.ship_level(ship)`. `run`: `public.level_perk_at('run', ev)`. No such ship: `{}`.

Both bodies are in appendix A, as tried.

### 5.4 The hunks: seven, over four live bodies, each once, each reversing

Tried on the live bodies of the chain at head 0451: each OLD text occurs once, the new body compiles, each NEW text occurs once, and
the reverse is the pre-image, byte for byte. Appendix A has the texts. Read them once each on prod before the PR (5.8).

| # | Body | What the hunk does |
|---|---|---|
| 1 | `public.tick_fight(uuid,jsonb,jsonb,jsonb)` | declarations after `c_ptry`: three arrays a hull (speed, handling, `run`), three a side, the eight knobs read once |
| 2 | same | reading a hull: `speed`, `handling`, `run` from her card (after `h_need[n]`) |
| 3 | same | each tick, after 0450's `f_lv` loop: each side's skill, her slowest sailing (to run) and her fastest (to chase) |
| 4 | same | after 0450's `f_p[s] := ...` statement, which stands untouched: `if c_chase then f_p[s] := <the chase> end if;` The roll, `rc`, the `X` event and the failed-attempt count below it read `f_p[s]` as before |
| 5 | `public.battle_hull_card(uuid)` | the card gains `ev` and `run`: `... || public.evasion_of(s.id)` after the `caps` key. `tick_battle_run` already freezes the card once a hull; `world.battle_ticks` already serves it whole |
| 6 | `public.raid_close(uuid,jsonb,timestamptz)` | inside `if v_human then`: the two `perform public.level_grant(...)` lines |
| 7 | `public.level_perk(uuid,text)` | its last statement returns `public.level_perk_at(p_perk, public.level_from_points(v_xp))` |

**Not touched:** `public.battle_sheet_freeze`, `public.flee_bonus` and `sheet.a_flee` (the old rule and the round engine read them),
`public.tick_battle_run`, `world.battle_ticks`, `public.fight_card`, `public.fight_sides`, `public.fight_flee_chance`, `world.raid_read`,
`public.level_grant`, `public.level_skills_card`, `world.levels`, every sailing function.

**Self-assert** (the file's own; only its own probe rows; nothing deleted from an append-only table, the probe is rolled back):
1. Every hunk once and reversing; grants, volatility, definer, search path and owner of the four bodies unmoved; no other function
   moved; the two new functions not open to clients; the rows and the knobs are this file's.
2. `public.level_perk` after its hunk: for a probe company at each level 1 to 20 of each existing perk, the same figure as the steps' sum.
3. **The engine on a fixed sheet** (pure, as 0450's: hulls written in the file, with `speed`, `handling`, `run`, `crew_need`):
   - `chase_enabled` false, in a rolled-back block: every event and the result are the fight as it was BEFORE the hunks (fought first, kept).
   - lit, two hulls of speed 18 and handling 80: equal and whole, 15 at tick 0; her `run` 40 against 0: 29; 0 against 40: 8; `run` 190
     against 40: the cap, 50; half her hull: 10; short-handed: 7; a 13.2 / 45 ship against a 19.5 / 94 one: 5; both sides' speed
     doubled: 15 still; no speed on her sheet: the floor, 1; every roll is the chance served for its tick; each roll after a failed
     one is 5 lower or the floor. (These are the figures the prototype's engine served.)
   - the two sailing factors are the sailing rule's: for a probe ship at half her hull and under her crew, with an empty hold,
     `voyage.ship_speed_at(ship, 0)` over her `world.ship_stats` speed (and `wind_mult_v0`) equals the factor the engine used.
4. **The probe**, rolled back: a company with Evasion experience and a merchant: `public.evasion_of` answers her level and its steps'
   sum, and the merchant's hull level; a RAID row between a pirate-made fleet and the company's is run: its sheet's cards carry `ev`
   and `run`, a second run moves no card; closed through `public.battle_resolve`: the book holds `run_try` x her failed rolls and
   `run_away` when she fled, each once; closed again: nothing; a merchant set upon: no row.
5. News (0347's law), one call: `public.news_update('0452', 'New level, Evasion: running from a fight takes skill, speed and handling, hers against theirs', '새 레벨 회피: 도주는 내 기술, 속도, 조종성과 상대의 것을 견준다')`.

**In flight at the deploy:** a battle being fought keeps its timeline. If a join or a press re-runs it within its 75 seconds, the
re-run is under the new rule from tick 0 (as 0450 decided for itself): its cards have no `run`, so the ships alone decide.

### 5.5 The client

| File | Change |
|---|---|
| `src/lib/i18n/dict/command.ts` | EN: `lvEvasion: 'Evasion'`, `lvAct_run_away: 'Escape a pirate raid by running'`, `lvAct_run_try: 'A run that fails'`, `lvPerk_run: 'Runs {n}% better'`. KO: `'회피'`, `'도주로 해적 습격 탈출'`, `'실패한 도주'`, `'도주 능력 {n}% 증가'` |
| `src/live/levelWords.ts` | `MARKS.evasion`: a mark in the kit's stroke (a hull turning away with her wake); without it the tile shows the default wreath |
| `src/lib/rpc/types.ts` (`BattleShipCard`, 4752) | `ev?: number` (her Evasion level), `run?: number` (what it is worth, per cent) |
| `src/live/battle/ShipsPanel.tsx:88-98` | one more `Stat` in the card's grid: Evasion, `card.ev`, the word `command.lvEvasion` (one word for one thing) |
| the Run button (`BattleScreen.tsx:543-577`), the log (`lines.ts`), `runChanceAt` | **no change**: they print the server's `rc` and `X` |
| the You page, Command → Levels, the arrival card, History | **no change**: they draw what is served and name it through `levelName` |
| `tests/levels.tiles.spec.ts` | `CODES` gains `evasion` (eleven tiles; eight small ones on the You page) and its words |
| `tests/battle.screen.spec.ts`, `tests/battleTicks.fixture.ts` | a card with `ev`; the stat is seen; the Run chance read from `rc` as before |

An old client between the push and the publish shows the tile with the server's English words and the default mark, and ignores `ev`.

### 5.6 Proofs

- **New: `scripts/db/proofs/155_a_run_is_a_chase.sql`** (153 and 155 are free). Markers:
  `EV_PAGE` (`world.levels()` serves eleven levels, Evasion last, its two activities, nineteen steps);
  `EV_CARD` (a company's ship carries her company's level, a merchant's her hull's, a pirate's 5; frozen: a level gained after the open moves no card);
  `EV_EQUAL` (equal sides roll `chase_base`);
  `EV_RELATIVE` (both sides scaled: the same chance; skill, speed and handling each move it as the formula says, on either side);
  `EV_STATE` (a hurt or short-handed runner by the sailing rule's two factors; a hurt pursuer raises her chance; it follows the hull tick by tick);
  `EV_BOUNDS` (never under the floor or over the cap; no speed: the floor);
  `EV_TRIES` (each failed roll 5 lower);
  `EV_XP` (a real raid on a company's fleet through `public.battle_open` and `public.battle_resolve`: 5 a failed roll, 40 for the escape, once; the limit a day holds);
  `EV_NO_FARM` (a merchant set upon, a company that attacked and ran, and a second close grant nothing);
  `EV_OFF` (`chase_enabled` false: 0450's chance on the same sheet; `level_perks_on` false: every `run` is 0).
- **Amended:** proof **152** sets `chase_enabled` false in its own scene and says so: from 0452 on it proves the rollback's rule
  (`BS_LEVEL`, `BS_HURT`, `BS_BOUNDS`, `BS_TRIES`, `BS_OLD`), as the round engine's proofs set `tick_fight_kinds` to `[]` since 0435.
  Proofs **136** (lines 41-42, 138) and **140** (line 192) hold a roll within `raid_flee_floor` .. `raid_flee_max`: they read
  `chase_floor` .. `chase_cap` while `chase_enabled` is true. Proofs 107, 113 and 133 are not touched by the rule (113 counts the
  steps against the table; 133 drives the round engine).
- **Checks (lean):** `tsc`, `eslint`, `vite build`, the specs touched, and on the cached chain the proofs that read a level or fight
  a tick battle: 107, 113, 136, 137, 140, 146, 147, 150, 152, 154 and 155 (146, 147, 150 and 154 name no run and no escape, read
  here by their text only: a tick fight in which a side runs may now roll differently). No from-zero replay.

### 5.7 The harness (`scripts/ops/harness/evasion/`, as `battle-stats/`)

- `gen-checks.mjs` → `check.sql` (the PROD CHECK, the same read before and after) and `rollback-0452.sql` (a draft), both written
  from the migration's own hunks.
- `replay.mjs`: `battle-stats/replay.mjs` with these arms: `0450` (`chase_enabled` false), `PROPOSED`, `chase_base` 0.10 and 0.20.
  Each hull keeps her whole frozen card (sheets since 0450 carry `speed`, `handling`, `lv`, `crew_need`) and gets what 0452 would
  freeze: `ev` = her card's `lv` for a ship of the world (both sides of a raid on a MERCHANT or CARGO_SHIP), 1 for a company's hull
  (nobody has Evasion experience before the deploy); `run` = 10 x (`ev` - 1). **Run it on the lead's sheets before the PR**, and put
  its table in the dev-log beside 4.2's stand-in.
- `docs/dev-log/<date>-evasion.md`, with the measurements; `docs/LEVELS.md` (the level's entry and step table; section 5 there says
  three fight levels wait: Evasion is the first fight level built); `docs/design/tick-combat.md` section 6 (the run's rule) and 9.2
  (`ev`, `run` on a hull's card).

### 5.8 PROD CHECKS (read-only, one statement a file, the gate green first, one prod reader at a time)

**Before the PR's deploy** (`evasion/check.sql`):
1. `scripts/ops/harness/db-health/gate.sql`: green.
2. The head is 20260818000451 (or the migration is renumbered).
3. Each of the seven OLD texts occurs exactly once in the live bodies; each NEW text 0 times.
4. Nothing of this file is there: no `evasion` in `level_skills` (its highest order is 10), no perk `run`, no activity `run_away` or
   `run_try`, no `chase_*` knob, no `public.level_perk_at`, no `public.evasion_of`.
5. The knobs the design leans on, as prod has them: `levels_bite`, `level_skills_on`, `level_perks_on`, `npc_ship_level`,
   `npc_ship_level_enabled`, `hull_speed_floor`, `crew_short_speed_mult`, `tick_fight_kinds`, `raid_flee_ratio`, `raid_orders_enabled`,
   every `raid_flee_*`, `flee_*`, `fight_flee_*`, `fight_evade_*`, and `tick_abilities.RN` (cd 20, for 20).
6. The hour's raids, written down: how many, how many opened FLEE, how many got away by running, the rolls' chances (min / median /
   max), every hull of every sheet has `speed`, `handling`, `lv` and `crew_need`, none stuck FIGHTING, the beat.
7. The reads of appendix B (the 100 sheets for the replay; how often a player's ship is the one set upon).

**After, at 30 minutes** (a fight change): the same `check.sql`, and `scripts/ops/harness/raid/after-check.sh <start> <end>` for the
beat and the jobs. Wanted: head 0452; every NEW text once; the knobs; every battle opened since the deploy has `ev` and `run` on each
hull; every roll within 1 .. 50; of the runners about 1 in 10 away as before (4.2: 13.6 → 10.1 in the stand-in), chance at the open
median about 7 where it was 3; no raid stuck; a raid's length as before (75 s at most); the beat no worse; `level_xp` rows for
`evasion` only for companies that were raided and ran. **Fail lines, each a rollback by the knob:** the beat over 2 s; a raid stuck
FIGHTING; a roll outside 1 .. 50; of 30 or more runners none away, or more than 3 in 10.

### 5.9 Rollback (forward, owner only)

- **Quick, one knob:** `chase_enabled` false. Every new roll, and every re-run, is 0450's chance to the digit (the file's self-assert
  and proof 152 prove it). The level, its experience and its tile stay; what was earned is kept.
- **Softer or harder, not off:** `chase_base` (4.2's table); `chase_power`; the steps of perk `run`.
- **Whole:** the seven hunks reversed, `public.evasion_of` and `public.level_perk_at` dropped, the knobs and the perk steps deleted.
  The level's row and its activities stay if any company holds experience in it (`level_book` is append-only); 0411's rollback draft
  leaves what was earned in place the same way.
- **The debt this leaves, and when it is paid:** the old rule (0450's statement and its nine knobs, `public.flee_bonus`, `sheet.a_flee`,
  the switch itself) stays in the body only as the rollback. It is one rule kept beside its replacement, which the no-spaghetti
  law does not allow for long. **The next slice that cuts the fight deletes it** (the statement, the knobs, the bonus, proof 152's five
  markers), once the owner has kept the chase for a week. It is written here so that it is not forgotten.

## 6. Risks, and what is not verified

**Not verified (stated plainly):**
- **Nothing on production.** The knobs' values there (`levels_bite` true is the 0450 dev-log's word), that prod's live bodies are
  the chain's (0450's check held this on 2026-11-15; the seven OLD texts must be read again), how many companies play.
- **The 100 prod sheets were not replayed**, so the overall rate is a stand-in's (4.2). The stand-in's merchants are the chain's own,
  not the ones pirates meet on prod; its pirates are drawn by the roster's fleet counts, not by who raids most.
- **How often a player's ship is raided.** If the read B2 shows it is rare (under about one raid a day for an active company), the
  level will barely move, whatever the experience figures: then raise `run_away` and `run_try` (rows, no code), or bring the voyage day
  in (below). Until that read is in, how fast the level rises on prod is not known.
- **The client** was designed by reading, not built: the four words, the mark, the one stat, the two specs. The Korean wording is a first cut.
- **Cost.** A fight took 35 to 44 ms in PGlite here, the same with and without the hunks, on a machine busy with other jobs. The 0435
  dev-log says 5.2 ms; that was before 0450 and on a quiet machine. Not re-measured quiet.
- **Pirates' hands.** The table mans each pirate to what her class needs. A short-handed pirate chases at 0.7.
- The table's player ships are at a roll of 1.000 with no gear; a real ship has her own roll (1.00 to 1.09 for speed among the
  chain's merchant hulls) and wears gear that moves speed and handling (Starter Sails: +0.9 knots, -4 handling).

**Risks:**
1. **The voyage day's run is a different rule** (1.3, item 1) and stays so: a company with a FLEE standing order still gets clear
   about 6 times in 10 on a PIRATES day of a voyage, with no skill, while a battle is now a chase. This slice does not make it worse,
   and does not fix it. **Slice 2, if the owner wants one rule everywhere:** the voyage day's flee reads the same chase (her fleet
   against the raider class's hulls, `fight_raider_class`), and its escapes raise the same level. That makes fleeing on a voyage day
   much harder than it is, which is a change to live play the owner should order, not a default. This block of `tick_fight` reads only
   two sides' figures, the attempts and its knobs, so it lifts whole into one function both engines can call.
2. **Slow haulers lose.** A Nau's chance at the open goes from 3 % to 2 % as a merchant and stays low at any level (4.1). A trader in
   a slow ship must fight, pay, or fit sails. That is the owner's "along with speed", but it will be felt.
3. **A new player is a little worse off than today** until about level 5 (9 to 11 in 100 against 17), because today's floor of 3 %
   five times over is worth more than a low first roll. `chase_floor` 0.03 would give it back to everyone, crippled ships too (the
   world's runners would then get away 16.2 in 100, 4.2).
4. **A skilled friend lends her skill.** A side's skill is the best among her ships that are up, so a company that joins a merchant's
   defence (0436), or a navy ship called to it, lifts the merchant's run. Decided by default as fair ("she covers the retreat"); it is
   also the same rule for the side that chases.
5. **`raid_flee_ratio` is unmoved:** a ship of the world still opens FLEE when outgunned, even at 2 %. A Nau that runs is plundered
   as before; whether she should fight instead is the owner's knob (0450's "not done").
6. **A re-run re-rolls the past under the rule in force.** Flipping `chase_enabled`, or the deploy itself, changes the earlier rolls
   of a battle that is then re-run by a join or a press (75 seconds at most). 0450 had the same edge.
7. **One name near another:** "Evasion" beside Combat's "Evade pirates" (2, the name row).
8. **`level_perks_on` false** switches off Evasion's benefit together with the seven others (then every `run` is 0 and the ships alone
   decide). It is not the switch for this slice: `chase_enabled` is.

## 7. Every choice, decided by default

1. The name: Evasion / 회피, code `evasion`.
2. It is a company's level raised by doing (0411's kind), the eleventh, 300 a day, level 1 to 20 on the one curve.
3. Earned only as the side set upon in a pirate's RAID: 40 for the run that gets away, 5 for each failed roll, once a battle.
4. Nothing for an attacker's run, a joiner, a voyage day, an escape without running, a merchant.
5. It gives 10 % a level above 1 on her side's sailing in a chase (steps in `level_perks`), and the Reputation every level gives.
6. A ship of the world: her hull's level stands for her Evasion level.
7. The rule is a ratio, squared: 15 % between equal sides, floor 1 %, cap 50 %, minus 5 points a failed attempt.
8. Speed is the ship's own (her card), not the map's pace by kind.
9. She runs as her slowest ship afloat that began the fight; they chase as their fastest ship afloat.
10. Handling counts half (handling 100 = +50 %).
11. Condition is the sailing rule's own two factors (hull 0.6 to 1.0, short-handed 0.7), on both sides, as the fight stands.
12. The hull's level counts through handling only; the "3 points a level" is not in the chase.
13. The sighting lead, the hold's fill and the wind are not in the roll.
14. One rule for every run, whoever runs.
15. A side's skill is the best among her ships that are up.
16. A ship with no speed on her sheet cannot run and cannot chase; there is no fallback to another formula.
17. The old rule stays behind `chase_enabled` as the rollback, and a later slice deletes it.
18. Proof 152 proves the rollback's rule from now on.
19. The voyage day's flee and the round engine are not touched.
20. On the battle screen: Evasion on each ship's card; the Run button and the log as they are.
21. `public.level_perk` is cut once so that the steps' sum is written in one place.

## Appendix A: the code as tried

Laid over the live bodies of the chain at head 0451 (in memory), compiled, and run: section 4's figures and the checks of 5.4 come
from exactly this. The builder re-cuts each hunk from prod's body (`pg_get_functiondef`, LF) and holds it to these texts.

### A.1 The two new functions

```sql
create function public.level_perk_at(p_perk text, p_level int)
returns numeric language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0452: WHAT A BENEFIT'S STEPS ARE WORTH AT A LEVEL (public.level_perks: the sum of the steps at or below it). 0 while level_perks_on is false.
  -- public.level_perk reads a company's level into it; public.evasion_of reads a hull's.
  select case when public.wc('level_perks_on') = 'true'::jsonb
              then coalesce((select sum(k.amount) from public.level_perks k where k.perk = p_perk and k.level <= p_level), 0)
              else 0 end
$body$;

create function public.evasion_of(p_ship uuid)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0452: THE EVASION A HULL SAILS WITH, the one reading for a battle's sheet (public.battle_hull_card): ev the level, run what it is worth in a chase,
  -- per cent (public.level_perk_at 'run'). A company's ship: her company's Evasion level (public.level_xp on the one curve; 1 with no experience).
  -- A ship of the world (players.is_npc): her own hull's level (public.ship_level: a merchant 1 to 5 as founded, a crown's or a pirate's npc_ship_level),
  -- since the world's houses earn no experience (0411). No such ship: nothing.
  select coalesce((
    select jsonb_build_object('ev', z.ev, 'run', public.level_perk_at('run', z.ev))
      from (select case when p.is_npc then public.ship_level(s.id)
                        else coalesce((select public.level_from_points(x.xp) from public.level_xp x where x.player_id = s.player_id and x.skill = 'evasion'), 1) end as ev
              from public.ships s join public.players p on p.id = s.player_id where s.id = p_ship) z), '{}'::jsonb)
$body$;
```

### A.2 `public.tick_fight`, four hunks

Hunk 1, OLD:
```
  c_ptry   numeric := coalesce(public.wc_num('flee_per_try'), 0);
begin
```
NEW:
```
  c_ptry   numeric := coalesce(public.wc_num('flee_per_try'), 0);
  -- 0452: THE CHASE. Each hull's speed and handling and what her Evasion level is worth (her card); each side's sailing as the fight stands; the knobs, once a fight.
  h_spd    numeric[] := '{}';
  h_hdl    numeric[] := '{}';
  h_run    numeric[] := '{}';
  f_slow   numeric[];
  f_fast   numeric[];
  f_skill  numeric[];
  f_one    numeric;
  c_chase  boolean := coalesce(public.wc('chase_enabled') = 'true'::jsonb, false);
  c_cbase  numeric := public.wc_num('chase_base');
  c_cpow   numeric := public.wc_num('chase_power');
  c_cfloor numeric := public.wc_num('chase_floor');
  c_ccap   numeric := public.wc_num('chase_cap');
  c_chdl   numeric := public.wc_num('chase_per_handling');
  c_hsf    numeric := public.wc_num('hull_speed_floor');
  c_csm    numeric := public.wc_num('crew_short_speed_mult');
begin
```

Hunk 2, OLD (one line and its line end):
```
      h_need[n]  := greatest(0, coalesce((x ->> 'crew_need')::numeric, 0));   -- 0450: the crew her class needs (none on the sheet: her crew is never short)
```
NEW: that line, then:
```
      h_spd[n]   := greatest(0, coalesce((x ->> 'speed')::numeric, 0));       -- 0452: her speed and handling (her card, 0450), and what her Evasion level is worth, per cent (her card's run)
      h_hdl[n]   := greatest(0, coalesce((x ->> 'handling')::numeric, 0));
      h_run[n]   := greatest(0, coalesce((x ->> 'run')::numeric, 0));
```

Hunk 3, OLD:
```
      f_lv := array[1, 1];
      for i in 1 .. n loop
        if h_up[i] then f_lv[h_side[i]] := greatest(f_lv[h_side[i]], h_lvl[i]); end if;
      end loop;
```
NEW: those four lines, then:
```
      -- 0452: EACH SIDE'S SAILING, as the fight stands. A hull afloat sails at her speed x what her hull leaves of it (hull_speed_floor, the sailing rule's own knob) x
      -- crew_short_speed_mult when she is short-handed x (1 + chase_per_handling x her handling / 100). To RUN a side sails as her slowest hull that began the fight;
      -- to CHASE, as her fastest hull that is up. Her skill is the best Evasion benefit among her hulls that are up.
      f_slow := array[null, null]::numeric[]; f_fast := array[0, 0]::numeric[]; f_skill := array[0, 0]::numeric[];
      for i in 1 .. n loop
        continue when not h_up[i];
        f_skill[h_side[i]] := greatest(f_skill[h_side[i]], h_run[i]);
        continue when h_hull[i] <= 0;
        f_one := h_spd[i] * (c_hsf + (1 - c_hsf) * least(1, h_hull[i] / h_maxd[i])) * case when h_crew[i] < h_need[i] then c_csm else 1 end * (1 + c_chdl * h_hdl[i] / 100);
        f_fast[h_side[i]] := greatest(f_fast[h_side[i]], f_one);
        if h_from[i] = 0 then f_slow[h_side[i]] := least(coalesce(f_slow[h_side[i]], f_one), f_one); end if;
      end loop;
```

Hunk 4, OLD (one line and its line end):
```
        f_p[s] := case when s = 1 and p_opts ? 'a_flee' then least(c_rmax, greatest(c_rfloor, v_p)) else least(c_emax, greatest(c_ffloor, v_p)) end;
```
NEW: that line, then:
```
        -- 0452: THE CHASE (chase_enabled; false: the chance above, 0450's, to the digit). ONE rule for every run:
        --   chance = clamp(chase_floor, chase_base x (her sailing x (1 + her skill %) / (their sailing x (1 + their skill %))) ^ chase_power - failed attempts x flee_per_try, chase_cap)
        -- A side with no hull afloat that began (or no speed on her sheet) cannot run: the floor. Nobody afloat to chase her: the cap.
        if c_chase then
          f_p[s] := case when coalesce(f_slow[s], 0) <= 0 then c_cfloor
                         when f_fast[o] <= 0 then c_ccap
                         else least(c_ccap, greatest(c_cfloor,
                                c_cbase * power((f_slow[s] * (1 + f_skill[s] / 100)) / (f_fast[o] * (1 + f_skill[o] / 100)), c_cpow) - s_try[s] * c_ptry)) end;
        end if;
```

### A.3 The other three hunks

`public.battle_hull_card`, OLD `                       where cs.ship_id = s.id))` (and its line end); NEW: that line, then
```
           || public.evasion_of(s.id)   -- 0452: `ev` her Evasion level, `run` what it is worth in a chase (per cent)
```

`public.raid_close`, OLD:
```
  if v_human then
    v_line := case when v_out = 'NO_FIGHT' then 'Pirates came up, and there was no fight.'
```
NEW:
```
  if v_human then
    -- 0452: EVASION, raised by doing (public.level_grant; a merchant never comes here): each roll of her run that failed, and the run that got her away,
    -- once a battle. The rolls are the result's own: a window (a round) she ran in carries `flee`.
    perform public.level_grant(v_dp, 'run_try', (select count(*) from jsonb_array_elements(coalesce(p_fight -> 'rounds', '[]'::jsonb)) r where r ? 'flee')
                                                - case when coalesce((p_fight ->> 'fled')::boolean, false) then 1 else 0 end, 'run_try:' || p_battle);
    perform public.level_grant(v_dp, 'run_away', case when coalesce((p_fight ->> 'fled')::boolean, false) then 1 else 0 end, 'run_away:' || p_battle);
    v_line := case when v_out = 'NO_FIGHT' then 'Pirates came up, and there was no fight.'
```

`public.level_perk`, OLD:
```
  return coalesce((select sum(k.amount) from public.level_perks k
                    where k.perk = p_perk and k.level <= public.level_from_points(v_xp)), 0);
```
NEW:
```
  return public.level_perk_at(p_perk, public.level_from_points(v_xp));   -- 0452: the one sum of a benefit's steps at a level
```

### A.4 What the whole of it did on the chain's world (in memory)

- Seven hunks: each OLD once, each NEW once, each body reverses to its pre-image.
- **The switch off is the fight as it was:** 480 fights (three sheets, one with four pursuers and a hurt, short-handed runner; four
  sets of stances and bonuses, the side that closed running in one) told by the body before the hunks and by the hunked body with
  `chase_enabled` false: the events, the result and `rc` are the same text in all 480. With the switch on, all differ.
- **Relative:** equal sides 15; both sides twice as fast, 15; a slower, less skilled side against a faster one would run on 6 %, and
  the faster one from her on 36 % (15 x r² and 15 / r²).
- `public.level_perk` after its hunk: the steps' sum for all 180 pairs of an existing perk and a level.
- `public.evasion_of`: a probe company at Evasion 10: `{ev: 10, run: 90}`; a pirate: `{ev: 5, run: 40}`; a merchant of hull level 2: `{ev: 2, run: 10}`.
- Six raids opened through `public.battle_open('RAID', ...)` on the probe company's Caravela latina with a FLEE standing order, closed
  through `public.battle_resolve`: each card carried `ev` 10, `run` 90, speed 18, handling 79; the chance served was 21 at the open,
  then 16, 11, 6 after each failed roll, lower again as she was hit; a fight of five failed rolls granted `run_try` 25; a fight that
  got away at the fourth roll granted `run_try` 15 and `run_away` 40; a second close granted nothing; after the six her day stood at
  210 of 300 (four fights of 25, two of 55).
- A fleet of an NPC house set upon: no level row.
- `world.levels()` as the probe company: eleven codes, `evasion` last, level 10, its two activities, nineteen steps (level 10: total 90), five recent grants.

## Appendix B: the reads for the lead (production, read-only, one statement a file, the gate green first)

**B1. The 100 sheets**, the file that is in the repo, as it is:
`npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/battle-stats/prod-sheets.sql > sheets.json`
(then, today's arms: `node scripts/ops/harness/battle-stats/replay.mjs sheets.json`; the new arms once 5.7's `replay.mjs` exists).

**B2. How often a player's ship is the one set upon**, in the 48 hours RAID rows are kept (closed raids, by `battles_raid_done`; the
timeline is opened only for the raids on players):

```sql
begin transaction read only;
with pl as (
  select b.id, f.id as fleet_id, f.player_id, b.ticks #>> '{ai,a}' as ai, b.result ->> 'outcome' as out,
         coalesce((b.result ->> 'fled')::boolean, false) as fled,
         (select count(*) from jsonb_array_elements(case when jsonb_typeof(b.ticks -> 'e') = 'array' then b.ticks -> 'e' else '[]'::jsonb end) e
           where e ->> 2 = 'X' and e ->> 1 = '0') as rolls
    from public.battles b
    join public.battle_sides bs on bs.battle_id = b.id and bs.side = 'DEFENDER' and bs.how = 'OPENED'
    join public.fleets f on f.id = bs.fleet_id
    join public.players p on p.id = f.player_id
   where b.kind = 'RAID' and b.status <> 'FIGHTING' and b.resolves_at > now() - interval '48 hours' and not p.is_npc
)
select jsonb_build_object(
  'at', now(),
  'raids_48h', (select count(*) from public.battles b where b.kind = 'RAID' and b.status <> 'FIGHTING' and b.resolves_at > now() - interval '48 hours'),
  'companies', (select count(*) from public.players p where not p.is_npc),
  'on_players', (select jsonb_build_object(
                          'raids', count(*), 'companies', count(distinct x.player_id), 'fleets', count(distinct x.fleet_id),
                          'most_on_one_company', coalesce(max(x.per_player), 0),
                          'opened_flee', count(*) filter (where x.ai = 'FLEE'),
                          'ran', count(*) filter (where x.rolls > 0), 'rolls', coalesce(sum(x.rolls), 0),
                          'got_away_by_running', count(*) filter (where x.fled))
                   from (select pl.*, count(*) over (partition by pl.player_id) as per_player from pl) x),
  'outcomes_on_players', (select coalesce(jsonb_object_agg(o.out, o.n), '{}'::jsonb) from (select coalesce(y.out, 'NONE') as out, count(*) as n from pl y group by 1) o)
) as r;
commit;
```

**B3. The knobs the design leans on:**

```sql
begin transaction read only;
select jsonb_object_agg(k.key, k.value) as r from public.world_config k
 where k.key in ('levels_bite', 'level_skills_on', 'level_perks_on', 'npc_ship_level', 'npc_ship_level_enabled', 'skills_bite', 'combat_bite',
                 'hull_speed_floor', 'crew_short_speed_mult', 'load_speed_penalty', 'wind_mult_v0', 'raid_orders_enabled', 'raid_flee_ratio', 'tick_fight_kinds',
                 'raid_flee_base', 'raid_flee_floor', 'raid_flee_max', 'flee_per_level', 'flee_level_max', 'flee_hurt_under', 'flee_hurt_max', 'flee_per_try',
                 'fight_flee_base', 'fight_flee_floor', 'fight_evade_max', 'fight_evade_per_sighting', 'raid_flee_per_speed', 'raid_flee_per_handling',
                 'fleet_speed_by_kind', 'level_points_per_step', 'rep_level_per_level', 'peace_after_flee_minutes', 'pirate_strikes_per_run', 'attack_reach_nm');
commit;
```

**B4. Only if slice 2 (the voyage day) is wanted: how often companies flee on a voyage day**, 7 days, reached by the companies' own
fleets and voyages (`voyages_fleet_ended_0249`, then `voyage_events` by its key; never a scan of `voyage_events`):

```sql
begin transaction read only;
select jsonb_build_object(
  'at', now(), 'voyages_7d', count(distinct v.id), 'pirate_days', count(ve.voyage_id),
  'order_flee', count(*) filter (where ve.payload #>> '{fight,log,order}' = 'FLEE'),
  'got_clear_by_running', count(*) filter (where coalesce((ve.payload #>> '{fight,fled}')::boolean, false))) as r
  from public.players p
  join public.fleets f on f.player_id = p.id
  join public.voyages v on v.fleet_id = f.id and v.status <> 'SAILING' and v.eta > now() - interval '7 days'
  left join public.voyage_events ve on ve.voyage_id = v.id and ve.kind = 'PIRATES'
 where not p.is_npc;
commit;
```

B2, B3 and B4 were run on the chain's own world exactly as written here, for their syntax only (B2 and B4 answer zeros there).
`now()` is stable; no other function is called.

## Appendix C: how this was read and measured

- **The code:** the worktree at `origin/main` `7feee03e`. **The live bodies:** the chain's world at head 0451, restored in memory from
  the image build's newest snapshot on this PC (`node_modules/.cache/byeharu-world-image/prefix/browser/browser-p0411-*.tar.gz`, all
  411 files), and read with `pg_get_functiondef`. Nothing was written to the repo, to a cache, or to production.
- **The chain's knobs are not prod's** (the chain has `levels_bite` false; the runs set it true, as prod is said to have it).
- **The scripts** (the hunks as data, the staging of fleets, the four runs) are outside the repo, on PC 디폴리스 only:
  `C:\Users\디폴리스\dev\evasion-proto\`. Appendix A is what they lay over the engine; nothing else is needed from them.
- The 0450 replay tool needs the chain's proof snapshot (`byeharu-chain-prefix`), which on this PC stops at file 332, and the prod
  sheets: neither was to hand, so it was not run.
