// tables.mjs - prints the Markdown tables of docs/dev-log/2026-11-13-more-ships.md from data/ships.generated.json and the Korean name map (plain Node, no world).
//   node scripts/ops/harness/more-ships/tables.mjs            the 54 hulls, the roster by role before and after, and each new hull beside her nearest older ones
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { JOBS, outclasses } from '../../../build-ships.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..')
const gen = JSON.parse(readFileSync(join(ROOT, 'data', 'ships.generated.json'), 'utf8'))
const ko = Object.fromEntries([...readFileSync(join(ROOT, 'src', 'lib', 'i18n', 'names', 'realms.ts'), 'utf8').matchAll(/(?:'([^']+)'|([A-Za-z]+)): '([^']+)'/g)].map((m) => [m[1] ?? m[2], m[3]]))
const NEW = gen.hulls.filter((h) => h.wave === 'E')
const OLD = gen.hulls.filter((h) => h.wave !== 'E')
const SIZE = { 1: 'Small', 2: 'Light', 3: 'Medium', 4: 'Heavy', 5: 'Capital', 6: 'Flagship' }
const JOB = { raider: 'Combat: Raider', gunship: 'Combat: Gunship', boarder: 'Combat: Boarder', line: 'Combat: Line ship', escort: 'Support: Escort', armed: 'Trade: Armed trader', carrier: 'Trade: Cargo' }
const n = (x) => x.toLocaleString('en-US')
const req = (h) => h.requirements.map((r) => `${r.skill} ${['', 'I', 'II', 'III', 'IV', 'V'][r.level]}`).join(', ')

console.log('### Roster by role\n')
console.log('| role | before | new | after |\n|---|---|---|---|')
const live = { trade: 2, explorer: 1 }   // the barca and the nau; the caravela latina
for (const role of ['combat', 'support', 'trade', 'explorer']) {
  const b = OLD.filter((h) => h.role === role).length + (live[role] ?? 0)
  const a = NEW.filter((h) => h.role === role).length
  console.log(`| ${role} | ${b} | ${a} | ${b + a} |`)
}
console.log(`| all | ${OLD.length + 3} | ${NEW.length} | ${gen.hulls.length + 3} |`)
console.log('\nBy job: ' + Object.keys(JOBS).map((j) => `${j} ${NEW.filter((h) => h.job === j).length}`).join(', ') + `, plain trader ${NEW.filter((h) => !h.job).length}.`)

console.log('\n### The 54\n')
console.log('| name | Korean | role and job | line | size | needs | labour d. | price d. | hold t | knots | crew | hull | armour | attack | accuracy | reach | sighting | wave |')
console.log('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')
for (const h of NEW) {
  console.log(`| ${h.name} | ${ko[h.name] ?? '??'} | ${h.job ? JOB[h.job] : 'Trade'} | ${h.line} | ${SIZE[h.size]} | ${req(h)} | ${n(h.ducats)} | ${n(h.buildCost)} | ${n(h.hold)} | ${h.speedKn} | ${h.crewRequired} / ${h.crewMax} | ${n(h.durability)} | ${h.armour} | ${h.attack} | ${h.accuracy} | ${h.reach} | ${h.sighting} | ${h.waveResistance} |`)
}

console.log('\n### Each new hull beside the older hulls of her size and line (or the Portuguese ones)\n')
console.log('| new hull | older hull | labour | hold | knots | crew | hull | armour | attack | reach | sighting | which is better where |')
console.log('|---|---|---|---|---|---|---|---|---|---|---|---|')
const KEYS = [['hold', 'hold'], ['speedKn', 'speed'], ['durability', 'hull'], ['armour', 'armour'], ['attack', 'attack'], ['accuracy', 'accuracy'], ['reach', 'reach'], ['sighting', 'sighting'], ['crewMax', 'berths'], ['handling', 'handling']]
let pairs = 0
for (const h of NEW) {
  const same = OLD.filter((o) => o.size === h.size && o.tech === 'T1')
  const pool = [...same.filter((o) => o.line === h.line), ...same.filter((o) => o.line === 'PRT' && o.line !== h.line)]
  const picks = [pool.find((o) => o.role === h.role), pool.find((o) => o.role !== h.role), same.find((o) => o.role === h.role && !pool.includes(o))].filter(Boolean)
  for (const o of [...new Set(picks)].slice(0, 2)) {
    if (outclasses(h, o) || outclasses(o, h)) throw new Error(`${h.class} / ${o.class}: one outclasses the other`)
    const up = KEYS.filter(([k]) => h[k] > o[k]).map(([, w]) => w)
    const down = KEYS.filter(([k]) => h[k] < o[k]).map(([, w]) => w)
    pairs += 1
    console.log(`| ${h.name} | ${o.name} | ${n(h.ducats)} / ${n(o.ducats)} | ${h.hold} / ${o.hold} | ${h.speedKn} / ${o.speedKn} | ${h.crewRequired}-${h.crewMax} / ${o.crewRequired}-${o.crewMax} | ${h.durability} / ${o.durability} | ${h.armour} / ${o.armour} | ${h.attack} / ${o.attack} | ${h.reach} / ${o.reach} | ${h.sighting} / ${o.sighting} | more ${up.join(', ') || 'nothing'}; less ${down.join(', ') || 'nothing'} |`)
  }
}
console.log(`\n${pairs} pairs; in none does one hull outclass the other (the generator checks every pair of a size, ${NEW.length} new against ${OLD.length + 3} older and each other).`)
