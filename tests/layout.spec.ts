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
import { PHONE, ready, reachable } from './appReady.fixture'

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
const TABS = ['command', 'fleets', 'port', 'ledger', 'rank', 'compendium'] as const

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

// RETARGETED 2026-09-11, MARKET → PORT. The MARKET tab folded into PORT (owner row 76, the Quay
// Ledger), and the good is ONE ROW now rather than a tile: `TradeRow` under `trade-row`. The proof
// is the same proof — complete priced goods above the fold, the first carrying its range as a
// meter — measured on the screen that draws them.
test('PORT puts complete priced goods above the fold, per K.1', async ({ page, request, baseURL }) => {
  // The same measured budget its sibling tests carry (line ~133): a cold boot builds the whole
  // chain in the tab — ~100 s at 39 migrations, more under parallel load, and 0041's 52k-row
  // affinity recompute adds to it — so the global 120 s timeout fails a CORRECT build. The
  // standing cure is the pre-built database image (DEV_LOG D21); until then the number moves
  // with the world it measures.
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('port')
  await ready(page)
  await page.waitForTimeout(1200)

  // THE GOODS WERE TILES from 2026-08-23 ("make trade goods in blocks") to 2026-09-11, when the
  // owner's row 76 approved the Quay Ledger: ONE ROW per good — name, rarity mark, `N t aboard`,
  // the tide inside the served range as a `Bar` labelled "<good> price range", and the two price
  // cells. A row is ~79px where a tile was ~112px and two abreast, so a floor of 2 would be
  // near-vacuous: MEASURED 2026-09-11 on the local fixture at 390×844, the fold (the nav's top)
  // is at 787px, the first row starts at 322px under title · faces · port field · Stores · filter,
  // and FIVE complete rows fit above it. The floor is that measured figure; the first row must
  // carry its range meter, and so must every other.
  const fold = await page.evaluate(() => {
    const nav = document.querySelector('nav')
    const foldY = nav ? nav.getBoundingClientRect().top : window.innerHeight
    const rows = [...document.querySelectorAll('[data-testid="trade-row"]')]
    const complete = rows.filter((t) => t.getBoundingClientRect().bottom <= foldY)
    return {
      foldY: Math.round(foldY),
      firstRowTop: Math.round(rows[0]?.getBoundingClientRect().top ?? 0),
      rowHeight: Math.round(rows[0]?.getBoundingClientRect().height ?? 0),
      completeRowsAboveFold: complete.length,
      firstRowHasRange: rows[0]?.querySelector('[role="meter"][aria-label$="price range"]') !== null,
      rowsWithoutRange: rows.filter((r) => r.querySelector('[role="meter"][aria-label$="price range"]') === null).length,
    }
  })

  console.log(`PORT fold @${PHONE.width}px: ${JSON.stringify(fold)}`)

  // K.1's beat: "Sal is 62% of its neighbours. The BUY block is at the top; you did not have to
  // know anything to see it." If you have to scroll first, the game has said nothing.
  expect(
    fold.completeRowsAboveFold,
    `only ${fold.completeRowsAboveFold} complete good rows above the fold at ${fold.foldY}px ` +
      `(first row at ${fold.firstRowTop}px, ${fold.rowHeight}px each) — five fit on 2026-09-11`,
  ).toBeGreaterThanOrEqual(5)
  // 0071: this used to require a `%` — the nearby index. That figure is gone, and with it the
  // only thing on the row that was a comparison rather than a fact. What must be on screen now is
  // the RANGE, which is what replaced it: how far this price can travel, here — on EVERY row.
  expect(fold.firstRowHasRange, 'the first good row carries no price-range bar').toBe(true)
  expect(fold.rowsWithoutRange, 'a good row carries no price-range bar — the tide is the row\'s second line').toBe(0)
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A LIST OF THINGS IS A FIELD, NOT A COLUMN OF LINES
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-08-26: *"i told trade goods to be in grid like shape - organized not in lines.
// Yet this also did not occur."* SAID TWICE — the first telling (2026-08-23, "make trade goods in
// blocks as well, not all alligned in sentences — horizontally") converted MARKET and the
// compendium's GOODS face and stopped there, and nothing in this repo could tell that it had
// stopped. Three lists were still one entry per full-width line, MEASURED on the running build at
// 390px before this spec existed:
//
//   · COMMAND's BUY/SELL good picker  — 243 goods as 324px rows, a list 44,212px tall. The
//     biggest list of trade goods in the game and the only one you actually buy from.
//   · the compendium's SHIPS face     — a ten-column table 680px wide inside a 332px box, so six
//     of a hull's ten figures sat behind a sideways swipe.
//   · the compendium's CAPTAINS face  — every officer a 324px block, 107px tall.
//
// So the rule gets a measurement instead of a paragraph. A FIELD means: at 390px, at least two
// entries share a row. That is the whole assertion, and it is the one thing prose could not
// enforce. It cannot be satisfied by a wrapper, a class name or a comment — only by two boxes with
// the same top and different lefts.
//
// WHAT IT DELIBERATELY DOES NOT CLAIM. It says nothing about how TALL a tile is, and nothing about
// the NATIONS face, which is a three-column code→name lookup that measured 324px inside a 332px
// box — it fits, it does not scroll, and it is a lookup rather than a catalogue of entities. Two
// tiles abreast would make it twice as tall and no denser. That one stays a table, on purpose.
const FIELDS = [
  // GOODS ARE HERE EVEN THOUGH THEY ALREADY PASS, and that is the point: this face converted on
  // 2026-08-23 and had no assertion, which is exactly why nobody noticed that its two siblings had
  // not. A guard that only covers the thing that broke will let the next one break silently.
  { tab: 'compendium', face: 'Goods', testId: 'good-tile', noun: 'goods' },
  { tab: 'compendium', face: 'Ships', testId: 'ship-tile', noun: 'ship classes' },
  { tab: 'compendium', face: 'Captains', testId: 'officer-tile', noun: 'officers' },
] as const

/** HOW MANY ENTRIES SHARE A ROW. Self-contained on purpose: Playwright ships the source of this
 *  function into the page, so it may not reach anything outside itself (the same rule
 *  nav.geometry.spec.ts's MEASURE keeps). Tiles are grouped by their top edge, which is what "on
 *  the same line" actually means — no class name, no container, no wrapper can fake it. */
const MEASURE_FIELD = (testId: string) => {
  const tiles = [...document.querySelectorAll(`[data-testid="${testId}"]`)] as HTMLElement[]
  const perRow = new Map<number, number>()
  for (const t of tiles) {
    const top = Math.round(t.getBoundingClientRect().top)
    perRow.set(top, (perRow.get(top) ?? 0) + 1)
  }
  const first = tiles[0]?.getBoundingClientRect()
  return {
    tiles: tiles.length,
    maxPerRow: perRow.size === 0 ? 0 : Math.max(...perRow.values()),
    rows: perRow.size,
    tileWidth: first ? Math.round(first.width) : 0,
    tileHeight: first ? Math.round(first.height) : 0,
    pageScrollW: document.documentElement.scrollWidth,
    pageClientW: document.documentElement.clientWidth,
  }
}

/** Where every tile sits INSIDE the picker, not inside the viewport — so a rail above it
 *  re-rendering its own figures cannot be mistaken for the list restructuring. */
const MEASURE_OFFSETS = (testId: string) =>
  ([...document.querySelectorAll(`[data-testid="${testId}"]`)] as HTMLElement[]).map((t) => ({
    left: t.offsetLeft,
    top: t.offsetTop,
  }))

for (const field of FIELDS) {
  test(`COMPENDIUM ${field.face}: ${field.noun} stand in a field, not in lines, at ${PHONE.width}px`, async ({
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
    await page.waitForTimeout(400)

    const report = await page.evaluate(MEASURE_FIELD, field.testId)
    console.log(`${field.face} @${PHONE.width}px: ${JSON.stringify(report)}`)

    // NON-VACUITY, the floor every check in this file carries: a face that rendered nothing would
    // pass "no entry is on a line of its own" by having no entries.
    expect(report.tiles, `no [data-testid="${field.testId}"] found — did the face render?`).toBeGreaterThan(1)
    expect(
      report.maxPerRow,
      `every ${field.noun} entry is on a line of its own — ${report.tiles} tiles, ` +
        `widest row ${report.maxPerRow}. The owner asked for a grid twice; ` +
        `compose <TileField> (src/components/ui/Tile.tsx), do not write a second grid.`,
    ).toBeGreaterThanOrEqual(2)
    // A tile that is nearly the whole body is a line wearing a border.
    expect(report.tileWidth, `a tile is ${report.tileWidth}px wide — that is a row, not a tile`).toBeLessThan(220)
    expect(report.pageScrollW, 'the page shears sideways').toBeLessThanOrEqual(report.pageClientW)
  })
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PORT'S LEDGER — one row per good, AND the price cells are still the trade
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Two owner rules meet on this one screen:
//   · row 6  — *"i want to be able to click on buy and sell itself and do trades. when pressed
//               unfold another so that i can choose how much i buy."* Every price is a real,
//               labelled, 44px button, and a sell of what she does not carry says "none aboard"
//               ON THE CELL rather than going silently dead.
//   · row 15 — *"when pressing sail, stop folding the sail… don't restruct anything."* Said THREE
//               times. Nothing at or above the pressed row may move when a cell is pressed.
// MOVED DELIBERATELY 2026-09-09, COMMAND → PORT. The owner: *"Buy and sell should be in port -
// market … they should be located accordingly at different locations - the command."* COMMAND's
// verb grid and its BUY question are deleted (tests/verbHomes.spec.ts holds that they stay gone).
//
// RETARGETED 2026-09-11 — THE GRID RULE IS REVERSED BY OWNER ROW 76 (the Quay Ledger,
// docs/QUAY_LEDGER.md). The 2026-08-26 telling ("grid like shape - organized not in lines") was
// pinned here as `maxPerRow ≥ 2` and `tileWidth < 220`. The approved board is ONE ROW PER GOOD —
// `TradeRow` under `trade-row` — so those two assertions are replaced by their honest opposites
// (`maxPerRow === 1`, a row at least 300px wide), and everything about the CELLS stands unchanged:
// two per good, 44px, a figure on each, a dead one says why, no `Choose`, and a press moves
// nothing at or above its own row. The COMPENDIUM field proofs above keep the grid rule for the
// catalogue faces the owner has not spoken about since.
// The Trade face is the face PORT opens on (portView.ts), so nothing has to be pressed to reach it.
test(`PORT: the ledger's price cells are the trade, and a press moves nothing above it`, async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('port')
  await ready(page)
  await page.waitForTimeout(1200)

  const shape = await page.evaluate(MEASURE_FIELD, 'trade-row')
  const cellReport = await page.evaluate(() => {
    // SCOPED TO THE ROWS, not to the page. A price cell is a cell IN a good's row.
    const cells = [...document.querySelectorAll('[data-testid="trade-row"] button')].filter((b) =>
      /^(buy|sell)\b/i.test(((b as HTMLElement).innerText || '').trim()),
    ) as HTMLButtonElement[]
    return {
      priceCells: cells.length,
      shortestCell: cells.length ? Math.min(...cells.map((c) => c.getBoundingClientRect().height)) : 0,
      // The column must not zig-zag: every cell one width, every cell one height, whether or not
      // it carries a reason line. Measured after the first canary drive (2026-09-11) showed a row
      // with cargo aboard shrinking narrower and shorter than its neighbours.
      distinctCellWidths: new Set(cells.map((c) => Math.round(c.getBoundingClientRect().width))).size,
      distinctCellHeights: new Set(cells.map((c) => Math.round(c.getBoundingClientRect().height))).size,
      unlabelledCells: cells.filter((c) => !/\d/.test(c.innerText || '')).length,
      deadCellsSayingWhy: cells.filter((c) => (c as HTMLButtonElement).disabled && /none on board/i.test(c.innerText || '')).length,
      deadCellsSayingNothing: cells.filter((c) => (c as HTMLButtonElement).disabled && !/none on board/i.test(c.innerText || '')).length,
      chooseButtons: [...document.querySelectorAll('button')].filter((b) => /^choose /i.test((b.innerText || '').trim())).length,
    }
  })
  const field = { ...shape, ...cellReport }
  console.log(`PORT ledger @${PHONE.width}px: ${JSON.stringify(field)}`)

  expect(field.tiles, 'no [data-testid="trade-row"] found — is PORT open on its Trade face with a fleet alongside?').toBeGreaterThan(1)

  // 1. ONE ROW PER GOOD — owner row 76 (2026-09-11), reversing the 2026-08-26 grid rule. A ledger
  //    row spans the sheet; two goods sharing a line is the tile grid coming back.
  expect(
    field.maxPerRow,
    `${field.maxPerRow} goods share one line — the Quay Ledger is one row per good (docs/QUAY_LEDGER.md §3 A). ` +
      `Compose <TradeRow> (src/components/ui/TradeRow.tsx), not a grid.`,
  ).toBe(1)
  expect(field.tileWidth, `a good row is ${field.tileWidth}px wide — that is a tile, not a row`).toBeGreaterThanOrEqual(300)

  // 2. ROW 6 SURVIVED THE LEDGER. Two price cells per good, every one a real 44px labelled button,
  //    and a dead one says why on its own face.
  expect(field.priceCells, 'the price cells are gone — row 6 says the price IS the trade').toBe(field.tiles * 2)
  expect(field.shortestCell, 'a price cell is under the 44px reach floor').toBeGreaterThanOrEqual(44)
  expect(field.unlabelledCells, 'a price cell carries no figure').toBe(0)
  expect(field.distinctCellWidths, 'price cells differ in width — the column zig-zags (the TradeRow cell is a fixed box)').toBe(1)
  expect(field.distinctCellHeights, 'price cells differ in height — a live cell must stand as tall as a dead one').toBe(1)
  expect(field.deadCellsSayingNothing, 'a disabled sell cell went grey without saying "none on board"').toBe(0)
  expect(field.deadCellsSayingWhy, 'no sell cell says "none on board" — is `aboard` reaching the picker?').toBeGreaterThan(0)
  expect(field.chooseButtons, 'a `Choose <good>` button is back — two authorities for the pick').toBe(0)

  // 3. ROW 15 SURVIVED THE LEDGER. Press a price cell and NOTHING at or above the pressed row may
  //    move inside the ledger. What is BELOW may move down, which is what an unfold IS (the tray
  //    is `fixed`, so in practice nothing moves at all). Offsets are read against the ledger's own
  //    container, so a rail above it re-rendering its figures cannot make this red for a reason
  //    it is not about.
  const before = await page.evaluate(MEASURE_OFFSETS, 'trade-row')
  await page.evaluate(() => {
    const cell = [...document.querySelectorAll('button')].find((b) => /^buy\b/i.test((b.innerText || '').trim()))
    ;(cell as HTMLButtonElement | undefined)?.click()
  })
  await page.waitForTimeout(900)
  const after = await page.evaluate(MEASURE_OFFSETS, 'trade-row')

  expect(after.length, 'the ledger unmounted its goods on a press — that is the restructure row 15 forbids').toBe(
    before.length,
  )
  // The pressed cell is on the first row; it and everything above it must be where it was.
  const rowTop = before[0].top
  const moved = before
    .map((b, i) => ({ i, b, a: after[i] }))
    .filter(({ b, a }) => b.top <= rowTop && (a.top !== b.top || a.left !== b.left))
  expect(
    moved.map(({ i, b, a }) => `row#${i} ${b.left},${b.top} → ${a.left},${a.top}`),
    'pressing a price cell MOVED the pressed row. The tray is `fixed` and inserts nothing into ' +
      'the ledger (src/components/ui/TradeTray.tsx) — the owner has refused restructure-on-press ' +
      'three times.',
  ).toEqual([])
  // And what it opened is the TRADE tray — a fleet is alongside, so a price is an order.
  await expect(page.locator('[data-testid="trade-tray"]')).toBeVisible()
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PORT READS ELSEWHERE — the port field, and a quay with nobody alongside is read-only
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ADDED 2026-09-11 with the fold of MARKET into PORT (owner row 76). MARKET's one job — read the
// prices at a harbour you are not standing on — is PORT's now, through the same port field it
// carried. ONE fact decides what a price cell opens: a fleet of yours alongside the harbour on
// screen. Alongside → `trade-tray` (proved above). Nobody alongside → `price-tray`, which steps
// nothing and issues nothing. This proof picks a harbour where nobody is (the local world has one
// house with one fleet, so any chip that is not the current harbour is such a place) and presses
// a cell.
test(`PORT: the port field is on the sheet, and a harbour with nobody alongside opens the read-only tray`, async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('port')
  await ready(page)
  await page.waitForTimeout(1200)

  const field = page.locator('[data-testid="port-field"]')
  await expect(field, 'no port field on PORT — MARKET folded into PORT and brought its field').toBeVisible()
  const home = await field.inputValue()
  expect(home, 'the port field names no harbour at rest').not.toBe('')

  // Focus opens the nearest-ten chips; the current harbour is the `on` chip. Take another.
  await field.focus()
  const chips = page.locator('[data-testid="port-chip"]')
  await expect(chips.first()).toBeVisible()
  const other = chips.filter({ hasNotText: home }).first()
  const there = (await other.innerText()).trim()
  await other.click()
  await expect(field).toHaveValue(there)
  // The market for the picked harbour is fetched on demand; wait for the placeholder to go.
  await ready(page)
  await page.waitForTimeout(600)

  // No hull of yours lies there, and the ledger is the SAME ledger (QuayLedger under
  // `quay-ledger`). Its floor is the owner's own: a city trades at least FOUR goods
  // (docs/OWNER_REQUESTS.md row 48, migration 0061), so fewer than four rows means the read did
  // not land, not a small quay.
  const rows = page.locator('[data-testid="trade-row"]')
  await expect(page.locator('[data-testid="quay-ledger"]'), `${there} drew no ledger`).toBeVisible()
  expect(await rows.count(), `${there} drew fewer than the four goods every city trades`).toBeGreaterThanOrEqual(4)

  // Press the first live cell: it opens the READ-ONLY tray, never the trade tray.
  await rows.locator('button:enabled').first().click()
  await expect(page.locator('[data-testid="price-tray"]')).toBeVisible()
  await expect(page.locator('[data-testid="trade-tray"]')).toHaveCount(0)

  // The closed field's ✕ is "back to her quay": the pick clears and the board follows the fleet.
  await page.locator('[data-testid="port-field"] ~ button[aria-label="Clear"]').click()
  await expect(field).toHaveValue(home)
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PORT'S BASKET ON A PHONE — a line staged instead of traded; one tray; nothing above the press
// moves; the basket lands as a receipt and the world is read back
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ADDED 2026-09-13 with slice 2 of the Quay Ledger (docs/QUAY_LEDGER.md §3 C/E, migration 0083;
// owner rows 76 and 80). A price cell's tray carries `Add to basket` beside its one button.
// Pressing it closes the pick and docks the BASKET at PEEK — the title is the whole basket in one
// line — and nothing at or above the pressed row moves (row 15, the same measurement as the trade
// test). Every control in the basket clears the 44px floor. Dragged to half, the one button lands
// the basket through cmd.trade_basket and the same tray turns over to the RECEIPT, whose rows are
// the server's own settled figures; the ledger row of the good then says what is ON BOARD, which
// proves the world was read back and not patched (PR #59 review SHOULD 8). The in-tab PGlite
// world is disposable, so a real trade here is fine.
test(`PORT: a line staged onto the basket docks the one tray at peek, moves nothing, and lands as a receipt`, async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('port')
  await ready(page)
  await page.waitForTimeout(1200)

  const rows = page.locator('[data-testid="trade-row"]')
  expect(await rows.count(), 'no ledger rows — is PORT open on its Trade face with a fleet docked?').toBeGreaterThan(1)
  // On a phone an EMPTY basket docks nothing: there is nothing to say.
  await expect(page.locator('[data-testid="basket-panel"]')).toHaveCount(0)

  const before = await page.evaluate(MEASURE_OFFSETS, 'trade-row')
  // Press the first live BUY cell and remember whose row it is; the trade tray opens with
  // `Add to basket` beside its button.
  const pressed = await page.evaluate(() => {
    const cell = [...document.querySelectorAll('[data-testid="trade-row"] button:enabled')].find((b) =>
      /^buy\b/i.test(((b as HTMLElement).innerText || '').trim()),
    ) as HTMLButtonElement | undefined
    const row = cell?.closest('[data-testid="trade-row"]') as HTMLElement | null
    cell?.click()
    return row ? (row.innerText || '').split('\n')[0].trim() : ''
  })
  expect(pressed, 'no live buy cell to press').not.toBe('')
  const stage = page.locator('[data-testid="trade-tray-stage"]')
  await expect(stage).toBeVisible()
  // The dry run must price the quantity first — the stage button is disabled until the act is ready.
  await expect(stage).toBeEnabled({ timeout: 20_000 })
  await stage.click()

  // ONE tray: the pick is gone and the basket stands in its place, at PEEK, its title the line.
  await expect(page.locator('[data-testid="trade-tray"]')).toHaveCount(0)
  const basket = page.locator('[data-testid="basket-panel"]')
  await expect(basket).toBeVisible()
  expect(await basket.getAttribute('data-tray-detent')).toBe('peek')
  await expect(basket.locator('h2')).toHaveText(/^Buy 1 line/)

  // Row 15: staging moved nothing in the ledger.
  await page.waitForTimeout(600)
  const after = await page.evaluate(MEASURE_OFFSETS, 'trade-row')
  expect(after.length, 'the ledger unmounted its goods when a line was staged').toBe(before.length)
  expect(
    before.map((b, i) => ({ b, a: after[i] })).filter(({ b, a }) => a.top !== b.top || a.left !== b.left).length,
    'staging a line MOVED the ledger — the basket is `fixed` and inserts nothing',
  ).toBe(0)

  // Up to half: the cargo bar, the line, the served totals and the one button. Every control
  // clears the floor. The button carries the served figure and stays enabled across the world's
  // 3-second re-read (PR #59 MUST-FIX 1): it is checked, then checked again after a beat.
  await basket.locator('button[aria-label="Resize"]').focus()
  await page.keyboard.press('ArrowUp')
  await expect(basket).toHaveAttribute('data-tray-detent', 'half')
  await expect(basket.locator('[data-testid="cargo-bar"]')).toBeVisible()
  await expect(basket.locator('[data-testid="basket-line"]')).toHaveCount(1)
  const send = basket.locator('[data-testid="basket-send"]')
  await expect(send, 'the basket was never priced — cmd.preview_basket did not answer').toBeEnabled({ timeout: 20_000 })
  await expect(send).toHaveText(/^Buy 1 line · [\d,]+ d\.$/)
  expect(await basket.locator('[data-testid="basket-total"]').count(), 'no served totals rows').toBeGreaterThanOrEqual(3)
  await page.waitForTimeout(3_500)
  await expect(send, 'the button went dead on the world\'s re-read — the estimate was thrown away').toBeEnabled()
  await expect(send).toHaveText(/^Buy 1 line · [\d,]+ d\.$/)
  const short = await basket.evaluate((el) =>
    [...el.querySelectorAll('button')]
      .map((b) => ({ text: (b.innerText || b.getAttribute('aria-label') || '').slice(0, 24), r: b.getBoundingClientRect() }))
      .filter(({ r }) => r.width > 0 && r.height > 0 && (r.width < 44 || r.height < 44))
      .map(({ text, r }) => `${text} ${Math.round(r.width)}×${Math.round(r.height)}`),
  )
  expect(short, 'a control in the basket is under the 44px reach floor').toEqual([])
  // The staged units are drawn back onto the cargo bar as a wash.
  await expect(basket.locator('[data-testid="cargo-bar"] [data-bar-pending]')).toHaveCount(1)

  // Trade it. The same tray turns over to the receipt: the settled line, tax, fee, net, ducats,
  // trading — the server's own figures, at least five rows of them — dismissed by ONE press.
  await send.click()
  const receipt = page.locator('[data-testid="receipt-panel"]')
  await expect(receipt).toBeVisible({ timeout: 30_000 })
  await expect(receipt.locator('h2')).toHaveText(/^Traded · \d\d:\d\d$/)
  expect(await receipt.locator('[data-testid="receipt-row"]').count()).toBeGreaterThanOrEqual(5)
  await expect(page.locator('[data-testid="basket-panel"]')).toHaveCount(0)
  // …and the world was READ BACK: the pressed good's own row now says what is on board.
  await expect(rows.filter({ hasText: pressed }).first()).toContainText(/\d units? on board/, { timeout: 20_000 })
  await receipt.locator('[data-testid="receipt-done"]').click()
  await expect(receipt).toHaveCount(0)
  expect(await rows.count()).toBe(before.length)
})
