import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { GLASSES, phoneLaws, readGlass, type Glass } from './unfold.fixture'
import { serveTwoFleets } from './twoFleets.fixture'
import { serveVeteranWorld, VETERAN_CAPTAINS, VETERAN_HULLS } from './manyFleets.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// FLEETS AND YOU GROW WITHOUT SCROLLING THE PAGE — the owner's law, measured with 2 hulls and with 8 (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"check everything, fix all, redo the design, make things unfolded, minimize scrolling, everything compact with full
// info."* (owner, 2026-11-01; docs/dev-log/2026-11-01-ui-unfold.md U1–U8; docs/dev-log/2026-11-02-sheets-grow.md.)
// The layout sweep of 2026-11-02 (row 5) built a veteran's world — the cap on fleets is EARNED (`fleet_max`) — and measured that
// FLEETS scrolled the PAGE 122 px at 390×844 and 326 px at 320×640, YOU 140 and 344 (476 and 1,050 with six captains), and that a
// company of two left two thirds of the glass empty. Both screens are now what the five unfolded screens are: figures over ONE list
// panel (src/components/ui/ListPanel.tsx) that takes the glass they leave and scrolls INSIDE itself.
//
//   U2  the document and the Sheet never scroll, and nothing scrolls sideways, at 390×844, 320×640 and 1280×800 — with two hulls
//       AND with eight; when the rows are longer than the panel, the PANEL scrolls (its last row comes into view) and the page
//       stays where it was;
//   U1  the panel stands inside the glass with at least min(rows, N) rows WHOLE before any press;
//   U3  nothing removed: every old test id is on the screen, with as many of them as the world has hulls and captains;
//   U5  no two text boxes cross, no sibling box overlaps another, no text stands one letter to a line, no row label is cut; a NAME is
//       never cut at all (2026-11-11: it is printed whole, on as many lines as it needs); every row of the data is at least 44 px tall;
//   U8  a press on a fleet opens her page and nothing behind it moves; a press on a captain opens her tray, and the tray stands
//       OUTSIDE the panel's scroller.
//
// 2026-11-04 (owner row 267, "everything is on left, too packed"): FLEETS left this file. Its half held the compaction — ONE panel that
// scrolls inside itself and fills the glass, "N rows whole in the panel", "the page never scrolls" — which row 267 reverses; the page's laws are
// tests/fleets.design.spec.ts. What stays here is what this file was right about and still holds: YOU's panel, a fleet's page opening without
// moving what is behind it, the 24-character name whole at 320, a fleet at sea.
// 2026-11-05 (row 267): YOU left this file's panel laws the same way — U1/U2 and the GROW walk of YOU (levels over ONE scrolling panel) are gone;
// the page's laws are tests/you.design.spec.ts. What stays of YOU: a captain's long name whole (it was cut and read by a press until 2026-11-11), her tray outside the list card.
//
// The two worlds are throwaway images built from this build's own (tests/twoFleets.fixture.ts, tests/manyFleets.fixture.ts). A
// spec may not skip for want of rows — CI fails any skipped test — so the rows are made, and the count of what stands is asserted:
// a world with one hull would pass every line below, and the first assertion refuses it.

type World = 'two' | 'veteran'
const WORLDS: Record<World, { serve: (page: Page) => Promise<void>; hulls: number; captains: number }> = {
  two: { serve: serveTwoFleets, hulls: 2, captains: 0 },
  veteran: {
    serve: serveVeteranWorld,
    hulls: VETERAN_HULLS,
    captains: VETERAN_CAPTAINS,
  },
}

async function open(page: Page, glass: Glass, world: World, route: string, sheet: string): Promise<void> {
  await page.setViewportSize(glass)
  await WORLDS[world].serve(page)
  await page.goto(route)
  await ready(page)
  await expect(page.getByTestId(sheet)).toBeVisible()
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
}

test('a press on a fleet opens her page and nothing behind it moves; Back leaves the panel as it was', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, GLASSES[0], 'veteran', 'fleets', 'fleets')
  await expect(page.getByTestId('fleet-row')).toHaveCount(VETERAN_HULLS)
  const boxes = async () =>
    page.evaluate(() => {
      const r = (e: Element | null) => (e ? JSON.stringify(e.getBoundingClientRect().toJSON()) : null)
      return {
        panel: r(document.querySelector('[data-testid="fleets-list"]')),
        first: r(document.querySelectorAll('[data-testid="fleet-row"]')[0] ?? null),
        second: r(document.querySelectorAll('[data-testid="fleet-row"]')[1] ?? null),
        // Fleets is a PAGE (2026-11-04, row 267): its list is a card that never scrolls inside itself, so the thing that could move
        // under a press is the page's own scroll — the Sheet and the document — not the card's `[data-list-body]`.
        scroll: [document.querySelector('[data-testid="fleets"]'), document.scrollingElement].map((e) => e?.scrollTop ?? null),
      }
    })
  const before = await boxes()
  await page.getByTestId('fleet-row').first().click()
  await expect(page.getByTestId('fleet-page')).toBeVisible()
  expect(await boxes(), 'a press on a fleet moved the panel or its rows').toEqual(before)
  await page.locator('[data-detail-back]').last().click()
  await expect(page.getByTestId('fleet-page')).toHaveCount(0)
  expect(await boxes(), 'closing her page moved the panel or its rows').toEqual(before)
})

