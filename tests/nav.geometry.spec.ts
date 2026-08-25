import { test, expect } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'

// NAV BAR GEOMETRY — the pin that stops the tab rail growing a second row again.
//
// ── WHAT WENT WRONG, IN NUMBERS ─────────────────────────────────────────────────────────────────
// The ninth tab (Codex/도감) took the bar to a 3×3 grid on a phone. MEASURED on the built app at
// 390×844 before this slice: nine cells of 130×56 in a bar **168px tall** — 19.9% of an 844px
// screen spent on navigation, three rows deep, with the game squeezed into what was left. The
// answer recorded in docs/OWNER_REQUESTS.md was to GROUP the tabs rather than add rows, and the
// owner took that decision. After grouping: **six cells of 65×56 in a bar 56px tall.**
//
// A number in a comment is not a guard, which is why this file exists. The old bar passed every
// check the repo had — it did not overflow, it did not clip a label, the page never scrolled
// sideways — and it was still wrong. So the assertion that actually holds the decision is
// **ONE ROW**, and it is asserted beside the fit checks rather than instead of them.
//
// ── THE OTHER HALF: A GROUP MUST REVEAL, NOT DESTROY ────────────────────────────────────────────
// The owner's standing rule, said four times and built backwards twice
// (docs/RESUME.md, docs/OWNER_REQUESTS.md row 28):
//
//   "Pressing a control SELECTS. It never collapses, re-flows, replaces or destroys the surface it
//    was pressed on, and nothing docks and follows the scroll."
//
// A grouped tab rail is the single easiest place in this app to break that rule: the obvious
// implementation swaps the bar's contents for the group's members, which destroys the very surface
// the finger just landed on. The second test below makes that unbuildable — it records every bar
// cell's rectangle, opens a group, and requires the rectangles to be **identical to the pixel**.
//
// ── HOW TO RUN IT ───────────────────────────────────────────────────────────────────────────────
//     npm run build && npm run preview
//     npx playwright test nav.geometry.spec.ts
// It needs a LOCAL-mode build (no .env.local): a cloud build redirects to /auth, where there is no
// nav bar at all, and appReady.fixture's `ready()` skips with that reason stated rather than
// reporting an empty page as a layout failure.

test.use({ viewport: PHONE })

/** The reach floor this project holds every tap target to — navTabs.ts sets it, Explain.tsx and
 *  TabRow.tsx both cite it. A nav cell narrower than this is a miss waiting to happen. */
const TOUCH_FLOOR = 44

/** One row of the bar. `min-h-14` is 56px; the ceiling leaves room for a border and a rounding
 *  error and nothing like room for a second row. A bar taller than this HAS wrapped. */
const ONE_ROW_CEILING = 72

interface CellReport {
  testid: string
  label: string
  /** Rounded to the pixel — a rect compared for "did anything move" must not fail on 0.0001. */
  rect: { x: number; y: number; w: number; h: number }
  /** The label's own box: scrollWidth > clientWidth means the word is being shaved. */
  labelScrollW: number
  labelClientW: number
}

interface NavReport {
  cells: CellReport[]
  barRect: { x: number; y: number; w: number; h: number }
  /** The whole tab rail INCLUDING any revealed panel. It grows only if the panel is in flow. */
  navRect: { x: number; y: number; w: number; h: number }
  /** The tab CONTENT behind the rail. It shrinks only if the rail pushed it. */
  mainRect: { x: number; y: number; w: number; h: number }
  navScrollW: number
  navClientW: number
  pageScrollW: number
  pageClientW: number
}

