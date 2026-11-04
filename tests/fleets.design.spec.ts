import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, readGlass } from './unfold.fixture'
import { DESIGN_GLASSES, ROW_MAX_REM, boxesOf, readDesign, settled } from './design.fixture'
import { serveVeteranWorld, VETERAN_HULLS } from './manyFleets.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// FLEETS IS A PAGE — the owner's design order, measured with a veteran's eight fleets at five glasses, in English and Korean (2026-11-04)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.) Stats took the page first
// (tests/stats.design.spec.ts), then the Codex, History, Rank, Routes and the HQ; Fleets is the next screen on it, held to the SAME
// laws by the SAME apparatus (tests/design.fixture.ts).
//
// FLEETS WAS ONE PANEL that scrolled inside itself (the sheets-grow slice, 2026-11-02): a column of rows at the left of the glass,
// nothing at its right. It is now a PAGE (`Sheet layout="page"`): MAIN the fleets as one card list, SIDE (the tray's column) your
// company in figures. The page scrolls; nothing inside it does. A press on a fleet still opens her page and moves nothing behind it.
//
// THE LAWS (docs/dev-log/2026-11-04-fleets-design.md; screenLayout.ts "THE PAGE"):
//   (a) USE THE WIDTH. From 1,024 px the content block is centred — the band empty at its right is no wider than the margin at its
//       left — and from 1,280 it spans at least 80 % of the glass.
//   (b) THE DEFECT RULES STAND: no sideways scroll, no two text boxes crossing, no one-letter wrap, no cut text without its full text,
//       every control at least 44 × 44, the document flat.
//   (c) THE HIERARCHY: the company's two key figures at least 24 px over labels of at least 13; a fleet's row at least 52 px, none
//       wider than 36 rem.
//   (e) THE SIDE IS USED: the company card stands in the side column from 1,024; the fleets stand in the main.
//   (f) NO SCROLL TRAP: nothing but the sheet scrolls — the list never scrolls inside itself, however many fleets.
//   (g) THE FLEETS COME FIRST ON A PHONE: below the split the first fleet's row begins on the first glass.
//   (h) A PRESS ON A FLEET opens her page and moves nothing behind it; Back leaves the page as it was.
//
// WHICH WERE RED BEFORE: this file run against the build of origin/main 15d86521 (the one scrolling panel) — numbers in the dev-log.
// The 2026-11-02 spec `fleets.you.grow.spec.ts` held the panel ("a panel that scrolls inside itself", "the panel fills the glass") —
// the compaction row 267 reverses; its YOU half and what it was right about (a name whole at 320, a fleet at sea) stand there.

const SHEET = '[data-testid="fleets"]'
const FIGURES = ['fleets-total', 'fleets-hulls'] as const
const ROWS = ['fleet-row'] as const

/** Where a block stands: inside the side column (`[data-page-side]`) or not. Self-contained, shipped into the page. */
const IN_SIDE = ({ ids }: { ids: readonly string[] }) => {
  const side = document.querySelector('[data-page-side]')
  return ids.map((id) => ({ id, found: !!document.querySelector(`[data-testid="${id}"]`), inSide: !!side?.querySelector(`[data-testid="${id}"]`) }))
}

