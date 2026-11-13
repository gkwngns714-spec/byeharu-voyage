import { test, expect, type Page } from '@playwright/test'
import { passageLines, passageOf, shutByReach, type PlanLeg } from '../src/domain/passage'
import type { RouteLeg } from '../src/lib/rpc'
import { ready, reachable, WORLD_BOOT_MS } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A FAR CITY IS SENT IN ONE PRESS — the owner, 2026-11-13:
//
//   "when moving to a city, anywhere, far away, it says navigation restriction. i want the game to calculate which
//    cities to cross automatically, and just tell me the final time, price reaching the destination when pressed
//    send fleet."
//
// Before: the Map's place tray dry-ran ONE SAIL to the tapped city, and a city past one leg of her navigation ended the
// row at the server's refusal ("that leg is 9240 nm and your navigation carries you 1700 nm"). Now the one passage
// planner (src/domain/passage/chain.ts, src/live/passagePlan.ts) asks the server for the harbours between, has every
// leg judged, and the row says the whole trip's days (with the real wait) and what its supplies cost; Send queues every
// SAIL at once. Her navigation still bounds each leg: only a city no chain reaches keeps a refusal, and it says why.
//
//   1. PURE: the planner's reading of the server's answer — totals summed, shut at the first shut leg, one SAIL a leg.
//   2. DRIVEN, 390 px, English: a far city's row names its stops, a time and a price; ONE press sends her, and she is
//      under way TO THAT CITY (which she can only be if every SAIL of the chain is queued behind the leg she is on).
//   3. DRIVEN, 320 px, Korean: the same row holds the glass (no sideways scroll), and a city no chain reaches says so.
//
// The browser half drives the real game (PGlite, the whole chain); it SKIPS with a reason when nothing is served.
// Run it: npm run build && npx vite preview --port 4173, then `npx playwright test map.autoroute.spec.ts`.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const leg = (from: string | null, to: string): PlanLeg => ({ from, to, path: [[0, 0], [1, 1]], nm: 60 })
const served = (to: string, days: number, cost: number, shut: RouteLeg['shut'] = null, via: string[] | null = null): RouteLeg => ({
  from: null,
  to,
  nm: days * 100,
  days,
  supplies: { days, cost, fits: true },
  shut,
  via,
})

test.describe('the passage planner reads the server’s answer', () => {
  test('an open chain: the days and the supplies of every leg are summed, the stops are the harbours between', () => {
    const legs = [leg('LIS', 'ALG'), leg('ALG', 'HER'), leg('HER', 'IST')]
    const plan = passageOf(legs, [served('ALG', 1.5, 10), served('HER', 2.25, 0), served('IST', 1, 32)])
    expect(plan).toEqual({ kind: 'open', stops: ['ALG', 'HER'], legs, days: 4.75, cost: 42 })
    if (plan?.kind !== 'open') throw new Error('unreachable')
    expect(passageLines(plan).map((l) => l.text)).toEqual(['SAIL ALG', 'SAIL HER', 'SAIL IST'])
    expect(passageLines(plan).every((l) => Array.isArray(l.path))).toBe(true)
  })

  test('one leg within reach is a plan with no stops', () => {
    expect(passageOf([leg('LIS', 'CAD')], [served('CAD', 0.7, 3)])).toMatchObject({ kind: 'open', stops: [], days: 0.7, cost: 3 })
  })

  test('a leg the server calls shut shuts the plan at that leg, and "no stops" is said only of a whole way with none served', () => {
    const far = { code: 'E_LEG_TOO_FAR', sentence: 'too far' }
    expect(passageOf([leg('LIS', 'CLL')], [served('CLL', 25, 0, far)])).toMatchObject({ kind: 'shut', to: 'CLL', noStops: true, refusal: far })
    expect(passageOf([leg('LIS', 'IST')], [served('IST', 5, 0, far, ['ALG'])])).toMatchObject({ kind: 'shut', noStops: false })
    expect(passageOf([leg('LIS', 'ALG'), leg('ALG', 'IST')], [served('ALG', 1, 0), served('IST', 4, 0, far)])).toMatchObject({
      kind: 'shut',
      from: 'ALG',
      to: 'IST',
      noStops: false,
    })
    expect(passageOf([leg('LIS', 'SEA')], [served('SEA', 1, 0, { code: 'E_SEA_CLOSED', sentence: 'shut' })])).toMatchObject({ kind: 'shut', noStops: false })
  })

  test('an answer that does not match the question is no plan, and only length and stores are opened by a call on the way', () => {
    expect(passageOf([leg('LIS', 'ALG'), leg('ALG', 'IST')], [served('ALG', 1, 0)])).toBeNull()
    expect(passageOf([], [])).toBeNull()
    expect(['E_LEG_TOO_FAR', 'E_ENDURANCE', 'E_SEA_CLOSED', 'E_CREW_SHORT', null].map(shutByReach)).toEqual([true, true, false, false, false])
  })
})

