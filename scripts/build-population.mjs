// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-population.mjs — the ONE authored table of every harbour's real-world population (migration 0304)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-04: "set population on cities, based on real life." This file is the authored source;
// running it writes data/port-population.json (what the world guard holds the database equal to) and prints
// the SQL VALUES block that migration 0304 seeds public.port_population from.
//
//   node scripts/build-population.mjs            # writes data/port-population.json
//   node scripts/build-population.mjs --sql      # also prints the VALUES rows for the migration
//
// THE FIGURES. The townspeople of the port itself (not its province or island), c. 1650 - the middle of the
// age the game depicts (data/ports.json: "~1500-1650"; the brief: 1600s-1700s). Rounded. Each row says how sure:
//   A  a count or a figure the standard histories agree on (within ~15 %)
//   B  a scholarly estimate; sources differ by up to a factor of ~1.5; the middle is taken
//   C  thin evidence: travellers' figures or a guess from the town's role; treat as an order of magnitude
//   L  not yet a town in 1650: the figure is the first credible one for the port, in the year given
//   N  no figure exists: taken from the nearest real analogue named in the note
// Written from general historical knowledge (Bairoch/Chandler-style city-size tables, national histories),
// not from a single database: the owner audits and corrects any row here, then re-runs this file.
import { writeFileSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { REPO_ROOT, deriveWorld } from './lib/world-derive.mjs'

// id | population | year | confidence | note
const ROWS = `
acapulco|4000|1650|B|galleon port; swelled several-fold during the Manila galleon fair
accra|5000|1650|C|Ga towns beside the European forts
aden|10000|1650|C|much shrunk since its medieval height
agadir|3000|1650|C|Santa Cruz do Cabo, a small Saadian port after the Portuguese left (1541)
alexandria|20000|1650|B|Ottoman Alexandria in decline (estimates 8,000-50,000)
algiers|80000|1650|B|the corsair capital at its height (estimates 60,000-100,000+)
ambon|6000|1650|C|Dutch Fort Victoria and town
amsterdam|175000|1650|A|
ancona|20000|1650|B|
angra-do-heroismo|10000|1650|B|the chief town of the Azores
antalya|10000|1650|C|
antwerp|65000|1650|A|down from 100,000 in 1560 after the Scheldt was closed
arica|2000|1650|C|silver port of Potosi
arkhangelsk|5000|1650|C|Russia's only sea port to the west
astoria|150|1813|L|Fort Astoria, founded 1811
auckland|3000|1845|L|founded 1840
ayutthaya|150000|1650|B|Siam's capital; estimates up to 200,000
banda-aceh|50000|1650|C|capital of the Aceh sultanate
banda-neira|3000|1650|C|Dutch perkenier settlement after the 1621 conquest
bandar-abbas|15000|1650|C|Gombroon, Persia's port after Hormuz fell (1622)
banten|70000|1650|C|the Banten sultanate's pepper port
barcelona|40000|1650|B|
barra-de-navidad|200|1650|C|the 1564 Legazpi departure port; little more than a landing by 1650
basra|40000|1650|C|Ottoman Basra
beirut|6000|1650|C|
belem|2000|1650|C|founded 1616
bergen|14000|1650|A|Norway's largest town
bilbao|10000|1650|B|
bordeaux|45000|1650|B|
boston|3000|1650|A|
bridgetown|3000|1650|C|the island of Barbados held ~40,000; its town far fewer
bristol|20000|1650|B|
bruges|30000|1650|B|
buenaventura|300|1650|C|a river landing, abandoned and refounded more than once
buenos-aires|4000|1650|B|
busan|15000|1650|C|Dongnae town and the Japan House (Waegwan)
cadiz|30000|1650|B|rising toward 40,000 by 1700
cagliari|20000|1650|B|
calabar|5000|1650|C|Efik towns of Old Calabar
calais|8000|1650|B|
callao|5000|1650|B|the port alone; Lima (~25,000) lies inland
cape-coast|3000|1650|C|
cape-town|1500|1700|L|founded 1652 by the VOC
cartagena|10000|1650|B|
cebu|3000|1650|C|Spanish town and its Parian
ceuta|4000|1650|C|a garrison town
chennai|20000|1650|C|Madras, founded 1639; ~40,000 by the 1670s
chios|15000|1650|C|the town; the island held more
chittagong|20000|1650|C|the Arakanese port
cidade-velha|2000|1650|C|Ribeira Grande, in decline
colombo|8000|1650|C|Portuguese Colombo before the Dutch siege (1656)
concepcion|2000|1650|C|at Penco
copenhagen|30000|1650|A|
coquimbo|1000|1650|C|La Serena and its anchorage
corfu|12000|1650|C|the Venetian town; the island held more
cork|6000|1650|B|
cumana|2000|1650|C|
darwin|500|1871|L|founded 1869 as Palmerston
dili|1000|1650|N|a small Timorese coastal settlement; analogue: Kupang
diu|10000|1650|C|Portuguese Diu
dublin|20000|1650|B|after the 1650 plague; ~45,000 by 1680
dubrovnik|6000|1650|B|the city; the republic held ~30,000
el-realejo|1000|1650|C|
elmina|12000|1650|C|the town beside the castle
famagusta|2000|1650|C|much reduced under the Ottomans
feodosia|40000|1650|C|Ottoman Kefe; travellers' figures run far higher
fremantle|500|1832|L|founded 1829
fukuoka|40000|1650|C|Hakata and the Fukuoka castle town together
funchal|10000|1650|B|
fuzhou|200000|1650|C|Fujian's provincial capital; estimates vary widely
galle|5000|1650|C|
gdansk|70000|1650|A|
genoa|75000|1650|B|before the 1656 plague
gibraltar|4000|1650|B|the Spanish town before 1704
goree|500|1650|C|
guangzhou|400000|1650|C|late-Ming Canton; sacked by the Qing in 1650
guayaquil|5000|1650|C|
hadibu|500|1650|N|the chief village of Socotra; analogue: other Arabian Sea island towns
hagatna|1000|1670|L|the Spanish mission town, founded 1668
hamburg|75000|1650|A|
hanoi|100000|1650|C|Thang Long (Ke Cho); European visitors' estimates
havana|15000|1650|B|~26,000 by 1700
heraklion|20000|1650|B|Venetian Candia, under siege 1648-1669
hirado|5000|1650|C|in decline after the Dutch left for Dejima (1641)
hobart|1000|1810|L|founded 1804
hoi-an|8000|1650|C|Japanese and Chinese merchant quarters
hong-kong|7000|1841|L|the British count of the island, 1841; only villages before
honolulu|6000|1823|L|the Hawaiian town at the first missionary estimates
hooghly|30000|1650|C|the Mughal port that replaced the Portuguese town (1632)
hoorn|15000|1650|A|
hormuz|40000|1600|B|before its fall (1622); deserted by 1650, so the 1600 figure is used
huatulco|300|1650|C|raided by Drake (1579) and Cavendish (1587)
incheon|5000|1650|N|Joseon Incheon-bu; analogue: other Joseon county towns
istanbul|700000|1650|B|estimates 600,000-750,000
izmir|80000|1650|B|the Levant's rising entrepot
jaffna|10000|1650|C|
jakarta|30000|1650|B|Batavia within and around the walls
jamestown|500|1650|B|the Virginia colony held ~15,000; the town a few hundred
jeddah|10000|1650|C|
jeju|10000|1650|C|Jeju town; the island held more
kagoshima|50000|1650|C|the Satsuma castle town
kaliningrad|40000|1650|B|Konigsberg
kannur|10000|1650|C|
karachi|10000|1800|L|founded c. 1729
khambhat|50000|1650|C|Cambay, silting and declining
kilwa|4000|1650|C|long past its height
kingston-upon-hull|7000|1650|B|
kochi|20000|1650|C|Portuguese Cochin and Mattancherry, before the Dutch (1663)
kollam|10000|1650|C|
kozhikode|50000|1650|C|the Zamorin's city
kupang|1000|1650|C|
la-rochelle|15000|1650|C|recovering after the 1628 siege
lagos-ng|5000|1650|C|Eko, a Benin outpost
las-palmas|8000|1650|C|
le-havre|15000|1650|C|
leith|5000|1650|C|the port alone; Edinburgh (~30,000) lies inland
lisbon|150000|1650|B|
livorno|20000|1650|B|
london|400000|1650|A|
longyearbyen|200|1650|N|no town until 1906; analogue: the summer whaling station at Smeerenburg
luanda|6000|1650|C|
lubeck|30000|1650|B|
macau|30000|1650|C|after the Japan trade was lost (1639); ~40,000 at its height
machilipatnam|40000|1650|C|Golconda's great port
makassar|100000|1650|C|Gowa-Tallo before the Dutch conquest (1669)
malacca|5000|1678|A|the Dutch census of 1678; ~20,000 under the Portuguese before 1641
malaga|25000|1650|B|after the 1649 plague
male|2000|1650|C|
malindi|3000|1650|C|in decline after the Portuguese moved to Mombasa (1593)
manama|2000|1650|C|
mangaluru|10000|1650|C|
manila|40000|1650|B|Intramuros with the Chinese Parian
marseille|65000|1650|B|
massawa|2000|1650|C|
matsumae|10000|1650|C|the Matsumae castle town
mazatlan|3000|1830|L|a fishing village until the port opened in the 1820s
messina|80000|1650|C|before the 1674 revolt; figures run 60,000-120,000
mezen|1000|1650|C|
middelburg|25000|1650|B|
mocha|10000|1650|C|the coffee port, rising
mogadishu|5000|1650|C|
mokpo|1000|1650|N|a Joseon naval post; analogue: Yeosu's naval town, smaller
mombasa|8000|1650|C|under Fort Jesus
monterey|500|1790|L|founded 1770
mozambique-island|3000|1650|C|
mumbai|10000|1661|B|when ceded to England (1661)
muscat|8000|1650|C|retaken from the Portuguese in 1650
myeik|5000|1650|C|Mergui
nagasaki|40000|1650|B|25,000 in 1616, 64,500 by the 1696 count
naha|10000|1650|C|the port below Shuri
nampo|2000|1650|N|no town of the name until 1900s; analogue: Joseon river-mouth towns below Pyongyang
nantes|40000|1650|B|
naples|300000|1650|B|before the 1656 plague killed about half
new-york|1000|1650|A|New Amsterdam
ningbo|150000|1650|C|
nuuk|300|1730|L|Godthab, founded 1728
old-goa|40000|1650|C|~75,000 in 1600, ~20,000 by 1695
oran|5000|1650|C|a Spanish presidio
osaka|300000|1650|B|
ouidah|10000|1650|C|before the slave-trade boom of the 1670s
paita|500|1650|C|
palermo|110000|1650|B|
palma|25000|1650|B|
panama-city|8000|1650|B|old Panama, before the 1671 sack
paramaribo|1000|1680|L|English settlement 1650, Dutch from 1667
patras|8000|1650|C|
pattani|20000|1650|C|
plymouth|8000|1650|B|
ponta-delgada|8000|1650|C|
port-louis|3000|1740|L|founded 1735
port-royal|6500|1680|L|English from 1655; the 1680 figure
portland-maine|500|1680|L|Falmouth settlement
porto|20000|1650|B|
portobelo|1000|1650|B|the permanent town; thousands more at the fair
portsmouth|5000|1650|B|
pulicat|5000|1650|C|Dutch Fort Geldria
pustozersk|500|1650|C|
quanzhou|100000|1650|C|long past its Song height
quebec-city|500|1666|A|the 1666 census of the town (547)
recife|8000|1650|B|Dutch Mauritsstad and Recife
reykjavik|200|1786|L|a farm until the 1786 trading charter
rhodes|10000|1650|C|
riga|25000|1650|B|
rio-de-janeiro|4000|1650|C|
rotterdam|30000|1650|B|
safi|5000|1650|C|
saint-louis|1000|1700|L|founded 1659
saint-malo|15000|1650|C|
sakai|60000|1650|C|
sale|15000|1650|C|the corsair republic of Sale and Rabat
salvador|12000|1650|C|the capital of Brazil
san-diego|500|1800|L|founded 1769
san-francisco|500|1847|L|Yerba Buena, just before the gold rush
san-juan|3000|1650|C|
sanlucar|15000|1650|C|
santa-cruz-de-tenerife|2000|1650|C|La Laguna was the island's capital
santo-domingo|5000|1650|C|
santos|1000|1650|C|
sao-tome|3000|1650|C|
setubal|10000|1650|C|
seville|120000|1646|B|before the 1649 plague killed about half
shimonoseki|10000|1650|C|Akamagaseki
sofala|1000|1650|C|
soyo|5000|1650|C|Mbanza Soyo
split|5000|1650|C|
st-augustine|1000|1650|B|
st-georges-bermuda|1000|1650|C|
st-johns-nl|500|1680|C|the winter residents
stockholm|40000|1650|B|
suakin|5000|1650|C|
suez|2000|1650|C|
surabaya|10000|1650|C|after its conquest by Mataram (1625)
surat|100000|1650|B|the Mughal empire's chief port; ~200,000 by 1700
sydney|2500|1800|L|founded 1788
tainan|10000|1650|C|Dutch Zeelandia and Saccam with the Chinese settlers
tallinn|10000|1650|B|
tangier|5000|1650|C|
ternate|8000|1650|C|
thanlyin|10000|1650|C|Syriam
thessaloniki|40000|1650|B|
tidore|5000|1650|C|
tokyo|500000|1650|B|Edo; ~1,000,000 by 1720
tongyeong|5000|1650|C|the Joseon naval headquarters town
torshavn|300|1650|C|
toulon|20000|1650|C|
trabzon|15000|1650|C|
tripoli-lb|20000|1650|C|
tripoli-ly|15000|1650|C|
trondheim|6000|1650|B|
tsushima|10000|1650|C|Fuchu, the So clan's castle town
tunis|80000|1650|C|
turku|5000|1650|B|
ulsan|5000|1650|C|
valencia|50000|1650|B|
valletta|20000|1650|B|the harbour towns together
valparaiso|500|1650|C|
vardo|300|1650|C|
venice|140000|1650|A|after the 1630 plague
veracruz|5000|1650|C|
visby|3000|1650|C|
wellington|3000|1842|L|founded 1840
willemstad|2000|1650|C|
xiamen|50000|1650|C|Koxinga's base in the 1650s
yeosu|5000|1650|C|the Jeolla left naval base
zakynthos|15000|1650|C|the Venetian town
zanzibar|5000|1650|C|
`

export function populationRows() {
  return ROWS.trim().split('\n').map((line) => {
    const [id, pop, year, confidence, note] = line.split('|')
    return { id, population: Number(pop), year: Number(year), confidence, note: note ?? '' }
  })
}

const isMain = process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('scripts/build-population.mjs')
if (isMain) {
  const ports = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'ports.json'), 'utf8')).ports
  const world = deriveWorld()
  const codeOf = new Map(world.ports.map((p) => [p.id, p.code]))
  const rows = populationRows()
  const ids = new Set(rows.map((r) => r.id))
  const missing = ports.filter((p) => !ids.has(p.id)).map((p) => p.id)
  const extra = rows.filter((r) => !ports.some((p) => p.id === r.id)).map((r) => r.id)
  if (missing.length || extra.length || ids.size !== rows.length) {
    throw new Error(`population table does not match data/ports.json: missing ${missing}, extra ${extra}, rows ${rows.length}, unique ${ids.size}`)
  }
  for (const r of rows) {
    if (!(r.population > 0) || !Number.isInteger(r.population)) throw new Error(`${r.id}: population ${r.population}`)
    if (!'ABCLN'.includes(r.confidence) || r.confidence.length !== 1) throw new Error(`${r.id}: confidence ${r.confidence}`)
    if (!codeOf.get(r.id)) throw new Error(`${r.id}: no code`)
  }
  const out = {
    $doc: '../docs/dev-log/2026-11-04-city-population.md',
    note: 'Each harbour\'s real-world population c. 1650, the starting value and baseline of public.port_population (migration 0304). AUTHORED in scripts/build-population.mjs; the world guard holds the database equal to this file. confidence: A count/agreed, B scholarly estimate, C thin evidence, L later founding (year given), N analogue (named in note).',
    count: rows.length,
    ports: rows.map((r) => ({ code: codeOf.get(r.id), ...r })),
  }
  writeFileSync(join(REPO_ROOT, 'data', 'port-population.json'), JSON.stringify(out, null, 2) + '\n')
  console.log(`wrote data/port-population.json: ${rows.length} harbours, total ${rows.reduce((a, r) => a + r.population, 0)}`)
  if (process.argv.includes('--sql')) {
    const q = (s) => `'${String(s).replace(/'/g, "''")}'`
    console.log(out.ports.map((r) => `  (${q(r.code)}, ${r.population}, ${r.year}, ${q(r.confidence)}, ${q(r.note)})`).join(',\n'))
  }
}
