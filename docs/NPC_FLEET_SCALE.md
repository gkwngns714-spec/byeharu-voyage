# NPC_FLEET_SCALE — ten times the ships, three times the routes, and a world that can carry them

**Status:** plan, 2026-10-11, written against `main` `330dbeb` (chain head 0100, production still 0095).
Owner rows **115-122** in `docs/OWNER_REQUESTS.md`. This is the sequel to `docs/NPC_TRADERS.md`,
which is the design of the merchant companies themselves; nothing here replaces it.

**What the owner asked for, verbatim (2026-10-11):**

- *"show all trade routes created"* · *"rank them with distance, earning prices, etc."*
- *"make 3 times more traading routes"*
- *"set levels (requirements)"*
- *"The NPC ships, create them more at least 3 times more"* → *"increase the number by factor of 10"*
- *"sort them by countries. Powerful and rich countries will have more ships compare to the ones
  that are poor"*
- *"the ships, higher ships will have different graphics, such as in size, two ships grouping,
  different graphics completely etc."*
- *"I will be able to click on npc, see their info, trading routes, etc."*
- *"The trading routes should be from cities to cities, visiting 2 cities, 3 cities, to max 8 cities
  then returning from the original starting city, earning gold. Then waiting at least 2 weeks in
  that city."*
- *"By clicking the city, i get to see what trading ships started, resting, ending etc."*

---

## 0. The answer in ten lines

1. **~760 merchant fleets over ~200 routes.** Ten times the ships (row 118, the later of the two
   numbers the owner gave), three times the routes (row 116). Several fleets share a route, which
   is both what a trading nation does and what makes the measurement affordable. **BUILT as 761
   fleets over 219 loops, 3.47 fleets a loop (§4).**
2. **The measurement moves from the FLEET to the ROUTE.** Today's generator measures every fleet's
   every candidate loop with the whole roster running, and that took hours at 107 fleets. Each
   distinct ROUTE is measured once, in a batch of forty, and every fleet that sails it inherits the
   figure. What that gives up is the whole-roster market interaction; that was always the deploy's
   soak, and it is said so here rather than quietly dropped.
   **AS BUILT it went further than that, and §4 says so: capital is DERIVED for every route from
   the server's own planner on the untouched market, and only a sample is sailed.**
3. **A nation's share is DERIVED, never opinionated** (row 119): from `ports.dev_commerce` and
   `dev_industry` over the harbours that nation holds. Castile and Portugal get dozens; a
   one-harbour coast gets a handful. The formula is in the generator and asserted in **0105**.
   ~~`size_tier`~~ **is NOT in it** — see §4: multiplying by Σ`size_tier` is quadratic in harbour
   count and gave Castile 54 % of the world's merchant marine.
4. **A route is 2 to 8 stops and returns to its first** (row 122a). The engine already loops; the
   generator now authors the whole range, and 0101 asserts the 8 as a law rather than a habit.
5. **A lap ends in a two-week rest at home** (row 122b). New: `route_rest_game_days` (14), a FLOOR
   on the hold at stop 0, superseding the merchant pace there. A merchant lies at her home quay and
   is visible doing it.
6. **A harbour reads back its merchants and what they are doing** (row 121): started, resting,
   ending, passing — derived from the route's own cursor and hold, never a new state column.
7. **The chart draws what a fleet IS** (row 120): three hull silhouettes by class, size by class,
   and a fleet of several hulls drawn as several. No legend (MAP_ATMOSPHERE §4).
8. **`world.sea_traffic` stops serving the whole world every beat.** At 760 fleets that is ~120 KB
   a read. It takes a viewport and a cap, and says how many it did not send.
9. **The route board** (row 115): every route, ranked by distance and by what it earns, with its
   level requirement printed — a READ, composing no order.
10. **Levels gate routes** (rows 113/117): `public.passage_gate` refuses a leg beyond your
    NAVIGATION and a region beyond your EXPLORATION, and the board prints the requirement.

---

## 1. The order of work, and why

