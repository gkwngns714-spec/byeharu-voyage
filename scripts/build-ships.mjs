// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-ships.mjs — WAVES A + B: the 67 T1 hulls of docs/SHIPS_AND_SKILLS.md §4.3, generated
//                   (S12 Wave A, 52 hulls, 0135; S14 Wave B, 15 capitals and flagships, 0138)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE METHOD (§4.2): ONE archetype table (size × role — the Portuguese values) × ONE line table
// (data/ship-lines.json `mult` / `add`, the eleven lines of §3.1). Every hull = archetype × line,
// rounded the one way written below. A designer moves a number in ONE place and every hull of that
// size, role or line moves with it. The ANCHORS hold the method honest: the Portuguese small trade,
// light explorer and medium trade archetypes ARE the live barca, caravela latina and nau, and this
// file refuses to run unless all three come out of the archetype table to the digit (stats from
// 0003:2089-2091 + data/ship_stats.json, deck from data/ship-lines.json, racks from data/gear.json,
// labour, goods and yard tier from data/hulls.json).
//
// THE ROUNDING (measured against every one of the 52 rows of §4.3, not chosen): hold to 5 tons from
// 50 up and to the ton below it; speed to 0.1 knot; crew to the man; hull and attack to 10; labour to
// 500. Every rounding is HALF TO EVEN (banker's) on the binary product — the same arithmetic the
// table was drafted with: 5.0 kn × 1.05 = 5.25 → 5.2 (the crayer), 90 × 1.35 = 121.5 → 122 (the
// galea sottile). Additive stats: handling, armour, reach and sighting take the line's `add`;
// accuracy takes it only where the archetype has any (a hull with no guns aims nothing); draft is
// clamped to 1-6; attack 0 stays 0. `guns` = attack / 10 for every hull (0074's data rule).
//
// WHAT A HULL IS BUILT FROM (§4.2): the size's template with the line's own goods substituted
// (Dutch Memel fir and Stockholm tar, Indian teak / coir / coco fibre, Chinese abaca, Japanese and
// Korean iron for nails, French canvas duck, Italian hemp, Ottoman cedar); a heavy hull is the
// medium template × 1.4. Goods only — the table names no fittings for the new hulls (the live three
// keep their data/hulls.json recipes, fittings included). Yard labour = the archetype's base × the
// line's labour factor × `hull_labour_mult` (a knob, 1.0 — applied by the server, never here).
//
// WHAT IT NEEDS (§4.4): small — the line's Small Hulls I; light — Small III + Light I; medium —
// Light III + Medium I; heavy — Medium IV + Heavy I + the role skill I; capital (S14) — Heavy IV +
// Capital Hulls I + Command III + the role skill III; flagship (S14) — Capital Hulls V + Fleet
// Command I + the role skill V. Read only by public.requirements_unmet (0133, re-cut by 0135).
//
// IT FITS IN THE SHED (0072 (d), §8 S14 — never loosened): a hull's goods come out of ONE warehouse
// in the yard's city, and the biggest shed in the world holds SHED_TUNS. A capital's size template
// (medium × 2) fits; a flagship's (medium × 3) does not. So where a hull's goods exceed the shed,
// every quantity is scaled down to fit (floored, the template's proportions kept) and the value of
// what was taken out — each good at the middle of its baseValue band, data/goods.json, the "≈ market"
// of §4.2 — moves into the yard's labour (rounded UP to 500, so the all-in price never falls). The
// hull costs what it cost; more of it is paid to the yard and less is carried to the shed.
//
// WAVE (`wave` on each row): A = 0135's 52, B = 0138's 15. `--sql A` / `--sql B` print the VALUES
// of one wave — the rows that wave's migration pasted.
//
// RUN:   node scripts/build-ships.mjs           writes data/ships.generated.json
//        node scripts/build-ships.mjs --check   fails if the file is not what the generator gives
// scripts/db/world-guard.mjs re-runs generateShips() on every apply and holds the database to it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const readJson = (rel) => JSON.parse(readFileSync(join(ROOT, rel), 'utf8'))
export const SHIPS_FILE = 'data/ships.generated.json'

/** Round half to even on the binary value (Python's `round`) — see THE ROUNDING above. */
export function roundHalfEven(x) {
  const f = Math.floor(x)
  const d = x - f
  if (d > 0.5) return f + 1
  if (d < 0.5) return f
  return f % 2 === 0 ? f : f + 1
}
const roundTo = (x, step) => Number((roundHalfEven(x / step) * step).toFixed(4))

