import { test, expect, type Locator, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { arrivalCard, LANDING_TEST_TIMEOUT_MS } from './arrivalWait.fixture'
import { buyHere, findCarry, sailAndSell } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════
// THE LEVELS, AS TILES (migration 0411, docs/LEVELS.md). The owner, 2026-11-14: "like rs3, i want diverse skills related to
// this game" and "with exp table, exp info, with benefits when leveling up, what activity needs done etc."
//
// FIXED FACTS, on a new company, phone 320 and 390 and desktop 1280, EN and KO:
//   - the Levels page shows ten tiles in the served order, each with its name in her language, level 1 and a bar;
//   - a pressed tile shows FOUR things for that level: her experience (level, experience, into this level, to go; today
//     against the day's limit and the newest grants for a level raised by doing), what raises it with the served figures,
//     what every level gives, and the whole experience table (twenty rows: hers marked, the next one lit with what is left);
//   - Supplies says 2 a day at sea on a trip of 100 miles into a port, at most 300 a day; level 2 begins at 25 and gives
//     Reputation +20; Trading says a fleet at level 3 and a captain's promotion to B at level 5;
//   - on a phone the level opens in a tray and no tile moves; on a desktop it stands in the middle pane;
//   - nothing is cut and the page does not scroll sideways.
// AND THE HOOK ON THE GLASS (390, EN): after a first voyage that made a port, Supplies holds the experience of its days at sea
// (2 a day, a whole even number), today's figure is the same, and the newest grant is on the list.
// Screenshots go to LEVELS_SHOTS when it is set.
// ═══════════════════════════════════════════════════════════════════════════════

test.use({ locale: 'en-US', deviceScaleFactor: 2 })

const SIZES = [
  { width: 320, height: 568 },
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

const CODES = ['trading', 'exploration', 'combat', 'supplies', 'weather', 'shipbuilding', 'requests', 'craft', 'routes', 'investment'] as const

const WORDS = {
  en: {
    names: ['Trading', 'Exploration', 'Combat', 'Supplies', 'Weather', 'Shipbuilding', 'Requests', 'Craft', 'Routes', 'Investment'],
    fed: /A day at sea with enough supplies: 2 exp a day \(a trip of 100 miles or more, into a port\)/,
    cap: 'At most 300 exp a day.',
    every: 'Reputation +10 × the level',
    gift: (n: number) => `Reputation +${n}`,
    today: (a: number) => `Today ${a} / 300`,
    toGo: '25 to go',
    fleet: '+1 fleet',
    promote: 'Captain promotion to B',
    trade: /Buy or sell goods: 1 exp per 500/,
    noCap: 'No daily limit.',
    vs: 'Levels rise by doing. Academy skills are studied. A level never changes what a skill gives.',
  },
  ko: {
    names: ['교역', '탐험', '전투', '보급', '악천후', '조선', '의뢰', '제작', '항로', '투자'],
    fed: /보급이 충분한 항해 하루: 하루에 경험치 2 \(100.*이상 항해해 항구에 도착할 때\)/,
    cap: '하루 최대 경험치 300.',
    every: '평판 +10 × 레벨',
    gift: (n: number) => `평판 +${n}`,
    today: (a: number) => `오늘 ${a} / 300`,
    toGo: '25 남음',
    fleet: '선단 +1',
    promote: '선장 B 승급',
    trade: /교역품 사고팔기: 500.*마다 경험치 1/,
    noCap: '하루 제한 없음.',
    vs: '레벨은 직접 해서 오릅니다. 아카데미 기술은 배워서 오릅니다. 레벨은 기술의 효과를 바꾸지 않습니다.',
  },
} as const

const shot = async (page: Page, name: string) => {
  if (process.env.LEVELS_SHOTS) await page.screenshot({ path: `${process.env.LEVELS_SHOTS}/${name}.png` })
}

/** Nothing inside `scope` is wider than its own box (a word cut by its container), and the page does not scroll sideways. */
async function nothingCut(page: Page, scope: Locator, what: string) {
  const cut = await scope.evaluate((root) =>
    [...root.querySelectorAll<HTMLElement>('span, li, td, th, h3, h4, button')]
      .filter((e) => e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).overflow !== 'visible')
      .map((e) => (e.textContent ?? '').trim().slice(0, 60)),
  )
  expect(cut, `${what}: cut text`).toEqual([])
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `${what}: the page scrolls sideways`).toBe(true)
}

