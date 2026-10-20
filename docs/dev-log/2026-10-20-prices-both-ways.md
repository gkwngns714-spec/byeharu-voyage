# 2026-10-20 — both sides of every price, a longer window, and a chart you can drag (owner 178)

**The owner, 2026-10-20, row 178 of `docs/OWNER_REQUESTS.md`, verbatim:**

> *"in command, I press a city and it shows buying price, and selling price. But it is not known until
> I press it. I don't know if the city I press will show selling price, or buying price. Therefore, I
> want both for all cities. And also, the price is shown max 12 hours, can you make this more longer?
> Like day? Week? And make the chart dragable to see the past prices by swiping left?"*

Three parts, one commit each, so any one can be taken back alone. Client only — **no migration**.
Where a part could not be finished without one, §B says exactly what the migration would have to do.

---

## A. Both sides, always

### What was wrong, read from the code

The desk's good page drew **one figure beside a city** and the figure meant three different things
depending on where the city stood:

| Where | What the figure was | Where it comes from |
|---|---|---|
| `Buy at` rows | the **ask** — what you pay there | `world.good_board`'s `buy[].price_each` (`world.quote`, buy side) |
| `Sell at` rows, the dearest 10 | the **bid** — what you get there | `good_board`'s `sell[].price_each` (`world.quote`, sell side) |
| `Sell at` rows, the other ~228 | the **middle** price | `good_board`'s `sell[].mid` (`world.mid_price`) |
| the chart's head | the **middle** price, in the hero figure | `world.price_outlook`'s k = 0 point, side `mid` |

Same ink, same slot, no word. So "I don't know if the city I press will show selling price, or buying
price" is not a misreading of the screen: the screen never said. The column heads said *you pay each*
and *you get each*, but a head above a ladder is not a label on a figure, and the head of the page —
the figure a press changes — carried the middle price, which is neither side.

### What it does now

1. **A new primitive, `src/components/ui/PricePair.tsx`**: both sides of one price, each under its own
   word — `You pay` / `You get`. It prints served figures and derives nothing: a side the server did
   not price prints as a dash, never as the other side with the spread flipped. When **neither** side
   is served the market's **middle** price stands in, dim, under the word `market`, so it can never be
   read as a price one trader gets.
2. **The chart's head** (what a press changes) shows the pair for the city in focus, from
   `world.price_why` — which already serves `ask`, `bid` and `mid` for one city and one good, and which
   the page **already asks** for the "Why this price" breakdown below. So both sides cost **no new
   read**. The middle price keeps its own line under the pair, because the middle is what the chart's
   line and the record are made of (`price_history` stores the mid).
3. **Every row of both ladders** draws the same pair. `src/features/command/markets/citySides.ts`
   joins the board's two lists **by city** — a city that sells a good also buys it, so it stands in
   both lists and both of its sides were already on the wire, drawn in two places that never met.
   Nothing is priced in the client: `citySides` only reads `buy[].price_each`, `sell[].price_each`
   (when `quoted`) and `sell[].mid` across.

**The one price authority is untouched.** Every figure is the server's: `world.price_sides`, composed by
`world.price` (hence `world.price_why`) and by `world.quote_priced` (hence `world.quote`, hence
`good_board`) — the spread, the tax and the city's bid factor in one leaf, under 0211's law that a
round trip never pays. The client multiplies nothing and infers no side from the other.

### Where it is still not literally "both for all cities" [stated, not hidden]

`world.good_board` prices the **sell** side at the dearest `good_board_quoted` cities only (10 on
production, 0171) and serves the middle price for the rest. So a **cheap selling city** has an ask on
its row and a dash where its bid would be, and a far-down buyer has a dim middle price alone. Pressing
that city fills the pair exactly (the head reads `world.price_why`, which prices both sides for one
city), and the press costs no read the page was not already making.

Serving the whole pair on **every row at once** is a server change, not a client one, and it is small:
`good_board` already walks every city, and COMMAND_DESK §1.4 measured **238 × `world.price` at 236 ms**.
What a migration would do: add `ask` and `bid` to each `buy` and `sell` row of `world.good_board` from
`world.price` (the same leaf the row's `mid` comes from), keep `price_each` as it is (it is the stepped
average for the asked amount, a different and also useful figure), and self-assert that a row's `ask`
and `bid` equal `world.price`'s to the cent. The client would then pass them to the same `PricePair`
and nothing else would move.

### Words

`ui.youPay` / `ui.marketWord` are new (English and Korean). `markets.buyCols` and `markets.sellCols`
drop the side word they used to carry (the figures now carry their own): *each · stock · how far*,
*each · profit per ton*. `markets.midPrice` moved from the city caption to the middle-price line and
takes the price instead of the port; `markets.perUnitAt` is the city caption. `markets.marketPriceLower`
said *market price* in the slot where a profit figure stands — now that the pair says `market` itself,
that slot says *profit unknown*, beside its neighbour *cost unknown*.

### Proved by

`tests/citySides.spec.ts` (pure, Node): a city in both lists carries both sides from their own lists; a
city that only buys has no invented ask; an unquoted sell row keeps its middle price and no bid; a
seller with no stock for the amount has **no** ask rather than a nought; an unnamed city and a board
still on the wire read as the empty pair.

---