/** The hull-skill word of a size — a flagship is trained under Capital Hulls (§4.1: "(Capital Hulls V)"). */
export const SIZE_WORD = { 1: 'Small', 2: 'Light', 3: 'Medium', 4: 'Heavy', 5: 'Capital', 6: 'Capital' }
const SIZE_YARD_TIER = { 1: 1, 2: 2, 3: 3, 4: 3, 5: 3, 6: 3 }             // §4.1
const SIZE_CABINS = { 1: 3, 2: 4, 3: 5, 4: 6, 5: 7, 6: 8 }                // the live barca 3 / carlat 4 / nau 5 (0074), +1 a size
const SIZE_BUILD_HOURS = { 1: 24, 2: 40, 3: 96, 4: 144, 5: 240, 6: 360 } // build_hours: read by no rule (statGloss.ts:32)
/** THE BIGGEST SHED IN THE WORLD, in tuns: a tier-5 warehouse × warehouse_tuns_per_tier 150 (0070; every
 *  tier-3 build yard's city has one — measured 2026-10-17, 14 of 14). 0138's self-assert holds every hull's
 *  goods to the REAL storage of a yard where it can be built, so a wrong number here cannot ship. */
export const SHED_TUNS = 750
const ROLE_SKILL = { trade: 'MERCHANT_SHIPS', combat: 'SHIPS_OF_WAR', explorer: 'EXPLORERS', support: 'ESCORT_SUPPORT' }

/** THE ARCHETYPES (size/role) — the Portuguese values; Wave A uses these twelve. `racks` = High / Mid /
 *  Low / Refit (+ 1 Flourish from medium up). `labour` is the base yard labour in ducats. */
export const ARCHETYPES = {
  '1/trade':    { hold: 60,  speed: 5.0, crewReq: 8,   crewMax: 20,  hull: 400,  draft: 1, handling: 70, armour: 5,  attack: 0,   accuracy: 0,  reach: 20, sighting: 8,  deck: 12, racks: [1, 2, 0, 0], labour: 3000 },
  '1/explorer': { hold: 35,  speed: 6.4, crewReq: 6,   crewMax: 16,  hull: 300,  draft: 1, handling: 86, armour: 4,  attack: 0,   accuracy: 0,  reach: 20, sighting: 10, deck: 11, racks: [1, 3, 0, 0], labour: 2400 },
  '1/combat':   { hold: 30,  speed: 6.2, crewReq: 14,  crewMax: 40,  hull: 350,  draft: 1, handling: 84, armour: 6,  attack: 20,  accuracy: 30, reach: 30, sighting: 9,  deck: 15, racks: [2, 2, 0, 0], labour: 3500 },
  '1/support':  { hold: 45,  speed: 5.8, crewReq: 10,  crewMax: 30,  hull: 380,  draft: 1, handling: 80, armour: 6,  attack: 10,  accuracy: 20, reach: 25, sighting: 10, deck: 14, racks: [1, 2, 1, 0], labour: 3000 },
  '2/trade':    { hold: 130, speed: 5.4, crewReq: 14,  crewMax: 34,  hull: 600,  draft: 2, handling: 68, armour: 12, attack: 20,  accuracy: 30, reach: 40, sighting: 10, deck: 22, racks: [1, 3, 1, 1], labour: 7000 },
  '2/explorer': { hold: 90,  speed: 6.0, crewReq: 12,  crewMax: 30,  hull: 550,  draft: 1, handling: 75, armour: 12, attack: 20,  accuracy: 40, reach: 45, sighting: 10, deck: 22, racks: [2, 3, 0, 1], labour: 7000 },
  '2/combat':   { hold: 70,  speed: 6.6, crewReq: 28,  crewMax: 90,  hull: 480,  draft: 1, handling: 88, armour: 8,  attack: 50,  accuracy: 38, reach: 30, sighting: 11, deck: 28, racks: [2, 4, 0, 1], labour: 8000 },
  '2/support':  { hold: 100, speed: 5.8, crewReq: 20,  crewMax: 60,  hull: 650,  draft: 2, handling: 72, armour: 14, attack: 30,  accuracy: 40, reach: 50, sighting: 11, deck: 28, racks: [2, 3, 1, 1], labour: 9000 },
  '3/trade':    { hold: 400, speed: 4.4, crewReq: 60,  crewMax: 140, hull: 1800, draft: 3, handling: 45, armour: 30, attack: 120, accuracy: 55, reach: 70, sighting: 14, deck: 56, racks: [3, 5, 1, 2], labour: 30000 },
  '3/combat':   { hold: 300, speed: 4.8, crewReq: 90,  crewMax: 220, hull: 2000, draft: 3, handling: 50, armour: 34, attack: 170, accuracy: 58, reach: 72, sighting: 14, deck: 62, racks: [4, 5, 1, 2], labour: 34000 },
  '4/trade':    { hold: 600, speed: 4.4, crewReq: 80,  crewMax: 200, hull: 2400, draft: 4, handling: 40, armour: 32, attack: 110, accuracy: 50, reach: 65, sighting: 13, deck: 72, racks: [3, 6, 2, 2], labour: 48000 },
  '4/combat':   { hold: 420, speed: 4.6, crewReq: 130, crewMax: 320, hull: 2800, draft: 4, handling: 42, armour: 40, attack: 240, accuracy: 60, reach: 78, sighting: 14, deck: 82, racks: [5, 5, 2, 2], labour: 55000 },
  // Wave B (S14, 0138) — the capital and flagship archetypes, solved from §4.3's Wave B table (every row
  // reproduces from these × its line, checked column by column; the PRT nau da carreira and carraca
  // grande ARE the capital and flagship trade archetypes).
  '5/trade':    { hold: 900,  speed: 4.2, crewReq: 120, crewMax: 300, hull: 3400, draft: 5, handling: 35, armour: 38, attack: 160, accuracy: 50, reach: 65, sighting: 13, deck: 100, racks: [3, 7, 3, 3], labour: 80000 },
  '5/combat':   { hold: 600,  speed: 4.3, crewReq: 200, crewMax: 480, hull: 4000, draft: 5, handling: 36, armour: 48, attack: 340, accuracy: 62, reach: 82, sighting: 14, deck: 115, racks: [6, 6, 2, 3], labour: 95000 },
  '6/trade':    { hold: 1500, speed: 3.9, crewReq: 200, crewMax: 500, hull: 5000, draft: 5, handling: 30, armour: 42, attack: 220, accuracy: 50, reach: 65, sighting: 13, deck: 138, racks: [4, 7, 4, 3], labour: 150000 },
  '6/combat':   { hold: 800,  speed: 4.0, crewReq: 320, crewMax: 750, hull: 5600, draft: 5, handling: 32, armour: 55, attack: 480, accuracy: 64, reach: 85, sighting: 15, deck: 150, racks: [7, 6, 2, 3], labour: 170000 },
}

