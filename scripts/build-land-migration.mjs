// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-land-migration.mjs — THE LAND'S JOBS, as data (docs/design/land-2026-11.md 6.3; migration 0455)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ONE RULE, ONE LADDER. A land job is one row of public.land_actions. This file holds the two things a row is made of and
// nothing else:
//   THE LADDER  which good a skill works, and the level it asks (6.3's table, by the catalogue's own good codes). The level a
//               good asks is the same wherever the party comes from: distance is paid in time, never in levels.
//   THE RULE    a job's time and pay, from the good's own price (6.3, and the guard of 5.8):
//                 a party-hour of the good is worth 4,800 coin at level 1, rising in a straight line to 15,000 at level 100,
//                 at the catalogue's base value (data/goods.json `baseValue`, the middle of its range: the figure the
//                 database's public.goods.base_value holds, which scripts/db/world-guard.mjs keeps equal);
//                 seconds = that worth's time for one unit, to the nearest 5 s, never under 40 s;
//               THE MARKET GUARD (5.8 rule 2), the same rule's floor: at the FASTEST pace the game allows (Mining 100, the best
//                 tool of land_tools, the crowd's full chance of a second unit), one party-hour of a good is no more than one
//                 hundredth of its target stock at a middling harbour of EVERY region it comes from, at the least target the
//                 market's depth rule can hold a harbour at (its base x depth_m0, 0252). The least of those middling targets is
//                 data/land-guard.generated.json (scripts/db/measure-land-guard.mjs reads it from the world); the
//                 seconds are raised, by 5 s steps, until the guard holds with the server's own rounding of a turn
//                 (public.land_terms). A march, a passage or fewer packs only slow a party, so a turn is the bound;
//                 experience = the seconds, times the pay a minute of the level it asks (4.4's steps), rounded, at least 1.
// WHERE A JOB IS DONE is NOT here: a gather job is done on the land of every region its good comes from
// (public.goods.origin_regions), read by public.land_passage at the press. The catalogue is the list of sites.
//
// USAGE
//   node scripts/build-land-migration.mjs          prints the VALUES block the newest land migration carries between its marker lines
//   node scripts/build-land-migration.mjs --drops  prints the rare finds' VALUES block 0458 carries between its "drops" marker lines
//   node scripts/build-land-migration.mjs --smith  prints the smith's VALUES block 0461 carries between its "smith" marker lines (L2)
// tests/land.data.spec.ts holds that block equal to this file's output, so the rows cannot drift from the rule. 0455 carried the
// first cut (no market guard); 0457 carries the rows with the guard and is the block the spec reads; 0458 carries the finds, and
// its knob land_packs is MULES (L1c, at the foot of this file: mules, Repeat and finds, each judged by the same guard).
// The second caller is the next skill (Fishing, Smithing): a new entry in LADDERS, its rows printed the same way, into its own
// migration. A make job (L2) reads its inputs from public.goods_recipes, never from here.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

/** 6.3: Mining, all 57 minerals of the catalogue, by the level each asks. Good codes are data/goods.json's ids. */
export const LADDERS = {
  mining: {
    ground: 'mines',
    tool: 'pick',
    goods: [
      [1, 'coal'], [1, 'iron'], [1, 'clay'],
      [5, 'stone'], [7, 'sand'], [10, 'copper'], [13, 'salt'], [15, 'tin'], [18, 'lead'], [20, 'lime'], [23, 'gypsum'],
      [25, 'sulphur'], [28, 'alum'], [30, 'saltpetre'], [33, 'zinc-spelter'],
      [36, 'ochre'], [36, 'feldspar'], [36, 'quartz'],
      [40, 'silver'], [43, 'marble'], [45, 'antimony'], [48, 'cobalt'],
      [50, 'quicksilver'], [50, 'cinnabar'], [53, 'alum-shale'],
      [55, 'swedish-iron'], [55, 'osmund-iron'], [55, 'bar-iron'],
      [58, 'japan-copper'], [58, 'chilean-copper'], [58, 'tin-ingots'],
      [60, 'gold'], [60, 'gold-dust'], [65, 'amber'], [65, 'baltic-amber'], [68, 'lodestone'],
      [70, 'potosi-silver'], [70, 'zacatecas-silver'],
      [74, 'turquoise'], [74, 'carnelian'], [74, 'malachite'], [74, 'onyx'],
      [78, 'lapis-lazuli'], [78, 'opals'], [78, 'peridot'],
      [80, 'jade'], [80, 'nephrite'], [80, 'pounamu'],
      [84, 'emeralds'], [84, 'emerald-muzo'], [87, 'rubies'], [87, 'burma-rubies'], [90, 'ceylon-sapphires'],
      [93, 'diamonds'], [93, 'golconda-diamonds'], [96, 'platinum'], [96, 'andacollo-gold'],
    ],
  },
}

