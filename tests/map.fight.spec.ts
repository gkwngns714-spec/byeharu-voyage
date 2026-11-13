import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { reachable, ready } from './appReady.fixture'
import { FIGHT_OTHER_COMPANY, FIGHT_OTHER_FLEET, serveFightWorld, serveInstantFightWorld } from './fightWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A FIGHT ON THE MAP (0364, owner row 321: "i want a fight to be visible in map. in red circle surrounding all fleets
// ... by clicking that circle, like info i want to see the actual fight").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The world is tests/fightWorld.fixture.ts: the shipped image with attacks lit in a COPY, a round every 5 s, and one
// real battle that opens the moment the map first asks. Everything the page shows is the chain's own reads.
//   · THE RING is on the map, red, round its fleets (her own hull is inside it, in her own battle), under the harbours, hulls and
//     names in paint order, at least a touch target across, and it moves no name: every name on the sheet stands
//     where it stood, to the pixel, before and after the ring is there... which is what "the label planner's law is
//     not broken" means here, since the ring asks the planner for nothing.
//   · A PRESS on it opens the fight in a tray: both sides with their fleets (names whole) and a hull bar each, the
//     next round's countdown, and the ONE fight log. Somebody else's battle is watch-only: no stance button.
//   · THE LOG GROWS by a round while the tray is open, and says how it ended.
//   · THE RING GOES when the battle is over (the server keeps it a minute with the result; the fixture leaves 15 s).
//   · HER OWN battle opens her own card: the stance buttons are there.
//   · 390, 320 and 1280 px, English and Korean: nothing scrolls sideways, no name is cut, no word breaks inside.
// Run it: npm run build && npm run preview, then `npx playwright test map.fight.spec.ts`.
// Screenshots go to test-results/fight-rings (or FIGHT_SHOTS).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SHOTS = process.env.FIGHT_SHOTS ? path.resolve(process.env.FIGHT_SHOTS) : path.resolve('test-results', 'fight-rings')
const PHONE = { width: 390, height: 844 }
const SMALL = { width: 320, height: 640 }
const WIDE = { width: 1280, height: 800 }

test.use({ deviceScaleFactor: 2 })
test.beforeAll(() => mkdirSync(SHOTS, { recursive: true }))

/** The map, open, with the battle's ring on it. Answers the ring's circle on the glass. */
async function openMap(page: Page, mine = false) {
  await serveFightWorld(page, mine)
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
  const ring = page.getByTestId('map-fight-ring').first()
  await expect(ring, 'the battle the fixture opens is ringed').toBeVisible({ timeout: 90_000 })
  return ring
}

/** The ring's centre and radius on the glass, in CSS px. */
async function ringOnGlass(page: Page) {
  const box = (await page.getByTestId('map-fight-ring').first().locator('circle').first().boundingBox())!
  return { x: box.x + box.width / 2, y: box.y + box.height / 2, r: box.width / 2 }
}

/** No element of the sheet is wider than the sheet, no text is cut with an ellipsis, and nothing scrolls sideways. */
async function holdsItsWidth(page: Page, label: string) {
  const bad = await page.evaluate(() => {
    const sheet = document.querySelector('[data-testid="fight-sheet"]')
    if (!sheet) return ['no sheet']
    const out: string[] = []
    const edge = sheet.getBoundingClientRect()
    for (const el of sheet.querySelectorAll<HTMLElement>('*')) {
      const r = el.getBoundingClientRect()
      if (r.width === 0 || r.height === 0) continue
      if (r.right > edge.right + 1 || r.left < edge.left - 1) out.push(`outside the sheet: ${el.tagName} ${el.getAttribute('data-testid') ?? ''} "${(el.textContent ?? '').slice(0, 40)}"`)
      const cs = getComputedStyle(el)
      if (cs.textOverflow === 'ellipsis' && el.scrollWidth > el.clientWidth + 1) out.push(`cut with an ellipsis: "${(el.textContent ?? '').slice(0, 40)}"`)
      if (cs.wordBreak === 'break-all') out.push(`may break inside a word: "${(el.textContent ?? '').slice(0, 40)}"`)
    }
    if (document.documentElement.scrollWidth > document.documentElement.clientWidth) out.push('the page scrolls sideways')
    return out
  })
  expect(bad, label).toEqual([])
}

