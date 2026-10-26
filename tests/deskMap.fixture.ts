// A CITY PRESSED ON THE DESK'S MINI MAP (owner row 218) — the way a player presses it: on the harbour's mark,
// through the chart's own tap (the picture takes no pointer; the surface under it does, and THE map tab's hit test
// answers). Never an element click.
import { expect, type Locator, type Page } from '@playwright/test'

export async function pressCity(page: Page, map: Locator, code: string): Promise<void> {
  const mark = map.locator(`[data-port-code="${code}"]`).first()
  await expect(mark).toBeAttached({ timeout: 60_000 })
  await mark.evaluate((e) => e.scrollIntoView({ block: 'center' }))
  const box = (await mark.boundingBox())!
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
}