/** Each line's yard-labour factor (what its yards charge against Lisbon's) and its goods substitutions. */
export const LINE_YARDS = {
  PRT: { labour: 1.00, family: 'Western',       subs: {} },
  ESP: { labour: 1.10, family: 'Western',       subs: {} },
  NLD: { labour: 0.85, family: 'Western',       subs: { tar: 'stockholm-tar', 'naval-timber': 'memel-fir', 'live-oak': 'timber' } },
  ENG: { labour: 1.05, family: 'Western',       subs: { 'live-oak': 'timber' } },
  FRA: { labour: 1.05, family: 'Western',       subs: { cordage: 'canvas-duck', 'live-oak': 'timber' } },
  ITA: { labour: 1.10, family: 'Mediterranean', subs: { cordage: 'hemp', 'live-oak': 'timber' } },
  OTT: { labour: 1.00, family: 'Mediterranean', subs: { 'naval-timber': 'cedar', 'live-oak': 'timber' } },
  IND: { labour: 0.85, family: 'Indian Ocean',  subs: { timber: 'teak', 'naval-timber': 'teak', 'live-oak': 'teak', tar: 'coir', cordage: 'coir', 'ships-nails': 'coco-fibre' } },
  CHN: { labour: 0.90, family: 'East Asian',    subs: { 'naval-timber': 'timber', 'live-oak': 'timber', cordage: 'abaca' } },
  JPN: { labour: 1.00, family: 'East Asian',    subs: { 'naval-timber': 'timber', 'live-oak': 'timber', 'ships-nails': 'iron' } },
  KOR: { labour: 1.00, family: 'East Asian',    subs: { 'naval-timber': 'timber', 'live-oak': 'timber', 'ships-nails': 'iron' } },
}

/** The size templates (the live barca / carlat / nau goods); heavy = medium × 1.4, capital × 2, flagship
 *  × 3 (§4.3 Wave B) — before the shed (a flagship's × 3 does not fit; see IT FITS IN THE SHED). */
const TEMPLATES = {
  1: [['timber', 40], ['tar', 8], ['cordage', 6], ['ships-nails', 10]],
  2: [['timber', 70], ['naval-timber', 20], ['tar', 12], ['cordage', 10], ['ships-nails', 18]],
  3: [['live-oak', 90], ['naval-timber', 40], ['timber', 60], ['tar', 25], ['ships-nails', 40]],
}
TEMPLATES[4] = TEMPLATES[3].map(([g, q]) => [g, Math.round(q * 1.4)])
TEMPLATES[5] = TEMPLATES[3].map(([g, q]) => [g, q * 2])
TEMPLATES[6] = TEMPLATES[3].map(([g, q]) => [g, q * 3])

