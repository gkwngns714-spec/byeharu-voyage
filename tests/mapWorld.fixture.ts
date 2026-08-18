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

import type { FleetView, SnapshotLeg, SnapshotPort } from '../src/lib/rpc'

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
} as const

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

/** A sea lane, in `world.snapshot().legs` shape. `nm` is a SAILED distance and is deliberately not
 *  the great circle — nothing on this map may read a distance off the picture. */
export function leg(from: string, to: string, nm: number): SnapshotLeg {
  return { id: `leg-${from}-${to}`, from, to, nm, hazard_mult: 1, notes: null }
}

/** A fleet lying in a port. */
export function dockedFleet(id: string, name: string, portCode: string): FleetView {
  return {
    id,
    name,
    status: 'DOCKED',
    version: 1,
    port: portCode,
    busy_until: null,
    speed_kn: 5,
    endurance_days: 30,
    voyage: null,
    ships: [],
    queue: [],
  }
}

/**
 * A fleet at sea, placed THE WAY THE SERVER PLACES ONE.
 *
 * `voyage.position()` interpolates linearly in lat/lon along the current leg and rounds to four
 * decimals; this does exactly the same, so a spec asserting "the chart draws the ship where the
 * server put it" is comparing against the server's arithmetic and not against a nicer one.
 *
 * `destination` defaults to `to` — the fleet is on its last leg. Passing a different port is the
 * case the chart has to get right: the voyage carries on past this leg, so the map may RING that
 * port but may not draw a line to it, because the legs beyond the current one are not served.
 */
export function sailingFleet(args: {
  id: string
  name: string
  from: string
  to: string
  legFrac: number
  destination?: string
  sailedNm?: number
  totalNm?: number
  etaMs?: number
  legIndex?: number
}): FleetView {
  const a = portAt(args.from)
  const b = portAt(args.to)
  const round4 = (n: number) => Math.round(n * 10_000) / 10_000
  const totalNm = args.totalNm ?? 1000
  const nmDone = args.sailedNm ?? totalNm * args.legFrac
  return {
    id: args.id,
    name: args.name,
    status: 'SAILING',
    version: 1,
    port: null,
    busy_until: null,
    speed_kn: 5,
    endurance_days: 30,
    voyage: {
      id: `voyage-${args.id}`,
      to: args.destination ?? args.to,
      eta: new Date(args.etaMs ?? 1_700_000_600_000).toISOString(),
      total_nm: totalNm,
      nm_done: nmDone,
      position: {
        leg_index: args.legIndex ?? 0,
        from_code: args.from,
        to_code: args.to,
        leg_frac: args.legFrac,
        nm_done: nmDone,
        total_nm: totalNm,
        lat: round4(a.lat + (b.lat - a.lat) * args.legFrac),
        lon: round4(a.lon + (b.lon - a.lon) * args.legFrac),
      },
    },
    ships: [],
    queue: [],
  }
}
