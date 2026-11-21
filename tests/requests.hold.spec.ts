import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { tradeDict } from '../src/lib/i18n/dict/trade'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// REQUESTS A SHIP CAN CARRY (migration 0466, dark behind hold_requests_enabled; docs/dev-log/2026-11-22-ship-requests.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The server's half is 0466's self-assert and proof 169. Here: the two new words stand in both tongues, 1-2 plain words beside a
// figure, and the board prints a hold job's served total (never a sum of its own) and names it, while a city's request keeps its
// bonus line. Dark there is no hold row, so nothing on screen changes until the owner lights the switch.

test('the hold job words stand in both tongues, 1-2 plain words', () => {
  for (const key of ['holdJob', 'holdPays'] as const) {
    for (const lang of ['en', 'ko'] as const) {
      const w = tradeDict[lang][key]
      expect(w, `no ${lang} word ${key}`).toBeTruthy()
      expect(w.replace('{total}', '').trim().split(/\s+/).length, `${lang} ${key} is more than two words: ${w}`).toBeLessThanOrEqual(2)
    }
  }
  expect(tradeDict.en.holdPays).toContain('{total}')
  expect(tradeDict.ko.holdPays).toContain('{total}')
})

test('the board prints the served total for a hold job and adds nothing itself', () => {
  const src = readFileSync(path.resolve('src', 'live', 'RequestBoard.tsx'), 'utf8')
  expect(src).toContain("r.size === 'hold'")
  expect(src).toMatch(/holdPays', \{ total: formatDucats\(r\.total\) \}/)
  expect(src).toContain("t('trade.bonusLine'")
  expect(src).not.toMatch(/r\.qty\s*\*|\*\s*r\.price_each/)
})
