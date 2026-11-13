import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { ready, reachable } from './appReady.fixture'
import { serveGearWearWorld, WORN_SHIP } from './gearWear.fixture'
import { translate } from '../src/lib/i18n'
import { wornFittings } from '../src/domain/fleet'

// ═════════════════════════════════════════════════════════════════════════════════════════════════
// GEAR WEAR ON THE GLASS (0158, the switch gear_wear_bite), lit and dark, at 390 and 320 wide, in English and Korean.
// Names this spec selects by: world.ship_racks (each unit's wear card), public.gear_repair_quote (cmd.do_repair's
// `gear`), wornFittings (src/domain/fleet, the one count), live/ShipPanel (the wear bar and the worn line),
// live/PortShipyard (the yard's Worn fittings row), live/StepQuestion and live/orderCheck (the repair tray).
//
//   lit:  her ship's sheet draws a wear bar under each fitting that wears, named in the reader's language, and says in
//         words how many are worn and how well the weakest works; the Repair face says how many are worn although the
//         hull is whole; the repair tray prices them; a repair mends them and the row is gone;
//   dark: the same worn ship, and nothing of it on the sheet or at the yard (the world as it ships).
// The worn ship is the fixture's (tests/gearWear.fixture.ts): a wear is written, never rolled, so no figure here
// depends on a world's dice. Run it: npm run build && npx vite preview --port 4425, then
//   PLAYWRIGHT_BASE_URL=http://localhost:4425/byeharu-voyage/ npx playwright test gear.wear.spec.ts
// GEAR_WEAR_SHOTS=<dir> keeps the pictures.
// ═════════════════════════════════════════════════════════════════════════════════════════════════

async function shot(page: Page, name: string) {
  const to = process.env.GEAR_WEAR_SHOTS
  if (!to) return
  mkdirSync(path.resolve(to), { recursive: true })
  await page.screenshot({ path: path.join(path.resolve(to), `${name}.png`) })
}

/** Nothing scrolls sideways and no text of `scope` stands outside the glass. */
async function fits(page: Page, scope: string, where: string) {
  const broken = await page.evaluate((sel) => {
    const out: string[] = []
    const root = document.documentElement
    if (root.scrollWidth > root.clientWidth) out.push(`the page scrolls sideways (${root.scrollWidth} > ${root.clientWidth})`)
    for (const box of document.querySelectorAll(sel)) {
      for (const el of box.querySelectorAll<HTMLElement>('*')) {
        if (el.children.length > 0 || el.getClientRects().length === 0) continue
        const text = (el.textContent ?? '').trim()
        if (text === '') continue
        const r = el.getBoundingClientRect()
        if (r.width > 0 && (r.right > window.innerWidth + 1 || r.left < -1)) out.push(`"${text}" stands outside the glass`)
      }
    }
    return out
  }, scope)
  expect(broken, where).toEqual([])
}

test('one count: wornFittings reads the served wear, and nothing when none is served', () => {
  const unit = (wear?: number, works_pct?: number) => ({ code: 'x', name: 'x', slot: 'rig', deck: 1, hands: 0, wear, works_pct })
  const rack = (fitted: ReturnType<typeof unit>[]) => ({ rack: 'mid', word: 'Mid', open: 4, locked: 0, at_level: null, fitted })
  expect(wornFittings({ ships: [] })).toEqual({ units: 0, worstWorks: null })
  // dark: no wear is served
  expect(wornFittings({ ships: [{ racks: [rack([unit(), unit()])] }, {}] })).toEqual({ units: 0, worstWorks: null })
  // lit: a new piece is served wear 0 and is not worn
  expect(wornFittings({ ships: [{ racks: [rack([unit(0, 100), unit(62, 69)])] }, { racks: [rack([unit(20, 90)])] }] })).toEqual({ units: 2, worstWorks: 69 })
})

