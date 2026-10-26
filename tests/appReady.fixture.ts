import { expect, test } from '@playwright/test'

// THE ONE "IS THE APP UP" APPARATUS for every browser spec in this repo.
//
// It lived inside `layout.spec.ts` until 2026-08-25, when a second browser spec (`nav.geometry`)
// needed the same three things: the phone viewport the whole project measures at, the "is anything
// even served" probe, and the wait that knows the difference between a downloaded bundle and a
// booted world. Copying those into a second file would have made TWO measuring apparatuses that
// can drift — the exact shape `docs/NO_SPAGHETTI.md` forbids — and drift here is not cosmetic: the
// `ready()` below encodes hard-won knowledge (networkidle is NOT ready; the boot budget is
// MEASURED; a cloud build must SKIP rather than fail). A second copy would have gone stale silently.
//
// Everything below is moved verbatim from layout.spec.ts, comments included, so the reasoning
// travels with the code rather than being left behind at the old address.

/** iPhone 14 Pro logical viewport — the narrow case the brief names, and the viewport every
 *  screenshot check and every geometry proof in this repo uses. */
export const PHONE = { width: 390, height: 844 }

export async function reachable(
  request: { get: (url: string) => Promise<{ ok(): boolean }> },
  base: string,
) {
  try {
    const res = await request.get(base)
    return res.ok()
  } catch {
    return false
  }
}

/**
 * `networkidle` IS NOT "THE APP IS UP" HERE, and treating it as one is what made the fold test red.
 *
 * The chain applies inside the browser (PGlite), which takes seconds — 15 on this machine before
 * D11b, ~8 after. `networkidle` fires as soon as the bundle has finished downloading, long before
 * `world.snapshot()` has answered, so every measurement below was taken against the skeleton:
 * "only 0 complete price rows above the fold" was the loading placeholder, measured honestly.
 *
 * READY IS THE STORE SAYING SO, and then nothing pulsing. Waiting for a table row was the obvious
 * idea and it was wrong: COMMAND has no table at all, so the wait timed out on a screen that had
 * been up for a minute. So this waited for the ABSENCE of the two things loading looked like — a
 * `Skeleton` (`animate-pulse`) and "Opening the world" — and absence is true of an EMPTY page too.
 * It returned ~50 ms after `domcontentloaded`, before React had drawn anything, and on COMMAND
 * (whose "not yet" is its own "Loading…" row) and the map ("opening the chart…") it never saw the
 * boot at all. Every spec then raced PGlite on its next step: CI runs 39097978019, 39107062920 and
 * 39107806852 counted 0 ledger rows on COMMAND · City with `[db] ready` still 4 s away (the traces'
 * console), and #209's `chartOpen` patched the same race for the map route alone.
 *
 * The positive signal is the shell's `data-world` (src/app/AppShell.tsx): the world store's own
 * load phase, the one authority every screen gates on, so it is right for every route at once.
 * The absence check stays after it, for a screen that is still drawing its first read's skeleton.
 */
/** THE WORLD-BOOT BUDGET (see the measurement in `ready()`), named once so a wait that is the same
 *  boot — or a first read behind it — carries the same number rather than a second guess. */
export const WORLD_BOOT_MS = 300_000

/**
 * A PANEL HAS SETTLED: no `Skeleton` left inside `scope`. `Skeleton` is the design system's ONE
 * loading placeholder, so this is the panel's own "my read has landed" — the same signal `ready()`
 * reads for the whole page, scoped to the panel a spec has just opened. It replaces the fixed
 * 1200 ms sleeps that followed opening COMMAND · City: under CI load the quay's market read took
 * longer than that, and the specs counted 0 ledger rows beside a Skeleton (run 39107806852's
 * screencast). A sleep is a guess about a machine; this is the panel saying it is done.
 */
export async function settled(scope: import('@playwright/test').Locator): Promise<void> {
  await expect(scope.locator('.animate-pulse'), 'the panel is still drawing its first read').toHaveCount(0, { timeout: WORLD_BOOT_MS })
}

/**
 * THE DRIFT SLOT, IN WALL-CLOCK MS — `drift_slot_seconds` is 900 (0240's header: "900 → 600 → 900"; 16
 * readers), and a slot is `floor(epoch / 900)`, so every tab on every machine crosses an edge at the same
 * instants: :00, :15, :30, :45.
 *
 * WHY A SPEC MUST NOT SPAN ONE WITH A TRAY OPEN. A tab keeps the price record on its own (there is no
 * pg_cron in it): src/lib/rpc/localBackend.ts plays the snapshot job at boot (`warmRecord`) and again, in
 * front of the next record read (`world.price_series`, `world.watchlist`), when that read finds the
 * PRESENT slot empty — i.e. the first one after an edge. The job costs tens of seconds in a tab (the boot
 * that carries it is the 33 s `ready()` of the failing runs) and PGlite answers one call at a time, so
 * everything asked behind it waits: the buy tray's `world.buy_capacity` sat unanswered on "Checking max…"
 * while the shell's own 3-s reads stopped too. Two reds of trade.ceiling.spec.ts:267 fit to the second —
 * the tray was pressed 2 s after the 10:15:00 UTC edge (main 68b7817, run 40302467679: the tab booted
 * 10:14:29, the press was 10:15:02, no RPC logged for 26 s), and the sell test started 08:59:50 (PR #344,
 * run 40294400288), whose press falls on the 09:00:00 edge.
 */
