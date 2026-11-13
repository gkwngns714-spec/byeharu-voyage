# 2026-11-13: more ships, to trade, to carry and above all to fight (migration 0366, owner row 322)

The owner, row 322: *"i need more trade ships, cargo, and especially combat related ships."*

## What was there

103 classes of hull: the live three (Barca, Caravela latina, Nau) and the 100 the generator makes (`scripts/build-ships.mjs`, Waves A to D). By role: combat 44, trade 43, explorer 12, support 4.

- Every hull is one archetype (size and role, the Portuguese figures) times its line (the eleven shipbuilding countries of `data/ship-lines.json`) times its tech (T1, T2, famous).
- A hull's rows: `ship_classes`, `class_profile`, `class_slots`, `class_cabins`, `hull_recipes`, `hull_recipe_goods`, `hull_recipe_items`, `skill_requirements`.
- `cmd.do_build` is one verb over `hull_recipes`. It has no list of hulls in it. `world.snapshot` and `world.building_yard` serve every class. So a hull that has its rows is in the yard and the Codex at once.
- `scripts/db/world-guard.mjs` re-runs the generator on every apply and holds every one of those tables to it. That is the check that keeps `data/ships.generated.json` and the database equal.
- The chart draws a hull by her rig family and her size (twelve silhouettes, `src/chart/glyphs.ts` `hullShapeFor`). Both are served columns, so a new class is drawn through the one renderer with no new code.
- Every reader of a class on the NPC side is keyed by the ship's own class or by a knob (`fight_raider_class`, `navy_ship_class`, `convoy_ship_class`, `convoy_armed_class`, `pirate_ship_class`, `pirate_merchant_class`). No NPC rule lists the catalogue. The one table that picks a merchant's hull, `npc_line_hulls`, is loaded by a migration and compared with the generator's `merchant` rows.
- Since 0208 and 0220 the database holds each hull's hold times `hold_scale` (3) and speed times `speed_scale` (3). The data file keeps the design figures.

## What was built

54 new classes, Wave E of the same generator. Combat 31, support (escorts) 4, trade 19. The roster is 157.

Each new hull is the archetype of its size and role, times its line, times ONE JOB (`JOBS` in the generator). A job is a trade: it gives in one place and takes in another, and it costs yard labour. The six plain traders have no job. They are the archetype times the line, for a size the line had no trader at.

| job | role | gives | takes | labour | materials |
|---|---|---|---|---|---|
| raider | combat | speed x 1.06, sighting +3, handling +4 | hull x 0.85, hold x 0.8, armour -3 | x 1.10 | template x 0.9 |
| gunship | combat | attack x 1.2, reach +12, accuracy +6 | crew x 0.65, hull x 0.92, speed x 0.97, hold x 0.85, handling -4 | x 1.25 | template, iron 4 a size |
| boarder | combat | berths x 1.5 (crew she must have x 1.2) | attack x 0.7, reach -14, hull x 0.9, armour -4, accuracy -4, hold x 0.7 | x 1.10 | template, iron 2 a size |
| line | combat | hull x 1.25, armour +12, attack x 1.1, crew x 1.1, reach +2 | speed x 0.92, hold x 0.7, handling -8 | x 1.40 | template x 1.25, iron 6 a size |
| escort | support | reach +14, sighting +6, accuracy +8, armour +6, hull x 1.25, attack x 1.3 | hold x 0.8 | x 1.20 | template x 1.1, iron 3 a size |
| armed | trade | attack x 1.7, berths x 1.5 (crew she must have x 1.25), accuracy +6, reach +6, armour +5, hull x 1.05 | hold x 0.85, speed x 0.98 | x 1.20 | template, iron 3 a size |
| carrier | trade | hold x 1.3, hull x 1.1 | speed x 0.88, attack x 0.5, handling -8, armour -3, sighting -1 | x 1.15 | template x 1.2 |

Why each figure moves, in the fight as it is (`public.fight_sides`, six rounds: three LONG at 0.6 of accuracy, two MEDIUM at 0.8, one CLOSE):

- **Sighting.** The side with the better best sighting fires the first round alone. If that is the side set upon, it may slip away: 3 % a point of lead, at most 30 %. The side that closes never slips. So sighting is the defender's figure. A raider has it to run, an escort has it for the whole convoy.
- **Reach.** At LONG range a hull fires only if her reach is at least the other side's best. Three of the six rounds are LONG. A gunship is built to own those three rounds. One escort gives her reach to her whole fleet: raiders with shorter guns are silent for three rounds.
- **Armour and hull.** A hit is attack x 0.7 x (0.75 to 1.25), less armour x 0.5 %. The side that closes breaks off at 15 % of its hull lost. A line ship has the hull and the armour never to break off. A boarder's thin hull is what a gunship breaks.
- **Crew.** If nobody breaks off, the fight is boarded: each side's power is crew x 0.15 + tier x 3, times the share of hull left. The side set upon holds at 1.2 times the other's power, pays ransom from 0.7, and is plundered below. A boarder is a crowd. A gunship has few hands and cannot take anybody. An armed trader has the berths to hold her own deck.
- **A shot falls on hulls by their size.** An escort's big hull draws the fire that would land on the carrier.
- **Wave resistance** is the one rule of 0215 (12 a size, plus the rig, plus 2 for an explorer). It is derived, never set by a job. A galley (oared, -6) is the worst sea boat of her size, a square-rigged carrier (+3) the best.
- **Wages** are 5 d. a hand a voyage-day (`wage_per_crew_day`), stores are per hand too. So a boarder (crew x 1.2 to 1.5) and a line ship are dear to keep at sea, and a gunship (crew x 0.65) is cheap. That is part of each job's price.

Price. A hull's `ducats` is the yard's labour: the archetype's labour x the line's factor x the job's, rounded to 500. `build_cost` is four times that (0072's rule; it is what a crown pays for a navy hull). The materials are the size's template with the line's own goods, times the job's factor, plus iron for a gunned job. Where they pass 750 tuns (the biggest shed) the generator scales them to fit and moves their value into labour, as it does for every capital since 0138 (six of the 54: Nau capitânia 10,000, Barza 10,000, Louchuan 6,000, Tekkōsen 4,500, Jong 6,500, Nave grossa 31,000).

Requirements. Every one of the 54 is T1. It asks what a T1 hull of its line and size asks, by the existing ladder (`requirementsOf`, unchanged): small, the line's Small Hulls I; light, Small III and Light I; medium, Light III and Medium I; heavy, Medium III, Heavy I and the role skill I; capital, Heavy III, Capital I, Command III and the role skill III; the one flagship (Nave grossa), Capital V, Fleet Command I and Merchant Ships V. No new skill.

Where. A hull is laid down at a build yard of her line's countries, of her size's tier (1 small, 2 light, 3 medium and up). Every line has a tier-3 yard:

| line | built by | yards (tier) |
|---|---|---|
| PRT | Portugal | Lisbon 3, Malacca 2, Old Goa 2, Salvador 2, Macau 1 |
| ESP | Spain | Antwerp 3, Seville 3, Cadiz 2, Callao 2, Havana 2, Manila 2, Barcelona 1, Cartagena 1, Veracruz 1 |
| NLD | the Netherlands, the Hanse, Poland, Denmark, Sweden | Amsterdam 3, Hamburg 3, Gdansk 2, Lubeck 2, Copenhagen 1 |
| ENG | England | London 3 |
| FRA | France | Marseille 3, Bordeaux 2 |
| ITA | Venice, Genoa | Genoa 3, Venice 3 |
| OTT | the Ottoman Empire | Istanbul 3, Alexandria 2 |
| IND | Gujarat, Malabar, Banten | Surat 3, Jakarta 2, Kochi 2, Kozhikode 2 |
| CHN | Ming China | Guangzhou 3 |
| JPN | Japan | Osaka 3, Nagasaki 1, Tokyo 1 |
| KOR | Joseon | Busan 3 |

Every line gained at least one hull that fights and one that carries. The Hanseatic and northern ships (Schnigge, Kogge, Holk, Kraweel, Friedeschiff) are in the NLD line, which the Hanse towns already build. The Malay and Javanese ships (Lancaran, Ghali, Jong) are in the IND line, which Banten builds.

Names. Every name is a real ship type of its coast, in or near 1507: bergantim, balinger, schnigge, galliot (galeotta, kalyata), firkate, lancaran, the Ming patrol boat and centipede ship, the wako's bahan ship, the Joseon scout boat, sword ship and the three maengseon classes that were the navy's standard in 1507, galé and galera, the great galley, the roberge, the göke of 1495, the barza, the nef, the kraweel (the Peter von Danzig), the tower ship, the Hanse's peace ships, the English wafters of the wool fleet, the almiranta of a Spanish flota, cog, hulk, cocca, taforeia, hourque, nao, the kenminsen of the missions to Ming, the byeongjoseon (built since the 1460s for both war and the grain run), kotia, boum, the jong. Two are later than 1507 and are said so here: the roberge (1540s) and the Tekkōsen (1578). The game already has the turtle ship of 1592 and the fluit.

## The 54, and the roster

### The roster by role

| role | before | new | after |
|---|---|---|---|
| combat | 44 | 31 | 75 |
| support | 4 | 4 | 8 |
| trade | 43 | 19 | 62 |
| explorer | 12 | 0 | 12 |
| all | 103 | 54 | 157 |

By job: raider 10, gunship 5, boarder 10, line 6, escort 4, armed 5, carrier 8, plain trader 6.

### The 54

