# 2026-10-18 — COMMAND DESK D3: the desk (client) — `osn-desk-d3`

`docs/COMMAND_DESK.md` §3.1–3.5, §5, §8, and §10 row D3. **Client only, no migration.** It reads `world.price_outlook`
(0170) and `world.good_board` / `world.watchlist` (0171), both live on prod. PORT still stands.

The owner, 2026-10-17: *"it will be like stock trading screen … seeing charts of each trade goods that i click …
stylish - modern - sophisticated yet concise simple."*

## What was built

- **The shell** (`features/command/CommandScreen.tsx`):
  - the fleet strip (`FleetStrip.tsx`: fleet chips, the where line, Supplies and Cargo);
  - the faces, Markets and Plans (`deskView.ts`). City, Invest and Profit join with D5–D7: a face that opens
    nothing is not listed.
  - **One slot** holds either the good's page or the trade tray it hands over to.
- **Markets** (`markets/Markets.tsx`, `WatchRow.tsx`): every good once.
  - The list is world.watchlist laid over the snapshot's catalogue.
  - Search; filter chips: All · Here (what the docked city sells, from `world.market`'s `offered`) · On board ·
    one per category; sort Name · Change · Price.
  - Each row (52 px) shows the mark and name, a sub-line (`3 cities · 20 on board · Wanted in Lisbon`), the
    record's sparkline, the market price and its change.
  - Skeleton rows hold their final height while the list loads.
- **The good page** (`markets/GoodPage.tsx`, a Tray: full height on a phone, beside the column on a wide glass):
  - **The hero:** the focus city's market price and its move.
  - **Focus chips:** the cities that sell it, plus a tapped sell city.
  - **The chart:** the record plus the server's estimate.
  - **The line:** *"If nobody else trades here, the price is likely 73.7–82.8 🪙 at 15:45."* The first clause is
    the server's `assumes`.
  - **Buy at:** price, stock, distance; the docked row carries **Buy**.
  - **Sell at · for N units:** the quoted rows, best net first. Each shows what you get, net per ton (green or red),
    days, `arrive 17:52`, `best 19:10 +2%` and `wanted · +12%`. **All N cities** appends the rest below. The docked
    row carries **Sell** when cargo is on board.
  - **Loading:** while world.good_board is asked (0.3–0.5 s on prod), every block stands as a skeleton at its final
    size. A re-ask keeps the old figures (shot `desk-good-loading-390.png`).
- **Trading from the desk** (`markets/DeskTrade.tsx`): Buy or Sell turns the slot over to **the** trade tray. That
  is the same tray, `useTrade` and door as PORT's board; closing it returns to the page.
  - The bargain thread and the basket stay on PORT until D5 moves the City face.
- **Plans** (`plans/Plans.tsx`): the route fold and the queue, moved onto their face unchanged. The plan builder
  comes in D4.
- **The chart** (`components/ui/priceChartModel.ts`, `PriceChart.tsx`): one model and one painter, extended rather
  than duplicated.
  - An optional served estimate draws as a dashed path from now, with its band (ink-faint at 14 %), the best time
    as a diamond (warning tone) and the arrival as a rule (info tone). The axis runs to `+Nh`.
  - The record may be empty: a city that does not sell a good keeps no record of it.
  - The y labels' decimals follow the drawn span. 1.20 · 1.30 · 1.40 and 98,000 · 99,000 · 100,000 both keep their
    meaning, so prices from ~1 to ~100,000 a unit read correctly once distance pricing lands.
  - Two x labels never overlap.
- **Numbers** (`lib/format`): `formatPrice` / `formatPriceFigure` (two decimals below 10, one below 100, none
  above), `formatPriceDelta` and `formatPctChange`. These are the one authority, used by the list, the page and
  the axis.
- **The reads** (`live/useDesk.ts`): `useWatchlist`, `useGoodBoard` and `usePriceOutlook` sit on `useServedRead`
  with a new `trigger` option. `useReaskAtEdge` moves the trigger when the served `clock.next_change_at` passes, so
  the reads are re-asked at the market's edge, never on the 3-s beat; world.good_board would cost ~0.4 s a beat.
  - A trade (the fleet's version), a chosen fleet or an amount is a new question, asked at once.
- **Catalogue:** `worldPriceOutlook`, `worldGoodBoard` and `worldWatchlist`, with their types and wrappers. The
  `rpc.surface.spec` pin moved with them.
- **The map hand-off** (`live/PriceTray.tsx`): a good's price tray on the map has **Open in Command**. It opens the
  good on the desk (`store/deskGood.ts`, the session store both writers use).
- **Words:** COMMAND_DESK §9 is in `docs/WORDS.md`. Its NEVER column is in `tests/words.spec.ts`: watchlist, ticker,
  forecast, prediction, projection, confidence interval, optimal, ETA, P&L, portfolio, margin.

## A red on main this fixes (found while verifying)

**What I found:** D1's repair (0170) deleted every price-record row numbered past the present slot. In a fresh world
that was **all** of them: the chain's only record was 0061's self-assert snapshot at `now() + 1 hour`. So after 0170
a fresh world has no record. The 0171 image holds 0 rows (measured), and `layout.spec` "PORT: the Trend row opens
the price chart" went red against the post-0170 image.

**What I changed.** The local backend now plays the snapshot job the way it already plays the arrivals job
(`lib/rpc/localBackend.ts`, "THE ONE PLACE THIS BACKEND PLAYS THE CLOCK"):
- Before a read of the record, it runs **`public.tick_price_snapshot`**, the same function prod's cron runs.
  `world.price_history` and `world.watchlist` read the record.
- It runs at most once every 30 s, and it is idempotent per slot.
- A window with nothing in it starts at the previous boundary and now.

The cloud backend is unchanged.

**Considered and dropped:** a migration that seeds a record into an empty world. A cached chain prefix would freeze
that record at its build time, so it would have gone stale (and red again) 12 hours later.

## Laws kept

- **A press selects.** The faces row stands in the body, not the sticky title bar. As a 44-px control in the title
  bar it made the bar 18 px taller, which covered the route editor's chips: a press then scrolled the sheet
  (`route.stopface.spec` caught it).
- **Every figure is served.** No price, net, band or best time is computed on the client.
- **`verbHomes.spec` rule 1:** the owner reversed row 73, so `DeskTrade.tsx` is the one named doorway. D5 rewrites
  the rule to §2.2.
- **Flags:** the `Flag` component (`osn-flags`) is not on main yet, so the rows print city names only. They should
  adopt it once it lands.

## Verify (once)

- Build (local PGlite): `tsc -b` and `eslint .` are clean.
- `desk.layout.spec` (new; 390×844 and 1440×900): 52-px rows, 44-px controls, no sideways scroll. A press opens the
  page and moves no row; a chart-city press moves nothing below the chart; Buy → trade tray → close → page. 4 passed.
- `priceChart.spec` (estimate, empty record, small and large scales, label room): 7 passed.
- Run against `localhost:4260`:
  - `layout`, `wide.layout`, `route.stopface`, `nav.geometry`: 23 + 8 passed after the fixes. The PORT Trend test
    passes again.
  - `rpc.surface`, `rpc.firstSession`, `flicker`, `firstRead.empty`, `primitives.geometry`, `trade.ceiling`,
    `verbHomes`, `sections`, `words`, `duplication`, `map.townhall`, `selection.lock`, `format`, `manifest.store`,
    `chart.ink`: 117 passed, then `flicker` and `verbHomes` passed after their Plans/doorway edits.
- Not run locally (CI runs them): the merchants-on map specs. Rule A selects every browser spec, because
  `components/ui` changed.
- Shots (local world, dark): `docs/dev-log/2026-10-18-command-desk-d3/desk-{markets,good,good-loading}-{1440,390}.png`.
  The local world has no snapshot history, so its sparklines are a dash until the record has two hourly points.
  Prod's record is full.
- Selection map: `desk.layout.spec.ts` is added to `tests/shard-weights.json`.
