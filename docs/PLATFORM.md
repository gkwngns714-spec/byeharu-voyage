# PLATFORM — the foundation combat, exploration and NPCs will stand on

> The owner, 2026-08-23: *"this game might need OSN system as well as other system built in
> byeharu, the previous game. audit and implement it so that later on, combat, exploration, npcs
> can be added."*

This is architecture, not a feature. The ask is to make byeharu-voyage **able to grow** combat,
exploration and NPCs — not to build them. So this file answers four questions, and the fourth one
is the one that costs money:

1. Does voyage need OSN? — **No, and §1 is the evidence.**
2. What is the one spatial primitive? — **The leg. It already exists.** §2.
3. What seam does combat need that today does not expose? — **Three, named in §3.**
4. What is being built now, and what is deliberately NOT? — §5 and §6.

Everything below is cited. `dev/byeharu` paths are the predecessor project, read-only.

---

## 0. The sentence the predecessor wrote at the start, and then walked away from

`dev/byeharu/docs/ARCHITECTURE.md:24-30`, written before the first migration of that project:

> ***"Do not build free-moving ships that chase/fight from live positions — that path is bug-prone.
> Use discrete states: choose destination → validate → travel → arrive → present → activity →
> resolve."***
>
> ***"Most important rule: build the game around location presence, not directly around combat.
> Movement decides arrival; presence decides exposure; activity decides what happens; combat is
> only one activity; reports show the result."***

`docs/CORE_REUSE.md:1168` already records the verdict on what happened next:

> *"Byeharu spent 2026 walking away from that rule (OSN, free coordinate travel, spatial combat)
> and `byeharu-voyage` is walking back to it."*

**That is the whole audit in two quotations.** OSN is the name of the walking-away. Voyage's loop —
`Map → Port → Voyage → Arrival → Activity → Report` — is the rule itself. The foundation this file
lays is the **one link of that loop voyage does not have yet: ACTIVITY.**

---

## 1. Does voyage need OSN? No. And the honest reason is stronger than "no".

### What OSN actually was

Free-coordinate open-space navigation: a ship (later a fleet) sails to an arbitrary `(x, y)` in a
±10,000 square rather than to a named place. Position between departure and arrival is linear
interpolation over `(origin, target, depart_at, arrive_at)` —
`dev/byeharu/supabase/migrations/20260618000218_position_territory_leaves.sql:83-98`, one
`immutable strict` function, explicitly "the ONE movement-interpolation authority".

### The five findings, each of which alone would settle it

**1 — the per-ship coordinate stack was built, gated, never turned on, and then physically deleted.**
Migrations 0055–0070 built it. `20260618000231_movement_schema_drop.sql:245-250` refuses to run
unless both `mainship_space_movement_enabled` and `mainship_coordinate_travel_enabled` are FALSE —
and the drop ran, so both were. `20260618000232_movement_function_drop.sql` then drops **20
functions**; 0231 drops the table, three columns and six CHECK constraints. A whole subsystem was
authored, proved, deployed dark and demolished without a player ever using it. That is the single
most expensive fact in the predecessor repo, and copying the system is copying that.

**2 — free-coordinate travel is the state in which nothing can happen to you.** This is the finding
that inverts the owner's premise, so it is stated plainly. In byeharu **a fight is structurally
impossible without a `location_presence` row**: `combat_encounters.presence_id` is
`uuid not null references public.location_presence(id)`
(`dev/byeharu/supabase/migrations/20260616000014_combat_tables.sql:14`). And the space-arrival
branch of the settler creates **no presence at all** —
`20260618000208_fleetgo_coordinate_targets.sql:163-166`, whose own comment says *"open space has no
location"*. A fleet parked at a free coordinate is therefore a fleet that cannot be ambushed,
cannot hunt, cannot mine and cannot explore. **OSN does not enable combat, exploration and NPCs. It
is the one place they are unreachable.** Building it here to make room for them would achieve the
opposite of the request.

