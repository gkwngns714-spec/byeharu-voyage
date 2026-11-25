import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { corpWorld } from './corpWorld.fixture'
import { serveWorldImage } from './worldImage.fixture'

// THE PASSIVE SETTINGS, DRIVEN (0516): the Assign sheet sets buy under, sell over, crew, days, a count and the two stops; a run out of its
// range waits and says why, on her row and her sheet; a job stopped for her hull offers Repair and goes on once she is mended. On an image
// without 0516 (the switch's row is not there) it is skipped: the boxes are not drawn.

const OUT = process.env.SETTINGS_SHOTS ?? 'test-results/passive-settings'
const sideways = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)

for (const size of [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
])
  test(`Assign's settings @${size.width}: out of range, stopped for her hull, mended, in range`, async ({ page, request, baseURL }) => {
    test.setTimeout(900_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await serveWorldImage(page, await corpWorld({ courses: true, home: true, settings: true }))
    await page.setViewportSize(size)
    await page.goto('city')
    await ready(page)
    const hers = page.locator('[data-testid="corp-worker"][data-kind="fleet"]').first()
    await expect(hers).toBeVisible({ timeout: 300_000 })
    const sheet = page.getByTestId('hq-sheet-assign')
    const worker = page.getByTestId('hq-sheet-worker')
    const shot = (n: string) => page.screenshot({ path: `${OUT}/${n}-${size.width}.png` })
    const box = (code: string) => sheet.getByTestId(`corp-setting-${code}`)
    const open = async () => {
      await hers.click({ position: { x: 30, y: 24 } })
      await expect(sheet.or(worker).first()).toBeVisible({ timeout: 60_000 })
      if (await worker.count()) await worker.getByTestId('corp-sheet-change').click()
      await expect(sheet).toBeVisible({ timeout: 60_000 })
      const run = sheet.locator('[data-testid="corp-assign-runs"][data-end="sell"] [data-testid="corp-assign-run"]').first()
      await expect(run).toBeVisible({ timeout: 180_000 })
      await run.click()
      if ((await sheet.getByTestId('corp-settings').count()) === 0) await sheet.getByTestId('corp-settings-open').click()
    }
    const assign = async () => {
      await sheet.getByTestId('corp-assign-go').click()
      await expect(sheet).toHaveCount(0, { timeout: 120_000 })
    }

    // every press and box is 44 px, the space left is the served figure, a bad number is refused in place
    await hers.click({ position: { x: 30, y: 24 } })
    await expect(sheet.getByTestId('corp-assign-run').first()).toBeVisible({ timeout: 180_000 })
    test.skip((await sheet.getByTestId('corp-settings-open').count()) === 0, 'this image has no 0516')
    await sheet.getByTestId('corp-assign-run').first().click()
    await sheet.getByTestId('corp-settings-open').click()
    const small = await sheet.evaluate((el) =>
      [...el.querySelectorAll('input[data-testid^="corp-setting-"], button')]
        .filter((b) => {
          const r = b.getBoundingClientRect()
          return r.width > 0 && r.height < 43.5
        })
        .map((b) => b.getAttribute('data-testid')),
    )
    expect(small).toEqual([])
    await sheet.getByTestId('corp-settings').evaluate((el) => el.scrollIntoView({ block: 'center' }))
    await expect(sheet.getByTestId('corp-settings-left')).toBeInViewport()
    expect(Number(await sheet.getByTestId('corp-settings-left').getAttribute('data-left'))).toBeGreaterThan(0)
    expect(await sideways(page)).toBe(false)
    await shot('1-settings')
    await box('crew').fill('9999')
    await sheet.getByTestId('corp-assign-go').click()
    await expect(sheet.getByText('her crew is from').first()).toBeVisible({ timeout: 60_000 })
    await shot('2-refused')

    // OUT OF RANGE: she waits, her row and her sheet say why
    await box('crew').fill('')
    await box('under').fill('0.01')
    await assign()
    await expect(hers).toHaveAttribute('data-wait', 'range', { timeout: 120_000 })
    await expect(hers).toContainText('Out of range')
    expect(await sideways(page)).toBe(false)
    await shot('3-waiting-row')
    await hers.click({ position: { x: 30, y: 24 } })
    await expect(worker.getByTestId('corp-sheet-wait')).toHaveText(/^buys at [0-9,.]+, your limit 0\.01$/, { timeout: 60_000 })
    await shot('4-waiting-sheet')
    await page.goBack()
    await expect(worker).toHaveCount(0)

    // STOPPED FOR HER HULL (the world halves it when a job says `stop_damage` 31): the reason, Repair at its price, and she goes on
    await open()
    await expect(box('under'), 'the boxes do not start as her job has them').toHaveValue('0.01')
    await box('under').fill('')
    await box('stop_damage').fill('31')
    await assign()
    // (her row IS the press that mends her: pressed, it repairs at the served price)
    await expect(hers).toHaveAttribute('data-state', 'stopped', { timeout: 120_000 })
    await expect(hers.getByTestId('corp-worker-action')).toHaveText(/^hull damage [0-9]+ %, you stop over 31 %$/)
    await expect(hers).toHaveAttribute('data-fix', 'repair')
    await expect(hers, 'Repair has no price').toHaveAttribute('data-fix-cost', /[0-9]/, { timeout: 60_000 })
    await shot('5-stopped-repair')
    await hers.click()
    await expect(hers).not.toHaveAttribute('data-state', 'stopped', { timeout: 300_000 })
    await shot('6-mended')
    if (await worker.count()) await page.goBack()

    // IN RANGE: every setting, a count of runs: she sails
    await open()
    await box('stop_damage').fill('90')
    await box('under').fill('1000000')
    await box('over').fill('0.01')
    await box('crew').fill(/–(\d+)/.exec(await sheet.getByTestId('corp-settings').innerText())![1])
    await box('days').fill('5')
    await box('stop_profit').fill('0')
    await sheet.getByText('Runs', { exact: true }).last().click()
    await sheet.getByTestId('corp-settings').evaluate((el) => el.scrollIntoView({ block: 'center' }))
    await expect(sheet.getByTestId('corp-settings-left')).toBeInViewport()
    await shot('7-all-set')
    await assign()
    await expect(hers).toHaveAttribute('data-state', 'working', { timeout: 180_000 })
    await shot('8-sailing')
  })
