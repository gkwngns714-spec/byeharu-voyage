import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { arrivalCard, LANDING_TEST_TIMEOUT_MS } from './arrivalWait.fixture'
import { serveRoutesOn } from './routesOn.fixture'
import { awayLand, awayReport, AWAY_MS, parseSeenMark, seenMark, type SeenMark } from '../src/domain/route'
import { tripRoute } from '../src/live/standingRouteDraft'
import type { LandView, LedgerEvent, SnapshotGood, StandingRoute, StandingRouteBook } from '../src/lib/rpc'
import { LANGS } from './korean.paused'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A ROUTE IN REACH, AND A REPORT ON RETURN (2026-11-16, the content plan's slice B; docs/design/content-plan-2026-11.md
// §5.3 no. 2). Two halves:
//   * FIXED FACTS, no browser: the trip a route is made from (`tripRoute`) and the away report (`awayReport`) on fixed
//     events and fixed route books.
//   * THE DRIVE, at 390×844 in English and 1280×800 in Korean: a new company sails a profitable trip from its card, the
//     arrival card offers Make route, one press starts it (the button stays where it was; nothing under it moves), Trade
//     says On route where her name stands, the route closes a lap by itself, and when she comes back "after being away"
//     (the device's mark set eleven minutes back) the While away card says the laps and their net that History's lap
//     line says, and the purse's move. A brand-new company sees no card.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const OUT = process.env.SLICE_B_SHOTS ?? 'test-results/route-in-reach'

// ── FIXED FACTS ──────────────────────────────────────────────────────────────────────────────────

const good = (code: string, name: string) => ({ code, name }) as SnapshotGood
// the goods AS SERVED (worldStore `servedGoods`): the names a ledger event carries
const goods: SnapshotGood[] = [good('PEP', 'Pepper'), good('CRK', 'Cork'), good('WIN', 'Wine'), good('TW1', 'Twin'), good('TW2', 'Twin')]
let seq = 0
const ev = (kind: string, payload: Record<string, unknown>): LedgerEvent => ({ id: `e${++seq}`, kind, payload, at: '2026-11-16T00:00:00Z', ducats_delta: null, balance_after: null })

test.describe('fixed facts', () => {
  test('tripRoute: here first, each stop sells all and buys what she carried from it; nothing carried is no route', () => {
    const events = [
      ev('BOUGHT', { fleet: 'Gaivota', port: 'LIS', good: 'Pepper' }),
      ev('BOUGHT', { fleet: 'Gaivota', port: 'LIS', good: 'Cork' }), // bought, never sold at SET: not carried
      ev('BOUGHT', { fleet: 'Other', port: 'LIS', good: 'Wine' }), // another fleet's
      ev('SOLD', { fleet: 'Gaivota', port: 'SET', good: 'Pepper' }),
      ev('SOLD', { fleet: 'Other', port: 'SET', good: 'Wine' }),
    ]
    const stops = tripRoute({ fleet: 'Gaivota', here: 'SET', there: 'LIS' }, events, goods)
    expect(stops?.map((s) => [s.port, s.sellAll, s.buyGood, s.kept.length])).toEqual([
      ['SET', true, null, 0],
      ['LIS', true, 'PEP', 0],
    ])
    // the way back too, when she made it: bought at SET, sold at LIS
    const back = tripRoute({ fleet: 'Gaivota', here: 'SET', there: 'LIS' }, [...events, ev('BOUGHT', { fleet: 'Gaivota', port: 'SET', good: 'Wine' }), ev('SOLD', { fleet: 'Gaivota', port: 'LIS', good: 'Wine' })], goods)
    expect(back?.map((s) => s.buyGood)).toEqual(['WIN', 'PEP'])
    // two goods carried: one in the editor's BUY, the other a further BUY line
    const two = tripRoute({ fleet: 'Gaivota', here: 'SET', there: 'LIS' }, [...events, ev('SOLD', { fleet: 'Gaivota', port: 'SET', good: 'Cork' })], goods)
    expect(two?.[1].buyGood).toBe('CRK')
    expect(two?.[1].kept.map((l) => [l.kind, l.good, l.qty, l.price_limit])).toEqual([['BUY', 'PEP', null, null]])
    // nothing she bought at LIS was sold here, a name two goods share, the same harbour twice: no route
    expect(tripRoute({ fleet: 'Gaivota', here: 'SET', there: 'LIS' }, [ev('SOLD', { fleet: 'Gaivota', port: 'SET', good: 'Pepper' })], goods)).toBeNull()
    expect(tripRoute({ fleet: 'Gaivota', here: 'SET', there: 'LIS' }, [ev('BOUGHT', { fleet: 'Gaivota', port: 'LIS', good: 'Twin' }), ev('SOLD', { fleet: 'Gaivota', port: 'SET', good: 'Twin' })], goods)).toBeNull()
    expect(tripRoute({ fleet: 'Gaivota', here: 'LIS', there: 'LIS' }, events, goods)).toBeNull()
  })

  const route = (id: string, laps: number, net: number, state: StandingRoute['state'] = 'waiting', paused_reason: StandingRoute['paused_reason'] = null) =>
    ({ id, name: 'Lisbon ⇄ Setubal', stops: [{ port: 'LIS' }, { port: 'SET' }], state, paused_reason, earnings: { total: { laps, net } } }) as unknown as StandingRoute
  const book = (...routes: StandingRoute[]) => ({ enabled: true, max: 3, stop_max: 6, line_max: 6, laps_per_game_day: 1, routes }) as StandingRouteBook

  test('awayReport: the counters\' difference, a stuck route, the purse; nothing to say is no card', () => {
    const then = seenMark(1_000_000, 10_000, book(route('A', 4, 2_000), route('B', 1, -50)))
    expect(parseSeenMark(JSON.stringify(then))).toEqual(then)
    expect(parseSeenMark(null)).toBeNull()
    expect(parseSeenMark('{"at":"x"}')).toBeNull()
    const later = then.at + AWAY_MS
    // A closed 3 laps (net 2,000 → 8,684); B stopped and closed none; C is new (made elsewhere): all its laps count
    const now = book(route('A', 7, 8_684), route('B', 1, -50, 'stopped'), route('C', 2, 900))
    const r = awayReport(then, later, 16_500, now)!
    expect(r.routes.map((x) => [x.id, x.laps, x.net, x.stuck])).toEqual([
      ['A', 3, 6_684, false],
      ['B', 0, 0, true],
      ['C', 2, 900, false],
    ])
    expect(r.money).toBe(6_500)
    expect(r.since).toBe(then.at)
    // not away yet: no card; nothing moved: no card; paused by her own hand is not stuck
    expect(awayReport(then, later - 1, 16_500, now)).toBeNull()
    expect(awayReport(then, later, 10_000, book(route('A', 4, 2_000), route('B', 1, -50, 'paused', 'player')))).toBeNull()
    expect(awayReport(then, later, 10_000, book(route('A', 4, 2_000), route('B', 1, -50, 'paused', 'losing')))?.routes.map((x) => x.id)).toEqual(['B'])
    // a company with no routes whose purse did not move (a brand-new player) has nothing to report
    expect(awayReport(seenMark(0, 8_000, null), AWAY_MS * 10, 8_000, null)).toBeNull()
  })

  test('awayLand (0458): the party line is what is home and not collected, and the level; dark or nothing home is no line', () => {
    const lit = (n: number, waiting: number) =>
      ({
        enabled: true,
        company: true,
        party: { good: 'iron', waiting_good: null, waiting, progress: { new: n } },
        skill: { code: 'mining', level: 31 },
      }) as unknown as LandView
    expect(awayLand(lit(80, 6))).toEqual({ good: 'iron', n: 86, skill: 'mining', level: 31 })
    expect(awayLand(lit(0, 0))).toBeNull()
    expect(awayLand({ enabled: false })).toBeNull()
    expect(awayLand(null)).toBeNull()
    // the land alone is something to say; with nothing else, no card
    const then = seenMark(0, 8_000, null)
    expect(awayReport(then, AWAY_MS, 8_000, null, awayLand(lit(80, 6)))?.land?.n).toBe(86)
    expect(awayReport(then, AWAY_MS, 8_000, null, awayLand(lit(0, 0)))).toBeNull()
    // 0461: a smith's job read through Mining's view is Smithing's line, with no level (Mining's is not its)
    const smith = {
      enabled: true,
      company: true,
      party: { good: 'iron-bars', waiting_good: null, waiting: 0, progress: { new: 2 }, terms: { skill: 'smithing' } },
      skill: { code: 'mining', level: 31 },
    } as unknown as LandView
    expect(awayLand(smith)).toEqual({ good: 'iron-bars', n: 2, skill: 'smithing', level: null })
  })
})

// ── THE DRIVE ─────────────────────────────────────────────────────────────────────────────────────

const RUNS = [
  { size: { width: 390, height: 844 }, lang: 'en' as const },
  { size: { width: 1280, height: 800 }, lang: 'ko' as const },
].filter((r) => LANGS.includes(r.lang))

async function mark(page: Page): Promise<SeenMark | null> {
  const raw = await page.evaluate(() => {
    const key = Object.keys(localStorage).find((k) => k.startsWith('bv:last-seen:'))
    return key ? localStorage.getItem(key) : null
  })
  return parseSeenMark(raw)
}

const noSideways = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)

