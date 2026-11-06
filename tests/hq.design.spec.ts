import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, readGlass } from './unfold.fixture'
import { DESIGN_GLASSES, ROW_MAX_REM, boxesOf, readDesign, settled as settledSheet, trayBox } from './design.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE HQ IS A PAGE — the owner's design order, measured on all six places at five glasses, in English and Korean (2026-11-04)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.) Stats took the page first
// (tests/stats.design.spec.ts, PR #466), then the Codex, History, Rank and Routes; the HQ is the next screen on it, held to the SAME
// laws by the SAME apparatus (tests/design.fixture.ts).
//
// THE HQ WAS A FRAME OF ONE GLASS: a 100dvh box, the plan 50 % and the open place's panel 50 %, every panel scrolling inside itself,
// its rows pitched at the 44-px floor, its five figures at 16 px hugging their words — the hall panel was a 700-px card with 130 px of
// text in it. It is now a PAGE (`Sheet layout="page"`): the city's name for the title, the six places as a row of cards across the
// page, then MAIN | SIDE from 1,024 px — MAIN the plan (the market's chart when the market is open; the owner's 2026-10-31 order, the
// plan on the left, stands), SIDE the tray's column: your purse over the open place's panel. The page scrolls; nothing inside it does.
//
// THE LAWS (docs/dev-log/2026-11-04-hq-design.md; screenLayout.ts "THE PAGE"):
//   (a) USE THE WIDTH. From 1,024 px the content block is centred — the band empty at its right is no wider than the margin at its left
//       — and from 1,280 it spans at least 80 % of the glass.
//   (b) THE DEFECT RULES STAND: no sideways scroll, no two text boxes crossing, no one-letter wrap, no cut text without its full text,
//       every control at least 44 × 44, the document flat.
//   (c) THE HIERARCHY: the hall's figures at least 24 px with their labels at least 13; a summary row at least 52 px, none wider than 36 rem.
//   (d) THE INVESTORS DRAWER MOVES NOTHING BEHIND IT, and from 1,024 it slides over the page's SIDE column — the same x and width.
//   (e) THE SIDE IS USED: your purse and the open place's panel stand in the side column from 1,024; the plan stands in the main.
//   (f) NO SCROLL TRAP: nothing but the sheet scrolls — no panel, no chart card scrolls inside itself.
//   (g) THE PANEL COMES BEFORE THE PLAN ON A PHONE: below the split, the open place's card begins on the first glass.
//   (h) THE PLAN STANDS WHOLE ON THE FIRST GLASS from 1,024 px: its card ends above the rail.
//
// WHICH WERE RED BEFORE: this file run against the build of origin/main 30606229 (the 50/50 frame) — numbers in the dev-log. The rule
// "the frame never scrolls and the panel does inside itself" of tests/city.audit.spec.ts and city.density.spec.ts (the compaction
// order of 2026-11-01, "more compact with full detail") is what row 267 reverses; what those specs were right about stands here
// (nothing removed, no overlap, the six tiles in one place, a press changes the plan and the panel only).

/** The root the walk reads: the HQ's own screen box, which stands in the packed frame and in the page alike. */
const SHEET = '[data-testid="city-screen"]'

/** The five places, by their tile; the figures a place carries, the summary rows it stands (all kept from the old frame, U3). */
const PLACES: readonly { id: string; panel: string; figures: readonly string[]; rows: readonly string[] }[] = [
  { id: 'hall', panel: 'city-hall-panel', figures: ['city-population', 'city-gold', 'city-status', 'city-employees', 'city-relationship'], rows: [] },
  { id: 'market', panel: 'city-face-panel', figures: [], rows: [] },
  { id: 'production', panel: 'city-face-panel', figures: [], rows: [] },
  { id: 'port', panel: 'city-face-panel', figures: [], rows: ['city-port-yard', 'city-port-repair'] },
  { id: 'inn', panel: 'city-face-panel', figures: [], rows: ['city-inn-crew', 'city-inn-captains'] },
]
/** Production takes the whole page under the row (owner, 2026-11-06), so the plan-and-side laws do not read it. */
const WHOLE_PAGE = 'production'
const FIGURES = PLACES[0].figures
const ROWS = ['city-port-yard', 'city-port-repair', 'city-inn-crew', 'city-inn-captains'] as const

/** Where a block stands: inside the side column (`[data-page-side]`) or not. Self-contained, shipped into the page. */
const IN_SIDE = ({ ids }: { ids: readonly string[] }) => {
  const side = document.querySelector('[data-page-side]')
  return ids.map((id) => ({ id, found: !!document.querySelector(`[data-testid="${id}"]`), inSide: !!side?.querySelector(`[data-testid="${id}"]`) }))
}