/**
 * 0461 (L2, THE SMITH; design 6.3 "Smithing: the catalogue's 21 metal recipes"): the MAKE jobs, by the level each asks. A make job's
 * good is its PRODUCT, a good of the catalogue with a recipe; what it uses is public.goods_recipes' (the Forge's one recipe table),
 * never written here. Made at home (no ground, no march, no passage); its market guard is held against the product's least
 * middling-harbour target over EVERY region (a home can be in any), at FASTEST_MAKE. The design's three picks (Iron, Steel, Wootz)
 * are NOT here: a pick better than the plain one would break Mining's guard (FASTEST.toolPct 3) unless Mining's rows are re-timed,
 * which is live play and the owner's (docs/dev-log/2026-11-20-land-l2.md).
 */
export const MAKERS = {
  smithing: {
    goods: [
      [1, 'iron-bars'], [5, 'ships-nails'], [10, 'steel-billets'], [15, 'sword-blades'], [22, 'pike-heads'], [26, 'armour'],
      [30, 'brass-ingots'], [33, 'copper-cash'], [36, 'pewter'], [40, 'wootz-steel'], [43, 'copper-sheet'], [46, 'talwar'],
      [50, 'brassware'], [54, 'smallwares'], [58, 'kris'], [62, 'benin-bronzes'], [66, 'katana'], [70, 'milanese-armour'],
      [74, 'maghreb-brass'], [80, 'toledo-blades'], [88, 'damascus-blades'],
    ],
  },
}

/** 4.4: experience a minute of work, by the level a job asks (1-9, 10-19, ... 90-100). */
const PAY = [5, 6, 8, 10, 12, 16, 20, 24, 32, 40]
export const payAt = (level) => PAY[Math.min(9, Math.floor(level / 10))]

/** 6.3: what a party-hour of a good is worth at a level, at base values. */
export const worthAt = (level) => 4800 + ((15000 - 4800) * (level - 1)) / 99

/**
 * 5.8 rule 2: the fastest pace a party can dig at, from 0455's knobs and tools (the migration's self-assert reads the live ones
 * and fails if any is faster than this): land_level_speed_pct 0.2 a level above 1 to Mining 100; the best tool of land_tools
 * (the plain pick, 3 %); land_crowd_max 10 % chance of a second unit a turn; land_yield_pct 100. A new tool, level or knob that
 * is faster moves these figures and re-emits the rows.
 */
export const FASTEST = { top: 100, levelSpeedPct: 0.2, toolPct: 3, crowdMaxPct: 10, yieldPct: 100 }

/**
 * 0461 (L2): the fastest pace of a MAKE job (the smith): its skill at 100, land_level_speed_pct 0.2 a level above 1, no tool (no tool
 * speeds a make job: land_actions.tool is null, and L2 makes no tool), no second unit for company (public.land_terms gives a make job
 * crowd 0), land_yield_pct 100. 0461's self-assert reads the live knobs and fails if a make job is faster.
 */
export const FASTEST_MAKE = { top: 100, levelSpeedPct: 0.2, toolPct: 0, crowdMaxPct: 0, yieldPct: 100 }

/** A turn at the fastest pace, rounded as public.land_terms rounds it. */
export const fastestTurn = (seconds, pace = FASTEST) =>
  Math.max(1, Math.round(seconds * (100 / pace.yieldPct) * (1 - (pace.levelSpeedPct / 100) * (pace.top - 1)) * (1 - pace.toolPct / 100)))

/** Units one party-hour can bring at the fastest pace. */
export const fastestHour = (seconds, pace = FASTEST) => (3600 / fastestTurn(seconds, pace)) * (1 + pace.crowdMaxPct / 100)

