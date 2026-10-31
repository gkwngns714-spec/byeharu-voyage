import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PAGE, DRIVEN (2026-10-30, owner's "Game screen development") — local build, phone glass.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The brief's four rules, measured in the running app rather than read off the code:
//   1. NO page scroll, vertical or horizontal — the document does not overflow at 390×844, and the
//      rail and the earnings block sit inside the viewport.
//   2. A building press opens its FULL-SCREEN face and moves nothing behind it: every key region's
//      rectangle is identical before and after the press (the owner's UI law).
//   3. Population is a stated estimate off the served size tier — a huge grouped number with the
//      "≈" glyph and its caption; Status and Relationship stay visibly placeholders ("—", marked
//      `data-placeholder`) with the "next slice" caption — never a number dressed as game data.
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

  // ── 2. THE POPULATION ESTIMATE, AND TWO PLACEHOLDERS ────────────────────────────────────────
  // Population is no longer a placeholder: the huge estimate is derived from the served size tier
  // and says so (owner, 2026-10-31: "more tiny dot with huge number"). Status and Relationship are
  // still the data slice's and stay marked placeholders.
  for (const id of ['city-status', 'city-relationship']) {
    const cell = page.getByTestId(id)
    await expect(cell, `${id} is not marked as a placeholder`).toHaveAttribute('data-placeholder', 'true')
    await expect(cell, `${id} does not print the placeholder`).toContainText('—')
  }
  const populationCell = page.getByTestId('city-population')
  await expect(populationCell, 'the population is still a placeholder').not.toHaveAttribute('data-placeholder', 'true')
  const populationText = await populationCell.innerText()
  console.log(`population: ${populationText.replace(/\s+/g, ' ')}`)
  expect(populationText, 'the population estimate is not shown as an estimate').toContain('≈')
  expect(populationText, 'the population estimate is not grouped digits').toMatch(/\d{1,3}(,\d{3})+/)
  expect(Number(populationText.replace(/[^\d]/g, '')), 'the population estimate is not a city-sized number').toBeGreaterThanOrEqual(1000)
  await expect(page.getByTestId('city-soon')).toBeVisible()
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
  // face — "i keep getting the old screen"). The root route lands on the city, and the rail's
  // Command cell is the one press back to the desk.
  await page.goto('/')
  await expect(page).toHaveURL(/\/city(\?|$)/)
  await ready(page)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  await page.getByTestId('nav-cell-command').click()
  await expect(page).toHaveURL(/\/command$/)
  await ready(page)
  await expect(page.getByTestId('command')).toBeVisible()

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
