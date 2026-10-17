// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-ships.mjs — WAVES A + B + C + D: the 100 hulls of docs/SHIPS_AND_SKILLS.md §4.3, generated
//                   (S12 Wave A, 52 T1 hulls, 0135; S14 Wave B, 15 T1 capitals and flagships, 0138;
//                    S15 Wave C, 22 T2 hulls, 0159; S17 Wave D, 11 famous ships, 0166)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE METHOD (§4.2): ONE archetype table (size × role — the Portuguese values) × ONE line table
// (data/ship-lines.json `mult` / `add`, the eleven lines of §3.1) × ONE tech uplift (TECH below).
// Every hull = archetype × line × tech, rounded the one way written below. A designer moves a number
// in ONE place and every hull of that size, role, line or tech moves with it. The ANCHORS hold the
// method honest: the Portuguese small trade,
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
// Light III + Medium I; heavy — Medium III + Heavy I + the role skill I; capital (S14) — Heavy III +
// Capital Hulls I + Command III + the role skill III; flagship (S14) — Capital Hulls V + Fleet
// Command I + the role skill V; T2 (S15, any size) — the line's ⟨size⟩ Hulls V + the role's T2
// specialisation I. Read only by public.requirements_unmet (0133, re-cut by 0135). K1 (D2,
// docs/SKILLS_AND_CAPTAINS.md §3.2): heavy and capital asked Medium / Heavy IV until then; EVE's 2013 rule.
//
// T2 (S15 Wave C, §4.1): the archetype's (size, role) hull with ONE uplift keyed by role (TECH.T2 below),
// applied INSIDE the products before the one rounding — hull × 1.1 × line, attack × 1.25 × line, speed
// × 1.06 × line: trade +15 % hold, +10 % hull, +4 armour, +1 Low; combat +25 % attack, +10 % hull,
// +6 armour, +4 accuracy, +1 High; explorer +6 % speed, +6 handling, +3 sighting, +1 Mid; support
// +20 % hull, +1 Low. Common to every T2: deck + (the added rack's deck × size: High and Low 3 a size,
// Mid 1), labour × 2.5 (inside the product, one rounding to 500 — the ESP light combat is 8,000 × 2.5
// × 1.10 = 22,000, not 9,000 × 2.5), goods = the size template × 1.6 (each line rounded, then the line's
// substitutions merged — the IND small is teak 64, coir 13 + 10 = 23, coco-fibre 16) + copper sheet
// 10, +3 a size from heavy (13). Measured against the 22 rows of §4.3 Wave C; the cells the rows and the
// rule disagree on are listed in the S15 PR, not special-cased here.
//
// FAMOUS (S17 Wave D, §4.1 "famous (F)", one per house): the archetype's (size, role) hull with ONE uplift
// keyed by role (TECH.F below), measured against the 11 rows of §4.3 Wave D the same way: every famous hull
// is 3 % faster (speed × 1.03 inside the product); trade hold × 1.25, hull × 1.15, attack × 1.10, handling +2,
// armour +6, sighting +1, +1 Low; combat attack × 1.40, hull × 1.20, handling +4, armour +10, accuracy +8,
// sighting +1, +1 High; explorer speed × 1.06 more, hull × 1.10, handling +10, armour +2, accuracy +4,
// sighting +5, +1 Mid. Deck: T2's one rule (+ the added rack's deck × size). Labour × 4; goods = the size
// template × 2.2 with lignum vitae (9 a medium template, × the template's size factor) and sea charts 2
// (§4.1 "lignum vitae + sea charts"); then THE SHED. Its FITTING is its famous gear — one piece, made at a
// tier-3 workshop (scripts/build-gear.mjs FAMOUS, which names the hull: the one home of the link), spent from
// the yard city's store when she is laid down (0072's hull_recipe_items; §8 S17). Needs the line's ⟨size⟩
// Hulls V + Famous Ships I + the role's T2 specialisation III (§4.4); ONE OF EACH TO A HOUSE is
// public.famous_held, read by cmd.do_build and world.building_yard (0166). The heavy EXPLORER archetype is
// solved from the San Juan Bautista row (no T1 hull is built from it). Cells of the drafted table the rule
// does not give are listed in the S17 PR and under the table in §4.3, not special-cased here.
//
// MERCHANTS OF EVERY FLAG (S18, 0167, §8 row S18): THE ONE RULE of which hull a merchant company sails in
// place of a live class (barca, caravela latina, nau — the roster's classes, which ARE the Portuguese line).
// For each live class and each other line: that line's T1 hull whose cargo space is within MERCHANT.hold
// (± 10 %) and whose speed is within MERCHANT.speed (± 5 %) of the live class's, that needs NO MORE crew
// than she does and holds AT LEAST as many (so every merchant's crew sails on, unchanged, and her wages with
// it), and whose every rack and Deck hold at least hers (so every pattern of her gear still fits); the
// nearest by |Δ cargo| / cargo + |Δ speed| / speed, then code. None qualifies: the merchant keeps the live
// class (a truthful lesser answer, not a fallback to a different thing). The rows (`merchant`) are loaded
// into public.npc_line_hulls and read by public.npc_hull_for (founding, conversion) and npc_fit_loadout (a
// line hull wears the patterns of the live class she stands in for). The crew condition is the brief's
// "wages within ± 10 %" made exact — NOT in §8's row: confirm.
//
// IT FITS IN THE SHED (0072 (d), §8 S14 — never loosened): a hull's goods come out of ONE warehouse
// in the yard's city, and the biggest shed in the world holds SHED_TUNS. A capital's size template
// (medium × 2) fits; a flagship's (medium × 3) does not. So where a hull's goods exceed the shed,
// every quantity is scaled down to fit (floored but never below 1 — a famous hull's 2 sea charts — the template's proportions kept) and the value of
// what was taken out — each good at the middle of its baseValue band, data/goods.json, the "≈ market"
// of §4.2 — moves into the yard's labour (rounded UP to 500, so the all-in price never falls). The
// hull costs what it cost; more of it is paid to the yard and less is carried to the shed.
//
// WAVE (`wave` on each row): A = 0135's 52, B = 0138's 15, C = 0159's 22, D = 0166's 11. `--sql A` /
// `--sql B` / `--sql C` / `--sql D` print the VALUES of one wave — the rows that wave's migration pasted.
//
// RUN:   node scripts/build-ships.mjs           writes data/ships.generated.json
//        node scripts/build-ships.mjs --sql-merchant   the VALUES 0167 loads (public.npc_line_hulls)
//        node scripts/build-ships.mjs --check   fails if the file is not what the generator gives
// scripts/db/world-guard.mjs re-runs generateShips() on every apply and holds the database to it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { FAMOUS } from './build-gear.mjs'

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
/** The role's T2 specialisation (§4.4 "T2 (any size)"). */
const ROLE_T2_SKILL = { trade: 'ARMED_MERCHANT', combat: 'PRIVATEERS', explorer: 'SURVEY_SHIPS', support: 'CONVOY_ESCORTS' }

