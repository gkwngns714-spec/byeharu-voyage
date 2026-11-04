# 2026-11-04 - A city has people (migration 0304)

Branch `city-population` · migration `supabase/migrations/20260818000304_a_city_has_people.sql` · proof `scripts/db/proofs/14_city_population.sql`
· data `data/port-population.json` (authored in `scripts/build-population.mjs`). Prod head when cut: 0303. **Not deployed** (PR only).

## The orders (owner, verbatim)
1. "set population on cities, based on real life. Then with that population, they will provide gold to that city they reside in. So the cities will create money on its own."
2. "the population will change too, every 10 minute it will grow, stay still, or diminish. grow - invested alot. stay still - nothing unusual, diminish - war, famine, etc. Set up a mechanism of population and its growth rate."

## What was built (one authority per concept)
| Concept | The one place |
|---|---|
| Real-world figure per harbour | `scripts/build-population.mjs` -> `data/port-population.json` -> `public.port_population.baseline` (world guard holds them equal) |
| Current population (state) | `public.port_population.population`, moved only by `public.population_tick` |
| The signals | `public.population_signals()` (INVEST, FAMINE, WAR) |
| Their weights | rows of `public.population_signal_weights` |
| The growth rule | `public.population_rule(pop, baseline, score)` |
| The daily tax | `public.city_population_income(port)` |
| The 10-minute job | `public.population_tick()`, cron `byeharu-voyage:population` at :05/:15/:25/:35/:45/:55 (its own job) |
| History | `public.population_log` (one row per harbour per step, a day kept) |
| What the hall shows | `public.town_hall_people(port)` -> `world.town_hall` key `people` |

The old client-side estimate (`POPULATION_BY_TIER`, "≈" off the size tier) is **deleted**: the hall now prints the served figure.

## 1. The figures
Townspeople of the port itself, c. 1650 (the middle of the age the game shows), rounded. "Sure":
**A** a count or agreed figure · **B** a scholarly estimate (sources differ up to ~1.5x; the middle taken) · **C** thin evidence, an order of magnitude ·
**L** not a town in 1650: the first credible figure, in the year shown · **N** no figure at all: taken from the nearest analogue named.
Written from general history knowledge (city-size tables, national histories), not a single database. Counts: A 13, B 65, C 139, L 23, N 6.
**Total 7,442,750 people.** To correct a row: edit `scripts/build-population.mjs`, run `node scripts/build-population.mjs`, and a new migration updates `baseline` (0304 is frozen once deployed).

Judgement calls the owner may want to change: Hormuz uses 1600 (deserted after 1622); Seville 1646 and Naples 1650 are before their plagues halved them;
Malacca uses the 1678 Dutch census (5,000; ~20,000 under the Portuguese); Callao and Leith count the port only, not Lima / Edinburgh;
the Pacific/Australian/NZ ports (Sydney, Auckland, Wellington, Hobart, Fremantle, Darwin, Honolulu, San Francisco, San Diego, Monterey, Astoria...) are "L" figures from their founding years.

The tax column is the daily tax at the starting population (section 2).

