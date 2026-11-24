import { test, expect, type Page } from '@playwright/test'
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'
import { ready, reachable } from './appReady.fixture'
import { toPlaces } from './hqPlaces.fixture'
import { openFleetSheet } from './desk.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// H3 `desk-into-hq` (2026-11-24; docs/design/hq-corp-2026-11-24.md H3, simplify-2026-11-24.md S3)
// THE TRADE DESK AND THE OFFICE ARE GONE, AND NOTHING THEY HAD IS UNREACHABLE.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `/command` (the Trade desk) and `/office` (the Office) were two screens that drew what HQ draws. Their screens are deleted, their
// routes open HQ, and every face they had stands on an HQ plate or in a sheet over HQ. THE TABLE below is the whole list: each row is
// one face, where it is now, and the walk that proves it is reached from HQ by presses alone. The URL stays `/city` throughout.
//
//   THE TRADE DESK (/command)                          NOW
//   goal card, the starter chain's step                HQ, under the bridge (`hq-goal`)
//   the fleet in hand, where she is (strip, status)    HQ's worker row > her sheet (`trade-status`)
//   the goods board: Buy / Sell, the best sale         HQ > Market plate (`trade-good`, `best-sale`)
//   the city chips (read another city)                 HQ > Market plate (`city-chips`); the chart beside it follows
//   From here                                          HQ > Market plate (`from-here`, while she lies there)
//   the world's events line                            HQ > Market plate (`city-market-read`)
//   the trade sheet (hand trade, a trip)               the trade sheet over HQ (`good-detail`)
//   Your cargo (the sell face, with profit)            her sheet (`cargo-best`)
//   the route                                          her sheet (`route-row`)
//   Orders, insured voyages, her ship                  her sheet (`queue`, `buy-ship`)
//   the Map of her orders, and of the trip in hand     her sheet > Map (`trade-map`; tests/trade.map.spec.ts)
//
//   THE OFFICE (/office)                               NOW
//   City > Market (trade, or prices when away)         HQ > Market plate
//   City > Town (the buildings, the town hall)         HQ's five plates; HQ > City hall plate (`city-hall-figures`)
//   City > Production                                  HQ > Production plate (`port-production`)
//   City > Craft (the workstation)                     HQ > Port plate > Craft (`hq-sheet-workstation`)
//   City > Inn                                         HQ > Inn plate (`city-inn-page`)
//   City > Build                                       HQ > Port plate > Build (`city-port-yard-page`)
//   City > Repair                                      HQ > Port plate > Repair (`city-port-repair-page`)
//   City > Skills (the academy)                        HQ > Port plate > Skills (`hq-sheet-academy`)
//   City > Gear                                        HQ > Port plate > Gear (`city-port-gear-page`)
//   City: the fair, the events, what the city wants    HQ > Market plate (`city-market-read`)
//   City: the tow note                                 HQ > Port plate
//   Invest                                             HQ's Invest door (`hq-sheet-invest`)
//   Report                                             HQ's Report door (`hq-sheet-report`)

const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const
const OUT = 'test-results/desk-into-hq'

/** Close the top layer by its own back (a page's arrow, else a tray's close). */
async function back(page: Page) {
  const arrow = page.locator('[data-detail-page] [data-detail-back]')
  if ((await arrow.count()) > 0) await arrow.last().click()
  else await page.getByTestId('tray-close').last().click()
}

/** Open a plate; the URL does not move. */
async function plate(page: Page, id: string) {
  const url = page.url()
  await toPlaces(page)
  await page.getByTestId(`city-building-${id}`).click()
  await expect(page.getByTestId(`city-building-${id}`)).toHaveAttribute('aria-pressed', 'true')
  expect(page.url(), `the ${id} plate left HQ`).toBe(url)
}