**3 — it produced four movement systems, and they cost real player state.**
`dev/byeharu/docs/MOVEMENT_UNIFICATION_CHARTER.md:488-500`: *"Movement is four overlapping paths
pretending to be one"* — legacy single-ship, OSN single-ship, group (which looped the legacy mover
per member), and a readiness rule that had diverged so Send and Hunt could launch from a dock and
Move could not. Measured consequences, all from that repo's own docs: four production ships stuck
at `status='traveling'` with nothing behind it; five ships teleported to wrong ports by a stale
corpse read; the ghost-dock bug where *"the fleet flew while its ships stayed docked, trading and
storing at the origin"*; a global cron wedge where one bad row stopped every player's arrivals; and
a player's four-ship fleet destroyed because the brake refused. The predicate *"is this fleet
docked?"* ended up **hand-copied eleven times, three of them inside one function body**
(`20260618000306_empty_fleet_dock_authority.sql:25-29`).

**4 — voyage cannot enforce a free coordinate, because it does not know where land is.** The 782
legs are A\* paths through a 0.25° water raster produced at BUILD time by `scripts/sea-grid.mjs`.
**Nothing at runtime holds that raster.** A free `(lat, lon)` order would sail straight through
Africa, and the only fix would be to put the raster in the database — replacing a graph the router
already traverses in 0.1 s with a grid search, to gain a feature the predecessor never shipped.

**5 — it contradicts two of the eight laws.** Law 3, `docs/DESIGN.md:16`: *"The map is an output
device. It renders position and heading. It never accepts input."* A free coordinate is by
definition an input taken from the map. And orders are **composed, never typed**
(`docs/DEV_LOG.md`, the `validate.ts` deletion) — there is no composer control that produces a
latitude.

### What voyage should take from OSN — and already has

OSN's §12 core rule (`dev/byeharu/docs/MAINSHIP_TRANSITION.md:492-501`) is **"ONE authoritative
spatial state"**: an entity resolves to exactly one state, through one shared resolver, and every
surface reads it. That rule is right, it is the good half of OSN, and **voyage already enforces it
more strongly than byeharu ever managed**:

| OSN §12 wanted | voyage has | where |
|---|---|---|
| one authoritative spatial state | `fleets.status` ⇔ exactly one `SAILING` voyage, enforced by a partial unique index **and** an invariant function | `supabase/migrations/20260818000006_a_voyage_is_a_pure_function_of_time.sql:83-85, 716-731` |
| one shared position resolver | `voyage.progress_nm` → `voyage.position`, closed-form, no stored position to corrupt | `…0006…sql:555, 599` |
| no per-second position job | there is none; the read *is* the catch-up | `world.fleets()`, `20260818000028…sql:204-208` |

Voyage's position model is **strictly better than OSN's**: byeharu interpolated one straight
segment at one speed; voyage evaluates a multi-leg path with a per-leg speed profile frozen at
departure, minus accumulated delay, and it is recomputable at any `t` for ever. Importing OSN would
mean replacing the better thing with the thing it improved on.

### The verdict

> **Voyage does not need OSN. The good half — one authoritative spatial state, closed-form position
> — is already here and is better. The other half is a system that was built, gated, never lit and
> deleted, that cost the predecessor four movement paths and a player's fleet, that voyage cannot
> enforce without shipping a coastline raster to the server, and that in the predecessor's own
> schema is the one state in which no encounter can be created.**

This is a refusal, and it is recorded as one in `docs/OWNER_REQUESTS.md` #40 so it can be
overruled. If the owner wants free-coordinate sailing as *gameplay* — "sail to a position between
ports" — that is a different and legitimate request, and §6 says what it would actually cost.

---

## 2. The one spatial primitive is the LEG

Two spatial primitives is the spaghetti this project has torn out repeatedly, so this is stated
once and enforced.

Voyage has four spatial nouns today and they are **not** four primitives; they are one graph and a
picture of it:

| noun | what it is | who decides anything with it |
|---|---|---|
| **`ports`** | the graph's NODES. `lat`/`lon`, `sea_id`, `region_id` | every rule about being *somewhere* |
| **`legs`** | the graph's EDGES. `distance_nm`, `hazard_mult`, unique unordered pair | every rule about being *between* somewhere |
| **`seas`** | an attribute of a leg's far port: `hazard_base`, `piracy_index` | the hazard probability |
| **lat/lon on a voyage** | **display only** | *nothing* — and it says so |

That last row is a fence and it holds. `voyage.position`'s own comment,
`…0006…sql:627-629`:

> *"The MAP is an output device (DESIGN E.5 / law 3): this is display geometry, linear along the
> leg. It is not used by any rule; distance is always the authored leg distance."*

