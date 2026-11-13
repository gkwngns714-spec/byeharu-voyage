import { test, expect } from '@playwright/test'
import { ready, reachable, settled } from './appReady.fixture'
import { serveRoutesOn } from './routesOn.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DRIVE AUDIT, 2026-11-08 — A ROUTE THAT SAILS BY ITSELF, DRIVEN AS THE OWNER WOULD
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/OWNER_REQUESTS.md row 106: *"i want this game to be a simulating based - meaning i set up
// route, trade routes - going back and forth, afk, running all the time"*. route.stopface.spec.ts
// sets a route up and starts it; no browser spec has ever watched a LAP close — the fleet sail out,
// come back and the route count a lap on its own. This one sets the route up the way the owner does
// (the desk's Trade face, two stops), starts it, and then only WATCHES: the row's all-time laps and
// History's own line. The tab plays the arrivals and the lap starts itself (localBackend.ts), and a
// voyage in this world lasts seconds, so a lap that never closes is a finding.

const OUT = 'docs/dev-log/2026-11-08-drive-audit'
const WIDE = { width: 1280, height: 800 }

test.use({ deviceScaleFactor: 2 })

test('Routes: a two-stop route started on the desk closes a lap by itself, and History says so (row 106)', async ({ page, request, baseURL }) => {
  test.setTimeout(900_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveRoutesOn(page)
  await page.setViewportSize(WIDE)
  await page.goto('command')
  await ready(page)
  await page.getByRole('tablist', { name: 'Desk faces' }).getByRole('tab', { name: 'Goods', exact: true }).click()
  await settled(page.getByTestId('desk-trade'))

  const routeRow = page.getByTestId('route-row')
  await expect(routeRow).toContainText('No route', { timeout: 60_000 })
  await routeRow.click()
  await page.getByTestId('route-setup').click()
  const stops = page.getByTestId('route-editor-stop')
  await expect(stops).toHaveCount(2)
  await page.getByTestId('port-field').click()
  const home = (await stops.nth(0).getByTestId('route-stop-port').innerText()).trim()
  await expect(page.locator('[data-testid="port-chips"][data-reach="measured"]')).toBeVisible({ timeout: 60_000 })
  const chips = page.getByTestId('port-chip')
  await expect(chips.first()).toBeVisible()
  const n = await chips.count()
  let second = ''
  for (let i = 0; i < n; i++) {
    const name = (await chips.nth(i).innerText()).trim()
    if (name !== home) {
      second = name
      await chips.nth(i).click()
      break
    }
  }
  for (let i = 0; i < 2; i++) await expect(stops.nth(i).getByTestId('route-buy-good').first()).toBeVisible({ timeout: 60_000 })
  // buy the first good offered at each stop, so the lap trades (the owner's "going back and forth")
  for (let i = 0; i < 2; i++) {
    await stops.nth(i).getByTestId('route-buy-good').first().evaluate((e) => e.scrollIntoView({ block: 'center' }))
    await stops.nth(i).getByTestId('route-buy-good').first().click()
  }
  console.log(`route: ${home} ⇄ ${second}`)
  await page.getByTestId('route-start').click()
  await expect(page.getByTestId('route-editor')).toHaveCount(0, { timeout: 60_000 })
  await expect(routeRow).toContainText('Route ·', { timeout: 60_000 })
  const laps = page.getByTestId('route-month-laps')
  await expect(laps).toContainText('All time', { timeout: 60_000 })
  console.log(`just started: ${(await laps.innerText()).replace(/\s+/g, ' ')}; queue: ${JSON.stringify(await page.getByTestId('queue-row').allInnerTexts())}`)
  await page.screenshot({ path: `${OUT}/route-started-1280@2x.png` })

  // NOW WATCH. The desk re-reads on the world beat; the row's all-time laps must leave 0 on its own.
  const t0 = Date.now()
  let lapWords = ''
  await expect
    .poll(
      async () => {
        lapWords = (await laps.innerText()).replace(/\s+/g, ' ')
        const m = lapWords.match(/(\d+)/)
        return m ? Number(m[1]) : 0
      },
      { timeout: 420_000, intervals: [5000] },
    )
    .toBeGreaterThanOrEqual(1)
  console.log(`a lap closed after ${Math.round((Date.now() - t0) / 1000)} s: ${lapWords}`)
  await page.screenshot({ path: `${OUT}/route-lapped-1280@2x.png` })

  // History carries the lap
  await page.goto('ledger')
  await ready(page)
  await expect(page.getByTestId('ledger')).toBeVisible({ timeout: 120_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
  const entries = await page.locator('[data-testid="ledger"] [data-row-line], [data-testid="ledger"] [data-testid^="ledger-"]').allInnerTexts()
  const lapLines = entries.filter((e) => /lap|Lap|왕복/.test(e))
  console.log(`History: ${entries.length} lines, ${lapLines.length} about a lap; first: ${[...(lapLines[0] ?? '').replace(/\s+/g, ' ')].slice(0, 120).join('')}`)
  expect(lapLines.length, 'History has no line for the lap').toBeGreaterThanOrEqual(1)
})
