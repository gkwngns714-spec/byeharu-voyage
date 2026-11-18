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
//                 experience = the seconds, times the pay a minute of the level it asks (4.4's steps), rounded, at least 1.
// WHERE A JOB IS DONE is NOT here: a gather job is done on the land of every region its good comes from
// (public.goods.origin_regions), read by public.land_passage at the press. The catalogue is the list of sites.
//
// USAGE
//   node scripts/build-land-migration.mjs          prints the VALUES block that 0455 carries between its two marker lines
// tests/land.data.spec.ts holds the migration's block equal to this file's output, so the rows cannot drift from the rule.
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

/** One job's seconds and experience, by the rule. */
export function jobFigures(level, base) {
  const raw = (3600 * base) / worthAt(level)
  const seconds = Math.max(40, Math.round(raw / 5) * 5)
  const xp = Math.max(1, Math.round((seconds / 60) * payAt(level)))
  return { seconds, xp }
}

export function landRows() {
  const goods = JSON.parse(readFileSync(path.join(ROOT, 'data', 'goods.json'), 'utf8')).goods
  const byId = new Map(goods.map((g) => [g.id, g]))
  const rows = []
  for (const [skill, ladder] of Object.entries(LADDERS)) {
    ladder.goods.forEach(([level, code], i) => {
      const g = byId.get(code)
      if (!g) throw new Error(`build-land-migration: no good "${code}" in data/goods.json`)
      const base = (g.baseValue[0] + g.baseValue[1]) / 2
      const { seconds, xp } = jobFigures(level, base)
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
