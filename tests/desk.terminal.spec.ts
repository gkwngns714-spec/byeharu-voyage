import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADING TERMINAL, MEASURED (docs/COMMAND_DESK.md §3.9, 2026-10-18; Buy and Sell became ONE Trade face
// with owner 2026-10-30). The owner's own glass is 1440×731; the phone is 390×844.
//   · WIDE: the three panes (the orders · the docked city's goods · the panel) stand side by side and use the
//     glass; the page never scrolls sideways;
//   · A PRESS SELECTS: pressing a good's Buy opens its page in the right pane — no pane moves, no card moves;
//   · PHONE: no sideways scroll; the good's page opens under the board, the chart in it;
//   · at 1280, 1440 and 390 no good's name or figure is cut in its card.
// Prices are the local world's; nothing here asserts a figure — only geometry and presence.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

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

const box = (page: Page, id: string) =>
  page.getByTestId(id).first().evaluate((e) => {
    const r = e.getBoundingClientRect()
    return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), bottom: Math.round(r.bottom) }
  })

test.describe('the terminal at 1440×731 (the owner\'s glass)', () => {
  test.use({ viewport: { width: 1440, height: 731 } })

  test('three panes across the glass', async ({ page, request, baseURL }) => {
    await openDesk(page, request, baseURL)
    await expect(page.getByTestId('desk-trade')).toBeVisible()
    const list = await box(page, 'desk-pane-list')
    const chart = await box(page, 'desk-pane-chart')
    const ticket = await box(page, 'desk-pane-ticket')
    expect(list.x + list.w, 'the list and the centre overlap').toBeLessThanOrEqual(chart.x + 1)
    expect(chart.x + chart.w, 'the centre and the orders overlap').toBeLessThanOrEqual(ticket.x + 1)
    expect(ticket.x + ticket.w, 'the orders do not reach the right edge').toBeGreaterThanOrEqual(1440 - 2)
    expect(list.x, 'the list does not start at the left edge').toBeLessThanOrEqual(2)
    expect(chart.w, 'the centre pane is not the widest').toBeGreaterThan(Math.max(list.w, ticket.w))
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
  })

  test('a press selects: the good opens in the right pane, nothing moves', async ({ page, request, baseURL }) => {
    await openDesk(page, request, baseURL)
    const rows = () =>
      page.evaluate(() => [...document.querySelectorAll('[data-testid="trade-good"]')].slice(0, 10).map((e) => Math.round(e.getBoundingClientRect().top)))
    const panes = async () => [await box(page, 'desk-pane-list'), await box(page, 'desk-pane-chart'), await box(page, 'desk-pane-ticket')]
    // THE LIST SETTLES BEFORE THE PRESS IS MEASURED. The desk's cards grow 121 → 129 px as the
    // served market read lands; measuring the press across that arrival reported "a press moved the
    // list" while the press had moved nothing (measured 2026-10-31 on b14ae1c6: with the read
    // settled, the before/after rects are identical). The law is about the PRESS, so wait for the
    // list to stop changing and then compare.
    const settled = async () => {
      let prev = await rows()
      for (let i = 0; i < 40; i++) {
        await page.waitForTimeout(150)
        const next = await rows()
        if (JSON.stringify(next) === JSON.stringify(prev)) return next
        prev = next
      }
      return prev
    }
    const rowsBefore = await settled()
    const before = await panes()
    await page.getByTestId('trade-buy').nth(2).click()
    // owner row 229: the cards in the centre, the trade panel on the right
    await expect(page.getByTestId('desk-pane-ticket').getByTestId('good-detail')).toBeVisible()
    await expect(page.getByTestId('price-chart').or(page.getByTestId('trend-empty'))).toBeVisible({ timeout: 60_000 })
    await page.waitForTimeout(400)
    expect(await panes(), 'a press moved a pane').toEqual(before)
    expect(await rows(), 'a press moved the list').toEqual(rowsBefore)
  })
})

test.describe('the desk at 390×844', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('no sideways scroll; the good opens as the bottom sheet, the chart in it', async ({ page, request, baseURL }) => {
    await openDesk(page, request, baseURL)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    await page.getByTestId('trade-buy').first().click()
    const detail = page.getByTestId('good-detail')
    await expect(detail).toBeVisible()
    await expect(detail.getByTestId('trend-row')).toBeVisible()
    // owner row 229: a bottom sheet at the phone's bottom edge, the one button in it
    await expect(detail).toHaveAttribute('data-tray-mode', 'docked')
    await expect(page.getByTestId('trade-act')).toBeVisible()
    const d = await box(page, 'good-detail')
    expect(d.bottom, 'the sheet does not stand at the bottom edge').toBeGreaterThanOrEqual(844 - 120)
    expect(d.x).toBeGreaterThanOrEqual(0)
    expect(d.x + d.w).toBeLessThanOrEqual(390)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 2026-10-19, ON THE OWNER'S 1280×707 GLASS: figures were drawn over each other and names truncated to
// "Abalone …". Measured at 1280, 1440 and 390 on the Trade face's cards (a card per good).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
for (const size of [
  { width: 1280, height: 707 },
  { width: 1440, height: 731 },
  { width: 390, height: 844 },
]) {
  test.describe(`the city's goods at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('names are whole; figures are not cut', async ({ page, request, baseURL }) => {
      await openDesk(page, request, baseURL)
      const m = await page.evaluate(() => {
        const rows = [...document.querySelectorAll('[data-testid="trade-good"]')].slice(0, 12)
        const clipped: string[] = []
        for (const row of rows) {
          for (const cell of row.querySelectorAll<HTMLElement>('[data-testid="trade-good-name"], [data-testid="trade-good-buy"], [data-testid="trade-good-sell"], [data-testid="trade-good-aboard"]')) {
            if (cell.scrollWidth > cell.clientWidth + 1) clipped.push(row.getAttribute('data-good') ?? '?')
          }
        }
        return { n: rows.length, clipped: [...new Set(clipped)], scroll: document.documentElement.scrollWidth <= document.documentElement.clientWidth }
      })
      expect(m.n).toBeGreaterThan(5)
      expect(m.clipped, 'a name or figure is cut').toEqual([])
      expect(m.scroll).toBe(true)
    })
  })
}
