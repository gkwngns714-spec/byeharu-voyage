import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, readGlass } from './unfold.fixture'
import { DESIGN_GLASSES, ROW_MAX_REM, boxesOf, readDesign, settled as settledSheet, trayBox } from './design.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// RANK IS A PAGE — the owner's design order, measured on both faces at five glasses, in English and Korean (2026-11-03)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.) Stats took the page first
// (tests/stats.design.spec.ts, PR #466), the Codex second (tests/codex.design.spec.ts, PR #473), History third
// (tests/history.design.spec.ts, PR #474); Rank is the fourth screen on it, and this file holds it to the SAME laws, read by the
// SAME apparatus (tests/design.fixture.ts) — a second measuring apparatus would drift.
//
// THIS FILE REPLACES `rank.unfold.spec.ts`. That spec was written on 2026-11-02 for the order *"make it compact showing
// everything possible"* (rows 249-260) and held the packed design: U2 "the page and the Sheet never scroll; the board scrolls
// inside its panel", U1 "the panel stands inside the glass with N whole rows before any press", and "your line stays on the
// glass while the board scrolls" — a line pinned in the panel's header, docking and following the scroll, which the page
// pattern does not do. Row 267 reverses exactly that — *"too packed"* — so U1, U2 and the pin are gone. What it was right about
// stands here, restated: U3 (nothing removed: your line, the rows, the countries, the face tabs and the settled caption), U5 (no
// overlap; cut text carries its full text), U8 (a press on your line opens the fame tray, and closing it leaves the board as it
// was).
//
// THE LAWS (docs/dev-log/2026-11-03-rank-design.md; screenLayout.ts "THE PAGE"), at 1,440×900, 1,280×800, 1,024×768, 390×844
// and 320×640:
//   (a) USE THE WIDTH. From 1,024 px the content block (the visible text widened to the cards' edges) is centred — the band
//       empty at its right is no wider than the margin at its left, so nothing is kept clear for a tray that is shut — and from
//       1,280 it spans at least 80 % of the glass.
//   (b) THE DEFECT RULES STAND: no sideways scroll, no two text or figure boxes crossing, no text narrower than 1.4 × its font
//       size (the one-letter wrap), no cut text without its full text, every control at least 44 × 44, the document flat.
//   (c) THE HIERARCHY: the face's key figure (your place on the board; the cities your country holds) at least 24 px with its
//       label at least 13; a list row at least 52 px — and no list row wider than 36 rem, so the 2026-09-13 complaint ("too much
//       blank space" between a name and its figure) cannot come back.
//   (d) A TRAY OPENED FROM A ROW MOVES NOTHING BEHIND IT, and from 1,024 it slides over the page's SIDE column — the same x and
//       width — because the side is the tray's column.
//   (e) THE SIDE IS USED: each face has its figures as graphics — Your standing and the Leaders beside the board, Your country and
//       Cities held beside the countries — and from 1,024 they stand in the side column; a page never has an empty band at its right.
//   (f) NO SCROLL TRAP: nothing but the sheet scrolls — the page scrolls, a list never scrolls inside itself.
//   (g) THE LIST COMES FIRST ON A PHONE (the Codex's lesson, 2026-11-02): below the split the first row stands on the first glass,
//       before any scroll — no side card stands above the list there. (Rank has no picker: its faces are a segmented control, whose
//       cells name themselves; the "a picker reads its name" law of the Codex has nothing to read here.)
//
// WHICH WERE RED BEFORE: the same file, run against the build of origin/main 4078b90f (the packed column), fails (a) at every
// glass of 1,024 and up, (c) (no key figure; a pressable row 44 px), (d)'s side column, (e) (no side column, no Your standing, no
// Leaders, no Your country, no Cities held) and (f) (the board scrolls inside its panel where it does not fit) — both languages;
// (b), the no-move half of (d), U3, U5 and U8 were already green there: they are guards, kept. The numbers are in the dev-log.

const SHEET = '[data-testid="rank"]'
/** The rows of both faces: a house's line (yours carries its own id), a country's line. */
const ROWS = ['rank-row', 'rank-you', 'rank-country'] as const

/** The two faces, by their place in the tab strip (a Korean strip has other words): the card and the row each stands, the face's key
 *  figure, its side blocks (in the side from 1,024, after the list below it — (e)), and what the old screen had by test id — still
 *  on the face (U3). */
