import { test, expect, type Locator, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE YARD TAKES AN ORDER (migration 0465; docs/design/content-plan-2026-11.md 5.3 item 3, slice C)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A new company at Lisbon:
//   1. DARK (the shipped world: yard_order_enabled false). The Barca's sheet is as it was: no Order press, no Wait row, nothing on
//      order at the top of the yard.
//   2. LIT, the played flow at 390×844 (a copy of the shipped world with the switch lit, and every order's wait cut to 20 seconds by
//      a trigger so the spec need not wait the real 30 minutes). The sheet carries "Wait · 30m" and, under the one button, "Order ·
//      <price>", the server's quote. The press closes the sheet; the yard's top reads "On order · Barca" with its countdown, then
//      Ready; a name and Launch put her into the fleet: "<name> launched", and nothing is on order any more.
//   3. The same sheet in Korean: 대기, 주문 · <price>.
// The server half: proof 168 and the migration's own self-assert.

const PHONE = { width: 390, height: 844 } as const

/** The shipped world with the yard taking orders, every order ready 20 seconds after it is placed. */
function lit(): Promise<Buffer> {
  return patchedWorldImage('yard-order-lit', async (pg) => {
    await pg.exec(`
      update public.world_config set value = 'true'::jsonb where key = 'yard_order_enabled';
      create function public.spec_yard_order_soon() returns trigger
      language plpgsql security definer set search_path = public, pg_temp as $$
      begin
        new.ready_at := new.ordered_at + interval '20 seconds';
        return new;
      end $$;
      create trigger spec_yard_order_soon before insert on public.hull_orders
        for each row execute function public.spec_yard_order_soon();
    `)
  })
}

async function noSideways(page: Page, what: string) {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(over, `${what} scrolls sideways by ${over} px`).toBeLessThanOrEqual(0)
}

async function yard(page: Page, buildTab: string): Promise<Locator> {
  await page.goto('port')
  await ready(page)
  await page.getByRole('tablist').getByRole('tab', { name: buildTab, exact: true }).click()
  const root = page.getByTestId('port-yard')
  await expect(root).toBeVisible({ timeout: 60_000 })
  return root
}

async function barcaSheet(page: Page, root: Locator): Promise<Locator> {
  await root.getByTestId('yard-now').getByTestId('hull-barca').click()
  const tray = page.getByTestId('yard-tray')
  await expect(tray).toBeVisible()
  await expect(tray.getByTestId('yard-total')).toHaveAttribute('data-cost', /^\d+$/, { timeout: 60_000 })
  return tray
}

test.describe('the yard takes an order at 390×844', () => {
  test.use({ viewport: PHONE, deviceScaleFactor: 2 })

  test('dark: the Barca\'s sheet offers no order', async ({ page, request, baseURL }, info) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    const root = await yard(page, 'Build')
    await expect(root.getByTestId('yard-order-open')).toHaveCount(0)
    const tray = await barcaSheet(page, root)
    await expect(tray.getByTestId('yard-next')).toHaveText('Build')
    await expect(page.getByTestId('yard-order')).toHaveCount(0)
    await expect(tray.getByTestId('yard-order-wait')).toHaveCount(0)
    await page.screenshot({ path: info.outputPath('1-dark.png') })
  })

  test('lit: Order, the countdown, Ready, Launch', async ({ page, request, baseURL }, info) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await serveWorldImage(page, await lit())
    const root = await yard(page, 'Build')
    const tray = await barcaSheet(page, root)

    // the sheet: the wait beside the totals, and the order under the one button at the server's price
    await expect(tray.getByTestId('yard-order-wait')).toContainText('Wait')
    await expect(tray.getByTestId('yard-order-wait')).toContainText('30m')
    const order = page.getByTestId('yard-order')
    await expect(order).toHaveAttribute('data-price', /^\d+$/, { timeout: 60_000 })
    const price = Number(await order.getAttribute('data-price'))
    const cost = Number(await tray.getByTestId('yard-total').getAttribute('data-cost'))
    expect(price, 'the order is not dearer than the materials route').toBeGreaterThan(cost)
    expect(price, 'a Barca on order is not about 26,000').toBeGreaterThan(20_000)
    expect(price, 'a Barca on order is not about 26,000').toBeLessThan(32_000)
    await expect(order).toHaveText(/^Order · /)
    // 0472 dark (first_hour_enabled false): no floor on her second hull, no "First order" row
    await expect(tray.getByTestId('yard-order-first')).toHaveCount(0)
    await noSideways(page, 'the sheet with an order')
    await page.screenshot({ path: info.outputPath('2-sheet.png') })

    // the press: the sheet closes, the order stands at the top of the yard with its countdown
    await order.click()
    await expect(tray).toHaveCount(0, { timeout: 60_000 })
    const open = root.getByTestId('yard-order-open')
    await expect(open).toBeVisible({ timeout: 60_000 })
    await expect(open).toHaveAttribute('data-class', 'barca')
    await expect(open.getByTestId('yard-order-row')).toContainText('On order · Barca')
    await expect(open.getByTestId('yard-order-row')).toContainText(/Ready in \d+s/)
    await page.screenshot({ path: info.outputPath('3-on-order.png') })

    // ready: a name and Launch
    await expect(open).toHaveAttribute('data-ready', 'true', { timeout: 60_000 })
    await expect(open.getByTestId('yard-order-row')).toContainText('Ready')
    const launch = open.getByTestId('yard-launch')
    await expect(launch).toBeDisabled()
    await open.getByTestId('yard-launch-name').fill('Encomenda')
    await expect(launch).toBeEnabled()
    await noSideways(page, 'the order, ready')
    await page.screenshot({ path: info.outputPath('4-ready.png') })
    await launch.click()
    await expect(root.getByTestId('yard-launched')).toHaveText('Encomenda launched', { timeout: 60_000 })
    await expect(root.getByTestId('yard-order-open')).toHaveCount(0)
    await page.screenshot({ path: info.outputPath('5-launched.png') })
  })

  test('0472 lit: her second Barca is quoted at the floor, and the sheet says First-ship fee, and the Order she cannot pay is the gold button saying by how much', async ({ page, request, baseURL }, info) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await serveWorldImage(
      page,
      await patchedWorldImage('yard-order-first-hour', async (pg) => {
        await pg.exec(`update public.world_config set value = 'true'::jsonb where key in ('yard_order_enabled', 'first_hour_enabled');`)
      }),
    )
    const root = await yard(page, 'Build')
    const tray = await barcaSheet(page, root)
    const order = page.getByTestId('yard-order')
    await expect(order).toHaveAttribute('data-price', /^\d+$/, { timeout: 60_000 })
    // a new company (one ship, none on order): the floor, 52,000, at Trading 1
    expect(Number(await order.getAttribute('data-price')), 'her second Barca is not at the floor').toBe(52_000)
    const first = tray.getByTestId('yard-order-first')
    await expect(first).toContainText('First-ship fee')
    await expect(first).toHaveAttribute('data-fee', /^\d+$/)
    // a new company has 40,000: the Order says what she lacks and cannot be pressed; Build (materials 0 / 4) is the plain button
    await expect(order).toHaveAttribute('data-short', '12000')
    await expect(order).toHaveText(/^Order · 52,000\s\S+ · Short 12,000$/)
    await expect(order).toBeDisabled()
    await expect(order).toHaveAttribute('data-variant', 'primary')
    await expect(tray.getByTestId('yard-next')).toHaveAttribute('data-variant', 'secondary')
    await noSideways(page, 'the sheet with a first order')
    await page.screenshot({ path: info.outputPath('6-first-order.png') })
  })
})