async function openLevels(page: Page, lang: 'en' | 'ko') {
  await page.goto('command')
  await ready(page)
  if (lang === 'ko') {
    await page.evaluate(() => localStorage.setItem('bv.locale', 'ko'))
    await page.goto('command')
    await ready(page)
  }
  expect(await page.evaluate(() => document.documentElement.lang)).toBe(lang)
  await page.getByTestId('goal-card').click()
  await expect(page.getByTestId('desk-levels').first()).toBeVisible({ timeout: 60_000 })
  await expect(page.getByTestId('level-tiles')).toBeVisible({ timeout: 60_000 })
}

for (const size of SIZES) {
  for (const lang of ['en', 'ko'] as const) {
    test.describe(`Levels at ${size.width}×${size.height}, ${lang}`, () => {
      test.use({ viewport: size })

      test('ten tiles; a pressed level shows its experience, what raises it, what levels give and the experience table', async ({ page, request, baseURL }) => {
        test.setTimeout(420_000)
        expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}: run a preview (or set PLAYWRIGHT_BASE_URL)`).toBe(true)
        const words = WORDS[lang]
        const wide = size.width >= 1024
        await openLevels(page, lang)

        // TEN TILES, in the served order, each with its name whole, level 1 and a bar
        const tiles = page.getByTestId('level-tiles').locator('button')
        await expect(tiles).toHaveCount(CODES.length)
        for (const [i, code] of CODES.entries()) {
          const tile = tiles.nth(i)
          await expect(tile).toHaveAttribute('data-testid', `levels-${code}`)
          await expect(tile).toContainText(words.names[i])
          await expect(tile).toHaveAttribute('data-level', '1')
          await expect(tile.locator('[role="meter"]')).toHaveCount(1)
          const box = (await tile.boundingBox())!
          expect(box.x, `${code}: the tile starts inside the glass`).toBeGreaterThanOrEqual(0)
          expect(box.x + box.width, `${code}: the tile ends inside the glass`).toBeLessThanOrEqual(size.width + 0.5)
          expect(box.height, `${code}: a tile is a press target`).toBeGreaterThanOrEqual(44)
        }
        await expect(page.getByTestId('levels-vs-skills')).toHaveText(words.vs)
        await nothingCut(page, page.getByTestId('level-tiles'), 'the tiles')
        await shot(page, `levels-tiles-${size.width}-${lang}`)

        // PRESS SUPPLIES: no tile moves; the level stands in a tray (phone) or the middle pane (desktop)
        const before = await tiles.evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().left) + ':' + Math.round(e.getBoundingClientRect().top)))
        await page.getByTestId('levels-supplies').click()
        const detail = page.getByTestId('level-detail')
        await expect(detail).toHaveAttribute('data-level-code', 'supplies')
        if (!wide) await expect(page.getByTestId('level-tray')).toBeVisible()
        expect(await tiles.evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().left) + ':' + Math.round(e.getBoundingClientRect().top))), 'a press moved a tile').toEqual(before)

        // 1. her experience
        await expect(detail.getByTestId('level-detail-level')).toContainText('1')
        await expect(detail.getByTestId('level-detail-exp')).toContainText('0')
        await expect(detail.getByTestId('level-detail-progress')).toContainText('0 / 25')
        await expect(detail.getByTestId('level-detail-today')).toHaveText(words.today(0))
        // 2. what raises it, with the served figures and the day's limit
        await expect(detail.getByTestId('level-detail-activities').locator('li')).toHaveCount(1)
        await expect(detail.getByTestId('level-detail-activities')).toContainText(words.fed)
        await expect(detail.getByTestId('level-detail-cap')).toHaveText(words.cap)
        // 3. what every level gives
        await expect(detail.getByTestId('level-detail-benefits')).toContainText(words.every)
        // 4. the experience table: twenty rows; hers marked; the next one lit with what is left and what it gives
        const rows = detail.getByTestId('level-row')
        await expect(rows).toHaveCount(20)
        await expect(rows.nth(0)).toHaveAttribute('data-state', 'mine')
        await expect(rows.nth(1)).toHaveAttribute('data-state', 'next')
        await expect(rows.nth(2)).toHaveAttribute('data-state', 'later')
        await expect(rows.nth(1)).toContainText('25')
        await expect(rows.nth(1).getByTestId('level-row-togo')).toHaveText(words.toGo)
        await expect(rows.nth(1)).toContainText(words.gift(20))
        await expect(rows.nth(2)).toContainText('100')
        await expect(rows.nth(19)).toContainText('9,025')
        await expect(rows.nth(19)).toContainText(words.gift(200))
        await nothingCut(page, detail, 'Supplies')
        await shot(page, `levels-supplies-${size.width}-${lang}`)
        await rows.nth(1).scrollIntoViewIfNeeded()
        await shot(page, `levels-supplies-table-${size.width}-${lang}`)

        // TRADING, a level counted from her record: its own rules, served
        if (!wide) await page.getByTestId('tray-close').click()
        await page.getByTestId('levels-trading').click()
        await expect(detail).toHaveAttribute('data-level-code', 'trading')
        await expect(detail.getByTestId('level-detail-activities')).toContainText(words.trade)
        await expect(detail.getByTestId('level-detail-cap')).toHaveText(words.noCap)
        await expect(detail.getByTestId('level-detail-today')).toHaveCount(0)
        await expect(rows.nth(2)).toContainText(words.fleet)
        await expect(rows.nth(4)).toContainText(words.promote)
        await nothingCut(page, detail, 'Trading')
        await rows.nth(1).scrollIntoViewIfNeeded()
        await shot(page, `levels-trading-table-${size.width}-${lang}`)
      })
    })
  }
}

test.describe('Levels at 390×844, en: a voyage raises Supplies', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('after a first voyage into a port, Supplies holds its days at sea and lists the grant', async ({ page, request, baseURL }) => {
    test.setTimeout(Math.max(LANDING_TEST_TIMEOUT_MS, 900_000))
    expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}: run a preview (or set PLAYWRIGHT_BASE_URL)`).toBe(true)
    await page.goto('command')
    await ready(page)
    const { code, city } = await findCarry(page)
    await buyHere(page, code)
    await sailAndSell(page, code, city)
    await page.goto('you')
    await ready(page)
    await expect(page.getByTestId('arrival-card')).toBeVisible({ timeout: 480_000 })
    await arrivalCard(page, 'Levels: a voyage raises Supplies')

    await page.goto('command')
    await ready(page)
    await page.getByTestId('goal-card').click()
    await expect(page.getByTestId('level-tiles')).toBeVisible({ timeout: 60_000 })
    await page.getByTestId('levels-supplies').click()
    const detail = page.getByTestId('level-detail')
    await expect(detail).toHaveAttribute('data-level-code', 'supplies')
    const exp = Number(((await detail.getByTestId('level-detail-exp').innerText()).match(/[\d,]+/) ?? ['0'])[0].replace(/,/g, ''))
    const today = await detail.getByTestId('level-detail-today').innerText()
    console.log(`levels: after a first voyage to ${city}, Supplies ${exp} exp; ${today}; the list says ${JSON.stringify((await detail.innerText()).replace(/\s+/g, ' ').slice(0, 260))}`)
    // a near trip may be under the 100 miles the rule asks: then nothing is granted, and the page must say exactly that
    if (exp === 0) {
      await expect(detail.getByTestId('level-detail-recent')).toHaveCount(0)
      test.info().annotations.push({ type: 'note', description: `the trip to ${city} granted no Supplies (under 100 miles, or a hungry day)` })
    } else {
      expect(exp % 2, 'Supplies is 2 a day at sea').toBe(0)
      expect(today).toBe(`Today ${exp} / 300`)
      await expect(detail.getByTestId('level-detail-recent').locator('li')).toHaveCount(1)
      await expect(detail.getByTestId('level-detail-recent')).toContainText(`+${exp}`)
      await expect(detail.getByTestId('level-detail-recent')).toContainText('A day at sea with enough supplies')
    }
    await shot(page, 'levels-supplies-after-voyage-390-en')
  })
})