/** THE 52 (§4.3 Wave A): code, name, line, size, role, rig, and the one sentence the build yard prints. */
export const WAVE_A = [
  ['carred',   'Caravela redonda',    'PRT', 2, 'combat',   'mixed',  'The caravel re-rigged square for the open ocean and given a gun deck. Quick, handy and hard to catch.'],
  ['galeao',   'Galeão',              'PRT', 4, 'combat',   'square', 'The Portuguese war galleon of the Indies run: a fighting deck on a hull that can still carry a cargo.'],
  ['patache',  'Patache',             'ESP', 1, 'support',  'mixed',  'A small dispatch and escort vessel that runs messages and keeps a convoy together.'],
  ['carabela', 'Carabela de Indias',  'ESP', 2, 'trade',    'mixed',  'The caravel of the Indies trade, built higher and wider to carry more across the Atlantic.'],
  ['zabra',    'Zabra',               'ESP', 2, 'combat',   'square', 'A fast Biscay escort, heavily manned for its size.'],
  ['urca',     'Urca',                'ESP', 3, 'trade',    'square', 'A round-bellied supply ship of the treasure fleets, slow and very roomy.'],
  ['galeon',   'Galeón',              'ESP', 4, 'combat',   'square', 'The Spanish galleon: high-sided, heavily armed and crowded with soldiers.'],
  ['jacht',    'Jacht',               'NLD', 1, 'explorer', 'mixed',  'A light, fast Dutch boat for scouting and carrying news, with a tiny crew.'],
  ['buss',     'Haringbuis',          'NLD', 2, 'trade',    'square', 'The Dutch herring buss: a working hull with a lot of cargo space and few hands.'],
  ['fluyt',    'Fluit',               'NLD', 3, 'trade',    'square', 'The Dutch fluit: huge cargo space, a small crew and shallow draft. The cheapest cargo afloat.'],
  ['pinas',    'Pinas',               'NLD', 3, 'combat',   'square', 'A Dutch armed merchant and warship, faster and better gunned than a fluit.'],
  ['retour',   'Retourschip',         'NLD', 4, 'trade',    'square', 'The Dutch East India return ship, built to bring a fortune home from Asia.'],
  ['pinnace',  'Pinnace',             'ENG', 1, 'explorer', 'mixed',  'A small English scout and tender, the fastest small hull afloat.'],
  ['crayer',   'Crayer',              'ENG', 1, 'trade',    'square', 'An English coastal trader that works the short sea routes.'],
  ['bark',     'Bark',                'ENG', 2, 'support',  'mixed',  'A sturdy English bark that supports a squadron and can stand some punishment.'],
  ['levanter', 'Levant Merchantman',  'ENG', 3, 'trade',    'square', 'An English merchant built to trade into the Mediterranean and fight its way home.'],
  ['racegal',  'Race-built Galleon',  'ENG', 4, 'combat',   'square', 'The low, race-built English galleon: fast, handy, and it shoots straight and far.'],
  ['barque',   'Barque',              'FRA', 1, 'trade',    'mixed',  'A small French coastal trader, quick and easy to handle.'],
  ['carnorm',  'Caravelle normande',  'FRA', 2, 'explorer', 'lateen', 'The Norman caravel of the Dieppe navigators, light and weatherly.'],
  ['navire',   'Navire marchand',     'FRA', 3, 'trade',    'square', 'A French ocean merchant, an all-round hull with a good turn of speed.'],
  ['galere',   'Galère',              'FRA', 3, 'combat',   'oared',  'A French war galley from Marseille: oars and sail, crowded with rowers and soldiers.'],
  ['galion',   'Galion',              'FRA', 4, 'combat',   'square', 'The French galleon: elegant, quick and well armed.'],
  ['fusta',    'Fusta',               'ITA', 1, 'combat',   'oared',  'A light galley for raiding and coast patrol, packed with oarsmen.'],
  ['marcil',   'Marciliana',          'ITA', 2, 'trade',    'square', 'A Venetian round ship of the Adriatic trade.'],
  ['galsott',  'Galea sottile',       'ITA', 2, 'combat',   'oared',  'The light war galley of Venice and Genoa: nimble, crowded and short-ranged.'],
  ['galgros',  'Galea grossa',        'ITA', 3, 'trade',    'oared',  'The Venetian great galley: an oared merchant for the richest cargoes.'],
  ['caracca',  'Caracca genovese',    'ITA', 4, 'trade',    'square', 'The Genoese carrack, a high-castled bulk carrier of the Mediterranean.'],
  ['kayik',    'Kayık',               'OTT', 1, 'trade',    'lateen', 'A small Ottoman coaster of the Aegean and the Black Sea.'],
  ['xebec',    'Şebek (xebec)',       'OTT', 2, 'combat',   'lateen', 'A fast lateen raider with oars to spare, at home in light Mediterranean winds.'],
  ['karamur',  'Karamürsel',          'OTT', 3, 'trade',    'lateen', 'The Ottoman cargo ship of the Sea of Marmara and the Levant.'],
  ['kadirga',  'Kadırga',             'OTT', 3, 'combat',   'oared',  'The Ottoman war galley of the Arsenal, built for boarding.'],
  ['bastarda', 'Baştarda',            'OTT', 4, 'combat',   'oared',  'The heavy Ottoman galley that carries an admiral and a crowd of soldiers.'],
  ['dhow',     'Dhow',                'IND', 1, 'trade',    'lateen', 'The sewn teak trader of the monsoon coasts.'],
  ['sambuk',   'Sambuk',              'IND', 1, 'explorer', 'lateen', 'A fast Arabian sambuk for pearling, pilotage and scouting.'],
  ['ghurab',   'Ghurab',              'IND', 2, 'combat',   'lateen', 'The fast Malabar raider, sweet-handling and lightly gunned.'],
  ['baghlah',  'Baghlah',             'IND', 3, 'trade',    'lateen', 'The deep-sea dhow of the Gulf and the Indian Ocean, with a carved high stern.'],
  ['jahaz',    'Gujarati Jahaz',      'IND', 4, 'trade',    'mixed',  'The great Gujarati ship that carries the pilgrim and spice trade to the Red Sea.'],
  ['niao',     'Niaochuan',           'CHN', 1, 'explorer', 'lateen', 'The Fujian bird boat, a small fast scout.'],
  ['shachuan', 'Shachuan',            'CHN', 2, 'trade',    'lateen', 'The flat-bottomed sand boat of the northern Chinese coast.'],
  ['cangshan', 'Cangshan',            'CHN', 2, 'combat',   'lateen', 'A Ming coastal patrol ship.'],
  ['junk',     'Junk (Fuzhou trader)', 'CHN', 3, 'trade',   'lateen', 'The bulkheaded Fuzhou junk: roomy, very hard to sink, and slow to turn.'],
  ['fuchuan',  'Fuchuan',             'CHN', 4, 'combat',   'lateen', 'The great Fujian warship of the Ming navy, a tall fighting junk.'],
  ['kobaya',   'Kobaya',              'JPN', 1, 'combat',   'oared',  'The small, fast Japanese war boat that closes in for the fight.'],
  ['kobune',   'Kobune',              'JPN', 1, 'trade',    'square', 'A small Japanese coastal freighter.'],
  ['sekibune', 'Sekibune',            'JPN', 2, 'combat',   'oared',  'The Japanese medium war boat: fast oars and well-trained gunners.'],
  ['shuinsen', 'Shuinsen',            'JPN', 3, 'trade',    'square', 'A red-seal ship licensed to trade across East and Southeast Asia.'],
  ['ataka',    'Atakebune',           'JPN', 4, 'combat',   'oared',  'The Japanese floating fortress, boxed in with a castle of timber.'],
  ['hyeop',    'Hyeopseon',           'KOR', 1, 'explorer', 'oared',  'A small Joseon scout that sails ahead of the fleet.'],
  ['sangseon', 'Sangseon',            'KOR', 2, 'trade',    'lateen', 'A Joseon merchant ship of the coastal trade.'],
  ['byeong',   'Byeongseon',          'KOR', 2, 'combat',   'oared',  'A Joseon fighting boat, well armoured for its size.'],
  ['joun',     'Jounseon',            'KOR', 3, 'trade',    'lateen', 'The Joseon grain carrier of the tax routes.'],
  ['panok',    'Panokseon',           'KOR', 4, 'combat',   'oared',  'The Joseon battleship with a raised, plated upper deck: the best armour afloat.'],
]

