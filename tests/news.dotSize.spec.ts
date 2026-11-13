// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A NEWS DOT IS A 44-PX PRESS TARGET ON EVERY CHART THAT SHOWS ONE — 2026-11-11 (docs/dev-log/2026-11-11-news-dot-size.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE GAP THIS CLOSES. The dot of 0347 (#573) was a 24-px button. The 44-px law of every control is measured by the page specs
// (tests/design.fixture.ts `smallControls`), but they open the BUILT world, and on it a chart has a dot only by accident: a price
// chart's record starts a quarter hour before the tab opened, so the built world's own "Update" rows stand on it only when the world
// image was built within that quarter hour. tests/hq.design.spec.ts was red for exactly that long after each image build, and green
// the rest of the day; CI builds (or restores) the image long before the HQ's spec opens it. tests/news.chart.spec.ts did put news on
// a chart, and asked 24 px of it.
//
// HERE THE NEWS IS PUT THERE, with fixed facts: the built world with its first count half an hour old (so the Stats charts' record
// starts before the news) and FOUR world headlines written 10 min, 5 min, 1 min and 55 s before the seed (so they stand inside the
// quarter hour a price chart draws; the first two stand apart as NEIGHBOURS, and the last two are always one dot). Then, at 390 and at 1,280, on EVERY surface that draws dots
// — Stats Overview, Stats Merchants, a Stats city page, the HQ's market chart, the desk's good chart — every dot on the glass is read:
//   • its target is at least 44 × 44 (the law hq.design measures), inside its chart's box and inside the glass;
//   • no two targets of a chart overlap (marks closer than a target are ONE dot: newsMarksModel);
//   • the small mark stands inside its target, and the target is what a press at its centre reaches;
//   • pressing it opens the card with exactly that dot's news, and the chart's box does not move.
// It names NewsDots.tsx, newsMarksModel.ts, useChartNews.tsx, NewsCard.tsx, PriceChart.tsx, SeriesChart.tsx, MarketLeft.tsx,
// TradePanel.tsx, Overview.tsx, Merchants.tsx, CityDetail.tsx, PriceRows.tsx, PriceTray.tsx, PortPrices.tsx, PortTrade.tsx,
// TradeTray.tsx and MarketFace.tsx so CI's rule N selects it.
//
// 2026-11-13 (docs/dev-log/2026-11-13-news-dots-trays.md): TWO MORE SURFACES, the trays' chart (PriceRows): the quay's trade tray
// (More, then Trend) and the map's good panel. AND "THE CHART'S BOX DOES NOT MOVE" IS READ IN THE PAGE'S OWN TERMS (`placeOf`): the
// box plus how far everything it scrolls in is scrolled. This test was red about one run in twenty, "pressing moved its chart" by
// 372 px, and nothing had moved in the page: a dot's target crept a fraction of a px with the clock, Playwright found it "not stable"
// under the press and tried again, and its second try scrolls the dot to the glass's foot. The target now stands still (the lattice,
// newsMarksModel), and a scroll is no longer read as a re-flow. A block that lands late above a chart still moves its place.

import { test, expect, type Page } from '@playwright/test'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile } from '../src/lib/db/worldImage'
import { NEWS_HIT_PX } from '../src/components/ui/newsMarksModel'
import { PHONE, reachable, ready } from './appReady.fixture'
import { openCityPanel } from './openCity.fixture'

const WIDE = { width: 1280, height: 800 }
/** The probe's headlines: seconds before the seed. The last two are 5 s apart: one dot on any chart. */
const PROBE_AGO_S = [600, 300, 60, 55] as const
const PROBE_KEY = 'probe:dot-size:'