| # | slice | why it is here |
|---|---|---|
| A | **0101** — the two-week rest, and the 2-8 stop law · **DONE 2026-10-11** | A server rule the generator must know before it authors a single route. |
| B | **0102** — `world.sea_traffic` takes a viewport · **DONE 2026-10-11** | 760 fleets cannot ship on a read that serves them all. Must land before the roster does. |
| C | **0105** — the generator: routes ×3, fleets ×10, shares by nation · **DONE 2026-10-11, §4** | The long one. Runs unattended; everything else can be built while it runs. |
| D | **The chart: hull silhouettes and fleet groups** · **DONE 2026-10-11** | Pure client, disjoint from C. |
| E | **0104 — the harbour's merchants: started / resting / ending** · **DONE 2026-10-11** | Needs 0101's rest to mean anything. |
| F | **0106 — the route board, ranked** · **DONE 2026-10-11** | Needs C's routes to be worth ranking. |
| G | **0107 + 0108 — the gates, and the board that prints them** (rows 113/117) · **DONE 2026-10-11** | Last, because it refuses things, and refusing things is easiest to get wrong when the world underneath is still moving. |

EVERY SLICE LANDED, AND C LANDED LAST THOUGH IT WAS STARTED FIRST — which is what the table was
ordered for. It was built in its own worktree off a chain that had only reached 0102, so 0104 and
0106-0108 were authored beside it and know nothing of its 761 fleets. Their self-asserts had only
ever run against 76; the chain was re-applied in filename order after the merge so that every one
of them has now proven itself against the full roster.
## 2. What is NOT being done, and why it would be wrong to

- **Not 760 hand-authored companies.** `data/npc-houses.json` is authored because 26 companies can
  be; 200 routes and 760 fleets cannot be, and pretending otherwise would be 20,000 lines of
  invented names nobody could check. The generator composes them from the world's own harbours and
  reaches, and the names come from a per-nation pool with the nation's own naming habit.
- **Not a measurement per fleet.** Stated above: it does not fit in a day, let alone a gate.
- **Not a new state column for "resting".** A merchant resting at home is a route whose hold has
  not expired at stop 0 — three facts the schema already holds. A fourth copy of her state is how
  two readings of the same thing come to disagree.

---

## 3. What slices A and B actually landed (2026-10-11)

**A — `20260818000101_a_lap_ends_in_a_fortnight_at_home.sql`.** `standing_route_stop_max` 6 → 8,
the owner's stated maximum; and `route_rest_voyage_days` (14), a FLOOR on the pacing hold in
`cmd.run_standing_route` — the one place a route decides it may not sail yet — so the rule is
`greatest(pace, rest)` and a slower merchant pace still wins. VOYAGE-days, the days the player
counts, derived from `time_compression` and never typed: 1260 real seconds at 0100's clock.
Merchants only (`players.is_npc`); a captain's own routes are not held, and that is one `and` away
if the owner ever wants it. §0 item 5 said `route_rest_game_days`; the knob shipped spelled
`route_rest_voyage_days`, because fourteen CALENDAR days is 448 voyage-days — four times the
longest passage in the game — and a knob whose unit can be misread is a knob that will be.

**B — `20260818000102_the_sea_is_read_through_a_window.sql`.** `world.sea_traffic()` is dropped and
`world.sea_traffic(jsonb default null)` takes its place (two overloads, one with a default, is an
ambiguous call). The window is `{south, north, west, east}` in degrees, padded by
`sea_traffic_pad_deg` (10°) and wrapping the antimeridian through `public.lon_in_view`; the read is
capped at `sea_traffic_max` (240) nearest-the-centre-first, and serves `total` and `omitted` so a
cap is never a silent truncation. A merchant is tested on her TRACK, not a position: at sea the two
ends of her current segment and its short-way midpoint, in port her roadstead or her anchor.

Measured in the file on the roster as it stands (76 fleets): an 8° window on Lisbon served 24 and
owned up to the 52 it left out, at 28.6 ms a call. Handed no window the read is its own pre-image's
answer, fleet for fleet in the same order, byte for byte — asserted against the old body cloned
into `pg_temp` one statement before it was dropped.

