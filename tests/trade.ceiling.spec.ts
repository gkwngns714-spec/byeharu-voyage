// THE TRADE TRAY HOLDS STILL — a served figure keeps standing while the world is read again, the
// sell face says only what a sale is decided on, and one unit means one unit.
//
// The owner, 2026-09-14, three rows: *"when i press buy, the max keeps refreshing."* · *"when
// selling, a refresh sign of checking the price... keeps showing up. show necessary info only. For
// example i will be able to choose first how many i sell, then it will show only how much bought
// price, selling price with underneath showing the percentage. right now units? in stock? range?
// WTF man."* · *"the marker when selling unit is shitty. and it only moves in like 10? wtf. i
// should be able to sell only 1. make it so that i can type the quantity, and also scroll but
// better than this"*.
//
// THE FIRST. The shell reads the world every 3 s (src/app/AppShell.tsx, READ_MIN_MS — the local
// world's `time_compression` of 9600 (0045) clamps the cadence to that floor), and until that day
// `useBuyCapacity` keyed its answer on the read: every beat the ceiling was thrown away, the tray's
// `Max` row unmounted, the stepper clamped to a ceiling of nought, and the row repainted when the
// re-ask landed. `useOrderPreview` (the Storage tray's dry run) carried the same key. Both are
// doorways onto `useServedRead` now — the one rule that keeps the last answer for the same subject
// while the re-ask is on the wire.
//
// THIS SPEC WATCHES THE DOM, IT DOES NOT SAMPLE IT. The first cut polled every 250 ms and went
// green against the OLD hook: PGlite answers in-tab within a few milliseconds, so the blank fell
// between two samples every time (on production the round-trip to Seoul is what made it visible).
// A `MutationObserver` on the open tray records EVERY unmount of a named row, every change of the
// stepper's value and every flip of the button's `disabled` — and after more than three beats the
// record must be empty. Run against the old hook it logged the blank on the beat exactly: 87,
// 3088, 6087, 9078 ms (stepper 10 → 0, button dead, ~75 ms each). The in-tab world is disposable
// PGlite, so the trades it sends land nowhere that matters.
//
// The build under test must be served: `npm run build && npx vite preview --port <n>`, then
// PLAYWRIGHT_BASE_URL=http://localhost:<n>/byeharu-voyage/ (localhost, not 127.0.0.1 — the
// preview binds IPv6 only and a v4 base URL makes every browser spec SKIP).

import { test, expect, type Page } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'

test.use({ viewport: PHONE })

/** Longer than three of the shell's 3-s reads, with slack for the re-ask itself to land. */
const CEILING_WINDOW_MS = 10_500
const STORAGE_WINDOW_MS = 7_500

/** What the watcher writes down: one line per thing that moved, with the ms since it was armed. */
interface Moved {
  at: number
  what: string
}

declare global {
  interface Window {
    __trayWatch?: { log: Moved[]; stop: () => void }
  }
}

/** Arm a watcher on `trayId`'s subtree. `rowIds` are rows that must never leave (a React re-render
 *  that swaps a row's `data-testid` in place counts as leaving), `waitId` a row that must never
 *  arrive, `rangeId` the stepper whose value must never move, `buttonId` the button whose
 *  `disabled` must never flip, and `never` a text that must never appear. Runs in the page. */