/** THE TECH UPLIFT — one row per tech, keyed by role inside (§4.1's tech table, measured against §4.3
 *  Wave C). `mult` goes into the product before the one rounding; `add` is added after the line's; `rack`
 *  is the one rack that gains a slot and `rackDeck` the deck that slot brings per size. T1 is the identity. */
const NO_UPLIFT = { mult: {}, add: {}, rack: null, rackDeck: 0 }
/** A medium template's lignum vitae for a famous hull (§4.1), and each size's template factor (TEMPLATES below). */
const FAMOUS_LIGNUM = 9
const TEMPLATE_FACTOR = { 1: 1, 2: 1, 3: 1, 4: 1.4, 5: 2, 6: 3 }
const FAMOUS_SPEED = 1.03
/** `extra(size)` = the goods the tech adds to the template AFTER its factor (copper sheet, sea charts) and
 *  `scaled(size)` = goods it adds BEFORE it (a famous hull's lignum vitae rides with the template). */
export const TECH = {
  T1: { labour: 1, goods: 1, scaled: () => [], extra: () => [], role: { trade: NO_UPLIFT, combat: NO_UPLIFT, explorer: NO_UPLIFT, support: NO_UPLIFT } },
  T2: {
    labour: 2.5, goods: 1.6, scaled: () => [], extra: (size) => [['copper-sheet', 10 + 3 * Math.max(0, size - 3)]],
    role: {
      trade:    { mult: { hold: 1.15, hull: 1.10 },  add: { armour: 4 },                         rack: 'low',  rackDeck: 3 },
      combat:   { mult: { attack: 1.25, hull: 1.10 }, add: { armour: 6, accuracy: 4 },           rack: 'high', rackDeck: 3 },
      explorer: { mult: { speed: 1.06 },             add: { handling: 6, sighting: 3 },          rack: 'mid',  rackDeck: 1 },
      support:  { mult: { hull: 1.20 },              add: {},                                    rack: 'low',  rackDeck: 3 },
    },
  },
  // S17 (§4.1 famous, measured against §4.3 Wave D). No famous ship is a support hull.
  F: {
    labour: 4, goods: 2.2, scaled: (size) => [['lignum-vitae', FAMOUS_LIGNUM * TEMPLATE_FACTOR[size]]], extra: () => [['sea-charts', 2]],
    role: {
      trade:    { mult: { hold: 1.25, hull: 1.15, attack: 1.10, speed: FAMOUS_SPEED }, add: { handling: 2, armour: 6, sighting: 1 },               rack: 'low',  rackDeck: 3 },
      combat:   { mult: { attack: 1.40, hull: 1.20, speed: FAMOUS_SPEED },             add: { handling: 4, armour: 10, accuracy: 8, sighting: 1 }, rack: 'high', rackDeck: 3 },
      explorer: { mult: { speed: FAMOUS_SPEED * 1.06, hull: 1.10 },                    add: { handling: 10, armour: 2, accuracy: 4, sighting: 5 }, rack: 'mid',  rackDeck: 1 },
    },
  },
}

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
  // Wave C (S15, 0159) — the medium and heavy SUPPORT archetypes, solved from §4.3's Wave C table through
  // TECH.T2 (the PRT nau de guerra IS the medium support archetype × the T2 uplift; the OTT mavna ÷ its line
  // gives the heavy one: 455 / 0.95 → 480, 4.4 / 0.98 → 4.5, 125 / 1.25 → 100, 3,560 / 1.2 / 1.1 → 2,700,
  // 180 / 1.15 → 160, deck 89 − 12, racks 4/6/3/2 − the T2 Low). No T1 hull is built from them yet.
  '3/support':  { hold: 280,  speed: 4.8, crewReq: 70,  crewMax: 180, hull: 1700, draft: 3, handling: 52, armour: 34, attack: 100, accuracy: 55, reach: 60, sighting: 14, deck: 57,  racks: [3, 5, 2, 2], labour: 30000 },
  '4/support':  { hold: 480,  speed: 4.5, crewReq: 100, crewMax: 260, hull: 2700, draft: 4, handling: 44, armour: 44, attack: 160, accuracy: 60, reach: 70, sighting: 14, deck: 77,  racks: [4, 6, 2, 2], labour: 52000 },
  // Wave D (S17, 0166) — the heavy EXPLORER archetype, solved from §4.3's San Juan Bautista row through the
  // JPN line and TECH.F (360 / 0.9 → 400, 5.5 / 1.0918 → 5.0, 80 / 1.15 → 70, 207 / 1.15 → 180, 2,300 / 0.95
  // / 1.1 → 2,200, handling 64 − 4 − 10, armour 32 − 2 − 2, attack 110 / 1.1, accuracy 60 − 6 − 4, reach 57 + 8,
  // sighting 23 − 1 − 5, deck 78 − 4, racks 2/8/2/2 − the famous Mid, labour 184,000 / 4). No T1 hull is built from it.
  '4/explorer': { hold: 400,  speed: 5.0, crewReq: 70,  crewMax: 180, hull: 2200, draft: 3, handling: 50, armour: 28, attack: 100, accuracy: 50, reach: 65, sighting: 17, deck: 74,  racks: [2, 7, 2, 2], labour: 46000 },
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

