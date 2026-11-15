# 2026-11-15 - A battle is fought tick by tick (0435, slice 1 of docs/design/tick-combat.md; owner row 351)

The owner: "the round it takes for a combat to happen i guess is 1 minute, i want the combat system resemble something like rs3"; then "NO MORE 'wait
a minute for a round, then wait more for the result' ... keep the total fight length modest, around 30-90 seconds".

## What was there (read on the chain at 0433)

- A RAID: `battle_seconds` 600 over 6 rounds and the boarding = **85 s a round**, about **10 minutes** a raid. An ATTACK: `battle_round_seconds` 60,
  **420 s**. `public.battle_advance` logged a round when the minute job (`public.tick_battles`) or a stance press reached it.

## What 0435 does

- `public.tick_fight(seed, a, b, opts)`: a pure engine. 600 ms ticks; the six `fight_ranges` are six windows of 20 ticks (72 s), then the boarding.
  Guns on their own reload (4 + tier ticks), hit/crit/armour/brace, one ability a side per 3-tick global cooldown from `tick_abilities`
  (Broadside, Chain Shot, Rake, Grapeshot, Brace, Patch, Run, Pay) on their cooldowns, the Fury bar 0-100, an AI rotation (FIGHT, FLEE, PAY). The
  old rules kept: the range rule at LONG, the sighting slip, the raider's break at 15 %, 0432's flee chance on each Run, 0320's boarding.
  N vs M; a ship comes up at her `from` tick. Every draw keyed by (tick, side, place, what).
- `public.tick_battle_run(battle)`: the ONE (re)run: sheet -> timeline -> `battles.ticks` (new column), the end (last tick + 2), the job's due
  time, `busy_until` of every held side. `public.tick_fight_open` calls it at the open (from `battle_sheet_freeze`), with the ships her country
  called put on the sheet at their arrival tick.
- `battle_fight` answers the timeline's result (fight_sides' shape: one "round" a window, so logs, reports, stats, raid_close and attack_close read
  it unchanged); `battle_advance` logs no rounds for it.
- Doors: `world.battle_ticks(battle)` (the screen's read) and `cmd.battle_end(battle)` (close at the end; the screen calls it when playback ends).
  `fight_card` serves `reach_nm` (knob `battle_join_nm` 30) and `ticks`.
- Knob `tick_fight_kinds` `["RAID", "ATTACK"]`. `[]` is the quick rollback (every new battle round by round again; proof 136 TK_KNOB).

## Measurements (PGlite, this machine)

- Engine: 100 fights on real merchant sheets against raider-strength sheets in 523 ms: **5.2 ms a fight** (the round engine 0.5 ms; native
  Postgres is faster than wasm). The migration's own fixed sheet: 21 ms cold.
- Outcomes, the same 100 sheets and seeds: FIGHT tick 58 PLUNDERED / 18 DRIVEN_OFF / 18 EVADED / 6 RANSOM, rounds 59 / 12 / 21 / 8. FLEE tick
  76 EVADED / 24 PLUNDERED, rounds 75 / 23 (+1 DRIVEN_OFF, 1 RANSOM). **The new clock does not change who wins.**
- Length by outcome (ticks): EVADED 22 (FIGHT) / 49 (FLEE), DRIVEN_OFF 98, PLUNDERED 105-113, RANSOM 120: **13-72 s**, ending 1.2 s later.
- Size: the timeline 2-5 KB as text (the result inside it 0.7-1.9 KB); 13-80 events.
- Migration 0435 on the chain: 181 ms, self-assert ok. Proof 136: 6/6 in 0.3 s.

## Budget

- Rows: none new a battle (a column of the battle row, written once at the open); a tick battle writes 0 `battle_rounds` rows (the round battle 7),
  so **about -700 rows an hour** at the current ~100 battles an hour. No job, no cron, no table, no index.
- CPU: one engine call a battle at the open, ~0.5 s an hour at 100 battles. A watcher's `world.battle_ticks` is one row read; `cmd.battle_end` is
  one row read, and one close (the same close the job would run) at the end.
- Size held: a closed RAID row and its timeline are deleted after `raid_keep_hours` (48 h): ~10 MB at the ceiling.

## The old engine's specs and proofs

The specs and proofs that drive a round-by-round battle (their clocks, their stance presses, their rounds) set `tick_fight_kinds` to `[]` in their
own scene, so they keep proving the round engine, which is the rollback: tests/battleWorld, armadaBattleWorld, fightWorld fixtures; rpc.attack,
rpc.battle, rpc.armadaBattle, rpc.fights specs; and the proofs listed in the PR.

## Decided by default

- A player's side in a tick battle is fought by her standing order (0353) until slice 2's action bar; `cmd.battle_stance` still answers, but no
  stance after the open changes a tick battle.
- The whole timeline is served while the battle is fought (a reader could read the end early): it cannot be changed in slice 1, and slice 2's
  re-run keeps the past and replaces the rest.
- Positions are the client's (the server sends none).
- Merchants pass through a battle's circle untouched (not stopped, not rerouted); joining is a choice (0436).

## Left

- Merged into this branch and deployed with it: 0436 (#730, joining by choice: `cmd.battle_join`, the NPC join rule; proof 137), the battle
  screen (#729, `src/live/battle/`) and the map's red ships and Join bar (#728). Proofs 130-137 52/52 on the chain 0431-0436.
- Slice 2 (0437): `cmd.battle_act`, the action bar live.
