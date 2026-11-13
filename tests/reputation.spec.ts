import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { arrivalCard, LANDING_TEST_TIMEOUT_MS } from './arrivalWait.fixture'
import { buyHere, findCarry, sailAndSell } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// REPUTATION ON THE GLASS (migration 0352, slice R1 of docs/REPUTATION.md; owner row 317).
// A new company has 0 Reputation in the top bar. It buys at Lisbon, presses Sail & sell and sits on the You tab.
// When the fleet comes in and sells, the arrival card says `+N Reputation` (KO `평판 +N`), and N is held to fixed
// facts, all of them served: the top bar's figure went from 0 to N; N is 25 for the first landfall, 1 for each 250 of
// the sale's profit (the card's own figure) and the voyage's miles (at most 40); the You tab shows N and
// `Today N−25 / 600`, because a landfall is outside the day's cap. Phone and desktop, EN and KO.
// The voyage is driven in English (the trade fixtures read English words); the language is changed while she sails.
//
// A LEVEL CROSSED IS A MOMENT (migration 0356, slice R4). The same voyage crosses levels, and each crossing pays 10 x the
// level, once. FIXED FACTS, all served:
//   - at the quay the buy is turnover: if it makes Trading level L, the shell asks cmd.level_up once and the top bar reads
//     10 x (2 + ... + L) before she sails (0 when the buy crossed nothing). A buy still earns nothing by itself;
//   - a first arrival is one port reached, which is Exploration level 2: the card says `Exploration level 2 · +20 Reputation`
//     (KO `탐험 2레벨 · 평판 +20`), from the LEVEL_UP event and not from comparing two reads;
//   - the card's `+N Reputation` line is the arrival's own earnings; a level's gift stands on its level line. So the top
//     bar is what it read at the quay + N + every level line's gift;
//   - the Levels page prints the next level's gift beside each bar: `Next +30` (KO `다음 +30`) at Exploration level 2.
// THE WAIT: a near trip can take several real minutes, so the card is waited for 480 s inside a 900 s test, and what the
// page said is printed when it does not come.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ locale: 'en-US', deviceScaleFactor: 2 })

