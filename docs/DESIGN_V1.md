# DESIGN V1 — the systems the owner asked for, as ONE system

**Written 2026-09-01, DESIGN ONLY. Nothing here is built and no migration exists.**

This answers `docs/OWNER_REQUESTS.md` rows **57–70** together, because they are not thirteen
features. They are one economy with one spine:

```
    goods ──▶ storage ──▶ workstation ──▶ fittings ──┐
      │                                              ├──▶ 건조소 ──▶ hulls
      │                                     timber ──┘
      │
      └──▶ trade ──▶ levels ──▶ captain promotion ──▶ cabins ──▶ ship performance
```

Built as thirteen separate things the seams will not meet: two agents would mint two item tables,
two definitions of "a building", and two answers to "what bonus does this fleet have". The order in
§12 exists for that reason.

---

## 1. THE STAT MODEL

The owner: *"there should be also defense, speed, etc. and items should have speed related stats,
attack, accuracy, range, etc… make more stats that are related to the game."*

### 1.1 What exists today

`public.ship_classes` carries `hold`, `crew_required`, `crew_max`, `speed_kn`, `durability`,
`guns`, `draft`, `tier`, `family`, `rig`, `build_hours`, `build_cost`.

Two of those are dead: **`guns` is a count no rule reads** (combat is unbuilt, migration 0035), and
**`build_hours`/`build_cost` have carried real values since 0002 and are read by nothing**.
`durability` is the only survivability figure and REPAIR restores it.

### 1.2 The ten ship stats

Three of the four roles the owner named (trading, exploration, combat-long, combat-close) must each
have stats that are *theirs*, or roles are cosmetic.

| stat | unit | what it decides | role it serves |
|---|---|---|---|
| **Hold** | tuns | cargo, and stores share it | trading |
| **Speed** | knots | passage time; already the mover's input | exploration |
| **Handling** | 0–100 | how tightly she answers the helm — course efficiency at sea, position in a fight | all |
| **Draft** | 1–6 | which harbours she may enter — exists | all |
| **Durability** | points | hull integrity; what REPAIR restores — exists | combat |
| **Armour** | 0–100 | share of incoming damage the hull turns | combat |
| **Attack** | points | damage a broadside deals | combat |
| **Accuracy** | 0–100 | chance a shot tells, falling with range | combat-long |
| **Reach** | 0–100 | the band she fights at: low = boarding, high = gunnery | combat split |
| **Sighting** | nm | how far she raises a sail or a coast | exploration |

`guns` stops being a stat and becomes what it always was: **the number of mounts a hull has**, i.e.
how many gun fittings she can carry. That retires a dead column into a real one.

### 1.3 The rule that makes this a design and not a shopping list

> **Every fitting buys one stat and spends another.**

Without it, "design your own ship" means "fit everything", and the best ship is the one with the
most slots. With it, a hull is a set of choices the player defends.

### 1.4 The twelve fittings

선수상 = **figurehead**. Each entry: what it buys, what it spends.

| # | fitting | buys | spends |
|---|---|---|---|
| 1 | **Suit of sails** | Speed | Handling |
| 2 | **Bowsprit & jib** | Handling, a little Speed | Durability (more to carry away) |
| 3 | **Rudder & helm** | Handling | Hold (the gear takes room aft) |
| 4 | **Anchor & cable** | Weather-holding; faster turnaround in port | Hold |
| 5 | **Ballast** | Handling, Armour | Speed |
| 6 | **Copper sheathing** | Armour, Durability | Speed |
| 7 | **Broadside guns** | Attack, Reach | Hold, Handling |
| 8 | **Boarding gear** | Attack at low Reach | Reach (pulls her toward the close band) |
| 9 | **Powder magazine** | Attack sustain, Accuracy | Hold, Durability (it can go up) |
| 10 | **Crow's nest** | Sighting | Handling (weight aloft) |
| 11 | **Hold fittings** | Hold | Speed, Handling |
| 12 | **Figurehead** | Crew morale → effective crew; fame | ducats only |

The figurehead is the one that spends nothing but money, deliberately: it is the flourish a player
buys because they want to, and every catalogue needs one.

### 1.5 Slots by tier

The owner: *"for tier 1, sail, weapon, anchor would do. and 3 captain slot. it will grow."*

