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
// tests/land.data.spec.ts holds that block equal to this file's output, so the rows cannot drift from the rule. 0455 carried the
// first cut (no market guard); 0457 carries the rows with the guard and is the block the spec reads.
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

/** A turn at the fastest pace, rounded as public.land_terms rounds it. */
export const fastestTurn = (seconds) =>
  Math.max(1, Math.round(seconds * (100 / FASTEST.yieldPct) * (1 - (FASTEST.levelSpeedPct / 100) * (FASTEST.top - 1)) * (1 - FASTEST.toolPct / 100)))

/** Units one party-hour can bring at the fastest pace. */
export const fastestHour = (seconds) => (3600 / fastestTurn(seconds)) * (1 + FASTEST.crowdMaxPct / 100)

/** One job's seconds and experience, by the rule: the worth's time, the 40-s floor, and the market guard against `target`. */
export function jobFigures(level, base, target) {
  const raw = (3600 * base) / worthAt(level)
  let seconds = Math.max(40, Math.round(raw / 5) * 5)
  if (target !== undefined) while (fastestHour(seconds) > target / 100) seconds += 5
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

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.stdout.write(valuesBlock() + '\n')
}