for (const size of SIZES)
  test.describe('en-US', () => {
    test.use({ locale: 'en-US' })

    test(`HQ @${size.width}: every face of the Trade desk and of the Office is reached from HQ (H3)`, async ({ page, request, baseURL }) => {
      test.setTimeout(900_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await page.setViewportSize(size)
      await page.goto('city')
      await ready(page)
      await expect(page.getByTestId('city-hall-figures'), 'the Town face: the city hall is HQ’s first plate').toBeVisible({ timeout: 300_000 })
      await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
      const home = page.url()
      const still = (what: string) => expect(page.url(), `${what} left HQ`).toBe(home)
      const reached: string[] = []
      const seen = async (face: string, testid: string) => {
        await expect(page.getByTestId(testid).first(), `${face} is not reached (${testid})`).toBeVisible({ timeout: 60_000 })
        still(face)
        reached.push(face)
      }

      // ── THE TRADE DESK ─────────────────────────────────────────────────────────────────────
      await expect(page.getByTestId('hq-goal'), 'the goal card’s place under the bridge').toHaveCount(1)
      await expect(page.locator('[data-testid="hq-goal"] [data-testid^="goal-card"]'), 'the goal card').toHaveCount(1)
      reached.push('desk: goal card')

      // her sheet: where she is, her cargo, her route, her orders, her ship, her map
      await openFleetSheet(page)
      await seen('desk: the fleet in hand, her status', 'trade-status')
      await expect(page.getByTestId('hq-sheet-fleet').locator('[data-testid^="cargo-best"]').first(), 'Your cargo').toBeVisible()
      reached.push('desk: Your cargo')
      await seen('desk: the route', 'hq-sheet-fleet-route')
      await seen('desk: her ship', 'buy-ship')
      await page.getByTestId('hq-sheet-fleet-map').click()
      await seen('desk: the Map of her orders', 'trade-map')
      await page.screenshot({ path: `${OUT}/fleet-map-${size.width}.png` })
      await back(page)
      await expect(page.getByTestId('hq-sheet-fleet-map-page')).toHaveCount(0)
      await page.getByTestId('hq-sheet-fleet').evaluate((el) => el.scrollTo?.(0, 0))
      await page.screenshot({ path: `${OUT}/fleet-sheet-${size.width}.png` })
      await back(page)
      await expect(page.getByTestId('hq-sheet-fleet')).toHaveCount(0)

      // the Market plate: the one trade list
      await plate(page, 'market')
      await seen('desk: the goods board (Buy / Sell) = office: City > Market', 'city-market-buy')
      await seen('desk: the city chips', 'city-chips')
      await seen('office: the city’s fair, events and wants; desk: the world’s events', 'city-market-read')
      const goods = page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]')
      const codes = await goods.evaluateAll((els) => els.map((e) => e.getAttribute('data-good')))
      expect(codes.length, 'the Market lists no goods').toBeGreaterThan(0)
      expect(new Set(codes).size, 'a good stands twice on the Market').toBe(codes.length)
      for (const word of ['trade-buy', 'trade-sell']) expect(await goods.first().getByTestId(word).count(), `a card has no ${word}`).toBe(1)
      await expect(page.locator('[data-testid="city-market-buy"] [data-testid="best-sale"]').first(), 'the best sale on a card').toBeVisible({ timeout: 60_000 })
      reached.push('desk: the best sale')
      await page.screenshot({ path: `${OUT}/market-${size.width}.png` })

      // the trade sheet, over HQ
      await goods.nth(1).getByTestId('trade-buy').click()
      await seen('desk: the trade sheet (hand trade)', 'good-detail')
      await back(page)
      await expect(page.getByTestId('good-detail')).toHaveCount(0)

      // another city read: the list is that city's, the chart follows, and HQ's own chip returns
      const mine = await page.getByTestId('city-market-read').getAttribute('data-city')
      const other = page.locator(`[data-testid="city-chip"]:not([data-port="${mine}"])`).first()
      const otherCode = await other.getAttribute('data-port')
      await other.click()
      await expect(page.getByTestId('city-market-read'), 'the chip did not turn the list').toHaveAttribute('data-city', otherCode ?? '')
      still('a city chip')
      await expect(page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]').first()).toBeVisible({ timeout: 60_000 })
      await page.screenshot({ path: `${OUT}/market-away-${size.width}.png` })
      await page.locator(`[data-testid="city-chip"][data-port="${mine}"]`).click()
      await expect(page.getByTestId('city-market-read')).toHaveAttribute('data-city', mine ?? '')
      reached.push('desk: another city read')

      // ── THE OFFICE ─────────────────────────────────────────────────────────────────────────
      await plate(page, 'production')
      await seen('office: City > Production', 'port-production')

      await plate(page, 'port')
      for (const [face, door, sheet] of [
        ['office: City > Build', 'city-port-yard', 'city-port-yard-page'],
        ['office: City > Repair', 'city-port-repair', 'city-port-repair-page'],
        ['office: City > Gear', 'city-port-gear', 'city-port-gear-page'],
        ['office: City > Craft (workstation)', 'city-port-craft', 'hq-sheet-workstation'],
        ['office: City > Skills (academy)', 'city-port-skills', 'hq-sheet-academy'],
      ] as const) {
        await expect(page.getByTestId(door), `${face}: no door on the Port plate`).toBeVisible({ timeout: 60_000 })
        await page.getByTestId(door).click()
        await seen(face, sheet)
        if (door === 'city-port-craft') await expect(page.getByTestId('port-workstation')).toBeVisible({ timeout: 60_000 })
        if (door === 'city-port-skills') await expect(page.getByTestId('port-academy')).toBeVisible({ timeout: 60_000 })
        if (door === 'city-port-craft' || door === 'city-port-skills') await page.screenshot({ path: `${OUT}/${door}-${size.width}.png` })
        await back(page)
        await expect(page.getByTestId(sheet)).toHaveCount(0)
      }

      await plate(page, 'inn')
      await page.getByTestId('city-inn-crew').click()
      await seen('office: City > Inn', 'city-inn-page')
      await back(page)

      await plate(page, 'hall')
      await seen('office: City > Town (the town hall)', 'city-hall-figures')

      await page.getByTestId('city-office-invest').click()
      await seen('office: Invest', 'hq-sheet-invest')
      await expect(page.getByTestId('desk-invest')).toBeVisible()
      await back(page)
      await page.getByTestId('city-office-report').click()
      await seen('office: Report', 'hq-sheet-report')
      await expect(page.getByTestId('desk-report')).toBeVisible()
      await back(page)
      await expect(page.getByTestId('hq-sheet-report')).toHaveCount(0)

      const sideways = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)
      expect(sideways, 'HQ scrolls sideways').toBe(false)
      await page.getByTestId('city-page').evaluate((el) => el.scrollTo(0, 0))
      await page.screenshot({ path: `${OUT}/hq-${size.width}.png` })
      console.log(`[hq.desk @${size.width}] reached: ${reached.join(' | ')}`)
    })

    test(`HQ @${size.width}: the old routes open HQ, and the bar has no Trade or Office cell (H3)`, async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await page.setViewportSize(size)
      for (const [old, sheet] of [
        ['command', null],
        ['office', null],
        ['port', null],
        ['routes', null],
        ['', null],
        ['office?face=invest', 'hq-sheet-invest'],
        ['office?face=report', 'hq-sheet-report'],
        ['office?face=city&building=academy', 'hq-sheet-academy'],
      ] as const) {
        await page.goto(old)
        await expect(page.getByTestId('city-screen'), `/${old} did not open HQ`).toBeVisible({ timeout: 300_000 })
        await expect(page, `/${old} did not land on /city`).toHaveURL(/\/city(\?place=[a-z]+)?$/, { timeout: 60_000 })
        if (sheet) await expect(page.getByTestId(sheet), `/${old} did not open its sheet`).toBeVisible({ timeout: 300_000 })
      }
      await page.goto('city')
      await ready(page)
      const cells = await page.locator('[data-testid="city-rail"] a[href]').evaluateAll((els) => els.map((e) => e.getAttribute('href') ?? ''))
      expect(cells.some((h) => /\/(command|office)$/.test(h)), `the bar still links the desk or the Office: ${cells.join(' ')}`).toBe(false)
      expect(cells.some((h) => /\/city$/.test(h)), `the bar has no HQ cell: ${cells.join(' ')}`).toBe(true)
    })
  })

