import { test, expect, type Locator, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'
import { barcaWithParts, putBarcaPartsBack } from './barcaParts.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// S1 — THE YARD PLANS THE BUILD (docs/SECOND_SHIP.md; world.yard_sources re-cut by 0358; owner rows 180, 305, 316)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A new company at Lisbon, at 390×844, 320×844 (the narrowest phone the game holds its lines on) and 1280×800:
//   1. THE SHEET PLANS. The Barca's sheet carries ONE button. With nothing fetched it reads Build, off, beside
//      "Ready 0 / 6". A totals row stands (cost: what is still to buy at the sellers' prices now plus the labour;
//      weight, against her free hold: Fits). The Suit of Sails unfolds into the goods it is made of, and the flax
//      names Riga. The press moves nothing: the row pressed, the totals above it, the tray and its button stay.
//   2. THE PLAYED FLOW, on a world where her hold already carries the seven goods (a trigger on her founding ship
//      loads them through public.fleet_load, the one cargo mover: the image is the shipped one otherwise). The one
//      button walks her through: Make parts (both parts out of the hold, the tar the hull needs set aside) → Store
//      (the hull's goods into this city's storage) → Build (named) → Hire crew · 8, whose press opens the Inn.
//      "Fleet full" is said once she has two ships.
// The Korean words are read on the same sheet. The server half: tests/rpc.yardSources.spec.ts and proof 61.
//
// SINCE 0363 (S2: the Barca needs no parts) the shipped Barca takes four goods and no part. This spec is the proof of
// the sheet for a hull WITH parts, so every test here runs on a copy of the shipped world with her two part rows put
// back (tests/barcaParts.fixture.ts). The shipped Barca's sheet and her three-press flow: tests/second.ship.spec.ts.

const GLASSES = [
  { width: 390, height: 844 },
  { width: 320, height: 844 },
  { width: 1280, height: 800 },
] as const

/** The seven goods of a Barca and her two parts, counted as world.yard_sources serves them (hull + parts). */
function ladenHold(): Promise<Buffer> {
  return patchedWorldImage('yard-plan-laden', async (pg) => {
    await putBarcaPartsBack(pg)
    await pg.exec(`
      create function public.spec_yard_plan_laden() returns trigger
      language plpgsql security definer set search_path = public, pg_temp as $$
      declare
        g record;
      begin
        if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
        for g in
          select gd.code, sum(u.qty) as qty
            from (select hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = 'barca'
                  union all
                  select ir.good_id, ir.qty * hi.qty from public.hull_recipe_items hi
                    join public.item_recipes ir on ir.item_code = hi.item_code where hi.class_code = 'barca') u
            join public.goods gd on gd.id = u.good_id
           group by gd.code
        loop
          perform public.fleet_load(new.fleet_id, g.code, g.qty, 1);
        end loop;
        return null;
      end $$;
      create trigger spec_yard_plan_laden after insert on public.ships
        for each row when (new.is_flagship) execute function public.spec_yard_plan_laden();
    `)
  })
}

async function noSideways(page: Page, what: string) {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(over, `${what} scrolls sideways by ${over} px`).toBeLessThanOrEqual(0)
}

/** No word of the sheet is broken inside itself: every word of every text leaf stands in ONE line box. */
async function noBrokenWord(tray: Locator, what: string) {
  const broken = await tray.evaluate((root) => {
    const out: string[] = []
    const range = document.createRange()
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const text = node.textContent ?? ''
      for (const m of text.matchAll(/\S+/g)) {
        range.setStart(node, m.index)
        range.setEnd(node, m.index + m[0].length)
        if (range.getClientRects().length > 1) out.push(`"${m[0]}" in "${text}"`)
      }
    }
    return out
  })
  expect(broken, `${what}: a word is broken inside itself`).toEqual([])
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

async function box(l: Locator) {
  const b = await l.boundingBox()
  expect(b, 'not on the page').not.toBeNull()
  return b!
}

for (const glass of GLASSES) {
  test.describe(`the yard's plan at ${glass.width}×${glass.height}`, () => {
    test.use({ viewport: glass, deviceScaleFactor: 2 })

    test('a new company: Build is off beside Ready 0 / 6, the totals stand, the sails unfold to Riga, and the press moves nothing', async ({ page, request, baseURL }, info) => {
      test.setTimeout(300_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await serveWorldImage(page, await barcaWithParts())
      const tray = await barcaSheet(page, 'Build')

      // the one button: Build, off, beside the count of ready lines
      const next = tray.getByTestId('yard-next')
      await expect(next).toHaveText('Build')
      await expect(next).toBeDisabled()
      await expect(next).toHaveAttribute('data-step', 'wait')
      await expect(tray.getByTestId('yard-ready')).toHaveText('Ready 0 / 6')

      // the totals: more than the labour alone, and the errand fits her hold
      const cost = Number(await tray.getByTestId('yard-total').getAttribute('data-cost'))
      expect(cost, 'the total is not the labour plus the goods').toBeGreaterThan(15_000)
      expect(cost).toBeLessThan(40_000)
      await expect(tray.getByTestId('yard-total')).toContainText('Total')
      await expect(tray.getByTestId('yard-weight')).toContainText('Weight')
      await expect(tray.getByTestId('yard-weight')).toContainText('Fits')
      await expect(tray.getByTestId('yard-weight')).toHaveAttribute('data-fits', 'true')

      // each line: need, in storage, on board; and while short, the seller with miles, real time and cost
      await expect(tray.getByTestId('yard-good-timber')).toContainText('in storage')
      await expect(tray.getByTestId('yard-good-timber')).toContainText('on board')
      const timber = tray.getByTestId('yard-source-timber')
      await expect(timber).toContainText(/^Buy at /)
      await expect(timber).toContainText(/miles · ~\d+m · /)
      await expect(tray.getByText(/aboard/i)).toHaveCount(0)

      // a part unfolds into its goods, below itself; nothing above it, the tray or its button moves
      const sails = tray.getByTestId('yard-part-suit-of-sails')
      await sails.scrollIntoViewIfNeeded()
      await expect(sails).toHaveAttribute('aria-expanded', 'false')
      const before = { sails: await box(sails), tray: await box(tray), next: await box(next), ready: await box(tray.getByTestId('yard-ready')) }
      const anchorBefore = await box(tray.getByTestId('yard-part-anchor-and-cable'))
      await sails.click()
      const inputs = tray.getByTestId('yard-inputs-suit-of-sails')
      await expect(inputs).toBeVisible()
      await expect(sails).toHaveAttribute('aria-expanded', 'true')
      await expect(inputs).toContainText('Riga')
      await expect(tray.getByTestId('yard-input-source-suit-of-sails-flax')).toHaveAttribute('data-port', 'RIG')
      await expect(tray.getByTestId('yard-input-source-suit-of-sails-flax')).toHaveAttribute('data-seller', 'Riga')
      await expect(inputs.locator('[data-testid^="yard-input-suit-of-sails-"]')).toHaveCount(3)
      expect(await box(sails), 'the press moved the row pressed').toEqual(before.sails)
      expect(await box(tray), 'the press moved the tray').toEqual(before.tray)
      expect(await box(next), 'the press moved the button').toEqual(before.next)
      expect(await box(tray.getByTestId('yard-ready')), 'the press moved the ready line').toEqual(before.ready)
      expect(await box(tray.getByTestId('yard-part-anchor-and-cable')), 'the press moved the part above it').toEqual(anchorBefore)
      // no name is cut
      for (const text of await tray.locator('[data-testid^="yard-"]').allTextContents()) expect(text, 'a name is cut').not.toContain('...')
      await noSideways(page, 'the yard sheet')
      await noBrokenWord(tray, 'the yard sheet')
      await page.screenshot({ path: info.outputPath('yard-plan.png') })
    })

    test('the played flow: Make parts, Store, Build, Hire crew', async ({ page, request, baseURL }, info) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await serveWorldImage(page, await ladenHold())
      const tray = await barcaSheet(page, 'Build')
      const next = tray.getByTestId('yard-next')
      const readyLine = tray.getByTestId('yard-ready')
      const place = await box(next)
      let presses = 0

      // 1. everything is on board: the parts first (they are made from the hold)
      await expect(next).toHaveAttribute('data-step', 'make')
      await expect(next).toHaveText('Make parts')
      await expect(next).toBeEnabled()
      await expect(readyLine).toHaveText('Ready 0 / 6')
      await expect(tray.getByTestId('yard-weight')).toContainText('0')
      await page.screenshot({ path: info.outputPath('1-make.png') })
      await next.click()
      presses++

      // 2. both parts made; the hull's goods are still on board: Store
      await expect(next).toHaveAttribute('data-step', 'store', { timeout: 60_000 })
      await expect(next).toHaveText('Store')
      await expect(readyLine).toHaveText('Ready 2 / 6')
      expect(await box(next), 'the button moved between Make parts and Store').toEqual(place)
      await next.click()
      presses++

      // 3. all six lines are there: Build, once she is named
      await expect(next).toHaveAttribute('data-step', 'build', { timeout: 60_000 })
      await expect(next).toHaveText('Build')
      await expect(readyLine).toHaveText('Ready 6 / 6')
      await expect(next).toBeDisabled()
      await tray.getByTestId('yard-name').fill('Segunda')
      await expect(next).toBeEnabled()
      await page.screenshot({ path: info.outputPath('3-build.png') })
      await next.click()
      presses++

      // 4. she is laid down with no crew: the button is the hire, and the fleet is full
      await expect(next).toHaveAttribute('data-step', 'hire', { timeout: 60_000 })
      await expect(next).toHaveText('Hire crew · 8')
      await expect(next).toBeEnabled()
      await expect(tray.getByTestId('yard-fleet-full')).toHaveText('Fleet full')
      await expect(readyLine).toHaveText('Ready 0 / 6')
      await noSideways(page, 'the yard sheet after the build')
      await page.screenshot({ path: info.outputPath('4-hire.png') })
      await next.click()
      presses++
      await expect(page).toHaveURL(/\/command$/)
      await expect(page.getByTestId('port-inn')).toBeVisible({ timeout: 60_000 })
      await expect(page.getByTestId('inn-crew')).toBeVisible()
      expect(presses, 'the flow is four presses and a name').toBe(4)
      await page.screenshot({ path: info.outputPath('5-inn.png') })
    })
  })
}

test.describe('the plan in Korean', () => {
  // 320: the narrowest phone, where a Korean line is the first to break
  test.use({ viewport: { width: 320, height: 844 }, deviceScaleFactor: 2, locale: 'ko-KR' })

  test('the sheet reads in Korean', async ({ page, request, baseURL }, info) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await serveWorldImage(page, await barcaWithParts())
    const tray = await barcaSheet(page, '건조')
    await expect(tray.getByTestId('yard-next')).toHaveText('건조')
    await expect(tray.getByTestId('yard-next')).toBeDisabled()
    await expect(tray.getByTestId('yard-ready')).toHaveText('준비 0 / 6')
    await expect(tray.getByTestId('yard-total')).toContainText('합계')
    await expect(tray.getByTestId('yard-weight')).toContainText('무게')
    await expect(tray.getByTestId('yard-weight')).toContainText('실림')
    const sails = tray.getByTestId('yard-part-suit-of-sails')
    await sails.scrollIntoViewIfNeeded()
    await sails.click()
    await expect(tray.getByTestId('yard-input-source-suit-of-sails-flax')).toHaveAttribute('data-port', 'RIG')
    // the names are hers: the good and its seller read in Korean
    await expect(tray.getByTestId('yard-good-timber')).toContainText('목재')
    await expect(tray.getByTestId('yard-input-source-suit-of-sails-flax')).toContainText('리가')
    await noSideways(page, 'the Korean yard sheet')
    await noBrokenWord(tray, 'the Korean yard sheet')
    await page.screenshot({ path: info.outputPath('yard-plan-ko.png') })
  })

  test('the played flow reads in Korean', async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await serveWorldImage(page, await ladenHold())
    const tray = await barcaSheet(page, '건조')
    const next = tray.getByTestId('yard-next')
    await expect(next).toHaveText('부품 제작')
    await next.click()
    await expect(next).toHaveText('입고', { timeout: 60_000 })
    await next.click()
    await expect(next).toHaveAttribute('data-step', 'build', { timeout: 60_000 })
    await tray.getByTestId('yard-name').fill('Segunda')
    await next.click()
    await expect(next).toHaveText('선원 고용 · 8', { timeout: 60_000 })
    await expect(tray.getByTestId('yard-fleet-full')).toHaveText('선단 가득')
  })
})
