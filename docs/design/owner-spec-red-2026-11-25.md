# The owner's red comments on the specification deck (2026-11-25, second pass)

Read from the owner's open PowerPoint (`프레젠테이션1_EX.pptx`, 18 slides) at about 13:30 Korean time, before it was saved.
**This outranks `owner-spec-2026-11-25.md` and `owner-spec-plan-2026-11-25.md` (section 0 too) where they differ.**

Three kinds of text are in the deck, and they do not weigh the same:
- **Slides 1, 3, 8 and 14** are the owner's own pages (already recorded in `owner-spec-2026-11-25.md`).
- **`[[RED: ...]]`** is the owner's comment. It is an instruction.
- **The other 14 slides** were written by Claude on PC 디폴리스 from the plan's defaults plus proposals. A slide with no red comment
  is **not thereby approved**: text marked PROPOSED is still a proposal. In particular the city perks, the cities of the 12 premium goods,
  the happenings SICKNESS / FIRE / LEAK / RATS and "first company to report a site gets double RP" are Claude's inventions.

Nothing here was built, and no production read was made. Everything in sections 1 to 3 marked "read as" is a reading, reversible.

## 1. What the owner said, and what it changes

| # | Slide | The owner's red comment (verbatim) | Read as | Changes |
|---|---|---|---|---|
| R1 | 3 HQ page | "Right now my account does not have a designated HQ. I need a way to restart the game." | Two things: a company with no HQ must get one (its capital), and a Restart the player presses: founding again, company name, country, HQ. | New slice `restart-company`, first. `hq-cities` (0512) must seed row 1 for every company. |
| R2 | 4 HQ opening | "The specific requirement will be set by me after reviewing all the contents that has been made." | The HQ ladder numbers are NOT approved. Build it with the numbers as data and do not light it. | 0512 stays dark until the owner sets `hq_steps`. Plan 0.4's numbers are placeholders. |
| R3 | 6 Expedition | "This is like combat, where it has log. It will show activities. The activity uses provisions, crews (death). The activity however when you're level is high enough, will provide provisions. So it is give and take actions. Crews will die, but the rate will be determined by the level. Once you hit the MIN or the setted crew number, it will stop and return to nearest city with its goods. Expedition will give you gold, reputation. Also artifacts(uncommon - very rare) that can be given to the capital, for gold + reputation + special gear/ship(will add later)" | An expedition is a repeating activity with a log, not one trip to one site. Each round spends food, water and crew; at a high enough level a round also gives provisions. Stops at MIN crew or the number the player set, then goes to the nearest city with the goods. Gold and RP from the work itself; artifacts uncommon to very rare, given to the capital. Special gear / ships LATER. | Replaces F1 `expeditions` as planned (visit, find, report). |
| R4 | 6 Land site | "This will be like rs3 maldevor idle game. But instead you will take provisions and crews. Create a expedition with captains. How many crews you can assemble depends on your combat level. The more crew you have, the more provision you can carry -> the more dungeon raids, mining, woodcutting etc. can be done. Each captains will have levels like RS3, where you will be able level up by doing a designated work. First you will start with 2 captains, and later with levels and reputation, as well as gold, you will be able to unlock more captains. The captains can be used to send on land sites, or it can even be assigned to a fleet - ship, and give perks. The land site expedition in addition should give another currency called HONOR BADGE - where you can use to upgrade CAPTAINS." | Land expedition = captain + crew + provisions at a place, doing dungeon raids, mining, woodcutting, etc. Crew cap by the company's COMBAT level; crew carry the provisions. **Captains have their own levels per kind of work.** Start with 2 captains; more by levels + RP + gold. One seat each: land or a ship (perks there). New currency HONOR BADGE, from LAND only, spent on captains. | Reverses hq-corp A2.3 ("skills held by the company; there is no second captain-stat system"). New currency. |
| R5 | 6 Combat | "Yes that is good, but rather than chance of winning, it will show you the consumed ammo, provision and crew. For example you will send fleet to that sea, destroy the pirates - that is one round. Per round provision/crew will be lost, and in order to repeat and do the sea battles for a longer time, you will need to level up related skills. If provision is at its min, you will return to the nearest city and restock, then decided to repeat or go. The combat also gives the same benefits of expedition - gold and reputation. But in combat, honor badge is not gained but wrecks - ships and gears, that can be gathered and be used to make, upgrade ships and gears." | Combat is rounds in a sea. Show the cost of a round (ammo, provision, crew), not a winning chance. Skills lower the cost. At the provision minimum she goes to the nearest city, restocks, then repeats or goes on, by the setting. Gives gold, RP and WRECKS (ships, gear) used to make and upgrade ships and gear. No HONOR BADGE. | Replaces F2 `hunt` (it showed odds). New: ammo, round, wrecks. |
| R6 | 6 Run | "This is only where you don't want to do combat - such as trading or even expedition." | RUN and Evasion apply to trading and expedition fleets that are attacked. A fleet sent to COMBAT does not choose RUN. | `hunt` offers no RUN. |
| R7 | 7 PTG | "far cities pay closer to 5 times, near cities closer to 3 times. - YES" | Approved. | `premium_pct` = 3 to 5 by distance. |
| R8 | 7 PTG | "We already have premium trade goods no? a list of trade goods that are built by combining? No? if so, reuse what we have if not, make new." | YES, they exist: the 287 recipes (`goods_recipes`, 0280; Forge on HQ). What does not exist is "premium": one city each and the 3 to 5 times pay (no such column or table in `supabase/migrations`). So: reuse the made goods; add the city and pay. | D2 `premium-goods` as planned, no new goods. The 12 on slide 7 are all existing recipes. |
| R9 | 9 Passive | "NOPE, trading levels will give benefits when trading, such as +% increase in overall profits, bargaining success rate, etc." | Trading level no longer opens passive fleets. It gives profit % and bargain chance. | **0509 `passive-slots`: do not build or light by Trading level.** Cancels answer 3's gate ("trading 3 is good"). |
| R10 | 9 Passive | "There will be a new level, skill called management. This skill will enable to control fleets. You will be able to control fleets from the start of the game, as long as you have fleet/" | New level MANAGEMENT. A company commands any fleet it has from the first minute. | New slice `management-level`. Nothing locks a job for a fleet she owns. |
| R11 | 12 Seas | "GOOD, hange 내파 to English, and add more restrictions like 내파. Like uncharted island. Do a research if you don't know." | The eight rungs are GOOD. Screen word: **Wave resistance** (the code's word already). Add more restrictions of the same kind ("uncharted island" read as Uncharted Waters, 대항해시대). | Section 3. |
| R12 | 13 Gear | "See the previous powerpoint, and see what you need to add further." | Each new restriction needs its own way to raise it, on this page, beside wave resistance. | Section 3. |

## 2. For the builder: what stops, what changes, what is new

**Stop or hold now**
- **0509 `passive-slots`** by Trading level (R9). If it is already dark on prod, do not light it.
- **`hq-cities` numbers** (R2): dark until the owner sets them.
- **F1 `expeditions`, F2 `hunt`** as written in the plan (R3, R5): the new shapes below replace them.

**Unchanged by this pass:** company name, Trade tab and fleet map, black map, stores in the hold, riot and storm, bargaining and tax,
passive price ranges, the sea ladder (approved), automatic stops.

| Slice | What it is | Must hold | Questions / defaults |
|---|---|---|---|
| **`restart-company`** (R1, first) | A player presses Restart, confirms by typing the company name, and founds again (name, EUROPEAN country, HQ in its capital). | The owner presses it, nobody else runs it for them. **45 lines in the migrations say `references public.players`, many of them `on delete cascade`.** Append-only tables (`events`, the ledger) may not be deleted from: so retire the old company and bind the account to a new one, do not delete the row. Coin in the old purse, ships, shares and city offices must leave by rules the closed economy allows (nothing minted or lost). | Default: the old company is closed and its name freed; the new one gets the ordinary start. Not decided: whether other players get Restart too, and how often. Default: everyone, once a day. |
| **HQ for a company with none** (R1) | Row 1 of `company_hqs` for every existing company = its country's capital. | Read first why the owner's company shows none; not read here. | |
| **`management-level`** (R9, R10) | A new level, MANAGEMENT, granted by running fleet jobs. Trading's steps become profit % and bargain chance. | No company loses a job. Management locks nothing a fleet can do today. | NOT SAID: what its levels give. Default: lower maintenance per fleet, and better passive terms. Passive bargaining at Negotiation 8 / 12 / 16 (answer 13) stands. Trading's % is an amount the closed economy must pay: as a cut of her costs, not new coin. |
| **`rounds`** (R3, R5) | One shape for sea combat, sea expedition and land expedition: a round has a cost (food, water, crew, ammo), a yield, and a log line. One settle function, from time passed; a stop rule (MIN, or the set crew), then nearest city, then repeat or go. | Reuse the land party's settle-from-time (0455) and `tick_fight`; no second combat system, no row per step beyond the log's budget (`docs/DATABASE_BUDGET.md`). | Figures not set. |
| **`ammo`** (R5) | Ammo carried and used per round. | **No ammo exists today** (no such word in migrations, src or data; Powder Magazine is gear). The goods exist: Gunpowder, Shot and Ball. Default: those two goods ARE the ammo, carried in the hold. | |
| **`wrecks-yield`** (R5) | A won round gives wrecks: hull and gear parts, used by the yard and Forge. | Not the same as a player's own WRECKED fleet (#868): use another word in code, default "salvage", screen word Wrecks. Parts from a beaten NPC are moved, not minted, as `loot_due` does. | |
| **`captain-works`** (R4) | Captains gain levels by the work they do (mining, woodcutting, raids, sailing...). Start with 2; more by levels + RP + gold. Seat: land or ship. | This reverses hq-corp A2.3; captains have three levels today (Exploration, Trading, Combat). Extend that one system to works, do not add a second. Company levels stay as they are. | Price of captain 3 and up: the owner sets it (as R2). Default: existing captains above 2 are kept. |
| **`land-expedition`** (R4) | Captain + crew + provisions to a land site; crew cap by COMBAT level; crew carry the stores. | Extends `land_parties`; same 12-hour away cap. | Combat levels were not read (the sea design of October found combat at zero for everyone): check that a new company can send a first crew. Default: a starting cap that needs no combat. |
| **`honor-badge`** (R4) | Currency from LAND expeditions only, spent only on captains. | Not Reputation and not coin: a balance per company with its own ledger kind. Not from combat. | Where captain skill steps (bought with Reputation today) end up is NOT SAID. Default: Reputation keeps them; badges buy the new captain upgrades. |
| **`artifacts`** (R3) | Uncommon to very rare finds, given at the capital for gold + RP. | Gold from the capital's purse. | Special gear / ships: LATER, by the owner's word. |

## 3. More sea restrictions like wave resistance (R11, R12)

### 3.1 What the research found (2026-11-25, web; sources in the list below)

- In Uncharted Waters Origin some seas ask a minimum of: company level, **seaworthiness** (wave resistance), **ice breaking**,
  **momentum** (pushing through), **rowing**. The FLEET'S AVERAGE counts [1]. This is official.
- Ways to raise them [1]: an anchor on every ship (ice, momentum, seaworthiness); a ram (ice, momentum); armour and bigger ships
  (seaworthiness); oared ships and parts (rowing; only oared ships have it).
- Far seas are closed by a wall you cannot cross; in the beta they cost speed and hull instead [2, a wiki, not official].
- Basic ice breaking is said to be enough for the North Sea and Scandinavia [2].
- **Not found:** the figure each sea asks. The only map of them [3] is an image that could not be read. So no number below is copied.
- Disasters (storm, scurvy, rats, fire, leak, seaweed, sharks, homesickness) are answered with tools and crew; they are not entry gates [4].

[1] https://guide.floor.line.games/UWO/en_US/detail/1167031265223600324
[2] https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보 (about half of the page was read)
[3] https://www.inven.co.kr/board/uwo/5714/352
[4] https://guide.floor.line.games/UWO/en_US/detail/1166988222692000181

### 3.2 Proposal: three more, beside Level and Wave resistance (screen words in English)

All PROPOSED by Claude; the names, seas and figures are the owner's to set. Figures use wave resistance's scale and are placeholders.

| Restriction | Why | Seas that ask it (code: figure) | How to raise it (R12) |
|---|---|---|---|
| **Wave resistance** (exists, English from now on) | Big waves | As the table in plan 0.1 | Bigger ships, Anchor, Sheathing, Ballast; storm canvas, planking, pumps |
| **Ice resistance** (new) | Ice | ARC: 50; later `arctic-passage` and the far south: 70 | Sheathing, Hold Frames, Anchor; a new ram / ice bow; small strong hulls |
| **Current strength** (new) | Strong currents against you | SOU-CAPE: 20, PHI-JP: 25, NRT-OPEN and STH-OPEN: 50 | Sails, Rudder, Anchor; the Handling skill line |
| **Light wind** (new) | Seas with no wind | NOR-DOL: 20, IND-E: 20, PHI: 35 | Headsails, Sails; oared ships; the skill LIGHT_AIR (it exists) |

- **No oar-only sea.** Where the reference game asks rowing, only galleys pass. "Light wind" can be met by oars OR sails, so a company never
  needs one ship type.
- **Europe asks none of the three**, White and Barents Seas included, so the start stays open (rung 1, 89 harbours).
- **The Cape asks one**, and it is on the way to India and Asia. A figure there no rung-2 ship can meet would close 100+ harbours.

### 3.3 What the builder must hold

- **One rule.** The new asks are columns on `sea_zones`, read by the one `public.sea_refusal`; the fleet's figures are averages through
  `world.ship_stat`, as `fleet_wave` is. No second gate. `sea_floor` and `pass-home` (0513) must cover the new asks too.
- **Reachability is re-proved** with them (254 harbours; the counts of plan 0.1), on hulls a company of that rung can own.
- **Do not ship the figures above unchecked:** the stat of each hull and gear piece has not been derived, so whether a ship can meet them
  is NOT known. Derive hull figures first, as 0215 did for wave, then set the asks.
- `seas-by-continent` (0510) and the relight do not wait for this. Slice: **`sea-asks-more`**, after 0514, dark.

## 4. The whole deck, verbatim

Line breaks inside a paragraph are spaces here.

### Slide 1

> HQ can be assigned on any city. It can be assigned in any country anywhere.
> Each city has special perks – refer to city perks

### Slide 2

> CITY PERKS (each HQ city gives its perk to your whole company – kinds and numbers PROPOSED)
> 
> Every city has 1 perk, decided by what kind of city it is. You receive the perk only while you have an HQ there.
> CAPITAL CITY – (your first HQ) EXPEDITION reports are made here. REPUTATION POINTS +5%.
> TRADE CITY (ex. Venice, Antwerp, Malacca) – bargain success +5%.
> PORT CITY (ex. Gibraltar, Cape Town, Colombo) – food and water cost 20% less.
> SHIPYARD CITY (ex. Amsterdam, Portsmouth) – ship repair cost 15% less.
> CRAFT CITY (ex. Genoa, Nagasaki) – PTG need 10% less material.
> MILITARY CITY (ex. Valletta, Muscat) – COMBAT attack +5%.
> EXPLORER CITY (ex. Seville, Reykjavik) – MAP radius +10%.
> FINANCE CITY (ex. London, Livorno) – dividend +5%.
> 
> The same kind of perk does not add up twice. Two HQs in TRADE CITIES still give 1 TRADE perk, so you should
> open HQs in different kinds of cities. The perk must be shown before you open the HQ.

### Slide 3

> HQ PAGE
> [SYMBOL] COMPANY NAME – you can change it. When creating the account for the first time, it will ask you to assign a company name. It should not overlap with any other names(countries, trade goods, and with other playerinfo, no 특수문자). After that you can change your name again for free (1st time), but later if you want to, you willhave to pay(real money currency – not decided yet).Then you will choose your home COUNTRY (EUROPE), and your first HQ will be in your CAPITAL CITY.  
> Below the COMPANY NAME, there should be info on how much income you receive, how much maintenance itcosts, etc. 
> [[RED: Right now my account does not have a designated HQ. I need a way to restart the game.]]The income info should include Active income  – fleets, trading/ gold per hour.                                           Passive income – your income based on your investments on other cities – dividendMANAGING – your income management tab, where you manage FLEETS, EXPEDITION(land or sea), INVESTMENT
> FLEETS – you can either choose between 3 actions – COMBAT, EXPEDITION, TRADING
> TRADING – Active: You will choose a good, buy, and sell at different city. Or you can transport the trade goods to other citiesthat are needed(mission) for profit & REPUTATION. For transportation, the quantity of the trade goods matter. The higher tradequantity, the higher REPUTATION POINTS. For profits you will have to choose cities that pay the most, and REPUTATION POINTS willbe earned when the profit rate is higher(profit% + total overall price).Some trade goods can be combined to create PREMIUM TRADE GOODS. Each PREMIUM TRADE GOOD(PTG) will be needed by one city only,and it will pay 300~500% more. PREMIUM TRADE GOODS by themselves costs more. 1 PTG linked with 1 city.
> EXPEDITION – is where you visit certain location(sea and land), find architect, report to your CAPITAL CITY for rewards(GOLD) and REPUTATION POINTS(RP).
> COMBAT – is where you send FLEET for combat – PIRATES. Winning will provide you with GOLD and RP. 
> [FLAG] CITY NAME – by clicking the city name, you can change cities that have your HQ. The whole HQ screen willchange according to what city you’ve chosen. Top left corner below company name.

### Slide 4

> HQ – OPENING MORE (numbers PROPOSED)
> 
> Your first HQ is free, in your CAPITAL CITY. More HQs are opened by TOTAL LEVEL, GOLD, and REPUTATION.
> A FLEET of yours should be in that city, and you must be able to enter that SEA.
> 
> HQ 2 – total level 30, 50,000 gold, 300 RP
> HQ 3 – total level 65, 250,000 gold, 1,200 RP
> HQ 4 – total level 120, 1,500,000 gold, 5,000 RP
> HQ 5 – total level 160, 4,000,000 gold, 10,000 RP
> [[RED: The specific requirement will be set by me after reviewing all the contents that has been made.]]
> 
> Each HQ has its own WAREHOUSE, PTG manufacturing, and CITY PERK. GOLD, RP, and LEVELS are shared
> by the company.
> CITY LIST – when you tap [FLAG] CITY NAME, it shows only the cities that have your HQ. The last line is
> OPEN HQ, with what you still need.

### Slide 5

> HQ – INCOME INFO AND MANAGING (details PROPOSED)
> 
> Below the COMPANY NAME:
> ACTIVE + gold / hour – fleets, trading, combat, expedition
> PASSIVE + gold / hour – dividend from your investments
> MAINTENANCE – gold / hour – crew wages, captain wages, ship upkeep
> TOTAL = ACTIVE + PASSIVE – MAINTENANCE. Tap a number to see why.
> 
> MANAGING has 3 lists:
> FLEETS – name, where it is, what it is doing, gold / hour. Tap to choose COMBAT, EXPEDITION, TRADING.
> EXPEDITION – land or sea, where, time left, what was found.
> INVESTMENT – city name, gold invested, dividend / hour. Paid every hour. Tap to invest more.
> 
> If a FLEET stops, it says why in plain words, with 1 button to fix it (REPAIR, HIRE CREW, BUY FOOD).

### Slide 6

> EXPEDITION AND COMBAT (details PROPOSED)
> 
> EXPEDITION: choose a site, send the FLEET, find the artifact, carry it home, report to your CAPITAL CITY.
> [[RED: - This is like combat, where it has log. It will show activities. The activity uses provisions, crews (death). The activity however when you’re level is high enough, will provide provisions. So it is give and take actions. Crews will die, but the rate will be determined by the level. Once you hit the MIN or the setted crew number, it will stop and return to nearest city with its goods. Expedition will give you gold, reputation. Also artifacts(uncommon - very rare) that can be given to the capital, for gold + reputation + special gear/ship(will add later)]]
> SEA SITE – shipwreck, island, strait. You need a FLEET, food, water, and crew.
> LAND SITE – ruins, temple, tomb, mine. Your crew goes on land from the nearest city.
> [[RED: This will be like rs3 maldevor idle game. But instead you will take provisions and crews. Create a expedition with captains. How many crews you can assemble depends on your combat level. The more crew you have, the more provision you can carry -> the more dungeon raids, mining, woodcutting etc. can be done. Each captains will have levels like RS3, where you will be able level up by doing a designated work. First you will start with 2 captains, and later with levels and reputation, as well as gold, you will be able to unlock more captains. The captains can be used to send on land sites, or it can even be assigned to a fleet – ship, and give perks. The land site expedition in addition should give another currency called HONOR BADGE – where you can use to upgrade CAPTAINS.]]
> The artifact takes cargo space. You are rewarded GOLD and RP only when you report it.
> Harder SEA = better sites. A site's level is the level of its SEA.
> The first company to report a site gets double RP.
> 
> COMBAT: choose a SEA, see the PIRATE's level and your chance of winning, then send the FLEET.
> [[RED: Yes that is good, but rather than chance of winning, it will show you the consumed ammo, provision and crew. For example you will send fleet to that sea, destroy the pirates – that is one round. Per round provision/crew will be lost, and in order to repeat and do the sea battles for a longer time, you will need to level up related skills. If provision is at its min, you will return to the nearest city and restock, then decided to repeat or go. The combat also gives the same benefits of expedition – gold and reputation. But in combat, honor badge is not gained but wrecks – ships and gears, that can be gathered and be used to make, upgrade ships and gears.]]
> WIN – GOLD, RP, some of the pirate's cargo. Higher level pirates give more.
> LOSE – ships damaged, crew die, some cargo is taken. The FLEET goes to the nearest city.
> RUN – chance depends on your speed and EVASION skill against theirs.
> [[RED: This is only where you don’t want to do combat – such as trading or even expedition. ]]
> RP is not lost for losing or running.

### Slide 7

> PREMIUM TRADE GOODS – LIST (first 12, cities PROPOSED)
> 
> Combined in your HQ. Pays 3~5 times in its 1 city, normal price in any other. Each city has a daily limit.
> Venetian Mirrors (3 Glass + 1 Tin + 1 Silver) – Istanbul
> Flanders Lace (2 Yarn + 1 Linen) – London
> Azulejos (3 Clay + 1 Tin + 1 Sand + 1 Cobalt Blue) – Salvador
> Sherry (3 Wine + 1 Gypsum) – Bristol
> Carpets (3 Yarn + 1 Madder + 1 Indigo) – Amsterdam
> Cigars (3 Tobacco + 1 Fresh Water) – Seville
> Whisky (3 Malt + 1 Fresh Water) – New York
> Dhaka Muslin (4 Raw Cotton + 1 Fresh Water) – Hormuz
> Canton Enamel (1 Glass + 2 Copper + 1 Tin + 1 Cobalt Blue) – Surat
> Nishijin Brocade (3 Raw Silk + 1 Gold + 1 Cochineal + 1 Indigo) – Macau
> Katana (2 Steel Billets + 1 Sea Coal + 1 Fresh Water + 1 Timber) – Ayutthaya
> Porcelain (2 Clay + 1 Feldspar + 1 Quartz) – Lisbon
> PROPOSED: far cities pay closer to 5 times, near cities closer to 3 times. – [[RED: YES]]
> 
> [[RED: We already have premium trade goods no? a list of trade goods that are built by combining? No? if so, reuse what we have if not, make new.]]

### Slide 8

> TRADING
> 
> ACTIVE METHOD: You search for trade goods on your own. Finding a trade good that has lower prices, selling them high.
> Or you can combine in your HQ, manufacture PTG and sell them at a designated city.
> PASSIVE METHOD: You can order your fleet to do a repeated task – buy at a city, sell at this city. You can choose to stop or continue based on your settings.Settings include buying at a certain price range, selling at a certain price range. etc. However, PASSIVE METHOD will have restrictions and require higher LEVELS and SKILLS.
>  
> THE TRADE TAB is for ACTIVE TRADING. At the trade tab, it will show your FLEET name, and you can change your FLEET by tapping the name to trade on different location per FLEET.
> In the trade tab there should be a map, showing no NPCs but only locations, where you can click them for info – price info.
> 
> The MAP itself will be black, and your fleet will provide a radius that will show you nearby map(cities, location etc.). The radius will be larger based on your NAVIGATION SKILL.But the location you’ve visited (city, sites etc) will show like a grey map, where you can tab on that city to not see the info, but to go there. The MAP will be completely black, but where your fleets moved and been will be in grey, showing lands partly(transparent.)
> 
> 
> The VOYAGE is a action of going out to sea / land. You will need PROVISON(FOOD+WATER+CREW) as a core source. The CARGO SPACE based on your FLEET(up to 8 SHIPS) will also holdtrade goods as well as your PROVISIONs. The FLEET will have a crew slot too(based on your ships) – the crew slot will have min and max. You will need to fill up your crew to min to operate fully(full potential of ship – fleet)
> However, during voyage – if you meet a storm, or other HAPPENINGs at sea, your crewmates will die. So it is advisable to appoint appropriate amount of crew. These Happenings may lose your trade goods too(1~2% per happening)
> IF NO FOOD or WATER is given, crews may cause RIOT – causing dramatic decrease in crew numbers.IF crew numbers are below MIN, the ship speed will decrease dramatically.  
> 
> The SEA will have names. And some SEA will have higher level pirates, and higher expedition sites. Some seas will require 내파, 등(대항해시대 참조), that will require you to gear up your ship overall to increase the 내파, 등. If you do not meet the requirement, you will not be able to pass into that sea. The whole cities should be reachable, but the game should sea into parts – real life basis, and will add restriction. For example from Brazil to Korea, you cancross the atlantic ocean(left vast sea? Not 100% sure of the name), but that route will be sealed(requiring levels, and 내파 등), which you will have to go around through INDIA to reach KOREA.
> The PASSIVE METHOD should also require you to make provision, crew up in the setting. The provision will be spent more with the number of crews. Since Provision takes a cargo space, to maximize trade profit you will have to choosethe appropriate amount of provision, crew. Design the game so that you can reach all the places of the world, but due to restrictions of the sea, you will have to go around. For example one can go over Russia near antartica(north), or antartica(south) as a shortcut but thesetwo routes will require significant levels in Sailing and ship gear. 
> 
> For both Active and Passive methods, when you choose the final destination of the city you want to visit, the game itself will choose appropriate paths to reach that city, by visiting multiple cities for provision+crew, fix ships etc. 
> 
> 
> 
> 

### Slide 9

> TRADING – PASSIVE METHOD SETTINGS (details PROPOSED)
> 
> Opens at TRADING LEVEL 3. The number of FLEETS that can trade passively grows with TRADING:
> Level 3 – 1 fleet, 5 – 2, 8 – 3, 11 – 4, 14 – 5, 17 – 6
> [[RED: NOPE, trading levels will give benefits when trading, such as +% increase in overall profits, bargaining success rate, etc.]]
> [[RED: There will be a new level, skill called management. This skill will enable to control fleets. You will be able to control fleets from the start of the game, as long as you have fleet/]]
> 
> SETTINGS for each FLEET:
> GOOD, BUY CITY, SELL CITY
> BUY UNDER (price), SELL OVER (price)
> CREW, FOOD + WATER (days) – it shows how much cargo space is left
> REPEAT – forever, or a number of times
> STOP – when the profit is under what you set, or the ship is damaged more than what you set
> BARGAIN – needs a higher NEGOTIATION level (level 8 – 3 tries, 12 – 6 tries, 16 – 10 tries)
> 
> If the price is out of your range, the FLEET waits and tells you why.

### Slide 10

> MAP AND TRADE TAB (details PROPOSED)
> 
> BLACK – you have never been there. No land, no city is shown.
> GREY – you have been there. Land is partly shown (transparent). You can tap a city to go there, but no price info.
> BRIGHT – inside your FLEET's radius. Tap a city for price info.
> A city that has your HQ is always BRIGHT.
> 
> RADIUS = 150 nautical miles + 50 for each NAVIGATION level. The EXPLORER CITY perk adds more.
> 
> TRADE TAB: FLEET name on top (tap to change) > MAP > tap a city > trade goods, price, how many, tax
> > BUY, SELL or GO. When selling, it shows BOUGHT price, SELL price, TAX, PROFIT.
> When you tap GO, it shows the path, the days, food + water needed, and crew. No NPCs on this map.

### Slide 11

> VOYAGE – PROVISION, CREW, HAPPENINGS (numbers PROPOSED, goods lost 1~2% is decided)
> 
> CARGO SPACE = trade goods + food + water. More crew eats more, so less space for trade goods.
> CREW – MIN: full speed, full power. MAX: the most you can carry. Extra crew is for those who die on the way.
> BELOW MIN – speed = crew / MIN (ex. MIN 40, crew 20 = half the speed). Never under 30%.
> 
> STORM – crew 2~5% die, trade goods 1~2% lost, ship damaged
> SICKNESS – crew 2~5% die. Fewer with a surgeon.
> FIRE, LEAK – crew 2~5% die, trade goods 1~2% lost, ship damaged
> RATS – food 5% lost, trade goods 1~2% lost
> CALM – nothing lost, but more days, so more food and water
> PIRATES – fight or run (refer to COMBAT)
> 
> RIOT (no food or no water) – each day crew –15%, trade goods –5%. Some goods are lost, never all.
> If crew falls under a quarter of MIN, the FLEET goes to the nearest city with what is left.

### Slide 12

> SEA – BY CONTINENT (the order is decided, levels and 내파 are PROPOSED)
> 
> You start in EUROPE. The level is the lower of your TRADING and EXPLORATION level. 내파 is the FLEET's average.
> 
> 1. EUROPE – level 1, 내파 0~12 (Mediterranean, North Sea, Baltic Sea, Black Sea)
> 2. AFRICA – level 2, 내파 12, the Cape 44 (Canary, Gulf of Guinea, the Cape, East Africa)
> 3. USA – level 3, 내파 20, straight across 30 (Caribbean Sea, Gulf of Mexico, American shore)
> 4. BRAZIL – level 4, 내파 20 (Brazil and the Plate)
> 5. INDIA – level 5, 내파 44 by the Cape (Red Sea, Persian Gulf, Arabian Sea, Bay of Bengal)
> 6. ASIA – level 6, 내파 44 by the Cape (Malacca, South China Sea, Yellow Sea, Korea Strait)
> 7. AUSTRALIA – level 7, 내파 44~56 (Timor Sea, Tasman Sea)
> 8. SEALED – level 8, 내파 up to 70 (Pacific Ocean, Arctic Ocean, the far south)[[RED: GOOD, hange 내파 to English, and add more restrictions like 내파. Like uncharted island. Do a research if you don’t know.]]
> 
> The vast sea on the left of America is the PACIFIC OCEAN. Pirates and sites have the same level as their SEA.
> A FLEET can always sail back home, even if it does not meet the requirement.

### Slide 13

> SEA – GOING AROUND, SHORTCUT, GEAR (details PROPOSED)
> 
> GOING AROUND – BRAZIL to KOREA: Brazil > the Cape > India > Malacca > South China Sea > Korea. Level 6.
> SHORTCUTS (level 8): PACIFIC – 내파 70. ARCTIC (north, over Russia) and ANTARCTIC (south) – 70 or more.
> In the game now, north of Russia and the far south are closed by ice. These two need new sea paths.
> 
> HOW TO INCREASE 내파 – bigger ships, anchor, planking, sheathing, storm sails, pumps, ballast.
> One small ship will lower the whole FLEET's average, so the whole FLEET should be geared up.
> 
> [[RED: See the previous powerpoint, and see what you need to add further. ]]
> 
> AUTO PATH – when you choose the final city, the game:
> 1. removes the SEAs you cannot enter
> 2. finds the shortest path left
> 3. adds cities to stop at before food or water runs out
> 4. at each stop: buys food + water, hires crew up to your setting, repairs the ship if needed
> 5. shows the path, days, and cost before you press GO
> If there is no path, it says which SEA is closed and what is needed (level or 내파).

### Slide 14

> TRADING
> 
> Trade goods price will grow in accordance with the distance between the two cities. You can bargain 10 times for price reduction or increase when selling. The success rate will decrease everytime you attempt.Each time you attempt will create 5% of total price reduction. This will also be enhanced by captains, and skills(level) – I am thinking NEGOTIATION skill.
> 
> TAX
> Each city will have its own tax, with 0%~30%. Your own country or the city that has your HQ will provide less tax. TAX is only payed when only a profit is made, or when buying.
> 

### Slide 15

> BARGAIN (details PROPOSED)
> 
> Up to 10 tries for each good, in each city, each day. Buying or selling – one side only per day.
> Each SUCCESS = 5% of the total price. A FAILED try costs nothing, but it uses 1 try.
> SUCCESS RATE – first try 25%, and every try is half of the last one.
> NEGOTIATION skill, captains, and the TRADE CITY perk raise the first try, up to 50%.
> 
> ex. 1,000 gold of pepper, 2 successes when buying = you pay 900. 2 successes when selling = you receive 1,100.
> 
> You should not be able to bargain, buy, and sell at the same city for profit. A good bought in a city cannot be
> sold there on the same day for more than you paid.
> 
> DISTANCE PRICE – the further the two cities, the higher the price. Distance is the path sailed.

### Slide 16

> TAX – DETAILS (details PROPOSED)
> 
> SELLING – 0~30% of the PROFIT only. No profit = no tax.
> BUYING – 0~3% of the price.
> LESS TAX – your own COUNTRY: half. The city that has your HQ: half. Not both at once.
> 
> ex. Bought for 1,000, sold for 1,500 in a 20% city. PROFIT 500 = tax 100. With your HQ there = tax 50.
> Sold for 900 = no tax.
> 
> The tax goes to that city's gold. Tax is always shown before you press BUY or SELL.

### Slide 17

> LEVELS AND SKILLS (PROPOSED)
> 
> TRADING – earned by buying and selling. Opens PASSIVE fleets, SEAs.
> EXPLORATION – earned by new cities, expeditions. Opens SEAs, sites.
> COMBAT – earned by beating pirates. More attack, higher pirates.
> NAVIGATION – earned by sailing. Larger MAP radius, more speed.
> NEGOTIATION – earned by bargaining. Higher success rate, PASSIVE bargain.
> EVASION – earned by running away. Higher chance to run.
> SHIPBUILDING – earned by building and repairing. Less MAINTENANCE.
> TOTAL LEVEL – all levels added. Opens HQs and crew slots.
> 
> REPUTATION POINTS are earned by missions (quantity), profit (profit% + total price), EXPEDITION, COMBAT.
> They are spent on HQs, crew slots, and captain skills. RP does not go down for bad actions.

### Slide 18

> NOT DECIDED YET (your answer needed)
> 
> 1. The price of changing the company name after the free change (real money).
> 2. What happens to a company with all ships wrecked and not enough gold to repair.
> 3. A one-time payment to a company that is already stuck.
> 4. Everything marked PROPOSED in this file.
