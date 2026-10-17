// ═══════════════════════════════════════════════════════════════════════════════════════════════
// skills.catalogue.spec.ts — the skill catalogue keeps EVE's lessons (docs/SKILLS_AND_CAPTAINS.md
// §3.2-3.3, K1 = migration 0150: D1-D5, and D7 "never"). Reads data/skills.json, data/ships.generated.json
// and the RPC catalogue off disk — the one authority the world guard holds the database to — and asserts
// the RULES, never a count typed from today's world: every count below is derived from the files.
// What the database does with these rows is 0150's self-assert (world.skills, skill_taught_at,
// world.ship_budget, player_skill_bonus), run on every apply.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(process.cwd())
const read = (rel: string) => readFileSync(path.join(ROOT, rel), 'utf8')

interface Prereq { skill: string; level: number; choice: number }
interface Effect { scope: string; stat: string; pct: number; role?: string; tech?: string }
interface SkillRow {
  code: string; name: string; group: string; rank: number; enrol: string; line?: string
  prereqs: Prereq[]; effects?: Effect[]; live?: boolean; blurb?: string
}
const catalogue = JSON.parse(read('data/skills.json')) as { groups: { code: string }[]; skills: SkillRow[] }
const skills = catalogue.skills
const byCode = new Map(skills.map((s) => [s.code, s]))

test('D7: nothing in the catalogue or the RPC registry injects, extracts, remaps or sells skill points', () => {
  const words = /inject|extract|remap|attribute|sp[_ ]?for[_ ]?coin|buy[_ ]?sp/i
  const named = skills.filter((s) => words.test(s.code) || words.test(s.name) || words.test(s.blurb ?? ''))
  expect(named.map((s) => s.code), 'a skill names an injector / extractor / remap').toEqual([])
  const rpc = read('src/lib/rpc/catalog.ts')
  const fns = [...rpc.matchAll(/fn:\s*'([a-z_]+)'/g)].map((m) => m[1])
  expect(fns.length, 'the RPC catalogue was not read').toBeGreaterThan(20)
  expect(fns.filter((f) => words.test(f)), 'an RPC entry point injects / extracts / remaps').toEqual([])
})

test('D2: no class asks a lower class mastered — the hull ladder and the hull requirements ask III, never IV', () => {
  const ladder = skills.flatMap((s) => s.prereqs
    .filter((p) => (/_HEAVY$/.test(s.code) && /_MEDIUM$/.test(p.skill)) || (/_CAPITAL$/.test(s.code) && /_HEAVY$/.test(p.skill)))
    .map((p) => ({ of: s.code, ...p })))
  expect(ladder.length, 'no ladder prerequisites found — the rule reads nothing').toBeGreaterThan(0)
  expect(ladder.filter((p) => p.level !== 3)).toEqual([])
  const ships = JSON.parse(read('data/ships.generated.json')) as { hulls: { class: string; size: number; requirements: { skill: string; level: number }[] }[] }
  const asks = ships.hulls.filter((h) => h.size === 4 || h.size === 5)
    // the rung BELOW the hull's own class: a heavy asks Medium, a capital asks Heavy (its own class skill at I is not a rung)
    .flatMap((h) => h.requirements.filter((r) => (h.size === 4 ? /_MEDIUM$/ : /_HEAVY$/).test(r.skill)).map((r) => ({ hull: h.class, ...r })))
  expect(asks.length, 'no heavy / capital hull requirement found').toBeGreaterThan(0)
  expect(asks.filter((r) => r.level !== 3)).toEqual([])
})

test('D3: every skill is enrolled somewhere a company can reach — general skills anywhere, a line\'s hulls at its yards', () => {
  expect(skills.filter((s) => !['none', 'anywhere', 'line_yard'].includes(s.enrol)).map((s) => `${s.code}:${s.enrol}`)).toEqual([])
  expect(skills.filter((s) => (s.enrol === 'line_yard') !== (s.group === 'HULLS')).map((s) => s.code)).toEqual([])
  expect(skills.filter((s) => (s.enrol === 'none') !== Boolean(s.live)).map((s) => s.code)).toEqual([])
})

test('D4: every T2 specialisation needs one support skill at V and gives two bonuses per level on its T2 hulls', () => {
  const t2 = skills.filter((s) => (s.effects ?? []).some((e) => e.tech === 'T2'))
  expect(t2.length, 'no T2 specialisation found').toBeGreaterThan(0)
  for (const s of t2) {
    const role = (s.effects ?? []).find((e) => e.tech === 'T2')!.role
    const own = (s.effects ?? []).filter((e) => e.scope === 'ship' && e.tech === 'T2' && e.role === role)
    expect(own.length, `${s.code}: two per-level bonuses on its T2 hulls`).toBe(2)
    const support = s.prereqs.filter((p) => p.level === 5 && byCode.get(p.skill)?.group !== 'ROLES')
    expect(support.length, `${s.code}: one support skill at V`).toBe(1)
  }
})

test('D5: every prerequisite and group exists, no skill needs itself, and every effect is a scope its reader knows', () => {
  const groups = new Set(catalogue.groups.map((g) => g.code))
  expect(skills.filter((s) => !groups.has(s.group)).map((s) => s.code)).toEqual([])
  expect(skills.flatMap((s) => s.prereqs.filter((p) => !byCode.has(p.skill) || p.skill === s.code).map((p) => `${s.code}<${p.skill}`))).toEqual([])
  expect(new Set(skills.map((s) => s.code)).size).toBe(skills.length)
  expect(skills.filter((s) => s.code.length > 16).map((s) => s.code), 'public.skills.code holds 16 characters').toEqual([])
  const scopes = new Set(['company', 'ship', 'fitting', 'house'])
  expect(skills.flatMap((s) => (s.effects ?? []).filter((e) => !scopes.has(e.scope)).map((e) => `${s.code}:${e.scope}`))).toEqual([])
  // a company effect off the four live skills is one of the four company stats (player_skill_bonus reads them)
  const company = new Set(['ENDURANCE', 'SPEED', 'TRADE_CAP', 'SPREAD'])
  expect(skills.flatMap((s) => (s.effects ?? []).filter((e) => (e.scope === 'company') !== company.has(e.stat)).map((e) => `${s.code}:${e.stat}`))).toEqual([])
  // every group has a skill
  for (const g of groups) expect(skills.some((s) => s.group === g), `group ${g} is empty`).toBe(true)
})

test('K2: every house effect is a stat its one reader knows, and Shipwright gives yard labour (0154)', () => {
  // the stats public.skill_effects' house CHECK admits (0151, + yard_labour in 0154); each K2 stat has one
  // reader (standing_route_max_for, fleet_wage, crew_hire_cost, captain_wage, yard_labour, storm_hull_lost,
  // day_delay_for) — 0154's self-assert proves what they do
  const house = new Set(['officer_bonus', 'standing_routes', 'crew_wage', 'profit_tax', 'storm_damage', 'calm_delay',
    'captain_wage', 'crew_hire', 'influence', 'captain_xp', 'homesick', 'yard_labour'])
  expect(skills.flatMap((s) => (s.effects ?? []).filter((e) => e.scope === 'house' && !house.has(e.stat)).map((e) => `${s.code}:${e.stat}`))).toEqual([])
  expect((byCode.get('SHIPWRIGHT')?.effects ?? []).filter((e) => e.scope === 'house' && e.stat === 'yard_labour' && e.pct > 0)).toHaveLength(1)
})
