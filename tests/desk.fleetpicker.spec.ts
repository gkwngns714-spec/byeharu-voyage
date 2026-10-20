// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FLEET PICKER (the owner, 2026-10-20: "when i have multiple fleets, how should this change?"
// — of this shape, "good. we need that"), made to fail.
//
//   · the signal word (domain/fleet `fleetSignal`) is one rule: sailing · waiting · stuck;
//   · ONE fleet: the header names her, flag and name, and there is nothing to press — no ▾, no list;
//   · SEVERAL fleets, wide glass: one button (flag · name · dot · ▾) opens a dropdown of rows (flag ·
//     name · where · cargo); a row SELECTS and closes it; outside press and Escape close it; ← / →
//     switch fleets, but not while typing in the search field; a stuck fleet that is NOT selected
//     shows as a red dot on the button; opening the list moves nothing on the page;
//   · SEVERAL fleets, phone: the same button opens the bottom tray, and the figures row under it
//     does not move by a pixel.
//
// The several-fleet world is the shipped image with a trigger that founds the house with a second
// fleet carrying one refused order (tests/twoFleets.fixture.ts); the one-fleet world is the shipped
// image as it is. Nothing here asserts a figure — only words, counts and geometry.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { test, expect, type Page } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'
import { SECOND_FLEET, serveTwoFleets } from './twoFleets.fixture'
import { fleetSignal } from '../src/domain/fleet'
import type { FleetView, QueuedOrder } from '../src/lib/rpc'

// ── 1. THE SIGNAL, IN NODE ───────────────────────────────────────────────────────────────────────

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

// ── 2. THE BROWSER ───────────────────────────────────────────────────────────────────────────────

const WIDE = { width: 1440, height: 900 }

async function openDesk(page: Page, request: Parameters<typeof reachable>[0], baseURL: string | undefined) {
  test.setTimeout(480_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('command')
  await ready(page)
  await expect(page.getByTestId('fleet-picker')).toBeVisible({ timeout: 120_000 })
}

const rect = (page: Page, sel: string) =>
  page.evaluate((s) => {
    const e = document.querySelector(s)
    if (!e) return null
    const r = e.getBoundingClientRect()
    return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) }
  }, sel)

for (const size of [WIDE, PHONE]) {
  test(`one fleet at ${size.width}px: her flag and name, nothing to press, no list`, async ({ page, request, baseURL }) => {
    await page.setViewportSize(size)
    await openDesk(page, request, baseURL)
    const picker = page.getByTestId('fleet-picker')
    await expect(picker).toHaveAttribute('data-fleets', '1')
    await expect(picker).toContainText('Gaivota')
    // Not a control: no ▾, no dot, no popup promised.
    expect(await picker.evaluate((e) => e.tagName)).not.toBe('BUTTON')
    await expect(picker.locator('[data-tone]')).toHaveCount(0)
    await expect(picker.locator('svg')).toHaveCount(0)
    await picker.click()
    await expect(page.getByTestId('fleet-list')).toHaveCount(0)
    // The two figures stand beside / under her as before.
    await expect(page.getByTestId('command-line')).toContainText('Cargo')
  })
}