for (const run of RUNS) {
  const tag = `${run.size.width}-${run.lang}`
  test.describe(`a route in reach at ${run.size.width}×${run.size.height}, ${run.lang}`, () => {
    test.use({ viewport: run.size, deviceScaleFactor: 2, locale: run.lang === 'ko' ? 'ko-KR' : 'en-US' })

    test('a profitable trip offers Make route; one press runs it; on return the While away card says what History says', async ({ page, request, baseURL }) => {
      test.setTimeout(LANDING_TEST_TIMEOUT_MS + 1_800_000)
      expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}: run a preview (or set PLAYWRIGHT_BASE_URL)`).toBe(true)
      await page.addInitScript((l) => localStorage.setItem('bv.locale', l), run.lang)
      await serveRoutesOn(page)
      await page.goto('command')
      await ready(page)
      const face = page.getByTestId('desk-trade')

      // A BRAND-NEW COMPANY: the device keeps its first mark and says nothing
      await expect.poll(async () => (await mark(page)) !== null, { timeout: 120_000 }).toBe(true)
      await expect(page.getByTestId('away-card')).toHaveCount(0)

      // A PROFITABLE NEAR TRIP, from the card's own best sale: buy here, sail and sell there
      const sale = face.locator('[data-testid="trade-good"] [data-testid="best-sale"][data-state="sale"][data-pays="true"]:not(:has([data-testid="best-sale-money"]))')
      await expect(sale.first()).toBeVisible({ timeout: 180_000 })
      const n = await sale.count()
      let pick = -1
      let best = Infinity
      for (let i = 0; i < n; i++) {
        const s = Number(await sale.nth(i).getAttribute('data-seconds'))
        if (Number.isFinite(s) && s < best) {
          best = s
          pick = i
        }
      }
      expect(pick, 'no card serves a paying sale with a time').toBeGreaterThanOrEqual(0)
      const to = (await sale.nth(pick).getAttribute('data-port'))!
      await sale.nth(pick).click()
      const act = page.getByTestId('trade-act')
      await expect(act).toHaveAttribute('data-act', 'buy-sell', { timeout: 60_000 })
      await expect(act).toBeEnabled({ timeout: 60_000 })
      await act.click()
      await expect(page.getByTestId('good-detail')).toHaveCount(0, { timeout: 60_000 })
      console.log(`${tag}: sailing to ${to} (${best} s quoted)`)

      // sit on Fleets while she sails
      await page.goto('fleets')
      await ready(page)
      const main = page.locator('main')
      const card = await arrivalCard(page, `${tag}: the arrival`)
      const repeat = page.getByTestId('arrival-repeat-press')
      await expect(repeat, `${tag}: the card offers no Make route: ${(await card.innerText()).replace(/\s+/g, ' ')}`).toBeVisible()
      await expect(repeat).toHaveText(run.lang === 'ko' ? '항로 만들기' : 'Make route')
      console.log(`${tag}: card ${JSON.stringify((await card.innerText()).replace(/\s+/g, ' '))}`)
      await page.screenshot({ path: `${OUT}/arrival-make-route-${tag}.png` })

      // ONE PRESS: the route starts; the button stays where it was and the page under the card does not move
      const before = { main: await main.boundingBox(), button: await repeat.boundingBox() }
      await repeat.click()
      await expect(repeat).toHaveAttribute('data-started', 'true', { timeout: 60_000 })
      await expect(repeat).toHaveText(run.lang === 'ko' ? '항로 운항' : 'On route')
      expect(await repeat.boundingBox()).toEqual(before.button)
      expect(await main.boundingBox()).toEqual(before.main)
      expect(await noSideways(page)).toBe(true)
      await page.screenshot({ path: `${OUT}/arrival-on-route-${tag}.png` })

      // TRADE SAYS IT WHERE HER NAME STANDS, and the Route row is her route
      await page.goto('command')
      await ready(page)
      // (on a phone at sea the passage line keeps the strip's room, TradeStatus.tsx; the Route row and Fleets say it)
      const strip = page.getByTestId('trade-status').first()
      await expect(strip).toBeVisible({ timeout: 60_000 })
      const wide = run.size.width >= 1024
      await expect
        .poll(async () => (await page.getByTestId('trade-status-route').count()) > 0 || (!wide && (await strip.getAttribute('data-state')) === 'sailing'), { timeout: 60_000 })
        .toBe(true)
      await expect(page.getByTestId('route-row')).toContainText(run.lang === 'ko' ? '항로 ·' : 'Route ·', { timeout: 60_000 })
      expect(await noSideways(page)).toBe(true)
      await page.screenshot({ path: `${OUT}/trade-on-route-${tag}.png` })

      // THE MARK BEFORE THE LAP: one route, no lap closed
      await expect.poll(async () => Object.keys((await mark(page))?.routes ?? {}).length, { timeout: 120_000 }).toBe(1)
      const m0 = (await mark(page))!
      const id = Object.keys(m0.routes)[0]
      expect(m0.routes[id].laps, `${tag}: a lap had closed before the first mark`).toBe(0)

      // THE ROUTE CLOSES A LAP BY ITSELF (the device's own mark carries the served counters on every read)
      await expect.poll(async () => (await mark(page))?.routes[id]?.laps ?? 0, { timeout: LANDING_TEST_TIMEOUT_MS, intervals: [5000] }).toBeGreaterThanOrEqual(1)
      const m1 = (await mark(page))!
      console.log(`${tag}: lap closed; then ${JSON.stringify(m0)}; now ${JSON.stringify(m1)}`)

      // "AFTER BEING AWAY": the mark as it stood before the lap, eleven minutes back; then the game is opened again. The
      // old page writes its own mark as it unloads (hidden), so the set-back mark is put in by the NEW document before the
      // app runs (a one-shot init script, handed the mark through sessionStorage).
      await page.addInitScript(() => {
        const m = sessionStorage.getItem('slice-b-away')
        if (m === null) return
        sessionStorage.removeItem('slice-b-away')
        const key = Object.keys(localStorage).find((k) => k.startsWith('bv:last-seen:'))
        if (key) localStorage.setItem(key, m)
      })
      await page.evaluate((m) => sessionStorage.setItem('slice-b-away', m), JSON.stringify({ ...m0, at: Date.now() - 11 * 60_000 }))
      await page.goto('fleets')
      await ready(page)
      const away = page.getByTestId('away-card')
      await expect(away).toBeVisible({ timeout: 120_000 })
      const row = away.getByTestId('away-route')
      await expect(row).toHaveCount(1)
      const laps = Number(await row.getAttribute('data-laps'))
      const net = Number(await row.getAttribute('data-net'))
      expect(laps).toBe(m1.routes[id].laps - m0.routes[id].laps)
      expect(net).toBe(m1.routes[id].net - m0.routes[id].net)
      const money = await away.getAttribute('data-money')
      if (m1.ducats !== m0.ducats) expect(Number(money)).toBe(m1.ducats! - m0.ducats!)
      // each FLEET's route earnings (2026-11-23, the roadmap's slice 6): the fleet that ran it, with her picture, the route under it
      await expect(row.getByTestId('away-route-fleet')).not.toBeEmpty()
      await expect(row.locator('[data-ship-picture]')).toHaveCount(1)
      await expect(row.getByTestId('away-route-title')).toBeVisible()
      const netWords = (await row.getByTestId('away-route-net').innerText()).trim()
      console.log(`${tag}: away card ${JSON.stringify((await away.innerText()).replace(/\s+/g, ' '))}`)
      // inside the glass, nothing sideways; Close takes it away and the page under it did not move
      const box = (await away.boundingBox())!
      expect(box.x).toBeGreaterThanOrEqual(0)
      expect(box.x + box.width).toBeLessThanOrEqual(run.size.width)
      expect(box.y + box.height).toBeLessThanOrEqual(run.size.height)
      expect(await noSideways(page)).toBe(true)
      await page.screenshot({ path: `${OUT}/away-card-${tag}.png` })
      const under = await main.boundingBox()
      await away.getByTestId('away-close').click()
      await expect(away).toHaveCount(0)
      expect(await main.boundingBox()).toEqual(under)

      // HISTORY SAYS THE SAME: its lap line(s) carry that net
      await page.goto('ledger')
      await ready(page)
      const lapRows = page.locator('[data-testid="ledger-row"][data-kind="ROUTE_LAP"]')
      await expect(lapRows).toHaveCount(laps, { timeout: 120_000 })
      const lines = await lapRows.allInnerTexts()
      console.log(`${tag}: History ${JSON.stringify(lines.map((l) => l.replace(/\s+/g, ' ')))}`)
      if (laps === 1) expect(lines[0], `${tag}: History's lap line does not say ${netWords}`).toContain(` — ${netWords}`)
      await page.screenshot({ path: `${OUT}/history-lap-${tag}.png` })
    })
  })
}