| name | Korean | role and job | line | size | needs | labour d. | price d. | hold t | knots | crew | hull | armour | attack | accuracy | reach | sighting | wave |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Bergantim | 베르간팅 | Combat: Raider | PRT | Small | PRT_SMALL I | 19,000 | 76,000 | 24 | 6.6 | 14 / 40 | 300 | 3 | 20 | 30 | 30 | 12 | 6 |
| Schnigge | 슈니게 | Combat: Raider | NLD | Small | NLD_SMALL I | 16,500 | 66,000 | 30 | 6.4 | 10 / 30 | 270 | 0 | 20 | 30 | 30 | 12 | 13 |
| Balinger | 밸린저 | Combat: Raider | ENG | Light | ENG_SMALL III, ENG_LIGHT I | 46,000 | 184,000 | 50 | 7.3 | 28 / 90 | 390 | 3 | 50 | 46 | 38 | 14 | 25 |
| Brigantin | 브리강탱 | Combat: Raider | FRA | Small | FRA_SMALL I | 20,000 | 80,000 | 24 | 6.8 | 14 / 40 | 300 | 3 | 20 | 34 | 30 | 13 | 6 |
| Galeotta | 갈레오타 | Combat: Raider | ITA | Light | ITA_SMALL III, ITA_LIGHT I | 48,500 | 194,000 | 50 | 7 | 38 / 122 | 390 | 5 | 60 | 40 | 20 | 14 | 18 |
| Firkate | 피르카테 | Combat: Raider | OTT | Small | OTT_SMALL I | 19,000 | 76,000 | 23 | 6.4 | 18 / 50 | 330 | 7 | 20 | 30 | 26 | 12 | 6 |
| Lancaran | 란차란 | Combat: Raider | IND | Light | IND_SMALL III, IND_LIGHT I | 37,500 | 150,000 | 60 | 7.3 | 24 / 76 | 430 | 3 | 30 | 28 | 20 | 15 | 18 |
| Shaochuan | 초선 | Combat: Raider | CHN | Small | CHN_SMALL I | 17,500 | 70,000 | 28 | 6.2 | 14 / 40 | 360 | 9 | 20 | 26 | 30 | 12 | 12 |
| Bahansen | 바한선 | Combat: Raider | JPN | Light | JPN_SMALL III, JPN_LIGHT I | 44,000 | 176,000 | 50 | 7 | 32 / 103 | 390 | 7 | 60 | 44 | 22 | 15 | 25 |
| Sahuseon | 사후선 | Combat: Raider | KOR | Small | KOR_SMALL I | 19,000 | 76,000 | 22 | 6.4 | 15 / 44 | 330 | 13 | 20 | 34 | 30 | 12 | 6 |
| Galeoncete | 갈레온세테 | Combat: Gunship | ESP | Medium | ESP_LIGHT III, ESP_MEDIUM I | 234,000 | 936,000 | 255 | 4.5 | 67 / 164 | 2,120 | 40 | 230 | 64 | 88 | 14 | 39 |
| Great Galley | 그레이트 갤리 | Combat: Gunship | ENG | Heavy | ENG_MEDIUM III, ENG_HEAVY I, SHIPS_OF_WAR I | 361,000 | 1,444,000 | 330 | 4.7 | 84 / 208 | 2,450 | 38 | 300 | 74 | 98 | 14 | 42 |
| Roberge | 로베르주 | Combat: Gunship | FRA | Medium | FRA_LIGHT III, FRA_MEDIUM I | 223,000 | 892,000 | 255 | 4.8 | 58 / 143 | 1,840 | 34 | 210 | 68 | 84 | 15 | 37 |
| Göke | 괴케 | Combat: Gunship | OTT | Capital | OTT_HEAVY III, OTT_CAPITAL I, COMMAND III, SHIPS_OF_WAR III | 594,000 | 2,376,000 | 485 | 4.1 | 162 / 390 | 4,050 | 52 | 470 | 68 | 90 | 14 | 63 |
| Wugongchuan | 오공선 | Combat: Gunship | CHN | Light | CHN_SMALL III, CHN_LIGHT I | 45,000 | 180,000 | 70 | 6.1 | 18 / 58 | 530 | 14 | 50 | 40 | 42 | 11 | 18 |
| Galé | 갈레 | Combat: Boarder | PRT | Medium | PRT_LIGHT III, PRT_MEDIUM I | 187,000 | 748,000 | 210 | 4.8 | 108 / 330 | 1,800 | 30 | 120 | 54 | 58 | 14 | 30 |
| Galera | 갈레라 | Combat: Boarder | ESP | Medium | ESP_LIGHT III, ESP_MEDIUM I | 205,500 | 822,000 | 210 | 4.6 | 124 / 379 | 2,070 | 36 | 140 | 54 | 62 | 14 | 30 |
| Galea capitana | 갈레아 카피타나 | Combat: Boarder | ITA | Heavy | ITA_MEDIUM III, ITA_HEAVY I, SHIPS_OF_WAR I | 333,000 | 1,332,000 | 265 | 4.6 | 211 / 648 | 2,390 | 36 | 190 | 58 | 54 | 14 | 42 |
| Kalyata | 칼리아타 | Combat: Boarder | OTT | Light | OTT_SMALL III, OTT_LIGHT I | 44,000 | 176,000 | 47 | 6.5 | 42 / 169 | 480 | 8 | 40 | 34 | 12 | 11 | 18 |
| Parau | 파라우 | Combat: Boarder | IND | Small | IND_SMALL I | 16,500 | 66,000 | 23 | 6.4 | 14 / 51 | 330 | 0 | 10 | 16 | 6 | 10 | 6 |
| Ghali | 갈리 | Combat: Boarder | IND | Medium | IND_LIGHT III, IND_MEDIUM I | 159,000 | 636,000 | 225 | 5 | 92 / 280 | 1,890 | 28 | 70 | 44 | 48 | 15 | 30 |
| Mengchong | 몽충선 | Combat: Boarder | CHN | Medium | CHN_LIGHT III, CHN_MEDIUM I | 168,500 | 674,000 | 240 | 4.6 | 108 / 330 | 2,160 | 36 | 110 | 50 | 58 | 14 | 30 |
| Mekurabune | 메쿠라부네 | Combat: Boarder | JPN | Medium | JPN_LIGHT III, JPN_MEDIUM I | 187,000 | 748,000 | 190 | 4.8 | 124 / 379 | 1,710 | 32 | 130 | 60 | 50 | 15 | 30 |
| Geomseon | 검선 | Combat: Boarder | KOR | Light | KOR_SMALL III, KOR_LIGHT I | 44,000 | 176,000 | 44 | 6.4 | 37 / 148 | 480 | 14 | 40 | 38 | 16 | 11 | 18 |
| Daemaengseon | 대맹선 | Combat: Boarder | KOR | Heavy | KOR_MEDIUM III, KOR_HEAVY I, SHIPS_OF_WAR I | 302,500 | 1,210,000 | 265 | 4.5 | 172 / 528 | 2,770 | 46 | 180 | 60 | 64 | 14 | 42 |
| Nau capitânia | 나우 카피타니아 | Combat: Line ship | PRT | Capital | PRT_HEAVY III, PRT_CAPITAL I, COMMAND III, SHIPS_OF_WAR III | 675,000 | 2,700,000 | 420 | 4 | 220 / 528 | 5,000 | 60 | 370 | 62 | 84 | 14 | 63 |
| Kraweel | 크라벨 | Combat: Line ship | NLD | Heavy | NLD_MEDIUM III, NLD_HEAVY I, SHIPS_OF_WAR I | 327,000 | 1,308,000 | 370 | 4.1 | 107 / 264 | 3,150 | 48 | 200 | 60 | 80 | 14 | 51 |
| Nef | 네프 | Combat: Line ship | FRA | Heavy | FRA_MEDIUM III, FRA_HEAVY I, SHIPS_OF_WAR I | 404,000 | 1,616,000 | 295 | 4.4 | 143 / 352 | 3,500 | 52 | 280 | 64 | 80 | 15 | 51 |
| Barza | 바르차 | Combat: Line ship | ITA | Capital | ITA_HEAVY III, ITA_CAPITAL I, COMMAND III, SHIPS_OF_WAR III | 741,500 | 2,966,000 | 380 | 4 | 297 / 713 | 4,750 | 60 | 430 | 64 | 74 | 14 | 63 |
| Louchuan | 누선 | Combat: Line ship | CHN | Capital | CHN_HEAVY III, CHN_CAPITAL I, COMMAND III, SHIPS_OF_WAR III | 604,500 | 2,418,000 | 485 | 3.8 | 220 / 528 | 6,000 | 66 | 340 | 58 | 84 | 14 | 60 |
| Tekkōsen | 뎃코센 | Combat: Line ship | JPN | Capital | JPN_HEAVY III, JPN_CAPITAL I, COMMAND III, SHIPS_OF_WAR III | 669,500 | 2,678,000 | 380 | 4 | 253 / 607 | 4,750 | 62 | 410 | 68 | 76 | 15 | 54 |
| Friedeschiff | 프리데시프 | Support: Escort | NLD | Medium | NLD_LIGHT III, NLD_MEDIUM I | 153,000 | 612,000 | 280 | 4.7 | 52 / 135 | 1,910 | 36 | 100 | 63 | 74 | 20 | 39 |
| Wafter | 와프터 | Support: Escort | ENG | Light | ENG_SMALL III, ENG_LIGHT I | 56,500 | 226,000 | 75 | 6.1 | 20 / 60 | 770 | 18 | 40 | 56 | 72 | 17 | 25 |
| Almiranta | 알미란타 | Support: Escort | ESP | Heavy | ESP_MEDIUM III, ESP_HEAVY I, ESCORT_SUPPORT I | 343,000 | 1,372,000 | 385 | 4.3 | 115 / 299 | 3,880 | 56 | 240 | 68 | 88 | 20 | 51 |
| Jungmaengseon | 중맹선 | Support: Escort | KOR | Medium | KOR_LIGHT III, KOR_MEDIUM I | 180,000 | 720,000 | 200 | 4.7 | 77 / 198 | 2,340 | 50 | 140 | 67 | 74 | 20 | 30 |
| Caravelão | 카라벨랑 | Trade | PRT | Light | PRT_SMALL III, PRT_LIGHT I | 35,000 | 140,000 | 130 | 5.4 | 14 / 34 | 600 | 12 | 20 | 30 | 40 | 10 | 24 |
| Chalupa | 찰루파 | Trade | ESP | Small | ESP_SMALL I | 16,500 | 66,000 | 60 | 4.8 | 9 / 23 | 460 | 11 | 0 | 0 | 24 | 8 | 13 |
| Tartana | 타르타나 | Trade | ITA | Small | ITA_SMALL I | 16,500 | 66,000 | 55 | 5 | 11 / 27 | 380 | 5 | 0 | 0 | 10 | 8 | 12 |
| Boum | 붐 | Trade | IND | Light | IND_SMALL III, IND_LIGHT I | 30,000 | 120,000 | 140 | 5.6 | 12 / 29 | 630 | 10 | 10 | 20 | 30 | 11 | 24 |
| Şayka | 샤이카 | Trade | OTT | Light | OTT_SMALL III, OTT_LIGHT I | 35,000 | 140,000 | 125 | 5.3 | 18 / 42 | 660 | 16 | 20 | 30 | 36 | 10 | 25 |
| Bezaisen | 벤자이센 | Trade | JPN | Light | JPN_SMALL III, JPN_LIGHT I | 35,000 | 140,000 | 115 | 5.4 | 16 / 39 | 570 | 14 | 20 | 36 | 32 | 11 | 27 |
| Nao | 나오 | Trade: Armed trader | ESP | Heavy | ESP_MEDIUM III, ESP_HEAVY I, MERCHANT_SHIPS I | 317,000 | 1,268,000 | 510 | 4.1 | 115 / 345 | 2,900 | 43 | 220 | 56 | 75 | 13 | 51 |
| Kogge | 코게 | Trade: Armed trader | NLD | Light | NLD_SMALL III, NLD_LIGHT I | 35,500 | 142,000 | 140 | 5.2 | 13 / 38 | 570 | 13 | 30 | 36 | 46 | 10 | 27 |
| Byeongjoseon | 병조선 | Trade: Armed trader | KOR | Medium | KOR_LIGHT III, KOR_MEDIUM I | 180,000 | 720,000 | 305 | 4.2 | 82 / 231 | 2,080 | 45 | 220 | 65 | 76 | 14 | 36 |
| Kenminsen | 겐민센 | Trade: Armed trader | JPN | Heavy | JPN_MEDIUM III, JPN_HEAVY I, MERCHANT_SHIPS I | 288,000 | 1,152,000 | 460 | 4.3 | 115 / 345 | 2,390 | 39 | 210 | 62 | 63 | 14 | 51 |
| Kotia | 코티아 | Trade: Armed trader | IND | Medium | IND_LIGHT III, IND_MEDIUM I | 153,000 | 612,000 | 365 | 4.5 | 64 / 178 | 1,980 | 33 | 120 | 51 | 66 | 15 | 36 |
| Hoy | 호이 | Trade: Cargo | ENG | Small | ENG_SMALL I | 18,000 | 72,000 | 70 | 4.6 | 8 / 20 | 420 | 0 | 0 | 0 | 28 | 7 | 13 |
| Holk | 홀크 | Trade: Cargo | NLD | Medium | NLD_LIGHT III, NLD_MEDIUM I | 146,500 | 586,000 | 650 | 3.8 | 45 / 105 | 1,780 | 23 | 40 | 55 | 70 | 13 | 39 |
| Cocca | 코카 | Trade: Cargo | ITA | Medium | ITA_LIGHT III, ITA_MEDIUM I | 190,000 | 760,000 | 470 | 3.9 | 81 / 189 | 1,880 | 27 | 70 | 57 | 60 | 13 | 39 |
| Caochuan | 조량선 | Trade: Cargo | CHN | Medium | CHN_LIGHT III, CHN_MEDIUM I | 155,000 | 620,000 | 600 | 3.7 | 60 / 140 | 2,380 | 33 | 50 | 51 | 70 | 13 | 36 |
| Taforeia | 타포레이아 | Trade: Cargo | PRT | Heavy | PRT_MEDIUM III, PRT_HEAVY I, MERCHANT_SHIPS I | 276,000 | 1,104,000 | 780 | 3.9 | 80 / 200 | 2,640 | 29 | 60 | 50 | 65 | 12 | 51 |
| Hourque | 우르크 | Trade: Cargo | FRA | Heavy | FRA_MEDIUM III, FRA_HEAVY I, MERCHANT_SHIPS I | 290,000 | 1,160,000 | 780 | 4 | 80 / 200 | 2,640 | 29 | 60 | 54 | 65 | 13 | 51 |
| Jong | 종 | Trade: Cargo | IND | Capital | IND_HEAVY III, IND_CAPITAL I, COMMAND III, MERCHANT_SHIPS III | 397,500 | 1,590,000 | 1,265 | 3.8 | 102 / 255 | 3,930 | 33 | 50 | 40 | 55 | 13 | 61 |
| Nave grossa | 나베 그로사 | Trade: Cargo | ITA | Flagship | ITA_CAPITAL V, FLEET_COMMAND I, MERCHANT_SHIPS V | 980,000 | 3,920,000 | 1,755 | 3.4 | 270 / 675 | 5,220 | 39 | 130 | 52 | 55 | 12 | 75 |

### Each new hull beside older hulls of her size (her own line's, or the Portuguese ones)

Each cell is the new hull / the older hull.

