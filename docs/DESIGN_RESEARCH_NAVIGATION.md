# DESIGN_RESEARCH_NAVIGATION.md — how the reference games actually move a ship

Research date: **2026-08-24**. Researcher: Claude (Opus 5), worktree `bv-mover`.
Companion to `docs/DESIGN_RESEARCH.md`, which this file corrects on one point and extends on eight.

> **Why this file exists.** The owner, three times, with rising frustration:
> *"First it is a fleet game, moving by seas, and you've decided to make routes (constant) — a fixed
> method of reaching to the place. it should go by sea without the fixed route — but fastest way
> possible. Also, in map, i should be able to pinpoint anywhere in the ocean to make a fleet move."*
> and then *"everything in this game tells me that you did not / failed to do a proper research."*
>
> They are right, and the evidence is in our own file. `docs/DESIGN_RESEARCH.md` §1.11 records of the
> reference game: *"navigation is **manual** or automatic by picking the destination harbour on the
> mini-map"* — **manual listed first** — and §3.2 D7 then dropped manual navigation outright, citing a
> constraint ("the map cannot accept a command") that the owner has now reversed. One half of the
> reference game's movement model was read, written down, and thrown away; the fixed leg graph — 782
> legs when the owner wrote that, 829 today — became the whole model; and every route defect in
> `docs/OWNER_REQUESTS.md` rows 41–42 is that one decision showing through.

## 0. Source quality legend — same convention as `docs/DESIGN_RESEARCH.md`

| Marker | Meaning |
|---|---|
| **[P]** | **Primary.** Publisher/developer page, official guide, in-game manual, patch note, dev interview — retrieved and read. |
| **[S]** | **Secondary.** Wiki, established guide site, detailed player guide, review. Strong but not the publisher's word. |
| **[U]** | **Unverified.** Could not be confirmed. Stated as a gap, never as fact. |

**Where a question could not be answered from a source, this file says `[U]` and says so.** The
owner's complaint is about research quality; a confident fabrication would be worse than an honest
gap.

---

## PART ONE — HOW THE REFERENCE GAMES MOVE A SHIP

### 1. Is the sea a free plane, a grid, or a graph of routes?

**It is a free surface you steer across, and picking a destination is the *alternative* to steering,
not the only way.** [P]

