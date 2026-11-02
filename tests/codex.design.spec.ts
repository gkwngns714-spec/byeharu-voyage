import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, readGlass } from './unfold.fixture'
import { DESIGN_GLASSES, ROW_MAX_REM, boxesOf, readDesign, trayBox } from './design.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CODEX IS A PAGE — the owner's design order, measured on every face at five glasses, in English and Korean (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.) Stats took the page first
// (tests/stats.design.spec.ts, PR #466); the Codex is the second screen on it, and this file holds it to the SAME laws, read by
// the SAME apparatus (tests/design.fixture.ts) — a second measuring apparatus would drift.
//
// THIS FILE REPLACES `codex.unfold.spec.ts`. That spec was written on 2026-11-02 for the order *"make it compact showing
// everything possible"* (rows 249-260) and held the packed design: U2 "the page and the Sheet never scroll; the list scrolls
// inside its panel" and U1 "N whole rows of the list in the panel before a press". Row 267 reverses exactly that — *"too
// packed"* — so U1 and U2 are gone. What it was right about stands here, restated: U3 (nothing removed: the four faces, the
// search, the filters), U5 (no overlap; and, stricter than the shared law because the catalogue's names are static, NO text
// in a list card is cut at all), U8 (a press opens one item's tray and closing it leaves the list; the search narrows; a
// filter picks).
//
// THE LAWS (docs/dev-log/2026-11-02-codex-design.md; screenLayout.ts "THE PAGE"), at 1,440×900, 1,280×800, 1,024×768,
// 390×844 and 320×640:
//   (a) USE THE WIDTH. From 1,024 px the content block (the visible text of the sheet, leftmost to rightmost) is centred — the
//       band empty at its right is no wider than the margin at its left, so nothing is kept clear for a tray that is shut — and
//       from 1,280 it spans at least 80 % of the glass.
//   (b) THE DEFECT RULES STAND: no sideways scroll, no two text or figure boxes crossing, no text narrower than 1.4 × its font
//       size (the one-letter wrap), no cut text without its full text, every control at least 44 × 44, the document flat.
//   (c) THE HIERARCHY: a list row at least 52 px — and no list row wider than 36 rem, so the 2026-09-13 complaint ("too much
//       blank space" between a name and its price) cannot come back. (The Codex has no key figure of its own: a catalogue's
//       figures are its rows'.)
//   (d) A TRAY OPENED FROM A ROW MOVES NOTHING BEHIND IT, and from 1,024 it slides over the page's SIDE column — the same x and
//       width — because the side is the tray's column.
//   (e) THE SIDE IS USED: every face has a second block, and from 1,024 it stands in the side column (the Goods' kind and
//       rarity choices, the Ships' and Captains' boards, the local rulers) — a page never has an empty band at its right.
//   (f) NO SCROLL TRAP: nothing but the sheet scrolls — the page scrolls, a list never scrolls inside itself.
//   (g) THE LIST COMES FIRST ON A PHONE (the review of the first cut, 2026-11-02: the Goods' kind and rarity grids filled the whole
//       first glass at 390×844 and "Goods 629" stood at its bottom edge). Below the split the face's FIRST ROW stands on the first
//       glass, before any scroll: no side block (a choice grid, a board) stands above the list there — the Goods' kind and rarity
//       are two pickers in the list card's header (`filter-pick-kind`, `filter-pick-rarity`, the same picker the Ships and Captains
//       faces hold their filters in, driven by the one state the grids drive from 1,024), the boards stand after the list.
//
// WHICH WERE RED BEFORE: the same file, run against the build of origin/main 856a9830 (the packed column), fails (a) at
// every glass of 1,024 and up, (c) (a pressable row is 44 px, a nation's row 33), (d)'s side column, (e) (no side column, no
// second block) and (f) (the list scrolls inside itself) — at every glass, both languages; (b), the no-move half of (d), U3,
// U5 and U8 were already green there: they are guards, kept. (g) was red on the first cut of this branch (8445610e, measured:
// the first Goods row 69 px under the glass's edge at 390×844 and 327 at 320×640, the first Ships row 247 / 573, the first
// Captains row 65 / 299, and no kind or rarity picker on a phone — 6 of 6 phone tests) and is green on the second. The numbers
// are in the dev-log.

