// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REAL PORT TABLE, AS A SPEC PRECONDITION — 214 harbours, verbatim from the seed.
//
// WHY THEY ARE WRITTEN OUT HERE AND NOT READ. tsconfig.test.json deliberately withholds Node
// globals from specs (`types: ["vite/client"]`, and it says why in its own comment), so a spec can
// neither read supabase/migrations/*.sql nor import a .json. It therefore carries its own world —
// which is also the right shape for a proof: a spec that asserted whatever the ambient database
// happened to hold would be asserting a WORLD rather than a rule.
//
// The rows below are the `ports` VALUES block of
// supabase/migrations/20260818000003_the_real_world_and_the_water_between_it.sql, reduced to the
// six columns a chart uses: code | name | country | lat | lon | size_tier. The coordinates are the
// seed's (Wikidata P625, to 0.01°) and so are the tiers: 35 ports at tier 5, 79 at tier 3, 100 at
// tier 2. `REAL_PORT_COUNT` pins the total, so if the world grows and this file does not, the spec
// that reads it says so out loud instead of quietly proving less.
//
// It is a PRECONDITION, not a second source of truth: nothing in src/ imports this file, and the
// app gets its ports from `world.snapshot()` like everything else.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { FleetView, FleetVoyage, SnapshotPort } from '../src/lib/rpc'

