import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, playedWorld, readGlass } from './unfold.fixture'
import { DESIGN_GLASSES, ROW_MAX_REM, boxesOf, readDesign, settled as settledSheet, trayBox } from './design.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HISTORY IS A PAGE — the owner's design order, measured on every face at five glasses, in English and Korean (2026-11-03)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.) Stats took the page first
// (tests/stats.design.spec.ts, PR #466), the Codex second (tests/codex.design.spec.ts, PR #473); History is the third screen on
// it, and this file holds it to the SAME laws, read by the SAME apparatus (tests/design.fixture.ts) — a second measuring
// apparatus would drift.
//
// THIS FILE REPLACES `ledger.unfold.spec.ts`. That spec was written on 2026-11-02 for the order *"make it compact showing
// everything possible"* (rows 249-260) and held the packed design: U2 "the page and the Sheet never scroll; the feed scrolls
// inside its panel" and U1 "the panel stands inside the glass with N whole rows before any press". Row 267 reverses exactly
// that — *"too packed"* — so U1 and U2 are gone. What it was right about stands here, restated: U3 (nothing removed: the rows,
// the four face tabs, the count, the empty state), U5 (no overlap; cut text carries its full text), U8 (a row with a report
// opens THAT entry's tray and closing it leaves the list; a face tab narrows the feed), and the young world (one entry, and an
// empty face that says so).
//
// TWO WORLDS, BOTH READ, NO SKIP (kept from the unfold spec). The canary a CI run boots serves ONE entry (the founding); the
// owner's serves fifty. The laws are about the fifty, so the glass walks and the tray proof run on the PLAYED world the fixture
// builds at run time (tests/unfold.fixture.ts: this build's own image with `world.ledger` replaced by a page of fifty), and the
// young world has its own test.
//
// THE LAWS (docs/dev-log/2026-11-03-history-design.md; screenLayout.ts "THE PAGE"), at 1,440×900, 1,280×800, 1,024×768,
// 390×844 and 320×640:
//   (a) USE THE WIDTH. From 1,024 px the content block (the visible text widened to the cards' edges) is centred — the band
//       empty at its right is no wider than the margin at its left, so nothing is kept clear for a tray that is shut — and from
//       1,280 it spans at least 80 % of the glass.
//   (b) THE DEFECT RULES STAND: no sideways scroll, no two text or figure boxes crossing, no text narrower than 1.4 × its font
//       size (the one-letter wrap), no cut text without its full text, every control at least 44 × 44, the document flat.
//   (c) THE HIERARCHY: the record's key figure (the face's net) at least 24 px with its label at least 13; a list row at least
//       52 px — and no list row wider than 36 rem, so the 2026-09-13 complaint ("too much blank space" between a name and its
//       figure) cannot come back.
//   (d) A TRAY OPENED FROM A ROW MOVES NOTHING BEHIND IT, and from 1,024 it slides over the page's SIDE column — the same x and
//       width — because the side is the tray's column.
//   (e) THE SIDE IS USED: the record has its figures as graphics — the Money card, the By kind board, the Biggest board — and
//       from 1,024 they stand in the side column; a page never has an empty band at its right.
//   (f) NO SCROLL TRAP: nothing but the sheet scrolls — the page scrolls, a list never scrolls inside itself.
//   (g) THE LIST COMES FIRST ON A PHONE (the Codex's lesson, 2026-11-02): below the split the first entry stands on the first
//       glass, before any scroll — no side card stands above the list there. (History has no picker: its faces are a segmented
//       control, whose cells name themselves; the "a picker reads its name" law of the Codex has nothing to read here.)
//
// WHICH WERE RED BEFORE: the same file, run against the build of origin/main 567b2d29 (the packed column), fails (a) at every
// glass of 1,024 and up, (c) (no key figure; a pressable row 44 px), (d)'s side column, (e) (no side column, no Money card, no
// boards) and (f) (the list scrolls inside itself) — at every glass, both languages; (b), the no-move half of (d), U3, U5 and
// U8 were already green there: they are guards, kept. The numbers are in the dev-log.

const SHEET = '[data-testid="ledger"]'
const ROWS = ['ledger-row'] as const
const FIGURES = ['ledger-net'] as const
/** The record's three figure blocks — in the side from 1,024, after the list below it (e). */
const SIDE = ['ledger-money', 'ledger-kinds', 'ledger-biggest'] as const
/** What the old screen had by test id — still on the page (U3). */
const KEPT = ['ledger-list', 'ledger-row', 'ledger-day'] as const

/** The fixture's page: fifty entries — ten in Trade, twenty in Voyage, twenty in Crew — by the face's place in the strip
 *  (a Korean strip has other words). */
