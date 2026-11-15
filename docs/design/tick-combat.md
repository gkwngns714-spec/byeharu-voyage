# Tick combat (owner, 2026-11-15: "the round it takes for a combat to happen i guess is 1 minute, i want the combat system resemble something like rs3")

Status: DESIGN + CONTRACT. Slice 1 server = migration 0435 (branch `tick-combat`). Other slices are built against section 9, the contract.
Genre mechanics only: fast ticks, auto-attacks on a reload, abilities on cooldowns fed by a bar that builds as you fight. No name, art,
ability or number is taken from any other game. No PvP, ever: a player never fights, or joins against, another player.

## 1. What is there today (read on the chain at 0433)

- `public.battle_open(kind, attacker, defender, now)`: kinds PROBE (no sheet, one call at its end), ATTACK (a player's, `public.attack_for`),
  RAID (a pirate's, `public.pirate_strike`, 0427). It settles both fleets, stops every side (`public.battle_stop`: a sailing fleet is held where
  she is by `voyage.hold`, one at anchor goes IN_BATTLE; `busy_until` = the battle's end), calls her country's navy (`public.navy_call`, side
  rows `how = CALLED` with `arrives_at`), then freezes the sheet (`public.battle_sheet_freeze`: both sides' hulls once, `a_flee` for a raid, the
  defender's opening stance: an outgunned ship of the world opens FLEE (0432), a player's ship her standing order).
- The fight: `public.fight_sides(seed, 1, a, b, opts)`, six ROUNDS (`fight_ranges`: LONG x3 at 0.6, MEDIUM x2 at 0.8, CLOSE at 1.0) and then the
  boarding. `public.battle_fight` re-runs the sheet to round N under the stances kept; `public.battle_advance` logs a round into
  `battle_rounds` when it falls due; `public.tick_battles` (the minute job) and `cmd.battle_stance` drive it; `public.battle_resolve` closes it
  (hulls, `raid_close` / `attack_close`, navy, fleets freed, reports).
- HOW LONG A ROUND IS NOW: an ATTACK is `least(battle_seconds 600, battle_round_seconds 60 x 7)` = 420 s, so **60 s a round**; a RAID is
  `battle_seconds` 600 / 7 = **85 s a round**, about **10 minutes** a raid. The minute job writes each round, so a watcher waits a minute,
  then another. That is what the owner is asking to end.
- Queued and unapplied, and this work lands after them: 0432 (`pirate-flee`: a raid's flee chance with speed and handling, `a_flee`;
  5 minutes of peace, `public.fleet_peace_until`), 0433 (`short-server`: battle words). 0434 (`city-people-slot`) and 0431 do not touch battles.

## 2. The clock

- **One tick = 600 ms** (knob `tick_ms`).
- **A window = 20 ticks = 12 s** (`tick_window`). The six `fight_ranges` are six windows (LONG, LONG, LONG, MEDIUM, MEDIUM, CLOSE): **72 s**,
  then the boarding at tick 120. Most fights end sooner (a raider breaks off at 15 % of her hull lost; a ship that runs may slip away).
  Measured on 100 sheets: average 22-113 ticks by outcome (13-68 s). The battle closes 2 ticks after its last event.
- The windows keep the old game's range rule (at LONG a hull out-reached by the other side's best does not fire) and the old result shape
  (one "round" row a window), so every reader of a battle's result (logs, reports, stats, raid_close) keeps working.

## 3. The bar: Fury / 기세

Each SIDE has one bar, 0-100, starting at 0. Basic abilities build it (+10); heavier abilities spend it (50, 100). Auto fire builds nothing.
One commander a side: one ability at a time, a global cooldown of **3 ticks** (`tick_gcd`) between two abilities, each on its own cooldown.

## 4. Abilities (knob `tick_abilities`, the one table; ticks are 0.6 s)

| code | EN | KO | kind | cooldown | Fury | effect |
|---|---|---|---|---|---|---|
| BS | Broadside | 일제사격 | basic | 15 (9 s) | +10 | every gun of the side fires once at 0.25 x a full broadside |
| CH | Chain Shot | 사슬탄 | basic | 25 (15 s) | +10 | a volley at 0.15; the other side's reload is 1.5 x slower for 15 ticks |
| RK | Rake | 종사 | threshold | 40 (24 s) | -50 | a volley at 0.6 with +15 accuracy |
| GR | Grapeshot | 포도탄 | ultimate | 60 (36 s) | -100 | a volley at 0.5; the other side boards with 15 % fewer hands (floor 40 %) |
| BR | Brace | 방어태세 | defence | 40 (24 s) | 0 | what she takes is halved for 10 ticks (6 s) |
| PT | Patch | 응급수리 | defence | 60 (36 s) | -50 | her most hurt hull mends 8 % of its size (never above where it began) |
| RN | Run | 도주 | flee | 20 (12 s) | 0 | her guns fall silent for 20 ticks, then she rolls to slip away (section 6) |
| PY | Pay | 몸값 | pay | - | 0 | the side set upon pays: RANSOM (only at the start in slice 1, from her standing order) |

A "full broadside" is the old game's per-round figure: `attack / shots x fight_damage_per_attack`. All words go through `src/lib/i18n/dict/fight.ts`.

## 5. Damage (built from the ship stats `voyage.fleet_hulls` already serves: attack, accuracy, reach, armour, sighting, hull, maxd, crew, tier, boarder_pct)

- **Auto fire:** each hull with guns fires on her own reload, `tick_reload_base (4) + tier` ticks (a tier-1 sloop every 3 s, a tier-5 ship of the
  line every 5.4 s); the first shot after 1..reload ticks (a keyed draw), so guns are not all loaded at once.
- **Hit:** `clamp(accuracy / 100 x window share + ability accuracy / 100, 5 %, 95 %)`. **Target:** a hull of the other side afloat, by size.
- **Damage:** `attack / shots x fight_damage_per_attack x mult x (0.75..1.25)`, with `mult = tick_auto_share (0.5) x reload / tick_window` for auto
  fire (half a broadside a window from auto fire, the other half from abilities) and the ability's mult for a volley. **Crit** `tick_crit` 10 %:
  x `tick_crit_mult` 1.5. Then **armour** `x (1 - armour / 100 x armour_turns_pct)`, then **Brace** x 0.5. A hull never goes below 0.
- **First sight:** the side with the better best sighting sees first: the other is unready (fires nothing) for the first window. A lead may let the
  side set upon slip away before a shot (0320's roll, unchanged).
- **Balance check** (100 real merchant sheets against raiders, the same seeds): FIGHT: tick 58 PLUNDERED / 18 DRIVEN_OFF / 18 EVADED / 6 RANSOM against the
  rounds' 59 / 12 / 21 / 8; FLEE: tick 76 EVADED / 24 PLUNDERED against 75 / 23. The new clock does not change who wins.

## 6. Running, peace, the ends

- **Run (RN):** 20 ticks of silent guns (she still takes fire), then a roll on her own keyed draw. The side set upon in a RAID rolls 0432's chance
  `clamp(raid_flee_floor 10 %, fight_flee_base 15 % + (her sighting - theirs) x 3 % + a_flee (speed and handling, frozen at the open), raid_flee_max 80 %)`;
  any other run 0357's `clamp(fight_flee_floor, base + lead x 3 %, fight_evade_max)`. Away: EVADED (`fled`), or for the side that closed `b_fled`
  (BROKEN_OFF). The log shows each roll with its chance.
- **Peace:** unchanged. A ship whose battle as the side set upon has ended has `peace_after_flee_minutes` (5) of peace (`public.fleet_peace_until`):
  no pirate raids her, and (slice 2) she may not join a battle.
- **Break off:** the side that closes breaks off at `fight_raider_break` (15 %) of its hull lost: EVADED if the side set upon was never touched, else DRIVEN_OFF.
- **Boarding:** every hull of the side set upon at 0, or tick 120: 0320's arithmetic (crew x hand value x (1 + boarder share) + tier x 3, x the share
  of hull left; Grapeshot thins the crew) against `fight_board_bands`: DRIVEN_OFF, RANSOM, PLUNDERED (surrender under the last band).
- **Held to the end:** every side stays stopped (0432's `battle_stop`) until `public.battle_resolve`. The battle's `resolves_at` is the timeline's
  end, so the minute job closes it within a minute of the last tick, and any reader may close it AT the end through `cmd.battle_settle`
  (section 9.2), which the battle screen calls when its playback ends: the result does not wait for the minute job.

## 7. The AI rotation (NPCs always; a player's side in slice 1 from her standing order; slice 2 lets a player act)

Per side, at each tick its global cooldown allows, the first that applies:
- **FIGHT:** Patch if her side's hull is under 50 % and Fury >= 50; Brace if under 80 % and she was hit in the last 5 ticks; if her guns can fire:
  Grapeshot at 100 Fury, Rake at 50 (then she saves for Grapeshot), Chain Shot, Broadside.
- **FLEE:** Run whenever it is ready (so she runs again at once after a failed roll); Brace when hit and not running.
- **PAY:** pays at tick 0 (RANSOM).
Who uses which: the side set upon takes 0432's opening stance (an outgunned ship of the world FLEE, a player's ship her standing order FIGHT/FLEE/PAY,
otherwise FIGHT); the side that closes FIGHTs (and breaks off by rule). Navy and pirate joiners FIGHT.

## 8. Joining a battle (owner items 8-9, corrected: joining is a CHOICE)

- The red circle: centre = `battles.site` (where the ship set upon was), radius = `battle_join_nm` (knob, 30 nm). Entering it changes nothing.
- **A player's ship** inside the circle may press **Join** and pick a side; she may never join a side whose other side has a player's fleet (no PvP),
  and in a RAID she may only join the side set upon (against the pirates). She must be free (not held, not in a battle, not at peace).
- **NPCs decide by rule** (slice 2, 0436): a navy ship hunting nearby joins against the pirates with a chance; a pirate hunting nearby sometimes joins her
  own side. **Merchants and cargo ships never join**, and they **pass through** the circle untouched: not stopped, not rerouted (decided by default:
  a route around every circle would cost the arrivals beat for a 12-72 s fight; a ship that does not join is not part of it).
- **Only a ship that joins** stops (at her own point, held like every side: `battle_stop`) and is locked until the end. She enters the sheet with
  `from` = the join tick, the timeline is re-run (the past is identical, section 10), and the log says "Navy brig joins".
- Data model (exists already): `battle_sides` (`how` OPENED / ESCORT / CALLED / ARMADA; 0436 adds JOINED), `arrives_at`; the hulls of every ship
  in the fight are on `battles.sheet.a` / `.b` in a fixed order, each with `from` (tick) and `fleet`. A navy ship called at the open (0333) is
  already a joiner: 0435 puts her on the sheet with `from` = her arrival tick, if she arrives before the end.
- Split: **slice 1 (0435)** = N vs M in the engine, the sheet's `from`, called navy ships joining at their tick, `public.tick_battle_run` (the one
  re-run). **0436** = the Join door, `JOINED`, the NPC join rule. **Slice 2** = the player's action bar acting (`cmd.battle_act`).