async function open(page: Page, glass: { width: number; height: number }) {
  await page.setViewportSize(glass)
  await serveVeteranWorld(page)
  await page.goto('fleets')
  await ready(page)
  await expect(page.getByTestId('fleets')).toBeVisible()
  await expect(page.getByTestId('fleet-row')).toHaveCount(VETERAN_HULLS, { timeout: 120_000 })
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`Fleets is a page — ${locale}`, () => {
    test.use({ locale })

    for (const glass of DESIGN_GLASSES) {
      test(`${VETERAN_HULLS} fleets, at ${glass.width}×${glass.height}: the glass used, the side used, the hierarchy, no overlap, no trap`, async ({ page, request, baseURL }) => {
        test.setTimeout(600_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await open(page, glass)
        const where = `${locale} @${glass.width}×${glass.height}`
        const failures: string[] = []
        const d = await readDesign(page, { sheet: SHEET, figureIds: FIGURES, rowIds: ROWS })
        const flat = await readGlass(page, 'fleets-list', 'fleet-row', SHEET)
        console.log(
          `DESIGN ${where}: block ${d.block ? `${Math.round(d.block.left)}..${Math.round(d.block.right)}` : '-'} · figures ${d.figures.map((f) => f.font).join('/')} · rows ${d.rows.length}x${d.rows.length ? Math.round(Math.min(...d.rows.map((r) => r.h))) : '-'}..${d.rows.length ? Math.round(Math.max(...d.rows.map((r) => r.w))) : '-'}w · scrollers ${d.scrollers.length}`,
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

        // (c) THE HIERARCHY
        if (d.figures.length < FIGURES.length) failures.push(`${where}: (c) the company shows ${d.figures.length} of its ${FIGURES.length} key figures`)
        for (const f of d.figures) {
          if (f.font < 24) failures.push(`${where}: (c) the figure ${f.id} is ${f.font} px — the law is 24`)
          if (f.label !== null && f.label < 13) failures.push(`${where}: (c) the label of ${f.id} is ${f.label} px — the law is 13`)
        }
        if (d.rows.length < VETERAN_HULLS) failures.push(`${where}: (c) ${d.rows.length} of ${VETERAN_HULLS} fleet rows are visible`)
        const short = d.rows.filter((r) => r.h < 52 - 0.5)
        const wide = d.rows.filter((r) => r.w > ROW_MAX_REM * 16 + 1)
        if (short.length > 0) failures.push(`${where}: (c) ${short.length} fleet rows are under 52 px — the shortest is ${Math.round(Math.min(...short.map((r) => r.h)))}`)
        if (wide.length > 0) failures.push(`${where}: (c) ${wide.length} rows are wider than ${ROW_MAX_REM} rem — the widest is ${Math.round(Math.max(...wide.map((r) => r.w)))} px`)

        // (e) THE SIDE IS USED
        if (glass.width >= 1024 && d.side === null) failures.push(`${where}: (e) the page has no side column`)
        for (const b of await page.evaluate(IN_SIDE, { ids: ['fleets-company', 'fleets-list'] })) {
          if (!b.found) failures.push(`${where}: (e) the screen has no ${b.id} block`)
          else if (glass.width >= 1024 && b.id === 'fleets-company' && !b.inSide) failures.push(`${where}: (e) ${b.id} does not stand in the side column`)
          else if (glass.width >= 1024 && b.id === 'fleets-list' && b.inSide) failures.push(`${where}: (e) the fleets stand in the side column`)
        }

        // (f) NO SCROLL TRAP — only the sheet scrolls
        for (const s of d.scrollers) failures.push(`${where}: (f) a box scrolls inside itself — ${s}`)

        // (g) THE FLEETS FIRST ON A PHONE: the first row begins on the first glass
        if (glass.width < 1024) {
          const top = await page.evaluate(() => document.querySelector('[data-testid="fleet-row"]')?.getBoundingClientRect().top ?? null)
          if (top === null || top + 52 > glass.height) failures.push(`${where}: (g) the first fleet begins at ${top === null ? '-' : Math.round(top)} px of a ${glass.height}-px glass`)
        }

        // U3 — NOTHING WAS REMOVED: every old test id is on the screen
        for (const id of ['fleets', 'fleets-list']) if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: U3 ${id} is gone`)
        for (const id of ['fleet-row-bars', 'cargo-bar']) if ((await page.getByTestId(id).count()) !== VETERAN_HULLS) failures.push(`${where}: U3 ${id} is not on every fleet`)

        if (failures.length > 0) console.log(`LAWS ${where}: ${failures.length} lines\n  ${failures.join('\n  ')}`)
        expect(failures, 'Fleets is not the page the owner asked for').toEqual([])
      })
    }
  })
}

// (h) A PRESS ON A FLEET OPENS HER PAGE AND MOVES NOTHING BEHIND IT
for (const glass of [DESIGN_GLASSES[0], DESIGN_GLASSES[3]]) {
  test(`a press on a fleet opens her page and moves nothing behind it, at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await open(page, glass)
    const ids = ['fleets-list', 'fleets-company']
    await settled(page, '[data-sheet]').catch(() => {})
    const before = await boxesOf(page, SHEET, ids)
    const rows = await boxesOf(page, SHEET, ['fleet-row'])
    await page.getByTestId('fleet-row').first().click()
    await expect(page.getByTestId('fleet-page')).toBeVisible()
    expect(await boxesOf(page, SHEET, ids), 'her page moved the page behind it').toEqual(before)
    expect(await boxesOf(page, SHEET, ['fleet-row'])).toEqual(rows)
    await page.locator('[data-detail-back]').last().click()
    await expect(page.getByTestId('fleet-page')).toHaveCount(0)
    expect(await boxesOf(page, SHEET, ids), 'closing her page moved the page').toEqual(before)
  })
}
