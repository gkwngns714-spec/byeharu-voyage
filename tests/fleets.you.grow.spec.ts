import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { GLASSES, phoneLaws, readGlass, type Flat, type Glass } from './unfold.fixture'
import { serveTwoFleets } from './twoFleets.fixture'
import { serveVeteranWorld, VETERAN_CAPTAINS, VETERAN_HULLS } from './manyFleets.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// FLEETS AND YOU GROW WITHOUT SCROLLING THE PAGE — the owner's law, measured with 2 hulls and with 8 (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"check everything, fix all, redo the design, make things unfolded, minimize scrolling, everything compact with full
// info."* (owner, 2026-11-01; docs/dev-log/2026-11-01-ui-unfold.md U1–U8; docs/dev-log/2026-11-02-sheets-grow.md.)
// The layout sweep of 2026-11-02 (row 5) built a veteran's world — the cap on fleets is EARNED (`fleet_max`) — and measured that
// FLEETS scrolled the PAGE 122 px at 390×844 and 326 px at 320×640, YOU 140 and 344 (476 and 1,050 with six captains), and that a
// company of two left two thirds of the glass empty. Both screens are now what the five unfolded screens are: figures over ONE list
// panel (src/components/ui/ListPanel.tsx) that takes the glass they leave and scrolls INSIDE itself.
//
//   U2  the document and the Sheet never scroll, and nothing scrolls sideways, at 390×844, 320×640 and 1280×800 — with two hulls
//       AND with eight; when the rows are longer than the panel, the PANEL scrolls (its last row comes into view) and the page
//       stays where it was;
//   U1  the panel stands inside the glass with at least min(rows, N) rows WHOLE before any press;
//   U3  nothing removed: every old test id is on the screen, with as many of them as the world has hulls and captains;
//   U5  no two text boxes cross, no sibling box overlaps another, no text stands one letter to a line, no row label is cut; cut text
//       carries its full text, and on a glass with no hover a press reads it whole; every row of the data is at least 44 px tall;
//   U8  a press on a fleet opens her page and nothing behind it moves; a press on a captain opens her tray, and the tray stands
//       OUTSIDE the panel's scroller.
//
// The two worlds are throwaway images built from this build's own (tests/twoFleets.fixture.ts, tests/manyFleets.fixture.ts). A
// spec may not skip for want of rows — CI fails any skipped test — so the rows are made, and the count of what stands is asserted:
// a world with one hull would pass every line below, and the first assertion refuses it.

type World = 'two' | 'veteran'
const WORLDS: Record<World, { serve: (page: Page) => Promise<void>; hulls: number; captains: number }> = {
  two: { serve: serveTwoFleets, hulls: 2, captains: 0 },
  veteran: { serve: serveVeteranWorld, hulls: VETERAN_HULLS, captains: VETERAN_CAPTAINS },
}

/** Rows WHOLE in the panel's body, by glass width, for the veteran's world (the budget in the dev-log, held a little below what
 *  was measured so a different font on CI cannot fail it). */
const NEED_FLEETS: Record<number, number> = { 390: 7, 320: 3, 1280: 8 }
const NEED_SHIPS: Record<number, number> = { 390: 6, 320: 5, 1280: 8 }
const NEED_CAPTAINS: Record<number, number> = { 390: 1, 320: 0, 1280: 6 }

/** How many `id` rows stand whole inside the panel's body right now, and how many there are. */
async function whole(page: Page, panel: string, id: string): Promise<{ whole: number; total: number }> {
  return page.getByTestId(panel).evaluate((el, row) => {
    const body = el.querySelector('[data-list-body]')
    if (!body) return { whole: 0, total: 0 }
    const b = body.getBoundingClientRect()
    const rows = [...body.querySelectorAll(`[data-testid="${row}"]`)]
    return {
      total: rows.length,
      whole: rows.filter((r) => {
        const x = r.getBoundingClientRect()
        return x.top >= b.top - 1 && x.bottom <= b.bottom + 1
      }).length,
    }
  }, id)
}

/** Every row of the data and every control in the panel that is under the 44-px reach floor. */
async function underFloor(page: Page, panel: string, rows: string[]): Promise<string[]> {
  return page.getByTestId(panel).evaluate((el, ids) => {
    const body = el.querySelector('[data-list-body]')
    if (!body) return ['no body']
    const small = (e: Element) => {
      const r = e.getBoundingClientRect()
      return r.width > 0 && r.height > 0 && r.height < 43.5
    }
    return [
      ...ids.flatMap((id) => [...body.querySelectorAll(`[data-testid="${id}"]`)].filter(small).map((e) => `${id} ${Math.round(e.getBoundingClientRect().height)}px`)),
      ...[...body.querySelectorAll('button, a')].filter(small).map((e) => `${e.tagName.toLowerCase()} "${(e.textContent ?? '').trim().slice(0, 24)}" ${Math.round(e.getBoundingClientRect().height)}px`),
    ]
  }, rows)
}

/** The panel, not the page, carries what does not fit: when the body is longer than itself, scroll it to its end and read the page. */
async function panelScrolls(page: Page, panel: string, rowId: string, where: string, failures: string[]): Promise<{ overflow: boolean }> {
  const body = page.getByTestId(panel).locator('[data-list-body]')
  const sizes = await body.evaluate((el) => ({ sh: el.scrollHeight, ch: el.clientHeight }))
  const overflow = sizes.sh > sizes.ch + 1
  if (!overflow) return { overflow }
  await body.evaluate((el) => {
    el.scrollTop = el.scrollHeight
  })
  await page.waitForTimeout(150)
  const after = await page.evaluate((row) => {
    const sheet = document.querySelector('[data-sheet]') as HTMLElement | null
    const b = document.querySelector('[data-list-body]')!.getBoundingClientRect()
    const rows = [...document.querySelectorAll(`[data-testid="${row}"]`)]
    const last = rows[rows.length - 1]?.getBoundingClientRect()
    return {
      pageY: window.scrollY,
      docTop: document.documentElement.scrollTop,
      sheetTop: sheet?.scrollTop ?? -1,
      lastReachable: last ? last.bottom <= b.bottom + 1 && last.top >= b.top - 1 : false,
    }
  }, rowId)
  if (after.pageY !== 0 || after.docTop !== 0 || after.sheetTop !== 0) failures.push(`${where}: scrolling the panel moved the page (${JSON.stringify(after)})`)
  if (!after.lastReachable) failures.push(`${where}: the last ${rowId} row is not reachable at the end of the panel`)
  await body.evaluate((el) => {
    el.scrollTop = 0
  })
  return { overflow }
}

/** THE GLASS IS THE PANEL'S: the panel stands on the glass from under the title to the Sheet's own bottom padding (8 px) — no glass
 *  is left empty under it (the sweep measured 508 px of it under two fleets at 390×844). Returns how far the panel's bottom stands above the glass's. */
async function glassUnder(page: Page, panel: string): Promise<number> {
  return page.evaluate((id) => {
    const main = document.querySelector('[data-sheet]')?.closest('main')?.getBoundingClientRect()
    const box = document.querySelector(`[data-testid="${id}"]`)?.getBoundingClientRect()
    return main && box ? Math.round(main.bottom - box.bottom) : -1
  }, panel)
}

/** The failures every screen shares: the page is flat, the panel stands on the glass, nothing crosses, nothing is one letter wide. */
function flat(m: Flat, where: string, failures: string[]): void {
  if (m.doc.sh > m.doc.ch + 1) failures.push(`${where}: the document scrolls ${m.doc.sh}/${m.doc.ch}`)
  if (m.sheet === null) failures.push(`${where}: no Sheet`)
  else {
    if (m.sheet.sh > m.sheet.ch + 1) failures.push(`${where}: the Sheet scrolls ${m.sheet.sh}/${m.sheet.ch}`)
    if (m.sheet.top !== 0) failures.push(`${where}: the Sheet is scrolled to ${m.sheet.top}`)
  }
  if (!m.rows.found) failures.push(`${where}: no list panel`)
  else if (!m.rows.inView) failures.push(`${where}: the panel is not inside the glass`)
  // THE PHONE LAWS, spelled once in tests/unfold.fixture.ts (read for a named subtree): no two boxes overlap, no text stands one letter wide,
  // nothing is cut without its full text and no row label is cut at all, nothing scrolls sideways
  failures.push(...phoneLaws(where, m))
}

async function open(page: Page, glass: Glass, world: World, route: string, sheet: string): Promise<void> {
  await page.setViewportSize(glass)
  await WORLDS[world].serve(page)
  await page.goto(route)
  await ready(page)
  await expect(page.getByTestId(sheet)).toBeVisible()
  await page
    .waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 })
    .catch(() => {})
}

