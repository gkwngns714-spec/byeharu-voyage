import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { reachable, ready } from './appReady.fixture'
import { ARMADA_NAME, ARMADA_SISTERS, serveArmadaBattleWorld } from './armadaBattleWorld.fixture'
import { fightCountRadiusPx } from '../src/chart/fightRings'

// ═══════════════════════════════════════════════════════════════════════════════
// AN ARMADA'S BATTLE ON THE PAGE (0395, docs/ARMADA.md section 7, owner row 323: "with more than one fleet, max 6
// fleet - an armada").
// ═══════════════════════════════════════════════════════════════════════════════
// The world is tests/armadaBattleWorld.fixture.ts: the shipped image with attacks lit in a COPY, and one real battle
// that her armada of SIX (the owner's number) starts the moment the map first asks. Everything the page shows is the chain's own reads.
//   · THE RING IS BIGGER FOR AN ARMADA: seven fleets are there (her six and the ship set upon), and the ring is at
//     least the size the chart gives seven fleets, which is more than it gives the two a lone fleet's battle has.
//   · THE SHEET LISTS HER FLEETS: the attacker's side has her six fleets by their whole names; her own card says the
//     armada's name and her six fleets again.
//   · THE STANCE ACTS FOR ALL: the card says so beside the buttons, and one press of Flee is the stance the card reads.
//   · ONCE IT IS OVER each fleet has her share on the card.
//   · 390, 320 and 1280 px, English and Korean: nothing scrolls sideways, no name is cut, no word breaks inside.
// Run it: npm run build && npm run preview, then `npx playwright test map.armadaBattle.spec.ts`.
// Screenshots go to test-results/armada-battle (or ARMADA_BATTLE_SHOTS).
// ═══════════════════════════════════════════════════════════════════════════════

const SHOTS = process.env.ARMADA_BATTLE_SHOTS ? path.resolve(process.env.ARMADA_BATTLE_SHOTS) : path.resolve('test-results', 'armada-battle')
const PHONE = { width: 390, height: 844 }
const SMALL = { width: 320, height: 640 }
const WIDE = { width: 1280, height: 800 }
/** Her fleets in the battle, and every fleet in it (the ship set upon too). */
const HERS = ARMADA_SISTERS.length + 1
const THERE = HERS + 1

test.use({ deviceScaleFactor: 2 })
test.beforeAll(() => mkdirSync(SHOTS, { recursive: true }))

/** The map, open, with the armada's battle ringed. */
async function openMap(page: Page) {
  await serveArmadaBattleWorld(page)
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
  const ring = page.getByTestId('map-fight-ring').first()
  await expect(ring, 'the battle her armada starts is ringed').toBeVisible({ timeout: 90_000 })
  return ring
}

/** The ring's centre and radius on the glass, in CSS px. */
async function ringOnGlass(page: Page) {
  const box = (await page.getByTestId('map-fight-ring').first().locator('circle').first().boundingBox())!
  return { x: box.x + box.width / 2, y: box.y + box.height / 2, r: box.width / 2 }
}

/** The fight, opened from its ring. Seven fleets make a WIDE ring (52 px), and a wide ring leaves the harbour under its centre its own
 *  press (src/chart/fightRings.ts, fightTapWins): the press is on the open ground inside the ring, off the harbour. */
async function openFight(page: Page) {
  const g = await ringOnGlass(page)
  const sheet = page.getByTestId('fight-sheet')
  // just inside the rim, in each direction until one is clear of the harbour's own reach (a press that found the harbour is pressed again, which lets it go)
  for (const [dx, dy] of [[0, -0.93], [-0.93, 0], [0, 0.93], [0.93, 0], [-0.66, -0.66], [0.66, 0.66]] as const) {
    await page.mouse.click(g.x + dx * g.r, g.y + dy * g.r)
    await page.waitForTimeout(400)
    if (await sheet.isVisible().catch(() => false)) break
    await page.mouse.click(g.x + dx * g.r, g.y + dy * g.r)
    await page.waitForTimeout(300)
  }
  await expect(sheet, 'a press inside the ring opens the fight').toBeVisible()
  return sheet
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
      if ((el.textContent ?? '').includes('…')) out.push(`holds an ellipsis: "${(el.textContent ?? '').slice(0, 40)}"`)
    }
    if (document.documentElement.scrollWidth > document.documentElement.clientWidth) out.push('the page scrolls sideways')
    return out
  })
  expect(bad, label).toEqual([])
}

/** Her six fleets on the attacker's side and on her own card, by their whole names. Answers her first fleet's name. */
async function listsHerFleets(page: Page) {
  const side = page.getByTestId('fight-side-attacker').getByTestId('fight-side-fleet')
  await expect(side).toHaveCount(HERS)
  const names = await side.allTextContents()
  expect(names.slice(1), 'her sisters stand after the fleet that attacked, in the armada\'s order, whole').toEqual([...ARMADA_SISTERS])
  await expect(page.getByTestId('fight-side-defender').getByTestId('fight-side-fleet')).toHaveCount(1)
  const card = page.getByTestId('battle-card')
  await expect(card).toBeVisible({ timeout: 30_000 })
  const armada = page.getByTestId('battle-armada')
  await expect(armada).toHaveAttribute('data-fleets', String(HERS))
  await expect(page.getByTestId('battle-armada-name')).toHaveText(ARMADA_NAME)
  await expect(page.getByTestId('battle-armada-fleet')).toHaveText([names[0], ...ARMADA_SISTERS])
  await expect(page.getByTestId('battle-armada-row').first()).toHaveAttribute('data-lead', 'true')
  return names[0]
}