/** The panel card's top and the plan card's bottom on the glass, and the rail's top. Self-contained, shipped into the page. */
const FIRST_GLASS = (panel: string) => {
  const top = (id: string) => document.querySelector(`[data-testid="${id}"]`)?.getBoundingClientRect() ?? null
  const rail = top('city-rail')
  const card = top(panel)
  const plan = top('city-plan') ?? top('city-info-image')
  return { panelTop: card?.top ?? null, planBottom: plan?.bottom ?? null, railTop: rail?.top ?? innerHeight, glass: innerHeight }
}

async function open(page: Page, glass: { width: number; height: number }) {
  await page.setViewportSize(glass)
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  await expect(page.getByTestId('city-hall-panel')).toBeVisible({ timeout: 120_000 })
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
}

/** Press a place's tile and wait for its panel's reads to land. */
async function openPlace(page: Page, id: string) {
  await page.getByTestId(`city-building-${id}`).click()
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
  await page.waitForTimeout(700)
}

const settled = (page: Page) => settledSheet(page, '[data-sheet]')

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`The HQ is a page — ${locale}`, () => {
    test.use({ locale })

    for (const glass of DESIGN_GLASSES) {
      test(`all five places, at ${glass.width}×${glass.height}: the glass used, the side used, the hierarchy, no overlap, no trap`, async ({ page, request, baseURL }) => {
        test.setTimeout(900_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await open(page, glass)

        const failures: string[] = []
        let figuresMet = 0
        let rowsMet = 0
        for (const place of PLACES) {
          await openPlace(page, place.id)
          const where = `${locale} ${place.id} @${glass.width}×${glass.height}`
          const d = await readDesign(page, { sheet: SHEET, figureIds: place.figures.length ? place.figures : FIGURES, rowIds: place.rows.length ? place.rows : ROWS })
          const flat = await readGlass(page, place.panel, null, SHEET)
          console.log(
            `DESIGN ${where}: block ${d.block ? `${Math.round(d.block.left)}..${Math.round(d.block.right)}` : '-'} · figures ${d.figures.map((f) => f.font).join('/')} · rows ${d.rows.length}x${d.rows.length ? Math.round(Math.min(...d.rows.map((r) => r.h))) : '-'} · scrollers ${d.scrollers.length}`,
          )

          // (a) USE THE WIDTH
          if (d.block === null) failures.push(`${where}: (a) the screen has no visible text`)
          else if (glass.width >= 1024) {
            const band = d.glass.w - d.block.right
            const share = (d.block.right - d.block.left) / d.glass.w
            if (band > d.block.left + 2) failures.push(`${where}: (a) ${Math.round(band)} px are empty at the right of the content and ${Math.round(d.block.left)} at its left`)
            if (glass.width >= 1280 && share < 0.8) failures.push(`${where}: (a) the content spans ${(share * 100).toFixed(0)} % of the glass — the law is 80 %`)
          }

          // (b) THE DEFECT RULES
          failures.push(...phoneLaws(where, flat).map((m) => m.replace(/: \([abcd]\) /, ': (b) ')))
          if (flat.doc.sh > flat.doc.ch + 1) failures.push(`${where}: (b) the document scrolls ${flat.doc.sh}/${flat.doc.ch}`)
          for (const c of d.smallControls) failures.push(`${where}: (b) a control under 44 px — ${c}`)

          // (c) THE HIERARCHY — the hall's figures 24 px over 13-px labels; summary rows 52 px, none wider than 36 rem
          if (place.id === 'hall') {
            if (d.figures.length < FIGURES.length) failures.push(`${where}: (c) the hall shows ${d.figures.length} of its ${FIGURES.length} figures`)
            for (const f of d.figures) {
              figuresMet++
              if (f.font < 24) failures.push(`${where}: (c) the figure ${f.id} is ${f.font} px — the law is 24`)
              if (f.label !== null && f.label < 13) failures.push(`${where}: (c) the label of ${f.id} is ${f.label} px — the law is 13`)
            }
          }
          if (place.rows.length > 0) {
            const mine = d.rows.filter((r) => place.rows.includes(r.id))
            rowsMet += mine.length
            const short = mine.filter((r) => r.h < 52 - 0.5)
            const wide = mine.filter((r) => r.w > ROW_MAX_REM * 16 + 1)
            if (short.length > 0) failures.push(`${where}: (c) ${short.length} summary rows are under 52 px — the shortest is ${short[0].id} at ${Math.round(Math.min(...short.map((r) => r.h)))}`)
            if (wide.length > 0) failures.push(`${where}: (c) ${wide.length} rows are wider than ${ROW_MAX_REM} rem — ${wide[0].id} is ${Math.round(wide[0].w)} px`)
          }

          // (e) THE SIDE IS USED — your purse and the open panel in the side from 1,024; the plan in the main
          const blocks = await page.evaluate(IN_SIDE, { ids: ['city-summary', place.panel] })
          for (const b of place.id === WHOLE_PAGE ? [] : blocks) {
            if (!b.found) failures.push(`${where}: (e) the screen has no ${b.id} block`)
            else if (glass.width >= 1024 && !b.inSide) failures.push(`${where}: (e) ${b.id} does not stand in the side column`)
          }
          if (glass.width >= 1024 && d.side === null && place.id !== WHOLE_PAGE) failures.push(`${where}: (e) the page has no side column`)
          if (glass.width >= 1024) {
            const plan = (await page.evaluate(IN_SIDE, { ids: ['city-info-image'] }))[0]
            if (plan.inSide) failures.push(`${where}: (e) the plan stands in the side column`)
          }

          // (g) THE PANEL BEFORE THE PLAN ON A PHONE, (h) THE PLAN WHOLE ON THE FIRST GLASS FROM 1,024
          const first = await page.evaluate(FIRST_GLASS, place.panel)
          if (glass.width < 1024) {
            if (first.panelTop === null || first.panelTop + 100 > first.glass) failures.push(`${where}: (g) the panel's card begins at ${first.panelTop === null ? '-' : Math.round(first.panelTop)} px of a ${first.glass}-px glass — it is not on the first glass`)
          } else if (place.id !== WHOLE_PAGE && (first.planBottom === null || first.planBottom > first.railTop + 1)) {
            failures.push(`${where}: (h) the plan ends at ${first.planBottom === null ? '-' : Math.round(first.planBottom)} px, the rail begins at ${Math.round(first.railTop)}`)
          }

          // (f) NO SCROLL TRAP — only the sheet scrolls
          // the page's own sheet is the one box that scrolls (it stands inside the screen box this walk reads)
          for (const s of d.scrollers.filter((x) => !x.startsWith('city-page '))) failures.push(`${where}: (f) a box scrolls inside itself — ${s}`)

          // U3 — NOTHING WAS REMOVED: the six tiles, the name, your purse, the rail, the open place's panel
          for (const id of ['city-building-grid', 'city-name', 'city-phase', 'city-rail', place.panel, ...(place.id === WHOLE_PAGE ? [] : ['city-summary', 'city-info-image'])]) {
            if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: U3 ${id} is gone`)
          }
          if ((await page.getByTestId('city-building-grid').locator('button').count()) !== PLACES.length) failures.push(`${where}: U3 the tiles are not all there`)
        }

        if (failures.length > 0) console.log(`LAWS ${locale} @${glass.width}×${glass.height}: ${failures.length} lines\n  ${failures.join('\n  ')}`)
        // NON-VACUITY: the walk measured the hall's five figures and the rows of the port and the inn
        expect(figuresMet, 'the walk measured no hall figures — did the hall render?').toBe(FIGURES.length)
        expect(rowsMet, 'the walk measured no summary rows — did the port and the inn render?').toBeGreaterThanOrEqual(2)
        expect(failures, 'The HQ is not the page the owner asked for').toEqual([])
      })
    }
  })
}

// (d) THE INVESTORS DRAWER MOVES NOTHING BEHIND IT; from 1,024 it stands over the SIDE column — same x, same width
for (const glass of DESIGN_GLASSES) {
  test(`the investors drawer moves nothing behind it and stands over the side column, at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await open(page, glass)
    const ids = ['city-hall-panel', 'city-summary', 'city-info-image', 'city-building-grid']
    const row = page.getByTestId('city-hall-investors')
    await row.scrollIntoViewIfNeeded()
    await settled(page).catch(() => {})
    const before = await boxesOf(page, SHEET, ids)
    const side = (await readDesign(page, { sheet: SHEET, figureIds: [], rowIds: [] })).side
    await row.click()
    const tray = page.getByTestId('city-investors-drawer')
    await expect(tray).toBeVisible()
    await page.waitForTimeout(500)
    expect(await boxesOf(page, SHEET, ids), 'the drawer moved the page behind it').toEqual(before)
    const box = await trayBox(page)
    expect(box, 'the drawer has no box').not.toBeNull()
    if (glass.width >= 1024) {
      expect(side, 'the page has no side column for the drawer to stand over').not.toBeNull()
      expect(Math.abs(box!.l - side!.l), `the drawer stands at x=${Math.round(box!.l)} and the side column at x=${Math.round(side!.l)}`).toBeLessThanOrEqual(2)
      expect(Math.abs(box!.w - side!.w), `the drawer is ${Math.round(box!.w)} px wide and the side column ${Math.round(side!.w)}`).toBeLessThanOrEqual(2)
    } else {
      expect(box!.t + box!.h, 'the drawer hangs below the glass').toBeLessThanOrEqual(glass.height + 1)
    }
    await page.getByTestId('tray-close').click({ timeout: 10_000 })
    await expect(tray).toHaveCount(0)
    expect(await boxesOf(page, SHEET, ids), 'closing the drawer moved the page').toEqual(before)
  })
}