// ── U5: A NAME IS NEVER CUT TO NOTHING, AND ONE THE GLASS DOES CUT IS READ BY A PRESS ────────────────────────────────────────────
// A fleet's name stands on the line with where she is. In port that is one short word; AT SEA it is "to Cape St Vincent · 22s", and
// beside it the name was left 16 px at 320×640 and 76 px at 390×844 — a cut with nothing left to read or press. The row's label now
// WRAPS: the two stand on one line while they fit, and when they do not the where line drops under the name.
test('FLEETS: the longest fleet name the chain allows stands whole at 320×640, the where line under it', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, GLASSES[1], 'veteran', 'fleets', 'fleets')
  const row = page.getByTestId('fleet-row').filter({ hasText: 'Nossa Senhora da Estrela' })
  await expect(row).toHaveCount(1)
  const name = row.locator('[data-name]').first()
  expect(await name.evaluate((el) => el.scrollWidth > el.clientWidth + 1), 'the 24-character name is cut at 320').toBe(false)
  const stack = await row.evaluate((el) => {
    const label = el.querySelector('[data-row-cell="label"]')!
    const [nameBox, whereBox] = [...label.firstElementChild!.children].map((c) => c.getBoundingClientRect())
    return {
      nameBottom: nameBox.bottom,
      whereTop: whereBox.top,
      whereText: (label.firstElementChild!.children[1].textContent ?? '').trim(),
    }
  })
  expect(stack.whereText, 'the where line is gone').not.toBe('')
  expect(stack.whereTop, 'the where line is not under the long name').toBeGreaterThanOrEqual(stack.nameBottom - 1)
})

