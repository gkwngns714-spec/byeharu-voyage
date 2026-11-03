import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, playedWorld, readGlass } from './unfold.fixture'
import { DESIGN_GLASSES, ROW_MAX_REM, boxesOf, readDesign, settled as settledSheet, trayBox } from './design.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ROUTES IS A PAGE — the owner's design order, measured under every order at five glasses, in English and Korean (2026-11-03)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.) Stats took the page first
// (tests/stats.design.spec.ts, PR #466), the Codex second (tests/codex.design.spec.ts, PR #473), History third
// (tests/history.design.spec.ts, PR #474), Rank fourth (tests/rank.design.spec.ts, PR #476); Routes is the fifth screen on it,
// and this file holds it to the SAME laws, read by the SAME apparatus (tests/design.fixture.ts) — a second measuring
// apparatus would drift.
//
// THIS FILE REPLACES `routes.unfold.spec.ts`. That spec was written on 2026-11-02 for the order *"make it compact showing
// everything possible"* (rows 249-260) and held the packed design: U2 "the page and the Sheet never scroll; the board scrolls
// inside its panel" and U1 "the panel stands inside the glass with N whole lanes before any press". Row 267 reverses exactly
// that — *"too packed"* — so U1 and U2 are gone. What it was right about stands here, restated: U3 (nothing removed: the three
// orders, the refresh button on the 44-px floor, the lanes, the count, the empty state), U5 (no overlap; cut text carries its
// full text; no placeholder dash in a lane), U8 (a press on a lane opens THAT lane's tray and closing it leaves the board; an
// order re-ranks the lanes and moves neither the title nor the strip; a lane the server has no figure for says so in a word),
// and the young world (no lane yet — the board says so, the orders and the button stand).
//
// TWO WORLDS, BOTH READ, NO SKIP (kept from the unfold spec). The canary a CI run boots serves NO lane (its traders are off);
// the owner's serves up to `route_board_max`. The laws are about the lanes, so the glass walks and the tray proof run on the
// PLAYED world the fixture builds at run time (tests/unfold.fixture.ts: this build's own image with `world.route_board`
// replaced by forty lanes, two of them hers), and the empty board has its own test on the canary.
//
// THE LAWS (docs/dev-log/2026-11-03-routes-design.md; screenLayout.ts "THE PAGE"), at 1,440×900, 1,280×800, 1,024×768,
// 390×844 and 320×640:
//   (a) USE THE WIDTH. From 1,024 px the content block (the visible text widened to the cards' edges) is centred — the band
//       empty at its right is no wider than the margin at its left, so nothing is kept clear for a tray that is shut — and from
//       1,280 it spans at least 80 % of the glass.
//   (b) THE DEFECT RULES STAND: no sideways scroll, no two text or figure boxes crossing, no text narrower than 1.4 × its font
//       size (the one-letter wrap), no cut text without its full text, every control at least 44 × 44, the document flat.
//   (c) THE HIERARCHY: the board's key figure (the lanes on it) at least 24 px with its label at least 13; a list row at least
//       52 px — and no list row wider than 36 rem, so the 2026-09-13 complaint ("too much blank space" between a name and its
//       figure) cannot come back.
//   (d) A TRAY OPENED FROM A ROW MOVES NOTHING BEHIND IT, and from 1,024 it slides over the page's SIDE column — the same x and
//       width — because the side is the tray's column.
//   (e) THE SIDE IS USED: the board has its figures as graphics — the Overview card, the Top lanes board, the By company
//       board — and from 1,024 they stand in the side column; a page never has an empty band at its right.
//   (f) NO SCROLL TRAP: nothing but the sheet scrolls — the page scrolls, a list never scrolls inside itself.
//   (g) THE LIST COMES FIRST ON A PHONE (the Codex's lesson, 2026-11-02): below the split the first lane stands on the first
//       glass, before any scroll — no side card stands above the list there. (Routes has no picker: its orders are a segmented
//       control, whose cells name themselves; the "a picker reads its name" law of the Codex has nothing to read here.)
//
// WHICH WERE RED BEFORE: the same file, run against the build of origin/rank-design a84db57b (the packed column), fails (a) at
// every glass of 1,024 and up, (c) (no key figure; a lane 44 px; rows 728 px wide), (d)'s side column and its board, (e) (no side
// column, no Overview, no Top lanes, no By company) and (f) (the board scrolls inside its panel) — both languages; (b), the
// no-move half of (d), (g), U3, U5 and U8 were already green there: they are guards, kept. The numbers are in the dev-log.

