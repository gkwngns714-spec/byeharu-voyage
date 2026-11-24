import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { LOCALES } from './korean.paused'
import { corpWorld } from './corpWorld.fixture'
import { serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ CORP: THE ONE WORKER LIST AND THE ONE ASSIGN SHEET (2026-11-24, docs/design/hq-corp-2026-11-24.md A2, B3, C; slice H1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-24: *"it is like madevor's rs3 jagex game idle game, but instead of doing with only 1 player, i do it with
// multiple"*. HQ lists every worker (each fleet, and the land party) as one row on one action with a bar, the idle ones first.
//
// THE LAW, at 390 x 844 and 1440 x 900, English (Korean is paused):
//   * the idle fleet's row is first, and its press opens the Assign sheet over HQ (the URL stays /city);
//   * Assign asks world.actions ONCE when it opens (0496) and offers its runs, the best served coin an hour first, each priced for
//     what her purse can buy; a run's figures (what it leaves, its units, its cost, its time, its coin an hour) stand before the
//     press AS SERVED; Assign gives her that fixed run (cmd.set_fleet_job): her row says "<good> · <buy> → <sell> · Sell";
//   * once public.tick_fleet_jobs has run she sails, and her bar moves between her voyage's two served stamps;
//   * the party's Assign sends it (cmd.land_send), and its row shows the trip's bar;
//   * her sheet's Stop takes the job away (cmd.clear_fleet_job);
//   * every row keeps its height whatever its state, and its place; nothing scrolls sideways; every press is 44 px;
//   * a row prints the coin an hour and the XP an hour world.workers() serves for her (0496), and none where it serves none: a fixed
//     run just set has `basis` none (no rate yet), the party's job its served XP an hour.
//
// THE WORLD: tests/corpWorld.fixture.ts (the switches production runs lit, the served board, the standing jobs and the Land lit; the
// jobs tick run right after a job is set).

const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const
const OUT = 'test-results/hq-corp'

/** A figure as drawn, down to its digits ("+1,234 / h" is "1234"). */
const digits = (s: string) => s.replace(/[^0-9]/g, '')

const sideways = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)

/** Each worker row's id and height, in the order drawn. */
const rowsOf = (page: Page) =>
  page.evaluate(() =>
    [...document.querySelectorAll('[data-testid="corp-worker"]')].map((el) => ({
      id: el.getAttribute('data-worker'),
      state: el.getAttribute('data-state'),
      height: Math.round(el.getBoundingClientRect().height),
    })),
  )

/** Presses on the glass under 44 px (visible ones). */
const smallPresses = (page: Page, scope: string) =>
  page.evaluate(
    (sel) =>
      [...document.querySelectorAll(`${sel} button`)]
        .map((b) => ({ r: b.getBoundingClientRect(), id: b.getAttribute('data-testid') }))
        .filter((x) => x.r.width > 0 && (x.r.height < 43.5 || x.r.width < 43.5))
        .map((x) => `${x.id} ${Math.round(x.r.width)}x${Math.round(x.r.height)}`),
    scope,
  )

for (const size of SIZES)
  for (const locale of LOCALES)
    test.describe(`${locale}`, () => {
      test.use({ locale })
      test(`HQ @${size.width} ${locale}: the worker list, Assign a sea trade and a land job, the bars, Stop (H1)`, async ({ page, request, baseURL }) => {
        test.setTimeout(900_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        // every ask the page makes prints one debug line (src/lib/rpc/backend.ts): Assign's read is counted
        let actionAsks = 0
        page.on('console', (m) => {
          if (m.type() === 'debug' && m.text().includes('world.actions(')) actionAsks++
        })
        // sea_courses lit: world.actions offers only runs the server would take, and with no course held a fresh company may be offered none
        await serveWorldImage(page, await corpWorld({ courses: true }))
        await page.setViewportSize(size)
        await page.goto('city')
        await ready(page)
        const list = page.getByTestId('corp-worker-list')
        await expect(list).toBeVisible({ timeout: 300_000 })

        // THE LIST: a fleet and the party, the idle fleet first; it stands over the board
        const first = page.getByTestId('corp-worker').first()
        await expect(first).toHaveAttribute('data-kind', 'fleet')
        await expect(first).toHaveAttribute('data-state', 'idle')
        const fleet = (await first.getAttribute('data-worker'))!
        const party = page.locator('[data-testid="corp-worker"][data-kind="party"]')
        await expect(party).toHaveAttribute('data-state', 'idle')
        const before = await rowsOf(page)
        expect(new Set(before.map((r) => r.height)).size, `rows of more than one height: ${JSON.stringify(before)}`).toBe(1)
        const listTop = await list.evaluate((el) => el.getBoundingClientRect().top)
        const boardTop = await page.getByTestId('hq-board').evaluate((el) => el.getBoundingClientRect().top)
        expect(listTop, 'the worker list does not stand before the board').toBeLessThan(boardTop)
        expect(await sideways(page), 'HQ scrolls sideways').toBe(false)
        await page.screenshot({ path: `${OUT}/list-idle-${size.width}.png` })

        // ASSIGN, SEA TRADE: the sheet over HQ; a good; where it sells; the server's quote; one press
        const url = page.url()
        await first.click()
        const sheet = page.getByTestId('hq-sheet-assign')
        await expect(sheet).toBeVisible({ timeout: 60_000 })
        expect(page.url(), 'Assign left HQ').toBe(url)
        const go = sheet.getByTestId('corp-assign-go')
        await expect(go, 'Assign is open before anything is chosen').toBeDisabled()
        const runs = sheet.getByTestId('corp-assign-run')
        await expect(runs.first()).toBeVisible({ timeout: 180_000 })
        // THE RUNS ARE THE SERVER'S: one ask for the sheet, the best served coin an hour first, each within her purse
        const purse = Number(digits(await page.getByTestId('purse').innerText()))
        const served = await runs.evaluateAll((els) =>
          els.map((el) => ({ perHour: Number(el.getAttribute('data-per-hour')), cost: Number(el.getAttribute('data-cost')), units: Number(el.getAttribute('data-units')) })),
        )
        expect(served.map((r) => r.perHour), 'the runs are not in the order of the served coin an hour').toEqual([...served.map((r) => r.perHour)].sort((x, y) => y - x))
        for (const r of served) {
          expect(r.units, 'a run of no units is offered').toBeGreaterThan(0)
          expect(r.cost, `a run costing ${r.cost} is offered to a purse of ${purse}`).toBeLessThanOrEqual(purse)
        }
        let assigned = false
        for (let s = 0; s < served.length && !assigned; s++) {
          const run = runs.nth(s)
          await run.click()
          const quote = sheet.getByTestId('corp-assign-quote')
          await expect(quote, 'no quote before the press').toBeVisible()
          // THE FIGURES ARE THE SERVED ONES: the foot says the picked option's own numbers
          for (const k of ['data-per-hour', 'data-units', 'data-cost']) expect(await quote.getAttribute(k), `${k} of the foot is not the option's`).toBe(await run.getAttribute(k))
          expect(await quote.getAttribute('data-profit')).toBe(await run.getAttribute('data-net'))
          expect(digits(await quote.getByTestId('corp-assign-profit').innerText()), 'the profit drawn is not the served net').toBe(digits(String(await quote.getAttribute('data-profit'))))
          const rate = quote.getByTestId('corp-assign-rate')
          expect(digits(await rate.innerText()), 'the coin an hour drawn is not the served per_hour').toBe(digits(String(await rate.getAttribute('data-per-hour'))))
          expect(await rate.getAttribute('data-per-hour')).toBe(await run.getAttribute('data-per-hour'))
          await expect(quote.getByTestId('corp-assign-time')).not.toHaveText('')
          await expect(go).toBeEnabled()
          expect(await sideways(page), 'Assign scrolls sideways').toBe(false)
          expect(await smallPresses(page, '[data-testid="hq-sheet-assign"]'), 'Assign presses under 44 px').toEqual([])
          if (s === 0) await page.screenshot({ path: `${OUT}/assign-sea-${size.width}.png` })
          await go.click()
          // committed: the sheet closes; refused: the server's words stand, and the next run is tried
          await expect
            .poll(async () => (await sheet.count()) === 0 || (await sheet.getByTestId('corp-assign-refusal').count()) > 0, { timeout: 120_000 })
            .toBe(true)
          assigned = (await sheet.count()) === 0
        }
        expect(actionAsks, 'Assign asked world.actions more than once for one opening').toBe(1)
        expect(assigned, 'no run the server offered could be assigned').toBe(true)
        expect(page.url(), 'the assignment left HQ').toBe(url)

        // HER ROW: the action, in its place, at its height; the tick has run, so she sails and the bar moves between served stamps
        const hers = page.locator(`[data-testid="corp-worker"][data-worker="${fleet}"]`)
        await expect(hers).toHaveAttribute('data-action', 'fixed', { timeout: 120_000 })
        await expect(hers.getByTestId('corp-worker-action')).toHaveText(/.+ · .+ → .+ · Sell/)
        await expect(hers, 'her fleet did not sail on her job').toHaveAttribute('data-state', 'working')
        const bar = hers.getByTestId('corp-worker-bar')
        await expect(bar, 'no bar under way').toHaveAttribute('data-on', 'true', { timeout: 180_000 })
        const clock = hers.getByTestId('corp-worker-clock')
        const c0 = await clock.innerText()
        await expect.poll(async () => clock.innerText(), { timeout: 30_000, message: 'the clock to her arrival does not move' }).not.toBe(c0)
        const f0 = Number(await bar.getAttribute('data-fill'))
        await expect
          .poll(async () => Number(await bar.getAttribute('data-fill')), { timeout: 120_000, message: 'the bar does not move' })
          .toBeGreaterThan(f0)
        // her job's tally is While away's, said once there: her row does not repeat it
        await expect(hers.locator('[data-figure="runs"], [data-figure="earned"]')).toHaveCount(0)
        await expect(page.getByTestId('hq-away-job')).toHaveCount(1, { timeout: 120_000 })
        // A RATE THE SERVER DOES NOT SERVE IS NOT DRAWN: a fixed run just set has no runs of hers to read (basis none)
        await expect(hers.getByTestId('corp-worker-figures')).toHaveAttribute('data-basis', 'none', { timeout: 120_000 })
        await expect(hers.locator('[data-testid="corp-worker-rate"], [data-testid="corp-worker-xp"]'), 'a rate is drawn where none is served').toHaveCount(0)

        // ASSIGN, LAND: the party's sheet; a job of the home land; its served terms; one press
        await party.click()
        await expect(sheet).toBeVisible({ timeout: 60_000 })
        const iron = sheet.locator('[data-testid="corp-assign-job"][data-job="iron"]')
        await expect(iron).toBeVisible({ timeout: 120_000 })
        await iron.click()
        await expect(sheet.getByTestId('corp-assign-terms')).toHaveAttribute('data-job', 'iron')
        await expect(sheet.getByTestId('corp-assign-trip')).not.toHaveText('')
        const xpServed = String(await sheet.getByTestId('corp-assign-terms').getAttribute('data-xp-hour'))
        expect(Number(xpServed), 'the job serves no XP an hour').toBeGreaterThan(0)
        expect(digits(await sheet.getByTestId('corp-assign-xp').innerText()), 'the XP an hour drawn is not the served one').toBe(xpServed)
        expect(actionAsks, 'the Assign of the party did not ask world.actions once').toBe(2)
        expect(await sideways(page), 'the Land Assign scrolls sideways').toBe(false)
        await page.screenshot({ path: `${OUT}/assign-land-${size.width}.png` })
        await go.click()
        await expect(sheet).toHaveCount(0, { timeout: 120_000 })
        await expect(party).toHaveAttribute('data-state', 'working', { timeout: 120_000 })
        await expect(party.getByTestId('corp-worker-action')).toContainText('Iron')
        await expect(party.getByTestId('corp-worker-bar')).toHaveAttribute('data-on', 'true')
        // HER ROW'S RATES ARE world.workers()': the job's XP an hour as Assign served it, and no coin an hour (the Land moves no coin)
        await expect(party.getByTestId('corp-worker-figures')).toHaveAttribute('data-basis', 'terms')
        await expect(party.getByTestId('corp-worker-figures')).toHaveAttribute('data-xp-hour', xpServed)
        expect(digits(await party.getByTestId('corp-worker-xp').innerText()), 'the XP an hour on her row is not the served one').toBe(xpServed)
        await expect(party.getByTestId('corp-worker-rate')).toHaveCount(0)
        expect(page.url(), 'the Land assignment left HQ').toBe(url)

        // NOTHING MOVED: every row at the height it had, in the place it had
        const after = await rowsOf(page)
        expect(after.map((r) => r.id), 'a row changed its place').toEqual(before.map((r) => r.id))
        expect(after.map((r) => r.height), 'a row changed its height with its state').toEqual(before.map((r) => r.height))
        expect(await sideways(page), 'HQ scrolls sideways').toBe(false)
        expect(await smallPresses(page, '[data-testid="corp-workers"]'), 'worker presses under 44 px').toEqual([])
        await page.getByTestId('corp-workers').scrollIntoViewIfNeeded()
        await page.screenshot({ path: `${OUT}/list-working-${size.width}.png` })
        await page.screenshot({ path: `${OUT}/hq-full-${size.width}.png`, fullPage: true })

        // THE LEDGER: the money by line (no net of its own: the Rank strip's is HQ's one per-hour figure), and its press is the Report, in place
        const ledger = page.getByTestId('corp-ledger')
        await expect(ledger).toBeVisible({ timeout: 120_000 })
        await ledger.scrollIntoViewIfNeeded()
        await page.screenshot({ path: `${OUT}/areas-${size.width}.png` })
        await ledger.getByTestId('corp-ledger-open').click()
        await expect(page.getByTestId('hq-sheet-report')).toBeVisible({ timeout: 60_000 })
        await page.keyboard.press('Escape')
        await expect(page.getByTestId('hq-sheet-report')).toHaveCount(0)

        // HER SHEET: the action, and Stop takes the job away
        await hers.click()
        const own = page.getByTestId('hq-sheet-worker')
        await expect(own).toBeVisible({ timeout: 60_000 })
        await expect(own.getByTestId('corp-sheet-action')).toHaveText(/.+ → .+ · Sell/)
        await expect(own.getByTestId('corp-sheet-rates'), 'her sheet draws a rate the server does not serve').toHaveCount(0)
        expect(await smallPresses(page, '[data-testid="hq-sheet-worker"]'), 'sheet presses under 44 px').toEqual([])
        await page.screenshot({ path: `${OUT}/worker-sheet-${size.width}.png` })
        await own.getByTestId('corp-sheet-stop').click()
        await expect(own).toHaveCount(0, { timeout: 120_000 })
        await expect(hers).not.toHaveAttribute('data-action', 'fixed', { timeout: 120_000 })
        expect(page.url(), 'her sheet left HQ').toBe(url)
        expect((await rowsOf(page)).map((r) => r.height), 'a row changed its height after Stop').toEqual(before.map((r) => r.height))
      })
    })
