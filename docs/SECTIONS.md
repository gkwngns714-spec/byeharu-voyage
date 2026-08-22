# Sections — one part of the game, one place it lives

> The owner, 2026-08-20: *"organize them separately and independently so that individual have its
> own separate section … to have no spaghetti of whatsoever."*

This file answers one question and refuses to answer any other: **where does this belong?**

It is not a wish. `tests/sections.spec.ts` reads the import graph off disk and fails when a boundary
is crossed, and it was proved to bite by breaking it on purpose before it was trusted.

> **The other half of the law is [`docs/NO_SPAGHETTI.md`](NO_SPAGHETTI.md).** This file says where
> a thing goes; that one says **how many of it there may be** — one authority per concept, how to
> tell a second CALLER from a second AUTHOR, superseding a deployed migration instead of re-cutting
> it, the self-assert discipline, delete-don't-adapt, when a number may live in a test, and a
> ten-question checklist to run before finishing any change. Its teeth are
> `tests/duplication.spec.ts`.
>
> A boundary alone is not enough, and the two files exist together for a measured reason: forbidding
> a sideways import does not remove the need to share — it converts it into a **silent copy**, which
> no import-graph check can see. `PortPicker` is written twice today for exactly that reason
> (`NO_SPAGHETTI.md` §2). When a boundary bites, **promote the thing**; never copy it.

---

## The rule

**A section owns one concept. Sections may be used; they may not be reached into. Nothing reaches
sideways.**

> **And the trap that rule sets, discovered 2026-08-22.** A boundary that forbids borrowing does not
> stop sharing — it converts sharing into a SILENT COPY, and `tests/sections.spec.ts` stays green
> because a copy imports nothing. It really happened: MARKET could not import COMMAND's `PortPicker`
> so it wrote its own, and `fold()` was private to `ArgPickers` so MARKET matched with a bare
> `toLowerCase()` and quietly stopped finding `São Vicente` under `sao`.
>
> **So the boundary is only half the law.** The other half is `docs/NO_SPAGHETTI.md` and
> `tests/duplication.spec.ts`, which look for the copy the import graph cannot see. When you are
> forbidden to reach sideways, the answer is to MOVE the thing down a layer — never to retype it.

## One store, one way to read it

`useWorld()` with no selector is **banned**. It subscribes to the whole store object, which zustand
replaces on every `set()` — and `refresh()` sets twice, so a single read re-rendered every bare
subscriber twice no matter what actually moved. Reading is how time passes in this game, so that is
not an edge case, it is the main loop. Select primitives: `useWorld((s) => s.fleets)`. The rule and
its stable-return caveat are written at the head of `src/live/worldStore.ts`.

That is all of it. Everything below is where the line currently falls.

---

## The client — the layers, dependencies point one way only

```
src/domain/*      a part of the GAME.  Pure. No React, no store, no screen.
src/chart         HOW THE WORLD IS DRAWN. May use lib, domain, components/ui. One entrance.
src/features/*    a SCREEN.            May use any domain, chart, lib, component. NEVER another screen.
src/lib/*         MACHINERY.           rpc, db, format, geo, text. Knows nothing above it.
src/live/*        the world in memory. The store, and the gate that renders its loading/failure.
src/components/ui the design system.   One import surface, already a section in everything but name.
```

### The sections that exist

| section | owns | entrance |
|---|---|---|
| `domain/order` | the order language: the draft being composed, the composer that turns picks into the exact line `cmd.issue()` receives, and the hand-off another section can post into it | `domain/order/index.ts` |
| `domain/fleet` | what a hull, a crew and a hold add up to — free hold, crew against berths, worst hull, stores, cargo lines, draught, voyage progress | `domain/fleet/index.ts` |
| `domain/trade` | where a good is worth more than it is here — the index over `world.trade_routes()` | `domain/trade/index.ts` |
| **`chart`** | **the picture of the world**: the read model, the projection and the density rules, the SVG layers, the paint order, the pan/zoom surface, and the two things a screen mounts — `ChartCanvas` (a picture at a given view) and `SmallChart` (a whole framed one) | `chart/index.ts` |

The `domain/*` ones are pure and derive from served payloads. **Neither they nor the chart decide
anything** — the server owns every rule; these only read what a payload already says.

### `src/chart` — why the chart is a layer and not the Map tab's folder

Added **2026-08-23**, and it is the worked example of the trap named at the top of this file, so it
is written out as a case rather than left as a row in a table.

Every file in it was `src/features/map/`, which made the chart the Map tab's property. Then the
owner asked for a small chart on the SAIL composer — *"sail — a small map + current location on the
left side"* — and `tests/sections.spec.ts` correctly refused COMMAND an import of MAP. **That
refusal is the boundary working, and it is also the boundary's trap.** The smallest workable
carve-out measured at nine of the fourteen files (`src/features/command/README.md` §11 counted
them), so "copy what SAIL needs" meant copying most of the chart — a silent copy, invisible to
every import check in the repo, and the worst outcome available.

The two homes that already existed were both tried on paper and both fail on a rule this repo
already enforces:

* **Model to `src/domain/chart/`, layers to `src/components/chart/`.** *"Machinery knows nothing
  above it"* forbids `src/components/**` importing `src/domain/**`, and every layer needs
  `ChartModel` / `MapPort` / `PortRole`. Rewriting each layer to take plain `{x, y, role}` props to
  get past that is an adapter written to survive a boundary — the exact tell `NO_SPAGHETTI.md` §2
  gives for a boundary in the wrong place.
