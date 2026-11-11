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
// TradePanel.tsx, Overview.tsx, Merchants.tsx and CityDetail.tsx so CI's rule N selects it.

import { test, expect, type Page } from '@playwright/test'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile } from '../src/lib/db/worldImage'
import { NEWS_HIT_PX } from '../src/components/ui/newsMarksModel'
import { PHONE, reachable, ready } from './appReady.fixture'

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
  for (const root of document.querySelectorAll(scope)) {
    for (const layer of root.querySelectorAll('[data-testid="news-dots"]')) {
      for (const dot of layer.querySelectorAll('[data-testid="news-dot"]')) {
        const b = rect(dot)
        const label = dot.getAttribute('aria-label') ?? ''
        const mark = dot.querySelector('[data-testid="news-dot-mark"]')
        dots.push({
          label,
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

/** The laws of the dots of one surface, as sentences; and each dot pressed. */
async function measure(page: Page, where: string, scope: string, o: { headlines: number; most: number }): Promise<string[]> {
  const first = page.locator(scope).getByTestId('news-dot').first()
  await expect(first, `${where}: the chart shows no news dot`).toBeVisible({ timeout: 90_000 })
  await first.scrollIntoViewIfNeeded()
  await page.waitForTimeout(300)
  const { glass, dots } = await page.evaluate(READ_DOTS, scope)
  const bad: string[] = []
  const px = (b: readonly number[]) => `${Math.round(b[2] * 10) / 10}×${Math.round(b[3] * 10) / 10} at ${Math.round(b[0])},${Math.round(b[1])}`
  console.log(`DOTS ${where}: ${dots.map((d) => `"${d.label}" ${px(d.box)} mark ${d.mark ? px(d.mark) : '-'}`).join(' · ')}`)
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
    for (const e of dots.slice(i + 1)) {
      if (e.layer[0] !== ll || e.layer[1] !== lt) continue
      const ox = Math.min(l + w, e.box[0] + e.box[2]) - Math.max(l, e.box[0])
      const oy = Math.min(t + h, e.box[1] + e.box[3]) - Math.max(t, e.box[1])
      if (ox > 0.5 && oy > 0.5) bad.push(`${where}: the targets of "${d.label}" and "${e.label}" overlap by ${Math.round(ox)} × ${Math.round(oy)} px`)
    }
  })
  // the probe's headlines stand on every chart: no dot of this chart was lost to another's target
  const layers = new Map<string, number>()
  for (const d of dots) layers.set(d.layer.join(','), (layers.get(d.layer.join(',')) ?? 0) + d.n)
  o.most = Math.max(o.most, ...[...layers.keys()].map((k) => dots.filter((d) => d.layer.join(',') === k).length))
  for (const [, n] of layers) if (n < o.headlines) bad.push(`${where}: a chart's dots carry ${n} news — the probe wrote ${o.headlines}`)

  // PRESS EACH: the card holds exactly that dot's news, and the chart's box does not move
  const all = page.locator(scope).getByTestId('news-dot')
  for (let i = 0; i < dots.length; i++) {
    const dot = all.nth(i)
    await dot.scrollIntoViewIfNeeded()
    // what a press at the target's centre reaches: this dot, or the name of what lies over it
    const reaches = await dot.evaluate((e) => {
      const r = e.getBoundingClientRect()
      const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
      return hit === null ? 'nothing' : hit.closest('[data-testid="news-dot"]') === e ? 'itself' : (hit.getAttribute('data-testid') ?? hit.tagName.toLowerCase())
    })
    if (reaches !== 'itself') bad.push(`${where}: a press at the centre of "${dots[i].label}" reaches ${reaches}`)
    const layer = dot.locator('xpath=..')
    const before = await layer.boundingBox()
    // a dot another target lies over cannot be pressed: said as a sentence, not left to run the clock out
    const pressed = await dot.click({ timeout: 10_000 }).then(() => true, () => false)
    if (!pressed) {
      bad.push(`${where}: "${dots[i].label}" (dot ${i + 1} of ${dots.length}) cannot be pressed — something lies over it`)
      continue
    }
    const card = page.getByTestId('news-card')
    await expect(card, `${where}: pressing "${dots[i].label}" opened no card`).toBeVisible({ timeout: 10_000 })
    const items = await card.getByTestId('news-item').count()
    if (items !== dots[i].n) bad.push(`${where}: "${dots[i].label}" opened a card of ${items} news`)
    const after = await layer.boundingBox()
    if (JSON.stringify(after) !== JSON.stringify(before)) bad.push(`${where}: pressing "${dots[i].label}" moved its chart: ${JSON.stringify(before)} → ${JSON.stringify(after)}`)
    if (!(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))) bad.push(`${where}: the page scrolls sideways with the card of "${dots[i].label}" open`)
    await card.getByTestId('tray-close').click()
    await expect(card).toHaveCount(0, { timeout: 10_000 })
  }
  return bad
}

const face = (page: Page, name: string) => page.getByRole('tablist').first().getByRole('tab', { name, exact: true })

test.use({ deviceScaleFactor: 2 })

for (const glass of [PHONE, WIDE]) {
  test(`every news dot on every chart is a 44-px target that opens its own news — ${glass.width}px`, async ({ page, request, baseURL }) => {
    test.setTimeout(900_000)
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
