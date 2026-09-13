# byeharu-voyage — UI audit and design direction

Audited 2026-09-09 against the working tree at `C:\Users\디폴리스\byeharu-voyage` (main, 0080 chain).
Every claim below was checked in one of two ways: the source file and line it cites, or a
screenshot of the running build at 390×844 in local mode (served with `vite --port 4199`, world
booted in 33 s, Playwright pass over every tab and face — 63 captures, zero page errors).

The owner's verdict was *"so many unnecessary info, old fashioned component structure."*
Made precise, it is this:

* **Unnecessary info.** 81 ⓘ explain-dots, 93 lines of 11-px fine print, 31 section labels, 21
  status badges, 57 hover tooltips and 33 bordered cards across nine screens. On COMMAND the
  first price a player can tap is ~1,900 px below the top of the page (screenshot
  `02-command-buy-3`); on PORT it is ~1,300 px down; the Codex goods face is 39,365 px tall.
  Most of what fills that space is a sentence *about* a figure, not the figure.
* **Old-fashioned structure.** Every screen is the same web-admin document: eyebrow → serif
  title → ⓘ → stack of bordered cards with header bars → uppercase mono section labels →
  `dl` rows → footer note. Data tables with sticky columns and "swipe for the rest" hints; a
  design system that is mostly Tailwind class-string builders; screens of 750–900 lines that
  pass 8–14 props down a chain of local sub-components. The 2026-08-20 "material" doctrine
  (cut corners, brass gradients, brown header bars, serif titles, letter-spaced mono captions)
  is a 2008 browser-game skin laid over that document. That skin is what reads as old.

Part 1 is the audit. Part 2 is the direction that fixes both halves.

---

# PART 1 — THE REALITY

## 1. Screen inventory

The shell wraps every screen (`src/app/AppShell.tsx:102-136`):

| element | what it shows | where |
|---|---|---|
| TopBar | wordmark `BYEHARU VOYAGE` (a link to Profile), a "live read" dot, purse `◎ 8,000 D.` | `src/app/TopBar.tsx:28-70` |
| RebuildNotice | a warning card (2–3 paragraphs, 2 ⓘ, 1–2 buttons) when the local world was rebuilt | `src/app/RebuildNotice.tsx:44-134` |
| NavBar | 6 cells: COMMAND · FLEETS · PORT · MARKET · MAP · CABIN (▲). Cabin reveals LEDGER · RANK · CODEX · PROFILE in a panel above the bar. *(Audit as of 2026-08; five cells since 2026-09-11 — MARKET folded into PORT, owner row 76, `docs/QUAY_LEDGER.md`.)* | `src/app/NavBar.tsx:109-183`, `src/app/navTabs.ts` (`ALL_TABS`) |

Each screen, top to bottom, exactly as it renders on the phone.

### COMMAND (`src/features/command/CommandScreen.tsx:337-592`) — content height 1,418 px idle, 3,322 px on BUY
1. Header: eyebrow `ORDERS`, serif title `Command` + ⓘ, right side a wall clock `10:39:02` and `prices move in 5:57` (`:343-361`).
2. Card "COMMANDING" (accent border): fleet chip(s) `Gaivota / Lisbon` (`:373-408`), then three hero figures `PROVISION ⓘ 15.0 days · SPEED 4.9 kn · CARGO ⓘ 4 / 60 t · 7% full` (`:432-468`).
3. Card "MAKE / An order ⓘ" with badge `12 VERBS` (`:475-481`); inside: an "ORDER ⓘ" box printing the parser line `> nothing yet` / `> SAIL Gaivota` (`:483-494`); buttons `Issue this order` (disabled brass) + `Discard this order` (`:497-515`); the check line `Nothing to check yet ⓘ` (`:518-527`); then the composer (`OrderComposer.tsx:278-531`):
   - `VERB` label + a 2-column grid of **12** verb cards, each icon + word + a two-line help sentence (`OrderComposer.tsx:282-328`; screenshot `01-command-1/2`).
   - once a verb is chosen, **on the phone the rail renders first** (`splitRailClass` is `md:order-last`, `screenLayout.ts:59-63`; `OrderComposer.tsx:336-397`): for BUY/HIRE/REPAIR/PROVISION that is `FleetRail` — HOLD hero + gauge + "Water and food take the same tuns as cargo." / THIS ORDER / PRICE MOVEMENT ⓘ with spread ⓘ, purser ⓘ, tax ⓘ, big orders ⓘ (`FleetRail.tsx:141-323`); for HIRE a 7-row CREW block (`:342-429`); for SAIL a `CHART ⓘ` + 3:2 chart with +/−/⌖ (`OrderComposer.tsx:361-383`).
   - `NEEDS ⓘ` label, then one bordered box per argument (`WHERE TO`, `WHICH GOOD`, `HOW MANY CREW`…), each with a filter field, a count line (`10 goods traded here, by name`), and the tiles (`OrderComposer.tsx:401-523`, `tradePickers.tsx:141-233`, `ArgPickers.tsx:110-176`).
   - a good tile: icon, name, rarity mark, category word, a BUY cell `78 d./t`, a SELL cell `72 d./t · none aboard`, `RANGE 62–94`, `STOCK` meter (`tradePickers.tsx:336-373`). Tapping a cell unfolds under the row: `CAPACITY 40 t at most / stopped by the hold / all of it costs 3,120 d.`, `HOW MUCH` (max chip, −/+, slider, "up to 40 t — the hold stops you there"), `on the quay 120 of 400 t` (`:253-318, 425-517`).
   - HaggleBlock after a good is chosen: `STRIKE A BARGAIN ⓘ · 3 of 3 tries left today · your odds ▬▬ 45.0% · [Haggle over Aniseed]` (`HaggleBlock.tsx:104-186`).
4. Card "STANDING / Her queue ⓘ" + `as of 10:39`: `Gaivota [DOCKED] 0/12 queued`, sentence `Gaivota is alongside with nothing to do. A docked fleet earns nothing.`, disabled button `Clear Gaivota's queue` (`CommandScreen.tsx:554-588`, `OrderQueue.tsx:67-156`).

### FLEETS (`src/features/fleets/FleetsScreen.tsx:137-291`) — 964 px
1. Header `ASSETS / Fleets ⓘ`, right `1/2 fleets · 1/8 ships` (`:139-150`).
2. Card "ROSTER / All fleets ⓘ / Tap a fleet to command it." → per fleet a bordered block: name, `DOCKED` badge, `1 ship`, then `where / due / provision / hold [gauge] 4 t/60 t / hull [gauge] 100%` (`:170-227`); on ≥640 px the same data again as a 7-column table (`:229-264`).
3. Card "Standing orders ⓘ 0/6": `Keep a fleet at so many days of stores.` / `The book is empty. Not an error — a state.` / `[New]` (`:326-363`).
4. Per fleet a collapsible card: name, `DOCKED`, `flagship: Gaivota (Barca)`, tabs `SHIPS 1 · CARGO · GALLEY`; SHIPS = `SHIPS ⓘ` + an 8-column table (Ship Class Hull Crew Speed Hold Load Free) that clips at CREW with `Swipe the table for the rest.`, then `GAIVOTA — FITTED / Nothing mounted. She sails as the shipwright rated her. / rig 0/1 · weapon 0/1 · ground-tackle 0/1 · 3 cabin(s)` (`:512-590`; screenshot `10-fleets-2`). CARGO = 3-col table + `stowed` row (`:593-651`). GALLEY = a mono `dl` of water/food/provision/keep/crew/cargo ⓘ/a day + preset chips (`:653-724`).
5. Footer `Read 1s ago · local ⓘ` (`:280-289`).