const ROWS = ['good-tile', 'ship-tile', 'officer-tile', 'nation-row'] as const

/** The four faces, by their place in the tab strip (a Korean strip has other words), the panel and row each stands, what the
 *  old faces had by test id — still on the face (U3) — the face's second block, which stands in the side from 1,024 (e), and
 *  what stands in its place below the split (`phone`: the Goods' pickers; a board face keeps its boards, after the list). */
const FACES = [
  { name: 'Goods', panel: 'codex-list', row: 'good-tile', kept: ['codex-search', 'good-kind'], side: ['codex-kinds', 'codex-rarity'], phone: ['goods-filters', 'filter-pick-kind', 'filter-pick-rarity'] },
  { name: 'Ships', panel: 'codex-list', row: 'ship-tile', kept: ['codex-search', 'ship-filters'], side: ['codex-ships-cargo', 'codex-ships-speed'], phone: ['codex-ships-cargo', 'codex-ships-speed'] },
  { name: 'Captains', panel: 'codex-list', row: 'officer-tile', kept: ['codex-search', 'captain-filters'], side: ['codex-captains-grades', 'codex-captains-roles'], phone: ['codex-captains-grades', 'codex-captains-roles'] },
  { name: 'Nations', panel: 'nation-great', row: 'nation-row', kept: ['codex-search', 'nation-rows', 'nation-great', 'nation-rulers'], side: ['nation-rulers'], phone: ['nation-rulers'] },
] as const

/** The first row's box on the glass (viewport px), or null. Self-contained, shipped into the page. */
const FIRST_ROW = (id: string) => {
  const e = document.querySelector(`[data-testid="${id}"]`)
  if (!e) return null
  const r = e.getBoundingClientRect()
  return { top: r.top, bottom: r.bottom, glass: innerHeight }
}

const SHEET = '[data-testid="codex"]'

/** Every box in the sheet's list cards whose text is clipped (ellipsis or hidden overflow) — none may be (U5, strict). Self-contained:
 *  it is shipped into the page. */
const CLIPPED = (sheet: string) => {
  const root = document.querySelector(sheet)
  if (!root) return ['no sheet']
  return [...root.querySelectorAll('[data-list-panel] *')]
    .filter((e): e is HTMLElement => {
      if (!(e instanceof HTMLElement) || e.closest('[data-tray-mode]') !== null || e.clientWidth <= 2 || !(e.textContent ?? '').trim()) return false
      const s = getComputedStyle(e)
      return (s.overflowX === 'hidden' || s.overflowX === 'clip' || s.textOverflow === 'ellipsis') && e.scrollWidth > e.clientWidth + 1
    })
    .map((e) => `${e.tagName.toLowerCase()} "${(e.textContent ?? '').trim().slice(0, 30)}" ${e.scrollWidth}/${e.clientWidth}`)
}

/** The side column's blocks: which of the named test ids stand INSIDE `[data-page-side]`. Self-contained, shipped into the page. */
const IN_SIDE = ({ sheet, ids }: { sheet: string; ids: readonly string[] }) => {
  const root = document.querySelector(sheet)
  const side = root?.querySelector('[data-page-side]') ?? null
  return ids.map((id) => ({ id, found: root?.querySelector(`[data-testid="${id}"]`) !== null && root?.querySelector(`[data-testid="${id}"]`) !== undefined, inSide: side?.querySelector(`[data-testid="${id}"]`) !== null && side?.querySelector(`[data-testid="${id}"]`) !== undefined }))
}

async function open(page: Page, glass: { width: number; height: number }) {
  await page.setViewportSize(glass)
  await page.goto('compendium')
  await ready(page)
  await expect(page.getByTestId('codex')).toBeVisible()
}

