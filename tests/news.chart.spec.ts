// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A HAPPENING MAKES A DOT ON THE CHART, AND THE DOT SAYS WHAT CAUSED IT — 0347 (owner row 216; docs/NEWS_AND_MARKERS.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Owner, 2026-10-26: *"when an update or a happening is made, it should make a point on the chart, and i will be able to press it to
// see what caused it (major event, real time news-like feature)"*.
//
// THE HAPPENING is real: the served world is the built world with two great powers' stance changed in public.power_relations, so the
// RELATIONS writer (0347's trigger) wrote its news row in that transaction. Then, at 390 and at 1,280, at DPR 2:
//   1. Stats → Overview: the world's money chart carries a dot on its time axis; pressing it opens the card (a Tray, out of the flow:
//      the chart's card does not move by a pixel and nothing scrolls sideways), and the card says what happened, and what moved.
//   2. Stats → News: the face lists the happening, newest first, beside 0347's own "Update: News" row; nothing scrolls sideways.
// It names NewsDots.tsx, NewsCard.tsx, useChartNews.tsx, News.tsx, Overview.tsx, SeriesChart.tsx and StatsScreen.tsx so CI's rule N selects it.

import { test, expect, type Page } from '@playwright/test'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile } from '../src/lib/db/worldImage'
import { PHONE, reachable, ready } from './appReady.fixture'

const WIDE = { width: 1280, height: 800 }

let image: Buffer | null = null
let headline: { en: string; move: string } | null = null

/** The built world with ONE happening: the first pair of great powers made allies (or rivals, if they were allies). */
async function happenedWorld(): Promise<Buffer> {
  if (image) return image
  const dir = path.resolve('dist', 'db')
  const name = existsSync(dir) ? readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f)) : undefined
  if (!name) throw new Error(`no world image under ${dir} — run \`npm run build\` first`)
  const { PGlite } = await import('@electric-sql/pglite')
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, name)))) })
  try {
    const before = await pg.query<{ n: number }>(`select count(*)::int as n from public.world_news where kind = 'RELATIONS'`)
    await pg.exec(`update public.power_relations r set stance = case when r.stance = 'ally' then 'rival' else 'ally' end
                    where (r.a, r.b) = (select x.a, x.b from public.power_relations x order by x.a, x.b limit 1)`)
    const row = await pg.query<{ a: string; b: string; stance: string; was: string; now: string; n: number }>(
      `select w.detail->'words'->'a'->>'name' as a, w.detail->'words'->'b'->>'name' as b, w.detail->'words'->'stance'->>'en' as stance,
              w.detail->'before'->>'en' as was, w.detail->'after'->>'en' as now,
              (select count(*)::int from public.world_news where kind = 'RELATIONS') as n
         from public.world_news w where w.kind = 'RELATIONS' order by w.id desc limit 1`,
    )
    const r = row.rows[0]
    if (!r || r.n !== before.rows[0].n + 1) throw new Error(`the stance change did not write one RELATIONS row: ${JSON.stringify(r)}`)
    headline = { en: `${r.a} and ${r.b}: now ${r.stance}`, move: `${r.was} → ${r.now}` }
    image = Buffer.from(await (await pg.dumpDataDir('gzip')).arrayBuffer())
  } finally {
    await pg.close()
  }
  return image
}

const noSideways = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)

async function openStats(page: Page, glass: { width: number; height: number }) {
  const world = await happenedWorld()
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: world, contentType: 'application/gzip' }))
  await page.setViewportSize(glass)
  await page.goto('stats')
  await ready(page)
  await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 180_000 })
}

test.use({ deviceScaleFactor: 2 })

for (const glass of [PHONE, WIDE]) {
  test(`a happening is a dot on the world chart, and pressing it says what caused it — ${glass.width}px`, async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await openStats(page, glass)
    const card = page.getByTestId('stats-chart-world')
    const dots = card.getByTestId('news-dot')
    await expect(dots.first()).toBeVisible({ timeout: 60_000 })
    await card.scrollIntoViewIfNeeded()

    // THE DOT stands on the plot's floor, inside the plot's width
    const plot = await card.locator('[data-plot]').boundingBox()
    const n = await dots.count()
    let found = false
    for (let i = 0; i < n && !found; i++) {
      const dot = dots.nth(i)
      const box = await dot.boundingBox()
      expect(box, 'a dot has no box').not.toBeNull()
      expect(plot).not.toBeNull()
      const cx = box!.x + box!.width / 2
      const cy = box!.y + box!.height / 2
      expect(cx).toBeGreaterThanOrEqual(plot!.x - 1)
      expect(cx).toBeLessThanOrEqual(plot!.x + plot!.width + 1)
      expect(Math.abs(cy - (plot!.y + plot!.height))).toBeLessThan(2)
      expect(box!.width, 'a dot is a 24-px target').toBeGreaterThanOrEqual(24)

      // PRESS IT: the card opens over the page; the chart's card does not move
      const before = await card.boundingBox()
      await dot.click()
      const tray = page.getByTestId('news-card')
      await expect(tray).toBeVisible({ timeout: 10_000 })
      const after = await card.boundingBox()
      expect(after, 'the chart card moved when its dot was pressed').toEqual(before)
      expect(await page.getByTestId('stats-big-chart').count(), 'the press reached the chart under the dot').toBe(0)
      if ((await tray.getByTestId('news-headline').filter({ hasText: headline!.en }).count()) > 0) {
        found = true
        const line = tray.getByTestId('news-item').filter({ hasText: headline!.en })
        await expect(line.getByTestId('news-move')).toHaveText(headline!.move)
        await expect(line.getByTestId('news-ago')).toContainText(/ago|just now/)
        await expect(line.getByTestId('news-ago')).toContainText('UTC')
      }
      expect(await noSideways(page), 'the page scrolls sideways with the card open').toBe(true)
      await tray.getByTestId('tray-close').click()
      await expect(tray).toHaveCount(0, { timeout: 10_000 })
    }
    expect(found, `no dot on the world chart opened "${headline!.en}"`).toBe(true)
  })

  test(`the News face lists the happening, newest first — ${glass.width}px`, async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await openStats(page, glass)
    await page.getByRole('tablist').first().getByRole('tab', { name: 'News', exact: true }).click()
    const face = page.getByTestId('stats-news')
    await expect(face).toBeVisible()
    const items = face.getByTestId('news-item')
    await expect(items.first()).toBeVisible({ timeout: 60_000 })
    await expect(items.first().getByTestId('news-headline')).toHaveText(headline!.en)
    await expect(items.first().getByTestId('news-move')).toHaveText(headline!.move)
    await expect(face.getByTestId('news-headline').filter({ hasText: 'Update: News' })).toHaveCount(1)
    // My cities: a fresh house lies at one city; this happening is the world's, so it is not hers
    await face.getByRole('tab', { name: 'My cities', exact: true }).click()
    await expect(face.getByTestId('news-headline').filter({ hasText: headline!.en })).toHaveCount(0, { timeout: 30_000 })
    expect(await noSideways(page), 'the page scrolls sideways on the News face').toBe(true)
    // the face strip itself (six faces) wraps rather than scrolls
    const strip = page.getByRole('tablist').first()
    const sb = await strip.boundingBox()
    expect(sb!.x + sb!.width).toBeLessThanOrEqual(glass.width + 0.5)
  })
}
