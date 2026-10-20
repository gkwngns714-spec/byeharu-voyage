// PURE UNIT SPEC — src/lib/i18n. No browser: Playwright runs it as a plain Node process.
//
// What it pins: the two languages cannot drift apart. `defineDict` already makes a missing or
// extra Korean key a `tsc` error; this spec is the same law read at run time, plus the parts a
// type cannot see — an empty Korean entry, an entry left in English, a placeholder the Korean
// sentence dropped or invented, and a plural written on one side only.

import { test, expect } from '@playwright/test'
import { DICT, translate, translateMaybe, properName, type Msg } from '../src/lib/i18n'

/** Entries that are the SAME word in both languages on purpose: the switch names each language in
 *  its own script, and a symbol is a symbol. Anything else left equal is an untranslated string. */
const SAME_IN_BOTH = new Set(['common.korean', 'common.english'])

const texts = (m: Msg): string[] => (typeof m === 'string' ? [m] : [m.one, m.other])
const holes = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map((x) => x[1]).sort()
const sections = Object.entries(DICT as unknown as Record<string, { en: Record<string, Msg>; ko: Record<string, Msg> }>)

test('every dictionary has the same keys in English and in Korean', () => {
  expect(sections.length).toBeGreaterThan(0)
  const bad: string[] = []
  for (const [name, d] of sections) {
    const en = Object.keys(d.en).sort()
    const ko = Object.keys(d.ko).sort()
    for (const k of en) if (!(k in d.ko)) bad.push(`${name}.${k}: no Korean entry`)
    for (const k of ko) if (!(k in d.en)) bad.push(`${name}.${k}: Korean entry with no English one`)
  }
  expect(bad, bad.join('\n')).toEqual([])
})

test('no Korean entry is empty, left in English, or missing a placeholder', () => {
  const bad: string[] = []
  let checked = 0
  for (const [name, d] of sections) {
    for (const [k, en] of Object.entries(d.en)) {
      const ko = d.ko[k]
      if (ko === undefined) continue
      const id = `${name}.${k}`
      checked++
      if (typeof en !== typeof ko) bad.push(`${id}: plural on one side only`)
      const [e, o] = [texts(en), texts(ko)]
      o.forEach((s, i) => {
        if (s.trim() === '') bad.push(`${id}: empty`)
        if (s === e[i] && /[A-Za-z]{2}/.test(s.replace(/\{\w+\}/g, '')) && !SAME_IN_BOTH.has(id)) bad.push(`${id}: still English — "${s}"`)
        if (holes(s).join() !== holes(e[i] ?? '').join())
          bad.push(`${id}: placeholders {${holes(e[i] ?? '')}} vs {${holes(s)}}`)
      })
    }
  }
  expect(checked, 'no entries were read — the registry moved').toBeGreaterThan(0)
  expect(bad, bad.join('\n')).toEqual([])
})

test('a string is read in the asked language, filled, and plural-picked', () => {
  expect(translate('en', 'common.close')).toBe('Close')
  expect(translate('ko', 'common.close')).toBe('닫기')
  expect(translateMaybe('ko', 'common', 'no-such-entry')).toBeNull()
})

test('a proper noun is Korean where the map has it and the served name where it does not', () => {
  expect(properName('port', 'Lisbon', 'Lisbon', 'ko')).toBe('리스본')
  expect(properName('port', 'Lisbon', 'Lisbon', 'en')).toBe('Lisbon')
  expect(properName('port', 'Nowhere Bay', 'Nowhere Bay', 'ko')).toBe('Nowhere Bay')
  expect(properName('good', 'black-pepper', 'Black Pepper', 'ko')).toBe('후추')
  expect(properName('nation', 'JOS', 'Joseon', 'ko')).toBe('조선')
})
