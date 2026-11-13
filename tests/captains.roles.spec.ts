import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { readTray, trayViolations } from './trayLaw.fixture'
import { serveCaptainWorld } from './captainSheet.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A CAPTAIN'S ROLE, AND THE ROSTER BY ROLE (owner rows 61 and 66)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"captains will also be designated a role - role based on combat, exploration, trading ... combat close, long range, etc."* (owner, row 66.)
// The server has served the role and the two combat jobs since 0156; no face said which RANGE a combat captain fights at, and the roster on You
// was one flat list. This holds the client slice to the running build, at the phone (390×844) and the smallest phone (320×640), in English and Korean:
//
//   · ROSTER  You lists the captains under one heading a role, in the roster's order (Trading, Exploration, Combat · Long range, Combat · Close range).
//             The house of tests/captainSheet.fixture.ts keeps a Purser, a Navigator and a Boarder: three roles hold one captain each, and long range,
//             which nobody fills, keeps its heading and says None.
//   · ROLE    a captain's card says her role on its own row, and a combat captain's says her range (the Boarder: Combat · Close range).
//   · LAW     nothing stands past the glass and the tray keeps its width; no name is cut with an ellipsis.
//   · CODEX   the Codex's Role filter offers the two ranges, and choosing Long range leaves only Gunners.
//
// Run it: npm run build && npx vite preview --port 4405 --strictPort --host localhost, then
// PLAYWRIGHT_BASE_URL=http://localhost:4405/byeharu-voyage/ npx playwright test captains.roles.spec.ts

const GLASSES = [
  { width: 390, height: 844 },
  { width: 320, height: 640 },
] as const

const WORDS = {
  en: { roles: ['Trading', 'Exploration', 'Combat · Long range', 'Combat · Close range'], none: 'None', role: 'Role', boarder: 'Boarder', gunner: 'Gunner' },
  ko: { roles: ['교역', '탐험', '전투 · 원거리', '전투 · 근거리'], none: '없음', role: '역할', boarder: '돌격대', gunner: '포수' },
} as const

const NOT_SERVED = (url: string | undefined) => `nothing served at ${url} — run \`npm run build && npx vite preview --port 4405\` and re-run`

async function inLocale(page: Page, locale: 'en' | 'ko') {
  await page.addInitScript((l) => window.localStorage.setItem('bv.locale', l), locale)
}

const pageOverflow = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)

for (const locale of ['en', 'ko'] as const) {
  const w = WORDS[locale]

  test(`You lists the captains by role, a combat captain's card says her range, and nothing leaves the glass (${locale}, 390 and 320)`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), NOT_SERVED(baseURL))
    await inLocale(page, locale)
    await page.setViewportSize(GLASSES[0])
    await serveCaptainWorld(page)
    await page.goto('you')
    await ready(page)
    await expect(page.getByTestId('your-captain')).toHaveCount(3, { timeout: 120_000 })

    for (const glass of GLASSES) {
      const at = `${locale} ${glass.width}×${glass.height}`
      await page.setViewportSize(glass)
      const roster = page.getByTestId('your-captains')

      // ROSTER: the four headings, in order, each with its count; the empty role says None
      const heads = roster.getByTestId('captain-role')
      await expect(heads, at).toHaveText([...w.roles])
      expect(await heads.evaluateAll((els) => els.map((e) => `${e.getAttribute('data-role')}=${e.getAttribute('data-count')}`)), at).toEqual([
        'trading=1',
        'exploration=1',
        'combat:long=0',
        'combat:close=1',
      ])
      await expect(roster.getByTestId('captain-role-empty'), at).toHaveText([w.none])
      // each captain stands under her own role's heading, in the document's order
      const order = await roster.evaluate((el) =>
        [...el.querySelectorAll('[data-testid="captain-role"], [data-testid="your-captain"], [data-testid="captain-role-empty"]')].map((e) => {
          const id = e.getAttribute('data-testid')
          if (id === 'captain-role') return `#${e.getAttribute('data-role')}`
          if (id === 'captain-role-empty') return 'none'
          return (e.textContent ?? '').trim()
        }),
      )
      expect(order.filter((x) => x.startsWith('#') || x === 'none').join(' '), at).toBe('#trading #exploration #combat:long none #combat:close')
      expect(order[1], `${at}: the Purser stands under Trading`).toContain('Welser')
      expect(order[3], `${at}: the Navigator stands under Exploration`).toContain('Elcano')
      expect(order[7], `${at}: the Boarder stands under Close range`).toContain('Turgut')
      // LAW: no row past the roster's edge, no ellipsis on a name, the page does not scroll sideways
      const wide = await roster.evaluate((el) => {
        const edge = el.getBoundingClientRect().right
        return [...el.querySelectorAll('[data-testid="captain-role"], [data-testid="your-captain"]')].filter((e) => e.getBoundingClientRect().right > edge + 0.5).map((e) => e.textContent)
      })
      expect(wide, `${at}: a roster row stands past the roster's edge`).toEqual([])
      expect(await roster.innerText(), `${at}: a name is cut`).not.toContain('…')
      expect(await pageOverflow(page), `${at}: the page scrolls sideways`).toBeLessThanOrEqual(0)

      // ROLE: the Boarder's card
      await page.getByTestId('your-captain').filter({ hasText: 'Turgut' }).click()
      const tray = page.getByTestId('your-captain-tray')
      const role = tray.getByTestId('captain-role-word')
      await expect(role, at).toContainText(w.role)
      await expect(role, at).toContainText(w.roles[3])
      await expect(tray.getByTestId('captain-sheet'), at).toContainText(w.boarder)
      const read = await readTray(page, 'your-captain-tray')
      expect(trayViolations(read, at, (r) => !/^captain-(trait|level|role)-/.test(r.id)), `${at}: the tray broke its width law`).toEqual([])
      await tray.getByTestId('tray-close').click()
      await expect(tray).toHaveCount(0)
    }
  })

  test(`the Codex's Role filter offers the two ranges, and Long range leaves only Gunners (${locale}, 390 and 320)`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), NOT_SERVED(baseURL))
    await inLocale(page, locale)
    await page.setViewportSize(GLASSES[0])
    await page.goto('compendium')
    await ready(page)
    await page.locator('[data-testid="codex"] [role="tab"]').nth(2).click()
    const tiles = page.getByTestId('officer-tile')
    await expect(tiles.first()).toBeVisible({ timeout: 120_000 })
    const pick = page.getByTestId('filter-pick-focus')
    await expect(pick.locator('option')).toHaveText([/.+/, ...w.roles])
    await pick.selectOption({ label: w.roles[2] })
    const n = await tiles.count()
    expect(n, 'no long range captain is in the Codex').toBeGreaterThan(0)
    for (let i = 0; i < n; i++) await expect(tiles.nth(i)).toContainText(w.gunner)

    for (const glass of GLASSES) {
      const at = `${locale} ${glass.width}×${glass.height}`
      await page.setViewportSize(glass)
      expect(await pageOverflow(page), `${at}: the page scrolls sideways`).toBeLessThanOrEqual(0)
      await tiles.first().click()
      const tray = page.getByTestId('officer-tray')
      await expect(tray, at).toContainText(w.roles[2])
      const read = await readTray(page, 'officer-tray')
      expect(read.overflowX, `${at}: the captain's tray is wider than itself`).toBeLessThanOrEqual(0)
      expect(read.pageOverflowX, `${at}: the page scrolls sideways under the tray`).toBeLessThanOrEqual(0)
      await tray.getByTestId('tray-close').click()
      await expect(tray).toHaveCount(0)
    }
  })
}
