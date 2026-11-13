import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DRIVE AUDIT, 2026-11-08 — STATS, DRIVEN AS THE OWNER WOULD
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/OWNER_REQUESTS.md rows 289 / 294 / 295 (market and gold graphs by day, week, month; the Cities
// and Markets faces like Merchants: two charts over the list), the owner's twice-said chart rule
// (no falling right edge; the last point a whole period), 256 (the secondly data renewal stays),
// 273 / 298 (a city's People block and its kind), 247 (the Money log's tappable things in a grid)
// and 296 (the Report's Day and Week). The shipped world is young and empty — "Line starts at the
// next count" — so the first test COUNTS a series into a copy of the image: eight quarter-hour
// counts at the slot edges, a credit between each, and reads what each face then DRAWS: the
// `path` of every series chart, point by point. No spec in the suite reads a drawn chart today.

const OUT = 'docs/dev-log/2026-11-08-drive-audit'
const WIDE = { width: 1280, height: 800 }
const SLOT_MS = 900_000
const COUNTS = 8

test.use({ deviceScaleFactor: 2 })

async function shot(page: Page, name: string) {
  await page.waitForTimeout(300)
  await page.screenshot({ path: `${OUT}/${name}.png` })
}

async function open(page: Page, request: Parameters<typeof reachable>[0], baseURL: string | undefined, path: string, size = WIDE) {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(size)
  await page.goto(path)
  await ready(page)
}

const face = (page: Page, name: string) => page.getByRole('tablist').first().getByRole('tab', { name, exact: true })

/** Every series chart on the glass, read off what is DRAWN: the line's points, the plot box, the x labels. */
async function drawnCharts(page: Page, scope: string) {
  return page.evaluate((sel) => {
    const out: { card: string; record: boolean; label: string; points: [number, number][]; plot: { x: number; w: number } | null; xLabels: string[] }[] = []
    for (const chart of document.querySelectorAll(`${sel} [data-testid="series-chart"]`)) {
      const svg = chart.querySelector('svg[role="img"]')
      if (!svg) continue
      const line = [...svg.querySelectorAll('path')].find((p) => p.getAttribute('fill') === 'none')
      const d = line?.getAttribute('d') ?? ''
      const nums = d.match(/-?\d+(\.\d+)?/g)?.map(Number) ?? []
      const points: [number, number][] = []
      for (let i = 0; i + 1 < nums.length; i += 2) points.push([nums[i], nums[i + 1]])
      const plot = svg.querySelector('[data-plot]')
      const card = chart.closest('[data-card], [data-testid]')
      out.push({
        card: card?.getAttribute('data-testid') ?? '?',
        record: chart.closest('[data-testid="history-line"]') !== null,
        label: svg.getAttribute('aria-label') ?? '',
        points,
        plot: plot ? { x: Number(plot.getAttribute('x')), w: Number(plot.getAttribute('width')) } : null,
        xLabels: [...svg.querySelectorAll('text')].map((t) => (t.textContent ?? '').trim()),
      })
    }
    return out
  }, scope)
}

// ── A COUNTED WORLD ──────────────────────────────────────────────────────────────────────────────
function countedWorld(): Promise<Buffer> {
  return patchedWorldImage('drive-counted', async (pg) => {
    const who = await pg.query<{ id: string }>(`select id from public.players where is_npc order by id limit 1`)
    if (who.rows.length !== 1) throw new Error('no merchant house to credit')
    const npc = who.rows[0].id
    // the current slot's start, the instant the last count stands at; the seven before it, one per quarter
    for (let k = COUNTS - 1; k >= 0; k--) {
      await pg.query(`select public.credit($1::uuid, 'DRIVE_AUDIT', 1000)`, [npc])
      const r = await pg.query<{ w: unknown }>(
        `select public.tick_stats(to_timestamp(floor(extract(epoch from now()) / 900) * 900) - ($1::int * interval '15 minutes')) as w`,
        [k],
      )
      if (r.rows.length !== 1) throw new Error(`count ${k} wrote nothing`)
    }
  })
}

test('Stats: a counted world — every drawn series ends at its right edge on a whole period, with no falling last point (rows 289, 294, 295)', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  // THE SLOT MUST HOLD STILL: the counts stand at this slot's start; if the quarter turned before the page read them,
  // the tab's own count would add a partial row that no production count ever writes (the cron counts at the edges).
  const left = SLOT_MS - (Date.now() % SLOT_MS)
  if (left < 240_000) await new Promise((r) => setTimeout(r, left + 1500))
  await serveWorldImage(page, await countedWorld())
  await open(page, request, baseURL, 'stats')
  await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
  await page.waitForTimeout(1500)

  const findings: string[] = []
  for (const [name, root, cards] of [
    ['Overview', '[data-testid="stats-overview"]', []],
    ['Cities', '[data-testid="stats-cities"]', ['stats-chart-city-purses', 'stats-chart-city-trade']],
    ['Markets', '[data-testid="stats-markets"]', ['stats-chart-market-sold', 'stats-chart-market-bought']],
  ] as const) {
    if (name !== 'Overview') {
      await face(page, name).click()
      await expect(page.locator(root)).toBeVisible({ timeout: 60_000 })
      await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
      await page.waitForTimeout(1500)
    }
    await shot(page, `stats-${name.toLowerCase()}-counted-1280@2x`)
    const charts = await drawnCharts(page, root)
    console.log(`${name}: ${charts.length} series charts drawn`)
    for (const c of charts) {
      const n = c.points.length
      const last = c.points[n - 1]
      const prev = c.points[n - 2]
      const prev2 = c.points[n - 3]
      console.log(`  ${c.card} "${c.label}": ${n} points, x labels [${c.xLabels.join(' | ')}], last ${last?.join(',')}, prev ${prev?.join(',')}`)
      if (n < 2 || !c.plot) continue
      // (1) THE LAST POINT STANDS ON THE PLOT'S RIGHT EDGE
      if (Math.abs(last[0] - (c.plot.x + c.plot.w)) > 1) findings.push(`${name} ${c.card}: the last point is ${(c.plot.x + c.plot.w - last[0]).toFixed(1)} px short of the right edge`)
      // (2) NO FALLING LAST POINT: in this world every quarter carries the same credit, so a sum series is flat and a
      //     level series climbs by the same step; a last point LOWER than the trend is the partial period the owner saw.
      if (prev2) {
        const stepBefore = prev[1] - prev2[1]
        const stepLast = last[1] - prev[1]
        // y grows downward: a fall is stepLast > 0 beyond what the trend before it did (+1 px of rounding)
        if (stepLast > Math.max(stepBefore, 0) + 1) findings.push(`${name} ${c.card} "${c.label}": the last point falls ${stepLast.toFixed(1)} px below the trend (prev step ${stepBefore.toFixed(1)})`)
      }
      // (3) THE X LABELS SAY DIFFERENT THINGS: an axis that reads "now now now" tells the time nowhere
      const labels = c.xLabels.filter((l) => l !== '')
      if (labels.length >= 2 && new Set(labels).size === 1) findings.push(`${name} ${c.card}: every x label reads "${labels[0]}"`)
      // (4) THE WHOLE SERIES IS THERE: the eight counts, each a whole quarter. A history RECORD (Money record, Market record...) is not
      //     drawn per count: it has one point per calendar day/week/month the world has lived, so its point count is the UTC days
      //     the eight counts touch (one when they sit in one day, two when the run crosses midnight) — never eight. It was held to
      //     eight here and failed exactly when CI ran across 00:00 UTC (run 42427011790, 00:05 UTC), and passed the rest of the day
      //     because a one-point line is skipped above. Rules (1) to (3) still hold for it.
      if (!c.record && n < COUNTS - 1) findings.push(`${name} ${c.card}: only ${n} points for ${COUNTS} counts`)
    }
    for (const id of cards) {
      const card = page.getByTestId(id)
      await expect(card, `${name} lacks its ${id} card`).toBeAttached()
      const text = (await card.innerText()).replace(/\s+/g, ' ')
      const drawn = (await card.locator('svg[role="img"]').count()) > 0
      console.log(`  card ${id}: drawn=${drawn} "${[...text].slice(0, 80).join('')}"`)
    }
  }
  console.log(`chart findings: ${JSON.stringify(findings, null, 1)}`)
  expect(findings, 'the drawn charts break the owner\'s rule').toEqual([])
})

