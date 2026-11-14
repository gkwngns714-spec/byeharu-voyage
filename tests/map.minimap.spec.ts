import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { MINIMAP_ASPECT, MINIMAP_MIN_WIDTH, MINIMAP_PREFS_KEY, minimapMaxWidth, minimapWidth, readMinimapPrefs } from '../src/chart/minimapPrefs'

// THE MINIMAP'S SIZE AND FOLD ARE THE PLAYER'S (owner, 2026-11-14: "enable me to change the size of the minimap,
// and fold"): the grip resizes it in its one shape, a drag on the grip never moves the chart, the fold button
// leaves a tab, and a reload finds both where they were left.

/** Set MINIMAP_SHOTS to a folder to keep pictures of each state. */
const SHOTS = process.env.MINIMAP_SHOTS

test('the kept record: only its own shape is trusted, and the width is held to the glass', () => {
  expect(readMinimapPrefs(() => null)).toEqual({ width: null, folded: null })
  expect(readMinimapPrefs(() => 'yes')).toEqual({ width: null, folded: null })
  expect(readMinimapPrefs(() => '{"width":-4,"folded":"no"}')).toEqual({ width: null, folded: null })
  expect(readMinimapPrefs(() => '{"width":200,"folded":true}')).toEqual({ width: 200, folded: true })
  expect(
    readMinimapPrefs(() => {
      throw new Error('a private window')
    }),
  ).toEqual({ width: null, folded: null })
  // a desktop glass: 40% of its width, never taller than a third of it
  expect(minimapMaxWidth(1280, 700)).toBe(512)
  expect(minimapMaxWidth(1280, 300)).toBe(Math.floor(100 * MINIMAP_ASPECT))
  // a phone's glass still has room to grow, and never past its own width
  expect(minimapMaxWidth(390, 700)).toBe(280)
  expect(minimapMaxWidth(320, 500)).toBe(280)
  expect(minimapWidth({ width: 9999, folded: null }, 390, 700)).toBe(280)
  expect(minimapWidth({ width: 10, folded: null }, 390, 700)).toBe(MINIMAP_MIN_WIDTH)
  expect(minimapWidth({ width: null, folded: null }, 390, 700)).toBe(MINIMAP_MIN_WIDTH)
})

type Box = { x: number; y: number; w: number; h: number }
const hits = (a: Box, b: Box) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

const rectOf = (page: Page, id: string) =>
  page.getByTestId(id).evaluate((e) => {
    const r = e.getBoundingClientRect()
    return { x: r.x, y: r.y, w: r.width, h: r.height }
  })

const viewOf = (page: Page) => page.getByTestId('map-view').evaluate((e) => e.getAttribute('viewBox'))

/** The view's box, once it has stopped gliding. */
async function restingView(page: Page) {
  let prev = await viewOf(page)
  await expect
    .poll(async () => {
      await page.waitForTimeout(200)
      const now = await viewOf(page)
      const still = now === prev
      prev = now
      return still
    })
    .toBe(true)
  return prev
}

async function openMap(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g')
}

/** Drag the grip by (dx, dy), as a mouse does. */
async function dragGrip(page: Page, dx: number, dy: number) {
  const g = await rectOf(page, 'map-minimap-grip')
  const from = { x: g.x + g.w - 8, y: g.y + 8 }
  await page.mouse.move(from.x, from.y)
  await page.mouse.down()
  for (let i = 1; i <= 8; i++) await page.mouse.move(from.x + (dx * i) / 8, from.y + (dy * i) / 8)
  await page.mouse.up()
}

