# 2026-10-18 — 0162: K8, a captain is promoted for what her company has done — `osn-k8-promotion` (stacked on K7)

`docs/SKILLS_AND_CAPTAINS.md` §4.6 / §8 row K8 (D12 by default). **Dark** in effect: no company holds a promoted
captain. Provisional 0162 (S13 0158, K6 0160, K7 0161).

- **Items in the one item system**: `item_kinds.kind` ('fitting' for every row of today, 'promotion' for Sea Chart,
  Trade Seal, Battle Honour); `world.workstation` and `cmd.resolve_item` read fittings only, so a promotion item is
  never made, fitted or unfitted. `promotion_items` (item → focus → points) from `data/captains.json`, guard-held.
- **Trading's rate is measured** (production, read-only, 2026-10-18): one human sailor (6,478 miles) is no sample;
  the merchants turned over 61,712,599 coin across 12,732,386 miles = 4.85 coin a mile, so a Sea Chart's 100,000
  miles ≈ 485,000 coin ≈ **4,850** trading points: a Trade Seal takes about as long as a chart.
- **One writer** `promotion_credit(player, port, track, points)`: a player's company banks points
  (`promotion_progress`) and at a port turns whole items into storage there; merchants return at once. Called
  beside the captains' credit in settle's arrival (Exploration, Combat; anchored, the points wait) and the trade
  cores (Trading). No back-pay for the past (said).
- **Gates** on `captain_grades` (B 5/10, A 10/20, S 15/40); `promotion_next(signing)` is the one reading the verb
  and the roster share; `cmd.promote_captain` (+1) → `promote_captain_for`: aboard (E_NOT_ABOARD), docked
  (E_NOT_IN_PORT), level (E_LEVEL_TOO_LOW), items there (E_NOT_ENOUGH_ITEMS with the figures); raises
  `captain_state.grade` (her slots, known traits and — lit — floor follow from the ladder).
- **Client**: the Captains sheet (FLEETS) shows the server's promotion line, the items kept here and
  **Promote to B**; Storage shows the items like any other.
- **A trap found and fixed in the probe**: a volatile credit and a subquery in ONE `if` read the snapshot from
  before the credit — the first check passed vacuously (null). Every credit is now its own statement.
