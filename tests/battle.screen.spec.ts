import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { OLD_FIGHT, OLD_READ, READ, READ_BEFORE_0450, READ_MINE, RESULT } from './battleTicks.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BATTLE SCREEN, PLAYED FROM A FIXTURE (0435, docs/design/tick-combat.md 9 and 11; src/live/battle/).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The page is /ui/battle (src/features/gallery/BattleGalleryScreen.tsx): the real screen over a fixture source, outside
// sign-in, no world. tests/battleTicks.fixture.ts is a timeline written per the contract.
// THE VIEW IS SMALL (owner 2026-11-15: "too much words. simplify all"): each side's name with a hull bar and a thin Fury
// bar, the stage, ONE status line, and the log shut behind Log; a watcher has no action bar at all.
//   LATE OPENER  the battle began 10 s before the read: the screen jumps to tick 16 with the log up to it at once.
//   PLAYBACK     hit numbers rise (a crit marked), the log's short lines name each shot, the run with its chance, the join,
//                the patch, the ship sunk and the break-off; the end is ONE line; `cmd.battle_end` is asked ONCE and
//                the read after it brings the loot; Replay starts again from 0 and does not ask again.
//   REDUCED      under prefers-reduced-motion the stage is still (`data-motion` reduced), a hit number stands at full
//                strength, and the struck ship is drawn struck.
//   OLD BATTLE   `ticks` null: the sides and the result, no stage.
//   HER OWN SHIP (0439) the bar presses for her fleet: what her Fury cannot pay for is grey with its cost unlit, a cooling
//                ability sweeps, a refusal says its word, a taken act swaps the re-run timeline in at the same tick (no
//                jump; the log keeps its past), the keys 1-8 press on a desk; on a phone the bar fits.
//   THE SHIPS    (0450; owner 2026-11-16: "in fight, i want to see levels, their stats, their crew state, equipments ...
//                fighting graphics (ships), make it smaller, and fight scene more wider") under each side's name "Lv 5 ·
//                Ships 2" opens that side's ships: each her name whole, Lv, class, hull now / size, crew (red and "Short"
//                under what her class needs), the stats as icons with figures, what is fitted, her captains. Open on a
//                desk, shut on a phone until pressed. The stage has the sheet's whole width at 1280, 1920 and 390, and a
//                hull is drawn small. Her Run button says its chance (the server's `rc`). A battle from before 0450 (no
//                `ships`) draws names and hulls and no chance.
// Screenshots: test-results/battle-screen (or BATTLE_SCREEN_SHOTS).

const SHOTS = process.env.BATTLE_SCREEN_SHOTS ? path.resolve(process.env.BATTLE_SCREEN_SHOTS) : path.resolve('test-results', 'battle-screen')
test.beforeAll(() => mkdirSync(SHOTS, { recursive: true }))

async function openFixture(page: Page, fixture: unknown) {
  await page.addInitScript((fx) => {
    ;(window as unknown as { __BV_BATTLE_FIXTURE__: unknown }).__BV_BATTLE_FIXTURE__ = fx
  }, fixture)
  await page.goto('ui/battle')
  await expect(page.getByTestId('battle-screen')).toBeVisible()
}

const calls = (page: Page) =>
  page.evaluate(() => (window as unknown as { __BV_BATTLE_CALLS__: { read: number; end: number; act: { code: string; tick: number }[] } }).__BV_BATTLE_CALLS__)
const logText = (page: Page) => page.getByTestId('battle-log').innerText()

