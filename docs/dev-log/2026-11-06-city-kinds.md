# Every harbour shows its kind (owner row 298, 2026-11-06)

Order: *"show what they are, if they are city, capital city, island city etc."* (after *"is angra an island?"*). The map is not touched, by the owner's follow-up.

## What was found
- Capital: all 23 nations' `capital` codes resolve to a port of that same nation (checked on `deriveWorld`, the build's own world; not read from prod). Their sizes are mixed (e.g. Safi, Karachi are size 2), so a capital is labelled by capital, not by size.
- Size: `size_tier` 5 / 3 / 2 = a great entrepot / a working port / a small harbour (migration 0058). 35 / 82 / 129 ports.
- Island: in no data. `src/domain/port/islandPorts.ts` is the one authored list, read from all 246 ports in data/ports.json; its header holds the rule and the close calls. The database mints its own port ids, so the client matches the served name; the law test holds every id real, every name equal to its id's, and unique.

## What changed
- `src/domain/port/cityKind.ts`: `cityKind(port, nationByCode)`, the kind filter helpers; `src/live/useCityKind.ts`: the one hook.
- Six labels, EN and KO, under `port.kind*`. City = size 5, Town = size 3 or 2.
- Stats > Cities: the kind leads each row's facts line, and a Kind picker joins Area and Country (Capital, City, Town, Island). Stats city page and City page headers carry it beside the name.
- Counts over the 246: Capital 19, Island capital 4 (London, Copenhagen, Sakai, Banten), City 15, Island city 6, Town 122, Island town 80.
- Law test `tests/cityKind.law.spec.ts` (red with Angra removed from the list, green with it); `tests/stats.filters.spec.ts` gains a Kind case.
