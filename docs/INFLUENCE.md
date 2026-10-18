# INFLUENCE — countries compete for cities with money

**Status: APPROVED by the owner 2026-10-17 ("make the game — country region influences and all like
uncharted [waters]"), D1–D14 as written plus the three additions below. BEING BUILT from migration
0143** (0141 and 0142 were taken by other work). Slices: I1 0143 · I2 0144 · I3 0145 · I4 0146 ·
I5 0147 · I6 0148.

**Owner additions, 2026-10-17 (binding, like O1–O4):**
- **A1 UWO anti-whale damping** (§1.1) on top of D7's daily cap: each coin moves a country's influence
  in a city less as that country's share there rises, and the trailing country gets more per coin.
  It lives in the ONE posting authority, `public.influence_post` (I2).
- **A2 A company chooses its country** (UW): founding offers the 23 countries (default Portugal); a
  later change is allowed once every 7 real days (`nation_change_cooldown_days`) and costs the
  company its standing — the influence it gave stays with the old country (the book is keyed by the
  country at the moment of giving, I2) and a mayor must be a citizen of the holder (I5). Built in I1.
- **A3 Every merchant shows its company's flag when pressed** (merchant sheet, ship panel, city
  tray rows), through the one flag renderer (`src/live/HullCountry.tsx`). Built in I1.
- **A4 Rebalance the merchant companies across the countries** — proportional to a country's power
  (OWNER_REQUESTS row 119: *"powerful and rich countries will have more ships"*) with a cap on any one
  country's share and a floor so all 23 have merchants. Built in I3, before the merchants give.

**The owner, 2026-10-17, verbatim intent:** *"like uncharted [waters], i want to have influence of major
countries, so that each country can compete, and make the city have more influence [for that country]
by investing and spending money to that city."* And: *"research about the major influences and regions
of the game uncharted [waters]"* (§1).

**The owner's decisions (answered in chat, 2026-10-17) — every rule tagged OWNER comes from these:**

- **O1 City control:** *"each country will have 3~4 cities around them, and rest of them can be
  competitive"* — every country keeps 3–4 **home cities** that never change hands; every other harbour
  is **contestable** and goes to the country with the most influence.
- **O2 Merchants invest too**, for their own countries (the 821 merchant companies already carry a
  `players.nation_id`).
- **O3 Rewards for leading a city — all four:** **fame/rank**, a city **Mayor**, **investor dividends**,
  **cheaper trade** there.
- Still binding from `docs/ECONOMY_LOOP.md` §11 (owner, 2026-10-15): **O4** the profit tax is per city,
  max 20 %, and *"later the rate will be set by the city's mayor = its highest investor (within
  0–20 %)"*; `world.tax_rate` is the one place a mayor's choice plugs in.

Every other rule here is tagged **DEFAULT** — my proposal, justified by the research in §1. The owner was
burned today by a rule I invented and never asked for (the draft gate, removed by 0139), so the DEFAULTs
are kept few and are **all listed in the one table below**. Every number is a knob (`world_config`,
one reader each) so tuning needs no migration.

---

## Owner to confirm — every DEFAULT in this plan, in one table

