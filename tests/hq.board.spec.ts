import { test, expect, type Page } from '@playwright/test'
import { reachable, ready, WORLD_BOOT_MS } from './appReady.fixture'
import { serveHqLit } from './hqLit.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ'S COMMAND BOARD (owner, 2026-11-23: "all the work (activities) are done in HQ … choosing best options available, finding best
// options"; docs/design/hq-command-2026-11-23.md), and its RANK STRIP (docs/design/hq-corp-2026-11-24.md, slice H2).
//
// THE BOARD IS THE SERVER'S (world.hq_board, 0480). The client's own ranking and its own rate (v1) are deleted, so there is no pure
// ranking test here: the order is asserted on the served cards.
// Browser (the shipped world with production's switches lit, the sea limits dark; a fresh company, one barca at Lisbon):
//   - the Rank strip: her rank and its bar, what the next level opens, the net per hour as served; no purse figure on the board
//   - the best moves: the served trade cards stand by coin per hour, the best first; one press queues the trip, HQ kept
//   - an idle fleet glows and shows its best card inline
//   - the board's switch dark: one line, "Board off", no card and no rate, and the strip keeps its height
//   - no sideways scroll at 320, 390 and 1280
// ═══════════════════════════════════════════════════════════════════════════════════════════════

async function openHq(page: Page, width: number, height: number, served = true, jobs = false, contracts = false, race = false, roles = false) {
  await page.setViewportSize({ width, height })
  await serveHqLit(page, { served, jobs, contracts, race, roles })
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('hq-board')).toBeVisible({ timeout: WORLD_BOOT_MS })
}

const sideScroll = (page: Page) =>
  page.evaluate(() => {
    const over = [...document.querySelectorAll('[data-sheet], body, html')].some((el) => el.scrollWidth > el.clientWidth + 1)
    return over || document.documentElement.scrollWidth > window.innerWidth
  })

/** The strip's box and its per-hour slot's box, in whole pixels. */
const stripBoxes = (page: Page) =>
  page.evaluate(() => {
    const h = (id: string) => Math.round(document.querySelector(`[data-testid="${id}"]`)!.getBoundingClientRect().height)
    return { strip: h('hq-bridge'), slot: h('hq-bridge-rate-slot') }
  })

