// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-gear.mjs — WAVE A GEAR: grades 2-5 of the twelve live base types, grades 1-5 of the eleven new
//                  ones (docs/SHIPS_AND_SKILLS.md §6.2-6.4, S12, migration 0135)
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
// §6.3 lists ELEVEN new base types (Carronades, Chase Guns, Swivel Guns, Studding Sails, Storm
// Canvas, Whipstaff, Sheet Anchor, Capstan, Binnacle & Charts, Planking, Bilge Pumps); §0/§8 say
// "ten" and "~98 rows". The table is the specification: 11 × 5 + 12 × 4 = 103 rows.
//
// RUN:   node scripts/build-gear.mjs           writes data/gear.generated.json
//        node scripts/build-gear.mjs --check   fails if the file is not what the generator gives
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
    ['bronze-guns', 'Bronze Guns', r('copper 12, tin-ingots 8, culverin 10, falconet 2'), 'The finest gun metal there is, cast for range and weight of fire.'] ] },
  { base: 'Carronades', rack: 'high', skill: 'GUNNERY', also: { skill: 'SHORT_GUNS', level: 1 },
    g1: { code: 'carronades', name: 'Carronades', slot: 'weapon', buys: 'Attack at close range', spends: 'Reach, Cargo space, Handling',
      note: 'Short, heavy guns that smash at close range and reach nothing far off.', volume: 5, wsTier: 3, deck: 5, hands: 7, active: true,
      effects: [['attack', 90], ['reach', -15], ['hold', -14], ['handling', -4]], recipe: r('bar-iron 8, brass-ingots 2, gunpowder 2') },
    grades: [
      ['heavy-carronades', 'Heavy Carronades', r('culverin 3, bar-iron 6, gunpowder 2'), 'Carronades of a heavier pattern, with more shot in every broadside.'],
      ['brass-carronades', 'Brass Carronades', r('brass-ingots 8, culverin 4, gunpowder 2'), 'Brass short guns that take a bigger charge without bursting.'],
      ['swedish-carronades', 'Swedish Carronades', r('swedish-iron 8, culverin 6, gunpowder 3'), 'Short guns of Swedish iron, as heavy-hitting as any afloat.'],
      ['bronze-carronades', 'Bronze Carronades', r('copper 10, tin-ingots 6, culverin 6, gunpowder 3'), 'Bronze smashers: the hardest blow a ship can strike at close range.'] ] },
  { base: 'Chase Guns', rack: 'high', skill: 'GUNNERY', also: { skill: 'LONG_GUNS', level: 1 },
    g1: { code: 'stern-chasers', name: 'Stern Chasers', slot: 'weapon', buys: 'Reach, Accuracy', spends: 'Cargo space',
      note: 'Long guns at the stern and bow that keep a pursuer honest at a distance.', volume: 4, wsTier: 3, deck: 4, hands: 4, active: true,
      effects: [['reach', 20], ['accuracy', 10], ['hold', -8]], recipe: r('culverin 2, live-oak 2, shot-and-ball 2') },
    grades: [
      ['culverin-chasers', 'Culverin Chasers', r('culverin 3, bar-iron 3, shot-and-ball 2'), 'Longer chase guns that reach further and aim truer.'],
      ['brass-chasers', 'Brass Chasers', r('brass-ingots 6, culverin 4, shot-and-ball 2'), 'Brass chase guns, accurate at long range.'],
      ['swedish-chasers', 'Swedish Chasers', r('swedish-iron 6, culverin 5, shot-and-ball 3'), 'Swedish-iron chasers that outrange most broadsides.'],
      ['bronze-chasers', 'Bronze Chasers', r('copper 8, tin-ingots 5, culverin 6, falconet 1'), 'Bronze long chasers: the furthest-reaching guns a ship can carry.'] ] },
  { base: 'Swivel Guns', rack: 'high', skill: 'GUNNERY',
    g1: { code: 'swivel-guns', name: 'Swivel Guns', slot: 'weapon', buys: 'Attack, Accuracy', spends: 'Handling',
      note: 'Small guns on the rails that sweep a deck at close quarters.', volume: 2, wsTier: 2, deck: 2, hands: 3, active: true,
      effects: [['attack', 20], ['accuracy', 8], ['handling', -2]], recipe: r('bar-iron 3, timber 1, shot-and-ball 1') },
    grades: [
      ['iron-swivels', 'Iron Swivels', r('bar-iron 3, culverin 1, shot-and-ball 1'), 'Better-bored swivels that hit harder and truer.'],
      ['brass-swivels', 'Brass Swivels', r('brass-ingots 4, culverin 1, shot-and-ball 1'), 'Brass swivels, light enough to train fast.'],
      ['swedish-swivels', 'Swedish Swivels', r('swedish-iron 4, culverin 2, shot-and-ball 2'), 'Swivels of Swedish iron that can take a double charge.'],
      ['bronze-swivels', 'Bronze Swivels', r('copper 5, tin-ingots 3, swivel-gun 1, shot-and-ball 2'), 'Bronze swivels: the deadliest small guns on any rail.'] ] },
  { base: 'Boarding Gear', rack: 'high', skill: 'BOARDING', g1: 'boarding-gear', grades: [
    ['osmund-grapnels', 'Osmund Grapnels', r('osmund-iron 3, hemp 3, timber 1'), 'Grapnels of good iron that hold where cheaper ones straighten.'],
    ['boarding-pikes', 'Boarding Pikes', r('bar-iron 3, abaca 3, timber 2'), 'Pikes, nets and grapnels for a crew that means to board.'],
    ['boarding-axes', 'Boarding Axes & Grapnels', r('swedish-iron 3, abaca 3, live-oak 2'), 'Axes and grapnels of Swedish iron for the hardest boarding fights.'],
    ['storming-gear', 'Storming Gear', r('swedish-iron 4, copper 2, abaca 3, slow-match 1'), 'Everything a boarding party needs, down to the fire pots.'] ] },
  { base: 'Powder Magazine', rack: 'high', skill: 'GUNNERY', g1: 'powder-magazine', grades: [
    ['lined-magazine', 'Lined Magazine', r('gunpowder 5, live-oak 3, copper-sheet 2'), 'A lined powder room that keeps the guns firing longer.'],
    ['copper-magazine', 'Copper-lined Magazine', r('gunpowder 6, teak 3, copper-sheet 4'), 'A copper-lined powder room: drier powder and steadier fire.'],
    ['light-room-magazine', 'Light Room Magazine', r('gunpowder 8, live-oak 4, copper-sheet 4, lead 2'), 'A powder room with its own light room, so the gunners never fire blind.'],
    ['grand-magazine', 'Grand Magazine', r('gunpowder 10, greenheart 4, copper-sheet 6, slow-match 1'), 'The finest magazine afloat, built for a long day of fighting.'] ] },
  { base: 'Sails', rack: 'mid', skill: 'RIGGING', g1: 'suit-of-sails', grades: [
    ['hemp-canvas', 'Hemp Canvas', r('hemp 6, cordage 3, tar 1'), 'Sails of hemp canvas that hold their shape and drive harder.'],
    ['duck-canvas', 'Duck Canvas', r('canvas-duck 20, hemp 6, cordage 3, tar 1'), 'Heavy duck canvas that stands a stronger wind.'],
    ['baltic-sailcloth', 'Baltic Sailcloth', r('sailcloth 10, hemp 6, cordage 4, tar 2'), 'Close-woven Baltic sailcloth: more speed from the same wind.'],
    ['holland-duck', 'Holland Duck', r('sailcloth 14, abaca 8, whale-bone-stays 4, tar 2'), 'The best sail canvas there is, cut and stayed for speed.'] ] },
  { base: 'Headsails', rack: 'mid', skill: 'RIGGING', g1: 'bowsprit-and-jib', grades: [
    ['hemp-jib', 'Hemp Jib', r('naval-timber 3, hemp 3, cordage 2'), 'A hemp jib on a stouter bowsprit: quicker through the turn.'],
    ['duck-jib', 'Duck Jib & Staysail', r('naval-timber 3, canvas-duck 8, cordage 3'), 'A jib and staysail of duck canvas that turn the ship smartly.'],
    ['sailcloth-headsails', 'Sailcloth Headsails', r('riga-mast 2, sailcloth 4, cordage 3'), 'Headsails of Baltic sailcloth on a Riga spar.'],
    ['holland-headsails', 'Holland Headsails', r('riga-mast 2, sailcloth 6, abaca 3, whale-bone-stays 2'), 'The finest headsails: the ship answers almost before the helm is put over.'] ] },
  { base: 'Studding Sails', rack: 'mid', skill: 'RIGGING',
    g1: { code: 'studding-sails', name: 'Studding Sails', slot: 'rig', buys: 'Speed', spends: 'Handling, Hull',
      note: 'Extra sails set outside the main ones in fair weather: faster, but harder to handle and easy to damage.', volume: 4, wsTier: 2, deck: 4, hands: 5, active: false,
      effects: [['speed', 0.9], ['handling', -14], ['durability', -30]], recipe: r('flax 8, norway-spruce 2, cordage 3') },
    grades: [
      ['hemp-studding-sails', 'Hemp Studding Sails', r('hemp 8, norway-spruce 2, cordage 3'), 'Studding sails of hemp canvas on spruce booms.'],
      ['duck-studding-sails', 'Duck Studding Sails', r('canvas-duck 20, norway-spruce 3, cordage 3'), 'Duck-canvas studding sails that carry in a fresher wind.'],
      ['sailcloth-studding-sails', 'Sailcloth Studding Sails', r('sailcloth 8, riga-mast 2, cordage 4'), 'Baltic sailcloth studding sails on Riga booms.'],
      ['holland-studding-sails', 'Holland Studding Sails', r('sailcloth 12, abaca 6, riga-mast 2, whale-bone-stays 2'), 'The fastest studding sails there are.'] ] },
  { base: 'Storm Canvas', rack: 'mid', skill: 'RIGGING',
    g1: { code: 'storm-canvas', name: 'Storm Canvas', slot: 'rig', buys: 'Hull, Handling', spends: 'Speed',
      note: 'Small, heavy sails for bad weather: the ship rides out a storm and gives up a little speed.', volume: 3, wsTier: 1, deck: 3, hands: 3, active: true,
      effects: [['durability', 50], ['handling', 4], ['speed', -0.25]], recipe: r('canvas-duck 4, cordage 2, tar 1') },
    grades: [
      ['hemp-storm-canvas', 'Hemp Storm Canvas', r('hemp 4, canvas-duck 4, tar 1'), 'Storm sails of hemp and duck that take a harder blow.'],
      ['double-duck-storm-canvas', 'Double Duck Storm Canvas', r('canvas-duck 12, hemp 3, tar 1'), 'Doubled duck canvas for the worst weather.'],
      ['sailcloth-storm-canvas', 'Sailcloth Storm Canvas', r('sailcloth 6, hemp 4, tar 2'), 'Baltic storm canvas that holds where others split.'],
      ['holland-storm-canvas', 'Holland Storm Canvas', r('sailcloth 8, abaca 6, whale-bone-stays 2, tar 2'), 'The best storm canvas made: the ship can ride out almost anything.'] ] },
  { base: 'Rudder', rack: 'mid', skill: 'SEAMANSHIP', g1: 'rudder-and-helm', grades: [
    ['oak-rudder', 'Oak Rudder & Helm', r('timber 6, ships-nails 3, lignum-vitae 1'), 'A broader oak rudder that bites harder.'],
    ['teak-rudder', 'Teak Rudder & Helm', r('teak 4, ships-nails 3, lignum-vitae 1'), 'A teak rudder that does not warp or rot.'],
    ['live-oak-rudder', 'Live-oak Rudder & Tiller', r('live-oak 6, naval-timber 2, ships-nails 3, lignum-vitae 1'), 'A live-oak rudder on a long tiller: the ship turns on a coin.'],
    ['greenheart-rudder', 'Greenheart Rudder & Helm', r('greenheart 6, lignum-vitae 3, copper-sheet 2'), 'The finest steering gear made, of greenheart and lignum vitae.'] ] },
  { base: 'Whipstaff', rack: 'mid', skill: 'SEAMANSHIP',
    g1: { code: 'whipstaff', name: 'Whipstaff', slot: 'steering', buys: 'Handling', spends: 'Cargo space',
      note: 'A light steering lever that gives the helmsman more purchase on the rudder.', volume: 2, wsTier: 1, deck: 2, hands: 1, active: false,
      effects: [['handling', 7], ['hold', -2]], recipe: r('timber 3, iron 1, hemp 1') },
    grades: [
      ['oak-whipstaff', 'Oak Whipstaff', r('timber 4, osmund-iron 1, hemp 1'), 'A stouter oak whipstaff.'],
      ['teak-whipstaff', 'Teak Whipstaff', r('teak 3, bar-iron 1, hemp 1'), 'A teak whipstaff with iron fittings.'],
      ['live-oak-whipstaff', 'Live-oak Whipstaff', r('live-oak 4, naval-timber 1, swedish-iron 1'), 'A live-oak whipstaff that answers the lightest touch.'],
      ['greenheart-whipstaff', 'Greenheart Whipstaff', r('greenheart 4, lignum-vitae 2, brass-ingots 1'), 'The best whipstaff made, of greenheart and brass.'] ] },
  { base: 'Anchor', rack: 'mid', skill: 'SEAMANSHIP', g1: 'anchor-and-cable', grades: [
    ['osmund-anchor', 'Osmund Anchor & Cable', r('osmund-iron 4, hemp 4, tar 1'), 'An anchor of good osmund iron on a stronger cable.'],
    ['manila-anchor', 'Bar-iron Anchor & Manila Cable', r('bar-iron 4, abaca 4, tar 1'), 'A bar-iron anchor on Manila cable, which does not rot.'],
    ['swedish-anchor', 'Swedish Anchor & Cable', r('swedish-iron 4, abaca 5, tar 1'), 'A Swedish-iron anchor that holds in any ground.'],
    ['copper-fast-anchor', 'Copper-fast Anchor & Cable', r('swedish-iron 5, copper 2, abaca 5'), 'The best ground tackle made, copper-fastened against rust.'] ] },
  { base: 'Sheet Anchor', rack: 'mid', skill: 'SEAMANSHIP',
    g1: { code: 'sheet-anchor', name: 'Sheet Anchor', slot: 'ground-tackle', buys: 'Hull in a storm, Handling', spends: 'Cargo space',
      note: 'The biggest anchor on board, kept for the night it is the only thing between the ship and the rocks.', volume: 5, wsTier: 2, deck: 5, hands: 3, active: true,
      effects: [['durability', 60], ['handling', 2], ['hold', -10]], recipe: r('iron 6, hemp 6, tar 1') },
    grades: [
      ['osmund-sheet-anchor', 'Osmund Sheet Anchor', r('osmund-iron 6, hemp 6, tar 1'), 'A sheet anchor of osmund iron.'],
      ['bar-iron-sheet-anchor', 'Bar-iron Sheet Anchor', r('bar-iron 6, abaca 5, tar 1'), 'A bar-iron sheet anchor on Manila cable.'],
      ['swedish-sheet-anchor', 'Swedish Sheet Anchor', r('swedish-iron 6, abaca 6, tar 2'), 'A Swedish-iron sheet anchor that never drags.'],
      ['copper-fast-sheet-anchor', 'Copper-fast Sheet Anchor', r('swedish-iron 6, copper 3, abaca 6'), 'The best sheet anchor made.'] ] },
  { base: 'Capstan', rack: 'mid', skill: 'SEAMANSHIP',
    g1: { code: 'capstan', name: 'Capstan', slot: 'ground-tackle', buys: 'Handling, a little Speed', spends: 'Cargo space',
      note: 'A capstan to haul the anchor and the yards faster, so the ship gets under way sooner.', volume: 3, wsTier: 2, deck: 3, hands: 3, active: false,
      effects: [['handling', 6], ['speed', 0.1], ['hold', -5]], recipe: r('live-oak 3, iron 2, tallow 1') },
    grades: [
      ['osmund-capstan', 'Osmund Capstan', r('timber 4, osmund-iron 2, tallow 1'), 'A capstan with osmund-iron pawls.'],
      ['manila-capstan', 'Manila Capstan', r('teak 3, bar-iron 2, abaca 2, tallow 1'), 'A teak capstan with a Manila messenger.'],
      ['swedish-capstan', 'Swedish Capstan', r('live-oak 4, swedish-iron 2, abaca 2, tallow 1'), 'A live-oak capstan with Swedish-iron fittings.'],
      ['double-capstan', 'Double Capstan', r('greenheart 4, swedish-iron 3, copper 1, abaca 2'), 'A double capstan: two crews heave at once.'] ] },
  { base: 'Lookout', rack: 'mid', skill: 'LOOKOUTS', g1: 'crows-nest', grades: [
    ['topgallant-mast', 'Topgallant Mast', r('riga-mast 2, cordage 3, tar 1'), 'A taller mast with a lookout higher up: the horizon moves out.'],
    ['masthead-glass', 'Masthead Glass', r('riga-mast 2, brass-ingots 2, sea-charts 1'), 'A lookout with a brass glass and charts to name what is seen.'],
    ['lookout-top', 'Lookout Top & Glass', r('riga-mast 2, lodestone 1, sea-charts 1'), 'A fighting top with a glass and compass for the lookout.'],
    ['royal-lookout', 'Royal Lookout', r('riga-mast 3, lodestone 1, sea-charts 1, brass-ingots 2'), 'The highest lookout and the best glass afloat.'] ] },
  { base: 'Binnacle & Charts', rack: 'mid', skill: 'INSTRUMENTS',
    g1: { code: 'binnacle-and-charts', name: 'Binnacle & Charts', slot: 'lookout', buys: 'Sighting, Handling', spends: 'Cargo space',
      note: 'A compass housing and a chest of charts: the ship knows where it is and what lies ahead.', volume: 2, wsTier: 2, deck: 2, hands: 1, active: false,
      effects: [['sighting', 3], ['handling', 5], ['hold', -3]], recipe: r('timber 2, brass-ingots 1, sea-charts 1') },
    grades: [
      ['brass-binnacle', 'Brass Binnacle & Charts', r('riga-mast 1, brass-ingots 2, sea-charts 1'), 'A brass binnacle and better charts.'],
      ['binnacle-and-atlas', 'Binnacle & Sea Atlas', r('brass-ingots 2, sea-charts 2'), 'A binnacle and a full sea atlas.'],
      ['lodestone-compass', 'Lodestone Compass & Charts', r('lodestone 2, sea-charts 2, brass-ingots 1'), 'A compass touched with lodestone, true in any weather.'],
      ['masters-binnacle', "Master's Binnacle", r('lodestone 2, sea-charts 3, brass-ingots 2, lignum-vitae 1'), 'The finest instruments a sailing master can own.'] ] },
  { base: 'Ballast', rack: 'low', skill: 'SHIPWRIGHT', g1: 'ballast', grades: [
    ['iron-kentledge', 'Iron Kentledge', r('iron 6, timber 2'), 'Iron ballast blocks, stowed low and tight.'],
    ['pig-iron-ballast', 'Pig-iron Ballast', r('bar-iron 4, iron 4, timber 2'), 'Pig-iron ballast trimmed for a stiffer ship.'],
    ['lead-ballast', 'Lead & Shingle Ballast', r('lead 8, iron 4, oakum 2'), 'Lead ballast packed in shingle: very stiff, very steady.'],
    ['cast-kentledge', 'Cast Kentledge', r('lead 8, swedish-iron 3, copper 2'), 'Cast ballast fitted to the hull: the steadiest ship afloat.'] ] },
  { base: 'Sheathing', rack: 'low', skill: 'SHIPWRIGHT', g1: 'copper-sheathing', grades: [
    ['doubled-copper', 'Doubled Copper', r('copper-sheet 8, ships-nails 4, tar 2'), 'A double layer of copper below the waterline.'],
    ['teak-and-copper', 'Teak & Copper Sheathing', r('teak 4, copper-sheet 8, ships-nails 4'), 'Teak planking under copper: worm and shot both stop here.'],
    ['live-oak-and-copper', 'Live-oak & Copper Sheathing', r('live-oak 6, copper-sheet 10, ships-nails 5, oakum 2'), 'Live oak under copper, the hardest bottom a ship can have.'],
    ['greenheart-sheathing', 'Greenheart Sheathing', r('greenheart 8, copper-sheet 12, lignum-vitae 2, oakum 2'), 'Greenheart and copper: the best sheathing made.'] ] },
  { base: 'Planking', rack: 'low', skill: 'SHIPWRIGHT',
    g1: { code: 'deal-planking', name: 'Deal Planking', slot: 'hull', buys: 'Armour, Hull', spends: 'Speed, Cargo space',
      note: 'A second skin of planks over the hull: stronger, heavier and slower.', volume: 4, wsTier: 1, deck: 4, hands: 0, active: false,
      effects: [['armour', 10], ['durability', 160], ['speed', -0.45], ['hold', -12]], recipe: r('norway-spruce 12, ships-nails 4, oakum 2, pine-pitch 2') },
    grades: [
      ['oak-planking', 'Oak Planking', r('timber 12, ships-nails 5, oakum 3, tar 1'), 'Doubled oak planking.'],
      ['teak-planking', 'Teak Planking', r('teak 10, ships-nails 6, oakum 3, tar 1'), 'Doubled teak planking that does not rot.'],
      ['live-oak-planking', 'Live-oak Planking', r('live-oak 16, naval-timber 4, ships-nails 8, oakum 4'), 'Doubled live oak: shot bounces off it.'],
      ['greenheart-planking', 'Greenheart Planking', r('greenheart 20, lignum-vitae 10, naval-timber 6, copper-sheet 8'), 'Doubled greenheart, the hardest planking made.'] ] },
  { base: 'Bilge Pumps', rack: 'low', skill: 'SHIPWRIGHT',
    g1: { code: 'bilge-pumps', name: 'Bilge Pumps', slot: 'hull', buys: 'Hull', spends: 'Cargo space',
      note: 'Pumps that keep the water down when the hull is hurt or the sea gets in.', volume: 3, wsTier: 1, deck: 3, hands: 4, active: true,
      effects: [['durability', 90], ['hold', -5]], recipe: r('timber 3, lead 2, hides 1') },
    grades: [
      ['chain-pumps', 'Chain Pumps', r('timber 3, iron 2, hides 1, cordage 1'), 'Chain pumps that move more water than a plain pump.'],
      ['teak-chain-pumps', 'Teak Chain Pumps', r('teak 3, bar-iron 2, hides 1'), 'Chain pumps in teak cases.'],
      ['brake-pumps', 'Brake Pumps', r('live-oak 4, copper 2, hides 2'), 'Big brake pumps worked by a whole watch.'],
      ['copper-chain-pumps', 'Copper Chain Pumps', r('greenheart 3, copper 4, brass-ingots 2, hides 1'), 'Copper chain pumps: the best made.'] ] },
  { base: 'Hold Frames', rack: 'low', skill: 'CARGO_STOWAGE', g1: 'hold-fittings', grades: [
    ['teak-frames', 'Teak Frames', r('teak 5, ships-nails 4, oakum 3'), 'Teak frames that stow more cargo in the same space.'],
    ['live-oak-frames', 'Live-oak Frames', r('live-oak 10, teak 4, ships-nails 5, oakum 4'), 'Live-oak frames for a tighter stow.'],
    ['knee-braced-frames', 'Knee-braced Frames', r('live-oak 14, naval-timber 4, lignum-vitae 6, oakum 6'), 'Frames braced with knees, so the cargo space can be opened up.'],
    ['greenheart-frames', 'Greenheart Frames', r('greenheart 20, naval-timber 6, lignum-vitae 8, copper-sheet 6'), 'Greenheart frames: the most cargo space a hull can give.'] ] },
  { base: 'Figurehead', rack: 'flourish', skill: null, g1: 'figurehead', grades: [
    ['carved-figurehead', 'Carved Oak Figurehead', r('timber 4, tallow 1, lead 1'), "A carved oak figurehead. It moves no number; it is the ship's face."],
    ['painted-figurehead', 'Painted Teak Figurehead', r('teak 3, cedar 2, tallow 1'), 'A painted teak figurehead. It moves no number; the crew are proud of it.'],
    ['gilded-figurehead', 'Gilded Figurehead', r('cedar 4, gold-thread 1, vermilion 1'), 'A gilded figurehead. It moves no number; every port knows the ship by it.'],
    ['royal-figurehead', 'Royal Figurehead', r('sandalwood 3, gold 1, vermilion 1'), 'A royal figurehead in sandalwood and gold. It moves no number; it is a statement.'] ] },
]