const ARM = ({
  trayId,
  rowIds,
  waitId,
  rangeId,
  buttonId,
  never,
}: {
  trayId: string
  rowIds: string[]
  waitId?: string
  rangeId?: string
  buttonId?: string
  never?: string
}) => {
  const tray = document.querySelector(`[data-testid="${trayId}"]`)
  if (!tray) throw new Error(`no ${trayId} to watch`)
  const t0 = Date.now()
  const log: Moved[] = []
  const has = (n: Node, id: string) =>
    n instanceof HTMLElement && (n.getAttribute('data-testid') === id || n.querySelector(`[data-testid="${id}"]`) !== null)
  const rangeOf = () =>
    rangeId ? ((tray.querySelector(`[data-testid="${rangeId}"] input[type="range"]`) as HTMLInputElement | null)?.value ?? '') : ''
  const disabledOf = () =>
    buttonId ? ((tray.querySelector(`[data-testid="${buttonId}"]`) as HTMLButtonElement | null)?.disabled ?? null) : null
  let lastRange = rangeOf()
  let lastDisabled = disabledOf()
  const neverRe = never ? new RegExp(never, 'i') : null
  const obs = new MutationObserver((records) => {
    const at = Date.now() - t0
    for (const r of records) {
      r.removedNodes.forEach((n) => {
        for (const id of rowIds) if (has(n, id)) log.push({ at, what: `${id} unmounted` })
      })
      r.addedNodes.forEach((n) => {
        if (waitId && has(n, waitId)) log.push({ at, what: `${waitId} mounted` })
        if (neverRe && neverRe.test(n.textContent ?? '')) log.push({ at, what: `"${never}" appeared` })
      })
      if (r.type === 'attributes' && r.attributeName === 'data-testid') {
        const el = r.target as HTMLElement
        for (const id of rowIds) if (r.oldValue === id && el.getAttribute('data-testid') !== id) log.push({ at, what: `${id} became ${el.getAttribute('data-testid')}` })
      }
      if (r.type === 'characterData' && neverRe && neverRe.test(r.target.textContent ?? '')) log.push({ at, what: `"${never}" appeared` })
    }
    // The stepper is a controlled input: React writes `value` as a property, which no observer
    // sees, so it is read on every batch of mutations (a clamp re-renders the tray).
    const nowRange = rangeOf()
    if (nowRange !== lastRange) {
      log.push({ at, what: `${rangeId} ${lastRange} → ${nowRange}` })
      lastRange = nowRange
    }
    const nowDisabled = disabledOf()
    if (nowDisabled !== lastDisabled) {
      log.push({ at, what: `${buttonId} disabled ${lastDisabled} → ${nowDisabled}` })
      lastDisabled = nowDisabled
    }
  })
  obs.observe(tray, {
    childList: true,
    subtree: true,
    characterData: true,
    attributes: true,
    attributeOldValue: true,
    attributeFilter: ['disabled', 'value', 'data-testid'],
  })
  window.__trayWatch = { log, stop: () => obs.disconnect() }
  return { range: lastRange, disabled: lastDisabled }
}

const READ = () => {
  const w = window.__trayWatch
  if (!w) throw new Error('no watcher armed')
  w.stop()
  return w.log
}

/** The `data-testid`s inside `trayId`, in document order — the body's order as the player reads it. */
const ORDER = (trayId: string) =>
  [...document.querySelectorAll(`[data-testid="${trayId}"] [data-testid]`)].map((el) => el.getAttribute('data-testid') ?? '')

async function openPort(page: Page, request: { get: (url: string) => Promise<{ ok(): boolean }> }, baseURL: string | undefined) {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('port')
  await ready(page)
  await page.waitForTimeout(1200)
  const rows = page.locator('[data-testid="trade-row"]')
  expect(await rows.count(), 'no ledger rows — is PORT open on its Trade face with a fleet docked?').toBeGreaterThan(1)
  return rows
}

/** Press the first live `buy` cell; returns the good's name off its row. */
async function pressBuy(page: Page) {
  const name = await page.evaluate(() => {
    const cell = [...document.querySelectorAll('[data-testid="trade-row"] button:enabled')].find((b) =>
      /^buy\b/i.test(((b as HTMLElement).innerText || '').trim()),
    ) as HTMLButtonElement | undefined
    const row = cell?.closest('[data-testid="trade-row"]') as HTMLElement | null
    cell?.click()
    return row ? (row.innerText || '').split('\n')[0].trim() : ''
  })
  expect(name, 'no live buy cell to press').not.toBe('')
  await expect(page.locator('[data-testid="trade-tray"]')).toBeVisible()
  return name
}

