// sides.mjs: run by `node scripts/ops/harness/raid/sim.mjs --sides [runs]` from the repo root. Real hulls on BOTH sides through public.fight_sides (docs/WORLD_POWERS.md section 12): 1 and 2 xebecs,
// a nau and 2 galion closing on a navire and on a galion, `runs` fights each, on prod's class figures (mini-world.mjs), whole hulls, level 1, no captain, no gear. Prints shares, claims nothing.
// 0327: also on the crewless `qpinnace`, the cargo ship that sails today, until W8 arms her. `won` is what pays gold: public.battle_resolve calls the same engine, no sizing up, so it is this table.
import { readFile } from 'node:fs/promises'
import { miniWorld, CLASSES } from './mini-world.mjs'

const runs = Number(process.argv[3] ?? 500)
const db = await miniWorld()
await db.exec((await readFile('supabase/migrations/20260818000320_a_fight_has_two_sides.sql', 'utf8')).replaceAll('\r', ''))
const uuid = (n) => `00000000-0320-4000-8000-${String(n).padStart(12, '0')}`
const hull = (code, n, hands) => { const [, name, attack, crew, tier, hullPts, accuracy, reach, armour, sighting] = CLASSES.find((c) => c[0] === code)
  return { id: uuid(n), name, tier, hull: hullPts, maxd: hullPts, crew: hands ?? crew, attack, accuracy, reach, armour, sighting } }
const SIDES = [['1 xebec', ['xebec']], ['2 xebecs', ['xebec', 'xebec']], ['1 nau', ['nau']], ['2 galion', ['galion', 'galion']]]
console.log(`${runs} fights each. Won = the side closing took her (PLUNDERED) or paid off (RANSOM). % hull = mean share of each side's hull lost.`)
for (const [prey, hands] of [['navire'], ['galion'], ['qpinnace', 0]]) for (const [label, hulls] of SIDES) {
  const a = JSON.stringify([hull(prey, 1, hands)]), b = JSON.stringify(hulls.map((c, i) => hull(c, i + 10)))
  const r = (await db.query(`select j->>'outcome' o, (j->'hull'->>'a')::numeric / (j->'hull'->>'a_start')::numeric ha, (j->'hull'->>'b')::numeric / (j->'hull'->>'b_start')::numeric hb
    from (select public.fight_sides(gen_random_uuid(), d, $1::jsonb, $2::jsonb) j from generate_series(1, $3::int) d) z`, [a, b, runs])).rows
  const n = (o) => r.filter((x) => o.includes(x.o)).length, pc = (x) => (x / r.length * 100).toFixed(1).padStart(5)
  const lost = (k) => (r.reduce((s, x) => s + 1 - Number(x[k]), 0) / r.length * 100).toFixed(1).padStart(5)
  console.log(`${label.padEnd(9)} on ${prey.padEnd(8)} won ${pc(n(['PLUNDERED', 'RANSOM']))}  plundered ${pc(n(['PLUNDERED']))}  ransom ${pc(n(['RANSOM']))}  driven off ${pc(n(['DRIVEN_OFF']))}  evaded ${pc(n(['EVADED']))}  hull lost: her ${lost('ha')}  theirs ${lost('hb')}`)
}
await db.close()