/** One FLEETS state, every law. `ko` swaps the English words it reads for the Korean ones; the laws are the same. */
async function checkFleets(page: Page, glass: Glass, world: World, ko = false): Promise<void> {
  const { hulls } = WORLDS[world]
  const where = `FLEETS ${ko ? 'ko ' : ''}${world === 'two' ? '2 hulls' : `${hulls} hulls`} at ${glass.width}×${glass.height}`
  await open(page, glass, world, 'fleets', 'fleets')
  const failures: string[] = []

  // NON-VACUITY: the world really has this many fleets, and the old ids are on the screen
  await expect(page.getByTestId('fleet-row'), `${where}: the world does not hold ${hulls} fleets`).toHaveCount(hulls)
  await expect(page.getByTestId('fleet-row-bars')).toHaveCount(hulls)
  await expect(page.getByTestId('cargo-bar')).toHaveCount(hulls)
  await expect(page.getByTestId('fleets-list')).toBeVisible()
  await expect(page.getByTestId('fleets-list')).toContainText(ko ? `선단 ${hulls}개` : `${hulls} fleets`)

  const m = await readGlass(page, 'fleets-list', 'fleet-row', '[data-sheet]')
  console.log(`GROW ${where}: doc ${m.doc.sh}/${m.doc.ch}, sheet ${m.sheet?.sh}/${m.sheet?.ch}, rows ${m.rows.whole}/${m.rows.total}`)
  flat(m, where, failures)
  if (world === 'veteran') {
    const need = Math.min(m.rows.total, NEED_FLEETS[glass.width])
    if (m.rows.whole < need) failures.push(`${where}: ${m.rows.whole} whole fleets of ${m.rows.total}; the law is ${need}`)
  } else if (m.rows.whole !== m.rows.total) failures.push(`${where}: ${m.rows.whole} of ${m.rows.total} fleets whole`)
  for (const s of await underFloor(page, 'fleets-list', ['fleet-row'])) failures.push(`${where}: under the 44-px floor: ${s}`)
  const under = await glassUnder(page, 'fleets-list')
  if (under < 0 || under > 12) failures.push(`${where}: ${under} px of glass stand under the panel — the panel does not fill the glass`)
  const scroll = await panelScrolls(page, 'fleets-list', 'fleet-row', where, failures)
  // the panel is what scrolls where the fleets are longer than the glass: eight hulls on a 320×640 phone certainly are
  if (world === 'veteran' && glass.width === 320 && !scroll.overflow) failures.push(`${where}: eight fleets fit a 320×640 panel — the proof of an inner scroll is vacuous`)
  expect(failures, `FLEETS grew past the glass: ${where}`).toEqual([])
}