On the client, `src/live/seaWindow.ts` is the one place that shape is built, and the store sends the
UNION of the mounted screens' windows (`trafficWindows`, keyed by screen): MAP its viewport, PORT
six degrees of its own coast. A changed window does NOT read — the next beat picks it up, because a
merchant reading that lands outside the beat is drifted from an instant that did not produce it and
every hull on the chart jumps (`worldStore.wantTraffic`'s first-want rule). The 10° pad covers the
lag.

---

## 4. What slice C actually landed (2026-10-11) — `0105`, and the three things this plan got wrong

**`20260818000105_the_merchants_are_counted_by_their_coasts.sql`**, generated by
`scripts/build-npc-0105.mjs` from `scripts/roster/npc-names.mjs` and the world's own tables, with
`data/npc-roster.generated.json` as the reviewable receipt. 0098 is untouched.

### 4.1 The roster, as built

**761 merchant companies, 761 fleets, 761 hulls, over 219 distinct loops — 3.47 fleets a loop**,
beside the 76 fleets 0098 founded. Dark: `npc_traders_enabled` stays `false`, every route is saved
and unassigned, every fleet docked at its own stop 0 with no lines.

| | |
|---|---|
| loop lengths | 2 stops ×47 · 3 ×59 · 4 ×47 · 5 ×26 · 6 ×26 · 7 ×12 · 8 ×2 — **all seven legal lengths**, against 69-of-76 at three stops before this file |
| long loops | 66 call at five harbours or more, and **every one** takes in at least 2 regions and calls at least 2,500 nm from home. Median farthest call 4,154 nm |
| reach | **237 of the world's 238 harbours** are called at, including **80 of the 81 that belong to no nation** |
| classes | carlat 461 · nau 173 · barca 127 — read off each loop's own longest leg, then held to what every stop's `max_draft` can take |
| names | composed, never authored: every company has a distinct name and a distinct second spelling inside `players.company_name`'s own 24 characters, a master, a nation, and hull names no two of its own share |

### 4.2 The share: the formula, and the one that was rejected

`fleets(nation) = round(760 × Σ(dev_commerce + dev_industry) over that nation's HARBOURS ÷ Σ over
all nations)`. Linear in one authored sum, monotone in wealth, **no floor and no ceiling needed**,
and re-derived from `public.ports` inside the migration's self-assert — with a positive control that
proves the test bites on all 20 nations. Castile 194, Portugal 115, the Ottomans 93, Japan 56,
France 43, England 40, Joseon 31, Ming 27, Denmark-Norway 25, Venice 20, the Netherlands 20, the
Hanse 17, Poland-Lithuania 14, Morocco 13, Sweden 13, Genoa 12, Ayutthaya 8, Muscovy 8, the Mughals
7, Safavid Persia 5. **Built = derived for every one of the twenty.**

**§0 item 3 of this plan was wrong to include `size_tier`.** `(commerce+industry) × Σsize_tier`
multiplies two quantities that both grow with harbour count: it is quadratic in size, and measured
on the built world it gives **Castile 54 % — 412 fleets — against Safavid Persia's 0**. The sum
alone is what shipped.

81 of the world's 238 harbours belong to no nation. A HOME port comes only from a nation's own
harbours; the unaligned ones are destinations, which is also what they historically were.

### 4.3 MEASURED versus DERIVED — and the difference is not glossed

**DERIVED, for all 219 routes:** capital. `public.npc_plan` — the server's OWN planner — was run
once per route, in roster order, on the untouched market, and the BUY lines it wrote were priced
through `world.quote`, the one price authority. Capital is 1.5 × the dearest single leg's outlay,
floored at 1.5 × the loop's wages, which is 0098's own rule. 32 ms a route; the whole roster founded
at 1.8 ms a company.

**MEASURED:** a sample actually sailed through the one executor (`npc_found` →
`npc_traders_switch(true)` → `voyage.settle` at every arrival, `tick_market_drift` on its own
15-minute slots, the daily cap rolled at every game-day boundary, `npc_plan` + `npc_tend` on the
hour, hazards off), with 0098's roster driven beside it so the market is a real one. The sample is
chosen by the server itself: the roster order is STRATIFIED across nations and loop lengths, so
capping `npc_fleet_max` makes any prefix a proportional spread — and the reading is then also the
answer to "what does the world do at that ceiling".

**What the sample actually came to, and what it cost.** `npc_fleet_max` at 76 + 120 started **40 of
0105's routes**, and all 75 started routes (40 of 0105's, 35 of 0098's) were driven: **279 arrivals
over 139 simulated hours in 25 minutes of wall clock**, at which point the sail's own budget stopped
it with every sample route short of three laps — 37 of the 40 had closed one, none had closed three.
The budget is deliberate and the receipt says it bit: a build that cannot finish cannot be re-run by
the next person, and reporting fewer laps as though they were all it meant to take is the thing this
file refuses to do. An earlier run without a budget drove one short coastal loop round and round for
over an hour while the sample's longest carreira crawled, because nothing parked a route that was no
longer being measured.

**What the sample VALIDATES.** Derived capital ÷ 1.5 × the dearest single leg the sailed first lap
actually bought — like for like, the same rule the derivation sizes on — over the 35 routes that
closed a lap: **p10 1.04×, median 1.93×, p90 15.9×, and 2 of 37 under 1×**. So the derivation is
GENEROUS, by about twofold at the median: `npc_plan` plans a bigger parcel than the market actually
fills on the day, and the 1.5 floor sits on top of that. Two of the 37 were under-funded,
which is the honest residual — the plan at derivation time is not the plan at lap time, because the
market has drifted and a different merchant has taken the cargo. A merchant short of capital is not
stranded: she buys less. Over-funding by 3× a leg is a purse figure in world data, not an
exploit — nothing lets a merchant spend it anywhere but through `npc_plan`.

**What is therefore NOT known:** there is no per-fleet measurement of the whole roster over a long
soak. §0 item 2 said that, and it is still true; what §0 item 2 did not foresee is that *no* sailed
sample of useful size is cheap at this scale, so the figure every fleet actually carries is a
derivation. The generated JSON tags every number `measured` or `derived`, and the migration header
says which is which. A derivation is never reported as a measurement.

### 4.4 The clock, measured at each ceiling

`npc_fleet_max` was **120**. Measured on the built image (PGlite on this machine — slower than the
hosted Postgres, so these are conservative), hazards off, the switch on, 837 merchant routes in the
world:

| `npc_fleet_max` | routes running | `tick_arrivals` idle | …a minute on | …8 h on (every fleet at sea at once) | `npc_plan` hourly, all | `npc_tend` | `world.sea_traffic()` |
|---|---|---|---|---|---|---|---|
| 120 | 47 | 28 ms | **147 ms** (47 fleets) | 1,681 ms | 9,677 ms | 17 ms | 63 ms, serving 240/837, omitting 597 |
| 837 | 296 | 57 ms | **295 ms** (295 fleets) | 18,111 ms | 9,666 ms | 24 ms | 172 ms, serving 240/837, omitting 597 |

Reproduced across four independent builds of the same roster, to within 3 ms on the per-minute
figure and 600 ms on the hourly one, so these are the machinery's figures and not one run's.

`tick_arrivals` is the figure that decides the knob, because it is the one with a minute to finish
in — and it does **not** only settle arrivals: it settles every voyage whose next sea-day has ended
(0010:68), and a sea-day is 90 real seconds at 0100's clock, so nearly every fleet at sea is touched
by nearly every tick. At the full roster that is **279 ms a minute**. `npc_plan` and `npc_tend` have
an hour and take nine seconds between them. **So the ceiling is raised to cover the whole roster**,
and `sea_traffic_max` (240) is kept unchanged: 0102's cap is doing exactly the job it was built for
— it serves 240 and says it left out 597, rather than quietly shipping 837.

### 4.5 The finding that matters most: 760 fleets cannot all trade at once

On the untouched market, with each route planned by the server's own planner, **270 of 761 routes
found a cargo that pays and 491 did not**; switched on at the full ceiling, **296 of 837 run and the
rest are `laid_up`**. And it is not spread evenly: the planner funds **23 % of the two-stop fleets,
30 % of the three-stop, 39 % of the four-, 49 % of the five-**, which is the economy's own shape
showing through. `port_goods.affinity` is derived from how far a port is from the nearest place that
produces the good (0005), so two neighbouring harbours have nearly the same affinity for nearly
everything and a short coastal hop has almost no gradient to trade on. The owner asked for loops
"visiting 2 cities, 3 cities" (row 122a) and those loops are the poorest ones in this economy by
construction, not by accident.

This is not a defect, and it is not a roster that can be fixed by re-rolling it. On top of the
gradient it is the collision of two rules this plan did not put side by side:

- `npc_plan` allows **ONE merchant buyer per (port, good)** (0097), world-wide — not per route.
- A harbour trades only **4 to 10 goods** (0061). Across 224 harbours that is **1,288
  (port, good) slots in the whole world**, and a slot is only usable by a fleet whose own loop calls
  there and whose leg it actually pays on.

Giving the houses on a shared loop **different wares** — each takes her own slice of that loop's
affinity gradient, which is also what a real trading town looks like — moved it from 535 laid up to
513; lowering the generator's own gradient bar from a quarter of an affinity point to a hair's width
moved it to **491** and, more importantly, gave all 761 houses a real `wares` list where **448 had
been founded with an empty one**. That bar was mine and it was stricter than the game's: measured,
every single 2-stop and 3-stop loop fell under 0.25, while the server's planner still funded a fifth
of them, because `world.trade_routes` prices real stock and spread and the bar it clears is
`npc_min_return_pct` (2 %). An empty `wares` also costs a house `npc_plan`'s pass-1 preference,
which is the very mechanism by which houses on one loop specialise. So specialisation is right and
the bar had to be the game's — but neither is the binding constraint. The binding constraint is the
authored breadth of the market. A laid-up merchant is still founded, still visible in port, still
draws her whole loop on the chart, and `npc_tend` tries her again every `npc_laid_up_hours` as the
market drifts — so the world is not short of merchants, it is short of *simultaneously paying*
cargoes. **Widening it is a slice of its own** (more goods a harbour, or a per-route rather than
world-wide buyer rule) and it is the owner's call, not the generator's.

### 4.6 Two more things this plan, and one of 0098's rules, had wrong

- **A quay is a PRICE to a merchant, not a budget.** The roster very nearly shipped with a rule that
  Σ crew of the fleets homed at a quay must stay inside `crew_pool − npc_crew_pool_floor`, asserted
  in the migration. The premise is false, and 0097 says so in the body that draws the hands
  (`cmd.do_hire`): for a merchant only the hands ABOVE the floor come off the quay, the rest are
  recruited at `crew_urgent_multiplier` and take **nothing** off it, and `v_pool` itself is left
  alone — "a merchant at a drained quay still sails, poorer". The rule would also have refused a
  legal roster: Safavid Persia holds one harbour and all five of her fleets home on it. What is kept
  and asserted is the per-stop CAPACITY test, `crew_pool ≥ floor + a fifth of the fleet` — 0098's
  rule plus 0097's floor. Measured: **no fleet-stop pair in this roster would ever pay the urgent
  rate.**
- **Real water is not the same as a course a merchant would lay.** `voyage.path_refusal` passed
  Antwerp → Trabzon → Massawa happily: there is no Suez in 1500, so that leg sails round the Cape —
  **11,853 nm against an 1,800 nm straight line**. The generator now refuses a leg whose sailed
  distance exceeds 1.8 × its great-circle distance (floor 600 nm), which needs no map knowledge and
  catches every basin-crossing pair, and it scores the way home before committing the last stop.

### 4.7 What the generator costs, and where its time goes

77 s to lay 219 routes (2,483 pathfinder calls over 2,483 distinct legs, 38 s of it inside THE
pathfinder; 811 legs verified through `voyage.path_refusal`). The first build spent fifty minutes
here and was killed: it was verifying every *candidate* leg through the server, at ~150 ms a round
trip, for thousands of legs it would never use. Screening now measures a plotted course in JS — the
sum of great-circle distances between its own points, which is exactly what
`voyage.segments_from_course` sums, with the same formula and the same Earth radius — and the SERVER
still has the last word on every leg the roster keeps. Everything is seeded from a hash of
(nation, index, attempt): the same chain builds the same roster twice.