const MEASURE = () => {
  const round = (r: DOMRect) => ({
    x: Math.round(r.x),
    y: Math.round(r.y),
    w: Math.round(r.width),
    h: Math.round(r.height),
  })
  const nav = document.querySelector('[data-testid="app-nav"]') as HTMLElement | null
  const bar = document.querySelector('[data-testid="nav-bar"]') as HTMLElement | null
  const main = document.querySelector('main')
  const cells = bar ? ([...bar.children] as HTMLElement[]) : []
  return {
    cells: cells.map((c) => {
      const label = c.querySelector('[data-testid^="nav-label-"]') as HTMLElement | null
      return {
        testid: c.getAttribute('data-testid') ?? '(none)',
        label: (label?.textContent ?? '').trim(),
        rect: round(c.getBoundingClientRect()),
        labelScrollW: label?.scrollWidth ?? 0,
        labelClientW: label?.clientWidth ?? 0,
      }
    }),
    barRect: bar ? round(bar.getBoundingClientRect()) : { x: 0, y: 0, w: 0, h: 0 },
    navRect: nav ? round(nav.getBoundingClientRect()) : { x: 0, y: 0, w: 0, h: 0 },
    mainRect: main ? round(main.getBoundingClientRect()) : { x: 0, y: 0, w: 0, h: 0 },
    navScrollW: nav?.scrollWidth ?? 0,
    navClientW: nav?.clientWidth ?? 0,
    pageScrollW: document.documentElement.scrollWidth,
    pageClientW: document.documentElement.clientWidth,
  }
}

async function openApp(
  page: import('@playwright/test').Page,
  request: Parameters<typeof reachable>[0],
  baseURL: string | undefined,
) {
  // The boot dominates (see appReady.fixture's ready()); the measurement itself is milliseconds.
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('command')
  await ready(page)
}

test(`nav: one row, every cell reachable, no label shaved at ${PHONE.width}px`, async ({
  page,
  request,
  baseURL,
}) => {
  await openApp(page, request, baseURL)

  const report: NavReport = await page.evaluate(MEASURE)

  // The measurement, printed. This spec's whole reason for existing is that the bar's geometry was
  // being argued about in comments; the run should leave the number behind.
  console.log(
    `NAV @${PHONE.width}×${PHONE.height}: ${report.cells.length} cells, bar ${report.barRect.w}×${report.barRect.h}px, ` +
      `cells ${report.cells.map((c) => `${c.label} ${c.rect.w}×${c.rect.h}`).join(' | ')}`,
  )

  // 0. NON-VACUITY. Same floor layout.spec learned the hard way: point the base URL at a bare host
  //    and vite preview answers with its own "did you mean" page, which has no nav and would pass
  //    every assertion below by having nothing to measure.
  expect(
    report.cells.length,
    'no nav cells found — is [data-testid="nav-bar"] rendered? A bare host serves vite\'s ' +
      '"did you mean" page, which passes every check here by having no content at all.',
  ).toBeGreaterThanOrEqual(3)

  // 1. ONE ROW. The decision this file pins: at nine tabs the bar wrapped to 3×3 and ate 168px of
  //    an 844px screen. The cure was grouping, not a second row, so a second row is a failure.
  const rows = [...new Set(report.cells.map((c) => c.rect.y))].sort((a, b) => a - b)
  expect(
    rows.length,
    `the tab bar wrapped to ${rows.length} rows (cell tops at ${rows.join(', ')}px). Nine tabs cost ` +
      `168px of an 844px screen this way (measured, 2026-08-25). Group a tab into an existing group ` +
      `in src/app/navTabs.ts — ` +
      `never add a row.`,
  ).toBe(1)
  expect(
    report.barRect.h,
    `the tab bar is ${report.barRect.h}px tall; one row is at most ${ONE_ROW_CEILING}px`,
  ).toBeLessThanOrEqual(ONE_ROW_CEILING)

  // 2. EVERY CELL IS A REAL TAP TARGET.
  for (const c of report.cells) {
    expect(
      c.rect.w,
      `nav cell ${c.testid} (${c.label}) is ${c.rect.w}px wide, under the ${TOUCH_FLOOR}px reach floor — ` +
        `there are too many cells for one row at ${PHONE.width}px`,
    ).toBeGreaterThanOrEqual(TOUCH_FLOOR)
    expect(
      c.rect.h,
      `nav cell ${c.testid} (${c.label}) is ${c.rect.h}px tall, under the ${TOUCH_FLOOR}px reach floor`,
    ).toBeGreaterThanOrEqual(TOUCH_FLOOR)
  }

  // 3. NO LABEL IS SHAVED. NavBar deliberately does not use `truncate`: truncation would HIDE a
  //    clip instead of failing this. A word wider than its cell overflows its own box, and that is
  //    what is read here.
  const shaved = report.cells.filter((c) => c.labelScrollW > c.labelClientW + 1)
  expect(
    shaved.map((c) => `${c.label} (${c.labelScrollW}px in ${c.labelClientW}px)`),
    'nav labels are being cut off — shorten the NAME or group a tab, never truncate',
  ).toEqual([])

  // 4. THE BAR ITSELF DOES NOT SCROLL SIDEWAYS, and neither does the page. Asserted last and never
  //    alone: on its own a green page-scroll check is the camouflage layout.spec's header names.
  expect(report.navScrollW, 'the nav bar overflows itself horizontally').toBeLessThanOrEqual(
    report.navClientW,
  )
  expect(report.pageScrollW).toBeLessThanOrEqual(report.pageClientW)
})

