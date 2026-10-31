# NO DUPLICATE INFO — the other tabs (owner, 2026-10-31)

Owner: *"SAME FOR ALL THE OTHER TABS, NO INFO DUPLICATE INFO NEEDED. AND FOR EXAMPLE INN,
HORIZONTAL SPACE IS TOO LARGE. MAKE IT COMPACT SO THAT I DON'T NEED TO SCROLL DOWN. THIS GOES FOR
EVERY PARTS OF THE GAME"*.

The Inn's packing is the city slice's (`#429`/`#430`). This slice is the rest of the game.

## The inventory (measured on the served build, 390×844, English, headless)

Every screen's visible lines were captured and diffed across screens: 11 routes (`city`, `fleets`,
`map`, `stats`, `ledger`, `rank`, `routes`, `compendium`, `you`, `profile`, `command`) plus the five
Stats faces and the four desk faces — **20 screens**. The same fact on two different tabs:

| fact | printed on | home | action |
|---|---|---|---|
| the captains' board (rank + purse) | Stats/Me (row + full page + its own country filter) AND Rank | **Rank** | removed from Stats/Me |
| the fleet's cargo (used/total) | Fleets ("4 / 199 tons") AND the desk's fleet strip AND the desk's "Your cargo" door ("4 / 181") | **Fleets** | the DOOR lost its figure (title + Open); the strip keeps it (judgment below) |
| the fleet's supplies (days) | Fleets ("15.0 days of supplies") AND the desk's fleet strip ("15.0 days") | **Fleets** | strip keeps it (judgment below) |
| hall figures (Population · Gold · Status · Relationship · Employees) | City only — **verified absent** on all 10 other screens | **City** | proved by test |
| World money · At sea · Recent trades | Stats only (its own persistent band, every face) | Stats | none |
| Influence · Investors | the City hall AND the desk's Invest face — but the Invest face COMPOSES the same hall panel (two doors to one screen) | City hall | none: one home, two doors |
| the words Trade/Crew/Repair/Insurance | the ledger's kinds AND the Report's spending categories | — | different facts that share a word, not duplicate readouts |

## Judgment calls (kept, with the reason)

- **The desk's fleet strip keeps supplies and cargo.** The desk is where a voyage is bought, sold
  and sailed; those two figures are the ones you act on *there*. Removing them would break acting
  in place — the one exception the owner's rule allows, recorded here.
- **The map's selected-fleet panel keeps its voyage rows** (supplies, ETA, miles sailed). Those are
  voyage STATE, not the fleet's standing facts, and the map is the only screen that shows them.
- **Rank's own summary row keeps the board-size figure** — that figure's home is Rank.

## Compactness

No page or Sheet scrolls on any screen at 390×844 or 1280×800 — the consistency walk measured
**0 violations** at both sizes on this branch. The two changed screens:

| screen | before | after |
|---|---|---|
| Stats/Me | 2 summary rows (Best sales · Captains), sheet 755/755 | 1 summary row (Best sales), sheet 755/755 |
| desk Trade, cargo door | "Your cargo 4 / 181 Open" | "Your cargo Open" (the door); strip unchanged: "Supplies 15.0 days · Cargo 4 / 180 tons" |

## Proof

`tests/consistency.spec.ts` — new test *"one home per fact: the captains board is Rank's, the desk's
cargo door is a door, the hall's figures stay in the City"*: PASS 41.5 s. It asserts Stats/Me has
no `stats-leaderboard` and no "Captains" summary; Rank's board opens and names you; the cargo door
prints no digit while the strip does; and none of the hall's five figure test ids appears on the ten
non-city screens.

Regression: the consistency walk **0 violations** at 390 and 1280 (45.6 s / 45.5 s); `stats.tab`
(3/3), `command.sellCargo` (2/2) and `trade.map` (2/2) green. `tsc -b`, `eslint .`, `npm run build`
clean.