/** THE 15 (§4.3 Wave B, S14, 0138): eleven capitals (one per line) and four flagships (the four great
 *  naval powers, PRT ESP ENG OTT). Same columns as WAVE_A. */
export const WAVE_B = [
  ['naucarr',   'Nau da Carreira',     'PRT', 5, 'trade',  'square', 'The great Portuguese carrack of the India run, built to carry a year of pepper home round the Cape.'],
  ['carraca',   'Carraca grande',      'PRT', 6, 'trade',  'square', 'The largest carrack afloat: a floating warehouse with castles fore and aft, slow and enormous.'],
  ['galmanila', 'Galeón de Manila',    'ESP', 5, 'trade',  'square', 'The Manila galleon that crossed the Pacific once a year with silks and porcelain for Acapulco.'],
  ['galreal',   'Galeón real',         'ESP', 6, 'combat', 'square', 'The royal galleon that leads a Spanish fleet: three gun decks, a crowd of soldiers and an admiral.'],
  ['spiegel',   'Spiegelretourschip',  'NLD', 5, 'trade',  'square', 'The great Dutch East India ship with the flat painted stern, the biggest hold of any capital.'],
  ['indiaman',  'East Indiaman',       'ENG', 5, 'trade',  'square', 'The English company ship to the Indies: a merchant built and gunned like a man-of-war.'],
  ['greatship', 'Great Ship',          'ENG', 6, 'combat', 'square', 'The English great ship of the royal navy, the heaviest broadside of its line.'],
  ['grandnav',  'Grand navire',        'FRA', 5, 'combat', 'square', 'The French great ship of war, quick for its size and well armed.'],
  ['galeazza',  'Galeazza',            'ITA', 5, 'combat', 'oared',  'The Venetian galleass: a galley grown into a gun platform, with guns all round and oars to turn it.'],
  ['kalyon',    'Kalyon',              'OTT', 5, 'combat', 'square', 'The Ottoman sailing galleon of the Arsenal, high-sided and full of soldiers.'],
  ['bashum',    'Baştarda-i Hümayun',  'OTT', 6, 'combat', 'oared',  'The imperial galley of the Kapudan Pasha, the largest oared ship on the sea.'],
  ['hajji',     'Hajji Jahaz',         'IND', 5, 'trade',  'mixed',  'The great pilgrim ship of Surat that carries pilgrims and cargo to the Red Sea.'],
  ['dachuan',   'Dachuan (great junk)', 'CHN', 5, 'trade', 'lateen', 'The great ocean junk of the southern ports, with watertight bulkheads and an enormous hold.'],
  ['oataka',    'Ō-atakebune',         'JPN', 5, 'combat', 'oared',  'The great Japanese floating fortress, a castle of timber on a rowed hull.'],
  ['daepanok',  'Dae-panokseon',       'KOR', 5, 'combat', 'oared',  'The great Joseon battleship, its raised upper deck plated against boarders.'],
]

