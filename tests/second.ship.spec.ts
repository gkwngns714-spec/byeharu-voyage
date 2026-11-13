import { test, expect, type Locator, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// S2 + S3 — A SECOND SHIP WITHIN REACH (docs/SECOND_SHIP.md; migration 0363; owner rows 180, 305, 316)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The shipped world, a new company at Lisbon, at 390×844 and 320×844 (and the played flow at 1280×800, where the goal
// card stands on every face of the desk):
//   1. THE GOAL IS ON THE FIRST SCREEN. Trade's goal card reads "Second ship 0 / 4" on its second line, in place of the
//      two tracks, at the card's one height (44 px): one line, no word broken, nothing sideways.
//   2. THE BARCA NEEDS NO PARTS. Her sheet reads "Ready 0 / 4": four goods, no part. Under the totals stands ONE press,
//      "Plan trip", carrying the four sellers nearest first; it opens the Map's route builder with those stops kept and
//      Lisbon last. Nothing is sent: Final is still her press.
//   3. THE PLAYED FLOW, on a world where her hold already carries the four goods (a trigger on her founding ship loads
//      them through public.fleet_load): Store → Build (named) → Hire crew · 8. Three presses and a name. With two
//      ships the goal card reads the two tracks again.
// The Korean words are read on the same screens. The server half: proof 65 and the migration's own self-assert.
// A hull that still takes parts (Make parts before Store): tests/yard.plan.spec.ts.

const PHONES = [
  { width: 390, height: 844 },
  { width: 320, height: 844 },
] as const

/** The Barca's four hull goods in her hold, counted from the recipe the world ships. */
function ladenHold(): Promise<Buffer> {
  return patchedWorldImage('second-ship-laden', async (pg) => {
    await pg.exec(`
      create function public.spec_second_ship_laden() returns trigger
      language plpgsql security definer set search_path = public, pg_temp as $$
      declare
        g record;
      begin
        if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
        for g in select gd.code, hg.qty from public.hull_recipe_goods hg join public.goods gd on gd.id = hg.good_id where hg.class_code = 'barca' loop
          perform public.fleet_load(new.fleet_id, g.code, g.qty, 1);
        end loop;
        return null;
      end $$;
      create trigger spec_second_ship_laden after insert on public.ships
        for each row when (new.is_flagship) execute function public.spec_second_ship_laden();
    `)
  })
}

async function noSideways(page: Page, what: string) {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(over, `${what} scrolls sideways by ${over} px`).toBeLessThanOrEqual(0)
}

/** No word under `root` is broken inside itself, and no text is cut with an ellipsis. */
async function wholeWords(root: Locator, what: string) {
  const bad = await root.evaluate((el) => {
    const out: string[] = []
    const range = document.createRange()
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT)
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const text = node.textContent ?? ''
      if (text.includes('…') && !/^…$/.test(text.trim())) out.push(`cut: "${text}"`)
      for (const m of text.matchAll(/\S+/g)) {
        range.setStart(node, m.index)
        range.setEnd(node, m.index + m[0].length)
        if (range.getClientRects().length > 1) out.push(`broken: "${m[0]}" in "${text}"`)
      }
    }
    return out
  })
  expect(bad, `${what}: a word is broken or a name is cut`).toEqual([])
}

/** The goal card on Trade: its second line is the second ship, on one line, at the card's one height. */
async function goalCard(page: Page, words: RegExp) {
  await page.goto('command')
  await ready(page)
  const card = page.getByTestId('goal-card')
  await expect(card).toBeVisible({ timeout: 120_000 })
  const line = card.getByTestId('goal-second-ship')
  await expect(line).toBeVisible({ timeout: 120_000 })
  await expect(line).toHaveText(words)
  await expect(card.getByTestId('goal-tracks')).toHaveCount(0)
  const box = await card.boundingBox()
  expect(Math.round(box!.height), 'the card is not its one fixed height').toBe(44)
  const lines = await line.evaluate((el) => {
    const range = document.createRange()
    range.selectNodeContents(el)
    return new Set([...range.getClientRects()].map((r) => Math.round(r.top))).size
  })
  expect(lines, 'the second ship takes more than one line').toBe(1)
  const inside = await line.evaluate((el) => el.scrollWidth <= el.clientWidth + 1)
  expect(inside, 'the second ship runs out of the card').toBe(true)
  await wholeWords(card, 'the goal card')
  await noSideways(page, 'Trade')
  return card
}

