/// <reference types="node" />
import { test, expect, type Page } from '@playwright/test'
import { readdirSync } from 'node:fs'
import { ready, reachable } from './appReady.fixture'
import { corpWorld } from './corpWorld.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// THE BARGAIN, THE PURCHASE TAX, THE PREMIUM SALE AND A FRESH RUN'S RATE, DRIVEN (0506, 0507, 0517; the owner, 2026-11-25). Each registered
// only where its migration is in the chain (no skip: CI's floor counts every registered test). The dice and the premium good's city are the
// world's own rows, set here; nothing in the product is told.

const OUT = process.env.BARGAIN_SHOTS ?? 'test-results/bargain'
const has = (re: RegExp) => readdirSync('supabase/migrations').some((f) => re.test(f))
const when = (on: boolean) => (on ? test : () => undefined) as typeof test
const testBargain = when(has(/_ten_bargains/) && has(/_a_tax_when_buying/))
const testPremium = when(has(/_premium_goods/))
const testRun = when(has(/_jobs_never_lose/))
const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
] as const
const PURSES = `insert into public.port_treasury (port_id, ducats) select p.id, 50000000 from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do update set ducats = 50000000;`
const on = (...keys: string[]) => `update public.world_config set value = 'true'::jsonb where key in (${keys.map((k) => `'${k}'`).join(', ')});`

/** The bargain and the tax lit; `odds`: the chance of every try. */
const bargainWorld = (odds: 0 | 1) =>
  patchedWorldImage(`bargain-${odds}`, async (pg) => {
    await pg.exec(`${on('bargain_total_enabled', 'buy_tax_enabled', 'city_treasury_enabled')} ${PURSES}
      update public.world_config set value = '${odds}'::jsonb where key in ('bargain_p1_base', 'bargain_p1_max');
      update public.world_config set value = '1'::jsonb where key = 'bargain_decay';`)
  })
/** Attar of Roses is Lisbon's own premium good, and a new company has what makes one in its shed there. */
const premiumWorld = () =>
  patchedWorldImage('premium-lis', async (pg) => {
    await pg.exec(`${on('premium_goods_enabled', 'city_treasury_enabled', 'economy_closed', 'storage_enabled')} ${PURSES}
      update public.goods set premium_port_id = null where premium_port_id = (select id from public.ports where code = 'LIS');
      update public.goods set premium_port_id = (select id from public.ports where code = 'LIS') where code = 'attar-of-roses';
      create function public.spec_shed() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
      begin
        insert into public.player_storage (player_id, port_id, good_id, qty, basis)
        select new.player_id, p.id, g.id, 12, 10 from public.ports p, public.goods g where p.code = 'LIS' and g.code in ('rose', 'tallow', 'fresh-water')
          and not exists (select 1 from public.player_storage s where s.player_id = new.player_id and s.good_id = g.id);
        return null;
      end $f$;
      create trigger spec_shed after insert on public.fleets for each row execute function public.spec_shed();`)
  })

const figure = (s: string) => Number(s.replace(/[^0-9.\-−]/g, '').replace('−', '-'))
const total = async (page: Page) => figure((await page.getByTestId('good-detail-total').innerText()).split('\n')[1] ?? '')

async function openBuy(page: Page, units: string) {
  await page.goto('command')
  await ready(page)
  const board = page.getByTestId('desk-trade').getByTestId('trade-board')
  const card = board.locator('[data-testid="trade-good"]:has([data-testid="trade-buy"]:not([disabled]))').first()
  await expect(card).toBeVisible({ timeout: 120_000 })
  const code = (await card.getAttribute('data-good'))!
  await card.getByTestId('trade-buy').click()
  const box = page.getByTestId('good-detail').getByTestId('stepper-figure')
  await box.fill(units)
  await box.press('Enter')
  await expect(page.getByTestId('trade-act')).toBeEnabled({ timeout: 60_000 })
  await page.waitForTimeout(1500)
  return board.locator(`[data-testid="trade-good"][data-good="${code}"]`)
}

