import { test, expect, type Locator, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { reachable, ready } from './appReady.fixture'
import { BATTLE_ABOARD, serveBattleWorld } from './battleWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A BATTLE SHE STARTS HERSELF, DRIVEN IN A REAL BROWSER, LIT (owner row 324: "make everything work. open them if
// everything is built and is workable"; docs/COMBAT_LOG.md 3.3, 3.4, 3.6; docs/dev-log/2026-11-13-attacks-ready.md).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// `attack_enabled` is dark on production, so until this spec no page had ever reached the Attack section or the
// battle card (docs/dev-log/2026-11-12-live-rounds.md, "Not proven"). The world is tests/battleWorld.fixture.ts: the
// shipped image with attacks, the armed cargo ship, the navy, regard and the crown hulls' level LIT in a private
// copy, a round every 5 s, a cargo ship of Spain at sea with 100,000 aboard and her own fleet at anchor near her.
// NOTHING OF THE FIGHT IS PINNED: the page presses the real doors and reads the chain's own answers.
//   THE PATH   the map: a cargo ship's hull -> her card -> the Attack section's read (the foe in a word, the funds in
//              a word, the miles, when the navy arrives) -> Attack -> the battle card.
//   THE CARD   rounds arrive one at a time; each round has both hull bars and they only ever go down (but for the
//              round a navy ship comes up for, which says so); the countdown runs; the navy's own clock runs until she
//              is there; Fight and Flee are there, and a stance takes hold from the NEXT round.
//   TO THE BOARDING ('board')  the battle is fought to its clock's end, the boarding is told, gold is taken and her
//              purse on the bar rises by exactly that; the navy's line is said; the held cargo ship ARRIVES afterwards.
//   BREAK-OFF  ('flee')  Flee is kept from the next round; the round she runs she fires nothing; she gets away and the
//              battle is BROKEN_OFF with no gold.
//   THE RING   her battle is ringed on the map (0364), a press opens the fight with both sides, and the navy ship
//              called to it is on the defender's side, on her way and then there.
//   HISTORY    the BATTLE_REPORT is in History with its whole log; the regard that fell and the WANTED mark are there.
//   THE GLASS  390x844 and 1280x800, English and Korean, and 320 px for the card: nothing leaves its box, nothing is
//              cut with an ellipsis, no word is broken inside, the page never scrolls sideways, and every name is whole.
// EVERY BUILT WORLD HAS ITS OWN DICE (0031's world_secret), so no assertion here assumes how a roll falls: the two
// worlds are arranged so that the ENDING is the same under any dice (see the fixture), and SPEC_WORLD_SECRET lets
// scripts/ops/harness/attacks/dice.mjs prove that under ten others.
// Run it: npm run build && npm run preview, then `npx playwright test battle.live.spec.ts`.
// Screenshots go to test-results/battle-live (or BATTLE_SHOTS).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SHOTS = process.env.BATTLE_SHOTS ? path.resolve(process.env.BATTLE_SHOTS) : path.resolve('test-results', 'battle-live')
const PHONE = { width: 390, height: 844 }
const SMALL = { width: 320, height: 640 }
const WIDE = { width: 1280, height: 800 }

test.use({ deviceScaleFactor: 2 })
// each test boots its own private world and fights its own battle: they do not share a page, so they run side by side
test.describe.configure({ mode: 'parallel' })
test.beforeAll(() => mkdirSync(SHOTS, { recursive: true }))

const num = (s: string | null) => Number((s ?? '').replace(/[^0-9]/g, ''))

/** What the page's console said in error, and any error it threw: a battle that goes wrong on the server says so there (an RPC that raised). Printed with a failure. */
const said = new WeakMap<Page, string[]>()

/** The map, open, with the cargo ship at sea on it; her card opened by a press on her hull. Answers her fleet id. */
async function openCargoCard(page: Page, kind: 'board' | 'flee'): Promise<string> {
  const errors: string[] = []
  said.set(page, errors)
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text().slice(0, 400))
  })
  page.on('pageerror', (e) => errors.push(`thrown: ${e.message.slice(0, 400)}`))
  page.on('crash', () => errors.push('THE PAGE CRASHED'))
  await serveBattleWorld(page, kind)
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
  const hull = page.locator('[data-testid="map-merchant"][data-merchant-docked="false"]').first()
  await expect(hull, 'the cargo ship the fixture sailed is on the sea').toBeVisible({ timeout: 90_000 })
  const id = (await hull.getAttribute('data-merchant-id'))!
  // she is a few miles out of harbour and a harbour is still the harbour under a press: come in close on her, as a player does
  for (let i = 0; i < 4; i++) {
    const z = (await hull.boundingBox())!
    await page.mouse.move(z.x + z.width / 2, z.y + z.height / 2)
    await page.mouse.wheel(0, -400)
    await page.waitForTimeout(350)
  }
  const b = (await hull.boundingBox())!
  await page.mouse.click(b.x + b.width / 2, b.y + b.height / 2)
  await expect(page.getByTestId('cargo-sheet')).toBeVisible()
  await expect(page.getByTestId('cargo-sheet-name')).toContainText('Cargo ship')
  return id
}

