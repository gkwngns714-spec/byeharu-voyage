# 2026-11-11 — S8: a yard a player can finish (0349, owner rows 180 and 305)

## Why
The remaster playtest: Port > Build listed 50+ hulls; the cheapest (Barca) needs six materials; the sheet had no Build
button, only "Missing: ...", and nothing said where Timber (or any material) is sold. No player could plan a second ship.

## What changed
- **Order** (`src/live/PortYard.tsx`): the hulls the server marks `buildable` here and now stand first; every other hull
  waits under one "More · N" row (the ones this country builds that you cannot yet, then "Built abroad only"). The row
  opens below itself, once, and moves nothing above it. Nothing is removed.
- **Where to get it** (`world.yard_sources(port, class)`, migration 0349, STABLE): per material of a hull, the nearest
  harbour that hands it over — a good where `cmd.do_buy` sells it (`port_offered_goods` + `culture_refuses`, called), a
  fitting where `cmd.do_make` makes it (workstation tier + `made_only_in`, called) — with the sailed miles from
  `sea_reaches` (0 for the yard itself). No existing read answered this without one call per good per fleet
  (`good_board`, about 1 s each and needing a fleet) or a client copy of the roster.
- **The press**: a missing good → the Trade desk on the seller's city with the good in hand (the map's own
  "Open in Command" hand-over, `store/deskGood.ts`); a fitting made here → this city's Workshop face; a fitting made
  elsewhere → that harbour on the map (`chart/goTo.ts`).
- **Build**: by design the Build button stands only when nothing is short (`ready` = buildable, a fleet here, no
  shortfall). Proven server-side: with the materials ashore and the labour in the purse, `BUILD` lays her down
  (`tests/rpc.yardSources.spec.ts`).

## Measured
- Prod, read-only, the function body as a plain SELECT at Lisbon for the Barca (EXPLAIN ANALYZE of STABLE functions,
  `explain (analyze, buffers)` of the body in `scripts/ops/harness/yard-sources/answer.sql`, run by hand — the harness guard keeps EXPLAIN ANALYZE out of the repo): 72.8, 64.9, 73.3 ms execution. Answer identical to the local world.
- Local (PGlite): ~40 ms a call with fittings, ~3 ms without; self-assert over 103 hull classes 4.5 s.

## What the data says (reported, not changed)
From Lisbon the Barca's goods are sold nearest at Funchal (timber, 505 nm), La Rochelle (ships-nails, 665 nm),
Portsmouth (cordage, 867 nm) and Bergen (tar, 1,517 nm); her two fittings are made at Lisbon. The labour is 15,000 d.; a new company holds 40,000 d.