// ── THE DRIVE ────────────────────────────────────────────────────────────────────────────────────

async function openWorldChart(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: WORLD_BOOT_MS })
  // draw the chart back to the whole world, so a far harbour is on the glass
  const chart = (await page.getByTestId('map-chart').boundingBox())!
  for (let i = 0; i < 6; i++) {
    await page.mouse.move(chart.x + chart.width / 2, chart.y + chart.height / 2)
    await page.mouse.wheel(0, 900)
    await page.waitForTimeout(700)
  }
}

/** Tap the harbour's mark, press Send fleet, and wait for the first row's verdict. */
async function askCity(page: Page, code: string): Promise<boolean> {
  const at = await page.evaluate((c) => {
    const g = document.querySelector(`[data-port-code="${c}"]`)
    if (!g) return null
    const r = g.getBoundingClientRect()
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
  }, code)
  if (!at) return false
  await page.mouse.click(at.x, at.y)
  const tray = page.getByTestId('map-detail-tray')
  if (!(await tray.isVisible().catch(() => false))) return false
  await page.getByTestId('map-send-fleet').click()
  await expect(page.getByTestId('map-send-row').first()).toBeVisible()
  // the verdict: a passage, or a refusal — the cold first check compiles every plan under the verb (map.sendfleet.spec.ts)
  await expect(page.locator('[data-testid="map-send-passage"], [data-testid="map-send-refusal"]').first()).toBeVisible({ timeout: 180_000 })
  return true
}

async function closeTray(page: Page) {
  await page.getByTestId('map-detail-tray').getByTestId('tray-close').click()
  await expect(page.getByTestId('map-detail-tray')).toHaveCount(0)
}

/** The first of these cities whose row is a chain (harbours between); the tray is left open on it. */
async function findChain(page: Page, codes: readonly string[]): Promise<string | null> {
  for (const code of codes) {
    if (!(await askCity(page, code))) continue
    if ((await page.getByTestId('map-send-via').count()) > 0) return code
    await closeTray(page)
  }
  return null
}

const FAR = ['IST', 'HAV', 'ALE', 'KOC', 'GUA', 'BUS']
/** Past every chain from Lisbon at Navigation 1: the Pacific coast of the Americas, Hawaii. */
const NO_WAY = ['CLL', 'ACA', 'HNL'
]