/** Inside `root`: no element wider than it or outside it, no text cut with an ellipsis, no rule that breaks inside a word, and the page does not scroll sideways. */
async function holdsItsWidth(root: Locator, label: string) {
  const bad = await root.evaluate((box) => {
    const out: string[] = []
    const edge = box.getBoundingClientRect()
    for (const el of box.querySelectorAll<HTMLElement>('*')) {
      const r = el.getBoundingClientRect()
      if (r.width === 0 || r.height === 0) continue
      const what = `${el.tagName} ${el.getAttribute('data-testid') ?? ''} "${(el.textContent ?? '').slice(0, 40)}"`
      if (r.right > edge.right + 1 || r.left < edge.left - 1) out.push(`outside its box: ${what}`)
      const cs = getComputedStyle(el)
      if (cs.textOverflow === 'ellipsis' && el.scrollWidth > el.clientWidth + 1) out.push(`cut with an ellipsis: ${what}`)
      if (cs.wordBreak === 'break-all' || cs.overflowWrap === 'anywhere') out.push(`may break inside a word: ${what}`)
      // a one-line cell (a figure, a bar, a button's word) is not wider than itself
      if (cs.whiteSpace === 'nowrap' && el.children.length === 0 && el.scrollWidth > el.clientWidth + 1 && cs.display !== 'inline') out.push(`a one-line cell overflows: ${what}`)
    }
    if (document.documentElement.scrollWidth > document.documentElement.clientWidth) out.push('the page scrolls sideways')
    return out
  })
  expect(bad, label).toEqual([])
}

/** The Attack section's pre-fight read, then the press. Answers the battle card. */
async function attack(page: Page, words: { foe: string; funds: string }): Promise<Locator> {
  const section = page.getByTestId('cargo-attack')
  const go = page.getByTestId('cargo-attack-go')
  await go.scrollIntoViewIfNeeded()
  await expect(go).toBeVisible({ timeout: 30_000 })
  // the read: her side in a word and her funds in a word (never a figure, never a forecast), the miles, and when the navy would be there
  await expect(page.getByTestId('cargo-attack-word')).toContainText(words.foe)
  await expect(page.getByTestId('cargo-attack-funds')).toContainText(words.funds)
  await expect(page.getByTestId('cargo-attack-navy'), 'a navy ship of her country is in reach, and the read says so before the press').toBeVisible()
  await expect(section.getByTestId('cargo-attack-refused')).toHaveCount(0)
  await go.click()
  const card = page.getByTestId('battle-card')
  await expect(card, 'the press opens the battle card under the Attack section').toBeVisible({ timeout: 30_000 })
  await expect(page.getByTestId('cargo-attack-started')).toBeVisible()
  // the frozen pre-fight rows are gone: the card says it live from here
  await expect(go).toHaveCount(0)
  await expect(page.getByTestId('cargo-attack-navy')).toHaveCount(0)
  return card
}

/** The log's rows as the glass shows them: round, her bar, theirs, whether a ship came up for that round, and what her cell says. */
async function logRows(page: Page) {
  return page.getByTestId('fight-log-round').evaluateAll((rows) =>
    rows.map((li) => ({
      round: Number(li.getAttribute('data-round')),
      hull: Number(li.querySelector('[data-testid="fight-log-hull"]')?.getAttribute('data-pct')),
      foe: Number(li.querySelector('[data-testid="fight-log-foe-hull"]')?.getAttribute('data-pct')),
      joined: li.querySelector('[data-testid="fight-log-joined"]') !== null,
      you: li.querySelector('[data-testid="fight-log-you"]')?.getAttribute('data-kind') ?? '',
    })),
  )
}