## 9. THE CONTRACT (build against this; changes go through the lead first)

### 9.1 The battles table (0435)

| column | change |
|---|---|
| `ticks jsonb` | NEW, null = an old round-by-round battle (PROBE, a battle opened before 0435, or a kind not in `tick_fight_kinds`). The timeline, 9.3. |
| `sheet` | each hull may carry `from` (the tick she comes up, absent 0), `fleet` (her fleet id) and `fleet_name`. Slice 2: `sheet.acts` = `[{t, s, code}]`. |
| `resolves_at` | `started_at + (ticks.n + 2) x tick_ms`. |
| `next_round_at` | = `resolves_at` (the minute job's due time). `round_seconds` = 12 (a window). `rounds_done` 0 until the close. |
| `result` | at the close: the timeline's `r` (0320's shape, `engine: "tick"`), plus what the close adds (`raid`, `navy`, `loot`, `crew_lost`) as today. |

Knobs: `tick_ms` 600, `tick_window` 20, `tick_gcd` 3, `tick_reload_base` 4, `tick_auto_share` 0.5, `tick_crit` 0.10, `tick_crit_mult` 1.5,
`tick_abilities` (section 4), `tick_fight_kinds` `["RAID", "ATTACK"]` (quick rollback: `[]` = every new battle is the old round engine),
`battle_join_nm` 30.

