# NAVIGATION — the plan, and what is measured

Written 2026-08-24 for the owner, who asked to see the plan before anything is built.

> *"do all the work in appropriate order, after research, build what you think it is best without
> ruining this game"*

**Status of this document:** the MEASUREMENTS below are real, taken from the prototype in
`scripts/proto/`. The reference-game research (`DESIGN_RESEARCH_NAVIGATION.md`) was **not finished** —
the agent writing it hit the session limit. That gap is stated rather than papered over; the owner
supplied the design directly, which is what the proposal is built on.

---

## 1. WHAT IS WRONG TODAY, measured

byeharu-voyage sails a **fixed graph of 782 precomputed legs** between ports. The owner's verdict:

> *"it should go by sea without the fixed route — but fastest way possible. Also, in map, i should be
> able to pinpoint anywhere in the ocean to make a fleet move."*

The prototype pathfinder was run against the shipping leg graph. It is worse than previously
diagnosed:

```
sea-grid.mjs's Lisboa→Nagasaki reaches 88.6°N
proto's        Lisboa→Nagasaki reaches 38.7°N
```

**The game currently routes Europe to Japan over the North Pole.** Its distances look *shorter*
because of it:

| route | shipping graph | honest path | ratio |
|---|---|---|---|
| Lisboa → Nagasaki | 7,565 nm | **12,989 nm** | ×1.72 |
| Antwerp → Honolulu | 6,501 nm | **14,040 nm** | ×2.16 |
| Nagasaki → Lisboa | 7,570 nm | **13,131 nm** | ×1.73 |
| Lisboa → Manila | 8,779 nm | **11,858 nm** | ×1.35 |

Every one of these numbers is served to a player, gates the endurance check, and prices
`world.trade_routes`. **The Asian trade is being quoted at roughly half its true distance.**

This is the same single cause as the four defects already logged: Brazil via Iceland, ships drawn
over land, 41 ports teleporting 20–72 nm, lanes across continents. One wrong model, five symptoms.

---

## 2. THE MODEL, as the owner specified it

- **The sea is a free plane.** Any water point is a destination.
- **Auto-sail pathfinds** the fastest way through the 0.25° water raster, computed at departure.
- **Wind and current change speed** — and the point is **provision risk**: a slow passage burns more
  stores.
- **NPCs distributed by area, with levels.** A panel on the map lists nearby contacts and their
  **distance**; the player clicks one to engage.
- **The empty ocean is filled by consequence:** attacks, and disasters that take crew, stores, cargo.

**A path found through water cells cannot cross land by construction.** The owner's law — *"i don't
want the fleet to ever touch land"* — stops needing a guard bolted on afterwards and becomes a
property of how a route is made.

---

## 3. IS IT FAST ENOUGH? — measured in Node

```
worst single search                    166 ms   (Nagasaki → Lisboa)
Lisboa → Nagasaki, 5 consecutive        75 ms each
40 random port pairs                    47 ms each   (38/40 routable)
verifying an 11-point path is all water  0.02 ms
```

**Yes, in Node.** A search is tens of milliseconds, and *verifying* a path is water costs
essentially nothing — which matters, because that verification is how the never-touch-land law is
enforced rather than hoped for.

**The number that decides it is PGlite**, the runtime that actually ships — the world is applied and
queried inside the player's browser tab. `scripts/proto/pglite-astar.sql` implements A* in plpgsql
and `bench-pglite.mjs` measures it. **That measurement was still running when this was written and
must be filled in before anything is built.** If plpgsql A* is too slow, the fallbacks in order of
preference are: a coarser first pass refined locally; the search in the client with the server
verifying the result; or a precomputed distance field. **None of them may turn the answer back into
a fixed graph of routes.**

---

## 4. WHAT IT REPLACES — and this is the constraint that matters most

It **REPLACES** `voyage.reach_from`, `voyage.sail_refusal`, `voyage.route_direct` and `voyage.route`.
It does **not** join them.

The predecessor's recorded catastrophe was **four overlapping movement paths**: four ships stuck at
`traveling` with nothing behind them, five teleported to the wrong ports, a global cron wedge, a
player's fleet destroyed because the brake refused, and *"is this fleet docked?"* reaching **eleven**
hand-copied definitions. Adding free movement beside the leg graph would recreate that exactly.

**One mover.** `data/sea-routes.json` and `scripts/build-sea-routes.mjs` are deleted; the raster
becomes the one source of what water connects to what.

---

## 5. WHAT MUST SURVIVE

**Offline settlement stays byte-identical.** `voyages.speed_profile` is frozen at departure and
proof 01 rests on it — it is why a voyage settles while the player is asleep. Wind that varies along
a passage *appears* to break this and must not: **wind must be a pure function of (position, time,
world secret)** — the shape `voyage.rng` already has, `immutable`, so Postgres itself forbids it
reading the clock. Integrate a known field over a known path and any two evaluations agree to the
digit. Losing this means the game only advances while someone is watching.

**Consequence:** if wind moves speed, the ETA quoted at departure is a **forecast, not a promise**.
`docs/UI_DIRECTION.md` forbids printing a number the game will not honour, so the player must be told
which it is.

---

## 6. ORDER OF WORK

1. **Finish the PGlite measurement.** Everything below depends on it.
2. **The pathfinder as the one mover** — replacing the four route authorities, with the water-path
   guard as its acceptance test (walk every path at sub-cell intervals, assert every sample is water,
   proven able to catch a straight line across Iberia).
3. **The chart follows the served path** — `src/chart/route.ts` draws straight lines *deliberately*,
   to agree with the server's straight-line interpolation. Both change together or the ship is drawn
   off its own track.
4. **Pinpoint anywhere** — the map's tap becomes a destination.
5. **Wind and current**, pure, with the ETA honestly labelled.
6. **Encounters** — the contacts panel with distances. `0035` already made *what befalls a fleet at
   sea* a table with a foreign key, so the disasters are largely authoring, not machinery.

**Sea places and diverting (0036, 0037) already landed** and compose the current model. `cmd.divert`
turns at the far node of the leg she is on; under free movement it becomes a supersede that turns
where she stands. That is a normal supersede, not rework.
