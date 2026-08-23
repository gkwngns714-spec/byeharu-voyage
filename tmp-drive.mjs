// THROWAWAY acceptance drive — sails a real browser session to a sea place, reads the landfall,
// then diverts a passage from the map. Screenshots to the scratchpad. Deleted after the run.
import { chromium } from '@playwright/test'

const BASE = 'http://localhost:5931/byeharu-voyage/'
const SHOTS = String.raw`C:\Users\gkwng\AppData\Local\Temp\claude\C--Windows-System32\eccf5855-1f56-4703-b874-ac25ab8aee95\scratchpad`
const shot = (page, name) => page.screenshot({ path: `${SHOTS}\\${name}`, fullPage: false })
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a)

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 390, height: 844 } })
page.setDefaultTimeout(30_000)

log('opening the world (first boot applies the chain in-browser)…')
await page.goto(BASE)
await page.waitForFunction(
  () => !/Opening the world/i.test(document.body.innerText) && document.querySelectorAll('.animate-pulse').length === 0,
  undefined, { timeout: 180_000 },
)

// Sign the book if this is a fresh browser profile.
if (await page.getByText('Sign the book').first().isVisible().catch(() => false)) {
  log('signing the book…')
  await page.locator('#house-name').fill('Casa das Aguas')
  await page.getByRole('button', { name: 'Sign the book' }).click()
}
await page.waitForFunction(() => {
  const el = document.querySelector('[data-testid="purse"]')
  return el && !el.textContent.includes('—')
}, undefined, { timeout: 120_000 })
log('purse reads:', (await page.locator('[data-testid="purse"]').textContent()).trim())

// ── COMMAND: provision, then the SAIL picker offering a sea place ─────────────────────────────
await page.locator('[data-testid="nav-command"]').click()
await page.waitForTimeout(1500)
// She needs water for the endurance gate (round trip to a sea place): PROVISION FULL first.
await page.getByRole('button', { name: /^PROVISION/ }).first().click()
await page.waitForTimeout(800)
await page.getByRole('button', { name: /FULL/ }).first().click().catch(() => {})
await page.waitForTimeout(800)
const issueBtn = page.getByRole('button', { name: 'Issue this order' })
if (await issueBtn.isVisible().catch(() => false)) {
  await issueBtn.click()
  await page.waitForTimeout(2500)
  log('provisioned')
}
// Now SAIL.
await page.getByRole('button', { name: /^SAIL/ }).first().click()
await page.waitForTimeout(1000)
await page.getByPlaceholder('Filter ports').fill('Cape St Vincent')
await page.waitForTimeout(600)
await shot(page, 'sail-picker-sea-place.png')
log('shot: sail-picker-sea-place.png')
await page.getByRole('button', { name: /Cape St Vincent/ }).first().click()
await page.waitForTimeout(1200)
await shot(page, 'sail-sheet-sea-place.png')
await page.getByRole('button', { name: 'Issue this order' }).click()
await page.waitForTimeout(3000)
log('SAIL issued')

// ── MAP: the passage, and the lozenges on the chart ───────────────────────────────────────────
await page.locator('[data-testid="nav-map"]').click()
await page.waitForTimeout(2500)
await shot(page, 'map-underway.png')
const seaPlaceMarks = await page.locator('[data-port-kind="SEA_PLACE"]').count()
log(`map shows ${seaPlaceMarks} sea-place lozenge(s) at this zoom`)
for (let i = 0; i < 3; i++) { await page.getByRole('button', { name: 'Zoom in' }).click(); await page.waitForTimeout(400) }
await page.waitForTimeout(800)
await shot(page, 'map-iberia-sea-places.png')
log(`zoomed: ${await page.locator('[data-port-kind="SEA_PLACE"]').count()} lozenge(s) on the sheet`)

// ── ARRIVAL: poll the Port tab until she lies at the sea place ────────────────────────────────
log('waiting for the arrival (about 3 real minutes at compression 480)…')
let arrived = false
for (let i = 0; i < 24 && !arrived; i++) {
  await page.waitForTimeout(15_000)
  await page.locator('[data-testid="nav-port"]').click()
  await page.waitForTimeout(2500)
  arrived = await page.getByText('Open water').first().isVisible().catch(() => false)
  log(`  poll ${i + 1}: ${arrived ? 'SHE HAS ARRIVED' : 'still at sea'}`)
}
if (!arrived) throw new Error('she never arrived — the drive cannot claim the acceptance')
await shot(page, 'port-anchorage.png')
log('shot: port-anchorage.png (the sea-place anchorage view)')

// The report line on the Ledger.
await page.locator('[data-testid="nav-ledger"]').click()
await page.waitForTimeout(2500)
const landfall = await page.getByText(/We raised Cape St Vincent/).first().isVisible().catch(() => false)
log(`ledger shows the landfall line: ${landfall}`)
await shot(page, 'ledger-landfall.png')

// ── DIVERT: sail on from the anchorage, then put the helm over from the map ───────────────────
await page.locator('[data-testid="nav-port"]').click()
await page.waitForTimeout(2000)
// The anchorage's own "Sailing on" rows compose the order — take the farthest listed harbour so
// there is water left to divert in.
const sailRow = page.locator('[data-testid], button').filter({ hasText: /^SAIL / }).last()
await sailRow.click()
await page.waitForTimeout(1200)
await page.getByRole('button', { name: 'Issue this order' }).click()
await page.waitForTimeout(3000)
log('sailed on from the anchorage')

await page.locator('[data-testid="nav-map"]').click()
await page.waitForTimeout(2500)
// Select a harbour by tapping the sheet: nearest-wins hit test — try a few points until the
// corner panel offers the helm.
const sea = page.locator('[data-testid="map-sea"]').first()
const box = await sea.boundingBox()
let diverted = false
for (const [fx, fy] of [[0.5, 0.35], [0.35, 0.45], [0.65, 0.3], [0.5, 0.55], [0.3, 0.3]]) {
  await page.mouse.click(box.x + box.width * fx, box.y + box.height * fy)
  await page.waitForTimeout(1200)
  const btn = page.locator('[data-testid="map-divert-button"]')
  if (await btn.isVisible().catch(() => false)) {
    await shot(page, 'map-divert-offer.png')
    await btn.click()
    await page.waitForFunction(() => {
      const t = document.querySelector('[data-testid="map-divert-turned"]')
      const r = document.querySelector('[data-testid="map-divert-refusal"]')
      return !!t || !!r
    }, undefined, { timeout: 20_000 })
    diverted = await page.locator('[data-testid="map-divert-turned"]').isVisible().catch(() => false)
    await shot(page, 'map-divert-turned.png')
    log(`divert from the map: ${diverted ? 'HELM ANSWERED' : 'refused (see map-divert-turned.png)'}`)
    break
  }
}
if (!diverted) log('note: no divert completed from the map taps — see screenshots')

await browser.close()
log('drive complete')
