import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COMMAND DESK, MEASURED (docs/COMMAND_DESK.md §5.5–5.7, slice D3) — at the phone (390×844) and
// the desktop (1440×900), on a local build:
//   · a Trade card (the docked city's goods) stands taller than the old 52-px row, and every control on the desk clears 44 px;
//   · the page never scrolls sideways;
//   · A PRESS SELECTS (the owner's law): pressing a good's Buy opens its page — under the card on a phone, in the centre
//     pane on a wide glass — and moves no card at or above the one pressed;
//   · the page's Trade (docked here) opens THE trade tray, and closing it returns to the page.
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
  await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
}

const tops = (page: Page, sel: string) =>
  page.evaluate((s) => [...document.querySelectorAll(s)].slice(0, 8).map((e) => Math.round(e.getBoundingClientRect().top)), sel)

for (const size of SIZES) {
  test.describe(`COMMAND desk at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('Trade: a card taller than 52 px, 44-px controls, no sideways scroll', async ({ page, request, baseURL }) => {
      await openDesk(page, request, baseURL)
      const m = await page.evaluate(() => {
        const desk = document.querySelector('[data-testid="command"]')!
        const rows = [...document.querySelectorAll('[data-testid="trade-good"]')].slice(0, 12)
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

    test('a press opens the good in its own place; the rows above it do not move', async ({ page, request, baseURL }) => {
      await openDesk(page, request, baseURL)
      await page.waitForTimeout(800)
      const before = await tops(page, '[data-testid="trade-good"]')
      await page.getByTestId('trade-buy').nth(1).click()
      await expect(page.getByTestId('good-detail')).toBeVisible()
      await page.waitForTimeout(300)
      const after = await tops(page, '[data-testid="trade-good"]')
      // owner row 229: the panel stands in the right pane (wide) or rises as the bottom sheet (phone) — no card moves
      expect(after, 'opening a good moved the cards').toEqual(before)

      // its one button; closing the panel returns to the cards, still where they were
      await expect(page.getByTestId('trade-act')).toBeVisible({ timeout: 30_000 })
      await page.getByTestId('good-detail').getByRole('button', { name: /close/i }).first().click()
      await expect(page.getByTestId('good-detail')).toHaveCount(0)
      expect(await tops(page, '[data-testid="trade-good"]'), 'closing the panel moved the cards').toEqual(before)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })

    // A CARD'S HEIGHT IS THE DATA'S (a best sale's city or its hours run a second line: 165, 174, 190 px seen), so the test above
    // passes or fails by which sale the world happens to show. This one plants its own tall card: 30 px more above the buttons.
    // The phone's pane holds one whole row, measured, so the row's Buy still stands inside it and a press moves nothing
    // (run 44507902138: the pane was a fixed 168 px, the card 190, the press scrolled the cards 6 px).
    test('a tall card: its Buy stands inside the pane, and a press still moves no card', async ({ page, request, baseURL }) => {
      await openDesk(page, request, baseURL)
      await page.addStyleTag({ content: '[data-testid="trade-good"] { padding-top: 30px !important }' })
      await page.waitForTimeout(800)
      const before = await tops(page, '[data-testid="trade-good"]')
      const pane = await page.evaluate(() => {
        const p = document.querySelector('[data-testid="trade-board"] [data-scroll-pane]')!.getBoundingClientRect()
        const b = document.querySelector('[data-testid="trade-buy"]')!.getBoundingClientRect()
        return { paneBottom: p.bottom, buyBottom: b.bottom }
      })
      expect(pane.buyBottom, 'the first row Buy stands under the pane edge').toBeLessThanOrEqual(pane.paneBottom)
      await page.getByTestId('trade-buy').nth(1).click()
      await expect(page.getByTestId('good-detail')).toBeVisible()
      await page.waitForTimeout(300)
      expect(await tops(page, '[data-testid="trade-good"]'), 'a press moved the cards').toEqual(before)
    })
  })
}
