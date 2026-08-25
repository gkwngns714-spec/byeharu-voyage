# NAVIGATION — the plan, and what is measured

Written 2026-08-24 for the owner, who asked to see the plan before anything is built.

> *"do all the work in appropriate order, after research, build what you think it is best without
> ruining this game"*

**Status of this document:** BUILT, 2026-08-24 — landed as migrations **0046**
(`the_water_knows_the_way`) and **0047** (`the_sea_is_a_free_plane`) — corrected 2026-08-25: this
was originally cut in the `bv-mover` worktree as 0038/0039 against a 37-migration base, but generated migrations are
regenerated against the current chain rather than textually merged, so the files that actually
shipped on `main` are 0046 and 0047 (see `supabase/migrations/`; `docs/RESUME.md`'s "LANDED
2026-08-24" section spells this out). Other 0038/0039 references below name the slice as it was
planned, not the file that landed. With the client in `src/lib/sea` + `src/domain/passage` and the
chart drawing the served course whole. `docs/DEV_LOG.md` D22 records what landed and what it
measured; proof 09 (renumbered here: 08 is the sea-membership proof) holds the never-touch-land law and the Arctic door shut on every run. The
prototype in `scripts/proto/` was CONSUMED by the build (the pathfinder moved into
`src/lib/sea/pathfind.ts`, the plpgsql A* was rejected by its own measurements) and is deleted;
the measurements below are its record. The reference-game research
(`DESIGN_RESEARCH_NAVIGATION.md`) was **not finished** — the agent writing it hit the session
limit. That gap is stated rather than papered over; the owner supplied the design directly, which
is what the built system rests on. Wind (§6 step 5) and encounters (§6 step 6) are deliberately
NOT in the built slice; the wind seam (per-segment frozen speeds) is.

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

### And in PGlite — measured 2026-08-24, and it settles the design

```
route                  |      ms |  expanded |   nm
-----------------------+---------+-----------+------
Lisboa -> Cadiz        |     330 |        74 |  286
Lisboa -> Amsterdam    |   3 549 |       957 | 1122
Lisboa -> Salvador     |  42 619 |     11150 | 3731
Amsterdam -> Venice    |  67 729 |     17775 | 3246
Lisboa -> Calicut      | 302 438 |     85268 | 9802
```

**A\* written in plpgsql is about 1,800x slower than the same algorithm in JavaScript.** Five
minutes to issue one order is not a tuning problem, and no constant factor rescues it: the search
expands 85,000 cells and plpgsql pays interpreter cost on every one. Raster load and storage are
fine (163 ms, and 1 MiB of raster TOASTs to 27 KiB) — **the loop is the problem, not the data.**

**So the pathfinding does not run in SQL.**

### THE ANSWER: the client proposes, the server verifies

The asymmetry the prototype measured is the whole design:

| | cost |
|---|---|
| FINDING a path (JS) | 47-166 ms |
| VERIFYING a path is all water | **0.02 ms** |

Finding is expensive; checking is free. So the client — which is JavaScript, and fast — proposes a
water path, and the **server verifies it and measures it**. Verification is the authoritative act.

**This does not weaken server authority, and it is worth being precise about why.** The server
independently (a) samples every segment against its own raster and refuses anything touching land,
and (b) computes the distance itself from the polyline. A client cannot gain by lying:
- a path crossing land is **refused**;
- a longer path only **costs the player** more days and more stores;
- a *shorter* water-valid path is not a cheat — it is a better route, and legal water is legal water.

The one thing the server must never do is take the client's word for the DISTANCE. It measures.

**Rejected, and why:** a precomputed waypoint mesh is a fixed graph wearing a new name and the owner
has refused that three times. Edge Functions would put the search on a server but add a service and a
second runtime for one function. A coarse-then-refine pass in plpgsql still pays interpreter cost on
the refinement, and 330 ms for Lisboa-Cadiz — the SHORTEST case measured — is already too slow to
build on.

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
