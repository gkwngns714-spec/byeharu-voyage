# COMMAND DESK — the PORT tab goes; COMMAND becomes a trading desk

**Status: BUILT, D1–D8 (2026-10-18): 0170 · 0171 · 0175 · 0176 · 0177 and the client slices; PORT deleted (D8). Each slice's dev-log (`docs/dev-log/2026-10-18-command-desk-d*.md`) says where it departed from this design.** Design v1 (2026-10-17) follows as written. No migration, no code,
no production change. Written against `main` `3814ec9` (production head **0141**). Every production
number below was read **read-only** on 2026-10-17 between 13:50 and 14:30 UTC with
`npx supabase@2.120.0 db query --linked "<one select>"` (or `explain analyze` of a STABLE read). The
build happens **after the current queue** (owner); migration numbers are therefore not assigned here.
Each server slice takes the next free number when it is built.

**The owner, 2026-10-17, verbatim:**

> *"i want you to delete port tab, and focus on command tab. it will be like stock trading screen,
> with buy and sell plans, seeing charts of each trade goods that i click, setting up trade routes for
> my fleet, investing, and all. i will be able to see the estimated price movement so that i can plan
> buying and selling for max profit. for example when i press coffee trade goods, it will show chart,
> where i can buy, the price if i sell to other cities. at which time and so on. i want you to make the
> command page stylish - modern - sophisticated yet concise simple."*

**Three standing rules this order REVERSES, recorded so nobody restores them later** (rule 3 of
`docs/OWNER_REQUESTS.md`: a reversed row keeps its row and says what reversed it):

| Row | It said | Now |
|---|---|---|
| **55** (LAW) | *"there is no need info - cheapest here, the game is to challenge players for finding the best prices by themselves"* | **REVERSED [OWNER].** *"where i can buy, the price if i sell to other cities … for max profit"* asks for exactly the comparison row 55 deleted. 0071's comment in `world.market` (*"the question the game exists to make the player answer for themselves"*) is superseded the same way. |
| **64** | *"no nearby price info needed"* | **REVERSED [OWNER]**, same sentence. Row 64's other half (prices move like a stock, bounded) stands and is what the estimate is built on. |
| **73** | *"Buy and sell should be in port - market … located accordingly at different locations"* (COMMAND composes no verb; `tests/verbHomes.spec.ts` rule 1) | **REVERSED [OWNER]:** *"delete port tab, and focus on command tab"*. What survives of row 73 is its true half: a verb still happens **at a place**, and only while a fleet is docked there (§2.1). The building faces move under COMMAND; they are not merged into one grid. |

What does NOT change: the cargo laws (goods have volume and a place; storage is per port; reachable
only while docked), the server as the one authority for every figure, the press-selects-never-
restructures law, the map as the place you see where things are.

---

## Owner to confirm — every DEFAULT in this plan, in one table

Every rule below is tagged **OWNER** (your words, above or in an earlier row) or **DEFAULT** (my
proposal). The DEFAULTs are few. Each one says what happens if you say no.

| # | DEFAULT | Why | If you say no |
|---|---|---|---|
| **D1** | **The desk has five faces, in this order: Markets · Plans · City · Invest · Profit.** Markets opens first. | Your sentence names them in this order: charts and buy/sell (Markets), buy and sell plans and trade routes (Plans), investing (Invest), "and all" (City holds every building PORT had: storage, craft, inn, build, repair, skills, requests, town). Profit is the "max profit" you plan for, kept as a running total. Five fit one row at 390 px. | Rename or reorder: it is one table (`deskView.ts`, §8). |
| **D2** | **The sell list is SORTED by net profit per ton**, best first, and the buy list by price, cheapest first. | You asked for "max profit"; an unsorted list of 238 cities hides the answer you asked to see. Row 55 is reversed by your order, but sorting is the strongest form of that reversal, so it is listed. | Sort by distance or by name; the player can still re-sort. |
| **D3** | **The estimate looks 6 hours ahead** (24 price moves of 15 minutes), stretched to cover the voyage if it is longer, and draws an **80 % band**: 8 times in 10 the price lands inside it. | Prices move every 15 minutes; a voyage takes ~15 minutes real time per 1,500 miles (§4.1), so the useful question is mostly *"wait here, or sell now?"*. Six hours covers four stock refills (48 min each) and is where the random part has nearly reached its full width (§4.3). 80 % is the band a person reads as "likely" without it filling the chart. | 2 h / 12 h / 24 h, or a 50 % / 95 % band: two knobs. |
| **D4** | **A city that does not SELL a good has no recorded price history for it**, so its chart on the good page shows only the estimate (from now). History is kept only where a good is sold, as today. | The record is a disk budget (0057: the table once filled 98 % of the database and took the game read-only). Recording all 132,090 (city, good) pairs would be 98× today's rows. | Record sell-side history for the pairs players watch — a new table and a cap; its own slice. |
| **D5** | **The estimate assumes nobody else trades the good there before you arrive.** It says so in one line under the chart. Players and merchants do trade, and the band does not cover that. | The server cannot know future trades. Merchants' loops are known, but folding their scheduled buys into a forecast is a second simulation of the merchant executor — exactly the duplication NO_SPAGHETTI §1 forbids. | Add merchant stops to the estimate (a large slice; would need its own design). |
| **D6** | **A plan does not wait.** A planned BUY with a Max, or SELL with a Min, runs when the fleet arrives; if the price is past the limit, the line is refused like any order today (a one-off plan halts the queue; a route skips the line and notes it on the lap). | That is how BUY … AT / SELL … AT ≥ already work (`docs/TRADE_ROUTES.md` §1), so plans need no second executor. A plan that waits in port for its price is a new verb (`WAIT`, designed in DESIGN.md:809 and never built). | Add `WAIT UNTIL <price> OR <time>` as its own slice after D8. |
| **D7** | **Net profit on the sell list counts:** what you get (the real quote for the amount, in 10-ton steps), minus what it cost (the buy quote, or what you paid if it is on board), minus the profit tax, minus the port fee (spread), minus crew wages for the days at sea. It does **not** count repairs, losses at sea, or bargains you have not struck. | Each of these has one server reader already (§7.2). Wear and hazards are dice; counting them would be a guess. | Add supplies at the price Resupply charges (one more reader, if it exists as a leaf — checked in D2's architect pass). |
| **D8** | **The map's city panel stays** (Market · Port · Inn · Town Hall) as the read-only view of a place. Tapping a good in its Market tab opens that good on the desk. The "merchants in port" list lives only on the map. | The map is where things are; the desk is where you act. Two lists of the same merchants would be two screens to keep in step. | Move the merchants list onto the City face as well. |

---

## 0. The answer in fifteen lines

1. **PORT is deleted LAST** (slice D8), after every verb it carried has a home on COMMAND (§2). The bar
   goes from five cells to four: Command · Fleets · Map · Menu.
2. **COMMAND is the desk.** A fleet strip on top says which fleet you are commanding and where it is —
   `Docked at Lisbon` or `Sailing to Cádiz · 12 min`. Every act that happens at a place is offered only
   for the city that fleet is docked at, exactly as today.
3. **Markets** is a watchlist of all 555 goods — filter by category, *Here* (what this city trades),
   *On board*; each row a name, a sparkline, the market price and its change.
4. **Pressing a good opens its page** (a tray on a phone; the middle column on a wide screen): the
   chart, **Buy at** (the 1–3 cities that sell it, with stock and days away), **Sell at** (every city
   that buys it, with what you would net per ton and when to arrive), and the Buy/Sell cells when you
   are docked where it trades.
5. **The chart** draws the recorded price (the last 12 hours) and the **estimated path** with its
   **80 % band** for the next 6 hours, a dotted line where you would arrive, and a dot where the
   estimate peaks.
6. **The estimate is ONE new server function, `world.price_outlook`,** built from the same terms the
   price is made of today (`world.mid_terms` → `world.mid_from_terms`). The parts that are certain —
   stock refilling toward its target, the season term, development — are computed exactly; the random
   walk becomes the band. The client draws it and computes nothing.
7. **Buy at / Sell at are ONE new read, `world.good_board`,** which prices every city through
   `world.quote` (the function the money moves by), so the net it shows is the net a trade would get.
8. **Plans** holds the fleet's route (today's route editor, moved) and its orders (today's queue,
   moved), plus a **plan builder**: *buy coffee at Mocha, at most 95 🪙 → sell at Lisbon, at least 140 🪙*,
   committed either as **queued orders** (one new atomic verb, `cmd.issue_lines`, over the existing
   `cmd.enqueue`) or as a **route** (the existing route editor, prefilled). No second executor.
