// ═══════════════════════════════════════════════════════════════════════════════════════════════
// GRAPHS BY DAY, WEEK AND MONTH — 0316 (docs/dev-log/2026-11-05-history-graphs.md; owner row 289)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Owner, 2026-11-05: *"the market data, as well as gold earned data / loss graphs record. i want to be able to see them by days, weeks, months."*
//
// THE READ: world.history through the client wrapper. One daily row per subject is the one authority; a week and a month are the same rows
// grouped: a flow adds, a state is the last day's, a price is first open, highest high, lowest low, last close. A company sees its own books,
// a merchant company's are public, another player's are not.
// THE PAGE: HistoryChart.tsx on Stats and on the Report: Day / Week / Month, one press, EN + KO, nothing moves and nothing scrolls sideways.
// It names HistoryChart.tsx, Overview.tsx, CityDetail.tsx, GoodTray.tsx, Me.tsx, Merchants.tsx and Report.tsx so CI's rule N selects it.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldHistory, HISTORY_PERIODS, type HistoryCompanyPoint, type HistoryGoodPoint } from '../src/lib/rpc'
import { PHONE, reachable, ready } from './appReady.fixture'

const WIDE = { width: 1280, height: 707 }

test.describe('the read', () => {
  test.describe.configure({ mode: 'serial' })
  let db: LocalDb

  test.beforeAll(async () => {
    test.setTimeout(360_000)
    db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
    setBackend(createLocalBackend(db))
    await db.callAs(`select cmd.found_house('Historia Spec', 'PRT') as result`)
  })

  test.afterAll(async () => {
    clearBackend()
    await db?.close()
  })

  test('there are three periods, and an unknown one is refused, not defaulted', async () => {
    expect([...HISTORY_PERIODS]).toEqual(['day', 'week', 'month'])
    const bad = await db.callAs<string>(`select coalesce((select 'no' from world.history('world', null, 'year')), 'no') as result`).catch((e) => String(e))
    expect(bad).toContain('E_BAD_PERIOD')
  })

  test('a company reads what it earned and lost; week and month are the same days added', async () => {
    await db.callAs(`select public.credit(public.current_player_id(), 'SELL', 500)::text as result`)
    await db.callAs(`select public.credit(public.current_player_id(), 'BUY', -200)::text as result`)
    await db.callAs(`select public.credit(public.current_player_id(), 'WAGES', -30)::text as result`)
    // the job reads the ledger up to its lag before p_now: an hour ahead reads every row above
    await db.callAs(`select public.tick_history(now() + interval '1 hour')::text as result`)

    const day = await worldHistory<HistoryCompanyPoint>('me', null, 'day')
    expect(day.ok).toBe(true)
    if (!day.ok) return
    expect(day.value.period).toBe('day')
    expect(day.value.points.reduce((s, p) => s + p.earned, 0)).toBe(500)
    expect(day.value.points.reduce((s, p) => s + p.lost, 0)).toBe(230)
    for (const period of ['week', 'month'] as const) {
      const r = await worldHistory<HistoryCompanyPoint>('me', null, period)
      expect(r.ok).toBe(true)
      if (!r.ok) continue
      expect(r.value.points.reduce((s, p) => s + p.earned - p.lost, 0)).toBe(270)
    }
  })

  test('a good answers open, high, low, close and its volume; a city its four figures; the world its four holders', async () => {
    await db.callAs(`select public.tick_price_snapshot(now())::text as result`)
    await db.callAs(`select public.tick_stats(now())::text as result`)
    await db.callAs(`select public.tick_history(now())::text as result`)
    const code = await db.callAs<string>(`select (select g.code from public.history_good_day h join public.goods g on g.id = h.good_id where h.close is not null limit 1) as result`)
    const good = await worldHistory<HistoryGoodPoint>('good', code, 'month')
    expect(good.ok).toBe(true)
    if (!good.ok) return
    const p = good.value.points.at(-1)!
    expect(p.high!).toBeGreaterThanOrEqual(p.low!)
    expect(p.high!).toBeGreaterThanOrEqual(p.close!)
    expect(p.low!).toBeLessThanOrEqual(p.open!)
    expect(typeof p.sold).toBe('number')

    const city = await db.callAs<string>(`select (select p.code from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1) as result`)
    const c = await worldHistory<Record<string, number>>('city', city, 'week')
    expect(c.ok).toBe(true)
    if (!c.ok) return
    expect(Object.keys(c.value.points.at(-1)!).sort()).toEqual(['at', 'income', 'profit', 'purse', 'spending'])

    const w = await worldHistory<Record<string, number>>('world', null, 'day')
    expect(w.ok).toBe(true)
    if (!w.ok) return
    expect(Object.keys(w.value.points.at(-1)!).sort()).toEqual(['at', 'bought', 'cities', 'merchants', 'minted', 'players', 'removed', 'set_aside', 'sold'])
  })

  test("another player's books are not served; a merchant company's are", async () => {
    const theirs = await db.callAs<string>(`select (select company_name from public.players where is_npc limit 1) as result`)
    if (theirs !== null) {
      const r = await worldHistory<HistoryCompanyPoint>('company', theirs, 'day')
      expect(r.ok).toBe(true)
    }
    const mine = await db.callAs<string>(`select (select company_name from public.players where id = public.current_player_id()) as result`)
    const refused = await worldHistory<HistoryCompanyPoint>('company', mine, 'day')
    expect(refused.ok).toBe(false)
  })
})

test.describe('the page', () => {
  const box = (testid: string) => (page: import('@playwright/test').Page) =>
    page.evaluate((id) => {
      const r = document.querySelector(`[data-testid="${id}"]`)!.getBoundingClientRect()
      return { top: r.top, height: r.height }
    }, testid)
  const flat = (page: import('@playwright/test').Page) =>
    page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)

  for (const vp of [PHONE, WIDE]) {
    test(`Stats and the Report offer Day, Week, Month at ${vp.width}px and a press moves nothing`, async ({ page, request, baseURL }) => {
      test.setTimeout(420_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await page.setViewportSize(vp)
      await page.goto('stats')
      await ready(page)
      const card = page.getByTestId('history-world')
      await expect(card).toBeVisible({ timeout: 120_000 })
      // the page may scroll to reach the picker; from there a press may move nothing
      await card.getByRole('tablist').scrollIntoViewIfNeeded()
      const before = await box('history-world')(page)
      for (const [word, period] of [['Week', 'week'], ['Month', 'month'], ['Day', 'day']] as const) {
        await card.getByRole('tab', { name: word, exact: true }).click()
        await expect(card).toHaveAttribute('data-period', period, { timeout: 30_000 })
        expect(await box('history-world')(page)).toEqual(before)
        expect(await flat(page)).toBe(true)
      }

      await page.goto('command')
      await ready(page)
      await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Report', exact: true }).click()
      await page.getByTestId('report-history').click() // the Report keeps its record behind one door, so the face stays one glass tall
      const mine = page.getByTestId('history-me')
      await expect(mine).toBeVisible({ timeout: 120_000 })
      await mine.getByRole('tablist').scrollIntoViewIfNeeded()
      const was = await box('history-me')(page)
      await mine.getByRole('tab', { name: 'Month', exact: true }).click()
      await expect(mine).toHaveAttribute('data-period', 'month', { timeout: 30_000 })
      expect(await box('history-me')(page)).toEqual(was)
      expect(await flat(page)).toBe(true)
    })
  }
})