| # | DEFAULT | Why (research) | If you say no |
|---|---|---|---|
| **D1** | **How many home cities:** 4 for a country holding ≥ 4 harbours today, 3 for the others. The capital plus its nearest own harbours **by sea**. A country with fewer than 3 is topped up from the nearest **free** (stateless) harbours, so nobody loses a city to make a home. Result: §3.1. Three top-ups are odd by geography: **Muscovy → Nuuk**, **the Hanse → Tórshavn**, **Mughal India → Hadibu (Socotra)**. | O1 says 3–4 for every country. UWO's *territory ports* and UW2's capitals are the same idea: a fixed core that is never contested (§1.1, §1.3). | Name the cities; the list is a data file (§3.2), so changing it is one edit. |
| **D2** | **Day one:** each of the 156 contestable cities keeps the country it has today (95 held, 61 free) until out-invested. | Nothing is taken from anyone at launch, and the map does not change the day this ships. | Alternative: all 156 start free. |
| **D3** | **What counts as influence:** coin a company pays **into the city** through **Invest** (0123 shares) and a new **Donate** (`ECONOMY_LOOP.md` §12.2, already designed and deferred). Trade does **not** count. | UWO, Origin and UW2 all count investment only (§1). If trade counted, Spain's 205 merchant companies would take every port they visit. Shares alone cannot carry the race: a city's works stop at level 5, and cities already buy their own shares (201 levels built, 0 shares sold to companies on prod today). Donate has no ceiling, and the money stays in the city's purse. | Shares only; or trade spend counts too. |
| **D4** | **Evaluation once a real day** at 00:47 UTC (09:47 KST). One job handles changes of country, the mayor and the fame awards. | UWO and Origin evaluate weekly, but they have thousands of players. With 17 players and merchants investing hourly, a week is too long to see anything happen. | Weekly: change the cron line only. |
| **D5** | **Change of country needs a 10 % lead:** a challenger takes the city only when its influence is ≥ 1.10 × the holder's. A free city goes to the leader once that leader has ≥ 10,000 coin of influence there. | Without a margin, two countries near a tie would swap the flag every day. UW2 used a high bar (75 % support, §1.3). | Plain "most influence wins". |
| **D6** | **Decay 10 % per evaluation** (influence halves in about a week). | Ownership must wear away when nobody spends. Origin fixed its runaway leaders by retrofitting seasons (§1.2), and UWO drops inactive investors from its rankings (§1.1). Decay does the same job continuously. | Seasons (DESIGN H.6), or no decay. |
| **D7** | **Anti-whale:** a company may **Donate** at most 20,000 coin per city per real day. Shares are not capped, because each work's shares already run out. | UWO capped each player and damped influence near the top; Origin capped NPC spending (§1.1, §1.2). A per-company cap is the simplest form, and it binds a merchant company the same way it binds a player. | UWO's damping (each coin moves the share less the higher it already is) in place of the cap. |
| **D8** | **The Mayor** is the controlling country's top investor in that city, not the top investor of any country. | Origin's bug: a foreign mayor turned a port into a tariff trap against its own country, and the fix was a cap (§1.2). O4 says "highest investor". This keeps O4 and lets a mayor reward only the country that leads. | The top investor of any country (O4 read literally). |
| **D9** | **Cheaper trade = half the profit tax** for companies of the controlling country in that city. | UWO: citizens of the owning country pay no tariff in its alliance ports (§1.1). Origin: titled players trade duty-free where their country holds ≥ 10 % (§1.2). Tax is the one price authority we already have (`world.tax_rate`). | No tax (UWO's version), or a price discount (it would need a second authority, so no). |
| **D10** | **Dividends:** a controlling-country holder's coupons are paid at **1.5 ×**. Everyone else's are unchanged. | O3 asks for dividends as a reward for leading. 0123's coupons are the existing payout, so this reuses them instead of adding a second payout. | Coupons unchanged; "dividends" then means the coupons that already exist. |
| **D11** | **Fame:** coin given to a city counts toward trading fame at the same rate as turnover (1 point per 100 coin), plus 25 points for each day as Mayor. **Rank** gains a **Countries** board: cities held, home and won. | UWO pays trade fame for investing; Origin and UW2 use "national power" = cities held (§1). | Other weights; they are knobs. |
| **D12** | **Where a merchant invests:** the same amount as 0123 (her surplus above 1.5 × capital). Where changes: the contestable stop on her loop where her country is in the **closest race** (the smallest gap to flipping or to being flipped). She buys shares if any are offered, otherwise she donates. With no contestable stop on her loop, 0123's rule stays. | O2. Origin's NPC countries also invest where a city is contested, and Origin later had to cap them (§1.2). D7's cap applies to them too. | Spend a fixed share of each lap's profit instead. |
| **D13** | **One concept: "the country a city belongs to."** The build yard's country rule (0130), the academy's (0131), the inn's officers (0073) and the map all follow the flag. A Havana won by England builds English hulls. | NO_SPAGHETTI §1: two answers to "whose city is this" would be two authorities. | Keep the yards on the founding country. That would be a second concept, named and kept apart. |
| **D14** | **The flag on screen:** the city panel's title line always shows `⚓ Portugal` (the flag and the country that holds it), plus **Home city** or **Contested**. On the map, the city's name carries the flag while the existing **Regions** filter is on. **Changed 2026-10-18 (the owner: *"beside the name show flag"*):** the flag is a bundled picture (`public/flags`, `Flag`), it stands beside the city's NAME in the tray and on the map's names at every zoom close enough to name quiet harbours, Regions on or off; the title line reads `Portugal · Home city`. | Owner rule (map-UX): keep the map clean. Regions is already the "colour by country" switch for merchants. | The flag is always on the map. |

**Consequences to know (stated, not gated):**

- **All 17 players are Portuguese today**, and stay so unless they change (A2). From I1 the Start
  screen offers every country (default Portugal) and Profile → Country changes it.
- **Malabar, Gujarat and Banten have no merchant companies** (0 houses). They hold their homes and
  will win nothing unless players invest for them.
- **Spain holds 36 contestable cities today and has 205 merchants.** Portugal holds 21 and has 122
  merchants plus every player. Expect Spain to hold the Americas and the race to happen where loops
  cross: West Africa, the Indies and the Caribbean.
- Investment is live, but **no company had bought a share** (`city_shares` = 0 rows). **Found in I1
  (a defect, fixed by 0143):** every reconcile run takes 62–71 s on prod and `npc_upkeep_budget_seconds`
  is 60; 0137 gave the whole hour ONE deadline, so by the companies' step it had passed and
  `npc_invest` deferred every company, every hour (`invested_at` null for all 821). 0143 gives the
  companies' step its own budget.

---

## 0. The answer in twelve lines

1. **One new fact, one reader:** `public.port_allegiance(port_id, nation_id, home, since)` is the
   country that holds a city. **`public.port_nation(p_port)` is the only reader.** `ports.nation_id`
   stays as the authored **founding** country, held by the world guard, and no game rule reads it
   any more.
2. **Home cities are data**: a `home` list per country in the nations data, generated once by
   `scripts/build-home-ports.mjs` from the sea distances and then authored (§3). They never change
   hands (OWNER O1).
3. **Influence is coin paid into a city by a company** through the two doors **Invest** (0123) and
   **Donate** (new; ECONOMY_LOOP §12.2's `donate_for`). It is posted in exactly one place, inside
   `public.pay_city`, into `public.port_influence(port, nation, player, points)` (D3).
4. **A country's share in a city** = its points ÷ all points there, read by `public.influence_shares(p_port)`.
5. **Once a real day**, `public.tick_influence()` decays every row (D6), changes a contestable city's
   country on a 10 % lead (D5), names each city's Mayor (D8), and posts the day's fame events (D11).
6. **Mayor (OWNER O3/O4):** sets the city's profit tax within 0–20 %, once a real day, by
   `cmd.set_tax`. A merchant mayor leaves the city's rate as it is.
7. **Cheaper trade (OWNER O3):** `world.tax_rate(p_port, p_player)` is generalised, still one
   authority: the mayor's rate (or the city's own), halved for companies of the controlling country (D9).
8. **Dividends (OWNER O3):** 0123's coupons, × 1.5 for controlling-country holders, in `tick_city` step 6 (D10).
9. **Fame/rank (OWNER O3):** `player_progress` reads the INVESTED/DONATED/MAYOR record (derived,
   never a counter, the 0014 rule); Rank gains **Countries** (D11).
10. **Merchants (OWNER O2):** `public.npc_invest` keeps its amount and changes only where she invests (D12).
11. **Town Hall** gains an **Influence** block and a **Donate** press. The city's title line and the
    map follow the flag (D14).
12. **Six migration slices, I1–I6 (0143–0148).** Each is dark or byte-parity when it lands, and one
    switch, `influence_switch(true)`, lights the race (§7).

---

## 1. Research — how the Uncharted Waters series does it

This extends `docs/DESIGN_RESEARCH.md`: §1.6 (Origin investment), §1.7 (Origin seasons), §2.1 (UW2)
and §3.2 D10 (the banded mayor tax). Those are not repeated here. The research was gathered
2026-10-17. Fandom and GameFAQs still refuse direct fetch, so their numbers below come from search
snippets and are labelled as such.

### 1.1 Uncharted Waters Online (大航海時代 Online, Koei Tecmo, 2005–)

- **Two classes of port.** *Territory ports* (領地港) belong permanently to one country. *Alliance
  ports* (同盟港) belong to whichever country holds the highest **influence %** (影響度) in that town.
  The owning country's citizens buy more goods there and **pay no tariff**, which is why key ports
  are fought over. This is the shape of OWNER O1. —
  https://ja.wikipedia.org/wiki/大航海時代Online
- **Influence is shown per country as a percentage**, and published battle results print it before and
  after (e.g. Kandia: Venice 63 % → 67 %). — https://www.gamecity.ne.jp/dol/topics_cms/fight/28278.html
- **Investment feeds two pools.** One is *development*, which unlocks goods, ships and recipes. The
  other is *influence*, which the developers deliberately damp: at about 50 % share, 100 M moves it
  about 1 %; above 90 % even 1 G may not move it; and **the country with less influence gets more
  effect per ducat**. The damping came after "intense investment wars" (Cruz del Sur ch. 5, Feb
  2009). Each character has a lifetime cap (100 G). —
  https://wikiwiki.jp/gvo/Investment, https://ja.wikipedia.org/wiki/大航海時代Online
- **Investor rewards:** trade fame for investing; a per-town **top-5 ranking** with tariff reductions
  of 10/8/6/4/2 %; **inactive characters drop out of the ranking**. The **honorary mayor** (名誉市長)
  is chosen **monthly**, may not serve two terms in a row, and earns a weekly payout from the town's
  use of facilities. — https://wikiwiki.jp/gvo/Investment
- **Great Investment War** (大投資戦): it triggers when several countries pour money into one alliance
  port at once, lasts 4 real hours, and moves influence at 3 ×. Small countries earn more rewards
  from it, and the town's bank freezes withdrawals. — https://wikiwiki.jp/gvo/GreatInvestmentWar
- **Money is paired with force.** Grand Naval Battles (大海戦) move influence by a published formula,
  and after a loss a **1–7-day investment ban** stops the loser simply buying the port back.
  *(We have no PvP and no war. ECONOMY_LOOP §12.3 keeps war deferred, so this lever is not ours.)* —
  https://wikiwiki.jp/gvo/GrandNavalBattle, https://game.watch.impress.co.jp/docs/news/378314.html
- **Playable countries:** Spain, Portugal, England; then the Netherlands, France and Venice; the
  Ottomans from 2009. Smaller countries get easier title requirements and bigger war rewards. —
  https://ja.wikipedia.org/wiki/大航海時代Online, https://game.watch.impress.co.jp/docs/20090213/dol.htm
- *Unconfirmed:* the exact moment an alliance port is re-evaluated (on each investment, or on a tick).

### 1.2 Uncharted Waters Origin (Line Games / Motif, 2022–)

- **Free, Allied and Occupied ports** go to the country with the highest Investment Score. **Some
  capitals and territories never change**, and they take investment only from their own country.
  **National Power = cities owned + their development.** — https://guide.floor.line.games/UWO/en_US/detail/1167031186467500250
- **Mayor:** the company that invested most that **week** (ties go to the earlier investor). The mayor
  sets the trade and build tax once a day; namu.wiki gives the range as −5 % to +15 %. —
  same guide; https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보
- **Area control:** above 50 % of a limited area's points gives +1 speed, more goods and −5 % build
  time; 100 % gives +2 speed and −10 % build time. —
  same guide *(DESIGN H.5 already copied this; this plan does not build it, because the owner did not
  ask for it)*.
- **NPC countries invest in proportion to player investment**, so contested ports draw more NPC money.
  Later patches cut how often they invest and capped them. —
  https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보
- **What broke:**
  - Paid-gem investment let a few whales decide national power.
  - **A foreign mayor turned an "allied" port into a tariff trap** (Kokola: an English investor took
    the port from the Dutch, who then paid 10 % there). The fix capped mismatched tariffs at 5 %. —
    https://namu.wiki/w/대항해시대%20오리진/평가
  - In Nov 2024 about 40 players were making over 50 bn a week and a single city's mayor pay could
    pass 50 bn ("ducats buying ducats"). Since Dec 2024: 3-month seasons, mayor pay removed,
    dividends raised, and points that expire each season. — https://www.inven.co.kr/board/uwo/5713/20694
  - Still unsolved: one country holding 150+ cities on a server ("천통"), and Portugal monopolising
    Africa and the Caribbean. — https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보
- **Countries:** 8. Portugal, Spain, England, the Netherlands and the Ottomans at start; Joseon, Ming
  and Japan only by emigration; about 43 NPC states. —
  same namu page; https://news.qoo-app.com/en/post/154244

### 1.3 Uncharted Waters II / New Horizons (1993) and IV

- **UW2:**
  - Investing at a port's market raises Economy, and at its shipyard raises Industry. It also raises
    **your country's support %**, and at **75 %** (one English guide says 80 %) the port becomes your
    country's ally.
  - **The six capitals cannot be invested in.** National strength = the economy of a country's
    allied ports.
  - Support gain scales with the port's size, so a big port needs more gold per 1 %.
  - A tax-free permit makes trade in your country's allied ports tax-free.
  - Sources: https://ja.wikipedia.org/wiki/大航海時代II; GameFAQs and unchartedwaters.fandom.com,
    snippet only; https://unchartedwatersnewhorizons.com/?page_id=53/new-forum-group1/general-forum1/investing-in-ports-thread426
- **UW IV:**
  - Shares belong to a player's faction, at most 3 factions per city. 100 % share = an exclusive
    contract plus monthly tribute.
  - Takeovers happen by declared war or by schemes, and the win condition is a token from each of
    the seven sea areas.
  - Source: https://www.gamecity.ne.jp/manual/dk4HeN38/jp/3300.html, …/3500.html, …/1400.html

### 1.4 Regions and the major powers

| Title | Regions it plays in | Major (playable) powers |
|---|---|---|
| UW2 / New Horizons | cultural areas decide what a yard builds (Islamic xebecs, Chinese junks, Japanese atakebune) | Portugal, Spain, England, the Netherlands, Italy/Genoa, the Ottomans (6 protagonists) |
| UW IV | seven sea areas, each with a "proof of supremacy" | Portuguese, Dutch, Swedish, Ming, Japanese, Arab, Inca-mestiza protagonists |
| UWO | **13 culture zones (文化圏, 2006):** British, Hanseatic, North French, Iberian, Apennine, Greek, Ottoman, West African, East African, Arabian, Persian, Indian, Caribbean. Expansions added Central America and Southeast Asia, South America West and Oceania, East Asia, North-East America and the Arctic | Spain, Portugal, England, the Netherlands, France, Venice, the Ottomans |
| Origin | "limited areas" are the unit of control | Portugal, Spain, England, the Netherlands, the Ottomans (+ Joseon, Ming, Japan) |

Sources: ja.wikipedia (UW2, UWO); https://news.17173.com/z/dol/content/2006-03-24/20060324163606659.shtml;
gamecity UW IV manual; namu.wiki (Origin).

**Our world already has this shape.** It has **25 regions** (`public.regions`: Iberia, British Isles,
France & the Low Countries, Baltic & the Hanse, Scandinavia & the Arctic, Western Mediterranean,
Adriatic & Ionian, Aegean/Anatolia/Black Sea, Levant & Egypt, Maghreb, Atlantic Isles, West Africa,
East Africa & the Horn, Arabia & the Gulf, Western India, Eastern India/Ceylon/Burma, Southeast Asia,
China Coast, Korea, Japan & the Ryukyus, Caribbean & the Spanish Main, North America Atlantic,
South America Atlantic, Pacific Americas, Oceania). It has **23 countries**; the seven of UWO plus
Ming, Japan and Joseon (Origin's eight) are all among them. This plan adds no region and no country.

### 1.5 What we take, what we leave

| Take | From | Where it lands |
|---|---|---|
| Permanent home ports + contestable ports, owner = highest influence | UWO territory/alliance; Origin "never change"; UW2 capitals | O1, §3, §4.3 |
| Per-country influence % shown on the town | UWO, Origin | §6 Town Hall |
| Citizens of the owner trade cheaper there | UWO (no tariff), UW2 (permit), Origin (titled duty-free) | O3, D9 |
| Mayor = top investor, sets the tax, once a day | Origin | O3/O4, D8 |
| Fame for investing; national power = cities held | UWO, Origin, UW2 | O3, D11 |
| NPC countries invest where it is contested, capped | Origin | O2, D12, D7 |
| Influence wears away (Origin's seasons; UWO's dropped inactive investors) | Origin, UWO | D6 decay |

| Leave | Why |
|---|---|
| Naval battles moving influence, investment bans after a loss | No PvP, no war (ECONOMY_LOOP §12.3 deferred) |
| Mayor pay ("weekly payout") | Origin removed it as the "ducats buying ducats" engine (§1.2). The Mayor is paid in fame and in the dividend bonus instead |
| Foreign mayors | Origin's tariff-trap bug, so D8 |
| Great Investment War events | A content event, and not asked for. It could come later as a fair-like buff |
| Area-control speed and build bonuses | Not asked for. DESIGN H.5 keeps the idea |
| Paid investment of any kind | We have no monetisation (DESIGN_RESEARCH §3.2 D3) |

---

## 2. The game today (read from the repo and from prod, 2026-10-17 ~12:15 UTC, read-only)

| Fact | Where |
|---|---|
| 23 countries, each with a flag and a capital | `public.nations(code, name, flag_char, capital_port_code)` (0002:56, 0130); world guard holds it equal to the data |
| 252 places = **238 harbours** + 14 sea places; **85 harbours have no country** (stateless) | `public.ports.nation_id`. **Authored**: `scripts/db/world-guard.mjs:107` holds every port's `nation` equal to `data/ports.json` |
| Harbours per country: ESP 40 · PRT 25 · OTT 20 · JPN 11 · FRA 8 · ENG 8 · JOS 7 · DNK 6 · MNG 5 · MLB 5 · MAR 4 · VEN 4 · NLD 4 · SWE 3 · GEN 2 · RUS 2 · HAN 2 · AYU 2 · GUJ 2 · BAN 2 · POL 2 · MUG 2 · PER 1 | prod query |
| Players: 17, all `PRT`. Merchant companies: 821 (ESP 205, PRT 122, OTT 96, JPN 58, FRA 48, ENG 46, JOS 32, MNG 29, DNK 27, NLD 23, VEN 22, HAN 21, GEN 15, POL 14, MAR 13, SWE 13, MUG 11, AYU 10, RUS 8, PER 8; MLB/GUJ/BAN 0) | `players.nation_id`, `players.is_npc` |
| City economy **ON** since 11:19 UTC: 238 purses, Σ 7.27 M coin | `port_treasury`, `city_treasury_enabled` true |
| Works: 201 levels built, all by the cities' own subscription; **0 company shares** | `city_works`, `city_shares` |
| The one tax authority: `world.tax_rate(p_port)` = city column × `profit_tax_scale` (5), ≤ `tax_rate_max` (0.20) | 0122:394-407. Callers on prod: `cmd.do_sell`, `public.profit_tax`, `public.npc_leg_lines`, `world.market`, `world.price`, `world.quote`, `world.snapshot`, `world.town_hall` |
| The one door into a city's purse: `public.pay_city(player, port, kind, ducats, event)` | 0122; `invest_for` (0123) calls it with `SHARE` |
| Fame is derived, never stored: `public.player_progress` (trading = turnover/100; exploration; combat 0) | 0069 |
| **Functions that read a country (prod `pg_proc` scan for `nation_id`):** the port's country in `world.snapshot`, `world.inn`, `world.inn_chance`, `public.yard_wrong_country`, `public.skill_taught_at`. A company's or an officer's country (not a port's) in `world.player`, `world.standings`, `world.npc_fleet_card`, `world.port_merchants`, `world.route_board`, `world.sea_roster`, `world.sea_traffic`, `world.officers`, `public.new_house` | prod scan; I1 re-runs it as its own assert |
| Cron jobs: arrivals 15 s, drift */10, price-snapshot */10, buff-calendar */10, reconcile :07, city :37, cron-purge 04:23 | `cron.job` |
| The client: the city panel's tabs Market · Port · Inn · **Town Hall** (`src/features/map/CityTabs.tsx`, `CityTownHall.tsx` 300 lines); its title line prints `port.country` (`src/features/map/MapScreen.tsx:116-124`); the **Regions** filter tints merchants by country ink (`src/chart/FleetsLayer.tsx:114`) | src |

`docs/DESIGN.md` §H.3–H.5 sketched this before the economy existed: shares per track, a weekly cap,
a banded mayor tax, weekly dividends, and "a free port flips … owned ports never flip". This plan
**replaces** H.3–H.5. It keeps their spirit (the cap, the band, the free-port flip) and builds on what
0122/0123 actually made. When I1 lands, H.3–H.5 get a one-line pointer here (NO_SPAGHETTI §5: delete,
don't adapt).

---

## 3. Home cities (OWNER O1, rule D1)

### 3.1 The table, computed from prod

The rule (D1), applied to prod data with distances **sailed** (`public.sea_reaches`, the miles the SAIL
picker uses):

1. Each country takes its capital and then its own harbours in order of sailed miles from the capital.
2. It keeps 4 of them if it holds 4 or more, otherwise 3.
3. A country left short takes the nearest free harbours, shortest distance first across the whole
   world, so no harbour goes to two countries.

Mughal India's capital is taken as **Karachi** (0140).

| Country | Holds today | Homes | Home cities (sailed miles from the capital) | Players / merchants |
|---|---|---|---|---|
| ESP ⚔ Castile-Spain | 40 | 4 | Seville (capital) · Sanlúcar de Barrameda 40 · Cádiz 66 · Ceuta 141 | 0 / 205 |
| PRT ⚓ Portugal | 25 | 4 | Lisbon (capital) · Setúbal 38 · Porto 158 · Funchal 505 | 17 / 122 |
| OTT ☾ Ottoman Empire | 20 | 4 | Istanbul (capital) · Izmir 271 · Thessaloniki 294 · Rhodes 389 | 0 / 96 |
| JPN ⛩ Japan | 11 | 4 | Sakai (capital) · Osaka 0 (same anchorage) · Tokyo 326 · Kagoshima 366 | 0 / 58 |
| FRA ⚜ France | 8 | 4 | Marseille (capital) · Toulon 24 · La Rochelle 1,656 · Nantes 1,702 | 0 / 48 |
| ENG ☩ England | 8 | 4 | London (capital) · Portsmouth 172 · Kingston upon Hull 215 · Plymouth 290 | 0 / 46 |
| JOS ☰ Joseon | 7 | 4 | Busan (capital) · Ulsan 32 · Tongyeong 50 · Yeosu 80 | 0 / 32 |
| DNK ✠ Denmark-Norway | 6 | 4 | Copenhagen (capital) · Bergen 439 · Trondheim 745 · Reykjavík 1,225 | 0 / 27 |
| MNG 龍 Ming China | 5 | 4 | Guangzhou (capital) · Xiamen 343 · Quanzhou 383 · Fuzhou 457 | 0 / 29 |
| MLB ✹ Malabar | 5 | 4 | Kozhikode (capital) · Kannur 54 · Kochi 82 · Mangaluru 122 | 0 / 0 |
| MAR ❂ Morocco | 4 | 4 | Safi (capital) · Agadir 146 · Salé 151 · Tangier 270 | 0 / 13 |
| VEN ✥ Venice | 4 | 4 | Venice (capital) · Corfu 473 · Zakynthos 583 · Heraklion 846 | 0 / 22 |
| NLD ⚑ The Netherlands | 4 | 4 | Amsterdam (capital) · Hoorn 18 · Rotterdam 49 · Middelburg 91 | 0 / 23 |
| SWE ✦ Sweden | 3 | 3 | Stockholm (capital) · Visby 105 · Turku 128 | 0 / 13 |
| GEN ✚ Genoa | 2 | 3 | Genoa (capital) · Chios 1,153 · **Livorno (free today)** 62 | 0 / 15 |
| RUS ☦ Muscovy | 2 | 3 | Arkhangelsk (capital) · Kaliningrad 2,253 · **Nuuk (free today)** 2,737 ⚠ | 0 / 8 |
| HAN ⚖ The Hanse | 2 | 3 | Hamburg (capital) · Lübeck 581 · **Tórshavn (free today)** 740 ⚠ | 0 / 21 |
| AYU ⛨ Ayutthaya | 2 | 3 | Ayutthaya (capital) · Pattani 451 · **Hội An (free today)** 1,082 | 0 / 10 |
| GUJ ❁ Gujarat Sultanate | 2 | 3 | Khambhat (capital) · Surat 17 · **Mumbai (free today)** 138 | 0 / 0 |
| BAN ✧ Banten | 2 | 3 | Banten (capital) · Jakarta 45 · **Surabaya (free today)** 419 | 0 / 0 |
| POL ♛ Poland-Lithuania | 2 | 3 | Gdańsk (capital) · Riga 319 · **Tallinn (free today)** 362 | 0 / 14 |
| MUG ✺ Mughal India | 2 | 3 | Karachi (capital) · Chittagong 2,373 · **Hadibu (free today)** 1,024 ⚠ | 0 / 11 |
| PER ☀ Safavid Persia | 1 | 3 | Bandar Abbas (capital) · **Muscat (free today)** 238 · **Manama (free today)** 317 | 0 / 8 |

**82 home cities; 156 contestable.** On day one (D2) the contestable cities are: **95 held** (ESP 36,
PRT 21, OTT 16, JPN 7, ENG 4, FRA 4, JOS 3, DNK 2, MLB 1, MNG 1) and **61 free**. Where they lie
(region: holder count): Pacific Americas ESP 14 / free 3 · Caribbean ESP 6 / free 4 · West Africa
PRT 5 / free 6 · East Africa OTT 1, PRT 2 / free 8 · Southeast Asia ESP 2, PRT 1 / free 7 · Eastern
India PRT 1 / free 8 · North America Atlantic free 7 · Oceania free 6 · Maghreb OTT 4 · Arabia OTT 5,
PRT 1 · Japan JPN 7 · British Isles ENG 4 · the rest 1–5 each.

⚠ = the three odd top-ups named in D1. Better choices by history would be **Muscovy: Narva or
Astrakhan** (neither is in our world), **the Hanse: Bergen's Kontor** (Bergen is Denmark's home),
**Mughal: Thatta/Lahori Bandar** (not in our world). So either the owner names three free harbours,
or these countries keep three anyway.

### 3.2 Where the list lives

- **Data, not code** (game-development-method §1): each country in the nations data gains
  `home: ["SVQ","SNL","CAD","CEU"]`. `scripts/build-home-ports.mjs` writes it once from a dump of
  `sea_reaches` and prints the table above. After that the file is authored, the owner may edit it,
  and the script's `--check` mode only reports when the computed rule and the file differ.
- **The world guard** (`scripts/db/world-guard.mjs`) gains one check: `port_allegiance.home` equals the
  data, both directions; every country has 3 or 4; no harbour is home to two countries; every home's
  current `nation_id` is its own country (an owned home is never taken from another country).
- A top-up home (a free harbour today) becomes that country's: its `port_allegiance.nation_id` is
  set at I1. `ports.nation_id` stays NULL. That column is the founding record, and the guard keeps
  holding it equal to `data/ports.json`.

---

## 4. The influence model

### 4.1 What counts (D3)

Influence is **coin a company pays into a city's purse through an investment door**, and nothing else:

| Door | Kind (`pay_city`) | Status |
|---|---|---|
| `public.invest_for` → `cmd.invest` (shares in a work) | `SHARE` | live (0123) |
| `public.donate_for` → `cmd.donate` (a gift to the purse) | `DONATION` | new in I2. Its design is ECONOMY_LOOP §12.2 verbatim: docked there only; `donate_min_ducats` 100; event `DONATED`; a Donate press on the Town Hall |

Not counted: buying, selling, wages, supplies, repairs, hire, building, tuition, tax. All of those
already reach the purse (0122), but they are trade, not patronage, and counting them would hand every
port to the country with the most merchant traffic.

**The money is not burned.** A donation lands in the purse, and the city's own subscription
(`tick_city` step 4) turns its surplus into works. So *"make the city have more influence by
investing and spending money to that city"* also makes the city grow.

### 4.2 The book — one writer, one reader

```sql
create table public.port_influence (
  port_id    uuid not null references public.ports(id) on delete cascade,
  nation_id  uuid not null references public.nations(id),
  player_id  uuid not null references public.players(id) on delete cascade,
  points     numeric not null check (points >= 0),     -- coin given, decayed (D6)
  day_given  bigint  not null default 0,               -- coin donated today (D7's cap), reset by the evaluation
  updated_at timestamptz not null default now(),
  primary key (port_id, nation_id, player_id)   -- as built (0144): the country AT GIVING (A2)
);
```

- **The one writer at spend time:** `public.pay_city`, when `p_kind in ('SHARE', 'DONATION')`, calls
  `public.influence_post(p_player, p_port, p_ducats)`. It upserts `points += ducats` and
  `day_given += ducats` for a donation, with the company's `nation_id` read **at the moment of
  giving**. That is one hunk, sliced from the live `pay_city` and asserted to occur once. A future
  investment door gets influence by passing through `pay_city`, which it must do anyway.
- **The one other writer:** `tick_influence` (decay, reset of `day_given`).
- **The one reader of shares:** `public.influence_shares(p_port) returns table(nation_id, points,
  share)`, summed per country. The Town Hall, the evaluation, the mayor rule, the merchant rule and
  Rank all compose it. A house's own line (`player_id`) exists so the Mayor (D8) and fame read the
  same book.
- Why a table and not a reading of the ledger: decay (D6) is a running state. Re-deriving it from
  every INVESTED event for 238 harbours each day would be the exponential-cost shape that 0137 just
  removed from reconcile. The INVESTED/DONATED events remain the record for fame (§5.4) and History.

### 4.3 Share, evaluation and change of country (D4, D5, D6)

`public.tick_influence(p_now)`, cron `byeharu-voyage:influence` at `47 0 * * *` (clear of :07, :37,
*/10 and 04:23). It follows the `tick_city` shape: `lock_timeout` 2 s, each step in its own exception
block with the error in the receipt, `for update skip locked` on `port_allegiance`.

```
1. DECAY    update port_influence set points = points × (1 − influence_decay), day_given = 0;
            delete rows under 1 point
2. RANK     per harbour: influence_shares(port) → leader, runner-up, the holder's points
3. CHANGE   contestable harbours only (port_allegiance.home = false):
              held:  leader ≠ holder and leader.points ≥ influence_flip_lead × holder.points
                     → nation_id := leader, since := p_now, event FLAG_CHANGED {port, from, to, shares}
              free:  leader.points ≥ influence_claim_min → nation_id := leader, FLAG_CHANGED {from: null}
            home harbours are never written (a CHECK trigger refuses any change to a home row's nation_id)
4. MAYOR    (I5) per harbour: the top player_id among the holder's country in port_influence
            (ties → the earlier updated_at) → port_mayor
5. FAME     (I6) one MAYOR_DAY event per mayor (the fame record, §5.4)
6. RECEIPT  jsonb: decayed, changed [{port, from, to}], claimed, mayors, ms per step
```

A city never goes from held back to free (D5): only a challenger can take it. When nobody gives,
decay leaves the shares where they were, but it shrinks the coin a newcomer must beat, which is how
stale ownership erodes (D6).

**Changes of country are announced.**
- Every company of the two countries concerned gets a History line: `Havana now flies the flag of
  England (54 % to 41 %).` It is written by the existing event → headline path
  (`src/features/ledger/headline.ts`), with no new channel.
- The receipt's `changed` list is what the owner reads after the 00:47 run.

### 4.4 Anti-whale (D7)

`donate_for` refuses `E_DAY_CAP`, with figures (`cmd.figures(given_today, cap, 'ducats')`), once
`day_given + amount > influence_day_cap`. The amount is not trimmed to fit: a refusal that names the
remaining room is the shape every other door uses (E_OVERSUBSCRIBED). Shares carry no cap, because
`city_offered` already limits them. The cap is per company, so a merchant company meets it exactly
as a player does. D7 offers UWO's damping as the alternative; it would be one function,
`influence_weight(share)`, inside `influence_post`, and nothing else would change.

---

## 5. The four rewards (OWNER O3)

### 5.1 Mayor (O3, O4, D8)

- `public.port_mayor(port_id pk, player_id, since, tax_rate numeric null, tax_set_at)`. The **only
  writer** is `tick_influence` step 4 (for the person). The **only other writer** is `cmd.set_tax`
  (for the rate).
- The mayor is the top investor of the **controlling** country in that city (D8). This includes home
  cities, where the home country's top investor is mayor.
- When the mayor changes, the rate goes back to the city's own (`tax_rate := null`). A new mayor
  chooses again.
- `cmd.set_tax(p_port uuid, p_rate numeric)`:
  - Refuses `E_NOT_MAYOR`, `E_TAX_BAND` (outside 0–`tax_rate_max`, OWNER O4) and `E_ONCE_A_DAY`
    (Origin's rule).
  - It is authenticated-only and registered in `client_rpc_entry_points`. It is not a queue verb.
  - The mayor sets the rate from anywhere; no docking is needed, because the mayor holds an office
    and has no cargo to move.
- **A merchant mayor** never calls `set_tax`, so its city keeps its own rate.

### 5.2 Cheaper trade (O3, D9) — one authority, generalised

`world.tax_rate(p_port uuid)` becomes `world.tax_rate(p_port uuid, p_player uuid default null)`:

```
base  := case when city_treasury_on() then coalesce(port_mayor.tax_rate,
                   least(ports.tax_rate × profit_tax_scale, tax_rate_max))   -- 0122's line, unchanged
              else ports.tax_rate end
rate  := case when influence_on() and p_player is not null
                   and players.nation_id = port_nation(p_port)
              then base × (1 − influence_citizen_tax_cut) else base end
```

- The old one-argument signature is dropped. The callers on prod (§2: `do_sell`, `profit_tax`,
  `npc_leg_lines`, `market`, `price`, `quote`, `snapshot`, `town_hall`) are re-cut to pass the
  seller. A read with no company passes null and prints the city's base rate.
- The merchant planner (`npc_leg_lines`) passes the merchant, so merchants also prefer to sell where
  their country leads.
- This is the hot path: one PK lookup each on `port_mayor`, `port_allegiance` and `players`. I5
  measures arrivals on prod before and after (the 10 s budget, RESUME 10-17).

### 5.3 Dividends (O3, D10)

`tick_city` step 6 (0123): `due = round(paid × works_coupon_pct × days × m)`, where `m =
influence_owner_coupon_mult` (1.5) when the holder's country holds the city and `influence_on()`,
and 1 otherwise. A city still pays only what it holds above its reserve (0123's rule, unchanged), so
the bonus makes a poor city skip sooner. That is stated, and visible on the Town Hall. This is one
hunk in the live `tick_city`.

### 5.4 Fame and rank (O3, D11)

- `public.player_progress` (0069) gains two terms in **trading**:
  - `floor(Σ coin given (INVESTED.cost + DONATED.amount) / fame_ducats_per_point)`, read off the
    ledger like turnover;
  - `count(MAYOR_DAY events) × fame_per_mayor_day` (25).
  - It stays derived, with no counter (0014's rule).
- **Rank → Countries** (`world.nation_standings()`, one read): per country, cities held (home and won),
  the change this week, and that country's top 3 investors by name. In `src/features/rank/RankScreen.tsx`
  it is a second segment beside the captains board.
- A company's line on the captains board shows `Mayor of Havana` when it holds an office.

---

## 6. Merchants invest for their own country (OWNER O2, D12)

`public.npc_invest` (0123, composed by 0137's companies step) keeps:
- **who** invests: purse > `npc_invest_above` × capital;
- **how much**: down to `npc_invest_keep` × capital;
- **how many an hour**: `npc_invest_max_per_hour`.

Only **where** changes, and only while `influence_on()`:

```
candidates := the harbours of her routes' stops (npc_fleets.route_id → standing_route_stops.port_id)
              that are contestable (port_allegiance.home = false)
gap(port)  := if her country holds it:  her_points / (influence_flip_lead × best_rival_points) − 1   (defend)
              else:                     (influence_flip_lead × holder_points) / her_points − 1        (attack)
              (a free city: influence_claim_min / her_points − 1)
pick       := smallest gap ≥ 0 (closest race). No candidates → 0123's rule (most shares offered)
spend      := shares there if offered (invest_for), the rest as a donation (donate_for), all under D7's cap
```

Both doors are the players' doors (NPC_TRADERS §0: merchants use the same tables and the same
executor). The receipt counts `invested` and `donated`. The merchant sheet line becomes `Gave 24,000 🪙
to Havana for Castile-Spain`.

---

### 6.1 As built (0145)

- **The rebalance (A4)**, measured on prod 2026-10-17 (ESP 205 · PRT 122 · OTT 96 · JPN 58 · FRA 48 ·
  ENG 46 · JOS 32 · MNG 29 · DNK 27 · NLD 23 · VEN 22 · HAN 21 · GEN 15 · POL 14 · SWE 13 · MAR 13 ·
  MUG 11 · AYU 10 · PER 8 · RUS 8 · MLB / GUJ / BAN 0 — 821): quotas by 0105's weight (Σ commerce +
  industry of the harbours a country holds today) with a **cap of 12 %** (99) and a **floor of 12**,
  water-filled. Result on the chain: ESP 99 · OTT 99 · PRT 99 · JPN 65 · FRA 50 · ENG 46 · JOS 36 ·
  MNG 31 · MLB 30 · DNK 29 · HAN 23 · NLD 23 · VEN 23 · POL 22 · GUJ 21 · BAN 20 · GEN 19 · MAR 16 ·
  AYU 15 · PER 15 · SWE 15 · RUS 13 · MUG 12. 129 companies move (106 from Castile, 23 from
  Portugal); 62 take a home on their own loop, 67 (no loop reaches the new country) at its capital.
- **The gap**, corrected from §6's formula (which compared defence the wrong way round): defend =
  `flip_lead × hers / best rival − 1` (never below 0), attack = `flip_lead × holder / hers − 1`, claim =
  `claim_min / hers − 1`; a stop where her country has given nothing is no race.

## 7. The switch, and what each slice does

`influence_enabled` (false) is read by **`public.influence_on()`** and nothing else, which is the
0122 `city_treasury_on()` shape. `public.influence_switch(true)`:
- schedules `byeharu-voyage:influence`;
- opens Donate;
- turns on the rewards and the merchant where-rule;
- leaves the book alone, because posting runs from I2 whether lit or dark, so influence given before
  the switch counts.

`influence_switch(false)` puts every consequence back at once and keeps the flags as they stand.

Every slice follows the live-DB rules in `docs/SHIPS_AND_SKILLS.md`'s header and `docs/DEPLOY_RUNBOOK.md`:
- hunks are sliced from the LIVE body, LF-normalised, and each must occur exactly once;
- the self-asserts use their own throw-away houses (`new_house` / `npc_found`), never a live fleet;
- deploy is `unwind_the_clock()` → `db push --linked` → `wind_the_clock()` → merge at once (client
  ahead of DB is the broken direction);
- after any game change, `npm run refresh` in `tools/projectmap`.

The DEPLOY_RUNBOOK's job list gains `influence` in I4.

| # | Migration | What it changes | Proof (self-assert, rolled back) | Dark / rollback |
|---|---|---|---|---|
| **I1 · 0143** | `a_city_flies_a_flag` | `port_allegiance` seeded = `ports.nation_id` (+ `home` from the data, + the 10 top-up homes' `nation_id`); home-row guard trigger; **`public.port_nation(p_port)`** (PL/pgSQL, the one reader); `world.snapshot`'s port `nation`, `world.inn_chance`, `public.yard_wrong_country`, `public.skill_taught_at` re-cut to read it (`world.inn` reads an officer's country, not the port's); the companies' reconcile step gets its own budget (the 0-shares defect); `cmd.change_country` + `nation_change_next_at` + founding in the capital (A2); merchant flags (A3); **`world.allegiance()`** → `[{port, nation, home, since}]` (authenticated, registered); world guard home check; `scripts/build-home-ports.mjs` | (a) the prod `pg_proc` scan finds **no** function reading a port's `nation_id` except `port_nation`; (b) byte parity: snapshot, inn chances on 50 sampled (officer, port) pairs, `yard_wrong_country` for every (hull, yard), `skill_taught_at` for every skill all equal their pre-images, **except** the 10 top-up homes, which are asserted to have moved from null to their country; (c) a probe UPDATE of a home row is refused | no switch: the only visible change is the 10 top-ups. Rollback = a forward slice restoring the five readers' `p.nation_id` |
| **I2 · 0144** | `a_city_counts_who_gives` | `port_influence`; `influence_post`; the `pay_city` hunk; `influence_shares`; `donate_for` + `cmd.donate` + `cmd.preview_donate` (registered); `E_DAY_CAP`; `world.town_hall` restated whole with an `influence` block (`{holder, home, since, shares:[{nation, share, points}], you:{points, given_today, cap}}`); knobs `influence_enabled` false, `influence_day_cap` 20,000, `donate_min_ducats` 100 | an investment by a probe PRT house posts its cost to PRT at that port; a donation is refused dark (`E_NOT_OFFERED` "… is not taking gifts yet"), and lit (inside the assert) posts, is refused past the cap with figures, and conserves purse + treasury; `town_hall` keys exact | book posts from shares now; donate dark. Rollback: drop the hunk |
| **I3 · 0145** | `merchants_give_for_their_country` | `npc_invest` where-rule (§6) behind `influence_on()`; receipt `donated`; `npc_fleet_card` line | a probe merchant (PRT) with stops at a PRT-held and an ESP-held contestable port, ESP leading by 5 %, gives at the ESP one (closest race); with only home stops she follows 0123's rule byte for byte; dark → 0123's choice on 50 sampled merchants equals the pre-image | dark. The whole npc pool is selected in CI (`docs/CI.md` S rule) |
| **I4 · 0146** | `the_flag_follows_the_money` | `tick_influence` steps 1–3 + 6; cron `byeharu-voyage:influence` (inactive); `influence_switch`; `FLAG_CHANGED` event + headline words; knobs `influence_decay` 0.10, `influence_flip_lead` 1.10, `influence_claim_min` 10,000 | on probe rows: decay to the coin; a 9 % lead keeps the holder and an 11 % lead changes it; a free city is claimed at the minimum and not below; a home row never changes; the receipt figures equal a recount; the run on the live world takes < 5 s (a notice, not a raise; prod CPU is burstable) | the switch. Flags already changed stay (they are true facts) |
| **I5 · 0147** | `a_city_has_a_mayor` | `port_mayor`; step 4; `cmd.set_tax` (registered); **`world.tax_rate(p_port, p_player)`** and the eight callers re-cut; `influence_citizen_tax_cut` 0.5 | the mayor is the controlling country's top giver, not a richer foreigner; `set_tax` refuses a non-mayor, 0.21 and a second same-day call; a citizen pays half the profit tax on a probe sale and a foreigner pays it all; dark = every caller's output equals its pre-image on 200 sampled quotes (the 0122 pre-image method) | the switch. Arrivals measured on prod before and after |
| **I6 · 0148** | `leading_a_city_is_known` | step 5 (`MAYOR_DAY`); `player_progress`'s two terms; the coupon multiplier hunk in `tick_city`; `world.nation_standings()`; knobs `fame_per_mayor_day` 25, `influence_owner_coupon_mult` 1.5 | a probe giver's trading points rise by cost/100; one mayor day = 25; the controlling holder's coupon = 1.5 × another's for the same `paid`; standings count = `port_allegiance` per country | the switch |

**As built (0146):** `tick_influence` writes nothing while dark; the job `byeharu-voyage:influence`
is defined inactive and `influence_switch(true)` starts it; the History line goes to the PLAYER
companies of the two countries. **Then:** `select public.influence_switch(true)`. The first 00:47 run's receipt is read (`changed`,
`claimed`, `mayors`), and the next day's change count is checked against §8.

### 7.1 Client PRs (each after its migration is LIVE)

| After | Change | Files |
|---|---|---|
| I1 | One client reader: **`portNationOf(code)`** in `src/live/worldStore.ts`, filled from the snapshot and refreshed from `world.allegiance()` when the city panel opens and once an hour. No screen reads `port.nation` directly; a spec greps for it. The city title line prints `⚓ Portugal · Home city` / `⚑ Spain · Contested` in place of the modern `port.country` (`MapScreen.tsx:116-124`). When **Regions** is on, the map's city name carries the flag (`src/chart/labels.ts`, `PortsLayer.tsx`) | `worldStore.ts`, `catalog.ts` (`worldAllegiance`), `MapScreen.tsx`, `labels.ts`, `PortsLayer.tsx` |
| I2 | Town Hall **Influence** block above the works: one bar per country with ≥ 1 % (`Portugal 54 % · Castile-Spain 31 % · Ottoman 15 %`), the holder and since when, `Home city of Portugal: cannot change hands` on a home, your own points, a **Donate** press (docked only) through the step tray (`cmd.preview_donate` → `cmd.donate`), `20,000 / 20,000 🪙 given today` | `CityTownHall.tsx`, `catalog.ts` |
| I4 | History headline for `FLAG_CHANGED`; the next evaluation time on the Town Hall (`Next count 09:47`) | `headline.ts`, `CityTownHall.tsx` |
| I5 | `Mayor · Casa Lopes & Filhos` on the Town Hall; for the mayor, a **Tax** stepper 0–20 % (once a day); the sell receipt's `Tax` line shows `(half: your country leads here)` | `CityTownHall.tsx`, the sell receipt |
| I6 | Rank → **Countries** segment; `Mayor of …` on a captain's row | `RankScreen.tsx` |

**Words (`docs/WORDS.md`)**, added with I1/I2:

| Concept | Say | Never |
|---|---|---|
| a country's weight in a city | **Influence** (`Influence · Portugal 54 %`) | share (that word is 0123's), control, sway |
| a city that cannot change hands | **Home city** | territory, core, capital (unless it is the capital) |
| a city that can | **Contested** | alliance port, free port |
| a city held by nobody | **No country** | free port, neutral |
| a gift to the purse | **Donate** (`Donate · 5,000 🪙`) | patronage, aid |
| the change of country | **now flies the flag of …** | flipped, captured, occupied |
| the daily count | **Next count 09:47** | evaluation, tick |
| the top giver | **Mayor** | governor |

### 7.2 CI (`docs/CI.md`, scoped per diff)

- Every slice adds a migration, so **S** selects `db.chain.spec` and `db.image.spec`, plus every spec
  that names a function the slice **defines**. So each slice's spec must **name its functions**:
  `world.allegiance` / `worldAllegiance` (I1), `cmd.donate` / `world.town_hall` (I2),
  `public.npc_invest` (I3: the whole npc pool, which is the long leg), `tick_influence` (I4),
  `world.tax_rate` / `cmd.set_tax` (I5: `tax_rate` is named by the market and sell specs, so expect a
  wide selection), `world.nation_standings` (I6).
- New specs:
  - `tests/map.flag.spec.ts` (I1): the title line prints the holder's flag and name from
    `portNationOf`, a home city says Home city, and Regions on puts the flag on a city label;
  - `tests/map.townhall.spec.ts` extended (I2/I5): the influence bars, Donate disabled when not
    docked, the Mayor line;
  - `tests/rank.countries.spec.ts` (I6).
  - Each uses the `npcOn` fixture and sets its own preconditions (proofs never assert ambient
    defaults).
- **I1 edits `scripts/db/world-guard.mjs`**, which is under `scripts/db/` but is not one of rule F's
  image-pipeline files, so it is selected by rule G (the import graph). **No slice edits an old
  migration** (that would trigger F, the full suite).
- Main runs everything; check one full Acceptance run on main after the batch (CI.md).

---

## 8. Watching it

| Measure | Target after a week lit | Query |
|---|---|---|
| Cities that change country per day | a few (1–10), not zero, not dozens | `tick_influence` receipt `changed` in `cron.job_run_details` |
| Contestable cities held per country | movement where loops cross; nobody at > 80 % of the 156 | `world.nation_standings()` |
| Merchants who gave | most of those above 2 × capital, every hour | reconcile receipt `invested` + `donated` |
| World money `W` | flat (donations are transfers into purses) | ECONOMY_LOOP §7.2 |
| Arrivals tick (I5 hot path) | avg ≤ 3 s, max < 10 s | the arrivals runs in `cron.job_run_details` |

**Levers (knobs, no migration):**
- Too many changes → `influence_flip_lead` up, `influence_decay` down.
- None at all → the reverse, or `influence_claim_min` down.
- One country runs away → `influence_day_cap` down (it binds every company), or D7's damping (a slice).

---

## 9. What this plan does not do

- No **seasons** (DESIGN H.6): decay (D6) does their job without a wipe.
- No **area-control bonuses** (DESIGN H.5, Origin): not asked for.
- No **war, PvP or naval battles** moving influence: ECONOMY_LOOP §12.3 stays deferred.
- ~~No choosing a country~~ — superseded by A2 (built in I1).
- No **mayor pay**: Origin removed it as a runaway engine (§1.2).
- `docs/DESIGN.md` §H.3–H.5 are superseded by this file. They get a pointer here in I1.