/** code | name | country | lat | lon | size_tier */
const PORT_ROWS = `
ACA|Acapulco|Mexico|16.86|-99.89|3
ACC|Accra|Ghana|5.56|-0.2|2
ADE|Aden|Yemen|12.8|45.03|3
AGA|Agadir|Morocco|30.42|-9.58|2
ALE|Alexandria|Egypt|31.2|29.89|5
ALG|Algiers|Algeria|36.78|3.06|3
AMB|Ambon|Indonesia|-3.7|128.18|3
AMS|Amsterdam|Netherlands|52.37|4.88|5
ANC|Ancona|Italy|43.62|13.52|2
ANT|Antalya|Turkey|36.91|30.7|2
ARP|Antwerp|Belgium|51.22|4.4|5
ARK|Arkhangelsk|Russia|64.54|40.54|3
AYU|Ayutthaya|Thailand|14.36|100.58|3
BAN|Banda Aceh|Indonesia|5.55|95.32|3
BND|Banda Neira|Indonesia|-4.51|129.9|3
BAS|Bandar Abbas|Iran|27.19|56.28|3
BNT|Banten|Indonesia|-6.04|106.16|3
BAR|Barcelona|Spain|41.38|2.18|5
BSR|Basra|Iraq|30.52|47.81|3
BEI|Beirut|Lebanon|33.89|35.51|3
BEL|Belem|Brazil|-1.46|-48.5|2
BER|Bergen|Norway|60.39|5.32|3
BIL|Bilbao|Spain|43.26|-2.93|3
BOR|Bordeaux|France|44.84|-0.58|5
BOS|Boston|United States|42.36|-71.06|3
BRI|Bridgetown|Barbados|13.1|-59.62|2
BRS|Bristol|United Kingdom|51.45|-2.6|3
BRU|Bruges|Belgium|51.21|3.22|2
BUE|Buenos Aires|Argentina|-34.6|-58.38|3
BUS|Busan|South Korea|35.18|129.07|5
CAD|Cadiz|Spain|36.53|-6.3|5
CAL|Calabar|Nigeria|4.95|8.32|2
CLS|Calais|France|50.95|1.86|2
CLL|Callao|Peru|-12.05|-77.14|5
CAP|Cape Coast|Ghana|5.1|-1.25|2
CPT|Cape Town|South Africa|-33.93|18.42|3
CAR|Cartagena|Colombia|10.42|-75.53|5
CEB|Cebu|Philippines|10.29|123.9|2
CEU|Ceuta|Spain|35.89|-5.3|2
CHE|Chennai|India|13.08|80.28|3
CHI|Chittagong|Bangladesh|22.34|91.83|2
CID|Cidade Velha|Cape Verde|14.92|-23.6|2
COL|Colombo|Sri Lanka|6.93|79.86|3
COP|Copenhagen|Denmark|55.68|12.57|5
COR|Corfu|Greece|39.62|19.92|2
CRK|Cork|Ireland|51.9|-8.47|2
CUM|Cumana|Venezuela|10.45|-64.17|2
DIL|Dili|Timor-Leste|-8.55|125.58|2
DIU|Diu|India|20.71|70.98|2
DUB|Dublin|Ireland|53.35|-6.26|3
DBR|Dubrovnik|Croatia|42.64|18.11|3
ELM|Elmina|Ghana|5.08|-1.35|3
FAM|Famagusta|Cyprus|35.12|33.95|2
FEO|Feodosia|Ukraine|45.05|35.38|2
FUK|Fukuoka|Japan|33.59|130.4|3
FNC|Funchal|Portugal|32.65|-16.92|3
FUZ|Fuzhou|China|26.08|119.29|2
GAL|Galle|Sri Lanka|6.03|80.22|2
GDA|Gdansk|Poland|54.35|18.65|5
GOA|Genoa|Italy|44.41|8.93|5
GIB|Gibraltar|Gibraltar|36.14|-5.35|2
GOR|Goree|Senegal|14.67|-17.4|2
GUA|Guangzhou|China|23.13|113.26|5
HAG|Hagatna|Guam|13.48|144.75|2
HAM|Hamburg|Germany|53.55|10|5
HAN|Hanoi|Vietnam|21.02|105.84|2
HAV|Havana|Cuba|23.14|-82.36|5
HER|Heraklion|Greece|35.34|25.13|3
HIR|Hirado|Japan|33.37|129.55|3
HOI|Hoi An|Vietnam|15.88|108.33|3
HON|Hong Kong|Hong Kong|22.28|114.16|2
HNL|Honolulu|United States|21.3|-157.86|2
HOO|Hooghly|India|22.91|88.4|3
HRN|Hoorn|Netherlands|52.65|5.07|2
HOR|Hormuz|Iran|27.07|56.46|3
INC|Incheon|South Korea|37.46|126.65|3
IST|Istanbul|Turkey|41.01|28.96|5
IZM|Izmir|Turkey|38.41|27.14|3
JAF|Jaffna|Sri Lanka|9.66|80.02|2
JAK|Jakarta|Indonesia|-6.18|106.83|5
JAM|Jamestown|United States|37.21|-76.78|3
JED|Jeddah|Saudi Arabia|21.53|39.16|3
JEJ|Jeju|South Korea|33.51|126.52|2
KAG|Kagoshima|Japan|31.6|130.56|2
KAL|Kaliningrad|Russia|54.72|20.5|2
KAN|Kannur|India|11.87|75.36|2
KAR|Karachi|Pakistan|24.86|67.01|2
KHA|Khambhat|India|22.31|72.62|3
KIL|Kilwa|Tanzania|-8.98|39.52|2
KIN|Kingston upon Hull|United Kingdom|53.74|-0.33|2
KOC|Kochi|India|9.97|76.28|5
KOL|Kollam|India|8.89|76.59|2
KOZ|Kozhikode|India|11.25|75.78|5
KUP|Kupang|Indonesia|-10.16|123.58|2
LAR|La Rochelle|France|46.16|-1.15|3
LAG|Lagos|Nigeria|6.46|3.39|2
LPA|Las Palmas|Spain|28.13|-15.43|3
LEH|Le Havre|France|49.49|0.11|2
LEI|Leith|United Kingdom|55.98|-3.17|2
LIS|Lisbon|Portugal|38.71|-9.14|5
LIV|Livorno|Italy|43.55|10.32|3
LON|London|United Kingdom|51.51|-0.13|5
LNG|Longyearbyen|Norway|78.22|15.63|2
LUA|Luanda|Angola|-8.84|13.23|3
LUB|Lubeck|Germany|53.87|10.69|5
MAC|Macau|Macau|22.19|113.54|5
MCH|Machilipatnam|India|16.17|81.13|2
MAK|Makassar|Indonesia|-5.13|119.41|3
MAL|Malacca|Malaysia|2.19|102.25|5
MLG|Malaga|Spain|36.72|-4.42|3
MLN|Malindi|Kenya|-3.22|40.12|2
MAN|Manama|Bahrain|26.22|50.58|2
MNG|Mangaluru|India|12.87|74.84|2
MNL|Manila|Philippines|14.6|120.98|5
MRS|Marseille|France|43.3|5.38|5
MAS|Massawa|Eritrea|15.6|39.43|2
MES|Messina|Italy|38.19|15.55|2
MID|Middelburg|Netherlands|51.5|3.61|2
MOC|Mocha|Yemen|13.32|43.25|3
MOG|Mogadishu|Somalia|2.04|45.34|2
MOK|Mokpo|South Korea|34.79|126.39|2
MOM|Mombasa|Kenya|-4.05|39.67|3
ISL|Island of Mozambique|Mozambique|-15.04|40.73|3
MUM|Mumbai|India|19.08|72.88|3
MUS|Muscat|Oman|23.61|58.59|3
MYE|Myeik|Myanmar|12.44|98.6|2
NAG|Nagasaki|Japan|32.75|129.88|5
NAH|Naha|Japan|26.21|127.68|3
NAM|Nampo|North Korea|38.73|125.4|2
NAN|Nantes|France|47.22|-1.55|3
NAP|Naples|Italy|40.84|14.25|3
NEW|New York|United States|40.71|-74.01|3
NIN|Ningbo|China|29.88|121.55|3
NUU|Nuuk|Greenland|64.18|-51.73|2
OLD|Old Goa|India|15.5|73.91|5
ORA|Oran|Algeria|35.7|-0.63|2
OSA|Osaka|Japan|34.69|135.5|5
OUI|Ouidah|Benin|6.37|2.08|2
PAL|Palermo|Italy|38.12|13.36|3
PLM|Palma de Mallorca|Spain|39.57|2.65|2
PAN|Panama City|Panama|8.97|-79.53|3
PAR|Paramaribo|Suriname|5.87|-55.17|2
PAT|Patras|Greece|38.25|21.73|2
PTT|Pattani|Thailand|6.87|101.25|2
PLY|Plymouth|United Kingdom|50.37|-4.14|3
PON|Ponta Delgada|Portugal|37.74|-25.67|3
POR|Port Royal|Jamaica|17.94|-76.84|2
OPO|Porto|Portugal|41.15|-8.61|3
PRT|Portobelo|Panama|9.55|-79.65|3
PTH|Portsmouth|United Kingdom|50.81|-1.09|3
PUL|Pulicat|India|13.42|80.32|2
QUA|Quanzhou|China|24.91|118.59|3
QUE|Quebec City|Canada|46.82|-71.22|3
REC|Recife|Brazil|-8.05|-34.88|3
REY|Reykjavik|Iceland|64.15|-21.93|2
RHO|Rhodes|Greece|36.43|28.22|2
RIG|Riga|Latvia|56.95|24.11|3
RIO|Rio de Janeiro|Brazil|-22.91|-43.21|3
ROT|Rotterdam|Netherlands|51.92|4.48|3
SAF|Safi|Morocco|32.28|-9.23|2
SAI|Saint-Louis|Senegal|16.03|-16.5|2
SNT|Saint-Malo|France|48.65|-2.03|3
SAK|Sakai|Japan|34.57|135.48|3
SAL|Sale|Morocco|34.05|-6.82|2
SLV|Salvador|Brazil|-12.98|-38.49|5
SAN|San Juan|Puerto Rico|18.47|-66.12|2
SNL|Sanlucar de Barrameda|Spain|36.78|-6.35|2
SGO|Santo Domingo|Dominican Republic|18.46|-69.94|3
SOS|Santos|Brazil|-23.93|-46.33|2
SAO|Sao Tome|São Tomé and Principe|0.34|6.73|2
SET|Setubal|Portugal|38.52|-8.89|2
SVQ|Seville|Spain|37.39|-5.99|5
SHI|Shimonoseki|Japan|33.96|130.94|2
SOF|Sofala|Mozambique|-20.15|34.72|2
SOY|Soyo|Angola|-6.13|12.37|2
SPL|Split|Croatia|43.51|16.44|2
STA|St. Augustine|United States|29.89|-81.31|2
STG|St. George''s|Bermuda|32.38|-64.68|2
STJ|St. John''s|Canada|47.56|-52.71|3
STO|Stockholm|Sweden|59.33|18.07|3
SUA|Suakin|Sudan|19.1|37.33|2
SUE|Suez|Egypt|29.97|32.53|2
SUR|Surabaya|Indonesia|-7.25|112.74|2
SRT|Surat|India|21.21|72.84|5
SYD|Sydney|Australia|-33.87|151.21|2
TAI|Tainan|Taiwan|22.99|120.19|3
TAL|Tallinn|Estonia|59.44|24.75|3
TAN|Tangier|Morocco|35.77|-5.8|2
TER|Ternate|Indonesia|0.78|127.37|3
THA|Thanlyin|Myanmar|16.77|96.25|2
THE|Thessaloniki|Greece|40.64|22.94|3
TOK|Tokyo|Japan|35.69|139.69|5
TON|Tongyeong|South Korea|34.85|128.42|2
TOR|Torshavn|Faroe Islands|62.01|-6.77|2
TOU|Toulon|France|43.13|5.93|2
TRA|Trabzon|Turkey|41.01|39.72|2
TRI|Tripoli|Lebanon|34.44|35.83|2
TRP|Tripoli|Libya|32.89|13.19|2
TRO|Trondheim|Norway|63.44|10.4|2
TSU|Tsushima|Japan|34.2|129.29|2
TUN|Tunis|Tunisia|36.8|10.18|3
TUR|Turku|Finland|60.45|22.27|2
ULS|Ulsan|South Korea|35.55|129.32|2
VAL|Valencia|Spain|39.47|-0.38|3
VLL|Valletta|Malta|35.9|14.51|3
VLP|Valparaiso|Chile|-33.05|-71.62|2
VAR|Vardo|Norway|70.37|31.11|2
VEN|Venice|Italy|45.44|12.33|5
VER|Veracruz|Mexico|19.19|-96.15|5
VIS|Visby|Sweden|57.63|18.31|2
WIL|Willemstad|Curaçao|12.11|-68.93|2
XIA|Xiamen|China|24.48|118.08|3
YEO|Yeosu|South Korea|34.76|127.66|3
ZAN|Zanzibar|Tanzania|-6.17|39.2|3
`