**So: the LEG is voyage's spatial primitive for anything that happens at sea, and the PORT is the
primitive for anything that happens ashore.** A leg is already exactly what a byeharu `danger_zone`
was — *a continuous exposure surface with its own risk multiplier, bounded by two places* — except
that it needs no polygon, no PostGIS, no overlap policy and no hit test, because a voyage's path
is a list of legs by construction.

### Zones are REJECTED, and the predecessor's own reviewer said why

`dev/byeharu/docs/ZONE_PLATFORM_REVIEW.md:262-275` records the argument against the zone platform,
written by its own reviewer:

> *"Forcing every spatial mechanic into polygons can introduce arbitrary radii, complex overlap
> policy, more expensive queries, and an increasingly central dispatcher that becomes a new god
> module… The owner's approach is justified only if area membership is genuinely intended to become
> part of mining and exploration gameplay, rather than merely a desire for schema uniformity."*

Voyage never needs area membership: a fleet is on a leg or in a port, and `voyage.leg_at_day(v, d)`
already answers which. Adding polygons here would be schema uniformity with no game behind it —
and a second answer to "where is this fleet", which is the disease.

**The rule, for whoever adds the next thing:** if a new mechanic needs a place, it hangs off a
`port` or a `leg`. If neither fits, that is a design conversation, not a new table.

---

## 3. The three seams that actually matter

Voyage's core loop is `Map → Port → Voyage → Arrival → Activity → Report`. Four of those five links
are built and good. **ACTIVITY is missing**, and combat, exploration and NPCs are all activities.

Here is what happens today when a fleet is raided, in full — this is voyage's entire combat system:

1. `voyage.hazard_roll` (`…0006…sql:666-714`) draws three numbers from
   `voyage.rng(voyage, day, stream)` and picks a kind from a **hard-coded CASE**:
   `when r_kind < 0.40 then 'STORM' when r_kind < 0.75 then 'CALM' else 'PIRATES'`.
2. `voyage.settle` (`…0007…sql:887`, re-cut at `…0027…sql:238`) runs a **hard-coded if/elsif arm**
   per kind. The PIRATES arm computes the raider out of thin air —
   `piracy_index × 40 × (0.5 + magnitude)` — compares it to an escort score, and mutates crew,
   durability and cargo.
3. `voyage.report_line` (`…0027…sql:196`) turns it into prose from a **hard-coded CASE**, with
   `else format('Day %s. %s', p_day, p_kind)` as the fallback for anything it does not know.

### SEAM 1 — *what can happen at sea* is stated in three functions, so it is not data

This is the load-bearing one. Adding a `DERELICT`, a `LANDFALL`, a `CONVOY` or a named corsair band
today means editing `hazard_roll`, `settle` **and** `report_line` — and forgetting the third one
does not fail: it silently prints the raw code `Day 7. DERELICT` at the player.

`docs/NO_SPAGHETTI.md` §1 question 2 — *"would a rule change have to be made here too?"* — answers
yes in three places. The predecessor learned this and got it right on the second attempt: in
byeharu's combat-content program *"adding a new enemy type today is an INSERT through an RPC, not a
migration"* (`docs/COMBAT_CONTENT_PROGRAM.md`), and the zone→city link is *"a row, not a code
edit"* (`20260618000338…sql:20-39`). The `game-development-method` rule states it as law: **a new
enemy must be rows, not code; if adding content requires editing a function, the design is wrong.**

**This seam is what migration 0035 builds.** See §5.

### SEAM 2 — an event has no SUBJECT, so an encounter has no actor

A raid today happens *with the sea*. `v_raider` is a number derived from `seas.piracy_index`;
nothing persists, nothing is named, nothing can be met twice. An "encounter with an actor" needs
the raider to be a **row** — a band with a strength, home waters, and a standing you build against
it. That is also exactly what an NPC is, and what an exploration find is (a site is a subject you
meet once).