> *"Either manually navigate to the harbor or select [Mini Map] → [Harbor] from the top-right corner
> to travel automatically."*
> — [Voyage: How to Set Sail](https://uwo.floor.line.games/us/bbsCmn/detail/1653443788526014645), LINE Games' own guide **[P]**

This is the same page `docs/DESIGN_RESEARCH.md` §1.11 already cited, and its §1.11 summary —
*"navigation is manual or automatic"* — was accurate. **The mistake was not in the research. It was
in §3.2 D7, which dropped the manual half and kept only the automatic one**, and then let the
automatic half's data structure (a graph between harbours) become the entire world model.

Corroborating that the surface is continuous rather than a set of links, from the same guide family:

> *"Upon finding a suspicious area while sailing, select the ship to execute a search."*
> — [Voyage: Search and Exploration](https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1653444258130018779) **[P]**
> *"Approach a landing location while sailing"* to begin an exploration ashore. **[P]**

You *find* things by being near them and you *approach* places that are not harbours. Neither
sentence is expressible on a port-to-port graph — there is no "near" between two nodes, and nothing
to approach that is not an endpoint.

**Not verified:** whether the sea is internally a continuous plane or a fine grid, and at what scale.
The publisher does not say and I could not find a source that does. **[U]**

### 2. What does auto-sail actually do?

**It carries the fleet to a HARBOUR chosen on the mini-map, and it keeps going when the player
leaves.** [P]

> *"In Uncharted Waters Origin, you sail to your destination even if you go offline during Auto
> Sail. Should you run into extreme situations such as disasters or enemy attacks during offline
> sailing, actions will be taken according to your [Aide] settings."*
> — [Fleet Basics: The Company](https://guide.floor.line.games/UWO/en_US/detail/1111111111111111115) **[P]**

> *"Combats still occur during offline-sailing."*
> — [Growing Your Fleet](https://guide.floor.line.games/UWO/en_US/detail/1167031329446900354) **[P]**

**This closes a gap our own file recorded as unclosable.** `docs/DESIGN_RESEARCH.md` §4 item 3 lists
*"whether voyages progress while offline"* as **[U]**, *"Not published on any page I could reach."*
It is published, on two pages, and the answer is yes.

**And the shape of the answer is the more valuable half.** Origin does not pause the danger while you
are away and it does not decide for you: **the player pre-declares a policy (the Aide) and the server
resolves the encounter against it.** That is precisely byeharu-voyage's model — a standing order, a
server-side roll, an after-action report — arrived at independently and now confirmed against the
reference game. It is the strongest validation in this whole document of something we already have.

**Not verified:** whether auto-sail pathfinds around land or follows authored lanes; whether an
arbitrary open-water point can be an auto-sail destination. The guide documents only *"[Mini Map] →
[Harbor]"*. **[U]** The honest reading of the two halves together is that **steering is how you go
anywhere and auto-sail is the convenience for going to a harbour** — but that is my inference, and it
is labelled as one.

### 3. How is the coast handled? Aground, shallows, draft?

**Nothing in the official guide describes running aground, shallow water, or ship draft. [U]**

I looked specifically and found none of it. `unchartedwaters.fandom.com` refuses this environment
with HTTP 402, as it did for the previous research, so a wiki answer is not available either.

**But the guide answers a better question than the one I asked**, and this is the single most
directly transplantable idea in the document:

> **Momentum** — *"The ability of a ship to move through obstacles such as seaweed. **Some waters
> require high Momentum stats.**"* **[P]**
> **Ice Breaking** — *"The ability of a ship to break through ice. **Some waters require high Ice
> Breaking stats.**"* **[P]**

**Origin does not model collision with the coast. It models WATER THAT REQUIRES A SHIP CAPABILITY TO
ENTER.** Passability is not a property of the sea alone; it is a property of *(this water, this
ship)*.

That is exactly the shape byeharu-voyage needs, and it dissolves two of our problems at once:

- **Draft.** Today `voyage.sail_refusal` refuses a hull that is too deep **for a destination port**
  (`…0019…sql:441`). Under Origin's shape, draft is a **water requirement** — a shallow cell demands
  a shallow hull — and a port simply inherits the requirement of the water it sits in. One rule, and
  it works for a strait as well as a harbour.
- **Ice.** §P.10's residual gap stops needing a special case. Ice is a water requirement like any
  other; a hull with the capability passes, and in 1550 no hull has it.

Mechanically this means the raster's cell is not a bit but a small record — *is there water, how deep,
what does it demand* — and the pathfinder takes the fleet's capabilities as an argument. **The cost of
that is one extra byte per cell and a comparison in the inner loop.** It is the cheapest large idea
found in this research.

### 4. Wind and current, and how they meet a chosen course — the crux

**Origin resolves wind against the ship's heading, in at least four named relations.** [P] Verbatim,
from [Ship Details](https://guide.floor.line.games/UWO/en_US/detail/1167031287203500028):

> **Vertical Sail** — *"Equipping a sail with a high Vertical Sail stat increases the ship's speed
> during **Cross Tailwinds or Cross Headwinds** while sailing, and improves the ship's speed during
> combat."* **[P]**
>
> **Horizontal Sail** — *"Equipping a sail with a high Horizontal Sail stat increases the ship's speed
> during **Tailwinds or Cross Tailwinds** while sailing, and improves the ship's speed during
> combat."* **[P]**

Read those two together and the model falls out. There are at least four points of sail — **Tailwind,
Cross Tailwind, Cross Headwind, and (by elimination) Headwind** — and the two sail stats overlap on
Cross Tailwind and diverge everywhere else. A square rig (Horizontal) runs before the wind; a lateen
rig (Vertical) works across it and into it. This is real square-versus-fore-and-aft rig behaviour,
and it is the historically correct reason a caravel could beat back down the African coast when a nau
could not.

**And this is the finding that settles the owner's argument, so it is stated plainly:**

> **A point of sail is an angle between a heading and a wind. A fixed leg between two harbours has no
> heading — it has two endpoints. Origin's best mechanic is therefore *unimplementable* on the model
> byeharu-voyage chose, and `docs/DESIGN_RESEARCH.md` T9 took it anyway.** T9 says wind becomes *"a
> number that multiplies a speed"* — but nothing in the current schema can compute *which* number,
> because there is no bearing anywhere in `public.legs`. The knob `wind_mult_v0` is pinned at 1.00
> (`…0006…sql:357`) and there is no way to unpin it.

Two more current-related stats, same page:

> **Seaworthiness** — *"The ability of a ship to endure Rogue Waves. A Fleet with a high average
> Seaworthiness stat can **reduce the decrease in speed due to reverse currents**."* **[P]**
> **Rowing** — *"only exists for ships with oars, like a Galley … The speed of ships with high Rowing
> stats increases with more crew."* **[P]**

So **currents exist, they are directional ("reverse"), and they subtract speed** — and oars are the
period's answer to no wind at all, scaled by crew.

**Not verified:** the actual speed multipliers, the angular boundaries between the four relations,
whether wind is seasonal, and whether there are named real-world wind belts (trades, westerlies) or
an abstract per-region wind. **[U]** Every number in any wind model we build is ours, not theirs —
same honesty rule `docs/DESIGN_RESEARCH.md` §4 applied to ship stats.

### 5. Supply and range

**Consumed daily; running out kills crew, steadily rather than instantly.** [P]

> *"Food and Water are consumed every day during a voyage. **When you run out of Food and Water, the
> number of crew slowly decreases.**"*
> — [Voyage: How to Set Sail](https://uwo.floor.line.games/us/bbsCmn/detail/1653443788526014645) **[P]**

Note what Origin does **not** do: it does not end the run. That is a real difference from the
ancestor — `docs/DESIGN_RESEARCH.md` §2.1 records **[S]** that in *New Horizons* running out of
provisions is a **game over**. Origin softened a hard fail into an attrition curve, which is the
correct choice for a game you can be absent from, and it is what byeharu-voyage already does.

**So supply is what bounds free sailing, and it does so without any fence.** This matters for the
proposal: the answer to *"what stops a player pinpointing the middle of the Pacific?"* is **nothing
stops them, and nothing should** — the stores do. A destination you cannot provision for is refused
by an endurance rule that already exists (`voyage.sail_refusal`'s `E_ENDURANCE`), and that is the
whole fence the model needs.

### 6. Unit of time and control

**You steer in real time when present; you set a destination and leave when not; the voyage resolves
either way.** [P] — the two quotes in §2 above.

The load-bearing detail for us is the **Aide**: the player's absence is handled by *policy declared in
advance*, not by pausing, not by an AI improvising, and not by asking. byeharu-voyage's closed-form
position (`voyage.progress_nm`, `…0006…sql:555`) and its deterministic hazard seed
(`voyage.rng_raw`, `IMMUTABLE`, `…0006…sql:113`) are a **stronger** version of the same promise:
Origin's fleet must be simulated forward by something, ours is a pure function of time and cannot
drift, stall or double-apply.

**Not verified:** how fast Origin's game clock runs against real time, whether a voyage-day is a
unit at all, and what the Aide's option set is. **[U]**

### 7. How encounters find a ship at sea

**By proximity while sailing, at minimum for discoveries** [P] — *"Upon finding a suspicious area
while sailing"*, *"Approach a landing location while sailing"*.

**For danger, the mechanism is not published and I could not find it. [U]** What *is* published is
that danger occurs during offline sailing and is resolved against the Aide's settings **[P]** (§2),
which tells us the encounter is server-resolved, not player-driven — but not how the fleet and the
threat are matched.

**This matters for the proposal and is treated as an open risk, not a solved problem.**
`docs/PLATFORM.md` §1 finding 2 is the predecessor's hard-won lesson, and it is right: in byeharu a
fight was structurally impossible without a `location_presence` row, and free-coordinate arrival
created none, so **free movement was the one state in which nothing could happen to you.** The
proposal must not rebuild that. §P.10 gap 1 is exactly this — a water point must carry a `sea_id`, or
free sailing silently switches the hazard system off. **That is why the sea-id raster is inside the
slice and not after it.**

### 8. What did they do about the ocean being mostly empty?

Origin's answer is **things to find in the water, and a reason to look**: a *suspicious area* you sail
near, a **Telescope consumed to search it**, a camera flourish when you succeed, and a permanent entry
in the Journal. **[P]** Ashore, an exploration is *"a random event per exploration day"* with a
results screen of costs and rewards — `docs/DESIGN_RESEARCH.md` §1.10 **[P]**.

Advertised scale, **[S]** only (marketing copy via search extract, unchanged from the previous
research): *~200 ports, ~60 villages, 300+ battlegrounds, 20+ weather types.*

And one mechanic that fills the ocean with meaning for free:

> *"Each time you dock in a City, Adventure EXP is gained based on the distance you have sailed."*
> — [Growing Your Fleet](https://guide.floor.line.games/UWO/en_US/detail/1167031329446900354) **[P]**

`docs/DESIGN_RESEARCH.md` already takes this as T11. Under free sailing it gets **better and more
dangerous at the same time**: distance is now the *true* sailed distance rather than a graph's
inflated one — see §P.2, which measures the graph 15–22% long — so the reward is honest. But it also
means **a player can farm distance by sailing in circles**, which a port-to-port graph made
impossible. The fix is one line and should be written into the slice: credit **displacement between
ports actually docked at**, never path length.

### 9. What the reference does that we cannot or should not copy — bluntly

| Origin does | our answer |
|---|---|
| **Real-time manual steering with a stick** | **We cannot and must not.** Law 1 is *words, not pixels*; there is no per-frame client in this game and no visual sea. What we take is the *freedom* the steering gives — any water is a destination — not the steering. **The owner asked for "pinpoint anywhere in the ocean", which is the freedom without the frame rate.** |
| **A 3D sea with camera flourishes, seaweed, rogue waves, 20+ weather types** | Dropped, as `docs/DESIGN_RESEARCH.md` D8 already dropped it. Their sensory content is our *numbers and prose*. |
| **Momentum / Ice Breaking as ship stats** | **Taken, and generalised** — see §3. This is the one place we should copy the mechanism and not merely the flavour. |
| **Vertical / Horizontal sail against four points of sail** | **Taken** — and §4 is the proof that it requires the model change. Do not take it before there is a heading; T9 already made that mistake once. |
| **Aide: offline encounters resolved against pre-set policy** | **Already ours**, independently. Confirmed, not imported. |
| **Auto-sail to a harbour on the mini-map** | Taken as the *convenience default* — most voyages are port to port. It must be **one code path with pinpointing**, computing a path to a coordinate that happens to be a harbour. Two movers is the recorded catastrophe. |
| **Provisions as an attrition curve, not a game over** | Already ours. Their softening is the right call for an absent player and we made it too. |
| **Telescopes, Bedrolls — a consumable per discovery attempt** | **Deliberately not taken now.** It is a monetisation-adjacent friction and we have no discovery content for it to gate. Named so the decision is visible rather than forgotten. |

### 10. Explicit gaps — what I could NOT source

Stated so this file never launders a guess, same rule as `docs/DESIGN_RESEARCH.md` §4.

1. **Whether Origin's auto-sail pathfinds or follows authored lanes.** **[U]** The most directly
   relevant question to our decision, and the publisher does not answer it.
2. **Whether an arbitrary open-sea point can be an auto-sail destination.** **[U]** Only *"[Mini Map]
   → [Harbor]"* is documented.
3. **Running aground, shallow water, ship draft in Origin.** **[U]** Not mentioned anywhere I could
   reach. Our `max_draft` is our own invention, not an import.
4. **Every wind and current NUMBER** — multipliers, the angles bounding Tailwind / Cross Tailwind /
   Cross Headwind / Headwind, seasonality, named wind belts. **[U]** The *names* are **[P]**; the
   arithmetic is nowhere.
5. **How a hazard or pirate selects its victim at sea.** **[U]** Only that it happens offline and is
   answered by the Aide.
6. **The world map's scale, in cells or coordinates**, for Origin or for *New Horizons*. **[U]**
7. **Anything from `unchartedwaters.fandom.com` / `koei.fandom.com` / GameFAQs** — still HTTP 402/403
   from this environment, exactly as recorded in `docs/DESIGN_RESEARCH.md` §4 item 5. Every *New
   Horizons* and *UWO Online* claim in the previous file remains **[S]** and none of it is
   load-bearing here.
8. **Korean and Japanese sources.** Three background research agents were dispatched for
   Korean (나무위키, 인벤, 루리웹), Japanese (攻略wiki, 4Gamer, ファミ通) and English secondary
   material. **They exhausted this session's 200-call web-search budget and had not reported by the
   time this was written, so NOTHING in this document comes from them.** Everything above was fetched
   directly by me from the URLs cited. If their findings arrive they should be merged in as a
   revision — and the Korean/Japanese material is where questions 1, 5 and 6 above are most likely to
   be answerable.

### 11. The one-line version of Part One

**Uncharted Waters Origin lets you steer anywhere on an open sea, and offers destination-picking as a
shortcut. We built only the shortcut, then mistook its data structure for the world. Its best
mechanic — wind resolved against your heading — cannot exist without the thing we did not build.**

---

## PART TWO — THE PROPOSAL

Everything below is measured on this machine on 2026-08-24 unless marked otherwise. The measuring
tools are in `scripts/proto/` and every number in this part is reproducible by running them.

### P.1 What the game has today, stated exactly

| | |
|---|---|
| the sea | **a graph of 829 stored legs over 224 ports** (`data/sea-routes.json`, generated by `scripts/build-sea-routes.mjs`) |
| a route | Dijkstra over that graph — `voyage.reach_from` (`…0019…sql:220`), walked back by `voyage.route_direct` (`…0019…sql:352`), composed through hard VIA stops by `voyage.route` (`…0006…sql:273`) |
| a destination | **a port, and only a port.** `voyages.dest_port_id uuid not null references public.ports(id)` (`…0006…sql:69`) |
| a position | `voyage.progress_nm` → `voyage.position` (`…0006…sql:555, 599`), closed-form, **linear in lat/lon between the two ports of the current leg** |
| the coast | **not represented at runtime at all.** The 0.25° water raster exists only in `scripts/sea-grid.mjs`, at BUILD time. `docs/PLATFORM.md` §1 finding 4 says so in terms: *"Nothing at runtime holds that raster."* |

### P.2 The four defects that follow from it — all measured, none inferred

**1. A fleet is drawn across land on 65% of its legs.** A leg keeps its *length* but discards its
*shape*: `data/sea-routes.json` carries **0 paths on 829 legs**, and `voyage.position` interpolates
straight between two port coordinates. Re-tested here:

```
532 of 821 legs are drawn over land when rendered as a straight line
```

`docs/OWNER_REQUESTS.md` #41 is the owner's law — *"i don't want the fleet to ever touch land"* — and
today it is violated on the majority of legs, every time a fleet moves.

*(821 and not 829, because **8 legs reference a port `tidore` that is not in `data/ports.json`**.
Found incidentally while measuring; it may be another worktree's work in flight. Flagged, not fixed —
this task does not own that file.)*

**2. The graph is 17–22% longer than the sea.** This is the "fastest way possible" the owner asked
for, quantified. Dijkstra over the stored legs, against A\* over the water:

| route | graph nm | water nm | the graph costs |
|---|---|---|---|
| Lisbon → Manila | 14,478 | 11,858 | **+22.1%** |
| Antwerp → Macau | 15,647 | 13,099 | **+19.5%** |
| London → Guangzhou | 15,549 | 13,025 | **+19.4%** |
| Lisbon → Nagasaki | 15,466 | 12,989 | **+19.1%** |
| Amsterdam → Venice | 3,659 | 3,117 | **+17.4%** |
| Seville → Old Goa | 11,246 | 9,606 | **+17.1%** |
| Lisbon → Kozhikode | 10,928 | 9,499 | **+15.0%** |
| Lisbon → Salvador | 3,578 | 3,530 | +1.4% |
| Lisbon → Cádiz | 247 | 254 | −2.6% (the graph is *shorter*: see the honest note in P.8) |

A port-to-port graph must **land at a harbour to turn**. A ship does not. Every extra mile is extra
voyage-days, extra wages, extra provisions and extra hazard rolls, so this is not a cosmetic error —
it is a ~20% tax on the whole economy of long-haul trade, which is the game's entire late arc.

**3. The generator routed over the North Pole — and this one was FIXED WHILE THIS RESEARCH RAN.**
Recorded because it is the same root cause and because the correction is instructive, not because it
is still broken. At the start of this session `scripts/sea-grid.mjs`'s raster had an open Arctic and
no ice, so its own A\* took the Northeast Passage:

```
sea-grid.mjs's Lisboa→Nagasaki reached 88.6°N  —  7,565 nm
the true route round the Cape                  — 12,989 nm   (x1.72)
Antwerp→Honolulu: 6,501 nm  →  14,040 nm                     (x2.16)
```

A concurrent worktree added an `ICE` list to `scripts/sea-grid.mjs` on 2026-08-23 which closes the
Siberian and Canadian arctics **by longitude** above 66.5°N. **Re-measured against the current file:
Lisboa→Nagasaki is 12,989 nm and reaches 38.7°N. Fixed.** My own prototype had a flat latitude cut,
which was *worse* — it stranded Vardø at 70.4°N and fifteen real legs with it — so the prototype now
composes the upstream authority instead of keeping a second copy.

One residual, stated precisely: `ICE` closes only 60°E–180° and 180°–60°W, so **between 60°W and
60°E the raster is open water all the way to the pole.** That is right for the Barents and the
Svalbard whaling grounds and wrong at 88°N. It routes nothing today, because the passages either
side are shut — but under free sailing a player can pinpoint it.

**4. Ports teleport, silently.** A harbour sits on the coastline, so its own 0.25° cell is usually
land, and both generators snap it to water. Re-measured across all 223 ports:

```
mean water-snap 12.9 nm, worst 67 nm at longyearbyen (bristol 65 nm)
```

`sea-grid.mjs` then exempts a flat **25 nm at each end** of every straightening test, so that snap
costs no time, no distance and no risk, and is missing from every endurance check and every trade
margin. This is `docs/OWNER_REQUESTS.md` #41's second half.

### P.3 The model

> **A destination is any WATER POINT. The route is the fastest way through water, computed at
> departure. A fleet never touches land, by construction.**

Three sentences, and the third is the strongest argument for the whole change:

**A path found through water cells cannot cross land.** The never-touch-land law stops being an
intention enforced by a bolted-on guard and becomes a *property of how a route is made*. There is no
version of this model in which a fleet is drawn over Iberia, because the only shapes that exist are
shapes the search produced, and the search cannot leave the water.

Ports stop being the medium and become **places on the water**: a harbour is a coordinate with a
name, a market and a `max_draft`. Sailing to Cádiz is sailing to Cádiz's coordinate; the only thing
that makes it a *port* call is arriving there and docking.

### P.4 Where the search runs — and the measurement that decided it

I built the same A\* twice and ran both. **This is the load-bearing measurement of the whole
proposal**, and it settles the architecture rather than leaving it to taste.

| | Lisbon → Nagasaki (165,611 cells expanded) |
|---|---|
| **A\* in plpgsql, inside PGlite** (`scripts/proto/pglite-astar.sql`) | **582,971 ms — 9.7 minutes** |
| **A\* in JavaScript** (`scripts/proto/pathfind.mjs`) | **110 ms** |

A 5,300× gap. plpgsql pays interpreter overhead per statement and the inner loop runs ~1.3 million
times. **The search cannot live in the database.** That is not a preference; it is a measured wall.

Full JS figures, worst case first (binary heap, ice mask, 1,440 × 720 grid, warm):

```
route                          |  ms | cells expanded |     nm
Lisboa → open Pacific 0N 150W  | 158 |        122,695 | 11,602
Antwerp → Honolulu             | 138 |        138,642 | 14,040
Nagasaki → Lisboa              | 129 |        257,332 | 13,131
Lisboa → Nagasaki              | 110 |        165,611 | 12,989
Veracruz → Acapulco            |  92 |        132,984 | 12,379
Lisboa → Calicut               |  69 |         84,992 |  9,500
Amsterdam → Venice             |  17 |         17,775 |  3,117
Lisboa → Salvador              |   9 |         10,896 |  3,530
Lisboa → Cádiz                 |   5 |             40 |    254

WORST 158 ms · 40 random port pairs: 65 ms each · grid build 114 ms, once
```

For contrast, the same algorithm with the **linear open-list scan `scripts/sea-grid.mjs` uses today**
takes **3,453 ms** on Lisbon → Nagasaki. The heap is a 31× win and it is why this is affordable at
all; the existing generator's own comment — *"a linear scan … is fast enough and this runs offline"* —
is exactly the assumption that has to die.

### P.5 So what is the server for? The two things that must be authoritative

The server does not search. It does the two things that decide truth, and both are cheap.

**1. `sea.path_is_navigable(path)` — the law, enforced.** Every sample at half-cell spacing along
every segment of the submitted polyline is sailable water. **8.2 ms** for the Lisbon → Nagasaki path
inside PGlite.

**2. `sea.path_nm(path)` — the length, computed from the shape.** The client supplies a *shape* and
never a number. Verified equal to the JS figure to the nautical mile on every route tested.

```
route                  | pts |    nm | verify ms (three runs)
Lisboa → Nagasaki      |  11 | 12989 |  8.2 · 7.2 · 4.1
Lisboa → Calicut       |  12 |  9500 |  6.2 · 10.0 · 3.2
Lisboa → Salvador      |   4 |  3530 |  2.7 · 3.5 · 2.0
Amsterdam → Venice     |  16 |  3117 |  1.4 · 4.1 · 1.9
Lisboa → Cádiz         |   4 |   254 |  0.6 · 1.7 · 0.7
```

Three runs are quoted because the figures are noisy at this scale; **the claim is the order of
magnitude — single-digit milliseconds — not any one number.**

**That 8.2 ms took three attempts and the difference was storage, not arithmetic.** The first two
shapes both cost ~750–840 ms, because a 1 MB `bytea` lives in TOAST and every `get_byte()` pays a
detoast. Storing the sea as **720 rows of 1,440 bytes**, one per grid row, puts every value inline —
and consecutive samples nearly always share a row, so the fetch is cached inside one segment:

| shape | Lisbon → Nagasaki |
|---|---|
| one 1 MB `bytea`, plpgsql loop | 725–961 ms |
| one 1 MB `bytea`, single set-based SQL statement | 799 ms |
| **720 rows of 1,440 bytes, plpgsql loop with a row cache** | **4–8 ms** |

All three return identical answers on every case, including every anti-proof — asserted in the
bench, not assumed.

**The anti-proof, because a guard that cannot catch the thing is not a guard** — all seven refused,
and the real route accepted:

```
REFUSED   Lisboa → Barcelona straight across Iberia
REFUSED   Alexandria → Aden straight through Arabia
REFUSED   Veracruz → Acapulco straight across Mexico
REFUSED   Lisboa → Nagasaki great circle over Asia
REFUSED   a leg over the Sahara
REFUSED   the Northeast Passage along the Siberian coast
REFUSED   the Northwest Passage through the Canadian arctic
ACCEPTED  the real Lisboa → Barcelona, 828 nm round Gibraltar
```

### P.6 Why the server does not need to verify that the path is OPTIMAL

This is the question that decides whether "client searches, server judges" is honest or a hole, so
it is answered plainly rather than assumed.

A client controls only the **shape**. It cannot submit a shorter route than the water allows,
because shorter means crossing land and check 1 refuses that. It *can* submit a longer one — and a
longer route costs **more voyage-days, more wages, more provisions and more hazard rolls**, every one
of them already server-computed from the path. **Sub-optimality is a self-inflicted penalty, not an
exploit.** So optimality is a client *convenience*, exactly like `world.trade_routes`' mid-price
shortlist, and legality is a server *law*. One authority each, and they are different questions.

The one thing that must not happen: the server must never accept a client's *number*. It recomputes
`total_nm` from the polyline it just verified, and the frozen speed profile is derived from that.

### P.7 What this REPLACES — and it replaces, it does not join

`docs/OWNER_REQUESTS.md` #42 states the hard constraint, and `docs/PLATFORM.md` §1 records what the
predecessor paid for ignoring it: four overlapping movement paths, four ships stuck, five teleported,
a player's fleet destroyed, and *"is this fleet docked?"* in eleven hand-copied definitions.

| dies | what happens to its job |
|---|---|
| `voyage.route_direct(a, b)` (`…0019…sql:352`) | **deleted.** Its job is the water search. |
| `voyage.route(a, b, via[])` (`…0006…sql:273`) | **deleted.** A VIA waypoint becomes what it always physically was — *a water point you pass through* — so a multi-stop voyage is a path with fixed interior points, searched segment by segment by the same one function. |
| `voyage.reach_from(from, …)` (`…0019…sql:220`) | **deleted as a router.** Its *other* job — "how far is every port from here" — is real and is answered by the same authority: see P.9. |
| `public.legs` + `data/sea-routes.json` + `scripts/build-sea-routes.mjs` | **deleted.** Confirmed expectation: the leg table is the fixed graph. |
| `voyage.path_from_nodes` (`…0006…sql:305`) | **deleted.** A path is a polyline, not a chain of leg rows. |
| `voyage.sail_refusal(fleet, dest, nm)` (`…0019…sql:396`) | **re-cut, not kept alongside.** Crew, flagship, endurance are about the FLEET and survive unchanged. Draft and ice are about the DESTINATION and only apply when the destination is a harbour — an open-water point has no `max_draft` and refuses nothing. It keeps its name and its one-authority role; its signature changes from `(fleet, dest_port, nm)` to `(fleet, destination, nm)` where a destination is a water point that may or may not be a port. |

**The tell that this has gone wrong:** if, after the change, any code path computes a distance
between two ports by adding up stored edges, the graph has grown back under a new name.

### P.8 What survives untouched — and this is most of the value of the current design

**The closed-form position survives completely, and it gets better.** `voyage.progress_nm` consumes
`(departed_at, path, speed_profile, delay)`. Nothing in it cares whether a path element is a stored
leg or a computed segment — it needs a length and a speed per element, and a polyline has both. The
change is confined to `voyage.path_from_nodes` (which builds the path) and to `voyage.position`
(which turns progress into lat/lon).

And `voyage.position` gets *more* correct, not less: today it interpolates linearly between two port
coordinates, which is why a fleet crosses capes. On a polyline it interpolates along the segment it
is actually on — so **the line drawn and the distance charged become the same object**, which they
have never been.

**Byte-identical offline settlement survives, because nothing it depends on moves.**
`voyage.rng_raw` is `IMMUTABLE` and keyed on `(voyage_id, day_index, stream, world_secret)`
(`…0006…sql:113`). The path is frozen at departure. `voyage_events` stays `primary key (voyage_id,
day_index)`. `voyage.day_ends_at`'s ETA clamp is untouched. `scripts/db/proofs/01_offline_equivalence.sql`
should pass unchanged, and **must be run to prove it rather than argued about**.

**The frozen speed profile survives and finally earns its shape.** `speed_profile` is already *"a
jsonb array of knots, one per leg of `path`"* (`…0006…sql:79`) and today every entry is identical,
because `M_wind` is pinned at 1.00. On a polyline the entries are **one per segment**, and a segment
has something a leg never had: **a heading**. That is what makes §P.11's wind model possible at all.

**One honest correction.** Lisbon → Cádiz measures 247 nm on the graph and 254 nm on my raster — the
graph is 2.6% *shorter*. Two 0.25° rasters snap the same harbour to slightly different cells and
straighten differently. It is small, it goes both ways, and it means **the migration will move some
short-haul distances by a few per cent**, which will move `05_first_voyage_balance.sql`'s medians.
That is a retune, it is expected, and it must be done by the sanctioned path (`tune-balance.mjs`
sweep, then 0005's knobs) rather than by widening the band.

### P.9 The one hard consequence, stated rather than glossed

`world.trade_routes` (`…0019…sql:726`) ranks destinations by sailed distance, and it asks
`voyage.reach_from` for **every port's distance at once**. That question is real and it does not go
away. Priced over the water:

```
reach_from(lisbon) over the WATER: 237 ms, 607,598 cells expanded, 219/223 ports settled
reach_from(amsterdam):             210 ms, 608,073 cells expanded, 219/223 ports settled
```

One Dijkstra floods the whole ocean and settles every port — the many-destination question costs
**one** search, not 223. (The four that never settle are landlocked or inland-sea ports the raster
cannot join to the world ocean; they need naming, and they are the same four that would be
unreachable under any model.) But it costs ~220 ms against `voyage.reach_from`'s measured **15–23 ms**,
and — decisively — **it is in JavaScript, while `world.trade_routes` is a SQL read.**

**This is the seam where "replace, never join" is hardest, so here is the honest menu and my
recommendation, not a fudge:**

- **Recommended: `world.trade_routes` stops computing distance and starts being *given* it.** The
  client runs the one authority once (~200 ms, on the world read, cached until the fleet moves) and
  passes the reach set into the read. One authority for "how far is it by sea", one implementation of
  it, and the SQL keeps ranking and pricing, which is what it is good at.
- **Rejected: a materialised port-to-port distance matrix.** 221 × 221 is a cache, and a cache of
  distances that nothing sails along is *defensible* — but it is 24,310 rows shaped exactly like the
  thing we are deleting, and the day someone composes two of its rows into a route, the graph is
  back. If it is ever built, the guard is a self-assert that spot-checks N pairs against the
  pathfinder, and the rule is written on it: **if anything ever *sails* along a row of this table, it
  has become a second mover — delete it.**
- **Rejected: port them both.** Two implementations of A\*, one of which takes 9.7 minutes.

### P.10 Two gaps this proposal opens and cannot close by itself

**1. A water point has no `sea_id`, and the hazard system is keyed on one.**
`voyage.hazard_roll` reads `seas.hazard_base` and `seas.piracy_index` via the leg's destination port
(`…0006…sql:683`). A free path has no ports in the middle. And `data/seas.json` gives each sea only a
hand-placed `centroid`, explicitly *"NOT a surveyed centroid"* — so nearest-centroid would put the
Barbary piracy index on water off Sardinia. **This needs a sea layer with real extent** (a coarse
sea-id raster on the same 0.25° grid is the cheap, exact answer: one more byte per cell, built the
same way, indexed the same way). Until it exists, free sailing would silently lose the hazard
system's spatial dimension — which is the thing that makes the Barbary run different from the
Channel. **This is a required part of the slice, not a follow-up.**

**2. Ice is a static hand-drawn list, and a fleet can still pinpoint the North Pole.**
Upstream `ICE` (added 2026-08-23) is the right *shape* and it correctly shuts both passages. Two
things it does not do, both of which only bite once free sailing exists:

- **Between 60°W and 60°E the raster is open to 90°N.** Deliberate and right for the Barents and
  Svalbard; wrong at the pole. Under a fixed graph nothing could ever go there; under "pinpoint any
  water" a player can.
- **Ice does not move with the season.** The game already has `ports.is_ice_closed` and a season, so
  the concept exists — it just applies to harbours, not to water. The right shape is a **per-sea,
  per-season closure that masks cells**, and the pathfinder is where it attaches (the `buildNavGrid`
  wrapper in the prototype exists for exactly this and nothing else).

Neither blocks the model. Both should land in the same slice, because "sail anywhere" plus "the pole
is water" is a bug a player will find in the first hour.

### P.11 What a heading buys, once there is one — and the honest warning attached

The whole reason §P.8's per-segment speed profile matters: **wind only means anything if a course
exists, and a course only exists if you steer.** `docs/DESIGN_RESEARCH.md` T9 already took Origin's
best idea — `Vertical Sail` (crosswind) vs `Horizontal Sail` (tailwind) as two ship stats — and then
had nowhere to put it, because a leg has no bearing. A polyline segment does.

So the V1 shape is: for each segment, bearing → angle to the prevailing wind of that water and season
→ pick the ship's crosswind or tailwind coefficient → that segment's frozen knots. **It changes a
value, not the formula**, exactly as `…0006…sql:427` intended when it wrote *"the SHAPE is per-leg so
V1's seasonal wind changes the seeded values and not this code."*

**The warning, stated because it is the trap:** once wind is real, *the fastest path is no longer the
shortest path* — that is the whole of age-of-sail navigation, and it is why the Portuguese sailed the
**volta do mar** halfway to Brazil to reach India. A search that minimises distance will confidently
route into the doldrums. When wind lands, the cost function must become **time, not distance**, and
`sea.path_nm` stays as the legality check while a second number — sailed hours — becomes what the
search minimises. Building the search now with distance as its cost is correct for V0; **writing
`nm` into the search's contract as though it were the objective is the mistake to avoid**, and it is
avoided by making the step cost a function from the start, not a constant.

### P.12 What happens to `data/sea-routes.json`

**Deleted, with its generator `scripts/build-sea-routes.mjs`.** It is the fixed graph in file form.

`scripts/sea-grid.mjs` is **kept and promoted**: its raster, its channel list and its scan-fill are
the world's coastline, and they stop being a build-time convenience and become the shipped artefact.
Measured, it is small enough that this is a non-issue:

```
raw, one byte per cell           : 1,013 KiB
bit-packed                       :   127 KiB
bit-packed, base64 (in a migration): 169 KiB of SQL text
stored in Postgres, 720 rows     : 1,216 KiB on disk (uncompressed, deliberately — see P.5)
stored in Postgres, one bytea    :    27 KiB (TOAST-compressed — and 100x slower to read)
```

**The whole navigable sea of 1550 is a 169 KiB literal in one migration.** That is cheaper than the
829 legs it replaces, and unlike them it carries shapes.

One thing to flag rather than discover later: **`data/sea-places.json` is being built right now in
another worktree**, and its note says the spur legs joining each named water to its nearest harbours
are *generated* into the leg graph. Under this model, sea-places should be **labels on water and
legitimate destinations** — which is exactly what the owner asked for — and must **not** become graph
nodes with spur legs, or we will have deleted the graph and immediately grown a new one.

### P.13 Cost summary, all measured

| | |
|---|---|
| grid build, once per session | 114 ms |
| worst single search (JS) | **158–177 ms** |
| typical port pair (40 sampled) | 37–65 ms |
| whole-ocean reach, all 223 ports | 210–237 ms |
| **server proof that a path never touches land** | **0.6–10 ms** |
| server recompute of the path's length | included above |
| the sea, as a migration literal | 169 KiB |
| A\* in plpgsql — **rejected** | 582,971 ms |

---

## PART THREE — the prototype

`scripts/proto/` — measuring tools, not shipping code. Nothing in `src/` imports them.

| file | what it is |
|---|---|
| `pathfind.mjs` | the pathfinder: binary-heap A\*, line-of-sight straightening, `segmentIsWater`. Composes `sea-grid.mjs`'s raster and its `ICE` — it does **not** keep a second copy of either |
| `pglite-loader.mjs` | resolves PGlite for the benches. Prototype-only, and it exists for a bad reason: see the note below |
| `bench.mjs` | JS timings, the Arctic diff, 40 random port pairs |
| `pglite-astar.sql` | the same A\* in plpgsql — **the rejected option, kept so the rejection stays evidence** |
| `bench-pglite.mjs` | runs it: 582,971 ms |
| `raster.sql` | the sea in the database: one bytea, plus `sea.gc_nm` |
| `verify.sql` / `verify2.sql` / `verify3.sql` | the three storage shapes of the never-touch-land law |
| `bench-verify*.mjs` | their timings and the anti-proofs |
| `bench-graph.mjs` | the 829-leg graph against the water: the +19% table |
| `bench-reach.mjs` | the whole-ocean reach, and the port water-snap census |

### How to re-run the measurements

```
node scripts/proto/bench.mjs          # JS pathfinder, the Arctic diff, 40 random port pairs
node scripts/proto/bench-graph.mjs    # the leg graph against the water — the +19% table
node scripts/proto/bench-verify3.mjs  # the server-side law, three storage shapes, seven anti-proofs
node scripts/proto/bench-reach.mjs    # whole-ocean reach and the port water-snap census
node scripts/proto/bench-pglite.mjs   # the REJECTED plpgsql A*. Takes about 20 minutes.
```

**A warning for whoever runs these.** During this session the `bv-mover` worktree was emptied by
something outside this task — every tracked file vanished, including `docs/`, `src/`, `supabase/` and
the `node_modules` junction — while the measurements were mid-flight. The work was completed against
a scratchpad mirror and copied back, so `docs/` and `scripts/proto/` here are complete and the
numbers above are real. But:

- **the worktree still has no git metadata and no other files**, and needs recreating before anything
  can be committed;
- **`node_modules` is missing**, so the PGlite benches will not resolve the package. That is what
  `pglite-loader.mjs` works around, and re-creating the junction
  (`mklink /J node_modules ..\byeharu-voyage\node_modules`) is the proper fix;
- `scripts/proto/pathfind.mjs` imports `../sea-grid.mjs`, which is one of the files that vanished.
  **Restore the worktree before running the benches**, or run them from a clone that has it.
