# 0357: a battle is fought round by round (C3, dark)

Slice C3 of `docs/COMBAT_LOG.md` (sections 3, 5.2, 6), owner row 315: *"when pressed fight, it keeps on fighting, when flee, it tries to flee ... showing logs, damages"*.

**Everything here is dark.** A battle exists only behind `attack_enabled`, which is false on prod. This file does not write that switch, or any existing knob. With the switch off, no body takes a new branch for anyone.

## What it does, in plain words

- A battle a player starts (`cmd.attack`) is no longer one call at its end. It is fought one round a minute: six rounds, then the boarding, 7 minutes in all.
- The log grows as it is fought. One row a round is kept in `public.battle_rounds`.
- Her stance is a door, `cmd.battle_stance`. **Fight** keeps fighting. **Flee** silences her guns, she takes that round's fire, then rolls to get away. Away is `BROKEN_OFF`: no loot.
- The card on screen polls `world.battle(fleet)` every 5 seconds, only while it is open, and draws the log with the same `FightLog` a raid uses.
- A hold at sea for a battle no longer costs days of stores and wages. The day she was held on is longer; the count of days is that of a voyage never held.
- No player fights a player. Both refusals (`E_HUMAN_TARGET`) are untouched, and the self-assert presses both.

## How it stays honest

No engine state is kept between rounds. The two sides are frozen once at the open (`battles.sheet`). Round N is the whole fight re-run to round N with the stances kept so far. Every dice roll is keyed by (battle, round), so a run to N is exactly the first N rows of a run to N + 1. A round logged on time, a late catch-up and a full re-run all give the same rows. The self-assert and proof 60 hold this as text.

## Where the code leaves the design

1. The read is keyed by her fleet, `world.battle(fleet)`, not by the battle id: the client knows the fleet and no read serves a battle id.
2. `public.battle_advance` logs rounds; `public.battle_resolve` stays the one closer and calls it first. The job's hunk is its WHERE alone.
3. The read re-runs the sheet instead of reading `battle_rounds`. The rows are the record; the proof holds the two equal.
4. A row of `battle_rounds` is the engine's own row, not the 14 compact cells. The read builds the cells, for either deck.
5. The clock is a new knob, `battle_round_seconds` 60 (so 420 s), never longer than `battle_seconds`. No existing knob is written. A probe keeps `battle_seconds`.
6. The side that attacked rolls to get away before her losses are read that round.
7. A fight that ends in a round ends the battle there and cuts the hold (`voyage.hold_cut`).
8. `voyage.arrival_at` carries the day count a third time, so it takes the same hunk as `voyage.total_days` and `voyage.days_complete`.
9. A fair wind after a hold may still make up the hold's hours (`voyage.settle` is not cut).
10. No human is ever set upon in a battle in this slice, so a defender's standing order as an opening stance is proved on the leaf and on a sheet the proof writes. No door reaches it.
11. The log of a battle she started says `atk: true`, so a reader knows whose deck it is, and it has its own endings (`A_NONE`, `A_LOST`, `A_BROKE`, `A_THROWN`, `A_TERMS`, `A_TOOK`, and `FLED`). A battle still being fought has no `end`.

## Decided by default (the owner may reverse each)

- **420 seconds, one round a minute**, the design's recommendation, not the 600 s default. It keeps a watched battle and an offline one on the same clock as the minute job.
- **Flee is a roll each round, one rule for both sides**, as section 3.3 chose. The owner's words are "it tries to flee".
- **Pay is not offered to the side that attacked.** She started it.
- **No news row** (`-- news: none`): nothing a player can see changes at this deploy. The news belongs to the step that lights `attack_enabled`.
- **A watched battle keeps time by the card**: when a round falls due the card sends her own stance again. The door writes nothing for a stance she already holds, and fights the round now, so the log does not wait up to a minute for the job.
- **The battle card is mounted in two places**: under the Attack section after the press, and on the fleet's fold while she is in a battle. It asks nothing at any other time, so a dark world sends no read.
- **Korean words**: 해전 (Battle), 태세 (Stance), 다음 라운드부터 (From next round), 전리품 (Loot), 선원 손실 (Crew lost).

## Measured locally (PGlite, the cached world at head 0353)

- The migration applies in about 7.0 s: engine parity 4.8 s (6,760 pairs, all 1,120 fights, all four endings), stances and prefix 1.8 s (1,120 fights), the rest 0.4 s. The pure fights are bounded by the clock (6 s and 4 s) and fail under their least (200 pairs, 20 fights); the hard limit is 40 s.
- Expected on prod at about 6x: 6 s + 4 s + about 3 s, so about 13 s.
- A probe 160-hour hold: 14 days before this file, 7 after (the voyage never held: 7).
- Proof 60: 14 of 14 markers, 7.5 s.
- The cost of the extra index probe on the day count was **not** measured here. The design's figure is 0323's, about 5 µs.

## Local body digests at head 0353 (`before.sql` prints prod's as `bodies`)

