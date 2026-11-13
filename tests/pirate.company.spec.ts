import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import { GREAT_POWERS, PIRATE_POWER } from '../scripts/lib/world-derive.mjs'
import { translate } from '../src/lib/i18n'
import { reachable, ready } from './appReady.fixture'
import { serveBrethrenOpen, servePirateCompany } from './pirateWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A COMPANY UNDER THE SKULL, ON THE GLASS (0338's knob `pirates_joinable`, 0380's `pirate` key; owner row 284 "yes they can", row 324
// "do all, make everything work"). Proof 69 plays her through the real commands; this drives the pages she meets, lit, at 390 x 844 and
// 1280 x 800, in English and Korean:
//   * the picker offers the eleven, and choosing the skull SAYS WHAT IT COSTS before she presses Start (the server names the pirate power);
//   * a company founded under the skull through cmd.found_house opens as a company of the Brethren, and her Levels page lists the ten
//     crowns by their names IN HER LANGUAGE, with their flags (the list printed the server's English names in Korean);
//   * her own free port does not say "half: your country" beside a tax of 0;
//   * a company of a crown changes country to the Brethren through Profile's own picker and button.
// Preconditions are the data files and the served snapshot, never a literal count of the world.
// Run it: npm run build && npx vite preview --port 4424 --strictPort, then
//   PLAYWRIGHT_BASE_URL=http://localhost:4424/byeharu-voyage/ npx playwright test pirate.company.spec.ts
// PIRATE_SHOTS=<dir> keeps a picture of each page.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { name: 'phone', width: 390, height: 844 },
  { name: 'desk', width: 1280, height: 800 },
] as const
const LANGS = ['en', 'ko'] as const
const SHOTS = process.env.PIRATE_SHOTS
const CROWNS: string[] = GREAT_POWERS.filter((c: string) => c !== PIRATE_POWER)

async function open(page: Page, lang: string, size: { width: number; height: number }, serve: (p: Page) => Promise<void>, path: string) {
  await page.addInitScript((l) => {
    try {
      localStorage.setItem('bv.locale', l)
    } catch {
      /* a private window: the page falls back to its default */
    }
  }, lang)
  await page.setViewportSize({ width: size.width, height: size.height })
  await serve(page)
  await page.goto(path)
  await ready(page)
}

async function shot(page: Page, name: string) {
  if (!SHOTS) return
  mkdirSync(SHOTS, { recursive: true })
  await page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true })
}

/** Nothing on the page is wider than the window: no sideways scroll at this width. */
async function fits(page: Page, where: string) {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(over, `${where}: the page scrolls sideways by ${over}px`).toBeLessThanOrEqual(0)
}

for (const lang of LANGS) {
  for (const size of SIZES) {
    const tag = `${lang}, ${size.width}`

    test(`the picker offers the eleven and says what the skull costs (${tag})`, async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await open(page, lang, size, serveBrethrenOpen, 'ui/gates/found')
      const picker = page.getByTestId('nation-picker')
      await expect(picker.locator('[data-testid^="nation-"]')).toHaveCount(GREAT_POWERS.length, { timeout: 60_000 })
      await expect(page.getByTestId('nation-skull'), 'no word of the skull while a crown is chosen').toHaveCount(0)
      const begin = (await page.getByTestId('found-begin').innerText()).trim()
      await picker.getByTestId(`nation-${PIRATE_POWER}`).click()
      const note = page.getByTestId('nation-skull')
      await expect(note).toBeVisible()
      await expect(note).toHaveText(translate(lang, 'found.skull'))
      // how she begins names her own capital now, not the capital of the crown that was chosen first
      await expect(page.getByTestId('found-begin')).not.toHaveText(begin)
      // the note stands inside the form card, whole
      const card = (await page.getByTestId('found-form').boundingBox())!
      const box = (await note.boundingBox())!
      expect(box.x, 'the note starts inside the card').toBeGreaterThanOrEqual(card.x)
      expect(box.x + box.width, 'the note ends inside the card').toBeLessThanOrEqual(card.x + card.width + 0.5)
      await fits(page, 'Start')
      await shot(page, `picker-skull-${lang}-${size.width}`)
    })

    test(`a company under the skull: her Levels page names the crowns in her language, her free port asks no half (${tag})`, async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await open(page, lang, size, servePirateCompany, 'profile')
      // the names the page prints for the powers in this language: the picker's own tiles
      await page.getByTestId('country-change').click()
      const tiles = page.getByTestId('nation-picker').locator('[data-testid^="nation-"]')
      await expect(tiles).toHaveCount(GREAT_POWERS.length, { timeout: 60_000 })
      const local: Record<string, string> = {}
      for (const c of GREAT_POWERS as string[]) local[c] = (await page.getByTestId(`nation-${c}`).innerText()).trim()
      // she is of the Brethren: the house line says so, in her language
      await expect(page.getByTestId('house-line')).toContainText(local[PIRATE_POWER])
      await fits(page, 'Profile')
      await shot(page, `profile-${lang}-${size.width}`)

      await page.goto('command')
      await ready(page)
      await page.getByText(translate(lang, 'command.f_levels'), { exact: true }).first().click()
      const rows = page.getByTestId('levels-country')
      await expect(rows).toHaveCount(CROWNS.length, { timeout: 60_000 })
      const printed = (await rows.allInnerTexts()).join('\n')
      for (const c of CROWNS) expect(printed, `the Levels list names ${c} as the picker does (${local[c]})`).toContain(local[c])
      await expect(rows.locator('[data-testid="flag"]')).toHaveCount(CROWNS.length)
      await fits(page, 'Levels')
      await shot(page, `levels-${lang}-${size.width}`)

      // her own free port: a tax of 0 is not "half: your country"
      await page.goto('command')
      await ready(page)
      await page.getByText(translate(lang, 'command.f_invest'), { exact: true }).first().click()
      const tax = page.getByTestId('townhall-your-tax')
      await expect(tax).toBeVisible({ timeout: 60_000 })
      await expect(tax).not.toContainText(translate(lang, 'books.half').trim())
      await fits(page, 'Invest')
      await shot(page, `townhall-home-${lang}-${size.width}`)
    })
  }
}

test('a company of a crown changes country to the Brethren through Profile, and is told what it costs first', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  await open(page, 'en', SIZES[0], serveBrethrenOpen, 'profile')
  await page.getByTestId('country-change').click()
  const tile = page.getByTestId(`nation-${PIRATE_POWER}`)
  await expect(tile).toBeVisible({ timeout: 60_000 })
  const name = (await tile.innerText()).trim()
  await tile.click()
  await expect(page.getByTestId('nation-skull')).toHaveText(translate('en', 'found.skull'))
  await shot(page, 'profile-change-skull-en-390')
  await page.getByTestId('country-confirm').click()
  await expect(page.getByTestId('house-line')).toContainText(name, { timeout: 60_000 })
  // the next change is a wait: the page says when
  await expect(page.getByTestId('country-next')).toBeVisible()
  await shot(page, 'profile-changed-en-390')
})