/** THE 22 (§4.3 Wave C, S15, 0159): the T2 hulls — two per line. Same columns as WAVE_A. */
export const WAVE_C = [
  ['carvarm',    'Caravela de armada',    'PRT', 2, 'combat',   'mixed',  'The armed caravel of the Portuguese fleets, sheathed in copper and given a heavier battery.'],
  ['nauguerra',  'Nau de guerra',         'PRT', 3, 'support',  'square', 'A nau built for the fleet rather than the cargo: stout, well armed and able to keep a convoy together.'],
  ['galplata',   'Galeón de la Plata',    'ESP', 4, 'trade',    'square', 'The silver galleon of the treasure fleets, built to carry bullion home under heavy guns.'],
  ['dunkirk',    'Fragata de Dunquerque', 'ESP', 2, 'combat',   'square', 'The fast Dunkirk frigate of the Flanders privateers, built for the chase.'],
  ['armfluit',   'Gewapende fluit',       'NLD', 3, 'trade',    'square', 'A fluit with a proper gun deck for the dangerous routes, keeping most of its cargo space.'],
  ['kaper',      'Kaperschip',            'NLD', 2, 'combat',   'square', 'A Dutch privateer, fast and lightly built, with more hold than most fighting hulls.'],
  ['qpinnace',   "Queen's Pinnace",       'ENG', 1, 'explorer', 'mixed',  'A royal pinnace of the English navy, the fastest small scout afloat.'],
  ['armmerch',   'Armed Merchantman',     'ENG', 3, 'trade',    'square', 'An English merchant built to fight its way through, with a stout hull and a full broadside.'],
  ['fregcourse', 'Frégate de course',     'FRA', 2, 'combat',   'square', 'A French privateer frigate from Saint-Malo, quick and handy with a sharp battery.'],
  ['fluteroy',   'Flûte royale',          'FRA', 3, 'trade',    'square', 'The royal store ship of the French navy, a roomy hull built to naval standards.'],
  ['galbast',    'Galea bastarda',        'ITA', 3, 'combat',   'oared',  'The heavy Mediterranean war galley: more oars, more soldiers and a heavier bow battery than the sottile.'],
  ['carcarm',    'Caracca armata',        'ITA', 4, 'trade',    'square', 'An armed Genoese carrack, built to carry a rich cargo through pirate waters.'],
  ['korsan',     'Korsan şebeği',         'OTT', 2, 'combat',   'lateen', 'The Barbary corsair xebec: a fast lateen raider with a heavier battery than the common şebek.'],
  ['mavna',      'Mavna',                 'OTT', 4, 'support',  'oared',  'The great Ottoman mahone, a heavy oared hull that carries guns, troops and stores for the fleet.'],
  ['batil',      'Batil',                 'IND', 1, 'explorer', 'lateen', 'A fast Arabian batil, a long sharp hull for scouting and the pearl banks.'],
  ['ghurabj',    'Ghurab-i-jang',         'IND', 2, 'combat',   'lateen', 'The war ghurab of the Malabar fleets, with a heavier bow gun and copper below the waterline.'],
  ['zhanchuan',  'Zhanchuan',             'CHN', 3, 'combat',   'lateen', 'The Ming war junk proper, built heavier and gunned harder than the coastal patrol ships.'],
  ['haicang',    'Haicang',               'CHN', 4, 'trade',    'lateen', 'The great ocean trader of the Zhangzhou junks, deep in the hold and hard to sink.'],
  ['murakami',   'Murakami kobaya',       'JPN', 1, 'combat',   'oared',  'The war boat of the Murakami sea lords of the Inland Sea, fast and crowded with fighters.'],
  ['oshuin',     'Ō-shuinsen',            'JPN', 3, 'trade',    'square', 'A great red-seal ship for the long runs to Siam and Luzon, built bigger and stouter.'],
  ['tamang',     'Tamangseon',            'KOR', 1, 'explorer', 'oared',  'The Joseon scout boat of the coastal watch, fast under oars with a sharp lookout.'],
  ['bangpae',    'Bangpaeseon',           'KOR', 3, 'combat',   'oared',  'A Joseon warship with a shielded upper deck, the forerunner of the panokseon.'],
]