| Code | Harbour | People | Year | Sure | Tax a day | Note |
|---|---|---:|---:|:-:|---:|---|
| ACA | Acapulco | 4,000 | 1650 | B | 11,314 | galleon port; swelled several-fold during the Manila galleon fair |
| ACC | Accra | 5,000 | 1650 | C | 13,375 | Ga towns beside the European forts |
| ADE | Aden | 10,000 | 1650 | C | 22,494 | much shrunk since its medieval height |
| AGA | Agadir | 3,000 | 1650 | C | 9,118 | Santa Cruz do Cabo, a small Saadian port after the Portuguese left (1541) |
| ALE | Alexandria | 20,000 | 1650 | B | 37,830 | Ottoman Alexandria in decline (estimates 8,000-50,000) |
| ALG | Algiers | 80,000 | 1650 | B | 106,998 | the corsair capital at its height (estimates 60,000-100,000+) |
| AMB | Ambon | 6,000 | 1650 | C | 15,335 | Dutch Fort Victoria and town |
| AMS | Amsterdam | 175,000 | 1650 | A | 192,459 |  |
| ANC | Ancona | 20,000 | 1650 | B | 37,830 |  |
| ANG | Angra | 10,000 | 1650 | B | 22,494 | the chief town of the Azores |
| ANT | Antalya | 10,000 | 1650 | C | 22,494 |  |
| ARP | Antwerp | 65,000 | 1650 | A | 91,568 | down from 100,000 in 1560 after the Scheldt was closed |
| ARI | Arica | 2,000 | 1650 | C | 6,727 | silver port of Potosi |
| ARK | Arkhangelsk | 5,000 | 1650 | C | 13,375 | Russia's only sea port to the west |
| AST | Astoria | 150 | 1813 | L | 964 | Fort Astoria, founded 1811 |
| AUK | Auckland | 3,000 | 1845 | L | 9,118 | founded 1840 |
| AYU | Ayutthaya | 150,000 | 1650 | B | 171,446 | Siam's capital; estimates up to 200,000 |
| BAN | Banda Aceh | 50,000 | 1650 | C | 75,212 | capital of the Aceh sultanate |
| BND | Banda Neira | 3,000 | 1650 | C | 9,118 | Dutch perkenier settlement after the 1621 conquest |
| BAS | Bandar Abbas | 15,000 | 1650 | C | 30,488 | Gombroon, Persia's port after Hormuz fell (1622) |
| BNT | Banten | 70,000 | 1650 | C | 96,802 | the Banten sultanate's pepper port |
| BAR | Barcelona | 40,000 | 1650 | B | 63,622 |  |
| NAV | Navidad | 200 | 1650 | C | 1,196 | the 1564 Legazpi departure port; little more than a landing by 1650 |
| BSR | Basra | 40,000 | 1650 | C | 63,622 | Ottoman Basra |
| BEI | Beirut | 6,000 | 1650 | C | 15,335 |  |
| BEL | Belem | 2,000 | 1650 | C | 6,727 | founded 1616 |
| BER | Bergen | 14,000 | 1650 | A | 28,950 | Norway's largest town |
| BIL | Bilbao | 10,000 | 1650 | B | 22,494 |  |
| BOR | Bordeaux | 45,000 | 1650 | B | 69,498 |  |
| BOS | Boston | 3,000 | 1650 | A | 9,118 |  |
| BRI | Bridgetown | 3,000 | 1650 | C | 9,118 | the island of Barbados held ~40,000; its town far fewer |
| BRS | Bristol | 20,000 | 1650 | B | 37,830 |  |
| BRU | Bruges | 30,000 | 1650 | B | 51,274 |  |
| BUV | Buenaventura | 300 | 1650 | C | 1,621 | a river landing, abandoned and refounded more than once |
| BUE | Buenos Aires | 4,000 | 1650 | B | 11,314 |  |
| BUS | Busan | 15,000 | 1650 | C | 30,488 | Dongnae town and the Japan House (Waegwan) |
| CAD | Cadiz | 30,000 | 1650 | B | 51,274 | rising toward 40,000 by 1700 |
| CAG | Cagliari | 20,000 | 1650 | B | 37,830 |  |
| CAL | Calabar | 5,000 | 1650 | C | 13,375 | Efik towns of Old Calabar |
| CLS | Calais | 8,000 | 1650 | B | 19,027 |  |
| CLL | Callao | 5,000 | 1650 | B | 13,375 | the port alone; Lima (~25,000) lies inland |
| CAP | Cape Coast | 3,000 | 1650 | C | 9,118 |  |
| CPT | Cape Town | 1,500 | 1700 | L | 5,422 | founded 1652 by the VOC |
| CAR | Cartagena | 10,000 | 1650 | B | 22,494 |  |
| CEB | Cebu | 3,000 | 1650 | C | 9,118 | Spanish town and its Parian |
| CEU | Ceuta | 4,000 | 1650 | C | 11,314 | a garrison town |
| CHE | Chennai | 20,000 | 1650 | C | 37,830 | Madras, founded 1639; ~40,000 by the 1670s |
| CHS | Chios | 15,000 | 1650 | C | 30,488 | the town; the island held more |
| CHI | Chittagong | 20,000 | 1650 | C | 37,830 | the Arakanese port |
| CID | Cidade Velha | 2,000 | 1650 | C | 6,727 | Ribeira Grande, in decline |
| COL | Colombo | 8,000 | 1650 | C | 19,027 | Portuguese Colombo before the Dutch siege (1656) |
| CON | Concepcion | 2,000 | 1650 | C | 6,727 | at Penco |
| COP | Copenhagen | 30,000 | 1650 | A | 51,274 |  |
| COQ | Coquimbo | 1,000 | 1650 | C | 4,000 | La Serena and its anchorage |
| COR | Corfu | 12,000 | 1650 | C | 25,790 | the Venetian town; the island held more |
| CRK | Cork | 6,000 | 1650 | B | 15,335 |  |
| CUM | Cumana | 2,000 | 1650 | C | 6,727 |  |
| DAR | Darwin | 500 | 1871 | L | 2,378 | founded 1869 as Palmerston |
| DIL | Dili | 1,000 | 1650 | N | 4,000 | a small Timorese coastal settlement; analogue: Kupang |
| DIU | Diu | 10,000 | 1650 | C | 22,494 | Portuguese Diu |
| DUB | Dublin | 20,000 | 1650 | B | 37,830 | after the 1650 plague; ~45,000 by 1680 |
| DBR | Dubrovnik | 6,000 | 1650 | B | 15,335 | the city; the republic held ~30,000 |
| REA | Realejo | 1,000 | 1650 | C | 4,000 |  |
| ELM | Elmina | 12,000 | 1650 | C | 25,790 | the town beside the castle |
| FAM | Famagusta | 2,000 | 1650 | C | 6,727 | much reduced under the Ottomans |
| FEO | Feodosia | 40,000 | 1650 | C | 63,622 | Ottoman Kefe; travellers' figures run far higher |
| FRE | Fremantle | 500 | 1832 | L | 2,378 | founded 1829 |
| FUK | Fukuoka | 40,000 | 1650 | C | 63,622 | Hakata and the Fukuoka castle town together |
| FNC | Funchal | 10,000 | 1650 | B | 22,494 |  |
| FUZ | Fuzhou | 200,000 | 1650 | C | 212,732 | Fujian's provincial capital; estimates vary widely |
| GAL | Galle | 5,000 | 1650 | C | 13,375 |  |
| GDA | Gdansk | 70,000 | 1650 | A | 96,802 |  |
| GOA | Genoa | 75,000 | 1650 | B | 101,943 | before the 1656 plague |
| GIB | Gibraltar | 4,000 | 1650 | B | 11,314 | the Spanish town before 1704 |
| GOR | Goree | 500 | 1650 | C | 2,378 |  |
| GUA | Guangzhou | 400,000 | 1650 | C | 357,771 | late-Ming Canton; sacked by the Qing in 1650 |
| GYE | Guayaquil | 5,000 | 1650 | C | 13,375 |  |
| HAD | Hadibu | 500 | 1650 | N | 2,378 | the chief village of Socotra; analogue: other Arabian Sea island towns |
| HAG | Hagatna | 1,000 | 1670 | L | 4,000 | the Spanish mission town, founded 1668 |
| HAM | Hamburg | 75,000 | 1650 | A | 101,943 |  |
| HAN | Hanoi | 100,000 | 1650 | C | 126,491 | Thang Long (Ke Cho); European visitors' estimates |
| HAV | Havana | 15,000 | 1650 | B | 30,488 | ~26,000 by 1700 |
| HER | Heraklion | 20,000 | 1650 | B | 37,830 | Venetian Candia, under siege 1648-1669 |
| HIR | Hirado | 5,000 | 1650 | C | 13,375 | in decline after the Dutch left for Dejima (1641) |
| HOB | Hobart | 1,000 | 1810 | L | 4,000 | founded 1804 |
| HOI | Hoi An | 8,000 | 1650 | C | 19,027 | Japanese and Chinese merchant quarters |
| HON | Hong Kong | 7,000 | 1841 | L | 17,214 | the British count of the island, 1841; only villages before |
| HNL | Honolulu | 6,000 | 1823 | L | 15,335 | the Hawaiian town at the first missionary estimates |
| HOO | Hooghly | 30,000 | 1650 | C | 51,274 | the Mughal port that replaced the Portuguese town (1632) |
| HRN | Hoorn | 15,000 | 1650 | A | 30,488 |  |
| HOR | Hormuz | 40,000 | 1600 | B | 63,622 | before its fall (1622); deserted by 1650, so the 1600 figure is used |
| HUA | Huatulco | 300 | 1650 | C | 1,621 | raided by Drake (1579) and Cavendish (1587) |
| INC | Incheon | 5,000 | 1650 | N | 13,375 | Joseon Incheon-bu; analogue: other Joseon county towns |
| IST | Istanbul | 700,000 | 1650 | B | 544,357 | estimates 600,000-750,000 |
| IZM | Izmir | 80,000 | 1650 | B | 106,998 | the Levant's rising entrepot |
| JAF | Jaffna | 10,000 | 1650 | C | 22,494 |  |
| JAK | Jakarta | 30,000 | 1650 | B | 51,274 | Batavia within and around the walls |
| JAM | Jamestown | 500 | 1650 | B | 2,378 | the Virginia colony held ~15,000; the town a few hundred |
| JED | Jeddah | 10,000 | 1650 | C | 22,494 |  |
| JEJ | Jeju | 10,000 | 1650 | C | 22,494 | Jeju town; the island held more |
| KAG | Kagoshima | 50,000 | 1650 | C | 75,212 | the Satsuma castle town |
| KAL | Kaliningrad | 40,000 | 1650 | B | 63,622 | Konigsberg |
| KAN | Kannur | 10,000 | 1650 | C | 22,494 |  |
| KAR | Karachi | 10,000 | 1800 | L | 22,494 | founded c. 1729 |
| KHA | Khambhat | 50,000 | 1650 | C | 75,212 | Cambay, silting and declining |
| KIL | Kilwa | 4,000 | 1650 | C | 11,314 | long past its height |
| KIN | Kingston upon Hull | 7,000 | 1650 | B | 17,214 |  |
| KOC | Kochi | 20,000 | 1650 | C | 37,830 | Portuguese Cochin and Mattancherry, before the Dutch (1663) |
| KOL | Kollam | 10,000 | 1650 | C | 22,494 |  |
| KOZ | Kozhikode | 50,000 | 1650 | C | 75,212 | the Zamorin's city |
| KUP | Kupang | 1,000 | 1650 | C | 4,000 |  |
| LAR | La Rochelle | 15,000 | 1650 | C | 30,488 | recovering after the 1628 siege |
| LAG | Lagos | 5,000 | 1650 | C | 13,375 | Eko, a Benin outpost |
| LPA | Las Palmas | 8,000 | 1650 | C | 19,027 |  |
| LEH | Le Havre | 15,000 | 1650 | C | 30,488 |  |
| LEI | Leith | 5,000 | 1650 | C | 13,375 | the port alone; Edinburgh (~30,000) lies inland |
| LIS | Lisbon | 150,000 | 1650 | B | 171,446 |  |
| LIV | Livorno | 20,000 | 1650 | B | 37,830 |  |
| LON | London | 400,000 | 1650 | A | 357,771 |  |
| LNG | Longyearbyen | 200 | 1650 | N | 1,196 | no town until 1906; analogue: the summer whaling station at Smeerenburg |
| LUA | Luanda | 6,000 | 1650 | C | 15,335 |  |
| LUB | Lubeck | 30,000 | 1650 | B | 51,274 |  |
| MAC | Macau | 30,000 | 1650 | C | 51,274 | after the Japan trade was lost (1639); ~40,000 at its height |
| MCH | Machilipatnam | 40,000 | 1650 | C | 63,622 | Golconda's great port |
| MAK | Makassar | 100,000 | 1650 | C | 126,491 | Gowa-Tallo before the Dutch conquest (1669) |
| MAL | Malacca | 5,000 | 1678 | A | 13,375 | the Dutch census of 1678; ~20,000 under the Portuguese before 1641 |
| MLG | Malaga | 25,000 | 1650 | B | 44,721 | after the 1649 plague |
| MLE | Malé | 2,000 | 1650 | C | 6,727 |  |
| MLN | Malindi | 3,000 | 1650 | C | 9,118 | in decline after the Portuguese moved to Mombasa (1593) |
| MAN | Manama | 2,000 | 1650 | C | 6,727 |  |
| MNG | Mangaluru | 10,000 | 1650 | C | 22,494 |  |
| MNL | Manila | 40,000 | 1650 | B | 63,622 | Intramuros with the Chinese Parian |
| MRS | Marseille | 65,000 | 1650 | B | 91,568 |  |
| MAS | Massawa | 2,000 | 1650 | C | 6,727 |  |
| MAT | Matsumae | 10,000 | 1650 | C | 22,494 | the Matsumae castle town |
| MZT | Mazatlan | 3,000 | 1830 | L | 9,118 | a fishing village until the port opened in the 1820s |
| MES | Messina | 80,000 | 1650 | C | 106,998 | before the 1674 revolt; figures run 60,000-120,000 |
| MEZ | Mezen | 1,000 | 1650 | C | 4,000 |  |
| MID | Middelburg | 25,000 | 1650 | B | 44,721 |  |
| MOC | Mocha | 10,000 | 1650 | C | 22,494 | the coffee port, rising |
| MOG | Mogadishu | 5,000 | 1650 | C | 13,375 |  |
| MOK | Mokpo | 1,000 | 1650 | N | 4,000 | a Joseon naval post; analogue: Yeosu's naval town, smaller |
| MOM | Mombasa | 8,000 | 1650 | C | 19,027 | under Fort Jesus |
| MTY | Monterey | 500 | 1790 | L | 2,378 | founded 1770 |
| ISL | Island of Mozambique | 3,000 | 1650 | C | 9,118 |  |
| MUM | Mumbai | 10,000 | 1661 | B | 22,494 | when ceded to England (1661) |
| MUS | Muscat | 8,000 | 1650 | C | 19,027 | retaken from the Portuguese in 1650 |
| MYE | Myeik | 5,000 | 1650 | C | 13,375 | Mergui |
| NAG | Nagasaki | 40,000 | 1650 | B | 63,622 | 25,000 in 1616, 64,500 by the 1696 count |
| NAH | Naha | 10,000 | 1650 | C | 22,494 | the port below Shuri |
| NAM | Nampo | 2,000 | 1650 | N | 6,727 | no town of the name until 1900s; analogue: Joseon river-mouth towns below Pyongyang |
| NAN | Nantes | 40,000 | 1650 | B | 63,622 |  |
| NAP | Naples | 300,000 | 1650 | B | 288,337 | before the 1656 plague killed about half |
| NEW | New York | 1,000 | 1650 | A | 4,000 | New Amsterdam |
| NIN | Ningbo | 150,000 | 1650 | C | 171,446 |  |
| NUU | Nuuk | 300 | 1730 | L | 1,621 | Godthab, founded 1728 |
| OLD | Old Goa | 40,000 | 1650 | C | 63,622 | ~75,000 in 1600, ~20,000 by 1695 |
| ORA | Oran | 5,000 | 1650 | C | 13,375 | a Spanish presidio |
| OSA | Osaka | 300,000 | 1650 | B | 288,337 |  |
| OUI | Ouidah | 10,000 | 1650 | C | 22,494 | before the slave-trade boom of the 1670s |
| PAI | Paita | 500 | 1650 | C | 2,378 |  |
| PAL | Palermo | 110,000 | 1650 | B | 135,864 |  |
| PLM | Palma de Mallorca | 25,000 | 1650 | B | 44,721 |  |
| PAN | Panama City | 8,000 | 1650 | B | 19,027 | old Panama, before the 1671 sack |
| PAR | Paramaribo | 1,000 | 1680 | L | 4,000 | English settlement 1650, Dutch from 1667 |
| PAT | Patras | 8,000 | 1650 | C | 19,027 |  |
| PTT | Pattani | 20,000 | 1650 | C | 37,830 |  |
| PLY | Plymouth | 8,000 | 1650 | B | 19,027 |  |
| PON | Ponta Delgada | 8,000 | 1650 | C | 19,027 |  |
| PLO | Port Louis | 3,000 | 1740 | L | 9,118 | founded 1735 |
| POR | Port Royal | 6,500 | 1680 | L | 16,283 | English from 1655; the 1680 figure |
| PTL | Portland | 500 | 1680 | L | 2,378 | Falmouth settlement |
| OPO | Porto | 20,000 | 1650 | B | 37,830 |  |
| PRT | Portobelo | 1,000 | 1650 | B | 4,000 | the permanent town; thousands more at the fair |
| PTH | Portsmouth | 5,000 | 1650 | B | 13,375 |  |
| PUL | Pulicat | 5,000 | 1650 | C | 13,375 | Dutch Fort Geldria |
| PUS | Pustozersk | 500 | 1650 | C | 2,378 |  |
| QUA | Quanzhou | 100,000 | 1650 | C | 126,491 | long past its Song height |
| QUE | Quebec City | 500 | 1666 | A | 2,378 | the 1666 census of the town (547) |
| REC | Recife | 8,000 | 1650 | B | 19,027 | Dutch Mauritsstad and Recife |
| REY | Reykjavik | 200 | 1786 | L | 1,196 | a farm until the 1786 trading charter |
| RHO | Rhodes | 10,000 | 1650 | C | 22,494 |  |
| RIG | Riga | 25,000 | 1650 | B | 44,721 |  |
| RIO | Rio de Janeiro | 4,000 | 1650 | C | 11,314 |  |
| ROT | Rotterdam | 30,000 | 1650 | B | 51,274 |  |
| SAF | Safi | 5,000 | 1650 | C | 13,375 |  |
| SAI | Saint-Louis | 1,000 | 1700 | L | 4,000 | founded 1659 |
| SNT | Saint-Malo | 15,000 | 1650 | C | 30,488 |  |
| SAK | Sakai | 60,000 | 1650 | C | 86,233 |  |
| SAL | Sale | 15,000 | 1650 | C | 30,488 | the corsair republic of Sale and Rabat |
| SLV | Salvador | 12,000 | 1650 | C | 25,790 | the capital of Brazil |
| SDG | San Diego | 500 | 1800 | L | 2,378 | founded 1769 |
| SFR | San Francisco | 500 | 1847 | L | 2,378 | Yerba Buena, just before the gold rush |
| SAN | San Juan | 3,000 | 1650 | C | 9,118 |  |
| SNL | Sanlucar de Barrameda | 15,000 | 1650 | C | 30,488 |  |
| TEN | Santa Cruz de Tenerife | 2,000 | 1650 | C | 6,727 | La Laguna was the island's capital |
| SGO | Santo Domingo | 5,000 | 1650 | C | 13,375 |  |
| SOS | Santos | 1,000 | 1650 | C | 4,000 |  |
| SAO | Sao Tome | 3,000 | 1650 | C | 9,118 |  |
| SET | Setubal | 10,000 | 1650 | C | 22,494 |  |
| SVQ | Seville | 120,000 | 1646 | B | 145,026 | before the 1649 plague killed about half |
| SHI | Shimonoseki | 10,000 | 1650 | C | 22,494 | Akamagaseki |
| SOF | Sofala | 1,000 | 1650 | C | 4,000 |  |
| SOY | Soyo | 5,000 | 1650 | C | 13,375 | Mbanza Soyo |
| SPL | Split | 5,000 | 1650 | C | 13,375 |  |
| STA | St. Augustine | 1,000 | 1650 | B | 4,000 |  |
| STG | St. George's | 1,000 | 1650 | C | 4,000 |  |
| STJ | St. John's | 500 | 1680 | C | 2,378 | the winter residents |
| STO | Stockholm | 40,000 | 1650 | B | 63,622 |  |
| SUA | Suakin | 5,000 | 1650 | C | 13,375 |  |
| SUE | Suez | 2,000 | 1650 | C | 6,727 |  |
| SUR | Surabaya | 10,000 | 1650 | C | 22,494 | after its conquest by Mataram (1625) |
| SRT | Surat | 100,000 | 1650 | B | 126,491 | the Mughal empire's chief port; ~200,000 by 1700 |
| SYD | Sydney | 2,500 | 1800 | L | 7,953 | founded 1788 |
| TAI | Tainan | 10,000 | 1650 | C | 22,494 | Dutch Zeelandia and Saccam with the Chinese settlers |
| TAL | Tallinn | 10,000 | 1650 | B | 22,494 |  |
| TAN | Tangier | 5,000 | 1650 | C | 13,375 |  |
| TER | Ternate | 8,000 | 1650 | C | 19,027 |  |
| THA | Thanlyin | 10,000 | 1650 | C | 22,494 | Syriam |
| THE | Thessaloniki | 40,000 | 1650 | B | 63,622 |  |
| TID | Tidore | 5,000 | 1650 | C | 13,375 |  |
| TOK | Tokyo | 500,000 | 1650 | B | 422,949 | Edo; ~1,000,000 by 1720 |
| TON | Tongyeong | 5,000 | 1650 | C | 13,375 | the Joseon naval headquarters town |
| TOR | Torshavn | 300 | 1650 | C | 1,621 |  |
| TOU | Toulon | 20,000 | 1650 | C | 37,830 |  |
| TRA | Trabzon | 15,000 | 1650 | C | 30,488 |  |
| TRI | Tripoli | 20,000 | 1650 | C | 37,830 |  |
| TRP | Tripoli | 15,000 | 1650 | C | 30,488 |  |
| TRO | Trondheim | 6,000 | 1650 | B | 15,335 |  |
| TSU | Tsushima | 10,000 | 1650 | C | 22,494 | Fuchu, the So clan's castle town |
| TUN | Tunis | 80,000 | 1650 | C | 106,998 |  |
| TUR | Turku | 5,000 | 1650 | B | 13,375 |  |
| ULS | Ulsan | 5,000 | 1650 | C | 13,375 |  |
| VAL | Valencia | 50,000 | 1650 | B | 75,212 |  |
| VLL | Valletta | 20,000 | 1650 | B | 37,830 | the harbour towns together |
| VLP | Valparaiso | 500 | 1650 | C | 2,378 |  |
| VAR | Vardo | 300 | 1650 | C | 1,621 |  |
| VEN | Venice | 140,000 | 1650 | A | 162,801 | after the 1630 plague |
| VER | Veracruz | 5,000 | 1650 | C | 13,375 |  |
| VIS | Visby | 3,000 | 1650 | C | 9,118 |  |
| WLG | Wellington | 3,000 | 1842 | L | 9,118 | founded 1840 |
| WIL | Willemstad | 2,000 | 1650 | C | 6,727 |  |
| XIA | Xiamen | 50,000 | 1650 | C | 75,212 | Koxinga's base in the 1650s |
| YEO | Yeosu | 5,000 | 1650 | C | 13,375 | the Jeolla left naval base |
| ZAK | Zakynthos | 15,000 | 1650 | C | 30,488 | the Venetian town |
| ZAN | Zanzibar | 5,000 | 1650 | C | 13,375 |  |

