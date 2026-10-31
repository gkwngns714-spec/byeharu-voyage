import { test, expect } from '@playwright/test'
import { readFileSync, readdirSync } from 'node:fs'
import path from 'node:path'
import { GREAT_POWERS, NATIONS } from '../scripts/lib/world-derive.mjs'
import { PHONE, reachable, ready } from './appReady.fixture'
import { openCityPanel } from './openCity.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE GREAT POWERS (0187, docs/GREAT_POWERS.md slice GP1). The owner, 2026-10-18: "make it 7 big
// power like uncharted island, spread mainly on europe and asia, as well as islamic region" … "in
// asia add korea, in europe add more". Ten powers race for cities; the thirteen other nations are
// LOCAL RULERS of the cities they founded. Names this spec selects by: public.great_powers,
// public.great_power, public.port_ruler, public.port_countries, world.allegiance / worldAllegiance,
// world.nation_standings / worldNationStandings, cmd.found_house / cmdFoundHouse,
// cmd.change_country / cmdChangeCountry, world.snapshot.
//
//   * one list: world-derive.mjs GREAT_POWERS = the homes in data/home-ports.json = what 0187 seeds;
//     four homes each, a capital first;
//   * Start / Profile offer the ten and no ruler;
//   * a ruler's city says so: Safi → "ruled by Morocco", with the ruler's flag;
//   * the Codex lists the ten as Great powers and the thirteen as Local rulers.
// Preconditions are the data files the world guard holds the database to — never a literal count
// of the world (proofs never assert ambient defaults).
// Run it: npm run build && npx vite preview --port 4350, then
//   PLAYWRIGHT_BASE_URL=http://localhost:4350/byeharu-voyage/ npx playwright test greatPowers.spec.ts
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const ROOT = process.cwd()
const homes = (JSON.parse(readFileSync(path.join(ROOT, 'data', 'home-ports.json'), 'utf8')) as {
  homes: Record<string, string[]>
}).homes
const minors = NATIONS.filter(([c]) => !GREAT_POWERS.includes(c))
const nameOf = (code: string) => NATIONS.find(([c]) => c === code)?.[1] ?? code

test('one list of ten: GREAT_POWERS = the home cities\' powers = what 0187 seeds, four homes each', () => {
  expect(GREAT_POWERS).toHaveLength(10)
  expect(Object.keys(homes).sort()).toEqual([...GREAT_POWERS].sort())
  for (const c of GREAT_POWERS) expect(homes[c], c).toHaveLength(4)
  const all = Object.values(homes).flat()
  expect(new Set(all).size, 'no harbour is home to two powers').toBe(all.length)
  // Europe, the Islamic world and Asia (the owner's three regions) — Joseon and Japan both in
  for (const c of ['PRT', 'ESP', 'ENG', 'NLD', 'FRA', 'OTT', 'MUG', 'MNG', 'JOS', 'JPN']) expect(GREAT_POWERS).toContain(c)
  const dir = path.join(ROOT, 'supabase', 'migrations')
  const file = readdirSync(dir).find((f) => f.endsWith('_the_great_powers.sql'))
  expect(file, 'the GP1 migration').toBeTruthy()
  const sql = readFileSync(path.join(dir, file as string), 'utf8')
  const seeded = /insert into public\.great_powers \(nation_id\)\s+select n\.id from public\.nations n\s+where n\.code in \(([^)]*)\)/.exec(sql)?.[1].match(/'([A-Z]{3})'/g)?.map((s) => s.slice(1, 4)) ?? []
  expect(seeded.sort()).toEqual([...GREAT_POWERS].sort())
  for (const [c, ports] of Object.entries(homes)) {
    expect(sql, `0187 seeds ${c}'s homes as data/home-ports.json lists them`).toContain(
      `('${c}', array[${ports.map((p) => `'${p}'`).join(', ')}])`,
    )
  }
})

test('the picker offers the ten great powers and no local ruler', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(PHONE)
  await page.goto('profile')
  await ready(page)
  await page.getByTestId('country-change').click()
  const picker = page.getByTestId('nation-picker')
  await expect(picker.locator('[data-testid^="nation-"]')).toHaveCount(GREAT_POWERS.length, { timeout: 60_000 })
  for (const c of GREAT_POWERS) await expect(picker.getByTestId(`nation-${c}`)).toBeVisible()
  for (const [c] of minors) await expect(picker.getByTestId(`nation-${c}`)).toHaveCount(0)
})

test('a city a minor nation founded names its local ruler: Safi, ruled by Morocco', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(PHONE)
  await page.goto('map')
  await ready(page)
  // Safi: Morocco's seat (data/ports.json), one of the thirteen; it lies in Lisbon's first view, clear of a strait
  await openCityPanel(page, 'SAF', 'Safi')
  const ruler = page.getByTestId('city-ruler').first()
  await expect(ruler).toBeVisible({ timeout: 30_000 })
  await expect(ruler).toContainText(`ruled by ${nameOf('MAR')}`)
  await expect(ruler.getByTestId('flag')).toHaveAttribute('data-nation', 'MAR')
  // the ruler is not a holder: Morocco's former home is contested now, flying no country or a power's
  await expect(page.getByTestId('city-flag').first()).not.toContainText('Home city')
  // (a great power's home names no ruler: Lisbon, in map.flag.spec.ts's title-line test)
})

test('the Codex lists the ten as Great powers and the thirteen as Local rulers', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(PHONE)
  await page.goto('compendium')
  await ready(page)
  await page.getByRole('tab', { name: /^Nations/i }).first().click()
  // THE CATALOGUE IS A POP-UP PAGE (owner, 2026-10-31: *"make everything small, compact and once
  // clicked show new page popping up"*): the face strip selects, and `codex-open` opens the face's
  // whole page. Here the face used to draw in place; this drives the mechanism a player drives.
  await page.getByTestId('codex-open').click()
  await expect(page.getByTestId('codex-open-page')).toBeVisible()
  await expect(page.getByTestId('nation-great').locator('[data-testid="flag"]')).toHaveCount(GREAT_POWERS.length, { timeout: 60_000 })
  await expect(page.getByTestId('nation-rulers').locator('[data-testid="flag"]')).toHaveCount(minors.length)
})
