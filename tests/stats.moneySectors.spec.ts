// THE MONEY LOG'S SECTORS (moneySectors.ts, owner 227): one map from a row's kind to its filter chip. Pure.
import { test, expect } from '@playwright/test'
import { SECTORS, sectorOf } from '../src/features/stats/moneySectors'

test('kinds file under their sector; the city side of a trade flips; unknown kinds are other', () => {
  expect(sectorOf('BUY', 'company')).toBe('bought')
  expect(sectorOf('BUY', 'city')).toBe('sold')
  expect(sectorOf('SELL', 'company')).toBe('sold')
  expect(sectorOf('SELL', 'city')).toBe('bought')
  expect(sectorOf('PROVISION', 'company')).toBe('supplies')
  expect(sectorOf('WAGES', 'company')).toBe('wages')
  expect(sectorOf('REPAIR', 'company')).toBe('repairs')
  expect(sectorOf('INSURANCE', 'company')).toBe('insurance')
  expect(sectorOf('INSURANCE_PAID', 'city')).toBe('insurance')
  expect(sectorOf('TAX', 'company')).toBe('tax')
  expect(sectorOf('PORT_FEE', 'company')).toBe('fees')
  expect(sectorOf('CAPITAL_GIFT', 'company')).toBe('gifts')
  expect(sectorOf('SHARE', 'company')).toBe('shares')
  expect(sectorOf('DIVIDEND', 'company')).toBe('shares')
  expect(sectorOf('SOMETHING_NEW', 'company')).toBe('other')
  expect(SECTORS).toContain('other')
})
