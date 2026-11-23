# The visual overhaul, 2026-11-23: fewer words, more pictures

The owner, 2026-11-23: *"I want the whole front end — tabs, screens — to be visually appealing: less words, good graphics and all."*
References for the feel: EVE Online's clean dark HUD, RuneScape 3 and Melvor Idle's icon-led skill and item tiles with progress bars
you can feel fill, Uncharted Waters' sea charts and port pictures.

This builds on the design system the game already has; it does not start a second one. The one token source stays `src/index.css`
(`@theme`: the night-sea palette, one gold accent, three inks, the type scale), the primitives stay `src/components/ui/*` (Card,
ListPanel, Tile, Row, SummaryRow, Bar, Nav, Tray, Icon and the one inline-SVG glyph set in `icons.ts`, with a drawn mark for every
good a player meets often in `goodIcons.ts`), and the laws stay `docs/UI_DIRECTION.md` §4-5 and `docs/WORDS.md`. What changes is
how much of each screen is words, and how much is marks, bars and pictures.

It also carries the navigation half of the roadmap's clear-out (`docs/design/roadmap-2026-11-23.md` §4, X1-X8): the lead gave the
tab bar and the page lists to this overhaul, so one hand edits the navigation.

## 1. The audit (local build, lit world, fresh company)

Local build of origin/main 1b62c976 (`vite preview`, headless), the shipped world image with every switch production runs lit (the
`docs/design/playable-2026-11-22.md` §6 set: `raid_companies_enabled`, `yard_order_enabled`, `hold_requests_enabled`,
`houses_board_enabled`, `level_unlocks_enabled`, `world_events_enabled`, `pirate_bounties_enabled`, `first_hour_enabled`,
`pirates_bite`, `regard_enabled`, `levels_bite`, `standing_routes_enabled`, `pirates_joinable`, `land_enabled`, then
`city_treasury_switch(true)`, `influence_switch(true)`, `economy_close_switch(true)`). A fresh company, the welcome card, then every
destination at 390x844 and 1280x800, English and Korean.