### PORT (`src/features/port/PortScreen.tsx:256-401`) — 1,842 px on Market face
1. Header `HARBOUR / Port · Lisbon ⓘ`, subtitle `Portugal · latin culture · North Atlantic Ocean`, badge `DRAFT 5` (`:258-266`).
2. Fine print `The roads lie 23.3 nm off the quay. Ships anchor there; a pilot takes them in.` (`:270`, `domain/passage`).
3. Warning notice if the acting fleet is elsewhere, with ⓘ and a button (`:273-291`).
4. `The quay is quiet — nothing is on. ⓘ` (`PortFair.tsx:92-101`) or an accent card with a hero % when a fair runs.
5. Card with header bar `The market ⓘ`; a tab strip of **seven** faces that wraps to two rows (`MARKET CITY WAREHOUSE / WORKSTATION INN YARD ACADEMY`, `:308-319`; screenshot `20-port-1`); then:
   - Market: `BUY | SELL` tabs, filter field, `10 goods traded here, by name`, the same good tiles as COMMAND, and when a quantity is picked the line `> BUY Gaivota aniseed 20` + `Issue this order` (`PortTrade.tsx:132-187`). First price at ~1,300 px.
   - City: `How grown, of 20 — trade 20 · crafts 18 · garrison 11 ⓘ`, `Market tax 3.0% ⓘ`, `Spread 2.0% ⓘ`, then `WHAT THIS CITY KEEPS` — every building with a sentence and `· tier N` (`:333-378`; screenshot `21-port-city`).
   - Warehouse: `ROOM` meter + a 3-line sentence, `ASHORE IN THIS CITY` rows with `Take aboard`, `ABOARD` rows with `Land it here` (`PortWarehouse.tsx:59-131`).
   - Workstation: intro sentence, per item `Buys / Spends / Made of` rows and a button or a reason (`PortWorkstation.tsx:77-146`) — 3,279 px.
   - Inn: a 3-line paragraph, then per guest `name · 40 d. a voyage · blurb · Rates as · Out of · [Sign X]` (`PortInn.tsx:72-127`).
   - Yard: intro sentence, per hull `She is / Timber / Fittings` + reason or `Build a X` (`PortYard.tsx:78-156`).
   - Academy: `X's captain sits the course.` + skill cards with gauge, blurb, `+N% per level`, button (`PortFaces.tsx:179-233`).