/** The built world, its first count half an hour old, with the four probe headlines. Seeded for each test: the facts are minutes old. */
async function worldWithNews(): Promise<Buffer> {
  const dir = path.resolve('dist', 'db')
  const name = existsSync(dir) ? readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f)) : undefined
  if (!name) throw new Error(`no world image under ${dir} — run \`npm run build\` first`)
  const { PGlite } = await import('@electric-sql/pglite')
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, name)))) })
  try {
    // the Stats charts' record starts BEFORE the news (a built world has no count; a dot outside a chart's time is not drawn)
    await pg.query(`select public.tick_stats(now() - interval '30 minutes')::text`)
    // THE PROBE'S HEADLINES ARE THE ONLY NEWS OF THIS WORLD (2026-11-13). The image carries one "Update" row per lit migration, written
    // when the image was BUILT: on an image minutes old they stand inside the charts' time and join, or bridge, the probe's dots (seen
    // as "no chart drew two dots", and as a fifth dot beside the probe's), and every migration adds one. This is the test's own copy
    // of the world, served to this one page: its append-only guard is stepped over for this one statement.
    await pg.exec(`set session_replication_role = replica; delete from public.world_news; set session_replication_role = default;`)
    const left = await pg.query<{ n: number }>(`select count(*)::int as n from public.world_news`)
    if (left.rows[0].n !== 0) throw new Error(`the image's own news was not taken out: ${left.rows[0].n} rows left`)
    for (const [i, ago] of PROBE_AGO_S.entries()) {
      await pg.query(
        `insert into public.world_news (at, kind, importance, scope, key, detail)
         select now() - make_interval(secs => $1::int), k.kind, k.importance, k.scope, $2,
                jsonb_build_object('words', jsonb_build_object('title', jsonb_build_object('en', $3::text, 'ko', $3::text)))
           from public.news_kinds k where k.kind = 'UPDATE'`,
        [ago, `${PROBE_KEY}${i}`, `Probe ${i + 1}`],
      )
    }
    const n = await pg.query<{ n: number }>(`select count(*)::int as n from public.world_news where key like '${PROBE_KEY}%' and importance = 3 and scope = 'world'`)
    if (n.rows[0].n !== PROBE_AGO_S.length) throw new Error(`the probe wrote ${n.rows[0].n} of its ${PROBE_AGO_S.length} headlines`)
    return Buffer.from(await (await pg.dumpDataDir('gzip')).arrayBuffer())
  } finally {
    await pg.close()
  }
}

interface DotRead {
  label: string
  /** The news it holds (`data-news-ids`): the dot's own name. */
  ids: string
  /** Which of the scope's charts it stands on, in the page's order. */
  chart: number
  n: number
  box: [number, number, number, number]
  mark: [number, number, number, number] | null
  layer: [number, number, number, number]
}

/** Every dot inside `scope`, as it stands on the glass. Self-contained, shipped into the page. */
const READ_DOTS = (scope: string): { glass: number; dots: DotRead[] } => {
  const rect = (e: Element): [number, number, number, number] => {
    const r = e.getBoundingClientRect()
    return [r.left, r.top, r.width, r.height]
  }
  const dots: DotRead[] = []
  let chart = -1
  for (const root of document.querySelectorAll(scope)) {
    for (const layer of root.querySelectorAll('[data-testid="news-dots"]')) {
      chart++
      for (const dot of layer.querySelectorAll('[data-testid="news-dot"]')) {
        const b = rect(dot)
        const label = dot.getAttribute('aria-label') ?? ''
        const mark = dot.querySelector('[data-testid="news-dot-mark"]')
        dots.push({
          label,
          ids: dot.getAttribute('data-news-ids') ?? '',
          chart,
          n: Number(/\d+/.exec(label)?.[0] ?? NaN),
          box: b,
          mark: mark ? rect(mark) : null,
          layer: rect(layer),
        })
      }
    }
  }
  return { glass: innerWidth, dots }
}

/** WHERE A BOX STANDS IN ITS PAGE: its box on the glass plus how far each thing it scrolls in (and the page) is scrolled. A scroll
 *  does not change it; a block above it that grows, lands or leaves does. Self-contained, shipped into the page. */
const placeOf = (e: Element): { x: number; y: number; width: number; height: number } => {
  const r = e.getBoundingClientRect()
  let x = r.left + scrollX
  let y = r.top + scrollY
  for (let p = e.parentElement; p !== null; p = p.parentElement) {
    x += p.scrollLeft
    y += p.scrollTop
  }
  return { x, y, width: r.width, height: r.height }
}

/** The most reads one surface is given: a chart holds a dot per 44 px at most, and a regrouping costs one more read. */
const MAX_ROUNDS = 24
/** Every step of a press says within this long whether it could be done. */
const STEP_MS = 10_000