9. **City** is PORT's building faces, moved as they are: Storage, Craft, Inn, Build, Repair, Skills,
   Requests, Town — for the city the fleet is docked at, read-only otherwise.
10. **Invest** lists what you hold in every city (one new read, `world.holdings`) and the docked city's
    Town Hall (Invest today; Donate when `docs/INFLUENCE.md` I2 lands).
11. **Profit** is the running total: today, the last 7 days, per fleet, per route (one new read,
    `world.books`, summing the ledger the server already keeps).
12. **The look:** the existing tokens and type scale, one accent (gold = yours / act), green–red only for
    gain–loss, tabular figures, hairlines, no boxes, no chart library (the existing SVG chart grows a
    band), 390 px and 1440 px layouts (§5).
13. **Nothing moves under a press** (owner law): a press selects; a page or tray rises in its own slot.
14. **Found while reading prod:** half of `public.price_history` (61,824 of 126,528 rows) is a stale
    2026-09-02 record numbered on an old slot clock; it is never pruned and every history read returns
    it as the newest points (§1.3). D1 removes it.
15. **Eight slices, D1–D8** (§10). Three are migrations that only ADD reads (D1, D2, D6/D7 share the
    pattern), one adds a verb (D4). PORT's removal is D8 and only after `tests/verbHomes.spec.ts` proves
    every verb has a home on COMMAND.

---

## 1. What exists today (read from the repo and from production)

### 1.1 The screens

| Today | What it is | File |
|---|---|---|
| **COMMAND** | Fleet chips, two figures (supplies, cargo), the fleet's **Route** fold, its **Orders** queue. Composes no verb since 2026-09-09. | `src/features/command/CommandScreen.tsx`, `Queue.tsx`, `RouteFold.tsx`, `RouteEditor.tsx`, `RouteStop.tsx`, `standingRouteDraft.ts` |
| **PORT** | One harbour (the port field picks any), faces: Trade · Town · Storage · Craft · Inn · Build · Repair · Skills; a fair row; merchants in port; the anchorage view for a sea place. | `src/features/port/*` (PortScreen 311 lines; faces in `portView.ts` `PORT_FACES`) |
| **MAP city panel** | Market (read-only ledger + price tray) · Port (ships here and incoming) · Inn (crew, supplies, captains) · Town Hall (treasury, works, Invest). | `src/features/map/CityTabs.tsx`, `cityTab.ts`, `CityHarbour.tsx`, `CityTownHall.tsx` |
| **Routes** (Menu) | Every lane the world sails, ranked. | `src/features/routes/RoutesScreen.tsx` |
| Charts | `Sparkline` (folded) and `PriceChart` (340×170 SVG, served min/mid/max, three marks), model in `priceChartModel.ts`. **No chart library** in `package.json`. | `src/components/ui/{Sparkline,PriceChart,priceChartModel}.ts(x)` |

### 1.2 The price, as the server makes it (live bodies, read from prod)

```
mid = clamp( base × affinity × demand × (stock_target / max(stock,1))^elasticity
             × (1 + drift) × (1 + season_mod) × (1 − mid_dev_discount × dev_commerce),
             price_band_lo × base, price_band_hi × base )                 -- world.mid_from_terms (0066)
ask (per 10-ton step) = mid × (1 + tax + spread/2)                       -- world.quote (0134 re-cut)
bid (per 10-ton step) = mid × (1 − spread/2) × (1 − tax) × city_bid_factor
   tax inside the quote is 0 while city purses are on (tax falls on PROFIT, public.profit_tax, 0122)
```

The terms of one row are read by **`world.mid_terms(port, good)`** (0134), the one reader; `world.quote`
walks the stock in `trade_step_tuns` (10) steps and re-prices each step.

**What moves a price over time** — `public.tick_market_drift(p_now, p_port)` (live body, 0137), run for
every harbour by the drift job every `drift_slot_seconds`:

| Term | Rule (live) | Knobs on prod |
|---|---|---|
| drift | `drift ← clamp(θ·drift + σ·N(0,1), ±clamp)` once per slot (Box-Muller from `random()`, deliberately not replayable) | θ = `drift_theta` **0.9**, σ = `drift_sigma` **0.02**, clamp **0.2**, slot **900 s** |
| stock | closed form per game day: `stock ← min(target, target − (target − stock)·(1 − rate)^days + production × works_factor × days)` | rate = `stock_regen_fraction` **0.15**, game day **2,880 s**; `production_rate` = 0 on all 132,090 rows today |
| season | `port_goods.season_mod`, read as it stands | **0 on every row** today (the term is in the formula and inert) |
| development | `dev_commerce` × `mid_dev_discount` (0.004) | changes only when a city grows |

Trades move `stock` (a buy lowers it, a sale raises it), which moves the price through the elasticity
(0.5).

### 1.3 The record, and a defect found while reading it

`public.tick_price_snapshot` writes one row per (city, good) **that the city sells** per slot
(`public.port_offers`, 0061) and prunes `slot ≤ now_slot − window`; `world.price_history(port, slots)`
serves `slot ≥ now_slot − slots + 1`, keyed by good code, ordered by slot.

| Production, 2026-10-17 ~14:20 UTC | |
|---|---|
| harbours · goods · market rows | **238 · 555 · 132,090** (every harbour has a row for every good) |
| (city, good) pairs a city SELLS | **1,348** — each good is sold in **1 to 3** cities (median 3) |
| history window | `price_history_window()` = **48 slots = 12 hours** |
| rows on the current clock | 64,704 (48 slots) |
| **rows numbered on an old clock** | **61,824**, all dated 2026-09-02 08:40–16:30, for 2,046 pairs, `slot` ≈ 2.98 M while today's slot is 1,991,384 |

Those 61,824 rows were written when the slot was 600 s or shorter, so their slot numbers are **larger**
than today's. The prune (`slot ≤ now − window`) can never delete them, and the history read
(`slot ≥ now − slots + 1`) **returns them as the newest points** of every pair they cover. I did not
drive the chart to see what it draws for such a pair — it is a finding from the data, not from the
screen — but the chart model's x span is "the wider of now − earliest `at` and points × slot", so a
pair with these rows would be stretched over ~45 days. **D1 deletes them** (one statement,
`slot > drift_slot_of(now())`, self-asserted). It is 49 % of the table (22 MB on disk in total).

### 1.4 What the server already answers that the desk composes