test.describe('the Rank strip (H2)', () => {
  for (const glass of [
    { width: 390, height: 844 },
    { width: 1440, height: 900 },
  ]) {
    test(`her rank, the next opening and the served net per hour at ${glass.width}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await openHq(page, glass.width, glass.height)
      await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'served', { timeout: 180_000 })
      const strip = page.getByTestId('hq-bridge')
      await expect(strip).toBeVisible()

      // THE RANK: the title's name, its step and the bar to the next
      const rank = page.getByTestId('hq-rank')
      await expect(page.getByTestId('hq-rank-name')).toHaveText(/\S/, { timeout: 120_000 })
      expect(Number(await rank.getAttribute('data-level'))).toBeGreaterThanOrEqual(1)
      await expect(rank.getByRole('meter')).toHaveAccessibleName(/^Rank \d+ \/ \d+$/)
      // THE NEXT OPENING: a served level_perks step, named with its level (level_unlocks_enabled is lit in this world)
      const next = page.getByTestId('hq-rank-next')
      await expect(next).toHaveText(/\S/)
      expect(Number(await next.getAttribute('data-level')), 'no next level_perks opening on the strip').toBeGreaterThan(1)

      // NET PER HOUR: the served figure, drawn as served ("+N / hour"), green or red, in its own held slot
      const rate = page.getByTestId('hq-bridge-rate')
      await expect(rate).toBeVisible({ timeout: 180_000 })
      await expect(rate).toHaveAttribute('data-span', '24h')
      const perHour = Number(await rate.getAttribute('data-per-hour'))
      expect(Number.isFinite(perHour)).toBe(true)
      const digits = (await rate.innerText()).replace(/[^0-9]/g, '')
      expect(Number(digits), 'the figure drawn is not the served per-hour').toBe(Math.abs(Math.round(perHour)))
      await expect(rate).toHaveText(/\/ hour$/)
      const boxes = await stripBoxes(page)
      expect(boxes.slot, "the per-hour slot is not the figure's own line").toBe(28)

      // NO PURSE ON THE BOARD (the top bar's figure, said once), and none of the old bridge's tiles
      for (const id of ['hq-bridge-purse', 'hq-bridge-fleets', 'hq-bridge-next', 'hq-bridge-threat']) await expect(page.getByTestId(id)).toHaveCount(0)
      // the board is the first thing seen: it begins on the first glass, above the city's buildings
      const board = (await page.getByTestId('hq-board').boundingBox())!
      const places = (await page.getByTestId('city-buildings').boundingBox())!
      expect(board.y).toBeLessThan(glass.height)
      expect(board.y).toBeLessThan(places.y)
      // the strip stands whole inside the glass
      const box = (await strip.boundingBox())!
      expect(box.x).toBeGreaterThanOrEqual(0)
      expect(box.x + box.width).toBeLessThanOrEqual(glass.width + 1)
      expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)

      // AN IDLE FLEET GLOWS AND OFFERS ITS BEST CARD INLINE (the same card as the board's best for her)
      const trades = page.locator('[data-testid="hq-moves"] [data-testid="hq-move"][data-kind="trade"]')
      await expect(trades.first()).toBeVisible({ timeout: 180_000 })
      const idle = page.locator('[data-testid="hq-fleet"][data-job="idle"]').first()
      await expect(idle).toBeVisible()
      const inline = idle.getByTestId('hq-fleet-best').getByTestId('hq-move')
      await expect(inline).toBeVisible()
      await expect(inline).toHaveAttribute('data-kind', 'trade')
      await expect(inline).toHaveAttribute('data-good', (await trades.first().getAttribute('data-good'))!)
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/rank-${glass.width}.png`, fullPage: true })
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/rank-top-${glass.width}.png` })
    })

    test(`the board's switch dark: "Board off", no card, no rate, the strip's height kept at ${glass.width}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await openHq(page, glass.width, glass.height, false)
      await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'off', { timeout: 180_000 })
      await expect(page.getByTestId('hq-board-off')).toHaveText('Board off')
      await expect(page.getByTestId('hq-move')).toHaveCount(0)
      await expect(page.getByTestId('hq-bridge-rate')).toHaveCount(0)
      // the rank is drawn all the same (world.levels is not the board's read)
      await expect(page.getByTestId('hq-rank-name')).toHaveText(/\S/, { timeout: 120_000 })
      // the per-hour line's room is held with no figure in it
      const boxes = await stripBoxes(page)
      expect(boxes.slot, 'the empty per-hour slot gave its room up').toBe(28)
      // her fleets stand under it as before
      await expect(page.locator('[data-testid="hq-fleet"]').first()).toBeVisible()
      expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/off-${glass.width}.png`, fullPage: true })
    })
  }
})

// 0480: THE BOARD FROM THE SERVER (hq_board_enabled lit): world.hq_board() ranks every move; each card names its own act and one press
// commits it through the desk's own door (the trip: planLines and cmd.issue_lines), HQ kept; a trade card wears its risk as a mark.
test.describe('the board from the server (0480, lit)', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('served, ranked by coin per hour, the risk marked, and one press queues the trip', async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    test.setTimeout(600_000)
    await openHq(page, 390, 844, true)
    await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'served', { timeout: 180_000 })
    await expect(page.getByTestId('hq-bridge-rate')).toHaveAttribute('data-span', '24h')

    const trades = page.locator('[data-testid="hq-moves"] [data-testid="hq-move"][data-kind="trade"]')
    await expect(trades.first()).toBeVisible({ timeout: 180_000 })
    const top = trades.first()
    await expect(top).toHaveAttribute('data-served', 'true')
    await expect(top).toHaveAttribute('data-act', 'cmd.issue_lines')
    await expect(top.getByTestId('hq-move-risk')).toBeVisible()
    expect(['shield', 'pirate']).toContain(await top.getByTestId('hq-move-risk').getAttribute('data-risk'))
    const rates = (await trades.evaluateAll((els) => els.map((e) => e.getAttribute('data-per-hour') ?? ''))).filter((r) => r !== '').map(Number)
    expect(rates.length, 'served trade cards with coin an hour').toBeGreaterThan(0)
    expect(rates, 'the server ranks trade runs by coin an hour').toEqual([...rates].sort((a, b) => b - a))

    // ONE PRESS: the trip is queued for her fleet and HQ stays; no refusal stands under the card
    const fleet = (await top.getAttribute('data-fleet'))!
    await top.click()
    await expect(page.locator(`[data-testid="hq-fleet"][data-fleet="${fleet}"]`)).not.toHaveAttribute('data-job', 'idle', { timeout: 120_000 })
    await expect(page).toHaveURL(/\/city/)
    await expect(page.getByTestId('hq-move-refusal')).toHaveCount(0)
  })
})

// 0481: STANDING FLEET JOBS (fleet_jobs_enabled lit, the board served): each fleet row carries her job's setter; Best gives her the best
// run and her row then wears the job's mark; a served trade card's Repeat sends the trip and keeps it as her fixed route (working).
test.describe('standing fleet jobs (0481, lit)', () => {
  for (const glass of [
    { width: 390, height: 844 },
    { width: 1280, height: 800 },
  ]) {
    test(`a fleet row sets her job, a trade card repeats its trip, and nothing leaves the glass at ${glass.width}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await openHq(page, glass.width, glass.height, true, true)
      const control = page.getByTestId('hq-job-control').first()
      await expect(control).toBeVisible({ timeout: 180_000 })
      const fleet = (await control.getAttribute('data-fleet'))!
      await control.getByTestId('hq-job-set-best').click()
      const mark = page.locator(`[data-testid="hq-job-control"][data-fleet="${fleet}"] [data-testid="hq-job"]`)
      await expect(mark).toHaveAttribute('data-kind', 'best', { timeout: 120_000 })
      await expect(page.getByTestId('hq-job-refusal')).toHaveCount(0)
      // a served trade card's Repeat: the trip goes now (the card's own act) and stays her job as a fixed route (its course her voyage)
      const card = page.locator(`[data-testid="hq-moves"] li:has([data-testid="hq-move"][data-kind="trade"][data-served="true"][data-fleet="${fleet}"])`).first()
      await expect(card).toBeVisible({ timeout: 180_000 })
      await card.getByTestId('hq-move-repeat').click()
      await expect(mark).toHaveAttribute('data-kind', 'fixed', { timeout: 120_000 })
      await expect(mark).toHaveAttribute('data-state', 'working')
      await expect(page.getByTestId('hq-move-repeat-refusal')).toHaveCount(0)
      await expect(page.getByTestId('hq-move-refusal')).toHaveCount(0)
      expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)
      const small = await page.evaluate(() =>
        [...document.querySelectorAll('[data-testid="hq-job-control"] button, [data-testid="hq-move-repeat"]')]
          .map((b) => b.getBoundingClientRect())
          .filter((r) => r.width > 0 && (r.height < 43.5 || r.width < 43.5)).length,
      )
      expect(small, 'job presses under 44 px').toBe(0)
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/jobs-${glass.width}.png`, fullPage: true })
    })
  }
})

// A STOPPED JOB SAYS WHY IN PLAIN WORDS (owner row 381: the away card's chip read "E_LEG_TOO_FAR"). The world: the board and the jobs
// lit, and every job written is stopped on E_LEG_TOO_FAR by a trigger of this spec's own (the image only; no such trigger ships). She
// sets a job; While away then lists it stopped: the chip is the code's label ("Range"), its sentence stands under her name, and no
// code is printed anywhere on the board.
const STOP_EVERY_JOB = `
  update public.world_config set value = 'true'::jsonb where key in ('hq_board_enabled', 'fleet_jobs_enabled', 'standing_routes_enabled', 'land_enabled', 'level_unlocks_enabled');
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  create function public.spec_stop_job() returns trigger language plpgsql as $$ begin new.paused_reason := 'E_LEG_TOO_FAR'; return new; end $$;
  create trigger spec_stop_job before insert or update on public.fleet_jobs for each row execute function public.spec_stop_job();`

test.describe('a stopped job (owner row 381)', () => {
  for (const glass of [
    { width: 390, height: 844 },
    { width: 1440, height: 900 },
  ]) {
    test(`its chip and its line are plain words, and no code is printed on the board at ${glass.width}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await page.setViewportSize(glass)
      await serveWorldImage(page, await patchedWorldImage('hq-job-stopped', async (pg) => void (await pg.exec(STOP_EVERY_JOB))))
      await page.goto('city')
      await ready(page)
      await expect(page.getByTestId('hq-board')).toBeVisible({ timeout: WORLD_BOOT_MS })
      const control = page.getByTestId('hq-job-control').first()
      await expect(control).toBeVisible({ timeout: 180_000 })
      await control.getByTestId('hq-job-set-best').click()
      const row = page.locator('[data-testid="hq-away-job"][data-state="stopped"]')
      await expect(row).toBeVisible({ timeout: 120_000 })
      await expect(row, 'the world did not stop her job on the code under test').toHaveAttribute('data-code', 'E_LEG_TOO_FAR')
      await expect(row.getByTestId('hq-away-stopped')).toHaveText('Range')
      await expect(row.getByTestId('hq-away-why')).toHaveText('Leg too far.')
      const text = await page.getByTestId('hq-board').innerText()
      expect(text.match(/E_[A-Z_]+/g) ?? [], 'a code is printed on the HQ board').toEqual([])
      expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/stopped-${glass.width}.png`, fullPage: true })
    })
  }
})

// 0483: COURIER CONTRACTS (contracts_enabled lit, the board served, one house contract posted at Lisbon): her board offers it as a
// `contract` card (the pact, Carry <good> to <harbour>, the reward and coin an hour, the collateral and the risk as marks) and one press
// takes it and sends her: the fleet leaves Lisbon, HQ stays, no refusal. The Requests face's door is "Post a contract".
test.describe('courier contracts (0483, lit)', () => {
  for (const glass of [
    { width: 390, height: 844 },
    { width: 1280, height: 800 },
  ]) {
    test(`a contract card takes it in one press, and nothing leaves the glass at ${glass.width}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await openHq(page, glass.width, glass.height, true, false, true)
      await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'served', { timeout: 180_000 })
      await expect(page.locator('[data-testid="hq-move"]').first()).toBeVisible({ timeout: 180_000 })
      await page.getByTestId('hq-filter-contract').click()
      const card = page.locator('[data-testid="hq-moves"] [data-testid="hq-move"][data-kind="contract"]').first()
      await expect(card).toBeVisible({ timeout: 180_000 })
      await expect(card).toHaveAttribute('data-served', 'true')
      await expect(card).toHaveAttribute('data-act', 'cmd.take_contract')
      await expect(card.getByTestId('hq-move-risk')).toBeVisible()
      await expect(card.getByTestId('hq-move-collateral')).toBeVisible()
      expect(Number(await card.getAttribute('data-per-hour'))).toBeGreaterThan(0)
      expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/contracts-${glass.width}.png`, fullPage: true })
      const fleet = (await card.getAttribute('data-fleet'))!
      await card.click()
      await expect(page.locator(`[data-testid="hq-fleet"][data-fleet="${fleet}"]`)).not.toHaveAttribute('data-job', 'idle', { timeout: 120_000 })
      await expect(page).toHaveURL(/\/city/)
      await expect(page.getByTestId('hq-move-refusal')).toHaveCount(0)
    })
  }
})

// 0484: THE COUNTRY RACE (nation_race_enabled lit, the board served, Castile leading three contested harbours): under the bridge her
// country's flag and place, the countries as bars of the cities they lead, her influence and the week's clock; nothing leaves the glass.
// The map's filter offers Race, and with it on each led city is ringed (a rival's: amber).
test.describe('the country race (0484, lit)', () => {
  for (const glass of [
    { width: 320, height: 640 },
    { width: 1280, height: 800 },
  ]) {
    test(`the race strip on HQ and the Race layer on the map at ${glass.width}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await openHq(page, glass.width, glass.height, true, false, false, true)
      const strip = page.getByTestId('hq-race')
      await expect(strip).toBeVisible({ timeout: 180_000 })
      await expect(strip).toHaveAttribute('data-nation', 'PRT')
      await expect(page.getByTestId('hq-race-place')).toBeVisible()
      await expect(page.locator('[data-testid="hq-race-nations"] li[data-nation="ESP"]')).toBeVisible()
      expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/race-${glass.width}.png`, fullPage: true })
      await page.goto('map')
      await ready(page)
      await page.getByTestId('map-layer-filter').click()
      await page.getByTestId('map-layer-race').click()
      await expect(page.getByTestId('map-layer-filter')).toHaveAttribute('data-layer', 'race')
      await expect(page.locator('[data-testid="map-event-mark"][data-code="RACE_RIVAL"]').first()).toBeAttached({ timeout: 60_000 })
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/race-map-${glass.width}.png` })
    })
  }
})

