import { test, expect, type Locator, type Page } from '@playwright/test'
import { readdirSync } from 'node:fs'
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
//   * ASSIGN IS world.actions' ANSWER (0496), asked once for each opening: a card opens it on the card's own run where the server
//     offers that run; every run is within her purse; the runs stand in the order of the served coin an hour;
//   * 0492, its switch lit: Assign offers Once / Repeat / a count, and Bring home WHERE THE SERVER OFFERS IT (never at home: the
//     server offers none there); a run bought away and brought home, once, is taken by the server and her row says "... · Store";
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
  // (one read of the page: the board's cards may change between two)
  const perHour = await page.evaluate(() => {
    const said = (e: Element) => (e as HTMLElement).innerText.split('/ hour').length - 1
    return said(document.querySelector('[data-testid="city-page"]')!) - [...document.querySelectorAll('[data-testid="hq-move"]')].filter((e) => said(e) > 0).length
  })
  expect(perHour, `${when}: more than one per-hour figure of the company`).toBeLessThanOrEqual(1)
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

async function open(page: Page, size: { width: number; height: number }, home: boolean, near: { near?: boolean; nearLow?: boolean } = {}) {
  await serveWorldImage(page, await corpWorld({ courses: true, home, ...near }))
  await page.setViewportSize(size)
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('corp-worker-list')).toBeVisible({ timeout: 300_000 })
  await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'served', { timeout: 180_000 })
}

const fleetRow = (page: Page) => page.locator('[data-testid="corp-worker"][data-kind="fleet"]').first()

