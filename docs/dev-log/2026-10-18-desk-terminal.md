# 2026-10-18 — the COMMAND desk as a trading terminal (0184 + the client)

The owner, 2026-10-17: *"delete port tab, and focus on command tab. it will be like stock trading screen …
stylish — modern — sophisticated yet concise simple."* On 2026-10-18, on his Chrome (DPR 2, 1440×731),
the desk read as a phone list in a 750-px column. A fleet at anchor showed "—" for net per ton and
arrival on every Sell at row. Then: *"i don't see stock of the trade goods so there needs fixing"*.

## Part 1: migration 0184, `the_desk_reads_stock_and_the_anchor` (server, deploys first)

**Why the rows were bare.** `world.good_board` (0171) measures distances from the fleet's berth, or
from the port she is bound for. An ANCHORED fleet has neither, so `voyage.reach_from(null)` returns
nothing. Every row then has null miles, days, arrival and wages, so the net is null too.

**Fix, one hunk.** With no berth and no voyage, the board starts from the **nearest harbour** to her
position (great circle). The miles to that harbour are added up front, the way a voyage's miles left
are. `fleet.where` gains `via` and `miles_left`.

**Stock.** No desk read served a city's normal stock (`port_goods.stock_target`). Only `world.market`
had it. Keys added, and nothing removed:

| Read | Adds |
|---|---|
| `world.good_board` | buy rows: `stock_target`; sell rows: `stock`, `stock_target` |
| `world.watchlist` | `best.stock`, `best.stock_target` |
| `world.price_history` | each point's `stock` (the column the snapshot already writes) |
| `world.price_outlook` | each point's `stock` (`public.price_path`'s stepped stock) and `stock_target` |

**Proof.** The world image's PGlite run takes 2.4 s. The probe runs on its own house, docked at
Lisbon and then anchored off the Tagus bar, and is rolled back whole.
- At anchor the board runs from LIS (20 miles). All 10 quoted sell rows are complete. The old board
  had 10 bare rows (positive control). Anchored miles = docked miles + the lead on every row
  (0 off). The call took 212 ms.
- Stock: every sell row's stock and normal level equal `port_goods`, and every buy row carries its
  normal level. All 555 watchlist goods carry it. Outlook point 0 = the city's stock (673, normal 670).
- All four bodies reverse to their pre-images, and the ACLs are unchanged.

**Number.** 0184, after #220 (0182) and #219 (0183), which are in flight. Neither touches these
four functions.

**Not the owner's, to confirm.** The lead from an anchorage is a great circle, not a sailed course.
It is an estimate's figure.
