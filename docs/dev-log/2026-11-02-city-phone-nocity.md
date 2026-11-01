# 2026-11-02 — THE HQ WITH NO CITY IN HAND (branch `city-phone-nocity`, client-only; part 4 of the HQ-on-a-phone slice)

> The coordinator's layout sweep, row 8: *"HQ when the fleet in hand is bound for a cape or open sea — the whole page is one line, 'No city in hand.', plus the rail: 740 px (390, of 787) / 536 px (320, of 583) of glass empty;
> no doors, no header, no way to pick another fleet from HQ."* The slice is `docs/dev-log/2026-11-02-city-phone.md`; this is its fourth PR (it stands on the first, for the law's fixture).

## 1. Inventory (served `main`, headless, `/city?port=CSV` — a SEA_PLACE, which is exactly what a fleet bound for Cape St Vincent makes `fleetPortCode` answer)

`CityScreen.tsx`: `if (!port || port.kind !== 'HARBOUR')` drew `<Note>No city in hand.</Note>` in a `p-gutter` box and the rail — nothing else. At 390×844 that is one 20-px line over 740 px of glass; no fleet to pick, no
word on what the fleet in hand is doing. The only ways out were the rail (Map, Fleets) — a player who sent her flagship to a cape and came back to the HQ saw a wall.

## 2. The change

`NoCity` (in `CityScreen.tsx`): the old line, then **YOUR FLEETS** — one `Row` per fleet of the house, her name and under it what she is doing (the one where-rule, `whereLine(whereabouts(f))`, `to Cape St Vincent · 3 h`
on the page's own clock), the fleet in hand in gold; a press **selects** her (`useCommandDraft().selectFleet`, the one selection the desk's picker and the Map write), so a fleet that lies in a harbour, pressed, makes the page that
harbour. The picker's own component lives in `features/command`, a screen this one may not import (`tests/sections.spec.ts`); on a glass that has the room the list is the picker. No new word (`city.noCity`, `command.fleets`),
no new primitive, no data.

## 3. The law (`tests/city.nocity.spec.ts`; red on `main` — the state has no test id there)

At 390×844, 320×640, 1280×800 (and 390 / 320 in Korean): the state stands; every fleet of the house is a row of ≥ 44 px with a second line saying where she is; the rail stays; the page does not scroll; it is clean by the HQ's laws
(`phoneLaws`, now spelt once in `tests/unfold.fixture.ts` and read by this spec and `city.phone.spec.ts`); a press moves the gold to the fleet pressed.

## 4. Not done

The state is still mostly empty glass (a list of two or three fleets over 600 px): there is no city to draw, and inventing content to fill it would be an invention. A route to the Map for the fleet in hand ("show her") is one press away in the rail and was
not duplicated here.