/** The live three, as 0003:2089-2091 + data/ship_stats.json rate them — the anchors. */
const LIVE_ANCHORS = {
  barca:  { key: '1/trade',    hold: 60,  speed: 5.0, crewReq: 8,  crewMax: 20,  hull: 400,  draft: 1, guns: 0 },
  carlat: { key: '2/explorer', hold: 90,  speed: 6.0, crewReq: 12, crewMax: 30,  hull: 550,  draft: 1, guns: 2 },
  nau:    { key: '3/trade',    hold: 400, speed: 4.4, crewReq: 60, crewMax: 140, hull: 1800, draft: 3, guns: 12 },
}

const RACKS = ['high', 'mid', 'low', 'refit']

/** One hull = archetype × line. Pure. */
function hullOf(archetype, line, size) {
  const a = archetype
  const m = line.mult
  const d = line.add
  const hold = a.hold * m.hold
  return {
    hold: roundTo(hold, hold >= 50 ? 5 : 1),
    speedKn: roundTo(a.speed * m.speed, 0.1),
    crewRequired: roundHalfEven(a.crewReq * m.crew),
    crewMax: roundHalfEven(a.crewMax * m.crew),
    durability: roundTo(a.hull * m.hull, 10),
    draft: Math.min(6, Math.max(1, a.draft + d.draft)),
    handling: Math.min(100, Math.max(0, a.handling + d.handling)),
    armour: Math.min(100, Math.max(0, a.armour + d.armour)),
    attack: a.attack === 0 ? 0 : roundTo(a.attack * m.attack, 10),
    accuracy: a.accuracy === 0 ? 0 : Math.min(100, Math.max(0, a.accuracy + d.accuracy)),
    reach: Math.min(100, Math.max(0, a.reach + d.reach)),
    sighting: a.sighting + d.sighting,
    deck: a.deck,
    racks: { ...Object.fromEntries(RACKS.map((r, i) => [r, a.racks[i]])), flourish: size >= 3 ? 1 : 0 },
  }
}

/** The size template with the line's goods substituted (merged, first appearance first). */
function goodsOf(size, subs) {
  const out = new Map()
  for (const [g, q] of TEMPLATES[size]) {
    const s = subs[g] ?? g
    out.set(s, (out.get(s) ?? 0) + q)
  }
  return [...out].map(([g, qty]) => ({ in: g, qty }))
}

/** IT FITS IN THE SHED: the goods scaled to SHED_TUNS where they exceed it, and the value taken out. */
function shedFit(goodsList, bulk, mid) {
  const tonsOf = (list) => list.reduce((t, g) => t + g.qty * bulk.get(g.in), 0)
  const tons = tonsOf(goodsList)
  if (tons <= SHED_TUNS + 1e-9) return { goods: goodsList, moved: 0, tons: Number(tons.toFixed(3)) }
  const f = SHED_TUNS / tons
  const capped = goodsList.map((g) => ({ in: g.in, qty: Math.floor(g.qty * f) }))
  const moved = goodsList.reduce((v, g, i) => v + (g.qty - capped[i].qty) * mid.get(g.in), 0)
  const after = tonsOf(capped)
  if (after > SHED_TUNS + 1e-9) throw new Error(`shed: capped goods are ${after} t, over ${SHED_TUNS}`)
  return { goods: capped, moved: Math.ceil(moved / 500) * 500, tons: Number(after.toFixed(3)) }
}

function requirementsOf(line, size, role) {
  const sk = (s) => `${line}_${SIZE_WORD[s].toUpperCase()}`
  if (size === 1) return [{ skill: sk(1), level: 1 }]
  if (size === 2) return [{ skill: sk(1), level: 3 }, { skill: sk(2), level: 1 }]
  if (size === 3) return [{ skill: sk(2), level: 3 }, { skill: sk(3), level: 1 }]
  if (size === 4) return [{ skill: sk(3), level: 4 }, { skill: sk(4), level: 1 }, { skill: ROLE_SKILL[role], level: 1 }]
  if (size === 5) return [{ skill: sk(4), level: 4 }, { skill: sk(5), level: 1 }, { skill: 'COMMAND', level: 3 }, { skill: ROLE_SKILL[role], level: 3 }]
  return [{ skill: sk(6), level: 5 }, { skill: 'FLEET_COMMAND', level: 1 }, { skill: ROLE_SKILL[role], level: 5 }]
}

