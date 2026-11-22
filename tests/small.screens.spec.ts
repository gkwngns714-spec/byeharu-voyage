import { readFileSync } from 'node:fs'
import path from 'node:path'
import { test, expect, type Locator, type Page } from '@playwright/test'
import { KO_GOODS } from '../src/lib/i18n/names/goods'
import { KO_PORTS } from '../src/lib/i18n/names/ports'
import { ready, settled } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SMALL SCREENS' LEFTOVERS, MEASURED (2026-11-13; docs/dev-log/2026-11-13-small-screens.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, on a phone (2026-11-12): *"word box overlapping, long words and sentences making new messy lines... fix all.
// especially on phone."* Two slices fixed most of it; this one holds what they left at 320 px, and the wide desk's two.
//
// THE LAWS, in English and Korean:
//   (1) AT 320 PX NO NAME IN A CARD LIST IS TURNED INSIDE A WORD: every hull of the Codex ("Spiegelretourschip" stood on two
//       lines), every city of Stats' list (산타크루스데테네리페 did), and a city page's goods, with the world's longest goods
//       names put in ("Balsam of Peru" stood a letter a line). A name turns at a space, or after its own hyphen.
//   (2) AT 320 PX THE HQ MARKET'S BUY BUTTON IS ONE LINE, and neither button of its tray stands past the panel.
//   (3) A GOODS CARD'S HEAD IS THE SAME TWO LINES IN EVERY CARD, at 320, 390 and 1,280: the name, then the count ("On board 0")
//       under it at the card's right edge. It was beside the name in one card and under it in the next.
//   (4) ON THE WIDE DESK THE RIGHT PANE IS NOT EMPTY: with no good pressed it carries the ship block; a good pressed, the trade
//       panel stands there instead; with the Orders page open the screen holds one ship block, not two.
//   (5) AT 320 PX A SENTENCE OF THE HISTORY PAGE TURNS BETWEEN WORDS (the second slice, 2026-11-13): in Korean the founding line
//       "Casa de Aveiro 설립(리스본)." stood as "설립" / "(리스본)." (lib/i18n/translate.ts joins a word to its bracket).
//   (6) A PAGE'S LARGE TITLE NEVER STANDS OVER THE PAGE'S CONTENT: scrolled a little (before the title pins as a bar), the HQ's
//       city name stood over its building tiles. At rest the title goes up with the page (components/ui/Sheet.tsx).
//   (7) AT 1,280 × 800 AND 1,440 × 900 TRADE'S RIGHT PANE DOES NOT SCROLL, and the centre pane never scrolls sideways (it may scroll itself, down to its last card, when its cards are taller: 2026-11-20), with an empty hold and no good pressed, and
//       the right pane does not print the hold's figure a second time (the top bar has it) nor "No cargo.".
// Nothing here asserts a price, a count or which goods a city sells: only names, lines and boxes.

const GOODS = (JSON.parse(readFileSync(path.resolve('data', 'goods.json'), 'utf8')) as { goods: { id: string; name: string }[] }).goods

/** The longest word of a name, by letters: the measure of what a row must give it. */
const longestWord = (name: string) => Math.max(...name.split(/[\s-]+/).map((w) => w.length))

/** The twelve goods whose longest word is longest, in the language shown. */
function longestGoods(ko: boolean): string[] {
  const names = GOODS.map((g) => (ko ? (KO_GOODS[g.id] ?? g.name) : g.name))
  return [...new Set(names)].sort((a, b) => longestWord(b) - longestWord(a)).slice(0, 12)
}

/** Every name under `selector` (optionally with `names` put in, the own names put back after): a word on two lines, or a name
 *  standing past its row's right edge. Self-contained: Playwright ships this function's source into the page. */
