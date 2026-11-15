# 2026-11-15 battle-join: 0436 A SHIP MAY JOIN A FIGHT

Owner, 2026-11-15 (items 8-9, corrected): joining a battle is a choice. Entering the red circle changes nothing; only a ship that joins stops,
and she is locked to the end. No PvP, ever. The contract is `docs/design/tick-combat.md` section 9.2; this is slice 0436 on top of 0435
(the tick engine, branch `tick-combat`).

## What it does

- **The Join door** `cmd.battle_join(p_battle, p_fleet, p_side)` -> `{ok, battle, side, from_tick}` (catalogue `cmdBattleJoin`). The core is
  `public.battle_join_for` (the NPC rule uses it too). Refusals, in the short have / need style of 0433 where there are figures:
  `E_BAD_SIDE` (not ATTACKER/DEFENDER, or a player's ship on the pirates' side of a raid), `E_NO_BATTLE`, `E_BATTLE_OVER` (closed, an old round
  battle, or the next tick past the timeline's last), `E_NOT_YOUR_FLEET`, `E_FLEET_BUSY` (held, in a battle, in her port time, no hull, or a
  merchant), `E_AT_PEACE` ("Junta 137: Wait 1 / 5 min", 0432's peace), `E_HUMAN_TARGET` (a player's ship on a side whose other side has a
  player's fleet), `E_NOT_IN_REACH` ("Range 30 / 42 miles", `battle_join_nm` of `battles.site`).
- **She joins at the NEXT tick** (`floor((now - started_at) / tick_ms) + 1`), so nothing a watcher has already seen changes: a `battle_sides`
  row `how = JOINED`, her hulls APPENDED to her side of the sheet (`a` = DEFENDER, `b` = ATTACKER) with `from` and `fleet`, a navy ship tied to
  the battle (`navy_ships.battle_id`), `public.tick_battle_run` (re-run; the past is the same fight, k + 1, every side's `busy_until` to the new
  end), then she is stopped to that end (`public.battle_stop`). `public.battle_resolve` frees her with every side.
- **The NPC rule** `public.battle_npc_joins`, from `public.tick_pirates`' tail (gated like the strikes; never raises). Each run, the newest live
  tick RAIDs (`battle_join_battles_per_run` 10); per battle a roll on md5(battle, minute, kind): `battle_join_navy_chance` 0.35 brings the
  nearest free navy ship (PATROL or HUNT, navy lit) to the side set upon; `battle_join_pirate_chance` 0.15 brings the nearest free hunting
  pirate to her own side. Caps: `battle_join_per_battle` 1 a battle a run, `battle_join_per_side` 2 JOINED a side, `battle_join_per_run` 3 a
  run (0 = the quick rollback). Candidates by a sieve (as `public.raid_target`), SKIP LOCKED, measured exactly by the core.
- **Merchants and cargo ships never join**, and nothing stops a ship that does not join: no step, no route and no hold reads the circle.
- `public.navy_close`: a JOINED pirate is not counted as "the navy came".
- `battle_sides.how` takes `JOINED` (the check rebuilt NOT VALID, then validated).

## Decided by default

- Any country's navy ship may join against the pirates (not only the country of the ship set upon).
- A joining navy ship leaves her PATROL / HUNT; `public.navy_close` sets her back to PATROL (as a called ship).
- A pirate that joins takes no share of the plunder (the raid's opener does, as before); she rests like a pirate that struck.
- A player's ship may help another player's ATTACK on a ship of the world (that is not PvP), never the side against a player.

## Measured (local PGlite, on the draft 0435)

- Self-assert (rolled-back probe, runs on every world): every refusal of the door, a join at the next tick, sheet + `from`, k + 1, held to
  the end; the NPC step answers. Within its 30 s budget.
- Proof 137, 4/4 in 0.2 s: BJ_REFUSE, BJ_DOOR (her `J` event at her tick), BJ_NPC (`{"NAVY": 1, "PIRATE": 1}`, the merchant in the circle
  untouched), BJ_CLOSE (every joiner freed, navy came 1).
- Load: at most ~3 joins a minute x ~6 rows = ~18 rows a minute; reads: one scan of the FIGHTING battles a minute and, only when a roll
  passes, one sieve of the navy or pirate fleets. No job, no table, no cron change.
