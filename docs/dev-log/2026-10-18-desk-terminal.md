# 2026-10-18 — the COMMAND desk as a trading terminal (0183 + the client)

The owner, 2026-10-17: *"delete port tab, and focus on command tab. it will be like stock trading screen …
stylish — modern — sophisticated yet concise simple."* On 2026-10-18, on his Chrome (DPR 2, 1440×731),
the desk read as a phone list in a 750-px column. A fleet at anchor showed "—" for net per ton and
arrival on every Sell at row. Then: *"i don't see stock of the trade goods so there needs fixing"*.

## Part 1: migration 0183, `the_desk_reads_stock_and_the_anchor` (server, deploys first)

**Why the rows were bare.** `world.good_board` (0171) measures distances from the fleet's berth, or
from the port she is bound for. An ANCHORED fleet has neither, so `voyage.reach_from(null)` returns
nothing. Every row then has null miles, days, arrival and wages, so the net is null too.

**Fix, one hunk.** With no berth and no voyage, the board starts from the **nearest harbour** to her
position (great circle). The miles to that harbour are added up front, the way a voyage's miles left
are. `fleet.where` gains `via` and `miles_left`.

**Stock.** No desk read served a city's normal stock (`port_goods.stock_target`). Only `world.market`
had it. Keys added, and nothing removed:

| Read | Adds |
|---|---|
| `world.good_board` | buy rows: `stock_target`; sell rows: `stock`, `stock_target` |
| `world.watchlist` | `best.stock`, `best.stock_target` |
| `world.price_history` | each point's `stock` (the column the snapshot already writes) |
| `world.price_outlook` | each point's `stock` (`public.price_path`'s stepped stock) and `stock_target` |

**Proof.** The world image's PGlite run takes 2.4 s. The probe runs on its own house, docked at
Lisbon and then anchored off the Tagus bar, and is rolled back whole.
- At anchor the board runs from LIS (20 miles). All 10 quoted sell rows are complete. The old board
  had 10 bare rows (positive control). Anchored miles = docked miles + the lead on every row
  (0 off). The call took 212 ms.
- Stock: every sell row's stock and normal level equal `port_goods`, and every buy row carries its
  normal level. All 555 watchlist goods carry it. Outlook point 0 = the city's stock (673, normal 670).
- All four bodies reverse to their pre-images, and the ACLs are unchanged.

**Number.** 0183, after #220 (0182) and #219 (0183), which are in flight. Neither touches these
four functions.

**Not the owner's, to confirm.** The lead from an anchorage is a great circle, not a sailed course.
It is an estimate's figure.

## Part 2: the client, the trading terminal (merges only after 0183 is live)

The design is in `docs/COMMAND_DESK.md` §3.9.

**Wide (≥ 1024 px).** The Markets face is three panes that use the whole glass:
- **Watchlist** on the left: search, filter chips, sort, and rows with mark, stock gauge, sparkline, price and move.
- **Chart** in the centre: a big chart with the good, the city (flag), the price, its move and the stock. It has
  city chips with flags and a 1 h / 6 h / 12 h window. The plot shows the record, the estimate, the band,
  ◆ best and the arrival, with a **stock strip** under it (the normal level dashed). Under the chart,
  the best time and the likely range.
- **Ticket** on the right: the Best trade card (buy A for X, sell B for Y, net per ton and for the hold,
  days at sea, arrival, best time to sell, then Buy here / Plan this trade), and the Buy at and Sell at
  ladders below it. The plan builder and the trade tray stand in this pane (`Tray mode="pane"`).

Fleet, figures and faces sit on one header line. Each pane scrolls on its own with a thin bar
(`.bv-scroll`), and chip rows draw no bar (`.bv-scroll-x`). With nothing chosen, the list's first
good is shown.

**Phone.** The same Sheet. The good's tray holds the chart, then the ticket.

**Stock: one component.** `StockGauge` shows `240 / 300` and a thin bar whose tick is normal. Low
stock reads danger, high reads success. It is drawn on:
- the watchlist rows and the ladders;
- `TradeRow`, which is both the City face's trade board and the map city panel's Market tab (it
  replaces the tide-in-range bar);