for (const size of [PHONE, WIDE]) {
  test.describe(`a battle somebody else fights, at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size, locale: 'en-US' })

    test('the ring is on the map round the fleets; a press opens the fight; the log grows a round; the ring goes when it ends', async ({ page, request, baseURL }) => {
      test.setTimeout(420_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`)
      const ring = await openMap(page)

      // ── THE RING ──
      const g = await ringOnGlass(page)
      expect(g.r * 2, 'the ring is at least a touch target across').toBeGreaterThanOrEqual(44 - 0.5)
      expect(Number(await ring.getAttribute('data-r-px'))).toBeGreaterThanOrEqual(22)
      await expect(ring).not.toHaveAttribute('data-mine', /.+/)
      // red: the palette's danger colour, as the browser resolved it
      const ink = await ring.locator('circle').nth(1).evaluate((el) => {
        const probe = document.createElement('span')
        probe.style.color = 'var(--color-danger)'
        document.body.appendChild(probe)
        const danger = getComputedStyle(probe).color
        probe.remove()
        return { stroke: getComputedStyle(el).stroke, danger }
      })
      expect(ink.stroke).toBe(ink.danger)
      // (the two fleets are another company's, which no chart draws, and a cargo ship, which the shipped world's sea does
      // not serve while its merchants are dark: the ring ROUND a drawn hull is the next describe's, her own battle)
      expect(g.x - g.r).toBeGreaterThanOrEqual(0)
      expect(g.x + g.r).toBeLessThanOrEqual(size.width)
      // paint order: the ring is under the harbours, the hulls and every name
      const order = await page.evaluate(() => {
        const ringEl = document.querySelector('[data-testid="map-fight-rings"]')!
        const after = (sel: string) => {
          const el = ringEl.parentElement!.querySelector(sel) ?? document.querySelector(sel)
          return el ? (ringEl.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0 : null
        }
        return { ports: after('[data-testid="map-ports"]'), labels: after('[data-testid="map-labels"]') }
      })
      expect(order).toEqual({ ports: true, labels: true })
      await page.screenshot({ path: path.join(SHOTS, `ring-${size.width}-en.png`) })

      // ── A PRESS OPENS THE FIGHT ──
      await page.mouse.click(g.x, g.y)
      const sheet = page.getByTestId('fight-sheet')
      await expect(sheet).toBeVisible()
      await expect(sheet).not.toHaveAttribute('data-mine', /.+/)
      await expect(page.getByTestId('fight-sheet-name-line')).toContainText('2 fleets')
      await expect(page.getByTestId('fight-sheet-name-line')).toContainText('Watching')
      // both sides, their fleets by their whole names, a hull bar each
      const attacker = page.getByTestId('fight-side-attacker')
      await expect(attacker.getByTestId('fight-side-fleet')).toHaveText(FIGHT_OTHER_FLEET)
      await expect(attacker).toContainText(FIGHT_OTHER_COMPANY)
      await expect(page.getByTestId('fight-side-defender').getByTestId('fight-side-row')).toHaveCount(1)
      await expect(page.getByTestId('fight-side-defender')).toContainText('Cargo ship')
      const card = page.getByTestId('battle-card')
      await expect(card).toBeVisible({ timeout: 30_000 })
      await expect(card).toHaveAttribute('data-watch', 'true')
      await expect(page.getByTestId('fight-side-hull')).toHaveCount(2)
      // watch-only: no stance button, no loot
      await expect(page.locator('[data-testid^="battle-stance-"]')).toHaveCount(0)
      await expect(page.getByTestId('battle-loot')).toHaveCount(0)
      // the next round's countdown runs
      if ((await card.getAttribute('data-status')) === 'FIGHTING') await expect(page.getByTestId('battle-clock')).toBeVisible()
      await holdsItsWidth(page, `the fight sheet at ${size.width} px`)

      // ── THE LOG GROWS BY A ROUND ──
      const log = page.getByTestId('fight-log')
      await expect(log).toHaveAttribute('data-watch', 'true')
      const rounds = async () => Number(await log.getAttribute('data-rounds'))
      // HOW THE FIGHT GOES IS THE WORLD'S DICE (each built world has its own): it may be over before a round is fought (they stood off, or one slipped away). So: a
      // first round is shown, OR the battle is over with none; and where a round is shown, it names the two sides.
      const fightingNow = async () => (await card.getAttribute('data-status')) === 'FIGHTING'
      await expect.poll(async () => (await rounds()) >= 1 || !(await fightingNow()), { timeout: 40_000, message: 'a first round is fought and shown, or the fight ended before one' }).toBe(true)
      const seen = await rounds()
      await page.screenshot({ path: path.join(SHOTS, `fight-${size.width}-en.png`) })
      if (seen >= 1) {
        await expect(page.getByTestId('fight-log-you').first()).toContainText('Attacker')
        await expect(page.getByTestId('fight-log-them').first()).toContainText('Defender')
      }
      if ((await card.getAttribute('data-status')) === 'FIGHTING') {
        await expect
          .poll(async () => (await rounds()) > seen || (await card.getAttribute('data-status')) !== 'FIGHTING', { timeout: 40_000, message: 'the log grows by a round, or the fight ends in that round' })
          .toBe(true)
      }

      // ── IT ENDS: the result is told, and the ring goes ──
      await expect(card).not.toHaveAttribute('data-status', 'FIGHTING', { timeout: 90_000 })
      await expect(page.getByTestId('fight-log-result')).toBeVisible()
      await expect(page.getByTestId('battle-clock')).toHaveCount(0)
      await page.screenshot({ path: path.join(SHOTS, `fight-over-${size.width}-en.png`) })
      await expect(page.getByTestId('map-fight-ring'), 'the ring leaves the map after the battle ends').toHaveCount(0, { timeout: 90_000 })
      // the result is still there to read for the one who was watching
      await expect(page.getByTestId('fight-log-result')).toBeVisible()
      await holdsItsWidth(page, `the finished fight at ${size.width} px`)
    })
  })
}

