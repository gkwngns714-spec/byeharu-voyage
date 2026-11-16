# Content plan, November 2026: why there is nothing to do, and what to build

The owner, 2026-11-16: *"this game is not playable in terms of contents - nothing to do. do a research on this, and come up with solution"*.

**Status: research and a plan. No code, no migration, no knob was changed.** Every choice marked **default** was decided without asking; the owner may reverse it.

How each statement below is known, marked where it matters:
**(M)** measured on production today, read-only. **(P)** played by me on a local build. **(R)** read in the code or the docs. **(S)** from a cited source. **(J)** my judgment.

---

## 1. Summary (two minutes)

**The finding.** The world is rich. The player's part in it is one small loop: buy what the card says, sail, sell. It works, and it pays from the second minute. But nothing can go wrong in it, the money it earns buys nothing, and nothing needs the player back. Most other systems (the fight, gear, captains, skills, shares, requests, 157 hulls) are built and have no job.

**A correction first.** Production does not have 19 players. **One** company plays (M). Four other logins came once and never sailed (M). The other fourteen have no login: by every sign they are test companies the migrations made (J). So there is no churn to read. The evidence is that one company's record, my own play, and the genre.

**Four reasons there is nothing to do.**

| # | Reason | The evidence, in short |
|---|---|---|
| 1 | **One loop, and the card plays it for you.** | (P) One choice a trip: which card. 50 of my first 60 minutes were at sea with nothing to decide. (M) The one company: 123 voyages, 29 trades, almost nothing else in three months. |
| 2 | **Nothing can go wrong.** | (M) 2,339 pirate raids in 48 hours, none on a company. No company has ever been in a fight. (R) `public.raid_target` takes the world's ships first. |
| 3 | **Money buys nothing.** | (M) The one company has sat on 0.8 to 2.1 million since October, with its starter ship. (P) A ship cannot be bought: the second one is an 85-minute errand, and the planned trip sails past its own materials. |
| 4 | **No reason to come back, nobody to beat.** | (P) The route that trades by itself works, but it is the last row of the screen and nothing tells you on return what it earned. (M) City requests ask for 31,000 units on average; a new ship carries 200 to 300. (P) The Rank board holds the player and test companies; the 845 merchant houses are not on it. |

**What to build, in order of fun for the work** (section 5 has each one in full).

| Rank | What | Size | In one line |
|---|---|---|---|
| 1 | **Pirates raid companies too** | S | The known fix, with a beginner's peace and a knob. Wakes eight sleeping systems at once. |
| 2 | **A route in reach, and a report on return** | S | The game already sails a route by itself. Offer it on the arrival card, and say on return what it earned. Client only. |
| 3 | **The yard takes an order** | M | Pay coin, wait real hours, launch the ship. Money gets a use, and the player gets something to come back for. |
| 4 | **Requests a ship can carry** | S-M | Each harbour posts jobs sized for a hold, with a deadline in hours and a clear total. |
| 5 | **The houses' board** | S-M | Rank the company among the 845 merchant houses, by week. Take the test companies off. |
| 6 | **The logbook** | M | Counts of harbours, goods, seas, hulls, captains. Sets pay once. It counts; it asks nothing. |
| 7 | **Bounties on named pirates** | M | Countries pay for the pirates that robbed them. Needs 1 and 3 first. |
| 8 | **World events on the fair's rails** | M | Famine, blockade, festival: named, timed, in the news, on the map. |
| 9 | **Each level opens something** | S each | Levels now pay Reputation and little else. Give each a real unlock. |
| 10 | Goods mastery, choices at sea, player workshops | M-L | Later. |

**The first three slices: 1, 2 and 3.** Each is about a day. Together they make a second game on top of the first: a ship that earns while you are away (2), a danger to it (1), and a yard that turns what it earned into the next ship (3). Number 4 follows at once: it gives the ship you sail by hand somewhere to go.

