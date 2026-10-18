import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY FACE, DRIVEN (docs/COMMAND_DESK.md §2.2, §3.6, slice D5) — on a local build, at the phone. Every
// building PORT carried is a face of the city the fleet is docked at, on COMMAND:
//   · each face the city has opens (its panel is not empty), a press selects and moves nothing above it,
//     and the page never scrolls sideways;
//   · the acts run from here: a BUY through the Trade face's own tray (cargo rises), and the Town face
//     carries the Town Hall (the purse and Invest).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ viewport: { width: 390, height: 844 } })

test('every building face opens on the desk, and a buy runs from its Trade face', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('command')
  await ready(page)
  await page.getByRole('tab', { name: 'City', exact: true }).click()
  await expect(page.getByTestId('desk-city')).toBeVisible()
  const strip = page.getByRole('tablist', { name: 'City buildings' })
  const tabs = strip.getByRole('tab')
  const names = await tabs.allInnerTexts()
  console.log(`city faces: ${names.join(', ')}`)
  expect(names).toEqual(expect.arrayContaining(['Trade', 'Town', 'Inn']))

  const stripTop = async () => Math.round((await strip.boundingBox())!.y)
  const top = await stripTop()
  for (const name of names) {
    await strip.getByRole('tab', { name, exact: true }).click()
    await page.waitForTimeout(600)
    expect(await stripTop(), `pressing ${name} moved the strip`).toBe(top)
    const panel = page.getByTestId('desk-city').getByRole('tabpanel')
    await expect(panel, `${name} drew nothing`).not.toBeEmpty({ timeout: 30_000 })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `${name} scrolls sideways`).toBe(true)
  }

  // Town carries the Town Hall
  await strip.getByRole('tab', { name: 'Town', exact: true }).click()
  await expect(page.getByTestId('desk-town-hall')).toBeVisible({ timeout: 30_000 })

  // a BUY from the Trade face: the quay's own tray, the one door
  await strip.getByRole('tab', { name: 'Trade', exact: true }).click()
  const cargo = page.getByTestId('command-line')
  const before = await cargo.innerText()
  await page.locator('[data-testid="trade-row"] button:enabled').first().click()
  const tray = page.getByTestId('trade-tray')
  await expect(tray).toBeVisible()
  const send = tray.getByTestId('trade-tray-send')
  await expect(send).toBeEnabled({ timeout: 30_000 })
  await send.click()
  await expect.poll(async () => cargo.innerText(), { timeout: 60_000 }).not.toBe(before)
})

test('the Invest face: your holdings, and the Town Hall of the city the fleet is at', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await page.goto('command')
  await ready(page)
  await page.getByRole('tab', { name: 'Invest', exact: true }).click()
  await expect(page.getByTestId('invest-holdings')).toBeVisible()
  await expect(page.getByTestId('invest-holdings')).toContainText(/shares|Held/, { timeout: 30_000 })
  await expect(page.getByTestId('invest-hall')).toBeVisible({ timeout: 30_000 })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
})
