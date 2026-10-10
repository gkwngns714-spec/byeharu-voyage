# NPC_TRADERS — merchant houses that sail the same sea, on the same machinery

**Status:** architect's plan, 2026-10-08, **revised the same day after two independent design
checks and a second measurement run (§14).** Nothing is built. Written against `bv-npc` HEAD
`e4d271b` (chain head `20260818000095_the_price_record_is_swept_every_tick.sql`; production head
0095, routes ON since 2026-10-01, ~30 real players). Owner request rows **109-111** in
`docs/OWNER_REQUESTS.md`. The dated design decisions this plan depends on are recorded in
`docs/DESIGN.md` §J.3 (MAP: the merchant exception, and the randomised spice geography) and Q7.

**What the owner asked for, verbatim (2026-10-08):**

- *"this game will now turn into simulator, of trades. add npc to and show movement on map to make
  this game feel more alive"*
- *"by clicking the npc ship, it will show how much it is earning per day or so"*
- *"it should be fleet as well, i will be able to click on fleet, see ships, captains, skills etc."*

**Ground truth.** Three read-only audits of the live function bodies (the chain applied under PGlite
and every function dumped with `pg_get_functiondef`), two measurement runs on 2026-10-08 (§3.2,
§3.3, §5.1; the second with every candidate loop priced leg by leg on the applied chain,
`scripts/db/measure-roster.mjs`, 308 `world.trade_routes` calls at **12.0 ms/call**), and the two
design checks in §14 back every file:line below. A re-cut function's live body is not its last
`create` text, so citations say "live (re-cut …)" where that applies.

**Words.** In SQL and on the wire the concept is `npc` (the switch is `npc_traders_enabled`). **To
the player it is a *merchant*: a merchant company, a merchant fleet.** "NPC" never appears on a
screen (`docs/WORDS.md` law 1; `tests/words.spec.ts` gains the ban). "House" is already banned as a
player word (`words.spec.ts:38`), so the card says *company*.

**Rules that bind this plan.** `docs/NO_SPAGHETTI.md` §1 (one authority per concept), §3 (a deployed
migration is never edited; supersede forward), §4 (self-asserts that can fail, probes that set their
own preconditions, **a positive control for every scan**), §7B (concept, home, second caller, wrong
shape — answered in §1 below), §7C (a conditional never chooses between an acceptable and an
unacceptable outcome); dark-first; `docs/DESIGN.md` law 3 (the map is an output device), §J.2 (no
PvP), §J.3; `docs/MAP_ATMOSPHERE.md` §4 (no mark that needs a legend) and §5; `docs/UI_DIRECTION.md`
§6 MAP (corners, a Tray, no new chrome).

---

## 0. The answer in ten lines

1. **A merchant company is a `public.players` row with `is_npc = true` and `auth_uid` NULL.** It
   owns real fleets, real ships, real signed officers and real skill levels in the tables players
   use. There is no NPC-only model of anything.
2. **A merchant fleet trades by a standing route (0092), and the ONE executor runs it:**
   `tick_arrivals` → `voyage.settle` → `cmd.advance` → route refill → `do_sail / do_buy / do_sell /
   do_provision / do_repair / do_hire`. No merchant code moves a ship or trades. Ever.
3. **Identity.** `current_player_id()` = `players.auth_uid = auth.uid()` (0004:262). NULL never
   matches, so no client door can resolve to a merchant. The doors the seeder needs are **sliced
   into server-only cores that take `p_player`** (the `cmd.enqueue` precedent, 0092:310); no core is
   granted to `anon` or `authenticated`; `cmd.assume_identity` (0008:599) is never used.
4. **Stops and courses are authored and baked** (deterministic, courses from THE pathfinder);
   **lines are planned live by ONE planner** from the server's one ranking (`world.trade_routes`,
   0019:676; server-only since the owner revoked the player's door in 0071:176), filtered by the
   house's authored wares, **sized by the quote authority's own answer to "how much does the sink
   take above cost"** (`world.quote(… p_limit)`, 0005:442-448), and tested per leg against the
   leg's wages. Merchants react to the market players trade in, hour by hour.
5. **Market impact is bounded by price, not by quantity:** every merchant BUY carries a ceiling of
   *the port's normal ask × (1 + patience)*, so a merchant can never drive a good more than
   `patience` above its normal price, and the daily cap and regeneration do the rest (§4.3).
6. **Self-heal, re-planning and retention ride the existing hourly `tick_reconcile`** (0010:133,
   cron `byeharu-voyage:reconcile`, 0012:97). No new cron. Merchant books are compacted to a
   rolling window; players' books stay append-only for ever. Upkeep never waits on a lock (§4.5).
7. **Read side:** `world.sea_traffic()` on the shell's beat (**3 s** at `time_compression` 9600,
   `src/app/AppShell.tsx:33-42`), read only while MAP or PORT is mounted, and
   `world.npc_fleet_card(fleet)` at tap time. Both refuse every non-merchant company.
8. **The client draws merchants through the SAME model, layer, glyph and hit test**, in a separate
   `model.traffic` list so nothing player-only ever sees one: a full-size hull in its NATION's ink
   with a quieter halo, drawn at sea AND docked (at the port's served roadstead point). A tap opens
   a read-only sheet built from the existing tiles.
9. **Dark first.** `npc_traders_enabled = false`: merchant routes are paused `dark`, both reads
   answer `enabled:false` and nothing, the map draws nothing. **The owner's one action, after the
   soak numbers are in DEV_LOG:** `select public.npc_traders_switch(true);`
10. **Four migrations, 0096-0099** (§11), each self-asserting with positive controls, plus proof 12
    (PGlite) that a merchant completes a profitable lap through the shared executor and that an
    authenticated client cannot reach a merchant, and one Playwright spec for the hull, the sheet
    and the per-frame liveliness.

---

## 1. NO_SPAGHETTI §7B: the concepts, answered before the first line

### 1.1 Merchant company

1. **Concept:** *a trading company the world keeps, not a person.* One predicate: `players.is_npc`.
2. **Where it lives:** a column on `public.players` (0004:49), `boolean not null default false`,
   with `check (not is_npc or auth_uid is null)` so a merchant can structurally never sign in.
   The authored flavour of a merchant (ink slot, blurb, master, home port, capital, patience,
   wares, the alternate loop) lives in `public.npc_houses (player_id pk → players)`: world data
   about a company, like `officers` is world data about people. **`npc_houses` is never a
   predicate.** Every "is this a merchant?" reads `players.is_npc` and nothing else (a trigger on
   `npc_houses` refuses a row whose player is not `is_npc`).
3. **Second callers, named now:** `settle_standings` (Rank exclusion, §6), `world.sea_traffic` and
   `world.npc_fleet_card` (the privacy filter, §7), `npc_tend` / `npc_plan` / `npc_compact` (§4.5,
   §5.2), the `forbid_mutation` exemption (§5.2) and the local rescue filter (§8.5). All read
   `players.is_npc`.
4. **Wrong shape, and its guard:** a second spelling of "merchant" (a name prefix, an
   `auth_uid is null` test, a uuid list, an `exists (select 1 from npc_houses …)`). Guard: the 0097
   self-assert reads the live bodies of every function in `cmd`, `world`, `public` and `voyage` and
   fails if any contains `auth_uid is null` or joins `npc_houses` inside a `where` that does not
   also name `is_npc` — **after first proving the scan can see** (a `pg_temp` function carrying the
   banned token must be reported, then dropped; §11). A text grep is a weak net and is said to be
   one; the reviewer's checklist (§8 of NO_SPAGHETTI) is the rest.

### 1.2 Merchant fleet

1. **Concept:** *a fleet whose standing route the world writes.* Not a new kind of fleet: a `fleets`
   row of a merchant company, with ships, posted officers, a provision preset and one route, made
   by the same authorities a player's fleet is made by.
2. **Where it lives:** the existing tables. The only new writers are the seeder
   `public.npc_found(spec jsonb)` (0098) and the upkeep trio (0097), and every row they create goes
   through an authority a player's verb also calls (§3).
3. **Second caller:** every core sliced for the seeder keeps its player door as its first caller.
   `public.form_fleet` has a plausible third caller (a player verb to form a second fleet:
   `fleet_max` = 2 exists, 0021, and no verb forms one today). `public.commission_ship` has two
   callers on day one: `new_house` and `cmd.do_build` (today's two copies of the ship insert,
   0004:308 and 0072 live `do_build`).
4. **Wrong shape, and its guards:** (a) a merchant trade that is not an `orders` row — proof 12
   asserts every merchant BOUGHT/SOLD event's order has `route_lap_id` set (the 0092 guard, applied
   to merchants); (b) a direct `insert into public.standing_routes / player_officers /
   player_skills / ships` in merchant code — the 0098 self-assert fails if `npc_found`'s live body
   contains `insert into public.`; (c) an executor that reads the caller — the 0096 self-assert
   fails if the live body of any of `cmd.advance`, `cmd.execute_order`, `cmd.do_*`,
   `voyage.settle`, `cmd.run_standing_route`, `cmd.enqueue`, `cmd.parse` contains `auth.uid()` or
   `current_player_id()`. That invariant is what the whole plan rests on; it was verified on the
   dump and is made a guard (with its positive control) so a future re-cut cannot break it silently.

### 1.3 Merchant route

1. **Concept:** *a standing route whose stops and courses are authored and whose lines are planned
   from the market.* An ordinary `standing_routes` row (0092:145) in every respect.
2. **Where it lives:** `standing_routes` / `_stops` / `_lines` / `_laps`. The planner,
   `public.npc_plan(now)`, is server-only and writes lines ONLY through
   `cmd.standing_route_save_for` (§3.1), never into the tables.
