import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { reachable, ready } from './appReady.fixture'

// SHIP → CABINS (0157, docs/SKILLS_AND_CAPTAINS.md K5): world.ship_view serves `seats` (world.ship_seats)
// and the ship panel prints them as served — seat 1 the Captain's cabin, the rest typed by the hull's
// role (data/captains.json `cabins.rotation`), each empty until a captain is seated, and the server's
// sentence while cabin rates are not in use. Your own docked ship offers Seat; with no captain kept the
// picker says to hire one first (cmdSeatCaptain is the verb behind it). Preconditions from the data
// files, never a literal count: the fresh company sails the starting hull of data/ship_stats.json.

const read = (rel: string) => JSON.parse(readFileSync(path.join(process.cwd(), rel), 'utf8'))
const stats = read('data/ship_stats.json') as { slots: { class: string; cabins: number }[] }
const cat = read('data/captains.json') as { cabins: { kinds: { code: string; word: string }[] } }
const captainsCabin = cat.cabins.kinds.find((k) => k.code === 'captain')!.word

// WIDE, on purpose: on a 390px phone the ship panel opens BEHIND the fleet tray (found 2026-10-18 by this
// spec; it predates 0157 and is reported, not fixed here). At the owner's width it stands beside it.
test.use({ viewport: { width: 1440, height: 900 } })

test('your docked ship shows her cabins, seat 1 the Captain\'s cabin, and offers Seat', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.goto('map')
  await ready(page)
  // the fleets corner is a pill at rest; pressed, it lists your fleets (map.sendfleet.spec's way in)
  await page.getByTestId('map-fleets-corner').locator('button[aria-expanded]').click()
  await page.getByTestId('map-fleet-row').first().click()
  await page.getByTestId('tray-ship').first().click()
  const cabins = page.getByTestId('ship-cabins')
  await expect(cabins).toBeVisible({ timeout: 60_000 })
  const counts = new Set(stats.slots.map((s) => s.cabins))
  const drawn = await cabins.locator('li').count()
  expect(drawn, 'no cabins drawn').toBeGreaterThan(0)
  expect(counts.has(drawn), `${drawn} cabins drawn; the data's hulls have ${[...counts].join(' / ')}`).toBe(true)
  await expect(cabins.getByTestId('cabin-1')).toContainText(captainsCabin)
  await expect(cabins.getByTestId('cabin-1')).toContainText('Empty')
  await expect(cabins).toContainText('Cabin rates are not in use yet.')
  await cabins.getByTestId('cabin-seat-1').click()
  await expect(cabins.getByTestId('cabin-pick-1')).toContainText('Hire a captain at an inn first.')
})