/** One YOU state, every law. */
async function checkYou(page: Page, glass: Glass, world: World, ko = false): Promise<void> {
  const { hulls, captains } = WORLDS[world]
  const where = `YOU ${ko ? 'ko ' : ''}${world === 'two' ? '2 hulls' : `${hulls} hulls`} at ${glass.width}×${glass.height}`
  await open(page, glass, world, 'you', 'you')
  const failures: string[] = []

  // NON-VACUITY: the hulls and captains this world holds, and every id the old screen carried
  await expect(page.getByTestId('you-ship'), `${where}: the world does not hold ${hulls} hulls`).toHaveCount(hulls)
  if (captains > 0) {
    await expect(page.getByTestId('your-captain'), `${where}: the world does not hold ${captains} captains`).toHaveCount(captains)
    await expect(page.getByTestId('your-captains-none')).toHaveCount(0)
  } else {
    await expect(page.getByTestId('your-captains-none')).toContainText(ko ? '고용하세요' : 'Hire one at an inn')
    await expect(page.getByTestId('your-captain')).toHaveCount(0)
  }
  for (const id of ['levels', 'you-list', 'you-ships', 'you-ships-count', 'your-captains']) await expect(page.getByTestId(id), `${where}: ${id} is gone`).toBeVisible()
  // THE THREE TRACKS ARE ALL ON THE SCREEN: two bars and the combat line while the server says there is no fighting (0069), three bars the day it does
  const tracks = await page.getByTestId('level-track').count()
  const waits = await page.getByTestId('combat-waits').count()
  expect(tracks + waits, `${where}: ${tracks} level bars and ${waits} combat lines — the three tracks are not all there`).toBe(3)
  await expect(page.getByTestId('you-ships-count')).toContainText(ko ? `선단 ${hulls}개` : 'fleets')

  const m = await readGlass(page, 'you-list', 'you-ship', '[data-sheet]')
  const caps = await whole(page, 'you-list', 'your-captain')
  console.log(`GROW ${where}: doc ${m.doc.sh}/${m.doc.ch}, sheet ${m.sheet?.sh}/${m.sheet?.ch}, ships ${m.rows.whole}/${m.rows.total}, captains ${caps.whole}/${caps.total}`)
  flat(m, where, failures)
  if (world === 'veteran') {
    const ships = Math.min(m.rows.total, NEED_SHIPS[glass.width])
    if (m.rows.whole < ships) failures.push(`${where}: ${m.rows.whole} whole ships of ${m.rows.total}; the law is ${ships}`)
    const cap = Math.min(caps.total, NEED_CAPTAINS[glass.width])
    if (caps.whole < cap) failures.push(`${where}: ${caps.whole} whole captains of ${caps.total}; the law is ${cap}`)
  } else if (m.rows.whole !== m.rows.total) failures.push(`${where}: ${m.rows.whole} of ${m.rows.total} ships whole`)
  for (const s of await underFloor(page, 'you-list', ['you-ship', 'your-captain'])) failures.push(`${where}: under the 44-px floor: ${s}`)
  const under = await glassUnder(page, 'you-list')
  if (under < 0 || under > 12) failures.push(`${where}: ${under} px of glass stand under the panel — the panel does not fill the glass`)
  const scroll = await panelScrolls(page, 'you-list', world === 'veteran' ? 'your-captain' : 'you-ship', where, failures)
  if (world === 'veteran' && glass.width === 320 && !scroll.overflow) failures.push(`${where}: eight hulls and six captains fit a 320×640 panel — the proof of an inner scroll is vacuous`)
  // THE FIGURES STAND ON THE GLASS, ABOVE THE PANEL: the levels are not inside the scroller
  const above = await page.evaluate(() => {
    const levels = document.querySelector('[data-testid="levels"]')?.getBoundingClientRect()
    const panel = document.querySelector('[data-testid="you-list"]')?.getBoundingClientRect()
    return levels && panel ? { levelsBottom: levels.bottom, panelTop: panel.top, inside: !!document.querySelector('[data-list-body] [data-testid="levels"]') } : null
  })
  if (above === null) failures.push(`${where}: the levels or the panel is missing`)
  else if (above.inside || above.levelsBottom > above.panelTop + 1) failures.push(`${where}: the levels are not above the panel (${JSON.stringify(above)})`)
  expect(failures, `YOU grew past the glass: ${where}`).toEqual([])
}

