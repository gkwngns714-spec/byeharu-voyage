// PURE UNIT SPEC — a Korean refusal keeps the fleet name the server's English sentence leads with (an armada's
// fleet refused: `Frota 1-1: Wait 10 / 30 min`, `Almiranta: Crew 6 / 8`). No browser, no server.

import { test, expect } from '@playwright/test'
import { refusalWords, servedName } from '../src/components/ui/refusalWords'

const CREW = { have: 6, need: 8, unit: 'crew' }

test('the name before the have / need line is kept in Korean', () => {
  expect(servedName('Almiranta: Crew 6 / 8', CREW)).toBe('Almiranta')
  expect(servedName('Frota 1-1: Wait 10 / 30 min', { have: 10, need: 30 })).toBe('Frota 1-1')
  const bare = refusalWords('ko', 'E_CREW_SHORT', CREW)
  expect(bare).not.toBeNull()
  expect(refusalWords('ko', 'E_CREW_SHORT', CREW, 'Almiranta: Crew 6 / 8')).toBe(`Almiranta: ${bare}`)
})

test('no name, no prefix; prose with a colon is not a name; English stays the server sentence', () => {
  expect(servedName('Crew 6 / 8', CREW)).toBeNull()
  expect(servedName('Frota 1-1 fought 3 minutes ago: one battle in 30', { have: 3, need: 30 })).toBeNull()
  expect(servedName('Almiranta: Crew 6 / 8', undefined)).toBeNull()
  expect(refusalWords('ko', 'E_CREW_SHORT', CREW, 'Crew 6 / 8')).toBe(refusalWords('ko', 'E_CREW_SHORT', CREW))
  expect(refusalWords('en', 'E_CREW_SHORT', CREW, 'Almiranta: Crew 6 / 8')).toBeNull()
})