test('nav: opening a group REVEALS its members and moves nothing in the bar', async ({
  page,
  request,
  baseURL,
}) => {
  await openApp(page, request, baseURL)

  const before: NavReport = await page.evaluate(MEASURE)
  expect(before.cells.length).toBeGreaterThanOrEqual(3)

  // A group cell is a button; a destination is a link. That is the whole difference, and it is how
  // this spec finds the groups without a second list to keep in step with navTabs.ts.
  const groupCells = await page.locator('[data-testid="nav-bar"] > button').all()
  expect(
    groupCells.length,
    'no group cell in the tab bar — the bar fits one row only because tabs are grouped; if the ' +
      'grouping is gone, the row count assertion in the sibling test is the one that will explain why',
  ).toBeGreaterThanOrEqual(1)

  for (const cell of groupCells) {
    const testid = await cell.getAttribute('data-testid')
    await expect(cell).toHaveAttribute('aria-expanded', 'false')

    await cell.click()

    // It REVEALS: the members are on screen, and they are real destinations.
    const panel = page.locator('[data-testid="nav-group-panel"]')
    await expect(panel).toBeVisible()
    const members = panel.locator('a')
    expect(await members.count(), `${testid} revealed no members`).toBeGreaterThanOrEqual(2)
    await expect(cell).toHaveAttribute('aria-expanded', 'true')

    // IT DOES NOT DESTROY. Every cell of the bar — the surface the finger was on — is exactly
    // where it was, to the pixel, with the same label. This is the assertion the owner's rule
    // becomes when it is written down as a measurement.
    const after: NavReport = await page.evaluate(MEASURE)
    expect(
      after.cells.map((c) => ({ testid: c.testid, label: c.label, rect: c.rect })),
      `pressing ${testid} moved, replaced or re-flowed the bar it was pressed on`,
    ).toEqual(before.cells.map((c) => ({ testid: c.testid, label: c.label, rect: c.rect })))
    expect(
      after.barRect,
      `pressing ${testid} changed the bar's own box — the revealed panel must overlay, not push`,
    ).toEqual(before.barRect)

    // AND NOTHING ELSE RE-FLOWED EITHER. This pair was ADDED after the guard was break-tested and
    // let a break through: making the panel `relative` instead of `absolute` leaves the bar's six
    // cells exactly where they were — the rail is pinned to the bottom of a flex column, so it
    // grows UPWARD — while the tab rail swells from 57px to 113px and `main` is squeezed by the
    // difference. The cells were identical to the pixel and the screen behind had still been
    // re-flowed, which is the half of the owner's rule the cell check does not see.
    expect(
      after.navRect,
      `pressing ${testid} grew the tab rail from ${before.navRect.h}px to ${after.navRect.h}px — the ` +
        `revealed panel is IN FLOW. It must be positioned out of flow so it overlays the screen.`,
    ).toEqual(before.navRect)
    expect(
      after.mainRect,
      `pressing ${testid} re-flowed the tab content behind the bar ` +
        `(${before.mainRect.w}×${before.mainRect.h} → ${after.mainRect.w}×${after.mainRect.h}). ` +
        `"It never collapses, re-flows, replaces or destroys the surface it was pressed on."`,
    ).toEqual(before.mainRect)

    // And nothing it revealed pushed the page sideways.
    expect(after.pageScrollW).toBeLessThanOrEqual(after.pageClientW)

    // Pressing it again puts the surface back exactly as it was.
    await cell.click()
    await expect(panel).toBeHidden()
    await expect(cell).toHaveAttribute('aria-expanded', 'false')
  }
})
