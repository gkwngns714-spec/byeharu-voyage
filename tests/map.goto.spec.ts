import { test, expect, type Page } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// GO TO, DRIVEN (src/chart/goTo.ts) — owner, 2026-10-15: *"if i press a city, it will point me to
// that location with a marker"*.
//
// A city's name in its own panel is a link. The chart is first dragged so the city is somewhere
// else on the glass; pressing the name must glide the view back until the city stands in the
// middle of the CLEAR glass (beside the side panel on a wide screen; the whole glass on a phone,
// where the panel folds out of the way), with the marker ringing it. The marker is placed from the
// same viewBox the chart draws with, so "the marker is at the middle" is "the view is centred on
// the city" — measured off the DOM, never off a prop.
//
// Run it: npm run build && npm run preview, then `npx playwright test map.goto.spec.ts`.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const WIDE = { width: 1280, height: 800 }

/** Press a harbour's name somewhere in the left part of the glass; returns its code. */
async function openACity(page: Page, maxX: number): Promise<string> {
  await page.locator('[data-label-id^="port:"]').first().waitFor({ state: 'attached', timeout: 120_000 })
  const pick = await page.evaluate((limit) => {
    const glass = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
    for (const e of document.querySelectorAll('[data-label-id^="port:"]')) {
      const r = e.getBoundingClientRect()
      const x = r.x + r.width / 2
      const y = r.y + r.height / 2
      if (r.width > 0 && x > glass.x + 80 && x < limit && y > glass.y + 120 && y < glass.bottom - 140) {
        return { id: e.getAttribute('data-label-id')!, x, y }
      }
    }
    return null
  }, maxX)
  if (!pick) throw new Error('no harbour named in the open part of the opening frame')
  await page.mouse.click(pick.x, pick.y)
  await expect(page.getByTestId('map-place-name')).toBeVisible()
  return pick.id.slice('port:'.length)
}

async function drag(page: Page, from: { x: number; y: number }, by: { x: number; y: number }) {
  await page.mouse.move(from.x, from.y)
  await page.mouse.down()
  for (let i = 1; i <= 10; i++) await page.mouse.move(from.x + (by.x * i) / 10, from.y + (by.y * i) / 10)
  await page.mouse.up()
}

/** Waits, in the page and frame by frame, for the marker to stand within 8 px of `target` —
 *  inside its ring time (GOTO_MARK_MS, 4 s); a marker that never arrives fails with what it saw. */
async function settlesAt(page: Page, target: { x: number; y: number }) {
  const seen: string[] = []
  const ok = await page
    .waitForFunction(
      ({ x, y }) => {
        const w = window as unknown as { __goto?: string[] }
        w.__goto ??= []
        const e = document.querySelector('[data-testid="map-goto-marker"]')
        if (!e) {
          w.__goto.push('none')
          return false
        }
        const r = e.getBoundingClientRect()
        w.__goto.push(`${r.x.toFixed(0)},${r.y.toFixed(0)}`)
        return Math.hypot(r.x - x, r.y - y) < 8
      },
      target,
      { polling: 'raf', timeout: 3500 },
    )
    .then(() => true)
    .catch(() => false)
  if (!ok) seen.push(...(await page.evaluate(() => (window as unknown as { __goto?: string[] }).__goto ?? [])))
  expect(ok, `the marker settles on ${target.x},${target.y}; saw ${seen.filter((v, i) => i % 10 === 0).join(' ')}`).toBe(true)
}

test.describe('a place named in a panel is a link that brings the chart to it', () => {
  test.beforeEach(async ({ request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  })

  test('wide: the city glides to the middle of the glass beside the panel, ringed', async ({ page }) => {
    test.setTimeout(600_000)
    await page.setViewportSize(WIDE)
    await page.goto('map')
    await ready(page)

    await openACity(page, WIDE.width - 120)
    // The harbour the tap opened (a dot beside a name may win the tap — hitTest.ts), read off the
    // panel's own link.
    const link = page.getByTestId('map-place-name').getByTestId('goto-link')
    const code = ((await link.getAttribute('data-goto')) ?? '').replace(/^port:/, '')
    expect(code).not.toBe('')
    const glass = await page.getByTestId('map-chart').boundingBox()
    if (!glass) throw new Error('no glass')

    // Move the city away (likely under the panel now): drag the open part of the chart.
    await drag(page, { x: glass.x + 450, y: glass.y + glass.height / 2 }, { x: -300, y: -160 })
    // The panel's edge read once its slide-in has finished (it animates in from the right).
    await page.waitForTimeout(500)
    const panel = await page.getByTestId('map-detail-tray').boundingBox()
    if (!panel) throw new Error('no panel')
    const target = { x: glass.x + (panel.x - glass.x) / 2, y: glass.y + glass.height / 2 }
    // NOT VACUOUS: before the press the city is nowhere near where the go-to must put it.
    const name = page.locator(`[data-label-id="port:${code}"]`).first()
    const before = (await name.count()) > 0 ? await name.boundingBox({ timeout: 1000 }) : null
    if (before) expect(Math.hypot(before.x - target.x, before.y - target.y)).toBeGreaterThan(150)

    await link.click()
    // The panel the link was in stays open — a go-to selects and closes nothing.
    await expect(page.getByTestId('map-detail-tray')).toBeVisible()
    await settlesAt(page, target)
    const at = target
    // And it rings the city itself: her name is drawn beside the marker.
    const label = await name.boundingBox({ timeout: 5000 })
    if (!label) throw new Error(`${code} is not named after the go-to`)
    expect(Math.hypot(label.x + label.width / 2 - at.x, label.y + label.height / 2 - at.y)).toBeLessThan(160)
  })

  test('phone: the panel folds out of the way, the city is centred, the edge tab brings the panel back', async ({ page }) => {
    test.setTimeout(600_000)
    await page.setViewportSize(PHONE)
    await page.goto('map')
    await ready(page)

    await openACity(page, PHONE.width - 40)
    const glass = await page.getByTestId('map-chart').boundingBox()
    if (!glass) throw new Error('no glass')

    await page.getByTestId('map-place-name').getByTestId('goto-link').click()
    // Read inside the marker's ring time first, then the fold.
    await settlesAt(page, { x: glass.x + glass.width / 2, y: glass.y + glass.height / 2 })
    await expect(page.getByTestId('map-unfold')).toBeVisible()
    await expect(page.getByTestId('map-detail-tray')).toBeHidden()

    await page.getByTestId('map-unfold').click()
    await expect(page.getByTestId('map-detail-tray')).toBeVisible()
    await expect(page.getByTestId('map-unfold')).toHaveCount(0)
  })
})