const SHEET = '[data-testid="routes"]'
const ROWS = ['route-lane'] as const
const FIGURES = ['routes-lanes'] as const
/** The board's three figure blocks — in the side from 1,024, after the list below it (e). */
const SIDE = ['routes-overview', 'routes-top', 'routes-companies'] as const
/** What the old screen had by test id — still on the page (U3). */
const KEPT = ['routes-list', 'route-lane', 'routes-refresh'] as const

/** The fixture's board: forty lanes served (of a hundred and twenty), two of them hers. */
const SERVED = 40

/** The three orders, by their place in the strip (a Korean strip has other words). */
const ORDERS = ['Distance', 'Earnings', 'Calls'] as const

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

/** The order strip's box (the one tablist of the sheet), rounded, in sheet coordinates. Self-contained, shipped into the page. */
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
  await page.goto('routes')
  await ready(page)
  await expect(page.getByTestId('routes')).toBeVisible()
  await expect(page.getByTestId('routes-list')).toBeVisible({ timeout: 60_000 })
}

/** Press an order by its place in the strip and let the list re-rank. */
async function openOrder(page: Page, index: number) {
  await page.locator(SHEET).getByRole('tablist').first().getByRole('tab').nth(index).click()
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
  await page.waitForTimeout(600)
}

const settled = (page: Page) => settledSheet(page, SHEET)

