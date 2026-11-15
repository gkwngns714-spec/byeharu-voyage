# A fight shows its ships, and escaping is hard (0450 + client; owner, 2026-11-16)

Owner: "in fight, i want to see levels, their stats, their crew state, equipments, etc. levels, escaping should be hard. and
fighting graphics (ships), make it smaller, and fight scene more wider."

One PR, branch `battle-stats`: migration 0450 (NOT deployed), proof 152, the battle screen and the map's card.

## What the game had (read on the chain at 0444, and on prod read-only 2026-11-15 16:34 UTC, gate green: beat 135 ms, 699 MB)

- **Level.** A hull's level is her experience on the one curve (`ship_xp`, `level_in_force`). Prod has `levels_bite` true: a
  merchant's hull is fixed at 1 to 5 at her founding (0127), a crown's or a pirate's at `npc_ship_level` 5 (0344), a player's
  rises. A captain has a level in three tracks; a company's Combat level is counted from her record.
- **A level already fights.** `world.ship_stats` gives a hull, per level above 1, +1.5 accuracy (her chance to hit), +0.15
  sighting (who sees first, and the sighting term of a run) and +1 handling. Proof 152 BS_FIGHTS reads it: level 1 to 4 is
  accuracy 40 to 44.5. So 0450 adds **no** second to-hit or crit by level: it would count a level twice.
- **Crew.** A ship has crew, the crew her class needs and the most she may carry. There is no morale in the game.
- **The sheet.** `battle_sheet_freeze` froze per hull: name, tier, hull, size, crew, attack, accuracy, reach, armour, sighting,
  gunner, boarder. No level, class, guns, crew she needs, speed, handling, or what is fitted.
- **The run.** A raid's side set upon rolled `clamp(0.10, 0.15 + sighting lead x 0.03 + a_flee, 0.80)`, the same every attempt,
  and a ship that runs tries again every 20 ticks. On prod `a_flee` is -0.15 to -0.09 for every merchant (a pirate sails 4.5 x
  as fast since 0424), so nearly every roll was the floor, 10 %, about four times a fight. The last hour on prod: 115 raids,
  46 opened FLEE, 26 got away by running; 155 rolls on 10 to 23 %.

## What changed on the server (0450)

- `public.battle_hull_card(ship)` and `public.ship_level(ship)` (new, server-only). `public.tick_battle_run` (one hunk) adds
  the card to every hull of the sheet that has none, the first time she is run (the open; a joiner's join), and it is frozen
  there. Card: `lv`, `cls`, `guns`, `crew_need`, `crew_max`, `speed`, `handling`, `fit` (name, slot, wear), `caps` (name, combat level).
- `world.battle_ticks` (one hunk) serves `ships: {a, b}`: every hull of the sheet in the timeline's order. NPC ships too.
- `public.fight_card` (two hunks) serves each side's `lv` (her fleet's best level) beside `ships`.
- `public.tick_fight` (five hunks): ONE formula for every run, computed each tick, served as `rc` (`[tick, per cent]` where it
  changes) so the Run button says what the roll would be now; each ship of the timeline carries `lv`.

### The new rule (decided by default; the owner may reverse it with the knobs)

```
chance = clamp(floor, base + (her best sighting - theirs) x 0.03 + a_flee (speed, handling: 0432)
                           + clamp(-0.15, (her best level - theirs) x 0.03, +0.15)
                           - 0.20 x max(0, 1 - min(hull left / her size, crew / the crew she needs) / 0.5)
                           - failed attempts in this fight x 0.05, cap)
```

| knob | value | was | what |
|---|---|---|---|
| `raid_flee_floor` | 0.03 | 0.10 | the least a raid's run rolls |
| `raid_flee_max` | 0.45 | 0.80 | the most |
| `raid_flee_base` | 0.10 | 0.15 (`fight_flee_base`) | a raid's base, new |
| `flee_per_level` / `flee_level_max` | 0.03 / 0.15 | none | a level ahead +3 points, behind -3, at most 15 |
| `flee_hurt_under` / `flee_hurt_max` | 0.5 / 0.20 | none | under half her hull or crew the chance falls, by 20 points at nothing |
| `flee_per_try` | 0.05 | none | each failed roll costs the next 5 points |

A run that is not the side set upon in a raid keeps 0357's base 0.15, floor 0.05 and cap 0.30, with the same three new terms.
Run keeps its 20 ticks of silent guns. The round engine (`fight_sides`, fought only when `tick_fight_kinds` is `[]`) keeps
0432's formula and reads the same floor and cap.

**Rollback is the knobs:** floor 0.10, cap 0.80, base 0.15 and the three new terms 0 give the old chance to the digit
(self-asserted in the file; proof 152 BS_OLD: 60 rolls over 18 fights).

## What "hard to escape" does to merchants (100 real frozen sheets, replayed)

`scripts/ops/harness/battle-stats/prod-sheets.sql` read the 100 newest closed tick RAIDs from prod once (their frozen sheets,
`a_flee`, stances, and each hull's level and needed crew). `replay.mjs` re-fights them locally through `public.tick_fight`
under each rule: the same seeds, the same dice in every arm, prod's own fight knobs. 39 of the 100 opened FLEE (an outgunned
ship of the world); 61 fought. As prod itself fought them: PLUNDERED 17 / DRIVEN_OFF 22 / EVADED 55 / RANSOM 6.

