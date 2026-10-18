// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-gear.mjs — THE GEAR: grades 2-5 of the twelve live base types, grades 1-5 of the eleven new ones
//                  (docs/SHIPS_AND_SKILLS.md §6.2-6.4, S12, migration 0135); the refits and what works
//                  every item (S13, 0158); the T2 and Named rungs (S15, 0159); the Country rung — the
//                  eleven sets — and the four perk kits (S16, 0163); the Famous rung — the gear of the
//                  eleven famous ships (S17, 0166)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ONE ITEM MODEL (§6.2): base type × grade. Grade 1 of a live base type is the live item, untouched
// (data/fittings.json + data/gear.json — this file reads them as the anchors and never re-writes
// them). Grade g of a base type:
//   * BUYS × the grade multiplier — 1.30 / 1.60 / 1.90 / 2.20 for G2-G5; speed and hold (the money
//     stats) climb gentler: 1.15 / 1.30 / 1.45 / 1.60. SPENDS × 1.00 (the cost of a fitting is the
//     same at every grade). Whole stats round half up, speed to 0.01 knot. (§6.4's Long Guns ladder:
//     reach 15 → 20 / 24 / 29 / 33 — 15 × 1.9 = 28.5 → 29.)
//   * Deck and Hands × (1 + 0.1 × (g − 1)), rounded half up (§6.1 "+10 % per grade above 1").
//   * NEEDS its module skill at level g (G2 → II … G5 → V). Grade 1 needs nothing — the live pre-image
//     and §6.2's rule for the G1 of a new base type — except where the base type itself names a
//     second skill (Carronades: Short Guns I; Chase Guns: Long Guns I), which every grade needs.
//   * Made at workshop tier ≥ 2 for G2-G3 (never below the G1's own tier), tier 3 for G4-G5.
//   * Made of its FAMILY'S material ladder (§6.4): cast metal (bar-iron → culverin → brass → Swedish
//     iron → bronze), timber (deal/pine → oak → teak → live oak → greenheart), canvas (flax → hemp →
//     duck → Baltic sailcloth → Holland duck), cordage & iron (iron → osmund → bar-iron + abaca →
//     Swedish iron → + copper), instruments (masts → riga mast → brass + charts → lodestone). 2-5
//     goods each (0068), every one sold somewhere (asserted by 0135).
// The same buys/spends sentence as its G1 (the stats it moves do not change, only how far). The
// figurehead is the one base type that moves no stat at any grade (0074, DESIGN 1.4).
//
// S15 (migration 0159, §6.2's meta ladder): two more rungs, each ONE rule over the same base types.
//   * T2 (meta 5, "improved") — one per base type but the figurehead (22). BUYS × 2.60 (speed and hold
//     × 1.80), SPENDS × 1.25 rounded half away from zero (handling −6 → −8; −5 → −6; speed −0.35 → −0.44);
//     Deck and Hands = the G1's × 1.5; needs the module skill V + its specialisation I (T2_SPEC) + the
//     base type's second skill, if any; made at tier 3; the G1's words, volume and active flag. Its
//     recipe is the G5's materials scaled up plus the family's T2 component (§6.2: cast metal gunpowder +
//     falconet, timber copper-sheet + swedish-iron, canvas abaca, cordage & iron lodestone, instruments
//     sea-charts). §6.4's three are verbatim and asserted: Long Eighteens 156 / 39, hold −25, handling
//     −8; Racing Courses +1.08, handling −10; Orlop Stowage +45, speed −0.44, handling −6.
//   * Named (meta 1) — a city's own pattern of ONE grade of ONE base type (NAMED, 12: one per city with a
//     tier-3 workshop). The grade's effects with BUYS × 1.10 (half up; speed to 0.01) and spends as they
//     are; Deck −1 (never below 0), Hands the grade's; the grade's recipe plus one good the city is
//     known for; the grade's requirements exactly; tier 3; made in that one city (public.item_city).
//     §6.4's Lisbon-cast Brass Guns (G3 Long Guns) come out 106 / 26 — asserted.
//
// S16 (migration 0163, §6.2's Country row, §6.6, §6.7): the sets and the kits, each ONE rule.
//   * Country (meta 6, grade 4) — a line's pattern of ONE base type, four a line (COUNTRY, 44): a High piece, a
//     Mid piece, a Low piece and a Figurehead, the four pieces of the line's SET (§6.7). The G1's effects with
//     BUYS × 2.40 (speed and hold × 1.70), SPENDS × 1.00, then the line's second buy — a stat the G1 does not
//     move, appended (its word joins `buys`); or, where it IS one the G1 moves (item_effects keeps one row per
//     stat), folded into that row by the sum. Deck and Hands = the G1's × 1.3; needs the module skill IV + the
//     line's Medium Hulls I (+ the base type's second skill); made at tier ≥ 2 (0163 confines it to a port of the
//     line's builder nations through public.item_line); the G1's words, volume and active flag. The Country
//     Figurehead moves nothing, costs nothing and needs the line's Medium Hulls I only. §6.4's four are asserted:
//     Sea Dogs' Culverin Battery 144 / 36, accuracy +10, hold −20, handling −6; Toiles de Bretagne +1.02,
//     handling −4 (§6.4 writes it "handling +4 | handling −8": one row, the sum); VOC Frames speed −0.18,
//     handling −5; Turtle-back Plating armour 30.
//   * Kits (KITS, 4; §6.6) — the perk kits: base type Kit, rack kit (no hull has a place in it: a kit is never
//     fitted, it is used up), grade 1, meta 0, tier 3, volume 1, no effect, no requirement, never wear.
//
// S17 (migration 0166, §6.2's Famous row): the gear of a famous ship, ONE per famous hull (FAMOUS, 11), each
//   the Famous rung (meta 8, grade 5) of ONE base type. The G1's effects with BUYS × 3.00 (speed and hold
//   × 2.00), SPENDS × 1.00, plus an authored second buy where §6.4 names one (Drake's Culverins: accuracy
//   +12 — the only one it names); Deck and Hands = the G1's × 1.6 (§6.1 "Famous +60 %"); needs the module
//   skill V + Famous Ships I (+ the base type's second skill); the G1's words, volume and active flag.
//   It goes into its hull's recipe as a fitting (scripts/build-ships.mjs reads `hull` from this table —
//   the one home of "which famous ship's gear this is"; §8 S17 "famous gear as hull_recipe_items").
//   §6.2 says the Famous rung is "made at —, comes with the hull"; 0072 (b) — the owner's row 58, "not
//   only some trading goods but some items" — refuses a hull fitting that no city can make. So a Famous
//   piece is MADE at a tier-3 workshop, of its base type's T2 recipe × 1.5 (rounded up), and spent when
//   its hull is laid down (NOT the owner's — confirm; written in the S17 PR).
//   0184 (the owner, 2026-10-18: "yes famous gear can be made, but later. there will be other items that
//   needs to be gained in act of pirating, trading, and all. i will set them later."): FAMOUS_MADE is false,
//   so every Famous piece is written `made: false` — public.item_unmade's rows, held by the world guard —
//   and no workshop makes it (public.item_not_made, read by public.made_only_in); its hull cannot be laid
//   down while its piece is made nowhere (public.hull_unmade). The recipe stays authored here, for the day
//   the owner sets how the piece is won.
//   §6.4's Drake's Culverins (Famous Long Guns) come out 180 / 45, accuracy +12 — asserted.
//
// §6.3 lists ELEVEN new base types (Carronades, Chase Guns, Swivel Guns, Studding Sails, Storm
// Canvas, Whipstaff, Sheet Anchor, Capstan, Binnacle & Charts, Planking, Bilge Pumps); §0/§8 say
// "ten" and "~98 rows". The table is the specification: 11 × 5 + 12 × 4 = 103 rows.
//
// RUN:   node scripts/build-gear.mjs             writes data/gear.generated.json
//        node scripts/build-gear.mjs --check     fails if the file is not what the generator gives
//        node scripts/build-gear.mjs --sql-0184  the items made nowhere (public.item_unmade, migration 0184)
//        node scripts/build-gear.mjs --sql       the VALUES 0135 loaded (103 Wave A items)
//        node scripts/build-gear.mjs --sql-0158  the VALUES 0158 loaded (14 refits + item_use)
//        node scripts/build-gear.mjs --sql-0159  the VALUES 0159 loaded (22 T2 + 12 Named, item_use, item_city)
//        node scripts/build-gear.mjs --sql-0163  the VALUES 0163 loads (44 Country + 4 kits, item_use, item_line)
//        node scripts/build-gear.mjs --sql-0166  the VALUES 0166 loads (11 Famous, item_use)
// scripts/db/world-guard.mjs re-runs generateGear() on every apply and holds the database to it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const readJson = (rel) => JSON.parse(readFileSync(join(ROOT, rel), 'utf8'))
export const GEAR_FILE = 'data/gear.generated.json'

export const GRADE_MULT = { 1: 1, 2: 1.3, 3: 1.6, 4: 1.9, 5: 2.2 }
export const MONEY_MULT = { 1: 1, 2: 1.15, 3: 1.3, 4: 1.45, 5: 1.6 }
const MONEY_STATS = new Set(['speed', 'hold'])
const roundUp = (x) => Math.round(x + 1e-9)
const round2 = (x) => Math.round(x * 100 + 1e-6) / 100

const r = (s) => s.split(',').map((p) => { const [g, q] = p.trim().split(' '); return { in: g, qty: Number(q) } })

/**
 * THE BASE TYPES (§6.3). `g1` names the live item (its row is data/fittings.json's) or, for a new
 * base type, carries the G1 row in full. `grades` are G2-G5: [code, name, recipe, note].
 * `skill` is the module skill (null: the figurehead); `also` a second skill every grade needs.
 */
