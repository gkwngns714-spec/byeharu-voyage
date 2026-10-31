# The Market desk — chart left, BUY · SELL · REQUEST in the panel, requests only at the home city (2026-10-31)

Owner, verbatim:

> *"when pressing a market, instead of city, i would like to have a graph shown, that is changed
> when pressed a trade good. when pressing buy, a new page pops up - this is not good. instead,
> have BUY, beneath show all the trade goods neatly organized. So is sell - cargo good. Request i
> press, a page shows up, where i search trade good - press it, shows up chart, choose price to buy,
> and then the put the money in it. - the order is made, and merchants will come and sell it to you
> if the price is reasonable"*

> *"but this feature, request, should only be done in your home country- home city. get it?"*

## The screen

- **The Market face's LEFT region is the price chart** instead of the city picture (CityScreen swaps
  `CityScene` for `MarketLeft` only when the open place is the market; the box is the frame's,
  unchanged). `MarketLeft` paints the served series (`usePriceSeries` over `world.price_series`) for
  the good in hand, with the one `SpanPicker`, the served range and the stock gauge — the same
  `ui.*` words PriceRows prints. The chart is always drawn, never folded.
- **One answer to "which good"**: `src/live/marketPick.ts` (session store, keyed by port). With no
  pick, the chart shows the port's first good by name (the ledger's own order); a pick that has left
  the board falls back the same way.
- **The right panel**: Basket (unchanged: a summary IN the panel), then the `Segmented` strip
  **Buy · Sell · Requests**, then the goods listed BENEATH the pressed door — grouped by the SERVED
  category, each group composed from the one `QuayLedger` (its membership and order are not re-spelt
  here). A press on a good pins it (the chart follows) AND opens the one `TradeTray` in
  `mode="pane"` inside this panel — never a page, never a screen-covering sheet. No fleet alongside:
  the press only pins the good (a read-only board).
- **Requests** — the door exists only when the server's `world.requests(port).home` is true; the
  same `public.home_port_of()` the verb enforces, so the door and the gate cannot disagree. Its face
  lists the caller's open requests (good × quantity, the unit price, the money set aside) with a
  44-px Cancel; **New request** opens the page: search → press a good → its chart → price +
  quantity → the payment → Place.

## The server (migration 0288 `the_market_takes_requests`)

- `public.market_requests` — one standing BUY order: (player, port, good, qty left, unit price,
  escrow left, status). The escrow column IS the money set aside: taken from the purse at placement
  through the one `public.credit` as its own `REQUEST_ESCROW` row.
- `public.home_port_of(player)` — THE one reading of "home city": the port of the house's earliest
  `FOUNDED` event (the payload `new_house` already writes). No second notion of home.
- `world.requests(port)` (authenticated) — the caller's own open rows + the `home` flag.
- `cmd.request_place(port, good, qty, price)` (authenticated) — refuses `E_NOT_HOME` anywhere but
  the home city (hiding a door is not an enforcement), whole quantities only (`E_NO_QTY`), a price
  (`E_NO_PRICE`), a good this city trades (`E_NO_SUCH_GOOD`), and the purse covering the escrow
  (`E_INSUFFICIENT_FUNDS` through `credit`). Insert + `REQUESTED` event.
- `cmd.request_cancel(request)` (authenticated) — the owner's own open row only; the unfilled escrow
  returns as `REQUEST_REFUND` and the order closes (`REQUEST_CANCELLED`).
- `public.market_request_fill(fleet)` + `public.tg_market_request_fill()` — a NEW trigger on
  `public.fleets` `AFTER UPDATE OF status` when the new status is `DOCKED`. No cron, no schedule, no
  TTL, no body re-cut: the fill rides the arrival `voyage.settle` already performs. A merchant house
  (`players.is_npc`, 0097's predicate) sells into the best-priced open request at her port for a
  good she carries, **at the request's price when it is at least the quay's ask** (`world.price`);
  the goods go ashore through `public.storage_put` (the one storage writer, basis = the price paid),
  her cargo leaves through `public.fleet_unload`, the money reaches her as `REQUEST_FILL`. Storage
  room and cargo cap the fill; the remainder stays open.
- Registry: THREE rows added to `client_rpc_entry_points` by the house recut (the pre-image asserted
  to occur exactly once). No job added; no switch, knob or wall moved.

## Proof

- **0288 self-assert** (rolled-back probe, run on every apply): the home reading resolves the
  founding port; `E_NOT_HOME` away from home; `E_INSUFFICIENT_FUNDS` over the purse; placement moves
  exactly qty × price into `REQUEST_ESCROW`; the read serves it with `home = true`; a merchant
  docking with 5 units fills the 5-unit request, is paid the escrow and the goods land in storage; a
  partial fill (4 asked, 2 carried) leaves 2, and Cancel refunds exactly 2 × price; a price below the
  ask does NOT fill; registry +3; jobs, switches and walls as found; the probe houses/requests are
  gone after the rollback.
- **`tests/market.desk.spec.ts`** (served local build, 390×844, headless): the chart is the city's
  left region and follows a pressed good (the chart's good text changes to the pressed row's name);
  Buy/Sell are doors in the panel with no page; Sell lists nothing a fresh house does not carry; at
  the home city the request page places an order, the row is listed (payment included) and Cancel
  removes it on the next beat.
- Local gates: `tsc -b`, `eslint .`, `npm run build` (0288 applies; client bundles) clean.
  `city.audit` market tests (rail/frame/six-split, compact faces, Basket) green; `city.page` green;
  `layout` + `desk.plantab` 21/21 green after one design-system change (below).

## Decisions taken by default (the owner may reverse)

1. **The goods list scrolls inside the panel.** A port lists every good it trades; the owner asked
   for all of them beneath BUY. The list is a bounded LIST PANE (`consistency.spec`'s own rule);
   the page, the frame and the document never scroll. `city.audit`'s no-scroll loop now excepts the
   market's inner list with the owner's quote in the reason.
2. **`Segmented` cells gained `min-w-11`** (one line in `src/components/ui/Chip.tsx`): the audit's
   44×44 floor measured the new tabs/span chips 26–40 px wide. This widens every segmented strip in
   the app by at most 18 px per cell; `layout` and `desk.plantab` re-ran green.
3. **The city page now arms the world's beat** (`src/live/useWorldBeat.ts`, shared with AppShell —
   the beat was AppShell's own copy). The city stands outside the shell, so its served reads (hall,
   market, requests) were asked once and frozen under a standing player; the request list after a
   Place/Cancel needs the beat to refresh.
4. **The payment figure on the request page is qty × price** — both numbers the player typed, so the
   multiplication is exact arithmetic, not a market price; the escrow actually taken is the server's
   answer, and a refusal arrives typed under it.
5. **The request page searches the port's listed goods** (the same board the chart and the BUY list
   read), not the whole catalogue: a request for a good this city's market does not price has no ask
   to judge "reasonable" against.

## Deploy order

0288 deploys AFTER **0286** (the Report, PR #416) and **0287** (the stats indexes, PR #428), in
strict number order, one migration PR at a time. This PR is not merged by its author.

## PROD CHECKS (read-only, before the PR)

See the PR body.
