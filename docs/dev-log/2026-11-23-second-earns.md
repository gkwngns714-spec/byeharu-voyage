# The second hull earns while away (roadmap 2026-11-23, slice 6; play-test 3 finding 26)

Client only. No migration, no new server door.

## What changed
- **A launched hull is asked one question** (`src/app/LaunchOffer.tsx`, an overlay at the top of the glass). Between two world reads in
  a visit, a ship id no fleet held appears in a docked fleet of two or more: the card shows her picture, "Andorinha launched", the
  route line, and two presses: **Own fleet** and **Join Gaivota**. Own fleet runs three existing doors in order: `cmd.move_ship` with a
  new fleet named after the hull, `HIRE n` for the hands she lacks, and the one route path (`saveAndStartRoute`: save + assign) with a
  copy of her best route. A refused step prints the server's sentence; the next press resumes from that step.
- **Best route** (`domain/route bestRouteAt`): of her saved routes that call at the harbour the hull lies in, the highest all-time net
  (`earnings.total.net`); a route that lost money is never offered. No saved route: her last trip to or from that harbour made a route
  (`tripRoute`, the arrival card's Make route).
- **The red crew line says what to do** (`src/live/CrewHint.tsx`): under the desk's Ship crew row and the fleet's More page, the crew
  glyph, the hands short ("−8") and one press "Hire crew · 8" (`HIRE 8` through the store's `issue`). At sea: "Hire in port".
- **While away** names each FLEET with its picture, its route under it, and the route's earnings.
- **The goal card** reads a met requirement as "Trading 7 ✓" (an unmet one stays "Trading 3/4").

## Decided by default
- The card is offered only when there is something to repeat (a route or a trip) and the server says the fleet may found one
  (`world.ship_moves` `can_new`); otherwise the hull stays where it joined, with no card.
- The copy of the route is the route as saved (no extra crew-up stops); the crew is hired once, before the route starts.
- The new fleet takes the hull's name.
- The hint's press hires directly (no trip to the Inn), as the yard's BUILD and the workstation's MAKE issue their fixed lines.
- The You page keeps its own "Trading 1/2 · Exploration 1/2" sentence (out of this slice's scope).

## Checks
- `tsc`, `eslint`, `vite build`; specs against a served build: `second.earns` (fixed facts), `second.ship` (goal card tracks, the crew
  hint pressed and gone), `goal.card`, `route.inReach` (the While away row names the fleet), `sections`, `verbHomes`, `i18n.keys`, `words`.
- Not driven in a browser: the launch card's three steps end to end (it needs routes lit, a route, and a launched hull in one world).