/** THE 11 (§4.3 Wave D, S17, 0166): the famous ships — one per line, one of each to a house. Same columns as
 *  WAVE_A; the note is the ship's history line (the build yard prints it under her name). */
export const WAVE_D = [
  ['madre',      'Madre de Deus',             'PRT', 6, 'trade',    'square', 'The great Portuguese carrack taken by the English off the Azores in 1592, the richest prize ever brought into an English port.'],
  ['sanmartin',  'San Martín',                'ESP', 6, 'combat',   'square', 'The flagship of the Duke of Medina Sidonia in the Armada of 1588, which fought through the Channel and came home.'],
  ['batavia',    'Batavia',                   'NLD', 4, 'trade',    'square', 'The Dutch East India Company ship wrecked on the Abrolhos reefs off Australia on her maiden voyage in 1629.'],
  ['goldenhind', 'Golden Hind',               'ENG', 2, 'explorer', 'mixed',  'The galleon in which Francis Drake sailed round the world between 1577 and 1580, the second ship ever to do it.'],
  ['couronne',   'La Couronne',               'FRA', 5, 'combat',   'square', 'The first great French ship of the line, built at La Roche-Bernard for Richelieu in 1636.'],
  ['duodo',      'Galeazza di Duodo',         'ITA', 5, 'combat',   'oared',  "The Venetian galleass of Francesco Duodo's squadron, whose guns broke the Ottoman line at Lepanto in 1571."],
  ['turgut',     "Turgut Reis's Kadırga",     'OTT', 3, 'combat',   'oared',  'The war galley of Turgut Reis, the corsair admiral who raided the Christian coasts and fell at the siege of Malta in 1565.'],
  ['rahimi',     'Rahimi',                    'IND', 6, 'trade',    'mixed',  "The great pilgrim ship of the Mughal queen mother, the largest ship of the Red Sea trade until the Portuguese burned it in 1614."],
  ['baochuan',   'Baochuan (treasure ship)',  'CHN', 6, 'trade',    'lateen', "A treasure ship of Zheng He's fleets, which sailed from Nanjing to India, Arabia and Africa between 1405 and 1433."],
  ['sjb',        'San Juan Bautista',         'JPN', 4, 'explorer', 'square', 'The galleon Date Masamune built in 1613 to carry Hasekura Tsunenaga across the Pacific to Acapulco, and on to Rome.'],
  ['geobuk',     'Geobukseon (turtle ship)',  'KOR', 3, 'combat',   'oared',  "Yi Sun-sin's turtle ship, its back plated and spiked against boarders, which led the Joseon fleet against Japan in 1592."],
]

