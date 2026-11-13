# SECOND SHIP: a second ship a new player can reach (design F8; owner rows 180, 305, 316)

**Status: design, 2026-11-12. Nothing built. Figures are from the local world image at chain 0353 (a probe company founded in memory), NOT from prod: prices there differ by live stock and tax.** This is the lead's condensed record of the designer's report; the builder of S1 re-measures before cutting.

## The finding

The earlier belief was wrong on three counts.

| Believed | Measured |
|---|---|
| A barca holds 60 t at 5 kn | Live: **180 t, 15 kn** (`hold_scale` 3, `speed_scale` 3). A new company has 176.8 t free. |
| The materials (~90 t) do not fit her hold | They do: the four hull goods weigh 89.6 t, with the parts' inputs 112.4 t. |
| The purse is the wall | A second barca costs about **24,000** of the starting 40,000 (labour 15,000, goods ~4,060, crew 800, port calls ~4,000 unverified). One good first trade earns ~15,900 in 8.5 real minutes. |

**The walls are information and distance.**
1. The yard names four sellers (timber Funchal 505 nm, nails La Rochelle 665, cordage Portsmouth 867, tar Bergen 1,517), but the two parts hide three more goods: **flax (nearest Riga, 2,101 nm), hemp (Naples, 1,270 nm), iron (Lisbon)**. The real errand is seven goods from six foreign ports: 7,812 nm as one tour (~45 real minutes), ~13,850 nm (~75 minutes) following the yard's rows one at a time.
2. Nothing says hull goods must be **stored** in the warehouse (`cmd.do_build` reads `player_storage` at the yard's port: the "build order held open" already exists, Lisbon 750 t, no fee), that parts are made from the **hold** (storing the tar first makes `MAKE` refuse), that the new ship has **no crew** (the fleet then refuses to sail, `E_CREW_SHORT`; `HIRE 8` costs 800), or that a full fleet refuses last (`E_FLEET_SHIP_MAX` after the whole errand).
3. The Build button is hidden until everything is there. No total, no weight, no "3 of 6 ready".

Other facts: merchants do not use the yard (they call `commission_ship` directly). 89 of 103 hulls need no parts; only barca, carlat, nau and 11 famous ships do. Reach is a limit per leg (1,700 nm for a new company). A ship is built at once. On prod 3 of 19 human companies hold 2 hulls.

## Options weighed

| Option | Verdict |
|---|---|
| (a) The yard's port sells the materials (`port_specialties` rows) | **No.** Breaks the owner's three-cities-a-good limit; moves rarity, prices and requests for everyone. |
| (b) A smaller recipe: the barca needs no parts | **Yes, as S2.** Human builders only; 89 hulls already have none. |
| (c) A build order the yard holds open | Already exists (the warehouse). **Show it, in S1.** |
| (d) A used hull for coin | **No.** Nothing exists; makes the yard a shop. |
| (e) A yard that plans the build | **Yes, S1.** |
| (f) The yard sells from the city's stock | **No** for the starter hull: a second ship at minute zero. |

## The path

| | Today | After S1 | After S1 + S2 |
|---|---|---|---|
| Goods to fetch | 7 (3 hidden) | 7, all named | 4 |
| Foreign ports | 6 | 6 | 4 (Funchal, La Rochelle, Portsmouth, Bergen) |
| Miles | 7,812 to 13,850 | 7,812, the tour shown | ~4,250 |
| Real time, no weather | 45 to 75 min | ~45 min | ~25 min |
| Coin | ~23,900 | the same | ~21,000 |
| Steps she must guess | store, make, crew, fleet full | none | none |

Funchal and back (1,010 nm, ~5 real minutes) fills line 1 of 4 while she trades; the northern loop (La Rochelle, Portsmouth, Bergen, home: ~3,270 nm, ~18 minutes) finishes it. It stays an achievement: half her purse, two voyages to four new countries, a leg close to her limit. Reputation: the build pays 100 (`rep_built`), the errand four first landfalls (100) and ~40 for miles; no rule changes.

### S1: the yard plans the build (one read re-cut + client; alters no rule of play)

- **Server:** `world.yard_sources(uuid, text)` (created 0349, never re-cut), three hunks, additive keys only: the `sold` CTE also sources a part's goods (union of `hull_recipe_goods` and `hull_recipe_items` ⋈ `item_recipes`) and keeps the port id; each good's row gains `qty`, `bulk`, `ask` (`world.price(port, good).ask`, STABLE); each part's row gains `inputs: [{code, good, qty, bulk, port, name, miles, ask}]`. Stays STABLE SECURITY DEFINER, `authenticated` only. Self-assert: the answer minus the new keys equals the pre-image's for all 103 classes at three yards; positive control at Lisbon: the barca's sails name flax at Riga 2,101 nm.
- **Client (`src/live/PortYard.tsx`, `dict/yard.ts`):** one button always there whose label is the next thing she can do (**Make parts** when a part's inputs are aboard, **Store** when needed hull goods are aboard, **Build** when all is there, else Build disabled with "Ready 2 / 6"); each line shows need / storage / aboard and, while short, the seller, miles, real minutes and cost; a part unfolds into its inputs; a totals row (cost, weight against the free hold: Fits / Too heavy); **Fleet full** said first; after the build **Hire crew · 8** with the press. A press moves nothing.
- **Words:** Ready {n} / {of} · 준비 {n} / {of}; Store · 입고; Make parts · 부품 제작; Total · 합계; Weight · 무게; Fits · 실림; Too heavy · 초과; Fleet full · 선단 가득; Hire crew · 선원 고용.
- **Proof:** a new company through the real doors: Funchal for timber, `BUILD` refuses `E_NO_TIMBER` until `STORE`; `MAKE` from the hold; `BUILD barca` pays 15,000 to Lisbon, Reputation +100; `SAIL` refuses `E_CREW_SHORT` until `HIRE 8`; a third `BUILD` refuses `E_FLEET_SHIP_MAX` with storage untouched.
- No 30-minute window (no rule moved); the read's time by hand after the deploy (0349 measured 65-73 ms on prod; hold under 250 ms).

### S2: the barca needs no parts (a recipe is a rule of play: its own window)

Delete the barca's two `hull_recipe_items` rows, rewrite its `hull_recipes.note`, `data/hulls.json` barca `items: []` (the world guard). No function touched; carlat, nau and the famous hulls keep their parts; parts players already hold stay usable. Touches owner row 58 ("some items"): done in its own measured window and reported; forward rollback re-inserts the rows.

### S3: the goal is on the first screen (client)

A second line on Trade's goal card while the company has one ship ("Second ship 1 / 4" · "두 번째 배 1 / 4"), a **Plan trip** press on the totals row that seeds the Map's route builder with the missing sellers, and the Fleets page's "Add a ship" tile opening the same sheet.

## Where the new ship goes

She joins the fleet that gave the order; a new company's limit is 2 ships a fleet, so the first second ship has a home with nothing lit. Measured after the build: 2 ships, free hold 357.8 t, purse 25,000, Reputation 100. A third ship is refused until Seamanship, bought room or a second fleet (F6).

## Found on the way, its own design (S4)

Sakai and Karachi (starting capitals) have no build yard; from the four Asian capitals a barca cannot be built in practice (nails 10,500+ nm, tar 11,300+ nm) and their own small hulls also need tar; Istanbul's nearest sources are past a single leg. Default: regional recipes, as the Indian hulls already have, after S2.

## Not verified

Prod prices, `restock_by_investment` on prod, port fees on a real sail, how long level I of a foreign hull skill takes, whether a hull can be scrapped.
