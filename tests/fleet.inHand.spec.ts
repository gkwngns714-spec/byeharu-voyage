import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { openFleetSheet } from './desk.fixture'
import { SECOND_FLEET, serveTwoFleets } from './twoFleets.fixture'
import { fleetSignal } from '../src/domain/fleet'
import type { FleetView, QueuedOrder } from '../src/lib/rpc'

// WHICH FLEET, AND HOW SHE IS. Until H3 (2026-11-24) this was tests/desk.fleetpicker.spec.ts: the Trade desk's fleet picker (a
// button, a dropdown, a tray). The picker went with the desk; what it guarded and still stands is kept here:
//   · the one where-rule, `fleetSignal` (domain/fleet), which HQ's worker rows now read (features/city/corp/workerRows.ts);
//   · with two fleets, HQ lists both, and the fleet whose row is pressed is the one in hand: the sheet that opens is HERS.

const order = (status: QueuedOrder['status']): QueuedOrder =>
  ({ id: status, seq: 1, text: 'SAIL', verb: 'SAIL', status, error_code: status === 'failed' ? 'E_X' : null, error_message: null, figures: null, result: null }) as QueuedOrder

const fleet = (over: Partial<FleetView>): FleetView =>
  ({ id: 'f', name: 'F', status: 'DOCKED', port: 'LIS', anchor: null, voyage: null, queue: [], ...over }) as unknown as FleetView

test('fleetSignal: a sailing voyage is green, a docked or anchored fleet is grey, a refused order or a crippled status is red', () => {
  expect(fleetSignal(fleet({}))).toBe('waiting')
  expect(fleetSignal(fleet({ queue: [order('pending')] }))).toBe('waiting')
  expect(fleetSignal(fleet({ status: 'ANCHORED', port: null, anchor: [33, -15] }))).toBe('waiting')
  expect(fleetSignal(fleet({ status: 'SAILING', port: null, voyage: { to: 'CAD', eta: '2026-01-01T00:00:00Z' } as FleetView['voyage'] }))).toBe('sailing')
  expect(fleetSignal(fleet({ queue: [order('done'), order('failed')] }))).toBe('stuck')
  expect(fleetSignal(fleet({ status: 'ADRIFT', port: null }))).toBe('stuck')
  expect(fleetSignal(fleet({ status: 'UNABLE_TO_SAIL' }))).toBe('stuck')
  // A refused order outranks the voyage: she may still be moving, and she still needs you.
  expect(fleetSignal(fleet({ status: 'SAILING', port: null, voyage: { to: 'CAD', eta: '2026-01-01T00:00:00Z' } as FleetView['voyage'], queue: [order('failed')] }))).toBe('stuck')
})

for (const size of [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const)
  test.describe('en-US', () => {
    test.use({ locale: 'en-US' })
    test(`two fleets at ${size.width}px: HQ lists both, and the one pressed is the one in hand`, async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`)
      await page.setViewportSize(size)
      await serveTwoFleets(page)
      await page.goto('city')
      await ready(page)
      const rows = page.locator('[data-testid="corp-worker"][data-kind="fleet"]')
      await expect(rows, 'HQ does not list both fleets').toHaveCount(2, { timeout: 120_000 })
      const second = rows.filter({ hasText: SECOND_FLEET })
      await expect(second).toHaveCount(1)
      const id = (await second.getAttribute('data-worker'))!
      const sheet = await openFleetSheet(page, id)
      await expect(page.locator('[data-detail-page]').last(), 'the sheet that opened is not hers').toContainText(SECOND_FLEET)
      await expect(sheet.getByTestId('trade-status')).toBeVisible()
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