test.describe('the ring moves no name', () => {
  test.use({ viewport: WIDE, locale: 'en-US' })

  test('every name on the sheet stands where it stood before the ring was there', async ({ page, request, baseURL }) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await serveFightWorld(page)
    await page.goto('map')
    await ready(page)
    await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
    const names = () =>
      page.evaluate(() =>
        [...document.querySelectorAll('[data-testid="map-labels"] text')].map((t) => {
          const b = t.getBoundingClientRect()
          return `${t.textContent}@${Math.round(b.x)},${Math.round(b.y)}`
        }),
      )
    await expect(page.getByTestId('map-fight-ring').first()).toBeVisible({ timeout: 90_000 })
    const withRing = await names()
    expect(withRing.length).toBeGreaterThan(3)
    // the battle ends and the ring goes: the same names in the same places
    await expect(page.getByTestId('map-fight-ring')).toHaveCount(0, { timeout: 180_000 })
    const without = await names()
    const place = (rows: string[]) => new Map(rows.map((r) => [r.split('@')[0], r.split('@')[1]]))
    const a = place(withRing)
    const b = place(without)
    // a harbour's or a sea's name that is on the sheet both times has not moved (a fleet's own name follows her hull)
    let same = 0
    for (const [name, at] of a) {
      if (!b.has(name)) continue
      if (b.get(name) === at) same += 1
    }
    expect(same, `names with the ring: ${withRing.length}, without: ${without.length}`).toBeGreaterThanOrEqual(Math.min(a.size, b.size) - 2)
  })
})

