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
