import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { LOCALES } from './korean.paused'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ CORP: THE ONE WORKER LIST AND THE ONE ASSIGN SHEET (2026-11-24, docs/design/hq-corp-2026-11-24.md A2, B3, C; slice H1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-24: *"it is like madevor's rs3 jagex game idle game, but instead of doing with only 1 player, i do it with
// multiple"*. HQ lists every worker (each fleet, and the land party) as one row on one action with a bar, the idle ones first.
//
// THE LAW, at 390 x 844 and 1440 x 900, English (Korean is paused):
//   * the idle fleet's row is first, and its press opens the Assign sheet over HQ (the URL stays /city);
//   * Sea trade: a good, where it is sold, and the SERVER'S quote (the run's profit and its time) stands before the press; Assign
//     gives her that fixed run (cmd.set_fleet_job): her row says "<good> · <buy> → <sell> · Sell";
//   * once public.tick_fleet_jobs has run she sails, and her bar moves between her voyage's two served stamps;
//   * the party's Assign sends it (cmd.land_send), and its row shows the trip's bar;
//   * her sheet's Stop takes the job away (cmd.clear_fleet_job);
//   * every row keeps its height whatever its state, and its place; nothing scrolls sideways; every press is 44 px;
//   * no row prints a per-hour figure (they arrive with 0495's world.workers()).
//
// THE WORLD: the shipped image with the switches production runs lit, the served board, the standing jobs and the Land lit.
// THE JOBS TICK: on a server pg_cron calls public.tick_fleet_jobs every 2 minutes; a tab has no cron. So this world runs the same
// procedure (one pass, in the caller's transaction, as the migration's own self-assert does) right after a job is set.

const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const
const OUT = 'test-results/hq-corp'

const LIT = [
  'raid_companies_enabled',
  'yard_order_enabled',
  'hold_requests_enabled',
  'houses_board_enabled',
  'level_unlocks_enabled',
  'world_events_enabled',
  'pirate_bounties_enabled',
  'first_hour_enabled',
  'regard_enabled',
  'levels_bite',
  'land_enabled',
  'hq_board_enabled',
  'fleet_jobs_enabled',
]

const corpWorld = () =>
  patchedWorldImage('hq-corp', async (pg) => {
    await pg.exec(`update public.world_config set value = 'true'::jsonb where key in (${LIT.map((k) => `'${k}'`).join(', ')})`)
    await pg.exec(`update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite'`)
    await pg.exec(`
      create function public.spec_tick_fleet_jobs() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
      begin
        if pg_trigger_depth() = 1 then call public.tick_fleet_jobs(false); end if;
        return null;
      end $f$;
      create trigger spec_tick_fleet_jobs after insert or update of since on public.fleet_jobs
        for each statement execute function public.spec_tick_fleet_jobs();`)
  })

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
        await serveWorldImage(page, await corpWorld())
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
        await expect(sheet.getByTestId('corp-assign-good').first()).toBeVisible({ timeout: 120_000 })
        // the first good, in the market's order, that a priced harbour buys and the server takes as her fixed run
        const goods = await sheet.getByTestId('corp-assign-good').count()
        let assigned = false
        for (let g = 0; g < goods && !assigned; g++) {
          await sheet.getByTestId('corp-assign-good').nth(g).click()
          await expect(sheet.getByTestId('corp-assign-sales').or(sheet.getByTestId('corp-assign-nosale'))).toBeVisible({ timeout: 120_000 })
          const sales = await sheet.getByTestId('corp-assign-sale').count()
          for (let s = 0; s < sales && !assigned; s++) {
            await sheet.getByTestId('corp-assign-sale').nth(s).click()
            const quote = sheet.getByTestId('corp-assign-quote')
            await expect(quote, 'no quote before the press').toBeVisible()
            await expect(quote.getByTestId('corp-assign-profit')).toHaveText(/[+−-]?[\d,]+/)
            await expect(quote.getByTestId('corp-assign-time')).not.toHaveText('')
            await expect(go).toBeEnabled()
            expect(await sideways(page), 'Assign scrolls sideways').toBe(false)
            expect(await smallPresses(page, '[data-testid="hq-sheet-assign"]'), 'Assign presses under 44 px').toEqual([])
            if (!assigned && s === 0 && g === 0) await page.screenshot({ path: `${OUT}/assign-sea-${size.width}.png` })
            await go.click()
            // committed: the sheet closes; refused (no course the world remembers): the server's words stand, and the next is tried
            await expect
              .poll(async () => (await sheet.count()) === 0 || (await sheet.getByTestId('corp-assign-refusal').count()) > 0, { timeout: 120_000 })
              .toBe(true)
            assigned = (await sheet.count()) === 0
          }
        }
        expect(assigned, 'no good at her harbour could be assigned as a fixed run').toBe(true)
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
        await expect(hers.locator('[data-figure="runs"]')).toBeVisible()
        await expect(page.getByTestId('corp-worker-list')).not.toContainText('/ h')

        // ASSIGN, LAND: the party's sheet; a job of the home land; its served terms; one press
        await party.click()
        await expect(sheet).toBeVisible({ timeout: 60_000 })
        const iron = sheet.locator('[data-testid="corp-assign-job"][data-job="iron"]')
        await expect(iron).toBeVisible({ timeout: 120_000 })
        await iron.click()
        await expect(sheet.getByTestId('corp-assign-terms')).toHaveAttribute('data-job', 'iron')
        await expect(sheet.getByTestId('corp-assign-trip')).not.toHaveText('')
        expect(await sideways(page), 'the Land Assign scrolls sideways').toBe(false)
        await page.screenshot({ path: `${OUT}/assign-land-${size.width}.png` })
        await go.click()
        await expect(sheet).toHaveCount(0, { timeout: 120_000 })
        await expect(party).toHaveAttribute('data-state', 'working', { timeout: 120_000 })
        await expect(party.getByTestId('corp-worker-action')).toContainText('Iron')
        await expect(party.getByTestId('corp-worker-bar')).toHaveAttribute('data-on', 'true')
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

        // THE LEDGER: the served rate when the board serves one (never one made here), and its press is the Report, in place
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
        expect(await smallPresses(page, '[data-testid="hq-sheet-worker"]'), 'sheet presses under 44 px').toEqual([])
        await page.screenshot({ path: `${OUT}/worker-sheet-${size.width}.png` })
        await own.getByTestId('corp-sheet-stop').click()
        await expect(own).toHaveCount(0, { timeout: 120_000 })
        await expect(hers).not.toHaveAttribute('data-action', 'fixed', { timeout: 120_000 })
        expect(page.url(), 'her sheet left HQ').toBe(url)
        expect((await rowsOf(page)).map((r) => r.height), 'a row changed its height after Stop').toEqual(before.map((r) => r.height))
      })
    })