| tier | fitting slots | of which weapon mounts | cabins |
|---|---|---|---|
| 1 | 3 — sail, weapon, anchor | 1 | 3 |
| 2 | 5 | 2 | 4 |
| 3 | 7 | 3 | 5 |

Slots are **typed** (a sail goes in a rig slot), so a tier-3 hull is not simply "more of anything".

---

## 2. THE GOODS TAXONOMY

The owner, on the seven categories: *"wtf is foodstuff? … liqure, meat etc. tobacco, etc."*

They are right. Measured: `raw` holds **82** goods — dyes, medicines, gunpowder stock, hides,
livestock (including war elephants), timber and stone. `foodstuff` holds **48** — grain, all the
liquor, all the stimulants, salt meat, oils, fruit and Cantonese delicacies — while **tobacco sits
in `raw`**. `luxury` holds **41**, mixing gems, porcelain, aromatics, books, paintings, sword
blades and live parrots.

### 2.1 Seventeen categories, in plain words

The owner, on the first draft: *"where is liquir? indulgences? dyestuff? use simpler category i
mean come on!"* — right on both counts. "Indulgences" and "Dyestuff" were a thesaurus talking, and
liquor was buried inside a word nobody says.

| category | what goes in it |
|---|---|
| **Grain** | wheat, rice, rye, barley, maize, cassava flour |
| **Food** | salt meat, cheese, butter, herring, dried fish, ghee, oils, fruit, nuts |
| **Drink** | wine, beer, **vodka**, rum, brandy, sake, arrack, coffee, tea, cacao |
| **Tobacco** | tobacco and its makes |
| **Spice** | pepper, cloves, cinnamon, nutmeg, cumin |
| **Medicine** | senna, Chinese rhubarb, Jesuit's bark, jalap, opium, bezoar |
| **Dye** | indigo, cochineal, brazilwood, woad, madder, safflower |
| **Cloth** | silk, linen, calico, broadcloth, says & serges, raw cotton, raw wool |
| **Metal** | iron, copper, tin, silver, quicksilver, saltpetre, sulphur |
| **Gems** | diamonds, rubies, emeralds, pearls, amber, lapis |
| **Crafts** | porcelain, lacquerware, glassware, majolica, celadon |
| **Weapons** | sword blades, boarding gear |
| **Guns** | firearms — the crafted class the owner named |
| **Ship supplies** | timber, pitch, tar, hemp, canvas, cordage |
| **Art** | paintings, sea charts & globes, clocks & instruments |
| **Books** | printed books, paper, ink & brushes |
| **Animals** | horses, war elephants, gyrfalcons, parrots |

Every name is a word a player would say out loud, which is the owner's standing rule: labels are
NAMES, not vocabulary.

**Trading captains specialise on exactly this axis** (§7), which is why the taxonomy has to land
first: a "Provisions trader" is a real merchant; a "foodstuff trader" is three merchants wearing
one coat.

### 2.2 How it lands

`category` lives in `data/goods.json` and is compared field-for-field by
`scripts/db/world-guard.mjs`. So a re-categorisation is: edit the data, ship a migration that moves
the applied world to match, and the guard proves both directions. No new machinery.

---

## 3. THE CATALOGUE, AND THE 1–3 RULE

The owner: *"each trade goods should be distributed to only 1~3 cities, meaning that 4 cities
cannot have a same trade goods."*

### 3.1 The arithmetic, measured

| | |
|---|---|
| Offers the rosters need | **1,288** — capitals 350, mid 498, small 440 |
| Ceiling at 243 goods, ≤3 cities each | **729** |
| Goods needed, strict | **430** (+187) |
| Goods needed, band-1 bulk exempt | **361** (+118) |

Today **160 goods already comply**; **83 break the rule**, led by Salt 53, Dried & Salt Fish 50,
Hides 45, Timber 39, Wheat 37, Wine 35.

### 3.2 The ruling — STRICT, decided by the owner

*"strict 1-3 cities, make more trade goods."* No staple exemption. **Every good, including salt,
sits in one to three cities.** The catalogue grows to **430** (+187), asserted per good by the
migration that lands it.

**What the new goods are, from the owner's own list:**

- **Drinks** — wine, beer, **vodka**, and the rest of the still-room
- **Tobacco** — and its makes
- **Named fish** — salmon, tuna, cod, herring: a catch is a place, and "dried & salt fish" in fifty
  ports was one of the worst offenders
- **Regional goods** — soy sauce, **chilli paste**, which is row 38's gochujang finally arriving

