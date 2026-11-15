// PURE UNIT SPEC — migration 0433, THE SERVER SAYS HAVE AND NEED (owner 2026-11-15, row 350: "too much word should be shorter ... just tell me what
// i have, and what is required"). No browser, no server.
//   * a Korean refusal with have / need figures is the label and the pair, as the server's English is (cmd.refusal_line): `돈 5,000 / 9,000`;
//     a skill's refusal keeps its sentence (it names the skill); figures of another shape keep the sentence alone;
//   * the eight news templates 0433 writes name the same {words} in English and Korean, and the same words as the templates they replace (0347, 0362),
//     and each is no longer than the one it replaces; filled, no `{name}` is left;
//   * a room rung still shut reads her level against it (`Trading 2 / 3`).

import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { refusalWords } from '../src/components/ui/refusalWords'
import { roomStepWord } from '../src/live/houseRoom'
import { tFor } from '../src/lib/i18n'

const MIG = readFileSync(path.resolve('supabase', 'migrations', '20260818000433_the_server_says_have_and_need.sql'), 'utf8').replaceAll('\r', '')

test('a Korean refusal with a have / need pair is the label and the pair; English is the server\'s own sentence', () => {
  expect(refusalWords('en', 'E_INSUFFICIENT_FUNDS', { have: 5000, need: 9000, unit: 'ducats' })).toBeNull()
  expect(refusalWords('ko', 'E_INSUFFICIENT_FUNDS', { have: 5000, need: 9000, unit: 'ducats' })).toBe('돈 5,000 / 9,000')
  expect(refusalWords('ko', 'E_ENDURANCE', { have: 2.9, need: 33, unit: 'days' })).toBe('보급 2.9 / 33일')
  expect(refusalWords('ko', 'E_HOLD_FULL', { have: 120, need: 150, unit: 't' })).toBe('화물칸 120 / 150톤')
  expect(refusalWords('ko', 'E_HOLD_FULL', { have: 120, need: 150, unit: 'ducats' })).toBe('돈 120 / 150')
  expect(refusalWords('ko', 'E_CREW_SHORT', { have: 6, need: 8, unit: 'crew' })).toBe('선원 6 / 8')
  // a skill's refusal names the skill: its sentence stands, the figures after it
  expect(refusalWords('ko', 'E_NEEDS_SKILL', { have: 2, need: 3, unit: 'level' })).toMatch(/\(2 \/ 3 /)
  // no figures, or a closed sea's: the code's sentence alone
  expect(refusalWords('ko', 'E_HOLD_FULL', null)).toBe('화물칸 가득 참.')
})

test('the server labels and the client labels are the same codes and units', () => {
  // every code the server labels (cmd.refusal_line) has a Korean label, and every unit it labels too
  const fn = MIG.slice(MIG.indexOf('create function cmd.refusal_line'), MIG.indexOf('$fn$\n$f$;', MIG.indexOf('create function cmd.refusal_line')))
  const codes = [...fn.matchAll(/'(E_[A-Z_]+)'/g)].map((m) => m[1]).filter((c) => !['E_NEEDS_SKILL', 'E_SKILL_PREREQ', 'E_SKILL_ORDER'].includes(c))
  expect(codes.length).toBeGreaterThan(10)
  for (const c of codes) expect(refusalWords('ko', c, { have: 1, need: 2, unit: 'zz' }), c).not.toBeNull()
  for (const u of ['ducats', 'crew', 'days', 't', 'miles', 'minutes', 'seconds', 'reputation', 'level', 'levels', 'depth'])
    expect(refusalWords('ko', 'E_ANY', { have: 1, need: 2, unit: u }), u).not.toMatch(/\(/)
})

test('the eight short news templates name the same words in both languages and as before, and are no longer', () => {
  const rows = [...MIG.matchAll(/^ {6}\('([A-Z_]+)',\s+'([^']+)', '([^']+)', '([^']+)'\)[,)]/gm)].map((m) => ({ kind: m[1], was: m[2], en: m[3], ko: m[4] }))
  expect(rows.map((r) => r.kind).sort()).toEqual(['BIG_BUY', 'BIG_SALE', 'CAPITAL_GIFT', 'NEW_HARBOUR', 'PIRATES', 'PRICE_SPIKE', 'RELATIONS', 'UPDATE'])
  const names = (s: string) => [...s.matchAll(/\{([a-z_]+)\}/g)].map((m) => m[1]).sort()
  for (const r of rows) {
    expect(names(r.en), r.kind).toEqual(names(r.was))
    expect(names(r.ko), r.kind).toEqual(names(r.was))
    expect(r.en.length, `${r.kind}: ${r.en}`).toBeLessThanOrEqual(r.was.length)
  }
  expect(rows.find((r) => r.kind === 'UPDATE')!.en).toBe('{title}')
})

test('a room rung still shut reads her level against it', () => {
  const t = tFor('en')
  expect(roomStepWord(t, { how: 'level', tracks: ['trading'], level: 3, open: false }, 2)).toBe('Trading 2 / 3')
  expect(roomStepWord(t, { how: 'level', tracks: ['trading'], level: 1, open: true }, 2)).toBe('Trading 1')
  expect(roomStepWord(t, { how: 'level', tracks: ['trading'], level: 3, open: false })).toBe('Trading 3')
})