/** THE GENERATOR. Pure but for reading data/*.json; throws on any broken rule. */
export function generateShips() {
  const lines = Object.fromEntries(readJson('data/ship-lines.json').lines.map((l) => [l.code, l]))
  const goodsRows = readJson('data/goods.json').goods
  const goods = new Set(goodsRows.map((g) => g.id))
  const bulk = new Map(goodsRows.map((g) => [g.id, g.bulk]))
  const mid = new Map(goodsRows.map((g) => [g.id, (g.baseValue[0] + g.baseValue[1]) / 2]))
  const skills = new Set(readJson('data/skills.json').skills.map((s) => s.code))
  const liveHulls = Object.fromEntries(readJson('data/hulls.json').hulls.map((h) => [h.class, h]))
  const liveProfiles = Object.fromEntries(readJson('data/ship-lines.json').profiles.map((p) => [p.class, p]))
  const liveRacks = Object.fromEntries(readJson('data/gear.json').classes.map((c) => [c.class, c]))
  const liveStats = Object.fromEntries(readJson('data/ship_stats.json').classes.map((c) => [c.class, c]))

  // ── THE ANCHORS: the Portuguese archetypes ARE the live three, to the digit ──────────────────
  for (const [code, live] of Object.entries(LIVE_ANCHORS)) {
    const [size] = live.key.split('/').map(Number)
    const a = ARCHETYPES[live.key]
    const h = hullOf(a, lines.PRT, size)
    const want = {
      hold: live.hold, speedKn: live.speed, crewRequired: live.crewReq, crewMax: live.crewMax, durability: live.hull,
      draft: live.draft, handling: liveStats[code].handling, armour: liveStats[code].armour, attack: liveStats[code].attack,
      accuracy: liveStats[code].accuracy, reach: liveStats[code].reach, sighting: liveStats[code].sighting,
      deck: liveProfiles[code].deck, racks: Object.fromEntries([...RACKS, 'flourish'].map((r) => [r, liveRacks[code][r]])),
    }
    for (const [k, v] of Object.entries(want)) {
      if (JSON.stringify(h[k]) !== JSON.stringify(v)) throw new Error(`LIVE ANCHOR ${code}.${k}: the archetype gives ${JSON.stringify(h[k])}, the live hull is ${JSON.stringify(v)}`)
    }
    if (h.attack / 10 !== live.guns) throw new Error(`LIVE ANCHOR ${code}: guns ${live.guns} is not attack / 10`)
    if (roundTo(a.labour * LINE_YARDS.PRT.labour, 500) !== liveHulls[code].ducats) throw new Error(`LIVE ANCHOR ${code}: labour`)
    if (SIZE_YARD_TIER[size] !== liveHulls[code].yard_tier) throw new Error(`LIVE ANCHOR ${code}: yard tier`)
    const g = goodsOf(size, LINE_YARDS.PRT.subs).map((x) => `${x.in}:${x.qty}`).sort().join(',')
    const lg = liveHulls[code].goods.map((x) => `${x.in}:${x.qty}`).sort().join(',')
    if (g !== lg) throw new Error(`LIVE ANCHOR ${code}: goods ${g} vs ${lg}`)
  }

  const seen = new Set(Object.keys(LIVE_ANCHORS))
  const waves = [...WAVE_A.map((h) => ['A', ...h]), ...WAVE_B.map((h) => ['B', ...h])]
  const hulls = waves.map(([wave, code, name, lineCode, size, role, rig, note]) => {
    const key = `${size}/${role}`
    const a = ARCHETYPES[key]
    const line = lines[lineCode]
    const yard = LINE_YARDS[lineCode]
    if (!a) throw new Error(`${code}: no archetype ${key}`)
    if (!line || !yard) throw new Error(`${code}: no line ${lineCode}`)
    if (seen.has(code)) throw new Error(`${code}: a second hull of that code`)
    seen.add(code)
    if (!['square', 'lateen', 'mixed', 'oared'].includes(rig)) throw new Error(`${code}: rig ${rig}`)
    if (note.length <= 12) throw new Error(`${code}: the note is too short for hull_recipes`)
    const h = hullOf(a, line, size)
    const shed = shedFit(goodsOf(size, yard.subs), bulk, mid)
    const goodsList = shed.goods
    const ducats = roundTo(a.labour * yard.labour, 500) + shed.moved
    for (const g of goodsList) if (!goods.has(g.in)) throw new Error(`${code}: good ${g.in} is not in data/goods.json`)
    const requirements = requirementsOf(lineCode, size, role)
    for (const r of requirements) if (!skills.has(r.skill)) throw new Error(`${code}: skill ${r.skill} is not in data/skills.json`)
    return {
      wave, class: code, name, line: lineCode, size, role, tech: 'T1', anyYard: false,
      family: yard.family, rig, tier: Math.min(size, 5),
      hold: h.hold, crewRequired: h.crewRequired, crewMax: h.crewMax, speedKn: h.speedKn, durability: h.durability,
      guns: h.attack / 10, draft: h.draft, buildHours: SIZE_BUILD_HOURS[size], buildCost: ducats * 4,
      handling: h.handling, armour: h.armour, attack: h.attack, accuracy: h.accuracy, reach: h.reach, sighting: h.sighting,
      deck: h.deck, hands: h.crewMax - Math.ceil(h.crewRequired / 2), racks: h.racks, cabins: SIZE_CABINS[size],
      yardTier: SIZE_YARD_TIER[size], ducats, shedLabour: shed.moved, tons: shed.tons, note, goods: goodsList, requirements,
    }
  })
  const nA = hulls.filter((h) => h.wave === 'A').length
  const nB = hulls.filter((h) => h.wave === 'B').length
  if (nA !== 52) throw new Error(`Wave A is 52 hulls; the list has ${nA}`)
  if (nB !== 15) throw new Error(`Wave B is 15 hulls; the list has ${nB}`)
  for (const h of hulls) if (h.tons > SHED_TUNS) throw new Error(`${h.class}: ${h.tons} t does not fit the shed`)
  return { _: 'GENERATED by scripts/build-ships.mjs — do not edit; edit the generator and re-run it (docs/SHIPS_AND_SKILLS.md §4.2; S12 Wave A, migration 0135; S14 Wave B, migration 0138).', hulls }
}

