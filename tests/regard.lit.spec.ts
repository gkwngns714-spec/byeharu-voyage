import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// A COMPANY'S STANDING WITH EACH COUNTRY, LIT, ON THE PAGE (0319 built it; 0373 lit `regard_enabled`, owner rows 288 and 324).
//   1. THE LEVELS PAGE, as shipped (no patch): the Countries list no longer says "Not open yet."; it names every country, in her language, with her band and her score. A new
//      company of Portugal is Friendly 200 at home and Wary -200 with a country her power is at war with. Phone (390 px) and narrow phone (320 px), English and Korean; nothing
//      cut, no sideways scroll.
//   2. THE TOWN HALL'S BAND: the City page's Relationship cell reads her band ("Friendly" / "우호") in place of the stance's word. The hall serves its dues only where the city
//      purses are lit and the economy is closed (as on prod), so this one runs on a copy of the image with the purses lit by the chain's own switch (public.city_treasury_switch)
//      and the economy closed. Regard itself is NOT set by the patch: it is the chain's.

const WORDS = {
  en: { levels: 'Levels', city: 'City', dark: 'Not open yet.', friendly: 'Friendly', wary: 'Wary', neutral: 'Neutral', home: 'Portugal' },
  ko: { levels: '레벨', city: '도시', dark: '아직 안 열림', friendly: '우호', wary: '경계', neutral: '중립', home: '포르투갈' },
} as const
const GLASSES = [{ width: 390, height: 844 }, { width: 320, height: 640 }] as const

const pursesLit = () =>
  patchedWorldImage('regard-hall-purses', async (pg) => {
    // the switch refuses a world whose money cannot carry the merchants' surplus line; lowered for the switch and put back (tests/map.townhall.spec.ts does the same)
    const above = await pg.query<{ v: unknown }>(`select value as v from public.world_config where key = 'npc_invest_above'`)
    await pg.exec(`update public.world_config set value = to_jsonb(0) where key = 'npc_invest_above'`)
    const sw = await pg.query<{ j: { enabled: boolean } }>(`select public.city_treasury_switch(true) as j`)
    if (!sw.rows[0].j.enabled) throw new Error(`the switch did not light the purses: ${JSON.stringify(sw.rows[0].j)}`)
    await pg.query(`update public.world_config set value = $1::jsonb where key = 'npc_invest_above'`, [JSON.stringify(above.rows[0].v)])
    // the hall's dues (and so her band) are served where a dock fee exists: the economy closed, as on prod
    await pg.exec(`update public.world_config set value = 'true'::jsonb where key = 'economy_closed'`)
  })

async function noCut(page: Page, testid: string, where: string) {
  const cut = await page
    .getByTestId(testid)
    .first()
    .evaluate((el) => [...el.querySelectorAll('span, div')].filter((n) => n.children.length === 0 && (n.scrollWidth > n.clientWidth + 1 || (n.textContent ?? '').includes('…'))).length)
  expect(cut, `${where}: a word is cut`).toBe(0)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `${where}: the page scrolls sideways`).toBe(true)
}

for (const glass of GLASSES) {
  for (const lang of ['en', 'ko'] as const) {
    test.describe(`regard lit, ${glass.width}px ${lang}`, () => {
      test.use({ viewport: glass, locale: lang === 'ko' ? 'ko-KR' : 'en-US' })
      const w = WORDS[lang]
      const bandAndScore = new RegExp(`(${w.friendly}|${w.wary}|${w.neutral}) [-−]?[0-9]`)

      test('the Levels page names every country with her band and score', async ({ page, request, baseURL }) => {
        test.setTimeout(480_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
        await page.goto('command')
        await ready(page)
        await page.getByRole('tab', { name: w.levels, exact: true }).click()
        await expect(page.getByTestId('desk-levels').first()).toBeVisible({ timeout: 60_000 })
        const list = page.getByTestId('levels-regard').first()
        await expect(list).toBeVisible({ timeout: 60_000 })
        await list.scrollIntoViewIfNeeded()
        await expect(list).not.toContainText(w.dark)
        const rows = list.getByTestId('levels-country')
        // every country with a crown: the ten great powers
        expect(await rows.count()).toBeGreaterThanOrEqual(10)
        const texts = (await rows.allInnerTexts()).map((s) => s.replace(/\s+/g, ' ').trim())
        const said = texts.join(' | ')
        // a founding company is Portugal's: Friendly 200 at home; Wary -200 with a country at war; the rest Neutral
        const home = texts.filter((s) => s.includes(`${w.friendly} 200`))
        expect(home, `no "${w.friendly} 200" row: ${said}`).toHaveLength(1)
        // the country is named in her language
        expect(home[0], 'the home row does not name her country in her language').toContain(w.home)
        // a score below zero is printed with the minus sign (U+2212), as every figure of the game is
        expect(texts.filter((s) => /[-−]200$/.test(s) && s.includes(w.wary)).length, `no "${w.wary} -200" row: ${said}`).toBeGreaterThanOrEqual(1)
        expect(texts.filter((s) => s.includes(w.neutral)).length).toBeGreaterThanOrEqual(1)
        for (const s of texts) {
          expect(s, 'a row with no band word and score').toMatch(bandAndScore)
          if (lang === 'ko') expect(s, 'a country is named in English on the Korean page').not.toMatch(/[A-Za-z]{4,}/)
        }
        await noCut(page, 'levels-regard', 'the Countries list')
        if (process.env.REGARD_SHOTS) await page.screenshot({ path: `${process.env.REGARD_SHOTS}/regard-levels-${glass.width}-${lang}.png` })
      })

      test('the Town Hall: Relationship reads her band at home', async ({ page, request, baseURL }) => {
        test.setTimeout(600_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
        await serveWorldImage(page, await pursesLit())
        await page.goto('command')
        await ready(page)
        await page.getByRole('tab', { name: w.city, exact: true }).click()
        await expect(page.getByTestId('desk-city')).toBeVisible()
        await page.getByTestId('desk-city-open').click()
        await expect(page).toHaveURL(/\/city\?port=[A-Z]{3}/)
        await ready(page)
        const cell = page.getByTestId('city-relationship')
        await expect(cell).toBeVisible({ timeout: 60_000 })
        await expect.poll(async () => cell.getAttribute('data-band'), { timeout: 90_000, message: 'the hall never served her band' }).toBe('friendly')
        await expect(cell).toContainText(w.friendly)
        await expect(cell).toHaveAttribute('data-stance', 'home')
        await noCut(page, 'city-hall-panel', 'the hall panel')
        if (process.env.REGARD_SHOTS) await page.screenshot({ path: `${process.env.REGARD_SHOTS}/regard-hall-${glass.width}-${lang}.png` })
      })
    })
  }
}
