# EVE Online - research for the HQ trading-company game

Researched 2026-11-24. Every figure below was read on the page named beside it. EVE changes with patches, so each figure carries the patch or page date where the source gave one. Where two sources disagree, both are given.

Short names:
- EVEU = wiki.eveuniversity.org (community wiki; some pages are flagged "needs update" by their own editors)
- MER = CCP Monthly Economic Report, October 2026 edition (published 2026-11-09): https://eveonline.com/news/view/monthly-economic-report-october-2026 . Raw data: https://web.ccpgamescdn.com/aws/community/EVEOnline_MER_202610.zip

---

## 1. Taxes and fees (the "skills reduce tax" model)

| Item | Base | Reduction | Formula / note | Source |
|---|---|---|---|---|
| Sales tax | 7.5% (patch 22.02, 2025-03-12; was 4%) | Accounting: 11% off per level | `7.5% x (1 - 0.11 x level)`: L0 7.5, L1 6.675, L2 5.85, L3 5.025, L4 4.2, L5 about 3.375 (derived from the formula on the page). The Market page's Skills section says "8% to 3.6%", which conflicts with its own Taxes section | https://wiki.eveuniversity.org/Sales_tax , https://wiki.eveuniversity.org/Market |
| Sales tax history | Max 2% (before 2019) -> 5% (2019-08) -> 2.5% temporary (2021-07) -> 8% (2021-10) -> 4.5% (2024-07, patch 22.01) -> 7.5% (2025-03, 22.02) | | EVEU also says "4% to 7.5%" for 22.02; 4% vs 4.5% before it is unexplained on the page | https://wiki.eveuniversity.org/Sales_tax |
| Broker's fee, NPC station | 3%, minimum 100 ISK | Broker Relations: 0.3 percentage points per level (1.5% at L5) | `3% - 0.3% x BrokerRelations - 0.03% x faction standing - 0.02% x corp standing`. Corp standing counts 2/3 of faction. Unmodified standing is used (standing-boost skills do not help). Minimum about 1% at Broker Relations V and max standing | https://wiki.eveuniversity.org/Market , https://wiki.eveuniversity.org/Tax |
| Broker's fee, player structure | 0.5% SCC surcharge (fixed) + owner's % (owner may set 0%) | Skills do not apply | `0.5% + owner %`. The 0% minimum owner fee dates from patch 21.05 (2023-06-21) | https://wiki.eveuniversity.org/Market , https://wiki.eveuniversity.org/Tax |
| Relist fee (modify an order) | | Advanced Broker Relations | `(100% - (50% + 6% x AdvBrokerRel level)) x broker fee % x new order value`, plus `broker fee % x max(new value - old value, 0)`; min 100 ISK. The page's prose says 5 points per level but its formula uses 6 | https://wiki.eveuniversity.org/Market |
| 2019 tax devblog (official, dated 2019-07-29) | Max sales tax 2% -> 5%; max broker fee 3% -> 5%; Accounting 10% -> 11% per level; Broker Relations 0.1% -> 0.3% per level; total max taxation 5% -> 10% | | Old rules; shown for the history of the skill numbers | https://www.eveonline.com/news/view/updates-to-sales-taxes-and-brokers-fees |
| Industry job cost | | | `Job cost = Estimated item value x ((System cost index x structure bonuses) + facility tax + SCC surcharge + Alpha clone tax)` | https://wiki.eveuniversity.org/Manufacturing |
| ...facility tax | 0.25% at NPC stations; owner-set at player structures; industry service taxes capped at 10% | | | same |
| ...SCC surcharge (industry) | 4% | | Only this one EVEU page gave 4% | same |
| ...Alpha clone tax | 0.25% (Manufacturing page) | Omega pays none | The Alpha clone page says Alpha pays "an extra 2%". The two EVEU pages disagree | https://wiki.eveuniversity.org/Manufacturing , https://wiki.eveuniversity.org/Alpha_clone |
| ...System cost index | work hours in the system / work hours in the universe, last 28 days | | The Manufacturing page warns this form is "probably no longer correct" after a later patch | https://wiki.eveuniversity.org/Manufacturing , https://wiki.eveuniversity.org/Research |
| Research/copy cost | | | Copy cost = `system cost index x copies x runs per copy x 0.02 x sum(material qty x adjusted price)`; research cost = `process time value x system cost index x structure bonus` | https://wiki.eveuniversity.org/Research |
| Planetary customs (POCO) tax | High-sec NPC office: 10% + owner's rate. Low/null/wormhole NPC office: 17% (skill cannot reduce). Player offices outside high-sec: owner's rate only | Customs Code Expertise: PI pages say 1% per level; the Tax page says 10% per level (10% -> 5% at L5) | Export fee = base cost x tax rate (x1.5 if launched from a Command Center). Import fee = base cost x rate x 0.5. High-sec Command Center export tax 15%. Total can reach 100% per the Tax page | https://wiki.eveuniversity.org/Planetary_Industry , https://wiki.eveuniversity.org/Planetary_Interaction , https://wiki.eveuniversity.org/Tax |
| Corporation tax | Player corp sets its own rate; NPC corps always 11% | | Applies to bounty, Project Discovery, AIR Daily Goals, and mission payouts over 100,000 ISK. Not applied to wallet ISK, sell orders or transactions | https://wiki.eveuniversity.org/Tax |
| Reprocessing tax | 5% at 0 standing, 0% at 6.67 standing (higher of personal or corp standing with the station owner) | Connections V cuts corp tax by 25% (only after one mission for that corp) | Player structures can set any rate, including 0% | https://wiki.eveuniversity.org/Reprocessing , https://wiki.eveuniversity.org/Tax |
| Reprocessing yield | Base 30-50% at NPC stations, 50% at Upwell | Reprocessing +3%/level, Reprocessing Efficiency +2%/level, ore skill +2%/level | `Yield = base x (1+R x 0.03) x (1+Re x 0.02) x (1+Ore x 0.02) x (1+implant)` | https://wiki.eveuniversity.org/Reprocessing |
| Faction Warfare maintenance tax | Starts 0%, up to 75% with faction tier | | | https://wiki.eveuniversity.org/Tax |