## 2. The daily tax
- Each harbour's people pay its city **round(population_tax_per_1000 x (population / 1000) ^ population_tax_exponent)** d. a UTC day, from the CURRENT population.
- Paid by `population_tick` at the first step of each UTC day (00:05 UTC = 09:05 KST), through `public.treasury_post`, new kind **POPULATION_TAX**,
  registered `minted` ("New money: population tax", ord 9): Stats shows it as new money. `port_population.paid_day` makes it once a day.
- Why `^0.75` (mild sub-linear): linear, the 23 biggest harbours would take 61.7 % of the tax; at 0.75 they take 46.5 %. London (400,000) pays 357,771 not 1,600,000;
  a 10,000 town pays 22,494 (16x less than London, not 40x). The investment yardstick (section 3) uses the same scale.
- **Knobs:** `population_tax_per_1000` = 4000, `population_tax_exponent` = 0.75.

### Prod measurements (read-only, 2026-11-04 06:13 UTC, head 0303; pure SELECTs, no function calls)
| | d. |
|---|---:|
| Merchants (players.is_npc) | 10,023,916,900 |
| Players | 3,330,755 |
| City purses, rolled | 23,726,616,149 |
| City purses, unrolled flows | -25,028,107 |
| Set aside (city_shares.accrued) | 1,475,339,508 |
| **Money supply** | **35,204,175,205** |
| Trade, last 30 game-days (30 real minutes; `game_day_seconds` = 60 on prod): BUY 46,522,224 + SELL 48,249,646 | 94,771,870 |
| **Trade a real day** (x 48) | **~4.55 billion** |