async function barcaSheet(page: Page, buildTab: string): Promise<Locator> {
  await page.goto('port')
  await ready(page)
  await page.getByRole('tablist').getByRole('tab', { name: buildTab, exact: true }).click()
  await expect(page.getByTestId('port-yard')).toBeVisible({ timeout: 60_000 })
  await page.getByTestId('yard-now').getByTestId('hull-barca').click()
  const tray = page.getByTestId('yard-tray')
  await expect(tray).toBeVisible()
  // the plan is whole once the sellers' prices have landed
  await expect(tray.getByTestId('yard-total')).toHaveAttribute('data-cost', /^\d+$/, { timeout: 60_000 })
  return tray
}

for (const glass of PHONES) {
  test.describe(`a second ship within reach at ${glass.width}×${glass.height}`, () => {
    test.use({ viewport: glass, deviceScaleFactor: 2 })

    test('the goal card counts it, the Barca takes four goods and no part, and Plan trip opens the route with the four sellers', async ({ page, request, baseURL }, info) => {
      test.setTimeout(480_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)

      // 1. the first screen
      await goalCard(page, /^Second ship 0 \/ 4$/)
      await page.screenshot({ path: info.outputPath('1-trade.png') })

      // 2. her sheet: four lines, no part
      const tray = await barcaSheet(page, 'Build')
      await expect(tray.getByTestId('yard-ready')).toHaveText('Ready 0 / 4')
      await expect(tray.getByTestId('yard-next')).toHaveText('Build')
      await expect(tray.getByTestId('yard-next')).toBeDisabled()
      await expect(tray.locator('[data-testid^="yard-part-"]')).toHaveCount(0)
      await expect(tray.locator('[data-testid^="yard-good-"]')).toHaveCount(4)
      const cost = Number(await tray.getByTestId('yard-total').getAttribute('data-cost'))
      expect(cost, 'the total is not the labour plus four goods').toBeGreaterThan(15_000)
      expect(cost, 'a second Barca is not within half her purse').toBeLessThan(20_000)
      await expect(tray.getByTestId('yard-weight')).toHaveAttribute('data-fits', 'true')

      // the one press under the totals: the four sellers, nearest first
      const trip = tray.getByTestId('yard-plan-trip')
      await expect(trip).toContainText('Plan trip')
      await expect(trip).toContainText(/4\s*stops/)
      await expect(trip).toHaveAttribute('data-stops', 'FNC LAR PTH BER')
      const weight = await tray.getByTestId('yard-weight').boundingBox()
      const tripBox = await trip.boundingBox()
      const firstGood = await tray.locator('[data-testid^="yard-good-"]').first().boundingBox()
      expect(tripBox!.y, 'Plan trip does not stand under the totals').toBeGreaterThanOrEqual(weight!.y + weight!.height - 1)
      expect(tripBox!.y + tripBox!.height, 'Plan trip does not stand above the lines').toBeLessThanOrEqual(firstGood!.y + 1)
      await wholeWords(tray, 'the Barca\'s sheet')
      await noSideways(page, 'the Barca\'s sheet')
      await page.screenshot({ path: info.outputPath('2-sheet.png') })

      // 3. the press: the Map's route builder, the four sellers kept and Lisbon last; nothing is sent
      await trip.click()
      await expect(page).toHaveURL(/\/map$/)
      const bar = page.getByTestId('route-bar')
      await expect(bar).toBeVisible({ timeout: 120_000 })
      const legs = bar.getByTestId('route-legs-box')
      for (const name of ['Funchal', 'La Rochelle', 'Portsmouth', 'Bergen', 'Lisbon']) await expect(legs).toContainText(name)
      // every leg is the server's to judge: once it has, the trip can be sent, and it is not sent by this spec
      await expect(bar.getByTestId('route-final')).toBeEnabled({ timeout: 120_000 })
      await expect(bar.getByTestId('route-refusal')).toHaveCount(0)
      await noSideways(page, 'the route builder')
      await page.screenshot({ path: info.outputPath('3-route.png') })
      await bar.getByTestId('route-cancel').click()
      await expect(bar).toHaveCount(0)
    })
  })
}