Naming the fish is the pattern for all 187: **one generic good in fifty ports becomes several
specific goods in three ports each**, which is the rule and the flavour arriving together.

### 3.3 What it does to the game

It is the strongest single change in this document. At ≤3 cities a good, **every cargo worth
carrying is a place you have to go**, which is row 48's stated purpose — *"there should be a
purpose to go to a city that is far away"* — enforced by arithmetic instead of hoped for.

---

## 3A. DEMAND — where a good is WANTED

The owner, and this is the largest single change in the document:

> *"you can sell at any port you like, longer or trade goods that are needed in that region/
> country will be sold higher. For example tobacco from america (cigarette etc) will be very
> popular in India since they like to smoke. no need to give info on where to sell. The
> information gaining will be part of the game for the future."*

### 3A.1 What the game has, and what it lacks

Price today is **supply-side only**: `affinity` is distance to the nearest producer, so a good is
cheap where it is made and dear where it is not. That gives a gradient, but it is a gradient of
**scarcity**, not of **appetite** — every port wants every good equally.

There is no demand term anywhere in `world.mid_price`.

### 3A.2 The model

**A region wants what it wants.** Demand is a multiplier on the sell price, keyed on
(good category or good, region or culture), authored like every other world fact and guarded like
every other world fact.

- Tobacco pays in India because India smokes — a **category × region** fact.
- Some are finer: a specific good in a specific place. The authority allows both, most rows are
  categories, and the exceptions are hand-written, exactly as 0062's entrepôts are.
- **Distance still pays**, unchanged. Demand multiplies it; it does not replace it. A wanted good
  carried far is the best trade in the game, which is the sentence the whole economy should make
  true.

### 3A.3 The rule that makes it a game and not a table

> **The game never says where a good is wanted.**

*"no need to give info on where to sell. The information gaining will be part of the game."*

This is row 55 — *the game is to challenge players for finding the best prices by themselves* —
given a **positive** form. Until now that law only ever deleted things: the best-bargain row, and
next the NEARBY column, `pays at`, and `Where to sail`. Demand gives the player something to
**discover** in the space those deletions leave. Without it, removing the hints just makes the game
quieter; with it, removing them makes the game a game.

**So: no demand map, no "wanted here" badge, no sort-by-demand.** The player learns that Indian
ports pay for tobacco by carrying tobacco to an Indian port, and then remembers. That memory is the
progression, and it is the only progression in this design that lives in the player rather than in
a table.

### 3A.4 What it must not break

- **Prices stay bounded.** §10's −20%…+20% band is the *drift*; demand is a separate, static
  multiplier on top, or the two random-walk together and no price means anything.
- **Demand is authored, never derived from player behaviour.** A demand that responds to what
  players carry is a feedback loop, and a feedback loop in a market is a farm.
- **It must survive the read being the catch-up.** Demand is a fact about the world, not an event,
  so it costs nothing at settle time.

---

## 4. BUILDINGS, AS A CONCEPT

The owner: *"buildings are market, a workstation where you can create ship related items - sail
etc. inn where you can hire crew, find captains. etc. it is a concept."*

### 4.1 Why a concept and not four columns

Today a facility is a boolean on the port plus a hard-coded screen: `has_yard` gates REPAIR,
`has_academy` gates study. Adding storage, workstation, 건조소 and Inn that way is four more
columns, four more faces, and PORT grows back to the six tabs rows 53/56 just cut to two.

### 4.2 The shape

A building is a **row**, not a column: `(port, kind, tier)`.

- **Adding a seventh building is a row**, not a migration that re-cuts every screen.
- **One PORT surface** lists what this city keeps and opens the one pressed. Bilbao shows Bilbao's;
  a small harbour shows fewer. The tab strip stops growing — which is what row 56 was about.
- **Each building keeps its own behaviour.** The Inn hires, the yard builds, the warehouse stores.
  The shared part is only *where it is, whether this city has it, and how you reach it*.
- **`tier` is already the precedent** — `ports.yard_tier` exists (0–5) and is read by nothing. A
  building's tier is where *"some cities can craft"* lives: a city crafts because its workstation is
  good enough, not because a list names it.

### 4.3 The six kinds

