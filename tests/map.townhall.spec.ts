import { test, expect, type Page } from '@playwright/test'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile } from '../src/lib/db/worldImage'
import { PHONE, reachable, ready } from './appReady.fixture'
import { openCityPanel } from './openCity.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TOWN HALL, DRIVEN (0123, owner 2026-10-15): *"by clicking a city, there should be another
// building called town hall, where you click and can invest, and see who or what npcs invested."*
//
// The shipped world keeps the city purses dark, so this spec SETS its precondition in Node, on the
// build's own image: it lights the purses through THE switch (`public.city_treasury_switch(true)`)
// and has one merchant company buy ten shares of Porto's docks through THE door
// (`public.invest_for`, the one merchants and players share). Then the page opens Porto — away
// from your fleet at Lisbon, so you are not docked there — and the Town Hall tab must show the
// treasury, offer no Invest (with the one line that says why), and name the merchant investor.
//
// Run it: npm run build && npm run preview, then `npx playwright test map.townhall.spec.ts`.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const CITY = 'OPO'

let image: { body: Buffer; investor: string; investorNation: string } | null = null
let litImage: { body: Buffer; mayor: string } | null = null

/** 0144: the same build's world with the city purses AND the influence race lit (`influence_enabled`
 *  set directly — the switch is I4's), for the Donate press at Lisbon, where your fleet lies. */
async function donateWorld(): Promise<{ body: Buffer; mayor: string }> {
  if (litImage) return litImage
  const dir = path.resolve('dist', 'db')
  const name = existsSync(dir) ? readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f)) : undefined
  if (!name) throw new Error(`no world image under ${dir} — run \`npm run build\` first`)
  const { PGlite } = await import('@electric-sql/pglite')
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, name)))) })
  try {
    const above = await pg.query<{ v: unknown }>(`select value as v from public.world_config where key = 'npc_invest_above'`)
    await pg.exec(`update public.world_config set value = to_jsonb(0) where key = 'npc_invest_above'`)
    await pg.query(`select public.city_treasury_switch(true)`)
    await pg.query(`update public.world_config set value = $1::jsonb where key = 'npc_invest_above'`, [JSON.stringify(above.rows[0].v)])
    await pg.exec(`update public.world_config set value = 'true'::jsonb where key = 'influence_enabled'`)
    // 0147: a Portuguese merchant gives Lisbon 1,000 and the daily count names it the mayor
    const giver = await pg.query<{ name: string; r: { ok: boolean } }>(
      `select pl.company_name as name, public.donate_for(pl.id, (select id from public.ports where code = 'LIS'), 1000) as r
         from public.players pl join public.npc_houses h on h.player_id = pl.id
        where pl.nation_id = (select id from public.nations where code = 'PRT') and pl.ducats >= 1000
        order by h.roster_ord limit 1`,
    )
    if (giver.rows.length !== 1 || !giver.rows[0].r.ok) throw new Error('no Portuguese merchant could give at Lisbon')
    await pg.query(`select public.tick_influence()`)
    litImage = { body: Buffer.from(await (await pg.dumpDataDir('gzip')).arrayBuffer()), mayor: giver.rows[0].name }
  } finally {
    await pg.close()
  }
  return litImage
}

async function townHallWorld(): Promise<{ body: Buffer; investor: string; investorNation: string }> {
  if (image) return image
  const dir = path.resolve('dist', 'db')
  const name = existsSync(dir) ? readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f)) : undefined
  if (!name) throw new Error(`no world image under ${dir} — run \`npm run build\` first`)
  const { PGlite } = await import('@electric-sql/pglite')
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, name)))) })
  try {
    // The switch refuses a world whose money cannot carry the merchants' surplus line; this
    // fixture only needs the purses lit, so that line is lowered for the switch and put back.
    const above = await pg.query<{ v: unknown }>(`select value as v from public.world_config where key = 'npc_invest_above'`)
    await pg.exec(`update public.world_config set value = to_jsonb(0) where key = 'npc_invest_above'`)
    const sw = await pg.query<{ j: { enabled: boolean } }>(`select public.city_treasury_switch(true) as j`)
    if (!sw.rows[0].j.enabled) throw new Error(`the switch did not light the purses: ${JSON.stringify(sw.rows[0].j)}`)
    await pg.query(`update public.world_config set value = $1::jsonb where key = 'npc_invest_above'`, [
      JSON.stringify(above.rows[0].v),
    ])
    const who = await pg.query<{ name: string; nation: string; r: { ok: boolean } }>(
      `select pl.company_name as name, (select n.name from public.nations n where n.id = pl.nation_id) as nation,
              public.invest_for(pl.id, (select id from public.ports where code = $1), 'docks', 10) as r
         from public.npc_houses h join public.players pl on pl.id = h.player_id
        order by h.roster_ord limit 1`,
      [CITY],
    )
    if (who.rows.length !== 1 || !who.rows[0].r.ok) throw new Error(`no merchant could invest at ${CITY}`)
    image = {
      body: Buffer.from(await (await pg.dumpDataDir('gzip')).arrayBuffer()),
      investor: who.rows[0].name,
      investorNation: who.rows[0].nation,
    }
  } finally {
    await pg.close()
  }
  return image
}