Switches on prod: `economy_closed` true, `city_treasury_enabled` true.

### The arithmetic
- Sum over the 246 harbours at their starting populations: **10,027,625 d. a day** (the migration prints it; the proof minted exactly this).
- = **0.028 % of the money supply a day** (about 10 % a year if nothing else changed), and **0.22 % of a day's trade**.
- If every harbour reached its ceiling (2x baseline) it would be 16,864,392 a day (0.048 %).
- Smallest: 964 a day (Astoria, 150 people). London 357,771; Istanbul 544,357 (4000 x 700^0.75); Amsterdam 192,459.
- Seen on prod while measuring: Amsterdam's purse held 630 d., Istanbul 2,874, London 7.5 M, Lisbon 350 M. A broke capital gets real money from this every day.

## 3. The 10-minute step
Every 10 minutes (`slot = epoch / 600`) each harbour takes one step. ONE set-based UPDATE over every harbour; a second run in the same slot steps nothing.

**score = sum of (weight x signal)**, each signal 0..1:

| Signal | Weight (row) | Reads (real game state only) |
|---|---:|---|
| INVEST | +1.0 | `port_treasury.invested` (0245: SHARE + DONATION, 72-hour half-life) / (`population_invest_full` x (population/1000)^0.75), capped at 1 |
| FAMINE | -1.0 | share of the harbour's staple goods (`population_staple_categories` = food, grain) with stock under `population_famine_stock_frac` (0.1) x `stock_target` |
| WAR | -1.0 | share of the harbour's influence points held by nations at war with its holder (`port_allegiance`, `power_relations`, `port_influence`) |
| PIRATES | -1.0 | **no source yet.** No live pirate pressure exists (`docs/PIRATES_AND_HAVENS.md` is design only). The row waits; a future branch of `population_signals` emits it and it counts with no other change |
| STORM | -0.5 | **no source yet.** `voyage_events` records storms but has no time index to read per city cheaply. Same plug as PIRATES |
| Blockade | - | **no data at all**: nothing in the game blocks a port. Not wired; named here |