for (const size of [PHONE, WIDE]) {
  test.describe(`her own battle, at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size, locale: 'en-US' })

    test('the ring goes round her fleet and says it is hers; a press opens her own card with the stance buttons', async ({ page, request, baseURL }) => {
      test.setTimeout(300_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      const ring = await openMap(page, true)
      await expect(ring).toHaveAttribute('data-mine', 'true')
      // HER HULL IS INSIDE THE RING, with air to spare (she lies a fifth of a degree from the ship she set upon; the
      // world's read of her fleets lands on its own beat, so it is asked until she is drawn at her anchor)
      const inside = async () => {
        const g = await ringOnGlass(page)
        return page.evaluate(({ x, y, r }) => {
          let n = 0
          for (const el of document.querySelectorAll('[data-fleet-heading]')) {
            const b = el.getBoundingClientRect()
            if (Math.hypot(b.x + b.width / 2 - x, b.y + b.height / 2 - y) <= r - 6) n += 1
          }
          return n
        }, g)
      }
      await expect.poll(inside, { timeout: 60_000, message: 'her hull stands inside the ring' }).toBe(1)
      await page.screenshot({ path: path.join(SHOTS, `ring-mine-${size.width}-en.png`) })
      const g = await ringOnGlass(page)
      // a press ON HER HULL inside the ring opens the fight (the ring is her battle's target, and she is in it)
      await page.mouse.click(g.x, g.y)
      const sheet = page.getByTestId('fight-sheet')
      await expect(sheet).toBeVisible()
      await expect(sheet).toHaveAttribute('data-mine', 'true')
      await expect(page.getByTestId('fight-sheet-name-line')).toContainText('Your battle')
      const card = page.getByTestId('battle-card')
      await expect(card).toBeVisible({ timeout: 30_000 })
      await expect(card).not.toHaveAttribute('data-watch', /.+/)
      if ((await card.getAttribute('data-status')) === 'FIGHTING') {
        await expect(page.getByTestId('battle-stance-FIGHT')).toBeVisible()
        await expect(page.getByTestId('battle-stance-FLEE')).toBeVisible()
      }
      await page.screenshot({ path: path.join(SHOTS, `fight-mine-${size.width}-en.png`) })
      await holdsItsWidth(page, `her own fight at ${size.width} px`)
    })
  })
}

for (const lang of ['ko-KR', 'en-US'] as const) {
  for (const size of lang === 'ko-KR' ? [PHONE, SMALL, WIDE] : [SMALL]) {
    test.describe(`the words, ${lang} at ${size.width}×${size.height}`, () => {
      test.use({ viewport: size, locale: lang })

      test('the ring and the open fight hold their width: nothing cut, nothing sideways', async ({ page, request, baseURL }) => {
        test.setTimeout(300_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
        await openMap(page)
        const tag = `${size.width}-${lang.slice(0, 2)}`
        await page.screenshot({ path: path.join(SHOTS, `ring-${tag}.png`) })
        const g = await ringOnGlass(page)
        await page.mouse.click(g.x, g.y)
        await expect(page.getByTestId('fight-sheet')).toBeVisible()
        await expect(page.getByTestId('fight-side-attacker').getByTestId('fight-side-fleet')).toHaveText(FIGHT_OTHER_FLEET)
        await expect(page.getByTestId('battle-card')).toBeVisible({ timeout: 30_000 })
        // a first round, or a fight that ended before one: the dice are the world's own
        const shown = async () => Number(await page.getByTestId('fight-log').getAttribute('data-rounds'))
        await expect.poll(async () => (await shown()) >= 1 || (await page.getByTestId('battle-card').getAttribute('data-status')) !== 'FIGHTING', { timeout: 40_000 }).toBe(true)
        if (lang === 'ko-KR') {
          await expect(page.getByTestId('fight-sheet-name-line')).toContainText('관전 중')
          if ((await shown()) >= 1) await expect(page.getByTestId('fight-log-you').first()).toContainText('공격 측')
        }
        await page.screenshot({ path: path.join(SHOTS, `fight-${tag}.png`) })
        await holdsItsWidth(page, `the fight sheet, ${lang} at ${size.width} px`)
      })
    })
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FIGHTS A PLAYER MEETS TODAY: HER OWN RAID, AND THE NAVY AGAINST PIRATES (0364's second half). Both are settled in
// an instant, so the ring appears with the fight already over and a press opens the WHOLE log with its result. The
// worlds are tests/fightWorld.fixture.ts `instantFightWorld`: a real raid day on her own voyage (the real settle, the
// real fight), and a real `public.navy_fight`. The ring stays 5 minutes (proof 66 holds the clock); here it is still on
// the map after the log has been read.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

async function openInstant(page: Page, kind: 'raid' | 'navy') {
  await serveInstantFightWorld(page, kind)
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
  const ring = page.locator(`[data-testid="map-fight-ring"][data-kind="${kind === 'raid' ? 'RAID' : 'NAVY'}"]`).first()
  await expect(ring, `the ${kind}'s ring is on the map`).toBeVisible({ timeout: 90_000 })
  return ring
}

/** Press the ring: its centre, or, if a city's name lies on the centre (a name is still the city), the open water of the disc. */
async function pressRing(page: Page) {
  const g = await ringOnGlass(page)
  for (const [dx, dy] of [[0, 0], [-0.6, 0], [0, 0.6], [0, -0.6], [0.6, 0], [-0.45, 0.45], [-0.45, -0.45]] as const) {
    await page.mouse.click(g.x + dx * g.r, g.y + dy * g.r)
    if (await page.getByTestId('fight-sheet').isVisible().catch(() => false)) return
    // whatever that press opened (a city, a hull), close it and try the next point of the disc
    await page.keyboard.press('Escape')
    const close = page.locator('[data-tray-mode] button[aria-label]').first()
    if (await close.isVisible().catch(() => false)) await close.click().catch(() => {})
  }
  await expect(page.getByTestId('fight-sheet'), 'a press inside the ring opens the fight').toBeVisible()
}

for (const size of [PHONE, WIDE]) {
  test.describe(`her own raid, at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size, locale: 'en-US' })

    test('a raid day settles while she is at sea: the ring is where it happened, and a press opens that raid with its result and what it cost', async ({ page, request, baseURL }) => {
      test.setTimeout(300_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      const ring = await openInstant(page, 'raid')
      await expect(ring).toHaveAttribute('data-mine', 'true')
      await expect(ring).not.toHaveAttribute('data-over', /.+/)
      const g = await ringOnGlass(page)
      expect(g.r * 2).toBeGreaterThanOrEqual(44 - 0.5)
      await page.screenshot({ path: path.join(SHOTS, `ring-raid-${size.width}-en.png`) })
      await pressRing(page)
      const sheet = page.getByTestId('fight-sheet')
      await expect(sheet).toHaveAttribute('data-kind', 'RAID')
      await expect(page.getByTestId('fight-sheet-name')).toHaveText('Raid')
      // the raiders set upon her: they are the attacker, her fleet the defender, a hull bar each
      await expect(page.getByTestId('fight-side-attacker')).toContainText('Raiders')
      await expect(page.getByTestId('fight-side-defender').getByTestId('fight-side-fleet')).toHaveCount(1)
      await expect(page.getByTestId('fight-side-hull')).toHaveCount(2)
      // the whole log, from her deck, with its result and the day's cost; no clock, no stance, nothing is asked again
      const log = page.getByTestId('fight-log')
      await expect(log).toBeVisible()
      await expect(log).toHaveAttribute('data-deck', 'raided')
      await expect(log).not.toHaveAttribute('data-end', 'OPEN')
      await expect(page.getByTestId('fight-log-result')).toBeVisible()
      await expect(page.getByTestId('fight-log-lost')).toBeVisible()
      await expect(page.getByTestId('battle-clock')).toHaveCount(0)
      await expect(page.locator('[data-testid^="battle-stance-"]')).toHaveCount(0)
      await page.screenshot({ path: path.join(SHOTS, `fight-raid-${size.width}-en.png`) })
      await holdsItsWidth(page, `her raid at ${size.width} px`)
      // the ring is still on the map: it stays 5 minutes from the day's instant
      await expect(page.locator('[data-testid="map-fight-ring"][data-kind="RAID"]').first()).toBeAttached()
    })
  })

  test.describe(`the navy against pirates, at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size, locale: 'en-US' })

    test('a navy ship fights a pirate ship: every player sees the ring, and a press opens the actual fight, watch-only', async ({ page, request, baseURL }) => {
      test.setTimeout(300_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      const ring = await openInstant(page, 'navy')
      await expect(ring).not.toHaveAttribute('data-mine', /.+/)
      await page.screenshot({ path: path.join(SHOTS, `ring-navy-${size.width}-en.png`) })
      await pressRing(page)
      const sheet = page.getByTestId('fight-sheet')
      await expect(sheet).toHaveAttribute('data-kind', 'NAVY')
      await expect(page.getByTestId('fight-sheet-name')).toHaveText('Navy fight')
      await expect(page.getByTestId('fight-sheet-name-line')).toContainText('Watching')
      await expect(page.getByTestId('fight-side-attacker')).toContainText('Navy ship')
      await expect(page.getByTestId('fight-side-defender')).toContainText('Pirate ship')
      await expect(page.getByTestId('fight-side-hull')).toHaveCount(2)
      const log = page.getByTestId('fight-log')
      await expect(log).toBeVisible()
      await expect(log).toHaveAttribute('data-watch', 'true')
      await expect(log).toHaveAttribute('data-deck', 'attacker')
      await expect(page.getByTestId('fight-log-result')).toBeVisible()
      expect(Number(await log.getAttribute('data-rounds'))).toBeGreaterThanOrEqual(0)
      await expect(page.locator('[data-testid^="battle-stance-"]')).toHaveCount(0)
      await expect(page.getByTestId('battle-loot')).toHaveCount(0)
      await page.screenshot({ path: path.join(SHOTS, `fight-navy-${size.width}-en.png`) })
      await holdsItsWidth(page, `the navy fight at ${size.width} px`)
    })
  })
}

for (const kind of ['raid', 'navy'] as const) {
  for (const [lang, size] of [['ko-KR', PHONE], ['ko-KR', SMALL], ['en-US', SMALL]] as const) {
    test.describe(`the words of a ${kind}, ${lang} at ${size.width}×${size.height}`, () => {
      test.use({ viewport: size, locale: lang })

      test('the open fight holds its width: nothing cut, nothing sideways', async ({ page, request, baseURL }) => {
        test.setTimeout(300_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
        await openInstant(page, kind)
        const tag = `${kind}-${size.width}-${lang.slice(0, 2)}`
        await page.screenshot({ path: path.join(SHOTS, `ring-${tag}.png`) })
        await pressRing(page)
        if (lang === 'ko-KR') await expect(page.getByTestId('fight-sheet-name')).toHaveText(kind === 'raid' ? '습격' : '해군 교전')
        await expect(page.getByTestId('fight-log-result')).toBeVisible()
        await page.screenshot({ path: path.join(SHOTS, `fight-${tag}.png`) })
        await holdsItsWidth(page, `the ${kind}, ${lang} at ${size.width} px`)
      })
    })
  }
}
