// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PLAN WORDS — why a city is out of reach, in the player's words (docs/WORDS.md; 0188)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `reachWords` is THE ONE WORDING for an unsailable city — the plan builder's note and the best-trade
// card's rows both read it. It used to say "cannot be reached in legs of 1,700 nm" and "her reach"; the
// owner's map-UX law is no jargon, and docs/WORDS.md says a distance reads as days of sailing. This spec
// pins the three answers and the words they may not contain.
//
// PURE SPEC. No `page` fixture; Playwright runs it as a plain Node process.

import { test, expect } from '@playwright/test'
import { reachBoard, reachWords, viaWords } from '../src/features/command/plans/planLines'

/** A 5-knot fleet whose captain plots 1,700 miles a leg (14.2 days) with 36 days of supplies on board. */
const board = reachBoard({ fleet: { speed_kn: 5 } as never, reach: { navigation: 2, reach_nm: 1700 }, supplies: { days: 36, margin: 1.2 } })

const noLeg = { stops: null, miles: null }

test('a city no leg reaches names the Navigation that would, in days at sea', () => {
  const words = reachWords({ ...noLeg, needs: { navigation: 3, reach_nm: 2600 } }, board)
  expect(words).toBe('farther than your navigator can plot in one leg (up to 14.2 days); Navigation 3 plots legs of up to 21.7 days')
})

test('a city no Navigation reaches says so, with the farthest any plots', () => {
  const words = reachWords({ ...noLeg, needs: { navigation: null, reach_nm: 4000 } }, board)
  expect(words).toBe(
    'farther than your navigator can plot in one leg (up to 14.2 days); no navigator plots one that long (33.3 days at the most), and no chain of ports gets there',
  )
})

test('a reachable city the supplies do not carry names its longest leg against them', () => {
  const words = reachWords({ stops: ['CEU'], miles: 3100, longest_leg: { miles: 2500, days: 20.8 } }, board)
  expect(words).toBe('its longest leg is 20.8 days at sea, more than your 36.0 days of supplies')
})

test('a board with no speed falls back to miles, spelled, never nm', () => {
  const slow = { ...board, speedKn: 0 }
  expect(reachWords({ ...noLeg, needs: { navigation: 3, reach_nm: 2600 } }, slow)).toContain('2,600 miles')
})

test('no answer says nm, her, passage or stores', () => {
  const rows = [
    { ...noLeg, needs: { navigation: 3, reach_nm: 2600 } },
    { ...noLeg, needs: { navigation: null, reach_nm: 4000 } },
    { ...noLeg },
    { stops: ['CEU'], miles: 3100, longest_leg: { miles: 2500, days: 20.8 } },
    { stops: [], miles: 900 },
  ]
  for (const b of [board, { ...board, reachNm: null, supplyDays: null }]) {
    for (const row of rows) expect(reachWords(row, b)).not.toMatch(/\bnm\b|\bher\b|\bpassage\b|\bstores\b/)
  }
})

test('via words name the stops in the server order, or nothing when the voyage is direct', () => {
  const name = (c: string) => ({ CEU: 'Ceuta', ANG: 'Angra' })[c] ?? c
  expect(viaWords(['CEU', 'ANG'], name)).toBe('via Ceuta, Angra')
  expect(viaWords([], name)).toBeNull()
})
