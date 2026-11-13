# Phone tidy 4: every lit screen holds its lines at 390 and 320 (2026-11-14)

Owner row 318 (2026-11-12, on a phone): *"the map ui graphic became shit, so those rest of ui. word box overlapping, long words and sentences makine new messy lines... fix all. especially on phone."* Three passes fixed the screens that existed on 2026-11-12 (`2026-11-13-small-screens.md`, `2026-11-13-small-screens-2.md`). Since then many screens went live and ten switches were lit. This pass walks the lit game and fixes what it found. Client only: no migration, no knob.

## The walk

1,280 × 800 was spot-checked with the same script on the fixed build (the shipped world, eight fleets, a battle).

A script (kept out of the repo: a measuring tool, not a law) opened every screen at 320 × 640 and 390 × 844, in English and Korean, and pressed every tab, row, door and button it found, up to four presses deep, with the close buttons last. On the map it also pressed fight rings (on the rim), fleets, city names and a track, and then walked the tray that opened. It ran in the shipped world and in the staged worlds the specs keep: eight fleets and six captains, an armada of two fleets, an armada in battle, a battle being fought, a flight, a raid ring, a navy-fight ring, a raid just settled, a pirate company at Port Royal, the brethren open, the seas lit, worn gear, captain skills, merchants at sea, two ships with fleet room lit. At every stop, at the top and at the foot of every scrolling box, it flagged: text over other text, a word broken inside itself, text clipped or off the glass, text cut with dots, a label of 14 letters or fewer on two lines.

## What was found and fixed

| where | size, language | what | fix |
|---|---|---|---|
| top bar, every screen | 390 and 320, Korean | with a purse of six figures the game date was cut with dots ("1507년 4월 26일 · 0…"); at 320 by 2 px | the right side is one wrapping line, one line high: what does not fit goes out whole, the clock's word first, then the clock; the date is cut only when the date and the purse alone do not fit (`src/app/TopBar.tsx`) |
| HQ, the title | 320, English | "Port Royal" and "Island capital" each on two lines beside the day | the name turns only at a space; the kind is one line and goes under the name (`CityScreen.tsx`) |
| HQ, City hall figures | 320 | a rich city's gold ("99,960,000" and its coin) stood past the card's edge | a cell is half the line at least and as wide as its figure; the cell that no longer fits takes the next line (`CityHallPanel.tsx`) |
| HQ, Production, Cargo: the fleet picker | 320 and 390 | eight fleets in four 76-px columns: "Nossa Senhora da Estrela" on four lines, five more names on two | `Segmented` can be a words grid (`words`); the picker is one, two columns, so a two-word name is one line (`Chip.tsx`, `PortProduction.tsx`) |
| Trade, City face, a fleet at sea: five building tabs | 320, English | "Production" (72 px) stood over the cells beside it in a 51-px column | a four- or five-column choice grid under 375 px: a column is never narrower than its word, 2 px padding (`tileStyles.ts`) |
| Trade at 1,280, City face: the building tabs in the 272-px left pane | 1,280, English | "Production" (67 px) against "Town" and "Craft" in four 53-px columns | from 1,024 px the tabs are a wrapping line, each cell as wide as its word at least (`command/city/City.tsx`) |
| Trade, the fleet picker | 320 | "Flor do Mar" on two lines, 9 px short beside "In port / Lisbon" | the picker's button gives up 12 px at its right under 375 px (`FleetPicker.tsx`) |
| map, a fleet's sheet: crew bonuses | 320 and 390 | "CREW BONUSES" on two lines with the totals run up against it | the heading is one line; the totals go under it where they do not fit (`CrewBonuses.tsx`) |
| Inn, Supplies | 320, English | "On board" on two lines beside the two tonnages | the row is a `wholeName` row: the tonnages go under the label (`StepQuestion.tsx`) |
| map, a city's sheet, Port: the merchants' rows | 320 | beside her mark, level and state the label had 55 px: a company stood a syllable a line ("Herma / nos / Ocam / po"), "Casa Mendes & Filhos" was broken inside its words, and the level's word ran under the name | the row is a `wholeName` row whose name keeps 9 rem under 375 px: the two figures go under it, at the right; "1 ship" is one piece (`MerchantRow.tsx`) |
| the same rows | Korean | "level" and "1 ship" in English | through the dictionary (`port.level`, `port.shipsOf`) |
| map, a city's sheet: its head | 320 Korean, 390 English | 산루카르데바라메다 stood over "Send fleet"; "Sanlucar de Barrameda" pushed the button 23 px off the tray | the head's name is never narrower than its longest word, and the button goes under it where the two do not fit (`TrayTitle.tsx`, every tray's head) |
| map, a cargo ship's sheet (and a navy ship's, a pirate ship's) | 320 | "Shipment" a syllable a line beside "Sanlucar de Barrameda" | `wholeName` rows: the city goes under its word (`CargoSheet.tsx`, `NavySheet.tsx`, `PirateSheet.tsx`) |
| a merchant's sheet, Trade: the goods table | 320, Korean | 브라질나무 ran into its quantity ("브라질나무13") | the name's column is never narrower than its longest word; under 375 px the columns stand 8 px apart, not 12 (`TradeHistoryPanel.tsx`) |
| map and Trade, Requests | Korean | the good's name in English ("Cardamom", "Kangaroo Skins") and the tray's title "… · request" | the name goes through the goods' name map, the word through the dictionary (`RequestBoard.tsx`, `FulfilTray.tsx`) |

The leftovers the earlier passes listed:

| where | size, language | what | fix |
|---|---|---|---|
| HQ, Port, Yard: hull tiles | 390, English (and 320) | "1,275 tons" and ten more tonnages as "1,275" over "tons" | the tonnage is one piece (`PortYard.tsx`) |
| map, the route bar | 320 | Confirm and Repeat cut a refusal's word ("No water", "Same city", "Supplies short", "Checking") in a 53-px cell; a refused route's sentence was cut with dots | five buttons, each as wide as its words at least, sharing the spare width, 4 px padding; the sentence keeps its words and wraps (`RouteBar.tsx`) |
| Fleets, a fleet's page | all | the empty and locked places, and each ship's Move button, landed a moment after the page and pushed its foot down (694 px, then 746) | the room's answer is kept a minute, so the page draws its places in its first frame (the list's Room card has already asked); the Move button's place is kept while its read is on the way (`houseRoom.ts`, `MoveShip.tsx`) |
| ship block, Skills, a merchant's sheet | Korean | skill names in English | every skill has a Korean name, by its code (`src/lib/i18n/names/skills.ts`, through `properName('skill', …)` in `SkillTile` and the Skills tray's title) |
| map, an armada's fight ring | all | a harbour's reach is 38 px, so a 52-px ring round an armada in port left a sliver to press | the 12 px just inside a wide ring's line open the fight whatever lies under them, except within 22 px of another mark's own centre (`fightRings.ts` `fightRimWins`, `MapScreen.tsx`) |