const READ_NAMES = ({ selector, row, names }: { selector: string; row: string; names: string[] | null }) => {
  const faults: string[] = []
  const spans = [...document.querySelectorAll(selector)] as HTMLElement[]
  const textOf = (e: HTMLElement) => {
    const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT)
    for (let n = w.nextNode(); n; n = w.nextNode()) if ((n as Text).data.trim() !== '') return n as Text
    return null
  }
  const read = (span: HTMLElement) => {
    const node = textOf(span)
    if (!node) return
    const text = node.data
    for (const m of text.matchAll(/[^\s-]+-?/g)) {
      const range = document.createRange()
      range.setStart(node, m.index)
      range.setEnd(node, m.index + m[0].length)
      const lines = new Set([...range.getClientRects()].filter((r) => r.width > 0).map((r) => Math.round(r.top)))
      if (lines.size > 1) faults.push(`"${text}": the word "${m[0]}" stands on ${lines.size} lines`)
    }
    const box = span.closest(row)?.getBoundingClientRect()
    const range = document.createRange()
    range.selectNodeContents(node)
    const right = Math.max(...[...range.getClientRects()].map((r) => r.right))
    if (box && right > box.right + 1) faults.push(`"${text}" stands ${Math.round(right - box.right)} px past its row`)
  }
  if (!names) spans.forEach(read)
  else {
    const some = spans.slice(0, 4)
    for (let i = 0; i < names.length; i += some.length) {
      const own = some.map((s) => textOf(s)?.data ?? '')
      some.forEach((s, k) => {
        const node = textOf(s)
        if (node) node.data = names[(i + k) % names.length]
      })
      some.forEach(read)
      some.forEach((s, k) => {
        const node = textOf(s)
        if (node) node.data = own[k]
      })
    }
  }
  return { count: spans.length, faults: [...new Set(faults)] }
}

async function open(page: Page, route: string) {
  test.setTimeout(480_000)
  await page.goto(route)
  await ready(page)
  await page.evaluate(() => document.fonts.ready)
}

/** The lines a locator's own words stand on. */
const linesOf = (el: Locator) =>
  el.evaluate((e) => {
    const range = document.createRange()
    range.selectNodeContents(e)
    return new Set([...range.getClientRects()].filter((r) => r.width > 0).map((r) => Math.round(r.top))).size
  })

