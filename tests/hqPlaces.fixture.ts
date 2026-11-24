import type { Page } from '@playwright/test'

// HQ'S PLACES STAND UNDER THE COMMAND BOARD (owner, 2026-11-23: "build the HQ board"; docs/design/hq-command-2026-11-23.md).
//
// The board is the first thing on HQ, and the buildings, the doors and the open place stand under it, one scroll down. The frame laws
// (a press on a place moves no frame, the doors stand whole on the glass) are about the places as the player presses them: scrolled
// to, the title pinned. A press on a place below the glass used to be read from the page's top, so the browser's own scroll to the
// pressed control was counted as the frame moving. `toPlaces` brings the places' row up under the pinned title first, once the
// page's reads have landed (the board grows as they do), and the laws then read what a press changes and nothing else.

/** Scroll HQ's sheet so the places' row stands just under the pinned title. Idempotent; a page too short to scroll that far stands at
 *  its foot. It waits for the page to SETTLE first (2026-11-24, S1; #850's shard 4/6: the scroll was made while the board above was
 *  still growing and was lost, and the next law read a 510-px scroll to a row as the frame moving): no loading mark, and the sheet's
 *  height the same across a second. And it FAILS, never goes on silently, when the page will not settle or the scroll did not take. */
export async function toPlaces(page: Page): Promise<void> {
  await page.waitForFunction(
    () => document.querySelectorAll('.animate-pulse').length === 0 && document.querySelector('[data-testid="city-load-host"]') === null,
    undefined,
    { timeout: 120_000 },
  )
  const height = () =>
    page.evaluate(() => (document.querySelector('[data-testid="city-buildings"]')?.closest('[data-sheet]') as HTMLElement | null)?.scrollHeight ?? -1)
  let last = await height()
  for (let still = 0, tries = 0; still < 2; tries++) {
    if (tries > 120) throw new Error(`toPlaces: HQ's page never settled (its height still moving: ${last} px)`)
    await page.waitForTimeout(500)
    const now = await height()
    still = now === last ? still + 1 : 0
    last = now
  }
  // three passes: the title pins (and shrinks) on the first scroll, which moves the row by its own change
  for (let i = 0; i < 3; i++) {
    await page.evaluate(() => {
      const places = document.querySelector('[data-testid="city-buildings"]')
      const sheet = places?.closest('[data-sheet]') as HTMLElement | null
      if (!places || !sheet) return
      let bar: HTMLElement | null = document.querySelector('[data-testid="city-header"]')
      while (bar && bar !== sheet && getComputedStyle(bar).position !== 'sticky') bar = bar.parentElement
      const under = bar && bar !== sheet ? bar.getBoundingClientRect().bottom : sheet.getBoundingClientRect().top
      sheet.scrollTop += Math.round(places.getBoundingClientRect().top - under - 8)
    })
    await page.waitForTimeout(250)
  }
  // THE SCROLL TOOK: the row stands under the title, or the page is at its foot (too short to bring it higher)
  const where = await page.evaluate(() => {
    const places = document.querySelector('[data-testid="city-buildings"]')
    const sheet = places?.closest('[data-sheet]') as HTMLElement | null
    if (!places || !sheet) return { ok: false, why: 'no places row or no sheet' }
    let bar: HTMLElement | null = document.querySelector('[data-testid="city-header"]')
    while (bar && bar !== sheet && getComputedStyle(bar).position !== 'sticky') bar = bar.parentElement
    const under = bar && bar !== sheet ? bar.getBoundingClientRect().bottom : sheet.getBoundingClientRect().top
    const off = Math.round(places.getBoundingClientRect().top - under - 8)
    const atFoot = sheet.scrollTop >= sheet.scrollHeight - sheet.clientHeight - 1
    return { ok: Math.abs(off) <= 2 || (off > 0 && atFoot), why: `row ${off} px from its place, scrollTop ${Math.round(sheet.scrollTop)} of ${sheet.scrollHeight - sheet.clientHeight}` }
  })
  if (!where.ok) throw new Error(`toPlaces: the scroll to HQ's places did not take (${where.why})`)
}