export const DRIFT_SLOT_MS = 900_000

/**
 * STEP ACROSS A SLOT EDGE BEFORE THE SPEC TOUCHES THE TRAY. If the next edge is closer than `quietMs`,
 * wait for the edge (a stated instant, not a guess about a machine), then boot the tab again: the boot's
 * own `warmRecord` writes the new slot's record, and `ready()` does not return until the world's reads
 * — queued behind it — have answered. What follows has a whole slot of quiet ahead of it.
 */
async function pastSlotEdge(page: import('@playwright/test').Page, quietMs: number) {
  const left = DRIFT_SLOT_MS - (Date.now() % DRIFT_SLOT_MS)
  if (left > quietMs) return
  // +1 s: every clock in the room has agreed the edge has gone by.
  await page.waitForFunction((edge) => Date.now() >= edge, Date.now() + left + 1_000, { polling: 250, timeout: quietMs + 30_000 })
  await page.reload()
  await ready(page)
}

/**
 * @param quietMs  A spec that opens a tray and waits on its reads asks for the slot to hold still for
 *                 that long (see DRIFT_SLOT_MS). Absent: no promise, no wait — most specs never read the
 *                 price record after boot.
 */
export async function ready(page: import('@playwright/test').Page, { quietMs }: { quietMs?: number } = {}) {
  await page.waitForLoadState('domcontentloaded')
  // BUDGET, MEASURED (2026-08-23, D21): the 243-good world cold-boots in 78.8 s in an idle
  // chromium — the chain's 52,002-row price seed is most of it — and this suite runs several
  // workers, each booting its own tab, so contention multiplies that. 90 s was sized for the
  // ~8-15 s chain this comment block used to describe and it now fails a CORRECT build. 300 s
  // covers the measured boot times a loaded machine; the real cure is the pre-built database
  // image DEV_LOG D21 names, at which point this number can shrink back.
  //
  // A cloud build redirects to /auth and never mounts the shell; that page is "up" too, and the
  // skip below names it. A world that FAILED to open is up as well — and is a failure, said with
  // the sentence the screen printed rather than left to time out 300 s later.
  const phase = await page.waitForFunction(
    () => {
      if (/\/auth$/.test(location.pathname)) return 'auth'
      const world = document.querySelector('[data-world]')?.getAttribute('data-world')
      if (world === 'failed') return 'failed'
      if (world !== 'ready') return false
      const pulsing = document.querySelectorAll('.animate-pulse').length
      const opening = /Opening the world/i.test(document.body.innerText)
      return pulsing === 0 && !opening ? 'ready' : false
    },
    undefined,
    { timeout: WORLD_BOOT_MS },
  )
  if ((await phase.jsonValue()) === 'failed') {
    throw new Error(`the world failed to open: ${(await page.evaluate(() => document.body.innerText)).slice(0, 400)}`)
  }
  // One frame, so nothing measures a box that is still being laid out.
  await page.waitForTimeout(250)

  // THESE SPECS MEASURE THE GAME, AND A CLOUD BUILD SHOWS A SIGN-IN FORM INSTEAD.
  // With `.env.local` present the app runs against the Supabase project and every route redirects
  // to /auth until a captain signs in — on which there is no table to measure, no nav bar to
  // measure, and no world to wait for. That is not a layout failure, so it must not be reported as
  // one: the build under test is simply the wrong one. Build without `.env.local` to measure
  // local play.
  if (/\/auth$/.test(new URL(page.url()).pathname)) {
    test.skip(
      true,
      'this build is in CLOUD mode and redirected to /auth — the layout proof measures local play. ' +
        'Move .env.local aside, `npm run build && npm run preview`, and re-run.',
    )
  }
  if (quietMs) await pastSlotEdge(page, quietMs)
}

/**
 * THE FRAME COST OF A ZOOM STEP, in ms — row 90's apparatus, run INSIDE the page: twelve wheel
 * steps (six in, six out) dispatched on the chart element, two animation frames awaited after
 * each, `performance.now()` around the lot. Nothing in the timed loop crosses to Playwright, so
 * the figure is the chart's, not the driver's round trips (which cost ~150 ms a step on a loaded
 * machine and swamped the first measurement on 2026-09-14).
 */
export async function zoomStepMs(page: import('@playwright/test').Page): Promise<number> {
  return page.evaluate(async () => {
    const chart = document.querySelector('[data-testid="map-chart"]') as HTMLElement
    // THE VIEW SHEET (src/chart/ChartCanvas.tsx): the one svg whose viewBox is the view.
    const svg = chart.querySelector('[data-testid="map-view"]') as SVGSVGElement
    const rect = chart.getBoundingClientRect()
    const frame = () => new Promise<void>((r) => requestAnimationFrame(() => requestAnimationFrame(() => r())))
    const step = async (deltaY: number) => {
      const before = svg.getAttribute('viewBox')
      svg.dispatchEvent(
        new WheelEvent('wheel', { deltaY, clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2, bubbles: true, cancelable: true }),
      )
      await frame()
      if (svg.getAttribute('viewBox') === before) throw new Error('the wheel did not zoom the chart')
    }
    const t0 = performance.now()
    for (let i = 0; i < 12; i++) await step(i < 6 ? -120 : 120)
    return (performance.now() - t0) / 12
  })
}