/** One effect at grade g: buys × the grade's multiplier (gentler for speed / hold), spends × 1. */
export function gradedDelta(stat, delta, g) {
  if (delta < 0) return delta
  const v = delta * (MONEY_STATS.has(stat) ? MONEY_MULT[g] : GRADE_MULT[g])
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
      items.push({
        code, name, slot: g1.slot, buys: g1.buys, spends: g1.spends, note, volume: g1.volume,
        wsTier: g === 1 ? g1.wsTier : g <= 3 ? Math.max(2, g1.wsTier) : 3,
        baseType: b.base, rack: b.rack, grade: g, meta: 0,
        deck: roundUp(g1.deck * (1 + 0.1 * (g - 1))), hands: roundUp(g1.hands * (1 + 0.1 * (g - 1))), active: g1.active,
        effects, recipe, requirements,
      })
    }
  }
  if (items.length !== 103) throw new Error(`Wave A gear is 103 items (12 × G2-G5 + 11 × G1-G5); the generator made ${items.length}`)
  return { _: 'GENERATED by scripts/build-gear.mjs — do not edit; edit the generator and re-run it (docs/SHIPS_AND_SKILLS.md §6.2-6.4, S12, migration 0135).', items }
}

const q = (s) => `'${String(s).replace(/'/g, "''")}'`

