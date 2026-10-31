# MAIN RED on 7c1031cf — three specs, two causes, no product defect

2026-11-01. Run 41209940429 (main `7c1031cf`, the #428 merge) failed three specs. All three were
reproduced on the served build before any change; each was diagnosed to its cause.

## 1 + 3. `quay-stores` — the same stale composition, twice

- `tests/cache.once.spec.ts:112` (openMarket)
- `tests/nav.geometry.spec.ts:336` ("the market face is not the trade face")

Cause: **#429/#430 replaced the Market building's face with the market face** (`MarketFace`:
Basket · Buy · Sell · Requests, `src/features/city/CityFace.tsx`). `quay-stores` is `PortTrade`'s
supplies row, and `PortTrade` now renders only inside the pressed board page
(`city-market-${open}-page`), never on the face itself. Both specs still drove the pre-#429
composition and waited for an element that no longer exists there.

Fix: assert the face's own door, `city-market-buy` — it renders only after the quay read has
landed, so it is the face's own "I am up" marker (and the market read the cache spec counts is the
same read). No product change: opening Market still shows the market face in the split, and its
Buy door opens the board.

## 2. `desk.terminal.spec.ts:62` — a measured SPEC RACE, not a moved list

The spec measured the good rows' tops before the press and after it, and reported *a press moved
the list*. Measured on `b14ae1c6` with the same viewport (1440×731):

| measurement | tops of the first 10 goods |
|---|---|
| before the press (read still landing) | 219, 219, 219, **340, 340, 340, 461, 461, 461, 582** |
| after the press (read landed) | 219, 219, 219, **356, 356, 356, 493, 493, 493, 630** |

Indexes 3–9 moved by 16/32/48 px — exactly one screen-row of 8 px of card growth per row, i.e. the
cards were still growing (121 → 129 px) as the served market read landed between the two reads.
With the list settled first, before and after are **identical** (`219,219,219,356,356,356,493,493,493,630`
both times). The press moved nothing; the data arrival did.

Fix: the spec now waits for the list's tops to be stable twice before taking `rowsBefore`, then
presses and compares — the press law is still proven, and the arrival of data is no longer mistaken
for it. No product change.

## Verification (served build of this branch, headless, localhost:4323)

- `cache.once` (the full two-cycle tab walk): **PASS 27.6 s**
- `desk.terminal` press test: **PASS 6.9 s**; the other two tests in the file green
- `nav.geometry` Market test: **PASS 8.3 s**; the other two tests in the file green
- all three specs together: **10 passed (40.6 s)**
- `tsc -b`, `eslint .`, `npm run build` clean