**The rule** (`population_rule`):
- |score| < `population_hold_band` (0.5) -> **HOLD** ("nothing unusual").
- else step = min(`population_step_max` 0.0002, `population_step_base` 0.0001 x |score|): **GROW** if score > 0, **SHRINK** if < 0.
- the result is held in [`population_floor_ratio` 0.5, `population_ceiling_ratio` 2] x baseline; a step the bound stops is HOLD, reason CEILING / FLOOR.
- reason = the signal that weighed most in the step's direction.

**What a day moves** (144 steps): at score 1, 1.0001^144 = **+1.45 % a day** (or -1.43 %); at the cap (score 2+), **+2.9 % a day**. From baseline to the ceiling takes ln 2 / ln 1.0001 = 6,932 steps = **48 days** at score 1 (24 at the cap); the floor the same down.
Population is kept to 3 decimals, so a 150-person hamlet still moves (150 -> 150.015).

**What it would do on prod today** (computed from the read-only measurements, not run): INVEST >= 0.5 for **61 harbours**, almost all small ones (Arica, Astoria, Belem, Callao, Cape Town, Jamestown, New York, Quebec, Sydney, ...) - the yardstick is sub-linear, so a little money in a small town counts as heavy investment. Biggest WAR shares: Portobelo 0.61, Setubal 0.50, Funchal 0.49, Cape Coast 0.48 - but each also has investment, so **no harbour would shrink**. FAMINE: no harbour has any staple under 10 % of its target (0 of ~31,000 staple rows) - it never fires today.