/** Send the first fleet the map offers to the harbour nearest the chart's centre, through the map's own flow (tests/map.sendfleet.spec.ts). */
async function sendToSea(page: Page): Promise<void> {
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-chart"]', { timeout: 60_000 })
  await page.waitForTimeout(1500)
  const at = await page.evaluate(() => {
    const chart = document.querySelector('[data-testid="map-chart"]')?.getBoundingClientRect()
    if (!chart) return null
    const cx = chart.left + chart.width / 2
    const cy = chart.top + chart.height / 2
    let best: { x: number; y: number; d: number } | null = null
    for (const e of document.querySelectorAll('[data-testid="map-ports"] [data-port-code]')) {
      const r = e.getBoundingClientRect()
      const x = r.x + r.width / 2
      const y = r.y + r.height / 2
      if (r.width <= 0 || x < chart.left + 40 || x > chart.right - 40 || y < chart.top + 90 || y > chart.bottom - 70) continue
      const d = Math.hypot(x - cx, y - cy)
      if (d < 25) continue // the home harbour, where she lies
      if (!best || d < best.d) best = { x, y, d }
    }
    return best
  })
  expect(at, 'no harbour on the chart to sail to').not.toBeNull()
  await page.mouse.click(at!.x, at!.y)
  await page.waitForTimeout(900)
  await page.locator('[data-testid="map-send-fleet"]').click({ timeout: 8000 })
  await page.waitForTimeout(700)
  await page.locator('[data-testid="map-send-row-head"]').first().click({ timeout: 6000 })
  await page.waitForTimeout(1500)
  await page.locator('[data-testid="map-send-ratio-send"]').click({ timeout: 6000 })
  await page.waitForTimeout(3500)
}

test('FLEETS: a fleet AT SEA keeps her name whole at 320×640, with where she is bound under it, and the page stays flat', async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(GLASSES[1])
  await WORLDS.veteran.serve(page)
  await sendToSea(page)
  // the app's own navigation, not a reload: the voyage lasts seconds in this world and a reload would only re-read it
  await page.evaluate(() => {
    history.pushState({}, '', '/byeharu-voyage/fleets')
    dispatchEvent(new PopStateEvent('popstate'))
  })
  await expect(page.getByTestId('fleets-list')).toBeVisible()
  await expect(page.getByTestId('fleet-row')).toHaveCount(VETERAN_HULLS)
  // the row whose where line says she is BOUND somewhere ("to Cape St Vincent · 22s"), found by that line's own box: the row's TEXT runs the
  // name and the where line together ("Boa Esperançato Cape…"), so a word-boundary match on the row would miss her
  const atSea = () =>
    page
      .getByTestId('fleet-row')
      .evaluateAll((rows) =>
        rows.flatMap((r, i) =>
          (r.querySelector('[data-row-cell="label"]')?.firstElementChild?.children[1]?.textContent ?? '').trim().startsWith('to ') ? [i] : [],
        ),
      )
  await expect
    .poll(atSea, {
      message: 'no fleet is at sea — the voyage was not sent, or she has already arrived',
      timeout: 15_000,
    })
    .toHaveLength(1)
  const sailing = page.getByTestId('fleet-row').nth((await atSea())[0])
  const name = sailing.locator('[data-name]').first()
  expect(await name.evaluate((el) => el.scrollWidth > el.clientWidth + 1), 'her name is cut beside where she is bound').toBe(false)
  expect(await name.evaluate((el) => el.clientWidth), 'her name is a few pixels wide').toBeGreaterThan(60)
  // FLEETS is a page now (tests/fleets.design.spec.ts holds its laws): the document is flat and the defect rules stand
  const m = await readGlass(page, 'fleets-list', 'fleet-row', '[data-sheet]')
  const failures = phoneLaws('FLEETS at sea at 320×640', m)
  if (m.doc.sh > m.doc.ch + 1) failures.push(`the document scrolls ${m.doc.sh}/${m.doc.ch}`)
  expect(failures, 'a fleet at sea broke the page').toEqual([])
})