export const BASE_TYPES = [
  { base: 'Long Guns', rack: 'high', skill: 'GUNNERY', g1: 'broadside-guns', grades: [
    ['culverins', 'Culverins', r('culverin 4, bar-iron 4, timber 2'), 'Longer guns of a better pattern: they hit harder and carry further.'],
    ['brass-guns', 'Brass Guns', r('brass-ingots 8, culverin 6, live-oak 3'), 'Cast brass does not burst as iron does, so the charge can be heavier.'],
    ['swedish-guns', 'Swedish Guns', r('swedish-iron 8, culverin 8, shot-and-ball 2'), 'Guns of the best Swedish iron: light for their weight of shot.'],
    ['bronze-guns', 'Bronze Guns', r('copper 12, tin-ingots 8, culverin 10, falconet 2'), 'The finest gun metal there is, cast for range and weight of fire.'] ],
    t2: ['long-eighteens', 'Long Eighteens', r('swedish-iron 10, culverin 12, falconet 4, gunpowder 4'), 'Long guns bored for an eighteen-pound ball: the heaviest broadside a trader can mount, and it costs more cargo space and handling.'] },
  { base: 'Carronades', rack: 'high', skill: 'GUNNERY', also: { skill: 'SHORT_GUNS', level: 1 },
    g1: { code: 'carronades', name: 'Carronades', slot: 'weapon', buys: 'Attack at close range', spends: 'Reach, Cargo space, Handling',
      note: 'Short, heavy guns that smash at close range and reach nothing far off.', volume: 5, wsTier: 3, deck: 5, hands: 7, active: true,
      effects: [['attack', 90], ['reach', -15], ['hold', -14], ['handling', -4]], recipe: r('bar-iron 8, brass-ingots 2, gunpowder 2') },
    grades: [
      ['heavy-carronades', 'Heavy Carronades', r('culverin 3, bar-iron 6, gunpowder 2'), 'Carronades of a heavier pattern, with more shot in every broadside.'],
      ['brass-carronades', 'Brass Carronades', r('brass-ingots 8, culverin 4, gunpowder 2'), 'Brass short guns that take a bigger charge without bursting.'],
      ['swedish-carronades', 'Swedish Carronades', r('swedish-iron 8, culverin 6, gunpowder 3'), 'Short guns of Swedish iron, as heavy-hitting as any afloat.'],
      ['bronze-carronades', 'Bronze Carronades', r('copper 10, tin-ingots 6, culverin 6, gunpowder 3'), 'Bronze smashers: the hardest blow a ship can strike at close range.'] ],
    t2: ['gunnades', 'Gunnades', r('copper 12, tin-ingots 8, falconet 4, gunpowder 4'), 'A cross between a gun and a carronade: it smashes at close range and keeps a little more reach.'] },
  { base: 'Chase Guns', rack: 'high', skill: 'GUNNERY', also: { skill: 'LONG_GUNS', level: 1 },
    g1: { code: 'stern-chasers', name: 'Stern Chasers', slot: 'weapon', buys: 'Reach, Accuracy', spends: 'Cargo space',
      note: 'Long guns at the stern and bow that keep a pursuer honest at a distance.', volume: 4, wsTier: 3, deck: 4, hands: 4, active: true,
      effects: [['reach', 20], ['accuracy', 10], ['hold', -8]], recipe: r('culverin 2, live-oak 2, shot-and-ball 2') },
    grades: [
      ['culverin-chasers', 'Culverin Chasers', r('culverin 3, bar-iron 3, shot-and-ball 2'), 'Longer chase guns that reach further and aim truer.'],
      ['brass-chasers', 'Brass Chasers', r('brass-ingots 6, culverin 4, shot-and-ball 2'), 'Brass chase guns, accurate at long range.'],
      ['swedish-chasers', 'Swedish Chasers', r('swedish-iron 6, culverin 5, shot-and-ball 3'), 'Swedish-iron chasers that outrange most broadsides.'],
      ['bronze-chasers', 'Bronze Chasers', r('copper 8, tin-ingots 5, culverin 6, falconet 1'), 'Bronze long chasers: the furthest-reaching guns a ship can carry.'] ],
    t2: ['long-nines', 'Long Nines', r('copper 10, tin-ingots 6, culverin 8, falconet 3, gunpowder 2'), 'Nine-pounder chase guns of the longest pattern: they reach and aim further than any broadside piece.'] },
  { base: 'Swivel Guns', rack: 'high', skill: 'GUNNERY',
    g1: { code: 'swivel-guns', name: 'Swivel Guns', slot: 'weapon', buys: 'Attack, Accuracy', spends: 'Handling',
      note: 'Small guns on the rails that sweep a deck at close quarters.', volume: 2, wsTier: 2, deck: 2, hands: 3, active: true,
      effects: [['attack', 20], ['accuracy', 8], ['handling', -2]], recipe: r('bar-iron 3, timber 1, shot-and-ball 1') },
    grades: [
      ['iron-swivels', 'Iron Swivels', r('bar-iron 3, culverin 1, shot-and-ball 1'), 'Better-bored swivels that hit harder and truer.'],
      ['brass-swivels', 'Brass Swivels', r('brass-ingots 4, culverin 1, shot-and-ball 1'), 'Brass swivels, light enough to train fast.'],
      ['swedish-swivels', 'Swedish Swivels', r('swedish-iron 4, culverin 2, shot-and-ball 2'), 'Swivels of Swedish iron that can take a double charge.'],
      ['bronze-swivels', 'Bronze Swivels', r('copper 5, tin-ingots 3, swivel-gun 1, shot-and-ball 2'), 'Bronze swivels: the deadliest small guns on any rail.'] ],
    t2: ['pateraros', 'Pateraros', r('copper 6, tin-ingots 4, swivel-gun 2, falconet 1, gunpowder 2'), 'Breech-loading swivels with spare chambers: they fire faster and truer than a plain swivel.'] },
  { base: 'Boarding Gear', rack: 'high', skill: 'BOARDING', g1: 'boarding-gear', grades: [
    ['osmund-grapnels', 'Osmund Grapnels', r('osmund-iron 3, hemp 3, timber 1'), 'Grapnels of good iron that hold where cheaper ones straighten.'],
    ['boarding-pikes', 'Boarding Pikes', r('bar-iron 3, abaca 3, timber 2'), 'Pikes, nets and grapnels for a crew that means to board.'],
    ['boarding-axes', 'Boarding Axes & Grapnels', r('swedish-iron 3, abaca 3, live-oak 2'), 'Axes and grapnels of Swedish iron for the hardest boarding fights.'],
    ['storming-gear', 'Storming Gear', r('swedish-iron 4, copper 2, abaca 3, slow-match 1'), 'Everything a boarding party needs, down to the fire pots.'] ],
    t2: ['grenadoes-and-cutlasses', 'Grenadoes & Cutlasses', r('swedish-iron 5, abaca 4, gunpowder 3, falconet 1, slow-match 1'), 'Grenades, cutlasses and a falconet in the top: a boarding party that clears a deck before it crosses.'] },
  { base: 'Powder Magazine', rack: 'high', skill: 'GUNNERY', g1: 'powder-magazine', grades: [
    ['lined-magazine', 'Lined Magazine', r('gunpowder 5, live-oak 3, copper-sheet 2'), 'A lined powder room that keeps the guns firing longer.'],
    ['copper-magazine', 'Copper-lined Magazine', r('gunpowder 6, teak 3, copper-sheet 4'), 'A copper-lined powder room: drier powder and steadier fire.'],
    ['light-room-magazine', 'Light Room Magazine', r('gunpowder 8, live-oak 4, copper-sheet 4, lead 2'), 'A powder room with its own light room, so the gunners never fire blind.'],
    ['grand-magazine', 'Grand Magazine', r('gunpowder 10, greenheart 4, copper-sheet 6, slow-match 1'), 'The finest magazine afloat, built for a long day of fighting.'] ],
    t2: ['hanging-magazine', 'Hanging Magazine', r('gunpowder 12, greenheart 5, copper-sheet 8, swedish-iron 2'), 'A powder room hung clear of the hull on iron knees and lined in copper: dry powder and a steadier rate of fire.'] },
  { base: 'Sails', rack: 'mid', skill: 'RIGGING', g1: 'suit-of-sails', grades: [
    ['hemp-canvas', 'Hemp Canvas', r('hemp 6, cordage 3, tar 1'), 'Sails of hemp canvas that hold their shape and drive harder.'],
    ['duck-canvas', 'Duck Canvas', r('canvas-duck 20, hemp 6, cordage 3, tar 1'), 'Heavy duck canvas that stands a stronger wind.'],
    ['baltic-sailcloth', 'Baltic Sailcloth', r('sailcloth 10, hemp 6, cordage 4, tar 2'), 'Close-woven Baltic sailcloth: more speed from the same wind.'],
    ['holland-duck', 'Holland Duck', r('sailcloth 14, abaca 8, whale-bone-stays 4, tar 2'), 'The best sail canvas there is, cut and stayed for speed.'] ],
    t2: ['racing-courses', 'Racing Courses', r('sailcloth 18, abaca 10, whale-bone-stays 6, canvas-duck 6'), 'Courses and topsails cut flat and full for speed: the fastest suit a ship can carry, and a handful to work.'] },
  { base: 'Headsails', rack: 'mid', skill: 'RIGGING', g1: 'bowsprit-and-jib', grades: [
    ['hemp-jib', 'Hemp Jib', r('naval-timber 3, hemp 3, cordage 2'), 'A hemp jib on a stouter bowsprit: quicker through the turn.'],
    ['duck-jib', 'Duck Jib & Staysail', r('naval-timber 3, canvas-duck 8, cordage 3'), 'A jib and staysail of duck canvas that turn the ship smartly.'],
    ['sailcloth-headsails', 'Sailcloth Headsails', r('riga-mast 2, sailcloth 4, cordage 3'), 'Headsails of Baltic sailcloth on a Riga spar.'],
    ['holland-headsails', 'Holland Headsails', r('riga-mast 2, sailcloth 6, abaca 3, whale-bone-stays 2'), 'The finest headsails: the ship answers almost before the helm is put over.'] ],
    t2: ['flying-jib', 'Flying Jib & Jibboom', r('riga-mast 3, sailcloth 8, abaca 5, whale-bone-stays 3'), 'A jibboom run out beyond the bowsprit with a flying jib on it: the ship turns quicker and gains a little way.'] },
  { base: 'Studding Sails', rack: 'mid', skill: 'RIGGING',
    g1: { code: 'studding-sails', name: 'Studding Sails', slot: 'rig', buys: 'Speed', spends: 'Handling, Hull',
      note: 'Extra sails set outside the main ones in fair weather: faster, but harder to handle and easy to damage.', volume: 4, wsTier: 2, deck: 4, hands: 5, active: false,
      effects: [['speed', 0.9], ['handling', -14], ['durability', -30]], recipe: r('flax 8, norway-spruce 2, cordage 3') },
    grades: [
      ['hemp-studding-sails', 'Hemp Studding Sails', r('hemp 8, norway-spruce 2, cordage 3'), 'Studding sails of hemp canvas on spruce booms.'],
      ['duck-studding-sails', 'Duck Studding Sails', r('canvas-duck 20, norway-spruce 3, cordage 3'), 'Duck-canvas studding sails that carry in a fresher wind.'],
      ['sailcloth-studding-sails', 'Sailcloth Studding Sails', r('sailcloth 8, riga-mast 2, cordage 4'), 'Baltic sailcloth studding sails on Riga booms.'],
      ['holland-studding-sails', 'Holland Studding Sails', r('sailcloth 12, abaca 6, riga-mast 2, whale-bone-stays 2'), 'The fastest studding sails there are.'] ],
    t2: ['royal-stunsails', 'Royal Stunsails', r('sailcloth 14, abaca 8, riga-mast 3, whale-bone-stays 3'), 'Studding sails set right up to the royals: a great deal more speed in fair weather, and a great deal more to tear.'] },
  { base: 'Storm Canvas', rack: 'mid', skill: 'RIGGING',
    g1: { code: 'storm-canvas', name: 'Storm Canvas', slot: 'rig', buys: 'Hull, Handling', spends: 'Speed',
      note: 'Small, heavy sails for bad weather: the ship rides out a storm and gives up a little speed.', volume: 3, wsTier: 1, deck: 3, hands: 3, active: true,
      effects: [['durability', 50], ['handling', 4], ['speed', -0.25]], recipe: r('canvas-duck 4, cordage 2, tar 1') },
    grades: [
      ['hemp-storm-canvas', 'Hemp Storm Canvas', r('hemp 4, canvas-duck 4, tar 1'), 'Storm sails of hemp and duck that take a harder blow.'],
      ['double-duck-storm-canvas', 'Double Duck Storm Canvas', r('canvas-duck 12, hemp 3, tar 1'), 'Doubled duck canvas for the worst weather.'],
      ['sailcloth-storm-canvas', 'Sailcloth Storm Canvas', r('sailcloth 6, hemp 4, tar 2'), 'Baltic storm canvas that holds where others split.'],
      ['holland-storm-canvas', 'Holland Storm Canvas', r('sailcloth 8, abaca 6, whale-bone-stays 2, tar 2'), 'The best storm canvas made: the ship can ride out almost anything.'] ],
    t2: ['storm-trysails', 'Storm Trysails', r('sailcloth 10, abaca 8, whale-bone-stays 3, tar 2'), 'Small trysails on their own gaffs, cut from the heaviest cloth: the ship lies to in the worst weather and loses a little speed.'] },
  { base: 'Rudder', rack: 'mid', skill: 'SEAMANSHIP', g1: 'rudder-and-helm', grades: [
    ['oak-rudder', 'Oak Rudder & Helm', r('timber 6, ships-nails 3, lignum-vitae 1'), 'A broader oak rudder that bites harder.'],
    ['teak-rudder', 'Teak Rudder & Helm', r('teak 4, ships-nails 3, lignum-vitae 1'), 'A teak rudder that does not warp or rot.'],
    ['live-oak-rudder', 'Live-oak Rudder & Tiller', r('live-oak 6, naval-timber 2, ships-nails 3, lignum-vitae 1'), 'A live-oak rudder on a long tiller: the ship turns on a coin.'],
    ['greenheart-rudder', 'Greenheart Rudder & Helm', r('greenheart 6, lignum-vitae 3, copper-sheet 2'), 'The finest steering gear made, of greenheart and lignum vitae.'] ],
    t2: ['wheel-steered-rudder', 'Wheel-steered Rudder', r('greenheart 8, lignum-vitae 4, copper-sheet 4, swedish-iron 2'), "A ship's wheel and tiller ropes on a greenheart rudder: the helmsman has more purchase and the ship answers at once."] },
  { base: 'Whipstaff', rack: 'mid', skill: 'SEAMANSHIP',
    g1: { code: 'whipstaff', name: 'Whipstaff', slot: 'steering', buys: 'Handling', spends: 'Cargo space',
      note: 'A light steering lever that gives the helmsman more purchase on the rudder.', volume: 2, wsTier: 1, deck: 2, hands: 1, active: false,
      effects: [['handling', 7], ['hold', -2]], recipe: r('timber 3, iron 1, hemp 1') },
    grades: [
      ['oak-whipstaff', 'Oak Whipstaff', r('timber 4, osmund-iron 1, hemp 1'), 'A stouter oak whipstaff.'],
      ['teak-whipstaff', 'Teak Whipstaff', r('teak 3, bar-iron 1, hemp 1'), 'A teak whipstaff with iron fittings.'],
      ['live-oak-whipstaff', 'Live-oak Whipstaff', r('live-oak 4, naval-timber 1, swedish-iron 1'), 'A live-oak whipstaff that answers the lightest touch.'],
      ['greenheart-whipstaff', 'Greenheart Whipstaff', r('greenheart 4, lignum-vitae 2, brass-ingots 1'), 'The best whipstaff made, of greenheart and brass.'] ],
    t2: ['geared-whipstaff', 'Rowle-geared Whipstaff', r('greenheart 5, lignum-vitae 3, brass-ingots 2, copper-sheet 1, swedish-iron 1'), 'A whipstaff turning in a brass rowle with iron gearing: more rudder for the same push.'] },
  { base: 'Anchor', rack: 'mid', skill: 'SEAMANSHIP', g1: 'anchor-and-cable', grades: [
    ['osmund-anchor', 'Osmund Anchor & Cable', r('osmund-iron 4, hemp 4, tar 1'), 'An anchor of good osmund iron on a stronger cable.'],
    ['manila-anchor', 'Bar-iron Anchor & Manila Cable', r('bar-iron 4, abaca 4, tar 1'), 'A bar-iron anchor on Manila cable, which does not rot.'],
    ['swedish-anchor', 'Swedish Anchor & Cable', r('swedish-iron 4, abaca 5, tar 1'), 'A Swedish-iron anchor that holds in any ground.'],
    ['copper-fast-anchor', 'Copper-fast Anchor & Cable', r('swedish-iron 5, copper 2, abaca 5'), 'The best ground tackle made, copper-fastened against rust.'] ],
    t2: ['admiralty-anchor', 'Admiralty-pattern Anchor', r('swedish-iron 6, copper 3, abaca 6, lodestone 1'), 'An anchor of the improved pattern with a longer shank and curved arms: it bites in any ground and weighs a little more.'] },
  { base: 'Sheet Anchor', rack: 'mid', skill: 'SEAMANSHIP',
    g1: { code: 'sheet-anchor', name: 'Sheet Anchor', slot: 'ground-tackle', buys: 'Hull in a storm, Handling', spends: 'Cargo space',
      note: 'The biggest anchor on board, kept for the night it is the only thing between the ship and the rocks.', volume: 5, wsTier: 2, deck: 5, hands: 3, active: true,
      effects: [['durability', 60], ['handling', 2], ['hold', -10]], recipe: r('iron 6, hemp 6, tar 1') },
    grades: [
      ['osmund-sheet-anchor', 'Osmund Sheet Anchor', r('osmund-iron 6, hemp 6, tar 1'), 'A sheet anchor of osmund iron.'],
      ['bar-iron-sheet-anchor', 'Bar-iron Sheet Anchor', r('bar-iron 6, abaca 5, tar 1'), 'A bar-iron sheet anchor on Manila cable.'],
      ['swedish-sheet-anchor', 'Swedish Sheet Anchor', r('swedish-iron 6, abaca 6, tar 2'), 'A Swedish-iron sheet anchor that never drags.'],
      ['copper-fast-sheet-anchor', 'Copper-fast Sheet Anchor', r('swedish-iron 6, copper 3, abaca 6'), 'The best sheet anchor made.'] ],
    t2: ['bower-and-sheet-anchors', 'Bower & Sheet Anchors', r('swedish-iron 8, copper 4, abaca 8, lodestone 1'), 'A sheet anchor and a best bower carried together: the ship rides out almost any night, at a cost in cargo space.'] },
  { base: 'Capstan', rack: 'mid', skill: 'SEAMANSHIP',
    g1: { code: 'capstan', name: 'Capstan', slot: 'ground-tackle', buys: 'Handling, a little Speed', spends: 'Cargo space',
      note: 'A capstan to haul the anchor and the yards faster, so the ship gets under way sooner.', volume: 3, wsTier: 2, deck: 3, hands: 3, active: false,
      effects: [['handling', 6], ['speed', 0.1], ['hold', -5]], recipe: r('live-oak 3, iron 2, tallow 1') },
    grades: [
      ['osmund-capstan', 'Osmund Capstan', r('timber 4, osmund-iron 2, tallow 1'), 'A capstan with osmund-iron pawls.'],
      ['manila-capstan', 'Manila Capstan', r('teak 3, bar-iron 2, abaca 2, tallow 1'), 'A teak capstan with a Manila messenger.'],
      ['swedish-capstan', 'Swedish Capstan', r('live-oak 4, swedish-iron 2, abaca 2, tallow 1'), 'A live-oak capstan with Swedish-iron fittings.'],
      ['double-capstan', 'Double Capstan', r('greenheart 4, swedish-iron 3, copper 1, abaca 2'), 'A double capstan: two crews heave at once.'] ],
    t2: ['geared-capstan', 'Geared Capstan', r('greenheart 5, swedish-iron 4, copper 2, abaca 3, lodestone 1'), 'A capstan geared so one crew heaves like two: the anchor comes up fast and the yards faster.'] },
  { base: 'Lookout', rack: 'mid', skill: 'LOOKOUTS', g1: 'crows-nest', grades: [
    ['topgallant-mast', 'Topgallant Mast', r('riga-mast 2, cordage 3, tar 1'), 'A taller mast with a lookout higher up: the horizon moves out.'],
    ['masthead-glass', 'Masthead Glass', r('riga-mast 2, brass-ingots 2, sea-charts 1'), 'A lookout with a brass glass and charts to name what is seen.'],
    ['lookout-top', 'Lookout Top & Glass', r('riga-mast 2, lodestone 1, sea-charts 1'), 'A fighting top with a glass and compass for the lookout.'],
    ['royal-lookout', 'Royal Lookout', r('riga-mast 3, lodestone 1, sea-charts 1, brass-ingots 2'), 'The highest lookout and the best glass afloat.'] ],
    t2: ['night-glass', 'Night Glass & Royal Mast', r('riga-mast 4, lodestone 1, sea-charts 2, brass-ingots 3'), 'A royal mast with a night glass at its head: the lookout sees further by day and something by night.'] },
  { base: 'Binnacle & Charts', rack: 'mid', skill: 'INSTRUMENTS',
    g1: { code: 'binnacle-and-charts', name: 'Binnacle & Charts', slot: 'lookout', buys: 'Sighting, Handling', spends: 'Cargo space',
      note: 'A compass housing and a chest of charts: the ship knows where it is and what lies ahead.', volume: 2, wsTier: 2, deck: 2, hands: 1, active: false,
      effects: [['sighting', 3], ['handling', 5], ['hold', -3]], recipe: r('timber 2, brass-ingots 1, sea-charts 1') },
    grades: [
      ['brass-binnacle', 'Brass Binnacle & Charts', r('riga-mast 1, brass-ingots 2, sea-charts 1'), 'A brass binnacle and better charts.'],
      ['binnacle-and-atlas', 'Binnacle & Sea Atlas', r('brass-ingots 2, sea-charts 2'), 'A binnacle and a full sea atlas.'],
      ['lodestone-compass', 'Lodestone Compass & Charts', r('lodestone 2, sea-charts 2, brass-ingots 1'), 'A compass touched with lodestone, true in any weather.'],
      ['masters-binnacle', "Master's Binnacle", r('lodestone 2, sea-charts 3, brass-ingots 2, lignum-vitae 1'), 'The finest instruments a sailing master can own.'] ],
    t2: ['azimuth-compass', 'Azimuth Compass & Rutter', r('lodestone 3, sea-charts 4, brass-ingots 3, lignum-vitae 1'), 'An azimuth compass and a written rutter of every coast: the ship knows its bearing and what lies ahead.'] },
  { base: 'Ballast', rack: 'low', skill: 'SHIPWRIGHT', g1: 'ballast', grades: [
    ['iron-kentledge', 'Iron Kentledge', r('iron 6, timber 2'), 'Iron ballast blocks, stowed low and tight.'],
    ['pig-iron-ballast', 'Pig-iron Ballast', r('bar-iron 4, iron 4, timber 2'), 'Pig-iron ballast trimmed for a stiffer ship.'],
    ['lead-ballast', 'Lead & Shingle Ballast', r('lead 8, iron 4, oakum 2'), 'Lead ballast packed in shingle: very stiff, very steady.'],
    ['cast-kentledge', 'Cast Kentledge', r('lead 8, swedish-iron 3, copper 2'), 'Cast ballast fitted to the hull: the steadiest ship afloat.'] ],
    t2: ['trimmed-kentledge', 'Trimmed Kentledge', r('lead 10, swedish-iron 4, copper 2, copper-sheet 2'), 'Kentledge cast to the hull and trimmed by a shipwright: the stiffest ship afloat, and a slower one.'] },
  { base: 'Sheathing', rack: 'low', skill: 'SHIPWRIGHT', g1: 'copper-sheathing', grades: [
    ['doubled-copper', 'Doubled Copper', r('copper-sheet 8, ships-nails 4, tar 2'), 'A double layer of copper below the waterline.'],
    ['teak-and-copper', 'Teak & Copper Sheathing', r('teak 4, copper-sheet 8, ships-nails 4'), 'Teak planking under copper: worm and shot both stop here.'],
    ['live-oak-and-copper', 'Live-oak & Copper Sheathing', r('live-oak 6, copper-sheet 10, ships-nails 5, oakum 2'), 'Live oak under copper, the hardest bottom a ship can have.'],
    ['greenheart-sheathing', 'Greenheart Sheathing', r('greenheart 8, copper-sheet 12, lignum-vitae 2, oakum 2'), 'Greenheart and copper: the best sheathing made.'] ],
    t2: ['copper-bolted-sheathing', 'Copper-bolted Sheathing', r('greenheart 10, copper-sheet 16, lignum-vitae 3, swedish-iron 2, oakum 2'), 'Copper sheathing fastened with copper bolts over greenheart, so the iron below does not rot away: the hardest bottom made.'] },
  { base: 'Planking', rack: 'low', skill: 'SHIPWRIGHT',
    g1: { code: 'deal-planking', name: 'Deal Planking', slot: 'hull', buys: 'Armour, Hull', spends: 'Speed, Cargo space',
      note: 'A second skin of planks over the hull: stronger, heavier and slower.', volume: 4, wsTier: 1, deck: 4, hands: 0, active: false,
      effects: [['armour', 10], ['durability', 160], ['speed', -0.45], ['hold', -12]], recipe: r('norway-spruce 12, ships-nails 4, oakum 2, pine-pitch 2') },
    grades: [
      ['oak-planking', 'Oak Planking', r('timber 12, ships-nails 5, oakum 3, tar 1'), 'Doubled oak planking.'],
      ['teak-planking', 'Teak Planking', r('teak 10, ships-nails 6, oakum 3, tar 1'), 'Doubled teak planking that does not rot.'],
      ['live-oak-planking', 'Live-oak Planking', r('live-oak 16, naval-timber 4, ships-nails 8, oakum 4'), 'Doubled live oak: shot bounces off it.'],
      ['greenheart-planking', 'Greenheart Planking', r('greenheart 20, lignum-vitae 10, naval-timber 6, copper-sheet 8'), 'Doubled greenheart, the hardest planking made.'] ],
    t2: ['diagonal-planking', 'Diagonal Planking', r('greenheart 24, lignum-vitae 12, copper-sheet 10, swedish-iron 4'), 'A second skin of greenheart laid diagonally over the frames: the hull stops working in a sea and takes far more shot.'] },
  { base: 'Bilge Pumps', rack: 'low', skill: 'SHIPWRIGHT',
    g1: { code: 'bilge-pumps', name: 'Bilge Pumps', slot: 'hull', buys: 'Hull', spends: 'Cargo space',
      note: 'Pumps that keep the water down when the hull is hurt or the sea gets in.', volume: 3, wsTier: 1, deck: 3, hands: 4, active: true,
      effects: [['durability', 90], ['hold', -5]], recipe: r('timber 3, lead 2, hides 1') },
    grades: [
      ['chain-pumps', 'Chain Pumps', r('timber 3, iron 2, hides 1, cordage 1'), 'Chain pumps that move more water than a plain pump.'],
      ['teak-chain-pumps', 'Teak Chain Pumps', r('teak 3, bar-iron 2, hides 1'), 'Chain pumps in teak cases.'],
      ['brake-pumps', 'Brake Pumps', r('live-oak 4, copper 2, hides 2'), 'Big brake pumps worked by a whole watch.'],
      ['copper-chain-pumps', 'Copper Chain Pumps', r('greenheart 3, copper 4, brass-ingots 2, hides 1'), 'Copper chain pumps: the best made.'] ],
    t2: ['bentinck-pumps', 'Bentinck Chain Pumps', r('greenheart 4, copper 5, brass-ingots 3, copper-sheet 2, swedish-iron 1'), 'Chain pumps of the improved pattern, worked by fewer hands and moving far more water.'] },
  { base: 'Hold Frames', rack: 'low', skill: 'CARGO_STOWAGE', g1: 'hold-fittings', grades: [
    ['teak-frames', 'Teak Frames', r('teak 5, ships-nails 4, oakum 3'), 'Teak frames that stow more cargo in the same space.'],
    ['live-oak-frames', 'Live-oak Frames', r('live-oak 10, teak 4, ships-nails 5, oakum 4'), 'Live-oak frames for a tighter stow.'],
    ['knee-braced-frames', 'Knee-braced Frames', r('live-oak 14, naval-timber 4, lignum-vitae 6, oakum 6'), 'Frames braced with knees, so the cargo space can be opened up.'],
    ['greenheart-frames', 'Greenheart Frames', r('greenheart 20, naval-timber 6, lignum-vitae 8, copper-sheet 6'), 'Greenheart frames: the most cargo space a hull can give.'] ],
    t2: ['orlop-stowage', 'Orlop Stowage', r('naval-timber 10, greenheart 20, copper-sheet 10, swedish-iron 2'), 'An orlop deck laid over greenheart frames so cargo stows on two levels: the most cargo space a hull can give, and a slower ship.'] },
  { base: 'Figurehead', rack: 'flourish', skill: null, g1: 'figurehead', grades: [
    ['carved-figurehead', 'Carved Oak Figurehead', r('timber 4, tallow 1, lead 1'), "A carved oak figurehead. It moves no number; it is the ship's face."],
    ['painted-figurehead', 'Painted Teak Figurehead', r('teak 3, cedar 2, tallow 1'), 'A painted teak figurehead. It moves no number; the crew are proud of it.'],
    ['gilded-figurehead', 'Gilded Figurehead', r('cedar 4, gold-thread 1, vermilion 1'), 'A gilded figurehead. It moves no number; every port knows the ship by it.'],
    ['royal-figurehead', 'Royal Figurehead', r('sandalwood 3, gold 1, vermilion 1'), 'A royal figurehead in sandalwood and gold. It moves no number; it is a statement.'] ] },
]

