// PURE UNIT SPEC — BOUNTIES ON NAMED PIRATES (0471): a named pirate's name in both languages from the three served parts, and the one reader
// of "Bounty claimed +N" off a fight's BATTLE_REPORT (src/live/bountyPaid.ts). Dark, no report carries a bounty, so nothing is read.

import { test, expect } from '@playwright/test'
import { bountyName } from '../src/live/bountyWords'
import { bountyOf, bountyOfBattle } from '../src/live/bountyPaid'
import { translate } from '../src/lib/i18n'
import type { LedgerEvent, SnapshotPort } from '../src/lib/rpc'

const ports = { PRL: { code: 'PRL', name: 'Port Royal' } } as unknown as Record<string, SnapshotPort>

const report = (payload: Record<string, unknown>, id = 'e1'): LedgerEvent =>
  ({ id, kind: 'BATTLE_REPORT', payload, created_at: '2026-11-22T00:00:00Z' }) as unknown as LedgerEvent

test('a named pirate is called by her three parts, in English and in Korean', () => {
  expect(bountyName('en', { epithet: 'BLACK', given: 'Ruy', home: 'PRL' }, ports)).toBe('Black Ruy of Port Royal')
  const ko = bountyName('ko', { epithet: 'BLACK', given: 'Ruy', home: 'PRL' }, ports)
  expect(ko).toContain('검은 루이')
  expect(ko).not.toContain('Black')
  // a part the dictionary does not know prints as served, never a guess
  expect(bountyName('en', { epithet: 'NEW', given: 'Zed', home: null }, ports)).toBe('NEW Zed of ')
})

test('a fight that paid a bounty says so; a report with none, or a bounty of 0, says nothing', () => {
  const paid = report({ battle_id: 'b1', outcome: 'DRIVEN_OFF', bounty: { name: 'Black Ruy of Port Royal', epithet: 'BLACK', given: 'Ruy', home: 'PRL', paid: 17000, value: 17000 } })
  expect(bountyOf(paid)).toEqual({ battle: 'b1', paid: 17000, epithet: 'BLACK', given: 'Ruy', home: 'PRL' })
  expect(bountyOf(report({ battle_id: 'b2', outcome: 'PLUNDERED' }))).toBeNull()
  expect(bountyOf(report({ battle_id: 'b3', bounty: { epithet: 'RED', given: 'Anne', paid: 0 } }))).toBeNull()
  expect(bountyOf({ ...paid, kind: 'VOYAGE_REPORT' } as LedgerEvent)).toBeNull()
  expect(bountyOfBattle([report({ battle_id: 'b2' }, 'e0'), paid], 'b1')?.paid).toBe(17000)
  expect(bountyOfBattle([paid], 'b9')).toBeNull()
  expect(bountyOfBattle([paid], null)).toBeNull()
  expect(translate('en', 'bounty.claimed', { n: '17,000' })).toBe('Bounty claimed +17,000')
  expect(translate('ko', 'bounty.claimed', { n: '17,000' })).toBe('현상금 수령 +17,000')
})
