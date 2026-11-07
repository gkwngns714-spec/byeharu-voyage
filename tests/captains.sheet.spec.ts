import { test, expect, type Page } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'
import { readTray, trayViolations } from './trayLaw.fixture'
import { SHEET_CAPTAINS, SHEET_STATS, serveCaptainWorld } from './captainSheet.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A CAPTAIN HAS A SHEET — the five lines on her card, and the Power line of a hull (0337, docs/WORLD_POWERS.md 2.3, 2.4; owner row 288)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"we also need levels and stats for characters as well as ships ... these factors will be the power and ability of each company / ships. captains should also
// have stats"* (owner, 2026-11-05.) `world.captain_stats` serves a captain's SHEET (five stats, each her level in its track and the parts she adds, every figure and
// every line the server's); the card prints it under her grade, job and seat. A ship's tile prints the five figures a fight reads on one caption line, from the very
// ship the server served. This holds both to the running build, at the phone (390×844) and the desk (1440×900):
//
//   · SHEET   three REAL captains are seated through the game's own doors (tests/captainSheet.fixture.ts: nothing is stubbed). Each card shows the five stats in the
//             server's order, in the app's words, with her level (Care has none) and, on the stats she adds to, the server's lines — checked against the very numbers
//             the same card prints a different way, on her trait rows. A stat that adds nothing shows its level alone: no line, never a 0.
//   · LAW     the tray's width law holds with the five rows in it (no row past the edge, no label or figure wrapped), and the list behind the card does not move by a pixel
//             when a card opens or closes (pressing SELECTS).
//   · WAY OUT this slice adds no screen, so the cycle is the one it sits on: the card's ✕ closes it and the roster is whole again; a fleet's page has its Back and the
//             roster is whole again.
//   · POWER   the tile of a hull on her fleet's page carries the Power line, five words and five numbers; the numbers are the ones the ship's own panel prints in its Spec.
//   · KOREAN  the labels are the dictionary's Korean (포술 백병 항해 교역 돌봄, 능력치, 레벨); the parts stay the server's own lines, English, as every trait line on the card is.
//
// Run it: npm run build && npx vite preview --port 4191 --strictPort, then PLAYWRIGHT_BASE_URL=http://localhost:4191/byeharu-voyage/ npx playwright test captains.sheet.spec.ts

const GLASSES = [PHONE, { width: 1440, height: 900 }] as const

const EN_LABELS: Record<(typeof SHEET_STATS)[number], string> = { gunnery: 'Gunnery', boarding: 'Boarding', seamanship: 'Seamanship', trade: 'Trade', care: 'Care' }
const KO_LABELS: Record<(typeof SHEET_STATS)[number], string> = { gunnery: '포술', boarding: '백병', seamanship: '항해', trade: '교역', care: '돌봄' }
const POWER_RE = /^Power Attack ([\d,]+) Accuracy ([\d,]+) Reach ([\d,]+) Armour ([\d,]+) Sighting ([\d,]+)$/
const NOT_SERVED = (url: string | undefined) => `nothing served at ${url} — run \`npm run build && npx vite preview --port 4191\` and re-run`

/** Where every roster row and the page's scroll stand, as numbers — what a press must not move. Self-contained, shipped into the page. */
async function rosterBoxes(page: Page) {
  return page.evaluate(() => ({
    rows: [...document.querySelectorAll('[data-testid="your-captain"]')].map((e) => JSON.stringify(e.getBoundingClientRect().toJSON())),
    scroll: [document.querySelector('[data-testid="you"]'), document.scrollingElement].map((e) => e?.scrollTop ?? null),
  }))
}

async function openYou(page: Page, glass: { width: number; height: number }) {
  await page.setViewportSize(glass)
  await serveCaptainWorld(page)
  await page.goto('you')
  await ready(page)
  await expect(page.getByTestId('your-captain')).toHaveCount(SHEET_CAPTAINS.length, { timeout: 120_000 })
}