| Read / verb | Answers | Used by the desk for |
|---|---|---|
| `world.market(port)` | the city's board: buy, sell, mid, range, stock, offered | Markets → *Here* rows' two cells (as PORT's Trade face today) |
| `world.price_history(port, slots)` | recorded mids | the chart's solid line |
| `world.quote(port, good, qty, side, limit, fleet)` | the money for a quantity, step by step | every net on Sell at (through `world.good_board`) |
| `world.trade_routes(from, fleet, radius, limit, to)` | from one city: the best good to carry per destination (no client caller today) | not used; its priced stage is re-cut onto the same leaf as `good_board` (§7.2) |
| `world.buy_capacity`, `world.haggle_state`, `cmd.preview_basket`, `cmd.trade_basket` | the trade tray and basket | unchanged; the good page opens the same tray |
| `world.standing_routes`, `cmd.standing_route_*` | routes | Plans (moved) |
| `cmd.issue`, `cmd.cancel_at`, `cmd.clear`, `cmd.enqueue` | orders | Plans (moved); `cmd.issue_lines` wraps `cmd.enqueue` |
| `world.town_hall(port)`, `cmd.preview_invest`, `cmd.invest` | a city's purse, works, shares | Invest |
| `world.contracts` | requests | City → Requests, and one row on the good page |
| `world.ledger`, `world.fleet_trades` | the record | Profit (through `world.books`) |
| `voyage.reach_from(port)`, `voyage.fleet_speed(fleet)` | sailed miles from a city; a fleet's speed | days and arrival times on Buy at / Sell at |

Measured on production (`explain analyze`, STABLE reads only): **238 sell quotes of one good** cost
**416 ms** at 200 tons and **384 ms** at 10 tons — the cost is the fixed per-call preamble (≈1.6 ms:
the row's terms, the effective spread, the city's bid factor, five knob reads), not the steps.
**238 × `world.price`** costs **236 ms**. The 12-hour scan of `price_history` grouped per pair costs
**61 ms**. These numbers set the server design in §7.

---

## 2. What leaves PORT, and where every verb lands

### 2.1 The docked rule [OWNER — the cargo laws, unchanged]

A verb that acts on a city — buy, sell, resupply, hire, dismiss, repair, build, craft, put in storage,
take on board, enrol, hire a captain, fulfil a request, invest, donate — runs **only for a fleet docked
at that city**. The server already refuses otherwise (`E_NOT_DOCKED`, `E_UNAVAILABLE`, …); the desk does
not add a second check, it only says where the fleet is:

- **The fleet strip** (top of every face) prints the one fact: `⚓ Docked at Lisbon` (accent), or
  `⛵ Sailing to Cádiz · 12 min` (info), or `Anchored · 38° N 9° W` — from `domain/fleet`'s
  `whereabouts`/`whereLine`, the one rule (`src/domain/fleet/where.ts`).
- **City** shows the city the fleet is **docked at**; for a fleet at sea, the city it is **bound for**,
  read-only, with one `Note`: *"Orders run when Gaivota arrives (12 min)."* — PORT's `actingIsHere`
  logic, moved.
- **On the good page**, the Buy/Sell cells exist only on the row of the city the fleet is docked at.
  Every other row offers **Plan** (§3.6), never Buy.
- **Which fleet acts** is the selected fleet in the strip. PORT's `alongsideAt` ("the one docked here,
  else the draft fleet") is no longer needed on the desk, because the desk always has one selected fleet
  [DEFAULT, follows from the strip]. The map's city panel keeps `alongsideAt`.

### 2.2 The verb map — nothing lost

| PORT today (face → act) | Lands on the desk | Component (moved, not rewritten) |
|---|---|---|
| Trade → **Buy / Sell** (price cells, trade tray, basket, receipt, bargain) | **Markets** → *Here* filter rows (the same `TradeRow` cells) and the good page's Buy/Sell cells; the basket stands in the ticket column (wide) or the tray (phone) | `PortTrade.tsx`, `TradeTray`, `ManifestPanel`, `ManifestTotals`, `ReceiptFace`, `HaggleThread`, `OnBoard` |
| Trade → **Resupply** (supplies row) | **City → Inn** (it is already there on the map's Inn), and one supplies row in the fleet strip's fold | `live/PortInn.tsx`, `live/StepQuestion.tsx` |
| Trade → **Requests** (contracts, Fulfil) | **City → Requests**; and a `Wanted here · +12 %` row on the good page for that good | `live/RequestBoard.tsx`, `FulfilTray.tsx` |
| Town (tax, port fee, buildings) | **City → Town** | `PortTown.tsx` |
| Fair row | **City** (top of the face, only when a fair is on) and a marker on the good page's chart | `PortFair.tsx` |
| Storage → **Put in storage / Take on board** | **City → Storage** | `PortStorage.tsx` |
| Craft → **Make** | **City → Craft** | `PortWorkstation.tsx` |
| Inn → **Hire / Dismiss crew, Resupply, Hire captain** | **City → Inn** | `live/PortInn.tsx` |
| Build → **Build ship** | **City → Build** | `PortYard.tsx` |
| Repair → **Repair** | **City → Repair** | `PortShipyard.tsx` |
| Skills → **Enrol**, Training queue | **City → Skills** (enrol where taught; training runs anywhere) | `PortAcademy.tsx` |
| Map's Town Hall → **Invest** (and Donate, I2) | **Invest** (the docked city's hall) — the map keeps its tab too (D8) | `CityTownHall.tsx` → moved to `src/live/` so both compose it |
| Port field (read any harbour's prices) | **The good page** (every city's price for one good) and the **map's Market tab** (every good at one city) | `live/PortField.tsx` stays for the map; PORT's use goes |
| Merchants in port | **Map only** (D8) | `MerchantsHere.tsx` deleted with PORT; the map's `CityHarbour` is the one list |
| Sea place (anchorage) view | the fleet strip's `Anchored` line | — |
| Fit / Unfit | unchanged — the ship panel (FLEETS) | — |
| **Sail** | unchanged — the MAP (owner row 45). A plan's SAIL lines are proposed by the same `proposeCourse`. | `src/domain/passage` |

`tests/verbHomes.spec.ts` is rewritten in D5 to this table: rule 1 becomes *"every building verb is
composed under `src/features/command/city/` (or `src/live/`) and nowhere else"*; rule 3 (StepQuestion has
one home) stands.

---

## 3. The desk

### 3.1 Shape

Every figure in the sketches below is illustrative; the real ones are served.

```
 PHONE 390 × 844                                   DESKTOP 1440 × 900
 ┌──────────────────────────────────┐   ┌──────────────┬──────────────────────────────┬──────────────┐
 │ ◎ 8,180 🪙          prices 5:57  │   │ status strip ─────────────────────────────── 8,180 🪙   │
 │ Gaivota ▾  ⚓ Docked at Lisbon   │   │ Gaivota ▾ ⚓ Docked at Lisbon · 51 / 60 tons · 14 days  │
 │ [Markets◆][Plans][City][Invest][Profit]│[Markets◆][Plans][City][Invest][Profit]                │
 │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │   ├──────────────┼──────────────────────────────┼──────────────┤
 │ 🔍 Search goods                  │   │ WATCHLIST    │ GOOD PAGE                    │ TICKET       │
 │ [All◆][Here][On board][Spices]…  │   │ 340 px       │ flexible                     │ 360 px       │
 │ ☕ Coffee      ╱╲╱‾   112  +4.1% │   │ rows…        │ chart, Buy at, Sell at       │ trade tray / │
 │    3 cities · 20 on board        │   │              │                              │ basket / plan│
 │ 🌶 Pepper     ‾╲_╱    149  −2.0% │   │              │                              │ builder      │
 │ …                                │   │              │                              │              │
 ├──────────────────────────────────┤   └──────────────┴──────────────────────────────┴──────────────┘
 │ Command · Fleets · Map · Menu    │    768–1279 px: two columns (watchlist 340 | page);
 └──────────────────────────────────┘    the ticket is a side tray beside the page.
```

- **Status strip** (existing, 32 px): purse right, the market countdown left (`navTabs.ts`
  `TRADE_ROUTES` becomes `['/command']`).
- **Fleet strip** (52 px row): the fleet chip (`Gaivota ▾` opens a tray of your fleets — more than ~3
  fleets do not fit as chips at 390 px) and the where line (§2.1). On wide screens the two figures
  (cargo `51 / 60 tons`, supplies `14 days`) stand on the same line; on a phone they are in the chip's
  tray. Pressing the chip SELECTS a fleet in the tray; nothing on the page moves.
