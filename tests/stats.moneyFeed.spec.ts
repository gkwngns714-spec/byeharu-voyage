// THE MONEY LOG (0235, owner row 219, 2026-10-26): *"beside the stat, world money, i want to see the live log of each
// happenings that cause money - drop and gain, at the right side. possible?"* — the Stats Overview lists every money
// move as it happens, beside World money: green for a gain, red for a drop, who, what for, how long ago.
//
// Here, in the in-tab (PGlite) canary world with the city purses lit (the shipped world keeps them dark, so the
// precondition is set in Node on the build's own image through THE switch, as tests/map.townhall.spec.ts does):
// buy one lot on the quay, open Stats, and the log carries the buy twice — YOUR row in red (a drop) and the CITY's
// row in green (its gain) — under World money on a phone and in the right-hand column on a wide glass, with no
// sideways scroll. It names MoneyLog.tsx / Overview.tsx so CI's rule N selects it.
//
// The build under test must be served: `npm run build && npx vite preview --port <n>`, then
// PLAYWRIGHT_BASE_URL=http://localhost:<n>/byeharu-voyage/ (localhost, not 127.0.0.1).

import { test, expect, type Page } from '@playwright/test'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile } from '../src/lib/db/worldImage'
import { PHONE, ready, reachable } from './appReady.fixture'
import { openCityFace } from './desk.fixture'

test.use({ viewport: PHONE })

let litImage: Buffer | null = null

/** The build's world with the city purses lit (public.city_treasury_switch(true)). */
async function litWorld(): Promise<Buffer> {
  if (litImage) return litImage
  const dir = path.resolve('dist', 'db')
  const name = existsSync(dir) ? readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f)) : undefined
  if (!name) throw new Error(`no world image under ${dir} — run \`npm run build\` first`)
  const { PGlite } = await import('@electric-sql/pglite')
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, name)))) })
  try {
    // The switch refuses a world whose money cannot carry the merchants' surplus line; only the purses are needed
    // here, so that line is lowered for the switch and put back (map.townhall.spec.ts).
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

/** Press the first live `buy` cell on the quay and send the tray. */
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

test('Stats › the money log shows my buy in red and the city’s side of it in green, beside World money', async ({ page, request, baseURL }, testInfo) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  const world = await litWorld()
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: world, contentType: 'application/gzip' }))
  await page.goto('command')
  await ready(page)
  await openCityFace(page)
  expect(await page.locator('[data-testid="trade-row"]').count(), 'no ledger rows — is a fleet docked?').toBeGreaterThan(1)

  await buyOne(page)

  // to Stats, in the app (the world lives in this tab)
  await page.getByTestId('nav-bar').getByText('Stats').click()
  await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
  const log = page.getByTestId('money-log')
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

  // PHONE: under World money, nothing sideways
  const money = page.getByTestId('stats-overview').locator('section').first()
  const [mb, lb] = [await money.boundingBox(), await log.boundingBox()]
  expect(mb && lb && lb.y >= mb.y + mb.height - 1, 'the log is not under World money on a phone').toBe(true)
  expect(await noSideways(page), 'the page scrolls sideways at 390').toBe(true)
  await page.screenshot({ path: testInfo.outputPath('money-log-phone.png') })

  // WIDE: the right-hand column beside World money, its top on World money's line, inside the glass
  await page.setViewportSize({ width: 1280, height: 900 })
  await expect(mine.first()).toBeVisible()
  const [mw, lw] = [await money.boundingBox(), await log.boundingBox()]
  const [mh, lh] = [await money.locator('h2').first().boundingBox(), await log.locator('h2').first().boundingBox()]
  expect(mw && lw && lw.x >= mw.x + mw.width, 'the log is not to the right of World money').toBe(true)
  expect(mh && lh && Math.abs(lh.y - mh.y) <= 2, 'the log’s heading is not on World money’s line').toBe(true)
  expect(lw && lw.x + lw.width <= 1280, 'the log runs off the glass').toBe(true)
  expect(await noSideways(page), 'the page scrolls sideways at 1280').toBe(true)
  await page.screenshot({ path: testInfo.outputPath('money-log-wide.png') })
})
