// THROWAWAY — the corrected browser ARRIVAL proof. Drive 1's poll matched "Open water" on the
// Port tab, which reads the DESTINATION's anchorage while she is still at sea (an honest screen,
// a wrong signal). The arrival signal here is the anchorage's "At anchor" card actually LISTING
// her — the "holding station" row — which exists only once the server has docked her at the place.
import { chromium } from '@playwright/test'

const BASE = 'http://localhost:5931/byeharu-voyage/'
const SHOTS = String.raw`C:\Users\gkwng\AppData\Local\Temp\claude\C--Windows-System32\eccf5855-1f56-4703-b874-ac25ab8aee95\scratchpad`
const shot = (page, name) => page.screenshot({ path: `${SHOTS}\\${name}`, fullPage: false })
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a)

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 390, height: 844 } })
page.setDefaultTimeout(30_000)

await page.goto(BASE)
await page.waitForFunction(
  () => !/Opening the world/i.test(document.body.innerText) && document.querySelectorAll('.animate-pulse').length === 0,
  undefined, { timeout: 180_000 },
)
if (await page.getByText('Sign the book').first().isVisible().catch(() => false)) {
  await page.locator('#house-name').fill('Casa da Chegada')
  await page.getByRole('button', { name: 'Sign the book' }).click()
}
await page.waitForFunction(() => {
  const el = document.querySelector('[data-testid="purse"]')
  return el && !el.textContent.includes('—')
}, undefined, { timeout: 120_000 })
log('world open; purse', (await page.locator('[data-testid="purse"]').textContent()).trim())

await page.locator('[data-testid="nav-command"]').click()
await page.waitForTimeout(1500)
await page.getByRole('button', { name: /^PROVISION/ }).first().click()
await page.waitForTimeout(800)
await page.getByRole('button', { name: /FULL/ }).first().click().catch(() => {})
await page.waitForTimeout(800)
const issue1 = page.getByRole('button', { name: 'Issue this order' })
if (await issue1.isVisible().catch(() => false)) { await issue1.click(); await page.waitForTimeout(2500) }
log('provisioned')
await page.getByRole('button', { name: /^SAIL/ }).first().click()
await page.waitForTimeout(1000)
await page.getByPlaceholder('Filter ports').fill('Cape St Vincent')
await page.waitForTimeout(600)
await page.getByRole('button', { name: /Cape St Vincent/ }).first().click()
await page.waitForTimeout(1200)
await page.getByRole('button', { name: 'Issue this order' }).click()
await page.waitForTimeout(3000)
log('SAIL TO CSV issued — waiting for the real arrival (holding station row)')

let arrived = false
for (let i = 0; i < 30 && !arrived; i++) {
  await page.waitForTimeout(15_000)
  await page.locator('[data-testid="nav-port"]').click()
  await page.waitForTimeout(3000)
  arrived = await page.getByText('holding station').first().isVisible().catch(() => false)
  const gone = await page.getByText('None of your hulls are lying here').first().isVisible().catch(() => false)
  log(`  poll ${i + 1}: ${arrived ? 'SHE LIES AT THE PLACE' : gone ? 'anchorage read from a distance — still at sea' : 'at sea'}`)
}
if (!arrived) throw new Error('no arrival within the window')
await shot(page, 'port-anchorage-arrived.png')
log('shot: port-anchorage-arrived.png — the At anchor card lists her')

await page.locator('[data-testid="nav-ledger"]').click()
await page.waitForTimeout(3000)
const landfall = await page.getByText(/We raised Cape St Vincent/).first().isVisible().catch(() => false)
log('ledger shows "We raised Cape St Vincent…":', landfall)
if (landfall) {
  await page.getByText(/We raised Cape St Vincent/).first().scrollIntoViewIfNeeded().catch(() => {})
  await page.waitForTimeout(400)
}
await shot(page, 'ledger-landfall-arrived.png')

// The map, lying at the place: her marker at the sea place, lozenge under it.
await page.locator('[data-testid="nav-map"]').click()
await page.waitForTimeout(2500)
for (let i = 0; i < 3; i++) { await page.getByRole('button', { name: 'Zoom in' }).click(); await page.waitForTimeout(400) }
await page.waitForTimeout(600)
await shot(page, 'map-at-anchor-sea-place.png')
log(`map lozenges on sheet: ${await page.locator('[data-port-kind="SEA_PLACE"]').count()}`)

await browser.close()
log(landfall && arrived ? 'ARRIVAL PROOF COMPLETE' : 'ARRIVAL ONLY — check the ledger shot')