for (const world of Object.keys(WORLDS) as World[]) {
  for (const glass of GLASSES) {
    const tag = `${world === 'two' ? '2 hulls' : `${VETERAN_HULLS} hulls`} at ${glass.width}×${glass.height}`

    test(`FLEETS with ${tag}: the page is flat, every fleet stands in the panel, nothing removed`, async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await checkFleets(page, glass, world)
    })

    test(`YOU with ${tag}: the page is flat, levels over one panel of ships and captains, nothing removed`, async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await checkYou(page, glass, world)
    })
  }
}

// THE OWNER PLAYS IN KOREAN: the words are shorter and break by word, so the veteran's two screens are walked in his language on
// the narrowest glass the repo measures — the place a cut name and a wrapped line show first.
test.describe('in Korean', () => {
  test.use({ locale: 'ko-KR' })
  test(`FLEETS with ${VETERAN_HULLS} hulls at 320×640: the page is flat, every law holds`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await checkFleets(page, GLASSES[1], 'veteran', true)
  })
  test(`YOU with ${VETERAN_HULLS} hulls at 320×640: the page is flat, every law holds`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await checkYou(page, GLASSES[1], 'veteran', true)
  })
})

test('a press on a fleet opens her page and nothing behind it moves; Back leaves the panel as it was', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, GLASSES[0], 'veteran', 'fleets', 'fleets')
  await expect(page.getByTestId('fleet-row')).toHaveCount(VETERAN_HULLS)
  const boxes = async () =>
    page.evaluate(() => {
      const r = (e: Element | null) => (e ? JSON.stringify(e.getBoundingClientRect().toJSON()) : null)
      return {
        panel: r(document.querySelector('[data-testid="fleets-list"]')),
        first: r(document.querySelectorAll('[data-testid="fleet-row"]')[0] ?? null),
        second: r(document.querySelectorAll('[data-testid="fleet-row"]')[1] ?? null),
        scroll: (document.querySelector('[data-list-body]') as HTMLElement).scrollTop,
      }
    })
  const before = await boxes()
  await page.getByTestId('fleet-row').first().click()
  await expect(page.getByTestId('fleet-page')).toBeVisible()
  expect(await boxes(), 'a press on a fleet moved the panel or its rows').toEqual(before)
  await page.locator('[data-detail-back]').last().click()
  await expect(page.getByTestId('fleet-page')).toHaveCount(0)
  expect(await boxes(), 'closing her page moved the panel or its rows').toEqual(before)
})

