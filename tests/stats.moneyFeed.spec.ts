import { test, expect, type Page } from '@playwright/test'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile } from '../src/lib/db/worldImage'
import { closeDetail, openDetail, ready, reachable } from './appReady.fixture'
import { openCityFace } from './desk.fixture'

// THE MONEY LOG (0235, owner row 219): every money move beside World money. Since the owner's
// 2026-10-31 compact-screen law it is ONE summary row on Stats; a press opens its full-screen page,
// where the sector grid and the live rows stand. This proof buys a lot on the quay, opens Stats,
// opens the log's page, and finds YOUR row (a drop) and the CITY's row (a gain), filters, and the
// page's own no-scroll law at the phone and the wide desk.

let litImage: Buffer | null = null

async function litWorld(): Promise<Buffer> {
  if (litImage) return litImage
  const dir = path.resolve('dist', 'db')
  const name = existsSync(dir) ? readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f)) : undefined
  if (!name) throw new Error(`no world image under ${dir} — run \`npm run build\` first`)
  const { PGlite } = await import('@electric-sql/pglite')
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, name)))) })
  try {
    const above = await pg.query<{ v: unknown }>(`select value as v from public.world_config where key = 'npc_invest_above'`)
    await pg.exec(`update public.world_config set value = to_jsonb(0) where key = 'npc_invest_above'`)
    const sw = await pg.query<{ j: { enabled: boolean } }>(`select public.city_treasury_switch(true) as j`)
    if (!sw.rows[0].j.enabled) throw new Error(`the switch did not light the purses: ${JSON.stringify(sw.rows[0].j)}`)
    await pg.query(`update public.world_config set value = $1::jsonb where key = 'npc_invest_above'`, [JSON.stringify(above.rows[0].v)])
    litImage = Buffer.from(await (await pg.dumpDataDir('gzip')).arrayBuffer())
  } finally {
    await pg.close()
  }
  return litImage
}

async function buyOne(page: Page): Promise<void> {
  const pressed = await page.evaluate(() => {
    const cell = [...document.querySelectorAll('[data-testid="trade-row"] button:enabled')].find((b) =>
      /^buy\b/i.test(((b as HTMLElement).innerText || '').trim()),
    ) as HTMLButtonElement | undefined
    cell?.click()
    return cell !== undefined
  })
  expect(pressed, 'no live buy cell to press').toBe(true)
  const tray = page.locator('[data-testid="trade-tray"]')
  await expect(tray.locator('[data-testid="trade-tray-send"]')).toBeEnabled({ timeout: 30_000 })
  await tray.locator('[data-testid="trade-tray-send"]').click()
  await expect(tray).toHaveCount(0, { timeout: 30_000 })
}

const noSideways = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)

test('Stats › the money log page shows my buy in red and the city’s side in green', async ({ page, request, baseURL }, testInfo) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  const world = await litWorld()
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: world, contentType: 'application/gzip' }))
  await page.goto('command')
  await ready(page)
  await openCityFace(page)
  expect(await page.locator('[data-testid="trade-row"]').count(), 'no ledger rows — is a fleet docked?').toBeGreaterThan(1)

  await buyOne(page)

  await page.getByTestId('nav-bar').getByText('Stats').click()
  await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
  // the log is a compact summary row; a press opens its page
  await openDetail(page, 'money-log')
  const log = page.getByTestId('money-log-page')
  await expect(log).toBeVisible({ timeout: 30_000 })

  // MY BUY: a drop, red, mine
  const mine = log.locator('[data-testid="money-move"][data-holder="company"][data-kind="BUY"][data-tone="drop"]').filter({ hasText: '(you)' })
  await expect(mine.first()).toBeVisible({ timeout: 30_000 })
  await expect(mine.first()).toContainText(/−[\d,]+/)
  await expect(mine.first()).toContainText('Bought')
  await expect(mine.first()).toContainText(/\d+ s ago|just now/)
  await expect(mine.first().locator('.text-danger')).toHaveCount(1)
  // THE CITY'S SIDE: a gain, green
  const city = log.locator('[data-testid="money-move"][data-holder="city"][data-kind="BUY"][data-tone="gain"]')
  await expect(city.first()).toBeVisible({ timeout: 30_000 })
  await expect(city.first()).toContainText(/\+[\d,]+/)
  await expect(city.first()).toContainText('Sold')
  await expect(city.first().locator('.text-success')).toHaveCount(1)

  // THE FILTERS ARE THE ORDERED GRID (owner, 2026-10-31) on the page; a sector press filters.
  await log.getByTestId('money-chip-bought').click()
  await expect(mine.first()).toBeVisible()
  await expect(log.locator('[data-testid="money-move"][data-holder="city"]')).toHaveCount(0)
  await log.getByTestId('money-chip-supplies').click()
  await expect(log.locator('[data-testid="money-move"][data-kind="BUY"]')).toHaveCount(0)
  expect(await page.evaluate(() => localStorage.getItem('bv:moneylog-filter'))).toContain('supplies')
  await log.getByTestId('money-chip-all').click()
  await expect(mine.first()).toBeVisible({ timeout: 30_000 })

  // THE PAGE ITSELF DOES NOT SCROLL; its body does. The document/Sheet behind are fixed.
  const pageBox = await page.evaluate(() => {
    const pg = document.querySelector('[data-detail-page]') as HTMLElement
    const de = document.documentElement
    return { h: pg.scrollHeight, ch: pg.clientHeight, top: pg.scrollTop, docH: de.scrollHeight, docCh: de.clientHeight }
  })
  expect(pageBox.top, 'the money log page is already scrolled').toBe(0)
  expect(pageBox.h, `the money log page itself scrolls: ${pageBox.h} > ${pageBox.ch}`).toBeLessThanOrEqual(pageBox.ch + 1)
  expect(pageBox.docH, 'the document scrolls behind the page').toBeLessThanOrEqual(pageBox.docCh + 1)
  expect(await noSideways(page), 'the page scrolls sideways at 390').toBe(true)
  await page.screenshot({ path: testInfo.outputPath('money-log-page-phone.png') })

  // WIDE: the same page, full screen, still no sideways scroll.
  await page.setViewportSize({ width: 1280, height: 900 })
  await expect(mine.first()).toBeVisible()
  expect(await noSideways(page), 'the page scrolls sideways at 1280').toBe(true)
  await page.screenshot({ path: testInfo.outputPath('money-log-page-wide.png') })

  // BACK REVEALS THE COMPACT SCREEN UNTOUCHED.
  await closeDetail(page)
  await expect(page.getByTestId('stats-overview')).toBeVisible()
  expect(await noSideways(page), 'the compact screen scrolls sideways after the back press').toBe(true)
})
