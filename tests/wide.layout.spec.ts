// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WIDE GLASS — the page's numbers, and a column that stays a column (owner row 80)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-09-13, on PORT › Trade in a 1,545-px window: *"look. too much blank space."*
// Every geometry test in this suite is pinned to the phone (390×844), which is why a Sheet that
// stretched to any width passed for a month. This file is the desktop's own pin: 1440×900.
//
// Two proofs. The PURE one parses the literal Tailwind classes `screenLayout.ts` must type out
// (Tailwind cannot see a class built from a number) and asserts the arithmetic against the named
// constants, so the tray's edge and the page's edge cannot drift apart. The BROWSER one opens the
// Trade face wide, presses a price, and requires: the rows are no wider than the column; the tray
// is a side panel to the RIGHT of the rows with no overlap; and — row 15, still — nothing moved.

import { test, expect } from '@playwright/test'
import {
  PAGE_REM,
  RAIL_REM,
  SIDE_REM,
  pageColumnClass,
  pageSplitClass,
  pageVarsClass,
  trayDockPageClass,
} from '../src/components/ui/screenLayout'
import { reachable, ready } from './appReady.fixture'
import { openFleetSheet } from './desk.fixture'

/** A readable row, in rem: the gulf between a name and its price stays shut. A law of the desk's panes, not a layout constant. */
const ROW_MAX_REM = 48
const WIDE = { width: 1440, height: 900 }

// THE PAGE (2026-11-02, owner row 267; screenLayout.ts "THE PAGE"): the same proof for the other shape. The page's side column IS the
// tray's column, so the split and the docked tray must read ONE width — `--page-side`, set once on the Sheet from SIDE_REM — and the
// tray's right edge is the page's right margin: `max(--page-pad, 50% − PAGE_REM/2)`. The browser half is tests/stats.design.spec.ts
// ("a chart's tray … stands over the side column", at five glasses).
test('the literal page classes encode the named page constants — the split and the tray read one side width', () => {
  const rem = (cls: string, prefix: string) => {
    const m = new RegExp(`${prefix}\\[([0-9.]+)rem\\]`).exec(cls)
    expect(m, `${prefix}[…rem] missing from "${cls}"`).not.toBeNull()
    return Number(m![1])
  }
  // the container: PAGE_REM of content plus the widest margin (xl:px-10 = 2.5 rem) on each side
  expect(rem(pageColumnClass(), 'max-w-')).toBe(PAGE_REM + 2 * 2.5)
  // the margins: 1 · 1.5 · 2 · 2.5 rem = --page-pad = the container's px-4 · md:px-6 · lg:px-8 · xl:px-10
  const vars = pageVarsClass()
  expect(vars).toContain('[--page-pad:1rem]')
  expect(vars).toContain('md:[--page-pad:1.5rem]')
  expect(vars).toContain('lg:[--page-pad:2rem]')
  expect(vars).toContain('xl:[--page-pad:2.5rem]')
  for (const cls of ['px-4', 'md:px-6', 'lg:px-8', 'xl:px-10']) expect(pageColumnClass()).toContain(cls)
  // the side: SIDE_REM at lg, xl and from 90 rem, set once …
  expect(vars).toContain(`[--page-side:${SIDE_REM.lg}rem]`)
  expect(vars).toContain(`xl:[--page-side:${SIDE_REM.xl}rem]`)
  expect(vars).toContain(`min-[90rem]:[--page-side:${SIDE_REM.wide}rem]`)
  // … and read twice: by the split, and by the tray (its width, and its right edge at half the content)
  expect(pageSplitClass()).toContain('lg:grid-cols-[minmax(0,1fr)_var(--page-side)]')
  const tray = trayDockPageClass()
  expect(tray).toContain('lg:w-[var(--page-side)]')
  // 2026-11-11 (S9): the page is centred on what the RAIL leaves from `lg` (screenLayout.ts THE SHELL), so the margin is
  // (glass − rail)/2 − PAGE_REM/2
  const half = /calc\(50%-var\(--rail-w\)\/2-([0-9.]+)rem\)/.exec(tray)
  expect(half, `the tray's right offset is not (100% − rail)/2 − PAGE_REM/2 in "${tray}"`).not.toBeNull()
  expect(Number(half![1])).toBe(PAGE_REM / 2)
  expect(tray).toContain('max(var(--page-pad)')
})

