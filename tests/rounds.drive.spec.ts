import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { corpWorld } from './corpWorld.fixture'
import { serveWorldImage } from './worldImage.fixture'

// ROUNDS, DRIVEN (0518 to 0534; owner R3, R5, R6, slide 5): on the Assign sheet a fleet takes COMBAT, EXPEDITION or TRADING. Combat: a sea, what a round costs (never
// a chance, no RUN), the stop, repeat or home. Her sheet: the rounds, the log, what she has, Come home. Expedition: the same; its artifacts given at the capital. On an
// image without the rounds it is skipped: the action is not drawn.

const OUT = process.env.ROUNDS_SHOTS ?? 'test-results/rounds'
const sideways = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)

for (const size of [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
])
  test(`Rounds @${size.width}: combat, its log, an expedition, its artifacts`, async ({ page, request, baseURL }) => {
    test.setTimeout(900_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    let asks = 0
    page.on('console', (m) => {
      if (m.type() === 'debug' && m.text().includes('world.rounds(')) asks++
    })
    await serveWorldImage(page, await corpWorld({ courses: true, rounds: true }))
    await page.setViewportSize(size)
    await page.goto('city')
    await ready(page)
    const hers = page.locator('[data-testid="corp-worker"][data-kind="fleet"]').first()
    await expect(hers).toBeVisible({ timeout: 300_000 })
    const sheet = page.getByTestId('hq-sheet-assign')
    const worker = page.getByTestId('hq-sheet-worker')
    const shot = (n: string) => page.screenshot({ path: `${OUT}/${n}-${size.width}.png` })
    const act = (word: string) => sheet.getByText(word, { exact: true }).first()
    const row = () => hers.click({ position: { x: 30, y: 24 } })
    const openSheet = async () => {
      await row()
      await expect(sheet.or(worker).first()).toBeVisible({ timeout: 60_000 })
      if ((await worker.count()) > 0) await worker.getByTestId('corp-sheet-change').click()
      await expect(sheet).toBeVisible({ timeout: 60_000 })
    }
    const small = () =>
      sheet.evaluate((el) =>
        [...el.querySelectorAll('[data-testid="round-assign"] input, [data-testid="round-assign"] button')]
          .filter((b) => {
            const r = b.getBoundingClientRect()
            return r.width > 0 && (r.height < 43.5 || r.width < 43.5)
          })
          .map((b) => b.getAttribute('data-testid')),
      )

    // THREE ACTIONS, one read
    await openSheet()
    await expect(sheet.getByText('Trading', { exact: true }).first()).toBeVisible({ timeout: 120_000 })
    test.skip((await sheet.getByText('Combat', { exact: true }).count()) === 0, 'this image has no rounds')
    expect(asks, 'the sheet asked world.rounds more than once for one opening').toBeLessThanOrEqual(1)
    await shot('1-actions')

    // COMBAT: a sea, a round's cost, no odds, no RUN
    await act('Combat').click()
    const form = sheet.getByTestId('round-assign')
    await expect(form).toHaveAttribute('data-kind', 'combat')
    await expect(form.getByTestId('round-cost')).toBeVisible({ timeout: 60_000 })
    expect(Number(await form.getByTestId('round-cost').getAttribute('data-hull'))).toBeGreaterThan(0)
    for (const c of ['food', 'water', 'crew', 'ammo', 'hull']) await expect(form.locator(`[data-cost="${c}"]`)).toBeVisible()
    expect((await sheet.innerText()).toLowerCase(), 'a chance is drawn').not.toMatch(/chance|odds|win rate|run away/)
    expect(await small()).toEqual([])
    expect(await sideways(page)).toBe(false)
    await shot('2-combat')
    const open = form.locator('[data-testid="round-sea"]:not([disabled])')
    if ((await open.count()) > 1) {
      const before = await form.getByTestId('round-cost').getAttribute('data-hull')
      await open.nth(1).click()
      await expect.poll(async () => (await form.getByTestId('round-cost').count()) > 0).toBe(true)
      await shot('3-another-sea')
      await open.first().click()
      await expect(form.getByTestId('round-cost')).toHaveAttribute('data-hull', before ?? '')
    }
    await form.getByTestId('round-stop-hull').fill('999')
    await form.getByTestId('round-stop-boxes').scrollIntoViewIfNeeded()
    await form.getByTestId('round-go').click()
    await expect(sheet.getByText('the hull to leave at').first()).toBeVisible({ timeout: 60_000 })
    await shot('4-refused')
    await form.getByTestId('round-stop-hull').fill('60')
    await form.getByTestId('round-stop-rounds').fill('40')
    await form.getByTestId('round-stop-boxes').evaluate((el) => el.scrollIntoView({ block: 'center' }))
    await shot('5-stop')
    await form.getByTestId('round-go').click()
    await expect(sheet).toHaveCount(0, { timeout: 120_000 })
    await expect(hers).toHaveAttribute('data-action', 'round', { timeout: 120_000 })
    await expect(hers).toContainText('Combat')
    await expect(hers).toHaveAttribute('data-state', 'working')
    await shot('6-out-row')

    // HER SHEET: out, the rounds, the clock, Come home; then the log
    await row()
    const card = worker.getByTestId('round-card')
    await expect(card).toBeVisible({ timeout: 120_000 })
    await shot('7-out-sheet')
    const state = await card.getAttribute('data-state')
    const h0 = await card.getByTestId('round-log').evaluate((el) => el.getBoundingClientRect().height)
    if (state === 'out') await card.getByTestId('round-home').click()
    await expect(card).toHaveAttribute('data-state', 'home', { timeout: 120_000 })
    await expect(card.getByTestId('round-log-line').first()).toBeVisible({ timeout: 60_000 })
    expect(await card.getByTestId('round-log').evaluate((el) => el.getBoundingClientRect().height), 'the log changed its height').toBe(h0)
    await expect(card.getByTestId('round-log-line').first()).toContainText(/Won|Lost/)
    await shot('8-log')
    await page.goBack()
    await expect(worker).toHaveCount(0)
    const away = page.getByTestId('rounds-away')
    await expect(away).toBeVisible({ timeout: 120_000 })
    await away.getByTestId('rounds-away-open').click()
    await expect(away.getByTestId('round-log')).toBeVisible()
    await away.scrollIntoViewIfNeeded()
    expect(await sideways(page)).toBe(false)
    await shot('9-away')

    // EXPEDITION, and its artifacts at the capital
    await openSheet()
    await act('Expedition').click()
    await expect(form).toHaveAttribute('data-kind', 'sea')
    await expect(form.getByTestId('round-cost')).toBeVisible({ timeout: 60_000 })
    await expect(form.getByTestId('round-stop-hull')).toHaveCount(0)
    await form.getByTestId('round-stop-rounds').fill('3')
    await form.getByText('Go home', { exact: true }).click()
    await shot('10-expedition')
    await form.getByTestId('round-go').click()
    await expect(sheet).toHaveCount(0, { timeout: 120_000 })
    await expect(hers).toContainText('Expedition', { timeout: 120_000 })
    await row()
    await expect(card).toBeVisible({ timeout: 120_000 })
    if ((await card.getAttribute('data-state')) === 'out') await card.getByTestId('round-home').click()
    const give = card.getByTestId('round-give')
    await expect(give).toBeVisible({ timeout: 120_000 })
    await give.scrollIntoViewIfNeeded()
    await shot('11-artifacts')
    await give.click()
    await expect(give).toHaveCount(0, { timeout: 120_000 })
    await shot('12-given')
  })
