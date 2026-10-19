# 2026-10-19 — a good opens at once (migration 0205 + the desk's kept answers, `osn-good-switch-fast`)

**The order.** The owner, 2026-10-19: *"when pressing a different trade goods, it takes too long to load, any way to
fix this?"* — COMMAND → Markets: pressing a good loads the chart pane and the ticket (Best trade, Buy at, Sell at,
Why this price).

## 1. What a press asks (the client, read from the code)

A press re-mounts the good's panes (`Terminal.tsx` keys them by good) and each read is asked from nothing:

| order | read | why it waits |
|---|---|---|
| 1 | `world.good_board(good, fleet)` | asked at mount |
| 1 | `world.price_history(port)` (once a port a session) | only when the focus city is known without the board |
| 2 | `world.price_outlook(focus, good, 24, 'mid')` | the focus city is the board's (the docked seller, else the cheapest) |
| 2 | `world.price_why(focus, good)` | the same |
| 2 | `world.price_history(focus)` | the same |

So the chart's estimate and the ticket's "Why this price" waited for the board, then for their own read: a waterfall.
Going BACK to a good just shown asked everything again (nothing was kept across the re-mount).

## 2. What prod measured (read-only)

Every check ran inside `begin transaction read only … rollback` through `supabase db query --linked`. All five
functions are `provolatile = 's'` (checked first). The calls ran as a docked fleet of a company that is not the
owner's (its JWT set locally in the transaction), six goods picked by hash.

| read | prod, server time |
|---|---|
| `world.good_board` | **4,288–6,111 ms** (6 goods: 6111, 4390, 4587, 4977, 4344, 4288) |
| `world.price_outlook` | 8–9 ms |
| `world.price_why` | 8–12 ms |
| `world.price_history(port)` | 64–90 ms (17–44 KB) |

The board is the whole wait. Inside it (same fleet, barley; total 4,185 ms):

| piece | prod |
|---|---|
| `voyage.reach_passage(player, origin)` (0188, the passage pathfinder) | **1,203–1,270 ms a call, asked 3 times a board** |
| · its miles matrix: `sr.reaches->>code` in a 238 × 238 cross join | 784–1,172 ms |
| · its region door: `public.passage_gate` once per harbour (238) | 379–477 ms |
| · the search itself (n² loop) | ~60 ms |
| `world.quote` with the fleet | 14 ms a call (× ~13) |
| `world.price_outlook` | 8 ms a call (× ~13) |
| `world.mid_price` × 238 | 57 ms |

Why the three pieces cost what they do:
- **The matrix** read `sr.reaches->>b.c` once per CELL. Each read de-toasts the harbour's whole stored miles document
  (238 keys) again: 56,644 de-toasts.
- **The door** called `passage_gate(player, null, harbour)` for each of 238 harbours. Each call re-derives her
  exploration (`public.exploration_reach` reads her VOYAGE_REPORT events). With no leg length named, the gate's answer
  depends only on the harbour's REGION, and there are 25 regions.
- **Three calls a board:** BUY AT and SELL AT each asked the same `reach_passage(v_player, v_origin)`, and the buy-city
  leg asked it a third time (from the cheapest seller).

## 3. The change

### Server — migration 0205 (`a_good_opens_at_once`; renumbers to the prod head + 1 at push)

1. `voyage.reach_passage` reads each harbour's miles document into memory once (`sr.reaches || '{}'` in an
   `offset 0` lateral) and looks the cells up there. It asks `passage_gate` once per region, of the region's first
   harbour. It is still the one gate and the one pathfinder.
2. `world.good_board` asks `reach_passage(v_player, v_origin)` once, keeps the rows in a jsonb, and reads them for
   BUY AT, SELL AT, and for the buy city when that is where she sails from.

Both are hunks sliced from the live bodies. Each hunk occurs once and reverses to its pre-image, and the ACL is
unchanged. The self-assert makes its own probe company (rolled back). It compares the new `reach_passage` with the
pre-image from four harbours, and five boards with the pre-image's boards (the old board calling the old
pathfinder). They must be equal, byte for byte.

Measured on prod, read-only, as inline blocks (a function cannot be created in a read-only transaction):

| piece | before | after | same answer |
|---|---|---|---|
| region door | 379–477 ms | 41–55 ms | yes (all 238 flags equal) |
| miles matrix | 784–1,172 ms | 157 ms | yes (all 56,644 cells equal) |
| `reach_passage`, one call | ~1,200 ms | ~260 ms (door + matrix + search) | — |

So `world.good_board` should drop from 4.3–6.1 s to about **0.65–0.9 s**: the rest of the board (~375 ms) plus one
pathfinder call, or two when the buy city is not where she lies. This is an estimate from the pieces. The real
figure is the self-assert's notice on CI, and a read-only timing after the push.

### Client (a normal part of the same PR)

- **Kept answers** (`src/live/servedMemo.ts`). Each desk read (board, estimate, breakdown, watchlist) keeps its answer
  under its own question until the market's next edge (the moment the open desk re-asks anyway), capped at 2 minutes.
  The question includes the fleet's version, so a trade is a new question. Going back to a good just shown draws at
  once and asks nothing. A question already on the wire is joined, not asked twice. A refusal is not kept.
  `useServedRead` takes this as an opt-in `memo`; the four port faces and the other readers are unchanged.
- **No waterfall.** While the board is on the wire, the cities the focus is likely to be (the docked city, and the
  watchlist's cheapest seller) have their estimate, breakdown and price record asked beside it
  (`prefetchGoodDesk`). When the board names one of them, those reads are already in.
- **A rest asks ahead.** The pointer resting 150 ms on a Markets row (or the row's keyboard focus) starts that good's
  reads, board included. A pointer only passing over the list asks nothing.
- `loadHistory` joins a port's read already on the wire.
- **The chart keeps room for what an estimate draws, on a phone.** CI caught this on the PR's first two runs:
  `desk.layout.spec.ts`, "pressing a chart city moved what is under the chart" (+10 px). The chip pressed (Elmina)
  had been asked ahead, because the row rest names the cheapest seller, so its estimate drew at once. Before, the test
  looked while a skeleton stood there. The chart's legend (low, now, high, estimate, stock) wrapped to two lines, so
  the 250-px box held 260 px. The foot's likely-range line wrapped too. Main has the same push, later, when the
  estimate lands. The box now keeps 260 px on a phone, and the foot keeps three caption lines (`sm:` unchanged).

Not changed: GoodTicket's section headings, GoodChart's head caption, planLines' reachWords.

## 4. Before / after, as the player waits on a press (wide desk)

| case | before | after |
|---|---|---|
| first press of a good | board 4.3–6.1 s, then estimate + breakdown (+ RTT) | board ~0.65–0.9 s; estimate + breakdown already asked beside it |
| press after resting on the row | the same | the board began on the rest: up to the board's time sooner |
| back to a good shown in this edge (≤ 2 min) | the whole wait again | at once (0 requests) |

Not measured here, said plainly:
- **The live client's network timings.** The game has no guest login. Making an account on the live game would write
  a real company to prod, so the client was not driven against the live site. The order of the calls is from the code
  (section 1). The server times are prod's.
- **The board's after-time on prod** is an estimate until 0205 is pushed. Read it then with one read-only call.

## Verify (once)

- `npx tsc -b` clean; `npx eslint` clean on the touched files.
- `tests/servedMemo.spec.ts` (new, no browser): 3 passed.
- 0205's self-assert: CI's pglite-gate and disposable-chain run it (the PR's checks).
