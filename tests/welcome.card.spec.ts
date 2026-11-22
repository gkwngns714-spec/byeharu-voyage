import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// THE FIRST-RUN WELCOME (src/app/WelcomeCard.tsx; P0 of docs/design/playable-2026-11-22.md). A fresh company that has never traded
// meets one card on the Trade tab: who she is (a trading house in Lisbon, the world's year), the goal (the second ship) and the
// first press (a good's green line, then Buy & sell: it buys, sails and sells). It is an overlay (nothing under it moves, nothing scrolls sideways), and Start closes it
// for good in this browser. Every other spec starts with the mark set (playwright.config.ts); this one starts without it.

test.use({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, storageState: { cookies: [], origins: [] } })

test('a new company is welcomed once: who, the goal, the first press; Start closes it for good', async ({ page, request, baseURL }, info) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await page.goto('command')
  await ready(page)
  const card = page.getByTestId('welcome-card')
  await expect(card).toBeVisible({ timeout: 120_000 })
  await expect(card.getByTestId('welcome-who')).toHaveText(/^You run a trading house in Lisbon, 1[5-6]\d\d\.$/)
  await expect(card.getByTestId('welcome-goal')).toHaveText('Goal: earn your second ship.')
  await expect(card.getByTestId('welcome-first')).toHaveText('First: press a good’s green line, then Buy & sell.')
  // an overlay: out of the flow (fixed), and the page does not scroll sideways
  expect(await page.getByTestId('welcome-card-wrap').evaluate((el) => getComputedStyle(el).position)).toBe('fixed')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), 'the page scrolls sideways').toBe(true)
  await page.screenshot({ path: info.outputPath('welcome-390.png') })

  await card.getByTestId('welcome-start').click()
  await expect(card).toHaveCount(0)
  expect(await page.evaluate(() => localStorage.getItem('bv:welcome-seen'))).toBe('1')
  await page.reload()
  await ready(page)
  await expect(page.getByTestId('goal-card')).toBeVisible({ timeout: 120_000 })
  await expect(page.getByTestId('welcome-card')).toHaveCount(0)
})
