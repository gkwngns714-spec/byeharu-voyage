# 2026-11-06 - The Levels page (Command desk, fifth face; migration 0325, a read only)

Owner, 2026-11-06: "first create a tab on command - levels. This page will show you all the info."

## Spec
A fifth face on the Command desk, after Report: **Levels** / 레벨. No control on it, so a press moves nothing. Wide: three panes (company, hulls and captains, room and countries). Phone: one column, company, room, then hulls and captains; the two lists scroll inside themselves. No sideways scroll at 1440, 1280, 1024, 390 (measured: `scrollWidth <= innerWidth`).

| Part | Shows | Read from |
|---|---|---|
| Trading, Exploration | level, a bar from where this level began to where the next begins, "N to level N+1", points, turnover or ports and nm | `world.levels()` over `player_progress` |
| Combat | the track once `playable`; until then "Not counted yet." | same |
| Seamanship | level of 5, marked a skill | `skill_level` |
| Title | name and level; the next title, what it needs, which sea zones ask it (said as "would open" while `sea_conditions_bite` is false) | `title_level`, `title_names`, `sea_zones` |
| Room | fleets used of open, ships in a fleet | `earned_caps` |
| Ships | every hull: earned level, bar, class, fleet, flagship, and "acts as level N" when levels do not bite yet | `ship_xp` through `level_line`, `level_in_force` |
| Captains | each captain's three earned levels, "(acts as level N)", and the server's cap line | the existing `world.captains` |
| Countries | each great power: band and score. While `regard_enabled` is false: "Not open yet." | `regard_of`, `regard_band` |
| Banner | "Ship and captain levels change nothing yet. They are counted and kept." while `levels_bite` is false; "...are working." lit | `levels_bite_on` |

**The truth while dark** (`levels_bite` false, untouched): earned levels are shown, never dressed as working. A hull with 115 points reads Level 3 and "acts as level 1". Title and fleet room do act today (they read no switch), so they are shown plainly.

## One authority, a migration was needed
`world.player` serves a track's points and level but not where the next level begins; `world.ship_view` serves the level in force (1 while dark), not the earned one; nothing served the title's next name, the room, or regard in one place. The client may not compute a level (the curve is `level_from_points`), so **migration 0325** adds, read-only and STABLE, no table, no knob, no row:
- `public.level_line(points)`: the one cut of points into `{points, level, from, next_at}` (the same expression as 0127's `next_level_at`). Granted to nobody.
- `world.levels()`: the page's one read, composing the readers above. Granted to `authenticated`. One hunk in `public.client_rpc_entry_points` (a row), once and reversing.
- Proof 32 (`scripts/db/proofs/32_levels_page.sql`, 6 markers, green locally 6/6). It was red first: the proof found my first draft read `regions.min_exploration_level`, which 0218 removed. There is no region door; exploration opens nothing by itself, so "what opens" is the next **title's** sea zones.

**Not deployed.** Auto-merge is off for this PR; the owner's deploy script pushes 0325 first. Until it is pushed, prod has no `world.levels`, and the face would show "Levels did not load."

## Not shown, and why
- What the next **Trading** level opens in fleet room: no reader answers "caps at level N+1", and a client sum would be a second calculation. Room is shown as it stands now.
- Captain levels and ships are not given a "needs" line beyond their bar.
- Achievements: none exist.

## Proof
tsc, eslint clean; `proof.mjs levels_page` 6/6 against the chain with 0325; the canary world rendered headless (persistent profile, DPR 2) at 1440, 1280, 1024 and 390, English, and 1440 and 390 Korean. The canary company is new (all level 1), so the screenshots show the dark truth with zeros; a lit or levelled company was proved by the SQL proof, not drawn. Specs for desk faces (`consistency`, `align`, `desk.inplace`, `onepage`) gained the Levels face and run in CI, not here.

Images: `img/levels-en-1440.jpg`, `levels-en-1280.jpg`, `levels-en-1024.jpg`, `levels-en-390.jpg`, `levels-en-390-end.jpg`, `levels-ko-1440.jpg`, `levels-ko-390.jpg`.
