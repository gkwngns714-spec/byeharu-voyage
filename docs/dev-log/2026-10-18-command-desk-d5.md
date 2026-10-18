# 2026-10-18 — COMMAND DESK D5: the City face — every PORT building on the desk — `osn-desk-d5`

`docs/COMMAND_DESK.md` §2.2, §3.6, §10 row D5. **Client only, no migration.** PORT still stands; it is deleted in
D8.

## What was built

**City** (`features/command/city/City.tsx`) is the third face of the desk: Markets · Plans · **City**.
- **Which city:** the one the selected fleet is docked at. At sea it is the city the fleet is bound for, read
  only, with one line: *"Gaivota is sailing to Cádiz. Orders run when it arrives; until then this city is read only."*
- **Its faces:** PORT's own table — Trade · Town · Storage · Craft · Inn · Build · Repair · Skills. Each is offered
  only where its building stands, and a press selects.
- **What is shown with them:** the fair row, a tow for a wreck, and the city's flag beside its name.
- **Trade** is the quay's board with its basket, bargain, Requests (with Fulfil) and the Supplies row, exactly as
  on PORT. Read only (prices) when the fleet is not docked there.
- **Town** carries the city's buildings and, under them, **the Town Hall**:
  - the treasury and the day's money lines served since 0172 / 0174: Grant, Earnings, from and to the crown, and
    *Paid by its people*;
  - Invest, and the influence block (Donate, the mayor's tax).

**One copy of each face.** The sections rule forbids one screen importing another, so the faces PORT and the
desk both compose moved to **src/live**, as the Inn, the port field and the request board already had:

| Moved | Files |
|---|---|
| from `features/port` | PortTrade, PortTown, PortStorage, PortWorkstation, PortYard, PortShipyard, PortAcademy, PortFair, FulfilTray, HaggleThread, ManifestPanel, ManifestTotals, OnBoard, ReceiptFace, useHaggleState |
| from `features/map` | CityTownHall, TownHallInfluence |

- The faces table (`PORT_FACES`, the one building→word map) moved to `live/cityFaces.ts`.
- PORT's `portView.ts` keeps only PORT's own persisted face.
- PORT and the map's city panel import the moved files. No behaviour changed; only import paths did.
- The desk's tray slot (good page / plan builder / trade tray) stands aside on City. There, the Trade face's
  basket owns the slot on a wide screen.

**Flags** (`PortFlag`, #198) now stand beside every city name on the desk: the fleet chips, the good page's chart
chips, the Buy at and Sell at rows, the plan builder's chips, and the City heading.

## verbHomes, rewritten to §2.2

- **Rule 3** (the stepped question has one home) now names `live/PortInn`, `live/PortShipyard` and
  `live/PortTrade`.
- **New rule:** every building face is one component in src/live, and the desk's City face composes each of
  them — PortTrade, PortTown, CityTownHall, PortStorage, PortWorkstation, PortInn, PortYard, PortShipyard,
  PortAcademy, QuayFair and TowNote. No screen keeps a building face of its own.
- This is the gate D8 deletes PORT behind.

## A red on main this fixes

**What failed:** `route.stopface.spec` "a buy press moves nothing" fails on main as it stands. I built main
(a2502f1) and ran it: `secondStop 335 → 736`.

**Why:** since the flags, the editor stands taller. Picking the second stop leaves the first stop's chips above
the screen, so Playwright's click scrolls the page itself — the driver's scroll read as "the press moved the page".

**The fix:** the spec now brings the chip into view before it measures. The claim is the owner's again: the
**press** moves nothing. After the fix, before and after are equal (`736 → 736`).

## Verify (once)

- `tsc -b` and `eslint .` are clean.
- `desk.city.spec` (new, 390):
  - every face the city has — Trade, Town, Storage, Craft, Inn, Build, Repair, Skills — opens, and its panel is
    not empty;
  - a face press never moves the strip, and there is no sideways scroll;
  - Town carries the Town Hall;
  - a BUY from the Trade face's own tray changes the cargo.
  - 1 passed.
- On `localhost:4260`:
  - layout, wide.layout, map.townhall, trade.ceiling, desk.layout, desk.plan, selection.lock, firstRead.empty and
    nav.geometry: 46 passed.
  - route.stopface failed as on main, then passed after the spec fix, together with flicker: 8 passed.
- verbHomes, sections, duplication and words: 23 passed.
- Shots: `docs/dev-log/2026-10-18-command-desk-d5/` — City Trade, City Town and the Town Hall, each at 1440 and 390.
  The local world's city purse is dark ("Not open yet"), so its money lines are empty there. On prod the same
  component prints them.
