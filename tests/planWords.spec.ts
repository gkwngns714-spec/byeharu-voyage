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
  expect(words).toBe('too far to sail in one go: your navigator can only plan 14.2 days at sea without a stop. A captain with Navigation 3 could take you there')
})

test('a city no Navigation reaches says so, with the farthest any plots', () => {
  const words = reachWords({ ...noLeg, needs: { navigation: null, reach_nm: 4000 } }, board)
  expect(words).toBe(
    'too far to sail in one go: your navigator can only plan 14.2 days at sea without a stop. No captain can plan a trip that long, and there are no ports on the way to stop at',
  )
})

test('a reachable city the supplies do not carry names its longest leg against them', () => {
  const words = reachWords({ stops: ['CEU'], miles: 3100, longest_leg: { miles: 2500, days: 20.8 } }, board)
  expect(words).toBe('the longest stretch at sea is 20.8 days, but your supplies last only 36.0 days')
})

test('a board with no speed falls back to miles, spelled, never nm', () => {
  const slow = { ...board, speedKn: 0 }
  expect(reachWords({ ...noLeg, needs: { navigation: 3, reach_nm: 2600 } }, slow)).toContain('1,700 miles')
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
