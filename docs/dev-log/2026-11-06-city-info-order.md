# 2026-11-06 - City panel: Info first, and the money lines un-crowded (client only, no migration)

Owner, 2026-11-06: "the map - city - info - money in out taxes they are too crowded. fix this. and right now market port info etc. info should be at first order, then town hall, then whatever."

## What I saw first (headless, DPR 2, Lisbon)
`img/city-info/before-en-{1440,1280,1024,390}.jpg`. Money, In, Out and Taxes sat in a row of four (a 2 x 2 grid on the phone), each a caption over a figure with the coin. The local world shows 0 in all four, so the crowding in these images is the packed row and the captions; with live nine-digit money (StatCell.tsx notes 988 M) a quarter of the panel is narrower than the figure plus its coin, which I did not see on screen. The tab bar read Market, Port, Inn, Town Hall, Info, Giving, with Info fifth and the panel opening on Market.

## What changed
- `src/features/map/cityTab.ts`: `CITY_TABS` is the ONE order and the default tab is `CITY_TABS[0]`. Now: Info, Town Hall, Market, Port, Inn, Giving. `CityTabs.tsx` draws it as it stands. The City page and the desk are different surfaces with their own faces (Trade, Town, Inn) and are not listed here, so there is nothing to unify. The tab is not stored anywhere else; `Send fleet` still turns to Port by its own press.
- `src/live/CityInfo.tsx`: the four money figures are one column of the existing `StatCell look="line"` (label left, figure right on one edge, row-height lines, hairlines between), under a rule that sets the block apart from the facts above. No new component, no new tokens. Words are unchanged (EN and KO already short).

## After
`img/city-info/after-{en,ko}-{1440,1280,1024,390}.jpg`. Info is first and selected, the lines never touch, nothing scrolls sideways.

## Spec
`tests/city.info.spec.ts`: the tab order, that a city opens on Info, and at 1440, 1280, 1024 and 390 that the four lines do not overlap, stay inside the panel and do not overflow, with a nine-digit figure written into each.
