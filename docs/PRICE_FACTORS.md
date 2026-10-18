# PRICE FACTORS — what else moves a price, and where each factor lives in the one price

**Status: DESIGN, 2026-10-18; slice P1 LIVE (0185); P2 built in 0190** (faith tastes, `world.price_why`, the good
page's "Why this price"; not yet on prod). Every DEFAULT is listed in the table below for the owner to confirm.

**The owner, 2026-10-18, verbatim:**
- *"is there a way for the prices move on many different factors? like relationship with other countries,
  religion, merchants, any more ideas?"*
- *"research on your ideas on different games like uncharted origins, eve, runescape, and come up with a good
  idea then apply to this game"*

**The rule this doc keeps.** There is ONE price authority:
- `world.mid_terms` reads a market row's terms once, and `world.mid_from_terms` multiplies them into the
  market's middle price. Today that is base × affinity × demand × stock term × (1 + drift) × (1 + season) ×
  development discount, clamped by the band, × haul (0173).
- `world.quote_terms` / `world.quote_priced` add what one trader pays at that middle: the spread (her purser,
  her bargain), the tax and the city's bid factor (0169, 0174).

Every factor below is a multiplier or a term inside one of those two, never a second pricing path. Each says
whether it moves the **market price** (everyone sees the same number) or the **trader's quote** (per
company).

---

## Owner to confirm — every DEFAULT in this plan