## B. A longer window than 12 hours — what limits it, and how far it opened

### What limits it, read from the chain

The 12 hours were **two** limits, one on each side of the wire, and only one of them was the client's.

1. **The record itself.** `public.price_history_window()` (0057) is
   `greatest(48, floor(629,145,600 / (pairs × 201)))` — a 600 MiB disk budget divided by the world's
   (port, good) pairs and the measured 201 bytes a row costs, with a floor of 48 slots. Production has
   **132,090** pairs in `public.port_goods`, so the derived figure is `floor(600 MiB / (132,090 × 201))`
   = **23**, under the floor, and the floor wins: **48 slots × 900 s = exactly 12 h.** That one number
   clamps BOTH ends — `world.price_history` clamps `p_slots` to it, and `public.tick_price_snapshot`
   **deletes** every row older than it. So the older points do not exist to be read, and no client
   change can find them.
2. **The client.** `worldPriceHistory(portId, slots = 48)` hard-coded the ask, and the chart offered
   three chips — 1 h, 6 h, 12 h — with 12 h as both the default and the ceiling. This half is the half
   that moved.

### What it does now

- `worldPriceHistory(portId, slots)` asks for **the slots the chosen window would fill** (null asks for
  the server's own default). The server clamps the ask to what it keeps and **says what it gave** in the
  payload's `slots`, which the client now carries on `PriceTrend`.
- `worldStore.loadHistory(portId, slots)` re-asks only when the window is **wider** than the widest
  already covered (asked, or served) — a payload for N slots holds every shorter window inside it, and a
  window the record cannot fill must not ask again every time it is chosen. One extra read per good page
  when a longer window is pressed, and none at all for a shorter one.
- The chips are **1 h · 6 h · 12 h · 1 day · 1 week** (`DESK_WINDOW_HOURS`). The slots each one needs are
  derived from the **served** cadence (`slot_seconds`, the same `drift_slot_seconds` knob on both
  payloads) — never from a literal 900 or 48.
- When the record cannot fill the chosen window the chart's foot says so, in words, from the **served**
  points: *"The record goes back 11.8 h — the game keeps no more than that yet."* It is derived from the
  earliest point drawn, so it tells the truth at any retention.

**So: today a week still draws 12 hours of line and one honest sentence.** The moment the server keeps
more, these same chips draw it with no client change — which is the half of the request a client-only
slice can land.

### The migration this needs, and exactly what it would do [NOT WRITTEN — client-only slice]

**Do not widen `price_history`.** A week at the fine cadence is 672 slots ×  132,090 pairs × 201 bytes =
**17.8 GB**, against a 600 MiB budget and the 1.43 GB that once took the project read-only (0057's own
header). The floor cannot simply be raised.

**Serve the rollup that already keeps it.** 0214 (live today) writes `public.stats_city_good` every
15 minutes — `(port_id, good_id, slot, at, mid, stock, stock_target, sold, bought, …)` for the offered
pairs — keeps it fine for `stats_city_good_fine_hours` (48) and then **one row per UTC day forever**. A
week of one city's good is therefore already stored: ~192 fine rows and 5 daily ones. What is missing is
only a read:

1. **A new read, `world.price_record(p_port uuid, p_good uuid, p_hours int)`**, returning points as
   `{at, mid, cadence}` oldest first, plus `slot_seconds` and the window it actually covered. It UNIONS
   `public.price_history` (the fine, recent half — the authority for a recorded mid, 0013) with
   `public.stats_city_good` (the older half), **preferring `price_history` where both have a slot** so a
   point is never served twice from two tables, and marking each point with the cadence it came from so
   the client can draw a coarser stretch honestly rather than interpolating.
2. **Public, like every other price.** `world.market` serves a city's prices to any signed-in company,
   so a recorded mid is not intelligence; `world.stats_city`'s tier gate (0214) is for a city's **books**
   — purse, income, taxes — and must not be extended over a price, or the chart would go blank for
   everyone who holds no shares (no player holds one today).
3. **Self-assert**, in its own transaction, on its own probe rows: the union's newest points equal
   `world.price_history`'s to the cent; no slot appears twice; a window longer than the fine retention
   returns the daily rows and marks them; a window of 0 or a missing port refuses; registered in
   `public.client_rpc_entry_points`, granted to `authenticated`, refused to `anon`.
4. **The client change it would need is one line**: `usePortHistory` asks `world.price_record` instead of
   `world.price_history` and passes `winHours` straight through. The chips, the model and the drag need
   nothing — they already read the served points and the served cadence.

**Also stale, and worth correcting in that migration's header:** 0057's floor is justified by *"48 = THE
FLOOR: `src/lib/rpc/index.ts:289`, `worldPriceHistory(portId, slots = 48)`, is the ONLY client caller
and it never asks for more."* As of this commit the client asks for what its window needs and takes what
it is given, so the floor's reasoning needs restating (the floor itself is still right: the chart must
never be starved below the window the page opens on).

### Decided by default

- **The page still opens on 12 h**, because that is the whole record on production today — the most line
  there is. The longer chips are a press away.
- **No second store and no browser-side accumulation.** Keeping points in `localStorage` as the game runs
  would be a second price record, drifting from the server's, unshared between devices, and empty for a
  new player: the rollup already exists and is the server's own.