/** The sheet stands on a run: the card's own where the server offers it, else the first the server offers. */
async function onARun(sheet: Locator) {
  await expect(sheet.getByTestId('corp-assign-runs').or(sheet.getByTestId('corp-assign-norun'))).toBeVisible({ timeout: 180_000 })
  if ((await sheet.getByTestId('corp-assign-quote').count()) === 0) await sheet.getByTestId('corp-assign-run').first().click()
  await expect(sheet.getByTestId('corp-assign-quote')).toBeVisible({ timeout: 60_000 })
}

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
    let actionAsks = 0
    page.on('console', (m) => {
      if (m.type() === 'debug' && m.text().includes('world.hq_board(')) boardAsks++
      if (m.type() === 'debug' && m.text().includes('world.actions(')) actionAsks++
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
    let opened = 0
    for (let i = 0; i < cards && !assigned; i++) {
      await card.nth(i).click()
      opened++
      const sheet = page.getByTestId('hq-sheet-assign')
      await expect(sheet).toBeVisible({ timeout: 60_000 })
      await onARun(sheet)
      expect(actionAsks, 'Assign did not ask world.actions once for each opening').toBe(opened)
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
    // AT HOME the server offers no Bring home (there is nothing to bring home from home), so the sheet offers none; Once is offered
    const row0 = fleetRow(page)
    await row0.click()
    await expect(sheet.getByTestId('corp-assign-run').first()).toBeVisible({ timeout: 180_000 })
    await expect(sheet.getByRole('tab', { name: 'Bring home' }), 'Bring home is offered at home').toHaveCount(0)
    // she sails ONE run to the nearest sale, the shortest the server offers, and lies there
    // (the runs that lose are listed when asked for: the nearest may be one of them)
    if ((await sheet.getByTestId('corp-assign-losses').count()) > 0) await sheet.getByTestId('corp-assign-losses').click()
    const spans = await sheet.getByTestId('corp-assign-run').evaluateAll((els) => els.map((el) => Number(el.getAttribute('data-interval'))))
    const order = spans.map((v, i) => ({ v, i })).sort((x, y) => x.v - y.v)
    let away = false
    for (const { i } of order) {
      await sheet.getByTestId('corp-assign-run').nth(i).click()
      await sheet.getByRole('tab', { name: 'Once' }).click()
      await expect(sheet.getByTestId('corp-assign-go')).toHaveAttribute('data-times', '1')
      away = await pressGo(sheet)
      if (away) break
    }
    expect(away, 'no run could be sailed once').toBe(true)
    await expect(row0).toHaveAttribute('data-action', 'fixed', { timeout: 120_000 })
    await expect(row0.getByTestId('corp-worker-bar'), 'she did not sail').toHaveAttribute('data-on', 'true', { timeout: 180_000 })
    await expect(row0, 'she did not arrive at her sale').toHaveAttribute('data-waiting', 'true', { timeout: 600_000 })

    // AWAY FROM HOME: her sheet's Change opens Assign, and the server offers Bring home
    let assigned = false
    const said: string[] = []
    await row0.click()
    await page.getByTestId('hq-sheet-worker').getByTestId('corp-sheet-change').click()
    await expect(sheet.getByTestId('corp-assign-run').first()).toBeVisible({ timeout: 180_000 })
    await sheet.getByRole('tab', { name: 'Bring home' }).click()
    const loads = sheet.locator('[data-testid="corp-assign-runs"][data-end="store"] [data-testid="corp-assign-run"]')
    await expect(loads.first(), 'the server offers nothing to bring home away from home').toBeVisible({ timeout: 60_000 })
    const n = await loads.count()
    for (let c = 0; c < n && !assigned; c++) {
      await loads.nth(c).click()
      const quote = sheet.locator('[data-testid="corp-assign-quote"][data-end="store"]')
      await expect(quote, 'no quote for a run brought home').toBeVisible({ timeout: 60_000 })
      expect(Number(await quote.getAttribute('data-units')), 'the quote has no units').toBeGreaterThan(0)
      expect(await quote.getAttribute('data-units'), 'the units of the foot are not the served option\u2019s').toBe(await loads.nth(c).getAttribute('data-units'))
      await sheet.getByRole('tab', { name: 'Once' }).click()
      await expect(sheet.getByTestId('corp-assign-go')).toHaveAttribute('data-end', 'store')
      await expect(sheet.getByTestId('corp-assign-go')).toHaveAttribute('data-times', '1')
      expect(await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth), 'Assign scrolls sideways').toBe(false)
      if (c === 0) await page.screenshot({ path: `${OUT}/assign-home-${size.width}.png` })
      assigned = await pressGo(sheet)
      if (!assigned) {
        const words = await sheet.getByTestId('corp-assign-refusal').innerText()
        expect(words, 'the lit door refused Bring home as not open').not.toContain('not open')
        said.push(words)
      }
    }
    expect(assigned, `nothing the server offered could be brought home: ${said.join(' | ')}`).toBe(true)
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
  await onARun(sheet)
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

test('Assign: every run the server offers is within her purse, in the order of the served coin an hour, from one request', async ({ page, request, baseURL }) => {
  test.setTimeout(900_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  let actionAsks = 0
  page.on('console', (m) => {
    if (m.type() === 'debug' && m.text().includes('world.actions(')) actionAsks++
  })
  await open(page, SIZES[0], false)
  const purse = Number((await page.getByTestId('purse').innerText()).replace(/[^0-9]/g, ''))
  expect(purse, 'no purse on the top bar').toBeGreaterThan(0)
  // from her row: the sheet draws what world.actions served, and asks nothing else of the market
  await fleetRow(page).click()
  const sheet = page.getByTestId('hq-sheet-assign')
  const runs = sheet.getByTestId('corp-assign-run')
  await expect(runs.first()).toBeVisible({ timeout: 180_000 })
  const n = await runs.count()
  const rates: number[] = []
  for (let g = 0; g < n; g++) {
    await runs.nth(g).click()
    const quote = sheet.getByTestId('corp-assign-quote')
    await expect(quote).toHaveAttribute('data-id', (await runs.nth(g).getAttribute('data-id'))!)
    const cost = Number(await quote.getAttribute('data-cost'))
    expect(Number(await quote.getAttribute('data-units')), `run ${g}: a quote for no units`).toBeGreaterThan(0)
    expect(cost, `run ${g}: quoted at ${cost}, more than her purse of ${purse}`).toBeLessThanOrEqual(purse)
    // the coin an hour drawn is the served figure, digit for digit
    const rate = quote.getByTestId('corp-assign-rate')
    const servedRate = Number(await rate.getAttribute('data-per-hour'))
    expect((await rate.innerText()).replace(/[^0-9]/g, ''), `run ${g}: the coin an hour drawn is not the served one`).toBe(String(Math.abs(servedRate)))
    rates.push(servedRate)
  }
  expect(n, 'no run was offered').toBeGreaterThan(0)
  expect(rates, 'the runs are not in the order of the served coin an hour').toEqual([...rates].sort((x, y) => y - x))
  await expect(sheet.locator('[data-over]'), 'an over-purse mark is drawn').toHaveCount(0)
  expect(actionAsks, 'the sheet asked world.actions more than once').toBe(1)
  await page.screenshot({ path: `${OUT}/assign-runs-${SIZES[0].width}.png` })
})

// ═══════════════════════════════════════════════════════════════════════════════
// 0498 THE NEAR ROUND AND 0497 THE WAIT, where their switches are lit
// ═══════════════════════════════════════════════════════════════════════════════
//   * "Trade nearby" is Assign's FIRST choice and the one the sheet opens on; its words are the served base's ("Trade near Lisbon");
//     no rate is drawn (the server serves none); one world.actions request; assigned, her row says it and she sails;
//   * a job that waits for a price is NOT shown as stopped: her row says "Prices low" with the clock to the server's next ask.
/** 0499 (near-round) is in this chain (so in the built image): without it the server serves no near round and no wait, and those two tests do not run. */
const HAS_NEAR = readdirSync('supabase/migrations').some((f) => /_near_round\.sql$/.test(f))
// NOT REGISTERED where they cannot run (no skip: CI's floor counts every registered test; the way tests/korean.paused.ts does it)
const testNear = (HAS_NEAR ? test : () => undefined) as typeof test
const testUnless = (HAS_NEAR ? () => undefined : test) as typeof test

testUnless('Assign: where the server serves no near round, Trade nearby is not drawn', async ({ page, request, baseURL }) => {
  test.setTimeout(900_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await open(page, SIZES[0], false)
  await fleetRow(page).click()
  const sheet = page.getByTestId('hq-sheet-assign')
  await expect(sheet.getByTestId('corp-assign-run').first()).toBeVisible({ timeout: 180_000 })
  await expect(sheet.getByRole('tab', { name: 'Trade nearby' })).toHaveCount(0)
  await expect(sheet.getByRole('tab').first()).toHaveText('Sea trade')
  await expect(page.locator('[data-testid="corp-worker"][data-wait]'), 'a row says it waits for a price though the server serves no wait').toHaveCount(0)
})

test('Assign: a read that took too long once is asked again by itself, and nothing is said', async ({ page, request, baseURL }) => {
  test.setTimeout(900_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  let actionAsks = 0
  page.on('console', (m) => {
    if (m.type() === 'debug' && m.text().includes('world.actions(')) actionAsks++
  })
  await serveWorldImage(page, await corpWorld({ courses: true, slow: 1 }))
  await page.setViewportSize(SIZES[0])
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('corp-worker-list')).toBeVisible({ timeout: 300_000 })
  await fleetRow(page).click()
  const sheet = page.getByTestId('hq-sheet-assign')
  const waiting = sheet.getByTestId('corp-assign-waiting')
  const runs = sheet.getByTestId('corp-assign-run')
  await expect(waiting.or(runs.first())).toBeVisible({ timeout: 180_000 })
  await expect(sheet.getByTestId('corp-assign-closed')).toHaveCount(0)
  await expect(runs.first(), 'the quiet retry did not bring the runs').toBeVisible({ timeout: 180_000 })
  await expect(sheet.getByTestId('corp-assign-slow')).toHaveCount(0)
  expect(actionAsks, 'asked once, and once more by itself').toBe(2)
})

test('Assign: a read that stays too long says so in plain words after three quiet tries, and Try again asks once more', async ({ page, request, baseURL }) => {
  test.setTimeout(900_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  let actionAsks = 0
  page.on('console', (m) => {
    if (m.type() === 'debug' && m.text().includes('world.actions(')) actionAsks++
  })
  await serveWorldImage(page, await corpWorld({ courses: true, slow: 4 }))
  await page.setViewportSize(SIZES[0])
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('corp-worker-list')).toBeVisible({ timeout: 300_000 })
  await fleetRow(page).click()
  const sheet = page.getByTestId('hq-sheet-assign')
  const slow = sheet.getByTestId('corp-assign-slow')
  await expect(slow).toBeVisible({ timeout: 180_000 })
  await expect(slow.getByTestId('corp-assign-closed')).toContainText('slow')
  expect((await sheet.innerText()).match(/E_[A-Z_]+/g) ?? [], 'a code is printed in Assign').toEqual([])
  await expect(sheet.getByTestId('corp-assign-run'), 'a shorter list is drawn beside the slow answer').toHaveCount(0)
  expect(actionAsks, 'asked once, and three times by itself').toBe(4)
  const retry = slow.getByTestId('corp-assign-retry')
  const box = (await retry.boundingBox())!
  expect(box.height, 'Try again is under 44 px').toBeGreaterThanOrEqual(43.5)
  await page.screenshot({ path: `${OUT}/assign-slow-${SIZES[0].width}.png` })
  await retry.click()
  await expect(sheet.getByTestId('corp-assign-run').first(), 'Try again did not bring the runs').toBeVisible({ timeout: 180_000 })
  await expect(slow).toHaveCount(0)
  expect(actionAsks, 'Try again did not ask world.actions exactly once more').toBe(5)
})

for (const size of SIZES) {
  testNear(`Assign @${size.width}: Trade nearby is the first choice; assigned, she works a near round`, async ({ page, request, baseURL }) => {
    test.setTimeout(900_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    let actionAsks = 0
    page.on('console', (m) => {
      if (m.type() === 'debug' && m.text().includes('world.actions(')) actionAsks++
    })
    await open(page, size, false, { near: true })
    await fleetRow(page).click()
    const sheet = page.getByTestId('hq-sheet-assign')
    const tabs = sheet.getByRole('tab')
    await expect(tabs.first()).toHaveText('Trade nearby', { timeout: 180_000 })
    await expect(tabs.first(), 'the sheet does not open on Trade nearby').toHaveAttribute('aria-selected', 'true')
    const foot = sheet.getByTestId('corp-assign-near')
    await expect(foot).toContainText('Trade near Lisbon')
    await expect(foot).toHaveAttribute('data-basis', 'none')
    await expect(sheet.getByTestId('corp-assign-rate'), 'a rate is drawn for the near round, which serves none').toHaveCount(0)
    expect(await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth), 'Assign scrolls sideways').toBe(false)
    await page.screenshot({ path: `${OUT}/assign-near-${size.width}.png` })
    expect(await pressGo(sheet), 'the server refused the near round it offered').toBe(true)
    expect(actionAsks, 'Assign asked world.actions more than once').toBe(1)
    const row = fleetRow(page)
    await expect(row).toHaveAttribute('data-action', 'near', { timeout: 120_000 })
    await expect(row.getByTestId('corp-worker-action')).toHaveText('Trade near Lisbon')
    await expect(row.getByTestId('corp-worker-bar'), 'she did not sail on her round').toHaveAttribute('data-on', 'true', { timeout: 180_000 })
    await expect(row.locator('[data-testid="corp-worker-rate"]'), 'a rate is drawn where none is served').toHaveCount(0)
    await page.getByTestId('corp-workers').scrollIntoViewIfNeeded()
    await page.screenshot({ path: `${OUT}/near-working-${size.width}.png` })
  })

  testNear(`HQ @${size.width}: a job that waits for a price says "Prices low" with its retry clock, and is not stopped`, async ({ page, request, baseURL }) => {
    test.setTimeout(900_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await open(page, size, false, { near: true, nearLow: true })
    await fleetRow(page).click()
    const sheet = page.getByTestId('hq-sheet-assign')
    await expect(sheet.getByTestId('corp-assign-near')).toBeVisible({ timeout: 180_000 })
    expect(await pressGo(sheet), 'the server refused the near round it offered').toBe(true)
    const row = fleetRow(page)
    await expect(row, 'her row does not say she waits for a price').toHaveAttribute('data-wait', 'low', { timeout: 180_000 })
    await expect(row, 'a waiting job is drawn as stopped').toHaveAttribute('data-state', 'working')
    await expect(row.getByTestId('corp-worker-state')).toHaveText('Prices low')
    const retry = row.getByTestId('corp-worker-retry')
    await expect(retry, 'no clock to the next ask').toBeVisible()
    const c0 = await retry.innerText()
    expect(c0, 'the retry clock is empty').toMatch(/\d/)
    await expect.poll(async () => retry.innerText(), { timeout: 30_000, message: 'the retry clock does not move' }).not.toBe(c0)
    await expect(row.getByTestId('corp-worker-bar')).toHaveAttribute('data-on', 'false')
    expect(await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth), 'HQ scrolls sideways').toBe(false)
    await page.getByTestId('corp-workers').scrollIntoViewIfNeeded()
    await page.screenshot({ path: `${OUT}/prices-low-${size.width}.png` })
  })
}
