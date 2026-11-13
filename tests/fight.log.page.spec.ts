import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { OLD_ROUNDS, serveRaidWorld } from './raidWorld.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FIGHT LOG AND THE STANDING ORDER ON THE GLASS (migration 0353, slices C1 + C2 of docs/COMBAT_LOG.md; owner row 315).
// One world with ONE RAID OF FIXED FACTS (tests/raidWorld.fixture.ts: a barca under Flee, six rounds, hit twice in the
// sixth for 68, away). The spec drives the real page:
//   1. the fleet's page draws the order's picker (Fight / Flee / Pay), with the server's read beside it;
//   2. she is given Flee through the real door, and (in this world) sails a 30-second passage on which the raid falls;
//   3. the arrival card says one line for the raid, and Log unfolds the log inside the card;
//   4. History hangs the same log under its day, to the figure; an OLD report beside it (sentences, no log) draws
//      its sentences as it always did;
//   5. nothing scrolls sideways, on a phone (390), a small phone (320) and a desktop (1280), in English and Korean.
// And the world as it ships (orders dark) draws no picker at all.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ locale: 'en-US', deviceScaleFactor: 2 })

const RUNS = [
  { width: 390, height: 844, lang: 'en' },
  { width: 390, height: 844, lang: 'ko' },
  { width: 1280, height: 800, lang: 'en' },
  { width: 1280, height: 800, lang: 'ko' },
  { width: 320, height: 640, lang: 'en' },
] as const

const X = '▮'
const O = '▯'
const WORDS = {
  en: {
    orders: ['Fight', 'Flee', 'Pay'], nothing: 'Empty hold', noGuns: 'No guns', slip: ['Poor', 'Fair', 'Good'],
    raid: 'Raid: Fled · Hull −17%', log: 'Log',
    foe: 'Raid · 1 Şebek (xebec) · 50 crew', order: 'Order Flee · They saw first',
    range: ['Long', 'Long', 'Long', 'Medium', 'Medium', 'Close'], you: 'You Run · Slip 6%', miss: 'Them 0/2', hit: 'Them 2/2 −68', foeBar: 'Foe',
    result: 'Result Fled, round 6', lost: 'Lost Hull −68 (17%) · Crew 0 · Cargo 0', ship: 'Gaivota Hull 400 → 332',
  },
  ko: {
    orders: ['전투', '도주', '지불'], nothing: '화물 없음', noGuns: '포 없음', slip: ['낮음', '보통', '높음'],
    raid: '습격: 도주 성공 · 선체 −17%', log: '기록',
    foe: '습격 · Şebek (xebec) 1척 · 선원 50', order: '명령 도주 · 먼저 들킴',
    range: ['원거리', '원거리', '원거리', '중거리', '중거리', '근거리'], you: '아군 도주 중 · 이탈 6%', miss: '적 0/2', hit: '적 2/2 −68', foeBar: '적',
    result: '결과 도주 성공, 6라운드', lost: '손실 선체 −68 (17%) · 선원 0 · 화물 0', ship: 'Gaivota 선체 400 → 332',
  },
} as const

const flat = (s: string) => s.replace(/\s+/g, ' ').trim()
/** A picture kept with the run (the report's attachments): what the player sees at this size, in this language. */
async function shot(of: { screenshot: (o: { path: string }) => Promise<Buffer> }, file: string): Promise<string> {
  await of.screenshot({ path: file })
  return file
}
const noSideways = async (page: Page, what: string) =>
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `${what}: the page scrolls sideways`).toBe(true)

/** Open the report in History whose tray holds `testid`; the tray stays open. */
async function openReport(page: Page, testid: string) {
  const rows = page.getByTestId('ledger-row')
  await expect(rows.first()).toBeVisible()
  const n = await rows.count()
  for (let i = 0; i < n; i++) {
    await rows.nth(i).click()
    const tray = page.getByTestId('ledger-report')
    if (await tray.isVisible().catch(() => false)) {
      if ((await tray.getByTestId(testid).count()) > 0) return tray
    }
    await page.keyboard.press('Escape')
  }
  throw new Error(`no report in History holds ${testid}`)
}