/**
 * 0076 — WHERE EACH OF THOSE HARBOURS IS REACHED FROM: `code | roadstead lat | roadstead lon | nm`.
 *
 * The ROADSTEAD is the one point of open water a port is reached from, and it is a fact about the
 * RASTER rather than about the city — which is why it lives on `public.sea_reaches` and not in
 * `data/ports.json`, and why these three columns come from a different migration than the six
 * above. They are the `sea_reaches` VALUES block of
 * supabase/migrations/20260818000076_a_harbour_is_reached_from_its_roads.sql, reduced to the 214
 * harbours this fixture carries and to the three fields `world.snapshot()` serves.
 *
 * 159 of the 214 lie off the quay; the other 55 stand on sailable water
 * already and ARE their own roadstead at 0.00 nm, coordinate for coordinate (DESIGN_ROADSTEAD §2.4).
 * `nm` is never null — 0076 asserts that for all 238 places before anything relies on it, so there
 * is no null arm here and none in the client.
 */
const ROADSTEAD_ROWS = `
ACA|16.625|-99.875|14.14
ACC|5.375|-0.125|11.98
ADE|12.625|45.125|11.89
AGA|30.375|-9.875|15.51
ALE|31.375|29.625|17.18
ALG|36.78|3.06|0
AMB|-3.7|128.18|0
AMS|52.875|4.375|35.47
ANC|43.62|13.52|0
ANT|36.625|30.875|19.07
ARP|51.22|4.4|0
ARK|64.875|40.125|22.76
AYU|14.36|100.58|0
BAN|5.55|95.32|0
BND|-4.51|129.9|0
BAS|26.875|56.375|19.58
BNT|-5.875|106.125|10.12
BAR|41.125|2.125|15.51
BSR|30.375|47.875|9.33
BEI|34.125|35.375|15.63
BEL|-1.46|-48.5|0
BER|60.375|4.875|13.23
BIL|43.625|-2.875|22.05
BOR|44.84|-0.58|0
BOS|42.375|-70.625|19.32
BRI|13.1|-59.62|0
BRS|51.45|-2.6|0
BRU|51.375|3.125|10.53
BUE|-34.6|-58.38|0
BUS|35.125|129.375|15.33
CAD|36.375|-6.375|9.99
CAL|4.375|8.375|34.68
CLS|51.125|1.875|10.52
CLL|-12.125|-77.375|14.51
CAP|4.875|-1.125|15.44
CPT|-34.125|18.125|18.78
CAR|10.625|-75.625|13.53
CEB|10.375|124.125|14.24
CEU|35.89|-5.3|0
CHE|12.875|80.375|13.51
CHI|22.125|91.625|17.22
CID|14.92|-23.6|0
COL|6.875|79.625|14.39
COP|55.625|12.875|10.85
COR|39.62|19.92|0
CRK|51.625|-8.375|16.88
CUM|10.875|-64.125|25.65
DIL|-8.375|125.625|10.84
DIU|20.71|70.98|0
DUB|53.375|-5.875|13.88
DBR|42.625|17.875|10.42
ELM|4.875|-1.125|18.24
FAM|35.125|34.125|8.6
FEO|44.875|35.375|10.51
FUK|33.625|130.125|13.91
FNC|32.65|-16.92|0
FUZ|25.625|119.625|32.77
GAL|6.03|80.22|0
GDA|54.625|18.875|18.28
GOA|44.125|8.875|17.27
GIB|35.875|-5.375|15.96
GOR|14.625|-17.625|13.35
GUA|23.13|113.26|0
HAG|13.48|144.75|0
HAM|53.625|9.875|6.33
HAN|20.375|106.625|58.68
HAV|23.375|-82.375|14.13
HER|35.625|25.125|17.11
HIR|33.375|129.375|8.78
HOI|16.125|108.375|14.94
HON|22.125|114.125|9.51
HNL|21.125|-157.875|10.54
HOO|22.91|88.4|0
HRN|53.125|4.625|32.76
HOR|26.875|56.375|12.56
INC|37.125|126.375|24.02
IST|40.875|28.875|8.98
IZM|37.875|26.625|40.29
JAF|9.625|79.875|8.84
JAK|-5.875|106.875|18.51
JAM|37.125|-76.125|31.75
JED|21.625|38.875|16.9
JEJ|33.51|126.52|0
KAG|31.625|130.125|22.29
KAL|55.125|20.375|24.7
KAN|11.875|75.125|13.81
KAR|24.625|66.875|15.91
KHA|21.375|72.375|57.77
KIL|-8.98|39.52|0
KIN|53.875|0.125|18.05
KOC|9.875|76.125|10.8
KOL|8.875|76.375|12.79
KOZ|11.125|75.625|11.82
KUP|-10.375|123.625|13.18
LAR|46.125|-1.375|9.59
LAG|6.125|3.375|20.13
LPA|28.13|-15.43|0
LEH|49.625|-0.375|20.55
LEI|56.125|-2.625|20.24
LIS|38.625|-9.625|23.3
LIV|43.625|10.125|9.6
LON|51.375|-0.125|8.11
LNG|77.125|14.375|67.68
LUA|-8.625|12.875|24.71
LUB|54.125|11.125|21.68
MAC|22.19|113.54|0
MCH|16.125|81.375|14.39
MAK|-4.875|119.375|15.45
MAL|2.125|102.125|8.45
MLG|36.625|-4.125|15.31
MLN|-3.125|40.375|16.32
MAN|26.22|50.58|0
MNG|12.875|74.625|12.59
MNL|14.375|120.625|24.67
MRS|43.125|5.375|10.51
MAS|15.875|39.625|19.99
MES|38.375|15.375|13.83
MID|51.5|3.61|0
MOC|13.125|43.125|13.8
MOG|1.875|45.625|19.76
MOK|34.875|126.125|14.02
MOM|-4.125|39.875|13.08
ISL|-15.125|40.875|9.83
MUM|19.125|72.625|14.72
MUS|23.625|58.875|15.7
MYE|12.375|98.125|28.13
NAG|32.625|129.625|14.91
NAH|26.21|127.68|0
NAM|38.625|124.875|25.4
NAN|47.22|-1.55|0
NAP|40.625|14.125|14.11
NEW|40.625|-73.875|7.99
NIN|30.125|121.875|22.4
NUU|63.875|-52.125|21.05
OLD|15.625|73.625|18.11
ORA|35.875|-0.625|10.51
OSA|34.375|135.125|26.49
OUI|6.125|2.125|14.95
PAL|38.12|13.36|0
PLM|39.57|2.65|0
PAN|8.875|-79.375|10.82
PAR|6.125|-55.125|15.54
PAT|37.625|21.125|47.21
PTT|6.87|101.25|0
PLY|50.125|-4.125|14.72
PON|37.74|-25.67|0
POR|17.625|-76.875|19.02
OPO|41.125|-9.125|23.34
PRT|9.55|-79.65|0
PTH|50.625|-1.125|11.19
PUL|13.625|80.375|12.72
QUA|24.625|118.875|23.11
QUE|46.82|-71.22|0
REC|-8.125|-34.625|15.81
REY|64.375|-22.125|14.43
RHO|36.43|28.22|0
RIG|56.95|24.11|0
RIO|-23.125|-43.125|13.74
ROT|52.125|3.875|25.52
SAF|32.625|-9.375|21.98
SAI|16.125|-16.625|9.19
SNT|48.875|-2.125|14.02
SAK|34.375|135.125|21.11
SAL|34.125|-7.125|15.82
SLV|-13.125|-38.375|11
SAN|18.625|-66.125|9.31
SNL|36.78|-6.35|0
SGO|18.46|-69.94|0
SOS|-24.125|-46.375|11.97
SAO|0.34|6.73|0
SET|38.125|-9.125|26.17
SVQ|37.39|-5.99|0
SHI|34.125|130.625|18.54
SOF|-20.125|34.875|8.87
SOY|-6.125|12.125|14.63
SPL|43.375|16.125|15.95
STA|29.875|-81.125|9.67
STG|32.38|-64.68|0
STJ|47.625|-52.375|14.11
STO|59.375|18.375|9.72
SUA|19.375|37.375|16.71
SUE|29.97|32.53|0
SUR|-7.125|112.875|11
SRT|21.125|72.375|26.53
SYD|-34.125|151.375|17.37
TAI|22.875|119.875|18.74
TAL|59.44|24.75|0
TAN|35.77|-5.8|0
TER|0.875|127.125|15.78
THA|16.875|96.125|9.56
THE|40.125|22.875|31.06
TOK|35.125|140.375|47.69
TON|34.85|128.42|0
TOR|62.01|-6.77|0
TOU|43.13|5.93|0
TRA|41.01|39.72|0
TRI|34.375|35.625|10.88
TRP|32.875|13.375|9.37
TRO|64.125|9.625|45.98
TSU|34.2|129.29|0
TUN|36.875|10.375|10.4
TUR|60.375|22.125|6.23
ULS|35.625|129.625|15.56
VAL|39.375|0.125|24.11
VLL|35.9|14.51|0
VLP|-33.125|-71.875|13.59
VAR|70.37|31.11|0
VEN|45.375|12.625|13.03
VER|19.375|-96.125|11.2
VIS|57.63|18.31|0
WIL|12.11|-68.93|0
XIA|24.125|118.375|26.74
YEO|34.625|127.875|13.35
ZAN|-6.17|39.2|0
`

