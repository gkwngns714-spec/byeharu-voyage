import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
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
const WIDE = { width: 1280, height: 800 }
const PHONE = { width: 390, height: 844 }

test.use({ deviceScaleFactor: 2 })

async function shot(page: Page, name: string) {
  await page.waitForTimeout(300)
  await page.screenshot({ path: `${OUT}/${name}.png` })
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
    return { header: pick('city-header'), grid: pick('city-building-grid'), rail: pick('city-rail'), earnings: pick('city-summary') }
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
    // citizen's diameter is the path's stroke width; the walkers are circles with animateMotion.
    const crowdPaths = [...svg.querySelectorAll('[data-testid="city-crowd"] path')]
    const crowdDiameters = crowdPaths.map((p) => parseFloat(getComputedStyle(p).strokeWidth)).filter((n) => Number.isFinite(n))
    const crowdCount = crowdPaths.reduce((n, p) => n + ((p.getAttribute('d') ?? '').match(/M/g)?.length ?? 0), 0)
    const walkers = [...svg.querySelectorAll('[data-testid="city-dots"] circle')]
    const walkerR = walkers.map((c) => parseFloat(c.getAttribute('r') ?? '0'))
    const motions = [...svg.querySelectorAll('[data-testid="city-dots"] animateMotion')]
    const durs = motions.map((a) => parseFloat((a.getAttribute('dur') ?? '0').replace('s', '')))
    const begins = motions.map((a) => parseFloat((a.getAttribute('begin') ?? '0').replace('s', '')))
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
  // (248) THE WALKERS ARE SLOW: every animateMotion lasts at least 18 s (strollers 18-42 s, walkers 42-78 s after the ×3).
  expect(scene.durs[0], 'a walker is faster than the ×3 slowdown allows').toBeGreaterThanOrEqual(18)
  // ... and they do walk: a dot moves within 6.4 s (polled, with the page in front — animateMotion freezes in a
  // backgrounded tab, which is how city.page.spec read "0.00 px" on a loaded shard once). Read at BOTH glasses, with the
  // SMIL clock beside it, so a still dot says whether the timeline runs at all.
  // EVERY moving dot is sampled IN the page (no driver round trips), 4 s apart, on a fresh load at each glass: a single
  // dot can be a stroller waiting at the end of its line, and a resize restarts the SMIL paths (a jump, not a walk).
  const walk = async (glass: string) => {
    await page.bringToFront()
    // every walker starts at its own `begin` phase: nobody moves before the earliest one, so the read waits for it
    await page.waitForFunction((t) => (document.querySelector('[data-testid="city-scene"]') as SVGSVGElement).getCurrentTime() >= t, scene.begins[0] + 1, { timeout: 180_000 })
    // the picture itself: two clips of the plan 3 s apart differ when anyone walks
    const box = (await page.getByTestId('city-info-image').boundingBox())!
    const f1 = await page.screenshot({ clip: box })
    await page.waitForTimeout(3000)
    const f2 = await page.screenshot({ clip: box })
    const frames = Buffer.compare(f1, f2) === 0 ? 'identical' : 'differ'
    const r = await page.evaluate(async () => {
      const svg = document.querySelector('[data-testid="city-scene"]') as SVGSVGElement
      const dots = [...svg.querySelectorAll('[data-testid="city-dots"] circle')]
      // the same DOM nodes four seconds later? (a React remount would restart every path at its phase)
      for (const d of dots) (d as unknown as { __drive: boolean }).__drive = true
      const at = () => dots.map((c) => c.getBoundingClientRect()).map((b) => [b.x, b.y] as [number, number])
      const a = at()
      const t0 = svg.getCurrentTime()
      // a fine read of the first dot every 100 ms: a sawtooth (moves, then jumps back) is a restart, a flat line is no motion
      const fine: number[] = []
      for (let i = 0; i < 40; i++) {
        await new Promise((res) => setTimeout(res, 100))
        const b = dots[0]?.getBoundingClientRect()
        fine.push(b ? +b.x.toFixed(1) : -1)
      }
      const b = at()
      const t1 = svg.getCurrentTime()
      let moved = 0
      let far = 0
      for (let i = 0; i < dots.length; i++) {
        const d = Math.abs(a[i][0] - b[i][0]) + Math.abs(a[i][1] - b[i][1])
        if (d > 0.5) moved++
        far = Math.max(far, d)
      }
      const now = [...svg.querySelectorAll('[data-testid="city-dots"] circle')]
      const sameNodes = now.length === dots.length && now.every((d) => (d as unknown as { __drive?: boolean }).__drive === true)
      return {
        dots: dots.length,
        moved,
        far: +far.toFixed(1),
        clock: +(t1 - t0).toFixed(1),
        visible: document.visibilityState,
        animations: document.getAnimations().length,
        sameNodes,
        fineDistinct: new Set(fine).size,
        fineSpan: `${Math.min(...fine)}–${Math.max(...fine)}`,
      }
    })
    console.log(
      `@${glass}: ${r.moved} of ${r.dots} dots moved in 4 s (farthest ${r.far} px); the plan's frames 3 s apart ${frames}; SMIL clock ran ${r.clock} s from ${scene.begins[0]} s (begins ${scene.begins.join('–')} s); ${r.visible}; web animations ${r.animations}; same DOM nodes after 4 s: ${r.sameNodes}; the first dot's x every 100 ms: ${r.fineDistinct} distinct values, ${r.fineSpan}`,
    )
    return { ...r, frames }
  }
  const wide = await walk('1280')

  // The same picture on a phone, for the reader — and the walk read there too on a fresh load, where city.page.spec reads it.
  await page.setViewportSize(PHONE)
  await page.reload()
  await ready(page)
  await expect(page.getByTestId('city-hall-figures')).toBeVisible({ timeout: 120_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
  await page.waitForTimeout(600)
  await shot(page, 'hq-hall-390@2x')
  const phone = await walk('390')
  // THE LAW (a walker must move) is the fixme below: read eight times on 2026-11-08, nobody moved (see it).
  console.log(`the people walk: 1280 ${wide.moved > 0 || wide.frames === 'differ'}, 390 ${phone.moved > 0 || phone.frames === 'differ'}`)
  const noScroll = await page.evaluate(() => ({ docH: document.documentElement.scrollHeight, clientH: document.documentElement.clientHeight, docW: document.documentElement.scrollWidth, clientW: document.documentElement.clientWidth }))
  console.log(`HQ @390 document: ${JSON.stringify(noScroll)}`)
  expect(noScroll.docW, 'the HQ scrolls sideways on a phone').toBeLessThanOrEqual(noScroll.clientW)
})

// WHAT THE DRIVE FOUND (2026-11-08, eight runs, 1280 and 390, fresh loads): THE PEOPLE DO NOT WALK. 0 of 36 walkers moved
// over 4 s (every dot's rect sampled in the page; the first dot's x read every 100 ms held one value), the plan's two clips
// 3 s apart were byte-identical, the svg's SMIL clock ran, nothing was paused, the DOM nodes were the same. The same walker
// markup alone on a blank page MOVES (x 100 → 121 in 3 s), and in the app `svg.setCurrentTime(svg.getCurrentTime())` wakes
// them (9.6 px in the next 1.5 s), a cloned svg appended to the body stands still too — a timeline that is never serviced
// until seeked, in this headless Chromium; whether the owner's Chrome shows the same is a read he can make at a glance.
// tests/city.page.spec.ts's "the people walk" passes on main because it reads the dot right after a viewport change (the
// plate re-scales under the dot). Rows 241 / 242 / 248: *"these dots are population, it can stop it can go back and forth"*.
test.fixme('HQ: the people walk — a dot moves on a fresh load at 1280 and 390 (rows 241/248 — DEFECT: 0 of 36 walkers move until the svg timeline is seeked)', async () => {})

// ── ROWS 247, 251, 255, 262: THE HALL IN PLACE ───────────────────────────────────────────────────
for (const size of [WIDE, PHONE]) {
  test(`HQ @${size.width}: Investors slides in from the right edge and closes, Influence folds and unfolds, a tile press moves no frame, figures hug their words`, async ({ page, request, baseURL }) => {
    await openHq(page, request, baseURL, size)
    const before = await frame(page)

    // (247) THE INVESTORS DRAWER: it SLIDES in (sampled frame by frame from BEFORE the press: its first painted left is
    // right of its last), says what it is, and its own close takes it away — the frame behind it untouched. Where it
    // LANDS is measured and printed; the window-edge law is the fixme below (a finding at the wide glass).
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
    // the owner's 2026-11-06 order (storage · cargo · recipes across it), so the earnings card leaves with the split there;
    // the header, the tiles and the rail still may not move.
    for (const tile of ['market', 'port', 'inn', 'production', 'hall']) {
      await page.getByTestId(`city-building-${tile}`).click()
      await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
      await page.waitForTimeout(400)
      const after = await frame(page)
      if (tile === 'production') expect({ ...after, earnings: null }, `pressing ${tile} moved the frame`).toEqual({ ...before, earnings: null })
      else expect(after, `pressing ${tile} moved the frame`).toEqual(before)
      const scrolled = await page.evaluate(() => window.scrollY)
      expect(scrolled, `pressing ${tile} scrolled the page`).toBe(0)
    }
  })
}

// WHAT THE DRIVE FOUND AT 1280 (2026-11-08, twice): the Investors drawer lands at x 856-1240, 40 px short of the window's
// right edge — it is docked over the page's side column (CityHallPanel.tsx:176-190 → trayDockPageClass, screenLayout.ts:81),
// the look the owner refused for the map's pop-up a day later (row 278: *"not totally fully on the right. i want it to slide
// from the right slide from the edge of the page"*, fixed for the map alone by #491/#493 with traySideEdgeClass). Held as a
// law for the day the HQ's drawer takes the same edge.
test.fixme('HQ @1280: the Investors drawer lands on the window\'s own right edge (row 247 / 278 — DEFECT: 40 px inset at 1280, docked over the side column)', async () => {})

// AND IT DOES NOT SLIDE (2026-11-08, twice, at 1280 and at 390): sampled frame by frame from before the press, the drawer's
// first painted frame is already where it lands (left 856 at 1280, 0 at 390); its `data-tray-mode` is `docked`, whose class
// (trayDockPageClass, screenLayout.ts:81) has no entering animation — `bv-slide-in-right` belongs to `mode="side"` alone
// (traySideEdgeClass). The owner's words (row 247): *"investors - tappable where when tapped, a list slides to the right"*.
test.fixme('HQ: the Investors list SLIDES in when tapped (row 247 — DEFECT: the docked drawer appears in place, no slide, at 1280 and 390)', async () => {})

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
  const purseBefore = (await page.getByTestId('city-summary').innerText()).replace(/\s+/g, ' ')
  console.log(`hall before: gold "${goldBefore}", your purse "${purseBefore}"`)

  // buy ONE unit of the first good on the Buy face, through the City page's own Market face
  await page.getByTestId('city-building-market').click()
  await expect(page.getByTestId('city-market-buy')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
  const row = page.locator('[data-testid="city-market-buy"] [data-testid="trade-row"]').first()
  const good = (await row.innerText()).split('\n')[0].trim()
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
  const purseAfter = (await page.getByTestId('city-summary').innerText()).replace(/\s+/g, ' ')
  console.log(`hall after: gold "${goldAfter}", your purse "${purseAfter}"`)
  expect(purseAfter, 'your purse did not fall after the purchase').not.toBe(purseBefore)
  await shot(page, 'hq-hall-live-gold-1280@2x')
})