test('a late opener jumps to the tick now, the fight plays tick by tick to its end, and the end is asked once', async ({ page }) => {
  test.setTimeout(90_000)
  await page.setViewportSize({ width: 1280, height: 800 })
  await openFixture(page, { read: READ, agoMs: 10_000, result: RESULT })

  // THE JUMP: tick 16 at once, the early shots already in the log, nothing after tick 17 yet
  const body = page.getByTestId('battle-body')
  await expect(body).toHaveAttribute('data-motion', 'full')
  await expect.poll(async () => Number(await body.getAttribute('data-tick'))).toBeGreaterThanOrEqual(16)
  expect(Number(await body.getAttribute('data-tick'))).toBeLessThan(20)
  // THE MAIN VIEW: the two sides by name, ONE status line, no paragraph; the log is shut until Log is pressed
  await expect(page.getByTestId('battle-side-0')).toHaveText('Santa Rosa, Navy brig')
  await expect(page.getByTestId('battle-side-1')).toHaveText('Raiders')
  await expect(page.getByTestId('battle-status')).toHaveText(/^(Navy brig hits 40|Black Gull hits 22|Navy brig joins|Miss)$/)
  await expect(page.getByTestId('battle-log')).toHaveCount(0)
  await page.screenshot({ path: path.join(SHOTS, 'wide-main.png') })
  await page.getByTestId('battle-log-toggle').click()
  const early = await logText(page)
  expect(early).toContain('Black Gull → Santa Rosa 31!')
  expect(early).toContain('Miss')
  expect(early).toContain('Navy brig joins')
  expect(early).toContain('Flees 35%')
  expect(early).toContain('Brace')
  expect(early).not.toContain('sunk')
  // every line is short: a clock and a few words, never a sentence
  for (const line of early.split('\n').filter((l) => l.trim() !== '' && !/^\d+:\d\d$/.test(l.trim()))) expect(line.trim().split(/\s+/).length, line).toBeLessThanOrEqual(6)
  // the thin Fury bar: the raiders used Chain at 12 (Fury 20); A WATCHER HAS NO ACTION BAR
  await expect(page.getByTestId('battle-fury-1')).toHaveAttribute('data-fury', '20')
  await expect(page.getByTestId('battle-actions')).toHaveCount(0)
  // the joiner is on the stage: four ships, two a side
  await expect(page.getByTestId('battle-ship')).toHaveCount(4)
  await page.screenshot({ path: path.join(SHOTS, 'wide-playing.png') })

  // THE SHIPS (0450): open on a desk, the side set upon on the left; every figure is the sheet's, the hull is the fight's now
  const toggles = page.getByTestId('battle-ships-toggle')
  await expect(toggles.nth(0)).toHaveText(/^Lv 5 · Ships 2/)
  await expect(toggles.nth(1)).toHaveText(/^Lv 5 · Ships 2/)
  const mine = page.getByTestId('battle-ships-0').getByTestId('battle-ship-card')
  const theirs = page.getByTestId('battle-ships-1').getByTestId('battle-ship-card')
  await expect(mine).toHaveCount(2)
  await expect(theirs).toHaveCount(2)
  const rosa = mine.nth(0)
  await expect(rosa.getByTestId('battle-ship-name')).toHaveText('Santa Rosa')
  await expect(rosa.getByTestId('battle-ship-level')).toHaveText('Lv 2')
  await expect(rosa).toContainText('Caravela latina')
  await expect(rosa.getByTestId('battle-ship-hull')).toHaveText(/^3\d\d\/400$/)
  await expect(rosa.getByTestId('battle-ship-crew')).toHaveAttribute('data-short', '1')
  await expect(rosa.getByTestId('battle-ship-crew')).toHaveText(/10\/30\s*Short/)
  await expect(theirs.nth(0).getByTestId('battle-ship-crew')).toHaveAttribute('data-short', '0')
  for (const label of ['Guns 2', 'Attack 55', 'Accuracy 42', 'Reach 25', 'Armour 12', 'Sighting 10', 'Speed 19.8', 'Handling 71', 'Tier 2'])
    await expect(rosa.getByTestId('battle-ship-stats').getByLabel(label, { exact: true })).toBeVisible()
  await expect(rosa.getByTestId('battle-ship-fit')).toHaveText(/Starter Guns ×2 · Boarding Gear/)
  await expect(rosa.getByTestId('battle-ship-caps')).toHaveText(/Inês de Castro Lv 3/)
  await expect(theirs.nth(0).getByTestId('battle-ship-level')).toHaveText('Lv 5')
  // scannable: no card holds a sentence (a line is a name, a class, figures or a short list)
  for (const line of (await rosa.innerText()).split('\n').filter((l) => l.trim() !== '')) expect(line.trim().split(/\s+/).length, line).toBeLessThanOrEqual(7)
  // THE STAGE IS WIDE AND THE SHIPS SMALL: the stage has the sheet's whole width, the sheet nearly the window's; a hull (her wake with her) is under a sixth of it (it was a quarter)
  const sheet = (await page.getByTestId('battle-screen').boundingBox())!
  const stage = (await page.getByTestId('battle-stage').boundingBox())!
  expect(sheet.width).toBeGreaterThanOrEqual(1280 * 0.96)
  // (the log is open here and has its column on a desk: the stage's whole width is measured with it shut, in the three glasses below)
  expect(stage.width).toBeGreaterThanOrEqual(sheet.width - 330)
  const hullBox = (await page.locator('[data-testid="battle-ship"] g[data-rot]').first().boundingBox())!
  expect(Math.max(hullBox.width, hullBox.height)).toBeLessThan(stage.width / 6)
  expect(Math.max(hullBox.width, hullBox.height)).toBeGreaterThan(50)
  // a side's line shuts its ships, and the stage takes the room
  await toggles.nth(0).click()
  await expect(page.getByTestId('battle-ships-0')).toHaveCount(0)
  await toggles.nth(1).click()
  await expect(page.getByTestId('battle-ships')).toHaveCount(0)
  expect((await page.getByTestId('battle-stage').boundingBox())!.height).toBeGreaterThan(stage.height + 100)
  await toggles.nth(0).click()
  await toggles.nth(1).click()
  await expect(mine).toHaveCount(2)

  // THE HIT NUMBERS rise as the shots land (16..26), a crit marked
  await expect(page.locator('[data-testid="battle-hit"][data-crit="1"]').first()).toBeAttached({ timeout: 15_000 })
  await expect(page.locator('[data-testid="battle-hit"][data-crit="1"]').first()).toHaveText(/^-(55|60)!$/)

  // THE END
  await expect(page.getByTestId('battle-end')).toBeVisible({ timeout: 20_000 })
  await expect(page.getByTestId('battle-outcome')).toHaveAttribute('data-outcome', 'DRIVEN_OFF')
  const done = await logText(page)
  expect(done).toContain('Caught')
  expect(done).toContain('Patch +24')
  expect(done).toContain('Navy brig → Sea Wolf 60!')
  expect(done).toContain('Sea Wolf sunk')
  expect(done).toContain('Broke off')
  await expect(page.locator('[data-testid="battle-ship"][data-struck="1"]')).toHaveCount(1)
  // ONE end asked, and the read after it brings the loot to the end card and the log's last line
  await expect.poll(async () => (await calls(page)).end).toBe(1)
  await expect(page.getByTestId('battle-end')).toHaveText('Driven off · 1,250 gold')
  await expect(page.getByTestId('battle-log-line').first()).toHaveText(/Driven off · 1,250 gold$/)
  await page.screenshot({ path: path.join(SHOTS, 'wide-end.png') })

  // REPLAY from 0: the log empties back, the end is not asked again
  await page.getByTestId('battle-replay').click()
  await expect.poll(async () => Number(await body.getAttribute('data-tick'))).toBeLessThan(4)
  expect(await page.getByTestId('battle-log-line').count()).toBeLessThan(4)
  await expect(page.getByTestId('battle-end')).toHaveCount(0)
  expect((await calls(page)).end).toBe(1)

  // Close
  await page.getByTestId('battle-close').click()
  await expect(page.getByTestId('battle-screen')).toHaveCount(0)
})