// ── THE SOURCE: the deleted screens stay deleted, and no file names their routes as a place to go ──────────────────────────
const SRC = path.resolve(process.cwd(), 'src')
function sources(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const full = path.join(dir, name)
    if (statSync(full).isDirectory()) sources(full, out)
    else if (/\.tsx?$/.test(name)) out.push(full)
  }
  return out
}

test('H3: the desk’s and the Office’s screens are gone, and nothing navigates to them', () => {
  for (const gone of [
    'features/command/CommandScreen.tsx',
    'features/command/OfficeScreen.tsx',
    'features/command/officeView.ts',
    'features/command/DeskShell.tsx',
    'features/command/DeskFrame.tsx',
    'features/command/FleetStrip.tsx',
    'features/command/FleetPicker.tsx',
    'features/command/city/City.tsx',
    'features/command/buysell/Trade.tsx',
    'features/command/buysell/TradeBoard.tsx',
    'live/PortTrade.tsx',
    'live/PortPrices.tsx',
    'live/PriceTray.tsx',
    'live/HaggleThread.tsx',
    'live/ManifestPanel.tsx',
    'live/tradeOnDeskKnob.ts',
    'store/deskHandoff.ts',
    'store/manifest.ts',
  ])
    expect(existsSync(path.join(SRC, gone)), `${gone} is back`).toBe(false)
  const jumps: string[] = []
  for (const file of sources(SRC)) {
    const rel = path.relative(SRC, file).split(path.sep).join('/')
    // the route table alone names the old routes: it is where they are sent to HQ
    if (rel === 'app/App.tsx') continue
    readFileSync(file, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/^\s*(\/\/|\*|\/\*|\{\/\*)/.test(line)) return
        if (/['"`]\/(command|office)\b/.test(line) || /openOfficeCity|OFFICE_TAB|TRADE_ON_DESK/.test(line)) jumps.push(`${rel}:${i + 1}  ${line.trim()}`)
      })
  }
  expect(jumps, `these lines still send the player to the desk or the Office:\n${jumps.join('\n')}`).toEqual([])
})