// 0485: A HULL'S ROLE (ship_roles_enabled lit, the board served; the first slot opens at her first hull in this world): the board's role card
// names the best role for her barca (Guard: nothing she does yet asks another) and one press sets it; her fleet row's chips show it on, and
// one press there changes it (Fast). Nothing leaves the glass, and every press is 44 px.
test.describe("a hull's role (0485, lit)", () => {
  for (const glass of [
    { width: 320, height: 640 },
    { width: 1280, height: 800 },
  ]) {
    test(`the role card and the fleet row's chips at ${glass.width}`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await openHq(page, glass.width, glass.height, true, false, false, false, true)
      const card = page.locator('[data-testid="hq-move"][data-kind="role"]')
      await expect(card).toBeVisible({ timeout: 180_000 })
      await expect(card).toHaveAttribute('data-act', 'cmd.set_ship_role')
      await expect(page.locator('[data-testid="hq-move-role"]')).toHaveAttribute('data-role', 'guard')
      const hull = page.getByTestId('hq-role-hull').first()
      await expect(hull).toHaveAttribute('data-role', '')
      await expect(hull.getByTestId('hq-role-set-guard')).toHaveAttribute('data-best', 'true')
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/roles-${glass.width}.png`, fullPage: true })
      await card.click()
      await expect(hull).toHaveAttribute('data-role', 'guard', { timeout: 60_000 })
      await expect(hull.getByTestId('hq-role-set-guard')).toHaveAttribute('aria-pressed', 'true')
      await expect(card).toHaveCount(0, { timeout: 60_000 })
      await hull.getByTestId('hq-role-set-fast').click()
      await expect(hull).toHaveAttribute('data-role', 'fast', { timeout: 60_000 })
      await expect(page.getByTestId('hq-role-refusal')).toHaveCount(0)
      expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)
      const small = await page.evaluate(() =>
        [...document.querySelectorAll('[data-testid="hq-board"] button')]
          .map((b) => b.getBoundingClientRect())
          .filter((r) => r.width > 0 && (r.height < 43.5 || r.width < 43.5)).length,
      )
      expect(small, 'presses under 44 px').toBe(0)
      if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/roles-set-${glass.width}.png`, fullPage: true })
    })
  }
})