**Knobs:** `population_step_base`, `population_step_max`, `population_hold_band`, `population_floor_ratio`, `population_ceiling_ratio`, `population_invest_full` (2,400,000 = 600 days of the default tax; a quarter of harbours are over half of it), `population_famine_stock_frac`, `population_staple_categories`, `population_log_slots` (144).

### Cost
- The job is its own cron entry; nothing is added to arrivals or any other hot beat.
- Local PGlite (the full chain world: 246 harbours, 154,734 market rows): the slowest tick, including a day's 246 tax posts, **303 ms** (proof 14).
- Prod: the signal read (the heavy part: the staples aggregate over `port_goods` plus investment and influence) run read-only as a pure SELECT: **indistinguishable from `select 1`** through the CLI (4.7 s vs 5.2 s, then 4.2 s vs 4.3 s: the round trip from Korea is all of it). Not measured: the UPDATE and the log insert on prod (writes; 246 rows each).
- The log holds 246 x 144 = ~35,400 rows; each step trims ~246.

## 4. The hall
City hall figures (no new row, no layout change): **Population** prints the served figure and under it the last step - `↑ Investment`, `→ Steady`, `↓ War`, `→ At its peak`...; **Gold** gains `+357,771 a day` under it. EN + KO in `src/lib/i18n/dict/city.ts`; the Stats/feed word `POPULATION_TAX` in `feed.ts`.