async function openFace(page: Page, index: number) {
  await page.locator(SHEET).getByRole('tablist').first().getByRole('tab').nth(index).click()
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
  await page.waitForTimeout(700)
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`the Codex is a page — ${locale}`, () => {
    test.use({ locale })

    for (const glass of DESIGN_GLASSES) {
      test(`every Codex face, at ${glass.width}×${glass.height}: the glass used, the side used, the hierarchy, no overlap, no cut text, no trap`, async ({ page, request, baseURL }) => {
        test.setTimeout(900_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await open(page, glass)

        const failures: string[] = []
        let rowsMet = 0
        for (const [i, face] of FACES.entries()) {
          await openFace(page, i)
          const where = `${locale} ${face.name} @${glass.width}×${glass.height}`
          const d = await readDesign(page, { sheet: SHEET, figureIds: [], rowIds: ROWS })
          const flat = await readGlass(page, face.panel, face.row, SHEET)
          console.log(
            `DESIGN ${where}: block ${d.block ? `${Math.round(d.block.left)}..${Math.round(d.block.right)}` : '-'} (text ${d.span ? `${Math.round(d.span.left)}..${Math.round(d.span.right)}` : '-'}) · rows ${d.rows.length}x${d.rows.length ? Math.round(Math.min(...d.rows.map((r) => r.h))) : '-'} (widest ${d.rows.length ? Math.round(Math.max(...d.rows.map((r) => r.w))) : '-'}) · cards ${d.cards.length} · side ${d.side ? Math.round(d.side.w) : '-'} · scrollers ${d.scrollers.length} · sheet ${flat.sheet?.sh}/${flat.sheet?.ch}`,
          )

          // (a) USE THE WIDTH — from 1,024 the block is centred (nothing kept clear at the right), from 1,280 it spans 80 % of the glass.
          // The block is the text WIDENED TO THE CARDS' EDGES (design.fixture.ts `block`): a card at the margin is content at the margin,
          // though its words end at its padding (a kind grid's words are centred in their cells; a board's figure hugs its label). On the
          // packed column of origin/main the one list panel is the block, 132..884 at 1,440 — the law is red there by either reading.
          if (d.block === null) failures.push(`${where}: (a) the sheet has no visible text`)
          else if (glass.width >= 1024) {
            const band = d.glass.w - d.block.right
            const share = (d.block.right - d.block.left) / d.glass.w
            if (band > d.block.left + 2) failures.push(`${where}: (a) ${Math.round(band)} px are empty at the right of the content and ${Math.round(d.block.left)} at its left — a column is kept clear for a tray`)
            if (glass.width >= 1280 && share < 0.8) failures.push(`${where}: (a) the content spans ${(share * 100).toFixed(0)} % of the glass — the law is 80 %`)
          }

          // (b) THE DEFECT RULES: overlap, one-letter wrap, cut text, sideways scroll, the 44-px floor — and the document is flat (the SHEET scrolls)
          // (the fixture numbers its laws a-d; they are all (b) here — the defect rules of the 2026-11-02 sweep)
          failures.push(...phoneLaws(where, flat).map((m) => m.replace(/: \([abcd]\) /, ': (b) ')))
          if (flat.doc.sh > flat.doc.ch + 1) failures.push(`${where}: (b) the document scrolls ${flat.doc.sh}/${flat.doc.ch}`)
          if (flat.sheet !== null && flat.sheet.top > 0) failures.push(`${where}: (b) the Sheet arrived scrolled`)
          for (const c of d.smallControls) failures.push(`${where}: (b) a control under 44 px — ${c}`)

          // (c) THE HIERARCHY — a list row 52 px and no wider than 36 rem (a row is counted once per rule: the worst is named, the rest are a number)
          const short = d.rows.filter((r) => r.h < 52 - 0.5)
          const wide = d.rows.filter((r) => r.w > ROW_MAX_REM * 16 + 1)
          rowsMet += d.rows.length
          if (d.rows.length === 0) failures.push(`${where}: (c) the face has no ${face.row} rows`)
          if (short.length > 0) failures.push(`${where}: (c) ${short.length} list rows are under 52 px — the shortest is a ${short[0].id} row of ${Math.round(Math.min(...short.map((r) => r.h)))}`)
          if (wide.length > 0) failures.push(`${where}: (c) ${wide.length} list rows are wider than ${ROW_MAX_REM} rem — the widest is a ${wide[0].id} row of ${Math.round(Math.max(...wide.map((r) => r.w)))} px`)

          // (e) THE SIDE IS USED — from 1,024 the face's second block stands in the side column; below it, what stands in its place is there
          if (glass.width >= 1024) {
            const blocks = await page.evaluate(IN_SIDE, { sheet: SHEET, ids: face.side })
            for (const b of blocks) {
              if (!b.found) failures.push(`${where}: (e) the face has no ${b.id} block`)
              else if (!b.inSide) failures.push(`${where}: (e) ${b.id} does not stand in the side column`)
            }
            if (d.side === null) failures.push(`${where}: (e) the page has no side column`)
          } else {
            for (const id of face.phone) {
              if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: (e) the face has no ${id} on a phone`)
            }
            // (g) THE LIST COMES FIRST ON A PHONE — the first row stands on the first glass, before any scroll
            const first = await page.evaluate(FIRST_ROW, face.row)
            if (first === null) failures.push(`${where}: (g) the face has no ${face.row} row`)
            else if (first.bottom > first.glass + 1) failures.push(`${where}: (g) the first ${face.row} row stands ${Math.round(first.bottom - first.glass)} px under the glass's edge — a side block stands above the list`)
          }

          // (f) NO SCROLL TRAP — only the sheet scrolls
          for (const s of d.scrollers) failures.push(`${where}: (f) a box scrolls inside itself — ${s}`)

          // U3 — NOTHING WAS REMOVED
          for (const id of face.kept) {
            if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: U3 ${id} is gone`)
          }
          // U5 (strict) — no text in a list card is cut at all: the catalogue's names are static and the rows were built for them
          for (const c of await page.evaluate(CLIPPED, SHEET)) failures.push(`${where}: U5 text is cut in a list card ${c}`)
        }

        // NON-VACUITY: the walk measured a list's rows on every face
        expect(rowsMet, 'the walk measured almost no list rows — did the lists render?').toBeGreaterThan(40)
        expect(failures, 'the Codex is not the page the owner asked for').toEqual([])
      })
    }
  })
}

// (d) A TRAY OPENED FROM A ROW MOVES NOTHING BEHIND IT; from 1,024 it stands over the SIDE column — same x, same width.
// And a KIND pressed in the side SELECTS: the list narrows, and the side's own cards and the search stand where they stood.
for (const glass of DESIGN_GLASSES) {
  test(`a good's tray moves nothing behind it and stands over the side column; a kind pressed selects, at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await open(page, glass)
    const goods = page.getByTestId('good-tile')
    await expect.poll(() => goods.count(), { timeout: 60_000 }).toBeGreaterThan(100)
    const ids = ['codex-list', 'codex-kinds', 'codex-rarity', 'codex-search', 'good-kind', 'good-tile']
    // bring the first row under the finger FIRST, then measure: a scroll the browser makes to reach a control is not a move
    await goods.first().scrollIntoViewIfNeeded()
    await page.waitForTimeout(400)
    const before = await boxesOf(page, SHEET, ids)
    const side = (await readDesign(page, { sheet: SHEET, figureIds: [], rowIds: [] })).side
    const total = await goods.count()
    const first = (await goods.first().innerText()).split('\n')[0]
    await goods.first().click()
    const tray = page.getByTestId('good-tray')
    await expect(tray).toBeVisible()
    await expect(tray).toContainText(first.trim().slice(0, 5))
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
    expect(await goods.count(), 'closing the tray changed the list').toBe(total)

    // A KIND PRESSED SELECTS (owner rows 6, 15, 25: *"Pressing a control SELECTS. It never collapses, re-flows, replaces or
    // destroys the surface it was pressed on"*): the list holds that kind alone, the control says it is on, and the side's cards
    // (the pickers' bar, on a phone) and the search are exactly where they were — the list is the only thing that changed.
    if (glass.width >= 1024) {
      const chips = page.locator('[data-testid="codex-kinds"] [data-testid^="filter-chip-"]')
      expect(await chips.count(), 'the Kind card offers no kinds').toBeGreaterThan(5)
      const chip = chips.nth(1)
      await chip.scrollIntoViewIfNeeded()
      await page.waitForTimeout(300)
      const still = ['codex-kinds', 'codex-rarity', 'codex-search']
      const held = await boxesOf(page, SHEET, still)
      await chip.click()
      await expect(chip).toHaveAttribute('aria-pressed', 'true')
      await expect.poll(() => goods.count(), { timeout: 15_000 }).toBeLessThan(total)
      expect(await goods.count(), 'the kind left no goods').toBeGreaterThan(0)
      expect(await page.getByTestId('good-kind').count(), 'one kind, one heading').toBe(1)
      expect(await boxesOf(page, SHEET, still), 'pressing a kind moved the side or the search').toEqual(held)
      await chips.first().click()
      await expect.poll(() => goods.count(), { timeout: 15_000 }).toBe(total)
    } else {
      // (g) on a phone the kind is a picker in the list card's header — the same state the grid drives from 1,024
      const pick = page.getByTestId('filter-pick-kind')
      await expect(pick, 'the Goods face has no kind picker on a phone').toBeVisible()
      const options = await pick.locator('option').evaluateAll((os) => os.map((o) => (o as HTMLOptionElement).value))
      expect(options.length, 'the kind picker offers no kinds').toBeGreaterThan(5)
      // a compact picker is as wide as the word it shows (FilterBar: `field-sizing-content`), so the bar's WIDTH follows the choice
      // by design; its place and its height, and the search's whole box, must not
      const place = (b: Record<string, [number, number, number, number] | null>) => ({ search: b['codex-search'], bar: b['goods-filters'] === null ? null : [b['goods-filters'][0], b['goods-filters'][1], b['goods-filters'][3]] })
      const held = place(await boxesOf(page, SHEET, ['goods-filters', 'codex-search']))
      await pick.selectOption(options[1])
      await expect.poll(() => goods.count(), { timeout: 15_000 }).toBeLessThan(total)
      expect(await goods.count(), 'the kind left no goods').toBeGreaterThan(0)
      expect(await page.getByTestId('good-kind').count(), 'one kind, one heading').toBe(1)
      expect(place(await boxesOf(page, SHEET, ['goods-filters', 'codex-search'])), 'picking a kind moved the pickers or the search').toEqual(held)
      await pick.selectOption('all')
      await expect.poll(() => goods.count(), { timeout: 15_000 }).toBe(total)
    }
  })
}

// U8 — THE SEARCH NARROWS AND THE FILTERS PICK, on the page as on the panel (kept from codex.unfold.spec.ts)
test('the search narrows the goods and clearing it brings them back; a Ships picker narrows the hulls; a hull opens its tray', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, { width: 1280, height: 800 })
  const goods = page.getByTestId('good-tile')
  await expect.poll(() => goods.count(), { timeout: 60_000 }).toBeGreaterThan(100)
  const total = await goods.count()
  await page.getByTestId('codex-search').fill('amber')
  await expect.poll(() => goods.count(), { timeout: 15_000 }).toBeLessThan(total)
  expect(await goods.count()).toBeGreaterThan(0)
  await page.getByTestId('codex-search').fill('')
  await expect.poll(() => goods.count(), { timeout: 15_000 }).toBe(total)

  // SHIPS: the pickers stand over the rows, each naming itself; one picked narrows the list; a row opens its tray and closing it leaves the list
  await openFace(page, 1)
  const ships = page.getByTestId('ship-tile')
  await expect.poll(() => ships.count(), { timeout: 60_000 }).toBeGreaterThan(10)
  const shipTotal = await ships.count()
  const pick = page.getByTestId('filter-pick-size')
  await expect(pick).toBeVisible()
  const options = await pick.locator('option').evaluateAll((os) => os.map((o) => (o as HTMLOptionElement).value))
  await pick.selectOption(options[1])
  await expect.poll(() => ships.count(), { timeout: 15_000 }).toBeLessThan(shipTotal)
  // the boards follow the filter: no board names a hull the filter left out
  const named = await page.locator('[data-testid="codex-ships-cargo"] [data-row-cell="label"]').allInnerTexts()
  const shown = new Set((await ships.locator('[data-row-cell="label"]').allInnerTexts()).map((s) => s.trim()))
  expect(named.length, 'the cargo board is empty under a filter that left hulls').toBeGreaterThan(0)
  for (const n of named) expect(shown.has(n.trim()), `the cargo board names ${n}, which the filter left out`).toBe(true)
  await pick.selectOption('all')
  await expect.poll(() => ships.count(), { timeout: 15_000 }).toBe(shipTotal)
  await ships.first().click()
  await expect(page.getByTestId('ship-tray')).toBeVisible()
  await page.getByTestId('tray-close').click()
  await expect(page.getByTestId('ship-tray')).toHaveCount(0)
  expect(await ships.count(), 'closing the tray changed the list').toBe(shipTotal)
})