| # | DEFAULT | Why | If you say no |
|---|---|---|---|
| **F1** | **Faith is per GOOD, not per category.** Coffee and wine are both "Drink", but an Islamic port wants coffee and refuses wine. | The existing taste table (0066) is per region × category, so it cannot say this. Origin and Online both price per good (§1.1). | Keep categories only and author more region rows. |
| **F2** | **Four faiths, from the culture each port already carries, with named exceptions:** Christian (latin, anglo, germanic, nordic), Islamic (islamic, swahili, malay), Hindu (indic), East Asian Buddhist (sinic, korean, japanese). Guinean and oceanic ports carry none. Exceptions by port: Ayutthaya, Hanoi and Hoi An are Buddhist; Manila and Cebu are Christian. | `ports.culture` already exists (0003, `scripts/lib/world-derive.mjs`). The Malay coast's trading cities (Malacca, Aceh, Banten, Demak, Ternate) were sultanates by 1550, but the `malay` token also covers Siam, Vietnam and the Spanish Philippines. | Name another mapping; it is one data file. |
| **F3** | **Faith tastes move the price by at most −40 % / +35 %** after their knob (`faith_demand_amplitude` 1.0, checked against proof 05's first-voyage band when P1 is built, as 0066 measured its own). | Origin's own cultural preference is 10/30/50 % (§1.1). The haul runs 1 to 600×, so a taste can turn a choice between two ports, never beat the distance. | A softer amplitude (0.5 halves every taste). |
| **F4** | **Relations between powers are a TARIFF on the trader's profit tax:** ally × 0.5, at peace × 1, rival × 1.5, at war × 2. The total stays at most `tariff_rate_max` 35 %. | UWO's tariffs differ by nation; Origin's allied ports charge none (§1.1). The profit tax is already per company (`world.tax_rate(p_port, p_player)`, 0147). | A turnover duty instead (a new quote term). |
| **F5** | **Relations are authored, not simulated, until the 10 great powers land.** One data file of stances between powers. | The great-powers redesign (`docs/GREAT_POWERS.md`, in flight) decides which powers exist. A war system is a later candidate (§7). | Wait for the redesign before any relation. |
| **F6** | **Influence keeps its built form (0147: half the profit tax for the holder's citizens) and adds an investor's spread shave**: your own company's rank among a city's givers takes 10 / 8 / 6 / 4 / 2 % off your spread. | UWO's investor ranks give exactly 10/8/6/4/2 % (§1.1). The citizen cut is a country's reward; the shave is the company's own. | Keep 0147 only. |
| **F7** | **A glut: a big sale leaves a mark that fades in about a day.** Selling more than half a market's depth in one day lowers that market's price further, by at most 30 %. | UWO crashes a category after a large sale; RuneScape and EVE have no crash but show volume (§1.2, §1.3). Today the stock refills in hours, so merchants' crowding is invisible. | Show crowding only (the volume line, §5) and leave the price alone. |
| **F8** | **"Why this price" is shown on the good page, term by term, for the city in focus.** | Row 137 reversed row 55: the desk serves every city's price. Showing why a price is what it is turns factors into something a player can read and use (EVE's market details, Origin's 시세 %). | Show only the total, as now. |

---

## 1. Research — how other trading games make a price move

Researched 2026-10-18 for the owner's second order. Facts are marked with their source; **not found** means
no source was found, never a guess. The earlier Uncharted Waters pass (`docs/research/UWO_TRADE_PRICES.md`,
for 0173's distance term) still stands; this pass adds what moves a price besides distance.

### 1.1 Uncharted Waters Origin (대항해시대 오리진) and Online (대항해시대 온라인)

**Origin — the market rate (시세) and its events.**
- A price is shown as a % of a base. 100 % "reflects nearby cities"; the recommended-buy list is goods at ≤ 90 %
  and the recommended-sell list goods at ≥ 110 %; a 7-day graph is shown. Official guide:
  https://guide.floor.line.games/UWO/en_US/detail/1167031329446900354 (KR:
  https://guide.floor.line.games/UWO/ko_KR/detail/1167031103747200277)
- Outside events the rate barely moves (90 – 110 %). Selling in volume pushes it down, buying pushes it up; no
  elasticity is published. https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보
- Six event kinds: 폭등 (one good up), 폭락 (one good down), 유행 (a category up), 과잉 (a category down),
  폭증 (an unpopular good up), 대유행 (a category up a lot). Events start on the hour, last 1 – 2 hours, and are
  shown on the world map (official guide above; namu above).
- **대유행 has a server-wide BUDGET**: each sale into the city takes the seller's profit out of it; the trend ends
  at 0 % budget or after an hour, then the rate falls to a random 100 – 125 %. Examples: Foods 299 – 319 %,
  Medicines 216 – 236 %. Each cause raises three categories, e.g. War → livestock, weapons, firearms;
  Extravagance → crafts, spices, perfumes (official guide above).
- Seasons: some goods carry a season mark (alcohol peaks in winter) (official guide, namu).

**Origin — tariffs, investment, culture.**
- A tariff applies to both buy and sell; buying in one foreign nation and selling in another pays twice.
  Reductions stack from a tax permit, national reputation, the admiral's title and expertise, never below 0 %
  (official guide above). The base tariff is 20 – 30 %; a nation's allied port charges its citizens none; the
  weekly mayor (the top investor) can move a nation's tariff −5 … +15 %; from 백작 up, the home-nation tariff is
  waived where you hold ≥ 10 % of the city's investment (namu; official notice
  https://uwo.floor.line.games/kr/bbsCmn/detail/1732533460119023930).
- A free or allied port goes to the nation with the most investment; home ports never flip; the top investor is
  mayor for a week (https://www.gameple.co.kr/news/articleView.html?idxno=203417).
- Culture: alcohol is not traded in Islamic culture, and alcohol and pork are fixed at 0 ducats in Islamic ports;
  some ports pay more for one good (England for tea) (official guide; namu). The cultural-sphere preference is
  10/30/50 % for basic goods since 2024-12 (`UWO_TRADE_PRICES.md` §1).
- Language level 5: 5 % off a buy, 5 % on a sale (namu).
- One open question: Origin's guide ties distance to adventure EXP, while namu and the 2024-12 notice tie it to the
  sale price. 0173 followed the notice (`UWO_TRADE_PRICES.md` §1).

**Online.**
- The rate changes every 20 minutes to an hour, in steps, faster the more is sold. A usual band is 60 – 130 %,
  with a crash floor near 50 % (https://www.inven.co.kr/board/dho/2597/147).
- **폭락**: selling too much of one of the 20 categories at one port drops the whole category to its floor. A port
  that already stocks the category (내성항) crashes less; players split sales into lots of 20 – 50 and
  deliberately crash a cheap category to protect a dear one (https://www.inven.co.kr/board/dho/2597/146;
  https://namu.wiki/w/대항해시대%20온라인/교역). Recovery time: **not found**.
- **Tariffs by nation rank**: about 14 % for the top three nations, 12 → 6 % for ranks 4 – 7; a Baron or a 10 %
  city share pays none in allied ports; **investor ranks 1 – 5 get 10 / 8 / 6 / 4 / 2 % off**; each step of
  friendliness is about 1 % off and bad relations raise it (Inven 2597/147 above).
- A quarterly boom event sells chosen categories at 300 – 350 % of their ceiling (namu 교역 above).

### 1.2 EVE Online

- Every region has its own order book of buy and sell orders, filled in part or whole; most trade happens at a
  few hubs (https://wiki.eveuniversity.org/Market). Jita holds ~687 T ISK of open orders, Amarr ~54 T; a hub
  charges a convenience premium and its margins are thin (https://wiki.eveuniversity.org/Trade_hubs).
- Hauling arbitrage: buy where a good is made or dumped, haul it to where it is short
  (https://wiki.eveuniversity.org/Trading).
- **Fees by skill and standing**: sales tax = 7.5 % × (1 − 0.11 × Accounting level), 3.37 % at level V. Broker
  fee = 3 % − 0.3 % × Broker Relations − 0.03 % × faction standing − 0.02 % × corporation standing, floor 1 %
  (https://wiki.eveuniversity.org/Trading). Standing with the station's owner lowers what you pay there.
- LP stores turn mission rewards into goods, a source that pushes those goods' prices down
  (https://wiki.eveuniversity.org/Loyalty_Points).
- **Supply shocks**: the 2020 "scarcity" changes to ore distribution moved the Mineral Price Index 68 → 112 in
  five months (https://www.eveonline.com/news/view/Q1%20Economy%20Review). War consumes: World War Bee 2 destroyed
  55 T ISK in January 2021 and mineral prices "continued to climb dramatically"
  (https://tagn.wordpress.com/2021/02/19/the-january-eve-online-economic-report-shows-destruction-and-mineral-prices-soaring/).
  Numbers for Jita during a blockade: **not found**.

### 1.3 RuneScape

- The Grand Exchange matches buy and sell offers; a buyer is refunded down to the lowest sell
  (https://oldschool.runescape.wiki/w/Grand_Exchange).
- **The guide price** is computed from recent trades and volume; it updates every 3 hours and moves at most 20 %
  an update (since 30 Sep 2026; it was 24 h and 5 %). Jagex sets prices by hand against manipulation "on an
  inexcusable scale" (same page; RS3: https://runescape.wiki/w/Grand_Exchange).
- **Buy limits**: a fixed quantity per item per 4 hours, from 8 (a Barrows set) to 50,000 (air runes), "to
  prevent price manipulation" (https://oldschool.runescape.wiki/w/Grand_Exchange/Buying_limits;
  https://oldschool.runescape.wiki/w/Flipping).
- **The GE tax as a sink**: 1 % from 2021, 2 % from 29 May 2025, capped at 5 M a trade; "well over half the
  taxed coins are drained" (https://oldschool.runescape.wiki/w/Grand_Exchange_tax).
- Flipping: profit is the spread between a pending buy and sell (Flipping page above).

### 1.4 Port Royale and Patrician (the closest age-of-sail sims)

- Port Royale 4: each town shows a demand bar; a full bar is a surplus and cheap, an empty one buys dear, and
  buying a town's stores down raises its price (https://www.thesixthaxis.com/?p=365980). A town of 6,500 needs
  ~650 fruit to fill two bars; trade licences cost 10,000 gold and rise with wealth
  (https://steamah.com/port-royale-4-soup-to-nuts-the-economy-guide/).
- Port Royale 3: consumption is per head per day × population (wheat 0.0027, cloth 0.00054); a "dynamic demand"
  option raises luxury demand only in prosperous towns
  (https://steamah.com/port-royale-3-goods-suply-formula-consuption-per-capita/).
- Patrician II/III (player-measured): the price tier follows stock against a week's consumption — under a week
  is the top price, two weeks the producer's; beer falls 62 → 41 across that range; **the sell price falls
  slowly while the buy price falls fast**; a siege raises food ~20 %
  (https://gog.com/forum/patrician_series/captain_trading_for_a_loss).
- Town-hall and reputation effects on price: **not found**.

### 1.5 Religion and culture in strategy games

- Victoria 3: **taboos** — "Pops with that religion purchase half as much of taboo goods" (Islam: liquor and
  wine; Hindu: meat) (https://vic3.paradoxwikis.com/Religion). **Obsessions** give a culture's favourite good
  double weight (English tea, French wine, Dutch coffee) (https://vic3.paradoxwikis.com/Culture).
- Europa Universalis IV: dated price events — "Protestants Don't Eat Fish" −10 % (1515), "Reformed and
  Protestant Rejection of Incense" −25 % (1530), coffee +50 % (1550); no wine in Muslim provinces
  (https://eu4.paradoxwikis.com/Trade_goods).

---

## 2. What we take, and what we leave

Our game prices every (port, good) with one server function; no player posts an order. So a mechanism is
taken only if it can be a term of that function.

| idea | from | taken? | why |
|---|---|---|---|
| A taste per faith and per GOOD, a taboo at about half | Victoria 3 (taboo 0.5×, obsession), EU4, Origin (alcohol and pork at 0 in Islamic ports) | **TAKEN — P1** (§3.1) | One stored column we already have (`demand`); zero cost per quote; the owner named religion. |
| "Why this price" — the price with its causes | Origin (% of base; buy ≤ 90 % / sell ≥ 110 % lists), RuneScape (guide price) | **TAKEN — P1** (§5) | Makes every factor legible; the desk already serves every city's price (row 137). |
| Tariffs by relation between powers | UWO (by nation rank; ~1 % a step of friendliness), Origin (allied ports free; foreign at both ends pays twice) | **TAKEN — P4** (§3.2) | The per-company tax authority exists (0147). Waits for the 10 powers. |
| Fees fall with your standing or stake | EVE (broker fee − standing), UWO (investor ranks 10/8/6/4/2 %) | **TAKEN — P3** (§3.3) | One precomputed rank per city; rewards giving (influence). |
| A dumped market crashes and recovers slowly; sales, not buys, cause it | UWO (폭락), Patrician (sell price falls slowly, buy fast) | **TAKEN — P5** (§3.4) | Merchants' crowding becomes felt. Costs a re-cut, so it comes later. |
| Daily volume shown beside the price | EVE, RuneScape | **TAKEN — P2** (§3.4) | Merchants' crowding becomes seen, cheaply. |
| A trend with a server-wide budget that sales drain | Origin (대유행) | **LATER** (§7) | The best multiplayer-safe trend: first movers win and the pie is bounded. Needs an event table. |
| Wars, plague and festivals raise named categories | Origin (War → weapons, firearms; Plague; Festival), EVE (war consumes), EU4 (dated events) | **LATER** (§7) | `season_mod` already carries a bounded event term. |
| A player order book, regional books, hubs | EVE, RuneScape | **NOT TAKEN** | Our market is the city's, priced by one function; an order book is a second price authority and needs a crowd we do not have (~17 players). |
| Buy limits per 4 hours | RuneScape | **NOT TAKEN** | Our stock term already limits a buy (each 10 t walks the price); a limit would be a refusal players cannot see coming. |
| A cap on the price change per update | RuneScape | **NOT TAKEN** | Our drift is clamped and the band bounds the swing (0056, 0173). |
| A trade tax as a money sink | RuneScape (2 %) | **NOTED** for the owner's open sink decision (0174) | We already tax profit per city; a sink is the owner's call, not this doc's. |
| Consumption per head of population | Port Royale, Patrician | **NOT NOW** | `stock_target` and production already set each city's depth; tying them to population is a world-data change of its own. |
| A supply index moved by a visible event | EVE (scarcity, the MPI) | **LATER** (harvest years, §7) | It moves production, and the price follows the stock. |

**New in this game (no source does it):** the faith taste multiplies the distance haul instead of replacing it,
so a far Islamic city pays a fortune for incense and very little for a long-hauled wine; and "why this price"
shows each term's own multiplier, with the haul's nautical miles.

---

## 3. The factors, one by one

### 3.1 ★ Faith and culture — "an Islamic city wants incense, not wine" [F1–F3]

**Grounding.**
- Origin prices a sale by its cultural sphere (문화권 우대 10/30/50 % for basic goods since 2024-12) and some
  goods by a named region: azulejo +60 % in Japan, Nishijin brocade +40 % in Iberia. Islamic ports fix alcohol
  and pork at 0 ducats (`docs/research/UWO_TRADE_PRICES.md` §1).
- History: Islam forbade wine but made coffee its own drink; the coffeehouses of Mecca, Cairo and Istanbul ran
  on Yemeni beans from the 1500s. Frankincense, aloeswood (oud), ambergris and rosewater were mosque and
  household perfumes. Dates break the Ramadan fast.
- Latin Christendom kept about 150 fast days a year, so salt fish (stockfish, bacalhau, herring) was a staple.
  Churches burned beeswax candles (tallow was forbidden at the altar) and frankincense, and the Mass needed
  wine.
- Hindu worship burns camphor (aarti) and sandalwood; ghee feeds the lamps and the offerings.
- East Asian Buddhist temples burn aloeswood, sandalwood and benzoin, and copy sutras.

**What exists today, and why it is not enough.**
- `goods.culture_mask` (0080, `public.culture_refuses`) REFUSES a good outright: 6 goods in Islamic and
  Swahili ports, beef in Indic and Japanese ports.
- `world.region_demand` (0066, `data/demand.json`, 80 rows) is per region × CATEGORY. Its "drink" row makes an
  Arabian port pay 0.72 for every drink — including coffee, the one drink Islam loved.

**The term.** It enters the price as part of the existing `port_goods.demand` column, so no function that
prices moves:

    demand(port, good) = region_part(port.region, good.category) × faith_part(port.faith, good)
    region_part = 1 + (region_demand.multiplier − 1) × demand_amplitude          (0066, unchanged)
    faith_part  = 1 + (faith_demand.multiplier  − 1) × faith_demand_amplitude    (new)

`world.demand_for(port, good)` is the one derivation (0066). It gains the second factor; `port_goods.demand` is
re-derived from it. **Market price, everyone.**

**Data.**
- `data/faiths.json` — the four faiths, culture → faith, and the port exceptions, each defended in a line.
- `data/faith-demand.json` — rows of (faith, good id, multiplier, why), authored by hand like 0066's
  appetites, because a seeded number can invent a taste but it cannot mean one.
- Tables `public.faiths` (code, name), `public.culture_faith` (culture → faith), `public.port_faith_override`
  (port → faith), `world.faith_demand` (faith, good, multiplier, why); one reader `public.port_faith(port)`.
  The world guard compares the tables with the data, and every market row's `demand` with `world.demand_for`.

**Size.** Authored multipliers are bounded 0.60 – 1.35 by a CHECK, after the knob at most −40 % / +35 %. With
the region part (0.92 – 1.14 today) the whole taste stays within 0.55 – 1.55: it chooses between two ports at
the same distance and never turns a short haul into a long one.

**Cost.** None at quote time: the multiplier is folded into the stored `demand` column. The re-derive runs only
when the migration lands or a knob changes (one UPDATE of every market row).

**How a player sees it.** "Why this price" (§5) prints the taste as two lines when either is not 1: *"Islamic
taste ×1.30"* and *"Arabia & the Gulf taste ×0.92"*.

**The 10 great powers.** None: faith follows the city's culture, not its flag. A Portuguese Goa still prices
as an Indic city.

### 3.2 ★ Relations between powers — tariffs [F4, F5]

**Grounding.**
- UWO: a tariff by nation, 6 – 14 %, and investor ranks get 10/8/6/4/2 % off. Origin: a base tariff of
  20 – 30 % that a mayor can move −5 … +15 %; an allied port charges none (`UWO_TRADE_PRICES.md` §4).
- History: the Navigation Acts (1651) shut foreign hulls out of English colonial trade; Spain's Casa de
  Contratación kept the Indies trade Spanish; the Ottoman capitulations (France 1536, England 1580) gave
  friendly merchants lower customs, 3 – 5 %, than others paid.

**The term.** In the trader's quote, through the one per-company tax authority that already exists:

    world.tax_rate(p_port, p_player)  (0147)
      rate := base (mayor's or city's)                                   -- unchanged
      rate := rate × (1 − influence_citizen_tax_cut)  if citizen          -- 0147, unchanged
      rate := least(rate × stance_mult(company's power, city's power), tariff_rate_max)  -- NEW
    stance_mult: ally 0.5 · peace 1.0 · rival 1.5 · war 2.0      (knobs)

A free city (no flag) is at peace with everyone. **Trader's quote, per company.**

**Data.** `data/relations.json`: one row per unordered pair of powers that is not at peace, with its stance
and a line of why (e.g. Spain – England rival, the Armada years). Table `public.power_relations(a, b, stance)`.
Keyed on the power codes the great-powers redesign settles; until it lands, it is keyed on today's
`public.nations` and carries only the pairs everyone agrees on.

**Size.** The profit tax is at most 20 % today (`tax_rate_max`). A rival's tariff can reach 30 %, a war's 35 %
(`tariff_rate_max`), so a hostile port takes at most a third of the profit — never the trade.

**Cost.** Two primary-key reads per quote (`port_allegiance` is already read; one more read of the stance
pair). The merchant planner calls `world.tax_rate` once per leg, so the arrivals sweep pays ~0.02 ms a leg.
Can be precomputed as `port_power_stance(port, power)` if the measure says so.

**How a player sees it.** "Why this price" (§5) prints *"Tax 12 % (English city, rival: ×1.5)"*. The city
panel shows the city's flag and your stance with it.

**The 10 great powers.** This IS the powers' interaction with prices. Merchants (who carry
`players.nation_id`) pay it too, so a war between two powers really moves their merchants' routes.

### 3.3 ★ Influence — your country's hold and your own stake [F6]

**Grounding.**
- UWO investor ranks (10/8/6/4/2 % off), Origin's duty-free trade for titled players where their country holds
  ≥ 10 %, UW2's trade permits (`docs/INFLUENCE.md` §1).
- EVE: standings with the station's owner lower the broker fee (§1.2).

**What exists.** 0147 built the country half: a citizen of the holder pays half the profit tax (D9 of
`docs/INFLUENCE.md`, `influence_citizen_tax_cut` 0.5). Nothing is built for the company's own stake.

**The term.** The company half, in the trader's quote, on the spread:

    world.spread_effective(port, good, fleet)  (0017, 0022, 0083)
      spread := … (purser, bargain — unchanged)
      spread := spread × (1 − investor_shave(rank of the company among this city's givers))   -- NEW
    investor_shave: rank 1 0.10 · 2 0.08 · 3 0.06 · 4 0.04 · 5 0.02 · else 0     (one jsonb knob)

The rank is the company's points in the city's influence book (`public.port_influence`, 0144; it decays 10 % a day, D6). **Trader's
quote, per company.**

**Data.** The influence book that exists. A nightly table `port_top_givers(port, player, rank)` (top 5 a city)
filled by the daily evaluation (D4, 00:47 UTC), so the quote reads one row.

**Size.** The spread is a few per cent of the middle, so a 10 % shave of it is a fraction of one per cent of the
price: a reward that shows on every trade and never pays for a voyage on its own.

**Cost.** One PK read per quote of the precomputed rank table.

**How a player sees it.** "Why this price" (§5): *"Your stake here: #2 giver, spread −8 %"*. The Town Hall's
givers list already shows the rank.

**The 10 great powers.** Only the company counts, not its country: a Portuguese house that leads the givers in
English Bristol gets its shave even while England holds Bristol.

### 3.4 ★ Merchant pressure — crowding that is felt and seen [F7]

**Grounding.**
- UWO: a large sale of one category (profit ≥ 100,000) can trigger a 폭락 that halves the price, so players
  split sales into lots of 20 – 50. Origin retuned the volume that moves the 시세 (2024-12).
- RuneScape's Grand Exchange and EVE's market show each item's daily volume; prices fall when sellers pile in.
- Patrician / Port Royale: a town's stock against its consumption sets the price; a flooded town stays cheap
  until its people eat through the glut (§1.4).

**What exists.** The stock term √(stock_target / stock) (elasticity 0.5), walked 10 t at a time in
`world.quote_priced`. A sale lowers the price at once, but the stock refills toward its target within hours,
so 821 merchant companies selling the same pepper leave no trace a player can see.

**The term.** A glut on the market row, in the market price:

    mid_from_terms(… , p_glut)   ×  (1 − p_glut)          glut ∈ [0, glut_max 0.30]
    on a SELL of q tons:  glut += glut_per_depth × q / stock_target          (glut_per_depth 0.30)
    each tick slot:       glut *= (1 − glut_decay)                           (half-life ~1 game-day)

Applied after the band like the haul, so the band bounds the drift, not the crash. A BUY does not lower it.
**Market price, everyone.**

**Data.** `port_goods.glut numeric(5,4) default 0` (new column). Written in the same UPDATE of `port_goods`
that a sale already makes; decayed in the tick that already steps `drift` on every row.

**Size.** At most 30 % off; a sale of a full market's depth costs 30 %, half the depth 15 %.

**Cost.** No new read at quote time beyond one more column of the row `mid_terms` already reads; one more
column in two existing UPDATEs. Needs a 13 → 14 argument re-cut of `mid_from_terms` and its four callers
(0173's pattern), which is why it is not the first slice.

**How a player sees it.** "Why this price" (§5): *"Sold heavily here today: −12 %"*, and a volume line —
*"312 t sold here in the last day by 9 houses"* — read from the city's trade flows (`public.treasury_flows`, 0122).

**The 10 great powers.** None directly; a power with more merchants (A4) crowds its home goods more.

---

## 4. Bounds — no factor swamps distance

| factor | acts on | range | vs the haul (1 – 600×) |
|---|---|---|---|
| region taste (0066) | market | 0.92 – 1.14 | unchanged |
| **faith taste** | market | 0.60 – 1.35 | chooses between ports at one distance |
| **glut** | market | 0.70 – 1 | a day's crowding, never a route |
| drift, season (existing) | market | ±20 %, ±30 % | unchanged |
| **tariff** | your quote | tax ×0.5 – ×2, ≤ 35 % of profit | never refuses a trade |
| citizen cut (0147) | your quote | tax × 0.5 | unchanged |
| **investor shave** | your quote | spread −0 – 10 % (under 1 % of price) | a reward, not a route |

The market product of the new market terms is bounded 0.42 – 1.35; the haul alone is up to 600.

## 5. "Why this price" — one reader, every term [F8]

`world.price_why(p_port uuid, p_good uuid, p_fleet uuid default null) returns jsonb` — authenticated, stable,
read on the good page when the focus city changes (never on the beat). It reads `world.mid_terms` and
`world.quote_terms` (the authorities themselves; it computes nothing they do not) and returns:

    { base, mid,                                    -- world.price's own middle (asserted equal)
      terms: [ {key, value, mult} … ] }             -- each factor as its multiplier on the middle
      keys:  haul · affinity · region_taste · faith_taste · stock · drift · season · development · band
      quote: { spread, tax, bid_factor }            -- with p_fleet: the company's own

The client prints the terms that are not 1, largest effect first, as short lines under the hero price:
*"Far from its makers (6,900 nm) ×4.3 · Islamic taste ×1.30 · Stock high −8 % · Market today +6 %"*. The
product of the lines is the middle, so the page never shows a number the server did not price.

## 6. Build plan — slices by value against cost

| slice | what | value | cost | depends on |
|---|---|---|---|---|
| **P1 · 0185** | **Faith tastes** (§3.1) + **"Why this price"** (§5): data files, three tables, `world.demand_for` re-cut, re-derive of `port_goods.demand`, `world.price_why`, the good page's lines | the owner's "religion"; every later factor shows up through the same reader | low: no pricing function changes signature; the quote path reads the same column | — |
| **P2 · 0190** | **Volume line** (§3.4's visible half): "312 t sold here in a day by 9 houses" in `price_why` | the owner's "merchants", seen | low: one aggregate over today's flows for one (port, good) | P1 |
| **P3** | **Investor shave** (§3.3) | rewards giving, per company | low: one precomputed rank table, one hunk in `spread_effective` | I1–I6 live |
| **P4** | **Tariffs by relation** (§3.2) | the owner's "relationship with other countries" | medium: a relation table, one hunk in `world.tax_rate` | the 10 great powers |
| **P5** | **Glut** (§3.4's price half) | crowding felt | medium: `mid_from_terms` 13 → 14 arguments and four callers re-cut, two UPDATEs | P2 measured |

## 7. Later candidates — one line each

- **War** — two powers at war (P4's stance): guns, gunpowder, shot, saltpetre and grain ×1.3 – 1.6 in both
  powers' cities for the war's length; a `season_mod`-style row event, cleared at peace.
- **Trends (유행, Uncharted Waters)** — every few game-days one category in one region is "in fashion" ×1.3 – 1.6
  for a few days, announced in the city's news; reuses `season_mod` (bounded ±0.30) and the fair scheduler (0026,
  0028).
- **Festivals and holy days** — authored calendar rows (Ramadan: dates, sugar, lamp oil ×1.2 in Islamic cities;
  Lent: salt fish ×1.3 in Christian cities; Diwali: ghee, oil, sweets in Indic cities); `season_mod` on the game
  calendar.
- **Plague and famine** — a city event: grain and food ×1.5, medicine ×1.6, every other good ×0.8 (no buyers),
  population and purse down for its length; one event row, the purse and the price read it.
- **Harvest years** — a good-and-region yield draw each game-season (0.7 – 1.3) that scales `production_rate`
  rather than the price: the price follows the stock it already reads.
- **Embargo** — a power closes its cities to a rival's companies (P4's war stance with `embargo = true`):
  `cmd.do_buy` / `cmd.do_sell` refuse, like the culture mask, never a hidden price.
- **Smuggling** (UW) — trading an embargoed or refused good at a stiff discount with a chance of seizure; only
  after embargoes exist.