for (const size of [PHONE, WIDE]) {
  test.describe(`her armada's battle, at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size, locale: 'en-US' })

    test('the ring is the size of seven fleets; the sheet lists her six fleets; one Flee is the whole armada\'s; each fleet has her share at the end', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`)
      const ring = await openMap(page)

      // ── THE RING IS BIGGER FOR AN ARMADA ──
      await expect(ring).toHaveAttribute('data-mine', 'true')
      const rPx = Number(await ring.getAttribute('data-r-px'))
      expect(fightCountRadiusPx(THERE), 'seven fleets draw a bigger ring than the two of a lone fleet\'s battle').toBeGreaterThan(fightCountRadiusPx(2))
      expect(rPx, 'the ring is at least the size of seven fleets').toBeGreaterThanOrEqual(fightCountRadiusPx(THERE))
      const g = await ringOnGlass(page)
      expect(g.r * 2).toBeGreaterThanOrEqual(2 * fightCountRadiusPx(THERE) - 1)
      await page.screenshot({ path: path.join(SHOTS, `ring-${size.width}-en.png`) })

      // ── THE SHEET LISTS HER FLEETS ──
      const sheet = await openFight(page)
      await expect(sheet).toHaveAttribute('data-mine', 'true')
      await expect(page.getByTestId('fight-sheet-name-line')).toContainText(`${THERE} fleets`)
      await expect(page.getByTestId('fight-sheet-name-line')).toContainText('Your battle')
      await listsHerFleets(page)
      const card = page.getByTestId('battle-card')

      // ── THE STANCE ACTS FOR ALL ──
      expect(await card.getAttribute('data-status'), 'the battle is still being fought when the sheet opens (a round is 10 s here)').toBe('FIGHTING')
      await expect(page.getByTestId('battle-stance-all')).toContainText('Whole armada')
      await expect(card).toHaveAttribute('data-stance', 'FIGHT')
      await page.screenshot({ path: path.join(SHOTS, `fight-${size.width}-en.png`), fullPage: false })
      await page.getByTestId('battle-stance-FLEE').click()
      await expect(card, 'one press of Flee is the stance her card reads back from the server').toHaveAttribute('data-stance', 'FLEE', { timeout: 20_000 })
      await holdsItsWidth(page, `her armada's fight at ${size.width} px`)
      await page.getByTestId('battle-armada').scrollIntoViewIfNeeded()
      await page.screenshot({ path: path.join(SHOTS, `fight-flee-${size.width}-en.png`) })

      // ── ONCE IT IS OVER: each fleet's share, as the server counted it ──
      await expect.poll(async () => card.getAttribute('data-status'), { timeout: 150_000, message: 'the battle closes' }).not.toBe('FIGHTING')
      await expect(page.getByTestId('battle-armada-share')).toHaveCount(HERS)
      await expect(page.getByTestId('battle-armada-loot')).toHaveCount(HERS)
      await expect(page.getByTestId('battle-loot')).toBeVisible()
      await holdsItsWidth(page, `her armada's fight, closed, at ${size.width} px`)
      await page.getByTestId('battle-armada').scrollIntoViewIfNeeded()
      await page.screenshot({ path: path.join(SHOTS, `fight-closed-${size.width}-en.png`) })
    })
  })
}

for (const lang of ['ko-KR', 'en-US'] as const) {
  for (const size of lang === 'ko-KR' ? [PHONE, SMALL] : [SMALL]) {
    test.describe(`the words, ${lang} at ${size.width}×${size.height}`, () => {
      test.use({ viewport: size, locale: lang })

      test('the ring and her armada\'s open fight hold their width: every fleet\'s name whole, nothing cut, nothing sideways', async ({ page, request, baseURL }) => {
        test.setTimeout(360_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
        const ring = await openMap(page)
        expect(Number(await ring.getAttribute('data-r-px'))).toBeGreaterThanOrEqual(fightCountRadiusPx(THERE))
        const tag = `${size.width}-${lang.slice(0, 2)}`
        await page.screenshot({ path: path.join(SHOTS, `ring-${tag}.png`) })
        await openFight(page)
        await listsHerFleets(page)
        if (lang === 'ko-KR') {
          await expect(page.getByTestId('battle-armada')).toContainText('대함대')
          if ((await page.getByTestId('battle-card').getAttribute('data-status')) === 'FIGHTING') await expect(page.getByTestId('battle-stance-all')).toContainText('대함대 전체')
        }
        await holdsItsWidth(page, `her armada's fight at ${tag}`)
        await page.getByTestId('battle-armada').scrollIntoViewIfNeeded()
        await page.screenshot({ path: path.join(SHOTS, `fight-${tag}.png`) })
      })
    })
  }
}
