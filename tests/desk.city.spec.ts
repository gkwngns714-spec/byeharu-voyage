import { test, expect } from '@playwright/test'
import { ready, reachable, settled } from './appReady.fixture'
import { phoneLaws, readGlass } from './unfold.fixture'

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

test('the Report face: spans, the total, eight section rows and the places', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await page.goto('command')
  await ready(page)
  await page.getByRole('tab', { name: 'Report', exact: true }).click()
  await expect(page.getByTestId('desk-report')).toBeVisible()
  await expect(page.getByTestId('report-spans')).toBeVisible({ timeout: 30_000 })
  for (const id of ['trade', 'crew', 'supplies', 'repairs', 'insurance', 'invest', 'ships', 'other'])
    await expect(page.getByTestId(`report-section-${id}`)).toHaveAttribute('data-summary-row', '')
  // a pressed section opens its own page (the pop-up mechanism), and the back press returns
  await page.getByTestId('report-section-trade').click()
  await expect(page.getByTestId('report-section-trade-page')).toBeVisible()
  await page.locator('[data-detail-back]').last().click()
  await expect(page.getByTestId('report-section-trade-page')).toHaveCount(0)
  // a new company has made nothing yet (its starting money is capital, not profit): the report says so
  await expect(page.getByTestId('report-places')).toContainText(/Nothing in or out|수입/, { timeout: 30_000 })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BOARD STANDS ON THE GLASS (2026-11-02, the HQ-on-a-phone slice: docs/dev-log/2026-11-02-city-phone-desk.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The desk's City face on a phone is a stack — the fleet strip, the four faces, the city's header and its eight buildings — over ONE board: the building's own
// face, which scrolls inside its pane so the page never does. That pane was `max-h-[12rem]` (192 px) inside a Sheet that ended 187 px BELOW it (pane 408…600, Sheet
// 32…787 at 390×844), and the pane's own controls (the supplies row, Buy · Sell · Requests, the filter: 150 px) took 150 of the 192: forty px of goods stood on the glass at 390
// and none at 320×640. The owner: *"make it concise and simple so that it is easy to see in one eye without scrolling down"* (row 251).
//
// WHAT IT HOLDS, at 390×844 and 320×640: the Sheet does not scroll; the pane's bottom edge stands within 16 px of the Sheet's (it took the glass that was left, it does
// not stop short of it); at 390 it is at least 350 px tall and two goods stand WHOLE in it before any press (the strip, faces and header are 400 px of an 844-px glass); at 320
// it is at least the 7 rem floor. And what stands in it is clean by the HQ's own laws (tests/city.phone.spec.ts): no letter column, no box over another, nothing cut,
// nothing sideways — the request rows' `deliver` cell included (its reason ran 15 px past its row and the pane scrolled sideways).
test("the desk's City board stands on the glass at 390 and 320: no Sheet scroll, the pane takes what is left, and what is in it is clean", async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  const found: string[] = []
  for (const size of [{ width: 390, height: 844 }, { width: 320, height: 640 }]) {
    const where = `${size.width}×${size.height}`
    await page.setViewportSize(size)
    await page.goto('command')
    await ready(page)
    await page.getByRole('tab', { name: 'City', exact: true }).click()
    await expect(page.getByTestId('desk-city')).toBeVisible()
    const pane = page.locator('[data-testid="desk-city"] [role="tabpanel"] [data-scroll-pane]')
    await expect(pane).toBeVisible()
    await settled(pane)
    await page.waitForTimeout(500)
    const m = await page.evaluate(() => {
      const sheet = document.querySelector('[data-sheet]') as HTMLElement
      const pane = document.querySelector('[data-testid="desk-city"] [role="tabpanel"] [data-scroll-pane]') as HTMLElement
      const s = sheet.getBoundingClientRect()
      const p = pane.getBoundingClientRect()
      const whole = [...pane.querySelectorAll('[data-testid="trade-row"]')].filter((r) => {
        const b = r.getBoundingClientRect()
        return b.top >= p.top - 1 && b.bottom <= p.bottom + 1
      }).length
      return { sheetScroll: sheet.scrollHeight - sheet.clientHeight, paneH: p.height, gap: s.bottom - p.bottom, whole }
    })
    console.log(`DESK CITY ${where}: Sheet scroll ${m.sheetScroll}, pane ${Math.round(m.paneH)} px, ${Math.round(m.gap)} px above the Sheet's bottom, ${m.whole} goods whole`)
    if (m.sheetScroll > 1) found.push(`${where}: the Sheet scrolls by ${m.sheetScroll} px`)
    if (m.gap > 16) found.push(`${where}: the pane stops ${Math.round(m.gap)} px short of the Sheet's bottom`)
    if (size.width === 390) {
      if (m.paneH < 350) found.push(`${where}: the pane is ${Math.round(m.paneH)} px (under 350)`)
      if (m.whole < 2) found.push(`${where}: ${m.whole} goods stand whole in the pane (under 2)`)
    } else if (m.paneH < 112) found.push(`${where}: the pane is ${Math.round(m.paneH)} px (under the 7 rem floor)`)
    // the Trade face's three boards, by the HQ's laws
    const faces = page.getByRole('tablist', { name: 'Trade faces' })
    for (const name of ['Buy', 'Sell', 'Requests']) {
      await faces.getByRole('tab', { name, exact: true }).click()
      await page.waitForTimeout(600)
      const f = await readGlass(page, 'desk-city', null, '[data-testid="desk-city"] [role="tabpanel"]')
      found.push(...phoneLaws(`${where} ${name}`, f))
    }
  }
  expect(found, `the desk's City board is not on the glass:\n${found.join('\n')}`).toEqual([])
})
