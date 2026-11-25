# 2026-11-25 — C1 `trade-tab-fleet-map` (client only)

The owner (docs/design/owner-spec-2026-11-25.md): *"THE TRADE TAB is for ACTIVE TRADING. At the trade tab, it will show your FLEET
name, and you can change your FLEET by tapping the name to trade on different location per FLEET. In the trade tab there should be
a map, showing no NPCs but only locations, where you can click them for info – price info."*

## What was already there (read, not rebuilt)

- **The fleet's name at the top, pressed to change her** (`FleetStrip.tsx`, `FleetPicker.tsx`): one button, a list of fleets, a row
  selects in place. Kept as it is, with its tab, route (`/command`), nav cell and `CommandScreen`.
- **A map of harbours on the tab** (`plans/TradeMap.tsx`, behind the tab's "Map" door): it was never handed the merchants. A harbour
  pressed became the city in hand, but its prices stood on the board BEHIND the map's page: nothing was shown until Back.

## What changed

- **A place pressed shows its prices in a sheet** (`buysell/CityPrices.tsx`): the place's flag and name, "Docked" / "Not docked",
  one line a good (Buy, Sell), and one press, **Trade here**, which closes the map on that place's board. Buy and Sell are pressed
  there as before. A phone: the bottom half of the glass. A wide glass: the panel at the right edge.
- **No new read.** The sheet is handed the board's own market read and rows (`usePortMarket`, `tradeRows` in `Trade.tsx`). A press
  is the city in hand, as it was, so it asks `world.market` once; the sheet's figure and the board's are the same number.
- **Places only.** With no order pressed the map draws no ship at all, hers included (decided by default: "only locations"). Her
  ship and course are still drawn when an order, the voyage or the route is pressed (the estimate's map), and on the Map tab.
- **Lifted from `desk-into-hq`**: the trade card holds three lines for its best sale (`live/TradeCard.tsx`), so a card is one height
  whether or not a sale has landed. Without it, changing the fleet changed the cards' height (182 to 166 px at 390). Nothing else
  came over: that branch's one trade list is this tab's own board hosted on HQ, and it deletes the tab, the picker and the strip.

- **The "From here" block stands last, under the orders, at both widths.** On a phone it moved Route and Orders 44 px or more. On a wide glass it moved Cargo, Map, Route and Orders by 174 px when the
  fleet changed and again when her best sales landed.
- **"No gain" stands beside its red figure** (it took a line of its own and made its row of cards 18 px taller).

## Second round, the same day (the map on the face)

- **The map stands on the face**: a phone 358 x 260 under the fleet's name, the list under it (the face scrolls as a page now); a wide
  glass beside the list. It opens on 60 S to 75 N round her place (no empty bands; 8 % at 390). "Big map", a button on the map's corner (on a phone beside "Your cargo"; over the southern sea, and at the top while a good's panel covers the foot), is the page of old, where an
  order's estimate and a plan are drawn. Pressing a good's Buy with a sheet open, or the reverse, leaves one of the two.
- **A second press named the neighbour (Cadiz, then Dublin)**: not a stale hit test. The name of the place in hand stood over Dublin's
  mark and `hitTest` gives a mark under a name's letters the press. The name in hand answers first now (`held`); the test fails without it.
- **The toast is at the top.** "No gain", short of money and "far" stand with the figure, so no card is a line taller; a one-line city
  stands level with its flag in the two lines held.
- Frame rate, the map panned: 60 a second, worst frame 17 ms (390 and 1440, this PC, not a real phone).

## Proof

`tests/trade.tab.spec.ts`, 390 and 1440, two fleets: the name is at the top and 44 px; a row pressed changes the fleet with the
address and the face unmoved, and "On board" follows her; the map draws places, no merchant, no ship; a place pressed opens the
sheet from at most one `world.market` ask; the sheet's first price equals the board's after Trade here; a good bought is sold
again at her own harbour through the map; nothing moves over 4 s; no sideways scroll; no word outside English.

## Not good yet

- The wide map is about 42 % of the map and the list, not 45: four cards a line need 544 px.
- At 1440 Route, Orders and "From here" are under the left pane's scroll. On a phone the city chips, Route and Orders are too.
- The face's map of names overlaps itself where seas and cities meet; tests/command.design.spec.ts no longer reads inside the chart.
- The zoom column covers the map's right edge. "Short of money" gives way to the figure on narrow cards (the title says it).
- Names crowd round Iberia until zoomed.