// ── U5: A NAME IS NEVER CUT TO NOTHING, AND ONE THE GLASS DOES CUT IS READ BY A PRESS ────────────────────────────────────────────
// A fleet's name stands on the line with where she is. In port that is one short word; AT SEA it is "to Cape St Vincent · 22s", and
// beside it the name was left 16 px at 320×640 and 76 px at 390×844 — a cut with nothing left to read or press. The row's label now
// WRAPS: the two stand on one line while they fit, and when they do not the where line drops under the name.
test('FLEETS: the longest fleet name the chain allows stands whole at 320×640, the where line under it', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, GLASSES[1], 'veteran', 'fleets', 'fleets')
  const row = page.getByTestId('fleet-row').filter({ hasText: 'Nossa Senhora da Estrela' })
  await expect(row).toHaveCount(1)
  const name = row.locator('.truncate').first()
  expect(await name.evaluate((el) => el.scrollWidth > el.clientWidth + 1), 'the 24-character name is cut at 320').toBe(false)
  const stack = await row.evaluate((el) => {
    const label = el.querySelector('[data-row-cell="label"]')!
    const [nameBox, whereBox] = [...label.firstElementChild!.children].map((c) => c.getBoundingClientRect())
    return { nameBottom: nameBox.bottom, whereTop: whereBox.top, whereText: (label.firstElementChild!.children[1].textContent ?? '').trim() }
  })
  expect(stack.whereText, 'the where line is gone').not.toBe('')
  expect(stack.whereTop, 'the where line is not under the long name').toBeGreaterThanOrEqual(stack.nameBottom - 1)
})

/** Send the first fleet the map offers to the harbour nearest the chart's centre, through the map's own flow (tests/map.sendfleet.spec.ts). */
async function sendToSea(page: Page): Promise<void> {
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-chart"]', { timeout: 60_000 })
  await page.waitForTimeout(1500)
  const at = await page.evaluate(() => {
    const chart = document.querySelector('[data-testid="map-chart"]')?.getBoundingClientRect()
    if (!chart) return null
    const cx = chart.left + chart.width / 2
    const cy = chart.top + chart.height / 2
    let best: { x: number; y: number; d: number } | null = null
    for (const e of document.querySelectorAll('[data-testid="map-ports"] [data-port-code]')) {
      const r = e.getBoundingClientRect()
      const x = r.x + r.width / 2
      const y = r.y + r.height / 2
      if (r.width <= 0 || x < chart.left + 40 || x > chart.right - 40 || y < chart.top + 90 || y > chart.bottom - 70) continue
      const d = Math.hypot(x - cx, y - cy)
      if (d < 25) continue // the home harbour, where she lies
      if (!best || d < best.d) best = { x, y, d }
    }
    return best
  })
  expect(at, 'no harbour on the chart to sail to').not.toBeNull()
  await page.mouse.click(at!.x, at!.y)
  await page.waitForTimeout(900)
  await page.locator('[data-testid="map-send-fleet"]').click({ timeout: 8000 })
  await page.waitForTimeout(700)
  await page.locator('[data-testid="map-send-row-head"]').first().click({ timeout: 6000 })
  await page.waitForTimeout(1500)
  await page.locator('[data-testid="map-send-ratio-send"]').click({ timeout: 6000 })
  await page.waitForTimeout(3500)
}