**Deliberately not built.** A `subject_id` column with no table to point at is the recorded failure
class — byeharu shipped `enemy_archetypes.stat_overrides` (*"a DEAD authored field… read by nothing
at spawn"*) and `encounter_runtime_state.active_count` (*"dead weight as a runtime authority —
nothing reads it"*). §6 states the exact shape so whoever builds the first actor does not have to
re-derive it.

### SEAM 3 — a voyage-day can hold exactly ONE event, and only a voyage can hold events

`public.voyage_events` is keyed `primary key (voyage_id, day_index)` (`…0006…sql:89-98`). Two
consequences:

* **One thing per day.** An encounter that develops over days (sighted → closed → boarded), or a
  storm on the same day as a sail sighting, cannot be represented.
* **Nothing can happen ashore.** Every event needs a `voyage_id`. A rumour heard in port, a visitor
  at the quay, a discovery made while docked — none has a row to live in.

**Deliberately not built.** The PK is what makes `settle` idempotent
(`on conflict (voyage_id, day_index) do nothing`, `…0007…sql:1023`), which is what makes offline
settlement byte-identical to tick-by-tick settlement — the property the whole design rests on. It
can be widened safely, but only by a slice that re-cuts `settle` and re-proves determinism, and
that slice should be the one that first needs it. §6 has the shape.

---

## 4. What each future system will need, item by item

Read this as a shopping list against the foundation, not as a plan to build them.

### Combat (an encounter with an actor)

| needs | status |
|---|---|
| a place to be exposed | **have** — the leg (§2), via `voyage.leg_at_day` |
| a deterministic roll not keyed on the wall clock | **have** — `voyage.rng(voyage, day, stream)`, `immutable`, so Postgres itself forbids it reading the clock |
| the set of things that can happen to be data | **0035 builds it** |
| an actor with an identity | seam 2 — not built |
| more than one beat per day | seam 3 — not built |
| an outcome that mutates ships | **have** — `settle`'s PIRATES arm already does exactly this |
| after-action prose | **have**, and 0035 makes it extend without a code edit |

**Note what combat does NOT need here: positions, ranges, ticks, or a fight scene.** Law 4 —
*"No visual combat, ever"* — and byeharu's spatial-combat engine is the thing the owner pivoted
away from. Combat in this game is a better raid table with a named opponent.

### Exploration

| needs | status |
|---|---|
| a thing to discover, that is a row | seam 2 |
| that row to be **invisible before discovery** | not built. byeharu's answer is exactly right and transplants: RLS enabled with **no policy and no grant at all**, so the client cannot see the table (`20260618000098…sql:5-10`), plus *"a dark feature answers identically regardless of input, so no hidden-site existence can be probed"* |
| a per-(player, thing) once-only fact | not built — a `unique (player_id, site_id)` table, byeharu's `exploration_discoveries` |
| a place for it to be | **have** — a leg, or a port |
| a way to attempt it | a verb. See below |

### NPCs

An NPC is seam 2 plus persistence between meetings. The minimum first NPC is: a row with a name and
a strength, a home sea, and a `player_standing` row per house. Nothing else. It does **not** need a
position, a schedule or an AI.

### And the one thing all three share: a VERB

`cmd.execute_order` (`…0007…sql:781-789`) dispatches on a hard-coded `case o.verb`, and
`cmd.verb_schema` (`…0021…sql:249`) is a hard-coded JSONB literal. Adding `EXPLORE` means editing
both. **This is seam 1's twin on the order side**, and it is deliberately left alone: the six verbs
are a closed, designed vocabulary today, the grammar is already served from one place to one
composer, and a verb registry with six rows and no seventh caller would be machinery ahead of a
need. When the seventh verb is real, it converts the same way 0035 converts the hazard table — and
0035 is the worked example of how.

---

## 5. What migration 0035 builds — and why it is enough

**One table, two superseded functions, no new concepts on screen.**

`public.voyage_event_kinds` — **the catalogue of things that can befall a fleet at sea.**

* **The concept, in one noun phrase** (NO_SPAGHETTI §7B q1): *a kind of thing that can happen to a
  fleet on a voyage-day.*
* **Where it lives and why** (q2): `public`, beside the tables, because it is world reference data
  like `seas` and `goods` — not in `voyage`, which owns *time and motion*, and not in `cmd`, which
  owns writes.
* **Who the second caller is** (q3): `voyage.hazard_roll` reads the weights, `voyage.report_line`
  reads the prose, and `public.voyage_events.kind` is a **foreign key into it**. Three callers on
  day one, which is why it is a table and not three literals.
* **What would make it the wrong shape, and how anyone finds out** (q4): if the weights ever have
  to differ per sea, this table is too flat — and the tell is somebody writing a second weight
  anywhere. Named in §6 with its shape.

The three things it changes, each with a structural guarantee rather than a comment:

1. **`voyage_events.kind` gains a foreign key** into the catalogue. A kind that nobody named can no
   longer be written — the byeharu lesson that *"the cures that actually worked were structural,
   not disciplinary: make the duplicate impossible"*.
2. **`voyage.hazard_roll` composes the weights** instead of the CASE. Proven byte-identical to the
   old CASE over a large deterministic sample, including a sample where the piracy shift actually
   fires — a no-op proof, because prose saying "this changes nothing" is not evidence
   (NO_SPAGHETTI §3.3).
3. **`voyage.report_line` composes the prose** instead of the CASE. This is what closes the seam:
   without it the set of kinds would still be stated in two places, and a new kind would print a
   raw code at the player. The `else format('Day %s. %s', p_day, p_kind)` fallback — a code shown
   to a player — is **deleted**, and an unknown kind now raises instead (NO_SPAGHETTI §7C: if the
   `else` branch is unacceptable, it is not a branch).

`voyage.settle` is **not touched.** Its arms are genuinely different code — a storm subtracts
durability, a calm adds hours — and one arm per kind is composition, not duplication. The FK means
`settle` can never write a kind the catalogue does not know, which is all the coupling that is
needed.

### After 0035, adding a thing that happens at sea is:

```
insert into public.voyage_event_kinds (...)   -- one row: weights, prose, note
+ one arm in a superseding voyage.settle       -- only if it does something new to the ships
```

instead of three functions and a silent way to get it wrong. **That is the foundation.** It is
small on purpose: a small migration whose value is that the next four are also small.

---

## 6. Deliberately NOT built — the shapes, so nobody re-derives them

Each of these is a real gap. Each is stated with the shape it should take, so the slice that needs
it starts from a decision rather than a blank page. **None of them should be built before something
needs it** — byeharu's ledger of deployed-with-zero-callers is four items long and each one cost a
migration to remove.

| not built | the shape when it is needed | why not now |
|---|---|---|
| **an actor / subject on an event** | `voyage_events.subject_kind text` + `subject_id uuid`, both null today, plus the first actor table (`raider_bands`: name, home `sea_id`, strength, `is_active`). Until then a subject rides in the existing `payload` jsonb, which already carries `outcome`/`escort`/`raider`. | a column with no reader is byeharu's recorded failure class — `stat_overrides`, `active_count`, `fleet_combat_stats`, all authored and read by nothing |
| **more than one event per voyage-day** | PK becomes `(voyage_id, day_index, seq)` with `seq` a **deterministic** ordinal (event *k* of day *d*), so `on conflict do nothing` stays exactly as idempotent. Requires re-cutting `voyage.settle` and re-proving offline equivalence in the same slice. | the PK is what makes the whole offline model byte-identical; widening it belongs to the slice that first needs a second beat, so the determinism proof is written against a real case |
| **events ashore** (a rumour, a visitor, a discovery in port) | not `voyage_events` — that table is correctly about a passage. A sibling keyed on `(player_id, port_id, game_day)`, sharing this same catalogue via the same FK. | no caller. The catalogue is deliberately named `voyage_event_kinds` and not something grander, so this decision stays open |
| **per-sea event weights** | `voyage_event_kind_seas (kind_code, sea_id, weight)`, overriding the flat weight where a row exists. The leg and sea already carry `hazard_base`, `piracy_index` and `hazard_mult`, so the spatial dimension exists — only the per-kind mix is flat. | one flat mix plus `piracy_index` reproduces today exactly; a second weight table with one row would be machinery ahead of content |
| **a verb registry** | the same conversion 0035 does, applied to `cmd.verb_schema`'s literal and `cmd.execute_order`'s CASE. | six verbs, no seventh. §4's last paragraph |
| **zones / polygons** | — | rejected in §2, with the predecessor's own reviewer quoted against them |
| **free-coordinate sailing** | if ever wanted as *gameplay*: it needs the water raster at runtime (or a legality oracle), a synthetic leg carrying a `sea_id` so the hazard system still fires, and an answer to Law 3. It is a design decision, not an import. | rejected in §1 |
| **`world.reachable(fleet)`** | already named in `docs/OWNER_REQUESTS.md` — a served read composing `voyage.reach_from`, so reachability is not 214 round trips or a client copy | unchanged by this work; listed so it is not thought to be solved |

---

## 7. The one-line version

**Voyage does not need OSN — it already has the only part of OSN that was ever right, and the rest
is the system byeharu built, never lit, and deleted. What voyage is missing is the ACTIVITY link of
its own loop, and the first brick of that is making *what can happen out there* a table instead of
a CASE in three functions.**