/** Every harbour's roads, by code. A missing code throws rather than serving a null. */
const ROADSTEAD_BY_CODE = new Map(
  ROADSTEAD_ROWS.trim()
    .split('\n')
    .map((line) => {
      const [code, lat, lon, nm] = line.split('|')
      return [code, { lat: Number(lat), lon: Number(lon), nm: Number(nm) }] as const
    }),
)

/** How many ports the seeded world has. A guard, not a decoration. */
export const REAL_PORT_COUNT = 214

/** The columns a chart never uses, filled with values that are legal but say nothing — a fixture
 *  must not smuggle in a market, a shipyard or a tax rate the map was never told about. */
const UNUSED = {
  nation: null,
  sea: 'Sea',
  region: 'REG',
  culture: 'latin',
  max_draft: 5,
  has_yard: false,
  yard_tier: 0,
  has_academy: false,
  is_ice_closed: false,
  tax_rate: 0.05,
  crew_pool: 200,
  dev_industry: 8,
  dev_commerce: 8,
  dev_military: 8,
  // 0067: it keeps NOTHING, for the reason this block already states — the map is never told what
  // a city keeps, so a fixture that handed it a market or a shipyard would be measuring a world
  // the map does not have.
  buildings: [],
  // 0036: the fixture is the HARBOUR table verbatim — the 14 sea places are deliberately absent
  // here (they are 0036's rows, proven by 0036's own asserts and the live snapshot), so every
  // density/label measurement below stays a measurement of the same 214 harbours it pinned.
  kind: 'HARBOUR',
  approach: null,
} as const

