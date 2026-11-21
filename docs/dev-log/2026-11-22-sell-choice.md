# 2026-11-22 — A choice of where to sell (P1, client only)

Plan: `docs/design/playable-2026-11-22.md` §3 P1, "A choice of where to sell". The play-test: a good's card pre-picked one
city and "Buy & sell" bought, sailed there and sold. The player never chose where.

## What changed

- The Buy & sell sheet (`TradePanel.tsx`, `SellChoices`) offers **the best three places to sell**, right under the city
  line: each one line, "City · time · +profit", pressable (`role=radio`). The card's sale (world.best_sales: the best per
  day within her purse) is lit as the default. Another pressed is the same trip to that city at the same units; the
  sheet's profit is that row's to the coin.
- It replaces 0351's one quiet "Far" / "Near" row (dict keys `farSale`, `nearSale` removed; `sellWhere`: "Sell at" /
  "팔 곳" added).
- `saleChoice.ts` picks the rows (lead review, follow-up commit): the card's sale, the QUICKEST row that pays, the RICHEST row,
  then the next best by profit per day (ranking only, never printed), to three; only rows that pay, are sailable and whose stores fit.
  Shown nearest first, so quick-and-near reads above far-and-rich.

## Why no server change

Every figure is a row of the trip's own read — `world.good_board(good, fleet, from = buy city, qty = the sheet's units)`,
the read `useTripBoard` already makes and whose row the sheet prints as its profit, time, wages and fees. Its `sell`
rows carry `profit`, `days`, `sailable` and `supplies.fits` for every quoted city (10 dearest + 5 nearest). The client
only picks rows by served figures (as `CargoBest.tsx` does); nothing is priced, added or divided. The press already took
a destination: the plan's `sellAt` (`useDeskPlan.open`), queued by `cmd.issue_lines` as before.

A choice's units are the sheet's units, not the far sale's own `far.units`: the row was priced for these units, so what is
pressed is what was shown.

## Placement

At 390 × 844 under the units, the three rows stood below the half-raised sheet's fold. They now stand first under the city
line; the half sheet shows all three, the cost, the profit and the button (screenshot from `tests/command.bestSale.spec.ts`
at 390, `test-results/sell-choice-390.png`). The units stepper is one swipe up.

## Checks

- `tsc -b`, `eslint` (changed files), `vite build`: clean.
- `tests/command.bestSale.spec.ts` (rewritten tray part: 2-3 places, distinct cities, distinct times, the card's lit,
  another pressed → `data-sell-at` and the tray's profit equal the row's, back again): 2/2 pass, 33 s, against
  `vite preview --port 4797`.
- `tests/trade.flow.spec.ts -g T3` (the far sale now reached through `trade-sale-choice[data-port=far]`): 5/5 pass, 1.1 min.

## Follow-up (lead review)

The first rule gave Darwin / Jeju / Fukuoka from Lisbon, all about 6h20m. Now quickest-that-pays and richest are lines 2 and 3.
Re-run at 390: Porto 0.4 days +1,088 (default) | Santos 12.0 days +11,143 | Buenos Aires 14.5 days +14,658; at 1280:
Setubal 0.2 days +1,304 | Cadiz 0.9 days +3,197 | Tokyo 54.6 days +32,369. The spec asserts the lines stand quickest first.
