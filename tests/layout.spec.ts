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
const TABS = ['command', 'fleets', 'port', 'market', 'ledger', 'rank', 'compendium'] as const

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

test('MARKET puts complete priced goods above the fold, per K.1', async ({ page, request, baseURL }) => {
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
  await page.goto('market')
  await ready(page)

  // THE GOODS ARE TILES NOW (2026-08-23, the owner: "make trade goods in blocks as well, not all
  // alligned in sentences — horizontally"), so the fold is measured in complete TILES rather than
  // complete table rows. A tile carries MORE than the old 44px row did (the index, both prices,
  // stock, trend and destination all at once), so two whole tiles above the fold say strictly more
  // than three rows used to — the floor is 2 tiles, and the first must show its % index.
  const fold = await page.evaluate(() => {
    const nav = document.querySelector('nav')
    const foldY = nav ? nav.getBoundingClientRect().top : window.innerHeight
    const tiles = [...document.querySelectorAll('[data-testid="good-tile"]')]
    const complete = tiles.filter((t) => t.getBoundingClientRect().bottom <= foldY)
    return {
      foldY: Math.round(foldY),
      completeTilesAboveFold: complete.length,
      firstTileText: tiles[0] ? (tiles[0] as HTMLElement).innerText.replace(/\s+/g, ' ') : '',
    }
  })

  // K.1's beat: "MARKET tab. Sal is 62% of its neighbours. The BUY block is at the top; you did not
  // have to know anything to see it." If you have to scroll first, the game has said nothing.
  expect(
    fold.completeTilesAboveFold,
    `only ${fold.completeTilesAboveFold} complete good tiles above the fold at ${fold.foldY}px`,
  ).toBeGreaterThanOrEqual(2)
  expect(fold.firstTileText).toMatch(/%/) // the nearby index really is on screen
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
        `compose tileFieldClass() (src/components/ui/tileLayout.ts), do not write a second grid.`,
    ).toBeGreaterThanOrEqual(2)
    // A tile that is nearly the whole body is a line wearing a border.
    expect(report.tileWidth, `a tile is ${report.tileWidth}px wide — that is a row, not a tile`).toBeLessThan(220)
    expect(report.pageScrollW, 'the page shears sideways').toBeLessThanOrEqual(report.pageClientW)
  })
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// COMMAND'S GOOD PICKER — a field, AND the price cells are still the trade
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Two owner rules meet on this one screen and the second is the reason the first is hard:
//   · row 6  — *"i want to be able to click on buy and sell itself and do trades. when pressed
//               unfold another so that i can choose how much i buy."* Every price is a real,
//               labelled, 44px button, and a sell of what she does not carry says "none aboard"
//               ON THE CELL rather than going silently dead.
//   · row 15 — *"when pressing sail, stop folding the sail… don't restruct anything."* Said THREE
//               times. A grid makes this sharper, not easier: a fold placed beside the pressed
//               tile re-flows its row and shoves its neighbour out of the way, which is exactly
//               the restructure-on-press being refused. The fold must land after the WHOLE ROW.
test(`COMMAND: the good picker is a field, its price cells are the trade, and a press moves nothing beside it`, async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('command')
  await ready(page)
  await page.getByRole('button', { name: /^BUY/ }).first().click()
  await page.waitForTimeout(1200)

  const shape = await page.evaluate(MEASURE_FIELD, 'good-pick-tile')
  const cellReport = await page.evaluate(() => {
    // SCOPED TO THE TILES, not to the page: the verb cards at the head of the composer are also
    // buttons whose text starts "BUY" and "SELL" (that is the whole point of them), and counting
    // those made this read 488 cells over 243 goods. A price cell is a cell IN a good's tile.
    const cells = [...document.querySelectorAll('[data-testid="good-pick-tile"] button')].filter((b) =>
      /^(buy|sell)\b/i.test(((b as HTMLElement).innerText || '').trim()),
    ) as HTMLButtonElement[]
    return {
      priceCells: cells.length,
      shortestCell: cells.length ? Math.min(...cells.map((c) => c.getBoundingClientRect().height)) : 0,
      unlabelledCells: cells.filter((c) => !/\d/.test(c.innerText || '')).length,
      deadCellsSayingWhy: cells.filter((c) => (c as HTMLButtonElement).disabled && /none aboard/i.test(c.innerText || '')).length,
      deadCellsSayingNothing: cells.filter((c) => (c as HTMLButtonElement).disabled && !/none aboard/i.test(c.innerText || '')).length,
      chooseButtons: [...document.querySelectorAll('button')].filter((b) => /^choose /i.test((b.innerText || '').trim())).length,
    }
  })
  const field = { ...shape, ...cellReport }
  console.log(`COMMAND good picker @${PHONE.width}px: ${JSON.stringify(field)}`)

  expect(field.tiles, 'no [data-testid="good-pick-tile"] found — did BUY open its good picker?').toBeGreaterThan(1)

  // 1. A FIELD, NOT LINES — the assertion the owner had to ask for twice.
  expect(
    field.maxPerRow,
    `every trade good is on a line of its own — ${field.tiles} goods, widest row ${field.maxPerRow}, ` +
      `tile ${field.tileWidth}px wide. Compose tileFieldClass() (src/components/ui/tileLayout.ts).`,
  ).toBeGreaterThanOrEqual(2)
  expect(field.tileWidth, `a good tile is ${field.tileWidth}px wide — that is a row, not a tile`).toBeLessThan(220)

  // 2. ROW 6 SURVIVED THE GRID. Two price cells per good, every one a real 44px labelled button,
  //    and a dead one says why on its own face.
  expect(field.priceCells, 'the price cells are gone — row 6 says the price IS the trade').toBe(field.tiles * 2)
  expect(field.shortestCell, 'a price cell is under the 44px reach floor').toBeGreaterThanOrEqual(44)
  expect(field.unlabelledCells, 'a price cell carries no figure').toBe(0)
  expect(field.deadCellsSayingNothing, 'a disabled sell cell went grey without saying "none aboard"').toBe(0)
  expect(field.deadCellsSayingWhy, 'no sell cell says "none aboard" — is `aboard` reaching the picker?').toBeGreaterThan(0)
  expect(field.chooseButtons, 'a `Choose <good>` button is back — two authorities for the pick').toBe(0)

  // 3. ROW 15 SURVIVED THE GRID. Press a price cell and NOTHING at or above the pressed tile's own
  //    row may move inside the picker — least of all the tile beside it. What is BELOW moves down,
  //    which is what an unfold IS. Offsets are read against the picker's own container, so a rail
  //    above it re-rendering its figures cannot make this red for a reason it is not about.
  const before = await page.evaluate(MEASURE_OFFSETS, 'good-pick-tile')
  await page.evaluate(() => {
    const cell = [...document.querySelectorAll('button')].find((b) => /^buy\b/i.test((b.innerText || '').trim()))
    ;(cell as HTMLButtonElement | undefined)?.click()
  })
  await page.waitForTimeout(900)
  const after = await page.evaluate(MEASURE_OFFSETS, 'good-pick-tile')

  expect(after.length, 'the picker unmounted its goods on a press — that is the restructure row 15 forbids').toBe(
    before.length,
  )
  // The pressed tile is the first, so its whole row is `cols` wide; everything in it must be where
  // it was, and so must every tile above it (there are none above the first row — the assertion
  // still holds the row-mate still, which is the tile a mid-row fold would have shoved).
  const rowTop = before[0].top
  const moved = before
    .map((b, i) => ({ i, b, a: after[i] }))
    .filter(({ b, a }) => b.top <= rowTop && (a.top !== b.top || a.left !== b.left))
  expect(
    moved.map(({ i, b, a }) => `tile#${i} ${b.left},${b.top} → ${a.left},${a.top}`),
    'pressing a price cell MOVED a tile in the pressed tile\'s own row. The fold must land after ' +
      'the WHOLE row (features/command/ArgPickers.tsx, GoodPicker rule 4) — the owner has refused ' +
      'restructure-on-press three times.',
  ).toEqual([])
})