test('reduced motion: the stage stands still, a hit number stands at full strength, the struck ship is drawn struck', async ({ page }) => {
  test.setTimeout(60_000)
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.setViewportSize({ width: 390, height: 844 })
  await openFixture(page, { read: READ, agoMs: 13_800, result: RESULT })
  const body = page.getByTestId('battle-body')
  await expect(body).toHaveAttribute('data-motion', 'reduced')
  // a ship does not move between two frames
  const ship = page.getByTestId('battle-ship').first()
  const at = await ship.getAttribute('transform')
  await page.waitForTimeout(250)
  const tick = await body.getAttribute('data-tick')
  if ((await body.getAttribute('data-tick')) === tick) expect(await ship.getAttribute('transform')).toBe(at)
  // the crit at tick 24 stands, not faded
  const crit = page.locator('[data-testid="battle-hit"][data-crit="1"]').first()
  await expect(crit).toBeAttached({ timeout: 15_000 })
  const look = await crit.evaluate((el) => {
    const cs = getComputedStyle(el)
    return { opacity: Number(cs.opacity), animation: cs.animationName }
  })
  expect(look.opacity).toBe(1)
  expect(look.animation).toBe('none')
  await page.screenshot({ path: path.join(SHOTS, 'phone-reduced-hit.png') })
  await expect(page.getByTestId('battle-end')).toBeVisible({ timeout: 15_000 })
  await expect(page.locator('[data-testid="battle-ship"][data-struck="1"]')).toHaveCount(1)
  await expect(page.getByTestId('battle-outcome')).toHaveAttribute('data-outcome', 'DRIVEN_OFF')
  // the page never scrolls sideways on a phone
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: path.join(SHOTS, 'phone-reduced-end.png') })
})

