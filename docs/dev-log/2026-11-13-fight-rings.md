# 0364: fights show on the map (owner row 321)

The owner, 2026-11-13: *"i want a fight to be visible in map. in red circle surrounding all fleets. if more fleets participate, bigger circle. by clicking that circle, like info i want to see the actual fight"*.

Stacked on 0357 (live rounds, PR #612). One migration, 0364. It deploys after 0358 to 0363 by its number and shares no hunk with them.

## Which fights there are, and what a player sees after this deploys

| Fight | How it happens | On prod today | The ring |
|---|---|---|---|
| **A battle** | A company attacks (`cmd.attack`). Timed: a round a minute, 7 minutes. | Dark: `attack_enabled` is false. | None until the owner lights attacks. Then: every player sees it while it is fought, and 60 s after. |
| **Her own raid** | Pirates set upon one of her fleets on a voyage day. Settled in an instant. | Live (`combat_bite` true). | **From this deploy.** Only she sees it, for 5 minutes, where it happened. |
| **A navy fight** | A navy ship meets a pirate ship in one sea. One call, at most once an hour a ship. | Live (`navy_enabled` and `pirates_bite` true). | **From this deploy.** Every player sees it, for 5 minutes, where it happened. |

A press on any ring opens the actual fight: both sides, a hull bar each, and the log round by round with its result.

**How often (an estimate, not measured on prod):**
- **Raids.** The combat design puts a raid day at about one sea day in 30 to 60. A sea day is 90 real seconds. So a fleet that is at sea the whole hour meets about one raid an hour, and its ring stays 5 minutes. A company sees a raid ring only for its own fleets.
- **Navy fights.** A navy ship fights at most once an hour, a pirate ship at most once an hour, and the pass fights at most 5 a minute. So the world has at most one ring an hour for each pirate ship that is out, each for 5 minutes. With ten pirate ships out that is at most ten rings an hour, and on average less than one on the map at a time. The true figure needs a count of prod's `NAVY_FIGHT` events, which the builder did not read.

## What was built

**Server (0364). No knob, no job, no switch written.**
- `world.fights()`: the one read the map polls. It serves battles, her own recent raids and recent navy fights, each with a `kind` (BATTLE, RAID, NAVY), a place, a `size`, its fleets and, for a raid and a navy fight, the whole log.
- `world.fight(battle)`: any battle's log for a watcher (a timed battle grows, so its log is asked for while the sheet is open).
- `public.fight_card`: one battle's row, server-only.
- `public.navy_fight_log` and `public.navy_fight_keep`: the navy fight's log, kept. One row a navy ship, written over at each fight, so the table never grows past the number of navy ships. One line in `public.navy_fight` calls the keeper.
- An index on ended battles.
- The news row: "Fights on the map" / "지도에 전투 표시".

**A raid needed no change to the voyage.** 0353 already writes the raid's log on the day's own row the moment the day settles, and every read of her fleets settles them first. So the row is there while she is still at sea, and `world.fights()` reads it. `voyage.settle` is not cut. The `RAID` event of the design's C4-lite is not needed for the map and was not built.

**Client.** The ring and the sheet are the same components for all three kinds. A raid opens her own log as her History draws it, with what the day cost her. A navy fight opens as a watcher's: Attacker is the navy ship, Defender the pirate ship.

## The ring's size

In screen pixels, the same at every zoom:

    radius = max( 22 + 6 x (size - 2), capped at 64 ,  reach + 14 )

- `size` is: a battle's fleets that are there; a raid's fleet plus the raiders' ships from the log (one raider ship is 22 px; five are 46 px); a navy fight's ships on both sides.
- `reach` is how far the farthest fleet lies from the ring's centre on the glass. Only a timed battle has fleets' places; a raid and a navy fight stand on the place they happened.
- A raid's place is where her fleet was at the end of that voyage day (`voyage.position` at the day's own instant). A navy fight's place is where the navy ship was at the fight.

Red is the palette's danger colour: a 2 px line that breathes slowly, a thin dashed line inside it, a 10 % wash. Reduced motion leaves it still. It is painted under the harbours, the hulls and every name, and asks the label planner for nothing.

**The press.** The whole disc, never less than a 22 px radius. A city's name under a ring is still the city. A ring of 44 px radius or less takes every other press inside it. A wider one leaves a harbour, a merchant or an outside fleet its own press.

**How long a ring stays.** A battle: while it is fought, then 60 s with its result. A raid and a navy fight: 300 s from the fight's own instant. Both numbers are fixed in `world.fights()` and served (`keep_seconds`, `raid_seconds`).

## What a watcher sees, and why it is safe