| new hull | older hull | labour | hold | knots | crew | hull | armour | attack | reach | sighting | which is better where |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bergantim | Fusta | 19,000 / 19,000 | 24 / 27 | 6.6 / 6.2 | 14-40 / 19-54 | 300 / 330 | 3 / 6 | 20 / 20 | 30 / 20 | 12 / 9 | more speed, reach, sighting; less hold, hull, armour, accuracy, berths, handling |
| Schnigge | Jacht | 16,500 / 10,000 | 30 / 44 | 6.4 / 6.3 | 10-30 / 4-12 | 270 / 270 | 0 / 0 | 20 / 0 | 30 / 20 | 12 / 10 | more speed, attack, accuracy, reach, sighting, berths, handling; less hold |
| Schnigge | Fusta | 16,500 / 19,000 | 30 / 27 | 6.4 / 6.2 | 10-30 / 19-54 | 270 / 330 | 0 / 6 | 20 / 20 | 30 / 20 | 12 / 9 | more hold, speed, reach, sighting; less hull, armour, accuracy, berths, handling |
| Balinger | Caravela redonda | 46,000 / 40,000 | 50 / 70 | 7.3 / 6.6 | 28-90 / 28-90 | 390 / 480 | 3 / 8 | 50 / 50 | 38 / 30 | 14 / 11 | more speed, accuracy, reach, sighting, handling; less hold, hull, armour |
| Balinger | Bark | 46,000 / 47,000 | 50 / 90 | 7.3 / 6.1 | 28-90 / 20-60 | 390 / 620 | 3 / 12 | 50 / 30 | 38 / 58 | 14 / 11 | more speed, attack, sighting, berths, handling; less hold, hull, armour, accuracy, reach |
| Brigantin | Barque | 20,000 / 16,000 | 24 / 60 | 6.8 / 5.2 | 14-40 / 8-20 | 300 / 400 | 3 / 5 | 20 / 0 | 30 / 20 | 13 / 9 | more speed, attack, accuracy, reach, sighting, berths, handling; less hold, hull, armour |
| Brigantin | Fusta | 20,000 / 19,000 | 24 / 27 | 6.8 / 6.2 | 14-40 / 19-54 | 300 / 330 | 3 / 6 | 20 / 20 | 30 / 20 | 13 / 9 | more speed, accuracy, reach, sighting; less hold, hull, armour, berths |
| Galeotta | Galea sottile | 48,500 / 44,000 | 50 / 65 | 7 / 6.6 | 38-122 / 38-122 | 390 / 460 | 5 / 8 | 60 / 60 | 20 / 20 | 14 / 11 | more speed, sighting, handling; less hold, hull, armour |
| Galeotta | Marciliana | 48,500 / 38,500 | 50 / 115 | 7 / 5.4 | 38-122 / 19-46 | 390 / 570 | 5 / 12 | 60 / 20 | 20 / 30 | 14 / 10 | more speed, attack, accuracy, sighting, berths, handling; less hold, hull, armour, reach |
| Firkate | Kayık | 19,000 / 15,000 | 23 / 55 | 6.4 / 4.9 | 18-50 / 10-25 | 330 / 440 | 7 / 9 | 20 / 0 | 26 / 16 | 12 / 8 | more speed, attack, accuracy, reach, sighting, berths, handling; less hold, hull, armour |
| Firkate | Fusta | 19,000 / 19,000 | 23 / 27 | 6.4 / 6.2 | 18-50 / 19-54 | 330 / 330 | 7 / 6 | 20 / 20 | 26 / 20 | 12 / 9 | more speed, armour, reach, sighting; less hold, accuracy, berths, handling |
| Lancaran | Ghurab | 37,500 / 34,000 | 60 / 75 | 7.3 / 6.9 | 24-76 / 24-76 | 430 / 500 | 3 / 6 | 30 / 30 | 20 / 20 | 15 / 12 | more speed, sighting, handling; less hold, hull, armour |
| Lancaran | Zabra | 37,500 / 44,000 | 60 / 70 | 7.3 / 6.3 | 24-76 / 32-103 | 430 / 550 | 3 / 14 | 30 / 60 | 20 / 34 | 15 / 11 | more speed, sighting, handling; less hold, hull, armour, attack, accuracy, reach, berths |
| Shaochuan | Niaochuan | 17,500 / 11,000 | 28 / 40 | 6.2 / 6.1 | 14-40 / 6-16 | 360 / 360 | 9 / 10 | 20 / 0 | 30 / 20 | 12 / 10 | more speed, attack, accuracy, reach, sighting, berths, handling; less hold, armour |
| Shaochuan | Fusta | 17,500 / 19,000 | 28 / 27 | 6.2 / 6.2 | 14-40 / 19-54 | 360 / 330 | 9 / 6 | 20 / 20 | 30 / 20 | 12 / 9 | more hold, hull, armour, reach, sighting; less accuracy, berths, handling |
| Bahansen | Sekibune | 44,000 / 40,000 | 50 / 65 | 7 / 6.6 | 32-103 / 32-103 | 390 / 460 | 7 / 10 | 60 / 60 | 22 / 22 | 15 / 12 | more speed, sighting, handling; less hold, hull, armour |
| Bahansen | Zabra | 44,000 / 44,000 | 50 / 70 | 7 / 6.3 | 32-103 / 32-103 | 390 / 550 | 7 / 14 | 60 / 60 | 22 / 34 | 15 / 11 | more speed, accuracy, sighting, handling; less hold, hull, armour, reach |
| Sahuseon | Hyeopseon | 19,000 / 12,000 | 22 / 32 | 6.4 / 6.2 | 15-44 / 7-18 | 330 / 330 | 13 / 14 | 20 / 0 | 30 / 20 | 12 / 10 | more speed, attack, accuracy, reach, sighting, berths, handling; less hold, armour |
| Sahuseon | Fusta | 19,000 / 19,000 | 22 / 27 | 6.4 / 6.2 | 15-44 / 19-54 | 330 / 330 | 13 / 6 | 20 / 20 | 30 / 20 | 12 / 9 | more speed, armour, accuracy, reach, sighting; less hold, berths, handling |
| Galeoncete | Urca | 234,000 / 165,000 | 255 / 400 | 4.5 / 4.2 | 67-164 / 69-161 | 2120 / 2070 | 40 / 36 | 230 / 140 | 88 / 74 | 14 / 14 | more speed, hull, armour, attack, accuracy, reach, berths, handling; less hold |
| Galeoncete | Pinas | 234,000 / 144,500 | 255 / 375 | 4.5 / 4.7 | 67-164 / 68-165 | 2120 / 1800 | 40 / 30 | 230 / 130 | 88 / 72 | 14 / 14 | more hull, armour, attack, accuracy, reach; less hold, speed, berths, handling |
| Great Galley | Race-built Galleon | 361,000 / 289,000 | 330 / 385 | 4.7 / 4.8 | 84-208 / 130-320 | 2450 / 2660 | 38 / 38 | 300 / 250 | 98 / 86 | 14 / 14 | more attack, accuracy, reach; less hold, speed, hull, berths, handling |
| Great Galley | Galeón | 361,000 / 302,500 | 330 / 420 | 4.7 / 4.4 | 84-208 / 150-368 | 2450 / 3220 | 38 / 46 | 300 / 280 | 98 / 82 | 14 / 14 | more speed, attack, accuracy, reach, handling; less hold, hull, armour, berths |
| Roberge | Galère | 223,000 / 178,500 | 255 / 300 | 4.8 / 5 | 58-143 / 90-220 | 1840 / 2000 | 34 / 34 | 210 / 180 | 84 / 72 | 15 / 15 | more attack, accuracy, reach; less hold, speed, hull, berths, handling |
| Roberge | Navire marchand | 223,000 / 157,500 | 255 / 400 | 4.8 / 4.6 | 58-143 / 60-140 | 1840 / 1800 | 34 / 30 | 210 / 130 | 84 / 70 | 15 / 15 | more speed, hull, armour, attack, accuracy, reach, berths, handling; less hold |
| Göke | Kalyon | 594,000 / 475,000 | 485 / 570 | 4.1 / 4.2 | 162-390 / 250-600 | 4050 / 4400 | 52 / 52 | 470 / 390 | 90 / 78 | 14 / 14 | more attack, accuracy, reach; less hold, speed, hull, berths, handling |
| Göke | Nau da Carreira | 594,000 / 400,000 | 485 / 900 | 4.1 / 4.2 | 162-390 / 120-300 | 4050 / 3400 | 52 / 38 | 470 / 160 | 90 / 65 | 14 / 13 | more hull, armour, attack, accuracy, reach, sighting, berths; less hold, speed, handling |
| Wugongchuan | Cangshan | 45,000 / 36,000 | 70 / 80 | 6.1 / 6.3 | 18-58 / 28-90 | 530 / 580 | 14 / 14 | 50 / 40 | 42 / 30 | 11 / 11 | more attack, accuracy, reach; less hold, speed, hull, berths, handling |
| Wugongchuan | Shachuan | 45,000 / 31,500 | 70 / 150 | 6.1 / 5.1 | 18-58 / 14-34 | 530 / 720 | 14 / 18 | 50 / 20 | 42 / 40 | 11 / 10 | more speed, attack, accuracy, reach, sighting, berths, handling; less hold, hull, armour |
| Galé | Pinas | 187,000 / 144,500 | 210 / 375 | 4.8 / 4.7 | 108-330 / 68-165 | 1800 / 1800 | 30 / 30 | 120 / 130 | 58 / 72 | 14 / 14 | more speed, berths; less hold, attack, accuracy, reach, handling |
| Galera | Urca | 205,500 / 165,000 | 210 / 400 | 4.6 / 4.2 | 124-379 / 69-161 | 2070 / 2070 | 36 / 36 | 140 / 140 | 62 / 74 | 14 / 14 | more speed, berths, handling; less hold, accuracy, reach |
| Galera | Pinas | 205,500 / 144,500 | 210 / 375 | 4.6 / 4.7 | 124-379 / 68-165 | 2070 / 1800 | 36 / 30 | 140 / 130 | 62 / 72 | 14 / 14 | more hull, armour, attack, berths; less hold, speed, accuracy, reach, handling |
| Galea capitana | Galeão | 333,000 / 275,000 | 265 / 420 | 4.6 / 4.6 | 211-648 / 130-320 | 2390 / 2800 | 36 / 40 | 190 / 240 | 54 / 78 | 14 / 14 | more berths, handling; less hold, hull, armour, attack, accuracy, reach |
| Galea capitana | Caracca genovese | 333,000 / 264,000 | 265 / 540 | 4.6 / 4.4 | 211-648 / 108-270 | 2390 / 2280 | 36 / 32 | 190 / 130 | 54 / 55 | 14 / 13 | more speed, hull, armour, attack, accuracy, sighting, berths, handling; less hold, reach |
| Kalyata | Şebek (xebec) | 44,000 / 40,000 | 47 / 65 | 6.5 / 6.5 | 42-169 / 35-112 | 480 / 530 | 8 / 12 | 40 / 60 | 12 / 26 | 11 / 11 | more berths; less hold, hull, armour, attack, accuracy, reach |
| Kalyata | Zabra | 44,000 / 44,000 | 47 / 70 | 6.5 / 6.3 | 42-169 / 32-103 | 480 / 550 | 8 / 14 | 40 / 60 | 12 / 34 | 11 / 11 | more speed, berths, handling; less hold, hull, armour, attack, accuracy, reach |
| Parau | Dhow | 16,500 / 13,000 | 23 / 65 | 6.4 / 5.2 | 14-51 / 7-17 | 330 / 420 | 0 / 3 | 10 / 0 | 6 / 10 | 10 / 9 | more speed, attack, accuracy, sighting, berths, handling; less hold, hull, armour, reach |
| Parau | Fusta | 16,500 / 19,000 | 23 / 27 | 6.4 / 6.2 | 14-51 / 19-54 | 330 / 330 | 0 / 6 | 10 / 20 | 6 / 20 | 10 / 9 | more speed, sighting; less hold, armour, attack, accuracy, reach, berths, handling |
| Ghali | Baghlah | 159,000 / 127,500 | 225 / 430 | 5 / 4.6 | 92-280 / 51-119 | 1890 / 1890 | 28 / 28 | 70 / 70 | 48 / 60 | 15 / 15 | more speed, berths, handling; less hold, accuracy, reach |
| Ghali | Pinas | 159,000 / 144,500 | 225 / 375 | 5 / 4.7 | 92-280 / 68-165 | 1890 / 1800 | 28 / 30 | 70 / 130 | 48 / 72 | 15 / 14 | more speed, hull, sighting, berths, handling; less hold, armour, attack, accuracy, reach |
| Mengchong | Junk (Fuzhou trader) | 168,500 / 135,000 | 240 / 460 | 4.6 / 4.2 | 108-330 / 60-140 | 2160 / 2160 | 36 / 36 | 110 / 110 | 58 / 70 | 14 / 14 | more speed, berths, handling; less hold, accuracy, reach |
| Mengchong | Pinas | 168,500 / 144,500 | 240 / 375 | 4.6 / 4.7 | 108-330 / 68-165 | 2160 / 1800 | 36 / 30 | 110 / 130 | 58 / 72 | 14 / 14 | more hull, armour, berths; less hold, speed, attack, accuracy, reach, handling |
| Mekurabune | Shuinsen | 187,000 / 150,000 | 190 / 360 | 4.8 / 4.4 | 124-379 / 69-161 | 1710 / 1710 | 32 / 32 | 130 / 130 | 50 / 62 | 15 / 15 | more speed, berths, handling; less hold, accuracy, reach |
| Mekurabune | Pinas | 187,000 / 144,500 | 190 / 375 | 4.8 / 4.7 | 124-379 / 68-165 | 1710 / 1800 | 32 / 30 | 130 / 130 | 50 / 72 | 15 / 14 | more speed, armour, accuracy, sighting, berths, handling; less hold, hull, reach |
| Geomseon | Byeongseon | 44,000 / 40,000 | 44 / 65 | 6.4 / 6.4 | 37-148 / 31-99 | 480 / 530 | 14 / 18 | 40 / 60 | 16 / 30 | 11 / 11 | more berths; less hold, hull, armour, attack, accuracy, reach |
| Geomseon | Sangseon | 44,000 / 35,000 | 44 / 115 | 6.4 / 5.2 | 37-148 / 15-37 | 480 / 660 | 14 / 22 | 40 / 20 | 16 / 40 | 11 / 10 | more speed, attack, accuracy, sighting, berths, handling; less hold, hull, armour, reach |
| Daemaengseon | Panokseon | 302,500 / 275,000 | 265 / 380 | 4.5 / 4.5 | 172-528 / 143-352 | 2770 / 3080 | 46 / 50 | 180 / 260 | 64 / 78 | 14 / 14 | more berths; less hold, hull, armour, attack, accuracy, reach |
| Daemaengseon | Galeón | 302,500 / 302,500 | 265 / 420 | 4.5 / 4.4 | 172-528 / 150-368 | 2770 / 3220 | 46 / 46 | 180 / 280 | 64 / 82 | 14 / 14 | more speed, berths, handling; less hold, hull, attack, reach |
| Nau capitânia | Nau da Carreira | 675,000 / 400,000 | 420 / 900 | 4 / 4.2 | 220-528 / 120-300 | 5000 / 3400 | 60 / 38 | 370 / 160 | 84 / 65 | 14 / 13 | more hull, armour, attack, accuracy, reach, sighting, berths; less hold, speed, handling |
| Nau capitânia | Grand navire | 675,000 / 499,000 | 420 / 600 | 4 / 4.5 | 220-528 / 200-480 | 5000 / 4000 | 60 / 48 | 370 / 360 | 84 / 82 | 14 / 15 | more hull, armour, attack, reach, berths; less hold, speed, accuracy, sighting, handling |
| Kraweel | Galeão | 327,000 / 275,000 | 370 / 420 | 4.1 / 4.6 | 107-264 / 130-320 | 3150 / 2800 | 48 / 40 | 200 / 240 | 80 / 78 | 14 / 14 | more hull, armour, reach; less hold, speed, attack, berths, handling |
| Kraweel | Retourschip | 327,000 / 204,000 | 370 / 750 | 4.1 / 4.3 | 107-264 / 60-150 | 3150 / 2160 | 48 / 28 | 200 / 80 | 80 / 65 | 14 / 13 | more hull, armour, attack, accuracy, reach, sighting, berths; less hold, speed, handling |
| Nef | Galion | 404,000 / 289,000 | 295 / 420 | 4.4 / 4.8 | 143-352 / 130-320 | 3500 / 2800 | 52 / 40 | 280 / 250 | 80 / 78 | 15 / 15 | more hull, armour, attack, reach, berths; less hold, speed, handling |
| Nef | Galeón | 404,000 / 302,500 | 295 / 420 | 4.4 / 4.4 | 143-352 / 150-368 | 3500 / 3220 | 52 / 46 | 280 / 280 | 80 / 82 | 15 / 14 | more hull, armour, accuracy, sighting; less hold, reach, berths |
| Barza | Galeazza | 741,500 / 522,500 | 380 / 540 | 4 / 4.3 | 297-713 / 270-648 | 4750 / 3800 | 60 / 48 | 430 / 390 | 74 / 72 | 14 / 14 | more hull, armour, attack, reach, berths; less hold, speed, handling |
| Barza | Nau da Carreira | 741,500 / 400,000 | 380 / 900 | 4 / 4.2 | 297-713 / 120-300 | 4750 / 3400 | 60 / 38 | 430 / 160 | 74 / 65 | 14 / 13 | more hull, armour, attack, accuracy, reach, sighting, berths, handling; less hold, speed |
| Louchuan | Dachuan (great junk) | 604,500 / 360,000 | 485 / 1035 | 3.8 / 4 | 220-528 / 120-300 | 6000 / 4080 | 66 / 44 | 340 / 140 | 84 / 65 | 14 / 13 | more hull, armour, attack, accuracy, reach, sighting, berths; less hold, speed, handling |
| Louchuan | Grand navire | 604,500 / 499,000 | 485 / 600 | 3.8 / 4.5 | 220-528 / 200-480 | 6000 / 4000 | 66 / 48 | 340 / 360 | 84 / 82 | 14 / 15 | more hull, armour, reach, berths; less hold, speed, attack, accuracy, sighting, handling |
| Tekkōsen | Ō-atakebune | 669,500 / 475,000 | 380 / 540 | 4 / 4.3 | 253-607 / 230-552 | 4750 / 3800 | 62 / 50 | 410 / 370 | 76 / 74 | 15 / 15 | more hull, armour, attack, reach, berths; less hold, speed, handling |
| Tekkōsen | Nau da Carreira | 669,500 / 400,000 | 380 / 900 | 4 / 4.2 | 253-607 / 120-300 | 4750 / 3400 | 62 / 38 | 410 / 160 | 76 / 65 | 15 / 13 | more hull, armour, attack, accuracy, reach, sighting, berths; less hold, speed, handling |
| Friedeschiff | Fluit | 153,000 / 127,500 | 280 / 500 | 4.7 / 4.3 | 52-135 / 45-105 | 1910 / 1620 | 36 / 26 | 100 / 90 | 74 / 70 | 20 / 14 | more speed, hull, armour, attack, accuracy, reach, sighting, berths, handling; less hold |
| Wafter | Bark | 56,500 / 47,000 | 75 / 90 | 6.1 / 6.1 | 20-60 / 20-60 | 770 / 620 | 18 / 12 | 40 / 30 | 72 / 58 | 17 / 11 | more hull, armour, attack, accuracy, reach, sighting; less hold |
| Wafter | Caravela redonda | 56,500 / 40,000 | 75 / 70 | 6.1 / 6.6 | 20-60 / 28-90 | 770 / 480 | 18 / 8 | 40 / 50 | 72 / 30 | 17 / 11 | more hold, hull, armour, accuracy, reach, sighting; less speed, attack, berths, handling |
| Almiranta | Galeón | 343,000 / 302,500 | 385 / 420 | 4.3 / 4.4 | 115-299 / 150-368 | 3880 / 3220 | 56 / 46 | 240 / 280 | 88 / 82 | 20 / 14 | more hull, armour, accuracy, reach, sighting, handling; less hold, speed, attack, berths |
| Jungmaengseon | Jounseon | 180,000 / 150,000 | 200 / 360 | 4.7 / 4.3 | 77-198 / 66-154 | 2340 / 1980 | 50 / 40 | 140 / 130 | 74 / 70 | 20 / 14 | more speed, hull, armour, attack, accuracy, reach, sighting, berths, handling; less hold |
| Caravelão | Caravela redonda | 35,000 / 40,000 | 130 / 70 | 5.4 / 6.6 | 14-34 / 28-90 | 600 / 480 | 12 / 8 | 20 / 50 | 40 / 30 | 10 / 11 | more hold, hull, armour, reach; less speed, attack, accuracy, sighting, berths, handling |
| Caravelão | Carabela de Indias | 35,000 / 38,500 | 130 / 130 | 5.4 / 5.2 | 14-34 / 16-39 | 600 / 690 | 12 / 18 | 20 / 20 | 40 / 44 | 10 / 10 | more speed, handling; less hull, armour, reach, berths |
| Chalupa | Patache | 16,500 / 16,500 | 60 / 45 | 4.8 / 5.6 | 9-23 / 12-34 | 460 / 440 | 11 / 12 | 0 / 10 | 24 / 29 | 8 / 10 | more hold, hull; less speed, armour, attack, accuracy, reach, sighting, berths, handling |
| Chalupa | Crayer | 16,500 / 16,000 | 60 / 55 | 4.8 / 5.2 | 9-23 / 8-20 | 460 / 380 | 11 / 3 | 0 / 0 | 24 / 28 | 8 / 8 | more hold, hull, armour, berths; less speed, reach, handling |
| Tartana | Fusta | 16,500 / 19,000 | 55 / 27 | 5 / 6.2 | 11-27 / 19-54 | 380 / 330 | 5 / 6 | 0 / 20 | 10 / 20 | 8 / 9 | more hold, hull; less speed, armour, attack, accuracy, reach, sighting, berths, handling |
| Tartana | Crayer | 16,500 / 16,000 | 55 / 55 | 5 / 5.2 | 11-27 / 8-20 | 380 / 380 | 5 / 3 | 0 / 0 | 10 / 28 | 8 / 8 | more armour, berths, handling; less speed, reach |
| Boum | Ghurab | 30,000 / 34,000 | 140 / 75 | 5.6 / 6.9 | 12-29 / 24-76 | 630 / 500 | 10 / 6 | 10 / 30 | 30 / 20 | 11 / 12 | more hold, hull, armour, reach; less speed, attack, accuracy, sighting, berths, handling |
| Boum | Carabela de Indias | 30,000 / 38,500 | 140 / 130 | 5.6 / 5.2 | 12-29 / 16-39 | 630 / 690 | 10 / 18 | 10 / 20 | 30 / 44 | 11 / 10 | more hold, speed, sighting, handling; less hull, armour, attack, accuracy, reach, berths |
| Şayka | Şebek (xebec) | 35,000 / 40,000 | 125 / 65 | 5.3 / 6.5 | 18-42 / 35-112 | 660 / 530 | 16 / 12 | 20 / 60 | 36 / 26 | 10 / 11 | more hold, hull, armour, reach; less speed, attack, accuracy, sighting, berths, handling |
| Şayka | Carabela de Indias | 35,000 / 38,500 | 125 / 130 | 5.3 / 5.2 | 18-42 / 16-39 | 660 / 690 | 16 / 18 | 20 / 20 | 36 / 44 | 10 / 10 | more speed, berths, handling; less hold, hull, armour, reach |
| Bezaisen | Sekibune | 35,000 / 40,000 | 115 / 65 | 5.4 / 6.6 | 16-39 / 32-103 | 570 / 460 | 14 / 10 | 20 / 60 | 32 / 22 | 11 / 12 | more hold, hull, armour, reach; less speed, attack, accuracy, sighting, berths, handling |
| Bezaisen | Carabela de Indias | 35,000 / 38,500 | 115 / 130 | 5.4 / 5.2 | 16-39 / 16-39 | 570 / 690 | 14 / 18 | 20 / 20 | 32 / 44 | 11 / 10 | more speed, accuracy, sighting, handling; less hold, hull, armour, reach |
| Nao | Galeón | 317,000 / 302,500 | 510 / 420 | 4.1 / 4.4 | 115-345 / 150-368 | 2900 / 3220 | 43 / 46 | 220 / 280 | 75 / 82 | 13 / 14 | more hold; less speed, hull, armour, attack, accuracy, reach, sighting, berths, handling |
| Nao | Retourschip | 317,000 / 204,000 | 510 / 750 | 4.1 / 4.3 | 115-345 / 60-150 | 2900 / 2160 | 43 / 28 | 220 / 80 | 75 / 65 | 13 / 13 | more hull, armour, attack, accuracy, reach, berths; less hold, speed, handling |
| Kogge | Haringbuis | 35,500 / 30,000 | 140 / 160 | 5.2 / 5.3 | 13-38 / 10-26 | 570 / 540 | 13 / 8 | 30 / 20 | 46 / 40 | 10 / 10 | more hull, armour, attack, accuracy, reach, berths; less hold, speed |
| Kogge | Caravela redonda | 35,500 / 40,000 | 140 / 70 | 5.2 / 6.6 | 13-38 / 28-90 | 570 / 480 | 13 / 8 | 30 / 50 | 46 / 30 | 10 / 11 | more hold, hull, armour, reach; less speed, attack, accuracy, sighting, berths, handling |
| Byeongjoseon | Jounseon | 180,000 / 150,000 | 305 / 360 | 4.2 / 4.3 | 82-231 / 66-154 | 2080 / 1980 | 45 / 40 | 220 / 130 | 76 / 70 | 14 / 14 | more hull, armour, attack, accuracy, reach, berths; less hold, speed |
| Byeongjoseon | Urca | 180,000 / 165,000 | 305 / 400 | 4.2 / 4.2 | 82-231 / 69-161 | 2080 / 2070 | 45 / 36 | 220 / 140 | 76 / 74 | 14 / 14 | more hull, armour, attack, accuracy, reach, berths, handling; less hold |
| Kenminsen | Atakebune | 288,000 / 275,000 | 460 / 380 | 4.3 / 4.6 | 115-345 / 150-368 | 2390 / 2660 | 39 / 42 | 210 / 260 | 63 / 70 | 14 / 15 | more hold; less speed, hull, armour, attack, accuracy, reach, sighting, berths, handling |
| Kenminsen | Retourschip | 288,000 / 204,000 | 460 / 750 | 4.3 / 4.3 | 115-345 / 60-150 | 2390 / 2160 | 39 / 28 | 210 / 80 | 63 / 65 | 14 / 13 | more hull, armour, attack, accuracy, sighting, berths, handling; less hold, reach |
| Kotia | Baghlah | 153,000 / 127,500 | 365 / 430 | 4.5 / 4.6 | 64-178 / 51-119 | 1980 / 1890 | 33 / 28 | 120 / 70 | 66 / 60 | 15 / 15 | more hull, armour, attack, accuracy, reach, berths; less hold, speed |
| Kotia | Urca | 153,000 / 165,000 | 365 / 400 | 4.5 / 4.2 | 64-178 / 69-161 | 1980 / 2070 | 33 / 36 | 120 / 140 | 66 / 74 | 15 / 14 | more speed, sighting, berths, handling; less hold, hull, armour, attack, accuracy, reach |
| Hoy | Crayer | 18,000 / 16,000 | 70 / 55 | 4.6 / 5.2 | 8-20 / 8-20 | 420 / 380 | 0 / 3 | 0 / 0 | 28 / 28 | 7 / 8 | more hold, hull; less speed, armour, sighting, handling |
| Hoy | Pinnace | 18,000 / 12,500 | 70 / 32 | 4.6 / 6.7 | 8-20 / 6-16 | 420 / 280 | 0 / 2 | 0 / 0 | 28 / 28 | 7 / 10 | more hold, hull, berths; less speed, armour, sighting, handling |
| Holk | Fluit | 146,500 / 127,500 | 650 / 500 | 3.8 / 4.3 | 45-105 / 45-105 | 1780 / 1620 | 23 / 26 | 40 / 90 | 70 / 70 | 13 / 14 | more hold, hull; less speed, armour, attack, sighting, handling |
| Holk | Pinas | 146,500 / 144,500 | 650 / 375 | 3.8 / 4.7 | 45-105 / 68-165 | 1780 / 1800 | 23 / 30 | 40 / 130 | 70 / 72 | 13 / 14 | more hold; less speed, hull, armour, attack, accuracy, reach, sighting, berths, handling |
| Cocca | Galea grossa | 190,000 / 165,000 | 470 / 360 | 3.9 / 4.4 | 81-189 / 81-189 | 1880 / 1710 | 27 / 30 | 70 / 140 | 60 / 60 | 13 / 14 | more hold, hull; less speed, armour, attack, sighting, handling |
| Cocca | Urca | 190,000 / 165,000 | 470 / 400 | 3.9 / 4.2 | 81-189 / 69-161 | 1880 / 2070 | 27 / 36 | 70 / 140 | 60 / 74 | 13 / 14 | more hold, accuracy, berths, handling; less speed, hull, armour, attack, reach, sighting |
| Caochuan | Junk (Fuzhou trader) | 155,000 / 135,000 | 600 / 460 | 3.7 / 4.2 | 60-140 / 60-140 | 2380 / 2160 | 33 / 36 | 50 / 110 | 70 / 70 | 13 / 14 | more hold, hull; less speed, armour, attack, sighting, handling |
| Caochuan | Urca | 155,000 / 165,000 | 600 / 400 | 3.7 / 4.2 | 60-140 / 69-161 | 2380 / 2070 | 33 / 36 | 50 / 140 | 70 / 74 | 13 / 14 | more hold, hull; less speed, armour, attack, accuracy, reach, sighting, berths, handling |
| Taforeia | Galeão | 276,000 / 275,000 | 780 / 420 | 3.9 / 4.6 | 80-200 / 130-320 | 2640 / 2800 | 29 / 40 | 60 / 240 | 65 / 78 | 12 / 14 | more hold; less speed, hull, armour, attack, accuracy, reach, sighting, berths, handling |
| Taforeia | Retourschip | 276,000 / 204,000 | 780 / 750 | 3.9 / 4.3 | 80-200 / 60-150 | 2640 / 2160 | 29 / 28 | 60 / 80 | 65 / 65 | 12 / 13 | more hold, hull, armour, berths; less speed, attack, sighting, handling |
| Hourque | Galion | 290,000 / 289,000 | 780 / 420 | 4 / 4.8 | 80-200 / 130-320 | 2640 / 2800 | 29 / 40 | 60 / 250 | 65 / 78 | 13 / 15 | more hold; less speed, hull, armour, attack, accuracy, reach, sighting, berths, handling |
| Hourque | Retourschip | 290,000 / 204,000 | 780 / 750 | 4 / 4.3 | 80-200 / 60-150 | 2640 / 2160 | 29 / 28 | 60 / 80 | 65 / 65 | 13 / 13 | more hold, hull, armour, accuracy, berths; less speed, attack, handling |
| Jong | Hajji Jahaz | 397,500 / 340,000 | 1265 / 970 | 3.8 / 4.4 | 102-255 / 102-255 | 3930 / 3570 | 33 / 36 | 50 / 100 | 55 / 55 | 13 / 14 | more hold, hull; less speed, armour, attack, sighting, handling |
| Jong | Galeón de Manila | 397,500 / 440,000 | 1265 / 900 | 3.8 / 4 | 102-255 / 138-345 | 3930 / 3910 | 33 / 44 | 50 / 180 | 55 / 69 | 13 / 13 | more hold, hull; less speed, armour, attack, accuracy, reach, berths |
| Nave grossa | Carraca grande | 980,000 / 768,000 | 1755 / 1500 | 3.4 / 3.9 | 270-675 / 200-500 | 5220 / 5000 | 39 / 42 | 130 / 220 | 55 / 65 | 12 / 13 | more hold, hull, accuracy, berths; less speed, armour, attack, reach, sighting |

