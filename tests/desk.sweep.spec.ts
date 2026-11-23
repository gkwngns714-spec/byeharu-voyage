import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { tradeOnDesk } from './desk.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// NOTHING WAS LOST — every act PORT carried, reached from COMMAND (docs/COMMAND_DESK.md §2.2, slice D8)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-17: *"delete port tab, and focus on command tab"*. PORT is gone; this sweep walks §2.2's
// verb map on the desk, at the phone and the desktop, on a local build (a fresh company docked at Lisbon), and
// requires each act's doorway to stand where the map says — and the ones a fresh company can afford, to RUN:
//
//   Trade · Buy                 City › Market, a buy cell → the Trade desk on that good → Buy (X1)    RUNS
//   Trade · Sell                City › Market › Sell, the good on board → the desk on Sell (X1)        opens
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
      // An old /port link opens the Office's City face.
      await page.goto('port')
      // The first tray's reads are waited on below: not across a drift-slot edge (appReady.fixture DRIFT_SLOT_MS).
      await ready(page, { quietMs: 90_000 })
      await expect(page).toHaveURL(/\/office$/)
      await expect(page.getByTestId('desk-city')).toBeVisible()
      await expect(page.getByRole('navigation').getByText('Port', { exact: true })).toHaveCount(0)

      // Trade · Buy — runs. X1 (src/live/tradeOnDesk.ts): the Market face's price opens the Trade desk on that good, and the buy runs
      // there (the bargain and the basket were the Market face's own tray; they return with TRADE_ON_DESK false)
      await face(page, 'Market')
      const cargo = page.getByTestId('command-line')
      const before = await cargo.innerText()
      await page.locator('[data-testid="trade-row"] button:enabled').first().click()
      await tradeOnDesk(page)
      await expect.poll(async () => cargo.innerText(), { timeout: 60_000 }).not.toBe(before)
      await page.goBack()
      await expect(page.getByTestId('desk-city')).toBeVisible({ timeout: 30_000 })

      // Trade · Sell — the good now on board: its Sell opens the desk on Sell
      await page.getByRole('tablist', { name: 'Trade faces' }).getByRole('tab', { name: 'Sell', exact: true }).click()
      await page.locator('[data-testid="trade-row"] button:enabled').last().click()
      await expect(page).toHaveURL(/\/command$/, { timeout: 30_000 })
      await expect(page.getByTestId('trade-act')).toHaveAttribute('data-act', 'sell', { timeout: 30_000 })
      await page.goBack()
      await expect(page.getByTestId('desk-city')).toBeVisible({ timeout: 30_000 })

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
      console.log(`@${size.width}: reached ${['Market', ...reached].join(', ')} of ${names.join(', ')}`)
      expect(reached).toEqual(expect.arrayContaining(['Town', 'Inn']))
      // Production: the tab goes to the HQ's page, and what was just bought stands in Cargo, to put in storage (owner, 2026-11-06)
      await face(page, 'Production')
      await expect(page.getByTestId('port-production')).toBeVisible({ timeout: 30_000 })
      if (size.width < 1024) await page.getByTestId('port-production').getByRole('tab', { name: 'Cargo', exact: true }).click()
      await expect(page.getByTestId('cargo-row').first()).toBeVisible({ timeout: 30_000 })
      await page.goBack()
      await expect(page.getByTestId('desk-city')).toBeVisible({ timeout: 30_000 })
      // Inn: hire crew
      await face(page, 'Inn')
      await expect(page.getByTestId('inn-crew')).toBeVisible({ timeout: 30_000 })

      // Invest — the Office's face, the same Town Hall
      await page.getByRole('tab', { name: 'Invest', exact: true }).click()
      await expect(page.getByTestId('invest-hall')).toBeVisible({ timeout: 30_000 })

      // Trade — its own tab: the docked city's goods as priced cards, and its Buy button in the trade panel (owner 2026-10-30)
      await page.locator('a[href$="/command"]:visible').first().click()
      const tradeFace = page.getByTestId('desk-trade')
      // X1 (slice 3, #817): the desk keeps the good last handed to it (store/deskGood.ts), so it opens on the good the Sell above
      // handed over; on a phone that good's sheet may stand over the cards, and its ✕ lets go of it before a card's Buy is pressed
      await expect(tradeFace.getByTestId('trade-buy').first()).toBeVisible({ timeout: 60_000 })
      await page.waitForTimeout(1_000)
      const held = page.getByRole('dialog')
      if ((await held.count()) > 0) {
        await held.first().getByRole('button', { name: 'Close', exact: true }).click()
        await expect(held).toHaveCount(0)
      }
      await tradeFace.getByTestId('trade-buy').first().click()
      await expect(page.getByTestId('good-detail-price')).toContainText(/\d/, { timeout: 60_000 })
      await expect(page.getByTestId('trade-act')).toHaveAttribute('data-act', 'buy', { timeout: 30_000 })

      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
      await page.screenshot({ path: test.info().outputPath(`sweep-${size.width}.png`) })
    })
  })
}
