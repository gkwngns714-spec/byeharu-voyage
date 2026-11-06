# 2026-11-06 - Levels are lit (slice W2, measurement only, NO migration)

Owner row 288, `docs/WORLD_POWERS.md` section 2.2 and the W2 row. This slice is the part before the owner's switch: a measurement, and the guard for fitted items. **No migration is shipped (0325 is not used): the code shows the guard is not needed.** The switch is not flipped and nothing on prod was written.

Files: this log, `scripts/ops/harness/levels/after-check.mjs` (the 30-minute after-check, read-only).

## The switch, named exactly
`public.world_config` key **`levels_bite`**, jsonb `false` today (read on prod 2026-11-06, head 0321). Read through `public.levels_bite_on()`. Set to `true` to light levels, back to `false` to put them out. Nothing else needs to move.

## What lighting would change (from the code on prod, read with `pg_get_functiondef`)
Functions that read the switch: `public.level_in_force`, `world.ship_slots`, `public.mount_fitting`, `public.player_progress`, `public.captain_level_mult` (checked by searching every function body in public, world, cmd, voyage, sim for `levels_bite_on`, `level_in_force`, `captain_level`, `player_progress`, `level_from_points`, `ship_slots`).

| Lit, this changes | How |
|---|---|
| A hull's handling, accuracy, sighting | `world.ship_stats` adds (level - 1) x 1, 1.5, 0.15 (knobs `ship_level_handling_per_level`, `ship_level_accuracy_per_level`, `ship_level_sighting_per_level`). The other eight stats do not move. |
| A hull's slots | `world.ship_slots`: unlock rows open at their level. There are 3: barca +1 Mid at level 3, carlat +1 Low at 4, nau +1 High at 6. Dark, they are never open. |
| A captain's bonus | `captain_level_mult`: x (1 + 2 % x (level - 1)) in the trait's track, the level capped at the company's level in that track. |
| The Combat track | `player_progress` reports `combat` playable with points from EVADED 5 and DRIVEN_OFF 15 days (`fight_points`). Dark it is the honest zero. |
| The Combat bar | client; appears when `playable` is true. |

| Lit, this does NOT change | Why |
|---|---|
| Title | `title_level` is the lower of the Trading and Exploration levels; `player_progress` computes those with no switch in them. Combat is deliberately outside it. |
| Fleet and ship caps | `earned_caps` / `fleet_room_caps` read the Trading level and skills, no switch. |
| Fitted items | See the guard section. |
| Item requirements | `requirements_met` is skills (`skills_bite`), not levels. 0133 already dropped the old gear level ask. |

## Who it touches on prod (read-only, 2026-11-06)
- 19 human companies, 22 human hulls. **One human hull has any experience** (a barca, 115 points, level 3). The other 21 are level 1. Lit, that barca gets +2 handling, +3 accuracy, +0.3 sighting and one Mid slot. No human captain signing has a track above level 1. The 19 humans have 0 PIRATES days between them, so lit Combat points start at 0 for everyone.
- One human has Trading 11 and Exploration 10 (title 10); the other 18 read level 1 in both. Lit: unchanged, because those two do not read the switch.
- **945 merchant hulls: 305 are level 2 to 4** (by class: nau 184, carlat 55, barca 48, others fewer; `npc_fix_level` wrote their experience at founding). Dark they read as level 1; lit they gain the same per-level stats. This is where lighting moves the world, not for the 19 players.
- Merchant fleets are the only ones that meet pirates on prod: 263 PIRATES days in the last 7 days, all fought in rounds (130 EVADED, 72 PLUNDERED, 34 RANSOM, 27 DRIVEN_OFF), and every PIRATES day since 2026-10-16 (270) is a merchant's. The fight reads `world.ship_stats` per hull (0189). So lit, merchant accuracy and sighting rise and **merchant raid outcomes can shift**. I did not run a lit fight, so I give no new outcome numbers. By the code: the evade chance is `(our best sighting - theirs) x fight_evade_per_sighting (0.03)`, so +0.45 sighting at most (level 4) is at most +1.35 points of evade chance, and accuracy +4.5 at level 4 is the larger effect. This is arithmetic from the knobs, not a measurement.
- Merchant slots: 21 merchant hull-racks open one more slot lit. No fitted item is affected (next section).

## Cost of `player_progress`
Lit, `player_progress` for a human adds, per VOYAGE_REPORT with a voyage id, one lookup of that voyage's PIRATES rows by `voyage_events_pkey`. Merchants are skipped (`v_lit` is false for them). Measured on prod, read-only, stable functions, the busiest human (123 reports; the only human with reports):