102 pairs; in none does one hull outclass the other (the generator checks every pair of a size, 54 new against 103 older and each other).

The hold and the knots above are the design's. In the game they are three times that (`hold_scale` 3, `speed_scale` 3): the Nave grossa carries 5,265 tons at 10.2 knots, the Balinger makes 21.9 knots. The migration multiplies by the two knobs at apply, as the world guard does when it compares.

No new hull outclasses another. The generator refuses to run if a Wave E hull is at least as good as another hull of its size on every rated figure (hold, speed, hull, armour, attack, accuracy, reach, sighting, handling, wave resistance, berths, deck, cabins, every rack, and fewer hands needed and less draft) for the same labour or less; or if it is outclassed that way by a hull that costs no more. It checks every pair of a size: the 54 against the 103 older hulls and against each other. The table above shows each new hull beside two older ones.

## The balance, fought by the real engine

`scripts/ops/harness/more-ships/duels.mjs` builds each hull from `data/ships.generated.json` as one side of `public.fight_sides` on the cached world and fights it over 200 seeds. A duel uses full crews. A raid uses `voyage.raider_hulls`, as the game builds one (strength 12.7 a xebec), against the crew a hull must have.

One worked by hand, to show the engine's own arithmetic. A Great Galley (attack 300, accuracy 74, reach 98, hull 2,450, armour 38, crew 208, tier 4) is set upon by a Daemaengseon (attack 180, accuracy 60, reach 64, hull 2,770, armour 46, crew 528, tier 4).