| kind | what it does | exists today? |
|---|---|---|
| **Market** | buy and sell — row 53, already built as a PORT face | yes |
| **Warehouse** | per-city storage — row 57 | no |
| **Workstation** | makes fittings from goods — rows 68/69 | no |
| **건조소 / Building yard** | builds hulls from timber + fittings — row 58 | no |
| **Inn** | hires crew; captains appear here — row 60 | half (HIRE works) |
| **Shipyard** | repairs — exists, keeps its name | yes |
| **Academy** | studies skills — exists | yes |

**On the name:** the owner once asked *"what is yard?"* and a migration renamed everything to
**shipyard**, which today means *repair*. 건조소 is a different building. Repair keeps
**shipyard**; the new one is **the building yard**. Two buildings may not share one word.

---

## 5. STORAGE

Row 57, and the owner has legislated this before in their other game:
*items have VOLUME and a LOCATION; storage is PER-PORT; reachable only while DOCKED there.*

### 5.1 The laws

1. **A warehouse is per (player, port).** No global stash. Reachable only while docked there.
2. **It holds units, and units cost volume**, folded by `goods.bulk` exactly as a hold is — one
   volume model, not two.
3. **It is capped**, and its cap is its building tier. This is what investment already promises to
   buy (`CORE_REUSE.md` lists "warehouse capacity" as a purchasable).
4. **Moving goods composes `fleet_load`/`fleet_unload`**, the one cargo mover. Nothing here writes
   `ships.cargo` itself.
5. **It may hold what the city does not trade.** 0061 gates BUY, never SELL, precisely so a hold is
   never stranded; a warehouse inherits that.

### 5.2 Storage costs nothing to keep

`DESIGN.md` §F.2 proposed 0.5 d./tun/game-day rent and 1 d./tun handling, and an earlier draft of
this document put those figures in front of the owner as though they were theirs. They were not.

> *"wtf is warehoure's rent? i didn't say anything about this. remove"*

**Removed. A warehouse costs nothing to keep.** The cap on it is its building tier, which is a
limit on *space*, not a tax on time — and a per-day charge would also mean a player who stops
playing comes back poorer, which no rule in this game does today.

### 5.3 The disk question, answered

Row 57 flagged that a per-(player, port, good) table is the shape that filled production's disk.
It is not: `price_history` was **dense** — every port × every good × every slot, 7.3 M rows by
construction. A warehouse is **sparse**: one row per thing actually stored. The existing
per-(player, port, good) tables, `trade_daily` and `haggle_daily`, are the same shape and are tiny.

---

## 6. THE WORKSTATION, ITEMS, AND THE 건조소

### 6.1 The chain, which answers row 58's open question

Row 58 asked for ships to cost *"some items"* and could not say where items come from. The owner's
workstation answers it:

```
trade goods ──▶ WORKSTATION ──▶ fittings (§1.4) ──▶ 건조소 ──▶ hull
```

**The items are the fittings.** That gives the item system a native source that is not a random
drop, and it answers *"what stops items being farmed"*: you farm them by trading, which is the game.

### 6.2 What an item is

The game has **no table where a player owns N of a discrete thing** — ducats, cargo, crew and
stores are all continuous. An item table is genuinely new. It sits beside two existing shapes:
`player_officers` (own a row) and `player_skills` (own a level).

An item is **owned, countable, stored in a warehouse, and consumed by a build**. Fittings *mounted
on a ship* leave the inventory and become part of that hull.

### 6.3 Crafting

The owner: *"a special trade goods will be able to be made using trading trade goods (2~5 trade
goods)"* and *"could be trade goods from three separate cities that are far away."*

- **A recipe is 2–5 inputs → 1 output**, authored in `data/` and guarded, never migration-only:
  the world-guard has no notion of a recipe, and an unguarded recipe is exactly the drift the
  guard exists to kill.
- **A recipe must refuse a dead ingredient.** The owner's other game lost two hulls to recipes
  whose inputs had no live source; this game had three goods buyable nowhere until 0062 caught it.
  The migration asserts every input is offered somewhere.
- **The ≤3-cities rule does the work.** Guns from three inputs each sold in at most three cities
  *is* a voyage. The distribution rule and the recipe design are the same idea.

### 6.4 The crafted good is a producer

**The decision that settles four collisions at once.** A crafted good with no natural producer:

- prices **identically at all 224 ports** — affinity is distance-to-nearest-producer, and with no
  producer every port falls back to maximum distance, so the price gradient dies;