## 5. Tests
- **Migration self-assert** (in the file, prints a receipt; 169 ms locally): the seed is every harbour once at its baseline (total 7,442,750); the 11 knobs and 5 weights; `population_rule` on 10 literal cases (hold band, both directions, the step cap, ceiling, floor, a hamlet); the tax on the seed (London 357,771; sum 10,027,625); the guard in a rolled-back closed+lit probe (POPULATION_TAX refused without its setting, every other minted kind refused with it, POPULATION_TAX passes with it, OWNER_GRANT's exception unchanged); both hunks reverse to their pre-images; the hall serves `people`; the new pieces are server-only; nothing else moved (every other function md5, every existing knob, every existing cron job, treasury_post).
- **Proof 14** (`node scripts/db/proof.mjs 14_`, 10/10 markers, 1.6 s): the tax minted as POPULATION_TAX, one flow per harbour, each purse moved by its figure; the live Stats cities figure moved by exactly the tax (ratio 1.0000); the setting is off after the tick and every minted kind refused outside it; idempotent per slot and per day; GROW (INVEST), HOLD, SHRINK (FAMINE), SHRINK (WAR); CEILING and FLOOR; the next day pays again at the CURRENT population (London at 800,000: 601,696); the log and its trim; the hall; both off-switches; cost under 5 s.
- World guard: `public.port_population` authored columns equal `data/port-population.json`, both directions, with a planted-row positive control.

## How to turn it off (owner)
- The tax: `update public.world_config set value = '0' where key = 'population_tax_per_1000';` - nothing more is posted.
- The steps: `update public.world_config set value = '0' where key = 'population_step_base';` - every population freezes (every step HOLDs).
- Nothing else needs to change; both take effect at the next 10-minute step.

## What the owner should check
1. The population table (section 1), especially the C / L / N rows.
2. The tax size: 10.0 M a day in total (0.028 % of the money supply). Raise or lower `population_tax_per_1000`.
3. That 61 mostly-small harbours would start growing at once (the investment yardstick). Raise `population_invest_full` to make "heavy investment" rarer.
4. War is static data (two wars: Spain-Netherlands, Netherlands-Portugal) read through who holds influence in the city.
5. PIRATES / STORM / blockade have no source yet - they do nothing until one is built.

## Not verified
- Nothing ran on prod: the tick has never run against prod data. The prod figures above are read-only measurements and arithmetic.
- The cron job firing on Supabase (PGlite has no pg_cron; the migration schedules it inactive, `wind_the_clock()` starts it).
- The step's write cost on prod.
