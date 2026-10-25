// ═══════════════════════════════════════════════════════════════════════════════════════════════
// world-guard.mjs — ON EVERY APPLY: the applied world must EQUAL data/*.json, or the run fails.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHY THIS EXISTS. On 2026-08-24 migration 0003 was found to have been edited AFTER production
// applied it: production held 70 goods while every fresh rebuild got 243, and ten island ports in
// data/ports.json existed in no database at all. Nothing red happened anywhere — the chain was
// green, the proofs were green, and the world was simply not the data. This guard makes that class
// of drift impossible to commit silently: apply-chain.mjs calls it after the chain lands, so
// `npm run db:apply`, `npm run db:proof` and CI's apply-proof job all fail loudly the moment the
// chain's world and data/*.json disagree — whichever of the two moved.
//
// WHAT "EQUAL" MEANS HERE
//   * harbours    every port in data/ports.json exists (by pinned code), every column the chain
//                 derives from the data is equal, both directions — EXCEPT crew_pool, which is
//                 seeded once and then owned by the running game (0007 hire drains it)
//   * goods       every good, every column, both directions
//   * offers      every port's port_specialties rows equal its `goods` array, as a set
//   * (legs)      RETIRED 2026-08-24 with migration 0049: public.legs and data/sea-routes.json
//                 are both gone — the raster (0046) is the one authority for what water connects
//                 to what, cross-checked against 0040's sea-membership at generation. Sea places
//                 are still checked to exist and sit where data/sea-places.json says.
//   * seas/regions/nations   the code+name sets are equal
//   * market      exactly one port_goods row per (harbour, good) — the market covers the world
//   * nations     (0130) also each nation's flag and capital, as world-derive.mjs derives them
//   * ship lines  (0130) public.ship_lines and public.class_profile EQUAL data/ship-lines.json,
//                 every column, both directions — the eleven lines (builders, arsenal, modifiers,
//                 traits) and every hull's line / size / role / tech / deck / any_yard
//   * skills      (0131) public.skill_groups, public.skills + skill_profile + skill_prereqs EQUAL
//                 data/skills.json, both directions — every skill's name, group, rank, enrolment,
//                 line and prerequisites; the 88 new ones' blurb and NONE / 0
//   * gear        (0132) public.gear_racks, public.item_profile, the RACK rows of public.class_slots
//                 and public.class_slot_unlocks EQUAL data/gear.json, every column, both directions
//   * skill effects / requirements (0133) public.skill_effects EQUALS data/skills.json `effects` plus
//                 every hull skill's line traits (data/ship-lines.json, sizes by the skill's suffix,
//                 Capital = 5 and 6), every row and its per cent, both directions; the four company
//                 rows mirror skills.effect / pct_per_level; public.skill_requirements EQUALS
//                 data/skills.json `requirements`, both directions
//   * waves A + B (0135, 0138) the GENERATORS are re-run here: scripts/build-ships.mjs `generateShips()` and
//                 scripts/build-gear.mjs `generateGear()` must equal data/ships.generated.json and
//                 data/gear.generated.json byte for byte, AND the database: public.ship_classes (every
//                 column), class_profile, the rack rows of class_slots, class_cabins, hull_recipes +
//                 hull_recipe_goods + hull_recipe_items, item_kinds, item_profile, item_effects,
//                 item_recipes and skill_requirements EQUAL the live rows' data files (data/hulls.json,
//                 data/fittings.json, data/gear.json, data/ship_stats.json, data/ship-lines.json) plus
//                 what the generators give, every column, both directions
//                 (0138 added Wave B — 15 capitals and flagships — to the SAME generator, so this
//                 one check holds all 67 generated hulls; no second copy of the rule; 0162 and 0166 added
//                 Waves C and D the same way — 100 generated hulls — and a famous hull's one fitting, its
//                 famous gear, is held in hull_recipe_items with the live three's)
//   * item use    (0158, S13) public.item_use EQUALS the gear generator's `use` (scripts/build-gear.mjs
//                 USE_BY_BASE — what wears every item and what an active consumes), every item, both
//                 directions; the 14 refits ride in `generateGear()`'s items with the rest of the gear; (0166) the
//                 three promotion items of data/captains.json are in it too, never wearing and spending nothing
//   * named items (0159, S15) public.item_city EQUALS the gear generator's Named items' `city`, both
//                 directions (a Named item is made only in that city's workshop)
//   * items made nowhere (0184) public.item_unmade EQUALS the gear generator's items written `made: false`
//                 (the Famous pieces while scripts/build-gear.mjs FAMOUS_MADE is false), both directions
//   * perks, sets, Country lines (0163, S16) public.perks, public.gear_set_bonuses and public.gear_set_names
//                 EQUAL data/gear.json `perks` / `sets`, and public.item_line the gear generator's Country
//                 items' `line`, every column, both directions
//   * great powers (0187, GP1) public.great_powers EQUALS world-derive.mjs GREAT_POWERS, both
//                 directions; only a great power has home cities, and every one has four
//   * home cities (0143) public.port_allegiance's `home` rows EQUAL data/home-ports.json, both
//                 directions; every country has 3 or 4; no harbour is home to two; every home city
//                 flies its own country (a home never changes hands — docs/INFLUENCE.md §3.2).
//                 Who holds a CONTESTED city is the game's, not the data's, and is not checked.
//   * captains    (0156, K4) public.officers EQUALS data/officers.json, every column, both directions (the
//                 105 people); the catalogue — trait_foci, captain_grades, crew_effects, traits,
//                 trait_effects, languages — EQUALS data/captains.json; and the GENERATOR is re-run:
//                 scripts/build-captains.mjs `generateCaptains()` must equal data/captains.generated.json
//                 byte for byte AND the database: captain_profile, captain_traits, captain_languages and
//                 port_language, every row, both directions; (0157, K5) each effect's cap, the cabin kinds
//                 and the rotation of cabins by hull role; (0162, K8) the grades' promotion gates, the
//                 promotion items (item_kinds rows of kind 'promotion' + public.promotion_items)
//
//   * hauls       (0173) every port_goods row's haul_nm / haul EQUALS world.haul_rows() — derived from the
//                 roster, public.sea_reaches and the haul_* knobs, and refilled by no later apply
//   * faiths      (0185) world.faiths, world.culture_faith, world.port_faith_override and world.faith_demand
//                 EQUAL data/faiths.json and data/faith-demand.json, both directions; every port_goods row's
//                 demand EQUALS world.demand_for() (the region × category taste × the faith × good taste)
//   * relations   (0195) public.power_relations EQUALS data/relations.json, every pair (unordered), its
//                 stance and its why, both directions
// WHAT IT DOES NOT CHECK (and why): runtime state (stock, drift, season_mod, crew_pool — the
// game's, not the data's); affinity values (0041's self-assert pins them to the one formula, and
// re-runs on every chain apply); the browser's own apply (src/lib/db) — the chain FINGERPRINT
// guarantees the browser applies the same bytes this guard just certified.
//
// POSITIVE CONTROL, EVERY RUN: before certifying, the comparator is aimed at a deliberately
// mutated copy of the derived world (one harbour dropped, one good's value bent) and MUST report both
// wounds. A guard that cannot see a planted drift certifies nothing (proofs-never-assert rule).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { deriveWorld, goodsAtPriceLevel, GREAT_POWERS, REPO_ROOT, round2, waveResistance } from '../lib/world-derive.mjs'
import { generateShips, SHIPS_FILE } from '../build-ships.mjs'
import { generateGear, GEAR_FILE } from '../build-gear.mjs'
import { captainInputs, generateCaptains, CAPTAINS_FILE } from '../build-captains.mjs'

/** 0158: what an item consumes, as one comparable string (jsonb re-orders an object's keys). */
const consumedKey = (list) => list.map((c) => `${c.good} ${Number(c.qty)}`).join(', ')

/** 0133: one skill effect's identity — every column but the per cent. */
const effectKey = (e) => [e.skill, e.scope, e.stat, e.line ?? '', e.size ?? '', e.role ?? '', e.tech ?? ''].join('/')

/** 0133: the skill effects data/skills.json and data/ship-lines.json describe — each listed `effects`
 *  row, and every hull skill's two line traits on its line's hulls of its size (`hull` is durability;
 *  Capital Hulls also on size 6, the flagship). */
function wantedSkillEffects(skills, lines) {
  const out = []
  for (const s of skills) {
    for (const e of s.effects ?? []) {
      out.push({ skill: s.code, scope: e.scope, stat: e.stat, pct: Number(e.pct), line: e.line ?? null,
        size: e.size ?? null, role: e.role ?? null, tech: e.tech ?? null })
    }
  }
  const sizes = { SMALL: [1], LIGHT: [2], MEDIUM: [3], HEAVY: [4], CAPITAL: [5, 6] }
  for (const l of lines) {
    for (const [suffix, list] of Object.entries(sizes)) {
      for (const size of list) {
        for (const t of l.traits) {
          out.push({ skill: `${l.code}_${suffix}`, scope: 'ship', stat: t.stat === 'hull' ? 'durability' : t.stat,
            pct: Number(t.pct), line: l.code, size, role: null, tech: null })
        }
      }
    }
  }
  return out
}

