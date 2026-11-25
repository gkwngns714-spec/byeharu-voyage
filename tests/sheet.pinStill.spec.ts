import { test, expect } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'

// THE TITLE BAR PINS AND LETS GO WITHOUT MOVING THE PAGE (2026-11-25, the owner's law: nothing on a page moves by itself).
//
// PR #863's run failed tests/news.chart.spec.ts:147 at 1280: after a press on the News face's "My cities" tab the world's headline was
// still listed. The feed was never asked again and the trace shows why: "World" still selected, "My cities" only FOCUSED. The press
// was lost. The spec had pressed Older, so the sheet stood 2,684 px down with its title pinned as a small bar; the press scrolled the
// tab into view, the sheet came back to its top, the title let go and grew back to its large size (22 to 44 px on a page), and every
// line under it went down by that much between the pointer going down on the tab and coming up. A player meets the same thing on
// every return to the top of a long page: the page jumps down under the finger.
//
// The cause is the header changing its height in the page's flow. It keeps its room now (src/components/ui/Sheet.tsx: a spacer under
// the pinned bar is what the bar gave up), so pinning and letting go move nothing. Here the sheet is sent down and back, and the tab
// is read at once and again after the title has let go.

for (const glass of [
  { width: 1280, height: 800 },
  { width: 390, height: 844 },
]) {
  test(`Stats News at ${glass.width}: back at the top the title lets go and the filter tabs stay where they were; the press on My cities lands`, async ({ page, request, baseURL }) => {
    test.setTimeout(480_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(glass)
    await page.goto('stats?face=overview')
    await ready(page)
    await page.getByRole('tablist').first().getByRole('tab', { name: 'News', exact: true }).click()
    const face = page.getByTestId('stats-news')
    await expect(face.getByTestId('news-item').first()).toBeVisible({ timeout: 60_000 })

    // DOWN: the sheet scrolled to its foot, the title a pinned bar
    const header = page.getByTestId('stats').getByTestId('sheet-header')
    const read = () =>
      page.evaluate(() => {
        const sheet = document.querySelector('[data-testid="stats"]') as HTMLElement
        const tab = [...document.querySelectorAll('[data-testid="stats-news"] [role="tab"]')].find((b) => b.textContent === 'My cities') as HTMLElement
        const first = document.querySelector('[data-testid="stats-news"] [data-testid="news-item"]') as HTMLElement
        return { scroll: sheet.scrollTop, room: sheet.scrollHeight, tab: Math.round(tab.getBoundingClientRect().top), first: Math.round(first.getBoundingClientRect().top) }
      })
    const atRest = await read()
    await page.evaluate(() => {
      const sheet = document.querySelector('[data-testid="stats"]') as HTMLElement
      sheet.scrollTop = sheet.scrollHeight
    })
    await expect(header, 'the page is too short to pin its title: this spec proves nothing').toHaveAttribute('data-pinned', 'true')
    const down = await read()
    expect(down.room, 'pinning the title changed how tall the page is').toBe(atRest.room)

    // BACK TO THE TOP: read the tab in the same breath as the scroll (before the title has let go), then after it has
    const atOnce = await page.evaluate(() => {
      const sheet = document.querySelector('[data-testid="stats"]') as HTMLElement
      sheet.scrollTop = 0
      const tab = [...document.querySelectorAll('[data-testid="stats-news"] [role="tab"]')].find((b) => b.textContent === 'My cities') as HTMLElement
      return Math.round(tab.getBoundingClientRect().top)
    })
    await expect(header).toHaveAttribute('data-pinned', 'false')
    const settled = await read()
    expect(settled.tab, 'the filter tabs moved when the title let go at the top of the page').toBe(atOnce)
    expect(settled.tab, 'the page is not where it was before it was scrolled').toBe(atRest.tab)
    expect(settled.first).toBe(atRest.first)

    // AND THE PRESS THAT WAS LOST: from the foot of the page, one press on My cities selects it
    await page.evaluate(() => {
      const sheet = document.querySelector('[data-testid="stats"]') as HTMLElement
      sheet.scrollTop = sheet.scrollHeight
    })
    await expect(header).toHaveAttribute('data-pinned', 'true')
    const mine = face.getByRole('tab', { name: 'My cities', exact: true })
    await mine.click()
    await expect(mine).toHaveAttribute('aria-selected', 'true')
  })
}