/**
 * S13 (migration 0158, §6.1 / §6.5): WHAT WORKS A BASE TYPE — the ONE table of it, by base type, so every
 * grade of a type answers alike. `trigger` is the sea event the piece answers to: it WEARS by it
 * (§6.5 — MILES: canvas, rigging and the lookouts, gear_wear_per_1000nm a thousand miles; PIRATES: the
 * High rack, gear_wear_per_fight a PIRATES day; STORM: the Low rack and the Mid hull-keeping gear,
 * gear_wear_per_storm a STORM day), and an ACTIVE module (§6.1) acts on it — so an active's trigger is a
 * day (PIRATES or STORM), never MILES. null: the piece never wears (the figurehead; every refit).
 * `consumes` = what an active spends from the cargo each time it acts (§6.1: long guns a shot-and-ball and
 * a gunpowder a fight; pumps and storm canvas nothing but hands). Recorded only: nothing reads attack,
 * armour or a trigger in a roll until SHIPS_AND_GEAR S4 and the hazard re-cut.
 */
const GUN_SHOT = [{ good: 'shot-and-ball', qty: 1 }, { good: 'gunpowder', qty: 1 }]
export const USE_BY_BASE = {
  'Long Guns': { trigger: 'PIRATES', consumes: GUN_SHOT },
  'Carronades': { trigger: 'PIRATES', consumes: GUN_SHOT },
  'Chase Guns': { trigger: 'PIRATES', consumes: GUN_SHOT },
  'Swivel Guns': { trigger: 'PIRATES', consumes: GUN_SHOT },
  'Boarding Gear': { trigger: 'PIRATES', consumes: [] },
  'Powder Magazine': { trigger: 'PIRATES', consumes: [] },
  'Sails': { trigger: 'MILES', consumes: [] },
  'Headsails': { trigger: 'MILES', consumes: [] },
  'Studding Sails': { trigger: 'MILES', consumes: [] },
  'Storm Canvas': { trigger: 'STORM', consumes: [] },
  'Rudder': { trigger: 'STORM', consumes: [] },
  'Whipstaff': { trigger: 'STORM', consumes: [] },
  'Anchor': { trigger: 'STORM', consumes: [] },
  'Sheet Anchor': { trigger: 'STORM', consumes: [] },
  'Capstan': { trigger: 'STORM', consumes: [] },
  'Lookout': { trigger: 'MILES', consumes: [] },
  'Binnacle & Charts': { trigger: 'MILES', consumes: [] },
  'Ballast': { trigger: 'STORM', consumes: [] },
  'Sheathing': { trigger: 'STORM', consumes: [] },
  'Planking': { trigger: 'STORM', consumes: [] },
  'Bilge Pumps': { trigger: 'STORM', consumes: [] },
  'Hold Frames': { trigger: 'STORM', consumes: [] },
  'Figurehead': { trigger: null, consumes: [] },
  'Kit': { trigger: null, consumes: [] },
}
export const TRIGGERS = ['MILES', 'PIRATES', 'STORM']

