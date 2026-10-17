import { expect, type Page } from '@playwright/test'

// OPEN ONE CITY'S PANEL ON THE MAP, AND MAKE SURE IT IS THAT CITY (0144). A tap on a harbour's name
// goes to the NEAREST harbour (src/chart/hitTest.ts), and at the opening frame Lisbon's name sits
// close enough to Setúbal that a CI viewport opened Setúbal (PR #151, acceptance 3/3). So the tray's
// own title is read back, and when it names another place the chart is zoomed in at that name —
// the player's gesture — and the name tapped again.
export async function openCityPanel(page: Page, code: string, name: string): Promise<void> {
  const centre = async () => {
    await page.locator(`[data-label-id="port:${code}"]`).first().waitFor({ state: 'attached', timeout: 120_000 })
    const at = await page.evaluate((id) => {
      const e = document.querySelector(`[data-label-id="${id}"]`)
      if (!e) return null
      const r = e.getBoundingClientRect()
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
    }, `port:${code}`)
    if (!at) throw new Error(`${code} is not named on the chart`)
    return at
  }
  for (let attempt = 0; attempt < 4; attempt++) {
    const at = await centre()
    await page.mouse.click(at.x, at.y)
    const title = page.getByTestId('map-place-name')
    await title.first().waitFor({ state: 'visible', timeout: 30_000 }).catch(() => undefined)
    if (((await title.first().textContent().catch(() => '')) ?? '').includes(name)) return
    // another place opened: close it, zoom in at the name, and try again
    await page.keyboard.press('Escape')
    await page.mouse.move(at.x, at.y)
    for (let i = 0; i < 8; i++) {
      await page.mouse.wheel(0, -120)
      await page.waitForTimeout(40)
    }
    await page.waitForTimeout(400)
  }
  await expect(page.getByTestId('map-place-name').first()).toContainText(name)
}