/** What is true of the bars under any dice: each is a percent; hers never rises; theirs never rises but in a round a ship came up for. */
function barsOnlyFall(rows: Awaited<ReturnType<typeof logRows>>) {
  for (const [i, r] of rows.entries()) {
    expect(r.round, 'the rounds are numbered in order').toBe(i + 1)
    expect(r.hull).toBeGreaterThanOrEqual(0)
    expect(r.hull).toBeLessThanOrEqual(100)
    expect(r.foe).toBeGreaterThanOrEqual(0)
    expect(r.foe).toBeLessThanOrEqual(100)
    if (i === 0) continue
    expect(r.hull, `round ${r.round}: her hull bar does not rise`).toBeLessThanOrEqual(rows[i - 1].hull)
    if (!r.joined) expect(r.foe, `round ${r.round}: their hull bar does not rise unless a ship came up`).toBeLessThanOrEqual(rows[i - 1].foe)
  }
}

/** History, without a reload (the world lives in this tab). */
async function openHistory(page: Page) {
  const closer = page.getByTestId('cargo-sheet').getByRole('button').first()
  if (await closer.isVisible().catch(() => false)) await page.keyboard.press('Escape')
  const direct = page.locator('[data-testid="nav-bar"] a[href$="/ledger"]').first()
  if (await direct.isVisible().catch(() => false)) {
    await direct.click()
  } else {
    await page.locator('[data-testid="nav-bar"] > button').first().click()
    await page.getByTestId('nav-group-panel').locator('a[href$="/ledger"]').click()
  }
  await expect(page.getByTestId('ledger')).toBeVisible({ timeout: 30_000 })
}

