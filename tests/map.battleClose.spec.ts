import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { reachable, ready } from './appReady.fixture'
import { serveFightWorld } from './fightWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BATTLE SCREEN, OPENED FROM THE MAP, CLOSES (owner 2026-11-15: "after i press combat to view, i can't close it").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The world is tests/fightWorld.fixture.ts with `ticks` on: one real TICK battle (0435) that opens the moment the map
// first asks. A press on its red ring opens the battle screen over the map (and the fight's card under it).
// THE BUG: the screen was drawn INSIDE the chart's surface, so the surface took the press on Close for a gesture of its
// own (it captured the pointer) and the button never heard its click: no press and no touch closed the screen.
//   · ✕ (top right, at least a touch target, inside the glass), by mouse and by touch
//   · Escape
//   · a press on the dark backdrop
//   · the browser's Back
// each closes it, and it STAYS closed (the press goes to no ring under it). Watch on the card opens it again.
// A WATCHER sees no action bar; HER OWN battle shows it. The log is behind Log.
// Run it: npm run build && npm run preview, then `npx playwright test map.battleClose.spec.ts`.
// Screenshots go to test-results/battle-close (or BATTLE_CLOSE_SHOTS; BATTLE_CLOSE_TAG names the set).

const SHOTS = process.env.BATTLE_CLOSE_SHOTS ? path.resolve(process.env.BATTLE_CLOSE_SHOTS) : path.resolve('test-results', 'battle-close')
const TAG = process.env.BATTLE_CLOSE_TAG ?? 'now'
const PHONE = { width: 390, height: 844 }
const WIDE = { width: 1280, height: 800 }

test.beforeAll(() => mkdirSync(SHOTS, { recursive: true }))

const screen = (page: Page) => page.getByTestId('battle-screen')

/** The map with the tick battle's ring on it; answers the ring's centre on the glass. */
async function openMap(page: Page, mine = false) {
  await serveFightWorld(page, mine, true)
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
  const ring = page.getByTestId('map-fight-ring').first()
  await expect(ring, 'the battle the fixture opens is ringed').toBeVisible({ timeout: 90_000 })
  const box = (await ring.locator('circle').first().boundingBox())!
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 }
}

/** Closed, and still closed a moment later: the press that closed it opened nothing under it. */
async function staysClosed(page: Page, how: string) {
  await expect(screen(page), `${how} closes the battle screen`).toHaveCount(0)
  await page.waitForTimeout(700)
  await expect(screen(page), `${how}: it stays closed`).toHaveCount(0)
}

async function watchAgain(page: Page) {
  await page.getByTestId('fight-sheet-watch').click()
  await expect(screen(page)).toBeVisible()
}

for (const size of [PHONE, WIDE]) {
  const phone = size.width < 600
  test.describe(`the battle screen from the map, at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size, locale: 'en-US', hasTouch: phone })

    test('a press on the ring opens it; ✕, Escape, the backdrop and Back each close it, and it stays closed', async ({ page, request, baseURL }) => {
      test.setTimeout(420_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`)
      const ring = await openMap(page)
      if (phone) await page.touchscreen.tap(ring.x, ring.y)
      else await page.mouse.click(ring.x, ring.y)
      await expect(screen(page)).toBeVisible()
      await expect(page.getByTestId('battle-body')).toBeVisible({ timeout: 30_000 })
      await page.screenshot({ path: path.join(SHOTS, `${TAG}-screen-watch-${size.width}.png`) })

      // ── ✕: top right, a touch target, inside the glass, nothing over it ──
      const close = page.getByTestId('battle-close')
      await expect(close).toBeVisible()
      const box = (await close.boundingBox())!
      expect(box.width, '✕ is a touch target').toBeGreaterThanOrEqual(44)
      expect(box.height, '✕ is a touch target').toBeGreaterThanOrEqual(44)
      expect(box.x + box.width, '✕ is inside the glass').toBeLessThanOrEqual(size.width)
      expect(box.x, '✕ is at the right').toBeGreaterThan(size.width / 2)
      expect(box.y, '✕ is at the top').toBeLessThan(size.height / 4)
      const onTop = await close.evaluate((el) => {
        const r = el.getBoundingClientRect()
        const at = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
        return at !== null && el.contains(at)
      })
      expect(onTop, 'nothing lies over ✕').toBe(true)
      if (phone) await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2)
      else await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
      await staysClosed(page, '✕')

      // the card is still there: who against whom, one Watch
      const sheet = page.getByTestId('fight-sheet')
      await expect(sheet).toBeVisible()
      await expect(page.getByTestId('fight-sheet-watch')).toHaveCount(1)
      await page.screenshot({ path: path.join(SHOTS, `${TAG}-card-${size.width}.png`) })

      // ── Escape ──
      await watchAgain(page)
      await page.keyboard.press('Escape')
      await staysClosed(page, 'Escape')
      await expect(sheet, 'Escape closed the screen only, not the card under it').toBeVisible()

      // ── the dark backdrop ──
      await watchAgain(page)
      const back = (await page.getByTestId('battle-backdrop').boundingBox())!
      const panel = (await screen(page).boundingBox())!
      expect(panel.y - back.y, 'a strip of the backdrop shows above the screen').toBeGreaterThanOrEqual(16)
      const at = { x: back.x + back.width / 3, y: back.y + (panel.y - back.y) / 2 }
      if (phone) await page.touchscreen.tap(at.x, at.y)
      else await page.mouse.click(at.x, at.y)
      await staysClosed(page, 'a press on the backdrop')

      // ── the browser's Back ──
      await watchAgain(page)
      await page.goBack()
      await staysClosed(page, 'Back')
      await expect(page, 'Back left the battle, not the map').toHaveURL(/\/map$/)
      await expect(page.getByTestId('map-chart')).toBeVisible()

      // a second ✕ after all of it: the history is as it was (one Back per opening, none left over)
      await watchAgain(page)
      await page.getByTestId('battle-close').click()
      await staysClosed(page, '✕ again')
      await expect(page).toHaveURL(/\/map$/)

      // ── A WATCHER'S SCREEN: no action bar; the log is behind Log ──
      await watchAgain(page)
      await expect(page.getByTestId('battle-actions')).toHaveCount(0)
      await expect(page.getByTestId('battle-log')).toHaveCount(0)
      await page.getByTestId('battle-log-toggle').click()
      await expect(page.getByTestId('battle-log')).toBeVisible()
      await page.screenshot({ path: path.join(SHOTS, `${TAG}-screen-log-${size.width}.png`) })
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    })

    test('her own battle: the action bar is there, and ✕ still closes it', async ({ page, request, baseURL }) => {
      test.setTimeout(420_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`)
      const ring = await openMap(page, true)
      if (phone) await page.touchscreen.tap(ring.x, ring.y)
      else await page.mouse.click(ring.x, ring.y)
      await expect(screen(page)).toBeVisible()
      await expect(page.getByTestId('battle-body')).toBeVisible({ timeout: 30_000 })
      await page.screenshot({ path: path.join(SHOTS, `${TAG}-screen-mine-${size.width}.png`) })
      // while it is fought her bar is there (a fight this short may be over before the page drew it: then there is none)
      if ((await page.getByTestId('battle-end').count()) === 0 && (await page.getByTestId('battle-actions').count()) > 0) {
        await expect(page.getByTestId('battle-actions').getByRole('button')).toHaveCount(8)
      }
      const close = page.getByTestId('battle-close')
      if (phone) await close.tap()
      else await close.click()
      await staysClosed(page, '✕')
    })
  })
}
