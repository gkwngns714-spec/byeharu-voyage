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
//   2. ONE FRAME, TWO REGIONS (owner, 2026-10-31: *"in buildings 6 building tappable should always
//      be inside. when pressed each building, HQ stays the same, but the the location where the
//      city image is, as well as the right side should only change."*). The six building tiles sit
//      in the frame and are always visible; a press changes only the plan's mark and the RIGHT
//      panel — never the header, the tiles, the figures or the rail (their boxes are compared
//      before and after every press). The Town Hall is the default panel: treasury, influence book
//      (NO market rows, NO tax rows), one tappable Investors row whose drawer slides in from the
//      RIGHT with its own close. Every other building composes its existing face IN the panel. No
//      page scroll anywhere, and the hall panel itself needs no scroll at 390 or 320.
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

/** Every region of the FRAME that must not move when a building is pressed. `top`/`left`/`w`/`h`,
 *  rounded. The split (the plan and the open place's panel) is the one region a press MAY change;
 *  the frame above and below it may not. */
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
      grid: pick('city-building-grid'),
      rail: pick('city-rail'),
    }
  })
}

async function scrollState(page: Page) {
  return page.evaluate(() => {
    const el = document.documentElement
    const rail = document.querySelector('[data-testid="city-rail"]')!.getBoundingClientRect()
    return {
      docW: el.scrollWidth,
      clientW: el.clientWidth,
      docH: el.scrollHeight,
      clientH: el.clientHeight,
      scrollY: window.scrollY,
      railBottom: Math.round(rail.bottom),
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

/** THE HQ SPLIT IS SIDE BY SIDE, at every glass (owner, 2026-10-31: "the town hall screen is on the
 *  same HQ screen, but where the city is"): the plan's right edge is left of the hall panel's left
 *  edge, and both have real boxes. The plan DRAWING stays square through CityScene's meet contract
 *  (the whole-city proof above); its panel is square at the phone sizes, asserted there. */
async function expectHqSplit(page: Page, where: string) {
  const b = await page.evaluate(() => {
    const plan = document.querySelector('[data-testid="city-info-image"]')!.getBoundingClientRect()
    const panel = document.querySelector('[data-testid="city-hall-panel"]')!.getBoundingClientRect()
    return {
      planRight: plan.right,
      planW: plan.width,
      planH: plan.height,
      panelLeft: panel.left,
      panelW: panel.width,
      panelH: panel.height,
    }
  })
  expect(b.planW, `the plan has no width (${where})`).toBeGreaterThan(0)
  expect(b.panelW, `the hall panel has no width (${where})`).toBeGreaterThan(0)
  expect(b.panelH, `the hall panel has no height (${where})`).toBeGreaterThan(0)
  expect(b.planRight, `the plan is not left of the hall panel (${where})`).toBeLessThanOrEqual(b.panelLeft + 0.5)
}

test('the City page: entry, the six-tile frame, the hall in place, and no scroll', async ({ page, request, baseURL }) => {
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
  await expect(page.getByTestId('city-employees')).toContainText(/\d/)

  // ── 3. THE HQ SPLIT: PLAN LEFT, THE TOWN HALL IN PLACE RIGHT ────────────────────────────────
  // The hall has NO face and NO overlay; it stands in the main area beside the plan (owner,
  // 2026-10-31: "the town hall screen is on the same HQ screen, but where the city is"). The panel
  // carries the treasury, the influence book (no market rows, no tax rows) and the Investors row.
  await expectHqSplit(page, '390×844')
  // THE SIX TILES ARE THE FRAME: all six are visible at once, at the 44-px reach floor.
  const six = ['hall', 'market', 'storage', 'forge', 'port', 'inn']
  for (const b of six) {
    const tile = page.getByTestId(`city-building-${b}`)
    await expect(tile, `building tile ${b} is missing from the frame`).toBeVisible()
    const box = await tile.boundingBox()
    expect(box!.height, `building tile ${b} is under 44 px`).toBeGreaterThanOrEqual(44)
  }
  // THE HALL PANEL NEEDS NO SCROLL AT 390 (owner, 2026-10-31: "right now city hall i need to
  // scroll down"): its content fits the panel.
  const hallFit = await page.getByTestId('city-hall-scroll').evaluate((el) => ({ sh: el.scrollHeight, ch: el.clientHeight }))
  console.log(`hall scroll: ${hallFit.sh}/${hallFit.ch}`)
  expect(hallFit.sh, 'the hall panel scrolls at 390×844').toBeLessThanOrEqual(hallFit.ch)
  const hallPanel = page.getByTestId('city-hall-panel')
  await expect(hallPanel).toBeVisible()
  // THE INFLUENCE IS FOLDABLE (owner, 2026-10-31): the book stands behind the fold; a press opens
  // it in place — and TAX INFO STAYS OFF (the owner, 2026-10-30: "no need market info. tax info.
  // influence yes…" — that instruction stands).
  const fold = page.getByTestId('city-hall-influence')
  await expect(fold).toHaveAttribute('aria-expanded', 'false')
  await expect(hallPanel.getByTestId('city-hall-book')).toHaveCount(0)
  await fold.click()
  await expect(fold).toHaveAttribute('aria-expanded', 'true')
  await expect(hallPanel.getByTestId('townhall-influence')).toBeVisible({ timeout: 60_000 })
  await expect(hallPanel.getByTestId('city-hall-investors')).toBeVisible()
  await expect(hallPanel.locator('[data-testid="townhall-day"]'), 'market info must not stand in the hall panel').toHaveCount(0)
  for (const id of ['townhall-your-tax', 'townhall-mayor', 'townhall-mayor-tax']) {
    await expect(hallPanel.locator(`[data-testid="${id}"]`), `${id} must not stand in the influence book`).toHaveCount(0)
  }
  await fold.click()
  await expect(fold).toHaveAttribute('aria-expanded', 'false')
  // the row is a real control at the 44-px reach floor
  const investorRow = await page.getByTestId('city-hall-investors').boundingBox()
  expect(investorRow!.height, 'the Investors row is under 44 px').toBeGreaterThanOrEqual(44)
  // tapping it opens the served board in a drawer from the RIGHT, full-width on a phone; the side
  // Tray slides in (bv-slide-in-right), so the boxes are read after it has landed at the right edge
  const beforePanel = await frameBoxes(page)
  await page.getByTestId('city-hall-investors').click()
  const drawer = page.getByTestId('city-investors-drawer')
  await expect(drawer).toBeVisible()
  await expect.poll(async () => Math.round((await drawer.boundingBox())!.x), { timeout: 5_000 }).toBe(0)
  const drawerBox = await drawer.boundingBox()
  expect(Math.round(drawerBox!.width), 'the investors drawer is not full-width at 390').toBe(390)
  expect(Math.round(drawerBox!.x + drawerBox!.width), 'the investors drawer is not at the right edge').toBe(390)
  expect(await frameBoxes(page), 'opening the investors drawer re-flowed the page behind it').toEqual(beforePanel)
  const closeBox = await drawer.getByTestId('tray-close').boundingBox()
  expect(closeBox!.height, 'the drawer close is under 44 px').toBeGreaterThanOrEqual(44)
  await drawer.getByTestId('tray-close').click()
  await expect(drawer).toHaveCount(0)
  expect(await frameBoxes(page), 'closing the investors drawer moved the page').toEqual(beforePanel)

  // A PRESS CHANGES ONLY THE TWO REGIONS (owner, 2026-10-31: "HQ stays the same, but the the
  // location where the city image is, as well as the right side should only change"): for every
  // place on the row the frame's boxes are IDENTICAL before and after, no page scroll appears, and
  // the right panel is the pressed place's — never a full-screen layer.
  const before = await frameBoxes(page)
  for (const b of six) {
    await page.getByTestId(`city-building-${b}`).click()
    // THE CITY IMAGE STAYS LEFT (owner, 2026-10-31) and the panel stands right of it: a press
    // changes the plan's mark and the right-hand panel only.
    await expect(page.getByTestId('city-info-image'), `pressing ${b} removed the city image`).toBeVisible()
    const imageBox = (await page.getByTestId('city-info-image').boundingBox())!
    if (b === 'hall') {
      await expect(page.getByTestId('city-hall-panel')).toBeVisible()
      await expect(page.getByTestId('city-face-panel')).toHaveCount(0)
    } else {
      const panel = page.getByTestId('city-face-panel')
      await expect(panel).toBeVisible()
      await expect(panel).toHaveAttribute('data-building', b)
      const pb = (await panel.boundingBox())!
      expect(pb.x, `the ${b} panel is not right of the city image`).toBeGreaterThanOrEqual(imageBox.x + imageBox.width - 1)
      expect(pb.width, `the ${b} panel is a full-screen layer`).toBeLessThan(390)
    }
    expect(await frameBoxes(page), `pressing ${b} re-flowed the frame`).toEqual(before)
    const withPanel = await page.evaluate(() => ({
      w: document.documentElement.scrollWidth,
      cw: document.documentElement.clientWidth,
      h: document.documentElement.scrollHeight,
      ch: document.documentElement.clientHeight,
    }))
    expect(withPanel.w, `pressing ${b} scrolls the page sideways`).toBeLessThanOrEqual(withPanel.cw)
    expect(withPanel.h, `pressing ${b} scrolls the page down`).toBeLessThanOrEqual(withPanel.ch)
  }
  await page.getByTestId('city-building-hall').click()
  await expect(page.getByTestId('city-hall-panel')).toBeVisible()

  // The Forge is the goods forge (0281): the compact panel lists the product TIERS (audit row 39 —
  // a product's control carries the product's name, never the whole recipe); a tier row opens its
  // products as the one page (the audit's no-panel-scroll law), and a product's tray is the
  // server's to answer.
  await page.getByTestId('city-building-forge').click()
  await expect(page.getByTestId('city-face-panel')).toHaveAttribute('data-building', 'forge')
  const tierRows = page.getByTestId('city-face-panel').locator('[data-summary-row]')
  await expect.poll(() => tierRows.count(), { timeout: 60_000 }).toBeGreaterThan(0)
  const tierId = (await tierRows.first().getAttribute('data-testid'))!
  const tier = tierId.replace('city-forge-tier-', '')
  await tierRows.first().click()
  const forgePage = page.locator('[data-detail-page]')
  await expect(forgePage).toBeVisible()
  await expect(page.getByTestId('port-forge')).toBeVisible()
  const forgeTiles = page.locator('[data-testid^="forge-product-"]')
  await expect.poll(() => forgeTiles.count(), { timeout: 60_000 }).toBeGreaterThan(0)
  await expect(page.getByTestId(`forge-tier-${tier}`)).toBeVisible()
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
  // back from the tier's page to the compact panel, then the hall
  await page.locator('[data-detail-back]').last().click()
  await expect(forgePage).toHaveCount(0)
  await page.getByTestId('city-building-hall').click()
  await expect(page.getByTestId('city-face-panel')).toHaveCount(0)

  // A compact face composes in the panel: the market's three board faces, one press from the quay's
  // own ledger (the page the row opens).
  await page.getByTestId('city-building-market').click()
  await expect(page.getByTestId('city-face-panel')).toHaveAttribute('data-building', 'market')
  await expect(page.getByTestId('city-market-buy')).toBeVisible({ timeout: 60_000 })
  await page.getByTestId('city-market-buy').click()
  const marketPage = page.locator('[data-detail-page]')
  await expect(marketPage).toBeVisible()
  await expect(page.getByTestId('quay-stores')).toBeVisible({ timeout: 60_000 })
  await page.locator('[data-detail-back]').last().click()
  await expect(marketPage).toHaveCount(0)
  await page.getByTestId('city-building-hall').click()
  await expect(page.getByTestId('city-hall-panel')).toBeVisible()

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
  // THE SPLIT HOLDS AT 320 TOO (owner: "you know that this game is also for mobile right?"): the
  // plan left, the hall panel right, the six tiles visible at once, and the drawer full-width from
  // the right on this phone.
  await expectHqSplit(page, '320×568')
  for (const b of six) {
    const tile = page.getByTestId(`city-building-${b}`)
    await expect(tile, `building tile ${b} is missing at 320`).toBeVisible()
  }
  // THE HALL AT 320 FITS WITHOUT SCROLL (owner, 2026-10-31: the Influence fold + the hall's five
  // figures): COLLAPSED is the default — one 44-px Influence row, the five compact figure lines and
  // the Investors row — so its scroller no longer scrolls; the EXPANDED book may scroll inside the
  // panel at the smallest glass (stated and measured by city.audit.spec), while the page itself
  // never does (asserted above).
  const hallFitSmall = await page.getByTestId('city-hall-scroll').evaluate((el) => ({ sh: el.scrollHeight, ch: el.clientHeight }))
  console.log(`hall content at 320: ${hallFitSmall.sh}/${hallFitSmall.ch}`)
  expect(hallFitSmall.ch, 'the hall panel has no height at 320').toBeGreaterThan(100)
  expect(hallFitSmall.sh, `the hall panel scrolls at 320: ${hallFitSmall.sh} > ${hallFitSmall.ch}`).toBeLessThanOrEqual(hallFitSmall.ch + 1)
  await page.getByTestId('city-hall-investors').click()
  const smallDrawer = page.getByTestId('city-investors-drawer')
  await expect(smallDrawer).toBeVisible()
  await expect.poll(async () => Math.round((await smallDrawer.boundingBox())!.x), { timeout: 5_000 }).toBe(0)
  expect(Math.round((await smallDrawer.boundingBox())!.width), 'the investors drawer is not full-width at 320').toBe(320)
  await smallDrawer.getByTestId('tray-close').click()
  await expect(smallDrawer).toHaveCount(0)
  // …and the five building tiles still clear the 44 px reach floor
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
    await expectHqSplit(page, `${w}×${h}`)
    // THE FIVE FIGURES LIVE IN THE HALL PANEL (owner, 2026-10-31: the frame's card is gone).
    for (const id of ['city-population', 'city-gold', 'city-status', 'city-relationship', 'city-employees']) {
      await expect(page.getByTestId(id), `${id} is missing at ${w}×${h}`).toBeVisible()
    }
  }
  await page.setViewportSize({ width: 390, height: 844 })

  // ── 3a. THE PEOPLE WALK (owner, 2026-10-30: "see people moving as dots"; 2026-10-31: the crowd
  // also waits and turns back, but these walkers are the ones the spec measures — and the owner
  // asked for the walk to be 3× slower, so the window is 2.5 s: a slower walker must still move).
  // The drawing is NOT pressable: the six building tiles above are the only ways in.
  // the people WALK: one dot's place on the glass changes while we watch.
  // A HIDDEN DOCUMENT PAUSES THE SMIL TIMELINE (2026-11-01: run 41212925876 on main reported
  // "moved 0.00 px in 2500 ms" on a loaded shard while this test passed locally, 21.8 s — the page
  // had been backgrounded and animateMotion froze). Bring the page to the front and POLL for the
  // movement instead of trusting one pair of samples; the law is unchanged (a walker must move).
  await page.bringToFront()
  const dot = page.getByTestId('city-dots').locator('circle').first()
  const p0 = await dot.boundingBox()
  expect(p0, 'a people dot has no box').toBeTruthy()
  let moved = 0
  for (let i = 0; i < 8 && moved <= 0.5; i++) {
    await page.waitForTimeout(800)
    const p1 = await dot.boundingBox()
    if (p1) moved = Math.max(moved, Math.abs(p1.x - p0!.x) + Math.abs(p1.y - p0!.y))
  }
  expect(moved, `the people are still (moved ${moved.toFixed(2)} px in up to 6.4 s)`).toBeGreaterThan(0.5)

  // ── 3b. THE CITY IS THE APP'S HOME (owner, 2026-10-30: the new full-screen city IS the game's
  // face — "i keep getting the old screen"). The root route lands on the city; the rail has NO
  // Command cell (owner, 2026-10-31: "i told you to remove the command tab"), and the desk's door
  // from here is the MARKET building, whose face composes the trade face.
  await page.goto('/')
  await expect(page).toHaveURL(/\/city(\?|$)/)
  await ready(page)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  await expect(page.getByTestId('city-rail').getByTestId('nav-cell-command')).toHaveCount(0)
  await page.getByTestId('city-building-market').click()
  await expect(page.getByTestId('city-face-panel')).toHaveAttribute('data-building', 'market')
  await expect(page.getByTestId('city-market-buy')).toBeVisible({ timeout: 60_000 })
  await page.getByTestId('city-market-buy').click()
  await expect(page.getByTestId('quay-stores'), 'the market face is not the trade face').toBeVisible({
    timeout: 60_000,
  })
  await page.locator('[data-detail-back]').last().click()
  await expect(page.locator('[data-detail-page]')).toHaveCount(0)
  await page.getByTestId('city-building-hall').click()
  await expect(page.getByTestId('city-face-panel')).toHaveCount(0)

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