test('an old round-by-round battle shows its sides and its result, with no stage', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await openFixture(page, { read: OLD_READ, old: OLD_FIGHT })
  await expect(page.getByTestId('battle-old')).toBeVisible()
  await expect(page.getByTestId('battle-old')).toContainText('Santa Rosa, Navy brig')
  await expect(page.getByTestId('battle-old')).toContainText('Raiders')
  await expect(page.getByTestId('battle-outcome')).toHaveAttribute('data-outcome', 'PLUNDERED')
  await expect(page.getByTestId('battle-outcome')).toHaveText('Plundered · 900 gold')
  await expect(page.getByTestId('battle-stage')).toHaveCount(0)
  expect((await calls(page)).end).toBe(0)
  await page.screenshot({ path: path.join(SHOTS, 'phone-old.png') })
})

test('her own ship: the action bar presses, greys what it cannot pay for, says a refusal, swaps the new timeline in without a jump, and answers the keys', async ({ page }) => {
  test.setTimeout(60_000)
  await page.setViewportSize({ width: 1280, height: 800 })
  await openFixture(page, { read: READ_MINE, agoMs: 15_000, result: RESULT, actRefuse: ['E_COOLDOWN'] })
  const body = page.getByTestId('battle-body')
  const bar = page.getByTestId('battle-actions')
  const btn = (code: string) => bar.locator(`button[data-code="${code}"]`)
  await expect(bar.getByRole('button')).toHaveCount(8)
  await page.getByTestId('battle-log-toggle').click()
  await expect.poll(async () => Number(await body.getAttribute('data-tick'))).toBeGreaterThanOrEqual(25)
  // an icon and ONE word each
  // (0450: Run also says its chance, the server's figure: 35 % at the open, 30 once she was caught at 23)
  for (const b of await bar.getByRole('button').all()) expect(((await b.innerText()).trim().split(/\s+/).length)).toBeLessThanOrEqual((await b.getAttribute('data-code')) === 'RN' ? 3 : 2)
  await expect(btn('CH')).toContainText('Chain')
  await expect(btn('RN').getByTestId('battle-run-chance')).toHaveAttribute('data-chance', '30')
  await expect(btn('RN')).toContainText('Run 30%')
  await expect(bar.getByTestId('battle-run-chance')).toHaveCount(1)
  // her bar is empty: Rake, Grapeshot and Patch are grey; Brace is cooling (used at 7); the rest are ready
  for (const code of ['RK', 'GR', 'PT']) {
    await expect(btn(code)).toBeDisabled()
    await expect(btn(code)).toHaveAttribute('data-lock', 'fury')
    await expect(btn(code)).toHaveAttribute('data-afford', '0')
  }
  await expect(btn('BR')).toHaveAttribute('data-lock', 'cooldown')
  await expect(btn('BR')).toBeDisabled()
  for (const code of ['BS', 'CH', 'RN', 'PY']) await expect(btn(code)).toBeEnabled()
  await page.screenshot({ path: path.join(SHOTS, 'wide-act-bar.png') })

  // THE REFUSAL: its short word under the bar; nothing changes
  await btn('BS').click()
  await expect(page.getByTestId('battle-act-refusal')).toHaveText('Not ready')
  await expect(page.getByTestId('battle-act-refusal')).toHaveAttribute('data-code', 'E_COOLDOWN')

  // TAKEN: asked for the next tick; the re-run timeline is swapped in at the same tick (the log keeps its past), and the
  // Broadside is in it with her Fury after
  const before = Number(await body.getAttribute('data-tick'))
  await btn('BS').click()
  await expect.poll(async () => (await calls(page)).act.length).toBe(2)
  const asked = (await calls(page)).act[1]
  expect(asked.code).toBe('BS')
  expect(asked.tick).toBeGreaterThan(before)
  expect(asked.tick).toBeLessThanOrEqual(before + 3)
  const after = Number(await body.getAttribute('data-tick'))
  expect(after).toBeGreaterThanOrEqual(before)
  expect(after).toBeLessThan(before + 4)
  await expect(page.getByTestId('battle-log')).toContainText('Broadside')
  await expect(page.getByTestId('battle-log')).toContainText('Caught')
  await expect(page.getByTestId('battle-fury-0')).toHaveAttribute('data-fury', '10')
  await expect(btn('BS')).toHaveAttribute('data-lock', 'cooldown')
  await expect(page.getByTestId('battle-act-refusal')).toHaveCount(0)

  // THE KEYS: 2 is Chain Shot, once the spam cap (a global cooldown) has passed
  await expect(btn('CH')).toBeEnabled({ timeout: 5_000 })
  await page.keyboard.press('2')
  await expect.poll(async () => (await calls(page)).act.length).toBe(3)
  expect((await calls(page)).act[2].code).toBe('CH')
  await expect(page.getByTestId('battle-fury-0')).toHaveAttribute('data-fury', '20', { timeout: 5_000 })
  await page.screenshot({ path: path.join(SHOTS, 'wide-act-taken.png') })
})