for (const size of SIZES) {
  testBargain(`a won bargain lowers the buy and raises the sale @${size.width}`, async ({ page, request, baseURL }) => {
    test.setTimeout(400_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await serveWorldImage(page, await bargainWorld(1))
    await page.setViewportSize(size)
    const card = await openBuy(page, '20')
    const press = page.getByTestId('bargain-press')
    // seen without a scroll, 44 px, with the tax inside the cost
    await expect(press).toBeInViewport({ ratio: 1 })
    expect((await press.boundingBox())!.height).toBeGreaterThanOrEqual(44)
    await expect(page.getByTestId('trade-tray-qty')).toBeInViewport()
    await expect(page.getByTestId('buy-tax')).toHaveText(/^Tax [\d,.]+/)
    await page.screenshot({ path: `${OUT}/${size.width}-buy.png` })
    const plain = await total(page)
    const where = (await page.getByTestId('trade-act').boundingBox())!
    await press.click()
    await expect(page.getByTestId('bargain-held')).toHaveText('Won · 5% off', { timeout: 60_000 })
    await expect.poll(() => total(page), { timeout: 60_000 }).toBeLessThan(plain)
    expect(Math.abs((await total(page)) / plain - 0.95)).toBeLessThan(0.01)
    expect(await page.getByTestId('trade-act').boundingBox(), 'a won try moved the button').toEqual(where)
    await page.screenshot({ path: `${OUT}/${size.width}-buy-won.png` })
    await page.getByTestId('trade-act').click()
    await expect(page.getByTestId('trade-toast')).toBeVisible({ timeout: 60_000 })

    // THE SELL SIDE, the other good of the board's: the same day's row of this good is the buy's (the server says so)
    await card.getByTestId('trade-sell').click()
    await expect(page.getByTestId('good-detail')).toHaveAttribute('data-side', 'sell')
    await expect(press).toBeInViewport({ ratio: 1 })
    await page.waitForTimeout(1500)
    await press.click()
    await expect(page.getByTestId('bargain-said')).toHaveAttribute('data-tone', 'refused', { timeout: 60_000 })
    expect((await page.getByTestId('bargain-said').innerText()).trim(), 'a refusal is not in words').toMatch(/^[A-Z].+/)
    await page.screenshot({ path: `${OUT}/${size.width}-sell-same-day.png` })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
  })

  testBargain(`a sale bargained up; a sale at a loss reads as a loss @${size.width}`, async ({ page, request, baseURL }) => {
    test.setTimeout(400_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await serveWorldImage(page, await bargainWorld(1))
    await page.setViewportSize(size)
    const card = await openBuy(page, '20')
    await page.getByTestId('trade-act').click()
    await expect(page.getByTestId('trade-toast')).toBeVisible({ timeout: 60_000 })
    await card.getByTestId('trade-sell').click()
    await expect(page.getByTestId('trade-profit')).toContainText(/\d/, { timeout: 60_000 })
    await page.waitForTimeout(1500)
    const plain = await total(page)
    // bought and sold at once she loses: the total is red, as its profit is
    const red = await page.evaluate(() => {
      const t = document.querySelector('[data-testid="good-detail-total"]')!
      const colours = [...t.querySelectorAll('*')].filter((e) => e.children.length === 0 && /\d/.test(e.textContent ?? '')).map((e) => getComputedStyle(e).color)
      return new Set(colours).size === 1 ? colours[0] : colours.join(' / ')
    })
    expect(red, 'the total and the profit of a loss are not one colour').not.toContain('/')
    await page.screenshot({ path: `${OUT}/${size.width}-sell-loss.png` })
    await page.getByTestId('bargain-press').click()
    await expect(page.getByTestId('bargain-held')).toHaveText('Won · 5% more', { timeout: 60_000 })
    await expect.poll(() => total(page), { timeout: 60_000 }).toBeGreaterThan(plain)
    await page.screenshot({ path: `${OUT}/${size.width}-sell-won.png` })
    await page.getByTestId('trade-act').click()
    await expect(page.getByTestId('trade-toast')).toContainText(/^Sold 20 /, { timeout: 60_000 })
  })

  testPremium(`a premium good is made in the Forge and sold at its city @${size.width}`, async ({ page, request, baseURL }) => {
    test.setTimeout(400_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await serveWorldImage(page, await premiumWorld())
    await page.setViewportSize(size)
    await page.goto('city')
    await ready(page)
    await page.getByTestId('city-building-production').click()
    await page.getByTestId('port-production').waitFor()
    const tab = (name: string) => page.getByTestId('port-production').getByRole('tab', { name, exact: true })
    if ((await tab('Recipes').count()) > 0) await tab('Recipes').click()
    await page.getByTestId('forge-product-attar-of-roses').click()
    const tray = page.getByTestId('forge-tray')
    await expect(tray.getByTestId('premium-city')).toContainText('Lisbon')
    await expect(tray.getByTestId('premium-pays')).toContainText('make it first')
    await page.screenshot({ path: `${OUT}/${size.width}-premium-before.png` })
    await tray.getByTestId('forge-make-attar-of-roses').click()
    await expect(tray).toHaveCount(0, { timeout: 60_000 })
    const take = page.getByTestId('production-recipes').getByRole('button', { name: /^Take on board/ }).first()
    await expect(take).toBeVisible({ timeout: 60_000 })
    await page.getByTestId('forge-product-attar-of-roses').click()
    await expect(tray.getByTestId('premium-pays')).toContainText('1 left', { timeout: 60_000 })
    await page.screenshot({ path: `${OUT}/${size.width}-premium-made.png` })
    await tray.getByTestId('tray-close').click()
    await take.click()
    await page.getByRole('button', { name: 'Take 1 unit on board', exact: true }).click()
    await page.waitForTimeout(2500)
    await page.screenshot({ path: `${OUT}/${size.width}-premium-aboard.png` })
    await page.goto('command')
    await ready(page)
    const card = page.locator('[data-testid="trade-good"][data-good="attar-of-roses"]')
    await expect(card).toBeVisible({ timeout: 120_000 })
    await card.getByTestId('trade-sell').click()
    await expect(page.getByTestId('trade-act')).toBeEnabled({ timeout: 60_000 })
    await page.waitForTimeout(1500)
    const got = await total(page)
    const normal = figure((await page.getByTestId('good-detail-price').innerText()).split('\n').find((x) => /\d/.test(x)) ?? '')
    await page.screenshot({ path: `${OUT}/${size.width}-premium-sell.png` })
    console.log(`premium @${size.width}: one unit, price ${normal}, total ${got}`)
    await page.getByTestId('trade-act').click()
    await expect(page.getByTestId('trade-toast')).toContainText(/^Sold 1 /, { timeout: 60_000 })
    expect(got, 'the city did not pay a premium').toBeGreaterThan(normal * 2.5)
  })

  testRun(`a fresh run's company says Measuring, not a loss an hour @${size.width}`, async ({ page, request, baseURL }) => {
    test.setTimeout(500_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await serveWorldImage(page, await corpWorld({ courses: true, home: true }))
    await page.setViewportSize(size)
    await page.goto('city')
    await ready(page)
    const hers = page.locator('[data-testid="corp-worker"][data-kind="fleet"]').first()
    await hers.click({ position: { x: 30, y: 24 }, timeout: 300_000 })
    const sheet = page.getByTestId('hq-sheet-assign')
    await sheet.getByTestId('corp-assign-run').first().click({ timeout: 180_000 })
    await sheet.getByTestId('corp-assign-go').click()
    await expect(sheet).toHaveCount(0, { timeout: 120_000 })
    await expect(page.getByTestId('hq-rate-figure')).toHaveText(/Measuring/, { timeout: 120_000 })
    await page.screenshot({ path: `${OUT}/${size.width}-measuring.png` })
  })
}