test.describe('the yard takes an order in Korean at 390×844', () => {
  test.use({ viewport: PHONE, deviceScaleFactor: 2, locale: 'ko-KR' })

  test('the sheet reads 대기 and 주문', async ({ page, request, baseURL }, info) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await serveWorldImage(page, await lit())
    const root = await yard(page, '건조')
    const tray = await barcaSheet(page, root)
    await expect(tray.getByTestId('yard-order-wait')).toContainText('대기')
    const order = page.getByTestId('yard-order')
    await expect(order).toHaveAttribute('data-price', /^\d+$/, { timeout: 60_000 })
    await expect(order).toHaveText(/^주문 · /)
    await noSideways(page, 'the Korean sheet')
    await page.screenshot({ path: info.outputPath('ko-sheet.png') })
  })
})

// 2026-11-23 (third play-test, findings 3 and 21): while the yard takes orders the goal card counts her purse against the Order's price
// (the yard's own quote) with a bar, and its press opens the yard ON the Barca's sheet, where the Order is.
for (const [locale, words] of [
  ['en-US', /^Second ship · 40,000 \/ 52,000$/],
  ['ko-KR', /^두 번째 배 · 40,000 \/ 52,000$/],
] as const) {
  test.describe(`the goal card while the yard takes orders, ${locale}`, () => {
    test.use({ viewport: PHONE, deviceScaleFactor: 2, locale })

    test('reads purse / price with a bar, holds its height, and opens the Barca\'s sheet', async ({ page, request, baseURL }, info) => {
      test.setTimeout(300_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await serveWorldImage(
        page,
        await patchedWorldImage('yard-order-first-hour', async (pg) => {
          await pg.exec(`update public.world_config set value = 'true'::jsonb where key in ('yard_order_enabled', 'first_hour_enabled');`)
        }),
      )
      await page.goto('command')
      await ready(page)
      const card = page.getByTestId('goal-card')
      await expect(card).toBeVisible({ timeout: 120_000 })
      const line = card.getByTestId('goal-second-ship')
      await expect(line).toHaveText(words, { timeout: 120_000 })
      await expect(line).toHaveAttribute('data-price', '52000')
      // the purse against the price is the card's RING since slice 3 (2026-11-23): it was a thin bar in the line's rest
      await expect(card.getByTestId('goal-ring')).toHaveAttribute('data-pct', '77')
      expect(Math.round((await card.boundingBox())!.height), 'the card is not its one fixed height').toBe(44)
      await noSideways(page, 'Trade with the saving line')
      await page.screenshot({ path: info.outputPath(`goal-${locale}.png`) })

      await expect(card).toHaveAttribute('data-next', 'yard')
      await card.click()
      await expect(page).toHaveURL(/\/office$/)
      const tray = page.getByTestId('yard-tray')
      await expect(tray).toBeVisible({ timeout: 60_000 })
      await expect(page.getByTestId('yard-order')).toHaveAttribute('data-price', '52000', { timeout: 60_000 })
      await expect(page.getByTestId('yard-order')).toBeInViewport()
      await page.screenshot({ path: info.outputPath(`goal-press-${locale}.png`) })
    })
  })
}