// ── ROW 256: THE SECONDLY DATA RENEWAL ───────────────────────────────────────────────────────────
test('Stats: the live band asks once a second and its Updated stamp moves every second (row 256)', async ({ page, request, baseURL }) => {
  await page.addInitScript(() => {
    const w = window as unknown as { __rpcLog: { at: number; label: string }[] }
    w.__rpcLog = []
    const orig = console.debug
    console.debug = (...args: unknown[]) => {
      if (args[0] === '[rpc]' && typeof args[1] === 'string') w.__rpcLog.push({ at: performance.now(), label: args[1].replace(/\(.*$/, '') })
      orig.apply(console, args)
    }
  })
  await open(page, request, baseURL, 'stats')
  await expect(page.getByTestId('stats-updated')).toContainText(/\d\d:\d\d:\d\d/, { timeout: 120_000 })
  const stamps = new Set<string>()
  const t0 = await page.evaluate(() => performance.now())
  for (let i = 0; i < 12; i++) {
    stamps.add((await page.getByTestId('stats-updated').innerText()).trim())
    await page.waitForTimeout(500)
  }
  const asks = await page.evaluate((since) => (window as unknown as { __rpcLog: { at: number; label: string }[] }).__rpcLog.filter((l) => l.at >= since && /stats_now/.test(l.label)).length, t0)
  console.log(`stats_now asks in 6 s: ${asks}; distinct Updated stamps: ${[...stamps].join(', ')}`)
  expect(stamps.size, 'the Updated stamp did not move every second').toBeGreaterThanOrEqual(4)
  expect(asks, 'the live read is not asked about once a second').toBeGreaterThanOrEqual(4)
  await expect(page.getByTestId('stats-live-world')).toContainText(/\d/)

  // the young world's Cities chart, for the record: what its x axis says before any count
  await face(page, 'Cities').click()
  await expect(page.getByTestId('stats-cities')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
  await page.waitForTimeout(1500)
  for (const c of await drawnCharts(page, '[data-testid="stats-cities"]')) console.log(`young world, ${c.card}: ${c.points.length} points, x labels [${c.xLabels.join(' | ')}]`)
  await shot(page, 'stats-cities-young-1280@2x')
})

// ── D5 OF THE DRIVE AUDIT: A YOUNG WORLD'S CHART TELLS THE TIME AND INVENTS NO RANGE ─────────────
// WHAT THE WALK SAW ON A YOUNG WORLD (2026-11-08, twice): the City purses chart — the boot's own count and the live point, seconds
// to a minute apart, both 0 — labelled all three x ticks "now" and drew its flat 0 line between the y figures "1 🪙" and "−1 🪙".
// The axis tells the time at any span (seconds under a minute, one rule: tests/seriesChart.spec.ts), and a flat line has ONE y
// figure, its own value. The counted test above holds the same axis law on a counted series.
const FIX = 'docs/dev-log/2026-11-08-axis-map-load-words'
test('Stats: a young world\'s City purses chart labels its x ticks with different stretches of time, and a flat line gets one y figure, its own value (D5)', async ({ page, request, baseURL }) => {
  await open(page, request, baseURL, 'stats')
  await face(page, 'Cities').click()
  await expect(page.getByTestId('stats-cities')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
  const card = page.getByTestId('stats-chart-city-purses')
  await expect(card.locator('svg[role="img"]'), 'the young world drew no City purses line to judge').toHaveCount(1, { timeout: 60_000 })
  await page.waitForTimeout(500)
  await page.screenshot({ path: `${FIX}/stats-cities-young-1280@2x.png` })
  const [chart] = await drawnCharts(page, '[data-testid="stats-chart-city-purses"]')
  const xLabels = chart.xLabels.filter((l) => l !== '')
  // the y figures beside the plot: every visible figure of the chart but its reading line
  const yFigures = await card.locator('[data-testid="series-chart"] span.tabular-nums:not([data-testid="series-chart-reading"]):visible').allInnerTexts()
  const flat = chart.points.every((p) => Math.abs(p[1] - chart.points[0][1]) < 0.5)
  const reading = (await card.getByTestId('series-chart-reading').innerText()).split('·')[0]
  console.log(`young world City purses: ${chart.points.length} points${flat ? ', flat' : ''}; x labels [${xLabels.join(' | ')}]; y figures [${yFigures.join(' | ')}]; reading ${reading.trim()}`)
  // (1) THE X LABELS TELL THE TIME: each a different word, the last "now", the others a stretch of time ("40s", "3m", "2h") — a
  //     series younger than a second (the boot's count and its live point can be) is "now" alone, never "now" three times
  expect(xLabels.length).toBeGreaterThanOrEqual(1)
  expect(new Set(xLabels).size, `the x labels repeat themselves: ${xLabels.join(' | ')}`).toBe(xLabels.length)
  expect(xLabels[xLabels.length - 1]).toMatch(/^(now|지금)$/)
  for (const l of xLabels.slice(0, -1)) expect(l, `"${l}" is not a stretch of time`).toMatch(/^\d+(\.\d+)?([smhdy]|초|분|시간|일|년)$/)
  // (2) THE Y FIGURES ARE THE DATA'S OWN: a flat line has exactly one, its value — never a band invented around it
  const value = (s: string) => Number(s.replace(/−/g, '-').replace(/[^\d.-]/g, ''))
  if (flat) {
    expect(yFigures, `a flat line drawn between ${yFigures.join(' and ')}`).toHaveLength(1)
    expect(value(yFigures[0])).toBe(value(reading))
  } else {
    expect(yFigures).toHaveLength(2)
  }
})

// ── ROWS 273, 298, 247: A CITY'S PAGE, ITS KIND, THE MONEY LOG'S CONTROLS ────────────────────────
test('Stats: a city row opens its page with its kind in the title and the People block, Back returns; the Money log\'s filters (rows 273, 298, 247)', async ({ page, request, baseURL }) => {
  await open(page, request, baseURL, 'stats')
  await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
  // (247) the Money log's tappable things: what kind of control they are now
  const controls = await page.evaluate(() => {
    const log = document.querySelector('[data-testid="stats-overview"]')
    const grids = [...(log?.querySelectorAll('[data-choice-grid]') ?? [])].map((g) => ({
      label: g.getAttribute('aria-label'),
      cells: [...g.children].map((c) => {
        const r = c.getBoundingClientRect()
        return `${(c.textContent ?? '').trim().slice(0, 12)} ${Math.round(r.width)}×${Math.round(r.height)}`
      }),
    }))
    const selects = [...(log?.querySelectorAll('select') ?? [])].map((s) => `${s.getAttribute('data-testid') ?? s.name}: ${s.options.length} options`)
    return { grids, selects }
  })
  console.log(`Money log controls: ${JSON.stringify(controls)}`)
  for (const g of controls.grids) {
    const sizes = g.cells.map((c) => c.split(' ').pop())
    expect(new Set(sizes).size, `grid "${g.label}" has unequal cells: ${g.cells.join(', ')}`).toBe(1)
  }

  await face(page, 'Cities').click()
  await expect(page.getByTestId('stats-cities')).toBeVisible({ timeout: 60_000 })
  const rows = page.getByTestId('stats-city-open')
  await expect(rows.first()).toBeVisible({ timeout: 60_000 })
  // every row says its kind, in the six words the owner was given
  const kinds = await page.getByTestId('stats-city-kind').allInnerTexts()
  const allowed = new Set(['Capital', 'Island capital', 'City', 'Island city', 'Town', 'Island town', '수도', '섬 수도', '도시', '섬 도시', '마을', '섬 마을'])
  console.log(`city kinds on the list: ${JSON.stringify([...new Set(kinds.map((k) => k.trim()))])}`)
  for (const k of kinds) expect(allowed.has(k.trim()), `an unknown kind word: "${k}"`).toBe(true)

  const name = (await rows.first().getByTestId('stats-city-name').innerText()).trim()
  await rows.first().click()
  const cityPage = page.getByTestId('stats-city-page')
  await expect(cityPage).toBeVisible({ timeout: 60_000 })
  await expect(cityPage.locator('h1')).toContainText(name)
  const kindWord = (await page.getByTestId('stats-city-page-kind').innerText()).trim()
  expect(allowed.has(kindWord), `the page's kind word "${kindWord}"`).toBe(true)
  await expect(page.getByTestId('stats-city-people')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
  const people = await page.evaluate(() => {
    const t = (id: string) => (document.querySelector(`[data-testid="${id}"]`)?.textContent ?? '').replace(/\s+/g, ' ').trim()
    return { population: t('stats-city-population'), base: t('stats-city-people-base'), tax: t('stats-city-people-tax'), rank: t('stats-city-people-rank') }
  })
  console.log(`${name} (${kindWord}) people: ${JSON.stringify(people)}`)
  expect(people.population).toMatch(/\d/)
  expect(people.rank).toMatch(/\d/)
  await shot(page, 'stats-city-page-1280@2x')
  await page.locator('[data-detail-back]').last().click()
  await expect(page.locator('[data-detail-page]')).toHaveCount(0)
  await expect(rows.first()).toBeVisible()
})

// ── ROW 296: THE REPORT'S DAY AND WEEK ───────────────────────────────────────────────────────────
test('Report: its spans and its bars are real days (row 296)', async ({ page, request, baseURL }) => {
  await open(page, request, baseURL, 'command')
  await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: /^(Report|보고)$/ }).click()
  await expect(page.getByTestId('report-spans')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
  const spans = (await page.getByTestId('report-spans').getByRole('tab').allInnerTexts()).map((s) => s.trim())
  const bars = page.getByTestId('report-bars')
  const barWords = (await bars.count()) ? (await bars.first().innerText()).replace(/\s+/g, ' ') : '(no bars)'
  console.log(`report spans: ${JSON.stringify(spans)}; bars: ${[...barWords].slice(0, 200).join('')}`)
  expect(spans.length).toBe(3)
  for (const s of spans) expect(s.length, `a span word is not short: "${s}"`).toBeLessThanOrEqual(8)
  await shot(page, 'report-1280@2x')
  for (const s of spans) {
    await page.getByTestId('report-spans').getByRole('tab', { name: s, exact: true }).click()
    await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
    const labels = (await bars.count()) ? (await bars.first().locator('text, [data-bar-label], span').allInnerTexts()).filter((t) => /\d{2}-\d{2}/.test(t)) : []
    console.log(`  ${s}: ${labels.length} dated bars ${labels.slice(0, 8).join(' ')}`)
  }
})
