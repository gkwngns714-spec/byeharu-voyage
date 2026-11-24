import { test, expect, type Page } from '@playwright/test'
import { reachable, ready, WORLD_BOOT_MS } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE RATE SAYS WHY (0493; owner 2026-11-24: "i am -19.649 / hour. it should say why", then "why investing causes les money? wtf?").
//
// The world: the shipped image with the board served (hq_board_enabled) and no trade run priced (hq_board_fleets 0: the board answers
// at once), and every new company handed the owner's own day as ledger rows: she invested twice (SHARE -461,384), was towed (-6,932),
// signed a captain (-3,250) and paid wages (-480); a probe row, which the rate leaves out, squares her purse.
//   - the headline is her running costs only (the tow and the wages), never the investment;
//   - under it one fixed-height line names the biggest causes, and a neutral line says "Invested 461,384 · one time";
//   - a press on the figure (44 px) opens the sheet over HQ: two groups, Running and One time; each group's lines sum to its figure;
//   - its back arrow and Escape each close it and leave HQ as it was (the browser's back is DetailPage's own: useBackLayer);
//   - no sideways scroll at 320, 390 and 1440.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const OWNERS_DAY = `
  update public.world_config set value = 'true'::jsonb where key = 'hq_board_enabled';
  update public.world_config set value = to_jsonb(0) where key = 'hq_board_fleets';
  create function public.spec_rate_why_day() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
  begin
    if not new.is_npc then
      insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at) values
        (new.id, 'SHARE',        -400000, new.ducats, now() - interval '2 hours'),
        (new.id, 'SHARE',         -61384, new.ducats, now() - interval '3 hours'),
        (new.id, 'TOW',            -6932, new.ducats, now() - interval '4 hours'),
        (new.id, 'OFFICER_WAGE',   -3250, new.ducats, now() - interval '5 hours'),
        (new.id, 'WAGES',           -480, new.ducats, now() - interval '6 hours'),
        -- the boot reconciles her purse against her ledger: a probe row (which the rate leaves out, as 0480 did) squares the five above
        (new.id, 'PROBE_RATE_WHY', 472046, new.ducats, now() - interval '7 hours');
    end if;
    return new;
  end $f$;
  create trigger spec_rate_why_day after insert on public.players for each row execute function public.spec_rate_why_day();`

async function openHq(page: Page, width: number, height: number) {
  await page.setViewportSize({ width, height })
  await serveWorldImage(page, await patchedWorldImage('hq-rate-why', async (pg) => void (await pg.exec(OWNERS_DAY))))
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('hq-board')).toBeVisible({ timeout: WORLD_BOOT_MS })
  await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'served', { timeout: 180_000 })
}

const noSideways = (page: Page) =>
  page.evaluate(() => {
    const over = [...document.querySelectorAll('[data-sheet], [data-testid="hq-rate-sheet"], body, html')].some((el) => el.scrollWidth > el.clientWidth + 1)
    return !(over || document.documentElement.scrollWidth > window.innerWidth)
  })

const num = async (page: Page, testid: string, attr: string) => Number(await page.getByTestId(testid).getAttribute(attr))

for (const glass of [
  { width: 320, height: 640 },
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
]) {
  test(`the per-hour figure says why, and its sheet opens and closes (${glass.width})`, async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    test.setTimeout(600_000)
    await openHq(page, glass.width, glass.height)

    // THE BRIDGE: the figure is a 44 px press; the causes line has one fixed height; the investment is neutral and apart
    const figure = page.getByTestId('hq-bridge-rate')
    await expect(figure).toHaveAttribute('data-span', '24h')
    await expect(figure).toContainText('last 24 h')
    const box = (await figure.boundingBox())!
    expect(box.height, 'the figure is a 44 px target').toBeGreaterThanOrEqual(44)
    const perHour = await num(page, 'hq-bridge-rate', 'data-per-hour')
    expect(perHour, 'the headline is the running costs, not the investment (which alone is -19,224 an hour)').toBeGreaterThan(-1000)
    expect(perHour).toBeLessThan(0)
    const causes = page.getByTestId('hq-rate-causes')
    await expect(causes).toContainText('Tow −6,932')
    await expect(causes).toContainText('Wages −480')
    await expect(causes).not.toContainText('Invested')
    expect((await causes.boundingBox())!.height, 'the causes line has a fixed height').toBe(18)
    const once = page.getByTestId('hq-rate-once')
    await expect(once).toHaveText(/Invested 461,384\s*· one time/)
    expect(await once.evaluate((el) => getComputedStyle(el).color === getComputedStyle(document.querySelector('[data-testid="hq-rate-causes"]')!).color), 'a purchase is neutral, not red').toBe(true)
    expect(await noSideways(page), 'no sideways scroll on HQ').toBe(true)
    if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/rate-why-${glass.width}.png` })

    // THE SHEET: two groups; each line's total sums to its group's figure; the headline is the bridge's
    await figure.click()
    const sheet = page.getByTestId('hq-rate-sheet')
    await expect(sheet).toBeVisible()
    expect(await num(page, 'hq-rate-sheet-figure', 'data-per-hour')).toBe(perHour)
    for (const group of ['hq-rate-running', 'hq-rate-onetime']) {
      const totals = await sheet.getByTestId(group).getByTestId('hq-rate-line').evaluateAll((els) => els.map((e) => Number(e.getAttribute('data-total'))))
      expect(totals.length, `${group} lists its lines`).toBeGreaterThan(0)
      expect(totals.reduce((a, b) => a + b, 0), `${group}: the lines sum to the group's figure`).toBe(await num(page, group, 'data-total'))
    }
    const invest = sheet.getByTestId('hq-rate-onetime').locator('[data-line="invest"]')
    await expect(invest).toHaveAttribute('data-total', '-461384')
    await expect(invest.getByTestId('hq-rate-tag')).toHaveText('One time')
    await expect(invest).toContainText('×2')
    await expect(sheet.getByTestId('hq-rate-running').locator('[data-line="invest"]')).toHaveCount(0)
    await expect(sheet.getByTestId('hq-rate-running').locator('[data-line="tow"]')).toHaveAttribute('data-total', '-6932')
    const back = sheet.locator('[data-detail-back]')
    expect((await back.boundingBox())!.height).toBeGreaterThanOrEqual(44)
    expect(await noSideways(page), 'no sideways scroll with the sheet open').toBe(true)
    if (process.env.HQ_SHOTS) await page.screenshot({ path: `${process.env.HQ_SHOTS}/rate-why-sheet-${glass.width}.png` })

    // THE WAYS OUT: the page's back arrow and Escape; HQ stays
    await back.click()
    await expect(sheet).toHaveCount(0)
    await figure.click()
    await expect(sheet).toBeVisible()
    await page.keyboard.press('Escape')
    await expect(sheet).toHaveCount(0)
    await expect(page).toHaveURL(/\/city/)
    await expect(page.getByTestId('hq-board')).toBeVisible()
    await expect(figure).toHaveAttribute('data-per-hour', String(perHour))
  })
}