/** The roads of one harbour, or a loud throw — see ROADSTEAD_ROWS. */
function roadsteadOf(code: string): { lat: number; lon: number; nm: number } {
  const r = ROADSTEAD_BY_CODE.get(code)
  if (!r) throw new Error(`fixture: no roadstead for ${code}`)
  return r
}

/** The 214 ports of the seeded world, in `world.snapshot().ports` shape. */
export const REAL_PORTS: readonly SnapshotPort[] = PORT_ROWS.trim()
  .split('\n')
  .map((line) => {
    const [code, name, country, lat, lon, tier] = line.split('|')
    return {
      id: `port-${code}`,
      code,
      name,
      country,
      lat: Number(lat),
      lon: Number(lon),
      size_tier: Number(tier),
      // 0076: served beside `kind` and `approach`, never derived. A code with no roads is a
      // fixture that has drifted from the migration, and it throws instead of serving a null.
      roadstead: roadsteadOf(code),
      ...UNUSED,
    }
  })

/** Every port by code — the fixture's own lookup, used to place fleets on real coordinates. */
export const REAL_PORT_BY_CODE: ReadonlyMap<string, SnapshotPort> = new Map(
  REAL_PORTS.map((p) => [p.code, p]),
)

export function portAt(code: string): SnapshotPort {
  const port = REAL_PORT_BY_CODE.get(code)
  if (!port) throw new Error(`fixture: no port ${code}`)
  return port
}

