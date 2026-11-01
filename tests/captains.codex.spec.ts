import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, ready } from './appReady.fixture'
import { GLASSES, readTray, trayViolations } from './trayLaw.fixture'

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
  // THE CATALOGUE STANDS ON THE GLASS (the unfold slice, 2026-11-02: it was a pop-up page behind `codex-open`): the face
  // strip selects, and the captains and their three filters are the Codex's own list panel.
  const tiles = page.getByTestId('officer-tile')
  await expect(tiles).toHaveCount(people.length, { timeout: 60_000 })

  // the three filters are there, with the served words (pickers in the panel's header, one option each)
  await expect(page.getByTestId('filter-pick-grade')).toBeVisible()
  await expect(page.getByTestId('filter-pick-focus').locator('option', { hasText: 'Exploration' })).toHaveCount(1)
  await expect(page.getByTestId('filter-pick-job').locator('option', { hasText: 'Gem trader' })).toHaveCount(1)

  // Grade S keeps exactly the S captains, and every one of them says S on its tile
  expect(sCount, 'the data holds no S captain — the filter would prove nothing').toBeGreaterThan(0)
  await page.getByTestId('filter-pick-grade').selectOption('S')
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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE OFFICER TRAY IS AS WIDE AS THE TRAY (the layout sweep of 2026-11-02, row 10)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Measured on origin/main e6bf38d1, 105 captains, headless: the tray's trait rows passed their sentence as the row's
// `value` — "−4.2% crew lost to pirates · −4.2 points of homesickness", 436 px — into a cell that never wraps, so the
// tray's content stood 74 px wider than the tray at 390×844, 144 px at 320×640 and 48 px at 1280×800, "Surgeon" was
// left 0 px wide (one letter a line, 7 lines) and at 320 "Medicine trader" was 25 px wide over 5 lines. A trait now
// is its name on line 1 and its sentence on line 2 (CaptainsFace.tsx), where it wraps; this holds that, with the
// numbers, at the three glasses and in both languages (the traits' own words are served in English in both).
//
// WHICH CAPTAINS. The first of every grade the data holds (the tiles' order is the served one), because the grades carry
// different traits — and the law is made to prove something: at least one of them must know Surgeon, the widest sentence in the
// book, or the data has changed and this would pass over nothing.

const grades = [...new Set(cards.map((c) => c.grade))]

for (const [locale, tag] of [['en-US', 'English'], ['ko-KR', 'Korean']] as const) {
  test.describe(`the officer tray, ${tag}`, () => {
    test.use({ locale })

    test(`Codex → Captains: no trait sideways-scrolls the tray or wraps its name — at ${GLASSES.map((g) => `${g.width}×${g.height}`).join(', ')}`, async ({ page, request, baseURL }) => {
      test.setTimeout(420_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await page.setViewportSize(PHONE)
      await page.goto('compendium')
      await ready(page)
      await page.locator('[data-testid="codex"] [role="tab"]').nth(2).click()
      const tiles = page.getByTestId('officer-tile')
      await expect(tiles).toHaveCount(people.length, { timeout: 60_000 })
      expect(grades.length, 'the data holds no grades — nothing to open').toBeGreaterThan(1)

      const broken: string[] = []
      let surgeons = 0
      let traitRows = 0
      for (const glass of GLASSES) {
        await page.setViewportSize(glass)
        for (const grade of grades) {
          await page.getByTestId('filter-pick-grade').selectOption(grade)
          await tiles.first().click()
          const tray = page.getByTestId('officer-tray')
          await expect(tray.getByTestId('captain-grade')).toBeVisible()
          await expect(tray.locator('[data-testid^="captain-trait-"]').first()).toBeVisible()
          const read = await readTray(page, 'officer-tray')
          // `captain-speaks` is a SENTENCE in the label slot ("Speaks Persian, Turkish"): it wraps by design.
          broken.push(...trayViolations(read, `${glass.width}×${glass.height} · grade ${grade} · ${tag}`, (r) => r.id === 'captain-speaks'))
          traitRows += read.rows.filter((r) => r.id.startsWith('captain-trait-')).length
          surgeons += read.rows.filter((r) => r.id === 'captain-trait-SURGEON').length
          await tray.getByTestId('tray-close').click()
          await expect(tray).toHaveCount(0)
        }
      }
      expect(traitRows, 'no trait row was measured — the tray draws none, so nothing was proved').toBeGreaterThan(0)
      expect(surgeons, 'no opened captain knows Surgeon — the widest sentence in the book was not measured').toBeGreaterThan(0)
      expect(broken, `the officer tray is wider than itself, or a trait's name wrapped:\n${broken.join('\n')}`).toEqual([])
    })
  })
}