3. **Second caller of the planner's rule: none, and said plainly.** The RANKING the planner
   composes is `world.trade_routes` (0019:676; live signature `(p_from, p_fleet, p_radius_nm,
   p_limit, p_to)` after 0091). **It has no player caller:** the owner removed the player's
   comparison in 0071 (*"the game is to challenge players for finding the best prices by
   themselves"*, 0071:5-15), the grant was revoked at 0071:176 and 0071:227 asserts it stays
   unreachable; the function survived only because `scripts/db/proofs/04` runs it as `postgres`;
   `src/lib/rpc/catalog.ts` does not name it. Measured on the applied chain: it is the ONE registry
   row of `public.client_rpc_entry_points()` that `has_function_privilege('authenticated', …)`
   refuses — a stale row since 0071, dropped in 0096 (§11). So the planner is the ranking's only
   live caller; it is still the one ranking (a future player comparison, should the owner ever want
   one, must call it, never re-derive it). The planner adds no price, no gap screen and no second
   ranking of its own; what it adds are **two filters on that ranking's rows** (the house's wares,
   §4.1; one merchant buyer per (port, good)) and **one composed size** (the quote's `p_limit` walk).
4. **Wrong shape, and its guards:** a second ranking (a planner that quotes both ends itself to
   rank) — the 0097 self-assert fails if `npc_plan`'s live body contains `world.mid_price` or a
   `world.quote(… 'buy' …)` call (the sizing call is a `'sell'` quote with a limit, asserted
   present exactly once). A second pacing rule — the per-route `laps_per_game_day` (§4.2) is
   written only by the save door and read in exactly one place, `cmd.run_standing_route`'s pacing
   hunk. A second quantity rule — the BUY quantity is the quote authority's own `units`, never an
   arithmetic of the planner's.

### 1.4 Sea traffic (the map read)

1. **Concept:** *where every merchant fleet is right now, in the voyage shape the chart already
   draws — and where it lies when docked.*
2. **Where it lives:** `world.sea_traffic()` on the server; one store field `traffic` in
   `src/live/worldStore.ts`; mapped by `src/chart/liveWorld.ts`; placed by `buildChartModel`. The
   voyage sub-object is sliced out of `world.fleets` (live, 0028:185 re-cut through 0088) into
   `world.voyage_view(voyage, full)`, so both reads serve one shape from one builder.
3. **Second caller:** PORT's "Merchants in port" list (slice 5) reads the same store field.
4. **Wrong shape, and its guards:** traffic in `model.fleets` (it would leak into FleetsCorner
   `src/features/map/FleetsCorner.tsx:35`, the opening frame via `focusPoints`, labels
   `src/chart/labels.ts:478`, the Minimap `src/chart/Minimap.tsx:206`, and `selectFleet` at
   `MapScreen.tsx:140` which repoints the command draft). Guard: `tests/map.merchants.spec.ts`
   asserts `model.fleets`, `focusPoints`, `motionPoints` and `portRoles` are unchanged by traffic,
   and that a merchant tap never calls `selectFleet`. A second reader of traffic is guarded the way
   `flicker.spec.ts:67` guards the routes book.

### 1.5 Merchant card

1. **Concept:** *everything a player may know about one merchant fleet.*
2. **Where it lives:** `world.npc_fleet_card(fleet)` (server; the allow-listed key set is the
   contract, §7.3) and `src/live/MerchantSheet.tsx` (client; live-data React used by MAP and PORT,
   the `src/live/PortField.tsx` precedent).
3. **Second caller:** PORT (slice 5) opens the same sheet from its list.
4. **Wrong shape:** a card that serves `queue`, `cargo_basis`, `version`, `reserve` or ledger
   lines, or one that answers for a player's fleet. Guard: the key set is self-asserted exactly
   (the 0025:20-60 discipline), and the card refuses `E_NOT_FOUND` for any fleet whose company is
   not `is_npc`, asserted with a real player's fleet id.

### 1.6 Earnings

1. **Concept:** *what a route nets per real day, per lap, and over its last seven laps.*
2. **Where it lives:** ONE SQL function `public.route_earnings(route)` reading
   `standing_route_laps` (0092:196): the executors' own sums, 1:1 with the fleet.
3. **Second caller:** a player's own route card (`world.standing_routes`, 0092:788) is the obvious
   next reader; it will compose this function, never a copy.
4. **Wrong shape:** a client-side sum (forbidden by `src/chart/liveWorld.ts:16-28` and the live
   store's third rule) or a ledger sum (per company, not per fleet, and compacted for merchants).
   Guard: the browser spec asserts the printed figures equal the served ones.

### 1.7 Merchant upkeep

1. **Concept:** *what the world does for a merchant that a player would do by hand* — start it,
   un-stick it, re-plan it, refound it (a bounded number of times), and sweep its books.
2. **Where it lives:** `public.npc_tend(now)`, `public.npc_plan(now)`, `public.npc_compact(now)`,
   called in that order from `public.tick_reconcile` (0010:133, re-cut in 0097), each route in its
   own subtransaction, before reconcile's own invariant asserts (which therefore check the world
   AFTER upkeep touched it).
3. **Second caller:** `public.npc_traders_switch(p_on)` calls `npc_tend` at once, so a flip acts
   within the minute instead of at the next hour.
4. **Wrong shape:** upkeep that writes `orders`, `voyages`, `port_goods`, `ships` or `ledger`
   (becoming a second executor), or upkeep that WAITS on a lock the minute tick holds. Guard: the
   0097 self-assert fails if the live bodies of `npc_tend` and `npc_plan` contain `insert into
   public.orders`, `update public.voyages`, `update public.port_goods`, `update public.ships` or
   `insert into public.ledger`, or a `for update` without `nowait`. `npc_compact` alone may write
   the ledger (one carried row, §5.2) and says so in its header.

---

## 2. What exists that this composes (verified on the live bodies; file:line)

| Mechanism | Where | What merchants use it for |
|---|---|---|
| The queue runner and dispatcher | `cmd.advance` 0007:812 (re-cut 0047; 0092 hunks A/B at the queue-dry exit and the skip rule; 0093 gate) → `cmd.execute_order` 0007:759 (re-cut through 0086) → `cmd.do_sail` 0047:549 / `do_buy` 0022:674 / `do_sell` 0022:770 / `do_provision` 0017:251 / `do_repair` 0007:697 / `do_hire` 0007:632 | Every merchant order. None reads `auth.uid()` or `current_player_id()`; each takes `p_fleet` and reads `f.player_id` for `credit` / `emit_event` / `trade_daily` |
| The route refill | `cmd.run_standing_route` 0092:575 (re-cut 0093, 0094); renderer `cmd.standing_route_lines` 0092:396; `cmd.enqueue` 0092:310; `cmd.parse(p_player, p_fleet, text)` 0008:207 | Writes a merchant's next stop into its queue in the player's own grammar. Uses `sr.player_id`, never the caller. **The sail-on branch (0092:626-636) renders only `SAIL TO`; 0096 gives both branches one tail renderer (§4.4)** |
| Settlement and arrival | `voyage.settle` 0007:887 (live, re-cut 0027/0047/0059/0086): per settled sea-day a WAGES ledger row (`credit(f.player_id,'WAGES', -least(wages, purse))`) and a `voyage_events` row; on arrival ARRIVED → DOCKED (or UNABLE_TO_SAIL) → `VOYAGE_REPORT` (payload embeds every day line) → `cmd.run_standing_provision` → `cmd.advance`. Takes `fleets … for update` without `skip locked` (0007:916, live unchanged) | A merchant arrives, trades and departs in the same transaction, with nobody reading. Upkeep must never make this tick wait (§4.5) |
| The clock | `public.tick_arrivals` 0010:54 (re-cut 0092: the held-route wake loop); cron `byeharu-voyage:arrivals` `* * * * *` 0012:97; `tick_reconcile` hourly (`7 * * * *`), looping EVERY players row (0010:144); `wind_the_clock` / `unwind_the_clock` 0078; LIVE on production since 2026-10-01 (DEV_LOG) | The only thing that moves a merchant. PGlite has no pg_cron (`scripts/db/apply-chain.mjs:38`): proofs call the ticks by hand; local play gets a stand-in (§8.5) |
| Pacing | `standing_route_laps_per_game_day` = 1 (0092:134); the hold at 0092:656-668 — **`hold_until = to_timestamp((v_day + 1) × game_day_seconds)`, the same calendar boundary for every route on earth**; `world.game_day` 0005:294 (`game_day_seconds` 2880 = 48 real min) | Bounds laps per game-day. Generalised to an interval hold with a per-route count (§4.2) |
| The market | `port_goods` 0005:63 (stock, stock_target); price derives from stock (0005, elasticity 0.5); `world.mid_price(port, good, stock)` 0005:326; `world.quote(p_port, p_good, p_qty, p_side, p_limit, p_fleet)` 0005:399 (live 0083) — **`p_limit` stops the walk at a unit price (buy: above; sell: below, 0005:442-448) and `units` says how many it took**; `world.daily_cap_remaining(port, good, player)` 0005:453 (0.35 × target per company per game-day, lifted by ACCOUNTING, 0027); regeneration 15 % of the gap per game-day, clamped AT target (`tick_market_drift` 0010:111-117: `least(stock_target, …)`, so oversupply snaps back within a game-day); BUY is restricted to the city's 4-10 roster goods, SELL is not (0061) | Merchant trades move `port_goods.stock` exactly as a player's do. That is the simulator. The sell-side `p_limit` walk is the planner's parcel size (§4.1) |
| The ranking | `world.trade_routes(p_from, p_fleet, p_radius_nm, p_limit, p_to)` 0019:676, live signature after 0091; with `p_to` it prices every good this port trades against THAT port through `world.quote` at `route_probe_tuns` (50) and ranks by `profit`; rows carry `code, qty, outlay, proceeds, profit, return_pct, buy_price, sell_price, nm`. **Server-only since 0071:176; no caller in any live body, no catalogue entry; a stale registry row (measured)**. Measured 12.0 ms/call over 308 calls | THE ranking the planner composes (§4.1). With `p_fleet` null it needs no identity. Its player door is gone by the owner's order and is not reopened here |
| Officers and skills | `officers` 0015:55 (**51 seeded on the applied chain** through 0015/0022/0026/0073; 44 carry a nation, all 51 a `home_port_id`, 0015:63), `player_officers` 0015:82 (unique per player × officer, posted per FLEET), `fleet_officer_bonus` 0015:108; `skills` 0016:57 (4), `player_skills` 0016:78 (per COMPANY, max 5), `player_skill_bonus` 0016:97; `voyage.fleet_speed` (0027 re-cut), `ship_hold_capacity` 0017:157, `world.spread_effective`, `raid_crew_lost` 0027:167 | The "captains and skills" the owner asked to see. Every derivation is keyed by fleet or player, never by `auth.uid`, so merchants get identical speed, hold, spread, endurance and raid losses for free. An officer may serve several companies at once (already true between players) |
| Crew | `ports.crew_pool`: drawn by `cmd.do_hire` (0007:689), refilled only by `cmd.do_dismiss` (0086:219); **no tick regenerates it** (measured: those two are the only live writers) | A quay once emptied stays empty; the roster keeps big crews off small quays (§3.2) |
| Caps | `assert_house_caps` 0021:171 via `tg_house_caps`: `ship_max` 8 per company, `fleet_max` 2, `fleet_ship_max` 8 | Unchanged for merchants: one rule for all |
| Founding | `public.new_house(p_auth_uid, name, nation)` 0004:275 (server-only; **founds every nation at LIS**, live body unchanged; one barca 'Gaivota', `starting_ducats` 8,000 as a FOUNDING ledger row; an unknown nation code silently nulls `nation_id`, 0004:289) | Generalised with defaulted parameters (§3.1). Every new player's opening frame is Lisbon's, which is where liveliness is measured (§3.3) |
| Money and record | `public.credit` 0004:216 (THE mover; ledger row per movement), `emit_event` 0004:248, `forbid_mutation` 0004:135-150 on `events` and `ledger`, `assert_ledger_reconciles` (0004) run by `tick_reconcile` | Merchants pay what players pay. Their books are compacted (§5.2) under one exemption |
| Rank | `settle_standings` 0025:217 (loops EVERY players row, :247) → `player_fame` → `player_progress` 0069:119 (scans the whole ledger and events); `world.standings` 0025:270 reads only the photographed table | One filter keeps merchants off Rank and keeps the per-slot scans off their histories |
| Knobs | `public.world_config` 0001:128 (there is no `game_config` table), readers `wc/wc_int/wc_num/wc_text` 0001:182-209; dark-first precedent `standing_routes_enabled` 0092:125 + `standing_routes_on()` 0092:291 | `npc_traders_enabled` + `npc_traders_on()` in the same shape |
| The registry | `public.client_rpc_entry_points()` (last re-cut 0092:1167), `client_executable_writers()` 0018:228, `tests/rpc.surface.spec.ts` | Every new read is registered; every core is proven absent; **the stale `trade_routes` row goes, and the spec gains registry ⊆ granted and granted writers ⊆ registry** |
| Courses | `standing_route_stops.course` NOT NULL, ≥ 2 points (0092:170); `do_sail` verifies with `voyage.path_refusal(course, olat, olon, dlat, dlon, course_join_nm, head, tail)` and measures with `voyage.segments_from_course` (live); `voyage.sail_refusal` refuses `E_DRAFT` when `max(class.draft)` over the fleet exceeds the destination's `max_draft` (0036:443-447); the only course author is the pathfinder `src/lib/sea` (`proposeCourse`, `src/domain/passage/index.ts:160`; in Node, `scripts/db/proof-courses.mjs` imports it directly); endpoints are the served roadsteads `public.sea_reaches.roadstead_lat/lon` (0076:157, 0085) | Merchant courses are authored by that pathfinder at build time and verified by the server at every departure. Draft is checked at build time and asserted in 0098 |
| The chart | `src/chart/chartModel.ts:92-246` (THE position authority; sailing branch :182-219), `drift.ts:62-99` (needs `course[segIndex]`, `course[segIndex+1]`, `segNm`, `legFrac`, `sailedNm`, `totalNm`, `etaMs`), `FleetsLayer.tsx` (`TracksLayer` :30, `FleetsLayer` :115-157: header :21-24 "NO OTHER PLAYERS ARE DRAWN, EVER"), `hitTest.ts:62-89`, `liveWorld.ts:61-136` (position copied, never computed), `mapTypes.ts` (172 lines; `MapSelection` :166-171), `RoadsteadsLayer.tsx` + `roadsteads.ts` (the roads as furniture since 0076), `glyphs.ts` (`shipHalfLength` 6.5 = a 13 px hull, :82-87: "reads as a hull and not a dot", replacing the 8.8 px dot) | Merchants are placed, drawn and hit by the same code |
| The beat | `src/app/AppShell.tsx:33-42` (`READS_PER_VOYAGE_DAY` 4, `READ_MIN_MS` 3000: at 9600 a voyage-day is 9 s, so the beat is **3 s**; one `setInterval`, visibilitychange); `worldStore.refresh()` :446-475 reads fleets ‖ ledger ‖ player, then routes SEQUENTIALLY (the `for update` deadlock note :455-464) | Traffic is read on the same beat, after routes, only while a screen wants it (§8.1) |
| The opening frame | `src/chart/chartView.ts` (`OPENING_MIN_SPAN_DEG` 12 via `atLeast` :323, `OVER_COVERAGE_LIMIT` 2.2 :308, :343 "the frame is 12° across") | Liveliness is judged inside THIS frame, not world-wide (§3.3) |
| Dark-flag browser seam | `tests/routesOn.fixture.ts` (opens `dist/db/world-*.tar.gz` in PGlite, flips one `world_config` row, serves it with `page.route`) | `tests/npcOn.fixture.ts` copies it |
| Local rescue | `src/lib/db/rescue.ts:47-55` (`PLAYER_TABLES`), :122 (`select * from public.${table}`, unfiltered, into one ~2 MB localStorage slot); `scripts/db/build-image.mjs:125` ("an image is a WORLD, not a house"); `tests/db.image.spec.ts` | The seed companies are world data: the rescue must skip them (§8.5) |

**Names already taken, so not reused:** `world.trade_routes` (the ranking), `voyage.route`,
`src/chart/route.ts` (the voyage track, `buildTrack` :101), `standing_route*` (0092). The new SQL
names all start `npc_` (server) or `sea_traffic` / `npc_fleet_card` (reads); the client words are
*merchant*.

---

## 3. The merchant companies

### 3.1 The authorities, and how each is reached (migration 0096)

Each client door below follows the 0092 `cmd.enqueue` method: **slice the body into a core that
takes `p_player`; the door becomes `current_player_id()` + its player-only gates + the core.**
Hunks are cut from `pg_get_functiondef`, LF-normalised (memory: CRLF hunks never match), each
asserted to occur exactly once, and parity is proven by reverse substitution back to the pre-image
(the 0093/0094 discipline). ACLs are unmoved.

| Authority today | Live at | Sliced core (server-only) | What stays in the door |
|---|---|---|---|
| `public.new_house` | 0004:275 | **Generalised in place** (dropped and recreated, grants re-issued): `new_house(p_auth_uid, p_company_name, p_nation_code 'PRT', p_port_code 'LIS', p_fleet_name 'Gaivota', p_class_code 'barca', p_ship_name 'Gaivota', p_ducats null → starting_ducats, p_is_npc false)`; an unknown nation or port code RAISES instead of nulling (0004:289 today). `cmd.found_house`'s 3-argument call text is unchanged and asserted byte-identical in effect (same rows, same FOUNDING amount, same LIS) | n/a (server-only already) |
| the fleet insert in `new_house` | 0004:304 | `public.form_fleet(p_player, p_name, p_port) returns uuid` | n/a |
| the ship insert in `new_house` and in `cmd.do_build` | 0004:308; live `do_build` (0072) `insert into public.ships … values (…, c.durability, 0, 0, 0, store_ratio_default, false)` | `public.commission_ship(p_player, p_fleet, p_class_code, p_name, p_flagship, p_crewed boolean) returns uuid`: class defaults; `p_crewed` true = `crew_required` and the founding stores (new_house's 2.400 / 1.800), false = the empty hull `do_build` lays down. **Two copies of one insert today; folded here, per NO_SPAGHETTI §1's threshold.** Names are unique per company (`ships_player_name_unique`, 0004:104): the seeder names every hull distinctly | `do_build` keeps the yard, timber, fittings, price and the `BUILD` credit |
| `cmd.hire_officer` + `cmd.post_officer` | 0015:170 (re-cut 0073:231), 0015:242 | `public.sign_officer(p_player, p_officer_code, p_fleet)`: the `E_ALREADY_SIGNED` test, the purse precheck, the `player_officers` insert and the `OFFICER_WAGE` credit + `SIGNED_OFFICER` event; `public.post_officer_to(p_player, p_officer_code, p_fleet)`: the posting update | hire keeps `E_NOT_IN_THE_ROOM` (a docked fleet at an inn where `world.inn_present` is true, 0073) and fleet ownership; post keeps ownership |
| `cmd.study_skill` | 0016:155 | `public.raise_skill(p_player, p_skill_code)`: the level row and the `500 × next level` credit | the docked-at-an-academy gate |
| `cmd.provision_preset_save` / `_apply` | 0034:315 / 0034:417 | `cmd.provision_preset_save_for(p_player, p_preset, p_name, p_days)`, `cmd.provision_preset_apply_for(p_player, p_fleet, p_preset)` | `current_player_id()` only |
| `cmd.standing_route_save` | 0092:875 (re-cut 0093) | `cmd.standing_route_save_for(p_player, p_route, p_name, p_stops, p_reserve, p_losing, p_laps_per_game_day int default null)` — null = unchanged, so the door stays the ONE writer of every route column (§4.2). **The re-anchor hunk is fixed in the same cut (below)** | `current_player_id()` + `standing_routes_on()` |
| `cmd.standing_route_assign` | 0093:186 (replaced whole) | `cmd.standing_route_assign_for(p_player, p_route, p_fleet)` — already locks fleet-first and ends with `cmd.advance`, which starts the loop; its `min(ord)` anchor (0093:234) gets the same fix | same |
| `cmd.standing_route_pause` | 0093:274 | `cmd.standing_route_pause_for(p_player, p_route, p_paused, p_reason)` — `p_reason` defaults `'player'`; upkeep passes `'dark'` / `'laid_up'` | same |
| `cmd.clear` | 0008:573 | `cmd.clear_for(p_player, p_fleet, p_include_active)` | ownership |

**The repeated-harbour anchor, fixed for players and merchants alike (0096).** The live save door
re-anchors an assigned route with `select min(ord) … where port_id = v_at` (0092:1004-1021; the
assign door the same at 0093:234). A loop that calls at one harbour twice (outbound and homeward
Cape Town) is reset to the FIRST visit whenever the fleet is at or bound for the second, so the lap
boundary is never reached, no lap closes and no earnings exist — today's bug for any player who
edits such a route, and fatal for a merchant re-planned hourly. The cut: `v_anchor :=
coalesce((select ord from standing_route_stops where route_id = sr.id and ord = sr.stop_cursor %
v_n and port_id = v_at), (select min(ord) …))`, and in the docked-with-pending-orders branch prefer
`(sr.stop_cursor - 1 + v_n) % v_n` when that stop's port is `v_at`. Self-asserted with a probe route
that visits one harbour twice: the cursor at the second visit survives a save and an assign. **Until
0096 is live, `scripts/build-npc-0098.mjs` refuses a loop that repeats a harbour; the measured roster
(§3.2) repeats none, so the fix is a player repair, not a merchant dependency.**

**The encounter gates stay in the doors on purpose.** "You must stand in that port, on the day she
is drinking there" is a fact about a player's encounter; the money and the rows are in the cores,
so a merchant pays exactly what a player pays and passes every constraint and trigger (caps,
flagship uniqueness, the ships composite FK, the ledger invariant).

**Security, stated as the invariant the asserts check (0096):**

- Every core is `revoke all … from public, anon, authenticated`;
  `has_function_privilege('authenticated', core, 'execute')` is false, and asserted, for each.
- No core appears in `public.client_rpc_entry_points()` or in `public.client_executable_writers()`.
  Asserted. The stale `world.trade_routes` registry row is dropped, and
  `tests/rpc.surface.spec.ts` gains two set asserts: every registry row is executable by
  `authenticated`, and every client-executable writer is a registry row (today a listed-but-revoked
  row passes unseen).
- A door resolves its company only from `current_player_id()`. Under `cmd.assume_identity(<a probe
  player>)` + `set local role authenticated` (the proof 11 shape), every door in the table, plus
  `cmd.issue`, `cmd.haggle`, `cmd.divert`, `cmd.fulfil`, `cmd.trade_basket`, `cmd.hire_officer`,
  `cmd.study_skill`, handed a merchant's fleet, route, preset or officer id, refuses "not yours" /
  `E_NO_SUCH_*`. Asserted in proof 12 (as `authenticated`) and in 0096 (as the owner).
- The executor chain is identity-free (§1.2 guard c), asserted by reading the live bodies after a
  positive control.
- `npc_found`, `npc_tend`, `npc_plan`, `npc_compact`, `npc_traders_switch`, `route_earnings`,
  `npc_buy_ceiling`, `fleet_crew_shortfall` are not granted to any client role.

### 3.2 The roster (`data/npc-houses.json`, authored; §11 slice 2 bakes it)

> **GROWN THREEFOLD, 2026-10-10.** The owner opened the map and said *"make the npc counts 3 time
> larger"* and *"there are no trades seen between different continents"*. The authored roster went
> from 26 companies / 35 fleets / 78 hulls to **70 companies / 107 fleets / 224 hulls** — 44 new
> companies, 28 of them with a second fleet, because the chart draws one hull per FLEET and fleets
> are what make the sea look busy. The new houses are weighted at the two things those two
> sentences name: eight work the Iberia-Morocco-Madeira-Canaries frame every new captain is founded
> into, and eleven are intercontinental by construction (Pernambuco and Bahia to Lisbon, the Tierra
> Firme galleons, Manila to Acapulco, Delft to Colombo and Malacca, the Cape line to Mombasa,
> Angola to Brazil, Virginia, Québec). Each new fleet's `wares` are the goods its own loop's
> harbours actually offer (`data/ports.json`), never a guess. `npc_fleet_max` rose 40 → 120 in the
> same breath, or two thirds of the roster would have stayed dark and the count would have been a
> lie. **The measurement is still the judge**: the generator refuses an unsailable loop (it refused
> three — Guayaquil cannot take a nau's draft, Osaka↔Sakai is a zero-length course) and trims any
> fleet that cannot pay its own wages.
>
> **WHAT THE MEASUREMENT ACTUALLY FOUNDED: 60 companies, 76 fleets, 131 hulls** — against 23 / 32 /
> 64 before, so **2.4× the fleets on the water** rather than the 3× authored. The difference is 29
> drops, and they are the rule working: a loop that could not pay its own wages over laps 3-6, with
> the whole roster competing in the same market, is not seeded on hope. **The Lisbon opening frame
> is crossed by 21 loops, up from 14.** Six trim passes ran before the roster stopped changing. The table below is the FIRST roster, kept as the record of
> how the rule was applied; the numbers the chain actually founds are in
> `supabase/migrations/20260818000098_*.sql`'s own header, which the generator writes.

Real nations (`nations`, 0003:35-55; every roster code exists), real harbours (codes verified
against the applied chain's `ports`), the three hulls that exist (`barca` 60 t · 8 crew · 5.0 kn ·
draft 1; `carlat` 90 t · 12 · 6.0 · 1; `nau` 400 t · 60 · 4.4 · **draft 3**; 0003:2086-2091).
There are no new hulls: a Ming or Gujarati house sails Western classes, a known limitation of the
world data, not of this plan. Caps (`ship_max` 8 per company, `fleet_max` 2, `fleet_ship_max` 8)
are **not** raised for merchants; every company below holds ≤ 5 hulls in ≤ 2 fleets.

**Three physical rules the build step enforces and 0098 asserts (both were missing in the first
draft, and the first draft's roster broke the first two):**

1. **Draft.** For every fleet, `max(ship_classes.draft)` ≤ `min(ports.max_draft)` over its stops —
   the same test as `voyage.sail_refusal` (0036:443-447). A nau draws 3; **Seville, London,
   Hamburg, Gdansk, Riga, Bordeaux, Nantes, Antwerp, Bruges, Basra, Guangzhou, Ayutthaya and nine
   smaller harbours take 2** (measured), so they are barca/carlat stops only. The first draft homed
   the Flota at Seville and the Indiamen at London: both last legs would have been refused
   `E_DRAFT` every lap, for ever. They now sail from Cádiz (max_draft 5; where the flota moved
   historically) and Portsmouth (4).
2. **Crew.** Every stop's `crew_pool` ≥ 20 % of the fleet's `crew_required` — `crew_pool` never
   regenerates (§2), so a raid's loss must be replaceable on the loop. Every stop below is a
   tier-3 or tier-5 quay (240 / 400) or a tier-2 one (160) visited by a 16-24-crew fleet.
3. **No harbour twice in one loop** (the anchor bug, §3.1), and no stop that is not a `HARBOUR`,
   and every leg plottable by THE pathfinder from the served roadsteads.

**How the economy sizes a fleet, measured twice on 2026-10-08 on the applied chain.**
`stock_target` is 60 / 137 / 311 at p10 / p50 / p90 and 670 at the great harbours; regeneration
refills 15 % of the gap per game-day. Wages are `crew_wages(crew)` = crew × 1 🪙 per SEA-day
(0086), a sea-day is 9 real seconds (`time_compression` 9600, 0045:46-48), and a lap round the Cape
is ~190-220 sea-days: a three-nau convoy owes ~33-40 k 🪙 per lap before it sells a ton. **The
first measurement run priced only each leg's best good at the executor's full daily cap and found
11 of 31 fleets "unprofitable" — an artefact of the parcel size, not of the market: a 181-unit
parcel of a 5 % good is a loss at the sink, a 30-unit parcel of the same good is a gain. The
second run sizes every parcel the way the planner will (§4.1: the quote's own `p_limit` walk at
the sink, then the caps and the hold) and prices the top three goods per leg; on that sizing EVERY
candidate loop below nets positive on its first lap, 2-port shuttles always lose to a 3-4-stop
loop of the same house, and the ocean convoys are the thinnest against their wages (Indiamen
1.0×, Retourvloot 1.4×, Carreira 3.5×).** First-lap figures on an untouched market are an upper
bound (TRADE_ROUTES §13.2 measured Beirut ⇄ Tripoli saturating +2,531 → +1,399 → +250 → −18 in
four unpaced laps); what sizes a convoy is the STEADY STATE, so the build step (§11 slice 2)
founds the WHOLE roster, warps six laps through the real executor with hazards off, and judges each
fleet on the mean net of laps 3-6 — trimming hulls, largest first, until that mean is at least
`npc_min_net_to_wages` (0.2) × the mean lap wages, printing every trim. A fleet trimmed to nothing
is dropped, loudly, and the house's alternate loop is tried first. That is how "a big VOC convoy
versus a small Genoese pair" is decided by the game's own economics rather than by the author's
wish.

**Loops are chosen, not fixed.** `data/npc-houses.json` authors 3-4 candidate loops per fleet
(the ones measured below plus the losers, kept as the house's alternates); the build step picks
the loop with the best measured steady-state net, and the second-best is baked into
`npc_houses.alt_loop` for the refound rule (§4.5). Fleets are named after the ROUTE, never the
cargo, because the cargo is the market's to decide.

**The roster, with the 2026-10-08 first-lap measurement of the loop that won among its
candidates** (sink-sized parcels, top three goods per leg, lines − wages; "home outlay" is the
money the first stop's lines need; capital = 1.5 × the largest leg outlay of the measured lap,
floor 1.5 × lap wages, printed by the build step):

| # | Company (`company_name`, ≤ 24) | Nation | Fleet → hulls (max) | Loop (stop 0 = home) | Skills S/N/A/H | Officers | Patience | Lap at sea | Wages/lap | First-lap net | Home outlay | What it carried, measured (blurb source) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Casa da Índia | PRT | Carreira da Índia → 3 nau | LIS → CPT → KOC → OLD → ISL | 3/3/2/2 | NAV, QM, SURG | 0.30 | 27.8 min | 33,383 | +116,065 | 128,832 | quicksilver, silk-cloth, silk-raw to the Cape; civet-cats, malachite to Kochi; shawls, bezoar, sandalwood-carving Goa → Mozambique; civet, zanzibar-doors home |
|   |  |  | Carreira do Brasil → 2 carlat | LIS → SLV → ELM | (company) | PURSER | | 9.2 min | 1,474 | +68,782 | 254,480 | quicksilver, silk-cloth to Salvador; emerald-muzo, whale-oil, brazilwood to Elmina; benin-bronzes home |
| 2 | Casa da Guiné | PRT | Carreira da Guiné → 2 carlat | LIS → ELM → LUA | 2/2/1/1 | QM | 0.15 | 8.3 min | 1,321 | +64,204 | 231,207 | quicksilver, silk-raw, silk-cloth to Elmina; benin-bronzes, gold-dust to Luanda; yams, copper home |
| 3 | Capitania de Macau | PRT | Nau do Trato → 2 nau | MAC → NAG → MNL | 2/3/1/2 | NAV, PURSER | 0.25 | 4.2 min | 3,391 | +32,230 | 287,304 | musk, scroll-paintings, rice-paper to Nagasaki; katana, kyoto-fans to Manila; mace home |
| 4 | Kamer Amsterdam | NLD | Retourvloot → 3 nau | AMS → CPT → MAL → JAK | 3/3/3/2 | NAV, QM, SURG | 0.30 | 33.8 min | 40,611 | +57,434 | 75,157 | sea-charts, vermilion, pike-heads to the Cape; malachite, civet-cats, myrrh to Malacca; aloeswood; nutmeg, cloves, gamboge home |
|   |  |  | Oostzeevaart → 2 carlat | AMS → GDA → COP | (company) | QM | | 1.6 min | 255 | +11,611 | 9,294 | vermilion, snuff to Gdansk; kvass; baltic-amber, amber, amber-work home |
| 5 | Kamer Zeeland | NLD | Zeeuwse Vaart → 2 carlat | MID → BOR → LIS | 2/2/1/1 | NAV | 0.15 | 2.6 min | 410 | +11,883 | 0 (ballast out) | antwerp-presses, woad Bordeaux → Lisbon; silk-cloth, quicksilver, silk-raw home |
| 6 | Casa de Contratación | ESP | Flota de Indias → 3 nau | CAD → LPA → CAR → HAV | 3/2/2/2 | NAV, SURG | 0.30 | 13.3 min | 15,940 | +150,609 | 81,590 | sword-blades, merino to Las Palmas; indigo, sugar, archil-lichen to Cartagena; allspice, pearls to Havana; vanilla, emeralds, tortoiseshell-combs home |
|   |  |  | Galeón de Manila → 2 nau | ACA → MNL → MAC | (company) | PURSER | | 23.5 min | 18,768 | +96,497 | 87,304 | silver, cinchona-bark, vicuna-wool to Manila; mace to Macau; musk, scroll-paintings, jade home |
| 7 | East India Company | ENG | Indiamen → 3 nau (the trim will likely leave 2) | PTH → ELM → CPT → KOC → SRT | 3/3/2/1 | NAV, QM, SURG | 0.30 | 31.3 min | 37,527 | +39,149 | 49,758 | culverin, baize to Elmina; benin-bronzes to the Cape; civet-cats, malachite to Kochi; bezoar, shawls, saltpetre home |
|   |  |  | Country Ships → 2 carlat | SRT → HOR → DIU | (company) | PURSER | | 2.1 min | 330 | +18,186 | 173,331 | bezoar, shawls, carnelian to Hormuz; steel-billets, socotra-aloes to Diu; ballast home |
| 8 | Levant Company | ENG | Turkey Fleet → 3 carlat | LON → ALE → IZM → LIV | 2/2/1/1 | QM | 0.20 | 7.2 min | 1,717 | +20,647 | 150,573 | cannon, tin, sheffield-plate to Alexandria; damascene-work to Izmir; carpets to Livorno; ballast home |
| 9 | Merchant Adventurers | ENG | Cloth Fleet → 2 carlat | LON → ARP → COP → HAM | 2/1/1/1 | PURSER | 0.15 | 1.8 min | 293 | +9,242 | 20,939 | cannon, tin to Antwerp; tapestries, clocks to Copenhagen; beer; silver-plate home |
| 10 | Hanse zu Lübeck | HAN | Bergenfahrer → 2 carlat | LUB → BER → HAM | 2/2/2/1 | QM | 0.15 | 1.6 min | 260 | +3,523 | 41,677 | russia-hemp, shot-and-ball to Bergen; ballast; stoneware home |
|    |  |  | Rigafahrer → 2 barca | LUB → GDA → RIG → STO | (company) | — | | 1.6 min | 170 | +926 | 2,071 | smallwares to Gdansk; amber, beer to Riga; ballast; ballast home |
| 11 | Hamburger Kontor | HAN | Flandernfahrer → 2 carlat | HAM → ARP → LAR → BOR | 2/1/1/1 | PURSER | 0.15 | 2.1 min | 342 | +36,186 | 54,609 | silver-plate, smallwares to Antwerp; diamonds, clocks to La Rochelle; ballast; woad, weld home |
| 12 | Banco di San Giorgio | GEN | Coppia Genovese → 2 barca | GOA → NAP → PAL | 1/1/0/0 | — | 0.10 | 1.1 min | 118 | +6,522 | 75,901 | gold-thread, velvet, kermes to Naples; ballast; citrus home |
|    |  |  | Linea di Cadice → 2 carlat | GOA → CAD → BAR | (company) | PURSER | | 1.9 min | 304 | +30,791 | 232,107 | velvet, italian-canvases, gold-thread to Cádiz; quicksilver, sword-blades, merino-sheep to Barcelona; andalusian-horses home |
| 13 | Mude di Venezia | VEN | Muda d'Alessandria → 3 carlat | VEN → ALE → BEI → DBR | 2/2/2/2 | NAV | 0.20 | 3.0 min | 721 | +25,885 | 174,096 | velvet, lace, gunpowder to Alexandria; damask, cumin to Beirut; pistachios to Dubrovnik; ballast home |
|    |  |  | Muda di Fiandra → 2 carlat | VEN → MES → CAD → LIS → BRU | (company) | SURG | | 6.3 min | 1,007 | +23,791 | 43,680 | gunpowder, theriac, soap to Messina; ballast; sword-blades to Lisbon; quicksilver, porcelain, silk-raw to Bruges; ballast home |
| 14 | Marchands de Marseille | FRA | Caravane du Levant → 2 carlat | MRS → IZM → IST | 2/1/1/2 | — | 0.15 | 3.0 min | 482 | +27,937 | 154,838 | velvet, silk-cloth to Izmir; carpets to Istanbul; mastic, iznik-tiles, isinglass home |
|    |  |  | Barques d'Alger → 2 barca | MRS → TUN → PAL | (company) | — | | 1.4 min | 148 | +17,771 | 121,410 | velvet, silk-cloth to Tunis; coral to Palermo; ballast home |
| 15 | Tüccar-ı İstanbul | OTT | Mısır Kervanı → 3 carlat | IST → ALE → BEI | 2/1/1/1 | PURSER | 0.20 | 1.9 min | 448 | +29,100 | 47,231 | mastic, gallnuts, alum to Alexandria; damask, cumin to Beirut; pistachios, cotton-raw home |
| 16 | Mercadores de Surat | MUG | Mocha Fleet → 2 carlat | SRT → JED → ADE | 2/1/1/2 | PURSER | 0.15 | 4.9 min | 783 | +37,715 | 168,711 | shawls, bezoar, saltpetre to Jeddah; attar-of-roses to Aden; myrrh, dragons-blood, persian-berries home |
| 17 | Tujjar al-Basra | PER | Gulf Fleet → 2 barca | BSR → DIU → HOR | 1/1/1/1 | SURG | 0.10 | 3.6 min | 381 | +8,333 | 83,747 | peridot, horses, persian-berries to Diu; cowries to Hormuz; ballast home |
| 18 | Juncos de Quanzhou | MNG | Rota de Luzon → 3 carlat | QUA → MAC → MNL | 2/2/1/2 | NAV | 0.20 | 1.7 min | 402 | +19,861 | 0 (ballast out) | ballast to Macau; musk, nankeen, china-root to Manila; mace, abaca home |
|    |  |  | Costa de Cantão → 2 barca | QUA → GUA → HOI | (company) | SURG | | 2.1 min | 226 | +30,192 | 0 (ballast out) | ballast to Guangzhou; tea, cloisonne to Hoi An; burma-rubies, ceylon-sapphires, birds-nests home |
| 19 | Shuinsen de Nagasaki | JPN | Shuinsen → 2 carlat | NAG → AYU → HOI | 1/2/1/1 | QM | 0.15 | 5.3 min | 847 | +35,283 | 113,045 | kyoto-fans, matchlocks, katana to Ayutthaya; sappanwood to Hoi An; burma-rubies, aloeswood, birds-nests home |
| 20 | Waegwan Traders | JOS | Tsushima Run → 2 barca | BUS → NAG → SAK | 1/1/0/1 | NAV | 0.10 | 1.5 min | 156 | +5,055 | 43,556 | tiger-skins to Nagasaki; katana to Sakai; sutra-scrolls home |
| 21 | Krom Phra Khlang | AYU | Siam Junks → 2 carlat | AYU → BNT → MAL | 1/1/1/1 | — | 0.15 | 2.9 min | 471 | +12,883 | 45,974 | ceylon-sapphires, benzoin, gamboge to Banten; ballast; bezoar, aloeswood, sappan-java home |
| 22 | Dansk Kompagni | DNK | Øresund Fleet → 2 carlat | COP → BER → LON | 1/2/1/1 | SURG | 0.15 | 1.8 min | 290 | +869 | 11,282 | amber-work, beer to Bergen; ballast; pewter home |
| 23 | Consulado de Bilbao | ESP | Flota de Vizcaya → 2 carlat | BIL → BOR → NAN → LIS | 1/1/1/1 | — | 0.10 | 1.7 min | 275 | +17,360 | 0 (ballast out) | ballast to Bordeaux; arquebus, woad to Nantes; tapestries, snuff to Lisbon; quicksilver, porcelain, silk-cloth home |
| 24 | Armateurs de Nantes | FRA | Flotte de Nantes → 2 carlat | NAN → CAD → LIS | 1/1/1/1 | — | 0.10 | 2.0 min | 319 | +8,505 | 10,754 | tapestries to Cádiz; sword-blades to Lisbon; silk-raw, porcelain, quicksilver home |
| 25 | Consolat de Barcelona | ESP | Nau Catalana → 2 carlat | BAR → PAL → NAP | 1/1/0/1 | — | 0.10 | 1.3 min | 212 | +3,340 | 41,450 | armillary-spheres, andalusian-horses, bacalhau to Palermo; ballast; hemp, almonds home |
| 26 | Mercadores do Porto | PRT | Costa do Algarve → 2 barca | OPO → LIS → CAD | 1/1/0/1 | — | 0.10 | 1.0 min | 108 | +7,367 | 0 (ballast out) | ballast to Lisbon; wool-cloth to Cádiz; sword-blades, quicksilver, salted-tuna home |

That is **26 companies, 35 fleets, 78 hulls (maxima: 16 nau, 48 carlat, 14 barca), across every
region of the world data**, inside `npc_fleet_max` (40). Houses 23-26 are new since the first
draft: they densify the waters every new company starts in (§3.3). "Lap at sea" is the round
trip's sea-time, `Σ nm / (kn × 24) × 9 s`, from the measured reach table (LIS→CPT 5,145 nm;
CPT→KOC 4,346; KOC→OLD 377; OLD→ISL 2,680; ISL→LIS 7,038; AMS→CPT 6,221; CPT→MAL 5,579;
JAK→AMS 11,451; CAD→LPA 675; LPA→CAR 3,676; CAR→HAV 1,060; HAV→CAD 3,940; ACA→MNL 8,100;
MAC→ACA 7,794; PTH→ELM 3,706; SRT→PTH 10,664; LUB→BER 519; GOA→CAD 905; MRS→IZM 1,208;
QUA→MAC 342; NAG→AYU 2,480; BIL→BOR 191). Legs with no paying good on the untouched market are
printed as "ballast": a merchant sometimes sails empty, and the planner re-asks every hour.

**Blurbs and names are generated, never asserted from history.** Historical believability cannot
be claimed from history on this world: 0058 re-rolled `public.port_specialties` to the owner's
per-city counts (0061:14-18; OWNER_REQUESTS row 48 "randomly distributed"), and on the applied
chain **black-pepper is produced at Elmina, Lagos and Lisbon (affinity 0.930 = the producer floor,
0005:50) and not at Kochi (1.381); cinnamon at Chennai, Lisbon and Old Goa; cloves at Ambon,
Jakarta and Makassar; quicksilver at Cádiz, Lisbon and Seville; silk-raw at Lisbon, Patras and
Tripoli** (producers per good range 1-3 over 555 goods). The measured Carreira carries quicksilver
and silk out and civet home, never pepper. So the build step writes each `npc_houses.blurb` from the
measured steady-state lines (*"Quicksilver and silk to the Cape; shawls and bezoar to Mozambique;
civet home — under Capitão-mor Fernão Lopes."*), 0098 asserts that every good named in a blurb is
in the baked first-lap lines, and the spice geography itself is recorded in DESIGN.md §J.3 as a
dated decision the OWNER takes (re-authoring the producer roster is a HELD gameplay migration:
`port_goods.affinity` is re-derived under live players holding cargo), never changed silently here.

**Personality in four real ways:** hull count and class (trimmed by the economy); `player_skills`
levels (the company's four skills, 0016:78); officers posted per fleet (`player_officers.fleet_id`,
0015:82), taken from the 51-officer catalogue **by home port on the loop first, then nation, then
specialty, then bonus descending**, deterministically (the catalogue is shared and unique per
(player, officer), so a merchant signing an officer takes her from nobody and Bartolomeu Dias may
serve two companies, as he already may serve two players); and `npc_houses.master`, a named master
printed on the card (*under Capitão-mor Fernão Lopes*), flavour only, no mechanic. 0098 also adds
**twelve lesser, nation-matched officers** to `public.officers` as world data (bonus ≤ 10 %, home
ports on the roster's loops, 0015's row shape) so merchant sheets are not all famous names.
Plus `npc_houses.wares`, the authored list the planner filters by (§4.1), and the company's
nation ink on the map (§8.2).

**Names.** `company_name` is globally unique (0004:52). Each roster entry carries a second
spelling; `npc_found` uses the first that is free and prints which; if both are taken it raises
(never silent). Because a raise inside 0098 would abort `supabase db push` part-way and block every
later migration (DEPLOY_RUNBOOK:82's failure class), **`scripts/build-npc-0098.mjs` takes
`--taken names.txt`** — the owner's one SQL-editor read, `select company_name from public.players`
— and refuses to emit a colliding roster; the raise stays as the net. A player who later tries a
historical name gets `E_NAME_TAKEN` — accepted here.

**Founding money is ledger-honest.** `npc_found` founds the company with
`capital + Σ officer wages + Σ skill costs` and the officers and skills are then paid for through
the same `credit` calls the player verbs make, so the company's purse ends at `capital`. The ships
are endowed, exactly as every player's Gaivota is (0004:308 inserts her unpaid). **`capital` is the
measured first parcel, not a per-ton rule:** 1.5 × the largest leg outlay of the measured lap
(quicksilver is 1,919 🪙 a unit at Lisbon, measured, so a 100 🪙/t rule would have had the Carreira
trimmed for lack of money, not margin), floor 1.5 × lap wages. Minted merchant ducats never reach a
player: there are no transfers (DESIGN §G.7), and Rank excludes merchants (§6).

### 3.3 Liveliness, measured where the player looks

The player's eye is one frame, not the world. Every new company is founded at Lisbon (§2:
`new_house`), and the opening frame is at least 12° across, fitted to the player's own things
(`chartView.ts:323/343`, `OVER_COVERAGE_LIMIT` 2.2) — so for every new player the question is
"what moves inside Lisbon's 12° frame", and world-wide counts ("six hulls moving somewhere") say
nothing. **Ten of the 35 fleets' loops enter that frame** (Carreira da Índia, Carreira do Brasil,
Carreira da Guiné, Zeeuwse Vaart, Muda di Fiandra, Linea di Cadice, Flota de Indias, Flota de
Vizcaya, Flotte de Nantes, Costa do Algarve); with interval pacing at `npc_laps_per_game_day` 6
(§4.2) a 1-3-minute regional lap keeps a fleet at sea 15-40 % of the time, and docked merchants
are drawn at their roadsteads (§8.2), so the frame always shows the merchants that are in port and,
on average, two to four that are moving. **The build step computes this geometrically for every
nation's capital** (loops whose courses cross a 12°-wide portrait frame on the capital) and
refuses a roster that leaves any founding frame with fewer than two crossing loops; the Playwright
spec (§11) measures it on the real chart at 390 × 844 for a Lisbon start: ≥ 2 merchant hulls
inside the opening frame, averaged over 5 minutes of warped clock. **The lever if a frame looks
empty is `npc_laps_per_game_day` (higher = more often at sea), paid for in rows (§5); the lever if
it looks crowded is `npc_fleet_max`.** Both are live knobs.

**MEASURED ON THE BUILT ROSTER, 2026-10-10** (`node scripts/db/measure-merchants.mjs --ticks 20`,
the applied chain, switch on, 23 companies / 32 fleets). The script drives the roster UNPACED
(`npc_laps_per_game_day` 0 — every fleet starts her next lap the moment she can), which is the
**upper bound** of what the pace lever can buy:

| | |
|---|---|
| hulls inside the Lisbon 12° frame, after each of 21 ticks | `5 2 4 2 4 4 3 2 4 2 4 2 5 2 2 5 4 3 4 3 5` — **mean 3.4, min 2, max 5** |
| merchant rows written | 16,516 for 102 closed laps = **161.9 a lap**; 4,230 an hour of sea-time |
| retained after `npc_compact` | **1,076 rows** against the `npc_row_budget` of 100,000 |
| `world.sea_traffic()` | **7.07 ms/call** over 50 calls, 12,715 bytes served, 32 fleets at sea |
| `world.npc_fleet_card()` | 2.38 ms/call over 20 |

So the design's own target ("on average, two to four that are moving") is met and is also the
CEILING: **raising `npc_laps_per_game_day` cannot make the frame busier than ~3-5 hulls, because
the binding constraint is the roster, not the pace** — and the owner, reading
`docs/npc-traders/map-merchants-1280.png` on 2026-10-08, said the sea must look busier than that.
The cost figures above say the room exists (1,076 retained rows against 100,000; 7 ms a read), so
what a busier sea needs is MORE FLEETS — a roster past this plan's own maxima of 26 companies /
35 fleets (§14 N3), re-measured and re-generated through `scripts/build-npc-0098.mjs`. That is a
gameplay decision with the economy at stake (every added fleet trades in the market players trade
in), so it is **the owner's call and is not taken here**; it is `docs/OWNER_REQUESTS.md` row 109's
open half.

One thing that DID make a harbour look busier was a defect, now fixed: merchants lying in one port
were all drawn at the single roadstead point, one hull on top of another, so three merchants at
Lisbon looked like one (and only the first could ever be opened). They are fanned round the berth
(`src/chart/liveWorld.ts` `fannedBerth`).

---

## 4. Routes: baked where they must be, planned where they should be

### 4.1 Lines are planned by ONE planner, from the market, hourly

`public.npc_plan(p_now)` (0097; server-only; called by `tick_reconcile`) does, for every merchant
route **starting at roster index `(hour mod n)` and wrapping** (so no house is structurally last
every hour), inside its own subtransaction with the fleet locked before the route (the 0093 lock
order, `for update nowait`, §4.5), skipping routes paused `error` or `laid_up` (§4.5):

1. For each stop `i` with next stop `j`, rank goods with **`world.trade_routes(port_i, null,
   null, k', port_j)`** — the server's one ranking, priced end-to-end through `world.quote` at
   `route_probe_tuns`. No fleet is named, so no identity is needed and the basis is the default
   one (`basis.qty_from = 'default'`). Measured 12.0 ms/call: ~125 calls an hour for the roster.
2. **Filter** the rows: first to the house's authored `npc_houses.wares` (the Hanse carries
   herring, salt, wax, furs, hemp; the Levant Company wool-cloth and tin out, silk-raw, carpets,
   mastic back; Casa da Índia spices, cardamom, wootz, civet; the VOC cloves, nutmeg, camphor,
   sea-charts; the Flota silver, cochineal, emeralds, quicksilver; authored per house from the
   measured lines of §3.2), falling back to the unfiltered rows only when nothing on the list
   pays; then drop any good a merchant route planned EARLIER IN THIS PASS already buys at `port_i`
   (**one merchant buyer per (port, good)**; tracked in a temp table, so the previous hour's lines
   of a later route never block an earlier one). Both are filters on the ranking's rows, not a
   second ranking.
3. **Size** each kept good with the quote authority's own answer, not a rule of the planner's:
   `q = (world.quote(port_j, good, cap, 'sell', row.buy_price × (1 + npc_sell_margin 0.05),
   null)).units` — how many units the SINK takes above the probe's cost plus a margin, from the
   `p_limit` walk (0005:442-448) — where `cap = least(world.daily_cap_remaining(port_i, good,
   house), world.daily_cap_remaining(port_j, good, house), hold ÷ bulk)` (the cap authority, both
   ends; the executor applies the source cap again at fill time). **Keep the good only if
   `profit(q) − leg_wages > 0`**, `profit(q)` = the same two quotes at `q`, `leg_wages` = crew ×
   `wage_per_crew_day` × `nm ÷ (voyage.fleet_speed × 24)`; and `return_pct ≥ npc_min_return_pct`
   (**2**, a floor against noise, not a gate: a 500-nm hop for a 2-carlat pair owes ~85 🪙, which a
   5 % margin on 60 units pays several times). Keep the first `k` = `npc_lines_per_stop` (3).
4. Write stop `i`'s lines, in the existing grammar (0092:181), through
   `cmd.standing_route_save_for` with the SAME stops and courses:
   - `SELL` everything on board, **only above cost** (`good_id` null, `at_profit` true), one line;
   - for each good that was `E_PRICE_LIMIT`-skipped on a SELL at this stop in BOTH of the last two
     closed laps (`standing_route_laps.skipped`, 0092:496): `SELL <good> ALL` with no floor — the
     merchant cuts its losses after two failed tries, which is what makes a bad cargo leave;
   - `BUY <good> <q> AT <ceiling>` for each kept good, ceiling from `public.npc_buy_ceiling`
     (§4.3). `q` is the sink's answer; the executor still bounds it by hold, stock, the source's
     daily cap and the purse (`fleet_buy_capacity`), so the planner can never over-order;
   - `repair` true at stop 0; `crew_up` true at every stop (§4.4); `p_laps_per_game_day` =
     `npc_laps_per_game_day` (§4.2).
5. A leg with no qualifying good sails in ballast (a merchant sometimes does; §3.2 measured ~20 %
   of legs in ballast on the untouched market). A route with no qualifying good on ANY leg is
   paused `laid_up` for this hour and tried again next hour.

The queue fits by construction: ≤ k SELL expansions + ≤ 2 cut-loss SELLs + PROVISION + REPAIR +
HIRE + k BUY + SAIL = 12 = `order_queue_max` at k = 3; the renderer's existing overflow rule
(trailing SELLs dropped with `E_QUEUE_FULL` noted, 0092:690) covers the rest.

**Deterministic where it matters.** The STOPS and COURSES are authored (`data/npc-houses.json`)
and baked into 0098 by the build script; the LINES depend on the market, as a player's would,
with no randomness anywhere (ties fall to good code). The same world state always plans the same
lines.

**What "NPCs react to the player" means, concretely.** A player floods Cádiz with sword-blades:
the Linea di Cadice's SELL stands only above cost, it is skipped, and within the hour the planner
carries something else. A player corners quicksilver at Lisbon: the Carreira's BUY ceiling is
exceeded, the line is skipped, the lap sails short, and the card says so (§7.3 "skipped"). A
merchant's own sales push a sink's stock up and its price down, which a player can buy into.
Every one of those is the executor refusing or filling a line; none is new code. The market the
planner reads is the one players trade in — and the only one, since the owner removed the
player's comparison (0071): merchants have no view a player lacks, only the patience to re-ask
every hour.

### 4.2 Pacing: one rule, generalised; one knob; one per-route count

The live hold (0092:656-668) counts laps STARTED in the current game-day and holds until
`to_timestamp((v_day + 1) × game_day_seconds)` — **the next calendar boundary, the same instant
for every route on earth.** With merchants that is a thundering herd: every regional merchant
wakes in the same minute, bursts its laps back-to-back and sits docked for the rest of the 48-min
game-day (and lands all its departures in ONE `tick_arrivals` transaction). So 0096 generalises
THE ONE pacing hunk to an interval hold:

`v_per := coalesce(sr.laps_per_game_day, wc_int('standing_route_laps_per_game_day'))`;
if `v_per > 0` and this call has just closed a lap: `hold_until := (select max(started_at) from
standing_route_laps where route_id = sr.id) + game_day_seconds / v_per`.

One rule for all. For players (`laps_per_game_day` null → the knob, 1) the next lap may start one
game-day after the LAST START instead of at the next calendar boundary — **a small, visible
change for live players, stated here and in TRADE_ROUTES §13 and DEV_LOG**: D2's number (one lap
per game-day) is unchanged; its anchor moves from the calendar to the lap, which also stops every
player route on earth waking in the same minute. 0092's pacing self-assert ("six ticks run three
laps") is re-stated for the interval form in 0096 rather than claimed as byte parity.
`standing_routes.laps_per_game_day int null` (0096) is written only by the save door
(`p_laps_per_game_day`, §3.1); the planner passes `npc_laps_per_game_day` (knob, **6**: a lap start
at most every 8 min) at every pass, so a knob change propagates within the hour. An ocean lap
longer than the interval is paced by its own length. Routes de-synchronise by themselves because
lap lengths differ; the one burst left is the switch minute, when `npc_tend` assigns every route
in roster order and their first SAILs leave together — said, accepted, and it is one minute.
`world.standing_routes` keeps serving the knob as `laps_per_game_day` (its own routes are null);
the editor is the named next caller when players get the setting.

### 4.3 The market bound: a price ceiling anchored to the port's NORMAL price

`public.npc_buy_ceiling(p_port, p_good, p_patience)` =
`round(quote_now × mid(stock_target) / mid(stock_now) × (1 + p_patience), 2)` where
`quote_now` = `world.quote(port, good, 1, 'buy', null, null).avg_price` and `mid(s)` =
`world.mid_price(port, good, s)` (0005:326). It composes the two price authorities' own answers
and restates no spread, tax or elasticity; its self-assert pins `ceiling = quote_now ×
(1 + patience)` to the cent when stock = target.

Why a price and not a quantity:

| Bound | Mechanism (all existing, plus the ceiling) |
|---|---|
| A merchant cannot drain a market | `do_buy` fills `AT p` only while the step price stays under `p` (live, 0022 re-cut 0050/0061/0080-0083). Price is `(target/stock)^0.5` × drift (elasticity 0.5), so a ceiling of `(1+p) ×` normal is a stock FLOOR of `target / (1+p)²`: 0.83 × target at patience 0.10, 0.59 at 0.30. The 0097 self-assert drives a merchant BUY against a hand-set market and requires the stock to stop above that floor less one trade step |
| It cannot dominate a pair | one merchant buyer per (port, good) (§4.1) and the per-company daily cap of 0.35 × target (`fleet_buy_capacity` applies it to ALL) |
| It cannot chase a squeezed price | the ceiling is anchored to the port's NORMAL price, not to the price at plan time, so re-planning never ratchets it up behind a rising market |
| It cannot dump at a loss | SELL only above cost; the cut-loss line is the one deliberate exception, after two failed laps |
| It cannot flood a sink | the parcel is what the sink takes above cost (§4.1 step 3), so a merchant does not carry 180 units into a port that wants 30 |
| It SHOULD move prices, a little, visibly | it does: a merchant's source good sits up to `patience` dearer than normal while it works the pair, and its sink is briefly cheaper (regeneration clamps oversupply back to target within a game-day, 0010:117). Big companies carry `patience` 0.30, small ones 0.10 — the VOC is a price-setter, a Genoese pair is not. `npc_houses.patience` is checked to `[0.05, npc_price_patience_max = 0.30]`. A refound-subsidised house could hold that premium for ever, which is why refounds are capped (§4.5) |

Sustainable volume per (port, good) is then `0.15 × (target − floor)` per game-day: ~6 % of
target per game-day at patience 0.30, ~2.6 % at 0.10. That is the number the steady-state trim in
§3.2 is measuring against the wages.

**D3 (from TRADE_ROUTES §11), built here:** `cmd.do_sell` is re-cut (one hunk) so that
`SELL <good> ALL` sells what the day's allowance takes instead of refusing the whole parcel
(`E_DAILY_CAP`, live do_sell lines 38-41); an EXPLICIT quantity over the allowance still refuses
whole, byte-identically. It is the mirror of what `BUY ALL` already does, it is on the
TRADE_ROUTES plan as the owner's own default ("Yes, in slice 2"), and without it a merchant's
unsold parcel would ride every lap until a game-day boundary.

### 4.4 Supplies, repair and crew, so a merchant does not stall by itself

- **Supplies:** a provision preset per fleet (0034), applied through the core, with
  `days = ceil(1.5 × longest leg's sea-days)`; the route renders `PROVISION DAYS n` after its
  sales when the keep level is not met (0092:396 step 2). The build step checks the stores fit the
  hold with room to trade.
- **Repair:** `repair` true at stop 0 (skipped when nothing needs repair — D1, 0092).
- **Crew after a raid:** `voyage.settle` takes crew on DRIVEN_OFF / PLUNDERED / STRIPPED
  (0027:364-370), after which SAIL refuses `E_CREW_SHORT` and the queue halts. 0096 adds **one stop
  option for every route, `standing_route_stops.crew_up boolean default false`**, and **factors the
  tail of `cmd.standing_route_lines` (HIRE n when `crew_up` and `public.fleet_crew_shortfall(fleet)`
  > 0, then `SAIL TO next`) into one function, `cmd.standing_route_tail(p_route, p_stop, p_fleet)`,
  called from BOTH the full render and the sail-on branch (0092:626-636, which today hand-writes
  `SAIL TO cur` and could never render a HIRE — so a crew-short merchant would be cleared and
  re-failed every hour for ever).** One renderer, no hand-written SAIL text. `fleet_crew_shortfall`
  is a new one-line reading, Σ `max(0, crew_required − crew)` over the fleet's hulls; the Inn's
  served HIRE ceiling owed by OWNER_REQUESTS row 16 is its named second caller. HIRE is an existing
  queue verb (`do_hire`: draws the port's `crew_pool` at `hire_crew_rate`, refuses `E_CREW_POOL`
  on an empty quay — D1 then skips it and the SAIL halts until the next hour's tend, which counts
  the clear, §4.5). Players get the same option; the editor carries the flag through untouched
  (as it does `repair`) until it gains the checkbox.

### 4.5 When a route stalls anyway: `npc_tend`, hourly, inside `tick_reconcile`

`tick_reconcile` (0010:133) is re-cut to run, in order: `npc_tend(now)`, `npc_plan(now)`,
`npc_compact(now)` — each in its own `begin … exception` block, each route in its own
subtransaction, fleet locked before route — and THEN its existing invariant asserts, unchanged, so
they judge the world after upkeep. 0010's header claim "reads only" is superseded; 0097's header
and the function's comment say so. An hour (≈ 1.25 game-days) is fast enough for a self-heal: the
minute-level liveness (arrivals, the pacing wake) is already the arrivals job's.

**Upkeep never waits.** Row locks taken inside a savepoint survive `release savepoint`, so a
reconcile that locked 35 fleets would hold them until it commits, `voyage.settle` takes `fleets …
for update` without `skip locked` (0007:916), and a cycle between the minute tick and the hour tick
is a genuine deadlock in which the arrivals job may be the victim. So `npc_tend` and `npc_plan`
lock with **`for update nowait`** (fleet first, then route) inside each route's subtransaction,
treat `55P03` as "skip this route this hour" (counted, reported in the receipt), and `tick_reconcile`
sets `set local lock_timeout = '2s'` at the top of upkeep. Proven where it can be: PGlite is
single-connection and cannot hold a lock from another backend, so the `nowait` skip is proven in
CI's disposable Supabase from a second connection (proof 12), and 0097's self-assert proves only
the shape (the literal `nowait` in both bodies). Stated in §13, not papered over.

`npc_tend` may only:

| Condition | Action (through existing authorities only) |
|---|---|
| switch OFF | `standing_route_pause_for(…, true, 'dark')` on every merchant route not already dark. Fleets at sea finish their leg (the arrivals job settles them) and sit docked |
| switch ON, route unassigned, within `npc_fleet_max` in roster order | `standing_route_assign_for` (requires DOCKED at a stop + a preset; ends in `cmd.advance`) |
| switch ON, paused `dark` / `losing` / `reserve` / `laid_up` / `edited` | `npc_plan` first, then `standing_route_pause_for(…, false)` (resume → advance). `laid_up` resumes only after `npc_laid_up_hours` (6) |
| paused `off_route` | `standing_route_assign_for` at the port the fleet is in, if it is a stop; otherwise leave it and report (a merchant is never sailed by hand, so this is a bug report) |
| paused `error` | `npc_plan` SKIPS it (it would otherwise bump `updated_at` every hour through the save door, 0092:926-929, and the rule below could never fire); resume only if `updated_at < now − 6 h`, which now dates the pause; reported once. Self-asserted: pause a probe route `error`, run `npc_plan`, `updated_at` unchanged and still paused; warp 7 h, run `npc_tend`, resumed once |
| a `failed` order at the head of the queue (the halt law) | `cmd.clear_for(p_player, fleet, false)` then `cmd.advance(fleet, now)` — the same release the arrivals job gives a repaired fleet. **Counted:** the third consecutive clear of one route (no lap closed between; counted from the retained ROUTE_PAUSED/cleared events, no new column) pauses it `laid_up` with the failed order's code in the pause sentence, so a merchant that cannot crew or cannot sail stops burning the tick and the card says why |
| purse < `npc_houses.capital × npc_purse_floor_pct` (0.20), no refound in the last `npc_refound_cooldown_game_days` (30 = one real day), and fewer than `npc_refound_max_per_week` (3) refounds in the last 7 real days | `public.credit(house, 'NPC_REFOUND', capital − purse, emit_event(house, 'NPC_REFOUNDED', …))`: the company's backers put it back on its feet. Fortunes fall, visibly (the card prints the refound count and the last refound time), and nobody is cheated: merchants are off Rank and their money never reaches a player. **At the cap** the house is paused `laid_up` visibly, and its route is re-cut through `standing_route_save_for` to `npc_houses.alt_loop` (the second-best measured loop, baked by the build step) — the same door, the same courses authority — before the next resume. A house refounded three times in a week is a route the market has stopped paying; it changes route, it is not subsidised for ever (the price premium a subsidised merchant holds, §4.3, is what players would otherwise pay) |
| fleet ADRIFT or UNABLE_TO_SAIL | pause `laid_up`. There is no RECALL or salvage verb in the chain, for players either (0093 header, `blocked`); a merchant adrift stays adrift, drawn as a hull going nowhere, until that verb exists. The 1.5× keep level and the hazard clamp (`hazard_p_max` 0.06, 0001:171) make it rare; slice 6 counts it |
| merchant fleets beyond `npc_fleet_max` | stay paused `dark`, in roster order; population is lowered live without a migration |

`npc_tend` and `npc_plan` never write `orders`, `voyages`, `port_goods`, `ships` or `ledger`
(§1.7 guard). `paused_reason`'s check (0092:156) gains `'dark'` and `'laid_up'` — a CHECK
drop/re-add on a live table, instant on ~30 rows, named in 0096's list; `src/domain/route`'s
reason words (`index.ts:96`) gain the two (players never see them on their own routes, but the
word table is one).

---

## 5. The DB growth budget (Free plan 500 MB; production ≈ 113 MB after the 2026-10-01 reindex)

### 5.1 Rows per merchant, derived from the machinery (estimates until slice 6 measures)

Per fleet AT SEA, `voyage.settle` writes one `ledger` WAGES row and one `voyage_events` row per
sea-day, i.e. 2 rows per 9 s = **800 rows per hour at sea**. Per lap it adds a DEPARTED event per
leg, a VOYAGE_REPORT per leg (whose payload embeds every day line — ~15 KB for a 95-day leg), a
BOUGHT/SOLD event + ledger row per filled line, a ROUTE_LAP, a `voyages` row per leg (with the
course polyline), and `trade_daily` upserts. With the measured lap times (§3.2) and interval pacing
at 6 laps per game-day, the eight ocean fleets are at sea nearly always (laps of 13-34 min against
an 8-min interval) and the 27 regional fleets 15-40 % of the time (laps of 1-7 min), so about
**14 fleet-equivalents at sea ≈ 11,000-13,000 rows per hour, ~300,000 per real day**, roughly
40-60 MB/day with indexes. Unbounded, that fills the Free plan in a week: retention is not
optional. (The first draft's 4,500 rows/hour assumed burst pacing at 4 laps per calendar day with
merchants docked ~85 % of the time — the picture §3.3 rejects.)

The 2026-10-08 PGlite apply reads 194 MB total for the world itself (132,090 `port_goods` rows,
the sea raster); production's 113 MB is the same world on a different store.

### 5.2 Retention: `npc_compact(now)`, hourly, merchant rows only

Players' books stay append-only for ever. For merchant companies, every hour:

1. **`voyages`** of merchant fleets with `status <> 'SAILING'`, `eta < now − npc_retention_hours`
   (**6**) and not referenced by the fleet's OPEN lap (the lap closer reads `voyage_events.wages`
   for the lap's SAIL orders, 0092:536-541): delete; `voyage_events` cascades (0006:90). Nothing
   else references `voyages` (the audit found only `voyage_events`; asserted by `pg_constraint`).
2. **`ledger`** rows of a merchant older than the window collapse into ONE row per company, kind
   `NPC_CARRIED`: `ducats_delta = Σ` of the collapsed rows (the previous carried row included),
   `balance_after` = the newest collapsed row's, `created_at` = that row's, `ref_event_id` NULL.
   This is the one place a ledger row is written other than `public.credit`, and the function's
   header says so; `assert_ledger_reconciles(house)` runs inside `npc_compact` right after, so a
   wrong roll-up raises and rolls back.
3. **`events`** of a merchant older than the window, not referenced by a remaining ledger row and
   not of a KEPT kind (`FOUNDED`, `NPC_REFOUNDED`, `SIGNED_OFFICER`, the skill event): delete.
4. **`trade_daily`** merchant rows with `game_day < world.game_day()`: delete (the cap reads
   today only).
5. **`orders`** of merchant fleets in `done`/`skipped` older than the window: delete (the lap
   closer already prunes all but the newest lap's; this is the safety).

**How the append-only trigger lets it through.** `public.forbid_mutation` (0004:144) is re-cut
to allow DELETE only when BOTH hold: `current_setting('byeharu.npc_compact', true) = 'on'`
(set transaction-locally by `npc_compact` alone) AND the row's `player_id` is a merchant. Clients
hold no DELETE grant on either table (the 0001 lockdown), so the GUC alone opens nothing, and the
second condition means even the compactor cannot touch a player's row. Asserted both ways: with
the GUC on, deleting a player's ledger row still raises; without it, deleting a merchant row raises.

**Steady state:** about 6 h of rows ≈ 70,000-80,000, roughly **20-30 MB**, plus 26 carried rows
and ≤ 200 laps per route. Churn ≈ 12,000 deletes per hour across the big tables. 0097 sets
`autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 2000` on `ledger`, `events`,
`voyage_events`, `voyages` and `trade_daily` (the 0095 shape: the sweep follows the hourly delete
at any table size), because delete churn without VACUUM is exactly what grew `price_history_pkey`
to 738 MB (0095 header). Slice 6 reads each index after the soak and the deploy re-reads them a
day after the switch; a threshold retune is its own small migration.

**Budget gate:** knob `npc_row_budget` (100,000). Proof 12 counts merchant rows across the five
tables after its soak and fails above it; slice 6 re-measures rows per hour under the final pacing
and, if over budget, lowers `npc_fleet_max` before touching the pace. DEV_LOG records the number
before the switch.

### 5.3 Clock cost

At 35 fleets, the arrivals job gains roughly 14 fleets' worth of per-minute settling and about one
merchant arrival (trades + departure) every 20-30 s, inside its one transaction (0010:54); upkeep
never makes it wait (§4.5). Per-fleet subtransactions in `tick_arrivals` itself remain
TRADE_ROUTES' slice-2 item and are not built here. The planner costs ~125 `trade_routes` calls
(12 ms each, measured) plus ~750 sizing quotes (0.66 ms each) ≈ 2 s once an hour. The read side's
cost is `voyage.position` per merchant at sea per beat (§7.2): it walks the voyage's path jsonb
element by element (0047:504) and could not be timed on the applied chain (it carries no voyage),
so **slice 6 `explain analyze`s `world.sea_traffic()` with the roster at sea and records ms/call in
DEV_LOG before the switch; above ~5 ms the served jsonb is memoised once per 3-s slot in a one-row
table inside `sea_traffic` itself** (keyed by `floor(epoch / 3)`; the function's own output, not a
second position authority) and the header says so.

---

## 6. Exclusion from Rank and from everything player-only

| Player-only thing | Rule |
|---|---|
| Rank: `settle_standings` (0025:217, loop :247) | re-cut with `where not p.is_npc`. `world.standings` reads only the photographed table, so this is the single authority, and the "of N houses" count follows. It also keeps `player_progress`'s whole-ledger scans (0069:119) off merchant histories. Asserted with a positive control: a probe merchant whose `player_fame` exceeds a probe player's is founded, `settle_standings` runs, the player is on the board and the merchant is not |
| `tick_reconcile`'s purse invariant | **merchants stay in it**: Σ ledger = ducats must hold for them too (and the carried row is how it does) |
| Requests (0087), bargains, storage, workshops, build yards, investment | client doors only, unreachable with `auth_uid` NULL |
| Danger (storms, calms, pirates, STRIPPED) | **merchants face it** as players do — same `voyage.settle`. A simulator with charmed ships is a diorama |
| The daily cap, price impact, spread, tax, wages, port fees | identical, by construction: the same executor |
| MARKET's presence line (DESIGN §J.3 "4 large purchases") | not built in the chain today (no such read); when it is, merchant trades count, which is the point |

0097's header lists every live function that reads `public.players` without a key (the dump
finds `tick_reconcile` 0010:144 and `settle_standings` 0025:247; the rest are probe cleanups and
RLS), classified *filter* / *keep*, so the next reader added is a visible decision.

---

## 7. The reads (migration 0099)

### 7.1 `world.voyage_view(p_voyage uuid, p_full boolean)` — sliced out of `world.fleets`

The `'voyage', (select jsonb_build_object(…))` sub-select in `world.fleets`'s live body (keys
`id`, `to`, `dest_point`, `course` = `voyage.course_of(v.path)`, `eta`, `total_nm`, `waters`,
`departed_at`, `position` = `voyage.position(v.id)` + `seg_nm`) moves into this function;
`world.fleets` is re-cut to call it with `p_full = true` and its output on a probe fleet at sea is
asserted byte-identical before and after. With `p_full = false` it serves `course` as the CURRENT
SEGMENT ONLY (`course[seg_index]`, `course[seg_index+1]`, with `seg_index` re-based to 0),
`waters` empty, **and no `id` key** (`voyage.position` is executable by `authenticated`,
0088:184, so a served voyage id would be a callable handle; the client never uses it): exactly what
`driftedPoint` needs to move a hull between reads, and about 200 bytes instead of a 300-point
polyline per fleet on every beat. Both outcomes are true readings (§7C).

### 7.2 `world.sea_traffic()` — on the beat, while a screen wants it

- **Shape:** `{ enabled: bool, at: timestamptz, fleets: [ { id, company, nation_code, name,
  status, ships: int, port: code | null, roadstead: [lat, lon] | null, anchor: [lat, lon] | null,
  voyage: voyage_view(false) | null, next_lap_at: timestamptz | null } ] }`. A docked merchant
  carries its port's served roadstead point (`sea_reaches.roadstead_lat/lon`) so the chart can
  draw it at anchor (§8.2); `next_lap_at` is the route's `hold_until`.
- **It does not settle.** The arrivals job settles merchants every minute; `voyage.position` is
  closed-form, so between ticks a hull still moves correctly, and past its ETA it sits at its
  destination for at most a minute. A viewer-side settle was rejected on numbers: a sea-day ends
  every 9 s, so EVERY beat of EVERY viewer would find every merchant due and re-run
  `voyage.settle` + the arrival trades under row locks — 20× the clock's load and 20× the
  deadlock exposure. (`world.market` does call `tick_market_drift`, live body — but that tick is
  keyed on a 15-minute slot and is a no-op almost every call; arrivals are not.)
- **Cost, stated:** the beat is 3 s (§2), ~30 viewers ≈ 10 calls/s, each evaluating
  `voyage.position` for every merchant at sea (~14). Measured in slice 6 before the switch;
  memoised per 3-s slot above ~5 ms (§5.3). A planner-cost self-assert in 0099 requires one index
  scan on `fleets` by `players.is_npc` and no per-row subquery beyond `voyage.position`.
- `security definer`, `grant execute … to authenticated` only, registered in
  `client_rpc_entry_points()`. When `npc_traders_on()` is false it returns
  `{enabled:false, fleets:[]}`. Filter: `join players p on p.id = f.player_id and p.is_npc` — the
  only predicate. Dark routes' fleets are served docked (PORT may list them); nothing of a player's
  is ever a row.
- **Self-asserts:** the key set equals the allow-list exactly; with a probe PLAYER's fleet SAILING
  no row belongs to a non-merchant; switch off → empty; no `version`, `queue`, `cargo`,
  `cargo_basis`, purse, ledger or voyage `id` key anywhere in the tree.

### 7.3 `world.npc_fleet_card(p_fleet uuid)` — at tap time

- **Refuses `E_NOT_FOUND`** for any fleet whose company is not a merchant, and while the switch is
  off. The privacy rests on that one `is_npc` filter and on the executor chain never being
  reachable through the card — not on `voyage.position` being unreachable (it is executable by
  `authenticated`). A player's fleet id reveals nothing, not even that it exists.
- **Serves:** `company { name, nation_code, blurb, master, fortune (ducats), refounded (count of
  NPC_REFOUNDED events, a kept kind), refounded_at (the last) }`; `fleet { name, status, port,
  roadstead, anchor, voyage: voyage_view(true) }` — the FULL course for the tapped fleet only, so
  the chart can draw its leg while it is selected (§8.2); `route { stops: [codes], lap_no, state
  (the 0092 derived word: sailing / in_port / waiting / paused / stopped), next_lap_at,
  paused_reason, last_skipped: [{port, line, code}] }`; `earnings` (§7.4); `ships: [ { name,
  class, is_flagship, durability, max_durability, crew, crew_required, crew_max, hold, hold_rated,
  speed, speed_rated, cargo: {code: units}, cargo_tuns, fittings: [{name, qty}] } ]` — the fields
  `ShipTile` and `FleetCargo` print, computed by the same derivations (`world.ship_stat`,
  `ship_hold_capacity`, `voyage.ship_speed`); the definer serves fittings because
  `ship_fittings_read` (0074:219) checks `auth.uid()`; `officers: [ { name, specialty, bonus_pct,
  nation, home_port } ]` from `player_officers ⋈ officers` where `fleet_id` = this fleet;
  `skills: [ { code, name, level, max } ]` from `player_skills ⋈ skills` for the company.
- **Never serves:** `queue`, `orders`, `cargo_basis`, `version`, `reserve`, `provision` figures,
  ledger lines. Key set self-asserted (the 0025 discipline). Fortune IS served: a merchant has no
  privacy, and a rising and falling fortune is what the owner asked to watch.

### 7.4 Earnings: `public.route_earnings(p_route)` — the window, and why

Returns `{ day: Σ net of laps closed in the last 24 real hours, day_laps: n, day_since: the
oldest such lap's closed_at, lap: avg net of the last 7 closed laps (null until TWO have closed),
lap_basis: how many laps that average stands on, laps_recent: [net × ≤ 7, newest first],
laps_done: lap_no }`, all from `standing_route_laps` (sold, bought, supplies, repairs, wages, net,
closed_at; 0092:196).

- **WHY `lap` NEEDS TWO CLOSED LAPS — the lap boundary, found 2026-10-08 and corrected 2026-10-10.**
  A lap closes on arrival at the home stop (0092's one closer) BEFORE that stop's own SELL lines
  run, so the cargo a leg buys on lap N is sold on lap N+1. Lap 1 is therefore a purchase with no
  sale and is a large loss by construction — the committed screenshot of Carreira do Brasil read
  `So far today −116,690 🪙 / A lap ≈ −116,690 🪙` for a lap whose cargo fetched +139,165 on the
  next one — laps 2..N each hold one sale and one purchase and are the honest figure, and the open
  leg's cargo is in no lap at all. One closed lap can say what that lap's books did; it cannot say
  what a lap EARNS. So `lap` is null below two laps and the sheet prints `first lap under way`,
  and the day row is labelled by its real window (`So far · since 13:05`) rather than "today".
  **Moving the boundary itself** — closing a lap after the home sale, or attributing a leg's
  purchase to the lap that sells it — would change what every PLAYER's route history means, on a
  deployed feature ~30 players already use, so it is NOT done here: it is a decision for the owner
  and a slice of its own (`docs/OWNER_REQUESTS.md` row 110).

- **A real day, because that is the day the player lives in.** Thirty game-days pass in it
  (`game_day_seconds` 2880), History shows real clock times, and a player compares a merchant
  with their own yesterday. `standing_route_lap_keep` = 30 (0092:138) covers 24 h at the pacing
  cap of 1 lap per game-day; regional merchants at up to 6 laps per game-day are kept to 30 laps =
  4 h, so 0097 raises `standing_route_lap_keep` to **200** (bounded; a route's laps are ~150 B
  each). The card prints `≈ 37,200 🪙 a day` once `day_since` is 24 h old and `12,400 🪙 so far
  today` before that — a truthful lesser answer, never an extrapolation.
- **Per lap as well,** averaged over 7 so one raided lap does not swing it, **and the last seven
  laps themselves** (`+1,240 · +980 · −18 · …`) so a route in decline shows its decline instead of
  hiding it behind a 24-h sum.
- **Laps, not ledger.** Lap figures are per fleet; the ledger is per company, has no `fleet_id`,
  and is compacted. `NPC_REFOUND` is not a lap figure, so it never inflates earnings; wages are the
  OWED figure (0092:536), so a floored purse never flatters it.

---

## 8. The client

### 8.1 Data path: one reader, one beat, read only while a screen wants it

- `src/lib/rpc/catalog.ts` gains `worldSeaTraffic` (`world.sea_traffic`) and `worldNpcFleetCard`
  (`world.npc_fleet_card`, `p_fleet uuid`); typed wrappers in `src/lib/rpc/index.ts`; types
  `SeaTraffic`, `TrafficFleet`, `MerchantCard` in `src/lib/rpc/types.ts`.
- `src/live/worldStore.ts`: state field `traffic: SeaTraffic | null` and a counter
  `trafficWanted: number` (MAP and PORT increment it on mount and decrement on unmount, the one
  seam a screen has into the cadence); `refresh()` reads `worldSeaTraffic()` **sequentially after
  `readRoutes()`, and only while `trafficWanted > 0`** (the deadlock order is kept even though
  this read takes no locks, so the rule stays one rule; the beat is 3 s, `AppShell.tsx:33-42`, and
  a viewer on LEDGER should not pay for merchants it cannot see). A failed traffic read keeps the
  last traffic and nulls nothing fatal (a map without merchants is a map). It is the one reader;
  `flicker.spec.ts` gains the one-reader guard (`worldSeaTraffic(` only in the store). **No new
  poller**: `AppShell`'s beat is the only cadence.
- `src/live/useMerchantCard.ts`: a one-line doorway onto `useServedRead` for the card, keyed by
  fleet id, re-read on `readAt` (keeps the last answer, so the card never flickers).

### 8.2 Drawing: the same model, the same layer, the same glyph

- `src/chart/liveWorld.ts`: factor `mapFleetsOf`'s per-fleet body into `mapFleetOf(row)`; add
  `mapTrafficOf(traffic, selectedCard) → MapTraffic[]` (`MapFleet & { company, nationCode,
  docked: boolean }`) composing it. Position is copied, never computed; a 2-point `course`
  satisfies `course.length >= 2`; a docked merchant is an `anchored`-kind fleet at its served
  roadstead point. When the tapped fleet's card is in hand, its row carries the card's FULL course
  instead of the 2-point one — the only row that ever does.
- `src/chart/chartModel.ts`: factor the sailing branch (:182-219: `driftedPoint` + `buildTrack` +
  `headingDeg`) into one internal `placeSailing(fleet, drift)` used for own fleets and traffic
  alike; add the **optional** last parameter `traffic: readonly MapTraffic[] = []`
  (`buildChartModel.length` stays 2, `tests/map.voyage.spec.ts:106`); return
  `model.traffic: TrafficOnChart[]`, which never feeds `portRoles`, `destinationPoints`,
  `focusPoints`, `motionPoints`, labels or `model.fleets`. A traffic row's `track` is null unless
  its course has more than two points (the selected merchant), and its `heading` comes from the
  two served points.
- `src/chart/FleetsLayer.tsx`: `FleetsLayer` gains one more `map` over `model.traffic` with **the
  same `shipPath` at the same `GLYPH.shipHalfLength`** (13 px: 0.7 × that would be the 8.8 px dot
  `glyphs.ts:82-87` retired because it did not read as a hull), the hull filled with the company's
  NATION ink and **no halo** (the own fleet keeps its 16 px sea halo and the accent, which is how
  "yours" stays loud), `data-testid="map-merchant"`. **Docked merchants are drawn**, at the port's
  served roadstead point, pointing north (a ship at anchor needs no legend, MAP_ATMOSPHERE §4;
  own docked fleets stay the port's loud mark). `TracksLayer` (same file, :30) draws a traffic
  row's track when it has one — the selected merchant's current leg, faint, through the existing
  `buildTrack` paths — and nothing for the rest. No label (label plans and their pinned counts are
  unchanged). The header at :21-24 is amended: *"Other PLAYERS are never drawn (DESIGN Q7).
  Merchant companies are the owner's 2026-10-08 exception and arrive only through
  `model.traffic`."* `mapTypes.ts`'s header gets the same amendment.
- `src/index.css`: **eight nation inks** `--color-nation-prt/esp/nld/eng/han/ita/ott/east` for
  dark and light (ITA covers GEN and VEN; EAST the Ming, Japanese, Joseon and Siamese houses; the
  Mughal and Persian houses take OTT's family; FRA and DNK take ENG's) — no raw palette literal in a
  component (`duplication.spec.ts:84`), each measured against `chart-sea` and `chart-land` for
  contrast in both schemes (the `chart.ink.spec.ts` method). Ink by nation carries meaning a player
  can learn from the map (Portuguese hulls look Portuguese); the sheet names the company.
- `src/chart/hitTest.ts`: scan `model.traffic` after own fleets with the same reach; own fleets win
  ties. New `MapSelection` arm `{ kind: 'merchant', id }` (`mapTypes.ts:166-171`) and the
  `toggleSelection` arm. `src/chart/index.ts` exports `mapTrafficOf` and the types (the one
  entrance, `sections.spec.ts`).

### 8.3 The read-only fleet sheet: reuse, never copy

Screens may not import each other (`tests/sections.spec.ts`), so what MAP and PORT both show moves
to a shared layer first — **with pure props**: `src/components` may import nothing from `domain`,
`live` or `chart` (`sections.spec.ts:150`, "machinery knows nothing above it"), and today
`ShipTile` calls `hullFraction` / `shipHoldUsed` from `src/domain/fleet` (`FleetShips.tsx:4,
:31-32`) and `FleetCargo` reads `useWorld` (`FleetCargo.tsx:28`). Those computations stay with
the callers; the tiles print numbers they are handed.

| Today (inline, feature-owned) | Moves to | Props | Then composed by |
|---|---|---|---|
| `ShipTile` in `src/features/fleets/FleetShips.tsx:30-65` | `src/components/ui/ShipTile.tsx` | `{ name, className, flagship, hullPct, crew, crewRequired, speedKn, holdUsed, holdTotal }` | `FleetShips` (computes `hullPct`, `holdUsed` via `domain/fleet`), `MerchantSheet` (served) |
| the cargo rows of `src/features/fleets/FleetCargo.tsx:27-57` | `src/components/ui/CargoRows.tsx` | `{ rows: {code, name, icon, qty}[], totalTons }` | `FleetCargo` (resolves names through `useWorld`), `MerchantSheet` (served names) |
| the officer tile of `src/features/compendium/CaptainsFace.tsx:63-84` | `src/components/ui/OfficerTile.tsx` | `{ name, specialty, bonusPct, homePort, signed, takesEffect }` — home port is new on both callers (the catalogue has it, 0015:63) | `CaptainsFace`, `MerchantSheet` |
| the skill tile + level bar of `src/features/port/PortAcademy.tsx:69-92` | `src/components/ui/SkillTile.tsx` | `{ code, name, level, max }` | `PortAcademy`, `MerchantSheet` |

**`src/live/MerchantSheet.tsx`** is the card: a `Tray` (`src/components/ui/Tray.tsx:69`) spread
with `{...CHART_CHROME}` (`src/chart/useChartSurface.ts:86`) so labels keep clear of it, titled
by a `MapTrayTitle`-shaped row:

- **peek:** *Carreira da Índia · Casa da Índia* / *to Kochi · 11 min* (the `fleetLine` wording,
  `src/features/map/fleetLine.ts`; a docked merchant reads *Lisbon · sails at 14:32*, the docked
  form plus `next_lap_at`)
- **half:** `Figure` *≈ 37,200 🪙 a day*, `Row` *≈ 1,240 🪙 a lap*, `Row` *Last laps +1,240 ·
  +980 · −18 · …* (the seven served nets), `Row` *212 laps · Lisbon → Cape Town → Kochi → Old Goa
  → Mozambique*, `Row` *Fortune 148,000 🪙* (+ *refounded twice, last 09:40* when so), and the
  one-line blurb with the master's name
- **full:** *Ships* (`ShipTile` × n, flagship marked), *Cargo* (`CargoRows`), *Officers*
  (`OfficerTile` × n), *Skills* (`SkillTile` × 4 — the company's four levels, the word WORDS.md
  settles in §8.6), and *Last lap* with the skipped lines in words (*quicksilver too dear at
  Lisbon*).

**No `Button`, no `Stepper`, no Command hand-off, no `selectFleet`.** Asserted by the spec. The
map stays an output device (DESIGN E.5): the only action is closing the tray.

- `src/features/map/MapScreen.tsx`: pass `useWorld(s => s.traffic)` (and the selected card)
  through `mapTrafficOf` into `buildChartModel` (:111-115); in `onTap` (:131-149) a `merchant`
  hit sets the selection and does NOT call `selectFleet` (:140); the trays (:246-263) render
  `MerchantSheet` for it; MAP bumps `trafficWanted` on mount.

### 8.4 PORT: merchants in port. Decided: yes, as a section, never in `trailing`

`src/features/port/PortScreen.tsx` gains `SheetSection heading="Merchants in port"` (the
`Anchored here` pattern at :128-136) listing the traffic rows docked at this harbour, one `Row`
each (*Hanse zu Lübeck · Bergenfahrer* / *sails for Bergen at 14:32*), tap → `MerchantSheet`.
It reads the same `traffic` field — no new read — bumps `trafficWanted` on mount, and is hidden
when empty. It is never in the `trailing` slot (:153-163), which is "about YOU". DESIGN §J.3's
"count only" was written about PLAYERS; merchants are named, because they are the world's
furniture, not somebody's position.

### 8.5 Local mode (PGlite in the tab, no pg_cron) and the rescue

Locally nothing moves a merchant between reads, so `src/lib/rpc/localBackend.ts` runs
`select public.tick_arrivals(now())` in the same `callAs` transaction immediately before every
`world.sea_traffic` invocation. It is the local backend playing pg_cron's part (the same function
the job calls, a different driver), stated in the backend's header; the cloud backend does
nothing of the kind, because the job does. Both outcomes are acceptable (§7C): a local world where
merchants freeze at their ETA would not be. (`localDb.callAs` runs as PGlite's superuser, so the
revoked tick is callable there; `tests/rpc.surface.spec.ts` asserts it stays revoked from
`authenticated`.)

**The rescue skips the seed.** `rescuePlayerRows` (`src/lib/db/rescue.ts:47-55, :122`) dumps
`players, fleets, ships, voyages, voyage_events, orders, events, ledger` unfiltered into one
~2 MB localStorage slot; after 0098 the shipped world image carries 26 merchant companies and their
rows, so every rescue would grow by the seed, overflow the slot and silently drop the player's own
rows. It filters `players` to `not is_npc` and every child table by those player ids; the comment
at `build-image.mjs:125` and `tests/db.image.spec.ts` state that the seed companies are world
data; a unit case proves a rescue over the seeded image stores only the local captain's rows.

### 8.6 Words (`docs/WORDS.md` rows; `tests/words.spec.ts` bans)

| Concept | Say | Never |
|---|---|---|
| a trading company the world keeps | **merchant** / **merchant company** (`Merchants in port`) | NPC, bot, AI trader, house |
| its fleet on the map | the fleet's own name, with the company under it | NPC ship |
| what it makes | **≈ 37,200 🪙 a day** · **≈ 1,240 🪙 a lap** · **so far today** before 24 h · **Last laps** | earnings/day, per game-day, income |
| its money | **Fortune** | purse, treasury |
| a merchant put back on its feet | **refounded** | bailed out, reset |
| a merchant that cannot sail on | **laid up** | stranded, dead |
| the company's four levels (Academy and the sheet) | **Skills** — PortAcademy's *"Pick a fleet to train its captain."* (:65) becomes *"Pick a fleet docked at an academy to study."* | Captain (for a set of bars) |
| the person in charge of a fleet | **captain** = the player, for their own fleets; a merchant fleet's named **master**, flavour only | — |

---

## 9. Dark first, and the one switch

- **0097** inserts into `public.world_config`: `npc_traders_enabled` **false**,
  `npc_fleet_max` 40, `npc_laps_per_game_day` 6, `npc_lines_per_stop` 3, `npc_min_return_pct` 2,
  `npc_sell_margin` 0.05, `npc_min_net_to_wages` 0.2, `npc_price_patience_max` 0.30,
  `npc_purse_floor_pct` 0.20, `npc_refound_cooldown_game_days` 30, `npc_refound_max_per_week` 3,
  `npc_laid_up_hours` 6, `npc_retention_hours` 6, `npc_row_budget` 100000; and ONE reader
  `public.npc_traders_on()` = `wc('npc_traders_enabled') = 'true' and public.standing_routes_on()`
  in the 0092:291 shape. Every merchant path asks only this function. (An NPC loop needs routes
  on; they are, since 2026-10-01.)
- **Off:** routes are paused `dark` (`npc_tend`), both reads are empty, the client draws nothing
  and lists nothing. 0098 seeds companies and fleets docked at their stop 0 with routes saved and
  unassigned, so nothing sails between deploy and switch.
- **`public.npc_traders_switch(p_on boolean)`**, server-only, is THE switch: it writes the flag
  and calls `npc_tend(now())` at once, so merchants put to sea within the minute (the arrivals job
  takes them from there). `false` is the reverse, and is how an incident is stopped: one statement.
- **The owner's only decision:** `select public.npc_traders_switch(true);` in the SQL editor,
  after slice 6 has recorded in DEV_LOG the measured rows per lap, the retained rows after a
  3-game-day soak, the index sizes, the per-pair stock minima, `sea_traffic`'s ms/call, each
  company's steady-state net and the per-frame hull count.

---

## 10. Decided here (no open questions)

| # | Decision | Why |
|---|---|---|
| N1 | Merchant = `players.is_npc`, `auth_uid` NULL, check-enforced; flavour in `npc_houses`, never a predicate | one predicate; RLS and `current_player_id()` can never reach it |
| N2 | Doors sliced into server-only `p_player` cores; encounter gates stay in doors; money and rows in cores; the ship insert folded (two copies today); the save door gains `p_laps_per_game_day` and the repeated-harbour anchor fix | merchants pay what players pay through the same authorities; nothing is granted to a client; one writer per route column |
| N3 | 26 companies, 35 fleets as maxima; candidate loops authored, the loop CHOSEN by measured steady-state net; hulls trimmed to mean net(laps 3-6) ≥ 0.2 × wages with the whole roster running; draft, crew-pool and no-repeat rules asserted | the economy, not the author, sizes a convoy; a losing or unsailable merchant is never seeded silently |
| N4 | Stops and courses authored and baked; lines planned hourly by ONE planner from `world.trade_routes` (its only live caller; the player's door was removed by the owner in 0071 and stays removed), filtered by authored wares and one-buyer-per-(port, good), sized by the quote's own `p_limit` walk at the sink, kept by a per-leg wage test; planning order rotates hourly | deterministic where it must be; alive and market-reactive where it should be; no second ranking, no planner arithmetic; no house is structurally last |
| N5 | Market bound = a BUY ceiling anchored to the port's NORMAL ask × (1 + patience 0.10-0.30); the sink-sized parcel; SELL only above cost with a two-lap cut-loss | a provable stock floor; prices move a little, visibly, never ratchet, and no sink is flooded |
| N6 | D3 built: `SELL … ALL` takes the day's allowance | the TRADE_ROUTES owner default; a merchant's parcel must be able to leave |
| N7 | THE pacing hunk becomes an interval hold (`last start + game_day_seconds / v_per`), one rule for all; per-route `laps_per_game_day`; merchants at 6, oceans paced by their own length | the calendar hold put every route on earth on one clock; the interval de-synchronises them and keeps one rule; a small, stated change for players |
| N8 | `crew_up` stop option + `fleet_crew_shortfall` + one tail renderer for both refill branches; three consecutive clears → `laid_up` with the reason | the stall merchants hit most, built as a player feature too, and it cannot loop for ever |
| N9 | Upkeep (tend, plan, compact) inside `tick_reconcile`, asserts last, locks `nowait`, `lock_timeout` 2 s; the switch calls tend | no new cron, as ordered; self-heal within the hour; the minute tick never waits on the hour tick |
| N10 | Merchant-only retention: 6 h, one carried ledger row per company, kept kinds, autovacuum per table; budget 100 k rows | ~300 k rows/day unbounded would fill the Free plan in a week; the price_history lesson applied before the fact |
| N11 | Refound at most daily AND at most 3 a week, logged, printed on the card with its time; at the cap: laid up and re-cut to the alternate loop; adrift = laid up | fortunes fall and rise visibly; no silent faucet, and no permanent price premium paid by players |
| N12 | Earnings = Σ lap net over the last real day + the 7-lap average + the seven nets, served; lap keep raised to 200 | fleet-exact, honest about its window, decline visible, inside the keep |
| N13 | `sea_traffic` per beat while MAP/PORT is mounted, no settle, current segment only, no voyage id; the card at tap serves the full leg; cost measured before the switch, memoised per slot if > 5 ms | no viewer locks, ~200 B a fleet; the cron settles; a LEDGER viewer pays nothing |
| N14 | Full-size hull, nation ink, no halo, drawn at sea and at the roadstead when docked; the selected merchant's leg as a faint track; no label; a separate `model.traffic` | alive and legible at phone size; nothing player-only can see a merchant; colour means something |
| N15 | PORT lists merchants in port, never in `trailing` | the owner can tap a docked fleet too; the harbour is the world's, the trailing slot is yours |
| N16 | Local backend ticks arrivals before the traffic read; the rescue skips merchant rows | local play needs a clock; cloud has one; the seed is world data |
| N17 | Player word **merchant**, never NPC or house; the four levels are **Skills**; a merchant fleet has a named **master** | WORDS.md; what the owner called "captains" is answered honestly by officers, skills and a master |
| N18 | Blurbs and fleet names generated from the measured lines and asserted against them; the spice geography is the owner's HELD decision (DESIGN §J.3) | historical believability cannot be asserted on a re-rolled world; nothing is re-authored silently |
| N19 | Every text-scan self-assert carries a positive control that must be reported before the real scan must report nothing | a scanner that matches nothing is indistinguishable from a clean chain (NO_SPAGHETTI §4, 0023:81/:433) |
| N20 | The seed is guarded against production: `--taken` names, `nation_id` not null, distinct hull names, no repeated harbour, draft and crew-pool asserts | a raise inside 0098 would abort `db push` part-way and block every later migration |

---

## 11. Migrations, proofs and tests

Every migration self-asserts in the chain's usual block (`do $$ … $$`, `'<NNNN> self-assert FAIL: …'`,
the `self-assert ok` receipt), with probe rows rolled back by the 0092 `raise … 'P0920'` pattern,
and **every scan over `pg_get_functiondef` first proves it can see**: a `pg_temp` function carrying
the banned token is created, the scan must report exactly it, it is dropped, and only then must
the real scan over `cmd`, `world`, `public` and `voyage` report zero; the receipt prints the
positive-control hits. Every slice updates `docs/DEV_LOG.md`, `docs/OWNER_REQUESTS.md` rows
109-111, `supabase/migrations/CHAIN.md`, moves the `LAST` pin in `tests/db.chain.spec.ts:272`
with a dated comment, and runs `npm run refresh` in `tools/projectmap` if present. Before every
push: `npx tsc -b`, `npx eslint .`, `npm run build`, `npm run db:apply`, `npm run db:proof`, and
Playwright against `vite preview` on **localhost** (never 127.0.0.1) with an explicit port.

### 0096 — `a_fleet_is_formed_by_the_same_hands` (cores and parity; dark; no merchant exists yet)

- `new_house` generalised (unknown codes raise); `form_fleet`; `commission_ship` (re-cut
  `new_house`, `do_build`); `sign_officer` + `post_officer_to` (re-cut `hire_officer`,
  `post_officer`); `raise_skill` (re-cut `study_skill`); the `_for` cores + door re-cuts (preset
  save/apply; route save/assign/pause; clear), the save door with `p_laps_per_game_day` and the
  **repeated-harbour anchor fix** in save and assign; `standing_routes.laps_per_game_day` + **the
  interval pacing hunk**; `standing_route_stops.crew_up` + `fleet_crew_shortfall` +
  **`cmd.standing_route_tail`** called from both refill branches; D3 in `do_sell`;
  `paused_reason` gains `'dark'`, `'laid_up'` (CHECK re-cut); **the stale `world.trade_routes`
  row dropped from `client_rpc_entry_points()`**.
- **Self-asserts:** every door answers byte-identically on its existing scenario (uuids
  normalised) and moves the same ducats; every core refused to `anon`/`authenticated` and absent
  from both registries; every registry row executable by `authenticated` and every client writer
  registered; under a probe identity every door refuses another company's ids; the executor
  chain's live bodies contain no `auth.uid()` / `current_player_id()` (positive control first);
  pacing: a probe route at `v_per` 1 holds until one game-day after its last start and at 0 does
  not hold, and the 0092 six-tick scenario is re-stated for the interval form; a probe route that
  visits one harbour twice keeps its cursor at the second visit through a save and an assign;
  `crew_up` renders `HIRE n` only when short, in BOTH branches (the sail-on branch is driven by
  clearing a refused SAIL on a crew-short probe fleet); D3: `SELL x ALL` over the allowance sells
  the allowance, an explicit quantity still refuses whole; reconcile still raises on a falsified
  purse (0010:280's test).
- Also: `scripts/db/proofs/11_standing_route.sql` gains a `crew_up`, a repeated-port and a D3 case;
  `tests/rpc.surface.spec.ts` gains the two set asserts.

### 0097 — `a_company_the_world_keeps` (the merchant machinery; dark)

- Knobs + `npc_traders_on()`; `players.is_npc` + check; `npc_houses` (+ the is_npc trigger;
  columns `ink`, `blurb`, `master`, `home_port_id`, `capital`, `patience`, `wares text[]`,
  `alt_loop jsonb`); `npc_buy_ceiling`; `npc_plan`; `npc_tend`; `npc_compact`;
  `npc_traders_switch`; `route_earnings`; `settle_standings` re-cut; `forbid_mutation` re-cut;
  `tick_reconcile` re-cut (`lock_timeout`, upkeep first); `standing_route_lap_keep` → 200;
  autovacuum reloptions on the five tables.
- **Self-asserts:** the check rejects a merchant with a login; the ceiling equals quote ×
  (1 + patience) at target stock; a merchant BUY against a hand-set market stops above the stock
  floor; the sizing quote on a hand-set sink returns the units above the limit and the planner
  writes exactly that `q`; the wares filter keeps a listed good over a better unlisted one and
  falls back when nothing listed pays; two probe routes sharing a (port, good) are planned with
  one buyer, and the planning start index moves with the hour; the compactor cannot delete a
  player row even with the GUC on and cannot delete a merchant row without it; Σ ledger = ducats
  after a roll-up; `settle_standings` writes no merchant row (positive control: a famous probe
  merchant, a less famous probe player on the board); the live bodies of `npc_tend` and `npc_plan`
  contain no executor write and a `for update` only with `nowait`, and `npc_plan` contains no
  `world.mid_price` and exactly one `'sell'` quote with a limit; the live catalogue contains no
  `auth_uid is null` predicate (positive control first); a route paused `error` is left alone by
  `npc_plan` and resumed once by `npc_tend` after 7 warped hours; three consecutive clears pause
  `laid_up`; the fourth refound in a week is refused, the house laid up and its route re-cut to
  `alt_loop`; reconcile runs upkeep in order and still asserts; the switch flips and tends in one
  call.

### 0098 — `the_merchant_companies_are_founded` (generated; seed; dark)

- `data/npc-houses.json` (authored, §3.2: candidates, wares, masters, second spellings);
  `scripts/build-npc-0098.mjs` (applies 0001-0097 in PGlite with the proof-courses loader; plots
  every candidate leg with THE pathfinder from the served roadsteads; refuses a stop that is not a
  `HARBOUR`, a harbour repeated in one loop, a leg the pathfinder cannot plot, a draft the loop
  cannot take, a quay under 20 % of the crew, a founding frame with fewer than two crossing loops,
  and a name in `--taken`; founds EVERY house through `npc_found` in savepoints, warps six laps
  through `tick_arrivals` + hourly `tick_reconcile` with hazards off, judges each fleet on laps
  3-6, trims hulls largest first until mean net ≥ `npc_min_net_to_wages` × mean wages, chooses
  each fleet's loop by that net and bakes the runner-up as `alt_loop`, sizes `capital`, writes the
  blurb from the measured lines, prints every trim and choice, then rolls back and emits the
  migration with the roster and courses as one jsonb literal followed by `npc_found` calls);
  `data/npc-routes.generated.json` (checked in, reviewable, with the measurement table).
- `npc_found(spec)` composes, in order: `new_house(NULL, …, p_is_npc true, p_ducats = capital +
  wages + skill costs)` → `form_fleet` (second fleet) → `commission_ship` × n (crewed, distinct
  names) → `raise_skill` × levels → `sign_officer` × officers → `provision_preset_save_for` +
  `_apply_for` → `standing_route_save_for` (stops, courses, `crew_up`, `repair`,
  `laps_per_game_day`, NO lines) → `insert npc_houses`. **It does not assign the route**
  (assigning calls `cmd.advance`); `npc_tend` assigns when the switch is on. Twelve lesser
  officers are inserted as world data in the 0073 shape.
- **Self-asserts (structural only — nothing here may fail on market luck in production, §7C):**
  26 companies, 35 fleets, caps hold; each purse = capital and Σ ledger = ducats; every course
  passes `voyage.path_refusal` as `do_sail` calls it; every stop is a `HARBOUR`; `max(draft)` ≤
  `min(max_draft)` per fleet (positive control: a 3-nau probe at Seville is refused); every
  stop's `crew_pool` ≥ 20 % of the fleet's crew; no harbour repeated; `nation_id` not null for
  every merchant; hull names distinct per company; every blurb's goods are in the baked first-lap
  lines; no route assigned and every fleet DOCKED at its stop 0; name fallbacks printed, never
  silent; `npc_found`'s live body contains no `insert into public.` but `npc_houses`.

### 0099 — `the_sea_shows_who_else_sails` (the reads; dark)

- `world.voyage_view` sliced out of `world.fleets` (re-cut, parity byte-identical; `p_full =
  false` omits `id`); `world.sea_traffic` (roadstead point for docked rows); `world.npc_fleet_card`
  (full voyage for the tapped fleet, `laps_recent`, `master`, `refounded_at`, officers' home
  ports); `client_rpc_entry_points` re-cut (two rows after 0092's last).
- **Self-asserts:** `world.fleets` unchanged for a probe fleet at sea; exact key sets; no
  non-merchant row with a player sailing; the card refuses a player fleet and a random uuid alike;
  both reads empty while off; `voyage_view(false)` serves a 2-point course whose first point is
  the served position's segment start and no `id`; `explain` of `sea_traffic` shows one index scan
  on `fleets` and no per-row subquery beyond `voyage.position`.
- `tests/rpc.surface.spec.ts`: the two entry points and the eight cores' absence.

### Proof 12 — `scripts/db/proofs/12_merchant_companies.sql` (PGlite, hand-driven clock; the lock case in CI)

`@pass` markers in the proof-11 shape; every precondition set in the proof (hazards off, the switch
on, a probe merchant on a hand-set two-port market so profit is deterministic, the roster's own
merchants left as they are); all rolled back.

- **MERCHANT_CLIENT_WALL** — as `authenticated` (`cmd.assume_identity` + `set local role
  authenticated`): every core and every `npc_*` function is refused 42501; a direct write to any
  merchant row is refused; every door handed a merchant id answers "not yours"; RLS shows the
  probe player none of the merchants' rows; `world.sea_traffic` and the card answer; the card
  refuses the probe player's own fleet.
- **MERCHANT_AFK_LAP** — `npc_traders_switch(true)`, then `tick_arrivals(t)` and
  `tick_reconcile()` alone while `t` is warped over 3 game-days: the probe merchant closes ≥ 1 lap
  with `net > 0` through the shared executor (every BOUGHT/SOLD has a route-born order; one
  DEPARTED per arrival); a probe merchant on a loop that visits one harbour twice advances
  `lap_no` and closes a ROUTE_LAP through two hourly re-plans; the roster merchants each close
  ≥ 1 lap (sign unconstrained); over 24 hourly passes every house held at least one line.
- **MERCHANT_BOOKS** — after `npc_compact`: Σ ledger = ducats for every merchant; exactly one
  `NPC_CARRIED` row per compacted company; no player row touched; retained merchant rows ≤
  `npc_row_budget`; rows per lap PRINTED (the number slice 6 records).
- **MERCHANT_RANK** — after `settle_standings`, no merchant on the board, the probe player on it.
- **MERCHANT_EARNINGS** — the card's `earnings.day` equals the hand sum of the lap rows closed in
  the window, `laps_recent` the last seven nets in order.
- **MERCHANT_REFOUND_CAP** — four refound conditions in one warped week: three refounds, then
  `laid_up` and the route's stops equal `alt_loop`.
- **MERCHANT_DARK** — `npc_traders_switch(false)`: routes pause `dark`, fleets end docked, both
  reads are empty, and a woken tick writes no merchant order.
- **MERCHANT_NOWAIT** (CI only, two connections on the disposable Supabase): with a probe fleet
  locked by a second session, `tick_reconcile` skips it, reports one skip and finishes under
  `lock_timeout`.

### Playwright

- `tests/npcOn.fixture.ts` (the `routesOn.fixture.ts` pattern): opens `dist/db/world-*.tar.gz`,
  runs `select public.npc_traders_switch(true)` and warps `tick_arrivals` so merchants are at sea
  and in port, serves the image with `page.route`. Needs `npm run build` first.
- `tests/map.merchants.spec.ts`:
  - unit: traffic never enters `model.fleets`, `focusPoints`, `motionPoints` or `portRoles`;
    `buildChartModel.length === 2`; an own fleet wins a tie hit; `mapTrafficOf` copies position
    and never computes one; a traffic row's `track` is null unless its course exceeds two points;
    the eight nation tokens exist in both schemes and pass the contrast method.
  - browser with `npcOn`, 390 × 844, a Lisbon start: **≥ 2 `data-testid="map-merchant"` hulls
    inside the opening frame, averaged over 5 minutes of warped clock**; a sailing hull's
    transform changes between two beats; a docked merchant is drawn at its roadstead and its peek
    reads *Lisbon · sails at …*; tapping a hull opens the sheet with the company, master, route,
    the seven lap nets, ships, officers with home ports, Skills, earnings and laps, draws its leg,
    and the sheet contains no `button` but the tray handle; the command draft is unchanged after
    the tap; PORT at a harbour with a docked merchant lists it and opens the same sheet; the
    section is absent elsewhere; on LEDGER no `sea_traffic` request is made.
  - browser with the default image (switch off): zero merchant hulls, no section.
- Existing specs kept green and amended only where a pin moves, with a dated comment:
  `flicker.spec.ts` (one reader), `sections.spec.ts`, `duplication.spec.ts`, `words.spec.ts`
  (+ the NPC ban), `map.marks.spec.ts`, `map.labels.spec.ts` (no merchant labels, so no count
  moves), `map.lag.spec.ts` (35 hulls, one track: pan cost measured), `chart.ink.spec.ts`,
  `selection.lock.spec.ts`, `layout.spec.ts`, `primitives.geometry.spec.ts`,
  `rpc.surface.spec.ts`, `db.chain.spec.ts`, `db.image.spec.ts`.

---

## 12. Slices and the files each touches

### Slice 1 — the same hands (0096), server only

`supabase/migrations/20260818000096_a_fleet_is_formed_by_the_same_hands.sql` ·
`scripts/db/proofs/11_standing_route.sql` · `supabase/migrations/CHAIN.md` ·
`tests/db.chain.spec.ts` (LAST) · `tests/rpc.surface.spec.ts` (the two set asserts) ·
`src/lib/rpc/types.ts` (`laps_per_game_day`, `crew_up` on the served route shape — optional,
read-only) · `src/features/command/standingRouteDraft.ts` (carry `crew_up` through untouched, as
`repair`) · `docs/TRADE_ROUTES.md` (D3 built; the interval pacing in §13.3) · `docs/DEV_LOG.md` ·
`docs/OWNER_REQUESTS.md`.

### Slice 2 — the company the world keeps (0097) and the founding (0098), server only, dark

`supabase/migrations/20260818000097_a_company_the_world_keeps.sql` ·
`supabase/migrations/20260818000098_the_merchant_companies_are_founded.sql` (generated) ·
`data/npc-houses.json` · `data/npc-routes.generated.json` · `scripts/build-npc-0098.mjs` ·
`scripts/db/proofs/12_merchant_companies.sql` · `supabase/migrations/CHAIN.md` ·
`tests/db.chain.spec.ts` · `docs/SECTIONS.md` (the server table gains the merchant row; 0010's
"reads only" note) · `docs/DEV_LOG.md` · `docs/OWNER_REQUESTS.md`.

### Slice 3 — the sea is read (0099), server, dark

`supabase/migrations/20260818000099_the_sea_shows_who_else_sails.sql` · proof 12 (earnings and
read cases) · `tests/rpc.surface.spec.ts` · `supabase/migrations/CHAIN.md` ·
`tests/db.chain.spec.ts` · `docs/DEV_LOG.md`.

### Slice 4 — merchants on the chart, and the sheet (client)

Data: `src/lib/rpc/catalog.ts`, `src/lib/rpc/index.ts`, `src/lib/rpc/types.ts`,
`src/lib/rpc/localBackend.ts`, `src/lib/db/rescue.ts`, `src/live/worldStore.ts`,
`src/live/useMerchantCard.ts` (new).
Chart: `src/chart/liveWorld.ts`, `src/chart/mapTypes.ts`, `src/chart/chartModel.ts`,
`src/chart/FleetsLayer.tsx`, `src/chart/hitTest.ts`, `src/chart/index.ts`.
Shared tiles and their callers: `src/components/ui/ShipTile.tsx`, `CargoRows.tsx`,
`OfficerTile.tsx`, `SkillTile.tsx`, `src/components/ui/index.ts`,
`src/features/fleets/FleetShips.tsx`, `FleetCargo.tsx`,
`src/features/compendium/CaptainsFace.tsx`, `src/features/port/PortAcademy.tsx` (the Skills
wording).
The sheet and the map: `src/live/MerchantSheet.tsx` (new), `src/features/map/MapScreen.tsx`,
`src/features/map/fleetLine.ts` (a docked line with a time), `src/domain/route` (the two new
reason words), `src/index.css` (the eight nation inks).
Tests: `tests/npcOn.fixture.ts` (new), `tests/map.merchants.spec.ts` (new), `tests/flicker.spec.ts`,
`tests/words.spec.ts`, `tests/db.image.spec.ts`, and the pinned specs listed in §11.
Docs: `docs/WORDS.md`, `docs/SECTIONS.md` (the client table gains `live/MerchantSheet`),
`docs/MAP_ATMOSPHERE.md` §5 (the merchant hull, at sea and at anchor), `docs/UI_DIRECTION.md` §6
(the merchant tray), `docs/DEV_LOG.md`, `docs/OWNER_REQUESTS.md`.

### Slice 5 — merchants in port (client)

`src/features/port/PortScreen.tsx` · `tests/map.merchants.spec.ts` (the port cases) ·
`docs/DEV_LOG.md`.

### Slice 6 — measure, deploy, switch

- Run proof 12's soak and `scripts/db/breaktest-balance.mjs` with the switch on; a
  `scripts/db/measure-merchants.mjs` drives 3 game-days of `tick_arrivals` + hourly
  `tick_reconcile` on the applied chain and records in `docs/DEV_LOG.md`: rows per lap and per
  hour under the final pacing, retained rows, the five indexes' sizes, per-pair stock minima
  against each company's floor, each company's steady-state net and which hulls the build
  trimmed, refounds per house (**fail if any house refounds more than once per 3 game-days, or
  the median house net over the 3 game-days is negative**), merchants adrift,
  `explain analyze world.sea_traffic()` ms/call with the roster at sea, and the Lisbon-frame hull
  count.
- Deploy 0096-0099 per `docs/DEPLOY_RUNBOOK.md` (`unwind_the_clock` → `db push` →
  `wind_the_clock`, all jobs `active: true`). Confirm the Deploy run on the target; prove the new
  functions exist with the anon key (42501 = exists, memory rule).
- The owner runs `select public.npc_traders_switch(true);`. Then watch one reconcile hour:
  `pg_database_size`, merchant row counts against the budget, a merchant hull moving on the live
  map, the first ROUTE_LAP rows. `select public.npc_traders_switch(false);` is the rollback.

---

## 13. Known limitations, stated rather than discovered later

- Only three hulls exist; Eastern companies sail Western classes.
- No RECALL or salvage verb exists for anybody; a merchant adrift is laid up until one does.
- Officers are posted per FLEET (0015:82) while DESIGN §C.6 still describes per-ship posting; the
  card shows what the code does. An officer may serve several companies at once, players included.
- `tick_arrivals` still runs every company's arrivals in one transaction; per-fleet
  subtransactions remain TRADE_ROUTES' slice-2 item.
- The MARKET presence line of DESIGN §J.3 is not built; merchant trades will count when it is.
- `world.trade_routes` prices 50 units; the planner ranks by it and sizes by the sink's quote, so
  a good that pays only in bulk is ranked as if it did not. Named, not fixed: the ranking has one
  owner, and its player door stays shut by the owner's 0071 order.
- No port is ice-closed today (no migration ever sets `ports.is_ice_closed`; only the default and
  the refusals read it), so Baltic routes have no season. A seasonal closure is a future
  merchant-visible event, not a build-step refusal.
- `crew_pool` never regenerates; a quay a merchant empties stays empty for players too. The roster
  keeps big crews off small quays; a regenerating pool is a separate decision.
- PGlite is single-connection: the `nowait` skip path is proven only in CI's disposable Supabase.
- The spice geography is 0058's random roll (pepper at Lisbon and Elmina, not Kochi). Merchants
  will make it visible on the map; whether to re-author the producer roster is the owner's HELD
  decision (DESIGN §J.3), with live players' `port_goods.affinity` at stake.
- The first draft's historical blurbs and cargo-named fleets are gone; names follow routes and
  blurbs follow measurement, which is the only honest believability this world offers.

---

## 14. Design check 2026-10-08 — what the two reviews said, and what this revision did

Both reviews were verified against the live code before anything was changed; every claim below
was re-checked by hand or re-measured (`scripts/db/measure-roster.mjs`, cached world image,
308 ranking calls, 35 fleets × 4 candidate loops, top three goods per leg). **Accepted = the doc
now says so; rejected = one line why.**

| # | Review (severity) | Verdict | What changed, or why not |
|---|---|---|---|
| A1 | 3-nau convoys homed at Seville/London are refused `E_DRAFT` (blocker) | **Accepted — measured** (nau draft 3, 0003:2090; SVQ/LON `max_draft` 2; 0036:443-447) | Draft rule in the build step and 0098 (§3.2); Flota re-homed at Cádiz (5), Indiamen at Portsmouth (4); the twelve max_draft-2 harbours named |
| A2 | 11 of 31 fleets have no leg at `npc_min_return_pct` 8 (blocker) | **Accepted in substance, corrected in cause** | The 8 % gate is gone; a per-leg wage test on a SINK-sized parcel replaces it (§4.1). Re-measured: with that sizing every fleet, the Baltic ones included, nets positive on its first lap; the first run's losses were the parcel size (full daily cap on a 5 % good), not the market. Loops are now chosen among authored candidates by measured net; the per-leg table is in §3.2 |
| A3 | Trim and earnings measured on the one lap that never recurs; capital at 100 🪙/t (blocker) | **Accepted** | Trim on mean net of laps 3-6 with the whole roster running; `npc_min_net_to_wages` 0.2; 3-4-stop loops preferred (every shuttle measured lost to one); refounds capped at 3/week then the alternate loop; capital = 1.5 × the largest leg outlay; the seven lap nets on the card; slice 6 fails on a negative median (§3.2, §4.5, §7.4, §12) |
| A4 | Liveliness is world-wide; the pacing hold snaps every route to one boundary; docked ~85 % (major) | **Accepted** | Interval pacing as THE one rule (§4.2, a stated small change for players); liveliness measured in Lisbon's 12° frame, geometrically at build time and in Playwright (§3.3, §11); four Iberian/Biscay/Western-Med houses added (ten loops cross the Lisbon frame) |
| A5 | Docked merchants not drawn (major) | **Accepted** | Drawn at the served roadstead, pointing north; peek *Lisbon · sails at 14:32* (§8.2, §7.2) |
| A6 | 0.7 × hull = the retired dot; six company inks collide (major) | **Accepted** | Full `shipHalfLength`, no halo instead of a smaller hull; eight nation inks (§8.2) |
| A7 | Merchants sit on exactly the pairs MARKET shows players; add wares and `npc_leave_top` (major) | **Wares accepted; `npc_leave_top` rejected** | Authored `wares` as a filter on the one ranking (§4.1). Leave-top rejected: the owner removed the player's comparison in 0071 ("the game is to challenge players for finding the best prices by themselves"), so there is no "players' list" to protect, and a merchant on the best pair IS the simulator the owner asked for; the wares filter and the one-buyer rule already spread the houses |
| A8 | Blurbs assert history on a re-rolled world (major) | **Accepted — measured** (pepper at ELM/LAG/LIS, Kochi 1.381; cinnamon CHE/LIS/OLD; quicksilver CAD/LIS/SVQ; producers per good 1-3, not "exactly 3") | Blurbs generated from measured lines and asserted; fleets named after routes; DESIGN §J.3 gains the dated, HELD decision on the spice geography (§3.2, §13) |
| A9 | Refound has no ceiling; a subsidised house holds a permanent premium (major) | **Accepted** | 3 per real week, then laid up and re-cut to `alt_loop`; `refounded_at` on the card; knob `npc_refound_max_per_week`; slice 6 fails on > 1 refound per 3 game-days (§4.5, §12) |
| A10 | Roster-order planning makes the last houses structurally last (major) | **Accepted** | Start index rotates with the hour; proof 12 asserts every house held a line over 24 passes (§4.1, §11) |
| A11 | The beat is 3 s and unstated; per-viewer `voyage.position` cost (major) | **Accepted** | Stated (§2, §7.2); read only while MAP/PORT is mounted via `trafficWanted` (§8.1); planner-cost assert in 0099 (§11) |
| A12 | "Captain" = four company bars (minor) | **Accepted** | WORDS rows: **Skills** for the levels, **captain**/**master** for people; PortAcademy's line reworded; officer home port on the tile (§8.6, §8.3) |
| A13 | Officers are 51 not 43; prefer home port on the loop; add lesser officers (minor) | **Accepted — measured** (51; 44 with a nation; all with a home port) | Selection by home port first; twelve lesser nation-matched officers as world data; "may serve several companies" stated (§3.2, §13) |
| A14 | Draw the tapped merchant's leg (minor) | **Accepted** | The card serves `voyage_view(true)`; the selected row alone carries a track, drawn by `TracksLayer` (§7.3, §8.2) |
| A15 | No port is ice-closed; the ice refusal is moot (minor) | **Accepted — verified** (only the column default and the refusals read it) | Refusal dropped from the build step; stated in §13 as a future event |
| A16 | Re-measure rows after the pacing change (minor) | **Accepted** | §5.1 re-derived (~12 k rows/h, ~14 fleet-equivalents at sea); budget 100 k; slice 6 re-measures and lowers `npc_fleet_max` first (§5) |
| B1 | The save door's `min(ord)` re-anchor breaks any loop that repeats a harbour; three convoys repeat CPT (blocker) | **Accepted — verified** (0092:1004-1021; the assign door 0093:234 too) | Anchor fixed in 0096 for save and assign with a repeated-port probe; the build step refuses repeats until it ships; the measured roster repeats no harbour (ocean loops return by a different harbour or direct) (§3.1, §3.2, §11) |
| B2 | The sail-on branch never renders HIRE; crew-short merchants loop for ever; does `crew_pool` regenerate? (major) | **Accepted — verified** (0092:626-636; the only live writers of `crew_pool` are `do_hire` and `do_dismiss`) | One tail renderer for both branches; three consecutive clears → `laid_up`; crew-pool rule in the roster; "never regenerates" stated (§4.4, §4.5, §3.2, §13) |
| B3 | `world.trade_routes` is dead code with no player caller; the registry row is stale (major) | **Accepted — measured** (the ONE registry row `has_function_privilege` refuses) | §1.3 and §2 rewritten; row dropped in 0096; rpc.surface gains registry ⊆ granted and writers ⊆ registry (§3.1, §11) |
| B4 | The one pacing rule holds every route to the same boundary; option (a) interval or (b) unpaced (major) | **Accepted, option (a)** | One interval rule for all, players' change stated, 0092's assert re-stated; the switch-minute burst named and accepted (§4.2) |
| B5 | Upkeep locks survive savepoints and can deadlock the minute tick (major) | **Accepted, with one honest limit** | `for update nowait` fleet-then-route, 55P03 = skip, `lock_timeout` 2 s; proven in CI with a second connection — PGlite cannot hold a lock from another backend, so the local assert proves only the shape (§4.5, §13) |
| B6 | The `error` 6-h rule can never fire because the planner's save bumps `updated_at` (major) | **Accepted — verified** (0092:926-929) | `npc_plan` skips `error` and `laid_up`; self-assert with a 7-h warp (§4.5) |
| B7 | `sea_traffic`'s per-beat `voyage.position` cost is unmeasured; a served voyage id is a callable handle (major) | **Accepted — verified** (0047:504 walks the path; `voyage.position` granted to `authenticated`, 0088:184) | Slice 6 measures before the switch; memoise per 3-s slot above ~5 ms; `voyage_view(false)` omits `id` (§5.3, §7.1) |
| B8 | Text-scan self-asserts lack positive controls (major) | **Accepted** | Every scan proves it can see first; the Rank assert gains a famous probe merchant (§11, N19) |
| B9 | A raise in 0098 aborts `db push`; `nation_id` nulls silently; hull names must be unique (minor) | **Accepted — verified** (0004:289; `ships_player_name_unique` 0004:104) | `--taken names.txt`; `new_house` raises on unknown codes; `nation_id` not null and distinct hull names asserted (§3.1, §3.2, §11) |
| B10 | The rescue dumps the seed into localStorage (minor) | **Accepted — verified** (`rescue.ts:122`; `build-image.mjs:125`) | Filter by `not is_npc`; `db.image.spec.ts` and a rescue unit case (§8.5) |
| B11 | Moved tiles must not import `domain`/`live`; `placeSailing` would build tracks nobody draws (minor) | **Accepted — verified** (`FleetShips.tsx:4`, `FleetCargo.tsx:28`, `sections.spec.ts:150`) | Pure props on every tile; traffic `track` null unless the selected full course (§8.3, §8.2) |
| B12 | Citations: 51 officers; `world.quote`'s 5th argument is `p_limit`; `mapTypes.ts` is 172 lines; `npc_plan` writing `laps_per_game_day` is a second writer; the CHECK re-cut; the §7.3 privacy wording (minor) | **Accepted — all verified** (`p_limit` 0005:399; `MapSelection` at :166) | Every cite corrected; the save door gains `p_laps_per_game_day`; the CHECK re-cut named in 0096; §7.3 rests on the `is_npc` filter |
| — | Both reviews cite a separate `TracksLayer` file | Corrected | `TracksLayer` is a component inside `src/chart/FleetsLayer.tsx:30`; cited so |
| — | Review A: "every good has exactly 3 producers"; Review B: `new_house` founds "at a European capital" | Corrected — measured | Producers per good range 1-3; the live `new_house` founds every nation at LIS (0004:290 unchanged), which is why the Lisbon frame is THE frame (§3.3) |

**Net effect on the plan:** the architecture (one executor, players' own tables, server-only
cores, dark-first, bounded retention) is unchanged; what changed is everything that was argued
rather than measured — the roster (26 companies, 35 fleets, loops chosen by measurement, four
Iberian houses, no repeated harbours, drafts and quays checked), the planner's sizing (the quote's
own `p_limit` walk, no planner arithmetic), the pacing rule (interval, one rule), the self-heal
(one tail renderer, counted clears, no waiting locks, bounded refounds), the asserts (positive
controls, draft, names, registry sets) and the picture (full hulls in nation ink, docked merchants
at their roadsteads, the tapped leg drawn, the seven lap nets on the card).

---

## 15. As built (2026-10-08, branch `osn-npc-traders`) — where the build departs from this plan, and why

Everything above is the plan. These are the places the build differs, each for a stated reason; the
architecture (one executor, players' own tables, server-only cores, dark-first, bounded retention) is
unchanged.

| # | Plan said | Built | Why |
|---|---|---|---|
| X1 | `npc_houses.alt_loop` | `public.npc_fleets` (one row per merchant FLEET: route, roster order, alternate loop) beside `npc_houses` (per company) | A company sails up to two loops; roster order (`npc_fleet_max`) and the alternate loop are per fleet. Neither table is a predicate (a trigger refuses a non-merchant row) |
| X2 | `players.is_npc` in 0097 | in 0096 | so `new_house` is generalised once (it takes `p_is_npc`), not twice |
| X3 | — | `cmd.clear` and `cmd.cancel_at` refuse a fleet that is not the caller's (`E_NOT_YOUR_FLEET`) | both took a fleet id and never asked whose it was; harmless while no foreign fleet id was served, a hole once 0099 serves merchant fleet ids |
| X4 | 0098's build "warps six laps through `tick_arrivals` + hourly `tick_reconcile`" | the harness settles each fleet with `voyage.settle` at its own ETA in arrival order (what `tick_arrivals` runs for a due fleet), runs `npc_plan` + `npc_tend` on the simulated hour and `tick_market_drift` on its own 15-min slots, applies the merchant pace to the SIMULATED clock, and rolls the daily cap by deleting merchant `trade_daily` rows at each simulated game-day | `voyage.depart` stamps departures with the database's `now()`, so a clock cannot be passed down; the cap reads `world.game_day()` from `now()`. Stated in the script's header and in the generated JSON |
| X5 | refuse a roster that leaves ANY nation capital's frame with < 2 loops | refuses on the LISBON frame only; every capital's count is printed | `new_house` founds every company at Lisbon (§2), so Lisbon's is the only founding frame a player meets |
| X6 | `--taken names.txt` before emitting | generated without it (no production access from this machine) | **the owner's one read before deploy**: `select company_name from public.players` into a file, re-run the build with `--taken`, commit the regenerated 0098. `npc_found` still raises on a double collision (the net) |
| X7 | `sea_traffic` row keys `id, company, nation_code, name, status, ships, port, roadstead, anchor, voyage, next_lap_at` | + `ink` | the ink family is authored world data (`npc_houses.ink`); serving it means the client holds no second nation→ink table |
| X8 | the card's `route.state` = "the 0092 derived word" | the word's `case` is SLICED out of `world.standing_routes` into `public.standing_route_state(route, on)`, called by both | one derivation of the word, not a copy (world.standing_routes' output asserted identical) |
| X9 | 0099 asserts `explain` shows one index scan on `fleets` | 0099 times 20 calls and prints ms/call in its receipt; `scripts/db/measure-merchants.mjs` records the `explain analyze` figure | `fleets` holds ~100 rows; a plan-shape assert would pin the planner's choice, not a cost |
| X10 | proof 12: REFOUND_CAP; "over 24 hourly passes every house held a line"; NOWAIT | REFOUND_CAP is 0097's self-assert; the soak asserts every roster FLEET closes a lap (stronger than holding a line); NOWAIT stays CI-only | PGlite is one connection; a proof that repeats a migration's probe adds nothing |
| X11 | `MerchantSheet` reads its card | the SCREEN reads it (`useMerchantCard`) and hands it to the sheet | MAP also draws the open merchant's leg from the same answer: one read per screen, not two |
| X12 | the peek row is a `MapTrayTitle` | the sheet composes the same row itself | `src/live` sits below the screens and cannot import `features/map` |
| X13 | local backend ticks "in the same callAs transaction" | in its own `callAs`, immediately before the read | `LocalCaller` runs one statement per transaction; the order is what matters |
| X14 | trim until mean net(laps 3-6) ≥ 0.2 × wages, "with the whole roster running" | the same rule, applied only to fleets that have NOT yet passed in any measurement of the whole roster; a fleet that passed once is kept as it is; the market's `random()` stream is seeded per measurement (`setseed`) | measured on 2026-10-08: re-judging every fleet on every pass ratchets the roster down on NOISE — run 2 (unseeded, re-judged) dropped 19 of 35 fleets that had each passed at least once and left 14 companies / 16 fleets / 21 hulls; trimming one fleet moves the market every other fleet trades in, so a pass is not independent evidence. Run 3 (seeded, freeze-on-pass, ≤ 6 passes) kept **23 companies, 32 fleets, 64 hulls**, 14 loops crossing Lisbon's frame. The generated header prints each kept fleet's LAST measurement, which for a few is negative (it passed earlier); slice 6's soak on production's market is the judge the plan names |
| X15 | sea_traffic memoised per 3-s slot above ~5 ms | not built; measured instead | 0099 measured 27.7 ms/call and `scripts/db/measure-merchants.mjs` 20.5 ms/call (`explain analyze` 20.6 ms, 12 KB) — on PGlite (WebAssembly, one connection), not on production. A memo is a WRITE inside a read path; it is the slice-6 lever once production's own figure is read, not a guess made here |
| X16 | (found, not planned) | **NOT FIXED — reported.** A route's LAP closes when the fleet ARRIVES at stop 0, before stop 0's SELL lines run; those sales are written under the NEXT lap (0092's closer). So a parcel bought on the last leg (bought at the last stop, sold at home) books its COST on lap N and its REVENUE on lap N+1. Measured on 2026-10-08: Carreira do Brasil's first lap read −114,807 🪙 (emeralds bought at Salvador for 116,224, sold at Lisbon for 139,165 in the next lap). Per-lap means over several laps are right (the build judges laps 3-6); a route's FIRST lap, and the card's day sum in its first hours, read low | It is 0092's lap semantics, shared with every player route, and moving the boundary (close after stop 0's sales) is a change to a live player feature — the owner's call, recorded here and in DEV_LOG, not slipped into this branch |

