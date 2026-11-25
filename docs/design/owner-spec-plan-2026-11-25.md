# The owner's specification: what exists, what is missing, the slices (2026-11-25)

Source: `docs/design/owner-spec-2026-11-25.md` (row 385), the owner's words, which outrank every earlier design.
Everything here not marked as a question in section 2 is **decided by default; the owner may reverse it.**

**How this was made.** Read on origin/main 12e9807e (prod head 0496 by `docs/WORK_QUEUE.md`), in 60 minutes. No production read was made.
I read the design files named in the brief and `docs/SEA_CONDITIONS_AND_REGIONS.md`; three helper agents located the code.
- `NNN:line` means `supabase/migrations/20260818000NNN_*.sql`, the line of the definition. Many functions are later re-cut by text hunks,
  so the line is where the concept is defined, not always the whole live body.
- "lit" and "dark" are **as documented** (WORK_QUEUE, OWNER_REQUESTS, migration headers). No switch was read on prod.
- Lines I opened myself: 001:160-173, 004:92-95, 215 header, 321:104, 352:26-31 and 317-331, 396 header, 478 header, 481 header,
  `data/sea-zones.json`, `src/app/navTabs.ts`. Every other file:line is a helper's report, **not re-proven by me**.
- The open migrations are called by their planned numbers: 0497 wreck-can-sell, 0498 jobs-never-lose, 0499 near-round, 0500 fit-to-sail,
  0501 cargo-at-cost. On their branch tips the files still carry older numbers.

**The largest finding.** The sea part of the spec is mostly BUILT: 64 named seas, each with a level ask and a wave resistance ask, a
wave figure on every hull and on gear, one gate, a rule that never traps a fleet, the player's wall words, a Seas page. It was lit on
2026-11-13 and switched off on 2026-11-23 at the owner's word (row 369). The spec asks for it back. Nothing new needs inventing there;
the table needs three changes and the switch needs a careful light.

---

## 1. The spec, sentence by sentence

Columns: **Today** (authority, state) · **Missing** · **Contradicts** · **Smallest change** (slice name, section 3).