test.describe('the played flow at 1280×800', () => {
  test.use({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2 })

  test('Store, Build, Hire crew: three presses and a name; then the goal card reads the tracks again', async ({ page, request, baseURL }, info) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await serveWorldImage(page, await ladenHold())
    const tray = await barcaSheet(page, 'Build')
    const next = tray.getByTestId('yard-next')
    const readyLine = tray.getByTestId('yard-ready')
    let presses = 0

    // 1. the four goods are on board and there is no part to make: Store. Nothing is left to fetch, so no trip is offered.
    await expect(next).toHaveAttribute('data-step', 'store')
    await expect(next).toHaveText('Store')
    await expect(readyLine).toHaveText('Ready 0 / 4')
    await expect(tray.getByTestId('yard-plan-trip')).toHaveCount(0)
    await next.click()
    presses++

    // 2. all four lines are there: Build, once she is named
    await expect(next).toHaveAttribute('data-step', 'build', { timeout: 60_000 })
    await expect(readyLine).toHaveText('Ready 4 / 4')
    await tray.getByTestId('yard-name').fill('Segunda')
    await expect(next).toBeEnabled()
    await page.screenshot({ path: info.outputPath('2-build.png') })
    await next.click()
    presses++

    // 3. she is laid down with no crew: the button is the hire, and the fleet is full
    await expect(next).toHaveAttribute('data-step', 'hire', { timeout: 60_000 })
    await expect(next).toHaveText('Hire crew · 8')
    await expect(tray.getByTestId('yard-fleet-full')).toHaveText('Fleet full')
    await next.click()
    presses++
    await expect(page).toHaveURL(/\/command$/)
    await expect(page.getByTestId('port-inn')).toBeVisible({ timeout: 60_000 })
    expect(presses, 'the flow is three presses and a name').toBe(3)

    // with two ships the card's second line is the two tracks again
    const card = page.getByTestId('goal-card')
    await expect(card.getByTestId('goal-tracks')).toBeVisible({ timeout: 60_000 })
    await expect(card.getByTestId('goal-second-ship')).toHaveCount(0)
    await expect(card.getByTestId('goal-tracks')).toContainText(/Trading \d+\/\d+ · Exploration \d+\/\d+/)
    await page.screenshot({ path: info.outputPath('3-two-ships.png') })
  })
})

for (const glass of PHONES) {
  test.describe(`a second ship in Korean at ${glass.width}×${glass.height}`, () => {
    test.use({ viewport: glass, deviceScaleFactor: 2, locale: 'ko-KR' })

    test('the card, the sheet and the trip read in Korean', async ({ page, request, baseURL }, info) => {
      test.setTimeout(480_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await goalCard(page, /^두 번째 배 0 \/ 4$/)
      await page.screenshot({ path: info.outputPath('1-trade-ko.png') })
      const tray = await barcaSheet(page, '건조')
      await expect(tray.getByTestId('yard-ready')).toHaveText('준비 0 / 4')
      await expect(tray.locator('[data-testid^="yard-part-"]')).toHaveCount(0)
      const trip = tray.getByTestId('yard-plan-trip')
      await expect(trip).toContainText('항로 계획')
      await expect(trip).toContainText(/4\s*곳/)
      await wholeWords(tray, 'the Korean sheet')
      await noSideways(page, 'the Korean sheet')
      await page.screenshot({ path: info.outputPath('2-sheet-ko.png') })
      await trip.click()
      await expect(page).toHaveURL(/\/map$/)
      await expect(page.getByTestId('route-bar')).toBeVisible({ timeout: 120_000 })
      await noSideways(page, 'the Korean route builder')
    })
  })
}
