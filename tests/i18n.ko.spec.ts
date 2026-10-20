// BROWSER SPEC — the game in Korean (src/lib/i18n). The browser says `ko-KR`, so the game opens in
// Korean with no switch pressed; every main tab is visited and its UI chrome — headings, buttons,
// tabs, field labels and placeholders — must carry no English word outside an allow-list of proper
// nouns. Then the switch on Profile turns the same page to English and back, IN PLACE.
//
// WHAT THE ALLOW-LIST IS, AND WHY IT IS READ FROM DATA. A name the server serves and the client has
// no Korean entry for prints as served (a truthful lesser answer, NO_SPAGHETTI §7C): ship classes,
// captains, merchant companies and fleets, seas and regions, skills and fittings. Those words are
// read from data/*.json here, never typed, so the list cannot quietly grow to cover a leaked UI
// word: a word that is not a served name is a leak. The handful of fixed tokens below are named
// one by one with their reason.
//
// SCOPE: chrome, not prose. A row's served content (a captain's blurb, a trait line, the server's
// own sentences without a code) stays English in v1 and is out of this sweep by construction — the
// selectors are the elements the client itself words.

import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, WORLD_BOOT_MS } from './appReady.fixture'

test.use({ locale: 'ko-KR' })

const read = (rel: string): unknown => JSON.parse(readFileSync(path.join(process.cwd(), rel), 'utf8'))

/** Every `name` (and `company`, `fleet`) string anywhere in a data file. */
function namesIn(value: unknown, out: Set<string>): Set<string> {
  if (Array.isArray(value)) for (const v of value) namesIn(v, out)
  else if (value && typeof value === 'object')
    for (const [k, v] of Object.entries(value)) {
      if (typeof v === 'string' && /^(name|company|fleet|localName|countryName|word)$/.test(k)) out.add(v)
      else namesIn(v, out)
    }
  return out
}

const SERVED = new Set<string>()
for (const f of [
  'data/officers.json', 'data/captains.generated.json', 'data/npc-houses.json', 'data/npc-roster.generated.json',
  'data/ships.generated.json', 'data/seas.json', 'data/regions.json', 'data/ports.json', 'data/skills.json',
  'data/fittings.json', 'data/gear.generated.json', 'data/ship-lines.json', 'data/faiths.json',
])
  namesIn(read(f), SERVED)

const WORD = /[A-Za-z][A-Za-z'’-]{2,}/g
const ALLOWED = new Set<string>([...SERVED].flatMap((n) => n.match(WORD) ?? []))
for (const w of [
  'Byeharu', 'Voyage', // the game's own name, on the sign-in page and the tab title
  'English', // the switch names each language in its own script
  'Casa', 'Aveiro', 'Gaivota', 'Barca', // the local world's founding house and her ship (src/lib/db/localDb.ts)
])
  ALLOWED.add(w)

const ROUTES = ['command', 'fleets', 'map', 'ledger', 'rank', 'routes', 'compendium', 'profile'] as const

async function open(page: Page, route: string) {
  await page.goto(route)
  await page.waitForFunction(
    () => document.querySelector('[data-world]')?.getAttribute('data-world') === 'ready' && document.querySelectorAll('.animate-pulse').length === 0,
    undefined,
    { timeout: WORLD_BOOT_MS },
  )
  await page.waitForTimeout(400)
}

/** The words the client itself put on screen: headings, buttons, tabs, labels, placeholders. */
async function chromeWords(page: Page): Promise<string[]> {
  const texts = await page.evaluate(() => {
    const out: string[] = []
    for (const el of document.querySelectorAll<HTMLElement>('h1, h2, h3, h4, button, [role="tab"], dt, label, th')) {
      if (el.closest('svg') || !el.checkVisibility()) continue
      out.push(el.innerText)
    }
    for (const el of document.querySelectorAll<HTMLInputElement>('input[placeholder], textarea[placeholder]')) {
      if (el.checkVisibility()) out.push(el.placeholder)
    }
    return out
  })
  return texts.flatMap((t) => t.match(/[A-Za-z][A-Za-z'’-]{2,}/g) ?? [])
}

test('in Korean, no tab shows an English UI word outside the served proper nouns', async ({ page, request, baseURL }) => {
  test.setTimeout(WORLD_BOOT_MS + 240_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  expect(ALLOWED.size, 'no served names were read — the data files moved').toBeGreaterThan(200)
  await page.setViewportSize(PHONE)

  const leaks: string[] = []
  let words = 0
  for (const route of ROUTES) {
    await open(page, route)
    expect(await page.evaluate(() => document.documentElement.lang), 'the browser said ko-KR').toBe('ko')
    const found = await chromeWords(page)
    const korean = await page.evaluate(() => (document.body.innerText.match(/[가-힣]/g) ?? []).length)
    expect(korean, `${route} shows no Korean at all`).toBeGreaterThan(5)
    words += found.length + korean
    for (const w of found) if (!ALLOWED.has(w)) leaks.push(`${route}: ${w}`)
  }
  expect(words, 'nothing was read on any tab — the sweep measured an empty page').toBeGreaterThan(50)
  expect([...new Set(leaks)], 'English UI words in the Korean game').toEqual([])
})

test('the switch on Profile turns the page to English and back, in place', async ({ page, request, baseURL }) => {
  test.setTimeout(WORLD_BOOT_MS + 60_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(PHONE)
  await open(page, 'profile')
  const switcher = page.getByTestId('language-switch')
  await expect(page.getByRole('heading', { name: '프로필' })).toBeVisible()

  // A marker on the shell proves the switch re-rendered the page rather than reloading it.
  await page.evaluate(() => document.querySelector('[data-world]')?.setAttribute('data-ko-probe', 'kept'))
  await switcher.getByRole('tab', { name: 'English' }).click()
  await expect(page.getByRole('heading', { name: 'Profile' })).toBeVisible()
  await expect(page.locator('[data-ko-probe="kept"]')).toHaveCount(1)
  expect(await page.evaluate(() => document.documentElement.lang)).toBe('en')

  await switcher.getByRole('tab', { name: '한국어' }).click()
  await expect(page.getByRole('heading', { name: '프로필' })).toBeVisible()
  await expect(page.locator('[data-ko-probe="kept"]')).toHaveCount(1)

  // The choice is remembered: a reload opens in the language last chosen.
  await switcher.getByRole('tab', { name: 'English' }).click()
  await page.reload()
  await open(page, 'profile')
  await expect(page.getByRole('heading', { name: 'Profile' })).toBeVisible()
})
