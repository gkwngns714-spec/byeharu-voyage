import { test, expect, type Page } from '@playwright/test'
import { rankMoves, perHourOf, REQUEST_FLOOR_S, type Move } from '../src/domain/hq'
import { reachable, ready, WORLD_BOOT_MS } from './appReady.fixture'
import { serveHqLit } from './hqLit.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ'S COMMAND BOARD, v1 (owner, 2026-11-23: "all the work (activities) are done in HQ … choosing best options available, finding best
// options"; docs/design/hq-command-2026-11-23.md).
//
// Pure: the one ranking rule (domain/hq): the yard first, then trade runs and requests by coin per hour, then crew, then invest.
// Browser (the shipped world with production's switches lit, the sea limits dark; a fresh company, one barca at Lisbon):
//   - the bridge renders: coin, the fleets as ships, what is next, the pirate mark
//   - the best moves: the trade cards stand by coin per hour, the best first
//   - a trade card's press starts the same plan the desk's best-sale press does (the desk's trip, that good, sold there)
//   - an idle fleet glows and shows its best card inline
//   - no sideways scroll at 320, 390 and 1280
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const move = (id: string, kind: Move['kind'], perHour: number | null, gain: number | null = null): Move => ({
  id,
  kind,
  perHour,
  gain,
  seconds: null,
  fleet: null,
  data: null,
})

test.describe('the ranking rule', () => {
  test('the yard first, then trade and requests by coin per hour, then crew, then invest', () => {
    const order = rankMoves([
      move('invest', 'invest', null, 90_000),
      move('crew', 'crew', null),
      move('slow', 'trade', 100, 5_000),
      move('none', 'trade', null, 9_000),
      move('fast', 'trade', 900, 1_000),
      move('req', 'request', 400, 100),
      move('yard', 'yard', null, 52_000),
    ]).map((m) => m.id)
    expect(order).toEqual(['yard', 'fast', 'req', 'slow', 'none', 'crew', 'invest'])
  })
  test('coin per hour is the gain over the served time; a request takes a quarter hour', () => {
    expect(perHourOf(1_000, 1_800)).toBe(2_000)
    expect(perHourOf(1_000, null)).toBeNull()
    expect(perHourOf(1_000, 0)).toBeNull()
    expect(perHourOf(100, REQUEST_FLOOR_S)).toBe(400)
  })
  test('ties go to the bigger figure, then the id, so a card does not jump', () => {
    expect(rankMoves([move('b', 'trade', 10, 5), move('a', 'trade', 10, 5), move('c', 'trade', 10, 9)]).map((m) => m.id)).toEqual(['c', 'a', 'b'])
  })
})

async function openHq(page: Page, width: number, height: number, served = false, jobs = false, contracts = false) {
  await page.setViewportSize({ width, height })
  await serveHqLit(page, { served, jobs, contracts })
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('hq-board')).toBeVisible({ timeout: WORLD_BOOT_MS })
}

const sideScroll = (page: Page) =>
  page.evaluate(() => {
    const over = [...document.querySelectorAll('[data-sheet], body, html')].some((el) => el.scrollWidth > el.clientWidth + 1)
    return over || document.documentElement.scrollWidth > window.innerWidth
  })

