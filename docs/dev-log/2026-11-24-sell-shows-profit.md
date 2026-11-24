# 2026-11-24 — S2 `sell-shows-profit`: a sale shows its profit before the press (0490, proof 193)

The owner: *"when i sell, i want to see the price i bought, the price i will get, how much profit earn and such."*
Plan: `docs/design/simplify-2026-11-24.md`, slice S2.

## The finding, checked

The auditor wrote that the preview (`cmd.preview` → `cmd.do_sell`, rolled back) carries `basis`/`cost`/`profit` but not tax, wages,
dock fee or `trip_net`. Read on the chain's live body (dumped from the PGlite chain at 0488): the result already carried `tax` and
`wages` (`v_wages`, what `public.pay_wages` paid, = the event's `wages` by 0474's rule), and `net` = total − tax − wages. It did NOT
carry the dock fee or `trip_net`. So the finding stands for those two.

## Server (0490)

One body, `cmd.do_sell`, four hunks: `v_trip` declared; set once where 0474 reads the wages and the dock fee
(`v_profit - v_tax - v_due - coalesce(v_call, 0)`); the SOLD event writes `v_trip` (the same value, no longer an inline copy); the result
returns `dock_fee` and `trip_net` (`v_trip`). The preview is `cmd.do_sell` itself, so the figure before the press and the event after it
are one computation. No switch, no coin moves differently.

Self-assert: each hunk once and reversing; no other function moved; grants/volatility/definer/owner of `cmd.do_sell` unmoved; no
world_config row moved; a rolled-back probe (a fresh company at Lisbon, five units bought at half the bid, wages owed 40, a call fee 25):
preview, result and event tell one `trip_net`.

## Client

- `domain/order/estimate.ts`: `SaleEstimate` reads `tax`, `wages`, `dock_fee`, `trip_net` (nullable; a server before 0490 serves none).
- `live/useTrade.ts`: the dry run is `useTradeDryRun` (one reading), used by the sheet and by Your cargo's Here.
- `TradePanel.tsx`: `SaleLines`: Bought (each · total), Sells for (each · total), Tax / Wages / Dock fee (only when not 0), Profit
  (`trip_net`, green/red, % of cost). On a sale it stands ABOVE the units (decided by default): under them, the half-raised sheet at
  390 x 844 ended at the stepper (screenshot: the lines started below the fold). Even above, the half sheet shows only "Bought", so
  the two unit prices (Bought · Sells for) are also pinned with the button, above Total and Profit (`sale-pair`): all four are seen
  before the press at every sheet height. Sail & sell / Buy & sell show the same lines from the served sell row (supplies stay on
  their own row; a buy-and-sell trip keeps its units first).
- `CargoBest.tsx`: "Bought 81.6" beside each good; Here's profit is the dry run's `trip_net` (it was "—").
- `OnBoard.tsx` not changed: its per-unit gap is the owner's own 2026-09-18 ask, and it lives on the basket path S3 deletes.
- Words: `trade.bought` Bought / 산 값, `trade.sellsFor` Sells for / 판매가; Profit, Tax, Wages, Dock fee reuse `desk.*`.

## Measurements (local PGlite, this PC)

- 0490 applied on the 0488 snapshot: self-assert 619 ms. Probe: anise ×5, profit 198, tax 0 (treasury dark locally), wages 40,
  dock fee 25 → trip_net 133 in preview, result and event.
- Proof 193 (economy closed, treasuries lit): 6.6 s. Anise ×5: sells for 400, cost 200, tax 30, wages 40, dock fee 57 →
  profit 73 shown = 73 settled; purse moved 273 = 73 + 200; second good (black pepper) dock fee 0, 275 = 275.
- Proof 177 locally: GP_GIFT_* pass; GP_CARD fails "the cards ran out of their budget" (world.best_sales' 2.5 s budget on wasm; not
  touched by 0490). CI's run is the verdict.
- Load: no rows, no tables, no cron. 0 new rows a minute.