// ── TO THE BOARDING: the whole path, on a phone ──
test.describe('a battle fought to the boarding, 390×844, English', () => {
  test.use({ viewport: PHONE, locale: 'en-US' })

  test('the card of a cargo ship, the read, the press; rounds, bars, clocks, the navy; the boarding and the gold; she arrives; History keeps it', async ({ page, request, baseURL }) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`)
    const target = await openCargoCard(page, 'board')
    await expect(page.getByTestId('cargo-funds')).toContainText(BATTLE_ABOARD.toLocaleString('en-US'))
    await page.screenshot({ path: path.join(SHOTS, 'board-390-en-1-card.png') })
    const purse = num(await page.getByTestId('purse').first().textContent().catch(() => null))

    const card = await attack(page, { foe: 'Weaker', funds: 'Light' })
    await page.screenshot({ path: path.join(SHOTS, 'board-390-en-2-started.png') })
    // ── THE CARD WHILE IT IS FOUGHT ──
    await expect(card).toHaveAttribute('data-status', 'FIGHTING')
    await expect(card).toHaveAttribute('data-stance', 'FIGHT')
    await expect(page.getByTestId('battle-foe')).toHaveText('Cargo ship 1')
    await expect(page.getByTestId('battle-clock')).toHaveText(/^\d+:\d\d$/)
    await expect(page.getByTestId('battle-stance-FIGHT')).toBeVisible()
    await expect(page.getByTestId('battle-stance-FLEE')).toBeVisible()
    await expect(page.getByTestId('battle-stance-PAY'), 'the side that attacked cannot pay its way out').toHaveCount(0)
    // the navy is on her way: her own clock is on the card until she is there
    await expect(page.getByTestId('battle-navy-coming')).toBeVisible()
    await expect(page.getByTestId('battle-navy-clock')).toHaveText(/^\d+:\d\d$/)
    const log = page.getByTestId('fight-log')
    await expect(log).toHaveAttribute('data-deck', 'attacker')
    await expect(log).toHaveAttribute('data-end', 'OPEN')
    await expect(page.getByTestId('fight-log-result'), 'nothing is told before the server has it').toHaveCount(0)
    await expect(page.getByTestId('battle-loot')).toHaveCount(0)
    // ── ROUNDS ARRIVE, ONE AT A TIME ──
    const rounds = async () => Number(await log.getAttribute('data-rounds'))
    await expect.poll(rounds, { timeout: 40_000, message: 'a first round is fought and shown' }).toBeGreaterThanOrEqual(1)
    const first = (await logRows(page))[0]
    await expect.poll(rounds, { timeout: 40_000, message: 'the log grows by a round' }).toBeGreaterThanOrEqual(2)
    expect((await logRows(page))[0], 'a later round never rewrites an earlier one').toEqual(first)
    await holdsItsWidth(page.getByTestId('cargo-sheet'), 'the battle card being fought, 390 px')
    // ── THE NAVY COMES UP IN A LATER ROUND, and the log says in which ──
    await expect(page.getByTestId('fight-log-joined'), 'the navy ship called to the battle comes up, and the log says so').toHaveCount(1, { timeout: 60_000 })
    const joinedAt = (await logRows(page)).find((r) => r.joined)!.round
    expect(joinedAt, 'she was called at the press and came up in a LATER round').toBeGreaterThan(1)
    await expect(page.getByTestId('battle-navy-coming'), 'once she is there her clock is gone').toHaveCount(0)
    await expect(page.getByTestId('fight-log-foe')).toContainText('Ships 2')
    await page.getByTestId('fight-log-joined').scrollIntoViewIfNeeded()
    await page.screenshot({ path: path.join(SHOTS, 'board-390-en-3-navy-joined.png') })

    // ── THE BOARDING: it ends at its clock, the result and the gold are told ──
    await expect(card).not.toHaveAttribute('data-status', 'FIGHTING', { timeout: 90_000 })
    await expect(card).toHaveAttribute('data-status', 'RESOLVED')
    const rows = await logRows(page)
    expect(rows.length, 'every round of the clock was fought').toBe(6)
    barsOnlyFall(rows)
    await expect(log).toHaveAttribute('data-end', 'A_TOOK')
    await expect(page.getByTestId('fight-log-board')).toBeVisible()
    await expect(page.getByTestId('fight-log-result')).toContainText('Boarded')
    await expect(page.getByTestId('battle-clock')).toHaveCount(0)
    await expect(page.locator('[data-testid^="battle-stance-"]')).toHaveCount(0)
    const loot = num(await page.getByTestId('battle-loot').textContent())
    expect(loot, 'gold is taken at the boarding').toBeGreaterThan(0)
    expect(loot, 'never more than loot_share of what was aboard').toBeLessThanOrEqual(BATTLE_ABOARD * 0.15)
    await expect(page.getByTestId('battle-loot-rule')).toBeVisible()
    await expect(page.getByTestId('battle-navy')).toHaveText('The navy came in time.')
    // her ships by their whole names, each with her hull before and after
    await expect(page.getByTestId('fight-log-ship')).toHaveCount(2)
    await expect(page.getByTestId('fight-log-ship').nth(0)).toContainText('Gaivota')
    await expect(page.getByTestId('fight-log-ship').nth(1)).toContainText('Santa Ana')
    // the cargo ship's own card: what is left aboard is what was aboard less the loot
    await expect.poll(async () => num(await page.getByTestId('cargo-funds').textContent()), { timeout: 30_000 }).toBe(BATTLE_ABOARD - loot)
    if (purse > 0) await expect.poll(async () => num(await page.getByTestId('purse').first().textContent()), { timeout: 30_000 }).toBe(purse + loot)
    await page.getByTestId('battle-loot').scrollIntoViewIfNeeded()
    await page.screenshot({ path: path.join(SHOTS, 'board-390-en-4-boarded.png') })
    await holdsItsWidth(page.getByTestId('cargo-sheet'), 'the finished battle, 390 px')

    // ── THE HELD SHIP SAILS ON AND ARRIVES: back on the map, her hull is no longer on the passage she was held on (she lies in port, or is away on her next) ──
    await page.getByTestId('tray-close').first().click()
    await expect(page.getByTestId('cargo-sheet')).toHaveCount(0)
    const hullNow = page.locator(`[data-testid="map-merchant"][data-merchant-id="${target}"]`)
    const heldEta = (await hullNow.first().getAttribute('data-merchant-eta').catch(() => null)) ?? ''
    await expect
      .poll(
        async () => {
          if ((await hullNow.count()) === 0) return 'gone into port'
          if ((await hullNow.first().getAttribute('data-merchant-docked')) === 'true') return 'in port'
          return (await hullNow.first().getAttribute('data-merchant-eta')) !== heldEta ? 'on her next passage' : 'still held'
        },
        { timeout: 120_000, message: 'the cargo ship that was held for the battle sails on and arrives' },
      )
      .not.toBe('still held')

    // ── HISTORY KEEPS IT: the report with its whole log, the regard that fell, the WANTED mark ──
    await openHistory(page)
    const list = page.getByTestId('ledger-list')
    const report = list.getByTestId('ledger-row').filter({ hasText: 'fought a battle and took' }).first()
    await expect(report).toBeVisible({ timeout: 30_000 })
    await expect(report).toContainText('Gaivota')
    await expect(report).toContainText(loot.toLocaleString('en-US'))
    await expect(list.getByTestId('ledger-row').filter({ hasText: 'thinks worse of you' }).first()).toBeVisible()
    await expect(list.getByTestId('ledger-row').filter({ hasText: 'wants you' }).first()).toBeVisible()
    await page.screenshot({ path: path.join(SHOTS, 'board-390-en-5-history.png') })
    await report.click()
    const tray = page.getByTestId('ledger-report')
    await expect(tray).toBeVisible()
    const kept = tray.getByTestId('fight-log')
    await expect(kept).toHaveAttribute('data-deck', 'attacker')
    await expect(kept).toHaveAttribute('data-end', 'A_TOOK')
    await expect(kept).toHaveAttribute('data-rounds', '6')
    await expect(tray.getByTestId('fight-log-joined')).toHaveCount(1)
    await expect(tray.getByTestId('fight-log-result')).toContainText('Boarded')
    await page.screenshot({ path: path.join(SHOTS, 'board-390-en-6-history-log.png') })
    await holdsItsWidth(tray, 'the report in History, 390 px')
  })
})

// ── THE RING: her battle on the map, with the navy called to it (a wide screen: the sheet stands beside the map) ──
test.describe('her battle on the map, 1280×800, English', () => {
  test.use({ viewport: WIDE, locale: 'en-US' })

  test('the ring is hers; a press opens the fight with both sides; the navy ship called to it is on her way, then there', async ({ page, request, baseURL }) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await openCargoCard(page, 'board')
    await page.screenshot({ path: path.join(SHOTS, 'ring-1280-en-1-card.png') })
    const card = await attack(page, { foe: 'Weaker', funds: 'Light' })
    await expect(card).toHaveAttribute('data-status', 'FIGHTING')
    await holdsItsWidth(page.getByTestId('cargo-sheet'), 'the Attack section and the card, 1280 px')
    await page.screenshot({ path: path.join(SHOTS, 'ring-1280-en-2-started.png') })
    // the ring: on the map, hers
    const ring = page.locator('[data-testid="map-fight-ring"][data-kind="BATTLE"]').first()
    await expect(ring, 'her battle is ringed on the map').toBeVisible({ timeout: 30_000 })
    await expect(ring).toHaveAttribute('data-mine', 'true')
    const box = (await ring.locator('circle').first().boundingBox())!
    // press it: on the ring's own stroke side of the disc if a hull stands on the centre
    for (const [dx, dy] of [[0, 0], [-0.6, 0], [0, 0.6], [0, -0.6], [0.6, 0]] as const) {
      await page.mouse.click(box.x + box.width / 2 + (dx * box.width) / 2, box.y + box.height / 2 + (dy * box.height) / 2)
      if (await page.getByTestId('fight-sheet').isVisible().catch(() => false)) break
    }
    const sheet = page.getByTestId('fight-sheet')
    await expect(sheet, 'a press inside the ring opens the fight').toBeVisible()
    await expect(sheet).toHaveAttribute('data-mine', 'true')
    await expect(page.getByTestId('fight-side-attacker').getByTestId('fight-side-fleet')).toHaveText('Gaivota')
    // the defender's side: the cargo ship, and the navy ship that was called (two rows: she is on the list from the press)
    const defenders = page.getByTestId('fight-side-defender').getByTestId('fight-side-row')
    await expect(defenders).toHaveCount(2)
    await expect(page.getByTestId('fight-side-defender')).toContainText('Cargo ship 1')
    await expect(page.getByTestId('fight-side-defender')).toContainText('Navy ship 1')
    // she is on her way, then there
    await expect(defenders.nth(1)).toHaveAttribute('data-here', 'true', { timeout: 60_000 })
    await expect(sheet.getByTestId('battle-card')).toBeVisible()
    await expect(sheet.getByTestId('fight-log-joined')).toHaveCount(1, { timeout: 60_000 })
    await page.screenshot({ path: path.join(SHOTS, 'ring-1280-en-3-fight-sheet.png') })
    await holdsItsWidth(sheet, 'her fight opened from the ring, 1280 px')
  })
})

// ── BREAK-OFF: Flee from the next round, and away ──
for (const [size, lang, tag] of [
  [WIDE, 'ko-KR', '1280-ko'],
  [PHONE, 'ko-KR', '390-ko'],
  [SMALL, 'ko-KR', '320-ko'],
] as const) {
  test.describe(`Flee and the break-off, ${size.width}×${size.height}, ${lang}`, () => {
    test.use({ viewport: size, locale: lang })

    test('Flee is kept from the next round; the round she runs she fires nothing; she is away, with no gold; nothing is cut', async ({ page, request, baseURL }) => {
      test.setTimeout(300_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      const ko = lang === 'ko-KR'
      await openCargoCard(page, 'flee')
      const card = await attack(page, ko ? { foe: '약함', funds: '적음' } : { foe: 'Weaker', funds: 'Light' })
      await expect(card).toHaveAttribute('data-status', 'FIGHTING')
      await expect(page.getByTestId('battle-clock')).toHaveText(/^\d+:\d\d$/)
      await holdsItsWidth(page.getByTestId('cargo-sheet'), `the card just opened, ${tag}`)
      const log = page.getByTestId('fight-log')
      // a first round is fought under Fight
      await expect.poll(async () => Number(await log.getAttribute('data-rounds')), { timeout: 40_000 }).toBeGreaterThanOrEqual(1)
      await card.scrollIntoViewIfNeeded()
      await page.screenshot({ path: path.join(SHOTS, `flee-${tag}-1-fighting.png`) })
      // ── FLEE: the stance changes at once on the card, and takes hold from the NEXT round ──
      const before = await logRows(page)
      const flee = page.getByTestId('battle-stance-FLEE')
      await flee.scrollIntoViewIfNeeded()
      await flee.click()
      await expect(page.getByTestId('battle-refusal')).toHaveCount(0)
      // (in this world a side that runs is away for certain, so the card may already show the end: her stance is asked only while it is still fought)
      await expect.poll(async () => (await card.getAttribute('data-stance')) === 'FLEE' || (await card.getAttribute('data-status')) !== 'FIGHTING', { timeout: 20_000 }).toBe(true)
      // ── AWAY: BROKEN_OFF, the result said, no gold ──
      await expect(card).toHaveAttribute('data-status', 'BROKEN_OFF', { timeout: 60_000 })
      await expect(log).toHaveAttribute('data-end', 'FLED')
      const rows = await logRows(page)
      // every round fought before the press stands as it was, and none of them was a run
      for (const [i, r] of before.entries()) {
        expect(rows[i], `round ${r.round} was fought before the press: it is not rewritten`).toEqual(r)
        expect(r.you).not.toBe('run')
      }
      // the rounds after it: she ran, and fired nothing; and it ended in the first of them (a side that runs is away for certain here)
      expect(rows.length, 'the stance took hold from the next round, not the one being fought').toBeGreaterThan(before.length)
      for (const r of rows.slice(before.length)) expect(r.you, `round ${r.round}: she ran`).toBe('run')
      barsOnlyFall(rows)
      await expect(page.getByTestId('fight-log-result')).toContainText(ko ? '도주 성공' : 'Fled')
      expect(num(await page.getByTestId('battle-loot').textContent()), 'a break-off takes no gold').toBe(0)
      await expect(page.getByTestId('battle-clock')).toHaveCount(0)
      await expect(page.locator('[data-testid^="battle-stance-"]')).toHaveCount(0)
      if (ko) {
        await expect(page.getByTestId('battle-card')).toContainText('전리품')
        await expect(page.getByTestId('battle-card')).toContainText('선원 손실')
        // the navy's line is in her language too (the server's sentence is English)
        await expect(page.getByTestId('battle-navy')).not.toContainText(/[A-Za-z]{4,}/)
      }
      await page.getByTestId('fight-log-result').scrollIntoViewIfNeeded()
      await page.screenshot({ path: path.join(SHOTS, `flee-${tag}-2-away.png`) })
      await holdsItsWidth(page.getByTestId('cargo-sheet'), `the break-off, ${tag}`)
      // her ship by her whole name
      await expect(page.getByTestId('fight-log-ship')).toHaveCount(1)
      await expect(page.getByTestId('fight-log-ship').first()).toContainText('Gaivota')
    })
  })
}

// a failure prints what the page's console said in error (an RPC that raised is said there, with its SQL error)
test.afterEach(async ({ page }, info) => {
  const errors = said.get(page) ?? []
  if (info.status !== info.expectedStatus && errors.length > 0) console.log(`the page's console, in error:\n${errors.join('\n')}`)
})
