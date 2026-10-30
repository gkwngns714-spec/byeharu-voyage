import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// NOTHING WAS LOST — every act PORT carried, reached from COMMAND (docs/COMMAND_DESK.md §2.2, slice D8)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-17: *"delete port tab, and focus on command tab"*. PORT is gone; this sweep walks §2.2's
// verb map on the desk, at the phone and the desktop, on a local build (a fresh company docked at Lisbon), and
// requires each act's doorway to stand where the map says — and the ones a fresh company can afford, to RUN:
//
//   Trade · Buy                 City › Trade, a buy cell → the trade tray → Buy (cargo rises)         RUNS
//   Trade · Sell                City › Trade › Sell, the good on board → the tray says Sell            opens
//   Trade · bargain, basket     the tray's Bargain row and its Add to basket                           opens
//   Trade · Requests            City › Trade › Requests                                                 opens
//   Trade · Resupply            City › Trade's Supplies row → the step tray                            opens
//   Town · Town Hall · Invest   City › Town → the Town Hall; the desk's Invest face → the same hall    opens
//   Storage                     City › Storage — Put in storage on the cargo bought above              opens
//   Craft · Build · Repair ·    City › Craft / Build / Repair / Skills / Inn, where Lisbon has them    opens
//   Skills · Inn (hire)
//   Trade from the desk         Trade › a good's Buy → the same trade tray                             opens
//   (owner 2026-10-30: Buy and Sell are one Trade face; the mini map and its cross-city picks are gone)
//   Old /port links             land on COMMAND · City                                                  opens
//
// The nav has no Port cell (nav.geometry.spec pins the four).

const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const

async function face(page: Page, name: string) {
  await page.getByRole('tablist', { name: 'City buildings' }).getByRole('tab', { name, exact: true }).click()
  await page.waitForTimeout(400)
}

for (const size of SIZES) {
  test.describe(`every former PORT act from COMMAND at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the sweep', async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      // An old /port link opens the desk's City face.
      await page.goto('port')
      // The first tray's reads are waited on below: not across a drift-slot edge (appReady.fixture DRIFT_SLOT_MS).
      await ready(page, { quietMs: 90_000 })
      await expect(page).toHaveURL(/\/command$/)
      await expect(page.getByTestId('desk-city')).toBeVisible()
      await expect(page.getByRole('navigation').getByText('Port', { exact: true })).toHaveCount(0)

      // Trade · Buy — runs
      await face(page, 'Trade')
      const cargo = page.getByTestId('command-line')
      const before = await cargo.innerText()
      await page.locator('[data-testid="trade-row"] button:enabled').first().click()
      const tray = page.getByTestId('trade-tray')
      await expect(tray).toBeVisible()
      // bargain and basket stand in the same tray
      await expect(tray.getByTestId('haggle-row')).toBeVisible({ timeout: 30_000 })
      await expect(tray.getByTestId('trade-tray-stage')).toBeVisible()
      await expect(tray.getByTestId('trade-tray-send')).toBeEnabled({ timeout: 30_000 })
      await tray.getByTestId('trade-tray-send').click()
      await expect.poll(async () => cargo.innerText(), { timeout: 60_000 }).not.toBe(before)
      // the issued trade closes its tray (on a wide glass the slot returns to the basket)
      await expect(page.getByTestId('trade-tray')).toHaveCount(0, { timeout: 60_000 })

      // Trade · Sell — the good now on board offers its sell tray
      await page.getByRole('tablist', { name: 'Trade faces' }).getByRole('tab', { name: 'Sell', exact: true }).click()
      await page.locator('[data-testid="trade-row"] button:enabled').last().click()
      await expect(page.getByTestId('trade-tray-send')).toHaveText(/^Sell /, { timeout: 30_000 })
      await page.getByTestId('trade-tray').getByRole('button', { name: 'Close' }).first().click()

      // Trade · Requests
      await page.getByRole('tab', { name: 'Requests', exact: true }).click()
      await expect(page.getByTestId('desk-city').getByRole('tabpanel')).not.toBeEmpty()
      await page.getByRole('tablist', { name: 'Trade faces' }).getByRole('tab', { name: 'Buy', exact: true }).click()

      // Trade · Resupply
      await page.getByTestId('quay-stores').click()
      await expect(page.getByTestId('step-tray')).toBeVisible({ timeout: 30_000 })
      await page.getByTestId('step-tray').getByRole('button', { name: 'Close' }).first().click()

      // the buildings Lisbon has
      const names = await page.getByRole('tablist', { name: 'City buildings' }).getByRole('tab').allInnerTexts()
      const ids: Record<string, string> = {
        Town: 'desk-town-hall',
        Storage: 'port-storage',
        Craft: 'port-workstation',
        Inn: 'port-inn',
        Build: 'port-yard',
        Repair: 'port-shipyard',
        Skills: 'port-academy',
      }
      const reached: string[] = []
      for (const [name, id] of Object.entries(ids)) {
        if (!names.includes(name)) continue
        await face(page, name)
        await expect(page.getByTestId(id), `City › ${name}`).toBeVisible({ timeout: 30_000 })
        reached.push(name)
      }
      console.log(`@${size.width}: reached ${['Trade', ...reached].join(', ')} of ${names.join(', ')}`)
      expect(reached).toEqual(expect.arrayContaining(['Town', 'Storage', 'Inn']))
      // Storage: what was just bought can be put in storage
      await face(page, 'Storage')
      await expect(page.getByTestId('storage-row').first()).toBeVisible({ timeout: 30_000 })
      // Inn: hire crew
      await face(page, 'Inn')
      await expect(page.getByTestId('inn-crew')).toBeVisible({ timeout: 30_000 })

      // Invest — the desk's face, the same Town Hall
      await page.getByRole('tab', { name: 'Invest', exact: true }).click()
      await expect(page.getByTestId('invest-hall')).toBeVisible({ timeout: 30_000 })

      // Trade — the docked city's goods as priced cards, and its Buy button in the trade panel (owner 2026-10-30)
      await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Trade', exact: true }).click()
      const tradeFace = page.getByTestId('desk-trade')
      await tradeFace.getByTestId('trade-buy').first().click()
      await expect(page.getByTestId('good-detail-price')).toContainText(/\d/, { timeout: 60_000 })
      await expect(page.getByTestId('trade-act')).toHaveAttribute('data-act', 'buy', { timeout: 30_000 })

      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
      await page.screenshot({ path: test.info().outputPath(`sweep-${size.width}.png`) })
    })
  })
}
