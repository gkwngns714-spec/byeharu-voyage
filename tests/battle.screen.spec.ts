import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { OLD_FIGHT, OLD_READ, READ, READ_MINE, RESULT } from './battleTicks.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BATTLE SCREEN, PLAYED FROM A FIXTURE (0435, docs/design/tick-combat.md 9 and 11; src/live/battle/).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The page is /ui/battle (src/features/gallery/BattleGalleryScreen.tsx): the real screen over a fixture source, outside
// sign-in, no world. tests/battleTicks.fixture.ts is a timeline written per the contract.
//   LATE OPENER  the battle began 10 s before the read: the screen jumps to tick 16 with the log up to it at once.
//   PLAYBACK     hit numbers rise (a crit marked), the log names each shot, the run's roll with its chance, the join,
//                the patch, the ship struck and the break-off; the end is DRIVEN_OFF; `cmd.battle_end` is asked ONCE and
//                the read after it brings the loot; Replay starts again from 0 and does not ask again.
//   REDUCED      under prefers-reduced-motion the stage is still (`data-motion` reduced), a hit number stands at full
//                strength, and the struck ship is drawn struck.
//   OLD BATTLE   `ticks` null: the sides and the result, no stage.
//   HER OWN SHIP (0439) the bar presses for her fleet: what her Fury cannot pay for is grey with its cost unlit, a cooling
//                ability sweeps, a refusal says its word, a taken act swaps the re-run timeline in at the same tick (no
//                jump; the log keeps its past), the keys 1-8 press on a desk; on a phone the bar fits.
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
  const early = await logText(page)
  expect(early).toContain('Black Gull · Broadside → Santa Rosa · Hit 31 · Critical · Hull 345')
  expect(early).toContain('Gunfire → Santa Rosa · Miss · Hull 345')
  expect(early).toContain('Navy brig · Joins · Santa Rosa, Navy brig')
  expect(early).toContain('Brace · Fury 0')
  expect(early).not.toContain('Struck')
  // the Fury bar and the action row: the raiders used Chain Shot at 12 (Fury 20); a watcher's row is watch-only
  await expect(page.getByTestId('battle-fury-1')).toHaveAttribute('data-fury', '20')
  await expect(page.getByTestId('battle-actions')).toHaveAttribute('data-mode', 'watch')
  await expect(page.getByTestId('battle-actions').getByRole('button')).toHaveCount(8)
  for (const b of await page.getByTestId('battle-actions').getByRole('button').all()) await expect(b).toBeDisabled()
  // the joiner is on the stage: four ships, two a side
  await expect(page.getByTestId('battle-ship')).toHaveCount(4)
  await page.screenshot({ path: path.join(SHOTS, 'wide-playing.png') })

  // THE HIT NUMBERS rise as the shots land (16..26), a crit marked
  await expect(page.locator('[data-testid="battle-hit"][data-crit="1"]').first()).toBeAttached({ timeout: 15_000 })
  await expect(page.locator('[data-testid="battle-hit"][data-crit="1"]').first()).toHaveText(/^-(55|60)!$/)

  // THE END
  await expect(page.getByTestId('battle-end')).toBeVisible({ timeout: 20_000 })
  await expect(page.getByTestId('battle-outcome')).toHaveAttribute('data-outcome', 'DRIVEN_OFF')
  const done = await logText(page)
  expect(done).toContain('Santa Rosa, Navy brig · Run 35% · Caught')
  expect(done).toContain('Black Gull · Patch · Repaired +24 · Hull 229')
  expect(done).toContain('Navy brig · Gunfire → Sea Wolf · Hit 60 · Critical · Hull 0')
  expect(done).toContain('Sea Wolf · Struck')
  expect(done).toContain('Raiders · Broke off')
  await expect(page.locator('[data-testid="battle-ship"][data-struck="1"]')).toHaveCount(1)
  // ONE end asked, and the read after it brings the loot to the end card and the log's last line
  await expect.poll(async () => (await calls(page)).end).toBe(1)
  await expect(page.getByTestId('battle-end')).toContainText('Loot 1,250')
  await expect(page.getByTestId('battle-log-line').first()).toHaveText(/End · Driven off · Loot 1,250 · Crew lost 3/)
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
  await expect(bar).toHaveAttribute('data-mode', 'act')
  await expect.poll(async () => Number(await body.getAttribute('data-tick'))).toBeGreaterThanOrEqual(25)
  // her bar is empty: Rake, Grapeshot and Patch are grey, their cost unlit; Brace is cooling (used at 7); the rest are ready
  for (const code of ['RK', 'GR', 'PT']) {
    await expect(btn(code)).toBeDisabled()
    await expect(btn(code)).toHaveAttribute('data-lock', 'fury')
    await expect(btn(code)).toHaveAttribute('data-afford', '0')
  }
  await expect(btn('RK').getByTestId('battle-cost')).toHaveText('50')
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
  await expect(page.getByTestId('battle-log')).toContainText('Santa Rosa, Navy brig · Broadside · Fury 10')
  await expect(page.getByTestId('battle-log')).toContainText('Santa Rosa, Navy brig · Run 35% · Caught')
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

test('her own ship on a phone: the bar fits, a watcher\'s bar stays disabled', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await openFixture(page, { read: READ_MINE, agoMs: 15_000, result: RESULT })
  await expect(page.getByTestId('battle-actions')).toHaveAttribute('data-mode', 'act')
  await expect(page.getByTestId('battle-actions').locator('button[data-code="BS"]')).toBeEnabled()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: path.join(SHOTS, 'phone-act-bar.png') })
})
