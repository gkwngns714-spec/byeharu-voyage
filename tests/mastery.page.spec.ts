import { test, expect } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'
import { openMarket } from './desk.fixture'

// GOODS MASTERY (0479, roadmap 2026-11-23 slice 11). The shipped world is DARK (`goods_mastery_enabled` false): You draws no specialty
// and no good is named in gold. A copy of the image with the ladder and the logbook lit, and her company given two goods her home
// harbour sells (the first at the top, 16,000 units, level 10; the second 120 units, level 2) as the server's back-fill would write
// them: You's plate names her specialty (the level-10 good, its ring), the logbook's Goods page rings the two goods she has sold with
// their levels, and the Trade desk's card of the level-10 good is named in gold. Nothing here works a level out: it compares the
// faces with the rows the patch wrote.

// Her company is founded in the browser (scripts/db/build-image.mjs: an image is a world, not a house), so the patch leaves a trigger
// that writes her two rows the moment her house is founded at Lisbon: the rows the back-fill would have written for her sales there.
const lit = () =>
  patchedWorldImage('mastery-lit', async (pg) => {
    await pg.exec(`
      update public.world_config set value = 'true'::jsonb where key in ('goods_mastery_enabled', 'logbook_enabled');
      create function public.spec_mastery_seed() returns trigger language plpgsql as $f$
      begin
        if not new.is_npc then
          insert into public.goods_mastery (player_id, good_id, units, level)
          select new.id, two.id, case when two.k = 1 then 16000 else 120 end, case when two.k = 1 then 10 else 2 end
            from (select g.id, row_number() over (order by g.code) as k
                    from public.ports p join public.port_goods pg on pg.port_id = p.id join public.goods g on g.id = pg.good_id
                   where p.code = 'LIS' and p.kind = 'HARBOUR' and public.port_offers(p.id, g.id)
                   order by g.code limit 2) two;
          insert into public.logbook (player_id, kind, code)
          select m.player_id, 'good', g.code from public.goods_mastery m join public.goods g on g.id = m.good_id
           where m.player_id = new.id on conflict do nothing;
        end if;
        return new;
      end $f$;
      create trigger spec_mastery_seed after insert on public.players for each row execute function public.spec_mastery_seed();
    `)
  })

test.use({ viewport: PHONE })

test('dark: You names no specialty', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
  await page.goto('you')
  await ready(page)
  await expect(page.getByTestId('you-plate')).toBeVisible()
  await expect(page.getByTestId('you-specialty')).toHaveCount(0)
})

test('lit: the specialty on You, the level rings on the logbook, the mastered good in gold on the Market', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
  await serveWorldImage(page, await lit())
  await page.goto('you')
  await ready(page)
  const spec = page.getByTestId('you-specialty')
  await expect(spec).toBeVisible({ timeout: 60_000 })
  await expect(spec).toHaveAttribute('data-level', '10')
  const good = await spec.getAttribute('data-good')
  expect(good).toBeTruthy()

  // the logbook's Goods page: the two goods she has sold carry their levels
  await page.goto('logbook')
  await ready(page)
  await page.getByRole('tab', { name: 'Goods' }).click()
  await expect(page.locator('[data-testid="logbook-slot"][data-level]')).toHaveCount(2, { timeout: 60_000 })
  await expect(page.locator('[data-testid="logbook-slot"][data-level="10"]')).toHaveCount(1)
  await expect(page.locator('[data-testid="logbook-slot"][data-level="2"]')).toHaveCount(1)

  // HQ's Market plate (H3, 2026-11-24: it was the Trade desk): the level-10 good's card is named in gold, the other is not
  await page.goto('city')
  await ready(page)
  await openMarket(page)
  await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
  const card = page.locator(`[data-testid="trade-good"][data-good="${good}"]`).first()
  await expect(card.getByTestId('trade-good-name')).toHaveAttribute('data-mastered', 'true', { timeout: 60_000 })
  await expect(page.locator('[data-testid="trade-good-name"][data-mastered="true"]')).toHaveCount(1)

  // the page fits the phone: nothing wider than the glass
  const wide = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(wide).toBeLessThanOrEqual(0)
})
