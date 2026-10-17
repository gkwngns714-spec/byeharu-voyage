// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-captains.mjs — K4 "captains I": who every captain IS (grade, job, ten traits, languages) and
//                      what every harbour speaks (docs/SKILLS_AND_CAPTAINS.md §4.1, §4.2, §4.9, D10,
//                      D14, D15; migration 0156)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE CONCEPT, IN ONE NOUN PHRASE: a captain's card — her grade, her kit of traits and the languages
// she speaks — and a harbour's language. Generated, never typed, from two authored files:
//   data/officers.json   the people: code, name, job (`specialty`, the 25 trait codes), job value
//                        (`bonus_pct`), wage, nation, home harbour, blurb — 105 of them
//   data/captains.json   the catalogue: grades, foci, effects, traits, languages and the language
//                        rules
// WHERE IT LIVES AND WHY: here, beside build-ships.mjs / build-gear.mjs, because it is the same kind of
// thing — content as rows, with ONE generator, ONE output file and the world guard holding the
// database to both on every apply (scripts/db/world-guard.mjs re-runs generateCaptains()).
// THE SECOND CALLER: migration 0156 pastes `--sql`'s VALUES; K5 (cabins, seats, public.crew_pct) and
// K8 (promotion) read the rows this file generates through the tables, never through this file.
// WHAT WOULD MAKE IT THE WRONG SHAPE: a captain's numbers decided anywhere else (a second roster, a
// kit typed by hand, a harbour language guessed in SQL). The guard's both-directions check finds it.
//
// THE RULES (each one a DEFAULT of the plan, each one data in data/captains.json):
//   GRADE (D10)     the highest grade whose floor her job value reaches: C 4-5 %, B 5.5-6.5 %, A 7-8 %,
//                   S 8.5-9 % — the 63 captains of today fall 18 / 17 / 20 / 8, exactly the plan's count.
//   KIT (D15)       ten ordered traits: her job at her own value, then up to `same_focus` more of her
//                   job's focus, then the rest, each at `extra_pct` % of her value (tenths, exact: every
//                   value is a multiple of 0.5). The order after the first is md5(code:trait) — a pure
//                   function of who she is, so the kit is the same on every build.
//   LANGUAGES (D14) a harbour: `by_port`, else its nation's, else its culture's, else (a Latin harbour of
//                   no nation) its country's — none of these is a FAILURE, never a guess. A captain:
//                   her home harbour's, then `extra_languages[grade]` more: her own nation's language
//                   (when her home speaks another), then the languages most spoken in her home region,
//                   then the most spoken in the world (harbour counts, then catalogue order). No dice.
//   ROSTER (D15)    every trait is the job of at least two captains, one C or B and one A or S; every
//                   focus has a captain of every grade. Checked here, so a roster that breaks the rule
//                   cannot be generated.
//
// RUN:   node scripts/build-captains.mjs           writes data/captains.generated.json
//        node scripts/build-captains.mjs --check   fails if the file is not what the generator gives
//        node scripts/build-captains.mjs --sql     prints the VALUES migration 0156 loads
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { createHash } from 'node:crypto'
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { deriveWorld } from './lib/world-derive.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const readJson = (rel) => JSON.parse(readFileSync(join(ROOT, rel), 'utf8'))
export const CAPTAINS_FILE = 'data/captains.generated.json'

const md5 = (s) => createHash('md5').update(s).digest('hex')
const fail = (msg) => { throw new Error(`build-captains: ${msg}`) }

/** The authored inputs, read once. Exported so the world guard compares against the SAME reading. */
export function captainInputs() {
  return { people: readJson('data/officers.json').officers, cat: readJson('data/captains.json') }
}