/** A fleet's page, and the tile of her first hull on it, with the Power line read off it as text. */
async function openPower(page: Page, glass: { width: number; height: number }) {
  await page.setViewportSize(glass)
  await serveCaptainWorld(page)
  await page.goto('fleets')
  await ready(page)
  await page.getByTestId('fleet-row').first().click()
  const fleetPage = page.getByTestId('fleet-page')
  await expect(fleetPage).toBeVisible()
  const tile = fleetPage.getByTestId('fleet-ship-tile').first()
  await expect(tile).toBeVisible()
  const line = tile.getByTestId('ship-power')
  await expect(line).toBeVisible()
  const text = (await line.innerText()).replace(/\s+/g, ' ').trim()
  return { fleetPage, tile, line, text }
}

for (const glass of GLASSES) {
  test(`the card of each captain carries her five stats — ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), NOT_SERVED(baseURL))
    await openYou(page, glass)
    const before = await rosterBoxes(page)
    let measured = 0

    for (const captain of SHEET_CAPTAINS) {
      await page.getByTestId('your-captain').filter({ hasText: captain.name }).click()
      const tray = page.getByTestId('your-captain-tray')
      await expect(tray).toBeVisible()
      const stats = tray.getByTestId('captain-stats')
      await expect(stats.getByTestId('captain-stat-care'), `${captain.code}: the sheet did not land`).toBeVisible({ timeout: 60_000 })

      // THE FIVE, IN THE SERVER'S ORDER, IN THE APP'S WORDS, EACH WITH HER LEVEL (Care has none)
      const ids = await stats.locator('[data-testid^="captain-stat-"]:not([data-testid$="-parts"])').evaluateAll((els) => els.map((e) => e.getAttribute('data-testid')))
      expect(ids, `${captain.code}: the stats are not the five, in order`).toEqual(SHEET_STATS.map((s) => `captain-stat-${s}`))
      for (const stat of SHEET_STATS) {
        const row = stats.getByTestId(`captain-stat-${stat}`)
        await expect(row.locator('[data-row-cell="label"]')).toHaveText(EN_LABELS[stat])
        if (stat === 'care') await expect(row.locator('[data-row-cell="value"]'), 'Care has no level, so no figure').toHaveCount(0)
        else await expect(row.locator('[data-row-cell="value"]')).toHaveText('Lv 1')

        // THE PARTS: the server's lines where she adds, and nothing at all (no line, no 0) where she does not
        const parts = stats.getByTestId(`captain-stat-${stat}-parts`)
        const want = captain.parts[stat]
        if (want === undefined) await expect(parts, `${captain.code} ${stat}: a stat she adds nothing to shows a line`).toHaveCount(0)
        else await expect(parts, `${captain.code} ${stat}`).toHaveText(want)
      }

      // THE SAME NUMBERS, SAID A SECOND WAY: every part is a line her trait rows print too (public.captain_card's, from the kit), so the sheet cannot disagree with the card it stands on
      const traitText = (await tray.locator('[data-testid^="captain-trait-"]').allInnerTexts()).join(' | ')
      for (const line of Object.values(captain.parts).flatMap((p) => p.split(' · '))) {
        expect(traitText, `${captain.code}: the sheet says "${line}" and none of her trait rows does`).toContain(line)
      }

      // THE TRAY'S WIDTH LAW, with the five rows in it
      const read = await readTray(page, 'your-captain-tray')
      measured += read.rows.filter((r) => r.id.startsWith('captain-stat-')).length
      const broken = trayViolations(read, `${captain.code} @${glass.width}×${glass.height}`, (r) => !/^captain-(trait|level|stat)-/.test(r.id))
      expect(broken, broken.join('\n')).toEqual([])

      // THE WAY OUT: her ✕ closes the card, and the roster behind it is exactly as it stood
      await tray.getByTestId('tray-close').click()
      await expect(tray).toHaveCount(0)
      expect(await rosterBoxes(page), `${captain.code}: the roster moved when her card opened and closed`).toEqual(before)
    }
    expect(measured, 'no stat row was measured: the tray drew none').toBe(SHEET_CAPTAINS.length * SHEET_STATS.length)
  })

  test(`a hull's tile carries the Power line, five words and five numbers, and the page has its way back — ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), NOT_SERVED(baseURL))
    const { fleetPage, tile, line, text } = await openPower(page, glass)
    const m = POWER_RE.exec(text)
    expect(m, `the Power line reads "${text}", not Power then five labelled numbers`).not.toBeNull()
    // MEASURED on the founding Barca (unarmed, so Attack 0 and Accuracy 0 are the server's true figures, a per cent of nothing): Reach 21, Armour 5, Sighting 8. The line prints zeros as served and
    // is not a row of them: the hull's reach, armour and sighting are above 0.
    for (const [i, word] of [[3, 'Reach'], [4, 'Armour'], [5, 'Sighting']] as const) {
      expect(Number(m![i].replace(/,/g, '')), `${word} reads 0 on a hull that has some`).toBeGreaterThan(0)
    }
    // the line stands inside the tile, wraps rather than runs out of it, and is not cut
    const fits = await line.evaluate((el, tileEl) => {
      const l = el.getBoundingClientRect()
      const t = (tileEl as Element).getBoundingClientRect()
      return { inside: l.left >= t.left - 1 && l.right <= t.right + 1, cut: el.scrollWidth > el.clientWidth + 1 }
    }, await tile.elementHandle())
    expect(fits, 'the Power line stands outside its tile or is cut').toEqual({ inside: true, cut: false })
    // THE WAY BACK: the fleet's page has its Back, and the roster is whole behind it
    await fleetPage.locator('[data-detail-back]').last().click()
    await expect(fleetPage).toHaveCount(0)
    await expect(page.getByTestId('fleet-row').first()).toBeVisible()
  })
}

