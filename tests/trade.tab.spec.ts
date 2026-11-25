/// <reference types="node" />
import { test, expect, type Locator, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { pressCity } from './deskMap.fixture'
import { SECOND_FLEET, serveTwoFleets } from './twoFleets.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADE TAB: THE FLEET'S NAME AT THE TOP, AND A MAP OF PLACES THAT TELLS PRICES
// (the owner, 2026-11-25, docs/design/owner-spec-2026-11-25.md; slice C1 `trade-tab-fleet-map`):
//
//     "THE TRADE TAB is for ACTIVE TRADING. At the trade tab, it will show your FLEET name, and you can change your
//      FLEET by tapping the name to trade on different location per FLEET. In the trade tab there should be a map,
//      showing no NPCs but only locations, where you can click them for info – price info."
//
// Driven at 390 and 1440 on the world with two fleets (tests/twoFleets.fixture.ts):
//   · the fleet's name stands at the top; a press on it lists her fleets; a row pressed changes the fleet IN PLACE
//     (same address, nothing on the face moves) and the list follows her (what is on board is hers);
//   · the map draws places and nothing else: no ship, no merchant;
//   · a place pressed shows its prices in a sheet, with ONE market read for the press, and the sheet's figures are the
//     board's (there is no second list of prices that could differ);
//   · "Trade here" closes the map on that place's board, and Buy and Sell work there as before;
//   · nothing moves by itself, nothing scrolls sideways, every press is 44 px, every word is English.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** Where the screenshots go (a folder), when the run is asked for them. */
const SHOTS = process.env.TRADE_TAB_SHOTS ?? ''
const FLAGSHIP = 'Gaivota'
/** A place far enough from her harbour to stand alone on the whole-world map, named on it at both sizes. */
const FAR = 'CAD'
const NOT_ENGLISH = /[ㄱ-힝]/

const rect = async (l: Locator) => {
  const b = (await l.boundingBox())!
  return { x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height) }
}
const noSideScroll = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)
const shot = async (page: Page, name: string) => {
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/${name}.png` })
}

/** The `[rpc]` debug lines (src/lib/rpc/backend.ts prints one per ask), stamped on the page's own clock. */
async function watchAsks(page: Page) {
  await page.evaluate(() => {
    const log: { at: number; label: string }[] = []
    const debug = console.debug.bind(console)
    console.debug = (...args: unknown[]) => {
      if (args[0] === '[rpc]' && typeof args[1] === 'string') log.push({ at: performance.now(), label: args[1].replace(/\(.*$/, '') })
      debug(...args)
    }
    ;(window as unknown as { __rpcLog: typeof log }).__rpcLog = log
  })
}
const mark = (page: Page) => page.evaluate(() => performance.now())
const asksSince = (page: Page, from: number) =>
  page.evaluate((a) => (window as unknown as { __rpcLog: { at: number; label: string }[] }).__rpcLog.filter((e) => e.at >= a).map((e) => e.label), from)

async function pickFleet(page: Page, name: string) {
  await page.getByTestId('fleet-picker').click()
  const list = page.getByTestId('fleet-list')
  await expect(list).toBeVisible()
  const row = list.getByTestId('fleet-row').filter({ hasText: name })
  expect((await rect(row)).h, `the fleet row "${name}" is under 44 px`).toBeGreaterThanOrEqual(44)
  await row.click()
  await expect(list).toHaveCount(0)
  await expect(page.getByTestId('fleet-picker')).toContainText(name)
}

for (const size of [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const) {
  test.describe(`the Trade tab at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('the fleet name changes the fleet in place; the map is places only; a place pressed shows its prices; buy and sell work', async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`)
      await serveTwoFleets(page)
      await page.goto('command')
      await ready(page)
      await watchAsks(page)
      const face = page.getByTestId('desk-trade')
      const board = face.getByTestId('trade-board')
      const picker = page.getByTestId('fleet-picker')
      await expect(board.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
      const home = (await board.getAttribute('data-city'))!

      // ── THE FLEET'S NAME AT THE TOP ─────────────────────────────────────────────────────────────
      await expect(picker).toContainText(FLAGSHIP)
      const pickerBox = await rect(picker)
      expect(pickerBox.h, 'the fleet name is a press under 44 px').toBeGreaterThanOrEqual(44)
      expect(pickerBox.y + pickerBox.h, 'the fleet name is not above the goods').toBeLessThanOrEqual((await rect(board)).y)
      expect(pickerBox.y, 'the fleet name is not at the top of the tab').toBeLessThan(120)
      await shot(page, `${size.width}-1-tab`)

      // a good bought for the flagship, so the list has something that is HERS
      const card = board.locator('[data-testid="trade-good"]:has([data-testid="trade-buy"]:not([disabled]))').first()
      const code = (await card.getAttribute('data-good'))!
      await card.getByTestId('trade-buy').click()
      const units = page.getByTestId('good-detail').getByTestId('stepper-figure')
      await expect(units).toBeVisible({ timeout: 60_000 })
      await units.fill('1')
      await units.press('Enter')
      const act = page.getByTestId('trade-act')
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText(/^Bought 1 /, { timeout: 60_000 })
      expect((await rect(page.getByTestId('trade-toast'))).y, 'the toast is not at the top').toBeLessThan(100)
      const mine = board.locator(`[data-testid="trade-good"][data-good="${code}"]`)
      await expect(mine.getByTestId('trade-good-aboard')).toHaveText('On board 1', { timeout: 60_000 })
      const hers = 'On board 1'

      // ── A PRESS ON THE NAME CHANGES THE FLEET IN PLACE, AND THE LIST FOLLOWS ────────────────────
      const address = page.url()
      const where = async () => ({ strip: (await rect(page.getByTestId('fleet-strip'))).y, board: await rect(board), card: await rect(mine), doors: await Promise.all(['cargo-open', 'trade-map-open', 'command-queue'].map(async (id) => rect(face.getByTestId(id)))) })
      const before = await where()
      await picker.click()
      await expect(page.getByTestId('fleet-list')).toBeVisible()
      expect(await where(), 'opening the list of fleets moved the face').toEqual(before)
      await shot(page, `${size.width}-2-fleets`)
      await page.getByTestId('fleet-list').getByTestId('fleet-row').filter({ hasText: SECOND_FLEET }).click()
      await expect(page.getByTestId('fleet-list')).toHaveCount(0)
      await expect(picker).toContainText(SECOND_FLEET)
      await expect(mine.getByTestId('trade-good-aboard'), 'the list did not follow the fleet').toHaveText('On board 0')
      expect(page.url(), 'changing the fleet left the tab').toBe(address)
      expect(await where(), 'changing the fleet moved the face').toEqual(before)
      await shot(page, `${size.width}-3-second-fleet`)
      await pickFleet(page, FLAGSHIP)
      await expect(mine.getByTestId('trade-good-aboard')).toHaveText(hers)
      expect(await where(), 'changing the fleet back moved the face').toEqual(before)

      // ── THE MAP: PLACES ONLY ────────────────────────────────────────────────────────────────────
      const mapBox = face.getByTestId('trade-face-map-box')
      const map = face.getByTestId('trade-face-map')
      const box0 = await rect(mapBox)
      if (size.width === 390) {
        expect([box0.w, box0.h], 'the phone map is not about 358 x 260').toEqual([358, 260])
        expect(box0.y, 'the map is not under the fleet name').toBeGreaterThanOrEqual(pickerBox.y + pickerBox.h)
        expect(box0.y + box0.h, 'the list is not under the map').toBeLessThanOrEqual((await rect(board)).y)
      } else {
        const b = await rect(board)
        expect(box0.x + box0.w, 'the map is not beside the list').toBeLessThanOrEqual(b.x)
        expect(box0.w / (box0.w + b.w), 'the map is under 40 % of the map and the list').toBeGreaterThan(0.4)
      }
      expect(await mapBox.evaluate((e) => e.getBoundingClientRect().bottom <= innerHeight), 'the map is not on the first screen').toBe(true)
      const chart = map.getByTestId('small-chart')
      await expect(map).toHaveAttribute('data-cities', '*')
      await expect(chart.locator(`[data-port-code="${FAR}"]`).first()).toBeAttached({ timeout: 60_000 })
      expect(await chart.locator('[data-port-code]').count(), 'the map draws no places').toBeGreaterThan(20)
      await expect(chart.locator('[data-merchant-id]'), 'a merchant is drawn on the map of places').toHaveCount(0)
      await expect(chart.locator('[data-hulls]'), 'a ship is drawn on the map of places').toHaveCount(0)
      await expect(page.getByTestId('city-prices'), 'the prices stand before any place is pressed').toHaveCount(0)
      await shot(page, `${size.width}-4-map`)

      // ── A PLACE PRESSED SHOWS ITS PRICES, FROM ONE READ ─────────────────────────────────────────
      const chartBox = await rect(chart)
      const from = await mark(page)
      await pressCity(page, map, FAR)
      const sheet = page.getByTestId('city-prices')
      await expect(sheet).toBeVisible()
      await expect(sheet).toHaveAttribute('data-city', FAR)
      const prices = sheet.getByTestId('city-price')
      await expect(prices.first()).toBeVisible({ timeout: 60_000 })
      const asked = await asksSince(page, from)
      const beats = asked.filter((l) => l === 'world.fleets').length
      expect(asked.filter((l) => l === 'world.market').length, `the press asked for the market more than once (${asked.join(' · ')})`).toBeLessThanOrEqual(1 + beats)
      expect(await prices.count()).toBeGreaterThan(2)
      await expect(sheet.getByTestId('city-prices-where')).toHaveText('Not docked')
      for (const p of await prices.all()) await expect(p.getByTestId('city-price-buy')).toHaveText(/\d|—/)
      await expect(prices.first().getByTestId('city-price-buy')).toHaveText(/\d/)
      expect((await rect(prices.first())).h, 'a price line is under 44 px').toBeGreaterThanOrEqual(44)
      expect(await rect(chart), 'the prices opening moved or resized the map').toEqual(chartBox)
      for (const id of ['tray-close', 'city-prices-trade']) {
        const b = await rect(sheet.getByTestId(id))
        expect(Math.min(b.w, b.h), `${id} is under 44 px`).toBeGreaterThanOrEqual(44)
      }
      expect(await sheet.innerText(), 'a word that is not English on the prices').not.toMatch(NOT_ENGLISH)
      expect(await noSideScroll(page), 'the page scrolls sideways with the prices open').toBe(true)
      await shot(page, `${size.width}-5-prices`)

      // THE FRAME RATE of the map on this glass, panned by a mouse for 2 s (said, not held to a number: the machine is shared)
      await sheet.getByTestId('tray-close').click()
      await expect(sheet).toHaveCount(0)
      const fps = page.evaluate(() => new Promise<{ n: number; worst: number }>((done) => {
        let n = 0, worst = 0, last = performance.now()
        const end = last + 2_000
        const step = (at: number) => { n++; worst = Math.max(worst, at - last); last = at; if (at < end) requestAnimationFrame(step); else done({ n: n / 2, worst }) }
        requestAnimationFrame(step)
      }))
      const c = await rect(chart)
      await page.mouse.move(c.x + 60, c.y + c.h / 2)
      await page.mouse.down()
      for (let i = 0; i < 60; i++) { await page.mouse.move(c.x + 60 + i * 3, c.y + c.h / 2); await page.waitForTimeout(16) }
      await page.mouse.up()
      console.log(`FPS @${size.width} ${JSON.stringify(await fps)}`)
      await expect(sheet, 'a drag on the map opened a place').toHaveCount(0)
      await pressCity(page, map, FAR)
      await expect(prices.first()).toBeVisible({ timeout: 60_000 })
      await expect.poll(async () => { const a = await rect(chart.locator(`[data-port-code="${FAR}"]`).first()); await page.waitForTimeout(150); return JSON.stringify(a) === JSON.stringify(await rect(chart.locator(`[data-port-code="${FAR}"]`).first())) }).toBe(true)

      // NOTHING MOVES BY ITSELF: the sheet and the map stand where they are while the world goes on
      const still = { sheet: await rect(sheet), chart: await rect(chart), first: await rect(prices.first()) }
      await page.waitForTimeout(4_000)
      expect({ sheet: await rect(sheet), chart: await rect(chart), first: await rect(prices.first()) }, 'the prices or the map moved by themselves').toEqual(still)

      // the sheet shuts by its own close; the map stays; a press opens it again
      await sheet.getByTestId('tray-close').click()
      await expect(sheet).toHaveCount(0)
      await pressCity(page, map, FAR)
      await expect(prices.first()).toBeVisible({ timeout: 60_000 })
      // THE SECOND PRESS IS THE SAME PLACE: on a phone "Cadiz" stands over Dublin's mark, and a press on the word opened Dublin
      const there = FAR
      for (let i = 0; i < 4; i++) {
        await expect(sheet).toHaveAttribute('data-city', FAR)
        // never under the sheet: the pressed place's mark and the sheet do not meet
        const m = (await chart.locator(`[data-port-code="${FAR}"]`).first().boundingBox())!
        const sh = await rect(sheet)
        const under = m.x + m.width / 2 > sh.x && m.x + m.width / 2 < sh.x + sh.w && m.y + m.height / 2 > sh.y
        expect(under, 'the sheet covers the pressed place').toBe(false)
        if (i === 3) break
        await sheet.getByTestId('tray-close').click()
        await expect(sheet).toHaveCount(0)
        await pressCity(page, map, FAR)
      }
      await expect(prices.first()).toBeVisible({ timeout: 60_000 })

      // ── "TRADE HERE": THE MAP CLOSES ON THAT PLACE'S BOARD, WITH THE SAME FIGURES ───────────────
      const good = (await prices.first().getAttribute('data-good'))!
      const told = (await prices.first().getByTestId('city-price-buy').innerText()).trim()
      await sheet.getByTestId('city-prices-trade').click()
      await expect(sheet).toHaveCount(0)
      await expect(board).toHaveAttribute('data-city', there)
      await expect(board).toHaveAttribute('data-docked', 'false')
      await expect(board.locator(`[data-testid="trade-good"][data-good="${good}"]`).getByTestId('trade-good-buy'), "the sheet's price is not the board's").toHaveText(told)
      await shot(page, `${size.width}-6-board-there`)

      // ── HER OWN HARBOUR PRESSED: "Docked", and SELL works there as before ───────────────────────
      await pressCity(page, map, home)
      await expect(sheet).toHaveAttribute('data-city', home)
      await expect(sheet.getByTestId('city-prices-where')).toHaveText('Docked')
      await expect(sheet.locator(`[data-testid="city-price"][data-good="${code}"]`)).toBeVisible({ timeout: 60_000 })
      await sheet.getByTestId('city-prices-trade').click()
      await expect(board).toHaveAttribute('data-city', home)
      await expect(board).toHaveAttribute('data-docked', 'true')
      await mine.getByTestId('trade-sell').click()
      await expect(act).toHaveAttribute('data-act', 'sell')
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()
      await expect(page.getByTestId('trade-toast')).toContainText(/^Sold 1 /, { timeout: 60_000 })
      await expect(mine.getByTestId('trade-good-aboard')).toHaveText('On board 0', { timeout: 60_000 })

      expect(await face.innerText(), 'a word that is not English on the Trade tab').not.toMatch(NOT_ENGLISH)
      expect(await noSideScroll(page), 'the Trade tab scrolls sideways').toBe(true)
      await shot(page, `${size.width}-7-sold`)
    })
  })
}

// A SECOND PRESS ON A PLACE'S NAME IS THAT PLACE (the whole world on a phone): "Cadiz" in hand stands over Dublin's mark, the same
// longitude and 15 px north, and a press on the word opened Dublin (chart/hitTest.ts `held`).
test.describe('the big map at 390', () => {
  test.use({ viewport: { width: 390, height: 844 } })
  test('a second press on the name of the place in hand is the same place', async ({ page, request, baseURL }) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await page.goto('command')
    await ready(page)
    const face = page.getByTestId('desk-trade')
    await face.getByTestId('trade-map-open').click()
    const map = face.getByTestId('trade-map')
    const sheet = page.getByTestId('city-prices')
    for (let i = 0; i < 4; i++) {
      await pressCity(page, map, FAR)
      await expect(sheet, `press ${i + 1} on the same place named another`).toHaveAttribute('data-city', FAR)
      await sheet.getByTestId('tray-close').click()
      await expect(sheet).toHaveCount(0)
    }
  })
})