for (const locale of ['en-US', 'ko-KR'] as const) {
  const lang = locale === 'ko-KR' ? 'ko' : 'en'
  for (const width of [390, 320] as const) {
    test.describe(`gear wear lit, ${locale} at ${width}`, () => {
      test.use({ locale, viewport: { width, height: width === 390 ? 844 : 640 } })

      test('the sheet shows the wear, the yard counts it, a repair mends it', async ({ page, request, baseURL }) => {
        test.setTimeout(600_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await serveGearWearWorld(page, true)

        // ── HER SHIP'S SHEET ────────────────────────────────────────────────────────────────────────────────
        await page.goto('fleets')
        await ready(page)
        await page.getByTestId('fleet-row').first().click()
        await page.getByTestId('fleet-page').getByTestId('ship-stats').first().click()
        const sheet = page.getByTestId('map-ship-panel')
        await expect(sheet).toBeVisible()
        const bars = sheet.getByTestId('unit-wear')
        await expect(bars).toHaveCount(WORN_SHIP.units.length, { timeout: 60_000 })
        const names = await bars.evaluateAll((els) => els.map((e) => e.getAttribute('aria-label')))
        const want = WORN_SHIP.units.map((u) =>
          u.wear === 0 ? translate(lang, 'ship.wearNew') : translate(lang, 'ship.wearWorn', { n: String(u.wear), m: String(100 - u.wear / 2) }),
        )
        expect([...names].sort(), 'each bar is named in the language shown').toEqual([...want].sort())
        const line = sheet.getByTestId('ship-worn')
        await line.scrollIntoViewIfNeeded()
        await expect(line).toContainText(translate(lang, 'ship.wornCount', { n: String(WORN_SHIP.worn) }))
        await expect(line).toContainText(translate(lang, 'ship.wornWeakest', { m: String(WORN_SHIP.weakest) }))
        await expect(sheet).not.toContainText('worn · works at')   // the server's English sentence is not on the glass
        await fits(page, '[data-testid="map-ship-panel"]', `the sheet at ${width}`)
        await shot(page, `sheet-${lang}-${width}`)

        // ── THE YARD: the hull is whole, and she still has a reason to press ───────────────────────────────────────
        await page.goto('port')
        await ready(page, { quietMs: 90_000 })
        await page.getByRole('tab', { name: translate(lang, 'town.f_shipyard'), exact: true }).click()
        const yard = page.getByTestId('port-shipyard')
        await expect(yard).toBeVisible({ timeout: 30_000 })
        const worn = yard.getByTestId('shipyard-worn')
        await expect(worn).toContainText(translate(lang, 'ship.wornFittings'))
        await expect(worn).toContainText(String(WORN_SHIP.worn))
        await fits(page, '[data-testid="port-shipyard"]', `the yard at ${width}`)
        await shot(page, `yard-${lang}-${width}`)

        // ── THE TRAY: the fittings are priced with the hull, in the language shown ───────────────────────────────
        await worn.click()
        const tray = page.getByTestId('step-tray')
        await expect(tray).toBeVisible({ timeout: 30_000 })
        await expect(tray.getByTestId('step-worn')).toContainText(String(WORN_SHIP.worn))
        const gear = tray.getByTestId('repair-gear')
        await expect(gear).toBeVisible({ timeout: 60_000 })
        await expect(gear).toContainText(translate(lang, 'books.fittings'))
        await expect(gear).not.toContainText('repaired too')
        expect(await gear.innerText(), 'the row says how many').toContain(String(WORN_SHIP.worn))
        await expect(tray.getByTestId('step-send')).toBeEnabled({ timeout: 30_000 })
        await fits(page, '[data-testid="step-tray"]', `the tray at ${width}`)
        await shot(page, `tray-${lang}-${width}`)

        // ── THE REPAIR: one press, and nothing aboard is worn ───────────────────────────────────────────────
        await tray.getByTestId('step-send').click()
        await expect(yard.getByTestId('shipyard-worn')).toHaveCount(0, { timeout: 120_000 })
        await expect(page.locator('body')).not.toContainText('E_')
        await shot(page, `repaired-${lang}-${width}`)
      })
    })
  }
}

test.describe('gear wear dark, as the world ships', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('the same worn ship: no bar on the sheet, no row at the yard', async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await serveGearWearWorld(page, false)
    await page.goto('fleets')
    await ready(page)
    await page.getByTestId('fleet-row').first().click()
    await page.getByTestId('fleet-page').getByTestId('ship-stats').first().click()
    const sheet = page.getByTestId('map-ship-panel')
    await expect(sheet.getByTestId('ship-equipment')).toBeVisible({ timeout: 60_000 })
    await expect(sheet.getByTestId('ship-rack-mid').locator('[data-fitted]').first()).toBeVisible()
    await expect(sheet.getByTestId('unit-wear')).toHaveCount(0)
    await expect(sheet.getByTestId('ship-worn')).toHaveCount(0)
    await shot(page, 'sheet-dark-390')

    await page.goto('port')
    await ready(page, { quietMs: 90_000 })
    await page.getByRole('tab', { name: 'Repair', exact: true }).click()
    await expect(page.getByTestId('port-shipyard')).toBeVisible({ timeout: 30_000 })
    await expect(page.getByTestId('shipyard-worn')).toHaveCount(0)
  })
})