test.describe('the board, driven', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('the bridge, the ranked trade cards, the idle fleet, and the press that starts the desk\'s plan', async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    test.setTimeout(600_000)
    await openHq(page, 390, 844)

    // THE BRIDGE
    const bridge = page.getByTestId('hq-bridge')
    await expect(bridge).toBeVisible()
    for (const id of ['hq-bridge-purse', 'hq-bridge-fleets', 'hq-bridge-next', 'hq-bridge-threat']) await expect(page.getByTestId(id)).toBeVisible()
    await expect(page.getByTestId('hq-bridge-purse')).toContainText(/\d/)
    await expect(page.getByTestId('hq-bridge-fleets').locator('[data-ship-picture]')).toHaveCount(1)
    // the board is the first thing seen: it begins on the first glass, above the city's buildings
    const board = (await page.getByTestId('hq-board').boundingBox())!
    const places = (await page.getByTestId('city-buildings').boundingBox())!
    expect(board.y).toBeLessThan(844)
    expect(board.y).toBeLessThan(places.y)

    // THE BEST MOVES: the trade cards, by coin per hour, the best first
    const trades = page.locator('[data-testid="hq-moves"] [data-testid="hq-move"][data-kind="trade"]')
    await expect(trades.first()).toBeVisible({ timeout: 180_000 })
    const rates = (await trades.evaluateAll((els) => els.map((e) => e.getAttribute('data-per-hour') ?? ''))).filter((r) => r !== '').map(Number)
    expect(rates.length, 'trade cards with a served time').toBeGreaterThan(0)
    expect(rates, 'trade cards stand by coin per hour').toEqual([...rates].sort((a, b) => b - a))

    // AN IDLE FLEET GLOWS AND OFFERS ITS BEST CARD INLINE (the same card as the board's best for her)
    const idle = page.locator('[data-testid="hq-fleet"][data-job="idle"]').first()
    await expect(idle).toBeVisible()
    const inline = idle.getByTestId('hq-fleet-best').getByTestId('hq-move')
    await expect(inline).toBeVisible()
    await expect(inline).toHaveAttribute('data-kind', 'trade')
    const top = trades.first()
    await expect(inline).toHaveAttribute('data-good', (await top.getAttribute('data-good'))!)

    // THE PRESS: the desk's own best-sale trip — that good, on Buy, at her city, sold where the card said
    const good = (await top.getAttribute('data-good'))!
    const port = (await top.getAttribute('data-port'))!
    await top.click()
    await expect(page).toHaveURL(/\/command/)
    const panel = page.getByTestId('good-detail')
    await expect(panel).toBeVisible({ timeout: 120_000 })
    await expect(panel).toHaveAttribute('data-good', good)
    await expect(panel).toHaveAttribute('data-side', 'buy')
    await expect(panel).toHaveAttribute('data-city', 'LIS')
    await expect(panel).toHaveAttribute('data-sell-at', port)
    await expect(page.getByTestId('trade-act')).toHaveAttribute('data-act', 'buy-sell', { timeout: 120_000 })
  })
})

// 0480: THE BOARD FROM THE SERVER (hq_board_enabled lit): world.hq_board() ranks every move; each card names its own act and one press
// commits it through the desk's own door (the trip: planLines and cmd.issue_lines), HQ kept; a trade card wears its risk as a mark.
test.describe('the board from the server (0480, lit)', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('served, ranked by coin per hour, the risk marked, and one press queues the trip', async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    test.setTimeout(600_000)
    await openHq(page, 390, 844, true)
    await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'served', { timeout: 180_000 })
    await expect(page.getByTestId('hq-bridge-rate')).toHaveAttribute('data-span', '24h')

    const trades = page.locator('[data-testid="hq-moves"] [data-testid="hq-move"][data-kind="trade"]')
    await expect(trades.first()).toBeVisible({ timeout: 180_000 })
    const top = trades.first()
    await expect(top).toHaveAttribute('data-served', 'true')
    await expect(top).toHaveAttribute('data-act', 'cmd.issue_lines')
    await expect(top.getByTestId('hq-move-risk')).toBeVisible()
    expect(['shield', 'pirate']).toContain(await top.getByTestId('hq-move-risk').getAttribute('data-risk'))
    const rates = (await trades.evaluateAll((els) => els.map((e) => e.getAttribute('data-per-hour') ?? ''))).filter((r) => r !== '').map(Number)
    expect(rates.length, 'served trade cards with coin an hour').toBeGreaterThan(0)
    expect(rates, 'the server ranks trade runs by coin an hour').toEqual([...rates].sort((a, b) => b - a))

    // ONE PRESS: the trip is queued for her fleet and HQ stays; no refusal stands under the card
    const fleet = (await top.getAttribute('data-fleet'))!
    await top.click()
    await expect(page.locator(`[data-testid="hq-fleet"][data-fleet="${fleet}"]`)).not.toHaveAttribute('data-job', 'idle', { timeout: 120_000 })
    await expect(page).toHaveURL(/\/city/)
    await expect(page.getByTestId('hq-move-refusal')).toHaveCount(0)
  })
})

