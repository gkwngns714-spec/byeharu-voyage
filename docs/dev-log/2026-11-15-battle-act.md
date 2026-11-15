# 2026-11-15 battle-act: 0439 A PLAYER ACTS IN A FIGHT

Owner, 2026-11-15 (row 351): "i want the combat system resemble something like rs3". Slice 2 of `docs/design/tick-combat.md`: the battle
screen's action bar presses for her own fleet. Built on `tick-combat` (0435, #731) with `battle-join` (0436, #730) merged in. 0437 and 0438
are other queued branches, so this is 0439.

## What it does

- **The door** `cmd.battle_act(p_battle, p_fleet, p_code, p_tick)` -> `{ok, battle, tick, k, resolves_at, ticks}` (catalogue `cmdBattleAct`;
  client wrapper `src/lib/rpc/battleAct.ts`). The core is `public.battle_act_for` (server-only).
- **Where it lands:** `greatest(p_tick, the server's tick now + 1)`, then on to her side's global cooldown (`tick_gcd` after her commander's
  last ability, the AI's or an earlier act's). Nothing a watcher has seen changes.
- **Judged against the current timeline at that tick** (the past is fixed by construction): the ability's cooldown, her side's Fury, a run
  in progress (only Brace and Patch while she runs). Then written to `sheet.acts` (`{t, s, code, fleet, at}`), the timeline re-run by
  `public.tick_battle_run` (k + 1; the end and every held side's `busy_until` follow), and refused (rolled back) if the re-run did not use it
  at its tick (her guns could not bear).
- **Refusals:** `E_BAD_CODE` (not one of the eight; Pay by any but the ship set upon; Run by a ship that joined), `E_NO_BATTLE`,
  `E_NOT_YOUR_BATTLE`, `E_BATTLE_OVER` (closed, an old round battle, or past the timeline's last tick), `E_PAST_TICK` ("Tick 5 / 10"),
  `E_TOO_SOON` (one act a fleet every `tick_gcd` ticks of the server's clock: the spam cap), `E_COOLDOWN` ("Ready 6 / 40"), `E_NO_FURY`
  ("Fury 0 / 50").
- **The engine** (`public.tick_fight`, 4 hunks): `p_opts.acts`. At a tick where her side has an act, the commander uses it if it can; else,
  and on every tick she leaves empty, the AI as before. Pay by an act ends the fight in a RANSOM at its tick (`paid`; `raid_close` takes the
  ransom as for a Pay at the open). Run is the AI's Run: 0432's raid chance with `a_flee`, else 0357's.
- `public.tick_battle_run` (1 hunk) passes `sheet.acts`, so a join after an act keeps it. `public.client_rpc_entry_points` (1 hunk).
- **No PvP:** an act adds no side and no hull.
- **The battle screen** (`src/live/battle/BattleScreen.tsx`, `timeline.ts` `barLock`): for her own fleet (`read.mine`) in a battle still
  fought, the bar is live. Grey while the cooldown sweeps, while her Fury cannot pay (the cost shown, lit when she has it), while she runs
  (but Brace, Patch), or when it is not hers to order (Pay, Run). A press, or the keys 1-8 on a desk, asks for the next tick; the answer's
  timeline is swapped in at the same tick (the playback clock never moves; a later poll with a lower k never replaces it). A refusal's short
  word (EN/KO, `battle.act_*`) shows under the bar for 3 s. A watcher's bar stays disabled.

## Decided by default

- The AI keeps her side's commander between her acts (the brief), not the design's "HOLD between acts".
- `p_tick` under the tick now is `E_PAST_TICK`; a press one tick late lands at the next tick instead of being refused.
- `E_TOO_SOON` is added to the contract's list for the spam cap (the code the client already knows).
- Run is her whole side's, so only a ship that began the fight orders it; Pay only the ship set upon.

## Measured (local PGlite)

- The chain to 0439 applied with every self-assert receipt (the 0439 probe: every refusal, Brace at the next tick, k + 1, the past the same,
  E_TOO_SOON, E_COOLDOWN).
- Proof 140, 7/7 in 0.2 s: BA_REFUSE, BA_TAIL (asked 21, landed 23 after her Chain Shot at 20; 13 events before it the same, the tail
  changed), BA_RATE, BA_COOLDOWN ("Ready 6 / 40"), BA_FURY ("Fury 0 / 50"; Patch at 59 with Fury 50 taken, 0 after), BA_RUN (Run at 62,
  guns silent, rolled at 82 with 10 %), BA_PAY (RANSOM at 62, the end moved there). Proof 136 6/6.
- `tests/battle.screen.spec.ts` 5/5 (two new: her own ship's bar on a desk with a refusal, a taken act, the keys; and on a phone).
- Load: no new rows; an act is one battles update and the fleets' `busy_until` when the end moves, plus one engine run (~5 ms).