test.describe('wide glass', () => {
  test.use({ viewport: WIDE })

  // (H3 `desk-into-hq`, 2026-11-24: the Trade desk's three panes are gone, and with them the laws of the quay's tray, the basket
  // and the request board standing in the desk's right pane. The Market plate's own laws are tests/trade.layout.spec.ts.)

  // ═════════════════════════════════════════════════════════════════════════════════════════════
  // FLEETS — a fleet's PAGE holds THREE COLUMNS on a wide glass. The shape is row 89's (*"ships
  // cargo supplies should be in one page with three columns"*); the mechanism is the owner's
  // 2026-10-31 law (*"everything has folded. enough with folding things … once clicked show new
  // page popping up"*): the row opens the one `DetailPage`, and the list behind it cannot move
  // because a fixed overlay is out of flow. tests/layout.spec.ts proves the phone stack and the
  // unmoved list; here the page's three sections stand side by side, on one line.
  // ═════════════════════════════════════════════════════════════════════════════════════════════
  test(`FLEETS at ${WIDE.width}px: a fleet's page holds three columns, and the row behind it does not move`, async ({
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
    const rowBox = (await rows.first().boundingBox())!

    // PRESS. The page opens; the row's own box is the witness that the list did not move.
    await rows.first().click()
    const fleetPage = page.getByTestId('fleet-page')
    await expect(fleetPage).toBeVisible()
    await page.waitForTimeout(600)
    expect(await rows.first().boundingBox(), 'pressing the row moved it').toEqual(rowBox)
    const pageRoot = await fleetPage.evaluate((el) => ({ h: (el as HTMLElement).scrollHeight, ch: (el as HTMLElement).clientHeight }))
    expect(pageRoot.h, `the fleet page itself scrolls: ${pageRoot.h} > ${pageRoot.ch}`).toBeLessThanOrEqual(pageRoot.ch + 1)

    // TWO STEPS (owner, 2026-11-14: "when pressed a fleet, show only ships, then when i press the ship, show cargo and supplies"): the fleet's page carries no
    // section; a ship's row opens her page, and THAT holds Cargo and Supplies side by side.
    await expect(fleetPage.locator('[data-testid="fleet-fold-section"]')).toHaveCount(0)
    await fleetPage.getByTestId('fleet-ship-row').first().click()
    const shipPage = page.getByTestId('fleet-ship-page')
    await expect(shipPage).toBeVisible()
    await page.waitForTimeout(600)
    const sections = await shipPage.evaluate((el) =>
      [...el.querySelectorAll('[data-testid="fleet-fold-section"]')].map((s) => {
        const r = s.getBoundingClientRect()
        return {
          heading: (s.querySelector('h2')?.textContent ?? '').trim(),
          left: Math.round(r.left),
          right: Math.round(r.right),
          top: Math.round(r.top),
          width: Math.round(r.width),
        }
      }),
    )
    const pageBox = (await shipPage.boundingBox())!
    console.log(`FLEETS ship page @${WIDE.width}px: ${JSON.stringify(sections)}`)
    expect(sections.map((s) => s.heading)).toEqual(['Cargo', 'Supplies'])

    // 1. SIDE BY SIDE: three x ranges that do not overlap, left to right in the owner's order.
    for (let i = 1; i < sections.length; i++) {
      expect(
        sections[i].left,
        `${sections[i].heading} overlaps ${sections[i - 1].heading} — the sections are not three columns`,
      ).toBeGreaterThanOrEqual(sections[i - 1].right)
    }
    // 2. ONE LINE: the tops agree within 2px — a column that starts lower is a stack in disguise.
    for (const s of sections) {
      expect(Math.abs(s.top - sections[0].top), `${s.heading}'s top is not on the line`).toBeLessThanOrEqual(2)
    }
    // 3. INSIDE THE PAGE: every box within the page's own x range, never off the glass.
    for (const s of sections) {
      expect(s.left, `${s.heading} starts left of the page`).toBeGreaterThanOrEqual(Math.floor(pageBox.x))
      expect(s.right, `${s.heading} runs past the page's right edge`).toBeLessThanOrEqual(Math.ceil(pageBox.x + pageBox.width))
      expect(s.width, `${s.heading} is too narrow to read`).toBeGreaterThan(160)
    }
    // No tray stands: the page IS the detail now (FleetTray.tsx is deleted).
    await expect(page.locator('[data-tray-mode]')).toHaveCount(0)

    // THE BACK PRESS, twice: the ship's page gives the ships back, the fleet's page gives the list back, and the row is where it was.
    await page.locator('[data-detail-back]').last().click()
    await expect(shipPage).toHaveCount(0)
    await expect(fleetPage.getByTestId('fleet-ship-row').first()).toBeVisible()
    await page.locator('[data-detail-back]').last().click()
    await expect(page.locator('[data-testid="fleet-page"]')).toHaveCount(0)
    await page.waitForTimeout(400)
    expect(await rows.first().boundingBox()).toEqual(rowBox)
  })

  // 0092: the route row at the desktop's width (in her sheet over HQ since H3, 2026-11-24) — inside the 48rem column; since
  // consistency row 38 the press opens THE ROUTE'S PAGE (the one `DetailPage`, fixed over the glass) instead of
  // an in-column unfold: the row and the row below it keep their boxes, and Back returns.
  test(`HER SHEET › Route at ${WIDE.width}px: the route row sits in the column and opens its page`, async ({
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
    await openFleetSheet(page)
    const row = page.getByTestId('route-row')
    await expect(row).toContainText(/Not open yet|No route|Route ·/)
    await page.waitForTimeout(400)
    const remPx = await page.evaluate(() => parseFloat(getComputedStyle(document.documentElement).fontSize))
    const rowBox = (await row.boundingBox())!
    expect(rowBox.width).toBeLessThanOrEqual(ROW_MAX_REM * remPx + 1)

    const queueBox = (await page.getByTestId('hq-sheet-fleet-map').boundingBox())!
    await row.click()
    const routePage = page.getByTestId('route-page')
    await expect(routePage).toBeVisible()
    await expect(routePage).toHaveAttribute('data-detail-page', '')
    await page.waitForTimeout(400)
    expect(await row.boundingBox(), 'pressing the route row moved it').toEqual(rowBox)
    expect(await page.getByTestId('hq-sheet-fleet-map').boundingBox(), 'the route page re-flowed the row below').toEqual(queueBox)
    const pageBox = (await routePage.boundingBox())!
    console.log(`COMMAND route page @${WIDE.width}px: row ${JSON.stringify(rowBox)} page ${JSON.stringify(pageBox)}`)
    // 2026-11-11 (S9): from `lg` a detail page stands on the glass beside the rail (screenLayout.ts `glassBesideRailClass`), so it is
    // the whole window less the rail's RAIL_REM — still the full glass the page has, not a panel inside it
    expect(pageBox.x, 'the page does not stand at the rail edge').toBeCloseTo(RAIL_REM * remPx, 0)
    expect(pageBox.width, 'the page is not the full glass beside the rail').toBeGreaterThanOrEqual(WIDE.width - RAIL_REM * remPx - 1)

    await routePage.locator('[data-detail-back]').click()
    await expect(page.getByTestId('route-page')).toHaveCount(0)
    expect(await row.boundingBox()).toEqual(rowBox)
    expect(await page.getByTestId('hq-sheet-fleet-map').boundingBox()).toEqual(queueBox)
  })
})