/** The SQL VALUES migration 0135 loads (`--sql`), pasted verbatim; the world guard holds the database to
 *  generateGear() on every apply. */
export function gearSql(gen = generateGear()) {
  const I = gen.items
  const rows = (list) => list.join(',\n')
  return [
    '-- item_kinds (103)',
    rows(I.map((i) => `  (${q(i.code)}, ${q(i.name)}, ${q(i.slot)}, ${q(i.buys)}, ${q(i.spends)}, ${q(i.note)}, ${i.volume}, ${i.wsTier})`)),
    '-- item_profile (103)',
    rows(I.map((i) => `  (${q(i.code)}, ${q(i.baseType)}, ${q(i.rack)}, ${i.grade}, ${i.meta}, ${i.deck}, ${i.hands}, ${i.active})`)),
    '-- item_effects',
    rows(I.flatMap((i) => i.effects.map((e) => `  (${q(i.code)}, ${q(e.stat)}, ${e.delta})`))),
    '-- item_recipes (by good code)',
    rows(I.flatMap((i) => i.recipe.map((x) => `  (${q(i.code)}, ${q(x.in)}, ${x.qty})`))),
    '-- skill_requirements (item)',
    rows(I.flatMap((i) => i.requirements.map((r) => `  ('item', ${q(i.code)}, ${q(r.skill)}, ${r.level})`))),
  ].join('\n')
}

if (process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('scripts/build-gear.mjs')) {
  const text = JSON.stringify(generateGear(), null, 1) + '\n'
  if (process.argv.includes('--sql')) {
    console.log(gearSql())
  } else if (process.argv.includes('--check')) {
    const now = readFileSync(join(ROOT, GEAR_FILE), 'utf8')
    if (now !== text) { console.error(`${GEAR_FILE} is NOT what scripts/build-gear.mjs generates — re-run it.`); process.exit(1) }
    console.log(`${GEAR_FILE} equals the generator (103 items).`)
  } else {
    writeFileSync(join(ROOT, GEAR_FILE), text)
    console.log(`wrote ${GEAR_FILE}: 103 items`)
  }
}