/** A box's place and width (not its height): what an order press may not move. */
const place = (b: [number, number, number, number] | null) => (b === null ? null : [b[0], b[1], b[2]])

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`Routes is a page — ${locale}`, () => {
    test.use({ locale })

    for (const glass of DESIGN_GLASSES) {
      test(`the Routes board under every order, at ${glass.width}×${glass.height}: the glass used, the side used, the hierarchy, no overlap, no trap`, async ({ page, request, baseURL }) => {
        test.setTimeout(900_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await open(page, glass)

        const failures: string[] = []
        let rowsMet = 0
        let figuresMet = 0
        for (const [i, order] of ORDERS.entries()) {
          await openOrder(page, i)
          const where = `${locale} ${order} @${glass.width}×${glass.height}`
          const d = await readDesign(page, { sheet: SHEET, figureIds: FIGURES, rowIds: ROWS })
          const flat = await readGlass(page, 'routes-list', 'route-lane', SHEET)
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

          // (c) THE HIERARCHY — the board's key figure at 24 px over a 13-px label; a lane 52 px and no wider than 36 rem
          if (d.figures.length === 0) failures.push(`${where}: (c) the board has no key figure (${FIGURES.join(', ')})`)
          for (const f of d.figures) {
            figuresMet++
            if (f.font < 24) failures.push(`${where}: (c) the figure ${f.id} is ${f.font} px — the law is 24`)
            if (f.label !== null && f.label < 13) failures.push(`${where}: (c) the label of ${f.id} is ${f.label} px — the law is 13`)
          }
          const short = d.rows.filter((r) => r.h < 52 - 0.5)
          const wide = d.rows.filter((r) => r.w > ROW_MAX_REM * 16 + 1)
          rowsMet += d.rows.length
          // the fixture is live: the board serves its forty, so the count is a number and not "some"
          if (d.rows.length !== SERVED) failures.push(`${where}: (c) ${d.rows.length} lanes on the board; the played world serves ${SERVED}`)
          if (short.length > 0) failures.push(`${where}: (c) ${short.length} lanes are under 52 px — the shortest is ${Math.round(Math.min(...short.map((r) => r.h)))}`)
          if (wide.length > 0) failures.push(`${where}: (c) ${wide.length} lanes are wider than ${ROW_MAX_REM} rem — the widest is ${Math.round(Math.max(...wide.map((r) => r.w)))} px`)

          // (e) THE SIDE IS USED — from 1,024 the board's figures stand in the side column; below it they are there, after the list
          const blocks = await page.evaluate(IN_SIDE, { sheet: SHEET, ids: SIDE })
          for (const b of blocks) {
            if (!b.found) failures.push(`${where}: (e) the page has no ${b.id} block`)
            else if (glass.width >= 1024 && !b.inSide) failures.push(`${where}: (e) ${b.id} does not stand in the side column`)
          }
          if (glass.width >= 1024) {
            if (d.side === null) failures.push(`${where}: (e) the page has no side column`)
          } else {
            // (g) THE LIST COMES FIRST ON A PHONE — the first lane stands on the first glass, before any scroll
            const first = await page.evaluate(FIRST_ROW, 'route-lane')
            if (first === null) failures.push(`${where}: (g) the board has no route-lane`)
            else if (first.bottom > first.glass + 1) failures.push(`${where}: (g) the first lane stands ${Math.round(first.bottom - first.glass)} px under the glass's edge — a side block stands above the list`)
          }

          // (f) NO SCROLL TRAP — only the sheet scrolls
          for (const s of d.scrollers) failures.push(`${where}: (f) a box scrolls inside itself — ${s}`)

          // U3 — NOTHING WAS REMOVED: the list and its lanes, the refresh button on the 44-px floor, the three orders, the count on the card,
          // the read caption on the title line
          for (const id of KEPT) {
            if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: U3 ${id} is gone`)
          }
          if ((await page.locator(SHEET).getByRole('tablist').first().getByRole('tab').count()) !== ORDERS.length) failures.push(`${where}: U3 the three orders are not all there`)
          const count = await page.getByTestId('routes-list').locator('[data-list-count]').innerText().catch(() => '')
          if (!count.includes(String(SERVED))) failures.push(`${where}: U3 the card does not count its ${SERVED} lanes (reads "${count}")`)
          const header = (await page.locator(SHEET).locator('[data-testid="sheet-header"]').innerText()).trim()
          const word = (await page.locator(SHEET).locator('[data-testid="sheet-header"] h1').innerText()).trim()
          if (header === word) failures.push(`${where}: U3 the read caption is gone from the title line`)
          // U5 — an absent ranked figure is a word, never a dash (cut text and overlaps are in phoneLaws)
          const values = await page.getByTestId('route-lane').locator('[data-row-cell="value"]').allInnerTexts()
          for (const [k, v] of values.entries()) if (/^[—–-]$/.test(v.trim())) failures.push(`${where}: U5 lane ${k} draws a dash`)
        }

        // the law lines, printed before any gate: a red on a build with no key figure still says which laws it broke
        if (failures.length > 0) console.log(`LAWS ${locale} @${glass.width}×${glass.height}: ${failures.length} lines\n  ${failures.join('\n  ')}`)
        // NON-VACUITY: the walk measured the key figure under every order and the lanes under every order
        expect(figuresMet, 'the walk measured no key figure — did the Overview card render?').toBe(ORDERS.length)
        expect(rowsMet, 'the walk measured almost no lanes — did the board render?').toBe(ORDERS.length * SERVED)
        expect(failures, 'Routes is not the page the owner asked for').toEqual([])
      })
    }
  })
}

// (d) A LANE'S TRAY MOVES NOTHING BEHIND IT; from 1,024 it stands over the SIDE column — same x, same width. U8 (kept from
// routes.unfold.spec.ts): a press on a lane opens THAT lane's tray, and closing it leaves the board as it was; an order re-ranks
// the lanes (the Calls order ranks the merchants' lanes by how many harbours they call at) and a lane the server has no figure
// for says so in a word, never a dash. And AN ORDER PRESSED SELECTS (owner rows 6, 15, 25: *"Pressing a control SELECTS. It
// never collapses, re-flows, replaces or destroys the surface it was pressed on"*): the strip, the list card and (from 1,024)
// the side's cards keep their place and width; the Top lanes board follows the order (law (e): the side is used).
for (const glass of DESIGN_GLASSES) {
  test(`a lane's tray moves nothing behind it and stands over the side column; an order pressed selects and re-ranks, at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await open(page, glass)
    const lanes = page.getByTestId('route-lane')
    await expect(lanes).toHaveCount(SERVED)
    const ids = ['routes-list', ...SIDE]

    // Bring the first lane under the finger FIRST, then measure: a scroll the browser makes to reach a control is not a move.
    const first = lanes.first()
    const name = (await first.locator('[data-row-cell="label"]').innerText()).trim()
    await first.scrollIntoViewIfNeeded()
    await settled(page)
    const before = await boxesOf(page, SHEET, ids)
    const side = (await readDesign(page, { sheet: SHEET, figureIds: [], rowIds: [] })).side
    await first.click()
    const tray = page.getByTestId('route-tray')
    await expect(tray).toBeVisible()
    await expect(tray, 'the tray is not the pressed lane').toContainText(name)
    await page.waitForTimeout(500)
    expect(await boxesOf(page, SHEET, ids), "a lane's press moved the page behind its tray").toEqual(before)
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
    await expect(lanes).toHaveCount(SERVED)

    // AN ORDER PRESSED SELECTS: the strip, the list card and (from 1,024) the side's cards hold their place and width; the lanes re-rank
    await page.locator(SHEET).evaluate((e) => e.scrollTo(0, 0))
    await settled(page)
    const places = async () => {
      const boxes = await boxesOf(page, SHEET, ids)
      return { strip: await page.evaluate(STRIP, SHEET), blocks: Object.fromEntries(ids.map((id) => [id, place(boxes[id])])) }
    }
    const held = await places()
    expect(held.strip, 'the sheet has no order strip').not.toBeNull()
    const title = await page.getByTestId('routes-list').getByRole('heading').first().boundingBox()

    // the Calls order ranks the merchants' lanes by how many harbours they call at, most first (hers lead the list)
    await openOrder(page, 2)
    const calls = await lanes.evaluateAll((els) =>
      els.map((e) => Number(((e.querySelector('[data-row-cell="value"]')?.textContent ?? '').match(/\d+/) ?? ['0'])[0])),
    )
    const merchants = calls.slice(2)
    expect(merchants, 'the merchants lanes are not ranked by calls').toEqual([...merchants].sort((a, b) => b - a))
    expect(await page.getByTestId('routes-list').getByRole('heading').first().boundingBox(), 'a re-rank moved the title').toEqual(title)
    const now = await places()
    if (glass.width >= 1024) expect(now, 'pressing an order moved the strip, the list card or the side').toEqual(held)
    else expect({ strip: now.strip, list: now.blocks['routes-list'] }, 'pressing an order moved the strip or the list card').toEqual({ strip: held.strip, list: held.blocks['routes-list'] })
    // THE TOP LANES BOARD FOLLOWS THE ORDER (e): its first bar carries the largest figure on the list (the list leads with HER
    // lanes, whatever their figure; the board ranks every lane together, so it is the figure that is compared, not the place)
    // bounded: a build with no board (the packed column) must say so, not wait for one
    const topFirst = (await page.locator('[data-testid="routes-top"] [data-row-cell="value"]').first().innerText({ timeout: 10_000 }).catch(() => '')).trim()
    expect(Number((topFirst.match(/\d+/) ?? ['-1'])[0]), `the Top lanes board does not lead with the most calls (reads "${topFirst}")`).toBe(Math.max(...calls))

    // the Earnings order: a lane with no closed lap yet says so in a word — it never draws a dash (the old board did)
    await openOrder(page, 1)
    const earned = await lanes.locator('[data-row-cell="value"]').allInnerTexts()
    expect(earned.some((v) => /^[—–-]$/.test(v.trim())), 'a lane draws a dash').toBe(false)
    expect(earned.some((v) => v.trim() === 'not yet'), 'a lane with no closed lap does not say so').toBe(true)
    await openOrder(page, 0)
    await expect(lanes).toHaveCount(SERVED)
  })
}

// THE YOUNG WORLD (kept from the unfold spec): no lane yet — the board says so, the three orders and the refresh button stand,
// and the board's figures stand beside it (reading 0, not a dash).
test('a young world: no lane yet — the board says so, the three orders and the refresh button stand, the figures beside it read 0', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, { width: 1280, height: 800 }, false)

  await expect(page.getByTestId('route-lane')).toHaveCount(0)
  await expect(page.getByTestId('routes-list').getByText(/No routes/)).toHaveCount(1)
  for (const order of ORDERS) await expect(page.getByRole('tab', { name: order, exact: true })).toHaveCount(1)
  const refresh = await page.getByTestId('routes-refresh').boundingBox()
  expect(refresh, 'no refresh button').not.toBeNull()
  expect(refresh!.height, 'the refresh button is under the 44-px floor').toBeGreaterThanOrEqual(43.5)
  expect(refresh!.width, 'the refresh button is under the 44-px floor').toBeGreaterThanOrEqual(43.5)
  for (const id of SIDE) await expect(page.getByTestId(id), `${id} is not on the young page`).toBeVisible()
  await expect(page.getByTestId('routes-lanes')).toContainText('0')
  const d = await readDesign(page, { sheet: SHEET, figureIds: FIGURES, rowIds: ROWS })
  expect(d.figures.map((f) => f.font), 'the young board has no 24-px key figure').toEqual([24])
  expect(d.scrollers, 'a box scrolls inside itself on the young page').toEqual([])
})