- `PriceRows` "In stock".

**Shared reads.** `useGoodDesk` reads the good once for both halves. `useMarketRows` reads the list once
for the list and the terminal's default.

**Not built:** the best-margin watchlist column. It needs every good's dearest buyer, about 132k mids
a read (12.5 s measured on PGlite), so it needs a precompute at the market tick. That is its own slice.

**Verified once (local canary build, localhost:4330):**
- `tsc -b` and eslint are clean.
- Playwright: desk.terminal (new), desk.layout, desk.plan, priceChart, layout, wide.layout and
  trade.ceiling. **43 passed, 0 skipped, 0 failed (7.9 min); after the fixes, duplication + sections + the desk specs 29 passed, then desk.terminal + desk.layout + wide.layout 13 passed.**

**Screenshots** (DPR 2) are in `2026-10-18-desk-terminal/`:
- before: `before-1440-*`
- after, at 1440×731: markets, good, plan, queued, city (the City face's trade board with the stock gauge)
- after, at 390×844: markets, good, plan, queued

The local world has a one-slot record and stock at its normal level, so the stock strip is flat
there. Prod's record has 12 h.

## Part 3 (2026-10-19): on the owner's 1280×707 glass

The coordinator found two layout defects on the live terminal. This PR fixes both.

1. **Stock text overprinted in the watchlist.** It rendered as "1205 / 268". The gauge was `min-w-0`,
   so a narrow row squeezed it under its own figure, and the figure was drawn over the bar and the
   facts beside it. `StockGauge` is now `shrink-0`: it keeps its width, and the text beside it
   truncates instead.
2. **Names truncated** ("Abalone …", "Adire Cl…"). A watchlist name now wraps to two lines at most
   and never truncates. The sparkline is 40×18. The list pane is 19–23 rem and the ticket pane
   20–24 rem.

**Spec.** `desk.terminal.spec.ts` runs at 1280×707, 1440×731 and 390×844. In the first 12 rows no
gauge part runs past the gauge, nothing beside it starts before it ends, no name is clipped, and the
page has no sideways scroll. Locally, desk.terminal, desk.layout, wide.layout and duplication:
**26 passed, 0 skipped.**

**Screenshots** (DPR 2): `fix-1280-*`, `fix-1440-*`, `fix-390-markets`.

**Best trade must be sailable (fix 3)** waits for `osn-plan-reach-2`'s served `sailable`, `stops`,
`needs` and `supplies`. It ships in its own PR once those fields are live.

## Part 4 (2026-10-19): Best trade is a passage she can sail (reads 0188)

0188 serves these on every board row: `stops`, `needs` (the direct leg's Navigation), `sailable` and
`longest_leg`. On the board it serves `reach` and `supplies {days, margin}`.

- **Best trade** takes the first quoted sell row marked `sailable` and shows its stops ("via Angra ·
  St. John's · Jamestown").
- **The dearer row it skips** is named, with the server's reason: "needs Navigation 4 (reach
  13,600 nm a leg)", or "its longest leg is N days at sea, more than your M days of supplies".
- **Nothing sailable:** the card says "No buyer you can reach from here." and shows no Plan.
- **The ladders** say the same.

**Server quirk, reported.** 0188 serves an unreachable BUY row as `stops: []` with
`longest_leg {0, 0}` and `miles: null`, where a sell row gets `stops: null`. The client treats
`miles: null` as "no passage".

**Headless screenshots** (DPR 2):
- `sail-1280-sailable` and `sail-1440-sailable`: Black Pepper, Lisbon → St. Augustine via three
  stops, 32.6 days.
- `sail-1280-unreachable` and `sail-1440-unreachable`: Alerce Timber, every buyer past a
  1,700-nm reach.

**Tests.** desk.terminal, desk.layout and desk.plan: 20 passed, 0 skipped. duplication fails only on
`20260818000187_the_great_powers.sql`, which has no `raise exception '0187 self-assert FAIL: …'`.
That migration comes from #229, not this PR.