Size of each tax as an ISK sink, October 2026: see section 7.

---

## 2. Skills

| Topic | Fact | Source |
|---|---|---|
| Skill points per level | Rank-1 cumulative SP: I 250, II 1,414, III 8,000, IV 45,255, V 256,000. A rank-10 skill needs 2,560,000 SP for V. The EVEU printed formula is garbled; the series fits `250 x rank x 32^((L-1)/2)` (my fit to the page's numbers, not a printed formula). | https://wiki.eveuniversity.org/Skills |
| Training speed | Omega: `SP/min = Primary + 0.5 x Secondary`. Alpha: `0.5 x Primary + 0.25 x Secondary`. Default 20/20 attributes: Omega 30 SP/min, Alpha 15 SP/min. 27/21 with +5 implants: 45 SP/min | https://wiki.eveuniversity.org/Skills |
| Attributes | Base 20 each (Charisma 19). Remap: base 17-27, 99 base points, 14 remappable. One normal remap (refills yearly) + two bonus remaps | https://wiki.eveuniversity.org/Skills |
| Prerequisites (examples) | Wolf: Minmatar Frigate V, Mechanics V, Power Grid Management V. Drake: Caldari Cruiser III, Caldari Battlecruiser I, Missile Launcher Operation III, Heavy Missiles I. Injecting a skillbook does not need the prerequisites | https://wiki.eveuniversity.org/Skills |
| Per-level bonuses | Surgical Strike +3% turret damage; Navigation 5% at V; Biology +20% booster duration; Industry -4% manufacturing time; Advanced Industry -3% manufacturing and research time; Accounting -11% sales tax; Broker Relations -0.3 pts; Jump Drive Calibration +20% range; Jump Fuel Conservation -10% fuel; Social +5% standing gain; Negotiation +5% ISK on missions; Connections +10% LP (division) | https://wiki.eveuniversity.org/Skills , https://wiki.eveuniversity.org/Manufacturing , https://wiki.eveuniversity.org/Jump_drive , https://wiki.eveuniversity.org/Missions |
| Skills that add capacity | Mass Production +1 manufacturing job/level (2 at I to 6 at V; start with 1); Advanced Mass Production +1/level (level IV gives 10 lines total); Laboratory Operation +1 research/copy job/level (6 at V); Advanced Laboratory Operation to a max of 11 research jobs; Contracting +4 outstanding contracts/level; Advanced Contracting +4/level; Corporation Contracting +10 corp contracts/level | https://wiki.eveuniversity.org/Manufacturing , https://wiki.eveuniversity.org/Research , https://wiki.eveuniversity.org/Contracts |
| Alpha vs Omega | Alpha trains at half speed. Skills page (as of 2025-03-01): Alpha 175 skills, 19,669,072 SP total, queue stops when trained + unallocated SP reaches 5,000,000; Omega all skills (494 skills, 604,416,000 SP). Alpha page: 5M free SP, up to 20.5M with injectors; ships up to battleship; no T2; no Planetary Industry; basic T1 manufacturing only; sells only within 5 jumps; one active contract; no level 4/5 missions; cannot log in with another character. The two pages give different Alpha totals | https://wiki.eveuniversity.org/Skills , https://wiki.eveuniversity.org/Alpha_clone |
| Skill injectors | Injector gives 500,000 SP under 5M total SP; 400,000 at 5-50M; 300,000 at 50-80M; 150,000 above 80M. Extractor holds 500,000 SP; needs 5.5M total SP; cannot drop you below 5M; consumed on use; bought for PLEX or ISK; prices set by players | https://wiki.eveuniversity.org/Injector |
| Skill purchases in the economy | See section 7 (Skill Purchase and Skill (Market) lines) | MER data |

---

## 3. Upkeep

| Item | Fact | Source |
|---|---|---|
| Structure fuel, one service module | Standup Manufacturing Plant I: 12 fuel blocks per hour (cycle fuel need 12, one-hour cycle); onlining draws 864 units (3 days of fuel). Read from a search summary of the database listing | https://everef.net/type/35878 |
| Structure fuel, base structure | A sandbox page found by search: Standard Astrahus 7.5 blocks/hour, Standard Raitaru 10 blocks/hour. A forum post says Raitaru uses 216 units/day (9/hour). These conflict | https://wiki.eveuniversity.org/User:Rayanth/SandboxTestingCodes , https://forums.eveonline.com/t/raitaru-fuel-problem/59895 |
| Fuel bonus | Citadels (Astrahus, Fortizar, Keepstar) and engineering complexes (Raitaru, Azbel, Sotiyo) have a 25% fuel usage bonus for their service type | https://wiki.eveuniversity.org/Upwell_structures |
| At zero fuel | Service modules go offline: manufacturing pauses, market activity stops, clones are locked | https://wiki.eveuniversity.org/Upwell_structures |
| Structure service slots | Astrahus 3, Fortizar 5, Keepstar 7, Raitaru 3, Azbel 5, Sotiyo 6 (page table is flattened; read with care) | https://wiki.eveuniversity.org/Upwell_structures |
| Anchoring rules | Corp must be 7+ days old; 1,000 km from other stations/gates; Keepstar and Sotiyo not in high-sec | https://wiki.eveuniversity.org/Upwell_structures |
| Ship insurance | Payout as % of CCP base value: none 40%, Basic 50%, Standard 60%, Bronze 70%, Silver 80%, Gold 90%, Platinum 100%. Example hull (Rupture): Basic costs 356,011.65 ISK and pays 3,560,116.50; Platinum costs 2,136,069.90 and pays 7,120,233.00. Modules, rigs, cargo, drones not insured. Page is undated | https://wiki.eveuniversity.org/Insurance |
| Insurance in the economy (Oct 2026) | Faucet about 4,334 B ISK vs sink about 1,694 B ISK (insurance pays out more than it costs) | MER data (section 7) |
| Other upkeep lines (Oct 2026 sinks) | Repair bill about 261 B ISK; office rental about 1,094 B ISK; jump clone activation about 462 B ISK | MER data (section 7) |

---

## 4. Planetary Industry (closest to "estates on a timer")

EVEU's PI pages are flagged by their editors as needing an update for the Equinox patch; values may be stale. The CCP support PI page returned 403.

| Item | Fact | Source |
|---|---|---|
| Planets | Interplanetary Consolidation raises the number of planets with a Command Center, up to 6 | https://wiki.eveuniversity.org/Planetary_Industry |
| Scanning | Remote Sensing I needed to scan; higher levels extend range | same |
| Upgrade level | Command Center Upgrades skill caps the CC level; each level adds CPU and powergrid (no numbers on the page) | same |
| Command Center storage | 500 m3 | same |
| Extractors | Up to 10 heads per control unit; each head 110 CPU and 550 powergrid; program 1 hour to 14 days; cycle times listed as 30 min (25 h program), 1 h (50 h), 2 h (4d4h), 4 h (8d8h) - the page's wording is unclear | https://wiki.eveuniversity.org/Planetary_Industry , https://wiki.eveuniversity.org/Planetary_Interaction |
| Yield decay | Rate not given. Actual yield is usually below the survey estimate; Planetology and Advanced Planetology narrow the gap | same |
| Factories | Basic: 3,000 R0 -> 20 P1 per 30 min. P1 -> P2: 80 P1 -> 5 P2 per 1 h (one page calls this ambiguous). P2 -> P3: 20 or 30 P2 -> 3 P3 per 1 h. P3 -> P4: 18 P3, or 12 P3 + 40 P1, -> 1 P4 | same |
| Base commodity cost for tax (ISK/unit) | R0 5, P1 400, P2 7,200, P3 60,000, P4 1,200,000 | https://wiki.eveuniversity.org/Planetary_Industry |
| Link cost | PG `10 + 0.15 x length`; CPU `15 + 0.2 x length` | same |
| Launchpad | CPU 3,600 tf; capacity not given | same |
| Taxes | See section 1 (POCO). MER Oct 2026: import tax sink about 45 B, export tax about 177 B, "Planetary Construction" about 688 B ISK | MER data |
| Alpha | Cannot do Planetary Industry | https://wiki.eveuniversity.org/Alpha_clone |

---

## 5. Passive and assigned income

| Mechanism | Facts | Source |
|---|---|---|
| Industry jobs | Slots from Mass Production / Advanced Mass Production; time -4%/level (Industry) and -3%/level (Advanced Industry); job cost formula in section 1 | https://wiki.eveuniversity.org/Manufacturing |
| Research jobs | Duration = base duration x blueprint rank (base series 105 s, 250, 595, 1,414, 3,360, 8,000, 19,000, 45,255, 107,700, 256,000 s for levels 1-10); ME level = -1% materials each, max 10; TE level = -2% time each, max 10; 1 slot at start, +1 per Laboratory Operation level | https://wiki.eveuniversity.org/Research |
| Structure bonuses | Raitaru: 1% material, 15% job duration, 3% job fee, 25% fuel; Azbel: 1%, 20%, 4%, 25%; Sotiyo: 1%, 30%, 5%, 25% (flattened table; column reading inferred by the fetch tool) | https://wiki.eveuniversity.org/Upwell_structures |
| Market order slots | Base 5; Trade +4/level, Retail +8/level, Wholesale +16/level, Tycoon +32/level; all four at V = 305 | https://wiki.eveuniversity.org/Market |
| Contracts and courier | Reward goes to hauler on delivery; collateral is held in escrow from the hauler and goes to the issuer if the package is opened, destroyed or late; set collateral above item value. Up to 200 stacks per contract. MER Oct 2026: contract brokers fee sink about 427 B ISK, contract sales tax about 282 B ISK | https://wiki.eveuniversity.org/Contracts , MER data |
| Hauling corp norms | Some hauling corps cap T1 jobs at 50,000,000 ISK collateral and 17,000 m3; about 1,000,000,000 ISK estimated starting capital for freighter courier work. No reward rates given | https://wiki.eveuniversity.org/Hauling |
| Corporation shares / dividends | Only forum sources found (2011 era, not official docs): shareholders are paid in proportion to shares when the CEO issues a dividend; dividends go to all shares, the CEO cannot choose recipients; master wallet plus six divisions. A recent forum proposal asks for scheduled/automatic dividends, which implies they do not exist now | https://forums-archive.eveonline.com/topic/470355/6 , https://forums.eveonline.com/t/corporation-shares-2-0-making-shares-actually-matter/517624.md |
| Loyalty points | Earned from agent missions (to the agent's corp), Incursions (CONCORD LP), Invasions (DED LP), Faction Warfare. Mission LP: `Base LP x (1.6288 - system security) x (1 + Division Connections x 0.1)`. Connections +10%/level (max +50%). Storyline, Career, R&D and Epic Arc missions give no LP. Store items cost LP plus often ISK and items. EVEU suggests at least 1,000 ISK per LP (2,000 LP ~ 2,000,000 ISK). CONCORD LP conversion: Empire factions 1:0.8, other non-pirate corps 1:0.4. MER Oct 2026: LP Store sink about 17,038 B ISK | https://wiki.eveuniversity.org/Loyalty_Points , https://wiki.eveuniversity.org/Missions , MER data |

---

## 6. Security bands as area tiers

| Band | Range | Rules | Risk vs reward | Source |
|---|---|---|---|---|
| High-sec | 0.5-0.9 (1.0 Exordium is PvP-free) | CONCORD kills aggressors, in 0 to 24 seconds depending on system security; sentries at gates/stations; no bubbles; NPC sovereignty only; true capitals cannot enter | Lowest risk and reward. Aggression costs security status | https://wiki.eveuniversity.org/System_security , https://wiki.eveuniversity.org/Security_status |
| Low-sec | 0.1-0.4 | No CONCORD response to player aggression; fewer sentries; bubbles only in some Faction Warfare systems; NPC sovereignty | Moderate. Better asteroids, tougher rats, better mission LP, more PI abundance | same |
| Null-sec | 0.0 to -1.0 | No law response; bubbles, bombs and doomsdays allowed; NPC null or player-claimable sovereignty; many structures need sovereignty to anchor | Highest risk and reward; richest PI resources | same |
| Wormholes | Classes C1-C6 | No CONCORD, no sovereignty. Max single-jump mass: C1 62,000 t, C2-C4 300,000 t, C5-C6 1,350,000 t. C1 statics admit nothing bigger than a battlecruiser. Capital escalations only in C5-C6. C1-C2 soloable by a battlecruiser; C5-C6 for large corps. About 2,600 systems | https://wiki.eveuniversity.org/Wormhole_space |
| Security status | Range -10 to +10; -5.0 or lower is outlaw; faction police respond from -2.0 (in 1.0 systems) to -4.5 (in 0.5 systems) | | | https://wiki.eveuniversity.org/Security_status |
| Mission pay | Depends on true security (lower truesec pays more) | | | https://wiki.eveuniversity.org/System_security |

**Agent gating by standing (EVEU, undated):**

| Agent level | General | COSMOS | R&D |
|---|---|---|---|
| 1 | any | not listed | -2.00 |
| 2 | 1.00 | 2.00 | 1.00 |
| 3 | 3.00 | 4.00 | 3.00 |
| 4 | 5.00 | 6.00 | 5.00 |
| 5 | 7.00 | not listed | N/A |

Source: https://wiki.eveuniversity.org/Agents . One of personal, corp or faction standing must reach the level; corp or faction standing alone unlocks every agent of that level in that corp.

Mission level vs ship (https://wiki.eveuniversity.org/Missions): L1 basic frigates; L2 cruisers; L3 battlecruisers (highest level Alpha can take); L4 battleships (Omega); L5 group/capital encounters, low-sec only (Omega). ISK per mission level: not given on any page I read.

---

## 7. Faucets and sinks: CCP Monthly Economic Report data

How I got the figures: the MER web pages show charts only. I downloaded the October 2026 raw data zip, file `sinks_and_faucets_history.csv` (daily rows, ISK), and summed the 31 days of 2026-10 myself. These sums are my arithmetic on CCP's file, not numbers printed in the report. Units: billions of ISK (B).

**Top faucets, October 2026 (ISK created)**

| Faucet | B ISK |
|---|---|
| Commodity (Market) (NPC buyers of loot) | 60,942 |
| Bounty Prizes | 59,582 |
| ESS Main Bank Autopayment | 30,744 |
| Corporate Reward Payout (Sansha Incursions) | 18,377 |
| Corporate Reward Payout (Triglavian Invasions) | 8,526 |
| Corporate Reward Payout (Pirate FOBs) | 8,009 |
| Insurance | 4,334 |
| Agent Mission Reward | 3,368 |
| Total of all faucet lines | about 201,300 |

**Top sinks, October 2026 (ISK destroyed)**

| Sink | B ISK |
|---|---|
| Transaction Tax (sales tax) | 33,438 |
| LP Store | 17,038 |
| Skill Purchase | 11,699 |
| Brokers Fee | 11,310 |
| Manufacturing (job install cost) | 11,290 |
| Skill (Market) | 6,592 |
| Blueprint (Market) | 6,445 |
| Hypernet Relay Tax | 4,234 |
| Asset Safety recovery Tax | 2,771 |
| Reactions | 2,138 |
| SCC surcharge | 2,067 |
| Researching Material Productivity | 1,890 |
| Insurance | 1,694 |
| Office Rental Fee | 1,094 |
| Planetary Construction | 688 |
| Jump Clone Activation Fee | 462 |
| Contract Brokers Fee | 427 |
| Contract Sales Tax | 282 |
| Repair Bill | 261 |
| Planetary Export Tax | 177 |
| Industry Job Tax | 79 |
| Security Processing Fee | 79 |
| Reprocessing Tax | 38 |
| Bounty Surcharge | 25 |
| Total of all sink lines | about 119,400 |

Notes:
- The sum of faucet lines is larger than the sum of sink lines for the month. CCP's own text headline is "Net active ISK rose to about +1.1 trillion in October" (after about -144.7 trillion in September), from a search summary of the October page. My two column totals are not the same quantity as that headline and I do not claim how they reconcile.
- Money supply on 2026-10-31 (`money_supply.csv`): 2,978 trillion ISK total (characters 2,347T, corporations 631T); velocity 0.334.
- Report text context: August 2026 MER (2026-09-09): Module Price Index about -4% month on month; the summer slowdown "appears to have eased" (https://www.eveonline.com/news/view/monthly-economic-report-august-2026). Search summaries of the March and May 2026 reports: total faucets +17% (March), +26% (May, driven by Bounty Prizes and Commodities).

Reading it: trade tax is the biggest pure sink; the biggest faucets are NPC payments for kills and NPC purchase of loot; skills, blueprints and the LP store are large sinks that turn ISK into progression.

---

## 8. Hauling and trade

| Class | Cargo (m3) | Source |
|---|---|---|
| T1 haulers | 500 (Hoarder) to 7,300 (Tayra); Iteron Mark V 5,800 | https://wiki.eveuniversity.org/Hauling |
| Blockade runners (cloaked) | 2,900-4,300 (about 10,000 if fitted for cargo) | same |
| Deep Space Transports | 3,100-5,000 + 50,000 fleet hangar | same |
| Freighters | 435,000-465,000 | same |
| Jump freighters | 132,000-144,000 | same |
| Orca | 30,000 cargo (expandable to 90,000+), 150,000 mining hold | same |

- Jump drive (https://wiki.eveuniversity.org/Jump_drive): isotopes used = `D x F x (1-0.1xJFC) x (1-0.1xJF) x (Jump Drive Economizer terms)`; jump freighter range 5.0 ly base, 10 with skills; Jump Drive Calibration +20%/level. Fatigue: minimum 10 x (1+LY) minutes, otherwise existing fatigue x (1+LY), cap 5 hours. Activation cooldown min (1+LY) minutes, max 30 minutes. In-transit jump time: not given. Conflict: an older CCP-era summary found by search says the fatigue cap is 30 days (https://www.eveonline.com/news/view/phoebe-travel-change-update).
- Ganking risk rule of thumb: keep cargo + fit under about 3M ISK per 1,000 EHP; 4-6M can work on a known route. T1 hauler EHP about 4,000-20,000; freighter about 180,000-200,000 EHP with about 1-1.5B cargo as a rough benchmark. https://wiki.eveuniversity.org/Hauling
- Region price differences as profit source: no page I read gives a margin figure.

---

## 9. What the UI shows

- Wallet journal lines: the MER file lists the journal categories, including Transaction Tax, Brokers Fee, Bounty Prizes, Agent Mission Reward, LP Store, Manufacturing, Researching Material/Time Productivity, Copying, Industry Job Tax, Reprocessing Tax, Planetary Import/Export Tax, Planetary Construction, Contract Brokers Fee, Contract Sales Tax, Insurance, Repair Bill, Office Rental Fee, Jump Clone Activation Fee, Asset Safety recovery Tax, SCC surcharge, Bounty Surcharge, Skill Purchase, Corporate Reward Payout, ESS Main Bank Autopayment, Alliance Maintainance Fee, War Fee. Source: MER `sinks_and_faucets_history.csv` (Oct 2026).
- Brokers fee and transaction tax are separate journal entries: broker's fee when an order is placed, sales tax when it sells. API names include bounty_prize, brokers_fee, transaction_tax. https://forums.eveonline.com/t/esi-wallet-journal-question/73156.md , https://wiki.eveuniversity.org/Sales_tax
- Industry: the job window Facilities tab shows each activity's system cost index as a red bar. https://wiki.eveuniversity.org/Industry
- ISK-per-hour tools: a search listing named LP store comparison tools (DaOpa's LP Stores Database, Fuzzwork LP Store return of ISK, Arin's Loyalty Point Offer Comparator, EVE Starweb). I read the search summary only, not those sites.

---

## What transfers to an HQ trading-company game

1. Tax cut by skill with one linear formula: `base x (1 - 0.11 x level)` (Accounting), floor about 45% of base at level 5. Section 1.
2. Two-part market cost: a fee when you list, a tax when it sells, as separate journal lines. Good for a per-transaction tax line. Sections 1, 9.
3. Standing as a second discount: broker fee and reprocessing tax fall to a floor at a standing threshold (0% at 6.67 for reprocessing). Maps to city or guild reputation. Sections 1, 6.
4. Capacity is a skill: +1 slot per level for jobs, research, orders, contracts, with a second tier unlocked at level V of the first. Maps to captain slots and fleet size. Sections 2, 5.
5. Job cost = value x (local activity index + facility tax + fixed surcharge), capped at 10%. The index rises where many players work, so crowded places cost more. Section 1.
6. Fuel per hour per service module; all services go offline at zero fuel. This is the "maintenance per hour" model for estates. Section 3.
7. Planetary Industry: timed extraction programs plus factory chains with fixed cycle times, taxed on import and export, capped by a planet-count skill and an upgrade skill. Direct analogue of farm and mine estates. Section 4.
8. Security bands as access tiers: richer output where law is weaker (CONCORD response time shortens as security rises). Section 6.
9. Agents gated by standing 1/3/5/7 for levels 2-5, and by ship class per mission level. A template for rank-gated work tiers. Sections 6.
10. Money balance: the biggest faucet is NPC payment for kills and loot; the biggest sink is trade tax, then LP store and skills. Keep a monthly faucet-vs-sink table. Section 7.

---

## Not verified

- Official CCP Support pages (PI, fuel, taxes, insurance): not reachable or not found; EVEU used instead (CCP PI page returned 403).
- Current structure fuel per hour for Astrahus / Raitaru / each service module (a sandbox page, a forum post and one database listing; they conflict: 7.5 vs 10 vs 9).
- Clone and implant loss costs, ammo costs, sovereignty bill amounts.
- Whether ship insurance still works as the undated EVEU page says.
- PI: Command Center level-by-level CPU/PG and upgrade costs, extractor yield decay rate, launchpad/storage capacity, building install costs.
- Customs Code Expertise: 1% per level (PI pages) vs 10% per level (Tax page).
- Industry SCC surcharge 4% (one EVEU page) and Alpha tax 0.25% vs 2%.
- Alpha SP totals (19.67M vs 20.5M); jump fatigue cap (5 hours vs 30 days).
- Sales tax before 2025-03: 4% vs 4.5% on the same EVEU page.
- Mission ISK rewards and base LP per level, ISK per hour of any activity, region price gaps and trade margins, jump travel time, how corporation dividends work today (only old forum posts).
- The MER's own faucet/sink text (pages show charts only; the figures in section 7 are my sums of CCP's CSV).
- The structure-bonus table reading (Raitaru/Azbel/Sotiyo) is inferred by the fetch tool from a flattened table.
