import { test, expect } from '@playwright/test'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'
import { mapLabelRequests } from '../src/chart/labels'
import { buildChartModel } from '../src/chart/chartModel'
import type { MapPort } from '../src/chart/mapTypes'
import { PHONE, reachable, ready } from './appReady.fixture'
import { openCityPanel } from './openCity.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A CITY FLIES A FLAG (0143, docs/INFLUENCE.md I1). The owner, 2026-10-17: "like uncharted
// [waters], i want to have influence of major countries" — every harbour flies the flag of the
// country that holds it today (`world.allegiance` → `public.port_nation`), a HOME city never changes
// hands, and a company chooses its country and may change it. Names this spec selects by:
// world.allegiance / worldAllegiance, cmd.change_country / cmdChangeCountry, port_allegiance.
//
//   * the city panel's title line prints the holder's flag and name and `Home city` (Lisbon);
//   * a harbour's name on the chart carries its holder's flag — since 2026-10-18 at every zoom, with
//     or without Regions (the owner: "beside the name show flag"; the pictures: tests/flags.spec.ts);
//   * Profile → Country changes the company's country once, and then says when the next change opens;
//   * no screen reads the snapshot's `nation` or the modern `country` for a flag: `portNationOf`
//     (worldStore) is the one reader.
//
// Run it: npm run build && npx vite preview --port 4210, then `npx playwright test map.flag.spec.ts`.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const ROOT = process.cwd()
const read = (rel: string) => readFileSync(path.join(ROOT, rel), 'utf8')

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((f) => {
    const p = path.join(dir, f)
    return statSync(p).isDirectory() ? walk(p) : /\.tsx?$/.test(f) ? [p] : []
  })
}

test('portNationOf is the one reader of a city\'s flag; the title line no longer prints the modern country', () => {
  const store = read('src/live/worldStore.ts')
  expect(store).toContain('export function portNationOf(')
  const readers = walk(path.join(ROOT, 'src'))
    .filter((f) => !f.endsWith(path.join('live', 'worldStore.ts')))
    .filter((f) => /\ballegiance\[/.test(readFileSync(f, 'utf8')))
  expect(readers.map((f) => path.relative(ROOT, f))).toEqual([])
  const screen = read('src/features/map/MapScreen.tsx')
  expect(screen).not.toContain('[port.country]')
  expect(screen).toContain('portNationOf(allegiance, place.port.code)')
  // a nation flag is drawn by HullCountry (the merchant's, the ship's, the picker's) or PortFlag (a
  // city's, 2026-10-18), and both draw the design system's Flag — no screen prints the old glyph
  for (const f of ['src/live/MerchantSheet.tsx', 'src/live/MerchantRow.tsx', 'src/live/ShipPanel.tsx', 'src/live/NationPicker.tsx']) {
    expect(read(f), f).toContain('<HullCountry')
  }
  for (const f of ['src/live/HullCountry.tsx', 'src/live/PortFlag.tsx']) expect(read(f), f).toContain('<Flag ')
  const glyphReaders = walk(path.join(ROOT, 'src'))
    .filter((f) => !f.endsWith(path.join('rpc', 'types.ts')))
    .filter((f) => /\.flag_char\b/.test(readFileSync(f, 'utf8')))
  expect(glyphReaders.map((f) => path.relative(ROOT, f))).toEqual([])
})

test('with flags a harbour\'s name carries its holder\'s flag; without, the label is the name alone', () => {
  const ports: MapPort[] = [
    { code: 'LIS', name: 'Lisbon', lat: 38.7, lon: -9.1, sizeTier: 3 } as MapPort,
    { code: 'OPO', name: 'Porto', lat: 41.1, lon: -8.6, sizeTier: 3 } as MapPort,
  ]
  const model = buildChartModel([], ports)
  const off = mapLabelRequests(model, ports, null, true)
  expect(off.find((r) => r.id === 'port:LIS')?.text).toBe('Lisbon')
  expect(off.find((r) => r.id === 'port:LIS')?.flag).toBeUndefined()
  // the name stays the name; the flag is a picture beside it, named by the holder's nation code
  const on = mapLabelRequests(model, ports, null, true, new Map([['LIS', 'PRT']]))
  expect(on.find((r) => r.id === 'port:LIS')?.text).toBe('Lisbon')
  expect(on.find((r) => r.id === 'port:LIS')?.flag).toBe('PRT')
  // a harbour with no flag served keeps its bare name
  expect(on.find((r) => r.id === 'port:OPO')?.text).toBe('Porto')
  expect(on.find((r) => r.id === 'port:OPO')?.flag).toBeUndefined()
})

test('the city title line prints the flag it flies: Lisbon, Portugal, Home city', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(PHONE)
  await page.goto('map')
  await ready(page)
  await openCityPanel(page, 'LIS', 'Lisbon')
  const flag = page.getByTestId('city-flag').first()
  await expect(flag).toBeVisible({ timeout: 30_000 })
  await expect(flag).toContainText('Portugal')
  await expect(flag).toContainText('Home city')
})

test('Profile changes the company\'s country once, then says when the next change opens', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(PHONE)
  await page.goto('profile')
  await ready(page)
  const section = page.getByTestId('country')
  await expect(section).toContainText('Portugal', { timeout: 60_000 })
  await page.getByTestId('country-change').click()
  await page.getByTestId('nation-ENG').click()
  await page.getByTestId('country-confirm').click()
  await expect(section).toContainText('England', { timeout: 30_000 })
  await expect(page.getByTestId('country-next')).toBeVisible()
  await expect(page.getByTestId('country-change')).toHaveCount(0)
  await expect(page.getByTestId('house-line')).toContainText('England')
})
