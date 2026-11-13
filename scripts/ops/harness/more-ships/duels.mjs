// duels.mjs - LOCAL ONLY (PGlite, the cached world; never from zero; not in CI). The balance arithmetic of migration 0366, fought by the REAL engine.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/more-ships/duels.mjs [--seeds=200] [--matrix] [--md]
//
// Every hull is read from data/ships.generated.json (the generator's figures: what a new, unfitted hull is with no skills; a full crew in a duel, the crew she must have against a raid), built as one side of
// public.fight_sides and fought over N seeds, both ways round (`a` is set upon and never breaks off; `b` closes and breaks off at fight_raider_break of her hull lost).
// A duel's line:  held = a was not taken (EVADED or DRIVEN_OFF), paid = RANSOM, lost = PLUNDERED; hull% = the share of her own hull each side lost, on average.
//   default   each Wave E hull against two older hulls of its size (the nearest combat hull of her own line or the Portuguese one, and the nearest trader), both ways round.
//   --matrix  the jobs against each other at heavy size (rock, paper, scissors), and an escort beside a carrier against raiders.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, REPO_ROOT, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k, d) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3) ?? d
const SEEDS = Number(arg('seeds', '200'))
const NAME = '20260818000366_'
const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue   // the engine is the live one: 0366 moves no function
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: process.env.BYEHARU_PREFIX_CACHE === 'required', snapshots: false })
const db = out.db
const gen = JSON.parse(await readFile(path.join(REPO_ROOT, 'data', 'ships.generated.json'), 'utf8'))
const byCode = new Map(gen.hulls.map((h) => [h.class, h]))
const side = (codes, tag, crew = 'crewMax') => JSON.stringify(codes.map((c, i) => {
  const h = byCode.get(c)
  if (!h) throw new Error(`no hull ${c}`)
  return { id: `00000000-0366-4000-8000-0000000${tag}${String(i).padStart(4, '0')}`, name: h.name, tier: h.tier, hull: h.durability, maxd: h.durability, crew: h[crew],
    attack: h.attack, accuracy: h.accuracy, reach: h.reach, armour: h.armour, sighting: h.sighting }
}))
const hullOf = (codes) => codes.reduce((t, c) => t + byCode.get(c).durability, 0)

/** `a` set upon by `b`, over SEEDS seeds: the outcomes from a's side and the hull each side lost. */
async function duel(a, b, raid = null) {
  const r = (await db.query(`
    select count(*) filter (where f->>'outcome' in ('EVADED', 'DRIVEN_OFF'))::int as held,
           count(*) filter (where f->>'outcome' = 'RANSOM')::int as paid,
           count(*) filter (where f->>'outcome' = 'PLUNDERED')::int as lost,
           count(*) filter (where (f->>'slipped')::boolean)::int as slipped,
           count(*) filter (where (f->>'broke_off')::boolean)::int as broke,
           avg(((f->'hull'->>'a_start')::numeric - (f->'hull'->>'a')::numeric))::float8 as a_lost,
           avg(((f->'hull'->>'b_start')::numeric - (f->'hull'->>'b')::numeric))::float8 as b_lost
      from (select public.fight_sides(md5('0366:' || i)::uuid, 1, $1::jsonb, case when $4::numeric is null then $2::jsonb else voyage.raider_hulls($4::numeric) end, '{}'::jsonb) as f from generate_series(1, $3::int) i) x`,
  [side(a, 'a', raid === null ? 'crewMax' : 'crewRequired'), side(b, 'b'), SEEDS, raid])).rows[0]
  const pc = (n) => Math.round((n / SEEDS) * 100)
  return { held: pc(r.held), paid: pc(r.paid), lost: pc(r.lost), slipped: pc(r.slipped), broke: pc(r.broke),
    aHull: Math.round((r.a_lost / hullOf(a)) * 100), bHull: Math.round((r.b_lost / hullOf(b)) * 100) }
}
const line = (d) => `held ${d.held} % (slipped ${d.slipped}, drove off ${d.broke}), paid ${d.paid} %, lost ${d.lost} %; hull lost ${d.aHull} % / theirs ${d.bHull} %`
const name = (c) => byCode.get(c).name

const t0 = Date.now()
if (process.argv.includes('--matrix')) {
  // rock, paper, scissors at heavy size, and the smaller jobs at light size
  for (const set of [['greatgalley', 'daemaeng', 'nef', 'almiranta', 'nao', 'galeon', 'racegal'], ['galeoncete', 'galera', 'friedeschiff', 'kotia', 'galere', 'pinas'],
    ['balinger', 'wugong', 'kalyata', 'wafter', 'kogge', 'xebec', 'carred'], ['goke', 'naucap', 'louchuan', 'galeazza', 'kalyon', 'grandnav']]) {
    console.log(`\n| set upon \\ closes | ${set.map(name).join(' | ')} |`)
    console.log(`|---|${set.map(() => '---').join('|')}|`)
    for (const a of set) {
      const cells = []
      for (const b of set) {
        if (a === b) { cells.push('-'); continue }
        const d = await duel([a], [b])
        cells.push(`${d.held}`)
      }
      console.log(`| ${name(a)} | ${cells.join(' | ')} |`)
    }
  }
  // a fleet set upon by a RAID as the game builds one (voyage.raider_hulls: one squadron hull of fight_raider_class, strength 12.7 a xebec)
  console.log('\n| fleet set upon by a raid | 1 xebec | 2 xebecs | 4 xebecs | 6 xebecs |')
  console.log('|---|---|---|---|---|')
  for (const convoy of [['hoy'], ['hoy', 'wafter'], ['hoy', 'carred'], ['kogge'], ['buss'], ['holk'], ['fluyt'], ['kotia'], ['baghlah'], ['byeongjo'], ['joun'], ['holk', 'friedeschiff'], ['holk', 'pinas'],
    ['caochuan', 'jungmaeng'], ['nao'], ['urca'], ['taforeia'], ['taforeia', 'almiranta'], ['taforeia', 'galeon'], ['jong'], ['navegrossa']]) {
    const cells = []
    for (const n of [1, 2, 4, 6]) {
      const d = await duel(convoy, Array(n).fill('xebec'), n * 12.7)
      cells.push(`held ${d.held}, paid ${d.paid}, lost ${d.lost}`)
    }
    console.log(`| ${convoy.map(name).join(' + ')} | ${cells.join(' | ')} |`)
  }
} else {
  const older = gen.hulls.filter((h) => h.wave !== 'E' && h.tech === 'T1')
  const nearest = (n, role) => {
    const pool = older.filter((h) => h.size === n.size && h.role === role)
    const fallback = older.filter((h) => h.role === role).sort((x, y) => Math.abs(x.size - n.size) - Math.abs(y.size - n.size))
    return (pool.find((h) => h.line === n.line) ?? pool.find((h) => h.line === 'PRT') ?? pool[0] ?? fallback[0]).class
  }
  for (const n of gen.hulls.filter((h) => h.wave === 'E')) {
    const foes = [...new Set([nearest(n, 'combat'), nearest(n, 'trade')])]
    for (const foe of foes) {
      const set = await duel([n.class], [foe])
      const closes = await duel([foe], [n.class])
      console.log(`| ${n.name} (${n.job ?? n.role}) | ${name(foe)} | ${line(set)} | ${line(closes)} |`)
    }
  }
}
console.log(`\n${SEEDS} seeds a duel, ${((Date.now() - t0) / 1000).toFixed(0)} s`)
await db.close()