/** Every harbour's language by the rule in data/captains.json — `{ port: code, language: code }`. */
export function harbourLanguages(cat = captainInputs().cat, ports = deriveWorld().ports) {
  const langs = new Set(cat.languages.map((l) => l.code))
  const usedCountry = new Set()
  const out = ports.map((p) => {
    let lang = cat.by_port[p.code] ?? (p.nation_code ? cat.by_nation[p.nation_code] : undefined) ?? cat.by_culture[p.culture]
    if (lang === undefined && !p.nation_code) {
      lang = cat.by_country[p.country]
      if (lang !== undefined) usedCountry.add(p.country)
    }
    if (lang === undefined) fail(`harbour ${p.code} (${p.name}: ${p.nation_code ?? 'no nation'}, ${p.culture}, ${p.country}) has no language by any rule — name it in data/captains.json`)
    if (!langs.has(lang)) fail(`harbour ${p.code} speaks ${lang}, which is not in the language catalogue`)
    return { port: p.code, language: lang }
  })
  for (const c of Object.keys(cat.by_country)) if (!usedCountry.has(c)) fail(`by_country names ${c}, which no Latin harbour of no nation needs (a dead rule)`)
  for (const l of langs) if (!out.some((h) => h.language === l)) fail(`no harbour speaks ${l}`)
  return out.sort((a, b) => a.port.localeCompare(b.port))
}

/** The whole generated card set. Pure in the three data files. */
export function generateCaptains() {
  const { people, cat } = captainInputs()
  const world = deriveWorld()
  const harbour = new Map(world.ports.map((p) => [p.code, p]))
  const nations = new Set(world.nations.map((n) => n.code))
  const traits = new Map(cat.traits.map((t) => [t.code, t]))
  const effects = new Map(cat.effects.map((e) => [e.code, e]))
  const foci = new Set(cat.foci.map((f) => f.code))
  const grades = [...cat.grades].sort((a, b) => a.ord - b.ord)
  const goods = new Set(readJson('data/goods.json').goods.map((g) => g.category))

  // ── the catalogue is whole ──
  for (const t of cat.traits) {
    if (!foci.has(t.focus)) fail(`trait ${t.code}: focus ${t.focus} is not a focus`)
    if (!t.effects.length) fail(`trait ${t.code} does nothing`)
    for (const e of t.effects) if (!effects.has(e.effect)) fail(`trait ${t.code}: effect ${e.effect} is not in the effect table`)
    if (t.effects.some((e) => e.effect === 'category_spread') !== Boolean(t.goods)) fail(`trait ${t.code}: a trader names its goods category, and only a trader`)
    if (t.goods && !goods.has(t.goods)) fail(`trait ${t.code}: goods category ${t.goods} is not in data/goods.json`)
  }
  for (const c of goods) if (!cat.traits.some((t) => t.goods === c)) fail(`goods category ${c} has no trader (O5: one captain for each role)`)
  for (const e of cat.effects) if (!cat.traits.some((t) => t.effects.some((x) => x.effect === e.code))) fail(`effect ${e.code} is carried by no trait`)

  const langs = harbourLanguages(cat, world.ports)
  const portLang = new Map(langs.map((h) => [h.port, h.language]))
  const langOrd = new Map(cat.languages.map((l) => [l.code, l.ord]))
  const spoken = new Map()   // how many harbours speak each language: the world's lingua francas first
  for (const h of langs) spoken.set(h.language, (spoken.get(h.language) ?? 0) + 1)

  const gradeOf = (pct) => {
    const g = grades.filter((x) => pct >= x.floor_pct).pop()
    if (!g) fail(`a job value of ${pct} % is below every grade's floor`)
    return g.code
  }
  const tenths = (pct) => {
    const t = pct * 10
    if (Math.abs(t - Math.round(t)) > 1e-9) fail(`job value ${pct} is not in tenths`)
    return Math.round(t)
  }

  const seen = new Set()
  const captains = people.map((o) => {
    if (seen.has(o.code)) fail(`duplicate captain code ${o.code}`)
    seen.add(o.code)
    if (!/^[A-Z0-9]{2,16}$/.test(o.code)) fail(`bad code ${o.code}`)
    if (!(o.bonus_pct > 0 && o.bonus_pct <= 25)) fail(`${o.code}: job value out of band`)
    if (!(Number.isInteger(o.wage) && o.wage > 0)) fail(`${o.code}: wage must be a positive whole number`)
    if (!o.blurb || o.blurb.length < 12) fail(`${o.code}: every captain carries a line about who they are`)
    if (o.nation !== null && !nations.has(o.nation)) fail(`${o.code}: nation ${o.nation} is not a nation`)
    const home = harbour.get(o.home)
    if (!home) fail(`${o.code}: home ${o.home} is not a harbour`)
    const job = traits.get(o.specialty)
    if (!job) fail(`${o.code}: job ${o.specialty} is not a trait`)

    const grade = gradeOf(o.bonus_pct)
    const base = tenths(o.bonus_pct)
    const extra = Math.round((base * cat.kit.extra_pct) / 100) / 10
    const order = (list) => [...list].sort((a, b) => md5(`${o.code}:${a.code}`).localeCompare(md5(`${o.code}:${b.code}`)))
    const same = order(cat.traits.filter((t) => t.focus === job.focus && t.code !== job.code)).slice(0, cat.kit.same_focus)
    const rest = order(cat.traits.filter((t) => t.code !== job.code && !same.includes(t))).slice(0, cat.kit.size - 1 - same.length)
    const kit = [{ trait: job.code, pct: base / 10 }, ...[...same, ...rest].map((t) => ({ trait: t.code, pct: extra }))]
    if (kit.length !== cat.kit.size) fail(`${o.code}: a kit of ${kit.length}`)

    const own = portLang.get(home.code)
    const n = cat.extra_languages[grade]
    const region = new Map()
    for (const p of world.ports) {
      if (p.region_code !== home.region_code) continue
      const l = portLang.get(p.code)
      if (l !== own) region.set(l, (region.get(l) ?? 0) + 1)
    }
    const byCount = (m) => [...m.entries()].sort((a, b) => b[1] - a[1] || langOrd.get(a[0]) - langOrd.get(b[0])).map(([l]) => l)
    const nationLang = o.nation ? cat.by_nation[o.nation] : undefined
    const talks = [...new Set([...(nationLang && nationLang !== own ? [nationLang] : []), ...byCount(region), ...byCount(spoken)])]
      .filter((l) => l !== own)
    const languages = [own, ...talks.slice(0, n)]

    return { code: o.code, grade, job: job.code, kit, languages }
  })

  // ── the roster rule (D15, O5) ──
  const low = new Set(['C', 'B'])
  for (const t of cat.traits) {
    const mine = captains.filter((c) => c.job === t.code)
    if (mine.length < 2) fail(`trait ${t.code} is the job of ${mine.length} captain(s); every job has at least two`)
    if (!mine.some((c) => low.has(c.grade)) || !mine.some((c) => !low.has(c.grade))) fail(`trait ${t.code} needs one C or B captain and one A or S captain`)
  }
  for (const f of foci) {
    for (const g of grades) {
      if (!captains.some((c) => c.grade === g.code && traits.get(c.job).focus === f)) fail(`no ${g.code} captain has a ${f} job`)
    }
  }

  return {
    _: 'GENERATED by scripts/build-captains.mjs from data/officers.json + data/captains.json (+ data/ports.json through world-derive) — do not edit; edit the data and re-run it (docs/SKILLS_AND_CAPTAINS.md K4, migration 0156).',
    captains,
    harbours: langs,
  }
}

