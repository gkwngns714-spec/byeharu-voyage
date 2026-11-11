import { test, expect, type Page } from '@playwright/test'
import { arrivedAtEdge, ready, reachable } from './appReady.fixture'
import { sampleWalkers, walkVerdict } from './cityWalk.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DRIVE AUDIT, 2026-11-08 — THE HQ (CITY PAGE), DRIVEN AS THE OWNER WOULD
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/OWNER_REQUESTS.md rows 241-245 (the city picture: organic, closed, sea on the west, citizens
// scaled to the houses, more people), 248 (alleys to the buildings, walkers three times slower),
// 247/251/255 (the hall in place: Influence folds, Investors slides in from the right and closes,
// a tile press moves nothing in the frame), 262 (figures hug their words) and 277 (the hall's
// Population and Gold are LIVE like Stats). Each of those rows is merged but "not driven" in the
// ledger; this file drives them in the local PGlite world (no .env.local: never production) and
// takes DPR-2 pictures under docs/dev-log/2026-11-08-drive-audit/ for the reader to judge against
// the owner's words. What a spec cannot judge (does it LOOK like a city) the picture carries.
//
// Nothing here fixes product code: a red is a finding (docs/dev-log/2026-11-08-drive-audit.md).

const OUT = 'docs/dev-log/2026-11-08-drive-audit'
/** The pictures of the audit's D2 / D3 fix (the drawer's slide and edge), kept apart from the audit's own evidence. */
const FIX_OUT = 'docs/dev-log/2026-11-08-hq-drawer-production'
const WIDE = { width: 1280, height: 800 }
const OWNER = { width: 1440, height: 900 }
const PHONE = { width: 390, height: 844 }

test.use({ deviceScaleFactor: 2 })

async function shot(page: Page, name: string, dir = OUT) {
  await page.waitForTimeout(300)
  await page.screenshot({ path: `${dir}/${name}.png` })
}

async function openHq(page: Page, request: Parameters<typeof reachable>[0], baseURL: string | undefined, size: { width: number; height: number }) {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(size)
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('city-hall-figures')).toBeVisible({ timeout: 120_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
  await page.waitForTimeout(500)
}

/** Every region of the frame that a tile press may not move (rows 251/255), in rounded boxes. */
async function frame(page: Page) {
  return page.evaluate(() => {
    const pick = (id: string) => {
      const el = document.querySelector(`[data-testid="${id}"]`)
      if (!el) return null
      const r = el.getBoundingClientRect()
      return [Math.round(r.top), Math.round(r.left), Math.round(r.width), Math.round(r.height)]
    }
    return { header: pick('city-header'), grid: pick('city-building-grid'), rail: pick('city-rail') }
  })
}

// ── ROWS 241-245, 248: THE PICTURE ───────────────────────────────────────────────────────────────
test('HQ: the plan is one closed walled city with the sea west, citizens scaled to the houses, alleys, and slow walkers', async ({ page, request, baseURL }) => {
  await openHq(page, request, baseURL, WIDE)
  await shot(page, 'hq-hall-1280@2x')

  const scene = await page.evaluate(() => {
    const svg = document.querySelector('[data-testid="city-scene"]') as SVGSVGElement
    const vb = svg.viewBox.baseVal
    const box = (sel: string) => {
      const g = svg.querySelector(sel) as SVGGraphicsElement | null
      if (!g) return null
      const b = g.getBBox()
      return { x: +b.x.toFixed(1), y: +b.y.toFixed(1), w: +b.width.toFixed(1), h: +b.height.toFixed(1) }
    }
    // THE LAND: the largest filled path of the scene that is not the whole plate — the walled town's ground.
    let land: { x: number; y: number; w: number; h: number } | null = null
    for (const p of svg.querySelectorAll('path')) {
      const b = (p as SVGGraphicsElement).getBBox()
      const area = b.width * b.height
      if (area >= vb.width * vb.height * 0.98) continue
      if (!land || area > land.w * land.h) land = { x: +b.x.toFixed(1), y: +b.y.toFixed(1), w: +b.width.toFixed(1), h: +b.height.toFixed(1) }
    }
    // THE CITIZENS: the crowd is drawn as zero-length round-capped strokes (one path per radius bucket), so a
    // citizen's diameter is the path's stroke width; the walkers are circles moved by cityWalk.ts, each naming its
    // lap (one traverse, seconds) and its own start (`data-lap`, `data-begin`). A missing attribute reads 0, so the
    // ×3 law below fails loudly rather than vacuously.
    const crowdPaths = [...svg.querySelectorAll('[data-testid="city-crowd"] path')]
    const crowdDiameters = crowdPaths.map((p) => parseFloat(getComputedStyle(p).strokeWidth)).filter((n) => Number.isFinite(n))
    const crowdCount = crowdPaths.reduce((n, p) => n + ((p.getAttribute('d') ?? '').match(/M/g)?.length ?? 0), 0)
    const walkers = [...svg.querySelectorAll('[data-testid="city-dots"] circle')]
    const walkerR = walkers.map((c) => parseFloat(c.getAttribute('r') ?? '0'))
    const durs = walkers.map((c) => parseFloat(c.getAttribute('data-lap') ?? '0'))
    const begins = walkers.map((c) => parseFloat(c.getAttribute('data-begin') ?? '0'))
    // THE HOUSES: the smallest named-place mark against the ordinary houses — every rect in the scene that is not a
    // named place is a house, a hall or a storehouse.
    const rects = [...svg.querySelectorAll('rect')].map((r) => Math.min(parseFloat(r.getAttribute('width') ?? '0'), parseFloat(r.getAttribute('height') ?? '0'))).filter((n) => n > 0)
    rects.sort((a, b) => a - b)
    const teeming = svg.querySelectorAll('[data-testid="city-teeming"] path').length
    const lights = svg.querySelectorAll('[data-testid="city-lights"] path').length
    const firstWalker = (svg.querySelector('[data-testid="city-dots"] circle')?.outerHTML ?? '').slice(0, 320)
    return {
      firstWalker,
      viewBox: [vb.x, vb.y, vb.width, vb.height],
      nodes: svg.querySelectorAll('*').length,
      land,
      port: box('[data-testid="city-scene-port"]'),
      hall: box('[data-testid="city-scene-hall"]'),
      market: box('[data-testid="city-scene-market"]'),
      crowdCount,
      crowdDiameters: [...new Set(crowdDiameters.map((d) => +d.toFixed(2)))].sort((a, b) => a - b),
      walkers: walkers.length,
      walkerR: [Math.min(...walkerR), Math.max(...walkerR)],
      durs: [Math.min(...durs), Math.max(...durs)],
      begins: [Math.min(...begins), Math.max(...begins)],
      houseMin: rects[0] ?? null,
      houseMedian: rects[Math.floor(rects.length / 2)] ?? null,
      rects: rects.length,
      teeming,
      lights,
      phase: document.querySelector('[data-testid="city-phase"]')?.getAttribute('data-phase'),
    }
  })
  console.log(`HQ scene @1280: ${JSON.stringify(scene)}`)

  // (241/243/244) A CLOSED CITY, WHOLE IN ITS FRAME: the town's ground ends inside the plate on the north, east and south
  // (a margin, never a cut block) and reaches the plate's west half, where the sea and the port are.
  expect(scene.land, 'no land path in the scene').not.toBeNull()
  const land = scene.land!
  expect(land.y, 'the town touches the plate top: it is a section, not a closed city').toBeGreaterThan(0)
  expect(land.x + land.w, 'the town touches the plate right edge').toBeLessThan(scene.viewBox[2])
  expect(land.y + land.h, 'the town touches the plate bottom').toBeLessThan(scene.viewBox[3])
  // (241/245) THE SEA AND THE PORT ARE ON THE WEST: the port's mark lies left of the town hall and the market.
  expect(scene.port, 'no port in the scene').not.toBeNull()
  expect(scene.hall, 'no hall in the scene').not.toBeNull()
  expect(scene.port!.x + scene.port!.w, 'the port is not west of the hall').toBeLessThanOrEqual(scene.hall!.x + 1)
  expect(scene.port!.x + scene.port!.w, 'the port is not west of the market').toBeLessThanOrEqual(scene.market!.x + 1)
  // (242/243/245) CITIZENS: many, and scaled to the houses — a citizen's diameter is under the smallest house's side.
  expect(scene.crowdCount, 'too few citizens for a city').toBeGreaterThanOrEqual(200)
  expect(scene.walkers, 'no walkers').toBeGreaterThanOrEqual(30)
  // (the smallest rect is a crate on the quay, 1.5 units; a HOUSE is the median rect, ~3.5 units — a citizen is about half of it)
  if (scene.houseMedian !== null) {
    for (const d of scene.crowdDiameters) expect(d, `a citizen (${d}) is as big as a house (${scene.houseMedian})`).toBeLessThan(scene.houseMedian)
    expect(scene.walkerR[1] * 2, 'a walker is as big as a house').toBeLessThan(scene.houseMedian)
  }
  expect(scene.teeming, 'no teeming stipple').toBeGreaterThan(0)
  // (246) the perf budget the merged slice set
  expect(scene.nodes, 'the scene grew past its 400-node budget').toBeLessThan(400)
  // (248) THE WALKERS ARE SLOW: every walker's lap (one traverse) lasts at least 18 s (strollers 18-42 s, walkers 42-78 s after the ×3).
  expect(scene.walkers, 'no walkers to read a lap from').toBeGreaterThan(0)
  expect(scene.durs[0], 'a walker is faster than the ×3 slowdown allows').toBeGreaterThanOrEqual(18)
  expect(scene.begins[0], 'the walkers share one start: no phase spread').toBeLessThan(scene.begins[1])

  // The same picture on a phone, for the reader. (Whether the people WALK is the law below, read on its own fresh loads.)
  await page.setViewportSize(PHONE)
  await page.reload()
  await ready(page)
  await expect(page.getByTestId('city-hall-figures')).toBeVisible({ timeout: 120_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
  await page.waitForTimeout(600)
  await shot(page, 'hq-hall-390@2x')
  const noScroll = await page.evaluate(() => ({ docH: document.documentElement.scrollHeight, clientH: document.documentElement.clientHeight, docW: document.documentElement.scrollWidth, clientW: document.documentElement.clientWidth }))
  console.log(`HQ @390 document: ${JSON.stringify(noScroll)}`)
  expect(noScroll.docW, 'the HQ scrolls sideways on a phone').toBeLessThanOrEqual(noScroll.clientW)
})

// WHAT THE DRIVE FOUND (2026-11-08, eight runs, 1280 and 390, fresh loads): THE PEOPLE DID NOT WALK. 0 of 36 walkers moved
// over 4 s (every dot's rect sampled in the page; the first dot's x read every 100 ms held one value), the plan's two clips
// 3 s apart were byte-identical, the svg's SMIL clock ran, nothing was paused, the DOM nodes were the same. The same walker
// markup alone on a blank page MOVED, and in the app `svg.setCurrentTime(svg.getCurrentTime())` woke them — a SMIL timeline
// that was never serviced until seeked. tests/city.page.spec.ts's "the people walk" passed because it read the dot right
// after a viewport change (the plate re-scaled under the dot). Rows 241 / 242 / 248: *"these dots are population, it can
// stop it can go back and forth"*. FIXED the same day (docs/dev-log/2026-11-08-city-walkers.md): the people are moved on the
// page's own animation frame (src/features/city/cityWalk.ts), and this is the law that was the fixme — read through the one
// sampler (tests/cityWalk.fixture.ts) on a fresh load at each glass, nothing touched for the three seconds it watches.
for (const size of [WIDE, PHONE]) {
  test(`HQ @${size.width}: the people walk — on a fresh load, sampled over 3 s, most walkers move, none jumps a street, the picture changes (rows 241/242/248)`, async ({ page, request, baseURL }) => {
    await openHq(page, request, baseURL, size)
    await page.bringToFront()
    const r = await sampleWalkers(page)
    console.log(`the people walk @${size.width}: ${JSON.stringify(r)}`)
    expect(walkVerdict(r, `@${size.width}`)).toEqual([])
  })
}

// ── ROWS 247, 251, 255, 262: THE HALL IN PLACE ───────────────────────────────────────────────────
for (const size of [WIDE, PHONE]) {
  test(`HQ @${size.width}: Investors slides in from the right edge and closes, Influence folds and unfolds, a tile press moves no frame, figures hug their words`, async ({ page, request, baseURL }) => {
    await openHq(page, request, baseURL, size)
    const before = await frame(page)

    // (247) THE INVESTORS DRAWER: sampled frame by frame from BEFORE the press, it says what it is, and its own close takes
    // it away — the frame behind it untouched. Where it LANDS and how it ENTERS are printed here and HELD by the two laws
    // after this test (the slide, the window's edge).
    const sampler = page.evaluate(
      () =>
        new Promise<{ lefts: number[]; right: number; width: number; top: number }>((resolve) => {
          const lefts: number[] = []
          const t0 = performance.now()
          const tick = () => {
            const d = document.querySelector('[data-testid="city-investors-drawer"]')
            if (d) lefts.push(Math.round(d.getBoundingClientRect().left))
            if (performance.now() - t0 < 1500) requestAnimationFrame(tick)
            else {
              const r = d?.getBoundingClientRect()
              resolve({ lefts, right: r ? Math.round(r.right) : -1, width: r ? Math.round(r.width) : -1, top: r ? Math.round(r.top) : -1 })
            }
          }
          requestAnimationFrame(tick)
        }),
    )
    await page.waitForTimeout(50)
    await page.getByTestId('city-hall-investors').click()
    const slide = await sampler
    const drawer = page.getByTestId('city-investors-drawer')
    await expect(drawer).toBeVisible()
    await expect(drawer).toContainText(/Investors|투자자/)
    const how = await drawer.evaluate((e) => ({ mode: e.getAttribute('data-tray-mode'), animation: getComputedStyle(e).animationName }))
    console.log(
      `investors drawer @${size.width}: lefts ${slide.lefts.slice(0, 8).join(',')}…${slide.lefts.slice(-2).join(',')} right ${slide.right} (window ${size.width}) width ${slide.width} top ${slide.top}; mode ${how.mode}, animation ${how.animation}`,
    )
    expect(slide.lefts.length, 'the drawer never painted').toBeGreaterThan(0)
    if (size.width < 640) expect(slide.width, 'on a phone the drawer is not the full glass').toBe(size.width)
    await shot(page, `hq-investors-${size.width}@2x`)
    expect(await frame(page), 'opening the drawer moved the frame').toEqual(before)
    await page.getByTestId('tray-close').first().click()
    await expect(drawer).toHaveCount(0, { timeout: 5000 })
    expect(await frame(page), 'closing the drawer moved the frame').toEqual(before)

    // (255) THE INFLUENCE FOLD: one press opens the book, a second folds it; no tax rows inside.
    const fold = page.getByTestId('city-hall-influence')
    await expect(fold).toHaveAttribute('aria-expanded', 'false')
    await fold.click()
    await expect(fold).toHaveAttribute('aria-expanded', 'true')
    await expect(page.getByTestId('city-hall-book')).toBeVisible()
    await expect(page.locator('[data-testid="townhall-day"], [data-testid="townhall-your-tax"], [data-testid="townhall-mayor-tax"]')).toHaveCount(0)
    await shot(page, `hq-influence-open-${size.width}@2x`)
    await fold.click()
    await expect(fold).toHaveAttribute('aria-expanded', 'false')
    await expect(page.getByTestId('city-hall-book')).toHaveCount(0)
    expect(await frame(page), 'the fold moved the frame').toEqual(before)

    // (262) THE FIGURES HUG THEIR WORDS: the gap from a word's end to its figure's start, each hall cell. Measured and
    // printed; the law for this (8 px) was reversed by row 267's page pattern, so the figure is reported, not held.
    const gaps = await page.evaluate(() => {
      const out: Record<string, number | null> = {}
      for (const id of ['city-population', 'city-gold', 'city-status', 'city-employees', 'city-relationship']) {
        const cell = document.querySelector(`[data-testid="${id}"]`)
        if (!cell) {
          out[id] = null
          continue
        }
        const fig = cell.querySelector('.tabular-nums') ?? cell.lastElementChild
        const walker = document.createTreeWalker(cell, NodeFilter.SHOW_TEXT)
        let label: Range | null = null
        for (let n = walker.nextNode(); n; n = walker.nextNode()) {
          if (fig && (fig === n.parentElement || fig.contains(n))) continue
          if (!(n.textContent ?? '').trim()) continue
          label = document.createRange()
          label.selectNodeContents(n)
          break
        }
        if (!label || !fig) {
          out[id] = null
          continue
        }
        const l = label.getBoundingClientRect()
        const f = fig.getBoundingClientRect()
        // a figure under its word: the vertical gap; beside it: the horizontal gap
        out[id] = f.top >= l.bottom - 1 ? Math.round(f.top - l.bottom) : Math.round(f.left - l.right)
      }
      return out
    })
    console.log(`hall word→figure gaps @${size.width}: ${JSON.stringify(gaps)}`)
    for (const id of ['city-population', 'city-gold', 'city-status', 'city-relationship', 'city-employees']) {
      await expect(page.getByTestId(id), `${id} is missing from the hall`).toBeVisible()
      await expect(page.getByTestId(id)).not.toContainText('—')
    }

    // (251) EVERY TILE PRESS LEAVES THE FRAME WHERE IT WAS, and the page never scrolls. Production takes the whole page by
    // the owner's 2026-11-06 order (storage · cargo · recipes across it);
    // the header, the tiles and the rail still may not move.
    for (const tile of ['market', 'port', 'inn', 'production', 'hall']) {
      await page.getByTestId(`city-building-${tile}`).click()
      await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
      await page.waitForTimeout(400)
      const after = await frame(page)
      expect(after, `pressing ${tile} moved the frame`).toEqual(before)
      const scrolled = await page.evaluate(() => window.scrollY)
      expect(scrolled, `pressing ${tile} scrolled the page`).toBe(0)
    }
  })
}

// ── ROWS 247 / 278: THE DRAWER SLIDES IN FROM THE WINDOW'S EDGE AND LANDS ON IT ─────────────────
// WHAT THE DRIVE FOUND (2026-11-08, twice at 1280 and at 390; the audit's D2 and D3): the drawer APPEARED in place — sampled frame
// by frame from before the press, its first painted frame was already where it lands (left 856 at 1280, 0 at 390), its
// `data-tray-mode` "docked", its computed animation none — and at 1280 it landed at x 856-1240, 40 px short of the window's
// right edge. The docked tray's page dock (`trayDockPageClass`, the side column's own x and width) carries no entering slide, and
// its right edge is the page's MARGIN: the look the owner refused for the map's pop-up a day later (row 278: *"not totally fully on
// the right. i want it to slide from the right slide from the edge of the page"*), which #491/#493 fixed for the map alone
// (`traySideEdgeClass`, `right-0`, `bv-slide-in-right`). The owner's words for this drawer (row 247): *"investors - tappable where
// when tapped, a list slides to the right where you can close"*.
// FIXED after #560: the drawer IS the map's slide-in panel, `Tray mode="side"` (CityHallPanel.tsx), so `traySideEdgeClass` is the
// one authority for both the slide and the edge. The two laws below hold it the way tests/map.tray.edge.spec.ts holds the map's:
// the left edge recorded on every painted frame from before the press, the landing read off the running app.

type Probe = { __lefts: number[] }

/** Record the drawer's left edge on every painted frame, from BEFORE the press (the map.tray.edge method). */
async function watchDrawer(page: Page) {
  await page.evaluate(() => {
    const w = window as unknown as Probe
    w.__lefts = []
    const tick = () => {
      const el = document.querySelector('[data-testid="city-investors-drawer"]')
      if (el) w.__lefts.push(el.getBoundingClientRect().left)
      requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  })
}

for (const size of [WIDE, PHONE]) {
  test(`HQ @${size.width}: the Investors list SLIDES in when tapped — its first painted frame is off the window's right edge, then it travels in (row 247)`, async ({ page, request, baseURL }) => {
    await openHq(page, request, baseURL, size)
    await watchDrawer(page)
    await page.getByTestId('city-hall-investors').click()
    const drawer = page.getByTestId('city-investors-drawer')
    await expect(drawer).toBeVisible()
    // not a sleep (arrivedAtEdge): the slide's start follows the runner's speed; the frames below stay the verdict
    await arrivedAtEdge(drawer, size.width)
    const lefts = await page.evaluate(() => (window as unknown as Probe).__lefts)
    const how = await drawer.evaluate((e) => ({ mode: e.getAttribute('data-tray-mode'), animation: getComputedStyle(e).animationName }))
    console.log(
      `investors slide @${size.width}: ${lefts.length} frames, lefts ${lefts.slice(0, 6).map(Math.round).join(',')}…${lefts.slice(-2).map(Math.round).join(',')} (window ${size.width}); mode ${how.mode}, animation ${how.animation}`,
    )
    expect(lefts.length, 'the drawer painted fewer than three frames').toBeGreaterThan(2)
    expect(lefts[0], 'the first painted frame is not off the window: the drawer appeared in place instead of sliding').toBeGreaterThanOrEqual(size.width - 1)
    expect(lefts[lefts.length - 1], 'the drawer never travelled in').toBeLessThan(size.width - 100)
    await page.getByTestId('tray-close').first().click()
    await expect(drawer).toHaveCount(0, { timeout: 5000 })
  })
}

for (const size of [WIDE, OWNER, PHONE]) {
  test(`HQ @${size.width}: the Investors drawer lands on the window's own right edge, the side column's width (rows 247 / 278)`, async ({ page, request, baseURL }) => {
    await openHq(page, request, baseURL, size)
    const before = await frame(page)
    await page.getByTestId('city-hall-investors').click()
    const drawer = page.getByTestId('city-investors-drawer')
    await expect(drawer).toBeVisible()
    await arrivedAtEdge(drawer, size.width)
    const box = (await drawer.boundingBox())!
    const read = await page.evaluate(() => ({
      side: document.querySelector('[data-page-side]')?.getBoundingClientRect().width ?? null,
      flow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    }))
    const inset = Math.round(size.width - box.x - box.width)
    console.log(`investors drawer @${size.width}: x ${Math.round(box.x)}–${Math.round(box.x + box.width)} (window ${size.width}, inset ${inset}), width ${Math.round(box.width)}, side column ${read.side}`)
    await shot(page, `hq-investors-${size.width}@2x`, FIX_OUT)
    expect(Math.abs(size.width - box.x - box.width), `the drawer's right edge stands ${inset} px inside the window's`).toBeLessThanOrEqual(1)
    if (size.width >= 1024) {
      expect(read.side, 'the page has no side column to take the width of').not.toBeNull()
      expect(Math.abs(box.width - read.side!), `the drawer is ${Math.round(box.width)} px wide and the side column ${Math.round(read.side!)}`).toBeLessThanOrEqual(2)
    } else {
      expect(Math.round(box.width), 'on a phone the drawer is the glass').toBe(size.width)
    }
    expect(read.flow, 'the page gained a sideways scroll').toBeLessThanOrEqual(0)
    expect(await frame(page), 'opening the drawer moved the frame').toEqual(before)
    await page.getByTestId('tray-close').first().click()
    await expect(drawer).toHaveCount(0, { timeout: 5000 })
    expect(await frame(page), 'closing the drawer moved the frame').toEqual(before)
  })
}

// ── ROW 277 (AND THE PURSES OF 280/290): THE HALL IS LIVE ────────────────────────────────────────
// A world whose city purses are LIT (the shipped image keeps them dark): one purchase at the Market must
// show on the hall's Gold within a few seconds, with no reload — "can it be live like stats?".
async function litWorld(): Promise<Buffer> {
  return patchedWorldImage('drive-lit-purses', async (pg) => {
    const above = await pg.query<{ v: unknown }>(`select value as v from public.world_config where key = 'npc_invest_above'`)
    await pg.exec(`update public.world_config set value = to_jsonb(0) where key = 'npc_invest_above'`)
    const sw = await pg.query<{ j: { enabled: boolean } }>(`select public.city_treasury_switch(true) as j`)
    if (!sw.rows[0].j.enabled) throw new Error(`the switch did not light the purses: ${JSON.stringify(sw.rows[0].j)}`)
    await pg.query(`update public.world_config set value = $1::jsonb where key = 'npc_invest_above'`, [JSON.stringify(above.rows[0].v)])
  })
}

test('HQ: with the purses lit, a purchase at the Market shows on the hall\'s Gold within seconds, with no reload (row 277)', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveWorldImage(page, await litWorld())
  await openHq(page, request, baseURL, WIDE)
  const gold = page.getByTestId('city-gold')
  const goldBefore = (await gold.innerText()).replace(/\s+/g, ' ')
  const purseBefore = (await page.getByTestId('purse').innerText()).replace(/\s+/g, ' ')
  console.log(`hall before: gold "${goldBefore}", your purse "${purseBefore}"`)

  // buy ONE unit of the first good on the Buy face, through the City page's own Market face
  await page.getByTestId('city-building-market').click()
  await expect(page.getByTestId('city-market-buy')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
  const row = page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]').first()
  const good = (await row.getByTestId('trade-good-name').innerText()).split('\n')[0].trim()
  await row.getByRole('button', { name: /^buy/i }).first().click()
  const tray = page.getByTestId('trade-tray')
  await expect(tray).toBeVisible({ timeout: 30_000 })
  const send = page.getByTestId('trade-tray-send')
  await expect(send).toBeEnabled({ timeout: 60_000 })
  const sendWords = await send.innerText()
  console.log(`buying: ${good} — ${sendWords.replace(/\s+/g, ' ')}`)
  await send.click()
  await expect(tray).toHaveCount(0, { timeout: 60_000 })

  // back to the hall: the city's Gold must have moved on its own
  await page.getByTestId('city-building-hall').click()
  await expect(page.getByTestId('city-hall-figures')).toBeVisible({ timeout: 60_000 })
  await expect
    .poll(async () => (await gold.innerText()).replace(/\s+/g, ' '), { timeout: 15_000, intervals: [500] })
    .not.toBe(goldBefore)
  const goldAfter = (await gold.innerText()).replace(/\s+/g, ' ')
  const purseAfter = (await page.getByTestId('purse').innerText()).replace(/\s+/g, ' ')
  console.log(`hall after: gold "${goldAfter}", your purse "${purseAfter}"`)
  expect(purseAfter, 'your purse did not fall after the purchase').not.toBe(purseBefore)
  await shot(page, 'hq-hall-live-gold-1280@2x')
})
