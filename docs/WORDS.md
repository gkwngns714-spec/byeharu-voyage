# WORDS — the one vocabulary the game speaks

**Why this file exists.** The owner, 2026-08-22: *"common words — stores? t? kn? what are these"*.
The code answered by spelling "days" and keeping "stores" and "t". The owner, 2026-09-13, on
COMMAND's `54.3 days stores · 9 t free`: *"wtf is this? the wording is too old fashioned. 9t free?
9t free out of what?"* and then *"find similar crappy wordings, and make them new"*. An instruction
said twice means the wrong thing was built (the memory rule of that name), so this file is the
law the client's text is written to, and `docs/UI_DIRECTION.md` §4 defers to it for words.

## The three laws

1. **Plain, modern words.** The player is a person with a phone, not a reader of logbooks. No
   period-nautical: no *she/her* for a ship (a ship is *it*, or its name), no *alongside*, *lies
   at*, *in the roads*, *the quay*, *the shed*, *the house*, *sign on*, *mend*, *lay down*,
   *provision*, *fill the barrels*, *tuns*, *stores*. The test: would the word appear in a modern
   shipping app? If not, it does not appear here.
2. **No number without what it is out of.** A figure that is a SHARE prints its whole beside it:
   `51 / 60 tons`, `12 / 20 crew`, `3 / 6 tries`, never `9 t free`. A figure that is not a share
   (a price, a distance, a count of days) prints its unit spelled: `54 days`, `188 miles`, `4.9
   knots`, `71 d. per ton`. The one abbreviation kept is the currency mark `d.`, because it is the
   currency and appears beside every price.
3. **One word per thing, spelled in `src/lib/format`.** Units are printed by the formatters
   (`formatTons`, `formatKnots`, `formatMiles`, `formatVoyageDays`, `formatOfTotal`,
   `formatUnitPrice`) and by nothing else; a screen never writes a unit string of its own. A
   noun that names a game concept has one spelling, in the table below.

## The vocabulary

| Concept | Say | Never |
|---|---|---|
| food and water aboard | **supplies** (`54 days of supplies`) | stores, provisions, endurance |
| the act of buying them | **Resupply** | provision, fill the barrels |
| cargo space | **cargo** / **cargo space** (`51 / 60 tons`) | hold, tuns, room |
| cargo weight unit | **tons** (`1 ton`, `35 tons`) | t, tuns |
| the player's company | **you** / **your company** | the house, your house |
| creating it | **Start your company** | sign the book, found a house |
| a ship in port | **docked** / **in port** | alongside, lying at, at anchor (at a port) |
| goods on the ship | **on board** (`3 tons on board`) | aboard, stowed |
| a ship at a bare sea point | **anchored** | at anchor (ambiguous with port) |
| the offshore point a port is reached from | **anchorage** | the roads, roadstead |
| a trip | **voyage** | passage |
| distance | **miles** (`188 miles`) | nm, sea miles |
| speed | **knots** (`4.9 knots`) | kn |
| the port's storage building | **warehouse** (tab: **Store**) | shed |
| put cargo in it / take it out | **Store here** / **Load onto ship** | land it, take it aboard |
| the crafting building | **workshop** (tab: **Craft**) | workstation |
| the ship-building building | **shipyard** (tab: **Shipyard**); the repair face is **Repair** | yard, lay down |
| build a ship | **Build ship** | lay her down |
| repair | **Repair** (`Repair to 100%`) | mend |
| hire | **Hire** (`Hire crew`, `Hire officer`) | sign on |
| the inn's daily officers | **Officers today** | tonight's room |
| the market | **market** / **here** | the quay |
| price paid | **Bought at** | paid, basis |
| sale proceeds | **You get** | fetches |
| a price ceiling from the server | **Max** | at most |
| haggle | **Haggle** | bargain |
| port fee | **Port fee** | the port's cut |
| the event log | **History** (tab) | ledger |
| the top-right menu | **Menu** | cabin |
| the reference | **Codex** | compendium |
| loading | **Loading…** | asking the shed what it holds…, seeing who is in tonight… |
| empty | **No cargo** / **No fleets** / **Nothing here** | her hold is empty, nothing that floats |
| a refusal with no reason | **The server refused, without a reason.** | — |

## Where the words are checked

`tests/words.spec.ts` greps `src/features`, `src/app`, `src/components/ui`, `src/domain` and
`src/lib/format` for the NEVER column and fails on a hit in player-facing text. A new banned word
is added there the day the owner names it, not later.