/** The live three, as 0003:2089-2091 + data/ship_stats.json rate them — the anchors. */
const LIVE_ANCHORS = {
  barca:  { key: '1/trade',    hold: 60,  speed: 5.0, crewReq: 8,  crewMax: 20,  hull: 400,  draft: 1, guns: 0 },
  carlat: { key: '2/explorer', hold: 90,  speed: 6.0, crewReq: 12, crewMax: 30,  hull: 550,  draft: 1, guns: 2 },
  nau:    { key: '3/trade',    hold: 400, speed: 4.4, crewReq: 60, crewMax: 140, hull: 1800, draft: 3, guns: 12 },
}

const RACKS = ['high', 'mid', 'low', 'refit']
/** S18 (§8): how far a merchant's line hull may move from the live class she stands in for. */
export const MERCHANT = { hold: 0.10, speed: 0.05 }

/** One hull = archetype × line × tech (`up` = TECH[tech].role[role]; T1 is the identity). Pure. */
function hullOf(archetype, line, size, up = NO_UPLIFT) {
  const a = archetype
  const m = line.mult
  const d = line.add
  const um = (k) => up.mult[k] ?? 1
  const ud = (k) => up.add[k] ?? 0
  const hold = a.hold * um('hold') * m.hold
  const racks = Object.fromEntries(RACKS.map((r, i) => [r, a.racks[i] + (up.rack === r ? 1 : 0)]))
  return {
    hold: roundTo(hold, hold >= 50 ? 5 : 1),
    speedKn: roundTo(a.speed * um('speed') * m.speed, 0.1),
    crewRequired: roundHalfEven(a.crewReq * m.crew),
    crewMax: roundHalfEven(a.crewMax * m.crew),
    durability: roundTo(a.hull * um('hull') * m.hull, 10),
    draft: Math.min(6, Math.max(1, a.draft + d.draft)),
    handling: Math.min(100, Math.max(0, a.handling + ud('handling') + d.handling)),
    armour: Math.min(100, Math.max(0, a.armour + ud('armour') + d.armour)),
    attack: a.attack === 0 ? 0 : roundTo(a.attack * um('attack') * m.attack, 10),
    accuracy: a.accuracy === 0 ? 0 : Math.min(100, Math.max(0, a.accuracy + ud('accuracy') + d.accuracy)),
    reach: Math.min(100, Math.max(0, a.reach + d.reach)),
    sighting: a.sighting + ud('sighting') + d.sighting,
    deck: a.deck + up.rackDeck * size,
    racks: { ...racks, flourish: size >= 3 ? 1 : 0 },
  }
}