test('her own ship on a phone: the bar fits, ✕ is a touch target at the top right and closes it', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await openFixture(page, { read: READ_MINE, agoMs: 15_000, result: RESULT })
  await expect(page.getByTestId('battle-actions').getByRole('button')).toHaveCount(8)
  await expect(page.getByTestId('battle-actions').locator('button[data-code="BS"]')).toBeEnabled()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: path.join(SHOTS, 'phone-act-bar.png') })
  // THE SHIPS ON A PHONE (0450): shut until a side's line is pressed; open, a card is as wide as the sheet and nothing scrolls sideways
  await expect(page.getByTestId('battle-ships')).toHaveCount(0)
  const line = page.getByTestId('battle-ships-toggle').first()
  await expect(line).toHaveText(/^Lv 5 · Ships 2/)
  await expect(line).toHaveAttribute('aria-expanded', 'false')
  await line.click()
  await expect(line).toHaveAttribute('aria-expanded', 'true')
  const card = page.getByTestId('battle-ships-0').getByTestId('battle-ship-card').first()
  await expect(card.getByTestId('battle-ship-name')).toHaveText('Santa Rosa')
  await expect(card.getByTestId('battle-ship-level')).toHaveText('Lv 2')
  expect((await card.boundingBox())!.width).toBeGreaterThan(300)
  await expect(page.getByTestId('battle-ships-1')).toHaveCount(0)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await expect(page.getByTestId('battle-stage')).toBeVisible()
  await expect(page.getByTestId('battle-actions').locator('button[data-code="RN"]')).toBeVisible()
  await page.screenshot({ path: path.join(SHOTS, 'phone-ships-open.png') })
  await line.click()
  await expect(page.getByTestId('battle-ships')).toHaveCount(0)
  const box = (await page.getByTestId('battle-close').boundingBox())!
  expect(Math.min(box.width, box.height)).toBeGreaterThanOrEqual(44)
  expect(box.x + box.width).toBeLessThanOrEqual(390)
  expect(box.x).toBeGreaterThan(195)
  await page.getByTestId('battle-close').click()
  await expect(page.getByTestId('battle-screen')).toHaveCount(0)
})