### 9.2 The RPCs

| RPC | args | returns | slice |
|---|---|---|---|
| `world.battle_ticks` (read, any signed-in player) | `p_battle uuid` | see below | 0435 |
| `cmd.battle_settle` (any signed-in player) | `p_battle uuid` | `{ok: true, status}`: closes the battle if its end has come (else nothing); refusal envelope `E_NO_HOUSE`, `E_NO_BATTLE` | 0435 |
| `cmd.battle_join` | `p_battle uuid, p_fleet uuid, p_side text ('ATTACKER'\|'DEFENDER')` | `{ok: true, battle, side, from_tick}`; refusals `E_NO_BATTLE`, `E_BATTLE_OVER`, `E_NOT_YOUR_FLEET`, `E_NOT_IN_REACH`, `E_BAD_SIDE`, `E_HUMAN_TARGET` (no PvP), `E_FLEET_BUSY`, `E_AT_PEACE` | 0436 |
| `cmd.battle_act` (abilities, incl. Run = flee and Pay) | `p_battle uuid, p_fleet uuid, p_code text, p_tick int` | `{ok: true, tick, k}`; refusals `E_NO_BATTLE`, `E_BATTLE_OVER`, `E_NOT_YOUR_BATTLE`, `E_COOLDOWN`, `E_NO_FURY`, `E_PAST_TICK` (`p_tick` < the server's tick now), `E_BAD_CODE` | slice 2 |

`world.battle_ticks(p_battle)` returns:
```
{ on: true, battle, kind: 'RAID'|'ATTACK', status: 'FIGHTING'|'RESOLVED'|'BROKEN_OFF',
  started_at, resolves_at, now,            -- server clock; the tick now = floor((now - started_at) / ms)
  ticks: <timeline 9.3> | null,            -- null: an old battle; draw it with the round view
  site: {lat, lon}, reach_nm,              -- the circle
  sides: [{fleet, name, side: 'ATTACKER'|'DEFENDER', how, kind, nation, company, mine: bool}],
  mine: <her own fleet id in it> | null,
  result: null while FIGHTING | {outcome, fled, b_fled, paid, taken, loot, crew_lost, navy} }
{ on: false } for no house, no battle, or a PROBE.
```
Side mapping: timeline side 0 (`a`) = the DEFENDER side (the side set upon, and the ships that came to her), side 1 (`b`) = the ATTACKER side.

### 9.3 The timeline (`battles.ticks`, version 1)

```
{ v: 1, ms: 600, w: 20, n: <last tick>, first: 'A'|'B'|'BOTH', gcd: 3, k: <re-run count, 0 at the open>,
  ranges: [['LONG', 0.6], ...],            -- window i covers ticks [i*w, (i+1)*w)
  ab: { BS: {kind, cd, gain}, CH: {..., slow}, RK: {..., cost, acc}, GR: {..., cost, crew}, BR: {kind, cd, for, cut}, PT: {..., cost, mend}, RN: {kind, cd, for}, PY: {kind} },
  a: [ {n: ship name, fl: fleet name, h: hull at the start, m: max hull, t: tier, r: reload ticks, f: from tick, g: has guns} ],   -- side 0
  b: [ ... ],                                                                                                                         -- side 1
  ai: {a: 'FIGHT'|'FLEE'|'PAY', b: 'FIGHT'|'FLEE'},
  e: [ <event>, ... ],                     -- in tick order; within a tick: joins, abilities (a then b), shots, run rolls, ends
  out: 'EVADED'|'DRIVEN_OFF'|'RANSOM'|'PLUNDERED',
  r: <result in fight_sides' shape: outcome, broke_off, slipped, first, rounds_fought, rounds[one per window], board, hull_lost, hull, hits, fled?, b_fled?, paid?, engine: 'tick', ticks> }
```
Events are arrays `[t, side, kind, ...]` (side 0 = a, 1 = b, -1 = neither); ship indexes are positions in `a` / `b`:

| kind | array | meaning |
|---|---|---|
| `A` / `BS` `CH` `RK` `GR` | `[t, s, kind, i, j, dmg, crit, left]` | ship `i` of side `s` fires (auto, or the ability's volley) at ship `j` of the other side. `dmg` 0 = a miss (a splash). `crit` 0/1. `left` = her hull after. |
| `U` | `[t, s, 'U', code, fury]` | side `s` uses ability `code`; `fury` = her bar after. BR lasts `ab.BR.for` ticks; RN runs `ab.RN.for` ticks (her guns silent) and ends in an `X`. |
| `P` | `[t, s, 'P', i, amount, hull]` | Patch mends ship `i` by `amount`, to `hull`. |
| `X` | `[t, s, 'X', chance_pct, away]` | the run's roll: `away` 1 = she slipped away (the end follows), 0 = caught. |
| `J` | `[t, s, 'J', i]` | ship `i` comes up and joins side `s` ("Navy brig joins"). |
| `S` | `[t, s, 'S', i]` | ship `i` of side `s` is at 0 hull (strikes; the boarding follows if her whole side is down). |
| `K` | `[t, 1, 'K']` | the side that closed breaks off (15 % lost). |
| `L` | `[0, 0, 'L']` | the side set upon slipped away before a shot (she saw them first). |
| `O` | `[0, 1, 'O']` | nothing to fight (the side that closed has no hull). |
| `B` | `[t, -1, 'B', ratio, surrender]` | the boarding: strength ratio, surrendered. |
| `E` | `[t, -1, 'E', outcome]` | the end. The loot/ransom is `result.taken` / `result.loot` of `world.battle_ticks` once closed. |

**Positions:** the server sends none. The client lays ships out per side from (battle id, side, index) and animates them (circling, the flee
turn-away from a `U RN` to its `X`, sinking at `S`). Fury, cooldowns and the brace/slow/run states are all derivable from the events and `ab`.
**Playback:** the tick now is `floor((server now - started_at) / ms)`; a reader that opens late jumps to it. When `k` changes on a later read
(a join or an act re-ran it), the client swaps in the new timeline at the same tick: everything before it is unchanged by construction.

### 9.4 The map fields (no new read)

- **In battle:** `world.fights()` cards (`fight_card`) already list every fleet in each battle (`sides[].fleet`, `here`, and `at` while FIGHTING).
  A ship mark whose fleet id is on a FIGHTING card with `here` is in a fight: draw her red. A player's own fleets also carry `busy_until` in `world.fleets`.
- **The circle:** `lat`, `lon` of the card (= `battles.site`); 0435 adds `reach_nm` (= `battle_join_nm`) and `ticks` (boolean: a tick battle) to each card.

## 10. Determinism, and why it fits the database

- Every draw is `voyage.rng_raw(battle id, 1, 'tick:<t>:<hull>:<what>:<shot>', secret)`: keyed by the tick, the hull and the purpose, never by a
  counter. A re-run with something new from tick T (a joiner, a player's act) is therefore the same fight before T, event for event.
- **NPC battles need no client:** the whole fight is ONE call at the open (`public.tick_battle_run`), stored, and closed by the minute job (or
  `cmd.battle_settle`). No per-tick server work, no new job, no new cron.
- **Budget:** a fight is ~5 ms of CPU in PGlite (wasm; native is faster), 100 fights measured in 523 ms. At the current ~100 battles an hour that is
  ~0.5 s of CPU an hour. ROWS: none new a battle (the timeline is a column of the battle row, ~2-5 KB as text, TOASTed and compressed); the old
  engine wrote 7 `battle_rounds` rows a battle and the tick battle writes 0, so it is ~-700 rows an hour at 100 battles. The row is deleted with
  the raid after `raid_keep_hours` (48 h): ~4,800 raids x ~2 KB = ~10 MB held at the ceiling. A re-run (slice 2) is one more ~5 ms call and one
  row update per act or join.

## 11. The client screens (other builders; the contract above is all they need)

- **The battle screen:** a wide overlay (full width on desktop, full screen on a phone), opened from the red circle's tap and from her fleet card.
  Both sides' ships drawn ENLARGED (our own simple SVG hull shapes), circling slowly; cannon flashes and smoke at a shot, a splash at a miss, the hit
  number rising (crit larger), an HP bar over each ship, a fleeing ship turning and pulling away (then gone, or turning back), a ship at 0 heeling
  over or striking her colours. The Fury bar for each side; the ACTION BAR (Broadside, Chain Shot, Rake, Grapeshot, Brace, Patch, Run, Pay) with
  cooldown sweeps that light as the AI uses them (slice 1: watch only; slice 2: pressable for her own side); the log, every event in words.
  At the end it calls `cmd.battle_settle` and reads `world.battle_ticks` once more for the loot.
- **The map:** every ship in a fight drawn red; the Join button on the circle's tray when one of her fleets is free inside it (0436).

## 12. The slices

1. **0435 (this branch): the engine and its wiring.** `public.tick_fight` (pure), `public.tick_row`, `public.tick_battle_run` (the one (re)run:
   sheet -> timeline -> battles.ticks, resolves_at), `public.battle_sheet_freeze` calls it for `tick_fight_kinds`, `public.battle_fight` /
   `public.battle_advance` read the timeline instead of rounds, `world.battle_ticks`, `cmd.battle_settle`, `fight_card` serves `reach_nm` and `ticks`.
   Proof 136. Client: the battle screen and the map's red ships (parallel builders).
2. **0436: joining.** `cmd.battle_join`, `battle_sides.how` JOINED, the NPC join rule in the navy's and pirates' steps; the Join button.
3. **0437: the player acts.** `cmd.battle_act` (abilities, Run, Pay) into `sheet.acts`, the re-run, a player's side on HOLD (autos only) between acts.