- **A battle or a navy fight (everybody):** the place; the clock; each fleet's name, what it is, its company and country, its ships; the ships of the side that closed with hull and crew; the other side in sum; each round's range, shots, hits, damage, hull left and slip chance; the boarding's crews; the ending. Not served: loot, crew lost, the navy line, the pre-fight word, a stance, any purse, cargo, funds, route or destination. Both logs are cut to nine named keys.
- **A raid (only its own company):** what her History already tells her: the log and the day's cost in crew, cargo and ransom.
- No player fights a player, so a ring is never a way to find a target.

## Overlap with the other open migrations

- **0362 (news kinds) cuts `voyage.settle` in the PIRATES arm. 0364 does not cut `voyage.settle` at all**, so the two cannot meet. 0364's self-assert holds the digest of every function it does not name, `voyage.settle` among them.
- `public.navy_fight`: no file from 0358 to 0363 names it (read on `origin/batch-5`).
- The registry: 0364 cuts it on 0357's own `world.battle` row, which no other file touches.
- **Proved:** 0364 was applied locally on a chain that also carried `origin/batch-5`'s 0358, 0360, 0361, 0362 and 0363. Its self-assert passed (0.18 s).
- Order: after 0357, and by its number after 0362. It does not need 0362.

## NPC outcomes stay byte for byte

The one line added to `public.navy_fight` calls a keeper that writes one row of its own table and swallows its own errors. Proof 66 fights the same navy fight under the body before 0364 and after it and holds these equal as text: the answer, both ships' hulls, both fleets, the navy ship's row and stamp, the pirate ship's, the `NAVY_FIGHT` event, both voyages, every purse and the ledger. It then takes the keeper's table away and shows the fight is still that fight, with a warning.

## Decided by default (the owner may reverse each)

- **5 minutes** for a raid's and a navy fight's ring; **60 seconds** after a battle ends.
- **A raid's ring is hers alone.** Another company's raid is not shown to anybody.
- **A navy fight's ring is everybody's**, with its log.
- **A battle's ring tells any player where another company's fleet is fighting** (dark today). The chart still draws no rival hull.
- **The map asks every 5 s while a battle is being fought, every 15 s otherwise while any kind of fight is in use, every 60 s if none is, and never while the tab is hidden.** On prod that is every 15 s for each open map.
- **The words**: Attacker / Defender (공격 측 / 방어 측), Watching (관전 중), Your battle (내 해전), Navy fight (해군 교전), Raiders (해적).
- **One migration, not two**: one read serves all three kinds, so one file makes it.

## Measured locally (PGlite, the cached world at head 0357)

- The migration applies in about 0.25 s (made and cut 44 ms, catalog 82 ms, probe 119 ms). Its limit is 20 s.
- `world.fights()` as prod would ask it, 75 navy ships' rows, mean of 50 calls: **0.48 ms** for a company at sea with one raid and 5 navy fights to serve, **0.26 ms** for a company in port with the 5 navy fights, **0.10 ms** with nothing to serve.
- With battles (dark on prod): 0.40 ms with one, 5.9 ms with twenty.
- The keeper adds about **0.4 ms** to a navy fight (at most 5 a minute).
- A settled raid day costs nothing more than before: `voyage.settle` is unchanged. The settle of the proof's raid day took 7 ms here.
- Proof 66: 9 of 9 markers.
- Not measured on prod. At about 6x, the read would be near 3 ms with a raid and five navy fights. With 19 companies each polling every 15 s that is about 1.3 calls a second at most.

## Prod checks (read-only, one statement a file)

1. `scripts/ops/harness/fight-rings/volatility.sql`: every function the checks call is `s` or `i` (`world.fights()` is null before the deploy).
2. `before.sql`: 2 rows, each `old_times` 1 and `new_times` 0; `made` 0; `needs` 4; `attack` false; `navy` and `raids` say what is lit (expected true and true); `battles` 0; head = the migration before this one.
3. Deploy.
4. `after.sql`: 2 rows, each `new_times` 1; `made` 6; `doors` 2; `client_fns` 2; `anon_fns` 0; `stable` 3; `log_table` "rls, no client"; `attack` false; `battles` 0; `no_house` `{"on": false, "fights": []}`; `news` 1; head 0364. `kept` is 0 right after the deploy and rises as navy ships fight.
5. This changes what live players see, so: the 30-minute after-check. Within the hour `kept` in `after.sql` should be above 0, and a ring should be on the map.

Run locally on 2026-11-13 against the cached world: all read as wanted, and after `rollback-0364.sql` the `before.sql` statement reads `old_times` 1, `new_times` 0, `made` 0 on both rows. None was run on prod by the builder.

## Proven

