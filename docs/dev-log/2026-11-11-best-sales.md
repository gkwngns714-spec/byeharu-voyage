# 2026-11-11 — 0348: every card names its best sale (`s2-best-sale`, owner row 307)

## What it is
The Command board's goods cards (`src/features/command/buysell/TradeBoard.tsx`) each carry one more text line: the good's best
sale from the city in hand, the city and the served PROFIT. Green when it pays, red "No gain" when no city she can sail to
pays. Pressing it opens the trip in the same trade panel: bought at the city in hand, sold at that city (Buy & sell), at the
units the figure was priced for, so the tray's first profit is the card's. A good aboard opens Sail & sell there. A Buy tray
for a good that does not pay says so above the units and their Max.

## One authority
`world.good_board` stays the one place a sale's profit is worked out. Migration 0348 moves its opening (`world.board_origin`,
`world.board_passages`), its amount (`world.board_amount`) and its SELL AT (`world.board_sell`) into four server-only
functions, and good_board calls them. `world.best_sales(fleet, port)` calls the same four once per good. Two reader's options
in board_sell, both off for good_board: FIT (each priced row bought at the units that fit beside its own stores, the figure
good_board serves when asked for that count) and LEAN (leave out the cap, the estimate, a request, passage_needs, the dues and
the unpriced rows). The migration asserts in one statement each: good_board equals its pre-image byte for byte (no city, its
own city, an amount, another city, and her cargo), and every card's profit and units equal good_board's row for that city.

## Measured
| where | what | figure |
|---|---|---|
| local (PGlite, this PC) | `best_sales` at Lisbon, 10 goods | 1,332 / 1,613 / 1,663 ms (self-assert), 2,077 ms (cold) |
| local | `best_sales` at the 7 nearest other cities, 4–10 goods | 554–1,458 ms |
| local | one `good_board` | 746 / 1,037 ms |
| local | `mid_price` 249 harbours x 15 goods | 363 / 400 ms |
| local | `world.quote` x 225 | 202 / 260 ms |
| prod (read only, EXPLAIN ANALYZE of STABLE functions) | `mid_price` 249 x 15 | 710 / 764 ms |
| prod | `world.quote` x 225 | 594 / 1,354 ms |
| prod (dev log 0222, 0231) | one `good_board` | ~350 ms (0222 receipt) to ~900 ms (0231) |

## The prod estimate, composed (NOT measured: `best_sales` needs a signed-in player, which a read-only prod check is not)
* By the parts (prod is 1.9–2.1x local on `mid_price`, 2.3–6.7x on `quote`): Lisbon's 10 goods 2.7–6 s.
* By whole boards (prod `good_board` ~0.35–0.9 s against local 0.75–1.04 s): 0.5–2.5 s.
* The two do not agree; the honest range is 0.5–6 s for a 10-good city. The 2.5 s budget inside `best_sales` caps a call: the
  goods past it (in code order) get no line and `cut` is true. The real call is measured right after deploy; over ~1.5 s for
  a 10-good city, the precomputed dearest-buyers list (a swap inside `world.board_sell`'s `cand` / `ranked`) follows.

## Read
One `best_sales` per city in hand and fleet version, kept until the market's edge and asked again there (`useEdgeRead`),
never on the 3-s beat, never per card, and not while the Trade face is closed. A refusal or a cut good is no line, never a toast.

## Not done here
* The seas (`sea_conditions_bite`, false on prod) are not read by `best_sales`; the trip's Go gates on `sailable`, which the
  seas do not move.
* In the local world every good at the 8 nearest cities pays for a fresh company; the spec reaches a loss by filling the hold
  but for five units (a few units cannot carry a long voyage's wages).