| rule | PLUNDERED | DRIVEN_OFF | EVADED | RANSOM | of the 39 that ran: got away by running | chance at the open (min / median / max) |
|---|---|---|---|---|---|---|
| before (0432) | 22 | 26 | 47 | 5 | 15 | 10 / 10 / 23 % |
| **0450** | **32** | **26** | **36** | **6** | **4** | **3 / 3 / 9 %** |
| softer A: floor 0.05, base 0.15, level 0.02, try 0.03 | 28 | 26 | 41 | 5 | 9 | 5 / 5 / 17 % |
| softer B: floor 0.08, cap 0.60, base 0.20, level 0.02, try 0.03 | 23 | 26 | 47 | 4 | 15 | 8 / 8 / 22 % |
| harder: floor 0.01, cap 0.30, base 0.05 | 35 | 26 | 33 | 6 | 1 | 1 / 1 / 4 % |

- The 61 that fought are untouched by the rule (PLUNDERED 2 / DRIVEN_OFF 26 / EVADED 30 / RANSOM 3 in every arm): 30 of them
  still end EVADED because the raider breaks off before she is touched.
- **Evasions by running do not go to zero, but they go low: 15 to 4 of 39.** A merchant that runs from a level-5 pirate 4.5 x
  as fast is at the floor (3 %) on every roll; about one in ten gets away, and ten more of a hundred are plundered.
- If that is too hard on the world's merchants, softer A is the suggestion (9 of 39 get away): `raid_flee_floor` 0.05,
  `raid_flee_base` 0.15, `flee_per_level` 0.02, `flee_per_try` 0.03. Softer B is the old escape rate with the new shape.
- A player's ship is usually faster relative to a pirate than an NPC merchant only by her gear and handling skill: with level
  5 against 5, handling 20 % and a pirate 4.5 x as fast she opens on 0.10 - 0.15 + 0.10 = 5 %; two levels ahead 11 %.

## What changed on the client

- **Each side's ships** (`src/live/battle/ShipsPanel.tsx`): under each side's name, "Lv 5 · Ships 4" opens that side's ships,
  the side set upon on the left, the side that closed on the right; open on a desk, shut on a phone until pressed. A card:
  name, `Lv`, class, a hull bar with hull now / size, crew now / most (red and "Short" under the crew her class needs), then
  icons with figures: guns, attack, accuracy, reach, armour, sighting, speed, handling, tier; what is fitted ("Starter Guns ×2");
  her captains. Words are the ship panel's own (`ship.*`); five new short ones in `battle.*`, EN and KO.
- **Smaller ships, a wider sea:** a hull is drawn at six tenths; the sheet is nearly the whole window on a desk (1 vw / 2 vh
  margins, was 3 / 5); the stage has the sheet's whole width; the sides sail 38 % of it out from the middle (was 30 %); the
  drawing box follows a wide, low stage instead of letter-boxing it. Hit numbers keep their size and rise over her name.
- **Run says its chance** ("Run 30%"), the server's `rc`; the log says each roll's chance as before.
- **The map's card** (`FightSheet`): each fleet's line reads "Lv 5 · Ships 4".
- A battle opened before 0450 serves no card: the screen draws names and hulls and no chance.

## Where each figure comes from

| on the card | from |
|---|---|
| name, hull at the open, size, tier | `voyage.fleet_hulls` on the sheet (as before) |
| hull now | the timeline's events, folded (`timeline.ts`) |
| Lv | `public.ship_level` = `ship_xp` on `level_in_force` |
| class, guns, crew needed | `ship_classes` (name, guns, crew_required) |
| crew, crew max | `ships.crew` (on the sheet), `public.ship_base().crew_max` |
| attack, accuracy, reach, armour, sighting | `world.ship_stats` through `fleet_hulls`: what the engine reads |
| speed, handling | `world.ship_stats` (class x her roll, gear, skills, captains, level) |
| fitted | `fitted_units` x `item_kinds` (every slot), wear when worn |
| captains | `captain_seats` x `officers`, `public.captain_level(.., 'combat')` |
| the run's chance | `public.tick_fight`'s `rc`, the formula above |

## Measured

- Migration 0450 on the chain: self-assert ok, 243 ms. Proof 152: 10/10. Proofs 133 6/6, 136 6/6, 137 4/4, 140 7/7 (136 and
  140 had the old bounds 10 to 80 written in; they read the knobs now). Proof 146 prints no `PASS:` line on main (0/4, before
  and after this branch): not this branch's.
- `tests/battle.screen.spec.ts` 9/9 (the panel, the three glasses, the Run chance, a battle from before 0450),
  `tests/map.battleClose.spec.ts`, words, i18n and budget specs; tsc, eslint, vite build.
- Hull length with her wake at 390: 99 px (measured by the spec; about 165 before, by the drawing's own units); at 1280 about 300 to about 180 by the same units.
- Prod BEFORE check (`battle-stats/check.sql`, 16:51 UTC): head 0446, each of the nine old texts once in the live bodies.

## Decided by default

- "Level" in a fight is the HULL's level (the one that already moves her stats); the captains' combat levels are shown on her
  card, not counted in the run. A side's level for the run is its best hull's, like its sighting.
- No new to-hit or crit by level (it is already in her accuracy).
- The crew she is measured against is the crew her class NEEDS (an NPC merchant sails with exactly that), not the most she may carry.
- The ship panels sit above the stage, not beside it, so the stage keeps the whole width; a side's line shuts them and the stage takes the room.
- The whole card is served to any signed-in reader of a battle, as the Stats pages already open every fleet.
- A battle in flight at the deploy that is re-run by a join or an act is re-run under the new rule (at most ~75 s of fights).

## Not done

- `raid_flee_ratio` (when a ship of the world chooses to run at all) is unmoved: with running this hard, fighting or paying
  may be the better opening for more of them. A knob for the owner, or a later slice.
- Crew does not fall during a tick fight (only the boarding counts it), so "crew now" is her crew at the open.