**What not to build now:** quests and guides (the owner's order, and they are used once); daily rewards and streaks; guilds or PvP (one player); more goods, harbours or hulls (there are 629, 254 and 157); more NPC fleets (costs the database, and the player cannot feel it).

---

## 2. What the live game's record says (M)

Read-only, the gate read first (green: beat 122 ms, 797 MB, no disk waits). Then five small reads, one statement each, by index or over a small table. They are listed in the appendix. No names were read.

### 2.1 Who is there

| Group | Count | What they are | What they did |
|---|---|---|---|
| A company that plays | 1 | The oldest company (22 August). Its login was last refreshed today. | 123 voyages, 47 harbours, 115,000 miles, 13 buys, 16 sells. Trading 15, Exploration 10, Combat 1. |
| Logins that came once | 4 | Made 14, 15, 15 and 21 October. None was seen again after the day following its making. | Three: founded a company and nothing else, ever. One: founded, bought one thing 14 seconds later, nothing else. None ever sailed. |
| Test companies | 14 | No login exists for them. Made in clusters, several in the same minute, each with one kind of act (one study, one build, one fitting). The local world image holds 13 companies of the same pattern. | Nothing since their probe. |

I cannot tell whether the four one-day logins were other people or test sign-ups from another device. Either way: **nobody but company 1 has ever finished a voyage on the live game.**

Earlier documents counted these as 19 players. `docs/SECOND_SHIP.md` says three of the 19 hold two hulls: all three are test companies.

### 2.2 The one company that plays

- It played most on 20-21 October and 26-30 October (6 to 29 voyages a day, at most 7 trades a day).
- **Its last voyage ended on 30 October.** In the 17 days since, it did three things: hired crew (5 November), bought one cargo for 1,244,492 (12 November), bought a slot for 60,000 (14 November). It has not left port.
- So the pirates that strike (15 November), the tick fight, the levels raised by doing, Evasion: **no company's ship has met any of them.** No company holds one point of experience in the eight levels granted by doing (Supplies to Evasion), and none holds any Reputation.
- What it holds: 799,973 coin, one fleet, one ship (the starter barca), no captain, no shares, no skill trained, one route with 0 laps, 4 item rows.
- What it never did, in three months: build a ship, fit gear, craft, study a skill, invest, deliver a request, fight, or be raided.

This is one person's record, and probably a builder's rather than a player's. It still says something plain: a company can reach Trading 15 with two million coin and find no use for it.

### 2.3 The world around it

- (M, the lead's read today) 2,339 raids closed in 48 hours, none on a company. No company voyage ended in 7 days.
- (R) Why: `public.raid_target` sorts the ships near a pirate with `order by public.fleet_kind(c.id) = 'COMPANY', c.nm` and looks at the first 8. A company's ship is reached only when fewer than eight of the world's ships are within about 360 miles of that pirate. With about 900 of them at sea, that is almost never. The line was written to the owner's words: *"pirates' main goal is to attack other npcs"*.
- (M) City requests: 751 open at 252 harbours. Median bonus 123,708 coin. **Average size 31,367 units.** None was delivered by a company. 888 expired ones are on the books, all made between 11 and 13 November. They are sized by the city's budget, not by a ship.
- (M) Every switch is lit on production except `pirate_strike_from_port`. The default local world has twenty of them dark (section 3.1).

---

## 3. What playing it is like (P)

### 3.1 How I played, and the limits

A local build (no cloud keys), headless, 390 x 844, on port 4477. Three worlds:

| World | What it is | Used for |
|---|---|---|
| A. The shipped local world | What CI and the specs use. Twenty of production's switches are dark in it: no merchants at sea, no city purses, no sea rules. | First look, the screens. |
| B. Production-like | A copy with the purses lit, the economy closed, production's switches (all but the navy's and the cargo ships', which no local job runs), 120 merchants at sea, city wants drawn, requests posted. Built with the chain's own switch functions. | The first 10 minutes and the first hour, as a new company with 40,000. |
| C. Rich | World B with 3,000,000 to start. | The middle of the game: every place coin can go. |

Limits, stated plainly:
- **I did not fight.** The local build runs no pirate job, so no raid can happen in it. The fight's verbs below are read from `docs/design/tick-combat.md`, not played.
- Prices do not drift locally and there is no navy, no cargo ship, no pirate. The world I played is quieter than production.
- World A misleads: its cards promised +22,416 for a trade that paid +617. In world B the card, the plan and the result agreed (+6,792, +6,792, +7,142). I did not find the cause. Earlier playtests on the default world may have judged the cards by this fault.
- A local world founds its company by itself. I saw the founding screen only in the gallery, and the sign-in screen not at all.

### 3.2 The first 10 minutes (world B, timed)

| Clock | What happened |
|---|---|
| 0:00 | Open. The world is ready in 9 seconds. The Trade screen: ten goods cards, eight city chips, a goal card ("Mate · Second ship 0 / 4"). |
| 0:20 | The Black Pepper card says "Setubal +6,792 · 58s". Buy, Max, Buy: 290 units for 39,925. |
| 0:30 | Press the card's sale line, then "Sail & sell". The plan lists time, wages, dock fee, tax, profit. |
| 1:58 | Arrived. **Profit +7,142.** Trading 2, Exploration 2, +93 Reputation, new title. |
| 2:32 | Slow Match for Porto, +3,966. Sailed at 2:42. |
| 7:43 | Arrived. Profit +4,221. Trading 4. |
| 8:45 | Dyer's Broom back to Setubal. Sailed at 8:54. |
| 10:00 | Still at sea. Worth about 50,800 in coin and cargo, from 40,000. |

- **It works, and it pays early.** First profit before the second minute. That part is good.
- **About 7.5 of the 10 minutes were at sea.** While she sails there is nothing to press that matters. The board shows the next harbour's goods, greyed: "Money 3,344 / 35,442".
- **One decision a trip.** Which card. The card has already chosen the city and done the sum.
- A trip is about 5 presses. Ten minutes held 3 buys, 3 sailings, 2 arrivals.
- Levels fly: Trading 6 by minute 17. Each paid Reputation (it buys captain skills, and I had no captain) and moved my title along (it opens far seas I had no reason to enter yet). Nothing I could use that hour.

### 3.3 The first hour (world B)

A script played the rest of the hour as a greedy new player: at each port take the card with the best profit a minute among sales under 15 minutes, buy the most, sail, sell.

| By minute | Trips finished | Coin after the last sale | Trading level |
|---|---|---|---|
| 10 | 2 | 50,758 | 4 |
| 20 | 4 | 59,632 | 6 |
| 30 | 6 | 68,921 | 8 |
| 40 | 8 | 80,683 | 9 |
| 50 | 12 | 99,199 | 11 |
| 60 | 16 | 105,122 | 13 |

- **16 trips in the hour. 50 of the 60 minutes were at sea** (84 %). The rest was about five presses a trip. (Twice my script stalled for two minutes in port; that is its fault, not the game's.)
- **One kind of decision, 16 times.** Which card.
- **40,000 became 105,000.** A trip paid 800 to 13,400, about 4,700 on average. One plan was wrong: it promised +2,528 at Seville and the card said +797.
- **Three harbours for the first 35 minutes** (Lisbon, Setubal, Porto, round and round). Then the best cards led south: Seville, Sanlucar, Ceuta, Tangier, Gibraltar. Eight harbours in the hour. That was the hour's only change of scene, and nothing marked it but "New port" on the card.
- **The cards that pay most are far away**: Riga +75,366 in 45 minutes, Zakynthos +15,146 in 29, Thessaloniki +15,517 in 36. One press, then half an hour or more with nothing to do. My script never took one.
- **Nothing happened.** No event, no threat, no rival, no new kind of thing. Minute 50 was minute 5 with a bigger purse. The goal card still read "Second ship 0 / 4".
- **Trading reached level 13 of 20** in one hour, and Reputation 1,459 with nothing to spend it on (no captain).
- The market does answer: my 80 Slow Match moved its price 5.6 %. That is the one thing that pushes a player to vary the cargo.

### 3.4 The wall at about minute 15: the second ship

The goal card says "Second ship 0 / 4" from the first screen. It is the only goal the game gives. I followed it in world C.

- The yard's sheet is clear: a barca needs Timber 40 (Funchal), Nails 10 (La Rochelle), Cordage 6 (Portsmouth), Tar 8 (Bergen). Total 17,589 coin. "Plan trip · 4 stops".
- Plan trip lays the route: Lisbon, Funchal, La Rochelle, Portsmouth, Bergen, Lisbon. **11.3 voyage-days: 85 real minutes.**
- I pressed Final and she sailed. Ten minutes later she reached Funchal, lay there about a minute, **and sailed on by herself.** The plan sails; it does not buy. I was reading the orders list and missed the timber. A player who trusts the plan and walks away gets an empty ship back in 85 minutes. (Each material's row also has its own "Buy at Funchal" button. I did not try that path.)
- The next ship up is worse. A Caravela's sheet lists 9 things to fetch or make and 238 tons of materials. A Nau's lists 10, among them Live Oak from Jamestown (3,083 miles) and masts from Boston, and 468 tons in a 180-ton hold.

So after a quarter of an hour the choice is: repeat the three-harbour loop, or spend an hour and a half on an errand that is easy to get wrong. **Coin cannot shorten it.** This is where I would have closed the tab.

### 3.5 With three million (world C)

| Where coin can go | What I found |
|---|---|
| A bigger cargo | The only thing coin does by itself. Quicksilver to Setubal read +32,775 for a 55-second hop. Profit grows with the purse until the hold is full (180 tons). |
| Shares in a city | 100,000 bought the Market's level 1 in Lisbon. The tray said "Invest 100,000" and nothing about what it pays. (R) It pays 1.8 % of the price a real day: 55 days to earn it back. It also gave +10 regard and "Portugal 100 %". |
| A captain | Seven at the inn, 3,500 to 7,500 a voyage; the faces change on a timer. An S-grade pilot gives +5.4 % speed, -9 % storm damage and eight more small figures. Good system. With no danger, most of what a captain protects against never happens. |
| Starter gear | Guns 800, sails 300, planking 150. Guns have nothing to shoot at. |
| Skills | 107 of them, five levels each, trained by time ("8.3 min" for the first), free, 50 in a queue, **"Trains while away"**. It lives at Trade, City, Skills. I found it at Lisbon and not at Setubal: (R) 35 of 254 harbours have an academy. |
| A ship | Not for sale. See 3.4. |
| Fleet room | A second fleet is free at Trading 3, which came inside the first eight minutes. More ships a fleet cost 10,000 to 160,000 or a skill. All of it waits on having a second ship. |
| Requests | Lisbon asked for 2,473 Ambergris, 11,717 Cassia, 53,504 Mirin, each "1,000,000 left". A price note, not a job. |
| A route | The one thing that plays by itself. See 3.6. |

**The ships, the fleets, the armada and the fight all wait behind one door, the second ship, and coin does not open it.**

### 3.6 The route: the part that plays by itself (world B, a fresh company)

The owner asked for this on 30 September: *"i set up route, trade routes - going back and forth, afk, running all the time"*. It is built, it is lit on production, and it works.

- **Where it is:** the last row of the Trade screen, "Route · No route", under ten goods cards. Nothing points at it.
- **Setting it took 40 seconds.** A form of two stops. At each: sell everything, buy one good, resupply if low. I chose pepper out of Lisbon and armillary spheres back from Setubal, and pressed Start route.
- **She did the rest alone.** Bought, sailed, sold, bought, came home. Lap 1: +6,684 in three and a half minutes, with its own account (sold, bought, supplies, wages).
- Then "Next lap 18:31", four hours on. (R) One lap may start each game day. The local game day is four hours; production's is five minutes (`docs/dev-log/2026-11-14-day-hour.md`). So I could not see what a route earns an hour as production would pay it.
- **Nothing greets you with it.** When I looked back in, the screen held the usual arrival card for her last landfall ("Arrived at Lisbon") and no word of the lap. The lap's profit shows on that last row, and (R) as a line in History, which I did not open.
- **With one ship, the route and my own hand are the same ship.** Once she is on a route there is nothing left for me to press at all. A route becomes a second layer only with a second ship.
- (M) Company 1 has one route and 0 laps. On 14 November the owner asked whether routes are still needed. My answer: it is the one part of the game that plays for the player while he is away. Keep it, and lead to it.

### 3.7 Every verb a player has

Time is real time. A voyage-day is 450 seconds; a new barca makes about 50 miles a real minute.

| Verb | Where | How long | The decision in it | What it pays | Where it goes dead |
|---|---|---|---|---|---|
| Buy | Trade card, Max, Buy | 5 s | Which good. The card shows its best sale and profit. | Cargo | The card decides. Stock (thousands) is far deeper than a hold. |
| Sail & sell | The card's sale line, then one button | 1-6 min near home; 20-45 min across Europe; 1-5 h overseas | None once pressed | 2,000 to 7,400 a trip on a new purse; Reputation; Trading and Exploration | Nothing to do at sea. |
| Sell here | Card, Sell | 5 s | None | Coin | |
| Haggle | In the tray | Not tried | | A better price | |
| Supplies | Bought with the sailing | 0 | None | | Never short on short hops. |
| Insure | A button in the plan | 1 press | Pay for cover or not | Cover against pirates | (M) No company has ever been raided. |
| "If attacked": Fight, Flee, Pay | The fleet's page | 1 press | A standing order | | Never triggered. |
| Fight: Broadside, Chain Shot, Rake, Grapeshot, Brace, Patch, Run, Pay | The battle screen | 13-72 s (R) | Real ones, on cooldowns, with a Fury bar | Loot, levels | (R, not played) Has not happened to a company. |
| Attack a ship | The map, a ship within 240 miles | (R) | Whom: weaker, even, stronger | 15 % of her cargo; -150 regard; wanted 48 h | A new barca has 0 guns. |
| Join / Watch a battle | The map's red ring | 13-72 s (R) | Which side | Not read what a joiner earns; a watcher earns nothing | Not tried. Watching has no stake in it. |
| Invest in a city | Trade, Invest | 3 presses | Which work; the tray shows only the price | 1.8 % a real day, regard, influence | The return is invisible and tiny beside trade. |
| Donate | Trade, Invest | | How much | Influence for your country | Not tried. |
| Build a ship | HQ, Port, Build | 85 min of errand for a barca, then instant | The route | A second hull | 3.4 |
| Starter gear | HQ, Port, Gear | 1 press | Which of three | +30 attack, +0.9 knots, +5 armour | One purchase. |
| Craft a fitting | Trade, City, Craft | Needs goods on board | Which of 228 | A fitting | (M) No login has ever made one. |
| Forge a good | HQ, Production | Instant | Which recipe | A dearer good | Not tried. (M) No login has. |
| Store goods | HQ, Production | Instant | | 750 tons at home | Only use I found: hull materials. |
| Hire a captain | The inn | 1 press | Which of 7 | Ten small bonuses | Little to protect against. |
| Hire crew | The inn | 1 press | How many | | |
| Train a skill | Trade, City, Skills | 8 min to days; runs while away | Which of 107 | +6 % a level; opens hulls | Hidden; nothing leads there. |
| Deliver a request | Market, Requests | | | +8 to 20 % over market | Sized for cities. |
| Place a request | Market, Requests | | Good, amount, price | A standing buy order | Not tried. |
| A standing route | Trade, the last row | 40 s to set; then laps run by themselves | Two stops, one good to buy at each | A lap's profit (+6,684 for mine), also while away | Nothing leads to it, there is no summary on return, and with one ship it replaces play instead of adding to it. |
| New fleet, buy room, armada | Fleets | 1 press; 10,000 to 1,000,000 | | Room | Needs ships. |
| Read: Levels, Report, History, Stats, Rank, Codex, the map's filters, a merchant's card | Everywhere | | None | Knowledge | Reading, not doing. Rich, though: a merchant's card shows her route, cargo, ships and captains. |

### 3.8 Where the loop goes dead

1. **At sea.** Every trip. Nothing to decide, nothing at stake.
2. **At minute 15.** The second ship is an errand coin cannot shorten.
3. **At the end of a session.** Unless I found the route, nothing is left running. If I did, nothing will greet me with what it earned.
4. **Tomorrow.** Nothing will have happened to me.
5. **Next week.** There is no board I am on, no race I am in, no set I am completing.

---

## 4. What comparable games do (S)

Three research passes with web search, about 550 searches and page reads between them. Each link below was opened by the pass that cites it. I re-opened ten of them myself and they matched (marked *). A seventh, Melvor Idle's wiki, refused my reader; the research pass had read it through the wiki's own interface. Fan wikis are named as such in section 8.

### 4.1 The mechanisms, and what this game has of each

| Mechanism | Who does it, and what it gives | This game today | The gap |
|---|---|---|---|
| **Jobs made by the simulation** | Patrician IV: selling into an empty market raises reputation; the town hall posts assignments from world events [P4]. EVE: courier contracts with a reward, a deadline and collateral [EVE-C]*; agents open by standing [EVE-A]. Pardus: mission boards refresh twice a day [PAR]. RuneScape's ports: three voyages offered, pick one, reroll 15 a day [POP]*. | City requests exist (`trade_contracts`). | Sized for cities, not ships. No total, no short deadline. |
| **Risk you can price** | EVE: insurance pays 40-100 % of the hull; "don't fly what you can't afford to lose" [EVE-I]. OGame: fleets are safe only in flight, so players choose when to be exposed [OG-B]. Pirates!: defeat is capture and ransom, not the end [SM]. | Insurance, ransom, standing orders, a full fight. | Nothing ever attacks a company. |
| **A sink with a timer** | OGame: players send fleets out for 4 to 12 hours, timed to their own return [OG-B]. EVE: the skill queue trains offline [EVE-S]. Prosperous Universe: production in real hours; "it's a slow game" [PU]. | A column `ship_classes.build_hours` exists, but a ship is built at once (`docs/SECOND_SHIP.md`). The skill queue exists. | No timer the player starts with coin. |
| **Reward for being away** | Melvor Idle: up to 24 h of offline progress and a summary on return [MEL-O]. Pecorella: progress while away makes "a celebratory moment every time you return" [IDLE]. | Skill training, routes, share coupons run while away. | No summary on return. Nothing leads a new company to any of the three. |
| **A ladder of ranks with a bar always in sight** | Patrician IV: rank by net wealth, bar on screen, ranks open verbs [P4]. Pirates!: a fame ledger of eight categories, 126 points, a retirement job by score [SM-F]. | Titles (11), levels (11), the goal card. | Levels pay only Reputation. No ledger of what you have done. |
| **Collections** | Old School RuneScape: a collection log of 1,925 slots with ranks [OSRS-C]; Jagex called shipping a feature without one "a mistake" [OSRS-F]*. Melvor: a completion log; players wear their % [MEL-C]. Uncharted Waters Online: discoveries reported for fame [UWO-R]. In one survey idle players' top motives were Completion and Power [QUEST]. | 254 harbours, 629 goods, 51 seas, 157 hulls, 105 captains. First landfalls pay Reputation. | Nothing counts them or shows a set. |
| **A level opens a thing** | RuneScape: Oak at 15, Willow at 30, Yew at 60; unlock levels get a jingle [OSRS-W]. Melvor: tools gated by level and coin [MEL-S]. Cook: players value a skill only "a couple atoms down the chain" [LG-C]. | `level_perks`: 1-5 % discounts at five of twenty levels. | Too small to feel. |
| **Rivals and boards** | Patrician: AI rivals copy your buildings and can be ruined [P4]. OGame: points for coin spent, not held, in several categories [OG-P]. | 845 merchant houses with purses and laps. A Rank board. | The houses are not on the board. Test companies are. |
| **Investment as the big sink and the race** | Uncharted Waters: New Horizons: invest in a port to open its specialty and ally it [NH]. Online: the nation that invests most holds the city; the top five investors get 10 to 2 % off customs; a monthly honorary mayor [UWO-I]*. The designers damped big spenders so a pool beats one rich player [UWO-D]. | **All built**: shares, influence by country, the top-five price shave, a mayor who sets tax. | The screen does not say what any of it pays. |
| **World events on a clock** | Online: sea feuds monthly, "sudden investment wars" lasting 4 hours [UWO-E]. Travian: artefacts held by NPC villages, to be taken at a known time [TV-A]. OGame: events are "multipliers for efforts you make anyway", but "only if you're prepared" [OG-E]*. | One: the Fair (a harbour's cut -30 % for 3.2 h, 12 % a day). News in 8 kinds. | One kind, and nothing announces it ahead. |
| **Huntable pirates** | Patrician IV: pirate clans with hideouts, a bounty a convoy [P4]. Port Royale 2: killing pirates repairs reputation with every nation [PR2]. | 121 pirate fleets, named, on a five-rank ladder, with a record of what each took (`fleet_book`). | Nobody pays for sinking one. |
| **Passive goals instead of tasks** | EVE's career program: 188 goals that "progress passively during normal gameplay"; nothing has to be accepted [EVE-AIR]*. Torn: 500 awards [TORN]. | | None. |

### 4.2 Rules worth keeping in view

- **Build loops, not arcs.** A loop is exercised again and again; "an arc is a broken loop you exit immediately" [LG-L]*. This is the case for the owner's "no quests yet": a quest is used once. Everything in section 5 is a loop.
- **Sinks a little larger than sources.** "Big pools reduce pull", and "big desirable sinks make it trivial to balance" an economy [LG-V]*. With no drain a world gets "Monty Haul syndrome" [KOS]*. Company 1 is the proof.
- **Ownership keeps players.** Koster calls it the "barrier to departure" [KOS]*. A second and a third ship are the cheapest ownership this game can give.
- **A new thing every few minutes at first.** One developer's rule of thumb: first upgrade under a minute, a new phase every 3-5 minutes of play [ID7]. Here the first hour holds one kind of thing.
- **Let the player choose the timer.** A ladder of waits (20 minutes, 5 hours, 2 days) lets each player set a rhythm [GUAN]. A wait the player chose is a promise the player made [APPT].
- **Do not make it a duty.** Jagex removed much of its daily content on 16 March 2026: content "perceived as mandatory" [DS]*. Torn's critic: "the waiting game", a "hamster wheel" [TORN-R]. So: no login rewards, no streaks.
- **Small worlds live on NPCs.** Kingdom of Loathing has a few hundred online, Pardus under a hundred [KOL][PAR]. The opposition, the jobs and the prices come from the simulation. This game's simulation is already stronger than theirs.

---

## 5. The plan

### 5.1 Five rules for choosing

1. **Use what is built.** The world already simulates the opposition. Point it at the player.
2. **A loop, never a script.** Nothing is asked once and thrown away.
3. **Coin must buy time or strength.** Every slice names its sink.
4. **Something must be running when the player leaves.**
5. **About zero new rows a minute.** A feature that acts only when a player presses costs the database nothing with one player and little with a hundred.

One thing I would leave alone: **the best-sale card.** The remaster added it by default so that a new player earns in the first minute, and it does that. The owner had said earlier that a list of where to sell "will be too easy" (row 229), and reason 1 above is that worry come true. I would still keep the card, **default**, and get depth from what a card cannot solve: a deadline, a danger, a rival, a set to finish. The owner may judge otherwise.

Sizes: **S** one migration or one client change, about a day. **M** a migration and a client slice, 2-3 days. **L** a week or more.

### 5.2 Ranked

| Rank | Feature | Size | New rows a minute | Needs first |
|---|---|---|---|---|
| 1 | Pirates raid companies too | S | 0 (same raids, other targets) | Nothing |
| 2 | A route in reach, and a report on return | S, client only | 0 | Nothing. Worth more after 3 |
| 3 | The yard takes an order | M | 0 (only on a press) | The owner's yes: it reverses a "no" |
| 4 | Requests a ship can carry | S-M | about +6 | Nothing |
| 5 | The houses' board | S-M | 0 (one small weekly settle) | Nothing |
| 6 | The logbook | M | 0 (a row at a first time only) | Nothing |
| 7 | Bounties on named pirates | M | under 1 | 1, and a ship with guns (3) |
| 8 | World events on the fair's rails | M | a few an hour | A read of the fair on production |
| 9 | Each level opens something | S each | 0 | Nothing |
| 10 | Goods mastery | M | 0 | 6 |
| later | Choices at sea | L | | |
| later | Player workshops and buildings | L | | Fittings must matter first (1) |

### 5.3 Each feature

#### 1. Pirates raid companies too (S)

**Pitch.** Today a pirate looks at the ships in reach and always takes a merchant of the world before a player's. Change one line: she takes the nearest, whoever owns it. A company under the title Master is passed over, so nobody is robbed in the first half hour or so (my script's company became a Master at minute 42). A knob can weigh a company's ship nearer or further, and another puts today's rule back. Nothing else is needed: the fight, the action bar, Run, Pay, the standing order, insurance and Evasion are all live and waiting.

**The loop it makes.** *Now:* before a loaded voyage: insure or not, fit guns or keep the hold, set Fight, Flee or Pay. (The insurance price already knows how dangerous a passage is; I did not check whether the map shows it. If not, the plan's tray should.) In the fight, 13 to 72 seconds of real choices. *This session:* (J) a raid should be rare near home and likelier on the long, rich hauls, because the pirates' five grounds are the open oceans. So risk grows with ambition. *This week:* Evasion and Combat finally rise; guns, armour, a surgeon and an escort ship become worth their price.

**Stands on.** `public.raid_target` (one hunk: its `order by`), `public.pirate_strike`, `public.pirate_strikes`, `public.battle_open`, `public.tick_fight`, `cmd.battle_act`, `cmd.raid_order`, `public.raid_close`, `public.fleet_peace_until`, `public.insure_voyage`, `public.title_level`, the Evasion level (0453).

**Load.** No new rows: the pirates open as many raids as today. A raid on a company writes its report and at most 2 level rows.

**Needs first.** Nothing. It alters live play: the 30-minute after-check (`scripts/ops/harness/raid/after-check.sh`), rollback by the knob.

**Honest limits.** The world sees about 49 raids an hour over about 900 ships (M, the lead's figures): by my division, one raid in 18 hours at sea for an average ship. With the nearest-wins rule a company will be raided about that often. That is rare. The weight knob is for that, and it is the owner's to turn. The slice measures raids on companies an hour at sea, before and after. Second: a voyage day's own raid still rolls the older rule in `public.fight_sides` (the lead's note); this slice leaves it. Third (R): the price of losing is small today. A boarded company pays a ransom of 8 % of her cargo's cost (`ransom_share`), and only as much as her purse holds, loses a tenth of her hands and takes hull damage; her ship is never wrecked (`public.raid_close`). A company with all its coin in cargo pays almost nothing. That is a gentle start, which is right for a first lighting. If it proves too gentle to be felt, the next step is that a plunder takes goods (a voyage day's raid already takes 25 to 50 %): the owner's knob.

#### 2. A route in reach, and a report on return (S, client only)

**Pitch.** Two small pieces on what is already built. First: when a trip there and back has made a profit, the arrival card offers **Repeat as a route**. One press makes the route from what she just did (3.6 took me 40 seconds by hand, once I had found the row). Second: **While you were away.** Open the game after ten minutes or more and one card says what happened: laps closed and what they earned, a skill finished, a ship ready at the yard, shares paid, a fair open in Porto. And a thin "ticking" line on Trade for what is running now, with its time.

**The loop it makes.** *Now:* the first thing that runs by itself, by about minute five. Idle games put their first automation in the first three minutes [ID7]. *This session:* tune the route from its lap account; choose which ship sails by hand and which by route. *Away:* it earns. *On return:* a small celebration instead of a blank [IDLE], and coin to spend (3). *This week:* more ships on more routes.

**Stands on.** `cmd.standing_route_save`, `cmd.standing_route_assign`, `cmd.standing_route_pause`, `world.standing_routes`, `standing_route_laps`, `world.route_board`; for the card: `world.ledger`, `skill_queue`, `city_shares.accrued`, `world.buffs`, later the yard orders of 3. The arrival card's parts can be reused.

**Load.** None new. A company's route writes what one of the 885 merchants' routes writes.

**Needs first.** Nothing. No migration, so it can merge beside the others. It is worth much more once a second ship is easy to get (3): then one ship earns on a route while the other is sailed by hand.

#### 3. The yard takes an order (M)

**Pitch.** Beside "Build", the yard gets "Order". Pay the whole price (labour, the materials at today's market, and a fee, **default** half again), and the yard builds the hull in real time: a barca in about half an hour, a caravel in two hours, a nau in eight, a great ship in a day. Then "Ready" and one press launches her. Bringing your own materials stays, stays instant and stays far cheaper: the errand becomes the thrifty way, not the only way. One order a yard at a time.

**The loop it makes.** *Now:* the purse has a use from minute 15: order the second barca for about 26,000, keep trading. *This session:* come back when she is ready: the game's first appointment, and the player chose it. *This week:* a fleet plan. Two ships, one of them on a route, then a gunned ship for the pirates. The yard's list runs from 10,000 to over 3 million in labour alone, so there is always a next one.

**Stands on.** `public.ship_classes.build_hours` (present; a ship is built at once today), `public.hull_recipes`, `world.yard_sources` (it already prices the whole build: "Total 17,589"), `public.yard_labour`, `cmd.do_build`, `public.commission_ship`, the city's purse (`public.pay_city`), the Shipbuilding level, hull skills. New: one small table of open orders (a row a company a yard; retention: a launched or cancelled order goes after 7 days), two doors (`cmd.order_hull`, `cmd.launch_hull`), keys on the yard's read.

**Load.** Rows only when a player presses. No job: an order is ready when the clock passes its time, and the launch is the player's press.

**Needs first.** The owner's word. `docs/SECOND_SHIP.md` weighed "a used hull for coin" and said no ("makes the yard a shop"). This is a dearer, slower order, not a shop shelf, and the materials path stays the better deal. **Default: yes, at +50 % and with the timer.** Merchants already get their hulls with no materials (`public.commission_ship`), so the rule of the world is not broken by it.

**Also fix, in the same slice or beside it:** the planned trip for a build sails past the materials (3.4). Either the plan carries the buy lines, or the ship waits at a stop where a material is still missing.

#### 4. Requests a ship can carry (S-M)

**Pitch.** A harbour's requests are sized by its budget: (M) 31,000 units on average, standing for days, shown (P) as a price a unit with "1,000,000 left". Nobody treats that as a job, and no company has delivered one. Keep those for the cargo ships. Add a second size: **each harbour also asks for one or two loads a small ship can carry** (say 20 to 150 tons), for a fixed total ("Bring 120 Wine · 9,400 · 2 h 10 m left"), with a deadline of two to six real hours so the board is different each session. Paid from the city's purse as today, plus Reputation and regard with its country. The Trade card of a good that some harbour in reach is asking for says so.

**The loop it makes.** *Now:* in any port, three lines answer "where shall I go": a job here, a job I can fill from here, or plain trade. *This session:* chain three or four; a job sends you to harbours the best-sale card never would (new landfalls, new goods). *This week:* the Requests level (built, 0 experience on production), regard with each country, and a running count of jobs done. Counted in jobs, not days, so a missed day costs nothing.

**Stands on.** `public.trade_contracts` (one new column for the size class), `public.contract_draw`, `public.tick_contracts`, `public.tick_contract_wind`, `public.contracts_expire`, `world.contracts`, `cmd.preview_fulfil`, `cmd.fulfil`, `public.reputation_request`, `public.regard_add`, the level `requests`, `world.best_sales` (to mark a card).

**Load.** The board already holds 3 a harbour and is re-asked by the existing job, 3 harbours a run. Shorter deadlines mean more turnover: about 254 x 2 jobs every 3 hours, with their expiry, is about +6 rows a minute. No new job, no new table.

**Needs first.** Nothing. **Default:** add the size beside the big requests; do not replace them.

**Is this a quest?** No. Nothing is written by hand and nothing is used once. It is the request board the game already has, at a size a player can use.

#### 5. The houses' board (S-M)

**Pitch.** Put the company on a board with the 845 merchant houses, by profit this week: "212th of 846 · next: Casa da Índia, +3,100 ahead". The week is a key, not a wipe (`docs/WEEKLY_ROLLOVER.md`'s rule): last week stays readable. The week's top three are a line in the News. And take the test companies off the Rank board; in the local world they are the only "rivals" on it (P). Production has 14 companies of the same kind; I did not read its board.

**The loop.** *Now:* always one house just ahead. *This week:* a place to hold or beat. *Next week:* a fresh board.

**Stands on.** `public.stats_merchants_board` and `stats_merchants` (the houses' profit a day, already counted), `history_company_day` (a company's earned and lost a day), `standings`, `public.settle_standings`, `world.standings`, `public.news_post`.

**Load.** None new if it reads what the Stats count already writes. **Not checked:** that `history_company_day` is filled on production.

#### 6. The logbook (M)

**Pitch.** A page of counts. Harbours seen 3 / 254, by region. Goods sold 4 / 629, by kind. Seas sailed 1 / 51. Hulls owned 1 / 157. Captains signed 1 / 105. Each finished set (Iberia's harbours, every spice) pays Reputation once and one small standing benefit there. Totals have rank names. The arrival card gains a line: "New: Cinnamon · Spice 3 / 40".

**The loop.** *Now:* a second reason to choose a cargo or a harbour: I have not sold that, I have not been there. *This session:* "two more harbours finish Iberia". *This month:* the big sets. It is the cheapest way to turn the 629 goods and 254 harbours, which exist, into things to do.

**Stands on.** The company's own `SOLD`, `VOYAGE_REPORT`, `HULL_LAID_DOWN` and `SIGNED_OFFICER` events, `public.player_progress` (it already counts harbours reached), `public.reputation_credit`, the step pattern of `public.level_perks`, `regions`, `goods.category`. New: one small table of firsts, one writer, humans only.

**Load.** A row the first time only: about 1,200 rows in a company's whole life.

**Is this a quest?** No. It asks for nothing. It counts what was done.

#### 7. Bounties on named pirates (M)

**Pitch.** Each country names the pirate fleets that robbed its ships most in the last day and puts a price on them, paid from its capital's purse. A company that beats one, by attacking or by joining a raid on the merchant's side, is paid, gains regard, and makes the News. The pirates' five ranks are the difficulty steps.

**The loop.** *Now:* wanted pirates are marked on the map with their price. *This session:* hunt one in reach, or answer a red ring. *This week:* a bigger ship for a bigger bounty; standing with the countries.

**Stands on.** `pirate_ships`, `pirate_roster`, `npc_ladder`, `fleet_book` and `public.pirate_loot_book` (who took what), `cmd.attack`, `public.attack_for`, `public.attack_close`, `cmd.battle_join`, `public.battle_resolve`, `public.regard_add`, `public.reputation_credit`, `public.news_post`.

**Load.** A list of about 30 rows redrawn hourly inside the existing city job. **Needs:** 1 (so fights are part of play) and 3 (a ship with guns). **Not known:** whether one small warship can beat a Raider. The builder measures it on frozen sheets before any price is set.

#### 8. World events on the fair's rails (M)

**Pitch.** The game has one event: the Fair. It is built as data (`buff_kinds`), so a new event is a row and one reading. Add three: **Famine** (the city's food wants pay three times, for hours; stands on `city_wants`), **Blockade** (a sea's pirate pressure is high, the harbours behind it pay more), **Festival** (captains' wages down, new faces at the inn). Each is in the News *before* it starts, with a countdown, and marked on the map.

**The loop.** *This session:* a named target with a clock. *Tomorrow:* something announced to plan for.

**Stands on.** `buff_kinds`, `active_buffs`, `public.tick_buff_calendar`, `world.buffs`, `public.buff_multiplier`, `public.wants_draw`, `sea_pressure`, `public.news_post`, `world.news_marks`.

**Load.** A few rows an hour. **Not checked:** that fairs run on production today, and that the Trade screen shows one.

#### 9. Each level opens something (S each)

**Pitch.** In my play Trading reached level 13 of 20 in the first hour and each level paid Reputation. Give each level a thing it opens, from what exists: Requests levels open a second and third job held at once and bigger loads; Shipbuilding levels open hull tiers at the yard's order and shorten its time; Investment levels open a say in the city. Two levels already do this and are the model: Routes adds a route at 8 and 16, and Evasion changes the chase (0453). A benefit is a row in `public.level_perks` and one reading.

**Stands on.** `level_perks`, `public.level_perk`, `public.level_benefits`, `level_activities`. **Owner's to weigh:** Trading rises very fast for a company that turns its whole purse over each trip; that curve is his.

#### 10 and later

- **Goods mastery (M).** Each good a company sells has its own small ladder (a better price, a bigger daily cap). It gives a trader a specialty. After the logbook, on the same table.
- **Choices at sea (L).** A storm, a wreck, a strange sail: choose. It needs a default for a player who is away and it touches the voyage's settling, which is exact by design. Not now.
- **Player workshops and buildings (L).** The forge and the workshops exist and no login has used them. First make fittings matter (1), then ask again.

### 5.4 The first three slices, and why these

| Slice | What ships | Why now |
|---|---|---|
| **A. Pirates raid companies too** (1) | One migration: one hunk in `public.raid_target`, three knobs (today's rule back; the title under which a company is passed over; the weight), its proof, the after-check. No client. | Smallest change, largest effect. It gives a job to guns, armour, insurance, the standing order, the fight screen, Evasion, Combat and the surgeon. Without it a third of the game is decoration. |
| **B. A route in reach, and a report on return** (2) | Client only. "Repeat as a route" on the arrival card; the "While you were away" card; the ticking line. | Nearly free, because the route is built and works. It is what the owner asked the game to be in September, and today a player has to stumble on it. It makes leaving the game part of playing it. |
| **C. The yard takes an order** (3) | One migration: the orders table, two doors, the read's keys. Client: Order, the timer, Ready, Launch. And the planned trip stops sailing past its materials. | It opens the one door everything else waits behind (3.5). It is the sink the one real company has needed since October, the first thing a player pays for and comes back for, and what turns a route from a replacement for play into a second layer. |

Each is small enough for a day, or a day and a half for C. They touch different functions and screens, so three builders can work at once. A and C are migrations and deploy in number order; B needs none.

Together they are one loop that the game does not have today: **a ship earns while you are away (B), something can take it from you (A), and what it earned buys the next ship, which takes time to arrive (C).** Earn, risk, spend, wait, return. Today the game has only the first.

**The first hour with these three, as I expect it (J):**

| Minute | Today | After A, B, C |
|---|---|---|
| 2 | First profit. | The same. |
| 5 | The same trip again. | The arrival card offers "Repeat as a route": the ship can trade by herself whenever the player steps away. |
| 15 | The wall: an 85-minute errand, or the same loop. | Order a second barca for about 26,000. Ready in half an hour. |
| 45 | The same loop. | Launch her. One ship on the route, one in the hand. The second fleet is already free. |
| When she is a Master | Nothing. | A pirate in reach may take her on. Fight, Run or Pay, and a reason to buy guns. |
| Tomorrow | Nothing happened. | "While you were away": laps and what they earned. Enough for the next ship. |

**Next, at once: 4, requests a ship can carry.** The three above build the part of the game that runs by itself. Number 4 is for the ship the player still sails by hand: somewhere to go that the best-sale card did not choose, against a clock. It is fourth only because it is a little larger and its sizes and pay need measuring first.

**The wait at sea stays.** None of these removes it, and I would not try yet (choices at sea are a large slice). What changes is what the wait is for: a pirate may come (A), a route is earning beside you (B), a ship is on the stocks (C), a deadline is running (4), and with a second ship there is always another thing in flight. Slices 5, 7 and 8 then give reasons to look at the world while waiting.

Then, in order: 5, 6, 9 in small pieces, 7, 8.

### 5.5 What I would not build, and why

| Not this | Why |
|---|---|
| Quests, story chains, guides | The owner's standing order. And they are arcs: built at great cost, used once [LG-L]. With one player, loops first. |
| Daily login rewards, streaks, energy | They punish absence. Jagex cut its own in 2026 [DS]. The reference game's energy gate was already judged a fault (`docs/SUCCESS_PLAN.md`). |
| Guilds, co-op events, PvP, port wars between players | One company plays. The countries and the houses can be the other side for now; the influence race is already built. |
| More goods, harbours, hulls, skills, captains | 629, 254, 157, 107 and 105 exist. The count is not the problem. The use is. |
| More NPC fleets or faster jobs | It spends the database budget on something a player cannot feel. |
| A season that resets everyone (prestige) | Nothing to reset yet. Look again when there are ten players. |
| Player buildings and production chains | Large, and the small versions (forge, workshop) have never been used. |
| A second currency or a shop | Reputation already exists and has one use. |
| Choices at sea | Good idea, wrong time: large, and it touches the exact voyage settling. |

### 5.6 The owner's decisions, with my defaults

| Decision | Default |
|---|---|
| Pirates take a company's ship as readily as a merchant's | Yes. Nearest wins. Passed over under the title Master. Weight 1. |
| A ship for coin and time | Yes, at half again the price and with a real wait. Materials stay cheaper and instant. |
| Ship-sized requests beside the city-sized ones | Beside, not instead. |
| Test companies on the Rank board | Off the board. They stay in the database. |
| Routes: keep them? (the owner asked on 14 November) | Keep, and lead to them: "Repeat as a route" on the arrival card. |
| The best-sale card | Keep it (5.1). |
| The Trading curve (level 13 of 20 in the first hour) | Leave it. Give the levels things to open (9) before changing the pace. |

### 5.7 How we will know

With one company there is no statistic to move. So:

- **After A:** raids on companies for each hour a company is at sea (it is 0). The first Evasion and Combat experience on production.
- **After B:** route laps closed by a company (it is 0), and whether a company comes back the next day.
- **After C:** hulls ordered; coin held by the richest company falling.
- **After 4:** requests delivered by a company (it is 0). Distinct harbours a company calls at in a session.
- **The plain test:** the owner plays for an hour and does not run out of things to press.
- **(J)** The cheapest real evidence would be three or four people who have never seen the game, one hour each, with the screen recorded. Production has no such hour on record.

---

## 6. What is measured, and what is not

| Statement | How it is known |
|---|---|
| One company plays; 4 logins seen for a day or two; 14 companies with no login | (M) two reads of `players`, `events` and the logins' timestamps |
| Company 1's last voyage: 30 October | (M) its events by day |
| 0 of 2,339 raids on a company in 48 h; no company voyage ended in 7 days | (M) the lead's read today (`docs/dev-log/2026-11-16-evasion.md`); not re-read by me. The cause in `public.raid_target`: (R) |
| Requests: 751 open, mean 31,367 units, none delivered by a company | (M) one read of `trade_contracts` |
| The first 10 minutes and the first hour | (P) world B, one run. One run is not an average. |
| The second ship is 85 real minutes and the plan sails past the materials | (P) world C, once. I saw one stop of five. |
| The fight's verbs | (R) `docs/design/tick-combat.md`. Not played. |
| The 14 no-login companies are the chain's test companies | (J) from their pattern and the local image, which holds 13 of the same pattern. I did not trace each to its migration. |
| Raids on a company after slice A: about one in 18 hours at sea | (J) arithmetic from the lead's figures, assuming ships are spread evenly. They are not. |
| A request's size and pay (item 4); the yard's times and fee (item 3) | (J) Proposals. The builder measures prices first. |
| What a route earns an hour on production | Not known. I saw one lap, in a local world whose game day is four hours. |
| What other games do | (S) section 8. Fan wikis for Uncharted Waters Online; promotional pages for OGame. |
| The four one-day logins left because the first screen did not hold them | Not known. They may have been tests. |
| The sign-in screen | Not seen: the local build skips it. The founding screen I saw only in the gallery: a name, a country, "You get 1 ship · 40,000 · Lisbon", Start. |
| What happens to a new player in a storm, short of supplies, or wrecked | Not seen. No bad day came up in my runs. |

Things I met that are faults, for the lead (not part of the plan):
- The default local world's best-sale card overstated a profit 36 times (22,416 against 617). World B's did not. Cause not found.
- In worlds B and C a request's time left read "5758:09:35". Local only, I think: the local world's game day is longer than production's.
- The Invest tray shows a price and no return.
- The planned trip for a build does not buy (3.4).

---

## 7. Appendix: the production reads

All read-only (`begin transaction read only`), one statement a file, built-ins and `public.player_progress` (stable) only. Run 2026-11-16 between 04:33 and 05:00 UTC, the gate green before.

1. **The gate:** `scripts/ops/harness/db-health/gate.sql`.
2. **Switches:** `select key, value from public.world_config where jsonb_typeof(value) = 'boolean'`.
3. **Companies:** for each `players` row with `is_npc` false, in order of `created_at` and with no name: coin, nation, fleets, ships and their classes, where each fleet lies, first and last event, events by kind, events by day, the first 80 events as seconds from the first, `public.player_progress(id)`, `level_xp`, Reputation, shares, captains, skills, items, storage, routes, requests placed and delivered, mayoralties. Every lookup by `player_id` on `events (player_id, created_at desc)` and `ledger (player_id, created_at desc)`.
4. **Logins:** for the same rows: whether `auth_uid` is set, and from `auth.users` and `auth.sessions` three timestamps only (login made, last sign-in, last refresh). No address, no name.
5. **The oldest company:** its last 400 events by day and kind, and its last 40 ledger rows (kind, amount, balance).
6. **Requests:** `trade_contracts` by status: count, harbours, bonus (mean, median, least, most), mean size, how many a company delivered, oldest and newest.

---

## 8. Sources

Opened by the research pass that cites them; * re-opened by me.

**Sailing and trading games**
- [NH] Uncharted Waters: New Horizons, player's guide: https://www.video-games-museum.com/en/faqs/Super%20NES/2521-New-Horizons.pdf
- [UWO-I]* Uncharted Waters Online, investment (Japanese fan wiki, last edited 2015): https://wikiwiki.jp/gvo/Investment
- [UWO-D] Its designers' notes on damping large investors: https://www.gamecity.ne.jp/dol/developer/index_090217.htm
- [UWO-E] Sea feuds and investment wars (fan sites): https://uwo-hq.blogspot.com/2019/02/epic-sea-feud-esf.html and https://wikiwiki.jp/gvo/GreatInvestmentWar
- [UWO-R] Court rank and discovery reports (fan site): https://uwo-hq.blogspot.com/2019/08/court-rank-guide.html
- [P4] Patrician IV, the manual: https://www.rune-soft.com/upload/documents/Manual_PDF_Patrician4%20.pdf
- [PR2] Port Royale 2: https://en.wikipedia.org/wiki/Port_Royale_2
- [SM-F] Sid Meier's Pirates!, the fame ledger (a player's guide): https://www.cyberly.org/game-cheats/pc-walkthroughs/sid-meier's-pirates-faq.html
- [SM] Sid Meier's design lessons: https://www.gamedeveloper.com/game-platforms/analysis-sid-meier-s-key-design-lessons

**Persistent browser and text games**
- [OG-B] OGame, beginner's guide (the publisher's page): https://gameforge.com/en-GB/games/ogame-beginner-guide.html
- [OG-P] OGame, points: https://gameforge.com/en-GB/games/ogame-points-system.html
- [OG-E]* OGame, events: https://gameforge.com/en-GB/games/ogame-events.html
- [TV-A] Travian, artefacts: https://support.travian.com/en/articles/101-artefacts
- [TORN] Torn, awards (a player's paper): https://torncitynewspaper.blogspot.com/2021/01/hunting-for-awards.html
- [TORN-R] Torn, a review: https://intoindiegames.com/reviews/torn-city-review/
- [EVE-C]* EVE Online, contracts: https://wiki.eveuniversity.org/Contracts
- [EVE-A] Agents: https://wiki.eveuniversity.org/Agents
- [EVE-I] Insurance: https://wiki.eveuniversity.org/Insurance
- [EVE-S] Skill training: https://wiki.eveuniversity.org/Skill_training
- [EVE-AIR]* The career program: https://wiki.eveuniversity.org/AIR_Career_Program
- [KOL] Kingdom of Loathing: https://en.wikipedia.org/wiki/Kingdom_of_Loathing
- [PAR] Pardus: https://en.wikipedia.org/wiki/Pardus_(video_game)
- [PU] Prosperous Universe, a first day: https://tobolds.blogspot.com/2022/05/first-day-start-in-prosperous-universe.html?m=0

**Idle games and skilling**
- [MEL-O] Melvor Idle, offline progress: https://wiki.melvoridle.com/w/Offline_Progression
- [MEL-C] Completion log: https://wiki.melvoridle.com/w/Completion_Log
- [MEL-S] Shop: https://wiki.melvoridle.com/w/Shop
- [OSRS-W] Old School RuneScape, Woodcutting's level table: https://oldschool.runescape.wiki/w/Woodcutting/Level_up_table
- [OSRS-C] Collection log: https://oldschool.runescape.wiki/w/Collection_log
- [OSRS-F]* The Forestry update, on shipping without a collection log: https://oldschool.runescape.wiki/w/Update:Forestry:_The_Way_of_the_Forester_-_Part_One
- [POP]* RuneScape, Player-owned port: https://runescape.wiki/w/Player-owned_port
- [DS]* RuneScape, the DailyScape overhaul of 16 March 2026: https://runescape.wiki/w/Update:DailyScape_Overhaul_%26_Free_Runemetrics_for_Members

**Design writing**
- [IDLE] Anthony Pecorella, The Math of Idle Games: https://gamedeveloper.com/design/the-math-of-idle-games-part-i and his talk's slides: https://www.slideshare.net/slideshow/idle-chatter-gdc-2016-59734260/59734260
- [ID7] One developer's pacing rules: https://dev.to/aguier/i-built-7-idle-games-in-30-days-what-i-learned-about-incremental-design-5d3f
- [GUAN] Eric Guan, idle game design principles: https://ericguan.substack.com/p/idle-game-design-principles
- [LG-L]* Daniel Cook, Loops and Arcs: https://lostgarden.com/2012/04/30/loops-and-arcs/
- [LG-C] Daniel Cook, The Chemistry of Game Design: https://lostgarden.com/2021/03/13/the-chemistry-of-game-design-2/
- [LG-V]* Daniel Cook, Value Chains: https://lostgarden.com/2021/12/12/value-chains/
- [KOS]* Raph Koster, The Laws of Online World Design: https://www.raphkoster.com/games/laws-of-online-world-design/the-laws-of-online-world-design/
- [APPT] Appointment mechanics: https://gamedeveloper.com/design/how-big-games-use-appointment-mechanics-to-get-gamers-keep-coming-back
- [QUEST] Anthony Pecorella, Quest for Progress (slides; it cites a Quantic Foundry survey of idle players): https://www.slideshare.net/slideshow/quest-for-progress-gdc-europe-2016/65405507