const q = (s) => (s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "''")}'`)
const num = (n) => String(Number(n))

/** The SQL VALUES migration 0156 loads, pasted into it verbatim; the world guard holds the database to
 *  generateCaptains() and the two data files on every apply, so the migration and the data cannot drift. */
export function captainsSql(gen = generateCaptains()) {
  const { people, cat } = captainInputs()
  const live = new Set(['NAVIGATOR', 'QUARTERMASTER', 'PURSER', 'SURGEON'])
  const isNew = (o) => !OLD_63.has(o.code)
  const rows = (list) => list.join(',\n')
  const fresh = people.filter(isNew)
  return [
    '-- @@foci',
    rows(cat.foci.map((f, i) => `  (${q(f.code)}, ${q(f.word)}, ${i + 1})`)),
    '-- @@grades',
    rows(cat.grades.map((g) => `  (${q(g.code)}, ${g.ord}, ${g.slots}, ${g.known}, ${num(g.floor_pct)})`)),
    '-- @@effects',
    rows(cat.effects.map((e, i) => `  (${q(e.code)}, ${i + 1}, ${q(e.scope)}, ${e.live}, ${q(e.words)}, ${q(e.waits)}, ${q(e.reader)})`)),
    '-- @@traits',
    rows(cat.traits.map((t) => `  (${q(t.code)}, ${t.ord}, ${q(t.word)}, ${q(t.focus)}, ${q(t.goods ?? null)}, ${q(t.goods_word ?? null)})`)),
    '-- @@trait_effects',
    rows(cat.traits.flatMap((t) => t.effects.map((e, i) => `  (${q(t.code)}, ${q(e.effect)}, ${i + 1}, ${num(e.mult)})`))),
    '-- @@languages',
    rows(cat.languages.map((l) => `  (${q(l.code)}, ${l.ord}, ${q(l.name)})`)),
    '-- @@port_language',
    rows(gen.harbours.map((h) => `  (${q(h.port)}, ${q(h.language)})`)),
    `-- @@officers (the ${fresh.length} new captains; the ${people.length - fresh.length} of today are already rows)`,
    rows(fresh.map((o) => `  (${q(o.code)}, ${q(o.name)}, ${q(o.specialty)}, ${num(o.bonus_pct)}, ${o.wage}, ${q(o.nation)}, ${q(o.home)}, ${q(o.blurb)})`)),
    '-- @@captain_profile',
    rows(gen.captains.map((c) => `  (${q(c.code)}, ${q(c.grade)}, ${q(c.job)})`)),
    '-- @@captain_traits',
    rows(gen.captains.flatMap((c) => c.kit.map((k, i) => `  (${q(c.code)}, ${i + 1}, ${q(k.trait)}, ${num(k.pct)})`))),
    '-- @@captain_languages',
    rows(gen.captains.flatMap((c) => c.languages.map((l, i) => `  (${q(c.code)}, ${i + 1}, ${q(l)})`))),
    `-- @@live (${[...live].join(', ')} — the four jobs public.fleet_officer_bonus has always read)`,
  ].join('\n')
}