for (const [w, h] of [
  [1280, 800],
  [1920, 1080],
  [390, 844],
] as const) {
  test(`the stage has the sheet's whole width and small ships at ${w}x${h}`, async ({ page }) => {
    await page.setViewportSize({ width: w, height: h })
    await openFixture(page, { read: READ, agoMs: 9_300, result: RESULT })
    const body = page.getByTestId('battle-body')
    await expect.poll(async () => Number(await body.getAttribute('data-tick'))).toBeGreaterThanOrEqual(16)
    const sheet = (await page.getByTestId('battle-screen').boundingBox())!
    const stage = (await page.getByTestId('battle-stage').boundingBox())!
    expect(sheet.width).toBeGreaterThanOrEqual(w * 0.96)
    expect(stage.width).toBeGreaterThanOrEqual(sheet.width - 2)
    expect(stage.height).toBeGreaterThanOrEqual(180)
    // every ship that has come up is on the stage, and no hull (her wake with her) is longer than two sevenths of it (a phone; it was over four tenths) or a sixth (a desk; it was a quarter)
    for (const ship of await page.locator('[data-testid="battle-ship"]:not([opacity="0.00"]) g[data-rot]').all()) {
      const b = (await ship.boundingBox())!
      expect(Math.max(b.width, b.height)).toBeLessThan(stage.width / (w < 600 ? 3.5 : 6))
      expect(b.x + b.width / 2).toBeGreaterThan(stage.x)
      expect(b.x + b.width / 2).toBeLessThan(stage.x + stage.width)
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    await page.screenshot({ path: path.join(SHOTS, `stage-${w}x${h}.png`) })
  })
}

test('a battle opened before 0450 (no ships served): names and hulls, no level, no chance on Run', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 })
  const before = { ...READ_BEFORE_0450, mine: 'f-rosa', sides: READ_MINE.sides, ticks: { ...READ_BEFORE_0450.ticks!, n: 100, e: READ_MINE.ticks!.e } }
  await openFixture(page, { read: before, agoMs: 6_000, result: RESULT })
  await expect(page.getByTestId('battle-ships-toggle').first()).toHaveText(/^Ships 2/)
  const card = page.getByTestId('battle-ships-0').getByTestId('battle-ship-card').first()
  await expect(card.getByTestId('battle-ship-name')).toHaveText('Santa Rosa')
  await expect(card.getByTestId('battle-ship-hull')).toHaveText(/^\d+\/400$/)
  await expect(card.getByTestId('battle-ship-level')).toHaveCount(0)
  await expect(card.getByTestId('battle-ship-crew')).toHaveCount(0)
  await expect(page.getByTestId('battle-actions').locator('button[data-code="RN"]')).toHaveText(/Run$/)
  await expect(page.getByTestId('battle-run-chance')).toHaveCount(0)
})