/**
 * THE HOLD AND THE OFFICERS, added to every served fleet by 0017.
 *
 * Written ONCE and spread into both factories below. A map fixture has no opinion about cargo —
 * these fleets carry `ships: []` — so both fields take the value that is TRUE of an empty,
 * unofficered fleet rather than a plausible number a map spec might drift into asserting. The
 * whole point of `free_hold` being served (types.ts:274-284) is that the client stopped computing
 * it in three places; a fixture that invented a fourth answer would be the same defect wearing a
 * test's clothes.
 */
const EMPTY_HOLD_NO_OFFICERS = {
  free_hold: 0,
  officer_pct: { NAVIGATOR: 0, QUARTERMASTER: 0, SURGEON: 0, PURSER: 0 },
} satisfies Pick<FleetView, 'free_hold' | 'officer_pct'>

/** A fleet lying in a port. */
export function dockedFleet(id: string, name: string, portCode: string): FleetView {
  return {
    id,
    name,
    status: 'DOCKED',
    version: 1,
    port: portCode,
    anchor: null,
    busy_until: null,
    speed_kn: 5,
    endurance_days: 30,
    voyage: null,
    ships: [],
    queue: [],
    ...EMPTY_HOLD_NO_OFFICERS,
  }
}

/** A fleet holding a bare point of open water (0039). */
export function anchoredFleet(id: string, name: string, at: { lat: number; lon: number }): FleetView {
  return {
    id,
    name,
    status: 'ANCHORED',
    version: 1,
    port: null,
    anchor: [at.lat, at.lon],
    busy_until: null,
    speed_kn: 5,
    endurance_days: 30,
    voyage: null,
    ships: [],
    queue: [],
    ...EMPTY_HOLD_NO_OFFICERS,
  }
}

