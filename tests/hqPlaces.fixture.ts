import type { Page } from '@playwright/test'

// HQ'S PLACES STAND UNDER THE COMMAND BOARD (owner, 2026-11-23: "build the HQ board"; docs/design/hq-command-2026-11-23.md).
//
// The board is the first thing on HQ, and the buildings, the doors and the open place stand under it, one scroll down. The frame laws
// (a press on a place moves no frame, the doors stand whole on the glass) are about the places as the player presses them: scrolled
// to, the title pinned. A press on a place below the glass used to be read from the page's top, so the browser's own scroll to the
// pressed control was counted as the frame moving. `toPlaces` brings the places' row up under the pinned title first, once the
// page's reads have landed (the board grows as they do), and the laws then read what a press changes and nothing else.

/** Scroll HQ's sheet so the places' row stands just under the pinned title. Idempotent; a page too short to scroll stays put. */
export async function toPlaces(page: Page): Promise<void> {
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
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
}
