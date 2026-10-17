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
   knots`, `71 🪙 each`. Money carries no letter at all: the currency mark is the COIN, `🪙`,
   spelled once as `COIN` in `src/lib/format/numbers.ts` (owner, 2026-09-18: *"the currency is
   ... i don't like it. d. lets change it, to a coin"*) — `8,180 🪙`, `+600 🪙`, `7 🪙 each`.
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
| the port's storage building | **storage** (tab: **Storage**; `In storage`) — ONE word for the building, the tab and the act (owner row 87, 2026-09-13: *"there is warehourse and there is store. unify."*) | warehouse, shed, store |
| put cargo in it / take it out | **Put in storage** / **Take on board** (`Put 20 units in storage`) | Store here, Load onto ship, land it, take it aboard |
| the crafting building | **workshop** (tab: **Craft**) | workstation |
| the ship-building building | **build yard** (tab: **Build**; `This port can build up to level 3`) | shipyard, yard, lay down |
| the repairing building | the face is **Repair** (owner row 86, 2026-09-13: *"wtf is shipyard … use easy words"*) | shipyard |
| how badly a ship is hurt | **Damage** (`13% damaged`, the worst ship) | hull (worst ship), hull % |
| build a ship | **Build ship** | lay her down |
| repair | **Repair** (`Repair to 100%`) | mend |
| a fleet whose ships are at 0 and cannot sail (served status UNABLE_TO_SAIL; 0152) | **wrecked** (`Gaivota cannot sail: its ships are wrecked.`) | unable to sail, sunk |
| moving a wrecked fleet to the nearest port that repairs ships (0152) | **Tow** (button `Tow · 146 🪙`; the server's sentence `A tow takes it 49 miles to Lisbon, the nearest port that repairs ships.`; History `Gaivota was towed 49 miles to Lisbon.`) | salvage, haul, rescue |
| hire | **Hire** (`Hire crew`, `Hire Ana for 1,100 🪙`) | sign on |
| the captains in an inn this quarter hour | **Captains here** (`New faces in 12 min`) | tonight's room, officers today |
| a hired person (0156, docs/SKILLS_AND_CAPTAINS.md D8) | **captain** (`Captains here`, the Codex face **Captains**) — the wire still says `officer` (`public.officers`, `world.officers`) until K9 | mate, officer (in new text) |
| her grade (0156) | **S** · **A** · **B** · **C** — the server's letter, first on her tile (`S · Navigator`) and a **Grade** row in her card; Codex filter **Grade** | rank (that is RANK's word), tier, star |
| what she does (0156) | her **job**, by its word — **Navigator**, **Gem trader**, **Boarder** — and its focus **Exploration** · **Trading** · **Combat** (Codex filter **Role**, then **Job**) | specialty, class, profession |
| what a captain can do (0156) | **traits**, each named by its job word with the server's line (`Navigator · +7.5% speed`, `Gem trader · +4.5% better prices on gems`) | skills (the Academy's word), effects, perks |
| a trait that does not work yet (0156) | the server's sentence: *Not in use yet.* · *Works when combat arrives.* | locked, disabled, coming soon |
| the languages she speaks (0156) | the server's sentence **Speaks Portuguese, Spanish** | LV, fluency |
| the market | **market** / **here** | the quay |
| price paid | **Bought at** | paid, basis |
| sale proceeds | **You get** | fetches |
| a price ceiling from the server | **Max** | at most |
| ask for a better price | **Bargain** (row: `Bargain · 2 / 3 tries left · 45%`; button **Bargain** / **Try again**; `Bargain saved`) — owner row 100, 2026-09-18: *"haggle is a weird word. bargain? … more user friendly"* | haggle, haggling |
| money | **🪙** (`8,180 🪙`, `7 🪙 each`, `+600 🪙`) — the `COIN` mark, never a letter (owner row 102, 2026-09-18) | d., ducats as a unit mark |
| port fee | **Port fee** | the port's cut |
| the event log | **History** (tab) | ledger |
| the top-right menu | **Menu** | cabin |
| the reference | **Codex** | compendium |
| loading | **Loading…** | asking the shed what it holds…, seeing who is in tonight… |
| empty | **No cargo** / **No fleets** / **Nothing here** | her hold is empty, nothing that floats |
| a refusal with no reason | **The server refused, without a reason.** | — |
| a port's posted ask for goods (the reference's 의뢰) | **request** (tab: **Requests**; `This port is asking for nothing today.`) — added 2026-09-14 with slice 4 of `docs/QUAY_LEDGER.md` (migration 0087); the wire says `contract` (`trade_contracts`, `world.contracts`) and the player never reads it | contract, commission, order (that is a queued verb) |
| delivering on one | **Fulfil** (`Fulfil · 1,420 🪙`; the receipt's title `Fulfilled · 14:32`; History: `… delivered 20 pepper on Lisbon's request — 200 🪙 premium.`) | complete, deliver on, honour |
| what a request pays over the market | **premium** (`+12% over the market`; a receipt row `Premium +200 🪙`) | bonus, bounty |
| a loop of ports a fleet sails and trades by itself (0092, owner row 106) | **Route** (`Set up route`, `Route · Lisbon ⇄ Funchal`) — the wire says `standing_route` (`world.standing_routes`) and the player never reads it | trade route, circuit, template, standing route |
| one full turn of it | **Lap** (`Lap 12 · +1,240 🪙`) | circuit, round, cycle |
| a route not running by the player's choice | **Paused** / **Resume** | suspended, idle |
| a route halted by a refusal | **Stopped** + the refusal's own sentence | failed, halted, error |
| a route whose fleet cannot move on by itself (unable to sail, adrift, anchored; 0093) | **Blocked** (`… cannot sail on by itself.`) | stuck, disabled |
| pacing | `Next lap 14:32` | cooldown, fatigue |
| money kept back (slice 2) | **Keep at least** `5,000 🪙` | reserve, floor |
| "only sell at a profit" (slice 2) | **Only sell above cost** | at profit, basis |
| a route stop's two groups (owner, 2026-09-30: *"sell all buy all is ... in one line and not distinguished"*) | **Sell** above **Buy**, each word once in the stop's left column | Sell all · Buy … in one line |
| a price floor the player sets on a sale | **Min** (`Min 14 🪙 each`) — the mirror of **Max** | at least, >= |
| sell every good on board | **Everything on board** (amount `All`) | Sell all, ALL |
| buy as many as the cargo holds | **All that fit** | ALL, max qty |
| no price limit on a line | **Any price** | no cap, market |
| resupply at a route stop (every stop, when below the keep level) | **Resupply if low** · queue row **Resupply to 5 days** | PROVISION DAYS 5 |
| a trading company the world keeps (0096-0099, owner rows 109-111, `docs/NPC_TRADERS.md` §8.6) | **merchant** / **merchant company** (`Merchants in port`) — the wire says `npc` (`players.is_npc`, `world.sea_traffic`) and the player never reads it | NPC, bot, AI trader, house |
| its fleet on the map | the fleet's own name, with the company beside it (`Carreira da Índia · Casa da Índia`) | NPC ship |
| what it makes | **≈ 37,200 🪙 a day** · **A lap ≈ 1,240 🪙** · **So far today** before a whole day of laps · **Last laps** `+1,240 🪙 · −18 🪙 · …` | earnings/day, per game-day, income |
| its money | **Fortune** | purse, treasury |
| a merchant put back on its feet | **refounded** (`refounded twice, last 09:40`) | bailed out, reset |
| a merchant that cannot sail on | **laid up** | stranded, dead |
| the company's levels (the Academy and the merchant sheet) | **Skills** — the Academy face is the Skills screen (0131): groups of skill tiles under **Training** | Captain (for a set of bars) |
| paying once to start a skill, where it is taught (0131) | **Enrol** (`Enrol · 1,000 🪙`; History: `Enrolled in Gunnery at Lisbon.`) | sign up, register, buy |
| the skill levels waiting to train (0131) | **Training** (section) · `Train level 3` · `Remove` · `All done · 3 / 10 levels` · *Trains while you are away.* | skill queue, cooldown |
| where a fitting goes on a ship (0132) | the rack's word: **High** · **Mid** · **Low** · **Refit** · **Flourish** (`Mid 2 / 2`) — served by the server (`gear_racks.word`) | slot kinds as places (rig, ground tackle, steering) |
| what fittings cost a ship (0132) | **Deck** and **Hands**, each out of its whole (`Deck 12 / 12`, `Hands 16 / 16`) | CPU, powergrid, fitting points |
| what a company's skills add to a ship (0133) | **Skill bonuses** (ship panel section), one line per source: `Portuguese Medium Hulls III` · `+12% sighting` — both words the server's (`world.skill_bonuses`); a stat is named as on the panel (`cargo space`, `hull`, `Deck`, `Hands for High fittings`, `officer bonuses`) | per level of, trait, buff |
| a skill a ship or fitting asks for (0133) | **needs** + the skill and its level in Roman numerals, one sentence from the server: `Nau / Carrack needs Portuguese Medium Hulls IV`, `Suit of Sails needs Rigging II` | requires, prerequisite (that word is the Skills screen's, skill to skill), Lv 4 |
| a need that cannot be met while skills are switched off (0135) | the server's needs sentence plus **— ship skills are not in use yet** (`Fluit needs Dutch Light Hulls III and Dutch Medium Hulls I — ship skills are not in use yet`) | locked, unavailable, coming soon |
| a ship's place in the grid (0135, Codex filters and tray) | **Country** · **Size** (**Small** · **Light** · **Medium** · **Heavy** · **Capital** · **Flagship**) · **Role** (**Trade** · **Combat** · **Explorer** · **Support**) · **Tech** (**T1** · **T2** · **Famous**); each filter row starts with **All** | class (for size), tier, hauler, warship, frigate / cruiser (EVE words) |
| the build yard's second group (0135) | **Built only in other countries** — hulls this port's country cannot build, each with the server's own reason | foreign ships, unavailable |
| ship and fitting names and notes (0135, `scripts/build-ships.mjs`, `scripts/build-gear.mjs`) | the historical name as the player reads it (`Fluit`, `Galeón`, `Panokseon`; `Hemp Canvas`, `Brass Guns`) and one plain sentence, no *she/her* (`A light, fast Dutch boat for scouting and carrying news, with a tiny crew.`) | she, her, lay down |
| the person in charge of a fleet | **captain** = the player, for their own fleets; a merchant fleet's named **Master** (flavour only) | — |
| the country a city belongs to today (0143, docs/INFLUENCE.md) | its flag and name, **Home city** or **Contested** (`⚓ Portugal · Home city`, `⚔ Castile-Spain · Contested`) | territory, core, alliance port, free port, owner |
| a city held by no country (0143) | **No country** | free port, neutral, stateless |
| the country a company sails for (0143) | **Country** (`Sail for England`, `Your company now sails for England`); a merchant's company shows its flag | nation (on screen), faction, allegiance |
| a country's weight in a city (0144) | **Influence** (`Influence · Portugal 54%`, `Your influence 1,500`) | share (that word is 0123's), control, sway |
| a gift of coin to a city (0144) | **Donate** (`Donate 5,000 🪙`, `Gave 5,000 🪙 to Havana.`, `5,000 🪙 / 20,000 🪙 given today`) | patronage, aid, tribute |
| the top giver of the country that holds a city (0147) | **Mayor** (`Mayor · Casa Lopes`, `Your tax here 7.5% (half: your country holds this city)`) | governor |
| a city changing country at the daily count (0146) | **now flies the flag of …**; the count is **Next count 09:47** | flipped, captured, occupied; evaluation, tick |

## Where the words are checked

`tests/words.spec.ts` greps `src/features`, `src/app`, `src/components/ui`, `src/domain` and
`src/lib/format` for the NEVER column and fails on a hit in player-facing text. A new banned word
is added there the day the owner names it, not later.
