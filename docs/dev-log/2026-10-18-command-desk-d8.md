# 2026-10-18 — COMMAND DESK D8: PORT is deleted

Owner row 137: *"delete port tab, and focus on command tab"*. `docs/COMMAND_DESK.md` slice D8. Client only, no migration.

## What went
- `src/features/port/` (PortScreen, MerchantsHere, portView) and `src/store/harbour.ts`.
- The Port cell in `src/app/navTabs.ts`: the bar draws **four** cells — Command · Fleets · Map · Menu (`tests/nav.geometry.spec.ts` pins the four and refuses a Port or Market cell). `TRADE_ROUTES` is `['/command']`.
- `PortField`'s harbour-store path (read any harbour, "back to her quay"): its one caller is the route editor, so `onPick` is required and the ✕ only empties the search.

## Where each PORT act lives now (`tests/verbHomes.spec.ts` gates the homes; `tests/desk.sweep.spec.ts` walks them)
Trade (buy — run end to end, sell, bargain, basket, requests, supplies) · Town / Town Hall · Storage · Craft · Inn · Build · Repair · Skills: COMMAND › City, the same `src/live` faces PORT composed. Invest: COMMAND › Invest and City › Town. A distant city's prices: Markets › a good (Buy at / Sell at, every city) and the map's city panel. Merchants in port: the map's city panel (the one list). Old `/port` links: redirect to `/command` with the City face turned (`App.tsx` `PortMovedToCity`).

The map hand-offs: none opened PORT — the price tray's door already says "Open in Command" (D3).

## Specs
- Repointed `goto('port')` → `goto('command')` + `openCityFace` (new `tests/desk.fixture.ts`): layout (9), wide.layout (3), trade.ceiling (1), selection.lock (4), flags (1), map.merchants (2).
- Deleted, each with a note at its place: layout "port field on the sheet"; selection.lock's three port-field tests (the City face draws no field above its board); map.merchants "PORT at Lisbon lists the merchant"; `tests/port.merchants.spec.ts` whole (and its shard weight).
- flags: the City title's flag; the merchant-sheet flag moved to map.merchants' Porto test, where her sheet opens from.
- layout's K.1 fold: measured 3 complete rows above the fold on City › Trade (first row 536 px, fold 787 px); K.1's five-row floor now stands on Markets, the face a player lands on (6 priced rows measured).
- New `tests/desk.sweep.spec.ts` at 390×844 and 1440×900 — reached Trade, Town, Storage, Craft, Inn, Build, Repair, Skills of the eight Lisbon has, at both sizes; shard weight 120.

## Verified once (local build, `vite preview --port 4260`, localhost)
`tsc -b` clean · eslint clean · verbHomes/sections/duplication/words 23 passed · desk.sweep 2 passed · nav.geometry 2 passed · layout + selection.lock 19 passed then the K.1 retarget 1 passed · wide.layout, trade.ceiling, desk.layout, desk.plan, desk.city, route.stopface, flicker, firstRead.empty, primitives.geometry, map.townhall 34 passed · map.merchants "shipped image" 1 passed · flags 3 passed (City title). The merchants-on map.merchants tests run in CI.

## Docs
OWNER_REQUESTS rows 55, 64 and 73 marked REVERSED BY ROW 137; row 137 BUILT (open until driven on the live site). COMMAND_DESK status line, `features/command/README.md` head, `live/cityFaces.ts` header.

Screens: `2026-10-18-command-desk-d8/` — `nav-bar-{1440,390}`, `desk-nav-{1440,390}`, `old-port-link-lands-on-city-{1440,390}`.