### Company and home

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 1 | "COMPANY NAME – you can change it." | `players.company_name` 004:52. No rename door exists (only `cmd.rename_fleet` 354:357). | A rename door. | Nothing. | `cmd.rename_company` (**A1**). |
| 2 | "When creating the account ... it will ask you to assign a company name." | `cmd.found_house(name, nation)` 011:41; `src/features/found/SignTheBook.tsx`. Live. | Nothing. | Nothing. | None. |
| 3 | "It should not overlap with any other names (countries, trade goods, and with other player info, no special characters)." | 3 to 24 characters, unique, **case-sensitive** (004:52); `E_NAME_TAKEN`, `E_BAD_NAME`. | Case-blind uniqueness; no country name, no good name; letters, digits and single spaces only. | Live names may already break the new rule (not read). | One reading, `public.company_name_refusal(name)`, called by founding and rename (**A1**). Old names stay. |
| 4 | "You can change your name again for free (1st time), but later ... you will have to pay (real money – not decided yet)." | Nothing. | A rename count. | The game has no real-money path at all. | `players.renames int`. Rename 1 is free; rename 2 refuses with "Not available yet" until the owner decides payment (**A1**). |
| 5 | "Then you will choose your home COUNTRY (EUROPE)." | Founding is refused nowhere: every joinable country is offered (0396 header line 46, the lead's decision of 2026-11-14). `great_powers` 187:181 holds PRT ESP ENG NLD FRA OTT MUG MNG JOS JPN. | A Europe-only rule at founding. | 0396's "founding is refused NOWHERE"; companies of Japan or Joseon may exist on prod (one of Japan was read on 2026-11-13; not re-read). | `public.nation_joinable` (0338) also asks that the capital's sea is a European home sea (**A2**). Existing companies keep their country. |
| 6 | "Your first HQ will be in your CAPITAL CITY." | A new company starts at its country's capital (143:402); `public.home_port_of` 288:116 reads the founding harbour. Live. | Nothing for a new company. | hq-corp F1: "HQ is the home city only". | None now; see 13. |

### The HQ screen and income

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 7 | "Below the COMPANY NAME ... how much income you receive, how much maintenance it costs." | `world.company_rate` 493:184 (lines of the last 24 h, live); HQ's Ledger (`src/features/city/corp/LedgerArea.tsx`). | The figures under the name, in three groups. | Nothing. | `public.company_rate_line` 493:109 gains a `group` (active, passive, maintenance); read only (**B1**). |
| 8 | "Active income – fleets, trading / gold per hour." | `world.workers` 496:958 serves each fleet's coin per hour. Live. | Nothing. | Nothing. | Shown in B1's header. |
| 9 | "Passive income – your investments on other cities – dividend." | `city_shares` 123:120; `city_coupon_hour` 495:305, `dividend_hourly_enabled` lit 2026-11-24. | Nothing. | Nothing. | Shown in B1's header. |
| 10 | "Maintenance." | Wages are taken at a sale (`wages_due` 474:154); repairs, tow, dock fee. No hourly upkeep exists. | Hourly upkeep. | Nothing: hq-corp economy section 2 already designs it. | Build hq-corp's `upkeep-and-cuts` as designed (**B2**), dark. |
| 11 | "MANAGING – ... where you manage FLEETS, EXPEDITION (land or sea), INVESTMENT." | HQ's worker list (`WorkerList.tsx`), land parties (0455, lit), Invest (`cmd.invest` 123:324). | Sea expeditions (row 19). The three names as HQ's three headings. | hq-corp C1 names the areas differently. | Client: HQ headings Fleets, Expeditions, Investments (**B1**). |
| 12 | "FLEETS – you can choose between 3 actions – COMBAT, EXPEDITION, TRADING." | `public.fleet_jobs` 481:160, kinds `best`, `fixed`, `land`; one door `cmd.set_fleet_job` 481:782. Lit. | Kinds for combat and expedition. | Nothing. | Two new kinds on the same table and door (**F1**, **F2**). No second job system. |
| 13 | "[FLAG] CITY NAME – by clicking the city name, you can change cities that have your HQ. The whole HQ screen will change ... Top left corner below company name." | The HQ screen already draws any city: `CityScreen.tsx:197-201` (`?port=`, else the fleet in hand, else home). A company has one implicit home; no HQ ownership exists. Storage is per harbour (`storage_cap` 070:130). | "Cities that have your HQ": a list a company owns, and the switcher. How a second HQ is opened is **not in the spec**. | hq-corp F1 and C4 delete `?port=`. | `public.company_hqs` (one row an HQ) seeded from `home_port_of`; the switcher lists them (**B3**). Question Q4. |

### Trading

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 14 | "TRADING – Active: You will choose a good, buy, and sell at different city." | The Trade tab (`/command`, `CommandScreen.tsx` -> `buysell/Trade.tsx`); `cmd.do_buy`, `cmd.do_sell`. Live. | Nothing. | simplify S3, hq-corp F5 and branch `desk-into-hq` delete it. | Keep the tab; do not merge `desk-into-hq`. |
| 15 | "Or you can transport the trade goods to other cities that are needed (mission) for profit & REPUTATION." | City requests: `trade_contracts` 087:178, `cmd.fulfil` 087:481 (live); hold-size requests 0466 (lit per the 0473 header); courier contracts 0483 (lit). | Courier contracts pay no Reputation. | Nothing. | One hunk: `courier_settle` 483:386 credits Reputation by the request's rule (**D1**). |
| 16 | "For transportation, the quantity ... matter. The higher trade quantity, the higher REPUTATION POINTS." | A request earns 1 point per 250 coin of its bonus, 5 to 100 (352:325-327); the bonus is quantity x price x premium, so it already rises with quantity. | A plain quantity term. | Nothing. | Points = by tuns delivered (new knob `rep_request_per_tun`), same 5 to 100 bounds (**D1**). |
| 17 | "For profits you will have to choose cities that pay the most, and REPUTATION POINTS will be earned when the profit rate is higher (profit % + total overall price)." | A sale earns 1 point per 250 coin of profit, at most 120 (`public.reputation_sale` 352:404-439). Amount only; the rate is not read. Daily cap 600. | The profit rate. | Nothing. | `reputation_sale` multiplies by a margin factor (profit / cost), bounded; the caps stay (**D1**). |
| 18 | "Some trade goods can be combined to create PREMIUM TRADE GOODS. Each PTG will be needed by one city only, and it will pay 300~500% more. PTG by themselves costs more. 1 PTG linked with 1 city." | Recipes: `goods_recipes` 280:805 (287 recipes). The Forge: `cmd.forge_good` 281:267, `forge_take` 461:216 (the one take), screen HQ > Production. Smithing 0461 is dark (`land_smith_enabled`). No good has a single buying city; no premium for a made good. City wants (0255, x2, rotating) are a different thing. | The premium list; one city each; the pay. | Closed economy: a city pays from its own purse, so 300-500 % needs a daily cap or it empties the city. The reading of "300~500 % more" (Q5). | Three columns on `public.goods` (`premium_port`, `premium_pct`, `premium_day_units`) and one hunk on the sell side of `world.quote_priced` 169:514, beside `want_mult` (**D2**). No new table, no second forge. |
| 24 | "ACTIVE METHOD: ... Or you can combine in your HQ, manufacture PTG and sell them at a designated city." | The Forge is on HQ already and uses the Storage of that city with a fleet docked there. | Nothing but row 18. | Nothing. | D2. |
| 25 | "PASSIVE METHOD: You can order your fleet to do a repeated task – buy at a city, sell at this city." | `fleet_jobs` kind `fixed` {good, buy, sell, end, times} (481, 492: lit). | Nothing. | Nothing. | None. |
| 26 | "You can choose to stop or continue based on your settings. Settings include buying at a certain price range, selling at a certain price range." | No price setting on a job. The old standing routes had `price_limit` (092:181). 0498 jobs-never-lose (open) adds a WAIT state: a job that would lose waits. | `buy_max`, `sell_min` on the job. | Nothing. | Two params on `fixed`; out of range uses 0498's wait and says why (**E1**). |
| 27 | "PASSIVE METHOD will have restrictions and require higher LEVELS and SKILLS." | No gate on jobs (481, 492, 494). Every live company may set one. | The gate. | Rows 372-376 ("Melvor with many workers": every worker automated from minute one); the owner's own standing order that fleets earn while away. | A gate read from `level_perks` (417:128) inside `fleet_job_set_for`; companies that exist keep the right (**E1**). Question Q3. |
| 28 | "THE TRADE TAB is for ACTIVE TRADING ... it will show your FLEET name, and you can change your FLEET by tapping the name." | `FleetStrip.tsx` / `FleetPicker.tsx`; one fleet in hand (`src/domain/order/draft.ts:56-130`). Live. | The name as the one press, at the top. | `desk-into-hq` deletes these files. | Client only (**C1**). |
| 29 | "In the trade tab there should be a map, showing no NPCs but only locations, where you can click them for info – price info." | A small folding map, `plans/TradeMap.tsx`. The big chart draws merchants (`model.traffic` from `world.sea_traffic` 102:130). Whether TradeMap draws them: not verified. | A map of places only, a press for prices. | Nothing. | Client only: the chart with traffic off, a harbour press opens its prices (**C1**). |

### Expedition and combat

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 19 | "EXPEDITION – is where you visit certain location (sea and land), find architect, report to your CAPITAL CITY for rewards (GOLD) and REPUTATION POINTS." | Land parties dig goods (`land_sites` 455:267, lit). The logbook records firsts (`public.logbook` 478:137, lit 2026-11-23) and pays Reputation for a finished set. Choices at sea (0486, lit). | Sites to visit at sea and on land; a find that is carried; the report at the capital; the reward. | Closed economy: the gold must come from the capital's purse (`city_pays`), never minted. "architect" is unclear (Q6). | A data table of sites; job kind `explore`; the find is a `logbook` row; the report pays on arrival at the capital (**F1**). |
| 20 | "COMBAT – is where you send FLEET for combat – PIRATES. Winning will provide you with GOLD and RP." | A player attacks by hand: `public.attack_for` 327:246 (`attack_enabled` lit by 0375). Loot is moved, not minted (`loot_due` 327:135). Bounties 0471 are dark. `rep_battle` 40 is seeded and **read by nothing** (352:331). | Sending a fleet as an order; Reputation for a win. | Nothing. | Job kind `hunt` that calls `attack_for`; `rep_battle` hooked in `battle_resolve` 323:425 (**F2**). |

### The map

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 30 | "The MAP itself will be black, and your fleet will provide a radius that will show you nearby map. The radius will be larger based on your NAVIGATION SKILL." | The whole chart is drawn. NAVIGATION gives speed and leg reach (454:201; 112:105). No sight exists. | Sight; the black. | Nothing. | **G1**, section 3. |
| 31 | "The location you've visited (city, sites etc) will show like a grey map, where you can tab on that city to not see the info, but to go there." | Visited harbours: `logbook` kind `harbour` (478, lit, humans only). | Grey drawing; "no info, only go". | Today every city's prices are served to everyone (`world.market`). Hiding them on the client only is not secrecy. | G1 (client mask first); a served mask later (**G2**). |
| 32 | "The MAP will be completely black, but where your fleets moved and been will be in grey, showing lands partly (transparent)." | A voyage is one row with its path (`voyages` 006:56); position is computed on read (`voyage.position` 047:504). Nothing records where a company has been. | The trail. | The database budget: no row per step. | One bitmap a company, written once per arrival (**G1**). |

### The voyage

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 33 | "You will need PROVISION (FOOD + WATER + CREW) as a core source." | `ships.water_t`, `ships.food_t`, `ships.crew` (004:92-95); 0.020 and 0.015 tuns a crew a day (001:167-168); spent per sea-day in `voyage.settle` 027:237. Live. | Nothing. | Nothing. | None. |
| 34 | "The CARGO SPACE based on your FLEET (up to 8 SHIPS) will also hold trade goods as well as your PROVISIONs." | Stores have had their OWN space since 0345 (`ship_stores_separate`, lit by 0369, rows 221 and 324). Ships in a fleet: at most 7 (`fleet_ship_top` 321:104). | Stores in the hold; an 8th ship. | 0345/0369; 0321's "8 -> 7". | `fleet_ship_top` 7 -> 8 (**H1**). Stores back in the hold: Q2 (**H2**). |
| 35 | "The FLEET will have a crew slot too – min and max. You will need to fill up your crew to min to operate fully." | Per class `crew_required`, `crew_max` (002:155-156); hire `cmd.do_hire` 007:632. Live. | A fleet total shown as one min / max. | Nothing. | Client: the fleet's summed min and max (**H1** client). |
| 36 | "If you meet a storm, or other HAPPENINGs at sea, your crewmates will die." | `voyage.hazard_roll` 035:292: STORM, CALM, PIRATES. A storm costs hull and time only (`storm_hull_lost` 154:464). Crew die only in fights (`raid_crew_lost` 027:167). | Crew deaths in a storm. | Nothing. | One hunk on `voyage.settle`'s STORM arm (**H3**). |
| 37 | "These Happenings may lose your trade goods too (1~2% per happening)." | None. 0501 cargo-at-cost (open) records the cost of lost cargo. | The loss. | Nothing. | Same hunk: 1 to 2 % of each good, booked through 0501's record (**H3**). |
| 38 | "IF NO FOOD or WATER is given, crews may cause RIOT – causing dramatic decrease in crew numbers." | Today an empty store ends the voyage: `voyage.forced_home` 279:267 (ALL cargo lost, hull damage, docked at the nearest city; row 223, the owner's earlier order). `SHORT_RATIONS` raises wages. | The riot. | Row 223's forced home. | Question Q2b folded into Q2: riot replaces the total loss (**H3**). |
| 39 | "IF crew numbers are below MIN, the ship speed will decrease dramatically." | x0.70 flat (`crew_short_speed_mult` 001:172, in `voyage.ship_speed_parts` 454:133). Live. | "Dramatically". | Nothing. | Speed scales with crew / min, floor 0.30 (**H3**); frozen at departure as today. |
| 43 | "The PASSIVE METHOD should also require you to make provision, crew up in the setting. The provision will be spent more with the number of crews. Since Provision takes a cargo space ... choose the appropriate amount." | A job tops up stores by itself (`stores_topup` 150:91). Use per crew exists. 0500 fit-to-sail (open): a short-handed job waits. | Crew and stores as a job's settings. | Row 34's space. | Params `crew`, `days` on the job; the planner hires and provisions to them (**E1**, after H2). |

### The seas

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 40 | "The SEA will have names." | `public.sea_zones` 215:137, 64 named seas (`data/sea-zones.json`); the Seas page in the Codex. Data live; the gate dark. | Nothing. | Nothing. | None. |
| 41 | "Some SEA will have higher level pirates, and higher expedition sites." | Hazard per sea (`hazard_base`); pirate strength per sea: not verified. | Site level by sea. | Nothing. | F1's sites carry their sea's rank; pirates: read before building F2. |
| 42 | "Some seas will require wave resistance, etc. ... gear up your ship overall ... If you do not meet the requirement, you will not be able to pass into that sea." | BUILT in 0215/0396: `ship_classes.wave`, gear `item_effects` stat `wave`, `public.fleet_wave` 215:640, level `public.title_level` 215:652, the one rule `public.sea_refusal` 215:677, the gatherer `public.sea_gate` 215:700, `E_SEA_CLOSED`. `sea_conditions_bite` was lit 2026-11-13 and set false 2026-11-23. | Nothing in code. | **Row 369** ("remove sea limits entirely"); hq-corp 0500 `area-tiers` (a second gate, by miles from home). | Re-light the existing gate (**S2**). `area-tiers` is not built. |
| 44 | "The whole cities should be reachable, but the game should [be cut] into parts – real life basis, and will add restriction." | 64 zones cut on real seas. Today's table gives nearly every far sea a LEVEL ask (title 2 to 8): a new company cannot enter the Korea Strait until level 7. | A proof that every city is reachable by a way round. | The table's level ladder against "the whole cities should be reachable" (Q1). | **S1**: data change and a reachability proof. |
| 45 | "From Brazil to Korea, you can cross the [Pacific], but that route will be sealed (requiring levels, and wave resistance), which you will have to go around through INDIA to reach KOREA." | North and South Pacific crossings ask level 8, wave 70 (the highest). The way round (the Cape 44, the Indian Ocean crossing 40) also asks levels 5 to 7. | Nothing for the Pacific. | Same as 44. | S1. |
| 46 | "One can go over Russia [the Arctic] (north), or Antarctica (south) as a shortcut but these two routes will require significant levels in Sailing and ship gear." | Arctic Ocean: level 3, wave **20** (low). The far south: "The South Pacific and the Drake Passage" 70; "The Roaring Forties" 44. Whether the raster lets a ship sail north of Russia from the Barents Sea to the Pacific: **not verified**. No skill is named Sailing (NAVIGATION and SEAMANSHIP exist). | The Arctic as a sealed shortcut; a far-south zone. | The Arctic's low ask; the harbour LNG lies in the Arctic zone. | S1: an Arctic passage zone east of the Barents Sea and a Southern zone, both at the top ask; "Sailing" read as the level the gate already uses. |
| 47 | "Design the game so that you can reach all the places of the world, but due to restrictions of the sea, you will have to go around." | `voyage.reach_passage` 188:134 already avoids shut seas when the gate is lit (396). The client's pathfinder (`src/lib/sea/pathfind.ts`) does not avoid a shut zone (helper's reading). | The pathfinder going round. | Nothing. | S2: `findPath` takes the shut zones as closed water. |
| 48 | "For both Active and Passive methods, when you choose the final destination ... the game itself will choose appropriate paths ... by visiting multiple cities for provision + crew, fix ships etc." | 0494 (live): a job sails harbour by harbour when a leg is too long or stores run short; the sail tops up stores. Active: `src/domain/passage/chain.ts`. #864: one press to Repair or Hire. 0500 fit-to-sail (open): an unfit job waits. | Stops that hire and repair by themselves. | Nothing. | `fleet_job_legs` 494:240 adds HIRE and REPAIR at a stop when 0500's `fleet_unfit` says so (**P1**). |

---

## 2. Questions for the owner (six; one line answers each)

Each has the default I build if there is no answer.

| # | Question | Default |
|---|---|---|
| Q1 | **Do ordinary seas ask a level, or only the sealed oceans?** Today's table asks level 7 for Korea's own sea. Your spec says every city is reachable and only the Pacific, the Arctic and the far south are sealed. On 2026-11-23 you said "i can't send ships because of restriction". | **Only the three sealed oceans ask a level.** Every other sea asks wave resistance alone (gear and hull), so the way round is always open to a ship that is fit for it. |
| Q2 | **Do food and water go back into the cargo hold, and does a riot replace "lose all cargo"?** Stores have had their own space since 2026-11-13 (row 221), and an empty store today ends the voyage with all cargo lost (row 223). | **Yes to both.** Stores share the hold again; no food or water means a riot (crew lost each day), and the total loss happens only when no crew is left. |
| Q3 | **What level opens the PASSIVE method?** Every company can set a repeating job today, from its first minute. | **Trading level 3 for a repeating job; price ranges at level 5.** Companies that exist today keep it for ever. |
| Q4 | **How is a second HQ opened?** The spec says you switch between cities that have your HQ; it does not say how a city gets one. | **Bought in a city where one of your fleets is docked, paid to that city; one more HQ at Rank 3, 5, 7, 9.** |
| Q5 | **"300~500 % more": 3 to 5 times the normal price, or 4 to 6 times?** | **3 to 5 times**, paid by that city's purse, up to a daily quantity. |
| Q6 | **"find architect": is this an artifact (a thing found and carried home)?** | **Yes: a find**, carried in the hold to your capital and reported there for gold and Reputation. |

Decided by default, not asked: Europe-only applies to NEW companies; a second rename is refused until payment is decided; the Trade tab
stays and `desk-into-hq` is not merged; `area-tiers` is not built; 8 ships is the top, the ladder to it stays; "Sailing" means the level
the sea gate reads; fog hides on the client first.

---

## 3. The slices

Every slice is dark behind its own switch unless it is read-only. Migration numbers are the order after 0501; a slice takes the next
free number when it is built. Client slices own only the files named.

| # | Slice | Kind | Owns | The player sees | Proof | Database cost |
|---|---|---|---|---|---|---|
| 0502 | **A1 `company-name`** | migration + client | `public.company_name_refusal`, `cmd.rename_company`, `players.renames`; one hunk on `cmd.found_house`; `SignTheBook.tsx`, `ProfileScreen.tsx`, `dict/found.ts` | A name refused with the reason; "Rename (1 free)" on Profile | Probe: "LISBON", "Pepper", a taken name in other case and "A*B" are refused; rename 1 passes, rename 2 refused | One int column (no rewrite: default 0). One unique index on `lower(company_name)` over players: built only if no two live names collide (before-check); else the rule is in the function alone |
| client | **C1 `trade-tab-fleet-map`** | client | `features/command/buysell/*`, `plans/TradeMap.tsx`, `FleetStrip.tsx`, `dict/trade.ts` | Trade tab: the fleet's name at the top (press to change), a map of places only, a press on a place shows its prices | Headless drive at 390 and 1440: change fleet, press a city, read a price; no merchant drawn | None |
| 0503 | **G1 `chart-fog`** (`chart_fog_enabled`) | migration + client | `public.company_chart`, `public.chart_mark`, `world.chart()`; one hunk in `voyage.settle` beside `logbook_arrival`; `src/chart/FogLayer.tsx` | A black map; a circle of sight round each fleet; grey where she has been; grey cities can be pressed to sail there | Probe voyage marks only the cells of its path; a merchant writes nothing; dark = nothing written, chart as before | See "The fog" below: one row a company, at most 8.1 KB, one update per arrival |
| 0504 | **H1 `fleet-of-eight`** | migration (knob) + client | `fleet_ship_top` 7 -> 8; fleet row min / max crew | "8" as the top of fleet room; crew 34 / 20-60 | `fleet_room_caps` serves 8 | None. Load: at most one more hull a fleet for a company that buys it |
| 0505 | **A2 `europe-start`** (`europe_start_enabled`) | migration + client | one hunk on `public.nation_joinable`; `NationPicker` | The start sheet offers European countries only | Probe founding under Japan refused; `cmd.change_country` unchanged; no existing row touched | None |
| 0506 | **B1 `income-header`** | migration (read only) + client | `group` in `company_rate_line`; `corp/HqCompany.tsx`, `dict/hq.ts` | Under the name: Active +x/h, Passive +y/h, Maintenance -z/h; HQ headings Fleets, Expeditions, Investments | Sum of the three = `net_per_hour` on the same rows | None (STABLE read) |
| 0507 | **B2 `upkeep`** (`upkeep_enabled`) | migration | as hq-corp `upkeep-and-cuts`, unchanged | A Maintenance line that is real | hq-corp's 5 % proof | One ledger row a company an hour |
| 0508 | **B3 `hq-cities`** (`hq_cities_enabled`) | migration + client | `public.company_hqs`, `cmd.open_hq`; `CityScreen.tsx` switcher | The city name under the company name; a press lists her HQ cities; the screen changes | Probe opens a second HQ, pays the city, is listed; home is row 1 | One table, at most 5 rows a company; no cron |
| 0509 | **S1 `seas-sealed`** | migration (data, gate stays dark) | `data/sea-zones.json`, `sea_zones` rows, `sea_leg_asks` re-derived; `scripts/build-sea-legs.mjs` | Nothing yet (the Seas page shows the new asks) | For every harbour and every European capital, a chain exists that crosses none of the three sealed zones; a barca reaches every title-1 harbour as before | 64 rows updated; `sea_leg_asks` re-derived once (about 61,752 rows: off the beat, stated in the PR, gate read first) |
| 0510 | **S2 `seas-relit`** | migration + client, then the light | `sea_conditions_light`'s guard gains the reachability count; `src/lib/sea/pathfind.ts` (shut zones are closed water); the wall words | Sealed oceans shaded; a course goes round; a wall names what is short | The existing lit proofs (0396, 0398, 0402); a probe fleet beyond a gate sails home | None new |
| 0511 | **H2 `stores-in-hold`** | migration | `ship_stores_separate` and its light step | Food and water take hold space | A fleet over its hold keeps what she carries and may sail | None |
| 0512 | **H3 `happenings-bite`** (`happenings_bite`) | migration | hunks on `voyage.settle` (STORM, CALM arms), `voyage.ship_speed_parts`; riot in place of `forced_home` | Storm: "3 crew lost, 1.4 % cargo lost"; riot; slow when short-handed | Probe storm loses 1-2 % of each good and crew by the knob; no food: crew falls daily | None new: the fields ride the `voyage_events` row already written each sea-day |
| 0513 | **P1 `stops-mend`** | migration | `fleet_job_legs`, `fleet_job_plan` | A job that repairs and hires at a stop by itself | Probe job with a damaged hull repairs at the next yard and goes on | None new |
| 0514 | **E1 `passive-settings`** (`passive_gate_enabled`) | migration + client | `fleet_job_set_for`, `fleet_job_plan`; `AssignSheet.tsx` | Buy under / Sell over / Crew / Days on a job; a locked row with the level it needs | Out-of-range job waits and says why; an old company is not locked | One boolean a company (`players.passive_kept`, no rewrite) |
| 0515 | **D1 `reputation-by-rate`** | migration | `reputation_sale`, the request credit, `courier_settle` | Reputation on the sell face before the press | Two probe sales, same profit, the higher rate earns more; caps hold | None |
| 0516 | **D2 `premium-goods`** (`premium_goods_enabled`) | migration + client | three columns on `goods`; one hunk on `world.quote_priced`; `PortForge.tsx` | "Premium: sells at Venice, x4" on the recipe and the good | Probe sale at the linked city pays x3 to x5 from its purse up to the day's units; elsewhere the normal price; purse never negative | No table; a daily counter in the city's existing day row (to be read: where `city_wants` keeps its own) |
| 0517 | **F1 `expeditions`** (`expeditions_enabled`) | migration + client | `public.expedition_sites` (data), job kind `explore`, the report at the capital | Assign > Expedition: a site, the trip, the reward; "Report" at the capital | Probe finds, carries, reports; the capital's purse falls by the reward | Sites: bounded data (about 100 rows). One `logbook` row a company a site, first time only |
| 0518 | **F2 `hunt`** (`hunt_enabled`) | migration + client | job kind `hunt`; `rep_battle` hook | Assign > Combat: a sea, the pirates' level, the odds | Probe win pays loot (moved) and Reputation | None new |
| later | **G2 `fog-served`** | migration | the price reads take the chart | Prices only for cities in sight or with an HQ | to be designed | None |

### The fog, within the budget

- **One row a company**, players only (merchants keep none): `public.company_chart(player_id primary key, cells bytea, updated_at)`.
  `cells` is a bitmap of the world in 1 degree squares: 360 x 180 = 64,800 bits = **8,100 bytes at most**, mostly zeros (it compresses).
  `-- retention: none, bounded by one row a company of a fixed size`.
- **Written once per arrival, never per step.** `voyage.settle`'s arrival already calls `public.logbook_arrival` (478); the same hunk
  calls `public.chart_mark(player, voyage)`. It walks the voyage's stored path (`voyages.path`), sets the bits within the sight radius
  frozen at departure, and writes one UPDATE. A diverted or ended voyage marks the part sailed.
- **While she sails, nothing is written.** The client already holds the voyage row; it draws the sight circle and the fresh trail
  from the path and the clock, as it draws the ship (`voyage.position` is computed on read).
- **Visited cities are not stored again:** grey cities are `logbook` kind `harbour` (478), the authority that exists.
- **Sight:** `chart_sight_nm` (150) plus `chart_sight_per_level` (50) a NAVIGATION level, read through `public.player_skill_bonus`
  (a new effect kind on the existing skill; no new skill).
- **Cost:** rows written a minute = player arrivals a minute (well under 1 today; about 19 companies by the docs). 1,000 companies at the
  full size are about 8 MB. No cron, no index beyond the key.
- **Honest limit:** G1 hides on the client. A player reading the network sees every price. G2 closes that if the owner wants secrecy.

### What is kept, changed, thrown away

| Work | Verdict | Why |
|---|---|---|
| 0497 wreck-can-sell (#868) | **Kept** | A stranded company can act; needed more once riots and storms cost crew and cargo. |
| 0498 jobs-never-lose (#865) | **Kept, built on** | Its WAIT state is the spec's "stop or continue based on your settings" (E1). |
| 0499 near-round (#866) | **Kept** | A passive job near home; will respect the sea gate through `reach_passage`. |
| 0500 fit-to-sail (#867) | **Kept, built on** | `fleet_unfit` is what P1's automatic repair and hire stops read. |
| 0501 cargo-at-cost | **Kept, built on** | Its lost-cargo record is where H3 books the 1-2 %. |
| #862 pages-stand-still-2 | **Kept** | Client quality; touches no deleted screen (not checked file by file). |
| `desk-into-hq` (H3 / S3) | **Not merged; thrown away as a whole** | It deletes the Trade tab, FleetPicker and FleetStrip, which the spec keeps. Its HQ-side parts may be cherry-picked later; not sorted here. |
| simplify S4 `tabs-shrink`; hq-corp F1, F5, C4 | **Reversed** | Trade stays on the bar; `?port=` stays (it is the HQ city switch). |
| hq-corp 0500 `area-tiers`, `area_refusal` | **Thrown away** | A second answer to "is this place open". The sea gate is the one authority. |
| hq-corp `upkeep-and-cuts`, hourly dividends, `company_rate`, `workers`, crew slots | **Kept** | They are the spec's income, maintenance and managing. |
| civ-layer K1-K5 | **Kept, after this plan** | Not named by the spec, not contradicted. |
| Standing routes (0092-0096) | **Still to be folded** (hq-corp 0493) | Their `price_limit` idea moves to the job (E1); no second automation. |
| Sea conditions 0215-0404 | **Kept: the base of S1, S2** | Built, proven, once lit. |

---

## 4. The first three, started now without an answer

Chosen so that no live company is stranded and no answer is needed.

1. **A1 `company-name` (0502).** The spec is exact. It changes nothing for a company that exists: old names stay, even ones the new
   rule would refuse. No gate, no sea, no coin.
2. **C1 `trade-tab-fleet-map` (client).** The Trade tab exists; this adds the fleet name press and the map of places. No server change.
   It also settles in code that `desk-into-hq` is not merged.
3. **G1 `chart-fog` (0503), dark.** Fog hides; it never refuses a sail, so it cannot trap anyone. Before it is lit, every live
   company's chart is filled from where she has already been (section 5), so nobody wakes to a black world.

Built in parallel (three writers, files do not overlap). S1 can also be prepared, since its data is dark, but its numbers wait for Q1.
**Not started without an answer:** S2 (the light), H2 and H3 (stores and riot), E1's gate, B3, D2, F1.

**The three safety rules, where they are kept:**
- *A live company can be anywhere.* Nothing in the first three reads where a fleet is.
- *A sea gate never traps a fleet already beyond it.* The existing rule `public.sea_floor` (396:171): a fleet is judged as holding at
  least what the sea she lies in asks, so her own waters and the way home never refuse her. S2 lights only through
  `public.sea_conditions_light()` (398:161), whose guard refuses while any player route has a closing leg; S2 adds the count of player
  fleets lying in a sealed zone to that guard's print.
- *Existing companies keep everything.* No slice deletes a ship, a name, a country, a job, a share or a shed.

---

## 5. Live players under each new rule

| Rule | What happens to a company that exists |
|---|---|
| Name rules | Keeps her name. The new reading applies to founding and to renames. Two old names equal but for case both stay; the case-blind index is built only if none collide. |
| Rename count | Starts at 0: everyone has the one free rename. |
| Europe only | Keeps her country and home, wherever it is. `cmd.change_country` is unchanged. |
| HQ cities | Row 1 of `company_hqs` is written from `home_port_of` for every company at the slice. Sheds in other cities stay as "Stored elsewhere". |
| Income header, upkeep | The header is a read. Upkeep keeps hq-corp's rules: never under a 10,000 purse, unpaid is waived, not owed. |
| Passive gate | Every company founded before the light gets `passive_kept`: her jobs run on and she may set new ones. |
| Price ranges | Jobs without a range behave as today. |
| Reputation by rate | Balances are not recomputed; only later sales use the new rule. |
| Premium goods | Stock and Storage untouched; a made good that becomes premium simply pays more at its city. |
| Fog | At the slice, each company's chart is marked once from her stored voyages' paths and a sight circle round every harbour in her logbook and her arrival events (how far back voyages and events are kept: **not verified**; a company with no history gets her home waters). Then lit. |
| 8 ships | A cap that only rises. |
| Stores in the hold | A ship whose cargo and stores then exceed her hold keeps both and may sail; she cannot buy more until she is under. Lit in its own window with the 30-minute check. |
| Storm deaths, cargo loss, riot | Apply to voyages that DEPART after the light (the figures are frozen at departure, as speed is). A voyage at sea finishes under the old rule. |
| Speed below min crew | Frozen at departure, so the same. |
| Seas sealed | `sea_floor` keeps every fleet free to leave where she lies and to sail home. A job with a leg that closes waits with the wall's words (0500's wait), it is not cancelled. The light's guard prints each affected company first; the lead tells the owner the count before lighting. |
| Automatic stops | Only adds orders to a job's plan; a job without need plans as today. |
| Expeditions, hunt | New job kinds; nothing existing changes. Land parties stay as they are, under the Expeditions heading. |

---

## What I did not verify

- Any switch on production; any live row. All states are as written in the docs.
- Whether the sea raster lets a ship pass north of Russia or south of Cape Horn outside the Strait of Magellan; S1 must measure it
  (and the no-land and straits audits must pass: CLAUDE.md).
- Pirate strength per sea; the retention of `voyages` and `events`; which hunks last re-cut `passage_gate`, `invest_for`, `tick_contracts`.
- Whether `TradeMap.tsx` draws merchants; which `desk-into-hq` commits are worth keeping.
- The 300-500 % premium against real city purses: D2 must measure a city's purse and set the daily units before it is lit.
- Most file:line references (helpers' reports), as said at the top.
