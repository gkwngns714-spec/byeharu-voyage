// ═══════════════════════════════════════════════════════════════════════════════════════════════
// NO CONTROL GREYS ON THE WORLD'S BEAT — the owner, 2026-09-30, made to fail
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"Bars (e.g. Start route in COMMAND) blink on their own. Find all cases and fix."* The shell reads
// the world every 3 s (src/app/AppShell.tsx), and the store's flag for that read was worn as
// `disabled` by every button in COMMAND — Start route, the route fold's Start / Clear / Pause /
// Delete, each order's ✕ and Clear all orders — so each greyed and came back on every beat.
// docs/HANDOFF_ROUTE_STOPS_AND_BLINKS.md §2 has the sweep.
//
// TWO HALVES:
//   1. STATIC — the flag is `reading` now, and only the shell (which dedupes its own beat on it)
//      and the store may read it. No screen selects the store's old `busy`, and `loadRoutes(` is
//      called only inside the store (refresh() is the one routes reader; a screen that re-asked on
//      `readAt` was a second clock that blanked the book on a failed read).
//   2. BROWSER — COMMAND with a route being set up, routes switched on (tests/routesOn.fixture.ts).
//      A MutationObserver records EVERY `disabled` flip on every button under COMMAND, and every
//      unmount of Start route, across more than three beats. The record must be empty. It watches,
//      it does not sample: PGlite answers in-tab within milliseconds, so a poll would miss the flip
//      (tests/trade.ceiling.spec.ts learned that first).
//
// The build under test must be served: `npm run build && npx vite preview --port <n>`, then
// PLAYWRIGHT_BASE_URL=http://localhost:<n>/byeharu-voyage/ (localhost, not 127.0.0.1).

import { test, expect } from '@playwright/test'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'
import { PHONE, ready, reachable } from './appReady.fixture'
import { serveRoutesOn } from './routesOn.fixture'

// ── 1. STATIC ────────────────────────────────────────────────────────────────────────────────────

const SRC = path.resolve(process.cwd(), 'src')

/** Every TS/TSX file under src, as [repo-relative path, text]. */
function sources(): [string, string][] {
  const out: [string, string][] = []
  const walk = (d: string) => {
    for (const name of readdirSync(d)) {
      const full = path.join(d, name)
      if (statSync(full).isDirectory()) walk(full)
      else if (/\.tsx?$/.test(name)) out.push([path.relative(process.cwd(), full).split(path.sep).join('/'), readFileSync(full, 'utf8')])
    }
  }
  walk(SRC)
  return out
}

function where(pattern: RegExp): string[] {
  return sources()
    .filter(([, text]) => pattern.test(text))
    .map(([file]) => file)
    .sort()
}

test('the world-read flag is read only by the shell and the store', () => {
  const readers = where(/\b(?:s|world|state|get\(\))\.reading\b/)
  expect(readers).toContain('src/app/AppShell.tsx')
  expect(readers.filter((f) => f !== 'src/app/AppShell.tsx' && f !== 'src/live/worldStore.ts')).toEqual([])
})

test('no screen selects the store’s old `busy`', () => {
  expect(where(/useWorld\(\s*\(\s*\w+\s*\)\s*=>\s*\w+\.busy\b/)).toEqual([])
  expect(where(/\bworld\.busy\b/)).toEqual([])
})

test('the routes book has one reader: the store', () => {
  expect(where(/\bloadRoutes\(/)).toEqual(['src/live/worldStore.ts'])
})

// ── 2. BROWSER ───────────────────────────────────────────────────────────────────────────────────

/** Longer than three of the shell's 3-s reads, with slack for a read itself to land. */
const WINDOW_MS = 10_500

interface Moved {
  at: number
  what: string
}

declare global {
  interface Window {
    __blinkWatch?: { log: Moved[]; stop: () => void }
  }
}

test.use({ viewport: PHONE })

test('COMMAND: no button greys and Start route never leaves across three beats', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveRoutesOn(page)

  // A route cannot start without a keep level (E_NO_KEEP) — set one on FLEETS, the way a player does.
  await page.goto('fleets')
  await ready(page)
  await page.getByTestId('fleet-row').first().click()
  const typed = page.getByLabel(/days of supplies to keep .* at, typed/)
  await typed.fill('10')
  await typed.press('Enter')
  await page.getByTestId('fleet-keep').click()
  await expect(page.getByTestId('fleet-keep')).toHaveCount(0, { timeout: 60_000 })
  await page.getByTestId('fleet-command').click()
  await expect(page.getByTestId('command')).toBeVisible()

  const routeRow = page.getByTestId('route-row')
  await expect(routeRow).toContainText('No route', { timeout: 60_000 })
  await routeRow.click()
  await page.getByTestId('route-setup').click()
  const stops = page.getByTestId('route-editor-stop')
  await expect(stops).toHaveCount(2)
  await page.getByTestId('port-field').click()
  const home = (await stops.nth(0).getByTestId('route-stop-port').innerText()).trim()
  const chips = page.getByTestId('port-chip')
  await expect(chips.first()).toBeVisible()
  const n = await chips.count()
  for (let i = 0; i < n; i++) {
    if ((await chips.nth(i).innerText()).trim() !== home) {
      await chips.nth(i).click()
      break
    }
  }
  const start = page.getByTestId('route-start')
  // Non-vacuity: the button under watch is on the page and pressable before the window opens.
  await expect(start).toBeEnabled({ timeout: 60_000 })
  const buttons = await page.getByTestId('command').locator('button').count()
  expect(buttons).toBeGreaterThan(3)

  await page.evaluate(() => {
    const root = document.querySelector('[data-testid="command"]')
    if (!root) throw new Error('no COMMAND to watch')
    const t0 = Date.now()
    const log: Moved[] = []
    const name = (el: Element) => el.getAttribute('data-testid') ?? el.getAttribute('aria-label') ?? el.textContent?.trim() ?? '?'
    const obs = new MutationObserver((records) => {
      for (const r of records) {
        if (r.type === 'attributes' && r.target instanceof HTMLButtonElement) {
          log.push({ at: Date.now() - t0, what: `${name(r.target)} disabled ${r.oldValue === null ? 'off→on' : 'on→off'}` })
        }
        if (r.type === 'childList') {
          for (const gone of Array.from(r.removedNodes)) {
            if (gone instanceof HTMLElement && (gone.dataset.testid === 'route-start' || gone.querySelector('[data-testid="route-start"]'))) {
              log.push({ at: Date.now() - t0, what: 'route-start left' })
            }
          }
        }
      }
    })
    obs.observe(root, { subtree: true, childList: true, attributes: true, attributeFilter: ['disabled'], attributeOldValue: true })
    window.__blinkWatch = { log, stop: () => obs.disconnect() }
  })
  await page.waitForTimeout(WINDOW_MS)
  const log = await page.evaluate(() => {
    window.__blinkWatch?.stop()
    return window.__blinkWatch?.log ?? []
  })
  expect(log).toEqual([])
  await expect(start).toBeEnabled()
})
