# Full names — a name is printed whole, everywhere (2026-11-11)

The owner's rule, absolute: a NAME (a city, a good, a fleet, a ship, a captain, a house, a merchant, a route) is never cut with "…" in the game. It is printed whole, wrapping at a space if it must. Client only; no migration, knob or flag.

**Stacked on #589 (`trade-layout`): merge after it.** #589 added the one rule for this, `KEEP_WORDS_CLASS` (`src/components/ui/tileStyles.ts`: `min-w-min break-keep` — a name turns only at a space and its box is never narrower than its longest word). This slice reuses it; it does not copy it.

## What was there

Until this slice the game's rule was the opposite for names. `src/components/ui/Clip.tsx` said: "a short NAME in a fixed column (a ship, a captain, a good on a tile) may be cut with `…`", and carried the full text by a hover title or a press. 35 places asked `Clip` for a name. Six more places cut a name with a bare `truncate`. The two the owner saw are on "Your cargo" (`CargoBest.tsx`): the good's name, and each city's name in its row.

## What changed

1. **`Clip` now prints a name whole** (`src/components/ui/Clip.tsx`). Same address, opposite rule, so every place that already asked it for a name gets the rule at once: one `block` span with `KEEP_WORDS_CLASS` and the mark `data-name`. The cut line, its hover title and its press-to-read layer survive only behind an explicit `cut` prop, for what is not a name (one user: the top bar's clock line).
2. **The six bare `truncate` names** now go through `Clip` or `KEEP_WORDS_CLASS` (list below).
3. **Four rows had to give the name room** (each measured, below):
   - `CargoBest.tsx` (a city's row on Your cargo): one wrapping line, the city then its three figures together at the right, in place of a four-column grid whose first column could shrink under the name's longest word. The flag is tied to the name's first word.
   - `Tile.tsx`: the name's block is never narrower than its longest word, and stands under the tile's mark when that word does not fit beside it.
   - `OnBoard.tsx`: the row asks Row's own `pair` rule (the two price cells stand under the label in a container under 22 rem) and is its own query container. Before, the label had 78 px beside the price cells.
   - `MarketLeft.tsx`: the chart's head line wraps, so the two prices stand under a long good's name instead of the name being cut.
4. **The law**: `tests/names.whole.spec.ts` (a lint and a walk, below). `tests/fleets.you.grow.spec.ts` asserted the old cut state (a captain's 47-character name IS cut at 320 px and a press reads it); it now asserts the name stands whole on more than one line with no word broken, and that a press on it is the row's press.

## The full classified list

Swept in `src/`: `truncate`, `text-ellipsis`, `line-clamp-*`, `overflow-hidden` with `whitespace-nowrap`, `text-overflow`, and JS shortening (`.slice(0,` / `substring` / `substr` followed by "…" or "..."). No `text-ellipsis`, no `line-clamp-*` and no CSS `text-overflow` rule exists in `src/`.

### (N) could cut a name — FIXED

Bare `truncate`:

| where | the name | fix |
|---|---|---|
| `features/command/buysell/CargoBest.tsx:101` | a good (Your cargo) | `Clip` |
| `features/command/buysell/CargoBest.tsx:173` (`cargo-place-name`) | a city (Your cargo) | `Clip`; the row is one wrapping line |
| `features/command/city/City.tsx:93` | the city over the desk's City face | `Clip` |
| `live/MarketLeft.tsx:52` (`city-market-chart-good`) | the good the market chart shows | `Clip`, the line wraps |
| `components/ui/Detail.tsx:64` (`SummaryRow` title) | a good (`RequestPage`), a city (`Report`, `stats/Cities`), else a word | `KEEP_WORDS_CLASS`, `data-name` |
| `components/ui/Detail.tsx:132` (`DetailPage` title) | a fleet (`FleetsScreen`), a ship (`MoveShip`), else a word | `KEEP_WORDS_CLASS`, `data-name` |

Through `Clip` (fixed by the change to `Clip` itself; the caller is unchanged unless noted):

| where | the name |
|---|---|
| `components/ui/Tile.tsx:114` (every tile: `ShipTile`, goods, captains) | a ship, a good, a captain — tile changed, see above |
| `components/ui/Field.tsx:94` (a picker's value) | whatever is picked — dropped the caller's `min-w-0` |
| `components/ui/Corner.tsx:65` (a map corner's label) | a label — dropped the caller's `min-w-0` |
| `components/ui/Sheet.tsx:97`, `:118` (a page's title) | a city (the City page), else the tab's word |
| `components/ui/TrayTitle.tsx:40` (every tray's head) | a city, a fleet, a merchant |
| `features/command/CommandScreen.tsx:163` | the word "Trade" |
| `features/command/FleetPicker.tsx:106`, `:199` | a fleet |
| `features/command/levels/Levels.tsx:177`, `:200`, `:232` | a nation, a ship, a captain |
| `features/fleets/FleetsScreen.tsx:218` | a fleet |
| `features/gallery/GalleryScreen.tsx:152` | the gallery's sample name |
| `features/stats/Merchants.tsx:83`, `:211` | a house, a merchant |
| `features/you/YouScreen.tsx:171` | a ship |
| `live/CargoSheet.tsx:47`, `live/NavySheet.tsx:47`, `live/PirateSheet.tsx:46` | a fleet |
| `live/MerchantRow.tsx:59` | a merchant |
| `live/MerchantSheet.tsx:235` | a route (but see "not fixed": the name itself arrives cut) |
| `live/OnBoard.tsx:110` | a good — row changed, see above |
| `live/PortForge.tsx:139`, `live/PortProduction.tsx:313`, `live/RequestBoard.tsx:68` | a good |
| `live/ShipAugments.tsx:87` | a fitting |
| `live/TradeHistoryPanel.tsx:357`, `:370` | a good, a city |
| `live/YourCaptains.tsx:48` | a captain |
| `features/map/CityHarbour.tsx:178`, `features/map/VoyageTray.tsx:147` | a fleet, a ship. These two FILES belong to another open PR and are not edited; the names in them are whole because `Clip` is |

### (N) cut a name in a file another PR owned — FIXED after #584 merged (2026-11-12)

When this slice was built these two stood in files #584 owned, and were listed as not fixed. #584 is on main; both are fixed here.

| where | what it was | fix |
|---|---|---|
| `features/map/RouteBar.tsx:129` (`route-summary`) | `truncate` on "Route · {the fleet's name} · N stops" | `KEEP_WORDS_CLASS`, `data-name`: the line takes a second line when it must |
| `live/standingRouteDraft.ts:93` (`routeName`; it was in `features/command/`) | a route's name is its ports joined by " ⇄ ", then `name.slice(0, 23) + "…"` past 24 characters | see "A route's name" below |

**A route's name.** The 24 is the server's: `standing_routes_name_length check (length(btrim(name)) between 2 and 24)` (migration 0092). A player never types this name; the game makes it from the route's ports, and three ports already pass 24 characters. Decided by default, with no migration:

- The stored name is a KEY, not what the player reads. `routeName` keeps the first 24 characters of the ports line and no longer adds "…" (nothing pretends).
- What the player reads is `routeTitle(name, stops, portByCode)` (`src/domain/route/index.ts`), the one place that answers "what is this route called": when the stored name is the cut start of the route's own ports (with or without the old "…"), it answers with the WHOLE line of ports; a name the server holds whole (a merchant house's route, a short route) is printed as it is. So routes saved before this slice are whole too.
- Asked at the three places a route with stops is named: the desk's spare routes (`RouteFold.tsx:157`), your fleet's tray on the map (`VoyageTray.tsx:366`, "Trading of …"), the trade history tray's line (`TradeHistoryPanel.tsx:55`).
- The owner may prefer the server to hold the whole name (a migration raising the limit); then `routeTitle` becomes a pass-through.

### (O) cuts something that is not a name — LEFT

| where | what it cuts |
|---|---|
| `components/ui/Clip.tsx` (`cut` mode) + `app/TopBar.tsx:83` | the game date, hour and price countdown in the 32-px top bar on a phone: figures; read whole by hover or press |
| `components/ui/LoadMeter.tsx:64` | the loading step in hand ("Opening the world"): a status line |
| `features/map/RouteBar.tsx:125` | why Final was refused: the server's sentence, one line in the bar (has a `title`). By the game's older rule a sentence should wrap too; left as it is, listed |
| `features/map/RouteBar.tsx:146`, `:167` | the Confirm and Repeat buttons' words (a verb, or "Via 2", "No water") |

`whitespace-nowrap` with no clip (a long text would run, not be cut; none holds a name): `Figure.tsx:66`, `GoodClassMark.tsx:65`, `GoodKind.tsx:74`, `Rarity.tsx:59` (a class or rarity word and its mark); `ListPanel.tsx:214`, `:246` (a count); `PricePair.tsx:73`, `StockGauge.tsx:80`, `Invest.tsx:84`, `:86`, `WhyThisPrice.tsx:41`, `:49`, `TradeBoard.tsx:41` (figures); `Row.tsx:193` (a row's value: a figure), `Row.tsx:284` (a fixed column); `ShipTile.tsx:91` (a power word and its figure); `StatCell.tsx:130` (a stat's label); `TradePanel.tsx:521` (the Insure chip); `HullCrown.tsx:14` (a crown word); `VoyageTray.tsx:180`, `MerchantSheet.tsx:273` (a lap's profit pill).

`overflow-hidden` with no text rule on a name: the shell and page frames (`AppShell.tsx:127`, `:133`, `screenLayout.ts:36`, `Detail.tsx:118`, `Tray.tsx:197-198`, `ListPanel.tsx:236`, `DeskFrame.tsx:83`, `:112`, `:126`, `TradeTray.tsx:403`, `RouteBar.tsx:108`), bars and gauges (`Bar.tsx:104`, `LoadMeter.tsx:67`, `StackedBar.tsx:61`, `StockGauge.tsx:75`, `ShipPanel.tsx:222`), charts and pictures (`Minimap.tsx:172`, `SmallChart.tsx:280`, `SeriesChart.tsx:159`, `MapScreen.tsx:500`, `CityScreen.tsx:411`, `GalleryScreen.tsx:357`, `:367`), floating panels (`Corner.tsx:52`, `NewVersionToast.tsx:93`).

`.slice(0, n)` with no ellipsis: list caps ("the first N rows"), dates and parsing; none shortens a name's text.

## The law: `tests/names.whole.spec.ts`

**The lint (plain Node).** No cutting class (`truncate`, `line-clamp-*`, `text-ellipsis`), no `<Clip cut>` and no "slice and add …" may stand in `src/` unless its file is on the allow-list with its reason and its count; none at all may stand on an element marked as a name (`data-name`, or a `<Clip>` without `cut`). The allow-list is four files: `Clip.tsx`, `TopBar.tsx`, `LoadMeter.tsx`, `RouteBar.tsx` (the refusal sentence and two button words). A second case proves the scan sees a cut when there is one.

**The walk (the served build).** At 390 × 844 and 1,280 × 800, in English and Korean, in the veteran's world (`tests/manyFleets.fixture.ts`: eight fleets, one with the longest name the chain allows — "Nossa Senhora da Estrela", 24 characters — and a captain with a 47-character name), after buying one unit so the hold has cargo. Every `data-name` on each screen is read: not cut (no ellipsis, no clip, no overflow of its own box), no word on two lines, inside every box around it, over none of its neighbours, nothing scrolling sideways. Then the same again with the longest real names put in its own text: a slot showing a city gets the longest cities (data/ports.json), a good the longest goods (data/goods.json), a hull the longest hulls (data/ships.generated.json), each in the language shown; anything else gets the longest of the fleets, captains (data/officers.json) and houses, masters and merchant fleets (data/npc-houses.json).

The names put in:

| kind | English | Korean |
|---|---|---|
| city | Santa Cruz de Tenerife · Sanlucar de Barrameda · Machilipatnam (longest word) | 산타크루스데테네리페 · 산루카르데바라메다 |
| good | Bird-of-Paradise Plumes · Palm-leaf Manuscripts | 마그레브 황동 세공 · 셰필드 도금 은기 · 앵무새·원숭이 |
| fleet, captain, house | Commandeur Joris van Spilbergen · Senhor de Engenho Duarte Coelho · Nordlandsfarten (longest word) | the same (people's and players' names have one spelling) |

Screens walked: Trade; Trade › Your cargo; the desk's five faces; the City page with each of its five buildings pressed (hall, market, production, port, inn); Production; Fleets; a fleet's page; You; Stats (six faces); Rank (two); Routes; the Codex (four); the map's city tray.

## Measurements (local build, `vite preview`, headless Chromium)

**The walk**, run at three glasses in both languages (1,920 × 1,080 by hand, `NAMES_WIDE=1`; CI holds 390 and 1,280):

| | screens read | names read | read again with a longest name | faults |
|---|---|---|---|---|
| en-US 390 | 30 | 164 | 490 | 0 |
| en-US 1,280 | 30 | 521 | 1,198 | 0 |
| en-US 1,920 | 30 | 521 | 1,198 | 0 |
| ko-KR 390 | 30 | 164 | 484 | 0 |
| ko-KR 1,280 | 30 | 521 | 1,555 | 0 |
| ko-KR 1,920 | 30 | 521 | 1,555 | 0 |

(The sums of the walk's own lines. The same name on two screens is counted twice. On a phone the Production board is a page of its own, so 357 fewer names stand on the walked screens than on the wide desk.)

What the walk found on the way, each fixed before the zero:

| where | measured | fix |
|---|---|---|
| a ship's tile on a fleet's page, 390 | "Nordlandsfarten" is 124 px; the name had 121 px beside the mark | `Tile`: the name's block keeps its longest word and drops under the mark when it must |
| "On board" on the desk's City face, 1,280 | the row is 318 px; the label had 78 px beside two 112-px price cells; "Palm-leaf Manuscripts" (95-px word) ran 17 px under the buy cell; the label stood on 3 lines (72 px) with its own short name | `OnBoard`: `pair`; the label has the line (280 px), the cells stand under it. Row height 118 px before, 126 after, and 126 with the longest name (was 142) |
| the same, Korean | "앵무새·원숭이" turned at its middle dot in 78 px | not a fault: a name may turn after its own "·" as after its own hyphen (the spec says so); with the fix it stands on one line anyway |
| a city's row on "Your cargo", Korean, 390 (one run of the walk; the cell's width follows the row's figures) | 산타크루스데테네리페 is one word: the flag stood alone on the first line and the name on the second, 17 px under the price | `CargoBest` `PlaceRow`: the row is one wrapping line (the city, then the three figures together at the right); the flag is tied to the name's first word by a no-break space; where the longest word does not fit beside the figures, the figures stand on the next line |

**"Your cargo"** (the page the owner saw the cut on), with one good aboard and seven city rows:

| glass | the row | the city's cell | the three figures | a row with a short name | a row with a longest name |
|---|---|---|---|---|---|
| 390, English | 342 px | 153 px | 165 px | 30 px, one line | "Santa Cruz de Tenerife", "Sanlucar de Barrameda": 48 px, two lines, turned at a space ("Sanlucar de Barrameda" is a real row there). "Machilipatnam": 30 px |
| 390, Korean | 342 px | 160–168 px | 150–158 px | 30 px | 산타크루스데테네리페, 산루카르데바라메다: 30 px, one line |
| 1,280, both | 1,008 px | 818–834 px | 150–166 px | 30 px | 30 px, one line |
| 1,920, both | 1,008 px | 818–834 px | 150–166 px | 30 px | 30 px, one line |

The good's name over the rows: "Bird-of-Paradise Plumes" 164 px and 마그레브 황동 세공 119 px, each on one line at all three glasses.

In every row, at every glass, with every name: the price stands 6 px under the row's top (the same in every row, short name or long), the price, the days and the profit stand on one line, inside the row, uncut, and the page does not scroll sideways. A row is taller only when its own name needs a second line.

**The market chart's head** (City › market): the good's name is whole at 390, 1,280 and 1,920 in both languages, as it stands and with the longest goods put in (the walk's "City › market" line: 2 names, 0 faults, six times).

## Checks

- `tsc -b`: clean. `eslint .`: clean. `vite build`: built.
- `tests/names.whole.spec.ts`: 8 of 8 with `NAMES_WIDE=1` (2 lint, 6 walks); CI runs 6 (2 lint, 4 walks).
- `tests/fleets.you.grow.spec.ts` (updated), `tests/sections.spec.ts`, `tests/duplication.spec.ts`: green.
- Run as a net because `Clip`, `Tile` and the summary row are everywhere. On the final build: `align`, `command.sellCargo`, `trade.map` (38 of 38 with the four above). One build earlier (before the cargo row became a wrapping line and the market chart's head a wrapping line): `trade.layout`, `onepage`, `fleets.design`, `you.design`, `codex.design`, `desk.terminal`, `primitives.geometry`, `shell.kstClock`, `city.phone`: all green but one. `city.phone` was run again after the market chart's change: the same one red, nothing else.
- **The one red is not this slice's**: `tests/city.phone.spec.ts`, "in Korean › the HQ's six faces are legible and clean at 320×640" — `market: (a) two texts cross — "안 삼" × "574" (5×5)`. It fails the same way on the untouched base (`origin/trade-layout` at 524d3870, built and run with this slice stashed). It is a price cell's word over a figure, not a name.

## Not proven

- **320 px.** The walk holds 390 and 1,280 (and 1,920 by hand). At 320 only the specs that already ran there were run (`fleets.you.grow`, `city.phone`).
- **Screens the walk does not open**: the Ledger, the Profile, the Inn's and the Yard's pop-up pages, a ship's augment page, the Forge, the request board, the trade history panel, the merchant / navy / pirate / cargo sheets on the map, and your own fleet's tray on the map (`VoyageTray`). Their names go through the same `Clip`, so they follow the same rule, but their rows were not measured with long names. `align.spec` walks several of them for alignment and is green.
- **Names that never went through `Clip`** and carry no `data-name` (a goods card's name in `TradeCard`, `TradeRow`'s name, the chart's own labels): they were not in the sweep's hits (they wrap already, with `break-words`) and are not walked by the new spec. `break-words` can still break a word inside itself when the word is wider than its box; that is a different defect from "cut with …" and was not measured here.
- **A route's name on a real long route**: `routeTitle` is proven by type-check and by `map.routebuilder`'s own assertion that the desk's route row lists the harbours; no spec saves a route of three long ports and reads the three places that name it.
- **Before numbers** for "Your cargo" were not measured on the old build; the old state is read from the code (`truncate` on both names).
- **CI** was not waited for.

## Decided by default

- `Clip` keeps its name although it no longer clips by default. Renaming it would touch 35 call sites, two of them in files another PR owns. The owner may ask for the rename once those PRs are in.
- The summary row's title and the pop-up page's title carry `data-name` although many of them are plain words ("Cargo", "Map"): a title is where a name can stand, so the law reads all of them.
- A name may turn after its own hyphen or middle dot, as in #589's spec.

## After the merge with main (2026-11-12)

Main moved under this branch (#583, #584, #586) and #589 gained two commits. CI on the merge showed three reds of this slice's own; each read to its element:

| red | cause | fix |
|---|---|---|
| the lint | #584 moved `standingRouteDraft.ts` to `src/live/` and gave the route bar a fifth button with `truncate` (4 marks, the list said 3) | the fleet's line and the route's name are fixed (above); the allow-list names what is left |
| the walk at 390, English and Korean | #589 (ca0d69ef) put the "Your cargo" and "Map" doors side by side, 187 px each. With "Nordlandsfarten" put in the Map door's title the row could not go under 219 px, and the desk scrolled sideways (407 px in 390; 399 in Korean) | `SummaryRow` (`Detail.tsx:59-74`) is a wrapping line on every glass: the title takes what the figure and the word leave, never under its longest word and never over its own width (the figure still hugs it), and where the longest word does not fit beside them the word and the chevron stand on the next line |

The walk gained two screens: your fleet's tray on the map (`VoyageTray`, listed above as not walked) and the route bar. 32 screens now; 0 faults at 390, 1,280 and 1,920 in both languages.

Checks on the merge (local, headless, one Playwright at a time): `tsc -b`, `eslint .`, `vite build` clean. `names.whole` 8 of 8 with `NAMES_WIDE=1`. Then `trade.layout`, `desk.layout`, `onepage`, `layout`, `map.routebuilder`, `shell.polish`, `fleets.you.grow`, `sections`, `duplication`, `align`, `command.sellCargo`, `trade.map`, `city.phone`, `drive.routes`, `route.stopface`, `hq.design`, `market.shortTray`: 117 of 123. The six reds are not this slice's:

- four are the HQ Market reds this branch inherits from #589 (`city.phone:113`, `hq.design:96`, `market.shortTray:53` at 390 and 1,280), with #589's builder;
- two are `route.stopface`'s plain-Node word tests (`:47`, `:77`): they expect English words ("All", "Any price") and this machine's locale is Korean ("전부", "가격 무관"), the case CLAUDE.md names; its browser tests are green.