- Server: the self-assert, and proof 66's nine markers: dark; a real attack's card; the watcher's log equal to her own card's; kept 60 s; reads write nothing; a real raid day on a voyage still at sea, read by her alone for 300 s; a navy fight old against new, then the real pass kept and read by everybody; the costs.
- Proofs 48 (the navy hunts), 56 and 60 still pass.
- Client seam: `tests/rpc.fights.spec.ts`. Geometry: `tests/map.fightRings.spec.ts`.
- Browser (`tests/map.fight.spec.ts`), 390 and 1280: a battle's ring, the press, the log growing a round, the ring going; her own battle with her stance buttons; **a real raid on her own voyage rings the map and opens its log; a real navy fight rings the map and opens its log.** English and Korean at 390 and 320: nothing cut, nothing sideways.

## Not proven

- Nothing was run on prod. The rings-an-hour figures are estimates.
- A navy fight's ring in the browser stands at a navy ship lying in port (the fixture's). A fight between two ships under sail is proved on the server only.
- A raid's ring is found within 15 s of the map's next ask. A raid settled while she was offline shows only if she opens the map within 5 minutes of that day's instant.
- A watched battle in the browser has no hull inside its ring: the chart never draws another company's fleet.
- Many rings at once on a real glass were not looked at.

## Rollback

Forward, owner only. `scripts/ops/harness/fight-rings/rollback-0364.sql` is the draft: both hunks reversed, the four functions, the table and the index dropped. The navy's fights go on exactly as they did.

## 2026-11-13: `rpc.fights` red on CI, green on the desk: a distance that was the runner's speed

**What happened.** On #628's run `tests/rpc.fights.spec.ts` failed at `expect(a[0] - card.lat).toBeCloseTo(0.2, 3)`: received 0.1993. The two tests after it failed too.

**The cause.** Not the dice. The spec lays the attacker at anchor 0.2 degrees north of the cargo ship's point in `beforeAll`, and opens the battle in a later test. A cargo ship under sail covers about 0.02 degrees a real second (960x), so by the time the battle opened she had moved on, and the battle's place is where she was at the open. The gap between the anchor and the battle's place is therefore 0.2 less whatever the ship sailed in between: 0.0007 on CI, under 0.0005 on a faster desk. The read never promised that distance.

**The two tests after it were cascades.** Playwright starts a new worker after a failure, the new worker builds a new world, and the battle the failed test had opened is not in it. Proved by reading: both use `battle`, which only the second test sets.

**What changed in the spec.**
- It now asserts what the read guarantees: the attacker's served place is her stored anchor to the digit; the ship set upon is held at the battle's place to within 0.0002 (both are `voyage.position` rounded to 4 places, one unit each way). The distance between the two is no longer asserted.
- The file is serial, so a failure skips what follows instead of failing it on another world.
- The navy test no longer fights with what the earlier battle left of two fleets' hulls (the dice's); it fights two whole hulls written in the spec.

**Other places that held on one world's dice or one clock, found by reading and fixed.**
- Proof 66, FIGHTS_KEPT: the card of a battle "just over" was read where the dice ended it. A fight that ends in its first round ended 70 s ago by that battle's clock, which is past the 60 s the map keeps it. The proof now puts the end 5 s ago before it reads.
- Proof 66, NAVY_KEPT: the place and the hull after the fight were compared with the navy ship as she is after the pass. A fight that sinks her sends her home. They are now compared with her place read before the fight and with what the fight's own answer took.
- `tests/map.fight.spec.ts`: it waited for a first round to be shown. A fight may end before one. It now waits for a round or for the end, and reads the round's words only when there is one. The raid's "Lost" line is asserted to be there, not to name the crew.

**Proved under other worlds' dice.** `scripts/ops/harness/fight-rings/dice.mjs` gives the world another `world_secret` (64 random hex characters, as 0031 requires) and runs the proof, the RPC spec and, with `--browser`, the browser spec. `SPEC_WORLD_SECRET` is the knob the spec and the fixtures read. The figures are in the PR.

## 2026-11-13: `map.tray.edge` at 1440 on the combined tree: not this change

`tests/map.tray.edge.spec.ts:49` failed once on #632 at 1440 with `1024` against `> 1074`. Its own header records the same failure with the same two numbers on main on 2026-11-05 and 2026-11-07, before this branch existed.

What was checked in this change:
- The poll (`useFights`) sets state only when the answer differs. With no fight served it hands React the very list it already holds, so the map does not render. That was already so for an empty answer; it is now so for any unchanged answer (`sameOrNext`, held by `tests/map.fightRings.spec.ts`).
- Nothing of this change keys, wraps or re-mounts the map's detail tray. `FightSheet` is a sibling that is mounted only when a ring is pressed.
- `call()` has no side effect for a read: no store is written, nothing is invalidated.
- The poll adds two short statements to the tab's one database queue every 15 s. The tray's slide is a CSS animation and its removal a timer; neither waits on that queue.

So the spec was left alone.
