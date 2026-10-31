import { test, expect } from '@playwright/test'
import { PHONE, openDetail, reachable, ready } from './appReady.fixture'

// RANK → COUNTRIES (0148, docs/INFLUENCE.md I6): world.nation_standings / worldNationStandings — every
// country's cities, home and won, served by the server (public.port_nation) and printed as served.
// The precondition is the shipped world's own: since 0187 the ten great powers, each with its 4 home cities
// (data/home-ports.json, 0143) — the spec reads the count from the data file, never a literal.
import { readFileSync } from 'node:fs'
import path from 'node:path'

const homes = (JSON.parse(readFileSync(path.join(process.cwd(), 'data', 'home-ports.json'), 'utf8')) as {
  homes: Record<string, string[]>
}).homes

test('Rank → Countries lists every country with its home cities', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(PHONE)
  await page.goto('rank')
  await ready(page)
  await page.getByRole('tab', { name: 'Countries' }).click()
  // the board is a pop-up page (owner, 2026-10-31)
  await openDetail(page, 'rank-open')
  await expect(page.getByTestId('rank-country')).toHaveCount(Object.keys(homes).length, { timeout: 60_000 })
  const portugal = page.getByTestId('rank-country').filter({ hasText: 'Portugal' })
  await expect(portugal).toContainText(`${homes.PRT.length} home`)
})