- LONG rounds: 98 is more than 64, so only the galley fires, three times, at 74 % x 0.6 = 44.4 %. MEDIUM, twice, 59.2 %. CLOSE, 74 %. Expected hits 1.33 + 1.18 + 0.74 = 3.25.
- A hit is 300 x 0.7 = 210 raw, less armour 46 x 0.5 % = 23 %: 162. Expected 527 of hull.
- The Daemaengseon closes, so she breaks off at 15 % of 2,770 = 416. 527 is over it: she breaks off in most fights. Measured: the galley holds 76 % of 200 fights, driving her off.
- Where she does not break off it is boarded. The galley: 208 x 0.15 + 12 = 43.2. The Daemaengseon: 528 x 0.15 + 12 = 91.2, times her hull left (about 0.87) = 79. Ratio 0.55: the galley is plundered. That is the other 24 %.
- Turn it round. The galley closes on the Daemaengseon. She hits as before, but the one set upon never breaks off. The Daemaengseon fires only the MEDIUM and CLOSE rounds: 2 x 48 % + 60 % = 1.56 hits of 180 x 0.7 x (1 - 19 %) = 102, which is 159 against a break at 15 % of 2,450 = 368. No break. Boarding: 91.2 x 0.81 = 74 against 43.2 x 0.94 = 40: ratio 1.8, over 1.2. The galley is thrown back every time. Measured: the Daemaengseon holds 100 %.

So a gunship stops a boarder and cannot take one. The three heavy jobs against each other and against the older heavy hulls (each cell: of 200 fights, how many the hull at the left HELD when the hull at the top closed on her):


Heavy (size 4):

| set upon \ closes | Great Galley | Daemaengseon | Nef | Almiranta | Nao | Galeón | Race-built Galleon |
|---|---|---|---|---|---|---|---|
| Great Galley | - | 76 | 29 | 16 | 76 | 58 | 77 |
| Daemaengseon | 100 | - | 66 | 99 | 99 | 60 | 97 |
| Nef | 100 | 62 | - | 4 | 59 | 5 | 23 |
| Almiranta | 90 | 50 | 27 | - | 50 | 38 | 63 |
| Nao | 78 | 12 | 0 | 1 | - | 0 | 2 |
| Galeón | 99 | 52 | 14 | 8 | 53 | - | 17 |
| Race-built Galleon | 61 | 48 | 11 | 0 | 45 | 31 | - |

Medium (size 3):

| set upon \ closes | Galeoncete | Galera | Friedeschiff | Kotia | Galère | Pinas |
|---|---|---|---|---|---|---|
| Galeoncete | - | 67 | 87 | 56 | 55 | 77 |
| Galera | 100 | - | 100 | 100 | 98 | 100 |
| Friedeschiff | 15 | 15 | - | 14 | 14 | 23 |
| Kotia | 2 | 6 | 37 | - | 0 | 2 |
| Galère | 33 | 43 | 100 | 87 | - | 93 |
| Pinas | 0 | 11 | 8 | 8 | 8 | - |

Light (size 2):

| set upon \ closes | Balinger | Wugongchuan | Kalyata | Wafter | Kogge | Şebek (xebec) | Caravela redonda |
|---|---|---|---|---|---|---|---|
| Balinger | - | 63 | 47 | 29 | 100 | 39 | 47 |
| Wugongchuan | 45 | - | 35 | 0 | 83 | 26 | 35 |
| Kalyata | 96 | 100 | - | 100 | 100 | 63 | 97 |
| Wafter | 60 | 39 | 53 | - | 100 | 39 | 53 |
| Kogge | 10 | 1 | 2 | 0 | - | 1 | 2 |
| Şebek (xebec) | 36 | 98 | 51 | 97 | 100 | - | 38 |
| Caravela redonda | 25 | 66 | 33 | 41 | 100 | 23 | - |

Capital (size 5):

| set upon \ closes | Göke | Nau capitânia | Louchuan | Galeazza | Kalyon | Grand navire |
|---|---|---|---|---|---|---|
| Göke | - | 41 | 21 | 73 | 68 | 57 |
| Nau capitânia | 52 | - | 2 | 48 | 30 | 34 |
| Louchuan | 60 | 6 | - | 28 | 17 | 24 |
| Galeazza | 86 | 12 | 11 | - | 3 | 58 |
| Kalyon | 81 | 3 | 1 | 56 | - | 36 |
| Grand navire | 16 | 2 | 2 | 50 | 32 | - |

Read across a row for how a hull defends, down a column for how she attacks.

- **Line beats gunship.** A Nef set upon by a Great Galley holds 100 %; a Great Galley set upon by a Nef holds 29 %. The armour shrugs off the long rounds and the bigger crew takes the deck.
- **Gunship stops boarder.** The Great Galley holds 76 % against the Daemaengseon, and 77 % against the Race-built Galleon. She takes nobody: every hull holds 61 to 100 % against her.
- **Boarder holds against everything, line ships too.** The Daemaengseon holds 66 % against the Nef and 60 to 100 % against the rest. As the one who closes she is ordinary (the warships hold 48 to 76 %), because she breaks off under long guns.
- **The fight favours the one who closes** (the one set upon needs 1.2 times the power to hold). That is the engine's, and it is the same for the older hulls: a Galeón holds 17 % against a Race-built Galleon.
- **An armed trader is not a warship.** The Nao holds almost never against a warship. Her job is raids: see below.
- At capital size the line ships are the ones nobody holds against: when a Nau capitânia or a Louchuan closes, the galleass, the kalyon and the Grand navire hold 1 to 12 % and the Göke 41 % and 21 %. A line ship does not lose the 15 % of hull that makes the one who closes break off. The Göke holds 57 to 73 % against the older capitals.

Raids, as the game builds them, against the crew a hull must have:

