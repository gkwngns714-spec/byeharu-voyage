# 2026-10-31 — A closed, teeming, fine-drawn harbour city (owner row 243)

The owner liked the legible city and asked for three more things in the same pass:
*"good. more tiny dot with huge number"*, *"make it a closed city. right now it is only a
section"* and *"smaller more buildngs too"*. The slice `city-organic` (client-only) answers all
three without inventing data.

## The closed city

- **A wall with gate towers.** The land is enclosed by a wall on the top, right and bottom and by
  the coast on the left; the coast opens into the harbour front — the quay gate — over y 84-160.
  A tower marks every corner, every road end on the wall and both ends of the harbour front. A dark
  margin of ground lies outside the wall on the three landward sides; the sea lies outside on the
  left. The street network, the blocks and all six named places are complete inside the boundary;
  the quay road and the three streets end at the wall or the quay, the three lanes end at the top
  and bottom walls.
- **The port is outside the left wall**: a breakwater and lighthouse, three wide piers into the
  sea, eight moored hulls, three cranes on the quay, crates and the quay lamps. The storage
  warehouses and the harbour crowd stay inside the wall, behind the harbour front.
- **Four-edge check.** The scene at 390 was re-shot and read: the top, right and bottom edges show
  the dark margin outside the wall and the left edge shows the sea/port; no block or road is cut.

## Smaller, more buildings

- The typical footprint dropped roughly by half: small houses are 3-5 units long and 2.6-3.8 tall,
  narrow halls 6-9 x 3-4.2, round towers r 1.2-1.6. Each block now packs three dense rows of them
  with alleys between (top, middle and bottom), and the building count roughly doubled to about
  160 (seed-dependent) from the previous ~70.
- The six named places stay markedly larger than the houses but were trimmed a step: the Town Hall
  is a 24x8 hall with a 10x10 tower and flag, the market square 26x22 with six 5x3.2 stalls, the
  warehouse rows 24x5 / 21x5 / 12x4, the forge a 13x7 hall with a 2.4x13 chimney, and the inn a
  16x10.5 range around a 6x5 courtyard.
- **Citizens.** A small house is 3-5 units long, so a person at half a house would be r 0.6-0.9.
  That risks the pin-prick the owner rejected earlier (*"no smaller tiny dots"*), so the people
  were kept ONE STEP LARGER: r 0.95-1.25 — about half a house's length, still clearly smaller than
  the buildings. The scene at 390 was read: the gold walkers on the streets and the market/quay
  clusters remain distinguishable beside the grey houses and above the 0.35-0.7 window lights.
- The 2,200-dot stipple (`city-teeming`) and the window lights (325 with the denser roofs) keep
  their roles: the stipple is texture, the lights are small and dim, the crowd is the readable
  layer.

## The huge population number

The Population cell was a "—" placeholder. It is now the card's headline: `≈ 160,000` for Lisbon's
served tier 5, with the caption *Estimated from the city's size* (EN) / *도시 규모에서 추정한 값*
(KO). The number is derived from the only served size figure, `port.size_tier`, on the documented
curve 8,000 · 18,000 · 45,000 · 90,000 · 160,000 (a comment in CityScreen.tsx says so). Status and
Relationship remain marked placeholders with their "next slice" caption. `city.page.spec.ts` now
asserts the population cell is NOT a placeholder, contains the "≈" glyph, is grouped digits and is
>= 1,000.

## Measured

Local-mode build served on 4203; `city.page.spec.ts` PASS: `city scroll: 390/390 wide, 844/844
tall, scrollY 0, rail bottom 844`; `small scroll: 320/320 wide, 568/568 tall, rail bottom 568`;
`360 scroll: 360/360 wide, 640/640 tall, rail bottom 640`; population prints `≈ 160,000`; the
scene-in-frame assertion is green at all three sizes; the walker moves > 0.5 px in 900 ms.
Counts: teeming 2,200, crowd 132, walkers 36, lights 325; figures card/earnings gap 12 px;
`tsc`/`eslint`/`npm run build` clean; `duplication` 11/11. Screenshots: the scene at 390 and the
full page at 390/320 (DPR 2) were read and judged before pushing.
