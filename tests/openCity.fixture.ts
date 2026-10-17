import { expect, type Page } from '@playwright/test'

// OPEN ONE CITY'S PANEL ON THE MAP, AND MAKE SURE IT IS THAT CITY (0144). A tap goes to the NEAREST
// harbour (src/chart/hitTest.ts), and a tap on a harbour's NAME lands beside its mark: at the CI
// viewport the tap on Lisbon's name opened Setúbal (PR #151, acceptance 3/3). So the tap is on the
// harbour's MARK (`[data-port-code]`, the copy drawn inside the chart) — the place itself, where
// hitTest's one rule also gives the harbour over your own fleet lying in it — and the tray's title
// is read back.
export async function openCityPanel(page: Page, code: string, name: string): Promise<void> {
  await page.locator(`[data-testid="map-ports"] [data-port-code="${code}"]`).first().waitFor({ state: 'attached', timeout: 120_000 })
  const at = await page.evaluate((c) => {
    const chart = document.querySelector('[data-testid="map-chart"]')?.getBoundingClientRect()
    if (!chart) return null
    for (const e of document.querySelectorAll(`[data-testid="map-ports"] [data-port-code="${c}"]`)) {
      const r = e.getBoundingClientRect()
      const x = r.x + r.width / 2
      const y = r.y + r.height / 2
      if (r.width > 0 && x > chart.left && x < chart.right && y > chart.top && y < chart.bottom) return { x, y }
    }
    return null
  }, code)
  if (!at) throw new Error(`${code} has no mark inside the chart`)
  await page.mouse.click(at.x, at.y)
  await expect(page.getByTestId('map-place-name').first()).toContainText(name, { timeout: 30_000 })
}