test.describe('a far city, driven on a phone (390 px, English)', () => {
  test.use({ viewport: { width: 390, height: 844 }, locale: 'en-US' })
  test.setTimeout(900_000)

  test('the row says the stops, the whole time and the price; one press sends her there', async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run build && npm run preview\` and re-run`)
    await openWorldChart(page)
    const far = await findChain(page, FAR)
    expect(far, `none of ${FAR.join(' ')} is reached through harbours between — the far send is not planned`).not.toBeNull()
    const city = (await page.getByTestId('map-place-name').innerText()).split('\n')[0].trim()

    const row = page.getByTestId('map-send-row').first()
    // NO REFUSAL: the leg her navigation cannot make in one go is not the row's answer any more
    await expect(row.getByTestId('map-send-refusal')).toHaveCount(0)
    await expect(row.getByTestId('map-send-no-way')).toHaveCount(0)
    // THE STOPS, small, by name
    const via = row.getByTestId('map-send-via')
    const stops = ((await via.getAttribute('data-stops')) ?? '').split(' ').filter(Boolean)
    expect(stops.length, 'a chain names at least one harbour between').toBeGreaterThanOrEqual(1)
    await expect(via).toHaveText(/^via \S/)
    // THE FINAL TIME: voyage-days with the real wait beside them, as the app prints a trip's days
    await expect(row.getByTestId('map-send-passage')).toHaveText(/^[\d,.]+ days? · \d+(s|m|h)/)
    // THE PRICE: the supplies of the whole chain, a figure with the coin
    await expect(row.getByTestId('map-send-cost')).toHaveText(/^Supplies .*\d/)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'the tray scrolls sideways at 390').toBe(true)
    await page.screenshot({ path: 'test-results/auto-route-390-row.png' })

    // ONE PRESS: pick her, Send
    await page.getByTestId('map-send-row-head').first().click()
    const send = page.getByTestId('map-send-ratio-send')
    await expect(send).toBeEnabled()
    await send.click()
    // SHE IS UNDER WAY TO THE CITY, not to the first harbour between: the leg she is on ends at a stop, so the row can
    // only say this when every SAIL of the chain is queued behind it (sendRules.ts `standingOf` reads `boundFor`).
    const note = page.getByTestId('map-send-row-note').first()
    await expect(note).toHaveText(`Under way to ${city}.`, { timeout: 60_000 })
    await expect(page.getByTestId('map-send-issue-refusal')).toHaveCount(0)
    await page.screenshot({ path: 'test-results/auto-route-390-sent.png' })
  })
})

test.describe('a far city and a city past every chain (320 px, Korean)', () => {
  test.use({ viewport: { width: 320, height: 640 }, locale: 'ko-KR' })
  test.setTimeout(900_000)

  test('the chained row holds the glass, and a city no chain reaches says why', async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run build && npm run preview\` and re-run`)
    await openWorldChart(page)
    const far = await findChain(page, FAR)
    expect(far, `none of ${FAR.join(' ')} is reached through harbours between`).not.toBeNull()
    const row = page.getByTestId('map-send-row').first()
    await expect(row.getByTestId('map-send-via')).toHaveText(/\S 경유$/)
    await expect(row.getByTestId('map-send-cost')).toHaveText(/^보급 .*\d/)
    await expect(row.getByTestId('map-send-passage')).toHaveText(/\d.* · \d/)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'the tray scrolls sideways at 320').toBe(true)
    // NAMES WHOLE: the stops line wraps, it is never cut
    expect(await row.getByTestId('map-send-via').evaluate((e) => e.scrollWidth <= e.clientWidth + 1), 'the stops are cut off').toBe(true)
    await page.screenshot({ path: 'test-results/auto-route-320-ko-row.png' })
    await closeTray(page)

    // NO CHAIN: the refusal stays, with the plain reason under it
    let dead: string | null = null
    for (const code of NO_WAY) {
      if (!(await askCity(page, code))) continue
      if ((await page.getByTestId('map-send-no-way').count()) > 0) {
        dead = code
        break
      }
      await closeTray(page)
    }
    expect(dead, `every one of ${NO_WAY.join(' ')} is reached — pick farther cities`).not.toBeNull()
    await expect(page.getByTestId('map-send-refusal').first()).toBeVisible()
    await expect(page.getByTestId('map-send-no-way').first()).toHaveText('가는 길에 들를 항구 없음.')
    await expect(page.getByTestId('map-send-via')).toHaveCount(0)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    await page.screenshot({ path: 'test-results/auto-route-320-ko-no-way.png' })
  })
})