### MARKET (`src/features/market/MarketScreen.tsx:255-423`) — 1,261 px; 5,566 px with the port picker open
*(Audit history. The tab and `src/features/market/` were deleted on 2026-09-11 — folded into PORT's Trade face with its port field, owner row 76, `docs/QUAY_LEDGER.md` §6 slice 1.)*
1. Header `TRADE / Market · Lisbon ⓘ` (`:257-261`).
2. Card of controls: `PORT Lisbon ▾` and `name · all ▾`; the port picker opens to a search field, `All 238 ports — Iberia first.`, `YOUR FLEET` chip, and **238 port chips** in a wrap (`:264-333, 563-606`); the options open to `SORT name price stock` and `FILTER all traded` chips.
3. Card with header bar `Goods ⓘ` + badge `10 GOODS`; `Tap a good to send it to Command.`; block label `▾ TRADED HERE`; tiles with `RANGE 62–94 ─`(sparkline), `BUY 78`, `SELL 72`, `STOCK ▓▓▓░░░` (`:356-402, 469-514`); footer `tax 3.0% · spread 2.0% · trade 20/10 · latin culture ⓘ` and `Gaivota is here — 56 t of hold free.` (`:384-399`).
4. Accent card `HOW TO READ IT / NEARBY says cheap HERE — not profitable. ⓘ` (`:407-421`; screenshot `30-market-2`).

### MAP (`src/features/map/MapScreen.tsx:305-426`) — full-bleed
Chart; top-left `FLEETS 1 ▾` panel (folded on phone, opens to a fleet list, `FleetsPanel.tsx:51-105`); top-right `+ − ⌖` (`chart/ViewControls.tsx:46-82`); bottom-left minimap (`chart/Minimap.tsx`); bottom-right detail panel on a tap — fleet: `FLEET / Gaivota / at Lisbon / stores 15.0 days / Tap where she should go — a harbour, or any water.` (`DetailPanel.tsx:113-182`); sea or port: name + `[Send fleet]` → fleet rows `Gaivota / Lisbon / 229 nm · 1.9 days` → `KEEP & SEND ⓘ`, preset chips, `15.0 / 15 days` hero, −/gauge/+, `[Keep 15 & send]` (`SendFleet.tsx:383-587`; screenshot `45-map-send-fleet-picked`); bottom caption bar `1 min = 160 h sail · read 2s ago` (`MapScreen.tsx:411-423`).

### LEDGER (`src/features/ledger/LedgerScreen.tsx:122-193`)
Header `RECORD / Ledger ⓘ`; card of filter chips `ALL FOUNDED …` + `1 of 1 entries / read just now` (`:131-161`); one card per event: `10:38 [FOUNDED] just now`, serif headline, report paragraphs, `+8,000 d.` (xl) + `balance 8,000 d.` (`:210-257`); footer notice `Purse 8,000 d. — the balances above will not sum to it. ⓘ` (`:180-191`).

### RANK (`src/features/rank/RankScreen.tsx:121-241`) — 1,237 px
Header `STANDINGS / Rank ⓘ`; card `The table of captains ⓘ · Settled just now · 10 HOUSES` with a 5-column table that clips at `TRA…` + `Swipe the table for the rest.` (`:302-378`); card `Casa de Aveiro [PORTUGAL]` with `Purse ⓘ / Fleets ⓘ 1 / 2 / Ships 1 / 8` + gauge `hulls the house may still own` (`:131-175`); card `Fame ⓘ`: trade ⓘ, exploration ⓘ, total, ports reached, turned over (`:178-202`); card `Levels ⓘ`: Trading ⓘ, Exploration ⓘ, Combat ⓘ (`:205-239`).

### CODEX (`src/features/compendium/CompendiumScreen.tsx:221-283`) — 39,365 px on Goods
Header `REFERENCE / Compendium ⓘ`; card header `Trade goods ⓘ` (a 90-word paragraph behind the dot, `:84-98`); tabs `GOODS 523 · SHIPS 3 · CAPTAINS 51 / NATIONS 20` (wraps); filter field; two chip strips (kind ×17, rarity ×4) each scrolling sideways + `Swipe for the rest.`; `523 of 523 goods`; per category a label and tiles `BASE 512.5 d. / BULK 1.5 t / SPOILS — / REFUSED BY —` (`:512-576`). Ships: tiles of 8 figures incl. `build 40 h`, `cost 2,400 d.` (`:623-649`). Captains: 51 tiles with badge, blurb, bonus, wage, port, nation, `no rule reads this specialty yet — the bonus changes nothing` (`:727-772`) — 6,436 px. Nations: 3-col table (`:805-835`).

### PROFILE (`src/features/profile/ProfileScreen.tsx:59-203`)
Header `ACCOUNT / Profile ⓘ`; card `Session ⓘ` with a sentence, a disabled `Sign out` and `No account to sign out of.` (`:68-86`); card `This world`: `Where this world is ⓘ local / World open / Ports ⓘ 238 / Goods 523 / Time ⓘ 9,600x` (`:115-150`); card `The house`: company, nation, level, founded ⓘ, lying at ⓘ (`:152-183`); card `Not in the game yet ⓘ` — three bullets of unbuilt features (`:187-201`).

### Once-only: SIGN THE BOOK (`src/features/found/SignTheBook.tsx:49-104`), AUTH (`src/features/auth/AuthPage.tsx:50-105`). Both fine in shape; Sign the Book's ⓘ text cites `(DESIGN K.1)` — a repo document name, on a player screen (`:55`).

### What the store holds vs what the UI does with it (`src/live/worldStore.ts:103-207`)
* Read and shown, but nobody needs it: `mode` (Fleets footer `:283`, Profile `:120`), `phase` as a word (Profile `:127`), `readAt` printed as "read Ns ago" / "as of HH:MM" on **five** screens (Command `:564`, Fleets `:282`, Ledger `:157`, Map `:420`, Rank via `age_seconds`), `busy` as the TopBar dot, `snapshot.config.time_compression` as `9,600x` (Profile) and `1 min = 160 h sail` (Map), `snapshot.ports.length` / `goods.length` (Profile), `player.company_level` (Profile — no rule reads it), `config.order_queue_max` as `0/12 queued`, `config.fleet_max`/`ship_max` as `1/2 fleets · 1/8 ships` (Fleets header AND Rank AND a gauge).
* Read and shown where it does change a decision: prices, ranges, stock, `free_hold`, `endurance_days`, `speed_kn`, crew counts, hull %, ETA, `buy_capacity`, the preview estimate, refusal figures. These are the game. They are surrounded by the first list.
* Held but never rendered: `fleet.version` (correctly), `refusal.detail` (behind a dot), `officer_pct.QUARTERMASTER` (only as a sentence).

## 2. The noise list — ranked by what it costs

Cost = pixels × how often the screen is visited × how far it sits from a decision. "Fails the test" means: no decision the player is about to make changes because this is on screen.

| # | what | where | why it fails |
|---|---|---|---|
| 1 | **The order scaffolding above the verb grid** — `MAKE / An order ⓘ`, `12 VERBS` badge, `ORDER ⓘ` box with `> nothing yet`, `Issue` + `Discard`, `Nothing to check yet ⓘ`, `VERB` label. ~430 px of chrome on the most-visited screen before the first choice; the Issue button is disabled 100 % of the time it is first seen. | `CommandScreen.tsx:474-527`, `OrderComposer.tsx:282` | An empty order has nothing to issue, discard, check or read. The `>` line is the server parser's grammar (`SAIL Gaivota TO CAD`) shown as if a player wrote it. |
| 2 | **Rail-before-pickers on the phone.** Choose BUY and the next 700 px are HOLD / THIS ORDER (`Choose a good and the quay will price it.`) / PRICE MOVEMENT with four ⓘ rows — the goods themselves start ~1,900 px down. | `OrderComposer.tsx:336-397` + `screenLayout.ts:62` (`md:order-last`) ; `FleetRail.tsx:165-323`; screenshot `02-command-buy-2/3` | Spread, purser, tax and "each 10 t dearer" are already inside the price printed on the cell. None of them is a lever the player can pull here. |
| 3 | **12 verb cards with help sentences**, 2 per row, 6 rows, ~1,000 px. STORE/TAKE/MAKE/BUILD/FIT/UNFIT show letter glyphs (`S`, `T`, `M`…) because they have no icon. | `OrderComposer.tsx:284-327`, `verbIcons.ts:15-24` | A verb is one word. The help line is read once ever; the letters are placeholders that shipped. |
| 4 | **Hero triad on Command** `PROVISION ⓘ / SPEED / CARGO ⓘ` shown for every verb, then repeated inside the rail (HOLD hero, STORES hero) and again on Fleets. | `CommandScreen.tsx:432-468`, `FleetRail.tsx:172, 498` | Speed changes no order composed here. Provision matters to SAIL, hold to BUY — each belongs beside its verb, once. |
| 5 | **Eighty-one ⓘ dots.** One on every page title, on `provision`, `cargo`, `Order`, `Ships`, `Cargo`, `the hold`, `how fresh this is`, `Purse`, `Fleets`, `Founded`, `Ports`… Each is a 15 px glyph with a paragraph behind it. | count over `src/**`; heaviest `FleetRail.tsx` (14), `RankScreen.tsx` (11), `ProfileScreen.tsx` (9), `FleetsScreen.tsx` (8) | "Prose is a tooltip" became "a tooltip on every noun". A dot beside a label that is already plain (`Purse`) is a tax on the eye with no answer behind it. |
| 6 | **Fine-print sentences** (93 `fineClass` sites): `10 goods traded here, by name`; `Distances are still being fetched — every figure, when it lands, is the sailed water from where she lies, never a straight line.`; `up to 40 t — the hold stops you there`; `Water and food take the same tuns as cargo.`; `Your quartermaster is worth 3.0% of it, and it is already counted.`; `She is at sea. Crew are signed on in port.`; `Read 1s ago · local`; `1 min = 160 h sail`. | `tradePickers.tsx:143-148, 509-516`; `ArgPickers.tsx:168-173`; `FleetRail.tsx:183-187, 426`; `FleetsScreen.tsx:280-289`; `MapScreen.tsx:415-421` | Each is the code narrating itself. The slider already stops at 40; the count is visible; the map's scale is not a decision input. |
| 7 | **Dead lecture card on Market** — `HOW TO READ IT / NEARBY says cheap HERE — not profitable.` The NEARBY figure was removed by migration 0071; the card explaining it is still the last thing on every market visit. | `MarketScreen.tsx:407-421`; the header comment `:62-69` admits the figure is gone | Explains a number that is not on the screen. |
| 8 | **238 port chips** in a wrap when the port picker opens (page grows to 5,566 px). | `MarketScreen.tsx:594-604` | A search field already exists above it; the wall of chips is the search's failure mode made permanent. |
| 9 | **Port header stack**: eyebrow, `Port · Lisbon ⓘ`, `Portugal · latin culture · North Atlantic Ocean`, `DRAFT 5` badge, the roads sentence, the "quay is quiet" sentence — ~400 px before the panel; then seven face tabs that wrap to two rows, then Buy/Sell tabs, then a filter, then the count line. First price at ~1,300 px. | `PortScreen.tsx:258-319`, `PortFair.tsx:92-101`, `PortTrade.tsx:135-145` | Draft only matters when it refuses a hull (say it then). Culture only matters when it refuses a good (say it on the good). "Nothing is on" is news about nothing. Two rows of tabs is a menu, not a face. |
| 10 | **The queue card when the queue is empty**: `STANDING / Her queue ⓘ / as of 10:39 / Gaivota [DOCKED] 0/12 queued / Gaivota is alongside with nothing to do. A docked fleet earns nothing. / [Clear Gaivota's queue]` (disabled). | `CommandScreen.tsx:554-588`, `OrderQueue.tsx:69-107, 146-154` | Six lines and a dead button to say "0". The moralising sentence is the game scolding the player for reading the screen. |
| 11 | **Fleets shows the same fleet three times**: roster block (where/due/provision/hold/hull), a table variant of it at ≥640 px, and the collapsible detail (ships table with Hull/Crew/Hold/Load/Free). Plus `1/2 fleets · 1/8 ships` in the header, and again on Rank. | `FleetsScreen.tsx:170-264, 468-728`; `RankScreen.tsx:148-173` | One fleet, one place. Load and Free are the same fact as Hold twice. |
| 12 | **"Fitted" section per ship** — `GAIVOTA — FITTED / Nothing mounted. She sails as the shipwright rated her. / rig 0/1 · weapon 0/1 · ground-tackle 0/1 · 3 cabin(s)` and the empty **Standing orders** card `The book is empty. Not an error — a state. [New]`. | `FleetsScreen.tsx:558-590, 326-363` | Empty states are printed as paragraphs. `3 cabin(s)` — cabins hold nothing yet (`docs/OWNER_REQUESTS.md` row 68). |
| 13 | **Developer vocabulary in player text**: refusal codes `E_HOLD_FULL`, `E_UNKNOWN`, `E_REFUSED` as badges and prefixes; `local`/`cloud`/`open`/`failed`; `row(s) across N table(s)` and the storage key `byeharu-voyage.rescue.v1`; `(DESIGN K.1)`; `9,600x`; `ran on the server and was rolled back`; `<good>` placeholders rendered from fix strings; `0/12 queued`; `PENDING/ACTIVE/DONE` badges. | `RefusalNote.tsx:80`, `WorldGate.tsx:37-39`, `PortFaces.tsx:58`, `HaggleBlock.tsx:178`, `OrderQueue.tsx:121-123`, `RebuildNotice.tsx:89-98`, `SignTheBook.tsx:55`, `ProfileScreen.tsx:120-148`, `PreviewPanel.tsx:129, 157-172` | Jargon leaking. A code is for a log, not a quay. |
| 14 | **The parser line as UI**: `> BUY Gaivota aniseed 20` on Port, `> SAIL Gaivota` on Command, `SAIL Gaivota TO CAD` buttons on a sea place, order rows `[1] SAIL Gaivota TO CAD`, fix lines `SELL <good> ALL` with `make this`/`start this`. | `PortTrade.tsx:167-175`, `CommandScreen.tsx:72-87, 494`, `PortScreen.tsx:237-247`, `OrderQueue.tsx:112-113`, `PreviewPanel.tsx:76-98` | The string is the wire contract, not the player's language. Nobody reads `TO CAD`. |
| 15 | **Section labels in uppercase letter-spaced mono** everywhere (`COMMANDING`, `NEEDS`, `WHICH GOOD`, `PRICE MOVEMENT`, `WHAT THIS CITY KEEPS`, `ROSTER`, `STANDING`, `HOLD`, `THIS ORDER`…) — 31 `SectionLabel` + 35 `uppercase tracking-wider` sites + every table header, badge, nav label, tile line label. | `SectionLabel.tsx:6-10`, `NavBar.tsx:52`, `Badge.tsx:18`, `Table.tsx:77`, `EntryTileLine` `EntryTile.tsx:159` | The label voice is louder than the content voice. Uppercase tracking is the single strongest "2008 dashboard" signal on the screen. |
| 16 | **Codex tile figures nobody uses**: `SPOILS —`, `REFUSED BY —` on most of 523 goods; ship `build 40 h` and `cost 2,400 d.` for hulls no order can commission (`statGloss.ts:101-110` says so); captain tiles printing `no rule reads this specialty yet — the bonus changes nothing`. Two chip strips + `Swipe for the rest.` + `523 of 523 goods`. | `CompendiumScreen.tsx:549-568, 634-646, 765-769, 342-360, 441-445` | A dash is a figure that isn't there. A stat the rules do not read is a stat the player cannot use. |
| 17 | **Rank's four cards** — Purse (already in the TopBar), Fleets/Ships limits with a gauge captioned `hulls the house may still own`, Fame split five ways, Levels with `Combat — Level 0 ⓘ "There is no combat in this game yet"`. | `RankScreen.tsx:131-239` | The board row already carries the fame. Limits are not rank. A level track that admits it is empty should not be on screen. |
| 18 | **Profile's diagnostics** — `This world` (mode, phase, port count, good count, time compression) and `Not in the game yet` (a changelog of missing features). | `ProfileScreen.tsx:115-150, 187-201` | Developer telemetry and a roadmap on a player screen. |
| 19 | **Ledger chrome** — filter card with `1 of 1 entries / read just now`, per-entry four-item header (time, fleet, badge, relative time), `balance 8,000 d.` on every row, footer notice about balances not summing. | `LedgerScreen.tsx:131-161, 212-224, 253-255, 180-191` | The balance is the purse; the purse is in the top bar. Two timestamps per row. |
| 20 | **Map caption bar** `1 min = 160 h sail · read 2s ago`, the detail panel's `Tap where she should go — a harbour, or any water.` hint, `KEEP & SEND ⓘ` label, `None` preset chip when there are no presets. | `MapScreen.tsx:411-423`, `DetailPanel.tsx:44-53`, `SendFleet.tsx:484-499` | The map is the one screen closest to the owner's rules; these are the last four sentences on it. |
| 21 | **Wall clock with seconds** `10:39:02` on Command; `prices move in 5:57` is useful, the seconds are not. | `CommandScreen.tsx:352-358` | A ticking second hand draws the eye every second and changes nothing. |
| 22 | **TopBar wordmark** `BYEHARU VOYAGE` (134 px, letter-spaced mono) on every screen; the "live read" dot; `D.` after the purse. | `TopBar.tsx:36-45, 51-56, 67` | The player knows what game they are in. A dot that means "the store is fetching" is telemetry. |
| 23 | **Unit suffixes on every figure** `d./t`, `d.`, `t`, `kn`, `days` in 10 px beside 16 px numbers — 91 `font-mono` sites in features alone. | `tradePickers.tsx:340-352`, `lib/format/numbers.ts:44, 57` | On a tile whose column is headed BUY the unit is known; printed 20 times per screen it is texture. |
| 24 | **Text glyphs as icons**: `▾ ▴` on buttons, `▓▓░░` stock bar, `⚑` flagship, `✕` delete, `>` prompt, `−/+` steppers, `=2` tie marks. | `MarketScreen.tsx:275, 288, 451`, `marketRows.ts:65-69`, `FleetsScreen.tsx:742, 415`, `RankScreen.tsx:415` | Typewriter art in a game that draws 96 custom SVG marks for goods. |
| 25 | **RebuildNotice** — three paragraphs with two ⓘ and two buttons at the top of the app. | `RebuildNotice.tsx:66-134` | Correct to say; wrong at this length. One line and one button. |

## 3. The structural verdict — what is old-fashioned, by name

1. **Every screen is the same admin document.** `Screen` → `PageHeader(eyebrow, title, ⓘ, actions)` → N × `Card(head: CardHeader(eyebrow, title, ⓘ, aside Badge))` → `SectionLabel` → `dl` of `StatRow`/`DetailRow` → fine-print footer. That is the Bootstrap-era "page with panels" template, and the code enforces it: `Screen.tsx:9-23`, `PageHeader.tsx:26-67`, `Card.tsx:31-58`, `CardHeader` `:61-106`, `SectionLabel.tsx`. Thirty-three `<Card` and nine `PageHeader`s. Boxes inside boxes: Command nests Card → ORDER_BOX → arg box → tile → cell (`CommandScreen.tsx:474` → `:483` → `OrderComposer.tsx:433` → `EntryTile.tsx:45` → `tradePickers.tsx:391`) — five borders deep on one tap target.

2. **Tables as the default list, then a machine to make them survive a phone.** Fleets ships (8 cols), Rank (5), Cargo (3), Nations (3): `Table/TH/TD` (`Table.tsx:42-103`), `scrollTableClass` with a sticky first column and painted scrollbars (`tableLayout.ts:37-60`), `hScrollClass` (`scrollAffordance.ts`), `useClipped` ResizeObserver (`useClipped.ts:17-37`) to decide when to print `Swipe the table for the rest.`, a `hidden sm:block` duplicate of the roster (`FleetsScreen.tsx:170-264`), and 200 lines of `tests/layout.spec.ts:88-196` policing overhang. All of it exists so that a table can be used where a list of rows or tiles would simply fit. On screen the result is a header that reads `TRA…` (screenshot `60-rank-1`).

3. **Monolithic screen files with local sub-components and prop chains.** `CompendiumScreen.tsx` 899 lines / 9 components; `FleetsScreen.tsx` 883 / 5; `OrderComposer.tsx` 855, whose inner `ArgPicker` takes **14 props** (`:560-599`) forwarded from `OrderComposer`'s 10 (`:91-117`), which `CommandScreen` assembles from 15 store selectors (`:92-118`); `MarketScreen.tsx` 769 / 7; `SendFleet.tsx` 753 in one component with 12 selectors, 5 `useState`s and nested async closures (`:125-158, 242-306`); `GoodPicker` 11 props (`tradePickers.tsx:79-110`); `StandingLine` 9 props (`RankScreen.tsx:383-403`). Screens fetch everything at the top and drill it down — "container at the top, dumb children below" is the 2016 shape; the store already supports selecting at the leaf (`worldStore.ts` rule 4).

4. **A design system made of class-string builders, and screens that still hand-roll.** `buttonClasses`, `fineClass`, `rowLinkClass`, `headRowClass`, `inlineFigureClass`, `scrollTableClass`, `tileFieldClass`, `overlayPanelClass`, `hScrollClass` (`buttonStyles.ts`, `typography.ts`, `tableLayout.ts`, `tileLayout.ts`, `overlayLayout.ts`, `scrollAffordance.ts`) are string concatenation, not components; every caller adds an `extra` override (`buttonClasses('chip', 'md', 'font-mono text-xs uppercase tracking-wider')` appears in `ArgPickers.tsx:221, 246, 346`, `LedgerScreen.tsx:143-147`, `CompendiumScreen.tsx:391-402`, `tradePickers.tsx:461`), so a chip has no one look. Nine bordered skins are still written inline (`OrderComposer.tsx:296, 433`, `PortFaces.tsx:96, 190`, `HaggleBlock.tsx:104`, `FleetRail.tsx:142`, `PortYard.tsx:123`, `FleetsScreen.tsx:176`, `SendFleet.tsx:431`). Three different "selectable block" recipes coexist: `EntryTile.tileSkin` (`EntryTile.tsx:44-57`), the verb card (`OrderComposer.tsx:295-300`), and `PortPicker`'s `buttonClasses('chip', …, 'flex-col')` (`ArgPickers.tsx:135-139`).

5. **Five spellings of "label · value".** `StatRow` (`StatRow.tsx:19-47`), `DetailRow` (`DetailRow.tsx:31-66`), `EntryTileLine` (`EntryTile.tsx:155-165`), `Line` (`DetailPanel.tsx:74-80`), and inline `grid grid-cols-[auto_1fr]` dls (`FleetsScreen.tsx:185-223, 658-700`). Three spellings of "a bar": `Meter`, `Gauge`, `stockBar` text (`marketRows.ts:65-69`) plus `DangerMark` pips and `EnduranceBar` (`DetailPanel.tsx:57-72`). Three fold primitives: `Collapsible`, `CollapsibleCard`, `Explain` disclosure, plus `MapPanel` wrapping `Collapsible` inside `OverlayPanel` with an absolutely-positioned close button over its header (`MapPanel.tsx:77-108`).

6. **No type scale.** Ten distinct sizes in use: `text-xs` ×76, `text-sm` ×73, `text-[10px]` ×26, `text-[11px]` ×15, `text-lg` ×11, `text-base` ×9, `text-2xl` ×3, `text-xl` ×2, `text-[15px]`, `text-[13px]`. Three families — a *system* serif stack for titles (`index.css:98`, renders as Georgia/Noto Serif depending on device), Inter, JetBrains Mono — and the mono is used as the *label* voice, not the figure voice (`SectionLabel`, `Badge`, nav, table heads, `fineClass`). Spacing is ad hoc (`mt-0.5`, `mt-1`, `mt-1.5`, `mt-2`, `mt-3`, `mt-4`, `gap-x-0.5`, `-my-1.5`, `pr-11`, `bottom-11`). The `@theme` block (`index.css:38-159`) is a palette, not a scale.

7. **The 2026-08-20 "material" is the old-fashioned skin.** `.bv-cut` clip-path corners (`index.css:201-210`), `.bv-brass` gradient buttons with rims (`:213-219`), `.bv-panel-head` brown gradient header bars with a gold hairline (`:194-197`), warm-mixed panel tones (`:110-116`), serif display titles. This is the 대항해시대 오리진 chrome the owner pointed at in August as a reference for *density*; copied as *material* it reads as a decade-old browser game. The screenshots show it: every screen is brown boxes with clipped corners on a blue gradient.

8. **Layout expressed as JS arithmetic and prose.** Tile columns are computed in JS (`useTileCols.ts`, `tileFieldCols`, `inRowsOf`) so that a fold can be inserted "after the whole row" (`tradePickers.tsx:158-231`, `ArgPickers.tsx:105-167`); the nav's cell count is justified in a 60-line comment and asserted by a geometry spec; the rail's breakpoint is a 30-line comment (`screenLayout.ts:13-47`). Comments make up roughly half of every screen file. A layout that needs an essay is a layout without a system.

9. **Tooltips and titles** (57 `title=` attributes on a touch-first app) and `aria-expanded` chevrons drawn as text (`choose` / `change`, `OrderComposer.tsx:466-474`).

What is *not* wrong and must be kept: the store shape (one world, selectors per field), `domain/*` purity, the section boundaries (`tests/sections.spec.ts`), the chart layer, the 44 px reach floor, the "press moves nothing" rule, the served-number discipline, the hand-drawn goods marks (`icons.ts` — genuinely good), and the phone-first measurement habit.

---

# PART 2 — THE DIRECTION

## 4. Atmosphere — what "modern" means here, and the numbers

**Words are `docs/WORDS.md`'s.** This document decides how a screen is BUILT; what it SAYS is the
vocabulary law — plain modern words, no number without its whole, units spelled once in
`src/lib/format` — and `tests/words.spec.ts` is its teeth. Added 2026-09-13 after the owner's second
complaint about the same words; nothing below overrides it.

**Commit: an instrument over a living sea.** Not a ledger, not a brass console. The world (sea, coast, ports) is the ground on every tab; everything the player reads sits on flat, translucent sheets that rise from the bottom edge or hang in a corner; type is one family, quiet and tabular; colour is reserved for meaning; there is no border where a hairline or a tone step will do. The number is the loudest thing on the screen because nothing else is allowed to be loud.

Reference points, and what is taken from each:
* **Apple Maps' place sheet** — the map is always the ground; detail comes up as a bottom sheet with three detents; corners hold controls; nothing sits in the centre. This is the Port, Map and Send-fleet grammar.
* **Linear** — one sans, a 5-step type scale, hairlines instead of boxes, tone steps instead of borders, 8-px rhythm. This is the surface language.
* **Robinhood / Trade Republic** — a price is a headline figure with a sparkline and two big actions at the bottom; the detail is one tap down. This is the good tile and the trade tray.
* **Alto's Odyssey / Monument Valley** — a game whose chrome is nearly absent and appears only when summoned. This is the posture toward chrome.
* Explicitly **not** 대항해시대 오리진's material (brass, brown, clipped corners, serif) — take its density lesson only, which the tiles already have.

### 4.1 Type — one family, five sizes
Inter (already bundled), `font-variant-numeric: tabular-nums` on **every** figure via the `Figure` primitive, no serif, no mono except inside a code-like value that the server serves as code (none today). No uppercase, no letter-spacing, no italics.

| token | size/line | weight | use |
|---|---|---|---|
| `t-caption` | 12 / 16 | 500 | units, secondary meta, chip text |
| `t-label` | 14 / 20 | 400 | row labels, body copy, tile secondary line |
| `t-body` | 16 / 22 | 500 | row values, tile name, button text |
| `t-title` | 20 / 26 | 600 | sheet title (collapsed state), section heading |
| `t-figure` | 24 / 28 | 600 tabular | the one figure a block is about (price cell, ETA, purse) |
| `t-hero` | 34 / 38 | 600 tabular | the headline figure of a sheet (capacity, passage days) |

Colour on type: primary `ink`, secondary `ink-2`, tertiary `ink-3` (units, disabled). Never a fourth.

### 4.2 Space — 4-pt base, 8-pt rhythm
`4 · 8 · 12 · 16 · 24 · 32 · 48`. Screen gutter 16. Sheet padding 16. Row height 52 (44 target + 8). Tile min-height 112 with 12 padding. Section gap 24. Control gap 8. Nothing else.

### 4.3 Shape and elevation
* Radius: sheet 16 (top corners only when docked), tile 12, control 10, chip 999. No cut corners.
* Borders: none on tiles or rows. Separation is by tone step (`surface` on `bg`, `surface-2` inset on `surface`) or a 1-px `edge` hairline at 8 % alpha between rows.
* Elevation: exactly two levels. Docked sheet: `0 -8px 32px -16px rgb(0 0 0 / .45)`. Floating corner panel: `0 8px 24px -12px rgb(0 0 0 / .5)` + `backdrop-filter: blur(16px)` on a 72 %-alpha surface.
* A **surface** is defined as: a rectangle of `surface` colour, radius per the table, no border, one level of nesting allowed inside it (row or tile), never a surface inside a surface.

### 4.4 Colour tokens — light and dark, both first-class
Both palettes ship; `prefers-color-scheme` picks, the Cabin toggles. Dark stays the default for a night sea; light is a day sea.

| token | dark | light | meaning |
|---|---|---|---|
| `bg` | `#0A1018` | `#EEF2F6` | the ground under the sea gradient |
| `sea-1` / `sea-2` | `#0E1B2B` → `#070C14` | `#DCE8F2` → `#C9DAE8` | the world layer gradient (chart sea = `sea-2`) |
| `surface` | `#131C27` | `#FFFFFF` | sheet, tile |
| `surface-2` | `#1B2634` | `#F2F5F8` | inset cell, chip rest |
| `edge` | `rgb(255 255 255 / .08)` | `rgb(16 24 40 / .08)` | hairline |
| `ink` | `#F3F5F8` | `#111827` | primary text |
| `ink-2` | `#A9B3C0` | `#4B5563` | secondary |
| `ink-3` | `#6C7684` | `#8A94A3` | units, disabled, placeholders |
| `accent` | `#E2B45C` | `#B07E1F` | the one interactive colour: selected, primary action, your fleet on the chart |
| `accent-soft` | `accent` @ 14 % | `accent` @ 12 % | selected tile wash |
| `gain` | `#4FCB8B` | `#1E9E5F` | cheap / profit / safe |
| `loss` | `#F0655A` | `#D64545` | dear / loss / danger |
| `warn` | `#F2B84B` | `#C98A1B` | short, low, halted |
| `info` | `#6AA9F5` | `#2F6FD1` | at sea, en route |
| `land` / `coast` | `#3C4654` / `#5B6674` | `#B9C4CF` / `#8F9CAA` | chart |

Rules: gold means *you may act / yours*; green–red only ever mean cheap–dear or gain–loss; blue means moving; grey with a stated reason means *you may not*. Rarity keeps its four hues but only as the 10-px mark, never as text colour.

### 4.5 Icons and marks
One stroke set at 20 px / 1.75 stroke (the existing `Icon` renderer is fine; the nine chrome glyphs in `icons.ts:15-34` need redrawing to that weight). The 96 goods marks stay. Text glyphs (`▾ ▓ ⚑ ✕ > =`) are banned; every one becomes an `Icon` or a `Bar`.

### 4.6 Motion
Sheets: 240 ms `cubic-bezier(.2,.8,.2,1)` rise/fall. Fold: height auto with 180 ms. Nothing else animates. `prefers-reduced-motion` collapses all to 0.

## 5. Component architecture — the primitives, and what dies

Twelve primitives. Every screen is composed from these and nothing else; `tests/duplication.spec.ts` is repointed to fail on any inline `border … bg-` skin or any `text-[…px]` in `features/`.

| primitive | is | replaces (dies) |
|---|---|---|
| **`Sheet`** | the one scrolling surface of a tab. Title (t-title) that starts large and pins small on scroll; one optional trailing control; sections separated by 24 px and a t-label heading, never by boxes | `Screen`, `PageHeader`, `Card`, `CardHeader`, `SectionLabel`, `Collapsible`, `CollapsibleCard`, `screenLayout.ts`, `EmptyState` (an empty section is one `Row` of `ink-3` text) |
| **`Tray`** | a bottom-docked sheet with detents (peek 96 px · half · full), summoned by a tap and dismissed by drag or ✕. The place every "unfold under the press" goes: quantity, passage check, queue, fleet detail, port detail on the map | `OverlayPanel`+`MapPanel` for the bottom slot, `Explain`/`ExplainPanel` (long text opens a tray), the inline `GoodDetail` fold and `sailConfirm`, `inRows`, `useTileCols`, `tileLayout` (grid is CSS `repeat(auto-fill, minmax(160px, 1fr))`; nothing above a press ever moves because nothing is inserted into the grid) |
| **`Corner`** | a corner-anchored floating glass panel with a fold chevron; max 2 per screen; never centre | `OverlayPanel`, `overlayLayout.ts`, `MapPanel` (top slots) |
| **`Row`** | 52 px: leading mark · label · trailing `Figure` or text · optional chevron; tappable variant | `StatRow`, `DetailRow`, `EntryTileLine`, `Line`, `StatLegend`, every inline `dl`, `Table/TH/TD`, `tableLayout`, `scrollAffordance`, `useClipped`, `TABLE_SCROLL_HINT` |
| **`Figure`** | value + unit at t-figure / t-hero / t-body; tabular; the unit at t-caption in `ink-3` | `HeroFigure`, `inlineFigureClass`, every `font-mono … tabular-nums` span |
| **`Tile`** | selectable block: mark, name, one or two `Figure`s, optional `Bar`; states rest / selected (accent-soft wash + accent hairline) / muted; whole-tile or head tap | `EntryTile`, `GoodTile`, the verb card, `PortPicker` chip-tiles, Fleets' phone block, officer/skill cards, `SendFleet` rows |
| **`Bar`** | one fill bar 4 px, optional segments, tone by meaning, optional trailing figure | `Meter`, `Gauge`, `stockBar`, `DangerMark`, `EnduranceBar`, `Sparkline` stays as `Bar.trend` |
| **`Chip`** / **`Segmented`** | pill toggle (filter, preset); segmented control for 2–5 faces of one thing | `buttonClasses` chip/chip-on/chip-soft, `Chip`, `PortChip`, `TabRow` |
| **`Button`** | primary (accent fill, `ink` on it), secondary (surface-2), quiet (text), destructive; 44 and 36; icon | `Button` + `buttonStyles.ts` (flat; `.bv-brass` dies) |
| **`Field`** / **`Stepper`** | search/filter/text field; stepper = − `Figure` + over a slider, with max as the slider end and the server's ceiling as a tick | `Input`, `FilterBox`, `QtyPicker`, `NumberPicker`, `PricePicker`, `TruncationNote` |
| **`Note`** | one line with tone + optional single action. Refusal form: `Bar` have/need + `Figure` + one fix button; the code never prints (it goes to `console.debug`) | `Notice`, `RefusalNote`, `Badge`, `WorldFailed` body, every `refusal.code — sentence` |
| **`Hint`** | a t-caption line under a label, present only where the caller passes one; long text opens a `Tray`. Budget: one per section, none on titles | `Explain`, `ExplainDot`, `ExplainPanel`, `explainState`, all `title=` attributes |
| **`Nav`** | the tab bar: 5 + Cabin, 22 px icon, 12 px label, no uppercase; group opens a `Tray` | `NavBar` restyle, `navGridClass` |

Kept as-is: `Icon`/`icons.ts`, `goodIcons.ts`, `Skeleton`, `Clock`/`Countdown`, `Sparkline` (as `Bar.trend`), `rarityTiers`/`RarityMark` (mark only), the whole `src/chart` layer, `reaskAtEdge`.

Also dies from `index.css`: the MATERIAL block (`:100-158`), `.bv-panel-head`, `.bv-cut`, `.bv-brass`, `--font-serif`, `--font-mono` as a label voice, the "Conventions" line (`:32-35`). `.bv-sea` stays as the world layer, retuned to the tokens above.

Architecture rules that go with the primitives:
* A screen file is ≤ 250 lines and contains one exported component. Sub-views are files. A component takes ≤ 6 props; anything read from the world is read by the leaf with its own selector (`worldStore` rule 4 already permits this).
* No screen prints a `readAt`, a mode, a phase, a config knob or a code.
* No screen prints the order string. `orderText()` is called at issue time only.

## 6. Per-screen redesign — 390×844

Legend for the sketches: `═` sheet edge, `┄` hairline, `[ ]` button/chip, `◆` selected, `▔` bar. The Nav is 56 px at the bottom of every sketch; the sea is behind everything.

### COMMAND
Stays: fleet choice, the twelve verbs, the pickers, the server check, the queue. Cut: header, clock seconds, hero triad, "Make/An order", the order line, Issue/Discard above the grid, "Nothing to check", NEEDS/VERB labels, the rail. Folded away: queue (a pill on the fleet chip → Tray), verb help (long-press → Hint tray), fleet stats (one line under the fleet chip, only the figure the chosen verb needs).

```
 ◎ 8,000            prices ↻ 5:57      ← status strip, 32px, ink-2
════════════════════════════════════
 Gaivota · Lisbon         [queued 0]  ← fleet chip row; more fleets scroll sideways
 15 d stores · 56 t free              ← ONE line, t-label, per verb
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
 ⌖ Sail    ◎ Buy     ⚖ Sell           ← 3×4 verb tiles, icon + word only,
 ⛃ Provision 👥 Hire ⚒ Repair            64px tall, 12 in 4 rows = 300px
 ⬒ Store   ⬓ Take    ✂ Make
 ⛵ Build   ⚙ Fit     ⚙ Unfit
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
 (chosen verb's ONE question here)
 BUY:  [🔍 filter]
       ┌──────────┐ ┌──────────┐
       │ ✦ Aniseed│ │ ✦ Pepper │      ← Tile: mark, name, price Figure,
       │   78     │ │   149    │         range as a tiny Bar, buy/sell
       │ 62▔▔▔▔94 │ │113▔▔▔170 │         as the tile's two tap zones
       └──────────┘ └──────────┘
────────────────────────────────────
  TRAY (peek) after a tap:
  Aniseed · buy        40 t at most
  −  [   20 t   ]  +   ▔▔▔▔▔▔▔▔▔▔
  costs 1,560   ·  hold stops you
  [        Buy 20 t · 1,560        ]  ← the ONE primary button, always at
                                         the bottom edge, never in the scroll
```
SAIL: the chart takes the top 40 % of the sheet (it is the question), harbour tiles below (name + nm), tap → tray `Cádiz · 254 nm · 2.1 d · 15 d stores ✓  [Sail]`. HIRE/PROVISION/REPAIR: the `Stepper` is the question; the tray shows the server's cost line and the button. The haggle is one row in the buy tray (`Bargain · 3 left · 45 % [Try]`). The queue tray lists orders as rows `Sail to Cádiz · at sea 1.9 d` with a trailing ✕; a halted queue is one `Note` at the top of it.

### PORT
Stays: faces, the trade grid, warehouse/workstation/inn/yard. Cut: eyebrow/title/subtitle/draft/roads/quiet; the seven-tab wrap; Buy/Sell sub-tabs (the tile has both prices; the tap zone decides); count lines. Folded: town facts into one row group; a running fair becomes one accent `Row` at the top.

```
════════════════════════════════════
 Lisbon                      ⛵ Gaivota   ← title + who is here
 [Trade ◆][Town][Store][Craft][Inn][Yard] ← Segmented, ONE row, scrolls
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
 ▲ Fair on · 30 % off the cut · 2 d      ← only when true
 [🔍 filter]
 ┌──────────┐ ┌──────────┐
 │ ✦ Aniseed│ │ ✦ Pepper │
 │ 78 · 72  │ │149 · 137 │              ← buy · sell, two tap zones
 │ 62▔▔▔▔94 │ │113▔▔▔170 │
 │ ▪▪▪▫▫▫   │ │ ▪▪▪▪▪▫   │              ← stock segments
 └──────────┘ └──────────┘
 ┌──────────┐ ┌──────────┐ …            ← 2 cols, first price at ~200px
────────────────────────────────────
 TRAY: identical to Command's buy tray (same component, same `issue`)
```
Town face = rows: `Tax 3 %`, `Port's cut 2 %`, `Draft 5`, then building rows `Warehouse · tier 5 ›`. Culture appears only as a `Note` on a refused good. Inn/Yard/Craft faces are `Tile` grids with one figure each and a tray for the act.

### MARKET
*(Superseded 2026-09-11: the fold the last line of this section recommends was taken — MARKET is PORT's Trade face with the port field under the faces, one row per good (`TradeRow`), and a quay with nobody alongside opens the read-only `PriceTray`. Owner row 76, `docs/QUAY_LEDGER.md`. The sketch below is kept as the record of what was folded.)*

Its job after row 64/70 (`docs/OWNER_REQUESTS.md`): read prices somewhere else. Stays: port choice, the grid, range + trend. Cut: the control card, sort/filter chips, "Tap a good…", the footer line, the how-to-read card, 238 chips. Folded: the port picker is a `Field` at the top with the nearest ten as chips under it while typing.

```
════════════════════════════════════
 Prices                              
 [🔍 Lisbon ▾]  Porto · Cádiz · Seville ← field + nearest by sea
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
 ┌──────────┐ ┌──────────┐
 │ ✦ Aniseed│ │ ✦ Pepper │
 │ 78 · 72  │ │149 · 137 │
 │ 62▔╱╲▔94 │ │113▔╱╲170 │              ← range Bar with trend
 └──────────┘ └──────────┘
 (tap → tray: 30-day trend, range, stock; [Sail here] if not docked)
```
If the owner later folds Market into Port's Trade face with a port field (the tile is the same component), the tab is freed; recommended, not required.

### FLEETS
Stays: list, detail, stores, cargo, standing orders. Cut: header counts, roster/table duplicate, "Standing orders" card, fitted paragraphs, slots line, galley `dl`, footer read-age. Folded: detail into a tray from the row; ships as tiles; cargo as rows with a trailing Sell chevron.

```
════════════════════════════════════
 Fleets
 ▲ Gaivota      Lisbon         ›      ← Row: status mark, name, where/ETA
   15 d · 4 / 60 t · hull ▔▔▔▔▔       ← one t-caption line of Bars
 • Andorinha    → Cádiz · 1.2 d ›
────────────────────────────────────
 TRAY (half → full): Gaivota
 [Ships ◆][Cargo][Stores]             ← Segmented
 ┌──────────┐ ┌──────────┐
 │ ⚑ Gaivota│ │  Second  │            ← ship Tile: hull Bar, crew, hold
 │ Barca    │ │  Carrack │
 │ ▔▔▔▔ 100%│ │ ▔▔▔  70% │
 │ 12/12·60t│ │ 30/40·120│
 └──────────┘ └──────────┘
 Stores:  Water 8 t   Food 6 t   Keep 15 d [−][+]   ← the standing order
```

### MAP
Already closest. Keep the chart, the corner controls, the minimap (only when zoomed past the world frame). Cut: caption bar, the hint sentence, `KEEP & SEND` label. Fold: the Fleets panel to a pill `⛵ 1` that opens a `Corner` list; the detail panel becomes a `Tray` (peek shows name + one line; half shows Send).

```
 ⛵ 1                          + − ⌖   ← corners only
                 (chart)
 ▣ minimap                             ← bottom-left, only when zoomed
════════════════════════════════════
 TRAY peek:  Cádiz · Spain · 254 nm    [Send fleet]
 TRAY half:  Gaivota · Lisbon · 1.9 d · stores ✓
             Keep 15 d  [−] ▔▔▔▔▔▔ [+]
             [          Send Gaivota          ]
```

### LEDGER
Rows, not cards. Cut: filter card, per-row second timestamp, balance, purse footer. Fold: a `Segmented` `All · Trade · Voyage · Crew` in the sheet header; report lines behind a tap.

```
 Ledger        [All ◆][Trade][Voyage]
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
 10:38  Casa de Aveiro opens its books      +8,000
 10:41  Gaivota took 20 t aniseed at 78      −1,560
 10:42  Gaivota put to sea for Cádiz            ›   ← report in a tray
```

### RANK
One list, you pinned. Cut: House/Fame/Levels cards, the gauge, the limits. Fold: fame breakdown into a tray on your row.

```
 Standings                    settled 2 m
 ◆ 2  Casa de Aveiro          0   you  ← pinned, accent
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
   1  Casa do Cais   Portugal    28
  =2  Casa Almacen   Portugal     0
```

### CODEX
Cut: the paragraph, the two chip strips, the count, dash figures, unread stats. Fold: one filter field + one `Segmented` (Goods · Ships · Captains · Nations); category as a t-label heading; tile shows mark, name, rarity, **one** figure (base); everything else in a tray. Ships: hold · speed · crew only. Captains: specialty + bonus only; the "no rule reads this" ones are muted with the reason in the tray. Nations: rows.

### PROFILE (in Cabin)
```
 Casa de Aveiro · Portugal · since 9 Sep
 Trading     ▔▔▔▔▔▔▔▔▔▔ 1
 Exploration ▔▔▔▔▔▔▔▔▔▔ 1               ← levels live here, as Bars
 Appearance  [Dark ◆][Light][Auto]
 [Sign out]
```
`This world` and `Not in the game yet` are deleted; the mode/phase/compression go to `console.info` at boot, where they already are (`supabase.ts`).

### Shell
TopBar becomes a 32-px status strip: purse `Figure` on the right, the market countdown on the left when on a trade screen, nothing else — no wordmark, no dot. `RebuildNotice` becomes one `Note`: `The world was rebuilt from the first migration. [OK]`. The Nav keeps six cells; labels drop uppercase; Cabin opens a `Tray` of four rows.

## 7. Migration order — never half-redesigned in an ugly way

The trick is that tokens and primitives can land under the old screens without changing their layout, and each screen is then swapped whole. The app is never a mix of two skins on one screen.

1. **Tokens (one PR, visual only).** Rewrite `src/index.css` `@theme`: the palette in §4.4 (both schemes), the type scale as `--text-*` tokens, spacing, radius, shadows; delete MATERIAL, `.bv-cut`, `.bv-brass`, `.bv-panel-head`, `--font-serif`; map the old utility names (`bg-panel`, `border-edge`, `text-ink-faint`…) onto the new tokens so nothing breaks. Result: the same layouts, flat and quiet. Ship this first because it de-ages every screen at once and costs nothing structurally.
2. **Primitives (one PR per two primitives, no screen changes).** `Sheet`, `Tray`, `Corner`, `Row`, `Figure`, `Tile`, `Bar`, `Chip/Segmented`, `Button`, `Field/Stepper`, `Note`, `Hint`, `Nav`. Each with a Playwright geometry check (52-px row, 44-px targets, tray detents at 96/50 %/100 %). Old primitives stay exported and are marked deprecated in `components/ui/index.ts`; `tests/duplication.spec.ts` gains the two new bans (§5).
3. **Shell.** TopBar → status strip, Nav restyle, RebuildNotice → Note. Small, visible everywhere, proves the tokens.
4. **PORT** — the owner's current attention (rows 53/56/63) and the home of the trade tile + buy tray. Building the tray here settles the "press moves nothing" question for every later screen (`tests/layout.spec.ts:355-437` keeps its `good-pick-tile` ids, its 44-px cells, its `none aboard` text, and its "nothing above the press moved" assertion, which a tray satisfies trivially).
5. **COMMAND** — reuses Port's tile and tray; adds verb tiles, the SAIL chart-first layout, the queue tray. The largest deletion (`OrderComposer` 855 → ~200, `FleetRail`, `PreviewPanel`, `HaggleBlock` collapse into tray rows).
6. **MARKET** — same tile, read-only, port field. Decide the fold-into-Port question with the owner here, once both look the same.
7. **FLEETS** — rows + detail tray; the last table dies with it.
8. **MAP** — chrome only: pill, Corner, Tray; the chart layer is untouched.
9. **LEDGER, RANK, CODEX, PROFILE** — each a single day; Codex last because it is the largest data face and the least played.
10. **Delete.** Remove every deprecated primitive, `typography.ts`, `tableLayout.ts`, `scrollAffordance.ts`, `useClipped.ts`, `tileLayout.ts`, `inRows.ts`, `useTileCols.ts`, `overlayLayout.ts`, `screenLayout.ts`, `Table.tsx`, the `Explain*` trio, the `Collapsible*` pair; retarget `tests/layout.spec.ts` from tables to rows/tiles (the non-vacuity floor at `:169-174` already counts tiles and nav links, so the guard survives); delete `docs/UI_DIRECTION.md` §2 and §4 rules 1–3 and 6's "brass" reading and replace them with this document.

Two owner rules this direction touches, stated so they can be confirmed rather than assumed:
* *"unfold under the press … don't restructure anything"* (rows 6, 15, 25, 28, 45) — the tray keeps the second half absolutely (nothing on the grid ever moves) and changes the first half from *inline under the row* to *docked at the bottom edge*. That is what the corners-not-centre and chrome-hides-until-summoned rules ask for, and it is the only way to delete the row arithmetic. If the owner wants the inline fold kept, `Tray` gets an `inline` mode and the grid keeps `inRows` — everything else in this plan stands.
* *"make a gauge … the gauge max will be the stock"* (row 63) — kept exactly: the `Stepper`'s slider spans stock, with the server's capacity as a tick and the clamp point.

---

Files that carry the evidence, absolute:
`C:\Users\디폴리스\byeharu-voyage\src\index.css` · `src\app\{AppShell,TopBar,NavBar,navTabs,RebuildNotice}.tsx` · `src\components\ui\*` · `src\features\command\{CommandScreen,OrderComposer,FleetRail,ArgPickers,OrderQueue,PreviewPanel,HaggleBlock}.tsx` · `src\components\ui\tradePickers.tsx` · `src\features\port\{PortScreen,PortTrade,PortFair,PortFaces,PortInn,PortWarehouse,PortWorkstation,PortYard}.tsx` · `src\features\market\{MarketScreen.tsx,marketRows.ts}` · `src\features\fleets\FleetsScreen.tsx` · `src\features\map\{MapScreen,DetailPanel,FleetsPanel,MapPanel,SendFleet,WatersAhead}.tsx` · `src\features\ledger\LedgerScreen.tsx` · `src\features\rank\RankScreen.tsx` · `src\features\compendium\CompendiumScreen.tsx` · `src\features\profile\ProfileScreen.tsx` · `src\live\worldStore.ts` · `tests\layout.spec.ts`.
Screenshots used: `C:\Users\디폴리스\AppData\Local\Temp\claude\C--Users-----\256845d3-4148-4952-8da3-b9c582cd78d0\scratchpad\shots\*.png` (63 files).