- **A cargo carrier alone is lost.** A Hoy is plundered every time by one xebec, as a Barca is (docs/COMBAT_LOG.md 2.5). A Holk holds one xebec and is ransomed or plundered by two; a Fluit does a little better. The carrier's price is her escort.
- **An armed trader defends herself.** Byeongjoseon: holds 95 % against two xebecs, 72 % against four, 40 % against six. The Jounseon, the plain trader of her line and size: 80, 22, 6. Nao against Urca: 100, 59, 26 against 76, 24, 6. Kotia against Baghlah at two xebecs: 62 against 20. The small Kogge is ransomed by one xebec 46 % of the time where a Haringbuis is plundered 94 %; she is a small ship and it shows.
- **An escort protects cargo better than a warship of her size.** Taforeia with an Almiranta: holds 100 % against four xebecs and 74 % against six; with a Galeón 100 and 67. Holk with a Friedeschiff against six: 26 % held, with a Pinas 10 %. Caochuan with a Jungmaengseon: 67 % against four, 37 % against six. A Hoy with a Wafter holds 83 % against one xebec, and is ransomed the rest.
- **The very large carrier**: a Nave grossa holds four xebecs by her own crew (270 hands) and is ransomed by six. A Jong holds two and is plundered by four.

| fleet set upon by a raid | 1 xebec | 2 xebecs | 4 xebecs | 6 xebecs |
|---|---|---|---|---|
| Hoy | held 0, paid 0, lost 100 | held 0, paid 0, lost 100 | held 0, paid 0, lost 100 | held 0, paid 0, lost 100 |
| Hoy + Wafter | held 83, paid 17, lost 0 | held 15, paid 0, lost 85 | held 15, paid 0, lost 85 | held 15, paid 0, lost 85 |
| Hoy + Caravela redonda | held 92, paid 8, lost 0 | held 1, paid 3, lost 97 | held 0, paid 0, lost 100 | held 0, paid 0, lost 100 |
| Kogge | held 1, paid 46, lost 54 | held 0, paid 0, lost 100 | held 0, paid 0, lost 100 | held 0, paid 0, lost 100 |
| Haringbuis | held 0, paid 7, lost 94 | held 0, paid 0, lost 100 | held 0, paid 0, lost 100 | held 0, paid 0, lost 100 |
| Holk | held 100, paid 0, lost 0 | held 4, paid 64, lost 32 | held 4, paid 0, lost 96 | held 4, paid 0, lost 96 |
| Fluit | held 100, paid 0, lost 0 | held 48, paid 42, lost 10 | held 6, paid 0, lost 94 | held 6, paid 0, lost 94 |
| Kotia | held 100, paid 0, lost 0 | held 62, paid 38, lost 0 | held 16, paid 0, lost 84 | held 8, paid 0, lost 93 |
| Baghlah | held 100, paid 0, lost 0 | held 20, paid 78, lost 3 | held 8, paid 0, lost 93 | held 8, paid 0, lost 93 |
| Byeongjoseon | held 100, paid 0, lost 0 | held 95, paid 5, lost 0 | held 72, paid 0, lost 28 | held 40, paid 0, lost 61 |
| Jounseon | held 100, paid 0, lost 0 | held 80, paid 21, lost 0 | held 22, paid 0, lost 79 | held 6, paid 0, lost 94 |
| Holk + Friedeschiff | held 100, paid 0, lost 0 | held 100, paid 0, lost 0 | held 44, paid 56, lost 0 | held 26, paid 0, lost 75 |
| Holk + Pinas | held 100, paid 0, lost 0 | held 100, paid 0, lost 0 | held 39, paid 62, lost 0 | held 10, paid 0, lost 91 |
| Caochuan + Jungmaengseon | held 100, paid 0, lost 0 | held 100, paid 0, lost 0 | held 67, paid 33, lost 0 | held 37, paid 0, lost 63 |
| Nao | held 100, paid 0, lost 0 | held 100, paid 0, lost 0 | held 59, paid 17, lost 25 | held 26, paid 0, lost 75 |
| Urca | held 100, paid 0, lost 0 | held 76, paid 24, lost 0 | held 24, paid 0, lost 76 | held 6, paid 0, lost 94 |
| Taforeia | held 100, paid 0, lost 0 | held 14, paid 87, lost 0 | held 2, paid 0, lost 99 | held 2, paid 0, lost 99 |
| Taforeia + Almiranta | held 100, paid 0, lost 0 | held 100, paid 0, lost 0 | held 100, paid 0, lost 0 | held 74, paid 26, lost 0 |
| Taforeia + Galeón | held 100, paid 0, lost 0 | held 100, paid 0, lost 0 | held 100, paid 0, lost 0 | held 67, paid 34, lost 0 |
| Jong | held 100, paid 0, lost 0 | held 100, paid 0, lost 0 | held 4, paid 1, lost 95 | held 4, paid 0, lost 96 |
| Nave grossa | held 100, paid 0, lost 0 | held 100, paid 0, lost 0 | held 98, paid 3, lost 0 | held 2, paid 99, lost 0 |

Each new hull against two older ones, both ways round (200 seeds each; "held" is from the side set upon; the first cell is the new hull set upon by the older one, the second the older hull set upon by the new one):

