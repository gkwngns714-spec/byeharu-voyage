# Civilization, and "Civilization but online" - research for the HQ trading-company game

Researched 2026-11-24, in about 25 minutes of web reading. Facts only; every figure has a source beside it.

**How to read the marks.**
- **[V]** = verified: I opened the page today and it says this.
- **[S]** = search snippet only: a search result quoted it, I did not open the page. Treat as likely, not proven.
- **[M]** = from my memory of the game, not checked today. Do not build on it without a check.

The Civilization Fandom wiki refused every fetch today (HTTP 402), so most Civilization VI figures are from CivFanatics threads and
well-of-souls.com, or are marked [S] / [M].

Source key:
- **[CF-DIST]** `https://forums.civfanatics.com/threads/district-cost-actual-numbers.606701/` (player thread, formula taken from Reddit)
- **[CF-GROW]** `https://forums.civfanatics.com/threads/population-growth-formula.694910` (snippet only)
- **[CF-CS]** `https://forums.civfanatics.com/resources/guide-to-city-states.25846` (snippet only)
- **[WOS]** `https://well-of-souls.com/civ/civ6_civics.html` (fan reference page, launch-era figures, Quick speed)
- **[CF-AGES]** `https://civfanatics.com/civ7/civ-vii-gameplay-mechanics/civilization-vii-ages/`
- **[2K-TOT]** `https://civilization.2k.com/civ-vii/apple-arcade/test-of-time-update/` (snippet only)
- **[SGET]** `https://gametek.substack.com/p/staggered-goal-engagement-theory` (Geoff Engelstein, 23 March 2023)
- **[WP-CW]** `https://en.wikipedia.org/wiki/Civilization_World`
- **[PG-CW]** `https://www.pocketgamer.com/civworld/its-the-end-of-civworld-as-we-know-it-and-i-feel-meh` (4 March 2013)
- **[MMOS-CO]** `https://mmos.com/review/civilization-online/`
- **[MEIN-CO]** `https://mein-mmo.de/en/civilization-online-bye-bye-sandbox-mmo,123310` (7 November 2016)
- **[PCG-CO]** `https://www.pcgamer.com/civilization-online-revealed` (snippet only; the page body did not load)
- **[WP-FOE]** `https://en.wikipedia.org/wiki/Forge_of_Empires`
- **[FOE-FP]** `https://forgeofempires.fandom.com/wiki/Forge_Point` and `https://en.wiki.forgeofempires.com/index.php?title=FAQ` (snippets only)
- **[PW-CITY]** `https://politicsandwar.com/pwpedia/article/Cities` (the game's own wiki)
- **[PW-WAR]** `https://politicsandwar.fandom.com/wiki/War` (snippet only)
- **[TRAV]** `https://support.travian.com/support/solutions/articles/7000060689` (snippet only)
- **[OG]** `https://board.origin.ogame.gameforge.com/index.php/Thread/2972-Noob-Protection-Tutorial` (snippet only)
- **[LT]** `https://freeciv.fandom.com/wiki/Longturn`, `https://freecivweb.org/rules` (snippets only; longturn.net refused the fetch)
- **[EVE-VW]** `https://ccpcommunity1436997059.zendesk.com/hc/en-us/articles/210556429-Vulnerability-Window` (snippet only; 2015-era rules)
- **[UWO]** `https://guide.floor.line.games/UWO/en_US/detail/1167031186467500250` (snippet only; this is Uncharted Waters ORIGIN, not Online)

Already covered in sibling files, not repeated here: EVE taxes, skills, upkeep and security bands (`eve-online.md`); Tribal Wars
building curves and session design (`tribal-wars.md`); Melvor and RuneScape loops (`melvor-idle.md`, `runescape-3.md`).

---

## 1. Civilization VI and VII: the mechanics

### 1.1 Why "one more turn" works

- **Staggered goals [V, SGET].** Turns are short, and most actions (research, buildings, settlers) take several turns. A player runs
  many in parallel, so one is always close to done. Engelstein ties this to "endowed progress": a goal already part-filled is more
  likely to be finished. His rule for designers: never return the player to zero; leave them partway to the next goal.
  The article argues from examples, not from tests.
- **Overlapping goals [S].** Soren Johnson (Civ IV lead) traces Civ's pull to Railroad Tycoon's overlapping goals
  (`https://www.gamesradar.com/civilized-conversation-with-soren-johnson`). I did not open the interview.
- **What that means in plain terms:** several bars of different lengths (minutes, hours, days) that never all finish at once, and
  each finished bar opens a small choice.

### 1.2 Yields and city growth

- Six yields in Civ VI: food, production, gold, science, culture, faith [M].
- **Food for the next citizen [S, CF-GROW]:** 15 + 8 x (N - 1) + (N - 1)^1.5, rounded down; N = current population.
  Size 1 needs 15, size 2 needs 24, size 3 needs 33. My arithmetic: size 10 needs 114, size 20 needs 249. The exponent was 1.8 at
  launch and was cut to 1.5 [S].
- **Housing is a soft cap [M]:** growth at 100 % with 2 or more spare housing, 50 % with 1 spare, 25 % from the cap to 4 over, 0 % at
  5 over. Not checked today.
- The shape that matters: a cost that rises a little faster than straight-line, plus a soft cap that slows growth before it stops it.

### 1.3 Districts, buildings, adjacency

- **District cost [V, CF-DIST]:** `FLOOR(Base x (1 + 9 x FLOOR(100 x MAX(techs / 67, civics / 50)) / 100))`, base 60 at normal speed.
  So a district costs 60 at the start and 600 with the whole tree done: **10x across the game, driven by the player's own progress,
  not by how many districts he owns.**
- **Catch-up discount [V, CF-DIST]:** a district costs 75 % if you have fewer of that type than the average. Unique districts cost
  half (the thread flags mixed reports).
- **Adjacency [S]:** each neighbouring district gives +0.5 (so +1 per two); a mountain gives +1 to a Holy Site; the Government Plaza
  gives +1 on top of its +0.5 (`https://civilization.fandom.com/wiki/Government_Plaza_(Civ6)`, snippet).
- Districts are limited by population: 1 at size 1, then one more each 3 citizens (1 / 4 / 7 / 10) [M].
- The design point: **placement is a one-time choice with a permanent yield**, so the map itself becomes the puzzle.

### 1.4 Build queue, tech and civics trees

- One item is built at a time per city; a queue came later by patch [M].
- **Two trees, two currencies [V, WOS]:** science buys techs, culture buys civics. Civic costs on that page run from 20 (Code of
  Laws) to 2,400 (Social Media, repeatable) at Quick speed: **120x from first to last.**
- **Boosts (Eureka / Inspiration):** do a named thing in play and the cost of one tech or civic falls. The size is 40 % in the
  current game [S, a CivFanatics rebalance thread refers to "40 %"]; each boost fires once [S].
- Tree size at launch: 67 techs, 50 civics [V, CF-DIST].

### 1.5 Governments and policy cards

Slots as military / economic / diplomatic / wildcard [V, WOS, launch-era]:

| Government | Slots | Total | Built-in bonus |
|---|---|---|---|
| Chiefdom | 1 / 1 / 0 / 0 | 2 | none |
| Classical Republic | 0 / 2 / 1 / 1 | 4 | +1 Amenity in cities with a district |
| Oligarchy | 1 / 1 / 1 / 1 | 4 | melee +4 strength |
| Autocracy | 2 / 1 / 0 / 1 | 4 | capital +1 all yields |
| Monarchy | 3 / 1 / 1 / 1 | 6 | +2 Housing with Medieval Walls |
| Theocracy | 2 / 2 / 1 / 1 | 6 | buy land units with Faith |
| Merchant Republic | 1 / 2 / 1 / 2 | 6 | +2 Trade Routes |
| Democracy | 1 / 3 / 2 / 2 | 8 | Great People patronage -50 % gold |
| Communism | 3 / 3 / 1 / 1 | 8 | land units +4 defence |
| Fascism | 4 / 1 / 1 / 2 | 8 | all units +6 attack |

- **Slots grow 2 -> 4 -> 6 -> 8 by tier.** The cards are small percentage or flat modifiers.
- **Changing cards is free on the turn a civic completes; at any other time it costs gold** [V, WOS, quoting Firaxis's Dennis
  Shirk]. The amount is not on the page. This is the important rule: re-planning is tied to progress, not open at every moment.

### 1.6 Great people, trade routes, city-states

- **Great people [M]:** each type has its own points; the first civilization to reach the cost claims the person; the next one costs
  more; a person can be bought early with gold or faith. I could not verify figures today.
- **Trade routes:** each city with a Commercial Hub or Harbor adds one route; the two do not stack [S, Fandom Trade Route page].
  A route's yield is read from the districts of the destination city [S]. Merchant Republic gives +2 routes [V, WOS].
- **City-states and envoys [S, CF-CS]:** influence points accrue per turn by government tier (1 / 3 / 5 / 7); an envoy is granted at
  100 / 150 / 200 points. Bonuses come at 1, 3 and 6 envoys; the suzerain is the civilization with the most envoys and at least 3;
  a tie means no suzerain [S, Fandom Suzerain page]. **So there are tiers for everyone and one prize for the leader.**

### 1.7 Victory types

- Civ VI: Science, Culture, Domination, Religion, Score, plus Diplomacy from Gathering Storm (20 Diplomatic Points) [S,
  `https://civilization.fandom.com/wiki/Victory_(Civ6)`].
- Culture victory is relative: more foreign tourists than any rival has domestic ones [S].
- The design point: **several races run at once, and each is visible to everyone**, so a player always knows who leads what.

### 1.8 Civilization VII: ages reset

- Three ages: Antiquity, Exploration, Modern [V, CF-AGES]. The page says each age runs "approximately 150-200 turns".
- Age progress rises each turn and faster from all players' actions. At a threshold a Crisis starts, with forced negative policies
  [V; the threshold figure is not given].
- **Resets at the transition [V]:** tech and civic trees are replaced and progress on them reset; Legacy Path progress reset; some
  resources removed; obsolete buildings lose yield; obsolete cards removed.
- **Carries over [V]:** the leader and attribute points; Traditions (cards kept forever); wonders and "ageless" buildings;
  commanders with their experience; Legacy Options bought with Legacy Points.
- Four Legacy Paths (Science, Culture, Military, Economic), up to 3 milestones each; finishing a path gives a Golden Age option
  (at most 1 may be picked); no progress on a path gives a Dark Age option [V].
- A later "Test of Time" update is said to have replaced Legacy Paths with "Triumphs" [S, 2K-TOT]. I did not open it, so I cannot
  say what changed or why.
- The design point: **a soft reset that removes the leader's snowball but keeps a chosen few permanent things.**

---

## 2. The same ideas online, with many persistent players

### 2.1 CivWorld / Civilization World (Firaxis, Facebook, 2011-2013)

- Open beta 6 July 2011 as "Civilization Network"; closure announced 28 February 2013; last day 29 May 2013 [V, WP-CW].
- Real time, not turns. Players joined nations with ranks (king, princes, dukes); the winner was whoever held the most fame points
  from achievements, techs, era victories and wonders [V, WP-CW].
- **Numbers [V, PG-CW]:** a peak of about 89,000 daily players soon after launch; about 2,000 daily at the closure notice.
  A second report gives 10,000 monthly users at the notice [S, AOL].
- "Harvests" worked as an energy limit; **inactive players were expelled from their nation after 48 hours** [S, source not opened].
- A harsh review, relayed in a forum thread, listed connection trouble, few meaningful choices, a slow first week and dull
  minigames [S, `https://forums.civfanatics.com/threads/does-civworld-have-a-chance-to-succeed-review-forecast-etc.430199/`].
- **Why it closed:** no official reason found. The user figures fell by about 98 % from peak (my arithmetic, 89,000 -> 2,000).

### 2.2 Civilization Online (XLGames, Korea, 2015-2016)

- Launched December 2015, Korea only; closed 7 December 2016: under one year [V, MEIN-CO, MMOS-CO].
- 4 civilizations (Aztec, Egypt, China, Rome); each unit is one player; three roles (fighter, gatherer, builder) [V, MMOS-CO].
- **Sessions:** a world runs from the Ancient era to the Modern era; when one civilization wins (conquest or space race), the world
  and the scores reset, with a new random map; money, items and clothing reset, "some aspects" of the character are kept [S,
  PCG-CO and others].
- **Why it closed:** no official reason found. MEIN-CO says only that it "was not well received by players" and so never launched
  in the West. Session length, and whether faction imbalance was a cause, I could not verify.

### 2.3 Forge of Empires and Rise of Cultures (InnoGames)

- Forge of Empires: open beta 17 April 2012; over 130 million registrations and over 1 billion US dollars lifetime revenue as of
  2023; more than half of players on mobile [V, WP-FOE]. It is the commercial proof that "Civ-like, online, persistent, no world
  reset" can last more than ten years.
- **Forge Points [S, FOE-FP]:** 1 an hour; the hourly gain stops while 10 or more sit in the bar. One currency buys BOTH research
  and levels of Great Buildings, so every point is a choice between the two.
- **Great Buildings [S]:** each level needs more points; guild mates, friends and neighbours may contribute points to another
  player's building and are rewarded by rank of contribution. This is the co-operative replacement for conquest.
- Ages run from the Stone Age to the far future on one tech tree; nothing resets [V, WP-FOE].
- Rise of Cultures: no player-against-player fighting at all [S, `https://insider-gaming.com/rise-of-cultures/`]; workers are the
  limit on how many things run at once [S, levelwinner]. Figures not verified.

### 2.4 Politics and War (browser nation game)

- A turn every 2 hours, 12 a day [S, PW-WAR].
- **City cost [V, PW-CITY]:** the higher of `100,000 x X^2` and `100,000 x (X - A/4)^3 + 150,000 x (X - A/4) + 75,000`, where X is
  the city number and **A is the average city count of the top 20 % of nations, recalculated monthly.** As the leaders grow, every
  city behind them gets cheaper. From 20 cities, one new city per 120 turns (10 days).
- This is the cleanest catch-up rule I found: the price of growth is indexed to the leaders, and the leaders are rate-limited.

### 2.5 Travian, OGame, Freeciv Longturn, EVE sovereignty

- **Travian [S, TRAV]:** beginner's protection 5 days + 3 optional at speed 1 (3 + 3 at speed 2). A world ends when a Wonder is
  finished; the Natars' own Wonder finishes at day 250 at speed 1 (160 at speed 2, 95 at speed 3), so a world has a hard last day.
- **OGame [S, OG]:** a player under 50,000 points cannot be attacked by one more than 5 times his size (1:10 from 50,000 to
  500,000). Protection is lost after 7 days idle. Vacation mode stops attacks and stops production. Figures not verified.
- **Freeciv Longturn [S, LT]:** one turn a real day (23 hours on one community's servers, so the turn change drifts round the
  clock and no time zone always gets it at night); a game lasts 3-4 months. Idle nations are removed after 2 idle turns early on,
  rising to 7 later. Not verified; longturn.net refused the fetch.
- **EVE sovereignty [S, EVE-VW, 2015-era rules]:** the defender picks the hour he can be attacked; the window is 18 hours divided
  by an activity multiplier, so 3 to 18 hours. A space that is used is harder to take than one that is merely held. Current rules
  not checked.
- **Uncharted Waters Origin [S, UWO]:** companies invest in a city in three lines (Industry, Commerce, Military), minimum 50,000
  ducats; weekly rewards by investment rank. The developer said in December 2024 that it wanted to move away from "ducats making
  more ducats", and investment scores now reset each season. I found nothing usable on Uncharted Waters ONLINE or on Anno.

### 2.6 Lessons and failures

| Problem | Who shows it | What was done about it |
|---|---|---|
| **Snowballing** (the leader's lead grows by itself) | Every 4X; Civ VII built ages to stop it | Costs indexed to own progress (Civ VI districts, 10x); a 25 % discount for being under the average; prices indexed to the top 20 % and a 10-day timer for leaders (Politics and War); a soft reset that keeps only chosen things (Civ VII) |
| **Griefing and farming the weak** | Travian, OGame | Protection by days (Travian) or by size ratio (OGame). We have no player conquest, so the only form left to us is market crowding |
| **Inactivity** | CivWorld expelled idlers at 48 h; Longturn removes idle nations | Punishing absence lost CivWorld its players' places. Capping the bar (Forge of Empires stops at 10) is the gentle form; our away cap and paused charges are already that |
| **Time-zone warfare** | EVE, Longturn | The defender picks his window (EVE); the daily deadline drifts (Longturn). With no conquest we need only this: nothing a player owns should be decided at one fixed clock hour |
| **Seasonal reset or permanence** | Travian and Civilization Online reset the world; Forge of Empires never does | Both of the Civilization-branded online games reset or expelled, and both closed inside two years. The long-lived one keeps the player's city for ever and puts the competition in weekly events. Uncharted Waters Origin resets only the investment SCORE each season |
| **Few players** | Civilization Online needed 4 full factions; CivWorld needed full nations | Designs that need a crowd to function die when the crowd thins. Forge of Empires' loops (research, Great Buildings) work for one player alone and are only helped by others |

---

## 3. What fits us

Our facts: real time; play is asynchronous; about 19 companies, few active; no conquest between players; a closed money economy;
countries and cities are the server's; a simple text-and-tabs screen; one authority per concept.

| Mechanic | Verdict | Why |
|---|---|---|
| Staggered goals of mixed length (1.1) | **Fits as is** | Worker bars (minutes), estate builds (30 min doubling), crew-slot bars (hours to weeks) already are this. The rule to keep: never all at zero; a finished bar leaves the next one part-filled. |
| Yields shown per hour (1.2) | **Fits as is** | The Ledger's lines are our yields. No new yield is needed. |
| Rising cost a little above straight-line, plus a soft cap (1.2) | **Fits as is** | The crew-slot ladder and estate tiers already do this; the Warehouse bar is the "housing" that slows before it stops. |
| Cost indexed to own progress, with a discount under the average (1.3) | **Needs adapting** | Useful as a catch-up on a price we already have (the crew slot, an estate tier): cheaper for a company under the server's average. It must stay one reader on the existing price. |
| Price indexed to the top 20 %, leaders rate-limited (2.4) | **Needs adapting** | The strongest anti-snowball rule found. With about 19 companies "top 20 %" is 4 companies, so use the median or the top few. |
| Districts and adjacency on a hex map (1.3) | **Reject** | Needs a placement map and breaks "simple, words with figures". The idea that survives is a set bonus: estates of matching kinds at one HQ. |
| Build queue (1.4) | **Needs adapting** | A queue of 2-3 estate builds is cheap and suits away play. A long queue removes the reason to come back. |
| Tech and civics trees (1.4) | **Needs adapting** | `level_perks` is our one unlock table. A second personal tree would be a second authority. The Civ-like part we lack is a SHARED tree: a city or country project that companies fund (see Great Buildings). |
| Boosts: do a thing in play, a cost falls 40 % (1.4) | **Fits as is** | Maps onto Logbook sets and "first sale at a new harbour". It rewards variety, which a repeating-job game needs. |
| Policy cards in a few slots, free to change only at a milestone (1.5) | **Needs adapting** | A company "charter" of 2-4 slots that grows with Rank gives the Civ feeling cheaply. The free-change-at-Rank-up rule stops hourly re-optimising. Risk: it must be rows of the existing perk reader, not a new modifier system. |
| Great people claimed by the first to reach the points (1.6) | **Needs adapting** | With few active players a race has no rivals. Use a threshold anyone can reach (an S-grade captain offered at a Reputation mark), not a first-past-the-post claim. |
| Trade routes (1.6) | **Fits as is** | It is our core loop already. |
| City-state envoys: tiers at 1 / 3 / 6 and one suzerain (1.6) | **Fits as is** | Influence per city and "mayor = top investor" already exist. The missing half is the tiers: a small benefit for every investor at marks, not only for the top one. |
| Several visible victory races (1.7) | **Needs adapting** | The weekly country race is this. Add tracks (trade, exploration, building), not an end of the world. |
| Ages that reset the world (1.8) | **Reject** | A persistent company game cannot take away fleets and levels. Civilization Online and Travian reset the world; we keep it. |
| Seasons that reset only a score (2.5, Uncharted Waters Origin) | **Fits as is** | The weekly Champion is already a score reset. It gives late joiners a fresh race without touching what they own. |
| Shared projects others pay into, rewarded by rank (2.3) | **Fits as is** | City works and shares exist. This is the co-operative end-game that replaces conquest, and coin is moved to a city, never destroyed. |
| One currency that buys both research and buildings, capped in the bar (2.3) | **Needs adapting** | Reputation is already spent on two things. The cap idea is our away cap. No new currency. |
| Expelling or deleting idle players (2.1, 2.5) | **Reject** | With about 19 companies every one counts; we already pause charges for the dormant. |
| Beginner protection, vacation mode, attack windows (2.5) | **Reject** | They answer conquest, which we do not have. Keep one lesson: nothing is decided at one fixed clock hour. |
| Nations that need a full crowd of players (2.1, 2.2) | **Reject** | Both closed. Countries stay the server's; every loop must work for one company alone. |

---

## Not verified

- Every Civilization VI figure marked [M]: the housing growth steps, the district population steps, great-person costs, the queue.
- The 40 % boost size, the envoy point figures and the 1 / 3 / 6 bonus sizes: snippets only; the Fandom wiki refused every fetch.
- Trade route yields per district: sources disagreed in the snippets; no figure is given above for that reason.
- Civilization VII: the crisis threshold, age length in the shipped game, and what the "Test of Time" update changed.
- CivWorld: nation size, game length, and any official reason for closing. Wikipedia gives none.
- Civilization Online: session length in days or weeks, and the cause of the closure beyond "not well received".
- Forge of Empires' 1 point an hour and cap of 10; Rise of Cultures' figures; OGame's ratios; Travian's days; Longturn's rules;
  EVE's window: all from snippets, not from an opened page.
- Politics and War: only the city page was opened; infrastructure, alliance and colour-bloc rules were not.
- Uncharted Waters Online and Anno: nothing usable found. The investment notes are from Uncharted Waters Origin.