* **Leave it in `features/map` and let COMMAND import it.** That is the cross-screen import the
  first rule in the spec exists to refuse, and weakening the rule for one case retires it for every
  other. `NO_SPAGHETTI.md` §6: never weaken to green.

So the chart moved DOWN a layer instead. Its edges are two new tests, both broken on purpose and
watched go red before they were trusted:

| test | refuses |
|---|---|
| `the chart knows nothing above it` | `src/chart/**` importing `features/`, `app/`, `live/` or `store/`. `live/` is the sharp one: a chart that read the store could only ever be drawn on the tab the store happens to be about. What it needs from up there is a **parameter** |
| `the chart has one entrance` | anything importing `chart/<File>` instead of `chart`. The SVG layers, the label planner and the coastline builder are exported to **nobody** — `ChartCanvas` is the only thing that composes them, which is what makes the paint order a rule rather than a habit |

`ABOVE_DOMAIN` and `ABOVE_MACHINERY` both gained `chart` in the same pass, so a game rule or a
design-system primitive that reaches for a picture is refused too.

**What did NOT move: the Map tab.** `MapScreen`, its two corner panels and its caption are one
screen's chrome and they stay in `src/features/map/`, composing the section like any other caller.
MapScreen's composition is unchanged; only its import paths are — plus the seven lines of SVG paint
order, which became `ChartCanvas` so that the second caller composes it instead of restating it.
Two paint orders can disagree, which is question 3 of `NO_SPAGHETTI.md` §1.

**One property the carve-out exposed, and kept.** `src/chart/coastline.ts` imports
`…/world-110m.json?url`, which only a bundler can resolve, so re-exporting it from the entrance made
the whole section unloadable by a plain Node process — and this repo's pure specs are plain Node
processes (`coastlineBuild.ts`'s decimation figures are *measured* by one of them). Found by the
specs going red, not by argument. `useCoastline` therefore reaches that module with a dynamic
`import()` inside its effect and `loadCoastline` is deliberately absent from the entrance: one small
chunk ahead of a 280 KB fetch, in exchange for a section a spec can still import.

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

### What the spec checks, as of 2026-08-23

Every rule below was proved to bite by breaking it on purpose and watching it go red. A guard nobody
has seen fail is decoration.

| test | refuses |
|---|---|
| `no screen imports another screen` | one `features/<a>` file importing `features/<b>` |
| `a domain section depends on nothing above it` | a game rule importing a screen, the shell, the store, `live/`, the design system **or the chart** — a rule that needs a component or a picture to be proved cannot be proved without rendering one |
| `machinery knows nothing above it` | `src/lib/**` or `src/components/**` importing `domain/`, **`chart`**, `features/`, `app/`, `live/` or `store/`. What is needed up there is a parameter, not an import |
| `the design system has one entrance` | anything importing `components/ui/<File>` instead of `components/ui` — including from `src/chart`, which draws with the design system too. A primitive nobody can reach through the entrance is one the next screen hand-writes instead |
| `every domain section has one entrance` | a section with no `index.ts`, and reaching past one into a section's internals |
| `the chart knows nothing above it` | **NEW** — `src/chart/**` importing `features/`, `app/`, `live/` or `store/`. Read the case above for why `live/` is the sharp one |
| `the chart has one entrance` | **NEW** — anything importing `chart/<File>` instead of `chart`. The layers and the label planner are exported to nobody |

The three that were extended or added on 2026-08-23 were each shown failing first, with the file and
the crossing named in the message: `domain/fleet/derive.ts -> chart`,
`chart/glyphs.ts -> live/worldStore`, and `features/map/MapScreen.tsx -> chart/PortsLayer`.

**A known seam, named rather than enforced:** four `src/features/*` files import
`src/app/shellState` (`FleetsScreen`, `LedgerScreen`, `MapScreen`) and `src/app/navTabs`
(`AuthPage`) while `src/app` renders the screens — a folder-level cycle. That state is not the
shell's; it is app-wide UI state and it wants a section of its own. It is **not** a test, because a
guard that is red the day it is written gates nothing.

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
   and both import it from there. **Never copy it instead** — the boundary check cannot see a copy,
   only an import, which is why `docs/NO_SPAGHETTI.md` exists beside this file.
4. New shared LOOK or control → **`src/components/ui/`**, exported from `index.ts`. A recipe written
   in a screen is a recipe that will be written in the next screen too; that is how the chip reached
   twelve copies (`src/components/ui/buttonStyles.ts:31-35`).
5. New way of DRAWING THE WORLD → **`src/chart/`**, exported from its `index.ts`. A second `<svg>`
   that stacks the layers itself is a second paint order, and paint order is the only stacking SVG
   has. Compose `ChartCanvas`, or `SmallChart` if you want a whole framed chart in a box.
6. **A second screen wants a picture the first one has → the same rule as 3.** The chart is the
   proof that rule works at any size: it was nine of fourteen files, and it moved rather than
   being copied. If the move looks too big, that is a measure of how bad the copy would have been.

`npx playwright test tests/sections.spec.ts tests/duplication.spec.ts` is the check — the first for
where things live, the second for how many of them there are. Before finishing any change, run
`docs/NO_SPAGHETTI.md` §8.
