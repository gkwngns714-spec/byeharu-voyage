# 2026-10-20 — both sides of every price, a longer window, and a chart you can drag (owner 178)

**PR #286, branch `osn-prices-both-ways`. Client only, no migration; three commits, one per part.**

**One note for the next hand, learnt the hard way on this branch:** GitHub did not always create the
`pull_request` runs for a push here (two pushes got none, one got no `build`). Dispatching **Build**
on the branch is a safe way to get the required check. Dispatching **Migrations — apply proof** is
NOT: its own header says *"a dispatch is a from-zero apply (the net)"*, so on a client-only branch it
starts the whole-chain apply a pull request is forbidden from doing — and it turns a check that a PR
reports as **skipped** (which satisfies the branch protection) into a red one on the head commit. It
failed here at `Start disposable local Supabase`, three minutes in, which is not a chain error at all.
The way out is a fresh `pull_request` event: push again, and the newer skipped check is the one
protection reads.

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

---

## C. A chart you can drag

### What it does

The price chart's plot is a surface. A drag moves the window through the record — **the content follows
the finger**, as the map already pans (`panBy`, `src/chart/chartView.ts`) and as every chart does: drag
the line to the **right** and earlier prices come in from the left. ArrowLeft and ArrowRight walk it a
quarter of a window at a time, and there the owner's "swiping left" is literal, because the axis has
the past on its left. The chart's foot says so in one line while there is anything behind the window
to look at, and the line goes away once you have dragged.

### How it is built, and why not as a second chart

- **`src/components/ui/chartPan.ts`** is the whole gesture as arithmetic: a window's width, how far
  back it sits, and limits clamped to the data (`panBackMs`, `clampPan`, `panView`, `panByDrag`,
  `panByKey`). Pure, so a pointer never has to enter a test. It stands beside the two chart models
  rather than inside one, because `SeriesChart` can take the same pan the day its own record is long
  enough to need one.
- **`priceChartModel` gained one optional argument, a window.** With it the axis spans that stretch,
  x is no longer clamped to the plot (a point outside keeps its true place), and the y band, the x
  labels and the low / high marks are read from what is INSIDE the window — so panning back rescales
  to the prices you are looking at. **Without it every line behaves exactly as it did**, which is why
  all seven of `tests/priceChart.spec.ts`'s existing cases pass unchanged.