- **Faces** (`Segmented`, one row, 44 px): Markets · Plans · City · Invest · Profit (D1). The chosen
  face persists for the session (`deskView.ts`, PORT's `portView.ts` pattern).

### 3.2 Markets — the watchlist [OWNER: "seeing charts of each trade goods"; DEFAULT: the row's contents]

One `Row` per good, 52 px, two lines, everything tabular:

```
 ☕  Coffee                 ╱╲╱‾╲╱    112 🪙
     3 cities · 20 on board            +4.1 %
```

| Part | Value | Source |
|---|---|---|
| mark, name | the good's mark (`goodIcons.ts`) and name; rarity as its 10-px mark only | snapshot |
| sub-line | `N cities` that sell it · `N on board` (selected fleet) · `Wanted in Lisbon` if a request is open | `world.watchlist` |
| sparkline 56×20 | the last 12 h of the **cheapest selling city's** recorded mid, hourly (12 points) | `world.watchlist` from `price_history` |
| figure | that city's **market price (mid)**, now | `world.watchlist` (set-based `world.mid_from_terms`, §7.3) |
| change | % against 12 h ago, `success` up / `danger` down — read as *dearer / cheaper* only in tone; a buyer reads red as good news, so the chip carries the sign and the arrow, not a word | served |

**Why the list shows the market price (mid) and not what you pay** [DEFAULT, technical]: the ask needs
each city's effective spread, which costs ~1 ms per city through `world.price` (measured, §1.4) — 1,348
calls is over a second for one list. The mid is the chart's own figure and is computed set-based in
~10 ms. *What you pay* and *what you get* are on the good page, from the quote. The list says
`Market price` once in its header, as a stock app shows the last price and the ticket shows bid/ask.

**Filters** (`Chip`s, one scrolling row, single choice except search): **All** · **Here** (what the docked
city trades; this filter turns the rows into PORT's trade board — the same `TradeRow` with its two
price cells, Buy · Sell, and the basket) · **On board** · then one chip per served `category`. A
`Field` searches by name. **Sort** (a quiet control at the list's head): Name · Change · Price. The
filter and sort are session chrome (`deskView.ts`).

Pressing a row's **name** opens the good page; pressing a **price cell** (only under *Here*) opens the
trade tray, as PORT's board does today. The row that was pressed takes the `accent-soft` wash; nothing
else on the list changes.

### 3.3 The good page [OWNER: "when i press coffee … it will show chart, where i can buy, the price if i sell to other cities. at which time"]

```
 ☕ Coffee · Food                                      ✕
 Mocha   94 🪙   +4.1 % · 12 h                    ← hero: the focus city's price on the side you trade
 [Mocha◆][Aden][Zanzibar]  ·  [12 h◆][6 h][1 h]        ← focus city (a chip per city in Buy at ∪ the
                                                          sell row you tapped); history window
 ┌────────────────────────────────────────────────┐
 │ 104┤                         ┄┄╱‾‾‾‾‾‾╲┄┄       │  solid: recorded (12 h)
 │    │        ╱‾╲    ╱╲      ░░░░░░░░░░░░░░░░░    │  dashed + band: estimate (6 h), 80 %
 │  94┤ ‾╲__╱‾   ╲__╱  ╲_╱‾●  ░░░░░░░░░░░░░░       │  ● now   ◆ best   ┆ you arrive
 │  85┤                       ┆        ◆           │
 │    └──────────────────────┴────────────────────│
 │   −12 h          −6 h     now    +3 h     +6 h  │
 └────────────────────────────────────────────────┘
 If nobody else trades here, the price is likely 88–101 🪙 at 17:40.   ← one line (D5)

 Buy at                                   price · stock · away
 ⚓ Mocha            94 🪙   180 units    here        [ Buy ]   ← docked here: the cell opens the tray
   Aden              97 🪙    60 units    0.9 days    [ Plan ]
   Zanzibar         101 🪙   400 units    2.1 days    [ Plan ]

 Sell at   for 60 units          you get · net per ton · arrive
   Lisbon           141 🪙   +31 🪙 / ton   3.4 days · 17:52   best 19:10 +2 %   ›
   Cádiz            138 🪙   +28 🪙 / ton   3.2 days · 17:49                      ›
   Venice           152 🪙   +25 🪙 / ton   5.9 days · 18:30   wanted · +12 %    ›
   …  (10 shown)                                              [ All 231 cities ]
```

- **Hero figure** (`t-hero`): the focus city's price **on the side you would trade** — the ask at a
  selling city (Buy at), the bid at a buying city (Sell at) — from `world.good_board`. Under it, the
  change over the history window.
- **Focus chips**: the cities of Buy at, plus a sell city once you tap its row. The chart follows the
  chip. Pressing a chip selects; the chart's data changes in place; nothing above or below moves.
- **History window**: 12 h (the whole record, `price_history_window()`), 6 h, 1 h [DEFAULT].
- **The chart** — §5.4.
- **The one line** under the chart [DEFAULT D5]: the 80 % range at the moment you would arrive (or, for
  the city you are docked at, at the estimate's best time), in words and figures, served.
- **Buy at** [OWNER "where i can buy"]: every city that sells the good (1–3 today), cheapest ask first
  (D2): ask for the first 10 tons, stock in units, how far (`here` / days from the fleet's position).
  The docked city's row carries **Buy** (opens the existing trade tray, its `Stepper`, bargain row and
  basket); other rows carry **Plan** (§3.6).
- **Sell at** [OWNER "the price if i sell to other cities … at which time"]: every city whose culture
  buys it. Per row: the bid for the first 10 tons, **net per ton** for the amount in the header (D7),
  days and the clock time you would arrive, and the **best time** hint (§3.4). Sorted by net per ton
  (D2); the head toggles Net · Price · Nearest. The first 10 rows are shown; **All 231 cities** appends
  the rest **below** (nothing above the press moves). A row tap makes that city a focus chip and moves
  the chart to it (the chart is above the list, so the list does not move).
- **The amount** (`for 60 units`): defaults to what is on board, else what the fleet could load at the
  cheapest seller (`world.buy_capacity`'s ceiling). A `Stepper` in the header's tray changes it; the
  board is re-asked for that amount (debounced; the old figures stay drawn while it answers).
- **Requests**: a sell row whose city has an open request for the good says `wanted · +12 %` and opens
  the request's tray.

### 3.4 "At which time" — the best-time hint [OWNER; DEFAULT: the threshold]

For every Sell at row the server finds when the estimated **bid** peaks between your arrival and the
end of the horizon; for the docked city on Buy at, when the estimated **ask** bottoms out. The row shows
`best 19:10 +2 %` only when the estimate's expected gain at that time is larger than the band's
half-width at that time — otherwise the honest answer is *"no better time; it is as likely to fall as
to rise"*, and the row shows nothing. The chart marks the best time with ◆.

This is mostly about **waiting in port**: a 1,500-mile voyage is about 15 real minutes (§4.1), so the
arrival is usually within the first price move or two, and the gain comes from the parts that are
certain — a city whose stock is low refills over the next few game days and its price falls; a drift
far from zero reverts toward zero by 10 % a slot (§4.3).

### 3.5 Plans — orders, routes, and the plan builder [OWNER: "buy and sell plans … setting up trade routes for my fleet"]

One face, three sections, top to bottom:

1. **Plan** (only when a draft exists): the plan builder's draft (below).
2. **Route** — today's `RouteFold` / `RouteEditor` / `RouteStop`, moved as they are.
3. **Orders** — today's `Queue`, moved as it is (cancel ✕, Clear).

**The plan builder** opens from **Plan** on a Buy at row, or from a Sell at row's tray:

```
 Plan · Coffee                                         ✕
 Buy at   Mocha ▾      60 units ▾    Max  95 🪙  ▾      ← the stepper's end is the stock
 Sell at  Lisbon ▾                   Min 140 🪙  ▾
 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
 Estimate   cost 5,640 🪙 · you get 8,460 🪙 · net +1,860 🪙   ← good_board's figures for these two
 Gaivota sails Lisbon → Mocha → Lisbon · 6.8 days · back 18:31
 [ Queue it once ]            [ Make it a route ]
```

- **Queue it once** issues, in one transaction, `SAIL Mocha` · `BUY coffee 60 AT <= 95` · `SAIL Lisbon` ·
  `SELL coffee ALL AT >= 140` through **`cmd.issue_lines`** (§7.4), each SAIL with its course from
  `proposeCourse`. All lines are queued or none is.
- **Make it a route** prefills the existing route editor's draft (`standingRouteDraft.ts`) with the two
  stops and the two lines (Buy: units, Max; Sell: Min — the editor's own fields) and opens Route. The
  route is saved by the existing `cmd.standing_route_save`.
- **A plan does not wait** (D6): at arrival, a price past the limit is refused like any order.
- The estimate is labelled **Estimate** and is the board's own figures; the real check is the order
  itself when it runs (`cmd.preview` cannot run a BUY at a city the fleet is not at, and the desk does
  not pretend it can).
- **One good, one buy city, one sell city** [DEFAULT]: the builder answers your coffee example. A loop
  of several goods or cities is the route editor's job, and the builder hands off to it.

### 3.6 City [OWNER: "and all"]

A second `Segmented` row inside the face: the buildings the city has, PORT's `PORT_FACES` table moved
unchanged (`Town · Storage · Craft · Inn · Build · Repair · Skills`, each offered only where the building
stands) plus **Requests**. The face is about the city the fleet is docked at, or bound for (read-only,
§2.1). A fair runs → one accent row at the top. **There is no port field** on this face: the desk reads
other cities through the good page, and the map reads any city.

### 3.7 Invest [OWNER: "investing"]

1. **Your holdings** (new read `world.holdings()`): one row per (city, work) you hold — shares, what a
   share is worth today, coupons paid in the last full day, the city's purse state. Totals at the head:
   `Held 42,000 🪙 · paid 380 🪙 yesterday`. A row opens that city on the map's Town Hall.
2. **Here** — the docked city's Town Hall (`CityTownHall`, moved to `src/live/` so the map and the desk
   compose one file): treasury, works, **Invest** (docked only — `cmd.invest` refuses `E_NOT_DOCKED`;
   kept [DEFAULT, the server's rule]) and **Donate** once INFLUENCE I2 is live.

### 3.8 Profit [OWNER: "for max profit"; DEFAULT: the figures]

New read `world.books(p_days)`: per day (game-calendar days, newest first) and per fleet — sold, bought,
supplies, wages, repairs, port fees, profit tax, invested, coupons, **net**. The head: `Today +2,140 🪙 ·
7 days +18,900 🪙`, with a 7-bar chart (one bar per day, `success`/`danger` by sign, no axis but zero).
A fleet row opens today's `TradeHistoryPanel` for that fleet (laps, stops, lines). Routes show their
last lap net (already served by `world.standing_routes`).

### 3.9 The layout: a trading terminal (2026-10-18) [OWNER: "it will be like stock trading screen"]

This section **supersedes §3.1's desktop sketch and §5.5–5.6's column table.** On his own screen
(Chrome, DPR 2, 1440×731) the owner saw the desk as a phone list: a ~750-px column with half the glass
empty until a good was pressed, a 360-px chart in a tray, and Buy at / Sell at below the fold inside a
second scroll. Then: *"wtf what about the command tab? huh?"* and *"i don't see stock of the trade goods
so there needs fixing"*. The model is a broker's terminal (TradingView, Bloomberg): a watchlist, a chart
and an order ticket side by side, using the whole glass.

```
 WIDE (≥ 1024 px — WIDE_QUERY), the Markets face — 1440 × 731 shown
 ┌ Command  [⚑ Gaivota · Lisbon]  Supplies 15.0 days  Cargo 4 / 60 t ▬▬   [Markets◆|Plans|City|Invest|Profit] ┐
 ├ WATCHLIST 17–22 rem ─┬ CHART (the rest) ──────────────────────────────────┬ TICKET 20–25 rem ──────────┤
 │ 🔍 Search goods       │ ☕ Coffee ◇                         Stock · normal │ BEST TRADE      for 39 u  │
 │ [All◆][Here][On b.]…  │ ⚑ Mocha · market price             ▬▬|▬ 240 / 300 │ Buy  ⚑ Mocha     94 🪙    │
 │ [Name|Change|Price]   │ 94 🪙  +4.1 % · 12 h                              │ Sell ⚑ Lisbon   141 🪙    │
 │ ☕ Coffee   ╱╲╱  112  │ [⚑Mocha◆][⚑Aden][⚑Lisbon]…           [1h|6h|12h◆] │ Net / t   Net, the hold   │
 │   ▬|▬ 240/300 +4.1 % │ ┌────────────────────────────────────────────────┐ │ +31 🪙    +1,860 🪙       │
 │ 🌶 Pepper  ‾╲_  149  │ │ record ─── now ● estimate ┄┄ band ░░  ◆ best   │ │ 3.4 days · arrive 17:52 · │
 │ …  (own scroll,      │ │ ┆ arrive                                       │ │ best to sell 19:10 (+2 %) │
 │    thin bar)         │ │ normal ┄┄┄┄┄┄┄ stock ▁▂▃▅▆ (info) ┄┄ (est.)   │ │ [Buy here]  [Plan trade]  │
 │                      │ └────────────────────────────────────────────────┘ │ Buy at   price·stock·away │
 │                      │ ◆ Best time to sell at Lisbon: 19:10 · 144 (+2 %) │ Sell at  you get · net/t  │
 │                      │ If nobody else trades here, likely 88–101 at …   │ … (own scroll)            │
 └──────────────────────┴────────────────────────────────────────────────────┴───────────────────────────┘
```

- **One header line** (the old fleet strip's 52 px and the faces' 44 px folded into one 60-px bar):
  the fleet chips, the two figures, the faces.
- **Three panes, each with its own scroll** and a thin, quiet bar (`.bv-scroll`, `src/index.css`). This
  replaces §5.5's "no inner scroll box". The panes sit side by side, so the Best trade card stays
  above the fold while the list is read; on a terminal a pane that scrolls on its own is the norm.
  Sideways chip rows draw no bar at all (`.bv-scroll-x`).
- **Nothing chosen yet → the list's first good is shown.** The centre and the right are never empty.
  The row takes the wash as if pressed; the store is not written.
- **The ticket pane is THE SLOT.** The plan builder and the trade tray stand in it (`Tray
  mode="pane"`), and closing them gives the ticket back. The chart and the list do not move.
- **Best trade** is the board's own first answer, printed whole (§7.2): buy at `qty.bought_at` (or what
  is on board), sell at the first sell row. The board sorts by net, server-side, so the client ranks
  nothing.
- **The chart** fills its pane, measured with `ResizeObserver`, so the SVG's units are screen pixels and
  its labels keep their true size. The history window is 1 h / 6 h / 12 h (the served record, cut).
  The city chips carry flags. ◆ marks the best time, and a line under the chart names it.
- **Stock** [OWNER 2026-10-18]: every watchlist row, every Buy at / Sell at row, the chart head, the City
  face's trade board and the map city panel's Market tab draw ONE component, `StockGauge`. It shows
  `240 / 300` and a thin bar whose tick is the normal level (`stock_target`). Low stock (scarce, so
  dear) reads `danger`; high (plenty, so cheap) reads `success`; within a third of normal reads quiet.
  The chart has a **stock strip** under the price on the same time axis, with the normal level
  dashed: the reason the price moved. Served by 0183.
- **At sea**: the board runs from the nearest harbour (0183). Sell at says so in one line (`At sea:
  reckoned from Lisbon, 20 miles off`), and no row is bare.

**Phone (< 1024):** unchanged in shape: the Sheet, the list, and the good's page as a tray at full. The
tray holds the chart first, then the ticket (Best trade, Buy at, Sell at), so the same two halves stack.
No sideways scroll.

**Not built here, and why:** a *best-margin* column on the watchlist. It needs every good's dearest
buyer: about 132,000 market prices a read (measured 12.5 s on the local engine). That is a server
precompute at the market tick, which is a slice of its own.

---

## 4. The estimate — what it is, exactly

### 4.1 Time, measured from the live knobs

| Clock | Real time | Source |
|---|---|---|
| a price move (drift slot) | **15 min** | `drift_slot_seconds` 900 |
| a stock refill step (game day) | **48 min** | `game_day_seconds` 2,880 |
| a voyage day | **90 s** | 86,400 / `time_compression` 960 |
| 1,500 miles at 6 knots | 250 voyage hours = **≈ 15.6 min** | `t_real = hours × 3600 / 960` (DESIGN.md:126) |

### 4.2 The parts that are certain — computed exactly, server-side

For slot `k = 0 … H` ahead (instant `t_k`), with every term read by `world.mid_terms` once:

- **stock** `s_k` = the regeneration rule applied over the game days between now and `t_k` — the
  **same expression** the tick uses, moved into one leaf `public.stock_after(stock, target, rate,
  production, days)` that both the tick and the outlook call (the tick is re-cut onto it, byte-parity
  asserted). Trades are not assumed (D5).
- **season** `season_mod` as it stands (0 today). The day a season curve over time is authored, it gets
  one reader `public.season_at(port, good, t)` and both the tick and the outlook call it; until then the
  outlook reads the column, like the price does.
- **development** constant over the horizon (`dev_commerce` changes only when a city grows).
- **drift, expected**: `E[d_k] = θ^k · d_0` (θ = 0.9 per slot).

The estimated mid at `t_k` is `world.mid_from_terms(…, s_k, E[d_k], season, dev, …)` — the one price
expression, never a second spelling. The ask/bid at `t_k` applies today's effective spread, tax and city
bid factor (held constant over the horizon [DEFAULT, stated in the payload]; a fair whose window is
already drawn in `active_buffs` is returned as an event to mark, not folded into the line).

### 4.3 The part that is random — the band

The drift is an AR(1) walk: `d_{k+1} = θ·d_k + σ·ε`. Its spread after `k` slots is

```
sd_k = σ · sqrt( (1 − θ^(2k)) / (1 − θ²) )        σ = 0.02, θ = 0.9  →  sd_∞ = 0.0459
k = 1 (15 min) 0.020 · k = 4 (1 h) 0.035 · k = 8 (2 h) 0.041 · k = 24 (6 h) 0.046
```

The band at `t_k` is the price expression evaluated at `E[d_k] ± z·sd_k`, clamped to ±`drift_clamp`,
with `z` = 1.2816 for 80 % (D3) — so on a 100 🪙 good the band is about **±4.4 🪙 after an hour and ±5.9 🪙
at six hours**. These moments live in one leaf `public.drift_moments(d0, k)` beside the tick that
steps the walk, reading the same three knobs; a self-assert runs the tick's own step a few thousand
times on probe rows (rolled back) and checks the observed mean and spread against the leaf.

### 4.4 What the estimate is worth, measured on the knobs

- **Mean reversion is real and plannable.** A good whose drift is +15 % now is expected at +9.8 % in
  one hour and +1.2 % in six: a sell price ~13 % lower by evening, well outside the band.
- **Refill is real and plannable.** A city at half its stock target prices the good ×1.41 (elasticity
  0.5); after one game day ×1.32, after three (2.4 h) ×1.20.
- **Pure noise is not.** Where neither applies, the estimate is flat and the band is the honest
  answer; the best-time hint is suppressed (§3.4).

---

## 5. Visual specification

### 5.1 Posture [OWNER: "stylish - modern - sophisticated yet concise simple"]

The reference is a broker's app (Robinhood / Trade Republic: one headline figure, one line, two big
actions) laid on the game's existing instrument language (`docs/UI_DIRECTION.md` §4): flat translucent
sheets, one family, figures as the loudest thing, colour only for meaning. Concise means **one figure
per row is loud**, everything else is `ink-muted` at `t-label` or `t-caption`. No ⓘ, no sentences
explaining a figure, no boxes around sections.

### 5.2 Type — the existing scale, nothing new (`src/index.css` `--text-t-*`)

| Use on the desk | Token |
|---|---|
| fleet strip, row names, button text | `t-body` 16/22 · 500 |
| row sub-lines, column heads (`price · stock · away`) | `t-caption` 12/16 · 500, `ink-faint` |
| list figures (price, net per ton) | `t-body` tabular |
| a block's one figure (net of a plan, today's profit) | `t-figure` 24/28 · 600 tabular |
| the good page's price | `t-hero` 34/38 · 600 tabular |
| change chips (`+4.1 %`) | `t-caption` on `success-soft` / `danger-soft`, radius 999 |

Every figure through `Figure` (tabular-nums). Units through `src/lib/format` only (`🪙`, `units`, `tons`,
`days`, clock times through `formatRealShort`).

### 5.3 Colour — the existing tokens (both schemes; the Menu's Appearance and `prefers-color-scheme` pick)

| Meaning on the desk | Token (dark / light) |
|---|---|
| ground, sheet, inset | `bg` #0A1018 / #EEF2F6 · `surface` #131C27 / #FFFFFF · `surface-2` #1B2634 / #F2F5F8 |
| hairlines between rows, chart axes | `edge` (8 % / 14 %) |
| yours / may act: selected row wash, Buy, Queue, the docked city, the recorded price line | `accent` #E2B45C / #8A6011 and `accent-soft` |
| gain / cheaper-than / profit | `success` #4FCB8B / #12874D |
| loss / dearer / a losing net | `danger` #F0655A / #C13636 |
| moving: sailing line, your arrival marker on the chart | `info` #6AA9F5 / #215FC0 |
| short, fair on, best-time hint | `warning` #F2B84B / #96660C |
| the estimate's band | `ink-faint` at 12 % (it is uncertainty, not yours and not a gain) |

The map's day/night (NOAA sunlight) is the **map's** layer; the desk follows the app scheme only. No new
tokens are needed; a spec (`tests/duplication.spec.ts` §1) already fails on a literal colour.

### 5.4 Charts — no library [DEFAULT: none needed]

`package.json` has no chart library and does not need one: `PriceChart` / `priceChartModel` is already a
pure model + SVG painter with served axes. The desk **extends that one model** rather than adding a
second chart:

- `priceChartModel(points, slotSeconds, nowMs, outlook?)` gains an optional served outlook
  `{points:[{at, mid, lo, hi}], arrive_at, best_at, events}` and returns the extra paths (the dashed
  estimate, the band polygon) and marks (◆ best, ┆ arrive, fair window as a 4-px `warning` rule on the
  x axis). One model, one painter, both callers (the tray chart and the good page).
- **Sparkline** in the list: unchanged component, 56×20, 1.5-px stroke in `ink-muted`, no fill, no dot.
- **Good page chart**: full width of its column, 200 px tall on a phone, 280 px wide-screen. Recorded
  line 2 px `accent` with an `accent-soft` area fading to transparent; estimate 2 px dashed `accent` at
  60 %; band `ink-faint` 12 %; *now* as a 6-px `accent` dot on a 1-px `edge` vertical; three y labels
  (min, mid, max of everything drawn, history and band together), x labels `−12 h · now · +6 h`. No
  grid, no legend box, no shadows, no 3-D, no animation beyond the 180 ms fold.
- **Scrub** [DEFAULT]: press-and-drag (hover on desktop) reads a point; the **hero figure** shows the
  scrubbed value and time in place, so the readout never covers the chart and nothing moves.
- **Profit bars**: 7 bars, 8 px gap, radius 3 top only, zero line `edge`, figures only on the first and
  last bar.

### 5.5 Space and density

The existing 4-pt scale: gutter 16, row 52, section gap 24, control gap 8. Watchlist: ~13 rows on a
390×844 screen below the fleet strip and faces. Wide columns: 340 · flexible (min 480) · 360; the
watchlist and ticket columns scroll with the page (no inner scroll box — reach law, `CORE_REUSE` §1.5).

### 5.6 Phone vs wide

*Superseded by §3.9 (2026-10-18): from 1024 px the Markets face is the three-pane terminal; the table
below is the plan as first written.*

| | Phone (< 768) | Tablet (768–1279) | Wide (≥ 1280) |
|---|---|---|---|
| watchlist | the face | left column | left column |
| good page | `Tray` docked, detents peek / half / full, opens at **full** | middle column | middle column |
| trade tray / basket / plan builder | `Tray` docked over the page | `Tray mode="side-next"` beside the page | the right column (ticket), always present: the basket when nothing is open |
| fleet strip figures | in the chip's tray | on the strip | on the strip |

### 5.7 Interaction rules [OWNER — `dont-restructure-on-press`, rows 6/15/25/28/45]

1. **A press selects.** A row, chip, filter or focus city changes what is shown **in its own slot**;
   nothing above the press moves, nothing collapses, nothing docks and follows the scroll.
2. Things **appear** only in a tray (phone) or the next column (wide). Closing a tray returns the exact
   page it rose from, at the same scroll.
3. **Appending below is allowed** (*All 231 cities*), inserting above is not.
4. A control is busy **only while its own press is on the wire** (`usePress`, owner row 107); a
   background re-read never greys anything.
5. Every action has a 44-px target; icons carry `aria-label`.

### 5.8 Loading and refresh

- **First load**: `Skeleton` rows at the final row height (52) and a skeleton chart at the final chart
  size, so the page does not jump when data arrives.
- **Re-asks keep the old figures drawn** until the new answer lands (the PR #59 lesson: a 3-s re-ask
  blanked the tray). A stale figure is never dimmed for a re-ask.
- **Cadence**: the watchlist and an open good page re-ask at the market's own edge
  (`clock.next_change_at`, 0029 — the existing `reaskAtEdge`), not on the 30-s world beat; a trade or a
  fleet change re-asks the good page once.
- A refusal is a `Note` with the server's sentence and one **Try again**.

---

## 6. The concepts, planned before the code (NO_SPAGHETTI §7B)

| Concept (one noun phrase) | Lives | Why there | Second caller | Wrong shape if… / guard |
|---|---|---|---|---|
| **a good's estimated price path** | `world.price_outlook` (PL/pgSQL), composing `world.mid_terms`, `world.mid_from_terms`, `public.stock_after`, `public.drift_moments` | the server owns every price; the terms are already read there | `world.good_board` (arrival estimate, best time), the tray chart | …the client multiplied anything, or the tick and the outlook spelt regeneration twice. Guard: the tick is re-cut onto `stock_after` with byte parity; a self-assert compares the outlook's k = 0 point with `world.price` to the cent; `tests/duplication.spec.ts` forbids `drift_theta`/`stock_regen` in `src/` |
| **one good, every city** | `world.good_board` | money is the quote's; distance is the reach table's | the plan builder's estimate | …a net that differs from the quote. Guard: self-assert recomputes 20 rows through `world.quote` + `profit_tax` + `crew_wages` |
| **the list of goods with a price each** | `world.watchlist` | one read for 555 rows; set-based mid through the one expression | Markets only | …it priced asks one city at a time (1.3 s measured). Guard: timing notice in the self-assert (< 150 ms on the built world) |
| **several orders queued as one** | `cmd.issue_lines` wrapping `cmd.enqueue` | `cmd.enqueue` is already the one enqueuer (0092) | none today; the route renderer stays on `cmd.enqueue` | …it parsed or executed anything itself. Guard: it calls `cmd.parse` and `cmd.enqueue` per line inside one savepoint and nothing else |
| **what you hold in cities** | `world.holdings` | shares are `city_shares` (0123) | Invest only | …it re-derived a share price. Guard: the price is `world.town_hall`'s leaf |
| **the running profit** | `world.books` | the ledger is the record (`public.ledger`, append-only) | Profit; History could adopt it | …a counter column. Guard: derived per read, never stored (the 0014 rule) |
| **which good is open on the desk** | `src/store/deskGood.ts` (session) | two writers on day one: the watchlist and the map's Market tab hand-off | the map | …a prop chain. Guard: `sections.spec` (store has one entrance) |
| **which city the desk reads** | `src/store/harbour.ts` (existing, reused) | it is already "which harbour is read" | the map | …a second harbour store |
| **the plan being made** | `src/store/planDraft.ts` (session) | a draft, like `domain/order`'s and `standingRouteDraft` | none; it hands off to the route draft | …it duplicated the route draft's fields. Guard: "Make it a route" writes `standingRouteDraft` and clears itself |
| **which face is up** | `src/features/command/deskView.ts` | chrome of one screen (PORT's `portView.ts` pattern) | none | — |

---

## 7. Server work list

All reads are `STABLE SECURITY DEFINER`, `search_path = public, pg_temp`, granted to `authenticated`,
registered in `public.client_rpc_entry_points()`, and refuse a fleet that is not yours `E_NOT_YOURS`
(the `world.trade_routes` rule). Each migration sets nothing in the game's state and needs no switch,
except `cmd.issue_lines`, which is a verb (§7.4).

### 7.1 `world.price_outlook(p_port uuid, p_good uuid, p_slots int default null, p_side text default 'mid', p_fleet uuid default null) returns jsonb`

```
{ port, good, side, slot_seconds, now, horizon_slots, band: 0.80,
  assumes: 'no other trades; spread, tax and city purse as now',
  points: [{at, mid, lo, hi}]            -- k = 0..H, at the slot boundaries; side = mid | ask | bid
  best:   {at, value, gain_pct} | null,  -- only when the gain beats the band half-width (§3.4)
  events: [{kind:'fair', from, to}] }
```

- `H` = `coalesce(p_slots, outlook_slots)` capped at `outlook_slots_max`; knobs **`outlook_slots`** 24
  (D3), **`outlook_slots_max`** 96, **`outlook_band_z`** 1.2816 (D3).
- Cost: one `mid_terms` read, H+1 evaluations of an inlined SQL expression, one spread/tax/bid read for
  ask/bid — well under 5 ms.
- New leaves (same migration): `public.stock_after(...)` — the tick's regen UPDATE re-cut onto it
  (sliced from the live body, LF-normalised, the hunk asserted to occur exactly once, the live body
  reversing to its pre-image byte for byte — the 0137 method); `public.drift_moments(p_d0, p_k)` →
  `(mean, sd)`.
- **Also in this migration:** delete the 61,824 stale `price_history` rows (`slot >
  drift_slot_of(now())`, §1.3) and assert none remain.

### 7.2 `world.good_board(p_good uuid, p_fleet uuid, p_from uuid default null, p_qty numeric default null) returns jsonb`

```
{ good, fleet: {id, where, speed_kn}, qty: {units, basis: 'on_board' | 'capacity' | 'asked'},
  buy:  [{port, ask, stock, nm, days, arrive_at, outlook_at_arrival:{ask, lo, hi}, best:{…}|null}],
  sell: [{port, bid, nm, days, arrive_at, proceeds, cost, profit_tax, port_fee, wages, net, net_per_ton,
          cap_left, best:{at, bid, gain_pct}|null, request:{premium_pct, expires_at}|null}],
  clock: {now, next_change_at} }
```

- **From where:** a good on board sells from the fleet's position (bound-for city + the miles left);
  otherwise from `p_from`, or the buy row with the best net, and `days` is fleet → buy city → sell city.
- **Money:** buy cost through `world.quote(…, 'buy', …, p_fleet)`, or `fleet_cargo_basis` for cargo on
  board; proceeds through `world.quote(…, 'sell', …, p_fleet)`; `public.profit_tax(port, profit)`; the
  port fee is the quote's own `spread_total`; wages `public.crew_wages(crew, short) × days`;
  `world.daily_cap_remaining` as `cap_left` (a sale over the cap is refused whole, `TRADE_ROUTES` §1).
- **Distances:** `voyage.reach_from(port)` (the sailed-distance table, 252 rows, 1.6 MB on prod) — one
  row per origin, so at most two reads per call.
- **Best time:** `world.price_outlook`'s arithmetic over each row's `[arrive_at, horizon]`, called as
  the leaf, never re-spelt.
- **Cost, against the measurement (§1.4):** a naive 238 × `world.quote` is **~0.4 s**. The plan, in the
  0053/0136 shape ("read it once"): the quote's per-call preamble — the row's terms, the effective
  spread, the city's bid factor, the knobs — is generalised into one leaf that reads them **for a set of
  ports in one statement**, and `world.quote` is re-cut to call that leaf for its one port (byte parity
  on 200 sampled quotes, the 0122 pre-image method). The step walk stays `world.quote`'s. Target
  **≤ 150 ms** on the built world (238 × 555), asserted as a timing notice; if the leaf cannot reach it,
  the fallback is stage 1 = every city's first-step bid (cheap, set-based) and stage 2 = the full quote
  for the top 12 and any city the player taps — `world.trade_routes`' own two-stage shape. D2's
  architect pass measures before choosing.
- `world.trade_routes`' stage 2 is re-cut onto the same leaf (it is the second reader of "the money of
  carrying a good from A to B"), so there is one authority, not two.

### 7.3 `world.watchlist(p_fleet uuid default null) returns jsonb`

```
{ clock, goods: [{code, name, category, rarity, sellers, best:{port, mid}, change_pct,
                  spark:[mid × 12], on_board, wanted_at:[port codes]}] }
```

- Live mids set-based through `world.mid_from_terms` with the knobs read once (the `world.market`
  `knobs as materialized` pattern) over the 1,348 sold pairs; the cheapest per good; its last 12 hourly
  recorded mids (the 12-h scan measured **61 ms** for every pair); `change_pct` against the oldest of
  those.
- Payload: 555 rows, roughly 90 KB of JSON (estimated; measured in D2). Asked when Markets opens and at the market's
  edge (every 15 min), never on the beat.

### 7.4 `cmd.issue_lines(p_fleet uuid, p_lines jsonb, p_expected_version int) returns jsonb` — a verb

`p_lines = [{text, path}]` (path = a SAIL's proposed course). One savepoint: `cmd.parse` each line,
`cmd.enqueue` each, version check once, `cmd.advance` once at the end — **all queued or none** (a parse
or queue-full refusal names the line). Cap: the existing `order_queue_max` (12). No new executor, no
new grammar. Dark switch: none needed (it can only do what N separate `cmd.issue` calls already do);
it is registered like `cmd.issue`.

### 7.5 `world.holdings() returns jsonb` and `world.books(p_days int default 7) returns jsonb`

- **holdings:** the caller's `city_shares` grouped by city and work, the share value and coupon from
  `world.town_hall`'s own leaves, the city's purse state. ~tens of rows; < 10 ms.
- **books:** `public.ledger` for the caller, grouped by game-calendar day and kind and fleet, for
  `p_days` (cap 30); kinds mapped once in the function; `net` = the sum. D7's architect pass checks the
  ledger's index for (player, time) before costing it; a week is a few hundred rows per company.

### 7.6 Client contract

Each read gets a `catalog.ts` entry and a type in `src/lib/rpc/types.ts` (split by aspect, if cleanup
slice 7 has landed), a hook through `useServedRead` (`useWatchlist`, `useGoodBoard`, `usePriceOutlook`,
`useHoldings`, `useBooks`) in `src/live/`. No figure is computed on the client (`worldStore` rule 3).

---

## 8. Client modules

```
src/features/command/
  CommandScreen.tsx      the desk shell: fleet strip, faces, the slot (≤ 250 lines)
  deskView.ts            which face; filters; sort (session store; PORT's portView pattern)
  FleetStrip.tsx         the chip + where line + (wide) the two figures
  markets/
    Markets.tsx          the face: search, chips, sort, the list
    WatchRow.tsx         one good (name, sparkline, figure, change)  — `Row` + `Sparkline`
    GoodPage.tsx         hero, focus chips, chart, Buy at, Sell at (Tray on phone, column on wide)
    BuyAt.tsx · SellAt.tsx
  plans/
    Plans.tsx            Plan · Route · Orders
    PlanBuilder.tsx      the draft and its two commits
    (Queue.tsx, RouteFold.tsx, RouteEditor.tsx, RouteStop.tsx, standingRouteDraft.ts — moved here)
  city/
    City.tsx             the building strip and the docked/bound-for rule
    (PortTrade, PortTown, PortFair, PortStorage, PortWorkstation, PortYard, PortShipyard, PortAcademy,
     FulfilTray, ManifestPanel, ManifestTotals, ReceiptFace, HaggleThread, OnBoard, useHaggleState —
     moved from features/port, renamed only where the word "Port" is now wrong)
  invest/Invest.tsx · profit/Profit.tsx
src/store/deskGood.ts · src/store/planDraft.ts
src/live/CityTownHall.tsx (moved from features/map) · useWatchlist.ts · useGoodBoard.ts · usePriceOutlook.ts · useHoldings.ts · useBooks.ts
src/components/ui/priceChartModel.ts · PriceChart.tsx (extended with the outlook)
```

`docs/SECTIONS.md` gains nothing new: these are features over live over components, the existing
layering. `features/command/README.md` is rewritten (its "the verbs left this screen" banner is
history, §2).

---

## 9. Words (added to `docs/WORDS.md` with D3)

| Concept | Say | Never |
|---|---|---|
| the tab | **Command** (unchanged) | desk, terminal, exchange |
| the faces | **Markets · Plans · City · Invest · Profit** | Port (the tab is gone), Services, Books |
| the list | **Markets** · column head **Market price** | watchlist, ticker |
| where a good is sold | **Buy at** | sources, suppliers |
| where it is bought | **Sell at** | buyers, destinations |
| profit after costs, per ton | **net per ton** (`+31 🪙 / ton`) | margin, spread, P/L |
| the estimate | **Estimate** · `likely 88–101 🪙 at 17:40` · `If nobody else trades here` | forecast, prediction, projection, confidence interval |
| when it peaks | **best 19:10 +2 %** | optimal, ideal |
| arrival | **arrive 17:52** | ETA |
| a plan | **Plan** · **Queue it once** · **Make it a route** | strategy, template, order (that is a queued line) |
| where the fleet is | **Docked at Lisbon** · **Sailing to Cádiz · 12 min** · **Anchored** | alongside, at sea (alone), en route |
| your shares | **Your holdings** · `Held 42,000 🪙` | portfolio, positions |
| the running total | **Profit** · `Today +2,140 🪙 · 7 days +18,900 🪙` | P&L, books, earnings |

---

## 10. Slices

Every server slice follows `docs/DEPLOY_RUNBOOK.md` (unwind → push → wind → merge at once; client never
ahead of the DB), hunks sliced from the LIVE body and asserted exactly once, self-asserts on their own
throw-away houses (`new_house`), never a live fleet. CI is scoped (`docs/CI.md`): each spec **names the
functions its slice defines** so rule S selects it; a migration also selects `db.chain.spec` and
`db.image.spec`.

| # | What | Proof | Dark switch | Specs |
|---|---|---|---|---|
| **D1** · migration `a_price_says_where_it_is_going` | `public.stock_after` (+ tick re-cut, byte parity), `public.drift_moments`, `world.price_outlook`; knobs `outlook_slots` 24, `outlook_slots_max` 96, `outlook_band_z` 1.2816; delete the 61,824 stale history rows | (a) the tick reverses to its pre-image; (b) on a probe market row, k = 0 equals `world.price` to the cent for mid/ask/bid; (c) the deterministic path equals the tick run over N game days with drift held at 0 (rolled back); (d) 4,000 tick steps on probe rows: observed mean within 3 SE of `drift_moments`, and 80 % ± 3 % of draws inside the band; (e) no history row has `slot > drift_slot_of(now())`; (f) registered, granted, `anon` refused | none (a read; the history delete is a repair) | `tests/rpc.outlook.spec.ts` (names `price_outlook`): shape, k = 0 parity, the band widens, `best` null on a flat row |
| **D2** · migration `one_good_every_city` | the quote preamble leaf (+ `world.quote` and `world.trade_routes` re-cut, parity on 200 sampled quotes), `world.good_board`, `world.watchlist` | (a) 20 sell rows recomputed by hand through `world.quote` + `profit_tax` + `crew_wages` equal the board; (b) a good on board uses `fleet_cargo_basis`; (c) another house's fleet → `E_NOT_YOURS`; (d) timing notices: `good_board` and `watchlist` on the built world (target ≤ 150 ms each) | none | `tests/rpc.goodBoard.spec.ts` (names `good_board`, `watchlist`) |
| **D3** · client | the desk shell (fleet strip, faces), **Markets** (watchlist, filters, good page, chart with outlook, Buy at / Sell at, Buy cell → the existing trade tray), **Plans** = today's Route + Orders moved, `deskGood` store, map Market → desk hand-off. PORT still stands | driven on a canary world (the throwaway-world recipe in `docs/DEV_LOG.md`, 2026-09-09; localhost is the live game): press Coffee → chart, Buy at, Sell at; buy through the cell when docked | none (it adds a face; PORT is untouched) | `tests/desk.layout.spec.ts` (390×844 and 1440×900: row 52, targets 44, nothing above a press moves, no horizontal scroll), `tests/priceChart.spec.ts` (outlook paths, band, marks), `tests/words.spec.ts` (new NEVER words) |
| **D4** · migration `several_orders_are_one` + client | `cmd.issue_lines`; the plan builder (Queue it once / Make it a route) | (a) four lines queue atomically; (b) a bad third line queues none and names it; (c) queue-full refuses whole; (d) the queued lines run through `cmd.advance` exactly as typed ones | none | `tests/rpc.issueLines.spec.ts`, `tests/desk.plan.spec.ts` |
| **D5** · client | **City** face: every PORT building face moved under `features/command/city/`, the docked/bound-for rule, Requests; `verbHomes.spec` rewritten to §2.2. PORT now composes the moved files (transitional: two doorways, one component each, until D8) | every verb in §2.2 driven once on the canary from COMMAND | none | `tests/verbHomes.spec.ts` (rewritten), `tests/layout.spec.ts` (port ids retargeted to the City face) |
| **D6** · migration `what_you_hold` + client | `world.holdings`; **Invest** face; `CityTownHall` moved to `src/live/` | holdings equal `city_shares` × the hall's share value on a probe house | none | `tests/rpc.holdings.spec.ts`, `tests/map.townhall.spec.ts` (still green after the move) |
| **D7** · migration `the_books_add_up` + client | `world.books`; **Profit** face | a probe house's buy + sell + wages: the day's `net` equals the purse change | none | `tests/rpc.books.spec.ts` |
| **D8** · client — **LAST** | **Delete PORT**: `src/features/port/` (what was not moved), `/port` route (redirect → `/command`), `navTabs.ts` row, `TRADE_ROUTES = ['/command']`, `MerchantsHere`; `nav.geometry.spec` to four cells; OWNER_REQUESTS rows 55, 64, 73 marked REVERSED BY row 137 | **gate:** `verbHomes.spec` passes with `src/features/port/` absent — every verb in §2.2 has a home on COMMAND; driven on the live site after deploy | none (deletion; fix by deletion, never behind a flag — NO_SPAGHETTI §5) | `tests/nav.geometry.spec.ts`, `tests/verbHomes.spec.ts`, `tests/sections.spec.ts` |

**Order and dependencies.** D1 → D2 → D3 (D3 needs both reads). D4, D5, D6, D7 are independent after D3
(disjoint files: `plans/`, `city/`, `invest/`, `profit/`) and can run as parallel implementers in their
own worktrees. D8 only after D5 (and after D4/D6/D7 if the owner wants every face before the tab goes).
INFLUENCE I2's Donate lands in the Invest face whenever I2 is live; nothing here waits for it.

---

## 11. What this plan does not do

- **No WAIT verb** (D6) and no resting orders on the server; a limit is checked when the line runs.
- **No forecast of other traders** (D5); the band is the drift's alone.
- **No second price expression, regen rule or quote** anywhere: every number is a composition of the
  existing authorities, and the two new leaves are extractions the tick itself is re-cut onto.
- **No chart library**, no new colour tokens, no new type sizes.
- **No change to the map** beyond the Market tab's hand-off; the map still orders SAIL.
- **No change to FLEETS** (fit/unfit stay on the ship panel).