const q = (s) => `'${String(s).replace(/'/g, "''")}'`

/** The SQL VALUES a wave's migration loads (`--sql A` → 0135, `--sql B` → 0138): pasted into the file verbatim, and the world guard holds
 *  the database to generateShips() on every apply, so the file and the generator cannot drift apart. */
export function shipsSql(gen = generateShips(), wave = 'A') {
  const H = gen.hulls.filter((h) => h.wave === wave)
  const rows = (list) => list.join(',\n')
  return [
    `-- ship_classes (${H.length})`,
    rows(H.map((h) => `  (${q(h.class)}, ${q(h.name)}, ${q(h.family)}, ${q(h.rig)}, ${h.hold}, ${h.crewRequired}, ${h.crewMax}, ${h.speedKn.toFixed(2)}, ${h.durability}, ${h.guns}, ${h.draft}, ${h.buildHours.toFixed(2)}, ${h.buildCost.toFixed(2)}, ${h.tier}, ${h.handling}, ${h.armour}, ${h.attack}, ${h.accuracy}, ${h.reach}, ${h.sighting.toFixed(1)})`)),
    `-- class_profile (${H.length})`,
    rows(H.map((h) => `  (${q(h.class)}, ${q(h.line)}, ${h.size}, ${q(h.role)}, ${q(h.tech)}, ${h.deck}, ${h.anyYard})`)),
    '-- class_slots by rack',
    rows(H.flatMap((h) => Object.entries(h.racks).filter(([, n]) => n > 0).map(([r, n]) => `  (${q(h.class)}, ${q(r)}, ${n})`))),
    `-- class_cabins (${H.length})`,
    rows(H.map((h) => `  (${q(h.class)}, ${h.cabins})`)),
    `-- hull_recipes (${H.length})`,
    rows(H.map((h) => `  (${q(h.class)}, ${h.yardTier}, ${h.ducats}, ${q(h.note)})`)),
    '-- hull_recipe_goods (by good code)',
    rows(H.flatMap((h) => h.goods.map((g) => `  (${q(h.class)}, ${q(g.in)}, ${g.qty})`))),
    '-- skill_requirements (hull)',
    rows(H.flatMap((h) => h.requirements.map((r) => `  ('hull', ${q(h.class)}, ${q(r.skill)}, ${r.level})`))),
  ].join('\n')
}

if (process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('scripts/build-ships.mjs')) {
  const text = JSON.stringify(generateShips(), null, 1) + '\n'
  if (process.argv.includes('--sql')) {
    console.log(shipsSql(undefined, process.argv[process.argv.indexOf('--sql') + 1] === 'B' ? 'B' : 'A'))
  } else if (process.argv.includes('--check')) {
    const now = readFileSync(join(ROOT, SHIPS_FILE), 'utf8')
    if (now !== text) { console.error(`${SHIPS_FILE} is NOT what scripts/build-ships.mjs generates — re-run it.`); process.exit(1) }
    console.log(`${SHIPS_FILE} equals the generator (67 hulls: Wave A 52, Wave B 15).`)
  } else {
    writeFileSync(join(ROOT, SHIPS_FILE), text)
    console.log(`wrote ${SHIPS_FILE}: LIVE ANCHORS OK, 67 hulls (Wave A 52, Wave B 15)`)
  }
}