- is permanently **exotic**, because rarity is producers-per-good;
- breaks 0062's *every good is buyable at a producer* assert;
- has **no roster slot**, since capitals hold exactly 10 and small ports exactly 4.

**So the crafting city is declared a producer of what it crafts.** The good gains that city's
region as an origin, prices radiate from it, rarity means something, the assert holds, and it takes
a roster slot at those cities — deliberately.

---

## 7. CAPTAINS

Rows 61 and 66.

### 7.1 Rank

**S 5 slots / 10 skills · A 4/8 · B 3/6 · C 2/4.** Slots are the loadout; skills are what she
knows. A captain **knows** up to N and **carries** M at once.

*"for now"* on the rank list means the ladder is **data, not four letters** — a rank above S must
cost a row, not a migration that re-cuts every function.

### 7.2 Role and specialisation

| role | specialisation | what it moves |
|---|---|---|
| **Trading** | one of the sixteen categories (§2) | price, spread, daily cap on that category |
| **Exploration** | — | speed, sighting, endurance |
| **Combat — long** | gunnery | attack, accuracy, reach |
| **Combat — close** | boarding | attack at low reach, crew losses |

This **supersedes** `officers.specialty`, which is four ship-board jobs — navigator, quartermaster,
surgeon, purser — each wired to one live rule. Role-plus-specialisation is a different axis, and the
owner has ruled: **the four jobs become skills a captain may know**, not the captain's identity.
Replacing them silently would break speed, hold, spread and crew-losses at once.

The owner also widened two of them, and the second is a new mechanic:

> *"navigator could be increasing speed, or make wheather more fable etc, surgeon could be a healer
> where captains may be homesick even crews"*

- **Navigator** — speed, *or kinder weather*. Once climate exists (§9), a navigator shortens the
  passage by finding the better wind rather than by multiplying a number.
- **Surgeon** — a healer, and what she heals is **morale**. Captains and crew may become
  **homesick**: a long voyage far from home wears on them. That is a figure the game does not have
  today, and it gives the surgeon something to do outside a fight — which matters, because fights
  do not exist yet.

**Homesickness is the one genuinely new mechanic in this section.** It wants: a home for each
person (captains already carry `nation_id` and `home_port_id`), a distance-and-time measure the
voyage already produces, and an effect that is felt but not fatal. It must be *derived*, like
everything else that moves on its own, or it becomes a counter to farm.

### 7.3 Cabins, and the collision

Cabins are **per ship**. Captains are posted to a **fleet** today, and `fleet_officer_bonus` folds
them per fleet for four live rules. Moving captains into cabins **supersedes** that fold — the
per-ship reading becomes the authority and the fleet-level one is retired, never kept beside it.

### 7.4 Where captains come from

The owner: *"country of origin… randomly appear in inn (not 100%, S tear especially) on their
country land, or related fields."*

`officers` already carries `nation_id` and `home_port_id`.

**The hard rule: who is in an inn must be a pure function of (port, day, world secret).** This game
settles voyages while the player sleeps because every random thing is `immutable` — Postgres itself
forbids it reading the clock. A captain who is *rolled and stored* can be re-rolled by refreshing
until an S appears. Derived, they cannot.

Weighting, and the owner's answer to *"what is a related field"* was **all of them**: highest in
her own **nation's** ports, then the same **region**, then the same **culture**, lowest elsewhere.
S-tier rare everywhere — the owner's *"not 100%, S tear especially."*

---

## 8. LEVELS

Row 62. **Two of the three already exist.** `player_fame` computes trade fame from ledger turnover
(100 d. = 1 point) and exploration fame from distinct ports (25 each).

**The property to preserve above everything: nothing is granted.** Fame is *re-read from the
record* every time — there is no counter to inflate, only a history to recompute. A levels design
that wrote XP into a column would throw that away and hand the game its first farm loop.

| track | earned from | change from today |
|---|---|---|
| **Trading** | ledger turnover on completed buys and sells | none |
| **Exploration** | **distance sailed AND ports reached** — the owner: *"both"*. Both are already in the record | today counts ports only |
| **Combat** | combat that does not exist yet | reads **zero, honestly** |

Levels are the requirement captain promotion spends (§7.1), which is why rows 61 and 62 are one
system.

---

## 9. REGIONS, THE MAP, AND CLIMATE

Row 59. Much of this exists: 25 regions, every port in one, and 0062 gave every good
`origin_regions` and `entrepot_ports` — 1,241 native offers, 83 goods from exactly one region.