/** The size template × the tech's goods factor (each line rounded) with the line's goods substituted
 *  (merged, first appearance first), then the tech's copper sheet. */
function goodsOf(size, subs, tech) {
  const out = new Map()
  for (const [g, q] of [...TEMPLATES[size], ...tech.scaled(size)]) {
    const s = subs[g] ?? g
    out.set(s, (out.get(s) ?? 0) + roundHalfEven(q * tech.goods))
  }
  for (const [g, q] of tech.extra(size)) out.set(g, (out.get(g) ?? 0) + q)
  return [...out].map(([g, qty]) => ({ in: g, qty }))
}

/** IT FITS IN THE SHED: the goods scaled to SHED_TUNS where they exceed it, and the value taken out. */
function shedFit(goodsList, bulk, mid) {
  const tonsOf = (list) => list.reduce((t, g) => t + g.qty * bulk.get(g.in), 0)
  const tons = tonsOf(goodsList)
  if (tons <= SHED_TUNS + 1e-9) return { goods: goodsList, moved: 0, tons: Number(tons.toFixed(3)) }
  const f = SHED_TUNS / tons
  const capped = goodsList.map((g) => ({ in: g.in, qty: Math.max(1, Math.floor(g.qty * f)) }))   // S17: never floored to nothing
  const moved = goodsList.reduce((v, g, i) => v + (g.qty - capped[i].qty) * mid.get(g.in), 0)
  const after = tonsOf(capped)
  if (after > SHED_TUNS + 1e-9) throw new Error(`shed: capped goods are ${after} t, over ${SHED_TUNS}`)
  return { goods: capped, moved: Math.ceil(moved / 500) * 500, tons: Number(after.toFixed(3)) }
}

