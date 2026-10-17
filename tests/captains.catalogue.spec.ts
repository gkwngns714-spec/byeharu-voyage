// ═══════════════════════════════════════════════════════════════════════════════════════════════
// captains.catalogue.spec.ts — the captains keep the plan's rules (docs/SKILLS_AND_CAPTAINS.md §4, K4
// = migration 0156: D10, D14, D15, O3, O5). Reads data/officers.json, data/captains.json and
// data/captains.generated.json off disk — the one authority the world guard holds the database to —
// and asserts the RULES, never a count typed from today's world: every count is derived from the
// files. What the database serves from these rows (world.captain_card through world.inn / worldInn and
// world.officers / worldOfficers) is 0156's self-assert, run on every apply.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'

const read = (rel: string) => JSON.parse(readFileSync(path.join(process.cwd(), rel), 'utf8'))

interface Person { code: string; specialty: string; bonus_pct: number; wage: number; nation: string | null; home: string; blurb: string }
interface Grade { code: string; ord: number; slots: number; known: number; floor_pct: number }
interface Trait { code: string; word: string; focus: string; goods?: string; effects: { effect: string }[] }
interface Card { code: string; grade: string; job: string; kit: { trait: string; pct: number }[]; languages: string[] }

const people = (read('data/officers.json') as { officers: Person[] }).officers
const cat = read('data/captains.json') as {
  grades: Grade[]; traits: Trait[]; effects: { code: string; live: boolean }[]; languages: { code: string }[]
  kit: { size: number; extra_pct: number }; extra_languages: Record<string, number>
}
const gen = read('data/captains.generated.json') as { captains: Card[]; harbours: { port: string; language: string }[] }
const card = new Map(gen.captains.map((c) => [c.code, c]))
const trait = new Map(cat.traits.map((t) => [t.code, t]))

test('O3: the grade ladder is the owner\'s pattern — slots = rank, traits known = 2 × slots', () => {
  const g = [...cat.grades].sort((a, b) => a.ord - b.ord)
  expect(g.map((x) => x.code)).toEqual(['C', 'B', 'A', 'S'])
  for (const [i, x] of g.entries()) {
    expect(x.slots, `${x.code} slots`).toBe(i + 2)
    expect(x.known, `${x.code} known`).toBe(2 * x.slots)
  }
})

test('D10: every captain is graded by the floors, and her job is her first trait at her value (the mirror)', () => {
  expect(gen.captains.length, 'the generated cards do not cover the roster').toBe(people.length)
  const floors = [...cat.grades].sort((a, b) => a.ord - b.ord)
  for (const p of people) {
    const c = card.get(p.code)!
    expect(c, `${p.code} has no card`).toBeTruthy()
    expect(c.grade, p.code).toBe(floors.filter((g) => p.bonus_pct >= g.floor_pct).pop()!.code)
    expect(c.job, p.code).toBe(p.specialty)
    expect(c.kit[0], p.code).toEqual({ trait: p.specialty, pct: p.bonus_pct })
  }
})

test('D15: ten distinct traits a kit, the rest at the kit\'s share; every job held by a lesser and a greater captain', () => {
  for (const c of gen.captains) {
    expect(c.kit.length, c.code).toBe(cat.kit.size)
    expect(new Set(c.kit.map((k) => k.trait)).size, `${c.code} repeats a trait`).toBe(cat.kit.size)
    const base = c.kit[0].pct
    for (const k of c.kit.slice(1)) expect(k.pct, `${c.code}.${k.trait}`).toBeCloseTo(Math.round(base * cat.kit.extra_pct / 10) / 10, 9)
  }
  for (const t of cat.traits) {
    const mine = gen.captains.filter((c) => c.job === t.code)
    expect(mine.length, `${t.code} is the job of too few`).toBeGreaterThanOrEqual(2)
    expect(mine.some((c) => c.grade === 'C' || c.grade === 'B'), `${t.code}: no C or B captain`).toBe(true)
    expect(mine.some((c) => c.grade === 'A' || c.grade === 'S'), `${t.code}: no A or S captain`).toBe(true)
  }
})

test('O5: one trader for each goods category, and every effect carried by some trait', () => {
  const categories = new Set((read('data/goods.json') as { goods: { category: string }[] }).goods.map((g) => g.category))
  expect(categories.size).toBeGreaterThan(0)
  expect([...categories].filter((c) => !cat.traits.some((t) => t.goods === c))).toEqual([])
  expect(cat.effects.filter((e) => !cat.traits.some((t) => t.effects.some((x) => x.effect === e.code))).map((e) => e.code)).toEqual([])
})

test('DARK: only the four jobs public.fleet_officer_bonus has always read are live', () => {
  const liveTraits = cat.traits.filter((t) => t.effects.some((e) => cat.effects.find((x) => x.code === e.effect)!.live)).map((t) => t.code)
  expect(liveTraits.sort()).toEqual(['NAVIGATOR', 'PURSER', 'QUARTERMASTER', 'SURGEON'])
})

test('D14: every harbour speaks one language, every language is spoken, a captain speaks her home\'s first', () => {
  const ports = (read('data/ports.json') as { ports: unknown[] }).ports
  expect(gen.harbours.length, 'a harbour has no language').toBe(ports.length)
  expect(cat.languages.filter((l) => !gen.harbours.some((h) => h.language === l.code)).map((l) => l.code)).toEqual([])
  const spoken = new Map(gen.harbours.map((h) => [h.port, h.language]))
  for (const p of people) {
    const c = card.get(p.code)!
    expect(c.languages[0], p.code).toBe(spoken.get(p.home))
    expect(c.languages.length, p.code).toBe(1 + cat.extra_languages[c.grade])
    expect(new Set(c.languages).size, `${p.code} repeats a language`).toBe(c.languages.length)
    expect(trait.get(c.job), `${p.code}: job ${c.job} is not a trait`).toBeTruthy()
  }
})

test('§12: no captain, trait or language is a gate — the catalogue names no refusal', () => {
  const text = readFileSync(path.join(process.cwd(), 'data', 'captains.json'), 'utf8')
  expect(text).not.toMatch(/\bE_[A-Z_]+\b/)
})

test('D9 (0157): every hull role has a cabin rotation of the three typed cabins, and a Captain\'s cabin exists', () => {
  const cabins = (read('data/captains.json') as { cabins: { kinds: { code: string }[]; rotation: Record<string, string[]> } }).cabins
  expect(cabins.kinds.map((k) => k.code)).toContain('captain')
  const typed = cabins.kinds.map((k) => k.code).filter((c) => c !== 'captain').sort()
  for (const [role, list] of Object.entries(cabins.rotation)) expect([...list].sort(), role).toEqual(typed)
  const lines = read('data/ship-lines.json') as { profiles: { role: string }[] }
  const ships = read('data/ships.generated.json') as { hulls: { role: string }[] }
  const roles = new Set([...lines.profiles.map((p) => p.role), ...ships.hulls.map((h) => h.role)])
  expect([...roles].filter((r) => !(r in cabins.rotation))).toEqual([])
})
