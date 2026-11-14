# A harbour stands on the shore that is drawn (2026-11-14)

Follow-up to `2026-11-14-fine-coast.md`. With the real coast on the glass, a city floating inland or out at sea next to it is the "weird map" again.

## What was wrong

A harbour's mark is set on the drawn shore by the landfall (`src/chart/landfall.ts`). It was run once, against the 110m world, and the mark kept that place at every zoom. Close in the chart now draws a fine coast, so the mark stood on a shore that was no longer there.

At the closest zoom on a 1,280 px glass, of the 237 harbours whose real shore is within 10 nautical miles, **165 stood more than 8 px from the drawn shore**. The worst was Nantes, 148 px.

## What changed

The rule is the same one. Its input is now the coast in hand.

- `landfall.ts`: `landfallPorts` takes either the 110m world's rings (as before) or a `ShoreInHand`, the fine tiles under the sheet. Same function, same 10 mile cap, same hair inside the shore.
- Against a fine coast, a harbour standing **inland** within the cap is brought to the shore too. Against the 110m world it is not, exactly as before.
- `useChartShore.ts` (new): one hook picks the coast for the view and runs the landfall against it in the same render. It hands back the coast, the ports and the islets together. The Map tab and the small charts both read it.
- So the mark, its name, its tap target, the dotted line of its roads and a docked fleet all move in the frame the coast under them changes. At a level change a mark moves no more than the coast does: at most about 6 px at the 110m to mid change, 5 px at mid to fine.
- Wide views are untouched: the same marks on the same 110m shore.
- A harbour off the fine sheet keeps its place on the world coast.
- `MapScreen.tsx` and `SmallChart.tsx`: the chart's surface is now created before the drawn model, because the drawn ports depend on the view. The tap is handed to the surface as one stable function. The opening frame still reads the ports on the world coast, so the frame cannot chase the marks.
- **A picture only.** The served coordinate, the roadstead point, routes, distances and the land rule are not touched. No migration.

## Measured (closest zoom, 1,280 px glass, from the real ports and the shipped tiles)

| harbour | before | now |
|---|---|---|
| Tainan | 129 px (8.4 nm inland) | 4.3 px |
| Tripoli (Libya) | 121 px (8.3 nm inland) | 4.3 px |
| Algiers | 96 px (6.6 nm inland) | 4.3 px |
| Ternate | 61 px (4.3 nm out at sea) | 2.7 px |
| Ceuta | 36 px (2.5 nm out at sea) | 0.9 px |
| Nagasaki | 28 px | 4.3 px |
| Venice | 10 px | 4.3 px |

4.3 px is the landfall's own hair inside the shore (0.005 degrees). Of 249 harbours, 207 are set on the fine shore by the landfall, 30 already stood on it, and every one of those 237 is now within 4.3 px and on drawn land.

**Beyond the cap, left where the data puts them (12, river cities):** Amsterdam, Ayutthaya, Basra, Hanoi, Hooghly, Hoorn, Kaliningrad, London, Ningbo, Pustozersk, Rotterdam, Seville.

## Guard

`tests/map.fineCoast.spec.ts` (8), plain Node: at the closest zoom every harbour whose fine shore is within the cap is drawn within **8 px** of it and on drawn land; the harbours beyond the cap are exactly the 12 named, so a new one fails the test.

## Decided by default (the owner may reverse)

- **River ports within 10 miles of the sea are drawn at the river's mouth** close in (Nantes, Lübeck and the like). The land file has no rivers, so the other choice is a city in the middle of the land.
- **Ningbo is 10.1 miles from the shore**, just beyond the cap, and stays inland.

## Left

- **The roadstead point** (the small circle the dotted line runs to) is the server's, placed for the 110m coast. Close in it can stand on fine land or far from the fine shore. Moving it is not a picture change.
- **A sea place** (the Strait of Gibraltar's lozenge) is the server's point too and is never moved; close in it can stand on fine land. Seen at Ceuta.
- The mid level uses the same rule; only the fine level is held by the guard.

## Proven, and not

Run: `tsc -b --noEmit`, `eslint` on the touched files, `vite build`, `tests/map.fineCoast.spec.ts` and the plain-Node half of `tests/map.landfall.spec.ts`. Looked at: Tainan, Tripoli, Algiers, Ternate and Ceuta at the closest zoom, phone and desktop (`C:\Users\gkwng\dev\fine-coast-shots\onshore-<place>-<phone|desktop>.png`). Not run: every other spec; main's Acceptance run is the net. Specs that tap a harbour at a close zoom read the mark's place from the page, so they should follow it.