function requirementsOf(line, size, role, tech) {
  const sk = (s) => `${line}_${SIZE_WORD[s].toUpperCase()}`
  if (tech === 'T2') return [{ skill: sk(size), level: 5 }, { skill: ROLE_T2_SKILL[role], level: 1 }]
  if (tech === 'F') return [{ skill: sk(size), level: 5 }, { skill: 'FAMOUS_SHIPS', level: 1 }, { skill: ROLE_T2_SKILL[role], level: 3 }]
  if (tech !== 'T1') throw new Error(`requirementsOf: tech ${tech}`)
  if (size === 1) return [{ skill: sk(1), level: 1 }]
  if (size === 2) return [{ skill: sk(1), level: 3 }, { skill: sk(2), level: 1 }]
  if (size === 3) return [{ skill: sk(2), level: 3 }, { skill: sk(3), level: 1 }]
  if (size === 4) return [{ skill: sk(3), level: 3 }, { skill: sk(4), level: 1 }, { skill: ROLE_SKILL[role], level: 1 }]
  if (size === 5) return [{ skill: sk(4), level: 3 }, { skill: sk(5), level: 1 }, { skill: 'COMMAND', level: 3 }, { skill: ROLE_SKILL[role], level: 3 }]
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
    const g = goodsOf(size, LINE_YARDS.PRT.subs, TECH.T1).map((x) => `${x.in}:${x.qty}`).sort().join(',')
    const lg = liveHulls[code].goods.map((x) => `${x.in}:${x.qty}`).sort().join(',')
    if (g !== lg) throw new Error(`LIVE ANCHOR ${code}: goods ${g} vs ${lg}`)
  }

  const seen = new Set(Object.keys(LIVE_ANCHORS))
  const waves = [...WAVE_A.map((h) => ['A', 'T1', ...h]), ...WAVE_B.map((h) => ['B', 'T1', ...h]), ...WAVE_C.map((h) => ['C', 'T2', ...h]),
    ...WAVE_D.map((h) => ['D', 'F', ...h])]
  // S17: a famous hull's fitting is its famous gear (scripts/build-gear.mjs FAMOUS names the hull), one piece
  const famousGear = new Map()
  for (const [item, , hull] of FAMOUS) {
    if (famousGear.has(hull)) throw new Error(`${hull}: two famous pieces name it`)
    famousGear.set(hull, item)
  }
  const hulls = waves.map(([wave, tech, code, name, lineCode, size, role, rig, note]) => {
    const key = `${size}/${role}`
    const a = ARCHETYPES[key]
    const line = lines[lineCode]
    const yard = LINE_YARDS[lineCode]
    const t = TECH[tech]
    if (!a) throw new Error(`${code}: no archetype ${key}`)
    if (!line || !yard) throw new Error(`${code}: no line ${lineCode}`)
    if (!t || !t.role[role]) throw new Error(`${code}: no tech uplift ${tech}/${role}`)
    if (seen.has(code)) throw new Error(`${code}: a second hull of that code`)
    seen.add(code)
    if (!['square', 'lateen', 'mixed', 'oared'].includes(rig)) throw new Error(`${code}: rig ${rig}`)
    if (note.length <= 12) throw new Error(`${code}: the note is too short for hull_recipes`)
    const h = hullOf(a, line, size, t.role[role])
    const shed = shedFit(goodsOf(size, yard.subs, t), bulk, mid)
    const goodsList = shed.goods
    const ducats = roundTo(a.labour * t.labour * yard.labour, 500) + shed.moved
    for (const g of goodsList) if (!goods.has(g.in)) throw new Error(`${code}: good ${g.in} is not in data/goods.json`)
    const requirements = requirementsOf(lineCode, size, role, tech)
    for (const r of requirements) if (!skills.has(r.skill)) throw new Error(`${code}: skill ${r.skill} is not in data/skills.json`)
    if ((tech === 'F') !== famousGear.has(code)) throw new Error(`${code}: a famous hull has exactly one famous piece, and no other hull has one`)
    const items = tech === 'F' ? [{ in: famousGear.get(code), qty: 1 }] : []
    return {
      wave, class: code, name, line: lineCode, size, role, tech, anyYard: false,
      family: yard.family, rig, tier: Math.min(size, 5),
      hold: h.hold, crewRequired: h.crewRequired, crewMax: h.crewMax, speedKn: h.speedKn, durability: h.durability,
      guns: h.attack / 10, draft: h.draft, buildHours: SIZE_BUILD_HOURS[size], buildCost: ducats * 4,
      handling: h.handling, armour: h.armour, attack: h.attack, accuracy: h.accuracy, reach: h.reach, sighting: h.sighting,
      deck: h.deck, hands: h.crewMax - Math.ceil(h.crewRequired / 2), racks: h.racks, cabins: SIZE_CABINS[size],
      yardTier: SIZE_YARD_TIER[size], ducats, shedLabour: shed.moved, tons: shed.tons, note, goods: goodsList, items, requirements,
    }
  })
  for (const hull of famousGear.keys()) if (!seen.has(hull)) throw new Error(`famous piece names ${hull}, which is no hull`)
  const nA = hulls.filter((h) => h.wave === 'A').length
  const nB = hulls.filter((h) => h.wave === 'B').length
  const nC = hulls.filter((h) => h.wave === 'C').length
  if (nA !== 52) throw new Error(`Wave A is 52 hulls; the list has ${nA}`)
  if (nB !== 15) throw new Error(`Wave B is 15 hulls; the list has ${nB}`)
  if (nC !== 22) throw new Error(`Wave C is 22 hulls; the list has ${nC}`)
  const nD = hulls.filter((h) => h.wave === 'D').length
  if (nD !== 11) throw new Error(`Wave D is 11 hulls; the list has ${nD}`)
  if (new Set(WAVE_D.map((h) => h[2])).size !== 11) throw new Error('Wave D is one famous ship per line')
  for (const h of hulls) if (h.tons > SHED_TUNS) throw new Error(`${h.class}: ${h.tons} t does not fit the shed`)

  // S18: MERCHANTS OF EVERY FLAG — see the header. One row per (live class, line) that has a hull to offer.
  const merchant = []
  const allRacks = [...RACKS, 'flourish']
  for (const [live, a] of Object.entries(LIVE_ANCHORS)) {
    const lr = liveRacks[live]
    const ld = liveProfiles[live].deck
    for (const lineCode of Object.keys(LINE_YARDS)) {
      if (lineCode === 'PRT') continue   // the live three ARE the Portuguese line
      const pick = hulls
        .filter((h) => h.tech === 'T1' && h.line === lineCode
          && Math.abs(h.hold - a.hold) <= MERCHANT.hold * a.hold + 1e-9
          && Math.abs(h.speedKn - a.speed) <= MERCHANT.speed * a.speed + 1e-9
          && h.crewRequired <= a.crewReq && h.crewMax >= a.crewMax && h.deck >= ld
          && allRacks.every((r) => h.racks[r] >= lr[r]))
        .map((h) => ({ h, d: Math.abs(h.hold - a.hold) / a.hold + Math.abs(h.speedKn - a.speed) / a.speed }))
        .sort((x, y) => x.d - y.d || (x.h.class < y.h.class ? -1 : 1))[0]
      if (pick) merchant.push({ live, line: lineCode, class: pick.h.class })
    }
  }
  if (new Set(merchant.map((m) => m.class)).size !== merchant.length) throw new Error('a line hull stands in for two live classes')
  return { _: 'GENERATED by scripts/build-ships.mjs — do not edit; edit the generator and re-run it (docs/SHIPS_AND_SKILLS.md §4.2; S12 Wave A, migration 0135; S14 Wave B, migration 0138; S15 Wave C, migration 0159; S17 Wave D, migration 0166; S18 merchants, migration 0167).', hulls, merchant }
}

