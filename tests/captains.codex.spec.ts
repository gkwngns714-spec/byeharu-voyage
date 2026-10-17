import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, ready } from './appReady.fixture'

// CODEX → CAPTAINS (0156, K4; docs/SKILLS_AND_CAPTAINS.md §4.1, §8 K4): world.officers / worldOfficers
// serves every captain WITH her card (world.captain_card — the same card world.inn / worldInn serves
// every guest), and the face prints it as served: the grade on the tile, the Grade / Role / Job filters
// built from the served values, and in the tray the traits she knows with their lines and the
// "Speaks …" sentence. The preconditions come from the data files the world guard holds the database
// to (data/officers.json, data/captains.generated.json) — never a literal count.

const read = (rel: string) => JSON.parse(readFileSync(path.join(process.cwd(), rel), 'utf8'))
const people = (read('data/officers.json') as { officers: { code: string; name: string }[] }).officers
const cards = (read('data/captains.generated.json') as { captains: { code: string; grade: string; job: string }[] }).captains
const sCount = cards.filter((c) => c.grade === 'S').length

test('Codex → Captains: every captain carries her grade, and the Grade filter keeps exactly that grade', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(PHONE)
  await page.goto('compendium')
  await ready(page)
  await page.getByRole('tab', { name: /^Captains/i }).first().click()
  const tiles = page.getByTestId('officer-tile')
  await expect(tiles).toHaveCount(people.length, { timeout: 60_000 })

  // the three filters are there, with the served words
  const filters = page.getByTestId('captain-filters')
  await expect(filters.getByRole('tablist', { name: 'Grade' })).toBeVisible()
  await expect(filters.getByRole('tablist', { name: 'Role' }).getByRole('tab', { name: 'Exploration' })).toBeVisible()
  await expect(filters.getByRole('tablist', { name: 'Job' }).getByRole('tab', { name: 'Gem trader' })).toBeVisible()

  // Grade S keeps exactly the S captains, and every one of them says S on its tile
  expect(sCount, 'the data holds no S captain — the filter would prove nothing').toBeGreaterThan(0)
  await filters.getByRole('tablist', { name: 'Grade' }).getByRole('tab', { name: 'S', exact: true }).click()
  await expect(tiles).toHaveCount(sCount)
  for (const text of await tiles.allInnerTexts()) expect(text).toMatch(/\bS\b/)

  // a captain's tray: her job line, the traits she knows (S: ten), and the languages sentence
  await tiles.first().click()
  const tray = page.getByTestId('officer-tray')
  await expect(tray.getByTestId('captain-grade')).toContainText('S')
  await expect(tray.locator('[data-testid^="captain-trait-"]')).toHaveCount(10)
  await expect(tray.getByTestId('captain-speaks')).toContainText(/^Speaks /)
  await expect(tray).toContainText('%')
})
