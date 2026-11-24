// BROWSER MEASUREMENT SPEC — the one proof that no data is hidden on a phone.
//
// This is the only spec in the repo that needs a real viewport, and it exists because the defect
// it catches is invisible to every other kind of check: the page reported
// `scrollWidth === clientWidth === 390` — perfectly "no horizontal page scroll" — while the
// ENDURANCE column of the fleet roster was sheared off the right edge and the header rendered as a
// bare "E". A green page-scroll assertion was the CAMOUFLAGE for hidden data.
//
// THE ASSERTION, per table, in the words of the rule it enforces:
//   1. Either the table FITS its container, or the container is genuinely scrollable
//      (overflow-x auto/scroll AND scrollWidth > clientWidth). Clipping is neither.
//   2. Scrolled to the far end, the LAST cell of every row is fully inside the container. This is
//      what "reachable" actually means, and it is what a bare overflow rule does not guarantee.
//   3. Scrolled to the far end, the FIRST cell of every body row is still on screen — the row's
//      identity and its tap target. That is the reach law applied to a scroll container.
//   4. The page itself still never moves sideways.
//
// HOW TO RUN IT. It needs the app served:
//     npm run build && npm run preview        (or: npm run dev, then set the base URL)
//     npx playwright test layout.spec.ts
// Point it elsewhere with PLAYWRIGHT_BASE_URL (see playwright.config.ts).
//
// If nothing is served the tests SKIP with a stated reason rather than pass — a skip is visibly a
// skip, and a proof that goes green without measuring anything is worse than no proof at all.
//
// RUN IN CI SINCE 2026-08-22: .github/workflows/acceptance.yml installs a chromium, builds, serves
// the build and runs this suite against it. This comment used to say the opposite — "NOT RUN IN
// CI … this is a local gate" — which was true of `build.yml` (lint + tsc + vite build, no browser
// binaries) and is no longer true of the repo.
//
// THE SKIPS ARE WHY THAT WORKFLOW HAS A NON-VACUITY FLOOR. Every skip in this file (below, and at
// the two guards further down) fires on "nothing is being served" or "this is a cloud build and it
// redirected to /auth" — precisely the two states that would let a green tick measure no pixels at
// all. acceptance.yml therefore fails the job if ANY test skipped, or if zero passed, in the same
// spirit as migrations-apply-proof.yml requiring every declared PASS marker to actually appear.

import { test, expect } from '@playwright/test'
// The phone viewport, the served-anything probe and the boot wait live in ONE place now
// (tests/appReady.fixture.ts) because a second browser spec — nav.geometry — needs exactly the
// same three, and two copies of `ready()` would drift apart in silence. The reasoning that used to
// sit inline here travelled with them; nothing about it changed.
import { PHONE, reachable, ready, settled } from './appReady.fixture'
import { openFleetSheet, openMarket, openPlate, tradeOnDesk } from './desk.fixture'

// 'rank' joined the list 2026-08-23, when 0025 gave that tab a wide table to draw. It was the only
// tab carrying a scrolling table that this guard did not measure, which is the combination the guard
// exists for — a table 469px wide in a 332px box is fine, and a table 469px wide with a button
// inside the scrolled region is the reach-law break this file catches.
//
// STILL ABSENT, and not by oversight: 'map' draws an SVG chart with no table and no text rows, so
// every assertion here would pass vacuously on it; 'profile' is the auth surface and redirects on a
// cloud build, which is one of the two skip states the header above says must never go unnoticed.
// 'compendium' joined 2026-08-23, the day the tab shipped — with three scrolling tables (goods,
// ships, nations) it is exactly the combination this guard exists for, and 'rank' had to be added
// AFTER its screen shipped because this list was not grown in the same slice. Not this time.
// 'market' LEFT 2026-09-11: the tab folded into PORT (owner row 76, docs/QUAY_LEDGER.md), whose
// entry below now measures what MARKET's used to.
// 'command' and 'port' LEFT 2026-11-24 (H3 `desk-into-hq`): both routes open HQ ('city'), which is measured in their place.
const TABS = ['city', 'fleets', 'ledger', 'rank', 'compendium'] as const

test.use({ viewport: PHONE })

interface TableReport {
  index: number
  visible: boolean
  fits: boolean
  scrollable: boolean
  /** How far the last cell still sticks out AFTER scrolling to the end. Must be <= 0. */
  lastCellOverhangAtEnd: number
  /** Whether every body row's first cell is still on screen at full scroll. */
  firstCellStaysOnScreen: boolean
  /** Cells whose value is allowed to break across lines — the crushed-column signature. */
  wrappingCells: number
  /** Headers rendered narrower than their own text. */
  clippedHeaders: string[]
  headers: string[]
}


