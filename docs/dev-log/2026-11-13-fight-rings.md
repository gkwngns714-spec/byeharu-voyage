# 0364: a fight shows on the map (owner row 321)

The owner, 2026-11-13: *"i want a fight to be visible in map. in red circle surrounding all fleets. if more fleets participate, bigger circle. by clicking that circle, like info i want to see the actual fight"*.

Stacked on 0357 (live rounds, PR #612). It needs 0357's battle sheet and log.

## Which fights exist today

Read on the bodies at head 0357:

- **A timed, placed battle** is a row of `public.battles`. One function writes it, `public.battle_open`, and its one caller is `public.attack_for` (`cmd.attack`): a company's fleet attacks a cargo ship, a navy ship or a pirate ship. It is behind `attack_enabled`, which is false on prod. Escorts and called navy ships join such a battle; nothing else opens one.
- **A pirate raid on a voyage day** is settled in an instant inside `voyage.settle`. It has no duration and no row in `public.battles`.
- **A navy ship against a pirate ship** (0340) is one call, once an hour, "no timer, nobody watching". It has no row in `public.battles` either. It writes one public event, `NAVY_FIGHT`, and the navy ship's last fight on her card.

**So with the switches as they are on prod (`attack_enabled` false), no timed battle can exist, and a player sees no ring.** Nothing on the map changes at this deploy. The ring shows from the moment the owner lights `attack_enabled`.

## What it does

- **Server, three reads and one index. No table, column, knob, job or write.**
  - `world.fights()`: every battle being fought, and every battle that ended within the last 60 seconds. For each: its place, its clock and round, the fleets on each side (name, what it is, its company, its country, its ships, where it lies now), how many fleets and ships are there, and whether it is the reader's own.
  - `world.fight(battle)`: any battle's log, for anyone signed in. It is the shape `world.battle` serves her own in, with `watch` true.
  - `public.fight_card`: one battle's row, server-only.
- **The map.** A red ring round the fleets of each battle. A press on it opens a tray with both sides, a hull bar each, the next round's countdown and the fight's log. The log grows while the tray is open. Her own battle opens her own card, with the stance buttons; anybody else's is watch-only.
- **The local world's clock.** `src/lib/rpc/localBackend.ts` runs `public.tick_battles` before a read of the battles on the map, as it runs the arrivals job before a read of the ships. On Supabase the minute job does it.

## The ring's size

In screen pixels, the same at every zoom:

    radius = max( 22 + 6 x (fleets - 2), capped at 64 ,  reach + 14 )

- 22 px for the two fleets a battle starts with: a 44 px circle, the touch floor.
- 6 px more for each further fleet that has come up, to 64 px at nine fleets.
- `reach` is how far the farthest fleet lies from the ring's centre on the glass. An attacker may lie up to 240 nm from the ship she set upon (`attack_reach_nm`), so zoomed in the ring is as wide as the fight; zoomed out the fleets fall together and the count sets it.
- The centre is the middle of the box round the fleets' places and the battle's own place.

Red is the palette's danger colour: a 2 px line that breathes slowly, a thin dashed line inside it, and a 10 % wash. Reduced motion leaves it still at full strength. It is painted under the harbours, the hulls and every name. It is not a label and asks the label planner for nothing.

**The press.** The whole disc, never less than a 22 px radius. A city's name under a ring is still the city. A small ring (44 px radius or less) takes every other press inside it. A wide ring leaves a harbour, a merchant or a fleet that is not in the battle its own press, and takes the open water and its own fleets.

**When it ends.** The server keeps serving the battle for 60 seconds with its ending. The ring stays where it was, still and fainter, then goes. An open tray keeps the result for the reader.

## What a watcher sees, and why it is safe

Served to any signed-in player: the place; the clock and the round; each fleet's name, what it is, its company's name and country, its count of ships; the ships of the side that attacked by name with hull points and crew; the other side's name, ships, crew and hull in sum; each round's range, shots, hits, damage, hull left and the chance rolled to slip; the boarding's two crews; how it ended.

Not served to a watcher: loot, crew lost, the navy line, the pre-fight word, her stance or the stances she may take, and any purse, cargo, cargo value, funds aboard, route or destination. The log is cut to nine named keys (`v, atk, first, foe, you, r, board, after, end`), so a key a later migration adds to a log does not reach a watcher by accident. The self-assert and proof 66 hold both lists.

No player fights a player (both refusals are untouched), so a ring cannot be used to find a company to attack.

## Decided by default (the owner may reverse each)

- **A ring tells any player where another company's fleet is fighting**, for the minutes of the battle. Until now no read told one company where another's fleet was. The owner asked that a fight be visible, so it is. The chart still does not draw another company's hull: a watcher sees the ring, and the fleet's name in the tray.
- **Kept 60 seconds after the end**, fixed in `world.fights()`.
- **The map asks every 5 s while a battle is shown, every 15 s when attacks are in use and none is shown, every 60 s while attacks are dark**, and never while the tab is hidden. The open tray asks for its battle every 5 s.
- **A small ring takes a press on a harbour mark under it** (not on its name). Zooming in separates them.
- **The words**: Attacker / Defender (공격 측 / 방어 측), Watching (관전 중), Your battle (내 해전).
- **No news row** (`-- news: none`): nothing shows while attacks are dark.

## Showing a raid that has just been settled: a recommendation, not built

A raid is the only fighting a player meets today, and it has no duration. Two honest ways to show one for a short while:

1. **Her own raid.** A ring at her fleet's hull for a few minutes after a raid day settles, opening the raid's log (0353 keeps it; `FightLog` already draws it). This needs no new battle row, but it needs the day's row to reach the map while she is still at sea. That was not checked here.
2. **A navy ship against a pirate ship**, which does happen on prod now (`navy_enabled` and `pirates_bite` are true). The server stamps the navy ship (`navy_ships.fought_at`, `fought`). `world.fights()` could serve those from the last ten minutes as a ring at the navy ship. But no log of that fight is kept, so a press could show only who fought and who won.

**Recommendation: build 1 as its own small slice, and leave 2 until the owner says a ring with no log to open is wanted.** Neither is in this PR: each adds a second kind of ring whose press shows something different, and that deserves the owner's eye first.

## Measured locally (PGlite, the cached world at head 0357)

- The migration applies in about 0.15 s (made and cut 32 ms, catalog 31 ms, probe 89 ms). Its limit is 20 s.
- `world.fights()`, mean of 20 calls inside proof 66: under the clock's grain (0.00 ms) with no battle, 0.30 ms with one, 6.15 ms with twenty (each two fleets, one of them a held voyage).
- Proof 66: 6 of 6 markers, 1.5 s.
- Not measured on prod. At about 6x, twenty battles would be near 40 ms a call.

## Prod checks (read-only, one statement a file)

1. `scripts/ops/harness/fight-rings/volatility.sql`: every function the checks call is `s` or `i` (`world.fights()` is null before the deploy).
2. `before.sql`: `old_times` 1, `new_times` 0, `made` 0, `needs` 4 (0357 is deployed), `attack` false, `battles` 0, head = the migration before this one.
3. `after.sql`: `new_times` 1, `made` 4, `doors` 2, `client_fns` 2, `anon_fns` 0, `stable` 3, `attack` false, `battles` 0, `no_house` `{"on": false, "fights": []}`, head 0364.

Run locally on 2026-11-13 against the cached world: all three read as wanted, and after `rollback-0364.sql` the `before.sql` statement reads `old_times` 1, `new_times` 0, `made` 0. None was run on prod by the builder.

## Proven

- Server: the self-assert; proof 66 (dark; the card of a real attack read by a neighbour; the watcher's log equal to her own card's log key for key at three stages; kept 60 s; neither read writes or advances; 0, 1 and 20 battles).
- Client seam: `tests/rpc.fights.spec.ts` on the built world.
- Geometry: `tests/map.fightRings.spec.ts` (radius by fleets, the ring round every fleet, the press).
- Browser, 390 and 1280: `tests/map.fight.spec.ts`. The ring is on the map; a press opens the fight; the log grows a round; the result is told; the ring goes. Her own battle: her hull is inside the ring and her stance buttons are there. English and Korean at 390, 320 and 1280: nothing cut, nothing sideways.

## Not proven

- Nothing was run on prod.
- A watched battle in the browser has no hull inside its ring: the chart never draws another company's fleet, and the shipped local world does not serve cargo ships while its merchants are dark. The ring round a drawn hull is proved on her own battle.
- A battle with a called navy ship on the map is proved on the server (proof 66, rows of the proof) and in the geometry spec, not in a browser.
- Many rings at once on a real glass were not looked at. Twenty were measured on the server only.

## Rollback

Forward, owner only. First the switch: `attack_enabled` false, and no ring is drawn once the running battles end. The whole slice: `scripts/ops/harness/fight-rings/rollback-0364.sql` is the draft of the reversing migration.
