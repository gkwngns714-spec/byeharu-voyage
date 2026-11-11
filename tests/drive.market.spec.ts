import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DRIVE AUDIT, 2026-11-08 — THE MARKET, DRIVEN AS THE OWNER WOULD
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/OWNER_REQUESTS.md rows 48 (a city sells 4 to 10 goods: capital 10, mid 4-8, small 4), 257
// (the chart follows the pressed good; BUY lists the goods beneath, SELL the cargo, no page pops up;
// REQUEST only in the home city), 76/80 (the trade screen: buy, basket, no blank space) and 302
// (the Production page's cargo column). The local world: Casa de Aveiro of Portugal, home Lisbon,
// one fleet (Gaivota) docked there, 40,000 ducats, an empty hold.

const OUT = 'docs/dev-log/2026-11-08-drive-audit'
/** The pictures of the audit's D4 fix (the cargo column), kept apart from the audit's own evidence. */
const FIX_OUT = 'docs/dev-log/2026-11-08-hq-drawer-production'
const WIDE = { width: 1280, height: 800 }
const PHONE = { width: 390, height: 844 }

test.use({ deviceScaleFactor: 2 })

async function shot(page: Page, name: string, dir = OUT) {
  await page.waitForTimeout(300)
  await page.screenshot({ path: `${dir}/${name}.png` })
}