/**
 * S13 (migration 0158, §6.8): THE REFITS — EVE's rigs. Fitted only at a build yard, into the Refit rack;
 * cost no Deck or Hands; never wear; DESTROYED when removed (public.unmount_fitting, 0132). Refit I needs
 * Refitting I, Refit II needs Refitting V. §6.8 lists eight; SEVEN are here — Shallow Keel is not: its buy
 * is a LOWER draft (a negative delta, against 0074's buys-one-spends-one rule) and nothing in the game reads
 * draft as a gate since 0139 ("any hull enters any harbour"), so it would cost cargo space for nothing.
 * [code stem, name, slot (the item's TYPE word), buys, spends, note, [effects I], [effects II], [good a, good b]]
 */
export const REFITS = [
  ['fine-lines', 'Fine Lines', 'hull', 'Speed', 'Cargo space', 'The hull is faired to finer lines: faster through the water, with less room inside.',
    [['speed', 0.2], ['hold', -15]], [['speed', 0.35], ['hold', -20]], ['live-oak', 'lignum-vitae']],
  ['extended-hold', 'Extended Hold', 'hull', 'Cargo space', 'Handling', 'The cargo space is opened up and lengthened: more cargo, and a ship slower to answer the helm.',
    [['hold', 30], ['handling', -6]], [['hold', 50], ['handling', -8]], ['timber', 'ships-nails']],
  ['doubled-frames', 'Doubled Frames', 'hull', 'Hull', 'Speed', 'Every frame is doubled: the hull takes far more punishment and sits a little heavier.',
    [['durability', 200], ['speed', -0.15]], [['durability', 320], ['speed', -0.2]], ['naval-timber', 'live-oak']],
  ['raised-forecastle', 'Raised Forecastle', 'hull', 'Armour', 'Handling', 'A high, stout forecastle that shelters the crew and catches the wind.',
    [['armour', 8], ['handling', -5]], [['armour', 14], ['handling', -6]], ['timber', 'oakum']],
  ['lateen-rerig', 'Lateen Re-rig', 'rig', 'Handling', 'Speed', 'The ship is re-rigged with lateen sails: it turns and points higher, and runs a little slower.',
    [['handling', 10], ['speed', -0.1]], [['handling', 16], ['speed', -0.1]], ['hemp', 'naval-timber']],
  ['pierced-gun-deck', 'Pierced Gun Deck', 'weapon', 'Attack', 'Hull', 'A gun deck is cut through the side: more guns bear, and the hull is weaker for it.',
    [['attack', 40], ['durability', -100]], [['attack', 70], ['durability', -120]], ['timber', 'bar-iron']],
  ['lookout-refit', 'Lookout Top', 'lookout', 'Sighting', 'Handling', 'A permanent lookout top high on the mainmast: the horizon moves out, and the ship is a little tender.',
    [['sighting', 2], ['handling', -2]], [['sighting', 4], ['handling', -2]], ['riga-mast', 'cordage']],
]
/** A refit's two levels: I (grade 1, Refitting I, made at a tier-2 workshop) and II (grade 2, Refitting V, tier 3). */
const REFIT_LEVELS = [
  { g: 1, roman: 'I', skillLevel: 1, wsTier: 2, volume: 4, qty: [8, 4] },
  { g: 2, roman: 'II', skillLevel: 5, wsTier: 3, volume: 5, qty: [14, 8] },
]
const REFIT_COUNT = REFITS.length * REFIT_LEVELS.length

/** One effect at grade g: buys × the grade's multiplier (gentler for speed / hold), spends × 1. */
export function gradedDelta(stat, delta, g) {
  if (delta < 0) return delta
  const v = delta * (MONEY_STATS.has(stat) ? MONEY_MULT[g] : GRADE_MULT[g])
  return stat === 'speed' ? round2(v) : roundUp(v)
}

/**
 * S15 (migration 0159, §6.2's T2 row): the ONE map from a module skill to the specialisation that gates its
 * T2 module (§5.2: Gunnery Spec gates T2 guns, boarding and magazines; Ship Handling Spec the Mid handling
 * modules; Rigging / Instrument Spec the sails / instruments; Shipwright Spec the Low; Stowage Spec hold frames).
 */
export const T2_SPEC = {
  GUNNERY: 'GUNNERY_SPEC', BOARDING: 'GUNNERY_SPEC', RIGGING: 'RIGGING_SPEC', SEAMANSHIP: 'HANDLING_SPEC',
  LOOKOUTS: 'INSTRUMENT_SPEC', INSTRUMENTS: 'INSTRUMENT_SPEC', SHIPWRIGHT: 'SHIPWRIGHT_SPEC', CARGO_STOWAGE: 'STOWAGE_SPEC',
}
export const T2_MULT = { buys: 2.6, money: 1.8, spends: 1.25 }
/** One effect of a T2 (meta 5): buys × 2.60 (speed / hold × 1.80), spends × 1.25 rounded half AWAY from zero. */
export function t2Delta(stat, delta) {
  if (delta < 0) return -(stat === 'speed' ? round2(-delta * T2_MULT.spends) : roundUp(-delta * T2_MULT.spends))
  const v = delta * (MONEY_STATS.has(stat) ? T2_MULT.money : T2_MULT.buys)
  return stat === 'speed' ? round2(v) : roundUp(v)
}

/**
 * S15 (migration 0159, §6.2's Named row): a city's own pattern of ONE grade of ONE base type — one per city
 * with a tier-3 workshop (0068: 12 cities). [code, name, port code, base type, grade, the extra good, note].
 */
export const NAMED = [
  ['lisbon-cast-brass-guns', 'Lisbon-cast Brass Guns', 'LIS', 'Long Guns', 3, 'slow-match', 'Brass guns cast in the Lisbon foundry and proved with slow-match: a little more weight of fire than other brass guns.'],
  ['arsenale-rudder', 'Arsenale Rudder & Helm', 'VEN', 'Rudder', 3, 'brass-ingots', 'A teak rudder hung on brass pintles in the Venetian Arsenale way: the ship turns a little sharper.'],
  ['genoese-anchor', 'Genoese Anchor & Cable', 'GOA', 'Anchor', 3, 'hemp', 'A bar-iron anchor on a cable laid from Ligurian hemp as well as Manila: the ship rides easier and swings quicker.'],
  ['antwerp-duck-canvas', 'Antwerp Duck Canvas', 'ARP', 'Sails', 3, 'holland-linen', 'Duck canvas lined with Flemish linen at the seams, as the Antwerp sailmakers cut it: a little more speed from the same wind.'],
  ['elbe-frames', 'Elbe Frames', 'HAM', 'Hold Frames', 3, 'memel-fir', 'Live-oak frames with Memel fir ceiling between them, Hamburg fashion: a little more cargo space in the same hull.'],
  ['hanseatic-capstan', 'Hanseatic Capstan', 'LUB', 'Capstan', 3, 'osmund-iron', 'A teak capstan with osmund-iron pawls, as the Lubeck yards fit it: the anchor and yards come up a little faster.'],
  ['danzig-oak-planking', 'Danzig Oak Planking', 'GDA', 'Planking', 2, 'pine-pitch', 'Doubled planking of the straight Polish oak Gdansk ships, payed with pine pitch: a little stronger than other oak.'],
  ['london-pattern-chasers', 'London-pattern Chasers', 'LON', 'Chase Guns', 3, 'gunpowder', 'Brass chasers bored to the London pattern and proved with English powder: they reach and aim a little further.'],
  ['provencal-headsails', 'Provencal Jib & Staysail', 'MRS', 'Headsails', 3, 'linseed', 'A duck jib and staysail dressed with linseed oil, as the Marseille sailmakers do: the ship answers the helm a little quicker.'],
  ['surat-teak-sheathing', 'Surat Teak Sheathing', 'SRT', 'Sheathing', 3, 'coir', 'Teak and copper over a bed of coir caulking, as the Surat yards lay it: a little more armour and hull from the same bottom.'],
  ['malabar-chain-pumps', 'Malabar Chain Pumps', 'KOC', 'Bilge Pumps', 3, 'coco-fibre', 'Teak chain pumps with coco-fibre packing, Kochi fashion: they keep a little more water down.'],
  ['callao-copper-ballast', 'Callao Copper-pig Ballast', 'CLL', 'Ballast', 3, 'chilean-copper', 'Pig-iron ballast topped with copper pigs from the Callao quay: a little stiffer and steadier than plain pig iron.'],
]
export const NAMED_MULT = 1.1
/** One effect of a Named (meta 1): the grade's effect with buys × 1.10 (half up; speed to 0.01), spends as they are. */
export function namedDelta(stat, gradeDelta) {
  if (gradeDelta < 0) return gradeDelta
  const v = gradeDelta * NAMED_MULT
  return stat === 'speed' ? round2(v) : roundUp(v)
}

/**
 * S16 (migration 0163, §6.2's Country row, §6.7): THE SETS — one per line, four pieces: a High, a Mid and a
 * Low piece, each the Country rung of a base type of that rack, and a Figurehead. A piece is
 * [base type, code, name, recipe, second buy [stat, delta], note]; the figurehead [code, name, recipe, note].
 * The four of §6.4 are verbatim (ENG High, FRA Mid, NLD Low, KOR Low); the rest follow the line's character
 * (data/ship-lines.json) and are made of the line's own goods plus the family's materials.
 */