for (const run of RUNS) {
  test.describe(`the fight log at ${run.width}×${run.height}, ${run.lang}`, () => {
    test.use({ viewport: { width: run.width, height: run.height } })

    test('the picker takes Flee, the raid lands on the arrival card, History draws the log and an old report its sentences', async ({ page, request, baseURL }, testInfo) => {
      test.setTimeout(600_000)
      expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}: run a preview (or set PLAYWRIGHT_BASE_URL)`).toBe(true)
      const w = WORDS[run.lang]
      await serveRaidWorld(page)
      if (run.lang === 'ko') await page.addInitScript(() => localStorage.setItem('bv.locale', 'ko'))
      await page.goto('fleets')
      await ready(page)
      expect(await page.evaluate(() => document.documentElement.lang)).toBe(run.lang)

      // 1. THE PICKER, on the fleet's page: her order (Fight: she has none), and the server's read beside it
      await page.getByTestId('fleet-row').first().click()
      await expect(page.getByTestId('fleet-page')).toBeVisible()
      const picker = page.getByTestId('raid-order')
      await expect(picker).toBeVisible()
      await expect(picker).toHaveAttribute('data-order', 'FIGHT')
      expect([await page.getByTestId('raid-order-FIGHT').innerText(), await page.getByTestId('raid-order-FLEE').innerText(), await page.getByTestId('raid-order-PAY').innerText()].map(flat)).toEqual([...w.orders])
      await expect(page.getByTestId('raid-order-pay')).toHaveText(w.nothing)   // an empty hold: Pay would cost nothing, and would be refused
      await expect(page.getByTestId('raid-order-pay')).toHaveAttribute('data-pay', '0')
      await expect(page.getByTestId('raid-order-noguns')).toHaveText(w.noGuns)   // the founding barca carries no gun
      const slip = (await page.getByTestId('raid-order-slip').getAttribute('data-word'))!
      expect(['poor', 'fair', 'good']).toContain(slip)
      await expect(page.getByTestId('raid-order-slip')).toHaveText(w.slip[['poor', 'fair', 'good'].indexOf(slip)])
      await expect(page.getByTestId('raid-order-foe')).toHaveAttribute('data-word', /^(weaker|even|stronger|far_stronger)$/)
      const box = (await picker.boundingBox())!
      expect(box.x).toBeGreaterThanOrEqual(0)
      expect(box.x + box.width, 'the picker stands inside the glass').toBeLessThanOrEqual(run.width + 0.5)
      await noSideways(page, 'the fleet page')
      await testInfo.attach(`picker-${run.width}-${run.lang}`, { path: await shot(picker, testInfo.outputPath(`picker-${run.width}-${run.lang}.png`)) })

      // 2. FLEE, through the real door. In this world the order sends her on a 30-second passage with one raid on it.
      await page.getByTestId('raid-order-FLEE').click()
      await expect(picker).toHaveAttribute('data-order', 'FLEE')
      await page.keyboard.press('Escape')

      // 3. THE ARRIVAL CARD: one line for the raid, and the log unfolds inside the card
      const card = page.getByTestId('arrival-card')
      await expect(card).toBeVisible({ timeout: 300_000 })
      await expect(page.getByTestId('arrival-raid')).toHaveCount(1)
      await expect(page.getByTestId('arrival-raid')).toHaveAttribute('data-end', 'FLED')
      expect(flat(await page.getByTestId('arrival-raid').innerText())).toBe(`${w.raid} ${w.log}`)
      await page.getByTestId('arrival-raid-log').click()
      const onCard = card.getByTestId('fight-log')
      await expect(onCard).toBeVisible()
      // the lines come one at a time and end with the result
      await expect(onCard.getByTestId('fight-log-round')).toHaveCount(6, { timeout: 30_000 })
      await expect(onCard.getByTestId('fight-log-result')).toHaveText(w.result, { timeout: 30_000 })
      const cardBox = (await card.boundingBox())!
      expect(cardBox.x).toBeGreaterThanOrEqual(0)
      expect(cardBox.x + cardBox.width, 'the card stands inside the glass').toBeLessThanOrEqual(run.width + 0.5)
      expect(await onCard.evaluate((el) => el.scrollWidth <= el.clientWidth + 1), 'the log on the card scrolls sideways').toBe(true)
      await noSideways(page, 'the arrival card')
      console.log(`fight log ${run.width} ${run.lang}: card ${JSON.stringify(flat(await card.innerText()))}`)
      await testInfo.attach(`card-${run.width}-${run.lang}`, { path: await shot(card, testInfo.outputPath(`card-${run.width}-${run.lang}.png`)) })
      await page.getByTestId('arrival-close').click()
      await expect(card).toHaveCount(0)

      // 4. HISTORY: the same raid under its day, to the figure
      await page.goto('ledger')
      await ready(page)
      const tray = await openReport(page, 'fight-log')
      const log = tray.getByTestId('fight-log')
      await expect(log).toHaveAttribute('data-end', 'FLED')
      await expect(log).toHaveAttribute('data-order', 'FLEE')
      await expect(log).toHaveAttribute('data-rounds', '6')
      await expect(tray.getByTestId('battle-report'), 'a fight with a log draws its numbers, not its sentences').toHaveCount(0)
      await expect(log.getByTestId('fight-log-foe')).toHaveText(w.foe)
      await expect(log.getByTestId('fight-log-order')).toHaveText(w.order)
      const rounds = log.getByTestId('fight-log-round')
      await expect(rounds).toHaveCount(6)   // a record: the whole log stands at once
      for (let i = 0; i < 6; i++) {
        const r = rounds.nth(i)
        const text = flat(await r.innerText())
        expect(text.startsWith(`${i + 1} ${w.range[i]} `), `round ${i + 1} reads: ${text}`).toBe(true)
        expect(flat(await r.getByTestId('fight-log-you').innerText())).toBe(w.you)
        expect(flat(await r.getByTestId('fight-log-them').innerText())).toBe(i === 5 ? w.hit : w.miss)
        // the bars: her hull left (100 % until the sixth round's two hits, then 83 %), theirs untouched
        const hull = r.getByTestId('fight-log-hull')
        const pct = i === 5 ? 83 : 100
        await expect(hull).toHaveAttribute('data-pct', String(pct))
        const drawn = flat(await hull.innerText())
        const five = `${X.repeat(i === 5 ? 4 : 5)}${O.repeat(i === 5 ? 1 : 0)} ${pct}%`
        const ten = `${X.repeat(i === 5 ? 8 : 10)}${O.repeat(i === 5 ? 2 : 0)} ${pct}%`
        expect([five, ten], `round ${i + 1}: her bar reads ${drawn}`).toContain(drawn)
        if (run.width <= 390) expect(drawn, 'a phone draws the five-cell bar').toBe(five)
        await expect(r.getByTestId('fight-log-foe-hull')).toHaveAttribute('data-pct', '100')
      }
      await expect(log.getByTestId('fight-log-board')).toHaveCount(0)
      await expect(log.getByTestId('fight-log-result')).toHaveText(w.result)
      await expect(log.getByTestId('fight-log-lost')).toHaveText(w.lost)
      await expect(log.getByTestId('fight-log-ship')).toHaveText(w.ship)
      expect(await log.evaluate((el) => el.scrollWidth <= el.clientWidth + 1), 'the log scrolls sideways').toBe(true)
      const logBox = (await log.boundingBox())!
      expect(logBox.x).toBeGreaterThanOrEqual(0)
      expect(logBox.x + logBox.width, 'the log stands inside the glass').toBeLessThanOrEqual(run.width + 0.5)
      await noSideways(page, 'History, the log open')
      console.log(`fight log ${run.width} ${run.lang}: history ${JSON.stringify(flat(await log.innerText()))}`)
      await testInfo.attach(`history-${run.width}-${run.lang}`, { path: await shot(page, testInfo.outputPath(`history-${run.width}-${run.lang}.png`)) })
      await page.keyboard.press('Escape')

      // an OLD report (before 0353: sentences, no log) draws its sentences, as it always did
      const old = await openReport(page, 'battle-report')
      await expect(old.getByTestId('fight-log')).toHaveCount(0)
      expect((await old.getByTestId('battle-report').locator('li').allInnerTexts()).map(flat)).toEqual(OLD_ROUNDS)
      await noSideways(page, 'History, an old report open')
    })
  })
}

// 0371 lit standing orders in the shipped world (tests/raid.order.lit.spec.ts drives that picker). The dark page is still proven, on a copy of the image with the switch
// set back: what a rollback of 0371 would show.
test.describe('a world set dark (before 0371, and after its rollback): standing orders are off', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('the fleet page draws no order picker', async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}: run a preview (or set PLAYWRIGHT_BASE_URL)`).toBe(true)
    await serveWorldImage(
      page,
      await patchedWorldImage('raid-orders-dark', async (pg) => {
        await pg.exec(`update public.world_config set value = 'false'::jsonb where key = 'raid_orders_enabled'`)
      }),
    )
    await page.goto('fleets')
    await ready(page)
    await page.getByTestId('fleet-row').first().click()
    await expect(page.getByTestId('fleet-fold')).toBeVisible()
    await expect(page.getByTestId('fleet-command')).toBeVisible()
    // the read has answered {on: false} by now: give it a beat, then hold that nothing was drawn
    await page.waitForTimeout(1500)
    await expect(page.getByTestId('raid-order')).toHaveCount(0)
  })
})