test(`PORT › Trade (buy): the Max row, the stepper and the button hold still across three world reads; the count comes before the context`, async ({ page, request, baseURL }, testInfo) => {
  const rows = await openPort(page, request, baseURL)
  await pressBuy(page)
  const tray = page.locator('[data-testid="trade-tray"]')

  // THE FIRST ANSWER: the ceiling lands once, and the button is priced for it.
  const maxRow = tray.locator('[data-testid="trade-tray-max"]')
  await expect(maxRow, 'world.buy_capacity never answered — no Max row').toBeVisible({ timeout: 20_000 })
  await expect(tray.locator('[data-testid="trade-tray-send"]')).toBeEnabled({ timeout: 20_000 })
  // Let the first dry run settle too, so the watcher is armed on a tray at rest.
  await page.waitForTimeout(1000)
  const maxText = ((await maxRow.innerText()) || '').replace(/\s+/g, ' ').trim()
  expect(maxText, 'the Max row carries no figure').toMatch(/\d/)

  // THE ORDER ON BUY: Max, then the count, then what it does to the ship, then the market's
  // context (trend · range · stock) — below the decision, not above it. No profit row on a buy.
  const order = await page.evaluate(ORDER, 'trade-tray')
  const at = (id: string) => order.indexOf(id)
  expect(at('trade-tray-max'), 'no Max row on the buy face').toBeGreaterThanOrEqual(0)
  expect(at('trade-tray-qty'), 'no stepper on the buy face').toBeGreaterThan(at('trade-tray-max'))
  expect(at('trade-tray-space'), 'Cargo space is not under the count on buy').toBeGreaterThan(at('trade-tray-qty'))
  expect(at('trend-row'), 'the trend is not BELOW the count on buy').toBeGreaterThan(at('trade-tray-qty'))
  expect(at('quay-stock'), 'In stock is not BELOW the count on buy').toBeGreaterThan(at('trade-tray-qty'))
  expect(order).not.toContain('trade-tray-profit')
  await page.screenshot({ path: testInfo.outputPath('buy-tray.png') })

  const armed = await page.evaluate(ARM, {
    trayId: 'trade-tray',
    rowIds: ['trade-tray-max'],
    waitId: 'trade-tray-max-unknown',
    rangeId: 'trade-tray-qty',
    buttonId: 'trade-tray-send',
  })
  expect(Number(armed.range), 'the stepper holds no quantity').toBeGreaterThan(0)
  expect(armed.disabled, 'the Buy button is dead when the watcher is armed').toBe(false)
  await page.waitForTimeout(CEILING_WINDOW_MS)
  const moved = await page.evaluate(READ)
  const stillThere = ((await maxRow.innerText()) || '').replace(/\s+/g, ' ').trim()
  console.log(`PORT trade ceiling @${PHONE.width}px: "${maxText}", stepper ${armed.range}, watched ${CEILING_WINDOW_MS} ms, ${moved.length} moves`)

  expect(
    moved.map((m) => `${m.at}ms: ${m.what}`),
    'the tray moved on a world read — the Max row unmounted, the waiting row appeared, the stepper ' +
      'clamped or the button died (owner: "when i press buy, the max keeps refreshing")',
  ).toEqual([])
  expect(stillThere, 'the Max figure changed across the window').toBe(maxText)

  // SEND IT, so something is on board for the Storage leg; the tray closes when the order lands.
  await tray.locator('[data-testid="trade-tray-send"]').click()
  await expect(tray).toHaveCount(0, { timeout: 30_000 })
  await expect(rows.filter({ hasText: /\d units? on board/ }).first()).toBeVisible({ timeout: 20_000 })

  // THE STORAGE TRAY — the useOrderPreview leg. Choose a count, wait for the dry run to answer,
  // then watch: the button must not flip `disabled`, the line must not change, no refusal may
  // mount, across more than two beats.
  await page.getByRole('tab', { name: /^Storage$/i }).first().click()
  await expect(page.locator('[data-testid="port-storage"]')).toBeVisible()
  await expect(page.locator('[data-testid="storage-row"]').first()).toBeVisible({ timeout: 20_000 })
  const put = await page.evaluate(() => {
    const cell = [...document.querySelectorAll('[data-testid="storage-row"] button:enabled')].find((b) =>
      /^Put in storage/i.test(((b as HTMLElement).innerText || '').trim()),
    ) as HTMLButtonElement | undefined
    cell?.click()
    return cell !== undefined
  })
  expect(put, 'no live `Put in storage` cell — did the buy land?').toBe(true)
  const storageTray = page.locator('[data-testid="storage-tray"]')
  await expect(storageTray).toBeVisible()
  const act = storageTray.locator('[data-testid="storage-act"]')
  await expect(act, 'the move was never previewed — cmd.preview did not answer').toBeEnabled({ timeout: 20_000 })
  await expect(act).toHaveText(/^Put \d+ units? in storage$/)
  await page.waitForTimeout(500)
  const actText = ((await act.innerText()) || '').trim()

  const armedStorage = await page.evaluate(ARM, {
    trayId: 'storage-tray',
    rowIds: ['storage-act'],
    waitId: 'storage-preview-refusal',
    rangeId: 'storage-qty',
    buttonId: 'storage-act',
  })
  expect(armedStorage.disabled, 'the Storage button is dead when the watcher is armed').toBe(false)
  await page.waitForTimeout(STORAGE_WINDOW_MS)
  const movedStorage = await page.evaluate(READ)
  console.log(`PORT storage tray @${PHONE.width}px: "${actText}", watched ${STORAGE_WINDOW_MS} ms, ${movedStorage.length} moves`)
  expect(
    movedStorage.map((m) => `${m.at}ms: ${m.what}`),
    'the Storage tray moved on a world read — useOrderPreview dropped its answer',
  ).toEqual([])
  expect(((await act.innerText()) || '').trim(), 'the Storage button line changed across the window').toBe(actText)
})

