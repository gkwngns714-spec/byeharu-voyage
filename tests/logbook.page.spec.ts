import { test, expect } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// THE LOGBOOK (0478, roadmap 2026-11-23 slice 9). The shipped world is DARK (`logbook_enabled` false): You draws no logbook door, and
// the page's route shows no collection. A copy of the image with the switch lit: You's door is the totals as rings, one press to the
// page; the page's rings are the served counts (her home harbour and her first hull, served as she holds them now), and each collection
// is a grid of slots, hers lit and the rest silhouettes. Nothing here works a count out: it compares the page with what it was served.

const lit = () => patchedWorldImage('logbook-lit', async (pg) => {
  await pg.exec(`update public.world_config set value = 'true'::jsonb where key = 'logbook_enabled'`)
})

test.use({ viewport: PHONE })

test('dark: You has no logbook door and the page shows no collection', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
  await page.goto('you')
  await ready(page)
  await expect(page.getByTestId('you-plate')).toBeVisible()
  await expect(page.getByTestId('you-logbook')).toHaveCount(0)
  await page.goto('logbook')
  await ready(page)
  await expect(page.getByTestId('logbook-page')).toBeVisible()
  await expect(page.getByTestId('logbook-totals')).toHaveCount(0)
})

test('lit: the door opens the page; her harbour and her hull are lit, the rest silhouettes', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
  await serveWorldImage(page, await lit())
  await page.goto('you')
  await ready(page)
  const door = page.getByTestId('you-logbook-door')
  await expect(door).toBeVisible()
  await door.click()
  await expect(page).toHaveURL(/\/logbook$/)

  const harbours = page.getByTestId('logbook-total-harbours')
  await expect(harbours).toHaveAttribute('data-of', '254')
  await expect(harbours).toHaveAttribute('data-n', '1')
  await expect(page.getByTestId('logbook-total-hulls')).toHaveAttribute('data-n', '1')
  await expect(page.getByTestId('logbook-total-seas')).toHaveAttribute('data-n', '1')

  // Harbours: one card per region, every harbour a slot, hers lit
  await expect(page.getByTestId('logbook-set').first()).toBeVisible()
  await expect(page.locator('[data-testid="logbook-slot"]')).toHaveCount(254)
  await expect(page.locator('[data-testid="logbook-slot"][data-seen="true"]')).toHaveCount(1)
  await expect(page.locator('[data-testid="logbook-sea"][data-seen="true"]')).toHaveCount(1)

  // Goods: every good a slot, none sold yet
  await page.getByRole('tab', { name: 'Goods' }).click()
  await expect(page.locator('[data-testid="logbook-slot"]')).toHaveCount(629)
  await expect(page.locator('[data-testid="logbook-slot"][data-seen="true"]')).toHaveCount(0)

  // Hulls: her one class lit
  await page.getByRole('tab', { name: 'Hulls' }).click()
  await expect(page.locator('[data-testid="logbook-slot"][data-seen="true"]')).toHaveCount(1)

  // the page fits the phone: nothing wider than the glass
  const wide = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(wide).toBeLessThanOrEqual(0)
})
