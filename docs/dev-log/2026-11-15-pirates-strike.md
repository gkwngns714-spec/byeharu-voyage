# 2026-11-15 · pirates-strike · 0427 THE PIRATES STRIKE (owner row 347)

The owner, 2026-11-15: *"spawn rate of pirates should be faster alot. attack rate of pirates with other merchants should be done also
frequently. in stats i see no engagement"*. Earlier (row 329): pirates *"engage combat more aggressively with other npcs and players"*; no PvP.

## What production showed (read-only, 2026-11-15 00:19 UTC, head 0425, gate green: beat 93 ms, 1,002 MB)

`scripts/ops/harness/pirate-war/after.sql` (run as the "before") and `scripts/ops/harness/pirate-war/purse.sql`:

| figure | value |
|---|---|
| `public.battles`, all time | **0** (no ATTACK, no PROBE, ever) |
| pirate fleets | 87 (80 of the 108 roster fleets built) |
| laid up | **79**, all of them unpaid (the oldest unpaid since 2026-11-14 12:40, laid up since 15:15) |
| cruising (`pirate_ships_cruising`) | **3**, each with merchants within ~240 miles (33 among the three) |
| wrecks lying | 5, the oldest 52 minutes (respawn 60) |
| merchants under sail | 851 |
| the day's room | 2,283,791 (0.24 % of the 951.6 M hoard; renewed at 00:00 UTC) |
| spent on 2026-11-14 | **5,211,000** (11-11: 380,000; 11-12: 457,500; 11-13: 485,000) |
| an hour's pay a ship | 500 (`navy_upkeep_day` 12,000 / 24); 87 ships = 1.04 M a day |
| pirate cities' purses | Port Royal 951.3 M (the hoard); the other eight 648 to 176,173 |

## THE ROOT CAUSE: no pirate ever reached the battle

`public.battle_open` (0323) is the only writer of `public.battles`. On the head world it has exactly ONE caller, `public.attack_for` (0327), the
player's door behind `cmd.attack` / `cmd.preview_attack`:

- `public.attack_for`, its second gate: `if not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = p_player) then
  perform cmd.refuse('E_NO_SUCH_FLEET', 'that fleet is not yours');` — the caller is a signed-in player; no job calls it.
- `public.battle_open` itself: `if p_kind is null or p_kind not in ('PROBE', 'ATTACK') then raise exception 'E_BAD_KIND'` and
  `if not (select p.is_npc from public.players p where p.id = d.player_id) then raise exception 'E_HUMAN_TARGET'` — no kind for a pirate's
  attack, and no player's ship may ever be a defender.
- The pirate ship's own step, `public.pirate_ship_step` (0339, 0414, 0415), run each minute by `public.tick_pirates`, only sails out, lies at her
  haunt, trades, sails home and is laid up or reborn. **It calls no attack.**

What the pirates DO fight is elsewhere and writes no battle row: a merchant's voyage rolls PIRATES days in `voyage.settle` (0339: a named raider
fights in one call, plunder, RANSOM/LOOT), and the navy's hunt fights a pirate ship in `public.navy_fight` (0340: one call, a NAVY_FIGHT event).
So `battles` stayed at 0 because no player has pressed Attack.

A second cause of "no engagement" is the pirates' money pace: 79 of 87 fleets are laid up. The hour's pay goes through the day's room
(`public.pirate_pay`); 2026-11-14 spent 5.21 M against a room of ~2.3 M, so each fleet the next hour could not pay was laid up, and a laid-up fleet
is woken only one in `pirate_add_minutes` (5) and only while the room can pay her hour. Until 00:00 UTC nothing woke.

## What 0427 does