/** One job's seconds and experience, by the rule: the worth's time, the 40-s floor, and the market guard against `target`. */
export function jobFigures(level, base, target, pace = FASTEST) {
  const raw = (3600 * base) / worthAt(level)
  let seconds = Math.max(40, Math.round(raw / 5) * 5)
  if (target !== undefined) while (fastestHour(seconds, pace) > target / 100) seconds += 5
  const xp = Math.max(1, Math.round((seconds / 60) * payAt(level)))
  return { seconds, xp }
}

export function landRows() {
  const goods = JSON.parse(readFileSync(path.join(ROOT, 'data', 'goods.json'), 'utf8')).goods
  const byId = new Map(goods.map((g) => [g.id, g]))
  const guard = JSON.parse(readFileSync(path.join(ROOT, 'data', 'land-guard.generated.json'), 'utf8')).goods
  const rows = []
  for (const [skill, ladder] of Object.entries(LADDERS)) {
    ladder.goods.forEach(([level, code], i) => {
      const g = byId.get(code)
      if (!g) throw new Error(`build-land-migration: no good "${code}" in data/goods.json`)
      const base = (g.baseValue[0] + g.baseValue[1]) / 2
      if (!guard[code]) throw new Error(`build-land-migration: no guard figure for "${code}" (run scripts/db/measure-land-guard.mjs)`)
      const { seconds, xp } = jobFigures(level, base, guard[code].target)
      rows.push({ code, skill, kind: 'gather', level, seconds, xp, ground: ladder.ground, tool: ladder.tool, ord: i + 1 })
    })
  }
  return rows
}