| new hull | older hull | the new hull set upon | the older hull set upon |
|---|---|---|---|
| Bergantim (raider) | Fusta | held 8 % (slipped 6, drove off 2), paid 92 %, lost 0 %; hull lost 4 % / theirs 5 % | held 55 % (slipped 0, drove off 1), paid 45 %, lost 0 %; hull lost 6 % / theirs 4 % |
| Bergantim (raider) | Crayer | held 100 % (slipped 8, drove off 0), paid 0 %, lost 0 %; hull lost 0 % / theirs 5 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 5 % / theirs 0 % |
| Schnigge (raider) | Fusta | held 8 % (slipped 6, drove off 2), paid 33 %, lost 60 %; hull lost 4 % / theirs 5 % | held 100 % (slipped 0, drove off 3), paid 0 %, lost 0 %; hull lost 6 % / theirs 5 % |
| Schnigge (raider) | Crayer | held 100 % (slipped 8, drove off 0), paid 0 %, lost 0 %; hull lost 0 % / theirs 5 % | held 0 % (slipped 0, drove off 0), paid 95 %, lost 5 %; hull lost 5 % / theirs 0 % |
| Balinger (raider) | Caravela redonda | held 47 % (slipped 6, drove off 41), paid 54 %, lost 0 %; hull lost 8 % / theirs 12 % | held 25 % (slipped 0, drove off 25), paid 74 %, lost 2 %; hull lost 14 % / theirs 9 % |
| Balinger (raider) | Carabela de Indias | held 100 % (slipped 8, drove off 1), paid 0 %, lost 0 %; hull lost 4 % / theirs 5 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 6 % / theirs 4 % |
| Brigantin (raider) | Fusta | held 10 % (slipped 8, drove off 2), paid 91 %, lost 0 %; hull lost 4 % / theirs 6 % | held 51 % (slipped 0, drove off 1), paid 50 %, lost 0 %; hull lost 6 % / theirs 4 % |
| Brigantin (raider) | Barque | held 100 % (slipped 8, drove off 0), paid 0 %, lost 0 %; hull lost 0 % / theirs 5 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 5 % / theirs 0 % |
| Galeotta (raider) | Galea sottile | held 59 % (slipped 6, drove off 53), paid 38 %, lost 4 %; hull lost 13 % / theirs 12 % | held 48 % (slipped 0, drove off 48), paid 51 %, lost 2 %; hull lost 14 % / theirs 14 % |
| Galeotta (raider) | Marciliana | held 100 % (slipped 8, drove off 11), paid 0 %, lost 0 %; hull lost 4 % / theirs 7 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 7 % / theirs 4 % |
| Firkate (raider) | Fusta | held 8 % (slipped 6, drove off 2), paid 92 %, lost 0 %; hull lost 3 % / theirs 5 % | held 1 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 6 % / theirs 4 % |
| Firkate (raider) | Kayık | held 100 % (slipped 8, drove off 0), paid 0 %, lost 0 %; hull lost 0 % / theirs 4 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 4 % / theirs 0 % |
| Lancaran (raider) | Ghurab | held 8 % (slipped 6, drove off 2), paid 93 %, lost 0 %; hull lost 5 % / theirs 5 % | held 2 % (slipped 0, drove off 2), paid 98 %, lost 0 %; hull lost 5 % / theirs 5 % |
| Lancaran (raider) | Carabela de Indias | held 100 % (slipped 13, drove off 0), paid 0 %, lost 0 %; hull lost 3 % / theirs 2 % | held 0 % (slipped 0, drove off 0), paid 44 %, lost 56 %; hull lost 2 % / theirs 4 % |
| Shaochuan (raider) | Fusta | held 7 % (slipped 6, drove off 1), paid 94 %, lost 0 %; hull lost 3 % / theirs 5 % | held 55 % (slipped 0, drove off 0), paid 45 %, lost 0 %; hull lost 5 % / theirs 3 % |
| Shaochuan (raider) | Crayer | held 100 % (slipped 8, drove off 0), paid 0 %, lost 0 %; hull lost 0 % / theirs 4 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 4 % / theirs 0 % |
| Bahansen (raider) | Sekibune | held 65 % (slipped 6, drove off 59), paid 31 %, lost 4 %; hull lost 13 % / theirs 13 % | held 57 % (slipped 0, drove off 57), paid 41 %, lost 3 %; hull lost 15 % / theirs 15 % |
| Bahansen (raider) | Carabela de Indias | held 100 % (slipped 13, drove off 5), paid 0 %, lost 0 %; hull lost 4 % / theirs 6 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 6 % / theirs 4 % |
| Sahuseon (raider) | Fusta | held 8 % (slipped 6, drove off 2), paid 92 %, lost 0 %; hull lost 3 % / theirs 6 % | held 16 % (slipped 0, drove off 0), paid 85 %, lost 0 %; hull lost 6 % / theirs 4 % |
| Sahuseon (raider) | Crayer | held 100 % (slipped 8, drove off 0), paid 0 %, lost 0 %; hull lost 0 % / theirs 5 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 6 % / theirs 0 % |
| Galeoncete (gunship) | Pinas | held 77 % (slipped 0, drove off 77), paid 23 %, lost 0 %; hull lost 3 % / theirs 17 % | held 0 % (slipped 0, drove off 0), paid 92 %, lost 9 %; hull lost 21 % / theirs 5 % |
| Galeoncete (gunship) | Urca | held 67 % (slipped 0, drove off 67), paid 34 %, lost 0 %; hull lost 4 % / theirs 16 % | held 0 % (slipped 0, drove off 0), paid 97 %, lost 3 %; hull lost 18 % / theirs 5 % |
| Great Galley (gunship) | Race-built Galleon | held 77 % (slipped 0, drove off 77), paid 16 %, lost 8 %; hull lost 7 % / theirs 17 % | held 61 % (slipped 0, drove off 20), paid 39 %, lost 0 %; hull lost 21 % / theirs 10 % |
| Great Galley (gunship) | Retourschip | held 100 % (slipped 2, drove off 92), paid 1 %, lost 0 %; hull lost 1 % / theirs 17 % | held 0 % (slipped 0, drove off 0), paid 7 %, lost 93 %; hull lost 27 % / theirs 2 % |
| Roberge (gunship) | Galère | held 70 % (slipped 0, drove off 70), paid 23 %, lost 8 %; hull lost 7 % / theirs 16 % | held 67 % (slipped 0, drove off 14), paid 34 %, lost 0 %; hull lost 18 % / theirs 9 % |
| Roberge (gunship) | Navire marchand | held 74 % (slipped 0, drove off 74), paid 26 %, lost 0 %; hull lost 4 % / theirs 17 % | held 0 % (slipped 0, drove off 0), paid 95 %, lost 6 %; hull lost 20 % / theirs 6 % |
| Göke (gunship) | Kalyon | held 68 % (slipped 0, drove off 68), paid 21 %, lost 12 %; hull lost 6 % / theirs 15 % | held 81 % (slipped 0, drove off 4), paid 19 %, lost 0 %; hull lost 16 % / theirs 8 % |
| Göke (gunship) | Nau da Carreira | held 99 % (slipped 2, drove off 85), paid 1 %, lost 0 %; hull lost 1 % / theirs 17 % | held 0 % (slipped 0, drove off 0), paid 26 %, lost 74 %; hull lost 23 % / theirs 3 % |
| Wugongchuan (gunship) | Cangshan | held 23 % (slipped 0, drove off 23), paid 74 %, lost 3 %; hull lost 4 % / theirs 10 % | held 69 % (slipped 0, drove off 1), paid 32 %, lost 0 %; hull lost 10 % / theirs 5 % |
| Wugongchuan (gunship) | Shachuan | held 100 % (slipped 2, drove off 8), paid 0 %, lost 0 %; hull lost 2 % / theirs 8 % | held 0 % (slipped 0, drove off 0), paid 61 %, lost 39 %; hull lost 8 % / theirs 2 % |
| Galé (boarder) | Pinas | held 100 % (slipped 0, drove off 0), paid 0 %, lost 0 %; hull lost 11 % / theirs 6 % | held 21 % (slipped 0, drove off 21), paid 0 %, lost 80 %; hull lost 5 % / theirs 11 % |
| Galé (boarder) | Urca | held 100 % (slipped 0, drove off 0), paid 0 %, lost 0 %; hull lost 11 % / theirs 5 % | held 23 % (slipped 0, drove off 23), paid 0 %, lost 77 %; hull lost 5 % / theirs 11 % |
| Galera (boarder) | Pinas | held 100 % (slipped 0, drove off 1), paid 0 %, lost 0 %; hull lost 9 % / theirs 7 % | held 11 % (slipped 0, drove off 11), paid 0 %, lost 90 %; hull lost 7 % / theirs 9 % |
| Galera (boarder) | Urca | held 100 % (slipped 0, drove off 0), paid 0 %, lost 0 %; hull lost 10 % / theirs 5 % | held 15 % (slipped 0, drove off 15), paid 0 %, lost 85 %; hull lost 5 % / theirs 9 % |
| Galea capitana (boarder) | Galeão | held 100 % (slipped 0, drove off 0), paid 0 %, lost 0 %; hull lost 15 % / theirs 6 % | held 56 % (slipped 0, drove off 56), paid 0 %, lost 44 %; hull lost 5 % / theirs 14 % |
| Galea capitana (boarder) | Caracca genovese | held 100 % (slipped 2, drove off 3), paid 0 %, lost 0 %; hull lost 6 % / theirs 7 % | held 1 % (slipped 0, drove off 1), paid 0 %, lost 100 %; hull lost 7 % / theirs 6 % |
| Kalyata (boarder) | Şebek (xebec) | held 63 % (slipped 0, drove off 1), paid 37 %, lost 0 %; hull lost 14 % / theirs 5 % | held 51 % (slipped 0, drove off 51), paid 41 %, lost 8 %; hull lost 4 % / theirs 12 % |
| Kalyata (boarder) | Carabela de Indias | held 100 % (slipped 2, drove off 0), paid 0 %, lost 0 %; hull lost 3 % / theirs 3 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 3 % / theirs 3 % |
| Parau (boarder) | Fusta | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 5 % / theirs 1 % | held 4 % (slipped 0, drove off 2), paid 96 %, lost 0 %; hull lost 1 % / theirs 5 % |
| Parau (boarder) | Dhow | held 100 % (slipped 2, drove off 0), paid 0 %, lost 0 %; hull lost 0 % / theirs 1 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 1 % / theirs 0 % |
| Ghali (boarder) | Pinas | held 100 % (slipped 2, drove off 0), paid 0 %, lost 0 %; hull lost 9 % / theirs 3 % | held 12 % (slipped 0, drove off 12), paid 51 %, lost 38 %; hull lost 3 % / theirs 9 % |
| Ghali (boarder) | Baghlah | held 100 % (slipped 0, drove off 0), paid 0 %, lost 0 %; hull lost 5 % / theirs 3 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 3 % / theirs 5 % |
| Mengchong (boarder) | Pinas | held 100 % (slipped 0, drove off 0), paid 0 %, lost 0 %; hull lost 9 % / theirs 5 % | held 8 % (slipped 0, drove off 8), paid 0 %, lost 93 %; hull lost 5 % / theirs 9 % |
| Mengchong (boarder) | Junk (Fuzhou trader) | held 100 % (slipped 0, drove off 0), paid 0 %, lost 0 %; hull lost 7 % / theirs 4 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 4 % / theirs 7 % |
| Mekurabune (boarder) | Pinas | held 100 % (slipped 2, drove off 1), paid 0 %, lost 0 %; hull lost 10 % / theirs 7 % | held 16 % (slipped 0, drove off 16), paid 0 %, lost 85 %; hull lost 7 % / theirs 10 % |
| Mekurabune (boarder) | Shuinsen | held 100 % (slipped 0, drove off 1), paid 0 %, lost 0 %; hull lost 12 % / theirs 7 % | held 29 % (slipped 0, drove off 29), paid 0 %, lost 71 %; hull lost 6 % / theirs 12 % |
| Geomseon (boarder) | Byeongseon | held 54 % (slipped 0, drove off 1), paid 46 %, lost 0 %; hull lost 15 % / theirs 5 % | held 57 % (slipped 0, drove off 57), paid 37 %, lost 6 %; hull lost 4 % / theirs 13 % |
| Geomseon (boarder) | Sangseon | held 100 % (slipped 2, drove off 0), paid 0 %, lost 0 %; hull lost 4 % / theirs 4 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 4 % / theirs 4 % |
| Daemaengseon (boarder) | Panokseon | held 75 % (slipped 0, drove off 0), paid 25 %, lost 0 %; hull lost 14 % / theirs 5 % | held 48 % (slipped 0, drove off 48), paid 49 %, lost 4 %; hull lost 4 % / theirs 14 % |
| Daemaengseon (boarder) | Retourschip | held 100 % (slipped 2, drove off 5), paid 0 %, lost 0 %; hull lost 3 % / theirs 8 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 8 % / theirs 3 % |
| Nau capitânia (line) | Grand navire | held 34 % (slipped 0, drove off 28), paid 66 %, lost 0 %; hull lost 6 % / theirs 12 % | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 11 % / theirs 6 % |
| Nau capitânia (line) | Nau da Carreira | held 100 % (slipped 2, drove off 61), paid 0 %, lost 0 %; hull lost 2 % / theirs 15 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 17 % / theirs 2 % |
| Kraweel (line) | Galeão | held 19 % (slipped 0, drove off 19), paid 82 %, lost 0 %; hull lost 6 % / theirs 10 % | held 11 % (slipped 0, drove off 0), paid 89 %, lost 0 %; hull lost 11 % / theirs 6 % |
| Kraweel (line) | Retourschip | held 100 % (slipped 2, drove off 54), paid 0 %, lost 0 %; hull lost 1 % / theirs 13 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 15 % / theirs 2 % |
| Nef (line) | Galion | held 65 % (slipped 0, drove off 62), paid 35 %, lost 0 %; hull lost 5 % / theirs 14 % | held 0 % (slipped 0, drove off 0), paid 97 %, lost 3 %; hull lost 16 % / theirs 6 % |
| Nef (line) | Retourschip | held 100 % (slipped 4, drove off 79), paid 0 %, lost 0 %; hull lost 1 % / theirs 16 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 22 % / theirs 2 % |
| Barza (line) | Galeazza | held 67 % (slipped 0, drove off 64), paid 34 %, lost 0 %; hull lost 5 % / theirs 15 % | held 0 % (slipped 0, drove off 0), paid 95 %, lost 5 %; hull lost 17 % / theirs 7 % |
| Barza (line) | Nau da Carreira | held 100 % (slipped 2, drove off 72), paid 0 %, lost 0 %; hull lost 1 % / theirs 17 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 20 % / theirs 2 % |
| Louchuan (line) | Grand navire | held 24 % (slipped 0, drove off 16), paid 77 %, lost 0 %; hull lost 5 % / theirs 10 % | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 10 % / theirs 5 % |
| Louchuan (line) | Dachuan (great junk) | held 100 % (slipped 2, drove off 24), paid 0 %, lost 0 %; hull lost 1 % / theirs 11 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 12 % / theirs 1 % |
| Tekkōsen (line) | Ō-atakebune | held 70 % (slipped 0, drove off 69), paid 30 %, lost 0 %; hull lost 5 % / theirs 15 % | held 0 % (slipped 0, drove off 0), paid 97 %, lost 4 %; hull lost 17 % / theirs 7 % |
| Tekkōsen (line) | Nau da Carreira | held 100 % (slipped 4, drove off 72), paid 0 %, lost 0 %; hull lost 1 % / theirs 16 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 20 % / theirs 2 % |
| Friedeschiff (escort) | Pinas | held 23 % (slipped 15, drove off 8), paid 77 %, lost 0 %; hull lost 5 % / theirs 8 % | held 8 % (slipped 0, drove off 0), paid 92 %, lost 0 %; hull lost 9 % / theirs 6 % |
| Friedeschiff (escort) | Fluit | held 89 % (slipped 15, drove off 16), paid 12 %, lost 0 %; hull lost 3 % / theirs 9 % | held 0 % (slipped 0, drove off 0), paid 98 %, lost 2 %; hull lost 10 % / theirs 4 % |
| Wafter (escort) | Caravela redonda | held 53 % (slipped 15, drove off 38), paid 47 %, lost 0 %; hull lost 3 % / theirs 11 % | held 41 % (slipped 0, drove off 0), paid 60 %, lost 0 %; hull lost 14 % / theirs 4 % |
| Wafter (escort) | Carabela de Indias | held 100 % (slipped 19, drove off 7), paid 0 %, lost 0 %; hull lost 1 % / theirs 7 % | held 0 % (slipped 0, drove off 0), paid 76 %, lost 25 %; hull lost 9 % / theirs 1 % |
| Almiranta (escort) | Galeón | held 38 % (slipped 15, drove off 23), paid 63 %, lost 0 %; hull lost 5 % / theirs 10 % | held 8 % (slipped 0, drove off 0), paid 92 %, lost 0 %; hull lost 12 % / theirs 6 % |
| Almiranta (escort) | Retourschip | held 100 % (slipped 19, drove off 61), paid 0 %, lost 0 %; hull lost 1 % / theirs 14 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 20 % / theirs 1 % |
| Jungmaengseon (escort) | Pinas | held 85 % (slipped 15, drove off 33), paid 16 %, lost 0 %; hull lost 3 % / theirs 11 % | held 0 % (slipped 0, drove off 0), paid 95 %, lost 5 %; hull lost 14 % / theirs 4 % |
| Jungmaengseon (escort) | Jounseon | held 95 % (slipped 15, drove off 22), paid 5 %, lost 0 %; hull lost 4 % / theirs 10 % | held 0 % (slipped 0, drove off 0), paid 93 %, lost 7 %; hull lost 12 % / theirs 4 % |
| Caravelão (trade) | Caravela redonda | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 6 % / theirs 3 % | held 100 % (slipped 2, drove off 5), paid 0 %, lost 0 %; hull lost 3 % / theirs 6 % |
| Caravelão (trade) | Carabela de Indias | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 3 % / theirs 2 % | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 2 % / theirs 3 % |
| Chalupa (trade) | Fusta | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 4 % / theirs 0 % | held 100 % (slipped 2, drove off 0), paid 0 %, lost 0 %; hull lost 0 % / theirs 4 % |
| Chalupa (trade) | Crayer | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 0 % / theirs 0 % | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 0 % / theirs 0 % |
| Tartana (trade) | Fusta | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 5 % / theirs 0 % | held 100 % (slipped 2, drove off 1), paid 0 %, lost 0 %; hull lost 0 % / theirs 5 % |
| Tartana (trade) | Crayer | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 0 % / theirs 0 % | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 0 % / theirs 0 % |
| Boum (trade) | Ghurab | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 2 % / theirs 1 % | held 100 % (slipped 2, drove off 0), paid 0 %, lost 0 %; hull lost 1 % / theirs 2 % |
| Boum (trade) | Carabela de Indias | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 3 % / theirs 1 % | held 11 % (slipped 0, drove off 0), paid 90 %, lost 0 %; hull lost 1 % / theirs 3 % |
| Şayka (trade) | Şebek (xebec) | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 6 % / theirs 3 % | held 100 % (slipped 2, drove off 5), paid 0 %, lost 0 %; hull lost 3 % / theirs 6 % |
| Şayka (trade) | Carabela de Indias | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 3 % / theirs 2 % | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 2 % / theirs 3 % |
| Bezaisen (trade) | Sekibune | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 8 % / theirs 4 % | held 100 % (slipped 2, drove off 12), paid 0 %, lost 0 %; hull lost 4 % / theirs 8 % |
| Bezaisen (trade) | Carabela de Indias | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 3 % / theirs 2 % | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 2 % / theirs 3 % |
| Nao (armed) | Galeón | held 0 % (slipped 0, drove off 0), paid 99 %, lost 2 %; hull lost 14 % / theirs 5 % | held 53 % (slipped 2, drove off 49), paid 48 %, lost 0 %; hull lost 5 % / theirs 13 % |
| Nao (armed) | Retourschip | held 100 % (slipped 0, drove off 49), paid 0 %, lost 0 %; hull lost 2 % / theirs 14 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 15 % / theirs 2 % |
| Kogge (armed) | Caravela redonda | held 2 % (slipped 0, drove off 2), paid 1 %, lost 98 %; hull lost 6 % / theirs 6 % | held 100 % (slipped 2, drove off 5), paid 0 %, lost 0 %; hull lost 6 % / theirs 6 % |
| Kogge (armed) | Haringbuis | held 71 % (slipped 0, drove off 2), paid 30 %, lost 0 %; hull lost 2 % / theirs 6 % | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 6 % / theirs 2 % |
| Byeongjoseon (armed) | Pinas | held 99 % (slipped 0, drove off 75), paid 1 %, lost 0 %; hull lost 3 % / theirs 17 % | held 0 % (slipped 0, drove off 0), paid 26 %, lost 75 %; hull lost 21 % / theirs 5 % |
| Byeongjoseon (armed) | Jounseon | held 100 % (slipped 0, drove off 66), paid 0 %, lost 0 %; hull lost 4 % / theirs 16 % | held 0 % (slipped 0, drove off 0), paid 16 %, lost 85 %; hull lost 18 % / theirs 5 % |
| Kenminsen (armed) | Atakebune | held 1 % (slipped 0, drove off 1), paid 95 %, lost 5 %; hull lost 18 % / theirs 7 % | held 68 % (slipped 2, drove off 66), paid 32 %, lost 0 %; hull lost 5 % / theirs 15 % |
| Kenminsen (armed) | Retourschip | held 100 % (slipped 2, drove off 14), paid 0 %, lost 0 %; hull lost 4 % / theirs 10 % | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 9 % / theirs 4 % |
| Kotia (armed) | Pinas | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 9 % / theirs 5 % | held 8 % (slipped 0, drove off 8), paid 92 %, lost 0 %; hull lost 5 % / theirs 8 % |
| Kotia (armed) | Baghlah | held 100 % (slipped 0, drove off 13), paid 0 %, lost 0 %; hull lost 2 % / theirs 9 % | held 0 % (slipped 0, drove off 0), paid 59 %, lost 42 %; hull lost 9 % / theirs 3 % |
| Hoy (carrier) | Fusta | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 5 % / theirs 0 % | held 100 % (slipped 4, drove off 0), paid 0 %, lost 0 %; hull lost 0 % / theirs 5 % |
| Hoy (carrier) | Crayer | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 0 % / theirs 0 % | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 0 % / theirs 0 % |
| Holk (carrier) | Pinas | held 0 % (slipped 0, drove off 0), paid 18 %, lost 82 %; hull lost 12 % / theirs 2 % | held 100 % (slipped 2, drove off 24), paid 0 %, lost 0 %; hull lost 2 % / theirs 11 % |
| Holk (carrier) | Fluit | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 8 % / theirs 3 % | held 4 % (slipped 2, drove off 3), paid 96 %, lost 0 %; hull lost 3 % / theirs 8 % |
| Cocca (carrier) | Pinas | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 11 % / theirs 3 % | held 21 % (slipped 2, drove off 19), paid 80 %, lost 0 %; hull lost 3 % / theirs 10 % |
| Cocca (carrier) | Galea grossa | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 11 % / theirs 5 % | held 25 % (slipped 2, drove off 23), paid 76 %, lost 0 %; hull lost 5 % / theirs 11 % |
| Caochuan (carrier) | Pinas | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 8 % / theirs 2 % | held 49 % (slipped 2, drove off 4), paid 52 %, lost 0 %; hull lost 2 % / theirs 8 % |
| Caochuan (carrier) | Junk (Fuzhou trader) | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 6 % / theirs 3 % | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 3 % / theirs 6 % |
| Taforeia (carrier) | Galeão | held 0 % (slipped 0, drove off 0), paid 4 %, lost 96 %; hull lost 14 % / theirs 2 % | held 100 % (slipped 4, drove off 50), paid 0 %, lost 0 %; hull lost 1 % / theirs 13 % |
| Taforeia (carrier) | Retourschip | held 58 % (slipped 0, drove off 0), paid 42 %, lost 0 %; hull lost 4 % / theirs 3 % | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 3 % / theirs 4 % |
| Hourque (carrier) | Galion | held 0 % (slipped 0, drove off 0), paid 4 %, lost 97 %; hull lost 16 % / theirs 2 % | held 100 % (slipped 4, drove off 60), paid 0 %, lost 0 %; hull lost 1 % / theirs 14 % |
| Hourque (carrier) | Retourschip | held 69 % (slipped 0, drove off 0), paid 32 %, lost 0 %; hull lost 4 % / theirs 4 % | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 4 % / theirs 4 % |
| Jong (carrier) | Grand navire | held 0 % (slipped 0, drove off 0), paid 0 %, lost 100 %; hull lost 15 % / theirs 1 % | held 100 % (slipped 4, drove off 57), paid 0 %, lost 0 %; hull lost 1 % / theirs 14 % |
| Jong (carrier) | Hajji Jahaz | held 0 % (slipped 0, drove off 0), paid 100 %, lost 0 %; hull lost 3 % / theirs 1 % | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 1 % / theirs 3 % |
| Nave grossa (carrier) | Galeón real | held 0 % (slipped 0, drove off 0), paid 40 %, lost 61 %; hull lost 17 % / theirs 1 % | held 100 % (slipped 6, drove off 59), paid 0 %, lost 0 %; hull lost 1 % / theirs 14 % |
| Nave grossa (carrier) | Carraca grande | held 90 % (slipped 0, drove off 0), paid 10 %, lost 0 %; hull lost 5 % / theirs 2 % | held 2 % (slipped 2, drove off 0), paid 99 %, lost 0 %; hull lost 2 % / theirs 5 % |

