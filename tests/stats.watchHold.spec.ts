import { test, expect } from '@playwright/test'
import { PHONE, WORLD_BOOT_MS, reachable } from './appReady.fixture'

// THE WATCH CARD HOLDS ITS PLACE WHILE ITS READ IS OUT (the owner's law: nothing re-flows under the player; found 2026-11-12 as
// the intermittent red of tests/news.dotSize.spec.ts, `stats world @390: pressing "4 news" moved its chart: y 255 → y 611`).
// The cause: on Stats > Overview the Economy Watch card stands directly above the world's chart and its figures ride the live
// read (world.stats_now), a read of its own that lands AFTER the face's (one PGlite queue). The card drew nothing until it
// landed, and then 345 px of card (and the 12-px gap) pushed the chart down a phone, and across a column at 1,280.
// HOW THE READ IS HELD: a local world has no network seam, but every ask prints one `[rpc]` debug line BEFORE it is made
// (src/lib/rpc/backend.ts), and an ask that throws is a failed ask the live read simply asks again a second later
// (src/live/liveRead.ts). So the page's `console.debug` throws on `world.stats_now` for as long as the spec holds it: the face's
// own read lands, the chart is drawn, the watch read is out — for certain, not by a race — and then it is let go.
// A per-frame sampler records where the chart's card stands, and what the watch card holds, on EVERY frame from before the read
// lands until after: the chart's box must be one box throughout, and so must the watch card's. Names Watch.tsx and Overview.tsx.

const WIDE = { width: 1280, height: 800 }
type Frame = { loaded: string; chart: string; watch: string }

for (const vp of [PHONE, WIDE]) {
  test(`Overview: the watch read landing late moves nothing at ${vp.width}px`, async ({ page, request, baseURL }) => {
    test.setTimeout(420_000)
    expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`).toBe(true)
    await page.addInitScript(() => {
      const w = window as unknown as { __holdNow: boolean }
      w.__holdNow = true
      const debug = console.debug.bind(console)
      console.debug = (...args: unknown[]) => {
        if (w.__holdNow && args[0] === '[rpc]' && typeof args[1] === 'string' && args[1].startsWith('world.stats_now')) throw new Error('held by the spec')
        debug(...args)
      }
    })
    await page.setViewportSize(vp)
    await page.goto('stats')
    // the face's own read has landed and the world's chart is drawn; the watch read is still out
    const chart = page.getByTestId('stats-chart-world')
    await expect(chart.locator('[role="img"]').first()).toBeVisible({ timeout: WORLD_BOOT_MS })
    const watch = page.getByTestId('stats-watch')
    await expect(watch, 'the watch card does not hold its place while its read is out').toBeVisible()
    await expect(watch.locator('[data-watch-loaded]')).toHaveAttribute('data-watch-loaded', 'false')
    await page.evaluate(() => {
      const log: Frame[] = []
      type Frame = { loaded: string; chart: string; watch: string }
      ;(window as unknown as { __frames: Frame[] }).__frames = log
      const box = (id: string) => {
        const el = document.querySelector(`[data-testid="${id}"]`)
        if (!el) return 'absent'
        const r = el.getBoundingClientRect()
        return `x ${Math.round(r.left + window.scrollX)} y ${Math.round(r.top + window.scrollY)} w ${Math.round(r.width)} h ${Math.round(r.height)}`
      }
      const tick = () => {
        const loaded = document.querySelector('[data-testid="stats-watch"] [data-watch-loaded]')?.getAttribute('data-watch-loaded') ?? 'absent'
        log.push({ loaded, chart: box('stats-chart-world'), watch: box('stats-watch') })
        requestAnimationFrame(tick)
      }
      requestAnimationFrame(tick)
    })
    await page.waitForTimeout(300)
    await page.evaluate(() => {
      ;(window as unknown as { __holdNow: boolean }).__holdNow = false
    })
    // asked again within a second (LIVE_READ_MS), and this time it lands
    await expect(watch.locator('[data-watch-loaded]')).toHaveAttribute('data-watch-loaded', 'true', { timeout: 60_000 })
    await expect(watch).toContainText(/New money/)
    await page.evaluate(() => new Promise<void>((r) => requestAnimationFrame(() => requestAnimationFrame(() => r()))))
    const frames = await page.evaluate(() => (window as unknown as { __frames: Frame[] }).__frames)
    const turns = frames.filter((f, i) => i === 0 || JSON.stringify(f) !== JSON.stringify(frames[i - 1]))
    const said = JSON.stringify(turns)
    // the sampler saw both sides of the landing, or the law below is about nothing
    expect(frames.some((f) => f.loaded === 'false'), `no frame with the read out: ${said}`).toBe(true)
    expect(frames.some((f) => f.loaded === 'true'), `no frame with the read landed: ${said}`).toBe(true)
    expect([...new Set(frames.map((f) => f.chart))], `the world's chart moved when the watch read landed @${vp.width}: ${said}`).toHaveLength(1)
    expect([...new Set(frames.map((f) => f.watch))], `the watch card changed its box when its read landed @${vp.width}: ${said}`).toHaveLength(1)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), `the page scrolls sideways @${vp.width}`).toBe(true)
  })
}