async function openCity(page: Page, request: Parameters<typeof reachable>[0], baseURL: string | undefined, size: { width: number; height: number }, port?: string) {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(size)
  await page.goto(port ? `city?port=${port}` : 'city')
  await ready(page)
  await expect(page.getByTestId('city-building-market')).toBeVisible({ timeout: 120_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
}

async function openMarket(page: Page) {
  await page.getByTestId('city-building-market').click()
  await expect(page.locator('[data-testid="city-market-buy"], [data-testid="city-market-sell"], [data-testid="city-market-requests"]').first()).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
  await page.waitForTimeout(400)
}

/** The goods on the Buy face, as the player reads them: one name per row. */
async function buyRows(page: Page): Promise<string[]> {
  const tab = page.getByRole('tab', { name: /^(Buy|구매)$/ })
  if (await tab.count()) await tab.first().click()
  await expect(page.getByTestId('city-market-buy')).toBeVisible({ timeout: 30_000 })
  // THE ONE GOODS CARD (S5): the name is the card's name line's own first text, before its class mark and any Wanted word
  const rows = page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]')
  await expect(rows.first()).toBeVisible({ timeout: 30_000 })
  return rows.getByTestId('trade-good-name').evaluateAll((els) => els.map((e) => (e.firstChild?.textContent ?? '').trim()))
}

// ── ROW 48: THE ROSTER, AS THE QUAY LISTS IT ─────────────────────────────────────────────────────
test('Market: a capital lists 10 goods, every quay 4 to 10, and the Requests door stands only in the home city (rows 48, 257)', async ({ page, request, baseURL }) => {
  // Lisbon, the home city and a capital
  await openCity(page, request, baseURL, WIDE)
  await openMarket(page)
  const lisbon = await buyRows(page)
  console.log(`Lisbon sells ${lisbon.length}: ${lisbon.join(', ')}`)
  expect(lisbon.length, 'a capital must list exactly 10 goods').toBe(10)
  await expect(page.getByRole('tab', { name: /^(Requests|요청)$/ }), 'the home city has no Requests door').toHaveCount(1)
  await shot(page, 'market-lisbon-1280@2x')

  // (80) THE BLANK SPACE: the chart's box against its card, and a goods row against its panel, at 1280.
  const bands = await page.evaluate(() => {
    const r = (sel: string) => document.querySelector(sel)?.getBoundingClientRect() ?? null
    const chart = r('[data-testid="city-market-chart"]')
    const card = r('[data-testid="city-plan"]')
    const row = r('[data-testid="city-market-buy"] [data-testid="trade-good"]')
    const panel = r('[data-testid="city-face-panel"]')
    return {
      chartW: chart ? Math.round(chart.width) : null,
      cardW: card ? Math.round(card.width) : null,
      rowW: row ? Math.round(row.width) : null,
      panelW: panel ? Math.round(panel.width) : null,
    }
  })
  console.log(`blank space @1280: chart ${bands.chartW} px in a ${bands.cardW} px card; a goods row ${bands.rowW} px in a ${bands.panelW} px panel`)

  // (302) what the Production page says of an empty hold, read for the record (the fixme below holds the law)
  await page.getByTestId('city-building-production').click()
  await expect(page.getByTestId('port-production')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
  console.log(`production cargo column (fresh company): ${(await page.getByTestId('production-cargo').innerText()).replace(/\s+/g, ' ')}`)
  await shot(page, 'production-cargo-1280@2x')

  // Cadiz, Castile-Spain's capital: 10; Porto, a working port: 4 to 8; neither is home, so no Requests door.
  for (const [code, name, lo, hi] of [
    ['CAD', 'Cadiz', 10, 10],
    ['OPO', 'Porto', 4, 10],
  ] as const) {
    await page.goto(`city?port=${code}`)
    await ready(page)
    await expect(page.getByTestId('city-name')).toContainText(name, { timeout: 60_000 })
    await openMarket(page)
    const rows = await buyRows(page)
    console.log(`${name} sells ${rows.length}: ${rows.join(', ')}`)
    expect(rows.length, `${name} lists ${rows.length} goods`).toBeGreaterThanOrEqual(lo)
    expect(rows.length, `${name} lists ${rows.length} goods`).toBeLessThanOrEqual(hi)
    await expect(page.getByRole('tab', { name: /^(Requests|요청)$/ }), `${name} is not home, yet it offers Requests`).toHaveCount(0)
  }
  await shot(page, 'market-porto-1280@2x')
})

// ── ROW 257: THE CHART FOLLOWS THE GOOD; BUY LISTS THE GOODS; A PRESS OPENS NO PAGE ──────────────
for (const size of [WIDE, PHONE]) {
  test(`Market @${size.width}: the chart follows the pressed good, a buy completes in the panel, SELL then lists the cargo, no page pops up`, async ({ page, request, baseURL }) => {
    await openCity(page, request, baseURL, size)
    const purseBefore = (await page.getByTestId('purse').innerText()).replace(/\s+/g, ' ')
    await openMarket(page)
    const names = await buyRows(page)
    expect(names.length).toBeGreaterThanOrEqual(2)
    const rows = page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]')
    const chartGood = page.getByTestId('city-market-chart-good')

    // press the SECOND good's buy cell: the chart follows it, the tray opens IN THE PANEL (no DetailPage, no Tray overlay)
    await rows.nth(1).getByRole('button', { name: /^buy/i }).first().click()
    await expect(chartGood).toHaveText(names[1], { timeout: 30_000 })
    await expect(page.locator('[data-detail-page]')).toHaveCount(0)
    await expect(page.locator('[data-tray-mode="sheet"], [data-tray-mode="side"]')).toHaveCount(0)
    const tray = page.getByTestId('trade-tray')
    await expect(tray).toBeVisible({ timeout: 30_000 })
    const inPanel = await page.evaluate(() => {
      const panel = document.querySelector('[data-testid="city-face-panel"]')
      const tray = document.querySelector('[data-testid="trade-tray"]')
      return !!panel && !!tray && panel.contains(tray)
    })
    expect(inPanel, 'the trade tray stands outside the Market panel').toBe(true)
    // what the owner sees while the tray stands: are the goods still listed beneath BUY?
    const goodsWhileTray = await rows.count()
    console.log(`@${size.width}: goods rows still listed while the tray is open: ${goodsWhileTray}`)
    await shot(page, `market-tray-${size.width}@2x`)

    // buy one unit and read what changed
    const send = page.getByTestId('trade-tray-send')
    await expect(send).toBeEnabled({ timeout: 60_000 })
    console.log(`@${size.width}: ${(await send.innerText()).replace(/\s+/g, ' ')}`)
    await send.click()
    await expect(tray).toHaveCount(0, { timeout: 60_000 })
    await expect
      .poll(async () => (await page.getByTestId('purse').innerText()).replace(/\s+/g, ' '), { timeout: 30_000 })
      .not.toBe(purseBefore)
    console.log(`@${size.width}: purse ${purseBefore} → ${(await page.getByTestId('purse').innerText()).replace(/\s+/g, ' ')}`)

    // the list is back beneath BUY; the FIRST good's press moves the chart to it
    await expect(rows.first()).toBeVisible({ timeout: 30_000 })
    await rows.nth(0).getByRole('button', { name: /^buy/i }).first().click()
    await expect(chartGood).toHaveText(names[0], { timeout: 30_000 })
    await expect(page.getByTestId('trade-tray')).toBeVisible({ timeout: 30_000 })
    // the tray's own close returns to the list
    const close = page.locator('[data-testid="trade-tray"] [data-testid="tray-close"], [data-testid="trade-tray"] button[aria-label]').first()
    if (await close.count()) await close.click()
    else await page.keyboard.press('Escape')

    // SELL lists the cargo: the good just bought, and nothing else
    await page.getByRole('tab', { name: /^(Sell|판매)$/ }).click()
    await expect(page.getByTestId('city-market-sell')).toBeVisible({ timeout: 30_000 })
    const sellRows = page.locator('[data-testid="city-market-sell"] [data-testid="trade-good"]')
    await expect(sellRows).toHaveCount(1, { timeout: 30_000 })
    await expect(sellRows.first()).toContainText(names[1])
    await shot(page, `market-sell-${size.width}@2x`)

    // the Basket is a line in the panel, never a sheet over the doors
    await page.getByRole('tab', { name: /^(Buy|구매)$/ }).click()
    await page.getByTestId('city-market-basket').click()
    await expect(page.getByTestId('city-basket')).toBeVisible()
    await expect(page.locator('[data-detail-page], [data-tray-mode="sheet"]')).toHaveCount(0)
    await page.getByTestId('city-basket-back').click()
    await expect(page.getByTestId('city-market-buy')).toBeVisible()
  })
}

// ── ROW 76, THE PHONE: THE BUTTON SAYS WHAT YOU PAY ──────────────────────────────────────────────
// O7 of the drive audit read "Buy 10 units" at 390 where 1280 read "Buy 10 units · 5,748 🪙". The sum is the server's own for the
// quantity (the dry run, src/live/useTrade.ts: a 200 ms settle plus the wire), and it reaches the phone too: replayed at both widths
// (2026-11-08) the button carried it ~250 ms after it went live; the audit read it 300 ms plus one screenshot after the tray opened,
// and the phone's screenshot was the faster one. THE LAW: a phone's button carries the sum once it is served, and it FITS — never
// cut, on the 44-px reach floor, inside its panel. In both languages.
const FIX = 'docs/dev-log/2026-11-08-axis-map-load-words'
for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`in ${locale}`, () => {
    test.use({ locale })
    test('Market @390: the send button carries the sum once the price is served, and it fits (row 76, O7)', async ({ page, request, baseURL }) => {
      await openCity(page, request, baseURL, PHONE)
      await openMarket(page)
      const rows = page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]')
      await expect(rows.nth(1)).toBeVisible({ timeout: 30_000 })
      await rows.nth(1).locator('button:enabled').first().click()
      const send = page.getByTestId('trade-tray-send')
      await expect(send).toBeEnabled({ timeout: 60_000 })
      const live = Date.now()
      await expect(send, 'the sum never reached the phone\'s button').toContainText('🪙', { timeout: 60_000 })
      const text = (await send.innerText()).replace(/\s+/g, ' ')
      console.log(`@390 ${locale}: "${text}" — the sum landed ${Date.now() - live} ms after the button went live`)
      await send.scrollIntoViewIfNeeded()
      await shot(page, `market-tray-send-390-${locale === 'ko-KR' ? 'ko' : 'en'}@2x`, FIX)
      const fit = await send.evaluate((el) => {
        const r = el.getBoundingClientRect()
        const panel = el.closest('[data-testid="city-face-panel"]')?.getBoundingClientRect()
        return {
          height: r.height,
          inside: !!panel && r.left >= panel.left - 1 && r.right <= panel.right + 1,
          cut: el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + 1,
        }
      })
      expect(fit.height, 'the button is under the 44-px reach floor').toBeGreaterThanOrEqual(44)
      expect(fit.inside, 'the button stands outside its panel').toBe(true)
      expect(fit.cut, 'the button\'s words are cut').toBe(false)
    })
  })
}

