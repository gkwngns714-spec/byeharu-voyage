// ═══════════════════════════════════════════════════════════════════════════════════════════════
// "NO FLEETS YET" IS AN ANSWER, NEVER A WAIT — the live site, 2026-10-08, made to fail
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A signed-in captain who owns Gaivota opened COMMAND on a cold load and was told "No fleets yet.
// Start your company to get your first one." A reload showed "Loading…" and then the fleet. The
// empty note was rendered from a world that had not read its fleets yet: `open()` published the
// snapshot in one `set()` and only then awaited the first `refresh()`, so for the whole of that
// read the store said "snapshot here, fleets: []" — and COMMAND, which gates on the snapshot, took
// the empty list for an answer (src/live/worldStore.ts, `open`).
//
// The store now publishes the snapshot in the SAME `set()` as `phase: 'ready'`, after the first
// fleets read has landed, so there is no state in which a screen can see the world without its
// fleets. This spec watches a cold load of each tab that prints an empty-fleets sentence, with a
// MutationObserver installed before the first script runs: it records every moment the sentence is
// in the document. The record must be empty, and the tab must end on the fleet it really has.
//
// It WATCHES, it does not sample: the window is one read long (milliseconds against PGlite), so a
// poll would miss it (tests/flicker.spec.ts learned that first).
//
// The build under test must be served: `npm run build && npx vite preview --port <n>`, then
// PLAYWRIGHT_BASE_URL=http://localhost:<n>/byeharu-voyage/ (localhost, not 127.0.0.1).

import { test, expect } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'

declare global {
  interface Window {
    __emptyWatch?: { seen: { at: number; text: string }[]; loadingSeen: boolean }
  }
}

test.use({ viewport: PHONE })

const EMPTY = /No fleets yet/

for (const tab of [
  { path: 'command', sheet: 'command', fleet: (p: import('@playwright/test').Page) => p.getByTestId('command').getByRole('button').first() },
  { path: 'fleets', sheet: 'fleets', fleet: (p: import('@playwright/test').Page) => p.getByTestId('fleet-row').first() },
]) {
  test(`${tab.path.toUpperCase()} on a cold load never says "No fleets yet" while the first fleets read is in flight`, async ({
    page,
    request,
    baseURL,
  }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)

    await page.addInitScript((src: string) => {
      const empty = new RegExp(src)
      const t0 = performance.now()
      const watch = { seen: [] as { at: number; text: string }[], loadingSeen: false }
      window.__emptyWatch = watch
      const look = () => {
        const text = document.body?.textContent ?? ''
        if (empty.test(text)) {
          const m = text.match(new RegExp(`.{0,40}${src}.{0,40}`))
          watch.seen.push({ at: Math.round(performance.now() - t0), text: m ? m[0] : src })
        }
        if (/Loading…|Opening the world/.test(text)) watch.loadingSeen = true
      }
      new MutationObserver(look).observe(document, { subtree: true, childList: true, characterData: true })
    }, EMPTY.source)

    await page.goto(tab.path)
    await ready(page)
    // The tab ends on the fleet this captain really has — the local world founds one at boot.
    await expect(page.getByTestId(tab.sheet)).toBeVisible({ timeout: 60_000 })
    await expect(tab.fleet(page)).toBeVisible({ timeout: 60_000 })

    const watch = await page.evaluate(() => window.__emptyWatch)
    // Non-vacuity: the observer was live through the boot, and saw it.
    expect(watch?.loadingSeen, 'the observer never saw the world opening — it was not watching').toBe(true)
    expect(watch?.seen, 'the empty-fleets sentence was in the document while the fleets were still being read').toEqual([])
  })
}
