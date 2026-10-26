import { test, expect, type Page } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'
import { filterStorageKey, oneOf, readFilterChoice } from '../src/components/ui/filterState'
import { sortMerchants, filterCities, sortCities } from '../src/features/stats/statsFilters'
import type { StatsCityRow, StatsMerchantRow } from '../src/lib/rpc'

// THE STATS FILTERS (0244, owner row 228: *"also create filter for all parts in stats, for example in cities such as
// by area (continents), or by richest, etc"*). One shared FilterBar (chips + pickers + a sort), remembered per face
// (filterState.ts). Pinned: the Cities face's Europe chip leaves only European cities (the server's
// public.region_area), its Richest sort puts the bigger purse first, nothing scrolls sideways on a phone, and the
// pure halves hold (a remembered choice never trusts what it reads). It names Cities.tsx and FilterBar.tsx so CI's
// rule N selects it.

async function noSidewaysScroll(page: Page) {
  const w = await page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, client: document.documentElement.clientWidth }))
  expect(w.scroll, 'the page scrolls sideways').toBeLessThanOrEqual(w.client)
}

test('Cities: Europe leaves only European cities; Richest puts the bigger purse first', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(PHONE)
  await page.goto('stats')
  await ready(page)
  await page.getByRole('tab', { name: 'Cities', exact: true }).click()
  await expect(page.getByTestId('stats-cities')).toBeVisible({ timeout: 120_000 })
  const names = page.getByTestId('stats-city-name')
  await expect.poll(() => names.count(), { timeout: 60_000 }).toBeGreaterThan(10)
  const everyCity = await names.count()

  await page.getByTestId('filter-chip-europe').click()
  await expect(page.getByTestId('filter-chip-europe')).toHaveAttribute('aria-pressed', 'true')
  await expect.poll(() => names.count()).toBeLessThan(everyCity)
  const areas = await names.evaluateAll((els) => els.map((e) => e.getAttribute('data-area')))
  expect(areas.length).toBeGreaterThan(0)
  expect(new Set(areas)).toEqual(new Set(['europe']))
  await noSidewaysScroll(page)

  await page.getByTestId('filter-pick-sort').selectOption('richest')
  const purses = await names.evaluateAll((els) => els.map((e) => Number(e.getAttribute('data-purse'))))
  expect(purses.length).toBeGreaterThan(1)
  expect(purses[0]).toBeGreaterThanOrEqual(purses[1])

  // remembered: the face comes back on Europe
  await page.getByRole('tab', { name: 'Markets', exact: true }).click()
  await expect(page.getByTestId('stats-markets-filters')).toBeVisible({ timeout: 60_000 })
  await noSidewaysScroll(page)
  await page.getByRole('tab', { name: 'Cities', exact: true }).click()
  await expect(page.getByTestId('filter-chip-europe')).toHaveAttribute('aria-pressed', 'true', { timeout: 60_000 })
})

test('a remembered choice never trusts what it reads', () => {
  const d = { area: 'all', sort: 'richest' }
  const key = filterStorageKey('stats.cities')
  expect(key).toBe('byeharu-voyage.filter.v1:stats.cities')
  expect(readFilterChoice(() => null, 'stats.cities', d)).toEqual(d)
  expect(readFilterChoice(() => '{not json', 'stats.cities', d)).toEqual(d)
  expect(readFilterChoice(() => '[1,2]', 'stats.cities', d)).toEqual(d)
  expect(readFilterChoice(() => { throw new Error('private window') }, 'stats.cities', d)).toEqual(d)
  expect(readFilterChoice((k) => (k === key ? '{"area":"europe","sort":7,"x":"y"}' : null), 'stats.cities', d)).toEqual({ area: 'europe', sort: 'richest' })
  expect(oneOf('gone', ['all', 'europe'], 'all')).toBe('all')
  expect(oneOf('europe', ['all', 'europe'], 'all')).toBe('europe')
})

test('the sorts and filters are views: biggest first, name breaks a tie', () => {
  const city = (id: string, purse: number, area: StatsCityRow['area'], mine = false): StatsCityRow => ({ id, code: id, name: id, nation: 'PRT', purse, area, mine })
  const cities = [city('B', 5, 'europe'), city('A', 5, 'africa', true), city('C', 9, 'europe')]
  expect(sortCities(cities, 'richest', (c) => c.name).map((c) => c.id)).toEqual(['C', 'A', 'B'])
  expect(filterCities(cities, { area: 'europe', country: 'all', mine: false }).map((c) => c.id)).toEqual(['B', 'C'])
  expect(filterCities(cities, { area: 'all', country: 'all', mine: true }).map((c) => c.id)).toEqual(['A'])
  const m: StatsMerchantRow[] = [['Y', 'PRT', 10, 1, -5, 2], ['X', 'ESP', 10, 3, 7, 9]]
  expect(sortMerchants(m, 'richest').map((h) => h[0])).toEqual(['X', 'Y'])
  expect(sortMerchants(m, 'fleet').map((h) => h[0])).toEqual(['X', 'Y'])
  expect(sortMerchants(m, 'name').map((h) => h[0])).toEqual(['X', 'Y'])
})
