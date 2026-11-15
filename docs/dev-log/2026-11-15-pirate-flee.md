# 2026-11-15 · pirate-flee · 0432 A RAIDED SHIP MAY RUN (owner row 349)

The owner, 2026-11-15: *"pirates' main goal is to attack other npcs, loot them. while attacking each ships cannot move until the battle is over
(destroyed, ran away etc.) running away is an option (attempting to run away), but it will need skills for higher probability. after it ran, the
attacked ship will have 5 mins of peace time - no pirates or other npcs will be able to attack them."*

## What was already true (read on the head world, held by proof 133)

- **Held to the end.** `public.battle_open` stops every side with `public.battle_stop`: under sail she is held where she is (`voyage.hold`: her
  point stands still, `fleets.busy_until` is the battle's clock); in port or at anchor she is IN_BATTLE. `cmd.divert` refuses a held fleet
  (E_FLEET_BUSY); an IN_BATTLE fleet runs no order and takes no step (every NPC step reads DOCKED) until `public.battle_resolve` frees her. The
  attacker is held the same way, and a pirate in a battle strikes nobody else (she is not in `pirate_ships_cruising`).
- **Running.** A side's stance FLEE (0353, 0357): her guns fall silent, she takes that round's fire and rolls to slip away; away, the battle ends
  there (EVADED, `fled`) and nothing more is taken. A failed roll costs the round. A player sets it on the battle card (Fight / Flee / Pay,
  `cmd.battle_stance`; `world.battle` serves the defender's `may`).

## What 0432 adds (decided by default; the owner may reverse any)

1. **The world's merchants first** (`public.raid_target`): among the merchants in reach, a company's merchant or a crown's cargo ship before a
   player's ship, then the nearest. Players stay raidable (0427); no PvP.
2. **The world's ships run by a rule** (`public.battle_sheet_freeze`): set upon in a RAID, a MERCHANT or CARGO_SHIP opens with FLEE when her side's
   strength (`voyage.escort_score`) is under the raider's x `raid_flee_ratio` (1.0); otherwise she fights. A player's ship opens with her standing
   order and may press Flee each round.
3. **Running needs skill.** In a RAID, each round the side set upon runs, she slips away with

       chance = clamp( raid_flee_floor 0.10,
                       fight_flee_base 0.15 + (her best sighting - theirs) x 0.03 + speed + handling,
                       raid_flee_max 0.80 )
       speed    = clamp(-0.15, (her fleet speed / the raider's - 1) x raid_flee_per_speed 0.30, +0.25)    -- voyage.fleet_speed
       handling = min(0.25, her company's `handling` skill % on her flagship / 100 x raid_flee_per_handling 0.5)   -- world.skill_pct

   `speed + handling` (`public.flee_bonus`) is frozen on the battle's sheet at the open (`a_flee`), so every re-run is the same fight. A pirate
   sails 4.5x a merchant (0422), so a plain merchant runs at about the floor (10 % a round); a fast, well-handled ship up to 80 %. Sighting already
   carries the lookout skills and gear. An ATTACK (a player's) keeps 0357's chance to the digit (the self-assert compares a fixed fight).
4. **Five minutes of peace** (`public.fleet_peace_until`, knob `peace_after_flee_minutes` 5): after ANY battle she was set upon in ends (she ran,
   beat them off, was boarded, or they broke off), no pirate chooses her for five minutes. For raids this replaces 0427's 60-minute
   `attack_ship_minutes` rest (that knob still rests a navy ship from players' attacks). Her own fleet read serves `peace_until`; the fleet row
   and card say **"Peace 4:12" / "평화 4:12"** beside her clock. The map's fleet labels are not changed (one more read per map fleet was not worth it;
   said plainly, the owner may ask).
5. **Stats count runs:** the window's `raids_fled`; the Battles card's **Fled / 도주**.

## Rows a minute

No new rows of its own but a FLEE stance row at a raid's open when a ship of the world runs (at most ~2 a minute). One index probe of
`battle_sides` per candidate merchant (8 a pirate asked) and one per player fleet read. **About +2 rows a minute.** No job, no table.
Raid frequency: a merchant may be raided again 5 minutes after her battle ends instead of 60 after it began; the job still opens at most
`pirate_strikes_per_run` (2) a minute, so the ceiling of 120 raids an hour is unchanged.

## Proofs

- `scripts/db/proofs/133_a_raided_ship_may_run.sql`: FL_FIRST, FL_HELD, FL_RUN, FL_PLAYER, FL_PEACE, FL_STATS (dice-agnostic: it checks the
  chance every round rolled on, and that a ship that got away lost nothing more).
- Proof 128 (0427) still holds under the peace rule (its second strike falls inside the first merchant's peace).
- 0432's self-assert: ten hunks once and reversing; a fight with no `a_flee` is byte-identical; `a_flee` +5 / -5 clamp to 0.80 / 0.10.

## After-check (30 minutes)

`scripts/ops/harness/pirate-war/after-0432.sql` at +10 and +30: raids mostly on MERCHANT / CARGO_SHIP; `flee_opened_1h` > 0; `fled_1h` > 0 and
`taken_when_fled` 0; `flee_out_of_range` 0; `peace_broken` 0; `stuck` 0; beat under 1,000 ms; gate green. Fail = rollback.

## Forward rollback (owner only)

Quick: `raid_flee_ratio` 0 (the world's ships fight as before), `peace_after_flee_minutes` 0. Whole: `scripts/ops/harness/pirate-war/rollback-0432.sql`.