const FACES = [
  { name: 'Captains', panel: 'rank-list', row: 'rank-row', figures: ['rank-place'], side: ['rank-standing', 'rank-leaders'], kept: ['rank-list', 'rank-you'] },
  { name: 'Countries', panel: 'rank-countries', row: 'rank-country', figures: ['rank-held'], side: ['rank-my-country', 'rank-held-bars'], kept: ['rank-countries', 'rank-country'] },
] as const

/** The first row's box on the glass (viewport px), or null. Self-contained, shipped into the page. */
const FIRST_ROW = (id: string) => {
  const e = document.querySelector(`[data-testid="${id}"]`)
  if (!e) return null
  const r = e.getBoundingClientRect()
  return { top: r.top, bottom: r.bottom, glass: innerHeight }
}

/** The side column's blocks: which of the named test ids stand INSIDE `[data-page-side]`. Self-contained, shipped into the page. */
const IN_SIDE = ({ sheet, ids }: { sheet: string; ids: readonly string[] }) => {
  const root = document.querySelector(sheet)
  const side = root?.querySelector('[data-page-side]') ?? null
  return ids.map((id) => ({ id, found: !!root?.querySelector(`[data-testid="${id}"]`), inSide: !!side?.querySelector(`[data-testid="${id}"]`) }))
}

/** The face strip's box (the one tablist of the sheet), rounded, in sheet coordinates. Self-contained, shipped into the page. */
const STRIP = (sheet: string) => {
  const root = document.querySelector(sheet)
  const e = root?.querySelector('[role="tablist"]')
  if (!root || !e) return null
  const r = e.getBoundingClientRect()
  return [Math.round(r.left), Math.round(r.top + root.scrollTop), Math.round(r.width), Math.round(r.height)]
}

async function open(page: Page, glass: { width: number; height: number }) {
  await page.setViewportSize(glass)
  await page.goto('rank')
  await ready(page)
  await expect(page.getByTestId('rank')).toBeVisible()
}

/** Press a face by its place in the strip and wait for its rows: the board is a read of its own (`loadStandings`), the
 *  countries another (`useServedRead`), and each draws a skeleton until it lands. A face whose rows never come is not thrown
 *  here — the walk goes on and its gates say so, with the law lines printed first (a build with no `rank-row` at all, the
 *  packed column, still reports which laws it broke). */
async function openFace(page: Page, index: number) {
  await page.locator(SHEET).getByRole('tablist').first().getByRole('tab').nth(index).click()
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
  await page.getByTestId(FACES[index].row).first().waitFor({ state: 'visible', timeout: 30_000 }).catch(() => {})
  await page.waitForTimeout(600)
}

