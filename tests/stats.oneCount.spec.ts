// PURE UNIT SPEC — the Stats faces and their words. No browser: Playwright runs it as a plain Node process.
//
// ═══════════════════════════════════════════════════════════════════════════════
// THE STATS COUNT ONCE — the client's half of the guard (0448, docs/STATS_ONE_COUNT.md)
// ═══════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-16: *"stats is messed up. the ships at sea, in port, laid up, wrecked are all different numbers. i want you to make it so
// that this error does not happen again."* On production the Merchants face said In port 148 where the Ships face said 68, its five figures
// added up to 973 under "885 fleets", and a fleet in a fight was "at sea" on one line and nowhere on another. The server now decides a fleet's
// state in ONE function and counts in ONE (public.fleet_state_of, public.fleet_tally; proof 150 holds that side). This spec holds the client's:
//
//   1. ONE PLACE NAMES THE STATES. The five state words are spelled in src/features/stats/fleetStates.ts and nowhere else in src: every face
//      shows a kind's count through its <FleetStates> and a fleet's state through its fleetStateWord, so the words, their order and their tones
//      cannot differ between faces.
//   2. THE FACES PRINT SERVED NUMBERS. No Stats face adds, subtracts, multiplies or reduces a figure of the count (fleets, ships, or one of the
//      five states), and none builds a state bar of its own.
//   3. THE WORDS ARE THE SERVER'S FIVE. The client's states are exactly the server's keys, in the rule's vocabulary, each with its own word in
//      English and in Korean; no two states share a word; the count of wrecks in a window has a word of its own ("Wrecks"), not the state's.
//   4. THE OLD KEYS ARE GONE. The Merchants face's type has no state of its own (sailing / docked / repairing / unable).
//
// WHICH WERE RED BEFORE: 1 (Ships.tsx, Fleets.tsx and Merchants.tsx each spelled the words), 3 (no `battle`; "Wrecked" was a state and a 24 h
// count on one card) and 4, on origin/main 7419d275.

import { test, expect } from '@playwright/test'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { DICT, type Msg } from '../src/lib/i18n'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const SRC = path.join(ROOT, 'src')
const STATS = path.join(SRC, 'features', 'stats')
const AUTHORITY = path.join(STATS, 'fleetStates.ts')
/** The server's five states, in the rule's order of reading on a face (supabase/migrations/20260818000448: public.fleet_state_of). */
const SERVER_STATES = ['sea', 'port', 'battle', 'laid_up', 'wrecked'] as const
/** Every figure of the count (public.fleet_tally). */
const TALLY = ['fleets', 'ships', ...SERVER_STATES] as const

const read = (p: string) => readFileSync(p, 'utf8').replaceAll('\r\n', '\n')
/** A source file without its comments (a comment may say anything). */
const code = (p: string) =>
  read(p)
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '')
function files(dir: string): string[] {
  return readdirSync(dir).flatMap((n) => {
    const p = path.join(dir, n)
    return statSync(p).isDirectory() ? files(p) : /\.tsx?$/.test(n) ? [p] : []
  })
}
const rel = (p: string) => path.relative(ROOT, p).replaceAll('\\', '/')

/** The authority's table, read from its source: [{ id, word }] in order. */
const states = [...read(AUTHORITY).matchAll(/\{ id: '(\w+)', word: 'stats\.(\w+)', tone: '(\w+)' \}/g)].map((m) => ({ id: m[1], word: m[2], tone: m[3] }))
const stats = (DICT as unknown as Record<string, { en: Record<string, Msg>; ko: Record<string, Msg> }>).stats

test('the five states are the server\'s, in one table, each with its own word in English and Korean', () => {
  expect(states.map((s) => s.id)).toEqual([...SERVER_STATES])
  for (const lang of ['en', 'ko'] as const) {
    const words = states.map((s) => stats[lang][s.word])
    expect(words.every((w) => typeof w === 'string' && w.length > 0), `${lang}: ${JSON.stringify(words)}`).toBe(true)
    expect(new Set(words).size, `${lang}: two states share a word: ${JSON.stringify(words)}`).toBe(states.length)
    // a 24 h count of wrecks is not the state "Wrecked": it has its own word
    expect(stats[lang].wrecks, `${lang}: stats.wrecks`).toBeTruthy()
    expect(words).not.toContain(stats[lang].wrecks)
    expect(stats[lang].byFleet, `${lang}: stats.byFleet (the bar counts fleets, and says so)`).toBeTruthy()
  }
  expect(new Set(states.map((s) => s.tone)).size, 'each state has its own tone').toBe(states.length)
})