export const COUNTRY = [
  { line: 'PRT', set: 'Carreira da Índia',
    high: ['Chase Guns', 'bombardas-de-caca', 'Bombardas de Caça', r('culverin 6, swedish-iron 6, shot-and-ball 4, cork 4'), ['attack', 20],
      'Bow and stern chasers of the India run, wadded with Portuguese cork: they reach further, aim truer and hit harder too.'],
    mid: ['Lookout', 'gavea-da-carreira', 'Gávea da Carreira', r('riga-mast 3, portolan-charts 2, lodestone 1, cordage 4'), ['speed', 0.1],
      'A high fighting top with a Portuguese portolan and compass in it: the lookout sees further and the ship finds the wind sooner.'],
    low: ['Ballast', 'lastro-de-sal', 'Lastro de Sal', r('salt 20, iron 6, timber 2'), ['hold', 5],
      'Setúbal salt packed over iron kentledge: a stiff, steady ship, and the salt sells at the far end, so it counts as a little cargo space.'],
    figurehead: ['armillary-figurehead', 'Armillary Sphere Figurehead', r('timber 4, armillary-spheres 1, gold 1'),
      'An armillary sphere at the bow, the mark of the Portuguese crown. It moves no number; it completes the set.'] },
  { line: 'ESP', set: 'Flota de Indias',
    high: ['Boarding Gear', 'armas-del-tercio', 'Armas del Tercio', r('toledo-blades 6, swedish-iron 4, abaca 4, armour 2'), ['armour', 4],
      'Toledo blades, pikes and breastplates for a boarding party of soldiers: a harder blow across the rail, and the breastplates count on deck too.'],
    mid: ['Sheet Anchor', 'ancla-de-la-esperanza', 'Ancla de la Esperanza', r('swedish-iron 8, abaca 8, tar 2'), ['armour', 4],
      'The great anchor of the treasure fleets, chained along an iron-bound side: the ship rides out the worst night and the chain plates stop a little shot.'],
    low: ['Planking', 'tablazon-de-galeon', 'Tablazón de Galeón', r('live-oak 16, naval-timber 6, ships-nails 8, oakum 4, pine-pitch 2'), ['sighting', 2],
      'Doubled live-oak planking carried up into high sides: far more hull and armour, a slower ship, and a lookout a little higher above the water.'],
    figurehead: ['castile-lion-figurehead', 'León de Castilla Figurehead', r('timber 4, vermilion 1, gold 1'),
      'A crowned lion of Castile in red and gold. It moves no number; it completes the set.'] },
  { line: 'NLD', set: 'VOC Return Fleet',
    high: ['Swivel Guns', 'voc-swivels', 'VOC Draaibassen', r('swedish-iron 5, brass-ingots 3, shot-and-ball 2, holland-linen 2'), ['hold', 5],
      'Light rail guns of the Dutch East India Company with linen cartridges made up in advance: they sweep a deck and leave a little more cargo space than heavier metal would.'],
    mid: ['Capstan', 'fluit-kaapstander', 'Fluit Kaapstander', r('live-oak 4, swedish-iron 3, abaca 3, stockholm-tar 1'), ['durability', 40],
      'A geared capstan built for a small crew: the anchor and yards come up fast with few hands, and the ship meets a squall with sail already off.'],
    low: ['Hold Frames', 'voc-frames', 'VOC Frames', r('memel-fir 30, norway-spruce 20, oakum 6'), ['speed', 0.17],
      'Light fir frames and ceiling in the Dutch way: nearly the most cargo space a hull can give, at half the usual cost in speed.'],
    figurehead: ['holland-lion-figurehead', 'Leeuw van Holland Figurehead', r('timber 4, ochre 1, lead 1'),
      'The lion of Holland in red and gold paint. It moves no number; it completes the set.'] },
  { line: 'ENG', set: 'Sea Dogs',
    high: ['Long Guns', 'sea-dogs-culverins', "Sea Dogs' Culverin Battery", r('culverin 14, tin-ingots 6, oakum 4'), ['accuracy', 10],
      'A full battery of English culverins on truck carriages: they hit hard, reach far and shoot straighter than any plain battery.'],
    mid: ['Headsails', 'race-built-headsails', 'Race-built Headsails', r('sailcloth 8, riga-mast 2, abaca 4, tar 1'), ['accuracy', 6],
      'Headsails cut for a race-built hull: the ship turns smartly, gains a little way, and keeps a steadier gun platform through the turn.'],
    low: ['Sheathing', 'admiralty-copper', 'Admiralty Copper', r('copper-sheet 14, tin-ingots 4, ships-nails 6, tar 2'), ['handling', 4],
      'Copper sheathing to the Admiralty pattern over a clean bottom: more armour and hull, and a ship that answers the helm a little quicker.'],
    figurehead: ['sea-dog-figurehead', 'Sea Dog Figurehead', r('timber 4, tallow 1, lead-white 1'),
      'A carved and painted sea dog at the bow. It moves no number; it completes the set.'] },
  { line: 'FRA', set: 'Ponant',
    high: ['Powder Magazine', 'sainte-barbe-du-ponant', 'Sainte-Barbe du Ponant', r('gunpowder 10, live-oak 4, copper-sheet 4, lead 2'), ['reach', 6],
      'A copper-lined powder room stocked with fine French powder: steadier and more accurate fire, and the charge carries a little further.'],
    mid: ['Sails', 'toiles-de-bretagne', 'Toiles de Bretagne', r('canvas-duck 30, sailcloth 8, hemp 6'), ['handling', 4],
      'Breton duck canvas cut full and flat: a great deal more speed from the same wind, and the suit costs only half the usual handling.'],
    low: ['Bilge Pumps', 'pompes-du-ponant', 'Pompes du Ponant', r('live-oak 4, copper 3, hides 2, canvas-duck 4'), ['handling', 4],
      'Chain pumps with canvas hoses that keep the bilge dry: the hull takes far more punishment, and a dry ship answers the helm a little quicker.'],
    figurehead: ['fleur-de-lis-figurehead', 'Fleur-de-lis Figurehead', r('timber 4, gold-thread 1, ultramarine 1'),
      'A gilded fleur-de-lis on a blue ground. It moves no number; it completes the set.'] },
  { line: 'ITA', set: 'Arsenale',
    high: ['Carronades', 'petrieri', "Petrieri dell'Arsenale", r('culverin 6, brass-ingots 6, gunpowder 3, marble 4'), ['accuracy', 6],
      'Short brass stone-throwers of the Venetian Arsenal, bored true: they smash at close range and aim better than most short guns.'],
    mid: ['Whipstaff', 'agghiaccio', "Agghiaccio dell'Arsenale", r('live-oak 4, naval-timber 1, swedish-iron 1, hemp 1'), ['speed', 0.1],
      'A long steering lever in the Venetian pattern: the ship answers the helm at once and wanders less, so it keeps a little more way on.'],
    low: ['Ballast', 'zavorra-dell-arsenale', "Zavorra dell'Arsenale", r('lead 8, iron 6, marble 4, oakum 2'), ['attack', 15],
      'Lead and marble ballast trimmed by the Arsenal for a steady gun platform: a stiffer ship, and the bow guns tell harder.'],
    figurehead: ['san-marco-lion-figurehead', 'Leone di San Marco Figurehead', r('timber 4, gold 1, murano-glass 1'),
      'The winged lion of St Mark in gilt, with glass eyes from Murano. It moves no number; it completes the set.'] },
  { line: 'OTT', set: 'Kapudan',
    high: ['Long Guns', 'sahi-guns', 'Şahi Guns', r('bombard 2, culverin 8, copper 8, tin-ingots 4'), ['armour', 4],
      'Heavy bronze guns of the Tersane-i Amire behind stout bulwarks: a hard-hitting broadside, and the gun deck takes a little more shot.'],
    mid: ['Anchor', 'tersane-anchor', 'Tersane Anchor & Cable', r('swedish-iron 5, abaca 5, hemp 3, cedar 2'), ['durability', 40],
      'Ground tackle from the Imperial Arsenal on a cedar-stocked anchor: the ship turns around quicker in port and rides easier at anchor, which spares the hull.'],
    low: ['Planking', 'cedar-planking', 'Cedar Planking', r('cedar 16, naval-timber 4, ships-nails 8, oakum 4'), ['handling', 4],
      'Doubled planking of Anatolian cedar, lighter than oak: far more hull and armour for a slower ship, and the lighter wood leaves it a little handier.'],
    figurehead: ['crescent-figurehead', "Kapudan's Crescent Figurehead", r('cedar 4, gold-thread 1, iznik-tiles 1'),
      'A gilded crescent and star over Iznik tilework at the bow. It moves no number; it completes the set.'] },
  { line: 'IND', set: 'Monsoon',
    high: ['Boarding Gear', 'malabar-boarding-gear', 'Malabar Boarding Gear', r('talwar 4, swedish-iron 3, coir 4, teak 2'), ['handling', 4],
      'Talwars, coir grapnel lines and boarding ladders in the Malabar way: a hard blow across the rail from a light, handy ship.'],
    mid: ['Binnacle & Charts', 'rahmani-and-kamal', 'Rahmani & Kamal', r('lodestone 2, sea-charts 3, teak 2, brass-ingots 1'), ['speed', 0.1],
      'An Arab pilot book and a kamal for the star heights beside a lodestone compass: the ship knows where it is, answers the helm well and picks the better wind.'],
    low: ['Sheathing', 'monsoon-teak-sheathing', 'Monsoon Teak Sheathing', r('teak 10, copper-sheet 8, coir 6, coco-fibre 4'), ['hold', 6],
      'Teak and copper over coir caulking, sewn and nailed as the monsoon yards do it: more armour and hull, and the lighter build leaves a little more cargo space.'],
    figurehead: ['makara-figurehead', 'Monsoon Makara Figurehead', r('teak 4, sandalwood-carving 1, vermilion 1'),
      'A carved makara, the sea creature of the monsoon coasts, in sandalwood and red. It moves no number; it completes the set.'] },
  { line: 'CHN', set: 'Ming Treasure',
    high: ['Powder Magazine', 'fire-lance-magazine', 'Fire-lance Magazine', r('gunpowder 10, rocket-tubes 4, fire-lance 4, copper-sheet 4'), ['armour', 4],
      'A powder room stocked with rockets and fire-lances behind a watertight bulkhead: steadier and more accurate fire, and the bulkhead counts as armour.'],
    mid: ['Rudder', 'fenestrated-rudder', 'Fenestrated Rudder', r('live-oak 6, teak 2, iron 4, abaca 2'), ['durability', 40],
      'A deep junk rudder pierced with holes, raised and lowered on tackles: the ship turns sharply and the rudder shrugs off seas that would unship another.'],
    low: ['Hold Frames', 'treasure-junk-bulkheads', 'Treasure Junk Bulkheads', r('live-oak 14, teak 6, iron 6, oakum 6'), ['durability', 50],
      'Watertight bulkheads in the Ming way: the cargo stows in sealed compartments, so there is more room for it and one leak never sinks the ship.'],
    figurehead: ['dragon-eye-figurehead', 'Dragon-eye Figurehead', r('timber 4, lacquerware 1, vermilion 1'),
      'Painted eyes on the bow in red lacquer, as every junk carries. It moves no number; it completes the set.'] },
  { line: 'JPN', set: 'Red Seal',
    high: ['Swivel Guns', 'ozutsu-swivels', 'Ōzutsu Swivels', r('swedish-iron 4, culverin 2, matchlocks 2, shot-and-ball 2'), ['reach', 6],
      'Heavy Japanese hand cannon on the rails, served by matchlock men: they sweep a deck, shoot straight and reach a little further than a plain swivel.'],
    mid: ['Storm Canvas', 'typhoon-canvas', 'Typhoon Canvas', r('sailcloth 8, cotton-cloth 6, hemp 4, tar 2'), ['accuracy', 6],
      'Small, heavy sails of cotton and sailcloth for typhoon weather: the ship rides out the storm, gives up a little speed and keeps a steadier gun platform.'],
    low: ['Ballast', 'red-seal-ballast', 'Red Seal Ballast', r('japan-copper 8, iron 4, timber 2'), ['accuracy', 6],
      'Copper pigs from the Japanese mines stowed low as ballast: a stiff, steady ship, and the guns shoot straighter for it.'],
    figurehead: ['red-seal-figurehead', 'Red Seal Figurehead', r('timber 4, lacquerware 1, gold 1'),
      'The red seal of the shogunate in lacquer and gold leaf at the bow. It moves no number; it completes the set.'] },
  { line: 'KOR', set: 'Yi Sun-sin',
    high: ['Chase Guns', 'cheonja-chongtong', 'Cheonja Chongtong', r('culverin 8, copper 6, tin-ingots 4, rocket-tubes 2'), ['attack', 20],
      'Heavy Korean bronze cannon in the bows that fire great arrows as well as shot: they reach and aim further than a broadside gun and hit harder than most chasers.'],
    mid: ['Sails', 'ramie-sails', 'Ramie Sails', r('ramie-korea 20, hemp-cloth 8, cordage 4'), ['durability', 40],
      'Battened sails of Korean ramie and hemp cloth: more speed from the same wind, harder to handle, and the cloth stands weather that tears flax.'],
    low: ['Planking', 'turtle-back-plating', 'Turtle-back Plating', r('iron 20, copper-sheet 10, timber 10'), ['armour', 6],
      'Iron plates spiked over a timber deck in the turtle-ship way: the best armour afloat and a far stronger hull, for a slower ship with less cargo space.'],
    figurehead: ['dragon-head-figurehead', 'Dragon-head Figurehead', r('timber 4, iron 2, vermilion 1'),
      'The dragon head of the turtle ship, carved and painted red. It moves no number; it completes the set.'] },
]
export const COUNTRY_MULT = { buys: 2.4, money: 1.7, spends: 1.0 }
/** The word a stat goes by in an item's buys sentence (docs/WORDS.md: the player never reads "hold"). */
const STAT_WORD = { attack: 'Attack', accuracy: 'Accuracy', reach: 'Reach', handling: 'Handling', speed: 'Speed', hold: 'Cargo space', durability: 'Hull', armour: 'Armour', sighting: 'Sighting' }
/**
 * The effects of a Country item (meta 6) from its G1's: buys × 2.40 (speed / hold × 1.70), spends × 1.00 (speed
 * to 0.01, every other stat half up), then the line's second buy (always > 0) — appended; or, where its stat is one
 * the G1 already moves (item_effects keeps ONE row per stat), folded into that row by the sum: a lighter spend (VOC
 * Frames: speed −0.35 + 0.17 = −0.18; Toiles de Bretagne: handling −8 + 4 = −4) or a bigger buy (Turtle-back
 * Plating: armour 24 + 6 = 30).
 */
