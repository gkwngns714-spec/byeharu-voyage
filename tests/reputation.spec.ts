import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { buyHere, findCarry, sailAndSell } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// REPUTATION ON THE GLASS (migration 0352, slice R1 of docs/REPUTATION.md; owner row 317).
// A new company has 0 Reputation in the top bar. It buys at Lisbon, presses Sail & sell and sits on the You tab.
// When the fleet comes in and sells, the arrival card says `+N Reputation` (KO `평판 +N`), and N is held to fixed
// facts, all of them served: the top bar's figure went from 0 to N; N is 25 for the first landfall, 1 for each 250 of
// the sale's profit (the card's own figure) and the voyage's miles (at most 40); the You tab shows N and
// `Today N−25 / 600`, because a landfall is outside the day's cap. Phone and desktop, EN and KO.
// The voyage is driven in English (the trade fixtures read English words); the language is changed while she sails.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ locale: 'en-US', deviceScaleFactor: 2 })

const SIZES = [
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

const WORDS = {
  en: { name: 'Reputation', earned: /^\+([\d,]+) Reputation$/, today: (a: number) => `Today ${a} / 600` },
  ko: { name: '평판', earned: /^평판 \+([\d,]+)$/, today: (a: number) => `오늘 ${a} / 600` },
} as const

for (const size of SIZES) {
  for (const lang of ['en', 'ko'] as const) {
    test.describe(`Reputation at ${size.width}×${size.height}, ${lang}`, () => {
      test.use({ viewport: size })

      test('a first voyage earns Reputation: the top bar, the arrival card and You agree', async ({ page, request, baseURL }) => {
        test.setTimeout(480_000)
        expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}: run a preview (or set PLAYWRIGHT_BASE_URL)`).toBe(true)
        const words = WORDS[lang]
        await page.goto('command')
        await ready(page)

        // a new company: 0, with its word, left of the purse, and the bar stays inside the glass
        const bar = page.getByTestId('reputation')
        // THE TOP BAR'S FIGURE STANDS FROM 640 px UP. On a phone the bar has 17 px left beside the clocks and the purse, and
        // a figure there cuts the game hour off (tests/shell.kstClock.spec.ts); the served number is still on the element.
        const wide = size.width >= 640
        await expect(bar).toHaveAttribute('data-value', '0')
        if (wide) await expect(bar).toHaveText(/^0\s*Reputation$/)
        else await expect(bar).toBeHidden()
        const insideGlass = async () => {
          const purse = (await page.getByTestId('purse').boundingBox())!
          if (wide) {
            const rep = (await bar.boundingBox())!
            expect(rep.x, 'the figure starts inside the glass').toBeGreaterThanOrEqual(0)
            expect(rep.x + rep.width, 'Reputation stands left of the purse').toBeLessThanOrEqual(purse.x + 0.5)
          } else if ((await page.evaluate(() => document.documentElement.lang)) === 'en') {
            // the line tests/shell.kstClock.spec.ts holds, in English. (In Korean the bar's own words are wider and the
            // hour is cut on main already, with or without this slice: the figure is not drawn on a phone either way.)
            const hour = (await page.getByTestId('game-clock').boundingBox())!
            const right = await page.getByTestId('game-clock').evaluate((el) => (el.parentElement as HTMLElement).getBoundingClientRect().right)
            expect(hour.x + hour.width, 'the game hour is cut off').toBeLessThanOrEqual(right + 0.5)
          }
          expect(purse.x + purse.width, 'the purse ends inside the glass').toBeLessThanOrEqual(size.width + 0.5)
          expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
        }
        await insideGlass()

        // the Trade screen's goal card carries the same served balance on its second line (the phone's place for it)
        await expect(page.getByTestId('goal-reputation')).toHaveAttribute('data-value', '0')
        await expect(page.getByTestId('goal-reputation')).toHaveText(/^Reputation\s+0$/)

        const { code, city } = await findCarry(page)
        await buyHere(page, code)
        await sailAndSell(page, code, city)
        await expect(bar, 'a buy and a departure earn nothing').toHaveAttribute('data-value', '0')

        // sit on You while she sails, in the language under test
        if (lang === 'ko') await page.evaluate(() => localStorage.setItem('bv.locale', 'ko'))
        await page.goto('you')
        await ready(page)
        expect(await page.evaluate(() => document.documentElement.lang)).toBe(lang)
        await expect(page.getByTestId('you-reputation')).toContainText(words.name)
        await expect(page.getByTestId('you-reputation-balance')).toHaveAttribute('data-value', '0')
        await expect(page.getByTestId('you-reputation-today')).toHaveText(words.today(0))
        if (wide) await expect(bar).toHaveText(new RegExp(`^0\\s*${words.name}$`))
        await insideGlass()
        await expect(page.getByTestId('arrival-card')).toHaveCount(0)

        // she comes in and sells: one line on the card
        const card = page.getByTestId('arrival-card')
        await expect(card).toBeVisible({ timeout: 300_000 })
        const line = page.getByTestId('arrival-reputation')
        await expect(line).toHaveCount(1)
        const text = (await line.innerText()).trim()
        expect(text, 'the card line is the dictionary sentence').toMatch(words.earned)
        const earned = Number(text.match(words.earned)![1].replace(/,/g, ''))
        expect(Number(await line.getAttribute('data-reputation'))).toBe(earned)

        // FIXED FACTS. The balance was 0, so the top bar now reads what the card says was earned.
        await expect(bar).toHaveAttribute('data-value', String(earned))
        // 25 for the first landfall, 1 a 250 of the sale's profit (the card's own figure), and the miles (0 to 40).
        await expect(page.getByTestId('arrival-sale')).toHaveCount(1)
        const net = Number(await card.getAttribute('data-net'))
        expect(Number.isFinite(net)).toBe(true)
        const sale = Math.min(Math.floor(Math.max(net, 0) / 250), 120)
        const miles = earned - 25 - sale
        expect(miles, `earned ${earned} = 25 landfall + ${sale} for a profit of ${net} + miles`).toBeGreaterThanOrEqual(0)
        expect(miles).toBeLessThanOrEqual(40)
        // You: the same balance; today's capped earnings are everything but the landfall.
        await expect(page.getByTestId('you-reputation-balance')).toHaveAttribute('data-value', String(earned))
        await expect(page.getByTestId('you-reputation-today')).toHaveText(words.today(earned - 25))
        await insideGlass()
        const box = (await card.boundingBox())!
        expect(box.x).toBeGreaterThanOrEqual(0)
        expect(box.x + box.width).toBeLessThanOrEqual(size.width)
        console.log(`reputation ${size.width} ${lang}: card ${JSON.stringify((await card.innerText()).replace(/\s+/g, ' '))} · bar ${JSON.stringify(((await bar.textContent()) ?? '').replace(/\s+/g, ' '))}${wide ? '' : ' (not shown on a phone)'} · landfall 25 + sale ${sale} (profit ${net}) + miles ${miles}`)
      })
    })
  }
}
