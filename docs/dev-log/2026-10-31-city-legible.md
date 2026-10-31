# 2026-10-31 — The city redrawn to read as a city with citizens (owner row 242)

The owner looked at the shipped organic picture and said *"wtf is this city ... does this look like
a city with citizens?"*, then corrected the dot scale: *"no smaller tiny dots, scale it with
buildings"*. The slice `city-organic` (client-only) redraws the drawing as a legible coastal city
and keeps everything else (square plate, no pressable map, tiles with names top-left, no scroll).

## The city

- **A street network, then blocks.** The quay road runs the coast; three broad curved streets and
  three narrower lanes cross the land, and the blocks sit between them, each with a faint ground
  and one outline. The roads are continuous lighter lines (stroke-ink-faint; 3 units for the broad
  streets, 1.3 for the lanes), not scattered marks.
- **Buildings read as buildings.** Each ordinary block carries rows of real buildings along its
  street edges: long halls with a ridge line, small houses, round towers and a courtyard house, in
  pale roofs (fill-ink-faint, 0.6–0.78) with one consistent thin outline. Their widths and heights
  vary with the seed.
- **The six named places are larger and distinct.** Town Hall: a 30×10 hall, a 12×12 tower, a gold
  flag and a fountain plaza. Market: an open square with six stalls and the largest crowd. Storage:
  three long warehouse rows with crates. Forge: a 16×9 hall, a tall chimney and three smoke rings.
  Inn: a building around an 8×6 courtyard with a tree. Port: a breakwater and lighthouse, three wide
  piers, eight moored hulls, three cranes, crates and the quay lamps — the sea side is unmistakable.
- **Citizens are people, at the buildings' scale.** Warm accent dots of r 1.55–1.95 (a small house
  is r ≈ 2.5–3), never pin-pricks. The served tier's 36 walk the road network on animateMotion;
  132 gather at the market (34), the quay (24), the hall plaza (12), the streets (40) and the
  outskirts (10), with 12 strolling short lines. The 225 window lights stay small and dim as
  texture, clearly below the crowd; the city is not pressable, and all six named marks are inert.

## Measured

On a local-mode build served on 4203: `city.page.spec.ts` PASS — `city scroll: 390/390 wide,
844/844 tall, scrollY 0, rail bottom 844`; `small scroll: 320/320 wide, 568/568 tall, rail bottom
568`; `360 scroll: 360/360 wide, 640/640 tall, rail bottom 640`; the scene-in-frame assertion is
green at all three; the walker moves > 0.5 px in 900 ms. Counts: crowd 132 + walkers 36 = 168
citizens, lights 225; the figures card/earnings gap is 12 px. `tsc`/`eslint`/`npm run build` clean;
`duplication` 11/11. Screenshots (scene alone at 390 and 2× crops of the harbour and the market)
were read and judged: the buildings and people are in one scale and the picture reads as a city
with citizens in one second.