export function countryEffects(g1Effects, [stat2, delta2]) {
  if (!(delta2 > 0)) throw new Error(`a Country second buy is positive, not ${stat2} ${delta2}`)
  const scale = (stat, delta) => {
    if (delta < 0) return -(stat === 'speed' ? round2(-delta * COUNTRY_MULT.spends) : roundUp(-delta * COUNTRY_MULT.spends))
    const v = delta * (MONEY_STATS.has(stat) ? COUNTRY_MULT.money : COUNTRY_MULT.buys)
    return stat === 'speed' ? round2(v) : roundUp(v)
  }
  const effects = g1Effects.map(([stat, delta]) => ({ stat, delta: scale(stat, delta) }))
  const row = effects.find((e) => e.stat === stat2)
  if (row) row.delta = stat2 === 'speed' ? round2(row.delta + delta2) : row.delta + delta2
  else effects.push({ stat: stat2, delta: delta2 })
  return effects
}

/**
 * S16 (migration 0163, §6.6): THE PERK KITS — made items that augment a fitting at a tier-3 workshop and are used
 * up by it. Base type Kit, rack kit (no hull has a place in it); no effect, no requirement. [code, name, recipe, note].
 */
export const KIT_BASE = 'Kit'
export const KITS = [
  ['gunsmiths-kit', "Gunsmith's Kit", r('swivel-gun 1, slow-match 2, gunpowder 2'), "A gunsmith's tools and stores for augmenting a High-rack fitting at a tier-3 workshop; the kit is used up by it."],
  ['sailmakers-kit', "Sailmaker's Kit", r('sailcloth 4, whale-bone-stays 2, abaca 3'), "A sailmaker's cloth, stays and twine for augmenting a Mid-rack fitting at a tier-3 workshop; the kit is used up by it."],
  ['shipwrights-kit', "Shipwright's Kit", r('lignum-vitae 2, copper-sheet 3, oakum 3'), "A shipwright's blocks, copper and oakum for augmenting a Low-rack fitting at a tier-3 workshop; the kit is used up by it."],
  ['navigators-kit', "Navigator's Kit", r('sea-charts 1, lodestone 1'), "A navigator's charts and lodestone for augmenting a fitting at a tier-3 workshop; the kit is used up by it."],
]

/**
 * S17 (migration 0166, §6.2's Famous row): THE GEAR OF THE ELEVEN FAMOUS SHIPS — one per hull of
 * scripts/build-ships.mjs WAVE_D. [code, name, the famous hull's code, base type, second buy [stat, delta]
 * or null, note]. The base type is one of the rack the hull's tech uplift adds a place in (trade a Low,
 * combat a High, explorer a Mid) but where §6.4 names it (the Golden Hind's culverins) — chosen here, NOT
 * the owner's: confirm.
 */
export const FAMOUS = [
  ['madre-de-deus-holds', 'Madre de Deus Holds', 'madre', 'Hold Frames', null,
    'The deep cargo space of the great carrack taken off the Azores in 1592, whose pepper, silks and jewels filled a London custom house.'],
  ['san-martin-tercio', 'San Martín Tercio Arms', 'sanmartin', 'Boarding Gear', null,
    'The pikes, grapnels and breastplates of the soldiers Medina Sidonia carried in his flagship in 1588, ready to board.'],
  ['batavia-double-planking', 'Batavia Double Planking', 'batavia', 'Planking', null,
    'The doubled planking of the Dutch East India ship lost on the Abrolhos in 1629, laid two skins deep for the long voyage east.'],
  ['drakes-culverins', "Drake's Culverins", 'goldenhind', 'Long Guns', ['accuracy', 12],
    'The culverins Francis Drake carried round the world in 1577-1580: they hit harder, reach further and shoot straighter than any battery.'],
  ['couronne-battery', 'La Couronne Battery', 'couronne', 'Long Guns', null,
    'The great battery of the first French ship of the line, launched at La Roche-Bernard in 1636.'],
  ['duodo-bow-guns', 'Duodo Bow Guns', 'duodo', 'Chase Guns', null,
    'The heavy bow guns of the Venetian galleasses Francesco Duodo led at Lepanto in 1571, which broke the Ottoman line before it closed.'],
  ['turgut-reis-swivels', 'Turgut Reis Swivels', 'turgut', 'Swivel Guns', null,
    'The rail swivels of the corsair admiral Turgut Reis, which swept a Christian deck before his men went over the side.'],
  ['rahimi-pilgrim-holds', 'Rahimi Pilgrim Holds', 'rahimi', 'Hold Frames', null,
    "The vast cargo space of the Mughal queen mother's pilgrim ship, the largest in the Red Sea trade until the Portuguese burned it in 1614."],
  ['zheng-he-bulkheads', 'Zheng He Bulkheads', 'baochuan', 'Planking', null,
    "The watertight bulkheads and layered planking of Zheng He's treasure ships, which sailed as far as Africa between 1405 and 1433."],
  ['date-masamune-charts', 'Date Masamune Charts', 'sjb', 'Binnacle & Charts', null,
    'The binnacle and Pacific charts of the galleon Date Masamune sent to Acapulco in 1613 with Hasekura Tsunenaga on board.'],
  ['dragon-head-cannon', 'Dragon-head Cannon', 'geobuk', 'Carronades', null,
    "The cannon fired through the dragon's mouth of Yi Sun-sin's turtle ship, which smashed Japanese hulls at close range in 1592."],
]
export const FAMOUS_MULT = { buys: 3, money: 2, deckHands: 1.6, recipe: 1.5 }
/** 0184: whether a workshop makes the Famous pieces. The owner (2026-10-18): later, and how they are won he
 *  will set. False writes every Famous `made: false` (public.item_unmade), so none is made and no famous hull
 *  is laid down. */
export const FAMOUS_MADE = false
/** One effect of a Famous (meta 8): buys × 3.00 (speed / hold × 2.00; half up, speed to 0.01), spends × 1.00. */
export function famousDelta(stat, delta) {
  if (delta < 0) return delta
  const v = delta * (MONEY_STATS.has(stat) ? FAMOUS_MULT.money : FAMOUS_MULT.buys)
  return stat === 'speed' ? round2(v) : roundUp(v)
}