const settled = (page: Page) => settledSheet(page, SHEET)

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`Rank is a page — ${locale}`, () => {
    test.use({ locale })

    for (const glass of DESIGN_GLASSES) {
      test(`both Rank faces, at ${glass.width}×${glass.height}: the glass used, the side used, the hierarchy, no overlap, no trap`, async ({ page, request, baseURL }) => {
        test.setTimeout(900_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await open(page, glass)

        const failures: string[] = []
        let rowsMet = 0
        let figuresMet = 0
        for (const [i, face] of FACES.entries()) {
          await openFace(page, i)
          const where = `${locale} ${face.name} @${glass.width}×${glass.height}`
          const d = await readDesign(page, { sheet: SHEET, figureIds: face.figures, rowIds: ROWS })
          const flat = await readGlass(page, face.panel, face.row, SHEET)
          console.log(
            `DESIGN ${where}: block ${d.block ? `${Math.round(d.block.left)}..${Math.round(d.block.right)}` : '-'} (text ${d.span ? `${Math.round(d.span.left)}..${Math.round(d.span.right)}` : '-'}) · figure ${d.figures.map((f) => `${f.font}/${f.label}`).join(' ') || '-'} · rows ${d.rows.length}x${d.rows.length ? Math.round(Math.min(...d.rows.map((r) => r.h))) : '-'} (widest ${d.rows.length ? Math.round(Math.max(...d.rows.map((r) => r.w))) : '-'}) · cards ${d.cards.length} · side ${d.side ? Math.round(d.side.w) : '-'} · scrollers ${d.scrollers.length} · sheet ${flat.sheet?.sh}/${flat.sheet?.ch}`,
          )

          // (a) USE THE WIDTH — from 1,024 the block is centred (nothing kept clear at the right), from 1,280 it spans 80 % of the glass.
          // The block is the text widened to the cards' edges (design.fixture.ts `block`): a card at the margin is content at the margin.
          if (d.block === null) failures.push(`${where}: (a) the sheet has no visible text`)
          else if (glass.width >= 1024) {
            const band = d.glass.w - d.block.right
            const share = (d.block.right - d.block.left) / d.glass.w
            if (band > d.block.left + 2) failures.push(`${where}: (a) ${Math.round(band)} px are empty at the right of the content and ${Math.round(d.block.left)} at its left — a column is kept clear for a tray`)
            if (glass.width >= 1280 && share < 0.8) failures.push(`${where}: (a) the content spans ${(share * 100).toFixed(0)} % of the glass — the law is 80 %`)
          }

          // (b) THE DEFECT RULES: overlap, one-letter wrap, cut text, sideways scroll, the 44-px floor — and the document is flat (the SHEET scrolls)
          failures.push(...phoneLaws(where, flat).map((m) => m.replace(/: \([abcd]\) /, ': (b) ')))
          if (flat.doc.sh > flat.doc.ch + 1) failures.push(`${where}: (b) the document scrolls ${flat.doc.sh}/${flat.doc.ch}`)
          if (flat.sheet !== null && flat.sheet.top > 0) failures.push(`${where}: (b) the Sheet arrived scrolled`)
          for (const c of d.smallControls) failures.push(`${where}: (b) a control under 44 px — ${c}`)

          // (c) THE HIERARCHY — the face's key figure at 24 px over a 13-px label; a list row 52 px and no wider than 36 rem
          if (d.figures.length === 0) failures.push(`${where}: (c) the face has no key figure (${face.figures.join(', ')})`)
          for (const f of d.figures) {
            figuresMet++
            if (f.font < 24) failures.push(`${where}: (c) the figure ${f.id} is ${f.font} px — the law is 24`)
            if (f.label !== null && f.label < 13) failures.push(`${where}: (c) the label of ${f.id} is ${f.label} px — the law is 13`)
          }
          const short = d.rows.filter((r) => r.h < 52 - 0.5)
          const wide = d.rows.filter((r) => r.w > ROW_MAX_REM * 16 + 1)
          rowsMet += d.rows.length
          if (d.rows.length === 0) failures.push(`${where}: (c) the face has no ${face.row} rows`)
          if (short.length > 0) failures.push(`${where}: (c) ${short.length} list rows are under 52 px — the shortest is a ${short[0].id} row of ${Math.round(Math.min(...short.map((r) => r.h)))}`)
          if (wide.length > 0) failures.push(`${where}: (c) ${wide.length} list rows are wider than ${ROW_MAX_REM} rem — the widest is a ${wide[0].id} row of ${Math.round(Math.max(...wide.map((r) => r.w)))} px`)

          // (e) THE SIDE IS USED — from 1,024 the face's figure blocks stand in the side column; below it they are there, after the list
          const blocks = await page.evaluate(IN_SIDE, { sheet: SHEET, ids: face.side })
          for (const b of blocks) {
            if (!b.found) failures.push(`${where}: (e) the face has no ${b.id} block`)
            else if (glass.width >= 1024 && !b.inSide) failures.push(`${where}: (e) ${b.id} does not stand in the side column`)
          }
          if (glass.width >= 1024) {
            if (d.side === null) failures.push(`${where}: (e) the page has no side column`)
          } else {
            // (g) THE LIST COMES FIRST ON A PHONE — the first row stands on the first glass, before any scroll
            const first = await page.evaluate(FIRST_ROW, face.row)
            if (first === null) failures.push(`${where}: (g) the face has no ${face.row} row`)
            else if (first.bottom > first.glass + 1) failures.push(`${where}: (g) the first ${face.row} row stands ${Math.round(first.bottom - first.glass)} px under the glass's edge — a side block stands above the list`)
          }

          // (f) NO SCROLL TRAP — only the sheet scrolls
          for (const s of d.scrollers) failures.push(`${where}: (f) a box scrolls inside itself — ${s}`)

          // U3 — NOTHING WAS REMOVED: the list and its rows, your line, the two face tabs, the count on the card, the settled caption
          for (const id of face.kept) {
            if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: U3 ${id} is gone`)
          }
          if ((await page.locator(SHEET).getByRole('tablist').first().getByRole('tab').count()) !== FACES.length) failures.push(`${where}: U3 the two face tabs are not all there`)
          const count = await page.getByTestId(face.panel).locator('[data-list-count]').count()
          if (count === 0) failures.push(`${where}: U3 the card does not count its rows`)
          // the title line carries the settled caption beside the tab's word (a young board reads "just now", so no digit is asked for)
          const header = (await page.locator(SHEET).locator('[data-testid="sheet-header"]').innerText()).trim()
          const word = (await page.locator(SHEET).locator('[data-testid="sheet-header"] h1').innerText()).trim()
          if (header === word) failures.push(`${where}: U3 the settled caption is gone from the title line`)
          // U5 — cut text carries its full text; overlaps are in phoneLaws
        }

        // the law lines, printed before any gate: a red on a build with no key figure still says which laws it broke
        if (failures.length > 0) console.log(`LAWS ${locale} @${glass.width}×${glass.height}: ${failures.length} lines\n  ${failures.join('\n  ')}`)
        // NON-VACUITY: the walk measured the key figure of both faces and the rows of both
        expect(figuresMet, 'the walk measured no key figure — did the side cards render?').toBe(FACES.length)
        expect(rowsMet, 'the walk measured almost no list rows — did the lists render?').toBeGreaterThan(FACES.length * 2)
        expect(failures, 'Rank is not the page the owner asked for').toEqual([])
      })
    }
  })
}

// (d) THE FAME TRAY, OPENED FROM YOUR LINE, MOVES NOTHING BEHIND IT; from 1,024 it stands over the SIDE column — same x, same width.
// U8 (kept from rank.unfold.spec.ts): a press on your line opens the fame tray, and closing it leaves the board as it was. The
// other rows are read-only (RankScreen.tsx says why), so the one press the board has is the one measured.
// And A FACE PRESSED SELECTS (owner rows 6, 15, 25: *"Pressing a control SELECTS. It never collapses, re-flows, replaces or
// destroys the surface it was pressed on"*): the strip stands where it stood, the other face's card takes the main, and back again.
for (const glass of DESIGN_GLASSES) {
  test(`your line's tray moves nothing behind it and stands over the side column; a face pressed selects, at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await open(page, glass)
    await openFace(page, 0)
    const rows = page.getByTestId('rank-row')
    const total = await rows.count()
    expect(total, "the board's rows carry no id (rank-row)").toBeGreaterThan(0)
    const ids = ['rank-list', ...FACES[0].side]

    // Bring your line under the finger FIRST, then measure: a scroll the browser makes to reach a control is not a move.
    const you = page.getByTestId('rank-you')
    await expect(you, 'the board does not name you').toHaveCount(1)
    await you.scrollIntoViewIfNeeded()
    await settled(page)
    const before = await boxesOf(page, SHEET, ids)
    const side = (await readDesign(page, { sheet: SHEET, figureIds: [], rowIds: [] })).side
    await you.click()
    const tray = page.getByTestId('fame-tray')
    await expect(tray).toBeVisible()
    await expect(tray).toContainText(/Trade/)
    await page.waitForTimeout(500)
    expect(await boxesOf(page, SHEET, ids), "your line's press moved the page behind its tray").toEqual(before)
    const box = await trayBox(page)
    expect(box, 'the tray has no box').not.toBeNull()
    if (glass.width >= 1024) {
      expect(side, 'the page has no side column for the tray to stand over').not.toBeNull()
      expect(Math.abs(box!.l - side!.l), `the tray stands at x=${Math.round(box!.l)} and the side column at x=${Math.round(side!.l)}`).toBeLessThanOrEqual(2)
      expect(Math.abs(box!.w - side!.w), `the tray is ${Math.round(box!.w)} px wide and the side column ${Math.round(side!.w)}`).toBeLessThanOrEqual(2)
    } else {
      expect(box!.t + box!.h, 'the tray hangs below the glass').toBeLessThanOrEqual(glass.height + 1)
    }
    await page.getByTestId('tray-close').click({ timeout: 10_000 })
    await expect(tray).toHaveCount(0)
    expect(await boxesOf(page, SHEET, ids), 'closing the tray moved the page').toEqual(before)
    await expect(rows).toHaveCount(total)
    await expect(you).toHaveCount(1)

    // A FACE PRESSED SELECTS: the strip holds its place and width; the countries take the main and the side; back again, the board
    await page.locator(SHEET).evaluate((e) => e.scrollTo(0, 0))
    await settled(page)
    const strip = await page.evaluate(STRIP, SHEET)
    expect(strip, 'the sheet has no face strip').not.toBeNull()
    await openFace(page, 1)
    await expect(page.getByTestId('rank-countries')).toBeVisible()
    expect(await page.getByTestId('rank-country').count(), 'the countries face has no rows').toBeGreaterThan(0)
    expect(await page.evaluate(STRIP, SHEET), 'pressing a face moved the strip').toEqual(strip)
    await openFace(page, 0)
    await expect(rows).toHaveCount(total)
    await expect(you).toHaveCount(1)
    expect(await page.evaluate(STRIP, SHEET), 'pressing a face moved the strip').toEqual(strip)
  })
}
