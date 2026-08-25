import { test } from '@playwright/test'

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
 * READY IS THE ABSENCE OF THE TWO THINGS LOADING LOOKS LIKE, and nothing screen-shaped. Waiting
 * for a table row was the obvious idea and it was wrong: COMMAND has no table at all, so the wait
 * timed out on a screen that had been up for a minute. Both signals below are design-system-wide —
 * `Skeleton` is the ONE loading placeholder (`animate-pulse`), and "Opening the world" is the one
 * sentence every screen prints while the chain applies.
 */
export async function ready(page: import('@playwright/test').Page) {
  await page.waitForLoadState('domcontentloaded')
  // BUDGET, MEASURED (2026-08-23, D21): the 243-good world cold-boots in 78.8 s in an idle
  // chromium — the chain's 52,002-row price seed is most of it — and this suite runs several
  // workers, each booting its own tab, so contention multiplies that. 90 s was sized for the
  // ~8-15 s chain this comment block used to describe and it now fails a CORRECT build. 300 s
  // covers the measured boot times a loaded machine; the real cure is the pre-built database
  // image DEV_LOG D21 names, at which point this number can shrink back.
  await page.waitForFunction(
    () => {
      const pulsing = document.querySelectorAll('.animate-pulse').length
      const opening = /Opening the world/i.test(document.body.innerText)
      return pulsing === 0 && !opening
    },
    undefined,
    { timeout: 300_000 },
  )
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
}