/** THE GENERATOR. Pure but for reading data/*.json; throws on any broken rule. */
export function generateGear() {
  const fittings = Object.fromEntries(readJson('data/fittings.json').fittings.map((f) => [f.code, f]))
  const profiles = Object.fromEntries(readJson('data/gear.json').items.map((i) => [i.code, i]))
  const goods = new Set(readJson('data/goods.json').goods.map((g) => g.id))
  const skills = new Set(readJson('data/skills.json').skills.map((s) => s.code))
  const STATS = new Set(['hold', 'speed', 'handling', 'draft', 'durability', 'armour', 'attack', 'accuracy', 'reach', 'sighting'])
  const items = []
  const codes = new Set(Object.keys(fittings))
  const names = new Set(Object.values(fittings).map((f) => f.name.toLowerCase()))
  if (BASE_TYPES.length !== 23) throw new Error(`§6.3 lists 23 base types (12 live + 11 new); the table has ${BASE_TYPES.length}`)

  // S13: every base type answers to exactly one entry of USE_BY_BASE (S16: and the kits' Kit), and nothing else is in it
  const bases = new Set([...BASE_TYPES.map((b) => b.base), KIT_BASE])
  for (const b of bases) if (!(b in USE_BY_BASE)) throw new Error(`${b}: no entry in USE_BY_BASE (what wears it, what it consumes)`)
  for (const b of Object.keys(USE_BY_BASE)) if (!bases.has(b)) throw new Error(`USE_BY_BASE names ${b}, which is no base type`)
  /** S13: what works an item of base type `base` (active or not), checked against §6.1's rules. */
  const useOf = (code, base, active) => {
    const u = USE_BY_BASE[base]
    if (u.trigger !== null && !TRIGGERS.includes(u.trigger)) throw new Error(`${code}: trigger ${u.trigger}`)
    if (active && !['PIRATES', 'STORM'].includes(u.trigger)) throw new Error(`${code}: an active module acts on a PIRATES or STORM day, not on ${u.trigger}`)
    if (!active && u.consumes.length) throw new Error(`${code}: only an active module consumes anything`)
    for (const c of u.consumes) if (!goods.has(c.good) || !(c.qty > 0)) throw new Error(`${code}: consumes ${c.good} ${c.qty}`)
    return { trigger: u.trigger, consumes: u.consumes }
  }
  const use = []
  for (const [code, p] of Object.entries(profiles)) use.push({ code, ...useOf(code, p.baseType, p.active) })
  const g1ByBase = {}                       // S15: the T2 of a base type is cut from its G1
  const gradeItem = {}                      // S15: `${base}#${grade}` → the generated row the Named is a pattern of

  for (const b of BASE_TYPES) {
    // G1: the live row (anchor) or the new one
    let g1
    if (typeof b.g1 === 'string') {
      const f = fittings[b.g1]
      const p = profiles[b.g1]
      if (!f || !p) throw new Error(`${b.base}: live G1 ${b.g1} is not in data/fittings.json + data/gear.json`)
      if (p.baseType !== b.base || p.rack !== b.rack || p.grade !== 1) throw new Error(`${b.base}: the live G1 ${b.g1} is profiled ${p.baseType} / ${p.rack} / G${p.grade}`)
      g1 = { code: f.code, name: f.name, slot: f.slot, buys: f.buys, spends: f.spends, volume: f.volume, wsTier: f.ws_tier,
        deck: p.deck, hands: p.hands, active: p.active, effects: (f.effects ?? []).map((e) => [e.stat, e.delta]), live: true }
    } else {
      g1 = { ...b.g1, live: false }
    }
    g1ByBase[b.base] = g1
    const ladder = [[1, g1.code, g1.name, g1.recipe, g1.note], ...b.grades.map((x, i) => [i + 2, ...x])]
    for (const [g, code, name, recipe, note] of ladder) {
      if (g === 1 && g1.live) continue          // the live twelve are not re-written: their rows are 0068 / 0074 / 0132's
      if (g > 1 && codes.has(code)) throw new Error(`${code}: a second item of that code`)
      if (g > 1 || !g1.live) {
        if (codes.has(code) && g > 1) throw new Error(`${code}: duplicate`)
        if (names.has(name.toLowerCase())) throw new Error(`${name}: a second item of that name`)
      }
      codes.add(code)
      names.add(name.toLowerCase())
      if (!/^[a-z][a-z0-9-]+$/.test(code)) throw new Error(`${code}: not a code`)
      if (note.length <= 12) throw new Error(`${code}: note too short`)
      if (recipe.length < 2 || recipe.length > 5) throw new Error(`${code}: a recipe is 2-5 goods (0068), not ${recipe.length}`)
      for (const x of recipe) if (!goods.has(x.in)) throw new Error(`${code}: good ${x.in} is not in data/goods.json`)
      const effects = g1.effects.map(([stat, delta]) => ({ stat, delta: gradedDelta(stat, delta, g) }))
      for (const e of effects) if (!STATS.has(e.stat) || e.delta === 0) throw new Error(`${code}: effect ${e.stat} ${e.delta}`)
      const up = effects.some((e) => e.delta > 0)
      const down = effects.some((e) => e.delta < 0)
      if (b.base === 'Figurehead' ? effects.length !== 0 : !(up && down)) throw new Error(`${code}: every fitting buys one stat and spends another (0074); the figurehead none`)
      const requirements = []
      if (b.skill && g >= 2) requirements.push({ skill: b.skill, level: g })
      if (b.also) requirements.push({ ...b.also })
      for (const q of requirements) if (!skills.has(q.skill)) throw new Error(`${code}: skill ${q.skill} is not in data/skills.json`)
      const item = {
        code, name, slot: g1.slot, buys: g1.buys, spends: g1.spends, note, volume: g1.volume,
        wsTier: g === 1 ? g1.wsTier : g <= 3 ? Math.max(2, g1.wsTier) : 3,
        baseType: b.base, rack: b.rack, grade: g, meta: 0,
        deck: roundUp(g1.deck * (1 + 0.1 * (g - 1))), hands: roundUp(g1.hands * (1 + 0.1 * (g - 1))), active: g1.active,
        effects, recipe, requirements,
      }
      items.push(item)
      gradeItem[`${b.base}#${g}`] = item
      use.push({ code, ...useOf(code, b.base, g1.active) })
    }
  }
  if (items.length !== 103) throw new Error(`Wave A gear is 103 items (12 × G2-G5 + 11 × G1-G5); the generator made ${items.length}`)

  // S13 (§6.8): THE REFITS — rack refit, no Deck, no Hands, never wear (trigger null), passive; each buys one
  // stat and spends another (0074); Refit I needs Refitting I, II needs Refitting V.
  if (!skills.has('REFITTING')) throw new Error('REFITTING is not in data/skills.json')
  for (const [stem, base, slot, buys, spends, note, fx1, fx2, [ga, gb]] of REFITS) {
    for (const lv of REFIT_LEVELS) {
      const code = `${stem}-${lv.g}`
      const name = `${base} ${lv.roman}`
      if (codes.has(code)) throw new Error(`${code}: a second item of that code`)
      if (names.has(name.toLowerCase())) throw new Error(`${name}: a second item of that name`)
      codes.add(code)
      names.add(name.toLowerCase())
      const effects = (lv.g === 1 ? fx1 : fx2).map(([stat, delta]) => ({ stat, delta }))
      for (const e of effects) if (!STATS.has(e.stat) || e.delta === 0) throw new Error(`${code}: effect ${e.stat} ${e.delta}`)
      if (!(effects.some((e) => e.delta > 0) && effects.some((e) => e.delta < 0))) throw new Error(`${code}: every fitting buys one stat and spends another (0074)`)
      for (const g of [ga, gb]) if (!goods.has(g)) throw new Error(`${code}: good ${g} is not in data/goods.json`)
      items.push({
        code, name, slot, buys, spends, note, volume: lv.volume, wsTier: lv.wsTier,
        baseType: base, rack: 'refit', grade: lv.g, meta: 0, deck: 0, hands: 0, active: false,
        effects, recipe: [{ in: ga, qty: lv.qty[0] }, { in: gb, qty: lv.qty[1] }],
        requirements: [{ skill: 'REFITTING', level: lv.skillLevel }],
      })
      use.push({ code, trigger: null, consumes: [] })
    }
  }
  if (items.length !== 103 + REFIT_COUNT) throw new Error(`the gear is 103 Wave A items + ${REFIT_COUNT} refits; the generator made ${items.length}`)

  // S15 (§6.2's T2 row): ONE T2 per base type but the figurehead — t2Delta over the G1's effects, Deck and
  // Hands × 1.5, the module skill V + its specialisation I (+ the base type's second skill), tier 3.
  for (const [skill, spec] of Object.entries(T2_SPEC)) {
    if (!skills.has(skill)) throw new Error(`T2_SPEC: skill ${skill} is not in data/skills.json`)
    if (!skills.has(spec)) throw new Error(`T2_SPEC: specialisation ${spec} is not in data/skills.json`)
  }
  const take = (code, name) => {
    if (codes.has(code)) throw new Error(`${code}: a second item of that code`)
    if (names.has(name.toLowerCase())) throw new Error(`${name}: a second item of that name`)
    if (!/^[a-z][a-z0-9-]+$/.test(code)) throw new Error(`${code}: not a code`)
    codes.add(code)
    names.add(name.toLowerCase())
  }
  const checkRecipe = (code, recipe) => {
    if (recipe.length < 2 || recipe.length > 5) throw new Error(`${code}: a recipe is 2-5 goods (0068), not ${recipe.length}`)
    for (const x of recipe) if (!goods.has(x.in)) throw new Error(`${code}: good ${x.in} is not in data/goods.json`)
    if (new Set(recipe.map((x) => x.in)).size !== recipe.length) throw new Error(`${code}: a good twice in one recipe`)
  }
  const checkEffects = (code, effects, base = null) => {
    for (const e of effects) if (!STATS.has(e.stat) || e.delta === 0) throw new Error(`${code}: effect ${e.stat} ${e.delta}`)
    if (base === 'Figurehead' || base === KIT_BASE) { if (effects.length) throw new Error(`${code}: a ${base.toLowerCase()} moves no stat`); return }
    if (!(effects.some((e) => e.delta > 0) && effects.some((e) => e.delta < 0))) throw new Error(`${code}: every fitting buys one stat and spends another (0074)`)
  }
  const T2_COUNT = BASE_TYPES.length - 1
  for (const b of BASE_TYPES) {
    if (b.base === 'Figurehead') { if (b.t2) throw new Error('the figurehead has no T2 (it moves no stat at any rung)'); continue }
    if (!b.t2) throw new Error(`${b.base}: no T2 (every base type but the figurehead has one, §6.2)`)
    if (!b.skill || !(b.skill in T2_SPEC)) throw new Error(`${b.base}: module skill ${b.skill} has no specialisation in T2_SPEC`)
    const [code, name, recipe, note] = b.t2
    const g1 = g1ByBase[b.base]
    take(code, name)
    if (note.length <= 12) throw new Error(`${code}: note too short`)
    checkRecipe(code, recipe)
    const effects = g1.effects.map(([stat, delta]) => ({ stat, delta: t2Delta(stat, delta) }))
    checkEffects(code, effects)
    const requirements = [{ skill: b.skill, level: 5 }, { skill: T2_SPEC[b.skill], level: 1 }]
    if (b.also) requirements.push({ ...b.also })
    items.push({
      code, name, slot: g1.slot, buys: g1.buys, spends: g1.spends, note, volume: g1.volume, wsTier: 3,
      baseType: b.base, rack: b.rack, grade: 5, meta: 5,
      deck: roundUp(g1.deck * 1.5), hands: roundUp(g1.hands * 1.5), active: g1.active,
      effects, recipe, requirements,
    })
    use.push({ code, ...useOf(code, b.base, g1.active) })
  }
  if (items.length !== 103 + REFIT_COUNT + T2_COUNT) throw new Error(`the gear is 103 Wave A items + ${REFIT_COUNT} refits + ${T2_COUNT} T2; the generator made ${items.length}`)
  // §6.4's three T2 rows, verbatim
  const fx = (code) => Object.fromEntries(items.find((i) => i.code === code).effects.map((e) => [e.stat, e.delta]))
  const expectFx = (code, want) => {
    const got = fx(code)
    for (const [stat, v] of Object.entries(want)) if (got[stat] !== v) throw new Error(`§6.4: ${code} ${stat} should be ${v}, the rule gives ${got[stat]}`)
  }
  expectFx('long-eighteens', { attack: 156, reach: 39, hold: -25, handling: -8 })
  expectFx('racing-courses', { speed: 1.08, handling: -10 })
  expectFx('orlop-stowage', { hold: 45, speed: -0.44, handling: -6 })

  // S15 (§6.2's Named row): a city's own pattern of ONE grade of ONE base type — namedDelta over the grade's
  // effects, Deck −1, the grade's recipe + one good the city is known for, the grade's requirements, tier 3.
  const namedCities = new Set()
  for (const [code, name, city, base, grade, extra, note] of NAMED) {
    const src = gradeItem[`${base}#${grade}`]
    if (!src) throw new Error(`${code}: no generated ${base} G${grade} to pattern (a Named is of a generated grade, never the live G1)`)
    if (!/^[A-Z]{3}$/.test(city)) throw new Error(`${code}: ${city} is not a port code`)
    if (namedCities.has(city)) throw new Error(`${code}: a second Named for ${city} (one per tier-3 city)`)
    namedCities.add(city)
    take(code, name)
    if (note.length <= 12) throw new Error(`${code}: note too short`)
    const recipe = [...src.recipe, { in: extra, qty: 1 }]
    checkRecipe(code, recipe)
    const effects = src.effects.map((e) => ({ stat: e.stat, delta: namedDelta(e.stat, e.delta) }))
    checkEffects(code, effects)
    items.push({
      code, name, slot: src.slot, buys: src.buys, spends: src.spends, note, volume: src.volume, wsTier: 3,
      baseType: base, rack: src.rack, grade, meta: 1, city,
      deck: Math.max(0, src.deck - 1), hands: src.hands, active: src.active,
      effects, recipe, requirements: src.requirements.map((q) => ({ ...q })),
    })
    use.push({ code, ...useOf(code, base, src.active) })
  }
  if (NAMED.length !== 12) throw new Error(`§6.2: one Named per tier-3 city (12); the table has ${NAMED.length}`)
  if (items.length !== 103 + REFIT_COUNT + T2_COUNT + NAMED.length) throw new Error(`the gear is 103 Wave A + ${REFIT_COUNT} refits + ${T2_COUNT} T2 + ${NAMED.length} Named = 151; the generator made ${items.length}`)
  expectFx('lisbon-cast-brass-guns', { attack: 106, reach: 26 })

  // S16 (§6.2's Country row, §6.7): THE SETS — four pieces a line, each piece the Country rung of a base type of
  // its rack: countryEffects over the G1's, Deck and Hands × 1.3, the module skill IV + the line's Medium Hulls I
  // (+ the base type's second skill), tier ≥ 2, the G1's words with the second buy's word joined to `buys` when it
  // is a new buy; the Country Figurehead moves nothing and needs the line's Medium Hulls I only. Every piece
  // carries its line and set (public.item_line).
  const lineCodes = readJson('data/ship-lines.json').lines.map((l) => l.code)
  const byBase = Object.fromEntries(BASE_TYPES.map((b) => [b.base, b]))
  if (COUNTRY.length !== lineCodes.length) throw new Error(`§6.7: one set per line (${lineCodes.length}); COUNTRY has ${COUNTRY.length}`)
  const checkNote = (code, note) => {
    if (note.length <= 12) throw new Error(`${code}: note too short`)
    if (/hold|\bshe\b|\bher\b/i.test(note)) throw new Error(`${code}: a note says "cargo space", never "hold", and names no "she" or "her"`)
  }
  const setLines = new Set()
  const setNames = new Set()
  const figurehead = g1ByBase['Figurehead']
  for (const c of COUNTRY) {
    if (!lineCodes.includes(c.line)) throw new Error(`${c.line}: not a line of data/ship-lines.json`)
    if (setLines.has(c.line) || setNames.has(c.set)) throw new Error(`${c.line} / ${c.set}: a second set for that line or of that name`)
    setLines.add(c.line)
    setNames.add(c.set)
    const hullSkill = `${c.line}_MEDIUM`
    if (!skills.has(hullSkill)) throw new Error(`${c.line}: ${hullSkill} is not in data/skills.json`)
    for (const rack of ['high', 'mid', 'low']) {
      const [base, code, name, recipe, second, note] = c[rack]
      const b = byBase[base]
      if (!b || b.rack !== rack) throw new Error(`${code}: ${base} is no base type of the ${rack} rack`)
      const g1 = g1ByBase[base]
      take(code, name)
      checkNote(code, note)
      checkRecipe(code, recipe)
      const effects = countryEffects(g1.effects, second)
      checkEffects(code, effects)
      const [stat2] = second
      const newBuy = effects.find((e) => e.stat === stat2).delta > 0 && !g1.effects.some(([s, d]) => s === stat2 && d > 0)
      const requirements = [{ skill: b.skill, level: 4 }, { skill: hullSkill, level: 1 }]
      if (b.also) requirements.push({ ...b.also })
      items.push({
        code, name, slot: g1.slot, buys: newBuy ? `${g1.buys}, ${STAT_WORD[stat2]}` : g1.buys, spends: g1.spends, note, volume: g1.volume, wsTier: 2,
        baseType: base, rack, grade: 4, meta: 6, line: c.line, set: c.set,
        deck: roundUp(g1.deck * 1.3), hands: roundUp(g1.hands * 1.3), active: g1.active,
        effects, recipe, requirements,
      })
      use.push({ code, ...useOf(code, base, g1.active) })
    }
    const [code, name, recipe, note] = c.figurehead
    take(code, name)
    checkNote(code, note)
    checkRecipe(code, recipe)
    checkEffects(code, [], 'Figurehead')
    items.push({
      code, name, slot: figurehead.slot, buys: figurehead.buys, spends: figurehead.spends, note, volume: figurehead.volume, wsTier: 2,
      baseType: 'Figurehead', rack: 'flourish', grade: 4, meta: 6, line: c.line, set: c.set,
      deck: 0, hands: 0, active: false,
      effects: [], recipe, requirements: [{ skill: hullSkill, level: 1 }],
    })
    use.push({ code, ...useOf(code, 'Figurehead', false) })
  }
  const COUNTRY_COUNT = COUNTRY.length * 4
  if (items.length !== 151 + COUNTRY_COUNT) throw new Error(`the gear is 151 items through S15 + ${COUNTRY_COUNT} Country; the generator made ${items.length}`)
  // §6.4's four Country rows, verbatim (Toiles de Bretagne's "handling +4 | handling −8" is one row, the sum)
  expectFx('sea-dogs-culverins', { attack: 144, reach: 36, accuracy: 10, hold: -20, handling: -6 })
  expectFx('toiles-de-bretagne', { speed: 1.02, handling: -4 })
  expectFx('voc-frames', { speed: -0.18, handling: -5 })
  expectFx('turtle-back-plating', { armour: 30 })

  // S16 (§6.6): THE KITS — base type Kit, rack kit, tier 3, volume 1, no effect, no requirement, never wear.
  for (const [code, name, recipe, note] of KITS) {
    take(code, name)
    if (note.length <= 12) throw new Error(`${code}: note too short`)
    checkRecipe(code, recipe)
    checkEffects(code, [], KIT_BASE)
    items.push({
      code, name, slot: 'kit', buys: 'Augments a fitting', spends: 'Used up', note, volume: 1, wsTier: 3,
      baseType: KIT_BASE, rack: 'kit', grade: 1, meta: 0, deck: 0, hands: 0, active: false,
      effects: [], recipe, requirements: [],
    })
    use.push({ code, ...useOf(code, KIT_BASE, false) })
  }
  if (KITS.length !== 4) throw new Error(`§6.6 names four kits; KITS has ${KITS.length}`)
  if (items.length !== 151 + COUNTRY_COUNT + KITS.length) throw new Error(`the gear is 151 items through S15 + ${COUNTRY_COUNT} Country + ${KITS.length} kits = 199; the generator made ${items.length}`)

  // S17 (§6.2's Famous row): ONE Famous per famous hull — famousDelta over the G1's effects (+ its authored
  // second buy, a stat the G1 does not move), Deck and Hands × 1.6, the module skill V + Famous Ships I (+ the
  // base type's second skill), tier 3, the T2 recipe × 1.5 (rounded up).
  if (!skills.has('FAMOUS_SHIPS')) throw new Error('FAMOUS_SHIPS is not in data/skills.json')
  const famousHulls = new Set()
  for (const [code, name, hull, base, second, note] of FAMOUS) {
    const b = BASE_TYPES.find((x) => x.base === base)
    if (!b || !b.t2) throw new Error(`${code}: ${base} is no base type with a T2 (a Famous is cut from its G1 and T2)`)
    if (famousHulls.has(hull)) throw new Error(`${code}: a second Famous for the hull ${hull} (one each)`)
    famousHulls.add(hull)
    const g1 = g1ByBase[base]
    take(code, name)
    checkNote(code, note)
    const recipe = b.t2[2].map((x) => ({ in: x.in, qty: roundUp(x.qty * FAMOUS_MULT.recipe) }))
    checkRecipe(code, recipe)
    const effects = g1.effects.map(([stat, delta]) => ({ stat, delta: famousDelta(stat, delta) }))
    if (second) {
      if (effects.some((e) => e.stat === second[0])) throw new Error(`${code}: the second buy ${second[0]} is a stat the G1 already moves`)
      effects.push({ stat: second[0], delta: second[1] })
    }
    checkEffects(code, effects)
    const requirements = [{ skill: b.skill, level: 5 }, { skill: 'FAMOUS_SHIPS', level: 1 }]
    if (b.also) requirements.push({ ...b.also })
    items.push({
      code, name, slot: g1.slot, buys: second ? `${g1.buys}, ${STAT_WORD[second[0]]}` : g1.buys,
      spends: g1.spends, note, volume: g1.volume, wsTier: 3,
      baseType: base, rack: b.rack, grade: 5, meta: 8, hull,
      deck: roundUp(g1.deck * FAMOUS_MULT.deckHands), hands: roundUp(g1.hands * FAMOUS_MULT.deckHands), active: g1.active,
      effects, recipe, requirements,
      ...(FAMOUS_MADE ? {} : { made: false }),   // 0184: made nowhere until the owner sets how it is won
    })
    use.push({ code, ...useOf(code, base, g1.active) })
  }
  if (FAMOUS.length !== 11) throw new Error(`§4.3 Wave D: one Famous per famous ship (11); the table has ${FAMOUS.length}`)
  if (items.length !== 151 + COUNTRY_COUNT + KITS.length + FAMOUS.length) throw new Error(`the gear is 199 items through S16 + ${FAMOUS.length} Famous = 210; the generator made ${items.length}`)
  expectFx('drakes-culverins', { attack: 180, reach: 45, accuracy: 12, hold: -20, handling: -6 })
  if (use.length !== items.length + Object.keys(profiles).length) throw new Error(`every item has one use row: ${use.length} for ${items.length} + ${Object.keys(profiles).length} live`)

  use.sort((a, b) => (a.code < b.code ? -1 : a.code > b.code ? 1 : 0))
  return {
    _: 'GENERATED by scripts/build-gear.mjs — do not edit; edit the generator and re-run it (docs/SHIPS_AND_SKILLS.md §6.2-6.4, S12, migration 0135; §6.1 / §6.5 / §6.8, S13, migration 0158; §6.2 T2 + Named, S15, migration 0159; §6.2 Country + §6.6 kits + §6.7 sets, S16, migration 0163; §6.2 Famous, S17, migration 0166).',
    items,
    use,
  }
}