## Left, and why

| where | what | why left |
|---|---|---|
| yard, "Caracca armata"; goods cards "Black Pepper", "Merino Sheep"; the country picker "Ottoman Empire", "The Netherlands"; the Seas face, Korean, four-word seas | a name on two lines | it turns at a space, whole, in a half-width tile or cell; the names law allows it, and one line would need a wider cell than the grid has |
| HQ, City hall, 320, Korean | "하루" over "+171,446" | a label over its figure, as the cells beside it |
| map, a city's sheet | "… Gaivota heading / here", "… 정박 / 중" | a sentence turning between words |
| requests card | "개당 · 시세 1,066" on two lines | a caption turning between words in a third-width cell |
| map, 320, the fleets list open with six long-named fleets | the list (224 px) stands over the zoom buttons and half of "Regions" | an open drop-down over the controls; it folds on a pick. A narrower list would turn the fleets' names |
| a ship's sheet, fitting tiles | "Boarding Gear", "Storm Canvas" on two lines | a name turning at a space in a square tile |

The walker's own false alarms, checked by hand and not faults: rows passing under a pinned title or a tray's pinned tabs; and a sideways shift of the map it caused itself by scrolling a button into view (the chart's box is wider than the glass by design and does not scroll in play).

## Decided by default (the owner may reverse)

- The top bar drops the clock's word before the clock and the clock before the purse. Nothing on it is ever cut in half.
- A fleet picker with many fleets stands two to a line, not four.
- Under 375 px a set of four or five choices is not equal cells where a word is longer than its share of the glass. On the wide desk the building tabs of the left pane are a wrapping line, not a grid.
- A ship's Move button keeps its place (not drawn) for the moment its read is on the way; where the answer is "no move", the place closes.
- Skill names in Korean are this slice's own wording (110 names, the 55 hull skills written as country and size); the owner may reword any of them in `names/skills.ts`.
- The fight ring's rim rule is inward only: a press just outside the line is still open water, as the geometry spec holds.

## Laws

`tests/lit.screens.spec.ts` (new), English and Korean: the yard's tiles, the route bar with the longest refusal words put in, a fleet page's tile field never growing after its first frame, the HQ's title, five choices at 320 px, the top bar with a six- and an eight-figure purse, the fleet picker with eight fleets (no name on more than two lines), a city sheet's head with the longest city name, a harbour's merchant rows, and every skill having a Korean name. `tests/map.fightRings.spec.ts`: the rim rule. `tests/names.whole.spec.ts`: the route bar is off the list of files that may cut text (it cuts none now).

The walk made 11,036 stops in all. Not held by a law (staging them needs a fleet at sea or a served battle, and the fix is a shared primitive already under law): the crew bonuses heading, the Supplies row, the cargo, navy and pirate sheets' city rows, the merchant's goods table.

Pictures, before and after: `C:\Users\gkwng\dev\lit-screens-shots\` on the build machine (not in the repo).