// ── ROW 302: THE PRODUCTION PAGE'S CARGO COLUMN ──────────────────────────────────────────────────
// WHAT THE DRIVE FOUND (2026-11-08, the audit's D4) on a fresh company: the cargo bar read "4 / 180 tons" and the column under
// it "Cargo empty." — the four tons are her supplies (15 days), which the bar counts (`fleetHoldUsed`: goods AND supplies, the
// one hold of DESIGN C.3) and the goods-only list did not. FIXED after #560: the list carries the supplies as a plain line
// (PortProduction.tsx, `cargo-supplies`), and "Cargo empty." stands only over a hold with nothing in it.
// THE LAW: the bar's tons on board are the sum of the list's lines (each good's tons, the supplies' tons), to the ton; the
// bar never counts tons over a list that says the cargo is empty.
test('Production: the cargo bar and the cargo list agree about the hold (row 302)', async ({ page, request, baseURL }) => {
  await openCity(page, request, baseURL, WIDE)
  await page.getByTestId('city-building-production').click()
  await expect(page.getByTestId('port-production')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('[data-testid="production-cargo"] [data-testid="cargo-bar"]')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
  const cargo = (await page.getByTestId('production-cargo').innerText()).replace(/\s+/g, ' ')
  console.log(`production cargo column: ${cargo}`)
  await shot(page, 'production-cargo-1280@2x', FIX_OUT)
  const bar = /(\d[\d,]*)\s*\/\s*(\d[\d,]*)\s*(?:tons?|톤)/.exec(cargo)
  expect(bar, 'no cargo bar figure').not.toBeNull()
  const used = Number(bar![1].replace(/,/g, ''))
  // every line of the list and the tons it says: a good's caption ("12.5 tons"), the supplies' figure
  const lines = await page.evaluate(() =>
    [...document.querySelectorAll('[data-testid="production-cargo"] [data-testid="cargo-row"], [data-testid="production-cargo"] [data-testid="cargo-supplies"]')].map((l) => {
      const m = /(\d[\d,]*(?:\.\d+)?)\s*(?:tons?|톤)/.exec(l.textContent ?? '')
      return { id: l.getAttribute('data-testid'), tons: m ? Number(m[1].replace(/,/g, '')) : null }
    }),
  )
  const listed = lines.reduce((n, l) => n + (l.tons ?? 0), 0)
  console.log(`cargo bar: ${used} tons on board; the list: ${JSON.stringify(lines)} = ${listed}`)
  for (const l of lines) expect(l.tons, `${l.id} carries no tons figure`).not.toBeNull()
  if (/Cargo empty|화물 없음/.test(cargo)) expect(used, 'the bar counts tons while the list says the cargo is empty').toBe(0)
  else expect(lines.length, `the bar counts ${used} tons and the list names nothing`).toBeGreaterThan(0)
  expect(Math.abs(listed - used), `the bar says ${used} tons on board, the list adds up to ${listed}`).toBeLessThanOrEqual(1)
})