test('FLEETS: a fleet AT SEA keeps her name whole at 320×640, with where she is bound under it, and the page stays flat', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[1])
  await WORLDS.veteran.serve(page)
  await sendToSea(page)
  // the app's own navigation, not a reload: the voyage lasts seconds in this world and a reload would only re-read it
  await page.evaluate(() => {
    history.pushState({}, '', '/byeharu-voyage/fleets')
    dispatchEvent(new PopStateEvent('popstate'))
  })
  await expect(page.getByTestId('fleets-list')).toBeVisible()
  await expect(page.getByTestId('fleet-row')).toHaveCount(VETERAN_HULLS)
  // the row whose where line says she is BOUND somewhere ("to Cape St Vincent · 22s"), found by that line's own box: the row's TEXT runs the
  // name and the where line together ("Boa Esperançato Cape…"), so a word-boundary match on the row would miss her
  const atSea = () =>
    page.getByTestId('fleet-row').evaluateAll((rows) =>
      rows.flatMap((r, i) => ((r.querySelector('[data-row-cell="label"]')?.firstElementChild?.children[1]?.textContent ?? '').trim().startsWith('to ') ? [i] : [])),
    )
  await expect.poll(atSea, { message: 'no fleet is at sea — the voyage was not sent, or she has already arrived', timeout: 15_000 }).toHaveLength(1)
  const sailing = page.getByTestId('fleet-row').nth((await atSea())[0])
  const name = sailing.locator('.truncate').first()
  expect(await name.evaluate((el) => el.scrollWidth > el.clientWidth + 1), 'her name is cut beside where she is bound').toBe(false)
  expect(await name.evaluate((el) => el.clientWidth), 'her name is a few pixels wide').toBeGreaterThan(60)
  const m = await readGlass(page, 'fleets-list', 'fleet-row', '[data-sheet]')
  const failures: string[] = []
  flat(m, 'FLEETS at sea at 320×640', failures)
  expect(failures, 'a fleet at sea broke the page').toEqual([])
})

// A NAME THE GLASS DOES CUT IS READ BY A PRESS, on a glass with no hover (which has no `title` to hover over): `Clip`
// (src/components/ui/Clip.tsx) opens the full name IN PLACE as a layer over the cell. A captain's row is PRESSABLE, and her name is
// cut at every phone glass (47 characters): a press on the cut name must read it and must not open her tray.
test.describe('a cut name is read in place by a press', () => {
  test.use({ hasTouch: true, isMobile: true })

  test("YOU: a captain's long name is cut at 320×640, a press reads it whole and opens no tray", async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    const full = 'Ana Maria da Conceição Fernandes de Albuquerque'
    await open(page, GLASSES[1], 'veteran', 'you', 'you')
    const touch = await page.evaluate(() => window.matchMedia('(hover: none)').matches)
    expect(touch, 'the context is not a touch glass — press-to-read cannot be proved').toBe(true)
    await expect(page.getByTestId('your-captain')).toHaveCount(VETERAN_CAPTAINS)
    const name = page.locator('[data-testid="your-captain"] .truncate').filter({ hasText: full })
    await name.scrollIntoViewIfNeeded()
    expect(await name.evaluate((el) => el.scrollWidth > el.clientWidth + 1), 'the long name is not cut at 320 — the proof is vacuous').toBe(true)
    await name.tap()
    const layer = page.getByTestId('clip-full')
    await expect(layer).toBeVisible()
    await expect(layer).toHaveText(full)
    await expect(page.getByTestId('your-captain-tray'), 'reading a cut name opened her tray').toHaveCount(0)
    await page.keyboard.press('Escape')
    await expect(layer).toHaveCount(0)
  })
})

test('a press on a captain opens her tray, outside the panel; closing it leaves the panel as it was', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, GLASSES[0], 'veteran', 'you', 'you')
  await expect(page.getByTestId('your-captain')).toHaveCount(VETERAN_CAPTAINS)
  const panel = async () => JSON.stringify(await page.getByTestId('you-list').boundingBox())
  const before = await panel()
  // the first captain's row may stand below the fold of the panel; a press brings it into view the way a player's scroll does
  await page.getByTestId('your-captain').first().click()
  const tray = page.getByTestId('your-captain-tray')
  await expect(tray).toBeVisible()
  expect(await tray.evaluate((el) => el.closest('[data-list-panel]') !== null), 'the captain tray stands inside the panel and its scroller').toBe(false)
  expect(await page.evaluate(() => document.documentElement.scrollHeight <= document.documentElement.clientHeight + 1), 'opening her tray scrolled the page').toBe(true)
  expect(await panel(), 'opening her tray moved the panel').toEqual(before)
  await tray.getByRole('button', { name: /close/i }).first().click()
  await expect(tray).toHaveCount(0)
  expect(await panel(), 'closing her tray moved the panel').toEqual(before)
})
