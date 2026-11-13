# Small screens: the 320-px leftovers, and Trade on a desktop (2026-11-13)

Owner row 318 (2026-11-12, on a phone): *"word box overlapping, long words and sentences making new messy lines... fix all. especially on phone."* PRs #606 and #607 fixed most of it. This slice finishes what they left at 320 px, and the queue item "Trade on desktop: near-empty side panes, uneven card heights". Client only: no migration, no knob, no new word.

## What was there (measured before, local world, English and Korean)

Every screen and every tab was walked at 320 × 640 with a reader that marks any word standing on two lines.

| where, at 320 px | before |
|---|---|
| Codex, Ships: "Spiegelretourschip" | 101 px for the name (115 in Korean) beside the hold and the chevron: turned inside the word |
| Stats, Cities, all cities: 산타크루스데테네리페 | 126 px for the name: turned inside the word |
| Stats, a city's page, its goods | the kind and 156 px of figures left the name 21 to 44 px: "Balsam of Peru", "Jesuit's Bark", "Zacatecas Silver", 가다랑어 turned inside their words |
| HQ Market, the buy tray | the send button had 151 px beside "Add": "Buy 10 units ·" / "5,078" on two lines |
| a goods card (Trade, HQ Market) | "On board 0" stood beside the name in one card and on a second line in the next |

Trade at 1,280 × 800 and 1,440 × 900:

- the right pane (350 px wide, the desk's height) held one line, "Press a good.", until a good was pressed;
- a row of cards whose heads all fit one line was 20 px shorter than a row with one head on two lines, so the rows of one board had two heights.

## What changed

1. **A row whose label is a name** (`src/components/ui/Row.tsx`, `wholeName`). On a glass under 375 px the row is a wrapping line: the name is never narrower than its longest word and turns only at a space, and where the figure does not fit beside it the figure stands on the next line, at the right. From 375 px the row is the grid it was. Used by the Codex's ships, Stats' city list and a city page's goods.
2. **A city page's goods** (`src/features/stats/CityDetail.tsx`): the kind goes under the name where the two do not fit; under 375 px the figures give 32 px back.
3. **The trade tray's two buttons** (`src/components/ui/TradeTray.tsx`): a wrapping line. Side by side wherever the send button's words fit one line (it takes the spare width, as before); where they do not, each button has a line of its own.
4. **The goods card's head** (`src/live/TradeCard.tsx`): always two lines. The name has the first to itself; the class marks and "On board N" stand on the second, the count at the right. Every row of cards is one height.
5. **The wide desk's right pane** (`src/features/command/buysell/Trade.tsx`): with no good pressed it carries the ship block (owner row 233: cargo, crew, wages, supplies, food and water, the buying skills), which stood only behind the Orders door. A good pressed, the trade panel stands there as before. The block is not drawn while a page is open, so a screen never holds two.

## Decided by default (the owner may reverse)

- "On board 0" is on the card's second line in every card, not on the first: a 123-px card (the HQ Market at 320 px) has no room for a name, the marks and the count on one line, so one line could not hold at every width.
- The idle right pane carries the ship block and not her cargo's best sales or the small map: the ship block asks nothing new of the server (the cargo list asks `world.good_board` once per good aboard), and a second chart on the desk was too large a change for this slice.
- The left pane was left as the trade-layout slice made it (the picker and four doors, 391 of 626 px at 1,280).

## Measured after

The same walk at 320 px, English and Korean: no word on two lines in the Codex's ships, Stats' cities or a city page's goods; the buy button is one line. At 390 px none of the five screens changed. `tests/small.screens.spec.ts` holds all of it, with the world's twelve longest goods names put into a city page's rows.

## Still there

- Ledger at 320 px in Korean: the sentence "Casa de Aveiro 설립(리스본)." turns inside "설립(리스본)." (a sentence, not a name; Korean lines turn between any two letters unless told otherwise).
- With an empty hold the ship block's cargo line reads "No cargo."; the top bar's Cargo figure says the same total.
