import { test, expect, type Page } from '@playwright/test'
import { boundFor } from '../src/domain/order'
import { MINUS, formatDaysReal, formatRealShort, formatVoyageDays, moneyFigure, moneyWord, voyageDaysToRealMs } from '../src/lib/format'
import type { FleetView, QueuedOrder } from '../src/lib/rpc'
import { closeDetail, openDetail, ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE'S FLOW, FIVE LAWS (2026-11-11, the trade-flow slice; docs/dev-log/2026-11-11-trade-flow-1.md, SUCCESS_PLAN §A)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A played audit of the Trade home screen found five places where the screen was a dead end, said something false, or moved
// under the thumb. One law for each, measured on a phone (390×844) and a laptop (1,280×800), in English and Korean:
//
//   T1  YOUR CARGO IS NOT A DEAD END. A city row pressed on the Your cargo page closes the page and shows the tray it
//       opened (the tray is on the glass and its button can be pressed); the tray's Back opens the page again; the page's
//       Back returns to Trade. Before: the row lit up and the tray opened UNDER the full-screen page.
//   T2  "NO BUYER" IS SAID ONLY WHERE IT IS TRUE. A good the city bids for prints that bid with none aboard too (quiet, its
//       title "None on board", Sell dead). Before: every card of a fresh company said "No buyer".
//   T3  TRADE SAYS WHERE SHE IS. One line: in port, the port; under way, "to <destination> · arrives <clock>" and a bar (a
//       strip at the head of the wide desk's left pane; on a phone beside her name, in the fleet picker's own row). Under
//       way the board is her DESTINATION's, never a stop on the way: on a far trip the line names the destination and the
//       next stop, and the board, the line and the first chip are the same city.
//   T8  NO JUMPS. A city chip pressed moves no chip (the pressed one is marked) and nothing under the chips moves: the wide
//       desk's board keeps its own line in its place whether she lies at the city or not, and on a phone "<city> · Not
//       docked" stands beside her name, where it pushes nothing. Landing does not sort the chips again.
//       NOT HERE: "on a phone the goods scroll with the page". The owner's one-page law (tests/onepage.spec.ts: the tab's own
//       sheet never scrolls) forbids it, so the goods keep their own pane (one whole row of cards) and this file holds the
//       one-page law on the Trade face instead: with this slice's line added, the phone's sheet still does not scroll.
//   T9  FIGURES HAVE THEIR UNITS. A trip's days carry the real time; Your cargo's averaged price says "avg"; a buy's money is
//       its "Cost", unsigned; every toast carries its amount with its word; the arrival card's figure has its word (Profit /
//       Loss) and is the served figure in the tray's own rounding.
//
// Nothing here compares a price with a number: only words, boxes, order, and one figure with itself.

// ── THE PURE LAWS (no browser) ─────────────────────────────────────────────────────────────────

const order = (verb: string, text: string, status: QueuedOrder['status']): QueuedOrder => ({
  id: text,
  seq: 0,
  text,
  verb,
  status,
  error_code: null,
  error_message: null,
  figures: null,
  result: null,
})
const fleetWith = (voyage: boolean, queue: QueuedOrder[]) =>
  ({ name: 'Gaivota', voyage: voyage ? { to: 'SAI' } : null, queue }) as unknown as FleetView
const isPort = (c: string) => ['SAI', 'CCO', 'MAT', 'LIS'].includes(c)

test('T3 (pure): she is bound for the last harbour of the SAILs that follow her leg, never a stop on the way', () => {
  // a far trip: on the leg to Saint-Louis, two more SAILs queued, then the sale
  const far = fleetWith(true, [order('SAIL', 'SAIL CCO', 'pending'), order('SAIL', 'SAIL MAT', 'pending'), order('SELL', 'SELL anise ALL', 'pending')])
  expect(boundFor(far, isPort)).toBe('MAT')
  // the SAIL under way still listed, and orders already done before it
  const listed = fleetWith(true, [order('BUY', 'BUY anise 10', 'done'), order('SAIL', 'SAIL SAI', 'active'), order('SAIL', 'SAIL MAT', 'pending'), order('SELL', 'SELL anise ALL', 'pending')])
  expect(boundFor(listed, isPort)).toBe('MAT')
  // the SAILs after her next trade are another trip: she is bound for where she next acts
  const two = fleetWith(true, [order('SAIL', 'SAIL CCO', 'pending'), order('BUY', 'BUY anise 10', 'pending'), order('SAIL', 'SAIL MAT', 'pending')])
  expect(boundFor(two, isPort)).toBe('CCO')
  // one leg: nothing follows it, the voyage's own end is the destination (the caller reads it)
  expect(boundFor(fleetWith(true, [order('SELL', 'SELL anise ALL', 'pending')]), isPort)).toBeNull()
  // in port she is bound nowhere
  expect(boundFor(fleetWith(false, [order('SAIL', 'SAIL MAT', 'pending')]), isPort)).toBeNull()
})

test('T9 (pure): days carry the real time through the one rate; a cost is unsigned; a profit has its word', () => {
  for (const d of [0.1, 0.7, 1, 40.8]) expect(formatDaysReal(d)).toBe(`${formatVoyageDays(d)} · ${formatRealShort(voyageDaysToRealMs(d))}`)
  expect(formatDaysReal(Number.NaN)).toBe('—')
  for (const n of [856, -856]) {
    expect(moneyFigure('cost', n)).not.toContain(MINUS)
    expect(moneyFigure('cost', n)).not.toContain('+')
    expect(moneyFigure('cost', n)).toMatch(/^856/)
  }
  expect(moneyFigure('profit', -1183)).toContain(`${MINUS}1,183`)
  expect(moneyFigure('profit', 1183)).toContain('+1,183')
  expect(moneyWord('profit', -1), 'a loss and a profit are two words').not.toBe(moneyWord('profit', 1))
  expect(moneyWord('profit', 0)).toBe(moneyWord('profit', 1))
})

// ── THE PLAYED LAWS ────────────────────────────────────────────────────────────────────────────

const WORDS = {
  'en-US': {
    inPort: 'In port',
    docked: 'Docked',
    notDocked: 'Not docked',
    noBuyer: 'No buyer',
    noneAboard: 'None on board',
    avg: 'avg',
    cost: 'Cost',
    days: /^\d[\d.,]* days · \d+\S*$/,
    bought: /^Bought \d[\d,]* .+ · Cost \d[\d,.]*/,
    sailed: /^Sailing to .+ · (Profit|Loss|Total|Cost) [+−]?\d[\d,.]*/,
    arrives: /^arrives \d\d:\d\d · \d+\S*$/,
    nextStop: /^next stop .+ \d\d:\d\d · \d+\S*$/,
    profit: 'Profit',
    loss: 'Loss',
  },
  'ko-KR': {
    inPort: '정박 중',
    docked: '정박 중',
    notDocked: '정박 중 아님',
    noBuyer: '안 삼',
    noneAboard: '적재 없음',
    avg: '평균',
    cost: '비용',
    days: /^\d[\d.,]*일 · \d+\S*$/,
    bought: /^.+ \d[\d,]*개 삼 · 비용 \d[\d,.]*/,
    sailed: /^.+\(으\)로 출항 · (이익|손실|합계|비용) [+−]?\d[\d,.]*/,
    arrives: /^\d\d:\d\d · \d+\S* 도착$/,
    nextStop: /^다음 기항 .+ \d\d:\d\d · \d+\S*$/,
    profit: '이익',
    loss: '손실',
  },
} as const

const GLASSES = [
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

async function openTrade(page: Page) {
  test.setTimeout(600_000)
  await page.goto('command')
  await ready(page)
  await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
  await expect(page.getByTestId('city-chip').first()).toBeVisible()
  await page.evaluate(() => document.fonts.ready)
}

/** The chips' cities in order, and which is marked. */
const chipsOf = (page: Page) =>
  page.getByTestId('city-chip').evaluateAll((es) => ({
    order: es.map((e) => e.getAttribute('data-port') ?? ''),
    on: es.filter((e) => e.getAttribute('aria-pressed') === 'true').map((e) => e.getAttribute('data-port') ?? ''),
  }))

/** A box on the page (not on the glass): its place does not depend on how far the page is scrolled. */
const boxOf = (page: Page, testid: string) =>
  page.getByTestId(testid).first().evaluate((e) => {
    let scrolled = 0
    for (let p = e.parentElement; p; p = p.parentElement) scrolled += p.scrollTop
    const r = e.getBoundingClientRect()
    return { top: Math.round(r.top + scrolled), height: Math.round(r.height) }
  })

const oneLine = (s: string) => s.replace(/\s+/g, ' ').trim()

for (const locale of ['en-US', 'ko-KR'] as const) {
  const W = WORDS[locale]
  for (const glass of GLASSES) {
    const phone = glass.width < 1024
    test.describe(`Trade's flow — ${locale} at ${glass.width}×${glass.height}`, () => {
      test.use({ locale, viewport: glass })

      test('in port: the strip, the honest sell word, no jumps, the cargo page and its tray both ways, the units; then a near trip and its arrival', async ({ page }) => {
        await openTrade(page)
        const where = `${locale} @${glass.width}`
        const face = page.getByTestId('desk-trade')
        const board = face.getByTestId('trade-board')
        const status = page.getByTestId('trade-status')
        const panel = page.getByTestId('good-detail')
        const act = page.getByTestId('trade-act')
        const cargoPage = page.getByTestId('cargo-open-page')
        const home = (await chipsOf(page)).order[0]

        await test.step('T3: in port, the strip names her port', async () => {
          await expect(status).toHaveAttribute('data-state', 'docked')
          await expect(status).toContainText(W.inPort)
          const name = await face.locator(`[data-testid="city-chip"][data-port="${home}"]`).getByTestId('city-chip-name').innerText()
          await expect(status.getByTestId('trade-status-place')).toContainText(name)
          expect((await boxOf(page, 'trade-status')).top, `${where}: the strip is not above the goods`).toBeLessThan((await boxOf(page, 'trade-good')).top)
        })

        await test.step('T2: a bid is printed with none aboard; "No buyer" only where no bid is served', async () => {
          const cells = await face.getByTestId('trade-good').evaluateAll((cards) =>
            cards.map((c) => {
              const sell = c.querySelector('[data-testid="trade-good-sell"]') as HTMLElement
              return {
                good: c.getAttribute('data-good') ?? '',
                state: sell.dataset.state ?? '',
                text: (sell.textContent ?? '').trim(),
                title: sell.title,
                buy: (c.querySelector('[data-testid="trade-good-buy"]')?.textContent ?? '').trim(),
                sellDead: (c.querySelector('[data-testid="trade-sell"]') as HTMLButtonElement).disabled,
              }
            }),
          )
          const figure = (s: string) => Number(s.replace(/,/g, ''))
          const none = cells.filter((c) => c.state === 'none-aboard')
          // a new company carries nothing, and Lisbon bids for what it sells: the cards that said "No buyer"
          expect(none.length, `${where}: no card prints a bid with none aboard`).toBeGreaterThan(0)
          for (const c of none) {
            expect(c.text, `${where}: ${c.good} prints no bid`).toMatch(/^\d[\d,.]*$/)
            expect(c.title, `${where}: ${c.good} does not say why Sell is dead`).toBe(W.noneAboard)
            expect(c.sellDead, `${where}: ${c.good} offers Sell with none aboard`).toBe(true)
            // a fixed fact, not a price: a city buys a good for less than it sells it
            if (/\d/.test(c.buy)) expect(figure(c.text), `${where}: ${c.good}'s bid is not under its ask`).toBeLessThan(figure(c.buy))
          }
          for (const c of cells) {
            if (c.state === 'no-buyer') expect(c.text).toBe(W.noBuyer)
            else expect(c.text, `${where}: ${c.good} says "${W.noBuyer}" beside a served bid`).not.toBe(W.noBuyer)
          }
        })

        await test.step('T8: a chip pressed moves no chip and nothing under the chips; the phone sheet still does not scroll', async () => {
          const before = await chipsOf(page)
          expect(before.on).toEqual([home])
          // what stands under the chips: the board's own line on the wide desk; on a phone there is none, the cards start there
          const under = async () => ({
            chips: await boxOf(page, 'city-chips'),
            head: phone ? null : await boxOf(page, 'trade-board-head'),
            headShown: await face.getByTestId('trade-board-head').isVisible(),
          })
          const rest = await under()
          expect(rest.headShown, `${where}: the board's own line`).toBe(!phone)
          if (!phone) await expect(face.getByTestId('trade-board-docked')).toHaveText(W.docked)
          else await expect(page.getByTestId('trade-status-board')).toHaveCount(0)
          const strip0 = await boxOf(page, 'trade-status')
          for (const i of [2, before.order.length - 1, 1]) {
            const code = before.order[i]
            const chip = face.locator(`[data-testid="city-chip"][data-port="${code}"]`)
            await chip.click()
            await expect(board).toHaveAttribute('data-city', code)
            const now = await chipsOf(page)
            expect(now.order, `${where}: pressing ${code} moved the chips`).toEqual(before.order)
            expect(now.on, `${where}: ${code} is not the one marked`).toEqual([code])
            // "Not docked" is said, in a place that pushes nothing
            if (!phone) await expect(face.getByTestId('trade-board-not-docked')).toHaveText(W.notDocked)
            else {
              const name = await chip.getByTestId('city-chip-name').innerText()
              await expect(page.getByTestId('trade-status-board')).toHaveText(`${name} · ${W.notDocked}`)
            }
            expect(await under(), `${where}: something under the chips moved when ${code} was pressed`).toEqual(rest)
            expect(await boxOf(page, 'trade-status'), `${where}: the line that says where she is changed its box when ${code} was pressed`).toEqual(strip0)
          }
          await face.locator(`[data-testid="city-chip"][data-port="${home}"]`).click()
          await expect(board).toHaveAttribute('data-city', home)
          await expect(board).toHaveAttribute('data-docked', 'true')
          expect((await chipsOf(page)).order).toEqual(before.order)
          expect(await under(), `${where}: something under the chips moved back at her own city`).toEqual(rest)
          await expect(face.getByTestId('trade-good').first()).toBeVisible({ timeout: 60_000 })

          // THE OWNER'S ONE-PAGE LAW ON THIS FACE (tests/onepage.spec.ts holds it for every tab): the phone's sheet does not
          // scroll with the line that says where she is added, and that line is in the fleet picker's own 44-px row
          if (phone) {
            const sheet = await page.getByTestId('desk-scroll').evaluate((e) => ({ h: e.scrollHeight, ch: e.clientHeight }))
            expect(sheet.h, `${where}: the Trade face scrolls its sheet (${sheet.h} px in ${sheet.ch})`).toBeLessThanOrEqual(sheet.ch + 1)
            expect(strip0.height, `${where}: the line beside her name is taller than the picker's row`).toBeLessThanOrEqual(44)
          }
        })

        let bought = ''
        await test.step('T9: a buy is a Cost, unsigned, on the tray and on its toast', async () => {
          const card = face.locator('[data-testid="trade-good"]:has([data-testid="trade-buy"]:not([disabled]))').first()
          bought = (await card.getAttribute('data-good'))!
          await card.getByTestId('trade-buy').click()
          const total = panel.getByTestId('good-detail-total')
          await expect(total).toContainText(/\d/, { timeout: 60_000 })
          const words = oneLine(await total.innerText())
          expect(words, `${where}: a buy's money is not named a cost`).toContain(W.cost)
          expect(words, `${where}: a buy's money is drawn with a minus`).not.toMatch(/[−-]/)
          await expect(act).toBeEnabled({ timeout: 60_000 })
          await act.click()
          const toast = page.getByTestId('trade-toast')
          await expect(toast).toContainText(W.bought, { timeout: 60_000 })
          expect(await toast.innerText(), `${where}: the buy's toast is drawn with a minus`).not.toMatch(/[−-]/)
          await expect(panel).toHaveCount(0)
        })

        const block = page.getByTestId('cargo-best').locator(`[data-testid="cargo-good"][data-good="${bought}"]`)
        const away = block.locator(`[data-testid="cargo-place"]:not([data-port="${home}"])`)
        let to = ''
        await test.step('T9: Your cargo prints the real time beside the days, and "avg" on an averaged price', async () => {
          await openDetail(page, 'cargo-open')
          await expect(away.first()).toBeVisible({ timeout: 120_000 })
          const rows = await block.getByTestId('cargo-place').evaluateAll((es) =>
            es.map((e) => ({
              port: e.getAttribute('data-port') ?? '',
              days: (e.querySelector('[data-testid="cargo-place-days"]')?.textContent ?? '').trim(),
              avg: (e.querySelector('[data-testid="cargo-place-avg"]')?.textContent ?? '').trim(),
            })),
          )
          for (const r of rows.filter((x) => x.port !== home)) {
            expect(r.days, `${where}: ${r.port}'s days carry no real time`).toMatch(W.days)
            expect(r.avg, `${where}: ${r.port}'s averaged price does not say so`).toBe(W.avg)
          }
          // her own quay's price is the bid now, not an average, and has no trip
          for (const r of rows.filter((x) => x.port === home)) expect(r.avg + r.days).toBe('')
          to = (await away.first().getAttribute('data-port'))!
        })

        await test.step('T1: a cargo row closes its page and shows the tray; Back returns to the page; Back again to Trade', async () => {
          await away.first().click()
          await expect(cargoPage, `${where}: the cargo page stays over the tray`).toHaveCount(0)
          await expect(panel).toBeVisible()
          await expect(panel).toHaveAttribute('data-city', to)
          await expect(panel).toHaveAttribute('data-good', bought)
          await expect(act).toHaveAttribute('data-act', 'sail-sell')
          await expect(act).toBeInViewport()
          // the button is ON the glass: a press would land on it, not on a page lying over it
          const covered = await act.evaluate((b) => {
            const r = b.getBoundingClientRect()
            const at = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
            return !(at === b || b.contains(at))
          })
          expect(covered, `${where}: something lies over the tray's button`).toBe(false)
          await expect(page.getByTestId('plan-days'), `${where}: the tray's days carry no real time`).toContainText(new RegExp(W.days.source.replace(/^\^|\$$/g, '')), { timeout: 60_000 })
          // Back from the tray: where she was
          await panel.getByTestId('tray-close').click()
          await expect(panel).toHaveCount(0)
          await expect(cargoPage, `${where}: the tray's Back did not return to the cargo page`).toBeVisible()
          await expect(away.first()).toBeVisible()
          // Back from the page: Trade
          await closeDetail(page)
          await expect(board).toBeVisible()
          await expect(panel).toHaveCount(0)
        })

        let sailing: string[] = []
        await test.step('T3 + T9: a near trip — its toast carries the amount, the strip says where and when, the board is her destination', async () => {
          await openDetail(page, 'cargo-open')
          await block.locator(`[data-testid="cargo-place"][data-port="${to}"]`).click()
          await expect(act).toBeEnabled({ timeout: 60_000 })
          await act.click()
          await expect(page.getByTestId('trade-toast')).toContainText(W.sailed, { timeout: 60_000 })
          await expect(status).toHaveAttribute('data-state', 'sailing', { timeout: 30_000 })
          await expect(status).toHaveAttribute('data-to', to)
          await expect(status.getByRole('meter')).toBeVisible()
          // one leg: the clock is the arrival's
          await expect(status).toHaveAttribute('data-next', '')
          expect(oneLine(await status.getByTestId('trade-status-arrives').innerText()), `${where}: the strip gives no arrival clock`).toMatch(W.arrives)
          await expect(board).toHaveAttribute('data-city', to)
          const chips = await chipsOf(page)
          expect(chips.order[0], `${where}: under way the chips do not start at her destination`).toBe(to)
          expect(chips.on).toEqual([to])
          sailing = chips.order
          // a short strip: one line and its bar where the words fit, never more than two lines
          expect((await boxOf(page, 'trade-status')).height, `${where}: the line under way is taller than its place`).toBeLessThanOrEqual(phone ? 44 : 84)
        })

        await test.step('T9 + T8: the arrival card names its figure; landing does not sort the chips again', async () => {
          const card = page.getByTestId('arrival-card')
          await expect(card).toBeVisible({ timeout: 300_000 })
          const figure = card.getByTestId('arrival-figure').first()
          await expect(figure).toHaveAttribute('data-kind', 'profit')
          const word = (await figure.getByTestId('arrival-figure-word').innerText()).trim()
          const text = oneLine(await figure.innerText())
          expect([W.profit, W.loss], `${where}: the arrival figure has no word`).toContain(word)
          expect(word === W.loss, `${where}: "${text}" — the word and the sign disagree`).toBe(text.includes(MINUS))
          // the one sale's figure is the served one (data-net), in the tray's rounding
          const net = Number(await card.getAttribute('data-net'))
          expect(text, `${where}: the card does not print the served figure`).toContain(moneyFigure('profit', net).replace(/\s.*$/, ''))
          await page.getByTestId('arrival-close').click()
          await expect(status).toHaveAttribute('data-state', 'docked', { timeout: 60_000 })
          await expect(board).toHaveAttribute('data-docked', 'true')
          expect((await chipsOf(page)).order, `${where}: landing sorted the chips again`).toEqual(sailing)
        })
      })

      test('T3: on a far trip the board, the strip and the first chip are her destination, and the strip names the next stop', async ({ page }) => {
        await openTrade(page)
        const where = `${locale} @${glass.width}`
        const face = page.getByTestId('desk-trade')
        const status = page.getByTestId('trade-status')
        const act = page.getByTestId('trade-act')
        // a best sale pressed is a trip: bought here, sold at its city. The first one her purse can pay for.
        const sales = face.locator('[data-testid="best-sale"][data-state="sale"]')
        await expect(sales.first()).toBeVisible({ timeout: 180_000 })
        let to = ''
        for (let i = 0; i < (await sales.count()); i++) {
          to = (await sales.nth(i).getAttribute('data-port'))!
          await sales.nth(i).click()
          await expect(act).toHaveAttribute('data-act', 'buy-sell')
          const ready = await expect(act).toBeEnabled({ timeout: 20_000 }).then(
            () => true,
            () => false,
          )
          if (ready) break
          to = ''
        }
        expect(to, `${where}: no best sale made a trip she can sail`).not.toBe('')
        await act.click()
        await expect(page.getByTestId('trade-toast')).toContainText(W.sailed, { timeout: 60_000 })
        await expect(status).toHaveAttribute('data-state', 'sailing', { timeout: 60_000 })
        await expect(status).toHaveAttribute('data-to', to)
        await expect(face.getByTestId('trade-board')).toHaveAttribute('data-city', to)
        const chips = await chipsOf(page)
        expect(chips.order[0], `${where}: the chips do not start at her destination`).toBe(to)
        // her orders: every SAIL past the leg she is on means a stop on the way
        const orders = Number((await face.getByTestId('command-queue').innerText()).replace(/\D+/g, ' ').trim().split(' ')[0])
        const next = (await status.getAttribute('data-next')) ?? ''
        console.log(`far trip ${where}: to ${to}, next stop "${next}", ${orders} orders, strip ${JSON.stringify(oneLine(await status.innerText()))}`)
        const box = await boxOf(page, 'trade-status')
        const sheet = glass.width < 1024 ? await page.getByTestId('desk-scroll').evaluate((e) => ({ h: e.scrollHeight, ch: e.clientHeight })) : null
        console.log(`far trip ${where}: the line is ${box.height} px high${sheet ? `, the sheet ${sheet.h} in ${sheet.ch}` : ''}`)
        if (glass.width < 1024) {
          expect(box.height, `${where}: under way the line beside her name is taller than the picker's row`).toBeLessThanOrEqual(44)
          expect(sheet!.h, `${where}: under way the Trade face scrolls its sheet`).toBeLessThanOrEqual(sheet!.ch + 1)
        }
        if (orders > 1) {
          expect(next, `${where}: a trip of ${orders} orders has no next stop on the strip`).not.toBe('')
          expect(next, `${where}: the next stop is the destination`).not.toBe(to)
          expect(oneLine(await status.getByTestId('trade-status-next').innerText()), `${where}: the strip does not name the next stop and its clock`).toMatch(W.nextStop)
          expect(chips.order, `${where}: the stop on the way has taken the board's chips`).not.toContain(next)
        }
      })
    })
  }
}