- **`PriceChart` clips everything it draws to the plot** (one `clipPath`, only when there is a window),
  so a line leaves the plane at its edge instead of piling up on it, and holds the pointer handlers:
  pointer capture on the press, `touch-pan-y` so a thumb going DOWN a tray still scrolls the tray (the
  map's embedded-surface rule), and `tabIndex` + the two arrow keys when there is anything to pan.
- **No second charting idiom.** `SeriesChart` / `seriesChartModel` (PR #283) are untouched: its own
  header says why the estimate machinery and this axis are two models, and a window is one more
  argument to the model that already draws the estimate, not a flag on a generic one.

### The window, anchored

The chips say how far **back** the window reaches; the server's estimate always stands to the right of
now, so the window is the two together — the same plane the chart drew before a window existed, which
is why the default view did not change. A chip asking for more record than there is stops at the oldest
served point (an empty three-quarters of a plane is not a product), and the foot says how far back the
record truly reaches. The move beside the price is labelled with **its own** span and not with the chip,
so a week-wide chip over a twelve-hour record still reads *+4.1 % · 11.8 h*.

### Nothing on this page may move under a press — and the first CI run caught it

The desk's law is that a press SELECTS: the chart changes in place and nothing below it moves
(`tests/desk.layout.spec.ts` measures `buy-at`'s top across a city press). Two things in this slice
broke it on the first run, both for the same reason — **a box whose height depends on a read landing**:

1. **The head** drew a skeleton while the new city's `price_why` was on the wire and the pair once it
   landed, and the two were not the same height to the pixel. Fixed by deleting the skeleton: in
   `block` form `PricePair` always draws both cells, **dashed** where nothing is served yet, so the
   waiting state is the very markup the figure will take.
2. **The foot** gained a line (the record's reach, or the drag's hint) that appears only once the
   estimate has landed, past the three lines it had room for. Fixed by reserving a fourth line. Four
   is the most that can ever stand there: the reach line needs a window WIDER than the record and the
   drag hint a window NARROWER, so the two are mutually exclusive by arithmetic.

Both texts were cut to one line each at 390 px for the same reason (`The record only goes back 11.8 h.`,
`Drag the chart right to look back.`).

### The third box, and the real cause of the red that followed

The two fixes above were not the whole of it, and chasing the reservation's figure up and down was the
wrong search. `acceptance-shard (3/3)` stayed red — once with the reservation at 68 px, once at 70,
once more after main was merged — and the thing it was catching was a **third** box of the same kind,
one I had made with my own hand in part (a):

The head's **middle-price line**. Splitting the hero figure into a pair above and a caption below left
that caption holding only the middle price and its move — and **both of those come from the estimate**
(`world.price_outlook`'s k = 0 point), which is null while a newly pressed city's estimate is on the
wire. So the line had no words, a flex row with no words is 0 px tall, and the head lost a whole line
**on a press** — the one moment the desk's law says nothing may move. Before the split that line WAS
the hero figure's line and a skeleton of the same height stood in it, so it could never collapse.

It is also why the shard went green once in four: the desk asks the likely focus cities' estimates
**ahead** of the press (`prefetchGoodDesk` — the docked city and the watchlist's cheapest seller), so
when the pressed city is one of those, the estimate is already in, the line never empties and the test
passes. A prefetch hit or miss is exactly the sort of thing that reads as flakiness and is not.

**The fix is the same law, applied three times over:** the caption line carries `min-h-4` — one
t-caption line, the figure from `src/index.css` — so it keeps its line with nothing in it; and the
foot's two conditional lines (the record's reach, the drag's hint) became **ONE line that is always
drawn**, with a non-breaking space when it has nothing to say. This slice therefore adds exactly one
line to the three the foot held before, never a line that comes and goes, and the reservation is the
honest sum again: four lines at 16 px with three 2-px gaps = **70 px = `4.375rem`**, and three lines =
**52 px = `3.25rem`** from the `sm` width up.

**What this cost, written down so the next hand does not pay it again:** three CI cycles and one
wrong revert. The failing test's NAME was never readable from the build sandbox — its proxy answers
403 to CONNECT for `results-receiver.actions.githubusercontent.com` and `*.blob.core.windows.net`, so
`gh run view --log` and every artifact are out, and the check-run annotations carry only *"481 test(s)
to run but 480 passed"* and *"shard plain-3 had 1 unexpected result(s)"*. The way the cause was
finally found was reading **one's own markup for boxes whose height depends on a read**, not reading
the log. That list is short and worth keeping: the head's pair (constant by construction — both cells
are always drawn, dashed), the head's caption line (`min-h-4`), the foot (one constant note, a
reservation equal to its own maximum).

**The second run proved it:** with these two fixed, the plain pool's shard 3 — the one that had gone
red — passed. The one shard still red, `npc 1/2`, is red on **main** too: run 39460828282, main's own
full acceptance at 16:49 UTC on 7c2a4e2, before this branch existed, has exactly that shard failing and
everything else green. Its last error could not be read from the build sandbox (the proxy refuses
GitHub's log and artifact hosts), so it is handed back as a main-side red, not a finding of this slice.

### Decided by default

- **The drag follows the content, not the owner's word order.** He wrote *"dragable to see the past
  prices by swiping left"*; dragging the content left shows LATER prices in every chart and on this
  game's own map, so inverting it here would make the chart the one surface in the game that moves the
  other way. The keyboard keeps his reading (ArrowLeft goes back) and the hint line names the gesture.
  If he wants the drag itself inverted it is one sign in `panByDrag` and nothing else.
- **No pinch, no wheel, no zoom.** The window's width is the chips; the wheel stays the page's, so the
  chart never eats a scroll on a phone (the same choice `useChartSurface`'s embedded posture makes).
- **One keyboard step is a quarter of a window.**

### Proved by

`tests/priceChart.spec.ts`, extended (pure, Node): a window draws its own stretch and no other (the
band, the axis labels and the marks are the window's, and a point outside keeps its true x off the
plot's edge); `now` is labelled where it falls when the estimate puts it inside the window; a drag
moves the window with the finger and stops at both ends; a window as wide as the record cannot be
dragged at all; the keyboard walks a quarter of a window with the left arrow into the past.

**No browser spec for the gesture, on purpose.** The local engine's price record is **two points,
fifteen minutes apart** (`localBackend.ts` plays the snapshot job once so a fresh world has a line at
all), so on CI's world nothing is wider than the record and nothing is pannable: a browser spec would
assert a surface that is correctly inert there. The pure spec proves the arithmetic; the drag itself is
to be driven on production's twelve hours of record, at the 1 h and 6 h chips, with a mouse and at
390 px.
