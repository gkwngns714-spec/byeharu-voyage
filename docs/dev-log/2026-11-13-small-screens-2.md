# Small screens 2: Korean lines break between words; Trade fits 1,280; the walk's findings (2026-11-13)

Owner row 318 (2026-11-12, on a phone): *"word box overlapping, long words and sentences making new messy lines... fix all. especially on phone."* This slice is stacked on `2026-11-13-small-screens.md` (PR #619) and does what that one left and what a second reader reported. Client only: no migration, no knob, no new word.

## What was there (measured before, local world)

| where | before |
|---|---|
| History at 320 px, Korean | "Casa de Aveiro 설립(리스본)." stood as "설립" / "(리스본)." |
| HQ at 320 px, scrolled 1 to 60 px (also on main) | the large title "리스본 수도" stood over the building tiles |
| Trade at 1,280 × 800 | centre pane: 934 px of cards in 626 px (ten cards, two to a line). Right pane, idle: 892 px in 626 px |
| Trade at 1,440 × 900 | centre pane: 768 px in 722 px (three to a line). Right pane, idle: 892 px in 722 px |
| Trade's idle right pane | the hold bar "4 / 180 tons" a second time (the top bar has it) and "No cargo." |

## What changed

1. **A Korean word keeps its bracket** (`src/lib/i18n/translate.ts`). The app already had the base rule (`html:lang(ko) body { word-break: keep-all }`, `src/index.css`): Korean lines turn between words. That rule joins letter to letter only, so a browser still turned the line before a "(" written straight after a Hangul letter, as Korean writes it. Every Korean sentence the dictionary makes now carries a word joiner (U+2060: no width, no glyph) between a letter and the bracket that follows it, put in once, after the values are filled in. English is not touched. No dictionary entry and no screen carries the character.
2. **A page's title holds its place only once it is a bar** (`src/components/ui/Sheet.tsx`). The header was `sticky` at rest too, with no ground of its own, so until the pin (the header's own height) the page's first content slid under the large title. At rest the title now goes up with the page; pinned, it is the opaque bar it was. The pin and its threshold are unchanged. This is every page and every column sheet, not the HQ alone.
3. **Trade's centre pane holds four cards to a line from 1,280 to 1,600 px** (`DeskFrame.tsx`, `TradeBoard.tsx`, `TradeCard.tsx`). From 1,280 px the middle pane keeps 34 rem (it had 432 px at 1,280: the sides took their 22-rem caps first). The left pane gives the room (272 px at 1,280; 352 from 1,440 as before); the right keeps 20 rem for the trade panel. The cards stand four to a line, three lines for ten cards. A card there is about 120 px, and a column is never narrower than its card's words, so the one Korean city name longer than the card (산타크루스데테네리페) widens its own column instead of standing out of its card.
4. **The left pane at 272 px** (`TileGrid.tsx`, `command/city/City.tsx`). On the wide desk a long city name takes two columns of the picker even where that costs a line ("Sanlucar de Barrameda" stood on three lines in one column). The City face's heading is a wrapping line: where the name and "City view" do not fit, the button stands on the next line ("Machilipatnam" stood over it).
5. **The ship block in the idle right pane** (`ShipInfo.tsx`, `aside`). No hold bar and no "No cargo." line there (goods aboard are still listed); the skill tiles stand two to a line, each never narrower than its name's longest word. Under the Orders door the block is as it was.
6. **The hidden tail of a goods card** (`TradeCard.tsx`): the row gap of the part that wraps out of sight is 8 px, not 16, so in a 120-px card nothing stands under the card's foot.

From the walk (below):

7. **The craft tray** (`src/live/PortWorkstation.tsx`). "Gives" and "Uses" carried their sentence as the row's figure, which never wraps: at 320 px "Weather-holding, and a faster turnaround" ran 98 px off the glass and "Gives" stood one letter a line. The sentence now stands under its word and wraps between words.
8. **The trade panel's other sale** (`TradePanel.tsx`): under 375 px "Far" stood one letter a line beside the city, the profit and the time. The row is a wrapping line there (`wholeName`), the figure under its word.
9. **The route bar** (`src/features/map/RouteBar.tsx`): "Confirm" was clipped by 11 px at 320 and 4 px at 390, "Repeat" by 7 px at 320. The two buttons have no side padding now.
10. **A ship's figures** (`src/live/ShipPanel.tsx`): a figure ("0 / 184") and a roll's bracket ("(+12 %)") each stay on one line.

## Measured after

- History at 320 px, Korean: "설립(리스본)." is on one line.
- HQ at 320 px, scrolled 20, 40 and 60 px: the title is over no tile.
- Trade, English and Korean, empty hold, no good pressed: at 1,280 × 800 both panes are 626 px of content in 626 px; at 1,440 × 900, 722 in 722. Nothing scrolls.
- `tests/small.screens.spec.ts` holds all three (laws 5, 6, 7).

## The walk

A script (kept out of the repo; it is a measuring tool, not a law) opened every screen and pressed every tab, row and door it found, three presses deep, at 320 × 640 and 390 × 844, in English and Korean: about 900 stops. At each stop, at the top, 40 px down, the middle and the foot of every scrolling box, it flagged: text over other text or over a control, a word on two lines, text clipped or off the glass, a label of 14 letters or fewer on two lines. It reached Trade and its faces and trays, the HQ and its buildings (Market, Production, Port with its Yard, Inn), Fleets, the Map and its trays, Stats and its tabs, History, Rank, Routes, the Codex's faces, You and Profile.

It found items 7 to 10 above, and saw items 1 and 2 before their fix and not after. What it still flags, and why each is left:

| where | what | why left |
|---|---|---|
| HQ, Port, Yard, the other yards' hulls, 390 px, English | "1,275 tons" and "Caracca armata" on two lines | `src/live/PortYard.tsx` belongs to another open PR: reported, not touched |
| HQ, city hall, 320 px, Korean | "하루" over "+171,446" | a label over its figure in a half-width cell; it reads as the cells beside it do |
| goods cards and rows | "Black Pepper", "Woollen Cloth", "Duodo Bow Guns" on two lines | a name turning at a space, whole: the names law allows it |
| Codex, Nations, 320 px | "Denmark-Norway" on two lines | it turns after its own hyphen |
| Stats, Markets, 320 px, Korean | "거래된 교역품, 24시간" on two lines | a caption turning between words |
| Map, a ship's tray, 320 px | figures "cut at the foot" | the tray scrolls; they are under its edge, not cut |

## Decided by default (the owner may reverse)

- On the wide desk at 1,280 to 1,600 px a goods card is about 120 px, as on a phone: the day line (the small chart line) does not fit beside the profit and gives way, and so does the time to the sale where the profit has four figures or more. The card's title still says them, and the trade panel shows them. The other choice was a centre pane that scrolls.
- The left pane is 272 px at 1,280 (it was 352). Its picker and doors keep every name whole at that width.
- The word joiner is put in by the translator, not written into dictionary entries, so no one has to remember it.
- The route bar's Confirm and Repeat can also carry a refusal's word ("No water"); a longer one is still clipped at 320 px, as before.

## Still there

- The Yard's two-line tonnage (above), for the PR that owns `PortYard.tsx`.
- Skill names in the ship block are printed in English in Korean (the served names): not a layout fault, not touched.