for (const tab of TABS) {
  test(`${tab}: every table is fully readable at ${PHONE.width}px`, async ({ page, request, baseURL }) => {
    // The boot dominates (see ready()); the measurement itself is seconds.
    test.setTimeout(420_000)
    test.skip(
      !(await reachable(request, baseURL ?? '')),
      `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
    )

    await page.goto(tab)
    await ready(page)

    const report = await page.evaluate((): { pageScrollW: number; pageClientW: number; tables: TableReport[]; measurables: number } => {
      const tables: TableReport[] = []
      document.querySelectorAll('table').forEach((table, index) => {
        // A table hidden at this breakpoint (the roster's `hidden sm:block` variant) is not
        // rendered and has nothing to measure. Its stacked replacement IS measured, as markup.
        if (table.getClientRects().length === 0) {
          tables.push({
            index, visible: false, fits: true, scrollable: false,
            lastCellOverhangAtEnd: 0, firstCellStaysOnScreen: true, headers: [],
            wrappingCells: 0, clippedHeaders: [],
          })
          return
        }
        const box = table.parentElement as HTMLElement
        const style = getComputedStyle(box)
        const fits = table.getBoundingClientRect().width <= box.clientWidth + 1
        const scrollable = /auto|scroll/.test(style.overflowX) && box.scrollWidth > box.clientWidth

        // 1b. NOT CRUSHED. This is the assertion the original defect actually needed, and the one
        //     a bare overflow rule misses: with `w-full` the table was pinned to the box, every
        //     column squeezed to min-content, and values broke mid-figure ("4.1 / t",
        //     "→ Las / Palmas") — while still overflowing by 31px. Reachability alone said that was
        //     fine, because the sheared column WAS behind a scroll. It was not fine: the figures
        //     were mangled. A cell in a scroll-managed table renders its value on one line or the
        //     table is not doing its job.
        const cells = [...table.querySelectorAll('th,td')].filter((c) => !c.hasAttribute('colspan'))
        const wrappingCells = cells.filter((c) => getComputedStyle(c).whiteSpace !== 'nowrap').length
        // A header must also never be shaved: with nowrap, a clipped <th> overflows its own box.
        const clippedHeaders = [...table.querySelectorAll('th')]
          .filter((th) => th.scrollWidth > th.clientWidth + 1)
          .map((th) => th.textContent ?? '')

        const before = box.scrollLeft
        box.scrollLeft = box.scrollWidth // as far right as it goes
        const rect = box.getBoundingClientRect()
        const lastCells = [...table.querySelectorAll('tr')]
          .map((tr) => tr.lastElementChild)
          .filter((c): c is Element => c !== null)
        const lastCellOverhangAtEnd = Math.round(
          Math.max(...lastCells.map((c) => c.getBoundingClientRect().right - rect.right)),
        )
        const firstCells = [...table.querySelectorAll('tbody tr')]
          .map((tr) => tr.firstElementChild)
          .filter((c): c is Element => c !== null && !c.hasAttribute('colspan'))
        const firstCellStaysOnScreen = firstCells.every((c) => {
          const r = c.getBoundingClientRect()
          return r.left >= rect.left - 1 && r.left < rect.right
        })
        box.scrollLeft = before

        tables.push({
          index, visible: true, fits, scrollable, lastCellOverhangAtEnd, firstCellStaysOnScreen,
          wrappingCells, clippedHeaders,
          headers: [...table.querySelectorAll('th')].map((th) => th.textContent ?? ''),
        })
      })
      // WHAT COUNTS AS "THIS SCREEN RENDERED SOMETHING". Tables were the only measurable thing
      // when this spec was written; goods and harbours are TILES now, and a tile-only screen must
      // not read as an empty one. Both are counted, plus the nav rail, which every real screen of
      // this app carries and vite's 404 helper does not.
      const tiles = document.querySelectorAll('[data-good-tile], [role="tabpanel"] a, nav a').length
      return {
        pageScrollW: document.documentElement.scrollWidth,
        pageClientW: document.documentElement.clientWidth,
        tables,
        measurables: tables.length + tiles,
      }
    })

    // 3b. NON-VACUITY — THIS SPEC COULD PASS WHILE MEASURING NOTHING, AND DID.
    //     Found 2026-08-23 by an audit agent: point `PLAYWRIGHT_BASE_URL` at a bare host with no
    //     `/byeharu-voyage/` base and vite preview answers every path with its own "did you mean"
    //     page. That page has no tables, no tiles and no skeletons — so `ready()` resolves, the
    //     table loop finds nothing to walk, the sideways-scroll check passes on a page with no
    //     content, and ALL EIGHT TESTS GO GREEN having measured a 404 helper.
    //
    //     The header above already says why every skip in this file has a floor: a green tick that
    //     measured no pixels is worse than a red one. That reasoning was applied to `test.skip` and
    //     not to the body, which is exactly the gap. A guard that cannot fail is not a guard
    //     (docs/NO_SPAGHETTI.md §8 q7), so the spec now proves it FOUND something before it
    //     believes anything it did not find.
    expect(
      report.measurables,
      `${tab} rendered nothing measurable — no table and no tile. If PLAYWRIGHT_BASE_URL is set, ` +
        `check it carries the /byeharu-voyage/ base; a bare host serves vite's "did you mean" page, ` +
        `which passes every other assertion here by having no content at all.`,
    ).toBeGreaterThan(0)

    // 4. The page never moves sideways — necessary, but on its own it is the camouflage, so it is
    //    asserted LAST and never alone.
    expect(report.pageScrollW).toBeLessThanOrEqual(report.pageClientW)

    for (const t of report.tables) {
      if (!t.visible) continue
      const where = `${tab} table#${t.index} [${t.headers.join('|')}]`
      // 1. fits, or genuinely scrolls. Never clipped.
      expect(t.fits || t.scrollable, `${where} is neither narrow enough to fit nor scrollable — it is CLIPPED`).toBe(true)
      // 1b. never crushed: no value may be broken across lines to make the table fit
      expect(
        t.wrappingCells,
        `${where} lets ${t.wrappingCells} cells wrap — the columns are being crushed to fit instead of scrolling`,
      ).toBe(0)
      expect(t.clippedHeaders, `${where} shaves its own column headers: ${t.clippedHeaders.join(', ')}`).toEqual([])
      // 2. the far column is reachable
      expect(t.lastCellOverhangAtEnd, `${where} still hides ${t.lastCellOverhangAtEnd}px of its last column at full scroll`).toBeLessThanOrEqual(1)
      // 3. the identity column, and its tap target, never scroll away
      expect(t.firstCellStaysOnScreen, `${where} scrolls its first column (the tap target) off screen`).toBe(true)
    }
  })
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CODEX'S LISTS STAND ON THE PAGE, ONE ENTRY A LINE ON A PHONE (the page slice, 2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// RETARGETED TWICE. This block used to hold the owner's 2026-08-23/26 GRID rule for the catalogue faces — *"i told
// trade goods to be in grid like shape - organized not in lines"* — as `maxPerRow ≥ 2` and `tileWidth < 220`.
// The owner has spoken since, three times: 2026-10-31 (*"make everything small, compact and once clicked show new
// page popping up"*, which put the whole catalogue behind one `Goods 629 · Open` row); 2026-11-01 (*"everything
// is folded … make things unfolded, minimize scrolling, everything compact with full info"*, row 260 and
// docs/dev-log/2026-11-01-ui-unfold.md U1: a list is on the screen, not behind a press), which made the faces ONE
// `ListPanel` of `Row`s scrolling inside the glass with N rows whole before a press; and 2026-11-02 (row 267, *"it looks
// so wrong. The past was better. right now everything is on left, too packed. this was a mistake"*), which reverses
// the packing: the face is a PAGE (Sheet layout="page"; docs/dev-log/2026-11-02-codex-design.md), its list a CARD that
// holds every entry and scrolls nowhere inside itself — the page scrolls. So the two glass-fit assertions of the unfold
// slice ("the panel stands inside the glass", "N rows whole before a press") are gone — they held the packing — and what
// stays is strengthened: EVERY entry stands whole in the card's body (not N of them), the body is not a scroller, an
// entry is one a line on a phone and as wide as the card's body, and the page does not shear sideways. It cannot be
// satisfied by a wrapper or a comment: the rows are measured against the card's own body. tests/codex.design.spec.ts
// holds the page's own laws (the glass used, the hierarchy, the side column, the tray over it) at five glasses.
const FIELDS = [
  { tab: 'compendium', face: 'Goods', testId: 'good-tile', noun: 'goods' },
  { tab: 'compendium', face: 'Ships', testId: 'ship-tile', noun: 'ship classes' },
  { tab: 'compendium', face: 'Captains', testId: 'officer-tile', noun: 'officers' },
] as const

/** HOW MANY ENTRIES STAND WHOLE IN THE PANEL, AND ON HOW MANY LINES. Self-contained on purpose: Playwright
 *  ships the source of this function into the page, so it may not reach anything outside itself (the same
 *  rule nav.geometry.spec.ts's MEASURE keeps). Entries are grouped by their top edge, which is what "on the
 *  same line" actually means — no class name, no container, no wrapper can fake it. */
const MEASURE_FIELD = (testId: string) => {
  const body = document.querySelector('[data-testid="codex-list"] [data-list-body]') as HTMLElement | null
  const tiles = [...document.querySelectorAll(`[data-testid="${testId}"]`)] as HTMLElement[]
  const perRow = new Map<number, number>()
  for (const t of tiles) {
    const top = Math.round(t.getBoundingClientRect().top)
    perRow.set(top, (perRow.get(top) ?? 0) + 1)
  }
  const b = body?.getBoundingClientRect()
  const whole = b ? tiles.filter((t) => t.getBoundingClientRect().top >= b.top - 1 && t.getBoundingClientRect().bottom <= b.bottom + 1).length : 0
  const first = tiles[0]?.getBoundingClientRect()
  return {
    // the card's body holds its rows and scrolls nowhere inside itself (the page scrolls — 2026-11-02, row 267)
    bodyScroll: body === null ? null : { sh: body.scrollHeight, ch: body.clientHeight },
    tiles: tiles.length,
    whole,
    maxPerRow: perRow.size === 0 ? 0 : Math.max(...perRow.values()),
    rows: perRow.size,
    tileWidth: first ? Math.round(first.width) : 0,
    tileHeight: first ? Math.round(first.height) : 0,
    bodyWidth: b ? Math.round(b.width) : 0,
    pageScrollW: document.documentElement.scrollWidth,
    pageClientW: document.documentElement.clientWidth,
  }
}

for (const field of FIELDS) {
  test(`COMPENDIUM ${field.face}: ${field.noun} stand on the glass, one a line, no press, at ${PHONE.width}px`, async ({
    page,
    request,
    baseURL,
  }) => {
    test.setTimeout(420_000)
    test.skip(
      !(await reachable(request, baseURL ?? '')),
      `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
    )
    await page.goto(field.tab)
    await ready(page)
    await page.getByRole('tab', { name: new RegExp(`^${field.face}`, 'i') }).first().click()
    await page.waitForTimeout(500)

    const report = await page.evaluate(MEASURE_FIELD, field.testId)
    console.log(`${field.face} @${PHONE.width}px: ${JSON.stringify(report)}`)

    // NON-VACUITY, the floor every check in this file carries: a face that rendered nothing would
    // pass "no entry is on a line of its own" by having no entries.
    expect(report.tiles, `no [data-testid="${field.testId}"] found — did the face render?`).toBeGreaterThan(1)
    // THE LAW (2026-11-02, row 267): the list is a card on the page that holds EVERY entry whole and scrolls nowhere inside itself.
    expect(report.bodyScroll, 'the face has no list card').not.toBeNull()
    expect(report.bodyScroll!.sh, `the card's body scrolls inside itself (${report.bodyScroll!.sh} in ${report.bodyScroll!.ch} px) — the page scrolls, a list never does`).toBeLessThanOrEqual(report.bodyScroll!.ch + 1)
    expect(report.whole, `${report.whole} of ${report.tiles} ${field.noun} stand whole in the card — every one must`).toBe(report.tiles)
    // THE HONEST OPPOSITES of the old grid assertions: one entry a line on a phone, as wide as the card's body.
    expect(report.maxPerRow, `${field.noun} stand ${report.maxPerRow} to a line — a row is one`).toBe(1)
    expect(report.tileWidth, `a row is ${report.tileWidth}px of a ${report.bodyWidth}px card body`).toBeGreaterThanOrEqual(report.bodyWidth - 28)
    expect(report.pageScrollW, 'the page shears sideways').toBeLessThanOrEqual(report.pageClientW)
  })
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// FLEETS — a fleet row opens her page, and the list behind it does not move
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE FLEET'S PAGE (owner, 2026-10-31: *"everything has folded. enough with folding things. make
// everything small, compact and once clicked show new page popping up. this is wrong"*). Row 89's
// unfold-under-the-row is RETIRED: it re-flowed every row below the press, and a press may not
// re-flow what follows it. A press now opens the one `DetailPage` — a fixed overlay with a back
// press — holding the three sections row 89 asked for (Ships · Cargo · Supplies, stacked on a
// phone). The list behind it is measured to the pixel: the header, the pressed row AND the row
// below keep their boxes.
test(`FLEETS: a fleet row opens her page, nothing behind it moves at ${PHONE.width}px, and the back press returns`, async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('fleets')
  await ready(page)
  await page.waitForTimeout(600)

  const rows = page.locator('[data-testid="fleet-row"]')
  expect(await rows.count(), 'no fleet rows — did the world found a company with a fleet?').toBeGreaterThan(0)
  await expect(page.locator('[data-testid="fleet-page"]'), 'a fleet page is standing before anything was pressed').toHaveCount(0)

  // Everything AT OR ABOVE the press: the sheet's title and the first row, by viewport rect. The
  // sheet's box does not scroll on a press, so viewport rects are the sheet's own offsets here.
  const ABOVE = () => {
    const rect = (el: Element | null) => {
      if (!el) return null
      const r = el.getBoundingClientRect()
      return { left: Math.round(r.left), top: Math.round(r.top), width: Math.round(r.width), height: Math.round(r.height) }
    }
    return {
      header: rect(document.querySelector('[data-testid="sheet-header"]')),
      row: rect(document.querySelector('[data-testid="fleet-row"]')),
      // THE ROW BELOW is the witness the old unfold could not pass: it moved down by the fold's
      // height. An overlay is out of flow, so it may not move at all.
      next: rect(document.querySelectorAll('[data-testid="fleet-row"]')[1] ?? null),
    }
  }
  const before = await page.evaluate(ABOVE)
  expect(before.row, 'the first fleet row has no box').not.toBeNull()

  // 1. PRESS THE ROW. HER PAGE OPENS, and the list behind it does not move — not the row, not the
  //    title, and not the row BELOW it (which an unfold used to push down).
  await rows.first().click()
  const fleetPage = page.getByTestId('fleet-page')
  await expect(fleetPage).toBeVisible()
  await page.waitForTimeout(600)
  const after = await page.evaluate(ABOVE)
  expect(after, 'pressing a fleet row MOVED the list behind it — a page must overlay, never re-flow').toEqual(before)
  const pageRoot = await fleetPage.evaluate((el) => ({ h: (el as HTMLElement).scrollHeight, ch: (el as HTMLElement).clientHeight }))
  expect(pageRoot.h, `the fleet page itself scrolls: ${pageRoot.h} > ${pageRoot.ch}`).toBeLessThanOrEqual(pageRoot.ch + 1)
  const fold = fleetPage.locator('[data-testid="fleet-fold"]')
  await expect(fold).toBeVisible()

  // 2. TWO STEPS (owner, 2026-11-14: "when pressed a fleet, show only ships, then when i press the ship, show cargo and supplies"). The fleet's page
  //    carries her ships as rows and no section; a ship's row opens HER page, where Cargo and Supplies are stacked on a phone: same left edge, each
  //    top at or below the previous bottom, inside the page.
  await expect(fold.locator('[data-testid="fleet-fold-section"]')).toHaveCount(0)
  await expect(fold.locator('[data-testid="fleet-stores-days"]')).toHaveCount(0)
  await fold.locator('[data-testid="fleet-ship-row"]').first().click()
  const shipPage = page.getByTestId('fleet-ship-page')
  await expect(shipPage).toBeVisible()
  await page.waitForTimeout(600)
  const geometry = await shipPage.evaluate((el) => {
    const r = (n: Element) => n.getBoundingClientRect()
    return {
      left: Math.round(r(el).left),
      right: Math.round(r(el).right),
      sections: [...el.querySelectorAll('[data-testid="fleet-fold-section"]')].map((s) => ({
        heading: (s.querySelector('h2')?.textContent ?? '').trim(),
        left: Math.round(r(s).left),
        right: Math.round(r(s).right),
        top: Math.round(r(s).top),
        bottom: Math.round(r(s).bottom),
      })),
      pageScrollW: document.documentElement.scrollWidth,
      pageClientW: document.documentElement.clientWidth,
    }
  })
  console.log(`FLEETS page @${PHONE.width}px: ${JSON.stringify(geometry)}`)
  expect(geometry.sections.map((s) => s.heading)).toEqual(['Cargo', 'Supplies'])
  for (let i = 1; i < geometry.sections.length; i++) {
    const above = geometry.sections[i - 1]
    const here = geometry.sections[i]
    expect(here.top, `${here.heading} is not under ${above.heading} — the sections are not stacked on a phone`).toBeGreaterThanOrEqual(above.bottom)
    expect(here.left, `${here.heading} does not share ${above.heading}'s left edge`).toBe(above.left)
  }
  for (const s of geometry.sections) {
    expect(s.left, `${s.heading} starts left of the page`).toBeGreaterThanOrEqual(geometry.left)
    expect(s.right, `${s.heading} runs past the page's right edge`).toBeLessThanOrEqual(geometry.right)
  }
  expect(geometry.pageScrollW, 'the page shears sideways').toBeLessThanOrEqual(geometry.pageClientW)

  // 3. WHAT THE PAGE CARRIES: the supplies as one line (owner row 203 / 0225: no keep control), and the one
  //    hand-off at the foot. Every control on it clears the 44px reach floor.
  await expect(shipPage.locator('[data-testid="fleet-stores-days"]')).toBeVisible()
  await expect(shipPage.locator('[data-testid="fleet-keep-stepper"]')).toHaveCount(0)
  await expect(shipPage.locator('[data-testid="fleet-keep"]')).toHaveCount(0)
  const SHORT = (el: Element) =>
    [...el.querySelectorAll('button')]
      .map((b) => ({ text: (b.innerText || b.getAttribute('aria-label') || '').slice(0, 24), r: b.getBoundingClientRect() }))
      .filter(({ r }) => r.width > 0 && r.height > 0 && (r.width < 44 || r.height < 44))
      .map(({ text, r }) => `${text} ${Math.round(r.width)}×${Math.round(r.height)}`)
  expect(await shipPage.evaluate(SHORT), "a control on the ship's page is under the 44px reach floor").toEqual([])
  await shipPage.locator('[data-detail-back]').click()
  await expect(shipPage).toHaveCount(0)
  expect(await fold.evaluate(SHORT), "a control on the fleet's page is under the 44px reach floor").toEqual([])
  // the hand-off is the fleet's, one row further (the More page)
  await fold.locator('[data-testid="fleet-more"]').click()
  const morePage = page.getByTestId('fleet-more-page')
  await expect(morePage.locator('[data-testid="fleet-command"]')).toBeVisible()
  expect(await morePage.evaluate(SHORT), 'a control on the More page is under the 44px reach floor').toEqual([])
  await morePage.locator('[data-detail-back]').click()
  await expect(morePage).toHaveCount(0)


  // 5. THE BACK PRESS CLOSES THE PAGE. It is gone from the DOM, and the list behind it is untouched.
  await page.locator('[data-detail-back]').last().click()
  await expect(page.locator('[data-testid="fleet-page"]')).toHaveCount(0)
  await page.waitForTimeout(400)
  expect(await page.evaluate(ABOVE), 'closing the page moved the list').toEqual(before)
})

// 0092 (owner row 106): the route row stands ABOVE the queue (in her sheet over HQ since H3, 2026-11-24; it stood on the desk). Since the consistency audit
// (row 38) the press opens THE ROUTE'S PAGE — the one `DetailPage`, fixed OVER the desk and out of
// flow by construction — where it used to unfold in place. The owner's law is the stronger one the
// fold could never keep: a press selects and opens, and NOTHING behind it moves — the row AND the
// queue below it keep their boxes to the pixel. The local build ships with routes DARK, so the
// page's whole content here is the one line that says so; the mechanism is the same page.
test(`HER SHEET: the route row opens the route page, the queue below it may not move, and Back returns`, async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('city')
  await ready(page)
  // the route and the queue are in her sheet (her HQ row's press); its reads land before anything is measured
  await settled(await openFleetSheet(page))
  // an order in the queue, so there is a row below the route to hold still: none is needed — the sheet's Map row stands below it
  const row = page.getByTestId('route-row')
  await expect(row).toBeVisible()
  // The route book has landed (the label names what it read), so no late text moves the row.
  await expect(row).toContainText(/Not open yet|No route|Route ·/)
  // the route stands with the orders at the foot of the Buy face (below the map and the city's goods), so
  // the sheet is brought to it FIRST — the press itself must then scroll nothing (a scroll would read as a move).
  await row.scrollIntoViewIfNeeded()
  await page.waitForTimeout(400)

  const MEASURE = () => {
    const rect = (sel: string) => {
      const el = document.querySelector(sel)
      if (!el) return null
      const r = el.getBoundingClientRect()
      return { left: Math.round(r.left), top: Math.round(r.top), width: Math.round(r.width), height: Math.round(r.height) }
    }
    return {
      header: rect('[data-testid="hq-sheet-fleet"] h1'),
      line: rect('[data-testid="trade-status"]'),
      row: rect('[data-testid="route-row"]'),
      queue: rect('[data-testid="hq-sheet-fleet-map"]'),
      page: rect('[data-testid="route-page"]'),
      pageScrollW: document.documentElement.scrollWidth,
      pageClientW: document.documentElement.clientWidth,
      rootSh: (document.querySelector('[data-testid="route-page"]')?.closest('[data-detail-page]') as HTMLElement | null)?.scrollHeight ?? 0,
      rootCh: (document.querySelector('[data-testid="route-page"]')?.closest('[data-detail-page]') as HTMLElement | null)?.clientHeight ?? 0,
    }
  }
  const before = await page.evaluate(MEASURE)
  console.log(`COMMAND route row @${PHONE.width}px before the press: ${JSON.stringify(before)}`)
  expect(before.row, 'no route row').not.toBeNull()
  expect(before.queue, 'no queue section').not.toBeNull()
  expect(before.page, 'a route page stands before anything was pressed').toBeNull()
  expect(before.row!.top + before.row!.height, 'the route row is not ABOVE the queue').toBeLessThanOrEqual(before.queue!.top)

  // 1. PRESS: the route's page is up; the header, the row and — the new law — the QUEUE BELOW it do
  //    not move by a pixel; the page's root does not scroll; the document never scrolls sideways.
  await row.click()
  await expect(page.getByTestId('route-page')).toBeVisible()
  await page.waitForTimeout(400)
  const open = await page.evaluate(MEASURE)
  console.log(`COMMAND route page @${PHONE.width}px: ${JSON.stringify(open)}`)
  expect({ header: open.header, line: open.line, row: open.row, queue: open.queue }, 'the press MOVED the row or the queue below it').toEqual({
    header: before.header,
    line: before.line,
    row: before.row,
    queue: before.queue,
  })
  expect(open.rootSh, 'the page root scrolls — its body is the one scroller').toBeLessThanOrEqual(open.rootCh + 1)
  expect(open.pageScrollW).toBeLessThanOrEqual(open.pageClientW)

  // 2. BACK: the page is gone and nothing behind it has moved.
  await page.getByTestId('route-page').locator('[data-detail-back]').click()
  await expect(page.getByTestId('route-page')).toHaveCount(0)
  await page.waitForTimeout(400)
  const closed = await page.evaluate(MEASURE)
  expect(closed.queue).toEqual(before.queue)
  expect(closed.row).toEqual(before.row)
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PORT'S REQUEST BOARD — the third face of the trade board: rows shaped like the ledger, a Fulfil
// cell that is dead with its reason, and turning a face moves nothing above the board
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ADDED 2026-09-14 with slice 4 of the Quay Ledger (docs/QUAY_LEDGER.md §3 F, migration 0087;
// owner row 76). The trade board carries `Segmented` Buy · Sell · Requests. Requests lists what
// this port asks for — goods it does NOT sell — one row per request: the good, `N units · ends in
// …` (the calendar clock, printed like the fair's end), `+P% over market · have / need units
// on board`, and ONE cell `fulfil` carrying the served premium. The fixture fleet carries nothing
// of what its port asks for BY THE RULE (a port never asks for what it sells, and the only way to
// carry a good this port does not sell is to have brought it), so on this proof every cell is
// dead — and a dead cell says WHY on its own face, which is what tests/layout.spec.ts was written
// to stop going silent. The live press — the tray in the slot, the served preview, the premium
// line, the delivery — is proven end to end in tests/rpc.surface.spec.ts and 0087's self-assert,
// where the lot can be put aboard through the server's own mover.
test(`MARKET › Requests: the third face lists this port's requests as board rows, a dead fulfil cell says why, and turning faces moves nothing above the board`, async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  // H3 (2026-11-24): the board is HQ's Market plate (it was the Office's City face)
  await page.goto('city')
  await ready(page)
  await openMarket(page)

  // The three faces stand in one strip, Buy up first, and the goods are under it.
  const faces = page.getByRole('tablist', { name: 'Market', exact: true })
  await expect(faces).toBeVisible()
  await expect(faces.getByRole('tab')).toHaveText(['Buy', 'Sell', 'Requests'])
  const goods = page.locator('[data-testid="city-face-panel"] [data-testid="trade-good"]')
  await expect(goods.first()).toBeVisible({ timeout: 60_000 })
  expect(await goods.count()).toBeGreaterThan(1)

  // Everything AT OR ABOVE the board: the sheet's title, the supplies row, the port field, the
  // faces strip. By viewport rect — a face turn does not scroll the sheet.
  const ABOVE = () =>
    page.evaluate(() => {
      const rect = (el: Element | null) => {
        if (!el) return null
        const r = el.getBoundingClientRect()
        return { left: Math.round(r.left), top: Math.round(r.top), width: Math.round(r.width), height: Math.round(r.height) }
      }
      return {
        header: rect(document.querySelector('[data-testid="city-header"]')),
        places: rect(document.querySelector('[data-testid="city-buildings"]')),
        field: rect(document.querySelector('[data-testid="city-chips"]')),
        faces: rect(document.querySelector('[role="tablist"][aria-label="Market"]')),
      }
    })
  const before = await ABOVE()
  expect(before.faces, 'the faces strip has no box').not.toBeNull()

  // TURN TO REQUESTS. The board appears under the strip; nothing above it moved.
  await faces.getByRole('tab', { name: /^Requests$/ }).click()
  const rows = page.locator('[data-testid="request-row"]')
  await expect(rows.first(), 'no request rows — the board did not read, or this port posted nothing').toBeVisible({ timeout: 30_000 })
  await page.waitForTimeout(600)
  expect(await ABOVE(), 'turning to Requests MOVED what stands above the board').toEqual(before)
  await expect(goods).toHaveCount(0)

  const report = await page.evaluate(() => {
    const rows = [...document.querySelectorAll('[data-testid="request-row"]')] as HTMLElement[]
    const cells = [...document.querySelectorAll('[data-testid="request-fulfil"]')] as HTMLButtonElement[]
    const text = (el: HTMLElement) => (el.innerText || '').replace(/\s+/g, ' ').trim()
    return {
      rows: rows.length,
      rowsWithLot: rows.filter((r) => /On board [\d,]+ \/ [\d,]+/.test(text(r))).length, // 2026-11-15 owner: shorter words (HAVE / NEED)
      rowsWithPremium: rows.filter((r) => /Bonus [\d,.]+ 🪙 each · [\d,]+ 🪙 left/.test(text(r))).length,
      rowsWithShare: rows.filter((r) => /Time left (\d+ d )?(\d+:)?\d+:\d\d/.test(text(r))).length,
      cells: cells.length,
      shortestCell: cells.length ? Math.min(...cells.map((c) => c.getBoundingClientRect().height)) : 0,
      cellsSayingFulfil: cells.filter((c) => /^deliver\b/i.test(text(c))).length,
      cellsWithFigure: cells.filter((c) => /[+−]?[\d,]+\s🪙/.test(text(c))).length,
      deadCells: cells.filter((c) => c.disabled).length,
      deadSayingWhy: cells.filter((c) => c.disabled && /none on board|no ship here/.test(text(c))).length,
      rowWidth: rows[0] ? Math.round(rows[0].getBoundingClientRect().width) : 0,
      pageScrollW: document.documentElement.scrollWidth,
      pageClientW: document.documentElement.clientWidth,
      // A CELL NEVER RUNS PAST ITS ROW (2026-11-02): a dead `deliver` cell said "0 / 20 units on board" on ONE line, 15 px past its 112-px box
      // and the row's edge, and the pane scrolled sideways. Nothing inside a request row stands right of the row's own edge, and the pane the
      // rows stand in (the desk's board) does not scroll sideways.
      pastItsRow: rows.reduce((n, r) => n + [...r.querySelectorAll('*')].filter((e) => e.getBoundingClientRect().right > r.getBoundingClientRect().right + 1).length, 0),
      paneSideways: rows[0] ? (() => { const pane = rows[0].closest('[data-scroll-pane]'); return pane ? pane.scrollWidth - pane.clientWidth : 0 })() : 0,
    }
  })
  console.log(`PORT requests @${PHONE.width}px: ${JSON.stringify(report)}`)
  expect(report.rows).toBeGreaterThan(0)
  expect(report.rowsWithLot, 'a request row does not say what is wanted and held').toBe(report.rows)
  expect(report.rowsWithPremium, 'a request row does not say its bonus each and its budget left').toBe(report.rows)
  expect(report.rowsWithShare, 'a request row does not say its time left').toBe(report.rows)
  expect(report.cells, 'a request row does not carry exactly one cell').toBe(report.rows)
  expect(report.cellsSayingFulfil).toBe(report.rows)
  expect(report.cellsWithFigure, 'a fulfil cell carries no served price').toBe(report.rows)
  expect(report.shortestCell, 'a fulfil cell is under the 44px reach floor').toBeGreaterThanOrEqual(44)
  expect(report.deadSayingWhy, 'a dead fulfil cell went grey without saying why').toBe(report.deadCells)
  expect(report.rowWidth, 'a request row is not a board row').toBeGreaterThanOrEqual(300)
  expect(report.pageScrollW, 'the page shears sideways').toBeLessThanOrEqual(report.pageClientW)
  expect(report.pastItsRow, 'a fulfil cell, or the reason it gives, runs past its row').toBe(0)
  expect(report.paneSideways, 'the board the request rows stand in scrolls sideways').toBeLessThanOrEqual(1)
  // Nothing is docked: no tray opened by turning a face.
  await expect(page.locator('[data-testid="fulfil-tray"]')).toHaveCount(0)

  // SELL is the same ledger narrowed to what she carries — nothing, on a fresh hull — and BUY
  // brings every row back; neither turn moves what stands above.
  await faces.getByRole('tab', { name: /^Sell$/ }).click()
  await expect(page.locator('[data-testid="request-row"]')).toHaveCount(0)
  await expect(page.getByText('No cargo to sell.')).toBeVisible()
  await faces.getByRole('tab', { name: /^Buy$/ }).click()
  await expect(goods.first()).toBeVisible()
  await page.waitForTimeout(400)
  expect(await ABOVE(), 'turning back to Buy MOVED what stands above the board').toEqual(before)
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PORT'S STORAGE FACE — drawn like the trade board: a cell is the act, a press opens the one tray
// with a stepper, nothing above the press moves, and the count on the button is the count moved
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ADDED 2026-09-13, owner rows 87 and 88; 2026-11-06 the owner merged Storage and the Forge into the HQ's Production page. A good
// stands in its own column with one act, the ledger's own `ActCell`: `Put in storage` in Cargo, `Take on board` in Storage. A
// press opens `storage-tray` with a `Stepper` for the COUNT and one button `Put N units in storage`.
// The starter fleet carries nothing, so the proof BUYS first through the trade tray — the in-tab
// PGlite world is disposable — then puts part of it in storage and reads the world back.
test(`HQ › Production: a cell opens the one tray with a stepper, moves nothing above it, and the button says the count`, async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('city')
  await ready(page)
  await openMarket(page)

  // SOMETHING ON BOARD: buy the first live good (in the trade sheet over HQ), and wait for the world to
  // be read back (the card says what is on board).
  const rows = page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]')
  await expect(rows.first()).toBeVisible({ timeout: 60_000 })
  expect(await rows.count(), 'no goods cards — is a fleet docked at HQ?').toBeGreaterThan(1)
  const card = page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]:has([data-testid="trade-buy"]:not([disabled]))').first()
  const bought = (await card.getAttribute('data-good')) ?? ''
  expect(bought, 'no live buy to press').not.toBe('')
  await card.getByTestId('trade-buy').click()
  // S1 (2026-11-24, src/app/HqSheet.tsx): the Buy opens THE trade sheet over HQ; the lot is bought there, and Back closes it
  await tradeOnDesk(page, 5)
  await page.goBack()
  await expect(page.getByTestId('good-detail')).toHaveCount(0, { timeout: 30_000 })
  await expect(page.locator(`[data-testid="city-market-buy"] [data-testid="trade-good"][data-good="${bought}"]`).getByTestId('trade-good-aboard')).toContainText('5', { timeout: 20_000 })

  // PRODUCTION: HQ's plate; on a phone the columns stand under a segmented control. One row per good, one cell per row.
  await openPlate(page, 'production')
  await expect(page.locator('[data-testid="port-production"]')).toBeVisible()
  await page.locator('[data-testid="port-production"]').getByRole('tab', { name: 'Cargo', exact: true }).click()
  const storageRows = page.locator('[data-testid="cargo-row"]')
  await expect(storageRows.first()).toBeVisible({ timeout: 20_000 })
  // The page has landed: the hall's load meter leaves on its own, and a box read before that is the loading, not the press.
  await expect(page.getByTestId('city-load-host')).toHaveCount(0, { timeout: 60_000 })
  const cells = await page.evaluate(() => {
    const all = [...document.querySelectorAll('[data-testid="cargo-row"] button')] as HTMLButtonElement[]
    return {
      cells: all.length,
      rows: document.querySelectorAll('[data-testid="cargo-row"]').length,
      shortest: Math.min(...all.map((c) => c.getBoundingClientRect().height)),
      putCells: all.filter((c) => /^Put in storage/i.test((c.innerText || '').trim())).length,
      livePut: all.filter((c) => !c.disabled && /^Put in storage/i.test((c.innerText || '').trim())).length,
    }
  })
  console.log(`HQ production @${PHONE.width}px: ${JSON.stringify(cells)}`)
  expect(cells.cells, 'a cargo row does not carry one cell').toBe(cells.rows)
  expect(cells.putCells).toBe(cells.rows)
  expect(cells.shortest, 'a cell is under the 44px reach floor').toBeGreaterThanOrEqual(44)
  expect(cells.livePut, 'nothing on board can be put in storage — did the buy land?').toBeGreaterThan(0)

  // PRESS `Put in storage`. The one tray opens with a stepper; nothing at or above the row moves.
  // THE ROWS ARE READ AGAINST THEIR OWN PAGE (2026-11-24, simplify S1): the Production page stands under HQ's board, and the board's
  // bridge line ("/ hour") lands from its own read whenever it lands — measured, 2 px of the board's height arriving with no press at
  // all (main's red of this test). The law is the press's: the tray is fixed and inserts nothing into the list, so the rows are read
  // from the Production page's own top, which nothing above it can move.
  const ROWS_IN_PAGE = (testId: string) => {
    const page = document.querySelector('[data-testid="port-production"]')!.getBoundingClientRect()
    return ([...document.querySelectorAll(`[data-testid="${testId}"]`)] as HTMLElement[]).map((t) => {
      const r = t.getBoundingClientRect()
      return { left: Math.round(r.left - page.left), top: Math.round(r.top - page.top) }
    })
  }
  const before = await page.evaluate(ROWS_IN_PAGE, 'cargo-row')
  await page.evaluate(() => {
    const cell = [...document.querySelectorAll('[data-testid="cargo-row"] button:enabled')].find((b) =>
      /^Put in storage/i.test(((b as HTMLElement).innerText || '').trim()),
    ) as HTMLButtonElement | undefined
    cell?.click()
  })
  const tray = page.locator('[data-testid="storage-tray"]')
  await expect(tray).toBeVisible()
  await expect(tray.locator('[data-testid="storage-qty"] input[type="range"]')).toHaveCount(1)
  await expect(tray.locator('[data-testid="cargo-bar"]')).toContainText(/\d+ \/ \d+ tons?/)
  await page.waitForTimeout(600)
  const after = await page.evaluate(ROWS_IN_PAGE, 'cargo-row')
  expect(after.length, 'the storage list unmounted its rows on a press').toBe(before.length)
  expect(
    before.map((b, i) => ({ b, a: after[i] })).filter(({ b, a }) => a.top !== b.top || a.left !== b.left).length,
    'pressing a storage cell MOVED the list — the tray is `fixed` and inserts nothing',
  ).toBe(0)

  // THE BUTTON SAYS THE COUNT, in the vocabulary law's words, once the dry run has answered.
  const act = tray.locator('[data-testid="storage-act"]')
  await expect(act, 'the move was never previewed — cmd.preview did not answer').toBeEnabled({ timeout: 20_000 })
  await expect(act).toHaveText(/^Put \d+ units? in storage$/)

  // AND IT MOVES: the tray closes on success and the world is read back — the good stands in Storage now, which proves the line went
  // through `cmd.issue` and not a patched store.
  await act.click()
  await expect(tray).toHaveCount(0, { timeout: 30_000 })
  await page.locator('[data-testid="port-production"]').getByRole('tab', { name: 'Storage', exact: true }).click()
  await expect(page.locator('[data-testid="storage-row"]').first()).toBeVisible({ timeout: 20_000 })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PORT'S INN ON A PHONE — the crew as Trade draws a good: the figure, the stepper, the served
// cost moving under it, one button, and nothing above the press moves
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ADDED 2026-09-13 with migration 0086 (owner row 85: *"inn, it should be like trade, where you
// can hire, dismiss crews, and by doing so show how much it will consume everyday"*). The Inn
// face reads `Crew N / max crew` (WORDS law 2: a share prints its whole), a stepper from the
// complement to the crew slots, a wages row that is `world.crew_cost(fleet, n)` for the count
// under the finger — so pressing `More` must CHANGE it, from the server — and ONE button whose
// word follows the direction (`Hire 1` up, `Dismiss 1` down). Every control clears 44px. Row 15:
// the rows above the stepper stay exactly where they were when `More` is pressed.
test(`HQ › Inn: the crew face is a figure, a stepper, a served daily cost and one button, and a press moves nothing above it`, async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('city')
  await ready(page)
  await openPlate(page, 'inn')
  await page.getByTestId('city-inn-crew').click()
  await expect(page.getByTestId('city-inn-page')).toBeVisible()
  await page.waitForTimeout(600)

  const face = page.locator('[data-testid="inn-crew-face"]')
  await expect(face, 'no crew face — is a fleet docked at the port PORT opened on?').toBeVisible()
  // 1. THE FIGURE PRINTS ITS WHOLE: `N / max crew`, never a bare count.
  // 2026-11-15 owner: shorter words (the "crew" unit after the label Crew is gone)
  await expect(page.locator('[data-testid="inn-crew"]')).toContainText(/Crew\s*\d+\s*\/\s*\d+/)
  // 2. THE STEPPER, and the served cost for the count it stands at.
  const stepper = page.locator('[data-testid="inn-crew-stepper"]')
  await expect(stepper).toBeVisible()
  const cost = page.locator('[data-testid="inn-crew-cost"]')
  await expect(cost, 'the wages row never arrived — world.crew_cost did not answer').toBeVisible({ timeout: 20_000 })
  // Moved deliberately 2026-10-19 with 0210 (wages ÷ 5, the fraction owed): the day prints at a price's
  // digits — "0.60 🪙" for 3 hands — so the figure may carry a decimal point, and the whole of it is read.
  await expect(cost).toContainText(/(^|[^\d.,])\d[\d,]*(\.\d+)?\s🪙\s*a day at sea/)
  // THE FIGURE, not the row's text: `Figure` lays its value and unit out as sibling spans, so the
  // text content carries no space between them and the innerText does — comparing prose would
  // compare layout. The number is what the server served, and the number is what must move.
  const figureOf = async () => (await cost.textContent())?.match(/(\d[\d,]*(?:\.\d+)?)\s🪙/)?.[1] ?? null
  const costBefore = await figureOf()
  expect(costBefore).not.toBeNull()
  // 3. ONE BUTTON, dead while nothing has changed.
  const send = page.locator('[data-testid="inn-crew-send"]')
  await expect(send).toBeVisible()
  await expect(send).toBeDisabled()
  await expect(send).toHaveText('No change')

  // Row 15: remember where everything above the stepper sits, press More, and require it not to
  // have moved. Offsets are read against the face's own box.
  const above = () =>
    face.evaluate((el, id) => {
      const stepperEl = el.querySelector(`[data-testid="${id}"]`) as HTMLElement | null
      const stepTop = stepperEl ? stepperEl.getBoundingClientRect().top : Infinity
      return [...el.querySelectorAll<HTMLElement>('[data-testid]')]
        .filter((n) => n.getBoundingClientRect().top < stepTop)
        .map((n) => `${n.dataset.testid}@${Math.round(n.getBoundingClientRect().left)},${Math.round(n.getBoundingClientRect().top)}`)
    }, 'inn-crew-stepper')
  const before = await above()
  expect(before.length, 'nothing stands above the stepper — the figure rows are missing').toBeGreaterThanOrEqual(2)
  await stepper.getByRole('button', { name: 'More' }).click()
  await page.waitForTimeout(900)
  expect(await above(), 'pressing More MOVED a row above the stepper — restructure-on-press, which the owner has refused three times').toEqual(before)

  // 4. THE COST MOVED WITH THE STEPPER, and the button now says what one more crew is: a hire.
  await expect.poll(figureOf, { timeout: 20_000 }).not.toBe(costBefore)
  const costUp = await figureOf()
  await expect(send).toHaveText('Hire 1')
  // Hire the one — the in-tab PGlite world is disposable — and the ship follows: the figure reads
  // one more crew, the stepper stands at what is true, and the button goes quiet again.
  const crewBefore = (await page.locator('[data-testid="inn-crew"]').innerText()).match(/(\d+)\s*\/\s*(\d+)/)!
  await expect(send).toBeEnabled({ timeout: 20_000 })
  await send.click()
  await expect(page.locator('[data-testid="inn-crew"]')).toContainText(
    // 2026-11-15 (the owner's shorter words): the row is the label "Crew" and the figure "9 / 20"; the unit no longer follows the figure
    new RegExp(`Crew\\s*${Number(crewBefore[1]) + 1}\\s*/\\s*${crewBefore[2]}(?!\\d)`),
    { timeout: 30_000 },
  )
  await expect(send).toHaveText('No change')
  // …and one step back down from what is now aboard, the word turns over: a dismissal, and the
  // cost is the served figure for the smaller count — the one the hire was quoted against.
  await stepper.getByRole('button', { name: 'Less' }).click()
  await page.waitForTimeout(900)
  await expect(send).toHaveText('Dismiss 1')
  await expect.poll(figureOf, { timeout: 20_000 }).toBe(costBefore)
  expect(costUp).not.toBe(costBefore)

  // 5. EVERY CONTROL ON THE FACE CLEARS THE 44PX FLOOR — the two stepper buttons and the one button.
  const short = await face.evaluate((el) =>
    [...el.querySelectorAll('button')]
      .map((b) => ({ text: (b.innerText || b.getAttribute('aria-label') || '').slice(0, 24), r: b.getBoundingClientRect() }))
      .filter(({ r }) => r.width > 0 && r.height > 0 && (r.width < 44 || r.height < 44))
      .map(({ text, r }) => `${text} ${Math.round(r.width)}×${Math.round(r.height)}`),
  )
  expect(short, 'a control on the Inn face is under the 44px reach floor').toEqual([])
})