test(`PORT › Trade (sell): count first, then three prices and the share; no "checking" line across three reads and two presses; one unit chosen three ways and sold`, async ({ page, request, baseURL }, testInfo) => {
  const rows = await openPort(page, request, baseURL)

  // SOMETHING ON BOARD: buy the default lot of the first live good, and wait for the world to say so.
  const name = await pressBuy(page)
  const buyTray = page.locator('[data-testid="trade-tray"]')
  const send = buyTray.locator('[data-testid="trade-tray-send"]')
  await expect(send).toBeEnabled({ timeout: 20_000 })
  await send.click()
  await expect(buyTray).toHaveCount(0, { timeout: 30_000 })
  const row = rows.filter({ hasText: name }).first()
  await expect(row).toContainText(/\d units? on board/, { timeout: 20_000 })
  const aboardBefore = Number(((await row.innerText()).match(/(\d+) units? on board/) ?? [])[1])
  expect(aboardBefore, 'the buy landed nothing on board').toBeGreaterThan(1)

  // OPEN THE SELL TRAY on that row.
  // `hasText` reads textContent, where the cell is `sell75` — no word boundary after the label.
  await row.locator('button', { hasText: /^sell/i }).first().click()
  const tray = page.locator('[data-testid="trade-tray"]')
  await expect(tray).toBeVisible()
  const sendSell = tray.locator('[data-testid="trade-tray-send"]')
  await expect(sendSell).toHaveText(/^Sell \d+ units? · [\d,]+\s🪙$/, { timeout: 20_000 })
  await expect(tray.locator('[data-testid="trade-tray-fetches"]')).toBeVisible()
  await page.waitForTimeout(600)

  // THE ORDER ON SELL, and what is NOT there. The count first; then what it cost her, what it
  // sells at, what she gets with the share under it. No trend, no range, no stock, no cargo
  // space, no `On board` row, no waiting line for the ceiling.
  const order = await page.evaluate(ORDER, 'trade-tray')
  const at = (id: string) => order.indexOf(id)
  expect(at('trade-tray-qty'), 'no stepper on the sell face').toBeGreaterThanOrEqual(0)
  expect(at('trade-tray-paid'), 'no Bought at on the sell face').toBeGreaterThan(at('trade-tray-qty'))
  expect(at('trade-tray-sells-at'), 'no Sells at on the sell face').toBeGreaterThan(at('trade-tray-paid'))
  expect(at('trade-tray-fetches'), 'no You get on the sell face').toBeGreaterThan(at('trade-tray-sells-at'))
  expect(at('trade-tray-gain-share'), 'no share under You get').toBeGreaterThan(at('trade-tray-fetches'))
  for (const gone of ['trend-row', 'quay-stock', 'trade-tray-space', 'trade-tray-max', 'trade-tray-max-unknown']) {
    expect(order, `${gone} is still on the sell face`).not.toContain(gone)
  }
  const text = (await tray.innerText()).replace(/\s+/g, ' ')
  expect(text).not.toMatch(/\bRange\b/)
  expect(text).not.toMatch(/\bIn stock\b/)
  expect(text).not.toMatch(/\bOn board\b/)
  expect(text).not.toMatch(/Checking/i)
  await page.screenshot({ path: testInfo.outputPath('sell-tray.png') })
  // THE SHARE, with its whole on the same face: profit d. · +N% in the pinned row, the cost under Bought at.
  await expect(tray.locator('[data-testid="trade-tray-profit"]')).toHaveText(/[+−-][\d,]+\s🪙 · [+−-]?\d+%|0\s🪙 · 0%/)
  await expect(tray.locator('[data-testid="trade-tray-paid"]')).toContainText(/[\d,]+\s🪙 for \d+ units?/)
  await expect(tray.locator('[data-testid="trade-tray-gain-share"]')).toHaveText(/^[+−-]?\d+% on what it cost$/)

  // NO "CHECKING" LINE, across three beats AND two presses: the figures stand (dimmed while the
  // new quantity's are on the wire), the You get row never leaves, the button never dies.
  await page.evaluate(ARM, {
    trayId: 'trade-tray',
    rowIds: ['trade-tray-fetches', 'trade-tray-paid', 'trade-tray-sells-at'],
    buttonId: 'trade-tray-send',
    never: 'Checking',
  })
  await page.waitForTimeout(2_500)
  await tray.getByRole('button', { name: 'Less' }).click()
  await page.waitForTimeout(3_000)
  await tray.getByRole('button', { name: 'More' }).click()
  await page.waitForTimeout(5_000)
  const moved = await page.evaluate(READ)
  console.log(`PORT sell tray @${PHONE.width}px: watched 10500 ms with a − and a +, ${moved.length} moves`)
  expect(
    moved.map((m) => `${m.at}ms: ${m.what}`),
    'the sell tray moved — a "Checking" line, a row unmounted, or the button died (owner: "a refresh sign of checking the price... keeps showing up")',
  ).toEqual([])
  await expect(sendSell).toHaveText(/^Sell \d+ units? · [\d,]+\s🪙$/, { timeout: 20_000 })

  // ONE UNIT, THREE WAYS. The figure input and the slider are the one control (Stepper.tsx).
  const figure = tray.locator('[data-testid="stepper-figure"]')
  const range = tray.locator('[data-testid="trade-tray-qty"] input[type="range"]')
  const less = tray.getByRole('button', { name: 'Less' })
  // (a) − from the lot, one press at a time, down to 1 — and no further.
  const start = Number((await figure.inputValue()).replace(/\D/g, ''))
  for (let i = start; i > 1; i--) await less.click()
  await expect(figure).toHaveValue('1')
  await expect(less, '− walks below one').toBeDisabled()
  await expect(sendSell).toHaveText(/^Sell 1 unit · [\d,]+\s🪙$/, { timeout: 20_000 })
  // (b) typed: back to the lot by chip, then type 1 and Enter.
  await tray.locator('[data-testid="trade-tray-qty"] button', { hasText: /^\d+$/ }).last().click()
  await expect(figure).not.toHaveValue('1')
  await figure.click()
  await figure.fill('1')
  await figure.press('Enter')
  await expect(figure).toHaveValue('1')
  await expect(range).toHaveValue('1')
  await expect(sendSell).toHaveText(/^Sell 1 unit · [\d,]+\s🪙$/, { timeout: 20_000 })
  // (c) the slider by keyboard: type 2, then ArrowLeft steps by ONE.
  await figure.click()
  await figure.fill('2')
  await figure.press('Enter')
  await expect(range).toHaveValue('2')
  await range.focus()
  await range.press('ArrowLeft')
  await expect(range).toHaveValue('1')
  await expect(figure).toHaveValue('1')
  await expect(sendSell).toHaveText(/^Sell 1 unit · [\d,]+\s🪙$/, { timeout: 20_000 })
  // Nonsense reverts; Home clamps to the floor of one, not nought.
  await figure.click()
  await figure.fill('')
  await figure.press('Enter')
  await expect(figure).toHaveValue('1')
  await range.focus()
  await range.press('Home')
  await expect(range).toHaveValue('1')

  // AND IT SELLS ONE: the tray closes, and exactly one unit left the hold.
  await sendSell.click()
  await expect(tray).toHaveCount(0, { timeout: 30_000 })
  await expect(row).toContainText(new RegExp(`${aboardBefore - 1} units? on board`), { timeout: 20_000 })
})

