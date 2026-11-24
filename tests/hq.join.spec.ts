import { test, expect, type Locator, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { corpWorld } from './corpWorld.fixture'
import { serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ, JOINED INTO ONE PAGE (2026-11-24; docs/design/hq-corp-2026-11-24.md C1, C3; the join of H1, H2 and 0492's client)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE LAW, at 390 x 844 and 1440 x 900, English:
//   * THE ORDER: the Rank strip (net per hour), the workers, the best moves, Storage, the Ledger, the plates;
//   * EVERYTHING IS SAID ONCE, for a company of one fleet: her fleet's name stands once on the page; no figure stands in two areas
//     (the strip, While away, the workers, the best moves, Storage, the Ledger); there is ONE per-hour figure of the company (the
//     strip's), ONE While away, and no second Fleets section; checked while she lies idle and again once she works;
//   * THE BOARD IS READ ONCE: one world.hq_board request by the time the page stands;
//   * 0492, its switch lit: Assign offers Bring home and Once / Repeat / a count; a run bought away and brought home, once, is taken
//     by the server and her row says "... · Store";
//   * 0492, its switch dark: the first press that asks for a count is refused in the server's words, the two choices leave the
//     sheet, and the plain run then commits.

const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const
const OUT = process.env.HQ_SHOTS ?? 'test-results/hq-join'

/** The areas of the company on HQ, each by its test id. */
const AREAS = ['hq-bridge', 'hq-away', 'corp-workers', 'hq-board', 'corp-warehouse', 'corp-ledger'] as const

/** Each area's figures as drawn: every number of three digits or more, its sign and its commas dropped. */
const figuresByArea = (page: Page) =>
  page.evaluate((areas) => {
    const out: Record<string, string[]> = {}
    for (const id of areas) {
      const el = document.querySelector<HTMLElement>(`[data-testid="${id}"]`)
      if (!el) continue
      const found = (el.innerText.match(/\d[\d,]*\d/g) ?? []).map((s) => s.replace(/,/g, '')).filter((s) => s.length >= 3)
      out[id] = [...new Set(found)]
    }
    return out
  }, AREAS)

/** The figures that stand in more than one area. */
function repeated(by: Record<string, string[]>): string[] {
  const seen = new Map<string, string>()
  const twice: string[] = []
  for (const [area, figures] of Object.entries(by))
    for (const f of figures) {
      const first = seen.get(f)
      if (first) twice.push(`${f} in ${first} and ${area}`)
      else seen.set(f, area)
    }
  return twice
}

/** How many times `word` stands in the page's drawn text. */
const timesOnPage = (page: Page, word: string) => page.evaluate((w) => document.querySelector<HTMLElement>('[data-testid="city-page"]')!.innerText.split(w).length - 1, word)

async function saidOnce(page: Page, fleetName: string, when: string) {
  expect(await timesOnPage(page, fleetName), `${when}: her fleet's name does not stand exactly once on HQ`).toBe(1)
  expect(repeated(await figuresByArea(page)), `${when}: a figure stands in two areas of HQ`).toEqual([])
  expect(await timesOnPage(page, '/ hour') - (await page.locator('[data-testid="hq-move"]:has-text("/ hour")').count()), `${when}: more than one per-hour figure of the company`).toBeLessThanOrEqual(1)
  expect(await timesOnPage(page, 'While away'), `${when}: While away stands more than once`).toBeLessThanOrEqual(1)
  for (const id of ['hq-fleets', 'hq-fleet', 'hq-job-control', 'hq-move-repeat', 'corp-ledger-rate', 'hq-bridge-purse']) await expect(page.getByTestId(id), `${when}: ${id} is drawn`).toHaveCount(0)
}

/** The whole page as one picture: HQ scrolls inside its own pane, so the glass is made as tall as the pane's content for the shot. */
async function fullShot(page: Page, path: string, size: { width: number; height: number }) {
  const extra = await page.evaluate(() =>
    Math.max(0, ...[...document.querySelectorAll<HTMLElement>('*')].filter((el) => /auto|scroll/.test(getComputedStyle(el).overflowY)).map((el) => el.scrollHeight - el.clientHeight)),
  )
  await page.setViewportSize({ width: size.width, height: size.height + extra })
  await page.waitForTimeout(400)
  await page.screenshot({ path, fullPage: true })
  await page.setViewportSize(size)
}

async function open(page: Page, size: { width: number; height: number }, home: boolean) {
  await serveWorldImage(page, await corpWorld({ courses: true, home }))
  await page.setViewportSize(size)
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('corp-worker-list')).toBeVisible({ timeout: 300_000 })
  await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'served', { timeout: 180_000 })
}

const fleetRow = (page: Page) => page.locator('[data-testid="corp-worker"][data-kind="fleet"]').first()

/** Assign's press, and whether the server took it (the sheet closed) or refused it (its words stand). */
async function pressGo(sheet: Locator): Promise<boolean> {
  await sheet.getByTestId('corp-assign-go').click()
  await expect.poll(async () => (await sheet.count()) === 0 || (await sheet.getByTestId('corp-assign-refusal').count()) > 0, { timeout: 120_000 }).toBe(true)
  return (await sheet.count()) === 0
}

for (const size of SIZES) {
  test(`HQ @${size.width}: one order, the board read once, and nothing said twice for a company of one fleet`, async ({ page, request, baseURL }) => {
    test.setTimeout(900_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    // every ask the page makes prints one debug line (src/lib/rpc/backend.ts): the board's are counted
    let boardAsks = 0
    page.on('console', (m) => {
      if (m.type() === 'debug' && m.text().includes('world.hq_board(')) boardAsks++
    })
    await open(page, size, false)
    await expect(page.locator('[data-testid="hq-moves"] [data-testid="hq-move"]').first()).toBeVisible({ timeout: 180_000 })
    await expect(page.getByTestId('hq-bridge-rate')).toBeVisible({ timeout: 180_000 })

    // THE ORDER (C1)
    const tops: number[] = []
    for (const id of ['hq-bridge', 'corp-workers', 'hq-board', 'corp-warehouse', 'corp-ledger', 'city-buildings']) {
      const el = page.getByTestId(id)
      await expect(el, `${id} is not on HQ`).toBeVisible({ timeout: 120_000 })
      tops.push((await el.boundingBox())!.y)
    }
    expect(tops, 'the areas are not in the order Rank strip, Workers, Best moves, Storage, Ledger, plates').toEqual([...tops].sort((a, b) => a - b))

    // THE BOARD IS READ ONCE (world.hq_board: the strip, the moves and the Ledger share the one read)
    await expect(page.getByTestId('corp-ledger')).toBeVisible({ timeout: 120_000 })
    expect(boardAsks, 'the board was asked more than once to draw HQ').toBe(1)
    const fleetName = (await fleetRow(page).getByTestId('corp-worker-name').innerText()).trim()
    expect(fleetName.length).toBeGreaterThan(0)
    await expect(page.locator('[data-testid="corp-worker"][data-kind="fleet"]')).toHaveCount(1)

    // SAID ONCE, while she lies idle
    await saidOnce(page, fleetName, 'idle')
    await fullShot(page, `${OUT}/hq-idle-${size.width}.png`, size)

    // she takes the top trade card's run through Assign, and works
    const card = page.locator('[data-testid="hq-moves"] [data-testid="hq-move"][data-kind="trade"][data-act="cmd.issue_lines"]')
    const cards = await card.count()
    let assigned = false
    for (let i = 0; i < cards && !assigned; i++) {
      await card.nth(i).click()
      const sheet = page.getByTestId('hq-sheet-assign')
      await expect(sheet).toBeVisible({ timeout: 60_000 })
      await expect(sheet.getByTestId('corp-assign-quote')).toBeVisible({ timeout: 120_000 })
      assigned = await pressGo(sheet)
      if (!assigned) {
        await page.keyboard.press('Escape')
        await expect(sheet).toHaveCount(0)
      }
    }
    expect(assigned, 'no trade card could be assigned').toBe(true)
    await expect(fleetRow(page)).toHaveAttribute('data-state', 'working', { timeout: 120_000 })
    await expect(page.getByTestId('hq-away'), 'While away does not say what her job did').toBeVisible({ timeout: 120_000 })
    await expect(fleetRow(page).locator('[data-figure="runs"], [data-figure="earned"]'), 'her row repeats While away').toHaveCount(0)

    // SAID ONCE, once she works
    await saidOnce(page, fleetName, 'working')
    expect(await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth), 'HQ scrolls sideways').toBe(false)
    await fullShot(page, `${OUT}/hq-working-${size.width}.png`, size)
  })

  test(`Assign @${size.width}: Bring home, once, where 0492's switch is lit`, async ({ page, request, baseURL }) => {
    test.setTimeout(900_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await open(page, size, true)
    const sheet = page.getByTestId('hq-sheet-assign')
    const card = page.locator('[data-testid="hq-moves"] [data-testid="hq-move"][data-kind="trade"][data-act="cmd.issue_lines"]')
    await expect(card.first()).toBeVisible({ timeout: 180_000 })
    const cards = await card.count()

    // a card's good, bought at a harbour away from home: from home itself there is nothing to bring home, and the sheet says so
    let assigned = false
    const said: string[] = []
    for (let c = 0; c < cards && !assigned; c++) {
      await card.nth(c).click()
      await expect(sheet.getByTestId('corp-assign-quote')).toBeVisible({ timeout: 120_000 })
      await sheet.getByRole('tab', { name: 'Bring home' }).click()
      await expect(sheet.getByTestId('corp-assign-athome'), 'buying at home and bringing it home is offered').toBeVisible()
      await expect(sheet.getByTestId('corp-assign-go')).toBeDisabled()
      const away = sheet.locator('[data-testid="corp-assign-buy"][aria-pressed="false"]')
      if ((await away.count()) > 0) {
        await away.first().click()
        const quote = sheet.locator('[data-testid="corp-assign-quote"][data-end="store"]')
        await expect(quote, 'no quote for a run brought home').toBeVisible({ timeout: 120_000 })
        expect(Number(await quote.getAttribute('data-units')), 'the quote has no units').toBeGreaterThan(0)
        await sheet.getByRole('tab', { name: 'Once' }).click()
        await expect(sheet.getByTestId('corp-assign-go')).toHaveAttribute('data-end', 'store')
        await expect(sheet.getByTestId('corp-assign-go')).toHaveAttribute('data-times', '1')
        expect(await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth), 'Assign scrolls sideways').toBe(false)
        await page.screenshot({ path: `${OUT}/assign-home-${size.width}.png` })
        assigned = await pressGo(sheet)
        if (!assigned) {
          const words = await sheet.getByTestId('corp-assign-refusal').innerText()
          expect(words, 'the lit door refused Bring home as not open').not.toContain('not open')
          said.push(words)
        }
      }
      if (!assigned) {
        await page.keyboard.press('Escape')
        await expect(sheet).toHaveCount(0)
      }
    }
    expect(assigned, `no card's good could be bought away and brought home: ${said.join(' | ')}`).toBe(true)
    const row = fleetRow(page)
    await expect(row).toHaveAttribute('data-action', 'fixed', { timeout: 120_000 })
    await expect(row.getByTestId('corp-worker-action')).toHaveText(/.+ · .+ → .+ · Store$/)
    await expect(row.locator('[data-figure="left"]'), 'a counted job does not say its runs left').toBeVisible()
    await fullShot(page, `${OUT}/hq-home-${size.width}.png`, size)
  })
}

test("Assign: 0492's switch dark: a count is refused in the server's words, leaves the sheet, and the plain run commits", async ({ page, request, baseURL }) => {
  test.setTimeout(900_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await open(page, SIZES[0], false)
  const card = page.locator('[data-testid="hq-moves"] [data-testid="hq-move"][data-kind="trade"][data-act="cmd.issue_lines"]').first()
  await expect(card).toBeVisible({ timeout: 180_000 })
  await card.click()
  const sheet = page.getByTestId('hq-sheet-assign')
  await expect(sheet.getByTestId('corp-assign-quote')).toBeVisible({ timeout: 120_000 })
  await expect(sheet.getByTestId('corp-assign-sea')).toHaveAttribute('data-home-open', 'true')
  await sheet.getByRole('tab', { name: 'Once' }).click()
  await sheet.getByTestId('corp-assign-go').click()
  const refusal = sheet.getByTestId('corp-assign-refusal')
  await expect(refusal).toBeVisible({ timeout: 120_000 })
  await expect(refusal).toContainText('not open')
  expect((await sheet.innerText()).match(/E_[A-Z_]+/g) ?? [], 'a code is printed in Assign').toEqual([])
  await expect(sheet.getByTestId('corp-assign-sea')).toHaveAttribute('data-home-open', 'false')
  await expect(sheet.getByRole('tab', { name: 'Bring home' })).toHaveCount(0)
  await expect(sheet.getByRole('tab', { name: 'Once' })).toHaveCount(0)
  // the plain run (Sell, Repeat) is today's call
  await expect(sheet.getByTestId('corp-assign-go')).not.toHaveAttribute('data-times')
  await sheet.getByTestId('corp-assign-go').click()
  await expect(sheet).toHaveCount(0, { timeout: 120_000 })
  await expect(fleetRow(page)).toHaveAttribute('data-action', 'fixed', { timeout: 120_000 })
})

test('Assign: where she lies, a run is quoted for what her purse can buy, never for the bare hold', async ({ page, request, baseURL }) => {
  test.setTimeout(900_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await open(page, SIZES[0], false)
  const purse = Number((await page.getByTestId('purse').innerText()).replace(/[^0-9]/g, ''))
  expect(purse, 'no purse on the top bar').toBeGreaterThan(0)
  // from her row (no card's units): the sheet asks the server what she can buy (world.buy_capacity) and quotes that
  await fleetRow(page).click()
  const sheet = page.getByTestId('hq-sheet-assign')
  await expect(sheet.getByTestId('corp-assign-good').first()).toBeVisible({ timeout: 120_000 })
  const goods = await sheet.getByTestId('corp-assign-good').count()
  let quoted = 0
  for (let g = 0; g < goods; g++) {
    await sheet.getByTestId('corp-assign-good').nth(g).click()
    await expect(sheet.getByTestId('corp-assign-sales').or(sheet.getByTestId('corp-assign-nosale')).or(sheet.getByTestId('corp-assign-nobuy'))).toBeVisible({ timeout: 120_000 })
    if ((await sheet.getByTestId('corp-assign-sale').count()) === 0) continue
    await sheet.getByTestId('corp-assign-sale').first().click()
    const quote = sheet.getByTestId('corp-assign-quote')
    await expect(quote).toBeVisible()
    const cost = Number(await quote.getAttribute('data-cost'))
    expect(Number(await quote.getAttribute('data-units')), `good ${g}: a quote for no units`).toBeGreaterThan(0)
    expect(cost, `good ${g}: the run is quoted at ${cost}, more than her purse of ${purse}`).toBeLessThanOrEqual(purse)
    await expect(quote).toHaveAttribute('data-over', 'false')
    quoted++
  }
  expect(quoted, 'no good was quoted').toBeGreaterThan(0)
})
