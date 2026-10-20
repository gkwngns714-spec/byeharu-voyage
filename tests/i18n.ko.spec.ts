// BROWSER SPEC — the game in Korean (src/lib/i18n). The browser says `ko-KR`, so the game opens in
// Korean with no switch pressed; every main tab is visited and its UI chrome — headings, buttons,
// tabs, field labels and placeholders — must carry no English word outside an allow-list of proper
// nouns. Then the switch on Profile turns the same page to English and back, IN PLACE.
//
// WHAT THE ALLOW-LIST IS, AND WHY IT IS READ FROM DATA. A name the server serves and the client has
// no Korean entry for prints as served (a truthful lesser answer, NO_SPAGHETTI §7C): ship classes,
// captains, merchant companies and fleets, seas and regions, skills and fittings. Those words are
// read from data/*.json here, never typed, and matched as WHOLE names; a served name that is also
// an English UI string in the dictionaries is dropped, so the list cannot cover a leaked UI word.
// Broken on purpose 2026-10-20 (Korean `command.title` set to `Command`) and watched red.
//
// SCOPE: chrome, not prose. A row's served content (a captain's blurb, a trait line, the server's
// own sentences without a code) stays English in v1 and is out of this sweep by construction — the
// selectors are the elements the client itself words.

import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, WORLD_BOOT_MS } from './appReady.fixture'
import { DICT, type Msg } from '../src/lib/i18n'

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

/** Every English UI string the dictionaries hold. A served name that is ALSO one of these (a skill
 *  called `Trade`, a word `Command`) is not allowed: on screen it cannot be told from a leak. */
const UI_ENGLISH = new Set<string>()
for (const d of Object.values(DICT as unknown as Record<string, { en: Record<string, Msg> }>))
  for (const m of Object.values(d.en)) for (const v of typeof m === 'string' ? [m] : [m.one, m.other]) UI_ENGLISH.add(v.trim())

/** The served names a Korean screen may still print, WHOLE — longest first, so `Casa de Aveiro` is
 *  taken out before `Casa` would be. A name is matched as a phrase, never word by word: a word-level
 *  list swallowed `Cargo` and `Port` (a ship class, a harbour) and passed a leaked heading. */
const NAMES = [...SERVED, 'Byeharu Voyage', 'Casa de Aveiro', 'Gaivota', 'Barca']
  .filter((n) => n.length >= 3 && !UI_ENGLISH.has(n))
  // The switch names English in English on purpose (common.english), the one UI word excused.
  .concat('English')
  .sort((a, b) => b.length - a.length)
const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const NAME_RE = new RegExp(NAMES.map(escape).join('|'), 'g')

/** The Latin words left in a text once every served name in it is taken out. */
const leftover = (text: string) => text.replace(NAME_RE, ' ').match(/[A-Za-z][A-Za-z'’-]{2,}/g) ?? []

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
async function chromeTexts(page: Page): Promise<string[]> {
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
  return texts
}

test('in Korean, no tab shows an English UI word outside the served proper nouns', async ({ page, request, baseURL }) => {
  test.setTimeout(WORLD_BOOT_MS + 240_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  expect(NAMES.length, 'no served names were read — the data files moved').toBeGreaterThan(200)
  expect(leftover('Command'), 'a UI word is never excused as a served name').toEqual(['Command'])
  await page.setViewportSize(PHONE)

  const leaks: string[] = []
  let words = 0
  for (const route of ROUTES) {
    await open(page, route)
    expect(await page.evaluate(() => document.documentElement.lang), 'the browser said ko-KR').toBe('ko')
    const found = await chromeTexts(page)
    const korean = await page.evaluate(() => (document.body.innerText.match(/[가-힣]/g) ?? []).length)
    expect(korean, `${route} shows no Korean at all`).toBeGreaterThan(5)
    words += found.length + korean
    for (const text of found) for (const w of leftover(text)) leaks.push(`${route}: ${w} (in "${text.slice(0, 60)}")`)
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