async function openCity(page: Page, code: string, name: string): Promise<void> {
  await openCityPanel(page, code, name)
  await page.getByTestId('map-send-fleet').click()
  await expect(page.getByTestId('map-city-tabs')).toBeVisible()
}

test('the Town Hall shows the treasury, offers no Invest away from your fleet, and names the merchant investor', async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  const world = await townHallWorld()
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: world.body, contentType: 'application/gzip' }))
  await page.setViewportSize(PHONE)
  await page.goto('map')
  await ready(page)

  await openCity(page, CITY, 'Porto')
  await page.getByTestId('map-city-tabs').getByText('Town Hall', { exact: true }).click()
  await expect(page.getByTestId('map-city-townhall')).toBeVisible()
  await expect(page.getByTestId('townhall-treasury')).toBeVisible({ timeout: 30_000 })
  await expect(page.getByTestId('townhall-treasury')).toContainText('Treasury')
  // Four works; your fleet lies at Lisbon, so Invest is not offered here and one line says why.
  await expect(page.locator('[data-testid^="townhall-work-"]')).toHaveCount(4)
  await expect(page.locator('[data-testid^="townhall-invest-"][data-testid$="docks"]')).toHaveCount(0)
  await expect(page.getByTestId('townhall-invest-none')).toHaveText('Dock here to invest.')
  // The merchant who bought ten shares of the docks, by name.
  const row = page.getByTestId('townhall-investor').filter({ hasText: world.investor })
  await expect(row).toHaveCount(1)
  await expect(row).toContainText('Merchant')
  await expect(page.getByTestId('townhall-work-docks')).toContainText('10 of 100 sold')
  // 0144: Porto is a home city of Portugal; the merchant's investment is influence for its country;
  // the race is dark, so no Donate and one line that says so.
  await expect(page.getByTestId('townhall-holder')).toContainText('Portugal')
  await expect(page.getByTestId('townhall-holder')).toContainText('Home city')
  await expect(page.getByTestId('townhall-influence-share').filter({ hasText: world.investorNation })).toHaveCount(1)
  await expect(page.getByTestId('townhall-donate')).toHaveCount(0)
  await expect(page.getByTestId('townhall-donate-none')).toHaveText('Not taking gifts yet.')
})

test('0144: lit, a company docked at Lisbon donates, and its influence there is counted', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  const lit = await donateWorld()
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: lit.body, contentType: 'application/gzip' }))
  await page.setViewportSize(PHONE)
  await page.goto('map')
  await ready(page)

  await openCity(page, 'LIS', 'Lisbon')
  await page.getByTestId('map-city-tabs').getByText('Town Hall', { exact: true }).click()
  await expect(page.getByTestId('townhall-influence')).toBeVisible({ timeout: 30_000 })
  await expect(page.getByTestId('townhall-influence-you')).toContainText('0')
  // 0147: the mayor is the Portuguese merchant who gave; you sail for Portugal, which holds Lisbon
  await expect(page.getByTestId('townhall-mayor')).toContainText(lit.mayor)
  await expect(page.getByTestId('townhall-your-tax')).toContainText('half')
  // 0146: lit, the Town Hall says when the daily count next runs
  await expect(page.getByTestId('townhall-next-count')).toContainText('Next count')
  await page.getByTestId('townhall-donate').click()
  await expect(page.getByTestId('townhall-donate-points')).toBeVisible({ timeout: 30_000 })
  await page.getByTestId('townhall-donate-send').click()
  await expect(page.getByTestId('townhall-donate-tray')).toHaveCount(0, { timeout: 30_000 })
  await expect(page.getByTestId('townhall-given-today')).toContainText('given today', { timeout: 30_000 })
  await expect(page.getByTestId('townhall-influence-share').filter({ hasText: 'Portugal' })).toHaveCount(1, { timeout: 30_000 })
})

test('0275 (owner row 173): the city History tab folds the weeks — the current one open with the served total', async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  // The same fixture as the Town Hall board: a merchant invested ten shares of Porto's docks through
  // the one door, which lands her in THIS week's giving book — the History tab's current week.
  const world = await townHallWorld()
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: world.body, contentType: 'application/gzip' }))
  await page.setViewportSize(PHONE)
  await page.goto('map')
  await ready(page)

  await openCity(page, CITY, 'Porto')
  await page.getByTestId('map-city-tabs').getByText('History', { exact: true }).click()
  await expect(page.getByTestId('map-city-history')).toBeVisible({ timeout: 30_000 })
  // One fold per week, the current week FIRST and OPEN: its label and the served total.
  const weeks = page.getByTestId('city-history-week')
  await expect(weeks).toHaveCount(9) // the current week and the past eight
  const current = weeks.first()
  await expect(current).toContainText('This week')
  await expect(current).toContainText('given')
  await expect(current.getByTestId('city-history-investor').filter({ hasText: world.investor })).toHaveCount(1)
  await expect(current.getByTestId('city-history-investor').filter({ hasText: world.investor })).toContainText('Merchant')
  // The week before this one is folded shut and serves nothing — the fixture world gave nothing then.
  await expect(weeks.nth(1)).toContainText('Last week')
  await expect(weeks.nth(1).getByTestId('city-history-nobody')).toHaveCount(0) // folded: the muted line is inside the fold
  await weeks.nth(1).click()
  await expect(weeks.nth(1).getByTestId('city-history-nobody')).toHaveCount(1)
})