// THE WIDE GLASS, for the count: on a phone an EMPTY basket docks nothing (ManifestPanel.tsx), so
// the on-board list — the thing being counted — only stands at rest in the right-hand slot of a
// 1440×900 glass, where the basket panel always shows.
test.describe('the asks, counted', () => {
  test.use({ viewport: { width: 1440, height: 900 } })

  test(`PORT › Trade: an open on-board list makes NO dry run on the world's beat; an open sell tray makes at most one per beat`, async ({ page, request, baseURL }) => {
  // THE COST THAT MUST NOT BE PAID. `cmd.preview` is a real write rolled back, and the on-board
  // list is a LIST: folded onto useServedRead in its default mode it would have made N writes every
  // 3 s per player on a live ~30-player database. Since 2026-09-18 the on-board list makes NO ask
  // at all — its figure is the gap of two prices already served (OnBoard.tsx) — and this counts
  // the asks off the ONE debug
  // line `src/lib/rpc/backend.ts` prints per RPC. A sell tray ('beat' mode) may ask once per beat.
  const rows = await openPort(page, request, baseURL)
  // COUNTED IN THE PAGE, on the page's clock. Playwright hands console events over in batches,
  // so an ask made before a window opened can be DELIVERED inside it (measured: nine "asks" in a
  // window that held three). The wrapper below stamps each `[rpc]` line with `performance.now()`
  // as it is printed, and a window is two page-side marks.
  await page.evaluate(() => {
    const log: { at: number; label: string }[] = []
    const debug = console.debug.bind(console)
    console.debug = (...args: unknown[]) => {
      if (args[0] === '[rpc]' && typeof args[1] === 'string') log.push({ at: performance.now(), label: args[1].replace(/\(.*$/, '') })
      debug(...args)
    }
    ;(window as unknown as { __rpcLog: typeof log }).__rpcLog = log
  })
  const mark = () => page.evaluate(() => performance.now())
  const asksBetween = (from: number, to: number) =>
    page.evaluate(
      ([a, b]) => (window as unknown as { __rpcLog: { at: number; label: string }[] }).__rpcLog.filter((e) => e.at >= a && e.at < b),
      [from, to] as const,
    )
  const previewsIn = (asks: { label: string }[]) => asks.filter((e) => e.label === 'cmd.preview').length
  const line = (asks: { at: number; label: string }[], from: number) => asks.map((e) => `${((e.at - from) / 1000).toFixed(1)}s ${e.label}`).join(' · ')

  // Something on board, so the list has a row with a sale estimate.
  const name = await pressBuy(page)
  const tray = page.locator('[data-testid="trade-tray"]')
  const send = tray.locator('[data-testid="trade-tray-send"]')
  await expect(send).toBeEnabled({ timeout: 20_000 })
  await send.click()
  await expect(tray).toHaveCount(0, { timeout: 30_000 })
  const row = rows.filter({ hasText: name }).first()
  await expect(row).toContainText(/\d units? on board/, { timeout: 20_000 })
  await expect(page.locator('[data-testid="basket-panel"]')).toBeVisible({ timeout: 20_000 })
  await expect(
    page.locator('[data-testid^="on-board-sale-"]').first(),
    'no on-board sale row — is the basket panel showing the list?',
  ).toBeVisible({ timeout: 20_000 })
  // Let the first answers land, then count over more than three beats with no interaction.
  await page.waitForTimeout(2_000)
  const listFrom = await mark()
  await page.waitForTimeout(10_500)
  const listAsks = await asksBetween(listFrom, await mark())
  console.log(`PORT on-board list @1440px: ${previewsIn(listAsks)} cmd.preview asks in 10.5 s at rest — ${line(listAsks, listFrom)}`)
  expect(previewsIn(listAsks), "the on-board list re-asked its sale estimates on the world's beat").toBe(0)
  expect(listAsks.filter((e) => e.label === 'world.fleets').length, 'the world was not read during the window — the count proves nothing').toBeGreaterThanOrEqual(2)

  // The sell tray, open and at rest: one dry run per beat at most — and at least two in three
  // beats, or the world is not being read and the count above proves nothing.
  await row.locator('button', { hasText: /^sell/i }).first().click()
  await expect(tray).toBeVisible()
  await expect(send).toHaveText(/^Sell \d+ units? · [\d,]+\s🪙$/, { timeout: 20_000 })
  await page.waitForTimeout(1_000)
  const trayFrom = await mark()
  await page.waitForTimeout(10_500)
  const trayAsks = await asksBetween(trayFrom, await mark())
  const trayPreviews = previewsIn(trayAsks)
  console.log(`PORT sell tray @1440px: ${trayPreviews} cmd.preview asks in 10.5 s at rest — ${line(trayAsks, trayFrom)}`)
  expect(trayPreviews, 'the open sell tray asked more than once per 3-s beat').toBeLessThanOrEqual(4)
  expect(trayPreviews, 'the open sell tray never re-asked on the beat — is the world being read?').toBeGreaterThanOrEqual(2)
})
})