/** The laws of the dots of one surface, as sentences; and each dot pressed.
 *
 *  A DOT IS ASKED FOR BY ITS OWN NEWS, AND THE CHART IS READ AGAIN BEFORE EACH PRESS (2026-11-13). The dots of a chart are not a fixed
 *  list: marks closer than a target are one dot, and a live chart's time stretches with the clock, so two neighbours come together
 *  and become one. Counting once and then pressing "the third" waited for a dot that no longer was, until the test's own clock ran
 *  out (15 minutes on CI). A dot that is gone when its turn comes was regrouped: the chart is read again and what stands there now is
 *  measured and pressed. */
async function measure(page: Page, where: string, scope: string, o: { headlines: number; most: number }): Promise<string[]> {
  const first = page.locator(scope).getByTestId('news-dot').first()
  await expect(first, `${where}: the chart shows no news dot`).toBeVisible({ timeout: 90_000 })
  await first.scrollIntoViewIfNeeded({ timeout: STEP_MS })
  await page.waitForTimeout(300)
  // a law is read again at every read of the chart: a sentence said twice is returned once
  const bad: string[] = []
  const px = (b: readonly number[]) => `${Math.round(b[2] * 10) / 10}×${Math.round(b[3] * 10) / 10} at ${Math.round(b[0])},${Math.round(b[1])}`
  const pressed = new Set<string>()
  let regrouped = 0
  for (let round = 0; ; round++) {
    const { glass, dots } = await page.evaluate(READ_DOTS, scope)
    if (round === 0) console.log(`DOTS ${where}: ${dots.map((d) => `"${d.label}" ${px(d.box)} mark ${d.mark ? px(d.mark) : '-'}`).join(' · ')}`)
    // THE LAWS, of the chart as it stands at this read
    dots.forEach((d, i) => {
      const [l, t, w, h] = d.box
      const [ll, lt, lw, lh] = d.layer
      if (w < NEWS_HIT_PX - 0.5 || h < NEWS_HIT_PX - 0.5) bad.push(`${where}: the target of "${d.label}" is ${px(d.box)} — the law is ${NEWS_HIT_PX} × ${NEWS_HIT_PX}`)
      if (l < ll - 0.5 || t < lt - 0.5 || l + w > ll + lw + 0.5 || t + h > lt + lh + 0.5) bad.push(`${where}: the target of "${d.label}" (${px(d.box)}) hangs out of its chart's box (${px(d.layer)})`)
      if (l < -0.5 || l + w > glass + 0.5) bad.push(`${where}: the target of "${d.label}" (${px(d.box)}) hangs off the ${glass}-px glass`)
      if (d.mark === null) bad.push(`${where}: "${d.label}" draws no mark`)
      else {
        const [ml, mt, mw, mh] = d.mark
        if (ml < l - 0.5 || mt < t - 0.5 || ml + mw > l + w + 0.5 || mt + mh > t + h + 0.5) bad.push(`${where}: the mark of "${d.label}" (${px(d.mark)}) stands outside its target (${px(d.box)})`)
        if (mw > 24 || mh > 24) bad.push(`${where}: the mark of "${d.label}" is ${px(d.mark)} — the mark stays small`)
      }
      if (!Number.isFinite(d.n) || d.n < 1) bad.push(`${where}: the dot's label "${d.label}" carries no count`)
      if (d.n !== d.ids.split(' ').length) bad.push(`${where}: the dot "${d.label}" holds ${d.ids.split(' ').length} news`)
      for (const e of dots.slice(i + 1)) {
        if (e.chart !== d.chart) continue
        const ox = Math.min(l + w, e.box[0] + e.box[2]) - Math.max(l, e.box[0])
        const oy = Math.min(t + h, e.box[1] + e.box[3]) - Math.max(t, e.box[1])
        if (ox > 0.5 && oy > 0.5) bad.push(`${where}: the targets of "${d.label}" and "${e.label}" overlap by ${Math.round(ox)} × ${Math.round(oy)} px`)
      }
    })
    // the probe's headlines stand on every chart, each in one dot only: no dot of this chart was lost to another's target
    const charts = [...new Set(dots.map((d) => d.chart))]
    for (const c of charts) {
      const ids = dots.filter((d) => d.chart === c).flatMap((d) => d.ids.split(' '))
      if (ids.length !== o.headlines || new Set(ids).size !== o.headlines) bad.push(`${where}: a chart's dots carry ${ids.length} news (${new Set(ids).size} different) — the probe wrote ${o.headlines}`)
      o.most = Math.max(o.most, dots.filter((d) => d.chart === c).length)
    }

    // PRESS THE NEXT ONE NOT YET PRESSED: the card holds exactly that dot's news, and the chart's box does not move
    const i = dots.findIndex((d) => !pressed.has(`${d.chart}:${d.ids}`))
    if (i < 0) break
    const next = dots[i]
    if (round >= MAX_ROUNDS) {
      bad.push(`${where}: the chart's dots did not settle in ${MAX_ROUNDS} reads (${regrouped} regroupings)`)
      break
    }
    pressed.add(`${next.chart}:${next.ids}`)
    const layer = page.locator(scope).getByTestId('news-dots').nth(next.chart)
    const dot = layer.locator(`[data-testid="news-dot"][data-news-ids="${next.ids}"]`)
    const name = `"${next.label}" (news ${next.ids})`
    // each step answers in STEP_MS; a step that could not be done because the dot is no longer there was a regrouping, not a fault
    const step = async <T,>(what: string, run: () => Promise<T>): Promise<T | undefined> => {
      try {
        return await run()
      } catch {
        if ((await dot.count()) === 0) regrouped++
        else bad.push(`${where}: ${name} ${what}`)
        return undefined
      }
    }
    if ((await step('cannot be scrolled to', () => dot.scrollIntoViewIfNeeded({ timeout: STEP_MS }).then(() => true))) === undefined) continue
    // what a press at the target's centre reaches: this dot, or the name of what lies over it
    const reaches = await step('cannot be read', () =>
      dot.evaluate(
        (e) => {
          const r = e.getBoundingClientRect()
          const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
          return hit === null ? 'nothing' : hit.closest('[data-testid="news-dot"]') === e ? 'itself' : (hit.getAttribute('data-testid') ?? hit.tagName.toLowerCase())
        },
        undefined,
        { timeout: STEP_MS },
      ),
    )
    if (reaches === undefined) continue
    if (reaches !== 'itself') bad.push(`${where}: a press at the centre of ${name} reaches ${reaches}`)
    const before = await layer.evaluate(placeOf, undefined, { timeout: STEP_MS })
    // a dot another target lies over cannot be pressed: said as a sentence, not left to run the clock out
    if ((await step('cannot be pressed — something lies over it', () => dot.click({ timeout: STEP_MS }).then(() => true))) === undefined) continue
    const card = page.getByTestId('news-card')
    await expect(card, `${where}: pressing ${name} opened no card`).toBeVisible({ timeout: STEP_MS })
    const items = await card.getByTestId('news-item').count()
    // the card lists at most five (NewsCard's CARD_MAX) and says how many more the dot holds: every migration's own "Update" row lands in one dot, and 0362's made it six
    if (items !== Math.min(dots[i].n, 5)) bad.push(`${where}: "${dots[i].label}" opened a card of ${items} news`)
    const after = await layer.evaluate(placeOf)
    if (JSON.stringify(after) !== JSON.stringify(before)) bad.push(`${where}: pressing ${name} moved its chart: ${JSON.stringify(before)} → ${JSON.stringify(after)}`)
    if (!(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))) bad.push(`${where}: the page scrolls sideways with the card of ${name} open`)
    await card.getByTestId('tray-close').click({ timeout: STEP_MS })
    await expect(card).toHaveCount(0, { timeout: STEP_MS })
  }
  if (regrouped > 0) console.log(`DOTS ${where}: regrouped ${regrouped} time(s) under the presses; read again each time`)
  if (pressed.size === 0) bad.push(`${where}: no dot was pressed`)
  return [...new Set(bad)]
}

