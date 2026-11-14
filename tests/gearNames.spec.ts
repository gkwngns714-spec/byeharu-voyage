// PURE UNIT SPEC — the Gear face's words in Korean (0424, owner row 345: "every word in EN and KO"). The face prints each starter
// piece's name and note, its rack's word and its effects. The server serves those in English; Korean prints names/gear.ts and
// words the effects from their figures (src/live/gearWords.ts). This fails when a starter piece, a rack or a stat a starter piece
// moves has no Korean word, so a new piece cannot reach a Korean screen in English.

import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { KO_GEAR, KO_GEAR_NOTES, KO_RACKS } from '../src/lib/i18n/names/gear'
import { GEAR_STAT_WORD } from '../src/live/gearWords'
import { DICT } from '../src/lib/i18n'

const read = (rel: string) => JSON.parse(readFileSync(path.join(process.cwd(), rel), 'utf8'))

test('every starter piece, every rack and every stat a starter piece moves has a Korean word', () => {
  const items: { code: string; starter?: number; rack: string; effects: { stat: string }[] }[] = read('data/gear.generated.json').items
  const starters = items.filter((i) => i.starter)
  expect(starters.length, 'no starter piece in data/gear.generated.json: the spec reads nothing').toBeGreaterThan(0)
  const missing: string[] = []
  for (const s of starters) {
    if (!KO_GEAR[s.code]) missing.push(`name ${s.code}`)
    if (!KO_GEAR_NOTES[s.code]) missing.push(`note ${s.code}`)
    if (!KO_RACKS[s.rack]) missing.push(`rack ${s.rack}`)
    for (const e of s.effects) if (!GEAR_STAT_WORD[e.stat]) missing.push(`stat ${e.stat} (${s.code})`)
  }
  for (const r of read('data/gear.json').racks as { code: string }[]) if (!KO_RACKS[r.code]) missing.push(`rack ${r.code}`)
  const ko = (DICT as unknown as Record<string, { ko: Record<string, unknown> }>).ship.ko
  for (const key of Object.values(GEAR_STAT_WORD)) if (!ko[key.split('.')[1]]) missing.push(`dictionary ${key}`)
  expect(missing, missing.join('\n')).toEqual([])
})
