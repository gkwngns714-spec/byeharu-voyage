import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { openMarket } from './desk.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADE LIST, MEASURED (docs/COMMAND_DESK.md §5.5–5.7, slice D3) — at the phone (390×844) and
// the desktop (1440×900), on a local build. Since H3 (2026-11-24) the list is HQ's Market plate (the Trade desk is gone):
//   · a Trade card (the docked city's goods) stands taller than the old 52-px row, and every control on the desk clears 44 px;
//   · the page never scrolls sideways;
//   · A PRESS SELECTS (the owner's law): pressing a good's Buy opens THE trade sheet over HQ and moves no card;
//   · closing it returns to the cards, still where they were.
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
  await page.goto('city')
  await ready(page)
  await openMarket(page)
  await expect(page.locator(CARD).first()).toBeVisible({ timeout: 120_000 })
  // the cards stand under the chips: the first row is brought onto the glass, so a press on it scrolls nothing
  await page.locator(CARD).nth(1).getByTestId('trade-buy').scrollIntoViewIfNeeded()
}

const CARD = '[data-testid="city-market-buy"] [data-testid="trade-good"]'

const tops = (page: Page, sel: string) =>
  page.evaluate((s) => [...document.querySelectorAll(s)].slice(0, 8).map((e) => Math.round(e.getBoundingClientRect().top)), sel)

for (const size of SIZES) {
  test.describe(`the trade list at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('Trade: a card taller than 52 px, 44-px controls, no sideways scroll', async ({ page, request, baseURL }) => {
      await openDesk(page, request, baseURL)
      const m = await page.evaluate(() => {
        const desk = document.querySelector('[data-testid="city-face-panel"]')!
        const rows = [...document.querySelectorAll('[data-testid="city-market-buy"] [data-testid="trade-good"]')].slice(0, 12)
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
      expect(m.small, 'a control on the Market plate is under 44 px').toEqual([])
      expect(m.scrollW).toBeLessThanOrEqual(m.clientW)
    })

    test('a press opens the good in its own place; the rows above it do not move', async ({ page, request, baseURL }) => {
      await openDesk(page, request, baseURL)
      await page.waitForTimeout(800)
      const before = await tops(page, CARD)
      await page.locator(CARD).nth(1).getByTestId('trade-buy').click()
      await expect(page.getByTestId('good-detail')).toBeVisible()
      await page.waitForTimeout(300)
      const after = await tops(page, CARD)
      // owner row 229: the panel stands at the side (wide) or rises as the bottom sheet (phone) — no card moves
      expect(after, 'opening a good moved the cards').toEqual(before)

      // its one button; closing the panel returns to the cards, still where they were
      await expect(page.getByTestId('trade-act')).toBeVisible({ timeout: 30_000 })
      await page.getByTestId('good-detail').getByRole('button', { name: /close/i }).first().click()
      await expect(page.getByTestId('good-detail')).toHaveCount(0)
      expect(await tops(page, CARD), 'closing the panel moved the cards').toEqual(before)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