| body | md5 |
|---|---|
| `public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)` | e37521c89cbd5c37a163d9f7c4b9e548 |
| `public.battle_open(text,uuid,uuid,timestamp with time zone)` | 6478666cfbfbc18e0232738673c8e0e6 |
| `public.battle_resolve(uuid,timestamp with time zone)` | d470819ebc29823a43cd919afc8a248f |
| `public.tick_battles(timestamp with time zone)` | 7effd5902da726c0898eaf58657ed86d |
| `public.battle_words(jsonb,jsonb)` | 99eb1a0a6518025b0f817a6d0e0ee184 |
| `voyage.hold(uuid,timestamp with time zone,timestamp with time zone)` | f976dc5e39267033661ee5e48be9323d |
| `voyage.total_days(uuid)` | c6ec03f4b43321d259e9b728cd7440d4 |
| `voyage.days_complete(uuid,timestamp with time zone)` | 6165cbdb226440ea5de4fc46a2d1857f |
| `voyage.arrival_at(uuid,timestamp with time zone)` | 80262615b424382e250f31671622c9be |
| `public.client_rpc_entry_points()` | 2d5d49aa8dabaccd9c66610860594ff8 (moves with 0354, 0355, 0356: need not match) |

## Proof 56 (0353's)

Proof 56 pinned the old bodies by a fixed digest, so it went red as soon as this file re-cut `public.fight_sides` and the registry. Branch `fleet-room` (0354, #602) already rewrote it to judge the rebuild as a round trip on the live body. This branch carries that same file, byte for byte, so the two merge cleanly. It is green on 0357 (11 of 11).

## Prod checks (read-only, one statement a file)

1. `scripts/ops/harness/live-rounds/volatility.sql`: every function the checks call is `s` or `i`.
2. `before.sql`: 23 rows, every `old_times` 1 and `new_times` 0, `made` 0, `attack` false, `battles` 0, `holds` 0, head = the migration before this one.
3. `after.sql`: 23 rows `new_times` 1, `made` 17, `client_fns` 2, `anon_fns` 0, `doors` 2, tables "rls, no client", `attack` false, no battle, round, stance or hold row, knobs 60 and 600, both refusals stand, head 0357.
4. The golden digest (`scripts/ops/harness/two-sides/golden.sql`) before and after: it must not move.

None of these was run on prod by the builder.

## Not proven

- Nothing was run on prod. The 6x timing is an estimate from 0353's deploy.
- The card was not driven in a browser: attacks are dark, so no page can reach it. Its face is rendered in Node (`tests/battle.card.spec.ts`) and its doors are driven on the built world (`tests/rpc.battle.spec.ts`).
- A battle with a called navy ship on screen, and a human set upon (no door opens one), are proved on the server only (proof 60).

## Before lighting `attack_enabled` (its own step, owner only)

Section 3.6 of the design lists what the one switch opens. The known open point stands: an unarmed cargo ship loses almost every fight, so lighting attacks before `convoy_armed_enabled` is free gold. Lighting needs its 30-minute after-check and a news row.

## Rollback

Forward, owner only. The switch off stops new battles and the stance door; running ones finish under their last stance. The whole slice: `scripts/ops/harness/live-rounds/rollback-0357.sql` is the draft of the reversing migration.

The draft was run locally on 2026-11-13 after the file, in one scene with `before.sql`'s statement: 23 rows, every `old_times` 1, `new_times` 0, `made` 0.

## 2026-11-13: proof 60 red on CI, green on every desk: the dice are the world's own

**What happened.** `60_live_rounds.sql` went red on CI at CALLED_FROM (8 of 14 markers) on #612 and on the batch tree #626, and stayed green locally through 30 runs, the whole catch-all leg in CI's order, and five clock offsets.

**The cause.** Migration 0031 gives every built world its own `world_secret`, and every roll of a fight is keyed by it. So CI's cached world and a desk's cached world throw different dice for the same battle id. The proof assumed one outcome of them in two places:

- CALLED_FROM asserted that with a called ship the side's hull after round 3 is *greater* than without her. On CI's dice the first shot sank the target in round 1 and the round-3 shot sank the called ship (a cargo ship dies to one hit): 0 against 0.
- CLOSED_ONCE asserted that the job's call an hour on closes the battle. When her Flee gets her away in round 3 itself, the job's round-3 call is the one that closes it.

Read from CI itself: a draft PR (#627, closed) carried only a wider failure message. It printed the same seed, the same two sides, and hits in rounds 1 and 3 where this desk has them in rounds 4 and 6. Under 8 other secrets locally the old proof was green 2 times of 8, failing at one of the two places.

**A real fault found on the way.** CI's figures showed the side's starting hull as 790 for hulls of 261 + 268. With a called ship on the sheet, the engine counted every round-1 hull into the side's starting hull a second time (`a_from[i] = g` is true for a hull of round 1 at round 1). It moved `hull.a_start` in the answer, and the EVADED / DRIVEN_OFF word when the attacker broke off or fled having hit nothing. Fixed in hunk 3 (`a_from[i] > 1 and a_from[i] = g`); the self-assert and proof 60 now hold the starting hull to each hull once. Red first: the new proof on the old hunk fails at "the side's starting hull is not each hull once" (5,400 for 1,500 + 2,400).

**The proof now.** CALLED_FROM holds what is true under any dice: hull after round 3 = hull after round 2 + hers − what round 3 took, never more than was fired, and she is there (struck, or whole in what is left). CLOSED_ONCE counts the close over both calls. A failure prints which line and its figures. The secret is not pinned: a proof that holds on one world's dice only would go red again at the next cache rebuild.

**Not changed, and worth knowing.** A called ship's hulls are read when her round is fought. A job that runs late settles her to its own instant first, so a ship damaged on the way in between would join with the later hull. On the proof's quiet sea the two agree.