const SIZES = [
  { width: 320, height: 568 },
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

const WORDS = {
  en: {
    name: 'Reputation',
    earned: /^\+([\d,]+) Reputation$/,
    today: (a: number) => `Today ${a} / 600`,
    track: { trading: 'Trading', exploration: 'Exploration', combat: 'Combat' },
    level: (track: string, n: number, rep: number) => `${track} level ${n} · +${rep} Reputation`,
    next: (n: number) => `Next +${n}`,
  },
  ko: {
    name: '평판',
    earned: /^평판 \+([\d,]+)$/,
    today: (a: number) => `오늘 ${a} / 600`,
    track: { trading: '교역', exploration: '탐험', combat: '전투' },
    level: (track: string, n: number, rep: number) => `${track} ${n}레벨 · 평판 +${rep}`,
    next: (n: number) => `다음 +${n}`,
  },
} as const

/** THE WAIT FOR HER TO COME IN: a near trip can take several real minutes when the sea delays her, so the card is waited
 *  for 480 s; when it does not come, what the page says is printed (the top bar's figure, and the page's own words). */
async function landed(page: import('@playwright/test').Page, label: string): Promise<void> {
  try {
    await expect(page.getByTestId('arrival-card')).toBeVisible({ timeout: 480_000 })
  } catch (err) {
    const bar = await page.getByTestId('reputation').getAttribute('data-value').catch(() => null)
    const said = await page.locator('body').innerText().catch(() => '')
    console.log(`${label}: NO ARRIVAL CARD in 480 s. Reputation ${bar}; ${page.url()}; the page says ${JSON.stringify(said.replace(/\s+/g, ' ').slice(0, 700))}`)
    throw err
  }
}

/** 0356: what the crossings from level 1 to `level` give in all: 10 x (2 + ... + level). */
const giftsTo = (level: number) => 10 * ((level * (level + 1)) / 2 - 1)

for (const size of SIZES) {
  for (const lang of ['en', 'ko'] as const) {
    test.describe(`Reputation at ${size.width}×${size.height}, ${lang}`, () => {
      test.use({ viewport: size })

      test('a first voyage earns Reputation: the top bar, the arrival card and You agree', async ({ page, request, baseURL }) => {
        // the sea may delay any voyage: the wait and its arithmetic are tests/arrivalWait.fixture.ts
        test.setTimeout(LANDING_TEST_TIMEOUT_MS)
        expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}: run a preview (or set PLAYWRIGHT_BASE_URL)`).toBe(true)
        const words = WORDS[lang]
        // THE SEA MAY DELAY A NEAR TRIP BY MINUTES: at least 900 s for the whole test (never less than a longer one already set).
        test.setTimeout(Math.max(test.info().timeout, 900_000))
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
        // 0356: a buy and a departure earn nothing by themselves. The buy is turnover: the Trading level it made (the goal card's
        // own served figure) is paid once at the quay, 10 x each level crossed, and nothing else is.
        const tradingNow = async () => Number(/Trading (\d+)\//.exec((await page.getByTestId('goal-card').innerText()).replace(/\s+/g, ' '))?.[1] ?? Number.NaN)
        await expect
          .poll(async () => Number(await bar.getAttribute('data-value')) - giftsTo(await tradingNow()), { timeout: 60_000, message: 'at the quay the bar is not the gifts of her Trading level' })
          .toBe(0)
        const quay = Number(await bar.getAttribute('data-value'))
        const quayLevel = await tradingNow()

        // sit on You while she sails, in the language under test
        if (lang === 'ko') await page.evaluate(() => localStorage.setItem('bv.locale', 'ko'))
        await page.goto('you')
        await ready(page)
        expect(await page.evaluate(() => document.documentElement.lang)).toBe(lang)
        await expect(page.getByTestId('you-reputation')).toContainText(words.name)
        await expect(page.getByTestId('you-reputation-balance')).toHaveAttribute('data-value', String(quay))
        await expect(page.getByTestId('you-reputation-today'), 'a level gift is outside the day cap').toHaveText(words.today(0))
        if (wide) await expect(bar).toHaveText(new RegExp(`^${quay}\\s*${words.name}$`))
        await insideGlass()
        await expect(page.getByTestId('arrival-card')).toHaveCount(0)
        await landed(page, `reputation ${size.width} ${lang}`)

        // she comes in and sells: one line on the card
        const card = await arrivalCard(page, `Reputation at ${size.width}×${size.height}, ${lang}`)
        const line = page.getByTestId('arrival-reputation')
        await expect(line).toHaveCount(1)
        const text = (await line.innerText()).trim()
        expect(text, 'the card line is the dictionary sentence').toMatch(words.earned)
        const earned = Number(text.match(words.earned)![1].replace(/,/g, ''))
        expect(Number(await line.getAttribute('data-reputation'))).toBe(earned)

        // 0356: THE LEVEL LINES. A first arrival is one port reached: Exploration level 2, said from its LEVEL_UP event with its gift.
        const explore = page.locator('[data-testid="arrival-level"][data-track="exploration"]')
        await expect(explore).toHaveCount(1)
        await expect(explore).toHaveAttribute('data-level', '2')
        await expect(explore).toHaveAttribute('data-reputation', '20')
        await expect(explore).toHaveText(words.level(words.track.exploration, 2, 20))
        const levelGifts = async () => {
          let sum = 0
          for (const line of await page.getByTestId('arrival-level').all()) sum += Number(await line.getAttribute('data-reputation'))
          return sum
        }
        // FIXED FACTS. The top bar is what it read at the quay, what the card says the arrival earned, and every level line's gift
        // (a level the sale crossed is paid by the shell's one ask and joins the open card).
        await expect
          .poll(async () => Number(await bar.getAttribute('data-value')) - quay - earned - (await levelGifts()), { timeout: 30_000, message: 'the bar is not quay + earned + the level gifts on the card' })
          .toBe(0)
        const gifts = await levelGifts()
        for (const line of await page.getByTestId('arrival-level').all()) {
          const track = (await line.getAttribute('data-track')) as 'trading' | 'exploration' | 'combat'
          const level = Number(await line.getAttribute('data-level'))
          const rep = Number(await line.getAttribute('data-reputation'))
          expect((await line.innerText()).trim(), 'a level line is the dictionary sentence').toBe(words.level(words.track[track], level, rep))
          // the gift is 10 x each level crossed: from the level paid at the quay (Trading) or from 1 (a new house's other tracks)
          expect(rep, `${track} level ${level} gave ${rep}`).toBe(giftsTo(level) - (track === 'trading' ? giftsTo(quayLevel) : 0))
        }
        // 25 for the first landfall, 1 a 250 of the sale's profit (the card's own figure), and the miles (0 to 40).
        await expect(page.getByTestId('arrival-sale')).toHaveCount(1)
        const net = Number(await card.getAttribute('data-net'))
        expect(Number.isFinite(net)).toBe(true)
        const sale = Math.min(Math.floor(Math.max(net, 0) / 250), 120)
        const miles = earned - 25 - sale
        expect(miles, `earned ${earned} = 25 landfall + ${sale} for a profit of ${net} + miles`).toBeGreaterThanOrEqual(0)
        expect(miles).toBeLessThanOrEqual(40)
        // You: the same balance; today's capped earnings are everything but the landfall.
        await expect(page.getByTestId('you-reputation-balance')).toHaveAttribute('data-value', String(quay + earned + gifts))
        await expect(page.getByTestId('you-reputation-today')).toHaveText(words.today(earned - 25))
        await insideGlass()
        const box = (await card.boundingBox())!
        expect(box.x).toBeGreaterThanOrEqual(0)
        expect(box.x + box.width).toBeLessThanOrEqual(size.width)
        console.log(`reputation ${size.width} ${lang}: card ${JSON.stringify((await card.innerText()).replace(/\s+/g, ' '))} · bar ${JSON.stringify(((await bar.textContent()) ?? '').replace(/\s+/g, ' '))}${wide ? '' : ' (not shown on a phone)'} · quay ${quay} (Trading ${quayLevel}) + landfall 25 + sale ${sale} (profit ${net}) + miles ${miles} + level gifts ${gifts}`)
        await page.screenshot({ path: test.info().outputPath(`level-up-card-${size.width}-${lang}.png`) })

        // 0356: THE LEVELS PAGE prints the next level's gift beside each bar: 10 x (her level + 1), from the served gift.
        await page.goto('command')
        await ready(page)
        await page.getByTestId('goal-card').click()
        await expect(page.getByTestId('desk-levels').first()).toBeVisible({ timeout: 60_000 })
        for (const track of ['trading', 'exploration'] as const) {
          const row = page.getByTestId(`levels-${track}`).first()
          const level = Number((await row.innerText()).match(/\d+/)![0])
          const gift = row.getByTestId('levels-gift')
          await expect(gift).toHaveAttribute('data-value', String(10 * (level + 1)))
          await expect(gift).toHaveText(words.next(10 * (level + 1)))
        }
        await expect(page.getByTestId('levels-exploration').first().getByTestId('levels-gift')).toHaveText(words.next(30))
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), 'the Levels page scrolls sideways').toBe(true)
        await page.getByTestId('levels-exploration').first().scrollIntoViewIfNeeded()
        await page.screenshot({ path: test.info().outputPath(`levels-next-gift-${size.width}-${lang}.png`) })
      })
    })
  }
}