for (const glass of [
  { tag: 'desktop', width: 1280, height: 800 },
  { tag: '390', width: 390, height: 844 },
  { tag: '320', width: 320, height: 640 },
]) {
  test.describe(`the minimap at ${glass.tag}`, () => {
    test.use({ viewport: { width: glass.width, height: glass.height } })

    test('resize, fold, and a reload keeps both; a drag on the grip does not move the chart', async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      const shot = async (name: string) => {
        if (SHOTS) await page.screenshot({ path: `${SHOTS}/${glass.tag}-${name}.png` })
      }
      await openMap(page)
      const chart = await rectOf(page, 'map-chart')
      const max = minimapMaxWidth(chart.w, chart.h)

      // the old rule stands until the player chooses: it is up once the opening frame is left, at the old size
      const out = page.getByTestId('map-view-controls').locator('button').nth(1)
      await out.click()
      await out.click()
      await expect(page.getByTestId('map-minimap')).toBeVisible()
      const small = await rectOf(page, 'map-minimap')
      expect(Math.round(small.w)).toBe(MINIMAP_MIN_WIDTH)
      expect(Math.round(small.h)).toBe(52)
      for (const id of ['map-minimap-grip', 'map-minimap-fold']) {
        const r = await rectOf(page, id)
        expect(Math.min(r.w, r.h), `${id} is a small target`).toBeGreaterThanOrEqual(32)
      }
      await shot('small')

      // a drag on the grip: larger, in its one shape, its bottom-left corner where it was, and the chart did not move
      const before = await restingView(page)
      await dragGrip(page, 60, -10)
      const mid = await rectOf(page, 'map-minimap')
      expect(Math.round(mid.w)).toBe(Math.min(max, MINIMAP_MIN_WIDTH + 60))
      expect(mid.w / mid.h).toBeGreaterThan(MINIMAP_ASPECT - 0.1)
      expect(mid.w / mid.h).toBeLessThan(MINIMAP_ASPECT + 0.1)
      expect(Math.round(mid.x)).toBe(Math.round(small.x))
      expect(Math.round(mid.y + mid.h)).toBe(Math.round(small.y + small.h))
      expect(await restingView(page), 'a drag on the grip moved the chart').toBe(before)

      // as far as it goes: the glass's maximum, and it covers no other chrome
      await dragGrip(page, 2000, -2000)
      const large = await rectOf(page, 'map-minimap')
      expect(Math.round(large.w)).toBe(max)
      expect(large.h).toBeLessThanOrEqual(chart.h / 3 + 1)
      expect(large.x + large.w).toBeLessThanOrEqual(chart.x + chart.w)
      expect(await restingView(page), 'a drag on the grip moved the chart').toBe(before)
      await page.getByTestId('map-fleets-corner').locator('button[aria-expanded]').click()
      for (const id of ['map-fleets-corner', 'map-view-controls']) {
        expect(hits(large, await rectOf(page, id)), `the largest minimap covers ${id}`).toBe(false)
      }
      await shot('large')
      await page.getByTestId('map-fleets-corner').locator('button[aria-expanded]').click()

      // it is still the instrument: a press on it moves the chart
      await page.mouse.click(large.x + large.w * 0.25, large.y + large.h * 0.6)
      await expect.poll(() => viewOf(page)).not.toBe(before)
      await restingView(page)

      // and back down part of the way, so the kept size is neither end
      await dragGrip(page, -40, 0)
      const kept = await rectOf(page, 'map-minimap')
      expect(Math.round(kept.w)).toBe(Math.max(MINIMAP_MIN_WIDTH, max - 40))

      // fold: a tab in the same corner, and almost no room
      await page.getByTestId('map-minimap-fold').click()
      await expect(page.getByTestId('map-minimap')).toHaveCount(0)
      const tab = await rectOf(page, 'map-minimap-tab')
      expect(tab.w).toBeGreaterThanOrEqual(32)
      expect(tab.w * tab.h).toBeLessThanOrEqual(40 * 40)
      expect(Math.round(tab.x)).toBe(Math.round(small.x))
      expect(Math.round(tab.y + tab.h)).toBe(Math.round(small.y + small.h))
      await shot('folded')

      // a reload keeps the fold, and the tab is there at the opening frame too
      await page.reload()
      await ready(page)
      await expect(page.getByTestId('map-minimap-tab')).toBeVisible()
      await expect(page.getByTestId('map-minimap')).toHaveCount(0)

      // the tab unfolds it at the size it was left; a reload keeps that too
      await page.getByTestId('map-minimap-tab').click()
      expect(Math.round((await rectOf(page, 'map-minimap')).w)).toBe(Math.round(kept.w))
      await page.reload()
      await ready(page)
      await expect(page.getByTestId('map-minimap')).toBeVisible()
      expect(Math.round((await rectOf(page, 'map-minimap')).w)).toBe(Math.round(kept.w))
      expect(await page.evaluate((k) => localStorage.getItem(k), MINIMAP_PREFS_KEY)).toBe(JSON.stringify({ width: Math.round(kept.w), folded: false }))
    })
  })
}