/**
 * A fleet at sea, placed THE WAY THE SERVER PLACES ONE (0039).
 *
 * The voyage carries its WHOLE COURSE — a polyline of port coordinates (`course`, port codes,
 * default [from, to]) — and `voyage.position()` interpolates linearly in lat/lon along the
 * segment `legIndex`, rounding to four decimals; this does exactly the same, so a spec asserting
 * "the chart draws the ship where the server put it" is comparing against the server's arithmetic
 * and not against a nicer one. The destination is the course's LAST point (a port code), or a
 * bare water point when `toPoint` is given.
 */
export function sailingFleet(args: {
  id: string
  name: string
  from: string
  to: string
  legFrac: number
  /** Port codes of the whole course, in order. Defaults to [from, to]. */
  course?: readonly string[]
  /** A bare open-water destination; the course then ends on this point (0039). */
  toPoint?: { lat: number; lon: number }
  sailedNm?: number
  totalNm?: number
  etaMs?: number
  legIndex?: number
  /** 0075: the length of the leg she is on, as `world.fleets` serves it. Omitted = a server
   *  predating 0075, which is a case the chart must survive by drawing her where she was put. */
  segNm?: number
  /** 0055: the seas her frozen course still has to cross, exactly as world.fleets serves them.
   *  Omitted = a server predating 0055, which is a case the chart must survive. */
  waters?: FleetVoyage['waters']
}): FleetView {
  const codes = args.course ?? [args.from, args.to]
  const points: [number, number][] = codes.map((c) => {
    const p = portAt(c)
    return [p.lat, p.lon]
  })
  if (args.toPoint) points.push([args.toPoint.lat, args.toPoint.lon])
  const segIndex = args.legIndex ?? 0
  const [aLat, aLon] = points[segIndex]
  const [bLat, bLon] = points[segIndex + 1]
  const round4 = (n: number) => Math.round(n * 10_000) / 10_000
  const totalNm = args.totalNm ?? 1000
  const nmDone = args.sailedNm ?? totalNm * args.legFrac
  return {
    id: args.id,
    name: args.name,
    status: 'SAILING',
    version: 1,
    port: null,
    anchor: null,
    busy_until: null,
    speed_kn: 5,
    endurance_days: 30,
    voyage: {
      id: `voyage-${args.id}`,
      to: args.toPoint ? null : (codes[codes.length - 1] ?? args.to),
      dest_point: args.toPoint ? [args.toPoint.lat, args.toPoint.lon] : null,
      course: points,
      eta: new Date(args.etaMs ?? 1_700_000_600_000).toISOString(),
      total_nm: totalNm,
      nm_done: nmDone,
      ...(args.waters ? { waters: args.waters } : {}),
      position: {
        seg_index: segIndex,
        leg_frac: args.legFrac,
        nm_done: nmDone,
        total_nm: totalNm,
        lat: round4(aLat + (bLat - aLat) * args.legFrac),
        lon: round4(aLon + (bLon - aLon) * args.legFrac),
        ...(args.segNm === undefined ? {} : { seg_nm: args.segNm }),
      },
    },
    ships: [],
    queue: [],
    ...EMPTY_HOLD_NO_OFFICERS,
  }
}
