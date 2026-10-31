import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PAGE, DRIVEN (2026-10-30, owner's "Game screen development") — local build, phone glass.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The brief's four rules, measured in the running app rather than read off the code:
//   0. THE WHOLE SQUARE CITY IS ON THE GLASS at every shape: the plan panel can be a rectangle on a
//      wide or short window, and the scene must fit the entire plate inside it (never `slice`),
//      proven by mapping the viewBox's four corners through the svg's own screen CTM at 390×844,
//      320×568, 360×640, 1280×900 and 1440×900 (owner, 2026-10-31: "i told you that i need to see
//      all the city, a closed one").
//   1. NO page scroll, vertical or horizontal — the document does not overflow at 390×844, and the
//      rail and the earnings block sit inside the viewport.
//   2. A building press opens its FULL-SCREEN face and moves nothing behind it: every key region's
//      rectangle is identical before and after the press (the owner's UI law).
//   3. Population is a stated estimate off the served size tier — a huge grouped number with the
//      "≈" glyph and its caption. Status is the company's own SERVED influence points in this
//      city (`world.town_hall.influence.you.points`); Relationship is the harbour's served stance
//      toward the company's nation (home / ally / peace / rival / war), or the two served nations
//      compared while the dues block is not served — never a placeholder, never a random word.
//   4. The entry point (COMMAND · City → `City view`) and the routes beside it still work: MAP and
//      STATS open after the City page, and COMMAND's desk City face is here on return.
//
// Entry is driven as a player drives it: COMMAND, turn to the City face, press `City view`.

test.use({ viewport: { width: 390, height: 844 } })

/** Every region that must not move when a face opens. `top`/`left`/`w`/`h`, rounded. */
async function frameBoxes(page: Page) {
  return page.evaluate(() => {
    const pick = (id: string) => {
      const el = document.querySelector(`[data-testid="${id}"]`)
      if (!el) return null
      const r = el.getBoundingClientRect()
      return { top: Math.round(r.top), left: Math.round(r.left), w: Math.round(r.width), h: Math.round(r.height) }
    }
    return {
      header: pick('city-header'),
      scene: pick('city-info-image'),
      summary: pick('city-summary'),
      grid: pick('city-building-grid'),
      earnings: pick('city-earnings'),
      rail: pick('city-rail'),
    }
  })
}

async function scrollState(page: Page) {
  return page.evaluate(() => {
    const el = document.documentElement
    const rail = document.querySelector('[data-testid="city-rail"]')!.getBoundingClientRect()
    const earnings = document.querySelector('[data-testid="city-earnings"]')!.getBoundingClientRect()
    return {
      docW: el.scrollWidth,
      clientW: el.clientWidth,
      docH: el.scrollHeight,
      clientH: el.clientHeight,
      scrollY: window.scrollY,
      railBottom: Math.round(rail.bottom),
      earningsBottom: Math.round(earnings.bottom),
      vh: window.innerHeight,
    }
  })
}

/** THE SCENE SITS EXACTLY IN ITS SQUARE FRAME (owner, 2026-10-31: "the map is sticking out of its
 *  frame, meaning it is bigger than the square"). Clipping would hide an oversized drawing, so the
 *  proof is the boxes: every edge and both dimensions of `city-scene` must be the panel's, within
 *  0.5 px, at every glass. */
async function expectSceneInFrame(page: Page, where: string) {
  const gaps = await page.evaluate(() => {
    const panel = document.querySelector('[data-testid="city-info-image"]')!.getBoundingClientRect()
    const scene = document.querySelector('[data-testid="city-scene"]')!.getBoundingClientRect()
    return {
      left: scene.left - panel.left,
      top: scene.top - panel.top,
      right: panel.right - scene.right,
      bottom: panel.bottom - scene.bottom,
      width: scene.width - panel.width,
      height: scene.height - panel.height,
    }
  })
  for (const [side, gap] of Object.entries(gaps)) {
    expect(Math.abs(gap), `the scene is not inside its frame at the ${side} (${where})`).toBeLessThanOrEqual(0.5)
  }
}

/** THE WHOLE SQUARE CITY IS ON THE GLASS (owner, 2026-10-31: "i told you that i need to see all the
 *  city, a closed one"). On a wide or short window the flex row can flatten the plan panel into a
 *  rectangle; the old `xMidYMid slice` then scaled the 240×240 plate to COVER the panel and cropped
 *  the top and bottom of the walled city — the "section" the owner saw. The scene now uses
 *  `xMidYMid meet`, so the whole plate is drawn inside the panel. The proof does not trust the
 *  attribute: it maps the viewBox's four corners through the svg's own screen CTM and requires
 *  every corner ON the svg's rectangle. Under a slice crop the corners land outside it. */
async function expectWholeCityDrawn(page: Page, where: string) {
  const m = await page.evaluate(() => {
    const svg = document.querySelector('[data-testid="city-scene"]') as SVGSVGElement | null
    if (!svg) return null
    const box = svg.getBoundingClientRect()
    const ctm = svg.getScreenCTM()
    if (!ctm) return null
    const vb = svg.viewBox.baseVal
    const p = svg.createSVGPoint()
    const corners = [
      [vb.x, vb.y],
      [vb.x + vb.width, vb.y],
      [vb.x, vb.y + vb.height],
      [vb.x + vb.width, vb.y + vb.height],
    ].map(([x, y], i) => {
      p.x = x
      p.y = y
      const q = p.matrixTransform(ctm)
      return { i, x: q.x, y: q.y }
    })
    return { box: { left: box.left, top: box.top, right: box.right, bottom: box.bottom }, corners }
  })
  expect(m, `the city scene is not rendered (${where})`).not.toBeNull()
  for (const c of m!.corners) {
    expect(c.x, `the city's corner ${c.i} is off its frame to the left (${where})`).toBeGreaterThanOrEqual(m!.box.left - 0.5)
    expect(c.x, `the city's corner ${c.i} is off its frame to the right (${where})`).toBeLessThanOrEqual(m!.box.right + 0.5)
    expect(c.y, `the city's corner ${c.i} is off its frame above (${where})`).toBeGreaterThanOrEqual(m!.box.top - 0.5)
    expect(c.y, `the city's corner ${c.i} is off its frame below (${where})`).toBeLessThanOrEqual(m!.box.bottom + 0.5)
  }
}

test('the City page: entry, no scroll, placeholders, and a building face that moves nothing', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)

  // ── THE ENTRY POINT (as a player: COMMAND → City → City view) ────────────────────────────────
  await page.goto('command')
  await ready(page)
  await page.getByRole('tab', { name: 'City', exact: true }).click()
  await expect(page.getByTestId('desk-city')).toBeVisible()
  const door = page.getByTestId('desk-city-open')
  await expect(door).toBeVisible()
  await expect(door).toHaveText('City view')
  await door.click()
  await expect(page).toHaveURL(/\/city\?port=[A-Z]{3}/)
  await ready(page)
  const screen = page.getByTestId('city-screen')
  await expect(screen).toBeVisible()
  await expect(page.getByTestId('city-name')).not.toBeEmpty()
  await expect(page.getByTestId('city-scene')).toHaveAttribute('data-phase', /day|night/)
  await expect(page.getByTestId('city-phase')).toHaveAttribute('data-phase', /day|night/)

  // ── 1. NO PAGE SCROLL, VERTICAL OR HORIZONTAL ────────────────────────────────────────────────
  const s = await scrollState(page)
  console.log(`city scroll: ${s.docW}/${s.clientW} wide, ${s.docH}/${s.clientH} tall, scrollY ${s.scrollY}, rail bottom ${s.railBottom}`)
  expect(s.docW, 'the City page scrolls sideways').toBeLessThanOrEqual(s.clientW)
  expect(s.docH, 'the City page scrolls down').toBeLessThanOrEqual(s.clientH)
  expect(s.scrollY, 'the City page is scrolled').toBe(0)
  expect(s.railBottom, 'the rail hangs below the glass').toBeLessThanOrEqual(s.vh)
  expect(s.earningsBottom, 'the earnings block hangs below the glass').toBeLessThanOrEqual(s.vh)
  await expectSceneInFrame(page, '390×844')
  await expectWholeCityDrawn(page, '390×844')

  // THE LANDING SCENE'S NODE BUDGET (owner, 2026-10-31: "the game became slow, find this"). The
  // stipple, the window lights and the still people are drawn as a few paths, not one element per
  // dot; the scene keeps its exact look at ~390 elements. This fails if a future change goes back.
  const sceneNodes = await page.getByTestId('city-scene').evaluate((svg) => svg.querySelectorAll('*').length)
  console.log(`scene nodes: ${sceneNodes}`)
  expect(sceneNodes, 'the city scene is over its 400-node budget').toBeLessThan(400)

  // ── 2. THE THREE FIGURES: POPULATION (A STATED ESTIMATE), STATUS AND RELATIONSHIP (SERVED) ──
  // Population is a stated estimate off the served size tier (owner, 2026-10-31: "more tiny dot
  // with huge number"). Status is the company's own influence points in this city; Relationship is
  // the harbour's served stance toward the nation the company sails for — or, while the dues block
  // is not served, the two SERVED nations compared (owner: "status and relationship too"). Neither
  // cell may be a placeholder.
  const populationCell = page.getByTestId('city-population')
  await expect(populationCell, 'the population is still a placeholder').not.toHaveAttribute('data-placeholder', 'true')
  const populationText = await populationCell.innerText()
  console.log(`population: ${populationText.replace(/\s+/g, ' ')}`)
  expect(populationText, 'the population estimate is not shown as an estimate').toContain('≈')
  expect(populationText, 'the population estimate is not grouped digits').toMatch(/\d{1,3}(,\d{3})+/)
  expect(Number(populationText.replace(/[^\d]/g, '')), 'the population estimate is not a city-sized number').toBeGreaterThanOrEqual(1000)

  // STATUS — the company's own influence in this city, a served figure (`influence.you.points`).
  const statusCell = page.getByTestId('city-status')
  await expect(statusCell, 'Status is still a placeholder').not.toHaveAttribute('data-placeholder', 'true')
  // the hall's read rides the world beat: the cell prints '—' until the served influence lands
  await expect
    .poll(async () => statusCell.innerText(), { timeout: 60_000, message: 'Status never received the served influence points' })
    .not.toContain('—')
  const statusText = await statusCell.innerText()
  console.log(`status: ${statusText.replace(/\s+/g, ' ')}`)
  expect(statusText, 'Status does not print a served number').toMatch(/\d/)
  expect(statusText, 'Status is the placeholder dash').not.toContain('—')

  // RELATIONSHIP — the server's stance when the dues block is served (home / ally / peace / rival
  // / war), else the two served nations compared. The cell carries the served holder nation; the
  // printed word must be one of the city's words and, when a stance is served, exactly that
  // stance's word. The home-port word itself names a served fact: the company's nation and the
  // city's holder are the same.
  const relationCell = page.getByTestId('city-relationship')
  await expect(relationCell, 'Relationship is still a placeholder').not.toHaveAttribute('data-placeholder', 'true')
  // the holder nation is the served fact the word stands on; wait for the world's allegiance read
  await expect
    .poll(async () => relationCell.getAttribute('data-nation'), { timeout: 60_000, message: 'Relationship never received the served holder nation' })
    .toMatch(/^[A-Z]{3}$/)
  const relation = await relationCell.evaluate((el) => ({
    text: (el as HTMLElement).innerText.replace(/\s+/g, ' ').trim(),
    stance: el.getAttribute('data-stance'),
    nation: el.getAttribute('data-nation'),
  }))
  console.log(`relationship: ${JSON.stringify(relation)}`)
  const STANCE_WORDS: Record<string, string> = { home: 'Home port', ally: 'Ally', peace: 'Peace', rival: 'Rival', war: 'War' }
  const FALLBACK_WORDS = ['Home port', 'Different nation', 'Free port', 'No nation']
  expect(relation.nation, 'Relationship does not carry the served holder nation').toMatch(/^[A-Z]{3}$|^none$/)
  if (relation.stance !== null && relation.stance !== 'none') {
    expect(STANCE_WORDS[relation.stance], `the served stance "${relation.stance}" is not one this spec knows`).toBeTruthy()
    expect(relation.text, 'Relationship does not print the served stance').toContain(STANCE_WORDS[relation.stance])
  } else {
    expect(
      FALLBACK_WORDS.some((w) => relation.text.includes(w)),
      `Relationship prints no served word: ${relation.text}`,
    ).toBe(true)
  }
  expect(relation.text, 'Relationship prints the placeholder dash').not.toContain('—')
  await expect(page.getByTestId('city-gold')).toBeVisible()
  // Gold is NOT a placeholder: the city's served purse lands (0 on a new local world), and your
  // own purse and crew are served figures too.
  await expect(page.getByTestId('city-gold')).not.toHaveAttribute('data-placeholder', 'true')
  await expect.poll(async () => page.getByTestId('city-gold').innerText(), { timeout: 60_000 }).not.toContain('—')
  await expect.poll(async () => page.getByTestId('city-your-gold').innerText(), { timeout: 60_000 }).toContain('🪙')
  await expect(page.getByTestId('city-employees')).toContainText(/\d/)

  // ── 3. SIX BUILDINGS; A PRESS OPENS A FULL-SCREEN FACE AND MOVES NOTHING ────────────────────
  for (const b of ['hall', 'market', 'storage', 'forge', 'port', 'inn']) {
    await expect(page.getByTestId(`city-building-${b}`), `building ${b} is missing`).toBeVisible()
  }
  const before = await frameBoxes(page)

  await page.getByTestId('city-building-storage').click()
  const face = page.getByTestId('city-face')
  await expect(face).toBeVisible()
  await expect(face).toHaveAttribute('data-building', 'storage')
  // full screen: the layer covers the glass
  const faceBox = await face.boundingBox()
  expect(Math.round(faceBox!.width)).toBe(390)
  expect(Math.round(faceBox!.height)).toBe(844)
  // nothing behind it moved
  expect(await frameBoxes(page), 'opening a face re-flowed the page behind it').toEqual(before)
  // and the document still does not scroll while the face stands
  const withFace = await page.evaluate(() => ({ w: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }))
  expect(withFace.w).toBeLessThanOrEqual(withFace.cw)
  await page.getByTestId('city-face-back').click()
  await expect(face).toHaveCount(0)
  expect(await frameBoxes(page), 'closing a face moved the page').toEqual(before)

  // The Forge is the goods forge (0281): the crafted trade goods, their recipes, and a tray whose
  // Forge button is the server's to answer. A 287-recipe catalogue scrolls INSIDE the sheet — the
  // page behind it must not gain a scrollbar.
  await page.getByTestId('city-building-forge').click()
  await expect(page.getByTestId('city-face')).toHaveAttribute('data-building', 'forge')
  await expect(page.getByTestId('port-forge')).toBeVisible()
  const forgeTiles = page.locator('[data-testid^="forge-product-"]')
  await expect.poll(() => forgeTiles.count(), { timeout: 60_000 }).toBeGreaterThan(0)
  await expect(page.getByTestId('forge-tier-1')).toBeVisible()
  const forgeScroll = await page.evaluate(() => ({
    w: document.documentElement.scrollWidth,
    cw: document.documentElement.clientWidth,
    h: document.documentElement.scrollHeight,
    ch: document.documentElement.clientHeight,
  }))
  expect(forgeScroll.w, 'the Forge face scrolls sideways').toBeLessThanOrEqual(forgeScroll.cw)
  expect(forgeScroll.h, 'the Forge face scrolls the page').toBeLessThanOrEqual(forgeScroll.ch)
  // One recipe opens its tray: ingredients with a have/need figure, and one Forge button.
  const first = forgeTiles.first()
  const firstCode = (await first.getAttribute('data-testid'))!.replace('forge-product-', '')
  await first.click()
  await expect(page.getByTestId('forge-tray')).toBeVisible()
  // A fresh world has nothing ashore: the recipe's have/need figures are printed, the Forge button
  // is there but the server's own verdict keeps it shut, and the shortfall is named.
  await expect(page.getByTestId(`forge-make-${firstCode}`)).toBeVisible()
  await expect(page.getByTestId(`forge-make-${firstCode}`)).toBeDisabled()
  await expect(page.getByText(/^Missing:/)).toBeVisible()
  await page.getByTestId('tray-close').click()
  await page.getByTestId('city-face-back').click()
  await expect(page.getByTestId('city-face')).toHaveCount(0)

  // An existing face opens whole: the market is the quay's own ledger.
  await page.getByTestId('city-building-market').click()
  await expect(page.getByTestId('city-face')).toHaveAttribute('data-building', 'market')
  await expect(page.getByTestId('city-face')).not.toBeEmpty()
  await page.getByTestId('city-face-back').click()

  // ── 1b. THE SAME PAGE ON A SMALLER GLASS (320×568) ──────────────────────────────────────────
  await page.setViewportSize({ width: 320, height: 568 })
  await page.waitForTimeout(400)
  const small = await scrollState(page)
  console.log(`small scroll: ${small.docW}/${small.clientW} wide, ${small.docH}/${small.clientH} tall, rail bottom ${small.railBottom}`)
  expect(small.docW, 'the City page scrolls sideways at 320').toBeLessThanOrEqual(small.clientW)
  expect(small.docH, 'the City page scrolls down at 320').toBeLessThanOrEqual(small.clientH)
  expect(small.railBottom, 'the rail hangs below a 320×568 glass').toBeLessThanOrEqual(small.vh)
  await expectSceneInFrame(page, '320×568')
  await expectWholeCityDrawn(page, '320×568')
  // …and the six building tiles still clear the 44 px reach floor
  const heights = await page.locator('[data-testid^="city-building-"]').evaluateAll((es) => es.map((e) => Math.round(e.getBoundingClientRect().height)))
  expect(Math.min(...heights), `a building tile is under 44 px at 320: ${heights.join(', ')}`).toBeGreaterThanOrEqual(44)

  // ── 1c. THE SAME PAGE ON A 360×640 GLASS ────────────────────────────────────────────────────
  await page.setViewportSize({ width: 360, height: 640 })
  await page.waitForTimeout(400)
  const mid = await scrollState(page)
  console.log(`360 scroll: ${mid.docW}/${mid.clientW} wide, ${mid.docH}/${mid.clientH} tall, rail bottom ${mid.railBottom}`)
  expect(mid.docW, 'the City page scrolls sideways at 360').toBeLessThanOrEqual(mid.clientW)
  expect(mid.docH, 'the City page scrolls down at 360').toBeLessThanOrEqual(mid.clientH)
  expect(mid.railBottom, 'the rail hangs below a 360×640 glass').toBeLessThanOrEqual(mid.vh)
  await expectSceneInFrame(page, '360×640')
  await expectWholeCityDrawn(page, '360×640')

  // ── 1d. THE WIDE GLASS — THE SHAPE THE OWNER REPORTED CUT (2026-10-31: "i told you that i need
  // to see all the city, a closed one"). A wide or short window flattens the plan panel into a
  // rectangle; the old `slice` scaled the square city to COVER it and cropped the top and bottom of
  // the walled town. The whole plate must be on the glass here too, and the page must not gain a
  // scroll: these sizes are the ones that were never measured before the report.
  for (const [w, h] of [
    [1280, 900],
    [1440, 900],
  ] as const) {
    await page.setViewportSize({ width: w, height: h })
    await page.waitForTimeout(400)
    const wide = await scrollState(page)
    console.log(`wide ${w}×${h} scroll: ${wide.docW}/${wide.clientW} wide, ${wide.docH}/${wide.clientH} tall, rail bottom ${wide.railBottom}`)
    expect(wide.docW, `the City page scrolls sideways at ${w}×${h}`).toBeLessThanOrEqual(wide.clientW)
    expect(wide.docH, `the City page scrolls down at ${w}×${h}`).toBeLessThanOrEqual(wide.clientH)
    expect(wide.railBottom, `the rail hangs below a ${w}×${h} glass`).toBeLessThanOrEqual(wide.vh)
    await expectSceneInFrame(page, `${w}×${h}`)
    await expectWholeCityDrawn(page, `${w}×${h}`)
    // The same squeeze that flattened the plan also crushed the figures card to a 16-px sliver on
    // these windows; the population hero must actually fit inside the card, not be clipped away.
    const card = await page.evaluate(() => {
      const summary = document.querySelector('[data-testid="city-summary"]')!.getBoundingClientRect()
      const pop = document.querySelector('[data-testid="city-population"]')!.getBoundingClientRect()
      return { h: summary.height, popBottom: pop.bottom, summaryBottom: summary.bottom }
    })
    expect(card.h, `the figures card is crushed at ${w}×${h}`).toBeGreaterThanOrEqual(120)
    expect(card.popBottom, `the population figure is clipped by the figures card at ${w}×${h}`).toBeLessThanOrEqual(card.summaryBottom + 0.5)
  }
  await page.setViewportSize({ width: 390, height: 844 })

  // ── 3a. THE PEOPLE WALK (owner, 2026-10-30: "see people moving as dots"; 2026-10-31: the crowd
  // also waits and turns back, but these walkers are the ones the spec measures). The drawing is
  // NOT pressable: the six building tiles above are the only doors.
  // the people WALK: one dot's place on the glass changes while we watch
  const dot = page.getByTestId('city-dots').locator('circle').first()
  const p0 = await dot.boundingBox()
  await page.waitForTimeout(900)
  const p1 = await dot.boundingBox()
  expect(p0 && p1, 'a people dot has no box').toBeTruthy()
  const moved = Math.abs(p1!.x - p0!.x) + Math.abs(p1!.y - p0!.y)
  expect(moved, `the people are still (moved ${moved.toFixed(2)} px in 900 ms)`).toBeGreaterThan(0.5)

  // ── 3b. THE CITY IS THE APP'S HOME (owner, 2026-10-30: the new full-screen city IS the game's
  // face — "i keep getting the old screen"). The root route lands on the city; the rail has NO
  // Command cell (owner, 2026-10-31: "i told you to remove the command tab"), and the desk's door
  // from here is the MARKET building, whose face composes the trade face.
  await page.goto('/')
  await expect(page).toHaveURL(/\/city(\?|$)/)
  await ready(page)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  await expect(page.getByTestId('city-nav').getByTestId('nav-cell-command')).toHaveCount(0)
  await page.getByTestId('city-building-market').click()
  await expect(page.getByTestId('city-face')).toHaveAttribute('data-building', 'market')
  await expect(page.getByTestId('quay-stores'), 'the market face is not the trade face').toBeVisible({
    timeout: 60_000,
  })
  await page.getByTestId('city-face-back').click()
  await expect(page.getByTestId('city-face')).toHaveCount(0)

  // ── 4. NO EXISTING ROUTE BROKE ───────────────────────────────────────────────────────────────
  // The rail's map and stats are the app's own routes, reached from here.
  await page.getByTestId('nav-cell-/map').click()
  await expect(page).toHaveURL(/\/map$/)
  await ready(page)
  await expect(page.getByTestId('map-chart')).toBeVisible()

  await page.goto('stats')
  await ready(page)
  await expect(page.getByTestId('stats')).toBeVisible()

  // And the desk's City face is exactly where it was, with its door.
  await page.goto('command')
  await ready(page)
  await page.getByRole('tab', { name: 'City', exact: true }).click()
  await expect(page.getByTestId('desk-city')).toBeVisible()
  await expect(page.getByTestId('desk-city-open')).toBeVisible()
})
