# 2026-10-31 — The city as a fine coastal plan (owner row 241)

The owner looked at the square map and said it was *"too... too orderly"*: *"it has to be random
dots, make everything the buildings road smaller at least 10 times, make roads and buildings that
are circular, and way more dots of population"*, then *"these dots are population, it can stop it
can go back and forth, random movements, and they could be in buildings like houses and more. show a
city"*, then dropped pressing (*"i don't need to be able to press buildings for building info. it
just have to be visually attractive, with port, sea at the side etc."*), settled the aim as
*"it doesnt have to be attractive, but sophisticated"*, and reported *"the map is sticking out of
its frame, meaning it is bigger than the square"*. The slice `city-organic` (client-only) answers
all five in one picture.

## The picture

- **Sea on one side.** The water is a calm tonal mass on the LEFT (fill-bg over the fill-surface
  land) with a single compound curved coast up the full 240-unit plate and four fine hairline wave
  lines. The quay edge is a second hairline; there are no colour fields and no gradients.
- **The port is the clearest thing after the lights.** Three piers into the water, six moored hulls
  (fine outlines with one deck line), two cranes on the quay, three storehouses with crates, and
  the warm lamps along the quay and at the pier heads.
- **The town is organic and circular.** ~460 seeded houses are tiny circles (radius 0.9–2.6, some
  hollow rings), densest against the coast and thinning outward; three exact ring roads (radii 22,
  42, 62) and five winding Bezier lanes are the only straight-weight geometry; the park and pond
  are quiet tonal shapes; the six named places remain as small picture marks (hall ring and gold
  flag, market's gold stalls, forge chimney and smoke, inn courtyard ring, storehouses, the port) —
  inert `data-testid="city-scene-*"` groups with no handlers.
- **The dots are people.** `city-crowd` holds 440 dots: 116 are animated (half wander short seeded
  loops, half walk a short line and turn back via keyPoints 0;1;0), the rest are still, and 45 % of
  all homes are placed inside a house. `city-dots` keeps the served tier's walkers (36 at tier 5)
  on the ring roads and lanes, `animateMotion`, no cx/cy. Lights (`city-lights`, 210) are the one
  accent: faint by day (0.20–0.48), glowing at night (0.50–1.00) while the town dims to 0.62.

## The frame, measured

The panel keeps `overflow-hidden` and `aspect-square`, the svg is `block h-full w-full` with the
same `preserveAspectRatio="xMidYMid slice"`, and every coordinate is inside 0..240.
`city.page.spec.ts` now measures the panel and `city-scene` boxes: each edge and both dimensions
agree within 0.5 px at 390×844, 320×568 and 360×640.

## The page

The six tiles are the only doors and are small again (68 px rows): the building's NAME is at the
top-left, the served city gold sits beneath the City Hall name (and only there), and the icon is a
quiet mark at the bottom-right. The figures card under the plan compresses its rows (`min-h-0`) so
all four figures and the "next slice" caption stay visible at 320; it and the earnings block keep a
12 px gap at all three glasses. No page scroll: 390/390×844/844, 320/320×568/568,
360/360×640/640.

Measured on a local-mode build served on 4203: `city.page.spec.ts` PASS (frame, no scroll, tile
faces, moving walker); `duplication` 11/11; tsc/eslint/build clean; counts crowd 440 / lights 210 /
walkers 36, with 116 crowd animations.
