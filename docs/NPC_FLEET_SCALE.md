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
   is both what a trading nation does and what makes the measurement affordable.
2. **The measurement moves from the FLEET to the ROUTE.** Today's generator measures every fleet's
   every candidate loop with the whole roster running, and that took hours at 107 fleets. Each
   distinct ROUTE is measured once, in a batch of forty, and every fleet that sails it inherits the
   figure. What that gives up is the whole-roster market interaction; that was always the deploy's
   soak, and it is said so here rather than quietly dropped.
3. **A nation's share is DERIVED, never opinionated** (row 119): from `ports.dev_commerce`,
   `dev_industry` and `size_tier` over the harbours that nation holds. Castile and Portugal get
   dozens; a one-harbour coast gets one. The formula is in the generator and asserted in 0103.
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
| C | **The generator: routes ×3, fleets ×10, shares by nation** | The long one. Runs unattended; everything else can be built while it runs. |
| D | **The chart: hull silhouettes and fleet groups** | Pure client, disjoint from C. |
| E | **The harbour's merchants: started / resting / ending** | Needs 0101's rest to mean anything. |
| F | **The route board, ranked** | Needs C's routes to be worth ranking. |
| G | **0102 — the gates** (rows 113/117) | Last, because it refuses things, and refusing things is easiest to get wrong when the world underneath is still moving. |

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