test.describe('several fleets', () => {
  test.beforeEach(async ({ page }) => {
    await serveTwoFleets(page)
  })

  test('wide: one button, a dropdown of rows, a press selects, outside and Escape close, the arrows switch, the other red shows', async ({
    page,
    request,
    baseURL,
  }) => {
    await page.setViewportSize(WIDE)
    await openDesk(page, request, baseURL)
    const picker = page.getByTestId('fleet-picker')
    await expect(picker).toHaveAttribute('data-fleets', '2')
    await expect(picker).toHaveAttribute('aria-haspopup', 'dialog')
    // The desk opens on the first docked fleet — Gaivota, waiting (grey); Segunda's refused order
    // shows as the alert dot on the button, red.
    await expect(picker).toContainText('Gaivota')
    await expect(picker.getByTestId('fleet-picker-dot')).toHaveAttribute('data-tone', 'neutral')
    await expect(picker.getByTestId('fleet-picker-alert')).toHaveAttribute('data-tone', 'danger')
    await expect(page.getByTestId('fleet-list')).toHaveCount(0)

    // THE PRESS OPENS THE LIST AND MOVES NOTHING: the header, the figures and the first list rows
    // sit where they sat.
    await expect(page.getByTestId('watch-row').first()).toBeVisible({ timeout: 120_000 })
    const before = {
      header: await rect(page, '[data-testid="desk-header"]'),
      line: await rect(page, '[data-testid="command-line"]'),
      row: await rect(page, '[data-testid="watch-row"]'),
    }
    await picker.click()
    const list = page.getByTestId('fleet-list')
    await expect(list).toBeVisible()
    await expect(picker).toHaveAttribute('aria-expanded', 'true')
    const rows = list.getByTestId('fleet-row')
    await expect(rows).toHaveCount(2)
    await expect(rows.nth(0)).toContainText('Gaivota')
    await expect(rows.nth(0)).toContainText('Lisbon')
    await expect(rows.nth(0)).toContainText(/tons?/)
    await expect(rows.nth(1)).toContainText(SECOND_FLEET)
    await expect(rows.nth(1).locator('[data-tone]')).toHaveAttribute('data-tone', 'danger')
    // Hung under the button, over the panes: its top is at the header's foot or below, and its
    // left edge is the button's.
    await page.screenshot({ path: test.info().outputPath('fleet-list-wide.png') })
    const listBox = await rect(page, '[data-testid="fleet-list"]')
    const pickerBox = await rect(page, '[data-testid="fleet-picker"]')
    expect(listBox!.y).toBeGreaterThanOrEqual(pickerBox!.y + pickerBox!.h)
    expect(Math.abs(listBox!.x - pickerBox!.x)).toBeLessThanOrEqual(1)
    expect(
      {
        header: await rect(page, '[data-testid="desk-header"]'),
        line: await rect(page, '[data-testid="command-line"]'),
        row: await rect(page, '[data-testid="watch-row"]'),
      },
      'opening the list moved the page',
    ).toEqual(before)

    // A PRESS ON A ROW SELECTS AND CLOSES. Segunda is now in hand: red dot, no alert (nobody else is
    // stuck), and the figures are hers.
    await rows.nth(1).click()
    await expect(list).toHaveCount(0)
    await expect(picker).toContainText(SECOND_FLEET)
    await expect(picker.getByTestId('fleet-picker-dot')).toHaveAttribute('data-tone', 'danger')
    await expect(picker.getByTestId('fleet-picker-alert')).toHaveCount(0)
    await expect(page.getByTestId('command-line')).toContainText('Cargo')

    // ESCAPE CLOSES; A PRESS OUTSIDE CLOSES.
    await picker.click()
    await expect(list).toBeVisible()
    await page.keyboard.press('Escape')
    await expect(list).toHaveCount(0)
    await picker.click()
    await expect(list).toBeVisible()
    await page.getByRole('heading', { name: 'Command', exact: true }).click()
    await expect(list).toHaveCount(0)

    // ← / → SWITCH, WRAPPING: Segunda → (right) Gaivota → (left) Segunda.
    await page.keyboard.press('ArrowRight')
    await expect(picker).toContainText('Gaivota')
    await page.keyboard.press('ArrowLeft')
    await expect(picker).toContainText(SECOND_FLEET)
    // …but not while typing: the search field keeps its arrows.
    const search = page.getByRole('textbox', { name: 'Search goods' })
    await search.click()
    await search.pressSequentially('co')
    await page.keyboard.press('ArrowRight')
    await page.keyboard.press('ArrowLeft')
    await expect(picker).toContainText(SECOND_FLEET)
  })

  test('phone: the same button opens the bottom tray, a row selects, and the figures under it do not move', async ({
    page,
    request,
    baseURL,
  }) => {
    await page.setViewportSize(PHONE)
    await openDesk(page, request, baseURL)
    const picker = page.getByTestId('fleet-picker')
    await expect(picker).toHaveAttribute('data-fleets', '2')
    await expect(picker).toContainText('Gaivota')
    await expect(picker.getByTestId('fleet-picker-alert')).toHaveAttribute('data-tone', 'danger')

    const before = {
      header: await rect(page, '[data-testid="sheet-header"]'),
      picker: await rect(page, '[data-testid="fleet-picker"]'),
      line: await rect(page, '[data-testid="command-line"]'),
      faces: await rect(page, '[role="tablist"][aria-label="Desk faces"]'),
    }
    await picker.click()
    const tray = page.getByTestId('fleet-list')
    await expect(tray).toBeVisible()
    await expect(tray).toHaveAttribute('data-tray-mode', 'docked')
    const rows = tray.getByTestId('fleet-row')
    await expect(rows).toHaveCount(2)
    await page.waitForTimeout(400)
    await page.screenshot({ path: test.info().outputPath('fleet-list-phone.png') })
    expect(
      {
        header: await rect(page, '[data-testid="sheet-header"]'),
        picker: await rect(page, '[data-testid="fleet-picker"]'),
        line: await rect(page, '[data-testid="command-line"]'),
        faces: await rect(page, '[role="tablist"][aria-label="Desk faces"]'),
      },
      'the tray moved the sheet',
    ).toEqual(before)
    const trayBox = await rect(page, '[data-testid="fleet-list"]')
    expect(trayBox!.y + trayBox!.h, 'the tray is not docked at the bottom edge').toBeGreaterThanOrEqual(PHONE.height - 1)

    await rows.nth(1).click()
    await expect(tray).toHaveCount(0)
    await expect(picker).toContainText(SECOND_FLEET)
    await expect(picker.getByTestId('fleet-picker-dot')).toHaveAttribute('data-tone', 'danger')
    await expect(picker.getByTestId('fleet-picker-alert')).toHaveCount(0)
    expect(await rect(page, '[data-testid="command-line"]'), 'the pick moved the figures').toEqual(before.line)
  })
})