/** Compare the applied world (queried once, below) against a derived world. Pure. */
function drift(db_, want) {
  const out = []
  const say = (s) => out.push(s)

  // harbours
  const wPorts = new Map(want.ports.map((p) => [p.code, p]))
  for (const p of db_.ports) if (!wPorts.has(p.code)) say(`harbour ${p.code} (${p.name}) is in the database but not in data/ports.json`)
  for (const p of want.ports) {
    const d = db_.ports.find((x) => x.code === p.code)
    if (!d) { say(`harbour ${p.code} (${p.name}) is in data/ports.json but not in the database`); continue }
    const pairs = [
      ['name', d.name, p.name], ['country', d.country, p.country],
      ['nation', d.nation_code ?? null, p.nation_code ?? null],
      ['lat', Number(d.lat), p.lat], ['lon', Number(d.lon), p.lon],
      ['sea', d.sea_code, p.sea_code], ['region', d.region_code, p.region_code],
      ['culture', d.culture, p.culture], ['size_tier', Number(d.size_tier), p.size_tier],
      ['max_draft', Number(d.max_draft), p.max_draft], ['yard_tier', Number(d.yard_tier), p.yard_tier],
      ['has_yard', Boolean(d.has_yard), p.has_yard], ['has_academy', Boolean(d.has_academy), p.has_academy],
      ['dev_industry', Number(d.dev_industry), p.dev_industry],
      ['dev_commerce', Number(d.dev_commerce), p.dev_commerce],
      ['dev_military', Number(d.dev_military), p.dev_military],
    ]
    for (const [col, got, wanted] of pairs) {
      if (String(got) !== String(wanted)) say(`harbour ${p.code}.${col}: database has ${got}, data says ${wanted}`)
    }
  }

  // goods
  const wGoods = new Map(want.goods.map((g) => [g.code, g]))
  for (const g of db_.goods) if (!wGoods.has(g.code)) say(`good ${g.code} is in the database but not in data/goods.json`)
  for (const g of want.goods) {
    const d = db_.goods.find((x) => x.code === g.code)
    if (!d) { say(`good ${g.code} (${g.name}) is in data/goods.json but not in the database`); continue }
    const arr = (v) => (Array.isArray(v) ? v : String(v ?? '{}').replace(/[{}"]/g, '').split(',').filter(Boolean))
    const dMask = arr(d.culture_mask)
    // 0062: origin/entrepot are world data like any other column — drift here is drift.
    if (JSON.stringify(arr(d.origin_regions)) !== JSON.stringify(g.origin_regions)) {
      say(`good ${g.code}.origin_regions: {${arr(d.origin_regions)}} vs {${g.origin_regions}}`)
    }
    if (JSON.stringify(arr(d.entrepot_ports)) !== JSON.stringify(g.entrepot_ports)) {
      say(`good ${g.code}.entrepot_ports: {${arr(d.entrepot_ports)}} vs {${g.entrepot_ports}}`)
    }
    if (d.name !== g.name) say(`good ${g.code}.name: database has ${d.name}, data says ${g.name}`)
    if (Math.abs(Number(d.base_value) - g.base_value) > 1e-9) say(`good ${g.code}.base_value: ${d.base_value} vs ${g.base_value}`)
    if (Math.abs(Number(d.bulk) - g.bulk) > 1e-9) say(`good ${g.code}.bulk: ${d.bulk} vs ${g.bulk}`)
    if (Math.abs(Number(d.perishable_pct_day) - g.perishable_pct_day) > 1e-9) say(`good ${g.code}.perishable: ${d.perishable_pct_day} vs ${g.perishable_pct_day}`)
    if (d.category !== g.category) say(`good ${g.code}.category: ${d.category} vs ${g.category}`)
    if (JSON.stringify(dMask) !== JSON.stringify(g.culture_mask)) say(`good ${g.code}.culture_mask: {${dMask}} vs {${g.culture_mask}}`)
  }

  // offers
  const dSpec = new Set(db_.spec.map((s) => `${s.port}|${s.good}`))
  const wSpec = new Set(want.specialtyPairs.map(([p, g]) => `${p}|${g}`))
  for (const k of wSpec) if (!dSpec.has(k)) say(`offer ${k.replace('|', '·')} is in a data roster but not in port_specialties`)
  for (const k of dSpec) if (!wSpec.has(k)) say(`offer ${k.replace('|', '·')} is in port_specialties but in no data roster`)

  // sea places
  const wPlaces = new Map(want.places.map((p) => [p.code, p]))
  for (const p of db_.places) if (!wPlaces.has(p.code)) say(`sea place ${p.code} (${p.name}) is in the database but not in data/sea-places.json`)
  for (const p of want.places) {
    const d = db_.places.find((x) => x.code === p.code)
    if (!d) { say(`sea place ${p.code} (${p.name}) is in data/sea-places.json but not in the database`); continue }
    if (d.name !== p.name) say(`sea place ${p.code}.name: ${d.name} vs ${p.name}`)
    if (Math.abs(Number(d.lat) - round2(p.lat)) > 1e-9 || Math.abs(Number(d.lon) - round2(p.lon)) > 1e-9) {
      say(`sea place ${p.code} sits at (${d.lat}, ${d.lon}); data says (${round2(p.lat)}, ${round2(p.lon)})`)
    }
  }

  // seas / regions / nations
  const setCheck = (dbRows, wantRows, what) => {
    const ds = new Set(dbRows.map((x) => `${x.code}|${x.name}`))
    const ws = new Set(wantRows.map((x) => `${x.code}|${x.name}`))
    for (const k of ws) if (!ds.has(k)) say(`${what} ${k.replace('|', ' ')} is derived from the data but absent from the database`)
    for (const k of ds) if (!ws.has(k)) say(`${what} ${k.replace('|', ' ')} is in the database but the data does not derive it`)
  }
  setCheck(db_.seas, want.seas, 'sea')
  setCheck(db_.regions, want.regions, 'region')
  setCheck(db_.nations, want.nations, 'nation')

  // 0215: THE SEA CONDITIONS — public.sea_zones, public.sea_zone_boxes and public.title_names EQUAL
  // data/sea-zones.json, both directions (requirement order = the array's; a box's bounds; a sea's one rest box)
  if (want.seaZones && db_.seaZones) {
    const SZ = 'data/sea-zones.json'
    const nz = (v) => (v === null || v === undefined ? 'null' : String(v))
    const wantZones = want.seaZones.zones.map((z, i) => ({ code: z.code, name: z.name, title_min: z.title, wave_min: z.wave, ord: i + 1 }))
    const wantBoxes = want.seaZones.zones.flatMap((z) => z.boxes.map((b) => ({
      key: `${b.sea}/${b.ord}`, zone: z.code, sea: b.sea, ord: b.ord,
      lat_min: nz(b.lat_min), lat_max: nz(b.lat_max), lon_min: nz(b.lon_min), lon_max: nz(b.lon_max) })))
    const dbBoxes = db_.seaZones.boxes.map((b) => ({ ...b, key: `${b.sea}/${b.ord}`,
      lat_min: nz(b.lat_min), lat_max: nz(b.lat_max), lon_min: nz(b.lon_min), lon_max: nz(b.lon_max) }))
    const eq = (what, dbRows, wantRows, key, cols) => {
      const d = new Map(dbRows.map((r) => [key(r), r]))
      const w = new Map(wantRows.map((r) => [key(r), r]))
      for (const [k, r] of w) {
        const x = d.get(k)
        if (!x) { say(`${what} ${k} is in ${SZ} but absent from the database`); continue }
        for (const c of cols) if (String(x[c]) !== String(r[c])) say(`${what} ${k}.${c}: database has ${x[c]}, ${SZ} says ${r[c]}`)
      }
      for (const k of d.keys()) if (!w.has(k)) say(`${what} ${k} is in the database but not in ${SZ}`)
    }
    eq('sea zone', db_.seaZones.zones, wantZones, (r) => r.code, ['name', 'title_min', 'wave_min', 'ord'])
    eq('sea zone box', dbBoxes, wantBoxes, (r) => r.key, ['zone', 'lat_min', 'lat_max', 'lon_min', 'lon_max'])
    eq('title', db_.seaZones.titles, want.seaZones.titles, (r) => String(r.level), ['name'])
    // every raster sea has exactly ONE rest box (no bounds), so every water cell answers one zone
    for (const s of want.seas) {
      const rests = wantBoxes.filter((b) => b.sea === s.code && [b.lat_min, b.lat_max, b.lon_min, b.lon_max].every((v) => v === 'null'))
      if (rests.length !== 1) say(`sea ${s.code} has ${rests.length} rest boxes in ${SZ}; every sea has exactly one`)
    }
  }
  // 0215: every ship class's wave resistance IS the one derivation (world-derive.mjs waveResistance), the live three too
  if (db_.waveA && db_.waveA.classWaves) {
    for (const c of db_.waveA.classWaves) {
      const w = waveResistance(c.size, c.rig, c.role)
      if (Number(c.wave) !== w) say(`ship class ${c.code}.wave: database has ${c.wave}, the rule (12 × ${c.size} + ${c.rig} + ${c.role}) gives ${w}`)
    }
  }
  // 0130: a nation's flag and capital are derived too (world-derive.mjs NATIONS / CAPITALS)
  for (const n of want.nations) {
    const d = db_.nations.find((x) => x.code === n.code)
    if (!d) continue
    if (d.flag_char !== n.flag_char) say(`nation ${n.code}.flag_char: database has ${d.flag_char}, data says ${n.flag_char}`)
    if ((d.capital_port_code ?? null) !== (n.capital_port_code ?? null)) {
      say(`nation ${n.code}.capital: database has ${d.capital_port_code}, data says ${n.capital_port_code}`)
    }
  }

  // great powers (0187, GP1) — world-derive.mjs GREAT_POWERS, both directions
  {
    const dbGreat = new Set(db_.great)
    for (const c of want.great) if (!dbGreat.has(c)) say(`great power ${c} is in world-derive.mjs GREAT_POWERS but not in public.great_powers`)
    for (const c of dbGreat) if (!want.great.includes(c)) say(`great power ${c} is in public.great_powers but not in world-derive.mjs GREAT_POWERS`)
    // GP1: the home cities are the great powers' — four each, and nobody else's
    for (const c of want.great) if ((want.homes[c] ?? []).length !== 4) say(`home cities: great power ${c} has ${(want.homes[c] ?? []).length} in data/home-ports.json, the rule is 4`)
    for (const c of Object.keys(want.homes)) if (!want.great.includes(c)) say(`home cities: ${c} has homes in data/home-ports.json but is not a great power`)
  }

  // home cities (0143) — data/home-ports.json, both directions; each flies its own country
  {
    const dbHome = new Map(db_.homes.map((h) => [h.port, h.nation]))
    const wantHome = new Map()
    for (const [nation, ports] of Object.entries(want.homes)) {
      if (ports.length < 3 || ports.length > 4) say(`home cities: ${nation} has ${ports.length} in data/home-ports.json, the rule is 3 or 4`)
      for (const port of ports) {
        if (wantHome.has(port)) say(`home city ${port} is home to both ${wantHome.get(port)} and ${nation} in data/home-ports.json`)
        wantHome.set(port, nation)
      }
    }
    for (const [port, nation] of wantHome) {
      if (!dbHome.has(port)) say(`home city ${port} (${nation}) is in data/home-ports.json but public.port_allegiance does not mark it home`)
      else if (dbHome.get(port) !== nation) say(`home city ${port}: data says ${nation}, public.port_allegiance flies ${dbHome.get(port)}`)
    }
    for (const [port, nation] of dbHome) if (!wantHome.has(port)) say(`home city ${port} (${nation}) is marked home in public.port_allegiance but not in data/home-ports.json`)
  }

  // ship lines and class profiles (0130) — data/ship-lines.json, every column, both directions
  const norm = (v) => JSON.stringify(v, (_k, x) => (x && typeof x === 'object' && !Array.isArray(x)
    ? Object.fromEntries(Object.keys(x).sort().map((k) => [k, x[k]])) : x))
  const wLines = new Map(want.shipLines.map((l) => [l.code, l]))
  for (const l of db_.shipLines) if (!wLines.has(l.code)) say(`ship line ${l.code} is in the database but not in data/ship-lines.json`)
  for (const l of want.shipLines) {
    const d = db_.shipLines.find((x) => x.code === l.code)
    if (!d) { say(`ship line ${l.code} (${l.name}) is in data/ship-lines.json but not in public.ship_lines`); continue }
    const pairs = [
      ['name', d.name, l.name], ['home_nation', d.home_nation, l.homeNation],
      ['builder_nations', norm(d.builder_nations), norm(l.builderNations)],
      ['arsenal_port', d.arsenal_port ?? null, l.arsenalPort ?? null], ['philosophy', d.philosophy, l.philosophy],
      ['modifiers', norm(d.modifiers), norm({ mult: l.mult, add: l.add })], ['traits', norm(d.traits), norm(l.traits)],
    ]
    for (const [col, got, wanted] of pairs) {
      if (String(got) !== String(wanted)) say(`ship line ${l.code}.${col}: database has ${got}, data says ${wanted}`)
    }
  }
  const wProf = new Map(want.classProfiles.map((c) => [c.class, c]))
  for (const c of db_.classProfiles) if (!wProf.has(c.class_code)) say(`class profile ${c.class_code} is in the database but not in data/ship-lines.json`)
  for (const c of want.classProfiles) {
    const d = db_.classProfiles.find((x) => x.class_code === c.class)
    if (!d) { say(`class profile ${c.class} is in data/ship-lines.json but not in public.class_profile`); continue }
    const pairs = [
      ['line', d.line_code, c.line], ['size', Number(d.size), c.size], ['role', d.role, c.role],
      ['tech', d.tech, c.tech], ['deck', Number(d.deck), c.deck], ['any_yard', Boolean(d.any_yard), c.anyYard === true],
    ]
    for (const [col, got, wanted] of pairs) {
      if (String(got) !== String(wanted)) say(`class profile ${c.class}.${col}: database has ${got}, data says ${wanted}`)
    }
  }

  // skills (0131) — data/skills.json: the groups, and every skill's name / group / rank / enrolment /
  // line / prerequisites, both directions; the new skills' blurb, and NONE / 0 (the live four keep
  // their 0016 rows, so only their name and profile are held to the file)
  setCheck(db_.skillGroups, want.skillGroups, 'skill group')
  for (const [i, g] of want.skillGroups.entries()) {
    const d = db_.skillGroups.find((x) => x.code === g.code)
    if (d && Number(d.ord) !== i + 1) say(`skill group ${g.code}.ord: database has ${d.ord}, data says ${i + 1}`)
  }
  const wSkills = new Map(want.skills.map((s) => [s.code, s]))
  for (const s of db_.skills) if (!wSkills.has(s.code)) say(`skill ${s.code} is in the database but not in data/skills.json`)
  const prereqKey = (rows) => rows.map((p) => `${p.skill}:${p.level}:${p.choice}`).sort().join(',')
  for (const s of want.skills) {
    const d = db_.skills.find((x) => x.code === s.code)
    if (!d) { say(`skill ${s.code} (${s.name}) is in data/skills.json but not in public.skills`); continue }
    const pairs = [
      ['name', d.name, s.name], ['group', d.group_code, s.group], ['rank', Number(d.rank), s.rank],
      ['enrol', d.enrol_where, s.enrol], ['line', d.line_code ?? null, s.line ?? null],
      ['prereqs', prereqKey(db_.skillPrereqs.filter((p) => p.code === s.code)), prereqKey(s.prereqs)],
    ]
    if (!s.live) pairs.push(['blurb', d.blurb, s.blurb], ['effect', d.effect, 'NONE'], ['pct_per_level', Number(d.pct_per_level), 0])
    for (const [col, got, wanted] of pairs) {
      if (String(got) !== String(wanted)) say(`skill ${s.code}.${col}: database has ${got}, data says ${wanted}`)
    }
  }

  // gear (0132) — data/gear.json: the racks, every item's profile, every hull's rack places and the
  // level unlocks, every column, both directions (a zero in the file is simply no class_slots row)
  const keyed = (rows, key) => new Map(rows.map((r) => [key(r), r]))
  const both = (dbMap, wantMap, what, cols, file = 'data/gear.json') => {
    for (const k of dbMap.keys()) if (!wantMap.has(k)) say(`${what} ${k} is in the database but not in ${file}`)
    for (const [k, w] of wantMap) {
      const d = dbMap.get(k)
      if (!d) { say(`${what} ${k} is in ${file} but not in the database`); continue }
      for (const [col, dcol, wcol] of cols) {
        if (String(d[dcol]) !== String(w[wcol])) say(`${what} ${k}.${col}: database has ${d[dcol]}, data says ${w[wcol]}`)
      }
    }
  }
  both(keyed(db_.gearRacks, (r) => r.code), keyed(want.gear.racks, (r) => r.code), 'gear rack',
    [['word', 'word', 'word'], ['ord', 'ord', 'ord']])
  both(keyed(db_.itemProfiles, (r) => r.item_code), keyed(want.gear.items, (r) => r.code), 'item profile',
    [['base_type', 'base_type', 'baseType'], ['rack', 'rack', 'rack'], ['grade', 'grade', 'grade'], ['meta', 'meta', 'meta'],
      ['deck', 'deck', 'deck'], ['hands', 'hands', 'hands'], ['active', 'active', 'active']])
  const wantSlots = want.gear.classes.flatMap((c) => want.gear.racks
    .filter((r) => Number(c[r.code] ?? 0) > 0)
    .map((r) => ({ class_code: c.class, slot: r.code, count: Number(c[r.code]) })))
  both(keyed(db_.rackSlots, (r) => `${r.class_code}/${r.slot}`), keyed(wantSlots, (r) => `${r.class_code}/${r.slot}`), 'rack places',
    [['count', 'count', 'count']])
  both(keyed(db_.slotUnlocks, (r) => `${r.class_code}/${r.slot}@${r.min_level}`),
    keyed(want.gear.unlocks, (u) => `${u.class}/${u.rack}@${u.minLevel}`), 'rack unlock', [['count', 'count', 'count']])

  // skill effects and requirements (0133) — data/skills.json `effects` + the hull skills' line traits
  // (data/ship-lines.json), and `requirements`, both directions, every per cent and level
  both(keyed(db_.skillEffects, effectKey), keyed(want.skillEffects, effectKey), 'skill effect', [['pct', 'pct', 'pct']],
    'data/skills.json + data/ship-lines.json')
  both(keyed(db_.skillRequirements, (r) => `${r.kind}/${r.code}/${r.skill}`),
    keyed(want.skillRequirements, (r) => `${r.kind}/${r.code}/${r.skill}`), 'skill requirement', [['level', 'level', 'level']], 'data/skills.json')
  // wave A (0135) — the live rows' data files plus the generators' output, every column, both directions
  if (want.waveA) {
    const w = want.waveA
    const SHIP = 'data/hulls.json + data/ships.generated.json'
    const GEAR = 'data/fittings.json + data/gear.generated.json'
    // the live three are held row-for-row by 0135's own hash (their stats live in no data file); here
    // they must simply BE there, and every other class must be a generated one, column for column
    for (const code of w.liveClasses) if (!db_.waveA.classes.some((r) => r.code === code)) say(`ship class ${code} (live) is missing from the database`)
    both(keyed(db_.waveA.classes.filter((r) => !w.liveClasses.includes(r.code)), (r) => r.code), keyed(w.classes, (r) => r.code),
      'ship class', w.classCols.map((c) => [c, c, c]), SHIP)
    both(keyed(db_.waveA.cabins, (r) => r.class_code), keyed(w.cabins, (r) => r.class_code), 'cabins', [['cabins', 'cabins', 'cabins']],
      'data/ship_stats.json + data/ships.generated.json')
    both(keyed(db_.waveA.recipes, (r) => r.class_code), keyed(w.recipes, (r) => r.class_code), 'hull recipe',
      [['yard_tier', 'yard_tier', 'yard_tier'], ['ducats', 'ducats', 'ducats'], ['note', 'note', 'note']], SHIP)
    both(keyed(db_.waveA.recipeGoods, (r) => `${r.class_code}/${r.good}`), keyed(w.recipeGoods, (r) => `${r.class_code}/${r.good}`),
      'hull material', [['qty', 'qty', 'qty']], SHIP)
    both(keyed(db_.waveA.recipeItems, (r) => `${r.class_code}/${r.item}`), keyed(w.recipeItems, (r) => `${r.class_code}/${r.item}`),
      'hull fitting', [['qty', 'qty', 'qty']], SHIP)
    both(keyed(db_.waveA.items, (r) => r.code), keyed(w.items, (r) => r.code), 'item',
      [['name', 'name', 'name'], ['slot', 'slot', 'slot'], ['buys', 'buys', 'buys'], ['spends', 'spends', 'spends'],
        ['note', 'note', 'note'], ['volume', 'volume', 'volume'], ['ws_tier', 'ws_tier', 'ws_tier']], GEAR)
    both(keyed(db_.waveA.effects, (r) => `${r.item}/${r.stat}`), keyed(w.effects, (r) => `${r.item}/${r.stat}`), 'item effect',
      [['delta', 'delta', 'delta']], GEAR)
    both(keyed(db_.waveA.itemRecipes, (r) => `${r.item}/${r.good}`), keyed(w.itemRecipes, (r) => `${r.item}/${r.good}`), 'item recipe',
      [['qty', 'qty', 'qty']], GEAR)
  }

  // item use (0158) — the generator's `use`, every item, both directions (trigger and what it consumes)
  if (want.itemUse) {
    both(keyed(db_.itemUse, (r) => r.code), keyed(want.itemUse, (r) => r.code), 'item use',
      [['trigger', 'trigger', 'trigger'], ['consumes', 'consumes', 'consumes']], 'data/gear.generated.json (use) + data/captains.json (promotion items)')
  }

  // named items (0159) — each Named item's one city, both directions
  if (want.itemCity) {
    both(keyed(db_.itemCity, (r) => r.code), keyed(want.itemCity, (r) => r.code), 'named item city',
      [['city', 'city', 'city']], 'data/gear.generated.json (Named)')
  }

  // items made nowhere (0184) — every item the gear generator writes `made: false`, both directions
  if (want.itemUnmade) {
    both(keyed(db_.itemUnmade, (r) => r.code), keyed(want.itemUnmade, (r) => r.code), 'item made nowhere', [],
      'data/gear.generated.json (made: false)')
  }

  // merchants of every flag (0167) — the line hull a merchant sails in place of each live class, both directions
  if (want.npcLineHulls) {
    both(keyed(db_.npcLineHulls, (r) => `${r.live}/${r.line}`), keyed(want.npcLineHulls, (r) => `${r.live}/${r.line}`),
      'merchant line hull', [['class', 'class', 'class']], 'data/ships.generated.json (merchant)')
  }

  // perks, sets and Country lines (0163)
  if (want.perks) {
    both(keyed(db_.perks, (r) => r.code), keyed(want.perks, (r) => r.code), 'perk',
      [['word', 'word', 'word'], ['racks', 'racks', 'racks'], ['slot', 'slot', 'slot'], ['base', 'base', 'base'], ['mode', 'mode', 'mode'],
        ['stat', 'stat', 'stat'], ['per_rank', 'per_rank', 'perRank'], ['kit', 'kit', 'kit'], ['ord', 'ord', 'ord']])
    both(keyed(db_.setBonuses, (r) => `${r.line}/${r.pieces}/${r.stat}`), keyed(want.setBonuses, (r) => `${r.line}/${r.pieces}/${r.stat}`),
      'set bonus', [['pct', 'pct', 'pct'], ['flat', 'flat', 'flat']])
    both(keyed(db_.setNames, (r) => r.line), keyed(want.setNames, (r) => r.line), 'set name', [['name', 'name', 'name']])
    both(keyed(db_.itemLine, (r) => r.code), keyed(want.itemLine, (r) => r.code), 'country item line', [['line', 'line', 'line']],
      'data/gear.generated.json (Country)')
  }

  for (const s of db_.skills) {
    if (s.effect === 'NONE') continue
    const mirror = db_.skillEffects.filter((e) => e.skill === s.code && e.scope === 'company')
    if (mirror.length !== 1 || mirror[0].stat !== s.effect || Number(mirror[0].pct) !== Number(s.pct_per_level)) {
      say(`skill ${s.code}: its company effect row does not mirror skills.effect ${s.effect} / ${s.pct_per_level}`)
    }
  }

  // captains (0156) — data/officers.json, data/captains.json and the generator's cards, both directions
  if (want.captains) {
    const c = want.captains
    const PEOPLE = 'data/officers.json'
    const CAT = 'data/captains.json'
    const GEN = 'data/captains.generated.json'
    const same = (k) => [k, k, k]
    both(keyed(db_.captains.officers, (r) => r.code), keyed(c.people, (r) => r.code), 'captain',
      ['name', 'specialty', 'bonus_pct', 'wage', 'nation', 'home', 'blurb'].map(same), PEOPLE)
    both(keyed(db_.captains.foci, (r) => r.code), keyed(c.cat.foci.map((x, i) => ({ ...x, ord: i + 1 })), (r) => r.code), 'trait focus',
      ['word', 'ord'].map(same), CAT)
    both(keyed(db_.captains.grades, (r) => r.code), keyed(c.cat.grades, (r) => r.code), 'captain grade',
      ['ord', 'slots', 'known', 'floor_pct', 'promote_level', 'promote_items'].map(same), CAT)
    // 0162 (K8): the promotion items, their focus and the points that earn one
    both(keyed(db_.captains.promotion, (r) => r.code), keyed(c.cat.promotion_items, (r) => r.code), 'promotion item',
      ['focus', 'points'].map(same), CAT)
    both(keyed(db_.captains.effects, (r) => r.code), keyed(c.cat.effects.map((e, i) => ({ ...e, ord: i + 1 })), (r) => r.code), 'crew effect',
      ['ord', 'scope', 'live', 'cap_pct', 'words', 'waits', 'reader'].map(same), CAT)
    // 0157 (K5): the cabin kinds and the rotation by hull role
    both(keyed(db_.captains.cabinKinds, (r) => r.code), keyed(c.cat.cabins.kinds.map((k, i) => ({ ...k, ord: i + 1 })), (r) => r.code),
      'cabin kind', ['word', 'ord'].map(same), CAT)
    both(keyed(db_.captains.rotation, (r) => `${r.role}#${r.ord}`),
      keyed(Object.entries(c.cat.cabins.rotation).flatMap(([role, list]) => list.map((focus, i) => ({ role, ord: i + 1, focus }))),
        (r) => `${r.role}#${r.ord}`), 'cabin rotation', [same('focus')], CAT)
    both(keyed(db_.captains.traits, (r) => r.code),
      keyed(c.cat.traits.map((t) => ({ ...t, goods: t.goods ?? null, goods_word: t.goods_word ?? null })), (r) => r.code), 'trait',
      ['ord', 'word', 'focus', 'goods', 'goods_word'].map(same), CAT)
    both(keyed(db_.captains.traitEffects, (r) => `${r.trait}/${r.effect}`),
      keyed(c.cat.traits.flatMap((t) => t.effects.map((e, i) => ({ trait: t.code, effect: e.effect, ord: i + 1, mult: e.mult }))),
        (r) => `${r.trait}/${r.effect}`), 'trait effect', ['ord', 'mult'].map(same), CAT)
    both(keyed(db_.captains.languages, (r) => r.code), keyed(c.cat.languages, (r) => r.code), 'language', ['ord', 'name'].map(same), CAT)
    both(keyed(db_.captains.portLanguage, (r) => r.port), keyed(c.gen.harbours, (r) => r.port), 'harbour language', [same('language')], GEN)
    both(keyed(db_.captains.profile, (r) => r.code), keyed(c.gen.captains, (r) => r.code), 'captain card', ['grade', 'job'].map(same), GEN)
    both(keyed(db_.captains.kit, (r) => `${r.code}#${r.ord}`),
      keyed(c.gen.captains.flatMap((x) => x.kit.map((k, i) => ({ code: x.code, ord: i + 1, trait: k.trait, pct: k.pct }))), (r) => `${r.code}#${r.ord}`),
      'captain trait', ['trait', 'pct'].map(same), GEN)
    both(keyed(db_.captains.speaks, (r) => `${r.code}#${r.ord}`),
      keyed(c.gen.captains.flatMap((x) => x.languages.map((l, i) => ({ code: x.code, ord: i + 1, language: l }))), (r) => `${r.code}#${r.ord}`),
      'captain language', [same('language')], GEN)
  }

  // market coverage
  const expected = want.ports.length * want.goods.length
  if (Number(db_.marketRows) !== expected) {
    say(`port_goods holds ${db_.marketRows} rows; ${want.ports.length} harbours × ${want.goods.length} goods = ${expected} — the market does not cover the world`)
  }

  return out
}

/**
 * The standing check. Reads the applied world from `db` (a live PGlite/PG connection), derives
 * the wanted world from data/*.json, and THROWS with every difference if they are not equal.
 * apply-chain.mjs calls this after the last migration, so every local and CI apply is gated.
 */
export async function assertWorldMatchesData(db, { log = console.log } = {}) {
  const hasKind = (await db.query(
    `select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'ports' and column_name = 'kind'`,
  )).rows.length > 0
  if (!hasKind) throw new Error('world-guard: ports.kind is missing — the chain no longer reaches 0036, so this guard cannot tell harbours from sea places')

  const db_ = {}
  db_.ports = (await db.query(`
    select p.code, p.name, p.country, n.code as nation_code, p.lat::float8 lat, p.lon::float8 lon,
           s.code as sea_code, r.code as region_code, p.culture, p.size_tier, p.max_draft,
           p.has_yard, p.yard_tier, p.has_academy, p.dev_industry, p.dev_commerce, p.dev_military
      from public.ports p
      join public.seas s on s.id = p.sea_id
      join public.regions r on r.id = p.region_id
      left join public.nations n on n.id = p.nation_id
     where p.kind = 'HARBOUR' order by p.code`)).rows
  db_.places = (await db.query(`
    select p.code, p.name, p.lat::float8 lat, p.lon::float8 lon
      from public.ports p where p.kind = 'SEA_PLACE' order by p.code`)).rows
  db_.goods = (await db.query(`
    select code, name, base_value::float8 base_value, bulk::float8 bulk,
           perishable_pct_day::float8 perishable_pct_day, category, culture_mask,
           origin_regions, entrepot_ports
      from public.goods order by code`)).rows
  // 0208: the scales the database applies to the data when it writes the rows (world_config
  // hold_scale, goods_price_level; 0220: speed_scale). A chain before 0208 has no such knob and its rows
  // ARE the data's, so their absence reads 1 — the right answer there, not a fallback.
  db_.scales = (await db.query(`
    select coalesce((select (value #>> '{}')::float8 from public.world_config where key = 'hold_scale'), 1) as hold,
           coalesce((select (value #>> '{}')::float8 from public.world_config where key = 'goods_price_level'), 1) as price,
           coalesce((select (value #>> '{}')::float8 from public.world_config where key = 'speed_scale'), 1) as speed`)).rows[0]
  db_.spec = (await db.query(`
    select p.code as port, g.code as good from public.port_specialties s
      join public.ports p on p.id = s.port_id join public.goods g on g.id = s.good_id`)).rows
  db_.seas = (await db.query(`select code, name from public.seas`)).rows
  // 0215: the sea conditions — every zone, its boxes and the title names (data/sea-zones.json)
  db_.seaZones = {
    zones: (await db.query(`select code, name, title_min, wave_min, ord from public.sea_zones`)).rows,
    boxes: (await db.query(`
      select b.zone_code as zone, s.code as sea, b.ord, b.lat_min::float8 as lat_min, b.lat_max::float8 as lat_max,
             b.lon_min::float8 as lon_min, b.lon_max::float8 as lon_max
        from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id`)).rows,
    titles: (await db.query(`select level, name from public.title_names`)).rows,
  }
  db_.regions = (await db.query(`select code, name from public.regions`)).rows
  db_.nations = (await db.query(`select code, name, flag_char, capital_port_code from public.nations`)).rows
  // 0130: the eleven lines and every hull's profile (numeric jsonb values read back as numbers)
  db_.shipLines = (await db.query(`
    select code, name, home_nation, builder_nations, arsenal_port, philosophy, modifiers, traits
      from public.ship_lines order by code`)).rows
  db_.classProfiles = (await db.query(`
    select class_code, line_code, size, role, tech, deck, any_yard from public.class_profile order by class_code`)).rows
  // 0131: the skill catalogue, its groups and prerequisites
  db_.skillGroups = (await db.query(`select code, name, ord from public.skill_groups order by ord`)).rows
  db_.skills = (await db.query(`
    select s.code, s.name, s.effect, s.pct_per_level::float8 as pct_per_level, s.blurb,
           pr.group_code, pr.rank, pr.enrol_where, pr.line_code
      from public.skills s left join public.skill_profile pr on pr.skill_id = s.id order by s.code`)).rows
  db_.skillPrereqs = (await db.query(`
    select s.code, n.code as skill, q.level, q.choice from public.skill_prereqs q
      join public.skills s on s.id = q.skill_id join public.skills n on n.id = q.needs_skill_id`)).rows
  // 0143: the home cities
  const hasAllegiance = (await db.query(`select to_regclass('public.port_allegiance') is not null as ok`)).rows[0].ok
  if (!hasAllegiance) throw new Error('world-guard: public.port_allegiance is missing — the chain no longer reaches 0143, so the home cities cannot be checked')
  // 0187 (GP1): the great powers
  const hasGreat = (await db.query(`select to_regclass('public.great_powers') is not null as ok`)).rows[0].ok
  if (!hasGreat) throw new Error('world-guard: public.great_powers is missing — the chain no longer reaches 0187, so the great powers cannot be checked')
  db_.great = (await db.query(`select n.code from public.great_powers g join public.nations n on n.id = g.nation_id order by n.code`)).rows.map((r) => r.code)
  db_.homes = (await db.query(`
    select p.code as port, n.code as nation from public.port_allegiance a
      join public.ports p on p.id = a.port_id left join public.nations n on n.id = a.nation_id
     where a.home order by p.code`)).rows
  db_.marketRows = (await db.query(`select count(*)::int as n from public.port_goods`)).rows[0].n
  // 0132: the gear racks, item profiles, rack places and unlocks
  const hasGear = (await db.query(`select to_regclass('public.item_profile') is not null as ok`)).rows[0].ok
  if (!hasGear) throw new Error('world-guard: public.item_profile is missing — the chain no longer reaches 0132, so the gear cannot be checked')
  db_.gearRacks = (await db.query(`select code, word, ord from public.gear_racks order by ord`)).rows
  db_.itemProfiles = (await db.query(`
    select item_code, base_type, rack, grade, meta, deck, hands, active from public.item_profile order by item_code`)).rows
  db_.rackSlots = (await db.query(`select class_code, slot, count from public.class_slots order by 1, 2`)).rows
  db_.slotUnlocks = (await db.query(`select class_code, slot, count, min_level from public.class_slot_unlocks order by 1, 2, 4`)).rows
  // 0158: what works every item (S13)
  const hasUse = (await db.query(`select to_regclass('public.item_use') is not null as ok`)).rows[0].ok
  if (!hasUse) throw new Error('world-guard: public.item_use is missing — the chain no longer reaches 0158, so what wears the gear cannot be checked')
  db_.itemUse = (await db.query(`
    select item_code as code, coalesce(trigger, 'null') as trigger, consumes::text as consumes from public.item_use order by item_code`)).rows
    .map((r) => ({ ...r, consumes: consumedKey(JSON.parse(r.consumes)) }))
  // 0159: the one city of every Named item (S15)
  const hasCity = (await db.query(`select to_regclass('public.item_city') is not null as ok`)).rows[0].ok
  if (!hasCity) throw new Error('world-guard: public.item_city is missing — the chain no longer reaches 0159, so the Named items cannot be checked')
  db_.itemCity = (await db.query(`
    select ic.item_code as code, p.code as city from public.item_city ic join public.ports p on p.id = ic.port_id order by 1`)).rows
  // 0184: the items no workshop makes (the Famous pieces, until the owner sets how they are won)
  const hasUnmade = (await db.query(`select to_regclass('public.item_unmade') is not null as ok`)).rows[0].ok
  if (!hasUnmade) throw new Error('world-guard: public.item_unmade is missing — the chain no longer reaches 0184, so the items made nowhere cannot be checked')
  db_.itemUnmade = (await db.query(`select item_code as code from public.item_unmade order by 1`)).rows
  // 0167: the line hull a merchant sails in place of each live class (S18)
  const hasLineHulls = (await db.query(`select to_regclass('public.npc_line_hulls') is not null as ok`)).rows[0].ok
  if (!hasLineHulls) throw new Error('world-guard: public.npc_line_hulls is missing — the chain no longer reaches 0167, so the merchants of every flag cannot be checked')
  db_.npcLineHulls = (await db.query(`
    select live_class as live, line_code as line, class_code as class from public.npc_line_hulls order by 1, 2`)).rows
  // 0163: perks, sets and the Country items' lines (S16)
  const hasPerks = (await db.query(`select to_regclass('public.perks') is not null as ok`)).rows[0].ok
  if (!hasPerks) throw new Error('world-guard: public.perks is missing — the chain no longer reaches 0163, so the perks and sets cannot be checked')
  db_.perks = (await db.query(`
    select code, word, array_to_string(racks, ',') as racks, coalesce(slot, 'null') as slot, coalesce(base, 'null') as base, mode,
           coalesce(stat, 'null') as stat, per_rank::float8 as per_rank, coalesce(kit, 'null') as kit, ord from public.perks`)).rows
  db_.setBonuses = (await db.query(`
    select line_code as line, pieces, stat, coalesce(pct::float8::text, 'null') as pct, coalesce(flat::float8::text, 'null') as flat from public.gear_set_bonuses`)).rows
  db_.setNames = (await db.query(`select line_code as line, set_name as name from public.gear_set_names`)).rows
  db_.itemLine = (await db.query(`select item_code as code, line_code as line from public.item_line`)).rows
  // 0133: the skill effects and requirements
  const hasEffects = (await db.query(`select to_regclass('public.skill_effects') is not null as ok`)).rows[0].ok
  if (!hasEffects) throw new Error('world-guard: public.skill_effects is missing — the chain no longer reaches 0133, so the skill effects cannot be checked')
  db_.skillEffects = (await db.query(`
    select skill_code as skill, scope, stat, pct_per_level::float8 as pct, line_code as line, size, role, tech
      from public.skill_effects`)).rows
  db_.skillRequirements = (await db.query(`
    select subject_kind as kind, subject_code as code, skill_code as skill, level from public.skill_requirements`)).rows
  // 0135: wave A — every hull class, its cabins and recipe, and every item, its effects and recipe
  db_.waveA = {
    classes: (await db.query(`
      select code, name, family, rig, hold, crew_required, crew_max, speed_kn::float8 as speed_kn, durability, guns, draft,
             build_hours::float8 as build_hours, build_cost::float8 as build_cost, tier, handling, armour, attack, accuracy,
             reach, sighting::float8 as sighting, wave
        from public.ship_classes`)).rows,
    // 0215: every class's wave beside its profile, for the one-rule check (the live three included)
    classWaves: (await db.query(`
      select c.code, c.rig, c.wave, cp.size, cp.role from public.ship_classes c join public.class_profile cp on cp.class_code = c.code`)).rows,
    cabins: (await db.query(`select class_code, cabins from public.class_cabins`)).rows,
    recipes: (await db.query(`select class_code, yard_tier, ducats::float8 as ducats, note from public.hull_recipes`)).rows,
    recipeGoods: (await db.query(`
      select hg.class_code, g.code as good, hg.qty::float8 as qty from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id`)).rows,
    recipeItems: (await db.query(`select class_code, item_code as item, qty from public.hull_recipe_items`)).rows,
    items: (await db.query(`select code, name, slot, buys, spends, note, volume::float8 as volume, ws_tier from public.item_kinds`)).rows,
    effects: (await db.query(`select item_code as item, stat, delta::float8 as delta from public.item_effects`)).rows,
    itemRecipes: (await db.query(`
      select ir.item_code as item, g.code as good, ir.qty::float8 as qty from public.item_recipes ir join public.goods g on g.id = ir.good_id`)).rows,
  }

  // 0156: the captains — the people, the catalogue, and every generated card
  const hasCaptains = (await db.query(`select to_regclass('public.captain_profile') is not null as ok`)).rows[0].ok
  if (!hasCaptains) throw new Error('world-guard: public.captain_profile is missing — the chain no longer reaches 0156, so the captains cannot be checked')
  db_.captains = {
    officers: (await db.query(`
      select o.code, o.name, j.job as specialty, j.job_pct::float8 as bonus_pct, o.wage_ducats::int as wage, n.code as nation, p.code as home, o.blurb
        from public.officers o
        -- 0166 (K9): her job and its value are her first trait's (public.captain_job); officers.specialty / bonus_pct are gone
        left join public.captain_job j on j.officer_id = o.id
        left join public.nations n on n.id = o.nation_id left join public.ports p on p.id = o.home_port_id`)).rows,
    foci: (await db.query(`select code, word, ord from public.trait_foci`)).rows,
    grades: (await db.query(`select code, ord, slots, known, floor_pct::float8 as floor_pct, promote_level, promote_items from public.captain_grades`)).rows,
    promotion: (await db.query(`select item_code as code, focus, points::float8 as points from public.promotion_items`)).rows,
    effects: (await db.query(`select code, ord, scope, live, cap_pct::float8 as cap_pct, words, waits, reader from public.crew_effects`)).rows,
    cabinKinds: (await db.query(`select code, word, ord from public.cabin_kinds`)).rows,
    rotation: (await db.query(`select role, ord, focus from public.cabin_rotation`)).rows,
    traits: (await db.query(`select code, ord, word, focus, goods, goods_word from public.traits`)).rows,
    traitEffects: (await db.query(`select trait, effect, ord, mult::float8 as mult from public.trait_effects`)).rows,
    languages: (await db.query(`select code, ord, name from public.languages`)).rows,
    portLanguage: (await db.query(`select p.code as port, pl.language from public.port_language pl join public.ports p on p.id = pl.port_id`)).rows,
    profile: (await db.query(`select o.code, cp.grade, cp.job_trait as job from public.captain_profile cp join public.officers o on o.id = cp.officer_id`)).rows,
    kit: (await db.query(`select o.code, ct.ord, ct.trait, ct.base_pct::float8 as pct from public.captain_traits ct join public.officers o on o.id = ct.officer_id`)).rows,
    speaks: (await db.query(`select o.code, cl.ord, cl.language from public.captain_languages cl join public.officers o on o.id = cl.officer_id`)).rows,
  }

  const want = deriveWorld()
  want.places = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'sea-places.json'), 'utf8')).places
  {
    const lines = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'ship-lines.json'), 'utf8'))
    want.shipLines = lines.lines
    want.classProfiles = lines.profiles
  }
  {
    const skills = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'skills.json'), 'utf8'))
    want.skillGroups = skills.groups
    want.skills = skills.skills
    want.skillEffects = wantedSkillEffects(skills.skills, want.shipLines)   // 0133
    want.skillRequirements = skills.requirements                            // 0133
  }
  want.gear = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'gear.json'), 'utf8'))
  want.homes = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'home-ports.json'), 'utf8')).homes   // 0143
  want.seaZones = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'sea-zones.json'), 'utf8'))   // 0215: zones, boxes, titles
  want.great = [...GREAT_POWERS].sort()   // 0187 (GP1)

  // 0135: THE GENERATORS, RE-RUN. Their output must equal the committed files (a stale file is drift)
  // and, with the live rows' data files, the database (below, in `drift`).
  {
    const read = (rel) => JSON.parse(readFileSync(join(REPO_ROOT, rel), 'utf8'))
    const ships = generateShips()
    const gear = generateGear()
    for (const [file, gen] of [[SHIPS_FILE, ships], [GEAR_FILE, gear]]) {
      if (readFileSync(join(REPO_ROOT, file), 'utf8') !== JSON.stringify(gen, null, 1) + '\n') {
        throw new Error(`WORLD DRIFT: ${file} is not what its generator gives today — re-run the generator (a shipped migration is never edited).`)
      }
    }
    want.classProfiles = [...want.classProfiles, ...ships.hulls.map((h) => ({
      class: h.class, line: h.line, size: h.size, role: h.role, tech: h.tech, deck: h.deck, anyYard: h.anyYard }))]
    want.gear = {
      ...want.gear,
      items: [...want.gear.items, ...gear.items.map((i) => ({
        code: i.code, baseType: i.baseType, rack: i.rack, grade: i.grade, meta: i.meta, deck: i.deck, hands: i.hands, active: i.active }))],
      classes: [...want.gear.classes, ...ships.hulls.map((h) => ({ class: h.class, ...h.racks }))],
    }
    // 0163: the perks and sets (data/gear.json) and the Country items' lines (the generator)
    {
      const g = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'gear.json'), 'utf8'))
      const nz = (v) => (v === null || v === undefined ? 'null' : String(v))
      want.perks = g.perks.map((x, i) => ({ code: x.code, word: x.word, racks: x.racks.join(','), slot: nz(x.slot), base: nz(x.base), mode: x.mode,
        stat: nz(x.stat), perRank: x.perRank, kit: nz(x.kit), ord: i + 1 }))
      want.setBonuses = g.sets.flatMap((st) => st.bonuses.map((b) => ({ line: st.line, pieces: b.pieces, stat: b.stat,
        pct: b.pct === undefined ? 'null' : String(b.pct), flat: b.flat === undefined ? 'null' : String(b.flat) })))
      want.setNames = g.sets.map((st) => ({ line: st.line, name: st.name }))
      want.itemLine = gear.items.filter((i) => i.line).map((i) => ({ code: i.code, line: i.line }))
    }
    want.itemCity = gear.items.filter((i) => i.city).map((i) => ({ code: i.code, city: i.city }))   // 0159
    want.itemUnmade = gear.items.filter((i) => i.made === false).map((i) => ({ code: i.code }))   // 0184
    want.npcLineHulls = ships.merchant.map((m) => ({ live: m.live, line: m.line, class: m.class }))   // 0167
    want.itemUse = [
      ...gear.use.map((u) => ({ code: u.code, trigger: u.trigger ?? 'null', consumes: consumedKey(u.consumes) })),   // 0158
      // 0166: the three promotion items (data/captains.json, K8) are spent by cmd.promote_captain and never fitted —
      // so they never wear (trigger null) and spend no good when they act (consumes [])
      ...read('data/captains.json').promotion_items.map((p) => ({ code: p.code, trigger: 'null', consumes: '' })),
    ]
    want.skillRequirements = [
      ...want.skillRequirements,
      ...ships.hulls.flatMap((h) => h.requirements.map((q) => ({ kind: 'hull', code: h.class, skill: q.skill, level: q.level }))),
      ...gear.items.flatMap((i) => i.requirements.map((q) => ({ kind: 'item', code: i.code, skill: q.skill, level: q.level }))),
    ]
    const liveHulls = read('data/hulls.json').hulls
    const fittings = read('data/fittings.json').fittings
    want.waveA = {
      liveClasses: liveHulls.map((h) => h.class),
      classCols: ['name', 'family', 'rig', 'hold', 'crew_required', 'crew_max', 'speed_kn', 'durability', 'guns', 'draft',
        'build_hours', 'build_cost', 'tier', 'handling', 'armour', 'attack', 'accuracy', 'reach', 'sighting', 'wave'],   // 0215: + wave
      classes: ships.hulls.map((h) => ({
        code: h.class, name: h.name, family: h.family, rig: h.rig, hold: h.hold, crew_required: h.crewRequired, crew_max: h.crewMax,
        speed_kn: h.speedKn, durability: h.durability, guns: h.guns, draft: h.draft, build_hours: h.buildHours, build_cost: h.buildCost,
        tier: h.tier, handling: h.handling, armour: h.armour, attack: h.attack, accuracy: h.accuracy, reach: h.reach, sighting: h.sighting,
        wave: h.waveResistance })),   // 0215
      cabins: [...read('data/ship_stats.json').slots.map((s) => ({ class_code: s.class, cabins: s.cabins })),
        ...ships.hulls.map((h) => ({ class_code: h.class, cabins: h.cabins }))],
      recipes: [...liveHulls.map((h) => ({ class_code: h.class, yard_tier: h.yard_tier, ducats: h.ducats, note: h.note })),
        ...ships.hulls.map((h) => ({ class_code: h.class, yard_tier: h.yardTier, ducats: h.ducats, note: h.note }))],
      recipeGoods: [...liveHulls, ...ships.hulls].flatMap((h) =>
        h.goods.map((g) => ({ class_code: h.class, good: g.in, qty: g.qty }))),
      // 0166 (S17): and the generated hulls' fittings — a famous hull's famous gear (no other generated hull has one)
      recipeItems: [...liveHulls, ...ships.hulls].flatMap((h) => h.items.map((i) => ({ class_code: h.class, item: i.in, qty: i.qty }))),
      items: [...fittings.map((f) => ({ code: f.code, name: f.name, slot: f.slot, buys: f.buys, spends: f.spends, note: f.note, volume: f.volume, ws_tier: f.ws_tier })),
        // 0162 (K8): the three promotion items (data/captains.json), kept in the one item system as kind 'promotion'
        ...read('data/captains.json').promotion_items.map((p) => ({ code: p.code, name: p.name, slot: 'promotion', buys: 'a promotion',
          spends: 'nothing', note: p.note, volume: 0.01, ws_tier: 1 })),
        ...gear.items.map((i) => ({ code: i.code, name: i.name, slot: i.slot, buys: i.buys, spends: i.spends, note: i.note, volume: i.volume, ws_tier: i.wsTier }))],
      effects: [...fittings.flatMap((f) => (f.effects ?? []).map((e) => ({ item: f.code, stat: e.stat, delta: e.delta }))),
        ...gear.items.flatMap((i) => i.effects.map((e) => ({ item: i.code, stat: e.stat, delta: e.delta })))],
      itemRecipes: [...fittings, ...gear.items].flatMap((i) => i.recipe.map((x) => ({ item: i.code, good: x.in, qty: x.qty }))),
    }
  }

  // 0156: THE CAPTAINS GENERATOR, RE-RUN — its output must equal the committed file, and (in `drift`) the database
  {
    const gen = generateCaptains()
    if (readFileSync(join(REPO_ROOT, CAPTAINS_FILE), 'utf8') !== JSON.stringify(gen, null, 1) + '\n') {
      throw new Error(`WORLD DRIFT: ${CAPTAINS_FILE} is not what its generator gives today — re-run scripts/build-captains.mjs (a shipped migration is never edited).`)
    }
    const { people, cat } = captainInputs()
    want.captains = { people, cat, gen }
  }

  // 0208: THE DATA × THE TWO SCALES (the owner, 2026-10-19: "enlarge the ships cargo by 3x. reduce the
  // goods price by 5x"). The data files keep the design figures; the database holds them × hold_scale
  // (every hold quantity: a hull's rated hold, an item's hold delta, a flat hold perk or set bonus) and
  // × goods_price_level (a good's base value). 0220 (the owner, 2026-10-20: "ship speed ... about 3 times
  // faster"): × speed_scale, every flat speed quantity the same way (a hull's rated speed_kn, an item's
  // speed delta, a flat speed perk or set bonus). One place applies each scale to the wanted rows, here.
  // The product is rounded to 6 places: the database holds numeric(4,2) / numeric(8,2), and the rows are
  // compared as strings (6.6 × 3 must read 19.8, not 19.799999999999997).
  {
    const k = db_.scales
    const scaleOf = (stat) => (stat === 'hold' ? k.hold : stat === 'speed' ? k.speed : 1)
    const scaled = (x, stat) => Math.round(Number(x) * scaleOf(stat) * 1e6) / 1e6
    want.goods = goodsAtPriceLevel(want.goods, k.price)
    want.waveA = {
      ...want.waveA,
      classes: want.waveA.classes.map((c) => ({ ...c, hold: scaled(c.hold, 'hold'), speed_kn: scaled(c.speed_kn, 'speed') })),
      effects: want.waveA.effects.map((e) => (scaleOf(e.stat) !== 1 ? { ...e, delta: scaled(e.delta, e.stat) } : e)),
    }
    if (want.perks) want.perks = want.perks.map((x) => (scaleOf(x.stat) !== 1 && x.mode === 'flat' ? { ...x, perRank: scaled(x.perRank, x.stat) } : x))
    if (want.setBonuses) want.setBonuses = want.setBonuses.map((b) => (scaleOf(b.stat) !== 1 && b.flat !== 'null' ? { ...b, flat: String(scaled(b.flat, b.stat)) } : b))
  }

  // ── POSITIVE CONTROL: the comparator must SEE a planted drift before it may certify zero ─────
  const wounded = {
    ...want,
    ports: want.ports.slice(1),                                      // one harbour dropped
    goods: want.goods.map((g, i) => (i === 0 ? { ...g, base_value: g.base_value + 500 } : g)), // one value bent
    shipLines: want.shipLines.map((l, i) => (i === 0 ? { ...l, builderNations: [...l.builderNations, 'ENG'] } : l)), // 0130: one line's builders bent
    skills: want.skills.map((s, i) => (i === 0 ? { ...s, rank: s.rank + 1 } : s)), // 0131: one skill's rank bent
    gear: { ...want.gear, items: want.gear.items.map((it, i) => (i === 0 ? { ...it, deck: it.deck + 1 } : it)) }, // 0132: one item's deck bent
    skillEffects: want.skillEffects.map((e, i) => (i === 0 ? { ...e, pct: e.pct + 1 } : e)), // 0133: one skill effect's per cent bent
    perks: want.perks.map((x, i) => (i === 0 ? { ...x, perRank: x.perRank + 1 } : x)), // 0163: one perk's rank bent
    itemCity: want.itemCity.map((c, i) => (i === 0 ? { ...c, city: c.city === 'LIS' ? 'VEN' : 'LIS' } : c)), // 0159: one Named item's city bent
    itemUnmade: want.itemUnmade.slice(1), // 0184: one item made nowhere dropped
    npcLineHulls: want.npcLineHulls.map((m, i) => (i === 0 ? { ...m, class: m.class === 'barca' ? 'nau' : 'barca' } : m)), // 0167: one merchant line hull bent
    itemUse: want.itemUse.map((u, i) => (i === 0 ? { ...u, trigger: u.trigger === 'STORM' ? 'MILES' : 'STORM' } : u)), // 0158: one item's trigger bent
    waveA: { ...want.waveA, classes: want.waveA.classes.map((c, i) => (i === 0 ? { ...c, hold: c.hold + 5 } : c)) }, // 0135: one generated hull's hold bent
    homes: Object.fromEntries(Object.entries(want.homes).map(([n, ps], i) => [n, i === 0 ? ps.slice(1) : ps])), // 0143: one home city dropped
    great: want.great.slice(1), // 0187: one great power dropped
    captains: { ...want.captains, gen: { ...want.captains.gen, captains: want.captains.gen.captains.map((x, i) => (i === 0
      ? { ...x, kit: x.kit.map((k, j) => (j === 1 ? { ...k, pct: k.pct + 1 } : k)) } : x)) } }, // 0156: one captain's second trait bent
  }
  const seen = drift(db_, wounded)
  const sawDrop = seen.some((s) => s.includes(`${want.ports[0].code}`))
  const sawBend = seen.some((s) => s.includes('.base_value:'))
  const sawLine = seen.some((s) => s.includes('.builder_nations:'))
  const sawSkill = seen.some((s) => s.includes(`skill ${want.skills[0].code}.rank:`))
  const sawGear = seen.some((s) => s.includes(`item profile ${want.gear.items[0].code}.deck:`))
  const sawEffect = seen.some((s) => s.includes(`skill effect ${effectKey(want.skillEffects[0])}.pct:`))
  const sawPerk = seen.some((s) => s.includes(`perk ${want.perks[0].code}.per_rank:`))
  const sawCity = seen.some((s) => s.includes(`named item city ${want.itemCity[0].code}.city:`))
  const sawUnmade = want.itemUnmade.length === 0 || seen.some((s) => s.includes(`item made nowhere ${want.itemUnmade[0].code} is in the database`))
  const sawLineHull = seen.some((s) => s.includes(`merchant line hull ${want.npcLineHulls[0].live}/${want.npcLineHulls[0].line}.class:`))
  const sawUse = seen.some((s) => s.includes(`item use ${want.itemUse[0].code}.trigger:`))
  const sawHull = seen.some((s) => s.includes(`ship class ${want.waveA.classes[0].code}.hold:`))
  const droppedHome = Object.values(want.homes)[0][0]
  const sawHome = seen.some((s) => s.includes(`home city ${droppedHome} `))
  const sawGreat = seen.some((s) => s.includes(`great power ${want.great[0]} is in public.great_powers`))
  const sawCaptain = seen.some((s) => s.includes(`captain trait ${want.captains.gen.captains[0].code}#2.pct:`))
  if (!sawDrop || !sawBend || !sawLine || !sawSkill || !sawGear || !sawEffect || !sawUse || !sawCity || !sawUnmade || !sawLineHull || !sawPerk || !sawHull || !sawHome || !sawCaptain || !sawGreat) {
    throw new Error(
      'WORLD GUARD IS BLIND: a deliberately dropped harbour ' +
        `(${want.ports[0].code}), bent good value, bent ship line, bent skill rank, bent item deck, bent skill effect, bent item trigger, bent Named city, dropped item made nowhere, bent merchant line hull, bent perk, bent generated hull, dropped home city, bent captain trait or dropped great power was NOT reported by the comparator ` +
        `(saw ${seen.length} finding(s)). A guard that cannot see a planted drift certifies nothing.`,
    )
  }

  const findings = drift(db_, want)

  // 0173: THE HAUL IS THE DERIVATION — every market row's haul_nm / haul equals world.haul_rows() (the
  // sailing distance from the nearest maker and its multiplier, from the roster, public.sea_reaches and the
  // haul_* knobs). Not data/*.json but derived from it, like affinity — and unlike affinity no migration
  // re-derives it on every apply, so a roster, sea or knob change that forgets to refill it is caught here.
  // Its own positive control: the same comparison with one row's haul bent must see exactly one more.
  const hasHaul = (await db.query(`select to_regprocedure('world.haul_rows()') is not null as ok`)).rows[0].ok
  let haulRows = 0
  if (hasHaul) {
    const h = (await db.query(`
      with h as materialized (select * from world.haul_rows()),
      j as (select pg.haul_nm, pg.haul, h.haul_nm as want_nm, h.haul as want, h.port_id is null as missing,
                   row_number() over (order by pg.port_id, pg.good_id) as rn
              from public.port_goods pg left join h on h.port_id = pg.port_id and h.good_id = pg.good_id)
      select count(*) filter (where missing or haul_nm is distinct from want_nm or haul is distinct from want)::int as bad,
             count(*) filter (where missing or haul_nm is distinct from want_nm
                                 or haul is distinct from (case when rn = 1 then want + 1 else want end))::int as planted,
             count(*)::int as n
        from j`)).rows[0]
    if (h.planted !== h.bad + 1) {
      throw new Error(`WORLD GUARD IS BLIND: a deliberately bent haul was not seen (bad ${h.bad}, with the plant ${h.planted}).`)
    }
    if (h.bad > 0) findings.push(`port_goods: ${h.bad} of ${h.n} market rows' haul_nm / haul differ from world.haul_rows() — re-derive (update public.port_goods from world.haul_rows())`)
    haulRows = h.n
  }

  // 0185: THE FAITHS ARE THE DATA, AND EVERY TASTE IS ITS DERIVATION — world.faiths, world.culture_faith,
  // world.port_faith_override and world.faith_demand EQUAL data/faiths.json and data/faith-demand.json, both
  // directions, every column; and every market row's demand equals world.demand_for (region × faith). Its
  // own positive control: the same comparisons with one taste row bent and one demand bent must see both.
  const hasFaith = (await db.query(`select to_regclass('world.faith_demand') is not null as ok`)).rows[0].ok
  let faithRows = 0
  if (hasFaith) {
    const fdata = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'faiths.json'), 'utf8'))
    const ddata = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'faith-demand.json'), 'utf8')).demand
    const q = async (sql) => (await db.query(sql)).rows
    const sets = [
      ['faith', fdata.faiths.map((x) => `${x.code}|${x.name}`),
        (await q(`select code, name from world.faiths`)).map((x) => `${x.code}|${x.name}`)],
      ['culture faith', fdata.cultures.map((x) => `${x.culture}|${x.faith}|${x.why}`),
        (await q(`select culture, faith, why from world.culture_faith`)).map((x) => `${x.culture}|${x.faith}|${x.why}`)],
      ['port faith', fdata.ports.map((x) => `${x.port}|${x.faith}|${x.why}`),
        (await q(`select p.code, o.faith, o.why from world.port_faith_override o join public.ports p on p.id = o.port_id`))
          .map((x) => `${x.code}|${x.faith}|${x.why}`)],
      ['faith taste', ddata.map((x) => `${x.faith}|${x.good}|${Number(x.multiplier).toFixed(3)}|${x.why}`),
        (await q(`select d.faith, g.code, d.multiplier::text as m, d.why from world.faith_demand d join public.goods g on g.id = d.good_id`))
          .map((x) => `${x.faith}|${x.code}|${Number(x.m).toFixed(3)}|${x.why}`)],
    ]
    const compare = (wantRows, dbRows, what, out) => {
      const w = new Set(wantRows)
      const d = new Set(dbRows)
      for (const k of w) if (!d.has(k)) out.push(`${what} ${k} is in the data but not in the database`)
      for (const k of d) if (!w.has(k)) out.push(`${what} ${k} is in the database but not in the data`)
    }
    const planted = []
    for (const [what, w, d] of sets) compare(w, what === 'faith taste' ? [...d.slice(1), d[0] + 'x'] : d, what, planted)
    const t = (await q(`
      with j as (select pg.demand, world.demand_for(pg.port_id, pg.good_id) as want,
                        row_number() over (order by pg.port_id, pg.good_id) as rn
                   from public.port_goods pg)
      select count(*) filter (where demand is distinct from want)::int as bad,
             count(*) filter (where (case when rn = 1 then demand + 1 else demand end) is distinct from want)::int as planted,
             count(*)::int as n
        from j`))[0]
    if (!planted.some((s) => s.startsWith('faith taste')) || t.planted !== t.bad + 1) {
      throw new Error(`WORLD GUARD IS BLIND: a deliberately bent faith taste or demand was not seen (tastes ${planted.length}, demand bad ${t.bad}, with the plant ${t.planted}).`)
    }
    for (const [what, w, d] of sets) compare(w, d, what, findings)
    if (t.bad > 0) findings.push(`port_goods: ${t.bad} of ${t.n} market rows' demand differ from world.demand_for() — re-derive (update public.port_goods set demand = world.demand_for(port_id, good_id))`)
    faithRows = ddata.length
  }

  // 0195: HOW THE POWERS STAND IS THE DATA — public.power_relations EQUALS data/relations.json, both
  // directions, every column (the pair unordered: sorted by code on both sides). Its own positive control:
  // the same comparison with one stance bent must see it.
  const hasRelations = (await db.query(`select to_regclass('public.power_relations') is not null as ok`)).rows[0].ok
  let relationRows = 0
  if (hasRelations) {
    const rdata = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'relations.json'), 'utf8')).relations
    const key = (a, b, stance, why) => {
      const [x, y] = [a, b].sort()
      return `${x}|${y}|${stance}|${why}`
    }
    const want = rdata.map((x) => key(x.a, x.b, x.stance, x.why))
    const have = (await db.query(`
      select na.code as a, nb.code as b, r.stance, r.why
        from public.power_relations r join public.nations na on na.id = r.a join public.nations nb on nb.id = r.b`))
      .rows.map((x) => key(x.a, x.b, x.stance, x.why))
    const compare = (w, d, out) => {
      const ws = new Set(w)
      const ds = new Set(d)
      if (ws.size !== w.length) out.push('relation: data/relations.json names one pair twice')
      for (const k of ws) if (!ds.has(k)) out.push(`relation ${k} is in data/relations.json but not in public.power_relations`)
      for (const k of ds) if (!ws.has(k)) out.push(`relation ${k} is in public.power_relations but not in data/relations.json`)
    }
    const planted = []
    compare(want, [`${have[0] ?? 'ENG|PRT|ally|'}`.replace(/\|(ally|rival|war)\|/, '|peace|'), ...have.slice(1)], planted)
    if (!planted.some((s) => s.includes('|peace|'))) {
      throw new Error('WORLD GUARD IS BLIND: a deliberately bent power relation was not seen.')
    }
    compare(want, have, findings)
    relationRows = rdata.length
  }

  if (findings.length > 0) {
    const head = findings.slice(0, 40)
    throw new Error(
      [
        'WORLD DRIFT: the applied chain and data/*.json disagree ' +
          `(${findings.length} difference(s)). The world the players get is not the world the data ` +
          'describes. If the data moved, generate a growth migration ' +
          '(scripts/build-world-growth.mjs); a shipped migration is never edited.',
        ...head.map((s) => `  * ${s}`),
        findings.length > head.length ? `  … and ${findings.length - head.length} more` : null,
      ].filter(Boolean).join('\n'),
    )
  }

  log(
    `world-guard ok: the applied world EQUALS data/*.json — ${want.ports.length} harbours, ` +
      `${want.goods.length} goods, ${want.specialtyPairs.length} offers, ` +
      `${want.places.length} sea places, ${db_.marketRows} market rows, ${want.shipLines.length} ship lines, ` +
      `${want.classProfiles.length} class profiles, ${want.skills.length} skills in ${want.skillGroups.length} groups, ` +
      `${want.gear.racks.length} gear racks, ${want.gear.items.length} item profiles, ${db_.rackSlots.length} rack places, ` +
      `${want.skillEffects.length} skill effects, ${want.skillRequirements.length} skill requirements, ${want.itemUse.length} item uses, ${want.itemCity.length} Named items' cities, ${want.itemUnmade.length} items made nowhere, ${want.perks.length} perks, ${want.setNames.length} sets, ${want.itemLine.length} Country items' lines, ` +
      `${want.waveA.liveClasses.length + want.waveA.classes.length} ship classes and ${want.waveA.items.length} items (generators re-run = files = database), ` +
      `${db_.great.length} great powers, ${db_.homes.length} home cities, ${want.captains.people.length} captains with ${db_.captains.kit.length} traits and ` +
      `${db_.captains.speaks.length} languages, ${db_.captains.portLanguage.length} harbour languages (generator re-run = file = database)` +
      (hasHaul ? `, ${haulRows} market rows' hauls = world.haul_rows() (a planted bend seen) ` : ' ') +
      (hasFaith ? `, ${faithRows} faith tastes = data/faith-demand.json and every demand = world.demand_for() (planted bends seen) ` : ' ') +
      (hasRelations ? `, ${relationRows} power relations = data/relations.json (a planted bend seen) ` : ' ') +
      `(positive control: a planted dropped-harbour, bent-good-value, bent ship line, bent skill rank, bent item deck, bent skill effect, bent item trigger, bent Named city, dropped item made nowhere, bent merchant line hull, bent perk, bent generated hull, dropped home city, bent captain trait and dropped great power were all seen)`,
  )
}