// A NAME IS PRINTED WHOLE (2026-11-11, the full-names slice; the owner's rule: a name is never cut with "…"). Until then a captain's
// 47-character name was CUT at every phone glass and read by a press that opened it in place (`Clip`). `Clip` now prints a name
// whole, turning only at a space (src/components/ui/Clip.tsx), so the same name at the same glass is read here the other way round:
// nothing is cut, no word is broken, and the press on her name is the row's own press again (it opens her tray).
test.describe('a long name is printed whole', () => {
  test.use({ hasTouch: true, isMobile: true })

  test("YOU: a captain's 47-character name stands whole at 320×640, on more than one line, and a press on it opens her tray", async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    const full = 'Ana Maria da Conceição Fernandes de Albuquerque'
    await open(page, GLASSES[1], 'veteran', 'you', 'you')
    await expect(page.getByTestId('your-captain')).toHaveCount(VETERAN_CAPTAINS)
    const name = page.locator('[data-testid="your-captain"] [data-name]').filter({ hasText: full })
    await name.scrollIntoViewIfNeeded()
    await expect(name).toHaveText(full)
    const read = await name.evaluate((el) => {
      const node = el.firstChild as Text
      const tops = (from: number, to: number) => {
        const range = document.createRange()
        range.setStart(node, from)
        range.setEnd(node, to)
        return new Set([...range.getClientRects()].filter((r) => r.width > 0).map((r) => Math.round(r.top))).size
      }
      const text = node.data
      const row = el.closest('[data-testid="your-captain"]')!.getBoundingClientRect()
      const box = el.getBoundingClientRect()
      return {
        cut: el.scrollWidth > el.clientWidth + 1 || getComputedStyle(el).textOverflow === 'ellipsis',
        lines: tops(0, text.length),
        brokenWords: [...text.matchAll(/\S+/g)].filter((m) => tops(m.index, m.index + m[0].length) !== 1).map((m) => m[0]),
        inRow: box.left >= row.left - 0.5 && box.right <= row.right + 0.5 && box.top >= row.top - 0.5 && box.bottom <= row.bottom + 0.5,
        sideways: document.documentElement.scrollWidth > document.documentElement.clientWidth,
      }
    })
    expect(read.cut, 'the long name is cut').toBe(false)
    expect(read.lines, 'the 47-character name stands on one line at 320 px: the proof is vacuous').toBeGreaterThan(1)
    expect(read.brokenWords, 'a word of her name is broken inside itself').toEqual([])
    expect(read.inRow, 'her name stands outside her row').toBe(true)
    expect(read.sideways, 'the page scrolls sideways').toBe(false)
    await expect(page.getByTestId('clip-full'), 'a name opens no layer any more: it is already whole').toHaveCount(0)
    await name.tap()
    await expect(page.getByTestId('your-captain-tray'), 'a press on her name is the press on her row').toBeVisible()
  })
})

test('a press on a captain opens her tray, outside the list card; closing it leaves the card as it was', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await open(page, GLASSES[0], 'veteran', 'you', 'you')
  await expect(page.getByTestId('your-captain')).toHaveCount(VETERAN_CAPTAINS)
  const panel = async () => JSON.stringify(await page.getByTestId('your-captains').boundingBox())
  // the first captain's row may stand below the fold of the panel; the player scrolls it into view BEFORE the press, so the
  // press is measured from there. (2026-11-11, S4: with the 13-px caption the row's foot stands under the fold at the
  // first glass, so Playwright's own click scrolled it in and that scroll, not the press, moved the panel 6 px. Reading
  // `before` after the scroll keeps the law — a press moves nothing — and takes the scroll out of it.)
  await page.getByTestId('your-captain').first().scrollIntoViewIfNeeded()
  const before = await panel()
  await page.getByTestId('your-captain').first().click()
  const tray = page.getByTestId('your-captain-tray')
  await expect(tray).toBeVisible()
  expect(await tray.evaluate((el) => el.closest('[data-list-panel]') !== null), 'the captain tray stands inside the panel and its scroller').toBe(false)
  expect(
    await page.evaluate(() => document.documentElement.scrollHeight <= document.documentElement.clientHeight + 1),
    'opening her tray scrolled the page',
  ).toBe(true)
  expect(await panel(), 'opening her tray moved the panel').toEqual(before)
  await tray.getByRole('button', { name: /close/i }).first().click()
  await expect(tray).toHaveCount(0)
  expect(await panel(), 'closing her tray moved the panel').toEqual(before)
})