for (const glass of [
  { width: 320, height: 640 },
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
]) {
  test(`no sideways scroll and every name whole at ${glass.width}`, async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    test.setTimeout(600_000)
    await openHq(page, glass.width, glass.height)
    await expect(page.locator('[data-testid="hq-move"]').first()).toBeVisible({ timeout: 180_000 })
    expect(await sideScroll(page), 'the HQ scrolls sideways').toBe(false)
    // no card, chip or row stands past the glass, and no name is cut
    const out = await page.evaluate((w) => {
      const bad: string[] = []
      for (const el of document.querySelectorAll('[data-testid="hq-board"] *')) {
        const r = el.getBoundingClientRect()
        if (r.width > 0 && (r.right > w + 1 || r.left < -1)) bad.push(`${el.getAttribute('data-testid') ?? el.tagName} ${Math.round(r.left)}..${Math.round(r.right)}`)
        if (el instanceof HTMLElement && getComputedStyle(el).textOverflow === 'ellipsis' && el.scrollWidth > el.clientWidth) bad.push(`cut: ${el.textContent}`)
      }
      return bad
    }, glass.width)
    expect(out, 'past the glass or cut').toEqual([])
    // every press on the board is 44 px at least
    const small = await page.evaluate(() =>
      [...document.querySelectorAll('[data-testid="hq-board"] button')]
        .map((b) => b.getBoundingClientRect())
        .filter((r) => r.width > 0 && (r.height < 43.5 || r.width < 43.5)).length,
    )
    expect(small, 'presses under 44 px').toBe(0)
  })
}