const FACES = [
  { name: 'All', served: 50 },
  { name: 'Trade', served: 10 },
  { name: 'Voyage', served: 20 },
  { name: 'Crew', served: 20 },
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

async function open(page: Page, glass: { width: number; height: number }, played = true) {
  await page.setViewportSize(glass)
  if (played) await playedWorld(page)
  await page.goto('ledger')
  await ready(page)
  await expect(page.getByTestId('ledger')).toBeVisible()
}

async function openFace(page: Page, index: number) {
  await page.locator(SHEET).getByRole('tablist').first().getByRole('tab').nth(index).click()
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
  await page.waitForTimeout(600)
}

/** THE SHEET HAS SETTLED after a scroll the test made — the guard that found the Sheet's flutter (2026-11-03) lives in
 *  design.fixture.ts since Rank became its second caller; this spec reads it on its own sheet. */
const settled = (page: Page) => settledSheet(page, SHEET)

/** A box's place and width (not its height): what a face press may not move. */
const place = (b: [number, number, number, number] | null) => (b === null ? null : [b[0], b[1], b[2]])

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`History is a page — ${locale}`, () => {
    test.use({ locale })

    for (const glass of DESIGN_GLASSES) {
      test(`every History face, at ${glass.width}×${glass.height}: the glass used, the side used, the hierarchy, no overlap, no trap`, async ({ page, request, baseURL }) => {
        test.setTimeout(900_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await open(page, glass)

        const failures: string[] = []
        let rowsMet = 0
        let figuresMet = 0
        for (const [i, face] of FACES.entries()) {
          await openFace(page, i)
          const where = `${locale} ${face.name} @${glass.width}×${glass.height}`
          const d = await readDesign(page, { sheet: SHEET, figureIds: FIGURES, rowIds: ROWS })
          const flat = await readGlass(page, 'ledger-list', 'ledger-row', SHEET)
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

          // (c) THE HIERARCHY — the face's net at 24 px over a 13-px label; a list row 52 px and no wider than 36 rem
          if (d.figures.length === 0) failures.push(`${where}: (c) the record has no key figure (${FIGURES.join(', ')})`)
          for (const f of d.figures) {
            figuresMet++
            if (f.font < 24) failures.push(`${where}: (c) the figure ${f.id} is ${f.font} px — the law is 24`)
            if (f.label !== null && f.label < 13) failures.push(`${where}: (c) the label of ${f.id} is ${f.label} px — the law is 13`)
          }
          const short = d.rows.filter((r) => r.h < 52 - 0.5)
          const wide = d.rows.filter((r) => r.w > ROW_MAX_REM * 16 + 1)
          rowsMet += d.rows.length
          // the fixture is live: every face serves its share, so the count is a number and not "some"
          if (d.rows.length !== face.served) failures.push(`${where}: (c) ${d.rows.length} rows on the face; the played world serves ${face.served}`)
          if (short.length > 0) failures.push(`${where}: (c) ${short.length} list rows are under 52 px — the shortest is a ${short[0].id} row of ${Math.round(Math.min(...short.map((r) => r.h)))}`)
          if (wide.length > 0) failures.push(`${where}: (c) ${wide.length} list rows are wider than ${ROW_MAX_REM} rem — the widest is a ${wide[0].id} row of ${Math.round(Math.max(...wide.map((r) => r.w)))} px`)

          // (e) THE SIDE IS USED — from 1,024 the record's figures stand in the side column; below it they are there, after the list
          const blocks = await page.evaluate(IN_SIDE, { sheet: SHEET, ids: SIDE })
          for (const b of blocks) {
            if (!b.found) failures.push(`${where}: (e) the page has no ${b.id} block`)
            else if (glass.width >= 1024 && !b.inSide) failures.push(`${where}: (e) ${b.id} does not stand in the side column`)
          }
          if (glass.width >= 1024) {
            if (d.side === null) failures.push(`${where}: (e) the page has no side column`)
          } else {
            // (g) THE LIST COMES FIRST ON A PHONE — the first row stands on the first glass, before any scroll
            const first = await page.evaluate(FIRST_ROW, 'ledger-row')
            if (first === null) failures.push(`${where}: (g) the face has no ledger-row`)
            else if (first.bottom > first.glass + 1) failures.push(`${where}: (g) the first row stands ${Math.round(first.bottom - first.glass)} px under the glass's edge — a side block stands above the list`)
          }

          // (f) NO SCROLL TRAP — only the sheet scrolls
          for (const s of d.scrollers) failures.push(`${where}: (f) a box scrolls inside itself — ${s}`)

          // U3 — NOTHING WAS REMOVED: the list, its rows and days, the four face tabs, the count on the card
          for (const id of KEPT) {
            if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: U3 ${id} is gone`)
          }
          if ((await page.locator(SHEET).getByRole('tablist').first().getByRole('tab').count()) !== FACES.length) failures.push(`${where}: U3 the four face tabs are not all there`)
          if (!(await page.getByTestId('ledger-list').innerText()).includes(String(face.served))) failures.push(`${where}: U3 the card does not count its ${face.served} entries`)
          // U5 — cut text carries its full text; overlaps are in phoneLaws
        }

        // the law lines, printed before any gate: a red on a build with no key figure still says which laws it broke
        if (failures.length > 0) console.log(`LAWS ${locale} @${glass.width}×${glass.height}: ${failures.length} lines\n  ${failures.join('\n  ')}`)
        // NON-VACUITY: the walk measured the key figure on every face and the rows of every face
        expect(figuresMet, 'the walk measured no key figure — did the Money card render?').toBe(FACES.length)
        expect(rowsMet, 'the walk measured almost no list rows — did the list render?').toBe(FACES.reduce((n, f) => n + f.served, 0))
        expect(failures, 'History is not the page the owner asked for').toEqual([])
      })
    }
  })
}

// (d) A TRAY OPENED FROM A ROW MOVES NOTHING BEHIND IT; from 1,024 it stands over the SIDE column — same x, same width.
// And A FACE PRESSED SELECTS (owner rows 6, 15, 25: *"Pressing a control SELECTS. It never collapses, re-flows, replaces or
// destroys the surface it was pressed on"*): the list narrows to the face's entries and the strip, the list card and (from 1,024)
// the side's cards stand where they stood — the list's rows are the only thing that changed.
for (const glass of DESIGN_GLASSES) {
  test(`a report's tray moves nothing behind it and stands over the side column; a face pressed selects, at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await open(page, glass)
    const rows = page.getByTestId('ledger-row')
    await expect(rows).toHaveCount(FACES[0].served)
    // a row that opens something is a real button; the others are not
    const withReport = page.locator('button[data-testid="ledger-row"]')
    expect(await withReport.count(), 'the played feed has voyage reports').toBeGreaterThan(0)
    const ids = ['ledger-list', ...SIDE]
    // bring the row under the finger FIRST, then measure: a scroll the browser makes to reach a control is not a move
    await withReport.first().scrollIntoViewIfNeeded()
    await settled(page)
    const before = await boxesOf(page, SHEET, ids)
    const side = (await readDesign(page, { sheet: SHEET, figureIds: [], rowIds: [] })).side

    await withReport.first().click()
    const tray = page.getByTestId('ledger-report')
    await expect(tray).toBeVisible()
    await expect(tray).toContainText(/sailed|winds|losses/i)
    await page.waitForTimeout(500)
    expect(await boxesOf(page, SHEET, ids), "a row's press moved the page behind its tray").toEqual(before)
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
    await expect(rows).toHaveCount(FACES[0].served)

    // A FACE PRESSED SELECTS. The strip and the list card keep their place and width (the list is as tall as its entries, so its
    // height follows the face by design); from 1,024 the side's cards keep theirs too (the Money and Biggest figures follow the face,
    // their cards do not move; By kind is the record's shape and lights the face's row).
    await page.locator(SHEET).evaluate((e) => e.scrollTo(0, 0))
    await settled(page)
    const places = async () => {
      const boxes = await boxesOf(page, SHEET, ids)
      return { strip: await page.evaluate(STRIP, SHEET), blocks: Object.fromEntries(ids.map((id) => [id, place(boxes[id])])) }
    }
    const held = await places()
    expect(held.strip, 'the sheet has no face strip').not.toBeNull()
    await openFace(page, 2)
    await expect(rows).toHaveCount(FACES[2].served)
    await expect(page.getByTestId('ledger-list')).toContainText(String(FACES[2].served))
    const now = await places()
    if (glass.width >= 1024) expect(now, 'pressing a face moved the strip, the list card or the side').toEqual(held)
    else expect({ strip: now.strip, list: now.blocks['ledger-list'] }, 'pressing a face moved the strip or the list card').toEqual({ strip: held.strip, list: held.blocks['ledger-list'] })
    // the By kind board still names every kind — the face narrows the list, not the record's shape
    expect(await page.locator('[data-testid="ledger-kinds"] [data-row-line]').count(), 'the By kind board lost its rows under a face').toBeGreaterThanOrEqual(3)
    await openFace(page, 0)
    await expect(rows).toHaveCount(FACES[0].served)
  })
}

// THE YOUNG WORLD (kept from the unfold spec): one entry on the page, whole in its card, and a face with nothing says so
test('a young world: one entry on the page, its figures beside it, and a face with nothing says so', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, { width: 1280, height: 800 }, false)

  const rows = page.getByTestId('ledger-row')
  await expect(rows).toHaveCount(1)
  await expect(page.getByTestId('ledger-list')).toBeVisible()
  const m = await readGlass(page, 'ledger-list', 'ledger-row', SHEET)
  expect(m.rows.whole, 'the one entry is not whole in its card').toBe(1)
  for (const id of SIDE) await expect(page.getByTestId(id), `${id} is not on the young page`).toBeVisible()
  await openFace(page, 1)
  await expect(rows).toHaveCount(0)
  await expect(page.getByTestId('ledger-list').getByText(/Nothing/)).toHaveCount(1)
})