**The map splits on SEAS, not regions.** The world already carries two partitions — 51 seas for the
water, 25 regions for the land — and the sea is the one a ship is ever *in*. Seas already carry a
danger level and, since 0059, their own encounter mix. Splitting on regions would make a third
partition and put the split on the wrong side of the shoreline.

**Climate is row 43's unbuilt wind.** `wind_mult_v0` is pinned at 1.00. A region's weather and that
knob are the same thing, and the constraint that governs it is absolute: **wind must be a pure
function of (position, time, world secret)**, `immutable`, or offline settlement dies and the game
only advances while someone is watching.

---

## 10. THE MARKET

Row 64.

- **NEARBY goes.** It reports what neighbours charge, which is the answer the game exists to ask.
  This also decides row 55's two open questions: **`pays at`** and **`Where to sail`** are built on
  the same comparison and go with it.
- **What stays:** the goods, buy price, sell price, stock. **Price range behind the dot**, on press.
- **Prices move like a stock, bounded −20%…+20%.** The chain *already* has a bounded random walk —
  `port_goods.drift`, with `drift_sigma`/`drift_theta`, pinned on one authority by 0054. The band
  **supersedes** those knobs; it must not become a second mover.
- **Fifteen minutes.** `world.market()` already serves `clock.next_change_at` and COMMAND prints
  *"prices move in m:ss"*. The cadence knob moves; the clock stays.
- **Restock** means stock walks back toward `stock_target` at `production_rate` — which already
  exists — on the same fifteen-minute beat.

---

## 11. WHAT IS DELIBERATELY NOT DESIGNED HERE

- **Combat itself.** Rows 40/43 left it a seam on purpose, and migration 0035 says so: *"It adds no
  combat, no NPC, no exploration. A half-built combat system is worse than none."* This document
  gives combat its **stats** and its **captains** so that when it is built they are waiting — it
  does not build it.
- **NPCs and the contacts panel.** Same reason.
- **A thousand goods.** The catalogue grows to ≈430 because the 1–3 rule needs it, not because a
  bigger number is better.

---

## 12. THE ORDER, AND WHY IT CANNOT BE PARALLEL

The owner asked whether all of this could be built at once, in parallel. It cannot, and the reason
is the no-spaghetti law itself: parallel builders cannot make a *shared* decision, and §7B says
decide where a concept lives **before the second caller exists**. Items have two callers. Buildings
have four. Migrations are a linear chain.

**Stage 1 — foundations, one at a time. Each unblocks several leaves.**

1. **The taxonomy** — sixteen categories over the existing 243. Blocks captains and distribution.
2. **The catalogue** — grow to ≈430 and enforce 1–3 with staples exempt.
3. **Buildings** — the concept, plus moving Academy and Shipyard onto it.
4. **Items** — one table, kinds, one earn path (the workstation).
5. **Levels** — mostly a re-fold of `player_fame`, plus distance.

**Stage 2 — leaves, genuinely parallel, disjoint file domains, separate worktrees.**

Storage · Workstation · 건조소 · Inn · market simplification · ship stats and fittings content ·
regions and the map split.

**Stage 3 — last, because they depend on stage 2.**

Crafting recipes (needs storage + regions + the producer ruling) · captain ranks, roles and cabins
(needs items + levels + the Inn).

---

## 13. THE DECISIONS — ANSWERED 2026-09-01

All seven were put to the owner and all seven came back. Recorded as row 70.

| # | question | ruling |
|---|---|---|
| 1 | Are the categories right? | **Simpler names.** Seventeen plain words (§2.1). Liquor is **Drink**. |
| 2 | Strict 1–3, or staples exempt? | **Strict.** 430 goods, seeded from drinks, tobacco, named fish, regional goods (§3.2). |
| 3 | Does NEARBY's removal take `pays at` and `Where to sail`? | **Yes** — and §3A gives the player something to discover in their place. |
| 4 | Do the four ship-board jobs survive? | **Yes, as skills** — and navigator gains weather, surgeon gains **homesickness** (§7.2). |
| 5 | What is a captain's "related field"? | **All of them** — nation, region and culture (§7.4). |
| 6 | Exploration levels: distance or ports? | **Both** (§8). |
| 7 | Warehouse rent? | **Removed.** It was never the owner's (§5.2). |

**Nothing in this document is now waiting on a decision.** The order in §12 can begin.