test('the Power line is the five figures her own panel prints in its Spec — 390×844', async ({ page, request, baseURL }) => {
  test.setTimeout(900_000)
  test.skip(!(await reachable(request, baseURL ?? '')), NOT_SERVED(baseURL))
  const { text } = await openPower(page, PHONE)
  const m = POWER_RE.exec(text)
  expect(m, `the Power line reads "${text}"`).not.toBeNull()
  const power = Object.fromEntries(['Attack', 'Accuracy', 'Reach', 'Armour', 'Sighting'].map((k, i) => [k, m![i + 1]]))
  // Map → the fleets corner → her row → the fleet tray → her ship → the panel's Spec (the flow tests/map.shipPanel.spec.ts holds)
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
  await page.getByTestId('map-fleets-corner').locator('button[aria-expanded]').click()
  await page.getByTestId('map-fleet-row').first().click()
  await expect(page.getByTestId('map-detail-tray')).toBeVisible()
  await page.getByTestId('tray-ship').first().click()
  const panel = page.getByTestId('map-ship-panel')
  await expect(panel).toBeVisible()
  const spec = panel.getByTestId('ship-stats')
  for (const [word, value] of Object.entries(power)) {
    const cell = spec.locator('div', { has: page.locator('dt', { hasText: new RegExp(`^${word}$`) }) }).first()
    await expect(cell.locator('dd'), `${word}: the panel's Spec and the Power line disagree`).toHaveText(value)
  }
  await panel.getByTestId('tray-close').click()
  await expect(panel).toHaveCount(0)
})

test.describe('in Korean', () => {
  test.use({ locale: 'ko-KR' })

  test('the labels are the dictionary’s Korean; the parts are the server’s lines — 390×844', async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), NOT_SERVED(baseURL))
    await openYou(page, PHONE)
    expect(await page.evaluate(() => document.documentElement.lang), 'the browser said ko-KR').toBe('ko')
    await page.getByTestId('your-captain').first().click()
    const tray = page.getByTestId('your-captain-tray')
    const stats = tray.getByTestId('captain-stats')
    await expect(stats.getByTestId('captain-stat-care')).toBeVisible({ timeout: 60_000 })
    await expect(stats.locator('h4')).toHaveText('능력치')
    for (const stat of SHEET_STATS) {
      const row = stats.getByTestId(`captain-stat-${stat}`)
      await expect(row.locator('[data-row-cell="label"]')).toHaveText(KO_LABELS[stat])
      if (stat !== 'care') await expect(row.locator('[data-row-cell="value"]')).toHaveText('레벨 1')
    }
    // her parts, whoever the first row is, are the server's own lines (a sign, a number, its English words) or none: the client words nothing of them
    const lines = await stats.locator('[data-testid$="-parts"]').allInnerTexts()
    expect(lines.length, 'the first captain of the roster adds to nothing').toBeGreaterThan(0)
    for (const l of lines) expect(l, 'a part reads as the server worded it').toMatch(/^[+−][\d.]+/)
  })
})
