import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { closeTop, openMarket, openPlate, tradeOnDesk } from './desk.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// NOTHING WAS LOST — every act PORT carried, reached from HQ (docs/COMMAND_DESK.md §2.2, slice D8; H3 `desk-into-hq`, 2026-11-24)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-17: *"delete port tab, and focus on command tab"*. PORT is gone, and since H3 the Trade desk and the
// Office are gone too: this sweep walks §2.2's verb map on HQ, at the phone and the desktop, on a local build (a fresh company
// docked at Lisbon), and requires each act's doorway to stand where the map says — and the ones a fresh company can afford, to RUN:
//
//   Trade · Buy                 Market plate, a card's Buy → the trade sheet over HQ → Buy              RUNS
//   Trade · Sell                Market plate › Sell, the good on board → the sheet on Sell              opens
//   Trade · Requests            Market plate › Requests                                                 opens
//   Town Hall · Invest          the City hall plate; HQ's Invest door → the same hall                   opens
//   Storage                     Production plate — the cargo bought above stands in Cargo               opens
//   Craft · Build · Repair ·    Port plate › Craft / Build / Repair / Skills; Inn plate › crew,         opens
//   Skills · Inn (hire)         where Lisbon has them
//   Old /port links             land on HQ                                                              opens
// (Resupply's own row on the quay went with the Office's market tray: a voyage buys its stores at departure, 0454.)
//
// The nav has no Port cell (nav.geometry.spec pins the cells).

const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const

for (const size of SIZES) {
  test.describe(`every former PORT act from HQ at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the sweep', async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      // An old /port link opens HQ.
      await page.goto('port')
      // The first tray's reads are waited on below: not across a drift-slot edge (appReady.fixture DRIFT_SLOT_MS).
      await ready(page, { quietMs: 90_000 })
      await expect(page).toHaveURL(/\/city$/)
      await expect(page.getByTestId('city-screen')).toBeVisible()
      // (the bar: HQ's own row of plates carries a Port plate, which is the harbour's building, not a tab)
      await expect(page.getByTestId('nav-bar').getByText('Port', { exact: true })).toHaveCount(0)

      // Trade · Buy — runs: a card's Buy opens the trade sheet over HQ on that good, and the buy runs there
      await openMarket(page)
      const list = page.getByTestId('city-market-buy')
      const card = list.locator('[data-testid="trade-good"]:has([data-testid="trade-buy"]:not([disabled]))').first()
      await expect(card).toBeVisible({ timeout: 120_000 })
      const code = (await card.getAttribute('data-good'))!
      const cargo = list.locator(`[data-testid="trade-good"][data-good="${code}"]`).getByTestId('trade-good-aboard')
      const before = await cargo.innerText()
      await card.getByTestId('trade-buy').click()
      await tradeOnDesk(page)
      await expect.poll(async () => cargo.innerText(), { timeout: 60_000 }).not.toBe(before)
      await page.goBack()
      await expect(page.getByTestId('good-detail')).toHaveCount(0)
      await expect(page.getByTestId('city-screen')).toBeVisible({ timeout: 30_000 })

      // Trade · Sell — the good now on board: its Sell opens THE trade sheet on Sell over HQ, the URL unmoved (S1, src/app/HqSheet.tsx);
      // the browser's back closes it
      const url = page.url()
      await page.getByRole('tablist', { name: 'Market' }).getByRole('tab', { name: 'Sell', exact: true }).click()
      await page.locator(`[data-testid="city-market-sell"] [data-testid="trade-good"][data-good="${code}"]`).getByTestId('trade-sell').click()
      await expect(page.getByTestId('good-detail')).toHaveAttribute('data-side', 'sell', { timeout: 30_000 })
      expect(page.url(), 'the Sell left HQ').toBe(url)
      await expect(page.getByTestId('trade-act')).toHaveAttribute('data-act', 'sell', { timeout: 30_000 })
      await page.goBack()
      await expect(page.getByTestId('good-detail')).toHaveCount(0)
      await expect(page.getByTestId('city-screen')).toBeVisible({ timeout: 30_000 })

      // Trade · Requests
      await page.getByRole('tablist', { name: 'Market' }).getByRole('tab', { name: 'Requests', exact: true }).click()
      await expect(page.getByTestId('city-face-panel')).not.toBeEmpty()
      await expect(page.getByTestId('city-market-sell')).toHaveCount(0)
      await page.getByRole('tablist', { name: 'Market' }).getByRole('tab', { name: 'Buy', exact: true }).click()

      // the buildings Lisbon has: the Port plate's doors, each to its own page or sheet
      await openPlate(page, 'port')
      const doors: Record<string, [string, string]> = {
        Craft: ['city-port-craft', 'port-workstation'],
        Build: ['city-port-yard', 'port-yard'],
        Repair: ['city-port-repair', 'port-shipyard'],
        Skills: ['city-port-skills', 'port-academy'],
      }
      const reached: string[] = []
      for (const [name, [door, id]] of Object.entries(doors)) {
        if ((await page.getByTestId(door).count()) === 0) continue
        await page.getByTestId(door).click()
        await expect(page.getByTestId(id), `Port › ${name}`).toBeVisible({ timeout: 30_000 })
        await closeTop(page)
        await expect(page.getByTestId(id)).toHaveCount(0)
        reached.push(name)
      }
      // Town: the City hall plate carries the Town Hall
      await openPlate(page, 'hall')
      await expect(page.getByTestId('city-hall-figures')).toBeVisible({ timeout: 30_000 })
      reached.push('Town')
      // Production: what was just bought stands in Cargo, to put in storage (owner, 2026-11-06)
      await openPlate(page, 'production')
      await expect(page.getByTestId('port-production')).toBeVisible({ timeout: 30_000 })
      if (size.width < 1024) await page.getByTestId('port-production').getByRole('tab', { name: 'Cargo', exact: true }).click()
      await expect(page.getByTestId('cargo-row').first()).toBeVisible({ timeout: 30_000 })
      // Inn: hire crew
      await openPlate(page, 'inn')
      await page.getByTestId('city-inn-crew').click()
      await expect(page.getByTestId('city-inn-page')).toBeVisible({ timeout: 30_000 })
      await expect(page.getByTestId('inn-crew')).toBeVisible({ timeout: 30_000 })
      await closeTop(page)
      reached.push('Inn')
      console.log(`@${size.width}: reached ${['Market', ...reached].join(', ')}`)
      expect(reached).toEqual(expect.arrayContaining(['Town', 'Inn', 'Build']))

      // Invest — HQ's door, the same Town Hall
      await page.getByTestId('city-office-invest').click()
      await expect(page.getByTestId('invest-hall')).toBeVisible({ timeout: 30_000 })
      await closeTop(page)

      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
      await page.screenshot({ path: test.info().outputPath(`sweep-${size.width}.png`) })
    })
  })
}
