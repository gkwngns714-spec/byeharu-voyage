# Sections — one part of the game, one place it lives

> The owner, 2026-08-20: *"organize them separately and independently so that individual have its
> own separate section … to have no spaghetti of whatsoever."*

This file answers one question and refuses to answer any other: **where does this belong?**

It is not a wish. `tests/sections.spec.ts` reads the import graph off disk and fails when a boundary
is crossed, and it was proved to bite by breaking it on purpose before it was trusted.

---

## The rule

**A section owns one concept. Sections may be used; they may not be reached into. Nothing reaches
sideways.**

That is all of it. Everything below is where the line currently falls.

---

## The client — three layers, dependencies point one way only

```
src/domain/*      a part of the GAME.  Pure. No React, no store, no screen.
src/features/*    a SCREEN.            May use any domain, lib, component. NEVER another screen.
src/lib/*         MACHINERY.           rpc, db, format, geo. Knows nothing above it.
src/live/*        the world in memory. The store, and the gate that renders its loading/failure.
src/components/ui the design system.   One import surface, already a section in everything but name.
```

### The sections that exist

| section | owns | entrance |
|---|---|---|
| `domain/order` | the order language: the draft being composed, the composer that turns picks into the exact line `cmd.issue()` receives, and the hand-off another section can post into it | `domain/order/index.ts` |
| `domain/fleet` | what a hull, a crew and a hold add up to — free hold, crew against berths, worst hull, stores, cargo lines, draught, voyage progress | `domain/fleet/index.ts` |

Both are pure and derive from served payloads. **Neither decides anything** — the server owns every
rule; these only read what a payload already says.

### What this fixed, measured

Nine imports had one screen reaching into another's internals:

```
port/PortScreen      -> command/commandDraft, command/orderText, fleets/worldGate, fleets/fleetDerive
fleets/FleetsScreen  -> command/commandDraft
market/handOff       -> command/commandDraft
ledger/LedgerScreen  -> fleets/worldGate
```

None of it was bad code. Every one was a screen borrowing something that was never the lender's:
*"how much hold is free"* is a property of a fleet, not of the tab that draws one. The clearest
tell was `market/handOff.ts`, written as an adapter whose stated reason to exist was that
*"commandDraft.ts is owned by the CMD tab"* — **an adapter that exists only to survive a boundary is
a sign the boundary is in the wrong place.** It still exists, as a named intent; it is no longer a
border crossing.

Cross-screen imports today: **zero**, and the spec keeps it that way.

---

## The server — sections by role, files by narrative

The chain already separates by **role**, and that separation is strong:

| schema | owns |
|---|---|
| `public` | the tables, and the helpers every schema shares (`wc_*`, `credit`, `emit_event`, `current_player_id`, the ticks) |
| `world` | **reads.** Everything a client may look at, settled before it answers |
| `cmd` | **writes.** The verbs, the parser, the queue — the only way the world changes |
| `voyage` | **time and motion.** Distance, routing, the closed-form position, settlement |

Migrations are named as a sentence and ordered as a story, so a **domain** can span two of them —
`ports` and `legs` land in 0002/0003 while their *prices* land in 0005. That is a real seam, and it
is worth being honest about rather than tidy about:

> **The chain is deployed.** Re-cutting 0001–0012 would desync `schema_migrations` on the live
> project and destroy every player's world to gain a filing improvement. **Existing migrations are
> not reorganised. New concepts get new files.**

### Who owns what today

| concept | tables | behaviour |
|---|---|---|
| location | `nations` `seas` `regions` `ports` `legs` (0002, 0003) | `voyage.gc_distance_nm`, `voyage.route` (0002, 0006) |
| trade goods | `goods` `port_specialties` (0002) | `world.affinity_at` / `affinity_for` (0005) |
| prices | `port_goods` `trade_daily` (0005) | `world.quote` `mid_price` `spread` `tax_rate` (0005) |
| ships | `ship_classes` (0002) · `ships` (0004) | derived client-side in `domain/fleet` |
| fleet | `fleets` (0004) | `cmd.advance`, the queue (0007) |
| captains | `players` (0004) | `public.new_house` (0004) · `cmd.found_house` (0011) |
| the record | `events` `ledger` (0004) | `public.credit`, `emit_event`, reconciliation (0004) |
| voyages | `voyages` `voyage_events` (0006) | `voyage.settle`, closed-form position (0006) |
| orders | `orders` (0007) | the verb grammar and parser (0007, 0008) |
| the clock | — | ticks (0010) · **schedule** (0012) |

**0010 and 0012 are the pattern to copy.** 0010 owns what a tick *does*; 0012 owns *when it runs*.
Two files, two questions, no overlap — and 0012 derives its cadence from `drift_slot_seconds` rather
than restating it, so "how often does the market step" has exactly one answer.

### Where the sections that do not exist yet will go

The owner named these; none are built. Each gets its **own migration** and, where it needs client
maths, its **own `src/domain/`** — never a column bolted onto `players` because that table was
nearest.

| section | lands as | must not |
|---|---|---|
| skills | its own migration: `skills`, `player_skills` | become columns on `players` |
| buffs | its own migration: a timed modifier table, applied where it is read | be summed into a stored total anywhere |
| captains / officers | its own migration, referencing `players` | extend `ships` or `fleets` with officer columns |
| stats | wherever the stat's subject lives — a hull stat on ships, a house stat derived | become a `stats` grab-bag table |

The last row is the one worth guarding. A `stats` table that anything may write is not a section; it
is the place sections go to tangle.

---

## Adding a section

1. New concept on the server → **a new migration**, named as a sentence, with a self-assert whose
   positive controls bite. Never edit a deployed one.
2. New shared maths on the client → **`src/domain/<name>/`** with an `index.ts` entrance.
3. A screen needs something another screen has → **it is not that screen's.** Move it into a section
   and both import it from there.

`npx playwright test sections.spec.ts` is the check.