const q = (s) => `'${String(s).replace(/'/g, "''")}'`

/** The SQL VALUES a wave's migration loads (`--sql A` → 0135, `--sql B` → 0138, `--sql C` → 0159, `--sql D` → 0166): pasted into the file verbatim, and the world guard holds
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
    ...(H.some((h) => h.items.length) ? ['-- hull_recipe_items (S17: the famous gear)',
      rows(H.flatMap((h) => h.items.map((i) => `  (${q(h.class)}, ${q(i.in)}, ${i.qty})`)))] : []),
    '-- skill_requirements (hull)',
    rows(H.flatMap((h) => h.requirements.map((r) => `  ('hull', ${q(h.class)}, ${q(r.skill)}, ${r.level})`))),
  ].join('\n')
}

/** The SQL VALUES migration 0167 loads (`--sql-merchant`): public.npc_line_hulls, one row per (live class, line). */
export function merchantSql(gen = generateShips()) {
  return [`-- npc_line_hulls (${gen.merchant.length})`,
    gen.merchant.map((m) => `  (${q(m.live)}, ${q(m.line)}, ${q(m.class)})`).join(',\n')].join('\n')
}

if (process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('scripts/build-ships.mjs')) {
  const text = JSON.stringify(generateShips(), null, 1) + '\n'
  if (process.argv.includes('--sql-merchant')) {
    console.log(merchantSql())
  } else if (process.argv.includes('--sql')) {
    const wave = process.argv[process.argv.indexOf('--sql') + 1]
    if (!['A', 'B', 'C', 'D'].includes(wave)) { console.error(`--sql takes A, B, C or D (got ${wave})`); process.exit(1) }
    console.log(shipsSql(undefined, wave))
  } else if (process.argv.includes('--check')) {
    const now = readFileSync(join(ROOT, SHIPS_FILE), 'utf8')
    if (now !== text) { console.error(`${SHIPS_FILE} is NOT what scripts/build-ships.mjs generates — re-run it.`); process.exit(1) }
    console.log(`${SHIPS_FILE} equals the generator (100 hulls: Wave A 52, Wave B 15, Wave C 22, Wave D 11).`)
  } else {
    writeFileSync(join(ROOT, SHIPS_FILE), text)
    console.log(`wrote ${SHIPS_FILE}: LIVE ANCHORS OK, 100 hulls (Wave A 52, Wave B 15, Wave C 22, Wave D 11)`)
  }
}
