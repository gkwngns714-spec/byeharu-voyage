import { test, expect } from '@playwright/test'
import { draftOf, settingsOf } from '../src/features/city/corp/settingsDraft'
import { stateWord } from '../src/features/city/corp/workerRows'
import { fixOf } from '../src/domain/fleet/fix'

// THE PASSIVE SETTINGS OF A FIXED JOB (0516): what the Assign sheet sends is what was typed, and an empty box sends nothing.

test('an empty box sends nothing; a number is sent as typed; a bring-home run sends no sale settings', () => {
  expect(settingsOf({}, true)).toEqual({})
  expect(settingsOf({ under: '', over: ' ', crew: 'x' }, true)).toEqual({})
  expect(settingsOf({ under: '1,200', over: '15.5', crew: '20', days: '9', stop_profit: '0', stop_damage: '30' }, true)).toEqual({ under: 1200, over: 15.5, crew: 20, days: 9, stop_profit: 0, stop_damage: 30 })
  expect(settingsOf({ under: '5', over: '6', stop_profit: '7', stop_damage: '8' }, false)).toEqual({ under: 5, stop_damage: 8 })
})

test('the boxes start as the running job has them', () => {
  expect(draftOf(null)).toEqual({})
  expect(draftOf({ good: 'wine', buy: 'LIS', sell: 'OPO', under: 12, stop_damage: 30 })).toEqual({ under: '12', stop_damage: '30' })
})

test('a job out of its range says so, and a hull past its stop offers Repair', () => {
  expect(stateWord({ state: 'working', waiting: true, wait: { code: 'range', sentence: 'buys at 2.00, your limit 1.00', retryMs: 0 } })).toBe('corp.outOfRange')
  expect(fixOf('E_STOP_DAMAGE')).toBe('repair')
  expect(fixOf('E_STOP_PROFIT')).toBeNull()
})
