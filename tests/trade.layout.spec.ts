import { readFileSync } from 'node:fs'
import path from 'node:path'
import { test, expect, type Page } from '@playwright/test'
import { KO_PORTS } from '../src/lib/i18n/names/ports'
import { ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE'S LAYOUT, MEASURED (2026-11-11, the trade-layout slice; docs/dev-log/2026-11-11-trade-layout.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Two leftovers of the remaster's S4 and S9:
//   · the city picker stood in four columns at 390 px, which left a name 41 px: "Lisbon" stood as "Lisbo / n" and
//     "Sanlucar de Barrameda" on four lines;
//   · on the wide desk the left pane held two rows and the centre pane everything else, and in a row of goods cards the
//     prices and the buttons stood at two heights (a name on two lines pushed its own card's down, not its neighbours').
//
// THE LAWS, at 390 and 1,280 px, in English and Korean:
//   (1) NO CITY NAME IS BROKEN INSIDE A WORD OR CUT. Measured on the picker itself, for EVERY port name the world is seeded
//       with (data/ports.json, 249 names; Korean through the game's own table) and not for three samples: each name is put
//       in the picker's own cells, eight at a time, and each word of it must stand on one line, inside its cell, with no
//       ellipsis. A name may turn at a space or after its own hyphen ("Saint-" / "Louis"), nowhere else. A Korean name has no
//       spaces, so it is one word.
//   (2) THE PICKER STAYS A GRID: a line that holds no over-long name is equal cells on the same column lines.
//   (3) IN A ROW OF GOODS CARDS every card is one height, and the prices and the Buy buttons stand level (also at 1,920).
//   (4) NOTHING SCROLLS SIDEWAYS: not the page, not the picker.
//   (5) ON THE WIDE DESK the left pane carries the picker and the doors (cargo, map, the route's line, orders), and the centre pane
//       the goods.
//   (6) NO BEST SALE'S CITY IS CUT IN A GOODS CARD (the owner's rule: a name is never cut with "…"; it was "Hag…" at 1,280 and
//       one letter at 1,920). Measured on the cards' own best-sale lines, as they stand and with every seeded port name put in
//       them, at 390, 1,280 and 1,920: each word on one line, the name inside its card, no ellipsis, no clip, and (3) still
//       holds with the longest names in.
//   (7) THE HQ MARKET DRAWS THE SAME CARD: its rows are one height with prices and buttons level, and no name in a card is cut.
// Nothing here asserts a price or which cities are near: only names, boxes and lines.

const SEEDED: string[] = (JSON.parse(readFileSync(path.resolve('data', 'ports.json'), 'utf8')) as { ports: { name: string }[] }).ports.map((p) => p.name)

/** What the picker prints for a served name, in a locale: the game's own table (src/lib/i18n/names). */
const shown = (name: string, ko: boolean) => (ko ? (KO_PORTS[name] ?? name) : name)

async function openTrade(page: Page) {
  test.setTimeout(480_000)
  await page.goto('command')
  await ready(page)
  await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
  await expect(page.getByTestId('city-chip').first()).toBeVisible()
  // the fonts decide every width measured below
  await page.evaluate(() => document.fonts.ready)
}

/** Put `names` into the picker's cells (as many as there are cells) and read every law off them; the cells' own names are put
 *  back afterwards. Self-contained: Playwright ships this function's source into the page. With no names it reads the picker as
 *  it stands. */
const READ_CHIPS = ({ names, columns }: { names: string[] | null; columns: number }) => {
  const grid = document.querySelector('[data-testid="city-chips"]') as HTMLElement
  const cells = [...grid.querySelectorAll('[data-testid="city-chip"]')] as HTMLElement[]
  const spans = cells.map((c) => c.querySelector('[data-testid="city-chip-name"]') as HTMLElement)
  const own = spans.map((s) => s.textContent ?? '')
  if (names) spans.forEach((s, i) => (s.firstChild as Text).data = names[i % names.length])
  const faults: string[] = []
  const boxes: { top: number; left: number; width: number; height: number; long: boolean }[] = []
  // the column: the picker's line, less the gaps between its cells, by the count (tileStyles.ts WORDS_COLUMN_CLASS)
  const column = (grid.clientWidth - parseFloat(getComputedStyle(grid).columnGap) * (columns - 1)) / columns
  cells.forEach((cell, i) => {
    const span = spans[i]
    const text = span.textContent ?? ''
    const node = span.firstChild as Text
    const c = cell.getBoundingClientRect()
    const s = span.getBoundingClientRect()
    // a word on two lines is a word broken inside itself (a name may turn at a space or after its own hyphen: "Saint-" / "Louis")
    for (const m of text.matchAll(/[^\s-]+-?/g)) {
      const range = document.createRange()
      range.setStart(node, m.index)
      range.setEnd(node, m.index + m[0].length)
      const lines = new Set([...range.getClientRects()].filter((r) => r.width > 0).map((r) => Math.round(r.top)))
      if (lines.size !== 1) faults.push(`"${text}": the word "${m[0]}" stands on ${lines.size} lines in a ${Math.round(c.width)}-px cell`)
    }
    // cut: an ellipsis, a clip, or a name past its cell's edge
    for (let e: HTMLElement | null = span; e && e !== grid; e = e.parentElement) {
      const cs = getComputedStyle(e)
      if (cs.textOverflow === 'ellipsis') faults.push(`"${text}": an ellipsis rule stands on its cell`)
      if (e.scrollWidth > e.clientWidth + 1 && cs.overflowX !== 'visible') faults.push(`"${text}": clipped (${e.scrollWidth} px in ${e.clientWidth})`)
    }
    if (s.left < c.left - 0.5 || s.right > c.right + 0.5 || s.top < c.top - 0.5 || s.bottom > c.bottom + 0.5) {
      faults.push(`"${text}": the name stands outside its cell (${Math.round(s.width)}×${Math.round(s.height)} in ${Math.round(c.width)}×${Math.round(c.height)})`)
    }
    if (/…|\.\.\.$/.test((cell.innerText ?? '').trim())) faults.push(`"${text}": printed with an ellipsis`)
    boxes.push({ top: Math.round(c.top), left: Math.round(c.left), width: c.width, height: c.height, long: c.width > column + 0.5 })
  })
  if (grid.scrollWidth > grid.clientWidth + 1) faults.push(`the picker scrolls sideways (${grid.scrollWidth} px in ${grid.clientWidth}) with ${JSON.stringify(names)}`)
  if (document.documentElement.scrollWidth > document.documentElement.clientWidth) faults.push(`the page scrolls sideways with ${JSON.stringify(names)}`)
  const g = grid.getBoundingClientRect()
  for (const b of boxes) if (b.left < g.left - 0.5 || b.left + b.width > g.right + 0.5) faults.push(`a cell stands outside the picker with ${JSON.stringify(names)}`)
  if (names) spans.forEach((s, i) => (s.firstChild as Text).data = own[i])
  return { faults, boxes, column, cells: cells.length, own }
}

/** The goods cards by row: each card's height, and where its prices and its Buy button stand. */
const READ_CARDS = () =>
  [...document.querySelectorAll('[data-testid="trade-good"]')].map((c) => {
    const r = c.getBoundingClientRect()
    const top = (id: string) => Math.round((c.querySelector(`[data-testid="${id}"]`) as HTMLElement).getBoundingClientRect().top)
    return { good: c.getAttribute('data-good') ?? '', top: Math.round(r.top), height: Math.round(r.height), price: top('trade-good-buy'), buy: top('trade-buy') }
  })

/** Put `names` into the cards' best-sale lines (cycled over the cards that carry a sale) and read law (6) off them. The names
 *  STAY IN until the next call, so the rows can be measured with them; a call with the names it returned as `own` puts the
 *  players' own back. Self-contained, shipped into the page. With no names it reads the lines as they stand. */
const SET_SALES = (names: string[] | null) => {
  const spans = [...document.querySelectorAll('[data-testid="best-sale"][data-state="sale"] [data-testid="best-sale-city-name"]')] as HTMLElement[]
  const own = spans.map((s) => s.textContent ?? '')
  if (names) spans.forEach((s, i) => ((s.firstChild as Text).data = names[i % names.length]))
  const faults: string[] = []
  for (const span of spans) {
    const card = span.closest('[data-testid="trade-good"]') as HTMLElement
    const text = span.textContent ?? ''
    const node = span.firstChild as Text
    const c = card.getBoundingClientRect()
    for (const m of text.matchAll(/[^\s-]+-?/g)) {
      const range = document.createRange()
      range.setStart(node, m.index)
      range.setEnd(node, m.index + m[0].length)
      const lines = new Set([...range.getClientRects()].filter((r) => r.width > 0).map((r) => Math.round(r.top)))
      if (lines.size !== 1) faults.push(`"${text}": the word "${m[0]}" stands on ${lines.size} lines in a ${Math.round(c.width)}-px card`)
    }
    for (let e: HTMLElement | null = span; e && e !== card.parentElement; e = e.parentElement) {
      const cs = getComputedStyle(e)
      if (cs.textOverflow === 'ellipsis') faults.push(`"${text}": an ellipsis rule stands on it`)
      if (e.scrollWidth > e.clientWidth + 1 && cs.overflowX !== 'visible') faults.push(`"${text}": clipped (${e.scrollWidth} px in ${e.clientWidth})`)
    }
    // the name, the profit and the day line all stand inside the card
    const line = span.closest('[data-testid="best-sale"]') as HTMLElement
    for (const e of [span, ...line.querySelectorAll('[data-testid="best-sale-profit"], [data-testid="trade-good-spark"]')]) {
      const r = e.getBoundingClientRect()
      if (r.left < c.left - 0.5 || r.right > c.right + 0.5 || r.top < c.top - 0.5 || r.bottom > c.bottom + 0.5) faults.push(`"${text}": a part of its line stands outside the ${Math.round(c.width)}-px card`)
    }
  }
  if (document.documentElement.scrollWidth > document.documentElement.clientWidth) faults.push(`the page scrolls sideways with ${JSON.stringify(names)}`)
  return { faults, own, lines: spans.length }
}

/** Any text inside a goods card that is cut: an ellipsis rule or a clip on a box narrower than its words. */
const CUT_IN_CARDS = () =>
  [...document.querySelectorAll('[data-testid="trade-good"] *')].flatMap((e) => {
    const cs = getComputedStyle(e)
    const cut = e.scrollWidth > e.clientWidth + 1 && (cs.textOverflow === 'ellipsis' || (cs.overflowX !== 'visible' && (e.textContent ?? '').trim() !== ''))
    return cut ? [`"${(e.textContent ?? '').trim().slice(0, 40)}" is cut (${e.scrollWidth} px in ${e.clientWidth})`] : []
  })

function cardFaults(cards: Awaited<ReturnType<typeof READ_CARDS>>): string[] {
  const faults: string[] = []
  const rows = new Map<number, typeof cards>()
  for (const c of cards) rows.set(c.top, [...(rows.get(c.top) ?? []), c])
  for (const row of rows.values()) {
    for (const key of ['height', 'price', 'buy'] as const) {
      const seen = [...new Set(row.map((c) => c[key]))]
      if (seen.length !== 1) faults.push(`the row at ${row[0].top} px: ${key} differs across its cards (${row.map((c) => `${c.good} ${c[key]}`).join(', ')})`)
    }
  }
  return faults
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  const ko = locale === 'ko-KR'
  for (const glass of [
    { width: 390, height: 844 },
    { width: 1280, height: 800 },
  ] as const) {
    test.describe(`Trade's layout — ${locale} at ${glass.width}×${glass.height}`, () => {
      test.use({ locale, viewport: glass })

      test('no city name is broken inside a word or cut, for every port the world has', async ({ page }) => {
        await openTrade(page)
        const where = `${locale} @${glass.width}`
        // the picker as a player sees it
        const columns = glass.width >= 1024 ? 2 : 3
        const live = await page.evaluate(READ_CHIPS, { names: null, columns })
        expect(live.cells, 'the picker has no cells').toBeGreaterThan(2)
        expect(live.faults, `${where}: the picker as it stands`).toEqual([])
        // (2) a line with no over-long name is equal cells on the picker's column lines
        const lines = new Map<number, typeof live.boxes>()
        for (const b of live.boxes) lines.set(b.top, [...(lines.get(b.top) ?? []), b])
        const lefts = new Set<number>()
        for (const line of lines.values()) {
          expect(line.length, `${where}: a line holds more cells than the picker has columns`).toBeLessThanOrEqual(columns)
          if (line.some((b) => b.long)) continue
          for (const b of line) {
            expect(Math.abs(b.width - live.column), `${where}: a cell is ${b.width} px wide in a ${live.column}-px column`).toBeLessThanOrEqual(1)
            lefts.add(b.left)
          }
        }
        expect(lefts.size, `${where}: the cells stand on ${lefts.size} column lines, the picker has ${columns}`).toBeLessThanOrEqual(columns)

        // (1) every port name the world is seeded with, longest first, eight at a time in the picker's own cells
        const names = [...new Set(SEEDED.map((n) => shown(n, ko)))].sort((a, b) => b.length - a.length)
        expect(names.length, 'the seeded port list is not the whole world').toBeGreaterThan(200)
        const faults: string[] = []
        for (let i = 0; i < names.length; i += live.cells) {
          const batch = names.slice(i, i + live.cells)
          faults.push(...(await page.evaluate(READ_CHIPS, { names: batch, columns })).faults)
        }
        if (faults.length > 0) console.log(`CHIPS ${where}: ${faults.length} lines\n  ${faults.join('\n  ')}`)
        expect(faults, `${where}: a port name is broken or cut in the picker`).toEqual([])
        // the picker is the players' own again
        expect((await page.evaluate(READ_CHIPS, { names: null, columns })).own).toEqual(live.own)
      })

      test('a row of goods cards is one height, its prices and buttons level; nothing scrolls sideways', async ({ page }) => {
        await openTrade(page)
        const where = `${locale} @${glass.width}`
        // the cards settle as their reads land (the day's line, the best sale): two equal reads 300 ms apart
        let cards = await page.evaluate(READ_CARDS)
        for (let i = 0; i < 40; i++) {
          await page.waitForTimeout(300)
          const next = await page.evaluate(READ_CARDS)
          if (JSON.stringify(next) === JSON.stringify(cards)) break
          cards = next
        }
        expect(cards.length, 'no goods cards').toBeGreaterThan(2)
        expect(new Set(cards.map((c) => c.top)).size, `${where}: every card stands alone on its line`).toBeLessThan(cards.length)
        expect(cardFaults(cards), `${where}: a row of cards is uneven`).toEqual([])
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `${where}: the page scrolls sideways`).toBe(true)

        if (glass.width >= 1024) {
          // (5) the wide desk: where and what she has on the left, the goods in the centre
          const left = page.getByTestId('desk-pane-list')
          await expect(left.getByTestId('city-chips')).toBeVisible()
          for (const door of ['cargo-open', 'trade-map-open', 'command-queue']) await expect(left.getByTestId(door), `${door} is not in the left pane`).toBeVisible()
          const centre = page.getByTestId('desk-pane-chart')
          await expect(centre.getByTestId('trade-good').first()).toBeVisible()
          await expect(centre.getByTestId('city-chip')).toHaveCount(0)

          // (3) at 1,920 too, where six cards stand in a row
          await page.setViewportSize({ width: 1920, height: 1080 })
          await page.waitForTimeout(600)
          const wide = await page.evaluate(READ_CARDS)
          expect(cardFaults(wide), `${locale} @1920: a row of cards is uneven`).toEqual([])
          expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `${locale} @1920: the page scrolls sideways`).toBe(true)
        }
      })

      test("no best sale's city is cut in a goods card, for every port the world has", async ({ page }) => {
        await openTrade(page)
        await expect(page.locator('[data-testid="best-sale"][data-state="sale"]').first(), 'no best sale landed').toBeVisible({ timeout: 180_000 })
        const names = [...new Set(SEEDED.map((n) => shown(n, ko)))].sort((a, b) => b.length - a.length)
        for (const width of glass.width >= 1024 ? [glass.width, 1920] : [glass.width]) {
          if (width !== glass.width) {
            await page.setViewportSize({ width, height: 1080 })
            await page.waitForTimeout(600)
          }
          const where = `${locale} @${width}`
          const live = await page.evaluate(SET_SALES, null)
          expect(live.lines, `${where}: no card carries a best sale`).toBeGreaterThan(0)
          expect(live.faults, `${where}: a best sale's city as it stands`).toEqual([])
          expect(await page.evaluate(CUT_IN_CARDS), `${where}: a text in a goods card is cut`).toEqual([])
          const faults: string[] = []
          for (let i = 0; i < names.length; i += live.lines) {
            faults.push(...(await page.evaluate(SET_SALES, names.slice(i, i + live.lines))).faults)
            // (3) holds with these names in: the first batch is the longest names the world has
            if (i === 0) faults.push(...cardFaults(await page.evaluate(READ_CARDS)).map((f) => `with the longest names in, ${f}`))
          }
          await page.evaluate(SET_SALES, live.own)
          if (faults.length > 0) console.log(`SALES ${where}: ${faults.length} lines\n  ${faults.join('\n  ')}`)
          expect(faults, `${where}: a best sale's city is broken or cut in its card`).toEqual([])
        }
      })

      test('the HQ Market draws the same card: rows level, no name cut', async ({ page }) => {
        test.setTimeout(480_000)
        await page.goto('city')
        await ready(page)
        await page.getByTestId('city-building-market').click()
        await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
        await page.evaluate(() => document.fonts.ready)
        for (const width of glass.width >= 1024 ? [glass.width, 1920] : [glass.width]) {
          if (width !== glass.width) await page.setViewportSize({ width, height: 1080 })
          const where = `${locale} HQ Market @${width}`
          let cards = await page.evaluate(READ_CARDS)
          for (let i = 0; i < 40; i++) {
            await page.waitForTimeout(300)
            const next = await page.evaluate(READ_CARDS)
            if (JSON.stringify(next) === JSON.stringify(cards)) break
            cards = next
          }
          expect(cards.length, `${where}: no goods cards`).toBeGreaterThan(2)
          expect(cardFaults(cards), `${where}: a row of cards is uneven`).toEqual([])
          expect(await page.evaluate(CUT_IN_CARDS), `${where}: a text in a goods card is cut`).toEqual([])
          expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `${where}: the page scrolls sideways`).toBe(true)
        }
      })
    })
  }
}