/** The 63 captains production holds before 0156 (0015's 8, 0073's 43, 0098's 12). Their rows are not
 *  re-inserted; 0156 asserts every one of them equals data/officers.json instead. */
export const OLD_63 = new Set(('ALBUQUERQ ALCANT AMSPURSER BARENTS BARROS BERGENNAV CABRALNAV CHANCELLOR COENQM DANESURG DIASNAV ' +
  'ELCANO FUGGER GARCIAORTA GENOAQM GRESHAM GUJARATQM HANSEQM HAWKINSQM HEOJUN HOLBEK IBNMAJID JEONGNAV LISHIZHEN ' +
  'MALACCANAV MALSURG MEDICI MENDANA MONARDES MOREAU MOROCCOQM MUGPURSER NPCPILOTGEN NPCPILOTMNG NPCPILOTOTT ' +
  'NPCPILOTPRT NPCPURSERESP NPCPURSERMUG NPCPURSERVEN NPCQMHAN NPCQMJPN NPCQMNLD NPCSURGENG NPCSURGFRA OTTPURSER ' +
  'PERSSURG PINZON PIRIREIS POLPURSER PORTPURSER RUSPURSER SABUNCU SAKAIPURSER SAKAIQM SEVPURSER SWEDQM TULPSURG ' +
  'VENEZNAV VENSURG WELSER WOODALL ZAHRA ZHENGPIL').split(' '))

if (process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('scripts/build-captains.mjs')) {
  const gen = generateCaptains()
  const text = JSON.stringify(gen, null, 1) + '\n'
  const grades = gen.captains.reduce((m, c) => ({ ...m, [c.grade]: (m[c.grade] ?? 0) + 1 }), {})
  const say = `${gen.captains.length} captains (C ${grades.C ?? 0} · B ${grades.B ?? 0} · A ${grades.A ?? 0} · S ${grades.S ?? 0}), ${gen.harbours.length} harbours`
  if (process.argv.includes('--sql')) {
    console.log(captainsSql(gen))
  } else if (process.argv.includes('--check')) {
    const now = readFileSync(join(ROOT, CAPTAINS_FILE), 'utf8')
    if (now !== text) { console.error(`${CAPTAINS_FILE} is NOT what scripts/build-captains.mjs generates — re-run it.`); process.exit(1) }
    console.log(`${CAPTAINS_FILE} equals the generator: ${say}.`)
  } else {
    writeFileSync(join(ROOT, CAPTAINS_FILE), text)
    console.log(`wrote ${CAPTAINS_FILE}: ${say}`)
  }
}