/** The VALUES block, one row a line, exactly as the migration carries it. */
export function valuesBlock() {
  return landRows()
    .map((r, i, all) => `      ('${r.code}', '${r.skill}', '${r.kind}', ${r.level}, ${r.seconds}, ${r.xp}, '${r.ground}', '${r.tool}', ${r.ord})${i === all.length - 1 ? '' : ','}`)
    .join('\n')
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// L1c (migration 0458): MULES, REPEAT AND RARE FINDS, INSIDE THE SAME GUARD
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Each of these can raise what a party brings home an hour, so each is judged here by the guard above, at the same fastest pace:
//   REPEAT   the party goes out again by itself, trip after trip, with no idle time between: that is the pace fastestHour and
//            fastestHourPacked already count (trips back to back). Repeat off only adds idle time.
//   MULES    more packs a trip: p turns in a trip of 2 (s + m) + p x turn. A passage s and a march m only slow a party, so an hour
//            is at most p x 3600 / (2 m + p x turn) x the crowd's second unit (fastestHourPacked), which is UNDER fastestHour for
//            every p and m > 0: fastestHour is its bound as the packs grow. So the guard on the turn holds for any number of mules;
//            a mule saves walking (most on a far trip, where the passage is long) and never lifts an hour over the hundredth.
//   FINDS    a rare find is a second good G, rolled once a turn, one in `one_in` (FIND_ONE_IN, Melvor's gem on 1 action in 100). It
//            lands in G's market, so it is held to G's own guard: at the fastest pace of the job it comes from, finds of G an hour
//            (3600 / the turn / one_in; the crowd's second unit is the job's good, never a find) are at most a hundredth of G's
//            least middling target (data/land-guard.generated.json). one_in is raised until that holds.
//            WHICH finds: the gems of the skill's own ladder (data/goods.json category `gems`): every gem but the job's own good
//            whose land is one of the job's lands. At the press only those whose land is the land the party works roll
//            (public.land_terms, by public.goods.origin_regions): a good is found only where it lies, as it is dug only there.

/** The mules (design 6.2): the packs a trip carries after the 1st, 2nd, 3rd and 4th mule, and each mule's price to the home city. */
export const MULES = [
  { packs: 10, price: 3000 },
  { packs: 15, price: 8000 },
  { packs: 20, price: 20000 },
  { packs: 30, price: 50000 },
]

/** Units one party-hour can bring at the fastest pace with `packs` a trip and a march of `march` s each way, trips back to back. */
export const fastestHourPacked = (seconds, packs, march) =>
  ((packs * 3600) / (2 * march + packs * fastestTurn(seconds))) * (1 + FASTEST.crowdMaxPct / 100)

/** A rare find, by default: one turn in this many. */
export const FIND_ONE_IN = 100

/** One in how many turns a find of a good whose guard target is `findTarget` may come, off a job of `jobSeconds`: the guard. */
export function findOneIn(jobSeconds, findTarget) {
  let n = FIND_ONE_IN
  while (3600 / fastestTurn(jobSeconds) / n > findTarget / 100) n += 1
  return n
}

/** Finds of a good an hour at the fastest pace, off a job of `jobSeconds`, at one in `oneIn`. */
export const fastestFindsHour = (jobSeconds, oneIn) => 3600 / fastestTurn(jobSeconds) / oneIn

/** THE FINDS: one row a job a gem that can be found on its land. */
export function dropRows() {
  const goods = JSON.parse(readFileSync(path.join(ROOT, 'data', 'goods.json'), 'utf8')).goods
  const byId = new Map(goods.map((g) => [g.id, g]))
  const guard = JSON.parse(readFileSync(path.join(ROOT, 'data', 'land-guard.generated.json'), 'utf8')).goods
  const jobs = landRows()
  const rows = []
  for (const [skill, ladder] of Object.entries(LADDERS)) {
    const gems = ladder.goods.map(([, c]) => c).filter((c) => byId.get(c).category === 'gems')
    for (const j of jobs.filter((r) => r.skill === skill)) {
      const lands = byId.get(j.code).origin
      let ord = 0
      for (const gem of gems) {
        if (gem === j.code || !byId.get(gem).origin.some((r) => lands.includes(r))) continue
        rows.push({ action: j.code, good: gem, one_in: findOneIn(j.seconds, guard[gem].target), ord: ++ord })
      }
    }
  }
  return rows
}

/** The finds' VALUES block, one row a line, exactly as migration 0458 carries it. */
export function dropsBlock() {
  return dropRows()
    .map((r, i, all) => `      ('${r.action}', '${r.good}', ${r.one_in}, ${r.ord})${i === all.length - 1 ? '' : ','}`)
    .join('\n')
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// L2 (migration 0461): THE SMITH'S ROWS, BY THE SAME RULE
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A make job's seconds are jobFigures' (the worth's time of its product, the 40-s floor, the market guard) at FASTEST_MAKE against
// the product's least middling target of all 25 regions; its experience the seconds times the pay a minute of its level, as a
// gather job's. Its rows are 0461's block between its "smith" marker lines (tests/land.data.spec.ts).

/** THE SMITH'S JOBS: one row a product. */
export function smithRows() {
  const goods = JSON.parse(readFileSync(path.join(ROOT, 'data', 'goods.json'), 'utf8')).goods
  const byId = new Map(goods.map((g) => [g.id, g]))
  const guard = JSON.parse(readFileSync(path.join(ROOT, 'data', 'land-guard.generated.json'), 'utf8')).goods
  const rows = []
  for (const [skill, ladder] of Object.entries(MAKERS)) {
    ladder.goods.forEach(([level, code], i) => {
      const g = byId.get(code)
      if (!g) throw new Error(`build-land-migration: no good "${code}" in data/goods.json`)
      if (!guard[code]) throw new Error(`build-land-migration: no guard figure for "${code}" (run scripts/db/measure-land-guard.mjs)`)
      const base = (g.baseValue[0] + g.baseValue[1]) / 2
      const { seconds, xp } = jobFigures(level, base, guard[code].target, FASTEST_MAKE)
      rows.push({ code, skill, kind: 'make', level, seconds, xp, ord: i + 1 })
    })
  }
  return rows
}

/** The smith's VALUES block, one row a line, exactly as migration 0461 carries it. */
export function smithBlock() {
  return smithRows()
    .map((r, i, all) => `      ('${r.code}', '${r.skill}', '${r.kind}', ${r.level}, ${r.seconds}, ${r.xp}, ${r.ord})${i === all.length - 1 ? '' : ','}`)
    .join('\n')
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.stdout.write((process.argv.includes('--drops') ? dropsBlock() : process.argv.includes('--smith') ? smithBlock() : valuesBlock()) + '\n')
}