for (const locale of ['en-US', 'ko-KR'] as const) {
  const ko = locale === 'ko-KR'

  test.describe(`small screens — ${locale} at 320×640`, () => {
    test.use({ locale, viewport: { width: 320, height: 640 } })

    test('no hull, city or good is turned inside a word in a card list', async ({ page }) => {
      // the Codex's hulls
      await open(page, 'compendium')
      await page.locator('[data-testid="codex"] [role="tablist"] [role="tab"]').nth(1).click()
      await expect(page.getByTestId('ship-tile').first()).toBeVisible({ timeout: 120_000 })
      const hulls = await page.evaluate(READ_NAMES, { selector: '[data-testid="ship-tile"] [data-row-cell="label"]', row: '[data-testid="ship-tile"]', names: null })
      expect(hulls.count, 'the Codex lists too few hulls').toBeGreaterThan(50)
      expect(hulls.faults, `${locale}: a hull's name is broken`).toEqual([])

      // Stats: every city
      await open(page, 'stats')
      await page.locator('[data-testid="stats"] [role="tablist"] [role="tab"]').nth(3).click()
      await expect(page.getByTestId('stats-city-open').first()).toBeVisible({ timeout: 120_000 })
      await page.getByTestId('stats-cities-show-all').click()
      await page.waitForTimeout(400)
      const cities = await page.evaluate(READ_NAMES, { selector: '[data-testid="stats-city-name"]', row: '[data-testid="stats-city-open"]', names: null })
      expect(cities.count, 'Stats lists too few cities').toBeGreaterThan(100)
      expect(cities.faults, `${locale}: a city's name is broken`).toEqual([])

      // a city's page: its goods, and the longest goods names the world has
      await page.getByTestId('stats-city-open').first().click()
      await expect(page.getByTestId('stats-city-good').first()).toBeVisible({ timeout: 120_000 })
      await settled(page.getByTestId('stats-city-page'))
      for (const names of [null, longestGoods(ko)]) {
        const goods = await page.evaluate(READ_NAMES, { selector: '[data-testid="stats-city-good-name"]', row: '[data-testid="stats-city-good"]', names })
        expect(goods.count, 'the city page lists no good').toBeGreaterThan(0)
        expect(goods.faults, `${locale}: a good's name is broken on a city's page${names ? ' (the longest names put in)' : ''}`).toEqual([])
      }
    })

    test('a sentence of the History page turns between words', async ({ page }) => {
      await open(page, 'ledger')
      await expect(page.getByTestId('ledger-row').first()).toBeVisible({ timeout: 120_000 })
      const read = await page.evaluate(READ_NAMES, { selector: '[data-testid="ledger-row"] [data-row-cell="label"]', row: '[data-testid="ledger-row"]', names: null })
      expect(read.count, 'the History page has no entry').toBeGreaterThan(0)
      // READ_NAMES lets a word turn after its own hyphen; a sentence's word here is whatever stands between two spaces
      expect(read.faults, `${locale}: a History sentence is turned inside a word`).toEqual([])
    })

    test("a page's large title never stands over the page's content", async ({ page }) => {
      await open(page, 'city')
      await expect(page.getByTestId('city-building-grid')).toBeVisible({ timeout: 120_000 })
      for (const top of [20, 40, 60]) {
        const over = await page.evaluate((y) => {
          const sheet = document.querySelector('[data-testid="city-page"]')!.closest('[data-sheet]') ?? document.querySelector('[data-sheet]')!
          sheet.scrollTop = y
          const header = sheet.querySelector('[data-testid="sheet-header"]')!
          const title = header.querySelector('h1')!.getBoundingClientRect()
          const pinned = header.getAttribute('data-pinned') === 'true'
          const tiles = [...document.querySelectorAll('[data-testid="city-building-grid"] button')].map((b) => b.getBoundingClientRect())
          const hit = tiles.some((r) => r.top < title.bottom - 1 && r.bottom > title.top + 1 && r.left < title.right && r.right > title.left)
          return { at: sheet.scrollTop, pinned, hit }
        }, top)
        // pinned, the title is an opaque bar and the page passes under it: that is the bar's job
        if (!over.pinned) expect(over.hit, `${locale}: scrolled ${over.at} px, the title stands over a building tile`).toBe(false)
      }
    })

    test("the HQ Market's buy button is one line", async ({ page }) => {
      await open(page, 'city')
      await page.getByTestId('city-building-market').click()
      const panel = page.getByTestId('city-face-panel')
      await expect(panel).toHaveAttribute('data-building', 'market')
      await settled(panel)
      await panel.locator('[data-testid="trade-buy"]:not([disabled])').first().click()
      const send = panel.getByTestId('trade-tray-send')
      await expect(send).toBeVisible({ timeout: 60_000 })
      await expect(send).toHaveText(/\d/)
      expect(await linesOf(send), `${locale}: the buy button's words stand on more than one line`).toBe(1)
      const edge = (await panel.boundingBox())!
      for (const id of ['trade-tray-send', 'trade-tray-stage']) {
        const b = await panel.getByTestId(id).boundingBox()
        if (b) expect(b.x + b.width, `${locale}: ${id} stands past the panel`).toBeLessThanOrEqual(edge.x + edge.width + 1)
      }
    })
  })

  for (const glass of [
    { width: 320, height: 640 },
    { width: 390, height: 844 },
    { width: 1280, height: 800 },
  ] as const) {
    test.describe(`small screens — ${locale} at ${glass.width}×${glass.height}`, () => {
      test.use({ locale, viewport: glass })

      test("a goods card's head is the same two lines in every card", async ({ page }) => {
        await open(page, 'command')
        await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
        const faults = await page.evaluate(() =>
          ([...document.querySelectorAll('[data-testid="trade-good"]')] as HTMLElement[]).flatMap((card) => {
            const good = card.getAttribute('data-good')
            const name = card.querySelector('[data-testid="trade-good-name"]')!.getBoundingClientRect()
            const aboard = card.querySelector('[data-testid="trade-good-aboard"]') as HTMLElement
            const a = aboard.getBoundingClientRect()
            const c = card.getBoundingClientRect()
            const pad = parseFloat(getComputedStyle(card).paddingRight)
            const out: string[] = []
            if (a.top < name.bottom - 1) out.push(`${good}: the count stands beside the name, not under it`)
            if (Math.abs(c.right - pad - a.right) > 1) out.push(`${good}: the count is not at the card's right edge`)
            const range = document.createRange()
            range.selectNodeContents(aboard)
            if (new Set([...range.getClientRects()].map((r) => Math.round(r.top))).size !== 1) out.push(`${good}: the count stands on two lines`)
            return out
          }),
        )
        expect(faults, `${locale} @${glass.width}: a card's head is out of step`).toEqual([])

        if (glass.width < 1024) return
        // (4) the wide desk's right pane
        const right = page.getByTestId('desk-pane-ticket')
        await expect(right.getByTestId('buy-ship'), 'the idle right pane does not carry the ship').toBeVisible()
        await page.getByTestId('trade-buy').first().click()
        await expect(right.getByTestId('here-tray')).toBeVisible()
        await expect(page.getByTestId('buy-ship')).toHaveCount(0)
        await page.getByTestId('trade-buy').first().click()
        await expect(right.getByTestId('buy-ship')).toBeVisible()
        await page.getByTestId('command-queue').click()
        await expect(page.getByTestId('command-queue-page')).toBeVisible()
        await expect(page.getByTestId('buy-ship'), 'two ship blocks on one screen').toHaveCount(1)
      })
    })
  }
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  for (const glass of [
    { width: 1280, height: 800 },
    { width: 1440, height: 900 },
  ] as const) {
    test.describe(`small screens — ${locale} at ${glass.width}×${glass.height}`, () => {
      test.use({ locale, viewport: glass })

      test("Trade's right pane does not scroll or repeat the hold; the centre pane never scrolls sideways and, when its cards are taller than it, is the scroller itself, to the last card", async ({ page }) => {
        await open(page, 'command')
        await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
        const idle = page.getByTestId('desk-idle')
        await expect(idle.getByTestId('buy-ship-crew')).toBeVisible()
        await settled(idle)
        // a new company's hold is empty: the pane prints neither the hold's figure nor "No cargo."
        await expect(idle.getByTestId('cargo-bar'), "the right pane repeats the top bar's Cargo figure").toHaveCount(0)
        await expect(idle.getByTestId('buy-ship-cargo')).toHaveCount(0)
        const rows = await idle.locator('[data-row-cell="label"]').count()
        expect(rows, 'the ship block lost a row, or gained the "No cargo." line').toBe(await idle.locator('[data-testid^="buy-ship-"]:has([data-row-cell="label"])').count())
        // THE RIGHT PANE DOES NOT SCROLL (2026-11-20: the owner's law stands for it)
        const right = await idle.evaluate((e) => ({ content: e.scrollHeight, pane: e.clientHeight }))
        console.log(`TRADE ${locale} @${glass.width}×${glass.height} desk-idle: content ${right.content} px in ${right.pane} px`)
        expect(right.content, `${locale} @${glass.width}: desk-idle scrolls (${right.content} px of content in ${right.pane} px)`).toBeLessThanOrEqual(right.pane)

        // THE CENTRE PANE (decided by default 2026-11-20, the owner may reverse): a card's height is the data's (a long city name
        // runs three lines), and no layout that keeps every word fits the worst case (716 px in 634 at 1,280 × 800). So the pane
        // MAY scroll, by itself, when its cards are taller than it; it never scrolls sideways; the page never grows or scrolls.
        // Two cases are PLANTED, so the proof does not depend on which sale the world shows: one that fits, and the worst.
        const names = Object.keys(KO_PORTS)
        const pool = locale === 'ko-KR' ? names.map((n) => KO_PORTS[n]) : names
        const longest = [...pool].sort((a, b) => b.length - a.length).slice(0, 4)
        const sale = (city: string[], profit: string, time: string) =>
          page.evaluate(([c, pr, tm]) => {
            let n = 0
            document.querySelectorAll('[data-testid="trade-good"]').forEach((card, i) => {
              const name = card.querySelector('[data-testid="best-sale-city-name"]')
              if (!name) return
              name.textContent = (c as string[])[i % (c as string[]).length]
              const p = card.querySelector('[data-testid="best-sale-profit"]')
              if (p) p.textContent = pr as string
              const t = card.querySelector('[data-testid="best-sale-time"] span')
              if (t) t.textContent = tm as string
              n++
            })
            return n
          }, [city, profit, time] as const)
        const centre = () =>
          page.getByTestId('desk-pane-chart').evaluate((e) => {
            const pane = e as HTMLElement
            const cs = getComputedStyle(pane)
            const cards = [...pane.querySelectorAll('[data-testid="trade-good"]')] as HTMLElement[]
            return { content: pane.scrollHeight, height: pane.clientHeight, scrollW: pane.scrollWidth, clientW: pane.clientWidth, overflowY: cs.overflowY, cards: cards.length }
          })
        const reach = async () => {
          const last = page.getByTestId('trade-good').last()
          // SCROLLED AND MEASURED IN ONE STEP (main's Acceptance 44949997173, 2026-11-22: Buy 931 below a pane ending at 884, though the
          // pane read 810 px in 730 exactly as on the runs that passed). Two round trips let the live desk re-render between the scroll
          // and the measure (a beat's read lands, a card comes or goes), so the measure was of a pane no longer at its end. One
          // synchronous step forces the layout once: the pane at its very end, and where the last card's Buy then stands in it.
          const box = await page.evaluate(() => {
            const el = document.querySelector('[data-testid="desk-pane-chart"]') as HTMLElement
            el.scrollTop = el.scrollHeight
            const pane = el.getBoundingClientRect()
            const buy = [...document.querySelectorAll('[data-testid="trade-good"]')].at(-1)!.querySelector('[data-testid="trade-buy"]')!.getBoundingClientRect()
            return { paneTop: pane.top, paneBottom: pane.bottom, buyTop: buy.top, buyBottom: buy.bottom }
          })
          await expect(last).toBeVisible()
          return box
        }
        for (const plant of [
          { label: 'the case that fits (one short city line each)', args: [['Cork'], '+9', '1m'] as const, mustFit: true },
          { label: 'the worst case (the longest city names, the longest hours and profit)', args: [longest, '+99,999 🪙', locale === 'ko-KR' ? '12시간59분' : '12h59m'] as const, mustFit: false },
        ]) {
          const planted = await sale(plant.args[0] as string[], plant.args[1], plant.args[2])
          expect(planted, `${plant.label}: no card has a best sale to plant in`).toBeGreaterThanOrEqual(4)
          await page.waitForTimeout(500)
          const c = await centre()
          console.log(`TRADE ${locale} @${glass.width}×${glass.height} centre, ${plant.label}: content ${c.content} px in ${c.height} px`)
          // never sideways, whatever stands in it
          expect(c.scrollW, `${locale} @${glass.width}: the centre pane scrolls sideways, ${plant.label}`).toBeLessThanOrEqual(c.clientW)
          // the page itself never grows or scrolls
          expect(await page.evaluate(() => document.documentElement.scrollHeight <= document.documentElement.clientHeight), `the page scrolls, ${plant.label}`).toBe(true)
          if (plant.mustFit) expect(c.content, `${locale} @${glass.width}: the centre pane scrolls with one-line sales (${c.content} px in ${c.height} px)`).toBeLessThanOrEqual(c.height)
          if (c.content > c.height) {
            // taller than the pane: the pane itself is the scroller, and the last card (its Buy) can be reached inside it
            expect(['auto', 'scroll'], `${plant.label}: the taller pane is not a scroller`).toContain(c.overflowY)
            const at = await reach()
            expect(at.buyTop, `${plant.label}: the last card's Buy is above the pane`).toBeGreaterThanOrEqual(at.paneTop - 1)
            expect(at.buyBottom, `${plant.label}: the last card's Buy cannot be reached inside the pane`).toBeLessThanOrEqual(at.paneBottom + 1)
            await page.getByTestId('desk-pane-chart').evaluate((e) => { (e as HTMLElement).scrollTop = 0 })
          }
        }
      })
    })
  }
}
