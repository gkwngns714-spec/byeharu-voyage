import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// RESTART, AND HQ'S OWN CITY, ON THE GLASS (0509; the owner, 2026-11-25: "Right now my account does not have a designated HQ. I need a way
// to restart the game"). Proofs 213 and 214 prove the server. This proves what the player sees and presses:
//   * dark (the shipped world): Profile draws no Restart;
//   * lit: the press (44 px, inside the glass) opens a page OVER Profile and moves nothing on it; only the company's own name, typed whole,
//     opens the last press; six countries of Europe are offered; a bad name is refused in the server's words; a good one starts the new
//     company, whose name, country and HQ are drawn after;
//   * HQ shows the HQ city while the one fleet lies elsewhere; the city's name (44 px) opens the list; a second HQ is shown by a press.

const GLASSES = [
  { width: 390, height: 844 },
  { width: 320, height: 640 },
  { width: 1440, height: 900 },
] as const

const lit = () =>
  patchedWorldImage('restart-lit', async (pg) => {
    await pg.exec(`update public.world_config set value = 'true'::jsonb where key = 'restart_enabled'`)
  })
const away = () =>
  patchedWorldImage('hq-away', async (pg) => {
    await pg.exec(`
      create function public.t_away() returns trigger language plpgsql as $t$ begin new.port_id := (select id from public.ports where code = 'SET'); return new; end $t$;
      create trigger t_away before insert on public.fleets for each row execute function public.t_away();
      create function public.t_hq() returns trigger language plpgsql as $t$ begin
        if new.slot = 1 then insert into public.company_hqs (player_id, slot, port_id) select new.player_id, 2, id from public.ports where code = 'LON'; end if; return new; end $t$;
      create trigger t_hq after insert on public.company_hqs for each row execute function public.t_hq()`)
  })

const box = (page: Page, sel: string) =>
  page.evaluate((s) => {
    const r = document.querySelector(s)?.getBoundingClientRect()
    return r ? { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) } : null
  }, sel)
const tall = async (page: Page, sel: string) => {
  const b = await box(page, sel)
  expect(b && b.h >= 44 && b.w >= 44, `${sel} is under 44 px: ${JSON.stringify(b)}`).toBe(true)
}
const noSideScroll = async (page: Page) =>
  expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1), 'the page scrolls sideways').toBe(false)

test.beforeEach(async ({ request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
})

test('dark: Profile draws no Restart', async ({ page }) => {
  await page.goto('profile')
  await ready(page)
  await expect(page.getByTestId('house-line')).toBeVisible({ timeout: 120_000 })
  await expect(page.getByTestId('profile-restart')).toHaveCount(0)
})

for (const glass of GLASSES) {
  test(`lit, ${glass.width}: the name typed, a new name, a country; the new company is drawn after`, async ({ page }) => {
    await page.setViewportSize(glass)
    await serveWorldImage(page, await lit())
    await page.goto('profile')
    await ready(page)
    const open = page.getByTestId('restart-open')
    await expect(open).toBeVisible({ timeout: 120_000 })
    await tall(page, '[data-testid="restart-open"]')
    const old = (await page.getByTestId('house-line').locator('h2').innerText()).trim()
    await open.scrollIntoViewIfNeeded()
    const behind = ['[data-testid="house-line"]', '[data-testid="country"]', '[data-testid="profile-account"]', '[data-testid="profile-restart"]']
    const before = await Promise.all(behind.map((s) => box(page, s)))
    await open.click()
    await expect(page.getByTestId('restart-page')).toBeVisible()
    expect(await Promise.all(behind.map((s) => box(page, s))), 'Profile moved when the Restart page opened').toEqual(before)
    await noSideScroll(page)
    await expect(page.locator('[data-testid^="restart-nation-"]')).toHaveCount(6)
    const press = page.getByTestId('restart-press')
    await expect(press).toBeDisabled()
    await page.getByTestId('restart-name').fill('A*B')
    await page.getByTestId('restart-confirm').fill(old.slice(0, -1))
    await expect(press).toBeDisabled()
    await page.getByTestId('restart-confirm').fill(old)
    await expect(press).toBeEnabled()
    await tall(page, '[data-testid="restart-press"]')
    await press.click()
    await expect(page.getByTestId('restart-page').getByText('No special characters', { exact: false })).toBeVisible({ timeout: 60_000 })
    await page.screenshot({ path: `test-results/restart/refused-${glass.width}.png` })
    const next = `Casa Outra ${glass.width}`
    await page.getByTestId('restart-name').fill(next)
    await page.getByTestId('restart-nation-ENG').click()
    await press.click()
    await expect(page.getByTestId('house-line').locator('h2')).toHaveText(next, { timeout: 120_000 })
    await page.locator('a[href$="/city"]').first().click()
    await expect(page.getByTestId('city-name')).toHaveText('London', { timeout: 120_000 })
  })
}

for (const glass of GLASSES) {
  test(`HQ, ${glass.width}: the HQ city, not the fleet's; its name opens the list and switches`, async ({ page }) => {
    await page.setViewportSize(glass)
    await serveWorldImage(page, await away())
    await page.goto('city')
    await ready(page)
    await expect(page.getByTestId('city-name')).toHaveText('Lisbon', { timeout: 120_000 })
    await tall(page, '[data-testid="hq-city-switch"]')
    const before = await box(page, '[data-testid="hq-company"]')
    await page.getByTestId('hq-city-switch').click()
    await expect(page.getByTestId('hq-cities-page')).toBeVisible()
    expect(await box(page, '[data-testid="hq-company"]'), 'HQ moved when the list opened').toEqual(before)
    await tall(page, '[data-testid="hq-city-LON"]')
    await page.screenshot({ path: `test-results/restart/hq-list-${glass.width}.png` })
    await page.getByTestId('hq-city-LON').click()
    await expect(page.getByTestId('city-name')).toHaveText('London')
    await expect(page.getByTestId('hq-cities-page')).toBeHidden()
    await noSideScroll(page)
  })
}
