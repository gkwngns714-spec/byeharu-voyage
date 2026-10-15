import { test, expect, type Page } from '@playwright/test'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile } from '../src/lib/db/worldImage'
import { PHONE, reachable, ready } from './appReady.fixture'

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

let image: { body: Buffer; investor: string } | null = null

async function townHallWorld(): Promise<{ body: Buffer; investor: string }> {
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
    const who = await pg.query<{ name: string; r: { ok: boolean } }>(
      `select pl.company_name as name,
              public.invest_for(pl.id, (select id from public.ports where code = $1), 'docks', 10) as r
         from public.npc_houses h join public.players pl on pl.id = h.player_id
        order by h.roster_ord limit 1`,
      [CITY],
    )
    if (who.rows.length !== 1 || !who.rows[0].r.ok) throw new Error(`no merchant could invest at ${CITY}`)
    image = { body: Buffer.from(await (await pg.dumpDataDir('gzip')).arrayBuffer()), investor: who.rows[0].name }
  } finally {
    await pg.close()
  }
  return image
}

async function openCity(page: Page, code: string): Promise<void> {
  const label = await page.evaluate((id) => {
    const e = document.querySelector(`[data-label-id="${id}"]`)
    if (!e) return null
    const r = e.getBoundingClientRect()
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
  }, `port:${code}`)
  if (!label) throw new Error(`${code} is not named on the opening frame`)
  await page.mouse.click(label.x, label.y)
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

  await openCity(page, CITY)
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
})