// 0481: STANDING FLEET JOBS (fleet_jobs_enabled lit, the board served): each fleet row carries her job's setter; Best gives her the best
// run and her row then wears the job's mark; a served trade card's Repeat sends the trip and keeps it as her fixed route (working).
test.describe('standing fleet jobs (0481, lit)', () => {
  for (const glass of [
    { width: 390, height: 844 },
    { width: 1280, height: 800 },
  ]) {
    test(`a fleet row sets her job, a trade card repeats its trip, and nothing leaves the glass at ${glass.width}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await openHq(page, glass.width, glass.height, true, true)
      const control = page.getByTestId('hq-job-control').first()
      await expect(control).toBeVisible({ timeout: 180_000 })
      const fleet = (await control.getAttribute('data-fleet'))!
      await control.getByTestId('hq-job-set-best').click()
      const mark = page.locator(`[data-testid="hq-job-control"][data-fleet="${fleet}"] [data-testid="hq-job"]`)
      await expect(mark).toHaveAttribute('data-kind', 'best', { timeout: 120_000 })
      await expect(page.getByTestId('hq-job-refusal')).toHaveCount(0)
      // a served trade card's Repeat: the trip goes now (the card's own act) and stays her job as a fixed route (its course her voyage)
      const card = page.locator(`[data-testid="hq-moves"] li:has([data-testid="hq-move"][data-kind="trade"][data-served="true"][data-fleet="${fleet}"])`).first()
      await expect(card).toBeVisible({ timeout: 180_000 })
      await card.getByTestId('hq-move-repeat').click()
      await expect(mark).toHaveAttribute('data-kind', 'fixed', { timeout: 120_000 })
      await expect(mark).toHaveAttribute('data-state', 'working')
      await expect(page.getByTestId('hq-move-repeat-refusal')).toHaveCount(0)
      await expect(page.getByTestId('hq-move-refusal')).toHaveCount(0)
      expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)
      const small = await page.evaluate(() =>
        [...document.querySelectorAll('[data-testid="hq-job-control"] button, [data-testid="hq-move-repeat"]')]
          .map((b) => b.getBoundingClientRect())
          .filter((r) => r.width > 0 && (r.height < 43.5 || r.width < 43.5)).length,
      )
      expect(small, 'job presses under 44 px').toBe(0)
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/jobs-${glass.width}.png`, fullPage: true })
    })
  }
})

// 0483: COURIER CONTRACTS (contracts_enabled lit, the board served, one house contract posted at Lisbon): her board offers it as a
// `contract` card (the pact, Carry <good> to <harbour>, the reward and coin an hour, the collateral and the risk as marks) and one press
// takes it and sends her: the fleet leaves Lisbon, HQ stays, no refusal. The Requests face's door is "Post a contract".
test.describe('courier contracts (0483, lit)', () => {
  for (const glass of [
    { width: 390, height: 844 },
    { width: 1280, height: 800 },
  ]) {
    test(`a contract card takes it in one press, and nothing leaves the glass at ${glass.width}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await openHq(page, glass.width, glass.height, true, false, true)
      await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'served', { timeout: 180_000 })
      await expect(page.locator('[data-testid="hq-move"]').first()).toBeVisible({ timeout: 180_000 })
      await page.getByTestId('hq-filter-contract').click()
      const card = page.locator('[data-testid="hq-moves"] [data-testid="hq-move"][data-kind="contract"]').first()
      await expect(card).toBeVisible({ timeout: 180_000 })
      await expect(card).toHaveAttribute('data-served', 'true')
      await expect(card).toHaveAttribute('data-act', 'cmd.take_contract')
      await expect(card.getByTestId('hq-move-risk')).toBeVisible()
      await expect(card.getByTestId('hq-move-collateral')).toBeVisible()
      expect(Number(await card.getAttribute('data-per-hour'))).toBeGreaterThan(0)
      expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/contracts-${glass.width}.png`, fullPage: true })
      const fleet = (await card.getAttribute('data-fleet'))!
      await card.click()
      await expect(page.locator(`[data-testid="hq-fleet"][data-fleet="${fleet}"]`)).not.toHaveAttribute('data-job', 'idle', { timeout: 120_000 })
      await expect(page).toHaveURL(/\/city/)
      await expect(page.getByTestId('hq-move-refusal')).toHaveCount(0)
    })
  }
})

for (const glass of [
  { width: 320, height: 640 },
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
]) {
  test(`no sideways scroll and every name whole at ${glass.width}`, async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    test.setTimeout(600_000)
    await openHq(page, glass.width, glass.height)
    await expect(page.locator('[data-testid="hq-move"]').first()).toBeVisible({ timeout: 180_000 })
    expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)
    // no card, chip or row stands past the glass, and no name is cut
    const out = await page.evaluate((w) => {
      const bad: string[] = []
      for (const el of document.querySelectorAll('[data-testid="hq-board"] *')) {
        const r = el.getBoundingClientRect()
        if (r.width > 0 && (r.right > w + 1 || r.left < -1)) bad.push(`${el.getAttribute('data-testid') ?? el.tagName} ${Math.round(r.left)}..${Math.round(r.right)}`)
        if (el instanceof HTMLElement && getComputedStyle(el).textOverflow === 'ellipsis' && el.scrollWidth > el.clientWidth) bad.push(`cut: ${el.textContent}`)
      }
      return bad
    }, glass.width)
    expect(out, 'past the glass or cut').toEqual([])
    // every press on the board is 44 px at least
    const small = await page.evaluate(() =>
      [...document.querySelectorAll('[data-testid="hq-board"] button')]
        .map((b) => b.getBoundingClientRect())
        .filter((r) => r.width > 0 && (r.height < 43.5 || r.width < 43.5)).length,
    )
    expect(small, 'presses under 44 px').toBe(0)
  })
}
