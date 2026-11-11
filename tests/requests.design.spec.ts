import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { openCityFace } from './desk.fixture'
import { tradeDict } from '../src/lib/i18n/dict/trade'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A REQUEST STANDS A DAY (owner, 2026-11-05, migration 0311; docs/dev-log/2026-11-05-city-requests.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   *"the request, for example cumana, soju, the +300 gold should be on top of the prices. for example soju sold at
//   1000 each would be 1300. get it?"* — *"and it should show quantity, and time."* — *"the bonus fee should be set
//   [...] if bonus of 1,000,000 is depleted, that request no longer stands"*
//
// Written first, red on the board that showed `+premium` beside nothing, then green. A row says ONE price each (the
// served sale price and the bonus as one figure, the market small under it), what the budget still pays for, what you
// hold, the bonus each and the budget left, and the time as a live countdown. Nothing re-flows on a tick and nothing
// runs sideways, on the glasses the page laws walk. The server's half is 0311's self-assert and tests/rpc.surface.spec.ts.

const GLASSES = [
  { width: 1280, height: 800 },
  { width: 390, height: 844 },
  { width: 320, height: 640 },
] as const

/** Every figure of the rows on screen, as served (`data-*`) and as printed. */
async function rowsOf(page: Page) {
  return page.locator('[data-testid="request-row"]').evaluateAll((rows) =>
    rows.map((r) => {
      const e = r as HTMLElement
      const text = (s: string) => (r.querySelector(`[data-testid="${s}"]`) as HTMLElement | null)?.innerText.replace(/\s+/g, ' ').trim() ?? ''
      return {
        h: e.getBoundingClientRect().height,
        each: Number(e.dataset.priceEach),
        sale: Number(e.dataset.salePrice),
        bonus: Number(e.dataset.bonus),
        name: (e.innerText.split('\n')[0] ?? '').trim(),
        cell: text('request-fulfil'),
        want: text('request-want'),
        budget: text('request-budget'),
        time: text('request-time'),
        past: [...r.querySelectorAll('*')].filter((x) => x.getBoundingClientRect().right > r.getBoundingClientRect().right + 1).length,
      }
    }),
  )
}

const seconds = (s: string) => {
  const m = /(\d+):(\d\d)(?::(\d\d))?/.exec(s)
  if (!m) return NaN
  return m[3] === undefined ? Number(m[1]) * 60 + Number(m[2]) : Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3])
}

for (const glass of GLASSES) {
  test.describe(`at ${glass.width}`, () => {
    test.use({ viewport: glass })

    test('a request reads one price each, quantity, held, budget and a live time', async ({ page, request, baseURL }) => {
      test.setTimeout(420_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await page.goto('command')
      await ready(page)
      await openCityFace(page)
      await page.getByRole('tablist', { name: 'Trade faces' }).getByRole('tab', { name: /^Requests$/ }).click()
      await expect(page.locator('[data-testid="request-row"]').first()).toBeVisible({ timeout: 30_000 })

      await expect.poll(async () => (await rowsOf(page)).length).toBeGreaterThan(0)
      const first = await rowsOf(page)
      for (const r of first) {
        // ONE figure, the two served prices on top of each other; the client's copy is the server's
        expect(r.each, 'the row serves no price each').toBeGreaterThan(0)
        expect(Math.abs(r.each - (r.sale + r.bonus)), 'price each is not the sale price plus the bonus').toBeLessThanOrEqual(0.011)
        expect(r.cell, 'the cell does not lead with one coin figure').toMatch(/^deliver\s+[\d,.]+\s🪙/i)
        expect(r.cell, 'the market is not small under the price').toMatch(/each · market [\d,.]+/)
        expect(r.cell, 'a sum sits beside the price').not.toMatch(/\+[\d,]+\s🪙/)
        expect(r.want, 'no quantity and no held figure').toMatch(/^Wanted [\d,]+ · Held [\d,]+$/)
        expect(r.budget, 'no bonus each and no budget left').toMatch(/^Bonus [\d,.]+ 🪙 each · [\d,]+ 🪙 left$/)
        expect(r.time, 'no live time').toMatch(/^Time left (\d+:)?\d+:\d\d$/)
        expect(r.past, 'something runs past its row').toBe(0)
      }

      // THE TIME IS LIVE, AND THE ROW HOLDS STILL UNDER IT
      await page.waitForTimeout(3_000)
      const later = await rowsOf(page)
      // The read winds new jobs onto a young board (0087), so the board may GROW under the wait: each
      // row we first saw is found again by its good and fixed bonus, and its clock has run down.
      expect(later.length).toBeGreaterThanOrEqual(first.length)
      for (const f of first) {
        const r = later.find((x) => x.name === f.name && x.bonus === f.bonus)
        expect(r, `"${f.name}" left the board`).toBeTruthy()
        expect(seconds(r!.time), 'the time did not count down').toBeLessThan(seconds(f.time))
        expect(r!.h, 'a tick re-flowed the row').toBe(f.h)
      }

      // NOTHING SCROLLS SIDEWAYS
      const widths = await page.evaluate(() => ({
        page: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        pane: (() => {
          const p = document.querySelector('[data-testid="request-row"]')?.closest('[data-scroll-pane]')
          return p ? p.scrollWidth - p.clientWidth : 0
        })(),
      }))
      expect(widths.page).toBeLessThanOrEqual(0)
      expect(widths.pane).toBeLessThanOrEqual(1)
    })
  })
}

test('Stats shows the bonus money, in the page, at a phone and a laptop', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.goto('stats')
  await ready(page)
  await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
  const card = page.getByTestId('stats-bonus')
  await expect(card).toBeVisible({ timeout: 60_000 })
  for (const word of ['Held now', 'Budget set', 'Paid out', 'Returned']) await expect(card).toContainText(word)
})

test('the new words stand in both tongues, 1-2 plain words each side of a figure', () => {
  for (const key of ['wantHeld', 'bonusLine', 'timeLeft', 'eachMarket', 'bonus', 'noneHeld', 'wanted'] as const) {
    expect(tradeDict.en[key], `no EN word ${key}`).toBeTruthy()
    expect(tradeDict.ko[key], `no KO word ${key}`).toBeTruthy()
  }
  expect(tradeDict.en.bonus).toBe('Bonus')
  expect(tradeDict.ko.bonus).toBe('보너스')
})