/** THE WHOLE TEST'S TIME, STATED: five minutes. A run is about half a minute here and a minute on CI, and it does not grow with the
 *  migrations (the image's own news is taken out of the probe's world, in `worldWithNews`). It was 900 s, and a wait with no limit
 *  used all of it. */
const TEST_MS = 300_000

const face = (page: Page, name: string) => page.getByRole('tablist').first().getByRole('tab', { name, exact: true })

test.use({ deviceScaleFactor: 2 })

for (const glass of [PHONE, WIDE]) {
  test(`every news dot on every chart is a 44-px target that opens its own news — ${glass.width}px`, async ({ page, request, baseURL }) => {
    test.setTimeout(TEST_MS)
    expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`).toBe(true)
    const world = await worldWithNews()
    await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: world, contentType: 'application/gzip' }))
    await page.setViewportSize(glass)
    const at = (surface: string) => `${surface} @${glass.width}`
    const bad: string[] = []
    const all = { headlines: PROBE_AGO_S.length, most: 0 }

    // THE HQ'S MARKET CHART (PriceChart, MarketLeft) — the surface tests/hq.design.spec.ts walks
    await page.goto('city')
    await ready(page)
    await expect(page.getByTestId('city-hall-panel')).toBeVisible({ timeout: 180_000 })
    await page.getByTestId('city-building-market').click()
    bad.push(...(await measure(page, at('hq market'), '[data-testid="city-market-chart"]', all)))

    // THE QUAY'S TRADE TRAY (PriceRows in TradeTray; owner row 216): the same city's market, a good's Buy, More, then the Trend row
    // unfolds the chart. Its dots are the same dots; the card a press opens is a tray of its own.
    await page.getByTestId('trade-buy').first().click()
    const quayTray = page.getByTestId('trade-tray')
    await expect(quayTray).toBeVisible({ timeout: 60_000 })
    await quayTray.getByTestId('trade-tray-more').click()
    const trend = quayTray.getByTestId('trend-row')
    await expect(trend).toHaveAttribute('aria-expanded', 'false', { timeout: 60_000 })
    // the row's own corner: its middle is the span picker, whose press picks a span and does not unfold the row
    await trend.click({ position: { x: 12, y: 12 } })
    await expect(quayTray.getByTestId('price-chart')).toBeVisible({ timeout: 60_000 })
    bad.push(...(await measure(page, at('quay tray'), '[data-testid="trade-tray"]', all)))

    // THE MAP'S GOOD PANEL (PriceRows in PriceTray; owner row 216): Map, Lisbon, Market, a good: its chart stands unfolded
    await page.goto('map')
    await ready(page)
    await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
    await openCityPanel(page, 'LIS', 'Lisbon')
    await page.getByRole('tab', { name: 'Market' }).click()
    await expect(page.getByTestId('quay-ledger')).toBeVisible({ timeout: 60_000 })
    await page.locator('[data-testid="trade-row"] button:enabled').filter({ hasText: /^buy/i }).first().click()
    await expect(page.getByTestId('price-tray').getByTestId('price-chart')).toBeVisible({ timeout: 60_000 })
    bad.push(...(await measure(page, at('map good'), '[data-testid="price-tray"]', all)))

    // THE DESK'S GOOD CHART (PriceChart, TradePanel)
    await page.goto('command')
    await ready(page)
    await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 180_000 })
    await page.getByTestId('trade-buy').first().click()
    await expect(page.getByTestId('good-detail').first()).toBeVisible({ timeout: 60_000 })
    bad.push(...(await measure(page, at('desk good'), '[data-testid="trend-row"]', all)))

    // STATS → OVERVIEW (SeriesChart): the world's money, and whichever of sold / bought is drawn
    await page.goto('stats')
    await ready(page)
    await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 180_000 })
    bad.push(...(await measure(page, at('stats world'), '[data-testid="stats-chart-world"]', all)))
    bad.push(...(await measure(page, at('stats overview'), '[data-testid="stats-overview"]', all)))

    // STATS → MERCHANTS (SeriesChart)
    await face(page, 'Merchants').click()
    bad.push(...(await measure(page, at('stats merchants'), '[data-testid="stats-chart-purses"]', all)))

    // STATS → A CITY'S PAGE (SeriesChart)
    await face(page, 'Cities').click()
    const rows = page.getByTestId('stats-city-open')
    await expect(rows.first()).toBeVisible({ timeout: 60_000 })
    await rows.first().click()
    await expect(page.getByTestId('stats-city-page')).toBeVisible({ timeout: 60_000 })
    bad.push(...(await measure(page, at('stats city'), '[data-testid="stats-city-overview"]', all)))

    if (bad.length > 0) console.log(`DOT LAWS @${glass.width}: ${bad.length} lines\n  ${bad.join('\n  ')}`)
    // NON-VACUITY: some chart drew NEIGHBOURS (two dots or more), so "no target lies over another" measured something
    expect(all.most, 'no chart drew two dots — the neighbours were not measured').toBeGreaterThanOrEqual(2)
    expect(bad, 'a news dot is not the 44-px target it must be').toEqual([])
  })
}