## What does not move, and how it is held

The migration writes rows of seven catalogue tables for the 54 codes and nothing else: no function, no knob, no table, no column, no grant. Its self-assert holds, inside the one transaction:

- every row of `ship_classes`, `class_profile`, `class_slots`, `class_cabins`, `class_slot_unlocks`, `hull_recipes`, `hull_recipe_goods`, `hull_recipe_items`, `skill_requirements`, `ship_lines`, `npc_line_hulls`, `npc_loadouts` and `ship_variety` that is not one of the 54's is the same text before and after (one md5 over all of them; locally `e94802f387dcf73fa0005e29ee70f250` at head 0356);
- every function of `public`, `cmd`, `world` and `voyage` is the same definition, ACL, volatility and config (locally `e86d7ab9a9e89d85bfadf0fcfc36ee35`), and every `world_config` row is the same;
- a probe of `voyage.fight_resolve` on the golden digest's hulls (180 raids) answers the same text before and after, and `voyage.raider_hulls` builds the same raiders;
- no merchant (`npc_line_hulls`), no loadout, no knob and no ship names a new class;
- every new class is whole by the older files' rules (tier of its size, guns a tenth of attack, the one wave rule, T1, its line's requirements), no name or code answers for two classes (`cmd.resolve_class`), each has a build yard of its own country at its tier, and its materials fit the 750-tun shed;
- both reads serve them, and the engine fights them: a Great Galley set upon by a Daemaengseon, at LONG range only the longer reach fires.

The generator does not offer Wave E to the merchants: S18's table (`merchant`, the hull a merchant company sails in place of a live class) is cut from Waves A to D only, and the generated rows are the same five as before. So no NPC is given a new hull by this file or by a later founding.

The whole golden digest (`scripts/ops/harness/two-sides/golden.sql`, 1,080 raids) is `5dd44b7077ef9415f50057f399797923` at head 0356 and the same after 0366, locally. It is a prod check before and after the deploy.

The Barca's rows are not written and not read by name. 0363 (open on `second-ship`) deletes her two fittings and rewords her note; 0366 applies on a chain with it and on one without it (see "Checks").

## What the client shows

- The Codex ships list and the build yard list the 54 because the server serves them. Each job hull wears a small badge: Raider, Gunship, Boarder, Line ship, Escort, Armed trader, Cargo (약탈선, 포격선, 돌격선, 전열함, 호위선, 무장 상선, 화물선). The served role stays Trade, Combat or Support beside it.
- The Codex has a sixth picker, Job, and the search finds a job's word.
- A ship's sheet in the Codex and in the yard says her job and the five figures the fight reads: attack, accuracy, reach, armour, sighting (one renderer, `HullFight`). They have ridden the snapshot since 0074 and were never printed for a class.
- The yard names a hull in Korean as the Codex does (it printed the served name before).
- The map draws a new hull by her rig and size through the one renderer. No silhouette was added: the twelve cover every rig family and size, and both facts are served.
- Every one of the 54 has a Korean name in `KO_HULLS`. Korean and Chinese hulls take their own reading (검선, 대맹선, 병조선, 누선, 몽충선, 오공선); the others are written as Korean writes the foreign word.

## Decided by default (the owner may reverse any of these)

1. **54 hulls, 31 combat + 4 escorts against 19 trade and cargo.** "Especially combat" was read as about two thirds.
2. **"Cargo" is a job of the trade role, not a fifth role.** A fifth role would need the check constraints of three tables, a cabin rotation, skill effects and a wave rule. The Cargo badge says it on the faces. The crown's Cargo ship (the Type filter) is a different thing and is unchanged.
3. **The job word is client data from the generator, not a served column.** No rule reads a job. Serving it would re-cut `world.snapshot` and `world.building_yard`, and 0358 (open) re-cuts the yard read. `scripts/build-ships.mjs --check` and `tests/ships.more.spec.ts` hold the client's table to the generator.
4. **Every new hull is T1** and asks only its line's hull skills. No new skill, so nobody's training is moved.
5. **A gunned job asks iron** (2 to 6 a size) on top of the size's template. Iron is already in the Japanese and Korean recipes. Cannon as a good was not used: no hull recipe asks a made good of the guns category today, and iron keeps a new recipe inside what the older ones ask.
6. **Hanseatic ships are in the Dutch line, Malay and Javanese ships in the Arabia & India line.** Those lines already count the Hanse towns and Banten among their builders. No new line.
7. **No new silhouette.** The brief allowed adding silhouettes as data; none was needed.
8. **No merchant, pirate, navy or cargo ship sails a new hull.** The knobs that name their classes are the owner's.
9. **The very large carrier is Italian, a flagship (Nave grossa, 1,755 t at 3.4 knots).** She is the largest hold that is not a famous ship (the Madre de Deus, the Rahimi and the Baochuan stay larger) and the slowest hull in the game.
10. **A ship's class on the fleet faces still prints as served** (in Korean too). That is how every hull prints there today; the store's fleet read is not localised by this slice.
11. **The balance is told by the engine as it is.** The fight favours the side that closes, for old hulls and new. No knob was moved to change that.
12. **The roberge (1540s) and the Tekkōsen (1578) are a little after 1507.** The game already has later ships (the fluit, the turtle ship).

## Checks (2026-11-13, this PC, PGlite, cached chain; never from zero)

- **Apply and self-assert.** 0366 on the cached head 0356: `0366 self-assert ok`, 1,031 ms. World guard after it: 157 class profiles, 157 ship classes, 631 skill requirements, "generators re-run = files = database".
- **With the open chain beneath it.** A throwaway worktree of `origin/batch-5` (0357, 0358, 0360, 0361, 0362 and 0363, the Barca's fittings) with 0366 on top: 7 migrations applied on the cached 0356, every receipt, the world guard green, proof 67 7 of 7, proof 28 6 of 6. So it applies with 0363 and without it.
- **Proof 67** (`scripts/db/proofs/67_more_ships.sql`), 7 of 7: the 54 served and offered by a yard of their own country at the recipe's labour; the Great Galley refused at another country's yard, with no skills, with an empty shed and a ducat short; a hull of every job laid down by `cmd.do_build` (raider Bahansen, gunship Great Galley, boarder Daemaengseon, line Barza, escort Wafter, armed Byeongjoseon, carrier Hoy, plain Bezaisen); the built gunship set upon by the built boarder, 40 fights, 120 long rounds fired by the longer reach alone; the built boarder holds 40 of 40 raids of one xebec; the built Hoy's fleet holds 0 of 40 alone and 40 of 40 with the built Wafter beside it; no NPC, knob or crown names a new class.
- **Neighbour proofs**, each green on the chain with 0366: 18 cargo ships, 28 fight sides (2,880 fights word for word), 30 every NPC ship, 31 battles, 39 a player builds the crown ships, 46 pirate ships sail, 51 crown hulls have a level, 56 combat log.
- **Red first and mutations** (`scripts/ops/harness/more-ships/proof-0366.mjs`): proof 67 is red with no file; 15 breakages of the file are each red for their own reason (an older hull, recipe or requirement moved; a merchant given a new hull; a knob written; the raiders' class moved; a function re-cut; a wrong wave resistance; guns not a tenth of attack; a dropped requirement; a material that is no good; a taken name; an any-yard hull; another line's skill; the file applied twice).
- **Prod check files, run locally**: `before.sql` at 0356 and `after.sql` after 0366 print the same `old_rows` and `functions`; classes 103 then 157; every other figure as their headers want. The rollback draft after 0366 brings `before.sql` back to its first answer (news row 1). `two-sides/golden.sql`: the same digest at 0356 and after 0366.
- **Client**: `tsc -b`, `eslint .`, `vite build` green. Specs green against a preview of this build (port 4415, private in-browser world): `ships.more` (11: the files agree; the Codex and the yard at 390 and 320 px, English and Korean), `names.whole`, `small.screens`, `codex.design`, `captains.codex`, `yard.sources`, `rpc.yardSources`, `rpc.surface`, `i18n.keys`, `i18n.ko`, `news.lint`, `sections`, `duplication`, `cargo.design`, `skills.catalogue`, `captains.catalogue`. `duplication` was red once (the badge recipe written twice) and is green since `HullBadge`.
- **Not run here**: a from-zero replay and the whole proof suite (CI's), and nothing on prod (no read, no write).

## Rollback

`scripts/ops/harness/more-ships/rollback-0366.sql`, a draft: a forward migration that deletes the 54 classes' rows. It refuses while a ship of one of them exists. Run locally after 0366 it leaves the old-rows digest at `e94802f3…`, the value from before. The lighter answer for one bad hull is to delete her `hull_recipes` row: built ships stay whole and the yard stops offering her.