test('no file but fleetStates.ts spells a state\'s word', () => {
  const keys = states.map((s) => `stats.${s.word}`)
  expect(keys.length).toBe(5)
  const bad: string[] = []
  for (const f of files(SRC)) {
    if (f === AUTHORITY) continue
    const s = code(f)
    for (const k of keys) if (s.includes(`'${k}'`) || s.includes(`"${k}"`)) bad.push(`${rel(f)} spells ${k}: use <FleetStates> or fleetStateWord (src/features/stats/fleetStates.ts)`)
  }
  expect(bad, bad.join('\n')).toEqual([])
})

test('every face shows a kind\'s count through <FleetStates>, and none builds a state bar of its own', () => {
  for (const name of ['Ships.tsx', 'Fleets.tsx', 'Merchants.tsx']) {
    const s = code(path.join(STATS, name))
    expect(s.includes('<FleetStates '), `${name} does not show its count through <FleetStates>`).toBe(true)
    expect(/\bStackedBar\b/.test(s), `${name} draws a stacked bar of its own: a kind's states are drawn by <FleetStates> alone`).toBe(false)
  }
  // a fleet's own state, on her line and on her page
  expect((code(path.join(STATS, 'Fleets.tsx')).match(/fleetStateWord\(t, (r|p)\.state\)/g) ?? []).length).toBe(2)
})

test('no Stats face computes a figure of the count: it prints what the server served', () => {
  const field = `(?:${TALLY.join('|')})`
  // a tally figure next to an arithmetic sign, on either side: `v.sea + v.port`, `fleets - kind.laid_up`, `(v.sea ?? 0) + …`
  const after = new RegExp(`\\.${field}\\b(?:\\s*\\?\\?\\s*0)?\\s*\\)?\\s*[-+*/](?!=?>)\\s*[\\w(]`)
  const before = new RegExp(`[\\w)]\\s*[-+*/]\\s*\\(?\\s*[\\w.]+\\.${field}\\b`)
  const bad: string[] = []
  for (const f of files(STATS)) {
    const lines = code(f).split('\n')
    lines.forEach((line, i) => {
      if (after.test(line) || before.test(line)) bad.push(`${rel(f)}:${i + 1} computes with a figure of the count: ${line.trim()}`)
    })
    if (['Ships.tsx', 'Fleets.tsx', 'Merchants.tsx', 'FleetStatesBar.tsx', 'fleetStates.ts'].includes(path.basename(f)) && /\.reduce\(/.test(lines.join('\n'))) {
      bad.push(`${rel(f)} reduces a list to a figure: the server counts (public.fleet_tally)`)
    }
  }
  expect(bad, bad.join('\n')).toEqual([])
  // the detector itself sees the two defects that were on production
  expect(after.test('const port = v.fleets - v.sailing')).toBe(true)
  expect(before.test('const total = a + kind.laid_up')).toBe(true)
  expect(after.test('value={(v.sea ?? 0) + (v.port ?? 0)}')).toBe(true)
  expect(after.test('value={tally.fleets ?? 0} format={formatInt}') || before.test('value={tally.fleets ?? 0} format={formatInt}')).toBe(false)
})

test('the types say one count: the client\'s state is the server\'s five, and the Merchants face has no state of its own', () => {
  const types = read(path.join(SRC, 'lib', 'rpc', 'types.ts'))
  const state = /export type StatsFleetState = ([^\n]+)/.exec(types)?.[1] ?? ''
  expect([...state.matchAll(/'(\w+)'/g)].map((m) => m[1])).toEqual([...SERVER_STATES])
  const tally = /export interface StatsFleetTally \{([\s\S]*?)\n\}/.exec(types)?.[1] ?? ''
  for (const k of [...TALLY, 'ships_by']) expect(new RegExp(`\\n  ${k}: `).test(tally), `StatsFleetTally.${k}`).toBe(true)
  const merchants = /export interface StatsMerchants \{([\s\S]*?)\n\}/.exec(types)?.[1] ?? ''
  expect(merchants.length).toBeGreaterThan(0)
  for (const old of ['docked', 'repairing', 'unable']) expect(new RegExp(`\\n  ${old}\\??: `).test(merchants), `StatsMerchants.${old} is back`).toBe(false)
  expect(/\n {2}sailing\??: /.test(merchants), 'StatsMerchants.sailing is back (the count serves `sea`)').toBe(false)
  expect(/export interface StatsFleetList extends Partial<StatsFleetTally>/.test(types), 'a fleet list\'s header is the tally').toBe(true)
})