Screenshots (local to the PC that took them, not kept in the repo):
`C:\Users\gkwng\AppData\Local\Temp\claude\f5388e2006711d23\20c3c33b-2e64-4a9f-9933-ae93974d7413\scratchpad\visual-audit\`,
named `before-<en|ko>-<390|1280>-<NN>-<route>.png` (and `after-…` for slice 1), with one `.json` per glass holding the counts below.

**Counts** (390 px, English / Korean). *Words* is every word the page has drawn, scrolled or not; *controls* and *marks* are what is in
view on the first glass (presses, and glyphs under 40 px).

| Screen | Words EN / KO | Controls | Marks | What it is today |
|---|---|---|---|---|
| Trade (`/command`) | 190 / 174 | 34 | 29 | The best screen: good cards with their mark, flag, two prices, profit and time. But 34 presses on one glass, a city picker of 8 word-chips, and "Open" beside every chevron. |
| HQ (`/city`) | 45 / 42 | 14 | 14 | Five building tiles with line glyphs over words; the City hall card is a column of label-over-figure pairs. No picture of the city at all. |
| Fleets | 74 / 73 | 9 | 11 | One fleet row, then "Your company" (four figures that repeat the row), then "Room": a sentence ladder ("Next: Seamanship or Command level 0 / 1 or Price 10,000"). |
| Map | 42 / 37 | 12 | 11 | Strong: the chart is the picture. The ship's mark is a small triangle; no port art on a harbour's tray. |
| Office | 152 / 136 | 30 | 18 | Three nested tab rows (City / Invest / Report, then nine building faces, then Buy / Sell / Requests) before a single good. The Market face is a third copy of trading. |
| Land | 61 / 56 | 14 | 7 | A form: label-value rows, a thin grey bar, "Lisbon · 12 h at most". No picture of the site or the party. |
| You | 167 / 162 | 12 | 10 | Cards with word titles and no marks; Reputation is a bare "0" over "Day cap 0 / 600"; the levels are the one icon-led block, under the fold. |
| Stats | 338 / 305 | 17 | 7 | Ten faces in two rows of words; Overview opens on world money (a builder's figure); each holder is a dot, a word, and a 24-px number. |
| History | 57 / 53 | 11 | 8 | A book glyph per line and good money colours; the chart is one green blob. |
| Rank | 105 / 103 | 11 | 7 | A two-column list of names and zeros; "#1 of 846 · tied" and "You lead." for a company with no trade. No medal, flag or bar. |
| Routes | 53 / 52 | 11 | 7 | A list that a new company cannot use (the roadmap folds it, X3). |
| Codex | 2,271 / 2,180 | 22 | 47 | 629 goods; the long tail wears its category glyph, so a screen of grains is ten identical sacks. |
| Profile | 39 / 38 | 11 | 7 | "Not signed in · clearing browser data ends this game" as the first line. Belongs on You (X4). |
| Menu | n/a | 7 rows | 7 | A settings-style list of seven rows, glyph · word · chevron. HQ and Rank wore the same wreath; Map and Routes the same chart. |
| Welcome | 27 / n/a | 1 | 0 | Four sentences in a card over the desk, no picture. |

**What repeats on every screen, worst first**

1. **Labels that are words where a mark would do.** "Supplies 15.0 days", "Cargo 0 / 194 tons", "Reputation 0", "Crew 8 · room 20",
   "Wages 8.00 / day", "On board 0": each is a glyph and a number in every game the owner named. The same glyphs already exist
   (`cask`, `ship`, `crew`, `coin`) and are used in one place each.
2. **A word and a mark for one meaning.** "Open" beside every chevron (Trade, Report); "Docked" beside the anchor; "tied" on every
   rank line.
3. **One glyph, several meanings.** The compass was Trade's tab and the Exploration level; the coin was Office's tab and the Trading
   level; the wreath was HQ, Rank, City hall and the level fallback; the folded chart was Map and Routes.
4. **Progress drawn as a hairline or a sentence.** Bars were 4 px (a rule under the text, not a thing filling); the Room's next step and
   the levels' next title are sentences; Reputation has no bar at all.
5. **Card titles are words only.** A page of cards (You, Fleets, Stats, City hall) reads as a document: nothing to find a card by at a
   glance.
6. **No imagery of places.** Ports are names with a flag; HQ, the harbour tray, the yard and the Land site have no picture. The map is
   the only picture in the game.
7. **Stacked tab rows.** Office (3 levels), Stats (10 faces in 2 rows), Codex (5), Rank (4): rows of words above the content.
8. **Spacing and colour are mostly consistent** (one accent, tone steps, 16/24 rhythm, the look laws hold them). The inconsistencies are
   local: the Trade desk's top block packs tighter than the cards under it; Stats' figures are 24 px where every other card's are 20;
   the KO 390 bar labels sit 1 px lower than EN.
9. **Hierarchy is weak where every line is the same size.** City hall, Land and the Fleets Room are columns of label-over-figure pairs
   of equal weight; nothing says which one number matters.

## 2. The principles

1. **Icon + number over sentences.** A fact a player reads every minute is a glyph and a figure ("[cask] 15 d", "[hold] 0 / 194"). The
   word goes to the glyph's accessible name and, where the player needs it, a long-press or the detail page. A sentence on a screen
   is a defect unless it is the one instruction the screen exists to give.
2. **One meaning, one glyph; one glyph, one meaning.** `icons.ts` is the one glyph set; a destination, a level, a good class and a
   fact each own their glyph and no two share one (slice 1 fixes the bar's).
3. **One accent.** Gold is "yours / you may act"; green-red only gain-loss or cheap-dear; blue is moving. Nothing new is coloured for
   decoration.
4. **The same tile everywhere.** A thing you own or can pick (good, ship, captain, level, building, place) is a `Tile`: mark on a disc
   or plate, name, one figure, one bar. A card has a mark before its title (`Card icon`, `ListPanel icon`).
5. **Every level and goal has a bar or ring you can feel fill.** Bars are 6 px, lit toward the leading edge; a level or a goal that is
   the point of a tile wears a ring around its mark (RuneScape / Melvor). A "next" step is a bar with its target, never a sentence.
6. **Good and ship iconography carries the trade.** Every good wears its own mark or its class mark; every hull its silhouette; every
   port its flag. The long tail gets drawn marks by class family (slice 9).
7. **Port and sea imagery.** HQ, a harbour's tray, the yard and the Land site each get one picture: a drawn SVG skyline or scene in
   the night-sea palette (no bitmaps from outside, no new dependency), from a small set of regional silhouettes.
8. **The layout laws do not move.** No overlap, no cut name, 44-px touch targets, no sideways scroll, one glass where the laws say one
   glass. A change that needs a law weakened is the wrong change.
9. **Every removal is reversible** through the tab table or a face list (roadmap §4), and every word still goes through
   `src/lib/i18n/dict/*` in English and Korean; a word that leaves the screen leaves the dictionary.

## 3. The slices, in order (client only)

Each slice is one PR, on the primitives first so every screen moves at once, then screen by screen. "Before" and "after" are what a
player sees.

**1. Foundation: glyphs, the bar and Menu, bars, card marks (this PR).**
- Before: the bar's HQ and Rank shared a wreath, Map and Routes a chart, Trade the Exploration compass, Office the Trading coin; the lit
  cell was only a colour change; the Menu was a list of seven settings rows; bars were 4-px hairlines; cards were titled by words;
  "Open" stood beside every summary row's chevron.
- After: nine new glyphs (fort HQ, scales Trade, office Office, trophy Rank, route Routes, mountain Land, person You, cog Profile,
  four-tile Menu), no two destinations sharing one, and two card marks (laurel Reputation, two climbing chevrons Levels); the lit cell wears a gold pill under a heavier glyph and a bold word; the Menu is
  a three-across grid of place tiles (glyph on a disc over its word); bars are 6 px with a fill lit toward its end; `Card` and
  `ListPanel` take an `icon` (a gold-washed disc before the title), used on You (Ships, Captains, Reputation, Levels) and Fleets
  (fleets, Your company, Room); cards are lit faintly from above; the word "Open" is gone from every summary row (and `common.open`
  from the dictionary); the Trade desk's Map door names the city it opens on (or "At sea") at every width, so it never
  reads as the bar's own "Map" cell.

**2. The clear-out: navigation (roadmap X2, X4, X5, then X3).**
- Before: phone bar HQ · Trade · Fleets · Map · Land · Office · Menu; Profile, Routes in the Menu; Stats opens on ten faces.
- After: the bar is HQ · Trade · Fleets · Map · Land · Menu. X2: Office's City, Invest and Report become HQ buildings and the Office
  cell is `enabled: false` (the route stays, pointing at HQ). X4: Profile leaves the Menu; You gains an "Account" summary row at its
  foot (language, sign-in) and `/profile` stays a route. X5: Stats shows News, Markets, Cities, Pirates, Me; Overview's world money,
  Navy, Cargo, Ships and Merchants stand under one "More" fold in the face list. X3 (Routes off the Menu) lands with roadmap slice 4,
  whose desk "From here" line replaces it (until then the ranking has no other home). nav.geometry, nav.rails, consistency and
  land.party are updated for the new cell list only; every geometry law stays.
- Built (decided by default, the owner may reverse each): the three doors stand as a second row under HQ's five buildings
  (office, a new coin-stack `invest` and a new page `report` glyph) and open the Office page on that face (`/office?face=`), with the
  HQ cell lit there; the Profile page is worded "Account" (one word for the row and the page) and lights You; "More" is the sixth cell
  of the Stats strip and opens the Overview with the folded faces as a second strip; Stats opens on News (`/stats?face=` names
  another); "Gold in play" (and the funds at sea) stand in the live band only on the faces under More.

**3. Trade desk (with roadmap X1, X8).**
- Before: 34 presses on the first glass; word chips for eight cities; "Supplies 15.0 days / Cargo 0 / 194 tons" as words; a goal card in
  text; events from the far side of the world.
- After: the top block is three glyph-figures ([cask] 15 d, [hold] 0/194 with a bar, the goal as a ring); cities are flag tiles; the
  card's prices read Buy / Sell by tone and arrow, not by word; HQ > Market's basket and Office > City > Market's trade face open
  the desk instead (X1, face list); world events farther than two hours' sail move to News (X8, one distance knob). The TradeCard's
  profit lines and the arrival card stay out of this slice while 0474 rewrites them.
- Built (decided by default, the owner may reverse each): the fleet strip's two figures are glyph-figures, the cask and its days and
  the hold (slice 5's marks) with its share and a bar, the words "Supplies" and "Cargo" kept as the marks' accessible names
  (`FleetStrip.tsx`, both widths). The goal card leads with a 30-px `Ring` around the goal's mark (a ship for the second ship, the
  coronet for a title), filled by the purse against the Order's price, else the materials stored, else the lower track against the
  next title's level; the saving line's thin bar went into the ring, so the card's lines are no longer and its 44 px stand. The city
  picker's eight cells are flag tiles: the flag at 20 px over the name in the caption voice (a free town keeps the flag's room
  empty). The goods card's two prices are led by an arrow in a tone, not a word: Buy an arrow down into the hold (`buyIn`, blue,
  goods moving aboard), Sell an arrow up out of it (`sellOut`, green, coin coming in); the word is each mark's accessible name, and
  in the narrowest card (107 px inside) the figures stand alone as before. X1 is `live/tradeOnDesk.ts` (its one switch,
  `TRADE_ON_DESK`, in `tradeOnDeskKnob.ts`): the HQ Market stands no basket row and its Buy / Sell open the Trade desk on that
  city, good and side for the fleet docked there; Office > City > Market keeps its reading (Supplies, Buy · Sell · Requests, the
  ledger) and its price cells open the desk the same way, with no basket in the slot. The quay's own trade tray, its bargain and
  its basket are not reached while the switch is on (the desk's panel has no bargain; the specs of those trays stand skipped on the
  switch and run again with it off). X8 is `live/eventReach.ts` (`DESK_EVENT_REACH_MS`, two hours): the desk lists a world event
  only when it is at her place or the served sea miles from there (`world.reach`) at her served speed are two hours or less of real
  sailing; Stats > News heads its list with every event, and a press there opens the desk on that harbour.

**4. Map and its trays.**
- Before: your ship is a small triangle; a harbour's tray is rows of words; the minimap and filter are text buttons.
- After: your fleets are hull silhouettes with a gold halo; a harbour's tray opens on its regional skyline (principle 7) with the flag,
  the three best goods as marks with arrows, and one Sail press; filters are glyph chips.
- Built (decided by default, the owner may reverse each): your fleets on the chart keep their class silhouettes and gain a brass
  glow and a brass rim (selected: an ink rim and a dashed ink ring); the Fleets corner and the Port tab lead each fleet of yours with
  her flagship's outline seen from the beam (`FleetHull`, masts by `shipRig`, tier by `hullTierOf`), the selected corner row in a
  brass wash with a brass edge, and the untranslated "yours" tag gone; the harbour tray carries its regional skyline over the tabs
  (`Skyline`, six pictures picked from the served culture by `skylineOf`); the head line's counts are a sail and an anchor with
  their figures and your fleets an anchor (here) or a route (bound here) before their names, the words kept as accessible names;
  the filter is a glyph square (new `layers` and `waves` glyphs) whose choices are glyph chips. The three best goods on the tray
  wait for the Trade desk's slice (0474/0475 own those cards).

**5. Fleets and ships.**
- Before: a fleet row, then a card that repeats it, then the Room ladder in sentences.
- After: each fleet is a tile with its flagship's silhouette, a hold bar, a supplies cask and its state glyph (in port, at sea, laid
  up: `fleet_state_of`); "Your company" folds into the page title's figures; Room is two bars (fleets, ships each) with the next
  step's target on the bar.

**6. Captains (You > Captains, the Inn, the captain sheet).**
- Before: name, role word, a list of trait sentences (some that do nothing).
- After: a portrait plate (role glyph on a nation-tinted disc), the two skills that matter as rings, traits as glyph chips; traits that
  do nothing are hidden by one word list (X7, finishing #800).
- Built (decided by default, the owner may reverse each): a captain is drawn by one file (`src/live/captainLook.tsx`, its rules in
  `captainMarks.ts`) on You, the Inn and the Codex alike: her PLATE (`Portrait`, inline SVG) is her head and shoulders under the hat of
  her role (a soft cap for Trading, a tricorne for Exploration, a bicorne for Combat · Long range, a knotted scarf for Combat · Close
  range), one of three faces by her code, her grade's letter in the corner (gold at S), on a disc in the tint of her HOME TONGUE (her
  first served language, which every face already serves, so no new read; the great powers' seven tongues wear their nation ink).
  Her RINGS (`Ring`) are her levels: the two that matter (her role's track, then her stronger other one) under her name on the You
  roster, all three on her sheet, each the track's level mark in a ring filled toward the next level, the level beside it. Her TRAITS
  are chips, a new glyph per effect (speed, crate, tag, shield, heart, storm, target, cannon, cutlass; supplies keep the cask) and the
  line's figure, lit gold where she uses one and pressed to choose; the trait's name is the chip's accessible name. X7: `traitWorks`
  is the one test, a word list of the card's idle sentences: since 0179 lit crew_bite every fleet effect is read, so the card's
  "Not in use yet." is stale (#800's `in_use` filter hid working traits, e.g. a Pilot's storm damage); only "Works when combat
  arrives." (a ship effect, combat off) still means idle. Such a trait is not drawn on the Inn or on You; the Codex keeps all.
  The sheet's Grade / Job / Role / Where rows became the plate; the Inn's guests are cards of plate, name, job, what the job adds
  (its glyph and per cent, dim where nothing reads it) and the wage; the hire tray opens on the plate and the chips.

**7. HQ and the city.**
- Before: five word-and-line-glyph buildings; City hall a column of equal-weight figures.
- After: the city's skyline across the top (principle 7), buildings as plates with their glyph and one figure (gold, population trend,
  relationship as a mark); Office's faces as buildings (from slice 2); Academy, Workstation and Invest shown from Trading 5 with an
  unlock line (X6, one level gate).
- Built (decided by default, the owner may reverse each): the city's regional skyline (slice 4's `Skyline`, by `skylineOf`) stands
  behind HQ's title across the glass (`Sheet backdrop`, copies side by side and every second mirrored, so a wide glass does not crop it
  to its quay); it takes no room, so every glass law stands where it stood. The five buildings and the three doors are plates: the
  mark on a gold disc, the word, one figure already on the page (no plate asks a read of its own) — the hall the city's gold, the
  market its tax, production your free hold here, the port your fleets here (anchor), the inn their crew (crew); City this city's
  buildings, Invest your shares here; Report has none (its week's profit is a read of its own). Each figure's word is its accessible
  name. From `lg` the buildings and the doors stand on one row (5 : 3), which also puts the plan back on the first glass at 1280 x 800
  (law h; the doors' second row had pushed it 45 px under). The HQ city drawing, its walkers and the hall panel are untouched. X6 is
  `live/levelGate.ts`, the one table (`GATED`, `FROM`): Skills (Academy), Craft (Workstation) and the Office's Invest are held under
  Trading 5, and only while Trading's unlocks are lit (`level_unlocks_enabled`, the goal card's own test); dark, nothing is held. A held
  door on HQ is a dimmed plate whose figure is "Trading 5" (the unlock line), a held building on the City face's Town list a row with
  no door and the same figure, and the Office strip drops the held face. The Office faces: Report's sections and places each draw their
  share of the list as a bar (green in, red out); Invest's work levels are bars, not "Level 2 / 5"; City's door wears HQ's fort.

**8. Rank and Stats.**
- Before: lists of names and zeros; Stats' figures as 24-px words with dots.
- After: the top three on a podium (trophy, flags, bars of profit); your line pinned and lit; "tied" and the counted-ago lines gone
  where the figure says it; Stats' player faces lead with one chart each, holders as a stacked bar with marks.
- Built (decided by default, the owner may reverse each): the three boards (Week, Captains, Countries) share one picture
  (`src/features/rank/Podium.tsx`): the top three on a podium (second · first · third, the trophy over the first, each flag, the whole
  name, the figure, and a step as tall as its figure against the first's; the countries' steps carry no place, since that board serves
  none); your line pinned at the head of the list in a gold edge (your company or your country, whether placed or off the board's
  end; the fame tray opens from it) and lit again in its place; every row the place, the flag picture and the whole name, the figure,
  and a 6-px bar against the first row (the Week's green for a gain, red for a loss). "tied" left the rows and your standing (two houses
  level wear the same place; the tray keeps it), the leaders' country caption became their flag, the companies' count stands under
  your place ("of 846", a separate "Companies" line gone), your fame's lines wear coin, compass and anchor, and the Week no longer says
  "You lead." for a shared first. Stats: the live strip's figures wear coin, ship and scales; News leads with a line of time (the
  list's happenings as dots from the oldest to now, headlines larger; it counts nothing and adds no read); Markets' Up, Down and Most
  traded are ranked bars, each good with its own drawn mark; Me's week shows sold and bought as one stacked bar and the trades as a
  scales line (the "{n} trades" sentence gone). Markets and Cities already led with their two chart cards and kept them; Pirates was
  left as it is (its states bar is the chart). No new read: every figure is the one the face already asked.

**9. You and levels (and the Codex's marks).**
- Before: Reputation a bare number; levels under the fold; the next title a sentence.
- After: a header plate (your house, its flag, title, reputation ring); levels as Melvor-style tiles, each a mark in a ring with level and
  a 6-px bar to the next; the next title is a ring's target; the Codex's long tail gets drawn marks per class family.
- Built (decided by default, the owner may reverse each): You opens on the house's PLATE (`HousePlate`, YouScreen.tsx): the
  company's flag on a disc and its name whole, then two rings, the TITLE (a new `coronet` glyph, filled by the lower of her Trading
  and Exploration levels against the level the next title asks; its name and level beside it, the next title and the two levels
  it asks under them) and REPUTATION (the laurel, its ring today's capped earnings against the Day cap; the balance and "Day cap
  a / b" beside it), and the room line at its foot. The title MOVED from the levels card and Reputation from its own card, so each
  stands once. A level tile is now its mark in a 40-px `Ring` filled to the next level, the level figure, the name, the 6-px bar
  and the experience with the next level's gift. THE LEVEL-UP MOMENT: a tile whose served level is higher than the one it last
  drew this session glows gold once, its mark and figure pop and a chevron rises off the ring (1.4 s, `bv-level-*` in index.css;
  under reduced motion nothing plays); a page load starts with nothing seen, so only a rise plays it. The Codex's long tail: the
  twelve categories that wore another's glyph wear their own family mark (grain sheaf, amphora, clay pipe, apothecary bottle, dyer's
  skein, ring, basket, halberd, musket, framed portrait, books on a shelf, ox head; `CATEGORY_ICON`), so 313 tail goods are told
  apart by family. The Account row stays at the page's foot.

**10. Yard, Land and the welcome.**
- Before: the yard shows four prices in words; the Land site is a form; the welcome is four sentences.
- After: the yard is hull silhouettes with one price and the press she can make; Land shows the site's peak and the party as marks with
  a trip bar; the welcome is a picture (Lisbon's skyline, your ship) with one line and the goal ring.
- Built (decided by default, the owner may reverse each): a hull's tile leads with her picture (`ShipPicture`, slice 5's) and keeps
  its ONE figure, Labour; her sheet opens on her picture (`ShipPicture` hero) and carries one price a road, Total (build her yourself)
  and the Order press, with Labour under Total and the order's fee (Order fee, or #800's First-ship fee) under Wait as small print, not
  rows of their own; #800's rule (the Order is gold while materials are short) stands. Each material is its mark (`goodIcon`; a part
  the workshop's mallet), its need, and a 6-px bar of what is stored here with what is on board washed on, the words ("12 in storage ·
  3 on board") under the bar, the "Materials" / "Parts" prefixes a heading over the lines. Land's Party card opens on a drawn site
  (`LandSite`: the home town, the road, the mountains and the mine's lit mouth, the sea across the road for a far land) with the
  party a gold mark on the road as far along as the trip bar; the Storage leads each good with its mark; a skill's jobs are a field of
  tiles (mark, name, where, one figure, a bar of the skill's level against the job's). The welcome opens on her city's skyline with
  her ship on its water, then one line ("Your trading house · Lisbon, 1507"), the goal as a `Ring` around a ship with the goal card's
  own line ("Second ship · 40,000 / 52,000"; the two cards read one hook, `useSecondShipGoal`), and the first press; "Welcome" went.

## 4. How we will know

- At 390 px the first glass of Trade, Fleets, HQ and You carries at least a third fewer words than the counts above, with no fact lost
  (each moved to a mark with an accessible name or to a detail page).
- No glyph means two things (a check over the tab table, the level marks and the card marks).
- Every level, goal and room limit is drawn as a bar or ring.
- The look and layout specs stay green with no law weakened; every word still in both dictionaries.

## 5. Visual pass 2 (after the ten slices)

A second walk of every screen at 390 x 844 and 1280 x 800 (local build, lit world, fresh company) found the places the slices did not
reach. Fixed here (decided by default, the owner may reverse each):
- **Empty states draw their mark.** `Empty` takes an `icon`: the glyph of what would stand there on a disc over the one line. Used for
  an empty Storage (crate), an empty Land store (crate), nobody else on a Land site (crew), no captains (a new tricorne `captain`),
  no Report place (anchor) and no routes (route). Each was a grey sentence or a bare "0".
- **City hall's five figures lead with a mark** (new `people`, coin, new `banner` for Status, crew, new `pact` for Relationship).
- **Doors wear their face's glyph.** `SummaryRow` takes an `icon`; the HQ Port panel's Build (mallet), Repair (new `wrench`) and
  Gear (new `fitting`), the Inn's Crew and Captains here, and the Report's sections (scales, crew, cask, wrench, shield, invest,
  ship, coin). The face glyphs live on the one face table (`live/cityFaces.ts`).
- **The wide desk's ship block** leads its rows with crew, coin, cask and hold, and its "Press a good." with the scales.
- **Land's Party card** leads Packs, Home in and To collect with hold, clock and crate; its four cards carry card marks.
- **You's ships** lead with their picture (`ShipPicture`, gold for the flagship, whose word moved into the picture's name).
- **Card marks** on Production (Storage, Cargo, Recipes), History (Entries, Money) and Routes (Lanes).

Left for later: the Office City face's nine-word face strip (glyphs would add a line under the phone desk's one-glass law); the Stats
and History face strips (words only); Routes' Overview and Stats > Pirates' Totals (columns of label-figure zeros); the Rank podium
on an all-zero board (three equal steps of "1"); the Account page's header line and sign-in sentence; History's Money card (Net, In,
Out as label rows, one bar for a single day); Production's HQ tile and the build yard sharing the mallet.