const q = (s) => `'${String(s).replace(/'/g, "''")}'`
const NL = '\n'

/** The rows of one list of items, as the five catalogue tables take them. */
function itemRows(I) {
  const rows = (list) => list.join(',' + NL)
  return [
    `-- item_kinds (${I.length})`,
    rows(I.map((i) => `  (${q(i.code)}, ${q(i.name)}, ${q(i.slot)}, ${q(i.buys)}, ${q(i.spends)}, ${q(i.note)}, ${i.volume}, ${i.wsTier})`)),
    `-- item_profile (${I.length})`,
    rows(I.map((i) => `  (${q(i.code)}, ${q(i.baseType)}, ${q(i.rack)}, ${i.grade}, ${i.meta}, ${i.deck}, ${i.hands}, ${i.active})`)),
    '-- item_effects',
    rows(I.flatMap((i) => i.effects.map((e) => `  (${q(i.code)}, ${q(e.stat)}, ${e.delta})`))),
    '-- item_recipes (by good code)',
    rows(I.flatMap((i) => i.recipe.map((x) => `  (${q(i.code)}, ${q(x.in)}, ${x.qty})`))),
    '-- skill_requirements (item)',
    rows(I.flatMap((i) => i.requirements.map((r) => `  ('item', ${q(i.code)}, ${q(r.skill)}, ${r.level})`))),
  ]
}

/** Which migration an item's rows belong to: 0135 (Wave A, meta 0), 0158 (the refits), 0159 (T2 + Named, meta 1 / 5)
 *  or 0163 (Country, meta 6, and the kits). */
const isS16 = (i) => i.meta === 6 || i.rack === 'kit'
const isS12 = (i) => i.rack !== 'refit' && i.meta === 0 && !isS16(i)
const isS17 = (i) => i.meta === 8
const isS15 = (i) => i.meta > 0 && !isS16(i) && !isS17(i)
const useRows = (list) => list.map((u) => `  (${q(u.code)}, ${u.trigger === null ? 'null' : q(u.trigger)}, ${q(JSON.stringify(u.consumes))})`).join(',' + NL)

/** The SQL VALUES migration 0135 loaded (`--sql`): the 103 Wave A items (the refits are 0158's, T2 + Named 0159's). */
export function gearSql(gen = generateGear()) {
  return itemRows(gen.items.filter(isS12)).join(NL)
}

/** The SQL VALUES migration 0158 loaded (`--sql-0158`), pasted verbatim: the 14 refits, then what works
 *  every item 0158 knew (public.item_use — the 12 live + 103 Wave A + 14 refits; 0159 adds its own). The
 *  world guard holds the database to generateGear() on every apply. */
export function s13Sql(gen = generateGear()) {
  const later = new Set(gen.items.filter((i) => isS15(i) || isS16(i) || isS17(i)).map((i) => i.code))
  const use = gen.use.filter((u) => !later.has(u.code))
  return [
    ...itemRows(gen.items.filter((i) => i.rack === 'refit')),
    `-- item_use (${use.length})`,
    useRows(use),
  ].join(NL)
}

/** The SQL VALUES migration 0159 loads (`--sql-0159`), pasted verbatim: the 22 T2 and 12 Named items, what
 *  works each (public.item_use), and the one city that makes each Named (public.item_city). */
export function s15Sql(gen = generateGear()) {
  const I = gen.items.filter(isS15)
  const s15 = new Set(I.map((i) => i.code))
  const named = I.filter((i) => i.meta === 1)
  return [
    ...itemRows(I),
    `-- item_use (${s15.size})`,
    useRows(gen.use.filter((u) => s15.has(u.code))),
    `-- item_city (${named.length})`,
    named.map((i) => `  (${q(i.code)}, ${q(i.city)})`).join(',' + NL),
  ].join(NL)
}

/** The SQL VALUES migration 0163 loads (`--sql-0163`), pasted verbatim: the 44 Country items and the 4 kits, what
 *  works each (public.item_use), and the line each Country item belongs to (public.item_line). */
export function s16Sql(gen = generateGear()) {
  const I = gen.items.filter(isS16)
  const s16 = new Set(I.map((i) => i.code))
  const country = I.filter((i) => i.meta === 6)
  return [
    ...itemRows(I),
    `-- item_use (${s16.size})`,
    useRows(gen.use.filter((u) => s16.has(u.code))),
    `-- item_line (${country.length})`,
    country.map((i) => `  (${q(i.code)}, ${q(i.line)})`).join(',' + NL),
  ].join(NL)
}

/** The SQL VALUES migration 0166 loads (`--sql-0166`), pasted verbatim: the 11 Famous items and what works
 *  each (public.item_use). Which hull each is the gear of rides in scripts/build-ships.mjs (hull_recipe_items). */
export function s17Sql(gen = generateGear()) {
  const I = gen.items.filter(isS17)
  const s17 = new Set(I.map((i) => i.code))
  return [
    ...itemRows(I),
    `-- item_use (${s17.size})`,
    useRows(gen.use.filter((u) => s17.has(u.code))),
  ].join(NL)
}

/** The SQL VALUES migration 0184 loads (`--sql-0184`), pasted verbatim: public.item_unmade, every item written
 *  `made: false` (the Famous pieces while FAMOUS_MADE is false). */
export function unmadeSql(gen = generateGear()) {
  return gen.items.filter((i) => i.made === false).map((i) => `  ('${i.code}')`).join(',' + NL)
}

if (process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('scripts/build-gear.mjs')) {
  const gen = generateGear()
  const text = JSON.stringify(gen, null, 1) + NL
  const n = (f) => gen.items.filter(f).length
  const says = `${gen.items.length} items (${n(isS12)} Wave A + ${n((i) => i.rack === 'refit')} refits + ${n((i) => i.meta === 5)} T2 + ${n((i) => i.meta === 1)} Named + ${n((i) => i.meta === 6)} Country + ${n((i) => i.rack === 'kit')} kits + ${n(isS17)} Famous), ${gen.use.length} item uses`
  if (process.argv.includes('--sql')) {
    console.log(gearSql(gen))
  } else if (process.argv.includes('--sql-0158')) {
    console.log(s13Sql(gen))
  } else if (process.argv.includes('--sql-0159')) {
    console.log(s15Sql(gen))
  } else if (process.argv.includes('--sql-0163')) {
    console.log(s16Sql(gen))
  } else if (process.argv.includes('--sql-0166')) {
    console.log(s17Sql(gen))
  } else if (process.argv.includes('--sql-0184')) {
    console.log(unmadeSql(gen))
  } else if (process.argv.includes('--check')) {
    const now = readFileSync(join(ROOT, GEAR_FILE), 'utf8')
    if (now !== text) { console.error(`${GEAR_FILE} is NOT what scripts/build-gear.mjs generates — re-run it.`); process.exit(1) }
    console.log(`${GEAR_FILE} equals the generator (${says}).`)
  } else {
    writeFileSync(join(ROOT, GEAR_FILE), text)
    console.log(`wrote ${GEAR_FILE}: ${says}`)
  }
}
