# 0375: a company may attack (lights `attack_enabled`)

Owner row 324: *"do all, make everything work. open them if everything is built and is workable."* The readiness work is `docs/dev-log/2026-11-13-attacks-ready.md`; read its sections 2 and 3 first. This file is the light itself: one switch and one news row.

**State: built, PR open, NOT deployed. It alters live play: its own window, a 30-minute after-check, rollback ready.**

## What a player sees when it is lit

- **Attack** on the card of a cargo ship, a navy ship or a pirate ship of another country (map, press a hull). Before the press the card says: the foe in a word (Weaker, About even, Stronger, Far stronger), her funds in a word, the miles, and when the navy would arrive.
- A fleet may attack if it has guns and an empty hold, within 240 miles, once in 30 minutes. Never another player's fleet, never a merchant, never a ship of her own country, never a ship in port.
- **A battle of seven minutes**: six rounds a minute apart, then the boarding. The card shows each round as it is fought, both hull bars, the countdown, and Fight / Flee. Flee takes hold from the next round and may or may not get her away.
- **A red ring on the map** round the battle, for every player; pressing it shows the fight (watch-only for others).
- **Gold**: boarded, 15 % of the funds aboard; paid off, 8 %; counted for the share of her own hull she lost in the fight (0374), at most 60,000 d. a battle and 240,000 d. a company in 24 hours. Moved from the ship's funds, never minted.
- History keeps the report with its whole log.

## What it costs her

- **Standing, at once**: 150 regard with that country for a cargo ship, 250 for a navy ship, 100 more if she sinks her. About two attacks make her Hostile there (tax and dock fee doubled); buying it back is 200 d. a point.
- **The navy**: up to three of that country's ships sail to the battle. The sim: a navy ship that comes up turns a Nau's 3 wins in 4 into none.
- **Hands and hull**: a tenth of her hands when she is beaten or breaks off; her hull by the fight.
- **WANTED** for 48 hours when she wins or no navy came in time. With `navy_hunt_per_day` 0 that is a line in History and nothing more (the hunt is its own later light).
- Both fleets stand still for the battle; her orders wait.

## The guards

0375 refuses unless `public.attack_ready()` (0374) says ready, the same reading `before-light.sql` prints first:

| Check | Refuses when |
|---|---|
| `loot_rule_on` | 0374's rule is off (`loot_risk_full` 0 or `loot_risk_floor` 1) |
| `clock_sane` | `battle_round_seconds` is not 30 to 120 |
| `regard_lit` | `regard_enabled` is off (an attack would cost no standing) |
| `npc_levels_lit`, `levels_written` | `npc_ship_level_enabled` is off, or the level is on fewer than 9 cargo hulls in 10 |
| `convoy_armed_lit` | `convoy_armed_enabled` is off |
| `navy_lit` | `navy_enabled` is off |
| `cargo_safe` | more than a tenth of the cargo ships at sea are unarmed |

The last five bind where cargo ships sail (production). A world built from the chain alone has none, so the file applies there: that keeps CI and the shipped image building. It also refuses if attacks are already lit or a battle is being fought.

`navy_enabled` is a guard the brief did not list. Added because the news row tells players the navy answers. Decided by default.

`scripts/ops/harness/attacks/proof-0375.mjs` applies the real file on 13 worlds: it applies on the chain's own world, on production-as-it-will-be, and at the threshold (1 unarmed of 10 at sea); it refuses, naming its reason, with each switch off in turn, the level unwritten, 3 unarmed of 10, the loot rule off, attacks already lit, and a second time. All 13 as wanted.

## Proof

- Self-assert: the switch reads on; no other knob and no function moved; on a rolled-back probe the door is open (a preview of no ship is refused for its target, not for E_NOT_IN_USE) and a player's fleet is refused (E_HUMAN_TARGET) by the preview and by the press; the news row once. 55 ms locally.
- Proof 75 (`scripts/db/proofs/75_a_company_may_attack.sql`), 5 markers, with production's other switches lit inside it: a whole battle through `cmd.preview_attack`, `cmd.attack`, `world.battle`, `world.fights` and the minute job called minute by minute; the after-check's seven lines on that battle; the three refusals; and the rollback (switch off: a new press refused, the running battle still closes and pays). Green, and under 10 other worlds' dice (the battle ended PLUNDERED, RANSOM and DRIVEN_OFF across them).
- Proofs 31, 34, 39, 40, 41, 46, 48, 49, 56, 60, 64, 66, 74 green on the lit chain. Proof 31 refused to run in a world with attacks on; it now sets the switch off first, as every other proof of the family does.
- `rpc.attack`, `rpc.battle` and `rpc.fights` each begin with a "dark" test. The built world is lit from this file on, so each now sets the switch off before it (the state after a rollback), then lights it as before.

## PROD CHECKS, in order (each one read-only statement; none was run by the builder)

Before, after 0369 to 0374 are deployed:
1. `npx --yes supabase@2.120.0 db query --linked "select max(version) from supabase_migrations.schema_migrations"`: 0374.
2. `-f scripts/ops/harness/attacks/before-light.sql`: `ready.ready` true, `ready.lived` true, `ready.why` [], every check true; `attack_lit` false; `untouched` all 0; `doors` 4. Read `companies.with_guns`: who can attack on day one.
3. `-f scripts/ops/harness/attacks/cargo-at-sea.sql`: `unsafe.share` at most 0.10. Keep `aboard` (median, p90, how many at 400,000 or more) for the dev-log: it is what a boarding is worth.
4. `-f scripts/ops/harness/attacks/after-job.sql`: `job_active` true, `failed` 0, `last_run` within 2 minutes (the battles job already runs every minute, dark).
5. `bash scripts/ops/health.sh`.

Deploy with `~/bin/bv-deploy.sh <pr>`, about 20 minutes before a :37, never at :06 to :08 or :36 to :38, and not inside 30 minutes of another light.

After:
6. At once: `before-light.sql` again: `attack_lit` true. The news row is on the News face.
7. +5 and +15 minutes: `after-battles.sql`, `after-rounds.sql`, `after-loot.sql` by hand.
8. +30 minutes: `bash scripts/ops/harness/attacks/after-check.sh '<start>' '<end>'`, then `bash scripts/ops/health.sh`. With no battle in the window the check passes on nothing: say so, and run it again after the first battles.

## Rollback

`update public.world_config set value = 'false'::jsonb where key = 'attack_enabled'` (the owner's line), or `scripts/ops/harness/attacks/rollback-0375.sql` as the next migration (it posts its own news row). New presses are refused at once. A battle being fought finishes at its clock and still pays; loot, regard and WANTED marks stay. Proof 75 `LIT_SWITCH_OFF` holds that.

## Read before lighting

- **Who can attack today.** The audit read 16 of 19 companies owning one ship, and the starter Barca has no guns. `before-light.sql` prints how many companies own a gun. If it is 0 or 1, the first battles may be days away and the after-check will have nothing to read.
- **A strong fleet still has a small income at next to no risk** (readiness dev-log, section 2): about 3,400 to 4,000 d. a battle at 100,000 aboard. Its price is standing. The designed answer is the navy's hunt, dark.
- **Break-off costs a tenth of her hands** even before a shot lands. The card does not warn of it.
- **A new player cannot be attacked by anyone**: no player fights a player, in any file.

## Not proven

- Nothing was run on production.
- The first real battle against the real minute job at 60 s a round.
- Two companies attacking the same ship in the same second (reasoned in 0327: both meet on her fleet row; PGlite has one session).
- What the navy's sailing to battles does to its patrols on production's map.