1. **A pirate strikes, through the one battle.** Each minute, after its steps, its add and its pay (and never behind a trade's locks),
   `public.tick_pirates` calls `public.pirate_strikes`: the hunting pirates (`public.pirate_ships_cruising`: out for her haunt or lying at it, a hull
   left; and free) not resting are asked in a turning order; each takes the nearest merchant within `attack_reach_nm` (240) — a company's merchant,
   a crown's cargo ship or a PLAYER'S ship; never a navy or pirate ship, never one of the pirates' own country, never one in port, never one set
   upon in the last `attack_ship_minutes` (60) — and opens the battle on her with `public.battle_open('RAID', ...)`. Both rows are taken now or not
   at all (`skip locked`), so the job never waits on the beat or a press.
2. **Kind RAID** in `battles_kind_check`. `battle_open` takes it only from a pirate ship (an NPC) on a merchant; for RAID alone the human-defender
   refusal does not apply (a pirate is no player). Every other kind keeps the law: no player fights another player (proved: an ATTACK on a
   player's ship is still E_HUMAN_TARGET; a merchant opening a RAID is E_BAD_TARGET). A raid calls the navy (a crown's cargo ship's country answers)
   and is fought round by round on a sheet, as an attack is; it lasts `battle_seconds` (600).
3. **A raid closes** in `public.battle_resolve` (one hunk) through `public.raid_close`: won (PLUNDERED or RANSOM), a cargo ship's funds aboard,
   `loot_share`, go to the pirate's home (`pirate_loot_book`, LOOT); any other merchant pays a ransom from her company's purse (`pirate_ransom`,
   RANSOM); thrown back, the pirate loses hands; a side with every hull at 0 at sea is a wreck by 0322's rule. A player's ship gets a
   BATTLE_REPORT ("Pirates came alongside, and we threw them back."). Gold only, moved, never minted (proof 128: the world's money unmoved).
4. **Faster** (each knob moved only from prod's value): `pirate_add_minutes` 5 -> 1, `pirate_respawn_minutes` 60 -> 5, `pirate_spend_day_pct`
   0.0024 -> 0.006 (the day's room 2.28 M -> 5.7 M of a 951 M hoard: yesterday's 5.21 M fits, so the hour's pay, the wakes and a wreck's refit stop
   waiting for 00:00 UTC). **Who pays is unchanged** ("just like before"): her own purse, her home, another pirate city, then the hoard inside the room.
5. **The Stats count the battles.** `public.stats_fleets_count`'s window adds raids opened, raids won by the pirates, raids the merchants held,
   raids the navy came to, players' attacks; `world.stats_fleets` serves `battles` over 24 hours; the Ships face shows a **Battles / 교전** card:
   Raids, Pirates won, Ships held, Navy came, Navy fights (the hunt's), Attacks.

## The rates (decided by default)

| knob | value | meaning |
|---|---|---|
| `pirate_strike_minutes` | 5 | a pirate strikes at most once in 5 minutes |
| `pirate_strikes_per_run` | 2 | at most 2 raids opened a minute: **at most 120 an hour** (0 stops every new raid) |
| `pirate_strike_tries_per_run` | 8 | at most 8 pirates asked for a target a minute |
| `raid_keep_hours` | 48 | a closed raid is deleted 48 h after it closed, at most 20 a run |
| `attack_reach_nm`, `attack_ship_minutes` | 240, 60 | unchanged: the reach, and a merchant set upon rests an hour |

**Expected battles an hour:** in the first hour ~30-60 (3 hunting pirates at 00:19, each striking every 5 minutes when a merchant is in reach,
plus the laid-up fleets woken one a minute with the room renewed); once the fleets are back at sea (~1.5 h: 79 wakes at one a minute, then the
passage to their haunts at 4.5x speed), **the ceiling, ~120 an hour**, about 20 battles running at once. The Stats card shows them at the next
count (four an hour).

**Rows a minute:** a raid is ~40 row writes over its 10 minutes (the battle, 2-3 sides, 7 rounds and their updates, two holds, hulls, crew, 1-3
money rows, an event): 2 a minute = ~80; the retention ~20; the add every minute ~5. **About +100 rows a minute at the ceiling**, inside a
per-minute job's 5,000 and far inside half the budget. The search reads the sailing voyages once a pirate asked (~850 rows, two sums each), 8 a
minute. No job, no table; one partial index. The table holds at most ~5,800 raids (48 h x 120).

## Proofs

- `scripts/db/proofs/128_the_pirates_strike.sql` (7 markers, local green): the minute job opens one RAID on the nearest merchant; it closes at its
  clock with the money unmoved; the pirate rests 5 minutes, then strikes the next merchant (a player's ship), never the one she fought; the
  player gets her report; no ATTACK on a player, no RAID by a merchant; the Stats window and `world.stats_fleets` count them; the retention deletes
  an old raid and never an ATTACK.
- 0427's own probe, rolled back: on the head world with a hunting pirate (`scripts/ops/harness/pirate-war/scene-hunting.sql` before the file) it
  strikes a MERCHANT through `public.pirate_strike`; without one it says so. On prod (3 hunting) it takes the lit branch.
- `scripts/ops/harness/pirate-war/probe.mjs --pre=... --fix [rollback-0427.sql]`: the file applies in ~100 ms; the rollback draft reverses it.

## The after-check (30 minutes, this changes live play)

1. Before: `scripts/ops/harness/db-health/gate.sql` (gate_ok), then `scripts/ops/harness/pirate-war/before.sql` (applied false, battles 0).
2. +10 min: `after.sql`: applied true; `battles.raid_1h` > 0, `fighting` > 0, `stuck` 0; `by_defender` only MERCHANT / CARGO_SHIP / COMPANY.
3. +30 min: `after.sql` again: `raid_1h` 20-60 (at most 2 a minute), `stuck` 0, `pirates.laid_up` falling (~1 a minute), `pirates.wrecked_oldest_min`
   under 10, beat mean under 1,000 ms; then the gate. `cron.job_run_details` for `byeharu-voyage:pirates` and `:battles`: no failed run.
4. Fail lines (any one is a rollback): a raid stuck FIGHTING past its clock; a raid on a NAVY or PIRATE ship; a failed pirates or battles run;
   the beat over 2 s.

## Forward rollback (owner only)

Quick, no file: `pirate_strikes_per_run` 0 (no new raid; running ones close within 10 minutes), and the knobs back: `pirate_add_minutes` 5,
`pirate_respawn_minutes` 60, `pirate_spend_day_pct` 0.0024. Whole: `scripts/ops/harness/pirate-war/rollback-0427.sql`, a draft (the eight hunks
reversed, each checked once; the four functions and the index dropped; the closed raids deleted and RAID taken off the kind; the knobs back).

## Decided by default (the owner may reverse any)

- A player's ship at sea or at anchor may be raided by a pirate (the owner: "more aggressively with other npcs and players"); in port she is safe.
- A raid takes gold only (a cargo ship's funds, or a ransom on the cargo at cost), not goods, as 0327's attack decided.
- The day's room is 0.6 % of the hoard (was 0.24 %); the payers' order is unchanged.
- A raid lasts `battle_seconds` (600 s), the knob the owner set; a player's attack keeps its 60 s rounds.
- The pirates of the voyage's PIRATES days (0339) are untouched: a merchant may still meet a pirate on her passage as before; the raids are added.
