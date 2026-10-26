// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PLAN WORDS — why a city is out of reach, in the player's words (docs/WORDS.md; 0188)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `reachWords` is THE ONE WORDING for an unsailable city — the plan builder's note reads it. It used to say "cannot be reached in legs of 1,700 nm" and "her reach", then a full sentence; the
// owner's map-UX law is no jargon, and docs/WORDS.md says a distance reads as days of sailing. This spec
// pins the three answers and the words they may not contain.
//
// PURE SPEC. No `page` fixture; Playwright runs it as a plain Node process.

import { test, expect } from '@playwright/test'
import { reachBoard, reachWords, seaAsksWords } from '../src/features/command/plans/planLines'

/** A 5-knot fleet whose captain plots 1,700 miles a leg (14.2 days) with 36 days of supplies on board. */
const board = reachBoard({ fleet: { speed_kn: 5 } as never, reach: { navigation: 2, reach_nm: 1700 }, supplies: { days: 36, margin: 1.2 } })

const noLeg = { stops: null, miles: null }

test('a city no leg reaches names the Navigation that would, in days at sea', () => {
  const words = reachWords({ ...noLeg, needs: { navigation: 3, reach_nm: 2600 } }, board)
  expect(words).toBe('too far in one go: longest leg 14.2 days. Navigation 3 would reach it')
})

test('a city no Navigation reaches says so, with the farthest any plots', () => {
  const words = reachWords({ ...noLeg, needs: { navigation: null, reach_nm: 4000 } }, board)
  expect(words).toBe(
    'too far in one go: longest leg 14.2 days. No captain can plan it, and no port to stop at',
  )
})

test('a reachable city the supplies do not carry names its longest leg against them', () => {
  const words = reachWords({ stops: ['CEU'], miles: 3100, longest_leg: { miles: 2500, days: 20.8 } }, board)
  expect(words).toBe('longest leg 20.8 days, can carry 36.0 days')
})

test('0231: the board carry_days (her hold beside her cargo) is what the words read, not her casks now', () => {
  const carry = reachBoard({ fleet: { speed_kn: 5 } as never, reach: { navigation: 2, reach_nm: 1700 }, supplies: { days: 2, margin: 1.15, carry_days: 4.3 } })
  const words = reachWords({ stops: ['CEU'], miles: 3100, longest_leg: { miles: 2500, days: 20.8 } }, carry)
  expect(words).toBe('longest leg 20.8 days, can carry 4.3 days')
})

test('0231: a city the stores cannot reach says so with the server figures, not "too far"', () => {
  const shut = { code: 'E_ENDURANCE', sentence: '…', figures: { nm: 1614, leg_days: 6.8, need_days: 7.8, carry_days: 4.3, cap_nm: 884 } }
  const words = reachWords({ ...noLeg, needs: null, shut }, board)
  expect(words).toBe('Hold too full: 4.3 days of supplies, crossing needs 7.8 days')
  expect(words).not.toMatch(/\bnm\b|\bher\b|\bpassage\b|\bstores\b/)
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

// 0219: the board row's `sea` — what the seas on the route ask, and the one rule's verdict (public.sea_refusal)
const closed = {
  zone: 'NOR-MAC',
  zone_name: 'Macaronesia and the Canary Current',
  needs_title: 2,
  needs_wave: 10,
  refusal: {
    code: 'E_SEA_CLOSED',
    sentence: 'Macaronesia and the Canary Current asks title 2 and wave resistance 10 — you are title 1 and your fleet holds 12',
    figures: { zone: 'NOR-MAC', zone_name: 'Macaronesia and the Canary Current', needs_title: 2, title: 1, needs_wave: 10, wave: 12 },
  },
}
const lit = reachBoard({ fleet: { speed_kn: 5 } as never, reach: { navigation: 2, reach_nm: 1700 }, supplies: { days: 36, margin: 1.2 }, sea: { bite: true, title: 1, wave: 12 } })

test('lit, a city the sea closes says what the sea asks, not "too far"', () => {
  const words = reachWords({ ...noLeg, needs: null, sea: closed }, lit)
  expect(words).toBe('Sea Macaronesia and the Canary Current: title 2, waves 10 · you: title 1, waves 12')
  expect(words).not.toContain('too far')
})

test('dark, the sea is a reading: the reason stays the reach', () => {
  expect(board.seaBite).toBe(false)
  expect(reachWords({ ...noLeg, needs: { navigation: 3, reach_nm: 2600 }, sea: closed }, board)).toMatch(/^too far in one go/)
})

test('lit, a city closed by the reach and open by the sea is still too far', () => {
  const open = { ...closed, refusal: null }
  expect(reachWords({ ...noLeg, needs: { navigation: 3, reach_nm: 2600 }, sea: open }, lit)).toMatch(/^too far in one go/)
})

test('what the seas on the way ask, with no refusal, is the route\'s most', () => {
  expect(seaAsksWords({ ...closed, needs_title: 4, needs_wave: 30, refusal: null })).toBe(
    'Route: title 4, waves 30',
  )
  expect(seaAsksWords(closed)).not.toMatch(/\bnm\b|\bher\b|\bpassage\b|\bstores\b/)
})
