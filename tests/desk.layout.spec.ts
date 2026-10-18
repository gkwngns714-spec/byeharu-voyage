import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COMMAND DESK, MEASURED (docs/COMMAND_DESK.md §5.5–5.7, slice D3) — at the phone (390×844) and
// the desktop (1440×900), on a local build:
//   · a Markets row is the 52-px row, and every control on the desk clears 44 px;
//   · the page never scrolls sideways;
//   · A PRESS SELECTS (the owner's law): pressing a good opens its page in its own slot and moves no
//     row of the list; pressing a chart city changes the chart in place and moves nothing below it;
//   · the page's Buy cell (docked here) turns the slot over to THE trade tray, and closing it returns
//     to the page.
// Prices are the local world's; nothing here asserts a figure — only geometry and the slot's turns.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const

async function openDesk(page: Page, request: Parameters<typeof reachable>[0], baseURL: string | undefined) {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('command')
  await ready(page)
  await expect(page.getByTestId('watch-row').first()).toBeVisible({ timeout: 120_000 })
}

const tops = (page: Page, sel: string) =>
  page.evaluate((s) => [...document.querySelectorAll(s)].slice(0, 8).map((e) => Math.round(e.getBoundingClientRect().top)), sel)

for (const size of SIZES) {
  test.describe(`COMMAND desk at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('Markets: 52-px rows, 44-px controls, no sideways scroll', async ({ page, request, baseURL }) => {
      await openDesk(page, request, baseURL)
      const m = await page.evaluate(() => {
        const desk = document.querySelector('[data-testid="command"]')!
        const rows = [...document.querySelectorAll('[data-testid="watch-row"]')].slice(0, 12)
        const controls = [...desk.querySelectorAll('button, input, [role="tab"]')].filter((e) => {
          const r = e.getBoundingClientRect()
          return r.width > 0 && r.height > 0 && r.top < window.innerHeight
        })
        return {
          rowHeights: rows.map((r) => Math.round(r.getBoundingClientRect().height)),
          small: controls
            .map((e) => ({ t: (e.textContent ?? e.getAttribute('aria-label') ?? '').trim().slice(0, 24), h: Math.round(e.getBoundingClientRect().height) }))
            .filter((c) => c.h < 44),
          scrollW: document.documentElement.scrollWidth,
          clientW: document.documentElement.clientWidth,
        }
      })
      expect(m.rowHeights.length).toBeGreaterThan(5)
      for (const h of m.rowHeights) expect(h).toBeGreaterThanOrEqual(52)
      expect(m.small, 'a control on the desk is under 44 px').toEqual([])
      expect(m.scrollW).toBeLessThanOrEqual(m.clientW)
    })

    test('a press opens the good in its own slot; the list and the page do not move', async ({ page, request, baseURL }) => {
      await openDesk(page, request, baseURL)
      // A good the docked city sells, so the page offers Buy here.
      await page.getByRole('button', { name: 'Here', exact: true }).click()
      await page.waitForTimeout(800)
      const before = await tops(page, '[data-testid="watch-row"]')
      await page.getByTestId('watch-row').nth(1).click()
      await expect(page.getByTestId('good-page')).toBeVisible()
      await page.waitForTimeout(300)
      expect(await tops(page, '[data-testid="watch-row"]'), 'opening a good moved the list').toEqual(before)

      // The board lands (skeletons first, at their final height), then the rows.
      await expect(page.getByTestId('sell-row').first()).toBeVisible({ timeout: 60_000 })
      await expect(page.getByTestId('price-chart-estimate')).toBeVisible({ timeout: 60_000 })

      // A chart city pressed: the chart changes in place, nothing below it moves.
      const chips = page.getByRole('group', { name: 'Chart city' }).getByRole('button')
      if ((await chips.count()) > 1) {
        const buyTop = await page.getByTestId('buy-at').evaluate((e) => Math.round(e.getBoundingClientRect().top))
        await chips.first().click()
        await page.waitForTimeout(600)
        const after = await page.getByTestId('buy-at').evaluate((e) => Math.round(e.getBoundingClientRect().top))
        expect(after, 'pressing a chart city moved what is under the chart').toBe(buyTop)
      }

      // Buy, here: the slot turns over to the trade tray, and closing it returns to the page.
      await page.getByTestId('desk-buy').click()
      await expect(page.getByTestId('trade-tray')).toBeVisible({ timeout: 30_000 })
      await expect(page.getByTestId('good-page')).toHaveCount(0)
      await page.getByTestId('trade-tray').getByRole('button', { name: /close/i }).first().click()
      await expect(page.getByTestId('good-page')).toBeVisible()
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