| Read | Execution |
|---|---|
| `player_progress` today (dark) | 43 ms cold, then 15 ms and 17 ms and 28 ms on later runs |
| The lit scan alone (the extra lookup, 123 loops of about 0.035 ms) | 6.5 ms, against 0.67 ms for the dark scan |

So lit adds about 6 ms for the heaviest human, which stays under the 50 ms bound in section 2.2 and so does **not** need the side-table cache. Not measured: what it costs at a hundred times more reports; it grows with the number of reports. `captain_level` calls `player_progress` only for a track above level 1; none exists among humans today.

## The guard for fitted items: not needed
The claim to test is "a locked item already fitted must stay fitted".
- `public.mount_fitting` checks slots **only when fitting** (its own comment: "nothing already mounted is ever refused after the fact"). No other function re-checks a fitted unit against slots. `world.ship_stats` sums every row of `fitted_units` with no slot test.
- Level in force is `level_from_points`, always 1 or more, and an unlock row is open when `min_level <= level`. So the lit set of open slots is **always a superset** of the dark set. Lighting cannot shut a slot a unit sits in.
- Read on prod: fitted rack counts above open slots, dark: 0 for humans and 0 for merchants. Above open slots if lit, computed from the tables with the level formula: 0 for both. 21 merchant hulls open one more slot; 0 human hulls open any besides the one barca.
- The one case that does exist is **after a rollback**: if a player fits an item into a slot that only a level opens (the level 3 barca's Mid slot) and the owner then sets `levels_bite` back to false, that unit stays fitted and still counts in her stats, and she has one more unit than open slots until she unfits it. She cannot fit another into that rack. Nothing refuses or removes it. I did not read the client rack drawing for how it shows used greater than capacity (not verified).

So there is no guard to build. 0325 is not spent; 0324 stays reserved for W7.

## Proof bar, as met
| Bar | State |
|---|---|
| Fitted item stays | By code and by the prod read above; `after-check.mjs` check 2 reads every human hull's racks against `world.ship_slots` after the owner lights it. |
| A stat moves by exactly the knob | 0127's own self-assert proves it lit (level 2 is +1 handling, +1.5 accuracy, +0.15 sighting, the rest equal) and was green when it applied. I did not re-run it. `after-check.mjs` check 3 repeats it on prod after lighting for the 22 human hulls: expected values from the snapshot plus (level - 1) x knob. |
| Title unchanged | By code (above). `after-check.mjs` check 4 compares title, Trading, Exploration and fleet caps for all 19 humans. |
| `player_progress` cost printed | Above. `after-check.mjs` check 5 prints it again and fails at 50 ms. |
| 30-minute after-check ready | `node scripts/ops/harness/levels/after-check.mjs before <file>` now, `... after <file>` 30 minutes after. Check 6 reads `public.arrivals_beats` (avg 3 s, p95 5 s, no error). |
| Red first | The script was run against prod as it is today (dark) with a snapshot taken a minute earlier: it prints FAIL for check 1 (switch not true) and for check 3 (the level 3 barca should read +2 / +3 / +0.3 and reads 0), and `ok` for checks 2, 4, 5, 6. It is red until the switch is on, and the stat line proves it can detect a stat that has not moved. The green side (lit) has **not** been seen: lighting is the owner's. |

## Not verified
- Nothing lit has run anywhere in this slice; every "lit" statement is from reading code or from arithmetic.
- No lit fight was run, so the size of the change in merchant raid outcomes is unknown.
- The client's rack and Combat bar drawings were not read.
- `after-check.mjs` check 3 assumes no gear is fitted or worn between the two runs; the script says so.
- The 305 merchant hulls: whether merchants' other behaviour reads handling, accuracy or sighting beyond the fight, I did not search past the fight and `world.ship_stats` readers.

## Owner decision
To light levels, set `levels_bite` in `world_config` to `true` (one knob; nothing is built for it). The 19 players will see almost nothing: one barca gets three small stat gains and a new Mid slot, no title moves, and a Combat bar appears with 0 points, rising by 5 for an evaded pirate day and 15 for a driven-off one. The real change is to the merchants: 305 of 945 merchant hulls read as level 2 to 4 instead of 1, which makes them somewhat better in pirate fights, so fewer merchant losses and a small shift in the sea economy; I cannot size it without lighting it. What could go wrong: merchant raid results shift more than expected, or a heavy player's `player_progress` gets slower (about 6 ms more for the busiest today). Rollback: set `levels_bite` back to `false`; everything derived reverts at once, experience already earned stays recorded, and a unit fitted into a level-only slot stays fitted. Run the before snapshot first and the after-check 30 minutes later.
